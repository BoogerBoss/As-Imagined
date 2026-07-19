#!/usr/bin/env python3
"""
[M23.11 Phase 5b] Pulls the hybrid hit-effect asset set: a curated generic
type/category-keyed particle library (Part A) plus bespoke, higher-
fidelity assets for 3 hand-picked moves — Flamethrower, Thunder, Surf
(Part B) — locked scope, see docs/m23_11_phase5_recon.md Section 0 item 5
and Section 4.4.

Usage (from project root):
    python3 scripts/gen_hit_effect_sprites.py

Asset staging only — no dispatch/UI wiring here, that's 5c's job (matches
Phase 1's own "no UI consumption this session" precedent).

Step 0 findings (re-derived directly, not assumed from the recon's own
high-level description):

- graphics/battle_anims/sprites/ holds 402 real PNG files (all "P"-mode
  indexed) + 46 separate .pal files, NOT "~450 files / ~150 distinct
  assets" as the original recon's rough png+pal+import-triple estimate
  suggested — that estimate didn't account for most sprites being fully
  self-contained (no external .pal needed at all; the 46 .pal files are
  the exception, not a 1:3 pattern) or for ~400 stray .import files (a
  leftover artifact from before reference/.gdignore existed, confirmed
  present via `find . -iname .gdignore`; harmless, not real source data,
  not counted here).
- Every sprite is either a single square frame or a vertically/
  horizontally stacked strip of square sub-frames (e.g. `fire.png` is
  32x256 = 8 stacked 32x32 frames; `dragon_pulse.png` is 32x16 = 2 frames
  stacked HORIZONTALLY, the one exception to the vertical-stacking norm
  found among this session's own curated picks). This script pulls each
  chosen sprite as a single flat multi-frame strip PNG (matching the
  source shape exactly) — slicing into individual frames is a 5c dispatch
  concern, not an asset-staging one.
- CONFIRMED (not assumed): none of the source PNGs carry a PNG tRNS
  (transparency) chunk, unlike the Pokémon-sprite/trainer-portrait pulls
  from earlier phases, whose own source files already had one. But
  palette index 0 IS consistently the intended "background/unused" color
  at every sampled sprite's own corners (its own RGB value varies sprite-
  to-sprite, ruling out coincidence), matching the universal GBA hardware
  rule that OBJ (sprite) layer palette index 0 is always transparent —
  the same rule this project's Pokémon/trainer sprites already rely on,
  just not pre-tagged in these particular source files. This script
  EXPLICITLY tags index 0 as transparent on every pulled sprite (both
  generic and bespoke) via PIL's palette-transparency mechanism, rather
  than doing a byte-for-byte flat copy — a deliberate, documented
  deviation from every prior gen_*_sprites.py's pure shutil.copyfile
  convention, needed because these particular source files lack the
  tagging their own hardware semantics require. (Battle BACKGROUNDS —
  Phase 5a's own tilesets, and Surf's water.png below — are the OPPOSITE
  case: GBA BG layers render index 0 as a real opaque color, confirmed
  already in Phase 5a, so no transparency tagging is applied to those.)

Part A — generic library curation (21 sprites, one per major type family
plus 3 non-type-specific effects; a judgment call, not a mechanical
extraction — each pick's own reasoning is inline below):

Part B — bespoke moves, traced directly from each move's own
gBattleAnimMove_* script in data/battle_anim_scripts.s, not assumed
similar to each other:

- Flamethrower (move id 53): `FlamethrowerCreateFlames` creates repeated
  `gFlamethrowerFlameSpriteTemplate` sprites, tileTag/paletteTag
  ANIM_TAG_SMALL_EMBER -> gBattleAnimSpriteGfx_SmallEmber /
  gBattleAnimSpritePal_SmallEmber (src/graphics.c) -> the single flat
  sprite `small_ember.png` (self-contained, own embedded palette). A
  simple, already-flat sprite pull — same shape as Part A.
- Thunder (move id 87): `createsprite gLightningSpriteTemplate` repeatedly
  after a `fadetobg BG_THUNDER`/screen-invert sequence (the full-screen
  flash/invert is a pure engine effect this project has no equivalent
  layer for, out of scope — only the lightning bolt sprite itself is
  pulled). tileTag ANIM_TAG_LIGHTNING -> gBattleAnimSpriteGfx_Lightning
  (`lightning.png`), but paletteTag resolves to gBattleAnimSpritePal_
  Lightning2 -> a DIFFERENT file's embedded palette, `lightning_2.png`
  (confirmed via direct src/graphics.c read, not assumed same-name) — a
  genuine cross-file palette reference, the same general "external
  palette source" shape Phase 5a's `stadium` needed, just resolved
  precisely here since the real cross-reference exists in source (unlike
  stadium's own missing-default case). Both files are pulled.
- Surf (move id 57): the real surprise of this session — `create_surf_wave`
  is NOT a sprite dispatch at all, it's `AnimTask_CreateSurfWave`, which
  loads a genuine BG tile+tilemap animation (graphics/battle_anims/
  backgrounds/water.png + water_opponent.bin/water_player.bin), the exact
  same asset SHAPE as Phase 5a's environment tilesets — confirmed via
  direct src/battle_anim_water.c and src/graphics.c reads. Reconstructed
  here using the same decode algorithm Phase 5a's gen_battle_backgrounds.py
  already validated (GBA BG screen-entry format, 64x32 canvas as two
  block-major 32x32 screen blocks) — see that script's own doc comment
  for the full format writeup, not re-derived here. Two real differences
  from Phase 5a's environment tilesets, confirmed rather than assumed
  identical: (1) water.png's own embedded palette has only 16 colors (one
  bank), and every screen-entry's bank field is uniformly 8 — an absolute
  hardware BG-palette-slot reference (this Surf animation is configured to
  load into VRAM palette bank 8), not a 0-2 local offset into a small
  source file the way Phase 5a's multi-bank tilesets used it; the existing
  `bank % num_banks` wrap (num_banks=1 here) correctly collapses this to
  always read the single available palette, needing no special-casing.
  (2) UNLIKE Phase 5a's static single-screen-crop convention, the FULL
  512x256 composited canvas is kept uncropped for both variants — this is
  a horizontally-SCROLLING wave animation (the source C code visibly
  slides BG1HOFS/BG1VOFS over multiple animation-task steps), not a
  static resting backdrop, so a real future scrolling implementation (5c
  or later) needs the extra canvas width/height a single 240x160 crop
  would throw away. Visual inspection of both renders (water_opponent,
  water_player) found clean, immediately-recognizable curling-wave
  compositions with no artifacts — a notably cleaner result than Phase
  5a's own environment-tileset reconstruction, plausibly because this
  asset's whole canvas is genuinely meant to be visible during the
  animation, unlike Phase 5a's UI-occluded lower region.

Idempotent: re-running overwrites every output file with a fresh copy/
reconstruction.
"""

import os
import struct

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REF = os.path.join(ROOT, "reference", "pokeemerald_expansion")
SPRITES_SRC = os.path.join(REF, "graphics", "battle_anims", "sprites")
BACKGROUNDS_SRC = os.path.join(REF, "graphics", "battle_anims", "backgrounds")

GENERIC_OUT_DIR = os.path.join(ROOT, "assets", "sprites", "battle_effects", "generic")
BESPOKE_OUT_DIR = os.path.join(ROOT, "assets", "sprites", "battle_effects", "bespoke")


# ── Part A: generic library curation ────────────────────────────────────
# 18 type-family picks (one per type this project's TypeChart defines,
# grouped sensibly rather than forced when a type has no clean single
# representative) + 3 non-type-specific effects = 21 total, within the
# requested 15-30 range. Each entry: (output name, source filename stem,
# one-line reasoning).

GENERIC_PICKS = [
    # Type-family representatives
    ("fire", "fire", "Fire — a clean multi-frame flame burst, the most immediately recognizable Fire-type asset in the roster"),
    ("water", "water_impact", "Water — a single-frame splash/impact read, distinct from Surf's own bespoke wave asset"),
    ("electric", "lightning", "Electric — a bolt strip; also the literal asset Thunder's own bespoke pull uses, confirming this pick's fidelity"),
    ("grass", "leaf", "Grass — a plain leaf strip, more generically Grass-flavored than the sharper-edged razor_leaf"),
    ("ice", "ice_crystals_2", "Ice — a crystal-formation frame pair, reads clearly as Ice without needing the full 0-4 frame family"),
    ("rock", "big_rock", "Rock — a single large boulder, unambiguous"),
    ("ground", "dirt_mound", "Ground — distinct from Rock's boulder, reads as displaced earth/dirt"),
    ("psychic", "psycho_cut", "Psychic — a blade-of-energy shape, a common Psychic-type visual shorthand"),
    ("ghost", "ghostly_spirit", "Ghost — a wispy spirit shape, unambiguous"),
    ("dark", "void_lines", "Dark — an abstract void/shadow-line motif, deliberately distinct from Ghost's spirit shape"),
    ("poison", "poison_bubble", "Poison — a toxic bubble strip"),
    ("dragon", "dragon_pulse", "Dragon — an energy-pulse shape; the one pick that's a horizontal (not vertical) 2-frame strip"),
    ("fighting", "punch_impact", "Fighting — a fist-impact burst"),
    ("flying", "air_slash", "Flying — a wind-blade strip"),
    ("bug", "needle", "Bug — a single sharp needle/stinger shape"),
    ("steel", "metal_bits", "Steel — scattered metal fragments; the one pick with a non-square/irregular frame layout, flagged not fixed"),
    ("fairy", "pink_heart_2", "Fairy — a heart-shaped sparkle strip"),
    ("normal", "circle_impact", "Normal — a plain geometric ring/impact, deliberately neutral/type-agnostic in shape"),
    # Non-type-specific effects
    ("physical_impact", "impact", "Generic physical-impact effect — a plain hit-flash usable for any contact move regardless of type"),
    ("status_puff", "smoke", "Generic status-effect cloud/puff — neutral smoke, usable for burn/poison/paralysis/sleep infliction alike"),
    ("stat_shimmer", "sparkle_1", "Generic stat-buff/debuff shimmer — a neutral sparkle strip, tintable by 5c's own dispatch for raise vs. lower"),
]


def _tag_transparent_and_save(im: Image.Image, out_path: str) -> None:
    """Palette index 0 -> transparent (see module docstring: the source
    files lack this tagging even though it's the universal GBA OBJ-layer
    convention this project's other sprite pulls already rely on)."""
    im = im.convert("P")
    im.info["transparency"] = 0
    im.save(out_path, transparency=0)


def pull_generic_library() -> int:
    os.makedirs(GENERIC_OUT_DIR, exist_ok=True)
    count = 0
    for out_name, src_stem, _reasoning in GENERIC_PICKS:
        src_path = os.path.join(SPRITES_SRC, src_stem + ".png")
        im = Image.open(src_path)
        out_path = os.path.join(GENERIC_OUT_DIR, out_name + ".png")
        _tag_transparent_and_save(im, out_path)
        count += 1
        print(f"  generic/{out_name}.png  <- {src_stem}.png  ({im.size[0]}x{im.size[1]})")
    return count


# ── Part B: bespoke moves ────────────────────────────────────────────────

def pull_flamethrower() -> int:
    out_dir = os.path.join(BESPOKE_OUT_DIR, "0053_flamethrower")
    os.makedirs(out_dir, exist_ok=True)
    im = Image.open(os.path.join(SPRITES_SRC, "small_ember.png"))
    _tag_transparent_and_save(im, os.path.join(out_dir, "small_ember.png"))
    print(f"  bespoke/0053_flamethrower/small_ember.png  ({im.size[0]}x{im.size[1]})")
    return 1


def pull_thunder() -> int:
    out_dir = os.path.join(BESPOKE_OUT_DIR, "0087_thunder")
    os.makedirs(out_dir, exist_ok=True)
    written = 0
    for stem in ["lightning", "lightning_2"]:
        im = Image.open(os.path.join(SPRITES_SRC, stem + ".png"))
        _tag_transparent_and_save(im, os.path.join(out_dir, stem + ".png"))
        print(f"  bespoke/0087_thunder/{stem}.png  ({im.size[0]}x{im.size[1]})")
        written += 1
    return written


def _load_jasc_or_embedded_palette(png_path: str):
    im = Image.open(png_path).convert("P")
    pal = im.getpalette()
    return [tuple(pal[i:i + 3]) for i in range(0, len(pal), 3)]


def _render_surf_wave(map_path: str) -> Image.Image:
    """Reuses the exact GBA BG screen-entry decode Phase 5a's
    gen_battle_backgrounds.py established (block-major 32x32 screen
    blocks, standard bit layout) -- see this module's own doc comment for
    why Surf needed this at all and how it differs from Phase 5a's
    environment tilesets (single 16-color bank, always-8 bank field,
    kept uncropped rather than cropped to one screen)."""
    tiles_path = os.path.join(BACKGROUNDS_SRC, "water.png")
    palette = _load_jasc_or_embedded_palette(tiles_path)
    num_banks = max(1, len(palette) // 16)

    atlas = Image.open(tiles_path).convert("P")
    atlas_px = atlas.load()
    tiles_per_row = atlas.width // 8

    map_w, map_h = 64, 32
    with open(map_path, "rb") as f:
        entries = struct.unpack(f"<{map_w * map_h}H", f.read())

    canvas = Image.new("RGB", (map_w * 8, map_h * 8))
    canvas_px = canvas.load()

    for row in range(map_h):
        for col in range(map_w):
            block = col // 32
            local_col = col % 32
            entry = entries[block * 1024 + row * 32 + local_col]

            tile_idx = entry & 0x3FF
            hflip = (entry >> 10) & 1
            vflip = (entry >> 11) & 1
            bank = (entry >> 12) & 0xF
            bank = bank % num_banks

            tx = (tile_idx % tiles_per_row) * 8
            ty = (tile_idx // tiles_per_row) * 8
            for dy in range(8):
                for dx in range(8):
                    sx = 7 - dx if hflip else dx
                    sy = 7 - dy if vflip else dy
                    pixel = atlas_px[tx + sx, ty + sy]
                    final_idx = pixel + bank * 16
                    color = palette[final_idx] if final_idx < len(palette) else (0, 0, 0)
                    canvas_px[col * 8 + dx, row * 8 + dy] = color

    return canvas


def pull_surf() -> int:
    out_dir = os.path.join(BESPOKE_OUT_DIR, "0057_surf")
    os.makedirs(out_dir, exist_ok=True)
    written = 0
    for variant in ["opponent", "player"]:
        img = _render_surf_wave(os.path.join(BACKGROUNDS_SRC, f"water_{variant}.bin"))
        out_path = os.path.join(out_dir, f"water_{variant}.png")
        img.save(out_path)
        print(f"  bespoke/0057_surf/water_{variant}.png  ({img.width}x{img.height}, uncropped)")
        written += 1
    return written


def main():
    print("Part A: generic hit-effect library")
    generic_count = pull_generic_library()

    print("Part B: bespoke moves")
    bespoke_count = pull_flamethrower() + pull_thunder() + pull_surf()

    print(f"hit effects: {generic_count} generic + {bespoke_count} bespoke files written")


if __name__ == "__main__":
    main()
