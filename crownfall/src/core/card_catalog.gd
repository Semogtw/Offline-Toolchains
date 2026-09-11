class_name CardCatalog
extends RefCounted

const STARTER := ["iron_warden", "moss_colossus", "astral_sentinel", "spore_bomber", "gearling_trio", "prism_turret", "starfall", "gale_ring"]

static func starter_deck() -> Array[String]:
    return STARTER.duplicate()

static func all_cards() -> Array:
    return [
        _troop("iron_warden", "Guardião de Ferro", 3, 760, 112, 88.0, 86.0, 1.20, 1, false, "any", Color("67d7ff"), "shield"),
        _troop("moss_colossus", "Colosso de Musgo", 6, 2450, 188, 48.0, 76.0, 1.65, 1, false, "structures", Color("75d86d"), "siege_tank"),
        _troop("ember_vixen", "Raposa Ígnea", 4, 610, 154, 112.0, 245.0, 1.05, 1, false, "any", Color("ff805d"), "dash"),
        _troop("astral_sentinel", "Sentinela Astral", 4, 690, 128, 76.0, 310.0, 1.25, 1, false, "any", Color("8ab4ff"), "pierce"),
        _troop("tempest_rider", "Cavaleiro Tempestade", 5, 980, 176, 122.0, 92.0, 1.35, 1, false, "any", Color("e7eaff"), "charge"),
        _troop("lumen_swarm", "Enxame de Lúmens", 2, 115, 58, 134.0, 80.0, 0.70, 5, true, "any", Color("fff29a"), "swarm"),
        _troop("crystal_hexer", "Bruxa de Cristal", 5, 720, 102, 68.0, 285.0, 1.30, 1, false, "any", Color("dd8cff"), "summoner"),
        _troop("spore_bomber", "Bombardeiro Cogumelo", 3, 470, 162, 70.0, 255.0, 1.70, 1, false, "ground", Color("ffc56e"), "splash"),
        _troop("dune_prowler", "Rastreador das Dunas", 3, 540, 136, 126.0, 84.0, 0.95, 1, false, "any", Color("edc57b"), "ambush"),
        _troop("brassback", "Couraçado de Latão", 5, 1660, 149, 58.0, 88.0, 1.55, 1, false, "structures", Color("d59c5c"), "armor"),
        _troop("rift_moths", "Mariposas da Fenda", 3, 180, 72, 118.0, 105.0, 0.80, 4, true, "any", Color("9a84ff"), "phase"),
        _troop("thornkeeper", "Guardião de Espinhos", 4, 910, 120, 63.0, 225.0, 1.25, 1, false, "any", Color("6fca79"), "root"),
        _troop("rune_duelist", "Duelista Rúnico", 4, 790, 164, 104.0, 82.0, 0.95, 1, false, "any", Color("6ee7df"), "combo"),
        _troop("moonhorn", "Chifre Lunar", 7, 2780, 224, 52.0, 90.0, 1.75, 1, false, "structures", Color("bfccff"), "impact"),
        _troop("gearling_trio", "Trio de Engrenitos", 3, 330, 96, 96.0, 220.0, 1.10, 3, false, "any", Color("f3b95f"), "trio"),
        _troop("aether_drake", "Draco de Éter", 6, 1280, 182, 72.0, 250.0, 1.40, 1, true, "any", Color("78e4ff"), "breath"),
        _structure("prism_turret", "Torre Prisma", 4, 1180, 126, 330.0, 1.15, 35.0, Color("8edcff"), "ramp"),
        _structure("rootwell", "Poço-Raiz", 4, 1520, 64, 215.0, 1.60, 38.0, Color("76d47f"), "heal"),
        _structure("arc_coil", "Bobina de Arco", 5, 1060, 194, 290.0, 1.45, 32.0, Color("d896ff"), "chain"),
        _structure("waystone", "Pedra-Caminho", 3, 1320, 82, 235.0, 1.30, 42.0, Color("78c9c0"), "pull"),
        _spell("starfall", "Chuva Astral", 5, 360, 155.0, Color("9dafff"), "blast"),
        _spell("gale_ring", "Anel de Vendaval", 3, 145, 185.0, Color("9cf5df"), "knockback"),
        _spell("verdant_bloom", "Florescer Verdejante", 4, -310, 170.0, Color("83e58c"), "heal"),
        _spell("static_seal", "Selo Estático", 2, 95, 145.0, Color("f3e97c"), "stun")
    ]

static func get_card(id: String) -> Dictionary:
    for card in all_cards():
        if card.id == id:
            return card
    return {}

static func _troop(id: String, title: String, cost: int, hp: int, damage: int, speed: float, attack_range: float, rate: float, count: int, flying: bool, target: String, accent: Color, special: String) -> Dictionary:
    return {"id": id, "name": title, "type": "troop", "cost": cost, "hp": hp, "damage": damage, "speed": speed, "range": attack_range, "rate": rate, "count": count, "flying": flying, "target": target, "accent": accent, "special": special}

static func _structure(id: String, title: String, cost: int, hp: int, damage: int, attack_range: float, rate: float, lifetime: float, accent: Color, special: String) -> Dictionary:
    return {"id": id, "name": title, "type": "structure", "cost": cost, "hp": hp, "damage": damage, "range": attack_range, "rate": rate, "lifetime": lifetime, "accent": accent, "special": special}

static func _spell(id: String, title: String, cost: int, power: int, radius: float, accent: Color, special: String) -> Dictionary:
    return {"id": id, "name": title, "type": "spell", "cost": cost, "power": power, "radius": radius, "accent": accent, "special": special}
