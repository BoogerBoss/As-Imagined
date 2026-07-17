extends Node

# Milestone 5 verification: stat-stage moves, status-inflicting moves, secondary effects.
# Tests six areas independently:
#   1. MoveRegistry .tres spot-checks for new M5 moves.
#   2. StatusManager.apply_stat_change() — clamping and fail-at-limit behavior.
#   3. StatusManager.check_accuracy() — stage ratios and force parameters.
#   4. StatusManager.try_secondary_effect() — all SE_* types, type immunities, chance forcing.
#   5. DamageCalculator with staged stats — verify stages flow into damage formula.
#   6. Flinch handling via pre_move_check() — ordering before confusion/paralysis.
#
# Expected damage values are formula-derived, NOT copied from source:
#   base = floor(floor(floor((2*L/5+2)*power*A)/D)/50) + 2
#   → roll → STAB → type-eff (UQ4.12 accumulated, applied once)
#
# Source: pokeemerald_expansion (GEN_LATEST config)
#
# Run: /home/rob/Godot_v4.7.1-stable_linux.x86_64 --headless --path . scenes/battle/stat_test.tscn

var _pass := 0
var _fail := 0


func _ready() -> void:
	print("=== Milestone 5: Stat-Stage & Status Moves ===")
	print("")

	# ─── Test Pokémon ─────────────────────────────────────────────────────────
	# Charmander L50: Fire | base hp=39 atk=52 def=43 spatk=60 spdef=50 spd=65
	#   computed:      hp=99  atk=57  def=48  spatk=65 sdef=55 spd=70
	var charmander := _make_mon("Charmander", [TypeChart.TYPE_FIRE],
			39, 52, 43, 60, 50, 65)

	# Squirtle L50: Water | base hp=44 atk=48 def=65 spatk=50 spdef=64 spd=43
	#   computed:      hp=104 atk=53  def=70  spatk=55 sdef=69 spd=48
	var squirtle := _make_mon("Squirtle", [TypeChart.TYPE_WATER],
			44, 48, 65, 50, 64, 43)

	# Raichu L50: Electric | for Electric-immunity tests
	var raichu := _make_mon("Raichu", [TypeChart.TYPE_ELECTRIC],
			60, 90, 55, 90, 80, 110)

	# Arcanine L50: Fire | for burn-immunity tests
	var arcanine := _make_mon("Arcanine", [TypeChart.TYPE_FIRE],
			90, 110, 80, 100, 80, 95)

	# Dugtrio L50: Ground | for Thunder Wave type immunity test
	var dugtrio := _make_mon("Dugtrio", [TypeChart.TYPE_GROUND],
			35, 100, 50, 50, 70, 120)

	# Haunter L50: Ghost | for Confuse Ray type effectiveness (Ghost→Normal immunity)
	# Actually we want a Normal-type target to test Ghost→Normal immunity
	var snorlax := _make_mon("Snorlax", [TypeChart.TYPE_NORMAL],
			160, 110, 65, 65, 110, 30)

	# ─── SECTION 1: Move data spot-checks ────────────────────────────────────
	print("--- Section 1: New M5 move data ---")

	# Swords Dance (14): Normal/Status/acc=0/pp=20, +2 Atk self
	var sdance := MoveRegistry.get_move(14)
	_check_notnull("S1.swords_dance loaded",                    sdance)
	_check_exact("S1.swords_dance category=Status(2)",          sdance.category,        2)
	_check_exact("S1.swords_dance accuracy=0 (always hits)",    sdance.accuracy,        0)
	_check_exact("S1.swords_dance pp=20",                       sdance.pp,              20)
	_check_exact("S1.swords_dance stat_change_stat=ATK(0)",     sdance.stat_change_stat, 0)
	_check_exact("S1.swords_dance stat_change_amount=+2",       sdance.stat_change_amount, 2)
	_check_exact("S1.swords_dance stat_change_self=true",       int(sdance.stat_change_self), 1)

	# Growl (45): Normal/Status/acc=100/pp=40, -1 Atk foe, sound_move
	var growl := MoveRegistry.get_move(45)
	_check_notnull("S1.growl loaded",                           growl)
	_check_exact("S1.growl stat_change_amount=-1",              growl.stat_change_amount, -1)
	_check_exact("S1.growl stat_change_self=false",             int(growl.stat_change_self), 0)
	_check_exact("S1.growl sound_move=true",                    int(growl.sound_move),  1)

	# Thunder Wave (86): Electric/Status/acc=90/pp=20, secondary_effect=SE_PARALYSIS(3), chance=0
	var twave := MoveRegistry.get_move(86)
	_check_notnull("S1.thunder_wave loaded",                    twave)
	_check_exact("S1.thunder_wave type=ELECTRIC(14)",           twave.type,             TypeChart.TYPE_ELECTRIC)
	_check_exact("S1.thunder_wave accuracy=90",                 twave.accuracy,         90)
	_check_exact("S1.thunder_wave secondary_effect=PARA(3)",    twave.secondary_effect, MoveData.SE_PARALYSIS)
	_check_exact("S1.thunder_wave secondary_chance=0",          twave.secondary_chance, 0)

	# Body Slam (34): Normal/Phys/85, secondary_effect=SE_PARALYSIS, chance=30
	var bslam := MoveRegistry.get_move(34)
	_check_notnull("S1.body_slam loaded",                       bslam)
	_check_exact("S1.body_slam secondary_effect=PARA(3)",       bslam.secondary_effect, MoveData.SE_PARALYSIS)
	_check_exact("S1.body_slam secondary_chance=30",            bslam.secondary_chance, 30)

	# Rock Slide (157): Rock/Phys/75/90, secondary_effect=SE_FLINCH(7), chance=30
	var rslide := MoveRegistry.get_move(157)
	_check_notnull("S1.rock_slide loaded",                      rslide)
	_check_exact("S1.rock_slide secondary_effect=FLINCH(7)",    rslide.secondary_effect, MoveData.SE_FLINCH)
	_check_exact("S1.rock_slide secondary_chance=30",           rslide.secondary_chance, 30)

	# Flame Wheel (172): Fire/Phys/60/100/25, thaws_user, 10% burn
	var fwheel := MoveRegistry.get_move(172)
	_check_notnull("S1.flame_wheel loaded",                     fwheel)
	_check_exact("S1.flame_wheel thaws_user=true",              int(fwheel.thaws_user),  1)
	_check_exact("S1.flame_wheel secondary_effect=BURN(1)",     fwheel.secondary_effect, MoveData.SE_BURN)
	_check_exact("S1.flame_wheel secondary_chance=10",          fwheel.secondary_chance, 10)

	# ─── SECTION 2: apply_stat_change() ──────────────────────────────────────
	print("")
	print("--- Section 2: apply_stat_change() ---")

	var mon2 := _clone(squirtle)

	# +2 Atk from 0
	var r2a := StatusManager.apply_stat_change(mon2, BattlePokemon.STAGE_ATK, 2)
	_check_exact("S2a apply +2 Atk: returns 2",                r2a, 2)
	_check_exact("S2a apply +2 Atk: stage becomes +2",         mon2.stat_stages[BattlePokemon.STAGE_ATK], 2)

	# -1 Def from 0 on a fresh mon
	var mon2b := _clone(squirtle)
	var r2b := StatusManager.apply_stat_change(mon2b, BattlePokemon.STAGE_DEF, -1)
	_check_exact("S2b apply -1 Def: returns -1",               r2b, -1)
	_check_exact("S2b apply -1 Def: stage becomes -1",         mon2b.stat_stages[BattlePokemon.STAGE_DEF], -1)

	# Fail at max: +1 from +6 → returns 0, stage unchanged
	var mon2c := _clone(squirtle)
	mon2c.stat_stages[BattlePokemon.STAGE_ATK] = 6
	var r2c := StatusManager.apply_stat_change(mon2c, BattlePokemon.STAGE_ATK, 1)
	_check_exact("S2c fail at +6 max: returns 0",              r2c, 0)
	_check_exact("S2c fail at +6 max: stage stays +6",         mon2c.stat_stages[BattlePokemon.STAGE_ATK], 6)

	# Fail at min: -1 from -6 → returns 0, stage unchanged
	var mon2d := _clone(squirtle)
	mon2d.stat_stages[BattlePokemon.STAGE_DEF] = -6
	var r2d := StatusManager.apply_stat_change(mon2d, BattlePokemon.STAGE_DEF, -1)
	_check_exact("S2d fail at -6 min: returns 0",              r2d, 0)
	_check_exact("S2d fail at -6 min: stage stays -6",         mon2d.stat_stages[BattlePokemon.STAGE_DEF], -6)

	# Partial clamp: +2 from +5 → only +1 applied, stage becomes +6
	var mon2e := _clone(squirtle)
	mon2e.stat_stages[BattlePokemon.STAGE_SPATK] = 5
	var r2e := StatusManager.apply_stat_change(mon2e, BattlePokemon.STAGE_SPATK, 2)
	_check_exact("S2e clamp +2 from +5: returns 1 (partial)",  r2e, 1)
	_check_exact("S2e clamp +2 from +5: stage becomes +6",     mon2e.stat_stages[BattlePokemon.STAGE_SPATK], 6)

	# Accuracy stage lowering (Sand Attack -1 Accuracy)
	var mon2f := _clone(squirtle)
	var r2f := StatusManager.apply_stat_change(mon2f, BattlePokemon.STAGE_ACCURACY, -1)
	_check_exact("S2f Sand Attack -1 Acc: returns -1",         r2f, -1)
	_check_exact("S2f Sand Attack -1 Acc: stage becomes -1",   mon2f.stat_stages[BattlePokemon.STAGE_ACCURACY], -1)

	# ─── SECTION 3: check_accuracy() ─────────────────────────────────────────
	print("")
	print("--- Section 3: check_accuracy() ---")

	var atk3 := _clone(charmander)
	var def3 := _clone(squirtle)
	var twave3 := MoveRegistry.get_move(86)  # Thunder Wave, acc=90

	# acc=0 always hits regardless of force param
	_check_exact("S3a accuracy=0 (Swords Dance) → always hits",
			int(StatusManager.check_accuracy(atk3, def3, sdance, null)), 1)

	# acc=90, force_hit=true
	_check_exact("S3b force_hit=true → hits",
			int(StatusManager.check_accuracy(atk3, def3, twave3, true)), 1)

	# acc=90, force_hit=false
	_check_exact("S3c force_hit=false → misses",
			int(StatusManager.check_accuracy(atk3, def3, twave3, false)), 0)

	# Attacker STAGE_ACCURACY=-1: calc = 90 * 75 / 100 = 67. force_hit=true still hits.
	var atk3d := _clone(charmander)
	atk3d.stat_stages[BattlePokemon.STAGE_ACCURACY] = -1
	_check_exact("S3d acc_stage=-1, force_hit=true → hits",
			int(StatusManager.check_accuracy(atk3d, def3, twave3, true)), 1)
	_check_exact("S3e acc_stage=-1, force_hit=false → misses",
			int(StatusManager.check_accuracy(atk3d, def3, twave3, false)), 0)

	# Defender STAGE_EVASION=+1: net stage = 0 - 1 = -1; same calc = 67. force=true.
	var def3f := _clone(squirtle)
	def3f.stat_stages[BattlePokemon.STAGE_EVASION] = 1
	_check_exact("S3f evasion_stage=+1, force_hit=true → hits",
			int(StatusManager.check_accuracy(atk3, def3f, twave3, true)), 1)

	# ─── SECTION 4: try_secondary_effect() ───────────────────────────────────
	print("")
	print("--- Section 4: try_secondary_effect() ---")

	var ember := MoveRegistry.get_move(52)      # SE_BURN, chance=10
	var icebeam := MoveRegistry.get_move(58)    # SE_FREEZE, chance=10
	var psybeam := MoveRegistry.get_move(60)    # SE_CONFUSION, chance=10
	var bslam4 := MoveRegistry.get_move(34)     # SE_PARALYSIS, chance=30
	var rslide4 := MoveRegistry.get_move(157)   # SE_FLINCH, chance=30
	var sleeppowder := MoveRegistry.get_move(79)  # SE_SLEEP, chance=0 (guaranteed)
	var toxic := MoveRegistry.get_move(92)      # SE_TOXIC, chance=0 (guaranteed)

	# SE_BURN, force=true on non-Fire target
	var def4a := _clone(squirtle)
	var r4a := StatusManager.try_secondary_effect(charmander, def4a, ember, true)
	_check_exact("S4a SE_BURN forced: fires and applies",       int(r4a), 1)
	_check_exact("S4a SE_BURN forced: squirtle is burned",      def4a.status, BattlePokemon.STATUS_BURN)

	# SE_BURN, force=true on Fire-type (immune)
	var def4b := _clone(arcanine)
	var r4b := StatusManager.try_secondary_effect(charmander, def4b, ember, true)
	_check_exact("S4b SE_BURN on Fire-type: blocked by immunity", int(r4b), 0)
	_check_exact("S4b SE_BURN on Fire-type: no status applied",  def4b.status, BattlePokemon.STATUS_NONE)

	# SE_PARALYSIS, force=true on non-Electric target
	var def4c := _clone(squirtle)
	var r4c := StatusManager.try_secondary_effect(charmander, def4c, bslam4, true)
	_check_exact("S4c SE_PARALYSIS forced: fires",              int(r4c), 1)
	_check_exact("S4c SE_PARALYSIS forced: squirtle paralyzed", def4c.status, BattlePokemon.STATUS_PARALYSIS)

	# SE_PARALYSIS, force=true on Electric-type (immune in GEN6+)
	var def4d := _clone(raichu)
	var r4d := StatusManager.try_secondary_effect(charmander, def4d, bslam4, true)
	_check_exact("S4d SE_PARALYSIS on Electric-type: blocked",  int(r4d), 0)
	_check_exact("S4d SE_PARALYSIS on Electric-type: no status", def4d.status, BattlePokemon.STATUS_NONE)

	# SE_PARALYSIS on already-statused mon
	var def4e := _clone(squirtle)
	def4e.status = BattlePokemon.STATUS_BURN  # already has burn
	var r4e := StatusManager.try_secondary_effect(charmander, def4e, bslam4, true)
	_check_exact("S4e already-statused: secondary fails",       int(r4e), 0)

	# SE_CONFUSION, force=true on fresh target
	var def4f := _clone(squirtle)
	var r4f := StatusManager.try_secondary_effect(charmander, def4f, psybeam, true)
	_check_exact("S4f SE_CONFUSION forced: fires",              int(r4f), 1)
	_check_exact("S4f SE_CONFUSION: squirtle confused",         int(def4f.confusion_turns > 0), 1)

	# SE_SLEEP, chance=0 (guaranteed), force=null (skips roll), fires immediately
	var def4g := _clone(squirtle)
	var r4g := StatusManager.try_secondary_effect(charmander, def4g, sleeppowder, null)
	_check_exact("S4g SE_SLEEP guaranteed (chance=0): fires",   int(r4g), 1)
	_check_exact("S4g SE_SLEEP: squirtle asleep",               def4g.status, BattlePokemon.STATUS_SLEEP)

	# SE_TOXIC, chance=0 (guaranteed), force=null
	var def4h := _clone(squirtle)
	var r4h := StatusManager.try_secondary_effect(charmander, def4h, toxic, null)
	_check_exact("S4h SE_TOXIC guaranteed: fires",              int(r4h), 1)
	_check_exact("S4h SE_TOXIC: squirtle badly poisoned",       def4h.status, BattlePokemon.STATUS_TOXIC)

	# SE_FLINCH, force=true → try_secondary_effect returns true (caller sets flinched)
	var def4i := _clone(squirtle)
	var r4i := StatusManager.try_secondary_effect(charmander, def4i, rslide4, true)
	_check_exact("S4i SE_FLINCH forced roll: try_secondary returns true", int(r4i), 1)
	# Note: try_secondary does NOT set flinched — that's BattleManager's job after turn-order check
	_check_exact("S4i SE_FLINCH: squirtle.flinched not set by try_secondary", int(def4i.flinched), 0)

	# force_secondary=false suppresses roll entirely (no effect fires)
	var def4j := _clone(squirtle)
	var r4j := StatusManager.try_secondary_effect(charmander, def4j, ember, false)
	_check_exact("S4j force_secondary=false: effect suppressed", int(r4j), 0)
	_check_exact("S4j force_secondary=false: no status",        def4j.status, BattlePokemon.STATUS_NONE)

	# ─── SECTION 5: Damage formula with stat stages ───────────────────────────
	print("")
	print("--- Section 5: Damage formula with stat stages ---")

	# All cases: Charmander uses Scratch (Normal/Phys/40) on Squirtle.
	# roll=100, force_crit=false, no STAB (Normal≠Fire), Normal→Water=1.0×.
	# Charmander L50: atk=57. Squirtle L50: def=70.
	#
	# Formula: base = floor(floor(floor((2*50/5+2)*40*A)/D)/50) + 2
	#        = floor(floor(floor(22*40*A)/70)/50) + 2

	var scratch := MoveRegistry.get_move(10)   # Normal/Phys/40/100/35

	# T5a: no stat stages → atk=57, def=70
	#   floor(floor(floor(22*40*57)/70)/50)+2 = floor(floor(50160)/70)/50+2
	#   = floor(716)/50+2 = 14+2 = 16
	var ch5a := _clone(charmander)
	var sq5a := _clone(squirtle)
	var r5a := DamageCalculator.calculate(ch5a, sq5a, scratch, 100, false)
	_check_exact("T5a Scratch no stages (expect 16)",            r5a["damage"], 16)

	# T5b: Charmander +2 Atk → staged_atk = floor(57*2/1) = 114
	#   floor(floor(22*40*114)/70)/50+2 = floor(1433)/50+2 = 28+2 = 30
	var ch5b := _clone(charmander)
	ch5b.stat_stages[BattlePokemon.STAGE_ATK] = 2
	var sq5b := _clone(squirtle)
	var r5b := DamageCalculator.calculate(ch5b, sq5b, scratch, 100, false)
	_check_exact("T5b Scratch Char +2Atk (expect 30)",           r5b["damage"], 30)

	# T5c: Squirtle -1 Def → staged_def = floor(70*10/15) = 46   [ratio: 10/15 = 2/3]
	#   floor(floor(22*40*57)/46)/50+2 = floor(50160/46)/50+2
	#   = floor(1090)/50+2 = 21+2 = 23
	var ch5c := _clone(charmander)
	var sq5c := _clone(squirtle)
	sq5c.stat_stages[BattlePokemon.STAGE_DEF] = -1
	var r5c := DamageCalculator.calculate(ch5c, sq5c, scratch, 100, false)
	_check_exact("T5c Scratch Sqtl -1Def (expect 23)",           r5c["damage"], 23)

	# T5d: Charmander +2 Atk AND Squirtle -1 Def → staged_atk=114, staged_def=46
	#   floor(floor(22*40*114)/46)/50+2 = floor(100320/46)/50+2
	#   = floor(2180)/50+2 = 43+2 = 45
	var ch5d := _clone(charmander)
	ch5d.stat_stages[BattlePokemon.STAGE_ATK] = 2
	var sq5d := _clone(squirtle)
	sq5d.stat_stages[BattlePokemon.STAGE_DEF] = -1
	var r5d := DamageCalculator.calculate(ch5d, sq5d, scratch, 100, false)
	_check_exact("T5d Scratch +2Atk/-1Def (expect 45)",          r5d["damage"], 45)

	# T5e: Charmander -1 Atk (as if Growl hit) → staged_atk = floor(57*10/15) = 38
	#   floor(floor(22*40*38)/70)/50+2 = floor(33440/70)/50+2
	#   = floor(477)/50+2 = 9+2 = 11
	var ch5e := _clone(charmander)
	ch5e.stat_stages[BattlePokemon.STAGE_ATK] = -1
	var sq5e := _clone(squirtle)
	var r5e := DamageCalculator.calculate(ch5e, sq5e, scratch, 100, false)
	_check_exact("T5e Scratch Char -1Atk (expect 11)",           r5e["damage"], 11)

	# T5f: Charmander uses Flamethrower (Fire/Spec/90) on Squirtle, Char +1 SpAtk
	#   staged_spatk = floor(65*15/10) = 97   [ratio: 15/10 = 3/2]
	#   base = floor(floor(22*90*97)/69)/50+2
	#        = floor(192060/69)/50+2 = floor(2783)/50+2 = 55+2 = 57
	#   roll=100 → 57 → STAB (Char=Fire, FThr=Fire): floor((57*6144+2047)/4096)
	#     = floor(352215/4096) = floor(85.98) = 85
	#   Fire→Water (0.5×): floor((85*2048+2047)/4096)
	#     = floor(176127/4096) = floor(42.99) = 42
	var flamethrower := MoveRegistry.get_move(53)
	var ch5f := _clone(charmander)
	ch5f.stat_stages[BattlePokemon.STAGE_SPATK] = 1
	var sq5f := _clone(squirtle)
	var r5f := DamageCalculator.calculate(ch5f, sq5f, flamethrower, 100, false)
	_check_exact("T5f Flamethrower Char +1SpAtk (expect 42)",    r5f["damage"], 42)

	# ─── SECTION 6: Flinch via pre_move_check() ─────────────────────────────
	print("")
	print("--- Section 6: Flinch via pre_move_check() ---")

	# S6a: Not flinched → can_move=true
	var mon6a := _clone(squirtle)
	mon6a.flinched = false
	var check6a := StatusManager.pre_move_check(mon6a)
	_check_exact("S6a not flinched → can_move=true",            int(check6a["can_move"]), 1)
	_check_exact("S6a not flinched → flinched key=false",       int(check6a["flinched"]), 0)

	# S6b: flinched=true → stops move, clears flag on mon
	var mon6b := _clone(squirtle)
	mon6b.flinched = true
	var check6b := StatusManager.pre_move_check(mon6b)
	_check_exact("S6b flinched → can_move=false",               int(check6b["can_move"]), 0)
	_check_exact("S6b flinched → result key flinched=true",     int(check6b["flinched"]), 1)
	_check_exact("S6b flinched → mon.flinched cleared to false", int(mon6b.flinched), 0)

	# S6c: flinched BEFORE paralysis (canceler order: FLINCH pos34 < PARALYZED pos41)
	# Even with paralysis, flinch fires first and returns early.
	var mon6c := _clone(squirtle)
	mon6c.flinched = true
	mon6c.status = BattlePokemon.STATUS_PARALYSIS
	var check6c := StatusManager.pre_move_check(mon6c, null, null, null, false)
	# force_full_para=false so paralysis doesn't block (flinch must block before reaching para)
	_check_exact("S6c flinched + para → flinch fires first",    int(check6c["flinched"]), 1)
	_check_exact("S6c flinched + para → can_move=false",        int(check6c["can_move"]), 0)

	# S6d: flinched BEFORE confusion (canceler order: FLINCH pos34 < CONFUSED pos39)
	var mon6d := _clone(squirtle)
	mon6d.flinched = true
	mon6d.confusion_turns = 3
	# force_confusion_hit=false so confusion doesn't fire (flinch must fire first)
	var check6d := StatusManager.pre_move_check(mon6d, null, null, false)
	_check_exact("S6d flinched + confused → flinch fires first", int(check6d["flinched"]), 1)
	_check_exact("S6d flinched + confused → confusion_turns unchanged", mon6d.confusion_turns, 3)

	# ─── RESULTS ──────────────────────────────────────────────────────────────
	print("")
	print("=== Results: " + str(_pass) + " passed, " + str(_fail) + " failed ===")
	get_tree().quit(0 if _fail == 0 else 1)


# ─── Helpers ─────────────────────────────────────────────────────────────────

func _check_exact(label: String, got: int, expected: int) -> void:
	if got == expected:
		print("PASS  " + label)
		_pass += 1
	else:
		print("FAIL  " + label + "  expected=" + str(expected) + " got=" + str(got))
		_fail += 1


func _check_notnull(label: String, obj: Object) -> void:
	if obj != null:
		print("PASS  " + label)
		_pass += 1
	else:
		print("FAIL  " + label + "  (got null)")
		_fail += 1


func _make_mon(name: String, types: Array[int], base_hp: int, base_atk: int,
		base_def: int, base_satk: int, base_sdef: int, base_spd: int) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name    = name
	sp.types           = types
	sp.base_hp         = base_hp
	sp.base_attack     = base_atk
	sp.base_defense    = base_def
	sp.base_sp_attack  = base_satk
	sp.base_sp_defense = base_sdef
	sp.base_speed      = base_spd
	sp.abilities       = []
	sp.learnset        = []
	# [M18.5h-1] Pinned to a neutral nature — this whole file's exact-value damage/
	# stat assertions were written assuming no nature adjustment; from_species now
	# rolls a real (non-neutral 20/25 of the time) nature by default, which would
	# otherwise silently perturb Attack/Defense/Sp.Atk/Sp.Def/Speed here.
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])  # [M18.5h-1/2] pinned neutral nature + zero IVs -- exact-value assertions predate both


func _clone(mon: BattlePokemon) -> BattlePokemon:
	# [M18.5h-1] Copies the SOURCE mon's own nature forward rather than re-rolling —
	# a faithful clone must reproduce the original's stats exactly, matching this
	# function's own existing (if incomplete — IVs/EVs aren't copied either, a
	# pre-existing gap out of this tier's scope) "copy relevant state" contract.
	var bp := BattlePokemon.from_species(mon.species, mon.level, mon.nature, mon.ivs)  # [M18.5h-1/2] preserves the SOURCE mon's nature AND IVs, matching the copy contract
	bp.status          = mon.status
	bp.sleep_turns     = mon.sleep_turns
	bp.toxic_counter   = mon.toxic_counter
	bp.confusion_turns = mon.confusion_turns
	bp.flinched        = mon.flinched
	bp.stat_stages     = mon.stat_stages.duplicate()
	return bp
