class_name TiledWeatherOverlay
extends Node2D

## [M27N W3] The shared tiling-scroll mechanism used by FOG_HORIZONTAL /
## VOLCANIC_ASH / SANDSTORM's base layer. Source reimplements this 3x
## independently with no shared helper (`CreateFogHorizontalSprites`/
## `CreateAshSprites`/`CreateSandstormSprites`, `field_weather_effect.c`,
## 20 sprites each, a 5x4 grid of 64x64 hardware sprites) -- this project
## builds it once, reconfigured per active type (at most one of the three
## is ever current at a time, per `WeatherManager`'s own transition
## serialization).
##
## Screen-space (a plain `Node2D` child of `WeatherManager`'s CanvasLayer,
## NOT world-space) -- the tiles wrap within a fixed on-screen field rather
## than covering the actual world, matching source's own hardware-sprite
## tiling trick. Camera tracking is a PUSH from `overworld.gd`'s own
## `_snap_camera_to_player()` (via `WeatherManager.push_camera_scroll`), not
## a per-frame poll -- reading camera position from this node's own
## `_process()` would reliably see LAST frame's value, since the camera
## moves via a Tween that advances AFTER a frame's own `_process()` calls
## (the exact staleness `overworld.gd`'s own camera doc comment already
## measured and fixed once, one layer up the chain).
##
## Grid size is DERIVED from the real viewport size and this project's own
## fixed camera zoom (3, `TILE_SCALE` below), NOT source's literal 5x4
## (sized for a 240x160 GBA screen) -- porting 5x4 onto this project's
## 1024x768 canvas would leave visible gaps.
##
## ⚠️ DISCLOSED SIMPLIFICATION: each type's per-frame ANIMATION is not
## ported -- every tile draws a single static frame (the sheet's own first
## `frame_size` region). Source's own frame layout for these three sheets
## is GBA hardware tile-block addressing, not a simple horizontal filmstrip
## (confirmed for Ash: 64x128, two 64x64 frames stacked VERTICALLY; Fog's
## own "6 frames" and Sandstorm's do not resolve to an unambiguous pixel
## layout from the extracted PNG alone). With zero real map consumers for
## any of the three today, spending further Step 0 effort pinning down
## exact sub-frame rects is disproportionate; revisit once a real Fog/Ash/
## Sandstorm map is reachable and the animation is actually visible.

const TILE_SCALE := 3.0  # matches overworld.gd's own fixed `_camera.zoom`
const FRAME_SECONDS := 1.0 / 60.0  # source's own frame unit, 60fps-equivalent
const ALPHA_UNIT := 1.0 / 16.0  # one BLDALPHA coefficient step (0-16 range)

enum Drift { NONE, FOG_X, ASH_Y, SANDSTORM_XY }

var _active := false
var _sprites: Array[Sprite2D] = []
var _cols := 0
var _rows := 0
var _tile_size := Vector2.ZERO
var _camera_scroll_px := Vector2.ZERO

var _drift_kind: int = Drift.NONE
var _frame_accum := 0.0  # logical-60fps-frame accumulator, shared by drift + alpha

## Fog's own independent linear X creep (`fogHScrollOffset`, +1/4 frames).
var _fog_creep := 0.0
var _fog_counter := 0
## Ash's own independent linear Y creep (`tOffsetY`, +1/6 frames). Unbounded
## in source (relies on GBA hardware OAM truncation); `_layout_sprites`'s
## own `fposmod` wrap makes an explicit modulo on the accumulator itself
## unnecessary for correctness, only for long-run float precision.
var _ash_fall := 0.0
var _ash_counter := 0
## Sandstorm's sine-driven "gust" (`sandstormWaveIndex`/`XOffset`/`YOffset`).
## Wave index walks [0x20, 0x60], +1 every 5 frames; the X/Y integrators
## accumulate every frame off whatever sine value the (slowly-changing)
## index currently reads, X biased 4x as strongly as Y.
var _sandstorm_wave_index := 0x20
var _sandstorm_wave_counter := 0
var _sandstorm_x_offset := 0.0
var _sandstorm_y_offset := 0.0

## `init_alpha`/`teardown_alpha` are `(eva, evb, delay_frames)`, mirroring
## source's real `Weather_SetTargetBlendCoeffs` call sites -- simplified
## onto a single alpha (`eva/16.0`) ramping via Godot's own `modulate.a`
## rather than porting GBA BLDALPHA register semantics literally. Every
## real teardown row has `eva == 0`, so tearing down always means "ramp
## alpha to 0," never a type-specific target.
var _alpha := 0.0
var _target_alpha := 0.0
var _alpha_delay_frames := 1.0
var _alpha_step_accum := 0.0
var _teardown_delay_frames := 1.0
var _tearing_down := false


func begin(cfg: Dictionary, camera_scroll_px: Vector2) -> void:
	_destroy_sprites()
	_camera_scroll_px = camera_scroll_px
	_drift_kind = int(cfg.get("drift_kind", Drift.NONE))
	_frame_accum = 0.0
	_fog_creep = 0.0
	_fog_counter = 0
	_ash_fall = 0.0
	_ash_counter = 0
	_sandstorm_wave_index = 0x20
	_sandstorm_wave_counter = 0
	_sandstorm_x_offset = 0.0
	_sandstorm_y_offset = 0.0

	var init_alpha: Vector3 = cfg.get("init_alpha", Vector3(16, 0, 1))
	var teardown_alpha: Vector3 = cfg.get("teardown_alpha", Vector3(0, 16, 1))
	_alpha = 0.0
	_target_alpha = init_alpha.x / 16.0
	_alpha_delay_frames = maxf(1.0, init_alpha.z)
	_alpha_step_accum = 0.0
	_teardown_delay_frames = maxf(1.0, teardown_alpha.z)
	_tearing_down = false

	_active = true
	_build_grid(cfg)
	_layout_sprites()
	modulate.a = _alpha


func tick(delta: float) -> void:
	if not _active:
		return
	_frame_accum += delta
	while _frame_accum >= FRAME_SECONDS:
		_frame_accum -= FRAME_SECONDS
		_advance_drift()
		_step_alpha()
	modulate.a = _alpha
	_layout_sprites()


## Cheap, position-only update -- no drift/alpha advancement. Called
## synchronously from `WeatherManager.push_camera_scroll`, the frame-perfect
## moment the camera itself just moved.
func reposition(camera_scroll_px: Vector2) -> void:
	_camera_scroll_px = camera_scroll_px
	if _active:
		_layout_sprites()


## Returns true while still tearing down (ramping alpha to 0 and running
## drift, matching source's own `_Finish` keeping the gust/creep alive
## through teardown). Once alpha reaches 0, destroys the sprites and
## returns false, unblocking `WeatherManager`'s transition.
func teardown(delta: float) -> bool:
	if not _active:
		return false
	if not _tearing_down:
		_tearing_down = true
		_target_alpha = 0.0
		_alpha_delay_frames = _teardown_delay_frames
		_alpha_step_accum = 0.0
	_frame_accum += delta
	while _frame_accum >= FRAME_SECONDS:
		_frame_accum -= FRAME_SECONDS
		_advance_drift()
		_step_alpha()
	modulate.a = _alpha
	_layout_sprites()
	if _alpha <= 0.0:
		_destroy_sprites()
		_active = false
		return false
	return true


func is_active() -> bool:
	return _active


func _build_grid(cfg: Dictionary) -> void:
	var sheet: Texture2D = cfg.get("sheet")
	var frame_size: Vector2i = cfg.get("frame_size", Vector2i(64, 64))
	_tile_size = Vector2(frame_size) * TILE_SCALE
	var vp := get_viewport().get_visible_rect().size
	# +2 tiles of headroom each axis: one so a tile is never mid-wrap right
	# at the screen edge, one for the camera's own step/tween overshoot.
	_cols = maxi(1, int(ceil(vp.x / _tile_size.x)) + 2)
	_rows = maxi(1, int(ceil(vp.y / _tile_size.y)) + 2)
	for i in range(_cols * _rows):
		var spr := Sprite2D.new()
		spr.texture = sheet
		spr.centered = false
		spr.scale = Vector2(TILE_SCALE, TILE_SCALE)
		if sheet != null:
			spr.region_enabled = true
			spr.region_rect = Rect2(Vector2.ZERO, Vector2(frame_size))
		add_child(spr)
		_sprites.append(spr)


func _destroy_sprites() -> void:
	for spr in _sprites:
		if is_instance_valid(spr):
			# `remove_child` first -- `queue_free()` alone defers the actual
			# detach to end-of-frame, so a caller checking child count (or
			# `is_active()`'s own contract) immediately after teardown would
			# still see the stale sprites for one more frame.
			remove_child(spr)
			spr.queue_free()
	_sprites.clear()


func _layout_sprites() -> void:
	if _sprites.is_empty() or _tile_size.x <= 0.0 or _tile_size.y <= 0.0:
		return
	var drift := _drift_offset() * TILE_SCALE
	var total_w := _cols * _tile_size.x
	var total_h := _rows * _tile_size.y
	for i in range(_sprites.size()):
		var col := i % _cols
		var row := i / _cols
		var base_x := col * _tile_size.x
		var base_y := row * _tile_size.y
		var x := fposmod(base_x - _camera_scroll_px.x - drift.x, total_w) - _tile_size.x
		var y := fposmod(base_y - _camera_scroll_px.y - drift.y, total_h) - _tile_size.y
		_sprites[i].position = Vector2(x, y)


func _drift_offset() -> Vector2:
	match _drift_kind:
		Drift.FOG_X:
			return Vector2(_fog_creep, 0.0)
		Drift.ASH_Y:
			return Vector2(0.0, _ash_fall)
		Drift.SANDSTORM_XY:
			return Vector2(_sandstorm_x_offset / 256.0, _sandstorm_y_offset / 256.0)
		_:
			return Vector2.ZERO


func _advance_drift() -> void:
	match _drift_kind:
		Drift.FOG_X:
			_fog_counter += 1
			if _fog_counter >= 4:
				_fog_counter = 0
				_fog_creep += 1.0
		Drift.ASH_Y:
			_ash_counter += 1
			if _ash_counter >= 6:
				_ash_counter = 0
				_ash_fall += 1.0
		Drift.SANDSTORM_XY:
			_sandstorm_wave_counter += 1
			if _sandstorm_wave_counter >= 5:
				_sandstorm_wave_counter = 0
				if _sandstorm_wave_index < 0x60:
					_sandstorm_wave_index += 1
			var s: int = int(MonAnimator.SINE_TABLE[_sandstorm_wave_index])
			_sandstorm_x_offset -= float(s) * 4.0
			_sandstorm_y_offset -= float(s)


func _step_alpha() -> void:
	_alpha_step_accum += 1.0
	if _alpha_step_accum >= _alpha_delay_frames:
		_alpha_step_accum -= _alpha_delay_frames
		if _alpha < _target_alpha:
			_alpha = minf(_alpha + ALPHA_UNIT, _target_alpha)
		elif _alpha > _target_alpha:
			_alpha = maxf(_alpha - ALPHA_UNIT, _target_alpha)
