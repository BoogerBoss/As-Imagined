class_name RandomTeamGenerator
extends RefCounted

# [M23.6] A simple, genuinely-random-but-genuinely-legal team generator for
# battle_setup_screen.gd's "Random Team" option (used both as a player-side
# fallback when no saved teams exist, and as a selectable opponent option).
# Deliberately NOT competitive-quality — the task's own scope is "genuinely
# random and genuinely legal," not battle-optimal team-building logic. Every
# generated member is built through the exact same, already-tested
# PokemonFactory.create_battle_pokemon() path every other real BattlePokemon
# in this project goes through — this file only picks the RANDOM INPUTS to
# that call (dex/level/moves/nature/evs/ivs/ability_slot), never touches
# stat/legality computation itself.
#
# Legality sources reused directly, zero new legality logic invented:
#   - Moves: MovepoolResolver.legal_move_ids(dex, level) — the exact same
#     real-legality pool team_builder_screen.gd's own move dropdown uses.
#   - EV/IV caps: BattleManager.EV_CAP_TOTAL/EV_CAP_PER_STAT (510/252),
#     read directly rather than re-declared, matching team_builder_screen
#     .gd's own established precedent for not letting a cap drift.
#   - Ability slot: only a species' real, nonzero ability slots are ever
#     picked from — same "id 0 means no ability" rule PokemonFactory/
#     team_builder_screen.gd already establish.

const DEFAULT_TEAM_SIZE := 6
const DEFAULT_MIN_LEVEL := 10
const DEFAULT_MAX_LEVEL := 70


static func generate_team(size: int = DEFAULT_TEAM_SIZE, min_level: int = DEFAULT_MIN_LEVEL,
		max_level: int = DEFAULT_MAX_LEVEL) -> BattleParty:
	var clamped_size: int = clampi(size, 1, TeamStorage.MAX_TEAM_SIZE)
	var species_pool: Array = PokemonRegistry.get_all_species()

	var members: Array[BattlePokemon] = []
	var guard := 0
	# Bounded retry loop, not a fixed-size sample: a picked dex could (in
	# principle) fail to build (PokemonFactory.build_species returns null
	# for an unknown dex) — retried with a fresh random pick rather than
	# shrinking the team, bounded so a pathological data state can't hang.
	while members.size() < clamped_size and guard < clamped_size * 20:
		guard += 1
		if species_pool.is_empty():
			break
		var entry: Dictionary = species_pool[randi() % species_pool.size()]
		var dex: int = int(entry.get("dex", -1))
		var species := PokemonFactory.build_species(dex)
		if species == null:
			continue

		var level := randi_range(min_level, max_level)
		var bp := PokemonFactory.create_battle_pokemon(
				dex, level, _random_move_ids(dex, level), randi() % 25,
				_random_ivs(), null, _random_evs(), _random_ability_slot(species))
		if bp != null:
			members.append(bp)

	var party := BattleParty.new()
	party.members = members
	party.active_indices = [0]
	return party


# 1-4 distinct, real, legal moves — a random SUBSET (shuffle-then-take,
# without replacement), not independent rolls that could repeat the same
# move. Returns fewer than 4 (down to 0) if the species' own real legal
# pool at this level is smaller — matches PokemonFactory's own tolerance
# for a 0-3-move BattlePokemon (the engine's pre-existing Struggle-fallback
# handles a move-less actor already; not a new failure mode this
# introduces).
static func _random_move_ids(dex: int, level: int) -> Array[int]:
	var legal: Array[int] = MovepoolResolver.legal_move_ids(dex, level)
	if legal.is_empty():
		return []
	legal.shuffle()
	var count: int = mini(legal.size(), 1 + randi() % 4)
	return legal.slice(0, count)


static func _random_ivs() -> Array[int]:
	var ivs: Array[int] = []
	for i in range(6):
		ivs.append(randi() % 32)
	return ivs


# Randomly distributes EV points across the 6 stats respecting BOTH the
# real per-stat cap (BattleManager.EV_CAP_PER_STAT) and the real total cap
# (BattleManager.EV_CAP_TOTAL) — the same two constants team_builder_screen
# .gd's own EV SpinBoxes enforce, read directly rather than re-declared.
# A bounded loop (not a fixed formula): repeatedly commits a random-sized
# chunk to a random stat until the total cap is reached or the guard trips
# — terminates quickly in practice (6 stats × 252 far exceeds the 510
# total budget, so only a handful of stats end up touched at all).
static func _random_evs() -> Array[int]:
	var evs: Array[int] = [0, 0, 0, 0, 0, 0]
	var remaining: int = BattleManager.EV_CAP_TOTAL
	var guard := 0
	while remaining > 0 and guard < 60:
		guard += 1
		var stat := randi() % 6
		if evs[stat] >= BattleManager.EV_CAP_PER_STAT:
			continue
		var room: int = mini(remaining, BattleManager.EV_CAP_PER_STAT - evs[stat])
		var add: int = 1 + randi() % room
		evs[stat] += add
		remaining -= add
	return evs


static func _random_ability_slot(species: PokemonSpecies) -> int:
	var valid_slots: Array[int] = []
	for slot in range(species.abilities.size()):
		if species.abilities[slot] > 0:
			valid_slots.append(slot)
	if valid_slots.is_empty():
		return PokemonFactory.ABILITY_SLOT_PRIMARY
	return valid_slots[randi() % valid_slots.size()]
