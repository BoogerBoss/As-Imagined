class_name BattleParty
extends RefCounted

# An ordered list of BattlePokemon representing one side's party.
# In singles one slot is active; in doubles, two slots are simultaneously active.
# active_indices tracks which party slots are on the field.
# Source: gPlayerParty / gEnemyParty (pokemon.h L703–713)
#         gBattlerPartyIndexes[MAX_BATTLERS_COUNT] (battle.h L978)
#         PARTY_SIZE = 6 (constants/global.h L82)

var members: Array[BattlePokemon] = []
var active_indices: Array[int] = [0]

# Backward-compat property: reads/writes the first (primary) active slot.
# All M1–M13 test suites read and write active_index directly — this property
# keeps them unmodified. In doubles, use active_indices[field_slot] directly.
var active_index: int:
	get: return active_indices[0]
	set(v): active_indices[0] = v


func get_active() -> BattlePokemon:
	return members[active_indices[0]]


# M14a: get the active Pokémon at a specific field slot (0 = primary, 1 = secondary in doubles).
func get_active_at(field_slot: int) -> BattlePokemon:
	return members[active_indices[field_slot]]


# M14a: number of active field slots for this party (1 in singles, 2 in doubles).
func num_active() -> int:
	return active_indices.size()


func is_fully_fainted() -> bool:
	for m: BattlePokemon in members:
		if not m.fainted:
			return false
	return true


# Returns true if there is a non-active, non-fainted member available to switch in.
# M14a: checks against all active_indices (not just the primary slot).
func has_valid_switch_target() -> bool:
	for i in range(members.size()):
		if not active_indices.has(i) and not members[i].fainted:
			return true
	return false


# Returns the party index of a random non-active, non-fainted member, or -1 if none.
# Source: used by Roar / Whirlwind forced-switch random selection.
# M14a: excludes all active slots, not just the primary one.
func get_random_non_fainted_not_active(forced_rng: int = -1) -> int:
	var candidates: Array[int] = []
	for i in range(members.size()):
		if not active_indices.has(i) and not members[i].fainted:
			candidates.append(i)
	if candidates.is_empty():
		return -1
	if forced_rng >= 0:
		return candidates[forced_rng % candidates.size()]
	return candidates[randi() % candidates.size()]


# Returns the first non-active, non-fainted party member index, or -1 if none.
# M14a: excludes all active slots, not just the primary one.
func get_first_non_fainted_not_active() -> int:
	for i in range(members.size()):
		if not active_indices.has(i) and not members[i].fainted:
			return i
	return -1


# Convenience: wrap a single BattlePokemon into a 1-member party.
# Used by start_battle() for backward compat with pre-M9 test suites.
static func single(mon: BattlePokemon) -> BattleParty:
	var p := BattleParty.new()
	p.members = [mon]
	p.active_indices = [0]
	return p
