class_name WeatherManager
extends CanvasLayer

## [M27N] Field weather — a direct port of source's real `Task_WeatherMain`
## state machine (`field_weather.c`), driving a shared palette-grade shader
## applied to every loaded chunk's TERRAIN planes only (never the player/NPC
## layer — see `MapManager._apply_weather_material`'s own doc comment for
## why that's a clean exclusion here, not a special case).
##
## Built in code, not a `.tscn` — matches every sibling field widget
## (`MessageBox`/`YesNoBox`/`OakSpeechOverlay`/`NamingScreen`), this
## project's own established convention for this subsystem. Deliberately
## decoupled from `MapManager`: callers resolve "which map, which weather"
## themselves (`MapManager.weather_of(map_name)`) and just tell this widget
## the answer via `request_weather(w)`.
##
## ⚠️ THIS GROUP IS PALETTE-GRADE-ONLY (NONE/SUNNY_CLOUDS/SUNNY/SHADE/
## DROUGHT) — the other 7 real types (RAIN/RAIN_THUNDERSTORM/
## FOG_HORIZONTAL/VOLCANIC_ASH/SANDSTORM/DOWNPOUR/UNDERWATER_BUBBLES) need
## real sprite/particle work (a future phase, see docs) and are registered
## here only as STUBS — `finish()` returns false immediately so the state
## machine can never hang waiting on an unbuilt type, matching `ScriptVM`'s
## own `Pause.UNKNOWN_OP` + `diagnostic` degrade-and-report convention
## rather than a special case at every call site.
##
## ⚠️ DROUGHT is real (not a stub) but is the one type in this tier with a
## GENUINELY SEPARATE mechanism — source's own `sDroughtWeatherColors` is a
## direct 6-stage RGB->RGB 3D lookup (`weather_color_maps.gd`'s 19x32
## per-channel curve does not apply to it at all), a 6-step brightness ramp
## (`DroughtStateRun`, `field_weather.c:967-1001`) that rises over ~0.6s then
## oscillates via a real sine wave. **Confirmed zero real Kanto maps use it**
## (measured across all 421 imported maps: NONE 333 / SUNNY 62 /
## FOG_HORIZONTAL 19 / SHADE 7 / DROUGHT **0**) — so this is a from-source
## faithful port with no in-game consumer yet, exercised only by
## `m27n_weather_test.gd`'s own direct WeatherManager-instance driving.
##
## ⚠️ Disclosed simplification: source's `Drought_InitAll` fast-forwards the
## whole rise synchronously on a hard boot/warp so the player never SEES it
## climb (only a seamless map-crossing plays it gradually via `Drought_Main`).
## This port always plays the gradual rise, on every transition kind — with
## zero real consumers there is nothing to notice the difference, and faking
## an instant hard-warp variant now would be speculative machinery for a
## behavior nobody can currently observe. Flagged for whenever a real Drought
## map exists to test the distinction against.
##
## ⚠️ Source's `DroughtStateRun` switch has a THIRD case (`droughtState == 2`,
## a reverse fade-down) that is confirmed DEAD CODE — grepped the full tree,
## `droughtState` is never assigned 2 anywhere. Not ported: `Drought_Finish`
## itself always returns FALSE (drought never blocks a transition away from
## it, same as every other type in this tier), so nothing ever triggers it in
## source either.
##
## ⚠️ SUNNY's real "look" in source is a hardware shadow-blend coefficient
## (`Weather_SetBlendCoeffs`), not a colour-map grade — its own target index
## is 0 (no table lookup at all), so it is CORRECTLY a visual no-op under
## this shader alone. Flagged here, not silently absorbed: Sunny will look
## identical to None until a future phase ports the shadow-blend mechanism.

signal weather_changed(current: int)
## Fires on every `request_weather()` call, whether or not it actually
## changes anything — unlike `weather_changed`, which only fires when
## `_current_weather` really flips. Two adjacent maps sharing the same real
## weather value (e.g. Pallet Town and Route 1, both SUNNY) would otherwise
## be indistinguishable from "the hook was never wired at all".
signal weather_requested(w: int)

const COLOR_MAP_STEP_SECONDS := 20.0 / 60.0  # source: colorMapStepDelay = 20 frames

var _current_weather: int = MapData.Weather.NONE
var _next_weather: int = MapData.Weather.NONE
var _color_map_index: int = 0
var _color_map_step_accum: float = 0.0
var _diagnostic: String = ""

## [M27N Drought] `DroughtStateRun`'s own state, ported 1:1: state 0 = rising
## (a new stage every 6 real 60fps-equivalent frames until stage 6, i.e. all
## 6 real stages 0-5 applied), state 1 = oscillating (a real sine wave via
## the project's own already-ported `MonAnimator.SINE_TABLE`). `_frame_accum`
## converts wall-clock delta into "how many logical 60fps frames elapsed"
## (this project's own established refresh-rate-independence pattern, see
## `[M26G4]`), since source's own timer arithmetic is written in whole frames.
const DROUGHT_FRAME_SECONDS := 1.0 / 60.0
var _drought_state: int = 0
var _drought_timer: int = 0
var _drought_stage: int = 0
var _drought_last_stage: int = -1
var _drought_frame_accum: float = 0.0

## weather_id -> {init: Callable, main: Callable, finish: Callable, target: int}
## `target` is read by the default init/finish pair below; a custom `init`
## may ignore it entirely (Drought will, once it lands).
var _registry: Dictionary = {}

static var _shader: Shader = null
var _material: ShaderMaterial = null

## [M27N W3] The one shared tiled-sprite overlay, reused across FOG_HORIZONTAL/
## VOLCANIC_ASH/SANDSTORM (at most one is ever current at once, per this
## file's own transition serialization). `_camera_scroll_px` is PUSHED from
## `overworld.gd`'s own `_snap_camera_to_player()`, never polled — see
## `push_camera_scroll`'s own doc comment.
var _tiled_overlay: TiledWeatherOverlay = null
var _camera_scroll_px: Vector2 = Vector2.ZERO


func _init() -> void:
	# Below every message/menu widget (lowest sibling is OakSpeechOverlay's
	# 30), above the map/entities — this project's own established
	# CanvasLayer convention (see message_box.gd's own stack-ordering note).
	layer = 20
	_register_palette_grade(MapData.Weather.NONE, 0)
	_register_palette_grade(MapData.Weather.SUNNY, 0)
	_register_palette_grade(MapData.Weather.SHADE, 3)
	_registry[MapData.Weather.DROUGHT] = {
		"init": _drought_init, "main": _drought_main,
		"finish": func(_delta: float) -> bool: return false,  # Drought_Finish: always FALSE
		"target": 0,
	}
	# [M27N W3] The tiled-scroll group. Coefficients ported verbatim from
	# source's real `Weather_SetTargetBlendCoeffs` call sites
	# (`field_weather_effect.c`) — (eva, evb, delay_frames), simplified onto
	# `TiledWeatherOverlay`'s own single-alpha ramp (see its own doc comment).
	_register_tiled(MapData.Weather.FOG_HORIZONTAL, {
		"sheet_path": "res://assets/weather/fog_horizontal.png",
		"frame_size": Vector2i(64, 64),
		"drift_kind": TiledWeatherOverlay.Drift.FOG_X,
		"init_alpha": Vector3(12, 8, 3),
		"teardown_alpha": Vector3(0, 16, 3),
	})
	_register_tiled(MapData.Weather.VOLCANIC_ASH, {
		"sheet_path": "res://assets/weather/ash.png",
		"frame_size": Vector2i(64, 64),
		"drift_kind": TiledWeatherOverlay.Drift.ASH_Y,
		"init_alpha": Vector3(10, 12, 1),
		"teardown_alpha": Vector3(0, 12, 1),
	})
	_register_tiled(MapData.Weather.SANDSTORM, {
		"sheet_path": "res://assets/weather/sandstorm.png",
		"frame_size": Vector2i(64, 64),
		"drift_kind": TiledWeatherOverlay.Drift.SANDSTORM_XY,
		"init_alpha": Vector3(16, 2, 0),
		"teardown_alpha": Vector3(0, 16, 0),
	})
	for w in [
		MapData.Weather.SUNNY_CLOUDS, MapData.Weather.RAIN,
		MapData.Weather.RAIN_THUNDERSTORM,
		MapData.Weather.DOWNPOUR, MapData.Weather.UNDERWATER_BUBBLES,
	]:
		_register_stub(w)


func _ready() -> void:
	_material = ShaderMaterial.new()
	_material.shader = _get_shader()
	_material.set_shader_parameter("color_lut", _lut_texture())
	_material.set_shader_parameter("color_map_row", _row_for_index(0))
	_material.set_shader_parameter("drought_lut", _drought_lut_texture())
	_material.set_shader_parameter("drought_stage", -1.0)
	_tiled_overlay = TiledWeatherOverlay.new()
	add_child(_tiled_overlay)


## The one shared material — a caller (MapManager) applies this SAME
## instance by reference to every terrain plane it owns; mutating its
## uniforms here updates every plane at once with no per-chunk re-walk.
func material() -> ShaderMaterial:
	return _material


## [M27N W3] Called from `overworld.gd`'s own `_snap_camera_to_player()` —
## the exact frame-perfect moment the camera itself just moved, not a poll
## from this node's own `_process()` (which would reliably read LAST
## frame's camera position, since the camera moves via a Tween that
## advances AFTER a frame's `_process()` calls have already run).
func push_camera_scroll(px: Vector2) -> void:
	_camera_scroll_px = px
	if _tiled_overlay != null and _tiled_overlay.is_active():
		_tiled_overlay.reposition(px)


func request_weather(w: int) -> void:
	_next_weather = w
	weather_requested.emit(w)


func current_weather() -> int:
	return _current_weather


## Test-only seam: lets a synthetic weather type (e.g. a slow-finishing one)
## be injected without a real sprite/particle implementation existing yet.
func register(w: int, init: Callable, main: Callable, finish: Callable) -> void:
	_registry[w] = {"init": init, "main": main, "finish": finish, "target": 0}


func diagnostic() -> String:
	return _diagnostic


func _process(delta: float) -> void:
	if _current_weather != _next_weather:
		if not _call(_current_weather, "finish", [delta]):
			_call(_next_weather, "init")
			_color_map_step_accum = 0.0
			_current_weather = _next_weather
			weather_changed.emit(_current_weather)
	else:
		_call(_current_weather, "main", [delta])
	_step_color_map(delta)


func _call(w: int, key: String, args: Array = []) -> Variant:
	var entry: Dictionary = _registry.get(w, {})
	var c: Callable = entry.get(key, Callable())
	if not c.is_valid():
		return false
	return c.callv(args)


func _target_for(w: int) -> int:
	return int(_registry.get(w, {}).get("target", 0))


func _step_color_map(delta: float) -> void:
	var target: int = _target_for(_current_weather)
	if _color_map_index == target:
		return
	_color_map_step_accum += delta
	while _color_map_step_accum >= COLOR_MAP_STEP_SECONDS and _color_map_index != target:
		_color_map_step_accum -= COLOR_MAP_STEP_SECONDS
		_color_map_index += 1 if target > _color_map_index else -1
	if _material != null:
		_material.set_shader_parameter("color_map_row", _row_for_index(_color_map_index))


## ⚠️ `colorMapIndex == 0` is a REAL, distinct case in source (`ApplyColorMap`'s
## own `else` branch) — it means "no grading at all," not "row 0 of the
## table." Source decrements before indexing (`colorMapIndex--;` then
## `sDarkenedContrastColorMaps[colorMapIndex]`), so external index 1 reads
## row 0, index 2 reads row 1, etc. Returns a negative sentinel for the
## no-grading case; the shader passes the pixel through unchanged.
static func _row_for_index(index: int) -> float:
	if index <= 0:
		return -1.0
	var row: int = clampi(index - 1, 0, WeatherColorMaps.NUM_ROWS - 1)
	return (float(row) + 0.5) / float(WeatherColorMaps.NUM_ROWS)


func _register_palette_grade(w: int, target: int) -> void:
	_registry[w] = {
		"init": Callable(), "main": Callable(),
		"finish": func(_delta: float) -> bool: return false,
		"target": target,
	}


func _register_stub(w: int) -> void:
	_registry[w] = {
		"init": func() -> void: _diagnostic = "weather %d has no real implementation yet" % w,
		"main": Callable(),
		"finish": func(_delta: float) -> bool: return false,
		"target": 0,
	}


## [M27N W3] Sub-object-owned dispatch, matching Drought's own precedent
## (state lives on `WeatherManager`/its overlay, registry closures are thin
## dispatch). `cfg["sheet_path"]` is resolved to a real `Texture2D` once,
## here, rather than per-transition.
func _register_tiled(w: int, cfg: Dictionary) -> void:
	var full_cfg: Dictionary = cfg.duplicate()
	full_cfg["sheet"] = load(String(cfg["sheet_path"])) as Texture2D
	_registry[w] = {
		"init": func() -> void:
			# Any leftover palette-curve grading must not linger into a
			# tiled-overlay type — mirrors `_drought_init()`'s own
			# defensive immediate reset, for the identical reason: none of
			# these three types touch the 19x32 LUT mechanism at all.
			_color_map_index = 0
			_color_map_step_accum = 0.0
			if _material != null:
				_material.set_shader_parameter("color_map_row", _row_for_index(0))
			# `_tiled_overlay` is created unconditionally in `_ready()`,
			# before any weather transition can occur (`_process()` never
			# runs before `_ready()` completes) — no null guard needed.
			_tiled_overlay.begin(full_cfg, _camera_scroll_px),
		"main": func(delta: float) -> void:
			_tiled_overlay.tick(delta),
		"finish": func(delta: float) -> bool:
			return _tiled_overlay.teardown(delta),
		"target": 0,
	}


## `Drought_InitVars` (`field_weather_effect.c:239-246`): reset to the rising
## state. Source leaves colorMapIndex untouched here (no grading applied
## until the first real tick, 6 frames later) — matched by NOT touching the
## `drought_stage` uniform, so whatever the previous weather left behind
## (typically "no grading", -1) persists for those first few frames.
func _drought_init() -> void:
	_drought_state = 0
	_drought_timer = 0
	_drought_stage = 0
	_drought_last_stage = -1
	_drought_frame_accum = 0.0
	# Drought owns its own uniform channel entirely -- source's real
	# mechanism is ONE signed `colorMapIndex` field where the sign picks the
	# mechanism (positive -> the darkened-contrast curve, negative ->
	# Drought's own cube). This project splits that into two uniforms for
	# clarity, so the palette-curve one must be forced to its own "no
	# grading" sentinel immediately (not gradually stepped, which would
	# otherwise show a leftover Shade/Sunny grade fighting the Drought ramp
	# for the few frames it takes `_step_color_map` to catch up).
	_color_map_index = 0
	_color_map_step_accum = 0.0
	if _material != null:
		_material.set_shader_parameter("color_map_row", _row_for_index(0))


## `DroughtStateRun` (`field_weather.c:967-1001`), state 2 (dead code, see the
## class doc comment) omitted. Runs once per real 60fps-equivalent frame,
## accumulated from wall-clock `delta` for refresh-rate independence.
func _drought_main(delta: float) -> void:
	_drought_frame_accum += delta
	while _drought_frame_accum >= DROUGHT_FRAME_SECONDS:
		_drought_frame_accum -= DROUGHT_FRAME_SECONDS
		_drought_tick_one_frame()


func _drought_tick_one_frame() -> void:
	if _drought_state == 0:
		_drought_timer += 1
		if _drought_timer > 5:
			_drought_timer = 0
			_drought_apply_stage(_drought_stage)
			_drought_stage += 1
			if _drought_stage > 5:
				_drought_last_stage = _drought_stage
				_drought_state = 1
				_drought_timer = 60
	elif _drought_state == 1:
		_drought_timer = (_drought_timer + 3) & 0x7F
		var val: int = int(MonAnimator.SINE_TABLE[_drought_timer])
		var stage: int = clampi(((val - 1) >> 6) + 2, 0, 5)
		_drought_stage = stage
		if stage != _drought_last_stage:
			_drought_apply_stage(stage)
		_drought_last_stage = stage


func _drought_apply_stage(stage: int) -> void:
	if _material != null:
		_material.set_shader_parameter("drought_stage", float(stage))


static var _drought_lut: Texture2D = null


static func _drought_lut_texture() -> Texture2D:
	if _drought_lut == null:
		_drought_lut = load("res://assets/weather/drought_lut.png") as Texture2D
	return _drought_lut


static func _get_shader() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = _SHADER_CODE
	return _shader


static var _lut_image_texture: ImageTexture = null


static func _lut_texture() -> ImageTexture:
	if _lut_image_texture == null:
		_lut_image_texture = ImageTexture.create_from_image(WeatherColorMaps.build_lut_image())
	return _lut_image_texture


const _SHADER_CODE := """
shader_type canvas_item;
uniform sampler2D color_lut : repeat_disable;
// A negative row means "no grading" (source's colorMapIndex == 0 case) --
// the pixel passes through unchanged, not row 0 of the table.
uniform float color_map_row = -1.0;
// Drought's own separate mechanism: a full RGB->RGB 3D lookup, not a
// per-channel remap -- see weather_manager.gd's own class doc comment.
// A negative stage means "Drought inactive"; the two grading modes are
// mutually exclusive (only one weather is ever current at a time).
uniform sampler2D drought_lut : repeat_disable;
uniform float drought_stage = -1.0;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (color_map_row >= 0.0) {
		float r = texture(color_lut, vec2((floor(c.r*31.0+0.5)+0.5)/32.0, color_map_row)).r;
		float g = texture(color_lut, vec2((floor(c.g*31.0+0.5)+0.5)/32.0, color_map_row)).r;
		float b = texture(color_lut, vec2((floor(c.b*31.0+0.5)+0.5)/32.0, color_map_row)).r;
		c = vec4(r, g, b, c.a);
	} else if (drought_stage >= 0.0) {
		float r4 = floor(floor(c.r*31.0+0.5) * 0.5);
		float g4 = floor(floor(c.g*31.0+0.5) * 0.5);
		float b4 = floor(floor(c.b*31.0+0.5) * 0.5);
		float col = (r4 + g4*16.0 + 0.5) / 256.0;
		float row = (b4 + drought_stage*16.0 + 0.5) / 96.0;
		vec3 mapped = texture(drought_lut, vec2(col, row)).rgb;
		c = vec4(mapped, c.a);
	}
	COLOR = c;
}
"""
