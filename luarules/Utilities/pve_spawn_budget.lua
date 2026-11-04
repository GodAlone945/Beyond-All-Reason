local SpawnBudget = {}

function SpawnBudget.GetHumanTeams(enemyTeamID)
	local teams = {}
	local teamCount = 0
	for _, playerID in ipairs(Spring.GetPlayerList()) do
		local _, _, spectator, teamID = Spring.GetPlayerInfo(playerID, false)
		if not spectator and teamID ~= enemyTeamID and not teams[teamID] then
			teams[teamID] = true
			teamCount = teamCount + 1
		end
	end
	return teams, teamCount
end

function SpawnBudget.PlayerScaledCaps(enemyTeamID, combatMax, structureCap, bossCap, budgetMultiplier, teamCap)
	local _, teamCount = SpawnBudget.GetHumanTeams(enemyTeamID)
	teamCount = math.max(1, math.min(teamCount, 16))
	local combatCap = math.ceil(combatMax * (0.125 + 0.875 * (teamCount - 1) / 15))
	return {
		total = teamCap,
		combat = combatCap,
		structure = structureCap,
		boss = bossCap,
		weight = math.ceil(combatCap * budgetMultiplier),
	}
end

function SpawnBudget.New(teamID, caps)
	local active = { combat = 0, heavy = 0, structure = 0, boss = 0, weight = 0 }
	local reserved = { combat = 0, heavy = 0, structure = 0, boss = 0, weight = 0 }
	local tracked = {}
	local classes = {}

	local function classify(unitDefID)
		local class = classes[unitDefID]
		if class then
			return class[1], class[2]
		end
		local def = UnitDefs[unitDefID]
		if not def then
			return nil
		end
		local customParams = def.customParams or {}
		local kind, weight
		if customParams.ispvefinalboss then
			kind, weight = "boss", 0
		elseif def.isBuilding or not def.canMove then
			kind, weight = "structure", 0
		else
			kind = "combat"
			local metalCost = def.metalCost or 0
			if metalCost <= 100 then
				weight = 1
			elseif metalCost <= 500 then
				weight = 2
			elseif metalCost <= 2000 then
				weight = 5
			else
				weight = 8
			end
		end
		classes[unitDefID] = { kind, weight }
		return kind, weight
	end

	local function add(unitID, unitDefID)
		if tracked[unitID] then
			return
		end
		local kind, weight = classify(unitDefID)
		if kind then
			tracked[unitID] = { kind, weight }
			active[kind] = active[kind] + 1
			active.weight = active.weight + weight
			if kind == "combat" and weight >= 5 then
				active.heavy = active.heavy + 1
			end
		end
	end

	local function remove(unitID)
		local class = tracked[unitID]
		if class then
			active[class[1]] = active[class[1]] - 1
			active.weight = active.weight - class[2]
			if class[1] == "combat" and class[2] >= 5 then
				active.heavy = active.heavy - 1
			end
			tracked[unitID] = nil
		end
	end

	for _, unitID in ipairs(Spring.GetTeamUnits(teamID)) do
		add(unitID, Spring.GetUnitDefID(unitID))
	end

	local budget = {}

	function budget.CanCreate(unitDefID)
		local kind, weight = classify(unitDefID)
		if not kind then
			return false
		end
		local totalReserved = reserved.combat + reserved.structure + reserved.boss
		if budget.GetTotalActive() + totalReserved >= caps.total or active[kind] + reserved[kind] >= caps[kind] then
			return false
		end
		return kind ~= "combat" or active.weight + reserved.weight + weight <= caps.weight
	end

	function budget.Reserve(spawn)
		local def = UnitDefNames[spawn.unitName]
		local kind, weight
		if def then
			kind, weight = classify(def.id)
		end
		if not kind or active[kind] + reserved[kind] >= caps[kind] then
			return false
		end
		if kind == "combat" and active.weight + reserved.weight + weight > caps.weight then
			return false
		end
		spawn.pveBudgetKind = kind
		spawn.pveBudgetWeight = weight
		reserved[kind] = reserved[kind] + 1
		reserved.weight = reserved.weight + weight
		if kind == "combat" and weight >= 5 then
			reserved.heavy = reserved.heavy + 1
		end
		return true
	end

	function budget.Release(spawn)
		local kind = spawn.pveBudgetKind
		if kind then
			reserved[kind] = reserved[kind] - 1
			reserved.weight = reserved.weight - spawn.pveBudgetWeight
			if kind == "combat" and spawn.pveBudgetWeight >= 5 then
				reserved.heavy = reserved.heavy - 1
			end
			spawn.pveBudgetKind = nil
			spawn.pveBudgetWeight = nil
		end
	end

	function budget.ConsumeReservation(spawn)
		budget.Release(spawn)
	end

	function budget.ClearReservations()
		reserved.combat, reserved.heavy, reserved.structure, reserved.boss, reserved.weight = 0, 0, 0, 0, 0
	end

	function budget.UnitCreated(unitID, unitDefID, unitTeam)
		if unitTeam == teamID then
			add(unitID, unitDefID)
		end
	end

	function budget.UnitDestroyed(unitID)
		remove(unitID)
	end

	function budget.UnitGiven(unitID, unitDefID, newTeam, oldTeam)
		if oldTeam == teamID then
			remove(unitID)
		end
		if newTeam == teamID then
			add(unitID, unitDefID)
		end
	end

	function budget.GetCounts()
		return active, reserved
	end

	function budget.GetTotalActive()
		return active.combat + active.structure + active.boss
	end

	function budget.Publish(prefix, queueCount)
		local totalReserved = reserved.combat + reserved.structure + reserved.boss
		local available = math.min(
			caps.combat - active.combat - reserved.combat,
			caps.total - budget.GetTotalActive() - totalReserved,
			caps.weight - active.weight - reserved.weight
		)
		Spring.SetGameRulesParam(prefix .. "CombatCount", active.combat)
		Spring.SetGameRulesParam(prefix .. "HeavyCount", active.heavy)
		Spring.SetGameRulesParam(prefix .. "StructureCount", active.structure)
		Spring.SetGameRulesParam(prefix .. "BossCount", active.boss)
		Spring.SetGameRulesParam(prefix .. "SpawnQueueCount", queueCount)
		Spring.SetGameRulesParam(prefix .. "AvailableSpawns", math.max(0, available))
		Spring.SetGameRulesParam(prefix .. "CombatWeight", active.weight)
	end

	return budget
end

return SpawnBudget
