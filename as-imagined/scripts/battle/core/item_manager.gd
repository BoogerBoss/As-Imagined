class_name ItemManager
extends RefCounted

# Held-item mechanic implementations — M12.
# All constants sourced from include/constants/hold_effects.h (the HOLD_EFFECT enum).
# All UQ4.12 values sourced from include/fpmath.h.

# ── Hold-effect constants ─────────────────────────────────────────────────────
# Source: include/constants/hold_effects.h
const HOLD_EFFECT_NONE:          int = 0
const HOLD_EFFECT_CURE_STATUS:   int = 9    # Lum Berry — onStatusChange flag set
const HOLD_EFFECT_CHOICE_BAND:   int = 29
const HOLD_EFFECT_LEFTOVERS:     int = 41
const HOLD_EFFECT_CHOICE_SCARF:  int = 49
const HOLD_EFFECT_CHOICE_SPECS:  int = 50
const HOLD_EFFECT_DAMP_ROCK:     int = 51   # Rain → 8 turns
const HOLD_EFFECT_HEAT_ROCK:     int = 53   # Sun → 8 turns
const HOLD_EFFECT_ICY_ROCK:      int = 54   # Hail → 8 turns
const HOLD_EFFECT_SMOOTH_ROCK:   int = 56   # Sandstorm → 8 turns
const HOLD_EFFECT_LIFE_ORB:      int = 60
const HOLD_EFFECT_RESIST_BERRY:  int = 80   # type-resist berry (Occa=Fire, Wacan=Electric, …)
const HOLD_EFFECT_RESTORE_PCT_HP: int = 82  # Sitrus Berry — param=25 (25 %)
const HOLD_EFFECT_UTILITY_UMBRELLA: int = 115
const HOLD_EFFECT_HEAVY_DUTY_BOOTS: int = 119  # full immunity to entry hazards on switch-in

# Weather duration with the matching rock item vs. without.
# Source: TryChangeBattleWeather (battle_util.c L1993–1996): 8 if rock holder, else 5.
const WEATHER_DURATION_ROCK: int    = 8
const WEATHER_DURATION_DEFAULT: int = 5

# UQ4.12 multipliers.
# Source: include/fpmath.h :: UQ_4_12(n) = round(n * 4096).
# Life Orb uses UQ_4_12_FLOORED(1.3) = floor(1.3 * 4096) = 5324 (see GetAttackerItemsModifier).
const UQ412_CHOICE_MULT: int     = 6144   # 1.5 × — Band, Specs
const UQ412_LIFE_ORB: int        = 5324   # 1.3 × (floored) — Life Orb damage boost
const UQ412_RESIST_BERRY: int    = 2048   # 0.5 × — Resist Berry halving


# ── Attack-stat item modifier (applied to stat, BEFORE base formula) ──────────
#
# Source: GetAttackStatModifier (battle_util.c L6989–6996).
#   BAND boosts physical attack; SPECS boosts special attack.
#   SCARF has no attack-stat modifier.
#
# Returns the UQ4.12 multiplier to apply to the relevant attack stat.
# Caller is responsible for checking move category (0=physical, 1=special).

static func attack_modifier_uq412(mon: BattlePokemon, move: MoveData) -> int:
	if mon.held_item == null:
		return 4096
	var he: int = mon.held_item.hold_effect
	if he == HOLD_EFFECT_CHOICE_BAND and move.category == 0:
		return UQ412_CHOICE_MULT
	if he == HOLD_EFFECT_CHOICE_SPECS and move.category == 1:
		return UQ412_CHOICE_MULT
	return 4096


# ── Post-roll attacker item modifier (Life Orb) ───────────────────────────────
#
# Source: GetAttackerItemsModifier (battle_util.c L7497–7499) called from
#   GetOtherModifiers → ApplyModifiersAfterDmgRoll (AFTER roll, STAB, type eff, burn).

static func post_roll_modifier_uq412(mon: BattlePokemon) -> int:
	if mon.held_item != null and mon.held_item.hold_effect == HOLD_EFFECT_LIFE_ORB:
		return UQ412_LIFE_ORB
	return 4096


# ── Post-roll defender item modifier (Resist Berry) ───────────────────────────
#
# Source: GetDefenderItemsModifier (battle_util.c L7510–7524) called from
#   GetOtherModifiers → AFTER Life Orb, AFTER type effectiveness.
# Triggers when the move's type matches the berry's param type AND
#   (the move is TYPE_NORMAL OR effectiveness is ≥ 2.0×):
#   `ctx->moveType == GetBattlerHoldEffectParam(...) && (ctx->moveType == TYPE_NORMAL ||
#    ctx->typeEffectivenessModifier >= UQ_4_12(2.0))` (L7513). The TYPE_NORMAL bypass exists
#   because Normal-type moves can never be super-effective (no type resists Normal at 2×+),
#   so Chilan Berry (Normal-resist, param=TYPE_NORMAL) would be permanently unreachable
#   without it — Follow-up fixes session, 2026-07-02; previously an unwired gap (M12
#   decisions.md gap I2), Chilan Berry was the only resist berry this bypass applies to.
# The berry is consumed on trigger — BattleManager must call _consume_item().

static func defender_item_modifier_uq412(defender: BattlePokemon,
		move: MoveData, effectiveness: float) -> int:
	if defender.held_item == null:
		return 4096
	if defender.held_item.hold_effect != HOLD_EFFECT_RESIST_BERRY:
		return 4096
	# Berry param = the type it resists (e.g. Occa Berry param = TYPE_FIRE).
	if defender.held_item.hold_effect_param != move.type:
		return 4096
	if move.type != TypeChart.TYPE_NORMAL and effectiveness < 2.0:
		return 4096
	return UQ412_RESIST_BERRY


# Returns true when the resist berry should trigger (and be consumed) for this hit.
static func defender_berry_consumed(defender: BattlePokemon,
		move: MoveData, effectiveness: float) -> bool:
	return defender_item_modifier_uq412(defender, move, effectiveness) != 4096


# ── Speed modifier (Choice Scarf) ─────────────────────────────────────────────
#
# Source: battle_main.c GetChoiceScarf case — integer arithmetic: (speed * 150) / 100.
# NOT UQ4.12 — intentional; matches source.

static func apply_speed_modifier(mon: BattlePokemon, speed: int) -> int:
	if mon.held_item != null and mon.held_item.hold_effect == HOLD_EFFECT_CHOICE_SCARF:
		return (speed * 150) / 100
	return speed


# ── Life Orb recoil ───────────────────────────────────────────────────────────
#
# Source: TryLifeOrb (battle_hold_effects.c L547–562): recoil = max_hp / 10.
# Fires at MoveEnd after damage (MoveEndLifeOrbShellBell, battle_move_resolution.c L3819).
# Returns the recoil amount; BattleManager applies it and emits item_damage.

static func life_orb_recoil(mon: BattlePokemon) -> int:
	if mon.held_item != null and mon.held_item.hold_effect == HOLD_EFFECT_LIFE_ORB:
		return max(1, mon.max_hp / 10)
	return 0


# ── Leftovers EOT heal ────────────────────────────────────────────────────────
#
# Source: TryLeftovers (battle_hold_effects.c L634–648): heal = max_hp / 16.
# Fires at EOT via FIRST_EVENT_BLOCK_HEAL_ITEMS (after status damage).
# Returns 0 if already at full HP (source: ItemHealHp early-exits when hp == max_hp).

static func leftovers_heal(mon: BattlePokemon) -> int:
	if mon.held_item == null or mon.held_item.hold_effect != HOLD_EFFECT_LEFTOVERS:
		return 0
	if mon.current_hp >= mon.max_hp:
		return 0
	return max(1, mon.max_hp / 16)


# ── Sitrus Berry ──────────────────────────────────────────────────────────────
#
# Source: HasEnoughHpToEatBerry (battle_util.c L5461–5476): threshold = max_hp / hpFraction.
#   Sitrus Berry has hpFraction=2 (hardcoded via battlerAbilityParam for onHpThreshold items).
#   Heal amount = max_hp * param / 100 where param=25 (from items.h Sitrus Berry definition).
# Fires at MoveEnd after damage (MoveEndHpThresholdItemsTarget, battle_move_resolution.c).
# Returns heal amount if triggered, 0 otherwise. Berry is consumed on trigger.

static func sitrus_berry_heal(mon: BattlePokemon) -> int:
	if mon.held_item == null or mon.held_item.hold_effect != HOLD_EFFECT_RESTORE_PCT_HP:
		return 0
	if mon.current_hp > mon.max_hp / 2:
		return 0
	var pct: int = mon.held_item.hold_effect_param  # 25 for Sitrus Berry
	return max(1, mon.max_hp * pct / 100)


# ── Lum Berry ─────────────────────────────────────────────────────────────────
#
# Source: gHoldEffectsInfo (hold_effects.h) — CURE_STATUS has onStatusChange=TRUE.
#   Fires in ItemBattleEffects when any non-volatile status is inflicted (ITEMEFFECT_CURE_STATUS).
#   Source function: TryCureAnyStatus (battle_hold_effects.c L764+).
# Returns true when the berry should cure and be consumed.

static func lum_berry_cures(mon: BattlePokemon) -> bool:
	if mon.held_item == null or mon.held_item.hold_effect != HOLD_EFFECT_CURE_STATUS:
		return false
	return mon.status != BattlePokemon.STATUS_NONE


# ── Weather duration ──────────────────────────────────────────────────────────
#
# Source: TryChangeBattleWeather (battle_util.c L1993–1996):
#   if (GetBattlerHoldEffect(setter) == sBattleWeatherInfo[weather].rock) duration=8 else 5.
# Rock↔weather mapping from sBattleWeatherInfo in battle_util.c:
#   RAIN → DAMP_ROCK, SUN → HEAT_ROCK, HAIL → ICY_ROCK, SANDSTORM → SMOOTH_ROCK.

static func weather_duration(setter: BattlePokemon,
		weather_type: int) -> int:
	if setter == null or setter.held_item == null:
		return WEATHER_DURATION_DEFAULT
	var he: int = setter.held_item.hold_effect
	match weather_type:
		DamageCalculator.WEATHER_RAIN:
			if he == HOLD_EFFECT_DAMP_ROCK:
				return WEATHER_DURATION_ROCK
		DamageCalculator.WEATHER_SUN:
			if he == HOLD_EFFECT_HEAT_ROCK:
				return WEATHER_DURATION_ROCK
		DamageCalculator.WEATHER_HAIL:
			if he == HOLD_EFFECT_ICY_ROCK:
				return WEATHER_DURATION_ROCK
		DamageCalculator.WEATHER_SANDSTORM:
			if he == HOLD_EFFECT_SMOOTH_ROCK:
				return WEATHER_DURATION_ROCK
	return WEATHER_DURATION_DEFAULT


# ── Utility Umbrella ──────────────────────────────────────────────────────────
#
# Source: GetWeatherDamageModifier (battle_util.c L7258): if defender holds Umbrella,
#   return UQ_4_12(1.0) immediately (no weather boost/reduction).
#   GetAttackerWeather (L9281–9290): if attacker holds Umbrella, strip rain/sun from
#   the effective weather, returning WEATHER_NONE for modifier purposes.
# Both cases collapse to the same behaviour in our engine: if either battler holds
# Utility Umbrella, weather has no effect on this hit.

static func blocks_weather_modifier(mon: BattlePokemon) -> bool:
	return mon.held_item != null \
		and mon.held_item.hold_effect == HOLD_EFFECT_UTILITY_UMBRELLA


# ── Choice item detection ─────────────────────────────────────────────────────
#
# Source: IsHoldEffectChoice (item.c L970–974): BAND || SCARF || SPECS.

static func is_choice_item(mon: BattlePokemon) -> bool:
	if mon.held_item == null:
		return false
	return mon.held_item.hold_effect in [
		HOLD_EFFECT_CHOICE_BAND,
		HOLD_EFFECT_CHOICE_SCARF,
		HOLD_EFFECT_CHOICE_SPECS,
	]


# ── Heavy Duty Boots — entry hazard immunity ───────────────────────────────────
#
# Source: IsBattlerAffectedByHazards (battle_util.c L9209-9228): returns FALSE (blocked)
#   whenever `holdEffect == HOLD_EFFECT_HEAVY_DUTY_BOOTS`, for ALL of Spikes, Toxic Spikes,
#   and Stealth Rock (checked at every TryHazardsOnSwitchIn call site — battle_switch_in.c
#   L306-378) — full immunity, not a damage reduction. Follow-up fixes session, 2026-07-02
#   (flagged as a known gap in M16d's decisions.md Stealth Rock section).
# Caller (BattleManager._apply_switch_in_hazards) applies this as one uniform gate across
#   all three hazard branches rather than three separate checks, matching how source's
#   IsBattlerAffectedByHazards is the single shared choke point for all of them.
# Note: for Toxic Spikes specifically, a grounded Poison-type ABSORBS/clears the hazard
#   regardless of Heavy Duty Boots (source checks IS_BATTLER_OF_TYPE(POISON) in an earlier
#   else-if branch than the Heavy-Duty-Boots gate — battle_switch_in.c L338-344) — this
#   helper only decides whether the "would be poisoned" branch is blocked, not the absorb
#   branch; the caller must NOT gate the Poison-type-absorb check behind this helper.

static func is_hazard_immune(mon: BattlePokemon) -> bool:
	return mon.held_item != null \
		and mon.held_item.hold_effect == HOLD_EFFECT_HEAVY_DUTY_BOOTS
