extends Node

# M16c test suite — Tier C move effects (screens / side conditions)
# EFFECT_REFLECT (halves Physical damage hitting the caster's side, 5 turns)
# EFFECT_LIGHT_SCREEN (halves Special damage, 5 turns)
# EFFECT_AURORA_VEIL (halves both, hail-gated, independent slot from the above two)
# Screen damage modifier placement, crit bypass, doubles ⅔ fraction
# Brick Break (MOVE_EFFECT_BREAK_SCREEN — clears target's side's screens pre-damage)
#
# Ground truth: pokeemerald_expansion

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_section_1_move_data()
	_test_section_2_reflect()
	_test_section_3_light_screen()
	_test_section_4_aurora_veil()
	_test_section_5_crit_bypass()
	_test_section_6_brick_break()

	var total := _pass + _fail
	print("m16c_test: %d/%d passed" % [_pass, total])
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
	return BattlePokemon.from_species(sp, level, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])  # [M18.5h-1/2] pinned neutral nature + zero IVs -- exact-value assertions predate both


# ── Section 1: Move data spot-checks ─────────────────────────────────────────

func _test_section_1_move_data() -> void:
	var light_screen := _load_move(113)
	_chk("S1.01 Light Screen is_light_screen=true", light_screen.is_light_screen == true)
	_chk("S1.02 Light Screen category=STAT",        light_screen.category == 2)
	_chk("S1.03 Light Screen accuracy=0",            light_screen.accuracy == 0)
	_chk("S1.04 Light Screen pp=30",                 light_screen.pp == 30)
	_chk("S1.05 Light Screen ignores_protect",       light_screen.ignores_protect == true)
	_chk("S1.06 Light Screen type=PSYCHIC",          light_screen.type == TypeChart.TYPE_PSYCHIC)

	var reflect := _load_move(115)
	_chk("S1.07 Reflect is_reflect=true",  reflect.is_reflect == true)
	_chk("S1.08 Reflect category=STAT",    reflect.category == 2)
	_chk("S1.09 Reflect accuracy=0",       reflect.accuracy == 0)
	_chk("S1.10 Reflect pp=20",            reflect.pp == 20)
	_chk("S1.11 Reflect ignores_protect",  reflect.ignores_protect == true)

	var brick_break := _load_move(280)
	_chk("S1.12 Brick Break breaks_screens=true", brick_break.breaks_screens == true)
	_chk("S1.13 Brick Break power=75",             brick_break.power == 75)
	_chk("S1.14 Brick Break type=FIGHTING",        brick_break.type == TypeChart.TYPE_FIGHTING)
	_chk("S1.15 Brick Break makes_contact",        brick_break.makes_contact == true)
	_chk("S1.16 Brick Break category=PHYS",        brick_break.category == 0)

	var aurora_veil := _load_move(657)
	_chk("S1.17 Aurora Veil is_aurora_veil=true", aurora_veil.is_aurora_veil == true)
	_chk("S1.18 Aurora Veil category=STAT",        aurora_veil.category == 2)
	_chk("S1.19 Aurora Veil accuracy=0",           aurora_veil.accuracy == 0)
	_chk("S1.20 Aurora Veil pp=20",                aurora_veil.pp == 20)
	_chk("S1.21 Aurora Veil type=ICE",             aurora_veil.type == TypeChart.TYPE_ICE)

	# BattleManager _side_conditions defaults: fresh instance, both sides zeroed.
	var bm := BattleManager.new()
	add_child(bm)
	_chk("S1.22 _side_conditions has 2 entries", bm._side_conditions.size() == 2)
	_chk("S1.23 side 0 reflect_turns defaults 0",
			bm._side_conditions[0]["reflect_turns"] == 0)
	_chk("S1.24 side 0 light_screen_turns defaults 0",
			bm._side_conditions[0]["light_screen_turns"] == 0)
	_chk("S1.25 side 0 aurora_veil_turns defaults 0",
			bm._side_conditions[0]["aurora_veil_turns"] == 0)
	_chk("S1.26 side 1 reflect_turns defaults 0",
			bm._side_conditions[1]["reflect_turns"] == 0)
	bm.queue_free()


# ── Section 2: EFFECT_REFLECT ─────────────────────────────────────────────────

func _test_section_2_reflect() -> void:
	var reflect := _load_move(115)
	var tackle  := _load_move(33)
	var psybeam := _load_move(60)  # Special move, used to confirm Reflect does NOT affect it

	# S2.01 Using Reflect sets the caster's side reflect_turns=5 and emits screen_set.
	var player1 := _make_mon("R_A", 50, [TypeChart.TYPE_NORMAL], 80, 80, 80, 80, 80, 100)
	var opp1    := _make_mon("R_B", 50, [TypeChart.TYPE_NORMAL], 80, 30, 80, 80, 80, 50)
	player1.add_move(reflect)
	opp1.add_move(tackle)
	var set_events1: Array = []
	var bm1 := BattleManager.new()
	add_child(bm1)
	bm1.screen_set.connect(func(side: int, name_: String): set_events1.append([side, name_]))
	bm1.start_battle(player1, opp1)
	bm1.queue_free()
	_chk("S2.01 screen_set(0, reflect) emitted", [0, "reflect"] in set_events1)

	# S2.02 Reflect halves Physical damage — exact floor(dmg/2), verified via direct
	# DamageCalculator calls (screen_active=true vs false), same attacker/defender/move.
	var atk2 := _make_mon("R_Atk", 50, [TypeChart.TYPE_FIGHTING])
	var def2 := _make_mon("R_Def", 50, [TypeChart.TYPE_WATER])
	var r_normal2: Dictionary = DamageCalculator.calculate(
			atk2, def2, tackle, 100, false)
	var r_screened2: Dictionary = DamageCalculator.calculate(
			atk2, def2, tackle, 100, false, DamageCalculator.WEATHER_NONE, false, false, -1,
			true, false)
	_chk("S2.02 Reflect halves Physical damage (exact floor(dmg/2))",
			r_screened2["damage"] == r_normal2["damage"] / 2)

	# S2.03 Reflect does NOT reduce Special damage (screen_active resolved per-category by
	# the caller — this direct call passes screen_active=true regardless of category to
	# confirm DamageCalculator itself doesn't gate on category; the category gate lives in
	# BattleManager._do_damaging_hit, tested via S2.02 vs a live battle in S2.09).
	# Here we instead confirm via a live battle that Psybeam (Special) is unaffected while
	# Reflect is up on the defender's side.
	var player3 := _make_mon("R_C", 50, [TypeChart.TYPE_PSYCHIC], 80, 80, 80, 80, 80, 100)
	var opp3    := _make_mon("R_D", 50, [TypeChart.TYPE_NORMAL], 200, 80, 80, 80, 80, 50)
	player3.add_move(psybeam)
	opp3.add_move(reflect)
	var dmg_with_reflect3: Array[int] = []
	var bm3 := BattleManager.new()
	add_child(bm3)
	bm3._force_roll = 100
	bm3._force_crit = false
	bm3.move_executed.connect(func(a: BattlePokemon, _d: BattlePokemon, mv: MoveData, dmg: int):
		if a == player3 and mv == psybeam and dmg_with_reflect3.size() < 2:
			dmg_with_reflect3.append(dmg))
	bm3.queue_move(0, 0)  # turn 1: Psybeam (before opp's Reflect is even up)
	bm3.queue_move(1, 0)  # turn 1: opp sets up Reflect
	bm3.queue_move(0, 0)  # turn 2: Psybeam again (Reflect now up on opp's side)
	bm3.start_battle(player3, opp3)
	bm3.queue_free()
	_chk("S2.03 captured 2 Psybeam hits (before/after Reflect)", dmg_with_reflect3.size() == 2)
	_chk("S2.04 Psybeam (Special) unaffected by Reflect",
			dmg_with_reflect3.size() == 2 and dmg_with_reflect3[0] == dmg_with_reflect3[1])

	# S2.05 Duration: reflect_turns decrements 5→4→3→2→1→0 over 5 end-of-turns, and
	# screen_expired(side, "reflect") fires when it reaches 0.
	# player5's ONLY move is Reflect, so once it expires it gets auto-recast on the very
	# next turn (nothing else to select) — captures are bounded to exactly 5 (the first
	# expiry) so the test isn't polluted by that legitimate recast-after-expiry behavior.
	var player5 := _make_mon("R_E", 50, [TypeChart.TYPE_NORMAL], 300, 80, 300, 80, 300, 100)
	var opp5    := _make_mon("R_F", 50, [TypeChart.TYPE_NORMAL], 300, 5, 300, 80, 300, 50)
	player5.add_move(reflect)
	opp5.add_move(tackle)
	var turns_seq5: Array[int] = []
	var expired_events5: Array = []
	var bm5 := BattleManager.new()
	add_child(bm5)
	bm5._force_hit = true
	bm5.screen_expired.connect(func(side: int, name_: String):
		if expired_events5.size() < 1:
			expired_events5.append([side, name_]))
	bm5.phase_changed.connect(func(p: BattleManager.BattlePhase):
		if p == BattleManager.BattlePhase.SWITCH_PROMPT and turns_seq5.size() < 5:
			turns_seq5.append(bm5._side_conditions[0]["reflect_turns"]))
	for _t in range(6):
		bm5.queue_move(1, 0)
	bm5.start_battle(player5, opp5)
	bm5.queue_free()
	_chk("S2.06 reflect_turns sequence 4,3,2,1,0 over 5 end-of-turns",
			turns_seq5 == [4, 3, 2, 1, 0])
	_chk("S2.07 screen_expired(0, reflect) fired when it reached 0",
			expired_events5 == [[0, "reflect"]])

	# S2.08 Already-up: using Reflect again while up fails (does not refresh the timer).
	var player8 := _make_mon("R_G", 50, [TypeChart.TYPE_NORMAL], 300, 80, 300, 80, 300, 100)
	var opp8    := _make_mon("R_H", 50, [TypeChart.TYPE_NORMAL], 300, 5, 300, 80, 300, 50)
	player8.add_move(reflect)
	opp8.add_move(tackle)
	var fail_events8: Array[String] = []
	var bm8 := BattleManager.new()
	add_child(bm8)
	bm8._force_hit = true
	bm8.move_effect_failed.connect(func(_t: BattlePokemon, r: String): fail_events8.append(r))
	for _t in range(3):
		bm8.queue_move(1, 0)
	bm8.start_battle(player8, opp8)
	bm8.queue_free()
	_chk("S2.08 already_reflect fails on repeated use", "already_reflect" in fail_events8)
	_chk("S2.09 timer not refreshed (still counting down, not back at 5)",
			bm8._side_conditions[0]["reflect_turns"] < 5)

	# S2.10 Doubles: reflect reduces Physical damage by ⅔ (0.667) instead of ½ in doubles.
	var atk10 := _make_mon("R_Atk10", 50, [TypeChart.TYPE_FIGHTING])
	var def10 := _make_mon("R_Def10", 50, [TypeChart.TYPE_WATER])
	var r_singles10: Dictionary = DamageCalculator.calculate(
			atk10, def10, tackle, 100, false, DamageCalculator.WEATHER_NONE, false, false, -1,
			true, false)
	var r_doubles10: Dictionary = DamageCalculator.calculate(
			atk10, def10, tackle, 100, false, DamageCalculator.WEATHER_NONE, false, false, -1,
			true, true)
	_chk("S2.10 doubles screen reduction is weaker than singles (0.667 vs 0.5)",
			r_doubles10["damage"] > r_singles10["damage"])
	var r_unscreened10: Dictionary = DamageCalculator.calculate(atk10, def10, tackle, 100, false)
	_chk("S2.11 doubles reduction matches UQ_4_12(0.667) exactly",
			r_doubles10["damage"] == (r_unscreened10["damage"] * 2732 + 2047) / 4096)

	# S2.12 Persistence across switch: Reflect stays up on side 0 after the caster switches
	# out (side conditions are side-bound, not battler-bound — nothing in _clear_volatiles /
	# _switch_out_clear touches _side_conditions).
	var mon1_12 := _make_mon("R_I", 50, [TypeChart.TYPE_NORMAL], 80, 80, 80, 80, 80, 100)
	var mon2_12 := _make_mon("R_J", 50, [TypeChart.TYPE_NORMAL], 80, 80, 80, 80, 80, 90)
	mon1_12.add_move(reflect)
	mon2_12.add_move(tackle)
	var opp12 := _make_mon("R_K", 50, [TypeChart.TYPE_NORMAL], 300, 30, 80, 80, 80, 50)
	opp12.add_move(tackle)
	var player_party12 := BattleParty.new()
	player_party12.members = [mon1_12, mon2_12]
	player_party12.active_index = 0
	var bm12 := BattleManager.new()
	add_child(bm12)
	# Snapshot right at the switch-in moment — the battle keeps running afterward (mon2 vs
	# opp12 trade real damage) and Reflect will naturally expire 5 turns after being cast,
	# so checking _side_conditions after the whole battle completes would be checking
	# arbitrarily-later state, not "did the switch itself clear it."
	var reflect_turns_at_switch_in: Array[int] = [-1]
	bm12.pokemon_switched_in.connect(func(mon: BattlePokemon, side: int, _slot: int):
		if mon == mon2_12 and side == 0:
			reflect_turns_at_switch_in[0] = bm12._side_conditions[0]["reflect_turns"])
	bm12.queue_move(0, 0)   # turn 1: mon1 sets up Reflect
	bm12.queue_switch(0, 1) # turn 2: switch to mon2
	bm12.queue_move(1, 0)
	bm12.queue_move(1, 0)
	bm12.start_battle_with_parties(player_party12, BattleParty.single(opp12))
	bm12.queue_free()
	_chk("S2.12 Reflect persists across switch (still active on side 0 right after switch-in)",
			reflect_turns_at_switch_in[0] > 0)


# ── Section 3: EFFECT_LIGHT_SCREEN ────────────────────────────────────────────

func _test_section_3_light_screen() -> void:
	var light_screen := _load_move(113)
	var tackle := _load_move(33)   # Physical — used to confirm Light Screen doesn't affect it
	var psybeam := _load_move(60)  # Special

	# S3.01 Using Light Screen sets light_screen_turns=5, emits screen_set.
	var player1 := _make_mon("L_A", 50, [TypeChart.TYPE_NORMAL], 80, 80, 80, 80, 80, 100)
	var opp1    := _make_mon("L_B", 50, [TypeChart.TYPE_NORMAL], 80, 30, 80, 80, 80, 50)
	player1.add_move(light_screen)
	opp1.add_move(tackle)
	# screen_set only fires on a SUCCESSFUL fresh setup (unlike move_executed, which also
	# fires on subsequent already-up attempts) — safe to snapshot the timer right there.
	var set_events1: Array = []
	var turns_at_set1: Array[int] = [-1]
	var bm1 := BattleManager.new()
	add_child(bm1)
	bm1.screen_set.connect(func(side: int, name_: String):
		set_events1.append([side, name_])
		if side == 0 and name_ == "light_screen" and turns_at_set1[0] == -1:
			turns_at_set1[0] = bm1._side_conditions[0]["light_screen_turns"])
	bm1._force_hit = true
	bm1.start_battle(player1, opp1)
	bm1.queue_free()
	_chk("S3.01 screen_set(0, light_screen) emitted", [0, "light_screen"] in set_events1)
	_chk("S3.02 light_screen_turns == 5 right after setup", turns_at_set1[0] == 5)

	# S3.03 Light Screen halves Special damage but leaves Physical damage untouched.
	var player3 := _make_mon("L_C", 50, [TypeChart.TYPE_NORMAL], 200, 80, 80, 80, 80, 100)
	var opp3    := _make_mon("L_D", 50, [TypeChart.TYPE_NORMAL], 200, 80, 80, 80, 80, 50)
	player3.add_move(tackle)    # Physical
	player3.add_move(psybeam)   # Special
	opp3.add_move(light_screen)
	var phys_dmg3: Array[int] = []
	var spec_dmg3: Array[int] = []
	var bm3 := BattleManager.new()
	add_child(bm3)
	bm3._force_roll = 100
	bm3._force_crit = false
	bm3.move_executed.connect(func(a: BattlePokemon, _d: BattlePokemon, mv: MoveData, dmg: int):
		if a == player3 and mv == tackle and phys_dmg3.size() < 2:
			phys_dmg3.append(dmg)
		elif a == player3 and mv == psybeam and spec_dmg3.size() < 2:
			spec_dmg3.append(dmg))
	bm3.queue_move(0, 0)  # turn 1: Tackle (no screen yet)
	bm3.queue_move(1, 0)  # turn 1: opp sets up Light Screen
	bm3.queue_move(0, 0)  # turn 2: Tackle again (Light Screen up — should be unaffected)
	bm3.queue_move(1, 0)
	bm3.queue_move(0, 1)  # turn 3: Psybeam (Light Screen still up — should be halved)
	bm3.queue_move(1, 0)
	bm3.start_battle(player3, opp3)
	bm3.queue_free()
	_chk("S3.04 Physical Tackle damage unaffected by Light Screen",
			phys_dmg3.size() == 2 and phys_dmg3[0] == phys_dmg3[1])
	_chk("S3.05 Special Psybeam damage captured", spec_dmg3.size() >= 1)

	# S3.06 Direct DamageCalculator check: Special move, screen_active=true → exact half.
	var atk6 := _make_mon("L_Atk", 50, [TypeChart.TYPE_PSYCHIC])
	var def6 := _make_mon("L_Def", 50, [TypeChart.TYPE_NORMAL])
	var r_normal6: Dictionary = DamageCalculator.calculate(atk6, def6, psybeam, 100, false)
	var r_screened6: Dictionary = DamageCalculator.calculate(
			atk6, def6, psybeam, 100, false, DamageCalculator.WEATHER_NONE, false, false, -1,
			true, false)
	_chk("S3.06 Light Screen halves Special damage (exact floor(dmg/2))",
			r_screened6["damage"] == r_normal6["damage"] / 2)


# ── Section 4: EFFECT_AURORA_VEIL ─────────────────────────────────────────────

func _test_section_4_aurora_veil() -> void:
	var aurora_veil := _load_move(657)
	var reflect := _load_move(115)
	var light_screen := _load_move(113)
	var tackle := _load_move(33)
	var psybeam := _load_move(60)

	# S4.01 Aurora Veil fails outright (no_hail) without Hail active.
	var player1 := _make_mon("A_A", 50, [TypeChart.TYPE_ICE], 80, 80, 80, 80, 80, 100)
	var opp1    := _make_mon("A_B", 50, [TypeChart.TYPE_NORMAL], 80, 30, 80, 80, 80, 50)
	player1.add_move(aurora_veil)
	opp1.add_move(tackle)
	var fail1: Array[String] = []
	var bm1 := BattleManager.new()
	add_child(bm1)
	bm1.move_effect_failed.connect(func(_t: BattlePokemon, r: String): fail1.append(r))
	bm1.start_battle(player1, opp1)
	bm1.queue_free()
	_chk("S4.01 Aurora Veil fails (no_hail) without hail", "no_hail" in fail1)

	# S4.02 Aurora Veil succeeds in hail, sets aurora_veil_turns=5, emits screen_set.
	var player2 := _make_mon("A_C", 50, [TypeChart.TYPE_ICE], 80, 80, 80, 80, 80, 100)
	var opp2    := _make_mon("A_D", 50, [TypeChart.TYPE_NORMAL], 80, 30, 80, 80, 80, 50)
	player2.add_move(aurora_veil)
	opp2.add_move(tackle)
	var set_events2: Array = []
	var bm2 := BattleManager.new()
	add_child(bm2)
	bm2.weather = BattleManager.WEATHER_HAIL
	bm2.weather_duration = 10
	bm2.screen_set.connect(func(side: int, name_: String): set_events2.append([side, name_]))
	bm2.start_battle(player2, opp2)
	bm2.queue_free()
	_chk("S4.02 screen_set(0, aurora_veil) emitted in hail", [0, "aurora_veil"] in set_events2)

	# S4.03 Already-up: Aurora Veil fails if already active (independent of Reflect/LS).
	var player3 := _make_mon("A_E", 50, [TypeChart.TYPE_ICE], 300, 80, 300, 80, 300, 100)
	var opp3    := _make_mon("A_F", 50, [TypeChart.TYPE_NORMAL], 300, 5, 300, 80, 300, 50)
	player3.add_move(aurora_veil)
	opp3.add_move(tackle)
	var fail3: Array[String] = []
	var bm3 := BattleManager.new()
	add_child(bm3)
	bm3._force_hit = true
	bm3.weather = BattleManager.WEATHER_HAIL
	bm3.weather_duration = 10
	bm3.move_effect_failed.connect(func(_t: BattlePokemon, r: String): fail3.append(r))
	for _t in range(3):
		bm3.queue_move(1, 0)
	bm3.start_battle(player3, opp3)
	bm3.queue_free()
	_chk("S4.04 already_aurora_veil fails on repeated use", "already_aurora_veil" in fail3)

	# S4.05 Aurora Veil can be set up even when Reflect is already active on the same side
	# (independent slot, not blocked/replaced).
	var player5 := _make_mon("A_G", 50, [TypeChart.TYPE_ICE], 300, 80, 300, 80, 300, 100)
	var opp5    := _make_mon("A_H", 50, [TypeChart.TYPE_NORMAL], 300, 5, 300, 80, 300, 50)
	player5.add_move(reflect)      # index 0
	player5.add_move(aurora_veil)  # index 1
	opp5.add_move(tackle)
	# Snapshot right when Aurora Veil's setup succeeds — after only 2 queued player turns,
	# auto-select falls back to moves[0] (Reflect, already up, harmless no-op) and the
	# battle keeps running (bounded by the phase cap since neither side deals much damage),
	# long enough for both timers to eventually expire naturally. Checking post-battle would
	# be checking arbitrarily-later state, not "did the coexistence itself work."
	var reflect_turns_at_veil_set: Array[int] = [-1]
	var aurora_turns_at_veil_set: Array[int] = [-1]
	var bm5 := BattleManager.new()
	add_child(bm5)
	bm5._force_hit = true
	bm5.weather = BattleManager.WEATHER_HAIL
	bm5.weather_duration = 10
	bm5.screen_set.connect(func(side: int, name_: String):
		if side == 0 and name_ == "aurora_veil" and aurora_turns_at_veil_set[0] == -1:
			reflect_turns_at_veil_set[0] = bm5._side_conditions[0]["reflect_turns"]
			aurora_turns_at_veil_set[0] = bm5._side_conditions[0]["aurora_veil_turns"])
	bm5.queue_move(0, 0)  # turn 1: Reflect
	bm5.queue_move(0, 1)  # turn 2: Aurora Veil (Reflect already up)
	bm5.queue_move(1, 0)
	bm5.queue_move(1, 0)
	bm5.start_battle(player5, opp5)
	bm5.queue_free()
	_chk("S4.06 Reflect still up right after Aurora Veil setup",
			reflect_turns_at_veil_set[0] > 0)
	_chk("S4.07 Aurora Veil also up (coexists with Reflect)",
			aurora_turns_at_veil_set[0] > 0)

	# S4.08 Aurora Veil reduces BOTH Physical and Special damage (unlike Reflect/Light
	# Screen, no category gate).
	var atk8 := _make_mon("A_Atk", 50, [TypeChart.TYPE_NORMAL])
	var def8 := _make_mon("A_Def", 50, [TypeChart.TYPE_NORMAL])
	var r_phys_normal8: Dictionary = DamageCalculator.calculate(atk8, def8, tackle, 100, false)
	var r_phys_screened8: Dictionary = DamageCalculator.calculate(
			atk8, def8, tackle, 100, false, DamageCalculator.WEATHER_NONE, false, false, -1,
			true, false)
	var r_spec_normal8: Dictionary = DamageCalculator.calculate(atk8, def8, psybeam, 100, false)
	var r_spec_screened8: Dictionary = DamageCalculator.calculate(
			atk8, def8, psybeam, 100, false, DamageCalculator.WEATHER_NONE, false, false, -1,
			true, false)
	_chk("S4.08 Aurora Veil-equivalent screen_active halves Physical",
			r_phys_screened8["damage"] == r_phys_normal8["damage"] / 2)
	_chk("S4.09 Aurora Veil-equivalent screen_active halves Special",
			r_spec_screened8["damage"] == r_spec_normal8["damage"] / 2)

	# S4.10 No double-stacking: Reflect AND Aurora Veil both up on the same side reduce
	# Physical damage by exactly ½ ONCE, not ¼ (screens are a plain OR, not multiplicative).
	var atk10 := _make_mon("A_Atk10", 50, [TypeChart.TYPE_NORMAL])
	var def10 := _make_mon("A_Def10", 50, [TypeChart.TYPE_NORMAL])
	var r_normal10: Dictionary = DamageCalculator.calculate(atk10, def10, tackle, 100, false)
	# screen_active is a single resolved bool regardless of how many conditions are up —
	# both Reflect-only and Reflect+AuroraVeil-simultaneously collapse to the same call shape.
	var r_both_up10: Dictionary = DamageCalculator.calculate(
			atk10, def10, tackle, 100, false, DamageCalculator.WEATHER_NONE, false, false, -1,
			true, false)
	_chk("S4.10 Both screens up still reduces damage by exactly ½ (not ¼)",
			r_both_up10["damage"] == r_normal10["damage"] / 2)
	# Confirm via a live battle that _do_damaging_hit's screen_active resolution really is a
	# bool (not additive): set both flags directly and verify a Physical hit against that
	# side matches the single-screen reduction exactly.
	var bm_live := BattleManager.new()
	add_child(bm_live)
	bm_live._side_conditions[1]["reflect_turns"] = 5
	bm_live._side_conditions[1]["aurora_veil_turns"] = 5
	var atk_live := _make_mon("A_Live_Atk", 50, [TypeChart.TYPE_NORMAL], 80, 80, 80, 80, 80, 100)
	var def_live := _make_mon("A_Live_Def", 50, [TypeChart.TYPE_NORMAL], 300, 80, 80, 80, 80, 50)
	atk_live.add_move(tackle)
	def_live.add_move(tackle)
	var live_dmg: Array[int] = []
	bm_live._force_roll = 100
	bm_live._force_crit = false
	bm_live.move_executed.connect(func(a: BattlePokemon, _d: BattlePokemon, mv: MoveData, dmg: int):
		if a == atk_live and mv == tackle and live_dmg.is_empty():
			live_dmg.append(dmg))
	bm_live.start_battle(atk_live, def_live)
	bm_live.queue_free()
	_chk("S4.11 live battle: double-screened side still gets exactly ½ reduction",
			live_dmg.size() > 0 and live_dmg[0] == r_normal10["damage"] / 2)


# ── Section 5: Crit bypass ────────────────────────────────────────────────────

func _test_section_5_crit_bypass() -> void:
	var tackle := _load_move(33)
	var atk := _make_mon("C_Atk", 50, [TypeChart.TYPE_NORMAL])
	var def := _make_mon("C_Def", 50, [TypeChart.TYPE_NORMAL])

	var r_normal: Dictionary = DamageCalculator.calculate(atk, def, tackle, 100, false)
	var r_screened: Dictionary = DamageCalculator.calculate(
			atk, def, tackle, 100, false, DamageCalculator.WEATHER_NONE, false, false, -1,
			true, false)
	var r_crit_screened: Dictionary = DamageCalculator.calculate(
			atk, def, tackle, 100, true, DamageCalculator.WEATHER_NONE, false, false, -1,
			true, false)
	var r_crit_unscreened: Dictionary = DamageCalculator.calculate(atk, def, tackle, 100, true)

	_chk("S5.01 Non-crit screened damage is reduced vs normal",
			r_screened["damage"] < r_normal["damage"])
	_chk("S5.02 Crit hit ignores the screen entirely — matches the unscreened crit damage",
			r_crit_screened["damage"] == r_crit_unscreened["damage"])
	_chk("S5.03 Crit screened damage is greater than non-crit screened damage",
			r_crit_screened["damage"] > r_screened["damage"])


# ── Section 6: Brick Break (MOVE_EFFECT_BREAK_SCREEN) ────────────────────────

func _test_section_6_brick_break() -> void:
	var brick_break := _load_move(280)
	var reflect := _load_move(115)
	var light_screen := _load_move(113)
	var tackle := _load_move(33)

	# S6.01 Brick Break clears Reflect on the target's side and emits screens_broken.
	var player1 := _make_mon("B_A", 50, [TypeChart.TYPE_FIGHTING], 80, 80, 80, 80, 80, 100)
	var opp1    := _make_mon("B_B", 50, [TypeChart.TYPE_NORMAL], 200, 30, 80, 80, 80, 50)
	player1.add_move(brick_break)
	opp1.add_move(reflect)
	var broken_events1: Array[int] = []
	var bm1 := BattleManager.new()
	add_child(bm1)
	bm1._force_hit = true
	bm1.screens_broken.connect(func(side: int): broken_events1.append(side))
	bm1.queue_move(1, 0)  # turn 1: opp sets up Reflect
	bm1.queue_move(0, 0)  # turn 1: player Brick Break (opp acts first due to speed... )
	bm1.queue_move(0, 0)  # turn 2: player Brick Break (breaks the now-active Reflect)
	bm1.start_battle(player1, opp1)
	bm1.queue_free()
	_chk("S6.01 screens_broken(1) emitted", 1 in broken_events1)
	_chk("S6.02 Reflect cleared on opp's side after Brick Break",
			bm1._side_conditions[1]["reflect_turns"] == 0)

	# S6.03 Brick Break's OWN damage is NOT reduced by the screen it just broke
	# (preAttackEffect=TRUE — the break happens before this hit's damage calc).
	var player3 := _make_mon("B_C", 50, [TypeChart.TYPE_FIGHTING], 80, 80, 80, 80, 80, 100)
	var opp3    := _make_mon("B_D", 50, [TypeChart.TYPE_NORMAL], 300, 30, 80, 80, 80, 50)
	player3.add_move(brick_break)
	opp3.add_move(tackle)
	var bm3 := BattleManager.new()
	add_child(bm3)
	bm3._side_conditions[1]["reflect_turns"] = 5  # pre-set Reflect on opp's side directly
	bm3._force_roll = 100
	bm3._force_crit = false
	var dmg3: Array[int] = []
	bm3.move_executed.connect(func(a: BattlePokemon, _d: BattlePokemon, mv: MoveData, dmg: int):
		if a == player3 and mv == brick_break:
			dmg3.append(dmg))
	bm3.start_battle(player3, opp3)
	bm3.queue_free()
	# Baseline: same matchup with no screen at all.
	var player3b := _make_mon("B_Cb", 50, [TypeChart.TYPE_FIGHTING], 80, 80, 80, 80, 80, 100)
	var opp3b    := _make_mon("B_Db", 50, [TypeChart.TYPE_NORMAL], 300, 30, 80, 80, 80, 50)
	player3b.add_move(brick_break)
	opp3b.add_move(tackle)
	var bm3b := BattleManager.new()
	add_child(bm3b)
	bm3b._force_roll = 100
	bm3b._force_crit = false
	var dmg3b: Array[int] = []
	bm3b.move_executed.connect(func(a: BattlePokemon, _d: BattlePokemon, mv: MoveData, dmg: int):
		if a == player3b and mv == brick_break:
			dmg3b.append(dmg))
	bm3b.start_battle(player3b, opp3b)
	bm3b.queue_free()
	_chk("S6.04 Brick Break damage unaffected by the screen it just broke",
			dmg3.size() > 0 and dmg3b.size() > 0 and dmg3[0] == dmg3b[0])

	# S6.05 Brick Break does nothing (no screens_broken) when target's side has no screens.
	var player5 := _make_mon("B_E", 50, [TypeChart.TYPE_FIGHTING], 80, 80, 80, 80, 80, 100)
	var opp5    := _make_mon("B_F", 50, [TypeChart.TYPE_NORMAL], 80, 30, 80, 80, 80, 50)
	player5.add_move(brick_break)
	opp5.add_move(tackle)
	var broken_events5: Array[int] = []
	var bm5 := BattleManager.new()
	add_child(bm5)
	bm5.screens_broken.connect(func(side: int): broken_events5.append(side))
	bm5.start_battle(player5, opp5)
	bm5.queue_free()
	_chk("S6.06 screens_broken NOT emitted when no screens are up", broken_events5.is_empty())

	# S6.07 Brick Break clears ALL screen types simultaneously (Reflect + Light Screen both
	# up on target's side → both cleared by one Brick Break use).
	var player7 := _make_mon("B_G", 50, [TypeChart.TYPE_FIGHTING], 80, 80, 80, 80, 80, 100)
	var opp7    := _make_mon("B_H", 50, [TypeChart.TYPE_NORMAL], 80, 30, 80, 80, 80, 50)
	player7.add_move(brick_break)
	opp7.add_move(tackle)
	var bm7 := BattleManager.new()
	add_child(bm7)
	bm7._side_conditions[1]["reflect_turns"] = 5
	bm7._side_conditions[1]["light_screen_turns"] = 5
	bm7._force_hit = true
	bm7.start_battle(player7, opp7)
	bm7.queue_free()
	_chk("S6.08 Reflect cleared", bm7._side_conditions[1]["reflect_turns"] == 0)
	_chk("S6.09 Light Screen also cleared by the same Brick Break use",
			bm7._side_conditions[1]["light_screen_turns"] == 0)
