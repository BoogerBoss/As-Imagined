class_name TypeChart
extends RefCounted

# Type enum ids — source: include/constants/pokemon.h :: enum Type
const TYPE_NONE: int     = 0
const TYPE_NORMAL: int   = 1
const TYPE_FIGHTING: int = 2
const TYPE_FLYING: int   = 3
const TYPE_POISON: int   = 4
const TYPE_GROUND: int   = 5
const TYPE_ROCK: int     = 6
const TYPE_BUG: int      = 7
const TYPE_GHOST: int    = 8
const TYPE_STEEL: int    = 9
const TYPE_MYSTERY: int  = 10
const TYPE_FIRE: int     = 11
const TYPE_WATER: int    = 12
const TYPE_GRASS: int    = 13
const TYPE_ELECTRIC: int = 14
const TYPE_PSYCHIC: int  = 15
const TYPE_ICE: int      = 16
const TYPE_DRAGON: int   = 17
const TYPE_DARK: int     = 18
const TYPE_FAIRY: int    = 19
const TYPE_STELLAR: int  = 20

# gTypeEffectivenessTable transcription — source: src/data/types_info.h
# Config: B_UPDATED_TYPE_MATCHUPS = GEN_LATEST, meaning:
#   STL_RS (Ghost/Dark → Steel) = 1.0   (was 0.5 before Gen 6)
#   PSN_RS (Bug → Poison)       = 0.5   (was 2.0 in Gen 1)
#   BUG_RS (Poison → Bug)       = 1.0   (was 2.0 in Gen 1)
#   PSY_RS (Ghost → Psychic)    = 2.0   (was 0.0 in Gen 1)
#   FIR_RS (Ice → Fire)         = 0.5   (was 1.0 in Gen 1)
#
# Table indices: [attacker_type][defender_type], both using TYPE_* constants above.
# Rows = attacker type (0–20), Cols = defender type (0–20).
# Values: 0.0 (immune), 0.5 (NVE), 1.0 (neutral), 2.0 (SE).
#
# Column order: None Normal Fight Flying Poison Ground Rock Bug Ghost Steel Mystery Fire Water Grass Elec Psychic Ice Dragon Dark Fairy Stellar
static var TABLE: Array = [
	# TYPE_NONE (0)
	[1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0],
	# TYPE_NORMAL (1)
	[1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.5, 1.0, 0.0, 0.5, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0],
	# TYPE_FIGHTING (2)
	[1.0, 2.0, 1.0, 0.5, 0.5, 1.0, 2.0, 0.5, 0.0, 2.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.5, 2.0, 1.0, 2.0, 0.5, 1.0],
	# TYPE_FLYING (3)
	[1.0, 1.0, 2.0, 1.0, 1.0, 1.0, 0.5, 2.0, 1.0, 0.5, 1.0, 1.0, 1.0, 2.0, 0.5, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0],
	# TYPE_POISON (4) — Poison→Bug uses BUG_RS=1.0 (GEN_LATEST)
	[1.0, 1.0, 1.0, 1.0, 0.5, 0.5, 0.5, 1.0, 0.5, 0.0, 1.0, 1.0, 1.0, 2.0, 1.0, 1.0, 1.0, 1.0, 1.0, 2.0, 1.0],
	# TYPE_GROUND (5)
	[1.0, 1.0, 1.0, 0.0, 2.0, 1.0, 2.0, 0.5, 1.0, 2.0, 1.0, 2.0, 1.0, 0.5, 2.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0],
	# TYPE_ROCK (6)
	[1.0, 1.0, 0.5, 2.0, 1.0, 0.5, 1.0, 2.0, 1.0, 0.5, 1.0, 2.0, 1.0, 1.0, 1.0, 1.0, 2.0, 1.0, 1.0, 1.0, 1.0],
	# TYPE_BUG (7) — Bug→Poison uses PSN_RS=0.5 (GEN_LATEST)
	[1.0, 1.0, 0.5, 0.5, 0.5, 1.0, 1.0, 1.0, 0.5, 0.5, 1.0, 0.5, 1.0, 2.0, 1.0, 2.0, 1.0, 1.0, 2.0, 0.5, 1.0],
	# TYPE_GHOST (8) — Ghost→Steel uses STL_RS=1.0 (GEN_LATEST), Ghost→Psychic uses PSY_RS=2.0 (GEN_LATEST)
	[1.0, 0.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 2.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 2.0, 1.0, 1.0, 0.5, 1.0, 1.0],
	# TYPE_STEEL (9)
	[1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 2.0, 1.0, 1.0, 0.5, 1.0, 0.5, 0.5, 1.0, 0.5, 1.0, 2.0, 1.0, 1.0, 2.0, 1.0],
	# TYPE_MYSTERY (10)
	[1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0],
	# TYPE_FIRE (11)
	[1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.5, 2.0, 1.0, 2.0, 1.0, 0.5, 0.5, 2.0, 1.0, 1.0, 2.0, 0.5, 1.0, 1.0, 1.0],
	# TYPE_WATER (12)
	[1.0, 1.0, 1.0, 1.0, 1.0, 2.0, 2.0, 1.0, 1.0, 1.0, 1.0, 2.0, 0.5, 0.5, 1.0, 1.0, 1.0, 0.5, 1.0, 1.0, 1.0],
	# TYPE_GRASS (13)
	[1.0, 1.0, 1.0, 0.5, 0.5, 2.0, 2.0, 0.5, 1.0, 0.5, 1.0, 0.5, 2.0, 0.5, 1.0, 1.0, 1.0, 0.5, 1.0, 1.0, 1.0],
	# TYPE_ELECTRIC (14)
	[1.0, 1.0, 1.0, 2.0, 1.0, 0.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 2.0, 0.5, 0.5, 1.0, 1.0, 0.5, 1.0, 1.0, 1.0],
	# TYPE_PSYCHIC (15)
	[1.0, 1.0, 2.0, 1.0, 2.0, 1.0, 1.0, 1.0, 1.0, 0.5, 1.0, 1.0, 1.0, 1.0, 1.0, 0.5, 1.0, 1.0, 0.0, 1.0, 1.0],
	# TYPE_ICE (16) — Ice→Fire uses FIR_RS=0.5 (GEN_LATEST)
	[1.0, 1.0, 1.0, 2.0, 1.0, 2.0, 1.0, 1.0, 1.0, 0.5, 1.0, 0.5, 0.5, 2.0, 1.0, 1.0, 0.5, 2.0, 1.0, 1.0, 1.0],
	# TYPE_DRAGON (17)
	[1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.5, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 2.0, 1.0, 0.0, 1.0],
	# TYPE_DARK (18) — Dark→Steel uses STL_RS=1.0 (GEN_LATEST)
	[1.0, 1.0, 0.5, 1.0, 1.0, 1.0, 1.0, 1.0, 2.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 2.0, 1.0, 1.0, 0.5, 0.5, 1.0],
	# TYPE_FAIRY (19)
	[1.0, 1.0, 2.0, 1.0, 0.5, 1.0, 1.0, 1.0, 1.0, 0.5, 1.0, 0.5, 1.0, 1.0, 1.0, 1.0, 1.0, 2.0, 2.0, 1.0, 1.0],
	# TYPE_STELLAR (20)
	[1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0],
]


# UQ4.12 representations of the four possible type modifier values.
# Source: include/fpmath.h :: UQ_4_12(n) = (uq4_12_t)(n * 4096 + 0.5)
const UQ412_IMMUNE: int  = 0     # 0.0x — type immunity
const UQ412_NVE: int     = 2048  # 0.5x — not-very-effective
const UQ412_NEUTRAL: int = 4096  # 1.0x — neutral
const UQ412_SE: int      = 8192  # 2.0x — super-effective


# Returns the UQ4.12 integer modifier for one attacker-type vs one defender-type.
# Used for per-type application in DamageCalculator.
# Source: src/data/types_info.h :: gTypeEffectivenessTable; TABLE entry converted to UQ4.12.
#
# M17n-6: bypass_ghost_immunity — true only for a Scrappy/Mind's Eye-holding attacker.
# Source (battle_util.c :: MulByTypeEffectiveness, L8046-8052): checked PER
# defending-type component, restricted to Normal/Fighting-type moves vs a Ghost-type
# component specifically — mirrors weaken_flying_se's per-component pattern below,
# NOT the combined product (a dual-type defender's OTHER type's own modifier is
# untouched). Plain bool param (not an ability enum) for the same data-layer/
# DamageCalculator separation reason weaken_flying_se already established.
# [D2 batch 2] force_super_effective_type — Freeze-Dry(573)'s own move-level
# override: forces THAT SPECIFIC defending-type component to a flat 2.0
# (super-effective) UNCONDITIONALLY, regardless of the real table value —
# a genuinely different semantic from bypass_ghost_immunity/weaken_flying_se
# above/below (those only ever fix a 0.0 up to 1.0; this one forces UP to
# 2.0 even from a neutral or resisted starting value, since Water is
# normally just NEUTRAL to Ice, not immune). Still checked PER defending-
# type component, same shape as the other overrides. Pass TYPE_NONE (the
# default) to disable. Source: battle_util.c :: MulByTypeEffectiveness
# (L8061-8062).
static func get_uq412(atk_type: int, def_type: int, bypass_ghost_immunity: bool = false,
		force_super_effective_type: int = TYPE_NONE) -> int:
	var eff: float = TABLE[atk_type][def_type]
	if bypass_ghost_immunity and def_type == TYPE_GHOST and eff == 0.0 \
			and (atk_type == TYPE_NORMAL or atk_type == TYPE_FIGHTING):
		eff = 1.0
	if force_super_effective_type != TYPE_NONE and def_type == force_super_effective_type:
		eff = 2.0
	if eff == 0.0: return UQ412_IMMUNE
	if eff == 0.5: return UQ412_NVE
	if eff == 2.0: return UQ412_SE
	return UQ412_NEUTRAL


# Returns the combined effectiveness multiplier (as float) for reporting / immunity checks.
# Pass a single-element array for mono-type defenders.
# Source: src/battle_util.c :: CalcTypeEffectivenessMultiplierInternal + MulByTypeEffectiveness
#
# M17d: weaken_flying_se — true only under Delta Stream's Strong Winds weather. Source
#   (battle_util.c :: MulByTypeEffectiveness, L8069-8074) checks this PER defending type
#   component ("defType == TYPE_FLYING && mod >= 2.0 → mod = 1.0"), not on the combined
#   product — mirrored here by checking each component before multiplying it in. Plain
#   bool param (not a WEATHER_* constant) to avoid a cross-reference from this data-layer
#   script back to DamageCalculator; the one caller that needs this
#   (DamageCalculator.calculate) computes the bool itself. Every other caller (AI
#   heuristics, hazard/OHKO type checks) defaults to false — same simplification
#   precedent as weather-aware AI scoring being explicitly deferred since M11.
# M17n-6: bypass_ghost_immunity — see get_uq412's doc comment above; same per-component
# semantics (checked per defending type, not on the combined product), threaded through
# here too since this function is the OTHER independent type-effectiveness computation
# in this project (used for the early immunity short-circuit / Wonder Guard's own read),
# mirroring the same duplication already established for weaken_flying_se (M17d).
# [D2 batch 2] force_super_effective_type — see get_uq412's own doc comment; same
# per-component unconditional-force-to-2.0 semantics, mirrored here.
# [D2 batch 2] tar_shot_active — Tar Shot(695), a GENUINELY DIFFERENT shape from
# every override above: a flat POST-COMBINATION ×2.0 applied to the fully-combined
# `modifier` (not per-component), gated on `atk_type == TYPE_FIRE`. Source:
# battle_util.c L8145-8146, positioned after both per-type multiplications. See
# MoveData.is_tar_shot's own doc comment for the full citation and the confirmed-
# no-conflict finding against force_super_effective_type (mutually exclusive by
# construction — Freeze-Dry is always Ice-type, never Fire-type).
static func get_effectiveness(atk_type: int, def_types: Array,
		weaken_flying_se: bool = false, bypass_ghost_immunity: bool = false,
		grounded_override: bool = false, force_super_effective_type: int = TYPE_NONE,
		tar_shot_active: bool = false) -> float:
	if atk_type == TYPE_MYSTERY:
		return 1.0
	var modifier := 1.0
	var first_type: int = def_types[0] if def_types.size() > 0 else TYPE_NONE
	var first_mod: float = TABLE[atk_type][first_type]
	if weaken_flying_se and first_type == TYPE_FLYING and first_mod >= 2.0:
		first_mod = 1.0
	if bypass_ghost_immunity and first_type == TYPE_GHOST and first_mod == 0.0 \
			and (atk_type == TYPE_NORMAL or atk_type == TYPE_FIGHTING):
		first_mod = 1.0
	# M18t: Iron Ball grounds a Flying-type holder, removing the raw table's own
	# Ground-vs-Flying 0x entry — same shape as bypass_ghost_immunity above (a
	# held-item/ability condition overriding a specific 0x table entry), mirroring
	# source's own MulByTypeEffectiveness (battle_util.c L8064): `moveType ==
	# TYPE_GROUND && defType == TYPE_FLYING && IsBattlerGrounded(...) && mod ==
	# 0.0 -> mod = 1.0`. Caller passes ItemManager.holds_iron_ball's result as
	# this param; does NOT affect Levitate's OWN Ground-immunity, which is a
	# separate, ability-based pre-check (AbilityManager.blocks_move_type),
	# already gated on Iron Ball there too.
	if grounded_override and first_type == TYPE_FLYING and first_mod == 0.0 \
			and atk_type == TYPE_GROUND:
		first_mod = 1.0
	if force_super_effective_type != TYPE_NONE and first_type == force_super_effective_type:
		first_mod = 2.0
	modifier *= first_mod
	if modifier == 0.0:
		return 0.0
	if def_types.size() > 1 and def_types[1] != first_type and def_types[1] != TYPE_NONE:
		var second_mod: float = TABLE[atk_type][def_types[1]]
		if weaken_flying_se and def_types[1] == TYPE_FLYING and second_mod >= 2.0:
			second_mod = 1.0
		if bypass_ghost_immunity and def_types[1] == TYPE_GHOST and second_mod == 0.0 \
				and (atk_type == TYPE_NORMAL or atk_type == TYPE_FIGHTING):
			second_mod = 1.0
		if grounded_override and def_types[1] == TYPE_FLYING and second_mod == 0.0 \
				and atk_type == TYPE_GROUND:
			second_mod = 1.0
		if force_super_effective_type != TYPE_NONE and def_types[1] == force_super_effective_type:
			second_mod = 2.0
		modifier *= second_mod
	if tar_shot_active and atk_type == TYPE_FIRE:
		modifier *= 2.0
	return modifier


static func type_name(type_id: int) -> String:
	match type_id:
		TYPE_NONE:     return "None"
		TYPE_NORMAL:   return "Normal"
		TYPE_FIGHTING: return "Fighting"
		TYPE_FLYING:   return "Flying"
		TYPE_POISON:   return "Poison"
		TYPE_GROUND:   return "Ground"
		TYPE_ROCK:     return "Rock"
		TYPE_BUG:      return "Bug"
		TYPE_GHOST:    return "Ghost"
		TYPE_STEEL:    return "Steel"
		TYPE_MYSTERY:  return "???"
		TYPE_FIRE:     return "Fire"
		TYPE_WATER:    return "Water"
		TYPE_GRASS:    return "Grass"
		TYPE_ELECTRIC: return "Electric"
		TYPE_PSYCHIC:  return "Psychic"
		TYPE_ICE:      return "Ice"
		TYPE_DRAGON:   return "Dragon"
		TYPE_DARK:     return "Dark"
		TYPE_FAIRY:    return "Fairy"
		TYPE_STELLAR:  return "Stellar"
	return "Unknown"
