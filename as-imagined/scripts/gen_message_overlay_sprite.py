#!/usr/bin/env python3
"""
Pulls the real always-visible message-box overlay art from the already-
vendored Emerald UI Pack 1.2 (assets/Emerald UI Pack 1.2/, the same pack
gen_databox_sprites.py already sources from), for the new source-accurate
message-box pacing work (real games scroll this same screen slot between
the action menu and message text -- see battle_screen.gd's own
_setup_message_overlay_panel() doc comment for the full citation).

Usage (from project root):
    python3 scripts/gen_message_overlay_sprite.py

Step 0 finding (measured directly via PIL pixel inspection, not assumed):
unlike gen_databox_sprites.py's own 4 files, overlay_message.png does NOT
carry real PNG alpha -- every corner samples as a flat, fully-opaque
background color (74,66,82,255), with a red border band (214,74,57,255)
and a teal interior fill (107,165,165,255). This is the SAME shape as the
already-vendored text_window/1.png/std.png assets (color-keyed at RUNTIME
via battle_screen.gd's own _color_keyed_texture(), not baked in here) --
so, like those, this script does a pure flat copy and leaves the actual
transparency-keying to the runtime helper, NOT gen_databox_sprites.py's
"already has real alpha, flat copy is final" treatment.
"""

import os
from PIL import Image

PACK_BATTLE_DIR = os.path.join(
    "assets", "Emerald UI Pack 1.2", "Graphics", "UI", "Battle")
OUT_DIR = os.path.join("assets", "sprites", "battle_ui", "interface")

FILES = [
    ("overlay_message.png", "message_overlay.png"),
]


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    for src_name, dst_name in FILES:
        src_path = os.path.join(PACK_BATTLE_DIR, src_name)
        dst_path = os.path.join(OUT_DIR, dst_name)
        img = Image.open(src_path).convert("RGBA")
        img.save(dst_path)
        print(f"{src_name} ({img.size[0]}x{img.size[1]}) -> {dst_path}")


if __name__ == "__main__":
    main()
