#!/usr/bin/env python3
"""Build Crownfall Arena's deterministic mobile raster art pack.

Surface photographs are CC0 materials fetched from Poly Haven's public API.
If the API is unavailable, deterministic painterly fallbacks are generated so
CI/export remains reproducible and the final APK is fully offline.
"""
from __future__ import annotations

import io
import json
import math
import random
import sys
import urllib.request
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter, ImageOps

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "generated"
SIZE = 512
UA = "CrownfallArenaBuild/0.3 (+https://github.com/Semogtw/Offline-Toolchains)"

CARD_IDS = [
    "iron_warden", "moss_colossus", "astral_sentinel", "spore_bomber", "gearling_trio", "dune_lancer",
    "ember_fox", "tempest_oracle", "crystal_witch", "lumen_swarm", "storm_knight", "root_mender",
    "void_manta", "sunforged_ram", "rune_duelist", "frost_owl", "prism_turret", "thorn_bastion",
    "arc_coil", "sunwell", "starfall", "gale_ring", "bloom_pulse", "time_shard",
]

FAMILIES = {cid: ("structure" if cid in {"prism_turret", "thorn_bastion", "arc_coil", "sunwell"}
                  else "spell" if cid in {"starfall", "gale_ring", "bloom_pulse", "time_shard"}
                  else "troop") for cid in CARD_IDS}

ACCENTS = {
    "iron_warden": "6ec6ff", "moss_colossus": "78b85c", "astral_sentinel": "a59bff", "spore_bomber": "d99a69",
    "gearling_trio": "f0b85b", "dune_lancer": "e7c17a", "ember_fox": "ff754d", "tempest_oracle": "65d9e8",
    "crystal_witch": "c477ff", "lumen_swarm": "fff08a", "storm_knight": "7ca8ff", "root_mender": "6fc77b",
    "void_manta": "8d6bd8", "sunforged_ram": "ffc85a", "rune_duelist": "e66c9c", "frost_owl": "b8efff",
    "prism_turret": "a779ff", "thorn_bastion": "6a9b58", "arc_coil": "6bd6ff", "sunwell": "ffcf5c",
    "starfall": "9f86ff", "gale_ring": "7ee1cf", "bloom_pulse": "80e68e", "time_shard": "79aaff",
}

MATERIAL_SOURCES = {
    "arena_ground.png": ("grassy_cobblestone", "48734d"),
    "bridge_wood.png": ("wood_stone_pathway", "8f6840"),
    "tower_stone.png": ("stone_wall", "65707c"),
    "metal_trim.png": ("metal_plate", "5c7086"),
    "wood.png": ("wood_floor", "9a6c43"),
}


def hex_rgb(value: str) -> tuple[int, int, int]:
    value = value.lstrip("#")
    return tuple(int(value[i:i+2], 16) for i in (0, 2, 4))


def request_json(url: str) -> dict:
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=20) as response:
        return json.load(response)


def collect_urls(node, path=()):
    found = []
    if isinstance(node, dict):
        for key, value in node.items():
            found.extend(collect_urls(value, path + (str(key).lower(),)))
    elif isinstance(node, list):
        for idx, value in enumerate(node):
            found.extend(collect_urls(value, path + (str(idx),)))
    elif isinstance(node, str) and node.startswith("http"):
        found.append((path, node))
    return found


def polyhaven_diffuse_url(asset_id: str) -> str:
    data = request_json(f"https://api.polyhaven.com/files/{asset_id}")
    candidates = []
    for path, url in collect_urls(data):
        joined = "/".join(path) + " " + url.lower()
        score = 0
        if "diff" in joined or "albedo" in joined or "basecolor" in joined:
            score += 80
        if "1k" in joined:
            score += 40
        if url.lower().endswith((".jpg", ".jpeg")):
            score += 25
        elif url.lower().endswith(".png"):
            score += 12
        if "thumb" in joined or "preview" in joined:
            score -= 60
        if score > 80:
            candidates.append((score, url))
    if not candidates:
        raise RuntimeError(f"No diffuse candidate for Poly Haven asset {asset_id}")
    candidates.sort(reverse=True)
    return candidates[0][1]


def download_image(url: str) -> Image.Image:
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=30) as response:
        payload = response.read()
    return Image.open(io.BytesIO(payload)).convert("RGB")


def fallback_texture(seed: int, tint: tuple[int, int, int], kind: str) -> Image.Image:
    rng = random.Random(seed)
    noise = Image.effect_noise((SIZE, SIZE), 46).convert("L")
    dark = tuple(max(0, int(c * 0.42)) for c in tint)
    light = tuple(min(255, int(c * 1.28 + 22)) for c in tint)
    img = ImageOps.colorize(noise, dark, light)
    draw = ImageDraw.Draw(img, "RGBA")
    if kind == "wood":
        for y in range(0, SIZE, 54):
            draw.line((0, y, SIZE, y + rng.randint(-4, 4)), fill=(45, 25, 12, 130), width=5)
        for _ in range(35):
            x, y = rng.randrange(SIZE), rng.randrange(SIZE)
            draw.ellipse((x-18, y-5, x+18, y+5), outline=(60, 33, 19, 90), width=2)
    elif kind == "stone":
        for y in range(-30, SIZE, 68):
            offset = 0 if (y // 68) % 2 == 0 else 52
            for x in range(-80 + offset, SIZE, 104):
                draw.rounded_rectangle((x, y, x+96, y+59), radius=9, outline=(20, 25, 29, 125), width=5)
    elif kind == "metal":
        for y in range(0, SIZE, 64):
            for x in range(0, SIZE, 64):
                draw.ellipse((x+7, y+7, x+15, y+15), fill=(225, 235, 240, 90))
        for _ in range(28):
            x = rng.randrange(SIZE)
            draw.line((x, 0, x+rng.randint(-20, 20), SIZE), fill=(210,220,230,35), width=2)
    else:
        for _ in range(160):
            x, y = rng.randrange(SIZE), rng.randrange(SIZE)
            r = rng.randint(2, 12)
            draw.ellipse((x-r, y-r, x+r, y+r), fill=(75, 110+rng.randint(0,30), 66, rng.randint(25,70)))
    return img.filter(ImageFilter.GaussianBlur(0.35))


def stylize_material(img: Image.Image, tint: tuple[int, int, int]) -> Image.Image:
    img = ImageOps.fit(img.convert("RGB"), (SIZE, SIZE), method=Image.Resampling.LANCZOS)
    img = ImageOps.autocontrast(img, cutoff=1)
    img = ImageEnhance.Color(img).enhance(0.82)
    img = ImageEnhance.Contrast(img).enhance(1.12)
    overlay = Image.new("RGB", img.size, tint)
    img = Image.blend(img, overlay, 0.14)
    img = img.filter(ImageFilter.UnsharpMask(radius=1.2, percent=115, threshold=3))
    return img


def build_materials() -> dict[str, Image.Image]:
    OUT.mkdir(parents=True, exist_ok=True)
    built = {}
    for index, (name, (asset_id, tint_hex)) in enumerate(MATERIAL_SOURCES.items()):
        tint = hex_rgb(tint_hex)
        kind = "wood" if "wood" in name or "bridge" in name else "stone" if "stone" in name else "metal" if "metal" in name else "ground"
        try:
            url = polyhaven_diffuse_url(asset_id)
            source = download_image(url)
            print(f"[art] Poly Haven {asset_id}: {url}")
        except Exception as exc:
            print(f"[art] WARN {asset_id}: {exc}; using deterministic fallback", file=sys.stderr)
            source = fallback_texture(3000 + index, tint, kind)
        result = stylize_material(source, tint)
        result.save(OUT / name, optimize=True)
        built[name] = result
    return built


def make_water() -> Image.Image:
    img = Image.new("RGB", (SIZE, SIZE), (24, 91, 125))
    px = img.load()
    rng = random.Random(9107)
    for y in range(SIZE):
        for x in range(SIZE):
            wave = math.sin(x * 0.055 + y * 0.018) * 9 + math.sin(x * 0.017 - y * 0.043) * 6
            jitter = rng.randrange(-7, 8)
            px[x, y] = (20 + int(wave * .25), 91 + int(wave) + jitter, 130 + int(wave * 1.3) + jitter)
    draw = ImageDraw.Draw(img, "RGBA")
    for y in range(18, SIZE, 45):
        points = [(x, y + math.sin(x * 0.04 + y) * 5) for x in range(0, SIZE + 1, 8)]
        draw.line(points, fill=(165, 231, 241, 72), width=3)
    return img.filter(ImageFilter.GaussianBlur(0.45))


def make_parchment() -> Image.Image:
    base = fallback_texture(4412, (137, 106, 74), "ground")
    base = ImageEnhance.Color(base).enhance(0.55)
    overlay = Image.new("RGB", base.size, (98, 72, 52))
    return Image.blend(base, overlay, 0.24).filter(ImageFilter.GaussianBlur(0.2))


def tint_texture(img: Image.Image, color: tuple[int, int, int], strength: float = 0.32) -> Image.Image:
    tinted = Image.new("RGB", img.size, color)
    return Image.blend(img.convert("RGB"), tinted, strength)


def archetype(card_id: str) -> int:
    return CARD_IDS.index(card_id) % 8


def material_fill(material: Image.Image, size=(128, 128), color=None) -> Image.Image:
    tile = ImageOps.fit(material, size, method=Image.Resampling.LANCZOS)
    if color:
        tile = tint_texture(tile, color, 0.26)
    return tile.convert("RGBA")


def paste_mask(dst: Image.Image, fill: Image.Image, mask: Image.Image, xy=(0, 0)) -> None:
    if fill.size != mask.size:
        fill = ImageOps.fit(fill, mask.size, method=Image.Resampling.LANCZOS)
    dst.alpha_composite(Image.composite(fill, Image.new("RGBA", mask.size, (0,0,0,0)), mask), xy)


def draw_unit_cell(card_id: str, state: int, materials: dict[str, Image.Image]) -> Image.Image:
    cell = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
    draw = ImageDraw.Draw(cell, "RGBA")
    accent = hex_rgb(ACCENTS[card_id])
    family = FAMILIES[card_id]
    idx = CARD_IDS.index(card_id)
    a = archetype(card_id)
    bounce = [0, 3, -2, 1][state]
    attack_shift = 8 if state == 2 else 0
    hit_alpha = 95 if state == 3 else 0
    draw.ellipse((24, 100, 104, 119), fill=(5, 8, 12, 92))

    if family == "spell":
        cx, cy = 64, 60 + bounce
        for radius, alpha in [(42, 28), (31, 46), (20, 74)]:
            draw.ellipse((cx-radius, cy-radius, cx+radius, cy+radius), outline=accent + (alpha,), width=4)
        points = []
        tips = 8 if card_id != "starfall" else 5
        for i in range(tips * 2):
            ang = -math.pi/2 + i * math.pi / tips + state * 0.08
            r = 29 if i % 2 == 0 else 12
            points.append((cx + math.cos(ang)*r, cy + math.sin(ang)*r))
        draw.polygon(points, fill=accent + (215,), outline=(245, 248, 255, 220))
        draw.ellipse((54,50+bounce,74,70+bounce), fill=(255,255,255,170))
        return cell

    if family == "structure":
        mask = Image.new("L", (128,128), 0)
        md = ImageDraw.Draw(mask)
        md.rounded_rectangle((28,48+bounce,100,104+bounce), radius=8, fill=230)
        md.polygon([(36,50+bounce),(64,25+bounce),(92,50+bounce)], fill=255)
        fill_src = materials["tower_stone.png"] if card_id in {"thorn_bastion","sunwell"} else materials["metal_trim.png"]
        paste_mask(cell, material_fill(fill_src, color=accent), mask)
        draw.rectangle((31,86+bounce,97,104+bounce), outline=(18,25,31,220), width=4)
        if card_id == "prism_turret":
            draw.polygon([(64,22-attack_shift//2),(83,48),(64,63),(45,48)], fill=accent+(240,), outline=(245,245,255,230))
        elif card_id == "arc_coil":
            for r in (13,22,31): draw.arc((64-r,42-r+bounce,64+r,42+r+bounce), 195, 345, fill=accent+(240,), width=5)
        elif card_id == "sunwell":
            draw.ellipse((45,29+bounce,83,67+bounce), fill=(255,211,88,210), outline=(255,244,190,245), width=4)
        else:
            for x in (38,58,78): draw.polygon([(x,47+bounce),(x+10,25+bounce),(x+20,47+bounce)], fill=accent+(220,))
        if hit_alpha: draw.rectangle((24,22,104,108), fill=(255,255,255,hit_alpha))
        return cell

    body_mask = Image.new("L", (128, 128), 0)
    md = ImageDraw.Draw(body_mask)
    y = bounce
    if a == 0:
        md.rounded_rectangle((43,44+y,85,100+y), radius=12, fill=255); md.ellipse((46,22+y,82,58+y), fill=255)
    elif a == 1:
        md.ellipse((31,42+y,97,104+y), fill=255); md.ellipse((42,20+y,86,62+y), fill=255)
    elif a == 2:
        md.polygon([(64,18+y),(91,50+y),(84,102+y),(44,102+y),(37,50+y)], fill=255)
    elif a == 3:
        md.ellipse((37,34+y,91,88+y), fill=255); md.polygon([(49,78+y),(38,105+y),(64,93+y),(90,105+y),(79,78+y)], fill=255)
    elif a == 4:
        md.rounded_rectangle((48,38+y,80,96+y), radius=14, fill=255); md.ellipse((43,18+y,85,56+y), fill=255)
    elif a == 5:
        md.polygon([(28,62+y),(52,30+y),(96,33+y),(103,68+y),(75,94+y),(35,90+y)], fill=255)
    elif a == 6:
        md.ellipse((37,31+y,91,92+y), fill=255); md.polygon([(42,70+y),(23,103+y),(59,91+y),(64,108+y),(69,91+y),(105,103+y),(86,70+y)], fill=255)
    else:
        md.rounded_rectangle((38,36+y,90,101+y), radius=18, fill=255); md.ellipse((45,16+y,83,54+y), fill=255)

    base_material = materials["metal_trim.png"] if card_id in {"iron_warden","storm_knight","rune_duelist","gearling_trio","dune_lancer"} else materials["arena_ground.png"] if card_id in {"moss_colossus","root_mender","ember_fox"} else materials["tower_stone.png"]
    paste_mask(cell, material_fill(base_material, color=accent), body_mask)
    draw = ImageDraw.Draw(cell, "RGBA")
    # face/highlight details
    draw.ellipse((54,34+y,61,41+y), fill=(235,249,255,230)); draw.ellipse((68,34+y,75,41+y), fill=(235,249,255,230))
    # weapon / wings / distinctive profile
    facing = -1 if idx % 2 else 1
    if a in {0,7}:
        draw.line((80,62+y,109+attack_shift*facing,35+y-attack_shift), fill=(220,232,238,245), width=6)
        draw.ellipse((21,60+y,47,86+y), fill=accent+(190,), outline=(245,250,255,190), width=3)
    elif a == 1:
        draw.line((36,71+y,16-attack_shift,47+y), fill=(92,69,45,240), width=9); draw.line((92,71+y,112+attack_shift,47+y), fill=(92,69,45,240), width=9)
    elif a in {2,6}:
        wing = 12 + (8 if state == 1 else 0)
        draw.polygon([(45,53+y),(11,42+y-wing),(31,82+y),(49,74+y)], fill=accent+(155,))
        draw.polygon([(83,53+y),(117,42+y-wing),(97,82+y),(79,74+y)], fill=accent+(155,))
    elif a == 3:
        draw.ellipse((82+attack_shift//2,52+y,112+attack_shift,82+y), fill=accent+(220,), outline=(255,238,188,230), width=3)
    elif a == 4:
        draw.line((47,64+y,21-attack_shift,30+y), fill=accent+(245,), width=5); draw.line((81,64+y,107+attack_shift,30+y), fill=accent+(245,), width=5)
    elif a == 5:
        draw.line((95,62+y,119+attack_shift,56+y), fill=(232,206,154,245), width=7)
    if state == 1:
        draw.line((43,101+y,34,114), fill=(210,224,230,180), width=5); draw.line((83,101+y,94,113), fill=(210,224,230,180), width=5)
    if state == 2:
        draw.arc((21,18,108,107), 300, 65, fill=accent+(180,), width=4)
    if hit_alpha:
        draw.ellipse((26,16,103,108), fill=(255,255,255,hit_alpha))
    return cell


def build_unit_atlas(materials: dict[str, Image.Image]) -> Image.Image:
    atlas = Image.new("RGBA", (1024, 1536), (0,0,0,0))
    for card_index, card_id in enumerate(CARD_IDS):
        for state in range(4):
            frame_index = card_index * 4 + state
            col, row = frame_index % 8, frame_index // 8
            atlas.alpha_composite(draw_unit_cell(card_id, state, materials), (col*128, row*128))
    atlas.save(OUT / "unit_sprite_atlas.png", optimize=True)
    return atlas


def build_card_atlas(unit_atlas: Image.Image, materials: dict[str, Image.Image]) -> Image.Image:
    atlas = Image.new("RGB", (1536, 1024), (18, 25, 35))
    for index, card_id in enumerate(CARD_IDS):
        cell = Image.new("RGB", (256,256), (17,24,34))
        accent = hex_rgb(ACCENTS[card_id])
        bg_source = materials["tower_stone.png"] if FAMILIES[card_id] == "structure" else materials["parchment.png"] if "parchment.png" in materials else materials["arena_ground.png"]
        bg = ImageOps.fit(bg_source, (256,256), method=Image.Resampling.LANCZOS)
        bg = tint_texture(bg, accent, 0.22)
        cell.paste(bg)
        shade = Image.new("RGBA", (256,256), (0,0,0,0))
        sd = ImageDraw.Draw(shade, "RGBA")
        sd.rectangle((0,0,255,255), outline=accent+(210,), width=9)
        sd.ellipse((34,25,222,213), fill=accent+(26,), outline=(245,247,250,45), width=3)
        for r in (84,66): sd.arc((128-r,115-r,128+r,115+r), 205, 335, fill=accent+(80,), width=3)
        cell = Image.alpha_composite(cell.convert("RGBA"), shade)
        frame_index = index * 4
        sx, sy = (frame_index % 8)*128, (frame_index//8)*128
        sprite = unit_atlas.crop((sx,sy,sx+128,sy+128)).resize((190,190), Image.Resampling.LANCZOS)
        shadow = Image.new("RGBA", (190,190), (0,0,0,0)); sh = ImageDraw.Draw(shadow); sh.ellipse((25,150,165,178), fill=(0,0,0,100))
        cell.alpha_composite(shadow, (33,36)); cell.alpha_composite(sprite, (33,25))
        cd = ImageDraw.Draw(cell, "RGBA")
        cd.rectangle((0,208,256,256), fill=(8,13,20,180))
        cd.rectangle((0,208,256,214), fill=accent+(235,))
        # family rune
        if FAMILIES[card_id] == "spell":
            cd.ellipse((105,216,151,254), outline=accent+(245,), width=4)
        elif FAMILIES[card_id] == "structure":
            cd.polygon([(106,249),(150,249),(145,224),(111,224)], fill=accent+(210,))
        else:
            cd.polygon([(128,217),(145,248),(128,240),(111,248)], fill=accent+(220,))
        col, row = index % 6, index // 6
        atlas.paste(cell.convert("RGB"), (col*256,row*256))
    atlas.save(OUT / "card_art_atlas.png", optimize=True)
    return atlas


def build_hero_banner(card_atlas: Image.Image) -> None:
    banner = Image.new("RGB", (1024,512), (12,21,31))
    draw = ImageDraw.Draw(banner, "RGBA")
    ground = ImageOps.fit(Image.open(OUT/"arena_ground.png"), banner.size, method=Image.Resampling.LANCZOS)
    banner = Image.blend(banner, ground.convert("RGB"), 0.36)
    for i, idx in enumerate([0,1,2,6,10,12]):
        sx, sy = (idx % 6)*256, (idx // 6)*256
        art = card_atlas.crop((sx,sy,sx+256,sy+256)).resize((220,220), Image.Resampling.LANCZOS)
        x = 20 + i*165
        y = 125 + abs(i-2.5)*18
        banner.paste(art, (x,y))
    draw = ImageDraw.Draw(banner, "RGBA")
    for r, alpha in [(210,25),(150,34),(95,46)]:
        draw.ellipse((512-r,256-r,512+r,256+r), outline=(103,215,232,alpha), width=5)
    banner.save(OUT/"hero_banner.png", optimize=True)


def main() -> int:
    materials = build_materials()
    water = make_water(); water.save(OUT / "water.png", optimize=True); materials["water.png"] = water
    parchment = make_parchment(); parchment.save(OUT / "parchment.png", optimize=True); materials["parchment.png"] = parchment
    unit_atlas = build_unit_atlas(materials)
    card_atlas = build_card_atlas(unit_atlas, materials)
    build_hero_banner(card_atlas)
    manifest = {
        "version": "0.3.0",
        "materials": sorted(MATERIAL_SOURCES.keys()) + ["water.png", "parchment.png"],
        "atlases": ["card_art_atlas.png", "unit_sprite_atlas.png", "hero_banner.png"],
        "cards": CARD_IDS,
        "surface_source": "Poly Haven CC0 with deterministic offline fallback",
    }
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(f"[art] generated {len(list(OUT.iterdir()))} files in {OUT}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
