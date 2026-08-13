extends Node

## [M27H H4/H5] Catching and fleeing — the process, not the animation.
##
## The animation is M26B7, separately scoped and unbuilt. What this covers is the
## formula, the shake count it hands B7, and what happens to the Pokémon after.
##
## The claims most worth pinning:
##
##   * the badge malus is a LOOP, not one multiply — it bites once per missing
##     badge whose level threshold the target exceeds;
##   * a full party REFUSES BEFORE the roll, so a ball never wobbles and then
##     loses the Pokémon anyway;
##   * a catch is NOT a win — CAUGHT is its own outcome, and conflating them
##     would pay prize money and could set a defeated-trainer flag.

const EXPECTED_TOTAL := 66

var _total := 0
var _failed := 0
var _gated := 0


func _chk(label: String, cond: bool) -> void:
	_total += 1
	if not cond:
		_failed += 1
		print("FAILED: %s" % label)


func _rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


## A wild-shaped target with a known catch rate.
func _target(catch_rate: int, level: int, hp_fraction: float = 1.0) -> BattlePokemon:
	var m := PokemonFactory.create_battle_pokemon(10, level)  # Caterpie
	m.species.catch_rate = catch_rate
	m.current_hp = maxi(1, int(m.max_hp * hp_fraction))
	return m


func _ball() -> ItemData:
	var i := ItemRegistry.get_item(1)
	if i == null:
		i = ItemData.new()
		i.item_id = 1
	return i


func _ready() -> void:
	_test_odds()
	_test_shakes()
	_test_refusal()
	_test_outcome()
	_test_wiring()
	_test_fleeing()
	_test_a_forfeited_action_costs_the_turn()
	# ⚠️ AWAITED. This one suspends (it awaits the real `_on_run_pressed`, which
	# now awaits its own message drain), so calling it bare would let `_ready`
	# race ahead to Z.99 and count its four assertions as missing.
	await _test_flee_message()

	var accounted := _total + _gated
	_chk("Z.99 every expected assertion ran (%d + %d gated == %d)"
			% [_total, _gated, EXPECTED_TOTAL], accounted == EXPECTED_TOTAL)
	print("m27h_catching_test: %d/%d passed" % [_total - _failed, _total])
	get_tree().quit()


## --- A. the odds formula ---
func _test_odds() -> void:
	var ball := _ball()
	# A healthy, high-catch-rate target on full HP.
	var full := _target(255, 20, 1.0)
	var hurt := _target(255, 20, 0.1)
	var o_full := ItemManager.compute_capture_odds(full, ball, 8, 20)
	var o_hurt := ItemManager.compute_capture_odds(hurt, ball, 8, 20)
	# ⚠️ `maxHP*3 - hp*2` — lower HP is strictly better, and it is the FIRST
	# term, so getting it inverted would make full-health mons easiest to catch.
	_chk("A.01 a hurt target is easier than a healthy one", o_hurt > o_full)
	_chk("A.02 and both are positive", o_full > 0 and o_hurt > 0)

	# Catch rate scales it directly.
	var rare := _target(3, 20, 1.0)
	_chk("A.03 a low catch rate is much harder",
			ItemManager.compute_capture_odds(rare, ball, 8, 20) < o_full)

	# ⚠️ TWO DIFFERENT STATUS BONUSES, and they are mutually exclusive.
	var asleep := _target(255, 20, 1.0)
	asleep.status = BattlePokemon.STATUS_SLEEP
	var poisoned := _target(255, 20, 1.0)
	poisoned.status = BattlePokemon.STATUS_POISON
	var o_sleep := ItemManager.compute_capture_odds(asleep, ball, 8, 20)
	var o_psn := ItemManager.compute_capture_odds(poisoned, ball, 8, 20)
	_chk("A.04 sleep helps more than poison", o_sleep > o_psn)
	_chk("A.05 and poison helps more than nothing", o_psn > o_full)
	# 2.5x vs 1.5x at this project's GEN_LATEST config, not 2x vs 1.5x.
	_chk("A.06 sleep is x2.5, not the pre-Gen-5 x2",
			o_sleep == o_full * 25 / 10)

	# ⚠️ THE BADGE MALUS IS A LOOP. A level-50 target on zero badges crosses
	# several thresholds and is penalised once per crossing.
	var high := _target(255, 50, 1.0)
	var o_8 := ItemManager.compute_capture_odds(high, ball, 8, 50)
	var o_0 := ItemManager.compute_capture_odds(high, ball, 0, 50)
	var o_4 := ItemManager.compute_capture_odds(high, ball, 4, 50)
	_chk("A.07 fewer badges makes it harder", o_0 < o_8)
	_chk("A.08 and it is a LOOP — 0 badges is worse than 4, not equal",
			o_0 < o_4 and o_4 < o_8)

	# ⚠️ THE GEN 9 LOW-LEVEL BONUS IS EXACTLY x1.0 AT LEVEL 13, so 13, 14 and 20
	# all give the same odds — measured: 15 each, against 24 at level 10. The
	# bonus `(36 - 2L)/10` only HELPS below 13; 13 is its neutral boundary, not
	# its last helpful level. A first draft asserted level 13 beat level 14 and
	# was simply wrong about the formula.
	#
	# HP is pinned identical across the three so only the level differs —
	# otherwise level changes maxHP too and the comparison measures both.
	var l10 := _target(45, 10, 1.0)
	var l13 := _target(45, 13, 1.0)
	var l14 := _target(45, 14, 1.0)
	for m in [l10, l13, l14]:
		m.max_hp = 100
		m.current_hp = 100
	_chk("A.09 a level-10 target gets a real low-level bonus",
			ItemManager.compute_capture_odds(l10, ball, 8, 20)
			> ItemManager.compute_capture_odds(l13, ball, 8, 20))
	_chk("A.10 but level 13 is the NEUTRAL boundary, not the last helpful level",
			ItemManager.compute_capture_odds(l13, ball, 8, 20)
			== ItemManager.compute_capture_odds(l14, ball, 8, 20))

	_chk("A.11 a null target is 0, not a crash",
			ItemManager.compute_capture_odds(null, ball, 8, 20) == 0)


## --- B. shakes ---
func _test_shakes() -> void:
	var ball := _ball()
	# ⚠️ THE SHAKE COUNT IS FOR M26B7. 0-2 is a break-free, 3 is a capture, and
	# emitting it now means the animation has nothing to retrofit.
	var easy := _target(255, 5, 0.05)
	easy.status = BattlePokemon.STATUS_SLEEP
	var r := ItemManager.attempt_catch(easy, ball, 8, 20, _rng(1))
	_chk("B.01 the result reports shakes as well as caught",
			r.has("caught") and r.has("shakes") and r.has("odds"))
	_chk("B.02 an easy target is caught", bool(r["caught"]))
	_chk("B.03 and a capture is exactly 3 shakes", int(r["shakes"]) == 3)

	# ⚠️ A CATCH RATE OF 1 GIVES ODDS OF EXACTLY 0, AT ANY HP — integer
	# truncation, since `odds * 1 / (maxHP*3)` can never reach 1 when the
	# numerator is at most `maxHP*3`. Mathematically uncatchable with a plain
	# Poké Ball, which is source's behaviour and not a degenerate case to guard.
	var impossible := _target(1, 60, 0.05)
	impossible.max_hp = 100
	impossible.current_hp = 5
	_chk("B.04 a catch-rate-1 target has literally zero odds, even at 5%% HP",
			ItemManager.compute_capture_odds(impossible, ball, 0, 20) == 0)

	# A genuinely difficult but POSSIBLE target: the shake count must still vary,
	# or the animation has nothing to show on a near miss.
	var hard := _target(45, 20, 0.5)
	hard.max_hp = 100
	hard.current_hp = 50
	var shakes_seen := {}
	for i in range(300):
		var res := ItemManager.attempt_catch(hard, ball, 0, 20, _rng(i))
		shakes_seen[int(res["shakes"])] = true
	_chk("B.05 a hard-but-possible target produces varying shake counts",
			shakes_seen.size() >= 2)

	# ⚠️ odds > 254 is an outright capture with no rolls at all.
	_chk("B.06 the shake threshold rises with the odds",
			ItemManager.shake_threshold(200) > ItemManager.shake_threshold(20))
	_chk("B.07 and zero odds is a zero threshold, not a divide by zero",
			ItemManager.shake_threshold(0) == 0)

	# Determinism: the same seed gives the same answer, which is what makes
	# every assertion above reproducible.
	var a := ItemManager.attempt_catch(hard, ball, 0, 20, _rng(42))
	var b := ItemManager.attempt_catch(hard, ball, 0, 20, _rng(42))
	_chk("B.08 the same seed gives the same throw", a["shakes"] == b["shakes"])


## --- C. refusal on a full party ---
func _test_refusal() -> void:
	_chk("C.01 PARTY_SIZE is source's own 6", BattleParty.PARTY_SIZE == 6)
	var bm := BattleManager.new()
	_chk("C.02 a battle allows catching by default", bm.party_has_room)
	_chk("C.03 and holds no caught Pokémon", bm.caught_pokemon == null)
	_chk("C.04 badge count defaults to 0", bm.badge_count == 0)
	bm.free()

	# ⚠️ REFUSAL IS BEFORE THE ROLL — Rob's decision, and source's own behaviour
	# with no PC. A ball must never wobble and then lose the Pokémon anyway,
	# which is what refusing at the party-join step would look like.
	_chk("C.05 the context carries party room", "party_has_room" in BattleSetupContext)
	_chk("C.06 and the badge count", "badge_count" in BattleSetupContext)


## --- D. a catch is not a win ---
func _test_outcome() -> void:
	var mon := _target(255, 5, 1.0)
	var o := BattleOutcome.make(BattleOutcome.CAUGHT, "", 0, 5, mon)
	_chk("D.01 the outcome carries the caught Pokémon", o.caught_pokemon == mon)
	# ⚠️ CAUGHT IS NEITHER A WIN NOR A DEFEAT. Conflating it with WON would pay
	# prize money and could set a defeated-trainer flag.
	_chk("D.02 a catch is not a defeat", not o.player_defeated())
	_chk("D.03 nor does it set a defeated-trainer flag",
			not o.should_set_defeated_flag())
	_chk("D.04 and it is a distinct outcome from WON",
			BattleOutcome.CAUGHT != BattleOutcome.WON)
	_chk("D.05 an ordinary outcome carries no Pokémon",
			BattleOutcome.make(BattleOutcome.WON, "T").caught_pokemon == null)

	# --- [M27H H4 fix] the caught Pokémon has to be USABLE ---
	#
	# ⚠️ **REPORTED FROM PLAY: "I can't use any Pokémon I catch — they join the
	# party fainted".** The catch ends the battle by fainting the opponent (this
	# project's stand-in for source's `FinalizeCapture`, which REMOVES the
	# battler outright), and `BattlePokemon` is `RefCounted` — so
	# `caught_pokemon` is that same zeroed object, not a copy. Nothing here
	# asserted its state, which is exactly how it shipped.
	var bm := BattleManager.new()
	var wild := _target(255, 8, 1.0)
	wild.current_hp = 7
	wild.status = BattlePokemon.STATUS_SLEEP
	wild.stat_stages[BattlePokemon.STAT_ATK] = 2
	wild.confusion_turns = 3
	bm.caught_pokemon = wild
	bm.caught_hp = wild.current_hp
	# The battle-ending mutation the catch site performs, reproduced exactly.
	wild.current_hp = 0
	wild.fainted = true

	var got: BattlePokemon = bm.take_caught_pokemon()
	_chk("D.06 the caught Pokémon is handed over ALIVE, not fainted",
			got != null and not got.fainted and got.current_hp > 0)
	_chk("D.07 with the HP it actually had when the ball landed",
			got.current_hp == 7)
	# ⚠️ KEPT, not cured — source's capture cures nothing, and a Pokémon caught
	# asleep stays asleep. The discriminator that separates "restores it" from
	# "heals it".
	_chk("D.08 keeping its status — a capture is not a heal",
			got.status == BattlePokemon.STATUS_SLEEP)
	# ⚠️ The half that is easy to miss: the caught mon is appended AFTER
	# `restore_party_after_battle` has already cleaned the player's party, so
	# nothing else would ever strip its battle state.
	_chk("D.09 and its battle-only state stripped, since nothing else will",
			got.stat_stages[BattlePokemon.STAT_ATK] == 0
			and got.confusion_turns == 0)
	bm.free()


## --- E. wiring ---
func _test_wiring() -> void:
	# The ball must be throwable at all — without it the formula is unreachable.
	# ⚠️ **`_ITEMS` WAS RENAMED TO `_DEBUG_STOCK` AND THIS SUITE STOPPED
	# LOADING ENTIRELY — IT DID NOT FAIL, IT HUNG.** A GDScript parse error
	# means the script never loads, so nothing reaches `quit()` and the scene
	# sits until the harness timeout kills it. That is why this was recorded
	# for days as "a pre-existing hang" rather than as a broken reference:
	# the symptom of a stale name and the symptom of an infinite loop are
	# identical from outside.
	#
	# ⚠️ Renamed by `02bc4926` ("Polished lower battle text field") — the SAME
	# commit that left `m25h1_bottom_region_test`'s `ActionRegion` assertion
	# stale. One commit, two silently-broken battle suites, both misattributed
	# as pre-existing conditions. The common cause is that the battle suites
	# are not in the routine overworld sweep.
	var found := false
	for entry in ItemSelectScreen._DEBUG_STOCK:
		if int(entry.get("id", 0)) == 1:
			found = true
	_chk("E.01 a Poké Ball is throwable in battle", found)
	var ball := ItemRegistry.get_item(1)
	_chk("E.02 and the item resolves", ball != null)
	if ball == null:
		_gated += 1
	else:
		_chk("E.03 as a throw-ball item",
				ball.battle_usage == ItemManager.BATTLE_USE_THROW_BALL)

	var ow: Node2D = load("res://scenes/overworld/overworld.tscn").instantiate() as Node2D
	# Deliberately NOT added to the tree — _ready() would boot the whole region.
	_chk("E.04 the overworld counts badges in one place", ow.has_method("badge_count"))
	ow.free()

	var bs: Control = load("res://scenes/battle/battle_screen_singles.tscn").instantiate() as Control
	_chk("E.05 the battle screen reports a caught Pokémon", bs.has_method("caught_pokemon"))

	# --- [M27H H4 follow-up] the ACCESSOR, not just the function behind it ---
	#
	# ⚠️ **THE H4 FIX BUILT `take_caught_pokemon()` AND THEN DID NOT CALL IT.**
	# `caught_pokemon()` kept returning the raw field, so the restore never ran
	# for the one caller that matters and caught Pokémon still joined the party
	# fainted — reported from play a second time. D.06-D.09 all passed
	# throughout, because they call `take_caught_pokemon()` DIRECTLY and never
	# go through the accessor the overworld actually uses.
	#
	# ⚠️ Deliberately NOT added to the tree, so `_bm` (an `@onready`) is null and
	# is assigned by hand — the same bare-instance shape E.04 uses above.
	var bm2 := BattleManager.new()
	var caught := _target(255, 8, 1.0)
	caught.current_hp = 7
	caught.status = BattlePokemon.STATUS_SLEEP
	caught.stat_stages[BattlePokemon.STAT_ATK] = 2
	bm2.caught_pokemon = caught
	bm2.caught_hp = caught.current_hp
	caught.current_hp = 0
	caught.fainted = true
	bs._bm = bm2

	var handed: BattlePokemon = bs.caught_pokemon()
	_chk("E.05b the ACCESSOR hands over a usable Pokémon, not the raw corpse",
			handed != null and not handed.fainted and handed.current_hp == 7)
	_chk("E.05c still keeping its status, so the accessor restores and never heals",
			handed.status == BattlePokemon.STATUS_SLEEP)
	_chk("E.05d and strips the battle-only state, since nothing downstream will",
			handed.stat_stages[BattlePokemon.STAT_ATK] == 0)
	# The degrade path the accessor has always had, kept honest by the change.
	bs._bm = null
	_chk("E.05e and reports nothing when there is no battle behind it",
			bs.caught_pokemon() == null)
	bm2.free()
	bs.free()

	# A caught Pokémon joins a party that has room, and the party is the SAME
	# persistent one `[M27O O4]` introduced — not a copy.
	OverworldSession.reset()
	var party := OverworldSession.player_party()
	var before := party.members.size()
	_chk("E.06 the debug party starts with room", before < BattleParty.PARTY_SIZE)
	party.members.append(_target(255, 5, 1.0))
	_chk("E.07 and appending is what joining looks like",
			OverworldSession.player_party().members.size() == before + 1)
	OverworldSession.reset()


## --- F. fleeing [M27H H5] ---
func _test_fleeing() -> void:
	var bm := BattleManager.new()
	var me := _target(45, 20, 1.0)
	var foe := _target(45, 20, 1.0)

	# ⚠️ A TRAINER BATTLE CAN NEVER BE FLED, and this is the reason [M25b]'s
	# always-succeeds Run placeholder could not simply be repointed — the same
	# button serves both, and source refuses a normal trainer battle outright.
	bm.is_wild_battle = false
	_chk("F.01 a trainer battle refuses every escape",
			not bm.try_flee(me, foe, _rng(1)))
	_chk("F.02 and does not even count the attempt", bm.run_tries == 0)

	bm.is_wild_battle = true
	# ⚠️ EQUAL SPEED SUCCEEDS. Source's roll is gated on `speed < opponent`, so
	# a naive `>` would make same-speed encounters roll for no reason.
	me.speed = 50
	foe.speed = 50
	_chk("F.03 equal speed escapes outright", bm.try_flee(me, foe, _rng(1)))
	me.speed = 80
	_chk("F.04 and so does being faster", bm.try_flee(me, foe, _rng(1)))

	# Slower rolls, and repeated attempts get likelier — which is what stops a
	# slow Pokémon being trapped indefinitely by bad luck.
	var slow_bm := BattleManager.new()
	slow_bm.is_wild_battle = true
	# ⚠️ A MILD RATIO, DELIBERATELY. A first draft used 5-vs-200, which gives
	# `5*128/200 = 3` — a 3/256 chance, so 0 successes in 200 trials is ~10%
	# likely and the "sometimes succeeds" assertion flaked. 50-vs-100 gives 64,
	# i.e. 25%, which discriminates reliably in both directions.
	me.speed = 50
	foe.speed = 100
	var first_round := 0
	for i in range(200):
		var b2 := BattleManager.new()
		b2.is_wild_battle = true
		if b2.try_flee(me, foe, _rng(i)):
			first_round += 1
		b2.free()
	_chk("F.05 a much slower mon often fails on the first try (%d/200)" % first_round,
			first_round < 200)
	_chk("F.06 but sometimes succeeds", first_round > 0)

	# run_tries accumulates and makes it likelier.
	slow_bm.run_tries = 8
	var later_round := 0
	for i in range(200):
		var b3 := BattleManager.new()
		b3.is_wild_battle = true
		b3.run_tries = 8
		if b3.try_flee(me, foe, _rng(i)):
			later_round += 1
		b3.free()
	_chk("F.07 and repeated attempts get likelier (%d vs %d)"
			% [later_round, first_round], later_round > first_round)
	_chk("F.08 each attempt is counted", slow_bm.run_tries == 8)
	slow_bm.free()

	# ⚠️ Smoke Ball shipped DATA-ONLY in [M24b] with a note that no flee
	# mechanic existed to consume it. This is that mechanic.
	var smoke_bm := BattleManager.new()
	smoke_bm.is_wild_battle = true
	var holder := _target(45, 20, 1.0)
	holder.speed = 1
	foe.speed = 999
	var smoke := ItemRegistry.get_item(PokemonRegistry.item_id_of("ITEM_SMOKE_BALL"))
	if smoke == null:
		_gated += 1
	else:
		holder.held_item = smoke
		_chk("F.09 Smoke Ball always escapes, however slow",
				smoke_bm.try_flee(holder, foe, _rng(3)))
	smoke_bm.free()

	# A Ghost always escapes — the same rule that exempts them from trapping.
	var ghost_bm := BattleManager.new()
	ghost_bm.is_wild_battle = true
	var ghost := _target(45, 20, 1.0)
	ghost.speed = 1
	ghost.species.types = [TypeChart.TYPE_GHOST, TypeChart.TYPE_GHOST]
	_chk("F.10 a Ghost always escapes", ghost_bm.try_flee(ghost, foe, _rng(3)))
	ghost_bm.free()

	var reported: Array = []
	bm.flee_attempted.connect(func(b, ok): reported.append(ok))
	bm.try_flee(me, foe, _rng(1))
	_chk("F.11 every attempt is reported for the log", reported.size() == 1)
	bm.free()


## --- G. the flee message reaches the box ---
func _test_flee_message() -> void:
	# ⚠️ **GATED ON THE BATTLE SCREEN BEING LOADABLE AT ALL, which is not a
	# formality here.** `battle_screen_shared.gd` depends on `AnimBehaviors`, and
	# a parse error anywhere in that file makes this whole scene fail to
	# instantiate — so an unrelated in-flight edit to the battle-animation layer
	# would otherwise turn these four assertions into a phantom failure in the
	# CATCHING suite, pointing at the wrong author and the wrong file. Counted
	# into `_gated` so `Z.99`'s arithmetic still balances, which is the same
	# shape `m27a_step_resolver_test` uses when `map_scripts.json` is absent.
	var packed: PackedScene = load("res://scenes/battle/battle_screen_singles.tscn")
	var bs: Control = packed.instantiate() as Control if packed != null else null
	if bs == null:
		print("m27h_catching_test: G.01-G.04 GATED — battle screen would not "
				+ "instantiate (a dependency of battle_screen_shared.gd does not "
				+ "parse); the flee-message assertions did not run")
		_gated += 4
		return
	bs.overlay_mode = true

	# ⚠️ A REAL battle, not a bare manager. `_on_run_pressed` reads
	# `get_active_player_mon()`/`get_active_opponent_mon()`, and on a manager with
	# no parties both answer null — `try_flee(null, null)` then fails and the
	# code silently takes the FAILURE branch, so G.02 would be pinning the wrong
	# arm of the very `if` it exists to test.
	var bm := BattleManager.new()
	add_child(bm)
	var me := _target(45, 20, 1.0)
	var foe := _target(45, 20, 1.0)
	bm.start_battle(me, foe)
	# ⚠️ AFTER `start_battle`, not before: switch-in runs `_reset_mon_stats`,
	# which restores `original_speed` over anything assigned earlier — the same
	# restore that once silently undid a mid-battle level-up. Setting it first
	# left both mons at their real speeds, the escape roll then failed, and the
	# test was quietly pinning the FAILURE branch.
	me.speed = 200
	foe.speed = 1
	bm.is_wild_battle = true
	bs._bm = bm
	# ⚠️ `_return_to_overworld_if_pending` short-circuits on `_is_autoplay_run`,
	# and this suite runs under `--autoplay` — so without clearing it the emit
	# path never executes and G.02 would be testing the harness, not the fix.
	# Safe: the drain still bypasses via `not is_inside_tree()`, which is the
	# behaviour G.01 is actually pinning.
	bs._is_autoplay_run = false

	var outcomes: Array[int] = []
	bs.battle_finished.connect(func(o: int) -> void: outcomes.append(o))

	# A guaranteed escape: far faster, so `try_flee` succeeds outright.
	bs._pending_beats.clear()
	await bs._on_run_pressed()
	_chk("G.01 a successful escape hands its beats to the drain rather than "
			+ "leaving them queued for a screen that is about to be freed",
			bs._pending_beats.is_empty())
	# ⚠️ The diagnostic names the setup, because every way this assertion can
	# fail spuriously is a setup problem that looks identical from outside: a
	# null active mon, a non-wild manager, or a restored speed all just take the
	# FAILURE branch silently.
	_chk("G.02 and still reports RAN, so the drain did not swallow the outcome "
			+ "(got %s; wild=%s actives=%s/%s)"
			% [str(outcomes), str(bm.is_wild_battle),
			str(bm.get_active_player_mon() != null),
			str(bm.get_active_opponent_mon() != null)],
			outcomes.size() == 1 and outcomes[0] == BattleOutcome.RAN)

	# ⚠️ THE TRAINER REFUSAL HAD THE IDENTICAL BUG and was the least visible of
	# the three: nothing drains between the press and the player's next action,
	# so source's own "No! There's no running from a Trainer battle!" never
	# appeared and the button looked inert.
	var bm2 := BattleManager.new()
	add_child(bm2)
	bm2.start_battle(_target(45, 20, 1.0), _target(45, 20, 1.0))
	bm2.is_wild_battle = false
	bs._bm = bm2
	outcomes.clear()
	bs._pending_beats.clear()
	await bs._on_run_pressed()
	_chk("G.03 the trainer refusal is drained too", bs._pending_beats.is_empty())
	_chk("G.04 and produces no outcome — the battle continues untouched",
			outcomes.is_empty())

	bs._bm = null
	bm.queue_free()
	bm2.queue_free()
	bs.free()


# ── H. A failed escape spends the turn ──────────────────────────────────────
#
# ⚠️ **CLOSES A GAP `[M27H H5]` SHIPPED AND DISCLOSED**: "source SPENDS the turn
# on a failed escape ... which makes fleeing free, only slower", recorded as
# needing "a real skip-turn action in the TURN MACHINE, not in the escape code".
#
# Source models running as a real turn ACTION. `HandleAction_Run`
# (`battle_util.c:638`) rolls, and on failure prints the can't-escape string,
# sets `gCurrentActionFuncId = B_ACTION_EXEC_SCRIPT` and lets the turn carry on
# — so the opponent still attacks. Before this, the player simply picked again
# and the opponent never got a move for the attempt.
#
# Derived from the NEGATION rather than the truth: the wrong version is "the
# forfeiting battler does nothing", which is ALSO true of the fixed version. The
# claim that separates them is that the OPPONENT still acts, so that is what
# G.02 asserts and what injection removes.
func _test_a_forfeited_action_costs_the_turn() -> void:
	var me := _target(45, 20, 1.0)
	var foe := _target(45, 20, 1.0)

	# Snapshot the FIRST turn through signals rather than reading post-battle
	# state: `start_battle` runs the battle to completion, and with one move
	# apiece auto-select keeps re-picking it, so anything read afterwards
	# describes some later turn. This project's own standing convention.
	var skipped: Array = []
	var actors: Array = []
	var bm := BattleManager.new()
	bm.is_wild_battle = true
	bm.move_skipped.connect(func(mon: BattlePokemon, reason: String) -> void:
		skipped.append([mon, reason]))
	bm.move_executed.connect(func(attacker: BattlePokemon, _d: BattlePokemon,
			_m: MoveData, _dmg: int) -> void:
		actors.append(attacker))

	bm.queue_forfeit_for(0)
	bm.start_battle(me, foe)

	var first_skip_reason: String = str(skipped[0][1]) if not skipped.is_empty() else ""
	var first_skip_mon = skipped[0][0] if not skipped.is_empty() else null
	_chk("H.01 the forfeiting battler is skipped, and says why",
			first_skip_mon == me and first_skip_reason == "forfeited")

	# THE GUARD. Before the fix the turn never resolved at all, so the opponent
	# had no chance to act — which is exactly what made fleeing free.
	_chk("H.02 the opponent still gets its move on the forfeited turn",
			not actors.is_empty() and actors[0] == foe)
	_chk("H.03 and the forfeiting battler is not the one who acted first",
			actors.is_empty() or actors[0] != me)

	# Discriminator: the same fixture WITHOUT a forfeit must let the player act,
	# or G.02/G.03 would pass against a build that simply never lets `me` move.
	var actors2: Array = []
	var bm2 := BattleManager.new()
	bm2.is_wild_battle = true
	bm2.move_executed.connect(func(attacker: BattlePokemon, _d: BattlePokemon,
			_m: MoveData, _dmg: int) -> void:
		actors2.append(attacker))
	var me2 := _target(45, 20, 1.0)
	bm2.start_battle(me2, _target(45, 20, 1.0))
	var me_acted := false
	for a in actors2:
		if a == me2:
			me_acted = true
			break
	_chk("H.04 discriminator: with no forfeit queued the player does act", me_acted)

	# ⚠️ The flag is per COMBATANT and cleared on use, so a forfeit must not
	# leak into a later turn — a battle that ran more than one turn above would
	# otherwise keep skipping the player forever.
	var player_skips := 0
	for e in skipped:
		if e[0] == me and str(e[1]) == "forfeited":
			player_skips += 1
	_chk("H.05 the forfeit is consumed once, not every turn", player_skips == 1)
	_chk("H.06 fixture: the battle really ran (something was executed)",
			not actors.is_empty())

	# ⚠️ **THE WIRING IS NOT COVERED HERE, AND THAT IS A STATED GAP RATHER THAN
	# AN OVERSIGHT.** H.01-H.06 drive `BattleManager` directly, so they pin the
	# turn-machine primitive and say nothing about whether the Run button
	# actually USES it — the "guard on the callee, blind to the call site" trap
	# `[M27H H4]` already cost this project once. Injection shows the shape:
	# deleting the skip fails H.01/H.05 and leaves H.02 GREEN, because a battler
	# that simply takes its normal turn also lets the opponent act.
	#
	# An end-to-end version was written and WITHDRAWN: driving `_on_run_pressed`
	# needs a live battle, `start_battle` runs to completion, and calling
	# `advance()` on a finished battle hung the suite outright. Closing it wants
	# a way to start a battle and stop at MOVE_SELECTION — a harness change
	# rather than a test. `_force_flee` was added for that attempt and is KEPT:
	# it is what makes a FAILED escape drivable at all, and the next attempt
	# needs it.

	# BattleManager is a Node — leaving these unfreed reports "resources still
	# in use at exit", which `run_overworld_tests.sh` reads as a failed run.
	bm.queue_free()
	bm2.queue_free()
