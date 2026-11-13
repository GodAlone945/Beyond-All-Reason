-- Dedicated weapon callbacks for the Roguelike electric drone.
-- The reused LEGCA COB script has no weapon query/aim/fire callbacks.
local chassis = piece("chassis")

function script.Create()
	-- This unit is positioned and orbited by the synced Roguelike gadget.
end

function script.QueryWeapon1()
	return chassis
end

function script.AimFromWeapon1()
	return chassis
end

function script.AimWeapon1()
	return true
end

function script.FireWeapon1()
end

function script.Shot1()
end

-- Keep the auxiliary weapon slots valid as well, so their definitions cannot
-- leave the unit with missing script callbacks.
function script.QueryWeapon2()
	return chassis
end

function script.AimFromWeapon2()
	return chassis
end

function script.AimWeapon2()
	return true
end

function script.FireWeapon2()
end

function script.Shot2()
end

function script.QueryWeapon3()
	return chassis
end

function script.AimFromWeapon3()
	return chassis
end

function script.AimWeapon3()
	return true
end

function script.FireWeapon3()
end

function script.Shot3()
end

function script.Killed()
	return 1
end
