extends Node

## [M27F Stage 4] The yes/no prompt, and the narrow specials carve-out.
##
## The two claims most worth pinning are both ones a plausible implementation
## gets backwards while still looking like it works:
##
##   * the cursor defaults to **YES**, and **YES is 1, NO is 0** — defaulting to
##     NO or swapping the values changes what a mashed A button does in all 425
##     corpus call sites, silently;
##   * an **unknown special HALTS** rather than degrading to a default. Writing
##     0 to VAR_RESULT would carry the nurse script through unaided, which is
##     exactly why it is tempting and exactly why it is wrong.

const EXPECTED_TOTAL := 64

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


func _ready() -> void:
	_test_yes_no_widget()
	_test_vm_specials()
	_test_registry()
	_test_polarity()
	_test_auto_confirm()
	_test_text_override()
	_test_nurse_end_to_end()

	var accounted := _total + _gated
	_chk("Z.99 every expected assertion ran (%d + %d gated == %d)"
			% [_total, _gated, EXPECTED_TOTAL], accounted == EXPECTED_TOTAL)
	print("m27f_stage4_test: %d/%d passed" % [_total - _failed, _total])
	get_tree().quit()


## --- A. the yes/no widget ---
func _test_yes_no_widget() -> void:
	var box := YesNoBox.new()
	add_child(box)
	_chk("A.01 it starts closed and invisible", not box.is_open and not box.visible)
	box.open()
	# ⚠️ Source calls DisplayYesNoMenuDefaultYes — initialCursorPos 0.
	_chk("A.02 the cursor DEFAULTS TO YES", box.is_open and box.index == 0)

	# ⚠️ The debounce. Input before it elapses is ignored outright.
	_chk("A.03 input is refused before the debounce elapses", not box.accepts_input)
	_chk("A.04 and confirming during it does nothing", box.confirm() == false and box.is_open)
	box.move(1)
	_chk("A.05 nor does moving", box.index == 0)
	box._process(YesNoBox.INPUT_DELAY)
	_chk("A.06 input is accepted once it has", box.accepts_input)
	_chk("A.07 the delay is source's own 5 frames, held as seconds",
			is_equal_approx(YesNoBox.INPUT_DELAY, 5.0 / 60.0))

	box.move(1)
	_chk("A.08 down moves to NO", box.index == 1)
	# Source uses Menu_ProcessInputNoWrap* — it does not wrap.
	box.move(1)
	_chk("A.09 and does NOT wrap past NO", box.index == 1)
	box.move(-1)
	box.move(-1)
	_chk("A.10 nor above YES", box.index == 0)

	var answers: Array[bool] = []
	box.chosen.connect(func(yes: bool) -> void: answers.append(yes))
	_chk("A.11 confirming YES answers true", box.confirm() == true)
	_chk("A.12 and closes", not box.is_open and not box.visible)
	_chk("A.13 and reports through the signal",
			answers.size() == 1 and answers[0] == true)

	box.open()
	box._process(YesNoBox.INPUT_DELAY)
	box.move(1)
	_chk("A.14 confirming NO answers false", box.confirm() == false)

	# ⚠️ B is not a third outcome — source folds MENU_B_PRESSED into the same
	# branch as choosing NO.
	box.open()
	box._process(YesNoBox.INPUT_DELAY)
	answers.clear()
	box.cancel()
	_chk("A.15 cancelling answers NO, not a third outcome",
			answers.size() == 1 and answers[0] == false and not box.is_open)
	box.free()


## --- B. the VM opcodes ---
func _test_vm_specials() -> void:
	# `special HealPlayerParty` on a real, damaged party.
	OverworldSession.reset()
	# [M27L L5] Seeded EXPLICITLY. `player_party()` no longer lazily builds
	# `[M27D D5]`'s debug team — a new game starts empty, like source's own
	# `ZeroPlayerPartyMons()`. The team still exists for tests like this one;
	# it is simply no longer what you get by default.
	if OverworldSession.party == null or OverworldSession.party.members.is_empty():
		OverworldSession.party = OverworldParty.build_debug_player_party()
	var party := OverworldSession.player_party()
	var lead: BattlePokemon = party.members[0]
	lead.current_hp = 1
	lead.status = BattlePokemon.STATUS_POISON
	lead.fainted = true
	var flags := FlagStore.new()
	var vm := ScriptVM.new(_src({
		"A": [_op("special", ["HealPlayerParty"]), _op("end")],
	}), flags)
	vm.start("A")
	vm.step()
	_chk("B.01 special HealPlayerParty restores HP", lead.current_hp == lead.max_hp)
	_chk("B.02 clears status", lead.status == BattlePokemon.STATUS_NONE)
	_chk("B.03 and revives", lead.fainted == false)

	# ⚠️ AN UNKNOWN SPECIAL HALTS. Degrading would hide 2,109 call sites' worth
	# of real gaps and make the coverage figures meaningless.
	var vm2 := ScriptVM.new(_src({
		"A": [_op("special", ["MakeMeASandwich"]), _op("end")],
	}), FlagStore.new())
	vm2.start("A")
	vm2.step()
	_chk("B.04 an unknown special HALTS rather than continuing",
			vm2.pause_reason == ScriptVM.Pause.UNKNOWN_OP)
	_chk("B.05 and names it, so the gap is findable",
			vm2.diagnostic.contains("MakeMeASandwich"))

	# ⚠️ ARGUMENT ORDER: `specialvar VAR_RESULT, Fn` — destination FIRST.
	# Reading them the other way round reports every call site as unimplemented.
	var flags3 := FlagStore.new()
	flags3.var_set("VAR_RESULT", 99)
	var vm3 := ScriptVM.new(_src({
		"A": [_op("specialvar", ["VAR_RESULT", "CountPlayerTrainerStars"]), _op("end")],
	}), flags3)
	vm3.start("A")
	vm3.step()
	_chk("B.06 an allowlisted specialvar writes its real value to the NAMED var",
			flags3.var_get("VAR_RESULT") == 0)
	_chk("B.07 and does not halt", vm3.pause_reason != ScriptVM.Pause.UNKNOWN_OP)

	# It writes the named destination, not VAR_RESULT unconditionally.
	var flags4 := FlagStore.new()
	var vm4 := ScriptVM.new(_src({
		"A": [_op("specialvar", ["VAR_TEMP_1", "IsPokerusInParty"]), _op("end")],
	}), flags4)
	vm4.start("A")
	vm4.step()
	_chk("B.08 into whichever var it names", flags4.var_get("VAR_TEMP_1") == 0)

	var vm5 := ScriptVM.new(_src({
		"A": [_op("specialvar", ["VAR_RESULT", "GetSecretBaseNerdTrainerName"]), _op("end")],
	}), FlagStore.new())
	vm5.start("A")
	vm5.step()
	_chk("B.09 an unknown specialvar HALTS too",
			vm5.pause_reason == ScriptVM.Pause.UNKNOWN_OP)
	_chk("B.10 naming the function, not the var",
			vm5.diagnostic.contains("GetSecretBaseNerdTrainerName"))

	# The presentation no-ops must not halt.
	var vm6 := ScriptVM.new(_src({
		"A": [_op("incrementgamestat", ["GAME_STAT_USED_POKECENTER"]),
			_op("hidefollower", ["0"]), _op("dofieldeffect", ["FLDEFF_POKECENTER_HEAL"]),
			_op("waitfieldeffect", ["FLDEFF_POKECENTER_HEAL"]), _op("end")],
	}), FlagStore.new())
	vm6.start("A")
	var ex := _drive(vm6)
	# `end` halts rather than executing, so it is not in the trace — 4, not 5.
	_chk("B.11 the presentation no-ops run rather than halting",
			vm6.pause_reason == ScriptVM.Pause.DONE and ex.size() == 4)

	# callnative shares the special registry.
	var vm7 := ScriptVM.new(_src({
		"A": [_op("callnative", ["UpdateFollowingPokemon"]), _op("end")],
	}), FlagStore.new())
	vm7.start("A")
	vm7.step()
	_chk("B.12 callnative resolves through the same registry",
			vm7.pause_reason != ScriptVM.Pause.UNKNOWN_OP)
	OverworldSession.reset()


## --- C. the registry ---
func _test_registry() -> void:
	_chk("C.01 HealPlayerParty is known", FieldSpecials.is_known_special("HealPlayerParty"))
	_chk("C.02 an arbitrary special is not",
			not FieldSpecials.is_known_special("BufferEReaderTrainerName"))
	_chk("C.03 the allowlisted specialvars are known",
			FieldSpecials.is_known_specialvar("CountPlayerTrainerStars")
			and FieldSpecials.is_known_specialvar("IsPokerusInParty")
			and FieldSpecials.is_known_specialvar("PlayerNotAtTrainerHillEntrance")
			and FieldSpecials.is_known_specialvar("BufferUnionRoomPlayerName")
			and FieldSpecials.is_known_specialvar("IsPlayerNotInTrainerTowerLobby"))
	# ⚠️ **THIS ASSERTED "the allowlist is still SHORT" AGAINST A USE-COUNT
	# RULE THAT THE TABLE WAS NEVER ACTUALLY FOLLOWING** — three of its five
	# original entries are admitted for INVARIANCE under a documented exclusion,
	# not for rarity. See `SPECIALVAR_VALUES`' own restated admission rule.
	# The size bound is kept (a table growing by category really has become
	# M27G) but it is no longer described as a use-count rule it does not
	# enforce, and the real criterion is asserted directly below it.
	_chk("C.04 the allowlist stays a tail, not a category — growth means M27G",
			FieldSpecials.SPECIALVAR_VALUES.size() <= 10)
	# ⚠️ THE ACTUAL RULE: nothing needing LIVE state may live in this table,
	# because `specialvar_value` takes no context and can only answer a
	# constant. `CalculatePlayerPartyCount` and `GetLeadMonFriendship` are the
	# standing counter-examples — both were implemented in the same pass that
	# added `ShouldTryRematchBattle` here, and both were deliberately routed to
	# `ScriptVM` instead because they read the party.
	_chk("C.11 state-dependent specialvars are NOT in the constant table",
			not FieldSpecials.is_known_specialvar("CalculatePlayerPartyCount")
			and not FieldSpecials.is_known_specialvar("GetLeadMonFriendship"))
	_chk("C.05 every allowlisted entry carries a stated reason",
			FieldSpecials.SPECIALVAR_VALUES.values().all(
					func(v: Array) -> bool: return str(v[1]).length() > 20))
	# ⚠️ THE NEGATED-PREDICATE TRAP. Both of these `return TRUE` unless you are
	# standing in one specific facility, so 1 is the honest value in a
	# Pokecentre. A blanket 0 carries both nurse scripts through anyway, which
	# is exactly why it would have survived and then been wrong elsewhere.
	_chk("C.07 a negated predicate answers 1, not a convenient 0",
			FieldSpecials.specialvar_value("PlayerNotAtTrainerHillEntrance") == 1
			and FieldSpecials.specialvar_value("IsPlayerNotInTrainerTowerLobby") == 1)
	_chk("C.08 while the genuinely-zero ones stay 0",
			FieldSpecials.specialvar_value("CountPlayerTrainerStars") == 0
			and FieldSpecials.specialvar_value("IsPokerusInParty") == 0
			and FieldSpecials.specialvar_value("BufferUnionRoomPlayerName") == 0)
	_chk("C.06 a special is not silently also a specialvar",
			not FieldSpecials.is_known_specialvar("HealPlayerParty"))
	# ⚠️ **THE NAME LIES, AND HALTING ON IT SOFT-LOCKED THE CORRIDOR.**
	# `SetUnlockedPokedexFlags` reads like an M33 Pokédex dependency and was
	# filed as one; its body only sets `gcnLinkFlags` bits that nothing on the
	# GBA ever reads (`save_location.c:125`, `global.h:610`). It sits mid-way
	# through `ReceiveDexScene`, so the halt stranded that script BEFORE the
	# five Poké Balls and the five `setvar`s that open the Viridian mart, the
	# old man, the rival's house and Route 22 — and left the scene infinitely
	# repeatable. Pinned here so a future tidy-up of NOOP_SPECIALS cannot quietly
	# take it back out. See `FieldSpecials.NOOP_SPECIALS`' own note.
	_chk("C.09 SetUnlockedPokedexFlags is a known no-op, not a Pokedex gap",
			FieldSpecials.is_known_special("SetUnlockedPokedexFlags")
			and not FieldSpecials.is_known_specialvar("SetUnlockedPokedexFlags"))


## --- E. polarity and literals: the two silent inverters ---
func _test_polarity() -> void:
	# ⚠️ 753 corpus args are YES / NO / MULTI_B_PRESSED, and every one resolved
	# to 0 before Stage 4 — so `goto_if_eq VAR_RESULT, YES` compared against 0
	# and a NO answer took the YES branch, region-wide.
	_chk("E.01 YES resolves to 1, not 0", ScriptVM._literal("YES") == 1)
	_chk("E.02 NO resolves to 0", ScriptVM._literal("NO") == 0)
	_chk("E.03 MULTI_B_PRESSED is source's own 127",
			ScriptVM._literal("MULTI_B_PRESSED") == 127)

	# ⚠️ THE HEADLINE: the two opcodes are OPPOSITE. Answering YES must write 1
	# for yesnobox and 0 for multichoice.
	var f1 := FlagStore.new()
	var vm1 := ScriptVM.new(_src({"A": [_op("yesnobox"), _op("end")]}), f1)
	vm1.start("A"); vm1.step()
	vm1.answer_yes_no(true)
	_chk("E.04 yesnobox: YES writes 1", f1.var_get("VAR_RESULT") == 1)

	var f2 := FlagStore.new()
	var vm2 := ScriptVM.new(_src({
		"A": [_op("multichoice", ["19", "8", "MULTI_YESNO", "0"]), _op("end")]}), f2)
	vm2.start("A"); vm2.step()
	_chk("E.05 multichoice MULTI_YESNO pauses for an answer",
			vm2.pause_reason == ScriptVM.Pause.WAIT_YES_NO)
	vm2.answer_yes_no(true)
	_chk("E.06 multichoice: YES writes 0 — the OPPOSITE of yesnobox",
			f2.var_get("VAR_RESULT") == 0)

	var f3 := FlagStore.new()
	var vm3 := ScriptVM.new(_src({
		"A": [_op("multichoice", ["19", "8", "MULTI_YESNO", "0"]), _op("end")]}), f3)
	vm3.start("A"); vm3.step(); vm3.answer_yes_no(false)
	_chk("E.07 and NO writes 1", f3.var_get("VAR_RESULT") == 1)

	# B is a distinct outcome for multichoice, folded onto NO for yesnobox.
	var f4 := FlagStore.new()
	var vm4 := ScriptVM.new(_src({
		"A": [_op("multichoice", ["19", "8", "MULTI_YESNO", "0"]), _op("end")]}), f4)
	vm4.start("A"); vm4.step(); vm4.cancel_yes_no()
	_chk("E.08 multichoice B is its own value, not NO", f4.var_get("VAR_RESULT") == 127)
	var f5 := FlagStore.new()
	var vm5 := ScriptVM.new(_src({"A": [_op("yesnobox"), _op("end")]}), f5)
	vm5.start("A"); vm5.step(); vm5.cancel_yes_no()
	_chk("E.09 yesnobox B folds onto NO", f5.var_get("VAR_RESULT") == 0)

	# Any other multichoice list halts rather than guessing at its contents.
	var vm6 := ScriptVM.new(_src({
		"A": [_op("multichoice", ["0", "0", "MULTI_LEVEL_MODE", "0"]), _op("end")]}),
		FlagStore.new())
	vm6.start("A"); vm6.step()
	_chk("E.10 any other multichoice list HALTS rather than guessing",
			vm6.pause_reason == ScriptVM.Pause.UNKNOWN_OP
			and vm6.diagnostic.contains("MULTI_LEVEL_MODE"))


## --- F. auto-confirm: the nurse skips her own prompt ---
func _test_auto_confirm() -> void:
	# ⚠️ A DELIBERATE DIVERGENCE FROM SOURCE. Source asks; this does not.
	_chk("F.01 both nurses are listed",
			ScriptVM.AUTO_CONFIRM_LABELS.has("EventScript_PkmnCenterNurse_Frlg")
			and ScriptVM.AUTO_CONFIRM_LABELS.has("Common_EventScript_PkmnCenterNurse"))
	# ⚠️ The list must stay SHORT and script-keyed. A blanket auto-confirm would
	# silently answer all 425 yes/no sites — shops, tutors, trades included.
	_chk("F.02 and the list is short — a blanket skip would answer all 425 sites",
			ScriptVM.AUTO_CONFIRM_LABELS.size() <= 4)

	# Kanto's form: multichoice, so YES is 0.
	var f1 := FlagStore.new()
	var vm1 := ScriptVM.new(_src({"EventScript_PkmnCenterNurse_Frlg": [
			_op("multichoice", ["19", "8", "MULTI_YESNO", "0"]), _op("end")]}), f1)
	vm1.start("EventScript_PkmnCenterNurse_Frlg")
	vm1.step()
	_chk("F.03 the Kanto nurse does NOT pause for a prompt",
			vm1.pause_reason != ScriptVM.Pause.WAIT_YES_NO)
	_chk("F.04 and YES is already written, in multichoice polarity",
			f1.var_get("VAR_RESULT") == 0)

	# Hoenn's form: yesnobox, so YES is 1 — the auto path must respect the same
	# split the real prompt does, or one nurse heals and the other does not.
	var f2 := FlagStore.new()
	var vm2 := ScriptVM.new(_src({"Common_EventScript_PkmnCenterNurse": [
			_op("yesnobox"), _op("end")]}), f2)
	vm2.start("Common_EventScript_PkmnCenterNurse")
	vm2.step()
	_chk("F.05 the Hoenn nurse likewise skips it",
			vm2.pause_reason != ScriptVM.Pause.WAIT_YES_NO)
	_chk("F.06 with YES in yesnobox polarity — the OPPOSITE value",
			f2.var_get("VAR_RESULT") == 1)

	# ⚠️ The discriminator that matters: an ordinary script still prompts.
	var f3 := FlagStore.new()
	var vm3 := ScriptVM.new(_src({"SomeShopkeeper": [
			_op("yesnobox"), _op("end")]}), f3)
	vm3.start("SomeShopkeeper")
	vm3.step()
	_chk("F.07 but any OTHER script still gets its real prompt",
			vm3.pause_reason == ScriptVM.Pause.WAIT_YES_NO)


## --- G. the authored text override ---
func _test_text_override() -> void:
	# ⚠️ **REPOINTED 2026-08-07 — this used to assert on `ScriptVM.TEXT_OVERRIDES`,
	# which no longer exists.** That const held authored replacements for two
	# imported nurse lines and existed only because the corpus was generated
	# from a read-only reference clone at the time. `field_script_source/` is a
	# tracked, hand-editable fork, so overriding a reference line now means
	# EDITING THE LINE; both entries moved there and the const was retired
	# rather than becoming a third dialogue source with a VM special-case.
	#
	# These assertions are STRONGER for it: they test the shipped CONTENT in
	# the real compiled corpus rather than the mechanism that used to patch it,
	# so they would survive the content moving again.
	if not FileAccess.file_exists("res://data/map_texts.json"):
		_gated += 4
		return
	var parsed = JSON.parse_string(FileAccess.open(
			"res://data/map_texts.json", FileAccess.READ).get_as_text())
	var texts: Dictionary = parsed if parsed is Dictionary else {}
	var pages: Array = texts.get("Text_WelcomeWantToHealPkmn_Frlg", [])
	_chk("G.01 the nurse greeting is in the corpus at all", not pages.is_empty())
	# The nurse auto-confirms (AUTO_CONFIRM_LABELS), so source's own second page
	# would be printed and then answered by nobody.
	_chk("G.02 the authored edit replaces the corpus text, not appends to it",
			pages.size() == 1)
	_chk("G.03 the greeting survives",
			pages.size() > 0 and str(pages[0]).begins_with("Welcome"))
	_chk("G.04 and the question is gone",
			pages.size() > 0
			and not str(pages[0]).to_lower().contains("would you like"))


## --- D. the real nurse script, end to end ---
func _test_nurse_end_to_end() -> void:
	if not (FileAccess.file_exists("res://data/map_scripts.json")
			and FileAccess.file_exists("res://data/map_texts.json")):
		_gated += 6
		return
	var ops: Dictionary = JSON.parse_string(
			FileAccess.open("res://data/map_scripts.json", FileAccess.READ).get_as_text())
	var texts: Dictionary = JSON.parse_string(
			FileAccess.open("res://data/map_texts.json", FileAccess.READ).get_as_text())
	_chk("D.01 the real Pewter nurse script exists in the corpus",
			ops.has("PewterCity_PokemonCenter_1F_EventScript_Nurse"))

	OverworldSession.reset()
	# [M27L L5] Seeded EXPLICITLY. `player_party()` no longer lazily builds
	# `[M27D D5]`'s debug team — a new game starts empty, like source's own
	# `ZeroPlayerPartyMons()`. The team still exists for tests like this one;
	# it is simply no longer what you get by default.
	if OverworldSession.party == null or OverworldSession.party.members.is_empty():
		OverworldSession.party = OverworldParty.build_debug_player_party()
	var party := OverworldSession.player_party()
	for m: BattlePokemon in party.members:
		m.current_hp = 1
		m.status = BattlePokemon.STATUS_POISON
	var flags := FlagStore.new()
	var vm := ScriptVM.new(_src(ops, texts), flags)
	vm.start("PewterCity_PokemonCenter_1F_EventScript_Nurse")

	# Drive it, answering YES at the prompt — the whole point of Stage 4.
	var n := 0
	var saw_yes_no := false
	while n < 400:
		if vm.step():
			n += 1
			continue
		match vm.pause_reason:
			ScriptVM.Pause.WAIT_MESSAGE, ScriptVM.Pause.WAIT_BUTTON:
				vm.resume(); n += 1
			ScriptVM.Pause.WAIT_YES_NO:
				saw_yes_no = true
				vm.answer_yes_no(true)  # the VM writes the right value per opcode
				n += 1
			ScriptVM.Pause.WAIT_MOVEMENT:
				vm.resume(); n += 1
			_:
				break
	# ⚠️ REWRITTEN, NOT DELETED. This asserted the nurse reaches a prompt, which
	# was true until the auto-confirm follow-up made her heal on contact. The
	# property worth guarding now is the OPPOSITE one.
	_chk("D.02 the nurse never prompts — she heals on contact (Rob's call)",
			not saw_yes_no)
	_chk("D.03 and runs to completion rather than hitting a gap (%s: %s)"
			% [vm.pause_reason, vm.diagnostic], vm.pause_reason == ScriptVM.Pause.DONE)
	var healed := true
	for m: BattlePokemon in party.members:
		if m.current_hp != m.max_hp or m.status != BattlePokemon.STATUS_NONE:
			healed = false
	_chk("D.04 the party is fully healed", healed)

	# ⚠️ REWRITTEN, NOT DELETED. This used to answer NO and assert the party was
	# left alone — the check that the prompt was not decorative. With the nurse
	# auto-confirming there is no NO to give, so the property worth guarding is
	# the stronger one: she heals with NOBODY answering anything at all. A
	# driver that never handles WAIT_YES_NO would hang if the prompt returned.
	OverworldSession.reset()
	# [M27L L5] Seeded EXPLICITLY. `player_party()` no longer lazily builds
	# `[M27D D5]`'s debug team — a new game starts empty, like source's own
	# `ZeroPlayerPartyMons()`. The team still exists for tests like this one;
	# it is simply no longer what you get by default.
	if OverworldSession.party == null or OverworldSession.party.members.is_empty():
		OverworldSession.party = OverworldParty.build_debug_player_party()
	var party2 := OverworldSession.player_party()
	party2.members[0].current_hp = 1
	var flags2 := FlagStore.new()
	var vm2 := ScriptVM.new(_src(ops, texts), flags2)
	vm2.start("PewterCity_PokemonCenter_1F_EventScript_Nurse")
	var n2 := 0
	var prompted := false
	while n2 < 400:
		if vm2.step():
			n2 += 1
			continue
		match vm2.pause_reason:
			ScriptVM.Pause.WAIT_MESSAGE, ScriptVM.Pause.WAIT_BUTTON, \
			ScriptVM.Pause.WAIT_MOVEMENT:
				vm2.resume(); n2 += 1
			ScriptVM.Pause.WAIT_YES_NO:
				prompted = true
				break
			_:
				break
	_chk("D.05 she heals with nobody answering anything",
			not prompted and party2.members[0].current_hp == party2.members[0].max_hp)
	_chk("D.06 and still ends cleanly", vm2.pause_reason == ScriptVM.Pause.DONE)

	OverworldSession.reset()
