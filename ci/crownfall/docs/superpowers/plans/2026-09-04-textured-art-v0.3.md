# Crownfall Arena Textured Art v0.3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the flat/procedural-looking presentation with raster texture assets, original illustrated card/unit sprites, richer battle/lobby compositing, and ship Android v0.3.0.

**Architecture:** Keep deterministic gameplay untouched. Add a deterministic Python art pipeline that downloads a small set of CC0 Poly Haven diffuse materials at build time, stylizes/downsamples them for mobile, generates original Crownfall raster atlases, and writes `res://assets/generated/`. A new `TextureBank` owns texture lookup/atlas regions and a new `ArtOverlay` composites raster art above the existing procedural presentation but below interactive controls.

**Tech Stack:** Godot 4.7.2, GDScript, Python 3 + Pillow, Poly Haven CC0 materials API, GitHub Actions, Android arm64-v8a.

**Spec:** Approved in conversation: v0.3 art pass with real bitmap textures, original raster unit/card art, improved arena/towers/VFX/HUD, no Clash Royale assets.

## Global Constraints

- Do not change battle rules or progression semantics.
- Do not use Supercell/Clash Royale copyrighted assets.
- Android stays portrait, arm64-v8a, minimum SDK 24.
- Surface sources are CC0; include Poly Haven credit because the live API is used during builds.
- Generated output must remain usable offline after APK export.
- Reduced-motion/high-contrast settings remain functional.

---

### Task 1: Raster asset pipeline

**Files:**
- Create: `tools/generate_art_assets.py`
- Create: `src/presentation/texture_bank.gd`
- Create: `data/art_credits.txt`
- Create/Test: `tests/test_art_assets.gd`
- Modify: `.github/workflows/crownfall-arena-ci.yml`

**Interfaces:**
- `TextureBank.load_all() -> int`
- `TextureBank.material(name: String) -> Texture2D`
- `TextureBank.card_region(card_id: String) -> Rect2`
- `TextureBank.unit_region(card_id: String, state: String, anim_time: float) -> Rect2`

- [ ] Write RED tests that require five raster materials, card/unit atlases, 24 valid atlas regions, and credits.
- [ ] Run CI and confirm the tests fail before generation/integration.
- [ ] Implement the Python generator. It queries `https://api.polyhaven.com/files/<id>` with a Crownfall user-agent, chooses 1K diffuse JPGs for `grassy_cobblestone`, `wood_stone_pathway`, `stone_wall`, `metal_plate`, and `wood_floor`, downsamples/stylizes them to 512x512 PNGs, and falls back to deterministic painterly noise when network lookup fails.
- [ ] Generate `water.png`, `parchment.png`, a 1536x1024 24-card art atlas, and a 1024x1536 24-card x 4-state transparent unit atlas.
- [ ] Run generator before Godot tests and before Android export.
- [ ] Run tests to GREEN.

### Task 2: Textured battle/lobby compositor

**Files:**
- Create: `src/presentation/art_overlay.gd`
- Modify: `src/app/main.tscn`
- Modify: `tests/test_art_assets.gd`
- Modify: `tests/smoke_app.gd`

**Interfaces:**
- `ArtOverlay.art_snapshot() -> Dictionary`
- `ArtOverlay` reads host `current_screen`, `battle`, `card_cycle`, `db`, `profile` and sibling `BattlePresentation.presentation_snapshot()`.

- [ ] Add RED tests requiring an `ArtOverlay` node and snapshot with loaded raster assets.
- [ ] Composite tiled grass/stone/wood/water/metal surfaces over the arena at controlled alpha, textured tower faces, animated raster unit frames, and raster hand-card art.
- [ ] Composite raster card art/material panels on Home, Collection, Decks, Missions, Vaults, Exchange, and Profile while leaving dynamic buttons above the overlay.
- [ ] Preserve reduced-motion by disabling texture drift and frame bob when enabled.
- [ ] Run full tests and live-scene smoke.

### Task 3: Android v0.3 release

**Files:**
- Modify: `project.godot`
- Modify: `export_presets.cfg`
- Modify: `.github/workflows/crownfall-arena-ci.yml`
- Modify: `.github/workflows/publish-crownfall-apk.yml`

- [ ] Bump internal Android version to `versionCode=3`, `versionName=0.3.0`.
- [ ] Make APK validation assert package, version, signature, arm64-only ABI, and presence of generated PNG resources in the PCK.
- [ ] Run full CI: tests -> live smoke -> Android export -> validation.
- [ ] Publish `crownfall-v0.3.0` as a separate prerelease with APK + SHA-256.
