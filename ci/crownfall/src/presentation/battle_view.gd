extends Control

const W := 1080.0
const H := 2400.0
const ARENA_BOTTOM := 2180.0
const RIVER_Y := 1200.0

const BLUE := Color("58a6ff")
const BLUE_DARK := Color("173e70")
const RED := Color("ff657a")
const RED_DARK := Color("6f2636")
const GOLD := Color("ffd36a")
const ARCANA := Color("c77dff")
const INK := Color("f7f3e8")
const MUTED := Color("a8bdca")
const SHADOW := Color(0.01, 0.02, 0.03, 0.42)

var battle
var card_cycle
var db
var profile
var training_mode: bool = false

var visual_units: Dictionary = {}
var particles: Array = []
var tower_visuals: Dictionary = {}
var arena_time: float = 0.0
var shake_strength: float = 0.0
var reduced_motion: bool = false
var screen_shake: bool = true
var high_contrast: bool = false
var _context_battle_id: int = 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)
	visible = false

func bind_context(battle_ref, cycle_ref, db_ref, profile_ref, training: bool) -> void:
	battle = battle_ref
	card_cycle = cycle_ref
	db = db_ref
	profile = profile_ref
	training_mode = training
	visual_units.clear()
	particles.clear()
	tower_visuals.clear()
	shake_strength = 0.0
	_context_battle_id = 0 if battle == null else battle.get_instance_id() if battle is Object else int(Time.get_ticks_msec())
	if profile != null:
		configure_accessibility(profile.settings)
	if battle != null:
		sync_from_sim()
	queue_redraw()

func configure_accessibility(settings: Dictionary) -> void:
	reduced_motion = bool(settings.get("reduced_motion", false))
	screen_shake = bool(settings.get("screen_shake", true))
	high_contrast = bool(settings.get("high_contrast", false))
	queue_redraw()

func visual_profile(card_id: String) -> Dictionary:
	match card_id:
		"iron_warden": return {"silhouette":"warden", "motion":"march", "weapon":"sword_shield", "scale":1.0}
		"moss_colossus": return {"silhouette":"colossus", "motion":"lumber", "weapon":"stone_fists", "scale":1.28}
		"astral_sentinel": return {"silhouette":"winged", "motion":"hover", "weapon":"astral_spear", "scale":0.98}
		"spore_bomber": return {"silhouette":"bomber", "motion":"bounce", "weapon":"spore_bomb", "scale":0.90}
		"gearling_trio": return {"silhouette":"gearling", "motion":"scuttle", "weapon":"claws", "scale":0.76}
		"dune_lancer": return {"silhouette":"lancer", "motion":"charge", "weapon":"lance", "scale":1.03}
		"ember_fox": return {"silhouette":"fox", "motion":"prowl", "weapon":"flame_tail", "scale":0.86}
		"tempest_oracle": return {"silhouette":"oracle", "motion":"float", "weapon":"storm_staff", "scale":0.96}
		"crystal_witch": return {"silhouette":"crystal_mage", "motion":"glide", "weapon":"crystal_wand", "scale":0.94}
		"lumen_swarm": return {"silhouette":"sprite", "motion":"flutter", "weapon":"spark", "scale":0.68}
		"storm_knight": return {"silhouette":"heavy_knight", "motion":"stride", "weapon":"storm_hammer", "scale":1.08}
		"root_mender": return {"silhouette":"druid", "motion":"sway", "weapon":"root_staff", "scale":0.98}
		"void_manta": return {"silhouette":"manta", "motion":"glide", "weapon":"void_arc", "scale":1.16}
		"sunforged_ram": return {"silhouette":"ram", "motion":"charge", "weapon":"sun_horns", "scale":1.16}
		"rune_duelist": return {"silhouette":"duelist", "motion":"dash", "weapon":"twin_blades", "scale":0.94}
		"frost_owl": return {"silhouette":"owl", "motion":"flap", "weapon":"frost_talons", "scale":0.88}
		"thorn_bastion": return {"silhouette":"bastion", "motion":"rooted", "weapon":"thorn_crown", "scale":1.12}
		"prism_turret": return {"silhouette":"prism_turret", "motion":"pulse", "weapon":"prism_beam", "scale":1.0}
		"arc_coil": return {"silhouette":"arc_coil", "motion":"pulse", "weapon":"lightning", "scale":1.0}
		"sunwell": return {"silhouette":"sunwell", "motion":"pulse", "weapon":"radiance", "scale":1.05}
		"starfall": return {"silhouette":"spell_star", "motion":"fall", "weapon":"meteor", "scale":1.0}
		"gale_ring": return {"silhouette":"spell_ring", "motion":"spin", "weapon":"wind", "scale":1.0}
		"bloom_pulse": return {"silhouette":"spell_bloom", "motion":"bloom", "weapon":"healing", "scale":1.0}
		"time_shard": return {"silhouette":"spell_shard", "motion":"spin", "weapon":"time", "scale":1.0}
		_: return {"silhouette":"wanderer", "motion":"march", "weapon":"blade", "scale":1.0}

func sync_from_sim() -> void:
	if battle == null:
		return
	var seen: Dictionary = {}
	for entity in battle.entities:
		var serial: int = int(entity.get("serial", 0))
		seen[serial] = true
		var sim_pos: Vector2 = entity.get("pos", Vector2.ZERO)
		var hp: int = int(entity.get("hp", 1))
		var max_hp: int = maxi(1, int(entity.get("max_hp", 1)))
		if not visual_units.has(serial):
			visual_units[serial] = {
				"serial": serial,
				"card": str(entity.get("card", "")),
				"team": int(entity.get("team", 0)),
				"render_pos": sim_pos,
				"target_pos": sim_pos,
				"previous_target": sim_pos,
				"hp": hp,
				"max_hp": max_hp,
				"hit_flash": 0.0,
				"anim_time": float(serial % 11) * 0.17,
				"state": "spawn",
				"attack_pulse": 0.0,
				"facing": -1.0 if int(entity.get("team", 0)) == 0 else 1.0
			}
			_spawn_burst(sim_pos, _team_color(int(entity.get("team", 0))), 0.62, "spawn")
		else:
			var visual: Dictionary = visual_units[serial]
			var old_hp: int = int(visual.get("hp", hp))
			var old_target: Vector2 = visual.get("target_pos", sim_pos)
			visual.previous_target = old_target
			visual.target_pos = sim_pos
			visual.hp = hp
			visual.max_hp = max_hp
			var moved: float = old_target.distance_to(sim_pos)
			var cooldown: float = float(entity.get("cooldown", 0.0))
			var period: float = maxf(0.1, float(entity.get("attack_period", 0.9)))
			if hp < old_hp:
				visual.hit_flash = 1.0
				trigger_impact(sim_pos, clampf(float(old_hp - hp) / float(max_hp) * 4.0, 0.35, 1.2), _team_color(int(entity.get("team", 0))).lightened(0.35))
			if cooldown > period * 0.62:
				visual.state = "attack"
				visual.attack_pulse = 1.0
			elif moved > 1.0:
				visual.state = "move"
				visual.facing = signf(sim_pos.x - old_target.x) if absf(sim_pos.x - old_target.x) > 0.5 else visual.facing
			else:
				visual.state = "idle"
			visual_units[serial] = visual
	for serial_key in visual_units.keys():
		if not seen.has(serial_key):
			var vanished: Dictionary = visual_units[serial_key]
			_spawn_burst(vanished.get("render_pos", Vector2.ZERO), _team_color(int(vanished.get("team", 0))), 1.15, "death")
			visual_units.erase(serial_key)
	_sync_towers()

func _sync_towers() -> void:
	if battle == null:
		return
	var alive_ids: Dictionary = {}
	for tower in battle.towers:
		var id: String = str(tower.get("id", ""))
		alive_ids[id] = true
		var hp: int = int(tower.get("hp", 0))
		var max_hp: int = maxi(1, int(tower.get("max_hp", 1)))
		if not tower_visuals.has(id):
			tower_visuals[id] = {"hp": hp, "max_hp": max_hp, "flash": 0.0, "alive": bool(tower.get("alive", true))}
		else:
			var old: Dictionary = tower_visuals[id]
			if hp < int(old.get("hp", hp)):
				old.flash = 1.0
				trigger_impact(tower.get("pos", Vector2.ZERO), 0.8 if not bool(tower.get("core", false)) else 1.2, GOLD)
			if bool(old.get("alive", true)) and not bool(tower.get("alive", true)):
				_spawn_burst(tower.get("pos", Vector2.ZERO), GOLD, 1.8, "tower_death")
			old.hp = hp
			old.max_hp = max_hp
			old.alive = bool(tower.get("alive", true))
			tower_visuals[id] = old

func advance_visuals(delta: float) -> void:
	if delta <= 0.0:
		return
	arena_time += delta
	var smoothing: float = 1.0 if reduced_motion else 1.0 - exp(-delta * 13.0)
	for serial_key in visual_units.keys():
		var visual: Dictionary = visual_units[serial_key]
		var render_pos: Vector2 = visual.get("render_pos", Vector2.ZERO)
		var target_pos: Vector2 = visual.get("target_pos", render_pos)
		visual.render_pos = target_pos if reduced_motion else render_pos.lerp(target_pos, smoothing)
		visual.anim_time = float(visual.get("anim_time", 0.0)) + delta
		visual.hit_flash = maxf(0.0, float(visual.get("hit_flash", 0.0)) - delta * 5.5)
		visual.attack_pulse = maxf(0.0, float(visual.get("attack_pulse", 0.0)) - delta * 4.2)
		visual_units[serial_key] = visual
	for id in tower_visuals.keys():
		var tower_v: Dictionary = tower_visuals[id]
		tower_v.flash = maxf(0.0, float(tower_v.get("flash", 0.0)) - delta * 4.0)
		tower_visuals[id] = tower_v
	for i in range(particles.size() - 1, -1, -1):
		var p: Dictionary = particles[i]
		p.life = float(p.get("life", 0.0)) - delta
		if float(p.life) <= 0.0:
			particles.remove_at(i)
			continue
		if not reduced_motion:
			p.pos = p.get("pos", Vector2.ZERO) + p.get("vel", Vector2.ZERO) * delta
			p.vel = p.get("vel", Vector2.ZERO) * pow(0.12, delta)
		particles[i] = p
	shake_strength = maxf(0.0, shake_strength - delta * 5.5)
	queue_redraw()

func trigger_impact(pos: Vector2, intensity: float, color: Color) -> void:
	var count: int = 4 if reduced_motion else 9
	for i in range(count):
		var angle: float = TAU * float(i) / float(maxi(1, count)) + float((i * 37) % 11) * 0.03
		var speed: float = (80.0 + float((i * 29) % 95)) * maxf(0.35, intensity)
		particles.append({
			"pos": pos,
			"vel": Vector2(cos(angle), sin(angle)) * speed,
			"life": 0.24 + float(i % 4) * 0.045,
			"max_life": 0.42,
			"size": 5.0 + float(i % 3) * 2.5,
			"color": color,
			"kind": "impact"
		})
	if screen_shake and not reduced_motion:
		shake_strength = maxf(shake_strength, clampf(intensity, 0.0, 1.5))
	queue_redraw()

func presentation_snapshot() -> Dictionary:
	var units: Array = []
	for serial_key in visual_units.keys():
		units.append(visual_units[serial_key].duplicate(true))
	return {
		"visual_units": visual_units.size(),
		"units": units,
		"fx": particles.size(),
		"shake": shake_strength,
		"arena_time": arena_time,
		"reduced_motion": reduced_motion,
		"high_contrast": high_contrast
	}

func _process(delta: float) -> void:
	var host := get_parent()
	if host == null or not host.has_method("ui_snapshot"):
		return
	var screen_name: String = str(host.get("current_screen"))
	visible = screen_name == "battle"
	if not visible:
		return
	var host_battle = host.get("battle")
	if host_battle != battle:
		bind_context(host_battle, host.get("card_cycle"), host.get("db"), host.get("profile"), bool(host.get("training_mode")))
	else:
		card_cycle = host.get("card_cycle")
		profile = host.get("profile")
		training_mode = bool(host.get("training_mode"))
		if profile != null:
			configure_accessibility(profile.settings)
	if battle != null:
		sync_from_sim()
	advance_visuals(delta)

func _draw() -> void:
	if not visible:
		return
	var shake := Vector2.ZERO
	if shake_strength > 0.0 and not reduced_motion:
		shake = Vector2(sin(arena_time * 81.0), cos(arena_time * 67.0)) * shake_strength * 5.5
	draw_set_transform(shake)
	_draw_arena()
	if battle != null:
		_draw_towers()
		_draw_units()
	_draw_particles()
	_draw_hud()
	draw_set_transform(Vector2.ZERO)

func _draw_arena() -> void:
	# Layered grass with a warm central lane and cool shadowed edges.
	draw_rect(Rect2(0, 0, W, ARENA_BOTTOM), Color("10261f"), true)
	for band in range(14):
		var y: float = float(band) * 158.0
		var tint := Color("1d4635") if band % 2 == 0 else Color("183d31")
		draw_rect(Rect2(46, y, W - 92, 160), tint, true)
	# Soft lane carpets.
	for lane_x in [300.0, 780.0]:
		draw_rect(Rect2(lane_x - 112, 165, 224, 1940), Color(0.62, 0.62, 0.39, 0.055), true)
		for y in range(250, 2130, 128):
			var wobble: float = sin(float(y) * 0.031 + lane_x) * 8.0
			_draw_stone(Vector2(lane_x + wobble, float(y)), 0.82)
	# Decorative edge foliage and crystals.
	for i in range(13):
		var y2: float = 130.0 + float(i) * 158.0
		_draw_grass_clump(Vector2(76.0 + float(i % 2) * 22.0, y2), 0.8 + float(i % 3) * 0.12)
		_draw_grass_clump(Vector2(1004.0 - float(i % 2) * 22.0, y2 + 44.0), 0.82 + float((i + 1) % 3) * 0.1)
		if i % 3 == 0:
			_draw_crystal(Vector2(112.0, y2 + 38.0), BLUE if i % 2 == 0 else ARCANA, 0.62)
			_draw_crystal(Vector2(968.0, y2 + 92.0), RED if i % 2 == 0 else GOLD, 0.58)
	# River banks, animated water and foam.
	draw_rect(Rect2(45, RIVER_Y - 92, 990, 184), Color("163244"), true)
	draw_rect(Rect2(45, RIVER_Y - 78, 990, 156), Color("1f6780"), true)
	for line_i in range(7):
		var pts := PackedVector2Array()
		var base_y := RIVER_Y - 58.0 + float(line_i) * 19.0
		for x in range(50, 1035, 36):
			var phase := float(x) * 0.018 + arena_time * (1.1 + float(line_i) * 0.07)
			pts.append(Vector2(float(x), base_y + sin(phase) * 5.0))
		draw_polyline(pts, Color(0.55, 0.91, 1.0, 0.12 + float(line_i % 2) * 0.05), 3.0)
	# Bridges with drop shadow, stone anchors and planks.
	for bridge_x in [300.0, 780.0]:
		_draw_bridge(bridge_x)
	# Player-side deployment aura kept subtle.
	draw_rect(Rect2(48, RIVER_Y + 95, 984, 1000), Color(0.22, 0.48, 0.78, 0.025), true)

func _draw_bridge(center_x: float) -> void:
	draw_rect(Rect2(center_x - 83, RIVER_Y - 108, 166, 216), Color(0,0,0,0.25), true)
	draw_rect(Rect2(center_x - 76, RIVER_Y - 116, 152, 232), Color("55472f"), true)
	for plank in range(7):
		var y := RIVER_Y - 101.0 + float(plank) * 31.0
		var light := Color("b28a52") if plank % 2 == 0 else Color("977342")
		draw_rect(Rect2(center_x - 70, y, 140, 25), light, true)
		draw_line(Vector2(center_x - 66, y + 4), Vector2(center_x + 66, y + 4), light.lightened(0.14), 2.0)
	for side in [-1.0, 1.0]:
		draw_circle(Vector2(center_x + side * 86.0, RIVER_Y - 91), 20, Color("6d6856"))
		draw_circle(Vector2(center_x + side * 86.0, RIVER_Y + 91), 20, Color("6d6856"))

func _draw_stone(center: Vector2, scale_factor: float) -> void:
	var pts := PackedVector2Array([
		center + Vector2(-58,-22) * scale_factor,
		center + Vector2(-36,-35) * scale_factor,
		center + Vector2(48,-31) * scale_factor,
		center + Vector2(62,-8) * scale_factor,
		center + Vector2(44,27) * scale_factor,
		center + Vector2(-45,30) * scale_factor
	])
	draw_colored_polygon(pts, Color(0.78,0.78,0.62,0.075))
	draw_polyline(PackedVector2Array([pts[0],pts[1],pts[2],pts[3]]), Color(1,1,0.8,0.045), 2.0)

func _draw_grass_clump(pos: Vector2, scale_factor: float) -> void:
	var color := Color("2e6a47")
	for i in range(5):
		var dx := (float(i) - 2.0) * 8.0 * scale_factor
		draw_line(pos + Vector2(dx, 12) * scale_factor, pos + Vector2(dx + sin(float(i))*7.0, -19 - float(i%2)*9.0) * scale_factor, color.lightened(float(i) * 0.025), 5.0 * scale_factor)

func _draw_crystal(pos: Vector2, color: Color, scale_factor: float) -> void:
	var pulse: float = 1.0 + sin(arena_time * 2.1 + pos.y * 0.01) * 0.05
	var s := scale_factor * pulse
	var pts := PackedVector2Array([pos + Vector2(0,-30)*s, pos + Vector2(16,-5)*s, pos + Vector2(9,26)*s, pos + Vector2(-12,21)*s, pos + Vector2(-18,-4)*s])
	draw_colored_polygon(pts, color.darkened(0.18))
	draw_polyline(PackedVector2Array([pts[0],pts[1],pts[2]]), color.lightened(0.28), 3.0)

func _draw_towers() -> void:
	for tower in battle.towers:
		if not bool(tower.get("alive", true)):
			continue
		var id: String = str(tower.get("id", ""))
		var tv: Dictionary = tower_visuals.get(id, {})
		_draw_tower_actor(tower, float(tv.get("flash", 0.0)))

func _draw_tower_actor(tower: Dictionary, flash: float) -> void:
	var pos: Vector2 = tower.get("pos", Vector2.ZERO)
	var team: int = int(tower.get("team", 0))
	var core: bool = bool(tower.get("core", false))
	var accent := _team_color(team)
	var dark := BLUE_DARK if team == 0 else RED_DARK
	var pulse := 1.0 + sin(arena_time * 2.4 + pos.x * 0.01) * (0.018 if core else 0.009)
	var w := (118.0 if core else 94.0) * pulse
	var h := (154.0 if core else 126.0) * pulse
	# broad soft shadow
	draw_set_transform(pos)
	draw_circle(Vector2(0, h*0.38), w*0.68, Color(0,0,0,0.24))
	# masonry base and taper
	var base_pts := PackedVector2Array([Vector2(-w*0.56,h*0.38),Vector2(w*0.56,h*0.38),Vector2(w*0.43,-h*0.36),Vector2(-w*0.43,-h*0.36)])
	draw_colored_polygon(base_pts, dark.lightened(0.05))
	draw_rect(Rect2(-w*0.48, -h*0.18, w*0.96, h*0.14), accent.darkened(0.18), true)
	# crown deck
	draw_rect(Rect2(-w*0.51,-h*0.50,w*1.02,h*0.24), dark.lightened(0.12), true)
	for dx in [-0.36,0.0,0.36]:
		draw_rect(Rect2(w*dx-11,-h*0.66,22,h*0.22), accent.lightened(0.08), true)
	# doorway + team banner
	draw_rect(Rect2(-14,h*0.08,28,h*0.31), Color("09131d"), true)
	draw_rect(Rect2(-w*0.36,-h*0.18,16,h*0.42), accent.darkened(0.1), true)
	if core:
		var crystal_pos := Vector2(0,-h*0.22)
		draw_circle(crystal_pos, 28 + sin(arena_time*3.0)*3, Color(accent.r,accent.g,accent.b,0.16))
		_draw_rune(crystal_pos, 22, GOLD)
	else:
		draw_circle(Vector2(0,-h*0.19), 17, accent)
	if flash > 0.0:
		draw_rect(Rect2(-w*0.55,-h*0.67,w*1.1,h*1.1), Color(1,1,1,flash*0.34), true)
	draw_set_transform(Vector2.ZERO)
	var hp_ratio: float = float(tower.get("hp",0)) / maxf(1.0,float(tower.get("max_hp",1)))
	_draw_health(Vector2(pos.x - 69,pos.y - h*0.79),138,hp_ratio,accent,core)

func _draw_units() -> void:
	var ordered: Array = visual_units.values()
	ordered.sort_custom(func(a, b): return float(a.get("render_pos",Vector2.ZERO).y) < float(b.get("render_pos",Vector2.ZERO).y))
	for visual in ordered:
		_draw_unit_actor(visual)

func _draw_unit_actor(visual: Dictionary) -> void:
	var card_id: String = str(visual.get("card", ""))
	var vp: Dictionary = visual_profile(card_id)
	var pos: Vector2 = visual.get("render_pos", Vector2.ZERO)
	var team: int = int(visual.get("team",0))
	var state: String = str(visual.get("state","idle"))
	var t: float = float(visual.get("anim_time",0.0))
	var attack: float = float(visual.get("attack_pulse",0.0))
	var hit: float = float(visual.get("hit_flash",0.0))
	var scale_factor: float = 0.76 * float(vp.get("scale",1.0))
	var motion: String = str(vp.get("motion","march"))
	var bob: float = 0.0
	var lean: float = 0.0
	if not reduced_motion:
		match motion:
			"hover", "float", "glide": bob = sin(t*3.4) * 8.0
			"flutter", "flap": bob = sin(t*7.2) * 7.0
			"bounce", "scuttle": bob = absf(sin(t*6.0))*5.0
			"charge", "dash": bob = sin(t*8.0)*3.0
			_: bob = sin(t*(5.0 if state=="move" else 2.6))*3.2
		if state == "move":
			lean = clampf(float(visual.get("facing",1.0))*0.07,-0.09,0.09)
		if state == "attack":
			lean += (1.0 - attack) * 0.14 * float(visual.get("facing",1.0))
	var actor_pos := pos + Vector2(0,bob)
	var accent := _card_accent(card_id)
	var team_color := _team_color(team)
	# shadow, allegiance ring and optional air halo
	draw_circle(pos + Vector2(0,31)*scale_factor, 36*scale_factor, SHADOW)
	if str(vp.get("motion","")) in ["hover","float","glide","flutter","flap"]:
		draw_arc(pos + Vector2(0,23)*scale_factor, 33*scale_factor, 0, TAU, 28, Color(team_color.r,team_color.g,team_color.b,0.30), 3.0)
	else:
		draw_arc(pos + Vector2(0,25)*scale_factor, 31*scale_factor, 0, TAU, 26, Color(team_color.r,team_color.g,team_color.b,0.42), 4.0)
	draw_set_transform(actor_pos, lean, Vector2.ONE*scale_factor)
	_draw_silhouette(str(vp.get("silhouette","wanderer")), accent, team_color, t, attack)
	if hit > 0.0:
		draw_circle(Vector2.ZERO, 46, Color(1,1,1,hit*0.34))
	draw_set_transform(Vector2.ZERO)
	var hp_ratio: float = float(visual.get("hp",1)) / maxf(1.0,float(visual.get("max_hp",1)))
	_draw_health(Vector2(pos.x-33,pos.y-67*scale_factor),66,hp_ratio,team_color,false)

func _draw_silhouette(kind: String, accent: Color, team_color: Color, t: float, attack: float) -> void:
	var dark := accent.darkened(0.40)
	var light := accent.lightened(0.22)
	var eye := Color.WHITE if not high_contrast else GOLD
	match kind:
		"warden", "heavy_knight":
			var heavy := kind == "heavy_knight"
			draw_colored_polygon(PackedVector2Array([Vector2(-25,42),Vector2(25,42),Vector2(31,-5),Vector2(18,-30),Vector2(-18,-30),Vector2(-31,-5)]), dark)
			draw_circle(Vector2(0,-31),26 if heavy else 22,accent)
			draw_rect(Rect2(-25,-48,50,13),light,true)
			if heavy: draw_rect(Rect2(-31,-9,62,21),accent.darkened(0.12),true)
			_draw_weapon("storm_hammer" if heavy else "sword_shield",accent,attack)
			draw_circle(Vector2(-8,-31),3.4,eye); draw_circle(Vector2(8,-31),3.4,eye)
		"colossus":
			draw_circle(Vector2(0,5),41,dark)
			draw_circle(Vector2(0,-35),31,accent)
			draw_circle(Vector2(-35,4),22,light.darkened(0.08)); draw_circle(Vector2(35,4),22,light.darkened(0.08))
			for x in [-22.0,0.0,22.0]: draw_line(Vector2(x,-57),Vector2(x+5,-72),Color("78a65d"),7)
			draw_circle(Vector2(-10,-37),4,eye); draw_circle(Vector2(10,-37),4,eye)
		"winged":
			draw_colored_polygon(PackedVector2Array([Vector2(-9,6),Vector2(-56,-25),Vector2(-42,23),Vector2(-8,38)]),accent.darkened(0.18))
			draw_colored_polygon(PackedVector2Array([Vector2(9,6),Vector2(56,-25),Vector2(42,23),Vector2(8,38)]),accent.lightened(0.06))
			draw_rect(Rect2(-15,-18,30,52),dark,true); draw_circle(Vector2(0,-30),19,light)
			draw_line(Vector2(24,12),Vector2(48,-43-attack*18),GOLD,6)
		"bomber":
			draw_circle(Vector2(0,4),30,dark); draw_circle(Vector2(0,-28),22,accent)
			draw_circle(Vector2(36,8),20,Color("58492f")); draw_circle(Vector2(36,8),12,Color("9b5f3b"))
			draw_line(Vector2(34,-12),Vector2(43,-30),Color("f4d268"),4)
		"gearling":
			draw_circle(Vector2(0,0),28,dark)
			for i in range(8):
				var a := TAU*float(i)/8.0+t*0.6
				draw_rect(Rect2(Vector2(cos(a),sin(a))*30-Vector2(6,6),Vector2(12,12)),accent,true)
			draw_circle(Vector2(0,0),15,light); draw_circle(Vector2(0,0),6,team_color)
		"lancer":
			draw_colored_polygon(PackedVector2Array([Vector2(-31,33),Vector2(31,33),Vector2(20,-28),Vector2(-17,-28)]),dark)
			draw_circle(Vector2(0,-37),21,accent)
			draw_line(Vector2(18,3),Vector2(62,-30-attack*30),light,7); draw_circle(Vector2(-25,23),16,accent.darkened(0.1))
		"fox":
			draw_colored_polygon(PackedVector2Array([Vector2(-35,22),Vector2(22,28),Vector2(34,-4),Vector2(5,-25),Vector2(-29,-12)]),dark)
			draw_colored_polygon(PackedVector2Array([Vector2(-20,-15),Vector2(-8,-47),Vector2(0,-23),Vector2(14,-49),Vector2(23,-15)]),accent)
			draw_colored_polygon(PackedVector2Array([Vector2(24,14),Vector2(61,-10),Vector2(49,28)]),Color("ff7b45"))
			draw_circle(Vector2(-5,-18),3.5,eye); draw_circle(Vector2(9,-18),3.5,eye)
		"oracle", "crystal_mage", "druid":
			var robe := PackedVector2Array([Vector2(-30,42),Vector2(31,42),Vector2(21,-17),Vector2(-19,-17)])
			draw_colored_polygon(robe,dark); draw_circle(Vector2(0,-30),21,accent)
			if kind == "crystal_mage":
				for x in [-17.0,0.0,17.0]: draw_colored_polygon(PackedVector2Array([Vector2(x,-43),Vector2(x+8,-62),Vector2(x+13,-39)]),light)
			elif kind == "druid":
				draw_arc(Vector2(0,-34),27,PI,TAU,12,Color("78b95a"),6)
			_draw_weapon("staff",accent,attack)
		"sprite":
			var flap := sin(t*9.0)*8.0
			draw_circle(Vector2(0,0),16,light)
			draw_colored_polygon(PackedVector2Array([Vector2(-8,0),Vector2(-42,-24-flap),Vector2(-32,17),Vector2(-5,10)]),Color(accent.r,accent.g,accent.b,0.72))
			draw_colored_polygon(PackedVector2Array([Vector2(8,0),Vector2(42,-24+flap),Vector2(32,17),Vector2(5,10)]),Color(accent.r,accent.g,accent.b,0.72))
			draw_circle(Vector2(0,0),6,eye)
		"manta":
			var wave := sin(t*4.0)*5.0
			draw_colored_polygon(PackedVector2Array([Vector2(0,-32),Vector2(58,wave),Vector2(18,35),Vector2(0,22),Vector2(-18,35),Vector2(-58,-wave)]),dark)
			draw_colored_polygon(PackedVector2Array([Vector2(0,-24),Vector2(42,0),Vector2(0,13),Vector2(-42,0)]),accent)
			draw_circle(Vector2(0,-7),7,Color("b899ff"))
		"ram":
			draw_rect(Rect2(-37,-14,74,52),dark,true); draw_circle(Vector2(0,-24),28,accent)
			draw_arc(Vector2(-22,-29),20,PI*0.45,PI*1.55,12,GOLD,7); draw_arc(Vector2(22,-29),20,PI*1.45,PI*0.55+TAU,12,GOLD,7)
			draw_circle(Vector2(-9,-24),3,eye); draw_circle(Vector2(9,-24),3,eye)
		"duelist":
			draw_colored_polygon(PackedVector2Array([Vector2(-22,39),Vector2(22,39),Vector2(17,-22),Vector2(-17,-22)]),dark)
			draw_circle(Vector2(0,-34),20,accent)
			draw_line(Vector2(-16,3),Vector2(-48,-35-attack*20),light,5); draw_line(Vector2(16,3),Vector2(48,-35-attack*20),light,5)
		"owl":
			var flap2 := sin(t*8.0)*12.0
			draw_circle(Vector2(0,-14),24,accent)
			draw_colored_polygon(PackedVector2Array([Vector2(-12,-3),Vector2(-52,-15-flap2),Vector2(-32,27),Vector2(-5,20)]),dark)
			draw_colored_polygon(PackedVector2Array([Vector2(12,-3),Vector2(52,-15+flap2),Vector2(32,27),Vector2(5,20)]),light.darkened(0.1))
			draw_circle(Vector2(-9,-18),6,eye); draw_circle(Vector2(9,-18),6,eye); draw_colored_polygon(PackedVector2Array([Vector2(-5,-7),Vector2(5,-7),Vector2(0,2)]),GOLD)
		"bastion", "prism_turret", "arc_coil", "sunwell":
			_draw_structure_unit(kind,accent,t)
		_:
			draw_rect(Rect2(-22,-10,44,52),dark,true); draw_circle(Vector2(0,-28),22,accent); _draw_weapon("blade",accent,attack)

func _draw_structure_unit(kind: String, accent: Color, t: float) -> void:
	draw_rect(Rect2(-37,8,74,34),accent.darkened(0.48),true)
	if kind == "bastion":
		draw_rect(Rect2(-31,-32,62,44),accent.darkened(0.18),true)
		for x in [-22.0,0.0,22.0]: draw_rect(Rect2(x-7,-45,14,18),accent,true)
	elif kind == "prism_turret":
		draw_rect(Rect2(-22,-16,44,28),accent.darkened(0.2),true)
		var spin := t*1.7
		var tip := Vector2(cos(spin),sin(spin))*25
		draw_colored_polygon(PackedVector2Array([tip+Vector2(0,-27),tip+Vector2(20,10),tip+Vector2(-20,10)]),accent.lightened(0.25))
	elif kind == "arc_coil":
		for y in [-22.0,-6.0,10.0]: draw_arc(Vector2(0,y),27,0,TAU,18,accent.lightened(0.12),5)
		draw_circle(Vector2(0,-35),8,Color.WHITE)
	else:
		draw_circle(Vector2(0,-4),30,accent.darkened(0.15)); draw_circle(Vector2(0,-4),16,GOLD)
		for i in range(8):
			var a:=TAU*float(i)/8.0+t*0.4
			draw_line(Vector2(cos(a),sin(a))*22,Vector2(cos(a),sin(a))*38,GOLD,4)

func _draw_weapon(kind: String, accent: Color, attack: float) -> void:
	match kind:
		"sword_shield":
			draw_circle(Vector2(-32,2),17,accent.lightened(0.12)); draw_line(Vector2(22,10),Vector2(43,-36-attack*18),INK,6)
		"storm_hammer":
			draw_line(Vector2(22,12),Vector2(42,-28-attack*20),Color("b8d8e8"),7); draw_rect(Rect2(31,-46-attack*20,25,17),ARCANA,true)
		"staff":
			draw_line(Vector2(24,24),Vector2(37,-48),Color("80633d"),6); draw_circle(Vector2(37,-51),10,accent.lightened(0.28))
		_:
			draw_line(Vector2(23,8),Vector2(45,-29-attack*13),accent.lightened(0.28),5)

func _draw_health(pos: Vector2, width: float, ratio: float, accent: Color, crown: bool) -> void:
	var height := 13.0 if crown else 9.0
	draw_rect(Rect2(pos-Vector2(2,2),Vector2(width+4,height+4)),Color(0.02,0.03,0.04,0.80),true)
	draw_rect(Rect2(pos,Vector2(width,height)),Color("182029"),true)
	draw_rect(Rect2(pos,Vector2(width*clampf(ratio,0.0,1.0),height)),accent,true)
	if crown and ratio > 0.0:
		draw_circle(pos+Vector2(width+13,height*0.5),5,GOLD)

func _draw_particles() -> void:
	for p in particles:
		var life: float = float(p.get("life",0.0))
		var max_life: float = maxf(0.01,float(p.get("max_life",0.4)))
		var alpha: float = clampf(life/max_life,0.0,1.0)
		var color: Color = p.get("color",Color.WHITE)
		color.a *= alpha
		var pos: Vector2 = p.get("pos",Vector2.ZERO)
		var size_p: float = float(p.get("size",5.0))*maxf(0.35,alpha)
		if str(p.get("kind","")) == "spark":
			draw_line(pos-Vector2(size_p,0),pos+Vector2(size_p,0),color,2.5)
		else:
			draw_circle(pos,size_p,color)

func _draw_hud() -> void:
	if battle == null:
		return
	# top timer plaque
	draw_rect(Rect2(330,22,420,102),Color(0.025,0.04,0.065,0.94),true)
	draw_rect(Rect2(330,22,420,5),GOLD if str(battle.clock.phase)=="overtime" else BLUE,true)
	var remaining: float = float(battle.clock.remaining())
	var mins: int = int(remaining) / 60
	var secs: int = int(remaining) % 60
	_text_centered("OVERTIME" if str(battle.clock.phase)=="overtime" else "CROWNFALL",Rect2(350,39,380,26),18,GOLD if str(battle.clock.phase)=="overtime" else MUTED)
	_text_centered("%d:%02d" % [mins,secs],Rect2(350,68,380,43),35,INK)
	# arcana glass tube
	draw_rect(Rect2(50,2042,484,72),Color(0.03,0.04,0.075,0.94),true)
	_text("ARCANA",Vector2(72,2070),17,MUTED)
	var ratio: float = clampf(float(battle.player_arcana.value)/10.0,0.0,1.0)
	draw_rect(Rect2(160,2057,340,35),Color("241932"),true)
	for pip in range(10):
		var pip_x := 164.0+float(pip)*33.3
		var filled := ratio*10.0 > float(pip)
		draw_rect(Rect2(pip_x,2061,28,27),ARCANA if filled else Color("3b2b4b"),true)
	_text("%.1f" % float(battle.player_arcana.value),Vector2(505,2083),18,INK)
	# hand dock with raised selected card and clear cost pips
	draw_rect(Rect2(0,2145,W,255),Color("081018"),true)
	if card_cycle != null and not battle.finished:
		var host := get_parent()
		var selected: int = 0 if host == null else int(host.get("selected_hand_slot"))
		for i in range(card_cycle.hand.size()):
			var card_id: String = str(card_cycle.hand[i])
			var y := 2170.0 - (18.0 if i==selected else 0.0)
			_draw_hand_card(card_id,Rect2(38+float(i)*250.0,y,226,210),i==selected)
		var next_card: String = str(card_cycle.next_card)
		_text("NEXT",Vector2(985,2163),14,MUTED)
		if not next_card.is_empty():
			draw_circle(Vector2(1010,2197),20,_card_accent(next_card))
	if training_mode:
		_draw_training_prompt()
	if battle.finished:
		_draw_result_panel()

func _draw_hand_card(card_id: String, rect: Rect2, selected: bool) -> void:
	if db == null or not db.cards.has(card_id):
		return
	var card: Dictionary = db.cards[card_id]
	var accent := _card_accent(card_id)
	if selected:
		draw_rect(Rect2(rect.position-Vector2(5,5),rect.size+Vector2(10,10)),Color(accent.r,accent.g,accent.b,0.8),true)
	draw_rect(rect,Color("162333") if not selected else Color("25344b"),true)
	draw_rect(Rect2(rect.position,Vector2(rect.size.x,6)),accent,true)
	var family: String = str(card.get("family","troop"))
	_draw_mini_icon(rect.position+Vector2(rect.size.x*0.5,76),card_id,family,accent)
	_text_centered(str(card.get("name",card_id)),Rect2(rect.position.x+8,rect.position.y+121,rect.size.x-16,28),15,INK)
	draw_circle(rect.position+Vector2(29,29),23,ARCANA)
	_text_centered(str(card.get("cost",0)),Rect2(rect.position.x+10,rect.position.y+14,38,24),17,Color.WHITE)
	var level: int = 1 if profile==null else int(profile.levels.get(card_id,1))
	_text("LV.%d" % level,rect.position+Vector2(13,192),13,MUTED)

func _draw_mini_icon(center: Vector2, card_id: String, family: String, accent: Color) -> void:
	if family == "spell":
		draw_circle(center,31,Color(accent.r,accent.g,accent.b,0.16)); _draw_rune(center,24,accent)
	elif family == "structure":
		draw_rect(Rect2(center-Vector2(34,16),Vector2(68,45)),accent.darkened(0.34),true); draw_colored_polygon(PackedVector2Array([center+Vector2(0,-43),center+Vector2(31,-9),center+Vector2(-31,-9)]),accent)
	else:
		var vp := visual_profile(card_id)
		draw_set_transform(center,0,Vector2.ONE*0.55)
		_draw_silhouette(str(vp.get("silhouette","wanderer")),accent,BLUE,arena_time,0.0)
		draw_set_transform(Vector2.ZERO)

func _draw_training_prompt() -> void:
	var host := get_parent()
	if host == null or host.get("model") == null:
		return
	var steps: Array = host.get("model").tutorial_steps()
	var idx: int = mini(int(host.get("tutorial_step")),steps.size()-1)
	if idx < 0 or idx >= steps.size():
		return
	var step: Dictionary = steps[idx]
	draw_rect(Rect2(110,145,860,118),Color(0.025,0.05,0.075,0.94),true)
	draw_rect(Rect2(110,145,7,118),BLUE,true)
	_text("TRAINING %d/7  ·  %s" % [mini(idx+1,7),str(step.get("title",""))],Vector2(144,190),22,BLUE.lightened(0.18))
	_text(str(step.get("hint","")),Vector2(144,231),18,MUTED)

func _draw_result_panel() -> void:
	var won: bool = int(battle.winner)==int(battle.PLAYER)
	var draw_game: bool = int(battle.winner)<0
	var accent := GOLD if draw_game else (Color("71e3a0") if won else RED)
	draw_rect(Rect2(105,700,870,620),Color(0.02,0.035,0.055,0.96),true)
	draw_rect(Rect2(105,700,870,8),accent,true)
	_draw_rune(Vector2(540,845),78,accent)
	_text_centered("DRAW" if draw_game else ("CITADEL SECURED" if won else "CITADEL FALLEN"),Rect2(145,970,790,62),43,accent)
	_text_centered("The battlefield remembers every strike.",Rect2(145,1055,790,38),21,MUTED)
	_text_centered("Progress saved locally",Rect2(145,1110,790,32),18,MUTED)

func _draw_rune(center: Vector2, radius: float, color: Color) -> void:
	var pulse := 1.0 + sin(arena_time*3.2)*0.04
	var r := radius*pulse
	draw_arc(center,r,0,TAU,24,Color(color.r,color.g,color.b,0.55),4.0)
	draw_arc(center,r*0.66,arena_time*0.3,arena_time*0.3+PI*1.5,18,color,3.0)
	for i in range(4):
		var a:=TAU*float(i)/4.0+arena_time*0.18
		var p1:=center+Vector2(cos(a),sin(a))*r*0.28
		var p2:=center+Vector2(cos(a),sin(a))*r*0.82
		draw_line(p1,p2,Color(color.r,color.g,color.b,0.62),3.0)
	draw_circle(center,r*0.17,color.lightened(0.22))

func _spawn_burst(pos: Vector2, color: Color, intensity: float, kind: String) -> void:
	var count: int = 5 if reduced_motion else (8 if intensity < 1.0 else 14)
	for i in range(count):
		var angle: float = TAU*float(i)/float(maxi(1,count))+float((i*13)%7)*0.07
		var speed: float = 65.0+float((i*31)%120)*intensity
		particles.append({"pos":pos,"vel":Vector2(cos(angle),sin(angle))*speed,"life":0.34+float(i%4)*0.07,"max_life":0.58,"size":4.5+float(i%4)*2.0,"color":color,"kind":kind})
	if kind in ["death","tower_death"] and screen_shake and not reduced_motion:
		shake_strength=maxf(shake_strength,0.55*intensity)

func _team_color(team: int) -> Color:
	return BLUE if team == 0 else RED

func _card_accent(card_id: String) -> Color:
	var fixed := {
		"iron_warden":Color("6ec6ff"), "moss_colossus":Color("78b85c"), "astral_sentinel":Color("a59bff"),
		"spore_bomber":Color("d99a69"), "gearling_trio":Color("f0b85b"), "dune_lancer":Color("e7c17a"),
		"ember_fox":Color("ff754d"), "tempest_oracle":Color("65d9e8"), "crystal_witch":Color("c477ff"),
		"lumen_swarm":Color("fff08a"), "storm_knight":Color("7ca8ff"), "root_mender":Color("6fc77b"),
		"void_manta":Color("8d6bd8"), "sunforged_ram":Color("ffc85a"), "rune_duelist":Color("e66c9c"),
		"frost_owl":Color("b8efff"), "thorn_bastion":Color("6a9b58"), "prism_turret":Color("a779ff"),
		"arc_coil":Color("6bd6ff"), "sunwell":Color("ffcf5c"), "starfall":Color("9f86ff"),
		"gale_ring":Color("7ee1cf"), "bloom_pulse":Color("80e68e"), "time_shard":Color("79aaff")
	}
	if fixed.has(card_id):
		return fixed[card_id]
	var hue: float = float(abs(card_id.hash())%1000)/1000.0
	return Color.from_hsv(hue,0.58,0.92)

func _text(text: String, pos: Vector2, size_px: int, color: Color) -> void:
	draw_string(ThemeDB.fallback_font,pos,text,HORIZONTAL_ALIGNMENT_LEFT,-1,size_px,color)

func _text_centered(text: String, rect: Rect2, size_px: int, color: Color) -> void:
	draw_string(ThemeDB.fallback_font,rect.position+Vector2(0,size_px),text,HORIZONTAL_ALIGNMENT_CENTER,rect.size.x,size_px,color)
