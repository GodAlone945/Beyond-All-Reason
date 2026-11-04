-- Pure-rule microbenchmark; excludes Spring/Recoil callins, UnitDefs and healing writes.
local rules = assert(loadfile("unitbasedefs/roguelike_damage_healing.lua"))()
local count = tonumber(arg[1]) or 100000
local started = os.clock()
local checksum = 0
for i = 1, count do
	checksum = checksum + rules.EffectiveHealthDamage(1000, 750)
	checksum = checksum + rules.DamageCoefficient(i % 4 == 0 and "splitter" or "direct", {})
end
local elapsed = os.clock() - started
print(string.format("RESULT calls=%d elapsed=%.6fs calls_per_second=%.0f checksum=%.0f (pure Lua only)",
	count * 2, elapsed, elapsed > 0 and count * 2 / elapsed or 0, checksum))
