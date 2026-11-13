-- Run from the repository root with fengari-node-cli.
table.copy = function(source)
	local result = {}
	for key, value in pairs(source) do
		result[key] = type(value) == "table" and table.copy(value) or value
	end
	return result
end
VFS = { Include = dofile }
local tweaks = dofile("unitbasedefs/roguelike_unit_tweaks.lua")
local original = dofile("units/armcom.lua").armcom
local stock = table.copy(original)
tweaks.UnitTweaks("armcom", stock, { roguelike_mode = 0 })
assert(#stock.weapons == #original.weapons, "stock ARM weapon slots changed")
assert(not stock.weapondefs.roguelike_electric_orb, "stock ARM gained the electric orb")
local commander = table.copy(original)
tweaks.UnitTweaks("armcom", commander, { roguelike_mode = 1 })
assert(#commander.weapons == 14, "ARM must expose ten native shop weapons")
assert(commander.weapons[1].def == original.weapons[1].def, "primary slot changed")
assert(commander.weapons[2].def == original.weapons[3].def, "D-Gun slot changed")
local seen, common, faction = {}, 0, 0
for slot = 4, 13 do
	local weapon = commander.weapondefs[commander.weapons[slot].def:lower()]
	local params = weapon.customparams
	assert(params.roguelike_shop_item and not seen[params.roguelike_shop_item], "missing or duplicate shop slot")
	assert(tonumber(params.weapons_group) >= 0, "shop weapon hidden from detailed stats")
	seen[params.roguelike_shop_item] = true
	if params.roguelike_custom_weapon then
		faction = faction + 1
		assert(weapon.weapontype == "BeamLaser" and weapon.thickness > 0, "ARM faction beam has no visible width")
		assert(weapon.damage.default == 0, "faction damage must be applied once by Lua")
	else
		common = common + 1
		assert(weapon.damage.default > 0, "common native weapon has no damage")
	end
end
assert(common == 6 and faction == 4, "incorrect ARM shop pool")
local orb = commander.weapondefs[commander.weapons[13].def:lower()]
assert(orb.customparams.roguelike_shop_item == "electric_orb", "electric orb slot missing")
assert(orb.weapontype == "Cannon" and orb.model == nil and orb.size == 27
	and orb.rgbcolor == "0.3 0.7 1", "electric orb projectile invalid")
assert(orb.cegtag == "roguelike-electric-orb-trail"
	and orb.explosiongenerator == "custom:genericshellexplosion-small-lightning", "electric orb visuals missing")
local orbEffects = dofile("effects/roguelike_electric_orb.lua")
assert(orbEffects[orb.cegtag] and orbEffects[orb.cegtag].halo
	and orbEffects["roguelike-electric-orb-chain"], "electric orb effect definitions missing")
local shield = commander.weapondefs[commander.weapons[14].def:lower()]
assert(shield.weapontype == "Shield" and shield.shield.repulser == true
	and shield.shield.power == 10500 and shield.shield.intercepttype == tweaks.ShieldInterceptBit,
	"Roguelike shield must support all capacity upgrades and native repulsion")
for _, faction in ipairs({ { "corcom", "units/corcom.lua" }, { "legcom", "units/Legion/legcom.lua" } }) do
	local name, path = faction[1], faction[2]
	local unitDef = table.copy(dofile(path)[name])
	tweaks.UnitTweaks(name, unitDef, { roguelike_mode = 1 })
	local lastWeapon = unitDef.weapons[#unitDef.weapons]
	local factionShield = unitDef.weapondefs[lastWeapon.def:lower()]
	assert(factionShield and factionShield.customparams.roguelike_personal_shield
		and factionShield.shield.repulser and factionShield.shield.power == 10500,
		name .. " Roguelike repulsion shield missing")
end
print("PASS ARM native shop slots, visible definitions, D-Gun/shield mapping and stock-mode isolation")
