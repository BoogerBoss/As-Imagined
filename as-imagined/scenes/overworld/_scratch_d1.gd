extends Node
func _ready() -> void:
	var ow: Node2D = load("res://scenes/overworld/overworld.tscn").instantiate()
	add_child(ow)
	await get_tree().process_frame
	await get_tree().process_frame
	var mm = ow.manager
	var withspr := 0; var without := 0; var fell_back := 0
	var missing: Array[String] = []
	for map_name in mm.loaded_chunks():
		for n in mm.get_node(map_name).find_children("*", "OverworldEntity", true, false):
			var e := n as OverworldEntity
			var gid: String = e.sprite_graphics_id()
			if gid == "": continue
			if e.get_node_or_null("Sprite") != null: withspr += 1
			else: without += 1; missing.append(gid)
			if not ObjectEventGraphics.is_known(gid):
				fell_back += 1
				if not missing.has(gid): missing.append(gid)
	print("entities with a sprite : ", withspr)
	print("entities without       : ", without)
	print("ids falling back       : ", fell_back, "  ", missing)
	# a real NPC's frame + facing
	for map_name in mm.loaded_chunks():
		for n in mm.get_node(map_name).find_children("*", "NPC", true, false):
			var e := n as NPC
			var s := e.get_node_or_null("Sprite") as Sprite2D
			if s != null:
				print("sample: %s mv=%s facing=%s frame_y=%d flip=%s size=%s"
						% [e.graphics_id, e.movement_type, e.initial_facing(),
						int(s.region_rect.position.y), s.flip_h, s.region_rect.size])
				get_tree().quit(); return
	get_tree().quit()
