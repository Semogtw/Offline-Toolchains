extends Control

var model
var db
var profile
var battle
var current_screen: String = "home"
var training_mode: bool = false

func _ready() -> void:
	model = load("res://src/app/app_model.gd").new()
	db = load("res://src/autoload/content_db.gd").new()
	db.load_all()
	profile = load("res://src/core/profile.gd").new()
	mouse_filter = Control.MOUSE_FILTER_STOP
	queue_redraw()

func show_screen(screen_name: String) -> bool:
	if model == null:
		model = load("res://src/app/app_model.gd").new()
	if screen_name not in model.screen_names():
		return false
	current_screen = screen_name
	queue_redraw()
	return true

func start_battle(training: bool = false) -> void:
	if profile == null:
		profile = load("res://src/core/profile.gd").new()
	battle = load("res://src/core/battle_sim.gd").new(Time.get_ticks_msec())
	training_mode = training
	current_screen = "battle"
	queue_redraw()
