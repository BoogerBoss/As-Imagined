extends Node

# M23.3 test suite — PokemonFactory (real-data-to-BattlePokemon converter).
#
# Verifies PokemonFactory.build_species()/create_battle_pokemon() against
# REAL data from PokemonRegistry (data/pokemon.json, data/learnsets.json) —
# not just "doesn't crash." Every exact-value assertion is either (a) a
# direct comparison against PokemonRegistry's own raw dict for that species,
# or (b) an independently-computed expected stat via the documented HP/stat
# formula (matching this project's own "hand-verified via Python first"
# convention), never a value read back from the same code path under test.
#
# Species used, chosen for diversity (dual/mono-type, ordinary/genderless,
# ability slots populated/empty): Bulbasaur (1, Grass/Poison), Charizard
# (6, Fire/Flying), Mewtwo (150, mono Psychic, genderless, no 2nd ability),
# Rayquaza (384, Dragon/Flying, genderless, no hidden ability).

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_section_1_species_conversion()
	_test_section_2_stat_formula_correctness()
	_test_section_3_default_moveset()
	_test_section_4_explicit_moveset_edge_cases()
	_test_section_5_ability_slots()
	_test_section_6_construction_edge_cases()
	_test_section_7_default_moveset_fallback_direct()

	var total := _pass + _fail
	print("m23_3_converter_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL: " + label)


# ── Section 1: build_species() matches PokemonRegistry's own raw data ───────

func _test_section_1_species_conversion() -> void:
	var bulbasaur := PokemonFactory.build_species(1)
	var raw_bulba: Dictionary = PokemonRegistry.get_species(1)
	_chk("S1.01 Bulbasaur species_name matches registry", bulbasaur.species_name == raw_bulba["name"])
	_chk("S1.02 Bulbasaur national_dex_num == 1", bulbasaur.national_dex_num == 1)
	_chk("S1.03 Bulbasaur base stats match registry (hp/atk/def/spa/spd/spe)",
			bulbasaur.base_hp == int(raw_bulba["base_hp"])
			and bulbasaur.base_attack == int(raw_bulba["base_atk"])
			and bulbasaur.base_defense == int(raw_bulba["base_def"])
			and bulbasaur.base_sp_attack == int(raw_bulba["base_spa"])
			and bulbasaur.base_sp_defense == int(raw_bulba["base_spd"])
			and bulbasaur.base_speed == int(raw_bulba["base_spe"]))
	_chk("S1.04 Bulbasaur types == [GRASS, POISON] (dual-type, no dedup needed)",
			bulbasaur.types == [TypeChart.TYPE_GRASS, TypeChart.TYPE_POISON])
	_chk("S1.05 Bulbasaur abilities == [Overgrow(65), None(0), Chlorophyll(34)]",
			bulbasaur.abilities == [65, 0, 34])
	_chk("S1.06 Bulbasaur gender_ratio/catch_rate/exp_yield/weight match registry",
			bulbasaur.gender_ratio == int(raw_bulba["gender_ratio"])
			and bulbasaur.catch_rate == int(raw_bulba["catch_rate"])
			and bulbasaur.exp_yield == int(raw_bulba["exp_yield"])
			and bulbasaur.weight == int(raw_bulba["weight"]))
	_chk("S1.07 Bulbasaur ev_yield_spa == 1 (matches registry, all others 0)",
			bulbasaur.ev_yield_spa == 1 and bulbasaur.ev_yield_hp == 0
			and bulbasaur.ev_yield_atk == 0 and bulbasaur.ev_yield_def == 0
			and bulbasaur.ev_yield_spd == 0 and bulbasaur.ev_yield_spe == 0)
	_chk("S1.08 Bulbasaur egg_groups == [1, 7] (matches registry)",
			bulbasaur.egg_groups == [1, 7])
	_chk("S1.09 Bulbasaur learnset populated from registry (11 entries, first is level 1 Tackle)",
			bulbasaur.learnset.size() == 11
			and int(bulbasaur.learnset[0]["level"]) == 1
			and int(bulbasaur.learnset[0]["move_id"]) == 33)

	# Charizard — dual-type Fire/Flying, real hidden ability.
	var charizard := PokemonFactory.build_species(6)
	_chk("S1.10 Charizard types == [FIRE, FLYING]",
			charizard.types == [TypeChart.TYPE_FIRE, TypeChart.TYPE_FLYING])
	_chk("S1.11 Charizard abilities == [Blaze(66), None(0), Solar Power(94)]",
			charizard.abilities == [66, 0, 94])

	# Mewtwo — mono-typed in the source data as [PSYCHIC, PSYCHIC] (a real-data
	# quirk, not [PSYCHIC, TYPE_NONE]) — confirms the de-duplication actually ran,
	# not just that a dual-type species happened to look right.
	var mewtwo := PokemonFactory.build_species(150)
	_chk("S1.12 Mewtwo types == [PSYCHIC] exactly (de-duplicated from raw [15, 15], NOT left as a duplicate pair)",
			mewtwo.types == [TypeChart.TYPE_PSYCHIC] and mewtwo.types.size() == 1)
	_chk("S1.13 Mewtwo gender_ratio == 255 (genderless)", mewtwo.gender_ratio == 255)
	_chk("S1.14 Mewtwo abilities == [Pressure(46), None(0), Unnerve(127)]",
			mewtwo.abilities == [46, 0, 127])

	# Rayquaza — genderless legendary with NO hidden ability at all (ability_h=0),
	# a real edge case (species with an empty 3rd ability slot).
	var rayquaza := PokemonFactory.build_species(384)
	_chk("S1.15 Rayquaza types == [DRAGON, FLYING]",
			rayquaza.types == [TypeChart.TYPE_DRAGON, TypeChart.TYPE_FLYING])
	_chk("S1.16 Rayquaza abilities == [Air Lock(76), None(0), None(0)] (no hidden ability)",
			rayquaza.abilities == [76, 0, 0])

	# Invalid dex — build_species must return null, not a bogus zero-stat species.
	_chk("S1.17 build_species(9999) returns null for a nonexistent dex",
			PokemonFactory.build_species(9999) == null)


# ── Section 2: stat-formula correctness (independently computed, not read back) ─

func _test_section_2_stat_formula_correctness() -> void:
	var zero_ivs: Array = [0, 0, 0, 0, 0, 0]

	# Bulbasaur level 50, IV=0, EV=0, neutral nature — hand-computed via the
	# documented Gen III+ formula (floor((2*base+iv+floor(ev/4))*level/100)+5,
	# HP adds +level+10 instead of +5), independently in this test, not via
	# any BattlePokemon internals.
	var bulba := PokemonFactory.create_battle_pokemon(
			1, 50, [], BattlePokemon.NATURE_HARDY, zero_ivs)
	_chk("S2.01 Bulbasaur L50 max_hp == 105 (floor(90*0.5)+60)", bulba.max_hp == 105)
	_chk("S2.02 Bulbasaur L50 attack == 54",     bulba.attack == 54)
	_chk("S2.03 Bulbasaur L50 defense == 54",    bulba.defense == 54)
	_chk("S2.04 Bulbasaur L50 sp_attack == 70",  bulba.sp_attack == 70)
	_chk("S2.05 Bulbasaur L50 sp_defense == 70", bulba.sp_defense == 70)
	_chk("S2.06 Bulbasaur L50 speed == 50",      bulba.speed == 50)
	_chk("S2.07 Bulbasaur L50 current_hp == max_hp (freshly built, full HP)",
			bulba.current_hp == bulba.max_hp)

	# Charizard level 36, IV=0, EV=0, neutral nature.
	var charizard := PokemonFactory.create_battle_pokemon(
			6, 36, [], BattlePokemon.NATURE_HARDY, zero_ivs)
	_chk("S2.08 Charizard L36 max_hp == 102",   charizard.max_hp == 102)
	_chk("S2.09 Charizard L36 attack == 65",    charizard.attack == 65)
	_chk("S2.10 Charizard L36 defense == 61",   charizard.defense == 61)
	_chk("S2.11 Charizard L36 sp_attack == 83", charizard.sp_attack == 83)
	_chk("S2.12 Charizard L36 sp_defense == 66", charizard.sp_defense == 66)
	_chk("S2.13 Charizard L36 speed == 77",     charizard.speed == 77)

	# forced_nature/forced_ivs actually reached the constructed instance
	# (not silently dropped somewhere in the pipeline).
	_chk("S2.14 Bulbasaur's nature is the forced NATURE_HARDY", bulba.nature == BattlePokemon.NATURE_HARDY)
	_chk("S2.15 Bulbasaur's IVs are all forced to 0", bulba.ivs == [0, 0, 0, 0, 0, 0])

	# EVs: from_species itself always zeroes EVs; PokemonFactory applies them
	# as a real second pass that measurably changes the computed stat.
	var full_atk_evs: Array = [0, 252, 0, 0, 0, 0]
	var bulba_evs := PokemonFactory.create_battle_pokemon(
			1, 50, [], BattlePokemon.NATURE_HARDY, zero_ivs, null, full_atk_evs)
	# floor(ev/4)=63 is added INSIDE the pre-level-scaling term, not after —
	# floor((2*49+0+63)*50/100)+5 = floor(161*0.5)+5 = 80+5 = 85, hand-
	# verified via Python before writing this assertion (NOT 54+63=117, a
	# mistake this test caught on its own first run before being fixed).
	_chk("S2.16 252 Atk EVs raise Bulbasaur's attack stat to 85 (floor((98+63)*0.5)+5)",
			bulba_evs.attack == 85)
	_chk("S2.17 EVs don't affect an unrelated stat (defense unchanged at 54)",
			bulba_evs.defense == 54)
	_chk("S2.18 current_hp re-maxed after the EV-driven stat recalculation",
			bulba_evs.current_hp == bulba_evs.max_hp)

	# Malformed EVs array (wrong size) is ignored, not crashed on.
	var bulba_bad_evs := PokemonFactory.create_battle_pokemon(
			1, 50, [], BattlePokemon.NATURE_HARDY, zero_ivs, null, [1, 2, 3])
	_chk("S2.19 malformed (wrong-size) EVs array is ignored, stats stay at the zero-EV baseline",
			bulba_bad_evs.attack == 54 and bulba_bad_evs.evs == [0, 0, 0, 0, 0, 0])


# ── Section 3: default (auto-derived) moveset from the real learnset ────────

func _test_section_3_default_moveset() -> void:
	# Bulbasaur's real learnset (verified against data/learnsets.json directly):
	# L1 Tackle(33), L4 Growl(45), L7 Leech Seed(73), L10 Vine Whip(22),
	# L15 Poison Powder(77) + Sleep Powder(79), L20 Razor Leaf(75),
	# L25 Sweet Scent(230), L32 Growth(74), L39 Synthesis(235), L46 Solar Beam(76).

	# [Edge case] fewer than 4 moves learnable at the target level: level 1
	# only has Tackle — a real Pokémon with exactly 1 move.
	var bulba_l1 := PokemonFactory.create_battle_pokemon(1, 1)
	_chk("S3.01 Bulbasaur L1 has exactly 1 move (Tackle) — fewer than 4 is handled cleanly",
			bulba_l1.moves.size() == 1 and bulba_l1.moves[0].move_name == "Tackle")

	# Level 20: 7 moves eligible (L1-L20), last 4 in ascending order are
	# Vine Whip(10), Poison Powder(15), Sleep Powder(15), Razor Leaf(20).
	var bulba_l20 := PokemonFactory.create_battle_pokemon(1, 20)
	_chk("S3.02 Bulbasaur L20 has 4 moves", bulba_l20.moves.size() == 4)
	var l20_names: Array = []
	for m in bulba_l20.moves:
		l20_names.append(m.move_name)
	_chk("S3.03 Bulbasaur L20's moveset is the last 4 learnable-by-then moves, in learn order " +
			"(Vine Whip, Poison Powder, Sleep Powder, Razor Leaf), not an arbitrary subset",
			l20_names == ["Vine Whip", "Poison Powder", "Sleep Powder", "Razor Leaf"])

	# Level 100: still capped at 4 moves even though far more are learnable by then.
	var bulba_l100 := PokemonFactory.create_battle_pokemon(1, 100)
	_chk("S3.04 Bulbasaur L100 still capped at 4 moves (not all 11 learnset entries)",
			bulba_l100.moves.size() == 4)


# ── Section 4: explicit moveset — validation and edge cases ─────────────────

func _test_section_4_explicit_moveset_edge_cases() -> void:
	# Valid explicit moveset overrides the auto-derived default entirely.
	# 94=Psychic, 85=Thunderbolt, 53=Flamethrower (real move IDs, confirmed
	# individually against each move's own .tres move_name field).
	var mewtwo := PokemonFactory.create_battle_pokemon(150, 70, [94, 85, 53])
	_chk("S4.01 explicit valid moveset used verbatim (3 moves, in the requested order)",
			mewtwo.moves.size() == 3
			and mewtwo.moves[0].move_name == "Psychic"
			and mewtwo.moves[1].move_name == "Thunderbolt"
			and mewtwo.moves[2].move_name == "Flamethrower")

	# [Edge case] an invalid/unimplemented move ID mixed into an explicit
	# request is skipped, not fatal to the whole construction.
	var with_invalid := PokemonFactory.create_battle_pokemon(150, 70, [94, 999999, 85])
	_chk("S4.02 an invalid move ID (999999) is silently skipped, leaving the 2 valid moves",
			with_invalid.moves.size() == 2
			and with_invalid.moves[0].move_name == "Psychic"
			and with_invalid.moves[1].move_name == "Thunderbolt")

	# [Edge case] more than 4 valid move IDs — only the first 4 are used.
	# 94=Psychic, 85=Thunderbolt, 53=Flamethrower, 15=Cut, 17=Wing Attack.
	var too_many := PokemonFactory.create_battle_pokemon(150, 70, [94, 85, 53, 15, 17])
	var too_many_names: Array = []
	for m in too_many.moves:
		too_many_names.append(m.move_name)
	_chk("S4.03 more than 4 requested moves: only the first 4 are used, the 5th (Wing Attack) dropped",
			too_many.moves.size() == 4
			and too_many_names == ["Psychic", "Thunderbolt", "Flamethrower", "Cut"])

	# [Edge case] a duplicate move ID in the request isn't added twice.
	var with_dupe := PokemonFactory.create_battle_pokemon(150, 70, [94, 94, 85])
	_chk("S4.04 a duplicate move ID in the request is not added twice (2 unique moves, not 3)",
			with_dupe.moves.size() == 2)

	# Empty explicit array still falls through to the auto-derived default
	# (this is exactly what Section 3 already exercises via the default
	# parameter — confirmed here that passing [] explicitly is equivalent).
	var explicit_empty := PokemonFactory.create_battle_pokemon(1, 1, [])
	_chk("S4.05 an explicitly-empty move_ids array falls through to the auto-derived default",
			explicit_empty.moves.size() == 1 and explicit_empty.moves[0].move_name == "Tackle")


# ── Section 5: ability-slot resolution ───────────────────────────────────────

func _test_section_5_ability_slots() -> void:
	var charizard_primary := PokemonFactory.create_battle_pokemon(
			6, 36, [], null, null, null, null, PokemonFactory.ABILITY_SLOT_PRIMARY)
	_chk("S5.01 Charizard's primary ability slot resolves to a real Blaze AbilityData",
			charizard_primary.ability != null and charizard_primary.ability.ability_name == "Blaze")

	var charizard_hidden := PokemonFactory.create_battle_pokemon(
			6, 36, [], null, null, null, null, PokemonFactory.ABILITY_SLOT_HIDDEN)
	_chk("S5.02 Charizard's hidden ability slot resolves to a real Solar Power AbilityData",
			charizard_hidden.ability != null and charizard_hidden.ability.ability_name == "Solar Power")

	# [Edge case] Rayquaza's secondary slot is 0 ("None") — must leave
	# BattlePokemon.ability at null, matching the project-wide "no ability"
	# convention, NOT resolve to data/abilities/ability_0000.tres's own
	# real "None" placeholder Resource.
	var rayquaza_secondary := PokemonFactory.create_battle_pokemon(
			384, 70, [], null, null, null, null, PokemonFactory.ABILITY_SLOT_SECONDARY)
	_chk("S5.03 Rayquaza's empty secondary ability slot (id=0) leaves .ability == null",
			rayquaza_secondary.ability == null)

	# [Edge case] Rayquaza's hidden slot is ALSO 0 — same result.
	var rayquaza_hidden := PokemonFactory.create_battle_pokemon(
			384, 70, [], null, null, null, null, PokemonFactory.ABILITY_SLOT_HIDDEN)
	_chk("S5.04 Rayquaza's empty hidden ability slot (id=0) also leaves .ability == null",
			rayquaza_hidden.ability == null)

	# [Edge case] an out-of-range ability_slot index doesn't crash and leaves ability null.
	var out_of_range_slot := PokemonFactory.create_battle_pokemon(6, 36, [], null, null, null, null, 5)
	_chk("S5.05 an out-of-range ability_slot index leaves .ability == null without crashing",
			out_of_range_slot.ability == null)


# ── Section 6: construction-level edge cases ─────────────────────────────────

func _test_section_6_construction_edge_cases() -> void:
	_chk("S6.01 create_battle_pokemon returns null for a nonexistent dex",
			PokemonFactory.create_battle_pokemon(9999, 50) == null)

	var too_high := PokemonFactory.create_battle_pokemon(25, 250)
	_chk("S6.02 level 250 is clamped to 100", too_high.level == 100)

	var too_low := PokemonFactory.create_battle_pokemon(25, -5)
	_chk("S6.03 level -5 is clamped to 1", too_low.level == 1)

	var zero_level := PokemonFactory.create_battle_pokemon(25, 0)
	_chk("S6.04 level 0 is clamped to 1", zero_level.level == 1)

	var exact_bounds := PokemonFactory.create_battle_pokemon(25, 100)
	_chk("S6.05 level exactly 100 (the upper bound) is left unclamped", exact_bounds.level == 100)


# ── Section 7: _default_moveset's defensive zero-eligible-moves fallback ────
# [Edge case] every one of this project's 386 species has a real level-1
# learnset entry (confirmed via a full-dataset scan before writing this
# test) — the "zero moves eligible at this level" branch is therefore
# UNREACHABLE via create_battle_pokemon at any valid level (1-100). Tested
# directly against the underlying helper with an artificial sub-1 level, to
# confirm the fallback logic itself is correct rather than leaving it
# entirely unverified.

func _test_section_7_default_moveset_fallback_direct() -> void:
	var fallback_ids: Array[int] = PokemonFactory._default_moveset(1, 0)
	_chk("S7.01 _default_moveset falls back to the single lowest-level entry " +
			"(Bulbasaur's level-1 Tackle) when nothing is eligible at the requested level",
			fallback_ids == [33])
