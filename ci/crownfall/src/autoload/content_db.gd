extends RefCounted

var cards: Dictionary = {}
var leagues: Dictionary = {}

func load_all(_root: String = "res://data") -> int:
	cards.clear()
	leagues.clear()
	var roster := [
		_card("iron_warden", "Iron Warden", "troop", 3, 1120, 118, 82.0, 34.0, "A disciplined frontliner whose runic shield flares after taking heavy damage."),
		_card("moss_colossus", "Moss Colossus", "troop", 6, 2650, 142, 48.0, 30.0, "A walking grove that ignores distractions and crushes structures."),
		_card("astral_sentinel", "Astral Sentinel", "troop", 4, 820, 132, 70.0, 190.0, "A hovering marksman that fires star-lances from long range."),
		_card("spore_bomber", "Spore Bomber", "troop", 3, 710, 168, 68.0, 155.0, "Lobs volatile mushroom pods that burst in a small area."),
		_card("gearling_trio", "Gearling Trio", "troop", 3, 360, 78, 104.0, 32.0, "Three clockwork skirmishers that overwhelm isolated targets.", 3),
		_card("dune_lancer", "Dune Lancer", "troop", 4, 980, 154, 92.0, 40.0, "Builds momentum and dashes into its first target."),
		_card("ember_fox", "Ember Fox", "troop", 2, 530, 102, 118.0, 34.0, "A nimble spirit that accelerates after entering combat."),
		_card("tempest_oracle", "Tempest Oracle", "troop", 5, 790, 126, 66.0, 175.0, "Chains lightning between clustered enemies."),
		_card("crystal_witch", "Crystal Witch", "troop", 5, 940, 112, 62.0, 165.0, "Raises tiny crystal shards while firing prism bolts."),
		_card("lumen_swarm", "Lumen Swarm", "troop", 2, 180, 54, 125.0, 26.0, "Five tiny flying lights that shred undefended units.", 5),
		_card("storm_knight", "Storm Knight", "troop", 5, 1420, 176, 84.0, 38.0, "An armored duelist whose charged strike crackles with thunder."),
		_card("root_mender", "Root Mender", "troop", 4, 760, 74, 64.0, 145.0, "A support druid that periodically restores nearby allies."),
		_card("void_manta", "Void Manta", "troop", 4, 960, 138, 78.0, 120.0, "A flying bruiser that glides directly over the river."),
		_card("sunforged_ram", "Sunforged Ram", "troop", 5, 1860, 188, 74.0, 30.0, "A blazing construct focused entirely on enemy structures."),
		_card("rune_duelist", "Rune Duelist", "troop", 3, 690, 146, 108.0, 34.0, "Fast single-target fighter with a short parry window."),
		_card("frost_owl", "Frost Owl", "troop", 3, 580, 94, 86.0, 150.0, "Flying caster whose bolts briefly slow movement."),
		_card("prism_turret", "Prism Turret", "structure", 4, 1280, 122, 0.0, 205.0, "Rotating crystal battery with long defensive reach."),
		_card("thorn_bastion", "Thorn Bastion", "structure", 4, 1640, 82, 0.0, 125.0, "Durable living wall that retaliates against melee attackers."),
		_card("arc_coil", "Arc Coil", "structure", 3, 980, 108, 0.0, 160.0, "Compact coil that zaps the nearest aerial or ground threat."),
		_card("sunwell", "Sunwell", "structure", 5, 1360, 0, 0.0, 0.0, "Support shrine that periodically heals nearby allies."),
		_card("starfall", "Starfall", "spell", 4, 0, 420, 0.0, 125.0, "Marks an area, then drops a delayed stellar impact."),
		_card("gale_ring", "Gale Ring", "spell", 2, 0, 118, 0.0, 135.0, "A circular gust damages and shoves enemies away."),
		_card("bloom_pulse", "Bloom Pulse", "spell", 3, 0, -360, 0.0, 150.0, "Three restorative pulses sustain allies in the target zone."),
		_card("time_shard", "Time Shard", "spell", 3, 0, 86, 0.0, 145.0, "Damages foes and slows their attack rhythm for a moment.")
	]
	for card in roster:
		cards[card.id] = card
	leagues = {
		"verdant": {"name": "Verdant Reach", "min": 0, "sky": Color("243d32"), "ground": Color("385d49"), "accent": Color("7ee081")},
		"ember": {"name": "Ember Foundry", "min": 500, "sky": Color("40262e"), "ground": Color("6b3a32"), "accent": Color("ff9d5c")},
		"tide": {"name": "Tideglass Harbor", "min": 1000, "sky": Color("183a52"), "ground": Color("245d68"), "accent": Color("69d2e7")},
		"astral": {"name": "Astral Archive", "min": 1600, "sky": Color("29264f"), "ground": Color("443d75"), "accent": Color("c5a3ff")},
		"crown": {"name": "Crownfall Citadel", "min": 2300, "sky": Color("3b2d3f"), "ground": Color("64505a"), "accent": Color("ffd66b")}
	}
	return OK

func _card(id: String, name: String, family: String, cost: int, hp: int, damage: int, speed: float, range: float, text: String, count: int = 1) -> Dictionary:
	return {"id": id, "name": name, "family": family, "cost": cost, "hp": hp, "damage": damage, "speed": speed, "range": range, "text": text, "count": count}

func league_for_trophies(trophies: int) -> Dictionary:
	if leagues.is_empty(): load_all()
	var best: Dictionary = leagues["verdant"]
	for league in leagues.values():
		if trophies >= int(league.min) and int(league.min) >= int(best.min):
			best = league
	return best
