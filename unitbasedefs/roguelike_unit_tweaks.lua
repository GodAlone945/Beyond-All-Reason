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
	speed = 84,
	energymake = 60,
	metalmake = 0,
	metalstorage = 10000,
	sightdistance = 520,
}

-- 初始武器目标为各阵营约 +40%。这里只缩放常规伤害字段，
-- 跳过 DGun（99999 秒杀武器）和商店武器（它们有独立平衡表）。
local COMMANDER_WEAPON_DAMAGE_SCALE = 1.4
local COMMANDER_MAIN_WEAPONS = {
	armcomlaser = true,
	corcomlaser = true,
	legcomlaser = true,
}

local COMMANDER_MAIN_WEAPON_RANGE = 420
local COMMANDER_AA_RANGE = 480
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

local function scaleCommanderWeapons(unitDef)
	for weaponName, weaponDef in pairs(unitDef.weapondefs or {}) do
		local isDgun = weaponDef.weapontype == "DGun" or weaponDef.commandfire
		local isShopWeapon = weaponDef.customparams and weaponDef.customparams.roguelike_shop_item
		if not isDgun and not isShopWeapon and weaponDef.damage then
			for _, damageType in ipairs({ "default", "subs", "vtol" }) do
				local value = weaponDef.damage[damageType]
				if type(value) == "number" and value > 0 then
					weaponDef.damage[damageType] = value * COMMANDER_WEAPON_DAMAGE_SCALE
				end
			end
		end
		if COMMANDER_MAIN_WEAPONS[weaponName] then
			weaponDef.range = COMMANDER_MAIN_WEAPON_RANGE
			weaponDef.reloadtime = (weaponDef.reloadtime or 0) * 0.75
		end
	end
end

local function copyRoguelikeAntiAirWeapon(unitDef)
	local legionCom = VFS.Include("units/Legion/legcom.lua").legcom
	local sourceWeapon = legionCom and legionCom.weapondefs and legionCom.weapondefs.aa_missile
	if not sourceWeapon then return false end

	local antiAirWeapon = table.copy(sourceWeapon)
	antiAirWeapon.customparams = table.copy(sourceWeapon.customparams or {})
	antiAirWeapon.damage = table.copy(sourceWeapon.damage or {})
	antiAirWeapon.name = "Roguelike Commander Interceptor"
	antiAirWeapon.range = COMMANDER_AA_RANGE
	unitDef.weapondefs = unitDef.weapondefs or {}
	unitDef.weapondefs.roguelike_aa_missile = antiAirWeapon
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

local function markRoguelikeSuicideThreat(unitDef)
	unitDef.customparams = unitDef.customparams or {}
	unitDef.customparams.roguelike_suicide_threat = true
	return unitDef
end

local function addLightningShopWeapon(unitDef)
  unitDef.weapondefs = unitDef.weapondefs or {}
  local lightning = table.copy(rogueWeapons.weapondefs.rogue_lightning)
  lightning.customparams = table.copy(lightning.customparams or {})
  lightning.customparams.roguelike_shop_item = "lightning_weapon"
  -- 三阵营使用同一把雷霆步枪。这里显式写死数值，避免 corcom 分支修改共享
  -- weaponDef 表后，Arm/Leg 的强度取决于 UnitDef 的加载顺序。
  lightning.reloadtime = 0.85
  lightning.damage = lightning.damage or {}
  lightning.damage.default = 30.8
  lightning.customparams.spark_range = "180"
  unitDef.weapondefs.rogue_lightning = lightning

  unitDef.weapons = unitDef.weapons or {}
  local lastSlot = 0
  for slot in pairs(unitDef.weapons) do
    if type(slot) == "number" and slot > lastSlot then
      lastSlot = slot
    end
  end
  unitDef.weapons[lastSlot + 1] = {
    def = "ROGUE_LIGHTNING",
    onlytargetcategory = "NOTSUB",
    fastautoretargeting = true,
  }
  return unitDef
end

local function appendWeaponSlot(unitDef, weaponDefName, targetCategory)
	unitDef.weapons = unitDef.weapons or {}
	local lastSlot = 0
	for slot in pairs(unitDef.weapons) do
		if type(slot) == "number" and slot > lastSlot then lastSlot = slot end
	end
	unitDef.weapons[lastSlot + 1] = {
		def = string.upper(weaponDefName),
		onlytargetcategory = targetCategory or "SURFACE",
		fastautoretargeting = true,
	}
end

local function copyShopWeapon(sourceWeapon, itemId, weaponGroup)
	local weaponDef = table.copy(sourceWeapon)
	weaponDef.customparams = table.copy(sourceWeapon.customparams or {})
	weaponDef.damage = table.copy(sourceWeapon.damage or {})
	weaponDef.customparams.roguelike_shop_item = itemId
	weaponDef.customparams.weapons_group = weaponGroup
	return weaponDef
end

local function installCommonShopWeapons(unitDef, appendSlots)
	for _, item in ipairs(COMMON_SHOP_WEAPONS) do
		local sourceWeapon
		if item.id == "plasma_weapon" then
			local tzarDef = VFS.Include("units/CorVehicles/T2/corgol.lua").corgol
			sourceWeapon = tzarDef and tzarDef.weapondefs and tzarDef.weapondefs.cor_gol
		else
			sourceWeapon = rogueWeapons.weapondefs[item.source]
		end
		if sourceWeapon then
			local weaponDefName = "roguelike_" .. item.id
			unitDef.weapondefs[weaponDefName] = copyShopWeapon(sourceWeapon, item.id, item.group)
			if item.id == "lightning_weapon" then
				local lightning = unitDef.weapondefs[weaponDefName]
				lightning.reloadtime = 0.85
				lightning.damage.default = 30.8
				lightning.customparams.spark_range = "180"
			elseif item.id == "plasma_weapon" then
				unitDef.weapondefs[weaponDefName].name = "Tzar Heavy Cannon"
				unitDef.weapondefs[weaponDefName].damage.default = 1100
			end
			if appendSlots then appendWeaponSlot(unitDef, weaponDefName, item.target) end
		end
	end
end

local function makeFactionWeaponDef(item)
	return {
		name = item.name,
		weapontype = item.weaponType,
		range = item.range,
		reloadtime = item.reload,
		areaofeffect = 0,
		avoidfriendly = true,
		collidefriendly = false,
		noselfdamage = true,
		impactonly = true,
		turret = true,
		weaponvelocity = item.weaponType == "MissileLauncher" and 520 or 900,
		beamtime = item.weaponType == "BeamLaser" and 0.12 or nil,
		thickness = item.weaponType == "BeamLaser" and 3 or nil,
		corethickness = item.weaponType == "BeamLaser" and 0.4 or nil,
		laserflaresize = item.weaponType == "BeamLaser" and 7 or nil,
		rgbcolor = item.weaponType == "BeamLaser" and "0.25 0.8 1" or nil,
		rgbcolor2 = item.weaponType == "BeamLaser" and "0.9 1 1" or nil,
		burst = item.attack == "hive" and 4 or nil,
		burstrate = item.attack == "hive" and 0.08 or nil,
		startvelocity = item.weaponType == "MissileLauncher" and 260 or nil,
		weaponacceleration = item.weaponType == "MissileLauncher" and 520 or nil,
		tracks = item.weaponType == "MissileLauncher" and true or nil,
		turnrate = item.weaponType == "MissileLauncher" and 18000 or nil,
		explosiongenerator = item.ceg and ("custom:" .. item.ceg) or nil,
		damage = { default = 0, vtol = 0, subs = 0 },
		customparams = {
			roguelike_shop_item = item.id,
			roguelike_custom_weapon = item.id,
			roguelike_faction_weapon = "true",
			weapons_group = 20,
		},
	}
end

local function installFactionWeapons(unitDef, faction, appendSlots)
	local factionConfig = factionWeaponCatalog.factions[faction]
	if not factionConfig then return end
	for _, item in ipairs(factionConfig.weapons) do
		unitDef.weapondefs[item.id] = makeFactionWeaponDef(item)
		local targetCategory = item.targetClass == "all" and "NOTSUB"
			or (item.targetClass == "air" and "VTOL" or "SURFACE")
		if appendSlots then appendWeaponSlot(unitDef, item.id, targetCategory) end
	end
end

local function installRoguelikeShield(unitDef)
	unitDef.weapondefs.roguelike_personal_shield = {
		name = "Roguelike Commander Shield",
		weapontype = "Shield",
		range = 120,
		damage = { default = 0 },
		shield = {
			alpha = 0.24,
			armortype = "shields",
			exterior = true,
			energyupkeep = 0,
			force = 8,
			-- Dedicated Rogue bit: alldefs_post marks every weapon with this bit
			-- only in Roguelike mode, including stock weapons that set mask 0.
			intercepttype = ROGUELIKE_SHIELD_INTERCEPT_BIT,
			maxSpeed = 900,
			power = 5000,
			powerregen = 0,
			powerregenenergy = 0,
			radius = 120,
			repulser = true,
			smart = true,
			startingpower = 0,
			visible = true,
			visiblerepulse = true,
			visiblehitframes = 8,
			badcolor = { 1, 0.2, 0.2, 0.24 },
			goodcolor = { 0.2, 0.75, 1, 0.24 },
		},
		customparams = { roguelike_personal_shield = "true", weapons_group = 30 },
	}
	unitDef.weapons = unitDef.weapons or {}
	local lastSlot = 0
	for slot in pairs(unitDef.weapons) do
		if type(slot) == "number" and slot > lastSlot then lastSlot = slot end
	end
	unitDef.weapons[lastSlot + 1] = {
		def = "ROGUELIKE_PERSONAL_SHIELD",
		onlytargetcategory = "NOTSUB",
	}
end

local function roguelikeUnitTweaks(name, unitDef, modOptions)
  local enabled = modOptions.roguelike_mode
  if enabled ~= true and enabled ~= 1 and enabled ~= "1" and enabled ~= "true" then
    return unitDef
  end
	if name == "legkam" then
		return markRoguelikeSuicideThreat(unitDef)
	end
  if name ~= "armcom" and name ~= "corcom" and name ~= "legcom" then
    return unitDef
  end

  tuneCommanderBase(unitDef)
	-- The original COR/LEG COBs only implement their base weapon slots. These
	-- Roguelike-only copies preserve the original animation bytecode and add
	-- independent aim/muzzle callbacks for the appended shop weapon slots.
	if name == "corcom" then
		unitDef.script = "Units/corcom_roguelike.cob"
	elseif name == "legcom" then
		unitDef.script = "Units/legcom_roguelike.cob"
	end
	unitDef.weapondefs = unitDef.weapondefs or {}
	if name == "armcom" then
		-- Keep laser and manual D-Gun at slots 1/2. Shop weapons are appended
		-- below and use independent auxiliary callbacks in armcom_lus.lua.
		local originalWeapons = unitDef.weapons or {}
		unitDef.weapons = { originalWeapons[1], originalWeapons[3] }
		unitDef.weapondefs.armcomsealaser = nil
	end
	if name == "legcom" then
		if unitDef.weapondefs and unitDef.weapondefs.aa_missile then
			unitDef.weapondefs.aa_missile.range = COMMANDER_AA_RANGE
		end
	else
		copyRoguelikeAntiAirWeapon(unitDef)
	end
	scaleCommanderWeapons(unitDef)
	appendRoguelikeAntiAirSlot(unitDef)
	installCommonShopWeapons(unitDef, true)
	local faction = name == "armcom" and "armada" or name == "corcom" and "cortex" or "legion"
	installFactionWeapons(unitDef, faction, true)
	installRoguelikeShield(unitDef)
  return unitDef
end

return {
	UnitTweaks = roguelikeUnitTweaks,
	ShieldInterceptBit = ROGUELIKE_SHIELD_INTERCEPT_BIT,
}
