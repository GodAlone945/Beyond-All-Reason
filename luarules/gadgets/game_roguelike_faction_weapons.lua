--------------------------------------------------------------------------------
-- [SYNCED 权威模块：Roguelike 三阵营专属武器机制]
--
-- UnitTweaks 提供零伤害的视觉 WeaponDef 和稳定 shop ID；本 Gadget 在武器实际
-- 开火时按 catalog 结算扇区、多目标、贯穿、燃烧、升温和减速。伤害仍通过
-- Spring.AddUnitDamage 带原 WeaponDef 与指挥官 attackerID，复用升级伤害倍率。
-- 只在 roguelike_mode 生效；LuaUI 不能决定目标、伤害、DoT 或状态时长。
--------------------------------------------------------------------------------
local gadget = gadget ---@type Gadget

function gadget:GetInfo()
	return {
		name = "Roguelike Faction Weapons",
		desc = "Synced combat behaviors for faction-exclusive Roguelike commander weapons",
		author = "Codex",
		date = "2026",
		license = "GNU GPL, v2 or later",
		layer = 0,
		enabled = true,
	}
end

local option = Spring.GetModOptions().roguelike_mode
if option ~= true and option ~= 1 and option ~= "1" and option ~= "true" then return false end
if not gadgetHandler:IsSyncedCode() then return end

local catalog = VFS.Include("unitbasedefs/roguelike_weapon_catalog.lua")
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitTeam = Spring.GetUnitTeam
local spGetUnitPosition = Spring.GetUnitPosition
local spGetUnitHealth = Spring.GetUnitHealth
local spGetUnitWeaponTarget = Spring.GetUnitWeaponTarget
local spGetProjectileTarget = Spring.GetProjectileTarget
local spGetUnitRulesParam = Spring.GetUnitRulesParam
local spGetUnitsInCylinder = Spring.GetUnitsInCylinder
local spAreTeamsAllied = Spring.AreTeamsAllied
local spAddUnitDamage = Spring.AddUnitDamage
local spGetGameFrame = Spring.GetGameFrame
local spGetUnitVelocity = Spring.GetUnitVelocity
local spAddUnitImpulse = Spring.AddUnitImpulse
local spValidUnitID = Spring.ValidUnitID
local gameSpeed = Game.gameSpeed
local max = math.max
local min = math.min
local sqrt = math.sqrt
local cos = math.cos
local sin = math.sin
local pi = math.pi
local floor = math.floor
local projectileTargetGround = string.byte("g")
local projectileTargetUnit = string.byte("u")

local byWeaponDefID = {}
local configByID = {}
for _, faction in pairs(catalog.factions) do
	for _, item in ipairs(faction.weapons) do
		configByID[item.id] = item
	end
end
for weaponDefID, weaponDef in pairs(WeaponDefs) do
	local customParams = weaponDef.customParams or {}
	local itemID = customParams.roguelike_custom_weapon
	if itemID and configByID[itemID] then
		byWeaponDefID[weaponDefID] = configByID[itemID]
	end
end

local commanderIDs = {}
local burnStates = {}
local rampStates = {}
local slowStates = {}
local lastConeEffectFrame = {}
local weaponProjectiles = {}
local lastHiveVolleyFrame = {}
local targetTypeUnit = 1
local fireRamp
local activeEffectContext

local function getWeaponLevel(ownerID, itemID)
	return ownerID and (spGetUnitRulesParam(ownerID, "roguelike_shop_" .. itemID .. "_level") or 0) or 0
end

local function levelConfig(base, level)
	local result = {}
	for key, value in pairs(base) do result[key] = type(value) == "table" and table.copy(value) or value end
	for levelIndex = 1, min(max(0, level - 1), #(base.levels or {})) do
		for key, value in pairs(base.levels[levelIndex]) do
			result[key] = type(value) == "table" and table.copy(value) or value
		end
	end
	return result
end

local function isEnemy(unitID, teamID)
	if not teamID then return false end
	if not spValidUnitID(unitID) then return false end
	local otherTeam = spGetUnitTeam(unitID)
	if not otherTeam or spAreTeamsAllied(teamID, otherTeam) then return false end
	local health = spGetUnitHealth(unitID)
	return health and health > 0
end

local function targetAllowed(unitID, teamID, targetClass)
	if not isEnemy(unitID, teamID) then return false end
	local unitDef = UnitDefs[spGetUnitDefID(unitID)]
	if not unitDef then return false end
	local isAir = unitDef.isAirUnit or unitDef.canFly
	if targetClass == "surface" and isAir then return false end
	if targetClass == "air" and not isAir then return false end
	return true
end

local function distanceSquared(x1, z1, x2, z2)
	local dx, dz = x2 - x1, z2 - z1
	return dx * dx + dz * dz
end

local function collectTargets(ownerID, teamID, centerX, centerZ, radius, targetClass, preferredID)
	local found = {}
	local maxRadiusSquared = radius * radius
	for _, targetID in ipairs(spGetUnitsInCylinder(centerX, centerZ, radius) or {}) do
		if targetAllowed(targetID, teamID, targetClass) then
			local x, _, z = spGetUnitPosition(targetID)
			if x then
				local d2 = distanceSquared(centerX, centerZ, x, z)
				if d2 <= maxRadiusSquared then
					found[#found + 1] = { id = targetID, x = x, z = z, d2 = d2 }
				end
			end
		end
	end
	table.sort(found, function(a, b)
		local aPreferred = a.id == preferredID
		local bPreferred = b.id == preferredID
		if aPreferred ~= bPreferred then return aPreferred end
		if a.d2 == b.d2 then return a.id < b.id end
		return a.d2 < b.d2
	end)
	return found
end

local function dealDamage(targetID, ownerID, weaponDefID, damage, damageKind)
	if damage > 0 and spValidUnitID(targetID) then
		local hitX, _, hitZ = spGetUnitPosition(targetID)
		local context = activeEffectContext
		local effectBus = GG.RoguelikeWeaponEffects
		if context and effectBus and effectBus.RegisterHit then
			effectBus.RegisterHit(ownerID, spGetUnitTeam(ownerID), weaponDefID, targetID,
				hitX, hitZ, damage, context.eventID, context.effects, context.procCoefficient)
		end
		local rogue = GG.Roguelike
		if rogue and rogue.RegisterDamageHealContext then
			rogue.RegisterDamageHealContext(targetID, ownerID, damageKind or "direct", context and context.eventID)
		end
		spAddUnitDamage(targetID, damage, 0, ownerID, weaponDefID)
		if context and effectBus and effectBus.OnHit then
			effectBus.OnHit(ownerID, spGetUnitTeam(ownerID), context.itemID, weaponDefID,
				targetID, hitX, hitZ, damage, context.eventID, context.effects,
				context.procCoefficient, 0)
		end
	end
end

local function getUnlockedEffects(item, level)
	local effects = {}
	for levelIndex = 1, min(max(0, level - 1), #(item.levels or {})) do
		for _, effect in ipairs(item.levels[levelIndex].effectUnlocks or {}) do
			effects[#effects + 1] = effect
		end
	end
	return effects
end

local function applyBurn(itemID, targetID, ownerID, weaponDefID, dps, seconds, damageMult, frame)
	if not dps or dps <= 0 or not targetID then return end
	local key = ownerID .. ":" .. itemID .. ":" .. targetID
	local state = burnStates[key]
	if not state then
		state = { itemID = itemID, targetID = targetID, ownerID = ownerID, weaponDefID = weaponDefID,
			teamID = spGetUnitTeam(ownerID), endFrame = frame, nextFrame = frame, damage = 0 }
		burnStates[key] = state
	end
	state.ownerID = ownerID
	state.teamID = spGetUnitTeam(ownerID)
	state.weaponDefID = weaponDefID
	state.damage = dps * damageMult * (6 / gameSpeed)
	state.endFrame = frame + seconds * gameSpeed
end

local function applySlow(itemID, targetID, targetDefID, factor, seconds, frame, ownerID)
	if not GG.UnitAttributes or not GG.UnitAttributes.SetUnitModifier then return end
	local targetDef = UnitDefs[targetDefID]
	local baseHealth = targetDef and targetDef.health or 0
	if targetDef and targetDef.customParams and targetDef.customParams.roguelike_boss then return end
	if baseHealth > 12000 then return end
	local source = "roguelike_weapon:" .. ownerID .. ":" .. itemID
	GG.UnitAttributes.SetUnitModifier(targetID, "speed", 1 - factor, source)
	GG.UnitAttributes.SetUnitModifier(targetID, "turnRate", 1 - factor, source)
	GG.UnitAttributes.SetUnitModifier(targetID, "maxAcc", 1 - factor, source)
	slowStates[source .. ":" .. targetID] = {
		targetID = targetID, ownerID = ownerID, source = source,
		teamID = spGetUnitTeam(ownerID), endFrame = frame + seconds * gameSpeed,
	}
end

local function fireCone(item, params, ownerID, teamID, weaponDefID, target, targetX, targetZ, frame)
	local ownerX, _, ownerZ = spGetUnitPosition(ownerID)
	if not ownerX then return end
	local dx, dz = targetX - ownerX, targetZ - ownerZ
	local length = sqrt(dx * dx + dz * dz)
	if length <= 0 then return end
	dx, dz = dx / length, dz / length
	local maxRange = (spGetUnitRulesParam(ownerID, "roguelike_range_mult") or 1) * params.range
	local candidates = collectTargets(ownerID, teamID, ownerX, ownerZ, maxRange, params.targetClass, target)
	local halfAngle = (params.coneDegrees or 90) * pi / 360
	local maxTargets = params.maxTargets or #candidates
	local hitCount = 0
	for _, entry in ipairs(candidates) do
		local vx, vz = entry.x - ownerX, entry.z - ownerZ
		local d = sqrt(entry.d2)
		local dot = d > 0 and (vx * dx + vz * dz) / d or 1
		if d <= maxRange and dot >= cos(halfAngle) then
			local damage = params.damage * (params.damageMult or 1)
			dealDamage(entry.id, ownerID, weaponDefID, damage, "area")
			if params.burnDPS then
				applyBurn(item.id, entry.id, ownerID, weaponDefID, params.burnDPS * (params.burnDPSMult or 1),
					params.burnSeconds or 1, 1, frame)
			end
			if params.slow then applySlow(item.id, entry.id, spGetUnitDefID(entry.id), params.slow, params.slowSeconds or 1, frame, ownerID) end
			hitCount = hitCount + 1
			if hitCount >= maxTargets then break end
		end
	end
end

local function fireBlast(item, params, ownerID, teamID, weaponDefID, target, targetX, targetZ, frame)
	local levelRange = (spGetUnitRulesParam(ownerID, "roguelike_range_mult") or 1) * params.range
	local candidates = collectTargets(ownerID, teamID, targetX, targetZ, params.radius or 0, params.targetClass, target)
	local maxTargets = params.maxTargets or #candidates
	for index, entry in ipairs(candidates) do
		if index > maxTargets then break end
		local d = sqrt(entry.d2)
		local edgeMult = params.edgeDamageMult and max(params.edgeDamageMult, 1 - d / max(1, params.radius)) or 1
		local damage = params.damage * (params.damageMult or 1) * edgeMult
		if d <= levelRange then dealDamage(entry.id, ownerID, weaponDefID, damage, "area") end
		if params.burnDPS then
			applyBurn(item.id, entry.id, ownerID, weaponDefID, params.burnDPS, params.burnSeconds or 1,
				1, frame)
		end
		if params.knockback and d > 0 and (UnitDefs[spGetUnitDefID(entry.id)].health or 0) < 12000 and spAddUnitImpulse then
			local vx, vy, vz = spGetUnitVelocity(entry.id)
			spAddUnitImpulse(entry.id, (entry.x - targetX) / d * params.knockback,
				vy or 0, (entry.z - targetZ) / d * params.knockback)
		end
	end
end

local function firePierce(item, params, ownerID, teamID, weaponDefID, target, targetX, targetZ)
	local ownerX, _, ownerZ = spGetUnitPosition(ownerID)
	if not ownerX then return end
	local dx, dz = targetX - ownerX, targetZ - ownerZ
	local length = sqrt(dx * dx + dz * dz)
	if length <= 0 then return end
	dx, dz = dx / length, dz / length
	local maxRange = (spGetUnitRulesParam(ownerID, "roguelike_range_mult") or 1) * params.range
	local candidates = collectTargets(ownerID, teamID, ownerX, ownerZ, maxRange, params.targetClass, target)
	local line = {}
	for _, entry in ipairs(candidates) do
		local vx, vz = entry.x - ownerX, entry.z - ownerZ
		local projection = vx * dx + vz * dz
		local perpendicular = math.abs(vx * dz - vz * dx)
		if projection > 0 and projection <= maxRange and perpendicular <= 70 then
			entry.projection = projection
			line[#line + 1] = entry
		end
	end
	table.sort(line, function(a, b)
		if a.projection == b.projection then return a.id < b.id end
		return a.projection < b.projection
	end)
	for index, entry in ipairs(line) do
		if index > (params.maxTargets or 3) then break end
		local falloff = params.falloff[index] or params.falloff[#params.falloff] or 0
		local damage = params.damage * (params.damageMult or 1) * falloff
		if index == 1 and params.bossDamageMult then
			local unitDef = UnitDefs[spGetUnitDefID(entry.id)]
			if unitDef and ((unitDef.customParams and unitDef.customParams.roguelike_boss) or (unitDef.health or 0) > 12000) then
				damage = damage * params.bossDamageMult
			end
		end
		dealDamage(entry.id, ownerID, weaponDefID, damage, "direct")
	end
end

local function fireMulti(item, params, ownerID, teamID, weaponDefID, target, targetX, targetZ)
	local range = (spGetUnitRulesParam(ownerID, "roguelike_range_mult") or 1) * params.range
	local ownerX, _, ownerZ = spGetUnitPosition(ownerID)
	if not ownerX then return end
	local candidates = collectTargets(ownerID, teamID, ownerX, ownerZ, range, params.targetClass, target)
	local projectileCount = params.projectileCount or params.maxTargets or 1
	local maxPerTarget = params.maxPerTarget or 1
	local targetHits = {}
	for shot = 1, projectileCount do
		local entry
		for _, candidate in ipairs(candidates) do
			if (targetHits[candidate.id] or 0) < maxPerTarget then entry = candidate; break end
		end
		if not entry then break end
		targetHits[entry.id] = (targetHits[entry.id] or 0) + 1
		local damage = params.damage * (params.damageMult or 1)
		if params.splashTargets and params.splashTargets > 0 then
			if item.attack == "heatSuppress" then
				fireRamp(item, params, ownerID, weaponDefID, entry.id, spGetGameFrame())
			else
				dealDamage(entry.id, ownerID, weaponDefID, damage, "direct")
			end
			local splash = collectTargets(ownerID, teamID, entry.x, entry.z, 90, params.targetClass, entry.id)
			local splashCount = 0
			for _, splashTarget in ipairs(splash) do
				if splashTarget.id ~= entry.id then
					dealDamage(splashTarget.id, ownerID, weaponDefID, damage * (params.splashDamageMult or 0.25), "area")
					splashCount = splashCount + 1
					if splashCount >= params.splashTargets then break end
				end
			end
		else
			if item.attack == "heatSuppress" then
				fireRamp(item, params, ownerID, weaponDefID, entry.id, spGetGameFrame())
			else
				dealDamage(entry.id, ownerID, weaponDefID, damage, "direct")
			end
		end
		if params.slow then applySlow(item.id, entry.id, spGetUnitDefID(entry.id), params.slow, params.slowSeconds or 1, spGetGameFrame(), ownerID) end
	end
end

fireRamp = function(item, params, ownerID, weaponDefID, targetID, frame)
	local key = ownerID .. ":" .. item.id .. ":" .. (item.attack == "heatSuppress" and targetID or "single")
	local state = rampStates[key]
	local switching = not state or state.targetID ~= targetID or frame - state.lastFrame > 2 * gameSpeed
	local rampStart = params.rampStartDPS or 0
	local priorBonus = state and max(0, state.currentDPS - rampStart) or 0
	if switching then
		local carryBonus = state and state.carried and 0
			or (priorBonus * (params.switchCarry or 0))
		state = { targetID = targetID, startFrame = frame, lastFrame = frame,
			carryDPS = carryBonus,
			carried = (state and state.carried) or carryBonus > 0 }
		rampStates[key] = state
	end
	local elapsed = max(0, frame - state.startFrame) / gameSpeed
	local rampSeconds = max(0.1, params.rampSeconds or 1)
	local maxDPS = (params.rampMaxDPS or rampStart) * (params.rampMaxMult or 1)
	local stepDPS = params.rampStepDPS or ((maxDPS - rampStart) / rampSeconds)
	stepDPS = stepDPS * (params.rampStepMult or 1)
	local dps = min(maxDPS, rampStart + state.carryDPS + elapsed * stepDPS)
	state.currentDPS = dps
	state.lastFrame = frame
	local tickDamage = dps * (params.reload or 0.2) * (params.damageMult or 1)
	dealDamage(targetID, ownerID, weaponDefID, tickDamage, "dot")
	if params.slow then applySlow(item.id, targetID, spGetUnitDefID(targetID), params.slow, params.slowSeconds or 1, frame, ownerID) end
end

local function applyWeaponEffect(ownerID, weaponNum, weaponDefID, item, target, targetX, targetZ)
	if not targetX then return end
	if item.attack == "cone" then
		local key = ownerID .. ":" .. item.id
		local frame = spGetGameFrame()
		if lastConeEffectFrame[key] == frame then return end
		lastConeEffectFrame[key] = frame
	end
	local teamID = spGetUnitTeam(ownerID)
	if target and not targetAllowed(target, teamID, item.targetClass) then target = nil end
	if target and targetAllowed(target, teamID, item.targetClass) then
		targetX, _, targetZ = spGetUnitPosition(target)
	end
	if not targetX then return end
	local frame = spGetGameFrame()
	local params = levelConfig(item, getWeaponLevel(ownerID, item.id))
	params.reload = params.reload or item.reload
	params.damageMult = params.damageMult or 1
	local priorEffectContext = activeEffectContext
	local effectBus = GG.RoguelikeWeaponEffects
	activeEffectContext = {
		itemID = item.id,
		eventID = effectBus and effectBus.NewEvent and effectBus.NewEvent(ownerID, teamID, weaponDefID) or frame * 65536 + ownerID,
		effects = getUnlockedEffects(item, getWeaponLevel(ownerID, item.id)),
		procCoefficient = (item.attack == "multi" or item.attack == "hive") and 0.4 or 0.6,
	}
	if item.attack == "cone" or item.attack == "coneBurn" then
		fireCone(item, params, ownerID, teamID, weaponDefID, target, targetX, targetZ, frame)
	elseif item.attack == "blast" or item.attack == "burnBlast" then
		fireBlast(item, params, ownerID, teamID, weaponDefID, target, targetX, targetZ, frame)
	elseif item.attack == "pierce" then
		firePierce(item, params, ownerID, teamID, weaponDefID, target, targetX, targetZ)
	elseif item.attack == "multi" or item.attack == "hive" or item.attack == "heatSuppress" then
		fireMulti(item, params, ownerID, teamID, weaponDefID, target, targetX, targetZ)
	elseif item.attack == "ramp" or item.attack == "thermal" then
		if target then fireRamp(item, params, ownerID, weaponDefID, target, frame) end
	end
	if params.burnDPS and item.attack == "burnBlast" and target then
		applyBurn(item.id, target, ownerID, weaponDefID, params.burnDPS, params.burnSeconds, 1, frame)
	end
	activeEffectContext = priorEffectContext
end

local function findWeaponNumber(unitID, weaponDefID)
	local unitDef = UnitDefs[spGetUnitDefID(unitID)]
	for weaponNum, weapon in ipairs(unitDef and unitDef.weapons or {}) do
		if weapon.weaponDef == weaponDefID then return weaponNum end
	end
	return nil
end

local function handleSpecialWeapon(ownerID, weaponNum, weaponDefID)
	local item = byWeaponDefID[weaponDefID]
	if not item or not commanderIDs[ownerID] or (getWeaponLevel(ownerID, item.id) <= 0)
		or (spGetUnitRulesParam(ownerID, "roguelike_weapon_equipped_" .. item.id) or 0) ~= 1 then
		return
	end
	if item.weaponType == "Cannon" or item.weaponType == "MissileLauncher" then return end
	-- GetUnitWeaponTarget returns (targetType, isUserTarget, target); do not
	-- mistake the user-target flag for the UnitID when several targets compete.
	local targetType, _, target = spGetUnitWeaponTarget(ownerID, weaponNum)
	local targetID = targetType == targetTypeUnit and target or nil
	if targetType ~= targetTypeUnit or not targetID or not targetAllowed(targetID, spGetUnitTeam(ownerID), item.targetClass) then return end
	local targetX, _, targetZ = spGetUnitPosition(targetID)
	applyWeaponEffect(ownerID, weaponNum, weaponDefID, item, targetID, targetX, targetZ)
end

local function onWeaponFired(ownerID, weaponNum)
	local unitDef = UnitDefs[spGetUnitDefID(ownerID)]
	local weapon = unitDef and unitDef.weapons[weaponNum]
	if weapon then handleSpecialWeapon(ownerID, weaponNum, weapon.weaponDef) end
end

function gadget:Initialize()
	-- Lua unit scripts call this at their native FireWeapon callback. In
	-- particular, ARM's zero-damage beam supplies visuals while this supplies
	-- the catalog's cone/multi-target/piercing damage once per shot.
	GG.RoguelikeFactionWeapons = { OnWeaponFired = onWeaponFired }
	-- ProjectileCreated and Explosion are dispatched only for weapon definitions
	-- watched by this gadget. Cannon and missile faction weapons deal their
	-- catalog damage in Explosion; their WeaponDefs have zero native damage.
	for weaponDefID in pairs(byWeaponDefID) do
		gadgetHandler:RegisterProjectile(weaponDefID)
		gadgetHandler:RegisterExplosion(weaponDefID)
	end
	for _, unitID in ipairs(Spring.GetAllUnits()) do
		local unitDefID = spGetUnitDefID(unitID)
		local unitDef = unitDefID and UnitDefs[unitDefID]
		if unitDef and unitDef.customParams and unitDef.customParams.iscommander then
			local _, _, _, isAI = Spring.GetTeamInfo(spGetUnitTeam(unitID))
			if not isAI then commanderIDs[unitID] = true end
		end
	end
end

function gadget:Shutdown()
	GG.RoguelikeFactionWeapons = nil
end

function gadget:UnitCreated(unitID, unitDefID, teamID)
	local unitDef = UnitDefs[unitDefID]
	if unitDef and unitDef.customParams and unitDef.customParams.iscommander then
		local _, _, _, isAI = Spring.GetTeamInfo(teamID)
		if not isAI then commanderIDs[unitID] = true end
	end
end

function gadget:UnitDestroyed(unitID)
	commanderIDs[unitID] = nil
	for key in pairs(lastConeEffectFrame) do
		if key:match("^" .. unitID .. ":") then lastConeEffectFrame[key] = nil end
	end
	for key, state in pairs(burnStates) do
		if state.targetID == unitID or state.ownerID == unitID then burnStates[key] = nil end
	end
	for key, state in pairs(slowStates) do
		if state.targetID == unitID then slowStates[key] = nil end
	end
end

function gadget:UnitWeaponFired(unitID, unitDefID, unitTeam, weaponNum, weaponDefID)
	-- ARM dispatches from its Lua unit script, including on engines without
	-- this gadget call-in. Do not apply the same shot twice if it is provided.
	if UnitDefs[unitDefID] and UnitDefs[unitDefID].name == "armcom" then return end
	-- UnitWeaponFired supplies the weapon slot; resolve its WeaponDef from the
	-- firing UnitDef. Some engine builds do not pass weaponDefID as arg five.
	if not weaponDefID then
		local unitDef = UnitDefs[unitDefID]
		local weapon = unitDef and unitDef.weapons and unitDef.weapons[weaponNum]
		weaponDefID = weapon and weapon.weaponDef
	end
	if weaponDefID then handleSpecialWeapon(unitID, weaponNum, weaponDefID) end
end

function gadget:ProjectileCreated(projectileID, ownerID, weaponDefID)
	local item = byWeaponDefID[weaponDefID]
	if not item or not commanderIDs[ownerID] then return end
	local ownerDef = UnitDefs[spGetUnitDefID(ownerID)]
	-- ARM beams already resolve once from FireWeapon. A beam emits several
	-- visual projectiles, each with an Explosion event; none may deal it again.
	if ownerDef and ownerDef.name == "armcom"
		and item.weaponType ~= "Cannon" and item.weaponType ~= "MissileLauncher" then return end
	-- Cone weapons resolve synchronously from UnitWeaponFired; waiting for an
	-- explosion would either miss BeamLaser shots or apply the cone twice.
	if item.attack == "cone" then return end
	local weaponNum = findWeaponNumber(ownerID, weaponDefID)
	if not weaponNum then return end
	local targetType, target = spGetProjectileTarget(projectileID)
	local targetID = targetType == projectileTargetUnit and target or nil
	local x, z
	if targetType == projectileTargetGround and type(target) == "table" then
		x, z = target[1], target[3]
	elseif targetID and spValidUnitID(targetID) then
		x, _, z = spGetUnitPosition(targetID)
	end
	weaponProjectiles[projectileID] = { ownerID = ownerID, weaponDefID = weaponDefID,
		weaponNum = weaponNum, item = item, targetID = targetID, targetX = x, targetZ = z,
		firedFrame = spGetGameFrame() }
end

function gadget:Explosion(weaponDefID, x, y, z, ownerID, projectileID)
	local state = projectileID and weaponProjectiles[projectileID]
	if not state then return end
	weaponProjectiles[projectileID] = nil
	if state.item.attack == "hive" then
		local volleyKey = state.ownerID .. ":" .. state.item.id
		local lastFrame = lastHiveVolleyFrame[volleyKey]
		if lastFrame and state.firedFrame - lastFrame < gameSpeed then return end
		lastHiveVolleyFrame[volleyKey] = state.firedFrame
	end
	local targetID = state.targetID
	local centerX, centerZ = x or state.targetX, z or state.targetZ
	if targetID and spValidUnitID(targetID) then
		local targetX, _, targetZ = spGetUnitPosition(targetID)
		centerX, centerZ = targetX or centerX, targetZ or centerZ
	end
	applyWeaponEffect(state.ownerID, state.weaponNum, state.weaponDefID,
		state.item, targetID, centerX, centerZ)
end

function gadget:ProjectileDestroyed(projectileID)
	weaponProjectiles[projectileID] = nil
end

function gadget:GameFrame(frame)
	if frame % 6 ~= 0 then return end
	for key, state in pairs(rampStates) do
		if frame - state.lastFrame > 5 * gameSpeed or not spValidUnitID(state.targetID) then
			rampStates[key] = nil
		end
	end
	for key, state in pairs(burnStates) do
		if frame > state.endFrame or not isEnemy(state.targetID, state.teamID) then
			burnStates[key] = nil
		elseif frame >= state.nextFrame then
			dealDamage(state.targetID, state.ownerID, state.weaponDefID, state.damage, "dot")
			state.nextFrame = frame + 6
		end
	end
	for key, state in pairs(slowStates) do
		if frame >= state.endFrame or not isEnemy(state.targetID, state.teamID) then
			if GG.UnitAttributes and GG.UnitAttributes.SetUnitModifier and spValidUnitID(state.targetID) then
				GG.UnitAttributes.SetUnitModifier(state.targetID, "speed", nil, state.source)
				GG.UnitAttributes.SetUnitModifier(state.targetID, "turnRate", nil, state.source)
				GG.UnitAttributes.SetUnitModifier(state.targetID, "maxAcc", nil, state.source)
			end
			slowStates[key] = nil
		end
	end
end
