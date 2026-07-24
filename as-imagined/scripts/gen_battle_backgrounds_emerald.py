#!/usr/bin/env python3
"""
Replaces this project's 11 battle-background PNGs
(assets/sprites/battle_backgrounds/<id>.png) with real, already-composited
flat images pulled directly from the vendored Emerald UI Pack
(assets/Emerald UI Pack 1.2/Graphics/Battlebacks/<name>_bg.png) -- a plain
flat copy, no tile/tilemap/palette decoding involved (unlike Phase 5a's own
reconstruction attempts), since every `*_bg.png` in this pack is already a
single, complete, 512x288 composited image.

Supersedes M25e's own CFRU-pull for the 9 ids it covered, and finally
replaces sky/underwater's long-standing flawed Phase 5a reconstruction
(the two ids M25e explicitly could not find an acceptable CFRU replacement
for) -- every one of this project's 11 ids now sources from this one pack.

Mapping rationale (this pack has no per-id 1:1 name match -- these are
16 generic Essentials-style gradient backdrops, not scene-specific art):
  building    -> indoor1_bg.png  (plain neutral indoor gradient)
  cave        -> cave_bg.png     (real name match)
  long_grass  -> forest_bg.png   (denser/darker green than tall_grass)
  pond_water  -> swamp_bg.png    (a still, murky pond-like body)
  rock        -> desert_bg.png   (the pack has no dedicated rock asset --
                                   an arid/rocky tan is the closest fit)
  sand        -> sand_bg.png     (real name match)
  sky         -> arena1_bg.png   (the pack has no dedicated sky asset --
                                   the brightest/airiest of the 5 arena
                                   variants is the closest open-air fit;
                                   disclosed approximation, not a literal
                                   match, matching M25e's own precedent of
                                   flagging sky as unresolved rather than
                                   forcing a bad substitute)
  stadium     -> arena5_bg.png   (a distinct gym/arena-flavored purple)
  tall_grass  -> grass_bg.png    (a lighter, route-style grass field)
  underwater  -> sea_bg.png      (the most saturated/deep blue of the set)
  water       -> water_bg.png    (real name match, open water)

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
import shutil

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PACK_DIR = os.path.join(ROOT, "assets", "Emerald UI Pack 1.2", "Graphics", "Battlebacks")
OUT_DIR = os.path.join(ROOT, "assets", "sprites", "battle_backgrounds")

MAPPING = {
    "building": "indoor1_bg.png",
    "cave": "cave_bg.png",
    "long_grass": "forest_bg.png",
    "pond_water": "swamp_bg.png",
    "rock": "desert_bg.png",
    "sand": "sand_bg.png",
    "sky": "arena1_bg.png",
    "stadium": "arena5_bg.png",
    "tall_grass": "grass_bg.png",
    "underwater": "sea_bg.png",
    "water": "water_bg.png",
}


def main():
    for battle_id, source_name in sorted(MAPPING.items()):
        src = os.path.join(PACK_DIR, source_name)
        dst = os.path.join(OUT_DIR, f"{battle_id}.png")
        shutil.copyfile(src, dst)
        print(f"{battle_id}.png <- {source_name}")

    print(f"\n{len(MAPPING)} battle backgrounds replaced with Emerald UI Pack art.")
    print("Run a Godot editor reimport pass now (dimensions changed):")
    print('  /home/rob/Godot_v4.7.1-stable_linux.x86_64 --headless --editor --quit --path '
          f'{ROOT}')


if __name__ == "__main__":
    main()
