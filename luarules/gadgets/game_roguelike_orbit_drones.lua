--------------------------------------------------------------------------------
-- [SYNCED 权威模块：轨道无人机生命周期与任务状态机]
--
-- 本模块负责无人机等级、生成/补位、MoveCtrl 环绕、目标选择、残骸吸收、
-- 扣电修复和成长倍率。UnitDef 只定义模型与武器；实际优先级由这里统一决定：
-- 紧急修复（指挥官低于 45%，持续至 60%）→ 攻敌 → 吸铁 → 常规修复 → 环绕。
--
-- Upgrades 通过 GG.Roguelike.AddDroneLevel / SetSummonGrowthMultipliers 写入等级
-- 与成长，本模块通过 Salvage 的 GG 接口吸收残骸。修复粒子只在实际扣电并回血
-- 后生成，因此表现不能反过来决定游戏状态。详见 doc/RoguelikeArchitecture.md。
--------------------------------------------------------------------------------
local gadget = gadget ---@type Gadget

function gadget:GetInfo()
    return {
        name      = "Roguelike Orbit Drones",
        desc      = "Spawns invulnerable orbiting drones for the commander",
        author    = "GodAlone945",
        date      = "2025",
        license   = "GNU GPL, v2 or later",
        layer     = 0,
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

--------------------------------------------------------------------------------
-- API 缓存

local spCreateUnit          = Spring.CreateUnit
local spDestroyUnit         = Spring.DestroyUnit
local spGetUnitPosition     = Spring.GetUnitPosition
local spSetUnitPosition     = Spring.SetUnitPosition
local spGetUnitDefID        = Spring.GetUnitDefID
local spGetUnitTeam         = Spring.GetUnitTeam
local spGetUnitHealth       = Spring.GetUnitHealth
local spSetUnitHealth       = Spring.SetUnitHealth
local spSetUnitMaxHealth    = Spring.SetUnitMaxHealth
local spSetUnitNoSelect     = Spring.SetUnitNoSelect
local spSetUnitNoMinimap    = Spring.SetUnitNoMinimap
local spSetUnitNeutral      = Spring.SetUnitNeutral
local spGiveOrderToUnit     = Spring.GiveOrderToUnit
local spSetUnitMaxRange     = Spring.SetUnitMaxRange
local spSetUnitRulesParam   = Spring.SetUnitRulesParam
local spSetUnitWeaponState  = Spring.SetUnitWeaponState
local spValidUnitID         = Spring.ValidUnitID
local spGetUnitNearestEnemy = Spring.GetUnitNearestEnemy
local spSpawnCEG            = Spring.SpawnCEG
local spEcho                = Spring.Echo

local mcEnable              = Spring.MoveCtrl.Enable
local mcDisable             = Spring.MoveCtrl.Disable
local mcSetPosition         = Spring.MoveCtrl.SetPosition
local mcSetVelocity         = Spring.MoveCtrl.SetVelocity
local mcIsEnabled           = Spring.MoveCtrl.IsEnabled

local mSin   = math.sin
local mCos   = math.cos
local mPi    = math.pi
local mMin   = math.min
local mMax   = math.max
local mFloor = math.floor
local mSqrt  = math.sqrt

local GAME_SPEED = Game.gameSpeed
local INLOS_ACCESS = { inlos = true }
local CMD_FIGHT  = CMD.FIGHT
local CMD_GUARD  = CMD.GUARD
local CMD_STOP   = CMD.STOP
local CMD_ATTACK = CMD.ATTACK
local SEARCH_RADIUS = 800 -- 与 Roguelike 无人机视野一致，避免搜索半径大于可见范围
local WRECK_SEARCH_RADIUS = 260
local EMERGENCY_REPAIR_START = 0.45
local EMERGENCY_REPAIR_STOP = 0.60
local REPAIR_MAX_HEALTH_FRACTION_PER_DRONE = 0.006 -- 每架每秒修复指挥官最大生命的 0.6%
local ENERGY_PER_REPAIR_HEALTH = 0.75
local REPAIR_EFFECT_INTERVAL = 5

--------------------------------------------------------------------------------
-- 阵营→无人机映射

local FACTION_DRONE_MAP = {
    armada = "arm_electric_drone",
    cortex = "arm_fire_drone",
    legion = "leg_laser_drone",
}

-- 从 unitDef 推断阵营
local function getFaction(unitDefID)
    local ud = UnitDefs[unitDefID]
    if not ud then return nil end
    local name = ud.name or ""
    -- BAR 的指挥官命名: armcom=armada, corcom=cortex, legcom=legion
    if name == "armcom" or name == "armcomcon" or name == "armcomnew" then return "armada" end
    if name == "corcom" or name == "corcomcon" then return "cortex" end
    if name == "legcom" then return "legion" end
    -- 也检查 side
    if ud.customParams and ud.customParams.side then
        local side = ud.customParams.side:lower()
        if side == "armada" or side == "arm" then return "armada" end
        if side == "cortex" or side == "cor" then return "cortex" end
        if side == "legion" or side == "leg" then return "legion" end
    end
    return nil
end

--------------------------------------------------------------------------------
-- 配置

local ORBIT_RADIUS     = 150   -- 轨道半径
local ORBIT_HEIGHT     = 120    -- 悬浮高度
local ORBIT_SPEED_BASE = 1.2   -- 基础角速度（弧度/秒）
local DRONE_PER_LEVEL  = 2     -- 每级升级增加的无人机数
local MAX_DRONES       = 8     -- 最大无人机数

--------------------------------------------------------------------------------
-- 状态

local playerUnitID = nil
local playerFaction = nil
local activeDrones = {}   -- { [unitID] = { angle, level, ... } }
local droneLevel = 0       -- 当前无人机等级（0=未解锁）
local totalAngleOffset = 0 -- 全局旋转角
local emergencyRepairActive = false
local repairEffectUntilFrame = -1
local summonGrowth = {
    health = 1,
    move = 1,
    damage = 1,
    reload = 1,
    range = 1,
}
local droneStatesByTeam = {}

local function selectTeam(teamID)
	local state = droneStatesByTeam[teamID]
	if not state then
		state = { activeDrones = {}, droneLevel = 0, totalAngleOffset = 0,
			emergencyRepairActive = false, repairEffectUntilFrame = -1,
			summonGrowth = { health = 1, move = 1, damage = 1, reload = 1, range = 1 } }
		droneStatesByTeam[teamID] = state
	end
	playerUnitID, playerFaction = state.playerUnitID, state.playerFaction
	activeDrones, droneLevel = state.activeDrones, state.droneLevel
	totalAngleOffset, emergencyRepairActive = state.totalAngleOffset, state.emergencyRepairActive
	repairEffectUntilFrame, summonGrowth = state.repairEffectUntilFrame, state.summonGrowth
	return state
end

local function storeTeam(state)
	state.playerUnitID, state.playerFaction = playerUnitID, playerFaction
	state.activeDrones, state.droneLevel = activeDrones, droneLevel
	state.totalAngleOffset, state.emergencyRepairActive = totalAngleOffset, emergencyRepairActive
	state.repairEffectUntilFrame, state.summonGrowth = repairEffectUntilFrame, summonGrowth
end

local function withTeam(teamID, callback, ...)
	if not COOP_ENABLED then return callback(...) end
	if not teamID then return end
	local state = selectTeam(teamID)
	local result = callback(...)
	storeTeam(state)
	return result
end

-- Upgrades 通过 GG 接口更新这组 synced 倍率；新生成和已存在的无人机使用同一份状态。
local function applyDroneGrowth(droneID)
	-- 召唤物基础 UnitDef 保持不变；每次升级的倍率由 Upgrades 经 GG 接口传入，
	-- 再统一投影到已存在和新生成的无人机，避免散落修改原 BAR 单位定义。
    if not droneID or not spValidUnitID(droneID) then return end

    local unitDef = UnitDefs[spGetUnitDefID(droneID)]
    local droneData = activeDrones[droneID]
    local health, currentMaxHealth = spGetUnitHealth(droneID)
    local baseMaxHealth = (droneData and droneData.baseMaxHealth)
        or (unitDef and unitDef.health)
        or currentMaxHealth
    if baseMaxHealth and baseMaxHealth > 0 then
        local healthRatio = health and currentMaxHealth and currentMaxHealth > 0
            and health / currentMaxHealth
            or 1
        local newMaxHealth = baseMaxHealth * summonGrowth.health
        spSetUnitMaxHealth(droneID, newMaxHealth)
        spSetUnitHealth(droneID, { health = math.min(newMaxHealth, newMaxHealth * healthRatio) })
    end

    spSetUnitRulesParam(droneID, "roguelike_summon_health_mult", summonGrowth.health, INLOS_ACCESS)
    spSetUnitRulesParam(droneID, "roguelike_summon_damage_mult", summonGrowth.damage, INLOS_ACCESS)
    spSetUnitRulesParam(droneID, "selfMoveSpeedChange", summonGrowth.move, INLOS_ACCESS)
    spSetUnitRulesParam(droneID, "upgradesSpeedMult", 1, INLOS_ACCESS)
    spSetUnitRulesParam(droneID, "selfReloadSpeedChange", summonGrowth.reload, INLOS_ACCESS)
    if GG.UpdateUnitAttributes then
        GG.UpdateUnitAttributes(droneID)
    end

    local maxRange = 0
    if unitDef then
        for weaponNum, weapon in ipairs(unitDef.weapons or {}) do
            local weaponDef = WeaponDefs[weapon.weaponDef]
            if weaponDef and weaponDef.range then
                local range = weaponDef.range * summonGrowth.range
                spSetUnitWeaponState(droneID, weaponNum, "range", range)
                maxRange = mMax(maxRange, range)
            end
        end
    end
    if maxRange > 0 then
        spSetUnitMaxRange(droneID, maxRange)
    end
    spSetUnitRulesParam(droneID, "roguelike_summon_range_mult", summonGrowth.range, INLOS_ACCESS)
end

--------------------------------------------------------------------------------
-- 无人机生成

local function spawnDrone(index, totalDrones)
	-- 只由 synced 端创建。index/totalDrones 决定确定性的初始环绕槽位，
	-- 无人机被击毁或指挥官重建时也走同一入口补齐当前等级数量。
    if not playerUnitID or not spValidUnitID(playerUnitID) then
        return nil
    end

    local droneName = FACTION_DRONE_MAP[playerFaction]
    if not droneName or not UnitDefNames[droneName] then
        spEcho("RoguelikeDrones: No drone definition for faction " .. tostring(playerFaction))
        return nil
    end

    local px, py, pz = spGetUnitPosition(playerUnitID)
    if not px then return nil end

    local angle = (2 * mPi / totalDrones) * (index - 1)
    local dx = mCos(angle) * ORBIT_RADIUS
    local dz = mSin(angle) * ORBIT_RADIUS

    local teamID = spGetUnitTeam(playerUnitID)
    local droneID = spCreateUnit(droneName, px + dx, py + ORBIT_HEIGHT, pz + dz, 0, teamID)

    if not droneID then
        spEcho("RoguelikeDrones: Failed to spawn drone")
        return nil
    end

    -- 设为不可选中、不显示在小地图、中立（不挡路）
    spSetUnitNoSelect(droneID, true)
    spSetUnitNoMinimap(droneID, true)

    -- 开启 MoveCtrl：由 Gadget 控制位置，不受引擎物理影响
    mcEnable(droneID)

    -- 记录定义中的稳定基础生命；后续升级始终基于该值计算，避免重复复利基数。
    local _, maxHealth = spGetUnitHealth(droneID)
    if maxHealth then
        spSetUnitHealth(droneID, { health = maxHealth })
    end

    -- 让无人机自动攻击附近敌人
    -- 使用 GUARD 命令跟随指挥官，武器自动开火
    spGiveOrderToUnit(droneID, CMD_GUARD, { playerUnitID }, {})

    activeDrones[droneID] = {
        angle  = angle,
        index  = index,
        radius = ORBIT_RADIUS,
        baseMaxHealth = maxHealth,
    }
    applyDroneGrowth(droneID)

    return droneID
end

local function spawnAllDrones()
    -- 先清除已有
    for droneID in pairs(activeDrones) do
        if spValidUnitID(droneID) then
            spDestroyUnit(droneID, true, true) -- 立即摧毁，无爆炸
        end
    end
    activeDrones = {}

    local count = mMin(droneLevel * DRONE_PER_LEVEL, MAX_DRONES) -- 计算当前应生成的无人机数量
    if count <= 0 then return end

    for i = 1, count do
        spawnDrone(i, count) -- 生成无人机
    end

    spEcho("RoguelikeDrones: Spawned " .. count .. " drones for " .. tostring(playerFaction))
end

-- 查找最近的敌人
local function findNearestEnemy(unitID)
    if not unitID or not spValidUnitID(unitID) then
        return nil
    end
    return spGetUnitNearestEnemy(unitID, SEARCH_RADIUS, true)
end

-- 修复只在 synced 端按秒结算。先按队伍现有电量计算可承担的修复量，
-- 再由 UseTeamResource 原子扣除，避免 UI 或不同客户端各自修改权威资源。
local function repairCommander(repairDroneCount)
    spSetUnitRulesParam(playerUnitID, "roguelike_drone_repair_rate", 0, INLOS_ACCESS)
    if repairDroneCount <= 0 then return 0 end

    local health, maxHealth = spGetUnitHealth(playerUnitID)
    if not health or not maxHealth or health <= 0 or health >= maxHealth then return 0 end
    local wantedRepair = mMin(maxHealth - health,
        maxHealth * REPAIR_MAX_HEALTH_FRACTION_PER_DRONE * repairDroneCount)
    local teamID = spGetUnitTeam(playerUnitID)
    if not teamID or not GG.Roguelike or not GG.Roguelike.HealCommander then return 0 end

    local actualRepair = GG.Roguelike.HealCommander(teamID, "drone_repair", wantedRepair, {
        sustained = true,
        energyPerHP = ENERGY_PER_REPAIR_HEALTH,
    }) or 0
    -- The synced survival ledger limits combined passive, drone, kill and aura healing.
    spSetUnitRulesParam(playerUnitID, "roguelike_drone_repair_rate", actualRepair, INLOS_ACCESS)
    return actualRepair
end

--------------------------------------------------------------------------------
-- 每帧更新：紧急修复 > 攻击 > 回收残骸 > 常规修复 > 待机

local function updateDrones(frame)
	-- 每次更新先为整组无人机确定共同任务，再执行移动/命令，避免同一帧中
	-- 多架无人机因遍历先后各自改变指挥官修复阈值而产生摇摆。
    -- 每帧更新位置以保持平滑轨道
    local dt = 1.0 / GAME_SPEED
    totalAngleOffset = totalAngleOffset + ORBIT_SPEED_BASE * dt -- 全局旋转角度

    if not playerUnitID or not spValidUnitID(playerUnitID) then -- 指挥官不存在或已死亡
        return
    end

    local px, py, pz = spGetUnitPosition(playerUnitID) -- 获取指挥官位置
    if not px then return end -- 如果获取位置失败，直接返回

    local commanderHealth, commanderMaxHealth = spGetUnitHealth(playerUnitID)
    local commanderHealthRatio = commanderHealth and commanderMaxHealth and commanderMaxHealth > 0
        and commanderHealth / commanderMaxHealth or 1
    -- 45% 开始、60% 结束的滞回可防止无人机在临界生命值附近逐帧切换任务，
    -- 同时把“救急带”拉宽到足以在多轮交火中真正回血。
    if commanderHealthRatio < EMERGENCY_REPAIR_START then
        emergencyRepairActive = true
    elseif emergencyRepairActive and commanderHealthRatio >= EMERGENCY_REPAIR_STOP then
        emergencyRepairActive = false
    end
    spSetUnitRulesParam(playerUnitID, "roguelike_drone_emergency_repair",
        emergencyRepairActive and 1 or 0, INLOS_ACCESS)
    local isSecondTick = frame % GAME_SPEED == 0
    local repairDroneCount = 0

    local droneCount = 0 -- 统计当前活跃无人机数量
    for _ in pairs(activeDrones) do droneCount = droneCount + 1 end -- 统计当前活跃无人机数量

    for droneID, data in pairs(activeDrones) do -- 遍历所有活跃无人机
        if not spValidUnitID(droneID) then -- 如果无人机已被摧毁，则移除
            activeDrones[droneID] = nil -- 从 activeDrones 中移除已摧毁的无人机
        else
            -- 更新轨道位置
            local currentAngle = data.angle + totalAngleOffset -- 当前角度 = 初始角度 + 全局旋转角度
            local r = data.radius -- 轨道半径

            local dx = mCos(currentAngle) * r -- 计算 X 偏移
            local dz = mSin(currentAngle) * r -- 计算 Z 偏移
            local targetX = px + dx -- 目标 X 坐标 = 指挥官 X + 偏移
            local targetY = py + ORBIT_HEIGHT -- 目标 Y 坐标 = 指挥官 Y + 悬浮高度
            local targetZ = pz + dz -- 目标 Z 坐标 = 指挥官 Z + 偏移

            -- 通过 MoveCtrl 直接设置位置
            -- MoveCtrl 仅用于绕行/维修状态。攻击状态交给引擎移动；若仍每帧设置轨道坐标，
            -- 会把无人机拉回原处，抵消 CMD_ATTACK 的追击移动。
            if mcIsEnabled(droneID) then
                mcSetPosition(droneID, targetX, targetY, targetZ)
            end

            -- 保持无敌
            local health, maxHealth = spGetUnitHealth(droneID) -- 获取无人机当前生命值和最大生命值
            if health and maxHealth and health < maxHealth then -- 如果当前生命值小于最大生命值
                spSetUnitHealth(droneID, { health = maxHealth }) -- 强制设置为满血
            end

            if emergencyRepairActive then
                -- 紧急状态覆盖攻击和回收：无人机停止追敌，回到指挥官轨道持续修复至 60%。
                if not mcIsEnabled(droneID) then mcEnable(droneID) end
                if data.mode ~= "emergencyRepair" then
                    spGiveOrderToUnit(droneID, CMD_STOP, {}, {})
                    data.mode = "emergencyRepair"
                    data.target = nil
                end
                if isSecondTick then repairDroneCount = repairDroneCount + 1 end
            else
                local enemyID = findNearestEnemy(droneID)
                if enemyID then
                    if mcIsEnabled(droneID) then mcDisable(droneID) end
                    if data.mode ~= "attack" or data.target ~= enemyID then
                        spGiveOrderToUnit(droneID, CMD_ATTACK, { enemyID }, {})
                        data.mode = "attack"
                        data.target = enemyID
                    end
                else
                    if not mcIsEnabled(droneID) then mcEnable(droneID) end
                    local absorbed = 0
                    if isSecondTick and GG.Roguelike and GG.Roguelike.AbsorbWrecksForUnit then
                        absorbed = GG.Roguelike.AbsorbWrecksForUnit(
                            droneID, WRECK_SEARCH_RADIUS, 1)
                    end
                    if data.mode == "attack" then
                        spGiveOrderToUnit(droneID, CMD_STOP, {}, {})
                    end
                    local commanderNeedsRepair = commanderHealth and commanderMaxHealth
                        and commanderHealth < commanderMaxHealth
                    if absorbed > 0 then
                        data.mode = "salvage"
                    elseif commanderNeedsRepair and (isSecondTick or repairEffectUntilFrame >= frame) then
                        data.mode = "repair"
                    else
                        data.mode = "orbit"
                    end
                    data.target = nil
                    -- 没有敌人且本秒没有可吸收残骸时，未满血的指挥官才进入常规修复。
                    if isSecondTick and absorbed == 0 and commanderNeedsRepair then
                        repairDroneCount = repairDroneCount + 1
                    end
                end
            end

            -- 只有上一秒确实成功扣电并修复后才显示粒子，避免“有特效但没回血”的假动作。
            if repairEffectUntilFrame >= frame and frame % REPAIR_EFFECT_INTERVAL == 0
                and (data.mode == "repair" or data.mode == "emergencyRepair") then
                local effectDX = px - targetX
                local effectDY = (py + 35) - targetY
                local effectDZ = pz - targetZ
                local effectLength = mSqrt(
                    effectDX * effectDX + effectDY * effectDY + effectDZ * effectDZ)
                if effectLength > 0 then
                    spSpawnCEG("roguelike-drone-repair-nano",
                        targetX, targetY, targetZ,
                        effectDX / effectLength, effectDY / effectLength, effectDZ / effectLength)
                end
            end
        end
    end

    if isSecondTick then
        local repaired = repairCommander(repairDroneCount)
        repairEffectUntilFrame = repaired > 0 and (frame + GAME_SPEED - 1) or -1
    end

    -- 每秒检查一次：无人机被摧毁则补发
    if frame % GAME_SPEED == 0 and droneCount < mMin(droneLevel * DRONE_PER_LEVEL, MAX_DRONES) then
        local targetCount = mMin(droneLevel * DRONE_PER_LEVEL, MAX_DRONES)
        local missing = targetCount - droneCount
        if missing > 0 then
            for i = 1, missing do
                spawnDrone(droneCount + i, targetCount)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- GG 接口：供升级系统调用

-- 每一级固定增加 DRONE_PER_LEVEL 架，并立即重建整组轨道槽位。
-- 第二波里程碑与后续无人机卡都走这个入口，所以数量上限与生成时机不会分叉。
local function addDroneLevelCurrent(suppressNotification)
    droneLevel = droneLevel + 1
    spawnAllDrones()
    spSetUnitRulesParam(playerUnitID or -1, "roguelike_drone_level", droneLevel, INLOS_ACCESS)
    if not suppressNotification then
		SendToUnsynced("RoguelikeUpgradeApplied", spGetUnitTeam(playerUnitID), "Drone Swarm Lv" .. droneLevel,
            "+" .. DRONE_PER_LEVEL .. " orbiting drones")
    end
end

local function setSummonGrowthCurrent(health, move, damage, reload, range)
    summonGrowth.health = tonumber(health) or summonGrowth.health
    summonGrowth.move = tonumber(move) or summonGrowth.move
    summonGrowth.damage = tonumber(damage) or summonGrowth.damage
    summonGrowth.reload = tonumber(reload) or summonGrowth.reload
    summonGrowth.range = tonumber(range) or summonGrowth.range
    for droneID in pairs(activeDrones) do
        applyDroneGrowth(droneID)
    end
end

local function addDroneLevel(teamID, suppressNotification)
	return withTeam(teamID, addDroneLevelCurrent, suppressNotification)
end

local function setSummonGrowthMultipliers(teamID, health, move, damage, reload, range)
	return withTeam(teamID, setSummonGrowthCurrent, health, move, damage, reload, range)
end

--------------------------------------------------------------------------------
-- Callins

function gadget:Initialize()
    -- 找到玩家指挥官
    local units = Spring.GetAllUnits() -- 获取所有单位
    for _, uid in ipairs(units) do --  遍历所有单位
        local ud = UnitDefs[spGetUnitDefID(uid)] -- 获取单位定义
        if ud and ud.customParams and ud.customParams.iscommander then -- 检查是否为指挥官
            local _, _, _, isAI = Spring.GetTeamInfo(spGetUnitTeam(uid)) -- 获取队伍信息
            if not isAI then -- 如果不是 AI，则记录玩家指挥官
				withTeam(spGetUnitTeam(uid), function()
					playerUnitID = uid
					playerFaction = getFaction(spGetUnitDefID(uid))
				end)
            end
        end
    end

    -- GG 是 synced Gadget 之间的进程内契约：Upgrades 只表达“增加等级/更新成长”，
    -- 无人机数量、实例生命周期和属性投影仍由本模块集中负责。
    GG.Roguelike = GG.Roguelike or {} -- 确保 GG.Roguelike 表存在
    GG.Roguelike.AddDroneLevel = addDroneLevel -- 注册添加无人机等级的函数
	GG.Roguelike.GetDroneLevel = function(teamID)
		return COOP_ENABLED and ((droneStatesByTeam[teamID] or {}).droneLevel or 0) or droneLevel
	end
    -- Upgrades 写入，Orbit Drones 读取并应用于当前及后续召唤物。
    GG.Roguelike.SetSummonGrowthMultipliers = setSummonGrowthMultipliers
end

function gadget:GameFrame(frame)
    if COOP_ENABLED then
		for _, teamID in ipairs(GG.Roguelike and GG.Roguelike.teamIDs or {}) do
			local state = droneStatesByTeam[teamID]
			if state and state.droneLevel > 0 then withTeam(teamID, updateDrones, frame) end
		end
	elseif droneLevel > 0 then
		updateDrones(frame)
	end
end

function gadget:UnitCreated(unitID, unitDefID, unitTeam, builderID)
    if UnitDefs[unitDefID] and UnitDefs[unitDefID].customParams -- 检查 unitDef 是否存在且有 customParams
        and UnitDefs[unitDefID].customParams.iscommander then -- 检查是否为指挥官
        local _, _, _, isAI = Spring.GetTeamInfo(unitTeam) -- 获取队伍信息
        if not isAI then -- 如果不是 AI，则记录玩家指挥官
			withTeam(unitTeam, function()
				playerUnitID = unitID
				playerFaction = getFaction(unitDefID)
				if droneLevel > 0 then spawnAllDrones() end
			end)
        end
    end
end

function gadget:UnitDestroyed(unitID, unitDefID, unitTeam, attackerID, attackerDefID, attackerTeam)
	if COOP_ENABLED then
		local state = droneStatesByTeam[unitTeam]
		if not state or state.playerUnitID ~= unitID then return end
		withTeam(unitTeam, function()
			emergencyRepairActive = false
			repairEffectUntilFrame = -1
			for droneID in pairs(activeDrones) do
				if spValidUnitID(droneID) then spDestroyUnit(droneID, true, true) end
			end
			activeDrones = {}
			playerUnitID = nil
		end)
		return
	end
    -- 如果指挥官死了，清除所有无人机
    if unitID == playerUnitID then
        emergencyRepairActive = false
        repairEffectUntilFrame = -1
        for droneID in pairs(activeDrones) do
            if spValidUnitID(droneID) then
                spDestroyUnit(droneID, true, true)
            end
        end
        activeDrones = {}
    end
end

function gadget:Shutdown()
    if GG.Roguelike then
        GG.Roguelike.AddDroneLevel = nil
        GG.Roguelike.GetDroneLevel = nil
        GG.Roguelike.SetSummonGrowthMultipliers = nil
    end
end
