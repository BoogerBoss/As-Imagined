class_name PokemonFactory
extends RefCounted

# [M23.3] Converts REAL species/move data (loaded by the PokemonRegistry
# autoload from data/pokemon.json + data/learnsets.json at boot — the same
# registry every scene's own "PokemonRegistry: smoke test passed..." boot
# log confirms) into real, valid BattlePokemon instances — replacing the
# hand-built `PokemonSpecies.new()` + manually-set base-stat fields every
# test file (and M23.1's battle screen) constructs by hand.
#
# This is a pure converter: it reads PokemonRegistry (species/learnset data)
# and MoveRegistry (real MoveData .tres Resources — NOT
# PokemonRegistry.get_move(), which returns data/moves.json's own raw dict;
# confirmed via `[M19-pipeline-fix]`'s decisions.md entry that this JSON
# pipeline has zero real production consumers — every real move mechanic is
# `.tres`-sourced through MoveRegistry instead), and produces
# PokemonSpecies/BattlePokemon Resources via the exact same
# BattlePokemon.from_species(...) constructor every hand-built fixture
# already uses — no new BattlePokemon/BattleManager machinery, no changes to
# either registry or to battle_manager.gd.
#
# NOT wired into battle_screen.gd by this milestone — M23.1's hardcoded
# teams are untouched. Per the M23 roadmap, connecting real team data to the
# battle screen is M23.6's job (once M23.4's team builder exists to produce
# a real team in the first place); wiring this converter into the battle
# screen now, ahead of that, was considered and explicitly NOT done — see
# docs/m23_recon.md's M23.3 section for the full reasoning.
#
# Deliberately out of scope (flagged, not silently skipped):
#   - Held items: PokemonRegistry.get_item()/ItemRegistry both exist and
#     work, but the task's own parameter list (species/level/moveset/
#     nature/IVs/EVs) never asked for one, and a factory that also guesses
#     a "reasonable default held item" would be inventing scope. Add an
#     item parameter in a future session if a caller needs one — the
#     wiring is a one-line ItemRegistry.get_item(id) call, same shape as
#     the ability-loading code below.
#   - Cross-validating an EXPLICIT move request against the species' own
#     learnable-move list (PokemonRegistry.get_learnable_moves(dex), which
#     returns "MOVE_TACKLE"-style constant-name strings): reconciling that
#     naming scheme against MoveData.move_name's own display-string field
#     ("Tackle") would need a nontrivial, error-prone reverse name-mapping
#     (apostrophes, hyphens, "Mr. Mime"-style special cases — the same class
#     of complexity PokemonRegistry._name_to_learnable_key already fights on
#     the species-name side). This factory validates only that a requested
#     move ID resolves to a real, implemented MoveData via MoveRegistry —
#     it does NOT check whether the species could actually learn that move
#     in the source game. A future team builder wanting that stricter check
#     should build it directly against get_learnable_moves(dex).
#   - Evolution-aware construction (e.g. "build whatever this species
#     becomes at level 100"): out of scope — this factory builds exactly the
#     species/level requested, nothing more.
#   - Growth-rate population on the constructed PokemonSpecies Resource:
#     see build_species()'s own doc comment below for why this is
#     deliberately left at its dormant default rather than mapped.


const ABILITY_SLOT_PRIMARY: int = 0
const ABILITY_SLOT_SECONDARY: int = 1
const ABILITY_SLOT_HIDDEN: int = 2


# Builds a real PokemonSpecies Resource from PokemonRegistry's raw JSON dict
# for one national dex number. Returns null if the dex number isn't in the
# registry (386 species currently loaded) — a caller must check for null
# rather than receiving a bogus zero-stat species.
#
# [JSON float gotcha] JSON.parse_string returns numeric values as float, not
# int (a standing GDScript gotcha throughout this project) — every numeric
# field read from the raw dict is explicitly int()-cast below; without this,
# assigning a float into one of PokemonSpecies's strictly `int`-typed
# @export fields throws a runtime type-mismatch error.
static func build_species(dex: int) -> PokemonSpecies:
	var data: Dictionary = PokemonRegistry.get_species(dex)
	if data.is_empty():
		return null

	var sp := PokemonSpecies.new()
	sp.species_name = str(data.get("name", ""))
	sp.national_dex_num = dex
	sp.base_hp         = int(data.get("base_hp", 1))
	sp.base_attack     = int(data.get("base_atk", 1))
	sp.base_defense    = int(data.get("base_def", 1))
	sp.base_sp_attack  = int(data.get("base_spa", 1))
	sp.base_sp_defense = int(data.get("base_spd", 1))
	sp.base_speed      = int(data.get("base_spe", 1))

	# [Real-data quirk] pokemon.json encodes a mono-typed species as the SAME
	# type repeated twice (e.g. Pikachu = [14, 14]), NOT [type, TYPE_NONE] —
	# confirmed by direct inspection, not assumed from PokemonSpecies' own
	# doc comment (which describes the TYPE_NONE convention hand-built test
	# fixtures use). Normalized here so downstream dual-type-aware code
	# (type effectiveness, Flying Press's two-typed-move product, etc.)
	# never sees a duplicated second type.
	var raw_types: Array = data.get("types", [])
	var t1: int = int(raw_types[0]) if raw_types.size() > 0 else TypeChart.TYPE_NORMAL
	var t2: int = int(raw_types[1]) if raw_types.size() > 1 else t1
	var types: Array[int] = [t1]
	if t2 != t1:
		types.append(t2)
	sp.types = types

	var abilities: Array[int] = [
		int(data.get("ability1", 0)), int(data.get("ability2", 0)), int(data.get("ability_h", 0))]
	sp.abilities = abilities

	sp.catch_rate    = int(data.get("catch_rate", 45))
	sp.exp_yield     = int(data.get("exp_yield", 64))
	sp.gender_ratio  = int(data.get("gender_ratio", 127))
	sp.weight        = int(data.get("weight", 1))
	sp.base_friendship = int(data.get("base_friendship", 50))
	sp.ev_yield_hp   = int(data.get("ev_yield_hp", 0))
	sp.ev_yield_atk  = int(data.get("ev_yield_atk", 0))
	sp.ev_yield_def  = int(data.get("ev_yield_def", 0))
	sp.ev_yield_spa  = int(data.get("ev_yield_spa", 0))
	sp.ev_yield_spd  = int(data.get("ev_yield_spd", 0))
	sp.ev_yield_spe  = int(data.get("ev_yield_spe", 0))

	var egg_groups: Array[int] = []
	for g in data.get("egg_groups", []):
		egg_groups.append(int(g))
	sp.egg_groups = egg_groups

	# [Deliberately NOT populated] growth_rate: PokemonSpecies.growth_rate is
	# a dormant `int` enum field with no defined mapping anywhere in this
	# codebase (its own doc comment just says "GrowthRate enum id"). The
	# REAL growth-rate value in data/pokemon.json is a STRING ("MediumSlow",
	# "Slow", etc.), and BattleManager._check_level_up already reads it
	# fresh, by design, straight from PokemonRegistry.get_species(dex) —
	# never from a PokemonSpecies instance field — specifically so the level-
	# up path stays correct across a future evolution mechanic with no
	# stale-species-snapshot risk (see that function's own doc comment).
	# Inventing an int mapping here would populate a field nothing reads,
	# using a scheme with no defined values — left at its default.
	var raw_learnset: Array = PokemonRegistry.get_learnset(dex)
	var learnset: Array[Dictionary] = []
	for entry: Dictionary in raw_learnset:
		learnset.append(entry)
	sp.learnset = learnset

	return sp


# Builds a real, valid BattlePokemon for a given dex/level, with a real
# ability and a real moveset (auto-derived from the species' own level-up
# learnset if move_ids is left empty).
#
# move_ids: explicit move ID list (only the first 4 valid entries are used).
#   Each ID is validated against MoveRegistry (a real, implemented .tres
#   move) — an invalid/unimplemented ID is silently skipped, matching
#   MoveRegistry.get_move()'s own push_warning-then-null convention (the
#   warning is the visible signal; this factory doesn't duplicate it). NOT
#   cross-validated against the species' own learnable-move list — see this
#   file's own top-of-file doc comment for why that's out of scope.
# forced_nature/forced_ivs/forced_friendship: passed straight through to
#   BattlePokemon.from_species (same Variant=null forcing convention used
#   throughout this project).
# evs: optional explicit [hp,atk,def,spa,spd,spe] array. from_species itself
#   has no EV parameter — it hardcodes zero (a M1-era placeholder, still the
#   only real EV-assignment path anywhere in BattlePokemon). Applied here as
#   a second pass: set, recalculate stats, and re-max current_hp, matching
#   from_species's own "freshly created" semantics. Malformed input (wrong
#   size) is ignored, leaving EVs at zero.
# ability_slot: which of the species' 3 ability slots (ABILITY_SLOT_*) to
#   assign. A slot whose ability ID is 0 ("None" — every species has at
#   least ability2=0 when it only has one standard ability slot) leaves
#   BattlePokemon.ability at its default null, matching the project-wide
#   "ability == null means no ability" convention (AbilityManager.
#   effective_ability_id's own null check) — id 0 is deliberately NOT
#   resolved to data/abilities/ability_0000.tres's real "None" placeholder
#   Resource, to stay consistent with every other code path in this project.
#
# Returns null if dex doesn't exist in the registry. level is clamped to
# [1, 100] (BattlePokemon/the EXP system's own real bounds), with a warning
# if the caller's request was out of range.
static func create_battle_pokemon(
		dex: int, level: int, move_ids: Array = [],
		forced_nature: Variant = null, forced_ivs: Variant = null,
		forced_friendship: Variant = null, evs: Variant = null,
		ability_slot: int = ABILITY_SLOT_PRIMARY) -> BattlePokemon:
	var species := build_species(dex)
	if species == null:
		push_warning("PokemonFactory: no species data for dex %d" % dex)
		return null

	var clamped_level: int = clampi(level, 1, 100)
	if clamped_level != level:
		push_warning("PokemonFactory: level %d out of [1,100] range, clamped to %d" % [level, clamped_level])

	var bp := BattlePokemon.from_species(
			species, clamped_level, forced_nature, forced_ivs, forced_friendship)

	if evs != null and evs is Array and evs.size() == 6:
		var typed_evs: Array[int] = []
		for v in evs:
			typed_evs.append(clampi(int(v), 0, 252))
		bp.evs = typed_evs
		bp._calculate_stats()
		bp.current_hp = bp.max_hp

	if ability_slot >= 0 and ability_slot < species.abilities.size():
		var ability_id: int = species.abilities[ability_slot]
		if ability_id > 0:
			var ability_path := "res://data/abilities/ability_%04d.tres" % ability_id
			if ResourceLoader.exists(ability_path):
				bp.ability = ResourceLoader.load(ability_path) as AbilityData

	var resolved_move_ids: Array = move_ids if not move_ids.is_empty() else _default_moveset(dex, clamped_level)
	for move_id in resolved_move_ids:
		if bp.moves.size() >= 4:
			break
		var move: MoveData = MoveRegistry.get_move(int(move_id))
		if move == null:
			continue  # [Edge case] invalid/unimplemented move ID — skipped, not fatal.
		if bp.moves.has(move):
			continue  # skip an accidental duplicate request
		bp.add_move(move)

	return bp


# Derives a default up-to-4-move moveset from the species' own level-up
# learnset: every entry learnable at or below `level`, kept in ascending
# learn-order, taking (up to) the last 4 — "what this Pokémon would
# realistically know by now," the same shape a real game's default wild/
# trainer moveset uses.
#
# [Edge case] fewer than 4 moves learnable at this level: handled for free —
# returns however many exist; BattlePokemon.add_move already tolerates a
# 1-3-move Pokémon with no special-casing needed here.
# [Edge case] ZERO moves learnable at or below this level (e.g. a level-1
# request for a species whose first learnset entry is level 3): falls back
# to the single LOWEST-level entry in the full learnset, so a freshly-built
# Pokémon always has at least one real move rather than none. If the
# learnset itself is completely empty, returns an empty array — the
# resulting 0-move BattlePokemon relies on the battle engine's own existing
# Struggle-fallback (every move-less actor already goes through that path
# today; this is not a new failure mode this factory introduces).
static func _default_moveset(dex: int, level: int) -> Array[int]:
	var learnset: Array = PokemonRegistry.get_learnset(dex)
	if learnset.is_empty():
		return []

	var eligible: Array = []
	for entry: Dictionary in learnset:
		if int(entry.get("level", 0)) <= level:
			eligible.append(entry)

	if eligible.is_empty():
		var lowest: Dictionary = learnset[0]
		for entry: Dictionary in learnset:
			if int(entry.get("level", 0)) < int(lowest.get("level", 0)):
				lowest = entry
		var lowest_id: int = int(lowest.get("move_id", -1))
		var fallback: Array[int] = []
		if lowest_id > 0:
			fallback.append(lowest_id)
		return fallback

	eligible.sort_custom(func(a, b): return int(a.get("level", 0)) < int(b.get("level", 0)))
	var last_four: Array = eligible.slice(maxi(0, eligible.size() - 4), eligible.size())
	var ids: Array[int] = []
	for entry: Dictionary in last_four:
		var mid: int = int(entry.get("move_id", -1))
		if mid > 0 and mid not in ids:
			ids.append(mid)
	return ids
