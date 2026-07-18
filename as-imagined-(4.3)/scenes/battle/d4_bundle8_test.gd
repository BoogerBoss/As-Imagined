extends Node

# [D4 Bundle 8] Round, Snatch, Imprison, Grav Apple — reinstated after Rob
# reversed [Exclusion bookkeeping]'s own same-day exclusion decision.
#
# Real Step-0 forks found and preserved here (full citations in
# docs/decisions.md's own [D4 Bundle 8] entry):
#  - Round: power-double reuses _chosen_moves+_last_landed_move_anyone
#    directly (built for Copycat). REAL FINDING: source's own turn-order
#    self-promotion splice (TryUpdateRoundTurnOrder) is gated entirely on
#    IsDoubleBattle() — a genuine no-op in singles; only the power-double
#    half is built here, the doubles-only splice is a disclosed gap.
#  - Snatch: scope is ANY snatch_affected move used by anyone this turn,
#    not foe-targeting-only — the real 76-move source list is
#    overwhelmingly self-targeting buffs/heals. Only ONE steal can happen
#    per turn TOTAL (a global guard), not per-snatcher. This is the FIRST
#    call-a-move mechanic in this project to reassign the ATTACKER itself
#    (not just move/defender), so attacker_idx/attacker_side are
#    recomputed too.
#  - Imprison: fits the EXACT established execution-time-only pattern
#    already used for Disable/Torment/Taunt/Encore/Choice-item/Assault-
#    Vest — zero special-casing needed beyond it.
#  - Grav Apple: reduces to the exact shape the 79-move
#    M19-secondary-stat-on-hit family already handles generically —
#    pure data entry, zero new code.
#
# Ground truth: pokeemerald_expansion src/battle_util.c (EFFECT_ROUND
# L6300-6304, GetImprisonedMovesCount L1669-1688); src/battle_script_
# commands.c (TryUpdateRoundTurnOrder L11095-11134, CancelerSnatch
# L1800-1835, Cmd_trysetsnatch L9302-9314, Cmd_tryimprison L9195-9204);
# src/battle_move_resolution.c (CancelerImprisoned L378-386).

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_data_integrity()
	_test_grav_apple()
	_test_round()
	_test_imprison()
	_test_snatch()
	_test_negative_control()

	var total := _pass + _fail
	print("d4_bundle8_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


func _load_move(id: int) -> MoveData:
	return load("res://data/moves/move_%04d.tres" % id) as MoveData


func _make_mon(mon_name: String, base_hp: int = 100, base_atk: int = 60,
		base_def: int = 60, base_spatk: int = 60, base_spdef: int = 60,
		base_spd: int = 60, mon_type: int = TypeChart.TYPE_NORMAL) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types = [mon_type]
	sp.base_hp         = base_hp
	sp.base_attack     = base_atk
	sp.base_defense    = base_def
	sp.base_sp_attack  = base_spatk
	sp.base_sp_defense = base_spdef
	sp.base_speed      = base_spd
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])


func _make_bm() -> BattleManager:
	var bm := BattleManager.new()
	add_child(bm)
	return bm


func _doubles_party(m0: BattlePokemon, m1: BattlePokemon) -> BattleParty:
	var p := BattleParty.new()
	p.members = [m0, m1]
	p.active_indices.append(1)
	return p


# ── Section A: data integrity ────────────────────────────────────────────

func _test_data_integrity() -> void:
	var round_move := _load_move(496)
	_chk("A.496 Round: 60/100/15/Normal/Special/sound_move/ignores_substitute/is_round",
			round_move.move_name == "Round" and round_move.power == 60
			and round_move.accuracy == 100 and round_move.pp == 15
			and round_move.type == TypeChart.TYPE_NORMAL and round_move.category == 1
			and round_move.sound_move and round_move.ignores_substitute
			and round_move.is_round)

	var snatch := _load_move(289)
	_chk("A.289 Snatch: Dark/status/0acc/10pp/+4 priority/ignores_protect+substitute/is_snatch",
			snatch.move_name == "Snatch" and snatch.type == TypeChart.TYPE_DARK
			and snatch.category == 2 and snatch.accuracy == 0 and snatch.pp == 10
			and snatch.priority == 4 and snatch.ignores_protect
			and snatch.ignores_substitute and snatch.is_snatch)

	var imprison := _load_move(286)
	_chk("A.286 Imprison: Psychic/status/0acc/10pp/ignores_protect+substitute/snatch_affected/is_imprison",
			imprison.move_name == "Imprison" and imprison.type == TypeChart.TYPE_PSYCHIC
			and imprison.category == 2 and imprison.accuracy == 0 and imprison.pp == 10
			and imprison.ignores_protect and imprison.ignores_substitute
			and imprison.snatch_affected and imprison.is_imprison)

	var grav_apple := _load_move(716)
	_chk("A.716 Grav Apple: Grass/80/100/10/Physical, guaranteed -1 Defense, no new flag needed",
			grav_apple.move_name == "Grav Apple" and grav_apple.type == TypeChart.TYPE_GRASS
			and grav_apple.power == 80 and grav_apple.accuracy == 100 and grav_apple.pp == 10
			and grav_apple.category == 0
			and grav_apple.stat_change_stat == BattlePokemon.STAGE_DEF
			and grav_apple.stat_change_amount == -1
			and not grav_apple.stat_change_self
			and grav_apple.secondary_effect == MoveData.SE_NONE)

	# Spot-check the bulk snatch_affected tagging on 3 already-implemented moves.
	var swords_dance := _load_move(14)
	_chk("A.14 Swords Dance carries the new snatch_affected flag", swords_dance.snatch_affected)
	var recover := _load_move(105)
	_chk("A.105 Recover carries the new snatch_affected flag", recover.snatch_affected)
	var substitute := _load_move(164)
	_chk("A.164 Substitute carries the new snatch_affected flag", substitute.snatch_affected)
	# Confirmed-unreachable/excluded moves must NOT have been force-tagged.
	var tackle_check := _load_move(33)
	_chk("A.33 Tackle (an ordinary damaging move) is NOT snatch_affected",
			not tackle_check.snatch_affected)


# ── Section B: Grav Apple ────────────────────────────────────────────────

func _test_grav_apple() -> void:
	var grav_apple := _load_move(716)
	var atk := _make_mon("GaAtk", 300, 60, 60, 60, 60, 60)
	atk.add_move(grav_apple)
	var def := _make_mon("GaDef", 300, 60, 60, 60, 60, 1)
	var bm := _make_bm()
	bm._force_hit = true
	var dmg := [-1]
	var def_dropped := [false]
	bm.move_executed.connect(func(a, _d, m, amount):
		if a == atk and m == grav_apple and dmg[0] == -1: dmg[0] = amount)
	bm.stat_stage_changed.connect(func(mon, stat, delta):
		if mon == def and stat == BattlePokemon.STAGE_DEF and delta == -1:
			def_dropped[0] = true)
	bm.start_battle(atk, def)
	bm.queue_free()
	_chk("B.01 Grav Apple deals real damage", dmg[0] > 0)
	_chk("B.02 Grav Apple guaranteed-lowers the target's Defense", def_dropped[0] == true)


# ── Section C: Round ──────────────────────────────────────────────────────

func _test_round() -> void:
	var round_move := _load_move(496)
	var growl := _load_move(45)

	# (i) doubles: two allied Round-users acting back-to-back — the SECOND
	# one's Round (immediately following the first's own landed Round)
	# should deal roughly double the first's damage.
	var mon_a := _make_mon("RdA", 300, 60, 60, 60, 60, 100)
	mon_a.add_move(round_move)
	var mon_b := _make_mon("RdB", 300, 60, 60, 60, 60, 90)
	mon_b.add_move(round_move)
	var foe1 := _make_mon("RdFoe1", 300, 60, 60, 60, 60, 1)
	var foe2 := _make_mon("RdFoe2", 300, 60, 60, 60, 60, 1)
	var player := _doubles_party(mon_a, mon_b)
	var opp := _doubles_party(foe1, foe2)
	var bm := _make_bm()
	bm._force_hit = true
	bm._force_roll = 100
	bm._force_crit = false
	var dmg_a := [-1]
	var dmg_b := [-1]
	bm.move_executed.connect(func(a, _d, m, amount):
		if a == mon_a and m == round_move and dmg_a[0] == -1:
			dmg_a[0] = amount
		elif a == mon_b and m == round_move and dmg_b[0] == -1:
			dmg_b[0] = amount)
	bm.start_battle_doubles(player, opp)
	bm.queue_free()
	# Tolerance, not exact 2x: the base power is doubled BEFORE the damage
	# formula's own independent floor-roundings (defense stat, STAB, etc.),
	# so the two FINAL damage values won't be an exact 2x ratio even with
	# roll/crit both forced — matches this project's own established
	# "over-precise exact-equality" pitfall class (CLAUDE.md).
	_chk("C.01 REQUIRED: Round doubles after an immediately-preceding landed Round",
			dmg_a[0] > 0 and dmg_b[0] > dmg_a[0] * 1.8 and dmg_b[0] < dmg_a[0] * 2.2)

	# (ii) singles: first use this turn (no preceding action) — plain power.
	var atk2 := _make_mon("RdAtk2", 300, 60, 60, 60, 60, 100)
	atk2.add_move(round_move)
	var def2 := _make_mon("RdDef2", 300, 60, 60, 60, 60, 1)
	var bm2 := _make_bm()
	bm2._force_hit = true
	bm2._force_roll = 100
	bm2._force_crit = false
	var dmg2 := [-1]
	bm2.move_executed.connect(func(a, _d, m, amount):
		if a == atk2 and m == round_move and dmg2[0] == -1:
			dmg2[0] = amount)
	bm2.start_battle(atk2, def2)
	bm2.queue_free()
	_chk("C.02 Round does NOT double on the very first use this turn",
			dmg2[0] > 0 and dmg2[0] < dmg_b[0])

	# (iii) doubles: the preceding action was a DIFFERENT move (Growl, not
	# Round) — the second Round user should NOT double.
	var mon_c := _make_mon("RdC", 300, 60, 60, 60, 60, 100)
	mon_c.add_move(growl)
	var mon_d := _make_mon("RdD", 300, 60, 60, 60, 60, 90)
	mon_d.add_move(round_move)
	var foe3 := _make_mon("RdFoe3", 300, 60, 60, 60, 60, 1)
	var foe4 := _make_mon("RdFoe4", 300, 60, 60, 60, 60, 1)
	var player2 := _doubles_party(mon_c, mon_d)
	var opp2 := _doubles_party(foe3, foe4)
	var bm3 := _make_bm()
	bm3._force_hit = true
	bm3._force_roll = 100
	bm3._force_crit = false
	var dmg_d := [-1]
	bm3.move_executed.connect(func(a, _d, m, amount):
		if a == mon_d and m == round_move and dmg_d[0] == -1:
			dmg_d[0] = amount)
	bm3.start_battle_doubles(player2, opp2)
	bm3.queue_free()
	_chk("C.03 REQUIRED: Round does NOT double after a non-Round preceding action",
			dmg_d[0] > 0 and dmg_d[0] < dmg_b[0])


# ── Section D: Imprison ───────────────────────────────────────────────────

func _test_imprison() -> void:
	var imprison := _load_move(286)
	var growl := _load_move(45)

	# (i) cast succeeds, sets imprison_active.
	var atk := _make_mon("ImAtk", 300, 60, 60, 60, 60, 60)
	atk.add_move(imprison)
	var def := _make_mon("ImDef", 300, 60, 60, 60, 60, 1)
	def.add_move(growl)
	var bm := _make_bm()
	var im_set := [false]
	bm.imprison_set.connect(func(mon): if mon == atk: im_set[0] = true)
	bm.start_battle(atk, def)
	bm.queue_free()
	_chk("D.01 Imprison cast sets imprison_active", im_set[0] == true)

	# (ii) fails if already active.
	var atk2 := _make_mon("ImAtk2", 300, 60, 60, 60, 60, 60)
	atk2.add_move(imprison)
	atk2.imprison_active = true
	var def2 := _make_mon("ImDef2", 300, 60, 60, 60, 60, 1)
	var bm2 := _make_bm()
	var im_failed := [false]
	bm2.move_effect_failed.connect(func(mon, reason):
		if mon == atk2 and reason == "imprison_already_used": im_failed[0] = true)
	bm2.start_battle(atk2, def2)
	bm2.queue_free()
	_chk("D.02 Imprison fails if already active", im_failed[0] == true)

	# (iii) REQUIRED: blocks the OPPONENT from using a move the Imprison
	# caster ALSO KNOWS (Growl, shared by both sides — the Imprison caster
	# must itself carry Growl in its own moveset for the block to apply).
	var atk3 := _make_mon("ImAtk3", 300, 60, 60, 60, 60, 100)
	atk3.add_move(imprison)
	atk3.add_move(growl)
	var def3 := _make_mon("ImDef3", 300, 60, 60, 60, 60, 1)
	def3.add_move(growl)
	var bm3 := _make_bm()
	bm3.queue_move(0, 0)  # force atk3 to cast Imprison (slot 0), not Growl
	var skipped := [false]
	bm3.move_skipped.connect(func(mon, reason):
		if mon == def3 and reason == "imprison": skipped[0] = true)
	bm3.start_battle(atk3, def3)
	bm3.queue_free()
	_chk("D.03 REQUIRED: Imprison blocks the opponent's shared move", skipped[0] == true)

	# (iv) does NOT block a move the Imprison caster does NOT know.
	var atk4 := _make_mon("ImAtk4", 300, 60, 60, 60, 60, 100)
	atk4.add_move(imprison)
	var def4 := _make_mon("ImDef4", 300, 60, 60, 60, 60, 1)
	var tackle := MoveData.new()
	tackle.type = TypeChart.TYPE_NORMAL
	tackle.category = 0
	tackle.power = 40
	tackle.accuracy = 100
	def4.add_move(tackle)
	var bm4 := _make_bm()
	bm4._force_hit = true
	var skipped4 := [false]
	var dmg4 := [-1]
	bm4.move_skipped.connect(func(mon, reason):
		if mon == def4 and reason == "imprison": skipped4[0] = true)
	bm4.move_executed.connect(func(a, _d, m, amount):
		if a == def4 and m == tackle and dmg4[0] == -1: dmg4[0] = amount)
	bm4.start_battle(atk4, def4)
	bm4.queue_free()
	_chk("D.04 Imprison does NOT block a move the caster doesn't know",
			skipped4[0] == false and dmg4[0] > 0)


# ── Section E: Snatch ─────────────────────────────────────────────────────

func _test_snatch() -> void:
	var snatch := _load_move(289)
	var swords_dance := _load_move(14)

	# (i) cast succeeds when NOT last to move.
	var atk := _make_mon("SnAtk", 300, 60, 60, 60, 60, 100)
	atk.add_move(snatch)
	var def := _make_mon("SnDef", 300, 60, 60, 60, 60, 1)
	def.add_move(swords_dance)
	var bm := _make_bm()
	var sn_set := [false]
	bm.move_executed.connect(func(a, _d, m, _amount):
		if a == atk and m == snatch: sn_set[0] = atk.snatch_active)
	bm.start_battle(atk, def)
	bm.queue_free()
	_chk("E.01 Snatch cast succeeds when not last to move", sn_set[0] == true)

	# (ii) fails if the caster is last to move (only opponent left with a
	# pending move — construct via a bare mon with no other actor after it).
	var atk2 := _make_mon("SnAtk2", 300, 60, 60, 60, 60, 1)
	atk2.add_move(snatch)
	var def2 := _make_mon("SnDef2", 300, 60, 60, 60, 60, 100)
	var bm2 := _make_bm()
	bm2._combatants = [atk2, def2]
	bm2._turn_order = [def2, atk2]
	bm2._active_per_side = 1
	bm2._chosen_switch_slots = [-1, -1]
	bm2._chosen_targets = [1, 0]
	bm2._chosen_moves = [snatch, null]
	bm2._current_actor_index = 1
	var sn2_failed := [false]
	bm2.move_effect_failed.connect(func(mon, reason):
		if mon == atk2 and reason == "snatch_failed": sn2_failed[0] = true)
	bm2._phase_move_execution()
	_chk("E.02 Snatch fails when the caster is last to move", sn2_failed[0] == true)
	bm2.queue_free()

	# (iii) REQUIRED: steals the target's snatchable move — the buff lands
	# on the SNATCHER, not the original caster.
	var atk3 := _make_mon("SnAtk3", 300, 60, 60, 60, 60, 100)
	atk3.add_move(snatch)
	var def3 := _make_mon("SnDef3", 300, 60, 60, 60, 60, 1)
	def3.add_move(swords_dance)
	var bm3 := _make_bm()
	var stolen := [false]
	var atk3_atk_after_first := [-999]
	var def3_atk_after_first := [-999]
	var seen_swords_dance := [false]
	bm3.move_stolen.connect(func(stealer, original, m):
		if stealer == atk3 and original == def3 and m == swords_dance:
			stolen[0] = true)
	# Snapshot BOTH mons' Attack stage the instant the FIRST Swords Dance
	# resolution completes (move_executed fires after the whole dispatch,
	# including the stat change, for that action) — avoids the
	# whole-battle-aggregation pitfall, since both mons only know one
	# move each and would keep re-casting for many more turns otherwise.
	# Array-wrapped (not plain int locals) per CLAUDE.md's own documented
	# lambda-scalar-capture pitfall — a plain int assigned inside this
	# closure would mutate a private copy, never the outer variable.
	bm3.move_executed.connect(func(_a, _d, m, _amount):
		if m == swords_dance and not seen_swords_dance[0]:
			seen_swords_dance[0] = true
			atk3_atk_after_first[0] = atk3.stat_stages[BattlePokemon.STAGE_ATK]
			def3_atk_after_first[0] = def3.stat_stages[BattlePokemon.STAGE_ATK]
	)
	bm3.start_battle(atk3, def3)
	bm3.queue_free()
	_chk("E.03 REQUIRED: Snatch steals the target's move (move_stolen fires)",
			stolen[0] == true)
	_chk("E.04 REQUIRED: the stolen buff lands on the SNATCHER",
			atk3_atk_after_first[0] == 2)
	_chk("E.05 REQUIRED: the original caster does NOT get its own buff",
			def3_atk_after_first[0] == 0)

	# (iv) does NOT steal a non-snatchable move (ordinary damaging Tackle).
	var atk4 := _make_mon("SnAtk4", 300, 60, 60, 60, 60, 100)
	atk4.add_move(snatch)
	var def4 := _make_mon("SnDef4", 300, 60, 60, 60, 60, 1)
	var tackle := MoveData.new()
	tackle.type = TypeChart.TYPE_NORMAL
	tackle.category = 0
	tackle.power = 40
	tackle.accuracy = 100
	def4.add_move(tackle)
	var bm4 := _make_bm()
	bm4._force_hit = true
	var stolen4 := [false]
	var def4_dmg := [-1]
	bm4.move_stolen.connect(func(_s, _o, _m): stolen4[0] = true)
	bm4.move_executed.connect(func(a, _d, m, amount):
		if a == def4 and m == tackle and def4_dmg[0] == -1: def4_dmg[0] = amount)
	bm4.start_battle(atk4, def4)
	bm4.queue_free()
	_chk("E.06 REQUIRED: Snatch does NOT intercept a non-snatchable move",
			stolen4[0] == false and def4_dmg[0] > 0)


# ── Section F: negative control ──────────────────────────────────────────

func _test_negative_control() -> void:
	var tackle := MoveData.new()
	tackle.type = TypeChart.TYPE_NORMAL
	tackle.category = 0
	tackle.power = 40
	tackle.accuracy = 100
	tackle.makes_contact = true
	var atk := _make_mon("NegAtk", 300, 60, 60, 60, 60, 60)
	atk.add_move(tackle)
	var def := _make_mon("NegDef", 300, 60, 60, 60, 60, 60)
	var bm := _make_bm()
	bm._force_hit = true
	var dmg := [-1]
	bm.move_executed.connect(func(a, _d, m, amount):
		if a == atk and m == tackle and dmg[0] == -1: dmg[0] = amount)
	bm.start_battle(atk, def)
	bm.queue_free()
	_chk("F.01 NEGATIVE CONTROL: an ordinary move is unaffected by this bundle's dispatch",
			dmg[0] > 0)
