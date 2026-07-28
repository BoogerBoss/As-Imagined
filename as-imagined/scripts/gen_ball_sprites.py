#!/usr/bin/env python3
"""
[M26B3-6 assets] Copies pokeball sprite sheets and the shared ball-open
particle sheet from the read-only reference clone into project-owned,
git-tracked asset directories.

Usage (from project root):
    python3 scripts/gen_ball_sprites.py

Same rationale as gen_trainer_back_pics.py / gen_trainer_portraits.py:
reference/pokeemerald_expansion/ is .gitignore'd and not usable by
production code, so this is a re-runnable flat copy of what this project
actually needs.

Step 0 findings (2026-07-26, verified directly):

- Ball sheets are 16x48 mode-"P" = 3 VERTICAL frames of 16x16 (closed ->
  opening -> open). 29 ball types exist. Flat copy, no decode.

- The ball-open particles are ONE SHARED SHEET for every ball type, not a
  per-ball set: all 29 POKE_BALL_ANIMATION entries in
  `src/battle_anim_throw.c` pass the same `gBattleAnimSpriteGfx_Particles`
  (+ `gBattleAnimSpritePal_CircleImpact`); only the sprite TAG differs.
  That resolves to `graphics/battle_anims/sprites/particles.png`
  (`src/graphics.c:837`), 8x64 mode-"P".
  This was the open unknown left by B3-6's original scoping ("candidates
  sit in graphics/battle_anims/sprites/ -- particles.png, particles2.png,
  gold_stars.png -- none confirmed"); it is now confirmed, and it is
  particles.png.

- Particles are used by the RECALL too, not just the throw. The recall
  anim script lists only two tasks (`gBattleAnimSpecial_SwitchOutPlayerMon`,
  data/battle_anim_scripts.s:29942) but the first of them,
  `AnimTask_SwitchOutBallEffect`, calls `AnimateBallOpenParticles`
  internally.

Only BALL_POKE is consumed today. The full set is pulled because it is a
handful of tiny files and the alternative is a second near-identical
script run when catch UI (M26B7) or ball variety arrives.

TRANSPARENCY NOTE (fixed 2026-07-26, after a flat copy shipped opaque):
these sheets carry NO PNG tRNS chunk, and palette index 0 is the intended
transparent background per the universal GBA OBJ-layer rule -- the same
situation `gen_hit_effect_sprites.py` already had to handle (see its own
line `im.info["transparency"] = 0`). A plain shutil.copyfile is therefore
NOT sufficient here, unlike the Pokemon-sprite/trainer-pic pulls.

Index 0 is NOT a fixed colour across these files -- sampled directly:
poke.png's is white (255,255,255) while particles.png's is purple
(98,41,255) -- so colour-keying a single hardcoded value would be wrong.
Tagging index 0 is the correct generic rule.

The first cut of this script did a flat copy, and the ball rendered on
screen inside an opaque white box.
"""

import os
import shutil

from ref_path import REF

BALLS_SRC = os.path.join(REF, "graphics", "balls")
PARTICLES_SRC = os.path.join(
    REF, "graphics", "battle_anims", "sprites", "particles.png")

_HERE = os.path.dirname(os.path.abspath(__file__))
BALLS_OUT = os.path.normpath(
    os.path.join(_HERE, "..", "assets", "sprites", "battle_ui", "balls"))
# Deliberately NOT battle_effects/generic/ -- that directory holds the 21
# curated HIT-effect sprites and `hit_effect_smoke_test` asserts its exact
# contents. A ball-open burst is not a hit effect; it lives with the balls.
# (A first cut put it in generic/ and broke that test's count.)
PARTICLES_OUT = BALLS_OUT


def _copy_with_index0_transparent(src: str, dst: str) -> None:
    """Copy a palette-indexed sheet, tagging palette index 0 transparent.

    Falls back to a plain copy only if Pillow is unavailable, which would
    leave the asset opaque -- loud rather than silent, since that is a real
    visual defect (see this module's own TRANSPARENCY NOTE)."""
    try:
        from PIL import Image
    except ImportError:
        shutil.copyfile(src, dst)
        print("  !! Pillow absent -- %s copied OPAQUE" % os.path.basename(dst))
        return
    with Image.open(src) as im:
        if im.mode != "P":
            shutil.copyfile(src, dst)
            return
        im.info["transparency"] = 0
        im.save(dst, transparency=0)


def _report(path: str, expect_w: int, frame_h: int) -> str:
    try:
        from PIL import Image
        with Image.open(path) as im:
            w, h = im.size
        note = ""
        if w != expect_w or h % frame_h != 0:
            note = "  <-- UNEXPECTED SIZE"
        return "%sx%s  %d frames%s" % (w, h, h // frame_h, note)
    except ImportError:
        return "(Pillow absent -- size not verified)"


def main() -> None:
    os.makedirs(BALLS_OUT, exist_ok=True)

    if not os.path.isdir(BALLS_SRC):
        raise SystemExit("reference balls dir not found: %s" % BALLS_SRC)

    copied = 0
    for name in sorted(os.listdir(BALLS_SRC)):
        if not name.endswith(".png"):
            continue
        dst = os.path.join(BALLS_OUT, name)
        _copy_with_index0_transparent(os.path.join(BALLS_SRC, name), dst)
        copied += 1
        print("  ball %-14s %s" % (name, _report(dst, 16, 16)))

    if not os.path.isfile(PARTICLES_SRC):
        raise SystemExit("particles.png not found: %s" % PARTICLES_SRC)
    pdst = os.path.join(PARTICLES_OUT, "particles.png")
    _copy_with_index0_transparent(PARTICLES_SRC, pdst)
    print("  particles      %s" % _report(pdst, 8, 8))

    print("gen_ball_sprites: %d balls -> %s" % (copied, BALLS_OUT))
    print("gen_ball_sprites: particles -> %s" % pdst)


if __name__ == "__main__":
    main()


# [M26B5] The party-status BAR -- the black gradient strip that sits BEHIND
# the 6 ball icons (`sStatusSummaryBarSpriteTemplates`, battle_interface.c
# :1266, created at layer 10 vs the balls' 9). Sourced from
# graphics/battle_interface/ball_status_bar.png, 128x8 mode-"P".
#
# Same index-0 transparency rule as the ball sheets above -- no tRNS chunk,
# palette index 0 is the intended background. A plain shutil.copyfile ships
# it opaque.
BALL_STATUS_BAR_SRC = os.path.join(
    REF, "graphics", "battle_interface", "ball_status_bar.png")


def pull_status_bar() -> None:
    out_dir = os.path.normpath(os.path.join(
        _HERE, "..", "assets", "sprites", "battle_ui", "party_status"))
    os.makedirs(out_dir, exist_ok=True)
    dst = os.path.join(out_dir, "ball_status_bar.png")
    _copy_with_index0_transparent(BALL_STATUS_BAR_SRC, dst)
    print("  party status bar -> %s" % dst)
