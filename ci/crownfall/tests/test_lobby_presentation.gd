extends RefCounted

func _result() -> Dictionary:
	return {"assertions": 0, "errors": []}

func _expect(r: Dictionary, condition: bool, message: String) -> void:
	r.assertions += 1
	if not condition:
		r.errors.append(message)

func _load_lobby_script():
	if not FileAccess.file_exists("res://src/presentation/lobby_view.gd"):
		return null
	return load("res://src/presentation/lobby_view.gd")

func test_lobby_presentation_exposes_visual_contract() -> Dictionary:
	var r := _result()
	var script = _load_lobby_script()
	_expect(r, script != null, "lobby_view.gd must exist")
	if script == null:
		return r
	var view = script.new()
	_expect(r, view is Control, "lobby presentation must be a Control")
	for method_name in ["screen_theme", "card_style", "presentation_snapshot", "configure_accessibility"]:
		_expect(r, view.has_method(method_name), "lobby presentation must expose %s" % method_name)
	view.free()
	return r

func test_lobby_screens_have_distinct_visual_identities() -> Dictionary:
	var r := _result()
	var script = _load_lobby_script()
	if script == null:
		_expect(r, false, "lobby_view.gd must exist before checking themes")
		return r
	var view = script.new()
	var signatures: Dictionary = {}
	for screen_name in ["home", "collection", "decks", "missions", "vaults", "exchange", "profile"]:
		var theme: Dictionary = view.screen_theme(screen_name)
		_expect(r, theme.has("accent"), "%s theme must define accent" % screen_name)
		_expect(r, theme.has("mood"), "%s theme must define mood" % screen_name)
		_expect(r, theme.has("pattern"), "%s theme must define pattern" % screen_name)
		var sig := "%s:%s" % [str(theme.get("mood", "")), str(theme.get("pattern", ""))]
		signatures[sig] = true
	_expect(r, signatures.size() >= 5, "lobby must use at least five distinct screen identities")
	view.free()
	return r

func test_card_styles_encode_rarity_and_family() -> Dictionary:
	var r := _result()
	var script = _load_lobby_script()
	if script == null:
		_expect(r, false, "lobby_view.gd must exist before checking card styling")
		return r
	var db_script = load("res://src/autoload/content_db.gd")
	var db = db_script.new()
	db.load_all()
	var view = script.new()
	var signatures: Dictionary = {}
	for card_id in ["iron_warden", "moss_colossus", "prism_turret", "starfall", "bloom_pulse"]:
		var style: Dictionary = view.card_style(card_id, db)
		_expect(r, style.has("accent"), "%s style must define accent" % card_id)
		_expect(r, style.has("family_mark"), "%s style must define family mark" % card_id)
		_expect(r, style.has("rarity_mark"), "%s style must define rarity mark" % card_id)
		var sig := "%s:%s" % [str(style.get("family_mark", "")), str(style.get("rarity_mark", ""))]
		signatures[sig] = true
	_expect(r, signatures.size() >= 3, "card frames must visibly encode family and rarity")
	view.free()
	return r

func test_main_mounts_lobby_presentation() -> Dictionary:
	var r := _result()
	var scene = load("res://src/app/main.tscn")
	_expect(r, scene != null, "main scene must load")
	if scene == null:
		return r
	var instance = scene.instantiate()
	instance.call("_ready")
	var lobby = instance.get_node_or_null("LobbyPresentation")
	_expect(r, lobby != null, "main scene must mount LobbyPresentation")
	if lobby != null:
		_expect(r, lobby.has_method("presentation_snapshot"), "mounted lobby must expose diagnostics")
	instance.free()
	return r
