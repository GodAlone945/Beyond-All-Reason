--------------------------------------------------------------------------------
-- [LuaUI 本地展示模块：RML HUD、升级选卡与商店交互]
--
-- 本 Widget 只读取 synced Gadget 写入的 UnitRulesParam、接收同步事件并更新
-- RML 数据模型。点击卡牌/商品时只发送 roguelike_pick / roguelike_shop 请求；
-- 是否有效、是否扣费和属性是否生效，全部由 synced Upgrades 重新验证。
--
-- gui_roguelike.rml 定义结构，gui_roguelike.rcss 定义布局与交互样式。本文件
-- 还负责弹窗期间的本地暂停请求和鼠标事件隔离，但不持有权威游戏状态。
--------------------------------------------------------------------------------
local roguelikeOption = Spring.GetModOptions().roguelike_mode
-- 兼容 Spring 传入的布尔、数字和字符串形式；未启用时不注册此 Widget。
if roguelikeOption ~= true and roguelikeOption ~= 1 and roguelikeOption ~= "1" and roguelikeOption ~= "true" then
	return false
end
local coopOption = Spring.GetModOptions().roguelike_coop
local COOP_ENABLED = coopOption == true or coopOption == 1 or coopOption == "1" or coopOption == "true"

-- RmlUi 不可用时无法创建 HUD 文档，因此直接退出。
if not RmlUi then
    Spring.Echo("警告: 当前游戏引擎环境不支持 RmlUi，Widget 退出！")
    return
end

local widget = widget ---@type Widget

function widget:GetInfo()
    return {
        name      = "Roguelike HUD & Shop",
        desc      = "RmlUi-based upgrade picker, shop, and HUD for roguelike mode",
        author    = "GodAlone945",
        date      = "2025",
        license   = "GNU GPL, v2 or later",
        layer     = 1,
        enabled   = true,
    }
end

--------------------------------------------------------------------------------
-- API

local spGetMyTeamID       = Spring.GetMyTeamID
local spGetTeamResources  = Spring.GetTeamResources
local spGetUnitRulesParam = Spring.GetUnitRulesParam
local spGetUnitDefID      = Spring.GetUnitDefID
local spGetTeamUnits      = Spring.GetTeamUnits
local spSendLuaRulesMsg   = Spring.SendLuaRulesMsg
local spGetGameSeconds    = Spring.GetGameSeconds
local spGetGameFrame      = Spring.GetGameFrame
local spGetGameSpeed      = Spring.GetGameSpeed
local spSendCommands      = Spring.SendCommands

--------------------------------------------------------------------------------
-- 常量

local MODEL_NAME = "roguelike_model"
local RML_PATH   = "luaui/RmlWidgets/gui_roguelike/gui_roguelike.rml"

local UPDATE_INTERVAL = 0.5 -- 秒

--------------------------------------------------------------------------------
-- 商店定义

local SHOP_ITEMS = {
    { id = "damage", name = "武器强化", desc = "+2% 武器伤害", baseCost = 80, costStep = 60, maxLevel = 20, icon = "伤害", category = "damage" },
    { id = "absorb", name = "吸取", desc = "每次命中恢复攻击伤害的 5%", baseCost = 250, costStep = 200, maxLevel = 10, icon = "生命", category = "health" },
    { id = "health", name = "装甲强化", desc = "+10% 最大生命值", baseCost = 100, costStep = 75, maxLevel = 20, icon = "生命", category = "health" },
    { id = "regen", name = "纳米修复", desc = "开局准备或脱战额外回复 +0.30% 最大生命/秒，购买后回满生命", baseCost = 250, costStep = 220, maxLevel = 5, icon = "修复", category = "health" },
    { id = "reload", name = "冷却强化", desc = "+8% 攻击速度", baseCost = 120, costStep = 90, maxLevel = 15, icon = "攻速", category = "reload" },
    { id = "move", name = "机动强化", desc = "+6% 移动速度", baseCost = 100, costStep = 75, maxLevel = 15, icon = "移速", category = "move" },
    { id = "range", name = "火控强化", desc = "+5% 武器射程", baseCost = 150, costStep = 125, maxLevel = 8, icon = "射程", category = "range" },
    { id = "salvage", name = "残骸精炼", desc = "+15% 残骸金属收益", baseCost = 120, costStep = 100, maxLevel = 10, icon = "精炼", category = "salvage" },
    { id = "salvage_speed", name = "快速回收", desc = "+15% 残骸吸收速度", baseCost = 100, costStep = 80, maxLevel = 10, icon = "回收", category = "salvage" },
    { id = "lightning_weapon", name = "雷霆步枪", desc = "解锁近程连锁闪电武器", baseCost = 1200, costStep = 0, maxLevel = 1, icon = "贵重", category = "weapon" },
    { id = "plasma_weapon", name = "Tzar 重型主炮", desc = "解锁 Cortex Tzar 的 1100 伤害重型主炮", baseCost = 1800, costStep = 0, maxLevel = 1, icon = "贵重", category = "weapon" },
    { id = "multishot", name = "多重射击", desc = "每级增加两枚同帧弹丸，最多九枚", baseCost = 1200, costStep = 1000, maxLevel = 4, icon = "攻击", category = "weapon" },
    { id = "drone_swarm", name = "轨道无人机", desc = "每级召唤 2 架无人机，最多 8 架", baseCost = 900, costStep = 700, maxLevel = 4, icon = "无人机", category = "support" },
    { id = "sniper_weapon", name = "湮灭狙击光束", desc = "解锁高伤害远程单体武器", baseCost = 2800, costStep = 0, maxLevel = 1, icon = "狙击", category = "sniper" },
    { id = "barrage_weapon", name = "凝固汽油覆盖炮", desc = "解锁超远程范围覆盖打击", baseCost = 2700, costStep = 0, maxLevel = 1, icon = "覆盖", category = "barrage" },
    { id = "shockwave_weapon", name = "冲击清场炮", desc = "解锁击退与清杂范围武器", baseCost = 2200, costStep = 0, maxLevel = 1, icon = "清场", category = "crowd" },
    { id = "electric_orb", name = "电球", desc = "ARM 专属实体电球；命中后 18% 概率传导至附近敌人", baseCost = 1400, costStep = 0, maxLevel = 1, icon = "闪电", category = "weapon", prototypeFaction = "armada" },
    { id = "meteor_weapon", name = "陨星自动打击", desc = "自动锁定并召下陨石；Lv.2 落地灼烧，Lv.3 增加数量，Lv.4 分裂", baseCost = 2200, costStep = 1200, maxLevel = 4, icon = "陨星", category = "weapon", type = "supportSkill" },
    { id = "lightning_extension", name = "超导分叉", desc = "每级：连锁半径 +20%、目标 +1、直击伤害 +25%", baseCost = 900, costStep = 600, maxLevel = 3, icon = "超导", category = "weapon", requires = "lightning_weapon", requiresName = "雷霆步枪" },
    { id = "plasma_extension", name = "裂变弹头", desc = "每级：Tzar 主炮直击与溅射伤害 +25%；解锁余震重击", baseCost = 1100, costStep = 750, maxLevel = 3, icon = "裂变", category = "weapon", requires = "plasma_weapon", requiresName = "Tzar 重型主炮" },
    { id = "sniper_extension", name = "处决协议", desc = "每级：目标低于 40% 生命时伤害 +35%；解锁延迟打击", baseCost = 1500, costStep = 1000, maxLevel = 3, icon = "处决", category = "sniper", requires = "sniper_weapon", requiresName = "湮灭狙击光束" },
    { id = "barrage_extension", name = "燃烧增压", desc = "每级：炮击与持续燃烧伤害 +25%；解锁燃烧区域", baseCost = 1300, costStep = 850, maxLevel = 3, icon = "增压", category = "barrage", requires = "barrage_weapon", requiresName = "凝固汽油覆盖炮" },
    { id = "shockwave_extension", name = "动能粉碎", desc = "每级：对基础生命不高于 2500 的单位伤害 +30%；解锁范围爆裂", baseCost = 1000, costStep = 700, maxLevel = 3, icon = "粉碎", category = "crowd", requires = "shockwave_weapon", requiresName = "冲击清场炮" },
    { id = "rl_coop_medical_beacon", name = "团队修复信标", desc = "350 范围盟友指挥官在 8 秒内恢复最多 12% 生命；每人冷却 65 秒，消耗 350 电力", baseCost = 1800, costStep = 0, maxLevel = 1, icon = "治疗", category = "support", type = "supportSkill" },
}
-- 本地请求序号：即使玩家在同一游戏帧连续点击，也能生成不同的请求标识。
local requestCounter = 0
-- 向 LuaRules 提交需要绑定当前玩家的操作，例如购买、装备或使用技能。
-- action 是请求类型，itemId 是商品或技能 ID；这里只负责发送，不在 UI 中结算。
local function personalRequest(action, itemId)
	-- 每发送一次请求就递增序号，避免同帧请求使用相同标识。
	requestCounter = requestCounter + 1
	-- 消息格式为“操作:游戏帧-本地序号:目标 ID”。同步 Gadget 会解析并验证请求。
	spSendLuaRulesMsg(action .. ":" .. Spring.GetGameFrame() .. "-" .. requestCounter .. ":" .. itemId)
end

local factionWeaponCatalog = VFS.Include("unitbasedefs/roguelike_weapon_catalog.lua")
-- 阵营专属武器也放进本地商店展示列表；实际价格与购买资格由 Gadget 验证。
for faction, factionConfig in pairs(factionWeaponCatalog.factions) do
	for _, weapon in ipairs(factionConfig.weapons) do
		SHOP_ITEMS[#SHOP_ITEMS + 1] = {
			id = weapon.id,
			name = weapon.name,
			desc = weapon.desc,
			shortfall = weapon.shortfall,
			baseCost = weapon.baseCost,
			costStep = 0,
			maxLevel = 3,
			icon = weapon.icon,
			category = "faction-weapon",
			faction = faction,
			factionLabel = factionConfig.label,
			tags = weapon.tags,
			unlockAt = weapon.unlockAt or 0,
		}
	end
end

local UPGRADE_CARD_COLORS = {
    { icon = "攻击", class = "upgrade-card-attack" },
    { icon = "速度", class = "upgrade-card-move" },
    { icon = "生命", class = "upgrade-card-health" },
    { icon = "射程", class = "upgrade-card-range" },
    { icon = "护甲", class = "upgrade-card-armor" },
    { icon = "护盾", class = "upgrade-card-shield" },
    { icon = "无人机", class = "upgrade-card-drone" },
}

--------------------------------------------------------------------------------
-- 状态

local widgetState = {
    -- RML 对象、本地界面状态及最近一次显示值只在本客户端保存。
    rmlContext    = nil,
    document      = nil,
    dmHandle      = nil,
    upgradeListDrag = nil,
    lastUpdate    = 0,
    -- 当前数据
    wave          = 0,
    kills         = 0,
    atkMult       = "1.00x",
    spdMult       = "1.00x",
    hpMult        = "1.00x",
    rngMult       = "1.00x",
    visMult       = "1.00x",
    armor         = "0.0%",
    atkPercent    = 1,
    spdPercent    = 1,
    hpPercent     = 1,
    rngPercent    = 1,
    visPercent    = 1,
    droneLevel    = 1,
    metal         = 1,
    shield        = "0 / 0",
    phase         = 3,
    -- 升级选择
    upgradeActive = false,
    choiceId      = nil,
    choices       = {},
    banishArmed   = false,
    refreshesRemaining = 2,
    skipsRemaining = 1,
    banishesRemaining = 1,
    -- 商店
    shopOpen      = false,
    lobbyHidden   = false,
    shopRenderSignature = nil,
    shopLayoutCardWidth = 0,
    shopLayoutErrorShown = false,
    shopObservedLevels = {},
    shopPurchasable = {},
    shopEquippable = {},
    shopDisabledReasons = {},
    shopEquipDisabledReasons = {},
    -- 通知
    notifications = {},
    notificationExpires = 0,
    pauseReasons  = { upgrade = false, shop = false },
    pausedByRoguelike = false,
	syncPending = true,
	lastSyncRequestTime = 0,
}

--------------------------------------------------------------------------------
-- 工具函数

local function findCommander()
    -- 根据本地玩家所属队伍寻找指挥官，后续 HUD 从该单位读取 RulesParam。
    local myTeamID = spGetMyTeamID()
    if not myTeamID then return nil end
    local units = spGetTeamUnits(myTeamID)
    for _, uid in ipairs(units) do
        local ud = UnitDefs[spGetUnitDefID(uid)]
        if ud and ud.customParams and ud.customParams.iscommander then
            return uid
        end
    end
    return nil
end

local function formatMult(val)
    return string.format("%.2fx", val)
end

local function percentBar(val, maxVal)
    -- 将倍率相对 1 的增量映射到 0–100%，用于属性条宽度。
    if maxVal <= 0 then return 0 end
    return math.min(math.max((val - 1.0) / maxVal * 100, 0), 100)
end

local function updatePauseState()
    -- 单人选卡或打开商店时请求暂停；Coop 不发送暂停命令。
    if COOP_ENABLED then return end
    local shouldPause = widgetState.pauseReasons.upgrade or widgetState.pauseReasons.shop
    local _, _, isPaused = spGetGameSpeed()
    if shouldPause and not isPaused then
        spSendCommands("pause 1")
        widgetState.pausedByRoguelike = true
    elseif not shouldPause and widgetState.pausedByRoguelike then
        spSendCommands("pause 0")
        widgetState.pausedByRoguelike = false
    end
end

--------------------------------------------------------------------------------
-- DataModel（RmlUi 的数据绑定核心）

local modelData = {
    -- RML 文档绑定的初始展示值；运行时由 dmHandle 写入最新状态。
    wave       = 0,
    kills      = 0,
    atkMult    = "1.00x",
    spdMult    = "1.00x",
    hpMult     = "1.00x",
    rngMult    = "1.00x",
    visMult    = "1.00x",
    armor      = "0.0%",
    atkPercent = 0,
    spdPercent = 0,
    hpPercent  = 0,
    rngPercent = 0,
    visPercent = 0,
    droneLevel = 0,
    metal      = 0,
    shield     = "0 / 0",
    barrier    = "0",
    healBuild    = "偷取 0% | 吸取 0%伤害",
    phaseText  = "准备",
    phaseTime  = 0,
    topPhase = "战斗准备",
    topCountdown = "第 1 波即将开始",
    topUnits = "敌军 0",
    topRoleLevel = "Lv.1/60 · HP+0% · DMG x1.00 · XP 0/22",
    topKills = "击杀 0",
    choices    = {
        [0] = { icon = "", name = "", desc = "" },
        [1] = { icon = "", name = "", desc = "" },
        [2] = { icon = "", name = "", desc = "" },
    },
}

local function setupDataModel(context)
    -- 旧版手工字段绑定方案保留在下方注释中；当前使用 OpenDataModel。
    if not context then
        return nil
    end

    return context:OpenDataModel(MODEL_NAME, modelData, widget)
    -- if context.OpenDataModel then
    --     return context:OpenDataModel(MODEL_NAME, modelData, widget)
    -- end

    -- local dm = nil
    -- if context.CreateDataModel then
    --     dm = context:CreateDataModel(MODEL_NAME)
    -- end
    -- if not dm then
    --     return nil
    -- end

    -- -- 标量绑定
    -- dm:AddField("wave", "int")
    -- dm:AddField("kills", "int")
    -- dm:AddField("atkMult", "string")
    -- dm:AddField("spdMult", "string")
    -- dm:AddField("hpMult", "string")
    -- dm:AddField("rngMult", "string")
    -- dm:AddField("atkPercent", "float")
    -- dm:AddField("spdPercent", "float")
    -- dm:AddField("hpPercent", "float")
    -- dm:AddField("rngPercent", "float")
    -- dm:AddField("droneLevel", "int")
    -- dm:AddField("metal", "int")

    -- -- choices 子模型（3 个选项）
    -- local choiceDm = dm:AddChild("choices")
    -- for i = 0, 2 do
    --     local idx = tostring(i)
    --     choiceDm:AddField(idx .. ".icon", "string")
    --     choiceDm:AddField(idx .. ".name", "string")
    --     choiceDm:AddField(idx .. ".desc", "string")
    -- end

    -- -- 设置初始值
    -- dm:Set("wave", modelData.wave)
    -- dm:Set("kills", modelData.kills)
    -- dm:Set("atkMult", modelData.atkMult)
    -- dm:Set("spdMult", modelData.spdMult)
    -- dm:Set("hpMult", modelData.hpMult)
    -- dm:Set("rngMult", modelData.rngMult)
    -- dm:Set("atkPercent", modelData.atkPercent)
    -- dm:Set("spdPercent", modelData.spdPercent)
    -- dm:Set("hpPercent", modelData.hpPercent)
    -- dm:Set("rngPercent", modelData.rngPercent)
    -- dm:Set("droneLevel", modelData.droneLevel)
    -- dm:Set("metal", modelData.metal)

    -- for i = 0, 2 do
    --     local idx = tostring(i)
    --     choiceDm:Set(idx .. ".icon", "")
    --     choiceDm:Set(idx .. ".name", "")
    --     choiceDm:Set(idx .. ".desc", "")
    -- end

    -- return dm
end

--------------------------------------------------------------------------------
-- UI 操作

local function syncBuildMenuSuppression()
    -- 模态界面开启时通知建造菜单隐藏交互，避免点击穿透。
    local suppressed = widgetState.upgradeActive or widgetState.shopOpen
    if WG.buildmenu and WG.buildmenu.setRoguelikeSuppressed then
        WG.buildmenu.setRoguelikeSuppressed(suppressed)
    end
end

local function makeUpgradeListDraggable(doc)
    -- 鼠标按下时记录面板尺寸和偏移，拖动期间将其限制在视口内。
    local root = doc and doc:GetElementById("owned-upgrades")
    local handle = doc and doc:GetElementById("owned-upgrades-handle")
    if not root or not handle then return nil end

    local drag = { active = false }
    handle:AddEventListener("mousedown", function(event)
        local parameters = event and event.parameters
        if parameters and parameters.button and parameters.button ~= 0 then return end
        local mx, my = Spring.GetMouseState()
        local vsx, vsy = Spring.GetViewGeometry()
        drag.active = true
        drag.offsetX = mx - root.offset_left
        drag.offsetY = (vsy - my) - root.offset_top
        drag.width = root.offset_width
        drag.height = root.offset_height
        drag.viewWidth = vsx
        drag.viewHeight = vsy
        event:StopPropagation()
    end, false)
    doc:AddEventListener("mouseup", function()
        drag.active = false
    end, false)

    -- Keep these as closures instead of methods. LuaUI may invoke callbacks
    -- through wrappers that do not preserve a method receiver; a nil `self`
    -- here raises from Update() and causes the engine to remove the whole HUD.
    drag.tick = function()
        if not drag.active then return end
        local mx, my, _, _, _, offscreen = Spring.GetMouseState()
        if offscreen then return end
        local x = math.max(0, math.min(mx - drag.offsetX, drag.viewWidth - drag.width))
        local y = math.max(0, math.min((drag.viewHeight - my) - drag.offsetY, drag.viewHeight - drag.height))
        root.style.left = math.floor(x) .. "px"
        root.style.top = math.floor(y) .. "px"
    end
    drag.stop = function()
        drag.active = false
    end
    return drag
end

local function showUpgradePanel(choiceId, choices, refreshes, skips, banishes)
    -- 保存 synced 发来的本轮候选及剩余操作次数，并打开选卡遮罩。
    widgetState.upgradeActive = true
    widgetState.choiceId      = choiceId
    widgetState.choices       = choices
    widgetState.banishArmed = false
    if refreshes ~= nil then widgetState.refreshesRemaining = refreshes end
    if skips ~= nil then widgetState.skipsRemaining = skips end
    if banishes ~= nil then widgetState.banishesRemaining = banishes end
    widgetState.pauseReasons.upgrade = true
    updatePauseState()
    syncBuildMenuSuppression()

    -- 更新 DataModel
    local dm = widgetState.dmHandle --

    for i = 0, 2 do
        -- RML 卡位从 0 编号，Lua 候选数组从 1 编号；缺少候选时清空旧内容。
        local c = choices[i + 1]
        local idx = tostring(i)
        if dm and c then
            dm.choices[idx] = {
                icon = c.icon or "",
                name = c.name or "",
                desc = c.desc or "",
            }
        elseif dm then
            dm.choices[idx] = {
                icon = "",
                name = "",
                desc = "",
            }
        end

        local iconElement = widgetState.document:GetElementById("card-icon-" .. idx)
        local nameElement = widgetState.document:GetElementById("card-name-" .. idx)
        local descElement = widgetState.document:GetElementById("card-desc-" .. idx)
        local cardElement = widgetState.document:GetElementById("upgrade-card-" .. idx)
        if iconElement then iconElement.inner_rml = c and (c.icon or "") or "" end
        if nameElement then nameElement.inner_rml = c and (c.name or "") or "" end
        if descElement then descElement.inner_rml = c and (c.desc or "") or "" end
        if cardElement then cardElement:SetClass("hidden", not c) end
        if cardElement then
            -- 根据卡牌图标切换类别配色，避免上轮卡牌样式残留。
            for _, color in ipairs(UPGRADE_CARD_COLORS) do
                cardElement:SetClass(color.class, c ~= nil and c.icon == color.icon)
            end
        end
    end

    local overlay = widgetState.document:GetElementById("upgrade-overlay")
    local refresh = widgetState.document:GetElementById("upgrade-refresh")
    local skip = widgetState.document:GetElementById("upgrade-skip")
    local banish = widgetState.document:GetElementById("upgrade-banish")
    if refresh then refresh.inner_rml = "重抽（" .. widgetState.refreshesRemaining .. "）" end
    if skip then skip.inner_rml = "跳过（" .. widgetState.skipsRemaining .. "）" end
    if banish then banish.inner_rml = "移除候选（" .. widgetState.banishesRemaining .. "）" end
	local subtitle = widgetState.document:GetElementById("upgrade-subtitle")
	if subtitle then subtitle.inner_rml = "角色等级提升生命 +2%、伤害 +1%；属性模块可重复升级" end
    if overlay then
        overlay:SetClass("hidden", false)
    end
end

local function hideUpgradePanel()
    -- 完成选择或跳过后撤销选卡暂停原因并恢复界面可见状态。
    widgetState.upgradeActive = false
    widgetState.pauseReasons.upgrade = false
    updatePauseState()
    syncBuildMenuSuppression()

    local overlay = widgetState.document:GetElementById("upgrade-overlay")
    if overlay then
        overlay:SetClass("hidden", true)
    end
end

local function handlePickUpgrade(index)
	-- UI 只提交服务器发来的 choiceId 与 upgradeId，不发送属性数值；这样即使
	-- 本地数据模型被改动，synced 端也只能接受当前待选列表中的合法卡牌。
    if not widgetState.upgradeActive then return end
    local choice = widgetState.choices[index + 1] -- Lua 1-based → RML 0-based
    if not choice or not choice.id then return end
	if widgetState.banishArmed then
		-- 已进入“移除候选”状态时，点击卡牌改为发送移除请求。
		spSendLuaRulesMsg("roguelike_banish:" .. widgetState.choiceId .. ":" .. choice.id)
		widgetState.banishArmed = false
		local status = widgetState.document:GetElementById("upgrade-action-status")
		if status then status.inner_rml = "已移除此候选并重抽" end
		return
	end

    local msg = "roguelike_pick:" .. widgetState.choiceId .. ":" .. choice.id
    spSendLuaRulesMsg(msg)
    hideUpgradePanel()
end

local handleBuyShopItem
local addNotification

-- 商品节点每次重建后重新绑定点击事件。
local function bindShopItemClicks()
	-- inner_rml 会替换商品节点；每次重建后直接绑定新节点，避免依赖
	-- RmlUi 的事件代理路径和动态节点的冒泡行为。
	local complete = true
	for _, itemId in ipairs(widgetState.shopRenderedItemIds or {}) do
		local boundItemId = itemId
		local card = widgetState.document:GetElementById("shop-item-" .. itemId)
		if card and not widgetState.shopBoundCardIds[itemId] then
			card:AddEventListener("click", function(event)
				if widgetState.shopPurchasable[boundItemId] then
					handleBuyShopItem(boundItemId)
				else
					addNotification(widgetState.shopDisabledReasons[boundItemId] or "当前商品不可购买")
				end
				event:StopPropagation()
			end, false)
			widgetState.shopBoundCardIds[itemId] = true
		elseif not card then
			complete = false
		end
		local equip = widgetState.document:GetElementById("shop-equip-" .. itemId)
		-- 装备按钮单独绑定；阻止事件继续冒泡到商品卡片触发购买。
		if equip and not widgetState.shopBoundEquipIds[itemId] then
			equip:AddEventListener("click", function(event)
				if widgetState.shopEquippable[boundItemId] then
					personalRequest("roguelike_equip", boundItemId)
				else
					addNotification(widgetState.shopEquipDisabledReasons[boundItemId] or "当前武器无法装备")
				end
				event:StopPropagation()
			end, false)
			widgetState.shopBoundEquipIds[itemId] = true
		elseif not equip and widgetState.shopRenderedEquipIds[itemId] then
			complete = false
		end
	end
	widgetState.shopBindingsPending = not complete
end

local function handleShopItemsClick(event)
	-- 节点尚未完成绑定时保留容器级回退；已绑定节点只执行直接监听，
	-- 避免同一次点击提交两笔购买请求。
	local target = event and event.target_element
	while target and target.id ~= "shop-items" do
		-- 从实际点击节点向上寻找商品或装备按钮，兼容点击卡片内的文字。
		local elementId = target.id or ""
		if elementId:sub(1, 11) == "shop-equip-" then
			local itemId = elementId:sub(12)
			if not widgetState.shopBoundEquipIds[itemId] then
				if widgetState.shopEquippable[itemId] then
					personalRequest("roguelike_equip", itemId)
				else
					addNotification(widgetState.shopEquipDisabledReasons[itemId] or "当前武器无法装备")
				end
			end
			event:StopPropagation()
			return
		end
		if elementId:sub(1, 10) == "shop-item-" then
			local itemId = elementId:sub(11)
			if not widgetState.shopBoundCardIds[itemId] then
				if widgetState.shopPurchasable[itemId] then
					handleBuyShopItem(itemId)
				else
					addNotification(widgetState.shopDisabledReasons[itemId] or "当前商品不可购买")
				end
			end
			event:StopPropagation()
			return
		end
		target = target.parent_node
	end
end

local function refreshShopItems()
    -- 根据当前队伍资源、指挥官和购买状态生成三列商品卡片。
    -- 以下禁用状态仅用于展示；synced 端仍会独立校验每个请求。
    local scroll = widgetState.document:GetElementById("shop-scroll")
    if not scroll then return end

    local myTeamID = spGetMyTeamID() -- 获取队伍id
    local metal = 0
    if myTeamID then
        metal = select(1, spGetTeamResources(myTeamID, "metal")) or 0 -- 获取当前队伍金属量
    end

    local commanderID = findCommander()
    local commanderDef = commanderID and UnitDefs[spGetUnitDefID(commanderID)]
    local commanderName = commanderDef and string.lower(commanderDef.name or "") or ""
    -- 用指挥官名称前缀筛选本阵营商品；无法识别时不展示阵营专属武器。
    local faction = commanderName:sub(1, 3) == "arm" and "armada"
        or commanderName:sub(1, 3) == "cor" and "cortex"
        or commanderName:sub(1, 3) == "leg" and "legion"
        or nil
    local upgradeCount = commanderID and (spGetUnitRulesParam(commanderID, "roguelike_upgrade_count") or 0) or 0
    local columnItems = { stats = {}, weapons = {}, faction = {} }
    -- 分别保存三列商品、购买/装备可用状态、禁用原因和最终渲染签名。
    local purchasable = {}
    local equippable = {}
    local disabledReasons = {}
    local equipDisabledReasons = {}
    local signatureParts = {}
    local renderedItemIds = {}
    local renderedEquipIds = {}
    local factionEquippedCount = 0
    -- 已装备的专属武器数量用于决定“装备”按钮是否可用。
    for _, factionConfig in pairs(factionWeaponCatalog.factions) do
        for _, weapon in ipairs(factionConfig.weapons) do
            if commanderID and spGetUnitRulesParam(commanderID, "roguelike_weapon_equipped_" .. weapon.id) == 1 then
                factionEquippedCount = factionEquippedCount + 1
            end
        end
    end
    for _, item in ipairs(SHOP_ITEMS) do
        -- 公共商品对所有阵营可见；专属与原型商品只在对应阵营展示。
        if (not item.faction or item.faction == faction)
            and (not item.prototypeFaction or item.prototypeFaction == faction) then
        renderedItemIds[#renderedItemIds + 1] = item.id
        if item.faction then renderedEquipIds[item.id] = true end
        local factionWeapon = item.faction ~= nil
        local rulesLevel = commanderID
            and (tonumber(spGetUnitRulesParam(commanderID, "roguelike_shop_" .. item.id .. "_level") or 0) or 0)
            or 0
        -- RulesParam 尚未同步到 LuaUI 或受访问范围限制时，暂时以服务器确认结果显示等级。
        local level = math.max(rulesLevel, widgetState.shopObservedLevels[item.id] or 0)
        -- 商品等级影响下次价格、满级提示及是否能装备。
        local cost = factionWeapon and math.floor(item.baseCost * (({ 1, 0.55, 0.85 })[level + 1] or 0) + 0.5)
            or (item.baseCost + item.costStep * level)
        local maxed = level >= item.maxLevel
        local unlockMet = not factionWeapon or upgradeCount >= (item.unlockAt or 0)
        local equipped = factionWeapon and commanderID
            and spGetUnitRulesParam(commanderID, "roguelike_weapon_equipped_" .. item.id) == 1 or false
        local prerequisiteMet = not item.requires
            or (commanderID and (spGetUnitRulesParam(commanderID, "roguelike_shop_" .. item.requires .. "_level") or 0) > 0)
        -- 同时满足前置、累计升级次数、未满级和金属充足才显示为可购买。
        local canAfford = prerequisiteMet and unlockMet and not maxed and metal >= cost
        -- 按解锁、前置、等级和金属顺序生成不可购买原因，供按钮和提示使用。
        disabledReasons[item.id] = not unlockMet and ("需要累计升级 " .. (item.unlockAt or 0) .. " 次")
            or (not prerequisiteMet and ("请先解锁" .. (item.requiresName or "前置武器")))
            or (maxed and "该商品已经满级")
            or (not canAfford and "金属不足")
            or nil
        local disabledClass = canAfford and "" or " disabled"
        local costText = not unlockMet and ("升级 " .. (item.unlockAt or 0) .. " 次解锁")
            or (not prerequisiteMet and ("需要 " .. (item.requiresName or "前置武器")))
            or (maxed and "满级" or tostring(cost))
        purchasable[item.id] = canAfford
        -- 已装备时始终允许卸下；未装备时必须留有专属武器槽位。
        local equipAllowed = factionWeapon and level > 0
            and (equipped or factionEquippedCount < (factionWeaponCatalog.maxEquippedFactionWeapons or 3))
        equippable[item.id] = equipAllowed
        equipDisabledReasons[item.id] = level <= 0 and "先购买这款武器" or "最多同时装备 3 款阵营专属武器"
        local column = factionWeapon and "faction"
            or ((item.category == "damage" or item.category == "health" or item.category == "reload"
                or item.category == "move" or item.category == "range" or item.category == "salvage") and "stats" or "weapons")
        -- 支援技能和阵营武器使用专属标签；阵营商品还显示攻击类型标签。
        local tagsMarkup = item.type == "supportSkill"
            and '<div class="shop-item-tags"><span class="shop-attack-tag">支援技能</span></div>' or ""
        if factionWeapon then
            -- 阵营武器卡片额外显示阵营、拥有/装备状态及装备/卸下按钮。
            local tags = { "<span class=\"shop-faction-tag\">" .. item.factionLabel .. "专属</span>" }
            for _, tag in ipairs(item.tags or {}) do
                tags[#tags + 1] = '<span class="shop-attack-tag">' .. tag .. '</span>'
            end
            tagsMarkup = '<div class="shop-item-tags">' .. table.concat(tags) .. '</div>'
        end
        local weaponStateMarkup = ""
        if factionWeapon then
            local equipText = level == 0 and "购买后可装备" or (equipped and "卸下" or "装备")
            local stateText = level == 0 and "可购买 · " or (equipped and "已装备 · " or "已拥有 · ")
            weaponStateMarkup = string.format(
                '<div class="shop-item-weapon-state">%s%s</div>' ..
                '<div id="shop-equip-%s" class="shop-item-equip%s">%s</div>',
                stateText, item.factionLabel, item.id,
                equipAllowed and "" or " disabled", equipText)
        end
        -- 只在展示状态变化时重建 DOM，避免刷新造成点击丢失。
        signatureParts[#signatureParts + 1] = table.concat({
            item.id,
            tostring(level),
            canAfford and "1" or "0",
            prerequisiteMet and "1" or "0",
            unlockMet and "1" or "0",
            equipped and "1" or "0",
            tostring(cost),
        }, ":")
        columnItems[column][#columnItems[column] + 1] = string.format(
            '<div id="shop-item-%s" class="shop-item shop-%s%s">' ..
            '<div class="shop-item-header"><div class="shop-item-icon">%s</div><div class="shop-item-name">%s</div></div>' ..
            '<div class="shop-item-level">等级 %d/%d</div>%s%s<div class="shop-item-desc">%s</div>' ..
            '<div class="shop-item-shortfall">%s</div><div class="shop-item-footer"><div class="shop-item-cost">%s</div></div></div>',
            item.id, item.category or "default", disabledClass, item.icon, item.name, level, item.maxLevel,
            tagsMarkup, weaponStateMarkup, item.desc, item.shortfall or "", costText
        )
        end
    end
    local function makeSection(title, items)
        -- 每行最多三张卡片，三类商品分别生成独立标题和行容器。
        local markup = { '<div class="shop-section-title">' .. title .. '</div>' }
        for index = 1, #items, 3 do
            markup[#markup + 1] = '<div class="shop-row">'
                .. table.concat(items, "", index, math.min(index + 2, #items)) .. '</div>'
        end
        return table.concat(markup)
    end
    -- 商店暂停期间金属和等级通常不变。只有卡片状态真正变化时才重建 DOM，
    -- 避免鼠标按下与松开之间元素被 inner_rml 替换而丢失 click 事件。
    local renderSignature = table.concat(signatureParts, "|")
    if renderSignature == widgetState.shopRenderSignature then return end
    local scrollTop = scroll.scroll_top or 0
    widgetState.shopRenderSignature = renderSignature
    widgetState.shopPurchasable = purchasable
    widgetState.shopEquippable = equippable
    widgetState.shopDisabledReasons = disabledReasons
    widgetState.shopEquipDisabledReasons = equipDisabledReasons
    local factionConfig = faction and factionWeaponCatalog.factions[faction]
    scroll.inner_rml = makeSection("属性", columnItems.stats)
        .. makeSection("武器", columnItems.weapons)
        .. makeSection("阵营武器 · " .. (factionConfig and factionConfig.label or "未识别"), columnItems.faction)
    scroll.scroll_top = scrollTop
    widgetState.shopLayoutCardWidth = 0
    widgetState.shopRenderedItemIds = renderedItemIds
    widgetState.shopRenderedEquipIds = renderedEquipIds
    widgetState.shopBoundCardIds = {}
    widgetState.shopBoundEquipIds = {}
    widgetState.shopBindingsPending = true
    bindShopItemClicks()
end

local function layoutShopCards()
    -- 用实际滚动区域宽度计算三列卡片宽度，适配窗口缩放和 DPI。
    if not widgetState.shopOpen or not widgetState.document then return end
    local container = widgetState.document:GetElementById("shop-items")
    local containerWidth = container and container.client_width or 0
    if containerWidth < 200 then return end -- hidden documents have no usable layout yet

    local dpRatio = (widgetState.rmlContext and widgetState.rmlContext.dp_ratio) or 1
    local scroll = widgetState.document:GetElementById("shop-scroll")
    if not scroll then return end
    local scrollWidth = math.floor(scroll.client_width or 0)
    if scrollWidth < 200 then return end
    local gap = 10 * dpRatio -- must match .shop-row gap in RCSS
    local cardWidth = math.floor((scrollWidth - 2 * gap - 18 * dpRatio) / 3)
    if cardWidth < 60 then return end
    if widgetState.shopLayoutCardWidth ~= cardWidth then
        local widthStyle = cardWidth .. "px"
        for _, itemId in ipairs(widgetState.shopRenderedItemIds or {}) do
            local card = widgetState.document:GetElementById("shop-item-" .. itemId)
            if card then card.style.width = widthStyle end
        end
        widgetState.shopLayoutCardWidth = cardWidth
    end
end

local function refreshShopItemsSafely()
    -- 防止单次商店渲染异常移除整个 Widget；同一异常只回报一次。
    local ok, err = pcall(refreshShopItems)
    if not ok then
        if not widgetState.shopRenderError then
            Spring.Echo("Roguelike shop render error: " .. tostring(err))
            widgetState.shopRenderError = true
        end
        local overlay = widgetState.document and widgetState.document:GetElementById("shop-overlay")
        if overlay then overlay:SetClass("hidden", not widgetState.shopOpen) end
        return false
    end
    widgetState.shopRenderError = false
    return true
end

local function toggleShop()
    -- 切换商店遮罩，并同步单人暂停与建造菜单输入状态。
    widgetState.shopOpen = not widgetState.shopOpen
    widgetState.pauseReasons.shop = widgetState.shopOpen
    updatePauseState()
    syncBuildMenuSuppression()

    local overlay = widgetState.document:GetElementById("shop-overlay")
    if overlay then
        overlay:SetClass("hidden", not widgetState.shopOpen)
    end

    if widgetState.shopOpen then
        refreshShopItemsSafely()
    end
end

local function handleCloseShop()
    widgetState.shopOpen = false
    widgetState.pauseReasons.shop = false
    updatePauseState()
    syncBuildMenuSuppression()
    local overlay = widgetState.document:GetElementById("shop-overlay")
    if overlay then
        overlay:SetClass("hidden", true)
    end
end

handleBuyShopItem = function(itemId)
    -- UI 只发送商品 ID；是否有钱、是否解锁均由 synced Gadget 判定。
    personalRequest("roguelike_shop", itemId)
end

addNotification = function(text)
    local area = widgetState.document:GetElementById("notification-area")
    if not area then return end

    local notifRml = string.format(
        '<div class="notification">%s</div>', text
    )
    area.inner_rml = notifRml .. (area.inner_rml or "")
    widgetState.notificationExpires = os.clock() + 3
end

--------------------------------------------------------------------------------
-- Widget Callins

function widget:Initialize()
	-- LuaRules unsynced 转发层调用这些 Script.LuaUI 全局函数，把一次性事件
	-- 送入当前玩家的 RML；它们不是 synced API，也不会在其他客户端执行。
    -- 获取共享 Context
    widgetState.rmlContext = RmlUi.GetContext("shared")
	if not widgetState.rmlContext then
		return false
	end

	local dm = widgetState.rmlContext:OpenDataModel(MODEL_NAME, modelData, self)
	-- 数据模型必须先创建，随后加载的 RML 文档才能绑定字段。
	if not dm then
		return false
	end
	widgetState.dmHandle = dm
	WG.RoguelikeRmlActive = true

    widgetHandler:RegisterGlobal("RoguelikeShowChoices", function(choiceId, choicesStr, refreshes, skips, banishes)
        widget:RoguelikeShowChoices(choiceId, choicesStr, refreshes, skips, banishes)
        return true
    end)
    widgetHandler:RegisterGlobal("RoguelikeUpgradeNotification", function(name, desc)
        widget:RoguelikeUpgradeNotification(name, desc)
        return true
    end)
    widgetHandler:RegisterGlobal("RoguelikeUpgradeList", function(list)
        widget:RoguelikeUpgradeList(list)
        return true
    end)
    widgetHandler:RegisterGlobal("RoguelikeShopResult", function(success, itemId, name, level, cost, reason)
        widget:RoguelikeShopResult(success, itemId, name, level, cost, reason)
        return true
    end)
    widgetHandler:RegisterGlobal("RoguelikeSkillResult", function(success, skillID, cooldownFrame, reason)
        widget:RoguelikeSkillResult(success, skillID, cooldownFrame, reason)
        return true
    end)
    widgetHandler:RegisterGlobal("RoguelikeWaveStart", function(wave)
        widget:RoguelikeWaveStart(wave)
        return true
    end)
    widgetHandler:RegisterGlobal("RoguelikeWaveCleared", function(wave)
        widget:RoguelikeWaveCleared(wave)
        return true
    end)
    widgetHandler:RegisterGlobal("RoguelikeSuicideWarning", function(wave, unitName)
        widget:RoguelikeSuicideWarning(wave, unitName)
        return true
    end)

    -- 加载 RML 文档
    widgetState.document = widgetState.rmlContext:LoadDocument(RML_PATH, self)
    if not widgetState.document then
        Spring.Echo("Roguelike RML: Failed to load " .. RML_PATH)
        widgetHandler:RemoveWidget(self)
        return
    end

    widgetState.document:Show()
    widgetState.document:ReloadStyleSheet()
    widgetState.upgradeListDrag = makeUpgradeListDraggable(widgetState.document)
	-- A LuaUI reload or reconnect loses local events, not synced ownership. Ask
	-- the authoritative gadget for the current list and any pending card offer.
	spSendLuaRulesMsg("roguelike_sync")
	widgetState.lastSyncRequestTime = os.clock()

    for index = 0, 2 do
        -- 将三张卡片分别映射到 Lua 下标为 1–3 的候选。
        local cardIndex = index
        local card = widgetState.document:GetElementById("upgrade-card-" .. cardIndex)
        if card then
            card:AddEventListener("click", function(event)
                handlePickUpgrade(cardIndex)
                event:StopPropagation()
            end, false)
        end
    end
    local refreshButton = widgetState.document:GetElementById("upgrade-refresh")
    -- 重抽和跳过携带当前 choiceId；移除按钮先等待玩家指定卡牌。
    if refreshButton then refreshButton:AddEventListener("click", function(event)
        if widgetState.upgradeActive and widgetState.refreshesRemaining > 0 then
            spSendLuaRulesMsg("roguelike_refresh:" .. widgetState.choiceId)
        end
        event:StopPropagation()
    end, false) end
    local skipButton = widgetState.document:GetElementById("upgrade-skip")
    if skipButton then skipButton:AddEventListener("click", function(event)
        if widgetState.upgradeActive and widgetState.skipsRemaining > 0 then
            spSendLuaRulesMsg("roguelike_skip:" .. widgetState.choiceId)
            hideUpgradePanel()
        end
        event:StopPropagation()
    end, false) end
    local banishButton = widgetState.document:GetElementById("upgrade-banish")
    if banishButton then banishButton:AddEventListener("click", function(event)
        if widgetState.upgradeActive and widgetState.banishesRemaining > 0 then
            widgetState.banishArmed = true
            local status = widgetState.document:GetElementById("upgrade-action-status")
            if status then status.inner_rml = "点击要移除的卡片" end
        end
        event:StopPropagation()
    end, false) end
    local shopClose = widgetState.document:GetElementById("shop-close")
    if shopClose then
        shopClose:AddEventListener("click", function(event)
            handleCloseShop()
            event:StopPropagation()
        end, false)
    end
    local shopItems = widgetState.document:GetElementById("shop-items")
    if shopItems then
        shopItems:AddEventListener("click", handleShopItemsClick, false)
    end
    local skillActions = { "nanorepair", "thruster", "faction", "medical_beacon" }
    -- 技能按钮通过个人请求通道提交动作，冷却/资源限制由同步逻辑处理。
    for _, skillID in ipairs(skillActions) do
        local button = widgetState.document:GetElementById("skill-" .. skillID)
        if button then
            button:AddEventListener("click", function(event)
                personalRequest("roguelike_skill", skillID)
                event:StopPropagation()
            end, false)
        end
    end
    local test = widgetState.document:GetElementById("roguelike-hud")
    if not test then
        Spring.Echo("Roguelike Test".. test)
    end
    -- RML 初始 class 与本地状态必须一致；升级和商店都由玩家操作开启。
    local upgradeOverlay = widgetState.document:GetElementById("upgrade-overlay")
    if upgradeOverlay then upgradeOverlay:SetClass("hidden", true) end
    local shopOverlay = widgetState.document:GetElementById("shop-overlay")
    if shopOverlay then shopOverlay:SetClass("hidden", true) end
    return true
end

-- 接收 Gadget 通过 Script.LuaUI 发送的事件
function widget:RoguelikeShowChoices(choiceId, choicesStr, refreshes, skips, banishes)
    -- synced 端把候选编码为“候选;候选”，每项包含 ID、名称、描述和图标。
    local choices = {}
    for choiceStr in choicesStr:gmatch("([^;]+)") do
        local parts = {}
        for part in choiceStr:gmatch("([^|]+)") do
            parts[#parts + 1] = part
        end
        if #parts >= 4 then
            choices[#choices + 1] = {
                id   = parts[1],
                name = parts[2],
                desc = parts[3],
                icon = parts[4],
            }
        end
    end
    showUpgradePanel(choiceId, choices, refreshes, skips, banishes)
end

local function escapeRmlText(value)
    -- 将名称/描述中的特殊字符转义，避免插入 inner_rml 时被当作标签。
    return tostring(value or ""):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
end

function widget:RoguelikeUpgradeList(list)
    -- 同步已拥有升级列表，刷新浮动面板；这是断线/重载后恢复显示的依据。
    local content = widgetState.document and widgetState.document:GetElementById("owned-upgrades-content")
    if not content then return end
	widgetState.syncPending = false

    local rows = {}
    for row in tostring(list or ""):gmatch("[^;]+") do
        local name, desc, level = row:match("^(.-)|(.-)|(%d+)$")
        if name then
            local suffix = " ×" .. level
            rows[#rows + 1] = string.format(
                '<div class="owned-upgrade"><div class="owned-upgrade-name">%s%s</div><div class="owned-upgrade-desc">%s</div></div>',
                escapeRmlText(name), suffix, escapeRmlText(desc)
            )
        end
    end
    if #rows == 0 then
        content.inner_rml = '<div class="owned-upgrades-empty">尚无已升级选项</div>'
    else
        content.inner_rml = table.concat(rows)
    end
end

function widget:RoguelikeUpgradeNotification(name, desc)
    addNotification("升级完成：" .. name .. (desc and ("｜" .. desc) or ""))
end

function widget:RoguelikeShopResult(success, itemId, name, level, cost, reason)
    -- 用服务器确认结果更新本地提示；购买成功等级先缓存到 RulesParam 可见为止。
    if tonumber(success) == 1 then
		widgetState.shopObservedLevels[itemId] = math.max(
			widgetState.shopObservedLevels[itemId] or 0, tonumber(level) or 0)
		if reason == "equipped" then
			addNotification("已装备：" .. name)
		elseif reason == "unequipped" then
			addNotification("已卸下：" .. name)
		elseif reason == "purchased_unarmed" then
			addNotification(string.format("购买成功：%s 等级 %d；装备槽已满，请先卸下一款", name, tonumber(level) or 0))
		else
			addNotification(string.format("购买成功：%s 等级 %d", name, tonumber(level) or 0))
		end
    elseif reason == "not_enough_metal" then
        addNotification("购买失败：金属不足")
    elseif reason == "max_level" then
        addNotification("购买失败：已经达到最高等级")
    elseif reason == "weapon_unavailable" then
        addNotification("购买失败：当前指挥官不支持这个武器槽")
    elseif reason == "requires_weapon" then
        addNotification("购买失败：请先解锁对应武器")
	elseif reason == "wrong_faction" then
		addNotification("购买失败：该武器不属于当前阵营")
	elseif reason == "locked" then
		addNotification("购买失败：升级次数不足，尚未解锁")
	elseif reason == "equip_limit" then
		addNotification("装备失败：最多同时装备 3 款阵营专属武器")
	elseif reason == "not_owned" then
		addNotification("装备失败：请先购买这款武器")
    elseif reason == "not_recovery" then
        addNotification("购买失败：商店只在休整阶段开放")
    else
        addNotification("购买失败：无法完成购买")
    end
    if widgetState.shopOpen then
        refreshShopItemsSafely()
    end
end

function widget:RoguelikeSkillResult(success, skillID, cooldownFrame, reason)
    -- 把权威技能结果与失败原因映射为玩家可读的本地通知。
	local labels = {
		nanorepair = "紧急纳米修复", thruster = "应急推进", photon_guard = "光子缓冲",
		bastion = "重装强固", repair_link = "纳米协同修复", medical_beacon = "治疗信标",
	}
	if success then
		addNotification((labels[skillID] or skillID) .. "已启动")
		return
	end
	local reasons = {
		cooldown = "技能仍在冷却", full_health = "生命值已满", no_target = "范围内没有受伤的盟友指挥官",
		not_enough_energy = "电力不足", not_owned = "请先在商店解锁治疗信标",
		same_skill_active = "同类团队治疗效果已在生效", wrong_faction = "当前阵营不能使用此技能",
		commander_unavailable = "指挥官当前不可用",
	}
	addNotification((labels[skillID] or skillID) .. "未能启动：" .. (reasons[reason] or "请求无效"))
end

function widget:RoguelikeWaveStart(wave)
    addNotification("第 " .. wave .. " 波敌人来袭！")
end

function widget:RoguelikeWaveCleared(wave)
    addNotification("进入第 " .. ((tonumber(wave) or 0) + 1) .. " 波！恢复 10% 最大生命，敌人持续刷新")
end

function widget:RoguelikeSuicideWarning(wave, unitName)
    local labels = {
        legkam = "高速 Martyr 自爆机",
        armvader = "Arm T2 爬行炸弹",
        corroach = "Cortex T2 爬行炸弹",
        corsktl = "Skuttle T2 爬行炸弹",
        legsnapper = "Legion T2 爬行炸弹",
    }
    addNotification(string.format("危险目标：%s 已出现（第 %d 波）", labels[unitName] or unitName, tonumber(wave) or 0))
end

-- 定期刷新 HUD 数据
local function optionsDialogOpen()
    -- 大厅覆盖层、隐藏 GUI 或选项面板打开时暂时隐藏肉鸽界面。
    return widgetState.lobbyHidden
        or (Spring.IsGUIHidden and Spring.IsGUIHidden())
        or (WG.options and WG.options.isvisible and WG.options.isvisible()) or false
end

local function isPointOverUpgradeList(x, y)
    -- Spring 鼠标坐标从屏幕下方起算；RML 顶边偏移需按视口高度换算。
    local doc = widgetState.document
    local element = doc and doc:GetElementById("owned-upgrades")
    if not element or optionsDialogOpen() then return false end
    local _, viewHeight = Spring.GetViewGeometry()
    local left = element.offset_left
    local top = viewHeight - element.offset_top
    return x >= left and x <= left + element.offset_width
        and y >= top - element.offset_height and y <= top
end

local function syncOptionsVisibility()
    -- 逐个更新 HUD、卡牌、商店等节点的 hidden 类，保留原有打开状态。
    local optionsOpen = optionsDialogOpen()
    local doc = widgetState.document
    if not doc then return end

    local elements = {
        "wave-status", "roguelike-hud", "survival-skill-bar", "upgrade-overlay",
        "shop-overlay", "notification-area", "owned-upgrades",
    }
    for _, id in ipairs(elements) do
        local element = doc:GetElementById(id)
        local shouldHide = optionsOpen or (id == "upgrade-overlay" and not widgetState.upgradeActive) or (id == "shop-overlay" and not widgetState.shopOpen)
        if element then element:SetClass("hidden", shouldHide) end
    end
end
function widget:Update(dt)
    -- 每帧处理动态节点事件绑定、布局和拖动；较重的数据读取按间隔执行。
    if widgetState.shopBindingsPending and widgetState.document then
        bindShopItemClicks()
    end
    local shopLayoutOK, shopLayoutError = pcall(layoutShopCards)
    if not shopLayoutOK and not widgetState.shopLayoutErrorShown then
        local safeError = tostring(shopLayoutError):gsub("[%c]", " ")
        Spring.Echo("Roguelike shop layout error: " .. string.sub(safeError, 1, 180))
        widgetState.shopLayoutErrorShown = true
    end
    syncOptionsVisibility()
    syncBuildMenuSuppression()
    if optionsDialogOpen() and widgetState.upgradeListDrag then
        widgetState.upgradeListDrag.stop()
    end
    if widgetState.upgradeListDrag then widgetState.upgradeListDrag.tick() end
    local now = os.clock()
	if widgetState.syncPending and now - widgetState.lastSyncRequestTime >= 3 then
		-- 重载后尚未收到完整同步结果时，每三秒重发一次状态请求。
		spSendLuaRulesMsg("roguelike_sync")
		widgetState.lastSyncRequestTime = now
	end
    if now - widgetState.lastUpdate < UPDATE_INTERVAL then --
        return
    end
    widgetState.lastUpdate = now

    local dm = widgetState.dmHandle
    local doc = widgetState.document
    if not dm or not doc then return end

    if widgetState.notificationExpires > 0 and now >= widgetState.notificationExpires then
        local area = doc:GetElementById("notification-area")
        if area then area.inner_rml = "" end
        widgetState.notificationExpires = 0
    end

    local comID = findCommander()
    if not comID then return end

    -- 波次、属性、护盾和阶段都从当前指挥官的 UnitRulesParam 读取。
    -- 这些值由 synced Gadget 写入，此处只格式化与展示。
    local wave       = spGetUnitRulesParam(comID, "roguelike_wave") or 0
    local kills      = spGetUnitRulesParam(comID, "roguelike_kills") or 0
    local atkMult    = spGetUnitRulesParam(comID, "roguelike_reload_mult") or 1.0
    local spdMult    = spGetUnitRulesParam(comID, "roguelike_move_mult") or 1.0
    local hpMult     = spGetUnitRulesParam(comID, "roguelike_health_mult") or 1.0
    local rngMult    = spGetUnitRulesParam(comID, "roguelike_range_mult") or 1.0
    local visMult    = spGetUnitRulesParam(comID, "roguelike_sight_mult") or 1.0
    local armorReduction = spGetUnitRulesParam(comID, "roguelike_armor_reduction") or 0
    local droneLevel = spGetUnitRulesParam(comID, "roguelike_drone_level") or 0
    local shieldCurrent = spGetUnitRulesParam(comID, "roguelike_shield_current") or 0
    local shieldCapacity = spGetUnitRulesParam(comID, "roguelike_shield_capacity") or 0
    local barrierCurrent = spGetUnitRulesParam(comID, "roguelike_barrier_current") or 0
    local phase = spGetUnitRulesParam(comID, "roguelike_phase") or 3
    local phaseTime = spGetUnitRulesParam(comID, "roguelike_phase_time") or 0
    local enemiesAlive = spGetUnitRulesParam(comID, "roguelike_enemies_alive") or 0
    local frame = spGetGameFrame()

    local myTeamID = spGetMyTeamID()
    local metal = 0
    if myTeamID then
        metal = select(1, spGetTeamResources(myTeamID, "metal")) or 0
    end

    -- 更新 DataModel
    dm.wave = wave
    dm.kills = kills
    dm.atkMult = formatMult(atkMult)
    dm.spdMult = formatMult(spdMult)
    dm.hpMult = formatMult(hpMult)
    dm.rngMult = formatMult(rngMult)
    dm.visMult = formatMult(visMult)
    dm.armor = string.format("%.1f%%", armorReduction * 100)
    dm.atkPercent = percentBar(atkMult, 2.0) .. "%"
    dm.spdPercent = percentBar(spdMult, 2.0) .. "%"
    dm.hpPercent = percentBar(hpMult, 2.5) .. "%"
    dm.rngPercent = percentBar(rngMult, 1.5) .. "%"
    dm.visPercent = percentBar(visMult, 1.5) .. "%"
    dm.droneLevel = droneLevel
    dm.metal = math.floor(metal)
    dm.shield = string.format("%d / %d", math.floor(shieldCurrent), math.floor(shieldCapacity))
    dm.barrier = string.format("%d", math.floor(barrierCurrent))
    local stealChance = tonumber(spGetUnitRulesParam(comID, "roguelike_lifesteal_chance") or 0) or 0
    local damageSteal = tonumber(spGetUnitRulesParam(comID, "roguelike_damage_lifesteal") or 0) or 0
    dm.healBuild = string.format("偷取 %.0f%% | 吸取 %.0f%%伤害", stealChance * 100, damageSteal * 100)
	local unitDef = UnitDefs[spGetUnitDefID(comID)]
	local commanderName = unitDef and string.lower(unitDef.name or "") or ""
	-- 根据指挥官阵营选择技能名称和对应冷却状态。
	local factionSkill = commanderName:sub(1, 3) == "arm" and "photon_guard"
		or commanderName:sub(1, 3) == "cor" and "bastion"
		or commanderName:sub(1, 3) == "leg" and "repair_link" or nil
	local skillNames = { photon_guard = "光子缓冲", bastion = "重装强固", repair_link = "纳米协同修复" }
	local factionName = doc:GetElementById("skill-faction-name")
	if factionName then factionName.inner_rml = skillNames[factionSkill] or "阵营技能" end
	local function updateSkillStatus(skillID, activeParam, activeLabel)
		-- 冷却以游戏帧保存，显示时换算为秒；生效中的技能优先显示状态。
		local button = doc:GetElementById("skill-" .. skillID)
		local status = doc:GetElementById("skill-status-" .. skillID)
		if not button or not status then return end
		local cd = tonumber(spGetUnitRulesParam(comID, "roguelike_skill_cd_" .. skillID) or 0) or 0
		local active = activeParam and (tonumber(spGetUnitRulesParam(comID, activeParam) or 0) or 0) > frame
		local remaining = math.max(0, math.ceil((cd - frame) / (Game.gameSpeed or 30)))
		status.inner_rml = active and activeLabel or (remaining > 0 and ("冷却 " .. remaining .. " 秒") or "就绪")
		button:SetClass("disabled", remaining > 0)
	end
	updateSkillStatus("nanorepair", "roguelike_skill_active_nanorepair", "修复中")
	updateSkillStatus("thruster", "roguelike_skill_active_thruster", "推进中")
	updateSkillStatus("medical_beacon", nil, "已解锁")
	local beaconStatus = doc:GetElementById("skill-status-medical_beacon")
	local beaconButton = doc:GetElementById("skill-medical_beacon")
	local beaconOwned = (tonumber(spGetUnitRulesParam(comID, "roguelike_shop_rl_coop_medical_beacon_level") or 0) or 0) > 0
	local beaconCooldown = tonumber(spGetUnitRulesParam(comID, "roguelike_skill_cd_medical_beacon") or 0) or 0
	if beaconStatus and not beaconOwned then beaconStatus.inner_rml = "未解锁" end
	if beaconButton then beaconButton:SetClass("disabled", not beaconOwned or beaconCooldown > frame) end
	local factionStatus = doc:GetElementById("skill-status-faction")
	local factionButton = doc:GetElementById("skill-faction")
	if factionStatus then
		local cd = factionSkill and (tonumber(spGetUnitRulesParam(comID, "roguelike_skill_cd_" .. factionSkill) or 0) or 0) or 0
		local activeParam = factionSkill == "photon_guard" and "roguelike_barrier_expiry"
			or factionSkill == "bastion" and "roguelike_bastion_expiry"
			or factionSkill == "repair_link" and "roguelike_repair_link_expiry"
		local active = activeParam and (tonumber(spGetUnitRulesParam(comID, activeParam) or 0) or 0) > frame
		local remaining = math.max(0, math.ceil((cd - frame) / (Game.gameSpeed or 30)))
		factionStatus.inner_rml = active and "生效中" or (remaining > 0 and ("冷却 " .. remaining .. " 秒") or "就绪")
		if factionButton then factionButton:SetClass("disabled", remaining > 0) end
	end
    local phaseNames = { [1] = "持续作战", [3] = "开局准备" }
    dm.phaseText = phaseNames[phase] or "准备"
    dm.phaseTime = math.max(0, math.floor(phaseTime))
    -- phase_time 和 enemies_alive 均由 synced Spawner 写入；
    -- LuaUI 只负责格式化显示，不自行推算权威波次进度。
    if phase == 1 then
        dm.topPhase = string.format("第 %d 波", wave)
        dm.topCountdown = string.format("战斗剩余 %d 秒", math.max(0, math.floor(phaseTime)))
    else
        dm.topPhase = "战斗准备"
        dm.topCountdown = string.format("第 1 波将在 %d 秒后开始", math.max(0, math.floor(phaseTime)))
    end
    dm.topUnits = string.format("敌军 %d", math.max(0, math.floor(enemiesAlive)))
    local roleLevel = comID and (spGetUnitRulesParam(comID, "roguelike_level") or 1) or 1
    -- 角色经验与伤害倍率用于顶栏；达到等级上限时显示 MAX。
    local roleLevelMax = comID and (spGetUnitRulesParam(comID, "roguelike_level_max") or 60) or 60
    local roleXP = comID and (spGetUnitRulesParam(comID, "roguelike_role_xp") or 0) or 0
    local nextRoleXP = comID and (spGetUnitRulesParam(comID, "roguelike_role_next_xp") or -1) or -1
    local damageMult = comID and (spGetUnitRulesParam(comID, "roguelike_damage_mult") or 1) or 1
    local roleHealthBonus = math.max(0, roleLevel - 1) * 1.2
    dm.topRoleLevel = nextRoleXP > 0
        and string.format("Lv.%d/%d · HP+%.1f%% · DMG x%.2f · XP %d/%d", math.floor(roleLevel),
            math.floor(roleLevelMax), roleHealthBonus, damageMult, math.floor(roleXP), math.floor(nextRoleXP))
        or string.format("Lv.%d/%d · HP+%.1f%% · DMG x%.2f · MAX", math.floor(roleLevel),
            math.floor(roleLevelMax), roleHealthBonus, damageMult)
    dm.topKills = string.format("击杀 %d", math.max(0, math.floor(kills)))
    widgetState.phase = phase

    local barValues = {
        -- 属性条使用与文字倍率相同的 RulesParam，避免两处显示不一致。
        atk = percentBar(atkMult, 2.0),
        spd = percentBar(spdMult, 2.0),
        hp = percentBar(hpMult, 2.5),
        rng = percentBar(rngMult, 1.5),
        vis = percentBar(visMult, 1.5),
    }
    for barName, width in pairs(barValues) do
        local bar = doc:GetElementById(barName .. "-bar-fill")
        if bar then
            bar:SetAttribute("style", string.format("width: %.1f%%;", width))
        end
    end
    local metalElement = doc:GetElementById("shop-metal")
    if metalElement then
        metalElement.inner_rml = "金属：" .. math.floor(metal)
    end

    -- 商店打开时刷新
    if widgetState.shopOpen then
        refreshShopItemsSafely()
    end
end

-- 键盘
function widget:KeyPress(key, mods, isRepeat)
    -- 1/2/3 选择卡牌，F1 切换商店，Esc 关闭商店。
    if optionsDialogOpen() then return false end
    if widgetState.upgradeActive then
        if key == 49 then handlePickUpgrade(0); return true end  -- 1
        if key == 50 then handlePickUpgrade(1); return true end  -- 2
        if key == 51 then handlePickUpgrade(2); return true end  -- 3
    end
    if key == 282 then  -- F1 或自定义键
        toggleShop()
        return true
    end
    if key == 27 and widgetState.shopOpen then  -- Esc
        handleCloseShop()
        return true
    end
    return false
end

-- 商店和升级选择都是模态界面。RmlUi 继续接收并处理卡片点击与列表滚动，
-- 这些 Call-in 返回 true 只负责阻止同一输入继续穿透到选单位和镜头控制。
function widget:IsAbove(x, y)
    if optionsDialogOpen() then return false end
    return widgetState.shopOpen or widgetState.upgradeActive or isPointOverUpgradeList(x, y)
end

function widget:MousePress(x, y, button)
    if optionsDialogOpen() then return false end
    return widgetState.shopOpen or widgetState.upgradeActive or isPointOverUpgradeList(x, y)
end

function widget:MouseMove(x, y, dx, dy, button)
    if optionsDialogOpen() then return false end
    return (widgetState.upgradeListDrag and widgetState.upgradeListDrag.active)
        or widgetState.shopOpen or widgetState.upgradeActive or isPointOverUpgradeList(x, y)
end

function widget:MouseRelease(x, y, button)
    if optionsDialogOpen() then return false end
    if widgetState.upgradeListDrag and widgetState.upgradeListDrag.active then
        widgetState.upgradeListDrag.stop()
        return true
    end
    return widgetState.shopOpen or widgetState.upgradeActive or isPointOverUpgradeList(x, y)
end

function widget:MouseWheel(up, value)
    if optionsDialogOpen() then return false end
    local x, y = Spring.GetMouseState()
    return widgetState.shopOpen or widgetState.upgradeActive or isPointOverUpgradeList(x, y)
end

function widget:Shutdown()
	-- 卸载时撤销输入隔离和本地暂停，并解除所有全局回调及 RML 对象。
	widgetState.upgradeActive = false
	widgetState.shopOpen = false
	syncBuildMenuSuppression()
	widgetState.pauseReasons.upgrade = false
	widgetState.pauseReasons.shop = false
	updatePauseState()
	WG.RoguelikeRmlActive = nil
    widgetHandler:DeregisterGlobal("RoguelikeShowChoices")
    widgetHandler:DeregisterGlobal("RoguelikeUpgradeNotification")
    widgetHandler:DeregisterGlobal("RoguelikeUpgradeList")
    widgetHandler:DeregisterGlobal("RoguelikeShopResult")
    widgetHandler:DeregisterGlobal("RoguelikeSkillResult")
    widgetHandler:DeregisterGlobal("RoguelikeWaveStart")
    widgetHandler:DeregisterGlobal("RoguelikeWaveCleared")
    widgetHandler:DeregisterGlobal("RoguelikeSuicideWarning")
    if widgetState.rmlContext and widgetState.dmHandle then
        widgetState.rmlContext:RemoveDataModel(MODEL_NAME)
        widgetState.dmHandle = nil
    end
    if widgetState.document then
        widgetState.document:Close()
        widgetState.document = nil
    end
    widgetState.rmlContext = nil
end

-- Chobby 房间/设置覆盖层出现时隐藏整份 RML 文档，避免遮挡房间控件；
-- 返回游戏时恢复文档，并重新同步各界面的可见状态。
function widget:RecvLuaMsg(message, playerID)
    if type(message) ~= "string" or not widgetState.document then return false end
    if message:sub(1, 19) == "LobbyOverlayActive1" then
        widgetState.lobbyHidden = true
        widgetState.document:Hide()
        return false
    elseif message:sub(1, 19) == "LobbyOverlayActive0" then
        widgetState.lobbyHidden = false
        widgetState.document:Show()
        syncOptionsVisibility()
        return false
    end
    return false
end
