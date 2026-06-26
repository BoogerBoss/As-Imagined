class_name BattleParty
extends RefCounted

# An ordered list of BattlePokemon representing one side's party.
# One slot is "active" — currently on the field. active_index tracks which one.
# Source: gPlayerParty / gEnemyParty (pokemon.h L703–713)
#         gBattlerPartyIndexes[MAX_BATTLERS_COUNT] (battle.h L978)
#         PARTY_SIZE = 6 (constants/global.h L82)

var members: Array[BattlePokemon] = []
var active_index: int = 0


func get_active() -> BattlePokemon:
	return members[active_index]


func is_fully_fainted() -> bool:
	for m: BattlePokemon in members:
		if not m.fainted:
			return false
	return true


func has_valid_switch_target() -> bool:
	for i in range(members.size()):
		if i != active_index and not members[i].fainted:
			return true
	return false


# Returns the party index of a random non-active, non-fainted member, or -1 if none.
# Source: used by Roar / Whirlwind forced-switch random selection.
func get_random_non_fainted_not_active(forced_rng: int = -1) -> int:
	var candidates: Array[int] = []
	for i in range(members.size()):
		if i != active_index and not members[i].fainted:
			candidates.append(i)
	if candidates.is_empty():
		return -1
	if forced_rng >= 0:
		return candidates[forced_rng % candidates.size()]
	return candidates[randi() % candidates.size()]


# Returns the first non-active, non-fainted party member index, or -1 if none.
func get_first_non_fainted_not_active() -> int:
	for i in range(members.size()):
		if i != active_index and not members[i].fainted:
			return i
	return -1


# Convenience: wrap a single BattlePokemon into a 1-member party.
# Used by start_battle() for backward compat with pre-M9 test suites.
static func single(mon: BattlePokemon) -> BattleParty:
	var p := BattleParty.new()
	p.members = [mon]
	p.active_index = 0
	return p
