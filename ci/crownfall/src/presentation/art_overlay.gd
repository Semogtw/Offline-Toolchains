extends Control

const TextureBankScript = preload("res://src/presentation/texture_bank.gd")
const W := 1080.0
const H := 2400.0
const RIVER_Y := 1200.0

var bank
var host
var art_time: float = 0.0
var reduced_motion: bool = false
var high_contrast: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	bank = TextureBankScript.new()
	bank.load_all()
	set_process(true)
	queue_redraw()

func _process(delta: float) -> void:
	host = get_parent()
	if host == null:
		return
	var profile = host.get("profile")
	if profile != null:
		var settings: Dictionary = profile.settings
		reduced_motion = bool(settings.get("reduced_motion", false))
		high_contrast = bool(settings.get("high_contrast", false))
	if not reduced_motion:
		art_time += delta
	queue_redraw()

func art_snapshot() -> Dictionary:
	if bank == null:
		return {"loaded": 0, "complete": false, "mode": "none"}
	var snap: Dictionary = bank.snapshot()
	snap["mode"] = "none" if host == null else str(host.get("current_screen"))
	snap["reduced_motion"] = reduced_motion
	snap["high_contrast"] = high_contrast
	return snap

func _draw() -> void:
	if host == null:
		host = get_parent()
	if host == null or bank == null or not bank.has_complete_pack():
		return
	var screen_name: String = str(host.get("current_screen"))
	if screen_name == "battle":
		_draw_battle_art()
	else:
		_draw_lobby_art(screen_name)

func _draw_battle_art() -> void:
	var ground: Texture2D = bank.material("arena_ground")
	var water: Texture2D = bank.material("water")
	var bridge: Texture2D = bank.material("bridge_wood")
	var stone: Texture2D = bank.material("tower_stone")
	var metal: Texture2D = bank.material("metal_trim")
	var contrast_mul: float = 1.15 if high_contrast else 1.0
	if ground != null:
		draw_texture_rect(ground, Rect2(48, 155, 984, 1880), true, Color(0.82*contrast_mul, 0.94*contrast_mul, 0.82*contrast_mul, 0.43))
		# Lanes get a denser material pass so the playfield reads immediately.
		for lane_x in [300.0, 780.0]:
			draw_texture_rect(ground, Rect2(lane_x - 118.0, 245, 236, 1710), true, Color(0.93, 0.90, 0.73, 0.18))
	if water != null:
		var water_shift: float = 0.0 if reduced_motion else sin(art_time * 0.72) * 9.0
		draw_texture_rect(water, Rect2(48 + water_shift, RIVER_Y - 80, 984, 160), true, Color(0.78, 0.96, 1.0, 0.72))
		# hide the tiny shifted seam with a second translucent pass
		draw_texture_rect(water, Rect2(48, RIVER_Y - 80, 984, 160), true, Color(0.70, 0.91, 1.0, 0.22))
	if bridge != null:
		for bridge_x in [300.0, 780.0]:
			draw_texture_rect(bridge, Rect2(bridge_x - 72, RIVER_Y - 112, 144, 224), true, Color(1.0, 0.92, 0.78, 0.84))
	if host.get("battle") != null:
		var battle = host.get("battle")
		for tower in battle.towers:
			if not bool(tower.get("alive", true)):
				continue
			var pos: Vector2 = tower.get("pos", Vector2.ZERO)
			var core: bool = bool(tower.get("core", false))
			var w: float = 112.0 if core else 90.0
			var h: float = 142.0 if core else 116.0
			if stone != null:
				draw_texture_rect(stone, Rect2(pos.x-w*0.5, pos.y-h*0.58, w, h), true, Color(0.96,0.96,1.0,0.68))
			if metal != null:
				draw_texture_rect(metal, Rect2(pos.x-w*0.47, pos.y-h*0.20, w*0.94, h*0.14), true, Color(0.82,0.91,1.0,0.55))
	_draw_battle_units()
	_draw_battle_hand_art()

func _draw_battle_units() -> void:
	var presentation = get_parent().get_node_or_null("BattlePresentation")
	var atlas: Texture2D = bank.material("unit_sprites")
	if presentation == null or atlas == null or not presentation.has_method("presentation_snapshot"):
		return
	var snapshot: Dictionary = presentation.presentation_snapshot()
	for visual in snapshot.get("units", []):
		var card_id: String = str(visual.get("card", ""))
		var pos: Vector2 = visual.get("render_pos", Vector2.ZERO)
		var state: String = str(visual.get("state", "idle"))
		var hit: float = float(visual.get("hit_flash", 0.0))
		if hit > 0.42:
			state = "hit"
		var t: float = float(visual.get("anim_time", 0.0))
		var region: Rect2 = bank.unit_region(card_id, state, t)
		if region.size.x <= 0:
			continue
		var scale: float = 1.0
		var bob: float = 0.0 if reduced_motion else sin(t * (7.0 if state == "move" else 3.0)) * (4.0 if state == "move" else 2.0)
		var dest := Rect2(pos.x - 64*scale, pos.y - 78*scale + bob, 128*scale, 128*scale)
		# dark under-paint masks the old geometric actor so the raster sprite owns the silhouette.
		draw_circle(pos + Vector2(0, 31), 39, Color(0.01,0.015,0.02,0.34))
		draw_texture_rect_region(atlas, dest, region, Color(1.0,1.0,1.0,0.98))
		if state == "attack":
			draw_arc(pos, 55, -1.1, 0.35, 18, Color(0.85,0.94,1.0,0.36), 4.0)

func _draw_battle_hand_art() -> void:
	var cycle = host.get("card_cycle")
	var atlas: Texture2D = bank.material("card_art")
	if cycle == null or atlas == null:
		return
	var selected: int = int(host.get("selected_hand_slot"))
	for i in range(cycle.hand.size()):
		var card_id: String = str(cycle.hand[i])
		var y: float = 2170.0 - (18.0 if i == selected else 0.0)
		var src: Rect2 = bank.card_region(card_id)
		var dest := Rect2(58.0 + float(i)*250.0, y + 18.0, 186.0, 116.0)
		draw_texture_rect_region(atlas, dest, src, Color(1.0,1.0,1.0,0.92))
		# bottom fade preserves card name/level text drawn by the base presentation.
		draw_rect(Rect2(dest.position.x, dest.position.y + 84, dest.size.x, 32), Color(0.025,0.04,0.06,0.52), true)

func _draw_lobby_art(screen_name: String) -> void:
	var parchment: Texture2D = bank.material("parchment")
	var stone: Texture2D = bank.material("tower_stone")
	var metal: Texture2D = bank.material("metal_trim")
	if parchment != null:
		draw_texture_rect(parchment, Rect2(56, 182, 968, 2045), true, Color(0.84,0.88,0.90,0.10 if not high_contrast else 0.15))
	match screen_name:
		"home": _draw_home_art()
		"collection": _draw_collection_art()
		"decks": _draw_deck_art()
		"missions":
			if stone != null: draw_texture_rect(stone, Rect2(80,420,920,1260), true, Color(0.76,0.88,0.80,0.14))
		"vaults":
			if stone != null: draw_texture_rect(stone, Rect2(90,520,900,1180), true, Color(0.95,0.83,0.56,0.13))
		"exchange":
			if metal != null: draw_texture_rect(metal, Rect2(85,510,910,1220), true, Color(0.82,0.62,0.94,0.15))
		"profile":
			if metal != null: draw_texture_rect(metal, Rect2(90,520,900,1040), true, Color(0.55,0.83,0.95,0.10))
			_draw_credit_line()

func _draw_home_art() -> void:
	var banner: Texture2D = bank.material("hero_banner")
	if banner == null:
		return
	var drift: float = 0.0 if reduced_motion else sin(art_time * 0.45) * 7.0
	draw_texture_rect(banner, Rect2(82, 520 + drift, 916, 650), false, Color(1.0,1.0,1.0,0.86))
	draw_rect(Rect2(82, 1050 + drift, 916, 120), Color(0.02,0.04,0.055,0.30), true)

func _draw_collection_art() -> void:
	var atlas: Texture2D = bank.material("card_art")
	var db = host.get("db")
	if atlas == null or db == null:
		return
	var ids: Array = db.cards.keys()
	ids.sort()
	var page: int = int(host.get("collection_page"))
	var start: int = page * 20
	var finish: int = mini(ids.size(), start + 20)
	for index in range(start, finish):
		var local: int = index - start
		var col: int = local % 4
		var row: int = local / 4
		var card_id: String = str(ids[index])
		var src: Rect2 = bank.card_region(card_id)
		var dest := Rect2(58 + col*250, 404 + row*315, 204, 154)
		draw_texture_rect_region(atlas, dest, src, Color(1.0,1.0,1.0,0.94))
		draw_rect(Rect2(dest.position.x, dest.end.y-25, dest.size.x, 25), Color(0.02,0.03,0.05,0.52), true)

func _draw_deck_art() -> void:
	var atlas: Texture2D = bank.material("card_art")
	var profile = host.get("profile")
	if atlas == null or profile == null:
		return
	for i in range(profile.deck.size()):
		var col: int = i % 4
		var row: int = i / 4
		var src: Rect2 = bank.card_region(str(profile.deck[i]))
		var dest := Rect2(70 + col*250, 525 + row*430, 194, 196)
		draw_texture_rect_region(atlas, dest, src, Color(1.0,1.0,1.0,0.95))
	for i in range(mini(4, profile.deck.size())):
		var src2: Rect2 = bank.card_region(str(profile.deck[i]))
		var dest2 := Rect2(72 + i*250, 1635, 190, 180)
		draw_texture_rect_region(atlas, dest2, src2, Color(1.0,1.0,1.0,0.93))

func _draw_credit_line() -> void:
	draw_string(ThemeDB.fallback_font, Vector2(285, 2050), "Surface materials · Poly Haven CC0", HORIZONTAL_ALIGNMENT_CENTER, 510, 17, Color(0.70,0.82,0.88,0.72))
