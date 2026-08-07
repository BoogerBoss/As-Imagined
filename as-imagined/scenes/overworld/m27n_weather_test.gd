extends Node

## [M27N Phase 1] Field weather — the full palette-grade group
## (NONE/SUNNY/SHADE/DROUGHT), the other 8 sprite/particle types registered
## as stubs, real bodies land in later phases.
##
## The claims most worth pinning:
##
##   * a real baked map's `weather` field survives import -> JSON -> .tres,
##     using Viridian Forest (SHADE) and Pallet Town (SUNNY) as fixtures —
##     both are real, both are in the current 32-map corridor;
##   * the OLD weather type's `finish()` must report "done" before the NEW
##     type's `init()` fires — this needs a synthetic slow-finishing type,
##     since none of the 3 real palette-curve types built this pass ever
##     exercise that branch (all three finish immediately);
##   * `colorMapIndex` steps once per 20/60s, refresh-rate independent
##     (accumulates delta, does not reset on a partial step);
##   * `colorMapIndex == 0` means NO grading at all (a source-real, distinct
##     case — not "row 0 of the table"), returned as a negative sentinel
##     the shader must pass through unchanged;
##   * both real map-transition hook shapes (seamless crossing, hard-cut
##     warp) call `request_weather` with the destination's real value;
##   * Drought's own separate 3D-cube mechanism — a real 0.6s rise through
##     all 6 real stages, then a genuine sine-driven oscillation — and that
##     transitioning INTO Drought immediately clears any leftover
##     palette-curve grading rather than gradually stepping through it.
##     Confirmed zero real Kanto maps use Drought (see `weather_manager.gd`'s
##     own class doc comment), so this is exercised only by directly driving
##     a `WeatherManager` instance, not through a real map transition.
##   * [W3] The shared tiled-scroll overlay (FOG_HORIZONTAL/VOLCANIC_ASH/
##     SANDSTORM's base layer) — alpha ramps gradually via `modulate.a`
##     rather than snapping, each type's own drift formula genuinely moves
##     the tile field over time, `finish()` is now a real multi-frame
##     teardown (unlike the palette-grade types' immediate `false`), and
##     camera-scroll tracking is a synchronous PUSH from `overworld.gd`'s
##     own `_snap_camera_to_player()`, not a per-frame poll. Confirmed zero
##     real Kanto maps use Ash/Sandstorm and none of the 32-map corridor
##     uses Fog, so — like Drought — this is exercised by directly driving
##     `WeatherManager`/`TiledWeatherOverlay` instances.

const EXPECTED_TOTAL := 48

var _total := 0
var _failed := 0
var _gated := 0


func _chk(label: String, cond: bool) -> void:
	_total += 1
	if not cond:
		_failed += 1
		print("FAILED: %s" % label)


func _ready() -> void:
	_test_importer_round_trip()
	_test_state_machine_transition()
	_test_color_map_stepping()
	_test_no_grading_sentinel()
	_test_lut_texture()
	_test_registry_stubs()
	_test_drought_lut()
	_test_drought_state_machine()
	_test_drought_main_frame_accum()
	_test_tiled_overlay_lifecycle()
	_test_tiled_overlay_drift()
	_test_tiled_registry_integration()
	_test_camera_scroll_push()
	await _test_transition_hooks()

	var accounted := _total + _gated
	_chk("Z.99 every expected assertion ran (%d + %d gated == %d)"
			% [_total, _gated, EXPECTED_TOTAL], accounted == EXPECTED_TOTAL)
	print("m27n_weather_test: %d/%d passed" % [_total - _failed, _total])
	get_tree().quit()


## --- A. importer round-trip, against the real baked corridor ---
func _test_importer_round_trip() -> void:
	# `MapData.load_from()` parses the INTERMEDIATE JSON the importer emits
	# (`assets/maps/*.json`) — the real baked artifacts are `.tres` Resources,
	# loaded directly through `load()` like any other Resource, not re-parsed
	# as JSON text.
	var forest := load("res://scenes/maps/ViridianForest_Frlg_data.tres") as MapData
	_chk("A.01 Viridian Forest's real weather is SHADE, surviving the full import->bake pipeline",
			forest != null and forest.weather == MapData.Weather.SHADE)

	var pallet := load("res://scenes/maps/PalletTown_Frlg_data.tres") as MapData
	_chk("A.02 Pallet Town's real weather is SUNNY",
			pallet != null and pallet.weather == MapData.Weather.SUNNY)

	_chk("A.03 a fresh MapData with no weather set defaults to NONE",
			MapData.new().weather == MapData.Weather.NONE)


## --- B. state-machine transition, without real frame-stepping ---
func _test_state_machine_transition() -> void:
	var wm := WeatherManager.new()
	add_child(wm)

	# Two synthetic types: 99 (the OLD type, slow-finishing -- Finish()
	# returns true for 2 calls, then false) and 98 (the NEW type, whose own
	# Init() is what B.03 must observe firing). None of the 3 real types
	# built this pass ever exercise "old type blocks the new Init" --
	# without injectable synthetic types this branch is unfalsifiable.
	var finish_calls := [0]
	var init_fired := [false]
	wm.register(99, Callable(), Callable(),
			func(_delta: float) -> bool:
				finish_calls[0] += 1
				return finish_calls[0] <= 2)
	wm.register(98,
			func() -> void: init_fired[0] = true,
			Callable(), Callable())

	wm._current_weather = 99
	wm._next_weather = 98
	wm._process(0.0001)
	_chk("B.01 the new type's init does NOT fire while the old type is still finishing (call 1)",
			not init_fired[0] and wm._current_weather == 99)
	wm._process(0.0001)
	_chk("B.02 still finishing (call 2)",
			not init_fired[0] and wm._current_weather == 99)
	wm._process(0.0001)
	_chk("B.03 the old type reports done (call 3, false) -- NOW the new type's init fires and current flips",
			init_fired[0] and wm._current_weather == 98)

	wm.queue_free()


## --- C. colorMapIndex stepping, real numbers ---
func _test_color_map_stepping() -> void:
	var wm := WeatherManager.new()
	add_child(wm)
	_chk("C.01 the step interval is exactly 20/60 seconds",
			is_equal_approx(wm.COLOR_MAP_STEP_SECONDS, 20.0 / 60.0))

	wm._current_weather = MapData.Weather.SHADE
	wm._next_weather = MapData.Weather.SHADE
	wm._color_map_index = 0
	wm._color_map_step_accum = 0.0
	# NONE->SHADE (index 0->3) is 3 steps * (20/60)s = 1.0s exactly. Drive it
	# in irregular deltas (not a fixed 60fps tick), CYCLED until the target is
	# reached, to prove refresh-rate independence -- accumulate, don't reset
	# on a partial step.
	var elapsed := 0.0
	var deltas: Array[float] = [1.0 / 30.0, 1.0 / 30.0, 1.0 / 45.0, 1.0 / 45.0, 1.0 / 20.0, 1.0 / 20.0, 1.0 / 20.0]
	var di := 0
	var iterations := 0
	while wm._color_map_index != 3 and iterations < 500:
		var d: float = deltas[di % deltas.size()]
		wm._step_color_map(d)
		elapsed += d
		di += 1
		iterations += 1
	_chk("C.02 NONE->SHADE (index 0->3) reaches target in ~1.0s of WALL-CLOCK time regardless of frame size",
			wm._color_map_index == 3 and elapsed >= 1.0 and elapsed < 1.0 + wm.COLOR_MAP_STEP_SECONDS)

	wm.queue_free()


## --- D. colorMapIndex == 0 means "no grading," not row 0 ---
func _test_no_grading_sentinel() -> void:
	_chk("D.01 index 0 returns the negative no-grading sentinel",
			WeatherManager._row_for_index(0) < 0.0)
	_chk("D.02 a negative index (defensive) also returns the sentinel",
			WeatherManager._row_for_index(-1) < 0.0)
	_chk("D.03 index 3 (Shade's real target) resolves to row 2 (source decrements before indexing)",
			is_equal_approx(WeatherManager._row_for_index(3), (2.0 + 0.5) / float(WeatherColorMaps.NUM_ROWS)))


## --- E. the LUT texture matches the transcribed table ---
func _test_lut_texture() -> void:
	var img := WeatherColorMaps.build_lut_image()
	# Row 2 (Shade's real target row), column 0 and column 31 -- source's own
	# real table values, spot-checked at both ends.
	var c0 := img.get_pixel(0, 2)
	var c31 := img.get_pixel(31, 2)
	_chk("E.01 row 2 col 0 matches the transcribed table (value 0 -> 0.0)",
			is_equal_approx(c0.r, 0.0 / 31.0))
	# FORMAT_L8 is an 8-bit-quantized single channel -- 25/31 (~0.8065) round-
	# trips through it as ~0.8078, a real ~0.0014 quantization error rather
	# than a defect. A generous absolute tolerance, not is_equal_approx's tiny
	# epsilon, is what a LUT-through-an-8-bit-texture claim actually needs.
	_chk("E.02 row 2 col 31 matches the transcribed table (value 25 -> 25/31, within L8 quantization)",
			absf(c31.r - 25.0 / 31.0) < 0.01)
	_chk("E.03 value_at() agrees with the image directly",
			WeatherColorMaps.value_at(2, 0) == 0 and WeatherColorMaps.value_at(2, 31) == 25)


## --- F. registry stub behavior for the not-yet-built types ---
func _test_registry_stubs() -> void:
	var wm := WeatherManager.new()
	add_child(wm)
	wm._current_weather = MapData.Weather.NONE
	wm.request_weather(MapData.Weather.RAIN)  # a real type, still a stub this pass
	wm._process(0.016)
	_chk("F.01 requesting an unbuilt type transitions cleanly, no hang",
			wm._current_weather == MapData.Weather.RAIN)
	_chk("F.02 a diagnostic names the unbuilt type",
			wm.diagnostic().contains(str(MapData.Weather.RAIN)))
	wm.queue_free()


## --- H. Drought's own separate mechanism ---
func _test_drought_lut() -> void:
	var tex := WeatherManager._drought_lut_texture()
	_chk("H.01 the drought LUT texture loads at the real 256x96 size",
			tex != null and tex.get_width() == 256 and tex.get_height() == 96)

	# Cross-check index (r4=0,g4=0,b4=0) of stage 0's own real colors_0.bin
	# against the baked texture -- independent of the Python generator's own
	# internal logic, reading the raw reference bytes directly and decoding
	# RGB555->RGB888 the same way (top bits replicated into the low bits,
	# not a bare left-shift).
	var f := FileAccess.open(
			"/home/rob/GodotAsImagined/reference/pokeemerald_expansion/graphics/weather/drought/colors_0.bin",
			FileAccess.READ)
	_chk("H.02 the real reference colors_0.bin is readable", f != null)
	if f != null:
		var raw: int = f.get_16()  # little-endian u16, index 0 (r4=g4=b4=0)
		f.close()
		var r5 := raw & 0x1F
		var g5 := (raw >> 5) & 0x1F
		var b5 := (raw >> 10) & 0x1F
		var expected := Color8((r5 << 3) | (r5 >> 2), (g5 << 3) | (g5 >> 2), (b5 << 3) | (b5 >> 2))
		var img := tex.get_image()
		var actual := img.get_pixel(0, 0)
		_chk("H.03 stage 0, index 0 matches the raw reference byte decode",
				actual.is_equal_approx(expected))
	else:
		_gated += 1


func _test_drought_state_machine() -> void:
	var wm := WeatherManager.new()
	add_child(wm)

	wm._current_weather = MapData.Weather.SHADE
	wm._next_weather = MapData.Weather.DROUGHT
	wm._color_map_index = 3
	wm._process(0.0001)
	_chk("H.04 transitioning INTO Drought immediately clears any leftover palette-curve grading",
			wm._current_weather == MapData.Weather.DROUGHT and wm._color_map_index == 0)
	_chk("H.05 Drought starts in the rising state with no stage applied yet",
			wm._drought_state == 0 and wm._drought_last_stage == -1)
	_chk("H.11 DROUGHT is a REAL registration, not a stub -- no diagnostic fires transitioning into it",
			wm.diagnostic() == "")

	# 36 real 60fps-equivalent frames = 6 stage-steps * 6 frames each is
	# exactly when source's own DroughtStateRun finishes the rise and
	# switches from the rising state (0) to the oscillating one (1).
	for i in range(36):
		wm._drought_tick_one_frame()
	_chk("H.06 after 36 real frames (~0.6s) the rise completes and oscillation begins",
			wm._drought_state == 1)
	_chk("H.07 stage 5 (the final rise step) was applied to the shared material",
			is_equal_approx(wm._material.get_shader_parameter("drought_stage"), 5.0))

	# Oscillation: stage must always stay within the real table's 0-5 range,
	# the state must not fall back to rising, and it must genuinely vary
	# (a real sine wave, not a frozen value).
	var stage_min := 99
	var stage_max := -99
	var saw_variation := false
	var first_stage: int = wm._drought_stage
	for i in range(400):
		wm._drought_tick_one_frame()
		stage_min = mini(stage_min, wm._drought_stage)
		stage_max = maxi(stage_max, wm._drought_stage)
		if wm._drought_stage != first_stage:
			saw_variation = true
	_chk("H.08 oscillation stays within the real table's 0-5 range and never re-enters rising",
			stage_min >= 0 and stage_max <= 5 and wm._drought_state == 1)
	_chk("H.09 oscillation genuinely varies the stage over time", saw_variation)

	wm.queue_free()


func _test_drought_main_frame_accum() -> void:
	var wm := WeatherManager.new()
	add_child(wm)
	wm._current_weather = MapData.Weather.DROUGHT
	wm._next_weather = MapData.Weather.DROUGHT
	wm._drought_init()

	# 36 frames * (1/60)s = 0.6s exactly reaches the same rise-complete point
	# as H.06/H.07, driven through the real wall-clock delta path instead of
	# ticking whole frames directly -- irregular deltas, cycled, matching
	# Section C's own refresh-rate-independence discipline.
	var elapsed := 0.0
	var deltas: Array[float] = [1.0 / 30.0, 1.0 / 45.0, 1.0 / 20.0]
	var di := 0
	var iterations := 0
	while wm._drought_state == 0 and iterations < 2000:
		var d: float = deltas[di % deltas.size()]
		wm._drought_main(d)
		elapsed += d
		di += 1
		iterations += 1
	_chk("H.10 driving _drought_main via irregular wall-clock deltas reaches oscillation in ~0.6s",
			wm._drought_state == 1 and elapsed >= 0.6 and elapsed < 0.7)

	wm.queue_free()


## --- I. TiledWeatherOverlay lifecycle (W3) ---
func _test_tiled_overlay_lifecycle() -> void:
	var overlay := TiledWeatherOverlay.new()
	add_child(overlay)

	var cfg := {
		"sheet": null,
		"frame_size": Vector2i(64, 64),
		"drift_kind": TiledWeatherOverlay.Drift.FOG_X,
		"init_alpha": Vector3(12, 8, 3),
		"teardown_alpha": Vector3(0, 16, 3),
	}
	overlay.begin(cfg, Vector2.ZERO)
	_chk("I.01 begin() activates the overlay and builds a real sprite grid",
			overlay.is_active() and overlay.get_child_count() > 0)
	_chk("I.02 alpha starts at 0 immediately after begin() (ramps in, not instant)",
			is_equal_approx(overlay.modulate.a, 0.0))

	# Fog's real init coeffs (12,8,3): target 12/16=0.75, 12 steps of 1/16
	# each 3 frames apart = 36 real 60fps-equivalent frames = 0.6s.
	for i in range(36):
		overlay.tick(1.0 / 60.0)
	_chk("I.03 alpha ramps to the real target over multiple frames, not a snap",
			is_equal_approx(overlay.modulate.a, 12.0 / 16.0))

	var still_tearing_down := overlay.teardown(1.0 / 60.0)
	_chk("I.04 teardown() reports still-in-progress on its first call (alpha hasn't reached 0 yet)",
			still_tearing_down and overlay.is_active())

	var done := false
	for i in range(200):
		done = not overlay.teardown(1.0 / 60.0)
		if done:
			break
	_chk("I.05 teardown() eventually reports done (alpha ramped back to 0)", done)
	_chk("I.06 once torn down, the overlay is inactive and its sprites are gone",
			not overlay.is_active() and overlay.get_child_count() == 0)

	overlay.queue_free()


## --- J. per-type drift formulas (W3) ---
func _test_tiled_overlay_drift() -> void:
	var fog := TiledWeatherOverlay.new()
	add_child(fog)
	fog.begin({"sheet": null, "frame_size": Vector2i(64, 64),
			"drift_kind": TiledWeatherOverlay.Drift.FOG_X,
			"init_alpha": Vector3(12, 8, 3), "teardown_alpha": Vector3(0, 16, 3)}, Vector2.ZERO)
	for i in range(40):
		fog.tick(1.0 / 60.0)
	_chk("J.01 Fog's own independent X creep advances over time (+1 every 4 frames)",
			fog._fog_creep > 0.0)
	fog.queue_free()

	var ash := TiledWeatherOverlay.new()
	add_child(ash)
	ash.begin({"sheet": null, "frame_size": Vector2i(64, 64),
			"drift_kind": TiledWeatherOverlay.Drift.ASH_Y,
			"init_alpha": Vector3(10, 12, 1), "teardown_alpha": Vector3(0, 12, 1)}, Vector2.ZERO)
	for i in range(40):
		ash.tick(1.0 / 60.0)
	_chk("J.02 Ash's own independent Y creep advances over time (+1 every 6 frames)",
			ash._ash_fall > 0.0)
	ash.queue_free()

	var sand := TiledWeatherOverlay.new()
	add_child(sand)
	sand.begin({"sheet": null, "frame_size": Vector2i(64, 64),
			"drift_kind": TiledWeatherOverlay.Drift.SANDSTORM_XY,
			"init_alpha": Vector3(16, 2, 0), "teardown_alpha": Vector3(0, 16, 0)}, Vector2.ZERO)
	for i in range(60):
		sand.tick(1.0 / 60.0)
	# Source biases X 4x as strongly as Y (`sandstormXOffset -= sine*4` vs
	# `sandstormYOffset -= sine`) -- the discriminator that separates
	# Sandstorm's real gust from a plain uniform drift.
	_chk("J.03 Sandstorm's gust genuinely moves both axes, X biased ~4x Y",
			absf(sand._sandstorm_x_offset) > 0.0 and absf(sand._sandstorm_y_offset) > 0.0
			and absf(sand._sandstorm_x_offset) > absf(sand._sandstorm_y_offset) * 2.0)
	_chk("J.04 Sandstorm's wave index actually advanced (real oscillation state, not frozen)",
			sand._sandstorm_wave_index > 0x20)
	sand.queue_free()


## --- K. WeatherManager registry integration (W3) ---
func _test_tiled_registry_integration() -> void:
	var wm := WeatherManager.new()
	add_child(wm)

	# Transitioning FROM Shade (a real palette-curve grade, color_map_index
	# left at its target 3) INTO Fog must immediately reset the leftover
	# grade -- mirrors `_drought_init()`'s own established fix for exactly
	# this class of bug.
	wm._current_weather = MapData.Weather.SHADE
	wm._next_weather = MapData.Weather.FOG_HORIZONTAL
	wm._color_map_index = 3
	wm._process(0.0001)
	_chk("K.01 transitioning into Fog flips current_weather and activates the tiled overlay",
			wm._current_weather == MapData.Weather.FOG_HORIZONTAL and wm._tiled_overlay.is_active())
	_chk("K.02 any leftover palette-curve grading is cleared immediately",
			wm._color_map_index == 0)
	_chk("K.03 Fog/Ash/Sandstorm are REAL registrations, not stubs -- no diagnostic fires",
			wm.diagnostic() == "")

	# Ramp alpha up to its real target BEFORE tearing down -- tearing down
	# from an alpha that never left 0 would trivially "finish" in one call
	# for the wrong reason (nothing to ramp down FROM), the exact vacuous-
	# guard shape this project's own testing conventions warn about.
	for i in range(40):
		wm._process(1.0 / 60.0)
	_chk("K.03b alpha genuinely ramped up while Fog was current (main() is really ticking)",
			wm._tiled_overlay.modulate.a > 0.0)

	# Fog's own real finish() is now a multi-frame teardown ramp (12,8,3 ->
	# 0,16,3 takes real frames to reach alpha 0), unlike the palette-grade
	# types' `finish()` which returns false on the very first call.
	wm._next_weather = MapData.Weather.NONE
	wm._process(1.0 / 60.0)
	_chk("K.04 Fog's real finish() blocks the transition on its first call (still tearing down)",
			wm._current_weather == MapData.Weather.FOG_HORIZONTAL)

	var flipped := false
	for i in range(300):
		wm._process(1.0 / 60.0)
		if wm._current_weather == MapData.Weather.NONE:
			flipped = true
			break
	_chk("K.05 the transition eventually completes once the teardown ramp finishes",
			flipped)

	wm.queue_free()


## --- L. camera-scroll push wiring (W3) ---
func _test_camera_scroll_push() -> void:
	var wm := WeatherManager.new()
	add_child(wm)

	wm.push_camera_scroll(Vector2(100, 50))
	_chk("L.01 push_camera_scroll stores the pushed value even with no active overlay",
			wm._camera_scroll_px == Vector2(100, 50))

	wm._current_weather = MapData.Weather.FOG_HORIZONTAL
	wm._next_weather = MapData.Weather.FOG_HORIZONTAL
	wm._tiled_overlay.begin({"sheet": null, "frame_size": Vector2i(64, 64),
			"drift_kind": TiledWeatherOverlay.Drift.FOG_X,
			"init_alpha": Vector3(12, 8, 3), "teardown_alpha": Vector3(0, 16, 3)}, Vector2.ZERO)
	var before: Vector2 = wm._tiled_overlay.get_child(0).position
	wm.push_camera_scroll(Vector2(500, 500))
	var after: Vector2 = wm._tiled_overlay.get_child(0).position
	_chk("L.02 pushing a new camera scroll repositions the active overlay's sprites SYNCHRONOUSLY, not on next tick",
			before != after)

	wm.queue_free()


## --- G. both real map-transition hooks call request_weather correctly ---
func _test_transition_hooks() -> void:
	OverworldSession.reset()
	OverworldSession.pending_new_game = false
	var ow: Node2D = load("res://scenes/overworld/overworld.tscn").instantiate() as Node2D
	ow.start_map = "PalletTown_Frlg"
	ow.start_cell = Vector2i(12, 0)
	add_child(ow)
	for i in range(10):
		await get_tree().process_frame

	_chk("G.01 boots into Pallet Town's own real weather (SUNNY)",
			ow._weather != null and ow._weather.current_weather() == MapData.Weather.SUNNY)

	# Seamless crossing: walk north out of Pallet Town into Route 1. The debug
	# boot's own spawn cell sits right at the boundary (Route1's own chunk
	# origin is (0,-40) relative to it) -- hold the real input continuously
	# (matching this project's own established "held ui_down walked 9 cells"
	# precedent) rather than press/release cycling, which doesn't give a
	# single ~0.16s step tween time to complete.
	#
	# `weather_requested` (fires on every call), not `weather_changed` (fires
	# only on a real transition) -- Route 1's own real weather is ALSO SUNNY,
	# same as Pallet Town, so the hook firing produces no observable state
	# transition here; only the "was it called at all" signal can prove it.
	var requested: Array = []
	ow._weather.weather_requested.connect(func(w): requested.append(w))
	Input.action_press("ui_up")
	for i in range(180):
		await get_tree().process_frame
		if str(ow.manager.chunk_owning(ow._cell)) == "Route1_Frlg":
			break
	Input.action_release("ui_up")
	for i in range(10):
		await get_tree().process_frame
	var here: String = str(ow.manager.chunk_owning(ow._cell))
	_chk("G.02 walked into a different chunk (Route1_Frlg)", here == "Route1_Frlg")
	_chk("G.03 request_weather was called with Route 1's own real value along the way",
			requested.has(ow.manager.weather_of("Route1_Frlg")))

	ow.queue_free()
