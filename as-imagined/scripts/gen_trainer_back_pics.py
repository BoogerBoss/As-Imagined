#!/usr/bin/env python3
"""
[M26B3-3] Copies trainer BACK-pic art from the read-only reference clone
into a project-owned, git-tracked asset directory.

Usage (from project root):
    python3 scripts/gen_trainer_back_pics.py

Why this exists: same rationale as gen_trainer_portraits.py /
gen_pokemon_sprites.py -- reference/pokeemerald_expansion/ is .gitignore'd
and not directly usable by production code, so this performs a one-time
(re-runnable, idempotent) flat copy of just the files this project needs
into res://assets/sprites/trainers/back_pics/, which IS committed.

Step 0 findings (2026-07-26, verified directly -- do not re-derive):

- Back pics are NOT 64x64 like the front pics this project already pulled.
  They are multi-frame VERTICAL strips of 64x64 cells:
      8 files at (64, 256) = 4 frames
      2 files at (64, 320) = 5 frames   <- red.png, leaf.png
      1 file  at (64,  64) = 1 frame    <- none.png
  The frame COUNT is also declared explicitly in source, in each trainer's
  own TRAINER_BACK_PIC(...) macro call (src/data/graphics/trainers.h) --
  the first argument. Leaf's reads TRAINER_BACK_PIC(5, ...), matching the
  320px height. Both agree, so the height/64 derivation used here is safe.

- Every file is PNG mode "P" (palette-indexed) with its own embedded
  palette (Leaf: 16 entries), exactly like the front pics -- so this is a
  genuine FLAT COPY. No decode, no palette compositing, no color-keying,
  unlike the tilemap-based assets (backgrounds, UI frames) other scripts
  in this directory have to reconstruct.

- The full set is pulled, not just Leaf. It is 11 files totalling well
  under a megabyte, and M26B3-4 (battle-end return) plus any future
  player-character choice would otherwise need a second near-identical
  script run. Pulling once is cheaper than pulling twice.

PLAYER-CHARACTER NOTE: this project has NO player-identity concept at all
(no trainer id, no gender, no name -- confirmed via a direct grep). Leaf
is the current PLACEHOLDER player character, Rob's call 2026-07-26, chosen
because this is a Kanto game and both Kanto back pics (red.png / leaf.png)
exist here as real 5-frame sheets. Nothing in this script hardcodes that
choice -- it pulls everything; the selection lives in battle_screen_shared
.gd's own _PLAYER_BACK_PIC constant.
"""

import os
import shutil

REFERENCE_DIR = (
    "/home/rob/GodotAsImagined/reference/pokeemerald_expansion/"
    "graphics/trainers/back_pics"
)
OUT_DIR = os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    "..", "assets", "sprites", "trainers", "back_pics",
)

# Frame counts as declared by each trainer's own TRAINER_BACK_PIC(N, ...)
# in src/data/graphics/trainers.h -- recorded here so a future session can
# cross-check the derived height/64 without re-reading source.
DECLARED_FRAMES = {
    "brendan.png": 4,
    "brendan_rs.png": 4,
    "leaf.png": 5,
    "may.png": 4,
    "may_rs.png": 4,
    "none.png": 1,
    "old_man.png": 4,
    "pokedude.png": 4,
    "red.png": 5,
    "steven.png": 4,
    "wally.png": 4,
}


def main() -> None:
    out = os.path.normpath(OUT_DIR)
    os.makedirs(out, exist_ok=True)

    if not os.path.isdir(REFERENCE_DIR):
        raise SystemExit("reference back_pics dir not found: %s" % REFERENCE_DIR)

    copied = 0
    for name in sorted(os.listdir(REFERENCE_DIR)):
        if not name.endswith(".png"):
            continue
        src = os.path.join(REFERENCE_DIR, name)
        dst = os.path.join(out, name)
        shutil.copyfile(src, dst)
        copied += 1

        # Cross-check the strip against source's own declared frame count.
        # Deliberately a warning rather than a hard failure: a mismatch
        # means the reference tree moved on, which is a real finding worth
        # surfacing, not a reason to leave the asset unpulled.
        try:
            from PIL import Image
            with Image.open(dst) as im:
                w, h = im.size
            declared = DECLARED_FRAMES.get(name)
            derived = h // 64
            flag = ""
            if w != 64 or h % 64 != 0:
                flag = "  <-- UNEXPECTED SIZE (not a 64xN strip)"
            elif declared is not None and declared != derived:
                flag = "  <-- FRAME COUNT MISMATCH (source declares %d)" % declared
            print("  %-16s %sx%s  %d frames%s" % (name, w, h, derived, flag))
        except ImportError:
            print("  %s (Pillow absent -- size not verified)" % name)

    print("gen_trainer_back_pics: copied %d files -> %s" % (copied, out))


if __name__ == "__main__":
    main()
