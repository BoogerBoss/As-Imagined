class_name OverworldSession
extends RefCounted

## [M27D D5] The overworld state that must survive a battle.
##
## Starting a battle is a `change_scene_to_file`, which FREES the overworld —
## `MapManager`, every loaded chunk, the player's cell and facing, and (before
## this) the `FlagStore` D4 put on `overworld.gd` as an instance var. So the
## things that define "where you were" have to live outside the scene tree.
##
## Class-level statics, no autoload, matching `BattleSetupContext` — the same
## problem solved the same way, deliberately, rather than inventing a second
## mechanism for it.
##
## WHY A SCENE SWAP AND NOT AN OVERLAY. Keeping the overworld alive underneath
## the battle would avoid rebuilding it, and `[M25h-1.4]` set that precedent for
## the Bag screen. Two things argue the other way here: `battle_screen.tscn` is
## ~6,900 lines written to be a top-level scene, and — measured on Rob's machine
## — a chunk rebuild costs 66-100 ms, which SOURCE ITSELF hides behind a fade
## (`CB2_ReturnToFieldContinueScriptPlayMapMusic` fades in from the battle). So
## the rebuild is both affordable and authentic, and the overlay's cost is not.


## Persistent flags and vars: beaten trainers, hidden entities, trigger gates.
## Created once, never replaced, so a reference taken before a battle is still
## valid after one.
static var flags := FlagStore.new()

## [M27I I3] The player's bag. Static for the same reason `flags` is: a battle
## is a real scene swap, so anything held on the overworld scene would be
## discarded — and a bag that forgot itself every trainer fight is worse than
## no bag at all.
static var bag := Bag.new()

## [M27O O1] Where a whiteout sends the player. Static for the same reason the
## bag and the flags are — it must survive the scene swap a battle performs,
## and a respawn point forgotten by the fight that caused the whiteout would be
## worse than none.
static var respawn := RespawnPoint.new()

## [M27I I3b] Money and coins. Static for the same reason the bag is — a battle
## is a scene swap, and prize money that vanished with the fight that earned it
## would be worse than no wallet.
static var wallet := Wallet.new()

## [M27K K-b] Who the player is — name, gender, and the rival's name. Held here
## rather than on the overworld for the same reason the bag is: a battle is a
## real scene swap, and an identity that died with the field would be forgotten
## the first time you fought anything.
static var identity := PlayerIdentity.new()

## [M27O O3] `sWhiteOutBadgeMoney` (`battle_script_commands.c:315`), indexed by
## how many badges the player holds — nine entries for 0 through 8.
const WHITEOUT_BADGE_MONEY := [8, 16, 24, 36, 48, 64, 80, 100, 120]


## What a whiteout costs, at `B_WHITEOUT_MONEY = GEN_LATEST`: the badge-scaled
## rate times the player's highest party level, clamped to what they actually
## hold (source: `if (!IsEnoughMoney(..)) money = GetMoney()`).
##
## Returns the REAL amount that will be taken, not the amount asked for — the
## difference is the whole reason this is worth having in one place.
##
## ⚠️ **IT LIVES HERE, NOT ON `overworld.gd`, BECAUSE TWO DIFFERENT LAYERS NEED
## THE SAME ANSWER AND ONLY ONE OF THEM CAN SEE THE FIELD SCENE.**
## Source computes and deducts in one command — `getmoneyreward` is the first
## instruction of `BattleScript_LocalBattleLostPrintWhiteOut`
## (`data/battle_scripts_1.s:2915`), immediately before the three lines that
## narrate it. This project deliberately moved the DEDUCTION to the overworld's
## battle-return path (`[M27O O3]`), which left the NARRATION — printed by the
## battle screen, before it ever hands control back — needing a figure it had no
## way to compute: `scenes/overworld/overworld.gd` has no `class_name`, so
## neither the table nor the old method was reachable from `battle_screen_shared
## .gd` at all.
##
## The alternative was a second copy of the formula on the battle side, which is
## the two-hand-kept-copies drift this project already paid for once with
## `check_bake_diff`'s own normalisation rules — and it would fail in the
## nastiest possible way here, since only the CLAMP diverges: a screen with its
## own copy would happily print "You gave ¥2400 to the winner…" while the
## overworld took the ¥900 the player actually had.
##
## `OverworldSession` is the right owner because it already holds BOTH statics
## the formula reads — `flags` for the badge count, `wallet` for the clamp — so
## nothing has to be threaded in, and it is globally reachable exactly the way
## `BattleSetupContext` is.
static func whiteout_payout(highest_level: int) -> int:
	var badges: int = flags.badge_count()
	# Explicit `: int` — indexing an untyped Array yields Variant, which `:=`
	# cannot infer from. This project's own documented GDScript gotcha.
	var asked: int = int(WHITEOUT_BADGE_MONEY[mini(badges, WHITEOUT_BADGE_MONEY.size() - 1)]) \
			* maxi(1, highest_level)
	return mini(asked, wallet.money)

## [M27O O4] The player's party, held ACROSS battles rather than rebuilt for
## each one.
##
## ⚠️ **THIS CHANGED A REAL ASSUMPTION SEVERAL EARLIER ENTRIES WERE WRITTEN
## AGAINST.** Until now `OverworldParty.build_debug_player_party()` was called
## fresh at every battle, so every fight started at full health with no status —
## which is why `[M27O O2]`'s whiteout heal was "theatre", why `[M27O O3]`
## captured the party level at battle setup, and why field poison had nothing to
## act on. Persisting it is what makes O4 possible at all: a party that forgets
## its own poison the moment a battle ends can never be poisoned in the field.
##
## Still the DEBUG party — `[M27D D5]`'s hand-picked team. M27K's starter choice
## replaces it wholesale and M27L saves it; this only changes where it lives and
## how long it lives, not what it is.
##
## Held by REFERENCE and mutated in place by the battle, which is what carries HP
## and status back out. Source keeps the two separate — `gPlayerParty` holds the
## persistent facts and `gBattleMons` the battle-only ones, with a copy-back at
## the end — while this project conflates both into one `BattlePokemon`. So the
## copy-back's equivalent is a real clearing pass on the way out; see
## `BattleManager.restore_party_after_battle`, without which a +6 Swords Dance
## would follow the player into the next fight.
static var party: BattleParty = null


## The party, built on first use.
##
## Lazy rather than eager because `OverworldParty` reaches into `PokemonFactory`
## and the registries, and a static initialiser would run that at class-load
## time — before a test has had any chance to substitute one.
## ⚠️ **[M27L L5] BUILDS AN EMPTY PARTY, NOT `[M27D D5]`'s DEBUG TEAM.** Source's
## `NewGameInitData` calls `ZeroPlayerPartyMons()` (`new_game.c:155`): you start
## with nothing and Oak's script gives you the starter. This used to lazily build
## a 3-member debug team whenever the party was null, which meant **a brand new
## game arrived holding a team it was never given** — and that is what made
## `[M27K K-c]`'s starter-slot hazard reachable at all, since `givemon` appended
## at slot 3 while the script renamed slot 0.
##
## Still lazy, and still never null: every caller here treats "no party" as an
## empty party rather than a missing one, and a null would mean adding a check to
## all of them. `OverworldParty.build_debug_player_party()` survives for tests and
## debug boots that want a team — it is simply no longer the DEFAULT.
static func player_party() -> BattleParty:
	if party == null:
		party = BattleParty.new()
	return party


## Full restore: HP, status, PP. Source's `HealPlayerParty`, called by
## `DoWhiteOut` between the money loss and the warp.
##
## ⚠️ **NOW LOAD-BEARING, WHERE `[M27O O2]` COULD CORRECTLY CALL IT THEATRE.**
## With a persistent party a whiteout that did not heal would drop the player at
## the Centre with the same wiped team, and the next battle would start with a
## fainted lead — a soft-lock, not a lost fight.
static func heal_party() -> void:
	if party == null:
		return
	for mon: BattlePokemon in party.members:
		mon.current_hp = mon.max_hp
		mon.status = BattlePokemon.STATUS_NONE
		mon.toxic_counter = 0
		mon.fainted = false
		for i in range(mon.current_pp.size()):
			if i < mon.moves.size() and mon.moves[i] != null:
				mon.current_pp[i] = int(mon.moves[i].pp)
	party.active_indices = [0]


## [Bugfix, rolled in while implementing "don't whiteout and heal"] Source:
## `DowngradeBadPoison` (`battle_setup.c:633`), called at the end of every
## trainer battle that does NOT whiteout (won, already-beaten, or a
## heal-after loss) — never on a real whiteout, which heals everything via
## `heal_party()` and makes the distinction moot anyway. At this project's
## `GEN_LATEST` config source's own gate (`B_TOXIC_REVERSAL < GEN_5: return`)
## never fires, so the downgrade always applies.
##
## Toxic poison resets to plain poison the moment you leave a battle with it
## still active — `toxic_counter` resets alongside it, since that counter is
## meaningless for plain poison (it exists to escalate TOXIC's own damage).
static func downgrade_bad_poison() -> void:
	if party == null:
		return
	for mon: BattlePokemon in party.members:
		if mon.status == BattlePokemon.STATUS_TOXIC:
			mon.status = BattlePokemon.STATUS_POISON
			mon.toxic_counter = 0


## [M27E E1b] Is the player on the water?
##
## ⚠️ **STATIC, AND THIS ONE IS NOT OPTIONAL.** A wild encounter can start while
## surfing — `water_mons` is imported for 98 Kanto maps — and a battle is a real
## scene swap. Held on the overworld, this would clear itself the first time
## something attacked, dumping the player onto the water on foot, standing on a
## tile the step resolver refuses in every direction. That is the soft-lock
## `[M27C]`'s own start_cell guard exists to avoid, arrived at from a new angle.
static var surfing: bool = false


## [M27L L4] Which save slot this playthrough belongs to.
##
## ⚠️ Static, and it has to be: a battle is a real scene swap, so a slot held on
## the overworld would be forgotten by the first trainer fought — and the next
## SAVE would then write to slot 0 regardless of which one the player chose.
## Replaces `Overworld.active_slot`, which was L2's stated stand-in.
static var active_slot: int = 0

## [M27L L4] The overworld should run Oak's speech as soon as it loads.
##
## ⚠️ A one-shot CONSUMED on read, the same shape as `pending_return`. A flag
## that stayed set would re-run the new game every time the overworld rebuilt —
## which is every single battle.
static var pending_new_game: bool = false


static func take_new_game() -> bool:
	var v := pending_new_game
	pending_new_game = false
	return v


## [Quick Start] Set alongside `pending_new_game` when the whole Oak's-speech/
## naming/gender/rival-naming cutscene should be skipped — a brand new game
## that still spawns in the bedroom (`pending_new_game` still decides that),
## just without the talking-heads sequence in front of it. One-shot, same
## shape as `pending_new_game` itself, consumed by `overworld.gd`'s own
## `_ready()` in the same breath as `take_new_game()` so it can never survive
## into a later battle-triggered rebuild and skip a SECOND, real new game.
static var pending_new_game_skip_intro: bool = false


static func take_new_game_skip_intro() -> bool:
	var v := pending_new_game_skip_intro
	pending_new_game_skip_intro = false
	return v


## [M27L L2] Seconds of play in THIS playthrough.
##
## ⚠️ Static for the same reason the bag is — a battle is a real scene swap, and
## a counter living on the overworld would reset every fight, so the CONTINUE
## card would report the time since the last battle rather than the playthrough.
##
## ⚠️ Accumulated as a FLOAT and reported as an int. Ticking `+= delta` into an
## int truncates every frame, which at 60 fps loses most of an hour per hour —
## the kind of drift that looks like a working counter.
static var playtime: float = 0.0


static func tick_playtime(delta: float) -> void:
	playtime += maxf(0.0, delta)


## ⚠️ **TRUNCATES, AND MUST KEEP TRUNCATING.** Verified against the wall clock in
## the real scene (2.001 s elapsed -> 1.998 s counted over 290 frames, and it
## keeps counting with a menu open). The one artifact: summing 3600 ticks of
## exactly 1.0/60.0 lands on 59.999999999999986, so this reports **59, not 60**.
##
## That is float accumulation, not a counter bug, and truncation is the RIGHT
## semantics — "whole seconds played" should never claim a second the player has
## not finished. Do NOT "fix" it with `round()`: that would over-report by up to
## half a second at every read, which is a worse answer than under-reporting by
## microseconds. The error is bounded below one second in total and the card
## displays H:MM, so it is invisible where it is actually shown.
static func playtime_seconds() -> int:
	return int(playtime)


## Where to put the player when the overworld next loads, or empty for "use the
## scene's own start_map". Written when a battle starts, consumed on return.
static var pending_return: Dictionary = {}

## The result of the battle just fought, or null. Consumed by the overworld on
## return so the win/loss consequences are applied exactly once.
static var pending_result: BattleOutcome = null

## Which trainer the pending battle is against. Held here rather than widening
## battle_screen_shared's own state: the overworld already knows, and the battle
## screen has no reason to learn.
static var pending_trainer_key: String = ""


## Record where the player is standing, before a battle frees the overworld.
static func save_position(map_name: String, cell: Vector2i, facing: int,
		elevation: int, trainer_key: String = "") -> void:
	pending_trainer_key = trainer_key
	pending_return = {
		"map": map_name,
		"cell": cell,
		"facing": facing,
		"elevation": elevation,
	}


static func has_pending_return() -> bool:
	return not pending_return.is_empty()


## Take the saved position and clear it, so a later boot does not silently
## resume a stale one. Same consume-on-read shape as `BattleSetupContext`.
static func take_return() -> Dictionary:
	var r := pending_return.duplicate()
	pending_return = {}
	return r


static func set_result(r: BattleOutcome) -> void:
	pending_result = r


static func take_result() -> BattleOutcome:
	var r := pending_result
	pending_result = null
	return r


## The battle screens, loaded once and HELD.
##
## Same mechanism as MapManager's tileset preload: holding the reference is what
## guarantees residence, since a cache entry with no live reference can be
## evicted. Without this the first battle of a session pays the full scene parse
## plus every texture decode, which is exactly what "the first trainer takes a
## while, the rest are near instant" describes.
static var _battle_scenes: Dictionary = {}


static func preload_battle_scenes() -> int:
	for variant in ["singles", "doubles"]:
		var path := "res://scenes/battle/battle_screen_%s.tscn" % variant
		if _battle_scenes.has(variant) or not ResourceLoader.exists(path):
			continue
		_battle_scenes[variant] = load(path)
	return _battle_scenes.size()


static func battle_scene(is_doubles: bool) -> PackedScene:
	var key := "doubles" if is_doubles else "singles"
	if not _battle_scenes.has(key):
		preload_battle_scenes()
	return _battle_scenes.get(key, null) as PackedScene


## Tests only. Production never wants this — the flags ARE the save.
##
## ⚠️ **EVERY PIECE OF SESSION STATE, NOT MOST OF THEM.** This used to reset 5
## of 8 and leave `bag`/`wallet`/`respawn` standing, which leaks across tests AND
## across suites in one process — and since the only callers are tests, "give me
## a clean session" is the whole contract, so a partial reset was simply wrong.
##
## Found the expensive way during `[M27I I5-3a]`: a section added 2 Potions after
## calling this, then removed 2, and was left holding 1 from an earlier section
## — the assertion failed for a reason that had nothing to do with the code under
## test. Anything added here later must be reset here too; the cost of forgetting
## is a test that fails somewhere else.
static func reset() -> void:
	flags = FlagStore.new()
	party = null
	bag = Bag.new()
	wallet = Wallet.new()
	respawn = RespawnPoint.new()
	identity = PlayerIdentity.new()
	TextBuffers.identity = identity
	playtime = 0.0
	active_slot = 0
	surfing = false
	pending_new_game = false
	pending_new_game_skip_intro = false
	pending_return = {}
	pending_result = null
	pending_trainer_key = ""
	ObjectEventState.clear()
