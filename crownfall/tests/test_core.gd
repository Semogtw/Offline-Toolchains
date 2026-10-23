extends RefCounted

var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
    if not condition:
        failures.append(message)

func run_all() -> Array[String]:
    test_card_catalog_contract()
    test_card_cycle_contract()
    test_arcana_contract()
    test_battle_clock_contract()
    test_progression_contract()
    return failures

func test_card_catalog_contract() -> void:
    var script := load("res://src/core/card_catalog.gd")
    check(script != null, "card_catalog.gd must exist")
    if script == null: return
    var cards: Array = script.all_cards()
    check(cards.size() == 24, "catalog must contain exactly 24 cards")
    var ids := {}
    var counts := {"troop": 0, "structure": 0, "spell": 0}
    for card in cards:
        var id := String(card.get("id", ""))
        check(not id.is_empty() and not ids.has(id), "every card id must be unique")
        ids[id] = true
        check(int(card.get("cost", 0)) >= 1 and int(card.get("cost", 0)) <= 8, "card costs must be 1..8")
        var kind := String(card.get("type", ""))
        if counts.has(kind): counts[kind] += 1
    check(counts["troop"] == 16, "catalog must have 16 troops")
    check(counts["structure"] == 4, "catalog must have 4 structures")
    check(counts["spell"] == 4, "catalog must have 4 spells")
    check(script.starter_deck() == ["iron_warden", "moss_colossus", "astral_sentinel", "spore_bomber", "gearling_trio", "prism_turret", "starfall", "gale_ring"], "starter deck must match design")

func test_card_cycle_contract() -> void:
    var script := load("res://src/core/card_cycle.gd")
    check(script != null, "card_cycle.gd must exist")
    if script == null: return
    var cycle = script.new(["a","b","c","d","e","f","g","h"])
    check(cycle.hand() == ["a","b","c","d"], "opening hand must be first four cards")
    check(cycle.next_card() == "e", "fifth card must be previewed next")
    check(cycle.play(1) == "b", "play must return selected card")
    check(cycle.hand() == ["a","e","c","d"], "played slot must receive next card")
    check(cycle.next_card() == "f", "cycle must advance after play")

func test_arcana_contract() -> void:
    var script := load("res://src/core/arcana.gd")
    check(script != null, "arcana.gd must exist")
    if script == null: return
    var arcana = script.new(5.0)
    arcana.advance(14.0, 1.0)
    check(is_equal_approx(arcana.value, 10.0), "arcana must cap at 10")
    check(arcana.spend(4), "spending affordable arcana must succeed")
    check(is_equal_approx(arcana.value, 6.0), "spend must subtract exact cost")
    check(not arcana.spend(8), "overspending must fail")
    check(is_equal_approx(arcana.value, 6.0), "failed spend must preserve value")

func test_battle_clock_contract() -> void:
    var script := load("res://src/core/battle_clock.gd")
    check(script != null, "battle_clock.gd must exist")
    if script == null: return
    var clock = script.new()
    clock.advance(120.0)
    check(is_equal_approx(clock.arcana_multiplier(), 2.0), "final 60 seconds must use 2x arcana")
    clock.advance(60.0)
    check(clock.in_overtime, "clock must enter overtime after 180 seconds")
    check(is_equal_approx(clock.arcana_multiplier(), 2.5), "overtime must use 2.5x arcana")
    clock.advance(90.0)
    check(clock.finished, "overtime must finish after 90 seconds")

func test_progression_contract() -> void:
    var script := load("res://src/core/progression.gd")
    check(script != null, "progression.gd must exist")
    if script == null: return
    check(script.leagues().size() == 5, "v1 must ship five leagues")
    var profile: Dictionary = script.default_profile()
    check(int(profile.get("trophies", -1)) == 0 and int(profile.get("coins", 0)) >= 500, "new profile must start ready to play")
    check(Array(profile.get("deck", [])).size() == 8, "new profile must have an eight-card deck")
