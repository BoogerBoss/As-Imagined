extends Node
## TEMPORARY — M27F Stage 1 live drive. Delete after.
var _ow: Node
func _ready() -> void:
	get_tree().create_timer(60.0).timeout.connect(func(): print("TALK: watchdog"); get_tree().quit())
	_run()
func _run() -> void:
	await get_tree().process_frame
	_ow = load("res://scenes/overworld/overworld.tscn").instantiate()
	_ow.start_map = "PalletTown_Frlg"
	get_tree().root.add_child(_ow)
	for _i in range(600):
		if _ow._player != null and not _ow.manager.loaded_chunks().is_empty(): break
		await get_tree().process_frame

	# find a scripted sign or NPC on the start map
	var target: OverworldEntity = null
	for n in _ow.manager.get_node("PalletTown_Frlg").find_children("*", "OverworldEntity", true, false):
		var e := n as OverworldEntity
		if e.script_label != "" and e.script_label != "0x0" and (e is Sign or e is NPC):
			target = e; break
	if target == null:
		print("TALK: nothing scripted here"); get_tree().quit(); return
	print("TALK: target %s '%s' at %s" % [target.get_class(), target.script_label, target.cell])

	# stand adjacent, facing it
	var origin: Vector2i = _ow.manager.origin_of("PalletTown_Frlg")
	_ow._cell = target.cell + origin + Vector2i(0, 1)   # stand south of it
	_ow._facing = StepResolver.Dir.NORTH
	print("TALK: player at %s facing NORTH" % str(_ow._cell))

	var started := [""]
	var finished := [{}]
	_ow.script_started.connect(func(l): started[0] = l)
	_ow.script_finished.connect(func(l, p, d): finished[0] = {"l": l, "p": p, "d": d})

	print("TALK: try_interact -> %s" % str(_ow.try_interact()))
	print("TALK: script_started = '%s'" % started[0])
	print("TALK: vm running = %s" % str(_ow._vm != null))
	# drive frames; the box should open and type
	for i in range(120):
		await get_tree().process_frame
		if _ow._box.is_open and not _ow._box.is_typing:
			break
	print("TALK: box open=%s page %d of %d typing=%s"
		% [str(_ow._box.is_open), _ow._box.page_index, _ow._box.page_count, str(_ow._box.is_typing)])
	if _ow._box.page_count > 0:
		print("TALK: showing -> \"%s\"" % _ow._vm.pending_pages[_ow._box.page_index].replace("\n"," / "))
	# press A through every page
	var presses := 0
	while _ow._box.is_open and presses < 20:
		presses += 1
		_ow._box.advance()
		for _j in range(40):
			await get_tree().process_frame
			if not _ow._box.is_typing: break
	print("TALK: pressed A %d times, box open=%s" % [presses, str(_ow._box.is_open)])
	for _k in range(20): await get_tree().process_frame
	print("TALK: finished = %s" % str(finished[0]))
	print("TALK: vm cleared = %s" % str(_ow._vm == null))
	get_tree().quit()
