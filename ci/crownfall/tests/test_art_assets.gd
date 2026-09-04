extends RefCounted

const CARD_IDS := [
	"iron_warden", "moss_colossus", "astral_sentinel", "spore_bomber", "gearling_trio", "dune_lancer",
	"ember_fox", "tempest_oracle", "crystal_witch", "lumen_swarm", "storm_knight", "root_mender",
	"void_manta", "sunforged_ram", "rune_duelist", "frost_owl", "prism_turret", "thorn_bastion",
	"arc_coil", "sunwell", "starfall", "gale_ring", "bloom_pulse", "time_shard"
]

func _result() -> Dictionary:
	return {"assertions": 0, "errors": []}

func _expect(r: Dictionary, condition: bool, message: String) -> void:
	r.assertions += 1
	if not condition:
		r.errors.append(message)

func test_generated_raster_materials_and_atlases_exist() -> Dictionary:
	var r := _result()
	for path in [
		"res://assets/generated/arena_ground.png",
		"res://assets/generated/bridge_wood.png",
		"res://assets/generated/tower_stone.png",
		"res://assets/generated/metal_trim.png",
		"res://assets/generated/wood.png",
		"res://assets/generated/water.png",
		"res://assets/generated/parchment.png",
		"res://assets/generated/card_art_atlas.png",
		"res://assets/generated/unit_sprite_atlas.png"
	]:
		_expect(r, FileAccess.file_exists(path), "%s must be generated as a real raster asset" % path)
		if FileAccess.file_exists(path):
			var tex = load(path)
			_expect(r, tex is Texture2D, "%s must import as Texture2D" % path)
			if tex is Texture2D:
				_expect(r, tex.get_width() >= 256 and tex.get_height() >= 256, "%s must have useful raster resolution" % path)
	return r

func test_texture_bank_maps_all_cards_to_raster_regions() -> Dictionary:
	var r := _result()
	var path := "res://src/presentation/texture_bank.gd"
	_expect(r, FileAccess.file_exists(path), "texture_bank.gd must exist")
	if not FileAccess.file_exists(path):
		return r
	var script = load(path)
	var bank = script.new()
	var loaded: int = bank.load_all()
	_expect(r, loaded >= 9, "texture bank must load the complete raster art pack")
	for card_id in CARD_IDS:
		var card_rect: Rect2 = bank.card_region(card_id)
		var idle_rect: Rect2 = bank.unit_region(card_id, "idle", 0.0)
		var attack_rect: Rect2 = bank.unit_region(card_id, "attack", 0.0)
		_expect(r, card_rect.size.x > 0 and card_rect.size.y > 0, "%s needs card artwork region" % card_id)
		_expect(r, idle_rect.size.x > 0 and idle_rect.size.y > 0, "%s needs idle raster sprite" % card_id)
		_expect(r, attack_rect != idle_rect, "%s needs a distinct attack frame" % card_id)
	bank.free() if bank is Node else null
	return r

func test_main_scene_mounts_textured_art_overlay() -> Dictionary:
	var r := _result()
	var scene = load("res://src/app/main.tscn")
	_expect(r, scene != null, "main scene must load")
	if scene == null:
		return r
	var instance = scene.instantiate()
	var overlay = instance.get_node_or_null("ArtOverlay")
	_expect(r, overlay != null, "main scene must mount ArtOverlay")
	if overlay != null:
		_expect(r, overlay.has_method("art_snapshot"), "ArtOverlay must expose art_snapshot diagnostics")
	instance.free()
	return r

func test_poly_haven_credit_is_embedded() -> Dictionary:
	var r := _result()
	var path := "res://data/art_credits.txt"
	_expect(r, FileAccess.file_exists(path), "art credits must be embedded")
	if FileAccess.file_exists(path):
		var text := FileAccess.get_file_as_string(path)
		_expect(r, text.contains("Poly Haven"), "credits must name Poly Haven")
		_expect(r, text.contains("CC0"), "credits must state CC0 material license")
	return r
