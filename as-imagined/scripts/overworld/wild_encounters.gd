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

## `MAX_ENCOUNTER_RATE` (`wild_encounter.c:36`). The denominator of the odds roll.
const MAX_ENCOUNTER_RATE := 2880

## `WildEncounterCheck`'s own first line: `encounterRate *= 16`. Without it every
## table's rate would be 16x too low and grass would feel dead — Viridian Forest's
## 14 would be 0.5% a step rather than 7.8%.
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


## Does this map have a land table at all? Most do not — 192 of 421 region-wide,
## and only 5 of the 32 baked corridor maps.
static func has_table(map_name: String) -> bool:
	return _load().get("maps", {}).has(map_name)


static func table_for(map_name: String) -> Dictionary:
	return _load().get("maps", {}).get(map_name, {})


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
static func should_encounter(map_name: String, behavior: int, prev_behavior: int,
		rng: RandomNumberGenerator, lead_ability_id: int = -1) -> bool:
	if not is_land_encounter_tile(behavior):
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
