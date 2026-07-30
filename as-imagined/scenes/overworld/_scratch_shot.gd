extends Node
func _ready() -> void:
	var ow: Node2D = load("res://scenes/overworld/overworld.tscn").instantiate()
	add_child(ow)
	await get_tree().process_frame
	var mm = ow.manager
	var o: Vector2i = mm.origin_of("PalletTown_Frlg")
	ow._cell = o + Vector2i(12, 11)
	ow._elev = mm.elevation_at(ow._cell)
	ow._reparent_for_elevation()
	ow._player.position = mm.local_pixel_of(ow._cell)
	ow._camera.global_position = ow._player.global_position
	ow._camera.reset_smoothing()
	for i in range(8): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/d1_final.png")
	print("saved")
	get_tree().quit()
