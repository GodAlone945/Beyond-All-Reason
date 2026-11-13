-- Executed by Test-ShieldRepulsion.cjs, which injects the real callback source.
local power = { [101] = 250, [102] = 250 }
local changes = {}
local env = setmetatable({
	gadget = {},
	shieldUnitsData = {},
	roguelikePersonalShieldUnitDefs = { [1] = true },
	roguelikePersonalShieldHits = {},
	unitDefIDCache = { [101] = 1, [102] = 1, [201] = 2 },
	unitDefWeaponDefs = { [2] = { [1] = 11 } },
	originalShieldDamages = { [10] = 100, [11] = 20 },
	spGetProjectileDefID = function() return 10 end,
	spGetUnitShieldState = function(unitID) return 1, power[unitID] end,
	spSetUnitShieldState = function(unitID, _, value)
		power[unitID] = value
		changes[#changes + 1] = { unitID, value }
	end,
	mathMax = math.max,
	gameFrame = 90,
}, { __index = _G })
assert(load(shieldCallbackSource, "shield callback", "t", env))()

local function hit(projectileID, shieldUnitID, beamUnitID)
	return env.gadget:ShieldPreDamaged(projectileID, 201, 14, shieldUnitID,
		true, beamUnitID and 1 or nil, beamUnitID)
end

assert(hit(7, 101) == false and power[101] == 150, "first projectile must bounce and spend power")
assert(hit(7, 101) == false and power[101] == 150, "same projectile charged twice")
assert(hit(8, 102) == false and power[102] == 150, "other player's shield state leaked")
assert(hit(-1, 101, 201) == false and power[101] == 130, "beam frame was not blocked and charged")
assert(hit(9, 101) == false and power[101] == 30, "second projectile charge incorrect")
assert(hit(10, 101) == false and power[101] == 0, "last projectile should bounce and deplete shield")
assert(hit(11, 101) == true and power[101] == 0, "depleted shield must let the next shot through")
assert(hit(12, 999) == true, "ordinary unregistered shield behavior changed")
assert(#changes == 5, "unexpected shield power writes")
print("PASS native Roguelike shield bounce, charge, depletion, beam and Team isolation")
