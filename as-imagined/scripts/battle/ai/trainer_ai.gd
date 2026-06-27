class_name TrainerAI
extends RefCounted

# Trainer AI — rule-based move/switch scorer.
#
# Confirmed: the pokeemerald-expansion AI is flag-driven and scoring-based, NOT
# deep search. Verified in ChooseMoveOrAction_Singles (battle_ai_main.c L856):
# iterate over active AI_FLAG bits, run corresponding scoring pass for each move,
# pick highest score, break ties randomly.
#
# Two tiers implemented:
#   BASIC — AI_FLAG_BASIC_TRAINER (source constants/battle_ai.h L46):
#            AI_FLAG_CHECK_BAD_MOVE | AI_FLAG_TRY_TO_FAINT | AI_FLAG_CHECK_VIABILITY
#            Move scoring only. No proactive switches.
#   SMART — adds AI_FLAG_SMART_SWITCHING (source L24):
#            Includes ShouldSwitchIfAllMovesBad and ShouldSwitchIfHasBadOdds.
#
# Explicitly deferred (not implemented, documented in docs/decisions.md):
#   - Doubles AI (AI_FLAG_DOUBLE_BATTLE): no doubles engine yet.
#   - Item usage AI (battle_ai_items.c): no held items implemented.
#   - Weather-based scoring: weather is still stubbed (M8 decision).
#   - AI_FLAG_PREDICT_SWITCH, AI_FLAG_OMNISCIENT, and other advanced flags:
#     scope beyond basic + smart tier.

enum Tier { BASIC, SMART }

# Score constants — source: include/battle_ai_main.h L21-41
const AI_SCORE_DEFAULT: int = 100  # constants/battle_ai.h L57
const FAST_KILL: int        = 6    # AI faster and faints target
const SLOW_KILL: int        = 4    # AI slower and faints target
const BEST_EFFECT: int      = 4    # 4× effective or very strong secondary
const DECENT_EFFECT: int    = 2    # 2× effective or useful secondary

var tier: Tier = Tier.BASIC

# Test determinism: override RNG for move tie-breaking.
# Source: RandomUniform(RNG_AI_SCORE_TIE_SINGLES) in ChooseMoveOrAction_Singles L915.
# -1 = real RNG; ≥0 = index into the tied-best array.
var _force_tie_rng: int = -1

# Test determinism: override the switch-or-stay roll in ShouldSwitchIfHasBadOdds.
# Source: RandomPercentage(RNG_AI_SWITCH_HASBADODDS, ...) in battle_ai_switch.c L391.
# -1 = real RNG (50% chance per source config); 0 = always stay; 1 = always switch.
var _force_switch_rng: int = -1

# M11 test seams for deterministic damage estimates in AI scoring.
# The AI's damage estimate for KO detection uses DamageCalculator.calculate; pinning
# force_roll and force_crit makes the AI's damage output deterministic in tests.
# -1 / null = real RNG (default). Pinned values are only set by test code.
var _force_roll: int = -1         # passed as force_roll to DamageCalculator.calculate
var _force_crit: Variant = null   # passed as force_crit to DamageCalculator.calculate


# ── Main entry: choose an action for this turn ────────────────────────────────
#
# Source: ChooseMoveOrAction_Singles (battle_ai_main.c L856) for move scoring.
#         AI_TrySwitchOrUseItem (L456) for the switch-vs-attack decision.
# M11: weather parameter passes the current field weather so DamageCalculator picks
#   it up automatically — no AI-specific weather handling needed (proof that the M10
#   architecture pays off: the AI calls the real damage calc, not a separate estimate).
# Returns {"type": "move", "index": int} or {"type": "switch", "slot": int}.

func choose_action(attacker: BattlePokemon, defender: BattlePokemon,
		my_party: BattleParty, _opp_party: BattleParty,
		weather: int = DamageCalculator.WEATHER_NONE) -> Dictionary:
	# SMART tier: proactive switch evaluation before move scoring.
	# Basic trainers never proactively switch in source — that logic is gated
	# behind AI_FLAG_SMART_SWITCHING which is absent from AI_FLAG_BASIC_TRAINER.
	# Source: AI_TrySwitchOrUseItem L456, gAiLogicData->shouldSwitch.
	if tier == Tier.SMART:
		var switch_slot: int = _should_switch(attacker, defender, my_party, weather)
		if switch_slot >= 0:
			return {"type": "switch", "slot": switch_slot}

	# Score each available move, pick best.
	# Source: ChooseMoveOrAction_Singles runs each enabled AI_FLAG pass.
	var scores: Array[int] = []
	for i in range(attacker.moves.size()):
		var move: MoveData = attacker.moves[i]
		if move == null:
			scores.append(-999)
		else:
			scores.append(_score_move(attacker, defender, move, weather))

	return {"type": "move", "index": _pick_best(scores, attacker.moves)}


# ── Faint replacement: which party slot to send in ────────────────────────────
#
# Source: GetSwitchinCandidate(SWITCHIN_CONSIDER_MOST_SUITABLE) in
#   battle_ai_switch.c L55+. Simplified: pick the party member whose moves
#   have the highest type effectiveness against the current opponent.
#   Falls back to first alive non-active if no move data available.

func choose_replacement(my_party: BattleParty, opponent: BattlePokemon) -> int:
	var best_slot: int = -1
	var best_eff: float = -1.0
	for i in range(my_party.members.size()):
		if i == my_party.active_index:
			continue
		var mon: BattlePokemon = my_party.members[i]
		if mon.fainted:
			continue
		var best_mon_eff: float = 0.0
		for move: MoveData in mon.moves:
			if move == null or move.category == 2 or move.power == 0:
				continue
			var eff: float = TypeChart.get_effectiveness(
					move.type, opponent.species.types)
			if eff > best_mon_eff:
				best_mon_eff = eff
		if best_mon_eff > best_eff:
			best_eff = best_mon_eff
			best_slot = i

	if best_slot >= 0:
		return best_slot
	return my_party.get_first_non_fainted_not_active()


# ── Move scoring ──────────────────────────────────────────────────────────────
#
# Three AI passes from source, faithfully simplified to what we've implemented:
#   1. AI_CheckBadMove  — penalise immunities and wasted status moves.
#   2. AI_TryToFaint    — bonus for KO moves.
#   3. AI_CheckViability (partial) — bonus for type advantage and useful status.

func _score_move(attacker: BattlePokemon, defender: BattlePokemon,
		move: MoveData, weather: int = DamageCalculator.WEATHER_NONE) -> int:
	var score: int = AI_SCORE_DEFAULT

	# ── Pass 1: AI_CheckBadMove (battle_ai_main.c L1201) ──────────────────────

	# Type immunity (includes Thunder Wave vs Ground via Electric→Ground = 0.0).
	# Source: L1294 — if (effectiveness == UQ_4_12(0.0)) RETURN_SCORE_MINUS(20).
	var effectiveness: float = TypeChart.get_effectiveness(
			move.type, defender.species.types)
	if effectiveness == 0.0:
		return score - 20  # nothing further redeems a type-immune move

	# Two-turn non-semi-invulnerable move when defender can KO us on their turn.
	# Source: L1254 — if (CanTargetFaintAi && IsTwoTurnNotSemiInvulnerableMove)
	#   RETURN_SCORE_MINUS(10). Semi-inv moves (Dig/Fly) gain invulnerability that
	#   partially offsets the cost, so we only penalise the non-inv variant here.
	if move.two_turn and move.semi_inv_state == MoveData.SEMI_INV_NONE:
		if _can_defender_ko_attacker(attacker, defender, weather):
			score -= 10

	# Pure status move: penalise if target already has a non-volatile status.
	# Source: L2933-2960 — AI_CanParalyze/AI_CanPoison/AI_CanBurn/AI_CanPutToSleep
	#   all return FALSE when gBattleMons[battlerDef].status1 already set → -10.
	if move.category == 2 and move.secondary_effect in [
			MoveData.SE_BURN, MoveData.SE_PARALYSIS, MoveData.SE_SLEEP,
			MoveData.SE_TOXIC, MoveData.SE_FREEZE]:
		if defender.status != BattlePokemon.STATUS_NONE:
			score -= 10

	# ── Pass 2: AI_TryToFaint (battle_ai_main.c L3000) ───────────────────────

	# Status moves always return early here: "if (IsBattleMoveStatus(move)) return score"
	# M11: DamageCalculator.calculate now receives weather so the estimated damage
	# automatically reflects the current field boost/reduction — no AI-specific logic needed.
	# _force_roll / _force_crit are null/-1 in production; pinnable in tests for determinism.
	if move.category != 2 and move.power > 0:
		var result: Dictionary = DamageCalculator.calculate(
				attacker, defender, move, _force_roll, _force_crit, weather)
		if result["damage"] >= defender.current_hp:
			# Source: L3015-3019 — FAST_KILL if AI is faster, SLOW_KILL otherwise.
			if StatusManager.effective_speed(attacker) >= StatusManager.effective_speed(defender):
				score += FAST_KILL
			else:
				score += SLOW_KILL

	# ── Pass 3: AI_CheckViability partial (battle_ai_main.c L4143) ───────────
	#
	# Full AI_CalcMoveEffectScore is ~1400 lines of per-move-effect handling.
	# We implement the two universally applicable rules from source:
	#   a) Effectiveness bonus for damaging moves (from AI_CompareDamagingMoves).
	#   b) Status move bonus when target has no status (IncreasePoisonScore etc.).

	if move.category != 2:
		# Source: AI_CompareDamagingMoves penalises relatively lower-power moves;
		# CheckViability scores DECENT_EFFECT(2) for 2× and BEST_EFFECT(4) for 4×.
		if effectiveness >= 4.0:
			score += BEST_EFFECT
		elif effectiveness >= 2.0:
			score += DECENT_EFFECT
	else:
		# Status move bonus when applicable status CAN be inflicted.
		# Source: IncreasePoisonScore/IncreaseParalyzeScore/IncreaseSleepScore/IncreaseBurnScore
		#   each add DECENT_EFFECT(2) when AI_Can*(…) returns TRUE. AI_Can* is TRUE when
		#   target has STATUS_NONE, type not immune, no substitute blocking.
		if move.secondary_effect in [
				MoveData.SE_BURN, MoveData.SE_PARALYSIS, MoveData.SE_SLEEP,
				MoveData.SE_TOXIC, MoveData.SE_FREEZE]:
			if defender.status == BattlePokemon.STATUS_NONE:
				score += DECENT_EFFECT

	return score


# ── SMART-tier switch evaluation ──────────────────────────────────────────────
#
# Source: ComputeAiBattlerDecisions (battle_ai_main.c L401) invokes the switch
#   eval via gAiLogicData->shouldSwitch, populated by ShouldSwitch* calls in
#   battle_ai_switch.c. We implement two:
#
#   ShouldSwitchIfAllMovesBad (battle_ai_switch.c L481):
#     If every damaging move the AI has is type-immune against the current
#     defender, switch out. Switch chance = 100% (SHOULD_SWITCH_ALL_MOVES_BAD = 100).
#
#   ShouldSwitchIfHasBadOdds (battle_ai_switch.c L367):
#     If defender can OHKO the AI and AI has no super-effective move and AI has
#     ≥ 50% HP, switch out. Switch chance = 50% (SHOULD_SWITCH_HASBADODDS = 50).

func _should_switch(attacker: BattlePokemon, defender: BattlePokemon,
		my_party: BattleParty, weather: int = DamageCalculator.WEATHER_NONE) -> int:
	if not my_party.has_valid_switch_target():
		return -1  # no candidates: must stay

	# ShouldSwitchIfAllMovesBad — 100% chance when all moves immune.
	# Source: battle_ai_switch.c L481-538. SHOULD_SWITCH_ALL_MOVES_BAD_PERCENTAGE=100.
	if _all_damaging_moves_immune(attacker, defender):
		return _best_switch_target(my_party, defender)

	# ShouldSwitchIfHasBadOdds — 50% chance.
	# Source: battle_ai_switch.c L367-419. SHOULD_SWITCH_HASBADODDS_PERCENTAGE=50.
	# Conditions (all must be true): being OHKO'd, no SE move, HP >= 50%.
	if _can_defender_ko_attacker(attacker, defender, weather):
		if not _has_super_effective_move(attacker, defender):
			if attacker.current_hp >= attacker.max_hp / 2:
				if _roll_switch_decision(50):
					return _best_switch_target(my_party, defender)

	return -1


# ── Internal helpers ──────────────────────────────────────────────────────────

func _all_damaging_moves_immune(attacker: BattlePokemon,
		defender: BattlePokemon) -> bool:
	for move: MoveData in attacker.moves:
		if move == null or move.category == 2 or move.power == 0:
			continue
		if TypeChart.get_effectiveness(move.type, defender.species.types) > 0.0:
			return false
	return true


func _has_super_effective_move(attacker: BattlePokemon,
		defender: BattlePokemon) -> bool:
	for move: MoveData in attacker.moves:
		if move == null or move.category == 2 or move.power == 0:
			continue
		if TypeChart.get_effectiveness(move.type, defender.species.types) >= 2.0:
			return true
	return false


func _can_defender_ko_attacker(attacker: BattlePokemon,
		defender: BattlePokemon,
		weather: int = DamageCalculator.WEATHER_NONE) -> bool:
	# Uses current (not maximum) attacker HP per source L387: hp >= maxHP / 2 check.
	for move: MoveData in defender.moves:
		if move == null or move.category == 2 or move.power == 0:
			continue
		var result: Dictionary = DamageCalculator.calculate(
				defender, attacker, move, _force_roll, _force_crit, weather)
		if result["damage"] >= attacker.current_hp:
			return true
	return false


func _best_switch_target(my_party: BattleParty, opponent: BattlePokemon) -> int:
	# Pick party member with best type effectiveness against the opponent.
	# Source: GetSwitchinCandidate SWITCHIN_CONSIDER_MOST_SUITABLE (battle_ai_switch.c L55+).
	var best_slot: int = -1
	var best_eff: float = -1.0
	for i in range(my_party.members.size()):
		if i == my_party.active_index:
			continue
		var mon: BattlePokemon = my_party.members[i]
		if mon.fainted:
			continue
		var best_mon_eff: float = 0.0
		for move: MoveData in mon.moves:
			if move == null or move.category == 2 or move.power == 0:
				continue
			var eff: float = TypeChart.get_effectiveness(move.type, opponent.species.types)
			if eff > best_mon_eff:
				best_mon_eff = eff
		if best_mon_eff > best_eff:
			best_eff = best_mon_eff
			best_slot = i

	if best_slot >= 0:
		return best_slot
	return my_party.get_first_non_fainted_not_active()


# Pick highest-scoring available move index; ties broken by RNG or _force_tie_rng.
# Source: ChooseMoveOrAction_Singles L888-915 + RandomUniform(RNG_AI_SCORE_TIE_SINGLES).
func _pick_best(scores: Array[int], moves: Array) -> int:
	var best_score: int = -999
	var best_indices: Array[int] = []
	for i in range(scores.size()):
		if i >= moves.size() or moves[i] == null:
			continue
		if scores[i] > best_score:
			best_score = scores[i]
			best_indices = [i]
		elif scores[i] == best_score:
			best_indices.append(i)

	if best_indices.is_empty():
		return 0
	if best_indices.size() == 1:
		return best_indices[0]
	if _force_tie_rng >= 0:
		return best_indices[clampi(_force_tie_rng, 0, best_indices.size() - 1)]
	return best_indices[randi() % best_indices.size()]


# Roll the switch-or-stay decision.
# Source: RandomPercentage(RNG_AI_SWITCH_HASBADODDS, ...) in battle_ai_switch.c.
func _roll_switch_decision(pct: int) -> bool:
	if _force_switch_rng == 0:
		return false  # forced stay
	if _force_switch_rng == 1:
		return true   # forced switch
	return (randi() % 100) < pct
