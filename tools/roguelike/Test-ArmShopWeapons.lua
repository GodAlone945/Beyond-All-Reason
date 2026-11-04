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
local commander = table.copy(original)
tweaks.UnitTweaks("armcom", commander, { roguelike_mode = 1 })
assert(#commander.weapons == 13, "ARM must expose nine native shop weapons")
assert(commander.weapons[1].def == original.weapons[1].def, "primary slot changed")
assert(commander.weapons[2].def == original.weapons[3].def, "D-Gun slot changed")
local seen, common, faction = {}, 0, 0
for slot = 4, 12 do
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
assert(common == 5 and faction == 4, "incorrect ARM shop pool")
assert(commander.weapondefs[commander.weapons[13].def:lower()].weapontype == "Shield", "shield slot lost")
print("PASS ARM native shop slots, visible definitions, D-Gun/shield mapping and stock-mode isolation")
