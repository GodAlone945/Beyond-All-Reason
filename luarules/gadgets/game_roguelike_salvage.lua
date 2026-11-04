--------------------------------------------------------------------------------
-- [SYNCED 权威模块：敌军残骸吸收与金属奖励]
--
-- 本模块把“敌军死亡来源 → 其后创建的残骸 Feature”串成白名单，只允许吸收
-- Roguelike 敌军留下的合法残骸，随后销毁 Feature 并向玩家队伍发放金属。
-- 指挥官周期扫描调用本模块内部入口；无人机通过
-- GG.Roguelike.AbsorbWrecksForUnit 复用同一白名单和奖励公式。
--
-- 它读取 Upgrades 写入的回收倍率/半径 RulesParam，自己持有 Feature 白名单与
-- 累计回收量；UI 只能读取结果，不能指定奖励。详见 doc/RoguelikeArchitecture.md。
--------------------------------------------------------------------------------
local gadget = gadget ---@type Gadget

function gadget:GetInfo()
	return {
		name      = "Roguelike Wreck Absorption",
		desc      = "Converts nearby enemy wrecks into roguelike shop metal",
		author    = "GodAlone945",
		date      = "2026",
		license   = "GNU GPL, v2 or later",
		layer     = 2,
		enabled   = true,
	}
end

local roguelikeOption = Spring.GetModOptions().roguelike_mode
if roguelikeOption ~= true and roguelikeOption ~= 1 and roguelikeOption ~= "1" and roguelikeOption ~= "true" then
	return false
end
local coopOption = Spring.GetModOptions().roguelike_coop
local COOP_ENABLED = coopOption == true or coopOption == 1 or coopOption == "1" or coopOption == "true"

if not gadgetHandler:IsSyncedCode() then
	return
end

local spAddTeamResource      = Spring.AddTeamResource
local spAreTeamsAllied       = Spring.AreTeamsAllied
local spDestroyFeature       = Spring.DestroyFeature
local spGetAllUnits          = Spring.GetAllUnits
local spGetFeatureResources  = Spring.GetFeatureResources
local spGetFeaturesInCylinder = Spring.GetFeaturesInCylinder
local spGetGameFrame         = Spring.GetGameFrame
local spGetTeamInfo          = Spring.GetTeamInfo
local spGetUnitDefID         = Spring.GetUnitDefID
local spGetUnitPosition      = Spring.GetUnitPosition
local spGetUnitRulesParam    = Spring.GetUnitRulesParam
local spGetUnitTeam          = Spring.GetUnitTeam
local spSetUnitRulesParam    = Spring.SetUnitRulesParam
local spValidFeatureID       = Spring.ValidFeatureID
local spValidUnitID          = Spring.ValidUnitID

local BASE_ABSORB_RADIUS = 220
local ABSORB_RADIUS_PER_UPGRADE = 20
local BASE_ABSORB_INTERVAL = 10
local SOURCE_TIMEOUT = Game.gameSpeed * 10
local INLOS_ACCESS = { inlos = true }

local playerUnitID
local playerTeamID
local eligibleSources = {} -- destroyed enemy unitID -> expiry frame
local eligibleFeatures = {} -- featureID -> true
local recentDgunDamageFrame = {} -- unitID -> frame, used to omit D-Gun kills from salvage
local totalSalvagedMetal = 0
local salvagedByTeam = {}

local function isDgunWeapon(weaponDefID)
	local weaponDef = weaponDefID and WeaponDefs[weaponDefID]
	if not weaponDef then return false end
	if weaponDef.type == "DGun" or weaponDef.manualFire
		or weaponDef.weapontype == "DGun" or weaponDef.commandfire then return true end
	local name = string.lower(tostring(weaponDef.name or "")):gsub("[^%w]", "")
	return name:find("dgun", 1, true) ~= nil
end

local function isCommander(unitDefID)
	local unitDef = unitDefID and UnitDefs[unitDefID]
	return unitDef and unitDef.customParams and unitDef.customParams.iscommander
end

local function isHumanTeam(teamID)
	local _, _, _, isAI = spGetTeamInfo(teamID)
	return not isAI
end

local function findCommander()
	if GG.Roguelike and GG.Roguelike.playerUnitID and spValidUnitID(GG.Roguelike.playerUnitID) then
		playerUnitID = GG.Roguelike.playerUnitID
		playerTeamID = GG.Roguelike.playerTeamID or spGetUnitTeam(playerUnitID)
		return
	end

	for _, unitID in ipairs(spGetAllUnits()) do
		local teamID = spGetUnitTeam(unitID)
		if isCommander(spGetUnitDefID(unitID)) and isHumanTeam(teamID) then
			playerUnitID = unitID
			playerTeamID = teamID
			return
		end
	end
end

-- 所有回收入口共享同一份 synced 白名单与奖励结算；maxFeatures 用于限制
-- 每架无人机每秒最多吸收一个残骸，避免无人机数量增加后瞬间清空大范围战场。
local function absorbWrecksAt(x, z, absorbRadius, maxFeatures)
	if not x or not z or not playerTeamID then return 0 end
	local salvageMultiplier = spGetUnitRulesParam(playerUnitID, "roguelike_salvage_mult") or 1
	local absorbed = 0
	for _, featureID in ipairs(spGetFeaturesInCylinder(x, z, absorbRadius)) do
		if eligibleFeatures[featureID] and spValidFeatureID(featureID) then
			local metal = spGetFeatureResources(featureID) or 0
			local reward = math.max(0, math.floor(metal * salvageMultiplier + 0.5))
			eligibleFeatures[featureID] = nil
			spDestroyFeature(featureID)
			if reward > 0 then
				spAddTeamResource(playerTeamID, "metal", reward)
				totalSalvagedMetal = (salvagedByTeam[playerTeamID] or 0) + reward
				salvagedByTeam[playerTeamID] = totalSalvagedMetal
				spSetUnitRulesParam(playerUnitID, "roguelike_last_salvage", reward, INLOS_ACCESS)
				spSetUnitRulesParam(playerUnitID, "roguelike_salvaged_metal", totalSalvagedMetal, INLOS_ACCESS)
			end
			absorbed = absorbed + 1
			if maxFeatures and absorbed >= maxFeatures then
				break
			end
		end
	end
	return absorbed
end

local function absorbNearbyWrecks()
	if not playerUnitID or not spValidUnitID(playerUnitID) or not playerTeamID then return end
	local x, _, z = spGetUnitPosition(playerUnitID)
	if not x then return end

	-- Upgrades 负责写入权威升级次数；Salvage 只读取该 synced RulesParam
	-- 并派生查询半径，避免两个 Gadget 分别保存升级进度而产生状态偏差。
	local upgradeCount = spGetUnitRulesParam(playerUnitID, "roguelike_upgrade_count") or 0
	-- 新版由 Upgrades 在选卡时立即写入精确半径；旧存档/缺失参数仍使用原公式兜底。
	local absorbRadius = spGetUnitRulesParam(playerUnitID, "roguelike_salvage_radius")
		or (BASE_ABSORB_RADIUS + math.floor(upgradeCount) * ABSORB_RADIUS_PER_UPGRADE)
	spSetUnitRulesParam(playerUnitID, "roguelike_salvage_radius", absorbRadius, INLOS_ACCESS)
	absorbWrecksAt(x, z, absorbRadius)
end

-- Orbit Drones 调用该 GG 接口提出回收请求；这里验证单位归属后才执行权威结算。
local function absorbWrecksForUnit(unitID, absorbRadius, maxFeatures)
	if not unitID or not spValidUnitID(unitID) then return 0 end
	local unitTeam = spGetUnitTeam(unitID)
	if COOP_ENABLED then
		local state = GG.Roguelike and GG.Roguelike.teams and GG.Roguelike.teams[unitTeam]
		playerUnitID = state and state.commanderUnitID
		playerTeamID = state and unitTeam
	end
	if not playerUnitID or not spValidUnitID(playerUnitID) or not playerTeamID then return 0 end
	if unitTeam ~= playerTeamID then return 0 end
	local x, _, z = spGetUnitPosition(unitID)
	if not x then return 0 end
	return absorbWrecksAt(x, z, math.max(0, tonumber(absorbRadius) or 0),
		math.max(1, math.floor(tonumber(maxFeatures) or 1)))
end

function gadget:Initialize()
	findCommander()
	GG.Roguelike = GG.Roguelike or {}
	GG.Roguelike.AbsorbWrecksForUnit = absorbWrecksForUnit
end

function gadget:UnitCreated(unitID, unitDefID, unitTeam)
	if not COOP_ENABLED and isCommander(unitDefID) and isHumanTeam(unitTeam) and (not playerTeamID or unitTeam == playerTeamID) then
		playerUnitID = unitID
		playerTeamID = unitTeam
	end
end

function gadget:UnitDestroyed(unitID, unitDefID, unitTeam)
	if isCommander(unitDefID) and isHumanTeam(unitTeam) then
		playerUnitID = nil
		return
	end
	-- UnitDestroyed 发生时残骸 Feature 往往尚未创建，因此先短暂记录死亡来源；
	-- FeatureCreated 再用 sourceID 绑定，避免吸收地图初始残骸或友军残骸。
	local dgunFrame = recentDgunDamageFrame[unitID]
	recentDgunDamageFrame[unitID] = nil
	local killedByDgun = dgunFrame and spGetGameFrame() - dgunFrame <= 1
	if not killedByDgun and playerTeamID and unitTeam and not spAreTeamsAllied(unitTeam, playerTeamID) then
		eligibleSources[unitID] = spGetGameFrame() + SOURCE_TIMEOUT
	end
end

function gadget:UnitPreDamaged(unitID, unitDefID, unitTeam, damage, paralyzer, weaponDefID)
	if damage and damage > 0 and isDgunWeapon(weaponDefID) then
		recentDgunDamageFrame[unitID] = spGetGameFrame()
	end
end

-- BAR passes the destroyed source unit ID directly on current engines. The
-- existing unit_corpse_link gadget supplies it on older engines as well.
function gadget:FeatureCreated(featureID, allyTeam, sourceID)
	-- sourceID 必须命中上一步的短期白名单；客户端无法自行把任意 Feature
	-- 标记为可兑换资源。
	if sourceID and eligibleSources[sourceID] then
		eligibleFeatures[featureID] = true
		eligibleSources[sourceID] = nil
	end
end

function gadget:FeaturePreDamaged(featureID, featureDefID, featureTeam, damage, weaponDefID)
	if eligibleFeatures[featureID] and not isDgunWeapon(weaponDefID) then
		return 0, 0
	end
end

function gadget:FeatureDestroyed(featureID)
	eligibleFeatures[featureID] = nil
end

function gadget:GameFrame(frame)
	if COOP_ENABLED then
		for _, teamID in ipairs(GG.Roguelike and GG.Roguelike.teamIDs or {}) do
			local state = GG.Roguelike.teams and GG.Roguelike.teams[teamID]
			local uid = state and state.commanderUnitID
			if uid and spValidUnitID(uid) then
				playerUnitID, playerTeamID = uid, teamID
				local speedMultiplier = spGetUnitRulesParam(uid, "roguelike_salvage_speed_mult") or 1
				local absorbInterval = math.max(1, math.floor(BASE_ABSORB_INTERVAL / speedMultiplier + 0.5))
				if frame % absorbInterval == 0 then absorbNearbyWrecks() end
			end
		end
	else
		if not playerUnitID or not spValidUnitID(playerUnitID) then findCommander() end
		if playerUnitID and spValidUnitID(playerUnitID) then
			local speedMultiplier = spGetUnitRulesParam(playerUnitID, "roguelike_salvage_speed_mult") or 1
			local absorbInterval = math.max(1, math.floor(BASE_ABSORB_INTERVAL / speedMultiplier + 0.5))
			if frame % absorbInterval == 0 then absorbNearbyWrecks() end
		end
	end

	if frame % Game.gameSpeed == 0 then
		for unitID, damageFrame in pairs(recentDgunDamageFrame) do
			if damageFrame < frame - 1 then
				recentDgunDamageFrame[unitID] = nil
			end
		end
		for sourceID, expiryFrame in pairs(eligibleSources) do
			if expiryFrame < frame then
				eligibleSources[sourceID] = nil
			end
		end
	end
end

function gadget:Shutdown()
	if GG.Roguelike and GG.Roguelike.AbsorbWrecksForUnit == absorbWrecksForUnit then
		GG.Roguelike.AbsorbWrecksForUnit = nil
	end
end
