extends RefCounted

var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
    if not condition:
        failures.append(message)

func run_all() -> Array[String]:
    test_deploy_spends_arcana_and_spawns_group()
    test_player_cannot_deploy_troop_on_enemy_half()
    test_spell_can_damage_enemy_tower()
    test_ground_troop_advances_toward_enemy()
    test_destroyed_lane_tower_awards_crown()
    test_ai_returns_legal_affordable_action()
    return failures

func make_sim():
    var script := load("res://src/battle/battle_sim.gd")
    check(script != null, "battle_sim.gd must exist")
    if script == null: return null
    return script.new(CardCatalog.starter_deck(), CardCatalog.starter_deck(), 1337)

func test_deploy_spends_arcana_and_spawns_group() -> void:
    var sim = make_sim()
    if sim == null: return
    sim.player_arcana.value = 10.0
    var before := sim.entities.size()
    check(sim.deploy(0, "gearling_trio", Vector2(320, 1660)), "affordable valid deployment must succeed")
    check(sim.entities.size() == before + 3, "Gearling Trio must spawn exactly three units")
    check(is_equal_approx(sim.player_arcana.value, 7.0), "deployment must spend exact arcana cost")

func test_player_cannot_deploy_troop_on_enemy_half() -> void:
    var sim = make_sim()
    if sim == null: return
    sim.player_arcana.value = 10.0
    check(not sim.deploy(0, "iron_warden", Vector2(320, 700)), "player troop deployment above river must be rejected")
    check(is_equal_approx(sim.player_arcana.value, 10.0), "illegal deployment must not spend arcana")

func test_spell_can_damage_enemy_tower() -> void:
    var sim = make_sim()
    if sim == null: return
    sim.player_arcana.value = 10.0
    var tower_pos: Vector2 = sim.towers[1][0].pos
    var before: float = sim.towers[1][0].hp
    check(sim.deploy(0, "starfall", tower_pos), "spell must allow targeting enemy half")
    check(sim.towers[1][0].hp < before, "Starfall must damage an enemy tower inside its radius")

func test_ground_troop_advances_toward_enemy() -> void:
    var sim = make_sim()
    if sim == null: return
    sim.player_arcana.value = 10.0
    sim.deploy(0, "iron_warden", Vector2(320, 1650))
    var entity_id: int = sim.entities[-1].uid
    var y_before: float = sim.entity_by_uid(entity_id).pos.y
    sim.step(1.0)
    var unit: Dictionary = sim.entity_by_uid(entity_id)
    check(not unit.is_empty() and unit.pos.y < y_before, "player troop must advance upward toward enemy")

func test_destroyed_lane_tower_awards_crown() -> void:
    var sim = make_sim()
    if sim == null: return
    sim.player_arcana.value = 10.0
    sim.debug_set_tower_hp(1, 0, 100.0)
    sim.deploy(0, "starfall", sim.towers[1][0].pos)
    sim.step(0.01)
    check(sim.player_crowns == 1, "destroying one lane tower must award one crown")
    check(not sim.towers[1][0].alive, "destroyed tower must remain marked dead")

func test_ai_returns_legal_affordable_action() -> void:
    var ai_script := load("res://src/battle/battle_ai.gd")
    check(ai_script != null, "battle_ai.gd must exist")
    var sim = make_sim()
    if ai_script == null or sim == null: return
    sim.enemy_arcana.value = 10.0
    var ai = ai_script.new(99)
    var action: Dictionary = ai.choose_action(sim)
    check(not action.is_empty(), "AI with full arcana must choose an action")
    if action.is_empty(): return
    var card := CardCatalog.get_card(String(action.get("card_id", "")))
    check(not card.is_empty() and int(card.cost) <= int(sim.enemy_arcana.value), "AI action must be affordable")
    check(int(action.get("side", -1)) == 1, "AI must deploy for enemy side")
