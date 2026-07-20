#!/usr/bin/env python3
"""
[M25h-4] Reconstructs the real Item/Bag and Switch/Party screen frame art
from the reference clone's raw GBA tile+tilemap+palette source data into
flat PNGs, following gen_battle_backgrounds.py's own proven decode
technique (Phase 5a) -- see that script's own docstring for the general
GBA screen-entry format this reuses unchanged (u16 entries: bits 0-9 tile
index, bit 10/11 h/v-flip, bits 12-15 palette bank; one screen block =
32x32 tiles).

Usage (from project root):
    python3 scripts/gen_ui_frames.py

Why this exists: M25h-1.4/M25h-1.5 both shipped reusing the generic
text_window/1.png panel art (a real but screen-agnostic GBA dialogue-box
asset) for the Item/Bag and Switch/Party screens, since a prior attempt at
this exact class of decode (Phase 5a, battle backgrounds) was flagged as
visually incorrect and a second attempt was explicitly declined (M25h-1.4's
own Bag-screen scope note). M25h-3's audit revisited this and this session
re-attempts the decode a third time, with two real findings that change the
picture from Phase 5a's own experience:

1. Direct pixel inspection of Phase 5a's own still-in-use flawed output
   (assets/sprites/battle_backgrounds/sky.png -- never replaced, no CFRU
   substitute found during M25e) shows the SAME horizontal-banding artifact
   already present in the RAW SOURCE ATLAS (graphics/battle_environment/
   sky/tiles.png) when viewed with nothing but its own embedded palette --
   i.e. before any of Phase 5a's own decode/composition logic ever runs.
   This means the "flaw" very likely was not a bug in Phase 5a's own
   tile/tilemap/palette composition math (which a later session, M25.11
   Phase 5c, independently re-validated against a different asset --
   water.png -- and found "no artifacts, notably cleaner than Phase 5a's
   own environment-tileset output"), but rather a genuine stylistic
   mismatch between this reference checkout's own sky/atmosphere dither art
   and a modern viewer's expectation of a smooth gradient. Not conclusively
   provable from this checkout alone, but strong enough evidence that a
   fresh attempt on a COMPLETELY DIFFERENT asset (real UI chrome, not an
   environment backdrop) is warranted rather than treating Phase 5a's
   experience as a blanket "this technique doesn't work" verdict.
2. Bag's menu.bin/Party's bg.bin are both confirmed, via direct read of
   src/item_menu.c ("DecompressDataWithHeaderWram(gBagScreen_GfxTileMap,
   gBagMenu->tilemapBuffer)") and src/party_menu.c (the identical call for
   gPartyMenuBg_Tilemap), to load as a STANDARD single 32x32 GBA screen
   block (2048 bytes = 1024 u16 entries each) -- i.e. the exact same format
   Phase 5a's own script already correctly decodes, not the "smol"-
   compressed ROM-build-time target format the INCGFX_U32(...,".smolTM")
   macro's own name suggested at first glance (that name describes what the
   BUILD TOOLCHAIN compresses the checked-in raw file INTO for the ROM, not
   the checked-in source file's own on-disk encoding -- confirmed by exact
   byte-size sanity checks: 2048 bytes is precisely one 32x32 block's worth
   of plain u16 entries, not a plausible compressed-blob size).

A real, clean decode was confirmed via direct visual inspection before this
script was written for real (see this session's own report): Bag's canvas
shows a recognizable title bar (pokeball icon, dotted decoration) plus a
cream item-list panel plus white description boxes, at exactly 240x160px
(one full GBA screen) once cropped to real content; Party's canvas shows a
recognizable rounded-corner olive list panel, at 240x192px once cropped.

Party's PER-ROW slot art is a genuinely different, simpler format --
confirmed via direct read of BlitBitmapToPartyWindow (party_menu.c): a flat
u8 tile-index array (no flip/bank bits at all, unlike the screen-block
format above), referencing the SAME bg.png atlas. sSlotTilemap_Wide
(graphics/party_menu/slot_wide.bin, 18x3 tiles = 144x24px) is the format
actually relevant here -- this project's own Switch screen shows a
scrollable LIST of single-row candidates, which is exactly what source's
own "wide" (multi-mon-list-row) format is for, not the "main" (10x7, a
single big singles-battle box) format. Palette bank 0 renders it as a real
blue rounded pill with "HP" baked into the art (confirmed via direct visual
comparison against bank 1, which renders the identical shape/text in
yellow/gold -- confirming these banks are a real, source-native
selection/highlight-state palette swap, not directly the HP-fraction green/
yellow/red color; that HP-fraction color is a narrower, separate sub-
palette swap applied only to the HP bar's own few palette slots at runtime
(DisplayPartyPokemonHPBar, party_menu.c:2726) layered on top of whichever
bank is active -- reproduced in Godot as a color-tinted overlay rectangle
positioned over the bar's own known pixel region within the decoded slot
art, not a second full palette-bank re-decode.

Idempotent: re-running overwrites the output files with a fresh
reconstruction.
"""

import os
import struct

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REF = os.path.join(ROOT, "reference", "pokeemerald_expansion")
OUT_DIR = os.path.join(ROOT, "assets", "sprites", "battle_ui", "screens")

SCREEN_BLOCK_TILES = 32


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


def png_embedded_palette(path):
    im = Image.open(path)
    flat = im.getpalette()
    return [tuple(flat[i:i + 3]) for i in range(0, len(flat), 3)]


def decode_screen_block(tiles_path, map_path, palette):
    """Standard GBA BG format (Phase 5a's own decode, reused unchanged):
    u16 screen entries, one 32x32-tile block."""
    atlas = Image.open(tiles_path).convert("P")
    atlas_px = atlas.load()
    tiles_per_row = atlas.width // 8
    num_banks = max(1, len(palette) // 16)

    with open(map_path, "rb") as f:
        raw = f.read()
    entry_count = len(raw) // 2
    entries = struct.unpack(f"<{entry_count}H", raw)
    tiles_tall = entry_count // SCREEN_BLOCK_TILES

    canvas = Image.new("RGB", (SCREEN_BLOCK_TILES * 8, tiles_tall * 8))
    canvas_px = canvas.load()

    for row in range(tiles_tall):
        for col in range(SCREEN_BLOCK_TILES):
            entry = entries[row * SCREEN_BLOCK_TILES + col]
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
                    if tx + sx >= atlas.width or ty + sy >= atlas.height:
                        pixel = 0
                    else:
                        pixel = atlas_px[tx + sx, ty + sy]
                    final_idx = pixel + bank * 16
                    color = palette[final_idx] if final_idx < len(palette) else (255, 0, 255)
                    canvas_px[col * 8 + dx, row * 8 + dy] = color
    return canvas


def decode_u8_slot(tiles_path, map_path, palette, width_tiles, height_tiles, bank=0):
    """Party per-slot format (BlitBitmapToPartyWindow): flat u8 tile-index
    array, no flip/bank bits -- the bank param picks which of the atlas's
    own palette banks to render with (0 = the default/blue state, confirmed
    via direct visual comparison against bank 1's yellow/gold render)."""
    atlas = Image.open(tiles_path).convert("P")
    atlas_px = atlas.load()
    tiles_per_row = atlas.width // 8

    with open(map_path, "rb") as f:
        raw = f.read()

    canvas = Image.new("RGB", (width_tiles * 8, height_tiles * 8))
    canvas_px = canvas.load()
    for row in range(height_tiles):
        for col in range(width_tiles):
            idx = row * width_tiles + col
            tile_idx = raw[idx] if idx < len(raw) else 0
            tx = (tile_idx % tiles_per_row) * 8
            ty = (tile_idx // tiles_per_row) * 8
            for dy in range(8):
                for dx in range(8):
                    if tx + dx >= atlas.width or ty + dy >= atlas.height:
                        pixel = 0
                    else:
                        pixel = atlas_px[tx + dx, ty + dy]
                    final_idx = pixel + bank * 16
                    color = palette[final_idx] if final_idx < len(palette) else (255, 0, 255)
                    canvas_px[col * 8 + dx, row * 8 + dy] = color
    return canvas


def content_bbox(im, bg_color=None):
    """Crops the decoded canvas's large flat off-screen padding area away --
    mirrors Phase 5a's own reasoning that only the top portion of a
    composited canvas is ever real visible content (see that script's own
    docstring), just detected directly from pixel data here instead of
    assumed as a fixed 240x160."""
    import numpy as np
    arr = np.array(im.convert("RGB"))
    if bg_color is None:
        colors, counts = np.unique(arr.reshape(-1, 3), axis=0, return_counts=True)
        bg_color = colors[np.argmax(counts)]
    mask = np.any(arr != bg_color, axis=2)
    ys, xs = np.where(mask)
    return im.crop((int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1))


def main():
    os.makedirs(OUT_DIR, exist_ok=True)

    # Bag/Item screen frame -- menu.png (atlas) + menu.bin (tilemap) +
    # menu_male.pal (2 banks, matching item_menu.c's own
    # LoadPalette(gBagScreenMale_Pal, BG_PLTT_ID(0), 2 * PLTT_SIZE_4BPP)).
    bag_pal = load_jasc_pal(os.path.join(REF, "graphics/bag/menu_male.pal"))
    bag_canvas = decode_screen_block(
        os.path.join(REF, "graphics/bag/menu.png"),
        os.path.join(REF, "graphics/bag/menu.bin"),
        bag_pal,
    )
    bag_cropped = content_bbox(bag_canvas)
    bag_out = os.path.join(OUT_DIR, "bag_frame.png")
    bag_cropped.save(bag_out)
    print(f"  bag_frame.png  ({bag_cropped.width}x{bag_cropped.height})")

    # Switch/Party screen frame -- bg.png (atlas, own embedded 11-bank
    # palette used directly per src/graphics.c's own
    # INCGFX_U16("graphics/party_menu/bg.png", ".gbapal")) + bg.bin.
    party_pal = png_embedded_palette(os.path.join(REF, "graphics/party_menu/bg.png"))
    party_canvas = decode_screen_block(
        os.path.join(REF, "graphics/party_menu/bg.png"),
        os.path.join(REF, "graphics/party_menu/bg.bin"),
        party_pal,
    )
    party_cropped = content_bbox(party_canvas)
    party_out = os.path.join(OUT_DIR, "party_frame.png")
    party_cropped.save(party_out)
    print(f"  party_frame.png  ({party_cropped.width}x{party_cropped.height})")

    # Switch/Party per-row slot art -- the real "wide" list-row format
    # (sSlotTilemap_Wide, 18x3 tiles), bank 0 (the default/non-highlighted
    # state -- confirmed via direct visual comparison against bank 1).
    party_slot = decode_u8_slot(
        os.path.join(REF, "graphics/party_menu/bg.png"),
        os.path.join(REF, "graphics/party_menu/slot_wide.bin"),
        party_pal, 18, 3, bank=0,
    )
    party_slot_out = os.path.join(OUT_DIR, "party_slot_wide.png")
    party_slot.save(party_slot_out)
    print(f"  party_slot_wide.png  ({party_slot.width}x{party_slot.height})")

    print(f"UI frames: 3 written to {OUT_DIR}")


if __name__ == "__main__":
    main()
