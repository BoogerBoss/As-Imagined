extends Node
## ============ TEMPORARY DIAGNOSTIC — DELETE WHEN DONE ============
## M27D perf. Per-phase timing of first-visit map entry. Replicates
## MapManager.load_chunk/_install_chunk phase for phase so each is timed
## separately, then cross-checks against a REAL load_chunk so the replication
## is provably faithful rather than assumed.
##
## F6 THIS SCENE. Results go to the Output dock AND to:
##     user://phase_probe.log
##
## KNOWN LIMITATION, stated up front: phase 4 (add_child) measured ~0.00 ms on
## the Linux/llvmpipe machine this was written on, which is not credible —
## TileMapLayer defers its quadrant build to the first DRAW, which a probe that
## never renders a frame does not trigger. If phase 4 is also ~0 here, the real
## cost is in rendering and _frame_probe.tscn is the probe that will see it.
## ================================================================

const MAPS := ["PalletTown_Frlg", "ViridianForest_Frlg"]


func _out(s: String) -> void:
	print(s)
	var f := FileAccess.open("user://phase_probe.log", FileAccess.READ_WRITE) \
			if FileAccess.file_exists("user://phase_probe.log") \
			else FileAccess.open("user://phase_probe.log", FileAccess.WRITE)
	if f != null:
		f.seek_end()
		f.store_line(s)
		f.close()


func _ready() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://phase_probe.log"))
	_out("=== PHASE PROBE START ===")
	_run()


func _run() -> void:
	await get_tree().process_frame

	var t_pre := Time.get_ticks_usec()
	var n := MapManager.preload_tilesets(MapManager.TILESET_DIR, false)
	_out("boot preload: %d pairs, %.1f ms" % [n, (Time.get_ticks_usec() - t_pre) / 1000.0])
	_out("")

	for map_name in MAPS:
		await _probe(map_name)

	_out("log written to: %s" % ProjectSettings.globalize_path("user://phase_probe.log"))
	_out("=== END ===")
	get_tree().quit()


func _probe(map_name: String) -> void:
	var scene_path := "res://scenes/maps/%s.tscn" % map_name
	var data_path := "res://scenes/maps/%s_data.tres" % map_name
	if not (ResourceLoader.exists(scene_path) and ResourceLoader.exists(data_path)):
		_out("%s: not baked, skipped" % map_name)
		return

	# STEP 0 — is the pair TileSet actually a preload hit?
	var peek := ResourceLoader.load(data_path) as MapData
	var atlas := peek.atlas
	var ts_cached := ResourceLoader.has_cached(MapManager.TILESET_DIR + atlas + ".tres")
	var held := MapManager.preloaded_tileset(atlas) != null

	var t_all := Time.get_ticks_usec()

	var t0 := Time.get_ticks_usec()
	var data := ResourceLoader.load(data_path, "", ResourceLoader.CACHE_MODE_IGNORE) as MapData
	var ms_data := (Time.get_ticks_usec() - t0) / 1000.0

	t0 = Time.get_ticks_usec()
	var packed := ResourceLoader.load(scene_path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var ms_scene := (Time.get_ticks_usec() - t0) / 1000.0

	t0 = Time.get_ticks_usec()
	var root: Node2D = packed.instantiate() as Node2D
	var ms_inst := (Time.get_ticks_usec() - t0) / 1000.0

	var mm := MapManager.new()
	add_child(mm)

	# SPLIT add_child: detach the entity strata first, so tree-entry of the
	# three TileMapLayers is timed separately from every entity's own _ready
	# (which is where sprite sheets are loaded and Sprite2D nodes built).
	var strata: Array[Node] = []
	for nm in ["Entities_P1", "Entities_P2"]:
		var s := root.get_node_or_null(nm)
		if s != null:
			# Clear the owner before detaching, or re-adding warns about an
			# inconsistent owner. Harmless here (nothing re-packs this scene)
			# but a noisy probe is a worse handoff than a quiet one.
			s.owner = null
			root.remove_child(s)
			strata.append(s)

	t0 = Time.get_ticks_usec()
	mm.add_child(root)
	var ms_add_layers := (Time.get_ticks_usec() - t0) / 1000.0

	t0 = Time.get_ticks_usec()
	for s in strata:
		root.add_child(s)
	var ms_add_ents := (Time.get_ticks_usec() - t0) / 1000.0
	var ms_add := ms_add_layers + ms_add_ents

	t0 = Time.get_ticks_usec()
	mm.register_chunk(map_name, data, root, Vector2i.ZERO)
	var ms_reg := (Time.get_ticks_usec() - t0) / 1000.0

	t0 = Time.get_ticks_usec()
	mm.refresh_skirts_near(mm.chunk_rect(map_name))
	var ms_skirt := (Time.get_ticks_usec() - t0) / 1000.0

	# Let a frame actually DRAW, then time it — this is where TileMapLayer
	# builds quadrants, and it is what the headless probe could not see.
	var t_draw := Time.get_ticks_usec()
	await get_tree().process_frame
	await get_tree().process_frame
	var ms_draw := (Time.get_ticks_usec() - t_draw) / 1000.0

	var ents := root.find_children("*", "OverworldEntity", true, false).size()
	var ms_total := (Time.get_ticks_usec() - t_all) / 1000.0
	var accounted := ms_data + ms_scene + ms_inst + ms_add + ms_reg + ms_skirt + ms_draw

	_out("%s  cells=%d entities=%d  tileset_cached=%s held=%s"
			% [map_name, data.width * data.height, ents, ts_cached, held])
	_out("   1 .tscn load        %8.2f ms" % ms_scene)
	_out("   2 .tres load        %8.2f ms" % ms_data)
	_out("   3 instantiate       %8.2f ms" % ms_inst)
	_out("   4 add_child TOTAL   %8.2f ms" % ms_add)
	_out("     4a tilemap layers %8.2f ms   <- 3 TileMapLayers entering tree" % ms_add_layers)
	_out("     4b entity _ready  %8.2f ms   <- %d entities: sprites + nodes" % [ms_add_ents, ents])
	_out("   5 skirt paint       %8.2f ms" % ms_skirt)
	_out("   6 register/occup    %8.2f ms" % ms_reg)
	_out("   4c first 2 frames  %8.2f ms   <- first DRAW of those layers" % ms_draw)
	_out("   7 unaccounted       %8.2f ms" % (ms_total - accounted))
	_out("   = TOTAL             %8.2f ms" % ms_total)

	mm.free()

	var mm2 := MapManager.new()
	add_child(mm2)
	var t_real := Time.get_ticks_usec()
	mm2.load_chunk(map_name, Vector2i.ZERO)
	_out("   (real load_chunk, caches warm: %.2f ms)"
			% ((Time.get_ticks_usec() - t_real) / 1000.0))
	mm2.free()
	_out("")
