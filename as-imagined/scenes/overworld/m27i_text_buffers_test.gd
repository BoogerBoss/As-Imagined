extends Node

## [M27I I2] Text buffers and placeholder expansion.
##
## The property that matters most is EXPANSION AT PRINT TIME: a script buffers,
## prints, re-buffers and prints again, and the second print must show the
## second value. Expanding when the `message` opcode runs instead would freeze
## the first, and that is invisible until a script reuses a slot -- which most
## of the corpus does (STR_VAR_1 is written 176 times and read 1369).

const EXPECTED_TOTAL := 41

var _total := 0
var _failed := 0
var _gated := 0


func _chk(label: String, cond: bool) -> void:
	_total += 1
	if not cond:
		_failed += 1
		print("FAILED: %s" % label)


func _src(ops: Dictionary, texts: Dictionary = {}) -> ScriptVM.ScriptSource:
	var s := ScriptVM.ScriptSource.new()
	s.ops_by_label = ops
	s.texts = texts
	return s


func _op(name: String, args: Array = []) -> Dictionary:
	return {"op": name, "args": args}


func _ready() -> void:
	_test_slots()
	_test_expansion()
	_test_opcodes()
	_test_print_time()
	_test_corpus()
	_test_production_path()

	var accounted := _total + _gated
	_chk("Z.99 every expected assertion ran (%d + %d gated == %d)"
			% [_total, _gated, EXPECTED_TOTAL], accounted == EXPECTED_TOTAL)
	print("m27i_text_buffers_test: %d/%d passed" % [_total - _failed, _total])
	get_tree().quit()


## --- A. the three slots ---
func _test_slots() -> void:
	var b := TextBuffers.new()
	_chk("A.01 there are exactly three, as in source", TextBuffers.SLOTS == 3)
	_chk("A.02 they start empty", b.get_slot(0) == "" and b.get_slot(2) == "")
	b.set_slot(0, "POTION")
	_chk("A.03 a slot holds what was put in it", b.get_slot(0) == "POTION")
	_chk("A.04 and the others are untouched", b.get_slot(1) == "")
	# ⚠️ Both spellings are real: scripts mostly write STR_VAR_1, but the corpus
	# also carries a bare `0`. Handling only the named form drops those.
	_chk("A.05 named slots resolve",
			TextBuffers.slot_index("STR_VAR_1") == 0
			and TextBuffers.slot_index("STR_VAR_2") == 1
			and TextBuffers.slot_index("STR_VAR_3") == 2)
	_chk("A.06 a bare numeric slot resolves too", TextBuffers.slot_index("0") == 0)
	_chk("A.07 nonsense resolves to no slot", TextBuffers.slot_index("STR_VAR_9") == -1)
	b.set_slot(-1, "x")
	b.set_slot(99, "x")
	_chk("A.08 writing outside the range is a no-op, not a crash",
			b.get_slot(0) == "POTION")
	b.clear()
	_chk("A.09 clear empties all three",
			b.get_slot(0) == "" and b.get_slot(1) == "" and b.get_slot(2) == "")


## --- B. expansion ---
func _test_expansion() -> void:
	var b := TextBuffers.new()
	b.set_slot(0, "POTION")
	b.set_slot(1, "5")
	_chk("B.01 a single marker expands", b.expand("Got {STR_VAR_1}!") == "Got POTION!")
	_chk("B.02 several markers in one page expand",
			b.expand("{STR_VAR_2} x {STR_VAR_1}") == "5 x POTION")
	_chk("B.03 text without markers is returned untouched",
			b.expand("plain text") == "plain text")
	_chk("B.04 an empty slot expands to nothing, not to its own name",
			b.expand("[{STR_VAR_3}]") == "[]")
	# ⚠️ Source's own rule: an unknown placeholder id expands to EMPTY
	# (GetExpandedPlaceholder falls through to gText_ExpandedPlaceholder_Empty).
	# Leaving a raw {KUN} mid-sentence would read as a bug to a player.
	_chk("B.05 {KUN} is genuinely empty in English", b.expand("Hi{KUN}!") == "Hi!")
	_chk("B.06 an unknown marker expands to empty rather than surviving",
			b.expand("a{NO_SUCH_THING}b") == "ab")
	_chk("B.07 a control marker is dropped, not printed",
			b.expand("x{PLAY_BGM}y") == "xy")
	# Identity placeholders: no player-naming system yet (M27K).
	_chk("B.08 {PLAYER} expands to the placeholder identity",
			b.expand("{PLAYER}") == TextBuffers.PLAYER_NAME)
	_chk("B.09 and matches the overworld sprite's own choice",
			TextBuffers.PLAYER_NAME == "LEAF")
	# Malformed input must not hang or truncate the rest of the page.
	_chk("B.10 an unclosed brace is left alone rather than eating the page",
			b.expand("a{STR_VAR_1") == "a{STR_VAR_1")
	_chk("B.11 a stray closing brace survives", b.expand("a}b") == "a}b")


## --- C. the buffer opcodes ---
func _test_opcodes() -> void:
	var flags := FlagStore.new()
	var vm := ScriptVM.new(_src({
		"A": [_op("bufferitemname", ["STR_VAR_1", "ITEM_POTION"]),
			_op("bufferstdstring", ["STR_VAR_3", "STDSTRING_ITEMS"]),
			_op("buffernumberstring", ["STR_VAR_2", "7"]),
			_op("end")],
	}), flags)
	vm.start("A")
	vm.step(); vm.step(); vm.step()
	_chk("C.01 bufferitemname writes the item's real name",
			vm.buffers.get_slot(0) == "Potion")
	_chk("C.02 bufferstdstring writes source's own std string",
			vm.buffers.get_slot(2) == "ITEMS")
	_chk("C.03 buffernumberstring writes the number as text",
			vm.buffers.get_slot(1) == "7")

	# ⚠️ THE VARIABLE FORM. 64 corpus args are variables, not constants, and
	# they cluster in exactly the give-and-branch chains this exists for.
	flags.var_set("VAR_0x8009", PokemonRegistry.item_id_of("ITEM_POKE_BALL"))
	var vm2 := ScriptVM.new(_src({
		"A": [_op("bufferitemname", ["STR_VAR_1", "VAR_0x8009"]), _op("end")],
	}), flags)
	vm2.start("A")
	vm2.step()
	_chk("C.04 an item held in a VARIABLE resolves",
			vm2.buffers.get_slot(0) == "Poké Ball")

	# A TM must resolve through I1's bridge, not come back blank.
	var vm3 := ScriptVM.new(_src({
		"A": [_op("bufferitemname", ["STR_VAR_1", "ITEM_TM39"]), _op("end")],
	}), FlagStore.new())
	vm3.start("A")
	vm3.step()
	_chk("C.05 a TM resolves through the items.json gap", vm3.buffers.get_slot(0) == "TM39")

	# Plural: source appends a suffix when the count is not one.
	var vm4 := ScriptVM.new(_src({
		"A": [_op("bufferitemnameplural", ["STR_VAR_1", "ITEM_POTION", "2"]), _op("end")],
	}), FlagStore.new())
	vm4.start("A")
	vm4.step()
	_chk("C.06 a plural count pluralises", vm4.buffers.get_slot(0) == "Potions")

	var vm5 := ScriptVM.new(_src({
		"A": [_op("bufferitemname", ["STR_VAR_1", "ITEM_NOT_REAL"]), _op("end")],
	}), FlagStore.new())
	vm5.start("A")
	vm5.step()
	_chk("C.07 an unresolvable item blanks the slot rather than crashing",
			vm5.buffers.get_slot(0) == "")
	_chk("C.08 and the script keeps running", vm5.pause_reason != ScriptVM.Pause.UNKNOWN_OP)


## --- D. print-time expansion. THE property. ---
func _test_print_time() -> void:
	var b := TextBuffers.new()
	var page := "You got {STR_VAR_1}!"
	b.set_slot(0, "POTION")
	var first := b.expand(page)
	b.set_slot(0, "ETHER")
	var second := b.expand(page)
	# ⚠️ If expansion happened when the message opcode RAN rather than when the
	# page is shown, `second` would still read POTION. That is the whole reason
	# this is expanded at the box rather than in the VM.
	_chk("D.01 re-buffering changes what the SAME page expands to",
			first == "You got POTION!" and second == "You got ETHER!")
	_chk("D.02 and the source text itself is never mutated",
			page == "You got {STR_VAR_1}!")

	# The std-string table, which the obtain-item flow uses for the pocket name.
	_chk("D.03 pocket names come from source's own table",
			b.std_string("STDSTRING_ITEMS") == "ITEMS"
			and b.std_string("STDSTRING_KEYITEMS") == "KEY ITEMS")
	_chk("D.04 an unknown std string is empty rather than raw",
			b.std_string("STDSTRING_NOPE") == "")


## --- E. against the real corpus ---
func _test_corpus() -> void:
	if not FileAccess.file_exists("res://data/map_texts.json"):
		_gated += 4
		return
	var texts: Dictionary = JSON.parse_string(
			FileAccess.open("res://data/map_texts.json", FileAccess.READ).get_as_text())
	var b := TextBuffers.new()
	b.set_slot(0, "A")
	b.set_slot(1, "B")
	b.set_slot(2, "C")
	# Every marker in every real page must expand away. A survivor is a raw
	# `{...}` shown to the player.
	var leftovers := {}
	var pages := 0
	for label in texts:
		for page in texts[label]:
			pages += 1
			var out := b.expand(str(page))
			var at := out.find("{")
			while at >= 0:
				var close := out.find("}", at)
				if close < 0:
					break
				leftovers[out.substr(at, close - at + 1)] = true
				at = out.find("{", close)
	_chk("E.01 the corpus has a real amount of text", pages > 10000)
	_chk("E.02 no marker survives expansion anywhere (%d kinds left: %s)"
			% [leftovers.size(), str(leftovers.keys().slice(0, 5))], leftovers.is_empty())
	# And the buffers genuinely reach the text: some page must actually change.
	var changed := 0
	for label in texts:
		for page in texts[label]:
			if b.expand(str(page)) != str(page):
				changed += 1
	_chk("E.03 expansion actually changes a real number of pages", changed > 2000)
	_chk("E.04 a page with no markers is returned identical",
			b.expand("nothing here") == "nothing here")


## --- F. the production path: does expansion reach the box? ---
func _test_production_path() -> void:
	# ⚠️ Everything above tests TextBuffers. This tests the wiring — that the
	# overworld expands its pending pages before handing them to the box. A
	# correct expander that nobody calls shows raw {STR_VAR_1} to the player,
	# and no assertion on TextBuffers alone would notice.
	var ow: Node2D = load("res://scenes/overworld/overworld.tscn").instantiate() as Node2D
	# Deliberately NOT added to the tree: _ready() would boot the whole region.
	# The bare-instance pattern this project already uses for BattleScreen.
	var vm := ScriptVM.new(_src({"A": [_op("end")]},
			{"T": ["You got {STR_VAR_1}!"]}), FlagStore.new())
	vm.pending_pages = PackedStringArray(["You got {STR_VAR_1}!", "{PLAYER} smiled."])
	vm.buffers.set_slot(0, "TM39")
	ow._vm = vm
	var pages: PackedStringArray = ow._expanded_pages()
	_chk("F.01 the overworld expands its pending pages", pages.size() == 2)
	_chk("F.02 buffer markers are resolved on the way to the box",
			pages[0] == "You got TM39!")
	_chk("F.03 and identity markers too",
			pages[1] == "%s smiled." % TextBuffers.PLAYER_NAME)
	# Re-buffering and re-reading must show the NEW value: print-time, again,
	# but through the real production function rather than TextBuffers directly.
	vm.buffers.set_slot(0, "POTION")
	_chk("F.04 re-buffering changes what the box would be handed",
			ow._expanded_pages()[0] == "You got POTION!")
	ow._vm = null
	_chk("F.05 and with no script running it hands back nothing",
			ow._expanded_pages().is_empty())
	ow.free()
