extends SceneTree

var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if condition:
		print("[SMOKE] PASS: ", message)
	else:
		failures += 1
		push_error("[SMOKE] FAIL: %s" % message)

func _run() -> void:
	var packed = load("res://src/app/main.tscn")
	_check(packed != null, "main scene loads")
	if packed == null:
		quit(1)
		return
	var app = packed.instantiate()
	root.add_child(app)
	await process_frame
	_check(app.get_node_or_null("TopBar") != null, "top bar is in live scene tree")
	_check(app.get_node_or_null("BottomNav") != null, "bottom navigation is in live scene tree")
	_check(str(app.ui_snapshot().get("screen", "")) == "home", "live app opens on home")
	var overlay = app.get_node_or_null("ArtOverlay")
	_check(overlay != null, "textured art overlay is in live scene tree")
	if overlay != null:
		var art: Dictionary = overlay.art_snapshot()
		_check(bool(art.get("complete", false)), "raster art pack is completely loaded")
		_check(int(art.get("loaded", 0)) >= 9, "raster art pack loads real texture resources")
	app.start_battle(true)
	await process_frame
	_check(str(app.ui_snapshot().get("screen", "")) == "battle", "training battle opens")
	_check(app.get_node_or_null("ActionLayer/Hand0") != null, "battle hand control is interactive")
	_check(app.select_card(0), "first hand card can be selected")
	_check(app.deploy_selected(Vector2(300, 1700)), "selected card deploys through live controller")
	for i in range(30):
		app.tick_battle(0.1)
		await process_frame
	var snapshot: Dictionary = app.ui_snapshot()
	_check(float(snapshot.get("elapsed", 0.0)) >= 3.0, "battle simulation advances for multiple frames")
	_check(int(snapshot.get("entities", 0)) > 0, "live battle keeps simulated entities")
	_check(int(snapshot.get("nav_items", 0)) >= 5, "navigation model remains available during battle")
	if overlay != null:
		var battle_art: Dictionary = overlay.art_snapshot()
		_check(str(battle_art.get("mode", "")) == "battle", "art overlay follows live navigation into battle")
	app.queue_free()
	await process_frame
	print("[SMOKE] RESULT: %d failures" % failures)
	quit(0 if failures == 0 else 1)
