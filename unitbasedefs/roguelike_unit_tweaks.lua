-- Roguelike-only corcom weapons. Applied to PVE's corcom UnitDef only when the mode is enabled.
local rogueWeapons = {
  weapondefs = {
    rogue_lightning = {
				areaofeffect = 8,
				avoidfeature = false,
				beamttl = 1,
				burst = 10,
				burstrate = 0.03333,
				craterareaofeffect = 0,
				craterboost = 0,
				cratermult = 0,
				duration = 1,
				edgeeffectiveness = 0.15,
				energypershot = 10,
				explosiongenerator = "custom:genericshellexplosion-medium-lightning2",
				firestarter = 50,
				impactonly = 1,
				impulsefactor = 0,
				intensity = 24,
				laserflaresize = 5,
				name = "雷霆步枪",
				noselfdamage = true,
				range = 280,
				reloadtime = 1.7,
				rgbcolor = "0.5 0.5 1",
				soundhit = "xplomed3",
				soundhitwet = "sizzle",
				soundstart = "lghthvy1",
				soundtrigger = true,
				thickness = 1.5,
				turret = true,
				weapontype = "LightningCannon",
				weaponvelocity = 400,
				customparams = {
					spark_ceg = "genericshellexplosion-splash-lightning",
					spark_forkdamage = "0.33",
					spark_maxunits = "2",
					spark_range = "90",
					roguelike_shop_item = "lightning_weapon",
					weapons_group = 4,
				},
				damage = {
					default = 22,
				},
			},
    rogue_plasma = {
				areaofeffect = 72,
				avoidfeature = false,
				craterareaofeffect = 72,
				craterboost = 0,
				cratermult = 0,
				edgeeffectiveness = 0.15,
				explosiongenerator = "custom:genericshellexplosion-small",
				gravityaffected = "true",
				impulsefactor = 0.123,
				name = "远程等离子炮",
				noselfdamage = true,
				range = 650,
				reloadtime = 3.3,
				soundhit = "xplomed2",
				soundhitwet = "splssml",
				soundstart = "cannon1",
				turret = true,
				weapontype = "Cannon",
				weaponvelocity = 340,
				customparams = {
					roguelike_shop_item = "plasma_weapon",
					weapons_group = 5,
				},
				damage = {
					default = 255,
					vtol = 35,
				},
			},
    rogue_sniper = {
				areaofeffect = 24,
				avoidfeature = false,
				beamtime = 0.45,
				corethickness = 0.35,
				craterareaofeffect = 24,
				craterboost = 0,
				cratermult = 0,
				edgeeffectiveness = 0.15,
				energypershot = 250,
				explosiongenerator = "custom:genericshellexplosion-medium-beam",
				firestarter = 35,
				impulsefactor = 0,
				laserflaresize = 8.25,
				name = "湮灭狙击光束",
				noselfdamage = true,
				proximitypriority = -1,
				range = 900,
				reloadtime = 4,
				rgbcolor = "0.2 0.85 1.0",
				rgbcolor2 = "0.95 1.0 0.85",
				soundhitdry = "",
				soundhitwet = "sizzle",
				soundstart = "heatray2",
				soundtrigger = 1,
				thickness = 5,
				tolerance = 10000,
				turret = true,
				weapontype = "BeamLaser",
				weaponvelocity = 1500,
				customparams = {
					roguelike_shop_item = "sniper_weapon",
					weapons_group = 6,
				},
				damage = {
					default = 1800,
					vtol = 900,
				},
			},
    rogue_barrage = {
				burst = 6,
				burstrate = 0.15,
				areaofeffect = 150,
				avoidfeature = false,
				cegtag = "burnflame-xs",
				collidefriendly = false,
				craterareaofeffect = 90,
				craterboost = 0,
				cratermult = 0,
				edgeeffectiveness = 0.15,
				explosiongenerator = "custom:fire-explosion-small",
				flamegfxtime = 1,
				gravityaffected = "true",
				impulsefactor = 0.123,
				leadlimit = 0,
				mygravity = 0.08,
				name = "凝固汽油覆盖炮",
				noselfdamage = true,
				range = 1100,
				reloadtime = 6,
				rgbcolor = "1 0.35 0.1",
				size = 6,
				soundhitdry = "flamhit1",
				soundhitwet = "sizzle",
				soundstart = "cannhvy2",
				sprayangle = 1500,
				turret = true,
				weapontype = "Cannon",
				weaponvelocity = 400,
				customparams = {
					area_onhit_ceg = "fire-area-75-repeat",
					area_onhit_damageCeg = "burnflamexl-gen",
					area_onhit_resistance = "fire",
					area_onhit_damage = 110,
					area_onhit_range = 75,
					area_onhit_time = 7,
					roguelike_shop_item = "barrage_weapon",
					weapons_group = 7,
				},
				damage = {
					default = 170,
					subs = 40,
					vtol = 40,
				},
			},
    rogue_shockwave = {
				alphadecay = 0.1,
				areaofeffect = 144,
				avoidfeature = false,
				burnblow = true,
				cegtag = "impulse-trail",
				craterboost = 0,
				cratermult = 0,
				edgeeffectiveness = 0.9,
				explosiongenerator = "custom:genericshellexplosion-medium",
				flighttime = 0.534,
				gravityaffected = "true",
				heightboostfactor = 0,
				heightmod = 1,
				impulsefactor = 1.8,
				name = "冲击清场炮",
				nogap = false,
				noselfdamage = true,
				range = 315,
				reloadtime = 1.3,
				separation = 2,
				sizedecay = 0.08,
				soundhit = "corlevlrhit",
				soundhitvolume = 11.5,
				soundhitwet = "splsmed",
				soundstart = "corlevlr",
				soundstartvolume = 13,
				stages = 12,
				turret = true,
				weapontype = "Cannon",
				weaponvelocity = 540,
				customparams = {
					roguelike_shop_item = "shockwave_weapon",
					weapons_group = 8,
				},
				damage = {
					default = 340,
					subs = 70,
					vtol = 27,
				},
			},
  },
  weapons = {
    [4] = { def = "CORCOMLASER", onlytargetcategory = "NOTSUB", fastautoretargeting = true },
    [5] = {
				def = "ROGUE_LIGHTNING",
				onlytargetcategory = "NOTSUB",
				fastautoretargeting = true,
			},
    [6] = {
				badtargetcategory = "VTOL",
				def = "ROGUE_PLASMA",
				onlytargetcategory = "NOTSUB",
				fastautoretargeting = true,
			},
    [7] = {
				badtargetcategory = "VTOL",
				def = "ROGUE_SNIPER",
				onlytargetcategory = "NOTSUB",
				fastautoretargeting = true,
			},
    [8] = {
				badtargetcategory = "VTOL",
				def = "ROGUE_BARRAGE",
				onlytargetcategory = "SURFACE",
				fastautoretargeting = true,
			},
    [9] = {
				badtargetcategory = "VTOL",
				def = "ROGUE_SHOCKWAVE",
				onlytargetcategory = "SURFACE",
				fastautoretargeting = true,
			},
  },
}

-- 三阵营统一的 Roguelike 指挥官基础值。所有模式内数值集中在这里，
-- 避免再出现只改 armcom/corcom、漏掉 legcom 的情况；模式关闭时完全不生效。
local COMMANDER_BASE = {
	health = 10000,
	speed = 100,
	energymake = 60,
	metalmake = 0,
	metalstorage = 10000,
	sightdistance = 520,
}

-- 初始武器目标为各阵营约 +40%。这里只缩放常规伤害字段，
-- 跳过 DGun（99999 秒杀武器）和商店武器（它们有独立平衡表）。
local COMMANDER_WEAPON_DAMAGE_SCALE = 2
local COMMANDER_MAIN_WEAPONS = {
	armcomlaser = true,
	corcomlaser = true,
	legcomlaser = true,
}

local COMMANDER_MAIN_WEAPON_RANGE = 420 -- 初始武器攻击范围
local COMMANDER_AA_RANGE = 480 -- 防空武器范围
local ROGUELIKE_SHIELD_INTERCEPT_BIT = 16384
local factionWeaponCatalog = VFS.Include("unitbasedefs/roguelike_weapon_catalog.lua")
local COMMON_SHOP_WEAPONS = {
	{ id = "lightning_weapon", source = "rogue_lightning", group = 4, target = "NOTSUB" },
	{ id = "plasma_weapon", source = "rogue_plasma", group = 5, target = "NOTSUB" },
	{ id = "sniper_weapon", source = "rogue_sniper", group = 6, target = "NOTSUB" },
	{ id = "barrage_weapon", source = "rogue_barrage", group = 7, target = "SURFACE" },
	{ id = "shockwave_weapon", source = "rogue_shockwave", group = 8, target = "SURFACE" },
}

local function tuneCommanderBase(unitDef)
	for stat, value in pairs(COMMANDER_BASE) do
		unitDef[stat] = value
	end
end

-- 按肉鸽模式的平衡参数调整指挥官的武器定义。
-- 此函数直接修改传入的 unitDef.weapondefs 中的武器表；没有 weapondefs 时按空表处理。
local function scaleCommanderWeapons(unitDef)
	-- 遍历该单位定义中的所有武器：weaponName 是武器键名，weaponDef 是对应的属性表。
	for weaponName, weaponDef in pairs(unitDef.weapondefs or {}) do
		-- D-gun（或标记为 commandfire 的指令开火武器）有特殊用途，跳过普通伤害缩放。
		local isDgun = weaponDef.weapontype == "DGun" or weaponDef.commandfire
		-- 商店武器由肉鸽机制单独配置，避免在此重复缩放伤害。
		-- 若 customparams 或标记不存在，表达式结果为 nil，在条件判断中等同 false。
		local isShopWeapon = weaponDef.customparams and weaponDef.customparams.roguelike_shop_item

		-- 只对普通武器且拥有 damage 表的武器执行伤害调整。
		if not isDgun and not isShopWeapon and weaponDef.damage then
			-- 依次处理常规目标、潜艇和空中单位对应的伤害类别。
			for _, damageType in ipairs({ "default", "subs", "vtol" }) do
				local value = weaponDef.damage[damageType]
				-- 仅缩放正数伤害；缺失、非数值、零或负数的值保持不变。
				if type(value) == "number" and value > 0 then
					-- 伤害乘以统一倍率 COMMANDER_WEAPON_DAMAGE_SCALE。
					weaponDef.damage[damageType] = value * COMMANDER_WEAPON_DAMAGE_SCALE
				end
			end
		end

		-- 如果武器键名列在主武器名单中，还会统一调整射程和装填时间。
		if COMMANDER_MAIN_WEAPONS[weaponName] then
			-- 覆盖原射程，设为 COMMANDER_MAIN_WEAPON_RANGE。
			weaponDef.range = COMMANDER_MAIN_WEAPON_RANGE
			-- 装填时间乘以 0.75，即缩短 25%；原值缺失时按 0 计算。
			weaponDef.reloadtime = (weaponDef.reloadtime or 0) * 0.75
		end
	end
end

-- 从 Legion 指挥官定义中复制防空导弹，创建肉鸽指挥官专用的防空武器定义。
local function copyRoguelikeAntiAirWeapon(unitDef)
	-- 加载 Legion 指挥官的单位定义，并取出其中的 legcom 定义。
	local legionCom = VFS.Include("units/Legion/legcom.lua").legcom
	-- 尝试取得其 weapondefs 表里的 aa_missile 武器定义；中间任一层缺失都会得到 nil。
	local sourceWeapon = legionCom and legionCom.weapondefs and legionCom.weapondefs.aa_missile
	-- 找不到来源武器时无法复制，返回 false 表示操作失败。
	if not sourceWeapon then return false end

	-- 复制完整武器定义，避免直接改动 Legion 原始武器表。
	local antiAirWeapon = table.copy(sourceWeapon)
	-- 深复制这两个子表，之后修改它们时不会影响来源武器的对应数据。
	antiAirWeapon.customparams = table.copy(sourceWeapon.customparams or {})
	antiAirWeapon.damage = table.copy(sourceWeapon.damage or {})
	-- 设置肉鸽专用武器名称，并将射程覆盖为统一的防空射程。
	antiAirWeapon.name = "Roguelike Commander Interceptor"
	antiAirWeapon.range = COMMANDER_AA_RANGE
	-- 确保目标单位有 weapondefs 表，再以专用键名注册复制后的防空武器。
	unitDef.weapondefs = unitDef.weapondefs or {}
	unitDef.weapondefs.roguelike_aa_missile = antiAirWeapon
	-- 返回 true 表示复制并注册成功。
	return true
end

local function appendRoguelikeAntiAirSlot(unitDef)
	for _, slot in pairs(unitDef.weapons or {}) do
		local def = string.lower(tostring(slot.def or ""))
		if def == "aa_missile" or def == "roguelike_aa_missile" then return end
	end
	local lastSlot = 0
	for slot in pairs(unitDef.weapons or {}) do
		if type(slot) == "number" and slot > lastSlot then
			lastSlot = slot
		end
	end
	unitDef.weapons[lastSlot + 1] = {
		badtargetcategory = "NOTAIR GROUNDSCOUT",
		def = "ROGUELIKE_AA_MISSILE",
		onlytargetcategory = "VTOL",
	}
end

-- 给单位添加肉鸽模式的自爆威胁标记，并返回修改后的单位定义。
local function markRoguelikeSuicideThreat(unitDef)
	-- 确保 customparams 参数表存在；若原来没有则创建空表。
	unitDef.customparams = unitDef.customparams or {}
	-- 设置标记供其他肉鸽逻辑识别该单位具有自爆威胁。
	unitDef.customparams.roguelike_suicide_threat = true
	-- 返回同一个 unitDef，便于调用处继续传递或链式处理该定义。
	return unitDef
end

-- 为单位添加肉鸽商店提供的雷霆武器，并返回修改后的单位定义。
local function addLightningShopWeapon(unitDef)
  -- 确保武器定义表存在；后续会在其中注册这把武器。
  unitDef.weapondefs = unitDef.weapondefs or {}
  -- 从肉鸽武器库复制雷霆武器，避免直接修改共用的原始定义。
  local lightning = table.copy(rogueWeapons.weapondefs.rogue_lightning)
  -- 单独复制自定义参数表，避免下面设置商店标记或特效参数时影响原定义。
  lightning.customparams = table.copy(lightning.customparams or {})
  -- 标记该武器对应的商店物品 ID，供肉鸽商店逻辑识别。
  lightning.customparams.roguelike_shop_item = "lightning_weapon"
  -- 三阵营使用同一把雷霆步枪。这里显式设置数值，避免 corcom 分支修改共享
  -- weaponDef 表后，Arm/Leg 的强度受 UnitDef 加载顺序影响。
  lightning.reloadtime = 0.85
  -- 确保伤害表存在，并设置对普通目标的伤害值。
  lightning.damage = lightning.damage or {}
  lightning.damage.default = 30.8
  -- 设置雷霆特效的作用范围；该自定义参数以字符串形式保存。
  lightning.customparams.spark_range = "180"
  -- 将复制并调整后的武器注册到当前单位的武器定义表。
  unitDef.weapondefs.rogue_lightning = lightning

  -- 确保武器槽位表存在，再找出现有的最大数字槽位。
  unitDef.weapons = unitDef.weapons or {}
  local lastSlot = 0
  for slot in pairs(unitDef.weapons) do
    -- 忽略非数字键，只用数字键确定下一个可用槽位编号。
    if type(slot) == "number" and slot > lastSlot then
      lastSlot = slot
    end
  end
  -- 在最大槽位之后添加新槽位，并引用上面注册的雷霆武器。
  unitDef.weapons[lastSlot + 1] = {
    def = "ROGUE_LIGHTNING",
    -- 限定目标类别为 NOTSUB，即不将潜艇列为可攻击目标。
    onlytargetcategory = "NOTSUB",
    -- 开启快速重新选择目标，让武器更快转向新的有效目标。
    fastautoretargeting = true,
  }
  -- 返回已添加武器定义和槽位的同一个单位定义。
  return unitDef
end

-- 在单位定义中追加一个武器槽位，并设置武器名和可攻击目标类别。
local function appendWeaponSlot(unitDef, weaponDefName, targetCategory)
	-- 确保武器槽位表存在；如果没有则先创建空表。
	unitDef.weapons = unitDef.weapons or {}
	-- 查找当前最大的数字槽位编号，以便把新槽位追加在末尾。
	local lastSlot = 0
	for slot in pairs(unitDef.weapons) do
		-- 只把数字键纳入槽位编号比较，其他自定义键不参与计算。
		if type(slot) == "number" and slot > lastSlot then lastSlot = slot end
	end
	-- 新槽位引用大写形式的武器定义名称，并追加到最大编号之后。
	unitDef.weapons[lastSlot + 1] = {
		def = string.upper(weaponDefName),
		-- 使用调用方给定的目标类别；未指定时默认针对地面目标类别 SURFACE。
		onlytargetcategory = targetCategory or "SURFACE",
		-- 启用快速重新索敌，使武器能较快转向新的有效目标。
		fastautoretargeting = true,
	}
end

-- 复制一份武器定义并添加肉鸽商店所需的识别信息，返回新定义。
local function copyShopWeapon(sourceWeapon, itemId, weaponGroup)
	-- 复制武器的顶层属性，避免直接更改传入的来源定义。
	local weaponDef = table.copy(sourceWeapon)
	-- 分别复制自定义参数表和伤害表，确保修改副本时不会改动来源武器的子表。
	weaponDef.customparams = table.copy(sourceWeapon.customparams or {})
	weaponDef.damage = table.copy(sourceWeapon.damage or {})
	-- 标记该武器关联的商店物品 ID，供肉鸽商店逻辑识别。
	weaponDef.customparams.roguelike_shop_item = itemId
	-- 记录武器所属分组，供商店分类或相关逻辑使用。
	weaponDef.customparams.weapons_group = weaponGroup
	-- 返回完成复制和标记的新武器定义。
	return weaponDef
end

-- 将公共商店武器复制到单位定义中；可选地同时为这些武器添加单位武器槽位。
local function installCommonShopWeapons(unitDef, appendSlots)
	-- 按配置顺序处理公共商店武器，每个 item 描述武器来源、商店 ID 和目标类别等信息。
	for _, item in ipairs(COMMON_SHOP_WEAPONS) do
		local sourceWeapon
		if item.id == "plasma_weapon" then
			-- 等离子炮来源于 Tzar（corgol）单位定义中的 cor_gol 武器。
			local tzarDef = VFS.Include("units/CorVehicles/T2/corgol.lua").corgol
			sourceWeapon = tzarDef and tzarDef.weapondefs and tzarDef.weapondefs.cor_gol
		else
			-- 其他公共武器从肉鸽武器库中按配置的 source 键名读取。
			sourceWeapon = rogueWeapons.weapondefs[item.source]
		end
		-- 只有成功找到来源定义时才复制和安装该武器。
		if sourceWeapon then
			-- 为单位内的新武器生成统一的 roguelike_ 前缀名称，并复制商店元数据。
			local weaponDefName = "roguelike_" .. item.id
			unitDef.weapondefs[weaponDefName] = copyShopWeapon(sourceWeapon, item.id, item.group)
			if item.id == "lightning_weapon" then
				-- 使用肉鸽平衡参数覆盖雷霆武器的装填时间、普通伤害和特效范围。
				local lightning = unitDef.weapondefs[weaponDefName]
				lightning.reloadtime = 0.85
				lightning.damage.default = 30.8
				lightning.customparams.spark_range = "180"
			elseif item.id == "plasma_weapon" then
				-- 设置等离子炮显示名称，并将其普通伤害调整为肉鸽模式数值。
				unitDef.weapondefs[weaponDefName].name = "Tzar Heavy Cannon"
				unitDef.weapondefs[weaponDefName].damage.default = 1100
			end
			-- appendSlots 为真时，将武器槽位也加入单位；否则只注册武器定义。
			if appendSlots then appendWeaponSlot(unitDef, weaponDefName, item.target) end
		end
	end
end

-- 为 Arm 阵营单位安装肉鸽电能球武器定义及对应武器槽位。
local function installArmElectricOrb(unitDef)
	-- 指定该武器在单位 weapondefs 表中的键名。
	local weaponDefName = "roguelike_electric_orb"
	-- 加载独立文件中的电能球定义，并注册到当前单位的武器定义表。
	unitDef.weapondefs[weaponDefName] = VFS.Include("unitbasedefs/roguelike_electric_orb.lua")
	-- 添加武器槽位，并将可攻击目标限制为 NOTSUB（排除潜艇）。
	appendWeaponSlot(unitDef, weaponDefName, "NOTSUB")
end

-- 根据阵营武器目录中的配置项生成 Spring 可用的武器定义表。
local function makeFactionWeaponDef(item)
	return {
		-- 从配置读取武器名称、类型、射程和装填时间等基础属性。
		name = item.name,
		weapontype = item.weaponType,
		range = item.range,
		reloadtime = item.reload,
		-- 以下通用属性关闭范围伤害，并避免误伤友军或自身；武器以命中触发效果。
		areaofeffect = 0,
		avoidfriendly = true,
		collidefriendly = false,
		noselfdamage = true,
		impactonly = true,
		-- 允许炮塔式转向瞄准。
		turret = true,
		-- 导弹与其他武器采用不同的飞行速度。
		weaponvelocity = item.weaponType == "MissileLauncher" and 520 or 900,
		-- BeamLaser 专用参数：控制光束持续时间、粗细和颜色；其他类型为 nil。
		beamtime = item.weaponType == "BeamLaser" and 0.12 or nil,
		thickness = item.weaponType == "BeamLaser" and 3 or nil,
		corethickness = item.weaponType == "BeamLaser" and 0.4 or nil,
		laserflaresize = item.weaponType == "BeamLaser" and 7 or nil,
		rgbcolor = item.weaponType == "BeamLaser" and "0.25 0.8 1" or nil,
		rgbcolor2 = item.weaponType == "BeamLaser" and "0.9 1 1" or nil,
		-- hive 攻击类型使用四发连射，并设置每发之间的间隔。
		burst = item.attack == "hive" and 4 or nil,
		burstrate = item.attack == "hive" and 0.08 or nil,
		-- MissileLauncher 专用参数：初速、加速度、追踪能力和转向速度。
		startvelocity = item.weaponType == "MissileLauncher" and 260 or nil,
		weaponacceleration = item.weaponType == "MissileLauncher" and 520 or nil,
		tracks = item.weaponType == "MissileLauncher" and true or nil,
		turnrate = item.weaponType == "MissileLauncher" and 18000 or nil,
		-- 若配置了自定义爆炸效果，则添加 custom: 前缀供引擎识别；否则不设置。
		explosiongenerator = item.ceg and ("custom:" .. item.ceg) or nil,
		-- 伤害初始化为零，实际伤害由其他肉鸽逻辑处理。
		damage = { default = 0, vtol = 0, subs = 0 },
		-- 自定义参数用于商店识别、武器类型识别和分组。
		customparams = {
			roguelike_shop_item = item.id,
			roguelike_custom_weapon = item.id,
			roguelike_faction_weapon = "true",
			weapons_group = 20,
		},
	}
end

-- 根据阵营配置为单位安装对应武器定义，并可选择添加武器槽位。
local function installFactionWeapons(unitDef, faction, appendSlots)
	-- 从阵营武器目录中取得该阵营的配置。
	local factionConfig = factionWeaponCatalog.factions[faction]
	-- 若没有该阵营的配置，则不做处理并直接结束函数。
	if not factionConfig then return end
	-- 逐个处理该阵营配置的武器。
	for _, item in ipairs(factionConfig.weapons) do
		-- 按配置生成武器定义，并以 item.id 作为单位武器定义表中的键。
		unitDef.weapondefs[item.id] = makeFactionWeaponDef(item)
		-- 将目录中的目标类型映射为引擎使用的目标类别。
		local targetCategory = item.targetClass == "all" and "NOTSUB"
			or (item.targetClass == "air" and "VTOL" or "SURFACE")
		-- appendSlots 为真时，同时追加武器槽位并应用上面确定的目标类别。
		if appendSlots then appendWeaponSlot(unitDef, item.id, targetCategory) end
	end
end

-- 为单位注册肉鸽指挥官的个人护盾武器定义，并添加对应武器槽位。
local function installRoguelikeShield(unitDef)
	unitDef.weapondefs.roguelike_personal_shield = {
		name = "Roguelike Commander Shield",
		weapontype = "Shield",
		range = 120,
		damage = { default = 0 },
		shield = {
			-- 设置护盾透明度、护甲类型、外置显示和能量消耗等属性。
			alpha = 0.24,
			armortype = "shields",
			exterior = true,
			energyupkeep = 0,
			-- force 控制排斥效果强度；拦截掩码用于指定可拦截的武器。
			force = 8,
			-- 专用肉鸽拦截位：alldefs_post 仅在肉鸽模式下为武器设置此位，
			-- 包括原本拦截掩码为 0 的原版武器。
			intercepttype = ROGUELIKE_SHIELD_INTERCEPT_BIT,
			-- 设置护盾允许的最大速度、最大能量和能量恢复速率。
			maxSpeed = 900,
			power = 10500, -- shield1 + shield2 + shield3; the native cap must cover all upgrades
			powerregen = 0,
			powerregenenergy = 0,
			-- 半径决定护盾覆盖范围；repulser 和 smart 启用智能排斥行为。
			radius = 120,
			repulser = true,
			smart = true,
			-- 初始能量为 0；其余选项控制护盾可见性及命中后的显示帧数。
			startingpower = 0,
			visible = true,
			visiblerepulse = true,
			visiblehitframes = 8,
			-- 分别设置不利拦截和正常拦截时显示的 RGBA 颜色。
			badcolor = { 1, 0.2, 0.2, 0.24 },
			goodcolor = { 0.2, 0.75, 1, 0.24 },
		},
		-- 标记这是肉鸽个人护盾，并归入武器组 30。
		customparams = { roguelike_personal_shield = "true", weapons_group = 30 },
	}
	-- 确保武器槽位表存在，并查找当前最大的数字槽位编号。
	unitDef.weapons = unitDef.weapons or {}
	local lastSlot = 0
	for slot in pairs(unitDef.weapons) do
		if type(slot) == "number" and slot > lastSlot then lastSlot = slot end
	end
	-- 在末尾添加护盾槽位；NOTSUB 表示该槽位不面向潜艇目标类别。
	unitDef.weapons[lastSlot + 1] = {
		def = "ROGUELIKE_PERSONAL_SHIELD",
		onlytargetcategory = "NOTSUB",
	}
end

local function roguelikeUnitTweaks(name, unitDef, modOptions)
  -- 兼容布尔、数字和字符串形式的肉鸽模式开关。
  local enabled = modOptions.roguelike_mode
  -- 模式未启用时不修改单位定义。
  if enabled ~= true and enabled ~= 1 and enabled ~= "1" and enabled ~= "true" then
    return unitDef
  end
	-- legkam 只添加自爆威胁标记，不进入指挥官改造流程。
	if name == "legkam" then
		return markRoguelikeSuicideThreat(unitDef)
	end
  -- 只对三种阵营指挥官执行下方定制。
  if name ~= "armcom" and name ~= "corcom" and name ~= "legcom" then
    return unitDef
  end

  -- 应用肉鸽指挥官基础属性调整。
  tuneCommanderBase(unitDef)
	-- COR/LEG 原版 COB 脚本只支持基础武器槽位；肉鸽专用脚本保留动画并支持新增槽位回调。
	if name == "corcom" then
		unitDef.script = "Units/corcom_roguelike.cob"
	elseif name == "legcom" then
		unitDef.script = "Units/legcom_roguelike.cob"
	end
	-- 确保武器定义表存在，供后续注册武器使用。
	unitDef.weapondefs = unitDef.weapondefs or {}
	if name == "armcom" then
		-- 保留 ARM 指挥官原激光和手动 D-gun 的槽位，新增商店武器使用独立回调。
		local originalWeapons = unitDef.weapons or {}
		unitDef.weapons = { originalWeapons[1], originalWeapons[3] }
		-- 移除原密封激光定义。
		unitDef.weapondefs.armcomsealaser = nil
	end
	if name == "legcom" then
		-- Legion 已有防空导弹时只调整其射程。
		if unitDef.weapondefs and unitDef.weapondefs.aa_missile then
			unitDef.weapondefs.aa_missile.range = COMMANDER_AA_RANGE
		end
	else
		-- 其他阵营复制 Legion 的防空导弹作为肉鸽专用武器。
		copyRoguelikeAntiAirWeapon(unitDef)
	end
	-- 调整现有武器，并添加防空武器、公共商店武器和阵营武器。
	scaleCommanderWeapons(unitDef)
	appendRoguelikeAntiAirSlot(unitDef)
	installCommonShopWeapons(unitDef, true)
	-- 将单位名称映射为武器目录中的阵营键名并安装对应武器。
	local faction = name == "armcom" and "armada" or name == "corcom" and "cortex" or "legion"
	installFactionWeapons(unitDef, faction, true)
	-- ARM 指挥官额外安装电能球武器。
	if name == "armcom" then installArmElectricOrb(unitDef) end
	-- 添加个人护盾定义和槽位。
	installRoguelikeShield(unitDef)
  -- 返回修改后的同一份单位定义。
  return unitDef
end
return {
	UnitTweaks = roguelikeUnitTweaks,
	ShieldInterceptBit = ROGUELIKE_SHIELD_INTERCEPT_BIT,
}
