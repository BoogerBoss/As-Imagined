extends Node
## ============ TEMPORARY DIAGNOSTIC — DELETE WHEN DONE ============
## Probe 2: (a) static shots of the WEST and EAST skirt corners at the
## Pallet/Route 1 seam — the strips the center-path walk never showed;
## (b) capture the FIRST northward crossing and a SECOND one from the same
## start cell, so first-entry-only artifacts can be told apart from
## every-crossing artifacts.
## ================================================================

const OUT := "/tmp/claude-1000/-home-rob-GodotAsImagined/e00a7d65-8dc7-43c2-8b53-6a2ba92670f3/scratchpad/seam_shots2"

var _ow: Node


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	get_tree().create_timer(120.0).timeout.connect(func() -> void: get_tree().quit())
	_run()


func _teleport(gcell: Vector2i) -> void:
	_ow._cell = gcell
	_ow._elev = _ow.manager.elevation_at(gcell)
	_ow._reparent_for_elevation()
	_ow._player.position = _ow.manager.local_pixel_of(gcell)
	if _ow._camera != null:
		_ow._camera.global_position = _ow._player.global_position
		_ow._camera.reset_smoothing()


func _shot(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [OUT, name])


func _walk_north(tag: String, frames: int) -> void:
	Input.action_press("ui_up")
	for i in range(frames):
		await get_tree().process_frame
		_shot("%s_%03d" % [tag, i])
	Input.action_release("ui_up")


func _walk_south(steps: int) -> void:
	Input.action_press("ui_down")
	for _i in range(steps * 40):
		await get_tree().process_frame
	Input.action_release("ui_down")


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

	# --- (b) FIRST crossing from the spawn cell, BEFORE any teleporting ---
	print("SEAMPROBE2 first crossing from %s" % _ow._cell)
	await _walk_north("first", 70)
	# back south to the start cell, then cross again
	await _walk_south(6)
	print("SEAMPROBE2 back at %s in %s" % [_ow._cell,
			_ow.manager.chunk_owning(_ow._cell)])
	# walk to the same column/row as the first run if drift happened
	await get_tree().process_frame
	_teleport(Vector2i(12, 0))
	for _i in range(20):
		await get_tree().process_frame
	print("SEAMPROBE2 second crossing from %s" % _ow._cell)
	await _walk_north("second", 70)

	# --- (a) static corner shots ---
	_teleport(Vector2i(3, -2))
	for _i in range(10):
		await get_tree().process_frame
	_shot("west_corner")
	_teleport(Vector2i(20, -2))
	for _i in range(10):
		await get_tree().process_frame
	_shot("east_corner")
	_teleport(Vector2i(3, 3))
	for _i in range(10):
		await get_tree().process_frame
	_shot("west_corner_south")
	print("SEAMPROBE2 done")
	get_tree().quit()
