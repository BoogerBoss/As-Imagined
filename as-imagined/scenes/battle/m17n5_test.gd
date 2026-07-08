extends Node

# M17n-5 test suite — Damage-pipeline leftovers (docs/m17n_recon.md Group 4, trimmed
# by Rob's explicit exclusions). Continues the m17n<N> numeral-suffix naming
# convention established in [M17n-1].
#
# Scope: 17 abilities implemented this tier, per docs/decisions.md [M17n-5] (the
# task's own count of 19 didn't match its own 18-name enumeration — this project's
# re-derivation also lands on 18, and Skill Link (92) is further DEFERRED: no
# multi_hit mechanic exists anywhere in this codebase's battle logic to modify):
#   Attacker move-power modifiers (move_power_modifier_uq412): Iron Fist(89),
#     Technician(101), Reckless(120), Sheer Force(125, + suppresses its own
#     secondary effect), Strong Jaw(173), Mega Launcher(178, new pulse_move flag),
#     Punk Rock(244, own-boost half), Sharpness(292), Analytic(148).
#   Attacker stat modifier (attack_modifier_uq412, new `defender` param):
#     Stakeout(198), Slow Start(112, Atk half).
#   Defender damage modifiers (defense_damage_modifier_uq412): Fluffy(218),
#     Punk Rock(244, defense half).
#   Crit stage (DamageCalculator._roll_crit): Super Luck(105).
#   Accuracy (accuracy_modifier_percent): Tangled Feet(77).
#   Contact-flag override (new AbilityManager.move_makes_contact): Long Reach(203).
#   New mechanism (BattleManager._do_damaging_hit + the OHKO block): Sturdy(5).
#   New volatile (slow_start_timer, try_switch_in/try_end_of_turn/_clear_volatiles):
#     Slow Start(112, Speed half).
#   Secondary-chance doubler (StatusManager.try_secondary_effect): Serene Grace(32).
#
# No move in this project's current roster carries biting_move/slicing_move/
# pulse_move — Strong Jaw/Sharpness/Mega Launcher are tested via synthetic MoveData,
# matching the established _make_move-style precedent ([M17a]) for flag-dependent
# power modifiers.
#
# No prior suite in this codebase tests a probabilistic RATE directly (only
# force_crit/force_secondary, which bypass the underlying roll entirely) — Super Luck
# and Serene Grace's rate-doubling both need a statistical-sample test, a new pattern
# for this project, with wide safety margins (many standard deviations) to avoid flakiness.
#
# Testing conventions applied throughout (CLAUDE.md):
#   - Pairwise damage comparisons force BOTH _force_roll and _force_crit on every
#     scenario being compared (the newly-added convention this tier's task itself
#     required be documented first).
#   - Signal-snapshot, not post-battle state.
#   - Type immunity precedes ability logic: Normal-type combatants throughout.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_section_1_ability_data()
	_test_section_2_sturdy()
	_test_section_3_iron_fist()
	_test_section_4_technician()
	_test_section_5_reckless()
	_test_section_6_sheer_force()
	_test_section_7_strong_jaw()
	_test_section_8_mega_launcher()
	_test_section_9_punk_rock()
	_test_section_10_sharpness()
	_test_section_11_analytic()
	_test_section_12_super_luck()
	_test_section_13_tangled_feet()
	_test_section_14_stakeout()
	_test_section_15_long_reach()
	_test_section_16_fluffy()
	_test_section_17_slow_start()
	_test_section_18_serene_grace()
	_test_section_19_mold_breaker_and_neutralizing_gas()
	_test_section_20_negative_control()

	var total := _pass + _fail
	print("m17n5_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL: " + label)


func _load_ability(id: int) -> AbilityData:
	return load("res://data/abilities/ability_%04d.tres" % id) as AbilityData


func _load_move(id: int) -> MoveData:
	return load("res://data/moves/move_%04d.tres" % id) as MoveData


func _make_mon(mon_name: String, types: Array[int], hp: int = 100, atk: int = 80,
		def_stat: int = 80, spatk: int = 80, spdef: int = 80, spd: int = 80) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types = types
	sp.base_hp = hp
	sp.base_attack = atk
	sp.base_defense = def_stat
	sp.base_sp_attack = spatk
	sp.base_sp_defense = spdef
	sp.base_speed = spd
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY)  # [M18.5h-1] pinned neutral -- exact-value assertions predate Nature


func _synth_move(power: int = 40, category: int = 0, move_type: int = TypeChart.TYPE_NORMAL) -> MoveData:
	var m := MoveData.new()
	m.type = move_type
	m.category = category
	m.power = power
	m.accuracy = 100
	return m


# ── Section 1: Ability data spot-checks ──────────────────────────────────────

func _test_section_1_ability_data() -> void:
	var sturdy := _load_ability(5)
	_chk("S1.01 Sturdy id=5, breakable=true", sturdy.ability_id == 5 and sturdy.breakable)

	var iron_fist := _load_ability(89)
	_chk("S1.02 Iron Fist id=89, NOT breakable", iron_fist.ability_id == 89 and not iron_fist.breakable)

	var technician := _load_ability(101)
	_chk("S1.03 Technician id=101, breakable=true (data-faithful, unreachable here)",
			technician.ability_id == 101 and technician.breakable)

	var reckless := _load_ability(120)
	_chk("S1.04 Reckless id=120, NOT breakable", reckless.ability_id == 120 and not reckless.breakable)

	var sheer_force := _load_ability(125)
	_chk("S1.05 Sheer Force id=125, breakable=true (data-faithful, unreachable here)",
			sheer_force.ability_id == 125 and sheer_force.breakable)

	var analytic := _load_ability(148)
	_chk("S1.06 Analytic id=148, NOT breakable", analytic.ability_id == 148 and not analytic.breakable)

	var super_luck := _load_ability(105)
	_chk("S1.07 Super Luck id=105, NOT breakable", super_luck.ability_id == 105 and not super_luck.breakable)

	var tangled_feet := _load_ability(77)
	_chk("S1.08 Tangled Feet id=77, breakable=true", tangled_feet.ability_id == 77 and tangled_feet.breakable)

	var strong_jaw := _load_ability(173)
	_chk("S1.09 Strong Jaw id=173, NOT breakable", strong_jaw.ability_id == 173 and not strong_jaw.breakable)

	var mega_launcher := _load_ability(178)
	_chk("S1.10 Mega Launcher id=178, NOT breakable", mega_launcher.ability_id == 178 and not mega_launcher.breakable)

	var stakeout := _load_ability(198)
	_chk("S1.11 Stakeout id=198, breakable=true (data-faithful, unreachable here)",
			stakeout.ability_id == 198 and stakeout.breakable)

	var long_reach := _load_ability(203)
	_chk("S1.12 Long Reach id=203, NOT breakable", long_reach.ability_id == 203 and not long_reach.breakable)

	var fluffy := _load_ability(218)
	_chk("S1.13 Fluffy id=218, breakable=true", fluffy.ability_id == 218 and fluffy.breakable)

	var punk_rock := _load_ability(244)
	_chk("S1.14 Punk Rock id=244, breakable=true", punk_rock.ability_id == 244 and punk_rock.breakable)

	var sharpness := _load_ability(292)
	_chk("S1.15 Sharpness id=292, NOT breakable", sharpness.ability_id == 292 and not sharpness.breakable)

	var slow_start := _load_ability(112)
	_chk("S1.16 Slow Start id=112, NOT breakable", slow_start.ability_id == 112 and not slow_start.breakable)

	var serene_grace := _load_ability(32)
	_chk("S1.17 Serene Grace id=32, NOT breakable", serene_grace.ability_id == 32 and not serene_grace.breakable)

	# Skill Link (92) is intentionally NOT implemented this tier — confirmed via grep
	# that no multi_hit mechanic exists in this codebase's battle logic at all.
	var skill_link := _load_ability(92)
	_chk("S1.18 Skill Link's placeholder data exists (id/name only, no mechanism " +
			"wired — deferred, not forgotten)",
			skill_link.ability_id == 92 and skill_link.ability_name == "Skill Link")

	var pulse_probe := _synth_move()
	_chk("S1.19 the new pulse_move MoveData flag defaults to false", not pulse_probe.pulse_move)


# ── Section 2: Sturdy — survive-at-1-HP + OHKO block ─────────────────────────

func _test_section_2_sturdy() -> void:
	var tackle := _load_move(33)
	var double_edge := _load_move(38)  # power=120, comfortably lethal (Tackle's
	# power=40 was NOT lethal here — base_hp=100 -> actual max_hp=160 via the real
	# level-50 HP formula, base+level+10, not base_hp itself; caught by this test's
	# own first run).
	var sturdy := _load_ability(5)

	# Full HP, lethal hit -> survives at exactly 1 HP.
	var defender := _make_mon("SturdyDefender", [TypeChart.TYPE_NORMAL], 100, 40, 40, 40, 40, 40)
	defender.ability = sturdy
	defender.add_move(tackle)
	var attacker := _make_mon("SturdyAttacker", [TypeChart.TYPE_NORMAL], 100, 255, 40, 40, 40, 100)
	attacker.add_move(double_edge)

	# Signal-snapshot discipline: Sturdy only protects the FIRST lethal hit at full
	# HP — once the holder is down to 1 HP, a full battle continuing past that point
	# will land a SECOND, genuinely lethal hit (1 HP is no longer full HP) and the
	# holder faints normally. Reading defender.current_hp after the whole battle
	# completes would see 0/fainted, not 1 — snapshot the HP at the exact moment of
	# the FIRST attacker-on-defender hit instead.
	var triggered := []
	var hp_after_first_hit := [-1]
	var seen_first_hit := [false]
	var bm := BattleManager.new()
	add_child(bm)
	bm._force_hit = true
	bm._force_roll = 100
	bm._force_crit = false
	bm.ability_triggered.connect(func(m, tag): triggered.push_back([m, tag]))
	bm.move_executed.connect(func(a, d, m, dmg):
		if a == attacker and d == defender and not seen_first_hit[0]:
			seen_first_hit[0] = true
			hp_after_first_hit[0] = defender.current_hp)
	bm.start_battle_with_parties(BattleParty.single(attacker), BattleParty.single(defender))

	_chk("S2.01 Sturdy holder survives an otherwise-lethal hit at exactly 1 HP " +
			"(snapshotted at the first hit, not post-battle)",
			hp_after_first_hit[0] == 1)
	_chk("S2.02 the 'sturdy' ability_triggered signal fired",
			triggered.any(func(e): return e[0] == defender and e[1] == "sturdy"))

	bm.queue_free()

	# Discriminator: NOT at full HP when hit -> does NOT survive (faints normally).
	var defender2 := _make_mon("SturdyDefender2", [TypeChart.TYPE_NORMAL], 100, 40, 40, 40, 40, 40)
	defender2.ability = sturdy
	defender2.current_hp = 50  # below full HP
	defender2.add_move(tackle)
	var attacker2 := _make_mon("SturdyAttacker2", [TypeChart.TYPE_NORMAL], 100, 255, 40, 40, 40, 100)
	attacker2.add_move(tackle)

	var bm2 := BattleManager.new()
	add_child(bm2)
	bm2._force_hit = true
	bm2._force_roll = 100
	bm2._force_crit = false
	bm2.start_battle_with_parties(BattleParty.single(attacker2), BattleParty.single(defender2))

	_chk("S2.03 discriminator: Sturdy does NOT save a holder that was already below " +
			"full HP when hit",
			defender2.fainted and defender2.current_hp == 0)

	bm2.queue_free()

	# Blocks OHKO outright.
	var fissure := _load_move(90)  # Fissure — OHKO Ground move
	var ohko_attacker := _make_mon("SturdyOHKOAttacker", [TypeChart.TYPE_GROUND], 100, 80, 60, 60, 60, 100)
	ohko_attacker.add_move(fissure)
	var ohko_defender := _make_mon("SturdyOHKODefender", [TypeChart.TYPE_NORMAL], 100, 40, 40, 40, 40, 40)
	ohko_defender.ability = sturdy
	ohko_defender.add_move(tackle)

	var missed_events := []
	var bm3 := BattleManager.new()
	add_child(bm3)
	bm3._force_hit = true
	bm3.move_missed.connect(func(a, r): missed_events.push_back([a, r]))
	bm3.start_battle_with_parties(BattleParty.single(ohko_attacker), BattleParty.single(ohko_defender))

	_chk("S2.04 Sturdy blocks an OHKO move outright, regardless of HP",
			missed_events.any(func(e): return e[0] == ohko_attacker and e[1] == "sturdy_blocks_ohko"))
	_chk("S2.05 the Sturdy holder survived the OHKO attempt entirely",
			not ohko_defender.fainted)

	bm3.queue_free()


# ── Section 3: Iron Fist ──────────────────────────────────────────────────────

func _test_section_3_iron_fist() -> void:
	var iron_fist := _load_ability(89)
	var punching := _synth_move(60, 0)
	punching.punching_move = true
	var non_punching := _synth_move(60, 0)

	var holder := _make_mon("IronFistUnit", [TypeChart.TYPE_NORMAL])
	holder.ability = iron_fist
	var target := _make_mon("IronFistTarget", [TypeChart.TYPE_NORMAL])

	var boosted: Dictionary = DamageCalculator.calculate(holder, target, punching, 100, false)
	var unboosted: Dictionary = DamageCalculator.calculate(holder, target, non_punching, 100, false)
	_chk("S3.01 Iron Fist boosts a punching move's damage",
			boosted["damage"] > unboosted["damage"])

	var plain := _make_mon("IronFistPlain", [TypeChart.TYPE_NORMAL])
	var plain_punch: Dictionary = DamageCalculator.calculate(plain, target, punching, 100, false)
	_chk("S3.02 discriminator: a non-Iron-Fist holder gets no boost on the same move",
			plain_punch["damage"] == unboosted["damage"])


# ── Section 4: Technician ─────────────────────────────────────────────────────

func _test_section_4_technician() -> void:
	var technician := _load_ability(101)
	var weak_move := _synth_move(60, 0)   # base power == 60, boundary case
	var strong_move := _synth_move(61, 0)  # base power > 60

	var holder := _make_mon("TechnicianUnit", [TypeChart.TYPE_NORMAL])
	holder.ability = technician
	var target := _make_mon("TechnicianTarget", [TypeChart.TYPE_NORMAL])
	var plain := _make_mon("TechnicianPlain", [TypeChart.TYPE_NORMAL])

	var weak_boosted: Dictionary = DamageCalculator.calculate(holder, target, weak_move, 100, false)
	var weak_plain: Dictionary = DamageCalculator.calculate(plain, target, weak_move, 100, false)
	_chk("S4.01 Technician boosts a move at exactly base power 60 (the <= 60 boundary)",
			weak_boosted["damage"] > weak_plain["damage"])

	var strong_boosted: Dictionary = DamageCalculator.calculate(holder, target, strong_move, 100, false)
	var strong_plain: Dictionary = DamageCalculator.calculate(plain, target, strong_move, 100, false)
	_chk("S4.02 discriminator: Technician does NOT boost a move at base power 61",
			strong_boosted["damage"] == strong_plain["damage"])


# ── Section 5: Reckless ───────────────────────────────────────────────────────

func _test_section_5_reckless() -> void:
	var reckless := _load_ability(120)
	var double_edge := _load_move(38)  # recoil_percent=33
	var tackle := _load_move(33)       # no recoil

	var holder := _make_mon("RecklessUnit", [TypeChart.TYPE_NORMAL])
	holder.ability = reckless
	var target := _make_mon("RecklessTarget", [TypeChart.TYPE_NORMAL])
	var plain := _make_mon("RecklessPlain", [TypeChart.TYPE_NORMAL])

	var boosted: Dictionary = DamageCalculator.calculate(holder, target, double_edge, 100, false)
	var plain_recoil: Dictionary = DamageCalculator.calculate(plain, target, double_edge, 100, false)
	_chk("S5.01 Reckless boosts a recoil move's damage", boosted["damage"] > plain_recoil["damage"])

	var no_recoil_boosted: Dictionary = DamageCalculator.calculate(holder, target, tackle, 100, false)
	var no_recoil_plain: Dictionary = DamageCalculator.calculate(plain, target, tackle, 100, false)
	_chk("S5.02 discriminator: Reckless does NOT boost a non-recoil move",
			no_recoil_boosted["damage"] == no_recoil_plain["damage"])


# ── Section 6: Sheer Force ─────────────────────────────────────────────────────

func _test_section_6_sheer_force() -> void:
	var sheer_force := _load_ability(125)
	var with_secondary := _synth_move(60, 0)
	with_secondary.secondary_effect = MoveData.SE_PARALYSIS
	with_secondary.secondary_chance = 30
	var no_secondary := _synth_move(60, 0)  # SE_NONE, chance=0

	var holder := _make_mon("SheerForceUnit", [TypeChart.TYPE_NORMAL])
	holder.ability = sheer_force
	var target := _make_mon("SheerForceTarget", [TypeChart.TYPE_NORMAL])
	var plain := _make_mon("SheerForcePlain", [TypeChart.TYPE_NORMAL])

	var boosted: Dictionary = DamageCalculator.calculate(holder, target, with_secondary, 100, false)
	var plain_dmg: Dictionary = DamageCalculator.calculate(plain, target, with_secondary, 100, false)
	_chk("S6.01 Sheer Force boosts a move WITH a probabilistic secondary effect",
			boosted["damage"] > plain_dmg["damage"])

	var no_sec_boosted: Dictionary = DamageCalculator.calculate(holder, target, no_secondary, 100, false)
	var no_sec_plain: Dictionary = DamageCalculator.calculate(plain, target, no_secondary, 100, false)
	_chk("S6.02 discriminator: Sheer Force does NOT boost a move with NO secondary " +
			"effect at all (confirmed from source, not assumed)",
			no_sec_boosted["damage"] == no_sec_plain["damage"])

	# Suppression half: even forced to fire, Sheer Force blocks the secondary effect.
	var applied: bool = StatusManager.try_secondary_effect(holder, target, with_secondary, true)
	_chk("S6.03 Sheer Force suppresses the move's own secondary effect entirely, " +
			"even when force_secondary=true",
			not applied)

	var plain_applied: bool = StatusManager.try_secondary_effect(plain, target, with_secondary, true)
	_chk("S6.04 discriminator: a non-Sheer-Force attacker's forced secondary effect DOES apply",
			plain_applied)


# ── Section 7: Strong Jaw (synthetic biting move — none exist in this roster) ──

func _test_section_7_strong_jaw() -> void:
	var strong_jaw := _load_ability(173)
	var biting := _synth_move(60, 0)
	biting.biting_move = true
	var non_biting := _synth_move(60, 0)

	var holder := _make_mon("StrongJawUnit", [TypeChart.TYPE_NORMAL])
	holder.ability = strong_jaw
	var target := _make_mon("StrongJawTarget", [TypeChart.TYPE_NORMAL])
	var plain := _make_mon("StrongJawPlain", [TypeChart.TYPE_NORMAL])

	var boosted: Dictionary = DamageCalculator.calculate(holder, target, biting, 100, false)
	var plain_dmg: Dictionary = DamageCalculator.calculate(plain, target, biting, 100, false)
	_chk("S7.01 Strong Jaw boosts a biting move (synthetic — no real biting move " +
			"exists in this project's roster)",
			boosted["damage"] > plain_dmg["damage"])

	var non_biting_boosted: Dictionary = DamageCalculator.calculate(holder, target, non_biting, 100, false)
	var non_biting_plain: Dictionary = DamageCalculator.calculate(plain, target, non_biting, 100, false)
	_chk("S7.02 discriminator: Strong Jaw does NOT boost a non-biting move",
			non_biting_boosted["damage"] == non_biting_plain["damage"])


# ── Section 8: Mega Launcher (synthetic pulse move — none exist in this roster) ─

func _test_section_8_mega_launcher() -> void:
	var mega_launcher := _load_ability(178)
	var pulse := _synth_move(60, 1)
	pulse.pulse_move = true
	var non_pulse := _synth_move(60, 1)

	var holder := _make_mon("MegaLauncherUnit", [TypeChart.TYPE_NORMAL])
	holder.ability = mega_launcher
	var target := _make_mon("MegaLauncherTarget", [TypeChart.TYPE_NORMAL])
	var plain := _make_mon("MegaLauncherPlain", [TypeChart.TYPE_NORMAL])

	var boosted: Dictionary = DamageCalculator.calculate(holder, target, pulse, 100, false)
	var plain_dmg: Dictionary = DamageCalculator.calculate(plain, target, pulse, 100, false)
	_chk("S8.01 Mega Launcher boosts a pulse move (synthetic — no real pulse move " +
			"exists in this project's roster; new pulse_move MoveData flag)",
			boosted["damage"] > plain_dmg["damage"])

	var non_pulse_boosted: Dictionary = DamageCalculator.calculate(holder, target, non_pulse, 100, false)
	var non_pulse_plain: Dictionary = DamageCalculator.calculate(plain, target, non_pulse, 100, false)
	_chk("S8.02 discriminator: Mega Launcher does NOT boost a non-pulse move",
			non_pulse_boosted["damage"] == non_pulse_plain["damage"])


# ── Section 9: Punk Rock (own boost + defense half) ──────────────────────────

func _test_section_9_punk_rock() -> void:
	var punk_rock := _load_ability(244)
	var growl := _load_move(45)  # sound_move=true, but status (no damage) — use a
	# synthetic damaging sound move instead so both halves are testable via damage.
	var sound_move := _synth_move(60, 0)
	sound_move.sound_move = true
	var non_sound := _synth_move(60, 0)

	var holder := _make_mon("PunkRockAtkUnit", [TypeChart.TYPE_NORMAL])
	holder.ability = punk_rock
	var target := _make_mon("PunkRockAtkTarget", [TypeChart.TYPE_NORMAL])
	var plain := _make_mon("PunkRockAtkPlain", [TypeChart.TYPE_NORMAL])

	var boosted: Dictionary = DamageCalculator.calculate(holder, target, sound_move, 100, false)
	var plain_dmg: Dictionary = DamageCalculator.calculate(plain, target, sound_move, 100, false)
	_chk("S9.01 Punk Rock boosts its own sound move's damage",
			boosted["damage"] > plain_dmg["damage"])

	var non_sound_boosted: Dictionary = DamageCalculator.calculate(holder, target, non_sound, 100, false)
	var non_sound_plain: Dictionary = DamageCalculator.calculate(plain, target, non_sound, 100, false)
	_chk("S9.02 discriminator: Punk Rock does NOT boost a non-sound move",
			non_sound_boosted["damage"] == non_sound_plain["damage"])

	# Defense half: damage TAKEN from a sound move is halved.
	var pr_defender := _make_mon("PunkRockDefUnit", [TypeChart.TYPE_NORMAL])
	pr_defender.ability = punk_rock
	var plain_defender := _make_mon("PunkRockDefPlain", [TypeChart.TYPE_NORMAL])
	var attacker := _make_mon("PunkRockDefAttacker", [TypeChart.TYPE_NORMAL])

	var reduced: Dictionary = DamageCalculator.calculate(attacker, pr_defender, sound_move, 100, false)
	var baseline: Dictionary = DamageCalculator.calculate(attacker, plain_defender, sound_move, 100, false)
	_chk("S9.03 Punk Rock halves damage TAKEN from a sound move",
			reduced["damage"] < baseline["damage"])

	# sanity: Growl is confirmed sound_move=true in this project's actual roster.
	_chk("S9.04 sanity: Growl (id 45) is confirmed sound_move=true in this project's roster",
			growl.sound_move)


# ── Section 10: Sharpness (synthetic slicing move — none exist in this roster) ──

func _test_section_10_sharpness() -> void:
	var sharpness := _load_ability(292)
	var slicing := _synth_move(60, 0)
	slicing.slicing_move = true
	var non_slicing := _synth_move(60, 0)

	var holder := _make_mon("SharpnessUnit", [TypeChart.TYPE_NORMAL])
	holder.ability = sharpness
	var target := _make_mon("SharpnessTarget", [TypeChart.TYPE_NORMAL])
	var plain := _make_mon("SharpnessPlain", [TypeChart.TYPE_NORMAL])

	var boosted: Dictionary = DamageCalculator.calculate(holder, target, slicing, 100, false)
	var plain_dmg: Dictionary = DamageCalculator.calculate(plain, target, slicing, 100, false)
	_chk("S10.01 Sharpness boosts a slicing move (synthetic — no real slicing move " +
			"exists in this project's roster)",
			boosted["damage"] > plain_dmg["damage"])

	var non_slicing_boosted: Dictionary = DamageCalculator.calculate(holder, target, non_slicing, 100, false)
	var non_slicing_plain: Dictionary = DamageCalculator.calculate(plain, target, non_slicing, 100, false)
	_chk("S10.02 discriminator: Sharpness does NOT boost a non-slicing move",
			non_slicing_boosted["damage"] == non_slicing_plain["damage"])


# ── Section 11: Analytic — full-battle, moving last ──────────────────────────

func _test_section_11_analytic() -> void:
	var tackle := _load_move(33)
	var analytic := _load_ability(148)

	# Analytic holder is SLOWER (moves last naturally) vs. a faster plain opponent.
	var an := _make_mon("AnalyticBattle", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 40)
	an.ability = analytic
	an.add_move(tackle)
	var opp := _make_mon("AnalyticOpp", [TypeChart.TYPE_NORMAL], 200, 80, 60, 60, 60, 100)
	opp.add_move(tackle)

	# Deterministic damage baseline via a direct calc with is_last_to_move both ways.
	var last_calc: Dictionary = DamageCalculator.calculate(
			an, opp, tackle, 100, false, DamageCalculator.WEATHER_NONE, false, false, -1,
			false, false, null, null, false, true)
	var not_last_calc: Dictionary = DamageCalculator.calculate(
			an, opp, tackle, 100, false, DamageCalculator.WEATHER_NONE, false, false, -1,
			false, false, null, null, false, false)
	_chk("S11.01 sanity: Analytic's is_last_to_move flag genuinely changes the " +
			"calculated damage (moving last boosts it)",
			last_calc["damage"] > not_last_calc["damage"])

	var move_executed_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm._force_roll = 100
	bm._force_crit = false
	bm.move_executed.connect(func(a, d, m, dmg): move_executed_events.push_back([a, d, m, dmg]))
	bm.start_battle_with_parties(BattleParty.single(an), BattleParty.single(opp))

	var an_hit := move_executed_events.filter(func(e): return e[0] == an and e[1] == opp)
	_chk("S11.02 full-battle: Analytic's holder (moving last, naturally slower) " +
			"deals the BOOSTED damage matching the is_last_to_move=true calc",
			not an_hit.is_empty() and an_hit[0][3] == last_calc["damage"])

	bm.queue_free()

	# Discriminator: Analytic holder is FASTER (moves first) -> no boost.
	var an2 := _make_mon("AnalyticBattle2", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 100)
	an2.ability = analytic
	an2.add_move(tackle)
	var opp2 := _make_mon("AnalyticOpp2", [TypeChart.TYPE_NORMAL], 200, 80, 60, 60, 60, 40)
	opp2.add_move(tackle)

	var move_executed_events2 := []
	var bm2 := BattleManager.new()
	add_child(bm2)
	bm2._force_roll = 100
	bm2._force_crit = false
	bm2.move_executed.connect(func(a, d, m, dmg): move_executed_events2.push_back([a, d, m, dmg]))
	bm2.start_battle_with_parties(BattleParty.single(an2), BattleParty.single(opp2))

	var an2_hit := move_executed_events2.filter(func(e): return e[0] == an2 and e[1] == opp2)
	_chk("S11.03 discriminator: Analytic's holder moving FIRST (naturally faster) " +
			"deals the UN-boosted damage matching the is_last_to_move=false calc",
			not an2_hit.is_empty() and an2_hit[0][3] == not_last_calc["damage"])

	bm2.queue_free()


# ── Section 12: Super Luck — statistical crit-rate sample ───────────────────
# No deterministic seam exists for the underlying crit-STAGE roll (only
# force_crit=true/false, which bypasses the calculation as a whole) and no prior
# suite in this codebase tests a probabilistic rate directly — a statistical sample
# is the only way to verify the stage math. Expected rates (CRIT_ODDS_GEN7 =
# {24,8,2,1}): stage 0 = 1/24 ≈ 4.17%, stage 1 (Super Luck's +1) = 1/8 = 12.5% — wide
# margins (many standard deviations) are used to avoid flakiness.

func _test_section_12_super_luck() -> void:
	var super_luck := _load_ability(105)
	var tackle := _load_move(33)
	var holder := _make_mon("SuperLuckUnit", [TypeChart.TYPE_NORMAL])
	holder.ability = super_luck
	var plain := _make_mon("SuperLuckPlain", [TypeChart.TYPE_NORMAL])
	var target := _make_mon("SuperLuckTarget", [TypeChart.TYPE_NORMAL])

	var n := 5000
	var plain_crits := 0
	var luck_crits := 0
	for _i in range(n):
		var r1: Dictionary = DamageCalculator.calculate(plain, target, tackle, 100, null)
		if r1["is_crit"]:
			plain_crits += 1
		var r2: Dictionary = DamageCalculator.calculate(holder, target, tackle, 100, null)
		if r2["is_crit"]:
			luck_crits += 1

	var plain_rate: float = float(plain_crits) / n
	var luck_rate: float = float(luck_crits) / n
	_chk("S12.01 a plain Pokémon's observed crit rate is near the expected 1/24 " +
			"baseline (well under 7%%, n=%d, observed=%.3f)" % [n, plain_rate],
			plain_rate < 0.07)
	_chk("S12.02 Super Luck's observed crit rate is measurably higher, near the " +
			"expected 1/8 (well over 9%%, n=%d, observed=%.3f)" % [n, luck_rate],
			luck_rate > 0.09)


# ── Section 13: Tangled Feet ──────────────────────────────────────────────────

func _test_section_13_tangled_feet() -> void:
	var tangled_feet := _load_ability(77)
	var tackle := _load_move(33)

	var attacker := _make_mon("TangledFeetAttacker", [TypeChart.TYPE_NORMAL])
	var confused_defender := _make_mon("TangledFeetDefender", [TypeChart.TYPE_NORMAL])
	confused_defender.ability = tangled_feet
	confused_defender.confusion_turns = 3

	var pct: int = AbilityManager.accuracy_modifier_percent(
			attacker, tackle, false, confused_defender, DamageCalculator.WEATHER_NONE)
	_chk("S13.01 Tangled Feet reduces the attacker's accuracy to 50%% while confused",
			pct == 50)

	var not_confused := _make_mon("TangledFeetDefender2", [TypeChart.TYPE_NORMAL])
	not_confused.ability = tangled_feet
	var pct2: int = AbilityManager.accuracy_modifier_percent(
			attacker, tackle, false, not_confused, DamageCalculator.WEATHER_NONE)
	_chk("S13.02 discriminator: Tangled Feet has no effect while NOT confused",
			pct2 == 100)


# ── Section 14: Stakeout ──────────────────────────────────────────────────────

func _test_section_14_stakeout() -> void:
	var stakeout := _load_ability(198)
	var tackle := _load_move(33)

	var holder := _make_mon("StakeoutUnit", [TypeChart.TYPE_NORMAL])
	holder.ability = stakeout
	var switched_in_target := _make_mon("StakeoutTargetSwitched", [TypeChart.TYPE_NORMAL])
	switched_in_target.switched_in_this_turn = true
	var normal_target := _make_mon("StakeoutTargetNormal", [TypeChart.TYPE_NORMAL])

	var boosted: Dictionary = DamageCalculator.calculate(
			holder, switched_in_target, tackle, 100, false)
	var unboosted: Dictionary = DamageCalculator.calculate(
			holder, normal_target, tackle, 100, false)
	_chk("S14.01 Stakeout doubles damage against a target that switched in this turn",
			boosted["damage"] > unboosted["damage"])

	var plain := _make_mon("StakeoutPlain", [TypeChart.TYPE_NORMAL])
	var plain_vs_switched: Dictionary = DamageCalculator.calculate(
			plain, switched_in_target, tackle, 100, false)
	_chk("S14.02 discriminator: a non-Stakeout attacker gets no bonus against the " +
			"same switched-in target",
			plain_vs_switched["damage"] == unboosted["damage"])


# ── Section 15: Long Reach ────────────────────────────────────────────────────

func _test_section_15_long_reach() -> void:
	var long_reach := _load_ability(203)
	var tackle := _load_move(33)  # makes_contact = true
	var static_ability := _load_ability(9)

	var lr_attacker := _make_mon("LongReachAttacker", [TypeChart.TYPE_NORMAL])
	lr_attacker.ability = long_reach
	_chk("S15.01 an attacking Long Reach holder's contact move no longer counts as contact",
			not AbilityManager.move_makes_contact(lr_attacker, tackle))

	var plain_attacker := _make_mon("LongReachPlainAttacker", [TypeChart.TYPE_NORMAL])
	_chk("S15.02 discriminator: a plain attacker's same contact move still counts as contact",
			AbilityManager.move_makes_contact(plain_attacker, tackle))

	# Integration: Long Reach suppresses Static's contact-triggered paralysis chance
	# entirely (via try_contact_effects' shared chokepoint).
	var static_holder := _make_mon("LongReachStaticTarget", [TypeChart.TYPE_NORMAL], 100, 40, 40, 40, 40, 30)
	static_holder.ability = static_ability
	var result: Dictionary = AbilityManager.try_contact_effects(
			lr_attacker, static_holder, tackle, 50, true)
	_chk("S15.03 Long Reach suppresses Static's contact trigger entirely (forced " +
			"roll=true would otherwise guarantee it)",
			result["status_applied"] == 0)

	var result_plain: Dictionary = AbilityManager.try_contact_effects(
			plain_attacker, static_holder, tackle, 50, true)
	_chk("S15.04 discriminator: a plain attacker's contact DOES trigger Static " +
			"(forced roll=true)",
			result_plain["status_applied"] == BattlePokemon.STATUS_PARALYSIS)


# ── Section 16: Fluffy ────────────────────────────────────────────────────────

func _test_section_16_fluffy() -> void:
	var fluffy := _load_ability(218)
	var fire_move := _synth_move(60, 0, TypeChart.TYPE_FIRE)  # not flagged contact
	var contact_normal := _synth_move(60, 0, TypeChart.TYPE_NORMAL)
	contact_normal.makes_contact = true
	var contact_fire := _synth_move(60, 0, TypeChart.TYPE_FIRE)
	contact_fire.makes_contact = true

	var attacker := _make_mon("FluffyAttacker", [TypeChart.TYPE_NORMAL])
	var fluffy_defender := _make_mon("FluffyDefender", [TypeChart.TYPE_NORMAL])
	fluffy_defender.ability = fluffy
	var plain_defender := _make_mon("FluffyPlainDefender", [TypeChart.TYPE_NORMAL])

	var fire_boosted: Dictionary = DamageCalculator.calculate(attacker, fluffy_defender, fire_move, 100, false)
	var fire_baseline: Dictionary = DamageCalculator.calculate(attacker, plain_defender, fire_move, 100, false)
	_chk("S16.01 Fluffy DOUBLES damage from a non-contact Fire-type move",
			fire_boosted["damage"] > fire_baseline["damage"])

	var contact_reduced: Dictionary = DamageCalculator.calculate(attacker, fluffy_defender, contact_normal, 100, false)
	var contact_baseline: Dictionary = DamageCalculator.calculate(attacker, plain_defender, contact_normal, 100, false)
	_chk("S16.02 Fluffy HALVES damage from a contact non-Fire move",
			contact_reduced["damage"] < contact_baseline["damage"])

	# Key discriminator: a CONTACT Fire move triggers NEITHER branch — net x1.0,
	# not both halving and doubling stacking together.
	var contact_fire_result: Dictionary = DamageCalculator.calculate(attacker, fluffy_defender, contact_fire, 100, false)
	var contact_fire_baseline: Dictionary = DamageCalculator.calculate(attacker, plain_defender, contact_fire, 100, false)
	_chk("S16.03 key discriminator: a CONTACT Fire move is UNAFFECTED by Fluffy " +
			"(neither branch fires — confirmed from source, not both stacking to cancel out)",
			contact_fire_result["damage"] == contact_fire_baseline["damage"])

	# Long Reach interaction: an attacking Long Reach holder's contact move should
	# read as non-contact for Fluffy's purposes too.
	var long_reach := _load_ability(203)
	var lr_attacker := _make_mon("FluffyLRAttacker", [TypeChart.TYPE_NORMAL])
	lr_attacker.ability = long_reach
	var lr_result: Dictionary = DamageCalculator.calculate(lr_attacker, fluffy_defender, contact_normal, 100, false)
	var lr_baseline: Dictionary = DamageCalculator.calculate(lr_attacker, plain_defender, contact_normal, 100, false)
	_chk("S16.04 a Long-Reach-holding attacker's 'contact' move is NOT halved by " +
			"Fluffy (correctly reads as non-contact)",
			lr_result["damage"] == lr_baseline["damage"])


# ── Section 17: Slow Start ────────────────────────────────────────────────────

func _test_section_17_slow_start() -> void:
	var slow_start := _load_ability(112)
	var tackle := _load_move(33)

	# Direct unit test: Atk half (physical only), Speed half (unconditional).
	var holder := _make_mon("SlowStartUnit", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 100)
	holder.ability = slow_start
	holder.slow_start_timer = 3
	var special_move := _synth_move(60, 1)

	_chk("S17.01 Atk halved for a physical move while the timer is running",
			AbilityManager.attack_modifier_uq412(holder, tackle) == 2048)
	_chk("S17.02 discriminator: Atk NOT halved for a special move (physical-only gate)",
			AbilityManager.attack_modifier_uq412(holder, special_move) == 4096)
	_chk("S17.03 Speed halved unconditionally while the timer is running",
			StatusManager.effective_speed(holder) == holder.speed / 2)

	holder.slow_start_timer = 0
	_chk("S17.04 discriminator: no penalty once the timer reaches 0",
			AbilityManager.attack_modifier_uq412(holder, tackle) == 4096
			and StatusManager.effective_speed(holder) == holder.speed)

	# Full-battle: switch-in sets the timer to 5; exactly 5 end-of-turn ticks clear it.
	var ss := _make_mon("SlowStartBattle", [TypeChart.TYPE_NORMAL], 500, 60, 60, 60, 60, 60)
	ss.ability = slow_start
	ss.add_move(tackle)
	var opp := _make_mon("SlowStartOpp", [TypeChart.TYPE_NORMAL], 500, 60, 60, 60, 60, 60)
	opp.add_move(tackle)

	var ended_count := [0]
	var bm := BattleManager.new()
	add_child(bm)
	bm.ability_triggered.connect(func(m, tag):
		if tag == "slow_start_ended":
			ended_count[0] += 1)
	bm.start_battle_with_parties(BattleParty.single(ss), BattleParty.single(opp))

	_chk("S17.05 full-battle: 'slow_start_ended' fired exactly once (the 5-turn " +
			"timer ends cleanly, not multiple times)",
			ended_count[0] == 1)

	bm.queue_free()


# ── Section 18: Serene Grace ──────────────────────────────────────────────────

func _test_section_18_serene_grace() -> void:
	var serene_grace := _load_ability(32)
	var thirty_pct := _synth_move(60, 0)
	thirty_pct.secondary_effect = MoveData.SE_PARALYSIS
	thirty_pct.secondary_chance = 30

	var holder := _make_mon("SereneGraceUnit", [TypeChart.TYPE_NORMAL])
	holder.ability = serene_grace
	var plain := _make_mon("SereneGracePlain", [TypeChart.TYPE_NORMAL])
	var target_a := _make_mon("SereneGraceTargetA", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 30)
	var target_b := _make_mon("SereneGraceTargetB", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 30)

	var n := 3000
	var holder_fires := 0
	var plain_fires := 0
	for _i in range(n):
		target_a.status = BattlePokemon.STATUS_NONE
		target_b.status = BattlePokemon.STATUS_NONE
		if StatusManager.try_secondary_effect(holder, target_a, thirty_pct):
			holder_fires += 1
		if StatusManager.try_secondary_effect(plain, target_b, thirty_pct):
			plain_fires += 1

	var holder_rate: float = float(holder_fires) / n
	var plain_rate: float = float(plain_fires) / n
	_chk("S18.01 a plain attacker's observed trigger rate is near the expected 30%% " +
			"(n=%d, observed=%.3f)" % [n, plain_rate],
			plain_rate > 0.24 and plain_rate < 0.36)
	_chk("S18.02 Serene Grace's observed trigger rate is roughly DOUBLE, near the " +
			"expected 60%% (n=%d, observed=%.3f)" % [n, holder_rate],
			holder_rate > 0.52 and holder_rate < 0.68)

	# 100% cap: a 60% base chance doubles to 120%, must cap at guaranteed (100%).
	var sixty_pct := _synth_move(60, 0)
	sixty_pct.secondary_effect = MoveData.SE_PARALYSIS
	sixty_pct.secondary_chance = 60
	var capped_fires := 0
	var cap_trials := 50
	for _i in range(cap_trials):
		target_a.status = BattlePokemon.STATUS_NONE
		if StatusManager.try_secondary_effect(holder, target_a, sixty_pct):
			capped_fires += 1
	_chk("S18.03 a 60%% base chance doubled by Serene Grace (120%%) correctly caps " +
			"at guaranteed — fires all %d/%d trials" % [cap_trials, cap_trials],
			capped_fires == cap_trials)


# ── Section 19: Mold Breaker bypass / Neutralizing Gas suppression ──────────
# Only the genuinely-reachable defender-role checks are tested here (Sturdy,
# Fluffy, Punk Rock's defense half, Tangled Feet) — Technician/Sheer
# Force/Mega Launcher/Stakeout are breakable=true in .tres data (matching source)
# but structurally unreachable attacker-self-checks in this project, same
# reachability class as [M17j]'s Sticky Hold (not given a bypass test, since there is
# no reachable interaction to test).

func _test_section_19_mold_breaker_and_neutralizing_gas() -> void:
	var mold_breaker := _load_ability(104)
	var sturdy := _load_ability(5)
	var fluffy := _load_ability(218)
	var tangled_feet := _load_ability(77)
	var tackle := _load_move(33)

	var mb_attacker := _make_mon("MBAttackerN5", [TypeChart.TYPE_NORMAL])
	mb_attacker.ability = mold_breaker

	# Sturdy bypass: a lethal hit from a Mold-Breaker attacker still fully KOs.
	var sturdy_mon := _make_mon("MBSturdyTarget", [TypeChart.TYPE_NORMAL], 100, 40, 40, 40, 40, 40)
	sturdy_mon.ability = sturdy
	_chk("S19.01 Mold Breaker bypasses Sturdy's survive-at-1HP",
			AbilityManager.effective_ability_id(sturdy_mon, false, mb_attacker) != AbilityManager.ABILITY_STURDY)

	# Fluffy bypass: contact-move damage-halving no longer applies.
	var fluffy_mon := _make_mon("MBFluffyTarget", [TypeChart.TYPE_NORMAL])
	fluffy_mon.ability = fluffy
	var contact_move := _synth_move(60, 0)
	contact_move.makes_contact = true
	var mb_mod: int = AbilityManager.defense_damage_modifier_uq412(
			fluffy_mon, contact_move, 1.0, DamageCalculator.WEATHER_NONE, null, false, mb_attacker)
	_chk("S19.02 Mold Breaker bypasses Fluffy's contact damage-halving", mb_mod == 4096)

	# Tangled Feet bypass.
	var tf_mon := _make_mon("MBTangledFeetTarget", [TypeChart.TYPE_NORMAL])
	tf_mon.ability = tangled_feet
	tf_mon.confusion_turns = 3
	var mb_acc: int = AbilityManager.accuracy_modifier_percent(
			mb_attacker, tackle, false, tf_mon, DamageCalculator.WEATHER_NONE)
	_chk("S19.03 Mold Breaker bypasses Tangled Feet's accuracy reduction", mb_acc == 100)

	# Neutralizing Gas suppression (a representative sample, not all 17).
	var iron_fist_mon := _make_mon("NGIronFistN5", [TypeChart.TYPE_NORMAL])
	iron_fist_mon.ability = _load_ability(89)
	var punching := _synth_move(60, 0)
	punching.punching_move = true
	var target := _make_mon("NGTargetN5", [TypeChart.TYPE_NORMAL])
	_chk("S19.04 Neutralizing Gas suppresses Iron Fist's power boost",
			AbilityManager.move_power_modifier_uq412(iron_fist_mon, punching, DamageCalculator.WEATHER_NONE, null, true) == 4096)

	var sl_mon := _make_mon("NGSuperLuckN5", [TypeChart.TYPE_NORMAL])
	sl_mon.ability = _load_ability(105)
	_chk("S19.05 Neutralizing Gas suppresses Super Luck at the effective_ability_id " +
			"chokepoint (the same read DamageCalculator's crit-stage bonus consults — " +
			"not re-tested via a full probabilistic sample here, per S12's own note " +
			"that force_crit bypasses the roll entirely and can't discriminate this)",
			AbilityManager.effective_ability_id(sl_mon, true) != AbilityManager.ABILITY_SUPER_LUCK)


# ── Section 20: Negative control ─────────────────────────────────────────────

func _test_section_20_negative_control() -> void:
	var tackle := _load_move(33)
	var plain := _make_mon("PlainN5", [TypeChart.TYPE_NORMAL])
	var target := _make_mon("PlainTargetN5", [TypeChart.TYPE_NORMAL])

	var baseline: Dictionary = DamageCalculator.calculate(plain, target, tackle, 100, false)
	_chk("S20.01 a plain Pokémon with none of this tier's abilities deals ordinary damage",
			baseline["damage"] > 0)
	_chk("S20.02 a plain Pokémon's accuracy modifier is unaffected",
			AbilityManager.accuracy_modifier_percent(plain, tackle) == 100)
	_chk("S20.03 a plain Pokémon's attack modifier is unaffected",
			AbilityManager.attack_modifier_uq412(plain, tackle) == 4096)
	_chk("S20.04 a plain Pokémon's move-power modifier is unaffected",
			AbilityManager.move_power_modifier_uq412(plain, tackle, DamageCalculator.WEATHER_NONE) == 4096)
