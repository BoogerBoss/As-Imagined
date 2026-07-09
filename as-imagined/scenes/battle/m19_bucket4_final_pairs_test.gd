extends Node

# [M19-steal-stats] / [M19-ally-targeting-stat-change] — Bucket 4's two
# cleanly-buildable remaining sub-groups, closing them out:
#   - M19-steal-stats: Spectral Thief(666)
#   - M19-ally-targeting-stat-change: Howl(336), Aromatic Mist(597), Coaching(739)
#
# Two corrections found during Step 0, both explicitly anticipated by the
# task itself:
#   - Spectral Thief does NOT reuse Opportunist's pattern (Opportunist reacts
#     to a fresh stat-RISE event without touching the original mon's stage;
#     Spectral Thief snapshots-and-transfers ALL 7 currently-positive stages,
#     zeroing the target's own stage, dispatched via preAttackEffect=TRUE —
#     fires regardless of the move's own subsequent accuracy result).
#   - "No ally-targeting stat-change mechanism exists in any form" was WRONG
#     — Helping Hand already establishes exactly this shape (TARGET_ALLY,
#     fails if not doubles), reused directly via the pre-existing _get_ally.
#
# Ground truth: reference/pokeemerald_expansion/src/data/moves_info.h,
# battle_script_commands.c :: MOVE_EFFECT_STEAL_STATS (L3347-3366),
# include/constants/pokemon.h :: NUM_BATTLE_STATS.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_data_integrity()
	_test_spectral_thief_steal()
	_test_spectral_thief_discriminators()
	_test_aromatic_mist_coaching_ally_only()
	_test_howl_self_and_ally()

	var total := _pass + _fail
	print("m19_bucket4_final_pairs_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


func _load_move(id: int) -> MoveData:
	return load("res://data/moves/move_%04d.tres" % id) as MoveData


func _load_ability(id: int) -> AbilityData:
	return load("res://data/abilities/ability_%04d.tres" % id) as AbilityData


func _make_mon(mon_name: String, types: Array[int], base_hp: int = 100, base_atk: int = 60,
		base_def: int = 60, base_spatk: int = 60, base_spdef: int = 60,
		base_spd: int = 60) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types = types
	sp.base_hp         = base_hp
	sp.base_attack     = base_atk
	sp.base_defense    = base_def
	sp.base_sp_attack  = base_spatk
	sp.base_sp_defense = base_spdef
	sp.base_speed      = base_spd
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])


func _make_bm() -> BattleManager:
	var bm := BattleManager.new()
	add_child(bm)
	return bm


func _doubles_party(m0: BattlePokemon, m1: BattlePokemon) -> BattleParty:
	var p := BattleParty.new()
	p.members = [m0, m1]
	p.active_indices.append(1)
	return p


# ── Section A: data integrity (all 4 moves) ─────────────────────────────────

func _test_data_integrity() -> void:
	var spectral_thief := _load_move(666)
	_chk("666 Spectral Thief: 90/100/10 Ghost physical + steals_positive_stat_stages",
			spectral_thief.move_name == "Spectral Thief" and spectral_thief.power == 90
					and spectral_thief.accuracy == 100 and spectral_thief.pp == 10
					and spectral_thief.type == TypeChart.TYPE_GHOST and spectral_thief.category == 0
					and spectral_thief.makes_contact and spectral_thief.ignores_substitute
					and spectral_thief.steals_positive_stat_stages)

	var howl := _load_move(336)
	_chk("336 Howl: 0/0/40 Normal status, +1 Atk self, sound_move, also_boosts_ally",
			howl.move_name == "Howl" and howl.power == 0 and howl.pp == 40
					and howl.type == TypeChart.TYPE_NORMAL and howl.sound_move
					and howl.ignores_protect and howl.stat_change_stat == BattlePokemon.STAGE_ATK
					and howl.stat_change_amount == 1 and howl.stat_change_self
					and howl.also_boosts_ally and not howl.stat_change_target_ally)

	var aromatic_mist := _load_move(597)
	_chk("597 Aromatic Mist: 0/0/20 Fairy status, +1 SpDef ally-only, NOT self",
			aromatic_mist.move_name == "Aromatic Mist" and aromatic_mist.type == TypeChart.TYPE_FAIRY
					and aromatic_mist.pp == 20 and aromatic_mist.stat_change_stat == BattlePokemon.STAGE_SPDEF
					and aromatic_mist.stat_change_amount == 1 and not aromatic_mist.stat_change_self
					and aromatic_mist.stat_change_target_ally and not aromatic_mist.also_boosts_ally)

	var coaching := _load_move(739)
	_chk("739 Coaching: 0/0/10 Fighting status, +1 Atk/+1 Def ally-only, NOT self",
			coaching.move_name == "Coaching" and coaching.type == TypeChart.TYPE_FIGHTING
					and coaching.pp == 10 and coaching.stat_change_stat == BattlePokemon.STAGE_ATK
					and coaching.stat_change_amount == 1 and not coaching.stat_change_self
					and coaching.stat_change_target_ally
					and coaching.extra_stat_change_stats == [BattlePokemon.STAGE_DEF]
					and coaching.extra_stat_change_amounts == [1])


# ── M19-steal-stats: Spectral Thief steals all positive stages, all 7 ───────

func _test_spectral_thief_steal() -> void:
	var spectral_thief := _load_move(666)
	var tackle := _load_move(33)
	# Water-type defender: neutral to Ghost (Normal would be a flat 0x immunity
	# per CLAUDE.md's own "type immunity precedes ability logic" convention —
	# Ghost-type moves are immune against Normal-type defenders).
	var atk := _make_mon("STAtk", [TypeChart.TYPE_GHOST], 100, 100, 60, 60, 60, 100)
	atk.add_move(spectral_thief)
	var def := _make_mon("STDef", [TypeChart.TYPE_WATER], 300, 60, 60, 60, 60, 40)
	def.add_move(tackle)
	# Give the defender positive stages on several (not all) of the 7 stats,
	# including Accuracy/Evasion — the discriminator vs. Starf Berry's
	# narrower 5-stat pool.
	def.stat_stages[BattlePokemon.STAGE_ATK] = 2
	def.stat_stages[BattlePokemon.STAGE_DEF] = 0  # untouched — must stay 0, not stolen
	def.stat_stages[BattlePokemon.STAGE_SPEED] = 1
	def.stat_stages[BattlePokemon.STAGE_ACCURACY] = 3
	def.stat_stages[BattlePokemon.STAGE_EVASION] = -2  # negative — must NOT be touched

	var bm := _make_bm()
	bm._force_hit = true
	var events := []
	bm.stat_stage_changed.connect(func(mon, stat, amt): events.push_back([mon, stat, amt]))
	bm.start_battle(atk, def)

	var atk_events := events.filter(func(e): return e[0] == atk)
	var def_events := events.filter(func(e): return e[0] == def)

	_chk("S.01 attacker gains Atk +2 (stolen)",
			atk_events.any(func(e): return e[1] == BattlePokemon.STAGE_ATK and e[2] == 2))
	_chk("S.02 attacker gains Speed +1 (stolen)",
			atk_events.any(func(e): return e[1] == BattlePokemon.STAGE_SPEED and e[2] == 1))
	_chk("S.03 attacker gains Accuracy +3 (stolen) — the key Starf-Berry discriminator, " +
			"proving the steal covers ALL 7 stats, not just the narrower 5-stat pool",
			atk_events.any(func(e): return e[1] == BattlePokemon.STAGE_ACCURACY and e[2] == 3))
	_chk("S.04 defender's Atk stage zeroed (delta -2 emitted)",
			def_events.any(func(e): return e[1] == BattlePokemon.STAGE_ATK and e[2] == -2))
	_chk("S.05 defender's Speed stage zeroed (delta -1 emitted)",
			def_events.any(func(e): return e[1] == BattlePokemon.STAGE_SPEED and e[2] == -1))
	_chk("S.06 defender's Accuracy stage zeroed (delta -3 emitted)",
			def_events.any(func(e): return e[1] == BattlePokemon.STAGE_ACCURACY and e[2] == -3))
	_chk("S.07 discriminator: Defense (already 0) never emits a change for either mon",
			not events.any(func(e): return e[1] == BattlePokemon.STAGE_DEF))
	_chk("S.08 discriminator: a NEGATIVE stage (Evasion -2) is never stolen, never touched",
			not events.any(func(e): return e[1] == BattlePokemon.STAGE_EVASION))
	_chk("S.09 defender's own negative Evasion stage is untouched after the battle's first hit",
			def.stat_stages[BattlePokemon.STAGE_EVASION] == -2)


func _test_spectral_thief_discriminators() -> void:
	var spectral_thief := _load_move(666)
	var tackle := _load_move(33)

	# (i) Fires even on a forced MISS — preAttackEffect is unconditional on
	# the move's own subsequent accuracy roll.
	var atk := _make_mon("STMissAtk", [TypeChart.TYPE_GHOST], 100, 100, 60, 60, 60, 100)
	atk.add_move(spectral_thief)
	var def := _make_mon("STMissDef", [TypeChart.TYPE_WATER], 300, 60, 60, 60, 60, 40)
	def.add_move(tackle)
	def.stat_stages[BattlePokemon.STAGE_ATK] = 1

	var bm := _make_bm()
	bm._force_hit = false  # the move itself will MISS
	var stolen := [false]
	bm.stat_stage_changed.connect(func(mon, stat, amt):
		if mon == atk and stat == BattlePokemon.STAGE_ATK and amt == 1 and not stolen[0]:
			stolen[0] = true)
	var missed := [false]
	bm.move_missed.connect(func(a, _reason):
		if a == atk and not missed[0]:
			missed[0] = true)
	bm.start_battle(atk, def)
	_chk("D.01 Spectral Thief's own accuracy roll genuinely missed (baseline)", missed[0] == true)
	_chk("D.02 the steal STILL fired despite the move missing — preAttackEffect is " +
			"unconditional on hit/miss", stolen[0] == true)

	# (ii) Attacker already at +6 on a given stat: per-stat gate, no steal
	# for THAT stat, but other stats still steal normally.
	var atk2 := _make_mon("STCapAtk", [TypeChart.TYPE_GHOST], 100, 100, 60, 60, 60, 100)
	atk2.add_move(spectral_thief)
	atk2.stat_stages[BattlePokemon.STAGE_ATK] = 6
	var def2 := _make_mon("STCapDef", [TypeChart.TYPE_WATER], 300, 60, 60, 60, 60, 40)
	def2.add_move(tackle)
	def2.stat_stages[BattlePokemon.STAGE_ATK] = 3
	def2.stat_stages[BattlePokemon.STAGE_DEF] = 2

	var bm2 := _make_bm()
	bm2._force_hit = true
	var events2 := []
	bm2.stat_stage_changed.connect(func(mon, stat, amt): events2.push_back([mon, stat, amt]))
	bm2.start_battle(atk2, def2)
	var atk2_events := events2.filter(func(e): return e[0] == atk2)
	var def2_events := events2.filter(func(e): return e[0] == def2)
	_chk("D.03 attacker already at +6 Atk: no Atk steal for the attacker (per-stat gate)",
			not atk2_events.any(func(e): return e[1] == BattlePokemon.STAGE_ATK))
	# Source (battle_script_commands.c :: MOVE_EFFECT_STEAL_STATS, L3355):
	# `gBattleMons[battlerAtk].statStages[stat] != MAX_STAT_STAGE` gates BOTH
	# halves of the transfer together — when the attacker is already capped
	# on a stat, the defender's own matching stage is NOT zeroed either (the
	# whole per-stat steal is skipped, not just the attacker's own gain).
	_chk("D.04 when the attacker is already capped on Atk, the DEFENDER's +3 Atk is " +
			"correspondingly left UNTOUCHED too — the per-stat gate covers both halves " +
			"of the transfer together, confirmed against source directly",
			not def2_events.any(func(e): return e[1] == BattlePokemon.STAGE_ATK)
					and def2.stat_stages[BattlePokemon.STAGE_ATK] == 3)
	_chk("D.05 the OTHER stat (Def +2) still steals normally, proving this is a per-stat " +
			"gate, not a whole-move skip",
			atk2_events.any(func(e): return e[1] == BattlePokemon.STAGE_DEF and e[2] == 2))

	# (iii) Type immunity blocks the steal specifically, but the move still
	# proceeds to its own (zero-damage) resolution rather than aborting the
	# turn like Protect does. Ghost-type moves are flatly immune against a
	# Normal-type defender (TypeChart.TABLE row 8, col 1 = 0.0) — this
	# project's GENERAL damaging-move path has no distinct "immune" signal
	# for an ordinary 0x hit (see this function's own neighboring
	# crashes_on_miss-only pre-check comment in battle_manager.gd); it just
	# flows through as move_executed with amount=0.
	var atk3 := _make_mon("STImmuneAtk", [TypeChart.TYPE_GHOST], 100, 100, 60, 60, 60, 100)
	atk3.add_move(spectral_thief)
	var def3 := _make_mon("STImmuneDef", [TypeChart.TYPE_NORMAL], 300, 60, 60, 60, 60, 40)
	def3.add_move(tackle)
	def3.stat_stages[BattlePokemon.STAGE_ATK] = 2

	var bm3 := _make_bm()
	bm3._force_hit = true
	var stolen3 := [false]
	bm3.stat_stage_changed.connect(func(mon, stat, _amt):
		if mon == atk3 and stat == BattlePokemon.STAGE_ATK:
			stolen3[0] = true)
	var executed3 := [false, -1]
	bm3.move_executed.connect(func(a, _d, _m, amt):
		if a == atk3 and not executed3[0]:
			executed3[0] = true
			executed3[1] = amt)
	bm3.start_battle(atk3, def3)
	_chk("D.06 Ghost-type Spectral Thief connects (as a move) against a Normal-type " +
			"defender but deals 0 damage — the flat type immunity (%s)" % [executed3],
			executed3[0] == true and executed3[1] == 0)
	_chk("D.07 type immunity blocks the steal specifically — no stat was stolen",
			stolen3[0] == false)


# ── M19-ally-targeting-stat-change: Aromatic Mist / Coaching, ally-only ─────

func _test_aromatic_mist_coaching_ally_only() -> void:
	var aromatic_mist := _load_move(597)
	var coaching := _load_move(739)
	var tackle := _load_move(33)

	# (i) Singles: fails entirely, no target to buff (no ally exists).
	var atk := _make_mon("AMSinglesAtk", [TypeChart.TYPE_FAIRY], 100, 60, 60, 60, 60, 100)
	atk.add_move(aromatic_mist)
	var def := _make_mon("AMSinglesDef", [TypeChart.TYPE_NORMAL], 200, 60, 60, 60, 60, 40)
	def.add_move(tackle)

	var bm := _make_bm()
	var failed := [false, ""]
	bm.move_effect_failed.connect(func(mon, reason):
		if mon == atk and not failed[0]:
			failed[0] = true
			failed[1] = reason)
	var self_boosted := [false]
	bm.stat_stage_changed.connect(func(mon, _stat, _amt):
		if mon == atk:
			self_boosted[0] = true)
	bm.start_battle(atk, def)
	_chk("A.01 Aromatic Mist fails entirely in singles (%s)" % [failed],
			failed[0] == true and failed[1] == "not_doubles")
	_chk("A.02 discriminator: the user itself is never buffed (not TARGET_USER)",
			self_boosted[0] == false)

	# (ii) Doubles: buffs the ally's SpDef +1, never the user, never the foe.
	var attacker0 := _make_mon("AMDblAtk0", [TypeChart.TYPE_FAIRY], 100, 60, 60, 60, 60, 100)
	attacker0.add_move(aromatic_mist)
	var attacker1 := _make_mon("AMDblAtk1", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 20)
	attacker1.add_move(tackle)
	var opp0 := _make_mon("AMDblOpp0", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 40)
	opp0.add_move(tackle)
	var opp1 := _make_mon("AMDblOpp1", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 30)
	opp1.add_move(tackle)

	var bm2 := _make_bm()
	var events2 := []
	bm2.stat_stage_changed.connect(func(mon, stat, amt): events2.push_back([mon, stat, amt]))
	bm2.queue_move_targeted(0, 0, 2)  # attacker0 uses Aromatic Mist (ally-only, target arg unused, opp0 is a safe valid index)
	bm2.start_battle_doubles(_doubles_party(attacker0, attacker1), _doubles_party(opp0, opp1))

	var atk0_first_events := events2.filter(func(e): return e[0] == attacker1).slice(0, 1)
	_chk("A.03 the ALLY (attacker1) gains SpDef +1 from attacker0's Aromatic Mist",
			atk0_first_events.size() == 1 and atk0_first_events[0][1] == BattlePokemon.STAGE_SPDEF
					and atk0_first_events[0][2] == 1)
	_chk("A.04 discriminator: attacker0 (the user) never gains a stat change from its own " +
			"first move (only attacker1, its ally, does)",
			not (events2.slice(0, 1) as Array).any(func(e): return e[0] == attacker0))

	# (iii) Coaching's 2-stat payload on the ally: +1 Atk AND +1 Def, both landing
	# on the ally, neither on the user.
	var c_attacker0 := _make_mon("CoachDblAtk0", [TypeChart.TYPE_FIGHTING], 100, 60, 60, 60, 60, 100)
	c_attacker0.add_move(coaching)
	var c_attacker1 := _make_mon("CoachDblAtk1", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 20)
	c_attacker1.add_move(tackle)
	var c_opp0 := _make_mon("CoachDblOpp0", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 40)
	c_opp0.add_move(tackle)
	var c_opp1 := _make_mon("CoachDblOpp1", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 30)
	c_opp1.add_move(tackle)

	var bm3 := _make_bm()
	var events3 := []
	bm3.stat_stage_changed.connect(func(mon, stat, amt): events3.push_back([mon, stat, amt]))
	bm3.queue_move_targeted(0, 0, 2)
	bm3.start_battle_doubles(_doubles_party(c_attacker0, c_attacker1), _doubles_party(c_opp0, c_opp1))

	var first_two := events3.slice(0, 2)
	_chk("A.05 Coaching lands BOTH stats on the ally (Atk +1 and Def +1), none on the user",
			first_two.all(func(e): return e[0] == c_attacker1) and first_two.size() == 2
					and first_two.any(func(e): return e[1] == BattlePokemon.STAGE_ATK and e[2] == 1)
					and first_two.any(func(e): return e[1] == BattlePokemon.STAGE_DEF and e[2] == 1))


# ── M19-ally-targeting-stat-change: Howl — self ALWAYS, ally only in doubles ─

func _test_howl_self_and_ally() -> void:
	var howl := _load_move(336)
	var tackle := _load_move(33)

	# (i) Singles: self-buff applies normally, ally bolt-on is a no-op (no ally).
	var atk := _make_mon("HowlSinglesAtk", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 100)
	atk.add_move(howl)
	var def := _make_mon("HowlSinglesDef", [TypeChart.TYPE_NORMAL], 200, 60, 60, 60, 60, 40)
	def.add_move(tackle)

	var bm := _make_bm()
	var events := []
	bm.stat_stage_changed.connect(func(mon, stat, amt): events.push_back([mon, stat, amt]))
	bm.start_battle(atk, def)
	var first_event := events.slice(0, 1)
	_chk("H.01 Howl in singles: the user gains Atk +1 (ordinary self-buff, unaffected " +
			"by the ally bolt-on's own no-ally no-op)",
			first_event.size() == 1 and first_event[0][0] == atk
					and first_event[0][1] == BattlePokemon.STAGE_ATK and first_event[0][2] == 1)

	# (ii) Doubles: self-buff AND the ally bolt-on both fire, same stat/amount.
	var attacker0 := _make_mon("HowlDblAtk0", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 100)
	attacker0.add_move(howl)
	var attacker1 := _make_mon("HowlDblAtk1", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 20)
	attacker1.add_move(tackle)
	var opp0 := _make_mon("HowlDblOpp0", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 40)
	opp0.add_move(tackle)
	var opp1 := _make_mon("HowlDblOpp1", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 30)
	opp1.add_move(tackle)

	var bm2 := _make_bm()
	var events2 := []
	bm2.stat_stage_changed.connect(func(mon, stat, amt): events2.push_back([mon, stat, amt]))
	bm2.queue_move_targeted(0, 0, 2)
	bm2.start_battle_doubles(_doubles_party(attacker0, attacker1), _doubles_party(opp0, opp1))

	var first_two := events2.slice(0, 2)
	_chk("H.02 Howl in doubles: BOTH the user (attacker0) and its ally (attacker1) gain " +
			"Atk +1 from the same use",
			first_two.size() == 2
					and first_two.any(func(e): return e[0] == attacker0 and e[1] == BattlePokemon.STAGE_ATK and e[2] == 1)
					and first_two.any(func(e): return e[0] == attacker1 and e[1] == BattlePokemon.STAGE_ATK and e[2] == 1))
