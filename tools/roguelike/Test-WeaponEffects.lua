-- Standalone mocked-callin regressions. Run from repository root with Lua 5.2+
-- or fengari. This does not validate Recoil APIs, visuals or network determinism.
local sourcePath = arg[1] or "luarules/gadgets/game_roguelike_weapon_effects.lua"
local failures, total = 0, 0
local function expect(value, wanted, message)
	assert(value == wanted, (message or "unexpected result") .. ": expected " .. tostring(wanted) .. ", got " .. tostring(value))
end
local function fixture(enabled, randomValue)
	local f = { frame = 0, rules = { [1] = {} }, projectiles = {}, spawned = {}, deleted = {}, hits = {}, markers = {} }
	local definitions = assert(loadfile("unitbasedefs/roguelike_weapon_effects.lua"))()
	f.definitions = definitions
	local units = { [1] = { team = 1, x = 0 }, [10] = { team = 2, x = 100 }, [11] = { team = 2, x = 110 } }
	local noop = function() end
	local env = setmetatable({}, { __index = _G })
	env.math = setmetatable({ random = function() return randomValue or 0 end }, { __index = math })
	env.gadget, env.GG = {}, {}
	env.Game = { gameSpeed = 30, gravity = 120 }
	env.GameCMD, env.CMDTYPE, env.LOG = { ROGUELIKE_METEOR_STRIKE = 34567 }, { ICON_MAP = 1 }, { ERROR = 1 }
	env.gadgetHandler = { IsSyncedCode = function() return true end, RegisterCMDID = noop, RegisterAllowCommand = noop }
	env.VFS, env.Script = { Include = function() return definitions end }, { SetWatchWeapon = noop }
	env.UnitDefs = { [1] = { customParams = { iscommander = true }, weapons = { { weaponDef = 3 }, { weaponDef = 4 }, { weaponDef = 5 } } }, [2] = { customParams = {}, health = 1000 } }
	env.UnitDefNames = { armcom = { id = 1 } }
	env.WeaponDefNames = { roguelike_test_meteor_payload = { id = 1 } }
	env.WeaponDefs = {
		[1] = { customParams = { roguelike_weapon_effect = "meteor_payload" }, damages = { [0] = 500 } },
		[2] = { customParams = { roguelike_weapon_effect = "splitter" }, damages = { [0] = 180 } },
		[3] = { customParams = { roguelike_shop_item = "plasma_weapon" }, damages = { [0] = 100 }, type = "Cannon" },
		[4] = { customParams = { roguelike_shop_item = "sniper_weapon" }, damages = { [0] = 100 }, type = "BeamLaser", reload = 2 },
		[5] = { customParams = { roguelike_shop_item = "electric_orb" }, damages = { [0] = 120 }, type = "Cannon", reload = 1.8 },
	}
	local spring = {
		GetModOptions = function() return { roguelike_mode = enabled ~= false, roguelike_weapon_effect_tests = true } end,
		GetGameFrame = function() return f.frame end,
		GetUnitRulesParam = function(id, key) return f.rules[id] and f.rules[id][key] end,
		SetUnitRulesParam = function(id, key, value) f.rules[id] = f.rules[id] or {}; f.rules[id][key] = value end,
		GetAllUnits = function() return { 1 } end,
		GetUnitDefID = function(id) return units[id] and (id == 1 and 1 or 2) end,
		GetUnitTeam = function(id) return units[id] and units[id].team end,
		GetTeamInfo = function(id) return id, 0, false, false, "arm", id end,
		GetUnitPosition = function(id) if units[id] then return units[id].x, 0, 0 end end,
		GetUnitHealth = function(id) if units[id] then return f.health or 1000, f.health or 1000 end end,
		ValidUnitID = function(id) return units[id] ~= nil end,
		AreTeamsAllied = function(a, b) return a == b end,
		GetGroundHeight = function() return 0 end,
		GetUnitsInCylinder = function(x, z, radius)
			local result = {}
			for _, id in ipairs({ 1, 10, 11 }) do
				if (units[id].x - x)^2 + z^2 <= radius^2 then result[#result + 1] = id end
			end
			return result
		end,
		GetProjectilePosition = function(id) local p = f.projectiles[id]; if p then return p.x, 100, 0 end end,
		GetProjectileVelocity = function() return 10, -1, 0 end,
		GetProjectileTeamID = function() return 1 end,
		SetProjectileTarget = noop, SetProjectileDamages = noop, InsertUnitCmdDesc = noop,
		FindUnitCmdDesc = function() return nil end, Log = noop,
		SpawnCEG = function(name) f.markers[#f.markers + 1] = name end,
		AddUnitDamage = function(id, damage)
			f.hits[#f.hits + 1] = { id = id, damage = damage,
				procTarget = env.GG.RoguelikeWeaponEffects.currentProcTargetID }
		end,
	}
	env.Spring = spring
	spring.DeleteProjectile = function(id)
		f.deleted[#f.deleted + 1] = id; f.projectiles[id] = nil; env.gadget:ProjectileDestroyed(id)
	end
	local nextID = 100
	spring.SpawnProjectile = function(defID, params)
		if f.failSpawn then return nil end
		nextID = nextID + 1
		f.projectiles[nextID] = { x = params.pos[1] }
		f.spawned[#f.spawned + 1] = nextID
		env.gadget:ProjectileCreated(nextID, params.owner, defID)
		return nextID
	end
	local chunk = assert(loadfile(sourcePath, "t", env))
	f.loaded = chunk()
	f.gadget, f.GG = env.gadget, env.GG
	if enabled ~= false then env.gadget:Initialize() end
	function f.tick(frame) f.frame = frame; env.gadget:GameFrame(frame) end
	function f.root(id, defID, x)
		f.projectiles[id] = { x = x or 0 }; env.gadget:ProjectileCreated(id, 1, defID)
	end
	function f.effect(id, x, trigger)
		local bus = env.GG.RoguelikeWeaponEffects
		local event = bus.NewEvent(1, 1, 3)
		local entries = { { id = id, chance = 1, cooldownFrames = 0, trigger = trigger } }
		return bus, event, entries
	end
	return f
end
local function test(name, callback)
	total = total + 1
	local ok, err = pcall(callback)
	if not ok then failures = failures + 1 end
	print((ok and "PASS " or "FAIL ") .. name .. (ok and "" or ": " .. tostring(err)))
end

test("mode off does not install the effect bus", function()
	local f = fixture(false); expect(f.loaded, false); expect(f.GG.RoguelikeWeaponEffects, nil)
end)
test("native primary projectile survives a full tracking budget", function()
	local f = fixture(); f.definitions.limits.maxActivePerPlayer = 1; f.rules[1].roguelike_shop_plasma_extension_level = 1
	f.root(1, 3); f.root(2, 3); expect(#f.deleted, 0)
end)
test("splitter attribution preserves owner, team, depth and root attack", function()
	local f = fixture(); f.root(42, 2, 25)
	local info = f.GG.RoguelikeWeaponEffects.GetDamageAttribution(42)
	expect(info.kind, "splitter"); expect(info.ownerID, 1); expect(info.teamID, 1)
	expect(info.depth, 0); assert(info.rootAttackID ~= nil); expect(info.x, 25)
end)
test("two spawn credits create two split children", function()
	local f = fixture(); f.definitions.limits.maxSpawnsPerFrame = 2
	f.root(1, 2); f.gadget:Explosion(2, 100, 0, 0, 1, 1); expect(#f.spawned, 2)
end)
test("inflight children measure travel from their own origins", function()
	local f = fixture(); local r = f.rules[1]
	r.roguelike_effect_splitter_splitMode = 3; r.roguelike_effect_splitter_depth = 2; r.roguelike_effect_splitter_count = 2
	f.root(1, 2); f.projectiles[1].x = 400; f.tick(1); expect(#f.spawned, 2)
	for _, id in ipairs(f.spawned) do f.projectiles[id].x = 800 end
	f.tick(2); expect(#f.spawned, 6)
end)
test("meteor waits for per-owner capacity without being lost", function()
	local f = fixture(); f.rules[1].roguelike_shop_meteor_weapon_level = 1; f.definitions.limits.maxActivePerPlayer = 1
	f.tick(15); f.root(1, 2); f.tick(60); expect(#f.spawned, 0)
	f.gadget:ProjectileDestroyed(1); f.tick(61); expect(#f.spawned, 1)
end)
test("meteor waits for global capacity without being lost", function()
	local f = fixture(); f.rules[1].roguelike_shop_meteor_weapon_level = 1; f.definitions.limits.maxActiveProjectiles = 1
	f.tick(15); f.root(1, 2); f.tick(60); expect(#f.spawned, 0)
	f.gadget:ProjectileDestroyed(1); f.tick(61); expect(#f.spawned, 1)
end)
test("failed engine spawn remains queued for retry", function()
	local f = fixture(); f.rules[1].roguelike_shop_meteor_weapon_level = 1
	f.tick(15); f.failSpawn = true; f.tick(60); f.failSpawn = false; f.tick(61); expect(#f.spawned, 1)
end)
test("pending aftershocks do not consume the burn-zone-only cap", function()
	local f = fixture()
	for index = 1, 3 do
		local bus, event, entries = f.effect("aftershock")
		bus.OnHit(1, 1, "test", 3, 10, index * 1000, 0, 100, event, entries, 1, 0)
	end
	local bus, event, entries = f.effect("burn_zone")
	bus.OnHit(1, 1, "test", 3, 10, 100, 0, 100, event, entries, 1, 0)
	expect(f.markers[4], "roguelike-effect-burn_zone")
end)
test("default onHit effect cannot be consumed by an onKill callback", function()
	local f = fixture(); local bus, event, entries = f.effect("burst")
	bus.RegisterHit(1, 1, 3, 10, 100, 0, 100, event, entries, 1)
	f.gadget:UnitDestroyed(10, 2, 2, 1, 1, 1, 3); expect(#f.hits, 0)
end)
test("explicit onKill effect still fires exactly once", function()
	local f = fixture(); local bus, event, entries = f.effect("burst", 100, "onKill")
	bus.RegisterHit(1, 1, 3, 10, 100, 0, 100, event, entries, 1)
	f.gadget:UnitDestroyed(10, 2, 2, 1, 1, 1, 3); expect(#f.hits, 1)
	f.gadget:UnitDestroyed(10, 2, 2, 1, 1, 1, 3); expect(#f.hits, 1)
end)
test("projectile proc uses base damage rather than already amplified hit", function()
	local f = fixture(); f.rules[1].roguelike_shop_plasma_extension_level = 1
	f.root(1, 3); f.gadget:UnitDamaged(10, 2, 2, 200, false, 3, 1, 1)
	f.tick(18); assert(#f.hits > 0); expect(f.hits[1].damage, 35)
end)
test("electric orb chains once at its configured chance and draws impact sparks", function()
	local f = fixture(); f.rules[1].roguelike_shop_electric_orb_level = 1
	f.root(50, 5, 25)
	f.gadget:UnitDamaged(10, 2, 2, 240, false, 5, 50, 1)
	expect(#f.hits, 1); expect(f.hits[1].id, 11); expect(f.hits[1].damage, 54)
	expect(#f.markers, 3); expect(f.markers[1], "roguelike-electric-orb-chain")
	f.gadget:UnitDamaged(10, 2, 2, 240, false, 5, 50, 1)
	expect(#f.hits, 1)
	f.root(51, 5, 25); f.gadget:UnitDamaged(10, 2, 2, 240, false, 5, 51, 1)
	expect(#f.hits, 1) -- shared owner chain cooldown
	f.tick(12); f.root(52, 5, 25); f.gadget:UnitDamaged(10, 2, 2, 240, false, 5, 52, 1)
	expect(#f.hits, 2)
end)
test("locked electric orb does not register a chain hit", function()
	local f = fixture()
	f.root(59, 5, 25); f.gadget:UnitDamaged(10, 2, 2, 120, false, 5, 59, 1)
	expect(#f.hits, 0); expect(#f.markers, 0)
end)
test("electric orb does not chain at the 18 percent probability boundary", function()
	local f = fixture(true, 0.18); f.rules[1].roguelike_shop_electric_orb_level = 1
	f.root(60, 5, 25); f.gadget:UnitDamaged(10, 2, 2, 120, false, 5, 60, 1)
	expect(#f.hits, 0); expect(#f.markers, 0)
end)
test("beam proc works without projectile ID and triggers once per reload", function()
	local f = fixture(); f.rules[1].roguelike_shop_sniper_extension_level = 1
	f.gadget:UnitDamaged(10, 2, 2, 200, false, 4, nil, 1)
	f.gadget:UnitDamaged(11, 2, 2, 200, false, 4, nil, 1)
	expect(#f.markers, 1)
	f.tick(29); expect(#f.hits, 0)
	f.tick(30); expect(#f.hits, 2); expect(f.hits[1].damage, 45)
end)
test("boss proc damage is capped and target context is restored", function()
	local f = fixture(); f.health = 20000
	local bus, event, entries = f.effect("burst")
	bus.OnHit(1, 1, "test", 3, 10, 100, 0, 10000, event, entries, 1, 0)
	expect(#f.hits, 1); expect(f.hits[1].damage, 1000)
	expect(f.hits[1].procTarget, 11); expect(bus.currentProcTargetID, nil)
end)
print(string.format("RESULT %d/%d passed (mocked Lua callbacks; not an engine or multiplayer test)", total - failures, total))
if failures > 0 then os.exit(1) end
