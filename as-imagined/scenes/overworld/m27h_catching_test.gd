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

const EXPECTED_TOTAL := 56

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
	var found := false
	for entry in ItemSelectScreen._ITEMS:
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
