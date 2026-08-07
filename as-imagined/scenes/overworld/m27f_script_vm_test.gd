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

const EXPECTED_TOTAL := 291

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


## Drive a VM the way the overworld does: resume through message/button waits
## instead of stopping at the first one. Returns the ops actually executed, so
## a test can assert on PROGRESS rather than only on the end state -- the
## distinction F.08 was missing.
func _drive(vm: ScriptVM, limit: int = 400) -> PackedStringArray:
	var executed := PackedStringArray()
	var n := 0
	while n < limit:
		if vm.step():
			executed.append(vm.current_op)
			n += 1
			continue
		if vm.pause_reason == ScriptVM.Pause.WAIT_MESSAGE \
				or vm.pause_reason == ScriptVM.Pause.WAIT_BUTTON:
			executed.append(vm.current_op)
			vm.resume()
			n += 1
			continue
		break
	return executed


## Run one conditional in isolation and hand back the VM. Label "T" is the jump
## target, so `script_label == "T"` means the branch was taken.
func _cond_vm(op_name: String, args: Array, flags: FlagStore) -> ScriptVM:
	var vm := ScriptVM.new(_src({
		"A": [_op(op_name, args), _op("lockall"), _op("end")],
		"T": [_op("release"), _op("end")],
	}), flags)
	vm.start("A")
	vm.step()
	return vm


func _ready() -> void:
	_test_observable_state()
	_test_pause_kinds()
	_test_degrade_paths()
	_test_call_frames()
	_test_message_pages()
	_test_compiled_pipeline()
	_test_conditionals()
	_test_interaction()
	_test_stage2()
	_test_stage2_real_corpus()
	_test_stage3_movement()
	_test_stage3b_walk_anim()
	_test_trainer_battle_family()
	_test_small_opcode_batch()
	_test_m27g_g1_batch()
	_test_m27g_g2_choose_party_mon()
	_test_m27g_g3a_ingame_trade()
	_test_m27g_g5_native()
	_test_m27g_g6_event_script()
	_test_m27g_g8_g9()

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
	# ⚠️ THIS FIXTURE HAS NOW MOVED TWICE, BOTH TIMES BECAUSE IT WAS IMPLEMENTED:
	# `applymovement` (Stage 3) -> `checkitemspace` (M27I I3) -> here. Each move
	# was a genuine correctness change legitimately invalidating a stale
	# assumption, but picking the next roadblock is picking a fixture with an
	# expiry date, and [M27C] already paid for that once when a "known unbaked"
	# map got baked and took ten assertions down with it.
	#
	# `frontier_set` is chosen because it belongs to a PERMANENTLY EXCLUDED
	# subsystem — Battle Frontier facilities, which `docs/overworld_scope.md`
	# rules out and M35 owns only as trainer data. It is real (162 corpus uses),
	# so this still tests the VM against data it will genuinely meet, but nothing
	# on any roadmap will implement it out from under this test.
	var vm := ScriptVM.new(_src({"A": [_op("frontier_set", ["FRONTIER_DATA_1", "0"])]}),
			FlagStore.new())
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
	_chk("C.05 naming the opcode", vm.diagnostic.contains("frontier_set"))
	_chk("C.06 and current_op still points at it", vm.current_op == "frontier_set")


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
	# The key is CANONICAL (_FRLG), not the bare source constant. The compiler
	# suffixes it because the roster is keyed by origin (Rule A); a bare key
	# resolves to no trainer and the battle silently refuses to start.
	_chk("F.05 Brock compiles to a trainerbattle carrying his canonical key",
			found_key == "TRAINER_LEADER_BROCK_FRLG")

	# Real text really does page on \p.
	var intro: Array = texts.get("PewterCity_Gym_Text_BrockIntro", [])
	_chk("F.06 Brock's intro is split into multiple pages", intro.size() > 1)
	_chk("F.07 with newlines preserved inside a page",
			str(intro[0]).contains("\n"))

	# A real script runs through the real VM without throwing.
	# ⚠️ REWRITTEN. This used to pass for the WRONG REASON: the `goto_if_eq`
	# bug made every gated script jump to a VAR name and stop UNRESOLVED,
	# which satisfied "finished in a named state" while the script had in fact
	# run almost none of itself.
	#
	# But do NOT read this as the guard for that bug -- break-tested, and it is
	# not. This fixture reaches its `goto_if_set` with the flag UNSET, so the
	# branch falls through and the label is never read; breaking the label
	# position leaves F.08 green. Section G holds the real guards (G.04, G.08).
	# What F.08 is now worth is the weaker but still real claim it makes
	# honestly: a script off the actual corpus runs to DONE and shows its text.
	var vm := ScriptVM.new(_src(ops, texts), FlagStore.new())
	vm.start("PewterCity_Gym_EventScript_GymStatue")
	var ran := _drive(vm)
	_chk("F.08 a real compiled script runs to completion when its waits are driven",
			vm.pause_reason == ScriptVM.Pause.DONE)
	_chk("F.09 and genuinely showed its text on the way",
			ran.has("message") and ran.has("releaseall"))


## --- G. the conditional family. THE LABEL IS THE LAST ARGUMENT. ---
##
## The first cut read `args[0]` as the jump target, so every gated script in
## the region tried to jump to a VAR name and died UNRESOLVED. It shipped
## because nothing here exercised a conditional against real data. G.04 is the
## direct regression guard; the rest pin the three argument shapes apart.
func _test_conditionals() -> void:
	var flags := FlagStore.new()
	flags.var_set("VAR_X", 2)

	var vm := ScriptVM.new(_src({"A": [_op("compare", ["VAR_X", "2"]), _op("end")]}), flags)
	vm.start("A")
	vm.step()
	_chk("G.01 compare sets last_compare", vm.last_compare == 0)

	_chk("G.02 goto_if_eq takes the branch when equal",
			_cond_vm("goto_if_eq", ["VAR_X", "2", "T"], flags).script_label == "T")
	_chk("G.03 and falls through when not",
			_cond_vm("goto_if_eq", ["VAR_X", "9", "T"], flags).script_label == "A")

	# THE BUG, pinned. args[0] is a VAR name, not a label -- reading it as the
	# jump target is exactly what happened, and it reported UNRESOLVED.
	var guard := _cond_vm("goto_if_eq", ["VAR_X", "2", "T"], flags)
	_chk("G.04 the label is the LAST argument, never the first",
			guard.pause_reason != ScriptVM.Pause.UNRESOLVED and guard.diagnostic == "")

	_chk("G.05 goto_if_ne is the inverse",
			_cond_vm("goto_if_ne", ["VAR_X", "9", "T"], flags).script_label == "T"
			and _cond_vm("goto_if_ne", ["VAR_X", "2", "T"], flags).script_label == "A")
	_chk("G.06 goto_if_lt excludes equality",
			_cond_vm("goto_if_lt", ["VAR_X", "2", "T"], flags).script_label == "A")
	_chk("G.07 goto_if_ge includes it",
			_cond_vm("goto_if_ge", ["VAR_X", "2", "T"], flags).script_label == "T")

	# Flag form: TWO arguments, and the flag is read, not compared.
	flags.flag_set("FLAG_DONE")
	_chk("G.08 goto_if_set branches on a set flag",
			_cond_vm("goto_if_set", ["FLAG_DONE", "T"], flags).script_label == "T")
	_chk("G.09 and not on an unset one",
			_cond_vm("goto_if_set", ["FLAG_OTHER", "T"], flags).script_label == "A")
	_chk("G.10 goto_if_unset is the inverse",
			_cond_vm("goto_if_unset", ["FLAG_OTHER", "T"], flags).script_label == "T"
			and _cond_vm("goto_if_unset", ["FLAG_DONE", "T"], flags).script_label == "A")

	# Defeated form reads the SAME key set_trainer_defeated writes -- the seam
	# that lets a beaten trainer's script take its post-battle branch with
	# nothing extra wired. Written through the real API, not a hand-built key.
	flags.set_trainer_defeated("TRAINER_LEADER_BROCK")
	_chk("G.11 goto_if_defeated reads the key FlagStore actually writes",
			_cond_vm("goto_if_defeated", ["TRAINER_LEADER_BROCK", "T"], flags).script_label == "T")
	_chk("G.12 goto_if_not_defeated is the inverse",
			_cond_vm("goto_if_not_defeated", ["TRAINER_LEADER_BROCK", "T"], flags).script_label == "A"
			and _cond_vm("goto_if_not_defeated", ["TRAINER_ROCKET", "T"], flags).script_label == "T")

	# call_if_* is the same test with a pushed frame. goto_if_* must NOT push.
	var called := _cond_vm("call_if_eq", ["VAR_X", "2", "T"], flags)
	var jumped := _cond_vm("goto_if_eq", ["VAR_X", "2", "T"], flags)
	_chk("G.13 call_if pushes a frame where goto_if does not",
			int(called.describe()["depth"]) == 1 and int(jumped.describe()["depth"]) == 0)

	# The ONE-ARGUMENT form, which leans on a preceding compare. The corpus has
	# exactly 33 `compare` ops and exactly 33 one-argument conditionals; that
	# pairing is why deleting `compare` as "never emitted" was wrong.
	var vm1 := ScriptVM.new(_src({
		"A": [_op("compare", ["VAR_X", "2"]), _op("goto_if_eq", ["T"]), _op("end")],
		"T": [_op("release"), _op("end")],
	}), flags)
	vm1.start("A")
	vm1.step()
	vm1.step()
	_chk("G.14 the one-argument form uses the preceding compare", vm1.script_label == "T")

	# An operand this project never imported must resolve, not halt.
	var unknown := _cond_vm("goto_if_eq", ["VAR_X", "SOME_UNIMPORTED_CONSTANT", "T"], flags)
	_chk("G.15 an unrecognised symbolic operand resolves rather than stopping dead",
			unknown.pause_reason == ScriptVM.Pause.NONE and unknown.script_label == "A")


## --- H. what a press of A targets ---
##
## ⚠️ THE COUNTER HOP is the assertion that matters. MB_COUNTER is 729 cells
## across 89 corridor maps, and without the hop every shop clerk, nurse and gym
## receptionist in the region is unreachable -- while everything outdoors keeps
## working, so the gap reads as correct until you walk into a Poké Mart.
func _test_interaction() -> void:
	var npc := NPC.new()
	npc.script_label = "TALK_TO_ME"
	var sign_node := Sign.new()
	sign_node.script_label = "READ_ME"

	var plain := func(_c: Vector2i) -> int: return 0
	var at := func(cell: Vector2i, who: Node) -> Callable:
		return func(c: Vector2i) -> Variant: return who if c == cell else null

	var r: Dictionary = Interaction.resolve(Vector2i(5, 5), StepResolver.Dir.NORTH,
			plain, at.call(Vector2i(5, 4), npc))
	_chk("H.01 an entity on the faced tile answers",
			str(r.get("source", "")) == Interaction.SOURCE_OBJECT
			and str(r.get("script", "")) == "TALK_TO_ME")

	# The hop: the faced tile is a counter, so the search moves ONE FURTHER.
	var counter := func(c: Vector2i) -> int:
		return MetatileBehavior.MB_COUNTER if c == Vector2i(5, 4) else 0
	var hopped: Dictionary = Interaction.resolve(Vector2i(5, 5), StepResolver.Dir.NORTH,
			counter, at.call(Vector2i(5, 3), npc))
	_chk("H.02 a counter tile moves the search one tile further",
			str(hopped.get("script", "")) == "TALK_TO_ME"
			and hopped.get("cell", Vector2i.ZERO) == Vector2i(5, 3))
	# ...and the discriminator: without the hop, THIS is what would have answered.
	var unhopped: Dictionary = Interaction.resolve(Vector2i(5, 5), StepResolver.Dir.NORTH,
			counter, at.call(Vector2i(5, 4), npc))
	_chk("H.03 so an entity standing ON the counter is NOT what answers",
			unhopped.is_empty())

	var bg: Dictionary = Interaction.resolve(Vector2i(5, 5), StepResolver.Dir.NORTH,
			plain, at.call(Vector2i(5, 4), sign_node))
	_chk("H.04 a sign resolves as a background event",
			str(bg.get("source", "")) == Interaction.SOURCE_BACKGROUND)

	sign_node.facing = "BG_EVENT_PLAYER_FACING_NORTH"
	_chk("H.05 a facing-gated sign answers the required approach",
			not Interaction.resolve(Vector2i(5, 5), StepResolver.Dir.NORTH,
					plain, at.call(Vector2i(5, 4), sign_node)).is_empty())
	_chk("H.06 and refuses the wrong one",
			Interaction.resolve(Vector2i(5, 3), StepResolver.Dir.SOUTH,
					plain, at.call(Vector2i(5, 4), sign_node)).is_empty())

	_chk("H.07 an empty cell resolves to nothing",
			Interaction.resolve(Vector2i(5, 5), StepResolver.Dir.NORTH,
					plain, func(_c: Vector2i) -> Variant: return null).is_empty())

	npc.free()
	sign_node.free()


## --- I. Stage 2: the script engine takes control of the battle engine ---
##
## `trainerbattle_single` is the first opcode whose pause OUTLIVES the frame it
## started in, and the first whose RESULT decides where the script goes next.
func _test_stage2() -> void:
	var flags := FlagStore.new()
	var texts := {"Intro": ["Hi.", "Fight me."], "Defeat": ["I lost."]}
	var battle_ops := {
		"A": [_op("trainerbattle_single", ["TRAINER_X", "Intro", "Defeat", "POST"]),
				_op("lockall"), _op("end")],
		"POST": [_op("release"), _op("end")],
	}

	var vm := ScriptVM.new(_src({"A": [_op("famechecker", ["FAMECHECKER_BROCK", "1"]),
			_op("setflag", ["FLAG_A"]), _op("setvar", ["VAR_A", "3"]),
			_op("clearflag", ["FLAG_A"]), _op("end")]}), flags)
	vm.start("A")
	_run(vm)
	_chk("I.01 famechecker is a no-op, not a stall",
			vm.pause_reason == ScriptVM.Pause.DONE)
	_chk("I.02 setvar writes through FlagStore", flags.var_get("VAR_A") == 3)
	_chk("I.03 setflag then clearflag leaves the flag clear",
			not flags.flag_get("FLAG_A"))

	var b := ScriptVM.new(_src(battle_ops, texts), flags)
	b.start("A")
	_run(b)
	_chk("I.04 trainerbattle_single pauses on WAIT_BATTLE",
			b.pause_reason == ScriptVM.Pause.WAIT_BATTLE)
	_chk("I.05 carrying the trainer key", b.pending_trainer_key == "TRAINER_X")
	_chk("I.06 and the post-battle script from the 4th argument",
			b.pending_battle_script == "POST")
	_chk("I.07 and the intro speech, which source shows before the battle",
			b.pending_pages.size() == 2 and b.pending_pages[0] == "Hi.")
	_chk("I.08 and the trainer's own defeat speech, for whoever closes M26B3-4",
			b.pending_battle_defeat_text == "Defeat")
	_chk("I.09 WAIT_BATTLE counts as waiting", b.is_waiting())

	# ⚠️ A plain resume() must NOT clear it. Doing so would skip the win/loss
	# branch silently and read as "the post-battle script just did not run".
	b.resume()
	_chk("I.10 a plain resume() cannot clear WAIT_BATTLE",
			b.pause_reason == ScriptVM.Pause.WAIT_BATTLE)

	b.resume_after_battle(true)
	_chk("I.11 winning jumps to the post-battle script (`gotobeatenscript`)",
			b.script_label == "POST")

	# THREE arguments is a different battle type with no post-battle script.
	var short_form := ScriptVM.new(_src({
		"A": [_op("trainerbattle_single", ["TRAINER_Y", "Intro", "Defeat"]),
				_op("lockall"), _op("end")],
	}, texts), flags)
	short_form.start("A")
	_run(short_form)
	_chk("I.12 the 3-argument form carries no post-battle script",
			short_form.pending_battle_script == "")
	short_form.resume_after_battle(true)
	_chk("I.13 so winning ends the script rather than falling through",
			short_form.pause_reason == ScriptVM.Pause.DONE)

	var lost := ScriptVM.new(_src(battle_ops, texts), flags)
	lost.start("A")
	_run(lost)
	lost.resume_after_battle(false)
	_chk("I.14 losing ends the script and does NOT run the post-battle script",
			lost.pause_reason == ScriptVM.Pause.DONE and lost.script_label == "A")

	# THE ALREADY-BEATEN SKIP. Source checks GetTrainerFlag inside the shared
	# standard script, one level BELOW the command -- which is why Brock's own
	# script carries no guard and would otherwise re-challenge forever.
	var beaten := FlagStore.new()
	beaten.set_trainer_defeated("TRAINER_X")
	var again := ScriptVM.new(_src(battle_ops, texts), beaten)
	again.start("A")
	_run(again)
	_chk("I.15 an already-beaten trainer starts no battle at all",
			again.pause_reason != ScriptVM.Pause.WAIT_BATTLE)
	_chk("I.16 and the calling script continues past the command",
			again.pause_reason == ScriptVM.Pause.DONE and again.script_label == "A")

	# switch/case -- `compare VAR_0x8000` + the ONE-ARGUMENT goto_if_eq.
	var sw := FlagStore.new()
	sw.var_set("VAR_PICK", 2)
	var swvm := ScriptVM.new(_src({
		"A": [_op("switch", ["VAR_PICK"]), _op("case", ["1", "ONE"]),
				_op("case", ["2", "TWO"]), _op("end")],
		"ONE": [_op("setflag", ["GOT_ONE"]), _op("end")],
		"TWO": [_op("setflag", ["GOT_TWO"]), _op("end")],
	}), sw)
	swvm.start("A")
	_run(swvm)
	_chk("I.17 switch/case dispatches to the matching arm",
			sw.flag_get("GOT_TWO") and not sw.flag_get("GOT_ONE"))
	sw.var_set("VAR_PICK", 9)
	var swmiss := ScriptVM.new(_src({
		"A": [_op("switch", ["VAR_PICK"]), _op("case", ["1", "ONE"]), _op("end")],
		"ONE": [_op("setflag", ["GOT_ONE"]), _op("end")],
	}), sw)
	swmiss.start("A")
	_run(swmiss)
	_chk("I.18 and falls through when nothing matches",
			not sw.flag_get("GOT_ONE") and swmiss.script_label == "A")

	var cv := FlagStore.new()
	cv.var_set("SRC", 7)
	var cvvm := ScriptVM.new(_src({"A": [_op("copyvar", ["DST", "SRC"]), _op("end")]}), cv)
	cvvm.start("A")
	_run(cvvm)
	_chk("I.19 copyvar copies var to var", cv.var_get("DST") == 7)

	# settrainerflag writes the SAME key a won battle writes and goto_if_defeated
	# reads -- one representation of "beaten", three writers.
	var st := FlagStore.new()
	var stvm := ScriptVM.new(_src({
		"A": [_op("settrainerflag", ["TRAINER_Z"]),
				_op("goto_if_defeated", ["TRAINER_Z", "SEEN"]), _op("end")],
		"SEEN": [_op("release"), _op("end")],
	}), st)
	stvm.start("A")
	_run(stvm)
	_chk("I.20 settrainerflag and goto_if_defeated agree on one key",
			st.trainer_defeated("TRAINER_Z") and stvm.script_label == "SEEN")


## --- I (cont). the same thing against Brock's REAL script ---
func _test_stage2_real_corpus() -> void:
	if not (FileAccess.file_exists("res://data/map_scripts.json")
			and FileAccess.file_exists("res://data/map_texts.json")):
		_gated += 3
		return
	var ops: Dictionary = JSON.parse_string(
			FileAccess.open("res://data/map_scripts.json", FileAccess.READ).get_as_text())
	var texts: Dictionary = JSON.parse_string(
			FileAccess.open("res://data/map_texts.json", FileAccess.READ).get_as_text())
	var flags := FlagStore.new()
	var vm := ScriptVM.new(_src(ops, texts), flags)
	vm.start("PewterCity_Gym_EventScript_Brock")
	_drive(vm)
	# ⚠️ The _FRLG suffix is load-bearing. Scripts carry the bare source
	# constant; the roster is keyed by origin (Rule A). Without the compiler
	# canonicalising it, the party lookup finds nothing and the battle silently
	# refuses to start -- which is what live-driving Brock actually showed.
	_chk("I.21 Brock's real script reaches a real battle with a RESOLVABLE key",
			vm.pause_reason == ScriptVM.Pause.WAIT_BATTLE
			and vm.pending_trainer_key == "TRAINER_LEADER_BROCK_FRLG"
			and vm.pending_pages.size() > 1)

	flags.set_trainer_defeated(vm.pending_trainer_key)
	vm.resume_after_battle(true)
	_drive(vm)
	_chk("I.22 and winning awards the badge through the real post-battle chain",
			flags.flag_get("FLAG_BADGE01_GET")
			and flags.var_get("VAR_MAP_SCENE_PEWTER_CITY") == 1)

	var again := ScriptVM.new(_src(ops, texts), flags)
	again.start("PewterCity_Gym_EventScript_Brock")
	_drive(again)
	_chk("I.23 talking to a beaten Brock starts no second battle",
			again.pause_reason != ScriptVM.Pause.WAIT_BATTLE)


## --- J. Stage 3: applymovement / waitmovement ---
##
## The shape being guarded is the ASYMMETRY between the two halves.
## `applymovement` must NOT pause (source's own `ScrCmd_applymovement` starts the
## movement and returns, which is the only reason two entities can walk at once),
## while `waitmovement` must. Getting that backwards still "works" for a
## single-mover cutscene and quietly serialises every multi-mover one.
func _test_stage3_movement() -> void:
	# -- the action table, against source's own step tables --
	var walk := MovementRunner.action("walk_down")
	_chk("J.01 a normal step is 16 frames and displaces",
			int(walk.get("frames", 0)) == 16 and bool(walk.get("moves", false)))

	# `UpdateWalkSlowAnim` steps one pixel only on EVEN frames and ends after 16
	# of them, so SLOW is exactly double NORMAL -- not a fraction of it.
	_chk("J.02 a slow step is 32 frames, twice a normal one",
			int(MovementRunner.action("walk_slow_down").get("frames", 0)) == 32)

	# The discriminator that matters: same duration, opposite displacement.
	var ip := MovementRunner.action("walk_in_place_faster_up")
	var fw := MovementRunner.action("walk_faster_up")
	_chk("J.03 walk_in_place shares its speed but does NOT displace",
			int(ip.get("frames", 0)) == int(fw.get("frames", 0))
			and not bool(ip.get("moves", true)) and bool(fw.get("moves", false)))

	var face := MovementRunner.action("face_left")
	_chk("J.04 a turn is immediate and does not displace",
			int(face.get("frames", 0)) == 1 and not bool(face.get("moves", true)))

	_chk("J.05 an unimplemented action resolves to nothing, not a default",
			MovementRunner.action("cut_tree").is_empty())

	# Facing lock is a FLAG, not a duration -- a locked walk still moves.
	_chk("J.06 lock/unlock carry a flag rather than a frame cost",
			MovementRunner.action("lock_facing_direction").get("facing_locked") == true
			and MovementRunner.action("unlock_facing_direction").get("facing_locked") == false
			and not MovementRunner.action("lock_facing_direction").has("frames"))

	# -- the VM halves --
	var vm := ScriptVM.new(_src({"A": [
			_op("applymovement", ["LOCALID_PLAYER", "M1"]),
			_op("applymovement", ["4", "M2"]),
			_op("end"),
		]}), FlagStore.new())
	vm.start("A")
	_drive(vm)
	_chk("J.07 applymovement does NOT pause -- the script runs on past it",
			vm.pause_reason == ScriptVM.Pause.DONE)
	_chk("J.08 and BOTH movements are queued, in order, with target and script",
			vm.pending_movements.size() == 2
			and vm.pending_movements[0]["target"] == "LOCALID_PLAYER"
			and vm.pending_movements[0]["script"] == "M1"
			and vm.pending_movements[1]["target"] == "4")

	var vm2 := ScriptVM.new(_src({"A": [
			_op("applymovement", ["4", "M1"]),
			_op("waitmovement", ["0"]),
			_op("end"),
		]}), FlagStore.new())
	vm2.start("A")
	_drive(vm2)
	_chk("J.09 waitmovement is the half that blocks",
			vm2.pause_reason == ScriptVM.Pause.WAIT_MOVEMENT)
	# `waitmovement 0` is "everything in flight", not "object 0" -- LOCALID_NONE
	# is 0, so there is no object to name.
	_chk("J.10 waitmovement 0 means everything, a named target means only it",
			vm2.pending_wait_target == "")

	# THE ASYMMETRY. WAIT_BATTLE deliberately refuses a plain resume (resuming it
	# would skip the win/loss branch); WAIT_MOVEMENT must accept one, because
	# there is no result to branch on.
	vm2.resume()
	_drive(vm2)
	_chk("J.11 and a plain resume() clears it, unlike WAIT_BATTLE",
			vm2.pause_reason == ScriptVM.Pause.DONE)

	var vm3 := ScriptVM.new(_src({"A": [_op("waitmovement", ["LOCALID_RIVAL"])],
			"B": [_op("end")]}), FlagStore.new())
	vm3.start("A")
	_drive(vm3)
	var named_kept := vm3.pending_wait_target == "LOCALID_RIVAL"
	vm3.start("B")
	_chk("J.12 a named wait target is preserved, and start() clears stale state",
			named_kept and vm3.pending_movements.is_empty()
			and vm3.pending_wait_target == "")

	# -- the runner itself --
	var runner := MovementRunner.new()
	var node := Node2D.new()
	var commits := [0]
	var faces: Array[int] = []
	var commit := func(dir: int) -> void:
		commits[0] += 1
		node.position += Vector2(StepResolver.STEP[dir]) * 16.0
	var face_cb := func(dir: int) -> void: faces.append(dir)

	runner.start("p", node, [_op("walk_down"), _op("step_end")], commit, face_cb)
	# ⚠️ THE ORDERING IS THE TEST. The cell is committed IMMEDIATELY (occupancy
	# must be true the instant the step is taken, which is D3's invariant), and
	# the sprite is then REWOUND to interpolate from where it actually was. A
	# runner that skipped the rewind would teleport and still pass a cell check.
	_chk("J.13 a step commits once up front and rewinds the sprite to the start",
			commits[0] == 1 and node.position == Vector2.ZERO)

	runner.tick(MovementRunner.FRAME * 8.0)
	_chk("J.14 mid-step the sprite is strictly between the two cells",
			node.position.y > 0.0 and node.position.y < 16.0)

	runner.tick(MovementRunner.FRAME * 8.0)
	_chk("J.15 it lands exactly on the destination and step_end ends the script",
			node.position == Vector2(0, 16) and not runner.is_busy("p"))

	# An unknown action must be REPORTED, not silently swallowed -- including in
	# the first slot, which never reaches tick() at all.
	var r2 := MovementRunner.new()
	var n2 := Node2D.new()
	r2.start("x", n2, [_op("rock_smash_break")], commit, Callable())
	_chk("J.16 an unimplemented FIRST action stops the mover and names itself",
			not r2.is_busy("x") and r2.last_unknown() == "rock_smash_break")

	var r3 := MovementRunner.new()
	var n3 := Node2D.new()
	var c3 := [0]
	var commit3 := func(dir: int) -> void:
		c3[0] += 1
		n3.position += Vector2(StepResolver.STEP[dir]) * 16.0
	r3.start("v", n3, [_op("set_invisible"), _op("walk_down"), _op("step_end")],
			commit3, Callable())
	# Visibility is instantaneous: it must not consume the frame budget, so the
	# walk after it has to have already begun.
	_chk("J.17 set_invisible applies without spending a frame",
			not n3.visible and c3[0] == 1)

	# Facing lock: source keeps `facingDirectionLocked` as one bit and a locked
	# walk still MOVES. Both halves are asserted -- a port that skipped the whole
	# action would move but also turn.
	var r4 := MovementRunner.new()
	var n4 := Node2D.new()
	var c4 := [0]
	var f4: Array[int] = []
	var commit4 := func(dir: int) -> void:
		c4[0] += 1
		n4.position += Vector2(StepResolver.STEP[dir]) * 16.0
	r4.start("l", n4, [
			_op("lock_facing_direction"), _op("walk_down"),
			_op("unlock_facing_direction"), _op("walk_up"), _op("step_end")],
			commit4, func(dir: int) -> void: f4.append(dir))
	var locked_moved: bool = c4[0] == 1 and f4.is_empty()
	r4.tick(MovementRunner.FRAME * 16.0)
	_chk("J.18 a locked walk moves without turning, and unlock restores turning",
			locked_moved and c4[0] == 2 and f4 == [StepResolver.Dir.NORTH])

	# The whole reason applymovement is asynchronous: two movers at once.
	var r5 := MovementRunner.new()
	var a5 := Node2D.new()
	var b5 := Node2D.new()
	var noop := func(_d: int) -> void: pass
	r5.start("a", a5, [_op("delay_16"), _op("step_end")], noop, Callable())
	r5.start("b", b5, [_op("delay_4"), _op("step_end")], noop, Callable())
	_chk("J.19 two movers run concurrently", r5.is_busy("a") and r5.is_busy("b"))
	r5.tick(MovementRunner.FRAME * 4.0)
	_chk("J.20 and is_busy is per-mover, not global",
			r5.is_busy("a") and not r5.is_busy("b") and r5.is_busy())
	r5.tick(MovementRunner.FRAME * 12.0)
	_chk("J.21 until the last one finishes", not r5.is_busy())

	node.free()
	n2.free()
	n3.free()
	n4.free()
	a5.free()
	b5.free()

	# -- the real corpus --
	if not FileAccess.file_exists("res://data/map_scripts.json"):
		_gated += 2
		return
	var ops: Dictionary = JSON.parse_string(
			FileAccess.open("res://data/map_scripts.json", FileAccess.READ).get_as_text())
	# Movement scripts are ORDINARY labels -- the compiler indexes every label
	# uniformly, so applymovement resolves through the same table goto does.
	# A dangling target would be a cutscene that silently does nothing.
	var dangling := 0
	var targets := {}
	for label in ops:
		for o in ops[label]:
			if str(o.get("op", "")) == "applymovement":
				var a: Array = o.get("args", [])
				if a.size() > 1:
					targets[str(a[1])] = true
					if not ops.has(str(a[1])):
						dangling += 1
	_chk("J.22 every applymovement target in the region resolves to a real label (%d targets, %d dangling)"
			% [targets.size(), dangling], dangling == 0 and targets.size() > 1000)

	var playable := 0
	for t in targets:
		var ok := true
		for o in ops[t]:
			var name := str(o.get("op", ""))
			if name != "step_end" and MovementRunner.action(name).is_empty():
				ok = false
				break
		if ok:
			playable += 1
	# MEASURED, not estimated: 1270 of 1372. The floor is a regression guard --
	# it must not silently fall when the action table is touched.
	_chk("J.23 the great majority of real movement scripts run to completion (%d/%d)"
			% [playable, targets.size()], playable >= 1270)


## Section K -- [M27F Stage 3b] the walk cycle.
##
## Stage 3 made entities MOVE; this makes them WALK. The gap between those was
## invisible to every Stage 3 assertion, because all of them are on cells and
## pixels and none on which frame is showing.
func _test_stage3b_walk_anim() -> void:
	# -- the frame tables, against source --
	var sf := ObjectEventGraphics.STEP_FRAME
	_chk("K.01 step frames match sAnim_Go* exactly",
			sf["SOUTH"] == [3, 4] and sf["NORTH"] == [5, 6] and sf["WEST"] == [7, 8])
	# EAST has no frames of its own in the sheet -- it is WEST mirrored, the
	# same rule its idle frame already follows.
	_chk("K.02 EAST reuses WEST's pair rather than owning frames 9/10",
			sf["EAST"] == sf["WEST"]
			and ObjectEventGraphics.FACE_FRAME["EAST"] == ObjectEventGraphics.FACE_FRAME["WEST"])
	_chk("K.03 cycle-entry lengths match the ANIMCMD_FRAME durations",
			ObjectEventGraphics.ANIM_TICKS_NORMAL == 8
			and ObjectEventGraphics.ANIM_TICKS_FAST == 4
			and ObjectEventGraphics.ANIM_TICKS_FASTER == 2)

	# -- the cycle itself --
	# ⚠️ THE HEADLINE. The cycle is step, REST, step, REST -- the idle frame is
	# part of the walk. A port that alternates the two step frames alone looks
	# like a shuffle and would pass any "does the frame change" check.
	var T := ObjectEventGraphics.ANIM_TICKS_NORMAL
	var e := func(i: int) -> int:
		return WalkAnim.cycle_frame("SOUTH", T, (float(i) + 0.5) * float(T) * WalkAnim.FRAME)
	_chk("K.04 the cycle is stepA, idle, stepB, idle -- not stepA/stepB",
			e.call(0) == 3 and e.call(1) == 0 and e.call(2) == 4 and e.call(3) == 0)
	_chk("K.05 and it loops back round", e.call(4) == 3 and e.call(5) == 0)
	_chk("K.06 north and west run their own pairs, not south's",
			WalkAnim.cycle_frame("NORTH", T, 0.0) == 5
			and WalkAnim.cycle_frame("WEST", T, 0.0) == 7)

	# -- the free-running clock: the hop bug, directly --
	# Source restarts a walk anim only when the requested anim CHANGES
	# (StartSpriteAnimIfDifferent). Restarting per step is the obvious
	# implementation and makes the walker lead with the same foot every tile.
	var wa := WalkAnim.new()
	wa.setup("OBJ_EVENT_GFX_NINJA_BOY")
	_chk("K.07 a nine-frame sheet can animate", wa.animates())
	var spr := Sprite2D.new()
	spr.texture = load(ObjectEventGraphics.sheet_path("OBJ_EVENT_GFX_NINJA_BOY"))
	spr.region_enabled = true
	var w := ObjectEventGraphics.frame_size("OBJ_EVENT_GFX_NINJA_BOY").x
	var shown := func() -> int: return int(spr.region_rect.position.x / w)
	# Walk one full tile (two entries) then keep walking the SAME way.
	var entry := float(T) * WalkAnim.FRAME
	wa.step(spr, "SOUTH", T, 0.0)
	var first: int = shown.call()
	wa.step(spr, "SOUTH", T, entry)
	wa.step(spr, "SOUTH", T, entry)
	var third: int = shown.call()
	_chk("K.08 a continuous walk keeps advancing rather than restarting",
			first == 3 and third == 4)
	# Changing direction is a different anim, so it DOES restart.
	wa.step(spr, "NORTH", T, 0.0)
	_chk("K.09 changing direction restarts the cycle at its first step frame",
			shown.call() == 5)

	# -- resting --
	wa.rest(spr, "SOUTH")
	_chk("K.10 resting shows the idle frame", shown.call() == 0)
	wa.rest(spr, "SOUTH")
	_chk("K.11 and is idempotent, so a per-frame idle call is free",
			shown.call() == 0)
	# Standing still and then walking IS a changed anim (FACE_* -> GO_*), so a
	# fresh walk starts at stepA rather than resuming mid-stride.
	wa.step(spr, "SOUTH", T, 0.0)
	_chk("K.12 a walk after standing still begins at the first step frame",
			shown.call() == 3)

	# -- sheets that cannot animate --
	# 70 of 385 ids carry three frames and 96 carry one. Indexing a step frame
	# on those reads off the end of the sheet.
	var sign_anim := WalkAnim.new()
	sign_anim.setup("OBJ_EVENT_GFX_CUTTABLE_TREE")
	var can: bool = sign_anim.animates()
	var sspr := Sprite2D.new()
	sspr.region_enabled = true
	sign_anim.step(sspr, "SOUTH", T, 0.0)
	sign_anim.step(sspr, "SOUTH", T, entry)
	var sw := ObjectEventGraphics.frame_size("OBJ_EVENT_GFX_CUTTABLE_TREE").x
	_chk("K.13 a sheet without nine frames never indexes a step frame",
			not can and int(sspr.region_rect.position.x / maxf(1.0, float(sw))) == 0)

	# -- which ACTIONS animate --
	_chk("K.14 walking animates and turning does not",
			int(MovementRunner.action("walk_down").get("anim", 0)) == T
			and int(MovementRunner.action("face_down").get("anim", 0)) == 0
			and int(MovementRunner.action("delay_16").get("anim", 0)) == 0)
	# ⚠️ Gating the animation on `moves` would leave every walk-in-place beat
	# standing perfectly still, which is the one thing it exists to not do.
	var wip := MovementRunner.action("walk_in_place_down")
	_chk("K.15 walking in place animates despite not moving",
			not bool(wip["moves"]) and int(wip.get("anim", 0)) == T)
	# ⚠️ K.15 reads the TABLE. Injecting the real mistake (gating the animation
	# on `moves` inside the runner) left it green -- so it proves the data and
	# nothing about the behaviour. This drives a walk-in-place through the
	# runner and is what actually fails when that gate is added.
	var rip := MovementRunner.new()
	var nip := Node2D.new()
	var ip_ticks: Array[int] = []
	var ip_moved := [0]
	rip.start("ip", nip, [_op("walk_in_place_down"), _op("step_end")],
			func(_d: int) -> void: ip_moved[0] += 1, Callable(),
			func(_d: int, t: int, _dt: float) -> void: ip_ticks.append(t), Callable())
	rip.tick(MovementRunner.FRAME * 4.0)
	_chk("K.15b and the RUNNER really drives it, without committing a move",
			ip_ticks.size() == 1 and ip_ticks[0] == T and ip_moved[0] == 0)
	nip.free()
	# Source has no GoSlow* anim at all, so a slow walk reuses the NORMAL entry
	# length -- 32 movement frames play FOUR entries, not two stretched ones.
	var slow := MovementRunner.action("walk_slow_down")
	_chk("K.16 a slow walk plays four cycle entries, not two slower ones",
			int(slow["frames"]) == MovementRunner.FRAMES_SLOW
			and int(slow.get("anim", 0)) == T
			and int(slow["frames"]) / int(slow.get("anim", 0)) == 4
			and int(MovementRunner.action("walk_down")["frames"]) / T == 2)

	# -- the runner drives it --
	var r := MovementRunner.new()
	var n := Node2D.new()
	var ticks: Array[int] = []
	var rested: Array[int] = []
	var noop := func(_d: int) -> void: pass
	r.start("p", n, [_op("walk_down"), _op("step_end")], noop, Callable(),
			func(_d: int, t: int, _dt: float) -> void: ticks.append(t),
			func(d: int) -> void: rested.append(d))
	r.tick(MovementRunner.FRAME * 4.0)
	_chk("K.17 the runner advances the cycle while a step is in flight",
			ticks.size() == 1 and ticks[0] == T and rested.is_empty())
	r.tick(MovementRunner.FRAME * 16.0)
	_chk("K.18 and settles onto the standing frame once the script ends",
			rested == [StepResolver.Dir.SOUTH] and not r.is_busy())

	# A face-only caller (the pre-Stage-3b contract) must keep working: without
	# this, wiring the animation would silently stop older callers turning.
	var r2 := MovementRunner.new()
	var n2 := Node2D.new()
	var faced: Array[int] = []
	r2.start("q", n2, [_op("walk_up"), _op("step_end")], noop,
			func(d: int) -> void: faced.append(d))
	_chk("K.19 a caller supplying only `face` still gets it for a walk",
			faced == [StepResolver.Dir.NORTH])

	# A locked walk still moves its feet -- source's facingDirectionLocked
	# blocks the TURN, not the animation.
	var r3 := MovementRunner.new()
	var n3 := Node2D.new()
	var dirs: Array[int] = []
	r3.start("l", n3, [_op("walk_down"), _op("lock_facing_direction"),
			_op("walk_up"), _op("step_end")], noop, Callable(),
			func(d: int, _t: int, _dt: float) -> void: dirs.append(d), Callable())
	r3.tick(MovementRunner.FRAME * 17.0)
	r3.tick(MovementRunner.FRAME * 4.0)
	_chk("K.20 a locked walk keeps animating in its established direction",
			dirs.size() >= 2 and dirs[dirs.size() - 1] == StepResolver.Dir.SOUTH)

	# -- [M27F Stage 3c] the shared walk-script builder --
	# The trainer approach was the LAST caller still committing cells directly,
	# which is why an approaching trainer kept teleporting after Stage 3 fixed
	# wandering. Both callers now build their script here, so they cannot drift.
	var mm := MapManager.new()
	var ops3 := mm.walk_ops(StepResolver.Dir.WEST, 3)
	_chk("K.21 walk_ops builds one walk per tile and terminates",
			ops3.size() == 4
			and str(ops3[0]["op"]) == "walk_left" and str(ops3[2]["op"]) == "walk_left"
			and str(ops3[3]["op"]) == "step_end")
	# ⚠️ A trainer standing ADJACENT already has distance-1 == 0. It must produce
	# a script that ends immediately rather than one stray step onto the player.
	var ops0 := mm.walk_ops(StepResolver.Dir.NORTH, 0)
	_chk("K.22 an adjacent trainer walks nowhere rather than onto the player",
			ops0.size() == 1 and str(ops0[0]["op"]) == "step_end")
	_chk("K.23 and the ops it builds are real animating walk actions",
			int(MovementRunner.action("walk_left").get("anim", 0)) > 0
			and bool(MovementRunner.action("walk_left")["moves"]))
	# ⚠️ THE MULTI-TILE CASE, which is what an approach actually is. K.08 proves
	# the clock free-runs across `step` calls; this proves it also survives the
	# ACTION BOUNDARY inside one script. If `_begin` reset it per action -- or
	# called `face`, which parks it -- a three-tile approach would play
	# stepA,idle,stepA,idle,stepA,idle and the trainer would hop toward you.
	var rmt := MovementRunner.new()
	var nmt := Node2D.new()
	var wam := WalkAnim.new()
	wam.setup("OBJ_EVENT_GFX_NINJA_BOY")
	var sprm := Sprite2D.new()
	sprm.region_enabled = true
	var wm := ObjectEventGraphics.frame_size("OBJ_EVENT_GFX_NINJA_BOY").x
	var seq: Array[int] = []
	rmt.start("m", nmt, mm.walk_ops(StepResolver.Dir.SOUTH, 3),
			func(_d: int) -> void: pass, Callable(),
			func(d: int, tk: int, dt: float) -> void:
				wam.step(sprm, WalkAnim.facing_name(d), tk, dt)
				var f := int(sprm.region_rect.position.x / maxi(1, wm))
				if seq.is_empty() or seq[seq.size() - 1] != f:
					seq.append(f),
			Callable())
	# Three tiles at 16 frames each, stepped finely enough to sample every entry.
	for _i in range(48):
		rmt.tick(MovementRunner.FRAME)
	_chk("K.24 the cycle survives the action boundary inside one walk script",
			seq.size() >= 6 and seq[0] == 3 and seq[1] == 0 and seq[2] == 4
			and seq[3] == 0 and seq[4] == 3)
	sprm.free()
	nmt.free()

	mm.free()

	spr.free()
	sspr.free()
	n.free()
	n2.free()
	n3.free()


## Section L -- the trainer-battle family beyond `trainerbattle_single`.
##
## `[M27F Stage 2]` shipped exactly one of source's five real dispatch shapes
## (`BattleSetup_GetTrainerBattleScript`, `battle_setup.c:1121-1152`) — every
## other variant halted with UNKNOWN_OP. 496 combined corpus uses across the
## other four, all now routed through the same `_start_trainer_battle` this
## refactor extracted, so this section is deliberately about what's DIFFERENT
## per variant, not re-proving the shared machinery Section I already covers.
func _test_trainer_battle_family() -> void:
	var texts := {
		"Intro": ["Hi.", "Fight me."],
		"Defeat": ["I lost."],
	}

	# -- trainerbattle_no_intro: 2 args, no intro message at all --
	var flags_ni := FlagStore.new()
	var ni := ScriptVM.new(_src({
		"A": [_op("trainerbattle_no_intro", ["TRAINER_GRUNT", "Defeat"]),
				_op("lockall"), _op("end")],
	}, texts), flags_ni)
	ni.start("A")
	_run(ni)
	_chk("L.01 trainerbattle_no_intro pauses on WAIT_BATTLE",
			ni.pause_reason == ScriptVM.Pause.WAIT_BATTLE)
	_chk("L.02 with NO intro pages -- WAIT_BATTLE's own driver skips straight "
			+ "to the battle on an empty pending_pages",
			ni.pending_pages.is_empty())
	_chk("L.03 the defeat text is still carried", ni.pending_battle_defeat_text == "Defeat")
	_chk("L.04 and no continuation script -- the macro has no such argument",
			ni.pending_battle_script == "")
	ni.resume_after_battle(true)
	# ⚠️ CORRECTED, not merely updated: this used to assert the win ENDS the
	# script, matching `trainerbattle_single`'s `gotobeatenscript`-ends-when-
	# empty rule. Direct source read (`EventScript_DoNoIntroTrainerBattle`,
	# `data/scripts/trainer_battle.inc:47-54`) shows `trainerbattle_no_intro`
	# shares that handler with `trainerbattle_earlyrival` -- `dotrainerbattle`
	# then an UNCONDITIONAL `gotopostbattlescript`, so a win falls through to
	# the next opcode exactly like the already-beaten skip, never ending on
	# an empty continuation. The old assertion was never exercised against
	# source; this is the fix, not a re-litigation of a settled behavior.
	_chk("L.05 winning with no continuation FALLS THROUGH -- gotopostbattlescript "
			+ "is unconditional for this family, not gotobeatenscript's ends-when-empty rule",
			ni.pause_reason == ScriptVM.Pause.NONE)
	_run(ni)
	_chk("L.05b ...and reaches the calling script's own end (lockall, end)",
			ni.pause_reason == ScriptVM.Pause.DONE)

	var ni_short := ScriptVM.new(_src({
		"A": [_op("trainerbattle_no_intro", ["TRAINER_GRUNT"]), _op("end")],
	}, texts), FlagStore.new())
	ni_short.start("A")
	_run(ni_short)
	_chk("L.06 too few args is UNKNOWN_OP, not a crash",
			ni_short.pause_reason == ScriptVM.Pause.UNKNOWN_OP
			and ni_short.diagnostic.contains("trainerbattle_no_intro"))

	# -- trainerbattle_double: real corpus shapes are 4, 5, and 6 args --
	var flags_d := FlagStore.new()
	var d4 := ScriptVM.new(_src({
		"A": [_op("trainerbattle_double",
				["TRAINER_DUO", "Intro", "Defeat", "NotEnough"]), _op("end")],
	}, texts), flags_d)
	d4.start("A")
	_run(d4)
	_chk("L.07 trainerbattle_double (4 args) pauses on WAIT_BATTLE",
			d4.pause_reason == ScriptVM.Pause.WAIT_BATTLE)
	_chk("L.08 with the real intro shown", d4.pending_pages.size() == 2)
	_chk("L.09 and no continuation -- the 4-arg form has none",
			d4.pending_battle_script == "")

	var d5 := ScriptVM.new(_src({
		"A": [_op("trainerbattle_double",
				["TRAINER_DUO", "Intro", "Defeat", "NotEnough", "POST"]), _op("end")],
		"POST": [_op("release"), _op("end")],
	}, texts), FlagStore.new())
	d5.start("A")
	_run(d5)
	d5.resume_after_battle(true)
	_chk("L.10 the 5-arg form's event_script is at position 4, not 3 "
			+ "(`not_enough_pkmn_text` sits between lose_text and it)",
			d5.script_label == "POST")

	var d6 := ScriptVM.new(_src({
		"A": [_op("trainerbattle_double",
				["TRAINER_DUO", "Intro", "Defeat", "NotEnough", "POST", "NO_MUSIC"]),
				_op("end")],
		"POST": [_op("release"), _op("end")],
	}, texts), FlagStore.new())
	d6.start("A")
	_run(d6)
	d6.resume_after_battle(true)
	_chk("L.11 the 6-arg NO_MUSIC form still resolves the same continuation",
			d6.script_label == "POST")

	# -- trainerbattle_rematch: the already-beaten check is DELIBERATELY
	# bypassed. Source remaps through GetRematchTrainerId before that check is
	# ever reached; this project has no rematch-tier table, so the disclosed
	# simplification is "fight the same roster again", which only works if the
	# already-beaten gate does not itself refuse the rematch. -- the key
	# discriminator for this whole family.
	var beaten_r := FlagStore.new()
	beaten_r.set_trainer_defeated("TRAINER_RIVAL")
	var rematch := ScriptVM.new(_src({
		"A": [_op("trainerbattle_rematch", ["TRAINER_RIVAL", "Intro", "Defeat"]),
				_op("end")],
	}, texts), beaten_r)
	rematch.start("A")
	_run(rematch)
	_chk("L.12 trainerbattle_rematch starts even against an ALREADY-BEATEN "
			+ "trainer -- ordinary trainerbattle_single would refuse this",
			rematch.pause_reason == ScriptVM.Pause.WAIT_BATTLE)
	_chk("L.13 carrying the (unchanged, unremapped) trainer key",
			rematch.pending_trainer_key == "TRAINER_RIVAL")

	# Regression guard in the OTHER direction: an ordinary trainerbattle_single
	# against that same already-beaten trainer must still be refused, so L.12
	# is proven to be the rematch opcode's own behaviour, not a FlagStore bug.
	var single_vs_beaten := ScriptVM.new(_src({
		"A": [_op("trainerbattle_single", ["TRAINER_RIVAL", "Intro", "Defeat"]),
				_op("end")],
	}, texts), beaten_r)
	single_vs_beaten.start("A")
	_run(single_vs_beaten)
	_chk("L.14 discriminator: trainerbattle_single vs the SAME already-beaten "
			+ "trainer is correctly refused, proving L.12 is real",
			single_vs_beaten.pause_reason != ScriptVM.Pause.WAIT_BATTLE)

	var rematch_double := ScriptVM.new(_src({
		"A": [_op("trainerbattle_rematch_double",
				["TRAINER_RIVAL", "Intro", "Defeat", "NotEnough"]), _op("end")],
	}, texts), beaten_r)
	rematch_double.start("A")
	_run(rematch_double)
	_chk("L.15 trainerbattle_rematch_double also bypasses the already-beaten "
			+ "check", rematch_double.pause_reason == ScriptVM.Pause.WAIT_BATTLE)

	var rematch_double_short := ScriptVM.new(_src({
		"A": [_op("trainerbattle_rematch_double", ["TRAINER_RIVAL", "Intro"]),
				_op("end")],
	}, texts), FlagStore.new())
	rematch_double_short.start("A")
	_run(rematch_double_short)
	_chk("L.16 too few args is UNKNOWN_OP here too",
			rematch_double_short.pause_reason == ScriptVM.Pause.UNKNOWN_OP)

	# -- trainerbattle_earlyrival: `trainer, flags, lose_text, victory_text`.
	# Shares `EventScript_DoNoIntroTrainerBattle` with `trainerbattle_no_intro`
	# above -- no intro message, and (unlike trainerbattle_rematch) the
	# ordinary already-beaten check is NOT bypassed, since source dispatches
	# it through the same `SetMapVarsToTrainerA` path as a first-time battle,
	# not through `GetRematchTrainerId`.
	var flags_er := FlagStore.new()
	var er := ScriptVM.new(_src({
		"A": [_op("trainerbattle_earlyrival",
				["TRAINER_RIVAL_OAKS_LAB", "RIVAL_BATTLE_TUTORIAL", "Defeat", "Victory"]),
				_op("lockall"), _op("end")],
	}, texts), flags_er)
	er.start("A")
	_run(er)
	_chk("L.17 trainerbattle_earlyrival pauses on WAIT_BATTLE",
			er.pause_reason == ScriptVM.Pause.WAIT_BATTLE)
	_chk("L.18 with NO intro message -- intro_text_a is NULL in the macro's "
			+ "own expansion (event.inc:831-832)", er.pending_pages.is_empty())
	_chk("L.19 the defeat text is args[2] (lose_text), NOT args[1] (flags)",
			er.pending_battle_defeat_text == "Defeat")
	er.resume_after_battle(true)
	_chk("L.20 winning FALLS THROUGH here too -- the identical shared-handler "
			+ "reasoning as trainerbattle_no_intro's L.05",
			er.pause_reason == ScriptVM.Pause.NONE)
	_run(er)
	_chk("L.20b ...and reaches the calling script's own end",
			er.pause_reason == ScriptVM.Pause.DONE)

	var er_beaten := FlagStore.new()
	er_beaten.set_trainer_defeated("TRAINER_RIVAL_OAKS_LAB")
	var er2 := ScriptVM.new(_src({
		"A": [_op("trainerbattle_earlyrival",
				["TRAINER_RIVAL_OAKS_LAB", "RIVAL_BATTLE_TUTORIAL", "Defeat", "Victory"]),
				_op("lockall"), _op("end")],
	}, texts), er_beaten)
	er2.start("A")
	_run(er2)
	_chk("L.21 UNLIKE trainerbattle_rematch, an already-beaten rival battle "
			+ "IS skipped -- this variant has no rematch-tier remap to bypass "
			+ "the check for", er2.pause_reason == ScriptVM.Pause.DONE)

	var er_short := ScriptVM.new(_src({
		"A": [_op("trainerbattle_earlyrival", ["TRAINER_RIVAL_OAKS_LAB", "Flags"]),
				_op("end")],
	}, texts), FlagStore.new())
	er_short.start("A")
	_run(er_short)
	_chk("L.22 too few args is UNKNOWN_OP, not a crash",
			er_short.pause_reason == ScriptVM.Pause.UNKNOWN_OP
			and er_short.diagnostic.contains("trainerbattle_earlyrival"))

	# -- the real compiled corpus: the Bulbasaur-branch rival battle, driven
	# end to end through the real EndRivalBattle chain.
	if not (FileAccess.file_exists("res://data/map_scripts.json")
			and FileAccess.file_exists("res://data/map_texts.json")):
		_gated += 4
		return
	var ops_er: Dictionary = JSON.parse_string(
			FileAccess.open("res://data/map_scripts.json", FileAccess.READ).get_as_text())
	var texts_er: Dictionary = JSON.parse_string(
			FileAccess.open("res://data/map_texts.json", FileAccess.READ).get_as_text())
	var flags_real := FlagStore.new()
	var party_real := BattleParty.new()
	party_real.members = [PokemonFactory.create_battle_pokemon(1, 5)]
	var vm_real := ScriptVM.new(_src(ops_er, texts_er), flags_real)
	vm_real.party = party_real
	vm_real.start("PalletTown_ProfessorOaksLab_EventScript_RivalBattleBulbasaur")
	_drive(vm_real)
	_chk("L.23 the real compiled starter-rival script reaches WAIT_BATTLE with "
			+ "the real trainer key (diagnostic if not: '%s')" % vm_real.diagnostic,
			vm_real.pause_reason == ScriptVM.Pause.WAIT_BATTLE
			and vm_real.pending_trainer_key == "TRAINER_RIVAL_OAKS_LAB_BULBASAUR_FRLG")
	vm_real.resume_after_battle(true)
	_drive(vm_real)
	_chk("L.24 ...and winning runs the WHOLE real EndRivalBattle chain to DONE "
			+ "(diagnostic if not: '%s')" % vm_real.diagnostic,
			vm_real.pause_reason == ScriptVM.Pause.DONE)
	_chk("L.24b -- with the real post-battle state genuinely set: "
			+ "VAR_MAP_SCENE advanced to 4 and FLAG_BEAT_RIVAL_IN_OAKS_LAB set",
			flags_real.var_get("VAR_MAP_SCENE_PALLET_TOWN_PROFESSOR_OAKS_LAB") == 4
			and flags_real.flag_get("FLAG_BEAT_RIVAL_IN_OAKS_LAB"))
	_chk("L.24c -- and the party was genuinely healed by the real "
			+ "HealPlayerParty special this chain calls",
			party_real.members[0].current_hp == party_real.members[0].max_hp)


## Section M -- the small opcode batch: checkplayergender, random,
## setorcopyvar, the audio no-ops, bufferboxname, fadescreen's two siblings,
## and the symbolic-constant table.
func _test_small_opcode_batch() -> void:
	# -- checkplayergender --
	var prior_identity: PlayerIdentity = TextBuffers.identity
	var girl := PlayerIdentity.new()
	girl.gender = PlayerIdentity.Gender.GIRL
	TextBuffers.identity = girl
	var flags_g := FlagStore.new()
	var vm_g := ScriptVM.new(_src({
		"A": [_op("checkplayergender"), _op("end")],
	}), flags_g)
	vm_g.start("A")
	_run(vm_g)
	_chk("M.01 checkplayergender writes the real chosen gender (GIRL == 1)",
			flags_g.var_get("VAR_RESULT") == 1)

	var boy := PlayerIdentity.new()
	boy.gender = PlayerIdentity.Gender.BOY
	TextBuffers.identity = boy
	var flags_b := FlagStore.new()
	var vm_b := ScriptVM.new(_src({
		"A": [_op("checkplayergender"), _op("end")],
	}), flags_b)
	vm_b.start("A")
	_run(vm_b)
	_chk("M.02 and the other direction (BOY == 0)", flags_b.var_get("VAR_RESULT") == 0)
	# ⚠️ `TextBuffers.identity` is a class-level static -- leaving it set would
	# leak into every OTHER suite run in this same process.
	TextBuffers.identity = prior_identity

	# -- random --
	var flags_r := FlagStore.new()
	var seen := {}
	var in_range := true
	for i in range(200):
		var vm_r := ScriptVM.new(_src({"A": [_op("random", ["6"]), _op("end")]}), flags_r)
		vm_r.start("A")
		_run(vm_r)
		var v := flags_r.var_get("VAR_RESULT")
		seen[v] = true
		if v < 0 or v >= 6:
			in_range = false
	_chk("M.03 random limit stays within [0, limit) across 200 rolls", in_range)
	_chk("M.04 and is not a constant (real randomness, not a stub)", seen.size() > 1)

	var flags_r1 := FlagStore.new()
	var vm_r1b := ScriptVM.new(_src({"A": [_op("random", ["1"]), _op("end")]}), flags_r1)
	vm_r1b.start("A")
	_run(vm_r1b)
	_chk("M.05 random 1 always rolls 0 -- the only value in [0, 1)",
			flags_r1.var_get("VAR_RESULT") == 0)

	var flags_r0 := FlagStore.new()
	var vm_r0 := ScriptVM.new(_src({"A": [_op("random", ["0"]), _op("end")]}), flags_r0)
	vm_r0.start("A")
	_run(vm_r0)
	_chk("M.06 random 0 is defensive, not source-observed UB -- reports 0 "
			+ "rather than crashing", flags_r0.var_get("VAR_RESULT") == 0)

	# -- setorcopyvar --
	var flags_sc := FlagStore.new()
	flags_sc.var_set("SRC", 42)
	var vm_sc := ScriptVM.new(_src({
		"A": [_op("setorcopyvar", ["DST", "SRC"]), _op("end")],
	}), flags_sc)
	vm_sc.start("A")
	_run(vm_sc)
	_chk("M.07 setorcopyvar copies through the variable store, like copyvar",
			flags_sc.var_get("DST") == 42)

	# -- waitse / playmoncry / waitmoncry: audio does not exist, same no-op
	# class as playfanfare/waitfanfare/playse/playbgm/fadedefaultbgm --
	var vm_snd := ScriptVM.new(_src({
		"A": [_op("playmoncry", ["SPECIES_PIKACHU", "0"]), _op("waitmoncry"),
				_op("waitse"), _op("end")],
	}), FlagStore.new())
	vm_snd.start("A")
	_run(vm_snd)
	_chk("M.08 waitse/playmoncry/waitmoncry are no-ops, not a stall",
			vm_snd.pause_reason == ScriptVM.Pause.DONE)

	# -- [Corridor op-code scope] fadeoutbgm joins the same audio no-op group
	# -- its one corridor use is the Pokémon Center Jigglypuff easter egg --
	var vm_fob := ScriptVM.new(_src({
		"A": [_op("fadeoutbgm", ["0"]), _op("end")],
	}), FlagStore.new())
	vm_fob.start("A")
	_run(vm_fob)
	_chk("M.08b fadeoutbgm is a no-op, same class as playbgm/playse",
			vm_fob.pause_reason == ScriptVM.Pause.DONE)

	# -- [Corridor op-code scope] copyobjectxytoperm: a documented no-op.
	# This project has no template/instance split -- a placed NPC's own
	# `cell` is already the live source of truth within one play session,
	# so the position "sticks" with zero code. The real gap (save/reload
	# persistence) is a general M27L save-completeness question, not
	# something to solve one-off here. --
	var vm_cxy := ScriptVM.new(_src({
		"A": [_op("copyobjectxytoperm", ["LOCALID_PALLET_SIGN_LADY"]), _op("end")],
	}), FlagStore.new())
	vm_cxy.start("A")
	_run(vm_cxy)
	_chk("M.08c copyobjectxytoperm is a no-op, not a halt",
			vm_cxy.pause_reason == ScriptVM.Pause.DONE)

	# -- bufferboxname: a real halt, matching _begin_nickname's own PC branch --
	var vm_box := ScriptVM.new(_src({
		"A": [_op("bufferboxname", ["0", "1"]), _op("end")],
	}), FlagStore.new())
	vm_box.start("A")
	_run(vm_box)
	_chk("M.09 bufferboxname halts (no PC exists), rather than inventing a name",
			vm_box.pause_reason == ScriptVM.Pause.UNKNOWN_OP)
	_chk("M.10 and names the real reason -- no PC, not a bad parse",
			vm_box.diagnostic.contains("PC"))

	# -- fadescreenspeed / fadescreenswapbuffers: named but excluded when
	# fadescreen itself shipped -- same no-op reasoning, now included --
	var vm_fade := ScriptVM.new(_src({
		"A": [_op("fadescreen", ["FADE_TO_BLACK"]), _op("fadescreenspeed", ["2"]),
				_op("fadescreenswapbuffers"), _op("end")],
	}), FlagStore.new())
	vm_fade.start("A")
	_run(vm_fade)
	_chk("M.11 fadescreenspeed/fadescreenswapbuffers are no-ops too",
			vm_fade.pause_reason == ScriptVM.Pause.DONE)

	# -- the symbolic-constant table, reached through addvar/subvar directly
	# (money opcodes get their own coverage in m27i_wallet_test.gd) --
	var flags_sym := FlagStore.new()
	flags_sym.var_set("VAR_0x8004", 0)
	var vm_sym := ScriptVM.new(_src({
		"A": [_op("addvar", ["VAR_0x8004", "ROULETTE_SPECIAL_RATE"]), _op("end")],
	}), flags_sym)
	vm_sym.start("A")
	_run(vm_sym)
	_chk("M.12 addvar resolves ROULETTE_SPECIAL_RATE to its real value, 1<<7",
			flags_sym.var_get("VAR_0x8004") == 128)

	var flags_sym2 := FlagStore.new()
	flags_sym2.var_set("VAR_0x8004", 5000)
	var vm_sym2 := ScriptVM.new(_src({
		"A": [_op("subvar", ["VAR_0x8004", "BLACK_FLUTE_PRICE"]), _op("end")],
	}), flags_sym2)
	vm_sym2.start("A")
	_run(vm_sym2)
	_chk("M.13 subvar resolves BLACK_FLUTE_PRICE to its real value, 1000",
			flags_sym2.var_get("VAR_0x8004") == 4000)

	# Regression guard: a genuinely-unknown constant still resolves to 0, the
	# pre-existing `_literal` fallback -- proving the table is additive, not a
	# blanket "any unresolved name resolves to something" change.
	var flags_sym3 := FlagStore.new()
	flags_sym3.var_set("VAR_0x8004", 10)
	var vm_sym3 := ScriptVM.new(_src({
		"A": [_op("addvar", ["VAR_0x8004", "SOME_TRULY_UNKNOWN_CONSTANT"]), _op("end")],
	}), flags_sym3)
	vm_sym3.start("A")
	_run(vm_sym3)
	_chk("M.14 an unlisted constant still resolves to 0, unchanged",
			flags_sym3.var_get("VAR_0x8004") == 10)


## Section N -- [M27G G1] the real Tier 0 batch: signmsg/normalmsg,
## DisableMsgBoxWalkaway/SetWalkingIntoSignVars/OpenMuseumFossilPic/
## CloseMuseumFossilPic (no-ops), ScriptGetPartyMonSpecies/BufferMonNickname
## (party-context bridges), and the real Running Shoes script end to end.
##
## `docs/m27g_recon.md` is the scope of record. The headline: only 51 of the
## region-wide corpus's 567 special/specialvar functions are reachable from
## this project's own 32 baked maps at all, and the Running Shoes NPC
## (`PewterCity_EventScript_AideGiveRunningShoes`) is real, in-corridor
## content whose own script tail is `setflag FLAG_SYS_B_DASH` -- the first
## genuine in-game trigger for Run, previously granted only by the debug boot.
func _test_m27g_g1_batch() -> void:
	# -- signmsg / normalmsg: no-ops, matching source's own ScrCmd_nop1 --
	var vm_msg := ScriptVM.new(_src({
		"A": [_op("signmsg"), _op("message", ["T"]), _op("waitmessage"),
				_op("waitbuttonpress"), _op("normalmsg"), _op("end")],
	}, {"T": ["Hi."]}), FlagStore.new())
	vm_msg.start("A")
	_drive(vm_msg)
	_chk("N.01 signmsg/normalmsg are no-ops -- the script reaches DONE",
			vm_msg.pause_reason == ScriptVM.Pause.DONE)

	# -- the four new no-op specials --
	var vm_noop := ScriptVM.new(_src({
		"A": [_op("special", ["DisableMsgBoxWalkaway"]),
				_op("special", ["SetWalkingIntoSignVars"]),
				_op("special", ["OpenMuseumFossilPic"]),
				_op("special", ["CloseMuseumFossilPic"]), _op("end")],
	}), FlagStore.new())
	vm_noop.start("A")
	_run(vm_noop)
	_chk("N.02 all four new no-op specials run to DONE without halting",
			vm_noop.pause_reason == ScriptVM.Pause.DONE)

	# -- ScriptGetPartyMonSpecies: party-only, no PC fallback --
	var flags_sp := FlagStore.new()
	flags_sp.var_set("VAR_0x8004", 1)
	var party_sp := BattleParty.new()
	party_sp.members = [PokemonFactory.create_battle_pokemon(1, 5),
			PokemonFactory.create_battle_pokemon(4, 5)]  # Bulbasaur, Charmander
	var vm_sp := ScriptVM.new(_src({
		"A": [_op("specialvar", ["VAR_RESULT", "ScriptGetPartyMonSpecies"]), _op("end")],
	}), flags_sp)
	vm_sp.party = party_sp
	vm_sp.start("A")
	_run(vm_sp)
	_chk("N.03 ScriptGetPartyMonSpecies reads the REAL chosen slot's species "
			+ "(slot 1 == Charmander == dex 4)",
			flags_sp.var_get("VAR_RESULT") == 4)

	var flags_sp2 := FlagStore.new()
	flags_sp2.var_set("VAR_0x8004", 0)
	var vm_sp2 := ScriptVM.new(_src({
		"A": [_op("specialvar", ["VAR_RESULT", "ScriptGetPartyMonSpecies"]), _op("end")],
	}), flags_sp2)
	vm_sp2.party = party_sp
	vm_sp2.start("A")
	_run(vm_sp2)
	_chk("N.04 discriminator: slot 0 reads Bulbasaur, not slot 1's Charmander "
			+ "-- proving the slot is actually read, not hardcoded",
			flags_sp2.var_get("VAR_RESULT") == 1)

	var flags_sp3 := FlagStore.new()
	flags_sp3.var_set("VAR_0x8004", 99)
	var vm_sp3 := ScriptVM.new(_src({
		"A": [_op("specialvar", ["VAR_RESULT", "ScriptGetPartyMonSpecies"]), _op("end")],
	}), flags_sp3)
	vm_sp3.party = party_sp
	vm_sp3.start("A")
	_run(vm_sp3)
	_chk("N.05 an out-of-range slot degrades to 0, not a crash or a halt",
			flags_sp3.var_get("VAR_RESULT") == 0 and vm_sp3.pause_reason == ScriptVM.Pause.DONE)

	# -- BufferMonNickname: party-only here too (this project has no PC), but
	# the PC sentinel is still guarded exactly like _begin_nickname's own --
	var flags_bn := FlagStore.new()
	flags_bn.var_set("VAR_0x8004", 0)
	var party_bn := BattleParty.new()
	var nicked: BattlePokemon = PokemonFactory.create_battle_pokemon(7, 5)  # Squirtle
	nicked.nickname = "SHELLY"
	party_bn.members = [nicked]
	var vm_bn := ScriptVM.new(_src({
		"A": [_op("special", ["BufferMonNickname"]), _op("end")],
	}), flags_bn)
	vm_bn.party = party_bn
	vm_bn.start("A")
	_run(vm_bn)
	_chk("N.06 BufferMonNickname writes the REAL nickname into slot 0 "
			+ "(STR_VAR_1 / gStringVar1)",
			vm_bn.buffers.get_slot(0) == "SHELLY")

	var flags_bn_pc := FlagStore.new()
	flags_bn_pc.var_set("VAR_0x8004", ScriptVM.PC_MON_CHOSEN)
	var vm_bn_pc := ScriptVM.new(_src({
		"A": [_op("special", ["BufferMonNickname"]), _op("end")],
	}), flags_bn_pc)
	vm_bn_pc.party = party_bn
	vm_bn_pc.start("A")
	_run(vm_bn_pc)
	_chk("N.07 BufferMonNickname's PC branch halts (no PC exists), the same "
			+ "precedent _begin_nickname's own PC branch already established",
			vm_bn_pc.pause_reason == ScriptVM.Pause.UNKNOWN_OP
			and vm_bn_pc.diagnostic.contains("PC"))

	# -- the real compiled corpus: the Running Shoes NPC, end to end --
	if not (FileAccess.file_exists("res://data/map_scripts.json")
			and FileAccess.file_exists("res://data/map_texts.json")):
		_gated += 1
		return
	var ops: Dictionary = JSON.parse_string(
			FileAccess.open("res://data/map_scripts.json", FileAccess.READ).get_as_text())
	var texts: Dictionary = JSON.parse_string(
			FileAccess.open("res://data/map_texts.json", FileAccess.READ).get_as_text())
	var flags_rs := FlagStore.new()
	var vm_rs := ScriptVM.new(_src(ops, texts), flags_rs)
	vm_rs.start("PewterCity_EventScript_AideGiveRunningShoes")
	# `_drive` alone does not push through WAIT_MOVEMENT (the script's own
	# exclamation-mark + delay applymovement pair) -- resume it manually, the
	# same "no result to branch on" shape `[M27F Stage 3]` already documents.
	var n := 0
	while n < 30 and not vm_rs.is_finished():
		_drive(vm_rs)
		if vm_rs.pause_reason == ScriptVM.Pause.WAIT_MOVEMENT:
			vm_rs.resume()
		elif vm_rs.pause_reason == ScriptVM.Pause.NONE:
			pass
		else:
			break
		n += 1
	_chk("N.08 the REAL Running Shoes script runs to completion, not a halt "
			+ "(diagnostic if not: '%s')" % vm_rs.diagnostic,
			vm_rs.pause_reason == ScriptVM.Pause.DONE)
	_chk("N.09 and sets FLAG_SYS_B_DASH -- the first real in-game Run unlock, "
			+ "previously granted only by the debug boot",
			flags_rs.flag_get("FLAG_SYS_B_DASH"))


## Section O -- [M27G G2] `special ChoosePartyMon`, bridging to the already-built
## `FieldPartyScreen` in browse mode. Dispatched directly inside `step()`
## (not through `FieldSpecials`, which is deliberately stateless) since it
## needs real party context, the same precedent `ChangePokemonNickname` set.
##
## O.01-O.07 exercise the VM contract in isolation -- `WAIT_PARTY_CHOICE` is a
## RESULT-carrying pause (a plain `resume()` cannot clear it, only
## `answer_party_choice()` can), matching `WAIT_BATTLE`/`WAIT_NAMING`'s own
## shape. O.08-O.10 drive the real compiled `PalletTown_RivalsHouse_
## EventScript_GroomMon` script, which is what actually caught a real,
## GENERAL (not Hoenn-only) gap along the way: `PARTY_SIZE` -- 57 region-wide
## corpus uses, most in exactly this script's own very next opcode after
## `ChoosePartyMon`, `goto_if_ge VAR_0x8004, PARTY_SIZE, DeclineGrooming` --
## was unresolved by `_literal` and fell through to 0, so EVERY such check
## always took the Decline branch regardless of what was actually picked.
## Fixed at `_literal` directly (`script_vm.gd`), not here.
func _test_m27g_g2_choose_party_mon() -> void:
	var party_o := BattleParty.new()
	party_o.members = [PokemonFactory.create_battle_pokemon(1, 5),
			PokemonFactory.create_battle_pokemon(4, 5)]  # Bulbasaur, Charmander

	# -- the VM contract, in isolation --
	var flags_o := FlagStore.new()
	var vm_o := ScriptVM.new(_src({
		"A": [_op("special", ["ChoosePartyMon"]), _op("message", ["T"]),
				_op("waitmessage"), _op("end")],
	}, {"T": ["Chosen."]}), flags_o)
	vm_o.party = party_o
	vm_o.start("A")
	vm_o.step()
	_chk("O.01 special ChoosePartyMon pauses on WAIT_PARTY_CHOICE, not DONE",
			vm_o.pause_reason == ScriptVM.Pause.WAIT_PARTY_CHOICE)
	_chk("O.02 is_waiting() is true while WAIT_PARTY_CHOICE", vm_o.is_waiting())

	vm_o.resume()
	_chk("O.03 a plain resume() does NOT clear WAIT_PARTY_CHOICE -- it carries "
			+ "a result, the same shape as WAIT_BATTLE/WAIT_NAMING",
			vm_o.pause_reason == ScriptVM.Pause.WAIT_PARTY_CHOICE)

	vm_o.answer_party_choice(1)
	_chk("O.04 answer_party_choice(1) writes the real slot into VAR_0x8004",
			flags_o.var_get("VAR_0x8004") == 1)
	_chk("O.04b ...and clears the pause, letting the script continue to DONE",
			_drive(vm_o).size() > 0 and vm_o.pause_reason == ScriptVM.Pause.DONE)

	var flags_cancel := FlagStore.new()
	var vm_cancel := ScriptVM.new(_src({
		"A": [_op("special", ["ChoosePartyMon"]), _op("end")],
	}), flags_cancel)
	vm_cancel.party = party_o
	vm_cancel.start("A")
	vm_cancel.step()
	vm_cancel.answer_party_choice(-1)
	_chk("O.05 a cancel (-1) writes PARTY_NOTHING_CHOSEN (0xFF), not -1 itself",
			flags_cancel.var_get("VAR_0x8004") == ScriptVM.PARTY_NOTHING_CHOSEN)

	var flags_oob := FlagStore.new()
	var vm_oob := ScriptVM.new(_src({
		"A": [_op("special", ["ChoosePartyMon"]), _op("end")],
	}), flags_oob)
	vm_oob.party = party_o
	vm_oob.start("A")
	vm_oob.step()
	vm_oob.answer_party_choice(99)
	_chk("O.06 an out-of-range index also degrades to PARTY_NOTHING_CHOSEN, "
			+ "matching source's own >= PARTY_SIZE check rather than trusting "
			+ "the screen's own -1 convention is the only 'nothing' shape",
			flags_oob.var_get("VAR_0x8004") == ScriptVM.PARTY_NOTHING_CHOSEN)

	var flags_ignored := FlagStore.new()
	var vm_ignored := ScriptVM.new(_src({
		"A": [_op("special", ["ChoosePartyMon"]), _op("end")],
	}), flags_ignored)
	vm_ignored.party = party_o
	vm_ignored.start("A")
	vm_ignored.step()
	vm_ignored.answer_party_choice(0)
	_run(vm_ignored)
	vm_ignored.answer_party_choice(1)
	_chk("O.07 answer_party_choice is a no-op once the pause has already been "
			+ "resolved -- the second call cannot silently overwrite VAR_0x8004",
			flags_ignored.var_get("VAR_0x8004") == 0)

	# -- the real compiled corpus: Daisy's grooming script, end to end --
	if not (FileAccess.file_exists("res://data/map_scripts.json")
			and FileAccess.file_exists("res://data/map_texts.json")):
		_gated += 1
		return
	var ops_o: Dictionary = JSON.parse_string(
			FileAccess.open("res://data/map_scripts.json", FileAccess.READ).get_as_text())
	var texts_o: Dictionary = JSON.parse_string(
			FileAccess.open("res://data/map_texts.json", FileAccess.READ).get_as_text())
	var flags_gm := FlagStore.new()
	# The script's own FIRST opcode branches on a cooldown-step counter --
	# `goto_if_lt VAR_MASSAGE_COOLDOWN_STEP_COUNTER, 500, ...RateMonFriendship`
	# -- and an unset var reads 0, which is < 500, so an unprimed run would
	# take the RATING branch (needing the unimplemented `GetLeadMonFriendship`)
	# before ever reaching the grooming offer this test is actually about.
	flags_gm.var_set("VAR_MASSAGE_COOLDOWN_STEP_COUNTER", 999)
	var vm_gm := ScriptVM.new(_src(ops_o, texts_o), flags_gm)
	vm_gm.party = party_o
	vm_gm.start("PalletTown_RivalsHouse_EventScript_GroomMon")
	# The offer's own yes/no, then WAIT_PARTY_CHOICE.
	_drive(vm_gm)
	if vm_gm.pause_reason == ScriptVM.Pause.WAIT_YES_NO:
		vm_gm.answer_yes_no(true)
	_drive(vm_gm)
	_chk("O.08 the real script reaches WAIT_PARTY_CHOICE (diagnostic if not: "
			+ "'%s')" % vm_gm.diagnostic,
			vm_gm.pause_reason == ScriptVM.Pause.WAIT_PARTY_CHOICE)
	vm_gm.answer_party_choice(1)  # Charmander, dex 4
	_drive(vm_gm)
	_chk("O.09 -- and the PARTY_SIZE fix itself: ScriptGetPartyMonSpecies "
			+ "genuinely ran (VAR_RESULT holds Charmander's real dex, 4) -- had "
			+ "PARTY_SIZE stayed unresolved-to-0, the script would have taken "
			+ "the Decline branch unconditionally and this would still read 0",
			flags_gm.var_get("VAR_RESULT") == 4)
	_chk("O.10 the script then halts at the one real blocker left -- special "
			+ "DaisyMassageServices, which needs a friendship system this "
			+ "project doesn't have -- not a halt anywhere EARLIER than that",
			vm_gm.pause_reason == ScriptVM.Pause.UNKNOWN_OP
			and vm_gm.diagnostic.contains("DaisyMassageServices"))


## Section P -- [M27G G3a] In-game trade: `GetTradeSpecies`/
## `GetInGameTradeSpeciesInfo`/`CreateInGameTradePokemon`, plus the
## `INGAME_TRADE_*` `_literal` fix and `data/ingame_trades.json` itself.
##
## `docs/m27g_recon.md`'s "G3 Step 0" section is the scope of record. P.01-P.09
## exercise each piece directly, via real opcode dispatch (never a private
## function call) matching every earlier section's own discipline. P.10-P.13
## drive the REAL compiled `Route2_House_EventScript_Reyley` (Mr. Mime <->
## Abra) end to end across all four of its own branches -- success, wrong
## species offered, decline, and already-traded -- since a VM contract that
## passes in isolation but never actually reaches the corpus's own real
## dispatch order is exactly the class of gap G1/G2 both found this way.
func _test_m27g_g3a_ingame_trade() -> void:
	# -- the _literal fix, general not selective (matching PARTY_SIZE's own
	# "resolves to a real number is strictly safer than 0" precedent) --
	var flags_lit := FlagStore.new()
	var vm_lit := ScriptVM.new(_src({
		"A": [_op("setvar", ["VAR_TEMP_0", "INGAME_TRADE_MR_MIME"]),
				_op("setvar", ["VAR_TEMP_1", "INGAME_TRADE_SEEL"]),
				_op("setvar", ["VAR_TEMP_2", "INGAME_TRADE_SEEDOT"]), _op("end")],
	}), flags_lit)
	vm_lit.start("A")
	_run(vm_lit)
	_chk("P.01 INGAME_TRADE_MR_MIME resolves to its real enum value (4), "
			+ "not the unresolved-constant fallthrough (0)",
			flags_lit.var_get("VAR_TEMP_0") == 4)
	_chk("P.01b INGAME_TRADE_SEEL (the last entry, 12) resolves too",
			flags_lit.var_get("VAR_TEMP_1") == 12)
	_chk("P.01c INGAME_TRADE_SEEDOT (the RSE-only first entry, unreachable "
			+ "from any FRLG script but kept anyway) resolves to 0 -- the "
			+ "real enum value, not a coincidental match with the old "
			+ "unresolved fallthrough",
			flags_lit.var_get("VAR_TEMP_2") == 0)

	# -- the data table itself --
	var mimien := IngameTradeRegistry.entry(4)
	_chk("P.02 IngameTradeRegistry.entry(4) is the real Mr. Mime row",
			mimien.get("nickname") == "MIMIEN"
			and int(mimien.get("species", 0)) == 122
			and int(mimien.get("requested_species", 0)) == 63)
	_chk("P.02b an out-of-range index degrades to {} rather than crashing",
			IngameTradeRegistry.entry(99).is_empty())

	# -- the real bug this trade test found: a 3-arg conditional's SECOND
	# operand must resolve through _resolve_number (var-then-literal), not
	# _literal directly -- 17 region-wide corpus uses compare two VARIABLES
	# (goto_if_ne VAR_RESULT, VAR_0x8009, ...), 7 of them this exact
	# in-game-trade "did the player offer the right species" check. Before
	# this fix, `_literal("VAR_0x8009")` always fell through to 0, so a
	# genuinely correct trade was misread as wrong on every single one --
	var flags_cmp := FlagStore.new()
	flags_cmp.var_set("VAR_RESULT", 63)
	flags_cmp.var_set("VAR_0x8009", 63)
	var vm_cmp := _cond_vm("goto_if_ne", ["VAR_RESULT", "VAR_0x8009", "T"], flags_cmp)
	_chk("P.02c a 3-arg conditional correctly compares VARIABLE against "
			+ "VARIABLE (63 == 63, goto_if_ne must NOT branch)",
			vm_cmp.script_label == "A")
	flags_cmp.var_set("VAR_0x8009", 61)
	var vm_cmp2 := _cond_vm("goto_if_ne", ["VAR_RESULT", "VAR_0x8009", "T"], flags_cmp)
	_chk("P.02d -- and DOES branch when the two variables genuinely differ "
			+ "(63 != 61) -- the discriminator proving this isn't just "
			+ "'always take the fallthrough' in disguise",
			vm_cmp2.script_label == "T")
	var flags_cmp3 := FlagStore.new()
	flags_cmp3.var_set("VAR_TEMP_0", 5)
	var vm_cmp3 := _cond_vm("goto_if_eq", ["VAR_TEMP_0", "5", "T"], flags_cmp3)
	_chk("P.02e regression guard: a var-vs-LITERAL comparison (the "
			+ "overwhelming majority of the corpus's 4366 3-arg conditionals) "
			+ "is completely unaffected by this fix",
			vm_cmp3.script_label == "T")

	var party_p := BattleParty.new()
	party_p.members = [PokemonFactory.create_battle_pokemon(1, 5),   # Bulbasaur
			PokemonFactory.create_battle_pokemon(63, 5)]              # Abra

	# -- GetTradeSpecies: the SAME lookup as G1's ScriptGetPartyMonSpecies --
	var flags_gts := FlagStore.new()
	flags_gts.var_set("VAR_0x8004", 1)
	var vm_gts := ScriptVM.new(_src({
		"A": [_op("specialvar", ["VAR_RESULT", "GetTradeSpecies"]), _op("end")],
	}), flags_gts)
	vm_gts.party = party_p
	vm_gts.start("A")
	_run(vm_gts)
	_chk("P.03 GetTradeSpecies reads the REAL chosen slot's species (slot 1 "
			+ "== Abra == dex 63)", flags_gts.var_get("VAR_RESULT") == 63)

	# -- GetInGameTradeSpeciesInfo: buffers both names, returns the requested
	# dex, argument order is source's own (requested first, given second) --
	var flags_info := FlagStore.new()
	flags_info.var_set("VAR_0x8005", 4)  # INGAME_TRADE_MR_MIME
	var vm_info := ScriptVM.new(_src({
		"A": [_op("specialvar", ["VAR_0x8009", "GetInGameTradeSpeciesInfo"]), _op("end")],
	}), flags_info)
	vm_info.party = party_p
	vm_info.start("A")
	_run(vm_info)
	_chk("P.04 GetInGameTradeSpeciesInfo returns the REQUESTED species' dex "
			+ "(Abra, 63) into the named var", flags_info.var_get("VAR_0x8009") == 63)
	_chk("P.04b slot 0 (STR_VAR_1) buffers the REQUESTED species' name",
			vm_info.buffers.get_slot(0) == str(PokemonRegistry.get_species(63).get("name", "")))
	_chk("P.04c slot 1 (STR_VAR_2) buffers the GIVEN-AWAY species' name -- "
			+ "source's own argument order, not alphabetical",
			vm_info.buffers.get_slot(1) == str(PokemonRegistry.get_species(122).get("name", "")))

	var flags_info_oob := FlagStore.new()
	flags_info_oob.var_set("VAR_0x8005", 99)
	var vm_info_oob := ScriptVM.new(_src({
		"A": [_op("specialvar", ["VAR_0x8009", "GetInGameTradeSpeciesInfo"]), _op("end")],
	}), flags_info_oob)
	vm_info_oob.party = party_p
	vm_info_oob.start("A")
	_run(vm_info_oob)
	_chk("P.05 an out-of-range trade row degrades to empty buffers and 0, "
			+ "not a crash or a halt",
			flags_info_oob.var_get("VAR_0x8009") == 0
			and vm_info_oob.buffers.get_slot(0) == "" and vm_info_oob.buffers.get_slot(1) == "")

	# -- CreateInGameTradePokemon: the actual party splice, SAME slot --
	var party_c := BattleParty.new()
	party_c.members = [PokemonFactory.create_battle_pokemon(1, 5),   # slot 0: untouched
			PokemonFactory.create_battle_pokemon(63, 12)]             # slot 1: the offer, level 12
	var flags_c := FlagStore.new()
	flags_c.var_set("VAR_0x8004", 1)
	flags_c.var_set("VAR_0x8005", 4)  # INGAME_TRADE_MR_MIME
	var vm_c := ScriptVM.new(_src({
		"A": [_op("special", ["CreateInGameTradePokemon"]), _op("end")],
	}), flags_c)
	vm_c.party = party_c
	vm_c.start("A")
	_run(vm_c)
	var traded_in: BattlePokemon = party_c.members[1]
	_chk("P.06 CreateInGameTradePokemon replaces the SAME slot the offer "
			+ "came from (slot 1) with a real Mr. Mime",
			traded_in != null and traded_in.species.national_dex_num == 122)
	_chk("P.06b slot 0 -- the untouched party member -- is exactly unchanged",
			party_c.members[0].species.national_dex_num == 1)
	_chk("P.06c the incoming mon's level is the OFFERED mon's own level (12), "
			+ "not a fixed value from the trade row",
			traded_in.level == 12)
	_chk("P.06d nickname is the real row value",
			traded_in.nickname == "MIMIEN")
	_chk("P.06e IVs are forced from the row, not randomly rolled",
			traded_in.ivs == [20, 15, 17, 24, 23, 22])
	_chk("P.06f friendship resets to the real source-constant 70, "
			+ "regardless of the row",
			traded_in.friendship == 70)

	# -- held item: resolves when a real .tres exists (Farfetch'd's own "
	# ITEM_STICK == ITEM_LEEK alias, already implemented since [M18g]), --
	# degrades to null when it does not (Mr. Mime's own trade holds nothing) --
	_chk("P.07 Mr. Mime's trade (ITEM_NONE) holds nothing",
			traded_in.held_item == null)

	var party_ff := BattleParty.new()
	party_ff.members = [PokemonFactory.create_battle_pokemon(1, 5)]
	var flags_ff := FlagStore.new()
	flags_ff.var_set("VAR_0x8004", 0)
	flags_ff.var_set("VAR_0x8005", 7)  # INGAME_TRADE_FARFETCHD
	var vm_ff := ScriptVM.new(_src({
		"A": [_op("special", ["CreateInGameTradePokemon"]), _op("end")],
	}), flags_ff)
	vm_ff.party = party_ff
	vm_ff.start("A")
	_run(vm_ff)
	var farfetchd: BattlePokemon = party_ff.members[0]
	_chk("P.08 Farfetch'd's real held item (Leek, ITEM_STICK's own alias, "
			+ "already implemented since [M18g]) resolves to a genuine ItemData",
			farfetchd.held_item != null and farfetchd.held_item.item_id == 393)

	var party_jx := BattleParty.new()
	party_jx.members = [PokemonFactory.create_battle_pokemon(1, 5)]
	var flags_jx := FlagStore.new()
	flags_jx.var_set("VAR_0x8004", 0)
	flags_jx.var_set("VAR_0x8005", 5)  # INGAME_TRADE_JYNX -- Fab Mail, no .tres
	var vm_jx := ScriptVM.new(_src({
		"A": [_op("special", ["CreateInGameTradePokemon"]), _op("end")],
	}), flags_jx)
	vm_jx.party = party_jx
	vm_jx.start("A")
	_run(vm_jx)
	_chk("P.08b Jynx's real held item (Fab Mail, a real ID with no .tres -- "
			+ "this project has no Mail concept) degrades to no item held, "
			+ "not a crash",
			party_jx.members[0].held_item == null)

	# -- DoInGameTradeScene: a pure no-op, matching the fadescreen precedent --
	var flags_scene := FlagStore.new()
	var vm_scene := ScriptVM.new(_src({
		"A": [_op("special", ["DoInGameTradeScene"]), _op("end")],
	}), flags_scene)
	vm_scene.start("A")
	_run(vm_scene)
	_chk("P.09 DoInGameTradeScene runs to DONE without halting",
			vm_scene.pause_reason == ScriptVM.Pause.DONE)

	# -- the real compiled corpus: Route2_House_EventScript_Reyley, all four
	# of its own branches --
	if not (FileAccess.file_exists("res://data/map_scripts.json")
			and FileAccess.file_exists("res://data/map_texts.json")):
		_gated += 1
		return
	var ops_p: Dictionary = JSON.parse_string(
			FileAccess.open("res://data/map_scripts.json", FileAccess.READ).get_as_text())
	var texts_p: Dictionary = JSON.parse_string(
			FileAccess.open("res://data/map_texts.json", FileAccess.READ).get_as_text())

	# Success: offer the real Abra (slot 1).
	var flags_r1 := FlagStore.new()
	var party_r1 := BattleParty.new()
	party_r1.members = [PokemonFactory.create_battle_pokemon(1, 10),
			PokemonFactory.create_battle_pokemon(63, 10)]
	var vm_r1 := ScriptVM.new(_src(ops_p, texts_p), flags_r1)
	vm_r1.party = party_r1
	vm_r1.start("Route2_House_EventScript_Reyley")
	_drive(vm_r1)
	if vm_r1.pause_reason == ScriptVM.Pause.WAIT_YES_NO:
		vm_r1.answer_yes_no(true)
	_drive(vm_r1)
	if vm_r1.pause_reason == ScriptVM.Pause.WAIT_PARTY_CHOICE:
		vm_r1.answer_party_choice(1)
	_drive(vm_r1)
	_chk("P.10 the real Reyley script runs to DONE on a successful trade "
			+ "(diagnostic if not: '%s')" % vm_r1.diagnostic,
			vm_r1.pause_reason == ScriptVM.Pause.DONE)
	_chk("P.10b -- and the party slot genuinely holds the real Mr. Mime",
			party_r1.members[1].species.national_dex_num == 122)
	_chk("P.10c -- and FLAG_DID_MIMIEN_TRADE is set, the real gate the "
			+ "already-traded branch reads",
			flags_r1.flag_get("FLAG_DID_MIMIEN_TRADE"))

	# Wrong species: offer the Bulbasaur (slot 0).
	var flags_r2 := FlagStore.new()
	var party_r2 := BattleParty.new()
	party_r2.members = [PokemonFactory.create_battle_pokemon(1, 10),
			PokemonFactory.create_battle_pokemon(63, 10)]
	var vm_r2 := ScriptVM.new(_src(ops_p, texts_p), flags_r2)
	vm_r2.party = party_r2
	vm_r2.start("Route2_House_EventScript_Reyley")
	_drive(vm_r2)
	if vm_r2.pause_reason == ScriptVM.Pause.WAIT_YES_NO:
		vm_r2.answer_yes_no(true)
	_drive(vm_r2)
	if vm_r2.pause_reason == ScriptVM.Pause.WAIT_PARTY_CHOICE:
		vm_r2.answer_party_choice(0)
	_drive(vm_r2)
	_chk("P.11 offering the wrong species reaches DONE via NotRequestedMon, "
			+ "not a halt (diagnostic if not: '%s')" % vm_r2.diagnostic,
			vm_r2.pause_reason == ScriptVM.Pause.DONE)
	_chk("P.11b -- and NEITHER party slot was mutated",
			party_r2.members[0].species.national_dex_num == 1
			and party_r2.members[1].species.national_dex_num == 63)
	_chk("P.11c -- and the flag was never set",
			not flags_r2.flag_get("FLAG_DID_MIMIEN_TRADE"))

	# Decline: answer NO to the initial offer.
	var flags_r3 := FlagStore.new()
	var party_r3 := BattleParty.new()
	party_r3.members = [PokemonFactory.create_battle_pokemon(63, 10)]
	var vm_r3 := ScriptVM.new(_src(ops_p, texts_p), flags_r3)
	vm_r3.party = party_r3
	vm_r3.start("Route2_House_EventScript_Reyley")
	_drive(vm_r3)
	if vm_r3.pause_reason == ScriptVM.Pause.WAIT_YES_NO:
		vm_r3.answer_yes_no(false)
	_drive(vm_r3)
	_chk("P.12 declining the offer reaches DONE without ever asking "
			+ "ChoosePartyMon (diagnostic if not: '%s')" % vm_r3.diagnostic,
			vm_r3.pause_reason == ScriptVM.Pause.DONE)
	_chk("P.12b -- and the one party member is untouched",
			party_r3.members[0].species.national_dex_num == 63)

	# Already traded: the flag is pre-set, so the script never even offers.
	var flags_r4 := FlagStore.new()
	flags_r4.flag_set("FLAG_DID_MIMIEN_TRADE")
	var party_r4 := BattleParty.new()
	party_r4.members = [PokemonFactory.create_battle_pokemon(63, 10)]
	var vm_r4 := ScriptVM.new(_src(ops_p, texts_p), flags_r4)
	vm_r4.party = party_r4
	vm_r4.start("Route2_House_EventScript_Reyley")
	_drive(vm_r4)
	_chk("P.13 an already-completed trade reaches DONE via AlreadyTraded, "
			+ "never pausing on a yes/no or a party choice at all "
			+ "(diagnostic if not: '%s')" % vm_r4.diagnostic,
			vm_r4.pause_reason == ScriptVM.Pause.DONE)


## --- Q. [M27G G5] the `native` opcode ---
##
## ⚠️ Every assertion here reads the VM from OUTSIDE, the same discipline the
## rest of this suite uses. That is the whole reason `native` was built as a
## PAUSE rather than as a coroutine: a suspended handler leaves `pause_reason`,
## `pending_native` and `describe()["native"]` all readable, so a test can
## freeze mid-handler and assert. An `await`-based command could not be
## inspected at all.
func _test_m27g_g5_native() -> void:
	var flags := FlagStore.new()
	var vm := ScriptVM.new(_src({
		"A": [_op("native", ["Sparkle", "3"]), _op("setflag", ["FLAG_AFTER"]), _op("end")],
	}), flags)
	vm.start("A")
	_run(vm)
	_chk("Q.01 native pauses on WAIT_NATIVE rather than running on",
			vm.pause_reason == ScriptVM.Pause.WAIT_NATIVE)
	_chk("Q.02 and names the handler it is waiting on",
			vm.pending_native == "Sparkle")
	_chk("Q.03 extra arguments are carried, the handler name is not among them",
			vm.pending_native_args.size() == 1 and str(vm.pending_native_args[0]) == "3")
	_chk("Q.04 describe() reports the handler, so an overlay can name it",
			str(vm.describe().get("native", "")) == "Sparkle")
	# ⚠️ THE GUARD THAT MATTERS. WAIT_NATIVE carries a result, so a plain
	# resume() must refuse it — exactly as it refuses WAIT_BATTLE/WAIT_NAMING/
	# WAIT_PARTY_CHOICE. Without this a handler's answer is silently dropped and
	# the script reads as having just carried on.
	vm.resume()
	_chk("Q.05 a plain resume() does NOT clear WAIT_NATIVE",
			vm.pause_reason == ScriptVM.Pause.WAIT_NATIVE)
	_chk("Q.06 and the script has not advanced past the native",
			not flags.flag_get("FLAG_AFTER"))
	vm.resume_after_native(null)
	_chk("Q.07 resume_after_native releases it", vm.pause_reason == ScriptVM.Pause.NONE)
	_run(vm)
	_chk("Q.08 and the script carries on from the next opcode",
			flags.flag_get("FLAG_AFTER"))
	_chk("Q.09 the pending handler is cleared once resumed", vm.pending_native == "")

	# A handler that ANSWERS: the value lands in VAR_RESULT and the script
	# branches on it exactly as it would after a `special`.
	var flags2 := FlagStore.new()
	var vm2 := ScriptVM.new(_src({
		"A": [_op("native", ["AskSomething"]),
				_op("goto_if_eq", ["VAR_RESULT", "1", "YES"]), _op("end")],
		"YES": [_op("setflag", ["FLAG_SAID_YES"]), _op("end")],
	}), flags2)
	vm2.start("A")
	_run(vm2)
	vm2.resume_after_native(1)
	_run(vm2)
	_chk("Q.10 a handler's return value reaches VAR_RESULT and branches",
			flags2.flag_get("FLAG_SAID_YES"))

	# ⚠️ null must LEAVE VAR_RESULT ALONE rather than zeroing it. A presentation
	# beat sitting between a check and the `goto_if_eq VAR_RESULT` that consumes
	# it would otherwise silently break that branch.
	var flags3 := FlagStore.new()
	flags3.var_set("VAR_RESULT", 7)
	var vm3 := ScriptVM.new(_src({"A": [_op("native", ["Beat"]), _op("end")]}), flags3)
	vm3.start("A")
	_run(vm3)
	vm3.resume_after_native(null)
	_chk("Q.11 a handler with nothing to say does not clobber VAR_RESULT",
			flags3.var_get("VAR_RESULT") == 7)

	# A missing name is a data problem worth naming, not a silent skip.
	var vm4 := ScriptVM.new(_src({"A": [_op("native", []), _op("end")]}), FlagStore.new())
	vm4.start("A")
	_run(vm4)
	_chk("Q.12 native with no handler name halts rather than continuing",
			vm4.pause_reason == ScriptVM.Pause.UNKNOWN_OP)
	_chk("Q.13 and says what was wrong", vm4.diagnostic.contains("handler name"))

	# `start()` must clear a previous script's pending handler, or a fresh VM
	# reports itself waiting on something nobody asked for.
	var vm5 := ScriptVM.new(_src({
		"A": [_op("native", ["Stale"]), _op("end")],
		"B": [_op("end")],
	}), FlagStore.new())
	vm5.start("A")
	_run(vm5)
	vm5.start("B")
	_chk("Q.14 starting a new script clears the previous pending handler",
			vm5.pending_native == "" and vm5.pending_native_args.is_empty())

	# --- the registry ---
	#
	# ⚠️ A LOCAL INSTANCE, not a static table. `NativeEventRegistry` holds
	# Callables, and a static Dictionary of lambdas outlives the script that
	# made them — Godot then aborts at process exit with heap corruption
	# (SIGABRT/134). That was the first cut and it took down four suites the
	# moment a real overworld started registering handlers; the registry is now
	# owned per-`ScriptDriver`, which is the correct lifetime anyway. This
	# section builds its own for the same reason production does.
	var reg := NativeEventRegistry.new()
	FieldNativeEvents.register_all(reg)
	_chk("Q.15 the project's own built-in handlers register",
			reg.has("FadeToBlack") and reg.has("FadeFromBlack") and reg.has("Wait"))
	_chk("Q.16 names() lists them, for the overlay", reg.names().size() >= 3)
	_chk("Q.17 an unregistered handler is reported absent, not defaulted",
			not reg.has("NoSuchHandler_G5Test"))
	_chk("Q.18 and get_handler hands back an invalid Callable to halt on",
			not reg.get_handler("NoSuchHandler_G5Test").is_valid())
	var hits := [0]
	reg.register("G5TestHandler", func(_d, _a) -> Variant:
		hits[0] += 1
		return null)
	_chk("Q.19 a registered handler is found", reg.has("G5TestHandler"))
	# ⚠️ FIRST REGISTRATION WINS. Two under one name is a real conflict: the
	# second would win invisibly and the first would look implemented.
	var replaced := reg.register("G5TestHandler", func(_d, _a) -> Variant:
		hits[0] += 100
		return null)
	_chk("Q.20 a duplicate registration is refused rather than clobbering", not replaced)
	reg.get_handler("G5TestHandler").call(null, [])
	_chk("Q.21 and the FIRST handler is the one still registered", hits[0] == 1)
	# Each driver gets its own — a second field session cannot inherit a stale
	# handler from the last one.
	_chk("Q.22 a fresh registry starts empty",
			not NativeEventRegistry.new().has("FadeToBlack"))


## --- R. [M27G G6] the EventScript authoring front-end ---
##
## ⚠️ **R.01 IS THE HIGHEST-VALUE ASSERTION IN THIS FILE.** The whole premise of
## the front-end is that `ScriptVM` cannot tell an authored script from an
## imported one. That is only true if the builder emits BYTE-IDENTICAL structure
## to the compiler — same op names, same arg count, same arg TYPES (strings
## throughout, even the numbers). Comparing against a real entry from the real
## `map_scripts.json`, rather than a fixture, is what makes it a proof rather
## than a restatement.
func _test_m27g_g6_event_script() -> void:
	# `PalletTown_EventScript_FatMan` is `msgbox X, MSGBOX_NPC` + `end`, the
	# single most common script shape in the corpus and the one the compiler
	# expands through STD_EXPANSIONS.
	var corpus := {}
	if FileAccess.file_exists("res://data/map_scripts.json"):
		var parsed = JSON.parse_string(FileAccess.open(
				"res://data/map_scripts.json", FileAccess.READ).get_as_text())
		if parsed is Dictionary:
			corpus = parsed
	var real: Array = corpus.get("PalletTown_EventScript_FatMan", [])
	var corpus_texts := {}
	if FileAccess.file_exists("res://data/map_texts.json"):
		var pt = JSON.parse_string(FileAccess.open(
				"res://data/map_texts.json", FileAccess.READ).get_as_text())
		if pt is Dictionary:
			corpus_texts = pt
	var built: Array = EventScript.new() \
			.msgbox_npc("PalletTown_Text_CanStoreItemsAndMonsInPC") \
			.end()
	if real.is_empty():
		_gated += 2
	else:
		_chk("R.01 the builder reproduces a REAL compiled script exactly",
				JSON.stringify(built) == JSON.stringify(real))
		# Stated separately so a failure says WHICH half diverged.
		var same_ops := built.size() == real.size()
		if same_ops:
			for i in range(built.size()):
				if str(built[i]["op"]) != str(real[i]["op"]):
					same_ops = false
					break
		_chk("R.02 op sequence matches the compiler's msgbox expansion", same_ops)

	# ⚠️ EVERY ARG IS A STRING, matching the compiler. An int here would run
	# correctly today (`_resolve_number` calls str() on everything) and diverge
	# the moment anything compares the two forms — exactly the kind of
	# near-miss that reads as working.
	var typed: Array = EventScript.new().set_var("VAR_X", 3).end()
	_chk("R.03 numeric arguments are emitted as STRINGS, as the compiler does",
			typed[0]["args"][0] is String and typed[0]["args"][1] is String
			and str(typed[0]["args"][1]) == "3")

	# --- the mechanical guard §7 requires ---
	#
	# ⚠️ Drives a one-op VM for EVERY name in EventScript.OPS and asserts none
	# halts as UNKNOWN_OP. This makes it impossible to add a builder method for
	# an opcode the VM does not implement — which would compile cleanly and then
	# halt mid-conversation at runtime, the exact failure the front-end exists
	# to remove. A pause (WAIT_MESSAGE and friends) is fine; only UNKNOWN_OP is
	# a gap.
	# ⚠️ **THE PROBE TESTS FOR A MISSING `match` CASE, NOT FOR VALID ARGUMENTS**,
	# and the first cut conflated the two. Driven with empty args, `warp`,
	# `special`, `specialvar`, `trainerbattle_single`, `trainerbattle_no_intro`
	# and `native` all halt as UNKNOWN_OP — correctly, because each validates
	# its own arity and says so. That is a well-formed refusal, not an
	# unimplemented opcode. The distinction is in the DIAGNOSTIC: the generic
	# fallthrough at the bottom of `step()` is the only path that says "outside
	# Stage 1's set", and that is the one this guard is looking for.
	var unimplemented := PackedStringArray()
	for op_name in EventScript.OPS:
		var probe := ScriptVM.new(_src({"A": [_op(str(op_name), [])]}), FlagStore.new())
		probe.start("A")
		probe.step()
		if probe.pause_reason == ScriptVM.Pause.UNKNOWN_OP \
				and probe.diagnostic.contains("outside"):
			unimplemented.append(str(op_name))
	_chk("R.04 every op the builder can emit is implemented by the VM (%s)"
			% (", ".join(unimplemented) if unimplemented.size() > 0 else "all ok"),
			unimplemented.is_empty())

	# ⚠️ `step_end` is EXCLUDED, and it is not an oversight: it is the
	# TERMINATOR, special-cased by `MovementRunner._begin` rather than living in
	# the action table, so `action("step_end")` is legitimately empty. R.07
	# asserts `done()` emits it; this loop covers everything that has to resolve
	# to a real animation.
	var bad_moves := PackedStringArray()
	for action in Move.ACTIONS:
		if str(action) == "step_end":
			continue
		if MovementRunner.action(str(action)).is_empty():
			bad_moves.append(str(action))
	_chk("R.05 every action the Move builder can emit is known to MovementRunner (%s)"
			% (", ".join(bad_moves) if bad_moves.size() > 0 else "all ok"),
			bad_moves.is_empty())

	# --- movement builder ---
	var walk: Array = Move.new().walk_down(2).face_left().done()
	_chk("R.06 a repeat count emits that many actions, not one with an argument",
			walk.size() == 4 and str(walk[0]["op"]) == "walk_down"
			and str(walk[1]["op"]) == "walk_down")
	_chk("R.07 done() terminates with step_end, which the runner needs",
			str(walk[walk.size() - 1]["op"]) == "step_end")

	# --- the registry and its collision rule ---
	EventRegistry.clear()
	_chk("R.08 a fresh registry holds nothing", EventRegistry.labels().is_empty())
	EventRegistry.register("Authored_A", EventScript.new().set_flag("F").end())
	_chk("R.09 an authored script registers", EventRegistry.has("Authored_A"))
	_chk("R.10 a duplicate registration is refused, first wins",
			not EventRegistry.register("Authored_A",
					EventScript.new().set_flag("G").end()))
	# ⚠️ THE COLLISION RULE. Silently shadowing an imported label would replace
	# content somewhere across 17,137 labels nobody reads end to end. The
	# imported script wins and the clash is reported.
	var table := {"Imported_B": [{"op": "end", "args": []}]}
	EventRegistry.register("Imported_B", EventScript.new().set_flag("WRONG").end())
	var merged := EventRegistry.merge_into(table)
	_chk("R.11 an authored label that does NOT collide is merged in",
			table.has("Authored_A") and merged == 1)
	_chk("R.12 one that DOES collide is refused, and the imported op list stands",
			table["Imported_B"].size() == 1
			and str(table["Imported_B"][0]["op"]) == "end")
	_chk("R.13 and the collision is reported rather than swallowed",
			"Imported_B" in EventRegistry.rejected())

	# --- an authored script actually runs, through the unmodified VM ---
	EventRegistry.clear()
	AuthoredEvents.register_all()
	var ops := {}
	EventRegistry.merge_into(ops)
	# ⚠️ Authored dialogue is NOT registered — it lives in the one corpus with
	# every imported line, so the real `map_texts.json` is what must resolve it.
	var texts: Dictionary = corpus_texts
	_chk("R.14 the project's own authored content registers",
			ops.has(PalletTownEvents.LABEL_SIGN_POST))
	var flags := FlagStore.new()
	var vm := ScriptVM.new(_src(ops, texts), flags)
	vm.start(PalletTownEvents.LABEL_SIGN_POST)
	var seen := _drive(vm)
	_chk("R.15 an authored script runs on the unmodified VM",
			seen.size() > 0 and not vm.pause_reason == ScriptVM.Pause.UNRESOLVED)
	_chk("R.16 its native beat pauses exactly as an imported one would",
			vm.pause_reason == ScriptVM.Pause.WAIT_NATIVE
			and vm.pending_native == "Wait")
	vm.resume_after_native(null)
	_drive(vm)
	_chk("R.17 and it completes, setting the flag and checkpoint it declares",
			flags.flag_get("FLAG_AUTHORED_SEA_BREEZE_READ")
			and flags.var_get(PalletTownEvents.VAR_SCENE) == 1)
	# The gate branches on the second read — the whole point of the flag.
	var vm2 := ScriptVM.new(_src(ops, texts), flags)
	vm2.start(PalletTownEvents.LABEL_SIGN_POST)
	_drive(vm2)
	_chk("R.18 a second read takes the gated branch to the short label",
			vm2.script_label == PalletTownEvents.LABEL_SIGN_POST_AGAIN)
	# ⚠️ THE GUARD THAT REPLACED THE TEXT REGISTRY. An authored script names a
	# label in a separately-compiled corpus, which is the one thing the GDScript
	# front-end cannot type-check — so it is checked at boot instead.
	_chk("R.19 authored dialogue resolves out of the real compiled corpus",
			texts.has(PalletTownEvents.TEXT_SEA_BREEZE)
			and texts.has(PalletTownEvents.TEXT_SEA_BREEZE_SHORT))
	_chk("R.20 and verify_text reports nothing missing for shipped content",
			EventRegistry.verify_text(texts).is_empty())
	_chk("R.21 while a script naming an absent label IS reported",
			EventRegistry.verify_text({}).size() > 0)
	EventRegistry.clear()


## --- S. [M27G G8/G9] special routing, and the two persistence gaps ---
func _test_m27g_g8_g9() -> void:
	# --- G8: an unhandled special routes to a registered handler ---
	#
	# ⚠️ THE REGISTRY IS INJECTED INTO THE VM, not consulted by the driver, and
	# S.02 is why: without it the VM could no longer tell an unimplemented
	# special from a handled one, and only the driver would know. That would
	# quietly break the property this engine rests on — `step()` alone says what
	# a script did and why it stopped. `m27f_stage4_test` B.04/B.05 assert it
	# from a bare VM and are right to.
	var reg := NativeEventRegistry.new()
	reg.register("SomeAsyncSpecial", func(_d, _a) -> Variant: return 1)
	var vm := ScriptVM.new(_src({
		"A": [_op("special", ["SomeAsyncSpecial"]), _op("setflag", ["FLAG_AFTER"]),
				_op("end")],
	}), FlagStore.new())
	vm.natives = reg
	vm.start("A")
	_run(vm)
	_chk("S.01 an unhandled special with a registered handler waits on it",
			vm.pause_reason == ScriptVM.Pause.WAIT_NATIVE
			and vm.pending_native == "SomeAsyncSpecial")
	var vm2 := ScriptVM.new(_src({
		"A": [_op("special", ["NoHandlerAnywhere"]), _op("end")],
	}), FlagStore.new())
	vm2.natives = reg
	vm2.start("A")
	_run(vm2)
	_chk("S.02 one with NO handler still halts, from the VM alone",
			vm2.pause_reason == ScriptVM.Pause.UNKNOWN_OP
			and vm2.diagnostic.contains("NoHandlerAnywhere"))
	# ⚠️ A `specialvar` naming a destination other than VAR_RESULT is
	# deliberately NOT routed: `resume_after_native` answers into VAR_RESULT, so
	# serving it would write the wrong slot silently — worse than halting.
	var vm3 := ScriptVM.new(_src({
		"A": [_op("specialvar", ["VAR_TEMP_3", "SomeAsyncSpecial"]), _op("end")],
	}), FlagStore.new())
	vm3.natives = reg
	vm3.start("A")
	_run(vm3)
	_chk("S.03 a specialvar answering into another var halts rather than mis-writing",
			vm3.pause_reason == ScriptVM.Pause.UNKNOWN_OP)

	# --- G9a: the subject survives losing its node ---
	var npc := NPC.new()
	npc.local_id = "LOCALID_TEST_SUBJECT"
	var vm4 := ScriptVM.new(_src({"A": [_op("end")]}), FlagStore.new())
	vm4.start("A", npc)
	_chk("S.04 the subject's local_id is captured, not just the node",
			vm4.subject_local_id == "LOCALID_TEST_SUBJECT")
	npc.free()
	_chk("S.05 and it outlives the node a warp would free",
			not is_instance_valid(vm4.subject)
			and vm4.subject_local_id == "LOCALID_TEST_SUBJECT")

	# --- G9b: script-driven object-event changes persist ---
	ObjectEventState.clear()
	_chk("S.06 nothing is recorded until a script changes something",
			not ObjectEventState.has_any())
	ObjectEventState.record("PalletTown_Frlg", "LOCALID_OAK", "cell", Vector2i(4, 7))
	ObjectEventState.record("PalletTown_Frlg", "LOCALID_OAK", "facing", 2)
	var ov := ObjectEventState.overrides_for("PalletTown_Frlg", "LOCALID_OAK")
	_chk("S.07 both fields land under one map+local_id key",
			ov.get("cell") == Vector2i(4, 7) and int(ov.get("facing", -1)) == 2)
	_chk("S.08 and a different map with the same local_id is untouched",
			ObjectEventState.overrides_for("PewterCity_Frlg", "LOCALID_OAK").is_empty())
	# ⚠️ Vector2i does not survive JSON — the same reason SaveManager stores the
	# player's cell as two ints. The round trip is where that would bite.
	var payload := ObjectEventState.to_save()
	var json_round = JSON.parse_string(JSON.stringify(payload))
	ObjectEventState.clear()
	ObjectEventState.from_save(json_round if json_round is Dictionary else {})
	var back := ObjectEventState.overrides_for("PalletTown_Frlg", "LOCALID_OAK")
	_chk("S.09 an override survives a real JSON round trip, cell included",
			back.get("cell") == Vector2i(4, 7) and int(back.get("facing", -1)) == 2)
	# Untrusted input, like every other loader here.
	ObjectEventState.clear()
	ObjectEventState.from_save({"PalletTown_Frlg|LOCALID_OAK": "not a dictionary"})
	_chk("S.10 a hand-edited save fails closed rather than half-loading",
			not ObjectEventState.has_any())
	ObjectEventState.clear()

	# --- [M27G] multichoicegrid and fadescreen ---
	var reg2 := NativeEventRegistry.new()
	FieldNativeEvents.register_all(reg2)
	var vmg := ScriptVM.new(_src({
		"A": [_op("multichoicegrid", ["7", "1", "MULTI_STATUS_INFO", "3", "FALSE"]),
				_op("end")],
	}), FlagStore.new())
	vmg.natives = reg2
	vmg.start("A")
	_run(vmg)
	_chk("S.11 multichoicegrid waits on the Multichoice handler",
			vmg.pause_reason == ScriptVM.Pause.WAIT_NATIVE
			and vmg.pending_native == "Multichoice")
	_chk("S.12 carrying the list, row width and B-press flag",
			vmg.pending_native_args.size() == 3
			and str(vmg.pending_native_args[0]) == "MULTI_STATUS_INFO"
			and str(vmg.pending_native_args[1]) == "3")
	# ⚠️ An untranscribed list halts from the VM ALONE and names itself, rather
	# than opening a menu with nothing in it.
	var vmg2 := ScriptVM.new(_src({
		"A": [_op("multichoicegrid", ["0", "0", "MULTI_SOME_HOENN_THING", "2", "FALSE"]),
				_op("end")],
	}), FlagStore.new())
	vmg2.natives = reg2
	vmg2.start("A")
	_run(vmg2)
	_chk("S.13 an untranscribed list halts and names itself",
			vmg2.pause_reason == ScriptVM.Pause.UNKNOWN_OP
			and vmg2.diagnostic.contains("MULTI_SOME_HOENN_THING"))
	# ⚠️ THE ORDER IS FRLG'S, NOT THE REFERENCE TABLE'S — see MultichoiceLists.
	# The reference ships ONE MULTI_STATUS_INFO (PSN, PAR, SLP, ...) and the
	# FRLG blackboard's own `case 0 -> ReadSleep` disagrees with it, so upstream
	# picking PSN reads the sleep article. Kanto-only, so FRLG's order wins.
	var entries := MultichoiceLists.entries("MULTI_STATUS_INFO")
	_chk("S.14 MULTI_STATUS_INFO is in FRLG's order, matching its one caller",
			entries.size() == 6 and entries[0] == "SLP" and entries[1] == "PSN"
			and entries[5] == "EXIT")
	_chk("S.15 B answers source's own MULTI_B_PRESSED sentinel",
			MultichoiceGrid.B_PRESSED == 127)

	# fadescreen is a real fade now, and reads its DIRECTION.
	var vmf := ScriptVM.new(_src({
		"A": [_op("fadescreen", ["FADE_TO_BLACK"]), _op("end")],
	}), FlagStore.new())
	vmf.natives = reg2
	vmf.start("A")
	_run(vmf)
	_chk("S.16 fadescreen is no longer a no-op",
			vmf.pause_reason == ScriptVM.Pause.WAIT_NATIVE
			and vmf.pending_native == "FadeScreen"
			and str(vmf.pending_native_args[0]) == "FADE_TO_BLACK")
	# ⚠️ Without a registry it must fall back to the NO-OP, not halt: 128 corpus
	# uses would otherwise stop every script that fades.
	var vmf2 := ScriptVM.new(_src({
		"A": [_op("fadescreen", ["FADE_TO_BLACK"]), _op("setflag", ["F"]), _op("end")],
	}), FlagStore.new())
	vmf2.start("A")
	_run(vmf2)
	_chk("S.17 with no registry it degrades to the old no-op rather than halting",
			vmf2.pause_reason == ScriptVM.Pause.DONE)
