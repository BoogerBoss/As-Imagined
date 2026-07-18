class_name MovepoolResolver
extends RefCounted

# [M23.4] Computes a species' real, legal move set at a given level, for the
# team builder's move-selection UI to enforce as its ONLY selectable pool
# (so an illegal move is never constructible through the UI, per this
# milestone's own legality requirement — not merely rejected after the
# fact).
#
# Two real PokemonRegistry data sources exist and say different things:
#   - get_learnset(dex): level-up-only moves, each tagged with the real
#     level it's learned at.
#   - get_learnable_moves(dex): EVERY method combined (level-up + TM +
#     tutor + egg + universal moves like Substitute/Return/Hidden Power) —
#     confirmed via direct inspection of all_learnables.json (e.g.
#     Bulbasaur: 87 entries here vs. 11 level-up-only entries in its
#     learnset) — with NO per-entry method tag distinguishing which route
#     unlocked which move.
#
# [Flagged design decision — the one place this milestone's own task asked
# to flag an ambiguous rule rather than silently resolve it] Because
# get_learnable_moves() doesn't distinguish "TM-teachable regardless of
# level" from "only knowable via level-up," this resolver uses a
# deliberately CONSERVATIVE policy: a move is legal at a given level if it
# appears in get_learnable_moves() AND, if it ALSO appears in the level-up
# learnset specifically, the requested level is >= that level-up entry's
# level. A move that's level-up-only and not yet reached is excluded, even
# though the real game might make it independently available via TM/tutor
# at a lower level than this project's data can prove. This can produce a
# FALSE NEGATIVE (a move a real cartridge would allow gets excluded here)
# but never a false positive (an actually-illegal move is never let
# through) — the safe direction for a UI whose explicit job is to make
# illegal movesets unconstructible.
#
# Also filters to moves with real, IMPLEMENTED MoveData (via MoveRegistry)
# — this project implements 717 of 934 total moves; a move name that
# resolves to a real ID but has no shipped .tres is not offered, matching
# PokemonFactory.create_battle_pokemon's own silent-skip convention for an
# unresolvable move ID.


# Returns the sorted, deduplicated list of real, implemented move IDs a
# species can legally know at `level`, under the conservative policy
# documented above. Returns an empty array for an unknown dex number.
static func legal_move_ids(dex: int, level: int) -> Array[int]:
	if PokemonRegistry.get_species(dex).is_empty():
		return []

	var level_up_level_by_name: Dictionary = {}
	for entry: Dictionary in PokemonRegistry.get_learnset(dex):
		var name: String = str(entry.get("move_name", ""))
		var entry_level: int = int(entry.get("level", 0))
		if not level_up_level_by_name.has(name) or entry_level < level_up_level_by_name[name]:
			level_up_level_by_name[name] = entry_level

	var ids: Array[int] = []
	var seen: Dictionary = {}
	for move_name in PokemonRegistry.get_learnable_moves(dex):
		if level_up_level_by_name.has(move_name) and level_up_level_by_name[move_name] > level:
			continue  # level-up-only move not yet reached — conservative exclusion, see doc comment above.

		var move_id := MoveNameMap.id_for_name(move_name)
		if move_id <= 0 or seen.has(move_id):
			continue
		# [Avoids push_warning spam] Checked via ResourceLoader.exists directly
		# rather than MoveRegistry.get_move(id) — this resolver evaluates
		# dozens of candidate names per species/level change, and the
		# majority of PokemonRegistry's OWN "ever learnable" data (any
		# method, any generation) resolves to one of the ~217 moves this
		# project hasn't implemented; get_move()'s own push_warning-per-miss
		# convention is fine for the rare explicit-request case
		# PokemonFactory uses it for, not for a wide legality sweep like
		# this one.
		if not ResourceLoader.exists("res://data/moves/move_%04d.tres" % move_id):
			continue  # not yet implemented in this project — not offerable.

		seen[move_id] = true
		ids.append(move_id)

	ids.sort()
	return ids
