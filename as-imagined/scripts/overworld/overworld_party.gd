class_name OverworldParty
extends RefCounted

## [M27D D5] Building the two parties a field battle needs.
##
## The overworld has never had a party of its own — confirmed by grep at D5's
## Step 0, zero `BattleParty`/`BattlePokemon` references anywhere under
## `scenes/overworld/` or `scripts/overworld/`. This is that gap, at pre-alpha
## scope: a DEBUG player party (Rob's own call — a real one waits on M27K's
## starter choice), and a real opponent party built from `TrainerData`.


## The pre-alpha player party.
##
## Deliberately a fixed, legal, hand-picked team rather than anything random:
## the point of D5 is to prove the overworld -> battle -> overworld seam, and a
## party that varies run to run makes every failure ambiguous. Replaced wholesale
## when M27K lands a real starter choice and M27L can persist one.
const DEBUG_PARTY := [
	{"dex": 1, "level": 12},    # Bulbasaur
	{"dex": 4, "level": 12},    # Charmander
	{"dex": 7, "level": 12},    # Squirtle
]


static func build_debug_player_party() -> BattleParty:
	var party := BattleParty.new()
	for spec in DEBUG_PARTY:
		var mon := PokemonFactory.create_battle_pokemon(int(spec["dex"]), int(spec["level"]))
		if mon != null:
			party.members.append(mon)
	party.active_indices = [0]
	return party


## A real opponent party from a real trainer.
##
## Uses `BattlePokemon.from_trainer_mon`, which already resolves species, moves,
## held item, ability, nature, IVs and friendship from the converted roster —
## so this is assembly, not construction, and it stays correct as that converter
## improves. Returns null for an unresolvable key rather than an empty party: a
## trainer with no Pokémon would start a battle that instantly ends, which reads
## as a mechanics bug rather than the missing-data bug it is.
static func build_trainer_party(trainer_key: String) -> BattleParty:
	var data := TrainerRegistry.get_trainer_by_key(trainer_key)
	if data == null or data.party.is_empty():
		return null
	var party := BattleParty.new()
	for tpm in data.party:
		var mon := BattlePokemon.from_trainer_mon(tpm)
		if mon != null:
			party.members.append(mon)
	if party.members.is_empty():
		return null
	# Doubles is real in this project's battle engine and real in the roster
	# (`TrainerData.is_doubles`), but the overworld has no two-active concept
	# yet, so a doubles trainer is fought as singles for now. Disclosed rather
	# than silently flattened — active_indices is what would change.
	party.active_indices = [0]
	return party
