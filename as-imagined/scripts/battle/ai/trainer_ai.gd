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
#            Includes ShouldSwitchIfAllMovesBad, ShouldSwitchIfHasBadOdds,
#            and ShouldSwitchIfBadChoiceLock (M13).
#
# M11: weather passes through to DamageCalculator — no separate AI weather code.
# M13: choice-lock awareness via score-prefilter (moveLimitations, battle_ai_main.c L174-187)
#   and ShouldSwitchIfBadChoiceLock (battle_ai_switch.c L1170-1213).
#   Items compose through DamageCalculator automatically — no scoring changes needed.
#   Berry-triggered awareness: confirmed absent from source (docs/decisions.md).
#
# [M24c] `tier`/`Tier` above controls ONLY the proactive-switch axis (SMART vs
# BASIC) — a completely orthogonal, second axis, `ai_flags` (below), now
# controls exactly which of the 3 BASIC-tier scoring passes actually run, plus
# 2 optional modifiers. This is needed because real trainer data (854 real
# trainers, `docs/m24_recon.md` §2) uses 6 distinct AI-flag combinations, and
# NONE of them use SMART_SWITCHING at all — but 2 of the 6 are narrower than
# "Basic Trainer" (missing TRY_TO_FAINT and/or CHECK_VIABILITY), which the
# old pure `enum Tier{BASIC,SMART}` model had no way to represent at all
# (BASIC always meant "all 3 passes on"). `tier` stays exactly as it was for
# backward compatibility — every pre-existing test that only ever sets
# `.tier` is completely unaffected, since `ai_flags` defaults to
# AI_FLAG_BASIC_TRAINER (below), matching BASIC's own pre-existing behavior
# exactly.
#
# Step 0 (re-derived fresh from trainers.party + include/constants/
# battle_ai.h, not assumed from M24a's own prior grep): the 6 real
# combinations and their trainer counts out of 854 —
#   173 Basic Trainer                                            = 7  (CHECK_BAD_MOVE|TRY_TO_FAINT|CHECK_VIABILITY)
#     1 Basic Trainer / Force Setup First Turn                    = 15 (7|8)
#     5 Basic Trainer / Risky                                     = 23 (7|16)
#   640 Check Bad Move                                             = 1  (CHECK_BAD_MOVE only)
#     7 Check Bad Move / Try To Faint                              = 3  (1|2)
#    13 Check Bad Move / Try To Faint / Force Setup First Turn     = 11 (1|2|8)
# "Check Bad Move" ALONE is the single most common configuration in the
# entire roster (640/854, 75%) — a real, load-bearing gap in the old
# BASIC-only model, not a rare edge case.

enum Tier { BASIC, SMART }

# [M24c] AI-flag bit values — MUST match scripts/gen_trainer_data.py's own
# AI_TOKEN_MAP exactly (same cross-language-duplication precedent already
# established for ItemManager.HOLD_EFFECT_*/gen_items.py's own HOLD_EFFECT_*
# constants — no shared source between the Python build-time script and this
# GDScript runtime file is possible). Both were independently derived from
# the identical real bit POSITIONS in include/constants/battle_ai.h
# (AI_FLAG(0)=CHECK_BAD_MOVE ... AI_FLAG(4)=RISKY), so TrainerData.ai_flags
# (parsed by gen_trainer_data.py) and TrainerAI.ai_flags (this file) use the
# EXACT SAME numeric encoding — see from_trainer_data() below, a plain
# identity copy, not a translation.
const AI_FLAG_CHECK_BAD_MOVE: int         = 1   # bit 0
const AI_FLAG_TRY_TO_FAINT: int           = 2   # bit 1
const AI_FLAG_CHECK_VIABILITY: int        = 4   # bit 2
const AI_FLAG_FORCE_SETUP_FIRST_TURN: int = 8   # bit 3
const AI_FLAG_RISKY: int                  = 16  # bit 4
const AI_FLAG_BASIC_TRAINER: int = AI_FLAG_CHECK_BAD_MOVE | AI_FLAG_TRY_TO_FAINT | AI_FLAG_CHECK_VIABILITY  # = 7

# Score constants — source: include/battle_ai_main.h L21-41
const AI_SCORE_DEFAULT: int  = 100  # constants/battle_ai.h L57
const FAST_KILL: int         = 6    # AI faster and faints target
const SLOW_KILL: int         = 4    # AI slower and faints target
const BEST_DAMAGE_MOVE: int  = 1    # battle_ai_main.h L13 — move with fewest hits to KO
const WEAK_EFFECT: int       = 1    # small bonus
const DECENT_EFFECT: int     = 2    # moderate bonus
const GOOD_EFFECT: int       = 3    # good bonus
const BEST_EFFECT: int       = 4    # large bonus

var tier: Tier = Tier.BASIC

# [M24c] Defaults to AI_FLAG_BASIC_TRAINER — the exact set BASIC tier already
# implied before this session, so every pre-existing test/call site that
# never touches this field keeps its old behavior byte-for-byte.
var ai_flags: int = AI_FLAG_BASIC_TRAINER


# [M24c] Data → config factory — mirrors M24a's own "build the registry/data
# plumbing ahead of its real consumer" precedent. NO live caller wires this
# into an actual trainer battle yet: M26 (the overworld/encounter system
# that would call set_trainer_ai() for a real trainer fight) doesn't exist
# yet, confirmed via grep — this is data-ready infrastructure for that
# future consumer, exactly like TrainerRegistry/TrainerPicRegistry were for
# M24a's own portrait/data lookups before Phase 3 built a real consumer for
# one of them.
static func from_trainer_data(data: TrainerData) -> TrainerAI:
	var ai := TrainerAI.new()
	ai.ai_flags = data.ai_flags
	return ai

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


# ── Doubles entry: choose action for one combatant in a doubles battle ────────
#
# Source: ChooseMoveOrAction_Doubles (battle_ai_main.c L918-1038).
#
# Scoring architecture (from source):
#   For each candidate target slot, run the full AI scoring pipeline with that
#   slot as the nominal defender. Record the best-move score per target. Then
#   pick the target with the highest best-move score. Return that (move, target).
#   This means each (move, target) pair is scored independently — the AI does NOT
#   score a move once and bolt on a target separately.
#
# Spread moves (M14c extension of _score_move):
#   When ≥2 live opponents exist, DamageCalculator.calculate is called with
#   is_spread=true so the 0.75× reduction is applied in KO estimation.
#   No separate spread bonus is needed: AI_CalcDamage (battle_ai_util.c L887)
#   calls CalculateMoveDamageVars → GetTargetDamageModifier (battle_util.c L7220)
#   which applies 0.75× when GetMoveTargetCount==2. The per-target simulatedDmg
#   already incorporates the reduction, so GetNoOfHitsToKOBattler is naturally
#   target-count-aware. FAST_KILL/SLOW_KILL scoring handles the comparison correctly
#   with zero special-casing. ShouldUseSpreadDamageMove (L3915) only applies to
#   TARGET_FOES_AND_ALLY — irrelevant to TARGET_BOTH spread moves.
#
# AI_AttacksPartner (flag 30, L6045) — confirmed absent for trainer AI:
#   Only fires for IsNaturalEnemy (wild battles) or AI_FLAG_ATTACKS_PARTNER_FOCUSES_PARTNER.
#   Trainer doubles AI never deliberately targets its own ally. Documented in
#   docs/decisions.md as confirmed-absent.
#
# Returns {"type": "move", "index": int, "target": int}.
# "target" is opp0_idx or opp1_idx (the combatant index used by BattleManager).

func choose_action_doubles(
		attacker: BattlePokemon,
		_ally: BattlePokemon,
		opp0: BattlePokemon, opp0_idx: int,
		opp1: BattlePokemon, opp1_idx: int,
		my_party: BattleParty,
		_opp_party: BattleParty,
		weather: int = DamageCalculator.WEATHER_NONE,
		ally_chosen_switch_slot: int = -1) -> Dictionary:
	# SMART tier: proactive switch vs first live opponent (same logic as singles).
	if tier == Tier.SMART:
		var first_opp: BattlePokemon = opp0 if (opp0 != null and not opp0.fainted) else opp1
		if first_opp != null and not first_opp.fainted:
			# [M25a bugfix] ally_chosen_switch_slot -- see battle_manager.gd's
			# own call-site comment for the full aliasing mechanism this
			# guards against.
			var switch_slot: int = _should_switch(
					attacker, first_opp, my_party, weather, ally_chosen_switch_slot)
			if switch_slot >= 0:
				return {"type": "switch", "slot": switch_slot}

	# Choice lock — same as singles; target the first live opponent.
	if attacker.choice_locked_move != null:
		var locked_idx: int = attacker.moves.find(attacker.choice_locked_move)
		if locked_idx >= 0:
			var tgt_idx: int = opp0_idx if (opp0 != null and not opp0.fainted) else opp1_idx
			return {"type": "move", "index": locked_idx, "target": tgt_idx}

	# Count live opponents to determine spread-reduction applicability.
	var live_opp_count: int = 0
	if opp0 != null and not opp0.fainted and opp0.current_hp > 0:
		live_opp_count += 1
	if opp1 != null and not opp1.fainted and opp1.current_hp > 0:
		live_opp_count += 1

	# Score each move vs each live opponent slot independently.
	# Source: L930-1008 — outer loop over battlerIndex, inner scoring per move.
	# GDScript 4.x: typed Arrays from literals need loop assignment (gotcha: silent fail).
	var best_score: Array[int] = []
	best_score.resize(2)
	best_score[0] = -1
	best_score[1] = -1
	var best_move: Array[int] = []
	best_move.resize(2)
	best_move[0] = 0
	best_move[1] = 0
	var opps: Array = [opp0, opp1]
	var opp_idxs: Array[int] = []
	opp_idxs.append(opp0_idx)
	opp_idxs.append(opp1_idx)

	for oi in range(2):
		var opp: BattlePokemon = opps[oi]
		if opp == null or opp.fainted or opp.current_hp <= 0:
			continue
		var is_spread_active: bool = live_opp_count >= 2

		var scores: Array[int] = []
		for move: MoveData in attacker.moves:
			if move == null:
				scores.append(-999)
			else:
				scores.append(_score_move_doubles(
						attacker, opp, move, weather,
						move.is_spread and is_spread_active))

		# AI_CompareDamagingMoves pass, per-target (battle_ai_main.c L964).
		_apply_best_damage_move(attacker, opp, scores, weather, is_spread_active)

		var best_idx: int = _pick_best(scores, attacker.moves)
		best_score[oi] = scores[best_idx] if not scores.is_empty() else AI_SCORE_DEFAULT
		best_move[oi]  = best_idx

	# Pick target with highest best-move score.
	# Source: L1011-1034 — track mostMovePoints across target loop.
	var chosen_oi: int = 0
	if best_score[1] > best_score[0]:
		chosen_oi = 1

	return {
		"type":   "move",
		"index":  best_move[chosen_oi],
		"target": opp_idxs[chosen_oi]
	}


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
		weather: int = DamageCalculator.WEATHER_NONE,
		is_first_turn: bool = false) -> Dictionary:
	# SMART tier: proactive switch evaluation before move scoring.
	# Basic trainers never proactively switch in source — that logic is gated
	# behind AI_FLAG_SMART_SWITCHING which is absent from AI_FLAG_BASIC_TRAINER.
	# Source: AI_TrySwitchOrUseItem L456, gAiLogicData->shouldSwitch.
	if tier == Tier.SMART:
		var switch_slot: int = _should_switch(attacker, defender, my_party, weather)
		if switch_slot >= 0:
			return {"type": "switch", "slot": switch_slot}

	# M13: Choice-lock early return — return locked move index directly.
	# Source: BattleAI_SetupAIData (battle_ai_main.c L174-187): moveLimitations prefilter
	#   sets SET_SCORE(battler, moveIndex, 0) for all non-locked moves when choice-locked.
	#   BattleAI_DoAIProcessing (L1053) skips scoring for moves with score==0, leaving
	#   only the locked move with a non-zero score. It is automatically chosen.
	# Port: skip all scoring and return the locked move's index immediately.
	if attacker.choice_locked_move != null:
		var locked_idx: int = attacker.moves.find(attacker.choice_locked_move)
		if locked_idx >= 0:
			return {"type": "move", "index": locked_idx}

	# Score each available move, pick best.
	# Source: ChooseMoveOrAction_Singles runs each enabled AI_FLAG pass.
	var scores: Array[int] = []
	for i in range(attacker.moves.size()):
		var move: MoveData = attacker.moves[i]
		if move == null:
			scores.append(-999)
		else:
			scores.append(_score_move(attacker, defender, move, weather, is_first_turn))

	# [M24c] AI_CompareDamagingMoves pass (battle_ai_main.c L881) — source
	# gates this specifically on AI_FLAG_CHECK_VIABILITY (L879-880), not run
	# unconditionally the way this project's own code did before this
	# session (every real trainer previously implemented was BASIC_TRAINER-
	# shaped, so CHECK_VIABILITY was always on anyway — this only changes
	# observable behavior for the new narrower "Check Bad Move [/ Try To
	# Faint]" combinations, 647/854 real trainers).
	if ai_flags & AI_FLAG_CHECK_VIABILITY:
		_apply_best_damage_move(attacker, defender, scores, weather)

	return {"type": "move", "index": _pick_best(scores, attacker.moves)}


# ── Battle-use item AI (M24b) ─────────────────────────────────────────────────
#
# Confirmed via direct source read (battle_ai_items.c :: ShouldUseItem/
# AI_ShouldHeal) that TrainerAI had ZERO item-use decision logic before this —
# every prior "item" reference in this file is about a HELD item composing
# through DamageCalculator automatically (M13), a completely different axis
# from a trainer's own battle-use bag items (Potions/etc., TrainerData's
# "Items:" field). This is genuinely new plumbing, not a reuse.
#
# Deliberately narrow, matching this project's own BASIC/SMART scoring-only
# philosophy: reuses source's own FIRST-ORDER threshold from AI_ShouldHeal
# (battle_ai_items.c L204 — `hp < maxHP/4`) but WITHOUT its deeper
# AI_OpponentCanFaintAiWithMod/GetBestDmgFromBattler damage-prediction layer
# (would a heal actually save this Pokémon from a lethal hit?) — that's
# genuine deep item-strategy AI, explicitly out of scope for this tier.
#
# Only BATTLE_USE_RESTORE_HP items are considered — the one battle-use kind
# with a real, reachable data path in this project's own trainer roster today
# (854 real trainers: only Roxanne carries a resolved battle item at all,
# 2x Potion — every other trainer's "Items:" field resolves to Full Restore/
# Hyper Potion/Super Potion/Nugget, all confirmed M18 exclusions deferred to
# M25, see docs/m18_item_ledger.md). CURE_STATUS/INCREASE_STAT/THROW_BALL
# items are left for a future tier once real trainer data can actually
# reach them.
func should_use_item(mon: BattlePokemon, available_items: Array) -> ItemData:
	if mon == null or mon.current_hp <= 0:
		return null
	if mon.current_hp >= mon.max_hp / 4.0:
		return null
	for item in available_items:
		if item != null and item.battle_usage == ItemManager.BATTLE_USE_RESTORE_HP:
			return item
	return null


# ── Faint replacement: which party slot to send in ────────────────────────────
#
# Source: GetSwitchinCandidate (battle_ai_switch.c L2004). The real source picks
#   the last eligible party member by priority tier (trappers, revenge killers,
#   type-advantage candidates, etc.), not by move type effectiveness.
# Simplification: pick the party member whose moves have the highest type
#   effectiveness against the current opponent. Kept as-is — a different valid
#   simplification (see decisions.md F15/F32 entry). Falls back to first alive
#   non-active if no move data available.

func choose_replacement(my_party: BattleParty, opponent: BattlePokemon) -> int:
	var best_slot: int = -1
	var best_eff: float = -1.0
	for i in range(my_party.members.size()):
		# [M21] Bug fix: was `i == my_party.active_index`, which only excludes
		# slot 0 of the active pair. In doubles with BOTH slots alive, this let
		# the AI recommend "switching in" a mon already active in the OTHER
		# slot. `get_first_non_fainted_not_active` was already fixed to check
		# ALL active_indices; this function (checked FIRST, before that
		# fallback) was not. Mirrors that same fix exactly.
		if my_party.active_indices.has(i):
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
		move: MoveData, weather: int = DamageCalculator.WEATHER_NONE,
		is_first_turn: bool = false) -> int:
	var score: int = AI_SCORE_DEFAULT

	# ── Pass 1: AI_CheckBadMove (battle_ai_main.c L1201) ──────────────────────
	# [M24c] Gated on AI_FLAG_CHECK_BAD_MOVE — present in all 6 real
	# combinations (never actually off for a real trainer today), but the
	# gate is real and correct for direct unit testing / future data.
	if ai_flags & AI_FLAG_CHECK_BAD_MOVE:
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
	# [M24c] Gated on AI_FLAG_TRY_TO_FAINT — real for 4/6 combos, absent for
	# the 640/854-trainer "Check Bad Move" alone configuration.
	if ai_flags & AI_FLAG_TRY_TO_FAINT:
		# Status moves always return early here: "if (IsBattleMoveStatus(move)) return score"
		# M11: DamageCalculator.calculate now receives weather so the estimated damage
		# automatically reflects the current field boost/reduction — no AI-specific logic needed.
		# _force_roll / _force_crit are null/-1 in production; pinnable in tests for determinism.
		# [M24c] Uses _effective_ai_roll(), not _force_roll directly — see its own
		# doc comment for AI_FLAG_RISKY's real "assumes it deals max damage" effect
		# (battle_ai_util.c L112-113).
		if move.category != 2 and move.power > 0:
			var result: Dictionary = DamageCalculator.calculate(
					attacker, defender, move, _effective_ai_roll(), _force_crit, weather)
			if result["damage"] >= defender.current_hp:
				# Source: L3015-3019 — FAST_KILL if AI is faster, SLOW_KILL otherwise.
				if StatusManager.effective_speed(attacker) >= StatusManager.effective_speed(defender):
					score += FAST_KILL
				else:
					score += SLOW_KILL

	# ── Pass 3: AI_CalcMoveEffectScore (battle_ai_main.c L4143), called by AI_CheckViability (L5862) ──
	# [M24c] Gated on AI_FLAG_CHECK_VIABILITY.
	#
	# Source-accurate ports of IncreasePoisonScore / IncreaseBurnScore /
	# IncreaseParalyzeScore / IncreaseSleepScore (battle_ai_util.c L4791-4907).
	# Common guard: skip bonus if AI can already KO the target this turn.
	# See decisions.md for what is ported vs omitted per function.
	if (ai_flags & AI_FLAG_CHECK_VIABILITY) and move.category == 2 and defender.status == BattlePokemon.STATUS_NONE:
		var can_faint: bool = _can_attacker_ko_defender(attacker, defender, weather)
		match move.secondary_effect:
			MoveData.SE_TOXIC:
				# IncreasePoisonScore (L4791): base +WEAK_EFFECT.
				# Extra +DECENT_EFFECT when defender has no damaging moves (helpless).
				if not can_faint:
					if not _has_damaging_moves(defender):
						score += DECENT_EFFECT
					score += WEAK_EFFECT
			MoveData.SE_BURN:
				# IncreaseBurnScore (L4814): 0 if defender is not a physical attacker.
				# +DECENT_EFFECT if has explicit physical moves; +WEAK_EFFECT if stat heuristic only.
				if not can_faint:
					if _has_physical_moves(defender):
						score += DECENT_EFFECT
					elif defender.species.base_attack >= defender.species.base_sp_attack + 10:
						score += WEAK_EFFECT
			MoveData.SE_PARALYSIS:
				# IncreaseParalyzeScore (L4855): +GOOD_EFFECT if paralysis flips turn order
				# (defSpeed >= atkSpeed and defSpeed/2 < atkSpeed); +DECENT_EFFECT otherwise.
				if not can_faint:
					var atk_spd: int = StatusManager.effective_speed(attacker)
					var def_spd: int = StatusManager.effective_speed(defender)
					if def_spd >= atk_spd and def_spd / 2 < atk_spd:
						score += GOOD_EFFECT
					else:
						score += DECENT_EFFECT
			MoveData.SE_SLEEP:
				# IncreaseSleepScore (L4877): +DECENT_EFFECT when not can_faint.
				# Source has a Focus Punch carve-out (falls through to +DECENT_EFFECT even
				# when can_faint if all best moves are Focus Punch); omitted — not in scope.
				if not can_faint:
					score += DECENT_EFFECT

	# ── Pass 4: AI_ForceSetupFirstTurn (battle_ai_main.c L5905-5959) ─────────
	# [M24c] Gated on AI_FLAG_FORCE_SETUP_FIRST_TURN AND is_first_turn (source:
	# `gBattleResults.battleTurnCounter != 0` returns unchanged score on any
	# turn but the battle's very first). Source's real switch-case covers ~25
	# distinct move EFFECT_* values (Conversion/Light Screen/Focus Energy/
	# Confuse/Reflect/non-volatile-status/Substitute/Leech Seed/Curse/Swagger/
	# Camouflage/Yawn/Torment/Ingrain/Imprison/Acupressure/4 terrains/Stealth
	# Rock/Toxic Spikes/Trick Room/Wonder Room/Magic Room/Tailwind/Tidy Up/
	# Sticky Web/Weather/Ceaseless Edge/Stone Axe) — a deliberately NARROWED
	# slice ships here, matching this whole tier's own "narrow, not the full
	# engine" scope: only the single most common and cleanly-detectable
	# shape, a plain self-targeted POSITIVE stat-change status move (Swords
	# Dance/Bulk Up/Calm Mind/Growth-style — `stat_change_self` +
	# `stat_change_amount > 0`), gets the +DECENT_EFFECT bonus. The other
	# ~24 specific move-effect cases are NOT ported — flagged for a future
	# session, not silently dropped.
	if (ai_flags & AI_FLAG_FORCE_SETUP_FIRST_TURN) and is_first_turn:
		if move.category == 2 and move.stat_change_self \
				and move.stat_change_stat >= 0 and move.stat_change_amount > 0:
			score += DECENT_EFFECT

	# ── Pass 5: AI_Risky (battle_ai_main.c L5966-6040+) ──────────────────────
	# [M24c] Gated on AI_FLAG_RISKY. Source's real function has ~15 further
	# move-EFFECT-specific cases (Memento/Revenge/Belly Drum/Clangorous
	# Soul/Reflect Damage/etc., each with its own HP%/stat condition) beyond
	# the two ported here — deliberately NOT ported, same narrow-slice
	# scoping as Pass 4 above. The two kept are the cheapest, most broadly
	# applicable, and most easily verified:
	#   - `GetMoveCriticalHitStage(move) > 0` → +DECENT_EFFECT (any move with
	#     an elevated crit stage, e.g. Slash/Crabhammer/Storm Throw).
	#   - `IsExplosionMove(move)` → +STRONG_RISKY_EFFECT and RETURN (source's
	#     own early return — Self-Destruct/Explosion, `is_self_faint`).
	# STRONG_RISKY_EFFECT isn't one of this project's own pre-existing score
	# constants (WEAK/DECENT/GOOD/BEST_EFFECT) — reuses BEST_EFFECT (4) as
	# the closest existing magnitude rather than inventing a new unverified
	# numeric constant (source's own AI_SCORE_MAX-scaled values aren't
	# reproduced by this project's simplified point scale at all).
	if ai_flags & AI_FLAG_RISKY:
		if move.critical_hit_stage > 0:
			score += DECENT_EFFECT
		if move.is_self_faint:
			score += BEST_EFFECT
			return score

	return score


# ── Doubles move scoring ──────────────────────────────────────────────────────
#
# Extends _score_move with one doubles-specific adjustment:
#   is_spread_active passed to DamageCalculator so KO estimation uses 0.75×.
# No spread bonus: simulatedDmg already incorporates the reduction (see header).

# [M24c] KNOWN GAP, deliberately NOT fixed this session (out of this tier's
# own explicit scope): unlike _score_move above, this function is NOT gated
# on ai_flags at all — it always runs all 3 passes unconditionally
# (BASIC_TRAINER-shaped), and has no FORCE_SETUP_FIRST_TURN/RISKY passes or
# _effective_ai_roll() awareness either. Real consequence: a doubles-format
# trainer (77/854 real trainers use "Double Battle: Yes") whose ai_flags
# encode one of the narrower combinations (e.g. "Check Bad Move" alone)
# still gets full BASIC-shaped scoring in a doubles battle specifically,
# unlike the now-correctly-gated singles path above. Flagged for a future
# session, not silently dropped — mirrors this whole tier's own "narrow
# slice, not full parity" scoping already applied to Pass 4/5 above.
func _score_move_doubles(attacker: BattlePokemon, defender: BattlePokemon,
		move: MoveData, weather: int,
		is_spread_active: bool) -> int:
	var score: int = AI_SCORE_DEFAULT

	var effectiveness: float = TypeChart.get_effectiveness(
			move.type, defender.species.types)
	if effectiveness == 0.0:
		return score - 20

	if move.two_turn and move.semi_inv_state == MoveData.SEMI_INV_NONE:
		if _can_defender_ko_attacker(attacker, defender, weather):
			score -= 10

	if move.category == 2 and move.secondary_effect in [
			MoveData.SE_BURN, MoveData.SE_PARALYSIS, MoveData.SE_SLEEP,
			MoveData.SE_TOXIC, MoveData.SE_FREEZE]:
		if defender.status != BattlePokemon.STATUS_NONE:
			score -= 10

	if move.category != 2 and move.power > 0:
		var result: Dictionary = DamageCalculator.calculate(
				attacker, defender, move, _force_roll, _force_crit, weather,
				is_spread_active)
		if result["damage"] >= defender.current_hp:
			if StatusManager.effective_speed(attacker) >= StatusManager.effective_speed(defender):
				score += FAST_KILL
			else:
				score += SLOW_KILL

	# Mirrors _score_move Pass 3 — same source functions, same conditions.
	if move.category == 2 and defender.status == BattlePokemon.STATUS_NONE:
		var can_faint: bool = _can_attacker_ko_defender(attacker, defender, weather)
		match move.secondary_effect:
			MoveData.SE_TOXIC:
				if not can_faint:
					if not _has_damaging_moves(defender):
						score += DECENT_EFFECT
					score += WEAK_EFFECT
			MoveData.SE_BURN:
				if not can_faint:
					if _has_physical_moves(defender):
						score += DECENT_EFFECT
					elif defender.species.base_attack >= defender.species.base_sp_attack + 10:
						score += WEAK_EFFECT
			MoveData.SE_PARALYSIS:
				if not can_faint:
					var atk_spd: int = StatusManager.effective_speed(attacker)
					var def_spd: int = StatusManager.effective_speed(defender)
					if def_spd >= atk_spd and def_spd / 2 < atk_spd:
						score += GOOD_EFFECT
					else:
						score += DECENT_EFFECT
			MoveData.SE_SLEEP:
				if not can_faint:
					score += DECENT_EFFECT

	return score


# ── SMART-tier switch evaluation ──────────────────────────────────────────────
#
# Source: ComputeAiBattlerDecisions (battle_ai_main.c L401) invokes the switch
#   eval via gAiLogicData->shouldSwitch, populated by ShouldSwitch* calls in
#   battle_ai_switch.c. We implement two:
#
#   ShouldSwitchIfAllMovesBad (battle_ai_switch.c L484):
#     If every damaging move the AI has is type-immune against the current
#     defender, switch out. Switch chance = 100% (SHOULD_SWITCH_ALL_MOVES_BAD = 100).
#
#   ShouldSwitchIfHasBadOdds (battle_ai_switch.c L367):
#     If defender can OHKO the AI and AI has no super-effective move and AI has
#     ≥ 50% HP, switch out. Switch chance = 50% (SHOULD_SWITCH_HASBADODDS = 50).

func _should_switch(attacker: BattlePokemon, defender: BattlePokemon,
		my_party: BattleParty, weather: int = DamageCalculator.WEATHER_NONE,
		excluded_slot: int = -1) -> int:
	if not my_party.has_valid_switch_target():
		return -1  # no candidates: must stay

	# ShouldSwitchIfAllMovesBad — 100% chance when all moves immune.
	# Source: battle_ai_switch.c L484-538. SHOULD_SWITCH_ALL_MOVES_BAD_PERCENTAGE=100.
	if _all_damaging_moves_immune(attacker, defender):
		return _best_switch_target(my_party, defender, excluded_slot)

	# ShouldSwitchIfHasBadOdds — 50% chance.
	# Source: battle_ai_switch.c L367-419. SHOULD_SWITCH_HASBADODDS_PERCENTAGE=50.
	# Conditions (all must be true): being OHKO'd, no SE move, HP >= 50%.
	if _can_defender_ko_attacker(attacker, defender, weather):
		if not _has_super_effective_move(attacker, defender):
			if attacker.current_hp >= attacker.max_hp / 2:
				if _roll_switch_decision(50):
					return _best_switch_target(my_party, defender, excluded_slot)

	# M13: ShouldSwitchIfBadChoiceLock — 100% deterministic, no RNG seam needed.
	# Source: battle_ai_switch.c L1170-1213 (singles branch L1206-1209).
	#   Condition: choice-locked AND (locked move is status OR locked move is type-immune).
	#   SHOULD_SWITCH_CHOICE_LOCKED_PERCENTAGE = 100 (config/ai.h L23).
	# Port: if choice_locked_move != null, the mon IS locked (set by BattleManager when
	#   a choice-item holder uses a move). No need to re-check the item.
	if attacker.choice_locked_move != null:
		var locked: MoveData = attacker.choice_locked_move
		var is_status: bool = (locked.category == 2)
		var is_immune: bool = (TypeChart.get_effectiveness(
				locked.type, defender.species.types) == 0.0)
		if is_status or is_immune:
			return _best_switch_target(my_party, defender, excluded_slot)

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


func _best_switch_target(my_party: BattleParty, opponent: BattlePokemon,
		excluded_slot: int = -1) -> int:
	# Source: GetSwitchinCandidate (battle_ai_switch.c L2004). Real source picks by
	#   priority tier (not type effectiveness). Simplification: pick by highest type
	#   effectiveness. Kept as-is — see decisions.md F15/F32 entry.
	var best_slot: int = -1
	var best_eff: float = -1.0
	for i in range(my_party.members.size()):
		# [M21] Same bug fix as choose_replacement above — was slot-0-only.
		if my_party.active_indices.has(i):
			continue
		# [M25a bugfix] excluded_slot -- a doubles ally's own already-chosen
		# (but not-yet-applied) switch target this same turn, passed through
		# from choose_action_doubles. See battle_manager.gd's own call-site
		# comment for why active_indices alone isn't enough to prevent two
		# allies from picking the identical bench slot.
		if i == excluded_slot:
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
	# [M25a bugfix] my_party.get_first_non_fainted_not_active() has no
	# excluded_slot parameter -- calling it here as a bare fallback was the
	# actual remaining bug: when excluded_slot was the ONLY live,
	# non-active candidate (so the scored loop above excludes it and never
	# sets best_slot), this fallback picked it right back up anyway, since
	# it only checks active_indices, not excluded_slot. Confirmed via a
	# direct trace this was the exact final mechanism behind the residual
	# ~1.7% collision rate the earlier two M25a fixes didn't close.
	for i in range(my_party.members.size()):
		if my_party.active_indices.has(i) or my_party.members[i].fainted or i == excluded_slot:
			continue
		return i
	return -1


# ── AI_CompareDamagingMoves (battle_ai_main.c L3940) — bounded port ───────────
#
# Port: the move requiring strictly the fewest hits to KO the defender gets
#   BEST_DAMAGE_MOVE (+1). If multiple moves tie for fewest hits, all tied moves
#   get +1 equally (no cascade tiebreaker — see decisions.md for rationale).
#
# Deliberately omitted (each documented in decisions.md):
#   Tiebreaker cascade (resist-berry, speed/priority, guaranteed-KO, two-turn,
#     accuracy, effect) — none of the test scenarios exercise tied hit counts;
#     adding untested logic would be undocumented dead code.
#   Spread-move carve-out (source excludes spread moves because their full-damage
#     estimate is un-reduced; our estimate already incorporates the 0.75× reduction
#     from is_spread=true in DamageCalculator, so the concern is moot).
#   Self-sacrifice exception (source sets noOfHits=maxHP when AI declines
#     self-sacrifice; no Explosion/Selfdestruct in scope).

func _apply_best_damage_move(
		attacker: BattlePokemon, defender: BattlePokemon,
		scores: Array[int],
		weather: int,
		is_spread_active: bool = false) -> void:
	const INF_HITS: int = 1_000_000
	var hits_to_ko: Array[int] = []
	var least_hits: int = INF_HITS

	for move: MoveData in attacker.moves:
		if move == null or move.category == 2 or move.power == 0:
			hits_to_ko.append(INF_HITS)
			continue
		if TypeChart.get_effectiveness(move.type, defender.species.types) == 0.0:
			hits_to_ko.append(INF_HITS)
			continue
		var spread_this: bool = is_spread_active and move.is_spread
		var result: Dictionary = DamageCalculator.calculate(
				attacker, defender, move, _force_roll, _force_crit, weather, spread_this)
		var dmg: int = result["damage"]
		if dmg <= 0:
			hits_to_ko.append(INF_HITS)
			continue
		var hits: int = ceili(float(defender.current_hp) / float(dmg))
		hits_to_ko.append(hits)
		if hits < least_hits:
			least_hits = hits

	if least_hits >= INF_HITS:
		return
	for i in range(mini(hits_to_ko.size(), scores.size())):
		if hits_to_ko[i] == least_hits:
			scores[i] += BEST_DAMAGE_MOVE


func _can_attacker_ko_defender(attacker: BattlePokemon, defender: BattlePokemon,
		weather: int = DamageCalculator.WEATHER_NONE) -> bool:
	# CanAIFaintTarget equivalent — does any of attacker's damaging moves KO the defender?
	# Source: used as early-return guard in Increase*Score (battle_ai_util.c L4793).
	# [M24c] Uses _effective_ai_roll() — see its own doc comment.
	for move: MoveData in attacker.moves:
		if move == null or move.category == 2 or move.power == 0:
			continue
		if TypeChart.get_effectiveness(move.type, defender.species.types) == 0.0:
			continue
		var result: Dictionary = DamageCalculator.calculate(
				attacker, defender, move, _effective_ai_roll(), _force_crit, weather)
		if result["damage"] >= defender.current_hp:
			return true
	return false


# [M24c] AI_FLAG_RISKY's damage-roll-assumption half — source: AI_GetDamage
# (battle_ai_util.c L109-115, AI_ATTACKING context): "Risky assumes it deals
# max damage" — `if (RISKY && !CONSERVATIVE) return simulatedDmg.maximum`.
# AI_FLAG_CONSERVATIVE (the opposite modifier, "assumes min damage") is not
# implemented in this project at all (absent from every one of the 6 real
# trainer AI-flag combinations, per this file's own Step 0 above) — so the
# `!CONSERVATIVE` half of source's condition is permanently true here and
# correctly omitted, not silently dropped.
#
# Deliberately scoped to the ATTACKER'S OWN estimated damage only — source's
# separate AI_DEFENDING-context assumption ("Risky assumes it takes MIN
# damage" from the opponent) is NOT ported here; that half only ever feeds
# SMART-tier proactive-switch decisions (`_should_switch`), and none of the
# 6 real trainer AI-flag combinations use SMART_SWITCHING at all — building
# it now would be untested, unreachable surface for this project's actual
# data.
#
# A test-level `_force_roll` pin always wins over Risky's own assumption
# (matches every other test-seam in this file — tests must stay fully
# deterministic regardless of which AI flags are set).
func _effective_ai_roll() -> int:
	if _force_roll >= 0:
		return _force_roll
	if ai_flags & AI_FLAG_RISKY:
		return DamageCalculator.DMG_ROLL_HI
	return -1  # real random roll, unchanged default behavior


func _has_damaging_moves(mon: BattlePokemon) -> bool:
	# HasDamagingMove — does mon have any non-status, non-zero-power move?
	# Source: battle_ai_util.c — used in IncreasePoisonScore to detect helpless defenders.
	for move: MoveData in mon.moves:
		if move != null and move.category != 2 and move.power > 0:
			return true
	return false


func _has_physical_moves(mon: BattlePokemon) -> bool:
	# HasMoveWithCategory(DAMAGE_CATEGORY_PHYSICAL) — does mon have physical damaging moves?
	# Source: battle_ai_util.c — used in IncreaseBurnScore to detect physical attackers.
	for move: MoveData in mon.moves:
		if move != null and move.category == 0 and move.power > 0:
			return true
	return false


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
