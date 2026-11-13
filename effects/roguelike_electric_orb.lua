return {
	["roguelike-electric-orb-trail"] = {
		usedefaultexplosions = false,
		halo = {
			air = true, ground = true, water = true, underwater = true,
			class = [[CBitmapMuzzleFlame]], count = 1,
			properties = {
				colormap = [[0.35 0.75 1 0.035   0.55 0.9 1 0.015   0 0 0 0]],
				dir = [[dir]], frontoffset = 0,
				fronttexture = [[glow2]], sidetexture = [[lightninginair]],
				length = 0, size = 20, sizegrowth = 0, ttl = 1,
				useairlos = true,
			},
		},
		core = {
			air = true, ground = true, water = true, underwater = true,
			class = [[CSimpleParticleSystem]], count = 1,
			properties = {
				airdrag = 1, colormap = [[0.35 0.75 1 0.07   0.1 0.4 1 0.035   0 0 0 0]],
				directional = false, emitrot = 0, emitrotspread = 180,
				emitvector = [[0, 1, 0]], gravity = [[0, 0, 0]],
				numparticles = 1, particlelife = 1, particlesize = 14,
				particlespeed = 0, pos = [[0, 0, 0]], sizegrowth = 0,
				texture = [[glow2]],
			},
		},
		arcs = {
			air = true, ground = true, water = true, underwater = true,
			class = [[CSimpleParticleSystem]], count = 1,
			properties = {
				-- Bright, short-lived lightning flecks around the orb body; the halo stays faint.
				airdrag = 1, colormap = [[0.55 0.9 1 0.72   0.25 0.65 1 0.48   0 0 0 0]],
				directional = false, emitrot = 0, emitrotspread = 180,
				emitvector = [[0, 1, 0]], gravity = [[0, 0, 0]],
				numparticles = 5, particlelife = 3, particlelifespread = 1,
				particlesize = 12, particlesizespread = 3, particlespeed = 0.8,
				pos = [[-3 r9, -3 r9, -3 r9]], sizegrowth = -1,
				texture = [[lightninginair]],
			},
		},
	},
	["roguelike-electric-orb-chain"] = {
		usedefaultexplosions = false,
		spark = {
			air = true, ground = true, water = true, underwater = true,
			class = [[CSimpleParticleSystem]], count = 1,
			properties = {
				airdrag = 1, colormap = [[0.7 0.9 1 0.12   0.2 0.6 1 0.05   0 0 0 0]],
				directional = false, emitrot = 0, emitrotspread = 180,
				emitvector = [[0, 1, 0]], gravity = [[0, 0, 0]],
				numparticles = 2, particlelife = 4, particlelifespread = 1,
				particlesize = 12, particlesizespread = 3, particlespeed = 0,
				pos = [[-3 r6, -3 r6, -3 r6]], sizegrowth = -1,
				texture = [[lightninginair]],
			},
		},
	},
}
