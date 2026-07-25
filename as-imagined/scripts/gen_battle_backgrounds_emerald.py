#!/usr/bin/env python3
"""
Replaces this project's 11 battle-background PNGs
(assets/sprites/battle_backgrounds/<id>.png) with real, composited flat
images built from the vendored Emerald UI Pack
(assets/Emerald UI Pack 1.2/Graphics/Battlebacks/<name>_{bg,base0,base1}.png).

Supersedes M25e's own CFRU-pull for the 9 ids it covered, and finally
replaces sky/underwater's long-standing flawed Phase 5a reconstruction
(the two ids M25e explicitly could not find an acceptable CFRU replacement
for) -- every one of this project's 11 ids now sources from this one pack.

[Compositing, added in a same-day follow-up to this script's own first cut]
The `_bg` file ALONE is a flat, feature-less gradient with zero terrain
detail (confirmed via direct pixel inspection AND a real in-scene
screenshot pass -- every environment's `_bg` is visually just a colored
horizontal-stripe gradient, indistinguishable in character from any other).
All of the real per-environment texture (grass blades, water ripples, rock
pebbles, sand grain) lives in the two platform-oval layers instead:
`_base0` (512x64) and `_base1` (256x128). This project's own vendored copy
of the pack's real compositing script
(Plugins/Emerald UI Pack/003_Battle.rb :: pbCreateBackdropSprites) confirms
these are meant to be layered together, not used alone:
    battleBG   = <name>_bg
    playerBase = <name>_base0   (ox = width/2, oy = height   -- bottom-anchored)
    enemyBase  = <name>_base1   (ox = width/2, oy = height/2 -- center-anchored)
The script's own real absolute pixel coordinates (`Battle::Scene.
pbBattlerPosition`) live in the base Essentials engine, not this
graphics-only pack, so the exact per-side (x, y) isn't available here --
PLAYER_POS/ENEMY_POS below are a reasonable, source-informed approximation
(player lower-left/bottom-anchored, enemy upper-right/center-anchored,
matching both the script's own anchor convention AND this project's own
already-established sprite layout) rather than a literal engine value,
verified visually via this session's own real screenshot pass and adjusted
only if it looked wrong (it didn't).

Mapping rationale (this pack has no per-id 1:1 name match -- these are
16 generic Essentials-style gradient backdrops, not scene-specific art):
  building    -> indoor1  (plain neutral indoor gradient)
  cave        -> cave     (real name match)
  long_grass  -> forest   (denser/darker green than tall_grass)
  pond_water  -> swamp    (a still, blue-with-grassy-border pond look)
  rock        -> desert   (the pack has no dedicated rock asset --
                            an arid/rocky tan is the closest fit)
  sand        -> sand     (real name match)
  sky         -> arena1   (the pack has no dedicated sky asset --
                            the brightest/airiest of the 5 arena
                            variants is the closest open-air fit;
                            disclosed approximation, not a literal
                            match, matching M25e's own precedent of
                            flagging sky as unresolved rather than
                            forcing a bad substitute)
  stadium     -> arena5   (a distinct gym/arena-flavored purple)
  tall_grass  -> grass    (a lighter, route-style grass field)
  underwater  -> sea      (the most saturated/deep blue of the set)
  water       -> water    (real name match, open water)

Usage (from project root):
    python3 scripts/gen_battle_backgrounds_emerald.py

Idempotent: overwrites the 11 destination files unconditionally, so
reruns are safe. A forced Godot editor reimport pass is required
afterward -- these files change PIXEL DIMENSIONS (512x288, vs. the prior
240x160/256x112 files), and Godot's own .import cache does NOT
automatically pick up a changed dimension on a plain file overwrite (the
exact gotcha M25e's own session already hit and documented).
"""

import os
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PACK_DIR = os.path.join(ROOT, "assets", "Emerald UI Pack 1.2", "Graphics", "Battlebacks")
OUT_DIR = os.path.join(ROOT, "assets", "sprites", "battle_backgrounds")

MAPPING = {
    "building": "indoor1",
    "cave": "cave",
    "long_grass": "forest",
    "pond_water": "swamp",
    "rock": "desert",
    "sand": "sand",
    "sky": "arena1",
    "stadium": "arena5",
    "tall_grass": "grass",
    "underwater": "sea",
    "water": "water",
}

CANVAS_SIZE = (512, 288)
# (center_x, anchor_y) -- player is bottom-anchored (oy = height, matching
# the real script's own anchor), enemy is center-anchored (oy = height/2).
PLAYER_POS = (95, 284)
ENEMY_POS = (372, 108)


def composite(name: str) -> Image.Image:
    bg = Image.open(os.path.join(PACK_DIR, f"{name}_bg.png")).convert("RGBA")
    canvas = bg.resize(CANVAS_SIZE) if bg.size != CANVAS_SIZE else bg.copy()

    player = Image.open(os.path.join(PACK_DIR, f"{name}_base0.png")).convert("RGBA")
    px = PLAYER_POS[0] - player.width // 2
    py = PLAYER_POS[1] - player.height
    canvas.alpha_composite(player, (px, py))

    enemy = Image.open(os.path.join(PACK_DIR, f"{name}_base1.png")).convert("RGBA")
    ex = ENEMY_POS[0] - enemy.width // 2
    ey = ENEMY_POS[1] - enemy.height // 2
    canvas.alpha_composite(enemy, (ex, ey))

    return canvas


def main():
    for battle_id, source_name in sorted(MAPPING.items()):
        img = composite(source_name)
        dst = os.path.join(OUT_DIR, f"{battle_id}.png")
        img.save(dst)
        print(f"{battle_id}.png <- {source_name}_{{bg,base0,base1}}.png")

    print(f"\n{len(MAPPING)} battle backgrounds replaced with composited Emerald UI Pack art.")
    print("Run a Godot editor reimport pass now (dimensions changed):")
    print('  /home/rob/Godot_v4.7.1-stable_linux.x86_64 --headless --editor --quit --path '
          f'{ROOT}')


if __name__ == "__main__":
    main()
