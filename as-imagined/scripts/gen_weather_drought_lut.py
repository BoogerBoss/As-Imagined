#!/usr/bin/env python3
"""
[M27N] Bakes source's real Drought colour-remap table into one PNG texture
this project's own weather shader can sample directly.

Usage (from anywhere; paths are absolute per this project's standing rule):
    python3 scripts/gen_weather_drought_lut.py

Source's own mechanism (`field_weather.c`) is a GENUINELY SEPARATE
mechanism from the 19x32 `sDarkenedContrastColorMaps` curve every other
palette-grade weather type (Shade/Sunny/None) already uses — see
`weather_color_maps.gd`'s own doc comment for that one. Drought maps a
whole RGB triplet to a new RGB triplet via a direct 3D lookup, not a
per-channel remap:

    sDroughtWeatherColors[stage][DROUGHT_COLOR_INDEX(color)]

`DROUGHT_COLOR_INDEX(color) = ((color>>1)&0xF) | ((color>>2)&0xF0) | ((color>>3)&0xF00)`
drops each 5-bit RGB555 channel's LSB, keeping only its top 4 bits (0-15),
and packs the three nibbles into one 12-bit (4096-entry) index — i.e. the
index is exactly `r4 | (g4<<4) | (b4<<8)` where `r4/g4/b4 = channel >> 1`.

Six real binary files ship the table, one per Drought "stage" (0-5, the
6-step brightness ramp `DroughtStateRun` walks through):
`graphics/weather/drought/colors_0.bin` .. `colors_5.bin` — CONFIRMED via
direct `INCBIN_U16` citation (`field_weather.c:114-119`), NOT the
similarly-named `graphics/weather/drought0.bin`..`drought5.bin` siblings
one directory up, which are a different, unrelated asset. Each file is
8192 bytes = 4096 u16 little-endian RGB555 values (r | g<<5 | b<<10),
already ordered by the exact `DROUGHT_COLOR_INDEX` formula above — i.e.
entry `r4 | (g4<<4) | (b4<<8)` of the file IS the table's answer for that
index, no further reordering needed.

Output layout: one 256x96 RGB image, flattened as (r4, g4) -> the 256-wide
X axis (`col = r4 + g4*16`) and (b4, stage) -> the 96-tall Y axis
(`row = b4 + stage*16`) — 16 stages... no, 6 stages x 16 b4-levels = 96
rows. A single sampler2D lookup per pixel (`texture(drought_lut, vec2(
(col+0.5)/256.0, (row+0.5)/96.0))`) then returns the target colour
directly, no per-channel recombination needed on the shader side.
"""

import os
import struct

from PIL import Image

REF = "/home/rob/GodotAsImagined/reference/pokeemerald_expansion"
OUT_DIR = "/home/rob/GodotAsImagined/as-imagined/assets/weather"
OUT_PATH = os.path.join(OUT_DIR, "drought_lut.png")

NUM_STAGES = 6
LEVELS = 16  # 4-bit per channel, after dropping each 5-bit channel's LSB
TABLE_SIZE = LEVELS * LEVELS * LEVELS  # 4096

WIDTH = LEVELS * LEVELS  # 256 (r4, g4 combined)
HEIGHT = LEVELS * NUM_STAGES  # 96 (b4, stage combined)


def _decode_rgb555(value):
    r5 = value & 0x1F
    g5 = (value >> 5) & 0x1F
    b5 = (value >> 10) & 0x1F
    # 5-bit -> 8-bit, matching this project's own established RGB555->RGB888
    # expansion convention elsewhere (replicate the top bits into the gap
    # rather than a bare *8, which would leave 31 short of 255).
    return (
        (r5 << 3) | (r5 >> 2),
        (g5 << 3) | (g5 >> 2),
        (b5 << 3) | (b5 >> 2),
    )


def _load_stage(stage):
    path = os.path.join(REF, "graphics", "weather", "drought", "colors_%d.bin" % stage)
    with open(path, "rb") as f:
        data = f.read()
    assert len(data) == TABLE_SIZE * 2, (
        "colors_%d.bin is %d bytes, expected %d (4096 u16 values)"
        % (stage, len(data), TABLE_SIZE * 2)
    )
    values = struct.unpack("<%dH" % TABLE_SIZE, data)
    return values


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    img = Image.new("RGB", (WIDTH, HEIGHT))
    pixels = img.load()

    for stage in range(NUM_STAGES):
        values = _load_stage(stage)
        for b4 in range(LEVELS):
            for g4 in range(LEVELS):
                for r4 in range(LEVELS):
                    idx = r4 | (g4 << 4) | (b4 << 8)
                    rgb = _decode_rgb555(values[idx])
                    col = r4 + g4 * LEVELS
                    row = b4 + stage * LEVELS
                    pixels[col, row] = rgb

    img.save(OUT_PATH)
    print("gen_weather_drought_lut: wrote %s (%dx%d, %d stages)"
            % (OUT_PATH, WIDTH, HEIGHT, NUM_STAGES))


if __name__ == "__main__":
    main()
