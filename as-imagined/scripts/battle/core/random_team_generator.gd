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
## ⚠️ **50/50, MATCHING THE TEAM BUILDER — changed from 10-70, Rob 2026-08-07.**
## `team_builder_screen.gd`'s own `_current_level` is 50, so a saved team is a
## level-50 team; a random opponent rolling 10-70 produced the "oddly-matched
## opponents" M25F recorded as an open balance item. A level-14 Caterpie against
## a level-50 saved team is not a battle, and it is not a useful animation
## bench either — half the moves never get cast because the mon faints first.
##
## Kept as a RANGE rather than a single constant so a caller that genuinely
## wants variety (a future wild-encounter or facility generator) can still ask
## for one; the DEFAULT is what changed, not the capability.
const DEFAULT_MIN_LEVEL := 50
const DEFAULT_MAX_LEVEL := 50


## [M36 bench] `move_range` and `force_moves` exist to make this an ANIMATION
## TEST BENCH as well as a battle generator.
##
## `move_range` is an inclusive (from, to) pair of move ids; `Vector2i(0, 0)`
## means "no filter" and reproduces the pre-bench behaviour exactly, which is
## what every existing caller gets.
##
## ⚠️ **`force_moves` IGNORES LEGALITY, AND THAT IS THE POINT — but it is opt-in
## for a reason.** Moves 1-100 are largely Gen 1 physical moves, so a randomly
## picked Gen 4+ species may legally know NONE of them: filtering the legal pool
## alone yields empty movesets and poor coverage of the very range you asked to
## see. Forcing guarantees every battler on the field casts from the range.
## It also produces Charizard with Karate Chop, which is nonsense in a real
## battle — hence a caller has to ask for it explicitly rather than getting it
## by default from a screen that is the simulator's real front door.
static func generate_team(size: int = DEFAULT_TEAM_SIZE, min_level: int = DEFAULT_MIN_LEVEL,
		max_level: int = DEFAULT_MAX_LEVEL,
		move_range: Vector2i = Vector2i.ZERO,
		force_moves: bool = false) -> BattleParty:
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
				dex, level, _random_move_ids(dex, level, move_range, force_moves),
				randi() % 25,
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
static func _random_move_ids(dex: int, level: int,
		move_range: Vector2i = Vector2i.ZERO, force_moves: bool = false) -> Array[int]:
	var legal: Array[int] = MovepoolResolver.legal_move_ids(dex, level)

	if move_range != Vector2i.ZERO:
		var lo: int = mini(move_range.x, move_range.y)
		var hi: int = maxi(move_range.x, move_range.y)
		var in_range: Array[int] = []
		for m in legal:
			if m >= lo and m <= hi:
				in_range.append(m)
		if force_moves:
			# ⚠️ **BUILT FROM THE RANGE ITSELF, NOT FROM THE LEGAL POOL** —
			# every id in the window is a candidate whether or not this species
			# could ever learn it. Filtered to ids that actually EXIST, because
			# the id space is not contiguous and handing PokemonFactory a
			# non-move would produce a silent empty slot rather than an error.
			var forced: Array[int] = []
			for m in range(lo, hi + 1):
				if MoveRegistry.get_move(m) != null:
					forced.append(m)
			if not forced.is_empty():
				forced.shuffle()
				return forced.slice(0, mini(forced.size(), 4))
		# Legal-only: fall back to the unfiltered legal pool when this species
		# knows nothing in the window, rather than returning a move-less mon
		# that just Struggles — which would look like a broken bench.
		if not in_range.is_empty():
			in_range.shuffle()
			return in_range.slice(0, mini(in_range.size(), 4))

	if legal.is_empty():
		return []
	legal.shuffle()
	var count: int = mini(legal.size(), 4)
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
