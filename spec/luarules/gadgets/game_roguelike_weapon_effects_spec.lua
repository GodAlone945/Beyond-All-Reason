local effects = require("unitbasedefs.roguelike_weapon_effects")

describe("Roguelike weapon effect prototypes", function()
	it("defines a ground targeted meteor command and an engine splitter projectile", function()
		assert.equal("Meteor Strike", effects.testWeapons.meteor.command.name)
		assert.equal(900, effects.testWeapons.meteor.command.range)
		assert.equal("MissileLauncher", effects.testWeapons.splitter.weapontype)
		assert.is_true(effects.limits.warningFrames > 0)
	end)

	it("bounds recursive projectiles and per-frame work", function()
		assert.is_true(effects.limits.maxDepth > 0)
		assert.is_true(effects.limits.maxDepth <= 3)
		assert.is_true(effects.limits.maxActiveProjectiles > 0)
		assert.is_true(effects.limits.maxActivePerPlayer <= effects.limits.maxActiveProjectiles)
		assert.is_true(effects.limits.maxSpawnsPerFrame > 0)
	end)

	it("provides upgrade data independently for both effects", function()
		for _, key in ipairs({ "count", "radius", "interval", "damage", "split" }) do
			assert.is_table(effects.upgrades.meteor[key])
		end
		for _, key in ipairs({ "count", "depth", "homing", "damageFalloff", "splitMode" }) do
			assert.is_table(effects.upgrades.splitter[key])
		end
		assert.same({ "impact", "timed", "inflight" }, effects.upgrades.splitter.splitMode.values)
	end)
end)
