extends Node

# [M20a] Data-completeness check for exp_yield/ev_yield_* — NOT a battle-logic
# test (no BattleManager involved at all), matching item_registry_test.gd's
# Section 1 convention of one assertion per catalog entry. Confirms
# scripts/gen_exp_ev_yield_data.py's own regeneration actually landed real,
# in-range values for all 386 species in data/pokemon.json, independent of
# the generator's own internal validation (which only runs when the script
# is explicitly re-invoked, not on every future load of the JSON itself).
#
# Full source citations for the extraction itself (struct field names,
# ternary/named-macro resolution against this project's real GEN_9 config,
# Unown's UNOWN_MISC_INFO special case) live in
# scripts/gen_exp_ev_yield_data.py's own module docstring and
# docs/decisions.md's `[M20a]` entry — not repeated here.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_all_386_species_have_valid_yields()

	var total := _pass + _fail
	print("m20a_data_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


func _test_all_386_species_have_valid_yields() -> void:
	var all_species: Array = PokemonRegistry.get_all_species()
	_chk("A.0 PokemonRegistry reports exactly 386 species", all_species.size() == 386)

	for entry: Dictionary in all_species:
		var dex: int = entry.get("dex", -1)
		var name: String = entry.get("name", "?")
		var exp_yield: int = entry.get("exp_yield", -1)
		var ev_fields := ["ev_yield_hp", "ev_yield_atk", "ev_yield_def",
				"ev_yield_spa", "ev_yield_spd", "ev_yield_spe"]
		var ev_ok := true
		for f in ev_fields:
			var v: int = entry.get(f, -1)
			if v < 0 or v > 3:
				ev_ok = false
		_chk("Dex %d (%s): exp_yield > 0 (%d) and all 6 ev_yield_* in [0,3]" % [dex, name, exp_yield],
				exp_yield > 0 and ev_ok)
