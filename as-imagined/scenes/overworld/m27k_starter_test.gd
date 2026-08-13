extends Node

## [M27K K-a] The starter, which was already authored as imported Kanto data.
##
## The claims most worth pinning:
##
##   * a SPECIES_* constant is a real value — 295 corpus args are one, and every
##     single one resolved to 0 before this, so no script could name a Pokémon;
##   * the two in-roster ALIASES resolve (Castform, Deoxys), which an int-only
##     parse of the enum silently drops;
##   * a KNOWN constant naming an unimplemented species is a different failure
##     from an UNKNOWN constant, and stays distinguishable;
##   * Kanto's own `EventScript_ChoseStarter` runs, gives a real Pokémon, and
##     sets `FLAG_SYS_POKEMON_GET` — which is what makes the party screen
##     reachable in play at all.

const EXPECTED_TOTAL := 36

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


func _ready() -> void:
	_src = ScriptVM.ScriptSource.new()
	_src.ops_by_label = _read("res://data/map_scripts.json")
	_src.texts = _read("res://data/map_texts.json")

	_test_species_map()
	_test_literal()
	_test_givemon()
	_test_starter_script()

	var accounted := _total + _gated
	_chk("Z.99 every expected assertion ran (%d + %d gated == %d)"
			% [_total, _gated, EXPECTED_TOTAL], accounted == EXPECTED_TOTAL)
	print("m27k_starter_test: %d/%d passed" % [_total - _failed, _total])
	get_tree().quit()


## --- A. the species name map ---
func _test_species_map() -> void:
	_chk("A.01 the three Kanto starters resolve",
			PokemonRegistry.species_id_of("SPECIES_BULBASAUR") == 1
			and PokemonRegistry.species_id_of("SPECIES_CHARMANDER") == 4
			and PokemonRegistry.species_id_of("SPECIES_SQUIRTLE") == 7)
	_chk("A.02 each generation ends where the dex says",
			PokemonRegistry.species_id_of("SPECIES_MEW") == 151
			and PokemonRegistry.species_id_of("SPECIES_CELEBI") == 251
			and PokemonRegistry.species_id_of("SPECIES_DEOXYS") == 386)
	# ⚠️ 98 entries are `SPECIES_X = SPECIES_Y`, and TWO of them are Pokémon this
	# project implements. An int-only parse of the enum drops exactly these.
	_chk("A.03 the in-roster ALIASES resolve — an int-only parse loses them",
			PokemonRegistry.species_id_of("SPECIES_CASTFORM") == 351
			and PokemonRegistry.species_id_of("SPECIES_DEOXYS") == 386)
	_chk("A.04 and an alias equals its target exactly",
			PokemonRegistry.species_id_of("SPECIES_DEOXYS")
			== PokemonRegistry.species_id_of("SPECIES_DEOXYS_NORMAL"))
	# ⚠️ THE TWO-STEP. A known constant can still name a species this project
	# does not implement; that is a scope boundary, not a pipeline bug, and the
	# two must stay tellable apart.
	_chk("A.05 an out-of-roster species resolves to a real id",
			PokemonRegistry.species_id_of("SPECIES_TURTWIG") > 386)
	_chk("A.06 but an unknown constant is -1, not 0 and not a guess",
			PokemonRegistry.species_id_of("SPECIES_NOT_A_THING") == -1)
	_chk("A.07 SPECIES_NONE is 0 and is not an error",
			PokemonRegistry.species_id_of("SPECIES_NONE") == 0)
	_chk("A.08 the map covers the whole reference enum, not just the roster",
			PokemonRegistry.species_constants().size() > 1000)

	# The headline: every species constant the corpus names must resolve.
	if _src.ops_by_label.is_empty():
		_gated += 3
	else:
		var named := {}
		var false_friends := {}
		for label in _src.ops_by_label:
			for c in _src.ops_by_label[label]:
				for a in c.get("args", []):
					if typeof(a) != TYPE_STRING or not str(a).begins_with("SPECIES_"):
						continue
					# ⚠️ A PREFIX COLLISION, NOT A GAP — and the guard found it.
					# `SPECIES_GFX_CHANGE_*` are graphics-change MODES from a
					# different enum entirely (`include/constants/battle_anim.h`
					# :690), and every corpus use is a `createvisualtask` inside
					# a battle-ANIMATION script, which is M36's domain and not a
					# map script at all. Excluded by name so the carve-out is a
					# stated fact rather than a silently loosened assertion.
					if str(a).begins_with("SPECIES_GFX_CHANGE_"):
						false_friends[str(a)] = true
						continue
					named[str(a)] = true
		_chk("A.09a the SPECIES_GFX_CHANGE_* false friends are the only exclusions (%d)"
				% false_friends.size(),
				false_friends.size() == 5)
		var unresolved: Array[String] = []
		var out_of_roster := 0
		for name in named:
			var dex := PokemonRegistry.species_id_of(name)
			if dex < 0:
				unresolved.append(name)
			elif dex > 386:
				out_of_roster += 1
		_chk("A.09 every species constant the corpus names resolves (%d named, %d unresolved)"
				% [named.size(), unresolved.size()], unresolved.is_empty())
		_chk("A.10 and the corpus reaches past this project's roster (%d do), so the two-step is not theoretical"
				% out_of_roster, out_of_roster > 0)


## --- B. _literal ---
func _test_literal() -> void:
	# ⚠️ THE BUG THIS CLOSES. Before this, EVERY species constant fell through
	# to 0, so `setvar PLAYER_STARTER_SPECIES, SPECIES_BULBASAUR` stored nothing
	# and the starter script could not name its own Pokémon.
	_chk("B.01 a species constant is a real value, not 0",
			ScriptVM._literal("SPECIES_BULBASAUR") == 1)
	_chk("B.02 and a different species is a different value",
			ScriptVM._literal("SPECIES_SQUIRTLE") == 7)
	_chk("B.03 an unknown species reads 0 rather than -1 — a var holds numbers",
			ScriptVM._literal("SPECIES_NOT_A_THING") == 0)
	# The pre-existing literals must be untouched by the new branch.
	_chk("B.04 YES/NO still resolve as before",
			ScriptVM._literal("YES") == 1 and ScriptVM._literal("NO") == 0)
	_chk("B.05 and a plain integer still does",
			ScriptVM._literal("42") == 42)


## --- C. givemon ---
func _test_givemon() -> void:
	var vm := ScriptVM.new(_src, FlagStore.new())
	var party := BattleParty.new()
	vm.party = party
	vm._give_mon(1, 5)
	_chk("C.01 a real Pokémon lands in the party",
			party.members.size() == 1 and party.members[0].species.national_dex_num == 1)
	_chk("C.02 at the level asked for", party.members[0].level == 5)
	_chk("C.03 with full HP, like a real gift",
			party.members[0].current_hp == party.members[0].max_hp)
	_chk("C.04 and the first one becomes active",
			party.active_indices.size() == 1 and party.active_indices[0] == 0)

	# ⚠️ OUT-OF-ROSTER IS REFUSED, AND SAYS WHY. `species_id_of` covers all 1672
	# reference constants; this project implements 386.
	var vm2 := ScriptVM.new(_src, FlagStore.new())
	var p2 := BattleParty.new()
	vm2.party = p2
	vm2._give_mon(500, 5)
	_chk("C.05 a species outside the roster is refused",
			p2.members.is_empty())
	_chk("C.06 and the diagnostic names the roster, not a parse error",
			vm2.diagnostic.contains("roster"))

	# ⚠️ A FULL PARTY IS REFUSED, NOT DROPPED — there is no PC (I5-5 deferred).
	var vm3 := ScriptVM.new(_src, FlagStore.new())
	var p3 := BattleParty.new()
	for i in range(BattleParty.PARTY_SIZE):
		p3.members.append(PokemonFactory.create_battle_pokemon(1 + i, 5))
	vm3.party = p3
	vm3._give_mon(7, 5)
	_chk("C.07 a full party refuses the gift",
			p3.members.size() == BattleParty.PARTY_SIZE)
	_chk("C.08 and says so rather than failing silently",
			vm3.diagnostic.contains("full"))


## --- D. Kanto's own starter script ---
func _test_starter_script() -> void:
	if _src.ops_by_label.is_empty():
		_gated += 12
		return
	for lab in ["PalletTown_ProfessorOaksLab_EventScript_BulbasaurBall",
			"PalletTown_ProfessorOaksLab_EventScript_SquirtleBall",
			"PalletTown_ProfessorOaksLab_EventScript_ChoseStarter"]:
		_chk("D.01 the corpus carries %s" % lab.split("_")[-1],
				_src.ops_by_label.has(lab))

	var bulba := _run_starter("PalletTown_ProfessorOaksLab_EventScript_BulbasaurBall")
	_chk("D.02 picking the Bulbasaur ball sets the player's starter var",
			bulba["player_species"] == 1)
	_chk("D.03 and the rival's, to a different species",
			bulba["rival_species"] == 4 and bulba["rival_species"] != bulba["player_species"])
	_chk("D.04 the script gives a real Bulbasaur",
			bulba["party"].size() == 1
			and bulba["party"][0].species.national_dex_num == 1)
	_chk("D.05 at level 5, the level the script itself asks for",
			bulba["party"][0].level == 5)
	# ⚠️ THIS IS WHAT MAKES THE PARTY SCREEN REACHABLE IN PLAY. Nothing in
	# production set this flag before, so I5-2's browse mode was dead code.
	_chk("D.06 and sets FLAG_SYS_POKEMON_GET", bulba["pokemon_get"])
	_chk("D.07 the ball object is removed once taken",
			bulba["removed"].size() > 0)
	_chk("D.08 the script does not halt on an unknown opcode (%s)"
			% bulba["diagnostic"], not bulba["halted"])

	# ⚠️ A DIFFERENT BALL MUST GIVE A DIFFERENT POKÉMON. Without this, a starter
	# choice that always handed out Bulbasaur would pass every check above.
	var squirt := _run_starter("PalletTown_ProfessorOaksLab_EventScript_SquirtleBall")
	_chk("D.09 picking the Squirtle ball gives Squirtle, not Bulbasaur",
			squirt["party"].size() == 1
			and squirt["party"][0].species.national_dex_num == 7)
	_chk("D.10 with its own rival pairing",
			squirt["rival_species"] == 1)


## Run a ball script then the give, driving the VM the way the real scene does.
## Declines the nickname — that branch needs a naming screen, which is K-b.
func _run_starter(ball_label: String) -> Dictionary:
	var flags := FlagStore.new()
	var party := BattleParty.new()
	var vm := ScriptVM.new(_src, flags)
	vm.party = party
	var halted := false
	for label in [ball_label, "PalletTown_ProfessorOaksLab_EventScript_ChoseStarter"]:
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
				# YES to "is this the one?", NO to "nickname it?".
				vm.answer_yes_no(not str(vm.script_label).contains("ChoseStarter"))
			else:
				if vm.pause_reason == ScriptVM.Pause.UNKNOWN_OP \
						or vm.pause_reason == ScriptVM.Pause.UNRESOLVED:
					halted = true
				break
			guard += 1
	return {
		"party": party.members,
		# ⚠️ **`VAR_TEMP_2`/`VAR_TEMP_3`, NOT `PLAYER_STARTER_SPECIES`/
		# `RIVAL_STARTER_SPECIES` — AND READING THE ALIAS NAMES HERE USED TO
		# WORK, WHICH IS THE PROBLEM.** Oak's Lab declares
		# `.equ PLAYER_STARTER_SPECIES, VAR_TEMP_2` in its file preamble;
		# `gen_map_scripts.py` dropped every `.equ` line, so the alias reached
		# the VM verbatim and `setvar` created a var literally named
		# `PLAYER_STARTER_SPECIES`. Self-consistent within this one script, so
		# the scene played correctly and this test passed — by accident, against
		# a var source does not have. Now that the generator substitutes, the
		# real slot is the temp var, and reading it here is what makes this
		# assertion about the ENGINE rather than about a spelling.
		#
		# ⚠️ It also stops the test lying about temp scope: `VAR_TEMP_2` is
		# cleared on every warp and seam crossing by
		# `FlagStore.clear_temp_field_event_data`, and the alias slot never was.
		"player_species": flags.var_get("VAR_TEMP_2"),
		"rival_species": flags.var_get("VAR_TEMP_3"),
		"pokemon_get": flags.flag_get("FLAG_SYS_POKEMON_GET"),
		"removed": vm.removed_objects,
		"halted": halted,
		"diagnostic": vm.diagnostic,
	}
