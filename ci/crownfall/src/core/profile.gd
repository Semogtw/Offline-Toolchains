extends RefCounted

const STARTER_DECK := [
	"iron_warden", "moss_colossus", "astral_sentinel", "spore_bomber",
	"gearling_trio", "prism_turret", "starfall", "gale_ring"
]

var coins: int = 1200
var trophies: int = 0
var account_level: int = 1
var xp: int = 0
var deck: Array = STARTER_DECK.duplicate()
var decks: Array = []
var levels: Dictionary = {}
var rewarded_matches: Dictionary = {}
var vaults: Array = []
var missions: Array = []
var settings: Dictionary = {}

func _init() -> void:
	decks = [deck.duplicate(), deck.duplicate(), deck.duplicate()]
	for card_id in [
		"iron_warden", "moss_colossus", "astral_sentinel", "spore_bomber", "gearling_trio", "prism_turret", "starfall", "gale_ring",
		"dune_lancer", "ember_fox", "tempest_oracle", "crystal_witch", "lumen_swarm", "storm_knight", "root_mender", "void_manta",
		"sunforged_ram", "rune_duelist", "frost_owl", "thorn_bastion", "arc_coil", "sunwell", "bloom_pulse", "time_shard"
	]:
		levels[card_id] = 1
	vaults = [
		{"kind": "Verdant Seed", "ready": true, "coins": 180},
		{"kind": "Astral Seed", "ready": false, "coins": 320},
		{"kind": "Crown Seed", "ready": false, "coins": 520}
	]
	missions = [
		{"id": "play_8", "title": "Deploy 8 cards", "progress": 0, "goal": 8, "reward": 140, "claimed": false},
		{"id": "win_2", "title": "Win 2 battles", "progress": 0, "goal": 2, "reward": 260, "claimed": false},
		{"id": "spell_4", "title": "Cast 4 spells", "progress": 0, "goal": 4, "reward": 180, "claimed": false}
	]
	settings = {
		"master": 1.0,
		"music": 0.7,
		"sfx": 0.9,
		"haptics": true,
		"reduced_motion": false,
		"screen_shake": true,
		"high_contrast": false,
		"battery_saver": false
	}

func apply_match_reward(match_id: String, won: bool) -> bool:
	if match_id.is_empty() or rewarded_matches.has(match_id):
		return false
	rewarded_matches[match_id] = true
	if won:
		coins += 120
		trophies += 28
		xp += 55
		_increment_mission("win_2", 1)
	else:
		coins += 45
		trophies = maxi(0, trophies - 10)
		xp += 24
	while xp >= account_level * 140:
		xp -= account_level * 140
		account_level += 1
	return true

func record_deploy(card_family: String) -> void:
	_increment_mission("play_8", 1)
	if card_family == "spell":
		_increment_mission("spell_4", 1)

func _increment_mission(id: String, amount: int) -> void:
	for mission in missions:
		if str(mission.id) == id:
			mission.progress = mini(int(mission.goal), int(mission.progress) + amount)
			return

func claim_mission(id: String) -> bool:
	for mission in missions:
		if str(mission.id) == id and not bool(mission.claimed) and int(mission.progress) >= int(mission.goal):
			mission.claimed = true
			coins += int(mission.reward)
			return true
	return false

func claim_vault(index: int) -> bool:
	if index < 0 or index >= vaults.size(): return false
	var vault: Dictionary = vaults[index]
	if not bool(vault.get("ready", false)): return false
	coins += int(vault.get("coins", 0))
	vault.ready = false
	return true

func upgrade_card(card_id: String) -> bool:
	if not levels.has(card_id): return false
	var level: int = int(levels[card_id])
	if level >= 10: return false
	var cost: int = 90 + level * 70
	if coins < cost: return false
	coins -= cost
	levels[card_id] = level + 1
	return true

func to_dict() -> Dictionary:
	return {
		"version": 1,
		"coins": coins,
		"trophies": trophies,
		"account_level": account_level,
		"xp": xp,
		"deck": deck.duplicate(),
		"decks": decks.duplicate(true),
		"levels": levels.duplicate(true),
		"rewarded_matches": rewarded_matches.duplicate(true),
		"vaults": vaults.duplicate(true),
		"missions": missions.duplicate(true),
		"settings": settings.duplicate(true)
	}

func from_dict(data: Dictionary) -> void:
	coins = int(data.get("coins", coins))
	trophies = maxi(0, int(data.get("trophies", trophies)))
	account_level = maxi(1, int(data.get("account_level", account_level)))
	xp = maxi(0, int(data.get("xp", xp)))
	var incoming_deck: Array = data.get("deck", deck)
	if incoming_deck.size() == 8:
		deck = incoming_deck.duplicate()
	decks = data.get("decks", decks).duplicate(true)
	levels.merge(data.get("levels", {}), true)
	rewarded_matches = data.get("rewarded_matches", {}).duplicate(true)
	vaults = data.get("vaults", vaults).duplicate(true)
	missions = data.get("missions", missions).duplicate(true)
	settings.merge(data.get("settings", {}), true)
