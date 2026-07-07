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
const HOLD_EFFECT_PLATE:         int = 89  # Multitype's held-item type source (M17n-4)
const HOLD_EFFECT_TYPE_POWER:    int = 43  # M18a: Charcoal family / Incenses / Silk Scarf / Fairy Feather

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
const UQ412_RIPEN_RESIST_BERRY: int = 1024  # 0.25 × — Resist Berry halving, doubled by Ripen
const UQ412_TYPE_BOOST: int      = 4915   # 1.2 × — matching-type held item (M18a)


# ── Attack-stat item modifier (applied to stat, BEFORE base formula) ──────────
#
# Source: GetAttackStatModifier (battle_util.c L6989–6996).
#   BAND boosts physical attack; SPECS boosts special attack.
#   SCARF has no attack-stat modifier.
#
# Returns the UQ4.12 multiplier to apply to the relevant attack stat.
# Caller is responsible for checking move category (0=physical, 1=special).

# M17n-7: Klutz — the holder's own held item has no effect. Source:
# GetBattlerHoldEffectInternal (battle_util.c L5674-5692), the SINGLE chokepoint
# every held-item read in source funnels through: `if (ability == ABILITY_KLUTZ &&
# !gastroAcid) return HOLD_EFFECT_NONE`. No canonical exceptions apply here — the
# real games' Macho Brace/Power items/Iron Ball exemptions exist because those
# items are read via a DIFFERENT, raw parameter path in `GetBattlerTotalSpeedStat`
# rather than through this chokepoint, but this project implements NONE of those
# three items (confirmed via grep of HOLD_EFFECT_* constants below) — so the
# exception question is moot for every item this project actually models; Klutz
# suppresses all of them uniformly, matching this project's own scope. Gastro
# Acid (the ability-suppression status that would exempt a Klutz holder) is not
# implemented in this project either — moot, not silently dropped.
# Mirrors `AbilityManager.effective_ability_id`'s established shared-chokepoint
# pattern (`[M17g]`) rather than gating each of this file's ~13 functions
# ad-hoc — the same "build one accessor, retrofit every reader" precedent.
static func effective_held_item(mon: BattlePokemon, ng_active: bool = false) -> ItemData:
	if AbilityManager.effective_ability_id(mon, ng_active) == AbilityManager.ABILITY_KLUTZ:
		return null
	return mon.held_item


static func attack_modifier_uq412(mon: BattlePokemon, move: MoveData, ng_active: bool = false) -> int:
	var item: ItemData = effective_held_item(mon, ng_active)
	if item == null:
		return 4096
	var he: int = item.hold_effect
	if he == HOLD_EFFECT_CHOICE_BAND and move.category == 0:
		return UQ412_CHOICE_MULT
	if he == HOLD_EFFECT_CHOICE_SPECS and move.category == 1:
		return UQ412_CHOICE_MULT
	return 4096


# ── Post-roll attacker item modifier (Life Orb) ───────────────────────────────
#
# Source: GetAttackerItemsModifier (battle_util.c L7497–7499) called from
#   GetOtherModifiers → ApplyModifiersAfterDmgRoll (AFTER roll, STAB, type eff, burn).

static func post_roll_modifier_uq412(mon: BattlePokemon, ng_active: bool = false) -> int:
	var item: ItemData = effective_held_item(mon, ng_active)
	if item != null and item.hold_effect == HOLD_EFFECT_LIFE_ORB:
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
#
# M17c: Ripen doubles the resist berry's effectiveness — 0.25× instead of 0.5×.
# Source: battle_util.c :: GetDefenderItemsModifier (L7519): `(ctx->abilities[ctx->
#   battlerDef] == ABILITY_RIPEN) ? UQ_4_12(0.25) : UQ_4_12(0.5)`. Direct extension of
#   this existing function (it already takes the full BattlePokemon and can read its
#   ability), no new plumbing needed.

# M17n-7: Unnerve — opposing Pokémon can't eat berries at all while the Unnerve
# holder is on the field. Source: `IsUnnerveBlocked` (battle_util.c L333-343),
# gated on `GetItemPocket(itemId) == POCKET_BERRIES` (non-berry items — Leftovers,
# Life Orb, Choice items, Utility Umbrella, Heavy Duty Boots, Plate — are
# unaffected, confirmed from source; this project's `_consume_item` choke point
# already only ever handles berries in practice, matching Cheek Pouch's own
# established precedent) and `IsUnnerveAbilityOnOpposingSide` (checked field-wide —
# ANY live opposing battler with Unnerve blocks it, not per-hit/per-turn).
# `unnerve_active` is resolved by the caller (BattleManager, via a new
# `is_unnerve_active` helper mirroring `[M17f]`'s `_get_live_opponents` shape) since
# this stateless function has no access to the full combatant list.
static func defender_item_modifier_uq412(defender: BattlePokemon,
		move: MoveData, effectiveness: float, ng_active: bool = false,
		unnerve_active: bool = false) -> int:
	var item: ItemData = effective_held_item(defender, ng_active)
	if item == null:
		return 4096
	if item.hold_effect != HOLD_EFFECT_RESIST_BERRY:
		return 4096
	if unnerve_active:
		return 4096
	# Berry param = the type it resists (e.g. Occa Berry param = TYPE_FIRE).
	if item.hold_effect_param != move.type:
		return 4096
	if move.type != TypeChart.TYPE_NORMAL and effectiveness < 2.0:
		return 4096
	if defender.ability != null and defender.ability.ability_id == AbilityManager.ABILITY_RIPEN:
		return UQ412_RIPEN_RESIST_BERRY
	return UQ412_RESIST_BERRY


# Returns true when the resist berry should trigger (and be consumed) for this hit.
static func defender_berry_consumed(defender: BattlePokemon,
		move: MoveData, effectiveness: float, ng_active: bool = false,
		unnerve_active: bool = false) -> bool:
	return defender_item_modifier_uq412(
			defender, move, effectiveness, ng_active, unnerve_active) != 4096


# ── Speed modifier (Choice Scarf) ─────────────────────────────────────────────
#
# Source: battle_main.c GetChoiceScarf case — integer arithmetic: (speed * 150) / 100.
# NOT UQ4.12 — intentional; matches source.

static func apply_speed_modifier(mon: BattlePokemon, speed: int, ng_active: bool = false) -> int:
	var item: ItemData = effective_held_item(mon, ng_active)
	if item != null and item.hold_effect == HOLD_EFFECT_CHOICE_SCARF:
		return (speed * 150) / 100
	return speed


# ── Life Orb recoil ───────────────────────────────────────────────────────────
#
# Source: TryLifeOrb (battle_hold_effects.c L547–562): recoil = max_hp / 10.
# Fires at MoveEnd after damage (MoveEndLifeOrbShellBell, battle_move_resolution.c L3819).
# Returns the recoil amount; BattleManager applies it and emits item_damage.

static func life_orb_recoil(mon: BattlePokemon, ng_active: bool = false) -> int:
	# M17n-9: Magic Guard — Life Orb recoil is gated by it too (battle_hold_effects.c
	# TryLifeOrb, L547-559: `!IsAbilityAndRecord(...MAGIC_GUARD)`), the same as every
	# other indirect-damage source. Checked before the item lookup since a held item
	# and an ability are independent — no ordering dependency, just fail fast.
	if AbilityManager.blocks_indirect_damage(mon, ng_active):
		return 0
	var item: ItemData = effective_held_item(mon, ng_active)
	if item != null and item.hold_effect == HOLD_EFFECT_LIFE_ORB:
		return max(1, mon.max_hp / 10)
	return 0


# ── Leftovers EOT heal ────────────────────────────────────────────────────────
#
# Source: TryLeftovers (battle_hold_effects.c L634–648): heal = max_hp / 16.
# Fires at EOT via FIRST_EVENT_BLOCK_HEAL_ITEMS (after status damage).
# Returns 0 if already at full HP (source: ItemHealHp early-exits when hp == max_hp).

static func leftovers_heal(mon: BattlePokemon, ng_active: bool = false) -> int:
	var item: ItemData = effective_held_item(mon, ng_active)
	if item == null or item.hold_effect != HOLD_EFFECT_LEFTOVERS:
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

# M17n-7: `ng_active`/`unnerve_active` — Klutz (this mon's own) and Unnerve (any
# live opponent's) gates, same shape as the resist-berry function above.
# `override_item` — M17n-7: Cud Chew's re-trigger reuses this SAME heal check one
# turn later, but against `BattlePokemon.last_consumed_berry` rather than the
# CURRENT `held_item` (which is null by the time Cud Chew fires, per source — the
# physical item is never restored, only the effect script re-runs). Source's own
# `BattleScript_CudChewActivates` sets `gBattleScripting.overrideBerryRequirements`
# around its `consumeberry` call, and BOTH `HasEnoughHpToEatBerry` (battle_util.c
# L5465, returns TRUE unconditionally when the flag is set) and `IsUnnerveBlocked`
# (battle_util.c L338, returns FALSE unconditionally) key off that exact flag — so
# `override_item != null` bypasses BOTH the HP threshold AND `unnerve_active` here,
# not just `effective_held_item`. The one exception `ItemHealHp` itself still
# enforces even under override (battle_hold_effects.c L831: `!(override &&
# hp == maxHP)`) is a plain already-at-full-HP no-op, reproduced below directly.
# Klutz is moot in the override branch regardless (Klutz and Cud Chew can never
# coexist on the same holder, since a Pokémon has exactly one ability).
static func sitrus_berry_heal(mon: BattlePokemon, ng_active: bool = false,
		unnerve_active: bool = false, override_item: ItemData = null) -> int:
	var item: ItemData = override_item if override_item != null else effective_held_item(mon, ng_active)
	if item == null or item.hold_effect != HOLD_EFFECT_RESTORE_PCT_HP:
		return 0
	if override_item != null:
		if mon.current_hp >= mon.max_hp:
			return 0
	else:
		if unnerve_active:
			return 0
		# M17n-7: Gluttony lowers the eat-early threshold's fraction from a stricter
		# value to 2 (50%) for berries whose normal fraction is <=4 (25%-or-stricter).
		# Sitrus Berry's fraction is hardcoded to 2 in source regardless of ability
		# (ItemHealHp always calls HasEnoughHpToEatBerry(..., 2, ...)) — already at the
		# exact value Gluttony would move a stricter berry to, so this call is a
		# confirmed no-op for Sitrus specifically (2 in, 2 out) — see
		# AbilityManager.gluttony_adjusted_hp_fraction's own doc comment for why no
		# currently-implemented berry is actually affected, and why this is wired in
		# generically anyway rather than left unimplemented.
		var fraction: int = AbilityManager.gluttony_adjusted_hp_fraction(mon, 2, ng_active)
		if mon.current_hp > mon.max_hp / fraction:
			return 0
	var pct: int = item.hold_effect_param  # 25 for Sitrus Berry
	return max(1, mon.max_hp * pct / 100)


# ── Lum Berry ─────────────────────────────────────────────────────────────────
#
# Source: gHoldEffectsInfo (hold_effects.h) — CURE_STATUS has onStatusChange=TRUE.
#   Fires in ItemBattleEffects when any non-volatile status is inflicted (ITEMEFFECT_CURE_STATUS).
#   Source function: TryCureAnyStatus (battle_hold_effects.c L764+).
# Returns true when the berry should cure and be consumed.
# M17n-7: `ng_active`/`unnerve_active`/`override_item` — same shape as
# sitrus_berry_heal above (Cud Chew's re-trigger reuses this for a Lum Berry too).
# `TryCureAnyStatus` has no HP-threshold gate to begin with, so `override_item`'s
# only effect here is bypassing `unnerve_active` (matching `IsUnnerveBlocked`'s
# `overrideBerryRequirements` check, battle_util.c L338) — see sitrus_berry_heal's
# doc comment for the full source citation shared by both functions.
static func lum_berry_cures(mon: BattlePokemon, ng_active: bool = false,
		unnerve_active: bool = false, override_item: ItemData = null) -> bool:
	var item: ItemData = override_item if override_item != null else effective_held_item(mon, ng_active)
	if item == null or item.hold_effect != HOLD_EFFECT_CURE_STATUS:
		return false
	if override_item == null and unnerve_active:
		return false
	return mon.status != BattlePokemon.STATUS_NONE


# ── Weather duration ──────────────────────────────────────────────────────────
#
# Source: TryChangeBattleWeather (battle_util.c L1993–1996):
#   if (GetBattlerHoldEffect(setter) == sBattleWeatherInfo[weather].rock) duration=8 else 5.
# Rock↔weather mapping from sBattleWeatherInfo in battle_util.c:
#   RAIN → DAMP_ROCK, SUN → HEAT_ROCK, HAIL → ICY_ROCK, SANDSTORM → SMOOTH_ROCK.

static func weather_duration(setter: BattlePokemon,
		weather_type: int, ng_active: bool = false) -> int:
	if setter == null:
		return WEATHER_DURATION_DEFAULT
	var item: ItemData = effective_held_item(setter, ng_active)
	if item == null:
		return WEATHER_DURATION_DEFAULT
	var he: int = item.hold_effect
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

static func blocks_weather_modifier(mon: BattlePokemon, ng_active: bool = false) -> bool:
	var item: ItemData = effective_held_item(mon, ng_active)
	return item != null and item.hold_effect == HOLD_EFFECT_UTILITY_UMBRELLA


# ── Choice item detection ─────────────────────────────────────────────────────
#
# Source: IsHoldEffectChoice (item.c L970–974): BAND || SCARF || SPECS.
# M17n-7: Klutz-gated via effective_held_item — source's own choice-lock gate
# (`CheckMoveLimitations`, `IsHoldEffectChoice(holdEffect)`) reads
# `GetBattlerHoldEffect` too, so a Klutz holder wielding a Choice item is NOT
# choice-locked either, matching the item's stat boost also being suppressed.

static func is_choice_item(mon: BattlePokemon, ng_active: bool = false) -> bool:
	var item: ItemData = effective_held_item(mon, ng_active)
	if item == null:
		return false
	return item.hold_effect in [
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

static func is_hazard_immune(mon: BattlePokemon, ng_active: bool = false) -> bool:
	var item: ItemData = effective_held_item(mon, ng_active)
	return item != null and item.hold_effect == HOLD_EFFECT_HEAVY_DUTY_BOOTS


# ── M18a: Type-boost held items (base-power modifier) ─────────────────────────
#
# Source: CalcMoveBasePowerAfterModifiers (battle_util.c L6659–6661) — both
#   HOLD_EFFECT_TYPE_POWER (Charcoal family / Incenses / Silk Scarf / Fairy Feather)
#   and HOLD_EFFECT_PLATE share ONE case branch:
#     `if (moveType == GetItemSecondaryId(item)) modifier = uq4_12_multiply(modifier, holdEffectModifier)`
#   where `holdEffectModifier = 1.0 + holdEffectParamAtk/100` and
#   `holdEffectParamAtk = GetBattlerHoldEffectParam(...)`, clamped ≤100.
# Every one of this project's 40 M18a items resolves that param to 20 — confirmed by
#   reading all 40 struct entries in src/data/items.h directly: the Charcoal family/
#   Silk Scarf/Fairy Feather use `.holdEffectParam = TYPE_BOOST_PARAM` and Sea/Wave
#   Incense use an explicit `I_TYPE_BOOST_POWER >= GEN_4 ? 20 : 5` ternary, both of
#   which resolve to 20 under this reference clone's `I_TYPE_BOOST_POWER = GEN_LATEST`
#   config (include/config/item.h:15); every Plate and the remaining 3 Incenses use a
#   literal `.holdEffectParam = 20`. No item in this family varies — the boost is a
#   flat ×1.2 (`UQ412_TYPE_BOOST` = `UQ_4_12(1.2)` = 4915), not itemized per-item.
# This is a BASE-POWER modifier (`CalcMoveBasePowerAfterModifiers`), architecturally
#   the item-side sibling of `AbilityManager.move_power_modifier_uq412` (M17a's
#   Technician/Iron Fist/etc. live in this exact same source function) — NOT of this
#   file's `attack_modifier_uq412` above, which is `GetAttackStatModifier` (Choice
#   Band/Specs, a different function entirely, applied to the attack STAT before the
#   base formula rather than to the move's power). Caller wires this into
#   `DamageCalculator.calculate` alongside `ability_power_mod`, not `atk_item_mod`.
# The real struct field carrying the type is source's `.secondaryId`, which this
#   project's `ItemData` schema has no equivalent for. Reuses `hold_effect_param` to
#   store the type instead — the SAME pragmatic deviation `[M17n-4]` already
#   established for `HOLD_EFFECT_PLATE`'s Multitype read below, now extended
#   uniformly to `HOLD_EFFECT_TYPE_POWER` too, since both share this one case branch
#   in source and neither uses `hold_effect_param` for its literal source purpose
#   here (the 20% is a fixed constant, never itemized per-item in this project).
# Returns 4096 (neutral) if not holding a matching-type item — including when the
#   held item's type doesn't match the move being used, or Klutz suppresses it.
static func move_power_modifier_uq412(mon: BattlePokemon, move: MoveData, ng_active: bool = false) -> int:
	var item: ItemData = effective_held_item(mon, ng_active)
	if item == null:
		return 4096
	if item.hold_effect != HOLD_EFFECT_TYPE_POWER and item.hold_effect != HOLD_EFFECT_PLATE:
		return 4096
	if move.type != item.hold_effect_param:
		return 4096
	return UQ412_TYPE_BOOST


# M17n-4: Multitype's held Plate item → type. Source: src/data/items.h's Plate entries
# store the associated type in `.secondaryId` (e.g. Flame Plate: `.secondaryId =
# TYPE_FIRE`), with `.holdEffectParam = 20` reserved for Judgment/Natural Gift's power
# boost — a DIFFERENT field from the type. This project's `ItemData` schema has no
# `secondary_id` field, and has neither Judgment nor Natural Gift implemented (confirmed
# via grep — neither move exists here), so `holdEffectParam`'s source purpose is moot in
# this codebase; reusing `hold_effect_param` for the type value instead is the same
# pragmatic deviation this project's existing Resist Berry modifier already established
# (see `defender_item_modifier_uq412` above, which reads `hold_effect_param` as a type
# id for Occa/Chilan-style berries) rather than adding an unused field to match source's
# literal layout.
# Returns TypeChart.TYPE_NONE if not holding a Plate.
# M17n-7: Klutz-gated via effective_held_item for source-fidelity/uniformity, though
# structurally unreachable in practice (Multitype and Klutz can never coexist on the
# same holder — a Pokémon has exactly one ability) — same "recorded, not reachable"
# precedent as Sticky Hold ([M17j]) and Mind's Eye's breakable flag ([M17n-6]).
static func multitype_plate_type(mon: BattlePokemon, ng_active: bool = false) -> int:
	var item: ItemData = effective_held_item(mon, ng_active)
	if item == null or item.hold_effect != HOLD_EFFECT_PLATE:
		return TypeChart.TYPE_NONE
	return item.hold_effect_param
