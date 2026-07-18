extends Node

# [M20] I.1 (Gen VII+ base Exp formula, source-verified) + I.2 (custom
# participant-distribution table) + I.4 (Difficulty Setting) — the first
# real Exp-gain/leveling infrastructure this project has ever built. I.3
# (the automatic 20% non-participant bonus) remains explicitly DEFERRED,
# not built here — see docs/m20_recon.md Section I.3 and docs/decisions.md's
# `[M20 EXP design]` entry.
#
# Full source citations for I.1 live in docs/decisions.md's `[M20 EXP
# design]` entry and docs/m20_recon.md's Section I — not repeated here in
# full, only the load-bearing facts this suite exists to prove:
#  - EXP_SCALING_FACTORS is ported VERBATIM from source's
#    sExperienceScalingFactors (battle_script_commands.c:100-311), NOT
#    recomputed via sqrt() at runtime — the real per-index formula is
#    floor(i^2*sqrt(i)/4), NOT floor(sqrt(i)*i^2) (the missing /4 is
#    material, not a constant that cancels out of the ratio).
#  - B carries ZERO modifiers this session (Lucky Egg/Traded/Affection/
#    Exp Charm/unevolved-bonus all confirmed unbuilt in this project).
#  - Participant eligibility mirrors source's two-layer rule exactly:
#    _exp_participants[field_slot] (ever sent out against THIS specific
#    opponent instance, reset when a NEW opponent occupies that slot) AND
#    alive right now (current_hp > 0) at award time.
#  - I.2/I.4 are original design, not source-verified, applied as two
#    further truncating multiplies after I.1's own "+1".

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_data_integrity()
	_test_compute_exp_award_direct()
	_test_single_participant_integration()
	_test_doubles_two_participant_integration()
	_test_switched_out_but_alive_still_counts()
	_test_fainted_before_kill_excluded()
	_test_opponent_switch_in_resets_tracking()
	_test_difficulty_setting_end_to_end()
	_test_player_side_faint_negative_control()
	_test_real_species_data_integration()

	var total := _pass + _fail
	print("m20_exp_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


func _make_mon(mon_name: String, level: int, exp_yield: int,
		base_hp: int = 100, base_atk: int = 60, base_def: int = 60,
		base_spatk: int = 60, base_spdef: int = 60, base_spd: int = 60,
		mon_type: int = TypeChart.TYPE_NORMAL) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types = [mon_type]
	sp.base_hp         = base_hp
	sp.base_attack     = base_atk
	sp.base_defense    = base_def
	sp.base_sp_attack  = base_spatk
	sp.base_sp_defense = base_spdef
	sp.base_speed      = base_spd
	sp.exp_yield = exp_yield
	return BattlePokemon.from_species(sp, level, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])


func _make_bm() -> BattleManager:
	var bm := BattleManager.new()
	add_child(bm)
	return bm


func _load_move(id: int) -> MoveData:
	return load("res://data/moves/move_%04d.tres" % id) as MoveData


# ── Section A: data integrity ────────────────────────────────────────────

func _test_data_integrity() -> void:
	_chk("A.1 EXP_SCALING_FACTORS has exactly 211 entries",
			BattleManager.EXP_SCALING_FACTORS.size() == 211)
	_chk("A.2 EXP_SCALING_FACTORS[0]==0, [1]==0, [2]==1 (verified against floor(i^2.5/4))",
			BattleManager.EXP_SCALING_FACTORS[0] == 0
			and BattleManager.EXP_SCALING_FACTORS[1] == 0
			and BattleManager.EXP_SCALING_FACTORS[2] == 1)
	_chk("A.3 EXP_SCALING_FACTORS[11]==100 (source-verified spot check)",
			BattleManager.EXP_SCALING_FACTORS[11] == 100)
	_chk("A.4 EXP_SCALING_FACTORS[20]==447 (source-verified spot check)",
			BattleManager.EXP_SCALING_FACTORS[20] == 447)
	_chk("A.5 EXP_SCALING_FACTORS[100]==25000 (source-verified spot check)",
			BattleManager.EXP_SCALING_FACTORS[100] == 25000)
	_chk("A.6 EXP_SCALING_FACTORS[210]==159767 (last entry, source-verified)",
			BattleManager.EXP_SCALING_FACTORS[210] == 159767)
	_chk("A.7 DISTRIBUTION_PERCENT: 1->100/2->65/3->55/4->50/5->45/6->40",
			BattleManager.DISTRIBUTION_PERCENT[1] == 100
			and BattleManager.DISTRIBUTION_PERCENT[2] == 65
			and BattleManager.DISTRIBUTION_PERCENT[3] == 55
			and BattleManager.DISTRIBUTION_PERCENT[4] == 50
			and BattleManager.DISTRIBUTION_PERCENT[5] == 45
			and BattleManager.DISTRIBUTION_PERCENT[6] == 40)
	_chk("A.8 DifficultyMode is a genuine mutually-exclusive enum with 3 values",
			BattleManager.DifficultyMode.NORMAL == 0
			and BattleManager.DifficultyMode.HARD == 1
			and BattleManager.DifficultyMode.CASUAL == 2)
	_chk("A.9 DIFFICULTY_PERCENT: NORMAL->100/HARD->50/CASUAL->135",
			BattleManager.DIFFICULTY_PERCENT[BattleManager.DifficultyMode.NORMAL] == 100
			and BattleManager.DIFFICULTY_PERCENT[BattleManager.DifficultyMode.HARD] == 50
			and BattleManager.DIFFICULTY_PERCENT[BattleManager.DifficultyMode.CASUAL] == 135)
	_chk("A.10 BattleManager defaults to DifficultyMode.NORMAL",
			_make_bm().difficulty_mode == BattleManager.DifficultyMode.NORMAL)
	_chk("A.11 BattlePokemon.current_exp defaults to 0",
			_make_mon("Test", 10, 71).current_exp == 0)


# ── Section B: _compute_exp_award direct unit tests ──────────────────────

func _test_compute_exp_award_direct() -> void:
	var bm := _make_bm()
	var fainted := _make_mon("Fainted", 10, 71)
	var recipient := _make_mon("Recipient", 10, 64)  # exp_yield irrelevant for a recipient

	# Same level (fainted==recipient): A_index==C_index, ratio==1, so the
	# result reduces to exactly B+1 — a clean self-check independent of the
	# scaling table's own correctness.
	# B = (71*10)/5 = 142; +1 = 143.
	_chk("B.1 same-level base value == B+1 == 143 (1 participant, NORMAL)",
			bm._compute_exp_award(fainted, recipient, 1) == 143)

	var fainted20 := _make_mon("Fainted20", 20, 71)
	var recipient10 := _make_mon("Recipient10", 10, 64)
	# Hand-verified (Python, docs/decisions.md's own worked example):
	# B=284, A_idx=50(4419), C_idx=40(2529) -> floor(284*4419/2529)+1 = 497.
	_chk("B.2 asymmetric levels (fainted 20, recipient 10) base value == 497 (1 participant)",
			bm._compute_exp_award(fainted20, recipient10, 1) == 497)
	_chk("B.3 same asymmetric case, 2 participants (65%): floor(497*65/100) == 323",
			bm._compute_exp_award(fainted20, recipient10, 2) == 323)

	var recipient15 := _make_mon("Recipient15", 15, 64)
	# B.4: a DIFFERENT recipient level, same fainted mon, computed
	# independently — confirms C uses THIS recipient's own level, not a
	# shared/opponent-only value. Hand-verified: base 370, dist65% -> 240.
	_chk("B.4 a different recipient's own level changes their own share (370 base, not 497)",
			bm._compute_exp_award(fainted20, recipient15, 1) == 370)
	_chk("B.5 recipient15's own 2-participant share == 240 (independently computed, not r1's 323)",
			bm._compute_exp_award(fainted20, recipient15, 2) == 240)

	# B.6/B.7: Difficulty Setting is the LAST multiplicative step, after
	# distribution — verified directly against hand-computed values.
	bm.difficulty_mode = BattleManager.DifficultyMode.HARD
	_chk("B.6 HARD halves the post-distribution value: floor(323*50/100) == 161",
			bm._compute_exp_award(fainted20, recipient10, 2) == 161)
	bm.difficulty_mode = BattleManager.DifficultyMode.CASUAL
	_chk("B.7 CASUAL applies x1.35 to the post-distribution value: floor(323*135/100) == 436",
			bm._compute_exp_award(fainted20, recipient10, 2) == 436)

	# B.8: 3-participant distribution (55%), a third hand-verified data point
	# beyond just 1/2, confirming the table isn't hardcoded to only 2 cases.
	var bm2 := _make_bm()
	var fainted10b := _make_mon("Fainted10b", 10, 60)
	var recipient10b := _make_mon("Recipient10b", 10, 64)
	_chk("B.8 3-participant distribution (55%): floor(121*55/100) == 66",
			bm2._compute_exp_award(fainted10b, recipient10b, 3) == 66)


# ── Section C: full 1v1 wild-battle integration (single participant) ─────

func _test_single_participant_integration() -> void:
	var bm := _make_bm()
	bm._force_hit = true
	bm._force_roll = 100
	bm._force_crit = false
	var attacker := _make_mon("Attacker", 20, 64, 100, 100, 20, 20, 20, 100)
	attacker.moves = [_load_move(33)]  # Tackle
	attacker.current_pp = [attacker.moves[0].pp]
	var opponent := _make_mon("Opponent", 20, 71, 1, 20, 20, 20, 20, 1)

	var gained := [-1]
	bm.exp_gained.connect(func(recipient: BattlePokemon, amount: int):
		if gained[0] == -1:
			gained[0] = amount)

	bm.start_battle_with_parties(BattleParty.single(attacker), BattleParty.single(opponent))

	# Hand-verified: B=(71*20)/5=284, A_idx=50(4419), C_idx=20+20+10=50(4419)
	# -> ratio==1 (same level) -> 284+1=285. 1 participant (100%), NORMAL (100%).
	_chk("C.1 single-participant one-shot kill awards exp_gained with the expected amount",
			gained[0] == 285)
	_chk("C.2 attacker's own current_exp reflects the same amount",
			attacker.current_exp == 285)


# ── Section D: doubles, 2 participants, independently-computed shares ────

func _test_doubles_two_participant_integration() -> void:
	var bm := _make_bm()
	bm._force_hit = true
	bm._force_roll = 100
	bm._force_crit = false
	var a1 := _make_mon("A1", 20, 64, 100, 100, 20, 20, 20, 200)  # faster: acts first
	var a2 := _make_mon("A2", 15, 64, 100, 20, 20, 20, 20, 50)    # different level
	a1.moves = [_load_move(33)]
	a1.current_pp = [a1.moves[0].pp]
	a2.moves = [_load_move(33)]
	a2.current_pp = [a2.moves[0].pp]
	var opponent := _make_mon("Opponent", 20, 71, 1, 20, 20, 20, 20, 1)
	# Doubles requires 2 active slots per side — this filler never gets
	# targeted (default doubles targeting hits the FIRST opposing slot,
	# index 2 in the combatant layout, which is `opponent`).
	var filler := _make_mon("Filler", 20, 1, 999, 20, 20, 20, 20, 1)

	var player_party := BattleParty.new()
	player_party.members = [a1, a2]
	player_party.active_indices = [0, 1]
	var opp_party := BattleParty.new()
	opp_party.members = [opponent, filler]
	opp_party.active_indices = [0, 1]

	var gains := {}
	bm.exp_gained.connect(func(recipient: BattlePokemon, amount: int):
		if not gains.has(recipient):
			gains[recipient] = amount)

	bm.start_battle_doubles(player_party, opp_party)
	# a1 (faster) kills the 1-HP opponent on turn 1; both a1 and a2 were
	# active against it from the start, so both are tracked participants.
	# a1 is the SAME level as the fainted opponent (20), so its own base
	# value is the same-level case from Section B/C (285); a2 is level 15,
	# the asymmetric case from Section B (370). Both hand-verified
	# independently, then scaled by the SAME 2-participant 65%:
	# a1: floor(285*65/100)=185. a2: floor(370*65/100)=240.
	# (`filler` eventually also faints in a later turn, once it's the only
	# remaining live opponent — harmless here, since `gains` only records
	# each recipient's FIRST award via its own `not gains.has(...)` guard,
	# the same first-occurrence-signal-capture convention this project's
	# testing conventions already establish for exactly this reason.)
	_chk("D.1 a1 (level 20, same as the fainted opponent) gets its own 65% share (185)",
			gains.get(a1, -1) == 185)
	_chk("D.2 a2 (level 15, didn't land the hit but was active) gets its own independent share (240)",
			gains.get(a2, -1) == 240)


# ── Section E: eligibility — switched-out-but-alive still counts; ───────
# ── fainted-before-the-kill does NOT count ───────────────────────────────

func _test_switched_out_but_alive_still_counts() -> void:
	var bm := _make_bm()
	var a := _make_mon("SwitchedOutA", 20, 64)
	var b := _make_mon("SwitchedInB", 20, 64)
	var opponent := _make_mon("Opp", 20, 71, 1, 20, 20, 20, 20, 1)
	bm._parties = [BattleParty.new(), BattleParty.single(opponent)]
	bm._parties[0].members = [a, b]
	bm._parties[0].active_indices = [0]
	bm._active_per_side = 1
	bm._combatants = [a, bm._parties[1].get_active()]
	bm._exp_participants = [[0]]  # A tracked from "battle start"

	# A switches out for B (A stays alive, benched) — B should be ADDED,
	# A should remain tracked (never removed by a mere switch-out).
	bm._do_voluntary_switch(0, 1)
	_chk("E.1 after switching A out for B (both alive), both are tracked participants",
			bm._exp_participants[0].has(0) and bm._exp_participants[0].has(1))

	var gains := {}
	bm.exp_gained.connect(func(recipient: BattlePokemon, amount: int):
		gains[recipient] = gains.get(recipient, 0) + amount)
	opponent.current_hp = 0
	bm._award_exp_for_fainted_opponent(opponent)
	_chk("E.2 A (benched but alive) still receives an Exp share despite not landing the hit",
			gains.has(a) and gains[a] > 0)
	_chk("E.3 B (the one currently active) also receives a share",
			gains.has(b) and gains[b] > 0)


func _test_fainted_before_kill_excluded() -> void:
	var bm := _make_bm()
	var a := _make_mon("FaintsEarlyA", 20, 64)
	var b := _make_mon("FinishesB", 20, 64)
	var opponent := _make_mon("Opp2", 20, 71, 1, 20, 20, 20, 20, 1)
	bm._parties = [BattleParty.new(), BattleParty.single(opponent)]
	bm._parties[0].members = [a, b]
	bm._parties[0].active_indices = [0]
	bm._active_per_side = 1
	bm._combatants = [a, bm._parties[1].get_active()]
	bm._exp_participants = [[0]]

	# A fainted earlier this same fight (still tracked, per Section G1 — the
	# bit is never cleared by fainting itself), then B replaces it and lands
	# the finishing hit. A must be excluded (current_hp <= 0 at award time).
	a.current_hp = 0
	bm._do_switch_in(0, 1)  # faint-replacement: B comes in for A

	var gains := {}
	bm.exp_gained.connect(func(recipient: BattlePokemon, amount: int):
		gains[recipient] = gains.get(recipient, 0) + amount)
	opponent.current_hp = 0
	bm._award_exp_for_fainted_opponent(opponent)
	_chk("E.4 A (fainted earlier this fight) receives NOTHING despite still being tracked",
			not gains.has(a))
	_chk("E.5 B (the live replacement) receives the full 1-participant share",
			gains.has(b) and gains[b] > 0)


# ── Section F: a NEW opponent occupying a field slot resets that slot's ──
# ── participant tracking, even for still-alive prior participants ────────

func _test_opponent_switch_in_resets_tracking() -> void:
	var bm := _make_bm()
	var a := _make_mon("ResetA", 20, 64)
	var b := _make_mon("ResetB", 20, 64)
	var opp1 := _make_mon("Opp1", 20, 60, 1, 20, 20, 20, 20, 1)
	var opp2 := _make_mon("Opp2", 20, 71, 1, 20, 20, 20, 20, 1)
	var opp_party := BattleParty.new()
	opp_party.members = [opp1, opp2]
	opp_party.active_indices = [0]

	bm._parties = [BattleParty.new(), opp_party]
	bm._parties[0].members = [a, b]
	bm._parties[0].active_indices = [0]
	bm._active_per_side = 1
	bm._combatants = [a, opp1]
	bm._exp_participants = [[0]]  # only A tracked so far

	# Player switches A -> B (both now tracked for opp1's slot).
	bm._do_voluntary_switch(0, 1)
	_chk("F.1 both A and B tracked against opp1 after the voluntary switch",
			bm._exp_participants[0].has(0) and bm._exp_participants[0].has(1))

	# opp1 faints (both A and B alive -> both get a 2-participant share).
	var gains1 := {}
	bm.exp_gained.connect(func(recipient: BattlePokemon, amount: int):
		gains1[recipient] = gains1.get(recipient, 0) + amount)
	opp1.current_hp = 0
	bm._award_exp_for_fainted_opponent(opp1)
	_chk("F.2 opp1's kill credits both A and B (2-participant split)",
			gains1.has(a) and gains1.has(b))

	# A new opponent (opp2) switches in at the SAME field slot — this must
	# RESET tracking to just whoever is CURRENTLY active (B), even though A
	# is still alive and was a legitimate participant against opp1.
	bm._do_forced_switch_in(1, 1, 0)
	_chk("F.3 opp2's switch-in resets the slot to just the currently-active player mon (B only)",
			bm._exp_participants[0] == [1])

	var gains2 := {}
	bm.exp_gained.connect(func(recipient: BattlePokemon, amount: int):
		gains2[recipient] = gains2.get(recipient, 0) + amount)
	opp2.current_hp = 0
	bm._award_exp_for_fainted_opponent(opp2)
	_chk("F.4 opp2's kill credits ONLY B, not A — confirms the reset, not carried-over history",
			gains2.has(b) and not gains2.has(a))


# ── Section G: Difficulty Setting applied end-to-end through a real battle ─

func _test_difficulty_setting_end_to_end() -> void:
	var bm := _make_bm()
	bm._force_hit = true
	bm._force_roll = 100
	bm._force_crit = false
	bm.difficulty_mode = BattleManager.DifficultyMode.HARD
	var attacker := _make_mon("HardAttacker", 20, 64, 100, 100, 20, 20, 20, 100)
	attacker.moves = [_load_move(33)]
	attacker.current_pp = [attacker.moves[0].pp]
	var opponent := _make_mon("HardOpp", 20, 71, 1, 20, 20, 20, 20, 1)

	var gained := [-1]
	bm.exp_gained.connect(func(_recipient: BattlePokemon, amount: int):
		if gained[0] == -1:
			gained[0] = amount)
	bm.start_battle_with_parties(BattleParty.single(attacker), BattleParty.single(opponent))
	# NORMAL would give 285 (Section C); HARD halves it: floor(285*50/100)=142.
	_chk("G.1 HARD difficulty measurably halves the real end-to-end award (142, not 285)",
			gained[0] == 142)


# ── Section H: a PLAYER-side faint never awards Exp (negative control) ──

func _test_player_side_faint_negative_control() -> void:
	var bm := _make_bm()
	var a := _make_mon("PlayerSideFaints", 20, 71)
	var opponent := _make_mon("StillAlive", 20, 64)
	bm._parties = [BattleParty.single(a), BattleParty.single(opponent)]
	bm._active_per_side = 1
	bm._combatants = [a, opponent]
	bm._exp_participants = [[0]]

	var fired := [false]
	bm.exp_gained.connect(func(_r: BattlePokemon, _amt: int): fired[0] = true)
	a.current_hp = 0
	bm._award_exp_for_fainted_opponent(a)
	_chk("H.1 a player-side faint never awards Exp (side gate, mirrors IsOnPlayerSide)",
			not fired[0])


# ── Section I: [M20a] real species data now flows correctly end-to-end ───
# `PokemonRegistry` is a raw JSON dictionary API (no production code converts
# a row into a real `PokemonSpecies` object yet — confirmed, a known,
# disclosed gap, not this test's job to fix) — so this test does the minimal
# JSON-row -> PokemonSpecies field copy itself, purely to prove the newly-
# regenerated real exp_yield values produce the mathematically expected
# result through the SAME `_compute_exp_award` every other section already
# exercises, closing the loop between M20a's data and M20's formula.

func _species_from_registry(dex: int) -> PokemonSpecies:
	var data: Dictionary = PokemonRegistry.get_species(dex)
	var sp := PokemonSpecies.new()
	sp.species_name = data.get("name", "")
	sp.exp_yield = data.get("exp_yield", 0)
	return sp


func _test_real_species_data_integration() -> void:
	var bm := _make_bm()

	# Same-level self-check (A_index==C_index, reduces cleanly to B+1) keeps
	# each spot-check independent of anything but exp_yield itself.
	var bulbasaur := BattlePokemon.from_species(_species_from_registry(1), 10)
	var recipient10 := BattlePokemon.from_species(_species_from_registry(1), 10)
	_chk("I.1 Bulbasaur (real exp_yield=64): B=(64*10)/5=128, +1=129",
			bulbasaur.species.exp_yield == 64
			and bm._compute_exp_award(bulbasaur, recipient10, 1) == 129)

	var ivysaur := BattlePokemon.from_species(_species_from_registry(2), 10)
	_chk("I.2 Ivysaur (real exp_yield=142, the GEN_5+ ternary branch): B=284, +1=285",
			ivysaur.species.exp_yield == 142
			and bm._compute_exp_award(ivysaur, recipient10, 1) == 285)

	var charizard := BattlePokemon.from_species(_species_from_registry(6), 10)
	_chk("I.3 Charizard (real exp_yield=267, the CHARIZARD_EXP_YIELD named macro): B=534, +1=535",
			charizard.species.exp_yield == 267
			and bm._compute_exp_award(charizard, recipient10, 1) == 535)
