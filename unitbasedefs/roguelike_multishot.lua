-- Explicit first-phase allowlist. angleDegrees is the angular gap between adjacent shots.
-- Extend only after live validation per weapon.
local eligible = {
	plasma_weapon = { type = "Cannon", angleDegrees = 20 },
	shockwave_weapon = { type = "Cannon", angleDegrees = 20 },
}

return {
	armcom = {
		plasma_weapon = eligible.plasma_weapon,
		shockwave_weapon = eligible.shockwave_weapon,
		electric_orb = { type = "Cannon", angleDegrees = 20 },
	},
	corcom = eligible,
	legcom = eligible,
	maxProjectiles = 9,
	maxExtraPerFrame = 16, -- two commanders firing nine projectiles in one frame
}
