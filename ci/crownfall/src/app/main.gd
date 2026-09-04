extends Control

const W := 1080.0
const H := 2400.0
const TOP_H := 170.0
const NAV_Y := 2255.0
const NAV_H := 145.0
const SAVE_PATH := "user://crownfall_profile.json"
const PRIMARY_NAV := ["home", "collection", "decks", "missions", "profile"]
const NAV_LABELS := {"home": "HALL", "collection": "CARDS", "decks": "DECKS", "missions": "QUESTS", "profile": "PROFILE"}
const EXCHANGE_OFFERS := [
	{"title": "Iron Temper", "card": "iron_warden", "cost": 180},
	{"title": "Astral Lens", "card": "astral_sentinel", "cost": 240},
	{"title": "Verdant Core", "card": "moss_colossus", "cost": 310}
]

const C_BG := Color("101826")
const C_PANEL := Color("172538")
const C_PANEL_2 := Color("20344a")
const C_INK := Color("f5f0df")
const C_MUTED := Color("9eb3c7")
const C_GOLD := Color("f3c45b")
const C_ARCANA := Color("b66cff")
const C_CYAN := Color("65d8ea")
const C_GREEN := Color("70d38a")
const C_RED := Color("ef6a73")
const C_BLUE := Color("5e8ff7")

var model
var db
var profile
var battle
var card_cycle
var current_screen: String = "home"
var training_mode: bool = false
var selected_hand_slot: int = 0
var active_deck: int = 0
var deck_edit_slot: int = -1
var collection_page: int = 0
var tutorial_step: int = 0
var bot_timer: float = 1.35
var battle_rewarded: bool = false
var battle_match_id: String = ""
var toast_text: String = ""
var toast_time: float = 0.0
var _booted: bool = false
var _top_bar: Control
var _bottom_nav: Control
var _actions: Control
var _last_bot_personality: String = "balanced"

func _ready() -> void:
	if _booted:
		return
	_booted = true
	model = load("res://src/app/app_model.gd").new()
	db = load("res://src/autoload/content_db.gd").new()
	db.load_all()
	profile = load("res://src/core/profile.gd").new()
	_load_profile()
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)
	_build_shell()
	show_screen("home")

func _process(delta: float) -> void:
	if toast_time > 0.0:
		toast_time = maxf(0.0, toast_time - delta)
		if toast_time <= 0.0:
			toast_text = ""
	if current_screen == "battle" and battle != null and not battle.finished:
		tick_battle(delta)
	queue_redraw()

func _build_shell() -> void:
	_top_bar = Control.new()
	_top_bar.name = "TopBar"
	_top_bar.position = Vector2.ZERO
	_top_bar.size = Vector2(W, TOP_H)
	_top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_top_bar)

	_actions = Control.new()
	_actions.name = "ActionLayer"
	_actions.position = Vector2.ZERO
	_actions.size = Vector2(W, H)
	_actions.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_actions)

	_bottom_nav = Control.new()
	_bottom_nav.name = "BottomNav"
	_bottom_nav.position = Vector2(0, NAV_Y)
	_bottom_nav.size = Vector2(W, NAV_H)
	add_child(_bottom_nav)
	_build_bottom_nav()

func _build_bottom_nav() -> void:
	_clear_children(_bottom_nav)
	var button_w: float = W / float(PRIMARY_NAV.size())
	for i in range(PRIMARY_NAV.size()):
		var screen_name: String = str(PRIMARY_NAV[i])
		var button := _button(
			_bottom_nav,
			"Nav_%s" % screen_name,
			str(NAV_LABELS[screen_name]),
			Rect2(i * button_w + 8.0, 10.0, button_w - 16.0, 118.0),
			Callable(self, "_on_nav").bind(screen_name),
			C_PANEL_2,
			C_CYAN if current_screen == screen_name else Color("38516a")
		)
		button.add_theme_font_size_override("font_size", 22)

func show_screen(screen_name: String) -> bool:
	if model == null:
		model = load("res://src/app/app_model.gd").new()
	if screen_name not in model.screen_names():
		return false
	if current_screen == "battle" and screen_name != "battle" and battle != null and not battle.finished:
		battle = null
		card_cycle = null
	current_screen = screen_name
	if _bottom_nav != null:
		_bottom_nav.visible = screen_name != "battle"
		_build_bottom_nav()
	_rebuild_actions()
	queue_redraw()
	return true

func start_battle(training: bool = false) -> void:
	if profile == null:
		profile = load("res://src/core/profile.gd").new()
	battle = load("res://src/core/battle_sim.gd").new(Time.get_ticks_msec())
	card_cycle = load("res://src/core/card_cycle.gd").new(profile.deck)
	training_mode = training
	selected_hand_slot = 0
	tutorial_step = 0
	bot_timer = 1.5 if training else 1.1
	battle_rewarded = false
	battle_match_id = "%s-%s" % [Time.get_unix_time_from_system(), Time.get_ticks_msec()]
	_last_bot_personality = "balanced" if training else ["balanced", "rush", "control", "siege"][randi() % 4]
	current_screen = "battle"
	if _bottom_nav != null:
		_bottom_nav.visible = false
	_rebuild_actions()
	queue_redraw()

func select_card(slot: int) -> bool:
	if card_cycle == null or slot < 0 or slot >= card_cycle.hand.size():
		return false
	selected_hand_slot = slot
	queue_redraw()
	return true

func deploy_selected(pos: Vector2) -> bool:
	if battle == null or card_cycle == null or battle.finished:
		return false
	if selected_hand_slot < 0 or selected_hand_slot >= card_cycle.hand.size():
		return false
	var card_id: String = str(card_cycle.hand[selected_hand_slot])
	var card: Dictionary = db.cards.get(card_id, {})
	if card.is_empty():
		return false
	var ok: bool = battle.deploy(card_id, pos, battle.PLAYER)
	if not ok:
		_show_toast("Not enough Arcana or invalid deployment zone")
		return false
	profile.record_deploy(str(card.get("family", "troop")))
	card_cycle.play(card_id)
	selected_hand_slot = mini(selected_hand_slot, card_cycle.hand.size() - 1)
	if training_mode:
		var steps: Array = model.tutorial_steps()
		if tutorial_step < steps.size() and str(steps[tutorial_step].card) == card_id:
			tutorial_step += 1
			if tutorial_step < steps.size():
				_show_toast(str(steps[tutorial_step].title))
	_rebuild_actions()
	queue_redraw()
	return true

func tick_battle(delta: float) -> void:
	if battle == null or delta <= 0.0:
		return
	battle.step(delta)
	bot_timer -= delta
	if not battle.finished and bot_timer <= 0.0:
		var difficulty: int = 1 if training_mode else 2
		battle.bot_step(_last_bot_personality, difficulty)
		bot_timer = 1.7 if training_mode else 1.0 + randf() * 0.45
	if battle.finished and not battle_rewarded:
		battle_rewarded = true
		var won: bool = int(battle.winner) == int(battle.PLAYER)
		profile.apply_match_reward(battle_match_id, won)
		_save_profile()
		_rebuild_actions()
	queue_redraw()

func ui_snapshot() -> Dictionary:
	var hand: Array = []
	var next_card: String = ""
	var entities := 0
	var elapsed := 0.0
	var arcana := 0.0
	var finished := false
	var winner := -1
	if card_cycle != null:
		hand = card_cycle.hand.duplicate()
		next_card = str(card_cycle.next_card)
	if battle != null:
		entities = battle.entities.size()
		elapsed = float(battle.clock.elapsed)
		arcana = float(battle.player_arcana.value)
		finished = bool(battle.finished)
		winner = int(battle.winner)
	return {
		"screen": current_screen,
		"nav_items": PRIMARY_NAV.size(),
		"coins": 0 if profile == null else profile.coins,
		"trophies": 0 if profile == null else profile.trophies,
		"level": 1 if profile == null else profile.account_level,
		"hand": hand,
		"next": next_card,
		"entities": entities,
		"elapsed": elapsed,
		"arcana": arcana,
		"finished": finished,
		"winner": winner,
		"tutorial_step": tutorial_step,
		"active_deck": active_deck
	}

func _gui_input(event: InputEvent) -> void:
	if current_screen != "battle" or battle == null or battle.finished:
		return
	var pos := Vector2(-1, -1)
	if event is InputEventScreenTouch and event.pressed:
		pos = event.position
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		pos = event.position
	if pos.x >= 0.0 and pos.y >= 220.0 and pos.y <= 2180.0:
		deploy_selected(pos)
		accept_event()

func _rebuild_actions() -> void:
	if _actions == null:
		return
	_clear_children(_actions)
	match current_screen:
		"home": _build_home_actions()
		"collection": _build_collection_actions()
		"decks": _build_deck_actions()
		"missions": _build_mission_actions()
		"vaults": _build_vault_actions()
		"exchange": _build_exchange_actions()
		"profile": _build_profile_actions()
		"battle": _build_battle_actions()

func _build_home_actions() -> void:
	_button(_actions, "Play", "ENTER ARENA", Rect2(170, 1515, 740, 124), Callable(self, "start_battle").bind(false), Color("2c8b75"), C_GREEN)
	_button(_actions, "Training", "TRAINING GROVE", Rect2(170, 1660, 740, 105), Callable(self, "start_battle").bind(true), Color("3b5c8e"), C_CYAN)
	_button(_actions, "VaultShortcut", "VAULTS", Rect2(145, 1850, 360, 96), Callable(self, "show_screen").bind("vaults"), C_PANEL_2, C_GOLD)
	_button(_actions, "ExchangeShortcut", "EXCHANGE", Rect2(575, 1850, 360, 96), Callable(self, "show_screen").bind("exchange"), C_PANEL_2, C_ARCANA)

func _build_collection_actions() -> void:
	var ids: Array = db.cards.keys()
	ids.sort()
	var per_page := 20
	var start := collection_page * per_page
	var finish: int = mini(ids.size(), start + per_page)
	for index in range(start, finish):
		var local := index - start
		var col := local % 4
		var row := local / 4
		var rect := Rect2(45 + col * 250, 390 + row * 315, 230, 286)
		var card_id: String = str(ids[index])
		_button(_actions, "Card_%s" % card_id, "", rect, Callable(self, "_on_collection_card").bind(card_id), Color(0,0,0,0), Color(0,0,0,0), true)
	if collection_page > 0:
		_button(_actions, "PrevPage", "PREV", Rect2(80, 2040, 230, 84), Callable(self, "_set_collection_page").bind(collection_page - 1), C_PANEL_2, C_CYAN)
	if finish < ids.size():
		_button(_actions, "NextPage", "NEXT", Rect2(770, 2040, 230, 84), Callable(self, "_set_collection_page").bind(collection_page + 1), C_PANEL_2, C_CYAN)

func _build_deck_actions() -> void:
	for i in range(3):
		var fill := C_BLUE if i == active_deck else C_PANEL_2
		_button(_actions, "DeckTab%d" % i, "DECK %d" % (i + 1), Rect2(120 + i * 290, 290, 260, 80), Callable(self, "_switch_deck").bind(i), fill, C_CYAN)
	for i in range(profile.deck.size()):
		var col := i % 4
		var row := i / 4
		var rect := Rect2(55 + col * 250, 510 + row * 430, 225, 350)
		_button(_actions, "DeckSlot%d" % i, "EDIT", Rect2(rect.position + Vector2(20, 285), Vector2(185, 52)), Callable(self, "_choose_deck_slot").bind(i), Color("273e5a"), C_GOLD)

func _build_mission_actions() -> void:
	for i in range(profile.missions.size()):
		var mission: Dictionary = profile.missions[i]
		var ready: bool = int(mission.progress) >= int(mission.goal) and not bool(mission.claimed)
		var text := "CLAIM +%d" % int(mission.reward) if ready else ("CLAIMED" if bool(mission.claimed) else "IN PROGRESS")
		var b := _button(_actions, "Mission%d" % i, text, Rect2(690, 545 + i * 340, 250, 82), Callable(self, "_claim_mission").bind(str(mission.id)), Color("2c6b57") if ready else C_PANEL_2, C_GREEN if ready else Color("435a6d"))
		b.disabled = not ready

func _build_vault_actions() -> void:
	_button(_actions, "BackHome", "BACK", Rect2(55, 210, 190, 72), Callable(self, "show_screen").bind("home"), C_PANEL_2, C_CYAN)
	for i in range(profile.vaults.size()):
		var vault: Dictionary = profile.vaults[i]
		var ready: bool = bool(vault.ready)
		var b := _button(_actions, "Vault%d" % i, "OPEN" if ready else "LOCKED", Rect2(690, 600 + i * 390, 250, 86), Callable(self, "_claim_vault").bind(i), Color("735a29") if ready else C_PANEL_2, C_GOLD)
		b.disabled = not ready

func _build_exchange_actions() -> void:
	_button(_actions, "BackHome", "BACK", Rect2(55, 210, 190, 72), Callable(self, "show_screen").bind("home"), C_PANEL_2, C_CYAN)
	for i in range(EXCHANGE_OFFERS.size()):
		var offer: Dictionary = EXCHANGE_OFFERS[i]
		var b := _button(_actions, "Offer%d" % i, "INFUSE · %d" % int(offer.cost), Rect2(650, 620 + i * 390, 300, 88), Callable(self, "_buy_offer").bind(i), Color("543d74"), C_ARCANA)
		b.disabled = profile.coins < int(offer.cost) or int(profile.levels.get(str(offer.card), 1)) >= 10

func _build_profile_actions() -> void:
	var keys := ["music", "sfx", "haptics", "reduced_motion", "screen_shake", "high_contrast", "battery_saver"]
	for i in range(keys.size()):
		var key: String = str(keys[i])
		var current = profile.settings.get(key, false)
		var enabled: bool = bool(current) if typeof(current) == TYPE_BOOL else float(current) > 0.0
		_button(_actions, "Setting_%s" % key, "ON" if enabled else "OFF", Rect2(770, 670 + i * 190, 190, 72), Callable(self, "_toggle_setting").bind(key), Color("245a4d") if enabled else C_PANEL_2, C_GREEN if enabled else Color("52687b"))

func _build_battle_actions() -> void:
	_button(_actions, "ExitBattle", "✕", Rect2(930, 34, 105, 84), Callable(self, "_exit_battle"), Color("5b2831"), C_RED)
	if battle == null:
		return
	if battle.finished:
		_button(_actions, "BattleHome", "RETURN TO HALL", Rect2(210, 1990, 660, 100), Callable(self, "show_screen").bind("home"), Color("31557b"), C_CYAN)
		_button(_actions, "Rematch", "REMATCH", Rect2(315, 2110, 450, 88), Callable(self, "start_battle").bind(training_mode), Color("2b785f"), C_GREEN)
		return
	if card_cycle == null:
		return
	for i in range(card_cycle.hand.size()):
		var x := 44.0 + i * 250.0
		_button(_actions, "Hand%d" % i, "", Rect2(x, 2190, 225, 185), Callable(self, "select_card").bind(i), Color(0,0,0,0), Color(0,0,0,0), true)

func _on_nav(screen_name: String) -> void:
	show_screen(screen_name)

func _on_collection_card(card_id: String) -> void:
	if deck_edit_slot >= 0:
		if card_id in profile.deck and str(profile.deck[deck_edit_slot]) != card_id:
			_show_toast("A deck cannot contain duplicate cards")
			return
		profile.deck[deck_edit_slot] = card_id
		profile.decks[active_deck] = profile.deck.duplicate()
		deck_edit_slot = -1
		_save_profile()
		_show_toast("Deck updated")
		show_screen("decks")
		return
	var before: int = int(profile.levels.get(card_id, 1))
	if profile.upgrade_card(card_id):
		_save_profile()
		_show_toast("%s upgraded to Lv.%d" % [str(db.cards[card_id].name), before + 1])
	else:
		_show_toast("Need more coins or card is max level")
	_rebuild_actions()
	queue_redraw()

func _set_collection_page(page: int) -> void:
	collection_page = maxi(0, page)
	_rebuild_actions()
	queue_redraw()

func _switch_deck(index: int) -> void:
	if index < 0 or index >= profile.decks.size():
		return
	profile.decks[active_deck] = profile.deck.duplicate()
	active_deck = index
	profile.deck = profile.decks[index].duplicate()
	_save_profile()
	_rebuild_actions()
	queue_redraw()

func _choose_deck_slot(index: int) -> void:
	if index < 0 or index >= profile.deck.size():
		return
	deck_edit_slot = index
	collection_page = 0
	_show_toast("Choose a replacement card")
	show_screen("collection")

func _claim_mission(id: String) -> void:
	if profile.claim_mission(id):
		_save_profile()
		_show_toast("Mission reward claimed")
	else:
		_show_toast("Mission is not complete yet")
	_rebuild_actions()
	queue_redraw()

func _claim_vault(index: int) -> void:
	if profile.claim_vault(index):
		_save_profile()
		_show_toast("Vault opened")
	else:
		_show_toast("Vault is not ready")
	_rebuild_actions()
	queue_redraw()

func _buy_offer(index: int) -> void:
	if index < 0 or index >= EXCHANGE_OFFERS.size():
		return
	var offer: Dictionary = EXCHANGE_OFFERS[index]
	var card_id: String = str(offer.card)
	var cost: int = int(offer.cost)
	var level: int = int(profile.levels.get(card_id, 1))
	if profile.coins < cost or level >= 10:
		_show_toast("Offer unavailable")
		return
	profile.coins -= cost
	profile.levels[card_id] = level + 1
	_save_profile()
	_show_toast("Infusion complete · %s Lv.%d" % [str(db.cards[card_id].name), level + 1])
	_rebuild_actions()
	queue_redraw()

func _toggle_setting(key: String) -> void:
	if not profile.settings.has(key):
		return
	var current = profile.settings[key]
	if typeof(current) == TYPE_BOOL:
		profile.settings[key] = not bool(current)
	else:
		profile.settings[key] = 0.0 if float(current) > 0.0 else 1.0
	if key == "haptics" and bool(profile.settings[key]):
		Input.vibrate_handheld(28)
	_save_profile()
	_rebuild_actions()
	queue_redraw()

func _exit_battle() -> void:
	battle = null
	card_cycle = null
	show_screen("home")

func _show_toast(message: String) -> void:
	toast_text = message
	toast_time = 2.4
	queue_redraw()

func _save_profile() -> void:
	if profile == null:
		return
	if active_deck >= 0 and active_deck < profile.decks.size():
		profile.decks[active_deck] = profile.deck.duplicate()
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(profile.to_dict()))

func _load_profile() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		profile.from_dict(parsed)

func _button(parent: Control, node_name: String, text: String, rect: Rect2, callback: Callable, fill: Color, border: Color, transparent: bool = false) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.position = rect.position
	b.size = rect.size
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 25)
	if transparent:
		var clear := _style(Color(0,0,0,0), Color(0,0,0,0), 20)
		b.add_theme_stylebox_override("normal", clear)
		b.add_theme_stylebox_override("hover", _style(Color(1,1,1,0.04), Color(1,1,1,0.08), 20))
		b.add_theme_stylebox_override("pressed", _style(Color(1,1,1,0.08), Color(1,1,1,0.12), 20))
	else:
		b.add_theme_stylebox_override("normal", _style(fill, border, 24))
		b.add_theme_stylebox_override("hover", _style(fill.lightened(0.08), border.lightened(0.08), 24))
		b.add_theme_stylebox_override("pressed", _style(fill.darkened(0.08), border, 24))
	b.add_theme_color_override("font_color", C_INK)
	b.pressed.connect(callback)
	parent.add_child(b)
	return b

func _style(bg: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(2)
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.shadow_color = Color(0,0,0,0.25)
	style.shadow_size = 7
	return style

func _clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.free()

func _draw() -> void:
	draw_rect(Rect2(0, 0, W, H), C_BG)
	if current_screen == "battle":
		_draw_battle()
	else:
		_draw_lobby_background()
		_draw_top_bar()
		match current_screen:
			"home": _draw_home()
			"collection": _draw_collection()
			"decks": _draw_decks()
			"missions": _draw_missions()
			"vaults": _draw_vaults()
			"exchange": _draw_exchange()
			"profile": _draw_profile()
		_draw_bottom_nav()
	if not toast_text.is_empty() and toast_time > 0.0:
		_draw_toast()

func _draw_lobby_background() -> void:
	for i in range(12):
		var y := float(i) * 200.0
		var mix := float(i) / 12.0
		draw_rect(Rect2(0, y, W, 202), C_BG.lerp(Color("1a3042"), mix * 0.65))
	for i in range(8):
		var x := 80.0 + i * 145.0
		draw_circle(Vector2(x, 290.0 + sin(float(i)) * 50.0), 6.0 + float(i % 3) * 2.0, Color(0.35,0.85,0.92,0.18))

func _draw_top_bar() -> void:
	draw_rect(Rect2(0, 0, W, TOP_H), Color("0b121d"))
	draw_rect(Rect2(25, 24, 250, 118), C_PANEL, true)
	_draw_emblem(Vector2(82, 83), 40, C_CYAN)
	_text("CROWNFALL", Vector2(132, 72), 28, C_INK)
	_text("ARENA", Vector2(132, 108), 21, C_MUTED)
	_resource_chip(Rect2(315, 34, 215, 98), "COINS", str(profile.coins), C_GOLD)
	_resource_chip(Rect2(550, 34, 215, 98), "CROWNS", str(profile.trophies), C_CYAN)
	_resource_chip(Rect2(785, 34, 270, 98), "LEVEL", "%d · %d XP" % [profile.account_level, profile.xp], C_GREEN)

func _resource_chip(rect: Rect2, label: String, value: String, accent: Color) -> void:
	draw_rect(rect, C_PANEL, true)
	draw_rect(Rect2(rect.position, Vector2(7, rect.size.y)), accent, true)
	_text(label, rect.position + Vector2(24, 34), 18, C_MUTED)
	_text(value, rect.position + Vector2(24, 75), 27, C_INK)

func _draw_bottom_nav() -> void:
	draw_rect(Rect2(0, NAV_Y, W, NAV_H), Color("0b121d"), true)
	var button_w: float = W / float(PRIMARY_NAV.size())
	for i in range(PRIMARY_NAV.size()):
		var screen_name: String = str(PRIMARY_NAV[i])
		var cx := i * button_w + button_w * 0.5
		var accent := C_CYAN if screen_name == current_screen else Color("526a7d")
		draw_circle(Vector2(cx, NAV_Y + 38), 9.0, accent)

func _draw_home() -> void:
	_text("THE ASTRAL CITADEL", Vector2(65, 270), 32, C_MUTED)
	_text("Rise through the", Vector2(65, 350), 66, C_INK)
	_text("Crownfall Leagues", Vector2(65, 422), 66, C_CYAN)
	# Hero arena diorama.
	draw_rect(Rect2(65, 510, 950, 820), Color("1d3d38"), true)
	draw_rect(Rect2(65, 900, 950, 130), Color("235d78"), true)
	draw_rect(Rect2(260, 895, 130, 140), Color("a88754"), true)
	draw_rect(Rect2(690, 895, 130, 140), Color("a88754"), true)
	_draw_tower(Vector2(270, 790), C_BLUE, false, 1.0)
	_draw_tower(Vector2(810, 760), C_RED, false, 1.0)
	_draw_tower(Vector2(540, 1120), C_BLUE, true, 1.2)
	for i in range(7):
		_draw_unit(Vector2(310 + i * 75, 870 + sin(float(i) * 1.3) * 60), "iron_warden" if i % 2 == 0 else "ember_fox", 0, 1.0)
	_text("LIVE SKIRMISH · OFFLINE AI", Vector2(105, 1280), 22, Color("9ce9d0"))
	_text("5 leagues · 24 original cards · persistent progression", Vector2(170, 1420), 24, C_MUTED)
	_text("VAULTS & FORGE", Vector2(145, 1815), 20, C_MUTED)

func _draw_collection() -> void:
	_text("CARD ARCHIVE", Vector2(55, 250), 52, C_INK)
	_text("Tap a card to upgrade it with coins. Edit a deck slot to choose a replacement here.", Vector2(55, 305), 22, C_MUTED)
	var ids: Array = db.cards.keys()
	ids.sort()
	var per_page := 20
	var start := collection_page * per_page
	var finish: int = mini(ids.size(), start + per_page)
	for index in range(start, finish):
		var local := index - start
		var col := local % 4
		var row := local / 4
		var rect := Rect2(45 + col * 250, 390 + row * 315, 230, 286)
		_draw_card(str(ids[index]), rect, false, true)
	_text("PAGE %d / %d" % [collection_page + 1, int(ceil(float(ids.size()) / float(per_page)))], Vector2(455, 2095), 21, C_MUTED)

func _draw_decks() -> void:
	_text("BATTLE DECKS", Vector2(55, 250), 52, C_INK)
	_text("Eight-card cycle · tap EDIT on a slot, then choose a replacement from the archive.", Vector2(55, 420), 22, C_MUTED)
	for i in range(profile.deck.size()):
		var col := i % 4
		var row := i / 4
		_draw_card(str(profile.deck[i]), Rect2(55 + col * 250, 510 + row * 430, 225, 350), false, false)
	var avg := 0.0
	for id in profile.deck:
		avg += float(db.cards[str(id)].cost)
	avg /= maxf(1.0, float(profile.deck.size()))
	_text("AVERAGE ARCANA  %.1f" % avg, Vector2(360, 1475), 28, C_ARCANA)
	_text("NEXT IN CYCLE", Vector2(55, 1570), 23, C_MUTED)
	for i in range(4):
		_draw_card(str(profile.deck[i]), Rect2(55 + i * 250, 1620, 225, 330), false, false)

func _draw_missions() -> void:
	_text("DAILY MISSIONS", Vector2(55, 250), 52, C_INK)
	_text("Battle actions update these locally. No network or purchase required.", Vector2(55, 310), 22, C_MUTED)
	for i in range(profile.missions.size()):
		var mission: Dictionary = profile.missions[i]
		var y := 470.0 + i * 340.0
		draw_rect(Rect2(70, y, 940, 260), C_PANEL, true)
		var progress: int = int(mission.progress)
		var goal: int = int(mission.goal)
		_text(str(mission.title), Vector2(110, y + 65), 32, C_INK)
		_text("Reward  %d coins" % int(mission.reward), Vector2(110, y + 108), 21, C_GOLD)
		var ratio := clampf(float(progress) / maxf(1.0, float(goal)), 0.0, 1.0)
		draw_rect(Rect2(110, y + 155, 520, 28), Color("0f1824"), true)
		draw_rect(Rect2(110, y + 155, 520 * ratio, 28), C_GREEN, true)
		_text("%d / %d" % [progress, goal], Vector2(110, y + 222), 21, C_MUTED)

func _draw_vaults() -> void:
	_text("SEED VAULTS", Vector2(55, 345), 52, C_INK)
	_text("Offline reward containers earned through play.", Vector2(55, 405), 22, C_MUTED)
	for i in range(profile.vaults.size()):
		var vault: Dictionary = profile.vaults[i]
		var y := 520.0 + i * 390.0
		draw_rect(Rect2(95, y, 890, 290), C_PANEL, true)
		var accent := C_GOLD if bool(vault.ready) else Color("536271")
		_draw_vault_icon(Vector2(245, y + 145), accent, 1.0 + i * 0.08)
		_text(str(vault.kind), Vector2(390, y + 105), 36, C_INK)
		_text("Contains %d coins" % int(vault.coins), Vector2(390, y + 152), 23, C_GOLD)
		_text("READY" if bool(vault.ready) else "AWAKENING", Vector2(390, y + 205), 21, accent)

func _draw_exchange() -> void:
	_text("ARCANE EXCHANGE", Vector2(55, 345), 52, C_INK)
	_text("Spend earned coins to infuse cards. No real-money transactions.", Vector2(55, 405), 22, C_MUTED)
	for i in range(EXCHANGE_OFFERS.size()):
		var offer: Dictionary = EXCHANGE_OFFERS[i]
		var card_id: String = str(offer.card)
		var y := 520.0 + i * 390.0
		draw_rect(Rect2(95, y, 890, 290), C_PANEL, true)
		_draw_card(card_id, Rect2(125, y + 25, 190, 240), false, true)
		_text(str(offer.title), Vector2(370, y + 85), 34, C_INK)
		_text("%s · Lv.%d" % [str(db.cards[card_id].name), int(profile.levels.get(card_id, 1))], Vector2(370, y + 132), 23, C_MUTED)
		_text("%d coins" % int(offer.cost), Vector2(370, y + 185), 25, C_GOLD)

func _draw_profile() -> void:
	_text("WARDEN PROFILE", Vector2(55, 250), 52, C_INK)
	draw_rect(Rect2(65, 350, 950, 220), C_PANEL, true)
	_draw_emblem(Vector2(170, 460), 72, C_CYAN)
	_text("CITADEL WARDEN", Vector2(280, 430), 34, C_INK)
	_text("Account Lv.%d" % profile.account_level, Vector2(280, 477), 23, C_GREEN)
	_text("%d crowns · %d coins" % [profile.trophies, profile.coins], Vector2(280, 518), 22, C_MUTED)
	_text("SETTINGS", Vector2(70, 630), 26, C_MUTED)
	var keys := ["music", "sfx", "haptics", "reduced_motion", "screen_shake", "high_contrast", "battery_saver"]
	var labels := ["Music", "Sound effects", "Haptics", "Reduced motion", "Screen shake", "High contrast", "Battery saver"]
	for i in range(keys.size()):
		var y := 700.0 + i * 190.0
		draw_rect(Rect2(70, y - 65, 940, 135), C_PANEL, true)
		_text(str(labels[i]), Vector2(110, y + 5), 28, C_INK)
		var value = profile.settings.get(str(keys[i]), false)
		var enabled: bool = bool(value) if typeof(value) == TYPE_BOOL else float(value) > 0.0
		_text("ACTIVE" if enabled else "OFF", Vector2(600, y + 4), 20, C_GREEN if enabled else C_MUTED)

func _draw_battle() -> void:
	# Arena base and side walls.
	for i in range(12):
		var y := float(i) * 200.0
		draw_rect(Rect2(0, y, W, 202), Color("16392f").lerp(Color("254635"), float(i % 3) * 0.06), true)
	draw_rect(Rect2(0, 0, 45, 2190), Color("0b211c"), true)
	draw_rect(Rect2(1035, 0, 45, 2190), Color("0b211c"), true)
	# Stone lane markings.
	for lane_x in [300.0, 780.0]:
		for y in range(250, 2150, 125):
			draw_rect(Rect2(lane_x - 76, float(y), 152, 62), Color(0.75,0.80,0.65,0.055), true)
	# River and bridges.
	draw_rect(Rect2(45, 1125, 990, 150), Color("246a83"), true)
	for x in [235.0, 715.0]:
		draw_rect(Rect2(x, 1110, 130, 180), Color("a78252"), true)
		for plank in range(5):
			draw_line(Vector2(x, 1120 + plank * 35), Vector2(x + 130, 1120 + plank * 35), Color("60472e"), 3.0)
	# Deployment tint for player territory.
	draw_rect(Rect2(48, 1278, 984, 890), Color(0.2,0.45,0.70,0.055), true)
	if battle != null:
		for tower in battle.towers:
			if bool(tower.alive):
				_draw_sim_tower(tower)
		for entity in battle.entities:
			_draw_sim_entity(entity)
		_draw_battle_hud()
	# Hand dock.
	draw_rect(Rect2(0, 2180, W, 220), Color("0b121d"), true)
	if card_cycle != null and battle != null and not battle.finished:
		for i in range(card_cycle.hand.size()):
			var rect := Rect2(44 + i * 250, 2190, 225, 185)
			_draw_card(str(card_cycle.hand[i]), rect, i == selected_hand_slot, true)
		_text("NEXT", Vector2(952, 2174), 16, C_MUTED)
	if battle != null and battle.finished:
		_draw_battle_result()

func _draw_battle_hud() -> void:
	draw_rect(Rect2(260, 26, 560, 110), Color(0.04,0.07,0.11,0.88), true)
	var remaining := float(battle.clock.remaining())
	var mins := int(remaining) / 60
	var secs := int(remaining) % 60
	var phase_text := "OVERTIME" if str(battle.clock.phase) == "overtime" else "BATTLE"
	_text(phase_text, Vector2(300, 70), 20, C_MUTED)
	_text("%d:%02d" % [mins, secs], Vector2(462, 104), 42, C_INK)
	_text("ARCANA", Vector2(62, 2050), 18, C_MUTED)
	draw_rect(Rect2(62, 2070, 430, 34), Color("241934"), true)
	draw_rect(Rect2(62, 2070, 430 * clampf(float(battle.player_arcana.value) / 10.0, 0.0, 1.0), 34), C_ARCANA, true)
	_text("%.1f / 10" % float(battle.player_arcana.value), Vector2(515, 2098), 20, C_INK)
	if training_mode:
		var steps: Array = model.tutorial_steps()
		var idx: int = mini(tutorial_step, steps.size() - 1)
		var step: Dictionary = steps[idx]
		draw_rect(Rect2(90, 155, 900, 128), Color(0.05,0.08,0.13,0.90), true)
		_text("TRAINING %d/7 · %s" % [mini(tutorial_step + 1, 7), str(step.title)], Vector2(125, 205), 24, C_CYAN)
		_text(str(step.hint), Vector2(125, 245), 19, C_MUTED)

func _draw_sim_tower(tower: Dictionary) -> void:
	var team: int = int(tower.team)
	var accent := C_BLUE if team == 0 else C_RED
	var pos: Vector2 = tower.pos
	_draw_tower(pos, accent, bool(tower.core), 0.8 if not bool(tower.core) else 0.95)
	_draw_health_bar(Vector2(pos.x - 65, pos.y - 105), 130, float(tower.hp) / maxf(1.0, float(tower.max_hp)), accent)

func _draw_sim_entity(entity: Dictionary) -> void:
	var team: int = int(entity.team)
	var accent := C_BLUE if team == 0 else C_RED
	var pos: Vector2 = entity.pos
	_draw_unit(pos, str(entity.card), team, 0.72)
	_draw_health_bar(Vector2(pos.x - 30, pos.y - 54), 60, float(entity.hp) / maxf(1.0, float(entity.max_hp)), accent)

func _draw_battle_result() -> void:
	draw_rect(Rect2(100, 690, 880, 640), Color(0.03,0.05,0.09,0.94), true)
	var won: bool = int(battle.winner) == int(battle.PLAYER)
	var draw_game: bool = int(battle.winner) < 0
	var title := "DRAW" if draw_game else ("CITADEL SECURED" if won else "CITADEL FALLEN")
	var accent := C_GOLD if draw_game else (C_GREEN if won else C_RED)
	_draw_emblem(Vector2(540, 855), 92, accent)
	_text_centered(title, Rect2(130, 990, 820, 70), 46, accent)
	_text_centered("+120 coins · +28 crowns" if won else "+45 coins · battle experience", Rect2(130, 1080, 820, 50), 24, C_MUTED)
	_text_centered("Your local progression has been saved", Rect2(130, 1160, 820, 45), 20, C_MUTED)

func _draw_card(card_id: String, rect: Rect2, selected: bool, compact: bool) -> void:
	if not db.cards.has(card_id):
		return
	var card: Dictionary = db.cards[card_id]
	var hue := float(abs(card_id.hash()) % 1000) / 1000.0
	var accent := Color.from_hsv(hue, 0.62, 0.92)
	var bg := Color("1a2636")
	if selected:
		bg = Color("31304f")
		draw_rect(Rect2(rect.position - Vector2(5,5), rect.size + Vector2(10,10)), C_ARCANA, true)
	draw_rect(rect, bg, true)
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, 7)), accent, true)
	var icon_center := rect.position + Vector2(rect.size.x * 0.5, 72 if compact else 105)
	_draw_card_icon(icon_center, card_id, str(card.family), accent, 0.75 if compact else 1.0)
	var name_size := 15 if compact else 18
	_text_centered(str(card.name), Rect2(rect.position.x + 8, rect.position.y + (112 if compact else 168), rect.size.x - 16, 40), name_size, C_INK)
	var cost_r := 24.0 if compact else 27.0
	draw_circle(rect.position + Vector2(31, 31), cost_r, C_ARCANA)
	_text_centered(str(card.cost), Rect2(rect.position.x + 8, rect.position.y + 14, 46, 30), 18, Color.WHITE)
	var level: int = 1 if profile == null else int(profile.levels.get(card_id, 1))
	_text("LV.%d" % level, rect.position + Vector2(14, rect.size.y - 16), 14 if compact else 16, C_MUTED)
	if not compact:
		_text("%s · %s" % [str(card.family).to_upper(), str(card.rarity).to_upper()], rect.position + Vector2(14, rect.size.y - 46), 13, accent)

func _draw_card_icon(center: Vector2, card_id: String, family: String, accent: Color, scale_factor: float) -> void:
	if family == "structure":
		draw_rect(Rect2(center - Vector2(40, 28) * scale_factor, Vector2(80, 58) * scale_factor), accent.darkened(0.35), true)
		draw_rect(Rect2(center - Vector2(30, 48) * scale_factor, Vector2(60, 56) * scale_factor), accent, true)
		for dx in [-22.0, 0.0, 22.0]:
			draw_rect(Rect2(center + Vector2(dx - 8.0, -58.0) * scale_factor, Vector2(16, 22) * scale_factor), accent.lightened(0.15), true)
	elif family == "spell":
		var pts := PackedVector2Array([
			center + Vector2(0,-50) * scale_factor,
			center + Vector2(42,0) * scale_factor,
			center + Vector2(0,50) * scale_factor,
			center + Vector2(-42,0) * scale_factor
		])
		draw_colored_polygon(pts, accent)
		draw_circle(center, 15 * scale_factor, Color.WHITE)
	else:
		_draw_unit(center + Vector2(0, 12), card_id, 0, scale_factor)

func _draw_unit(pos: Vector2, card_id: String, team: int, scale_factor: float) -> void:
	var hue := float(abs(card_id.hash()) % 1000) / 1000.0
	var body := Color.from_hsv(hue, 0.58, 0.88)
	var team_glow := C_BLUE if team == 0 else C_RED
	# soft shadow and allegiance ring
	draw_circle(pos + Vector2(0, 28) * scale_factor, 30 * scale_factor, Color(0,0,0,0.25))
	draw_circle(pos + Vector2(0, 20) * scale_factor, 28 * scale_factor, team_glow.darkened(0.35))
	# torso / cape / head
	draw_rect(Rect2(pos + Vector2(-23,-5) * scale_factor, Vector2(46,55) * scale_factor), body.darkened(0.18), true)
	draw_circle(pos + Vector2(0,-24) * scale_factor, 25 * scale_factor, body.lightened(0.08))
	# helmet crest changes per id hash
	if abs(card_id.hash()) % 2 == 0:
		var crest := PackedVector2Array([
			pos + Vector2(-18,-45) * scale_factor,
			pos + Vector2(0,-67) * scale_factor,
			pos + Vector2(18,-45) * scale_factor
		])
		draw_colored_polygon(crest, body.lightened(0.22))
	else:
		draw_rect(Rect2(pos + Vector2(-24,-51) * scale_factor, Vector2(48,13) * scale_factor), body.lightened(0.22), true)
	# face lights and weapon silhouette
	draw_circle(pos + Vector2(-8,-24) * scale_factor, 3.5 * scale_factor, Color.WHITE)
	draw_circle(pos + Vector2(8,-24) * scale_factor, 3.5 * scale_factor, Color.WHITE)
	if abs(card_id.hash()) % 3 == 0:
		draw_line(pos + Vector2(24,0) * scale_factor, pos + Vector2(50,-42) * scale_factor, C_INK, 7 * scale_factor)
	elif abs(card_id.hash()) % 3 == 1:
		draw_circle(pos + Vector2(34,0) * scale_factor, 16 * scale_factor, body.lightened(0.3))
	else:
		draw_line(pos + Vector2(-25,3) * scale_factor, pos + Vector2(-49,-27) * scale_factor, C_CYAN, 6 * scale_factor)

func _draw_tower(pos: Vector2, accent: Color, core: bool, scale_factor: float) -> void:
	var w := (120.0 if core else 95.0) * scale_factor
	var h := (140.0 if core else 118.0) * scale_factor
	draw_rect(Rect2(pos + Vector2(-w * 0.56, h * 0.32), Vector2(w * 1.12, h * 0.28)), Color(0,0,0,0.24), true)
	draw_rect(Rect2(pos - Vector2(w * 0.5, h * 0.45), Vector2(w, h * 0.9)), accent.darkened(0.42), true)
	draw_rect(Rect2(pos - Vector2(w * 0.44, h * 0.52), Vector2(w * 0.88, h * 0.24)), accent, true)
	for dx in [-0.32, 0.0, 0.32]:
		draw_rect(Rect2(pos + Vector2(w * dx - 11 * scale_factor, -h * 0.68), Vector2(22, 30) * scale_factor), accent.lightened(0.12), true)
	if core:
		_draw_emblem(pos + Vector2(0, 4), 22 * scale_factor, C_GOLD)

func _draw_health_bar(pos: Vector2, width: float, ratio: float, accent: Color) -> void:
	draw_rect(Rect2(pos, Vector2(width, 10)), Color("0a0f16"), true)
	draw_rect(Rect2(pos, Vector2(width * clampf(ratio, 0.0, 1.0), 10)), accent, true)

func _draw_vault_icon(center: Vector2, accent: Color, scale_factor: float) -> void:
	draw_circle(center + Vector2(0,22) * scale_factor, 70 * scale_factor, Color(0,0,0,0.24))
	draw_rect(Rect2(center - Vector2(70,45) * scale_factor, Vector2(140,105) * scale_factor), accent.darkened(0.45), true)
	draw_rect(Rect2(center - Vector2(62,60) * scale_factor, Vector2(124,40) * scale_factor), accent, true)
	draw_circle(center + Vector2(0,5) * scale_factor, 17 * scale_factor, accent.lightened(0.35))

func _draw_emblem(center: Vector2, radius: float, accent: Color) -> void:
	var pts := PackedVector2Array([
		center + Vector2(0,-radius),
		center + Vector2(radius * 0.86,-radius * 0.28),
		center + Vector2(radius * 0.55,radius * 0.82),
		center + Vector2(-radius * 0.55,radius * 0.82),
		center + Vector2(-radius * 0.86,-radius * 0.28)
	])
	draw_colored_polygon(pts, accent.darkened(0.18))
	draw_circle(center, radius * 0.40, accent.lightened(0.18))

func _draw_toast() -> void:
	draw_rect(Rect2(140, 1990 if current_screen != "battle" else 1890, 800, 92), Color(0.03,0.06,0.10,0.94), true)
	_text_centered(toast_text, Rect2(165, 2010 if current_screen != "battle" else 1910, 750, 55), 22, C_INK)

func _text(text: String, pos: Vector2, size_px: int, color: Color) -> void:
	draw_string(ThemeDB.fallback_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)

func _text_centered(text: String, rect: Rect2, size_px: int, color: Color) -> void:
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(0, size_px), text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, size_px, color)
