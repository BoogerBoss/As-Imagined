class_name WeatherColorMaps
extends RefCounted

## [M27N] Source's real `sDarkenedContrastColorMaps` (field_weather.c:65-83),
## transcribed verbatim — a 19-row x 32-column per-channel gamma remap curve.
## Row = `color_map_index` (1-19, 1-based in source; here 0-based, row 0 is
## source's row 1 since source's index 0 is "no grading" and never looks
## this table up at all — see WeatherManager). Column = the ORIGINAL 0-31
## channel value; the cell is the REPLACEMENT value.
##
## This is the "everything except the player" curve — source's own gentler
## `sContrastColorMaps` (applied to the player + weather-effect sprites'
## own palette bank) is deliberately NOT ported: this project's shader is
## mounted per-TERRAIN-PLANE only (Ground/Objects/Overhangs), never on the
## player/NPC entity layers, so the player is excluded from grading by
## construction rather than needing a second, gentler curve. See
## WeatherManager's own doc comment for the full reasoning.
const NUM_ROWS := 19
const NUM_COLS := 32

const DARKENED_CONTRAST: Array[int] = [
	0, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29,
	0, 0, 1, 2, 3, 4, 5, 6, 7, 7, 8, 9, 10, 11, 12, 13, 14, 14, 15, 16, 17, 18, 19, 20, 21, 21, 22, 23, 24, 25, 26, 27,
	0, 0, 1, 2, 3, 4, 4, 5, 6, 7, 8, 8, 9, 10, 11, 12, 13, 13, 14, 15, 16, 17, 17, 18, 19, 20, 21, 21, 22, 23, 24, 25,
	0, 1, 2, 3, 4, 4, 5, 6, 7, 8, 8, 9, 11, 11, 12, 13, 14, 14, 15, 16, 17, 17, 18, 19, 20, 20, 21, 22, 23, 24, 24, 25,
	1, 2, 3, 3, 4, 5, 6, 6, 7, 8, 9, 9, 12, 13, 13, 14, 15, 15, 16, 17, 18, 18, 19, 20, 20, 21, 22, 23, 23, 24, 25, 25,
	1, 2, 3, 4, 4, 5, 6, 7, 7, 8, 9, 10, 13, 14, 15, 15, 16, 17, 17, 18, 19, 19, 20, 20, 21, 22, 22, 23, 24, 24, 25, 26,
	1, 2, 3, 4, 4, 5, 6, 7, 7, 8, 9, 10, 15, 15, 16, 16, 17, 18, 18, 19, 19, 20, 21, 21, 22, 22, 23, 24, 24, 25, 26, 26,
	1, 2, 3, 4, 4, 5, 6, 7, 7, 8, 9, 10, 16, 16, 17, 18, 18, 19, 19, 20, 20, 21, 21, 22, 23, 23, 24, 24, 25, 25, 26, 27,
	1, 2, 3, 4, 4, 5, 6, 7, 8, 8, 9, 10, 17, 18, 18, 19, 19, 20, 20, 21, 21, 22, 22, 23, 23, 24, 24, 25, 25, 26, 26, 27,
	1, 2, 3, 4, 4, 5, 6, 7, 8, 8, 9, 10, 19, 19, 19, 20, 20, 21, 21, 22, 22, 23, 23, 24, 24, 24, 25, 25, 26, 26, 27, 27,
	1, 2, 3, 4, 4, 5, 6, 7, 8, 8, 9, 10, 20, 20, 21, 21, 22, 22, 22, 23, 23, 24, 24, 24, 25, 25, 26, 26, 26, 27, 27, 28,
	1, 2, 3, 4, 4, 5, 6, 7, 8, 8, 9, 10, 21, 22, 22, 22, 23, 23, 23, 24, 24, 24, 25, 25, 25, 26, 26, 27, 27, 27, 28, 28,
	1, 2, 3, 4, 4, 5, 6, 7, 8, 8, 9, 10, 23, 23, 23, 23, 24, 24, 24, 25, 25, 25, 26, 26, 26, 26, 27, 27, 27, 28, 28, 28,
	1, 2, 3, 4, 4, 5, 6, 7, 8, 8, 9, 10, 24, 24, 24, 25, 25, 25, 25, 26, 26, 26, 26, 27, 27, 27, 27, 28, 28, 28, 28, 29,
	1, 2, 3, 4, 4, 5, 6, 7, 8, 8, 9, 10, 25, 25, 26, 26, 26, 26, 26, 27, 27, 27, 27, 27, 28, 28, 28, 28, 28, 29, 29, 29,
	1, 2, 3, 4, 4, 5, 6, 7, 8, 8, 9, 10, 27, 27, 27, 27, 27, 27, 27, 28, 28, 28, 28, 28, 28, 28, 29, 29, 29, 29, 29, 29,
	1, 2, 3, 4, 4, 5, 6, 7, 8, 8, 9, 10, 28, 28, 28, 28, 28, 28, 28, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 30, 30, 30,
	1, 2, 3, 4, 4, 5, 6, 7, 8, 8, 9, 10, 29, 29, 29, 29, 29, 29, 29, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30,
	1, 2, 3, 4, 4, 5, 6, 7, 8, 8, 9, 10, 31, 31, 31, 31, 31, 31, 31, 31, 31, 31, 31, 31, 31, 31, 31, 31, 31, 31, 31, 31,
]


static func value_at(row: int, col: int) -> int:
	return DARKENED_CONTRAST[row * NUM_COLS + col]


## Builds the LUT as a single-channel (L8) image, one row per color-map
## index, one column per original 0-31 channel value, values normalized so
## a shader can sample it directly as a 0.0-1.0 replacement fraction.
static func build_lut_image() -> Image:
	var img := Image.create(NUM_COLS, NUM_ROWS, false, Image.FORMAT_L8)
	for row in range(NUM_ROWS):
		for col in range(NUM_COLS):
			var v: float = float(value_at(row, col)) / 31.0
			img.set_pixel(col, row, Color(v, v, v, 1.0))
	return img
