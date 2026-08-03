extends Node
## ============ TEMPORARY DIAGNOSTIC — DELETE WHEN DONE ============
## M27D perf. Measures the FELT hitch: per-frame wall time in a real running
## overworld while the player walks the Pallet/Route1 seam and then warps into
## a building. Attributes nothing — it answers "how big is the stall, and
## when", which is the number any phase breakdown has to add up to.
##
## F6 THIS SCENE. Results go to the Output dock AND to:
##     user://frame_probe.log
## (Windows: %APPDATA%\Godot\app_userdata\<project>\frame_probe.log)
## ================================================================

var _ow: Node
var _frames: Array = []
var _last := 0
var _marks := {}
var _done := false


func _out(s: String) -> void:
	print(s)
	var f := FileAccess.open("user://frame_probe.log", FileAccess.READ_WRITE) \
			if FileAccess.file_exists("user://frame_probe.log") \
			else FileAccess.open("user://frame_probe.log", FileAccess.WRITE)
	if f != null:
		f.seek_end()
		f.store_line(s)
		f.close()


func _ready() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://frame_probe.log"))
	_out("=== FRAME PROBE START ===")
	get_tree().create_timer(120.0).timeout.connect(func(): _report("watchdog"))
	_run()


func _process(_d: float) -> void:
	var now := Time.get_ticks_usec()
	if _last != 0 and not _done:
		_frames.append([_frames.size(), (now - _last) / 1000.0])
	_last = now


func _mark(m: String) -> void:
	_marks[_frames.size()] = m
	_out("  ... frame %d: %s" % [_frames.size(), m])


func _run() -> void:
	await get_tree().process_frame
	_ow = load("res://scenes/overworld/overworld.tscn").instantiate()
	_ow.start_map = "PalletTown_Frlg"
	get_tree().root.add_child(_ow)
	for _i in range(600):
		if _ow._player != null and not _ow.manager.loaded_chunks().is_empty():
			break
		await get_tree().process_frame
	for _i in range(60):
		await get_tree().process_frame

	# --- 1. the seam. NOTE: Route 1 is loaded as a neighbour at boot, so this
	#        is expected to be free. If it spikes HERE, that is the finding.
	_mark("WALK NORTH toward the Route 1 seam")
	for i in range(26):
		_ow._try_step(StepResolver.Dir.NORTH)
		for _j in range(600):
			if not _ow._moving:
				break
			await get_tree().process_frame
		if _ow.manager.chunk_owning(_ow._cell) == "Route1_Frlg":
			_mark("CROSSED into Route1 (step %d)" % i)
			break
	for _k in range(30):
		await get_tree().process_frame

	# --- 2. a warp: unload_all + load_chunk + load_neighbours, synchronous.
	var pal: Node = _ow.manager.get_node_or_null("PalletTown_Frlg")
	if pal != null:
		var w: Warp = null
		for n in pal.find_children("*", "Warp", true, false):
			var ww := n as Warp
			if ww.triggers and MapConstants.is_baked(ww.dest_map):
				w = ww
				break
		if w != null:
			_mark("WARP -> %s" % w.dest_map)
			await _ow._do_warp(w)
			_mark("WARP DONE")
			for _k2 in range(40):
				await get_tree().process_frame
	_report("done")


func _report(why: String) -> void:
	if _done:
		return
	_done = true
	var sum := 0.0
	var worst := 0.0
	var worst_i := -1
	for f in _frames:
		sum += float(f[1])
		if float(f[1]) > worst:
			worst = float(f[1])
			worst_i = int(f[0])
	var mean: float = sum / max(1, _frames.size())
	_out("")
	_out("=== FRAME PROBE (%s) ===" % why)
	_out("frames: %d   mean: %.2f ms   worst: %.2f ms (frame %d)"
			% [_frames.size(), mean, worst, worst_i])
	# 20 ms ~= a dropped frame at 60fps; 12 ms is already a dropped frame at
	# this machine's ~144 Hz, so report those too.
	var over := []
	for f in _frames:
		if float(f[1]) > 12.0:
			over.append(f)
	_out("frames over 12 ms: %d" % over.size())
	for f in over:
		var lbl := ""
		for k in _marks:
			if abs(int(k) - int(f[0])) <= 3:
				lbl = "   <- near: %s" % _marks[k]
		_out("   frame %-5d %8.2f ms%s" % [int(f[0]), float(f[1]), lbl])
	_out("marks:")
	for k in _marks:
		_out("   frame %-5d %s" % [int(k), _marks[k]])
	_out("log written to: %s" % ProjectSettings.globalize_path("user://frame_probe.log"))
	_out("=== END ===")
	get_tree().quit()
