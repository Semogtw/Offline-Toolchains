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
	var content_db_script = load("res://src/autoload/content_db.gd")
	_expect(r, content_db_script != null, "content_db.gd must exist")
	if content_db_script == null:
		return r
	var db = content_db_script.new()
	var load_result = db.load_all("res://data")
	_expect(r, load_result == OK, "content database should load")
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
	var cycle_script = load("res://src/core/card_cycle.gd")
	_expect(r, cycle_script != null, "card_cycle.gd must exist")
	if cycle_script == null:
		return r
	var cycle = cycle_script.new(STARTER_DECK)
	_expect(r, cycle.hand == STARTER_DECK.slice(0, 4), "opening hand should be first four cards")
	_expect(r, cycle.next_card == STARTER_DECK[4], "fifth card should be previewed")
	var played := STARTER_DECK[1]
	var ok: bool = cycle.play(played)
	_expect(r, ok, "playing a card in hand should succeed")
	_expect(r, cycle.hand == [STARTER_DECK[0], STARTER_DECK[2], STARTER_DECK[3], STARTER_DECK[4]], "hand should refill in cycle order")
	_expect(r, cycle.next_card == STARTER_DECK[5], "next preview should advance")
	_expect(r, cycle.queue.back() == played, "played card should move to queue rear")
	return r

func test_arcana_caps_at_ten_and_rejected_spend_preserves_value() -> Dictionary:
	var r := _result()
	var arcana_script = load("res://src/core/arcana.gd")
	_expect(r, arcana_script != null, "arcana.gd must exist")
	if arcana_script == null:
		return r
	var pool = arcana_script.new(9.8)
	pool.tick(10.0, 1.0)
	_expect(r, is_equal_approx(pool.value, 10.0), "Arcana must cap at 10")
	var rejected: bool = pool.try_spend(11)
	_expect(r, not rejected, "overspend must be rejected")
	_expect(r, is_equal_approx(pool.value, 10.0), "rejected spend must not change Arcana")
	var accepted: bool = pool.try_spend(4)
	_expect(r, accepted, "affordable spend should succeed")
	_expect(r, is_equal_approx(pool.value, 6.0), "successful spend should subtract cost")
	return r

func test_battle_clock_enters_overtime_after_regulation_when_tied() -> Dictionary:
	var r := _result()
	var clock_script = load("res://src/core/battle_clock.gd")
	_expect(r, clock_script != null, "battle_clock.gd must exist")
	if clock_script == null:
		return r
	var clock = clock_script.new()
	clock.tick(179.9)
	_expect(r, clock.phase == "regulation", "179.9s must still be regulation")
	clock.tick(0.2)
	_expect(r, clock.phase == "overtime", "clock should enter overtime after 180s when unresolved")
	_expect(r, is_equal_approx(clock.arcana_multiplier(), 2.5), "overtime Arcana multiplier should be 2.5x")
	clock.tick(90.0)
	_expect(r, clock.phase == "expired", "overtime must expire after 90s")
	return r

func test_five_leagues_are_defined() -> Dictionary:
	var r := _result()
	var content_db_script = load("res://src/autoload/content_db.gd")
	_expect(r, content_db_script != null, "content_db.gd must exist")
	if content_db_script == null:
		return r
	var db = content_db_script.new()
	var load_result = db.load_all("res://data")
	_expect(r, load_result == OK, "content database should load")
	_expect(r, db.leagues.size() == 5, "five leagues must exist")
	return r
