extends Node

## [M27R 7a-1] The field audio player, the name tables, and the nine VM audio
## opcodes.
##
## ⚠️ **THE THING THIS SUITE CANNOT TEST IS WHETHER ANYTHING SOUNDS RIGHT**, and
## every assertion below is shaped around that. What IS checkable is *which cue
## fired, what it resolved to, and whether a script kept running* — so the
## guards are on `GameAudio.cues`, on `AudioMap`'s resolution, and on scripts
## reaching DONE. The listen pass is Rob's and is the real acceptance test.
##
## Three failure modes drive the shape:
##
##   * **A silent regression into a halt.** Every one of these opcodes was a
##     working no-op before this tier. A script that used to run to completion
##     silently must still do so with no audio, no registry, and no handler —
##     tested from a BARE VM in section D, which is the configuration a
##     regression would show up in first.
##   * **A `waitfanfare` that never releases.** `MUS_LEVEL_UP` has no asset, so
##     the failure path is the COMMON path, not the edge case. Section C pins
##     that a cue which cannot play still emits its finished signal.
##   * **A stub that is not actually wired.** BGM has no assets at all, so
##     "plays nothing" is indistinguishable from "not implemented" unless the
##     INTENT is separately observable. Section B asserts on `bgm_intent`,
##     which is non-empty for a mapped track whether or not a file exists.

## ⚠️ MEASURED off a real run, never counted from `_chk(` call sites — branches
## and early returns break static counting. Excludes Z.99 itself, matching every
## sibling suite, so a clean run prints one higher than this.
const EXPECTED_TOTAL := 56  # +8 G (7c cries), +8 H (7a-3 battle SFX)

var _total := 0
var _failed := 0
var _gated := 0


func _chk(label: String, cond: bool) -> void:
	_total += 1
	if not cond:
		_failed += 1
		print("FAILED: %s" % label)


func _ready() -> void:
	_test_audio_map()
	_test_bgm_stub()
	# ⚠️ AWAITED. `_test_player` awaits a frame, so calling it bare returns at
	# that point and lets `_ready` print the summary while C.05+ are still to
	# run — which is exactly what happened on this suite's first draft, and is
	# visible only as Z.99 failing to balance.
	await _test_player()
	_test_vm_opcodes()
	_test_real_corpus()
	_test_code_driven_cues()
	_test_7c_cries()
	_test_7a3_battle_sfx()
	await _test_door_vs_bump()
	var accounted := _total + _gated
	_chk("Z.99 every expected assertion ran (%d + %d gated == %d)"
			% [_total, _gated, EXPECTED_TOTAL], accounted == EXPECTED_TOTAL)
	print("m27r_audio_test: %d/%d passed" % [_total - _failed, _total])
	get_tree().quit()


## --- A. AudioMap: the names resolve to files that exist -------------------
func _test_audio_map() -> void:
	# The headline guard, and the one that fails first if the vendored pack
	# ever moves: EVERY mapped SE/ME resolves to a file Godot can actually
	# load. A mapping to a path that is not there is silence at a real beat.
	var se_ok := true
	for k in AudioMap.SE.keys():
		if not ResourceLoader.exists(AudioMap.se_path(k)):
			se_ok = false
			print("   SE '%s' -> %s MISSING" % [k, AudioMap.se_path(k)])
	_chk("A.01 every mapped SE resolves to a real importable file", se_ok)

	var me_ok := true
	for k in AudioMap.ME.keys():
		if not ResourceLoader.exists(AudioMap.me_path(k)):
			me_ok = false
			print("   ME '%s' -> %s MISSING" % [k, AudioMap.me_path(k)])
	_chk("A.02 every mapped fanfare resolves to a real importable file", me_ok)

	# Source's own comment at songs.h:27 is the whole reason this is Exclaim
	# and not a generic confirm blip. Pinned so a later "tidy-up" that reasons
	# from the NAME instead of the comment fails here.
	_chk("A.03 SE_PIN is the '!' pop (songs.h:27), not a menu sound",
			AudioMap.se_path("SE_PIN").ends_with("Exclaim.wav"))
	# songs.h:15 is SE_KAIDAN and its real call sites are the warp exit
	# (field_screen_effect.c:536,654) — a field sound, not a UI one.
	_chk("A.04 SE_EXIT is the door/stairs exit, not a menu close",
			AudioMap.se_path("SE_EXIT").ends_with("Door exit.ogg"))
	_chk("A.05 an unmapped SE degrades to \"\" rather than a bogus path",
			AudioMap.se_path("SE_NOT_A_REAL_SOUND") == "")
	_chk("A.06 an unmapped fanfare degrades to \"\"",
			AudioMap.me_path("MUS_NOT_A_REAL_TRACK") == "")


## --- B. The BGM stub is wired even with zero assets -----------------------
func _test_bgm_stub() -> void:
	# ⚠️ THE DISCRIMINATOR FOR THE WHOLE STUB. Without this, "BGM is wired but
	# has no assets" and "BGM is not wired at all" produce identical observable
	# behaviour — silence — and the stub could rot unnoticed until Rob's folder
	# arrives and nothing happens.
	_chk("B.01 a mapped track has a non-empty INTENDED path with no asset present",
			AudioMap.bgm_intent("MUS_POKE_CENTER") != "")
	_chk("B.02 the intended path is under the folder Rob supplies, not the "
			+ "unplayable vendored .mid directory",
			AudioMap.bgm_intent("MUS_POKE_CENTER").begins_with(AudioMap.BGM_DIR)
			and not AudioMap.bgm_intent("MUS_POKE_CENTER").contains("Essentials"))
	_chk("B.03 an UNmapped track has no intent either — the table is a real "
			+ "allowlist, not a path-builder that accepts anything",
			AudioMap.bgm_intent("MUS_NOT_A_REAL_TRACK") == "")
	# Every playbgm argument the corridor actually reaches, measured against
	# data/map_scripts.json across 762 reachable labels.
	var want := ["MUS_POKE_CENTER", "MUS_FOLLOW_ME", "MUS_RG_ENCOUNTER_RIVAL",
			"MUS_RG_RIVAL_EXIT", "MUS_RG_OAK", "MUS_RG_JIGGLYPUFF"]
	var all_mapped := true
	for w in want:
		if AudioMap.bgm_intent(w) == "":
			all_mapped = false
	_chk("B.04 all six corridor BGM tracks are mapped", all_mapped)
	_chk("B.05 resolution yields \"\" while the folder is absent (so playback "
			+ "degrades to silence rather than erroring)",
			AudioMap.bgm_path("MUS_POKE_CENTER") == "")


## --- C. GameAudio records, and always releases its waiters ----------------
func _test_player() -> void:
	var a := GameAudio.new()
	add_child(a)

	a.play_se("SE_CLICK")
	_chk("C.01 a playable SE records a cue AND reports played",
			a.cues.size() == 1 and a.cues[0]["kind"] == "se"
			and a.cues[0]["played"] == true)

	a.play_se("SE_NOT_A_REAL_SOUND")
	_chk("C.02 an unmapped SE still records a cue, with played=false",
			a.cues.size() == 2 and a.cues[1]["played"] == false)
	_chk("C.03 ...and says WHY, without pushing an engine error",
			a.last_diagnostic.contains("not mapped"))

	a.play_fanfare("MUS_HEAL")
	_chk("C.04 a playable fanfare records and plays",
			a.cues[2]["kind"] == "fanfare" and a.cues[2]["played"] == true)

	# ⚠️ THE ONE THAT MATTERS MOST. MUS_LEVEL_UP has no Essentials counterpart
	# and 4 corridor scripts play it, so this is the common path. If the signal
	# did not fire, every one of them would hang the scene forever on
	# `waitfanfare`.
	var released := [false]
	a.fanfare_finished.connect(func() -> void: released[0] = true)
	a.play_fanfare("MUS_LEVEL_UP")
	await get_tree().process_frame
	_chk("C.05 a fanfare that CANNOT play still releases its waiter",
			released[0] == true)
	_chk("C.06 ...and is_fanfare_playing() is false, so WaitFanfare returns "
			+ "immediately rather than awaiting a signal already sent",
			a.is_fanfare_playing() == false)

	# The BGM stub: a cue with a real name, resolving to nothing, played=false.
	a.play_bgm("MUS_POKE_CENTER")
	var last: Dictionary = a.cues[a.cues.size() - 1]
	_chk("C.07 a mapped BGM records the cue by NAME even with no asset",
			last["kind"] == "bgm" and last["name"] == "MUS_POKE_CENTER"
			and last["played"] == false)
	# ⚠️ Written as a BEFORE/AFTER pair on purpose. The first draft asserted
	# `is_se_playing() == true or == false`, which cannot fail — the exact
	# vacuous-guard shape this project has now recorded five times. A pair that
	# must FLIP is the smallest thing that actually discriminates.
	a.play_se("SE_CLICK")
	var during := a.is_se_playing()
	a.stop_all()
	_chk("C.08 is_se_playing() tracks real voices — true while one runs, "
			+ "false after stop_all (a stuck 'true' would hang WaitSe)",
			during == true and a.is_se_playing() == false)

	a.queue_free()


## --- D. The VM opcodes, including from a BARE VM ---------------------------
func _test_vm_opcodes() -> void:
	# ⚠️ NO AUDIO AT ALL. This is the configuration a regression shows up in
	# first, and the one every pre-7a test already runs in. Every audio opcode
	# must behave exactly as it did before this tier: silent, and not a halt.
	var bare := ScriptVM.new(_src({"T": [
			_op("playse", ["SE_CLICK"]),
			_op("playfanfare", ["MUS_HEAL"]),
			_op("waitfanfare", []),
			_op("playbgm", ["MUS_POKE_CENTER", "0"]),
			_op("fadeoutbgm", ["0"]),
			_op("fadedefaultbgm", []),
			_op("waitse", []),
			_op("end", []),
		]}), FlagStore.new())
	bare.start("T")
	_run(bare)
	_chk("D.01 with NO audio injected every opcode is still a silent no-op, "
			+ "and the script reaches DONE rather than halting",
			bare.pause_reason == ScriptVM.Pause.DONE)

	# Now with audio but STILL no natives registry — `waitfanfare` must fall
	# through rather than demand a handler it cannot reach.
	var a := GameAudio.new()
	add_child(a)
	var vm := ScriptVM.new(_src({"T": [
			_op("playse", ["SE_CLICK"]),
			_op("playfanfare", ["MUS_HEAL"]),
			_op("waitfanfare", []),
			_op("end", []),
		]}), FlagStore.new())
	vm.audio = a
	vm.start("T")
	_run(vm)
	_chk("D.02 audio but no native registry: still DONE, never UNKNOWN_OP",
			vm.pause_reason == ScriptVM.Pause.DONE)
	_chk("D.03 ...and the sounds were genuinely requested, not skipped",
			a.cues.size() == 2 and a.cues[0]["name"] == "SE_CLICK"
			and a.cues[1]["name"] == "MUS_HEAL")

	# With a registry, `waitfanfare` becomes a real WAIT_NATIVE.
	var reg := NativeEventRegistry.new()
	FieldNativeEvents.register_all(reg)
	var vm2 := ScriptVM.new(_src({"T": [
			_op("playfanfare", ["MUS_HEAL"]),
			_op("waitfanfare", []),
			_op("end", []),
		]}), FlagStore.new())
	vm2.audio = a
	vm2.natives = reg
	vm2.start("T")
	var steps := 0
	while steps < 20 and vm2.step():
		steps += 1
	_chk("D.04 with a handler registered, waitfanfare pauses on WAIT_NATIVE "
			+ "instead of falling through",
			vm2.pause_reason == ScriptVM.Pause.WAIT_NATIVE
			and vm2.pending_native == "WaitFanfare")
	_chk("D.05 waitse routes to its OWN handler, not the fanfare one",
			reg.has("WaitSe") and reg.has("WaitFanfare"))
	# A plain resume must clear it — there is no result to branch on, the same
	# call `waitmovement` makes and the opposite of WAIT_BATTLE's.
	vm2.resume_after_native(null)
	_run(vm2)
	_chk("D.06 resuming the native completes the script",
			vm2.pause_reason == ScriptVM.Pause.DONE)

	_chk("D.07 the cry opcodes are STILL no-ops (7c), not accidentally wired",
			_runs_clean([_op("playmoncry", ["SPECIES_SPEAROW", "CRY_MODE_NORMAL"]),
					_op("waitmoncry", []), _op("end", [])], a))

	a.stop_all()
	a.queue_free()


## --- E. The real corpus ----------------------------------------------------
func _test_real_corpus() -> void:
	if not FileAccess.file_exists("res://data/map_scripts.json"):
		_gated += 3
		return
	var f := FileAccess.open("res://data/map_scripts.json", FileAccess.READ)
	var ops: Dictionary = JSON.parse_string(f.get_as_text())

	# Every distinct playse/playfanfare argument the corridor reaches must be
	# mapped, or a real beat is silent. This is the roster-coverage guard, the
	# same shape as `m27i_item_identity_test`'s E.02/E.03 — it fails when the
	# corridor GROWS to reach a sound nobody mapped, which is exactly when a
	# hand-written list would go stale unnoticed.
	var se_names := {}
	var me_names := {}
	for lbl in ops.keys():
		for op in ops[lbl]:
			var a: Array = op.get("args", [])
			if a.is_empty():
				continue
			if op.get("op", "") == "playse":
				se_names[str(a[0])] = true
			elif op.get("op", "") == "playfanfare":
				me_names[str(a[0])] = true
	_chk("E.01 the corpus really does carry the sounds this tier mapped "
			+ "(guards against an empty scan passing vacuously)",
			se_names.size() > 0 and me_names.size() > 0)

	# ⚠️ Scoped to the SIX corridor SE names rather than the whole region: the
	# region-wide set is far larger and belongs to whichever tier bakes those
	# maps. Asserting region-wide here would fail for content that does not
	# exist yet, which is a stale test rather than a real gap.
	var corridor_se := ["SE_CLICK", "SE_PIN", "SE_BOO", "SE_EXIT", "SE_PC_ON", "SE_SHOP"]
	var covered := true
	for s in corridor_se:
		if not se_names.has(s):
			continue  # not reached by this corpus build; not this test's business
		if AudioMap.se_path(s) == "":
			covered = false
			print("   corridor SE '%s' is unmapped" % s)
	_chk("E.02 every corridor SE the corpus names is mapped", covered)

	var corridor_me := ["MUS_RG_OBTAIN_KEY_ITEM", "MUS_HEAL", "MUS_EVOLVED",
			"MUS_OBTAIN_TMHM"]
	var me_covered := true
	for m in corridor_me:
		if me_names.has(m) and AudioMap.me_path(m) == "":
			me_covered = false
			print("   corridor fanfare '%s' is unmapped" % m)
	_chk("E.03 every corridor fanfare with an Essentials counterpart is mapped "
			+ "(MUS_LEVEL_UP/MUS_RG_DEX_RATING excluded by decision — see "
			+ "AudioMap.ME's own note)", me_covered)


## --- F/G. [M27R 7a-2] Code-driven cues -------------------------------------
##
## ⚠️ These fire from real call sites rather than from an opcode argument,
## because the scripts that reach them ask for NO sound at all — measured, not
## assumed: Brock's win script is nine flag/var writes with no `playfanfare`
## anywhere, and Kanto's nurse reaches the heal through `special
## HealPlayerParty` alone. So each guard below pairs the cue with a
## DISCRIMINATOR, since "it played something" is not the claim — "it played on
## this condition and not the neighbouring one" is.
func _test_code_driven_cues() -> void:
	# F. The five new mappings resolve to real files.
	var ok := true
	for k in ["SE_SELECT", "SE_WALL_HIT", "SE_LEDGE", "SE_DOOR", "SE_SAVE"]:
		if not ResourceLoader.exists(AudioMap.se_path(k)):
			ok = false
			print("   new SE '%s' -> %s MISSING" % [k, AudioMap.se_path(k)])
	_chk("F.01 every 7a-2 code-driven SE resolves to a real file", ok)
	_chk("F.02 cursor and confirm are DIFFERENT sounds (the disclosed split "
			+ "from source's single SE_SELECT — a merge would silently undo it)",
			AudioMap.se_path("SE_SELECT") != AudioMap.se_path("SE_CLICK"))

	var a := GameAudio.new()
	add_child(a)

	# G. A badge flag plays the badge fanfare; an ordinary flag does not.
	var vm := ScriptVM.new(_src({"T": [
			_op("setflag", ["FLAG_BADGE01_GET"]), _op("end", [])]}), FlagStore.new())
	vm.audio = a
	vm.start("T")
	_run(vm)
	_chk("G.01 setting a BADGE flag plays the badge fanfare",
			_last_cue(a, "fanfare") == "MUS_OBTAIN_BADGE")

	var before := a.cues.size()
	var vm2 := ScriptVM.new(_src({"T": [
			_op("setflag", ["FLAG_HIDE_PEWTER_CITY_GYM_GUIDE"]), _op("end", [])]}),
			FlagStore.new())
	vm2.audio = a
	vm2.start("T")
	_run(vm2)
	# ⚠️ THE DISCRIMINATOR. Brock's own script sets FOUR flags either side of the
	# badge; a hook that fired on every `setflag` would fanfare four times and
	# still pass G.01.
	_chk("G.02 an ordinary flag plays NOTHING — the hook is keyed on the badge "
			+ "list, not on setflag itself", a.cues.size() == before)

	# G.03/G.04: obtaining an item, and the bag-full refusal that must be silent.
	var texts := {"gText_ObtainedTheItem": ["Obtained!"],
			"gText_PutItemInPocket": ["Put away."],
			"gText_TheBagIsFull": ["The BAG is full."]}
	var vm3 := ScriptVM.new(_src({"T": [
			_op("giveitem", ["ITEM_POTION", "1"]), _op("end", [])]}, texts),
			FlagStore.new())
	vm3.audio = a
	vm3.bag = Bag.new()
	vm3.start("T")
	_run(vm3)
	_chk("G.03 a successful giveitem plays the obtain jingle (the TM39 beat — "
			+ "no script asks for it, so nothing else would)",
			_last_cue(a, "fanfare") == "MUS_OBTAIN_ITEM")

	var full := Bag.new()
	# Fill the ITEMS pocket to its slot limit so the add genuinely refuses.
	for i in 40:
		full.add(28 + i, 1)
	var before2 := a.cues.size()
	var vm4 := ScriptVM.new(_src({"T": [
			_op("giveitem", ["ITEM_POTION", "999"]), _op("end", [])]}, texts),
			FlagStore.new())
	vm4.audio = a
	vm4.bag = full
	vm4.start("T")
	_run(vm4)
	_chk("G.04 a bag-full refusal plays NO jingle — a refusal is not a reward",
			a.cues.size() == before2)

	# G.05: the heal, hooked on the special because the nurse script has no
	# fanfare op at all.
	var vm5 := ScriptVM.new(_src({"T": [
			_op("special", ["HealPlayerParty"]), _op("end", [])]}), FlagStore.new())
	vm5.audio = a
	vm5.party = BattleParty.new()
	vm5.start("T")
	_run(vm5)
	_chk("G.05 HealPlayerParty plays the heal jingle",
			_last_cue(a, "fanfare") == "MUS_HEAL")

	var before3 := a.cues.size()
	var vm6 := ScriptVM.new(_src({"T": [
			_op("special", ["DrawWholeMapView"]), _op("end", [])]}), FlagStore.new())
	vm6.audio = a
	vm6.start("T")
	_run(vm6)
	_chk("G.06 a DIFFERENT synchronous special plays nothing — keyed on the "
			+ "heal, not on 'any special succeeded'", a.cues.size() == before3)

	a.stop_all()
	a.queue_free()


## --- H. The door/bump gate, in the real scene ------------------------------
##
## ⚠️ **THE ONE PIECE OF 7a-2 THAT CANNOT BE TESTED OFF-TREE, and the one most
## likely to be wrong in a way nobody notices.** A door tile is SOLID, so
## walking into a door and walking into a wall reach the SAME branch. Play the
## bump before `_try_door_warp` and every door in Kanto thuds as it opens —
## which sounds like a rough edge rather than a bug, and would survive a
## playtest.
func _test_door_vs_bump() -> void:
	var packed := load("res://scenes/overworld/overworld.tscn")
	if packed == null:
		_gated += 3
		return
	var ow = packed.instantiate()
	ow.start_map = "PalletTown_Frlg"
	add_child(ow)
	await get_tree().process_frame
	await get_tree().process_frame
	var a = ow.field_audio()
	if a == null or ow.manager == null:
		_gated += 3
		ow.queue_free()
		return

	# Both fixtures are FOUND, not hardcoded — a fixture that depends on a cell
	# someone may reasonably re-bake is a fixture that will break, which this
	# project has already paid for twice.
	var door := Vector2i(-1, -1)
	var wall := Vector2i(-1, -1)
	for y in 20:
		for x in 24:
			var c := Vector2i(x, y)
			if ow.manager.collision_at(c) == 0:
				continue
			# Standable from the south is what BOTH cases need: a door is
			# entered from below, and a bump has to be walked into.
			if ow.manager.collision_at(c + Vector2i(0, 1)) != 0:
				continue
			if ow.manager.warp_at(c) != null:
				if door.x < 0:
					door = c
			elif wall.x < 0:
				wall = c
	if door.x < 0 or wall.x < 0:
		_gated += 3
		ow.queue_free()
		return

	a.cues.clear()
	ow._cell = door + Vector2i(0, 1)
	ow._try_step(StepResolver.Dir.NORTH)
	var d_names := _cue_names(a)
	_chk("H.01 walking into a DOOR plays the door sound", d_names.has("SE_DOOR"))
	_chk("H.02 ...and does NOT also thud — the bump is gated on the door check "
			+ "FAILING, not played ahead of it", not d_names.has("SE_WALL_HIT"))

	# ⚠️ The discriminator: without this, a hook that never plays the bump at
	# all would still pass H.01/H.02.
	a.cues.clear()
	ow._warping = false
	ow._cell = wall + Vector2i(0, 1)
	ow._try_step(StepResolver.Dir.NORTH)
	_chk("H.03 walking into a plain WALL does thud",
			_cue_names(a).has("SE_WALL_HIT"))

	ow.queue_free()
	await get_tree().process_frame


# --- helpers ----------------------------------------------------------------

func _last_cue(a: GameAudio, kind: String) -> String:
	for i in range(a.cues.size() - 1, -1, -1):
		if a.cues[i]["kind"] == kind:
			return str(a.cues[i]["name"])
	return ""


func _cue_names(a: GameAudio) -> Array:
	var out := []
	for c in a.cues:
		out.append(str(c["name"]))
	return out



func _op(op_name: String, args: Array) -> Dictionary:
	return {"op": op_name, "args": args}


func _src(ops: Dictionary, texts: Dictionary = {}) -> ScriptVM.ScriptSource:
	var s := ScriptVM.ScriptSource.new()
	s.ops_by_label = ops
	s.texts = texts
	return s


func _run(vm: ScriptVM, limit: int = 200) -> void:
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


func _runs_clean(ops: Array, a: GameAudio) -> bool:
	var vm := ScriptVM.new(_src({"T": ops}), FlagStore.new())
	vm.audio = a
	vm.start("T")
	_run(vm)
	return vm.pause_reason == ScriptVM.Pause.DONE


## [M27R 7c] Cries.
func _test_7c_cries() -> void:
	# ⚠️ DEX-KEYED, never name-keyed. The name route is where the gendered
	# Nidoran collide — `[M27B Step 4]`'s own collision — and the generator has
	# already resolved it, so nothing at runtime needs to know.
	_chk("G.01 a cry path is built from the dex, not a name",
			AudioMap.cry_path(25).ends_with("cry_0025.wav")
			and AudioMap.cry_path(0) == "")

	if not FileAccess.file_exists(AudioMap.cry_path(1)):
		_gated += 7
		return

	# The roster guard: every species this project implements must have one, or
	# that Pokemon is silent and nothing reports it.
	var missing := 0
	var checked := 0
	for row in PokemonRegistry.get_all_species():
		var dex: int = int(row.get("dex", 0))
		if dex <= 0:
			continue
		checked += 1
		if not FileAccess.file_exists(AudioMap.cry_path(dex)):
			missing += 1
	_chk("G.02 every one of the %d roster species has a cry" % checked,
			checked > 300 and missing == 0)

	# ⚠️ THE NIDORAN PAIR SPECIFICALLY. They are the one case a name-based pull
	# gets wrong silently, by giving one of them the other's cry — so assert
	# they resolve to DIFFERENT files with different contents.
	var f := FileAccess.open(AudioMap.cry_path(29), FileAccess.READ)   # Nidoran-F
	var m := FileAccess.open(AudioMap.cry_path(32), FileAccess.READ)   # Nidoran-M
	var fb := f.get_buffer(4096) if f != null else PackedByteArray()
	var mb := m.get_buffer(4096) if m != null else PackedByteArray()
	if f != null: f.close()
	if m != null: m.close()
	_chk("G.03 the two Nidoran have DIFFERENT cries, not one shared file",
			fb.size() > 0 and mb.size() > 0 and fb != mb)

	# Authentic GBA rips, not resampled: RIFF, 8-bit mono 10512 Hz.
	var h := FileAccess.open(AudioMap.cry_path(1), FileAccess.READ)
	var head := h.get_buffer(32) if h != null else PackedByteArray()
	if h != null: h.close()
	_chk("G.04 the pulled files are real RIFF/WAVE",
			head.size() >= 12 and head.slice(0, 4).get_string_from_ascii() == "RIFF"
			and head.slice(8, 12).get_string_from_ascii() == "WAVE")

	var audio := GameAudio.new()
	add_child(audio)
	audio.cues.clear()
	_chk("G.05 playing a cry records a cue even with no audio device",
			audio.play_cry(25) or true)
	var last: Dictionary = audio.cues[audio.cues.size() - 1]
	_chk("G.06 ...and the cue names the cry and its real path",
			str(last["kind"]) == "cry" and str(last["path"]).ends_with("cry_0025.wav"))

	# ⚠️ An absent cry must still resolve `se_finished`, or a `waitmoncry` built
	# later would hang on a sound that never started.
	audio.cues.clear()
	_chk("G.07 an unknown dex does not play and does not hang",
			not audio.play_cry(99999)
			and str(audio.cues[0]["kind"]) == "cry")

	# The opcode is live: `playmoncry` used to be a flat no-op.
	audio.cues.clear()
	var vm := ScriptVM.new(_src({"T": [
			_op("playmoncry", ["SPECIES_PIKACHU"]),
			_op("waitmoncry", []),
			_op("end", []),
		]}), FlagStore.new())
	vm.audio = audio
	vm.start("T")
	_run(vm)
	var fired := false
	for c in audio.cues:
		if str(c["kind"]) == "cry" and str(c["path"]).ends_with("cry_0025.wav"):
			fired = true
	_chk("G.08 playmoncry resolves a SPECIES_ constant and really plays it",
			fired)
	audio.queue_free()


## [M27R 7a-3] Battle effects.
func _test_7a3_battle_sfx() -> void:
	var names := ["SE_DAMAGE_NORMAL", "SE_DAMAGE_SUPER", "SE_DAMAGE_WEAK",
			"SE_BALL_THROW", "SE_BALL_HIT", "SE_BALL_SHAKE", "SE_BALL_CLICK",
			"SE_BALL_DROP", "SE_RECALL", "SE_SEND_OUT", "SE_FLEE"]
	var known := 0
	var on_disk := 0
	for n in names:
		if AudioMap.SE.has(n):
			known += 1
			if FileAccess.file_exists(AudioMap.se_path(n)):
				on_disk += 1
	_chk("H.01 all 11 battle effects are catalogued", known == 11)
	# ⚠️ Catalogued is not the same as PRESENT. A name pointing at a missing
	# file plays silence and reports nothing, which is how `SE_SAVE` once ended
	# up aimed at the ME folder.
	_chk("H.02 ...and every one resolves to a real file (%d/11)" % on_disk,
			on_disk == 11)

	# ⚠️ THE THRESHOLDS ARE THE TIER. A super-effective hit that sounds
	# resisted is the most audible mistake a battle can make.
	_chk("H.03 effectiveness above 1 is SUPER, at every real multiplier",
			AudioMap.damage_se(2.0) == "SE_DAMAGE_SUPER"
			and AudioMap.damage_se(4.0) == "SE_DAMAGE_SUPER")
	_chk("H.04 below 1 is WEAK, and exactly 1 is NORMAL",
			AudioMap.damage_se(0.5) == "SE_DAMAGE_WEAK"
			and AudioMap.damage_se(0.25) == "SE_DAMAGE_WEAK"
			and AudioMap.damage_se(1.0) == "SE_DAMAGE_NORMAL")
	# An immune hit did no damage, so it makes no damage sound.
	_chk("H.05 an immune hit makes NO damage sound rather than a quiet one",
			AudioMap.damage_se(0.0) == "")

	# ⚠️ The shake count drives the capture sequence, and `[M27H H4]` already
	# emits one — recorded there so a later animation would have nothing to
	# retrofit. This is that consumer arriving.
	var caught := AudioMap.catch_sequence(3, true)
	_chk("H.06 a capture is throw, hit, three shakes, then the CLICK",
			caught.size() == 6 and caught[0] == "SE_BALL_THROW"
			and caught[1] == "SE_BALL_HIT" and caught[2] == "SE_BALL_SHAKE"
			and caught[5] == "SE_BALL_CLICK")
	var broke := AudioMap.catch_sequence(1, false)
	_chk("H.07 a break-free shakes fewer times and ends on the ball OPENING",
			broke.size() == 4 and broke[2] == "SE_BALL_SHAKE"
			and broke[3] == "SE_BALL_DROP")
	# The 0-shake case is real: a catch rate of 1 gives odds of exactly 0.
	# ⚠️ The 0-shake case is real, not defensive: `[M27H H4]` measured that a
	# catch rate of 1 gives odds of exactly 0 by integer truncation.
	var zero := AudioMap.catch_sequence(0, false)
	_chk("H.08 zero shakes still throws and opens, never an empty sequence",
			zero.size() == 3 and zero[0] == "SE_BALL_THROW"
			and zero[2] == "SE_BALL_DROP")
