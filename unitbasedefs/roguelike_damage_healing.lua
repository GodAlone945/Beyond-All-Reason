-- Pure rules shared by the Roguelike healing gadget and its regression tests.
local M = {}

function M.EffectiveHealthDamage(beforeHealth, afterHealth)
	beforeHealth = tonumber(beforeHealth) or 0
	afterHealth = tonumber(afterHealth) or 0
	if beforeHealth <= 0 then return 0 end
	return math.max(0, math.min(beforeHealth, beforeHealth - afterHealth))
end

function M.DamageCoefficient(kind, rates)
	rates = rates or {}
	if kind == "direct" then return 1 end
	if kind == "meteor" then return 0.5 end
	if kind == "splitter" then return 0.35 end
	if kind == "area" then return math.max(0, tonumber(rates.area) or 0) end
	if kind == "dot" then return math.max(0, tonumber(rates.dot) or 0) end
	return 0
end

function M.ClampHealing(requested, missingHP, sustainedRemaining, damageTriggeredRemaining)
	local wanted = math.max(0, tonumber(requested) or 0)
	wanted = math.min(wanted, math.max(0, tonumber(missingHP) or 0))
	if sustainedRemaining ~= nil then
		wanted = math.min(wanted, math.max(0, sustainedRemaining))
	end
	if damageTriggeredRemaining ~= nil then
		wanted = math.min(wanted, math.max(0, damageTriggeredRemaining))
	end
	return wanted
end

return M
