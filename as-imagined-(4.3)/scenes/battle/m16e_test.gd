extends Node

# M16e test suite — Tier E move effects
# EFFECT_PURSUIT (doubled power + turn-order interception vs a switching target)
# EFFECT_PAIN_SPLIT (current-HP averaging, both directions, floor rounding)
# EFFECT_CONVERSION (type <- first move slot's type)
# EFFECT_CONVERSION_2 (type <- random resist of the TARGET's last used move's type)
# EFFECT_PSYCH_UP (copies target's 7 stat stages + focus_energy)
# Baton Pass extension (focus_energy now passes; minimized/etc. still correctly excluded)
#
# Testing convention: per CLAUDE.md's "snapshot via signals, not post-battle state" rule,
# every assertion below that depends on "what happened at one specific moment" is captured
# via a signal callback (guarded to the first matching occurrence where the move could
# plausibly recur across a longer battle), never by reading state after start_battle()
# fully returns.
#
# Ground truth: pokeemerald_expansion

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_section_1_move_data()
	_test_section_2_pursuit()
	_test_section_3_pain_split()
	_test_section_4_conversion()
	_test_section_5_conversion2()
	_test_section_6_psych_up()
	_test_section_7_baton_pass()
	_test_section_8_type_reset_on_switch()

	var total := _pass + _fail
	print("m16e_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL: " + label)


func _load_move(id: int) -> MoveData:
	var path := "res://data/moves/move_%04d.tres" % id
	return load(path) as MoveData


func _make_mon(species_name: String, level: int, types: Array[int],
		base_hp: int = 80, base_atk: int = 80, base_def: int = 80,
		base_spatk: int = 80, base_spdef: int = 80, base_speed: int = 80) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = species_name
	sp.types = types
	sp.base_hp = base_hp
	sp.base_attack = base_atk
	sp.base_defense = base_def
	sp.base_sp_attack = base_spatk
	sp.base_sp_defense = base_spdef
	sp.base_speed = base_speed
	return BattlePokemon.from_species(sp, level, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])  # [Flaky-suite audit] pinned neutral nature + zero IVs -- S2.03's Pursuit doubled-power comparison is a cross-instance damage-magnitude check


# ── Section 1: Move data spot-checks ─────────────────────────────────────────

func _test_section_1_move_data() -> void:
	var pursuit := _load_move(228)
	_chk("S1.01 Pursuit is_pursuit=true",   pursuit.is_pursuit == true)
	_chk("S1.02 Pursuit type=DARK",         pursuit.type == TypeChart.TYPE_DARK)
	_chk("S1.03 Pursuit power=40",          pursuit.power == 40)
	_chk("S1.04 Pursuit accuracy=100",      pursuit.accuracy == 100)
	_chk("S1.05 Pursuit pp=20",             pursuit.pp == 20)
	_chk("S1.06 Pursuit makes_contact",     pursuit.makes_contact == true)

	var pain_split := _load_move(220)
	_chk("S1.07 Pain Split is_pain_split=true", pain_split.is_pain_split == true)
	_chk("S1.08 Pain Split accuracy=0",         pain_split.accuracy == 0)
	_chk("S1.09 Pain Split pp=20",              pain_split.pp == 20)
	_chk("S1.10 Pain Split power=0 (status)",   pain_split.power == 0)

	var conversion := _load_move(160)
	_chk("S1.11 Conversion is_conversion=true", conversion.is_conversion == true)
	_chk("S1.12 Conversion accuracy=0",         conversion.accuracy == 0)
	_chk("S1.13 Conversion pp=30",              conversion.pp == 30)
	_chk("S1.14 Conversion ignores_protect",    conversion.ignores_protect == true)

	var conversion2 := _load_move(176)
	_chk("S1.15 Conversion2 is_conversion2=true", conversion2.is_conversion2 == true)
	_chk("S1.16 Conversion2 accuracy=0",          conversion2.accuracy == 0)
	_chk("S1.17 Conversion2 pp=30",               conversion2.pp == 30)
	_chk("S1.18 Conversion2 ignores_protect",     conversion2.ignores_protect == true)
	_chk("S1.19 Conversion2 ignores_substitute",  conversion2.ignores_substitute == true)

	var psych_up := _load_move(244)
	_chk("S1.20 Psych Up is_psych_up=true",   psych_up.is_psych_up == true)
	_chk("S1.21 Psych Up accuracy=0",         psych_up.accuracy == 0)
	_chk("S1.22 Psych Up pp=10",              psych_up.pp == 10)
	_chk("S1.23 Psych Up ignores_protect",    psych_up.ignores_protect == true)
	_chk("S1.24 Psych Up ignores_substitute", psych_up.ignores_substitute == true)

	var baton_pass := _load_move(226)
	_chk("S1.25 Baton Pass is_baton_pass=true (pre-existing field)",
			baton_pass.is_baton_pass == true)


# ── Section 2: Pursuit ────────────────────────────────────────────────────────

func _test_section_2_pursuit() -> void:
	var pursuit := _load_move(228)
	var tackle := _load_move(33)

	# S2.01 Normal power (target does NOT switch): damage matches the calculator's
	# unmodified-power result for this move.
	var atk1 := _make_mon("Ps_A1", 50, [TypeChart.TYPE_NORMAL], 300, 100, 100, 80, 80, 100)
	var def1 := _make_mon("Ps_D1", 50, [TypeChart.TYPE_NORMAL], 300, 80, 100, 80, 80, 50)
	atk1.add_move(pursuit)
	def1.add_move(tackle)
	var dmg1: Array[int] = [-1]
	var bm1 := BattleManager.new()
	add_child(bm1)
	bm1._force_hit = true
	bm1._force_roll = 100
	bm1._force_crit = false
	bm1.move_executed.connect(func(_a, _d, mv: MoveData, dmg: int):
		if mv == pursuit and dmg1[0] == -1:
			dmg1[0] = dmg)
	bm1.start_battle(atk1, def1)
	bm1.queue_free()
	var expected1: Dictionary = DamageCalculator.calculate(atk1, def1, pursuit, 100, false)
	_chk("S2.01 Pursuit normal power matches unmodified calculator damage",
			dmg1[0] == expected1["damage"])

	# S2.02 Doubled power (target IS switching this turn): damage matches the calculator's
	# power_override=80 result, and is strictly greater than the normal-power case.
	var atk2 := _make_mon("Ps_A2", 50, [TypeChart.TYPE_NORMAL], 300, 100, 100, 80, 80, 100)
	var def2 := _make_mon("Ps_D2", 50, [TypeChart.TYPE_NORMAL], 300, 80, 100, 80, 80, 50)
	var bench2 := _make_mon("Ps_B2", 50, [TypeChart.TYPE_NORMAL], 300, 80, 100, 80, 80, 50)
	atk2.add_move(pursuit)
	def2.add_move(tackle)
	bench2.add_move(tackle)
	var opp_party2 := BattleParty.new()
	opp_party2.members = [def2, bench2]
	opp_party2.active_index = 0
	var dmg2: Array[int] = [-1]
	var dmg2_target: Array = [null]
	var bench2_hp_at_pursuit: Array[int] = [-1]  # snapshot AT the same moment — the battle
			# continues past turn 1 (both sides survive), so reading bench2.current_hp
			# after start_battle() returns would pick up LATER turns' damage too.
	var bm2 := BattleManager.new()
	add_child(bm2)
	bm2._force_hit = true
	bm2._force_roll = 100
	bm2._force_crit = false
	bm2.move_executed.connect(func(_a, d, mv: MoveData, dmg: int):
		if mv == pursuit and dmg2[0] == -1:
			dmg2[0] = dmg
			dmg2_target[0] = d
			bench2_hp_at_pursuit[0] = bench2.current_hp)
	bm2.queue_switch(1, 1)  # opponent switches to bench2 on turn 1
	bm2.start_battle_with_parties(BattleParty.single(atk2), opp_party2)
	bm2.queue_free()
	var expected2: Dictionary = DamageCalculator.calculate(
			atk2, def2, pursuit, 100, false, 0, false, false, 80)
	_chk("S2.02 Pursuit doubled power matches calculator power_override=80 result",
			dmg2[0] == expected2["damage"])
	_chk("S2.03 Doubled-power damage exceeds normal-power damage",
			dmg2[0] > dmg1[0])

	# S2.04 Turn-order interception: Pursuit strikes the ORIGINAL outgoing Pokémon (def2),
	# not the incoming replacement (bench2) — proves Pursuit executed BEFORE the switch
	# resolved, not after. bench2 should still be at full HP AT THAT MOMENT.
	_chk("S2.04 Pursuit's damage landed on the switching mon, not the replacement",
			dmg2_target[0] == def2)
	_chk("S2.05 Replacement (bench2) had taken no damage from Pursuit at that moment",
			bench2_hp_at_pursuit[0] == bench2.max_hp)

	# S2.06 The switch still resolves after Pursuit's hit (assuming the target survives).
	var switched_in2: Array = []
	var bm2b := BattleManager.new()
	add_child(bm2b)
	bm2b._force_hit = true
	bm2b._force_roll = 100
	bm2b._force_crit = false
	bm2b.pokemon_switched_in.connect(func(p: BattlePokemon, _s: int, _sl: int):
		switched_in2.append(p))
	var atk2b := _make_mon("Ps_A2b", 50, [TypeChart.TYPE_NORMAL], 300, 100, 100, 80, 80, 100)
	var def2b := _make_mon("Ps_D2b", 50, [TypeChart.TYPE_NORMAL], 300, 80, 100, 80, 80, 50)
	var bench2b := _make_mon("Ps_B2b", 50, [TypeChart.TYPE_NORMAL], 300, 80, 100, 80, 80, 50)
	atk2b.add_move(pursuit)
	def2b.add_move(tackle)
	bench2b.add_move(tackle)
	var opp_party2b := BattleParty.new()
	opp_party2b.members = [def2b, bench2b]
	opp_party2b.active_index = 0
	bm2b.queue_switch(1, 1)
	bm2b.start_battle_with_parties(BattleParty.single(atk2b), opp_party2b)
	bm2b.queue_free()
	_chk("S2.07 The queued switch still completes after surviving Pursuit's hit",
			switched_in2.any(func(p): return p == bench2b))


# ── Section 3: Pain Split ─────────────────────────────────────────────────────

func _test_section_3_pain_split() -> void:
	var pain_split := _load_move(220)
	var substitute := _load_move(164)

	# S3.01 User higher HP than target: user takes damage, target heals, both end at the
	# floored average. 300 and 100 -> avg = 200 (exact, no rounding ambiguity here).
	var user1 := _make_mon("PS_U1", 50, [TypeChart.TYPE_NORMAL], 400, 80, 80, 80, 80, 100)
	var tgt1  := _make_mon("PS_T1", 50, [TypeChart.TYPE_NORMAL], 400, 80, 80, 80, 80, 50)
	user1.current_hp = 300
	tgt1.current_hp = 100
	user1.add_move(pain_split)
	tgt1.add_move(_load_move(33))
	var snap1: Array = []
	var bm1 := BattleManager.new()
	add_child(bm1)
	bm1.pain_split_used.connect(func(a: BattlePokemon, d: BattlePokemon):
		if snap1.is_empty():
			snap1.append([a.current_hp, d.current_hp]))
	bm1.start_battle(user1, tgt1)
	bm1.queue_free()
	_chk("S3.01 Pain Split: higher-HP user takes damage down to the average (200)",
			snap1.size() == 1 and snap1[0][0] == 200)
	_chk("S3.02 Pain Split: lower-HP target heals up to the average (200)",
			snap1.size() == 1 and snap1[0][1] == 200)

	# S3.03 Reverse direction: target higher HP than user -> user heals, target damaged.
	var user3 := _make_mon("PS_U3", 50, [TypeChart.TYPE_NORMAL], 400, 80, 80, 80, 80, 100)
	var tgt3  := _make_mon("PS_T3", 50, [TypeChart.TYPE_NORMAL], 400, 80, 80, 80, 80, 50)
	user3.current_hp = 50
	tgt3.current_hp = 350
	user3.add_move(pain_split)
	tgt3.add_move(_load_move(33))
	var snap3: Array = []
	var bm3 := BattleManager.new()
	add_child(bm3)
	bm3.pain_split_used.connect(func(a: BattlePokemon, d: BattlePokemon):
		if snap3.is_empty():
			snap3.append([a.current_hp, d.current_hp]))
	bm3.start_battle(user3, tgt3)
	bm3.queue_free()
	_chk("S3.03 Pain Split reverse: lower-HP user heals up to the average (200)",
			snap3.size() == 1 and snap3[0][0] == 200)
	_chk("S3.04 Pain Split reverse: higher-HP target takes damage down to the average (200)",
			snap3.size() == 1 and snap3[0][1] == 200)

	# S3.05 Floor rounding: (101 + 100) / 2 = 100 (floor of 100.5), not 101 or 100.5.
	var user5 := _make_mon("PS_U5", 50, [TypeChart.TYPE_NORMAL], 400, 80, 80, 80, 80, 100)
	var tgt5  := _make_mon("PS_T5", 50, [TypeChart.TYPE_NORMAL], 400, 80, 80, 80, 80, 50)
	user5.current_hp = 101
	tgt5.current_hp = 100
	user5.add_move(pain_split)
	tgt5.add_move(_load_move(33))
	var snap5: Array = []
	var bm5 := BattleManager.new()
	add_child(bm5)
	bm5.pain_split_used.connect(func(a: BattlePokemon, d: BattlePokemon):
		if snap5.is_empty():
			snap5.append([a.current_hp, d.current_hp]))
	bm5.start_battle(user5, tgt5)
	bm5.queue_free()
	_chk("S3.05 Pain Split floors odd-sum averages ((101+100)/2 -> 100, not 101)",
			snap5.size() == 1 and snap5[0][0] == 100 and snap5[0][1] == 100)

	# S3.06 Blocked by the target's Substitute (no ignoresSubstitute flag on this move).
	var user6 := _make_mon("PS_U6", 50, [TypeChart.TYPE_NORMAL], 400, 80, 80, 80, 80, 50)
	var tgt6  := _make_mon("PS_T6", 50, [TypeChart.TYPE_NORMAL], 400, 80, 80, 80, 80, 100)
	# tgt6 keeps its default full HP here (well above the Substitute cost of maxHP/4) so
	# Substitute's own creation succeeds cleanly on turn 1 — this test is about Pain Split
	# being blocked by an ALREADY-UP Substitute, not about Substitute's own HP threshold.
	user6.add_move(pain_split)
	tgt6.add_move(substitute)
	# Both mons only have one move each, so the battle continues turn after turn (Substitute
	# re-fails "already up", Pain Split keeps getting blocked) well past the moment under
	# test. Capture only the FIRST event of either kind — whichever fires first settles
	# whether the very first Pain Split attempt was blocked, without being confounded by
	# whatever happens deeper into a long-running battle.
	var first_event6: Array = []
	var bm6 := BattleManager.new()
	add_child(bm6)
	bm6.move_missed.connect(func(_a, r: String):
		if first_event6.is_empty():
			first_event6.append(["missed", r]))
	bm6.pain_split_used.connect(func(_a, _d):
		if first_event6.is_empty():
			first_event6.append(["used"]))
	bm6.queue_move(1, 0)  # opp (faster) sets up Substitute before player's Pain Split
	bm6.start_battle(user6, tgt6)
	bm6.queue_free()
	_chk("S3.07 Pain Split blocked by target's Substitute",
			first_event6.size() == 1 and first_event6[0] == ["missed", "substitute"])
	_chk("S3.08 Pain Split's HP-averaging never applied when blocked by Substitute",
			first_event6.size() == 1 and first_event6[0][0] == "missed")


# ── Section 4: Conversion ─────────────────────────────────────────────────────

func _test_section_4_conversion() -> void:
	var conversion := _load_move(160)
	var ember := _load_move(52)    # FIRE
	var growl := _load_move(45)    # NORMAL, status

	# S4.01 Type <- first move slot's type (Ember, FIRE), even though the user is Water.
	var atk1 := _make_mon("Cv_A1", 50, [TypeChart.TYPE_WATER], 300, 80, 80, 80, 80, 100)
	var def1 := _make_mon("Cv_D1", 50, [TypeChart.TYPE_NORMAL], 300, 5, 80, 80, 80, 50)
	atk1.add_move(ember)     # moves[0]
	atk1.add_move(conversion)  # moves[1]
	var changed1: Array = []
	var bm1 := BattleManager.new()
	add_child(bm1)
	bm1.type_changed.connect(func(p: BattlePokemon, t: int):
		if changed1.is_empty():
			changed1.append(t))
	bm1.queue_move(0, 1)  # turn 1: use Conversion (index 1), not Ember
	bm1.start_battle(atk1, def1)
	bm1.queue_free()
	_chk("S4.01 Conversion sets type to FIRE (first move slot's type)",
			changed1.size() == 1 and changed1[0] == TypeChart.TYPE_FIRE)
	_chk("S4.02 Conversion result reflected on species.types[0]",
			atk1.species.types[0] == TypeChart.TYPE_FIRE)

	# S4.03 Fails when the user is already that exact type.
	var atk3 := _make_mon("Cv_A3", 50, [TypeChart.TYPE_FIRE], 300, 80, 80, 80, 80, 100)
	var def3 := _make_mon("Cv_D3", 50, [TypeChart.TYPE_NORMAL], 300, 5, 80, 80, 80, 50)
	atk3.add_move(ember)
	atk3.add_move(conversion)
	var failed3: Array = []
	var changed3: Array = []
	var bm3 := BattleManager.new()
	add_child(bm3)
	bm3.move_effect_failed.connect(func(_p, r: String): failed3.append(r))
	bm3.type_changed.connect(func(_p, _t): changed3.append(true))
	bm3.queue_move(0, 1)
	bm3.start_battle(atk3, def3)
	bm3.queue_free()
	_chk("S4.04 Conversion fails when user already has that type",
			"conversion_failed" in failed3)
	_chk("S4.05 Conversion does not change type on failure", changed3.is_empty())

	# S4.06 Uses the LITERAL first move slot regardless of category — a status move
	# (Growl, NORMAL) in slot 0 wins over a later damaging move (Ember, FIRE) in slot 1.
	var atk6 := _make_mon("Cv_A6", 50, [TypeChart.TYPE_WATER], 300, 80, 80, 80, 80, 100)
	var def6 := _make_mon("Cv_D6", 50, [TypeChart.TYPE_NORMAL], 300, 5, 80, 80, 80, 50)
	atk6.add_move(growl)
	atk6.add_move(ember)
	atk6.add_move(conversion)
	var changed6: Array = []
	var bm6 := BattleManager.new()
	add_child(bm6)
	bm6.type_changed.connect(func(_p, t: int):
		if changed6.is_empty():
			changed6.append(t))
	bm6.queue_move(0, 2)  # use Conversion (index 2) on turn 1
	bm6.start_battle(atk6, def6)
	bm6.queue_free()
	_chk("S4.07 Conversion uses moves[0]'s type (Growl/NORMAL) even though it's a status move",
			changed6.size() == 1 and changed6[0] == TypeChart.TYPE_NORMAL)


# ── Section 5: Conversion 2 ───────────────────────────────────────────────────

func _test_section_5_conversion2() -> void:
	var conversion2 := _load_move(176)
	var ember := _load_move(52)   # FIRE
	var growl := _load_move(45)   # NORMAL, status
	var tackle := _load_move(33)
	var water_gun := _load_move(55)  # WATER, damaging

	# S5.01 Resist selection against the TARGET's last used move type (Ember/FIRE).
	# Fire-resisting types in this chart, ascending id: ROCK(6), FIRE(11), WATER(12),
	# DRAGON(17). Forcing pick index 0 selects ROCK deterministically.
	var user1 := _make_mon("C2_U1", 50, [TypeChart.TYPE_NORMAL], 400, 80, 80, 80, 80, 50)
	var opp1  := _make_mon("C2_O1", 50, [TypeChart.TYPE_NORMAL], 400, 5, 80, 80, 80, 100)
	user1.add_move(tackle)
	user1.add_move(conversion2)
	opp1.add_move(ember)
	var changed1: Array = []
	var bm1 := BattleManager.new()
	add_child(bm1)
	bm1._force_conversion2_pick = 0
	bm1.type_changed.connect(func(_p, t: int):
		if changed1.is_empty():
			changed1.append(t))
	bm1.queue_move(0, 0)  # turn 1: harmless Tackle (lets opp establish last_move_used=Ember)
	bm1.queue_move(0, 1)  # turn 2: Conversion 2
	bm1.start_battle(user1, opp1)
	bm1.queue_free()
	_chk("S5.01 Conversion 2 picks a Fire-resisting type (forced index 0 -> ROCK)",
			changed1.size() == 1 and changed1[0] == TypeChart.TYPE_ROCK)

	# S5.02 Fails when the target has no last_move_used yet (very first action of the battle).
	var user2 := _make_mon("C2_U2", 50, [TypeChart.TYPE_NORMAL], 300, 80, 80, 80, 80, 150)
	var opp2  := _make_mon("C2_O2", 50, [TypeChart.TYPE_NORMAL], 300, 5, 80, 80, 80, 50)
	user2.add_move(conversion2)
	opp2.add_move(tackle)
	# user2's only move is Conversion 2, so the battle continues turn after turn — and by
	# turn 2, opp2 DOES have a last_move_used (from turn 1's Tackle), so a later Conversion 2
	# attempt would legitimately succeed. Capture only the FIRST event of either kind so
	# this test is strictly about the very first attempt (turn 1, before opp2 has acted).
	var first_event2: Array = []
	var bm2 := BattleManager.new()
	add_child(bm2)
	bm2.move_effect_failed.connect(func(_p, r: String):
		if first_event2.is_empty():
			first_event2.append(["failed", r]))
	bm2.type_changed.connect(func(_p, t: int):
		if first_event2.is_empty():
			first_event2.append(["changed", t]))
	bm2.start_battle(user2, opp2)  # user2 is faster -> acts before opp2 has ever moved
	bm2.queue_free()
	_chk("S5.03 Conversion 2 fails when target has no last used move",
			first_event2.size() == 1 and first_event2[0] == ["failed", "conversion2_failed"])
	_chk("S5.04 Conversion 2 does not change type on that first failed attempt",
			first_event2.size() == 1 and first_event2[0][0] == "failed")

	# S5.05 Candidate pool excludes types the user already has. User is already ROCK
	# (the index-0 candidate from S5.01's pool), so forcing index 0 now yields the NEXT
	# candidate, FIRE, proving exclusion happens before indexing (not after).
	var user5 := _make_mon("C2_U5", 50, [TypeChart.TYPE_ROCK], 400, 80, 80, 80, 80, 50)
	var opp5  := _make_mon("C2_O5", 50, [TypeChart.TYPE_NORMAL], 400, 5, 80, 80, 80, 100)
	user5.add_move(tackle)
	user5.add_move(conversion2)
	opp5.add_move(ember)
	var changed5: Array = []
	var bm5 := BattleManager.new()
	add_child(bm5)
	bm5._force_conversion2_pick = 0
	bm5.type_changed.connect(func(_p, t: int):
		if changed5.is_empty():
			changed5.append(t))
	bm5.queue_move(0, 0)
	bm5.queue_move(0, 1)
	bm5.start_battle(user5, opp5)
	bm5.queue_free()
	_chk("S5.06 Conversion 2 excludes the user's current type from the candidate pool",
			changed5.size() == 1 and changed5[0] == TypeChart.TYPE_FIRE)

	# S5.07 Uses the target's last USED move even if it's a non-damaging status move
	# (Growl) — confirms this project's "last move used" semantics (GEN_LATEST config),
	# not a "last move that hit the user" tracker (which Growl, dealing no damage, would
	# never have satisfied).
	var user7 := _make_mon("C2_U7", 50, [TypeChart.TYPE_NORMAL], 400, 80, 80, 80, 80, 50)
	var opp7  := _make_mon("C2_O7", 50, [TypeChart.TYPE_NORMAL], 400, 5, 80, 80, 80, 100)
	user7.add_move(tackle)
	user7.add_move(conversion2)
	opp7.add_move(growl)
	var changed7: Array = []
	var bm7 := BattleManager.new()
	add_child(bm7)
	bm7._force_conversion2_pick = 0
	bm7.type_changed.connect(func(_p, t: int):
		if changed7.is_empty():
			changed7.append(t))
	bm7.queue_move(0, 0)
	bm7.queue_move(0, 1)
	bm7.start_battle(user7, opp7)
	bm7.queue_free()
	_chk("S5.08 Conversion 2 resists Growl's type (NORMAL) even though Growl dealt no damage",
			changed7.size() == 1 and changed7[0] == TypeChart.TYPE_ROCK)

	# S5.09 [M16 Review, Area 2] Direct conflict discriminator: the target's last move that
	# actually HIT the user (Water Gun, WATER, turn 1) has a DIFFERENT resist-pool index-0
	# candidate (WATER, id 12) than the target's later LAST-USED move (Growl, NORMAL, turn 2,
	# which lands on ROCK, id 6 — a genuinely different type from the Water Gun case, not a
	# coincidental match). If the implementation used "type of the last move that hit the
	# user" instead of "target's last USED move," this would resist WATER, not NORMAL/ROCK.
	# opp9 is FASTER than user9 and only has 2 queued moves — Conversion 2 must land on
	# turn 2, right after Growl within that SAME turn (opp acts first), not turn 3: by turn 3
	# opp's queue would have drained and auto-select would re-use Water Gun (moves[0]) BEFORE
	# user9 acts, re-overwriting last_move_used and silently defeating the discriminator.
	# (This is exactly the kind of "long-battle recast" pitfall CLAUDE.md's testing
	# convention warns about — caught here during the M16 review, not before.)
	var user9 := _make_mon("C2_U9", 50, [TypeChart.TYPE_NORMAL], 400, 80, 80, 80, 80, 50)
	var opp9  := _make_mon("C2_O9", 50, [TypeChart.TYPE_NORMAL], 400, 5, 80, 80, 80, 100)
	user9.add_move(tackle)
	user9.add_move(conversion2)
	opp9.add_move(water_gun)
	opp9.add_move(growl)
	var changed9: Array = []
	var bm9 := BattleManager.new()
	add_child(bm9)
	bm9._force_conversion2_pick = 0
	bm9.type_changed.connect(func(_p, t: int):
		if changed9.is_empty():
			changed9.append(t))
	bm9.queue_move(0, 0)  # turn 1: user tackle (filler) — opp uses Water Gun (HITS user)
	bm9.queue_move(0, 1)  # turn 2: user Conversion 2 — fires AFTER opp's Growl this same turn
	bm9.queue_move(1, 0)  # opp turn 1: Water Gun
	bm9.queue_move(1, 1)  # opp turn 2: Growl
	bm9.start_battle(user9, opp9)
	bm9.queue_free()
	_chk("S5.10 [M16 Review] Conversion 2 resists the target's last USED move (Growl/NORMAL"
			+ " -> ROCK), not the type of an earlier move that actually hit the user"
			+ " (Water Gun/WATER -> would have been WATER if last-hit-by were used)",
			changed9.size() == 1 and changed9[0] == TypeChart.TYPE_ROCK)


# ── Section 6: Psych Up ───────────────────────────────────────────────────────

func _test_section_6_psych_up() -> void:
	var psych_up := _load_move(244)
	var tackle := _load_move(33)

	# S6.01/S6.02 Copies all 7 stat stages (including negatives), fully overwriting the
	# user's own pre-existing stages, and ALSO copies focus_energy (Gen6+ behavior).
	var user1 := _make_mon("PU_U1", 50, [TypeChart.TYPE_NORMAL], 400, 80, 80, 80, 80, 150)
	var opp1  := _make_mon("PU_O1", 50, [TypeChart.TYPE_NORMAL], 400, 80, 80, 80, 80, 50)
	user1.stat_stages = [-1, -1, -1, -1, -1, -1, -1]
	user1.focus_energy = false
	opp1.stat_stages = [2, -3, 1, 0, -1, 0, 2]
	opp1.focus_energy = true
	user1.add_move(psych_up)
	opp1.add_move(tackle)
	var copied1: Array = []
	var bm1 := BattleManager.new()
	add_child(bm1)
	bm1.stat_changes_copied.connect(func(u: BattlePokemon, _f: BattlePokemon):
		if copied1.is_empty():
			copied1.append([u.stat_stages.duplicate(), u.focus_energy]))
	bm1.start_battle(user1, opp1)  # user1 is faster -> Psych Up executes before opp acts
	bm1.queue_free()
	_chk("S6.01 Psych Up copies all 7 stat stages exactly (including negatives)",
			copied1.size() == 1 and copied1[0][0] == [2, -3, 1, 0, -1, 0, 2])
	_chk("S6.02 Psych Up also copies the target's focus_energy volatile",
			copied1.size() == 1 and copied1[0][1] == true)

	# S6.03 Overwrite, not merge/OR: target has focus_energy=false, user starts true ->
	# user ends up false (proves direct assignment, not a boolean-OR bug).
	var user3 := _make_mon("PU_U3", 50, [TypeChart.TYPE_NORMAL], 400, 80, 80, 80, 80, 150)
	var opp3  := _make_mon("PU_O3", 50, [TypeChart.TYPE_NORMAL], 400, 80, 80, 80, 80, 50)
	user3.focus_energy = true
	opp3.focus_energy = false
	user3.add_move(psych_up)
	opp3.add_move(tackle)
	var copied3: Array = []
	var bm3 := BattleManager.new()
	add_child(bm3)
	bm3.stat_changes_copied.connect(func(u: BattlePokemon, _f: BattlePokemon):
		if copied3.is_empty():
			copied3.append(u.focus_energy))
	bm3.start_battle(user3, opp3)
	bm3.queue_free()
	_chk("S6.04 Psych Up overwrites (not ORs) focus_energy: true -> false",
			copied3.size() == 1 and copied3[0] == false)


# ── Section 7: Baton Pass — focus_energy extension ────────────────────────────

func _test_section_7_baton_pass() -> void:
	var baton_pass := _load_move(226)
	var tackle := _load_move(33)

	# S7.01 focus_energy now passes through Baton Pass (was missing since M9 predates
	# Focus Energy's M16a implementation).
	var switcher1 := _make_mon("BP_S1", 50, [TypeChart.TYPE_NORMAL], 300, 80, 80, 80, 80, 100)
	var bench1     := _make_mon("BP_B1", 50, [TypeChart.TYPE_NORMAL], 300, 80, 80, 80, 80, 50)
	var opp1       := _make_mon("BP_OP1", 50, [TypeChart.TYPE_NORMAL], 300, 5, 80, 80, 80, 30)
	switcher1.focus_energy = true
	switcher1.add_move(baton_pass)
	bench1.add_move(tackle)
	opp1.add_move(tackle)
	var player_party1 := BattleParty.new()
	player_party1.members = [switcher1, bench1]
	player_party1.active_index = 0
	var incoming_snapshot1: Array = []
	var bm1 := BattleManager.new()
	add_child(bm1)
	bm1.baton_passed.connect(func(_f: BattlePokemon, t: BattlePokemon):
		if incoming_snapshot1.is_empty():
			incoming_snapshot1.append(t.focus_energy))
	bm1.start_battle_with_parties(player_party1, BattleParty.single(opp1))
	bm1.queue_free()
	_chk("S7.01 Baton Pass now carries focus_energy to the incoming Pokémon",
			incoming_snapshot1.size() == 1 and incoming_snapshot1[0] == true)

	# S7.02 [M16 Review, Area 1] Regression: every OTHER M16a-M16e BattlePokemon volatile
	# is still correctly NOT passed, because none of them appear in source's
	# VOLATILE_DEFINITIONS V_BATON_PASSABLE set (confirmed by re-reading constants/battle.h
	# in full): minimized (M16b, VOLATILE_MINIMIZE has no V_BATON_PASSABLE flag),
	# defense_curled (M16b, VOLATILE_DEFENSE_CURL has no flag), rollout_turns (M16b, no
	# dedicated Rollout volatile carries the flag either). focus_energy (M16a) was the only
	# M16-era field that source DOES flag as passable, and it was already fixed above (S7.01).
	var switcher2 := _make_mon("BP_S2", 50, [TypeChart.TYPE_NORMAL], 300, 80, 80, 80, 80, 100)
	var bench2     := _make_mon("BP_B2", 50, [TypeChart.TYPE_NORMAL], 300, 80, 80, 80, 80, 50)
	var opp2       := _make_mon("BP_OP2", 50, [TypeChart.TYPE_NORMAL], 300, 5, 80, 80, 80, 30)
	switcher2.minimized = true
	switcher2.defense_curled = true
	switcher2.rollout_turns = 3
	switcher2.add_move(baton_pass)
	bench2.add_move(tackle)
	opp2.add_move(tackle)
	var player_party2 := BattleParty.new()
	player_party2.members = [switcher2, bench2]
	player_party2.active_index = 0
	var incoming_snapshot2: Array = []
	var bm2 := BattleManager.new()
	add_child(bm2)
	bm2.baton_passed.connect(func(_f: BattlePokemon, t: BattlePokemon):
		if incoming_snapshot2.is_empty():
			incoming_snapshot2.append([t.minimized, t.defense_curled, t.rollout_turns]))
	bm2.start_battle_with_parties(player_party2, BattleParty.single(opp2))
	bm2.queue_free()
	_chk("S7.02 Baton Pass still correctly does NOT carry minimized",
			incoming_snapshot2.size() == 1 and incoming_snapshot2[0][0] == false)
	_chk("S7.03 [M16 Review] Baton Pass still correctly does NOT carry defense_curled",
			incoming_snapshot2.size() == 1 and incoming_snapshot2[0][1] == false)
	_chk("S7.04 [M16 Review] Baton Pass still correctly does NOT carry rollout_turns",
			incoming_snapshot2.size() == 1 and incoming_snapshot2[0][2] == 0)


# ── Section 8: Type reset on switch-in (follow-up fix) ────────────────────────

func _test_section_8_type_reset_on_switch() -> void:
	var conversion := _load_move(160)
	var ember := _load_move(52)   # FIRE
	var tackle := _load_move(33)

	# S8.01/S8.02 [Follow-up fixes session, 2026-07-02] A Conversion-induced type change
	# does NOT survive a voluntary switch-out and switch-back-in later in the same battle —
	# matches source, where the active battler struct is repopulated from natural species
	# types at every switch-in (CopyMonAbilityAndTypesToBattleMon, battle_util.c
	# L9365-9379; Cmd_switchindataupdate, battle_script_commands.c L5030-5032), unlike this
	# project's long-lived BattlePokemon objects which would otherwise keep the mutation
	# forever without an explicit reset (see BattleManager._reset_mon_type,
	# BattlePokemon.original_types).
	var user := _make_mon("TR_U8", 50, [TypeChart.TYPE_WATER], 400, 80, 80, 80, 80, 100)
	var bench := _make_mon("TR_B8", 50, [TypeChart.TYPE_GRASS], 400, 80, 80, 80, 80, 100)
	var opp := _make_mon("TR_O8", 50, [TypeChart.TYPE_NORMAL], 400, 5, 80, 80, 80, 30)
	user.add_move(ember)       # index 0 — Conversion reads THIS slot's type (FIRE)
	user.add_move(conversion)  # index 1
	bench.add_move(tackle)
	opp.add_move(tackle)

	var player_party := BattleParty.new()
	player_party.members = [user, bench]
	player_party.active_index = 0

	var type_after_conversion: Array = []
	var type_on_switch_back: Array = []
	var bm := BattleManager.new()
	add_child(bm)
	bm.type_changed.connect(func(_p, t: int):
		if type_after_conversion.is_empty():
			type_after_conversion.append(t))
	bm.pokemon_switched_in.connect(func(p: BattlePokemon, _s: int, _sl: int):
		if p == user and type_on_switch_back.is_empty():
			type_on_switch_back.append(p.species.types.duplicate()))
	bm.queue_move(0, 1)     # turn 1: Conversion (user still active)
	bm.queue_switch(0, 1)   # turn 2: user switches out to bench
	bm.queue_switch(0, 0)   # turn 3: bench switches out, user switches back in
	bm.start_battle_with_parties(player_party, BattleParty.single(opp))
	bm.queue_free()

	_chk("S8.01 Conversion changed the user's type to FIRE before switching out",
			type_after_conversion.size() == 1 and type_after_conversion[0] == TypeChart.TYPE_FIRE)
	_chk("S8.02 [Follow-up fix] Type reverts to the original species type (WATER) after " +
			"switching back in, not the Conversion-mutated FIRE",
			type_on_switch_back.size() == 1
			and TypeChart.TYPE_WATER in type_on_switch_back[0]
			and not (TypeChart.TYPE_FIRE in type_on_switch_back[0]))

	# Note: fainting needs no special handling here — a fainted mon never re-enters the
	# field, so there is no "restore type after faint" scenario. Confirmed by construction:
	# _reset_mon_type is only ever called from the 5 switch-IN call sites, never from
	# _clear_volatiles/_phase_faint_check, so this fix added nothing to the faint path.
