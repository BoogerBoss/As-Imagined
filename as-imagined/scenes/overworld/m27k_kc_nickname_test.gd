extends Node

## [M27K K-c] Nicknaming — where `[M27K K-a]` stopped, because the keyboard it
## needed did not exist yet.
##
## The claims most worth pinning:
##
##   * a NICKNAME has no preset list, where a PLAYER name is nothing but one —
##     `sMonNamingScreenTemplate` (`naming_screen.c:2172`) is a bare keyboard and
##     only PLAYER/RIVAL get the preset treatment, so the two really are
##     different screens rather than one screen with a flag;
##   * OK on an EMPTY entry is ACCEPTED for a nickname and REFUSED for a player
##     name, and both halves are source: `SaveInputText` (`naming_screen.c:1921`)
##     writes the typed buffer only if something was typed, and the buffer was
##     pre-seeded with the current nickname;
##   * `VAR_0x8004` is a party SLOT INDEX (`pokemon.c:6846`), with one reserved
##     value for the PC — and the PC path HALTS rather than quietly renaming a
##     party member instead;
##   * `display_name()` is now what the field shows, closing a gap where the
##     nickname was a field you could write and never see anywhere.

const EXPECTED_TOTAL := 43

## Past the cap and past the grid, so a refusal or a clamp is what stops the
## loop rather than the loop running out on its own.
const OVERFILL := 40

var _total := 0
var _failed := 0
var _gated := 0

var _src: ScriptVM.ScriptSource = null


func _chk(label: String, cond: bool) -> void:
	_total += 1
	if not cond:
		_failed += 1
		print("FAILED: %s" % label)


func _read(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var j = JSON.parse_string(f.get_as_text())
	return j if typeof(j) == TYPE_DICTIONARY else {}


func _screen() -> NamingScreen:
	var s := NamingScreen.new()
	add_child(s)
	return s


## A VM holding a real party, running a hand-written script.
##
## Synthetic ops rather than `_execute`: the opcode dispatch lives inside
## `step()`, so the only honest way to exercise an opcode is to run one.
func _run_ops(member_count: int, ops: Array) -> ScriptVM:
	var src := ScriptVM.ScriptSource.new()
	src.ops_by_label = {"T": ops}
	var vm := ScriptVM.new(src, FlagStore.new())
	var p := BattleParty.new()
	for i in range(member_count):
		p.members.append(PokemonFactory.create_battle_pokemon(1 + i * 3, 5))
	vm.party = p
	vm.start("T")
	var guard := 0
	while vm.step() and guard < 100:
		guard += 1
	return vm


## `setvar VAR_0x8004, <slot>` then `special ChangePokemonNickname` — the exact
## two-opcode shape `EventScript_GiveNicknameToStarter` reaches through
## `Common_EventScript_NameReceivedPartyMon`.
func _run_nickname(member_count: int, slot: int) -> ScriptVM:
	return _run_ops(member_count, [
		{"op": "setvar", "args": ["VAR_0x8004", str(slot)]},
		{"op": "special", "args": [FieldSpecials.NICKNAME_SPECIAL]},
	])


func _ready() -> void:
	_src = ScriptVM.ScriptSource.new()
	_src.ops_by_label = _read("res://data/map_scripts.json")
	_src.texts = _read("res://data/map_texts.json")

	_test_keyboard_mode()
	_test_display_name()
	_test_vm_plumbing()
	_test_real_script()

	var accounted := _total + _gated
	_chk("Z.99 every expected assertion ran (%d + %d gated == %d)"
			% [_total, _gated, EXPECTED_TOTAL], accounted == EXPECTED_TOTAL)
	print("m27k_kc_nickname_test: %d/%d passed" % [_total - _failed, _total])
	get_tree().quit()


## --- A. the keyboard-direct screen ---
func _test_keyboard_mode() -> void:
	var s := _screen()
	s.open_keyboard("Bulbasaur's nickname?")
	# ⚠️ THE OPPOSITE OF K-b's SCREEN, AND SOURCE IS WHY. A player name is a
	# preset list you can escape into a keyboard; a nickname has no list at all.
	_chk("A.01 a nickname opens straight onto the KEYBOARD",
			s.mode == NamingScreen.Mode.KEYBOARD and s.is_open)
	var rows := s.row_texts()
	_chk("A.02 with no preset list behind it at all",
			not " ".join(rows).contains(PlayerIdentity.NEW_NAME))
	_chk("A.03 and the prompt names what is being renamed",
			s.prompt_text() == "Bulbasaur's nickname?")

	s.confirm()
	_chk("A.04 typing works from the first frame", s.typed == "A")

	# ⚠️ OK IS A CELL ON THE GRID, NOT A SEPARATE BINDING — see NamingScreen's
	# OK_LABEL. This is the assertion standing between the screen and K-b's real
	# defect, where the only way to submit was an input action that could never
	# fire because `ui_accept` and `ui_text_submit` are both bound to Enter.
	_chk("A.05 OK is a real row on the grid",
			str(rows[rows.size() - 1]).contains(NamingScreen.OK_LABEL))
	s.move(OVERFILL)
	_chk("A.06 moving past the last character lands on OK, not off the end",
			s.on_ok_key())

	var got: Array[String] = []
	s.name_chosen.connect(func(v: String) -> void: got.append(v))
	s.confirm()
	_chk("A.07 confirming ON OK accepts, which is how a name is submitted",
			got.size() == 1 and got[0] == "A" and not s.is_open)

	# ⚠️ EMPTY IS ACCEPTED HERE. `SaveInputText` copies the typed buffer into the
	# destination only if something was typed, and the destination already held
	# the species name — so OK-with-nothing-typed is how you back out once the
	# keyboard is up, not an error.
	var s2 := _screen()
	s2.open_keyboard("Bulbasaur's nickname?")
	var got2: Array[String] = []
	s2.name_chosen.connect(func(v: String) -> void: got2.append(v))
	_chk("A.08 OK on an EMPTY nickname is accepted, not refused", s2.accept())
	_chk("A.09 and reports \"\", the caller's signal to keep what it had",
			got2.size() == 1 and got2[0] == "")

	# ⚠️ AND THE PLAYER SCREEN STILL REFUSES ONE. Two entry points, two
	# behaviours, both source — a fixture where they AGREED could not tell the
	# `_allow_empty` flag from a screen that simply always accepts.
	var s3 := _screen()
	s3.open("Your name?", PlayerIdentity.MALE_NAMES)
	s3.confirm()  # NEW NAME -> keyboard
	_chk("A.10 whereas an empty PLAYER name is still refused", not s3.accept())

	var s4 := _screen()
	s4.open_keyboard("X's nickname?")
	for i in range(OVERFILL):
		s4.confirm()
	_chk("A.11 the cap still applies on the keyboard-direct path",
			s4.typed.length() == PlayerIdentity.NAME_LENGTH)

	var s5 := _screen()
	s5.open_keyboard("X's nickname?")
	s5.move(OVERFILL)
	s5.next_page()
	_chk("A.12 changing page moves the cursor OFF OK, not off the new page",
			not s5.on_ok_key())
	s.free(); s2.free(); s3.free(); s4.free(); s5.free()


## --- B. the name things actually SHOW ---
func _test_display_name() -> void:
	var mon := PokemonFactory.create_battle_pokemon(1, 5)
	var species_name := mon.species.species_name
	_chk("B.01 an un-renamed mon displays its species name",
			mon.display_name() == species_name and species_name != "")
	mon.nickname = "SPUD"
	_chk("B.02 and a renamed one displays the nickname", mon.display_name() == "SPUD")

	# The fallback exists for hand-built fixtures, which is most of this project's
	# battle tests — the factory always seeds a nickname, so it never fires on a
	# mon anything in production made.
	var bare := BattlePokemon.new()
	bare.species = PokemonRegistry.get_species_resource(1)
	_chk("B.03 a bare fixture with no nickname falls back to the species",
			bare.display_name() == species_name)
	var empty := BattlePokemon.new()
	_chk("B.04 and one with no species at all is \"\", not a crash",
			empty.display_name() == "")

	# ⚠️ THE GAP THIS CLOSES. The field party screen read `species.species_name`,
	# so a mon you had just named still showed up as its species.
	var party := BattleParty.new()
	party.members.append(mon)
	var screen := FieldPartyScreen.new()
	add_child(screen)
	screen.open(party)
	_chk("B.05 the field party screen shows the nickname",
			str(screen.row_texts()[0]).contains("SPUD")
			and not str(screen.row_texts()[0]).contains(species_name))
	screen.free()

	# ⚠️ A FIXTURE WHERE THE TWO AGREE CANNOT TELL THEM APART. Everywhere else
	# `nickname` and `species_name` start equal; here the species is changed
	# underneath, which is the one case where reading the wrong field is visible
	# — and it is why the BATTLE screen's call sites are deliberately NOT swapped
	# in K-c. A Transformed Ditto reads DITTO here and PIKACHU there, source
	# agrees with this one, and that is a battle-behaviour change of its own.
	var shifted := PokemonFactory.create_battle_pokemon(1, 5)
	shifted.species = PokemonRegistry.get_species_resource(25)
	_chk("B.06 a species change moves species_name and NOT the nickname",
			shifted.display_name() == species_name
			and shifted.species.species_name != species_name)


## --- C. the VM plumbing ---
func _test_vm_plumbing() -> void:
	# ⚠️ A NO-OP ON PURPOSE, AND NOT BECAUSE NO FADE EXISTS — `_fade_to` does.
	# The nickname script fades TO black and nothing ever fades back; source's
	# screen-transition callback does that. A real fade here would leave the
	# screen black for good, so the no-op is the SAFE reading, not the lazy one.
	var vm0 := _run_ops(1, [{"op": "fadescreen", "args": ["FADE_TO_BLACK"]}])
	_chk("C.01 fadescreen runs to the end rather than halting",
			vm0.pause_reason == ScriptVM.Pause.DONE)

	var vm := _run_nickname(2, 0)
	_chk("C.02 the nickname special PAUSES rather than halting",
			vm.pause_reason == ScriptVM.Pause.WAIT_NAMING)
	_chk("C.03 and the specials registry reports it as known",
			FieldSpecials.is_known_special(FieldSpecials.NICKNAME_SPECIAL))
	# ⚠️ NAMED THERE BUT NOT RUN THERE. `run()` answers synchronously, the wrong
	# shape for a special that owns the display — so it refuses, and a caller
	# that skipped the VM's interception halts rather than silently skipping the
	# rename.
	_chk("C.04 but run() refuses it, so an un-intercepted caller cannot skip it",
			not FieldSpecials.run(FieldSpecials.NICKNAME_SPECIAL))
	_chk("C.05 the slot it paused on is VAR_0x8004's value", vm.naming_slot == 0)
	_chk("C.06 the prompt names the SPECIES being renamed",
			vm.naming_prompt() == "%s's nickname?"
					% vm.party.members[0].species.species_name)

	# ⚠️ A SECOND SLOT, BECAUSE A FIXTURE PINNED AT 0 CANNOT TELL "reads
	# VAR_0x8004" FROM "always renames the lead".
	var vm2 := _run_nickname(3, 2)
	_chk("C.07 a different VAR_0x8004 names a different slot", vm2.naming_slot == 2)

	# resume() must NOT clear this — the typed name is a result, like a battle's.
	vm2.resume()
	_chk("C.08 resume() alone cannot clear WAIT_NAMING, as it cannot for a battle",
			vm2.pause_reason == ScriptVM.Pause.WAIT_NAMING)

	var untouched := vm2.party.members[0].nickname
	vm2.answer_naming("SPUD")
	_chk("C.09 answering writes the nickname to the slot it paused on",
			vm2.party.members[2].nickname == "SPUD")
	_chk("C.10 and leaves the other members alone",
			vm2.party.members[0].nickname == untouched and untouched != "SPUD")
	_chk("C.11 and the VM resumes", vm2.pause_reason == ScriptVM.Pause.NONE)

	# ⚠️ EMPTY KEEPS, IT DOES NOT CLEAR. `SaveInputText` simply does not write
	# when nothing was typed, so the mon stays named after its species.
	var vm3 := _run_nickname(1, 0)
	var was := vm3.party.members[0].nickname
	vm3.answer_naming("")
	_chk("C.12 an empty answer KEEPS the existing name rather than clearing it",
			vm3.party.members[0].nickname == was and was != "")

	# ⚠️ THE PC PATH HALTS. There is no PC (I5-5), and renaming a party member
	# when the script asked for a boxed one is the near-miss that reads as
	# working.
	var vm4 := _run_nickname(1, ScriptVM.PC_MON_CHOSEN)
	# ⚠️ **C.13 ALONE CANNOT TELL WHICH GUARD FIRED, AND THE BREAK TEST PROVED
	# IT** — deleting the PC branch entirely leaves this assertion green, because
	# 0xFE is also past the end of any party, so the range check below it halts
	# with the same pause and the same untouched nickname. Two competing rules
	# agreeing on one fixture, which is this project's own recorded trap. C.14 is
	# the discriminator and is written as one: it pins that the diagnostic is the
	# PC one and NOT the range one.
	_chk("C.13 the PC path halts rather than renaming a party member",
			vm4.pause_reason == ScriptVM.Pause.UNKNOWN_OP
			and vm4.party.members[0].nickname
					== vm4.party.members[0].species.species_name)
	_chk("C.14 and halts as the PC case, not as an out-of-range slot",
			vm4.diagnostic.contains("PC") and not vm4.diagnostic.contains("party holds"))

	var vm5 := _run_nickname(1, 4)
	_chk("C.15 a slot past the end of the party halts too",
			vm5.pause_reason == ScriptVM.Pause.UNKNOWN_OP)

	var vm6 := _run_ops(1, [{"op": "end", "args": []}])
	var before := vm6.party.members[0].nickname
	vm6.answer_naming("GHOST")
	_chk("C.16 answering when nothing is waiting does nothing",
			vm6.party.members[0].nickname == before)


## --- D. Kanto's own script, end to end ---
func _test_real_script() -> void:
	if _src.ops_by_label.is_empty():
		_gated += 9
		return
	for lab in ["EventScript_GiveNicknameToStarter",
			"Common_EventScript_NameReceivedPartyMon"]:
		_chk("D.01 the corpus carries %s" % lab, _src.ops_by_label.has(lab))

	# ⚠️ THE HEADLINE: `[M27K K-a]` could not answer YES here. The branch reached
	# `fadescreen` and halted before the special, so nicknaming the starter was
	# unreachable in play — which is exactly why K-a's own runner answers NO.
	var named := _run_starter(true, "SPUD")
	_chk("D.02 saying YES reaches the keyboard rather than halting",
			named["reached_naming"] and not named["halted"])
	_chk("D.03 and offers the starter you actually chose",
			named["party"].size() == 1
			and named["prompt"] == "%s's nickname?"
					% named["party"][0].species.species_name)
	_chk("D.04 the typed name sticks to the mon",
			named["party"][0].nickname == "SPUD")
	_chk("D.05 and is what the field would show",
			named["party"][0].display_name() == "SPUD")

	# ⚠️ DECLINING MUST NOT OPEN IT. Without this, a flow that always opened the
	# keyboard would pass every assertion above.
	var plain := _run_starter(false, "")
	_chk("D.06 declining never opens the keyboard", not plain["reached_naming"])
	_chk("D.07 and leaves the mon named after its species",
			plain["party"].size() == 1
			and plain["party"][0].display_name()
					== plain["party"][0].species.species_name)
	_chk("D.08 which is a different answer from the renamed run",
			plain["party"][0].display_name() != "SPUD")


## Drive the ball script and the give the way the real scene does, answering the
## nickname prompt either way.
func _run_starter(nickname_it: bool, type_this: String) -> Dictionary:
	var flags := FlagStore.new()
	var party := BattleParty.new()
	var vm := ScriptVM.new(_src, flags)
	vm.party = party
	var halted := false
	var reached := false
	var prompt := ""
	for label in ["PalletTown_ProfessorOaksLab_EventScript_BulbasaurBall",
			"PalletTown_ProfessorOaksLab_EventScript_ChoseStarter"]:
		vm.start(label)
		var guard := 0
		while guard < 400:
			var inner := 0
			while vm.step() and inner < 500:
				inner += 1
			if vm.pause_reason == ScriptVM.Pause.WAIT_MESSAGE \
					or vm.pause_reason == ScriptVM.Pause.WAIT_BUTTON:
				vm.resume()
			elif vm.pause_reason == ScriptVM.Pause.WAIT_YES_NO:
				# YES to "is this the one?", then the nickname question.
				if str(vm.script_label).contains("ChoseStarter"):
					vm.answer_yes_no(nickname_it)
				else:
					vm.answer_yes_no(true)
			elif vm.pause_reason == ScriptVM.Pause.WAIT_NAMING:
				reached = true
				prompt = vm.naming_prompt()
				vm.answer_naming(type_this)
			else:
				if vm.pause_reason == ScriptVM.Pause.UNKNOWN_OP \
						or vm.pause_reason == ScriptVM.Pause.UNRESOLVED:
					halted = true
				break
			guard += 1
	return {
		"party": party.members,
		"reached_naming": reached,
		"prompt": prompt,
		"halted": halted,
		"diagnostic": vm.diagnostic,
	}
