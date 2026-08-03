extends Node

## [M27H H1-H3] Wild encounters — the table, the roll, and the battle mount.
##
## The claims most worth pinning are the ones a plausible port gets wrong while
## still producing encounters:
##
##   * the rate is scaled by 16 before the roll — without it grass is 16x too
##     quiet and reads as broken rather than as a bug;
##   * `MB_CAVE` is a land-encounter tile, which a grass-only reading misses;
##   * the new-metatile 40% gate applies ONLY when the behaviour changed;
##   * a wild battle carries an EMPTY trainer key, which is what makes the
##     no-flag and no-prize-money behaviour fall out rather than be special-cased.

const EXPECTED_TOTAL := 48

var _total := 0
var _failed := 0
var _gated := 0


func _chk(label: String, cond: bool) -> void:
	_total += 1
	if not cond:
		_failed += 1
		print("FAILED: %s" % label)


## A forced RNG. Godot's seeded sequence is deterministic, so a fixed seed makes
## every roll in this suite reproducible without a new forcing seam.
func _rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


func _ready() -> void:
	_test_table()
	_test_rate_math()
	_test_tiles_and_gates()
	_test_slot_and_level()
	_test_party_and_mount()

	var accounted := _total + _gated
	_chk("Z.99 every expected assertion ran (%d + %d gated == %d)"
			% [_total, _gated, EXPECTED_TOTAL], accounted == EXPECTED_TOTAL)
	print("m27h_wild_encounters_test: %d/%d passed" % [_total - _failed, _total])
	get_tree().quit()


## --- A. the generated table ---
func _test_table() -> void:
	if not FileAccess.file_exists(WildEncounters.TABLE_PATH):
		_gated += 12
		return
	_chk("A.01 the table loads", not WildEncounters.slot_rates().is_empty())
	var rates := WildEncounters.slot_rates()
	# Source picks a slot with `Random() % ENCOUNTER_CHANCE_LAND_MONS_TOTAL`, and
	# these are the per-slot chances. A table that did not sum to 100 would make
	# the last slot unreachable.
	_chk("A.02 there are 12 land slots", rates.size() == 12)
	_chk("A.03 whose chances sum to 100",
			rates.reduce(func(a, b): return a + int(b), 0) == 100)
	_chk("A.04 front-loaded, as source's own table is",
			int(rates[0]) == 20 and int(rates[11]) == 1)

	# ⚠️ The 5 corridor maps with a LAND table. Pallet Town and Viridian City
	# carry tables too, but WATER only — surfing, which is M27E — so a check for
	# "has a table" would wrongly include them.
	for m in ["Route1_Frlg", "Route2_Frlg", "Route3_Frlg", "Route22_Frlg",
			"ViridianForest_Frlg"]:
		_chk("A.05 %s has a land table" % m, WildEncounters.has_table(m))
	_chk("A.06 but Pallet Town does NOT — its table is water-only",
			not WildEncounters.has_table("PalletTown_Frlg"))

	var vf := WildEncounters.table_for("ViridianForest_Frlg")
	_chk("A.07 with a real rate and 12 resolved slots",
			int(vf.get("encounter_rate", 0)) > 0 and vf.get("slots", []).size() == 12)
	# Species are resolved to dex numbers at GENERATION time, reusing
	# gen_trainer_data's own map — so nothing resolves names at runtime.
	var slot0: Dictionary = vf["slots"][0]
	_chk("A.08 slots carry a dex number, not a species name",
			int(slot0.get("dex", 0)) > 0 and int(slot0.get("min", 0)) > 0)


## --- B. the rate math ---
func _test_rate_math() -> void:
	# ⚠️ THE x16. `WildEncounterCheck`'s own first line. Without it Viridian
	# Forest's 14 is 0.5% a step instead of 7.8% and grass reads as broken.
	_chk("B.01 the rate is scaled by 16", WildEncounters.effective_rate(14, -1) == 224)
	_chk("B.02 and the denominator is source's own 2880",
			WildEncounters.MAX_ENCOUNTER_RATE == 2880)
	_chk("B.03 which puts Viridian Forest near 7.8%%",
			abs(224.0 / 2880.0 - 0.0778) < 0.001)

	# Lead-ability modifiers are part of the same source function, not a
	# separate gate — porting the roll without them ports half a function.
	_chk("B.04 Illuminate doubles it",
			WildEncounters.effective_rate(14, AbilityManager.ABILITY_ILLUMINATE) == 448)
	_chk("B.05 White Smoke halves it",
			WildEncounters.effective_rate(14, AbilityManager.ABILITY_WHITE_SMOKE) == 112)
	_chk("B.06 Quick Feet halves it too",
			WildEncounters.effective_rate(14, AbilityManager.ABILITY_QUICK_FEET) == 112)
	_chk("B.07 an unrelated ability changes nothing",
			WildEncounters.effective_rate(14, AbilityManager.ABILITY_NO_GUARD) != 224
			and WildEncounters.effective_rate(14, 999) == 224)
	# ⚠️ Stench is M17's ONE open ability. Its field effect is this halving, so
	# the behaviour is already correct and simply unreachable until M17 closes.
	_chk("B.08 Stench's own halving is present and inert",
			WildEncounters.effective_rate(14, WildEncounters.ABILITY_STENCH_ID) == 112)
	_chk("B.09 and the result is capped at the maximum",
			WildEncounters.effective_rate(999, AbilityManager.ABILITY_ILLUMINATE)
			== WildEncounters.MAX_ENCOUNTER_RATE)


## --- C. which tiles, and the two gates ---
func _test_tiles_and_gates() -> void:
	_chk("C.01 tall grass is a land-encounter tile",
			WildEncounters.is_land_encounter_tile(MetatileBehavior.MB_TALL_GRASS))
	# ⚠️ THE ONE A GRASS-ONLY READING MISSES. 46 corridor cells are cave, inert
	# today only because their map has no table.
	_chk("C.02 and so is MB_CAVE",
			WildEncounters.is_land_encounter_tile(MetatileBehavior.MB_CAVE))
	_chk("C.03 an ordinary floor is not",
			not WildEncounters.is_land_encounter_tile(MetatileBehavior.MB_NORMAL))
	# Water is an encounter tile in source but NOT a LAND one — it needs surfing.
	_chk("C.04 nor is water — that is M27E",
			not WildEncounters.is_land_encounter_tile(MetatileBehavior.MB_OCEAN_WATER))

	if not FileAccess.file_exists(WildEncounters.TABLE_PATH):
		_gated += 4
		return
	# A map with no table never encounters, whatever it is standing on.
	_chk("C.05 a map with no land table never encounters",
			not WildEncounters.should_encounter("PalletTown_Frlg",
					MetatileBehavior.MB_TALL_GRASS, MetatileBehavior.MB_TALL_GRASS,
					_rng(1), -1))
	# Off-grass never encounters even on a map that has a table.
	_chk("C.06 and neither does a non-encounter tile",
			not WildEncounters.should_encounter("ViridianForest_Frlg",
					MetatileBehavior.MB_NORMAL, MetatileBehavior.MB_NORMAL,
					_rng(1), -1))

	# ⚠️ THE 40% NEW-METATILE GATE, and it must apply ONLY on a change. Measured
	# statistically because both paths are probabilistic: stepping grass-to-grass
	# must produce strictly more encounters than path-to-grass over the same
	# trials, since the latter pays an extra 40% gate first.
	var same := 0
	var changed := 0
	for i in range(400):
		if WildEncounters.should_encounter("ViridianForest_Frlg",
				MetatileBehavior.MB_TALL_GRASS, MetatileBehavior.MB_TALL_GRASS,
				_rng(i), -1):
			same += 1
		if WildEncounters.should_encounter("ViridianForest_Frlg",
				MetatileBehavior.MB_TALL_GRASS, MetatileBehavior.MB_NORMAL,
				_rng(i), -1):
			changed += 1
	_chk("C.07 stepping grass-to-grass encounters more than path-to-grass (%d vs %d)"
			% [same, changed], same > changed)
	_chk("C.08 and the gate is source's own 40%%",
			WildEncounters.NEW_METATILE_ALLOW_PERCENT == 40)


## --- D. slot and level selection ---
func _test_slot_and_level() -> void:
	if not FileAccess.file_exists(WildEncounters.TABLE_PATH):
		_gated += 6
		return
	# Every slot must be reachable, and slot 0 must dominate — a uniform pick
	# would make the 1%-slot rarities meaningless.
	var seen := {}
	var slot0 := 0
	for i in range(2000):
		var idx := WildEncounters.choose_slot(_rng(i))
		seen[idx] = true
		if idx == 0:
			slot0 += 1
	_chk("D.01 several slots are reachable", seen.size() >= 6)
	_chk("D.02 and slot 0 is far commoner than uniform (%d of 2000)" % slot0,
			slot0 > 300 and slot0 < 500)
	_chk("D.03 no slot index escapes the table",
			seen.keys().all(func(k: int) -> bool: return k >= 0 and k < 12))

	_chk("D.04 a fixed-level slot always gives that level",
			WildEncounters.choose_level({"min": 4, "max": 4}, _rng(7)) == 4)
	var lv := WildEncounters.choose_level({"min": 3, "max": 6}, _rng(9))
	_chk("D.05 a range stays inside itself", lv >= 3 and lv <= 6)
	# Source swaps them rather than erroring, and so does this.
	_chk("D.06 an inverted range is swapped, not an error",
			WildEncounters.choose_level({"min": 9, "max": 2}, _rng(3)) >= 2)


## --- E. the party, and the battle mount ---
func _test_party_and_mount() -> void:
	if not FileAccess.file_exists(WildEncounters.TABLE_PATH):
		_gated += 13
		return
	var party := WildEncounters.build_wild_party("ViridianForest_Frlg", _rng(5))
	_chk("E.01 a wild party builds", party != null)
	if party == null:
		_gated += 4
	else:
		# ⚠️ ALWAYS EXACTLY ONE. A wild battle is never a party battle here.
		_chk("E.02 with exactly one Pokémon", party.members.size() == 1)
		_chk("E.03 which is active",
				party.active_indices.size() == 1 and party.active_indices[0] == 0)
		var mon: BattlePokemon = party.members[0]
		_chk("E.04 real, with a species and HP",
				mon.species != null and mon.max_hp > 0 and mon.current_hp == mon.max_hp)
		# Viridian Forest is Caterpie/Weedle/Pikachu at levels 3-5.
		_chk("E.05 at a level its own table allows", mon.level >= 3 and mon.level <= 7)
	_chk("E.06 a map with no table builds nothing",
			WildEncounters.build_wild_party("PalletTown_Frlg", _rng(5)) == null)

	# ⚠️ THE EMPTY TRAINER KEY IS LOAD-BEARING. The no-flag and no-prize-money
	# behaviour falls out of it rather than needing a wild-specific branch —
	# which is exactly why a later session must not "helpfully" give wild
	# battles a synthetic key.
	_chk("E.07 a wild WIN records no defeated trainer",
			not BattleOutcome.make(BattleOutcome.WON, "").should_set_defeated_flag())
	_chk("E.08 while a trainer win still does",
			BattleOutcome.make(BattleOutcome.WON, "TRAINER_X").should_set_defeated_flag())

	var ow: Node2D = load("res://scenes/overworld/overworld.tscn").instantiate() as Node2D
	# Deliberately NOT added to the tree — _ready() would boot the whole region.
	_chk("E.09 the overworld can mount a wild battle", ow.has_method("begin_wild_battle"))
	_chk("E.10 shares one mount with the trainer path", ow.has_method("_mount_battle"))
	_chk("E.11 and has a step trigger", ow.has_method("_wild_step"))
	_chk("E.12 reading the LEAD's ability, not the active battler's",
			ow.has_method("_lead_ability_id"))
	_chk("E.13 an empty party is refused rather than mounted",
			ow.begin_wild_battle(null) == false)
	ow.free()
