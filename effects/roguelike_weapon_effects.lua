return {
	["roguelike-meteor-impact"] = {
		usedefaultexplosions = false,
		groundflash = {
			air = true,
			ground = true,
			water = true,
			count = 1,
			properties = {
				circlealpha = 0.8,
				circlegrowth = 8,
				flashalpha = 0.55,
				flashsize = 150,
				ttl = 18,
				color = { 1, 0.38, 0.12 },
			},
		},
	},
	["roguelike-split-impact"] = {
		usedefaultexplosions = false,
		groundflash = {
			air = true,
			ground = true,
			water = true,
			count = 1,
			properties = {
				circlealpha = 0.28,
				circlegrowth = 3,
				flashalpha = 0.25,
				flashsize = 26,
				ttl = 9,
				color = { 0.35, 0.7, 1 },
			},
		},
	},
	["roguelike-meteor-warning"] = {
		usedefaultexplosions = false,
		groundflash = {
			air = false,
			ground = true,
			water = true,
			count = 1,
			properties = {
				circlealpha = 0.3,
				circlegrowth = 0,
				flashalpha = 0.1,
				flashsize = 220,
				ttl = 45,
				color = { 1, 0.16, 0.06 },
			},
		},
	},
	["roguelike-effect-burn_zone"] = {
		usedefaultexplosions = false,
		groundflash = {
			air = false, ground = true, water = true, count = 1,
			properties = {
				circlealpha = 0.36, circlegrowth = 1, flashalpha = 0.12,
				flashsize = 110, ttl = 20, color = { 1, 0.28, 0.04 },
			},
		},
	},
	["roguelike-effect-aftershock"] = {
		usedefaultexplosions = false,
		groundflash = {
			air = true, ground = true, water = true, count = 1,
			properties = {
				circlealpha = 0.42, circlegrowth = 4, flashalpha = 0.32,
				flashsize = 100, ttl = 12, color = { 1, 0.72, 0.22 },
			},
		},
	},
	["roguelike-effect-delayed_strike"] = {
		usedefaultexplosions = false,
		groundflash = {
			air = false, ground = true, water = true, count = 1,
			properties = {
				circlealpha = 0.32, circlegrowth = 0, flashalpha = 0.18,
				flashsize = 130, ttl = 30, color = { 0.24, 0.76, 1 },
			},
		},
	},
}
