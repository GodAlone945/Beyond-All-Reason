local medkit = {
	blocking = false,
	destructible = false,
	indestructible = true,
	footprintx = 1,
	footprintz = 1,
	height = 24,
	metal = 0,
	energy = 0,
	reclaimable = false,
	resurrectable = 0,
	object = "Lootboxes/lootboxnanoarmT1.s3o",
	collisionvolumetype = "CylY",
	collisionvolumescales = "12 20 12",
	collisionvolumeoffsets = "0 0 0",
	customparams = {
		model_author = "BAR",
		nohealthbars = true,
		roguelike_medkit = 1,
	},
}

return {
	roguelike_medkit = medkit,
}
