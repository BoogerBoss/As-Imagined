#!/usr/bin/env python3
"""
[M27N W3] Pulls the tiled-scroll weather sprite sheets: FOG_HORIZONTAL,
VOLCANIC_ASH, and SANDSTORM's base layer (the 5 orbiting "dust devil"
sprites are a later, explicitly separate phase).

Usage (from anywhere; paths are absolute per this project's standing rule):
    python3 scripts/gen_weather_tile_sprites.py

Real graphics, confirmed on disk before pulling:
  graphics/weather/fog_horizontal.png  (64x64, P-mode/4bpp indexed)
  graphics/weather/ash.png             (64x128, two 64x64 frames stacked
                                         vertically)
  graphics/weather/sandstorm.png       (64x80)

PALETTE SPLIT, confirmed via direct source citation (`field_weather.c:195,
201-202` and `field_weather_effect.c:23,2150`): Fog and Ash BOTH use
`PALTAG_WEATHER`, loaded once from the external `graphics/weather/fog.pal`
-- i.e. Ash's own sheet is drawn with FOG's palette, not one embedded in
ash.png. Sandstorm uses its own separate `PALTAG_WEATHER_2`
(`LoadCustomWeatherSpritePalette(gSandstormWeatherPalette)`), extracted
directly from sandstorm.png's own embedded palette -- no external `.pal`
file for Sandstorm. This mirrors `gen_object_event_sprites.py`'s own
established "indexed PNG + possibly-separate external .pal" pattern
(`load_pal()` + palette-mismatch-detect-and-recolor), reused directly here
rather than inventing a second asset-pull shape.

Every file is tagged index-0-transparent on save, matching the universal
GBA convention this project already applies to every other pulled sprite
sheet (none of these carry a real tRNS chunk).
"""

import os

from PIL import Image

REF = "/home/rob/GodotAsImagined/reference/pokeemerald_expansion"
OUT_DIR = "/home/rob/GodotAsImagined/as-imagined/assets/weather"

FOG_SRC = os.path.join(REF, "graphics/weather/fog_horizontal.png")
ASH_SRC = os.path.join(REF, "graphics/weather/ash.png")
SANDSTORM_SRC = os.path.join(REF, "graphics/weather/sandstorm.png")
FOG_PAL = os.path.join(REF, "graphics/weather/fog.pal")


def load_pal(path):
    """JASC-PAL -> flat [r,g,b, r,g,b, ...] for the first 16 entries."""
    lines = open(path).read().split("\n")
    n = int(lines[2])
    out = []
    for i in range(min(16, n)):
        out += [int(v) for v in lines[3 + i].split()]
    return out


def _pull_with_external_pal(src, dst, pal_path):
    im = Image.open(src)
    assert im.mode == "P", "%s is %s, expected indexed" % (src, im.mode)
    want = load_pal(pal_path)
    have = im.getpalette()[:len(want)]
    recoloured = False
    if have != want:
        full = im.getpalette()
        full[:len(want)] = want
        im.putpalette(full)
        recoloured = True
    im.info["transparency"] = 0
    im.save(dst)
    return recoloured


def _pull_own_palette(src, dst):
    im = Image.open(src)
    assert im.mode == "P", "%s is %s, expected indexed" % (src, im.mode)
    im.info["transparency"] = 0
    im.save(dst)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)

    fog_recoloured = _pull_with_external_pal(
        FOG_SRC, os.path.join(OUT_DIR, "fog_horizontal.png"), FOG_PAL)
    ash_recoloured = _pull_with_external_pal(
        ASH_SRC, os.path.join(OUT_DIR, "ash.png"), FOG_PAL)
    _pull_own_palette(SANDSTORM_SRC, os.path.join(OUT_DIR, "sandstorm.png"))

    print("gen_weather_tile_sprites: pulled fog_horizontal.png, ash.png, "
            "sandstorm.png -> %s (fog recoloured=%s, ash recoloured=%s)"
            % (OUT_DIR, fog_recoloured, ash_recoloured))


if __name__ == "__main__":
    main()
