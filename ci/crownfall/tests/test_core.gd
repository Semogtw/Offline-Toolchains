extends RefCounted

const STARTER_DECK := [
	"iron_warden", "moss_colossus", "astral_sentinel", "spore_bomber",
	"gearling_trio", "prism_turret", "starfall", "gale_ring"
]

func _result() -> Dictionary:
	return {"assertions": 0, "errors": []}

func _expect(r: Dictionary, condition: bool, message: String) -> void:
	r.assertions += 1
	if not condition:
		r.errors.append(message)

func test_launch_roster_has_24_unique_original_cards() -> Dictionary:
	var r := _result()
	var script = load("res://src/autoload/content_db.gd")
	_expect(r, script != null, "content_db.gd must exist")
	if script == null: return r
	var db = script.new()
	_expect(r, db.load_all("res://data") == OK, "content database should load")
	var cards: Array = db.cards.values()
	_expect(r, cards.size() == 24, "launch roster must contain 24 cards")
	var ids := {}
	var family_counts := {"troop": 0, "structure": 0, "spell": 0}
	for card in cards:
		ids[card.id] = true
		family_counts[card.family] = int(family_counts.get(card.family, 0)) + 1
		_expect(r, int(card.cost) >= 1 and int(card.cost) <= 8, "%s has invalid Arcana cost" % card.id)
	_expect(r, ids.size() == 24, "all card IDs must be unique")
	_expect(r, family_counts.troop == 16, "expected 16 troops")
	_expect(r, family_counts.structure == 4, "expected 4 structures")
	_expect(r, family_counts.spell == 4, "expected 4 spells")
	return r

func test_card_cycle_opens_four_previews_next_and_cycles_played_card() -> Dictionary:
	var r := _result()
	var script = load("res://src/core/card_cycle.gd")
	_expect(r, script != null, "card_cycle.gd must exist")
	if script == null: return r
	var cycle = script.new(STARTER_DECK)
	_expect(r, cycle.hand == STARTER_DECK.slice(0, 4), "opening hand should be first four cards")
	_expect(r, cycle.next_card == STARTER_DECK[4], "fifth card should be previewed")
	var played := STARTER_DECK[1]
	_expect(r, cycle.play(played), "playing a card in hand should succeed")
	_expect(r, cycle.hand == [STARTER_DECK[0], STARTER_DECK[2], STARTER_DECK[3], STARTER_DECK[4]], "hand should refill in cycle order")
	_expect(r, cycle.next_card == STARTER_DECK[5], "next preview should advance")
	_expect(r, cycle.queue.back() == played, "played card should move to queue rear")
	return r

func test_arcana_caps_at_ten_and_rejected_spend_preserves_value() -> Dictionary:
	var r := _result()
	var script = load("res://src/core/arcana.gd")
	_expect(r, script != null, "arcana.gd must exist")
	if script == null: return r
	var pool = script.new(9.8)
	pool.tick(10.0, 1.0)
	_expect(r, is_equal_approx(pool.value, 10.0), "Arcana must cap at 10")
	_expect(r, not pool.try_spend(11), "overspend must be rejected")
	_expect(r, is_equal_approx(pool.value, 10.0), "rejected spend must not change Arcana")
	_expect(r, pool.try_spend(4), "affordable spend should succeed")
	_expect(r, is_equal_approx(pool.value, 6.0), "successful spend should subtract cost")
	return r

func test_battle_clock_enters_overtime_after_regulation_when_tied() -> Dictionary:
	var r := _result()
	var script = load("res://src/core/battle_clock.gd")
	_expect(r, script != null, "battle_clock.gd must exist")
	if script == null: return r
	var clock = script.new()
	clock.tick(119.9)
	_expect(r, is_equal_approx(clock.arcana_multiplier(), 1.0), "normal regulation must use 1x Arcana")
	clock.tick(0.2)
	_expect(r, is_equal_approx(clock.arcana_multiplier(), 2.0), "last regulation minute must use 2x Arcana")
	clock.tick(59.9)
	_expect(r, clock.phase == "overtime", "clock should enter overtime after 180s when unresolved")
	_expect(r, is_equal_approx(clock.arcana_multiplier(), 2.5), "overtime Arcana multiplier should be 2.5x")
	clock.tick(90.0)
	_expect(r, clock.phase == "expired", "overtime must expire after 90s")
	return r

func test_five_leagues_are_defined_and_trophy_lookup_advances() -> Dictionary:
	var r := _result()
	var script = load("res://src/autoload/content_db.gd")
	_expect(r, script != null, "content_db.gd must exist")
	if script == null: return r
	var db = script.new()
	db.load_all("res://data")
	_expect(r, db.leagues.size() == 5, "five leagues must exist")
	_expect(r, db.league_for_trophies(0).name == "Verdant Reach", "starter league should be Verdant Reach")
	_expect(r, db.league_for_trophies(2400).name == "Crownfall Citadel", "high trophies should resolve top league")
	return r

func test_profile_rewards_are_idempotent_and_upgrades_persist_in_state() -> Dictionary:
	var r := _result()
	var script = load("res://src/core/profile.gd")
	_expect(r, script != null, "profile.gd must exist")
	if script == null: return r
	var profile = script.new()
	_expect(r, profile.deck.size() == 8, "starter deck must have eight cards")
	var coins_before: int = profile.coins
	_expect(r, profile.apply_match_reward("match-001", true), "first reward application should succeed")
	_expect(r, profile.coins > coins_before, "winning should grant coins")
	var coins_after: int = profile.coins
	_expect(r, not profile.apply_match_reward("match-001", true), "same match reward must be idempotent")
	_expect(r, profile.coins == coins_after, "duplicate reward must not alter coins")
	profile.coins = 9999
	_expect(r, profile.upgrade_card("iron_warden"), "owned card should be upgradeable")
	_expect(r, int(profile.levels["iron_warden"]) == 2, "upgrade should raise card level")
	var snapshot: Dictionary = profile.to_dict()
	var restored = script.new()
	restored.from_dict(snapshot)
	_expect(r, restored.deck == profile.deck, "deck must survive round trip")
	_expect(r, restored.settings.has("reduced_motion") and restored.settings.has("haptics"), "accessibility settings must be persisted")
	return r

func test_battle_rejects_illegal_deploy_and_spends_atomically() -> Dictionary:
	var r := _result()
	var script = load("res://src/core/battle_sim.gd")
	_expect(r, script != null, "battle_sim.gd must exist")
	if script == null: return r
	var sim = script.new(7)
	var before: float = sim.player_arcana.value
	_expect(r, not sim.deploy("iron_warden", Vector2(300, 500), 0), "ground troop cannot deploy in enemy half")
	_expect(r, is_equal_approx(sim.player_arcana.value, before), "illegal deploy cannot spend Arcana")
	_expect(r, sim.deploy("iron_warden", Vector2(300, 1850), 0), "ground troop should deploy in own half")
	_expect(r, sim.player_arcana.value < before, "legal deploy should spend Arcana")
	_expect(r, sim.deploy("gale_ring", Vector2(540, 650), 0), "spell can target enemy half")
	return r

func test_units_move_fight_and_can_destroy_citadel() -> Dictionary:
	var r := _result()
	var script = load("res://src/core/battle_sim.gd")
	_expect(r, script != null, "battle_sim.gd must exist")
	if script == null: return r
	var sim = script.new(11)
	sim.player_arcana.value = 10.0
	_expect(r, sim.deploy("moss_colossus", Vector2(300, 1290), 0), "colossus deploy should succeed")
	var start_y: float = sim.entities[0].pos.y
	for i in range(120): sim.step(0.1)
	_expect(r, sim.entities.size() > 0, "battle should retain active entities")
	_expect(r, sim.entities[0].pos.y < start_y, "player unit should advance toward enemy")
	var core := sim.get_tower("enemy_core")
	core.hp = 1
	sim.damage_tower("enemy_core", 5, 0)
	_expect(r, sim.finished and sim.winner == 0, "destroying enemy Citadel should immediately win")
	return r

func test_bot_actions_remain_legal_across_personalities_and_difficulties() -> Dictionary:
	var r := _result()
	var script = load("res://src/core/battle_sim.gd")
	_expect(r, script != null, "battle_sim.gd must exist")
	if script == null: return r
	for personality in ["rush", "control", "siege", "balanced"]:
		for difficulty in [0, 1, 2]:
			var sim = script.new(100 + difficulty)
			sim.enemy_arcana.value = 10.0
			var action: Dictionary = sim.choose_bot_action(personality, difficulty)
			_expect(r, action.has("card") and action.has("pos"), "bot must produce a deploy action")
			_expect(r, sim.is_legal_deploy(str(action.card), action.pos, 1), "bot action must be legal")
	return r

func test_swarm_stress_remains_bounded_and_valid() -> Dictionary:
	var r := _result()
	var script = load("res://src/core/battle_sim.gd")
	_expect(r, script != null, "battle_sim.gd must exist")
	if script == null: return r
	var sim = script.new(404)
	for i in range(84):
		sim.spawn_for_test("gearling_trio", i % 2, Vector2(230 + (i % 8) * 80, 900 + (i % 12) * 45))
	for i in range(40): sim.step(0.05)
	_expect(r, sim.entities.size() <= 128, "stress scene must remain within entity safety cap")
	for entity in sim.entities:
		_expect(r, is_finite(entity.pos.x) and is_finite(entity.pos.y), "entity positions must stay finite")
	return r
