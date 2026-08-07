#!/usr/bin/env python3
"""
[M26E4 rework] Replaces the M26E4-2 Emerald UI Pack pull (Route B) with a
real decode of the reference engine's own Summary screen art
(reference/pokeemerald_expansion/graphics/summary_screen/) -- Rob's own
call, after the pack version was judged not to look right.

Usage (from project root):
    python3 scripts/gen_summary_screen_sprites.py

## The real architecture (confirmed via direct source read, not guessed)

Four real BG layers, per `sBgTemplates`/`InitBgsFromTemplates` (bg=0..3,
priority=0..3): BG0 (priority 0, text windows -- static labels/dynamic
values, not modeled here, this project draws its own real Label nodes
instead) sits on TOP; BG1 (priority 1, the "current" page -- SKILLS or
BATTLE_MOVES) and BG2 (priority 2, the "incoming" page during a page-swap
scroll animation -- this project doesn't animate page swaps, so BG2 is
unused here) sit in the MIDDLE; BG3 (priority 3, lowest -- ALWAYS loaded
with the INFO page's own tilemap, `SetBgTilemapBuffer(3, ...[PSS_PAGE_INFO]
[0])`, confirmed at `pokemon_summary_screen.c:1426`) sits at the BACK.

Confirmed BG_X scroll offset at rest is 0 (`ChangeBgX` uses 8.8 fixed-point;
the only non-zero values, `0x10000`=256px, are used exclusively during the
page-transition slide animation this project doesn't reproduce) -- so each
page's own checked-in 32x32 tilemap sits at its own literal tile
coordinates with no scroll correction needed for a static final layout.

This means: INFO's own tilemap is the ALWAYS-VISIBLE base layer (its own
real portrait-column art on the left, PLUS its own PROFILE/ABILITY/TRAINER
MEMO panel on the right -- E4-4's own future job to actually populate with
real dynamic text, deliberately not built here). SKILLS/BATTLE_MOVES's own
tilemaps are drawn ON TOP of that (BG1 priority 1 < BG3 priority 3, lower
number = drawn in front) -- and their own real content is fully OPAQUE from
roughly tile column 9 rightward (confirmed via direct decode), which is
exactly why the persistent portrait column shows through underneath on
every page: those pages' own tilemaps simply never draw anything opaque
over that region. No manual left/right splitting is needed -- decoding each
tilemap's FULL real content and letting natural opacity do the layering
reproduces the real hardware behavior exactly.

## The tile-atlas decode bug this script's own Step 0 found and fixed

`tiles.png` (128x120 = 16x15 = 240 8x8 tiles, mode "P") stores each pixel
as an ABSOLUTE index into its own embedded 128-color palette -- NOT a
tile-local 4bpp (0-15) index needing the tilemap entry's own palette-bank
bits (`(entry>>12)&0xF`) added on top. A first attempt at this decode
bank-shifted every pixel and produced solid black rectangles wherever a
tile's real color lived outside the bank-shifted range it was checked
against (confirmed via direct debug: local pixel value 44 is a real, valid
absolute palette index -- (205,222,123), a real light-green fill -- but
`bank*16 + 44` overflows into palette territory that happens to be black
for several bank values). The correct decode reads each tile pixel's raw
value directly as the final palette index, with local_idx==0 (true across
every relevant tile in this atlas' own tile 0, confirmed a genuine blank/
transparent filler, not a real color) mapped to alpha=0. The tilemap
entry's own palette-bank bits are read but NOT applied to color lookup --
they're vestigial for this specific atlas, since each tile was already
individually assigned its own correct absolute-palette-index colors at
whatever point produced this checked-in PNG.

## Output

Native 240x160 resolution (this project's own established convention for
genuinely GBA-native content -- scaled up via the consuming .tscn node's
own stretch settings, not pre-upscaled here), real per-pixel alpha
(transparent where the real tilemap draws nothing, letting whatever's
underneath show through -- exactly matching the real hardware layering):

- summary_frame_base.png   -- BG3's own INFO tilemap, ALWAYS visible,
                               every page's own base layer.
- summary_page_skills.png  -- BG1's own SKILLS tilemap, overlaid on the
                               base layer only while the SKILLS page shows.
- summary_page_moves.png   -- BG1's own BATTLE_MOVES tilemap, overlaid
                               only while the MOVES page shows.

CONTEST_MOVES/egg tilemaps are deliberately NOT decoded -- this project
holds to its own already-locked "no contests, no eggs" scope. The move-
selection cursor (`move_select.png`) and the EXP-bar tile variants are
each their own later phase's job (M26E4 rework Phase 3/Phase 4), not
pulled here. `cursor_move.png`/`overlay_exp.png` from the now-superseded
Emerald UI Pack pull are left in place until those phases replace them --
neither is consumed by any code yet, confirmed via direct grep.
"""

import os
import struct
from PIL import Image

from ref_path import REF

REF_SUMMARY_DIR = os.path.join(REF, "graphics", "summary_screen")
OUT_DIR = os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    "..", "assets", "sprites", "battle_ui", "summary",
)

TILE_SIZE = 8
SCREEN_WIDTH_TILES = 30   # 240px -- the real visible GBA screen, not the
SCREEN_HEIGHT_TILES = 20  # full 32x32 tilemap buffer each .bin encodes.

# (tilemap filename, output filename)
PAGES = [
    ("page_info.bin", "summary_frame_base.png"),
    ("page_skills.bin", "summary_page_skills.png"),
    ("page_battle_moves.bin", "summary_page_moves.png"),
]


def _load_atlas():
    atlas = Image.open(os.path.join(REF_SUMMARY_DIR, "tiles.png")).convert("P")
    pal = atlas.getpalette()
    cols = atlas.width // TILE_SIZE
    rows = atlas.height // TILE_SIZE
    return atlas, pal, cols, rows


def _get_tile(atlas, cols, rows, idx):
    tx, ty = idx % cols, idx // cols
    if ty >= rows:
        return None
    box = (tx * TILE_SIZE, ty * TILE_SIZE, tx * TILE_SIZE + TILE_SIZE, ty * TILE_SIZE + TILE_SIZE)
    return atlas.crop(box)


def _decode_tile(tile, pal):
    """Absolute-palette-index decode -- see this module's own doc comment
    for why the tilemap entry's palette-bank bits are NOT applied here."""
    rgba = Image.new("RGBA", (TILE_SIZE, TILE_SIZE))
    src = tile.load()
    dst = rgba.load()
    for y in range(TILE_SIZE):
        for x in range(TILE_SIZE):
            idx = src[x, y]
            if idx == 0:
                dst[x, y] = (0, 0, 0, 0)
                continue
            r, g, b = pal[idx * 3], pal[idx * 3 + 1], pal[idx * 3 + 2]
            dst[x, y] = (r, g, b, 255)
    return rgba


def decode_page(tilemap_path, atlas, pal, cols, rows):
    data = open(tilemap_path, "rb").read()
    entries = struct.unpack("<%dH" % (len(data) // 2), data)
    canvas = Image.new(
        "RGBA",
        (SCREEN_WIDTH_TILES * TILE_SIZE, SCREEN_HEIGHT_TILES * TILE_SIZE),
        (0, 0, 0, 0))
    for i, entry in enumerate(entries):
        tx, ty = i % 32, i // 32
        if tx >= SCREEN_WIDTH_TILES or ty >= SCREEN_HEIGHT_TILES:
            continue  # outside the real visible 240x160 screen
        tile_idx = entry & 0x3FF
        hflip = (entry >> 10) & 1
        vflip = (entry >> 11) & 1
        tile = _get_tile(atlas, cols, rows, tile_idx)
        if tile is None:
            continue
        t = _decode_tile(tile, pal)
        if hflip:
            t = t.transpose(Image.FLIP_LEFT_RIGHT)
        if vflip:
            t = t.transpose(Image.FLIP_TOP_BOTTOM)
        canvas.alpha_composite(t, (tx * TILE_SIZE, ty * TILE_SIZE))
    return canvas


# [Phase 4] The EXP bar is NOT a separate asset in source at all --
# `DrawExperienceProgressBar` (pokemon_summary_screen.c) writes raw tile
# INDICES 0x2062..0x206A directly into the SKILLS page's own live tilemap
# buffer, not a sprite or a second image. Masking off the palette-bank bits
# (entry & 0x3FF, the same mask decode_page() already applies) gives tile
# indices 98-106 -- 9 consecutive tiles already sitting in THIS SAME atlas
# (tiles.png), representing 0 through 8 lit "ticks" within one 8px-wide bar
# segment (source's real bar is 8 such segments wide, each independently
# picking one of these 9 states off its own fill fraction). Sliced here into
# one native-resolution horizontal strip (9 * 8 = 72px wide, 8px tall) for a
# future consumer to pull 8px-wide sub-regions from -- NOT wired into any UI
# node yet, that's E4-4's own job, matching every other Phase 4 asset in
# this pass.
EXP_BAR_FIRST_TILE = 98
EXP_BAR_TILE_COUNT = 9


def gen_exp_bar_ticks(atlas, pal, cols, rows):
    canvas = Image.new("RGBA", (EXP_BAR_TILE_COUNT * TILE_SIZE, TILE_SIZE), (0, 0, 0, 0))
    for i in range(EXP_BAR_TILE_COUNT):
        tile = _get_tile(atlas, cols, rows, EXP_BAR_FIRST_TILE + i)
        if tile is None:
            continue
        t = _decode_tile(tile, pal)
        canvas.alpha_composite(t, (i * TILE_SIZE, 0))
    return canvas


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    atlas, pal, cols, rows = _load_atlas()
    for tilemap_name, out_name in PAGES:
        tilemap_path = os.path.join(REF_SUMMARY_DIR, tilemap_name)
        canvas = decode_page(tilemap_path, atlas, pal, cols, rows)
        out_path = os.path.join(OUT_DIR, out_name)
        canvas.save(out_path)
        print(f"{tilemap_name} -> {out_path} ({canvas.size[0]}x{canvas.size[1]})")

    exp_canvas = gen_exp_bar_ticks(atlas, pal, cols, rows)
    exp_out_path = os.path.join(OUT_DIR, "summary_exp_bar_ticks.png")
    exp_canvas.save(exp_out_path)
    print(f"exp bar ticks -> {exp_out_path} ({exp_canvas.size[0]}x{exp_canvas.size[1]})")

    # [Status icons -- NOT pulled here] `sStatusIconsSpriteSheet`
    # (`graphics/interface/status_icons.png`, source: pokemon_summary_screen.c)
    # is a real, separate, already-pulled asset -- confirmed byte-identical to
    # `assets/sprites/battle_ui/interface/party_status_icons.png`
    # (32x64, pulled by gen_party_screen_sprites.py's own M26E3 E3-1 pull).
    # Deliberately not re-pulled here to avoid a second copy of one asset.
    print("status icons: already pulled, see gen_party_screen_sprites.py "
          "-> assets/sprites/battle_ui/interface/party_status_icons.png")


if __name__ == "__main__":
    main()
