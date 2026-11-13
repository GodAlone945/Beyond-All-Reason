-- Run from repository root with fengari.cmd or Lua 5.2+.
local path = "luarules/gadgets/game_roguelike_multishot.lua"
local config = assert(loadfile("unitbasedefs/roguelike_multishot.lua"))()
local function close(a, b) assert(math.abs(a - b) < 0.0001, tostring(a) .. " ~= " .. tostring(b)) end

local function fixture(enabled)
	local f = { frame = 10, rules = { [1] = {}, [2] = {} }, shots = {}, projectiles = {}, hp = 100000 }
	local env = setmetatable({ gadget = {}, GG = { Roguelike = { teams = {
		[1] = { commanderUnitID = 1 }, [2] = { commanderUnitID = 2 },
	} } } }, { __index = _G })
	env.gadgetHandler = { IsSyncedCode = function() return true end }
	env.VFS = { Include = function() return config end }
	env.Game = { gravity = 120, gameSpeed = 30 }
	env.UnitDefNames = { armcom = { id = 1 } }
	env.UnitDefs = { [1] = { weapons = { { weaponDef = 4 } } } }
	env.WeaponDefs = { [4] = { type = "Cannon", range = 650, gravityAffected = true,
		customParams = { roguelike_shop_item = "plasma_weapon" }, damages = { [0] = 100 } } }
	env.Script = { SetWatchWeapon = function(id) close(id, 4) end }
	env.Spring = {
		GetModOptions = function() return { roguelike_mode = enabled ~= false } end,
		GetGameFrame = function() return f.frame end,
		GetUnitDefID = function(id) if id == 1 or id == 2 then return 1 end end,
		GetUnitTeam = function(id) return id end,
		GetUnitWeaponState = function() return 650 end,
		GetUnitRulesParam = function(id, key) return f.rules[id] and f.rules[id][key] end,
		GetUnitWeaponVectors = function(id) return id * 10, 20, 30, 1, 0, 0 end,
		GetProjectilePosition = function(id) local p = f.projectiles[id]; return p and p.pos[1], p and p.pos[2], p and p.pos[3] end,
		GetProjectileVelocity = function(id) local p = f.projectiles[id]; return p and p.speed[1], p and p.speed[2], p and p.speed[3] end,
	}
	local nextID = 100
	env.Spring.SpawnProjectile = function(defID, params)
		nextID = nextID + 1
		f.projectiles[nextID] = params
		f.shots[#f.shots + 1] = { id = nextID, defID = defID, frame = f.frame, params = params }
		env.gadget:ProjectileCreated(nextID, params.owner, defID) -- synchronous callback
		return nextID
	end
	local loaded = assert(loadfile(path, "t", env))()
	f.loaded, f.gadget = loaded, env.gadget
	if enabled ~= false then env.gadget:Initialize() end
	function f.fire(id, projectileID)
		f.projectiles[projectileID] = { pos = { id * 10, 20, 30 }, speed = { 10, 2, 0 } }
		env.gadget:ProjectileCreated(projectileID, id, 4)
	end
	function f.hit(projectileID)
		local p = f.projectiles[projectileID]
		assert(p)
		f.hp = f.hp - env.WeaponDefs[4].damages[0] * (f.rules[p.owner].damageMultiplier or 1)
	end
	return f
end

do
	local f = fixture(false)
	assert(f.loaded == false)
	print("PASS mode off")
end
for _, count in ipairs({ 1, 3, 5, 7, 9 }) do
	local f = fixture()
	f.rules[1].roguelike_multishot_count = count
	f.rules[1].damageMultiplier = 1.5
	f.fire(1, 1)
	f.projectiles[1].owner = 1
	f.hit(1) -- native centre projectile
	assert(#f.shots == count - 1)
	local angles = {}
	for _, shot in ipairs(f.shots) do
		local p = shot.params
		assert(shot.frame == 10 and shot.defID == 4 and p.owner == 1 and p.team == 1)
		close(p.pos[1], 10); close(p.pos[2], 20); close(p.pos[3], 30)
		assert(p.gravity < 0)
		angles[#angles + 1] = math.floor(math.atan(p.speed[3], p.speed[1]) * 180 / math.pi + 0.5)
		f.hit(shot.id)
	end
	for i = 1, #angles do
		local wanted = (i <= (count - 1) / 2 and i - (count + 1) / 2 or i - (count - 1) / 2) * 4
		close(angles[i], wanted)
	end
	local nativeDamage = 100 * 1.5
	close(f.hp, 100000 - count * nativeDamage)
	f.gadget:ProjectileCreated(1, 1, 4)
	assert(#f.shots == count - 1)
	print("PASS count, angles, same frame and muzzle, full damage, repeat guard " .. count)
end
do
	local f = fixture()
	f.rules[1].roguelike_multishot_count = 9
	f.projectiles[50] = { pos = { 0, 0, 0 }, speed = { 10, 0, 0 } }
	f.gadget:ProjectileCreated(50, 1, 99) -- unregistered WeaponDef
	assert(#f.shots == 0)
	print("PASS explicit weapon allowlist")
end
do
	local f = fixture()
	f.rules[1].roguelike_multishot_count = 9
	f.rules[2].roguelike_multishot_count = 9
	f.fire(1, 1); f.fire(2, 2)
	assert(#f.shots == 16)
	f.frame = 11; f.rules[1].roguelike_multishot_count = 3
	f.fire(1, 3)
	assert(#f.shots == 18)
	print("PASS independent teams, immediate upgrade, same-frame budget")
end
