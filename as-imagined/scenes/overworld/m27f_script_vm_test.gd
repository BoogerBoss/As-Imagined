extends Node

## [M27F Stage 1] ScriptVM + the text/script pipelines.
##
## Every assertion here reads the VM from OUTSIDE — `pc`, `current_op`,
## `pause_reason`, `describe()` — never by reaching into execution. That is the
## property the VM was built for, and this suite is what proves it holds.
##
## Two sections exist specifically because a real bug shipped through them:
##   * D — call/return frames. `_call_stack` held bare PCs while `_jump` swapped
##     the op array, so `return` restored the right number into the wrong script
##     and the caller's own `release`/`end` never ran. Silent; player left locked.
##   * F — the compiler's msgbox expansion. Inlining a std script while keeping
##     its trailing `return` made that `return` exit the CALLER.
## Neither had a test when it was found. Both do now.

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


## Drive until the VM stops doing work. Returns the number of opcodes executed,
## so a test can assert on progress rather than only on the end state.
func _run(vm: ScriptVM, limit: int = 200) -> int:
	var n := 0
	while vm.step() and n < limit:
		n += 1
	return n


func _ready() -> void:
	_test_observable_state()
	_test_pause_kinds()
	_test_degrade_paths()
	_test_call_frames()
	_test_message_pages()
	_test_compiled_pipeline()

	var accounted := _total + _gated
	_chk("Z.99 every expected assertion ran (%d + %d gated == %d)"
			% [_total, _gated, EXPECTED_TOTAL], accounted == EXPECTED_TOTAL)
	print("m27f_script_vm_test: %d/%d passed" % [_total - _failed, _total])
	get_tree().quit()


## --- A. the constraint: state is readable from outside at every instant ---
func _test_observable_state() -> void:
	var vm := ScriptVM.new(_src({
		"A": [_op("lock"), _op("message", ["T"]), _op("end")],
	}, {"T": ["hello"]}), FlagStore.new())
	_chk("A.01 start() reports success", vm.start("A"))
	_chk("A.02 pc begins at 0", vm.pc == 0)
	_chk("A.03 running immediately after start", vm.is_running())
	vm.step()
	_chk("A.04 pc advances", vm.pc == 1)
	_chk("A.05 current_op names the opcode just run", vm.current_op == "lock")
	var d := vm.describe()
	_chk("A.06 describe() exposes pc/op/pause without reaching inside",
			d["pc"] == 1 and d["op"] == "lock" and d["pause"] == "NONE")
	_chk("A.07 describe() exposes call depth", d["depth"] == 0)
	_chk("A.08 describe() exposes last_compare", d.has("last_compare"))


## --- B. each pause kind is distinct and correctly classified ---
func _test_pause_kinds() -> void:
	var vm := ScriptVM.new(_src({
		"A": [_op("message", ["T"]), _op("waitbuttonpress"), _op("yesnobox"), _op("end")],
	}, {"T": ["p"]}), FlagStore.new())
	vm.start("A")
	vm.step()
	_chk("B.01 message pauses on WAIT_MESSAGE",
			vm.pause_reason == ScriptVM.Pause.WAIT_MESSAGE)
	_chk("B.02 WAIT_MESSAGE counts as waiting, not finished",
			vm.is_waiting() and not vm.is_finished())
	_chk("B.03 a paused VM does no further work", vm.step() == false)
	vm.resume()
	vm.step()
	_chk("B.04 waitbuttonpress pauses on WAIT_BUTTON",
			vm.pause_reason == ScriptVM.Pause.WAIT_BUTTON)
	vm.resume()
	vm.step()
	_chk("B.05 yesnobox pauses on WAIT_YES_NO",
			vm.pause_reason == ScriptVM.Pause.WAIT_YES_NO)
	vm.resume()
	vm.step()
	_chk("B.06 end is DONE and finished, not waiting",
			vm.pause_reason == ScriptVM.Pause.DONE and vm.is_finished()
			and not vm.is_waiting())
	_chk("B.07 resume() cannot revive a finished VM", not vm.is_running())


## --- C. degrading must NAME what it could not do ---
func _test_degrade_paths() -> void:
	var vm := ScriptVM.new(_src({"A": [_op("applymovement", ["X"])]}), FlagStore.new())
	_chk("C.01 an unknown label fails start() rather than throwing",
			not vm.start("NoSuchScript"))
	_chk("C.02 and reports UNRESOLVED",
			vm.pause_reason == ScriptVM.Pause.UNRESOLVED)
	_chk("C.03 naming the label it could not find",
			vm.diagnostic.contains("NoSuchScript"))
	vm.start("A")
	vm.step()
	_chk("C.04 an out-of-stage opcode stops on UNKNOWN_OP",
			vm.pause_reason == ScriptVM.Pause.UNKNOWN_OP)
	_chk("C.05 naming the opcode", vm.diagnostic.contains("applymovement"))
	_chk("C.06 and current_op still points at it", vm.current_op == "applymovement")


## --- D. call/return frames. THE BUG: bare PCs across a swapped op array. ---
func _test_call_frames() -> void:
	var vm := ScriptVM.new(_src({
		"A": [_op("lock"), _op("call", ["SUB"]), _op("release"), _op("end")],
		"SUB": [_op("faceplayer"), _op("return")],
	}), FlagStore.new())
	vm.start("A")
	# Trace the ops actually EXECUTED. Asserting only "ended DONE" is vacuous
	# here: the buggy version also ended DONE, by running off the end of the
	# callee. What distinguishes them is whether the caller's own `release`
	# ever ran — proven by break test, which D.01 originally survived.
	var executed := PackedStringArray()
	var guard := 0
	while vm.step() and guard < 50:
		guard += 1
		executed.append(vm.current_op)
	# `end` is never recorded: step() returns false on it, so the loop exits
	# first. `release` is the discriminator anyway — it is the op the buggy
	# version skipped — and reaching `end` is what D.02/D.04's DONE state proves.
	_chk("D.01 the caller's own ops after the call DO run", executed.has("release"))
	_chk("D.02 and the caller's own label is restored", vm.script_label == "A")

	# Nested: A -> B -> C, unwinding twice. Untested when the one-level bug shipped.
	var vm2 := ScriptVM.new(_src({
		"A": [_op("call", ["B"]), _op("lock"), _op("end")],
		"B": [_op("call", ["C"]), _op("release"), _op("return")],
		"C": [_op("faceplayer"), _op("return")],
	}), FlagStore.new())
	vm2.start("A")
	var depth_at_c := 0
	var n := 0
	while vm2.step() and n < 50:
		n += 1
		if vm2.script_label == "C":
			depth_at_c = max(depth_at_c, int(vm2.describe()["depth"]))
	_chk("D.03 nested calls reach depth 2", depth_at_c == 2)
	_chk("D.04 and unwind all the way back to A",
			vm2.script_label == "A" and vm2.pause_reason == ScriptVM.Pause.DONE)
	_chk("D.05 with the stack empty again", int(vm2.describe()["depth"]) == 0)

	# `return` at depth 0 ends the script rather than underflowing.
	var vm3 := ScriptVM.new(_src({"A": [_op("return")]}), FlagStore.new())
	vm3.start("A")
	_run(vm3)
	_chk("D.06 return at depth 0 is DONE, not an underflow",
			vm3.pause_reason == ScriptVM.Pause.DONE)

	# goto is a tail-call: it does NOT push a frame.
	var vm4 := ScriptVM.new(_src({
		"A": [_op("goto", ["B"])],
		"B": [_op("lock"), _op("end")],
	}), FlagStore.new())
	vm4.start("A")
	_run(vm4)
	_chk("D.07 goto transfers without pushing a frame",
			int(vm4.describe()["depth"]) == 0 and vm4.script_label == "B")


## --- E. messages carry their pages; missing text is named, not blank ---
func _test_message_pages() -> void:
	var vm := ScriptVM.new(_src(
		{"A": [_op("message", ["T"]), _op("end")]},
		{"T": ["page one", "page two", "page three"]}), FlagStore.new())
	vm.start("A")
	vm.step()
	_chk("E.01 pending_pages carries every page", vm.pending_pages.size() == 3)
	_chk("E.02 in order", vm.pending_pages[0] == "page one"
			and vm.pending_pages[2] == "page three")
	_chk("E.03 describe() reports the page count", int(vm.describe()["pages"]) == 3)

	var vm2 := ScriptVM.new(_src({"A": [_op("message", ["MISSING"])]}), FlagStore.new())
	vm2.start("A")
	vm2.step()
	_chk("E.04 a message with no text still pauses rather than skipping",
			vm2.pause_reason == ScriptVM.Pause.WAIT_MESSAGE)
	_chk("E.05 and names the missing label", vm2.diagnostic.contains("MISSING"))


## --- F. the real compiled corpus, incl. the msgbox-expansion bug ---
func _test_compiled_pipeline() -> void:
	if not (FileAccess.file_exists("res://data/map_scripts.json")
			and FileAccess.file_exists("res://data/map_texts.json")):
		_gated += 8
		return
	var ops: Dictionary = JSON.parse_string(
			FileAccess.open("res://data/map_scripts.json", FileAccess.READ).get_as_text())
	var texts: Dictionary = JSON.parse_string(
			FileAccess.open("res://data/map_texts.json", FileAccess.READ).get_as_text())
	_chk("F.01 the compiled script corpus is non-empty", ops.size() > 1000)
	_chk("F.02 the text corpus is non-empty", texts.size() > 1000)

	# THE MSGBOX BUG: an inlined std script must not keep its trailing `return`,
	# or the caller's own cleanup is skipped. The Pewter Gym statue is the
	# fixture it was found on.
	var statue: Array = ops.get("PewterCity_Gym_EventScript_GymStatue", [])
	var names := PackedStringArray()
	for o in statue:
		names.append(str(o["op"]))
	_chk("F.03 an expanded msgbox does NOT leave a stray return before cleanup",
			not (names.has("return") and names.find("return") < names.find("end")))
	_chk("F.04 and the script still ends with its own cleanup",
			names.has("releaseall") and names[names.size() - 1] == "end")

	# Brock: the alpha target. His key must be recoverable from the compiled op.
	var brock: Array = ops.get("PewterCity_Gym_EventScript_Brock", [])
	var found_key := ""
	for o in brock:
		if str(o["op"]) == "trainerbattle_single" and (o["args"] as Array).size() > 0:
			found_key = str((o["args"] as Array)[0])
	_chk("F.05 Brock compiles to a trainerbattle carrying his trainer key",
			found_key == "TRAINER_LEADER_BROCK")

	# Real text really does page on \p.
	var intro: Array = texts.get("PewterCity_Gym_Text_BrockIntro", [])
	_chk("F.06 Brock's intro is split into multiple pages", intro.size() > 1)
	_chk("F.07 with newlines preserved inside a page",
			str(intro[0]).contains("\n"))

	# A real script runs through the real VM without throwing.
	var vm := ScriptVM.new(_src(ops, texts), FlagStore.new())
	vm.start("PewterCity_Gym_EventScript_GymStatue")
	_run(vm)
	_chk("F.08 a real compiled script runs and stops in a NAMED state",
			vm.is_finished() and (vm.pause_reason != ScriptVM.Pause.UNKNOWN_OP
					or vm.diagnostic != ""))
