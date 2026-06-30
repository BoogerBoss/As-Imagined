class_name StatusManager
extends RefCounted

# Status condition logic for Milestone 3.
# All numeric constants and rules verified against pokeemerald_expansion source.
#
# Sources:
#   src/battle_util.c            :: CanSetNonVolatileStatus (L5235)
#   src/battle_end_turn.c        :: HandleEndTurnBurn (L565), HandleEndTurnPoison (L517)
#   src/battle_move_resolution.c :: CancelerSleep (L120), CancelerFrozen (L172),
#                                   CancelerConfused (L389), CancelerParalyzed (L447)
#   include/config/battle.h      :: B_BURN_DAMAGE, B_PARALYSIS_SPEED, B_SLEEP_TURNS,
#                                   B_CONFUSION_SELF_DMG_CHANCE, B_PARALYZE_ELECTRIC
#
# Config assumptions (all GEN_LATEST):
#   B_BURN_DAMAGE = GEN_7+          → burn tick = maxHP / 16 (not 1/8)
#   B_PARALYSIS_SPEED = GEN_7+      → paralysis speed cut = / 2 (not / 4)
#   B_SLEEP_TURNS = GEN_5+          → sleep duration = 2–4 turns (not 2–5)
#   B_CONFUSION_SELF_DMG_CHANCE=GEN_7+ → self-hit = 33% (not 50%)
#   B_PARALYZE_ELECTRIC = GEN_6+    → Electric-types cannot be paralyzed
# Scope for M3: no abilities (Guts, Quick Feet, Magic Guard, etc.), no weather,
#               no held items, no Facade interaction, no Early Bird.


# ── Status application ────────────────────────────────────────────────────
#
# try_apply_status: attempt to inflict a major status condition on `mon`.
# Returns true if the status was applied, false if blocked by type immunity
# or by the Pokémon already having a major status.
#
# force_sleep_turns: Variant — null = random 2–4; int value = pin duration
#   (only meaningful when status == BattlePokemon.STATUS_SLEEP)
static func try_apply_status(
		mon: BattlePokemon,
		status: int,
		force_sleep_turns: Variant = null) -> bool:

	# One major status at a time.
	# Source: CanSetNonVolatileStatus L5391 — "already has STATUS1_ANY → fails"
	if mon.status != BattlePokemon.STATUS_NONE:
		return false

	# Type immunities — source: CanSetNonVolatileStatus L5244–5354
	match status:
		BattlePokemon.STATUS_BURN:
			# Fire-types cannot be burned — source: L5291–5294
			if TypeChart.TYPE_FIRE in mon.species.types:
				return false

		BattlePokemon.STATUS_POISON, BattlePokemon.STATUS_TOXIC:
			# Poison-types and Steel-types cannot be poisoned — source: L5250–5252
			# (Corrosion ability bypasses this but is not in M3 scope)
			if TypeChart.TYPE_POISON in mon.species.types or \
					TypeChart.TYPE_STEEL in mon.species.types:
				return false

		BattlePokemon.STATUS_PARALYSIS:
			# Electric-types cannot be paralyzed (B_PARALYZE_ELECTRIC >= GEN_6) — source: L5272–5274
			if TypeChart.TYPE_ELECTRIC in mon.species.types:
				return false

		BattlePokemon.STATUS_FREEZE:
			# Ice-types cannot be frozen — source: L5342
			# (Sun weather also prevents freeze but weather is not in M3 scope)
			if TypeChart.TYPE_ICE in mon.species.types:
				return false
		# STATUS_SLEEP: no type immunity; only ability-based (not in M3 scope)

	mon.status = status

	match status:
		BattlePokemon.STATUS_SLEEP:
			# Duration: RandomUniform(2, 4) — source: battle_script_commands.c L2177
			# (B_SLEEP_TURNS >= GEN_5 → 2–4 inclusive)
			mon.sleep_turns = force_sleep_turns if force_sleep_turns != null \
					else randi_range(2, 4)
		BattlePokemon.STATUS_TOXIC:
			mon.toxic_counter = 0  # first EOT tick increments to 1

	return true


# try_apply_confusion: attempt to inflict confusion (a volatile status).
# Confusion is separate from the major status slot — a Pokémon can be
# paralyzed AND confused simultaneously.
# Returns true if confusion was applied, false if already confused.
#
# force_confusion_turns: Variant — null = random 2–5; int = pin duration
#   Source: battle_script_commands.c L2363
#   RandomUniform(2, B_CONFUSION_TURNS=5) — comment: "2–5 turns"
static func try_apply_confusion(
		mon: BattlePokemon,
		force_confusion_turns: Variant = null) -> bool:

	if mon.confusion_turns > 0:
		return false  # already confused

	mon.confusion_turns = force_confusion_turns if force_confusion_turns != null \
			else randi_range(2, 5)
	return true


# ── End-of-turn status damage ─────────────────────────────────────────────
#
# Returns the HP to subtract this end-of-turn. 0 = no damage.
# For toxic this also increments the counter (must call exactly once per turn).
#
# Source:
#   burn   — battle_end_turn.c :: HandleEndTurnBurn L577
#             maxHP / 16 (B_BURN_DAMAGE = GEN_LATEST = GEN_7+)
#   poison — battle_end_turn.c :: HandleEndTurnPoison L556
#             maxHP / 8
#   toxic  — battle_end_turn.c :: HandleEndTurnPoison L547–550
#             counter increments first (cap at 15), then damage = (maxHP/16) * counter
static func end_of_turn_damage(mon: BattlePokemon) -> int:
	match mon.status:
		BattlePokemon.STATUS_BURN:
			return max(1, mon.max_hp / 16)

		BattlePokemon.STATUS_POISON:
			return max(1, mon.max_hp / 8)

		BattlePokemon.STATUS_TOXIC:
			# Increment then multiply — source: L548–550
			# "(status & STATUS1_TOXIC_COUNTER) != STATUS1_TOXIC_TURN(15)" = cap at 15
			mon.toxic_counter = mini(mon.toxic_counter + 1, 15)
			return max(1, mon.max_hp / 16 * mon.toxic_counter)

	return 0


# ── Pre-move status checks ────────────────────────────────────────────────
#
# Executes all status-driven pre-move cancelers in source order:
#   1. Sleep  (battle_move_resolution.c :: CancelerSleep    ~L120)
#   2. Freeze (battle_move_resolution.c :: CancelerFrozen    L172)
#   3. Confusion (CancelerConfused L389)  ← volatile, checked independently
#   4. Paralysis (CancelerParalyzed L447)
#
# Returns a Dictionary:
#   "can_move"        : bool — false → skip move execution this turn
#   "self_hit_damage" : int  — >0 if confusion self-hit occurred
#   "woke_up"         : bool — true if woke from sleep (can still move)
#   "thawed"          : bool — true if thawed from freeze (can still move)
#   "snapped_out"     : bool — true if snapped out of confusion (can move)
#
# Force parameters (all Variant):
#   null = use RNG   |   true / false = pin the outcome
#   force_sleep_wake     : true = wake this turn, false = stay asleep
#   force_freeze_thaw    : true = thaw this turn, false = stay frozen
#   force_confusion_hit  : true = self-hit, false = snap out / no self-hit
#   force_full_para      : true = fully paralyzed, false = can move
static func pre_move_check(
		mon: BattlePokemon,
		force_sleep_wake: Variant = null,
		force_freeze_thaw: Variant = null,
		force_confusion_hit: Variant = null,
		force_full_para: Variant = null,
		move: MoveData = null) -> Dictionary:

	var result := {
		"can_move":        true,
		"self_hit_damage": 0,
		"woke_up":         false,
		"thawed":          false,
		"snapped_out":     false,
		"flinched":        false,
	}

	# ── Sleep ──────────────────────────────────────────────────────────────
	# Source: battle_move_resolution.c L120–169
	# Counter always decrements by 1 each attempt (toSub=1 without Early Bird).
	# If still > 0 → can't move. If hits 0 → wake and can move that turn.
	# force_sleep_wake overrides the wake/sleep outcome but does NOT suppress the
	# tick: force=false means "stay asleep regardless of counter"; force=true means
	# "wake regardless of counter". Counter still decrements in both cases.
	if mon.status == BattlePokemon.STATUS_SLEEP:
		mon.sleep_turns = max(0, mon.sleep_turns - 1)

		var wakes: bool
		if force_sleep_wake == null:
			wakes = mon.sleep_turns <= 0
		else:
			wakes = bool(force_sleep_wake)

		if wakes:
			mon.sleep_turns = 0
			mon.status = BattlePokemon.STATUS_NONE
			result["woke_up"] = true
			# Pokémon can use its move the turn it wakes — fall through to rest of checks
		else:
			result["can_move"] = false
			return result

	# ── Freeze ────────────────────────────────────────────────────────────
	# Source: battle_move_resolution.c L172–186, gated on !MoveThawsUser(cv->move).
	# When the attacker uses a thaws_user move, this block is skipped entirely —
	# the Pokémon stays frozen but can_move remains true; CancelerThaw
	# (our check_user_thaw in MOVE_EXECUTION) handles the thaw after the move fires.
	elif mon.status == BattlePokemon.STATUS_FREEZE and (move == null or not move.thaws_user):
		var thaws: bool
		if force_freeze_thaw == null:
			# 20% thaw: randi() % 100 < 20
			thaws = randi() % 100 < 20
		else:
			thaws = bool(force_freeze_thaw)

		if thaws:
			mon.status = BattlePokemon.STATUS_NONE
			result["thawed"] = true
		else:
			result["can_move"] = false
			return result

	# ── Flinch ────────────────────────────────────────────────────────────────
	# Source: battle_move_resolution.c :: CancelerFlinch (L298–316)
	# CANCELER_FLINCH (pos 34) fires before CANCELER_CONFUSED (pos 39).
	# Source clears the flag in the turn-boundary cleanup block (battle_main.c L5038
	# memset of gProtectStructs, same block that decrements isFirstTurn), NOT inside
	# CancelerFlinch itself. We clear it here on read for the same one-turn effect.
	if mon.flinched:
		mon.flinched = false
		result["flinched"] = true
		result["can_move"] = false
		return result

	# ── Confusion ─────────────────────────────────────────────────────────
	# Source: battle_move_resolution.c :: CancelerConfused L389–430
	# Decrement turns first. If still > 0: 33% self-hit chance.
	# If hits 0: snap out (move executes normally that turn).
	if mon.confusion_turns > 0:
		mon.confusion_turns -= 1
		if mon.confusion_turns > 0:
			# Still confused — roll for self-hit
			# B_CONFUSION_SELF_DMG_CHANCE = GEN_LATEST = GEN_7+ → 33%
			# Source: L398 RandomPercentage(RNG_CONFUSION, 33)
			var self_hits: bool
			if force_confusion_hit == null:
				self_hits = randi() % 100 < 33
			else:
				self_hits = bool(force_confusion_hit)

			if self_hits:
				result["self_hit_damage"] = DamageCalculator.calculate_confusion_damage(mon)
				result["can_move"] = false
				return result
			# Else: confused but didn't self-hit; continue to paralysis check
		else:
			# Snapped out of confusion — can still use move this turn
			result["snapped_out"] = true

	# ── Paralysis ─────────────────────────────────────────────────────────
	# Source: battle_move_resolution.c :: CancelerParalyzed L447–458
	# !RandomPercentage(RNG_PARALYSIS, 75) → 25% chance fully paralyzed.
	if mon.status == BattlePokemon.STATUS_PARALYSIS:
		var full_para: bool
		if force_full_para == null:
			# 25% full-para: randi() % 4 == 0
			full_para = randi() % 4 == 0
		else:
			full_para = bool(force_full_para)

		if full_para:
			result["can_move"] = false
			return result

	return result


# ── Freeze-thaw hooks (called from BattleManager.MOVE_EXECUTION) ─────────
#
# Both functions are extracted here so move_test.gd can call them directly
# rather than testing only through the full BattleManager loop.

# Target-thaw: clear freeze on a Pokémon that was hit by a Fire-type damaging move.
# Returns true if thaw occurred.
#
# Source: battle_script_commands.c :: CanFireMoveThawTarget (~L11041–11044)
#   B_HIT_THAW >= GEN_3: moveType == TYPE_FIRE && power > 0 && damage > 0
# Source: battle_move_resolution.c :: MoveEndDefrost (L3288–3314)
#   Runs after damage; checks IsBattlerTurnDamaged (damage > 0 covers this in singles).
static func check_target_thaw(defender: BattlePokemon, move: MoveData, damage: int) -> bool:
	if move.type == TypeChart.TYPE_FIRE \
			and move.power > 0 \
			and damage > 0 \
			and defender.status == BattlePokemon.STATUS_FREEZE:
		defender.status = BattlePokemon.STATUS_NONE
		return true
	return false


# User-thaw: clear the attacker's freeze when using a thawsUser move.
# Returns true if thaw occurred.
#
# Source: battle_move_resolution.c :: CancelerThaw (L586–622)
#   Fires after the attacker-canceler chain when MoveThawsUser(cv->move) is true.
# Source: move.h L455–457 (MoveThawsUser); moves: Flame Wheel, Sacred Fire,
#   Flare Blitz, Scald, Fusion Flare, Steam Eruption, Burn Up, Sizzly Slide,
#   Pyro Ball, Scorching Sands, Hydro Steam, Matcha Gotcha.
# None of the 20 Tier-1 moves carry thaws_user=true; this hook is wired now
# so it fires correctly when those moves are added in later milestones.
static func check_user_thaw(attacker: BattlePokemon, move: MoveData) -> bool:
	if move.thaws_user and attacker.status == BattlePokemon.STATUS_FREEZE:
		attacker.status = BattlePokemon.STATUS_NONE
		return true
	return false


# ── Accuracy check ───────────────────────────────────────────────────────────
#
# Returns true if the move hits the target, false if it misses.
# move.accuracy == 0 means always hits (accuracy = 0 is the "never misses" flag).
#
# Semi-invulnerable check fires BEFORE accuracy and before always-hit:
#   source: battle_move_resolution.c :: CancelerAccuracyCheck (L1993)
#   if !CanBreakThroughSemiInvulnerablity(attacker, defender, ...) → miss
#   CanBreakThroughSemiInvulnerablityInternal checks per-state move flags:
#     STATE_UNDERGROUND → MoveDamagesUnderground(move)  (e.g. Earthquake)
#     STATE_UNDERWATER  → MoveDamagesUnderWater(move)   (e.g. Surf)
#     STATE_ON_AIR      → MoveDamagesAirborne(move) || MoveDamagesAirborneDoubleDamage(move)
#
# Accuracy stage multiplier table — source: battle_script_commands.c L825
# Index 0 = combined stage -6, index 6 = stage 0 (neutral), index 12 = stage +6.
# Applied as: calc = moveAcc * ratio[idx][0] / ratio[idx][1]  (integer division).
# Combined stage = attacker_acc_stage - defender_eva_stage, clamped to [-6, +6].
# Source: src/battle_util.c :: GetTotalAccuracy (L10241–10281), no abilities/items for M5.
const ACCURACY_STAGE_RATIOS: Array = [
	[ 33, 100],  # -6
	[ 36, 100],  # -5
	[ 43, 100],  # -4
	[ 50, 100],  # -3
	[ 60, 100],  # -2
	[ 75, 100],  # -1
	[  1,   1],  #  0
	[133, 100],  # +1
	[166, 100],  # +2
	[  2,   1],  # +3
	[233, 100],  # +4
	[133,  50],  # +5
	[  3,   1],  # +6
]
#
# force_hit: null = use RNG; true = force hit; false = force miss.
#   When force_hit is non-null it overrides EVERYTHING including semi-invulnerable,
#   making it a pure test override (the source equivalent is No Guard ability).
# Stat stages for accuracy (STAGE_ACCURACY) and evasion (STAGE_EVASION) are applied.
# Abilities, held items, and weather are M8+ scope.
static func check_accuracy(
		attacker: BattlePokemon,
		defender: BattlePokemon,
		move: MoveData,
		force_hit: Variant = null) -> bool:
	# Test override — highest priority; bypasses all checks including semi-inv.
	if force_hit != null:
		return bool(force_hit)

	# Semi-invulnerable check: fires before accuracy roll and before always-hit.
	# Source: battle_move_resolution.c :: CancelerAccuracyCheck (L1993)
	if defender.semi_invulnerable != MoveData.SEMI_INV_NONE:
		if not _can_hit_semi_invulnerable(move, defender.semi_invulnerable):
			return false

	if move.accuracy == 0:
		return true  # always hits (Swift, Aerial Ace, Swords Dance, etc.)
	var acc_stage: int = attacker.stat_stages[BattlePokemon.STAGE_ACCURACY]
	var eva_stage: int = defender.stat_stages[BattlePokemon.STAGE_EVASION]
	var combined: int = clampi(acc_stage - eva_stage, -6, 6)
	var idx: int = combined + 6
	var calc: int = move.accuracy * ACCURACY_STAGE_RATIOS[idx][0] / ACCURACY_STAGE_RATIOS[idx][1]
	return randi() % 100 < calc


# Helper: can the attacking move hit a target in the given semi-invulnerable state?
# Source: battle_util.c :: CanBreakThroughSemiInvulnerablityInternal (L10464)
#   STATE_UNDERGROUND → MoveDamagesUnderground
#   STATE_UNDERWATER  → MoveDamagesUnderWater
#   STATE_ON_AIR      → MoveDamagesAirborne || MoveDamagesAirborneDoubleDamage
# In our model, damages_airborne covers both Airborne and AirborneDoubleDamage flags.
static func _can_hit_semi_invulnerable(move: MoveData, state: int) -> bool:
	match state:
		MoveData.SEMI_INV_UNDERGROUND: return move.damages_underground
		MoveData.SEMI_INV_ON_AIR:      return move.damages_airborne
		MoveData.SEMI_INV_UNDERWATER:  return move.damages_underwater
	return true  # STATE_NONE or unknown: no restriction


# ── Stat stage application ────────────────────────────────────────────────────
#
# Apply a stage change to a single stat on target. Returns the actual number of
# stages changed (0 if the stat was already at the limit and nothing changed).
#
# Source: src/battle_stat_change.c :: IncreaseStat / DecreaseStat / StatChanged
#   statStages[stat] += stage; then clamp [MIN_STAT_STAGE=0, MAX_STAT_STAGE=12].
#   In our -6..+6 system: clamp to [-6, +6].
#   At-limit behaviour: if already at max/min, returns 0 (caller should emit fail).
static func apply_stat_change(
		target: BattlePokemon,
		stat_idx: int,
		amount: int) -> int:
	var old_stage: int = target.stat_stages[stat_idx]
	if amount > 0 and old_stage >= 6:
		return 0   # already at +6 — nothing changed
	if amount < 0 and old_stage <= -6:
		return 0   # already at -6 — nothing changed
	var new_stage: int = clampi(old_stage + amount, -6, 6)
	var actual: int = new_stage - old_stage
	target.stat_stages[stat_idx] = new_stage
	return actual


# ── Secondary effect application ─────────────────────────────────────────────
#
# Roll and apply a move's secondary_effect to the target.  Returns true if the
# effect fired and was successfully applied; false if blocked or not rolled.
#
# For damaging moves: call only when damage > 0.
# For guaranteed effects (secondary_chance == 0): roll is skipped.
# force_secondary: null = RNG; true = force fire; false = force miss.
#   Setting force_secondary = false suppresses the effect but does NOT suppress
#   damage — the caller handles damage separately.
#
# Flinch (SE_FLINCH) is a special case: this function returns true to signal
# the caller that the flinch rolled, but the caller must decide whether to
# actually set the flinched flag based on turn order. The defender is NOT
# modified here for flinch.
#
# Source: src/battle_script_commands.c :: Cmd_setadditionaleffects (L3506)
#   RandomPercentage(RNG_SECONDARY_EFFECT, percentChance): fires if roll < chance.
#   Passes through SetMoveEffect → try_apply_status / try_apply_confusion for
#   status effects; for flinch sets volatiles.flinched = TRUE.
static func try_secondary_effect(
		attacker: BattlePokemon,
		defender: BattlePokemon,
		move: MoveData,
		force_secondary: Variant = null) -> bool:

	if move.secondary_effect == MoveData.SE_NONE:
		return false

	# Roll for secondary (skip if guaranteed: chance == 0)
	if move.secondary_chance > 0:
		var fires: bool
		if force_secondary == null:
			# RandomPercentage(RNG_SECONDARY_EFFECT, chance) → true with prob chance/100
			fires = randi() % 100 < move.secondary_chance
		else:
			fires = bool(force_secondary)
		if not fires:
			return false

	match move.secondary_effect:
		MoveData.SE_BURN:
			return try_apply_status(defender, BattlePokemon.STATUS_BURN)
		MoveData.SE_FREEZE:
			return try_apply_status(defender, BattlePokemon.STATUS_FREEZE)
		MoveData.SE_PARALYSIS:
			return try_apply_status(defender, BattlePokemon.STATUS_PARALYSIS)
		MoveData.SE_SLEEP:
			return try_apply_status(defender, BattlePokemon.STATUS_SLEEP)
		MoveData.SE_TOXIC:
			return try_apply_status(defender, BattlePokemon.STATUS_TOXIC)
		MoveData.SE_CONFUSION:
			return try_apply_confusion(defender)
		MoveData.SE_FLINCH:
			# Flinch: caller must check turn order and set defender.flinched.
			# We return true to signal the roll succeeded.
			return true
	return false


# ── Speed for priority resolution ─────────────────────────────────────────
#
# Returns the effective speed value used for turn-order sorting.
# Paralysis halves speed (Gen 7+). Stat stages applied.
#
# Source: battle_main.c L4712–4714
#   B_PARALYSIS_SPEED >= GEN_7 → speed /= 2   (was /= 4 before Gen 7)
static func effective_speed(mon: BattlePokemon) -> int:
	var spd: int = DamageCalculator._apply_stage(
			mon.speed, mon.stat_stages[BattlePokemon.STAGE_SPEED])
	if mon.status == BattlePokemon.STATUS_PARALYSIS:
		spd /= 2
	# M12: Choice Scarf — (speed * 150) / 100 integer arithmetic.
	# Source: battle_main.c GetChoiceScarf case (L4703–4704).
	return ItemManager.apply_speed_modifier(mon, spd)
