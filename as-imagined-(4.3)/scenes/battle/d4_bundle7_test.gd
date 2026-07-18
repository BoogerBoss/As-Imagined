extends Node

# [D4 Bundle 7] The last 7 REUSE-LIKELY residual moves: Curse, Focus Punch,
# Grudge, Last Resort, Pollen Puff, Beak Blast, Shell Trap.
#
# Real Step-0 forks found and preserved here (full citations in
# docs/decisions.md's own [D4 Bundle 7] entry):
#  - Curse: genuinely TWO different scripts (Ghost/non-Ghost), not one
#    script with a conditional. Ghost half never calls typecalc (same gap
#    as Foresight/Purify/Nightmare/Spite/Reflect Type/Toxic Thread/Venom
#    Drench) and needs no back-reference to the caster (simpler than
#    Leech Seed's shape) since the tick has no heal-back component.
#  - Focus Punch: dispatches through the ORDINARY EFFECT_HIT script — the
#    entire mechanic is a pre-move fail check reusing hit_by_this_turn.
#  - Grudge: reuses the SAME faint-reactive chokepoint as Destiny Bond/
#    Fell Stinger, draining the killer's own move slot to exactly 0 PP.
#  - Last Resort: REAL CORRECTION — its own "used moves" tracker resets on
#    SWITCH-OUT (same Volatiles-struct shape as Protean/Libero), NOT a
#    battle-lifetime tracker like times_hit.
#  - Pollen Puff: REAL CORRECTION — its ally-heal branch literally CALLS
#    Heal Pulse's own script, not just its formula.
#  - Beak Blast / Shell Trap: HIGH SCRUTINY, re-verified and CONFIRMED —
#    priority -3 + this project's sequential per-actor turn resolution
#    reproduces source's own separate pre-pass guarantee BY CONSTRUCTION.
#    Shell Trap's doubles-only turn-order splice is a disclosed, unbuilt
#    gap (singles-only correctness is unaffected).
#
# Ground truth: pokeemerald_expansion src/battle_script_commands.c
# (Cmd_cursetarget L8351-8369); src/battle_move_resolution.c (CancelerFocus
# L272-288, FAINT_BLOCK_DO_GRUDGE L2931-2949, CanUseLastResort L6644-6657,
# MoveEndShellTrap L3660-3676, IsBattlerUsingBeakBlast L4942-4948);
# src/battle_end_turn.c (HandleEndTurnCurse L635-650); data/battle_scripts_1.s
# (BattleScript_EffectHitEnemyHealAlly L940-942, BattleScript_EffectShellTrap).

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_data_integrity()
	_test_curse_ghost()
	_test_curse_non_ghost()
	_test_focus_punch()
	_test_grudge()
	_test_last_resort()
	_test_pollen_puff()
	_test_beak_blast()
	_test_shell_trap()
	_test_negative_control()

	var total := _pass + _fail
	print("d4_bundle7_test: %d/%d passed" % [_pass, total])
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


func _load_ability(id: int) -> AbilityData:
	return load("res://data/abilities/ability_%04d.tres" % id) as AbilityData


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
	var curse := _load_move(174)
	_chk("A.174 Curse: Ghost/status/0acc/10pp, ignores_protect+substitute, is_curse",
			curse.move_name == "Curse" and curse.type == TypeChart.TYPE_GHOST
			and curse.category == 2 and curse.accuracy == 0 and curse.pp == 10
			and curse.ignores_protect and curse.ignores_substitute
			and curse.stat_change_self and curse.is_curse)

	var focus_punch := _load_move(264)
	_chk("A.264 Focus Punch: 150/100/20/-3/Fighting/Physical/contact/is_focus_punch",
			focus_punch.move_name == "Focus Punch" and focus_punch.power == 150
			and focus_punch.accuracy == 100 and focus_punch.pp == 20
			and focus_punch.priority == -3 and focus_punch.type == TypeChart.TYPE_FIGHTING
			and focus_punch.category == 0 and focus_punch.makes_contact
			and focus_punch.is_focus_punch)

	var grudge := _load_move(288)
	_chk("A.288 Grudge: Ghost/status/0acc/5pp, ignores_protect+substitute, is_grudge",
			grudge.move_name == "Grudge" and grudge.type == TypeChart.TYPE_GHOST
			and grudge.category == 2 and grudge.accuracy == 0 and grudge.pp == 5
			and grudge.ignores_protect and grudge.ignores_substitute and grudge.is_grudge)

	var last_resort := _load_move(387)
	_chk("A.387 Last Resort: 140/100/5/Normal/Physical/contact/is_last_resort",
			last_resort.move_name == "Last Resort" and last_resort.power == 140
			and last_resort.accuracy == 100 and last_resort.pp == 5
			and last_resort.type == TypeChart.TYPE_NORMAL and last_resort.category == 0
			and last_resort.makes_contact and last_resort.is_last_resort)

	var pollen_puff := _load_move(639)
	_chk("A.639 Pollen Puff: 90/100/15/Bug/Special/ballistic/is_pollen_puff",
			pollen_puff.move_name == "Pollen Puff" and pollen_puff.power == 90
			and pollen_puff.accuracy == 100 and pollen_puff.pp == 15
			and pollen_puff.type == TypeChart.TYPE_BUG and pollen_puff.category == 1
			and pollen_puff.ballistic_move and pollen_puff.is_pollen_puff)

	var beak_blast := _load_move(653)
	_chk("A.653 Beak Blast: 100/100/15/-3/Flying/Physical/ballistic/is_beak_blast",
			beak_blast.move_name == "Beak Blast" and beak_blast.power == 100
			and beak_blast.accuracy == 100 and beak_blast.pp == 15
			and beak_blast.priority == -3 and beak_blast.type == TypeChart.TYPE_FLYING
			and beak_blast.category == 0 and beak_blast.ballistic_move
			and not beak_blast.makes_contact and beak_blast.is_beak_blast)

	var shell_trap := _load_move(658)
	_chk("A.658 Shell Trap: 150/100/5/-3/Fire/Special/is_shell_trap",
			shell_trap.move_name == "Shell Trap" and shell_trap.power == 150
			and shell_trap.accuracy == 100 and shell_trap.pp == 5
			and shell_trap.priority == -3 and shell_trap.type == TypeChart.TYPE_FIRE
			and shell_trap.category == 1 and shell_trap.is_shell_trap)


# ── Section B: Curse (Ghost-type user) ───────────────────────────────────

func _test_curse_ghost() -> void:
	var curse := _load_move(174)

	# (i) curses the target, costs the user maxHP/2, ticks maxHP/4 at end of turn.
	# Atk is faster and def's own move (Growl) deals no damage, so atk's HP
	# reading right after its own Curse cast reflects ONLY the self-cost.
	var atk := _make_mon("CurseAtk", 300, 60, 60, 60, 60, 100, TypeChart.TYPE_GHOST)
	atk.add_move(curse)
	var atk_max_hp: int = atk.max_hp
	var def := _make_mon("CurseDef", 300, 60, 60, 60, 60, 1)
	def.add_move(_load_move(45))  # Growl — harmless, deals no damage
	var def_max_hp: int = def.max_hp
	var bm := _make_bm()
	var cursed_set := [false]
	bm.curse_set.connect(func(mon): if mon == def: cursed_set[0] = true)
	var atk_hp_after_cast := [-1]
	bm.move_executed.connect(func(a, _d, m, _dmg):
		if a == atk and m == curse and atk_hp_after_cast[0] == -1:
			atk_hp_after_cast[0] = a.current_hp)
	var first_tick := [-1]
	bm.curse_damage.connect(func(mon, amount):
		if mon == def and first_tick[0] == -1: first_tick[0] = amount)
	bm.start_battle(atk, def)
	bm.queue_free()
	_chk("B.01 Curse (Ghost user) sets cursed on the target", cursed_set[0] == true)
	_chk("B.02 Curse (Ghost user) costs the caster maxHP/2",
			atk_hp_after_cast[0] == atk_max_hp - int(atk_max_hp / 2))
	_chk("B.03 Curse's own end-of-turn tick is maxHP/4",
			first_tick[0] == int(def_max_hp / 4))

	# (ii) fails outright if the target is already cursed (no re-cost).
	# Atk2 is faster and def2's own move (Growl) deals no damage, matching
	# (i)'s own fix for the same reason.
	var atk2 := _make_mon("CurseAtk2", 300, 60, 60, 60, 60, 100, TypeChart.TYPE_GHOST)
	atk2.add_move(curse)
	var atk2_max_hp: int = atk2.max_hp
	var def2 := _make_mon("CurseDef2", 300, 60, 60, 60, 60, 1)
	def2.add_move(_load_move(45))  # Growl — harmless, deals no damage
	def2.cursed = true
	var bm2 := _make_bm()
	var failed_hp := [-1]
	bm2.move_effect_failed.connect(func(mon, reason):
		if mon == def2 and reason == "curse_failed" and failed_hp[0] == -1:
			failed_hp[0] = atk2.current_hp)
	bm2.start_battle(atk2, def2)
	bm2.queue_free()
	_chk("B.04 Curse fails against an already-cursed target",
			failed_hp[0] == atk2_max_hp)

	# (iii) Magic Guard blocks the tick — direct _phase_end_of_turn() call,
	# matching the established direct-phase-call convention (avoids the
	# unbounded-stalemate risk a live battle would create here).
	var atk3 := _make_mon("CurseAtk3", 300, 60, 60, 60, 60, 60)
	var def3 := _make_mon("CurseDef3", 300, 60, 60, 60, 60, 60)
	var def3_max_hp: int = def3.max_hp
	def3.cursed = true
	def3.ability = _load_ability(98)  # Magic Guard
	var bm3 := _make_bm()
	bm3._combatants = [atk3, def3]
	bm3._active_per_side = 1
	bm3._turn_order = [atk3, def3]
	bm3._phase_end_of_turn()
	_chk("B.05 Magic Guard blocks Curse's own end-of-turn tick",
			def3.current_hp == def3_max_hp)
	bm3.queue_free()


func _test_curse_non_ghost() -> void:
	var curse := _load_move(174)
	var atk := _make_mon("CurseNgAtk", 300, 60, 60, 60, 60, 60)
	atk.add_move(curse)
	var def := _make_mon("CurseNgDef", 300, 60, 60, 60, 60, 60)
	var bm := _make_bm()
	var atk_changed := {}
	bm.stat_stage_changed.connect(func(mon, stat, delta):
		if mon == atk and not atk_changed.has(stat):
			atk_changed[stat] = delta)
	bm.start_battle(atk, def)
	bm.queue_free()
	_chk("B.06 Curse (non-Ghost user) raises own Attack +1",
			atk_changed.get(BattlePokemon.STAGE_ATK, 0) == 1)
	_chk("B.07 Curse (non-Ghost user) raises own Defense +1",
			atk_changed.get(BattlePokemon.STAGE_DEF, 0) == 1)
	_chk("B.08 Curse (non-Ghost user) lowers own Speed -1",
			atk_changed.get(BattlePokemon.STAGE_SPEED, 0) == -1)


# ── Section C: Focus Punch ────────────────────────────────────────────────

func _test_focus_punch() -> void:
	var focus_punch := _load_move(264)

	# (i) fails if the user was hit before its own turn (priority -3, so a
	# faster opponent's hit always lands first).
	var atk := _make_mon("FpAtk", 300, 60, 60, 60, 60, 30)
	atk.add_move(focus_punch)
	var opp := _make_mon("FpOpp", 300, 60, 60, 60, 60, 100)
	var tackle := MoveData.new()
	tackle.type = TypeChart.TYPE_NORMAL
	tackle.category = 0
	tackle.power = 40
	tackle.accuracy = 100
	tackle.makes_contact = true
	opp.add_move(tackle)
	var bm := _make_bm()
	bm._force_hit = true
	var fp_failed := [false]
	bm.move_effect_failed.connect(func(mon, reason):
		if mon == atk and reason == "focus_punch_lost_focus": fp_failed[0] = true)
	var fp_damage := [-1]
	bm.move_executed.connect(func(a, _d, m, dmg):
		if a == atk and m == focus_punch and fp_damage[0] == -1:
			fp_damage[0] = dmg)
	bm.start_battle(atk, opp)
	bm.queue_free()
	_chk("C.01 REQUIRED: Focus Punch fails when the user was hit this turn",
			fp_failed[0] == true)
	_chk("C.02 Focus Punch deals 0 damage on the turn it fails", fp_damage[0] == 0)

	# (ii) succeeds (real damage) when the user was NOT hit this turn —
	# opponent uses a status move instead (never damages the user).
	var atk2 := _make_mon("FpAtk2", 300, 60, 60, 60, 60, 30)
	atk2.add_move(focus_punch)
	var opp2 := _make_mon("FpOpp2", 300, 60, 60, 60, 60, 100)
	var growl := _load_move(45)
	opp2.add_move(growl)
	var bm2 := _make_bm()
	bm2._force_hit = true
	var fp2_damage := [-1]
	bm2.move_executed.connect(func(a, _d, m, dmg):
		if a == atk2 and m == focus_punch and fp2_damage[0] == -1:
			fp2_damage[0] = dmg)
	bm2.start_battle(atk2, opp2)
	bm2.queue_free()
	_chk("C.03 Focus Punch connects for real damage when the user wasn't hit",
			fp2_damage[0] > 0)


# ── Section D: Grudge ─────────────────────────────────────────────────────

func _test_grudge() -> void:
	var grudge := _load_move(288)

	# (i) drains the killer's own move to 0 PP.
	var victim := _make_mon("GrudgeVictim", 10, 60, 5, 60, 60, 100)
	victim.add_move(grudge)
	var killer := _make_mon("GrudgeKiller", 300, 250, 60, 60, 60, 10)
	var strike := MoveData.new()
	strike.type = TypeChart.TYPE_NORMAL
	strike.category = 0
	strike.power = 100
	strike.accuracy = 100
	strike.pp = 20
	killer.add_move(strike)
	var bm := _make_bm()
	bm._force_hit = true
	var drained := [false]
	bm.pp_drained.connect(func(mon, m):
		if mon == killer and m == strike: drained[0] = true)
	bm.start_battle(victim, killer)
	bm.queue_free()
	_chk("D.01 Grudge drains the killer's move to 0 PP", drained[0] == true)
	_chk("D.02 Grudge's drained slot is exactly 0 PP",
			killer.current_pp[killer.moves.find(strike)] == 0)

	# (ii) does NOT fire if the killing blow was Struggle.
	var victim2 := _make_mon("GrudgeVictim2", 10, 60, 5, 60, 60, 100)
	victim2.add_move(grudge)
	var killer2 := _make_mon("GrudgeKiller2", 300, 250, 60, 60, 60, 10)
	var weak_move := MoveData.new()
	weak_move.type = TypeChart.TYPE_NORMAL
	weak_move.category = 0
	weak_move.power = 100
	weak_move.accuracy = 100
	weak_move.pp = 5
	killer2.add_move(weak_move)
	killer2.current_pp[0] = 0  # forces Struggle every turn
	var bm2 := _make_bm()
	bm2._force_hit = true
	var drained2 := [false]
	bm2.pp_drained.connect(func(_mon, _m): drained2[0] = true)
	bm2.start_battle(victim2, killer2)
	bm2.queue_free()
	_chk("D.03 REQUIRED: Grudge does NOT drain PP when killed by Struggle",
			drained2[0] == false)


# ── Section E: Last Resort ────────────────────────────────────────────────

func _test_last_resort() -> void:
	var last_resort := _load_move(387)

	# (i) fails until every OTHER move slot has been used since switch-in.
	var atk := _make_mon("LrAtk", 300, 60, 60, 60, 60, 60)
	var tackle := MoveData.new()
	tackle.type = TypeChart.TYPE_NORMAL
	tackle.category = 0
	tackle.power = 40
	tackle.accuracy = 100
	tackle.pp = 5
	atk.add_move(tackle)
	atk.add_move(last_resort)
	var def := _make_mon("LrDef", 300, 60, 60, 60, 60, 1)
	var bm := _make_bm()
	bm.queue_move(0, 1)  # Last Resort first — should fail, tackle unused
	var lr_failed := [false]
	bm.move_effect_failed.connect(func(mon, reason):
		if mon == atk and reason == "last_resort_not_ready": lr_failed[0] = true)
	bm.start_battle(atk, def)
	bm.queue_free()
	_chk("E.01 Last Resort fails when another move hasn't been used yet",
			lr_failed[0] == true)

	# (ii) succeeds once every other move has been used.
	var atk2 := _make_mon("LrAtk2", 300, 60, 60, 60, 60, 60)
	var tackle2 := MoveData.new()
	tackle2.type = TypeChart.TYPE_NORMAL
	tackle2.category = 0
	tackle2.power = 40
	tackle2.accuracy = 100
	tackle2.pp = 5
	atk2.add_move(tackle2)
	atk2.add_move(last_resort)
	var def2 := _make_mon("LrDef2", 300, 60, 60, 60, 60, 1)
	var bm2 := _make_bm()
	bm2._force_hit = true
	bm2.queue_move(0, 0)  # tackle first, marks slot 0 used
	bm2.queue_move(0, 1)  # Last Resort second — should now succeed
	var lr2_damage := [-1]
	bm2.move_executed.connect(func(a, _d, m, dmg):
		if a == atk2 and m == last_resort and lr2_damage[0] == -1:
			lr2_damage[0] = dmg)
	bm2.start_battle(atk2, def2)
	bm2.queue_free()
	_chk("E.02 REQUIRED: Last Resort succeeds once the other move has been used",
			lr2_damage[0] > 0)

	# (iii) fails outright if it's the ONLY known move (moves.size() < 2).
	var atk3 := _make_mon("LrAtk3", 300, 60, 60, 60, 60, 60)
	atk3.add_move(last_resort)
	var def3 := _make_mon("LrDef3", 300, 60, 60, 60, 60, 1)
	var bm3 := _make_bm()
	var lr3_failed := [false]
	bm3.move_effect_failed.connect(func(mon, reason):
		if mon == atk3 and reason == "last_resort_not_ready": lr3_failed[0] = true)
	bm3.start_battle(atk3, def3)
	bm3.queue_free()
	_chk("E.03 Last Resort fails outright as the only known move", lr3_failed[0] == true)

	# (iv) REQUIRED: the "used" tracker resets on switch-out (real
	# correction from Step 0 — NOT a battle-lifetime tracker).
	var mover := _make_mon("LrSwitchMover", 300, 60, 60, 60, 60, 60)
	var tackle4 := MoveData.new()
	tackle4.type = TypeChart.TYPE_NORMAL
	tackle4.category = 0
	tackle4.power = 40
	mover.add_move(tackle4)
	mover.add_move(last_resort)
	mover.used_move_slots[0] = true  # simulate: already used the other move this stint
	var bm4 := _make_bm()
	bm4._clear_volatiles(mover)
	_chk("E.04 REQUIRED: used_move_slots resets on switch-out/_clear_volatiles",
			mover.used_move_slots[0] == false)
	bm4.queue_free()


# ── Section F: Pollen Puff ────────────────────────────────────────────────

func _test_pollen_puff() -> void:
	var pollen_puff := _load_move(639)

	# (i) doubles: heals the ALLY instead of damaging it.
	var caster := _make_mon("PpCaster", 300, 60, 60, 60, 60, 60)
	caster.add_move(pollen_puff)
	var ally := _make_mon("PpAlly", 300, 60, 60, 60, 60, 60)
	var ally_max_hp: int = ally.max_hp
	ally.current_hp = 100
	var foe1 := _make_mon("PpFoe1", 300, 60, 60, 60, 60, 1)
	var foe2 := _make_mon("PpFoe2", 300, 60, 60, 60, 60, 1)
	var player := _doubles_party(caster, ally)
	var opp := _doubles_party(foe1, foe2)
	var bm := _make_bm()
	bm.queue_move_targeted(0, 0, 1)  # caster (slot 0) uses Pollen Puff on ally (slot 1)
	var healed := [-1]
	bm.drain_heal.connect(func(mon, amount):
		if mon == ally and healed[0] == -1: healed[0] = amount)
	bm.start_battle_doubles(player, opp)
	bm.queue_free()
	_chk("F.01 REQUIRED: Pollen Puff heals the ally instead of damaging it (doubles)",
			healed[0] == max(1, int(ally_max_hp * 0.5)))

	# (ii) singles: ordinary damage against the foe (ally branch unreachable).
	var atk2 := _make_mon("PpAtk2", 300, 60, 60, 60, 60, 60)
	atk2.add_move(pollen_puff)
	var def2 := _make_mon("PpDef2", 300, 60, 60, 60, 60, 1)
	var bm2 := _make_bm()
	bm2._force_hit = true
	var pp2_damage := [-1]
	bm2.move_executed.connect(func(a, _d, m, dmg):
		if a == atk2 and m == pollen_puff and pp2_damage[0] == -1:
			pp2_damage[0] = dmg)
	bm2.start_battle(atk2, def2)
	bm2.queue_free()
	_chk("F.02 Pollen Puff deals ordinary damage against a foe in singles",
			pp2_damage[0] > 0)


# ── Section G: Beak Blast ─────────────────────────────────────────────────

func _test_beak_blast() -> void:
	var beak_blast := _load_move(653)

	# (i) burns a CONTACT attacker that hits before Beak Blast's own turn
	# (priority -3, so a faster contact attacker always lands first).
	var user := _make_mon("BbUser", 300, 60, 60, 60, 60, 30)
	user.add_move(beak_blast)
	var attacker := _make_mon("BbAtk", 300, 60, 60, 60, 60, 100, TypeChart.TYPE_WATER)
	var tackle := MoveData.new()
	tackle.type = TypeChart.TYPE_NORMAL
	tackle.category = 0
	tackle.power = 40
	tackle.accuracy = 100
	tackle.makes_contact = true
	attacker.add_move(tackle)
	var bm := _make_bm()
	bm._force_hit = true
	var burned := [false]
	bm.secondary_applied.connect(func(mon, se):
		if mon == attacker and se == MoveData.SE_BURN: burned[0] = true)
	bm.start_battle(user, attacker)
	bm.queue_free()
	_chk("G.01 REQUIRED: Beak Blast burns a contact attacker that hit it first",
			burned[0] == true)
	_chk("G.02 The burn actually landed on the attacker's status",
			attacker.status == BattlePokemon.STATUS_BURN)

	# (ii) does NOT burn a NON-contact attacker.
	var user2 := _make_mon("BbUser2", 300, 60, 60, 60, 60, 30)
	user2.add_move(beak_blast)
	var attacker2 := _make_mon("BbAtk2", 300, 60, 60, 60, 60, 100, TypeChart.TYPE_WATER)
	var ember := MoveData.new()
	ember.type = TypeChart.TYPE_FIRE
	ember.category = 1
	ember.power = 40
	ember.accuracy = 100
	ember.pp = 99  # avoid a Struggle-fallback contaminating the non-contact discriminator
	ember.makes_contact = false
	attacker2.add_move(ember)
	var bm2 := _make_bm()
	bm2._force_hit = true
	var burned2 := [false]
	bm2.secondary_applied.connect(func(mon, se):
		if mon == attacker2 and se == MoveData.SE_BURN: burned2[0] = true)
	bm2.start_battle(user2, attacker2)
	bm2.queue_free()
	_chk("G.03 REQUIRED: Beak Blast does NOT burn a non-contact attacker",
			burned2[0] == false)


# ── Section H: Shell Trap ─────────────────────────────────────────────────

func _test_shell_trap() -> void:
	var shell_trap := _load_move(658)

	# (i) fires (real damage) when hit by a PHYSICAL move before its own turn.
	var user := _make_mon("StUser", 300, 60, 60, 60, 60, 30)
	user.add_move(shell_trap)
	var attacker := _make_mon("StAtk", 300, 60, 60, 60, 60, 100)
	var tackle := MoveData.new()
	tackle.type = TypeChart.TYPE_NORMAL
	tackle.category = 0
	tackle.power = 40
	tackle.accuracy = 100
	attacker.add_move(tackle)
	var bm := _make_bm()
	bm._force_hit = true
	var st_damage := [-1]
	bm.move_executed.connect(func(a, _d, m, dmg):
		if a == user and m == shell_trap and st_damage[0] == -1:
			st_damage[0] = dmg)
	bm.start_battle(user, attacker)
	bm.queue_free()
	_chk("H.01 REQUIRED: Shell Trap fires for real damage after a physical hit",
			st_damage[0] > 0)

	# (ii) fails ("didn't work") if never hit.
	var user2 := _make_mon("StUser2", 300, 60, 60, 60, 60, 30)
	user2.add_move(shell_trap)
	var passive := _make_mon("StPassive", 300, 60, 60, 60, 60, 100)
	var growl := _load_move(45)
	passive.add_move(growl)
	var bm2 := _make_bm()
	bm2._force_hit = true
	var st2_failed := [false]
	bm2.move_effect_failed.connect(func(mon, reason):
		if mon == user2 and reason == "shell_trap_didnt_work": st2_failed[0] = true)
	bm2.start_battle(user2, passive)
	bm2.queue_free()
	_chk("H.02 Shell Trap fails when never hit this turn", st2_failed[0] == true)

	# (iii) REQUIRED: does NOT fire from a SPECIAL hit (physical-only gate).
	var user3 := _make_mon("StUser3", 300, 60, 60, 60, 60, 30)
	user3.add_move(shell_trap)
	var special_atk := _make_mon("StSpecialAtk", 300, 60, 60, 60, 60, 100)
	var ember := MoveData.new()
	ember.type = TypeChart.TYPE_FIRE
	ember.category = 1
	ember.power = 40
	ember.accuracy = 100
	special_atk.add_move(ember)
	var bm3 := _make_bm()
	bm3._force_hit = true
	var st3_failed := [false]
	bm3.move_effect_failed.connect(func(mon, reason):
		if mon == user3 and reason == "shell_trap_didnt_work": st3_failed[0] = true)
	bm3.start_battle(user3, special_atk)
	bm3.queue_free()
	_chk("H.03 REQUIRED: Shell Trap does NOT fire when only hit by a special move",
			st3_failed[0] == true)


# ── Section I: negative control ──────────────────────────────────────────

func _test_negative_control() -> void:
	# A move sharing none of this bundle's own flags should be completely
	# unaffected by any of the new dispatch code (proves the harness isn't
	# vacuously passing).
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
	_chk("I.01 NEGATIVE CONTROL: an ordinary move is unaffected by this bundle's dispatch",
			dmg[0] > 0)
