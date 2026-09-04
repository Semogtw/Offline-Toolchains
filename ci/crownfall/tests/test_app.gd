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
