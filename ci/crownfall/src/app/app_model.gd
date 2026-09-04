extends RefCounted

func screen_names() -> Array:
	return ["home", "collection", "decks", "missions", "vaults", "exchange", "profile", "battle"]

func tutorial_steps() -> Array:
	return [
		{"card": "iron_warden", "title": "Hold the Line", "hint": "Deploy Iron Warden behind a Guardian Tower."},
		{"card": "moss_colossus", "title": "Build a Push", "hint": "Send Moss Colossus down a lane to pressure structures."},
		{"card": "spore_bomber", "title": "Splash Support", "hint": "Place Spore Bomber behind your frontline."},
		{"card": "prism_turret", "title": "Anchor Defense", "hint": "Drop a Prism Turret on your side to intercept the counter-push."},
		{"card": "gale_ring", "title": "Control Space", "hint": "Cast Gale Ring on grouped enemies to displace them."},
		{"card": "starfall", "title": "Punish Clumps", "hint": "Mark the enemy push with Starfall."},
		{"card": "moss_colossus", "title": "Break the Citadel", "hint": "Finish the lane and destroy the enemy Citadel."}
	]
