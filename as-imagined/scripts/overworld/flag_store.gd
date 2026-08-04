class_name FlagStore
extends RefCounted

## [M27D D4] The game's persistent flag and variable state.
##
## Source keeps two parallel arrays in the save block and addresses them by
## numeric id: `FlagGet(id)` bit-tests one, `VarGet(id)` reads a u16 from the
## other. This project addresses them by NAME instead, for the same reason
## `[M24a]` retired `trainer_id` in favour of `trainer_key`: the importer
## already carries source's own `FLAG_*`/`VAR_*` constants as strings on every
## placed entity, and a numeric id would be a second identity to keep in step.
##
## What this store must answer, all three of which already have imported data
## waiting for them and no reader until now:
##
##   * has this trainer been beaten            (D4, and every later encounter)
##   * is this object event hidden             (31 of the corridor's 132 carry a
##                                              `visibility_flag`)
##   * does this trigger's gate match          (30 corridor triggers across 9
##                                              distinct VARs)
##
## IN MEMORY ONLY, deliberately, but shaped for serialisation: both backing
## dictionaries are plain `String -> bool` / `String -> int`, so M27L can write
## them out without a conversion step. Nothing here reaches disk yet.


## Flag name -> true. A flag that has never been set is simply absent.
##
## Storing only the SET flags (rather than every known flag with a false value)
## matches `FlagGet`'s own behaviour for an unknown id — it returns FALSE rather
## than erroring — and keeps a save small: source has ~2400 flag slots and a
## real playthrough sets a small fraction of them.
var _flags: Dictionary = {}

## Var name -> int value. An unset var reads 0.
##
## NOTE this deliberately does NOT reproduce `VarGet`'s own quirk of returning
## the *id itself* when there is no backing pointer (`event_data.c`). That
## fallback exists to make the special 0x8000+ var range work as immediates in
## script arguments; with name keys there is no id to return, and M27G will
## resolve special vars by name at the call site instead.
var _vars: Dictionary = {}

## Prefix for the derived per-trainer "already beaten" flag.
##
## Source computes this as `TRAINER_FLAGS_START + trainerId` (0x500 + id,
## `battle_setup.c:1287`) — one dedicated bit per trainer, in its own reserved
## block. Deriving a name from the trainer's own key is the same idea with this
## project's own identity scheme, and keeps the beaten-set inside the one store
## rather than beside it.
const TRAINER_DEFEATED_PREFIX := "DEFEATED_"


## [M27L L1] `gBadgeFlags` (`event_data.c:39`), in order.
##
## ⚠️ **MOVED HERE FROM `overworld.gd`, WHERE IT WAS UNREACHABLE BY THE ONE
## OTHER READER THAT NEEDS IT.** The save-slot summary has to count badges for
## the CONTINUE card *before any field scene exists*, and `overworld.gd` carries
## no `class_name`, so the constant simply could not be seen from there. A flag
## list belongs to the flag store in any case; the alternative was a second copy,
## which is the drift `badge_count()` was extracted to prevent in the first place.
const BADGE_FLAGS := [
	"FLAG_BADGE01_GET", "FLAG_BADGE02_GET", "FLAG_BADGE03_GET", "FLAG_BADGE04_GET",
	"FLAG_BADGE05_GET", "FLAG_BADGE06_GET", "FLAG_BADGE07_GET", "FLAG_BADGE08_GET",
]


## How many badges this store records. ONE implementation, two callers — the
## overworld's whiteout payout and the save-slot summary.
func badge_count() -> int:
	var n := 0
	for f in BADGE_FLAGS:
		if flag_get(str(f)):
			n += 1
	return n


## Source: `FlagGet` (`event_data.c`). Unknown/unset reads FALSE, never errors.
func flag_get(flag_name: String) -> bool:
	return bool(_flags.get(flag_name, false))


## Source: `FlagSet`.
func flag_set(flag_name: String) -> void:
	if flag_name == "":
		return
	_flags[flag_name] = true


## Source: `FlagClear`. Erases rather than storing false, so the dictionary only
## ever holds set flags (see `_flags`).
func flag_clear(flag_name: String) -> void:
	_flags.erase(flag_name)


## Source: `VarGet`. An unset var reads 0 — see `_vars` for the one deliberate
## divergence from source's own fallback.
func var_get(var_name: String) -> int:
	return int(_vars.get(var_name, 0))


## [M27K K-c2] Whether this name has ever been written as a var.
##
## ⚠️ Exists because `var_get` cannot tell "a var holding 0" from "not a var at
## all", and one caller genuinely needs to: `ScriptVM._resolve_number` has to
## decide whether an argument is a var reference or a symbolic CONSTANT, which is
## the distinction source makes in `VarGet` by comparing against `VARS_START`.
func has_var(var_name: String) -> bool:
	return _vars.has(var_name)


## Source: `VarSet`.
func var_set(var_name: String, value: int) -> void:
	if var_name == "":
		return
	_vars[var_name] = value


## The flag name recording that `trainer_key` has been beaten.
##
## Static so a caller can name the flag without holding a store — the same shape
## as source, where `TRAINER_FLAGS_START + id` is computable anywhere.
static func trainer_defeated_flag(trainer_key: String) -> String:
	if trainer_key == "":
		return ""
	return TRAINER_DEFEATED_PREFIX + trainer_key


## Source: `HasTrainerBeenFought` (`battle_setup.c:1287`).
func trainer_defeated(trainer_key: String) -> bool:
	return flag_get(trainer_defeated_flag(trainer_key))


## Source: `SetTrainerFlag`.
func set_trainer_defeated(trainer_key: String) -> void:
	flag_set(trainer_defeated_flag(trainer_key))


## Is this entity currently on the map?
##
## Source hides an object event whose `visibility_flag` is SET — the flag means
## "hidden", not "shown", which is why every one of them reads `FLAG_HIDE_*`.
## An entity with no flag is always present.
func entity_visible(e: OverworldEntity) -> bool:
	if e == null:
		return false
	if e.visibility_flag == "":
		return true
	return not flag_get(e.visibility_flag)


## Does this trigger's gate currently match?
##
## Source's `ShouldTriggerScriptRun` compares the coord event's own var against
## its expected value. A trigger with no var name is ungated and always fires —
## `Trigger` already warns about that case at author time.
func trigger_armed(t: Trigger) -> bool:
	if t == null:
		return false
	if t.var_name == "":
		return true
	return var_get(t.var_name) == t.var_value


## Everything set, for serialisation and for tests. Copies, so a caller cannot
## mutate the store by holding the result.
func snapshot() -> Dictionary:
	return {"flags": _flags.duplicate(), "vars": _vars.duplicate()}


func restore(data: Dictionary) -> void:
	_flags = (data.get("flags", {}) as Dictionary).duplicate()
	_vars = (data.get("vars", {}) as Dictionary).duplicate()


func clear() -> void:
	_flags.clear()
	_vars.clear()


## [M27L L1] Flags and vars, for a save slot.
##
## ⚠️ **DELEGATES TO `snapshot()` RATHER THAN REPEATING IT.** A first draft of
## this returned the same two duplicated dictionaries verbatim, which is a second
## copy of one rule — exactly the drift `badge_count()` was extracted to avoid.
## The NAME earns its place (Bag/Wallet/RespawnPoint all expose `to_save`, so the
## slot writer can treat them uniformly); the BODY does not.
##
## Badges need no field of their own: `badge_count()` counts `BADGE_FLAGS` out of
## this store, so they persist here for free.
func to_save() -> Dictionary:
	return snapshot()


## ⚠️ **NOT `restore()`, AND THE DIFFERENCE IS THE WHOLE POINT.** `restore`
## duplicates whatever it is handed; this COERCES every value, because a save
## file can be hand-edited or shared and a var holding a String would otherwise
## reach `var_get`'s `int()` cast at some random later moment. Keys are
## deliberately NOT filtered — a flag this build does not know is harmless since
## nothing reads it, whereas dropping unknown keys would silently discard a newer
## save's progress on an older build.
func from_save(data: Dictionary) -> void:
	_flags = {}
	_vars = {}
	for k in data.get("flags", {}):
		_flags[str(k)] = bool(data["flags"][k])
	for k in data.get("vars", {}):
		_vars[str(k)] = int(data["vars"][k])
