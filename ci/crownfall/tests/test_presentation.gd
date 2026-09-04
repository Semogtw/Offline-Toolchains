extends RefCounted

func _result() -> Dictionary:
	return {"assertions": 0, "errors": []}

func _expect(r: Dictionary, condition: bool, message: String) -> void:
	r.assertions += 1
	if not condition:
		r.errors.append(message)

func _load_view_script():
	if not FileAccess.file_exists("res://src/presentation/battle_view.gd"):
		return null
	return load("res://src/presentation/battle_view.gd")

func test_presentation_layer_exposes_rich_visual_contract() -> Dictionary:
	var r := _result()
	var script = _load_view_script()
	_expect(r, script != null, "battle_view.gd must exist")
	if script == null:
		return r
	var view = script.new()
	_expect(r, view is Control, "battle presentation must be a Control")
	for method_name in ["bind_context", "sync_from_sim", "advance_visuals", "presentation_snapshot", "visual_profile", "configure_accessibility", "trigger_impact"]:
		_expect(r, view.has_method(method_name), "presentation must expose %s" % method_name)
	view.free()
	return r

func test_visual_profiles_create_distinct_unit_silhouettes() -> Dictionary:
	var r := _result()
	var script = _load_view_script()
	if script == null:
		_expect(r, false, "battle_view.gd must exist before checking silhouettes")
		return r
	var view = script.new()
	var signatures: Dictionary = {}
	for card_id in ["iron_warden", "moss_colossus", "astral_sentinel", "spore_bomber", "gearling_trio", "prism_turret", "ember_fox", "void_manta"]:
		var profile: Dictionary = view.visual_profile(card_id)
		_expect(r, not profile.is_empty(), "%s must have a visual profile" % card_id)
		_expect(r, profile.has("silhouette"), "%s profile must define silhouette" % card_id)
		_expect(r, profile.has("motion"), "%s profile must define motion" % card_id)
		_expect(r, profile.has("weapon"), "%s profile must define weapon" % card_id)
		var signature := "%s:%s:%s" % [str(profile.get("silhouette", "")), str(profile.get("motion", "")), str(profile.get("weapon", ""))]
		signatures[signature] = true
	_expect(r, signatures.size() >= 6, "sample roster must produce at least six visibly distinct archetypes")
	view.free()
	return r

func test_visual_state_interpolates_and_reacts_to_damage() -> Dictionary:
	var r := _result()
	var script = _load_view_script()
	if script == null:
		_expect(r, false, "battle_view.gd must exist before checking animation")
		return r
	var battle_script = load("res://src/core/battle_sim.gd")
	var db_script = load("res://src/autoload/content_db.gd")
	var profile_script = load("res://src/core/profile.gd")
	var battle = battle_script.new(42)
	var db = db_script.new()
	db.load_all()
	var profile = profile_script.new()
	battle.spawn_for_test("iron_warden", battle.PLAYER, Vector2(300, 1700))
	var view = script.new()
	view.bind_context(battle, null, db, profile, false)
	view.sync_from_sim()
	var first: Dictionary = view.presentation_snapshot()
	_expect(r, int(first.get("visual_units", 0)) == 1, "sync must create one visual unit")
	var unit_before: Dictionary = first.get("units", [])[0]
	var before_pos: Vector2 = unit_before.get("render_pos", Vector2.ZERO)
	battle.entities[0].pos += Vector2(0, -140)
	battle.entities[0].hp -= 100
	view.sync_from_sim()
	var after_sync: Dictionary = view.presentation_snapshot()
	var synced_unit: Dictionary = after_sync.get("units", [])[0]
	_expect(r, float(synced_unit.get("hit_flash", 0.0)) > 0.0, "damage must trigger hit flash")
	_expect(r, int(after_sync.get("fx", 0)) > 0, "damage must emit impact particles")
	view.advance_visuals(0.05)
	var after_move: Dictionary = view.presentation_snapshot()
	var moved_unit: Dictionary = after_move.get("units", [])[0]
	var moved_pos: Vector2 = moved_unit.get("render_pos", Vector2.ZERO)
	var target_pos: Vector2 = moved_unit.get("target_pos", Vector2.ZERO)
	_expect(r, moved_pos.distance_to(before_pos) > 0.1, "render position must move toward simulation position")
	_expect(r, moved_pos.distance_to(target_pos) > 0.1, "movement must be interpolated rather than teleporting")
	view.free()
	return r

func test_reduced_motion_disables_camera_shake_but_keeps_feedback() -> Dictionary:
	var r := _result()
	var script = _load_view_script()
	if script == null:
		_expect(r, false, "battle_view.gd must exist before accessibility checks")
		return r
	var view = script.new()
	view.configure_accessibility({"reduced_motion": true, "screen_shake": true, "high_contrast": false})
	view.trigger_impact(Vector2(540, 900), 1.0, Color.WHITE)
	var snap: Dictionary = view.presentation_snapshot()
	_expect(r, float(snap.get("shake", 1.0)) == 0.0, "reduced motion must suppress camera shake")
	_expect(r, int(snap.get("fx", 0)) > 0, "reduced motion should preserve non-motion impact feedback")
	view.free()
	return r

func test_main_mounts_dedicated_battle_presentation() -> Dictionary:
	var r := _result()
	var scene = load("res://src/app/main.tscn")
	_expect(r, scene != null, "main scene must load")
	if scene == null:
		return r
	var instance = scene.instantiate()
	instance.call("_ready")
	instance.start_battle(true)
	var presentation = instance.get_node_or_null("BattlePresentation")
	_expect(r, presentation != null, "battle screen must mount BattlePresentation")
	if presentation != null:
		_expect(r, presentation.has_method("presentation_snapshot"), "mounted presentation must expose diagnostics")
	instance.free()
	return r
