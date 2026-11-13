--------------------------------------------------------------------------------
-- [SYNCED 权威模块：波次状态机与敌军生成]
--
-- 本模块持有开局准备与连续作战的唯一权威状态，并负责敌军选择、
-- 随时间补充刷怪额度、生成、强化、追击、死亡统计和波次编号更新。
--
-- 对外契约：
--   * 写入 GG.Roguelike.currentWave / totalKills / playerUnitID / playerTeamID；
--   * 敌人死亡时调用 GG.Roguelike.OnKill，供升级模块结算击杀进度；
--   * 每 70 秒时间边界调用 GG.Roguelike.OnWaveCleared(clearedWave)；
--   * UnitRulesParam 提供连续状态，SendToUnsynced 只通知 UI 播放表现。
--
-- 本模块不发放升级、不结算商店/残骸奖励，也不直接创建无人机。完整调用链见
-- doc/RoguelikeArchitecture.md。
--------------------------------------------------------------------------------
local gadget = gadget ---@type Gadget

function gadget:GetInfo()
	return {
		name      = "Roguelike Wave Spawner",
		desc      = "Spawns enemy waves with increasing difficulty for roguelike mode",
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
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Spring API Cache
--
-- Lua 每次调用 Spring.xxx 都需要进行一次全局查找。
-- 将常用 API 缓存到 local 变量能够减少 Table Lookup，
-- 这是 BAR Gadget 中普遍采用的优化方式。
--------------------------------------------------------------------------------

local spCreateUnit        = Spring.CreateUnit 			-- 创建单位
local spDestroyUnit       = Spring.DestroyUnit 			-- 摧毁单位
local spGiveOrderToUnit   = Spring.GiveOrderToUnit		-- 给单位下达命令
local spGetUnitPosition   = Spring.GetUnitPosition		-- 获取单位位置
local spGetGroundHeight   = Spring.GetGroundHeight		-- 获取地面高度
local spGetGameFrame      = Spring.GetGameFrame			-- 获取当前游戏帧
local spSetUnitRulesParam = Spring.SetUnitRulesParam	-- 设置单位规则参数
local spGetAllUnits       = Spring.GetAllUnits			-- 获取所有单位
local spGetUnitTeam       = Spring.GetUnitTeam			-- 获取单位所属队伍
local spGetUnitDefID      = Spring.GetUnitDefID			-- 获取单位定义 ID
local spGetUnitHealth     = Spring.GetUnitHealth
local spGetUnitRulesParam = Spring.GetUnitRulesParam
local spSetUnitHealth     = Spring.SetUnitHealth
local spSetUnitMaxHealth  = Spring.SetUnitMaxHealth
local spSetUnitAlwaysVisible = Spring.SetUnitAlwaysVisible
local spEcho              = Spring.Echo					-- 输出日志
local spGetTeamList       = Spring.GetTeamList			-- 获取所有队伍列表
local spGetTeamInfo       = Spring.GetTeamInfo			-- 获取队伍信息
local spGetGaiaTeamID     = Spring.GetGaiaTeamID		-- 获取 Gaia 队伍 ID
local mRandom             = math.random
local mCeil               = math.ceil
local mFloor              = math.floor
local mMin                = math.min
local mMax                = math.max

local GAME_SPEED = Game.gameSpeed -- 30
local CMD_PATROL = CMD.PATROL
local CMD_FIGHT  = CMD.FIGHT

-- Reissue the target periodically so enemies that lose their target resume pursuit.
local RETARGET_INTERVAL = 3 * GAME_SPEED

local INLOS_ACCESS = { inlos = true }

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- 配置：波次与敌人定义

-- 常规敌军严格按种族和移动类型组织：每族 5 个 Bot、5 个 Vehicle。
-- minStage/maxStage 控制出场阶段，role 用于维持每波近程/远程比例。
local ENEMY_ROSTERS = {
	arm = {
		bots = {
			{ unitName = "armpw", role = "close", minStage = 1, maxStage = 2, weight = 9 },
			{ unitName = "armrock", role = "ranged", minStage = 1, maxStage = 2, weight = 7 },
			{ unitName = "armzeus", role = "close", minStage = 2, maxStage = 3, weight = 6 },
			{ unitName = "armmav", role = "close", minStage = 3, maxStage = 4, weight = 5 },
			{ unitName = "armfido", role = "ranged", minStage = 3, maxStage = 5, weight = 5 },
		},
		vehicles = {
			{ unitName = "armflash", role = "close", minStage = 1, maxStage = 2, weight = 7 },
			{ unitName = "armstump", role = "close", minStage = 2, maxStage = 3, weight = 7 },
			{ unitName = "armjanus", role = "ranged", minStage = 2, maxStage = 3, weight = 5 },
			{ unitName = "armbull", role = "close", minStage = 3, maxStage = 5, weight = 4 },
			{ unitName = "armmart", role = "ranged", minStage = 3, maxStage = 5, weight = 4 },
		},
	},
	cor = {
		bots = {
			{ unitName = "corak", role = "close", minStage = 1, maxStage = 2, weight = 9 },
			{ unitName = "corstorm", role = "ranged", minStage = 1, maxStage = 2, weight = 7 },
			{ unitName = "corthud", role = "close", minStage = 2, maxStage = 3, weight = 6 },
			{ unitName = "corcan", role = "close", minStage = 3, maxStage = 4, weight = 5 },
			{ unitName = "corhrk", role = "ranged", minStage = 3, maxStage = 5, weight = 5 },
		},
		vehicles = {
			{ unitName = "corgator", role = "close", minStage = 1, maxStage = 2, weight = 7 },
			{ unitName = "corraid", role = "close", minStage = 2, maxStage = 3, weight = 7 },
			{ unitName = "corlevlr", role = "ranged", minStage = 2, maxStage = 3, weight = 5 },
			{ unitName = "correap", role = "close", minStage = 3, maxStage = 5, weight = 4 },
			{ unitName = "corvroc", role = "ranged", minStage = 3, maxStage = 5, weight = 4 },
		},
	},
	legion = {
		bots = {
			{ unitName = "legcen", role = "close", minStage = 1, maxStage = 2, weight = 8 },
			{ unitName = "leglob", role = "ranged", minStage = 1, maxStage = 2, weight = 7 },
			{ unitName = "legbal", role = "ranged", minStage = 1, maxStage = 3, weight = 5 },
			{ unitName = "legshot", role = "close", minStage = 2, maxStage = 4, weight = 6 },
			{ unitName = "legkark", role = "close", minStage = 2, maxStage = 5, weight = 5 },
		},
		vehicles = {
			{ unitName = "leggat", role = "close", minStage = 1, maxStage = 2, weight = 7 },
			{ unitName = "legbar", role = "ranged", minStage = 2, maxStage = 3, weight = 6 },
			{ unitName = "legrail", role = "ranged", minStage = 2, maxStage = 4, weight = 5 },
			{ unitName = "legmrv", role = "close", minStage = 3, maxStage = 5, weight = 5 },
			{ unitName = "legaskirmtank", role = "ranged", minStage = 3, maxStage = 5, weight = 5 },
		},
	},
}

local ENEMY_STAGES = {
	{ startTime = 0, name = "轻型先遣军", countScale = 1.00,
		bossPool = { { unitName = "armzeus", weight = 5 }, { unitName = "corcan", weight = 5 }, { unitName = "legkark", weight = 5 } } },
	{ startTime = 75, name = "快速混编军", countScale = 1.00,
		bossPool = { { unitName = "armbull", weight = 5 }, { unitName = "correap", weight = 5 }, { unitName = "legkark", weight = 5 } } },
	{ startTime = 180, name = "中型主力军", countScale = 0.86,
		bossPool = { { unitName = "armbanth", weight = 2 }, { unitName = "corkarg", weight = 2 }, { unitName = "legkeres", weight = 4 } } },
	{ startTime = 300, name = "重型突击军", countScale = 0.78,
		bossPool = { { unitName = "armraz", weight = 2 }, { unitName = "corcat", weight = 2 }, { unitName = "legeshotgunmech", weight = 4 } } },
	{ startTime = 450, name = "T3终局军团", countScale = 0.68,
		bossPool = { { unitName = "armthor", weight = 2 }, { unitName = "corkorg", weight = 2 }, { unitName = "legeallterrainmech", weight = 4 } } },
}

-- Intentional suicide attackers are removed from the health-banded common pool.
-- The synced scheduler below adds them back with explicit wave gates, weights,
-- spacing, visibility and a cap shared across all still-live spawned enemies.
local SUICIDE_UNIT_PROFILES = {
	{ unitName = "legkam", kind = "light", label = "高速 Martyr 自爆机", minWave = 2, weight = 4 },
	{ unitName = "armvader", kind = "heavy", label = "Arm T2 爬行炸弹", minWave = 5, weight = 0.5 },
	{ unitName = "corroach", kind = "heavy", label = "Cortex T2 爬行炸弹", minWave = 5, weight = 0.5 },
	{ unitName = "corsktl", kind = "heavy", label = "Skuttle T2 爬行炸弹", minWave = 5, weight = 0.5 },
	{ unitName = "legsnapper", kind = "heavy", label = "Legion T2 爬行炸弹", minWave = 5, weight = 0.5 },
}
local SUICIDE_UNIT_NAME_SET = {}
for _, profile in ipairs(SUICIDE_UNIT_PROFILES) do
	SUICIDE_UNIT_NAME_SET[profile.unitName] = true
end

local SUICIDE_MAX_ALIVE_BY_WAVE = { 0, 1, 2, 2, 3, 3, 3, 4 }
local SUICIDE_SPAWN_CHANCE_BY_WAVE = { 0, 1.00, 0.50, 0.50, 0.45, 0.50, 0.55, 0.60 }
local SUICIDE_SPAWN_INTERVAL = 10
local SUICIDE_MIN_SPAWN_DISTANCE = 800

-- Load all mobile combat units from the active UnitDefs, then divide them into
-- health-ordered bands. This keeps ARM/Cortex/Legion mixed and introduces
-- stronger units strictly from lower maximum health to higher maximum health.
local function getFaction(unitName)
	local prefix = unitName and unitName:sub(1, 3)
	return (prefix == "arm" or prefix == "cor" or prefix == "leg") and prefix or nil
end

local function getMaximumWeaponRange(unitDef)
	local maximumRange = 0
	for _, weapon in ipairs(unitDef.weapons or {}) do
		local weaponDef = weapon.weaponDef and WeaponDefs[weapon.weaponDef]
		if weaponDef then
			maximumRange = mMax(maximumRange, weaponDef.range or 0)
		end
	end
	return maximumRange
end

local function hasEffectiveGroundWeapon(unitDef)
	for _, weapon in ipairs(unitDef.weapons or {}) do
		local weaponDef = weapon.weaponDef and WeaponDefs[weapon.weaponDef]
		local onlyTargets = weapon.onlyTargets
		local isDedicatedAA = onlyTargets and onlyTargets.vtol and not onlyTargets.surface
		local isBogus = weaponDef and weaponDef.customParams and weaponDef.customParams.bogus
		if weaponDef
			and (weaponDef.range or 0) > 0
			and weaponDef.canAttackGround ~= false
			and not weaponDef.waterWeapon
			and not isDedicatedAA
			and not isBogus then
			return true
		end
	end
	return false
end

local function getGroundThreatProfile(unitDef)
	local maximumRange = 0
	local maximumAlphaDamage = 0
	for _, weapon in ipairs(unitDef.weapons or {}) do
		local weaponDef = weapon.weaponDef and WeaponDefs[weapon.weaponDef]
		local onlyTargets = weapon.onlyTargets
		local isDedicatedAA = onlyTargets and onlyTargets.vtol and not onlyTargets.surface
		local isBogus = weaponDef and weaponDef.customParams and weaponDef.customParams.bogus
		if weaponDef
			and weaponDef.canAttackGround ~= false
			and not weaponDef.waterWeapon
			and not isDedicatedAA
			and not isBogus then
			local baseDamage = weaponDef.damages and tonumber(weaponDef.damages[0]) or 0
			local projectileCount = (weaponDef.salvoSize or 1) * (weaponDef.projectiles or 1)
			maximumRange = mMax(maximumRange, weaponDef.range or 0)
			maximumAlphaDamage = mMax(maximumAlphaDamage, baseDamage * projectileCount)
		end
	end
	return maximumRange, maximumAlphaDamage
end

local function getThreatMinimumStage(weaponRange, alphaDamage)
	if weaponRange >= 1400 then return 5 end
	if weaponRange >= 1100 or alphaDamage >= 3000 then return 4 end
	if weaponRange >= 800 and alphaDamage >= 800 then return 4 end
	if weaponRange >= 700 and alphaDamage >= 1200 then return 3 end
	return 1
end

local candidates = {}
local factionCounts = { arm = 0, cor = 0, leg = 0 }
local admittedAircraft = 0
local rejectedAircraft = 0
local excludedDrones = 0
local highThreatUnitDefs = {}
local highThreatUnitCount = 0
for unitDefID, unitDef in ipairs(UnitDefs) do
	local unitName = unitDef.name
	local faction = getFaction(unitName)
	local customParams = unitDef.customParams or {}
	local isWaterOnly = not unitDef.canFly and (unitDef.minWaterDepth or 0) > 0
	local isDrone = customParams.drone or customParams.is_roguelike_drone
	local aircraftCanFightGround = not unitDef.canFly or hasEffectiveGroundWeapon(unitDef)
	if faction and isDrone and not unitName:find("_scav", 1, true) then
		excludedDrones = excludedDrones + 1
	end
	if faction and unitDef.canFly and not unitName:find("_scav", 1, true) and not aircraftCanFightGround then
		rejectedAircraft = rejectedAircraft + 1
	end
	if faction
		and unitDef.canMove and (unitDef.speed or 0) > 0
		and unitDef.canAttack and #(unitDef.weapons or {}) > 0
		and not unitDef.isBuilding and not isWaterOnly
		and aircraftCanFightGround
		and not isDrone
		and not customParams.iscommander
		and not customParams.isdecoycommander
		and customParams.subfolder ~= "ArmGantry"
		and customParams.subfolder ~= "CorGantry"
		and customParams.subfolder ~= "Legion/T3"
		and not SUICIDE_UNIT_NAME_SET[unitName]
		and not (unitDef.canMove and (customParams.unitgroup == "explo" or customParams.instantselfd))
		and not unitName:find("_scav", 1, true) then
		local groundRange, alphaDamage = getGroundThreatProfile(unitDef)
		local threatMinimumStage = getThreatMinimumStage(groundRange, alphaDamage)
		candidates[#candidates + 1] = {
			unitDefID = unitDefID,
			unitName = unitName,
			health = unitDef.health or 1,
			role = getMaximumWeaponRange(unitDef) >= 500 and "ranged" or "close",
			minimumStage = threatMinimumStage,
		}
		if threatMinimumStage >= 4 then
			highThreatUnitDefs[unitDefID] = true
			highThreatUnitCount = highThreatUnitCount + 1
		end
		factionCounts[faction] = factionCounts[faction] + 1
		if unitDef.canFly then admittedAircraft = admittedAircraft + 1 end
	end
end

table.sort(candidates, function(a, b)
	if a.health == b.health then return a.unitDefID < b.unitDefID end
	return a.health < b.health
end)

for _, stage in ipairs(ENEMY_STAGES) do
	stage.closePool = {}
	stage.rangedPool = {}
end
for rank, entry in ipairs(candidates) do
	local healthStage = mMin(#ENEMY_STAGES, mFloor((rank - 1) * #ENEMY_STAGES / mMax(1, #candidates)) + 1)
	local stageIndex = mMax(healthStage, entry.minimumStage or 1)
	local targetPool = entry.role == "ranged" and ENEMY_STAGES[stageIndex].rangedPool or ENEMY_STAGES[stageIndex].closePool
	targetPool[#targetPool + 1] = { unitName = entry.unitName, weight = 2 }
end

spEcho("Roguelike: dynamic enemy pool loaded " .. #candidates
	.. " units (ARM " .. factionCounts.arm .. ", COR " .. factionCounts.cor .. ", LEG " .. factionCounts.leg
	.. ", ground-capable aircraft " .. admittedAircraft .. ", rejected aircraft " .. rejectedAircraft
	.. ", excluded drones " .. excludedDrones .. ", delayed high-threat units " .. highThreatUnitCount
	.. ", suicide units held for controlled scheduling " .. #SUICIDE_UNIT_PROFILES .. ")")

local BOSS_WAVE_EVERY = 5     -- 每N波出一个 BOSS
local SPAWN_RADIUS    = 800  -- 刷怪离玩家的距离
local MAP_MARGIN      = 300   -- 刷怪点离地图边缘的最小距离
local RANGED_RATIO = 0.35
local COMBAT_DURATION = 70
local INITIAL_PREPARATION_DURATION = 5
local SPAWN_PULSE_INTERVAL = 4
local INITIAL_TARGET_ALIVE = 20
local TARGET_GROWTH_PER_COMBAT_MINUTE = 1.28
local MAX_TARGET_ALIVE = 120
local WAVE_BUDGET_MULTIPLIER = 3
local MAX_WAVE_BUDGET = 450
local BATCH_CAP_BY_STAGE = { 8, 12, 18, 24, 30 }
local SMALL_T3_START = 450
local SMALL_T3_RAMP = 4 * 70
local ULTIMATE_T3_RAMP = 3 * 70
local BOSS_RESPAWN_SECONDS = 90
local SMALL_T3_POOL = { "armlun", "armmar", "armprowl", "corshiva", "cordemon", "legjav", "legehovertank" }
local ULTIMATE_T3_POOL = { "armbanth", "armraz", "armthor", "corkarg", "corcat", "corkorg", "legkeres", "legeshotgunmech", "legeallterrainmech" }
local BOSS_POOLS = {
	{ "raptor_queen_easy", "armscavengerbossv2" },
	{ "raptor_queen_normal", "armscavengerbossv2" },
	{ "raptor_queen_hard", "scavengerbossv4" },
	{ "raptor_queen_veryhard", "scavengerbossv4" },
	{ "raptor_queen_epic", "scavengerbossv4" },
}

local PHASE_COMBAT = 1
local PHASE_RECOVERY = 3

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- 状态变量

local currentWave       = 0	   	-- 当前波次
local currentPhase      = PHASE_RECOVERY
local phaseEndFrame     = 0
local nextSpawnPulseFrame = 0
local combatElapsedFrames = 0
local enemyTeamID       = nil  	-- 敌人队伍
local playerTeamID      = nil  	-- 玩家队伍
local playerUnitID      = nil
local playerTeamIDs = {}
local commandersByTeam = {}
local spawnAnchorCursor = 0
local coopDefeated = false
local commanderOnlyStartCleanupPending = false  	-- 玩家指挥官
local aliveEnemies      = {}   	-- 追踪存活的敌人
local aliveSuicideEnemies = {}
local totalKills        = 0	   	-- 玩家击杀数（仅统计玩家队伍击杀）
local waveStage
local waveStageIndex = 1
local waveTargetAlive = 0
local waveSpawnBudgetRemaining = 0
local waveSpawnCredit = 0 -- 时间曲线持续补充的刷怪额度，不在波次边界耗尽后停刷
local waveBatchCap = BATCH_CAP_BY_STAGE[1]
local waveUsedCloseUnitDefs = {}
local waveUsedRangedUnitDefs = {}
local waveHighThreatLimit = 1
local waveHighThreatSpawned = 0
local nextSuicideSpawnFrame = 0
local lastSuicideSpawnFrame = -math.huge
local smallT3Defs, ultimateT3Defs = {}, {}
local activeSpecialBosses = {}
local bossLevel = 1
local nextBossFrame = math.huge

for _, name in ipairs(SMALL_T3_POOL) do
	if UnitDefNames[name] then smallT3Defs[#smallT3Defs + 1] = UnitDefNames[name].id end
end
for _, name in ipairs(ULTIMATE_T3_POOL) do
	if UnitDefNames[name] then ultimateT3Defs[#ultimateT3Defs + 1] = UnitDefNames[name].id end
end

local function t3Shares()
	local seconds = combatElapsedFrames / GAME_SPEED
	if seconds < SMALL_T3_START then return 0, 0 end
	local small = mMin(0.40, 0.10 + 0.30 * (seconds - SMALL_T3_START) / SMALL_T3_RAMP)
	local ultimate = 0
	if small >= 0.40 then
		ultimate = mMin(0.15, 0.05 + 0.10 * (seconds - SMALL_T3_START - SMALL_T3_RAMP) / ULTIMATE_T3_RAMP)
	end
	return small, ultimate
end

-- 构建权重表（用于随机抽取）
local function buildWeightTable(pool)
	local totalWeight = 0
	local entries = {}
	for _, entry in ipairs(pool) do
		if UnitDefNames[entry.unitName] then
			totalWeight = totalWeight + entry.weight
			entries[#entries + 1] = {
				unitDefID = UnitDefNames[entry.unitName].id,
				weight    = totalWeight,
			}
		end
	end
	return entries, totalWeight
end

for _, stage in ipairs(ENEMY_STAGES) do
	stage.closeWeightTable, stage.closeTotalWeight = buildWeightTable(stage.closePool)
	stage.rangedWeightTable, stage.rangedTotalWeight = buildWeightTable(stage.rangedPool)
	stage.bossWeightTable, stage.bossTotalWeight = buildWeightTable(stage.bossPool)
end

local function getCurrentEnemyStage(elapsedSeconds)
	local selectedStage = ENEMY_STAGES[1]
	local selectedIndex = 1
	for stageIndex, stage in ipairs(ENEMY_STAGES) do
		if elapsedSeconds >= stage.startTime then
			selectedStage = stage
			selectedIndex = stageIndex
		else
			break
		end
	end
	return selectedStage, selectedIndex
end

-- 从权重表随机选一个 unitDefID
local function pickRandomFromWeight(table, totalWeight)
	if not table or #table == 0 or not totalWeight or totalWeight <= 0 then return nil end
	local roll = mRandom() * totalWeight
	for _, entry in ipairs(table) do
		if roll <= entry.weight then
			return entry.unitDefID
		end
	end
	return table[#table].unitDefID
end

-- Prefer every available unit once before repeating a type in the same wave.
-- This preserves weighted selection but guarantees visible composition variety.
local function pickDiverseFromWeight(weightTable, usedUnitDefs, excludedUnitDefs)
	if not weightTable or #weightTable == 0 then return nil end
	local availableWeight = 0
	local previousWeight = 0
	for _, entry in ipairs(weightTable) do
		local entryWeight = entry.weight - previousWeight
		previousWeight = entry.weight
		if not usedUnitDefs[entry.unitDefID] and not (excludedUnitDefs and excludedUnitDefs[entry.unitDefID]) then
			availableWeight = availableWeight + entryWeight
		end
	end
	if availableWeight <= 0 then
		local hasPermittedUnit = false
		for _, entry in ipairs(weightTable) do
			if not (excludedUnitDefs and excludedUnitDefs[entry.unitDefID]) then
				usedUnitDefs[entry.unitDefID] = nil
				hasPermittedUnit = true
			end
		end
		if not hasPermittedUnit then return nil end
		return pickDiverseFromWeight(weightTable, usedUnitDefs, excludedUnitDefs)
	end

	local roll = mRandom() * availableWeight
	previousWeight = 0
	for _, entry in ipairs(weightTable) do
		local entryWeight = entry.weight - previousWeight
		previousWeight = entry.weight
		if not usedUnitDefs[entry.unitDefID] and not (excludedUnitDefs and excludedUnitDefs[entry.unitDefID]) then
			roll = roll - entryWeight
			if roll <= 0 then
				usedUnitDefs[entry.unitDefID] = true
				return entry.unitDefID
			end
		end
	end
	return nil
end

local function getAliveSuicideCount()
	local aliveCount = 0
	for unitID in pairs(aliveSuicideEnemies) do
		if Spring.ValidUnitID(unitID) then
			aliveCount = aliveCount + 1
		else
			aliveSuicideEnemies[unitID] = nil
		end
	end
	return aliveCount
end

local function selectSuicideUnitForSpawn(frame)
	local aliveCount = getAliveSuicideCount()
	local maximumAlive = SUICIDE_MAX_ALIVE_BY_WAVE[currentWave] or SUICIDE_MAX_ALIVE_BY_WAVE[#SUICIDE_MAX_ALIVE_BY_WAVE]
	local intervalFrames = SUICIDE_SPAWN_INTERVAL * GAME_SPEED
	if currentWave < 2 or maximumAlive <= aliveCount
		or frame < nextSuicideSpawnFrame
		or frame - lastSuicideSpawnFrame < intervalFrames then
		return nil, false
	end

	-- One weighted attempt per interval. A failed roll also waits another interval,
	-- avoiding repeated RNG checks when several normal units share one batch.
	nextSuicideSpawnFrame = frame + intervalFrames
	local chance = SUICIDE_SPAWN_CHANCE_BY_WAVE[currentWave]
		or SUICIDE_SPAWN_CHANCE_BY_WAVE[#SUICIDE_SPAWN_CHANCE_BY_WAVE]
	if mRandom() > chance then return nil, true end

	local totalWeight = 0
	local entries = {}
	for _, profile in ipairs(SUICIDE_UNIT_PROFILES) do
		local unitDef = UnitDefNames[profile.unitName]
		if unitDef and currentWave >= profile.minWave then
			local weight = profile.weight
			if profile.kind == "heavy" and currentWave > 5 then weight = 1 end
			if profile.kind == "light" and currentWave > 4 then weight = 3 end
			totalWeight = totalWeight + weight
			entries[#entries + 1] = { unitDefID = unitDef.id, cumulativeWeight = totalWeight }
		end
	end
	if totalWeight <= 0 then return nil, true end

	local roll = mRandom() * totalWeight
	for _, entry in ipairs(entries) do
		if roll <= entry.cumulativeWeight then
			return entry.unitDefID, true
		end
	end
	return entries[#entries].unitDefID, true
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- 查找玩家队伍与敌方队伍
local function findTeams()
	enemyTeamID = nil
	playerTeamID = nil
	playerTeamIDs = {}
	local gaiaTeamID = spGetGaiaTeamID()
	local coopAllyTeamID
	for _, teamID in ipairs(spGetTeamList()) do
		local _, _, isDead, isAI, _, allyTeamID = spGetTeamInfo(teamID, false)
		if teamID ~= gaiaTeamID and not isDead then
			if isAI then
				if not coopAllyTeamID or allyTeamID ~= coopAllyTeamID then enemyTeamID = teamID end
			else
				playerTeamIDs[#playerTeamIDs + 1] = teamID
				coopAllyTeamID = coopAllyTeamID or allyTeamID
			end
		end
	end
	table.sort(playerTeamIDs)
	playerTeamID = playerTeamIDs[1]
	if enemyTeamID then
		local enemyAlly = select(6, spGetTeamInfo(enemyTeamID, false))
		if enemyAlly == coopAllyTeamID then enemyTeamID = nil end
	end
	if COOP_ENABLED then
		if #playerTeamIDs ~= 2 then
			spEcho("Roguelike Coop requires exactly two player Teams")
			return false
		end
		local playersByTeam = {}
		for _, playerID in ipairs(Spring.GetPlayerList()) do
			local _, _, spectator, teamID = Spring.GetPlayerInfo(playerID, false)
			if not spectator then playersByTeam[teamID] = (playersByTeam[teamID] or 0) + 1 end
		end
		for _, teamID in ipairs(playerTeamIDs) do
			local allyTeamID = select(6, spGetTeamInfo(teamID, false))
			if allyTeamID ~= coopAllyTeamID then
				spEcho("Roguelike Coop player Teams must share an AllyTeam")
				return false
			end
			if playersByTeam[teamID] ~= 1 then
				spEcho("Roguelike Coop requires one player per Team")
				return false
			end
		end
	end
	-- Singleplayer Roguelike has no AI slot; scripted waves use Gaia as their owner.
	if not enemyTeamID then
		enemyTeamID = gaiaTeamID
	end
	return playerTeamID ~= nil and enemyTeamID ~= nil
end

local function isPlayerTeam(teamID)
	for _, playerID in ipairs(playerTeamIDs) do
		if playerID == teamID then return true end
	end
	return false
end

-- 查找玩家指挥官
local function findPlayerCommander()
	local units = spGetAllUnits() -- 获取所有单位
	for _, uid in ipairs(units) do
		local ud = UnitDefs[spGetUnitDefID(uid)] -- 获取单位定义
		local teamID = spGetUnitTeam(uid)
		if ud and ud.customParams and ud.customParams.iscommander
			and (teamID == playerTeamID or (COOP_ENABLED and isPlayerTeam(teamID))) then
			commandersByTeam[teamID] = uid
			if teamID == playerTeamID then playerUnitID = uid end
			GG.Roguelike = GG.Roguelike or {}
			GG.Roguelike.playerUnitID = playerUnitID
			GG.Roguelike.playerTeamID = playerTeamID
			GG.Roguelike.teams = GG.Roguelike.teams or {}
			GG.Roguelike.teams[teamID] = GG.Roguelike.teams[teamID] or {}
			GG.Roguelike.teams[teamID].commanderUnitID = uid
			spSetUnitRulesParam(uid, "roguelike_wave", currentWave, INLOS_ACCESS)
			spSetUnitRulesParam(uid, "roguelike_kills", totalKills, INLOS_ACCESS)
			if not COOP_ENABLED then return end
		end
	end
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- 刷怪逻辑
local function createEnemyUnit(unitDefID, x, y, z, facing)
	local unitID = spCreateUnit(unitDefID, x, y, z, facing, enemyTeamID)
	if not unitID then
		local gaiaTeamID = spGetGaiaTeamID()
		if gaiaTeamID and gaiaTeamID ~= enemyTeamID then
			unitID = spCreateUnit(unitDefID, x, y, z, facing, gaiaTeamID)
			if unitID then
				enemyTeamID = gaiaTeamID
				spEcho("Roguelike: enemy team unavailable; switched scripted spawns to Gaia")
			end
		end
	end
	return unitID
end
local function getSpawnPosition(minimumDistance)
	local anchorID = playerUnitID
	if COOP_ENABLED then
		local live = {}
		for _, teamID in ipairs(playerTeamIDs) do
			local uid = commandersByTeam[teamID]
			if uid and Spring.ValidUnitID(uid) then live[#live + 1] = uid end
		end
		if #live == 0 then return nil end
		spawnAnchorCursor = spawnAnchorCursor + 1
		anchorID = live[(spawnAnchorCursor - 1) % #live + 1]
	end
	if not anchorID then return nil end
	local px, py, pz = spGetUnitPosition(anchorID) -- 获取指挥官位置
	-- 如果玩家指挥官不存在，返回 nil
	if not px then
		return nil
	end

	local mapX = Game.mapSizeX -- 获取地图尺寸
	local mapZ = Game.mapSizeZ -- 获取地图尺寸

	-- 在玩家周围随机方向刷怪
	for attempt = 1, 20 do
		local angle = mRandom() * 2 * math.pi -- 随机角度
		local dist  = SPAWN_RADIUS + mRandom() * 400 -- 随机距离
		local sx = px + math.cos(angle) * dist -- 计算刷怪点坐标
		local sz = pz + math.sin(angle) * dist -- 计算刷怪点坐标

		-- 限制在地图范围内
		sx = mMax(MAP_MARGIN, mMin(mapX - MAP_MARGIN, sx))
		sz = mMax(MAP_MARGIN, mMin(mapZ - MAP_MARGIN, sz))

		local sy = spGetGroundHeight(sx, sz) -- 获取地面高度

		local dx = sx - px
		local dz = sz - pz
		local distanceIsSafe = not minimumDistance or dx * dx + dz * dz >= minimumDistance * minimumDistance
		if distanceIsSafe and COOP_ENABLED and minimumDistance then
			for _, teamID in ipairs(playerTeamIDs) do
				local uid = commandersByTeam[teamID]
				if uid and uid ~= anchorID and Spring.ValidUnitID(uid) then
					local ox, _, oz = spGetUnitPosition(uid)
					if ox and (sx - ox) ^ 2 + (sz - oz) ^ 2 < minimumDistance ^ 2 then
						distanceIsSafe = false
						break
					end
				end
			end
		end
		-- Suicide units are additionally rejected if map-edge clamping moved them
		-- inside the minimum reaction distance from the commander.
		if sy and sy > -10 and distanceIsSafe then
			return sx, sy, sz
		end
	end

	return nil
end

-- 给敌人下达攻击命令
local function orderEnemyAttack(unitID)
	local targetID = playerUnitID
	if COOP_ENABLED then
		local ex, _, ez = spGetUnitPosition(unitID)
		local bestDistance
		for _, teamID in ipairs(playerTeamIDs) do
			local uid = commandersByTeam[teamID]
			if uid and Spring.ValidUnitID(uid) then
				local px, _, pz = spGetUnitPosition(uid)
				if px then
					local distance = ex and ((px - ex) ^ 2 + (pz - ez) ^ 2) or 0
					if not bestDistance or distance < bestDistance then
						bestDistance, targetID = distance, uid
					end
				end
			end
		end
	end
	if targetID and Spring.ValidUnitID(targetID) then
		local x, y, z = spGetUnitPosition(targetID) -- 获取指挥官位置
		if x then
			-- A position-based Fight command does not require the Raptor team to have
			-- a valid unit target/LOS at spawn time. It is refreshed as the commander moves.
			spGiveOrderToUnit(unitID, CMD_FIGHT, { x, y, z }, {}) -- 给敌人下达攻击命令，目标为玩家指挥官位置
		end
	end
end

local function applyEnemyScaling(unitID, elapsedSeconds, isBoss)
	local elapsedMinutes = elapsedSeconds / 60
	-- Player damage upgrades must shorten time to kill; they do not increase
	-- newly spawned enemy health behind the player's back.
	local bossHealthScale = isBoss and 1.35 or 1
	local bossDamageScale = isBoss and 1.15 or 1
	local healthMult = mMin(12, (1.12 ^ elapsedMinutes) * bossHealthScale)
	local damageMult = mMin(6, (1.09 ^ elapsedMinutes) * bossDamageScale)
	local _, currentMaxHealth = spGetUnitHealth(unitID)
	if currentMaxHealth and currentMaxHealth > 0 then
		local scaledHealth = currentMaxHealth * healthMult
		spSetUnitMaxHealth(unitID, scaledHealth)
		spSetUnitHealth(unitID, { health = scaledHealth })
	end
	spSetUnitRulesParam(unitID, "roguelike_enemy_health_mult", healthMult, INLOS_ACCESS)
	spSetUnitRulesParam(unitID, "roguelike_enemy_damage_mult", damageMult, INLOS_ACCESS)
end

local function getAliveEnemyCount()
	local aliveCount = 0
	for unitID in pairs(aliveEnemies) do
		if Spring.ValidUnitID(unitID) then
			aliveCount = aliveCount + 1
		else
			aliveEnemies[unitID] = nil
		end
	end
	return aliveCount
end

local function writePhaseState(frame)
	GG.Roguelike = GG.Roguelike or {}
	GG.Roguelike.phase = currentPhase
	GG.Roguelike.combatSeconds = combatElapsedFrames / GAME_SPEED
	for _, teamID in ipairs(playerTeamIDs) do
		local commanderID = commandersByTeam[teamID]
	if commanderID and Spring.ValidUnitID(commanderID) then
		local remainingSeconds = mMax(0, mCeil((phaseEndFrame - frame) / GAME_SPEED))
		local enemiesAlive = getAliveEnemyCount()
		spSetUnitRulesParam(commanderID, "roguelike_phase", currentPhase, INLOS_ACCESS)
		spSetUnitRulesParam(commanderID, "roguelike_phase_time", remainingSeconds, INLOS_ACCESS)
		spSetUnitRulesParam(commanderID, "roguelike_target_alive", waveTargetAlive, INLOS_ACCESS)
		-- Spawner 在 synced 端持有 aliveEnemies 权威状态，并把数量镜像给 LuaUI。
		-- UI 不应按本地可见单位自行计数，否则不同客户端会因 LOS 不同而显示不一致。
		spSetUnitRulesParam(commanderID, "roguelike_enemies_alive", enemiesAlive, INLOS_ACCESS)
		spSetUnitRulesParam(commanderID, "roguelike_wave_budget", waveSpawnBudgetRemaining, INLOS_ACCESS)
		spSetUnitRulesParam(commanderID, "roguelike_combat_seconds", combatElapsedFrames / GAME_SPEED, INLOS_ACCESS)
	end
	end
end

local function spawnNormalBatch(requestedCount)
	local count = mMin(requestedCount, waveSpawnBudgetRemaining)
	if count <= 0 or not waveStage then return 0 end
	local rangedCount = mFloor(count * RANGED_RATIO + 0.5)
	local roles = {}
	for i = 1, count do roles[i] = i <= rangedCount and "ranged" or "close" end
	for i = count, 2, -1 do
		local j = mRandom(1, i)
		roles[i], roles[j] = roles[j], roles[i]
	end

	local spawned = 0
	local elapsedSeconds = combatElapsedFrames / GAME_SPEED
	local suicideAttemptedThisBatch = false
	for i = 1, count do
		local suicideUnitDefID
		if not suicideAttemptedThisBatch then
			local attempted
			suicideUnitDefID, attempted = selectSuicideUnitForSpawn(spGetGameFrame())
			suicideAttemptedThisBatch = attempted
		end
		local sx, sy, sz
		if suicideUnitDefID then
			sx, sy, sz = getSpawnPosition(SUICIDE_MIN_SPAWN_DISTANCE)
			if not sx then suicideUnitDefID = nil end
		end
		if not sx then sx, sy, sz = getSpawnPosition() end
		if sx then
			local unitDefID = suicideUnitDefID
			if not unitDefID then
				local smallShare, ultimateShare = t3Shares()
				local roll = mRandom()
				local pool = roll < ultimateShare and ultimateT3Defs
					or (roll < ultimateShare + smallShare and smallT3Defs or nil)
				if pool and #pool > 0 then unitDefID = pool[mRandom(1, #pool)] end
			end
			if not unitDefID then
				local isRanged = roles[i] == "ranged"
				local weightTable = isRanged and waveStage.rangedWeightTable or waveStage.closeWeightTable
				local usedUnitDefs = isRanged and waveUsedRangedUnitDefs or waveUsedCloseUnitDefs
				local excludedUnitDefs = waveHighThreatSpawned >= waveHighThreatLimit and highThreatUnitDefs or nil
				unitDefID = pickDiverseFromWeight(weightTable, usedUnitDefs, excludedUnitDefs)
				if not unitDefID then
					weightTable = isRanged and waveStage.closeWeightTable or waveStage.rangedWeightTable
					usedUnitDefs = isRanged and waveUsedCloseUnitDefs or waveUsedRangedUnitDefs
					unitDefID = pickDiverseFromWeight(weightTable, usedUnitDefs, excludedUnitDefs)
				end
			end
			local unitID = unitDefID and createEnemyUnit(unitDefID, sx, sy, sz, mRandom(0, 3))
			if unitID then
				spawned = spawned + 1
				aliveEnemies[unitID] = true
				if suicideUnitDefID then
					local unitName = UnitDefs[suicideUnitDefID].name
					aliveSuicideEnemies[unitID] = true
					lastSuicideSpawnFrame = spGetGameFrame()
					spSetUnitAlwaysVisible(unitID, true)
					spSetUnitRulesParam(unitID, "roguelike_suicide_unit", 1, INLOS_ACCESS)
					spEcho("Roguelike: wave " .. currentWave .. " suicide spawn " .. unitName
						.. " (alive " .. getAliveSuicideCount() .. "/"
						.. (SUICIDE_MAX_ALIVE_BY_WAVE[currentWave] or SUICIDE_MAX_ALIVE_BY_WAVE[#SUICIDE_MAX_ALIVE_BY_WAVE])
						.. ", interval " .. SUICIDE_SPAWN_INTERVAL .. "s)")
					SendToUnsynced("RoguelikeSuicideWarning", currentWave, unitName)
				end
				if highThreatUnitDefs[unitDefID] then
					waveHighThreatSpawned = waveHighThreatSpawned + 1
					spSetUnitAlwaysVisible(unitID, true)
				end
				applyEnemyScaling(unitID, elapsedSeconds, false)
				orderEnemyAttack(unitID)
			end
		end
	end
	waveSpawnBudgetRemaining = waveSpawnBudgetRemaining - spawned
	waveSpawnCredit = mMax(0, waveSpawnCredit - spawned)
	return spawned
end

local function spawnSpecialBosses(frame)
	local _, ultimateShare = t3Shares()
	if ultimateShare < 0.15 then return end
	if nextBossFrame == math.huge then nextBossFrame = frame end
	if frame < nextBossFrame or next(activeSpecialBosses) then return end
	local pool = BOSS_POOLS[mMin(bossLevel, #BOSS_POOLS)]
	local wanted = bossLevel > #BOSS_POOLS and mMin(5, 1 + bossLevel - #BOSS_POOLS) or 1
	local spawned = 0
	for _ = 1, wanted do
		local unitName = pool[mRandom(1, #pool)]
		local def = UnitDefNames[unitName]
		local sx, sy, sz = getSpawnPosition()
		local unitID = def and sx and createEnemyUnit(def.id, sx, sy, sz, mRandom(0, 3))
		if unitID then
			activeSpecialBosses[unitID] = true
			aliveEnemies[unitID] = true
			spSetUnitAlwaysVisible(unitID, true)
			spSetUnitRulesParam(unitID, "roguelike_boss_level", bossLevel, INLOS_ACCESS)
			applyEnemyScaling(unitID, combatElapsedFrames / GAME_SPEED, true)
			orderEnemyAttack(unitID)
			spawned = spawned + 1
		end
	end
	if spawned > 0 then nextBossFrame = math.huge else nextBossFrame = frame + GAME_SPEED end
end

local function targetAliveAtTime(combatSeconds)
	return mMin(MAX_TARGET_ALIVE,
		mMax(INITIAL_TARGET_ALIVE, mFloor(INITIAL_TARGET_ALIVE
			* (TARGET_GROWTH_PER_COMBAT_MINUTE ^ (combatSeconds / 60)) + 0.5)))
end

local function updateTimedSpawnParameters()
	local combatSeconds = combatElapsedFrames / GAME_SPEED
	local stage, stageIndex = getCurrentEnemyStage(combatSeconds)
	if stageIndex ~= waveStageIndex then
		waveUsedCloseUnitDefs = {}
		waveUsedRangedUnitDefs = {}
	end
	waveStage, waveStageIndex = stage, stageIndex
	waveTargetAlive = targetAliveAtTime(combatSeconds)
	waveBatchCap = BATCH_CAP_BY_STAGE[stageIndex] or BATCH_CAP_BY_STAGE[#BATCH_CAP_BY_STAGE]
end

local function startCombatPhase(frame)
	-- 波次只是作战时间的标记；敌人和刷怪额度跨波保留。
	currentWave = currentWave + 1
	currentPhase = PHASE_COMBAT
	phaseEndFrame = frame + COMBAT_DURATION * GAME_SPEED
	nextSpawnPulseFrame = frame

	updateTimedSpawnParameters()
	waveSpawnCredit = mMax(waveSpawnCredit, waveBatchCap)
	waveSpawnBudgetRemaining = mFloor(waveSpawnCredit)
	waveUsedCloseUnitDefs = {}
	waveUsedRangedUnitDefs = {}
	waveHighThreatLimit = mMax(1, mFloor(mMin(MAX_WAVE_BUDGET,
		waveTargetAlive * WAVE_BUDGET_MULTIPLIER) * 0.04 + 0.5))
	waveHighThreatSpawned = 0
	nextSuicideSpawnFrame = frame + SUICIDE_SPAWN_INTERVAL * GAME_SPEED

	local initialSpawned = spawnNormalBatch(mMin(waveBatchCap, mMax(0, waveTargetAlive - getAliveEnemyCount())))
    spEcho("Roguelike: wave " .. currentWave .. " initial batch created " .. initialSpawned .. " enemies")
	nextSpawnPulseFrame = frame + SPAWN_PULSE_INTERVAL * GAME_SPEED

	for _, teamID in ipairs(playerTeamIDs) do
		local uid = commandersByTeam[teamID]
		if uid and Spring.ValidUnitID(uid) then spSetUnitRulesParam(uid, "roguelike_wave", currentWave, INLOS_ACCESS) end
	end
	GG.Roguelike = GG.Roguelike or {}
	GG.Roguelike.currentWave = currentWave
	GG.Roguelike.totalKills = totalKills
	spEcho("Roguelike: Wave " .. currentWave .. " [" .. waveStage.name .. "] continuous combat; target "
		.. waveTargetAlive .. ", spawn reserve " .. waveSpawnBudgetRemaining .. ", batch cap " .. waveBatchCap)
	SendToUnsynced("RoguelikeWaveStart", currentWave)
	writePhaseState(frame)
end

local function advanceWave(frame)
	-- 结算只按 70 秒时间边界触发，不等待残敌清零，也不清除旧波敌人。
	if GG.Roguelike and GG.Roguelike.OnWaveCleared then
		GG.Roguelike.OnWaveCleared(currentWave)
	end
	spEcho("Roguelike: Wave " .. currentWave .. " time boundary; enemies continue spawning")
	SendToUnsynced("RoguelikeWaveCleared", currentWave)
	startCombatPhase(frame)
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Callins

function gadget:Initialize()
    gadgetHandler:RegisterAllowCommand(CMD.BUILD)
    gadgetHandler:RegisterAllowCommand(CMD.INSERT)
	local validTeams = findTeams()
	findPlayerCommander()

	if not validTeams then
		spEcho("Roguelike: Cannot find both player and enemy teams, disabling")
		gadgetHandler.RemoveGadget(self)
		return
	end

	-- 初始化无人机等级
	-- if GG.Roguelike and GG.Roguelike.AddDroneLevel then
    --     GG.Roguelike.AddDroneLevel() -- 初始化无人机等级
    -- end

	GG.Roguelike = GG.Roguelike or {}
	GG.Roguelike.currentWave = 0
	GG.Roguelike.totalKills  = 0
	GG.Roguelike.playerUnitID = playerUnitID
	GG.Roguelike.playerTeamID = playerTeamID
	GG.Roguelike.coop = COOP_ENABLED
	GG.Roguelike.teamIDs = playerTeamIDs
	currentPhase = PHASE_RECOVERY
	phaseEndFrame = spGetGameFrame() + INITIAL_PREPARATION_DURATION * GAME_SPEED
	writePhaseState(spGetGameFrame())
end

function gadget:GameStart()
	commanderOnlyStartCleanupPending = true
	findTeams()
	if GG.Roguelike then GG.Roguelike.teamIDs = playerTeamIDs end
	findPlayerCommander()
	self:GameFrame(spGetGameFrame())
end

local function keepOnlyCommanderAtStart()
	if not commanderOnlyStartCleanupPending or not playerUnitID or not Spring.ValidUnitID(playerUnitID) then
		return false
	end
	if COOP_ENABLED then
		for _, teamID in ipairs(playerTeamIDs) do
			local uid = commandersByTeam[teamID]
			if not uid or not Spring.ValidUnitID(uid) then return false end
		end
	end
	local removed = 0
	for _, unitID in ipairs(spGetAllUnits()) do
		local keep = false
		for _, teamID in ipairs(playerTeamIDs) do
			if commandersByTeam[teamID] == unitID then keep = true; break end
		end
		if not keep then
			spDestroyUnit(unitID, false, true)
			removed = removed + 1
		end
	end
	commanderOnlyStartCleanupPending = false
	spEcho("Roguelike: retained player commander and removed " .. removed .. " other starting units")
	return true
end
function gadget:GameFrame(frame)
	-- 每 1 秒检查一次（性能优化）
	if frame % GAME_SPEED ~= 0 then
		return
	end

	-- 确保玩家指挥官引用有效
	if not COOP_ENABLED and (not playerUnitID or not Spring.ValidUnitID(playerUnitID)) then
		findPlayerCommander()
	end
	if commanderOnlyStartCleanupPending then
		findTeams()
		if not playerUnitID or not Spring.ValidUnitID(playerUnitID) then findPlayerCommander() end
		keepOnlyCommanderAtStart()
	end
	if COOP_ENABLED and not commanderOnlyStartCleanupPending then
		local alive = 0
		for _, teamID in ipairs(playerTeamIDs) do
			local uid = commandersByTeam[teamID]
			if uid and Spring.ValidUnitID(uid) then alive = alive + 1 end
		end
		if alive == 0 then
			if not coopDefeated then
				coopDefeated = true
				Spring.SetGameRulesParam("roguelike_coop_defeated", 1)
			end
			return
		end
	end

	-- Refresh the current Fight destination so enemies follow the moving commander
	-- and resume movement if they previously lost their route.
	if frame % RETARGET_INTERVAL == 0 then
		for unitID in pairs(aliveEnemies) do
			if Spring.ValidUnitID(unitID) then
				orderEnemyAttack(unitID)
			end
		end
	end

	if currentPhase == PHASE_COMBAT then
		combatElapsedFrames = combatElapsedFrames + GAME_SPEED
		if frame >= phaseEndFrame then
			advanceWave(frame)
			return
		end
		updateTimedSpawnParameters()
		spawnSpecialBosses(frame)
		local spawnPerSecond = mMin(MAX_WAVE_BUDGET,
			waveTargetAlive * WAVE_BUDGET_MULTIPLIER) / COMBAT_DURATION
		waveSpawnCredit = mMin(waveBatchCap, waveSpawnCredit + spawnPerSecond)
		waveSpawnBudgetRemaining = mFloor(waveSpawnCredit)
		if frame >= nextSpawnPulseFrame and waveSpawnBudgetRemaining > 0 then
			local deficit = waveTargetAlive - getAliveEnemyCount()
			if deficit > 0 then
				spawnNormalBatch(mMin(deficit, waveBatchCap))
			end
			nextSpawnPulseFrame = frame + SPAWN_PULSE_INTERVAL * GAME_SPEED
		end
	elseif currentPhase == PHASE_RECOVERY and frame >= phaseEndFrame then
		startCombatPhase(frame)
		return
	end
	writePhaseState(frame)
end

function gadget:AllowCommand(unitID, unitDefID, teamID, cmdID, cmdParams)
	if commandersByTeam[teamID] ~= unitID then return true end
	if cmdID < 0 then return false end
	if cmdID == CMD.INSERT and cmdParams and tonumber(cmdParams[2]) and tonumber(cmdParams[2]) < 0 then return false end
	return true
end
function gadget:UnitDestroyed(unitID, unitDefID, unitTeam, attackerID, attackerDefID, attackerTeam, weaponDefID)
	local deathX, deathY, deathZ = spGetUnitPosition(unitID)
	aliveSuicideEnemies[unitID] = nil
	if activeSpecialBosses[unitID] then
		activeSpecialBosses[unitID] = nil
		if not next(activeSpecialBosses) then
			bossLevel = bossLevel + 1
			nextBossFrame = spGetGameFrame() + BOSS_RESPAWN_SECONDS * GAME_SPEED
		end
	end
	if aliveEnemies[unitID] then
		aliveEnemies[unitID] = nil

		-- 当前模式中的 tracked enemy 都属于刷怪系统；死亡即计入经验，
		-- 避免燃烧、无人机、溅射伤害导致 attackerTeam 缺失而漏算。
		totalKills = totalKills + 1
		GG.Roguelike = GG.Roguelike or {}
		GG.Roguelike.totalKills = totalKills
		for _, teamID in ipairs(playerTeamIDs) do
			local uid = commandersByTeam[teamID]
			if uid and Spring.ValidUnitID(uid) then
				spSetUnitRulesParam(uid, "roguelike_kills", totalKills, INLOS_ACCESS)
			end
		end
		if GG.Roguelike.OnKill then
			GG.Roguelike.OnKill(totalKills, deathX, deathY, deathZ)
		end
		SendToUnsynced("RoguelikeKill", totalKills)
	end
	if commandersByTeam[unitTeam] == unitID then
		commandersByTeam[unitTeam] = nil
		if GG.Roguelike and GG.Roguelike.teams and GG.Roguelike.teams[unitTeam] then
			GG.Roguelike.teams[unitTeam].commanderUnitID = nil
		end
		if unitID == playerUnitID then playerUnitID = nil end
	end
end

function gadget:UnitCreated(unitID, unitDefID, unitTeam, builderID)
	local unitName = string.lower((UnitDefs[unitDefID] and UnitDefs[unitDefID].name) or "")
	if unitName == "legkam" or unitName == "armvader" or unitName == "corroach"
		or unitName == "corsktl" or unitName == "legsnapper" then
		spSetUnitRulesParam(unitID, "roguelike_enemy_explosive", 1, INLOS_ACCESS)
	end
	-- 追踪新创建的玩家指挥官
	if isPlayerTeam(unitTeam) then
		local ud = UnitDefs[unitDefID]
		if ud and ud.customParams and ud.customParams.iscommander then
			commandersByTeam[unitTeam] = unitID
			if unitTeam == playerTeamID then playerUnitID = unitID end
			GG.Roguelike = GG.Roguelike or {}
			GG.Roguelike.playerUnitID = playerUnitID
			GG.Roguelike.playerTeamID = playerTeamID
			GG.Roguelike.teams = GG.Roguelike.teams or {}
			GG.Roguelike.teams[unitTeam] = GG.Roguelike.teams[unitTeam] or {}
			GG.Roguelike.teams[unitTeam].commanderUnitID = unitID
			spSetUnitRulesParam(unitID, "roguelike_wave", currentWave, INLOS_ACCESS)
			spSetUnitRulesParam(unitID, "roguelike_kills", totalKills, INLOS_ACCESS)
			writePhaseState(spGetGameFrame())
		end
	end
end

function gadget:UnitPreDamaged(unitID, unitDefID, unitTeam, damage, paralyzer,
	weaponDefID, projectileID, attackerID)
	if not paralyzer and attackerID and aliveEnemies[attackerID] then
		local damageMult = spGetUnitRulesParam(attackerID, "roguelike_enemy_damage_mult") or 1
		return damage * damageMult
	end
	return damage
end
