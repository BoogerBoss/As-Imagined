#!/usr/bin/env python3
"""
[M23.11 Phase 5a] Reconstructs the 11 real base battle-background tilesets
from the reference clone's raw GBA tile+tilemap+palette source data into
flat PNGs, written to a project-owned, git-tracked asset directory.

Usage (from project root):
    python3 scripts/gen_battle_backgrounds.py

Why this exists: unlike every prior asset pull (Pokémon sprites, trainer
portraits, item icons, battle UI chrome), the source battle-background art
is genuinely NOT a flat pre-rendered image in the reference checkout — see
docs/m23_11_phase5_recon.md Section 1.1/2 for the full recon. Each terrain
directory under graphics/battle_environment/ holds a 128x128px 4bpp tile
ATLAS (tiles.png, 16x16 grid of 8x8 tiles), a 4096-byte binary TILEMAP
(map.bin, 2048 little-endian u16 GBA screen entries), and a separate
palette file (palette.pal, JASC-PAL text format). This script decodes and
composites those three pieces into one flat PNG per background, following
this project's established one-time-reconstruction-then-flat-copy
convention (gen_pokemon_sprites.py / gen_item_sprites.py /
gen_trainer_portraits.py) rather than a live in-engine tile renderer —
locked scope, see docs/m23_11_phase5_recon.md Section 0 item 1.

Step 0 findings (re-derived directly against ALL 11 tilesets, not just the
single "rock" sample the original recon decoded — see the Phase 5a report
for the full writeup):

- 12 directories exist on disk under graphics/battle_environment/, but
  only 11 have their own tiles.png/map.bin: building, cave, long_grass,
  pond_water, rock, sand, sky, stadium, tall_grass, underwater, water.
  The 12th, `plain/`, has only a palette.pal — it's a pure palette recolor
  of `building`'s tileset (confirmed via src/data/battle_environment.h's
  own BATTLE_ENVIRONMENT_PLAIN entry: .entry/.background both resolve to
  Building's own symbols), matching the "~11 base tilesets, rest are
  recolors" finding from the original recon. `sky`'s own graphics are
  declared in source under the C symbol name "Rayquaza" (confirmed via
  direct grep of src/data/graphics/battle_environment.h) — same physical
  asset, two names; this script uses the on-disk directory name (`sky`)
  as the canonical id.
- All 11 tiles.png are uniformly 128x128px, 4bpp indexed ("P"-mode) PNGs.
  All 11 map.bin are uniformly 4096 bytes (2048 u16 little-endian screen
  entries). 10 of the 11 have their own palette.pal (JASC-PAL, 48 declared
  colors = 3 GBA 16-color palette banks) — `stadium` is the one exception,
  shipping only 8 named recolor variants (aqua/battle_frontier/drake/
  glacia/magma/phoebe/sidney/wallace.pal) with no generic default. Judgment
  call, documented here rather than silently picked: this script uses
  `stadium/battle_frontier.pal` as Stadium's own base/default look, since
  "Frontier" is the least context-specific of the 8 named variants (the
  other 7 are all tied to a specific Elite Four member/Champion/criminal
  team, already deferred to Phase 5d as palette-only recolors anyway).
- Exactly 2 distinct tilemap LAYOUTS are shared across all 11 tilesets,
  confirmed via direct md5sum (not assumed from the single rock sample):
  Group A (byte-identical map.bin) = cave, long_grass, pond_water, rock,
  tall_grass, underwater, water (7 tilesets); Group B (a different but
  also byte-identical-within-the-group map.bin) = building, sand, sky,
  stadium (4 tilesets). This means only 2 real tilemap decodes exist, not
  11 independent ones — each tileset just substitutes its own tiles.png/
  palette.pal into one of the two shared layouts.
- Screen-entry format confirmed as the standard GBA BG format: bits 0-9 =
  tile index (0-1023, atlas has 256 slots), bit 10 = horizontal flip, bit
  11 = vertical flip, bits 12-15 = 4-bit palette bank. The 4096-byte
  tilemap is a 64-tile-wide x 32-tile-tall canvas (2048 = 64*32),
  confirmed (via a block-major vs. row-major visual comparison, not
  assumed) to be TWO 32x32 GBA screen blocks arranged side-by-side
  (block-major: entries 0-1023 = left half, 1024-2047 = right half) — the
  row-major alternative produces a visibly duplicated/mirrored composition
  and was rejected after direct comparison.
- A small fraction of screen entries (32 of 2048, ~1.5%, confirmed via
  direct bank-value tally) reference palette bank 3, which is out of range
  for every tileset's 3-bank (48-color) palette. Handled by wrapping
  (bank % available_banks) — a deliberate, documented simplification for
  what are very likely unused/padding tile slots outside the composited
  canvas's actual visible content, not a sign of a wrong decode (the same
  wrap behavior was verified not to visibly affect the final 240x160 crop
  this script actually emits — the affected entries all fall outside it).
- The composited 64x32-tile canvas has real content concentrated in
  roughly its top 12-14 tile rows, with a large solid-color area below.
  Confirmed structurally intentional, not a decode bug: both shared
  tilemap layouts (Group A and Group B) independently show the identical
  shape (a striped upper band + a floating platform-oval + a large flat
  area beneath), and this matches the real GBA battle screen's own known
  composition — only the top portion of the 160px-tall screen is ever
  actually visible during a real battle, since the message/menu textbox
  permanently occludes roughly the bottom third. This script crops each
  composited canvas to exactly the top-left 240x160px (one full GBA
  screen, matching the implied zero default BG scroll offset — no
  evidence of a nonzero resting HOFS/VOFS was found in battle_bg.c), which
  is the correct "resting frame" a real battle would show before this
  project's own UI (health boxes, message box, menu) draws on top.
- The `.entry`/anim_tiles.png/anim_map.bin files (the intro-reveal wipe
  layer) are deliberately NOT read by this script at all — out of scope
  per the locked decision in docs/m23_11_phase5_recon.md Section 0 item 2.

Output: one flat 240x160 PNG per tileset, named `<id>.png` (id = the
on-disk directory name, already a clean snake_case slug — e.g. `rock.png`,
`tall_grass.png`), written to res://assets/sprites/battle_backgrounds/.
No numeric ID scheme is used (unlike Pokémon dex numbers / trainer pic
IDs) since there's no existing battle-environment-ID concept anywhere in
this project yet — BattleBackgroundRegistry keys purely off this filename
stem, matching TrainerPicRegistry's own lazy-scan convention.

Idempotent: re-running overwrites the 11 output files with a fresh
reconstruction.
"""

import os
import struct

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REF = os.path.join(ROOT, "reference", "pokeemerald_expansion")
SRC_DIR = os.path.join(REF, "graphics", "battle_environment")
OUT_DIR = os.path.join(ROOT, "assets", "sprites", "battle_backgrounds")

# The 11 real base tilesets (directories with their own tiles.png/map.bin).
# `plain` deliberately excluded (palette-only recolor of `building`, no own
# tiles/map — see module docstring). `stadium` has no own palette.pal; the
# override below picks a documented default.
TILESET_IDS = [
    "building", "cave", "long_grass", "pond_water", "rock", "sand", "sky",
    "stadium", "tall_grass", "underwater", "water",
]

PALETTE_OVERRIDE = {
    "stadium": "battle_frontier.pal",
}

CROP_WIDTH = 240
CROP_HEIGHT = 160
MAP_TILES_WIDE = 64
MAP_TILES_TALL = 32
SCREEN_BLOCK_TILES = 32  # one GBA screen block = 32x32 tiles = 1024 entries


def load_jasc_pal(path):
    with open(path, encoding="utf-8") as f:
        lines = f.read().splitlines()
    assert lines[0] == "JASC-PAL", f"unexpected palette header in {path}: {lines[0]!r}"
    n = int(lines[2])
    colors = []
    for i in range(n):
        r, g, b = (int(v) for v in lines[3 + i].split())
        colors.append((r, g, b))
    return colors


def render_background(tileset_id: str) -> Image.Image:
    src = os.path.join(SRC_DIR, tileset_id)
    tiles_path = os.path.join(src, "tiles.png")
    map_path = os.path.join(src, "map.bin")
    pal_filename = PALETTE_OVERRIDE.get(tileset_id, "palette.pal")
    pal_path = os.path.join(src, pal_filename)

    palette = load_jasc_pal(pal_path)
    num_banks = max(1, len(palette) // 16)

    atlas = Image.open(tiles_path).convert("P")
    atlas_px = atlas.load()
    tiles_per_row = atlas.width // 8

    with open(map_path, "rb") as f:
        raw = f.read()
    entry_count = MAP_TILES_WIDE * MAP_TILES_TALL
    entries = struct.unpack(f"<{entry_count}H", raw)

    canvas = Image.new("RGB", (MAP_TILES_WIDE * 8, MAP_TILES_TALL * 8))
    canvas_px = canvas.load()

    for row in range(MAP_TILES_TALL):
        for col in range(MAP_TILES_WIDE):
            # Two 32x32 screen blocks arranged side-by-side, block-major
            # (left half = block 0, right half = block 1) — confirmed via
            # direct visual comparison against row-major, see module
            # docstring.
            block = col // SCREEN_BLOCK_TILES
            local_col = col % SCREEN_BLOCK_TILES
            entry = entries[block * 1024 + row * SCREEN_BLOCK_TILES + local_col]

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

    return canvas.crop((0, 0, CROP_WIDTH, CROP_HEIGHT))


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    written = 0
    for tileset_id in TILESET_IDS:
        img = render_background(tileset_id)
        out_path = os.path.join(OUT_DIR, f"{tileset_id}.png")
        img.save(out_path)
        written += 1
        print(f"  {tileset_id}.png  ({img.width}x{img.height})")

    print(f"battle backgrounds: {written} written to {OUT_DIR}")


if __name__ == "__main__":
    main()
