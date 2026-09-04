extends RefCounted

const PLAYER := 0
const ENEMY := 1
const ENTITY_CAP := 128
const STARTER_DECK := [
	"iron_warden", "moss_colossus", "astral_sentinel", "spore_bomber",
	"gearling_trio", "prism_turret", "starfall", "gale_ring"
]

var db
var player_arcana
var enemy_arcana
var clock
var entities: Array = []
var towers: Array = []
var finished: bool = false
var winner: int = -1
var rng := RandomNumberGenerator.new()
var enemy_deck: Array = STARTER_DECK.duplicate()
var _serial: int = 0

func _init(seed: int = 1) -> void:
	db = load("res://src/autoload/content_db.gd").new()
	db.load_all()
	player_arcana = load("res://src/core/arcana.gd").new(5.0)
	enemy_arcana = load("res://src/core/arcana.gd").new(5.0)
	clock = load("res://src/core/battle_clock.gd").new()
	rng.seed = seed
	_reset_towers()

func _reset_towers() -> void:
	towers = [
		_tower("enemy_core", ENEMY, Vector2(540, 290), 4400, true),
		_tower("enemy_left", ENEMY, Vector2(280, 570), 2800, false),
		_tower("enemy_right", ENEMY, Vector2(800, 570), 2800, false),
		_tower("player_left", PLAYER, Vector2(280, 1830), 2800, false),
		_tower("player_right", PLAYER, Vector2(800, 1830), 2800, false),
		_tower("player_core", PLAYER, Vector2(540, 2110), 4400, true)
	]

func _tower(id: String, team: int, pos: Vector2, hp: int, core: bool) -> Dictionary:
	return {"id": id, "team": team, "pos": pos, "hp": hp, "max_hp": hp, "alive": true, "core": core, "cooldown": 0.0}

func get_tower(id: String) -> Dictionary:
	for tower in towers:
		if str(tower.id) == id:
			return tower
	return {}

func is_legal_deploy(card_id: String, pos: Vector2, team: int) -> bool:
	if finished or not db.cards.has(card_id): return false
	if pos.x < 55.0 or pos.x > 1025.0 or pos.y < 230.0 or pos.y > 2170.0: return false
	var card: Dictionary = db.cards[card_id]
	if str(card.family) == "spell":
		return true
	if team == PLAYER:
		return pos.y >= 1240.0 and pos.y <= 2010.0
	return pos.y >= 390.0 and pos.y <= 1160.0

func deploy(card_id: String, pos: Vector2, team: int) -> bool:
	if not is_legal_deploy(card_id, pos, team): return false
	var card: Dictionary = db.cards[card_id]
	var pool = player_arcana if team == PLAYER else enemy_arcana
	if not pool.try_spend(int(card.cost)): return false
	if str(card.family) == "spell":
		_cast_spell(card, pos, team)
		return true
	var count: int = int(card.get("count", 1))
	for i in range(count):
		if entities.size() >= ENTITY_CAP: break
		var spread := Vector2((i - (count - 1) * 0.5) * 34.0, absf(i - (count - 1) * 0.5) * 18.0)
		_spawn_entity(card, team, pos + spread)
	return true

func spawn_for_test(card_id: String, team: int, pos: Vector2) -> bool:
	if entities.size() >= ENTITY_CAP or not db.cards.has(card_id): return false
	var card: Dictionary = db.cards[card_id]
	_spawn_entity(card, team, pos)
	return true

func _spawn_entity(card: Dictionary, team: int, pos: Vector2) -> void:
	_serial += 1
	var hp: int = maxi(1, int(card.hp))
	entities.append({
		"serial": _serial,
		"card": str(card.id),
		"family": str(card.family),
		"team": team,
		"pos": pos,
		"hp": hp,
		"max_hp": hp,
		"damage": int(card.damage),
		"speed": float(card.speed),
		"range": float(card.range),
		"cooldown": rng.randf_range(0.0, 0.35),
		"attack_period": 0.9 if str(card.id) != "storm_knight" else 1.15,
		"air": str(card.id) in ["astral_sentinel", "lumen_swarm", "void_manta", "frost_owl"],
		"structure_focus": str(card.id) in ["moss_colossus", "sunforged_ram"],
		"slow": 0.0
	})

func _cast_spell(card: Dictionary, pos: Vector2, team: int) -> void:
	var id: String = str(card.id)
	var radius: float = float(card.range)
	if id == "bloom_pulse":
		for entity in entities:
			if int(entity.team) == team and entity.pos.distance_to(pos) <= radius:
				entity.hp = mini(int(entity.max_hp), int(entity.hp) + 360)
		return
	for entity in entities:
		if int(entity.team) != team and entity.pos.distance_to(pos) <= radius:
			var scale := 1.0
			if id == "starfall": scale = 1.25
			entity.hp -= int(absf(float(card.damage)) * scale)
			if id == "gale_ring":
				var away: Vector2 = (entity.pos - pos).normalized()
				entity.pos += away * 72.0
			if id == "time_shard": entity.slow = 2.4
	for tower in towers:
		if bool(tower.alive) and int(tower.team) != team and tower.pos.distance_to(pos) <= radius:
			damage_tower(str(tower.id), int(absf(float(card.damage)) * 0.55), team)
	_cleanup_dead()

func step(delta: float) -> void:
	if finished or delta <= 0.0: return
	clock.tick(delta)
	var multiplier: float = clock.arcana_multiplier()
	player_arcana.tick(delta, multiplier)
	enemy_arcana.tick(delta, multiplier)
	_update_entities(delta)
	_update_towers(delta)
	_cleanup_dead()
	if clock.phase == "expired" and not finished:
		_finish_by_health()

func _update_entities(delta: float) -> void:
	for entity in entities:
		if int(entity.hp) <= 0: continue
		entity.cooldown = maxf(0.0, float(entity.cooldown) - delta)
		entity.slow = maxf(0.0, float(entity.slow) - delta)
		var target_entity: Dictionary = _nearest_enemy_entity(entity)
		var target_tower: Dictionary = _nearest_enemy_tower(entity)
		var target_pos: Vector2
		var target_is_entity := false
		if not bool(entity.structure_focus) and not target_entity.is_empty():
			var e_dist: float = entity.pos.distance_to(target_entity.pos)
			var t_dist: float = 99999.0 if target_tower.is_empty() else entity.pos.distance_to(target_tower.pos)
			if e_dist < t_dist * 0.82:
				target_pos = target_entity.pos
				target_is_entity = true
			else:
				target_pos = target_tower.pos
		else:
			if target_tower.is_empty(): continue
			target_pos = target_tower.pos
		var distance: float = entity.pos.distance_to(target_pos)
		var reach: float = maxf(36.0, float(entity.range))
		if distance <= reach + 44.0:
			if float(entity.cooldown) <= 0.0:
				if target_is_entity:
					target_entity.hp -= int(entity.damage)
				else:
					damage_tower(str(target_tower.id), int(entity.damage), int(entity.team))
				entity.cooldown = float(entity.attack_period)
		else:
			var speed: float = float(entity.speed)
			if float(entity.slow) > 0.0: speed *= 0.62
			if speed <= 0.0: continue
			var desired: Vector2 = _path_target(entity, target_pos)
			var direction: Vector2 = (desired - entity.pos).normalized()
			entity.pos += direction * speed * delta
			entity.pos.x = clampf(entity.pos.x, 75.0, 1005.0)
			entity.pos.y = clampf(entity.pos.y, 250.0, 2150.0)

func _path_target(entity: Dictionary, final_target: Vector2) -> Vector2:
	if bool(entity.air): return final_target
	var y: float = float(entity.pos.y)
	var target_y: float = final_target.y
	if (y > 1250.0 and target_y < 1150.0) or (y < 1150.0 and target_y > 1250.0):
		var bridge_x: float = 300.0 if float(entity.pos.x) < 540.0 else 780.0
		if absf(y - 1200.0) > 48.0:
			return Vector2(bridge_x, 1200.0)
	return final_target

func _nearest_enemy_entity(source: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := 99999.0
	for candidate in entities:
		if int(candidate.hp) <= 0 or int(candidate.team) == int(source.team): continue
		var d: float = source.pos.distance_to(candidate.pos)
		if d < best_distance and d <= 340.0:
			best_distance = d
			best = candidate
	return best

func _nearest_enemy_tower(source: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := 99999.0
	for tower in towers:
		if not bool(tower.alive) or int(tower.team) == int(source.team): continue
		var d: float = source.pos.distance_to(tower.pos)
		if d < best_distance:
			best_distance = d
			best = tower
	return best

func _update_towers(delta: float) -> void:
	for tower in towers:
		if not bool(tower.alive): continue
		tower.cooldown = maxf(0.0, float(tower.cooldown) - delta)
		if float(tower.cooldown) > 0.0: continue
		var best: Dictionary = {}
		var best_distance := 280.0
		for entity in entities:
			if int(entity.hp) <= 0 or int(entity.team) == int(tower.team): continue
			var d: float = tower.pos.distance_to(entity.pos)
			if d < best_distance:
				best_distance = d
				best = entity
		if not best.is_empty():
			best.hp -= 105 if bool(tower.core) else 88
			tower.cooldown = 0.95

func damage_tower(id: String, amount: int, attacker_team: int) -> void:
	if amount <= 0: return
	var tower: Dictionary = get_tower(id)
	if tower.is_empty() or not bool(tower.alive): return
	tower.hp = int(tower.hp) - amount
	if int(tower.hp) <= 0:
		tower.hp = 0
		tower.alive = false
		if bool(tower.core):
			finished = true
			winner = attacker_team

func _cleanup_dead() -> void:
	for i in range(entities.size() - 1, -1, -1):
		if int(entities[i].hp) <= 0:
			entities.remove_at(i)

func _finish_by_health() -> void:
	var player_hp := 0
	var enemy_hp := 0
	for tower in towers:
		if int(tower.team) == PLAYER: player_hp += maxi(0, int(tower.hp))
		else: enemy_hp += maxi(0, int(tower.hp))
	finished = true
	if player_hp > enemy_hp: winner = PLAYER
	elif enemy_hp > player_hp: winner = ENEMY
	else: winner = -1

func choose_bot_action(personality: String = "balanced", difficulty: int = 1) -> Dictionary:
	var affordable: Array = []
	for id in enemy_deck:
		var card: Dictionary = db.cards[id]
		if int(card.cost) <= int(floor(enemy_arcana.value)):
			affordable.append(id)
	if affordable.is_empty():
		return {}
	var card_id: String = str(affordable[rng.randi_range(0, affordable.size() - 1)])
	if personality == "siege" and "moss_colossus" in affordable: card_id = "moss_colossus"
	elif personality == "rush" and "gearling_trio" in affordable: card_id = "gearling_trio"
	elif personality == "control" and "prism_turret" in affordable: card_id = "prism_turret"
	var card: Dictionary = db.cards[card_id]
	var lane_x: float = 300.0 if rng.randf() < 0.5 else 780.0
	if difficulty >= 2:
		var left: Dictionary = get_tower("player_left")
		var right: Dictionary = get_tower("player_right")
		lane_x = 300.0 if int(left.hp) <= int(right.hp) else 780.0
	var pos := Vector2(lane_x + rng.randf_range(-55.0, 55.0), rng.randf_range(720.0, 1040.0))
	if str(card.family) == "spell":
		pos = Vector2(lane_x, rng.randf_range(1420.0, 1840.0))
	return {"card": card_id, "pos": pos}

func bot_step(personality: String = "balanced", difficulty: int = 1) -> bool:
	var action: Dictionary = choose_bot_action(personality, difficulty)
	if action.is_empty(): return false
	return deploy(str(action.card), action.pos, ENEMY)
