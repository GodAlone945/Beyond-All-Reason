-- Run with fengari-node-cli. A zero-native-damage faction cannon must reach
-- the watched projectile/explosion path and apply its catalog damage.
table.copy = function(source)
	local result = {}
	for key, value in pairs(source) do result[key] = value end
	return result
end

local watchedProjectiles, watchedExplosions = {}, {}
local damage = 0
local beamOwned, beamEquipped = false, false
gadget = {}
gadgetHandler = {
	IsSyncedCode = function() return true end,
	RegisterProjectile = function(_, id) watchedProjectiles[id] = true end,
	RegisterExplosion = function(_, id) watchedExplosions[id] = true end,
}
VFS = { Include = function()
	return { factions = { cortex = { weapons = { {
		id = "test_cannon", attack = "blast", range = 155, radius = 120,
		damage = 300, targetClass = "surface", weaponType = "Cannon",
	}, {
		id = "test_beam", attack = "multi", range = 650, reload = 1.2,
		damage = 120, maxTargets = 3, targetClass = "surface", weaponType = "BeamLaser",
	} } } } }
end }
Game = { gameSpeed = 30 }
GG = {}
WeaponDefs = {
	[77] = { customParams = { roguelike_custom_weapon = "test_cannon" } },
	[78] = { customParams = { roguelike_custom_weapon = "test_beam" } },
}
WeaponDefNames = {}
UnitDefs = {
	[1] = { name = "armcom", customParams = { iscommander = true }, weapons = { { weaponDef = 77 }, { weaponDef = 78 } } },
	[2] = { health = 1000 },
}
Spring = {
	GetModOptions = function() return { roguelike_mode = 1 } end,
	GetUnitDefID = function(id) return id == 1 and 1 or 2 end,
	GetUnitTeam = function(id) return id == 1 and 1 or 2 end,
	GetUnitPosition = function(id) return id == 1 and 0 or 100, 0, 0 end,
	GetUnitHealth = function() return 1000 end,
	GetUnitWeaponTarget = function() return 1, false, 2 end,
	GetProjectileTarget = function() return string.byte("u"), 2 end,
	GetUnitRulesParam = function(_, key)
		if key == "roguelike_shop_test_beam_level" then return beamOwned and 1 or 0 end
		if key == "roguelike_weapon_equipped_test_beam" then return beamEquipped and 1 or 0 end
		return key == "roguelike_shop_test_cannon_level" and 1 or nil
	end,
	GetUnitsInCylinder = function() return { 2 } end,
	AreTeamsAllied = function(a, b) return a == b end,
	AddUnitDamage = function(_, amount) damage = damage + amount end,
	GetGameFrame = function() return 30 end,
	GetUnitVelocity = function() return 0, 0, 0 end,
	AddUnitImpulse = function() end,
	ValidUnitID = function(id) return id == 1 or id == 2 end,
	GetTeamInfo = function() return 1, 0, false, false end,
	GetAllUnits = function() return { 1, 2 } end,
}

dofile("luarules/gadgets/game_roguelike_faction_weapons.lua")
gadget:Initialize()
assert(watchedProjectiles[77] and watchedExplosions[77], "faction cannon is not watched")
gadget:ProjectileCreated(99, 1, 77)
gadget:Explosion(77, 100, 0, 0, 1, 99)
assert(damage == 300, "purchased cannon did not deal catalog damage: " .. damage)
print("PASS faction shop cannon projectile, explosion and damage")

damage = 0
GG.RoguelikeFactionWeapons.OnWeaponFired(1, 2)
assert(damage == 0, "unowned beam fired")
beamOwned = true
GG.RoguelikeFactionWeapons.OnWeaponFired(1, 2)
assert(damage == 0, "unequipped beam fired")
beamEquipped = true
GG.RoguelikeFactionWeapons.OnWeaponFired(1, 2)
assert(damage == 120, "native ARM script did not apply beam catalog damage")
gadget:UnitWeaponFired(1, 1, 1, 2, 78)
assert(damage == 120, "ARM beam dealt duplicate damage through gadget callback")
for projectile = 100, 103 do
	gadget:ProjectileCreated(projectile, 1, 78)
	gadget:Explosion(78, 100, 0, 0, 1, projectile)
end
assert(damage == 120, "ARM beam visual projectiles dealt duplicate damage")
beamEquipped = false
GG.RoguelikeFactionWeapons.OnWeaponFired(1, 2)
assert(damage == 120, "unequipped ARM beam kept dealing damage")
print("PASS native ARM beam ownership, equip, script callback and duplicate prevention")
