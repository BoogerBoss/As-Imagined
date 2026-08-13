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

const EXPECTED_TOTAL := 91

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
	_test_converter_rulings()
	_test_stamp_trigger()
	_test_authored_layer()

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
	# [Widened 2026-08-04, Rob's own design call — see gen_wild_encounters.py's
	# LAND_SLOT_RATES comment.] 15 slots, not source's own 12.
	_chk("A.02 there are 15 land slots", rates.size() == 15)
	_chk("A.03 whose chances sum to 100",
			rates.reduce(func(a, b): return a + int(b), 0) == 100)
	_chk("A.04 front-loaded, matching this project's own widened table",
			int(rates[0]) == 15 and int(rates[14]) == 1)

	# ⚠️ The 5 corridor maps with a LAND table. Pallet Town and Viridian City
	# carry tables too, but WATER only — surfing, which is M27E — so a check for
	# "has a table" would wrongly include them.
	for m in ["Route1_Frlg", "Route2_Frlg", "Route3_Frlg", "Route22_Frlg",
			"ViridianForest_Frlg"]:
		_chk("A.05 %s has a land table" % m, WildEncounters.has_table(m))
	_chk("A.06 but Pallet Town does NOT — its table is water-only",
			not WildEncounters.has_table("PalletTown_Frlg"))

	var vf := WildEncounters.table_for("ViridianForest_Frlg")
	_chk("A.07 with a real rate and 15 resolved slots",
			int(vf.get("encounter_rate", 0)) > 0 and vf.get("slots", []).size() == 15)
	# Species are resolved to dex numbers at GENERATION time, reusing
	# gen_trainer_data's own map — so nothing resolves names at runtime.
	var slot0: Dictionary = vf["slots"][0]
	_chk("A.08 slots carry a dex number, not a species name",
			int(slot0.get("dex", 0)) > 0 and int(slot0.get("min", 0)) > 0)


## --- B. the rate math ---
func _test_rate_math() -> void:
	# ⚠️ THE x16. `WildEncounterCheck`'s own first line. Without it Viridian
	# Forest's 14 is 0.875% a step instead of 14% and grass reads as broken.
	_chk("B.01 the rate is scaled by 16", WildEncounters.effective_rate(14, -1) == 224)
	# ⚠️ FIRE RED'S DENOMINATOR, NOT EMERALD'S — Rob's call, 2026-08-12. The
	# rate VALUES are Fire Red's, so running them against Emerald's 2880 halved
	# encounter frequency everywhere. Asserted against 2880 too, so a revert to
	# the old constant fails here loudly rather than just making grass quiet.
	_chk("B.02 the denominator is Fire Red's 1600, not Emerald's 2880",
			WildEncounters.MAX_ENCOUNTER_RATE == 1600
			and WildEncounters.MAX_ENCOUNTER_RATE != 2880)
	_chk("B.03 which puts Viridian Forest at 14%% a step, not 7.8%%",
			abs(224.0 / float(WildEncounters.MAX_ENCOUNTER_RATE) - 0.14) < 0.001)

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
	# [M27T piece 4] `should_encounter` now takes the resolved encounter TYPE —
	# the stamp — alongside the behaviour, which it still needs for the gate
	# below. These cases care about the gates rather than about where the type
	# came from, so they derive it the way an unstamped cell would.
	const LAND := MapManager.EncounterType.LAND
	const NONE := MapManager.EncounterType.NONE
	# A map with no table never encounters, whatever it is standing on.
	_chk("C.05 a map with no land table never encounters",
			not WildEncounters.should_encounter("PalletTown_Frlg", LAND,
					MetatileBehavior.MB_TALL_GRASS, MetatileBehavior.MB_TALL_GRASS,
					_rng(1), -1))
	# Off-grass never encounters even on a map that has a table.
	_chk("C.06 and neither does a non-encounter tile",
			not WildEncounters.should_encounter("ViridianForest_Frlg", NONE,
					MetatileBehavior.MB_NORMAL, MetatileBehavior.MB_NORMAL,
					_rng(1), -1))

	# ⚠️ THE 40% NEW-METATILE GATE, and it must apply ONLY on a change. Measured
	# statistically because both paths are probabilistic: stepping grass-to-grass
	# must produce strictly more encounters than path-to-grass over the same
	# trials, since the latter pays an extra 40% gate first.
	var same := 0
	var changed := 0
	for i in range(400):
		if WildEncounters.should_encounter("ViridianForest_Frlg", LAND,
				MetatileBehavior.MB_TALL_GRASS, MetatileBehavior.MB_TALL_GRASS,
				_rng(i), -1):
			same += 1
		if WildEncounters.should_encounter("ViridianForest_Frlg", LAND,
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
	# [Widened 2026-08-04.] Slot 0's own share dropped from source's 20% to this
	# project's own 15% (expected ~300 of 2000); band widened accordingly, still
	# well clear of the ~133 a uniform 15-slot pick would give.
	_chk("D.02 and slot 0 is far commoner than uniform (%d of 2000)" % slot0,
			slot0 > 200 and slot0 < 400)
	_chk("D.03 no slot index escapes the table",
			seen.keys().all(func(k: int) -> bool: return k >= 0 and k < 15))

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

	# --- [M27E follow-up] the black-screen guard ---
	#
	# ⚠️ **E.13 ABOVE GUARDS THE OPPONENT PARTY. NOTHING GUARDED THE PLAYER'S**,
	# and that is the entire defect: `begin_wild_battle` returned TRUE with a
	# 0-member player party, the overlay mounted, and `BattleManager` threw
	# `Out of bounds get index '0'` on the active slot — an unrecoverable black
	# screen. Reported from play, reproduced headlessly. The two guards read
	# almost identically and protect opposite sides; keeping them adjacent is
	# deliberate so the asymmetry cannot come back unnoticed.
	var opp := BattleParty.new()
	opp.members.append(PokemonFactory.create_battle_pokemon(16, 5, []))
	opp.active_indices = [0]

	OverworldSession.reset()          # empty party — a debug boot, or pre-Oak
	_chk("E.14 a real opponent is STILL refused when the player has no party",
			ow.begin_wild_battle(opp) == false)
	_chk("E.15 and nothing was mounted: no battle, no pending trainer key",
			not ow._in_battle and OverworldSession.pending_trainer_key == "")

	# ⚠️ THE DISCRIMINATOR. Without it this section cannot tell "refuses when it
	# should" from "refuses always", which is the failure mode a guard placed
	# one line too high would produce.
	OverworldSession.party = OverworldParty.build_debug_player_party()
	_chk("E.16 whereas a real party is accepted — the guard is not a blanket no",
			ow._party_can_battle())

	# An ALL-FAINTED party is a different origin with the same consequence.
	# Unreachable in correct play (a wipe whites you out), but a guard that
	# trusted that would be trusting the thing that already broke once.
	for m: BattlePokemon in OverworldSession.party.members:
		m.fainted = true
	_chk("E.17 an all-fainted party is refused too, not just an empty one",
			not ow._party_can_battle())
	# --- [M27H H5 fix] the battle must know it is WILD ---
	#
	# ⚠️ **REPORTED FROM PLAY AS "RUNNING FROM A WILD BATTLE SENDS ME TO THE HEAL
	# SPOT".** `try_flee` refuses outright unless `is_wild_battle`
	# (`battle_manager.gd:411`), so Run never rolled — it fell through to
	# FORFEITED, which `IsPlayerDefeated` counts as a defeat, which whites the
	# player out and charges the payout.
	#
	# The screen derived `is_wild_battle` from two signals that were BOTH read
	# after `BattleSetupContext.clear()` had already reset them: `opp_trainer_key
	# == ""` was vacuously true for every battle, and the other half vacuously
	# false. The context is now captured before the clear, and the overworld
	# marks its own battles explicitly. This asserts the half the overworld owns
	# — the flag is still set when the screen goes to read it.
	OverworldSession.party = OverworldParty.build_debug_player_party()
	BattleSetupContext.clear()
	var wild := BattleParty.new()
	wild.members.append(PokemonFactory.create_battle_pokemon(16, 5, []))
	wild.active_indices = [0]
	ow.begin_wild_battle(wild)
	_chk("E.18 a wild battle marks the context as an OVERWORLD battle",
			BattleSetupContext.is_overworld_battle)
	_chk("E.19 with an empty trainer key, which is what makes it WILD rather"
			+ " than merely from the overworld",
			BattleSetupContext.opp_trainer_key == "")
	# ⚠️ THE DISCRIMINATOR. Without it this cannot tell "marks overworld
	# battles" from "is simply always true" — which is exactly the shape of the
	# bug it replaces, a condition that read the same for every battle.
	BattleSetupContext.clear()
	_chk("E.20 and a cleared context does NOT claim to be an overworld battle",
			not BattleSetupContext.is_overworld_battle)

	OverworldSession.reset()
	BattleSetupContext.clear()
	ow.free()


## --- F. [M27T piece 2] the converter's four rulings ---
##
## ⚠️ **EVERY ASSERTION HERE PINS A DECISION, NOT A MECHANISM.** The version
## pick, the first-table-per-map rule and the Kanto scope were all previously
## decided by FILE ORDER — `gen_wild_encounters.py` never read `base_label` and
## assigned straight into a dict, so the last entry silently won. That produced
## a LeafGreen game nobody chose and an all-Smeargle Altering Cave nobody chose.
## A converter-side assert cannot catch a re-decision; these can.
##
## Scope of record: `docs/m27t_encounter_authoring_scope.md` §2.2-§2.4.
func _test_converter_rulings() -> void:
	if not FileAccess.file_exists(WildEncounters.TABLE_PATH):
		_gated += 9
		return

	var land := _read_json(WildEncounters.TABLE_PATH)
	var maps: Dictionary = land.get("maps", {})

	# Ruling 3 — the Kanto scope. Hoenn's own Altering Cave was in this table
	# until M27T; a Kanto project carrying Hoenn encounter data is the shape
	# this drops. Checked through the runtime accessor as well as the file, so
	# the two cannot disagree.
	_chk("F.01 Hoenn maps are gone — this is a Kanto table",
			not WildEncounters.has_table("AlteringCave")
			and not maps.has("Route101"))
	_chk("F.02 which leaves the 105 Kanto maps that carry a land table",
			maps.size() == 105)

	# ⚠️ RULING 1, AND F.04 IS THE ONE THAT MATTERS. Murkrow and Misdreavus are
	# a version-exclusive pair across 59 Kanto land maps — FireRed ships Murkrow
	# where LeafGreen ships Misdreavus. F.03 alone would still pass under a
	# FireRed build if the two ever coexisted; only asserting the ABSENCE of the
	# FireRed exclusive proves which version was actually taken.
	var lost: Dictionary = maps.get("FiveIsland_LostCave_Room1_Frlg", {})
	var dex := {}
	for s in lost.get("slots", []):
		dex[int(s.get("dex", 0))] = true
	_chk("F.03 LeafGreen's Misdreavus is in the table", dex.has(200))
	_chk("F.04 and FireRed's Murkrow is NOT — the version pick is real",
			not dex.has(198))

	# Ruling 2 — first table per map. Six Island Altering Cave ships 9 tables
	# per version and only table 1 (Zubat) is reachable without e-Reader/Mystery
	# Gift infrastructure. Last-wins took table 9 and shipped all-Smeargle.
	var cave: Dictionary = maps.get("SixIsland_AlteringCave_Frlg", {})
	var cave_dex := {}
	for s in cave.get("slots", []):
		cave_dex[int(s.get("dex", 0))] = true
	_chk("F.05 Altering Cave is table 1's Zubat, not table 9's Smeargle",
			cave_dex.has(41) and not cave_dex.has(235))

	# The three sibling tables. No runtime consumer yet — surfing encounters and
	# a fishing rod are M27E — so these assert the ARTIFACT, which is what piece
	# 2 actually delivers. ⚠️ Their rates are SOURCE's, not this project's: only
	# land carries Rob's own widened curve, and his 2026-08-04 note is explicit
	# that water/fishing numbers come from him rather than being guessed here.
	var water := _read_json("res://data/water_encounters.json")
	_chk("F.06 water converted at source's own 5 slots",
			int(water.get("maps", {}).size()) == 50
			and water.get("slot_rates", []).size() == 5)
	var rock := _read_json("res://data/rock_smash_encounters.json")
	_chk("F.07 rock smash likewise, on its 14 maps",
			int(rock.get("maps", {}).size()) == 14
			and rock.get("slot_rates", []).size() == 5)
	# The rod split is DATA in the reference, carried through rather than
	# hardcoded downstream — a consumer that assumed the bands would silently
	# mis-band a changed table.
	var fish := _read_json("res://data/fishing_encounters.json")
	var rods: Dictionary = fish.get("rod_groups", {})
	var banded := 0
	for k in rods:
		banded += (rods[k] as Array).size()
	_chk("F.08 fishing carries 10 slots and rod bands covering every one",
			fish.get("slot_rates", []).size() == 10
			and rods.has("old_rod") and rods.has("good_rod")
			and rods.has("super_rod") and banded == 10)

	# ⚠️ A GUARD, NOT A REPAIR — mirroring the converter's own. Measured across
	# all 388 reference entries: zero inversions. If one ever appears it is a
	# reference defect to report, not something to swap silently.
	var inverted := 0
	for name in maps:
		for s in (maps[name] as Dictionary).get("slots", []):
			if int(s.get("min", 0)) > int(s.get("max", 0)):
				inverted += 1
	_chk("F.09 no table anywhere has an inverted level range (%d)" % inverted,
			inverted == 0)


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## --- G. [M27T piece 4] the trigger reads Fire Red's stamp ---
##
## The switch from "what KIND of tile is this" (Emerald, and what `[M27H H2]`
## ported) to "did the developers stamp this tile" (Fire Red). Both references
## are internally correct; this project's maps are Fire Red's.
##
## ⚠️ **G.05 IS THE ONE THAT PROVES THE SWITCH DID ANYTHING**, and G.08 is the
## one that proves the hand-painted override is what saves authored maps from it.
##
## Scope of record: `docs/m27t_encounter_authoring_scope.md` §3.
func _test_stamp_trigger() -> void:
	# The behaviour-derived fallback, in isolation. Used for hand-painted cells
	# and for a pair with no sidecar; it is the OLD rule, kept where the stamp
	# cannot answer.
	_chk("G.01 grass derives LAND",
			WildEncounters.type_from_behavior(MetatileBehavior.MB_TALL_GRASS)
			== MapManager.EncounterType.LAND)
	_chk("G.02 open ocean derives WATER",
			WildEncounters.type_from_behavior(MetatileBehavior.MB_OCEAN_WATER)
			== MapManager.EncounterType.WATER)
	_chk("G.03 an ordinary floor derives NONE",
			WildEncounters.type_from_behavior(MetatileBehavior.MB_NORMAL)
			== MapManager.EncounterType.NONE)
	# ⚠️ THE DISCRIMINATOR FOR THE WATER SET. 12 behaviours are surfable and
	# carry NO encounter flag — fast water, all four currents, waterfalls. A set
	# guessed from the names would sweep them in; this one was extracted from
	# `sTileBitAttributes`.
	_chk("G.04 but fast water does NOT — surfable is not the same as spawning",
			WildEncounters.type_from_behavior(MetatileBehavior.MB_FAST_WATER)
			== MapManager.EncounterType.NONE)

	const CAVE_DATA := "res://scenes/maps/DiglettsCave_NorthEntrance_Frlg_data.tres"
	if not ResourceLoader.exists(CAVE_DATA):
		_gated += 5
		return
	var md: MapData = (load(CAVE_DATA) as MapData).duplicate(true)
	var mm := MapManager.new()
	add_child(mm)
	# A nonzero origin, deliberately: at (0,0) global and local cells are equal
	# and a missing conversion inside `encounter_type_at` would pass anyway.
	const ORIGIN := Vector2i(7, 3)
	mm.register_chunk("cave", md, null, ORIGIN)

	# ⚠️ THE MEASURED DISAGREEMENT, ON A BAKED CORRIDOR MAP. This map has 15
	# cells the stamp marks LAND while their behaviour is not a land-encounter
	# tile at all — the same shape as Pokemon Mansion's 577, which is where it
	# actually matters. If the trigger were still behaviour-keyed, none of these
	# would resolve LAND.
	var stamp_only := 0
	var agree := 0
	for y in range(md.height):
		for x in range(md.width):
			var g := Vector2i(x, y) + ORIGIN
			var t := WildEncounters.encounter_type_at(mm, g)
			var b := md.behavior_at(x, y)
			if t == MapManager.EncounterType.LAND:
				if WildEncounters.is_land_encounter_tile(b):
					agree += 1
				else:
					stamp_only += 1
	_chk("G.05 cells the stamp marks LAND that the behaviour rule cannot see (%d)"
			% stamp_only, stamp_only > 0)
	_chk("G.06 while the cells both rules agree on still resolve LAND (%d)"
			% agree, agree > 0)

	# The override. A hand-painted cell has no stamp — Fire Red never saw the
	# tile — so it resolves through the behaviour that was painted onto it.
	# Xanadu Nursery is the live case: 91 grass cells on a NONE-stamped
	# plain-floor metatile. Reproduced synthetically rather than against Xanadu
	# itself, which is a test map Rob is actively editing.
	var probe := Vector2i(0, 0)
	while probe.y < md.height:
		if WildEncounters.encounter_type_at(mm, probe + ORIGIN) \
				== MapManager.EncounterType.NONE:
			break
		probe.x += 1
		if probe.x >= md.width:
			probe.x = 0
			probe.y += 1
	md.set_behavior_override(probe.x, probe.y, MetatileBehavior.MB_TALL_GRASS)
	_chk("G.07 a hand-painted cell resolves from the behaviour you painted,"
			+ " not from the stamp under it",
			WildEncounters.encounter_type_at(mm, probe + ORIGIN)
			== MapManager.EncounterType.LAND)
	# ⚠️ THE DISCRIMINATOR. Without clearing the flag this cannot tell "the
	# override fired" from "that metatile happened to be stamped LAND anyway".
	md.set_attr_explicit(probe.x, probe.y, MapData.AttrFlag.BEHAVIOR_EXPLICIT, false)
	_chk("G.08 and with the human's mark cleared it falls back to the stamp",
			WildEncounters.encounter_type_at(mm, probe + ORIGIN)
			== MapManager.EncounterType.NONE)

	# A cell no chunk owns must answer NONE rather than crash — the step path
	# calls this before it has established anything about where the player is.
	_chk("G.09 an unowned cell is NONE, and a null manager does not crash",
			WildEncounters.encounter_type_at(mm, Vector2i(-999, -999))
			== MapManager.EncounterType.NONE
			and WildEncounters.encounter_type_at(null, Vector2i.ZERO)
			== MapManager.EncounterType.NONE)

	# ⚠️ WITHOUT THESE TWO, REVERTING THE TRIGGER TO THE BEHAVIOUR RULE FAILS
	# NOTHING. Section C hands `should_encounter` its type explicitly, and G.05
	# exercises `encounter_type_at` without ever reaching the roll — so the SEAM
	# between them was untested, which is the `[M27H H4]` shape again. G.10 is
	# the direct inversion: grass behaviour, no stamp.
	if FileAccess.file_exists(WildEncounters.TABLE_PATH):
		# ⚠️ MEASURED OVER TRIALS, NOT ONCE, AND THE DIFFERENCE IS THE WHOLE
		# GUARD. A single roll passes ~86% of the time even with the trigger
		# reverted to the behaviour rule — the roll simply misses — so the
		# one-shot version of this assertion was decoration. Zero out of 400 is
		# a claim only the type gate can satisfy.
		var unstamped_hits := 0
		for i in range(400):
			if WildEncounters.should_encounter("ViridianForest_Frlg",
					MapManager.EncounterType.NONE,
					MetatileBehavior.MB_TALL_GRASS, MetatileBehavior.MB_TALL_GRASS,
					_rng(i), -1):
				unstamped_hits += 1
		_chk("G.10 an unstamped cell never encounters even standing on grass (%d/400)"
				% unstamped_hits, unstamped_hits == 0)
		# And the converse — a stamped floor tile DOES, which is the whole of
		# Pokemon Mansion. Probabilistic, so measured over trials.
		var floor_hits := 0
		for i in range(400):
			if WildEncounters.should_encounter("ViridianForest_Frlg",
					MapManager.EncounterType.LAND,
					MetatileBehavior.MB_NORMAL, MetatileBehavior.MB_NORMAL,
					_rng(i), -1):
				floor_hits += 1
		_chk("G.11 while a stamped plain floor does (%d/400) — the Mansion case"
				% floor_hits, floor_hits > 0)
	else:
		_gated += 2

	# ⚠️ THE UNREGENERATED-CHECKOUT PATH. A pair with no sidecar answers -1, and
	# -1 must degrade to the OLD behaviour rule rather than to NONE — otherwise
	# a fresh clone that has not run the importer would play as a world where
	# nothing spawns anywhere, which looks like a content bug rather than a
	# missing build step. `probe` still carries the grass behaviour painted in
	# G.07, with its explicit mark cleared in G.08.
	# ⚠️ **THE EDITOR AND THE GAME MUST GIVE THE SAME ANSWER, AND THEY DID NOT.**
	# The ENCOUNTERS overlay was written in piece 3 against the raw stamp; piece
	# 4 added the hand-painted override and did not repoint it, so the view drew
	# Xanadu Nursery's 91 painted grass cells as empty while the game encountered
	# on them. Found by asking what a human would SEE before handing over test
	# steps — the third caller-not-updated instance in this arc, after the
	# `caught_pokemon()` accessor and BG.10. Both sides now call
	# `resolve_encounter_type`; this pins that they cannot drift apart again.
	var ov := MapOverlay.new()
	ov.map_data = md
	add_child(ov)
	md.set_behavior_override(probe.x, probe.y, MetatileBehavior.MB_TALL_GRASS)
	_chk("G.13 the overlay agrees with the runtime on a hand-painted cell",
			ov.encounter_type_of({"cell": probe, "metatile": md.metatile_at(probe.x, probe.y)})
			== WildEncounters.encounter_type_at(mm, probe + ORIGIN)
			and ov.encounter_type_of({"cell": probe, "metatile": 0})
			== MapManager.EncounterType.LAND)
	md.set_attr_explicit(probe.x, probe.y, MapData.AttrFlag.BEHAVIOR_EXPLICIT, false)
	ov.free()

	md.atlas = "no_such_pair__anywhere"
	_chk("G.12 a pair with no stamp table falls back to behaviour, not to NONE",
			WildEncounters.encounter_type_at(mm, probe + ORIGIN)
			== MapManager.EncounterType.LAND)
	mm.free()


## --- H. [M27T piece 5] the authored table layer ---
##
## Authored tables are `.tres` Resources under `data/encounters/`, overriding the
## generated JSON per map. ⚠️ **THIS REVERSES D4b** (`m27m5_map_creator_scope.md`,
## Rob 2026-08-09, which chose JSON and rejected Inspector editability by name) —
## reopened by Rob 2026-08-12 because in-Godot editing became a requirement and
## Godot gives free undo and property interception only for Resources.
##
## ⚠️ **H.05/H.06 ARE THE PAIR-SYMMETRY CONVENTION**, tested independently
## because a symmetric-LOOKING clamp where only one direction fires is exactly
## what a one-directional test passes.
##
## Scope of record: `docs/m27t_encounter_authoring_scope.md` §4.
func _test_authored_layer() -> void:
	# The migrated table. Xanadu is the project's only authored map, and its
	# grass exists ONLY because of piece 4's override — so this layer and that
	# one are load-bearing for the same 91 cells.
	_chk("H.01 Xanadu's authored table still resolves after the move to .tres",
			WildEncounters.has_table("XanaduNursery"))
	var x := WildEncounters.table_for("XanaduNursery")
	var dexes := {}
	for s in x.get("slots", []):
		dexes[int(s.get("dex", 0))] = true
	_chk("H.02 with its rate, its 15 slots and its own species intact",
			int(x.get("encounter_rate", 0)) == 21
			and x.get("slots", []).size() == 15
			and dexes.has(19) and dexes.has(16) and dexes.has(10) and dexes.has(13))
	# ⚠️ THE SHAPE IS THE GENERATED ONE. `to_runtime()` meets the JSON layer's
	# dictionary exactly, which is what kept this storage change invisible past
	# `table_for()` — the roll, the party builder and every older test are
	# untouched.
	# ⚠️ **COMPARED KEY-FOR-KEY AGAINST THE GENERATED LAYER, INCLUDING INSIDE A
	# SLOT — the first version of this checked only the top level plus `dex`, and
	# renaming `min`/`max` to `min_level`/`max_level` passed it while
	# `build_wild_party` would have read nothing at runtime.** Found by
	# injection, not by reading. The slot keys are where the two layers most
	# easily drift, because `EncounterSlot` names its own fields differently on
	# purpose and `to_runtime()` is the only thing translating them.
	var g := WildEncounters.table_for("ViridianForest_Frlg")
	var x_slot: Dictionary = x["slots"][0]
	var g_slot: Dictionary = g["slots"][0]
	var x_keys := x.keys(); x_keys.sort()
	var g_keys := g.keys(); g_keys.sort()
	var xs_keys := x_slot.keys(); xs_keys.sort()
	var gs_keys := g_slot.keys(); gs_keys.sort()
	_chk("H.03 and it is the same shape the generated layer returns, slots"
			+ " included (%s / %s)" % [x_keys, xs_keys],
			x_keys == g_keys and xs_keys == gs_keys
			and x.has("encounter_rate") and xs_keys.has("dex"))

	# ⚠️ A BLANK TABLE MUST BEHAVE AS NO TABLE. A freshly created one is all-zero
	# by construction, and an unset slot would otherwise resolve to species 0 and
	# hand the player a nonsense encounter.
	var blank := EncounterTable.new()
	_chk("H.04 a blank table is not complete, so it can never reach the roll",
			not blank.is_complete(15) and blank.incomplete_reason(15) != "")
	blank.map_name = "Somewhere"
	blank.encounter_rate = 21
	for i in range(15):
		blank.slots.append(EncounterSlot.new())
	_chk("H.05 nor is one whose slots have no species yet",
			not blank.is_complete(15)
			and blank.incomplete_reason(15).contains("no species"))
	for s in blank.slots:
		s.dex = 16
	_chk("H.06 but it becomes usable once every slot is filled",
			blank.is_complete(15) and blank.incomplete_reason(15) == "")
	# The wrong slot COUNT is its own failure: the rate table indexes by slot,
	# so a short list would point the odds at the wrong mon.
	blank.slots.remove_at(0)
	_chk("H.07 and a short slot list is refused rather than silently indexed",
			not blank.is_complete(15)
			and blank.incomplete_reason(15).contains("needs 15"))

	# ⚠️ CLAMPING LIVES IN THE SETTER, NOT THE UI — it has to hold for a script
	# edit, a converter and a fixture, not just for someone dragging a spinbox.
	var slot := EncounterSlot.new()
	slot.min_level = 10
	slot.max_level = 20
	slot.min_level = 30
	_chk("H.08 pushing min above max carries max up with it (%d-%d)"
			% [slot.min_level, slot.max_level],
			slot.min_level == 30 and slot.max_level == 30)
	# ⚠️ THE MIRROR, TESTED SEPARATELY. Same convention as every other pair in
	# this project: one direction passing proves nothing about the other.
	var slot2 := EncounterSlot.new()
	slot2.max_level = 40
	slot2.min_level = 20
	slot2.max_level = 5
	_chk("H.09 and pulling max below min carries min down (%d-%d)"
			% [slot2.min_level, slot2.max_level],
			slot2.min_level == 5 and slot2.max_level == 5)
	var slot3 := EncounterSlot.new()
	slot3.max_level = 999
	slot3.min_level = -5
	_chk("H.10 levels stay inside 1-100 whatever they are handed (%d-%d)"
			% [slot3.min_level, slot3.max_level],
			slot3.min_level == 1 and slot3.max_level == 100)

	# ⚠️ **THE LOADER'S OWN GATE, AND NOTHING ABOVE COVERS IT.** H.04-H.07 drive
	# `is_complete()` directly; the scan is what has to ACT on it, and with the
	# scan welded to the live directory the only way to exercise the refusal was
	# to write junk into `data/encounters/`. Removing the gate would have failed
	# nothing — the same callee-tested/caller-untested seam as `[M27H H4]`'s
	# accessor, BG.10 and G.10 before it. Pointed at a throwaway `user://`
	# directory so the game's own corpus is never involved.
	const SCRATCH := "user://m27t_scan_probe/"
	DirAccess.make_dir_recursive_absolute(SCRATCH)
	var half := EncounterTable.new()
	half.map_name = "HalfEdited"
	half.encounter_rate = 21
	for i in range(15):
		half.slots.append(EncounterSlot.new())
	half.slots[7].dex = 0                      # the one unset slot
	for s in half.slots:
		if s != half.slots[7]:
			s.dex = 16
	var whole := EncounterTable.new()
	whole.map_name = "Finished"
	whole.encounter_rate = 21
	for i in range(15):
		var s2 := EncounterSlot.new()
		s2.dex = 16
		whole.slots.append(s2)
	ResourceSaver.save(half, SCRATCH + "HalfEdited_land.tres")
	ResourceSaver.save(whole, SCRATCH + "Finished_land.tres")
	var scanned := WildEncounters.scan_authored_dir(SCRATCH)
	_chk("H.13 the loader admits a complete table",
			scanned.has("Finished")
			and (scanned["Finished"] as Dictionary).get("encounter_rate", 0) == 21)
	# ⚠️ THE DISCRIMINATOR. Without H.13 beside it, "the half-edited one is
	# absent" would also pass if the scan found nothing at all.
	_chk("H.14 and refuses the one with an unfilled slot, so the map plays as"
			+ " though it has no table",
			not scanned.has("HalfEdited") and scanned.size() == 1)
	DirAccess.remove_absolute(SCRATCH + "HalfEdited_land.tres")
	DirAccess.remove_absolute(SCRATCH + "Finished_land.tres")
	DirAccess.remove_absolute(SCRATCH)

	# ⚠️ THE SHIPPED CORPUS, swept rather than sampled — the whole point of a
	# hand-authored layer is that nobody regenerates it, so a table that went
	# stale or got half-edited stays broken until something looks.
	var dir := DirAccess.open(WildEncounters.AUTHORED_DIR)
	if dir == null:
		_gated += 2
		return
	var expected := WildEncounters.slot_rates().size()
	var bad_tables: Array = []
	var misnamed: Array = []
	var count := 0
	for file in dir.get_files():
		var fname := file.trim_suffix(".remap")
		if not (fname.ends_with(".tres") or fname.ends_with(".res")):
			continue
		count += 1
		var t := ResourceLoader.load(WildEncounters.AUTHORED_DIR + fname) as EncounterTable
		if t == null or not t.is_complete(expected):
			bad_tables.append(fname)
			continue
		# A file whose NAME and CONTENTS disagree is worse than either being
		# wrong on its own — it makes the map it feeds unguessable.
		if fname.get_basename() != t.expected_basename():
			misnamed.append(fname)
	_chk("H.11 every shipped authored table is complete (%d table(s), bad: %s)"
			% [count, bad_tables], count > 0 and bad_tables.is_empty())
	_chk("H.12 and its filename matches the map and field inside it (%s)"
			% [misnamed], misnamed.is_empty())
