extends RefCounted

func _result() -> Dictionary:
	return {"assertions": 0, "errors": []}

func _expect(r: Dictionary, condition: bool, message: String) -> void:
	r.assertions += 1
	if not condition: r.errors.append(message)

func test_app_model_exposes_complete_navigation_and_tutorial() -> Dictionary:
	var r := _result()
	var script = load("res://src/app/app_model.gd")
	_expect(r, script != null, "app_model.gd must exist")
	if script == null: return r
	var model = script.new()
	var screens: Array = model.screen_names()
	for expected in ["home", "collection", "decks", "missions", "vaults", "exchange", "profile", "battle"]:
		_expect(r, expected in screens, "navigation must include %s" % expected)
	var steps: Array = model.tutorial_steps()
	_expect(r, steps.size() == 7, "tutorial must contain seven action-driven steps")
	_expect(r, str(steps[0].card) == "iron_warden", "tutorial should begin with Iron Warden")
	_expect(r, str(steps[5].card) == "starfall", "tutorial should teach Starfall before the finale")
	return r

func test_main_scene_is_loadable_and_root_is_control() -> Dictionary:
	var r := _result()
	var scene = load("res://src/app/main.tscn")
	_expect(r, scene != null, "main.tscn must load")
	if scene == null: return r
	var instance = scene.instantiate()
	_expect(r, instance is Control, "main scene root must be a Control")
	_expect(r, instance.has_method("start_battle"), "main scene must expose start_battle")
	_expect(r, instance.has_method("show_screen"), "main scene must expose screen navigation")
	instance.free()
	return r

func test_main_controller_exposes_interactive_mobile_shell() -> Dictionary:
	var r := _result()
	var scene = load("res://src/app/main.tscn")
	_expect(r, scene != null, "main scene must exist")
	if scene == null: return r
	var instance = scene.instantiate()
	_expect(r, instance.has_method("ui_snapshot"), "main controller must expose ui_snapshot")
	_expect(r, instance.has_method("select_card"), "main controller must expose card selection")
	_expect(r, instance.has_method("deploy_selected"), "main controller must expose deployment")
	_expect(r, instance.has_method("tick_battle"), "main controller must expose deterministic battle ticking")
	if not instance.has_method("ui_snapshot"):
		instance.free()
		return r
	instance.call("_ready")
	var snap: Dictionary = instance.ui_snapshot()
	_expect(r, str(snap.get("screen", "")) == "home", "app should open on home")
	_expect(r, int(snap.get("nav_items", 0)) >= 5, "mobile shell should expose at least five primary nav items")
	_expect(r, int(snap.get("coins", 0)) >= 0, "top bar snapshot must expose coins")
	_expect(r, instance.get_node_or_null("TopBar") != null, "top resource bar must be built")
	_expect(r, instance.get_node_or_null("BottomNav") != null, "bottom navigation must be built")
	instance.free()
	return r

func test_main_controller_runs_card_cycle_and_real_deploy() -> Dictionary:
	var r := _result()
	var scene = load("res://src/app/main.tscn")
	if scene == null:
		_expect(r, false, "main scene must exist")
		return r
	var instance = scene.instantiate()
	instance.call("_ready")
	instance.start_battle(true)
	var before: Dictionary = instance.ui_snapshot()
	_expect(r, str(before.get("screen", "")) == "battle", "start_battle must enter battle screen")
	var hand_before: Array = before.get("hand", [])
	_expect(r, hand_before.size() == 4, "battle must expose a four-card hand")
	_expect(r, instance.select_card(0), "first card should be selectable")
	var deployed: bool = instance.deploy_selected(Vector2(300, 1700))
	_expect(r, deployed, "selected starter card should deploy on legal player territory")
	var after: Dictionary = instance.ui_snapshot()
	_expect(r, int(after.get("entities", 0)) > 0, "successful deploy must create battle entities")
	var hand_after: Array = after.get("hand", [])
	_expect(r, hand_after.size() == 4, "hand must refill after a play")
	_expect(r, hand_after != hand_before, "played card must rotate through deck cycle")
	instance.tick_battle(0.25)
	_expect(r, float(instance.ui_snapshot().get("elapsed", 0.0)) > 0.0, "battle tick must advance simulation time")
	instance.free()
	return r

func test_secondary_screens_are_reachable_without_reinitializing_profile() -> Dictionary:
	var r := _result()
	var scene = load("res://src/app/main.tscn")
	if scene == null:
		_expect(r, false, "main scene must exist")
		return r
	var instance = scene.instantiate()
	instance.call("_ready")
	var starting_coins: int = int(instance.ui_snapshot().get("coins", -1))
	for screen_name in ["collection", "decks", "missions", "vaults", "exchange", "profile", "home"]:
		_expect(r, instance.show_screen(screen_name), "screen %s should be reachable" % screen_name)
		_expect(r, str(instance.ui_snapshot().get("screen", "")) == screen_name, "snapshot should reflect %s" % screen_name)
	_expect(r, int(instance.ui_snapshot().get("coins", -2)) == starting_coins, "navigation must preserve profile state")
	instance.free()
	return r
