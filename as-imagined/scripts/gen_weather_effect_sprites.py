#!/usr/bin/env python3
"""
[M26B4-1] Pulls the in-battle weather animation asset set: five particle/
effect sprite sheets plus one decoded scrolling background.

Usage (from project root):
    python3 scripts/gen_weather_effect_sprites.py

Asset staging only — no dispatch/UI wiring here, that's M26B4-2/B4-3's job
(matches gen_hit_effect_sprites.py's own "no UI consumption this session"
precedent).

Full recon and per-animation breakdown: docs/m26_b4_recon.md.

WHY THESE ASSETS
────────────────
Source has NO persistent battle weather renderer (proven five ways in the
recon's §1 — battle_bg.c has zero weather references, and battle entry
destroys the whole field-weather task/sprite set). Instead it REPLAYS a
finite weather animation every turn, from BattleScript_WeatherContinues.
These are the assets those animations use.

Crucially, for Sun/Sandstorm/Hail/Snow the per-turn "continues" animation is
a literal `goto` into the MOVE's own script — the same animation, not a
variant — so one asset set serves both consumers. Only Rain has a separate
(shorter) per-turn routine, and it reuses the same rain_drops.png.

DESTINATION — a NEW `weather/` subdirectory, deliberately
─────────────────────────────────────────────────────────
NOT battle_effects/generic/: hit_effect_smoke_test asserts that directory's
exact contents (21 curated hit-effect sprites), and [M26B3-6a] already had
to relocate the ball-particle sheet out of it for exactly this reason.

NOT per-move battle_effects/bespoke/<id>_<move>/ subdirs either: these
assets have TWO consumers (the move animation AND the per-turn replay, which
is keyed by weather STATE, not by move), so keying the files by weather
rather than by move avoids duplicating them four ways.

TRANSPARENCY — index 0, tagged explicitly (sprites only)
────────────────────────────────────────────────────────
Same rule and same reasoning as gen_hit_effect_sprites.py / gen_ball_sprites.py:
these source PNGs carry no tRNS chunk, but palette index 0 is the intended
transparency key per the universal GBA rule that OBJ-layer palette index 0 is
always transparent. Index 0 is NOT a constant colour across these files
(verified), so tag the INDEX — never colour-key a value. A plain
shutil.copyfile would render each particle inside an opaque box.

The sandstorm BACKGROUND is the opposite case and is deliberately left
OPAQUE: GBA BG layers render index 0 as a real colour (already established
in Phase 5a and reconfirmed for Surf's water.png in Phase 5b).

SANDSTORM'S PALETTE — a real cross-file reference, checked
──────────────────────────────────────────────────────────
AnimTask_LoadSandstormBackground (battle_anim_rock.c:478-506) loads the BG
tiles and tilemap, then explicitly loads gBattleAnimSpritePal_FlyingDirt —
i.e. flying_dirt.png's palette, NOT the background's own. That is a genuine
cross-file palette reference, the same shape as Thunder's
lightning.png/lightning_2.png case in Phase 5b.

Checked directly rather than assumed: sandstorm_brew.png's own embedded
palette is BYTE-IDENTICAL to flying_dirt.png's across all 16 colours. So the
embedded palette gives the correct result and no second pull is needed —
resolving the same way M26B3-6a's particle-palette question did. The
flying_dirt palette is still the one passed below, so the code matches
source's own stated intent rather than relying on a coincidence that a
future reference update could break. An assert pins the equality so that if
it ever stops holding, this script fails loudly instead of silently
rendering the wrong colours.

SNOWSCAPE — Rob's call, 2026-07-27
──────────────────────────────────
snowflakes.png is pulled. [D2 batch] permanently collapsed source's separate
Snow and Hail into this project's single WEATHER_HAIL, so Snowscape (move
809) sets hail here. Source keeps them distinct (B_WEATHER_SNOW /
B_ANIM_SNOW_CONTINUES), which forces a choice the collapse can't avoid:

  (a) pull snowflakes and give Snowscape its own authentic MOVE animation,
      with the per-turn replay showing hail (it follows weather STATE), or
  (b) map Snowscape to the hail animation throughout.

Rob chose (a): one extra flat copy for a visibly distinct move, and it keeps
the door open if Snow is ever un-collapsed. The residual divergence — a
Snowscape user sees snowflakes once, then hail each turn — is a KNOWN,
ACCEPTED consequence of the collapse, not a defect to be "fixed" later by
whoever next reads this file.
"""

import os
import struct

from PIL import Image

REF = "/home/rob/GodotAsImagined/reference/pokeemerald_expansion"
OUT = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "assets/sprites/battle_effects/weather",
)

SCREEN_BLOCK_TILES = 32

# (source relative path, destination filename, what consumes it)
SPRITES = [
    ("graphics/battle_anims/sprites/rain_drops.png", "rain_drops.png",
     "Rain Dance (move) + gBattleAnimGeneral_Rain (per-turn, shorter)"),
    ("graphics/battle_anims/sprites/sunlight.png", "sunlight.png",
     "Sunny Day — gSunlightRaySpriteTemplate, 4 rays"),
    ("graphics/battle_anims/sprites/flying_dirt.png", "flying_dirt.png",
     "Sandstorm — gFlyingSandCrescentSpriteTemplate, 7 crescents"),
    ("graphics/battle_anims/sprites/hail.png", "hail.png",
     "Hail — gHailParticleSpriteTemplate, via AnimTask_Hail"),
    ("graphics/battle_anims/sprites/snowflakes.png", "snowflakes.png",
     "Snowscape (move 809) — see the SNOWSCAPE note above"),
]


def png_embedded_palette(path):
    im = Image.open(path)
    flat = im.getpalette()
    return [tuple(flat[i:i + 3]) for i in range(0, len(flat), 3)]


def decode_screen_block(tiles_path, map_path, palette):
    """Standard GBA BG format: u16 screen entries, one 32x32-tile block.
    Phase 5a's own decode, reused unchanged via gen_ui_frames.py — this is
    its fourth successful application (Phase 5a backgrounds, Phase 5c's
    water.png, M25h-4's Bag/Party frames, and now this)."""
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
            bank = ((entry >> 12) & 0xF) % num_banks
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


def main():
    os.makedirs(OUT, exist_ok=True)
    written = []

    # ── Part A: particle/effect sprite sheets (flat copy + index-0 tag) ──
    for src_rel, dst_name, consumer in SPRITES:
        src = os.path.join(REF, src_rel)
        assert os.path.exists(src), f"missing source asset: {src}"
        im = Image.open(src)
        assert im.mode == "P", f"expected palette-mode source, got {im.mode}: {src}"
        dst = os.path.join(OUT, dst_name)
        im.info["transparency"] = 0
        im.save(dst, transparency=0)
        written.append((dst_name, im.size, consumer))

    # ── Part B: the sandstorm scrolling background (real decode) ──
    bg_tiles = os.path.join(REF, "graphics/battle_anims/backgrounds/sandstorm_brew.png")
    bg_map = os.path.join(REF, "graphics/battle_anims/backgrounds/sandstorm_brew.bin")
    dirt = os.path.join(REF, "graphics/battle_anims/sprites/flying_dirt.png")
    for p in (bg_tiles, bg_map, dirt):
        assert os.path.exists(p), f"missing source asset: {p}"

    # Source's own stated palette (see the SANDSTORM'S PALETTE note above).
    palette = png_embedded_palette(dirt)
    assert palette[:16] == png_embedded_palette(bg_tiles)[:16], (
        "sandstorm_brew.png's embedded palette no longer matches flying_dirt.png's. "
        "Source loads gBattleAnimSpritePal_FlyingDirt for this background "
        "(battle_anim_rock.c:498-500); the two being identical is what made the "
        "embedded palette safe. Re-check before trusting this decode."
    )

    canvas = decode_screen_block(bg_tiles, bg_map, palette)
    dst = os.path.join(OUT, "sandstorm_bg.png")
    canvas.save(dst)  # deliberately OPAQUE — BG layer, index 0 is a real colour
    written.append(("sandstorm_bg.png", canvas.size, "Sandstorm scrolling BG layer"))

    print(f"Wrote {len(written)} weather effect assets to {OUT}:")
    for name, size, consumer in written:
        print(f"  {name:20s} {size[0]:>4}x{size[1]:<4}  {consumer}")


if __name__ == "__main__":
    main()
