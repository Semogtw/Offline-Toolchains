extends RefCounted

const CARD_IDS := [
	"iron_warden", "moss_colossus", "astral_sentinel", "spore_bomber", "gearling_trio", "dune_lancer",
	"ember_fox", "tempest_oracle", "crystal_witch", "lumen_swarm", "storm_knight", "root_mender",
	"void_manta", "sunforged_ram", "rune_duelist", "frost_owl", "prism_turret", "thorn_bastion",
	"arc_coil", "sunwell", "starfall", "gale_ring", "bloom_pulse", "time_shard"
]

const MATERIAL_PATHS := {
	"arena_ground": "res://assets/generated/arena_ground.png",
	"bridge_wood": "res://assets/generated/bridge_wood.png",
	"tower_stone": "res://assets/generated/tower_stone.png",
	"metal_trim": "res://assets/generated/metal_trim.png",
	"wood": "res://assets/generated/wood.png",
	"water": "res://assets/generated/water.png",
	"parchment": "res://assets/generated/parchment.png",
	"card_art": "res://assets/generated/card_art_atlas.png",
	"unit_sprites": "res://assets/generated/unit_sprite_atlas.png",
	"hero_banner": "res://assets/generated/hero_banner.png"
}

var textures: Dictionary = {}

func load_all() -> int:
	textures.clear()
	for key in MATERIAL_PATHS.keys():
		var path: String = str(MATERIAL_PATHS[key])
		if ResourceLoader.exists(path):
			var resource = load(path)
			if resource is Texture2D:
				textures[key] = resource
	return textures.size()

func material(name: String) -> Texture2D:
	if textures.is_empty():
		load_all()
	return textures.get(name, null)

func has_complete_pack() -> bool:
	if textures.is_empty():
		load_all()
	return textures.has("arena_ground") and textures.has("bridge_wood") and textures.has("tower_stone") and textures.has("metal_trim") and textures.has("card_art") and textures.has("unit_sprites") and textures.has("hero_banner")

func card_index(card_id: String) -> int:
	return CARD_IDS.find(card_id)

func card_region(card_id: String) -> Rect2:
	var index: int = card_index(card_id)
	if index < 0:
		return Rect2()
	var col: int = index % 6
	var row: int = index / 6
	return Rect2(float(col * 256), float(row * 256), 256.0, 256.0)

func unit_region(card_id: String, state: String, anim_time: float = 0.0) -> Rect2:
	var index: int = card_index(card_id)
	if index < 0:
		return Rect2()
	var state_index: int = 0
	match state:
		"move": state_index = 1
		"attack": state_index = 2
		"hit", "damage": state_index = 3
		_: state_index = 0
	# While moving, alternate between the move and idle drawings to avoid a frozen paper-doll look.
	if state == "move" and int(floor(anim_time * 7.0)) % 2 == 0:
		state_index = 0
	var frame_index: int = index * 4 + state_index
	var col: int = frame_index % 8
	var row: int = frame_index / 8
	return Rect2(float(col * 128), float(row * 128), 128.0, 128.0)

func snapshot() -> Dictionary:
	return {
		"loaded": textures.size(),
		"complete": has_complete_pack(),
		"cards": CARD_IDS.size(),
		"materials": MATERIAL_PATHS.keys()
	}
