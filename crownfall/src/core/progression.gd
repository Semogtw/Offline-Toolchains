class_name Progression
extends RefCounted

static func leagues() -> Array:
    return [
        {"id": "verdant", "name": "Liga Verdejante", "min": 0, "accent": Color("69d77a")},
        {"id": "brass", "name": "Liga de Latão", "min": 400, "accent": Color("d7a861")},
        {"id": "prism", "name": "Liga Prismática", "min": 900, "accent": Color("75d8ff")},
        {"id": "rift", "name": "Liga da Fenda", "min": 1500, "accent": Color("a884ff")},
        {"id": "astral", "name": "Liga Astral", "min": 2300, "accent": Color("f0ecae")}
    ]

static func default_profile() -> Dictionary:
    var collection := {}
    for card in CardCatalog.all_cards():
        collection[card.id] = {"level": 1, "copies": 0, "unlocked": CardCatalog.STARTER.has(card.id)}
    return {
        "schema": 1,
        "player_name": "Invoker",
        "level": 1,
        "xp": 0,
        "trophies": 0,
        "coins": 800,
        "crystals": 40,
        "wins": 0,
        "losses": 0,
        "deck": CardCatalog.starter_deck(),
        "collection": collection,
        "vaults": [],
        "missions": [],
        "tutorial_done": false,
        "settings": {"music": 0.75, "sfx": 0.85, "haptics": true, "reduced_motion": false}
    }

static func league_for_trophies(trophies: int) -> Dictionary:
    var result: Dictionary = leagues()[0]
    for league in leagues():
        if trophies >= int(league.min):
            result = league
    return result

static func apply_battle_result(profile: Dictionary, victory: bool, crowns: int) -> Dictionary:
    var updated := profile.duplicate(true)
    if victory:
        updated.trophies = int(updated.get("trophies", 0)) + 28 + max(0, crowns - 1) * 2
        updated.coins = int(updated.get("coins", 0)) + 65 + crowns * 10
        updated.wins = int(updated.get("wins", 0)) + 1
        updated.xp = int(updated.get("xp", 0)) + 35
    else:
        updated.trophies = max(0, int(updated.get("trophies", 0)) - 18)
        updated.coins = int(updated.get("coins", 0)) + 20
        updated.losses = int(updated.get("losses", 0)) + 1
        updated.xp = int(updated.get("xp", 0)) + 12
    return updated
