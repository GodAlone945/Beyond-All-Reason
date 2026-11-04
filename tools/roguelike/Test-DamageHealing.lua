-- Pure regression checks for effective-damage and lifesteal coefficients.
local rules = assert(loadfile("unitbasedefs/roguelike_damage_healing.lua"))()
local passed, total = 0, 0
local function check(name, condition)
	total = total + 1
	if not condition then error("FAIL " .. name) end
	passed = passed + 1
	print("PASS " .. name)
end

check("1000 HP damage remains 1000", rules.EffectiveHealthDamage(2000, 1000) == 1000)
check("overkill is capped to victim pre-hit HP", rules.EffectiveHealthDamage(50, 0) == 50)
check("healed or unchanged target contributes zero", rules.EffectiveHealthDamage(500, 500) == 0)
check("already-dead target contributes zero", rules.EffectiveHealthDamage(0, 0) == 0)
check("direct coefficient is 1.0", rules.DamageCoefficient("direct") == 1)
check("meteor coefficient is 0.5", rules.DamageCoefficient("meteor") == 0.5)
check("splitter coefficient is 0.35", rules.DamageCoefficient("splitter") == 0.35)
check("area coefficient is locked without its card", rules.DamageCoefficient("area", {}) == 0)
check("area coefficient uses the card value", rules.DamageCoefficient("area", { area = 0.2 }) == 0.2)
check("DoT coefficient is locked without its card", rules.DamageCoefficient("dot", {}) == 0)
check("DoT coefficient uses the card value", rules.DamageCoefficient("dot", { dot = 0.1 }) == 0.1)
check("unrecognized damage is ineligible", rules.DamageCoefficient("environment") == 0)
check("1000 damage at 12% is limited to 60 HP per second at 10k MaxHP",
	rules.ClampHealing(1000 * 0.12, 10000, 150, 60) == 60)
check("kill healing shares the sustained 1.5% budget",
	rules.ClampHealing(60, 10000, 25, nil) == 25)
check("missing HP prevents budget spend at full health", rules.ClampHealing(60, 0, 150, 60) == 0)

print(string.format("RESULT %d/%d passed (pure Lua rules; no Recoil engine callbacks)", passed, total))
