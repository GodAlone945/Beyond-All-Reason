local gadget = gadget ---@type Gadget

function gadget:GetInfo()
	return {
		name = "Roguelike Weapon Effects",
		desc = "Synced reusable projectile effects for Roguelike weapons",
		author = "Codex",
		date = "2026",
		license = "GNU GPL, v2 or later",
		layer = 0,
		enabled = true,
	}
end

local modOptions = Spring.GetModOptions()
local roguelikeMode = modOptions.roguelike_mode
if roguelikeMode ~= true and roguelikeMode ~= 1 and roguelikeMode ~= "1" and roguelikeMode ~= "true" then
	return false
end
local testEnabled = modOptions.roguelike_weapon_effect_tests
testEnabled = testEnabled == true or testEnabled == 1 or testEnabled == "1" or testEnabled == "true"
if not gadgetHandler:IsSyncedCode() then
	return
end

local definitions = VFS.Include("unitbasedefs/roguelike_weapon_effects.lua")
local limits = definitions.limits
local gameSpeed = Game.gameSpeed
local floor = math.floor
local sqrt = math.sqrt
local cos = math.cos
local sin = math.sin
local pi = math.pi
local max = math.max
local min = math.min
local random = math.random
local spSpawnProjectile = Spring.SpawnProjectile
local spDeleteProjectile = Spring.DeleteProjectile
local spSpawnCEG = Spring.SpawnCEG
local spGetUnitPosition = Spring.GetUnitPosition
local spGetUnitTeam = Spring.GetUnitTeam
local spGetUnitDefID = Spring.GetUnitDefID
local spGetProjectileTeamID = Spring.GetProjectileTeamID
local spGetProjectilePosition = Spring.GetProjectilePosition
local spGetProjectileVelocity = Spring.GetProjectileVelocity
local spSetProjectileTarget = Spring.SetProjectileTarget
local spSetProjectileDamages = Spring.SetProjectileDamages
local spGetUnitsInCylinder = Spring.GetUnitsInCylinder
local spAreTeamsAllied = Spring.AreTeamsAllied
local spGetGroundHeight = Spring.GetGroundHeight
local spGetGameFrame = Spring.GetGameFrame
local spSetUnitRulesParam = Spring.SetUnitRulesParam
local spGetUnitRulesParam = Spring.GetUnitRulesParam
local spAddUnitDamage = Spring.AddUnitDamage
local spValidUnitID = Spring.ValidUnitID
local spGetUnitHealth = Spring.GetUnitHealth
local spInsertUnitCmdDesc = Spring.InsertUnitCmdDesc
local spFindUnitCmdDesc = Spring.FindUnitCmdDesc
local inLosAccess = { inlos = true }
local targetUnit = string.byte("u")
local CMD_ROGUELIKE_METEOR_STRIKE = GameCMD.ROGUELIKE_METEOR_STRIKE
local armCommanderDefID = UnitDefNames.armcom and UnitDefNames.armcom.id

local function isArmCommander(unitDefID)
	return armCommanderDefID and unitDefID == armCommanderDefID
end

local launcherByWeaponDef = {}
local payloadByWeaponDef = {}
local commanderProjectileByWeaponDef = {}
local beamLastProcFrame = {}
local meteorPayloadWeaponDefID
local projectileState = {}
-- ??????????????/???????
local electricOrbs = {}
local activeByOwner = {}
local activeProjectileCount = 0
local pendingMeteors = {}
local roguelikeCommanders = {}
local areaStates = {}
local events = {}
local effectCooldowns = {}
local pendingKillContexts = {}
local effectCounters = { procEvents = 0, procChainRejected = 0, activeZones = 0, areaHits = 0 }
local nextMeteorFrame = {}
local spawnFrame = -1
local spawnsThisFrame = 0
local spawnContext
local eventSequence = 0
local procFrame = -1
local procEventsThisFrame = 0
local procEventsByOwner = {}

local function getUpgrade(ownerID, effectID, key)
	local schema = definitions.upgrades[effectID][key]
	local value = spGetUnitRulesParam(ownerID, "roguelike_effect_" .. effectID .. "_" .. key)
	if value == nil then
		return schema.default
	end
	return value
end

local function getDamageAttribution(projectileID)
	local state = projectileID and projectileState[projectileID]
	if not state then return nil end
	local x, _, z = spGetProjectilePosition(projectileID)
	local weaponDef = WeaponDefs[state.weaponDefID]
	return {
		ownerID = state.ownerID, teamID = state.teamID, kind = state.kind,
		depth = state.depth or 0, rootAttackID = state.eventID,
		projectileID = projectileID, x = x, z = z,
		radius = state.radius or (weaponDef and (weaponDef.damageAreaOfEffect or weaponDef.areaOfEffect)) or 0,
	}
end

local function newEvent(ownerID, teamID, weaponDefID)
	eventSequence = eventSequence + 1
	events[eventSequence] = { ownerID = ownerID, teamID = teamID, weaponDefID = weaponDefID,
		frame = spGetGameFrame(), used = {} }
	return eventSequence
end

local function collectProcTargets(teamID, x, z, radius, excludedTarget, maxTargets)
	local candidates = {}
	maxTargets = min(maxTargets or limits.maxTargetsPerAreaTick, limits.maxTargetsPerAreaTick)
	for _, unitID in ipairs(spGetUnitsInCylinder(x, z, radius) or {}) do
		if unitID ~= excludedTarget and spValidUnitID(unitID) then
			local targetTeam = spGetUnitTeam(unitID)
			local health = spGetUnitHealth(unitID)
			local ux, _, uz = spGetUnitPosition(unitID)
			if targetTeam and not spAreTeamsAllied(teamID, targetTeam) and health and health > 0 and ux then
				local dx, dz = ux - x, uz - z
				local candidate = { id = unitID, distance = dx * dx + dz * dz }
				local insertAt = #candidates + 1
				for index, current in ipairs(candidates) do
					if candidate.distance < current.distance
						or (candidate.distance == current.distance and candidate.id < current.id) then
						insertAt = index
						break
					end
				end
				if insertAt <= maxTargets then
					table.insert(candidates, insertAt, candidate)
					if #candidates > maxTargets then candidates[#candidates] = nil end
				end
			end
		end
	end
	local result = {}
	for index = 1, #candidates do result[index] = candidates[index].id end
	return result
end

local function dealProcDamage(ownerID, teamID, weaponDefID, targetID, damage)
	if damage <= 0 or not spValidUnitID(ownerID) or not spValidUnitID(targetID) then return false end
	local targetTeam = spGetUnitTeam(targetID)
	if not targetTeam or spAreTeamsAllied(teamID, targetTeam) then return false end
	local _, maxHealth = spGetUnitHealth(targetID)
	local targetDef = UnitDefs[spGetUnitDefID(targetID)]
	if targetDef and maxHealth and ((targetDef.customParams and targetDef.customParams.roguelike_boss) or maxHealth > 12000) then
		damage = min(damage, maxHealth * 0.05)
	end
	local bus = GG.RoguelikeWeaponEffects
	local previousTarget = bus and bus.currentProcTargetID
	if bus then bus.currentProcTargetID = targetID end
	local ok, err = pcall(spAddUnitDamage, targetID, damage, 0, ownerID, weaponDefID)
	if bus then bus.currentProcTargetID = previousTarget end
	if not ok then error(err, 0) end
	effectCounters.areaHits = effectCounters.areaHits + 1
	return true
end

local function registerHitContext(ownerID, teamID, weaponDefID, targetID, x, z, damage, eventID, effectEntries, procCoefficient)
	if not ownerID or not teamID or not targetID or not x or not z or damage <= 0 or not events[eventID] then return end
	pendingKillContexts[targetID] = {
		frame = spGetGameFrame(), ownerID = ownerID, teamID = teamID, weaponDefID = weaponDefID,
		x = x, z = z, damage = damage, eventID = eventID,
		effectEntries = effectEntries, procCoefficient = procCoefficient,
	}
end

local function enqueueArea(effectID, config, ownerID, teamID, weaponDefID, x, z, baseDamage, frame)
	local ownerCount = 0
	local ownerZoneCount = 0
	for _, state in ipairs(areaStates) do
		if state.ownerID == ownerID then
			ownerCount = ownerCount + 1
			if state.effectID == "burn_zone" then ownerZoneCount = ownerZoneCount + 1 end
			if state.effectID == effectID and (state.x - x) ^ 2 + (state.z - z) ^ 2 <= 64 * 64 then
				state.endFrame = max(state.endFrame, frame + (config.durationFrames or 1))
				state.nextFrame = min(state.nextFrame, frame + (config.tickFrames or config.delayFrames or 1))
				state.baseDamage = max(state.baseDamage, baseDamage)
				return true
			end
		end
	end
	if ownerCount >= limits.maxAreaStatesPerOwner
		or (effectID == "burn_zone" and ownerZoneCount >= limits.maxZonesPerOwner) then
		effectCounters.procChainRejected = effectCounters.procChainRejected + 1
		return false
	end
	if #areaStates >= (limits.maxAreaStatesPerOwner or 12) * 4 then
		effectCounters.procChainRejected = effectCounters.procChainRejected + 1
		return false
	end
	areaStates[#areaStates + 1] = {
		effectID = effectID, ownerID = ownerID, teamID = teamID, weaponDefID = weaponDefID,
		x = x, z = z, radius = config.radius, baseDamage = baseDamage,
		damageFraction = config.damageFraction, maxTargets = config.maxTargets,
		tickFrames = config.tickFrames or 0,
		endFrame = frame + (config.durationFrames or config.delayFrames or config.tickFrames or 1),
		nextFrame = frame + (config.delayFrames or config.tickFrames or 1),
	}
	local marker = "roguelike-effect-" .. effectID
	spSpawnCEG(marker, x, spGetGroundHeight(x, z), z, 0, 1, 0, config.radius)
	if effectID == "burn_zone" then effectCounters.activeZones = effectCounters.activeZones + 1 end
	return true
end

local function consumeProcBudget(ownerID, frame)
	if procFrame ~= frame then
		procFrame, procEventsThisFrame, procEventsByOwner = frame, 0, {}
	end
	local ownerCount = procEventsByOwner[ownerID] or 0
	if procEventsThisFrame >= limits.maxProcEventsPerFrame
		or ownerCount >= limits.maxProcEventsPerOwnerFrame then
		effectCounters.procChainRejected = effectCounters.procChainRejected + 1
		return false
	end
	procEventsThisFrame = procEventsThisFrame + 1
	procEventsByOwner[ownerID] = ownerCount + 1
	effectCounters.procEvents = effectCounters.procEvents + 1
	return true
end

local function triggerEffect(ownerID, teamID, sourceID, weaponDefID, targetID, x, z, damage,
		eventID, effectEntry, procCoefficient, depth, frame, triggerType)
	local config = definitions.effectRegistry[effectEntry.id]
	if not config or depth > limits.maxProcDepth or (procCoefficient or 0) <= 0 then return false end
	if (effectEntry.trigger or config.trigger or "onHit") ~= triggerType then return false end
	local event = events[eventID]
	if not event or event.used[effectEntry.id] then return false end
	event.used[effectEntry.id] = true
	local cooldownKey = ownerID .. ":" .. effectEntry.id
	if frame < (effectCooldowns[cooldownKey] or 0) then return false end
	local chance = (effectEntry.chance or config.chance or 1) * procCoefficient
	if chance < 1 and random() >= chance then return false end
	if not consumeProcBudget(ownerID, frame) then return false end
	effectCooldowns[cooldownKey] = frame + (effectEntry.cooldownFrames or config.cooldownFrames or 0)
	local radius = effectEntry.radius or config.radius or 0
	local fractions = effectEntry.damageFractions or config.damageFractions
	if effectEntry.id == "chain" or effectEntry.id == "ricochet" then
		local maxTargets = min(config.maxTargets or 1, #fractions)
		local targets = collectProcTargets(teamID, x, z, radius, targetID, maxTargets)
		local weaponParams = WeaponDefs[weaponDefID] and WeaponDefs[weaponDefID].customParams
		local electricOrb = effectEntry.id == "chain" and weaponParams
			and weaponParams.roguelike_shop_item == "electric_orb"
		for index, childTarget in ipairs(targets) do
			local targetX, targetY, targetZ
			local sourceY
			if electricOrb then
				sourceY = select(2, spGetUnitPosition(targetID))
				targetX, targetY, targetZ = spGetUnitPosition(childTarget)
			end
			if dealProcDamage(ownerID, teamID, weaponDefID, childTarget, damage * fractions[index])
				and electricOrb then
				if targetX then
					sourceY = sourceY or spGetGroundHeight(x, z) + 20
					for step = 1, 3 do
						local fraction = step / 3
						spSpawnCEG("roguelike-electric-orb-chain",
							x + (targetX - x) * fraction,
							sourceY + (targetY - sourceY) * fraction,
							z + (targetZ - z) * fraction, 0, 1, 0)
						end
				end
			end
		end
	elseif effectEntry.id == "burst" then
		local targets = collectProcTargets(teamID, x, z, radius, targetID, config.maxTargets or 8)
		for _, childTarget in ipairs(targets) do
			dealProcDamage(ownerID, teamID, weaponDefID, childTarget, damage * config.damageFraction)
		end
	else
		enqueueArea(effectEntry.id, config, ownerID, teamID, weaponDefID, x, z,
			damage, frame)
	end
	return true
end

local function onHit(ownerID, teamID, sourceID, weaponDefID, targetID, x, z, damage,
		eventID, effectEntries, procCoefficient, depth)
	if not ownerID or not teamID or not x or not z or damage <= 0 or (depth or 0) > 0 then return end
	if not events[eventID] then return end
	local frame = spGetGameFrame()
	for _, effectEntry in ipairs(effectEntries or {}) do
		if type(effectEntry) == "string" then effectEntry = { id = effectEntry } end
		if effectEntry and effectEntry.id then
			triggerEffect(ownerID, teamID, sourceID, weaponDefID, targetID, x, z, damage,
				eventID, effectEntry, procCoefficient or 0, depth or 0, frame, "onHit")
		end
	end
end

local function onKill(context)
	if not context or not events[context.eventID] then return end
	local frame = spGetGameFrame()
	for _, effectEntry in ipairs(context.effectEntries or {}) do
		if type(effectEntry) == "string" then effectEntry = { id = effectEntry } end
		if effectEntry and effectEntry.id then
			triggerEffect(context.ownerID, context.teamID, "kill", context.weaponDefID,
				context.targetID, context.x, context.z, context.damage, context.eventID,
				effectEntry, context.procCoefficient or 0, 0, frame, "onKill")
		end
	end
end

local function processAreaStates(frame)
	for index = #areaStates, 1, -1 do
		local state = areaStates[index]
		if not spValidUnitID(state.ownerID) or frame > state.endFrame then
			if state.effectID == "burn_zone" then effectCounters.activeZones = max(0, effectCounters.activeZones - 1) end
			table.remove(areaStates, index)
		elseif frame >= state.nextFrame then
			local targets = collectProcTargets(state.teamID, state.x, state.z, state.radius, nil, state.maxTargets or 12)
			for _, targetID in ipairs(targets) do
				dealProcDamage(state.ownerID, state.teamID, state.weaponDefID, targetID,
					state.baseDamage * state.damageFraction)
			end
			if state.tickFrames > 0 then
				state.nextFrame = frame + state.tickFrames
			else
				table.remove(areaStates, index)
			end
		end
	end
end

local function getSplitMode(ownerID)
	local modeIndex = getUpgrade(ownerID, "splitter", "splitMode")
	return definitions.upgrades.splitter.splitMode.values[modeIndex] or "impact"
end

local function setUpgrade(ownerID, effectID, key, value)
	local schema = definitions.upgrades[effectID] and definitions.upgrades[effectID][key]
	if not schema or not Spring.ValidUnitID(ownerID) then
		return false
	end
	if schema.values then
		local index = tonumber(value)
		if not index or index < 1 or index > #schema.values then
			return false
		end
		value = index
	else
		value = tonumber(value)
		if not value then
			return false
		end
		value = max(schema.min, min(schema.max, value))
		local steps = floor((value - schema.min) / schema.step + 0.5)
		value = schema.min + steps * schema.step
	end
	spSetUnitRulesParam(ownerID, "roguelike_effect_" .. effectID .. "_" .. key, value, inLosAccess)
	return true
end

local function reserveSpawn(frame)
	if spawnFrame ~= frame then
		spawnFrame = frame
		spawnsThisFrame = 0
	end
	if spawnsThisFrame >= limits.maxSpawnsPerFrame then
		return false
	end
	spawnsThisFrame = spawnsThisFrame + 1
	return true
end

local function clearProjectile(projectileID)
	local state = projectileState[projectileID]
	if not state then
		return
	end
	projectileState[projectileID] = nil
	activeProjectileCount = max(0, activeProjectileCount - 1)
	local count = activeByOwner[state.ownerID] or 1
	if count <= 1 then
		activeByOwner[state.ownerID] = nil
	else
		activeByOwner[state.ownerID] = count - 1
	end
end

local function registerProjectile(projectileID, state)
	if not projectileID or projectileState[projectileID] then
		return false
	end
	local ownerCount = activeByOwner[state.ownerID] or 0
	if activeProjectileCount >= limits.maxActiveProjectiles or ownerCount >= limits.maxActivePerPlayer then
		-- Observing a native weapon must never delete its primary shot when the proc budget is full.
		if state.kind ~= "commander_projectile" then spDeleteProjectile(projectileID) end
		effectCounters.procChainRejected = effectCounters.procChainRejected + 1
		return false
	end
	projectileState[projectileID] = state
	activeProjectileCount = activeProjectileCount + 1
	activeByOwner[state.ownerID] = ownerCount + 1
	if state.radius then
		spSetProjectileDamages(projectileID, 0, "damageAreaOfEffect", state.radius * 2)
	end
	return true
end

local function enqueueMeteor(ownerID, teamID, x, z, depth, damageScale, frame, eventID, profile)
	local ownerQueue = pendingMeteors[ownerID]
	if not ownerQueue then
		ownerQueue = {}
		pendingMeteors[ownerID] = ownerQueue
	end
	if #ownerQueue >= limits.maxPendingMeteorsPerPlayer then
		return false
	end
	local radius = profile and profile.radius or getUpgrade(ownerID, "meteor", "radius")
	spSpawnCEG("roguelike-meteor-warning", x, spGetGroundHeight(x, z), z, 0, 1, 0, radius)
	ownerQueue[#ownerQueue + 1] = {
		ownerID = ownerID,
		teamID = teamID,
		payloadDefID = meteorPayloadWeaponDefID,
		x = x,
		z = z,
		radius = radius,
		damageScale = damageScale,
		depth = depth,
		eventID = eventID,
		split = profile and profile.split,
		burnZone = profile and profile.burnZone,
		frame = frame + limits.warningFrames,
	}
	return true
end

local getEnemyTargets
local getNearestEnemy

local function launchMeteorStrike(ownerID, teamID, x, z, frame)
	local autoLevel = spGetUnitRulesParam(ownerID, "roguelike_shop_meteor_weapon_level") or 0
	local automatic = autoLevel > 0
	local interval = automatic and max(1.8, 2.8 - (autoLevel - 1) * 0.2)
		or getUpgrade(ownerID, "meteor", "interval")
	if frame < (nextMeteorFrame[ownerID] or 0) then
		return false
	end
	local count = automatic and (autoLevel >= 3 and 2 or 1) or getUpgrade(ownerID, "meteor", "count")
	local multishotCount = tonumber(spGetUnitRulesParam(ownerID, "roguelike_multishot_count")) or 1
	count = min(limits.maxMeteorProjectiles or 9, count + max(0, multishotCount - 1))
	local radius = automatic and (130 + (autoLevel - 1) * 15) or getUpgrade(ownerID, "meteor", "radius")
	local damageScale = automatic and (1 + (autoLevel - 1) * 0.18) or 1
	local split = automatic and autoLevel >= 4 or getUpgrade(ownerID, "meteor", "split") >= 1
	local burnZone = automatic and autoLevel >= 2
	local targets = getEnemyTargets(teamID, x, z, definitions.testWeapons.meteor.command.range)
	count = min(count, #targets)
	if count <= 0 then
		return false
	end
	local queue = pendingMeteors[ownerID]
	if (queue and #queue or 0) + count > limits.maxPendingMeteorsPerPlayer then
		return false
	end
	nextMeteorFrame[ownerID] = frame + floor(interval * gameSpeed + 0.5)
	local eventID = newEvent(ownerID, teamID, meteorPayloadWeaponDefID)
	for index = 1, count do
		local target = targets[index]
		enqueueMeteor(ownerID, teamID, target.x, target.z, 0, damageScale, frame, eventID,
			{ radius = radius, split = split, burnZone = burnZone })
	end
	return true
end

getEnemyTargets = function(teamID, x, z, searchRadius)
	local targets = {}
	local maxDistance = searchRadius * searchRadius
	for _, unitID in ipairs(spGetUnitsInCylinder(x, z, searchRadius) or {}) do
		local teamID2 = spGetUnitTeam(unitID)
		if teamID2 and not spAreTeamsAllied(teamID, teamID2) then
			local ux, _, uz = spGetUnitPosition(unitID)
			if ux then
				local dx, dz = ux - x, uz - z
				local distance = dx * dx + dz * dz
				if distance <= maxDistance then
					targets[#targets + 1] = { id = unitID, x = ux, z = uz, distance = distance }
				end
			end
		end
	end
	table.sort(targets, function(a, b)
		if a.distance == b.distance then return a.id < b.id end
		return a.distance < b.distance
	end)
	return targets
end

getNearestEnemy = function(teamID, x, z, searchRadius)
	local targets = getEnemyTargets(teamID, x, z, searchRadius)
	return targets[1] and targets[1].id
end

local function spawnChild(parentID, x, y, z, angle, depth, damageScale, frame)
	local parent = projectileState[parentID]
	if not parent or depth > min(limits.maxDepth, getUpgrade(parent.ownerID, "splitter", "depth")) then
		return false
	end
	local ownerCount = activeByOwner[parent.ownerID] or 0
	if ownerCount >= limits.maxActivePerPlayer or activeProjectileCount >= limits.maxActiveProjectiles then
		return false
	end
	if not reserveSpawn(frame) then return false end
	local defID = parent.weaponDefID
	if parent.kind == "meteor" then
		defID = parent.payloadDefID
	end
	local velocityX, velocityY, velocityZ = spGetProjectileVelocity(parentID)
	local horizontalSpeed = sqrt(velocityX * velocityX + velocityZ * velocityZ)
	local spread = pi * 2 * (angle - 1) / max(parent.childCount, 1)
	local speed = max(sqrt(velocityX * velocityX + velocityY * velocityY + velocityZ * velocityZ), 12)
	local params = {
		pos = { x, y, z },
		speed = { cos(spread) * horizontalSpeed, velocityY, sin(spread) * horizontalSpeed },
		owner = parent.ownerID,
		team = parent.teamID,
		ttl = gameSpeed * 8,
	}
	if params.speed[1] == 0 and params.speed[3] == 0 then
		params.speed[1] = cos(spread) * speed * 0.45
		params.speed[3] = sin(spread) * speed * 0.45
	end
	if parent.kind == "meteor" then
		params.gravity = -Game.gravity / (gameSpeed * gameSpeed)
		params.model = "meteor.s3o"
		params.cegTag = "roguelike-meteortrail"
	end
	spawnContext = {
		kind = parent.kind,
		ownerID = parent.ownerID,
		teamID = parent.teamID,
		weaponDefID = defID,
		payloadDefID = parent.payloadDefID,
		depth = depth,
		damageScale = damageScale,
		baseDamage = parent.baseDamage,
		radius = parent.radius,
		childCount = parent.childCount,
		mode = parent.mode,
		originX = x,
		originZ = z,
		firedFrame = frame,
		eventID = parent.eventID,
		effectEntries = {},
		procCoefficient = 0,
		procHit = false,
	}
	local childID = spSpawnProjectile(defID, params)
	if childID then
		registerProjectile(childID, spawnContext)
		if projectileState[childID] and getUpgrade(parent.ownerID, "splitter", "homing") >= 1 then
			local targetID = getNearestEnemy(parent.teamID, x, z, 1200)
			if targetID then
				spSetProjectileTarget(childID, targetID, targetUnit)
			end
		end
	end
	spawnContext = nil
	return childID ~= nil
end

local function splitProjectile(projectileID, frame, impactSplit)
	local state = projectileState[projectileID]
	if not state or state.depth >= min(limits.maxDepth, getUpgrade(state.ownerID, "splitter", "depth")) then
		return false
	end
	local x, y, z = spGetProjectilePosition(projectileID)
	if not x then
		return false
	end
	local childCount = state.childCount or getUpgrade(state.ownerID, state.kind, "count")
	local scale = state.damageScale * getUpgrade(state.ownerID, state.kind, "damageFalloff")
	local spawned = false
	for childIndex = 1, childCount do
		if (activeByOwner[state.ownerID] or 0) < limits.maxActivePerPlayer then
			spawned = spawnChild(projectileID, x, y, z, childIndex, state.depth + 1, scale, frame) or spawned
		end
	end
	if spawned and not impactSplit then
		spDeleteProjectile(projectileID)
		clearProjectile(projectileID)
	end
	return spawned
end

local function processMeteorQueue(frame)
	local ownerIDs = {}
	for ownerID in pairs(pendingMeteors) do
		ownerIDs[#ownerIDs + 1] = ownerID
	end
	table.sort(ownerIDs)
	for _, ownerID in ipairs(ownerIDs) do
		local queue = pendingMeteors[ownerID]
		local index = 1
		while index <= #queue do
			local meteor = queue[index]
			if frame >= meteor.frame then
				-- Keep the due meteor queued until there is room and an actual spawn succeeds.
				if not meteor.payloadDefID or (activeByOwner[ownerID] or 0) >= limits.maxActivePerPlayer
					or activeProjectileCount >= limits.maxActiveProjectiles or not reserveSpawn(frame) then
					break
				end
				do
					local groundY = spGetGroundHeight(meteor.x, meteor.z)
					local params = {
						pos = { meteor.x, groundY + limits.meteorAltitude, meteor.z },
						speed = { 0, -limits.meteorSpeed, 0 },
						["end"] = { meteor.x, groundY, meteor.z },
						owner = meteor.ownerID,
						team = meteor.teamID,
						ttl = gameSpeed * 8,
						gravity = -Game.gravity / (gameSpeed * gameSpeed),
						model = "meteor.s3o",
						cegTag = "roguelike-meteortrail",
					}
					spawnContext = {
						kind = "meteor",
						ownerID = meteor.ownerID,
						teamID = meteor.teamID,
						weaponDefID = meteor.payloadDefID,
						payloadDefID = meteor.payloadDefID,
						depth = meteor.depth,
						damageScale = meteor.damageScale * getUpgrade(ownerID, "meteor", "damage"),
						baseDamage = 500,
						radius = meteor.radius,
						childCount = 2,
						mode = "impact",
						firedFrame = frame,
						eventID = meteor.eventID,
						effectEntries = definitions.projectileEffects and definitions.projectileEffects.meteor or {},
						procCoefficient = meteor.depth == 0 and 0.5 or 0,
						procHit = false,
						split = meteor.split or getUpgrade(ownerID, "meteor", "split") >= 1,
						burnZone = meteor.burnZone,
					}
					local projectileID = spSpawnProjectile(meteor.payloadDefID, params)
					if projectileID then
						registerProjectile(projectileID, spawnContext)
					end
					spawnContext = nil
					if projectileID and projectileState[projectileID] then
						table.remove(queue, index)
					else
						break
					end
				end
			else
				index = index + 1
			end
		end
		if #queue == 0 then
			pendingMeteors[ownerID] = nil
		end
	end
end

local function initializeOwner(ownerID)
	for effectID, upgrades in pairs(definitions.upgrades) do
		for key, schema in pairs(upgrades) do
			local param = "roguelike_effect_" .. effectID .. "_" .. key
			if spGetUnitRulesParam(ownerID, param) == nil then
				spSetUnitRulesParam(ownerID, param, schema.default, inLosAccess)
			end
		end
	end
end

local meteorCommandDescription = {
	id = CMD_ROGUELIKE_METEOR_STRIKE,
	type = CMDTYPE.ICON_MAP,
	name = definitions.testWeapons.meteor.command.name,
	action = "roguelike_meteor_strike",
	cursor = "cursorattack",
	texture = "LuaUI/Images/nuke.png",
	tooltip = "Call a meteor down onto the selected ground position",
	queueing = false,
}

local function addMeteorCommand(unitID, unitDefID)
	if not testEnabled then return end
	if isArmCommander(unitDefID) then return end
	local unitDef = UnitDefs[unitDefID]
	if not (unitDef and unitDef.customParams and unitDef.customParams.iscommander)
		or spFindUnitCmdDesc(unitID, CMD_ROGUELIKE_METEOR_STRIKE) then
		return
	end
	spInsertUnitCmdDesc(unitID, 1, meteorCommandDescription)
end

function gadget:Initialize()
	local meteorPayload = WeaponDefNames.roguelike_test_meteor_payload
	meteorPayloadWeaponDefID = meteorPayload and meteorPayload.id
	if not meteorPayloadWeaponDefID then
		Spring.Log(gadget:GetInfo().name, LOG.ERROR, "Roguelike meteor payload WeaponDef did not load")
	end
	if testEnabled then
		gadgetHandler:RegisterCMDID(CMD_ROGUELIKE_METEOR_STRIKE)
		gadgetHandler:RegisterAllowCommand(CMD_ROGUELIKE_METEOR_STRIKE)
	end
	if meteorPayloadWeaponDefID then
		payloadByWeaponDef[meteorPayloadWeaponDefID] = true
		Script.SetWatchWeapon(meteorPayloadWeaponDefID, true)
	end
	for weaponDefID, weaponDef in pairs(WeaponDefs) do
		local effect = weaponDef.customParams and weaponDef.customParams.roguelike_weapon_effect
		if testEnabled and effect == "splitter" then
			launcherByWeaponDef[weaponDefID] = effect
			Script.SetWatchWeapon(weaponDefID, true)
		elseif testEnabled and effect == "meteor_payload" then
			payloadByWeaponDef[weaponDefID] = true
			Script.SetWatchWeapon(weaponDefID, true)
		end
	end
	for _, commanderName in ipairs({ "armcom", "corcom", "legcom" }) do
		local commanderDef = UnitDefNames[commanderName]
		local unitDef = commanderDef and UnitDefs[commanderDef.id]
		for _, weapon in ipairs(unitDef and unitDef.weapons or {}) do
			local weaponDefID = weapon.weaponDef
			local weaponDef = weaponDefID and WeaponDefs[weaponDefID]
			if weaponDef and weaponDef.type ~= "Shield" then
				commanderProjectileByWeaponDef[weaponDefID] = true
				Script.SetWatchWeapon(weaponDefID, true)
			end
		end
	end
	for _, unitID in ipairs(Spring.GetAllUnits()) do
		local unitDefID = spGetUnitDefID(unitID)
		local unitDef = UnitDefs[unitDefID]
		if unitDef and unitDef.customParams and unitDef.customParams.iscommander then
			local _, _, _, isAI = Spring.GetTeamInfo(spGetUnitTeam(unitID))
			if not isAI then roguelikeCommanders[unitID] = true end
		end
		if testEnabled and not isArmCommander(unitDefID) and unitDef and unitDef.customParams and unitDef.customParams.iscommander then
			initializeOwner(unitID)
		end
		addMeteorCommand(unitID, unitDefID)
	end
	GG.RoguelikeWeaponEffects = {
		SetUpgrade = setUpgrade,
		GetUpgrade = getUpgrade,
		NewEvent = newEvent,
		RegisterHit = registerHitContext,
		OnHit = onHit,
		GetDamageAttribution = getDamageAttribution,
	}
end

function gadget:UnitCreated(unitID, unitDefID)
	local unitDef = UnitDefs[unitDefID]
	if unitDef and unitDef.customParams and unitDef.customParams.iscommander then
		local _, _, _, isAI = Spring.GetTeamInfo(spGetUnitTeam(unitID))
		if not isAI then roguelikeCommanders[unitID] = true end
	end
	if testEnabled and not isArmCommander(unitDefID) and unitDef and unitDef.customParams and unitDef.customParams.iscommander then
		initializeOwner(unitID)
	end
	addMeteorCommand(unitID, unitDefID)
end

function gadget:AllowCommand(unitID, unitDefID, unitTeam, cmdID, cmdParams, cmdOptions, cmdTag, playerID)
	if cmdID ~= CMD_ROGUELIKE_METEOR_STRIKE then
		return true
	end
	local unitDef = UnitDefs[unitDefID]
	if not (unitDef and unitDef.customParams and unitDef.customParams.iscommander) or not playerID then
		return false
	end
	local _, active, spectator, playerTeam = Spring.GetPlayerInfo(playerID, false)
	if not active or spectator or playerTeam ~= unitTeam or not cmdParams or #cmdParams < 3 then
		return false
	end
	local x, z = tonumber(cmdParams[1]), tonumber(cmdParams[3])
	if not x or not z or not Spring.IsPosInMap(x, z) then
		return false
	end
	local unitX, _, unitZ = spGetUnitPosition(unitID)
	local range = definitions.testWeapons.meteor.command.range
	if not unitX or (unitX - x) * (unitX - x) + (unitZ - z) * (unitZ - z) > range * range then
		return false
	end
	launchMeteorStrike(unitID, unitTeam, x, z, spGetGameFrame())
	return false
end

function gadget:ProjectileCreated(projectileID, ownerID, weaponDefID)
	local def = WeaponDefs[weaponDefID]
	if def and def.customParams and def.customParams.roguelike_shop_item == "electric_orb" then
		local x, y, z = spGetProjectilePosition(projectileID)
		if x then
			local rangeMult = ownerID and spGetUnitRulesParam(ownerID, "roguelike_range_mult") or 1
			local range = (def.range or 560) * (tonumber(rangeMult) or 1)
			local teamID = spGetProjectileTeamID(projectileID) or (ownerID and spGetUnitTeam(ownerID))
			local damage = def.damages and tonumber(def.damages[0]) or 0
			electricOrbs[projectileID] = { x = x, y = y, z = z, distance = 0, range = range,
				ownerID = ownerID, teamID = teamID, weaponDefID = weaponDefID, damage = damage,
				targetNextFrame = {}, nextArcFrame = spGetGameFrame(),
				expires = spGetGameFrame() + math.ceil(range / 500 * gameSpeed) + gameSpeed }
		end
	end
	local effect = launcherByWeaponDef[weaponDefID] or (payloadByWeaponDef[weaponDefID] and "meteor_payload")
	if not ownerID then return end
	local unitDef = UnitDefs[spGetUnitDefID(ownerID)]
	local teamID = spGetUnitTeam(ownerID)
	if spawnContext then
		registerProjectile(projectileID, spawnContext)
	elseif effect == "splitter" then
		local weaponDef = WeaponDefs[weaponDefID]
		local originX, _, originZ = spGetProjectilePosition(projectileID)
		registerProjectile(projectileID, {
			kind = "splitter",
			ownerID = ownerID,
			teamID = spGetProjectileTeamID(projectileID) or teamID,
			weaponDefID = weaponDefID,
			depth = 0,
			damageScale = 1,
			baseDamage = (weaponDef.damages and tonumber(weaponDef.damages[0])) or 180,
			childCount = getUpgrade(ownerID, "splitter", "count"),
			mode = getSplitMode(ownerID),
			originX = originX,
			originZ = originZ,
			firedFrame = spGetGameFrame(),
			eventID = newEvent(ownerID, spGetProjectileTeamID(projectileID) or teamID, weaponDefID),
			effectEntries = definitions.projectileEffects and definitions.projectileEffects.splitter or {},
			procCoefficient = 0.5,
			procHit = false,
		})
	elseif commanderProjectileByWeaponDef[weaponDefID] then
		local weaponDef = WeaponDefs[weaponDefID]
		local customParams = weaponDef and weaponDef.customParams or {}
		local itemID = customParams.roguelike_shop_item
		local mapping = itemID and definitions.shopProjectileEffects[itemID]
		local unlocked = mapping and (spGetUnitRulesParam(ownerID, "roguelike_shop_" .. mapping.upgrade .. "_level") or 0) > 0
		if unlocked and not customParams.roguelike_custom_weapon then
			local originX, _, originZ = spGetProjectilePosition(projectileID)
			registerProjectile(projectileID, {
				kind = "commander_projectile", ownerID = ownerID, teamID = spGetProjectileTeamID(projectileID) or teamID,
				weaponDefID = weaponDefID, depth = 0, damageScale = 1,
				baseDamage = (weaponDef.damages and tonumber(weaponDef.damages[0])) or 0,
				originX = originX, originZ = originZ, firedFrame = spGetGameFrame(),
				eventID = newEvent(ownerID, spGetProjectileTeamID(projectileID) or teamID, weaponDefID),
				effectEntries = { { id = mapping.effect } },
				procCoefficient = mapping.procCoefficient or 0.5, procHit = false,
			})
		end
	end
	if testEnabled and unitDef and unitDef.customParams and unitDef.customParams.iscommander then
		initializeOwner(ownerID)
	end
end

function gadget:UnitDamaged(unitID, unitDefID, unitTeam, damage, paralyzer, weaponDefID, projectileID, attackerID)
	local state = projectileID and projectileState[projectileID]
	if not state and attackerID and damage > 0 and not paralyzer and roguelikeCommanders[attackerID] then
		local weaponDef = weaponDefID and WeaponDefs[weaponDefID]
		local params = weaponDef and weaponDef.customParams
		local mapping = params and definitions.shopProjectileEffects[params.roguelike_shop_item]
		if weaponDef and weaponDef.type == "BeamLaser" and mapping
			and not params.roguelike_custom_weapon
			and (spGetUnitRulesParam(attackerID, "roguelike_shop_" .. mapping.upgrade .. "_level") or 0) > 0 then
			local teamID = spGetUnitTeam(attackerID)
			if not teamID or spAreTeamsAllied(teamID, unitTeam) then return end
			local frame = spGetGameFrame()
			local lastByWeapon = beamLastProcFrame[attackerID] or {}
			local interval = max(1, floor((weaponDef.reload or 1) * gameSpeed * 0.75))
			if frame - (lastByWeapon[weaponDefID] or -interval) < interval then return end
			lastByWeapon[weaponDefID] = frame
			beamLastProcFrame[attackerID] = lastByWeapon
			local x, _, z = spGetUnitPosition(unitID)
			if teamID and x then
				local eventID = newEvent(attackerID, teamID, weaponDefID)
				local baseDamage = (weaponDef.damages and tonumber(weaponDef.damages[0])) or 0
				local entries = { { id = mapping.effect } }
				local procCoefficient = mapping.procCoefficient or 0.5
				registerHitContext(attackerID, teamID, weaponDefID, unitID, x, z,
					baseDamage, eventID, entries, procCoefficient)
				onHit(attackerID, teamID, "commander_beam", weaponDefID, unitID, x, z,
					baseDamage, eventID, entries, procCoefficient, 0)
			end
		end
		return
	end
	if not state or state.procHit or state.depth > 0 or damage <= 0 or paralyzer then return end
	state.procHit = true
	local x, _, z = spGetUnitPosition(unitID)
	-- UnitDamaged receives final damage. Feeding it back through AddUnitDamage
	-- would apply role/shop growth a second time; use the unmodified weapon basis.
	local procDamage = state.baseDamage * (state.damageScale or 1)
	registerHitContext(state.ownerID, state.teamID, weaponDefID, unitID, x, z, procDamage,
		state.eventID, state.effectEntries, state.procCoefficient)
	onHit(state.ownerID, state.teamID, state.kind, weaponDefID, unitID, x, z,
		procDamage, state.eventID, state.effectEntries, state.procCoefficient, state.depth)
end

function gadget:Explosion(weaponDefID, x, y, z, ownerID, projectileID)
	local state = projectileID and projectileState[projectileID]
	if not state then
		return
	end
	if state.kind == "meteor" then
		if state.burnZone then
			local burnConfig = definitions.effectRegistry.burn_zone
			enqueueArea("burn_zone", burnConfig, state.ownerID, state.teamID,
				state.weaponDefID, x, z, state.baseDamage * state.damageScale, spGetGameFrame())
		end
		if state.split and state.depth == 0 then
			state.childCount = 2
			local phase = ((state.ownerID + projectileID) % 97) * (2 * pi / 97)
			local spread = getUpgrade(state.ownerID, "meteor", "radius") * 0.5
			for childIndex = 1, state.childCount do
				local angle = phase + (childIndex - 1) * pi
				enqueueMeteor(state.ownerID, state.teamID,
					x + cos(angle) * spread, z + sin(angle) * spread, 1, 0.55, spGetGameFrame(), state.eventID)
			end
		end
	elseif state.kind == "splitter" and state.mode == "impact" then
		splitProjectile(projectileID, spGetGameFrame(), true)
	end
end

function gadget:ProjectileDestroyed(projectileID)
	clearProjectile(projectileID)
end

function gadget:UnitPreDamaged(unitID, unitDefID, unitTeam, damage, paralyzer, weaponDefID, projectileID, attackerID)
	local state = projectileID and projectileState[projectileID]
	if not state then
		return damage
	end
	local targetTeam = spGetUnitTeam(unitID)
	if targetTeam and state.teamID and spAreTeamsAllied(targetTeam, state.teamID) then
		return 0
	end
	if attackerID == unitID then
		return 0
	end
	return damage * (state.damageScale or 1)
end

function gadget:GameFrame(frame)
	-- ???????????????????????????
	local expired = {}
	local aura = definitions.electricOrbAura
	for id, orb in pairs(electricOrbs) do
		local x, y, z = spGetProjectilePosition(id)
		if x then
			local dx, dy, dz = x - orb.x, y - orb.y, z - orb.z
			orb.distance = orb.distance + sqrt(dx * dx + dy * dy + dz * dz)
			orb.x, orb.y, orb.z = x, y, z
			if aura and frame >= orb.nextArcFrame then
				orb.nextArcFrame = frame + aura.tickFrames
				local radiusSq = aura.radius * aura.radius
				for _, targetID in ipairs(spGetUnitsInCylinder(x, z, aura.radius) or {}) do
					local targetTeam = spGetUnitTeam(targetID)
					local nextHit = orb.targetNextFrame[targetID] or 0
					if targetTeam and orb.teamID and not spAreTeamsAllied(orb.teamID, targetTeam)
						and frame >= nextHit and spValidUnitID(targetID) then
						local tx, ty, tz = spGetUnitPosition(targetID)
						if tx and ty and tz then
							local ax, ay, az = tx - x, ty - y, tz - z
							if ax * ax + ay * ay + az * az <= radiusSq then
								local arcDamage = orb.damage * aura.damageFraction
								if dealProcDamage(orb.ownerID, orb.teamID, orb.weaponDefID, targetID, arcDamage) then
									orb.targetNextFrame[targetID] = frame + aura.tickFrames
									for step = 1, 3 do
										local fraction = step / 3
										spSpawnCEG("roguelike-electric-orb-chain",
											x + ax * fraction, y + ay * fraction, z + az * fraction, 0, 1, 0)
									end
								end
							end
						end
					end
				end
			end
		end
		if not x or orb.distance >= orb.range or frame >= orb.expires then expired[#expired + 1] = id end
	end
	table.sort(expired)
	for _, id in ipairs(expired) do
		electricOrbs[id] = nil
		if spGetProjectilePosition(id) then spDeleteProjectile(id) end
	end
	-- Kill contexts are only needed while the damage event can synchronously destroy its target.
	pendingKillContexts = {}
	processMeteorQueue(frame)
	processAreaStates(frame)
	if frame % 15 == 0 then
		local ownerIDs = {}
		for ownerID in pairs(roguelikeCommanders) do ownerIDs[#ownerIDs + 1] = ownerID end
		table.sort(ownerIDs)
		for _, ownerID in ipairs(ownerIDs) do
			if not spValidUnitID(ownerID) then
				roguelikeCommanders[ownerID] = nil
			elseif (spGetUnitRulesParam(ownerID, "roguelike_shop_meteor_weapon_level") or 0) > 0
				and frame >= (nextMeteorFrame[ownerID] or 0) then
				local ownerX, _, ownerZ = spGetUnitPosition(ownerID)
				local teamID = spGetUnitTeam(ownerID)
				if ownerX then
					launchMeteorStrike(ownerID, teamID, ownerX, ownerZ, frame)
				end
			end
		end
	end
	if frame % (10 * gameSpeed) == 0 then
		for _, unitID in ipairs(Spring.GetAllUnits()) do
			if spGetUnitRulesParam(unitID, "roguelike_level") then
				spSetUnitRulesParam(unitID, "roguelike_effect_proc_events", effectCounters.procEvents, inLosAccess)
				spSetUnitRulesParam(unitID, "roguelike_effect_proc_rejected", effectCounters.procChainRejected, inLosAccess)
				spSetUnitRulesParam(unitID, "roguelike_effect_active_zones", effectCounters.activeZones, inLosAccess)
				spSetUnitRulesParam(unitID, "roguelike_effect_area_hits", effectCounters.areaHits, inLosAccess)
			end
		end
	end
	for eventID, event in pairs(events) do
		if frame - event.frame > 10 * gameSpeed then events[eventID] = nil end
	end
	local projectileIDs = {}
	for projectileID in pairs(projectileState) do
		projectileIDs[#projectileIDs + 1] = projectileID
	end
	table.sort(projectileIDs)
	for _, projectileID in ipairs(projectileIDs) do
		local state = projectileState[projectileID]
		if state.kind == "splitter" and state.mode ~= "impact" and state.depth < min(limits.maxDepth, getUpgrade(state.ownerID, "splitter", "depth")) then
			local x, _, z = spGetProjectilePosition(projectileID)
			if x then
				local elapsed = frame - state.firedFrame
				local dx, dz = x - (state.originX or x), z - (state.originZ or z)
				local distance = sqrt(dx * dx + dz * dz)
				local shouldSplit = state.mode == "timed" and elapsed >= limits.timedSplitFrames
					or state.mode == "inflight" and distance >= limits.inFlightSplitDistance
				if shouldSplit then
					splitProjectile(projectileID, frame)
				end
			end
		end
	end
end

function gadget:UnitDestroyed(unitID, unitDefID, unitTeam, attackerID, attackerDefID, attackerTeam, weaponDefID)
	beamLastProcFrame[unitID] = nil
	local killContext = pendingKillContexts[unitID]
	pendingKillContexts[unitID] = nil
	if killContext and killContext.frame == spGetGameFrame() and attackerID == killContext.ownerID
		and (not weaponDefID or weaponDefID == killContext.weaponDefID) then
		killContext.targetID = unitID
		onKill(killContext)
	end
	roguelikeCommanders[unitID] = nil
	pendingMeteors[unitID] = nil
	nextMeteorFrame[unitID] = nil
	for eventID, event in pairs(events) do
		if event.ownerID == unitID then events[eventID] = nil end
	end
	for key in pairs(effectCooldowns) do
		if key:sub(1, #tostring(unitID) + 1) == tostring(unitID) .. ":" then effectCooldowns[key] = nil end
	end
	for index = #areaStates, 1, -1 do
		local state = areaStates[index]
		if state.ownerID == unitID then
			if state.effectID == "burn_zone" then effectCounters.activeZones = max(0, effectCounters.activeZones - 1) end
			table.remove(areaStates, index)
		end
	end
	local ownedProjectiles = {}
	for projectileID, state in pairs(projectileState) do
		if state.ownerID == unitID then ownedProjectiles[#ownedProjectiles + 1] = projectileID end
	end
	table.sort(ownedProjectiles)
	for _, projectileID in ipairs(ownedProjectiles) do
		spDeleteProjectile(projectileID)
		clearProjectile(projectileID)
	end
end
