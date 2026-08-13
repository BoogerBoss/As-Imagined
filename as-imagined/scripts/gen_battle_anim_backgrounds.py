#!/usr/bin/env python3
r"""[M36E1] Battle-anim background pull: BG tilemaps -> flat composited PNGs.

Scope of record: docs/m26_f1_recon.md (M36E = Phase E of the approved tiered
port). This is the asset half of the background layer, and it is what unblocks
the concentrated cluster of moves M36D could not reach: Surf (the move M23.11
Phase 5b flagged as looking wrong in the first place), the psychic-background
family, Metallic Shine, the sliding-BG family and the scrolling fog.

Why a separate script from gen_battle_anim_sprites.py: backgrounds are not
sprites. Each one is a TILEMAP over a tile sheet -- the sheet holds unique
8x8 tiles and the .bin says where each goes, with per-cell flip flags -- so
the pull has to composite rather than copy. That decode is the same GBA
screen-entry format this project has already implemented three times
(gen_ui_frames.py, gen_hit_effect_sprites.py's Surf wave, and the retired
gen_battle_backgrounds.py), and the bit layout is reproduced here rather than
imported because those callers each decode a different asset family.

Screen-entry format (u16 per cell):
    bits 0-9   tile index into the sheet (raster order, 8x8, 4bpp)
    bit 10     horizontal flip
    bit 11     vertical flip
    bits 12-15 palette bank

Findings that shape the output, each verified against the tree rather than
assumed:

- `gBattleAnimBackgroundTable` (src/data/battle_anim.h:1437) has 84 entries
  keyed by BG_* id, and they REUSE assets heavily: Hyper Beam, Dynamax Cannon
  and Chloroblast all share Hydro Cannon's tiles AND tilemap, differing only
  by palette, and the day/afternoon/night rock fields are one image with three
  palettes. Output is therefore keyed by BG NAME, not by source file -- the
  same "one sheet, N recolors" reason the sprite pull is tag-keyed.
- Player/opponent/contest variants are SEPARATE BG ids sharing one tile sheet
  with different tilemaps, so they composite to genuinely different images.
- Tilemap sizes are 896 / 1280 / 2048 / 4096 bytes = 32x14, 32x20, 32x32 and
  32x64 cells. Width is always 32 (the GBA screen is 30 tiles wide; the extra
  two are the scroll margin), so height is derived, never guessed.
- Palette banks: a background's CONTENT lives in one bank (2 for table
  entries, 8 for a couple of the code-referenced ones), while bank 0 carries
  only the blank tile (index 0) for empty cells. That was measured, not
  assumed -- the first cut asserted a single bank outright and correctly
  refused 19 backgrounds, which is how the real rule came to light. The
  assertion now allows the blank-tile bank and still refuses anything with
  content in TWO banks, because that asset would need more than the one
  16-colour palette this decode applies and would otherwise render in the
  wrong colours.
- Tile index 0 is the transparent/blank tile in these sheets, and the palette's
  index 0 is the transparency key, so output carries real alpha.

Also pulls the CODE-REFERENCED backgrounds that are not in the table at all
(they are loaded by symbol from anim code): the Surf wave's three variants,
scary_face, solarbeam, fog, sandstorm_brew and attract. Those are exactly the
ones M36E's behaviors need, and nothing else reaches them.

Output: assets/sprites/battle_anims/backgrounds/<name>.png + index.json
Idempotent; overwrites unconditionally. Requires Pillow.
"""

import json
import os
import re
import struct
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ref_path import REF, PROJECT, assert_inside_project
from gen_battle_anim_meta import parse_incgfx_symbols, strip_comments
from gen_battle_anim_scripts import ConstResolver, load_defines, CONST_HEADERS

DATA_BATTLE_ANIM_H = os.path.join(REF, "src", "data", "battle_anim.h")
OUT_DIR = assert_inside_project(
    os.path.join(PROJECT, "assets", "sprites", "battle_anims", "backgrounds"),
    "battle_anim backgrounds dir")
INDEX_PATH = os.path.join(OUT_DIR, "index.json")

TILEMAP_WIDTH = 32  # cells; the GBA screen is 30 wide plus a scroll margin

# ⚠️ **THE 32-WIDE RULE IS NOT UNIVERSAL, AND SURF IS THE EXCEPTION.**
# A text BG's shape comes from its BGCNT screen size, not from the tilemap's
# byte count: 0 = 256x256, 1 = 512x256, 2 = 256x512. Every move background in
# the tree sets size 0 EXCEPT Surf, which sets 1
# (`SetAnimBgAttribute(1, BG_ANIM_SCREEN_SIZE, 1)`, battle_anim_water.c:1000).
# So Surf's 2048 cells are 64 wide x 32 tall, and folding them 32x64 -- which
# this generator did, because it derived height from a fixed width -- halves
# the horizontal wrap period and stacks the right half of the wave underneath
# the left instead of beside it.
#
# Reported from play: "towards the end of the animation the top left corner
# has another wave sneak in." That is the wrap firing at 256px when hardware
# wraps at 512. Surf scrolls -2px/frame for ~134 frames = 268px, which clears
# 256 (so the port wraps, late, visibly) and does not clear 512 (so hardware
# never wraps at all).
#
# ⚠️ **AND A 512-WIDE TEXT BG IS TWO 32x32 SCREENBLOCKS SIDE BY SIDE, NOT ONE
# 64-WIDE GRID.** Cells 0-1023 are the left block and 1024-2047 the right, each
# row-major within itself. A plain 64-wide reshape would interleave the two and
# produce a finely striped image that still measures 512x256.
WIDE_TILEMAPS = {
    "graphics/battle_anims/backgrounds/water_player.bin",
    "graphics/battle_anims/backgrounds/water_opponent.bin",
    "graphics/battle_anims/backgrounds/water_contest.bin",
}
SCREENBLOCK_CELLS = 32 * 32

# ⚠️ **TEN OTHER TILEMAPS ARE ALSO 2048 CELLS AND ARE DELIBERATELY NOT LISTED**
# -- the four terrain families (this project has no terrain system; M17e is
# VOID) plus Hydro Cannon and Fissure. None of them sets screen size 1, so the
# ambiguity is not theirs; they are folded 32-wide as before. Flagged rather
# than swept in, because "2048 cells" is the symptom and "sets screen size 1"
# is the cause, and only Surf has the cause.
# The GBA shows 30x20 tiles of the 32-wide map; the rest is scroll margin.
VISIBLE_TILES_X = 30
VISIBLE_TILES_Y = 20

# Backgrounds the anim CODE loads by symbol rather than through the table.
# name -> (tiles, tilemap, palette) as repo-relative paths. These are the ones
# M36E's own behaviors reach for; every other non-table background belongs to
# systems this project does not implement.
CODE_REFERENCED = {
    "surf_player": ("water.png", "water_player.bin", None),
    "surf_opponent": ("water.png", "water_opponent.bin", None),
    "surf_contest": ("water.png", "water_contest.bin", None),
    "surf_muddy_player": ("water.png", "water_player.bin", "water_muddy.pal"),
    "scary_face_player": ("scary_face.png", "scary_face_player.bin", None),
    "scary_face_opponent": ("scary_face.png", "scary_face_opponent.bin", None),
    "sandstorm_brew": ("sandstorm_brew.png", "sandstorm_brew.bin", None),
    "attract": ("attract.png", "attract.bin", None),
    # Deliberately ABSENT, having been checked rather than guessed:
    #   solarbeam.bin is marked "// Unused" upstream (src/graphics.c:1434) and
    #     the real Solar Beam backgrounds are BG_SOLAR_BEAM_* table entries,
    #     already covered above.
    #   fog.bin (gBattleAnimFogTilemap, src/graphics.c:1638) has NO matching
    #     fog.png -- its tiles come from another symbol entirely, which the
    #     scrolling-fog behavior will have to resolve when it is ported.
}

BG_DIR_REL = os.path.join("graphics", "battle_anims", "backgrounds")


def read_jasc_pal(path):
    with open(path) as f:
        lines = [l.strip() for l in f if l.strip()]
    if lines[0] != "JASC-PAL":
        raise SystemExit("not a JASC palette: %s" % path)
    count = int(lines[2])
    colors = []
    for line in lines[3:3 + count]:
        r, g, b = (int(v) for v in line.split())
        colors.extend((r, g, b))
    return colors


def load_palette(rel_path):
    abs_path = os.path.join(REF, rel_path)
    if rel_path.endswith(".pal"):
        return read_jasc_pal(abs_path)
    with Image.open(abs_path) as im:
        if im.mode != "P":
            raise SystemExit("palette source not indexed: %s" % rel_path)
        return im.getpalette()


def tiles_of(img):
    """8x8 tiles in raster order -- the order gbagfx emits them."""
    out = []
    for ty in range(img.height // 8):
        for tx in range(img.width // 8):
            out.append(img.crop((tx * 8, ty * 8, tx * 8 + 8, ty * 8 + 8)))
    return out


def composite(tiles_rel, tilemap_rel, palette_rel, name):
    """Decode one background into a flat RGBA image."""
    tiles_path = os.path.join(REF, tiles_rel)
    map_path = os.path.join(REF, tilemap_rel)
    for p in (tiles_path, map_path):
        if not os.path.exists(p):
            return None, None, "missing source %s" % os.path.relpath(p, REF)

    with Image.open(tiles_path) as sheet:
        if sheet.mode != "P":
            return None, None, "tile sheet not indexed"
        sheet = sheet.copy()
    if palette_rel:
        sheet.putpalette(load_palette(palette_rel))
    tiles = tiles_of(sheet)
    # The 16 colours this decode actually applies, IN PALETTE ORDER. Emitted
    # because AnimTask_SetPsychicBackground (and FadeScreenToWhite) animate a
    # background by ROTATING palette entries 1..11 -- an effect that cannot be
    # reproduced from a composited RGBA image alone, since the image records
    # only which colour each pixel ended up as, not which slot it came from.
    bank_pal = [list(sheet.getpalette()[i * 3:i * 3 + 3]) for i in range(16)]

    with open(map_path, "rb") as f:
        raw = f.read()
    if len(raw) % 2:
        return None, None, "tilemap length %d is not u16-aligned" % len(raw)
    cells = struct.unpack("<%dH" % (len(raw) // 2), raw)
    # Surf and only Surf is a 512x256 BG -- see WIDE_TILEMAPS.
    wide = tilemap_rel in WIDE_TILEMAPS
    if wide:
        if len(cells) != 2 * SCREENBLOCK_CELLS:
            return None, None, ("wide tilemap %d cells, expected %d"
                                % (len(cells), 2 * SCREENBLOCK_CELLS))
        cols, rows = TILEMAP_WIDTH * 2, TILEMAP_WIDTH
    else:
        cols = TILEMAP_WIDTH
        rows = len(cells) // TILEMAP_WIDTH
        if rows * TILEMAP_WIDTH != len(cells):
            return None, None, "tilemap %d cells is not a multiple of %d" % (
                len(cells), TILEMAP_WIDTH)

    def cell_xy(i):
        """Cell index -> (tile x, tile y) for this BG's real screen size."""
        if not wide:
            return i % TILEMAP_WIDTH, i // TILEMAP_WIDTH
        # Two side-by-side 32x32 screenblocks, each row-major within itself.
        block, within = divmod(i, SCREENBLOCK_CELLS)
        return (within % TILEMAP_WIDTH) + block * TILEMAP_WIDTH, \
            within // TILEMAP_WIDTH

    # Bank 0 with tile index 0 is an EMPTY cell and carries no colour, so it
    # never conflicts. What matters is that all actual content shares one
    # bank -- otherwise a single 16-colour palette cannot render this asset.
    #
    # ⚠️ MEASURED OVER THE VISIBLE REGION ONLY, and that distinction is the
    # whole reason three assets were being refused. A tilemap is 32 cells wide
    # by up to 32 tall, but the GBA screen shows 30x20 of it; the rest is
    # scroll margin. The authors parked filler cells out there in whatever
    # bank was convenient, so measuring the WHOLE map reports a bank span that
    # nothing on screen ever exhibits:
    #
    #   scary_face_player / _opponent : one filler row at y=20 (bank 1),
    #                                   directly below the visible area
    #   attract                       : the x>=30 margin and y>=20 rows (bank 0)
    #
    # Restricted to what is actually drawn, all three are single-bank. Verified
    # across every tilemap in the tree: NONE is multi-bank inside the visible
    # region, so this narrows what the guard measures without weakening what it
    # means. Because no real asset can now trip it, `--self-test` injects a
    # synthetic two-bank-in-visible-region map to prove it still bites.
    #
    # DISCLOSED: the composite still covers the FULL map (the scroll margin is
    # load-bearing for the sliding-BG family), so an off-screen cell in another
    # bank is drawn with the visible bank's palette. That is only ever seen if
    # a behavior scrolls it into view. Confirmed non-scrolling for ScaryFace
    # (AnimTask_ScaryFace_Step holds BG1 X/Y at 0 and only blends); NOT checked
    # for attract, which currently has no consumer.
    def _content_banks(only_visible: bool) -> set:
        out = set()
        for idx, cell in enumerate(cells):
            if (cell & 0x3FF) == 0:
                continue
            cx, cy = cell_xy(idx)
            if only_visible and (cx >= VISIBLE_TILES_X
                    or cy >= VISIBLE_TILES_Y):
                continue
            out.add((cell >> 12) & 0xF)
        return out

    content_banks = _content_banks(True)
    if len(content_banks) > 1:
        return None, None, ("content spans %d palette banks %s INSIDE the visible "
                      "region -- needs more than the one 16-colour palette this "
                      "decode applies"
                      % (len(content_banks), sorted(content_banks)))
    offscreen_only = _content_banks(False) - content_banks
    if offscreen_only:
        print("   note: %s carries bank(s) %s only outside the visible region; "
              "drawn with the visible bank's palette"
              % (os.path.basename(map_path), sorted(offscreen_only)))

    # Composite in RGBA so palette index 0 becomes real transparency.
    canvas = Image.new("RGBA", (cols * 8, rows * 8), (0, 0, 0, 0))
    pal = sheet.getpalette()
    for i, cell in enumerate(cells):
        idx = cell & 0x3FF
        if idx >= len(tiles):
            return None, None, "tile index %d exceeds sheet (%d tiles)" % (
                idx, len(tiles))
        tile = tiles[idx]
        if cell & (1 << 10):
            tile = tile.transpose(Image.FLIP_LEFT_RIGHT)
        if cell & (1 << 11):
            tile = tile.transpose(Image.FLIP_TOP_BOTTOM)
        # Index 0 is the transparency key.
        rgba = Image.new("RGBA", (8, 8), (0, 0, 0, 0))
        px = tile.load()
        out = rgba.load()
        for y in range(8):
            for x in range(8):
                v = px[x, y]
                if v != 0:
                    out[x, y] = (pal[v * 3], pal[v * 3 + 1], pal[v * 3 + 2],
                                 255)
        cx, cy = cell_xy(i)
        canvas.paste(rgba, (cx * 8, cy * 8), rgba)
    return canvas, bank_pal, None


def parse_bg_table(resolver, sym_paths):
    """BG_* name -> (tiles, palette, tilemap) repo-relative source paths."""
    with open(DATA_BATTLE_ANIM_H) as f:
        text = strip_comments(f.read())
    start = text.index("gBattleAnimBackgroundTable")
    entries = {}
    pat = re.compile(
        r"\[(\w+)\]\s*=\s*\{\s*(\w+)\s*,\s*(\w+)\s*,\s*(\w+)\s*\}")
    for line in text[start:].splitlines():
        if line.strip().startswith("};"):
            break
        m = pat.search(line)
        if not m:
            continue
        bg, image, palette, tilemap = m.groups()
        missing = [s for s in (image, palette, tilemap) if s not in sym_paths]
        if missing:
            raise SystemExit("no INCGFX binding for %s" % missing)
        entries[bg] = {
            "tiles": sym_paths[image],
            "palette": sym_paths[palette],
            "tilemap": sym_paths[tilemap],
        }
    return entries


def main():
    resolver = ConstResolver(load_defines(CONST_HEADERS))
    sym_paths = parse_incgfx_symbols()
    table = parse_bg_table(resolver, sym_paths)

    os.makedirs(OUT_DIR, exist_ok=True)
    index = {}
    written = 0
    skipped = []

    for bg, src in sorted(table.items()):
        name = bg.replace("BG_", "").lower()
        # The palette source is only applied when it differs from the tile
        # sheet, matching the sprite pull's own rule: an embedded PLTE is
        # already correct, and re-applying it is a no-op that only risks
        # disagreeing with the source of truth.
        pal_rel = src["palette"] if src["palette"] != src["tiles"] else None
        img, bank_pal, err = composite(
            src["tiles"], src["tilemap"], pal_rel, name)
        if img is None:
            skipped.append((bg, err))
            continue
        out_name = name + ".png"
        img.save(os.path.join(OUT_DIR, out_name))
        index[bg] = {
            "file": out_name,
            "width": img.width,
            "height": img.height,
            "tiles": src["tiles"],
            "tilemap": src["tilemap"],
            "palette": src["palette"],
            "palette_colors": bank_pal,
            "source": "table",
        }
        img.close()
        written += 1

    for name, (tiles, tilemap, palette) in sorted(CODE_REFERENCED.items()):
        img, bank_pal, err = composite(
            os.path.join(BG_DIR_REL, tiles),
            os.path.join(BG_DIR_REL, tilemap),
            os.path.join(BG_DIR_REL, palette) if palette else None, name)
        if img is None:
            skipped.append((name, err))
            continue
        out_name = name + ".png"
        img.save(os.path.join(OUT_DIR, out_name))
        index[name.upper()] = {
            "file": out_name,
            "width": img.width,
            "height": img.height,
            "tiles": os.path.join(BG_DIR_REL, tiles),
            "tilemap": os.path.join(BG_DIR_REL, tilemap),
            "palette": os.path.join(BG_DIR_REL, palette) if palette else None,
            "palette_colors": bank_pal,
            "source": "code",
        }
        img.close()
        written += 1

    with open(INDEX_PATH, "w") as f:
        json.dump({"meta": {
            "generated_by": "scripts/gen_battle_anim_backgrounds.py [M36E1]",
            "count": written,
            "table_entries": len(table)},
            "backgrounds": index}, f, separators=(",", ":"), sort_keys=True)

    print("table entries parsed: %d" % len(table))
    print("wrote %d PNGs to %s" % (written, os.path.relpath(OUT_DIR, PROJECT)))
    if skipped:
        print("SKIPPED %d (reported, not silently dropped):" % len(skipped))
        for bg, err in skipped:
            print("   %-34s %s" % (bg, err))


if __name__ == "__main__":
    main()
