class_name WildEncounters
extends RefCounted

## [M27H H2] The wild-encounter roll.
##
## Source: `StandardWildEncounter` / `WildEncounterCheck` / `ChooseWildMonIndex_Land`
## / `ChooseWildMonLevel` (`src/wild_encounter.c`).
##
## ⚠️ **REPEL AND THE POST-BATTLE IMMUNITY WINDOW ARE DELIBERATELY ABSENT —
## ROB'S DECISION, 2026-08-03, AGAINST the recommendation in
## `docs/m27_next_step_recon.md` §2.3.** Source gates encounters on
## `RestartWildEncounterImmunitySteps` (a few free steps after a battle) and on a
## repel step counter. Neither is ported. **A later session finding either in
## source must NOT "fix" it without asking** — the absence is a decision, and
## back-to-back encounters immediately after a battle are the known consequence.

const TABLE_PATH := "res://data/land_encounters.json"

## `MAX_ENCOUNTER_RATE`. The denominator of the odds roll.
##
## ⚠️ **THIS IS FIRE RED'S 1600 (`pokefirered/src/wild_encounter.c:31`), NOT
## EMERALD'S 2880 (`pokeemerald_expansion/src/wild_encounter.c:36`) — Rob's
## call, 2026-08-12, and a DELIBERATE departure from this project's default
## reference.** `[M27H H2]` ported Emerald's `WildEncounterCheck` and pointed it
## at Fire Red's per-map rate values, which quietly halved encounter frequency
## everywhere for as long as grass has worked.
##
## The obvious defence — that the two games' rate VALUES compensate for their
## different denominators — was measured and does not hold: Kanto's land rates
## span 1-21 (median 7) and Hoenn's span 4-25 (median 10), the same numeric
## band. So the denominator alone sets felt density, and Fire Red is genuinely
## the denser game. Viridian Forest's 14 is 14.0% a step here, where at 2880 it
## was 7.8% — one encounter every ~7 steps rather than every ~13.
##
## The change is cleanly linear because **the cap never binds**: the highest
## rate in the whole corpus is 25, i.e. 400 after `RATE_SCALE`, well under
## either ceiling even with a lead ability doubling it. `effective_rate`'s clamp
## below is therefore unreachable in practice and kept for source fidelity.
##
## See `docs/m27t_encounter_authoring_scope.md` §2.1.
const MAX_ENCOUNTER_RATE := 1600

## `WildEncounterCheck`'s own first line: `encounterRate *= 16`. Without it every
## table's rate would be 16x too low and grass would feel dead — Viridian Forest's
## 14 would be 0.875% a step rather than 14%.
##
## (Those two figures were 0.5% and 7.8% until `MAX_ENCOUNTER_RATE` moved to Fire
## Red's 1600; see the note there.)
const RATE_SCALE := 16

## `AllowWildCheckOnNewMetatile`: `Random() % 100 >= 60` -> refuse.
##
## ⚠️ This is NOT the immunity window Rob declined. It is a per-step gate inside
## the trigger itself, and it only applies when the metatile behaviour CHANGED
## since the last step — walking from a path into grass gets one roll at 40%,
## while walking grass-to-grass always proceeds to the rate check.
const NEW_METATILE_ALLOW_PERCENT := 40

## Land-encounter behaviours: source's `IsEncounterTile && !IsSurfableWaterOrUnderwater`
## — i.e. `TILE_FLAG_HAS_ENCOUNTERS` minus the water ones.
##
## ⚠️ **`MB_CAVE` IS ONE OF THEM, WHICH A GRASS-ONLY READING MISSES.** The corridor
## has 46 cave cells (Diglett's Cave North Entrance) that are inert only because
## that map carries no table — the moment Diglett's Cave B1F is baked they are
## live, and a trigger keyed on grass alone would silently never fire there.
const LAND_BEHAVIORS := [
	MetatileBehavior.MB_TALL_GRASS,
	MetatileBehavior.MB_LONG_GRASS,
	MetatileBehavior.MB_UNUSED_05,
	MetatileBehavior.MB_DEEP_SAND,
	MetatileBehavior.MB_CAVE,
	MetatileBehavior.MB_INDOOR_ENCOUNTER,
	MetatileBehavior.MB_ASHGRASS,
	MetatileBehavior.MB_FOOTPRINTS,
	MetatileBehavior.MB_CYCLING_ROAD_PULL_DOWN_GRASS,
]

## The water half of the same split: `TILE_FLAG_HAS_ENCOUNTERS` **and**
## `TILE_FLAG_SURFABLE`, extracted from `sTileBitAttributes` rather than reasoned
## from the names — which matters, because 12 further behaviours are surfable and
## carry NO encounters (`MB_WATERFALL`, `MB_FAST_WATER`, all four currents,
## `MB_CYCLING_ROAD_WATER`…) and a name-based reading would sweep them in.
##
## ⚠️ **UNREACHABLE FROM PLAY TODAY — water encounters are M27E.** It exists so
## the behaviour-derived fallback below is SYMMETRIC: without it a hand-painted
## ocean cell would report NONE while an imported one reported WATER, which is
## the kind of asymmetry that surfaces months later as "surfing doesn't work on
## the map I made".
const WATER_BEHAVIORS := [
	MetatileBehavior.MB_POND_WATER,
	MetatileBehavior.MB_INTERIOR_DEEP_WATER,
	MetatileBehavior.MB_DEEP_WATER,
	MetatileBehavior.MB_OCEAN_WATER,
	MetatileBehavior.MB_SEAWEED,
	MetatileBehavior.MB_SEAWEED_NO_SURFACING,
]

## ⚠️ **STENCH IS THE ONE ABILITY M17 NEVER CLOSED**, and this is the first thing
## that would consume it. `docs/m17_final_ledger.md` records the whole 318-ability
## sweep as 226 implemented / 91 excluded / **1 open — Stench**, awaiting Rob's
## implement-or-exclude call.
##
## Deliberately a LITERAL ID here rather than a new `AbilityManager.ABILITY_STENCH`
## constant: adding that constant is what closing M17's last item looks like, and
## doing it as a side effect of an encounter roll would quietly answer a question
## that is Rob's. Halving the encounter rate is Stench's real field effect, so the
## behaviour is correct the moment the ability exists — and inert until then,
## since nothing can currently have it.
const ABILITY_STENCH_ID := 1

static var _table: Dictionary = {}


static func _load() -> Dictionary:
	if not _table.is_empty():
		return _table
	var f := FileAccess.open(TABLE_PATH, FileAccess.READ)
	if f == null:
		return _table
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) == TYPE_DICTIONARY:
		_table = parsed
	return _table


static func is_land_encounter_tile(behavior: int) -> bool:
	return behavior in LAND_BEHAVIORS


static func is_water_encounter_tile(behavior: int) -> bool:
	return behavior in WATER_BEHAVIORS


## [M27T piece 4] The Emerald rule, kept as the FALLBACK it now is.
##
## This is what the trigger used to ask outright. It survives for the two cases
## where Fire Red's stamp cannot answer: a hand-painted cell (which Fire Red
## never saw, so it has no stamp) and a tileset pair whose sidecar has not been
## generated.
static func type_from_behavior(behavior: int) -> int:
	if is_land_encounter_tile(behavior):
		return MapManager.EncounterType.LAND
	if is_water_encounter_tile(behavior):
		return MapManager.EncounterType.WATER
	return MapManager.EncounterType.NONE


## [M27T piece 4] What kind of wild encounter, if any, this cell hosts.
##
## ⚠️ **THIS IS THE DELIBERATE DIVERGENCE FROM THIS PROJECT'S DEFAULT REFERENCE
## — Rob's call, 2026-08-12.** pokeemerald-expansion asks what KIND of tile this
## is (`MetatileBehavior_IsLandWildEncounter`, i.e. the behaviour sets above) and
## `[M27H H2]` ported that correctly. **Fire Red asks a different question**: it
## reads a per-tile stamp the developers set by hand
## (`ExtractMetatileAttribute(..., METATILE_ATTRIBUTE_ENCOUNTER_TYPE)`,
## `pokefirered/src/wild_encounter.c:704-707`). Neither is a bug; each is right
## for its own game, and this project's maps, tilesets and art are all Fire Red's.
##
## Measured across all 421 Kanto maps, the two disagree on **15,677 cells**, and
## the land half is one-directional: **9,711 cells are stamped LAND that the
## behaviour rule cannot see**, 7,275 of them plain `MB_NORMAL`. Pokemon Mansion
## is the case that makes it concrete — its ordinary floor tiles are stamped, so
## real Fire Red has you meeting Grimer and Koffing in the corridors while the
## behaviour rule leaves the whole building silent.
##
## ⚠️ **A HAND-PAINTED CELL KEEPS USING WHAT YOU PAINTED, AND THAT IS LOAD-BEARING
## RATHER THAN A COURTESY.** A tile placed in the editor has no stamp, because
## Fire Red never saw it. Xanadu Nursery is the live proof: its 91 grass cells
## are painted on top of the plain-floor metatile, whose stamp is NONE — so a
## pure-stamp read would have silently killed every encounter on the project's
## first authored map. `BEHAVIOR_EXPLICIT` is already set on exactly those 91
## cells and nowhere else, by the paint itself, so this override needed no new
## data. On IMPORTED land data it is provably a no-op: behaviour-land is a strict
## subset of stamp-land, measured, so the override can only ever agree.
##
## Scope of record: `docs/m27t_encounter_authoring_scope.md` §3.
static func encounter_type_at(manager: MapManager, gcell: Vector2i) -> int:
	if manager == null:
		return MapManager.EncounterType.NONE
	var d := manager.data_at(gcell)
	if d == null:
		return MapManager.EncounterType.NONE
	var l := manager.local_of(gcell)
	return resolve_encounter_type(d, l.x, l.y)


## The rule itself, against a bare `MapData` in LOCAL cells.
##
## ⚠️ **SPLIT OUT SO THE EDITOR AND THE GAME CANNOT DISAGREE.** The overlay works
## on an open `MapData` with no `MapManager` anywhere, so it cannot call
## `encounter_type_at` — and the first cut of it therefore read the raw stamp
## and skipped the hand-painted override entirely. That made the ENCOUNTERS view
## silently WRONG on exactly the maps the override exists for: Xanadu Nursery's
## 91 painted grass cells drew as empty while the game encountered on them. Two
## hand-kept copies of one rule is the drift that has already cost this project
## a permanent `check_bake_diff` false positive; one function, two callers.
static func resolve_encounter_type(d: MapData, x: int, y: int) -> int:
	if d == null or not d.in_bounds(x, y):
		return MapManager.EncounterType.NONE
	if d.behavior_is_explicit(x, y):
		return type_from_behavior(d.behavior_at(x, y))
	var stamped := MapManager.encounter_type_for(d.atlas, d.metatile_at(x, y))
	# ⚠️ -1 is "this pair has no sidecar", NOT "nothing here". Degrading to the
	# behaviour rule keeps an unregenerated checkout playing exactly as it did
	# before piece 4, where treating it as NONE would silently empty every map
	# on that pair. The loudness lives where it can be acted on instead: the
	# overlay flags the pair and the suite asserts all 60 tables exist.
	if stamped < 0:
		return type_from_behavior(d.behavior_at(x, y))
	return stamped


## Does this map have a land table at all? Most do not — 192 of 421 region-wide,
## and only 5 of the 32 baked corridor maps.
static func has_table(map_name: String) -> bool:
	return _load().get("maps", {}).has(map_name) \
			or _load_authored().has(map_name)


## [M27M5 C3] Authored maps' own tables, hand-owned and merged on a MISS.
##
## ⚠️ **THE FILE THIS SITS BESIDE IS GENERATED** — `gen_wild_encounters.py`
## rebuilds `land_encounters.json` from the reference, so an authored map added
## there would be erased on the next run, silently. Same two-files-two-owners
## split as `AuthoredMaps` beside the generated `MapConstants`, for the same
## reason and with the same delegate-on-miss shape.
##
## ⚠️ **JSON, not fields on `MapData` — Rob's call, 2026-08-09**, and it follows
## this project's own two-layer data rule: full dataset in JSON, implemented
## BEHAVIOUR in `.tres`. An encounter table is dataset, and every other
## encounter table in the project is already JSON; a second storage shape for
## one kind of data would be drift arriving disguised as a convenience.
const AUTHORED_PATH := "res://data/authored_encounters.json"

static var _authored: Dictionary = {}
static var _authored_loaded := false


static func _load_authored() -> Dictionary:
	if _authored_loaded:
		return _authored
	_authored_loaded = true
	# Absent is the NORMAL state, not an error: a project with no authored map
	# has no such file, and warning about it every boot would train the eye to
	# ignore the one time it matters.
	if not FileAccess.file_exists(AUTHORED_PATH):
		return _authored
	var f := FileAccess.open(AUTHORED_PATH, FileAccess.READ)
	if f == null:
		return _authored
	var parsed = JSON.new()
	var err := parsed.parse(f.get_as_text())
	f.close()
	if err != OK or typeof(parsed.data) != TYPE_DICTIONARY:
		push_error("WildEncounters: %s is malformed — authored encounters "
				% AUTHORED_PATH + "ignored (line %d)" % parsed.get_error_line())
		return _authored
	_authored = parsed.data.get("maps", {})
	return _authored


## Every authored map name that has a table. Used by the integrity guard below
## and by tests; not a hot path.
static func authored_map_names() -> Array:
	return _load_authored().keys()


## ⚠️ **THE GUARD THAT MAKES A NAME-KEYED SIDE TABLE SAFE.**
##
## An authored map is exactly the kind that gets renamed, and a name-keyed table
## detaches SILENTLY when it does — the grass simply stops working, with no
## error and nothing pointing at the cause. This turns that into a named
## failure: every map named in the authored file must resolve to a real baked
## map. Returns the names that do not.
static func unresolved_authored_maps() -> Array:
	var bad: Array = []
	for name in _load_authored():
		if not ResourceLoader.exists("res://scenes/maps/%s.tscn" % str(name)):
			bad.append(name)
	return bad


static func table_for(map_name: String) -> Dictionary:
	# Generated first, authored second. They are disjoint by construction — an
	# imported map is never in the authored file and an authored map is never in
	# the generated one — so this is a fallback, not a precedence rule.
	var t: Dictionary = _load().get("maps", {}).get(map_name, {})
	return t if not t.is_empty() else _load_authored().get(map_name, {})


static func slot_rates() -> Array:
	return _load().get("slot_rates", [])


## Should a step onto `behavior` in `map_name` start an encounter?
##
## `prev_behavior` is what the player was standing on BEFORE this step; pass the
## same value to mean "unchanged". `rng` is injected so a test can force it.
##
## ⚠️ TWO ROLLS, IN THIS ORDER, and only the second one uses the table's rate.
## Collapsing them into one would make a path-to-grass step as likely as a
## grass-to-grass one, which is the opposite of how the reference feels.
static func should_encounter(map_name: String, encounter_type: int, behavior: int,
		prev_behavior: int, rng: RandomNumberGenerator,
		lead_ability_id: int = -1) -> bool:
	# [M27T piece 4] The trigger is the STAMP now, not the tile kind — see
	# `encounter_type_at`. `behavior` is still a parameter because the 40% gate
	# below is keyed on the behaviour CHANGING, which is true of Fire Red too
	# (`previousMetatileBehavior != ExtractMetatileAttribute(..., BEHAVIOR)`,
	# `pokefirered/src/wild_encounter.c:566`) — the two questions are asked of
	# the same tile for different reasons.
	if encounter_type != MapManager.EncounterType.LAND:
		return false
	if not has_table(map_name):
		return false
	if prev_behavior != behavior and rng.randi_range(0, 99) >= NEW_METATILE_ALLOW_PERCENT:
		return false
	var rate := effective_rate(int(table_for(map_name).get("encounter_rate", 0)),
			lead_ability_id)
	return rng.randi_range(0, MAX_ENCOUNTER_RATE - 1) < rate


## `WildEncounterCheck`'s rate math, including the LEAD's own ability.
##
## ⚠️ The ability modifiers are part of this function in source, not a separate
## gate — so porting the roll without them would be porting half a function.
## Every ability named here is already implemented in this project's battle
## engine; the bike/flute/cleanse-tag/lure terms are skipped because none of
## those exist here at all.
static func effective_rate(base_rate: int, lead_ability_id: int) -> int:
	var rate := base_rate * RATE_SCALE
	match lead_ability_id:
		ABILITY_STENCH_ID, AbilityManager.ABILITY_WHITE_SMOKE, \
		AbilityManager.ABILITY_QUICK_FEET:
			rate = rate / 2
		AbilityManager.ABILITY_ILLUMINATE, AbilityManager.ABILITY_ARENA_TRAP, \
		AbilityManager.ABILITY_NO_GUARD:
			rate = rate * 2
	return mini(rate, MAX_ENCOUNTER_RATE)


## Which of the 12 slots. Source walks a cumulative table; this reads the same
## numbers straight out of the data rather than hardcoding them.
static func choose_slot(rng: RandomNumberGenerator) -> int:
	var rates := slot_rates()
	if rates.is_empty():
		return 0
	var roll := rng.randi_range(0, 99)
	var acc := 0
	for i in range(rates.size()):
		acc += int(rates[i])
		if roll < acc:
			return i
	return rates.size() - 1


## `ChooseWildMonLevel`: uniform between min and max inclusive.
##
## Source additionally swaps them if min > max — reproduced, because the data is
## reference data and a bad row would otherwise make `randi_range` error rather
## than degrade.
static func choose_level(slot: Dictionary, rng: RandomNumberGenerator) -> int:
	var lo := int(slot.get("min", 1))
	var hi := int(slot.get("max", 1))
	if hi < lo:
		var t := lo
		lo = hi
		hi = t
	return rng.randi_range(lo, hi)


## Build the wild party — always exactly one Pokémon.
##
## Returns null if the map has no table or the species will not build, so the
## caller can decline the encounter rather than start an empty battle.
static func build_wild_party(map_name: String, rng: RandomNumberGenerator) -> BattleParty:
	var t := table_for(map_name)
	if t.is_empty():
		return null
	var slots: Array = t.get("slots", [])
	if slots.is_empty():
		return null
	var idx := choose_slot(rng)
	if idx >= slots.size():
		idx = slots.size() - 1
	var slot: Dictionary = slots[idx]
	var mon := PokemonFactory.create_battle_pokemon(
			int(slot.get("dex", 0)), choose_level(slot, rng))
	if mon == null:
		return null
	var party := BattleParty.new()
	party.members.append(mon)
	party.active_indices = [0]
	return party
