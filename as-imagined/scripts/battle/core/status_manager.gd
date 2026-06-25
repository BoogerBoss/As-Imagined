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
		force_full_para: Variant = null) -> Dictionary:

	var result := {
		"can_move":        true,
		"self_hit_damage": 0,
		"woke_up":         false,
		"thawed":          false,
		"snapped_out":     false,
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
	# Source: battle_move_resolution.c L172–186
	# 20% chance to thaw each turn (RandomPercentage(RNG_FROZEN, 20)).
	elif mon.status == BattlePokemon.STATUS_FREEZE:
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
	return spd
