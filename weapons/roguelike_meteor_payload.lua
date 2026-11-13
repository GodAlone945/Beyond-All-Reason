local modOptions = BAR.GetModOptionsCopy and BAR.GetModOptionsCopy() or {}
local roguelikeMode = modOptions.roguelike_mode

if roguelikeMode ~= true and roguelikeMode ~= 1 and roguelikeMode ~= "1" and roguelikeMode ~= "true" then
	return {}
end

return {
	roguelike_test_meteor_payload = {
		name = "Roguelike Meteor Payload",
		weapontype = "Cannon",
		range = 900,
		reloadtime = 1,
		areaofeffect = 260,
		weaponvelocity = 600,
		flighttime = 3,
		gravityaffected = "true",
		model = "meteor.s3o",
		cegtag = "roguelike-meteortrail",
		impactonly = true,
		noselfdamage = true,
		avoidfriendly = true,
		collidefriendly = false,
		edgeeffectiveness = 0.65,
		explosiongenerator = "custom:roguelike-meteor-impact",
		damage = { default = 500, subs = 300, vtol = 250 },
		customparams = { roguelike_weapon_effect = "meteor_payload" },
	},
}
