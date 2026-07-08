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
# Returns true if the status was applied, false if blocked by type immunity,
# ability immunity, or by the Pokémon already having a major status.
#
# force_sleep_turns: Variant — null = random 2–4; int value = pin duration
#   (only meaningful when status == BattlePokemon.STATUS_SLEEP)
# ally: mon's doubles partner (for Sweet Veil/Pastel Veil's ally-wide protection) —
#   null in singles or when unresolved by the caller.
#
# M17b ability-based immunities (the FIRST ability-based status immunities in this
# codebase — every prior check here was purely type-based):
#   ABILITY_PURIFYING_SALT (battle_util.c L5359-5361, same shape as Comatose): immune
#     to ALL non-volatile statuses, self only (no ally-wide check in source).
#   ABILITY_SWEET_VEIL (battle_util.c L5322-5327): immune to SLEEP specifically,
#     self OR ally (IsAbilityOnSide).
#   ABILITY_PASTEL_VEIL (battle_util.c L5254-5259): immune to POISON/TOXIC specifically,
#     self OR ally (IsAbilityOnSide). (Pastel Veil's OTHER half — curing the holder's
#     own pre-existing poison on switch-in — is in AbilityManager.try_switch_in.)
#
# M17n-1 additions, same function (CanSetNonVolatileStatus, L5235-5394), same
# ability-immunity block:
#   ABILITY_INSOMNIA / ABILITY_VITAL_SPIRIT (L5330-5334, MOVE_EFFECT_SLEEP case) —
#     immune to SLEEP specifically; confirmed via source these are genuinely the same
#     case branch, not just similarly-shaped.
#   ABILITY_IMMUNITY (L5261-5265, MOVE_EFFECT_POISON/TOXIC case) — immune to
#     POISON/TOXIC specifically (any type, not just the Poison/Steel type-immunity
#     already checked above at L5250-5253).
#   ABILITY_LIMBER (L5280-5284, MOVE_EFFECT_PARALYSIS case) — immune to PARALYSIS
#     specifically.
#   ABILITY_WATER_VEIL (L5295-5299, MOVE_EFFECT_BURN case — source also lists
#     ABILITY_WATER_BUBBLE in the same branch; Water Bubble isn't implemented in this
#     project yet, so only Water Veil is wired here) — immune to BURN specifically.
#   ABILITY_MAGMA_ARMOR (L5346-5350, MOVE_EFFECT_FREEZE case) — immune to FREEZE
#     specifically.
#   ABILITY_LEAF_GUARD (`IsLeafGuardProtected`, battle_script_commands.c L6846-6852,
#     called from L5370 — OUTSIDE the per-effect switch, applying to ALL
#     non-volatile statuses uniformly) — immune while harsh sun is active RIGHT NOW
#     (checked fresh every call via the new `weather` param, not cached — this
#     function is a stateless static already called fresh each time). Source gates
#     sun-detection through `IsBattlerWeatherAffected` (Utility-Umbrella-aware), but
#     this project's existing weather-conditional ABILITY checks (Flower Gift/Solar
#     Power/Slush Rush/Dry Skin) never consult `ItemManager.blocks_weather_modifier`
#     either — that helper is only ever consulted inside the damage-multiplier
#     pipeline — so Leaf Guard follows the same established precedent rather than
#     introducing a new nuance none of its siblings have. Leaf Guard's OTHER two
#     effects (Leech Seed/Yawn immunity) are N/A — neither move exists in this
#     project yet, confirmed via a roster grep.
# All six confirmed `breakable = TRUE` in src/data/abilities.h, same Mold-Breaker
# reachability as Purifying Salt/Sweet Veil/Pastel Veil above.
#
# weather: int — WEATHER_* constant (DamageCalculator), default WEATHER_NONE — needed
#   only for Leaf Guard's sun gate. Threaded through from try_secondary_effect (the
#   single choke point for all move-based status infliction, primary or secondary);
#   NOT threaded through the contact-ability-triggered call sites (Static/Poison
#   Point/Effect Spore/Synchronize in ability_manager.gd) or the switch-in-hazard call
#   site — a narrow, documented scope-limitation (Leaf Guard won't block those specific
#   ability-triggered infliction paths while in sun), matching the same category of
#   simplification `[M17c]`'s Slush Rush left for the two TrainerAI call sites.
static func try_apply_status(
		mon: BattlePokemon,
		status: int,
		force_sleep_turns: Variant = null,
		ally: BattlePokemon = null,
		ng_active: bool = false,
		attacker: BattlePokemon = null,
		weather: int = DamageCalculator.WEATHER_NONE,
		attacker_move: MoveData = null) -> bool:

	# One major status at a time.
	# Source: CanSetNonVolatileStatus L5391 — "already has STATUS1_ANY → fails"
	if mon.status != BattlePokemon.STATUS_NONE:
		return false

	# M17g: Purifying Salt/Sweet Veil/Pastel Veil are all flagged `.breakable = TRUE`
	# in source, so a Mold-Breaker-holder's status move bypasses these immunities the
	# same way it bypasses any other breakable defensive ability — `attacker` is
	# threaded through for exactly that (null at every non-move call site, e.g. hazard
	# poisoning on switch-in, correctly leaving Mold Breaker inapplicable there).
	# M17n-3: `attacker_move` additionally threads through Mycelium Might's
	# status-move-gated Mold-Breaker-type bypass (see `effective_ability_id`'s doc
	# comment) — null at every pre-existing call site, unaffected.
	var mon_id: int = AbilityManager.effective_ability_id(mon, ng_active, attacker, attacker_move)
	# M17n-11: Comatose — full immunity to ALL non-volatile statuses, the SAME shape
	# and the SAME source case branch as Purifying Salt (battle_util.c L5359-5361:
	# `abilityDef == ABILITY_COMATOSE || abilityDef == ABILITY_PURIFYING_SALT`) —
	# confirmed genuinely identical, not just similarly-shaped, unlike Comatose is NOT
	# `breakable` in source (Purifying Salt is), so the SAME `effective_ability_id`
	# call above already yields the correct per-ability Mold-Breaker behavior for each
	# without any extra branching. This is the ONLY piece of Comatose's real source
	# mechanic this project can implement — every other Comatose call site in source
	# (Sleep Talk/Snore's "is the user asleep" gate, Rest's "already asleep" failure,
	# Nightmare's continued damage, Wake-Up-Slap-style double-damage-vs-asleep) has
	# NOTHING to hook into, since none of Sleep Talk/Snore/Rest/Nightmare/Wake-Up Slap
	# exist in this project's 91-move roster (confirmed via grep) — flagged here as a
	# confirmed, deliberate scope limitation, not a silently dropped feature. See this
	# session's `[M17n-11]` decisions.md entry for the full citation list.
	if mon_id == AbilityManager.ABILITY_PURIFYING_SALT or mon_id == AbilityManager.ABILITY_COMATOSE:
		return false
	if mon_id == AbilityManager.ABILITY_LEAF_GUARD and weather == DamageCalculator.WEATHER_SUN:
		return false

	var ally_ability_id: int = \
			AbilityManager.effective_ability_id(ally, ng_active, attacker, attacker_move) \
			if (ally != null and not ally.fainted) else -1
	if status == BattlePokemon.STATUS_SLEEP:
		if mon_id == AbilityManager.ABILITY_SWEET_VEIL \
				or ally_ability_id == AbilityManager.ABILITY_SWEET_VEIL:
			return false
		if mon_id == AbilityManager.ABILITY_INSOMNIA or mon_id == AbilityManager.ABILITY_VITAL_SPIRIT:
			return false
	if status == BattlePokemon.STATUS_POISON or status == BattlePokemon.STATUS_TOXIC:
		if mon_id == AbilityManager.ABILITY_PASTEL_VEIL \
				or ally_ability_id == AbilityManager.ABILITY_PASTEL_VEIL:
			return false
		if mon_id == AbilityManager.ABILITY_IMMUNITY:
			return false
	if status == BattlePokemon.STATUS_PARALYSIS and mon_id == AbilityManager.ABILITY_LIMBER:
		return false
	if status == BattlePokemon.STATUS_BURN and mon_id == AbilityManager.ABILITY_WATER_VEIL:
		return false
	if status == BattlePokemon.STATUS_FREEZE and mon_id == AbilityManager.ABILITY_MAGMA_ARMOR:
		return false

	# Type immunities — source: CanSetNonVolatileStatus L5244–5354
	match status:
		BattlePokemon.STATUS_BURN:
			# Fire-types cannot be burned — source: L5291–5294
			if TypeChart.TYPE_FIRE in mon.species.types:
				return false

		BattlePokemon.STATUS_POISON, BattlePokemon.STATUS_TOXIC:
			# Poison-types and Steel-types cannot be poisoned — source: L5250–5252.
			# M17n-8: Corrosion (the ATTACKER's own ability, not `mon`'s) bypasses this
			# immunity entirely — closes the gap M3's own comment flagged and deferred.
			if (TypeChart.TYPE_POISON in mon.species.types or \
					TypeChart.TYPE_STEEL in mon.species.types) \
					and not (attacker != null \
							and AbilityManager.bypasses_poison_steel_immunity(attacker, ng_active)):
				return false

		BattlePokemon.STATUS_PARALYSIS:
			# Electric-types cannot be paralyzed (B_PARALYZE_ELECTRIC >= GEN_6) — source: L5272–5274
			if TypeChart.TYPE_ELECTRIC in mon.species.types:
				return false

		BattlePokemon.STATUS_FREEZE:
			# Ice-types cannot be frozen, OR harsh sunlight prevents freezing
			# entirely (any type) — source: battle_util.c L5342-5343:
			# `IS_BATTLER_OF_TYPE(battlerDef, TYPE_ICE) ||
			# IsBattlerWeatherAffected(..., B_WEATHER_SUN)`. [M17.5 Batch Fix]:
			# the Sun half was deferred at M3 with a "weather not in scope"
			# comment that's now stale — weather (and this exact `weather` param)
			# has existed since M11/M17c. Deliberately does NOT consult
			# `ItemManager.blocks_weather_modifier` (Utility Umbrella) even though
			# source's `IsBattlerWeatherAffected` does — matching this project's
			# own established precedent that its weather-conditional ABILITY
			# checks (Leaf Guard, Flower Gift, Solar Power, Slush Rush, Dry Skin)
			# never consult that helper, which is reserved for the damage-
			# multiplier pipeline only (see this function's own header comment).
			if TypeChart.TYPE_ICE in mon.species.types \
					or weather == DamageCalculator.WEATHER_SUN:
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
# Returns true if confusion was applied, false if already confused or blocked.
#
# force_confusion_turns: Variant — null = random 2–5; int = pin duration
#   Source: battle_script_commands.c L2363
#   RandomUniform(2, B_CONFUSION_TURNS=5) — comment: "2–5 turns"
#
# M17n-1: ABILITY_OWN_TEMPO (battle_util.c :: CanBeConfused, L5447-5458) blocks new
# confusion infliction outright — `breakable = TRUE` (src/data/abilities.h), so a
# Mold-Breaker-holding attacker bypasses it, same reachability shape as every other
# breakable defensive check in this project (attacker and mon are always different
# battlers for any move-inflicted confusion). Own Tempo does NOT cure pre-existing
# confusion on gaining the ability (this project has no Skill Swap/Entrainment-style
# ability-transfer move, so that half is N/A, not a dropped check).
#
# M18u: `infinite` — Berserk Gene's confusion never wears off naturally (source:
# `CanBeInfinitelyConfused`/`infiniteConfusion` volatile, battle_hold_effects.c
# L125-141, battle_move_resolution.c L389-393). Of source's three exemptions
# (Own Tempo / Misty Terrain / Safeguard), only Own Tempo is reachable in this
# project (Misty Terrain is void per M17e, Safeguard doesn't exist) — and Own
# Tempo already blocks confusion APPLICATION entirely via the check below, so no
# separate gate is needed for the infinite half specifically. Set on EVERY
# successful application (defaulting false), not just Berserk Gene's — this
# means a later ordinary confusion (Confuse Ray etc.) correctly overwrites a
# stale `true` left by an earlier Berserk Gene use, without needing to touch any
# of this project's several confusion_turns=0 reset sites.
static func try_apply_confusion(
		mon: BattlePokemon,
		force_confusion_turns: Variant = null,
		ng_active: bool = false,
		attacker: BattlePokemon = null,
		attacker_move: MoveData = null,
		infinite: bool = false) -> bool:

	if mon.confusion_turns > 0:
		return false  # already confused

	# M17n-3: `attacker_move` threads through Mycelium Might's status-move-gated
	# Mold-Breaker-type bypass of Own Tempo, null (no bypass) at every pre-existing
	# call site.
	if AbilityManager.effective_ability_id(mon, ng_active, attacker, attacker_move) \
			== AbilityManager.ABILITY_OWN_TEMPO:
		return false

	mon.confusion_turns = force_confusion_turns if force_confusion_turns != null \
			else randi_range(2, 5)
	mon.infinite_confusion = infinite
	return true


# [M18.5d-2] try_apply_attract: attempt to inflict infatuation (a volatile status,
# structurally the closest existing precedent is try_apply_confusion just above —
# confirmed at Step 0 to be the right structural match: both are chance-free-on-
# infliction volatiles with their own separate per-turn move-cancel check). The ONE
# real structural difference from confusion: infatuation is gender-pair-gated and
# has no turn counter (a single persistent bool, cured only by switch-out, not by
# a countdown) — genuinely different from confusion's 2-5 turn countdown, so this
# is NOT a copy-paste of try_apply_confusion's shape despite the shared precedent.
#
# Shared by BOTH real inflictors — Attract the move (battle_manager.gd's own
# `is_attract` dispatch) and Cute Charm the ability (AbilityManager.
# try_contact_effects) — confirmed genuinely unified in source (see
# AbilityManager.attract_block_reason's own doc comment for the two source
# citations), so this project builds ONE shared function rather than duplicating
# the already-required/gender/block checks at both call sites.
#
# `victim` = who is about to become infatuated. `inflictor` = who caused it — used
# for the gender-pair check AND [M18.5d-3] recorded directly onto
# `victim.infatuated_by`, so a later departure of `inflictor` from the field
# correctly cures `victim` (see BattlePokemon.infatuated_by's own doc comment).
# `victim_ally`/`attacker`/`attacker_move` thread straight through to
# AbilityManager.attract_block_reason — see that function's own doc comment for
# their exact meaning (attacker/attacker_move are Mold-Breaker/Mycelium-Might
# bypass context, null for Cute Charm's non-move call).
#
# Returns "" on success, else a fail-reason tag: "oblivious" / "aroma_veil"
# (blocked by an ability — source plays a distinct message for these under
# Attract; Cute Charm's own source has no such message, silently no-ops either
# way) or "already_infatuated" / "not_opposite_gender" (ordinary failure, not a
# block — source's own generic failInstr fallback, no distinction between the two
# either, matching AreBattlersOfOppositeGender's own unified false-for-both shape).
static func try_apply_attract(
		victim: BattlePokemon,
		inflictor: BattlePokemon,
		victim_ally: BattlePokemon = null,
		ng_active: bool = false,
		attacker: BattlePokemon = null,
		attacker_move: MoveData = null) -> String:

	var block_reason: String = AbilityManager.attract_block_reason(
			victim, victim_ally, ng_active, attacker, attacker_move)
	if block_reason != "":
		return block_reason
	if victim.infatuated_by != null:
		return "already_infatuated"
	if not BattlePokemon.are_opposite_gender(inflictor, victim):
		return "not_opposite_gender"

	victim.infatuated_by = inflictor
	return ""


# [M18.5f] Bind/Wrap-family trap application — the MOVE_EFFECT_WRAP additional
# effect shared identically by Bind/Wrap/Fire Spin/Clamp/Whirlpool/Sand
# Tomb/Magma Storm/Infestation/Snap Trap/Thunder Cage. Source:
# battle_script_commands.c L2465-2477 — if already wrapped, silently continues
# (no re-trap, no stacking, no fail message); otherwise sets wrappedBy and rolls
# a fresh duration via SetWrapTurns (battle_util.c L10726-10738). No Ghost-type
# gate here — Ghost-types ARE tracked as wrapped (still take the recurring
# damage) and only get their free-switch exemption from
# AbilityManager.is_trapped()'s existing Ghost check, not from being immune to
# the trap volatile itself (confirmed via CanBattlerEscape, battle_util.c
# L4943-4960, whose Ghost branch is checked BEFORE its wrapped branch).
# force_wrap_turns: Variant — null = random 4-5 (RandomUniform, B_BINDING_TURNS
#   >= GEN_5 branch, this project's default config); int value = pin duration
#   for deterministic testing, matching force_sleep_turns's own established seam
#   shape. Grip Claw's 7-turn fixed extension is out of scope (deferred M18.5i).
static func try_apply_wrap(
		victim: BattlePokemon,
		inflictor: BattlePokemon,
		force_wrap_turns: Variant = null) -> bool:

	if victim.wrapped_by != null:
		return false

	victim.wrapped_by = inflictor
	victim.wrapped_turns = force_wrap_turns if force_wrap_turns != null \
			else randi_range(4, 5)
	return true


# ── End-of-turn status damage ─────────────────────────────────────────────
#
# Returns the HP to subtract this end-of-turn (positive), or the HP to RESTORE
# (negative — Poison Heal only). 0 = no effect.
# For toxic this also increments the counter (must call exactly once per turn) —
# note Poison Heal's holder still increments the counter while poisoned/toxic
# (source keeps ticking it even though the ability heals instead of damaging),
# so the counter advance happens unconditionally before the ability check.
#
# Source:
#   burn   — battle_end_turn.c :: HandleEndTurnBurn L577
#             maxHP / 16 (B_BURN_DAMAGE = GEN_LATEST = GEN_7+)
#   poison — battle_end_turn.c :: HandleEndTurnPoison L556
#             maxHP / 8
#   toxic  — battle_end_turn.c :: HandleEndTurnPoison L547–550
#             counter increments first (cap at 15), then damage = (maxHP/16) * counter
#
# M17d: ABILITY_POISON_HEAL (L533-544) — inverts the poison/toxic branch entirely:
#   instead of damage, heals maxHP/8 (flat, NOT counter-scaled even while toxic),
#   gated on not already at max HP. This is the SAME central function every
#   poison/toxic/burn end-of-turn tick in this project already goes through — no
#   parallel poison-damage path, just a branch inside the existing one.
static func end_of_turn_damage(mon: BattlePokemon, ng_active: bool = false) -> int:
	var has_poison_heal: bool = \
			AbilityManager.effective_ability_id(mon, ng_active) == AbilityManager.ABILITY_POISON_HEAL
	# M17n-9: Magic Guard — zero damage from burn/poison/toxic, but the toxic
	# counter still ticks (source: HandleEndTurnPoison L526-530 increments the
	# counter INSIDE the Magic Guard branch, identical to how Poison Heal's own
	# branch below also keeps ticking it) — checked first, matching source's
	# if/Magic-Guard else-if/Poison-Heal else-if chain (battle_end_turn.c L526-556).
	var has_magic_guard: bool = AbilityManager.blocks_indirect_damage(mon, ng_active)

	match mon.status:
		BattlePokemon.STATUS_BURN:
			if has_magic_guard:
				return 0
			return max(1, mon.max_hp / 16)

		BattlePokemon.STATUS_POISON:
			if has_magic_guard:
				return 0
			if has_poison_heal:
				return -_poison_heal_amount(mon)
			return max(1, mon.max_hp / 8)

		BattlePokemon.STATUS_TOXIC:
			# Increment then multiply — source: L548–550
			# "(status & STATUS1_TOXIC_COUNTER) != STATUS1_TOXIC_TURN(15)" = cap at 15
			mon.toxic_counter = mini(mon.toxic_counter + 1, 15)
			if has_magic_guard:
				return 0
			if has_poison_heal:
				return -_poison_heal_amount(mon)
			return max(1, mon.max_hp / 16 * mon.toxic_counter)

	return 0


static func _poison_heal_amount(mon: BattlePokemon) -> int:
	if mon.current_hp >= mon.max_hp:
		return 0
	return max(1, mon.max_hp / 8)


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
#   "loafing"         : bool — true if Truant blocked the move this turn (M17c)
#
# Force parameters (all Variant):
#   null = use RNG   |   true / false = pin the outcome
#   force_sleep_wake     : true = wake this turn, false = stay asleep
#   force_freeze_thaw    : true = thaw this turn, false = stay frozen
#   force_confusion_hit  : true = self-hit, false = snap out / no self-hit
#   force_full_para      : true = fully paralyzed, false = can move
#   force_infatuation_hit: [M18.5d-2] true = stuck (can't move), false = can move
static func pre_move_check(
		mon: BattlePokemon,
		force_sleep_wake: Variant = null,
		force_freeze_thaw: Variant = null,
		force_confusion_hit: Variant = null,
		force_full_para: Variant = null,
		move: MoveData = null,
		ng_active: bool = false,
		force_infatuation_hit: Variant = null) -> Dictionary:

	var result := {
		"can_move":        true,
		"self_hit_damage": 0,
		"woke_up":         false,
		"thawed":          false,
		"snapped_out":     false,
		"flinched":        false,
		"loafing":         false,
		"infatuated_stuck": false,
	}

	# ── Sleep ──────────────────────────────────────────────────────────────
	# Source: battle_move_resolution.c L120–169
	# Counter decrements by 1 each attempt (toSub=1), or by 2 with Early Bird
	# (toSub=2 — M17n-1, battle_move_resolution.c L133-137:
	#   `if (IsAbilityAndRecord(..., ABILITY_EARLY_BIRD)) toSub = 2; else toSub = 1;`
	#   then clamped so the counter never goes negative, matching this project's
	#   existing `max(0, ...)` clamp exactly). Early Bird is NOT breakable in source
	#   (no `.breakable` flag on it) — this is the holder's own passive self-check, not
	#   a defensive ability an attacker's Mold Breaker would have any bearing on.
	# If still > 0 → can't move. If hits 0 → wake and can move that turn.
	# force_sleep_wake overrides the wake/sleep outcome but does NOT suppress the
	# tick: force=false means "stay asleep regardless of counter"; force=true means
	# "wake regardless of counter". Counter still decrements in both cases.
	if mon.status == BattlePokemon.STATUS_SLEEP:
		var sleep_to_sub: int = 2 if AbilityManager.effective_ability_id(mon, ng_active) == AbilityManager.ABILITY_EARLY_BIRD else 1
		mon.sleep_turns = max(0, mon.sleep_turns - sleep_to_sub)

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

	# ── Truant ────────────────────────────────────────────────────────────────
	# Source: battle_move_resolution.c :: CancelerTruant (L258-270) — CANCELER_TRUANT
	# fires after CANCELER_ASLEEP_OR_FROZEN but before CANCELER_FLINCH, matching this
	# function's Sleep/Freeze-then-Flinch ordering.
	# M17c: AbilityManager.try_end_of_turn toggles BattlePokemon.truant_loafing every end
	# of turn (XOR) when the holder has Truant; if it's currently true, the move fails
	# outright ("loafing around") with no PP cost and no other side effect.
	if AbilityManager.effective_ability_id(mon, ng_active) == AbilityManager.ABILITY_TRUANT \
			and mon.truant_loafing:
		result["can_move"] = false
		result["loafing"] = true
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
	# M18u: `infinite_confusion` (Berserk Gene) skips the decrement entirely —
	# source's exact `confusionTurns > 0 && !infiniteConfusion` gate (L389-393).
	if mon.confusion_turns > 0:
		if not mon.infinite_confusion:
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

	# ── Infatuation ───────────────────────────────────────────────────────
	# Source: battle_move_resolution.c :: CancelerInfatuation L460-479 — the LAST
	# canceler in source's own order (Asleep/Frozen -> Truant -> Flinch -> Confused
	# -> Paralyzed -> Infatuation), matching this function's own check order exactly.
	# !RandomPercentage(RNG_INFATUATION, 50) -> 50% chance stuck in love, can't move.
	# Source's `gBattleScripting.battler = infatuation - 1` (which battler caused it)
	# is flavor-text-only — irrelevant here, this project has no text system, even
	# though [M18.5d-3] now tracks the same "who" via `infatuated_by` for the
	# cross-battler cure check (BattleManager._clear_volatiles), not for messages.
	if mon.infatuated_by != null:
		var stuck: bool
		if force_infatuation_hit == null:
			stuck = randi() % 100 < 50
		else:
			stuck = bool(force_infatuation_hit)

		if stuck:
			result["infatuated_stuck"] = true
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
# M17a: No Guard (either battler) and Compound Eyes/Hustle (attacker) are now modeled.
# M17n-2: Sand Veil/Snow Cloak (defender, weather-gated) added — `weather` should be
#   the EFFECTIVE weather (see `BattleManager._effective_weather()`), so Air
#   Lock/Cloud Nine negation is automatic here too.
static func check_accuracy(
		attacker: BattlePokemon,
		defender: BattlePokemon,
		move: MoveData,
		force_hit: Variant = null,
		ng_active: bool = false,
		weather: int = DamageCalculator.WEATHER_NONE,
		target_already_acted: bool = false) -> bool:
	# Test override — highest priority; bypasses all checks including semi-inv.
	if force_hit != null:
		return bool(force_hit)

	# M17a: No Guard — always hits, bypassing BOTH the accuracy roll and the
	# semi-invulnerable gate below (matching source's ordering: the No Guard check
	# happens before CancelerAccuracyCheck's semi-invulnerable test).
	# Source: battle_util.c L10182-10193.
	if AbilityManager.bypasses_accuracy_check(attacker, defender, ng_active):
		return true

	# Semi-invulnerable check: fires before accuracy roll and before always-hit.
	# Source: battle_move_resolution.c :: CancelerAccuracyCheck (L1993)
	if defender.semi_invulnerable != MoveData.SEMI_INV_NONE:
		if not _can_hit_semi_invulnerable(move, defender.semi_invulnerable):
			return false

	if move.accuracy == 0:
		return true  # always hits (Swift, Aerial Ace, Swords Dance, etc.)
	var acc_stage: int = attacker.stat_stages[BattlePokemon.STAGE_ACCURACY]
	var eva_stage: int = defender.stat_stages[BattlePokemon.STAGE_EVASION]
	# M17b: Unaware (defender) ignores the ATTACKER's own accuracy stage; Unaware or
	# Keen Eye (attacker) ignores the DEFENDER's evasion stage. Both reset to neutral
	# (0), not just when positive — source's GetTotalAccuracy (L10251-10257) resets
	# unconditionally.
	if AbilityManager.ignores_attacker_accuracy_stage(defender, ng_active, attacker):
		acc_stage = 0
	if AbilityManager.ignores_defender_evasion_stage(attacker, ng_active):
		eva_stage = 0
	var combined: int = clampi(acc_stage - eva_stage, -6, 6)
	var idx: int = combined + 6
	# M17n-11: Wonder Skin — floors a STATUS move's own accuracy stat to 50 (never
	# raises an already-≤50 one) before the stage-ratio multiplication below, exactly
	# where source reassigns `moveAcc` itself (battle_util.c L10275-10276) rather than
	# adjusting the final computed chance — so an attacker's OTHER accuracy-boosting
	# abilities/stages still apply on top of the floored value afterward, unaffected.
	var effective_move_acc: int = move.accuracy
	if move.category == 2 and effective_move_acc > 50 \
			and AbilityManager.effective_ability_id(defender, ng_active, attacker) == AbilityManager.ABILITY_WONDER_SKIN:
		effective_move_acc = 50
	var calc: int = effective_move_acc * ACCURACY_STAGE_RATIOS[idx][0] / ACCURACY_STAGE_RATIOS[idx][1]

	# M17a: Compound Eyes (×1.30) / Hustle (physical ×0.80) — same "calc" integer-percentage
	# math source uses. Source: battle_util.c :: GetTotalAccuracy (L10283-10295).
	var ability_pct: int = AbilityManager.accuracy_modifier_percent(
			attacker, move, ng_active, defender, weather)
	if ability_pct != 100:
		calc = calc * ability_pct / 100

	# M18c: Micle Berry — one-shot ×1.2 (Ripen: ×1.4) for exactly this accuracy
	# check. A flag read, not a held-item read (the berry is already consumed by
	# the time this fires) — no Klutz gate, matching source (battle_util.c
	# L10357-10362). The caller clears `attacker.micle_boost_active` right after
	# this function returns, consuming it for exactly one check (hit or miss).
	var item_pct: int = ItemManager.micle_accuracy_modifier_percent(attacker)
	if item_pct != 100:
		calc = calc * item_pct / 100

	# M18j: Wide Lens/Zoom Lens (attacker-side) and Bright Powder/Lax Incense
	# (defender-side), same "calc" integer-percentage slot as the ability/Micle
	# modifiers above. Source: GetTotalAccuracy's item switches (battle_util.c
	# L10334-10354).
	var lens_pct: int = ItemManager.accuracy_modifier_percent(
			attacker, defender, ng_active, target_already_acted)
	if lens_pct != 100:
		calc = calc * lens_pct / 100

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
# stages changed (0 if the stat was already at the limit, or the change was
# blocked by an ability, and nothing changed).
#
# Source: src/battle_stat_change.c :: IncreaseStat / DecreaseStat / StatChanged
#   statStages[stat] += stage; then clamp [MIN_STAT_STAGE=0, MAX_STAT_STAGE=12].
#   In our -6..+6 system: clamp to [-6, +6].
#   At-limit behaviour: if already at max/min, returns 0 (caller should emit fail).
#
# M17b: this single central function is where ALL of this project's stat-stage
# moves/abilities/items already converge, so the three M17b mechanism shapes hook
# in here directly rather than touching every call site:
#   1. AdjustStatStage (battle_stat_change.c L797-815) — Simple/Contrary transform
#      the raw `amount` BEFORE anything else (matches source's call order: this runs
#      first, THEN the result's sign determines whether a decrease-block check
#      applies at all — so a Contrary-flipped "decrease" that becomes an increase is
#      correctly never blocked by Clear Body etc.).
#   2. CanAbilityPreventStatLoss / AbilityPreventsSpecificStatDrop / IsFlowerVeilBlocked
#      (battle_stat_change.c L823-634, called via TrySingleStatChange → CanDecreaseStat,
#      L294-321) — only evaluated when the (possibly Simple/Contrary-adjusted) amount
#      is negative.
#   3. BS_TryDefiantRattled / ShouldDefiantCompetitiveActivate (battle_script_commands.c
#      L13885, battle_util.c L1149) — Defiant/Competitive's follow-up +2 raise when a
#      decrease actually lands. NOT folded into this function (would need a Dictionary
#      return touching every one of this function's 30+ call sites for a follow-up that
#      only matters at the two places an OPPONENT actually lowers another Pokémon's
#      stat in this project: direct stat-lowering moves like Growl, and Intimidate).
#      Wired explicitly at those two call sites instead — see
#      AbilityManager.defiant_competitive_stat() and its callers in battle_manager.gd's
#      generic move-stat-change handler and AbilityManager.try_switch_in's Intimidate
#      branch. Known simplification: indirect opponent-caused decreases (e.g. Cotton
#      Down lowering the ATTACKER's Speed) don't check Defiant/Competitive on that
#      attacker — flagged, not silently assumed correct.
#
# ally: target's doubles partner (for Flower Veil's ally-wide protection) — null in
#   singles or when unresolved by the caller.
static func apply_stat_change(
		target: BattlePokemon,
		stat_idx: int,
		amount: int,
		ally: BattlePokemon = null,
		ng_active: bool = false,
		attacker: BattlePokemon = null) -> int:
	var adjusted: int = AbilityManager.adjust_stat_stage_amount(target, amount, ng_active, attacker)

	if adjusted < 0 and AbilityManager.blocks_stat_decrease(target, stat_idx, ally, ng_active, attacker):
		return 0

	var old_stage: int = target.stat_stages[stat_idx]
	if adjusted > 0 and old_stage >= 6:
		return 0   # already at +6 — nothing changed
	if adjusted < 0 and old_stage <= -6:
		return 0   # already at -6 — nothing changed
	var new_stage: int = clampi(old_stage + adjusted, -6, 6)
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
#
# M17n-1: ABILITY_SHIELD_DUST (battle_util.c :: IsMoveEffectBlockedByTarget, L9811-9824,
#   called only when `!primary` — i.e. a TRUE secondary effect, chance-based, never a
#   guaranteed/primary one) blocks the ENTIRE secondary effect from applying at all —
#   status, confusion, AND flinch alike, confirmed via source's single shared gate
#   rather than a per-effect-type check. Gated on `move.secondary_chance > 0` here to
#   mirror that `!primary` condition exactly (a guaranteed SE_* with chance 0, e.g. a
#   pure status move, is NOT blocked by Shield Dust). `breakable = TRUE`.
#   ABILITY_INNER_FOCUS (battle_util.c L8830, CancelerFlinch-adjacent) blocks flinch
#   SPECIFICALLY, not other secondary effects — a narrower, separate check inside the
#   SE_FLINCH case only, not the broad Shield-Dust-style gate above.
# weather: int — WEATHER_* constant, default WEATHER_NONE — threaded through to
#   try_apply_status for Leaf Guard's sun gate (see that function's doc comment).
static func try_secondary_effect(
		attacker: BattlePokemon,
		defender: BattlePokemon,
		move: MoveData,
		force_secondary: Variant = null,
		ng_active: bool = false,
		weather: int = DamageCalculator.WEATHER_NONE) -> bool:

	if move.secondary_effect == MoveData.SE_NONE:
		return false

	# Roll for secondary (skip if guaranteed: chance == 0)
	var is_true_secondary: bool = move.secondary_chance > 0
	if is_true_secondary:
		# M17n-5: Serene Grace doubles the ATTACKER's secondary-effect chance. Source:
		# CalcSecondaryEffectChance (battle_util.c L9436-9450): `secondaryEffectChance
		# * 2` (a Rainbow-status interaction also doubles it further, not modeled — no
		# Rainbow side status exists in this project). Explicitly capped at 100 here —
		# not strictly required given this project's `randi() % 100 < chance` roll
		# shape (any chance > 99 is already always-true by construction), but source's
		# own `MoveEffectIsGuaranteed` helper (L9453-9456) treats `>= 100` as
		# guaranteed explicitly, so the cap is added for clarity/parity rather than
		# relying on an incidental property of this project's roll implementation.
		var effective_chance: int = move.secondary_chance
		if AbilityManager.effective_ability_id(attacker, ng_active) == AbilityManager.ABILITY_SERENE_GRACE:
			effective_chance = mini(effective_chance * 2, 100)
		var fires: bool
		if force_secondary == null:
			# RandomPercentage(RNG_SECONDARY_EFFECT, chance) → true with prob chance/100
			fires = randi() % 100 < effective_chance
		else:
			fires = bool(force_secondary)
		if not fires:
			return false

	# M17n-3: `move` is passed through as `attacker_move` below — Mycelium Might's
	# status-move-gated Mold-Breaker-type bypass applies uniformly to every ability
	# check made while processing one move (source's `moldBreakerActive` is a single
	# flag consulted by every check during that move's resolution, not re-derived
	# per-check), so Shield Dust/Inner Focus are threaded through identically to the
	# status/confusion calls below.
	if is_true_secondary \
			and AbilityManager.effective_ability_id(defender, ng_active, attacker, move) \
					== AbilityManager.ABILITY_SHIELD_DUST:
		return false

	# M18x: Covert Cloak — the EXACT SAME gate as Shield Dust above, item-based
	# instead of ability-based. Source: `IsMoveEffectBlockedByTarget`
	# (battle_util.c L9811-9825) is the literal same if/else-if chain for both —
	# ability checked first, then item, both returning the identical block —
	# confirmed via direct read this project's Shield Dust gate (just above) is
	# the correct, single insertion point to mirror exactly, not a new
	# mechanism. Deliberately does NOT extend to try_contact_effects's Poison
	# Touch branch: real source ALSO gates Poison Touch through this same
	# check (battle_util.c L4286), but this project's EXISTING Shield Dust
	# implementation has no such gate there (a pre-existing gap from [M17c],
	# predating this tier) — Covert Cloak is scoped to match Shield Dust's
	# CURRENT actual behavior exactly, not to silently introduce a new
	# asymmetry between the two by fixing only this item's side. Flagged, not
	# fixed, per this project's own "flag but don't silently fix out-of-scope
	# gaps" discipline — an ability-side fix is out of scope for a 1-item tier.
	if is_true_secondary and ItemManager.holds_covert_cloak(defender, ng_active):
		return false

	# M17n-5: Sheer Force suppresses the move's OWN secondary effect entirely whenever
	# it qualifies for the power boost — confirmed from source to be the EXACT SAME
	# gate as the boost half (`IsSheerForceAffected`/`MoveIsAffectedBySheerForce`,
	# both keyed on "has a probabilistic secondary effect" — this project's
	# `is_true_secondary`), dispatched at the same general effect-resolution level as
	# Shield Dust's block just above (battle_script_commands.c L2315-2320) but keyed
	# on the ATTACKER's own ability, not the defender's.
	if is_true_secondary \
			and AbilityManager.effective_ability_id(attacker, ng_active) == AbilityManager.ABILITY_SHEER_FORCE:
		return false

	match move.secondary_effect:
		MoveData.SE_BURN:
			return try_apply_status(defender, BattlePokemon.STATUS_BURN, null, null, ng_active, attacker, weather, move)
		MoveData.SE_FREEZE:
			return try_apply_status(defender, BattlePokemon.STATUS_FREEZE, null, null, ng_active, attacker, weather, move)
		MoveData.SE_PARALYSIS:
			return try_apply_status(defender, BattlePokemon.STATUS_PARALYSIS, null, null, ng_active, attacker, weather, move)
		MoveData.SE_SLEEP:
			return try_apply_status(defender, BattlePokemon.STATUS_SLEEP, null, null, ng_active, attacker, weather, move)
		MoveData.SE_TOXIC:
			return try_apply_status(defender, BattlePokemon.STATUS_TOXIC, null, null, ng_active, attacker, weather, move)
		MoveData.SE_POISON:
			# [M18.5g] Regular (non-toxic) poison — Twineedle's own secondary effect.
			return try_apply_status(defender, BattlePokemon.STATUS_POISON, null, null, ng_active, attacker, weather, move)
		MoveData.SE_CONFUSION:
			return try_apply_confusion(defender, null, ng_active, attacker, move)
		MoveData.SE_FLINCH:
			# M17n-1: ABILITY_INNER_FOCUS blocks flinch specifically (not Shield Dust's
			# broad gate above) — battle_util.c L8830, same CancelerFlinch-adjacent
			# switch Steadfast's OWN reactive trigger already lives next to.
			if AbilityManager.effective_ability_id(defender, ng_active, attacker, move) \
					== AbilityManager.ABILITY_INNER_FOCUS:
				return false
			# Flinch: caller must check turn order and set defender.flinched.
			# We return true to signal the roll succeeded.
			return true
		MoveData.SE_WRAP:
			# [M18.5f] No Shield Dust/Covert Cloak/Sheer Force gate reaches here —
			# guaranteed (secondary_chance == 0), so is_true_secondary is false and
			# all three checks above already short-circuit past this branch, matching
			# source's own "not a true secondary" MOVE_EFFECT_WRAP finding.
			return try_apply_wrap(defender, attacker)
	return false


# ── Speed for priority resolution ─────────────────────────────────────────
#
# Returns the effective speed value used for turn-order sorting.
# Paralysis halves speed (Gen 7+). Stat stages applied.
#
# Source: battle_main.c L4712–4714
#   B_PARALYSIS_SPEED >= GEN_7 → speed /= 2   (was /= 4 before Gen 7)
#
# M17c: Slush Rush doubles Speed while Hail/Snow is active — same weather-conditional
# speed-multiplier shape as the Swift Swim/Chlorophyll/Sand Rush family added in
# M17n-2, the first of which this project implemented.
# Source: battle_util.c :: GetSpeedModifier-equivalent ability switch (Slush Rush ×2.0
#   gated on IsBattlerWeatherAffected(..., B_WEATHER_HAIL)).
#
# M17n-2 additions, same shape, same source function (`GetBattlerTotalSpeedStat`,
# battle_main.c L4657-4674): ABILITY_SWIFT_SWIM (rain ×2), ABILITY_CHLOROPHYLL (sun
# ×2), ABILITY_SAND_RUSH (sandstorm ×2). Source-verified nuance NOT shared with Slush
# Rush/Sand Rush: Swift Swim/Chlorophyll additionally check
# `holdEffect != HOLD_EFFECT_UTILITY_UMBRELLA` on the HOLDER (rain/sun specifically can
# be nullified by the holder's own Utility Umbrella; sandstorm/hail — Sand Rush/Slush
# Rush's conditions — are never touched by Umbrella at all, matching
# `ItemManager.blocks_weather_modifier`'s own existing damage-pipeline-only scope, so
# reusing it here for Swift Swim/Chlorophyll specifically is a deliberate, narrow,
# source-confirmed exception to this project's established "ability weather-checks
# don't consult Umbrella" simplification from `[M17n-1]`'s Leaf Guard entry — NOT a
# silent reversal of that call, since here source itself draws the distinction).
#
# weather: WEATHER_* constant, default WEATHER_NONE — callers pass the EFFECTIVE
#   weather (already WEATHER_NONE if Air Lock/Cloud Nine is active anywhere — see
#   `BattleManager._effective_weather()`), so no separate weather-negation check is
#   needed inside this function at all.
static func effective_speed(
		mon: BattlePokemon, weather: int = DamageCalculator.WEATHER_NONE,
		ng_active: bool = false) -> int:
	var spd: int = DamageCalculator._apply_stage(
			mon.speed, mon.stat_stages[BattlePokemon.STAGE_SPEED])
	var id: int = AbilityManager.effective_ability_id(mon, ng_active)
	# M17n-10: Quick Feet — source's paralysis-drop check is itself gated
	# `ability != ABILITY_QUICK_FEET` (battle_main.c L4712-4713), so a Quick Feet
	# holder's paralysis speed drop is skipped entirely, REPLACED by (not stacked
	# with) its own ×1.5 boost below, which fires unconditionally for any major
	# status1 condition, not just paralysis (battle_main.c L4676-4677).
	if mon.status == BattlePokemon.STATUS_PARALYSIS and id != AbilityManager.ABILITY_QUICK_FEET:
		spd /= 2
	if id == AbilityManager.ABILITY_QUICK_FEET and mon.status != BattlePokemon.STATUS_NONE:
		spd = spd * 150 / 100
	if id == AbilityManager.ABILITY_SLUSH_RUSH and weather == DamageCalculator.WEATHER_HAIL:
		spd *= 2
	if id == AbilityManager.ABILITY_SAND_RUSH and weather == DamageCalculator.WEATHER_SANDSTORM:
		spd *= 2
	if id == AbilityManager.ABILITY_SWIFT_SWIM and weather == DamageCalculator.WEATHER_RAIN \
			and not ItemManager.blocks_weather_modifier(mon, ng_active):
		spd *= 2
	if id == AbilityManager.ABILITY_CHLOROPHYLL and weather == DamageCalculator.WEATHER_SUN \
			and not ItemManager.blocks_weather_modifier(mon, ng_active):
		spd *= 2
	# M17n-5: Slow Start — unconditional Speed ×0.5 while the 5-turn timer is running
	# (no move-category gate, unlike its Atk half in AbilityManager.attack_modifier_uq412
	# — Speed isn't move-specific). Source: battle_main.c L4681-4682.
	if id == AbilityManager.ABILITY_SLOW_START and mon.slow_start_timer > 0:
		spd /= 2
	# M17n-7: Unburden — unconditional Speed ×2 while active (source: battle_main.c
	# L4686-4687, the same unconditional-on-weather shape as Slow Start's own check
	# directly above it in source). `unburden_active` is a persistent-until-switch-out
	# volatile set the moment the holder's OWN item is removed by any means (see
	# BattleManager._consume_item / AbilityManager._try_steal_item's doc comments).
	if id == AbilityManager.ABILITY_UNBURDEN and mon.unburden_active:
		spd *= 2
	# M12: Choice Scarf — (speed * 150) / 100 integer arithmetic.
	# Source: battle_main.c GetChoiceScarf case (L4703–4704).
	return ItemManager.apply_speed_modifier(mon, spd, ng_active)
