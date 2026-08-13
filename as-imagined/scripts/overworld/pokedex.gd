class_name Pokedex
extends RefCounted

## [Specials Tier 3] Which species the player has SEEN and CAUGHT.
##
## ⚠️ **THIS IS NOT THE POKÉDEX SCREEN, AND THE DISTINCTION IS THE WHOLE REASON
## THIS EXISTS SEPARATELY.** `docs/m27_corridor_opcode_scope.md` filed five
## reachable specials — `GetFrlgPokedexCount` (×5), `HasAllKantoMons`,
## `HasAllMons`, `GetProfOaksRatingMessage`, `EnableNationalPokedex` — under
## "M33 (Pokédex)", which read as "blocked on a whole browsable dex UI". Reading
## their real bodies during the specials Step 0 showed every one of them wants
## only two bitsets and a count. `GetFrlgPokedexCount`'s entire body writes
## `GetKantoPokedexCount(SEEN)` and `...(CAUGHT)` into `VAR_0x8005`/`VAR_0x8006`
## and returns `IsNationalPokedexEnabled()` (`birch_pc.c:92`). None of them open
## a screen. M33 still owns the screen; it CONSUMES this.
##
## That mattered in play: `GetFrlgPokedexCount` is what Oak's "you have no Poké
## Balls left, take five more" safety net branches on, so the halt made an
## already-cleared soft-lock reachable a second way.
##
## ⚠️ **INDEXED BY NATIONAL DEX NUMBER, 1-BASED.** Source stores a bit per
## species in `dexSeen`/`dexCaught` and every accessor does `nationalDexNo--`
## before indexing (`pokedex.c:4513`). This project keeps a Dictionary-as-set of
## the same 1-based numbers instead of a packed bitfield — the storage is a
## mechanism choice (M27's own "port the behaviour, not the mechanism" rule),
## while the INDEX SPACE is behaviour and is preserved exactly, because
## `PokemonSpecies.national_dex_num` is already that same number.

## Source's `KANTO_DEX_COUNT` = `KANTO_DEX_MEW + 1` = 151
## (`constants/pokedex.h:1527`).
const KANTO_DEX_COUNT := 151

## ⚠️ **MEW IS EXCLUDED FROM EVERY KANTO COUNT, AND IT IS NOT AN OFF-BY-ONE.**
## Both `GetKantoPokedexCount` (`pokedex.c:4593`) and `HasAllKantoMons`
## (`:4635`) loop `i < KANTO_DEX_COUNT - 1`, and the latter carries source's own
## comment `// -1 excludes Mew`. So "all Kanto Pokémon" means 150, and the
## rating counts stop at Bulbasaur..Mewtwo. Writing `<= 151` here would make
## Oak's completion check unsatisfiable in a way nothing would report.
const KANTO_COUNTED := KANTO_DEX_COUNT - 1

## The three-part test `IsNationalPokedexEnabled` performs (`event_data.c:93`)
## reduced to the one part this project can hold. Source additionally checks a
## `nationalMagic` byte of 0xDA and `VAR_NATIONAL_DEX == 0x302`; both are
## save-block integrity checks against a corrupted or transferred save, not game
## state, and this project has neither field. The flag IS the state.
const NATIONAL_FLAG := "FLAG_SYS_NATIONAL_DEX"

var _seen: Dictionary = {}
var _caught: Dictionary = {}


## Source: `GetSetPokedexFlag(n, FLAG_SET_SEEN)`.
##
## ⚠️ Silently ignores a non-positive number rather than storing it. Source
## cannot receive one — `SpeciesToNationalPokedexNum` always answers a real
## entry — but this project's `national_dex_num` is 0 for a hand-built test
## fixture with no registry backing, and a 0 in the set would be counted by
## nothing and yet inflate `national_seen_count`.
func mark_seen(national_dex_num: int) -> void:
	if national_dex_num > 0:
		_seen[national_dex_num] = true


## Source: `GetSetPokedexFlag(n, FLAG_SET_CAUGHT)`.
##
## ⚠️ **CATCHING ALSO MARKS SEEN, and that is source's own pairing rather than a
## convenience here.** Every acquisition site sets both, one after the other —
## `GiveMonToPlayer` (`pokemon.c:6885-6886`), the egg hatch, the evolution
## scene. Folding it in means no caller can set one and forget the other, which
## would leave a caught species missing from the SEEN count that Oak's rating
## reads.
func mark_caught(national_dex_num: int) -> void:
	if national_dex_num > 0:
		_seen[national_dex_num] = true
		_caught[national_dex_num] = true


func is_seen(national_dex_num: int) -> bool:
	return _seen.has(national_dex_num)


func is_caught(national_dex_num: int) -> bool:
	return _caught.has(national_dex_num)


## `GetKantoPokedexCount(FLAG_GET_SEEN)` — Bulbasaur..Mewtwo, Mew excluded.
func kanto_seen_count() -> int:
	return _count_in_range(_seen, KANTO_COUNTED)


## `GetKantoPokedexCount(FLAG_GET_CAUGHT)`.
func kanto_caught_count() -> int:
	return _count_in_range(_caught, KANTO_COUNTED)


## `GetNationalPokedexCount(...)`. ⚠️ Bounded by THIS PROJECT'S roster rather
## than source's `NATIONAL_DEX_COUNT`, which is a later-generation constant
## (`pokedex.h:1048-1055` resolves it to Pecharunt/Hydrapple/etc. depending on
## config). The honest ceiling here is the number of species that exist to be
## caught, and `PokemonRegistry` is the one place that knows it.
func national_seen_count() -> int:
	return _count_in_range(_seen, _roster_size())


func national_caught_count() -> int:
	return _count_in_range(_caught, _roster_size())


## `HasAllKantoMons` (`pokedex.c:4635`) — every Kanto species CAUGHT, Mew
## excluded.
##
## ⚠️ Source additionally skips a species that `isMythical && !dexForceRequired`.
## This project's species data carries no mythical flag at all, so the check
## cannot be reproduced; within Kanto the only entry it would exempt is Mew,
## which the `-1` already excludes. Recorded rather than silently dropped: a
## future roster carrying mythical data should revisit this, and the NATIONAL
## version below is where it would actually bite.
func has_all_kanto() -> bool:
	for n in range(1, KANTO_COUNTED + 1):
		if not _caught.has(n):
			return false
	return true


## `HasAllMons` (`pokedex.c:4649`) — the whole roster caught. Same mythical
## caveat as `has_all_kanto`, and here it is a real divergence rather than a
## theoretical one: source exempts Mew, Celebi, Jirachi and Deoxys, so a player
## who caught everything obtainable would still read FALSE here.
func has_all() -> bool:
	for n in range(1, _roster_size() + 1):
		if not _caught.has(n):
			return false
	return true


## `IsNationalPokedexEnabled` / `EnableNationalPokedex` (`event_data.c:82, 93`).
static func national_enabled(flags: FlagStore) -> bool:
	return flags != null and flags.flag_get(NATIONAL_FLAG)


static func enable_national(flags: FlagStore) -> void:
	if flags != null:
		flags.flag_set(NATIONAL_FLAG)


## `GetProfOaksRatingMessageByCount` (`birch_pc.c:107`) — the rating band, as a
## multiple of ten, for a caught count.
##
## ⚠️ **THE MEW DECREMENT IS REAL AND EASY TO MISS.** Source's first act is
## `if (count > 0 && GetSetPokedexFlag(NATIONAL_DEX_MEW, FLAG_GET_CAUGHT))
## count--;` — a player holding the event Mew has it subtracted before the band
## is chosen, so Mew never flatters the rating. Reproduced rather than dropped,
## because it changes the message at every boundary for exactly the players most
## likely to notice.
##
## Returns the band's lower bound (0, 10, 20, ... 200), which the caller maps to
## a message label. Kept as a number rather than returning the label so the text
## side stays with the text layer.
func oaks_rating_band(count: int) -> int:
	var c := count
	if c > 0 and is_caught(NATIONAL_DEX_MEW):
		c -= 1
	return mini((c / 10) * 10, 200)


## Mew's national number, named rather than inlined — see `oaks_rating_band`.
const NATIONAL_DEX_MEW := 151


func _count_in_range(set: Dictionary, upper: int) -> int:
	var n := 0
	for key in set:
		if int(key) >= 1 and int(key) <= upper:
			n += 1
	return n


## The highest national dex number this project's roster actually contains.
## ⚠️ Derived from the registry rather than a literal 386: `pokemon.json` is
## hand-owned (CLAUDE.md's own note — "I control Pokémon stats"), so the roster
## is Rob's to grow, and a hardcoded ceiling would silently stop counting the
## day it did. Cached because `has_all` walks it per call.
static var _cached_roster_size := 0

func _roster_size() -> int:
	if _cached_roster_size == 0:
		for dex in PokemonRegistry._species_by_dex:
			_cached_roster_size = maxi(_cached_roster_size, int(dex))
	return _cached_roster_size


func to_save() -> Dictionary:
	# ⚠️ Sorted arrays rather than the dictionaries themselves: JSON turns an int
	# key into a string, and this project has already paid for that once (see
	# CLAUDE.md's own note on `JSON.parse_string` returning float keys). A list
	# of numbers round-trips unambiguously.
	var seen := _seen.keys()
	seen.sort()
	var caught := _caught.keys()
	caught.sort()
	return {"seen": seen, "caught": caught}


func from_save(data: Dictionary) -> void:
	_seen.clear()
	_caught.clear()
	for n in data.get("seen", []):
		mark_seen(int(n))
	for n in data.get("caught", []):
		mark_caught(int(n))


func clear() -> void:
	_seen.clear()
	_caught.clear()
