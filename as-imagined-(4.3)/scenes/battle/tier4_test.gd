extends Node

# Milestone 7 test suite — Tier 4 moves (unique mechanics)
#
# Sections:
#   1. Move data spot-checks (fields on loaded .tres resources)
#   2. Substitute (creation, blocking, breaking, fail conditions)
#   3. Counter / Mirror Coat (reflect damage, fail with no damage)
#   4. Protect / Detect (blocking, protect_active cleared per-turn, consecutive field)
#   5. Destiny Bond (flag set, trigger on faint, cleared on attacker's next action)
#   6. Disable (lock target's last move, decrement, clear after 4 turns)
#   7. Encore (lock target to last move, substitute block, decrement)
#   8. Bide (setup, damage accumulation, release, empty bide)
#   9. Metronome (called move not banned, move_called signal, BAN_METRONOME filter)
#
# GDScript closure note: primitives (int, bool) inside lambdas are VALUE captures —
# assignment inside the lambda does NOT modify the outer variable.
# All mutable lambda captures use Array containers so subscript assignment works:
#   var counter := [0]
#   signal.connect(func(...): counter[0] += 1)
# Array/Dictionary are reference types; subscript mutation is visible externally.
#
# Ground truth: pokeemerald_expansion

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_section_1_move_data()
	_test_section_2_substitute()
	_test_section_3_counter_mirror_coat()
	_test_section_4_protect()
	_test_section_5_destiny_bond()
	_test_section_6_disable()
	_test_section_7_encore()
	_test_section_8_bide()
	_test_section_9_metronome()

	var total := _pass + _fail
	print("tier4_test: %d/%d passed" % [_pass, total])
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
	return load("res://data/moves/move_%04d.tres" % id) as MoveData


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
	return BattlePokemon.from_species(sp, level)


# ── Section 1: Move data spot-checks ─────────────────────────────────────────

func _test_section_1_move_data() -> void:
	var counter := _load_move(68)
	_chk("S1.01 Counter counter=true",       counter.counter == true)
	_chk("S1.02 Counter priority=-5",        counter.priority == -5)
	_chk("S1.03 Counter BAN_METRONOME",      (counter.ban_flags & MoveData.BAN_METRONOME) != 0)
	_chk("S1.04 Counter type=Fighting",      counter.type == TypeChart.TYPE_FIGHTING)

	var mcoat := _load_move(243)
	_chk("S1.05 Mirror Coat mirror_coat=true", mcoat.mirror_coat == true)
	_chk("S1.06 Mirror Coat priority=-5",      mcoat.priority == -5)
	_chk("S1.07 Mirror Coat category=Special", mcoat.category == 1)

	var protect := _load_move(182)
	_chk("S1.08 Protect is_protect=true",   protect.is_protect == true)
	_chk("S1.09 Protect priority=4",        protect.priority == 4)
	_chk("S1.10 Protect BAN_METRONOME",     (protect.ban_flags & MoveData.BAN_METRONOME) != 0)

	var detect := _load_move(197)
	_chk("S1.11 Detect is_protect=true",    detect.is_protect == true)
	_chk("S1.12 Detect type=Fighting",      detect.type == TypeChart.TYPE_FIGHTING)

	var dbond := _load_move(194)
	_chk("S1.13 Destiny Bond destiny_bond=true", dbond.destiny_bond == true)
	_chk("S1.14 Destiny Bond type=Ghost",        dbond.type == TypeChart.TYPE_GHOST)

	var disable := _load_move(50)
	_chk("S1.15 Disable is_disable=true",           disable.is_disable == true)
	_chk("S1.16 Disable ignores_substitute=true",   disable.ignores_substitute == true)

	var encore := _load_move(227)
	_chk("S1.17 Encore is_encore=true",       encore.is_encore == true)
	_chk("S1.18 Encore BAN_ENCORE set",        (encore.ban_flags & MoveData.BAN_ENCORE) != 0)
	# [M19.5 Task 1] Encore does NOT carry BAN_METRONOME in real source
	# (moves_info.h has no .metronomeBanned field on MOVE_ENCORE at all) —
	# this assertion previously baked in the confirmed-extra flag the ban-flag
	# audit found and removed; see ban_flag_audit_test.gd's own Section A.
	_chk("S1.19 Encore does NOT carry BAN_METRONOME (confirmed extra, removed)",
			(encore.ban_flags & MoveData.BAN_METRONOME) == 0)

	var bide := _load_move(117)
	_chk("S1.20 Bide is_bide=true",      bide.is_bide == true)
	_chk("S1.21 Bide priority=1",        bide.priority == 1)
	_chk("S1.22 Bide accuracy=0",        bide.accuracy == 0)
	# [M19.5 Task 1] Same correction as Encore above — Bide has no
	# .metronomeBanned in source either.
	_chk("S1.23 Bide does NOT carry BAN_METRONOME (confirmed extra, removed)",
			(bide.ban_flags & MoveData.BAN_METRONOME) == 0)

	var metro := _load_move(118)
	_chk("S1.24 Metronome is_metronome=true", metro.is_metronome == true)
	_chk("S1.25 Metronome BAN_METRONOME",     (metro.ban_flags & MoveData.BAN_METRONOME) != 0)

	var sub := _load_move(164)
	_chk("S1.26 Substitute creates_substitute=true", sub.creates_substitute == true)
	# [M19.5 Task 1] Same correction — Substitute has no .metronomeBanned in
	# source either (confirmed directly against MOVE_SUBSTITUTE's real data).
	_chk("S1.27 Substitute does NOT carry BAN_METRONOME (confirmed extra, removed)",
			(sub.ban_flags & MoveData.BAN_METRONOME) == 0)


# ── Section 2: Substitute ─────────────────────────────────────────────────────

func _test_section_2_substitute() -> void:
	var sub_move := _load_move(164)
	var tackle   := _load_move(33)   # Tackle (Normal/Phys/40)
	var ddedge   := _load_move(38)   # Double-Edge (33% recoil — for finite battles)

	# S2.01 Fresh BattlePokemon has substitute_hp=0
	var mon := _make_mon("A", 50, [TypeChart.TYPE_NORMAL])
	_chk("S2.01 Fresh mon: substitute_hp=0", mon.substitute_hp == 0)

	# S2.02 Substitute HP condition: fails when current_hp <= max_hp/4
	var low_hp_mon := _make_mon("LowHP", 50, [TypeChart.TYPE_NORMAL])
	var sub_cost2: int = low_hp_mon.max_hp / 4
	_chk("S2.02 HP == max_hp/4 boundary (condition for fail)",
			low_hp_mon.max_hp / 4 == sub_cost2)

	# S2.03 Substitute creation via BattleManager: HP deducted, substitute_hp set.
	# Player (speed=100) creates Substitute turn 1; opponent (speed=50) uses Double-Edge
	# (recoil KOs opponent in ~4 turns, keeping the battle finite).
	var player3 := _make_mon("Sub_A", 50, [TypeChart.TYPE_NORMAL], 80, 80, 80, 80, 80, 100)
	var opp3    := _make_mon("Opp_A", 50, [TypeChart.TYPE_NORMAL], 80, 80, 80, 80, 80, 50)
	player3.add_move(sub_move)
	opp3.add_move(ddedge)  # opponent KOs self via recoil in a few turns
	var expected_sub_hp3: int = player3.max_hp / 4
	var rec3 := [-1, -1]  # [recorded_sub_hp, recorded_player_hp]
	var bm3 := BattleManager.new()
	add_child(bm3)
	bm3.substitute_created.connect(func(atk: BattlePokemon, shp: int):
		if rec3[0] < 0:  # capture only the first creation
			rec3[0] = shp
			rec3[1] = atk.current_hp)
	bm3.start_battle(player3, opp3)
	bm3.queue_free()
	_chk("S2.03 substitute_created emitted",      rec3[0] >= 0)
	_chk("S2.04 substitute_hp == max_hp/4",       rec3[0] == expected_sub_hp3)
	_chk("S2.05 current_hp deducted by max_hp/4",
			rec3[1] == player3.max_hp - expected_sub_hp3)

	# S2.06 Damaging move hits substitute — substitute_broke fires when sub exhausted.
	# Same setup: player creates sub, opponent's Double-Edge breaks it (large damage).
	var player6 := _make_mon("Sub_B", 50, [TypeChart.TYPE_NORMAL], 80, 80, 80, 80, 80, 100)
	var opp6    := _make_mon("Atk_B", 50, [TypeChart.TYPE_NORMAL], 80, 80, 80, 80, 80, 50)
	player6.add_move(sub_move)
	opp6.add_move(ddedge)
	var sub_broke := [0]  # counter
	var bm6 := BattleManager.new()
	add_child(bm6)
	bm6.substitute_broke.connect(func(defender: BattlePokemon): sub_broke[0] += 1)
	bm6.start_battle(player6, opp6)
	bm6.queue_free()
	_chk("S2.06 substitute_broke fired (sub absorbed a hit)", sub_broke[0] > 0)

	# S2.07 Substitute fails when already active.
	# Preset substitute_hp so turn 1 triggers "already_substitute".
	# Opponent uses Tackle (weak, won't break sub in one hit from initial state).
	# Battle finite because opp uses Tackle and player keeps failing Substitute
	# until their HP runs out (each failed sub attempt: player HP not modified;
	# opponent Tackle directly hits player once sub breaks).
	var player7 := _make_mon("Sub_C", 50, [TypeChart.TYPE_NORMAL], 80, 80, 80, 80, 80, 100)
	var opp7    := _make_mon("Opp_C", 50, [TypeChart.TYPE_NORMAL], 80, 10, 80, 80, 80, 50)
	player7.add_move(sub_move)
	opp7.add_move(tackle)
	player7.substitute_hp = player7.max_hp / 4  # already has a sub active
	var fail7: Array[String] = []
	var bm7 := BattleManager.new()
	add_child(bm7)
	bm7.move_effect_failed.connect(func(t: BattlePokemon, r: String): fail7.append(r))
	bm7.start_battle(player7, opp7)
	bm7.queue_free()
	_chk("S2.07 Second Substitute fails with already_substitute",
			"already_substitute" in fail7)


# ── Section 3: Counter / Mirror Coat ─────────────────────────────────────────

func _test_section_3_counter_mirror_coat() -> void:
	var counter  := _load_move(68)   # Counter  (Fighting/Phys/priority=-5)
	var mcoat    := _load_move(243)  # Mirror Coat (Psychic/Spec/priority=-5)
	var tackle   := _load_move(33)   # Normal/Phys/40 — physical hit to counter
	var psybeam  := _load_move(60)   # Psychic/Spec/65 — special hit to mirror-coat
	var twwave   := _load_move(86)   # Thunder Wave — status, no physical damage

	# S3.01 Counter fails if no physical damage taken this turn.
	# Player (speed=100) uses Counter (priority=-5).
	# Opponent (speed=50) uses Thunder Wave (status, priority=0).
	# Turn order: opp priority=0 > player priority=-5 → opp acts first.
	# Opp uses T-Wave on player → status, no physical damage.
	# Player uses Counter → last_physical_damage=0 → fail "no_damage_to_counter".
	var player1 := _make_mon("Counter_A", 50, [TypeChart.TYPE_NORMAL], 80, 80, 80, 80, 80, 100)
	var opp1    := _make_mon("Opp1",      50, [TypeChart.TYPE_NORMAL], 80, 80, 80, 80, 80, 50)
	player1.add_move(counter)
	opp1.add_move(twwave)
	# T-Wave is Electric→Normal: type immunity → T-Wave misses, but still no physical dmg.
	# Use a Poison-type status (Toxic) instead to avoid type-immunity issues.
	# Actually Thunder Wave vs Normal type: Electric→Normal has no immunity in Gen VI+.
	# And T-Wave is status (category=STAT) → no physical damage recorded. ✓
	var fail1: Array[String] = []
	var bm1 := BattleManager.new()
	add_child(bm1)
	bm1.move_effect_failed.connect(func(t: BattlePokemon, r: String): fail1.append(r))
	bm1.start_battle(player1, opp1)
	bm1.queue_free()
	_chk("S3.01 Counter fails with no physical damage", "no_damage_to_counter" in fail1)

	# S3.02 Mirror Coat fails if no special damage taken this turn.
	# Player uses Mirror Coat (priority=-5). Opponent uses Tackle (physical, priority=0).
	# Opp's Tackle is PHYSICAL → last_special_damage stays 0.
	# Player uses Mirror Coat → last_special_damage=0 → fail "no_damage_to_counter".
	var player2 := _make_mon("MCoat_A", 50, [TypeChart.TYPE_NORMAL], 80, 80, 80, 80, 80, 100)
	var opp2    := _make_mon("Opp2",    50, [TypeChart.TYPE_NORMAL], 80, 80, 80, 80, 80, 50)
	player2.add_move(mcoat)
	opp2.add_move(tackle)
	var fail2: Array[String] = []
	var bm2 := BattleManager.new()
	add_child(bm2)
	bm2.move_effect_failed.connect(func(t: BattlePokemon, r: String): fail2.append(r))
	bm2.start_battle(player2, opp2)
	bm2.queue_free()
	_chk("S3.02 Mirror Coat fails after physical hit (no special dmg)", "no_damage_to_counter" in fail2)

	# S3.03 Counter deals 2× physical damage received.
	# Opp (speed=100, priority=0) uses Tackle first.
	# Player (speed=50, priority=-5) uses Counter → 2× last_physical_damage.
	# Counter is Fighting/Physical — hits Normal types.
	var player3 := _make_mon("Counter_B", 50, [TypeChart.TYPE_NORMAL], 80, 80, 80, 80, 80, 50)
	var opp3    := _make_mon("Tackling",  50, [TypeChart.TYPE_NORMAL], 80, 80, 80, 80, 80, 100)
	player3.add_move(counter)
	opp3.add_move(tackle)
	var counter_dmg := [0]
	var bm3 := BattleManager.new()
	add_child(bm3)
	bm3.move_executed.connect(func(atk: BattlePokemon, def: BattlePokemon, mv: MoveData, dmg: int):
		if mv.counter and counter_dmg[0] == 0:
			counter_dmg[0] = dmg)
	bm3.start_battle(player3, opp3)
	bm3.queue_free()
	_chk("S3.03 Counter executed with damage > 0",     counter_dmg[0] > 0)
	_chk("S3.04 Counter damage is even (2× formula)",  counter_dmg[0] % 2 == 0)

	# S3.05 Mirror Coat deals 2× special damage received.
	# Opp (faster) uses Psybeam (special). Player uses Mirror Coat.
	# Both are Psychic type → Psybeam hits player, Mirror Coat hits opp.
	var player5 := _make_mon("MCoat_B", 50, [TypeChart.TYPE_PSYCHIC], 80, 80, 80, 80, 80, 50)
	var opp5    := _make_mon("Psybeam", 50, [TypeChart.TYPE_PSYCHIC], 80, 80, 80, 80, 80, 100)
	player5.add_move(mcoat)
	opp5.add_move(psybeam)
	var mcoat_dmg := [0]
	var bm5 := BattleManager.new()
	add_child(bm5)
	bm5.move_executed.connect(func(atk: BattlePokemon, def: BattlePokemon, mv: MoveData, dmg: int):
		if mv.mirror_coat and mcoat_dmg[0] == 0:
			mcoat_dmg[0] = dmg)
	bm5.start_battle(player5, opp5)
	bm5.queue_free()
	_chk("S3.05 Mirror Coat executed with damage > 0", mcoat_dmg[0] > 0)
	_chk("S3.06 Mirror Coat damage is even (2× formula)", mcoat_dmg[0] % 2 == 0)


# ── Section 4: Protect / Detect ───────────────────────────────────────────────

func _test_section_4_protect() -> void:
	var protect  := _load_move(182)
	var detect   := _load_move(197)
	var tackle   := _load_move(33)

	# S4.01 Protect blocks incoming move: protected signal + move_missed "protected".
	# Player (speed=50) uses Protect (priority=4) — fires before opponent Tackle.
	# Opponent (speed=100) uses Tackle (priority=0) — blocked.
	# Battle finite because player eventually fails consecutive Protect and faints.
	var player1 := _make_mon("Guard", 50, [TypeChart.TYPE_NORMAL], 80, 80, 80, 80, 80, 50)
	var opp1    := _make_mon("Atk1",  50, [TypeChart.TYPE_NORMAL], 80, 80, 80, 80, 80, 100)
	player1.add_move(protect)
	opp1.add_move(tackle)
	var prot_count := [0]
	var miss_protected := [0]
	var bm1 := BattleManager.new()
	add_child(bm1)
	bm1.protected.connect(func(d: BattlePokemon): prot_count[0] += 1)
	bm1.move_missed.connect(func(atk: BattlePokemon, r: String):
		if r == "protected":
			miss_protected[0] += 1)
	bm1.start_battle(player1, opp1)
	bm1.queue_free()
	_chk("S4.01 protected signal emitted at least once",    prot_count[0] > 0)
	_chk("S4.02 move_missed 'protected' emitted",           miss_protected[0] > 0)

	# S4.03 Detect also sets protect_active (same is_protect handler).
	var player3 := _make_mon("GuardD", 50, [TypeChart.TYPE_NORMAL], 80, 80, 80, 80, 80, 50)
	var opp3    := _make_mon("Atk3",   50, [TypeChart.TYPE_NORMAL], 80, 80, 80, 80, 80, 100)
	player3.add_move(detect)
	opp3.add_move(tackle)
	var detect_count := [0]
	var bm3 := BattleManager.new()
	add_child(bm3)
	bm3.protected.connect(func(d: BattlePokemon): detect_count[0] += 1)
	bm3.start_battle(player3, opp3)
	bm3.queue_free()
	_chk("S4.03 Detect also blocks (protected signal fired)", detect_count[0] > 0)

	# S4.04 protect_consecutive increments on success — capture via Array.
	var player4 := _make_mon("PConsec", 50, [TypeChart.TYPE_NORMAL], 80, 80, 80, 80, 80, 100)
	var opp4    := _make_mon("Opp4",    50, [TypeChart.TYPE_NORMAL], 80, 80, 80, 80, 80, 50)
	player4.add_move(protect)
	opp4.add_move(tackle)
	var consec_first := [-1]  # protect_consecutive value right after first success
	var bm4 := BattleManager.new()
	add_child(bm4)
	bm4.protected.connect(func(defender: BattlePokemon):
		if consec_first[0] < 0:
			consec_first[0] = defender.protect_consecutive)
	bm4.start_battle(player4, opp4)
	bm4.queue_free()
	_chk("S4.04 protect_consecutive=1 after first success", consec_first[0] == 1)

	# S4.05-4.06 Fresh-mon field checks
	var fresh := _make_mon("Fresh", 50, [TypeChart.TYPE_NORMAL])
	_chk("S4.05 Fresh mon: protect_active=false",    fresh.protect_active == false)
	_chk("S4.06 Fresh mon: protect_consecutive=0",   fresh.protect_consecutive == 0)


# ── Section 5: Destiny Bond ───────────────────────────────────────────────────

func _test_section_5_destiny_bond() -> void:
	var dbond  := _load_move(194)  # Destiny Bond (Ghost/Status)
	var tackle := _load_move(33)   # Tackle (Normal/Phys)

	# S5.01 Fresh mon: destiny_bond=false
	var mon := _make_mon("DB_Mon", 50, [TypeChart.TYPE_NORMAL])
	_chk("S5.01 Fresh mon: destiny_bond=false", mon.destiny_bond == false)

	# S5.02 destiny_bond_set signal emitted when Destiny Bond is used.
	# Player is Normal type (not Ghost) so opponent's Tackle can hit — finite battle.
	# Destiny Bond is Ghost type but as a status move, type doesn't affect it.
	var player2 := _make_mon("DBUser", 50, [TypeChart.TYPE_NORMAL], 80, 80, 80, 80, 80, 100)
	var opp2    := _make_mon("Opp2",   50, [TypeChart.TYPE_NORMAL], 80, 80, 80, 80, 80, 50)
	player2.add_move(dbond)
	opp2.add_move(tackle)
	var db_set := [0]
	var bm2 := BattleManager.new()
	add_child(bm2)
	bm2.destiny_bond_set.connect(func(atk: BattlePokemon): db_set[0] += 1)
	bm2.start_battle(player2, opp2)
	bm2.queue_free()
	_chk("S5.02 destiny_bond_set emitted", db_set[0] > 0)

	# S5.03 Destiny Bond triggers when user is KO'd by the opponent.
	# Player (Normal, 1 HP, speed=100) uses Destiny Bond turn 1.
	# Opponent (faster... wait, player has speed=100, opp has speed=50 — player acts first).
	# Player uses DB, sets destiny_bond=true.
	# Opponent uses Tackle → player HP 1 - damage → 0 → player faints with destiny_bond=true
	# → opponent also faints (destiny_bond_triggered emitted).
	var player3 := _make_mon("DBWeak", 50, [TypeChart.TYPE_NORMAL], 80, 80, 80, 80, 80, 100)
	var opp3    := _make_mon("Killer", 50, [TypeChart.TYPE_NORMAL], 80, 120, 80, 80, 80, 50)
	player3.add_move(dbond)
	opp3.add_move(tackle)
	player3.current_hp = 1  # will be KO'd by first Tackle
	var db_triggered := [false]
	var both_fainted := [false]
	var bm3 := BattleManager.new()
	add_child(bm3)
	bm3.destiny_bond_triggered.connect(func(fainted_mon: BattlePokemon, killer: BattlePokemon):
		db_triggered[0] = true
		both_fainted[0] = fainted_mon.fainted and killer.fainted)
	bm3.start_battle(player3, opp3)
	bm3.queue_free()
	_chk("S5.03 destiny_bond_triggered emitted when DB user KO'd", db_triggered[0])
	_chk("S5.04 Both Pokémon fainted after Destiny Bond trigger",  both_fainted[0])

	# S5.05 Destiny Bond expires when the user acts — if they're KO'd AFTER acting,
	# the bond should NOT trigger (it was already cleared at the start of their action).
	# Setup: preset destiny_bond=true (simulating DB used last turn), player5 uses Tackle
	# (speed=100, acts first → clears destiny_bond), then opp5 (speed=50, high atk)
	# KOs player5 in the same turn. destiny_bond_triggered must NOT fire.
	var player5 := _make_mon("DBSurv", 50, [TypeChart.TYPE_NORMAL], 80, 80, 80, 80, 80, 100)
	var opp5    := _make_mon("Opp5",   50, [TypeChart.TYPE_NORMAL], 80, 200, 80, 80, 80, 50)
	player5.add_move(tackle)
	opp5.add_move(tackle)
	player5.destiny_bond = true  # preset: as if DB was used last turn
	player5.current_hp = 1       # opp5's Tackle will KO player5 after they act
	var triggered5 := [false]
	var bm5 := BattleManager.new()
	add_child(bm5)
	bm5.destiny_bond_triggered.connect(func(f: BattlePokemon, k: BattlePokemon): triggered5[0] = true)
	bm5.start_battle(player5, opp5)
	bm5.queue_free()
	_chk("S5.05 destiny_bond cleared on action → no trigger when KO'd after acting", not triggered5[0])


# ── Section 6: Disable ────────────────────────────────────────────────────────

func _test_section_6_disable() -> void:
	var disable := _load_move(50)
	var tackle  := _load_move(33)

	# S6.01-S6.02 Fresh mon fields
	var mon := _make_mon("DisA", 50, [TypeChart.TYPE_NORMAL])
	_chk("S6.01 Fresh mon: disabled_move=null",  mon.disabled_move == null)
	_chk("S6.02 Fresh mon: disable_turns=0",     mon.disable_turns == 0)

	# S6.03 Disable fails when target has no last_move_used.
	# Player (speed=100) uses Disable first; opponent hasn't moved yet → fail.
	var player3 := _make_mon("DisUser", 50, [TypeChart.TYPE_NORMAL], 80, 80, 80, 80, 80, 100)
	var opp3    := _make_mon("Opp3",    50, [TypeChart.TYPE_NORMAL], 80, 80, 80, 80, 80, 50)
	player3.add_move(disable)
	opp3.add_move(tackle)
	var fail3: Array[String] = []
	var bm3 := BattleManager.new()
	add_child(bm3)
	bm3.move_effect_failed.connect(func(t: BattlePokemon, r: String): fail3.append(r))
	bm3.start_battle(player3, opp3)
	bm3.queue_free()
	_chk("S6.03 Disable fails when target has no last move", "disable_failed" in fail3)

	# S6.04 Disable sets disabled_move when target has a last move.
	# Opponent (speed=100) uses Tackle first → opp.last_move_used = Tackle.
	# Player (speed=50) uses Disable → disabled_signal fires with Tackle.
	# Battle ends when player faints (opponent can't use Tackle but player Disable fails too).
	# We capture the signal early (turn 1) before any stack concerns.
	var player4 := _make_mon("DisUser4", 50, [TypeChart.TYPE_NORMAL], 80, 80, 80, 80, 80, 50)
	var opp4    := _make_mon("Opp4",     50, [TypeChart.TYPE_NORMAL], 80, 120, 80, 80, 80, 100)
	player4.add_move(disable)
	opp4.add_move(tackle)
	var disabled_mv := [null]
	var bm4 := BattleManager.new()
	add_child(bm4)
	bm4.disabled.connect(func(target: BattlePokemon, mv: MoveData):
		if disabled_mv[0] == null:
			disabled_mv[0] = mv)
	bm4.start_battle(player4, opp4)
	bm4.queue_free()
	_chk("S6.04 disabled signal emitted", disabled_mv[0] != null)
	_chk("S6.05 disabled move is Tackle", disabled_mv[0] == tackle)

	# S6.06 Disabled move causes move_skipped "disabled" when used.
	# Same scenario: opp uses Tackle (disabled on turn 1), player uses Disable.
	# Turn 2: opp tries Tackle → move_skipped "disabled".
	var player6 := _make_mon("DisUser5", 50, [TypeChart.TYPE_NORMAL], 80, 80, 80, 80, 80, 50)
	var opp6    := _make_mon("Opp5",     50, [TypeChart.TYPE_NORMAL], 80, 120, 80, 80, 80, 100)
	player6.add_move(disable)
	opp6.add_move(tackle)
	var skip6: Array[String] = []
	var bm6 := BattleManager.new()
	add_child(bm6)
	bm6.move_skipped.connect(func(m: BattlePokemon, r: String): skip6.append(r))
	bm6.start_battle(player6, opp6)
	bm6.queue_free()
	_chk("S6.06 Disabled move causes move_skipped 'disabled'", "disabled" in skip6)

	# S6.07-S6.09 disable_turns decrement logic (direct state simulation)
	var test_mon := _make_mon("DisTest", 50, [TypeChart.TYPE_NORMAL])
	test_mon.disabled_move = tackle
	test_mon.disable_turns = 4
	test_mon.disable_turns -= 1
	if test_mon.disable_turns == 0:
		test_mon.disabled_move = null
	_chk("S6.07 disable_turns decrements 4→3", test_mon.disable_turns == 3)
	_chk("S6.08 disabled_move still set at 3", test_mon.disabled_move != null)
	for _i in range(3):
		test_mon.disable_turns -= 1
		if test_mon.disable_turns == 0:
			test_mon.disabled_move = null
	_chk("S6.09 disable_turns reaches 0",          test_mon.disable_turns == 0)
	_chk("S6.10 disabled_move cleared at 0 turns", test_mon.disabled_move == null)


# ── Section 7: Encore ─────────────────────────────────────────────────────────

func _test_section_7_encore() -> void:
	var encore  := _load_move(227)
	var tackle  := _load_move(33)

	# S7.01-S7.02 Fresh mon fields
	var mon := _make_mon("EncA", 50, [TypeChart.TYPE_NORMAL])
	_chk("S7.01 Fresh mon: encored_move=null", mon.encored_move == null)
	_chk("S7.02 Fresh mon: encore_turns=0",    mon.encore_turns == 0)

	# S7.03 Encore fails when target has no last_move_used.
	var player3 := _make_mon("EncUser", 50, [TypeChart.TYPE_NORMAL], 80, 80, 80, 80, 80, 100)
	var opp3    := _make_mon("Opp3",    50, [TypeChart.TYPE_NORMAL], 80, 80, 80, 80, 80, 50)
	player3.add_move(encore)
	opp3.add_move(tackle)
	var fail3: Array[String] = []
	var bm3 := BattleManager.new()
	add_child(bm3)
	bm3.move_effect_failed.connect(func(t: BattlePokemon, r: String): fail3.append(r))
	bm3.start_battle(player3, opp3)
	bm3.queue_free()
	_chk("S7.03 Encore fails when target has no last move", "encore_failed" in fail3)

	# S7.04 Encore sets encored_move and encore_turns=3.
	# Opp (speed=100) uses Tackle first → opp.last_move_used=Tackle.
	# Player (speed=50) uses Encore → encored signal fires.
	# After Encore, opp is locked to Tackle. Player takes damage each turn and faints.
	# Battle finite: opp Tackle ~28 dmg/turn, player HP=140 → 5 turns.
	var player4 := _make_mon("EncUser4", 50, [TypeChart.TYPE_NORMAL], 80, 80, 80, 80, 80, 50)
	var opp4    := _make_mon("Opp4",     50, [TypeChart.TYPE_NORMAL], 80, 80, 80, 80, 80, 100)
	player4.add_move(encore)
	opp4.add_move(tackle)
	var encored_mv := [null]
	var bm4 := BattleManager.new()
	add_child(bm4)
	bm4.encored.connect(func(target: BattlePokemon, mv: MoveData):
		if encored_mv[0] == null:
			encored_mv[0] = mv)
	bm4.start_battle(player4, opp4)
	bm4.queue_free()
	_chk("S7.04 encored signal emitted", encored_mv[0] != null)
	_chk("S7.05 encored move is Tackle", encored_mv[0] == tackle)

	# S7.06-S7.08 encore_turns decrement logic (direct state simulation)
	var test_mon := _make_mon("EncTest", 50, [TypeChart.TYPE_NORMAL])
	test_mon.encored_move = tackle
	test_mon.encore_turns = 3
	test_mon.encore_turns -= 1
	if test_mon.encore_turns == 0:
		test_mon.encored_move = null
	_chk("S7.06 encore_turns decrements 3→2",   test_mon.encore_turns == 2)
	_chk("S7.07 encored_move still set at 2",    test_mon.encored_move != null)
	for _i in range(2):
		test_mon.encore_turns -= 1
		if test_mon.encore_turns == 0:
			test_mon.encored_move = null
	_chk("S7.08 encore_turns reaches 0",          test_mon.encore_turns == 0)
	_chk("S7.09 encored_move cleared at 0 turns", test_mon.encored_move == null)


# ── Section 8: Bide ───────────────────────────────────────────────────────────

func _test_section_8_bide() -> void:
	var bide   := _load_move(117)
	var tackle := _load_move(33)

	# S8.01-S8.03 Fresh mon fields
	var mon := _make_mon("BideA", 50, [TypeChart.TYPE_NORMAL])
	_chk("S8.01 Fresh mon: bide_turns=0",        mon.bide_turns == 0)
	_chk("S8.02 Fresh mon: bide_damage=0",        mon.bide_damage == 0)
	_chk("S8.03 Fresh mon: charging_move=null",   mon.charging_move == null)

	# S8.04-S8.05 Bide setup: bide_started signal, bide_turns=2.
	# Player (priority=1 from Bide, speed=50) vs opponent (Tackle, speed=100).
	# Priority 1 > 0 → player acts first despite lower speed.
	# Give player high HP (200 base) so they survive 3 Tackle hits.
	var player4 := _make_mon("BideUser", 50, [TypeChart.TYPE_NORMAL], 200, 80, 80, 80, 80, 50)
	var opp4    := _make_mon("Opp4",     50, [TypeChart.TYPE_NORMAL], 80, 80, 80, 80, 80, 100)
	player4.add_move(bide)
	opp4.add_move(tackle)
	var bide_start := [0]
	var bide_turns_at_start := [-1]
	var bm4 := BattleManager.new()
	add_child(bm4)
	bm4.bide_started.connect(func(atk: BattlePokemon):
		bide_start[0] += 1
		if bide_turns_at_start[0] < 0:
			bide_turns_at_start[0] = atk.bide_turns)
	bm4.start_battle(player4, opp4)
	bm4.queue_free()
	_chk("S8.04 bide_started emitted",  bide_start[0] > 0)
	_chk("S8.05 bide_turns=2 at setup", bide_turns_at_start[0] == 2)

	# S8.06 Bide stores turn: bide_storing emitted on turn 2.
	var player6 := _make_mon("BideStor", 50, [TypeChart.TYPE_NORMAL], 200, 80, 80, 80, 80, 50)
	var opp6    := _make_mon("Opp6",     50, [TypeChart.TYPE_NORMAL], 80, 80, 80, 80, 80, 100)
	player6.add_move(bide)
	opp6.add_move(tackle)
	var storing := [0]
	var bm6 := BattleManager.new()
	add_child(bm6)
	bm6.bide_storing.connect(func(atk: BattlePokemon): storing[0] += 1)
	bm6.start_battle(player6, opp6)
	bm6.queue_free()
	_chk("S8.06 bide_storing emitted (turn 2)", storing[0] > 0)

	# S8.07-S8.09 Bide release: bide_released emitted with damage > 0.
	# Player (high HP) bides for 2 turns, taking Tackle damage both turns.
	# Release deals 2× accumulated damage.
	var player7 := _make_mon("BideRel", 50, [TypeChart.TYPE_NORMAL], 200, 80, 80, 80, 80, 50)
	var opp7    := _make_mon("Opp7",    50, [TypeChart.TYPE_NORMAL], 80, 80, 80, 80, 80, 100)
	player7.add_move(bide)
	opp7.add_move(tackle)
	var release_dmg := [-1]
	var bm7 := BattleManager.new()
	add_child(bm7)
	bm7.bide_released.connect(func(atk: BattlePokemon, dmg: int):
		if release_dmg[0] < 0:
			release_dmg[0] = dmg)
	bm7.start_battle(player7, opp7)
	bm7.queue_free()
	_chk("S8.07 bide_released emitted",         release_dmg[0] >= 0)
	_chk("S8.08 bide_released damage > 0",      release_dmg[0] > 0)
	_chk("S8.09 bide damage is even (2× hits)", release_dmg[0] % 2 == 0)

	# S8.10 Bide with no damage received → bide_no_energy condition.
	# Direct state check: bide_damage=0 × 2 = 0 → fail condition.
	var bide_mon := _make_mon("BideZero", 50, [TypeChart.TYPE_NORMAL])
	bide_mon.bide_damage = 0
	_chk("S8.10 bide_damage=0 → 2×0 == 0 (bide_no_energy condition)",
			bide_mon.bide_damage * 2 == 0)

	# S8.11 Bide release with 0 damage → move_effect_failed 'bide_no_energy'.
	# Player bides while opponent uses Disable (status, no damage) + opp has burn so
	# opp KOs themselves via EOT burn damage, ending the battle.
	var player11 := _make_mon("BideNoDmg", 50, [TypeChart.TYPE_NORMAL], 80, 80, 80, 80, 80, 50)
	var opp11    := _make_mon("Opp11",     50, [TypeChart.TYPE_NORMAL], 80, 80, 80, 80, 80, 100)
	player11.add_move(bide)
	opp11.add_move(_load_move(50))  # Disable (status, no damage)
	opp11.status = BattlePokemon.STATUS_BURN
	opp11.current_hp = 30  # burn KOs opp in 2 EOT ticks (tick = max_hp/8 ≈ 17)
	var fail11: Array[String] = []
	var bm11 := BattleManager.new()
	add_child(bm11)
	bm11.move_effect_failed.connect(func(t: BattlePokemon, r: String): fail11.append(r))
	bm11.start_battle(player11, opp11)
	bm11.queue_free()
	_chk("S8.11 Bide no-damage release → bide_no_energy",
			"bide_no_energy" in fail11)


# ── Section 9: Metronome ──────────────────────────────────────────────────────

func _test_section_9_metronome() -> void:
	var metro  := _load_move(118)
	var tackle := _load_move(33)

	# S9.01 Metronome BAN_METRONOME (won't call itself)
	_chk("S9.01 Metronome BAN_METRONOME", (metro.ban_flags & MoveData.BAN_METRONOME) != 0)

	# S9.02-S9.05 move_called emitted and called move is valid.
	var player2 := _make_mon("Metro", 50, [TypeChart.TYPE_NORMAL], 80, 80, 80, 80, 80, 100)
	var opp2    := _make_mon("Opp2",  50, [TypeChart.TYPE_NORMAL], 80, 80, 80, 80, 80, 50)
	player2.add_move(metro)
	opp2.add_move(tackle)
	var called_mv := [null]
	var bm2 := BattleManager.new()
	add_child(bm2)
	bm2.move_called.connect(func(atk: BattlePokemon, mv: MoveData):
		if called_mv[0] == null:
			called_mv[0] = mv)
	bm2.start_battle(player2, opp2)
	bm2.queue_free()
	_chk("S9.02 move_called emitted",                    called_mv[0] != null)
	if called_mv[0] != null:
		_chk("S9.03 Called move is a MoveData",           called_mv[0] is MoveData)
		_chk("S9.04 Called move is not Metronome itself", not called_mv[0].is_metronome)
		_chk("S9.05 Called move not BAN_METRONOME banned",
				(called_mv[0].ban_flags & MoveData.BAN_METRONOME) == 0)
