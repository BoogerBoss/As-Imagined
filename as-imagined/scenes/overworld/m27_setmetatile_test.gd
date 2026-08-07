extends Node

## [Corridor op-code scope] `setmetatile` (`ScrCmd_setmetatile`, `scrcmd.c:2741`)
## — the one real subsystem-shaped item from the two trivial/documented-no-op
## fixes. Three layers, each with its own real failure mode:
##
##   * `MetatileLabels.id_of` — a METATILE_* constant resolves to the SAME
##     absolute id `MapData.metatile`/the atlas coord math already use.
##   * `MapManager.set_metatile` — collision force + the per-plane routing.
##     THE routing is the load-bearing part: `[M27C C3]`/`[M27M]` both paid
##     for "painted a NORMAL metatile into Ground alone, half the block never
##     renders" already, so every assertion below checks ALL THREE planes,
##     not just the ones expected to hold content — a routing bug that
##     leaves stale art in the WRONG plane is invisible to a test that only
##     checks the right one.
##   * `ScriptVM`'s own `setmetatile` opcode — queues rather than acts
##     (the VM has no scene-tree access), and every arg goes through
##     `_resolve_number` since source reads all four via `VarGet`.

const EXPECTED_TOTAL := 19

var _total := 0
var _failed := 0
var _gated := 0


func _chk(label: String, cond: bool) -> void:
	_total += 1
	if not cond:
		_failed += 1
		print("FAILED: %s" % label)


func _ready() -> void:
	_test_metatile_labels()
	_test_set_metatile_routing()
	_test_vm_opcode()
	_test_real_corpus()
	var accounted := _total + _gated
	_chk("Z.99 every expected assertion ran (%d + %d gated == %d)"
			% [_total, _gated, EXPECTED_TOTAL], accounted == EXPECTED_TOTAL)
	print("m27_setmetatile_test: %d/%d passed" % [_total - _failed, _total])
	get_tree().quit()


## --- A. MetatileLabels ---
func _test_metatile_labels() -> void:
	_chk("A.01 the corridor's own two real uses resolve to source's exact ids",
			MetatileLabels.id_of("METATILE_Mart_CounterMid_Top") == 703
			and MetatileLabels.id_of("METATILE_Mart_CounterMid_Bottom") == 704)
	_chk("A.02 an unknown constant degrades to 0, not a crash",
			MetatileLabels.id_of("METATILE_Not_A_Real_Thing") == 0)
	_chk("A.03 the full table is really generated, not a hand-picked pair",
			MetatileLabels.ID_BY_NAME.size() > 900)


## A minimal chunk: a MapData plus a real Node2D root carrying Ground/
## Objects/Overhangs TileMapLayers, each sharing one small TileSet whose
## source_id equals its own plane index -- exactly production's convention
## (`_paint_skirt`'s own doc comment: "the plane index doubles as the source
## id").
func _make_chunk(atlas_name: String) -> Dictionary:
	var d := MapData.new()
	d.width = 4
	d.height = 4
	d.collision = PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
	d.atlas = atlas_name

	var ts := TileSet.new()
	for i in range(3):
		var src := TileSetAtlasSource.new()
		src.texture = ImageTexture.create_from_image(
				Image.create(32 * 16, 16, false, Image.FORMAT_RGBA8))
		ts.add_source(src, i)

	var root := Node2D.new()
	for nm in ["Ground", "Objects", "Overhangs"]:
		var layer := TileMapLayer.new()
		layer.name = nm
		layer.tile_set = ts
		root.add_child(layer)

	return {"data": d, "root": root}


## --- B. MapManager.set_metatile ---
func _test_set_metatile_routing() -> void:
	# The real Mart pair: id 703 is NORMAL (objects+overhangs, no ground),
	# id 704 is COVERED (ground+objects, no overhangs) -- confirmed while
	# scoping this, and it's why one fixture with only ONE id would not have
	# proven the routing actually branches.
	if not FileAccess.file_exists("res://assets/map_atlases/building_frlg__mart_frlg_layer_types.json"):
		_gated += 11
		return

	var chunk := _make_chunk("building_frlg__mart_frlg")
	var d: MapData = chunk["data"]
	var root: Node2D = chunk["root"]
	var mm := MapManager.new()
	mm.register_chunk("Mart", d, root, Vector2i.ZERO)

	var ground: TileMapLayer = root.get_node("Ground")
	var objects: TileMapLayer = root.get_node("Objects")
	var overhangs: TileMapLayer = root.get_node("Overhangs")

	var ok703 := mm.set_metatile(Vector2i(1, 1), 703, true)
	_chk("B.01 set_metatile reports success for an owned cell", ok703)
	_chk("B.02 impassable=true forces collision solid",
			d.collision[1 * 4 + 1] == 1)
	# id 703 is NORMAL: objects(1) + overhangs(2), ground ERASED.
	var coords703 := Vector2i(703 % 32, int(703 / 32))
	_chk("B.03 NORMAL paints Objects", objects.get_cell_atlas_coords(Vector2i(1, 1)) == coords703
			and objects.get_cell_source_id(Vector2i(1, 1)) == 1)
	_chk("B.04 NORMAL paints Overhangs", overhangs.get_cell_atlas_coords(Vector2i(1, 1)) == coords703
			and overhangs.get_cell_source_id(Vector2i(1, 1)) == 2)
	_chk("B.05 and NORMAL leaves Ground erased -- the exact 'half the block "
			+ "never renders' trap this project has already paid for twice",
			ground.get_cell_source_id(Vector2i(1, 1)) == -1)

	var ok704 := mm.set_metatile(Vector2i(2, 2), 704, false)
	_chk("B.06 a second call on a different cell also succeeds", ok704)
	_chk("B.07 impassable=false leaves collision walkable",
			d.collision[2 * 4 + 2] == 0)
	# id 704 is COVERED: ground(0) + objects(1), overhangs ERASED.
	var coords704 := Vector2i(704 % 32, int(704 / 32))
	_chk("B.08 COVERED paints Ground", ground.get_cell_atlas_coords(Vector2i(2, 2)) == coords704
			and ground.get_cell_source_id(Vector2i(2, 2)) == 0)
	_chk("B.09 COVERED paints Objects", objects.get_cell_atlas_coords(Vector2i(2, 2)) == coords704
			and objects.get_cell_source_id(Vector2i(2, 2)) == 1)
	_chk("B.10 and COVERED leaves Overhangs erased -- the discriminator that "
			+ "proves routing actually branches per id, not a fixed plane set",
			overhangs.get_cell_source_id(Vector2i(2, 2)) == -1)

	_chk("B.11 an unowned cell refuses rather than crashing",
			not mm.set_metatile(Vector2i(99, 99), 703, true))

	mm.free()
	root.free()


## --- C. the VM opcode itself ---
func _test_vm_opcode() -> void:
	var flags := FlagStore.new()
	flags.var_set("VAR_TEMP_0", 9)
	var vm := ScriptVM.new(_src({
		"A": [_op("setmetatile", ["1", "VAR_TEMP_0", "METATILE_Mart_CounterMid_Top", "1"]),
				_op("end")],
	}), flags)
	vm.start("A")
	_run(vm)
	_chk("C.01 setmetatile queues rather than halting -- the VM has no "
			+ "scene-tree access to apply it directly",
			vm.pause_reason == ScriptVM.Pause.DONE
			and vm.pending_object_ops.size() == 1)
	var queued: Dictionary = vm.pending_object_ops[0]
	_chk("C.02 every arg resolved through _resolve_number: a literal x, a "
			+ "VAR for y, and the METATILE_* constant for metatile_id",
			queued.get("op") == "setmetatile" and queued.get("x") == 1
			and queued.get("y") == 9 and queued.get("metatile_id") == 703
			and queued.get("impassable") == true)

	var vm_short := ScriptVM.new(_src({
		"A": [_op("setmetatile", ["1", "2", "3"]), _op("end")],
	}), FlagStore.new())
	vm_short.start("A")
	_run(vm_short)
	_chk("C.03 too few args is UNKNOWN_OP, not a crash",
			vm_short.pause_reason == ScriptVM.Pause.UNKNOWN_OP
			and vm_short.diagnostic.contains("setmetatile"))


## --- D. the real compiled corridor script ---
func _test_real_corpus() -> void:
	if not (FileAccess.file_exists("res://data/map_scripts.json")
			and FileAccess.file_exists("res://data/map_texts.json")):
		_gated += 2
		return
	var ops: Dictionary = JSON.parse_string(
			FileAccess.open("res://data/map_scripts.json", FileAccess.READ).get_as_text())
	var texts: Dictionary = JSON.parse_string(
			FileAccess.open("res://data/map_texts.json", FileAccess.READ).get_as_text())
	var vm := ScriptVM.new(_src(ops, texts), FlagStore.new())
	vm.start("ViridianCity_Mart_EventScript_HideQuestionnaire")
	_run(vm)
	_chk("D.01 the real script runs to DONE and queues both real calls",
			vm.pause_reason == ScriptVM.Pause.DONE
			and vm.pending_object_ops.size() == 2)
	_chk("D.02 both resolve to their real ids (703 top, 704 bottom), both "
			+ "forcing the counter solid",
			vm.pending_object_ops[0].get("metatile_id") == 703
			and vm.pending_object_ops[0].get("impassable") == true
			and vm.pending_object_ops[1].get("metatile_id") == 704
			and vm.pending_object_ops[1].get("impassable") == true)


## --- helpers, mirroring m27f_script_vm_test.gd's own shape ---
func _op(op_name: String, args: Array = []) -> Dictionary:
	return {"op": op_name, "args": args}


func _src(ops: Dictionary, texts: Dictionary = {}) -> ScriptVM.ScriptSource:
	var s := ScriptVM.ScriptSource.new()
	s.ops_by_label = ops
	s.texts = texts
	return s


## Drive through message/button waits too, matching m27f_script_vm_test.gd's
## own `_drive` -- the real Mart script prints text before the setmetatile
## pair, and a plain `_run` would stall on the first WAIT_MESSAGE.
func _run(vm: ScriptVM, limit: int = 400) -> void:
	var n := 0
	while n < limit:
		if vm.step():
			n += 1
			continue
		if vm.pause_reason == ScriptVM.Pause.WAIT_MESSAGE \
				or vm.pause_reason == ScriptVM.Pause.WAIT_BUTTON:
			vm.resume()
			n += 1
			continue
		break
