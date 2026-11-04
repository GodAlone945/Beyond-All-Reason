--------------------------------------------------------------------------------
-- [SYNCED + UNSYNCED 边界模块：升级、商店与指挥官成长]
--
-- synced 部分持有击杀阈值、待选卡、已购项目、属性倍率、护甲和能量护盾等
-- 权威状态；它验证 LuaUI 发来的玩家、队伍、choiceId、卡牌、价格与前置条件，
-- 最终才改变单位属性和队伍资源。
--
-- unsynced 部分只把 SendToUnsynced 事件转发给 LuaUI，不决定抽卡、消费或伤害。
-- 输入来自 Spawner 的 GG.Roguelike.OnKill / OnWaveCleared，输出通过 RulesParam、
-- GG 无人机接口和同步事件提供给其他模块。完整契约见 doc/RoguelikeArchitecture.md。
--------------------------------------------------------------------------------
local gadget = gadget ---@type Gadget

function gadget:GetInfo()
	return {
		name      = "Roguelike Upgrades",
		desc      = "Kill-based card choices and metal shop upgrades",
		author    = "GodAlone945",
		date      = "2025",
		license   = "GNU GPL, v2 or later",
		layer     = 1,
		enabled   = true,
	}
end

--------------------------------------------------------------------------------
-- UNSYNCED: forward synced events to LuaUI

local roguelikeOption = Spring.GetModOptions().roguelike_mode
if roguelikeOption ~= true and roguelikeOption ~= 1 and roguelikeOption ~= "1" and roguelikeOption ~= "true" then
	return false
end
local coopOption = Spring.GetModOptions().roguelike_coop
local COOP_ENABLED = coopOption == true or coopOption == 1 or coopOption == "1" or coopOption == "true"
local damageHealingRules = VFS.Include("unitbasedefs/roguelike_damage_healing.lua")

if not gadgetHandler:IsSyncedCode() then
	local function localTeamEvent(teamID)
		return not COOP_ENABLED or teamID == Spring.GetMyTeamID()
	end
	local function showUpgradeChoices(_, teamID, choiceId, choicesStr, refreshes, skips, banishes)
		if not localTeamEvent(teamID) then return end
		if Script.LuaUI("RoguelikeShowChoices") then
			Script.LuaUI.RoguelikeShowChoices(choiceId, choicesStr, refreshes, skips, banishes)
		end
	end

	local function showUpgradeNotification(_, teamID, name, desc)
		if not localTeamEvent(teamID) then return end
		if Script.LuaUI("RoguelikeUpgradeNotification") then
			Script.LuaUI.RoguelikeUpgradeNotification(name, desc)
		end
	end

	local function showShopResult(_, teamID, success, itemId, name, level, cost, reason)
		if not localTeamEvent(teamID) then return end
		if Script.LuaUI("RoguelikeShopResult") then
			Script.LuaUI.RoguelikeShopResult(success, itemId, name, level, cost, reason)
		end
	end

	local function showUpgradeList(_, teamID, list)
		if not localTeamEvent(teamID) then return end
		if Script.LuaUI("RoguelikeUpgradeList") then
			Script.LuaUI.RoguelikeUpgradeList(list)
		end
	end

	local function showSuicideWarning(_, wave, unitName)
		if Script.LuaUI("RoguelikeSuicideWarning") then
			Script.LuaUI.RoguelikeSuicideWarning(wave, unitName)
		end
	end
	local function showSkillResult(_, teamID, success, skillID, cooldownFrame, reason)
		if not localTeamEvent(teamID) then return end
		if Script.LuaUI("RoguelikeSkillResult") then
			Script.LuaUI.RoguelikeSkillResult(success, skillID, cooldownFrame, reason)
		end
	end

	function gadget:Initialize()
		gadgetHandler:AddSyncAction("RoguelikeOfferChoices", showUpgradeChoices)
		gadgetHandler:AddSyncAction("RoguelikeUpgradeApplied", showUpgradeNotification)
		gadgetHandler:AddSyncAction("RoguelikeShopResult", showShopResult)
		gadgetHandler:AddSyncAction("RoguelikeUpgradeList", showUpgradeList)
		gadgetHandler:AddSyncAction("RoguelikeSuicideWarning", showSuicideWarning)
		gadgetHandler:AddSyncAction("RoguelikeSkillResult", showSkillResult)
		gadgetHandler:AddChatAction("roguelikeinfo", function()
			Spring.Echo("Roguelike: kills grant card choices; absorbed wreck metal buys permanent shop stats.")
		end, "Shows roguelike upgrade info")
	end

	function gadget:Shutdown()
		gadgetHandler:RemoveSyncAction("RoguelikeOfferChoices")
		gadgetHandler:RemoveSyncAction("RoguelikeUpgradeApplied")
		gadgetHandler:RemoveSyncAction("RoguelikeShopResult")
		gadgetHandler:RemoveSyncAction("RoguelikeUpgradeList")
		gadgetHandler:RemoveSyncAction("RoguelikeSuicideWarning")
		gadgetHandler:RemoveSyncAction("RoguelikeSkillResult")
		gadgetHandler:RemoveChatAction("roguelikeinfo")
	end

	return
end

--------------------------------------------------------------------------------
-- SYNCED：持有升级进度、商店购买和指挥官属性的权威状态。

local spValidUnitID           = Spring.ValidUnitID

local INLOS_ACCESS = { inlos = true }
local CHOICES_PER_OFFER = 3
local BASE_SALVAGE_RADIUS = 220
local SHIELD_REGEN_DELAY = Game.gameSpeed * 4
local SHIELD_REGEN_PER_SECOND = 0.03
local SHIELD_ENERGY_PER_POINT = 0.8
local SUSTAINED_HEAL_CAP_PER_SECOND = 0.015
local DAMAGE_TRIGGER_HEAL_CAP_PER_SECOND = 0.006
local NANO_REPAIR_COST = 180
local NANO_REPAIR_DURATION = 5
local NANO_REPAIR_COOLDOWN = 50
local NANO_REPAIR_TICK_FRAMES = 6
local NANO_REPAIR_TICKS = NANO_REPAIR_DURATION * Game.gameSpeed / NANO_REPAIR_TICK_FRAMES
local THRUSTER_DURATION = 2
local THRUSTER_COOLDOWN = 30
local THRUSTER_MULTIPLIER = 1.45
local MEDKIT_HEAL_FRACTION = 0.06
local MEDKIT_LIFETIME = 20 * Game.gameSpeed
local MEDKIT_PICKUP_RADIUS = 100
local MEDKIT_PICKUP_COOLDOWN = 5 * Game.gameSpeed
local MEDKIT_MAX_ON_GROUND = 4
local BEACON_RADIUS = 350
local BEACON_DURATION = 8 * Game.gameSpeed
local BEACON_COOLDOWN = 65
local BEACON_ENERGY_COST = 350
local BEACON_HEAL_FRACTION = 0.12
local BLAST_LINING_LIMIT = 0.30
local ENERGY_INCOME_PER_UPGRADE = 50
local MAX_ARMOR_DAMAGE_REDUCTION = 0.65
local HEALTH_REGEN_DELAY = Game.gameSpeed * 6
local BASE_HEALTH_REGEN_PER_SECOND = 0.0025
local WAVE_CLEAR_HEAL_FRACTION = 0.10
-- Phase 3 只用于开局准备；之后按作战时间每 70 秒结算一次 10% 治疗。
local RECOVERY_HEAL_PER_SECOND = 0.012
local FOCUS_GUARD_WINDOW_FRAMES = Game.gameSpeed
local FOCUS_GUARD_FULL_DAMAGE_FRACTION = 0.10
local FOCUS_GUARD_OVERFLOW_MULTIPLIER = 0.35
local LIGHTNING_EXTENSION_DAMAGE_PER_LEVEL = 0.25
local LIGHTNING_EXTENSION_RANGE_PER_LEVEL = 0.20
local PLASMA_EXTENSION_DAMAGE_PER_LEVEL = 0.25
local SNIPER_EXTENSION_EXECUTE_THRESHOLD = 0.40
local SNIPER_EXTENSION_DAMAGE_PER_LEVEL = 0.35
local BARRAGE_EXTENSION_DAMAGE_PER_LEVEL = 0.25
local SHOCKWAVE_EXTENSION_MAX_BASE_HEALTH = 2500
local SHOCKWAVE_EXTENSION_DAMAGE_PER_LEVEL = 0.30
local factionWeaponCatalog = VFS.Include("unitbasedefs/roguelike_weapon_catalog.lua")
local MAX_EQUIPPED_FACTION_WEAPONS = factionWeaponCatalog.maxEquippedFactionWeapons or 3

-- Normalized shared team XP plus wave guarantees; each unlock adds one personal offer.
-- Normalized shared team XP thresholds. Wave guarantees use max(XP offers, wave target)
-- so guarantees never stack on top of XP offers.
local UPGRADE_THRESHOLDS = { 25, 50, 75, 110, 145, 190, 245, 310, 395, 480, 565, 680, 850, 1100, 1400, 1750, 2150, 2600 }
local WAVE_GUARANTEED_OFFERS = { 2, 4, 6, 8, 10, 12, 13, 14, 15, 16 }
local TEAM_XP_NORMALIZATION = { [1] = 1, [2] = 1.6, [3] = 2.1, [4] = 2.6 }
local MAX_STAT_MODULE_TYPES = 4
local MAX_STAT_MODULE_LEVEL = 5
local MAX_COMMANDER_LEVEL = 60
local ROLE_HP_PER_LEVEL = 0.012
local ROLE_DAMAGE_PER_LEVEL = 0.008
local ROLE_LEVEL_TOTAL_XP = { [1] = 0 }
for level = 1, MAX_COMMANDER_LEVEL - 1 do
	local levelXP = math.ceil(22 + 2.5 * (level - 1) + 0.18 * (level - 1) ^ 2)
	ROLE_LEVEL_TOTAL_XP[level + 1] = ROLE_LEVEL_TOTAL_XP[level] + levelXP
end

local function roleLevelForXP(xp)
	local level = 1
	while level < MAX_COMMANDER_LEVEL and xp >= ROLE_LEVEL_TOTAL_XP[level + 1] do
		level = level + 1
	end
	return level
end

local STAT_MODULES = {
	{ id = "module_damage", name = "火控强化", type = "damage", icon = "攻击", category = "offense", values = { 0.08, 0.08, 0.08, 0.08, 0.08 }, rarityScale = { 1, 1.25, 1.5, 2 } },
	{ id = "module_reload", name = "超频核心", type = "reload", icon = "攻击", category = "offense", values = { 0.08, 0.08, 0.08, 0.08, 0.08 }, rarityScale = { 1, 1.25, 1.5, 2 } },
	{ id = "module_range", name = "精密测距", type = "range", icon = "射程", category = "offense", maxLevel = 4, values = { 0.07, 0.07, 0.07, 0.07 }, rarityScale = { 1, 1.25, 1.5, 2 } },
	{ id = "module_health", name = "重装骨架", type = "health", icon = "生命", category = "defense", values = { 0.12, 0.12, 0.12, 0.12, 0.12 }, rarityScale = { 1, 1.25, 1.5, 2 } },
	{ id = "module_move", name = "灵活推进", type = "move", icon = "速度", category = "defense", values = { 0.05, 0.05, 0.05, 0.05, 0.05 }, rarityScale = { 1, 1.25, 1.5, 2 } },
	{ id = "module_regen", name = "纳米循环", type = "combatRegen", icon = "生命", category = "defense", maxLevel = 4, values = { 0.001, 0.001, 0.001, 0.001 }, rarityScale = { 1, 1.25, 1.5, 2 } },
}
local STAT_MODULE_BONUS_CAPS = {
	damage = 0.40, reload = 0.40, range = 0.28,
	health = 0.60, move = 0.25, combatRegen = 0.004,
}
local RARITIES = {
	{ id = "common", name = "普通", scale = 1, weight = 70 },
	{ id = "uncommon", name = "优秀", scale = 1.25, weight = 25 },
	{ id = "rare", name = "稀有", scale = 1.5, weight = 4 },
	{ id = "epic", name = "史诗", scale = 2, weight = 1 },
}
local function moduleDescription(kind, value, total)
	if kind == "damage" or kind == "reload" or kind == "range" or kind == "aoe" or kind == "health" or kind == "move" then
		return string.format("+%.1f%%（累计 %.1f%%）", value * 100, total * 100)
	end
	return string.format("每秒恢复 +%.2f%% 最大生命（累计 %.2f%%）", value * 100, total * 100)
end

local UPGRADE_POOL = {
	{ id = "armor1", name = "复合装甲 I", desc = "+8% 伤害减免", type = "armor", value = 0.08, tier = 1, icon = "护甲", category = "defense" },
	{ id = "shield1", name = "能量护盾 I", desc = "+2000 护盾，消耗电力充能", type = "shield", value = 2000, tier = 1, icon = "护盾", category = "defense" },

	{ id = "armor2", name = "复合装甲 II", desc = "+12% 伤害减免", type = "armor", value = 0.12, tier = 2, icon = "护甲", category = "defense" },
	{ id = "shield2", name = "能量护盾 II", desc = "+3500 护盾容量", type = "shield", value = 3500, tier = 2, icon = "护盾", requires = "shield1", category = "defense" },
	-- 第一阶段在第二波时间边界、第三波开始前自动授予；后续阶段才进入候选池。
	{ id = "drone1", name = "轨道无人机 I", desc = "第二波时间结束、第三波开始时自动解锁 2 架无人机", type = "drone", value = 1, tier = 1, icon = "无人机", autoUnlock = true },

	{ id = "armor3", name = "相位装甲", desc = "+18% 伤害减免", type = "armor", value = 0.18, tier = 3, icon = "护甲", category = "defense" },
	{ id = "shield3", name = "能量护盾 III", desc = "+5000 护盾容量", type = "shield", value = 5000, tier = 3, icon = "护盾", requires = "shield2", category = "defense" },
	{ id = "drone2", name = "轨道无人机 II", desc = "+2 架无人机", type = "drone", value = 1, tier = 1, icon = "无人机", weight = 1.6, requires = "drone1" },
	{ id = "drone3", name = "轨道无人机 III", desc = "+2 架无人机", type = "drone", value = 1, tier = 1, icon = "无人机", weight = 1.6, requires = "drone2" },
	{ id = "drone4", name = "轨道无人机 IV", desc = "+2 架无人机（最多 8 架）", type = "drone", value = 1, tier = 1, icon = "无人机", weight = 1.6, requires = "drone3" },
	{ id = "blood_recycle1", name = "战利品回收 I", desc = "550 范围内队伍击杀恢复 0.6% 最大生命，内置冷却 2 秒", type = "bloodRecycle", value = 0.006, tier = 1, icon = "生命", weight = 0.8 },
	{ id = "blood_recycle2", name = "战利品回收 II", desc = "击杀恢复提高至 0.8% 最大生命，内置冷却仍为 2 秒", type = "bloodRecycle", value = 0.008, tier = 2, icon = "生命", weight = 0.8, requires = "blood_recycle1" },
	{ id = "rl_card_lifedrain", name = "能量汲取 I", desc = "吸血率 0% → 12%：合格直接有效伤害转为治疗；触发型治疗共用 0.6% 最大生命/秒上限", type = "lifeDrain", value = 0.12, tier = 1, icon = "生命", weight = 0.8, category = "defense" },
	{ id = "rl_card_lifedrain2", name = "能量汲取 II", desc = "吸血率 12% → 18%；仍受触发型治疗上限约束", type = "lifeDrain", value = 0.18, tier = 2, icon = "生命", weight = 0.8, requires = "rl_card_lifedrain", category = "defense" },
	{ id = "rl_card_hit_repair", name = "纳米回馈 I", desc = "命中回复 0% → 0.12% 最大生命/次；同一目标 0.25 秒限一次，与吸血共用上限", type = "hitRepair", value = 0.0012, tier = 1, icon = "生命", weight = 0.7, category = "defense" },
	{ id = "rl_card_hit_repair2", name = "纳米回馈 II", desc = "命中回复 0.12% → 0.20% 最大生命；同一目标 0.25 秒限一次", type = "hitRepair", value = 0.0020, tier = 2, icon = "生命", weight = 0.7, requires = "rl_card_hit_repair", category = "defense" },
	{ id = "rl_trait_aoe_leech", name = "范围汲取 I", desc = "解锁爆炸/溅射吸血：有效生命伤害的 20%，仍受治疗上限约束", type = "areaLeech", value = 0.20, tier = 2, icon = "生命", weight = 0.45, requires = "rl_card_lifedrain", category = "defense" },
	{ id = "rl_trait_aoe_leech2", name = "范围汲取 II", desc = "范围吸血系数 20% → 25%", type = "areaLeech", value = 0.25, tier = 3, icon = "生命", weight = 0.35, requires = "rl_trait_aoe_leech", category = "defense" },
	{ id = "rl_trait_dot_leech", name = "持续汲取 I", desc = "解锁燃烧/持续伤害吸血：有效生命伤害的 10%，按持续治疗预算结算", type = "dotLeech", value = 0.10, tier = 2, icon = "生命", weight = 0.4, requires = "rl_card_lifedrain", category = "defense" },
	{ id = "rl_trait_dot_leech2", name = "持续汲取 II", desc = "持续伤害吸血系数 10% → 15%", type = "dotLeech", value = 0.15, tier = 3, icon = "生命", weight = 0.3, requires = "rl_trait_dot_leech", category = "defense" },
	{ id = "blast_lining1", name = "防爆夹层 I", desc = "指定自爆威胁造成的伤害降低 20%", type = "blastLining", value = 0.20, tier = 1, icon = "护甲", weight = 0.8, category = "defense" },
	{ id = "blast_lining2", name = "防爆夹层 II", desc = "指定自爆威胁造成的伤害降低提高至 30%", type = "blastLining", value = 0.30, tier = 2, icon = "护甲", weight = 0.8, requires = "blast_lining1", category = "defense" },
}

-- 商店定义由 synced 端持有并验证；LuaUI 中的同名表只负责展示。
local SHOP_ITEMS = {
	damage  = { id = "damage", name = "武器强化", desc = "+2% 武器伤害", baseCost = 80, costStep = 60, maxLevel = 20, type = "damage", value = 1.02 },
	health  = { id = "health", name = "装甲强化", desc = "+10% 最大生命值", baseCost = 100, costStep = 75, maxLevel = 20, type = "healthPercent", value = 0.10 },
	regen   = { id = "regen", name = "纳米修复", desc = "开局准备或脱战额外回复 +0.30% 最大生命/秒，购买后回满生命", baseCost = 250, costStep = 220, maxLevel = 5, type = "regenPercent", value = 0.003 },
	reload  = { id = "reload", name = "冷却强化", desc = "+8% 攻击速度", baseCost = 120, costStep = 90, maxLevel = 15, type = "reload", value = 1.08 },
	move    = { id = "move", name = "机动强化", desc = "+6% 移动速度", baseCost = 100, costStep = 75, maxLevel = 15, type = "move", value = 1.06 },
	range   = { id = "range", name = "火控强化", desc = "+5% 武器射程", baseCost = 150, costStep = 125, maxLevel = 8, type = "range", value = 1.05 },
	salvage = { id = "salvage", name = "残骸精炼", desc = "+15% 残骸金属收益", baseCost = 120, costStep = 100, maxLevel = 10, type = "salvage", value = 1.15 },
	salvage_speed = { id = "salvage_speed", name = "快速回收", desc = "+15% 残骸吸收速度", baseCost = 100, costStep = 80, maxLevel = 10, type = "salvageSpeed", value = 1.15 },
	lightning_weapon = { id = "lightning_weapon", name = "雷霆步枪", desc = "解锁近程连锁闪电武器", baseCost = 1200, costStep = 0, maxLevel = 1, type = "weapon", weaponNum = 5 },
	plasma_weapon = { id = "plasma_weapon", name = "Tzar 重型主炮", desc = "解锁 Cortex Tzar 的 1100 伤害重型主炮", baseCost = 1800, costStep = 0, maxLevel = 1, type = "weapon", weaponNum = 6 },
	sniper_weapon = { id = "sniper_weapon", name = "湮灭狙击光束", desc = "解锁高伤害远程单体武器", baseCost = 2800, costStep = 0, maxLevel = 1, type = "weapon", weaponNum = 7 },
	barrage_weapon = { id = "barrage_weapon", name = "凝固汽油覆盖炮", desc = "解锁超远程范围覆盖打击", baseCost = 2700, costStep = 0, maxLevel = 1, type = "weapon", weaponNum = 8 },
	shockwave_weapon = { id = "shockwave_weapon", name = "冲击清场炮", desc = "解锁击退与清杂范围武器", baseCost = 2200, costStep = 0, maxLevel = 1, type = "weapon", weaponNum = 9 },
	meteor_weapon = { id = "meteor_weapon", name = "陨星自动打击", desc = "自动锁定并召下陨石；Lv.2 落地灼烧，Lv.3 增加数量，Lv.4 分裂", baseCost = 2200, costStep = 1200, maxLevel = 4, type = "supportSkill" },
	lightning_extension = { id = "lightning_extension", name = "超导分叉", desc = "连锁范围、目标数与直击伤害强化", baseCost = 900, costStep = 600, maxLevel = 3, type = "weaponExtension", requires = "lightning_weapon" },
	plasma_extension = { id = "plasma_extension", name = "裂变弹头", desc = "强化 Tzar 主炮直击与溅射伤害；解锁余震重击", baseCost = 1100, costStep = 750, maxLevel = 3, type = "weaponExtension", requires = "plasma_weapon" },
	sniper_extension = { id = "sniper_extension", name = "处决协议", desc = "强化对低生命目标的狙击伤害；解锁延迟打击", baseCost = 1500, costStep = 1000, maxLevel = 3, type = "weaponExtension", requires = "sniper_weapon" },
	barrage_extension = { id = "barrage_extension", name = "燃烧增压", desc = "强化炮击与持续燃烧伤害；解锁燃烧区域", baseCost = 1300, costStep = 850, maxLevel = 3, type = "weaponExtension", requires = "barrage_weapon" },
	shockwave_extension = { id = "shockwave_extension", name = "动能粉碎", desc = "强化对轻型单位的冲击伤害；解锁范围爆裂", baseCost = 1000, costStep = 700, maxLevel = 3, type = "weaponExtension", requires = "shockwave_weapon" },
	rl_coop_medical_beacon = { id = "rl_coop_medical_beacon", name = "团队修复信标", desc = "350 范围盟友指挥官在 8 秒内恢复最多 12% 生命；每人冷却 65 秒，消耗 350 电力", baseCost = 1800, costStep = 0, maxLevel = 1, type = "supportSkill" },
}

local FACTION_WEAPON_ITEMS = {}
for faction, factionConfig in pairs(factionWeaponCatalog.factions) do
	for _, weapon in ipairs(factionConfig.weapons) do
		FACTION_WEAPON_ITEMS[weapon.id] = weapon
		SHOP_ITEMS[weapon.id] = {
			id = weapon.id,
			name = weapon.name,
			desc = weapon.desc,
			baseCost = weapon.baseCost,
			costStep = 0,
			maxLevel = 3,
			type = "factionWeapon",
			faction = faction,
			unlockAt = weapon.unlockAt or 0,
		}
	end
end

local playerUnitID
local playerTeamID
local pendingChoices = {}
local choiceIdCounter = 0
local upgradeCount = 0
local commanderLevel = 1
local sharedXP = 0
local offersEarned = 0
local waveOfferTarget = 0
local statModuleLevels = {}
local statModuleBonuses = {}
local trainingLevels = {}
local refreshesRemaining = 2
local skipsRemaining = 1
local banishesRemaining = 1
local banishedCardIds = {}
local activeChoiceId
local showNextPendingChoice
local acquiredUpgradeIds = {}
local shopLevels = {}
local equippedFactionWeapons = {}
local personalEvent
local processedRequests = {}
local lastItemRequestFrame = {}

local function serializeAcquiredOptions()
	local items = {}
	for _, upgrade in ipairs(UPGRADE_POOL) do
		if acquiredUpgradeIds[upgrade.id] then
			items[#items + 1] = table.concat({ upgrade.name, upgrade.desc, 1 }, "|")
		end
	end
	for _, module in ipairs(STAT_MODULES) do
		local level = statModuleLevels[module.type] or 0
		if level > 0 then
			local bonus = statModuleBonuses[module.type] or 0
			items[#items + 1] = table.concat({ module.name .. " Lv." .. level,
				string.format("累计 +%.1f%%", bonus * 100), level }, "|")
		end
	end
	for stat, level in pairs(trainingLevels) do
		local label = stat == "health" and "生命" or stat == "damage" and "伤害" or "攻速"
		items[#items + 1] = table.concat({ "基础训练：" .. label .. " Lv." .. level,
			string.format("累计 +%.1f%%", (statModuleBonuses[stat] or 0) * 100), level }, "|")
	end
	local shopItemIds = {}
	for itemId, level in pairs(shopLevels) do
		if level > 0 then shopItemIds[#shopItemIds + 1] = itemId end
	end
	table.sort(shopItemIds)
	for _, itemId in ipairs(shopItemIds) do
		local item = SHOP_ITEMS[itemId]
		local level = shopLevels[itemId]
		if item then
			items[#items + 1] = table.concat({ item.name, item.desc, level }, "|")
		end
	end
	return table.concat(items, ";")
end

local function sendAcquiredOptions()
	personalEvent("RoguelikeUpgradeList", serializeAcquiredOptions())
end

local cumulativeMultipliers = {
	reload = 1.0,
	move = 1.0,
	health = 1.0,
	shopHealthBonus = 0,
	regenBonus = 0,
	damage = 1.0,
	range = 1.0,
	sight = 1.0,
	armor = 0,
	shield = 0,
	drone = 0,
	salvage = 1.0,
	salvageSpeed = 1.0,
	salvageRadius = BASE_SALVAGE_RADIUS,
	combatRegen = 0,
	bloodRecycle = 0,
	lifeDrain = 0,
	hitRepair = 0,
	areaLeech = 0,
	dotLeech = 0,
	blastLining = 0,
}
local summonMultipliers = {
	health = 1.0,
	move = 1.0,
	damage = 1.0,
	reload = 1.0,
	range = 1.0,
}
local function effectiveStatMultiplier(kind)
	return 1 + (statModuleBonuses[kind] or 0)
end

local function effectiveDamageMultiplier()
	return cumulativeMultipliers.damage * (1 + (statModuleBonuses.damage or 0)
		+ math.max(0, commanderLevel - 1) * ROLE_DAMAGE_PER_LEVEL)
end

local function effectiveCombatRegen()
	return math.min(0.004, cumulativeMultipliers.combatRegen + (statModuleBonuses.combatRegen or 0))
end
local shieldCurrent = 0
local lastShieldHitFrame = 0
local lastHealthDamageFrame = 0
local baseCommanderMaxHealth
local baseCommanderEnergyMake = 0
local focusGuardWindowStartFrame = 0
local focusGuardRawDamage = 0
local commanderWeaponSlotByDefID = {}
local commanderWeaponShopItemByDefID = {}
local shieldWeaponNum
local activeSkillCooldownEndFrame = {}
local nanoRepairEndFrame = 0
local nanoRepairNextTickFrame = 0
local nanoRepairTicksRemaining = 0
local thrusterEndFrame = 0
local barrierPoints = 0
local barrierEndFrame = 0
local bastionEndFrame = 0
local repairLinkEndFrame = 0
local repairLinkTargets = {}
local medicalBeaconCooldownEndFrame = 0
local healBudgetSecond = -1
local healBudgetUsed = 0
local damageHealBudgetSecond = -1
local damageHealBudgetUsed = 0
local healingTotals = {}
local lastBloodRecycleFrame = -Game.gameSpeed * 100
local lastHitRepairByTarget = {}
local damageHealRecentEvents = {}
local lastDamageHealCleanupFrame = 0
local pendingDamageByTarget = {}
local explicitDamageHealContexts = {}
local nextMedkitPickupFrame = 0
local medkitsByFeature = {}
local medkitKillProgress = 0
local activeMedicalBeacon
local activeRepairLink
local medkitFeatureDefID = FeatureDefNames.roguelike_medkit and FeatureDefNames.roguelike_medkit.id
local initialCumulativeMultipliers = table.copy(cumulativeMultipliers)
local initialSummonMultipliers = table.copy(summonMultipliers)
local statesByTeam = {}

-- Existing upgrade functions operate on one selected commander. In Coop each
-- synced callin selects the sender/target Team, runs those functions, then
-- stores every mutable field back to that Team. The global wave is not copied.
local function selectTeam(teamID)
	local state = statesByTeam[teamID]
	if not state then
		state = {
			playerTeamID = teamID, pendingChoices = {},
			choiceIdCounter = 0, upgradeCount = 0, acquiredUpgradeIds = {},
			commanderLevel = 1, sharedXP = 0, offersEarned = 0, waveOfferTarget = 0,
			statModuleLevels = {}, refreshesRemaining = 2, skipsRemaining = 1,
			statModuleBonuses = {},
			trainingLevels = {},
			banishesRemaining = 1, banishedCardIds = {}, activeChoiceId = nil,
			shopLevels = {}, equippedFactionWeapons = {},
			processedRequests = {}, lastItemRequestFrame = {},
			cumulativeMultipliers = table.copy(initialCumulativeMultipliers),
			summonMultipliers = table.copy(initialSummonMultipliers),
			shieldCurrent = 0, lastShieldHitFrame = 0, lastHealthDamageFrame = 0,
			baseCommanderEnergyMake = 0, focusGuardWindowStartFrame = 0,
			focusGuardRawDamage = 0, commanderWeaponSlotByDefID = {},
			commanderWeaponShopItemByDefID = {},
			shieldWeaponNum = nil,
			activeSkillCooldownEndFrame = {}, nanoRepairEndFrame = 0,
			nanoRepairNextTickFrame = 0, nanoRepairTicksRemaining = 0,
			thrusterEndFrame = 0, barrierPoints = 0, barrierEndFrame = 0,
			bastionEndFrame = 0, repairLinkEndFrame = 0, repairLinkTargets = {},
			medicalBeaconCooldownEndFrame = 0, healBudgetSecond = -1, healBudgetUsed = 0,
			damageHealBudgetSecond = -1, damageHealBudgetUsed = 0,
			healingTotals = {}, lastBloodRecycleFrame = -Game.gameSpeed * 100,
			lastHitRepairByTarget = {}, damageHealRecentEvents = {}, lastDamageHealCleanupFrame = 0,
			nextMedkitPickupFrame = 0,
		}
		statesByTeam[teamID] = state
	end
	playerUnitID, playerTeamID = state.playerUnitID, teamID
	pendingChoices = state.pendingChoices
	choiceIdCounter, upgradeCount = state.choiceIdCounter, state.upgradeCount
	commanderLevel, sharedXP = state.commanderLevel or 1, state.sharedXP or 0
	offersEarned, waveOfferTarget = state.offersEarned or 0, state.waveOfferTarget or 0
	statModuleLevels = state.statModuleLevels or {}
	statModuleBonuses = state.statModuleBonuses or {}
	trainingLevels = state.trainingLevels or {}
	refreshesRemaining, skipsRemaining = state.refreshesRemaining or 2, state.skipsRemaining or 1
	banishesRemaining, banishedCardIds = state.banishesRemaining or 1, state.banishedCardIds or {}
	activeChoiceId = state.activeChoiceId
	acquiredUpgradeIds, shopLevels = state.acquiredUpgradeIds, state.shopLevels
	equippedFactionWeapons = state.equippedFactionWeapons
	processedRequests, lastItemRequestFrame = state.processedRequests, state.lastItemRequestFrame
	cumulativeMultipliers, summonMultipliers = state.cumulativeMultipliers, state.summonMultipliers
	shieldCurrent, lastShieldHitFrame = state.shieldCurrent, state.lastShieldHitFrame
	lastHealthDamageFrame, baseCommanderMaxHealth = state.lastHealthDamageFrame, state.baseCommanderMaxHealth
	baseCommanderEnergyMake = state.baseCommanderEnergyMake
	focusGuardWindowStartFrame, focusGuardRawDamage = state.focusGuardWindowStartFrame, state.focusGuardRawDamage
	commanderWeaponSlotByDefID = state.commanderWeaponSlotByDefID
	commanderWeaponShopItemByDefID = state.commanderWeaponShopItemByDefID
	shieldWeaponNum = state.shieldWeaponNum
	activeSkillCooldownEndFrame = state.activeSkillCooldownEndFrame
	nanoRepairEndFrame, nanoRepairNextTickFrame = state.nanoRepairEndFrame, state.nanoRepairNextTickFrame
	nanoRepairTicksRemaining = state.nanoRepairTicksRemaining
	thrusterEndFrame = state.thrusterEndFrame
	barrierPoints, barrierEndFrame = state.barrierPoints, state.barrierEndFrame
	bastionEndFrame = state.bastionEndFrame
	repairLinkEndFrame, repairLinkTargets = state.repairLinkEndFrame, state.repairLinkTargets
	medicalBeaconCooldownEndFrame = state.medicalBeaconCooldownEndFrame
	healBudgetSecond, healBudgetUsed = state.healBudgetSecond, state.healBudgetUsed
	damageHealBudgetSecond, damageHealBudgetUsed = state.damageHealBudgetSecond or -1, state.damageHealBudgetUsed or 0
	healingTotals, lastBloodRecycleFrame = state.healingTotals, state.lastBloodRecycleFrame
	lastHitRepairByTarget = state.lastHitRepairByTarget or {}
	damageHealRecentEvents = state.damageHealRecentEvents or {}
	lastDamageHealCleanupFrame = state.lastDamageHealCleanupFrame or 0
	nextMedkitPickupFrame = state.nextMedkitPickupFrame
	return state
end

local function storeTeam(state)
	state.playerUnitID = playerUnitID
	state.choiceIdCounter, state.upgradeCount = choiceIdCounter, upgradeCount
	state.commanderLevel, state.sharedXP = commanderLevel, sharedXP
	state.offersEarned, state.waveOfferTarget = offersEarned, waveOfferTarget
	state.statModuleLevels = statModuleLevels
	state.statModuleBonuses = statModuleBonuses
	state.trainingLevels = trainingLevels
	state.refreshesRemaining, state.skipsRemaining = refreshesRemaining, skipsRemaining
	state.banishesRemaining, state.banishedCardIds = banishesRemaining, banishedCardIds
	state.activeChoiceId = activeChoiceId
	state.shieldCurrent, state.lastShieldHitFrame = shieldCurrent, lastShieldHitFrame
	state.lastHealthDamageFrame, state.baseCommanderMaxHealth = lastHealthDamageFrame, baseCommanderMaxHealth
	state.baseCommanderEnergyMake = baseCommanderEnergyMake
	state.focusGuardWindowStartFrame, state.focusGuardRawDamage = focusGuardWindowStartFrame, focusGuardRawDamage
	state.commanderWeaponSlotByDefID = commanderWeaponSlotByDefID
	state.commanderWeaponShopItemByDefID = commanderWeaponShopItemByDefID
	state.shieldWeaponNum = shieldWeaponNum
	state.activeSkillCooldownEndFrame = activeSkillCooldownEndFrame
	state.nanoRepairEndFrame, state.nanoRepairNextTickFrame = nanoRepairEndFrame, nanoRepairNextTickFrame
	state.nanoRepairTicksRemaining = nanoRepairTicksRemaining
	state.thrusterEndFrame = thrusterEndFrame
	state.barrierPoints, state.barrierEndFrame = barrierPoints, barrierEndFrame
	state.bastionEndFrame = bastionEndFrame
	state.repairLinkEndFrame, state.repairLinkTargets = repairLinkEndFrame, repairLinkTargets
	state.medicalBeaconCooldownEndFrame = medicalBeaconCooldownEndFrame
	state.healBudgetSecond, state.healBudgetUsed = healBudgetSecond, healBudgetUsed
	state.damageHealBudgetSecond, state.damageHealBudgetUsed = damageHealBudgetSecond, damageHealBudgetUsed
	state.healingTotals, state.lastBloodRecycleFrame = healingTotals, lastBloodRecycleFrame
	state.lastHitRepairByTarget = lastHitRepairByTarget
	state.damageHealRecentEvents = damageHealRecentEvents
	state.lastDamageHealCleanupFrame = lastDamageHealCleanupFrame
	state.nextMedkitPickupFrame = nextMedkitPickupFrame
	state.summonMultipliers = summonMultipliers
end

local function withTeam(teamID, callback, ...)
	if not COOP_ENABLED then return callback(...) end
	if not teamID then return end
	local previousTeamID = playerTeamID
	if previousTeamID and statesByTeam[previousTeamID] then
		storeTeam(statesByTeam[previousTeamID])
	end
	local state = selectTeam(teamID)
	local ok, result = pcall(callback, ...)
	storeTeam(state)
	if previousTeamID and previousTeamID ~= teamID and statesByTeam[previousTeamID] then
		selectTeam(previousTeamID)
	end
	if not ok then error(result, 0) end
	return result
end

personalEvent = function(action, ...)
	SendToUnsynced(action, playerTeamID or -1, ...)
end

local function isCommander(unitDefID)
	local unitDef = unitDefID and UnitDefs[unitDefID]
	return unitDef and unitDef.customParams and unitDef.customParams.iscommander
end

local function isHumanTeam(teamID)
	local _, _, _, isAI = Spring.GetTeamInfo(teamID)
	return not isAI
end

local function getPlayerTeam(playerID)
	local _, active, spectator, teamID = Spring.GetPlayerInfo(playerID, false)
	if not active or spectator then
		return nil
	end
	return teamID
end

local function serializeChoices(choices)
	local parts = {}
	for _, choice in ipairs(choices) do
		parts[#parts + 1] = table.concat({ choice.id, choice.name, choice.desc, choice.icon }, "|")
	end
	return table.concat(parts, ";")
end

local function maxAvailableTier()
	if commanderLevel >= 9 then return 3 end
	if commanderLevel >= 5 then return 2 end
	return 1
end

local function rollRarity()
	local wave = GG.Roguelike and GG.Roguelike.currentWave or 1
	local weights = wave <= 4 and { 70, 25, 4, 1 } or { 55, 32, 11, 2 }
	local total, roll = 0, math.random(1, 100)
	for index, rarity in ipairs(RARITIES) do
		total = total + weights[index]
		if roll <= total then return rarity end
	end
	return RARITIES[1]
end

local function pickRandomChoices(count, excludedIds)
	local maxTier = maxAvailableTier()
	local pool = {}
	for _, upgrade in ipairs(UPGRADE_POOL) do
		local prerequisiteMet = not upgrade.requires or acquiredUpgradeIds[upgrade.requires]
		if not upgrade.autoUnlock and not acquiredUpgradeIds[upgrade.id]
			and not banishedCardIds[upgrade.id] and not (excludedIds and excludedIds[upgrade.id])
			and prerequisiteMet and upgrade.tier <= maxTier then
			pool[#pool + 1] = upgrade
		end
	end
	for _, module in ipairs(STAT_MODULES) do
		local level = statModuleLevels[module.type] or 0
		local maxLevel = module.maxLevel or MAX_STAT_MODULE_LEVEL
		local hasSlot = level > 0 or (function()
			local kinds = 0
			for _, current in pairs(statModuleLevels) do if current > 0 then kinds = kinds + 1 end end
			return kinds < MAX_STAT_MODULE_TYPES
		end)()
		local candidateID = module.id .. "_l" .. (level + 1)
		local cap = STAT_MODULE_BONUS_CAPS[module.type] or math.huge
		if level < maxLevel and (statModuleBonuses[module.type] or 0) < cap and hasSlot and not banishedCardIds[candidateID]
			and not (excludedIds and excludedIds[candidateID]) then
			pool[#pool + 1] = {
				id = candidateID, name = module.name, desc = "", type = module.type,
				icon = module.icon, category = module.category, module = module,
				moduleLevel = level + 1,
			}
		end
	end

	-- synced math.random 在所有客户端按相同顺序执行；权重相同的卡不会重复出现。
	local function drawFrom(candidates)
		if #candidates == 0 then return nil end
		local totalWeight = 0
		for _, upgrade in ipairs(candidates) do
			totalWeight = totalWeight + (upgrade.weight or 1)
		end
		local roll = math.random() * totalWeight
		local accumulated = 0
		for index, upgrade in ipairs(candidates) do
			accumulated = accumulated + (upgrade.weight or 1)
			if roll <= accumulated then
			local choice = table.remove(candidates, index)
			if choice.module then
				local rarity = rollRarity()
				local index = choice.moduleLevel
				local current = statModuleBonuses[choice.type] or 0
				local amount = math.min(choice.module.values[index] * rarity.scale,
					(STAT_MODULE_BONUS_CAPS[choice.type] or math.huge) - current)
				choice.value = amount
				choice.rarity = rarity.name
				choice.desc = string.format("Lv.%d · %s · %s", index, rarity.name,
					moduleDescription(choice.type, amount, current + amount))
				choice.name = choice.module.name .. " " .. rarity.name
			end
			return choice
			end
		end
		return table.remove(candidates, #candidates)
	end

	-- 每次候选至少 1 张防御卡（生命/护甲/护盾）。第三波的压力已经翻倍，
	-- 若三张全是攻击/移速/无人机，玩家会在没有任何 EHP 成长的情况下暴毙。
	-- 无人机卡仍按 1.6 权重留在通用池，不额外占槽。
	local defensePool = {}
	for _, upgrade in ipairs(pool) do
		if upgrade.category == "defense" or upgrade.module and upgrade.module.category == "defense" then
			defensePool[#defensePool + 1] = upgrade
		end
	end

	local result = {}
	local defenseChoice = drawFrom(defensePool)
	if defenseChoice then
		result[#result + 1] = defenseChoice
		for index = #pool, 1, -1 do
			if pool[index] == defenseChoice then
				table.remove(pool, index)
				break
			end
		end
	end
	while #result < count and #pool > 0 do
		local nextChoice = drawFrom(pool)
		if not nextChoice then break end
		result[#result + 1] = nextChoice
	end
	local trainingChoices = {
		{ id = "training_health", name = "基础训练：坚韧", desc = "+1% 最大生命值", icon = "生命", type = "training", trainingStat = "health", value = 0.01, category = "defense" },
		{ id = "training_damage", name = "基础训练：火力", desc = "+1% 全局伤害", icon = "攻击", type = "training", trainingStat = "damage", value = 0.01 },
		{ id = "training_reload", name = "基础训练：超频", desc = "+1% 攻击速度", icon = "攻击", type = "training", trainingStat = "reload", value = 0.01 },
	}
	local hasDefense = false
	for _, choice in ipairs(result) do
		if choice.category == "defense" or choice.module and choice.module.category == "defense"
			or choice.trainingStat == "health" then hasDefense = true end
	end
	if not hasDefense and not banishedCardIds.training_health
		and not (excludedIds and excludedIds.training_health) then
		local safeTraining = trainingChoices[1]
		if #result < count then result[#result + 1] = safeTraining else result[#result] = safeTraining end
	end
	for _, fallback in ipairs(trainingChoices) do
		if #result >= count then break end
		local present = false
		for _, choice in ipairs(result) do if choice.id == fallback.id then present = true end end
		if not present and not banishedCardIds[fallback.id] and not (excludedIds and excludedIds[fallback.id]) then
			result[#result + 1] = fallback
		end
	end
	if #result == 0 then
		result[1] = trainingChoices[1]
	end
	return result
end

local function applySummonGrowth()
	if GG.Roguelike and GG.Roguelike.SetSummonGrowthMultipliers then
		GG.Roguelike.SetSummonGrowthMultipliers(
			playerTeamID,
			summonMultipliers.health,
			summonMultipliers.move,
			summonMultipliers.damage,
			summonMultipliers.reload,
			summonMultipliers.range
		)
	end
end

local function applyWeaponRange(unitID)
	local unitDef = UnitDefs[Spring.GetUnitDefID(unitID)]
	if not unitDef then return end

	local maxRange = 0
	local setWeaponAttribute = GG.UnitAttributes and GG.UnitAttributes.SetUnitWeaponAttribute
	for weaponNum, weapon in ipairs(unitDef.weapons) do
		local weaponDef = WeaponDefs[weapon.weaponDef]
		if weaponDef then
			local customParams = weaponDef.customParams or {}
			local unlockItemId = customParams.roguelike_shop_item
			local unlocked = not unlockItemId or (shopLevels[unlockItemId] or 0) > 0
			if unlockItemId and FACTION_WEAPON_ITEMS[unlockItemId] then
				unlocked = unlocked and equippedFactionWeapons[unlockItemId] == true
			end
			local range = unlocked and weaponDef.range * cumulativeMultipliers.range * effectiveStatMultiplier("range") or 0
			-- The Unit Attributes gadget rewrites weapon ranges after stat updates.
			-- Register the ownership gate there so an unowned slot cannot regain range.
			if setWeaponAttribute then
				setWeaponAttribute(unitID, weaponNum, "maxWeaponRange", range, "roguelike_weapon_pool")
			end
			Spring.SetUnitWeaponState(unitID, weaponNum, "range", range)
			local factionWeapon = unlockItemId and FACTION_WEAPON_ITEMS[unlockItemId]
			if factionWeapon and GG.UnitAttributes and GG.UnitAttributes.SetUnitWeaponModifier then
				local reload = factionWeapon.reload
				for level = 1, math.min((shopLevels[unlockItemId] or 0) - 1, #(factionWeapon.levels or {})) do
					reload = factionWeapon.levels[level].reload or reload
				end
				GG.UnitAttributes.SetUnitWeaponModifier(unitID, weaponNum, "reloadTime",
					reload / factionWeapon.reload, "roguelike_weapon_level")
			end
			if unlocked then
				maxRange = math.max(maxRange, range)
			end
		end
	end
	if maxRange > 0 then
		Spring.SetUnitMaxRange(unitID, maxRange)
		Spring.SetUnitRulesParam(unitID, "upgradedRange", maxRange, INLOS_ACCESS)
	end
end

local function cacheCommanderWeaponSlots(unitID)
	commanderWeaponSlotByDefID = {}
	commanderWeaponShopItemByDefID = {}
	shieldWeaponNum = nil
	local unitDef = UnitDefs[Spring.GetUnitDefID(unitID)]
	if not unitDef then return end
	for weaponNum, weapon in ipairs(unitDef.weapons or {}) do
		if weapon.weaponDef then
			commanderWeaponSlotByDefID[weapon.weaponDef] = weaponNum
			local weaponDef = WeaponDefs[weapon.weaponDef]
			local customParams = weaponDef and weaponDef.customParams or {}
			if customParams.roguelike_shop_item then
				commanderWeaponShopItemByDefID[weapon.weaponDef] = customParams.roguelike_shop_item
			end
			if customParams.roguelike_personal_shield then
				shieldWeaponNum = weaponNum
			end
		end
	end
end

local function findShopWeaponSlot(unitDef, itemId)
	for weaponNum, weapon in ipairs(unitDef and unitDef.weapons or {}) do
		local weaponDef = weapon.weaponDef and WeaponDefs[weapon.weaponDef]
		local customParams = weaponDef and weaponDef.customParams
		if customParams and customParams.roguelike_shop_item == itemId then
			return weaponNum
		end
	end
	return nil
end

local function writeProgressRules(unitID)
	Spring.SetUnitRulesParam(unitID, "roguelike_reload_mult", cumulativeMultipliers.reload * effectiveStatMultiplier("reload"), INLOS_ACCESS)
	Spring.SetUnitRulesParam(unitID, "roguelike_move_mult", cumulativeMultipliers.move * effectiveStatMultiplier("move"), INLOS_ACCESS)
	Spring.SetUnitRulesParam(unitID, "roguelike_health_mult", cumulativeMultipliers.health + cumulativeMultipliers.shopHealthBonus
		+ (commanderLevel - 1) * ROLE_HP_PER_LEVEL + (statModuleBonuses.health or 0), INLOS_ACCESS)
	Spring.SetUnitRulesParam(unitID, "roguelike_base_max_health", baseCommanderMaxHealth or 0, INLOS_ACCESS)
	Spring.SetUnitRulesParam(unitID, "roguelike_shop_health_bonus", cumulativeMultipliers.shopHealthBonus, INLOS_ACCESS)
	Spring.SetUnitRulesParam(unitID, "roguelike_health_regen_rate", BASE_HEALTH_REGEN_PER_SECOND + cumulativeMultipliers.regenBonus, INLOS_ACCESS)
	Spring.SetUnitRulesParam(unitID, "roguelike_health_regen_delay", HEALTH_REGEN_DELAY / Game.gameSpeed, INLOS_ACCESS)
	-- 休整阶段的额外回复；UI/诊断可据此区分“脱战回复”和“休整回复”。
	Spring.SetUnitRulesParam(unitID, "roguelike_recovery_heal_rate", RECOVERY_HEAL_PER_SECOND, INLOS_ACCESS)
	Spring.SetUnitRulesParam(unitID, "roguelike_damage_mult", effectiveDamageMultiplier(), INLOS_ACCESS)
	Spring.SetUnitRulesParam(unitID, "roguelike_range_mult", cumulativeMultipliers.range * effectiveStatMultiplier("range"), INLOS_ACCESS)
	Spring.SetUnitRulesParam(unitID, "roguelike_sight_mult", cumulativeMultipliers.sight, INLOS_ACCESS)
	Spring.SetUnitRulesParam(unitID, "roguelike_armor_reduction", cumulativeMultipliers.armor, INLOS_ACCESS)
	Spring.SetUnitRulesParam(unitID, "roguelike_shield_capacity", cumulativeMultipliers.shield, INLOS_ACCESS)
	Spring.SetUnitRulesParam(unitID, "roguelike_shield_current", shieldCurrent, INLOS_ACCESS)
	Spring.SetUnitRulesParam(unitID, "roguelike_shield_energy_per_point", SHIELD_ENERGY_PER_POINT, INLOS_ACCESS)
	Spring.SetUnitRulesParam(unitID, "roguelike_combat_regen", effectiveCombatRegen(), INLOS_ACCESS)
	Spring.SetUnitRulesParam(unitID, "roguelike_blood_recycle", cumulativeMultipliers.bloodRecycle, INLOS_ACCESS)
	Spring.SetUnitRulesParam(unitID, "roguelike_lifedrain_rate", cumulativeMultipliers.lifeDrain, INLOS_ACCESS)
	Spring.SetUnitRulesParam(unitID, "roguelike_hit_repair_fraction", cumulativeMultipliers.hitRepair, INLOS_ACCESS)
	Spring.SetUnitRulesParam(unitID, "roguelike_aoe_leech_coefficient", cumulativeMultipliers.areaLeech, INLOS_ACCESS)
	Spring.SetUnitRulesParam(unitID, "roguelike_dot_leech_coefficient", cumulativeMultipliers.dotLeech, INLOS_ACCESS)
	Spring.SetUnitRulesParam(unitID, "roguelike_damage_heal_cap", DAMAGE_TRIGGER_HEAL_CAP_PER_SECOND, INLOS_ACCESS)
	Spring.SetUnitRulesParam(unitID, "roguelike_damage_heal_used", damageHealBudgetUsed, INLOS_ACCESS)
	Spring.SetUnitRulesParam(unitID, "roguelike_blast_lining", cumulativeMultipliers.blastLining, INLOS_ACCESS)
	Spring.SetUnitRulesParam(unitID, "roguelike_barrier_current", barrierPoints, INLOS_ACCESS)
	Spring.SetUnitRulesParam(unitID, "roguelike_barrier_expiry", barrierEndFrame, INLOS_ACCESS)
	Spring.SetUnitRulesParam(unitID, "roguelike_bastion_expiry", bastionEndFrame, INLOS_ACCESS)
	Spring.SetUnitRulesParam(unitID, "roguelike_repair_link_expiry", repairLinkEndFrame, INLOS_ACCESS)
	for skillID, endFrame in pairs(activeSkillCooldownEndFrame) do
		Spring.SetUnitRulesParam(unitID, "roguelike_skill_cd_" .. skillID, endFrame, INLOS_ACCESS)
	end
	Spring.SetUnitRulesParam(unitID, "roguelike_skill_cd_medical_beacon", medicalBeaconCooldownEndFrame, INLOS_ACCESS)
	Spring.SetUnitRulesParam(unitID, "roguelike_skill_active_nanorepair", nanoRepairEndFrame, INLOS_ACCESS)
	Spring.SetUnitRulesParam(unitID, "roguelike_skill_active_thruster", thrusterEndFrame, INLOS_ACCESS)
	for source, total in pairs(healingTotals) do
		Spring.SetUnitRulesParam(unitID, "roguelike_heal_total_" .. source, total, INLOS_ACCESS)
	end
	Spring.SetUnitRulesParam(unitID, "roguelike_energy_income",
		baseCommanderEnergyMake + upgradeCount * ENERGY_INCOME_PER_UPGRADE, INLOS_ACCESS)
	Spring.SetUnitRulesParam(unitID, "roguelike_metal_income",
		0, INLOS_ACCESS)
	Spring.SetUnitRulesParam(unitID, "roguelike_salvage_mult", cumulativeMultipliers.salvage, INLOS_ACCESS)
	Spring.SetUnitRulesParam(unitID, "roguelike_salvage_speed_mult", cumulativeMultipliers.salvageSpeed, INLOS_ACCESS)
	-- Upgrades 写入精确半径，Salvage 只消费；选卡完成后无需等待下一次扫描才更新状态。
	Spring.SetUnitRulesParam(unitID, "roguelike_salvage_radius", cumulativeMultipliers.salvageRadius, INLOS_ACCESS)
	Spring.SetUnitRulesParam(unitID, "roguelike_summon_health_mult", summonMultipliers.health, INLOS_ACCESS)
	Spring.SetUnitRulesParam(unitID, "roguelike_summon_move_mult", summonMultipliers.move, INLOS_ACCESS)
	Spring.SetUnitRulesParam(unitID, "roguelike_summon_damage_mult", summonMultipliers.damage, INLOS_ACCESS)
	Spring.SetUnitRulesParam(unitID, "roguelike_summon_reload_mult", summonMultipliers.reload, INLOS_ACCESS)
	Spring.SetUnitRulesParam(unitID, "roguelike_summon_range_mult", summonMultipliers.range, INLOS_ACCESS)
	-- upgrade_count：Upgrades 写入，Salvage 和 UI 读取；Salvage 据此计算回收范围，
	-- 再将派生结果写入 roguelike_salvage_radius 供 UI 和诊断读取。
	Spring.SetUnitRulesParam(unitID, "roguelike_upgrade_count", upgradeCount, INLOS_ACCESS)
	Spring.SetUnitRulesParam(unitID, "roguelike_level", commanderLevel, INLOS_ACCESS)
	Spring.SetUnitRulesParam(unitID, "roguelike_level_max", MAX_COMMANDER_LEVEL, INLOS_ACCESS)
	Spring.SetUnitRulesParam(unitID, "roguelike_shared_xp", sharedXP, INLOS_ACCESS)
	local roleLevelStartXP = ROLE_LEVEL_TOTAL_XP[commanderLevel] or ROLE_LEVEL_TOTAL_XP[MAX_COMMANDER_LEVEL]
	local roleLevelNextXP = ROLE_LEVEL_TOTAL_XP[commanderLevel + 1]
	Spring.SetUnitRulesParam(unitID, "roguelike_role_xp", math.max(0, sharedXP - roleLevelStartXP), INLOS_ACCESS)
	Spring.SetUnitRulesParam(unitID, "roguelike_role_next_xp",
		roleLevelNextXP and (roleLevelNextXP - roleLevelStartXP) or -1, INLOS_ACCESS)
	Spring.SetUnitRulesParam(unitID, "roguelike_role_total_next_xp", roleLevelNextXP or -1, INLOS_ACCESS)
	Spring.SetUnitRulesParam(unitID, "roguelike_offers_earned", offersEarned, INLOS_ACCESS)
	Spring.SetUnitRulesParam(unitID, "roguelike_refreshes", refreshesRemaining, INLOS_ACCESS)
	Spring.SetUnitRulesParam(unitID, "roguelike_skips", skipsRemaining, INLOS_ACCESS)
	Spring.SetUnitRulesParam(unitID, "roguelike_banishes", banishesRemaining, INLOS_ACCESS)
	for kind, level in pairs(statModuleLevels) do
		Spring.SetUnitRulesParam(unitID, "roguelike_module_" .. kind .. "_level", level, INLOS_ACCESS)
		Spring.SetUnitRulesParam(unitID, "roguelike_module_" .. kind .. "_bonus", statModuleBonuses[kind] or 0, INLOS_ACCESS)
	end
	Spring.SetUnitRulesParam(unitID, "roguelike_focus_guard_threshold", FOCUS_GUARD_FULL_DAMAGE_FRACTION, INLOS_ACCESS)
	Spring.SetUnitRulesParam(unitID, "roguelike_focus_guard_overflow_mult", FOCUS_GUARD_OVERFLOW_MULTIPLIER, INLOS_ACCESS)
	-- 雷电连锁 Gadget 在创建主闪电投射物时读取这两个参数；未购买扩展时
	-- 分别保持 1 和 0，因此不会改变其他单位或原版武器的连锁行为。
	local lightningExtensionLevel = shopLevels.lightning_extension or 0
	Spring.SetUnitRulesParam(unitID, "roguelike_lightning_chain_range_mult",
		1 + lightningExtensionLevel * LIGHTNING_EXTENSION_RANGE_PER_LEVEL, INLOS_ACCESS)
	Spring.SetUnitRulesParam(unitID, "roguelike_lightning_chain_targets_bonus", lightningExtensionLevel, INLOS_ACCESS)
	Spring.SetUnitRulesParam(unitID, "roguelike_next_xp", UPGRADE_THRESHOLDS[offersEarned + 1] or -1, INLOS_ACCESS)
	for itemId, level in pairs(shopLevels) do
		Spring.SetUnitRulesParam(unitID, "roguelike_shop_" .. itemId .. "_level", level, INLOS_ACCESS)
	end
	for itemId in pairs(FACTION_WEAPON_ITEMS) do
		Spring.SetUnitRulesParam(unitID, "roguelike_weapon_equipped_" .. itemId,
			equippedFactionWeapons[itemId] and 1 or 0, INLOS_ACCESS)
	end
end

local HEAL_SOURCES = {
	passive_regen = true, drone_repair = true, combat_regen = true,
	blood_recycle = true, medical_beacon = true, leg_repair_link = true,
	nanorepair = true, medkit = true, wave_clear = true, shop_regen = true,
	lifesteal = true, hit_repair = true,
}

local function healCurrentCommander(source, amount, context)
	context = context or {}
	if not HEAL_SOURCES[source] or not playerUnitID or not spValidUnitID(playerUnitID) then return 0 end
	local unitTeam = Spring.GetUnitTeam(playerUnitID)
	if unitTeam ~= playerTeamID then return 0 end
	local health, maxHealth = Spring.GetUnitHealth(playerUnitID)
	if not health or not maxHealth or health <= 0 or health >= maxHealth then return 0 end
	local sustainedRemaining, damageTriggeredRemaining
	local frame = Spring.GetGameFrame()
	if context.sustained then
		local second = math.floor(frame / Game.gameSpeed)
		if healBudgetSecond ~= second then
			healBudgetSecond, healBudgetUsed = second, 0
		end
		local cap = maxHealth * SUSTAINED_HEAL_CAP_PER_SECOND
		sustainedRemaining = math.max(0, cap - healBudgetUsed)
	end
	if context.damageTriggered then
		local second = math.floor(frame / Game.gameSpeed)
		if damageHealBudgetSecond ~= second then
			damageHealBudgetSecond, damageHealBudgetUsed = second, 0
		end
		local cap = maxHealth * DAMAGE_TRIGGER_HEAL_CAP_PER_SECOND
		damageTriggeredRemaining = math.max(0, cap - damageHealBudgetUsed)
	end
	local wanted = damageHealingRules.ClampHealing(amount, maxHealth - health,
		sustainedRemaining, damageTriggeredRemaining)
	if wanted <= 0 then return 0 end
	local energyPerHP = math.max(0, tonumber(context.energyPerHP) or 0)
	if energyPerHP > 0 then
		local energy = select(1, Spring.GetTeamResources(playerTeamID, "energy")) or 0
		wanted = math.min(wanted, energy / energyPerHP)
		if wanted <= 0 or not Spring.UseTeamResource(playerTeamID, "energy", wanted * energyPerHP) then return 0 end
	end
	local actual = math.min(wanted, maxHealth - health)
	if actual <= 0 then return 0 end
	Spring.SetUnitHealth(playerUnitID, { health = health + actual })
	if context.sustained then healBudgetUsed = healBudgetUsed + actual end
	if context.damageTriggered then damageHealBudgetUsed = damageHealBudgetUsed + actual end
	healingTotals[source] = (healingTotals[source] or 0) + actual
	Spring.SetUnitRulesParam(playerUnitID, "roguelike_heal_total_" .. source, healingTotals[source], INLOS_ACCESS)
	Spring.SetUnitRulesParam(playerUnitID, "roguelike_last_heal_amount", actual, INLOS_ACCESS)
	Spring.SetUnitRulesParam(playerUnitID, "roguelike_last_heal_source", source, INLOS_ACCESS)
	Spring.SetUnitRulesParam(playerUnitID, "roguelike_damage_heal_used", damageHealBudgetUsed, INLOS_ACCESS)
	return actual
end

local function healCommanderForTeam(teamID, source, amount, context)
	if not teamID then return 0 end
	if COOP_ENABLED then return withTeam(teamID, healCurrentCommander, source, amount, context) or 0 end
	if teamID ~= playerTeamID then return 0 end
	return healCurrentCommander(source, amount, context)
end

local function registerDamageHealContext(targetID, ownerID, damageKind, attackID)
	if not targetID or not ownerID or not damageKind then return false end
	local teamID = Spring.GetUnitTeam(ownerID)
	local state = teamID and statesByTeam[teamID]
	local multipliers = state and state.cumulativeMultipliers
	if not multipliers or (multipliers.lifeDrain <= 0 and multipliers.hitRepair <= 0
		and multipliers.areaLeech <= 0 and multipliers.dotLeech <= 0) then return false end
	explicitDamageHealContexts[targetID] = {
		ownerID = ownerID, teamID = teamID, damageKind = damageKind,
		attackID = attackID, frame = Spring.GetGameFrame(),
	}
	return true
end

local function setNativeShield(unitID, power)
	if not unitID or not shieldWeaponNum then return end
	local enabled = cumulativeMultipliers.shield > 0
	Spring.SetUnitShieldState(unitID, shieldWeaponNum, enabled, math.max(0, power or 0))
end

local function syncNativeShield(unitID)
	if not unitID or not shieldWeaponNum or cumulativeMultipliers.shield <= 0 then
		shieldCurrent = 0
		return
	end
	local _, nativePower = Spring.GetUnitShieldState(unitID, shieldWeaponNum)
	if nativePower ~= nil then
		if nativePower + 0.01 < shieldCurrent then
			lastShieldHitFrame = Spring.GetGameFrame()
		end
		shieldCurrent = math.min(cumulativeMultipliers.shield, math.max(0, nativePower))
	end
	Spring.SetUnitRulesParam(unitID, "roguelike_shield_current", shieldCurrent, INLOS_ACCESS)
end

-- healMaxIncrease：生命类卡牌把新增的最大生命值同步加到当前生命。
-- 否则残血时抽到“+20% 最大生命”只按比例保留血量，玩家会感觉没有回血。
local function applyCommanderStats(unitID, fullHeal, healMaxIncrease)
	if not unitID or not spValidUnitID(unitID) then return false end
	local unitDef = UnitDefs[Spring.GetUnitDefID(unitID)]
	if not unitDef then return false end

	local health, oldMaxHealth = Spring.GetUnitHealth(unitID)
	local healthRatio = health and oldMaxHealth and oldMaxHealth > 0 and health / oldMaxHealth or 1
	-- Upgrade cards multiply health; shop levels add a fixed 10% of the stable
	-- base maximum. This prevents the shop bonus from compounding into spikes.
	local stableBaseHealth = baseCommanderMaxHealth or oldMaxHealth or unitDef.health
	local roleHealthBonus = math.max(0, commanderLevel - 1) * ROLE_HP_PER_LEVEL
	local newMaxHealth = stableBaseHealth * (cumulativeMultipliers.health + cumulativeMultipliers.shopHealthBonus
		+ roleHealthBonus + (statModuleBonuses.health or 0))
	local maxHealthIncrease = math.max(0, newMaxHealth - (oldMaxHealth or newMaxHealth))

	-- 每次选卡只增加电力产出；金属只从残骸吸收获取。
	-- ume/umm 写绝对值，避免重载 Gadget 或每秒校正时重复叠加。
	Spring.SetUnitResourcing(unitID, "ume", baseCommanderEnergyMake + upgradeCount * ENERGY_INCOME_PER_UPGRADE)
	Spring.SetUnitResourcing(unitID, "umm", 0)
	-- unit_attributes treats selfMoveSpeedChange as the standard per-unit speed
	-- modifier. Keeping upgradesSpeedMult at 1 avoids a second, hidden modifier
	-- path and makes the movement card immediately observable in engine data.
	Spring.SetUnitRulesParam(unitID, "selfMoveSpeedChange", cumulativeMultipliers.move * effectiveStatMultiplier("move"), INLOS_ACCESS)
	Spring.SetUnitRulesParam(unitID, "upgradesSpeedMult", 1, INLOS_ACCESS)
	Spring.SetUnitRulesParam(unitID, "selfReloadSpeedChange", cumulativeMultipliers.reload * effectiveStatMultiplier("reload"), INLOS_ACCESS)
	Spring.SetUnitRulesParam(unitID, "selfIncomeChange", 1, INLOS_ACCESS)
	if GG.UpdateUnitAttributes then
		GG.UpdateUnitAttributes(unitID)
	end

	Spring.SetUnitMaxHealth(unitID, newMaxHealth)
	local newHealth
	if fullHeal then
		newHealth = newMaxHealth
	elseif healMaxIncrease then
		newHealth = math.min(newMaxHealth, (health or newMaxHealth) + maxHealthIncrease)
	else
		newHealth = math.min(newMaxHealth, newMaxHealth * healthRatio)
	end
	Spring.SetUnitHealth(unitID, { health = newHealth })
	applyWeaponRange(unitID)
	local baseLos = unitDef.losRadius or 500
	local baseAirLos = unitDef.airLosRadius or baseLos
	Spring.SetUnitSensorRadius(unitID, "los", math.floor(baseLos * cumulativeMultipliers.sight))
	Spring.SetUnitSensorRadius(unitID, "airLos", math.floor(baseAirLos * cumulativeMultipliers.sight))
	shieldCurrent = math.min(shieldCurrent, cumulativeMultipliers.shield)
	setNativeShield(unitID, shieldCurrent)
	writeProgressRules(unitID)
	return true
end

local function setPlayerCommander(unitID, unitTeam)
	local commanderChanged = playerUnitID ~= unitID
	playerUnitID = unitID
	playerTeamID = unitTeam
	if statesByTeam[unitTeam] then statesByTeam[unitTeam].playerUnitID = unitID end
	if commanderChanged then
		local _, currentMaxHealth = Spring.GetUnitHealth(unitID)
		local unitDef = UnitDefs[Spring.GetUnitDefID(unitID)]
		baseCommanderMaxHealth = (unitDef and unitDef.health) or currentMaxHealth or 10000
		baseCommanderEnergyMake = (unitDef and unitDef.energyMake) or 0
		cacheCommanderWeaponSlots(unitID)
		lastHealthDamageFrame = Spring.GetGameFrame()
		focusGuardWindowStartFrame = lastHealthDamageFrame
		focusGuardRawDamage = 0
		if showNextPendingChoice then showNextPendingChoice() end
	end
	if commanderChanged and cumulativeMultipliers.shield > 0 then
		shieldCurrent = cumulativeMultipliers.shield
	end
	if commanderChanged then
		setNativeShield(unitID, shieldCurrent)
	end
	applyCommanderStats(unitID, false)
	GG.Roguelike = GG.Roguelike or {}
	if COOP_ENABLED then
		GG.Roguelike.teams = GG.Roguelike.teams or {}
		GG.Roguelike.teams[unitTeam] = GG.Roguelike.teams[unitTeam] or {}
		GG.Roguelike.teams[unitTeam].commanderUnitID = unitID
	else
		GG.Roguelike.playerUnitID = unitID
		GG.Roguelike.playerTeamID = unitTeam
	end
	if commanderChanged then
		local metalMake = Spring.GetUnitResources(unitID)
		Spring.Echo("Roguelike: commander registered unit=" .. unitID .. ", metalMake=" .. tostring(metalMake))
	end
end

local function applyCardUpgrade(upgrade)
	if not playerUnitID or not spValidUnitID(playerUnitID) then return false end
	local isModule = upgrade.module ~= nil
	if isModule then
		statModuleLevels[upgrade.type] = (statModuleLevels[upgrade.type] or 0) + 1
		statModuleBonuses[upgrade.type] = math.min(STAT_MODULE_BONUS_CAPS[upgrade.type] or math.huge,
			(statModuleBonuses[upgrade.type] or 0) + upgrade.value)
	elseif upgrade.type ~= "training" then
		acquiredUpgradeIds[upgrade.id] = true
	end

	if isModule then
		-- Additive bonuses are kept separate from shop and role-level multipliers.
	elseif upgrade.type == "training" then
		local stat = upgrade.trainingStat or "health"
		trainingLevels[stat] = (trainingLevels[stat] or 0) + 1
		statModuleBonuses[stat] = math.min(STAT_MODULE_BONUS_CAPS[stat] or 0.60,
			(statModuleBonuses[stat] or 0) + upgrade.value)
	elseif upgrade.type == "shield" then
		cumulativeMultipliers.shield = cumulativeMultipliers.shield + upgrade.value
		shieldCurrent = math.min(cumulativeMultipliers.shield, shieldCurrent + upgrade.value)
		setNativeShield(playerUnitID, shieldCurrent)
	elseif upgrade.type == "combatRegen" then
		cumulativeMultipliers.combatRegen = math.min(0.004,
			cumulativeMultipliers.combatRegen + upgrade.value)
	elseif upgrade.type == "bloodRecycle" then
		cumulativeMultipliers.bloodRecycle = upgrade.value
	elseif upgrade.type == "lifeDrain" then
		cumulativeMultipliers.lifeDrain = upgrade.value
	elseif upgrade.type == "hitRepair" then
		cumulativeMultipliers.hitRepair = upgrade.value
	elseif upgrade.type == "areaLeech" then
		cumulativeMultipliers.areaLeech = upgrade.value
	elseif upgrade.type == "dotLeech" then
		cumulativeMultipliers.dotLeech = upgrade.value
	elseif upgrade.type == "blastLining" then
		cumulativeMultipliers.blastLining = math.min(BLAST_LINING_LIMIT,
			math.max(cumulativeMultipliers.blastLining, upgrade.value))
	elseif upgrade.type == "armor" then
		cumulativeMultipliers.armor = math.min(MAX_ARMOR_DAMAGE_REDUCTION,
			cumulativeMultipliers.armor + upgrade.value)
	elseif upgrade.type == "drone" then
		cumulativeMultipliers.drone = cumulativeMultipliers.drone + upgrade.value
	elseif upgrade.type ~= "training" then
		cumulativeMultipliers[upgrade.type] = cumulativeMultipliers[upgrade.type] * upgrade.value
	end

	upgradeCount = upgradeCount + 1
	applyCommanderStats(playerUnitID, false, upgrade.type == "health" or upgrade.type == "training")
	applySummonGrowth()

	if upgrade.type == "drone" and GG.Roguelike and GG.Roguelike.AddDroneLevel then
		-- 升级系统会在下方统一发送本次选卡通知，避免无人机 Gadget 再弹一次。
		GG.Roguelike.AddDroneLevel(playerTeamID, true)
	end
	local appliedDescription = string.format("%s；角色 Lv.%d/%d（最大生命 +%.1f%%，全局伤害 +%.1f%%）；电力 +50",
		upgrade.desc or "", commanderLevel, MAX_COMMANDER_LEVEL,
		(commanderLevel - 1) * ROLE_HP_PER_LEVEL * 100,
		(commanderLevel - 1) * ROLE_DAMAGE_PER_LEVEL * 100)
	Spring.Echo("Roguelike Upgrade Applied: " .. upgrade.name .. " (" .. appliedDescription .. ")")
	personalEvent("RoguelikeUpgradeApplied", upgrade.name, appliedDescription)
	sendAcquiredOptions()
	return true
end

-- 第二波结算属于局内里程碑，不算玩家的一次选卡，因此只解锁无人机，
-- 不叠加“每次升级”的全局基础成长，也不推进卡牌 tier。
local function unlockFirstDroneMilestone()
	if acquiredUpgradeIds.drone1 then return false end
	if not GG.Roguelike or not GG.Roguelike.AddDroneLevel then
		Spring.Echo("Roguelike: drone milestone delayed because AddDroneLevel is unavailable")
		return false
	end

	acquiredUpgradeIds.drone1 = true
	cumulativeMultipliers.drone = cumulativeMultipliers.drone + 1
	applySummonGrowth()
	GG.Roguelike.AddDroneLevel(playerTeamID, true)
	Spring.Echo("Roguelike: wave 2 time boundary; first drone level unlocked for wave 3")
	personalEvent("RoguelikeUpgradeApplied", "轨道无人机 I", "第二波时间结束：进入第三波时自动解锁 2 架无人机")
	sendAcquiredOptions()
	return true
end

local function offerUpgradeChoices()
	local choices = not activeChoiceId and pickRandomChoices(CHOICES_PER_OFFER) or nil
	choiceIdCounter = choiceIdCounter + 1
	pendingChoices[choiceIdCounter] = {
		choices = choices,
		teamID = playerTeamID,
	}
	if not activeChoiceId then
		activeChoiceId = choiceIdCounter
		if #choices == 0 then choices = pickRandomChoices(CHOICES_PER_OFFER) end
		pendingChoices[choiceIdCounter].choices = choices
		if playerUnitID and spValidUnitID(playerUnitID) then
			personalEvent("RoguelikeOfferChoices", choiceIdCounter, serializeChoices(choices), refreshesRemaining, skipsRemaining, banishesRemaining)
		end
	end
	return true
end

showNextPendingChoice = function()
	if not playerUnitID or not spValidUnitID(playerUnitID) then return end
	if activeChoiceId and pendingChoices[activeChoiceId] then
		if not pendingChoices[activeChoiceId].choices then
			pendingChoices[activeChoiceId].choices = pickRandomChoices(CHOICES_PER_OFFER)
		end
		personalEvent("RoguelikeOfferChoices", activeChoiceId,
			serializeChoices(pendingChoices[activeChoiceId].choices), refreshesRemaining, skipsRemaining, banishesRemaining)
		return
	end
	activeChoiceId = nil
	local ids = {}
	for choiceID in pairs(pendingChoices) do ids[#ids + 1] = choiceID end
	table.sort(ids)
	if ids[1] then
		activeChoiceId = ids[1]
		pendingChoices[activeChoiceId].choices = pendingChoices[activeChoiceId].choices
			or pickRandomChoices(CHOICES_PER_OFFER)
		personalEvent("RoguelikeOfferChoices", activeChoiceId,
			serializeChoices(pendingChoices[activeChoiceId].choices), refreshesRemaining, skipsRemaining, banishesRemaining)
	end
end

local function processKillCount()
	local targetRoleLevel = roleLevelForXP(sharedXP)
	if targetRoleLevel > commanderLevel then
		local previousLevel = commanderLevel
		commanderLevel = targetRoleLevel
		if playerUnitID and spValidUnitID(playerUnitID) then
			-- Apply cumulative role growth once; add only the new max-HP delta.
			applyCommanderStats(playerUnitID, false, true)
		end
		Spring.Echo(string.format("Roguelike role level: Team %s Lv.%d -> Lv.%d (shared XP %d)",
			tostring(playerTeamID), previousLevel, commanderLevel, sharedXP))
	end

	local xpOffers = 0
	for _, threshold in ipairs(UPGRADE_THRESHOLDS) do
		if sharedXP >= threshold then xpOffers = xpOffers + 1 else break end
	end
	local targetOffers = math.max(waveOfferTarget, math.min(xpOffers, waveOfferTarget + 1))
	while offersEarned < targetOffers do
		offersEarned = offersEarned + 1
		offerUpgradeChoices()
	end
	if playerUnitID and spValidUnitID(playerUnitID) then writeProgressRules(playerUnitID) end
end

local function nextShopCost(item, level)
	if item.type == "factionWeapon" then
		local multiplier = ({ 1, 0.55, 0.85 })[level + 1]
		return math.floor(item.baseCost * (multiplier or 0) + 0.5)
	end
	return item.baseCost + item.costStep * level
end

local function getCommanderFaction(unitID)
	local unitDef = UnitDefs[Spring.GetUnitDefID(unitID)]
	local name = unitDef and string.lower(unitDef.name or "") or ""
	if name:sub(1, 3) == "arm" then return "armada" end
	if name:sub(1, 3) == "cor" then return "cortex" end
	if name:sub(1, 3) == "leg" then return "legion" end
	return nil
end

local function countEquippedFactionWeapons()
	local count = 0
	for _, equipped in pairs(equippedFactionWeapons) do
		if equipped then count = count + 1 end
	end
	return count
end

local function sendShopResult(success, item, level, cost, reason)
	personalEvent(
		"RoguelikeShopResult",
		success and 1 or 0,
		item and item.id or "",
		item and item.name or "",
		level or 0,
		cost or 0,
		reason or ""
	)
end

local function sendSkillResult(success, skillID, cooldownFrame, reason)
	personalEvent("RoguelikeSkillResult", success and 1 or 0, skillID,
		cooldownFrame or 0, reason or "")
end

local function findRepairLinkTargets(casterTeamID, casterUnitID)
	local x, _, z = Spring.GetUnitPosition(casterUnitID)
	if not x then return nil end
	local targets = { casterTeamID }
	local mostMissing, selectedTeam = 0, nil
	for _, teamID in ipairs(GG.Roguelike and GG.Roguelike.teamIDs or {}) do
		if teamID ~= casterTeamID then
			local state = statesByTeam[teamID]
			local unitID = state and state.playerUnitID
			if unitID and spValidUnitID(unitID) then
				local tx, _, tz = Spring.GetUnitPosition(unitID)
				local health, maxHealth = Spring.GetUnitHealth(unitID)
				if tx and health and maxHealth and health > 0 and maxHealth > health
					and (tx - x) * (tx - x) + (tz - z) * (tz - z) <= 350 * 350 then
					local missing = (maxHealth - health) / maxHealth
					if missing > mostMissing then mostMissing, selectedTeam = missing, teamID end
				end
			end
		end
	end
	if selectedTeam then targets[#targets + 1] = selectedTeam end
	local hasMissingHealth = false
	for _, teamID in ipairs(targets) do
		local state = statesByTeam[teamID]
		local unitID = state and state.playerUnitID
		if unitID and spValidUnitID(unitID) then
			local health, maxHealth = Spring.GetUnitHealth(unitID)
			if health and maxHealth and health < maxHealth then hasMissingHealth = true end
		end
	end
	return hasMissingHealth and targets or nil
end

local function canBenefitFromBeacon(casterTeamID, casterUnitID)
	local x, _, z = Spring.GetUnitPosition(casterUnitID)
	if not x then return false end
	local allyTeamID = select(6, Spring.GetTeamInfo(casterTeamID, false))
	for _, teamID in ipairs(GG.Roguelike and GG.Roguelike.teamIDs or { casterTeamID }) do
		if select(6, Spring.GetTeamInfo(teamID, false)) == allyTeamID then
			local state = statesByTeam[teamID]
			local unitID = state and state.playerUnitID
			if unitID and spValidUnitID(unitID) then
				local health, maxHealth = Spring.GetUnitHealth(unitID)
				local tx, _, tz = Spring.GetUnitPosition(unitID)
				if health and maxHealth and health > 0 and health < maxHealth and tx
					and (tx - x) * (tx - x) + (tz - z) * (tz - z) <= BEACON_RADIUS * BEACON_RADIUS then
					return true
				end
			end
		end
	end
	return false
end

local function useSurvivalSkill(skillID, playerID)
	local frame = Spring.GetGameFrame()
	local function fail(reason)
		sendSkillResult(false, skillID, activeSkillCooldownEndFrame[skillID] or medicalBeaconCooldownEndFrame, reason)
		Spring.Echo("Roguelike skill failed team=" .. tostring(playerTeamID) .. " id=" .. tostring(skillID) .. " reason=" .. reason)
	end
	if getPlayerTeam(playerID) ~= playerTeamID or not playerUnitID or not spValidUnitID(playerUnitID) then
		fail("invalid_player")
		return
	end
	local faction = getCommanderFaction(playerUnitID)
	local factionSkill = faction == "armada" and "photon_guard"
		or faction == "cortex" and "bastion"
		or faction == "legion" and "repair_link"
		or nil
	local cooldownEnd = skillID == "medical_beacon" and medicalBeaconCooldownEndFrame
		or activeSkillCooldownEndFrame[skillID] or 0
	if cooldownEnd > frame then fail("cooldown"); return end
	local health, maxHealth = Spring.GetUnitHealth(playerUnitID)
	if not health or not maxHealth or health <= 0 then fail("commander_unavailable"); return end

	if skillID == "nanorepair" then
		if health >= maxHealth then fail("full_health"); return end
		if not Spring.UseTeamResource(playerTeamID, "energy", NANO_REPAIR_COST) then fail("not_enough_energy"); return end
		nanoRepairEndFrame = frame + NANO_REPAIR_DURATION * Game.gameSpeed
		nanoRepairNextTickFrame = frame + NANO_REPAIR_TICK_FRAMES
		nanoRepairTicksRemaining = NANO_REPAIR_TICKS
		activeSkillCooldownEndFrame[skillID] = frame + NANO_REPAIR_COOLDOWN * Game.gameSpeed
	elseif skillID == "thruster" then
		if not GG.UnitAttributes or not GG.UnitAttributes.SetUnitModifier then fail("movement_api_unavailable"); return end
		local source = "roguelike_thruster:" .. playerTeamID
		GG.UnitAttributes.SetUnitModifier(playerUnitID, "speed", THRUSTER_MULTIPLIER, source)
		thrusterEndFrame = frame + THRUSTER_DURATION * Game.gameSpeed
		activeSkillCooldownEndFrame[skillID] = frame + THRUSTER_COOLDOWN * Game.gameSpeed
	elseif skillID == "photon_guard" and faction == "armada" then
		barrierPoints = 1600
		barrierEndFrame = frame + 6 * Game.gameSpeed
		activeSkillCooldownEndFrame[skillID] = frame + 48 * Game.gameSpeed
	elseif skillID == "bastion" and faction == "cortex" then
		bastionEndFrame = frame + 6 * Game.gameSpeed
		activeSkillCooldownEndFrame[skillID] = frame + 48 * Game.gameSpeed
	elseif skillID == "repair_link" and faction == "legion" then
		if activeRepairLink and activeRepairLink.endFrame > frame then fail("same_skill_active"); return end
		local targets = findRepairLinkTargets(playerTeamID, playerUnitID)
		if not targets then fail("no_target"); return end
		repairLinkTargets = targets
		repairLinkEndFrame = frame + 7 * Game.gameSpeed
		activeRepairLink = { casterTeamID = playerTeamID, endFrame = repairLinkEndFrame, targets = targets }
		activeSkillCooldownEndFrame[skillID] = frame + 55 * Game.gameSpeed
	elseif skillID == "medical_beacon" then
		if (shopLevels.rl_coop_medical_beacon or 0) <= 0 then fail("not_owned"); return end
		if activeMedicalBeacon and activeMedicalBeacon.endFrame > frame then fail("same_skill_active"); return end
		if not canBenefitFromBeacon(playerTeamID, playerUnitID) then fail("no_target"); return end
		if not Spring.UseTeamResource(playerTeamID, "energy", BEACON_ENERGY_COST) then fail("not_enough_energy"); return end
		medicalBeaconCooldownEndFrame = frame + BEACON_COOLDOWN * Game.gameSpeed
		activeMedicalBeacon = {
			casterTeamID = playerTeamID,
			allyTeamID = select(6, Spring.GetTeamInfo(playerTeamID, false)),
			endFrame = frame + BEACON_DURATION,
		}
	else
		fail("wrong_faction")
		return
	end
	writeProgressRules(playerUnitID)
	local cdEnd = skillID == "medical_beacon" and medicalBeaconCooldownEndFrame or activeSkillCooldownEndFrame[skillID]
	sendSkillResult(true, skillID, cdEnd, "")
	Spring.Echo("Roguelike skill used team=" .. playerTeamID .. " id=" .. skillID .. " cooldownEnd=" .. cdEnd)
end

local function sortedNumericKeys(source)
	local keys = {}
	for key in pairs(source) do keys[#keys + 1] = key end
	table.sort(keys)
	return keys
end

local function roguelikeTeams()
	if not COOP_ENABLED then return playerTeamID and { playerTeamID } or {} end
	local teams = GG.Roguelike and GG.Roguelike.teamIDs
	if teams and #teams > 0 then return teams end
	return playerTeamID and { playerTeamID } or {}
end

local function spawnMedkit(x, y, z)
	if not medkitFeatureDefID then
		Spring.Echo("Roguelike medkit spawn failed: featuredef roguelike_medkit is missing")
		return false
	end
	local count = 0
	for featureID in pairs(medkitsByFeature) do
		if Spring.ValidFeatureID(featureID) then count = count + 1 else medkitsByFeature[featureID] = nil end
	end
	if count >= MEDKIT_MAX_ON_GROUND then
		GG.Roguelike.medkitSpawnSkipped = (GG.Roguelike.medkitSpawnSkipped or 0) + 1
		return false
	end
	if not x or not z then
		for _, teamID in ipairs(roguelikeTeams()) do
			local state = statesByTeam[teamID]
			local unitID = state and state.playerUnitID
			if unitID and spValidUnitID(unitID) then
				x, y, z = Spring.GetUnitPosition(unitID)
				if x then
					local angle = math.random() * 2 * math.pi
					x, z = x + math.cos(angle) * 180, z + math.sin(angle) * 180
					y = Spring.GetGroundHeight(x, z)
					break
				end
			end
		end
	end
	if not x or not z then return false end
	y = y or Spring.GetGroundHeight(x, z)
	local featureID = Spring.CreateFeature(medkitFeatureDefID, x, y, z, 0, Spring.GetGaiaTeamID())
	if not featureID then return false end
	local expires = Spring.GetGameFrame() + MEDKIT_LIFETIME
	medkitsByFeature[featureID] = expires
	Spring.SetFeatureRulesParam(featureID, "roguelike_medkit", 1, { inlos = true })
	Spring.SetFeatureRulesParam(featureID, "roguelike_medkit_expiry", expires, { inlos = true })
	GG.Roguelike.medkitSpawnCount = (GG.Roguelike.medkitSpawnCount or 0) + 1
	Spring.Echo("Roguelike medkit spawned id=" .. featureID .. " expires=" .. expires)
	return true
end

local function processEffectiveKill(kills, x, y, z)
	local teamCount = math.max(1, #roguelikeTeams())
	local normalizedXP = math.floor((kills or 0) / (TEAM_XP_NORMALIZATION[teamCount] or 2.6))
	GG.Roguelike = GG.Roguelike or {}
	GG.Roguelike.sharedXP = normalizedXP
	if COOP_ENABLED then
		for _, teamID in ipairs(roguelikeTeams()) do
			local state = statesByTeam[teamID]
			if state then
				state.sharedXP = normalizedXP
				withTeam(teamID, processKillCount)
			end
		end
	else
		sharedXP = normalizedXP
		processKillCount()
	end
	local frame = Spring.GetGameFrame()
	for _, teamID in ipairs(roguelikeTeams()) do
		local state = statesByTeam[teamID]
		if state and (state.cumulativeMultipliers.bloodRecycle or 0) > 0 then
			local stats = state.bloodRecycleDiagnostics or {
				kills = 0, noPosition = 0, outOfRange = 0, cooldown = 0,
				fullHealth = 0, healedEvents = 0, healCap = 0, healedAmount = 0,
				lastLogFrame = -10 * Game.gameSpeed,
			}
			state.bloodRecycleDiagnostics = stats
			stats.kills = stats.kills + 1
			withTeam(teamID, function()
				local result = "no_position"
				local distance
				local unitID = playerUnitID
				if not unitID or not spValidUnitID(unitID) then
					result = "no_commander"
				elseif not x or not z then
					stats.noPosition = stats.noPosition + 1
				else
					local cx, _, cz = Spring.GetUnitPosition(unitID)
					if cx then
						distance = math.sqrt((cx - x) * (cx - x) + (cz - z) * (cz - z))
					end
					if not distance or distance > 550 then
						result = "out_of_range"
						stats.outOfRange = stats.outOfRange + 1
					elseif frame - lastBloodRecycleFrame < 2 * Game.gameSpeed then
						result = "cooldown"
						stats.cooldown = stats.cooldown + 1
					else
						local health, maxHealth = Spring.GetUnitHealth(unitID)
						if not health or not maxHealth or health <= 0 or health >= maxHealth then
							result = "full_health"
							stats.fullHealth = stats.fullHealth + 1
						else
							local requested = maxHealth * cumulativeMultipliers.bloodRecycle
							local restored = healCurrentCommander("blood_recycle", requested, { sustained = true })
							if restored > 0 then
								lastBloodRecycleFrame = frame
								stats.healedEvents = stats.healedEvents + 1
								stats.healedAmount = stats.healedAmount + restored
								result = string.format("healed %.1f/%.1f", restored, requested)
							else
								result = "heal_cap"
								stats.healCap = stats.healCap + 1
							end
						end
					end
				end
				if unitID and spValidUnitID(unitID) then
					Spring.SetUnitRulesParam(unitID, "roguelike_blood_recycle_seen", stats.kills, INLOS_ACCESS)
					Spring.SetUnitRulesParam(unitID, "roguelike_blood_recycle_healed_events", stats.healedEvents, INLOS_ACCESS)
					Spring.SetUnitRulesParam(unitID, "roguelike_blood_recycle_healed_amount", stats.healedAmount, INLOS_ACCESS)
					Spring.SetUnitRulesParam(unitID, "roguelike_blood_recycle_out_of_range", stats.outOfRange, INLOS_ACCESS)
					Spring.SetUnitRulesParam(unitID, "roguelike_blood_recycle_cooldown_blocks", stats.cooldown, INLOS_ACCESS)
					Spring.SetUnitRulesParam(unitID, "roguelike_blood_recycle_full_health", stats.fullHealth, INLOS_ACCESS)
					Spring.SetUnitRulesParam(unitID, "roguelike_blood_recycle_cap_blocks", stats.healCap, INLOS_ACCESS)
					Spring.SetUnitRulesParam(unitID, "roguelike_blood_recycle_missing_position", stats.noPosition, INLOS_ACCESS)
				end
				if frame - stats.lastLogFrame >= 10 * Game.gameSpeed then
					stats.lastLogFrame = frame
					Spring.Echo(string.format(
						"Roguelike BloodRecycle: team=%d result=%s distance=%s kills=%d healedEvents=%d healedHP=%.1f outOfRange=%d cooldown=%d fullHP=%d healCap=%d noPosition=%d",
						teamID, result, distance and string.format("%.1f", distance) or "n/a",
						stats.kills, stats.healedEvents, stats.healedAmount, stats.outOfRange,
						stats.cooldown, stats.fullHealth, stats.healCap, stats.noPosition))
				end
			end)
		end
	end
	medkitKillProgress = medkitKillProgress + 1
	local teams = roguelikeTeams()
	local threshold = 14 + 5 * math.max(0, #teams - 1)
	if medkitKillProgress >= threshold then
		medkitKillProgress = medkitKillProgress - threshold
		spawnMedkit(x, y, z)
	end
	GG.Roguelike.medkitKillProgress = medkitKillProgress
end

local function updateOwnedSurvivalEffects(frame)
	if not playerUnitID or not spValidUnitID(playerUnitID) then return end
	if thrusterEndFrame > 0 and frame >= thrusterEndFrame then
		if GG.UnitAttributes and GG.UnitAttributes.SetUnitModifier then
			GG.UnitAttributes.SetUnitModifier(playerUnitID, "speed", nil, "roguelike_thruster:" .. playerTeamID)
		end
		thrusterEndFrame = 0
	end
	if barrierEndFrame > 0 and frame >= barrierEndFrame then
		barrierPoints, barrierEndFrame = 0, 0
		Spring.SetUnitRulesParam(playerUnitID, "roguelike_barrier_current", 0, INLOS_ACCESS)
	end
	if bastionEndFrame > 0 and frame >= bastionEndFrame then
		bastionEndFrame = 0
		Spring.SetUnitRulesParam(playerUnitID, "roguelike_bastion_expiry", 0, INLOS_ACCESS)
	end
	if repairLinkEndFrame > 0 and frame >= repairLinkEndFrame then
		repairLinkEndFrame, repairLinkTargets = 0, {}
		Spring.SetUnitRulesParam(playerUnitID, "roguelike_repair_link_expiry", 0, INLOS_ACCESS)
	end
	if frame >= nanoRepairNextTickFrame and nanoRepairTicksRemaining > 0 then
		local _, maxHealth = Spring.GetUnitHealth(playerUnitID)
		if maxHealth then
			healCurrentCommander("nanorepair", maxHealth * 0.15 / NANO_REPAIR_TICKS)
		end
		nanoRepairTicksRemaining = nanoRepairTicksRemaining - 1
		nanoRepairNextTickFrame = frame + NANO_REPAIR_TICK_FRAMES
		if nanoRepairTicksRemaining <= 0 then
			nanoRepairEndFrame = 0
			Spring.SetUnitRulesParam(playerUnitID, "roguelike_skill_active_nanorepair", 0, INLOS_ACCESS)
		end
	end
	if nanoRepairEndFrame > 0 and frame >= nanoRepairEndFrame and nanoRepairTicksRemaining <= 0 then
		nanoRepairEndFrame = 0
		Spring.SetUnitRulesParam(playerUnitID, "roguelike_skill_active_nanorepair", 0, INLOS_ACCESS)
	end
	if frame % Game.gameSpeed == 0 and GG.Roguelike and GG.Roguelike.phase == 1
		and effectiveCombatRegen() > 0 then
		local _, maxHealth = Spring.GetUnitHealth(playerUnitID)
		if maxHealth then
			healCurrentCommander("combat_regen", maxHealth * effectiveCombatRegen(),
				{ sustained = true })
		end
	end
end

local function updateRepairLink(frame)
	if not activeRepairLink then return end
	if frame >= activeRepairLink.endFrame then activeRepairLink = nil; return end
	local casterTeamID = activeRepairLink.casterTeamID
	local casterState = statesByTeam[casterTeamID]
	local casterID = casterState and casterState.playerUnitID
	if not casterID or not spValidUnitID(casterID) then activeRepairLink = nil; return end
	if frame % NANO_REPAIR_TICK_FRAMES ~= 0 then return end
	local cx, _, cz = Spring.GetUnitPosition(casterID)
	if not cx then return end
	for _, targetTeamID in ipairs(activeRepairLink.targets or {}) do
		local state = statesByTeam[targetTeamID]
		local targetID = state and state.playerUnitID
		if targetID and spValidUnitID(targetID) then
			local tx, _, tz = Spring.GetUnitPosition(targetID)
			local _, maxHealth = Spring.GetUnitHealth(targetID)
			if tx and maxHealth and (tx - cx) * (tx - cx) + (tz - cz) * (tz - cz) <= 350 * 350 then
				healCommanderForTeam(targetTeamID, "leg_repair_link",
					maxHealth * 0.007 * NANO_REPAIR_TICK_FRAMES / Game.gameSpeed,
					{ sustained = true })
			end
		end
	end
end

local function updateMedicalBeacon(frame)
	if not activeMedicalBeacon then return end
	if frame >= activeMedicalBeacon.endFrame then activeMedicalBeacon = nil; return end
	if frame % NANO_REPAIR_TICK_FRAMES ~= 0 then return end
	local casterState = statesByTeam[activeMedicalBeacon.casterTeamID]
	local casterID = casterState and casterState.playerUnitID
	if not casterID or not spValidUnitID(casterID) then activeMedicalBeacon = nil; return end
	local x, _, z = Spring.GetUnitPosition(casterID)
	if not x then return end
	for _, teamID in ipairs(roguelikeTeams()) do
		if select(6, Spring.GetTeamInfo(teamID, false)) == activeMedicalBeacon.allyTeamID then
			local state = statesByTeam[teamID]
			local unitID = state and state.playerUnitID
			if unitID and spValidUnitID(unitID) then
				local health, maxHealth = Spring.GetUnitHealth(unitID)
				local tx, _, tz = Spring.GetUnitPosition(unitID)
				if health and maxHealth and health > 0 and tx
					and (tx - x) * (tx - x) + (tz - z) * (tz - z) <= BEACON_RADIUS * BEACON_RADIUS then
					healCommanderForTeam(teamID, "medical_beacon",
						maxHealth * BEACON_HEAL_FRACTION * NANO_REPAIR_TICK_FRAMES / BEACON_DURATION,
						{ sustained = true })
				end
			end
		end
	end
end

local function updateMedkitPickups(frame)
	for _, featureID in ipairs(sortedNumericKeys(medkitsByFeature)) do
		local expires = medkitsByFeature[featureID]
		if not Spring.ValidFeatureID(featureID) then
			medkitsByFeature[featureID] = nil
		elseif frame >= expires then
			medkitsByFeature[featureID] = nil
			Spring.DestroyFeature(featureID)
			GG.Roguelike.medkitExpireCount = (GG.Roguelike.medkitExpireCount or 0) + 1
		else
			local fx, _, fz = Spring.GetFeaturePosition(featureID)
			local bestTeam, bestDistance
			if fx then
				for _, teamID in ipairs(roguelikeTeams()) do
					local state = statesByTeam[teamID]
					local unitID = state and state.playerUnitID
					if state and unitID and spValidUnitID(unitID) and frame >= (state.nextMedkitPickupFrame or 0) then
						local health, maxHealth = Spring.GetUnitHealth(unitID)
						local x, _, z = Spring.GetUnitPosition(unitID)
						if health and maxHealth and health > 0 and health < maxHealth and x then
							local distance = (x - fx) * (x - fx) + (z - fz) * (z - fz)
							if distance <= MEDKIT_PICKUP_RADIUS * MEDKIT_PICKUP_RADIUS
								and (not bestDistance or distance < bestDistance) then
								bestTeam, bestDistance = teamID, distance
							end
						end
					end
				end
			end
			if bestTeam then
				local state = statesByTeam[bestTeam]
				local unitID = state and state.playerUnitID
				local maxHealth
				if unitID and spValidUnitID(unitID) then
					local _, unitMaxHealth = Spring.GetUnitHealth(unitID)
					maxHealth = unitMaxHealth
				end
				local restored = healCommanderForTeam(bestTeam, "medkit", (maxHealth or 0) * MEDKIT_HEAL_FRACTION)
				if restored > 0 then
					state.nextMedkitPickupFrame = frame + MEDKIT_PICKUP_COOLDOWN
					if not COOP_ENABLED then nextMedkitPickupFrame = state.nextMedkitPickupFrame end
					medkitsByFeature[featureID] = nil
					Spring.DestroyFeature(featureID)
					GG.Roguelike.medkitPickupCount = (GG.Roguelike.medkitPickupCount or 0) + 1
					Spring.Echo("Roguelike medkit picked team=" .. bestTeam .. " healed=" .. restored)
				end
			end
		end
	end
end

local function updateSharedSurvivalEffects(frame)
	updateRepairLink(frame)
	updateMedicalBeacon(frame)
	if frame % NANO_REPAIR_TICK_FRAMES == 0 then updateMedkitPickups(frame) end
end

local function buyShopItem(itemId, playerID)
	local item = SHOP_ITEMS[itemId]
	if not item then return end
	local teamID = getPlayerTeam(playerID)
	if not teamID or teamID ~= playerTeamID or not playerUnitID or not spValidUnitID(playerUnitID) then
		sendShopResult(false, item, shopLevels[itemId] or 0, 0, "invalid_player")
		return
	end
	if item.type == "factionWeapon" and getCommanderFaction(playerUnitID) ~= item.faction then
		sendShopResult(false, item, shopLevels[itemId] or 0, 0, "wrong_faction")
		return
	end
	if item.type == "factionWeapon" and upgradeCount < item.unlockAt then
		sendShopResult(false, item, shopLevels[itemId] or 0, 0, "locked")
		return
	end

	local level = shopLevels[itemId] or 0
	if level >= item.maxLevel then
		sendShopResult(false, item, level, 0, "max_level")
		return
	end
	if item.requires and (shopLevels[item.requires] or 0) <= 0 then
		sendShopResult(false, item, level, 0, "requires_weapon")
		return
	end
	if item.type == "weapon" or item.type == "factionWeapon" then
		local unitDef = UnitDefs[Spring.GetUnitDefID(playerUnitID)]
		if not findShopWeaponSlot(unitDef, itemId) then
			sendShopResult(false, item, level, 0, "weapon_unavailable")
			return
		end
	end
	local cost = nextShopCost(item, level)
	local metal = select(1, Spring.GetTeamResources(teamID, "metal")) or 0
	if metal < cost or not Spring.UseTeamResource(teamID, "metal", cost) then
		sendShopResult(false, item, level, cost, "not_enough_metal")
		return
	end

	shopLevels[itemId] = level + 1
	if item.type == "factionWeapon" and level == 0
		and countEquippedFactionWeapons() < MAX_EQUIPPED_FACTION_WEAPONS then
		equippedFactionWeapons[itemId] = true
	end
	if item.type == "healthPercent" then
		cumulativeMultipliers.shopHealthBonus = cumulativeMultipliers.shopHealthBonus + item.value
	elseif item.type == "regenPercent" then
		cumulativeMultipliers.regenBonus = cumulativeMultipliers.regenBonus + item.value
	elseif item.type ~= "weapon" and item.type ~= "weaponExtension" and item.type ~= "factionWeapon"
		and item.type ~= "supportSkill" then
		cumulativeMultipliers[item.type] = cumulativeMultipliers[item.type] * item.value
	end
	applyCommanderStats(playerUnitID, false)
	if item.type == "regenPercent" then
		local _, maxHealth = Spring.GetUnitHealth(playerUnitID)
		if maxHealth then healCurrentCommander("shop_regen", maxHealth) end
	end
	Spring.SetUnitRulesParam(playerUnitID, "roguelike_shop_" .. itemId .. "_level", level + 1, INLOS_ACCESS)
	Spring.SetUnitRulesParam(playerUnitID, "roguelike_shop_revision",
		(Spring.GetUnitRulesParam(playerUnitID, "roguelike_shop_revision") or 0) + 1, INLOS_ACCESS)
	Spring.Echo("Roguelike Shop: " .. item.name .. " level " .. (level + 1) .. " purchased for " .. cost .. " metal")
	sendAcquiredOptions()
	local resultReason = item.type == "factionWeapon"
		and (equippedFactionWeapons[itemId] and "purchased_equipped" or "purchased_unarmed")
		or ""
	sendShopResult(true, item, level + 1, cost, resultReason)
end

local function setFactionWeaponEquipped(itemId, playerID)
	local item = SHOP_ITEMS[itemId]
	if not item or item.type ~= "factionWeapon" or not playerUnitID or not spValidUnitID(playerUnitID)
		or getPlayerTeam(playerID) ~= playerTeamID then
		return
	end
	if getCommanderFaction(playerUnitID) ~= item.faction then
		sendShopResult(false, item, shopLevels[itemId] or 0, 0, "wrong_faction")
		return
	end
	if (shopLevels[itemId] or 0) <= 0 then
		sendShopResult(false, item, 0, 0, "not_owned")
		return
	end
	if equippedFactionWeapons[itemId] then
		equippedFactionWeapons[itemId] = nil
	else
		if countEquippedFactionWeapons() >= MAX_EQUIPPED_FACTION_WEAPONS then
			sendShopResult(false, item, shopLevels[itemId], 0, "equip_limit")
			return
		end
		equippedFactionWeapons[itemId] = true
	end
	applyCommanderStats(playerUnitID, false)
	sendAcquiredOptions()
	Spring.SetUnitRulesParam(playerUnitID, "roguelike_shop_revision",
		(Spring.GetUnitRulesParam(playerUnitID, "roguelike_shop_revision") or 0) + 1, INLOS_ACCESS)
	sendShopResult(true, item, shopLevels[itemId] or 0, 0,
		equippedFactionWeapons[itemId] and "equipped" or "unequipped")
end

local function receivePersonalMessage(msg, playerID)
	-- LuaUI 消息只是购买/选卡请求。所有影响资源和战斗属性的字段都必须在
	-- synced 端重新查表与验证，不能信任客户端传来的价格、等级或卡牌内容。
	if not msg then return end
	if msg == "roguelike_sync" then
		sendAcquiredOptions()
		showNextPendingChoice()
		return
	end

	local action, nonce, nonceItem = msg:match("^(roguelike_shop):(%d+%-%d+):([%w_%-]+)$")
	if not action then action, nonce, nonceItem = msg:match("^(roguelike_equip):(%d+%-%d+):([%w_%-]+)$") end
	if not action then action, nonce, nonceItem = msg:match("^(roguelike_skill):(%d+%-%d+):([%w_%-]+)$") end
	if action then
		local key = action .. ":" .. nonce
		if processedRequests[key] then return end
		processedRequests[key] = Spring.GetGameFrame()
		msg = action .. ":" .. nonceItem
	end
	local shopItemId = msg:match("^roguelike_shop:([%w_%-]+)$")
	if shopItemId then
		-- Requests carry a unique nonce and are deduplicated above. Do not throttle
		-- purchases by game frame: the single-player shop pauses the simulation,
		-- so a player could otherwise buy each attribute only once per visit.
		buyShopItem(shopItemId, playerID)
		return
	end
	local equipItemId = msg:match("^roguelike_equip:([%w_%-]+)$")
	if equipItemId then
		local key = "equip:" .. equipItemId
		local frame = Spring.GetGameFrame()
		if lastItemRequestFrame[key] == frame then return end
		lastItemRequestFrame[key] = frame
		setFactionWeaponEquipped(equipItemId, playerID)
		return
	end
	local skillID = msg:match("^roguelike_skill:([%w_%-]+)$")
	if skillID then
		useSurvivalSkill(skillID, playerID)
		return
	end

	local refreshID = tonumber(msg:match("^roguelike_refresh:(%d+)$"))
	local refreshPending = refreshID and refreshID == activeChoiceId and pendingChoices[refreshID]
	if refreshPending and getPlayerTeam(playerID) == playerTeamID and refreshesRemaining > 0 then
		local excluded = {}
		for _, choice in ipairs(refreshPending.choices) do excluded[choice.id] = true end
		refreshesRemaining = refreshesRemaining - 1
		refreshPending.choices = pickRandomChoices(CHOICES_PER_OFFER, excluded)
		if #refreshPending.choices == 0 then
			refreshPending.choices = { { id = "training", name = "基础训练", desc = "+1% 最大生命值", icon = "生命", type = "training", value = 0.01 } }
		end
		writeProgressRules(playerUnitID)
		personalEvent("RoguelikeOfferChoices", refreshID, serializeChoices(refreshPending.choices), refreshesRemaining, skipsRemaining, banishesRemaining)
		return
	end

	local skipID = tonumber(msg:match("^roguelike_skip:(%d+)$"))
	if skipID and skipID == activeChoiceId and pendingChoices[skipID]
		and getPlayerTeam(playerID) == playerTeamID and skipsRemaining > 0 then
		skipsRemaining = skipsRemaining - 1
		pendingChoices[skipID] = nil
		activeChoiceId = nil
		writeProgressRules(playerUnitID)
		showNextPendingChoice()
		return
	end

	local banishChoiceID, banishUpgradeID = msg:match("^roguelike_banish:(%d+):([%w_%-]+)$")
	banishChoiceID = tonumber(banishChoiceID)
	local banishPending = banishChoiceID and banishChoiceID == activeChoiceId and pendingChoices[banishChoiceID]
	if banishPending and getPlayerTeam(playerID) == playerTeamID and banishesRemaining > 0 then
		local found = false
		local excluded = {}
		for _, choice in ipairs(banishPending.choices) do
			excluded[choice.id] = true
			if choice.id == banishUpgradeID then found = true end
		end
		if found then
			banishesRemaining = banishesRemaining - 1
			banishedCardIds[banishUpgradeID] = true
			banishPending.choices = pickRandomChoices(CHOICES_PER_OFFER, excluded)
			if #banishPending.choices == 0 then
				banishPending.choices = { { id = "training", name = "基础训练", desc = "+1% 最大生命值", icon = "生命", type = "training", value = 0.01 } }
			end
			writeProgressRules(playerUnitID)
			personalEvent("RoguelikeOfferChoices", banishChoiceID, serializeChoices(banishPending.choices), refreshesRemaining, skipsRemaining, banishesRemaining)
		end
		return
	end

	local choiceIdString, upgradeId = msg:match("^roguelike_pick:(%d+):([%w_%-]+)$")
	if not choiceIdString then return end
	local choiceId = tonumber(choiceIdString)
	local pending = choiceId and pendingChoices[choiceId]
	if not pending or choiceId ~= activeChoiceId or getPlayerTeam(playerID) ~= pending.teamID then return end

	local selectedUpgrade
	for _, upgrade in ipairs(pending.choices) do
		if upgrade.id == upgradeId then
			selectedUpgrade = upgrade
			break
		end
	end
	if not selectedUpgrade then return end

	if applyCardUpgrade(selectedUpgrade) then
		pendingChoices[choiceId] = nil
		activeChoiceId = nil
		showNextPendingChoice()
	end
end

function gadget:RecvLuaMsg(msg, playerID)
	if not msg or not msg:find("^roguelike_") then return end
	local teamID = getPlayerTeam(playerID)
	if not teamID then return end
	if COOP_ENABLED then
		if not statesByTeam[teamID] then return end
		withTeam(teamID, receivePersonalMessage, msg, playerID)
	else
		receivePersonalMessage(msg, playerID)
	end
end

function gadget:Initialize()
	if COOP_ENABLED then
		for _, unitID in ipairs(Spring.GetAllUnits()) do
			local unitDefID = Spring.GetUnitDefID(unitID)
			local teamID = Spring.GetUnitTeam(unitID)
			if isCommander(unitDefID) and isHumanTeam(teamID) then
				withTeam(teamID, setPlayerCommander, unitID, teamID)
			end
		end
	elseif GG.Roguelike and GG.Roguelike.playerUnitID and spValidUnitID(GG.Roguelike.playerUnitID) then
		local state = selectTeam(GG.Roguelike.playerTeamID)
		setPlayerCommander(GG.Roguelike.playerUnitID, GG.Roguelike.playerTeamID)
		storeTeam(state)
	else
		for _, unitID in ipairs(Spring.GetAllUnits()) do
			local unitDefID = Spring.GetUnitDefID(unitID)
			local teamID = Spring.GetUnitTeam(unitID)
			if isCommander(unitDefID) and isHumanTeam(teamID) then
				local state = selectTeam(teamID)
				setPlayerCommander(unitID, teamID)
				storeTeam(state)
				break
			end
		end
	end

	GG.Roguelike = GG.Roguelike or {}
	GG.Roguelike.HealCommander = healCommanderForTeam
	GG.Roguelike.RegisterDamageHealContext = registerDamageHealContext
	GG.Roguelike.OnKill = processEffectiveKill
	GG.Roguelike.GetMultipliers = function()
		if not COOP_ENABLED then return cumulativeMultipliers end
		local strongest = 1
		for _, state in pairs(statesByTeam) do
			strongest = math.max(strongest, state.cumulativeMultipliers.damage)
		end
		return { damage = strongest }
	end
	local function waveClearedForCurrentTeam(clearedWave)
		waveOfferTarget = math.max(waveOfferTarget, WAVE_GUARANTEED_OFFERS[tonumber(clearedWave) or 0] or 0)
		processKillCount()
		-- Spawner 在 70 秒边界、下一波编号递增前调用；旧波敌人仍可存活。
		-- clearedWave == 2 对应“第二波时间结束、第三波开始”。
		if tonumber(clearedWave) == 2 then
			unlockFirstDroneMilestone()
		end
		if playerUnitID and spValidUnitID(playerUnitID) then
			local _, maxHealth = Spring.GetUnitHealth(playerUnitID)
			if maxHealth then
				local restored = healCurrentCommander("wave_clear", maxHealth * WAVE_CLEAR_HEAL_FRACTION)
				Spring.SetUnitRulesParam(playerUnitID, "roguelike_last_wave_heal", restored, INLOS_ACCESS)
			end
		end
	end
	GG.Roguelike.OnWaveCleared = function(clearedWave)
		if COOP_ENABLED then
			for _, teamID in ipairs(GG.Roguelike.teamIDs or {}) do
				if statesByTeam[teamID] then withTeam(teamID, waveClearedForCurrentTeam, clearedWave) end
			end
		else
			waveClearedForCurrentTeam(clearedWave)
		end
	end
	if not playerUnitID then
		Spring.Echo("Roguelike: no player commander found during initialization")
	end
end

function gadget:Shutdown()
	if GG.Roguelike then
		GG.Roguelike.OnKill = nil
		GG.Roguelike.GetMultipliers = nil
		GG.Roguelike.OnWaveCleared = nil
		GG.Roguelike.HealCommander = nil
		GG.Roguelike.RegisterDamageHealContext = nil
	end
end

local function updateCurrentTeam(frame)
	if frame % Game.gameSpeed ~= 0 then return end
	for requestKey, seenFrame in pairs(processedRequests) do
		if seenFrame < frame - Game.gameSpeed * 30 then processedRequests[requestKey] = nil end
	end
	if not COOP_ENABLED and (not playerUnitID or not spValidUnitID(playerUnitID)) and GG.Roguelike
		and GG.Roguelike.playerUnitID and spValidUnitID(GG.Roguelike.playerUnitID) then
		setPlayerCommander(GG.Roguelike.playerUnitID, GG.Roguelike.playerTeamID)
	end
	if not playerUnitID or not spValidUnitID(playerUnitID) then return end
	syncNativeShield(playerUnitID)

	-- 其他属性 Gadget 可能在初始化后刷新单位经济，因此每秒重申升级后的绝对产量。
	Spring.SetUnitResourcing(playerUnitID, "ume", baseCommanderEnergyMake + upgradeCount * ENERGY_INCOME_PER_UPGRADE)
	Spring.SetUnitResourcing(playerUnitID, "umm", 0)
	Spring.SetUnitRulesParam(playerUnitID, "selfMoveSpeedChange", cumulativeMultipliers.move, INLOS_ACCESS)
	Spring.SetUnitRulesParam(playerUnitID, "upgradesSpeedMult", 1, INLOS_ACCESS)
	if GG.UpdateUnitAttributes then
		GG.UpdateUnitAttributes(playerUnitID)
	end
	if cumulativeMultipliers.shield > 0
		and frame - lastShieldHitFrame >= SHIELD_REGEN_DELAY
		and shieldCurrent < cumulativeMultipliers.shield then
		local wantedRegen = math.min(cumulativeMultipliers.shield - shieldCurrent,
			math.max(1, cumulativeMultipliers.shield * SHIELD_REGEN_PER_SECOND))
		local availableEnergy = select(1, Spring.GetTeamResources(playerTeamID, "energy")) or 0
		local actualRegen = math.min(wantedRegen, availableEnergy / SHIELD_ENERGY_PER_POINT)
		local energyCost = actualRegen * SHIELD_ENERGY_PER_POINT
		if actualRegen > 0 and Spring.UseTeamResource(playerTeamID, "energy", energyCost) then
			shieldCurrent = shieldCurrent + actualRegen
			setNativeShield(playerUnitID, shieldCurrent)
			Spring.SetUnitRulesParam(playerUnitID, "roguelike_shield_current", shieldCurrent, INLOS_ACCESS)
		end
	end
	-- 开局准备阶段（phase 3）持续回复；之后连续作战，只在脱战
	-- HEALTH_REGEN_DELAY 后按基础+商店回复。
	local regenRate = 0
	if GG.Roguelike and GG.Roguelike.phase == 3 then
		regenRate = RECOVERY_HEAL_PER_SECOND + cumulativeMultipliers.regenBonus
	elseif frame - lastHealthDamageFrame >= HEALTH_REGEN_DELAY then
		regenRate = BASE_HEALTH_REGEN_PER_SECOND + cumulativeMultipliers.regenBonus
	end
	if regenRate > 0 then
		local health, maxHealth = Spring.GetUnitHealth(playerUnitID)
		if health and maxHealth and health > 0 and health < maxHealth then
			healCurrentCommander("passive_regen", maxHealth * regenRate, { sustained = true })
		end
	end

	if GG.Roguelike and GG.Roguelike.sharedXP then sharedXP = GG.Roguelike.sharedXP end
	processKillCount()
end

function gadget:GameFrame(frame)
	-- Damage pre/post callbacks are synchronous. Anything left at the next frame
	-- is stale (for example, a cancelled hit) and must not pay out.
	pendingDamageByTarget = {}
	explicitDamageHealContexts = {}
	if frame % NANO_REPAIR_TICK_FRAMES ~= 0 then return end
	if COOP_ENABLED then
		for _, teamID in ipairs(GG.Roguelike and GG.Roguelike.teamIDs or {}) do
			local state = statesByTeam[teamID]
			local registered = GG.Roguelike.teams and GG.Roguelike.teams[teamID]
			local unitID = registered and registered.commanderUnitID
			if state and unitID and spValidUnitID(unitID) then
				withTeam(teamID, function()
					if playerUnitID ~= unitID then setPlayerCommander(unitID, teamID) end
					updateOwnedSurvivalEffects(frame)
					if frame % Game.gameSpeed == 0 then updateCurrentTeam(frame) end
				end)
			end
		end
	else
		updateOwnedSurvivalEffects(frame)
		if frame % Game.gameSpeed == 0 then updateCurrentTeam(frame) end
	end
	updateSharedSurvivalEffects(frame)
end

function gadget:FeaturePreDamaged(featureID, featureDefID, featureTeam, damage, weaponDefID, projectileID, attackerID)
	if medkitsByFeature[featureID] then return 0, 0 end
	return damage
end

function gadget:FeatureDestroyed(featureID)
	if medkitsByFeature[featureID] then medkitsByFeature[featureID] = nil end
end

function gadget:UnitCreated(unitID, unitDefID, unitTeam)
	if isCommander(unitDefID) and isHumanTeam(unitTeam) then
		if COOP_ENABLED then
			if GG.Roguelike and GG.Roguelike.teamIDs then
				for _, teamID in ipairs(GG.Roguelike.teamIDs) do
					if teamID == unitTeam then withTeam(unitTeam, setPlayerCommander, unitID, unitTeam); return end
				end
			end
		elseif not playerTeamID or unitTeam == playerTeamID then
			if not statesByTeam[unitTeam] then selectTeam(unitTeam) end
			setPlayerCommander(unitID, unitTeam)
			storeTeam(statesByTeam[unitTeam])
		end
	end
end

function gadget:UnitDestroyed(unitID, unitDefID, unitTeam)
	if COOP_ENABLED then
		local state = unitTeam and statesByTeam[unitTeam]
		if state and state.playerUnitID == unitID then
			withTeam(unitTeam, function() playerUnitID = nil end)
		end
		return
	end
	if unitID == playerUnitID then
		playerUnitID = nil
		if statesByTeam[playerTeamID] then statesByTeam[playerTeamID].playerUnitID = nil end
		if GG.Roguelike then GG.Roguelike.playerUnitID = nil end
	end
end

-- WeaponDef 在开局后不可修改，因此全局伤害成长和武器专属扩展统一在
-- UnitPreDamaged 中结算。承伤顺序固定为：虚拟护盾吸收 → 护甲减伤 →
-- 集火保护 → 生命；指挥官输出则先应用通用倍率，再按 WeaponDefID 应用扩展。
local function calculateCurrentTeamDamage(unitID, unitDefID, unitTeam, damage, paralyzer, weaponDefID, projectileID, attackerID)
	if unitID == playerUnitID and not paralyzer and damage > 0 and attackerID then
		local frame = Spring.GetGameFrame()
		if Spring.GetUnitRulesParam(attackerID, "roguelike_enemy_explosive") == 1
			and cumulativeMultipliers.blastLining > 0 then
			damage = damage * (1 - math.min(BLAST_LINING_LIMIT, cumulativeMultipliers.blastLining))
		end
		if bastionEndFrame > frame and Spring.GetUnitTeam(attackerID) ~= playerTeamID then
			damage = damage * 0.75
		end
	end
	if unitID == playerUnitID and damage > 0 and cumulativeMultipliers.shield > 0 then
		-- The native shield has already intercepted/bounced eligible projectiles.
		-- Sync its charge here, but do not subtract the remaining unit damage a
		-- second time: UnitPreDamaged only sees damage that reached the commander.
		syncNativeShield(unitID)
		Spring.SetUnitRulesParam(playerUnitID, "roguelike_shield_current", shieldCurrent, INLOS_ACCESS)
	end
	if unitID == playerUnitID and not paralyzer and damage > 0 and barrierPoints > 0
		and barrierEndFrame > Spring.GetGameFrame() then
		local absorbed = math.min(damage, barrierPoints)
		barrierPoints = barrierPoints - absorbed
		damage = damage - absorbed
		Spring.SetUnitRulesParam(playerUnitID, "roguelike_barrier_current", barrierPoints, INLOS_ACCESS)
	end
	-- 护盾先承受原始伤害；只有溢出到机体的部分才经过护甲减免。
	if unitID == playerUnitID and not paralyzer and damage > 0 and cumulativeMultipliers.armor > 0 then
		damage = damage * (1 - cumulativeMultipliers.armor)
	end
	if unitID == playerUnitID and not paralyzer and damage > 0 and attackerID
		and Spring.GetUnitRulesParam(attackerID, "roguelike_enemy_damage_mult") ~= nil then
		local frame = Spring.GetGameFrame()
		if frame - focusGuardWindowStartFrame >= FOCUS_GUARD_WINDOW_FRAMES then
			focusGuardWindowStartFrame = frame
			focusGuardRawDamage = 0
		end

		local _, maxHealth = Spring.GetUnitHealth(playerUnitID)
		if maxHealth and maxHealth > 0 then
			-- 多个远程单位可能在相邻几帧内同时命中。每秒前 10% 最大生命伤害
			-- 保持全额结算，只压缩超出部分，为玩家保留反应时间；持续受火、
			-- 近战包围和错误站位仍然会造成致命威胁。
			local fullDamageBudget = maxHealth * FOCUS_GUARD_FULL_DAMAGE_FRACTION
			local fullDamage = math.min(damage, math.max(0, fullDamageBudget - focusGuardRawDamage))
			local overflowDamage = damage - fullDamage
			focusGuardRawDamage = focusGuardRawDamage + damage
			damage = fullDamage + overflowDamage * FOCUS_GUARD_OVERFLOW_MULTIPLIER
		end
	end
	if unitID == playerUnitID and not paralyzer and damage > 0 then
		lastHealthDamageFrame = Spring.GetGameFrame()
	end
	local attackerWeapon = weaponDefID and WeaponDefs[weaponDefID]
	if attackerID == playerUnitID and attackerWeapon and attackerWeapon.type ~= "DGun"
		and not attackerWeapon.manualFire and not paralyzer then
		damage = damage * effectiveDamageMultiplier()
		local weaponNum = commanderWeaponSlotByDefID[weaponDefID]
		local shopWeaponId = commanderWeaponShopItemByDefID[weaponDefID]
		if shopWeaponId == "lightning_weapon" then
			local level = shopLevels.lightning_extension or 0
			damage = damage * (1 + level * LIGHTNING_EXTENSION_DAMAGE_PER_LEVEL)
		elseif shopWeaponId == "plasma_weapon" then
			local level = shopLevels.plasma_extension or 0
			damage = damage * (1 + level * PLASMA_EXTENSION_DAMAGE_PER_LEVEL)
		elseif shopWeaponId == "sniper_weapon" then
			local level = shopLevels.sniper_extension or 0
			if level > 0 then
				local health, maxHealth = Spring.GetUnitHealth(unitID)
				if health and maxHealth and maxHealth > 0
					and health / maxHealth <= SNIPER_EXTENSION_EXECUTE_THRESHOLD then
					damage = damage * (1 + level * SNIPER_EXTENSION_DAMAGE_PER_LEVEL)
				end
			end
		elseif shopWeaponId == "barrage_weapon" then
			local level = shopLevels.barrage_extension or 0
			damage = damage * (1 + level * BARRAGE_EXTENSION_DAMAGE_PER_LEVEL)
		elseif shopWeaponId == "shockwave_weapon" then
			local level = shopLevels.shockwave_extension or 0
			local targetDef = UnitDefs[unitDefID]
			if level > 0 and targetDef and (targetDef.health or math.huge) <= SHOCKWAVE_EXTENSION_MAX_BASE_HEALTH then
				damage = damage * (1 + level * SHOCKWAVE_EXTENSION_DAMAGE_PER_LEVEL)
			end
		end
	end
	-- 召唤物由各自 Gadget 写入该 RulesParam；伤害仍在 synced 端统一结算。
	if attackerID and attackerID ~= playerUnitID and not paralyzer then
		local summonDamageMult = Spring.GetUnitRulesParam(attackerID, "roguelike_summon_damage_mult")
		if summonDamageMult then
			damage = damage * summonDamageMult
		end
	end
	return damage
end

local function getWeaponAreaOfEffect(weaponDef)
	return weaponDef and (tonumber(weaponDef.damageAreaOfEffect or weaponDef.areaOfEffect
		or weaponDef.areaofeffect or weaponDef.aoe) or 0) or 0
end

local function getDamageHealKind(context, targetID)
	if context.damageKind then return context.damageKind, context.attackID end
	local info = context.projectileInfo
	local bus = GG.RoguelikeWeaponEffects
	if not info and context.projectileID and bus and bus.GetDamageAttribution then
		info = bus.GetDamageAttribution(context.projectileID)
	end
	if info then
		local weaponDef = WeaponDefs[context.weaponDefID]
		local area = tonumber(info.radius) or getWeaponAreaOfEffect(weaponDef)
		local targetX, _, targetZ = Spring.GetUnitPosition(targetID)
		if info.x and info.z and targetX and area > 0 then
			local dx, dz = targetX - info.x, targetZ - info.z
			if dx * dx + dz * dz <= math.max(32, area * 0.35) ^ 2 then
				if info.kind == "meteor" then return "meteor", info.rootAttackID end
				if info.kind == "splitter" then return "splitter", info.rootAttackID end
			end
		end
		if info.kind == "meteor" or info.kind == "splitter" or area > 0 then
			return "area", info.rootAttackID or info.projectileID
		end
		return "direct", info.rootAttackID or info.projectileID
	end
	if getWeaponAreaOfEffect(WeaponDefs[context.weaponDefID]) > 0 then
		return "area", context.projectileID
	end
	return "direct", context.projectileID
end

local function isOwnedCommanderHit(attackerID, attackerTeam)
	local state = attackerTeam and statesByTeam[attackerTeam]
	return state and state.playerUnitID == attackerID
end

local function cleanupDamageHealState(frame)
	if frame - lastDamageHealCleanupFrame < 30 then return end
	lastDamageHealCleanupFrame = frame
	for targetID, lastFrame in pairs(lastHitRepairByTarget) do
		if frame - lastFrame > Game.gameSpeed then lastHitRepairByTarget[targetID] = nil end
	end
	for eventID, eventFrame in pairs(damageHealRecentEvents) do
		if frame - eventFrame > 10 * Game.gameSpeed then damageHealRecentEvents[eventID] = nil end
	end
end

local function applyDamageTriggeredHealing(targetID, unitTeam, damage, paralyzer, weaponDefID, projectileID, attackerID)
	local context = pendingDamageByTarget[targetID]
	pendingDamageByTarget[targetID] = nil
	if not context or context.frame ~= Spring.GetGameFrame() or context.attackerID ~= attackerID
		or context.weaponDefID ~= weaponDefID or paralyzer or not attackerID
		or not spValidUnitID(attackerID) then return end
	local ownerTeam = context.teamID
	if not ownerTeam or ownerTeam ~= Spring.GetUnitTeam(attackerID) or not isOwnedCommanderHit(attackerID, ownerTeam) then return end
	local effectBus = GG.RoguelikeWeaponEffects
	if effectBus and effectBus.currentProcTargetID == targetID then return end
	local hitWeapon = weaponDefID and WeaponDefs[weaponDefID]
	if hitWeapon and (hitWeapon.type == "DGun" or hitWeapon.manualFire) then return end
	if not statesByTeam[ownerTeam] or not context.healthBefore or context.healthBefore <= 0 then return end
	local targetDef = UnitDefs[context.targetDefID]
	local gaiaTeam = Spring.GetGaiaTeamID and Spring.GetGaiaTeamID()
	if unitTeam == ownerTeam or Spring.AreTeamsAllied(ownerTeam, unitTeam)
		or unitTeam == gaiaTeam or not targetDef or targetDef.isNeutral then return end
	local healthAfter = Spring.GetUnitHealth(targetID)
	if healthAfter == nil and spValidUnitID(targetID) then return end
	healthAfter = math.max(0, healthAfter or 0)
	local effectiveDamage = damageHealingRules.EffectiveHealthDamage(context.healthBefore, healthAfter)
	if effectiveDamage <= 0 then return end
	local damageKind, attackID = getDamageHealKind(context, targetID)
	if damageKind == "area" and cumulativeMultipliers.areaLeech <= 0 then return end
	if damageKind == "dot" and cumulativeMultipliers.dotLeech <= 0 then return end
	local coefficient = damageHealingRules.DamageCoefficient(damageKind, {
		area = cumulativeMultipliers.areaLeech, dot = cumulativeMultipliers.dotLeech,
	})
	if coefficient <= 0 then return end
	local frame = Spring.GetGameFrame()
	cleanupDamageHealState(frame)
	local eventIdentity = damageKind == "dot"
		and tostring(attackID or weaponDefID) .. ":tick:" .. math.floor(frame / math.max(1, Game.gameSpeed * 0.25))
		or tostring(attackID or (frame .. ":" .. tostring(weaponDefID)))
	local eventKey = tostring(ownerTeam) .. ":" .. eventIdentity
		.. ":" .. tostring(targetID) .. ":" .. tostring(damageKind)
	if damageHealRecentEvents[eventKey] then return end
	damageHealRecentEvents[eventKey] = frame
	local maxHealth = select(2, Spring.GetUnitHealth(attackerID))
	local attackerHealth = Spring.GetUnitHealth(attackerID)
	if not attackerHealth or attackerHealth <= 0 or not maxHealth or maxHealth <= 0 then return end
	if cumulativeMultipliers.lifeDrain > 0 then
		local nominal = effectiveDamage * cumulativeMultipliers.lifeDrain * coefficient
		healCurrentCommander("lifesteal", nominal, { sustained = true, damageTriggered = true })
	end
	if cumulativeMultipliers.hitRepair > 0
		and (damageKind == "direct" or damageKind == "meteor" or damageKind == "splitter") then
		local cooldownFrames = math.max(1, math.ceil(Game.gameSpeed * 0.25))
		if frame - (lastHitRepairByTarget[targetID] or -cooldownFrames) >= cooldownFrames then
			lastHitRepairByTarget[targetID] = frame
			healCurrentCommander("hit_repair", maxHealth * cumulativeMultipliers.hitRepair,
				{ sustained = true, damageTriggered = true })
		end
	end
end

function gadget:UnitPreDamaged(unitID, unitDefID, unitTeam, damage, paralyzer, weaponDefID, projectileID, attackerID)
	local explicit = explicitDamageHealContexts[unitID]
	explicitDamageHealContexts[unitID] = nil
	local attackerTeam = attackerID and Spring.GetUnitTeam(attackerID)
	if explicit or isOwnedCommanderHit(attackerID, attackerTeam) then
		local state = attackerTeam and statesByTeam[attackerTeam]
		local hasHealUpgrade = explicit or (state and state.cumulativeMultipliers
			and (state.cumulativeMultipliers.lifeDrain > 0 or state.cumulativeMultipliers.hitRepair > 0
				or state.cumulativeMultipliers.areaLeech > 0 or state.cumulativeMultipliers.dotLeech > 0))
		if hasHealUpgrade then
			local healthBefore = Spring.GetUnitHealth(unitID)
			if healthBefore and healthBefore > 0 then
				local context = explicit or {}
				local effectBus = GG.RoguelikeWeaponEffects
				local projectileInfo = projectileID and effectBus and effectBus.GetDamageAttribution
					and effectBus.GetDamageAttribution(projectileID) or nil
				pendingDamageByTarget[unitID] = {
					frame = Spring.GetGameFrame(), healthBefore = healthBefore, attackerID = attackerID,
					teamID = context.teamID or attackerTeam, damageKind = context.damageKind,
					attackID = context.attackID, targetDefID = unitDefID,
					weaponDefID = weaponDefID, projectileID = projectileID,
					projectileInfo = projectileInfo,
				}
			end
		end
	end
	if not COOP_ENABLED then
		damage = calculateCurrentTeamDamage(unitID, unitDefID, unitTeam, damage, paralyzer, weaponDefID, projectileID, attackerID)
		local bus = GG.RoguelikeWeaponEffects
		if bus and bus.currentProcTargetID == unitID and damage > 0 then
			local _, maxHealth = Spring.GetUnitHealth(unitID)
			local unitDef = UnitDefs[unitDefID]
			if maxHealth and unitDef and ((unitDef.customParams and unitDef.customParams.roguelike_boss) or maxHealth > 12000) then
				damage = math.min(damage, maxHealth * 0.05)
			end
		end
		return damage
	end
	local targetTeam = statesByTeam[unitTeam] and statesByTeam[unitTeam].playerUnitID == unitID and unitTeam or nil
	local attackerIsCommander = attackerTeam and statesByTeam[attackerTeam]
		and statesByTeam[attackerTeam].playerUnitID == attackerID
	if damage > 0 and attackerTeam and statesByTeam[unitTeam] and statesByTeam[attackerTeam]
		and Spring.AreTeamsAllied(unitTeam, attackerTeam) then
		return 0
	end
	if targetTeam then
		damage = withTeam(targetTeam, calculateCurrentTeamDamage, unitID, unitDefID, unitTeam,
			damage, paralyzer, weaponDefID, projectileID, attackerID)
	end
	if attackerIsCommander and attackerTeam ~= targetTeam then
		damage = withTeam(attackerTeam, calculateCurrentTeamDamage, unitID, unitDefID, unitTeam,
			damage, paralyzer, weaponDefID, projectileID, attackerID)
	elseif not targetTeam then
		local summonDamageMult = attackerID and Spring.GetUnitRulesParam(attackerID, "roguelike_summon_damage_mult")
		if summonDamageMult and not paralyzer then damage = damage * summonDamageMult end
	end
	local bus = GG.RoguelikeWeaponEffects
	if bus and bus.currentProcTargetID == unitID and damage > 0 then
		local _, maxHealth = Spring.GetUnitHealth(unitID)
		local unitDef = UnitDefs[unitDefID]
		if maxHealth and unitDef and ((unitDef.customParams and unitDef.customParams.roguelike_boss) or maxHealth > 12000) then
			damage = math.min(damage, maxHealth * 0.05)
		end
	end
	return damage
end

function gadget:UnitDamaged(unitID, unitDefID, unitTeam, damage, paralyzer, weaponDefID, projectileID, attackerID)
	local attackerTeam = attackerID and Spring.GetUnitTeam(attackerID)
	if not attackerTeam then pendingDamageByTarget[unitID] = nil; return end
	if COOP_ENABLED then
		if isOwnedCommanderHit(attackerID, attackerTeam) then
			withTeam(attackerTeam, applyDamageTriggeredHealing, unitID, unitTeam, damage,
				paralyzer, weaponDefID, projectileID, attackerID)
		else
			pendingDamageByTarget[unitID] = nil
		end
	elseif attackerTeam == playerTeamID then
		applyDamageTriggeredHealing(unitID, unitTeam, damage, paralyzer, weaponDefID, projectileID, attackerID)
	else
		pendingDamageByTarget[unitID] = nil
	end
end
