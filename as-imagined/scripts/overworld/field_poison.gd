class_name FieldPoison
extends RefCounted

## [M27O O4] Poison damage while walking.
##
## ⚠️ **THIS IS THE GEN 4 RULE, AND IT IS NOT THIS PROJECT'S `GEN_LATEST`
## DEFAULT.** Rob's explicit call, and worth stating plainly because every other
## config in this project follows `GEN_LATEST` and a later session will
## reasonably assume this one does too.
##
## `OW_POISON_DAMAGE` (`include/config/overworld.h:9`) carries source's own
## comment: *"In Gen4, Pokémon no longer faint from Poison in the overworld. In
## Gen5+, they no longer take damage at all."* At `GEN_LATEST` the whole system
## is COMPILED OUT — `UpdatePoisonStepCounter` and its single call site both sit
## inside `#if OW_POISON_DAMAGE < GEN_5` (`field_control_avatar.c:761, 862`). So
## the *newest* behaviour is no field poison whatsoever, and the rule modelled
## here — damage while walking, stopping and curing at 1 HP — is reachable at
## exactly one value: `OW_POISON_DAMAGE == GEN_4`.
##
## ⚠️ **THE WHITEOUT BRANCH IS STRUCTURALLY UNREACHABLE HERE, AND THAT IS
## SOURCE, NOT A SIMPLIFICATION.** `Task_TryFieldPoisonWhiteOut` only whites out
## when `AllMonsFainted()` holds, and that function tests `HP == 0`
## (`field_poison.c:35-43`). At `>= GEN_4` nothing ever reaches 0 from poison,
## so the condition can never be true on this path. `EventScript_FieldPoison`'s
## own `goto_if_eq VAR_RESULT, FLDPSN_WHITEOUT` branch is dead code at this
## config. That is why O4 needs no faint hookup — not because one was skipped.
##
## Source: `DoPoisonFieldEffect` / `Task_TryFieldPoisonWhiteOut`
## (`src/field_poison.c`), driven by `UpdatePoisonStepCounter`
## (`src/field_control_avatar.c:863-886`).

## Every 4th step, from source's own `(*ptr)++; (*ptr) %= 4;`.
const STEP_INTERVAL := 4

## Source's own `VAR_POISON_STEP_COUNTER` (`include/constants/vars.h:63`). Kept
## as a real var rather than a plain field so it lives in `FlagStore` alongside
## every other persistent var — which also means it survives the scene swap a
## battle performs, for free.
const STEP_COUNTER_VAR := "VAR_POISON_STEP_COUNTER"

## Mirrors `FLDPSN_NONE` / `FLDPSN_PSN` / `FLDPSN_FNT`
## (`include/constants/field_poison.h`). The third name is source's own and is
## misleading at this config — nothing faints; it means "someone reached 1 HP",
## which is what makes the script run. Renamed here to say what it does.
const RESULT_NONE := 0
const RESULT_POISONED := 1
const RESULT_AT_ONE_HP := 2

## `gText_PkmnFainted_FldPsn` (`src/strings.c:662`) — the `>= GEN_4` variant.
## The `< GEN_4` build of this same symbol reads "{STR_VAR_1} fainted…", which
## is the string a faint-based port would have used.
const MESSAGE := "{STR_VAR_1} survived the poisoning.\nThe poison faded away!"


## Poison or toxic. Source keys on `GetAilmentFromStatus(...) == AILMENT_PSN`,
## which maps BOTH `STATUS1_POISON` and `STATUS1_TOXIC_POISON` onto one ailment
## (`party_menu.c:2231`) — so badly-poisoned mons tick at the same flat rate as
## ordinary ones out of battle, with no escalation. Deliberately not "worse for
## toxic": that escalation is a battle mechanic and source does not apply it here.
static func is_poisoned(mon: BattlePokemon) -> bool:
	if mon == null or mon.species == null:
		return false
	return mon.status == BattlePokemon.STATUS_POISON \
			or mon.status == BattlePokemon.STATUS_TOXIC


## Apply one tick of poison to the whole party.
##
## **A flat 1 HP, not a fraction** — source's own `--hp`, not a maxHP divisor.
## Floors at 1 and never faints, per the config note above.
##
## Returns `RESULT_AT_ONE_HP` if any poisoned mon is now sitting at exactly 1 HP
## (which is what makes the caller run the cure-and-announce step), else
## `RESULT_POISONED` if anything took damage, else `RESULT_NONE`.
##
## ⚠️ A FAINTED MON IS SKIPPED, WHICH SOURCE DOES NOT DO. `IsMonValidSpecies`
## checks the species only, so a 0-HP poisoned mon reaches source's `--hp` and
## underflows a `u32`. Unreachable in normal play (a faint clears status), but
## reproducing an underflow to be faithful to a bug would be the wrong kind of
## fidelity.
static func tick(party: BattleParty) -> int:
	if party == null:
		return RESULT_NONE
	var poisoned := 0
	var at_one := 0
	for mon: BattlePokemon in party.members:
		if not is_poisoned(mon) or mon.fainted or mon.current_hp <= 0:
			continue
		# Source: `if (hp == 1 || --hp == 1) numFainted++;` — the short-circuit
		# is load-bearing, so a mon ALREADY at 1 HP counts again every tick and
		# keeps re-announcing until something cures it. Reproduced exactly: the
		# cure below is what actually breaks that loop.
		if mon.current_hp == 1 or mon.current_hp - 1 == 1:
			at_one += 1
		mon.current_hp = maxi(1, mon.current_hp - 1)
		poisoned += 1
	if at_one > 0:
		return RESULT_AT_ONE_HP
	if poisoned > 0:
		return RESULT_POISONED
	return RESULT_NONE


## Cure every poisoned mon sitting at exactly 1 HP, and report which.
##
## Source: `MonFaintedFromPoison` selects them (valid species AND `HP == 1` at
## `>= GEN_4` AND ailment PSN) and `FaintFromFieldPoison` clears the status —
## the function's name is a leftover from the `< GEN_4` build, where it really
## did faint them. The friendship penalty in that same function is explicitly
## gated `if (OW_POISON_DAMAGE < GEN_4)`, so it does NOT apply here.
##
## One message per cured mon: source loops back to state 0 after each one
## (`Task_TryFieldPoisonWhiteOut`), so a party with three survivors prints three.
static func cure_at_one_hp(party: BattleParty) -> Array[BattlePokemon]:
	var cured: Array[BattlePokemon] = []
	if party == null:
		return cured
	for mon: BattlePokemon in party.members:
		if is_poisoned(mon) and mon.current_hp == 1 and not mon.fainted:
			mon.status = BattlePokemon.STATUS_NONE
			# Source assigns `STATUS1_NONE` wholesale, and the toxic counter
			# lives in the same field's own bits — so it goes with it.
			mon.toxic_counter = 0
			cured.append(mon)
	return cured


## Advance the counter and report whether this step is a tick.
##
## Kept separate from `tick` so the cadence is testable without a party and the
## damage is testable without a counter.
static func advance_counter(flags: FlagStore) -> bool:
	if flags == null:
		return false
	var n := (flags.var_get(STEP_COUNTER_VAR) + 1) % STEP_INTERVAL
	flags.var_set(STEP_COUNTER_VAR, n)
	return n == 0


## Source calls `ClearPoisonStepCounter()` at every battle entry
## (`battle_setup.c:262, 298, 986`), so the count restarts after a fight rather
## than carrying a partial step across it.
static func clear_counter(flags: FlagStore) -> void:
	if flags != null:
		flags.var_set(STEP_COUNTER_VAR, 0)
