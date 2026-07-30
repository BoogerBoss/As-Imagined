extends Node
func _ready() -> void:
	var ow: Node2D = load("res://scenes/overworld/overworld.tscn").instantiate()
	add_child(ow)
	await get_tree().process_frame
	await get_tree().process_frame
	var mm = ow.manager
	ow._rng.seed = 12345
	# snapshot every NPC's spawn + range
	var watch := []
	for map_name in mm.loaded_chunks():
		for n in mm.get_node(map_name).find_children("*", "NPC", true, false):
			var e := n as NPC
			watch.append({"npc": e, "map": map_name, "spawn": e.cell,
					"mv": e.movement_type, "rx": e.range_x, "ry": e.range_y})
	print("watching %d NPCs for 8 seconds" % watch.size())
	await get_tree().create_timer(8.0).timeout
	var moved := 0; var still := 0; var escaped := []
	for w in watch:
		var e: NPC = w["npc"]
		if e.cell != w["spawn"]: moved += 1
		else: still += 1
		var dx: int = absi(e.cell.x - w["spawn"].x)
		var dy: int = absi(e.cell.y - w["spawn"].y)
		if (w["rx"] != 0 and dx > w["rx"]) or (w["ry"] != 0 and dy > w["ry"]):
			escaped.append("%s %s spawn=%s now=%s range=(%d,%d)"
					% [w["mv"], e.graphics_id, w["spawn"], e.cell, w["rx"], w["ry"]])
	print("  moved from spawn : ", moved)
	print("  never moved      : ", still)
	print("  LEFT THEIR RANGE : ", escaped.size(), escaped)
	# occupancy must still be true after all that moving
	var wrong := 0
	for w in watch:
		var e: NPC = w["npc"]
		if not mm.entity_at(mm.origin_of(w["map"]) + e.cell): wrong += 1
	print("  occupancy wrong after moving: ", wrong)
	# no two NPCs sharing a cell
	var seen := {}; var dup := 0
	for w in watch:
		var g: Vector2i = mm.origin_of(w["map"]) + (w["npc"] as NPC).cell
		if seen.has(g): dup += 1
		seen[g] = true
	print("  NPCs sharing a cell: ", dup)
	# breakdown by movement type
	var by := {}
	for w in watch:
		var k: String = w["mv"]
		if not by.has(k): by[k] = [0, 0]
		by[k][0] += 1
		if (w["npc"] as NPC).cell != w["spawn"]: by[k][1] += 1
	for k in by: print("    %-40s %d total, %d moved" % [k, by[k][0], by[k][1]])
	get_tree().quit()
