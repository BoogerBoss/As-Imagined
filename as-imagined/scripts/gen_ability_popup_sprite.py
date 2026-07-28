#!/usr/bin/env python3
"""
[M26B6-1] Re-pulls the ability-activation popup panel with palette index 0
tagged transparent.

Usage (from project root):
    python3 scripts/gen_ability_popup_sprite.py

Full recon: docs/m26_b6_recon.md.

WHY THIS SCRIPT EXISTS
──────────────────────
`assets/sprites/battle_ui/interface/ability_pop_up.png` was ALREADY present
before M26B6 — pulled during M23.11 Phase 1's battle-HUD chrome pass, and
verified pixel-identical to the reference. But that pass was a plain filtered
copy, and this file carries NO tRNS chunk while palette index 0 IS its
transparency key: index 0 occupies all four corners and 1202 of 4096 pixels
(29%), colour (1, 177, 91) — a green key. Rendered as-is, the popup appears
inside an opaque green box.

Same defect and same fix as [M26B3-6a]'s ball sheets and
gen_hit_effect_sprites.py: tag the INDEX, never colour-key a value (index 0 is
not a constant colour across this project's pulled assets).

The separate `ability_pop_up.pal` in the reference is NOT pulled: it is
byte-identical to the PNG's own embedded palette across all 16 colours
(checked), so the embedded palette already gives correct output. An assert
below pins that, so a future reference update that breaks the equality fails
loudly rather than silently recolouring the panel.

SCOPE — deliberately ONE file
─────────────────────────────
An audit of all 57 files in battle_ui/interface/ found **18** with this same
shape (no tRNS, index 0 on all four corners). This script fixes only the one
M26B6 needs, because it is the only one with ZERO consumers and therefore zero
regression risk. The rest are recorded as a flagged finding in
docs/m26_b6_recon.md rather than swept up here — blanket-tagging assets that
currently render acceptably could break working visuals, and two of them
(party_hold_icons.png, party_status_icons.png) are live on the Switch/Party
screen that M25h-4 already screenshot-verified.
"""

import os

from PIL import Image

REF = "/home/rob/GodotAsImagined/reference/pokeemerald_expansion"
SRC = os.path.join(REF, "graphics/battle_interface/ability_pop_up.png")
PAL = os.path.join(REF, "graphics/battle_interface/ability_pop_up.pal")
OUT = os.path.normpath(os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    "..", "assets/sprites/battle_ui/interface/ability_pop_up.png"))

EXPECTED_SIZE = (128, 32)  # two 64x32 OAM halves in source; one node here


def load_jasc_pal(path):
    lines = open(path, encoding="utf-8").read().split()
    n = int(lines[2])
    return [tuple(int(v) for v in lines[3 + i * 3:6 + i * 3]) for i in range(n)]


def main():
    assert os.path.exists(SRC), f"missing source asset: {SRC}"
    im = Image.open(SRC)
    assert im.mode == "P", f"expected palette-mode source, got {im.mode}"
    assert im.size == EXPECTED_SIZE, f"expected {EXPECTED_SIZE}, got {im.size}"

    # Source pairs this sheet with a SEPARATE palette file. Pin the equality
    # that makes ignoring it safe (same check gen_weather_effect_sprites.py
    # makes for the sandstorm background).
    if os.path.exists(PAL):
        embedded = [tuple(im.getpalette()[i * 3:i * 3 + 3]) for i in range(16)]
        assert load_jasc_pal(PAL)[:16] == embedded, (
            "ability_pop_up.pal no longer matches the PNG's embedded palette. "
            "Source loads the .pal separately (sSpritePalette_AbilityPopUp); the "
            "two being identical is what made the embedded one safe to rely on. "
            "Re-check before trusting this pull.")

    px = im.load()
    w, h = im.size
    corners = [px[0, 0], px[w - 1, 0], px[0, h - 1], px[w - 1, h - 1]]
    assert all(c == 0 for c in corners), (
        f"expected palette index 0 at all four corners, got {corners} -- the "
        "transparency-key assumption behind this script no longer holds.")

    im.info["transparency"] = 0
    im.save(OUT, transparency=0)

    check = Image.open(OUT)
    assert check.info.get("transparency") == 0, "tRNS was not written"
    print(f"Wrote {OUT}")
    print(f"  {w}x{h} mode={check.mode} tRNS=0 "
          f"(index 0 = {tuple(im.getpalette()[0:3])}, the green key)")


if __name__ == "__main__":
    main()
