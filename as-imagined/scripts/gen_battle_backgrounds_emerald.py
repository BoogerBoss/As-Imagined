#!/usr/bin/env python3
"""
Populates this project's battle-background assets
(assets/sprites/battle_backgrounds/<id>_{bg,base0,base1}.png) from the
vendored Emerald UI Pack
(assets/Emerald UI Pack 1.2/Graphics/Battlebacks/<name>_{bg,base0,base1}.png).

[M26 polish batch, item 1 -- supersedes this script's own earlier
compositing approach] Previously this script FLATTENED all three source
layers into one composited <id>.png per background, baked at generation
time via a hardcoded PLAYER_POS/ENEMY_POS approximation. Per explicit
request, the three layers are no longer merged into one texture at all --
_bg is the single full-screen backdrop (already 512x288, no per-side
positioning need of its own), while _base0 (player-side platform, 512x64)
and _base1 (enemy-side platform, 256x128) are each pulled as their OWN
separate file and wired to their OWN separate, independently-positioned
TextureRect node in the scene (Background/PlayerBase/EnemyBase under
BattleStage in battle_screen_singles.tscn/battle_screen_doubles.tscn) --
editable/repositionable per-background in the Godot editor, not baked into
one flattened image the way the old approach required a full regeneration
pass to adjust.

This is a pure per-file copy now, not a composite -- confirmed via direct
PIL inspection that every one of the 11 mapped source names' three files
are already uniformly sized (bg=512x288, base0=512x64, base1=256x128), so
no resizing step is needed either.

Supersedes M25e's own CFRU-pull for the 9 ids it covered, and replaces
sky/underwater's long-standing flawed Phase 5a reconstruction (the two ids
M25e explicitly could not find an acceptable CFRU replacement for) -- every
one of this project's 11 ids still sources from this one pack, just as 3
separate files each instead of 1 flattened composite.

PLAYER_POS/ENEMY_POS below are kept only as the STARTING anchor/offset
values baked into the two new .tscn nodes at authoring time (see
battle_screen_singles.tscn/battle_screen_doubles.tscn's own PlayerBase/
EnemyBase nodes) -- a reasonable, source-informed approximation (player
lower-left/bottom-anchored, enemy upper-right/center-anchored, matching
Plugins/Emerald UI Pack/003_Battle.rb :: pbCreateBackdropSprites' own real
anchor convention) rather than a literal engine value, since the real
absolute pixel coordinates (`Battle::Scene.pbBattlerPosition`) live in the
base Essentials engine, not this graphics-only pack. Editable per-background
afterward directly in the editor, which is the whole point of this change.

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

Idempotent: overwrites the 33 destination files (11 ids x 3 layers)
unconditionally, so reruns are safe. A forced Godot editor reimport pass is
required afterward if any file's own pixel dimensions changed since the
last run -- Godot's own .import cache does NOT automatically pick up a
changed dimension on a plain file overwrite (the exact gotcha M25e's own
session already hit and documented).
"""

import os
import shutil

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

# [Scene-authoring reference only -- see this file's own doc comment above]
# Not used by this script itself anymore; kept here as the single source of
# truth for the values PlayerBase/EnemyBase were authored with in the .tscn
# files, so a future re-tuning pass has the original reasoning in one place.
PLAYER_POS = (95, 284)  # bottom-anchored (oy = full canvas height)
ENEMY_POS = (372, 108)  # center-anchored (oy = canvas height / 2)

LAYERS = ("bg", "base0", "base1")


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for battle_id, source_name in sorted(MAPPING.items()):
        for layer in LAYERS:
            src = os.path.join(PACK_DIR, f"{source_name}_{layer}.png")
            dst = os.path.join(OUT_DIR, f"{battle_id}_{layer}.png")
            shutil.copyfile(src, dst)
        print(f"{battle_id}_{{bg,base0,base1}}.png <- {source_name}_{{bg,base0,base1}}.png")

    print(f"\n{len(MAPPING)} battle backgrounds populated as 3 separate layers each "
          f"({len(MAPPING) * 3} files) from the Emerald UI Pack.")
    print("Run a Godot editor reimport pass now if any dimensions changed:")
    print('  /home/rob/Godot_v4.7.1-stable_linux.x86_64 --headless --editor --quit --path '
          f'{ROOT}')


if __name__ == "__main__":
    main()
