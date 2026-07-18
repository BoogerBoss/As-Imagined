extends Node

# [D4 CHEAP bundle] Dream Eater, Torment, Gyro Ball, Electro Ball, Snore,
# Endure, Fell Stinger, Magnet Rise, Smack Down, Ingrain, Aqua Ring, Payback
# — 12 moves from D4's singleton pool, selected per Rob's own prompt (4
# confirmed standouts + 8 additional picks after Step 0 verification).
#
# Real corrections found during Step 0, all confirmed against source before
# implementing: Dream Eater's drain reuses the generic EFFECT_ABSORB/
# EFFECT_DREAM_EATER drain_percent chokepoint, NOT the Volt Absorb/Water
# Absorb ability family; Torment is a PERMANENT (never-expiring) target-side
# volatile (the decoy `tormentTimer`/`Cmd_TrySetTormentSide` belongs to an
# unrelated side-wide variant this project doesn't implement); Electro Ball
# is a genuinely different, stepped/banded formula from Gyro Ball's
# continuous one; Endure shares Protect/Detect's `setprotectlike` dispatch
# but that command itself branches internally to a SEPARATE `endure_active`
# field (confirmed via direct source read — the original plan to reuse
# `protect_active` with an `_is_protected_from` bypass case was abandoned
# before implementing, since it doesn't match source); Ingrain's own scope
# turned out to be fully buildable (self-heal + self-ground + BOTH
# voluntary-switch-block AND forced-switch-block via Roar/Circle Throw/Red
# Card, confirmed from source that Roar's own script checks VOLATILE_ROOT
# directly) rather than the partial scope originally proposed. A real,
# pre-existing gap was also found and fixed as a byproduct of Smack Down/
# Ingrain's own grounding work: `TypeChart.get_uq412` never had a
# `grounded_override` param at all (unlike `get_effectiveness`, which
# already did for Iron Ball, `[M18t]`), meaning `DamageCalculator.calculate`'s
# own SECOND, independent UQ4.12 computation would silently re-immune a
# Ground move against ANY forced-grounded target (Iron Ball included, not
# just this bundle's own new moves) even after the FIRST immunity gate
# already passed — fixed by adding the same param/check to `get_uq412` and
# threading it through both of `calculate`'s own call sites.
#
# Ground truth: pokeemerald_expansion src/data/moves_info.h; src/battle_
# util.c (EFFECT_DREAM_EATER/EFFECT_GYRO_BALL/EFFECT_ELECTRO_BALL/
# EFFECT_PAYBACK/EFFECT_FELL_STINGER/EFFECT_SMACK_DOWN/IsBattlerGrounded
# InverseCheck); src/battle_script_commands.c (Cmd_settorment/
# Cmd_setprotectlike/Cmd_trysetvolatile); src/battle_end_turn.c
# (HandleEndTurnAquaRing/HandleEndTurnIngrain/HandleEndTurnMagnetRise);
# data/battle_scripts_1.s (BattleScript_EffectDreamEater/EffectMagnetRise/
# EffectRoar/EffectTorment/EffectEndure).

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_data_integrity()
	_test_dream_eater()
	_test_torment()
	_test_gyro_ball()
	_test_electro_ball()
	_test_snore()
	_test_endure()
	_test_fell_stinger()
	_test_magnet_rise()
	_test_smack_down()
	_test_ingrain()
	_test_aqua_ring()
	_test_payback()

	var total := _pass + _fail
	print("d4_bundle2_test: %d/%d passed" % [_pass, total])
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


func _bench_party(active_mon: BattlePokemon, bench_mon: BattlePokemon) -> BattleParty:
	var p := BattleParty.new()
	p.members = [active_mon, bench_mon]
	p.active_indices = [0]
	return p


# ── Section A: data integrity ────────────────────────────────────────────

func _test_data_integrity() -> void:
	var de := _load_move(138)
	_chk("A.01 Dream Eater power=100/acc=100/pp=15/SPEC/Psychic",
			de.power == 100 and de.accuracy == 100 and de.pp == 15
			and de.category == 1 and de.type == TypeChart.TYPE_PSYCHIC)
	_chk("A.02 Dream Eater drain_percent=50 + requires_target_asleep + healing_move",
			de.drain_percent == 50 and de.requires_target_asleep and de.healing_move)

	var snore := _load_move(173)
	_chk("A.03 Snore power=50/acc=100/pp=15/SPEC/Normal",
			snore.power == 50 and snore.accuracy == 100 and snore.pp == 15
			and snore.category == 1 and snore.type == TypeChart.TYPE_NORMAL)
	_chk("A.04 Snore is_snore + usable_while_asleep + ignores_substitute + sound_move",
			snore.is_snore and snore.usable_while_asleep and snore.ignores_substitute
			and snore.sound_move)
	_chk("A.05 Snore secondary_effect=SE_FLINCH/chance=30",
			snore.secondary_effect == MoveData.SE_FLINCH and snore.secondary_chance == 30)

	var endure := _load_move(203)
	_chk("A.06 Endure acc=0/pp=10/priority=4/STAT/Normal",
			endure.accuracy == 0 and endure.pp == 10 and endure.priority == 4
			and endure.category == 2 and endure.type == TypeChart.TYPE_NORMAL)
	_chk("A.07 Endure is_protect + protect_method=PROTECT_METHOD_ENDURE",
			endure.is_protect and endure.protect_method == BattlePokemon.PROTECT_METHOD_ENDURE)

	var torment := _load_move(259)
	_chk("A.08 Torment acc=100/pp=15/STAT/Dark",
			torment.accuracy == 100 and torment.pp == 15 and torment.category == 2
			and torment.type == TypeChart.TYPE_DARK)
	_chk("A.09 Torment is_torment + bounceable + blocked_by_aroma_veil",
			torment.is_torment and torment.bounceable and torment.blocked_by_aroma_veil)

	var ingrain := _load_move(275)
	_chk("A.10 Ingrain acc=0/pp=20/STAT/Grass", ingrain.accuracy == 0 and ingrain.pp == 20
			and ingrain.category == 2 and ingrain.type == TypeChart.TYPE_GRASS)
	_chk("A.11 Ingrain is_ingrain + ignores_protect",
			ingrain.is_ingrain and ingrain.ignores_protect)

	var gyro := _load_move(360)
	_chk("A.12 Gyro Ball power=1/acc=100/pp=5/PHYS/Steel/contact/ballistic",
			gyro.power == 1 and gyro.accuracy == 100 and gyro.pp == 5
			and gyro.category == 0 and gyro.type == TypeChart.TYPE_STEEL
			and gyro.makes_contact and gyro.ballistic_move)
	_chk("A.13 Gyro Ball is_gyro_ball", gyro.is_gyro_ball)

	var payback := _load_move(371)
	_chk("A.14 Payback power=50/acc=100/pp=10/PHYS/Dark/contact",
			payback.power == 50 and payback.accuracy == 100 and payback.pp == 10
			and payback.category == 0 and payback.type == TypeChart.TYPE_DARK
			and payback.makes_contact)
	_chk("A.15 Payback is_payback", payback.is_payback)

	var aqua_ring := _load_move(392)
	_chk("A.16 Aqua Ring acc=0/pp=20/STAT/Water", aqua_ring.accuracy == 0 and aqua_ring.pp == 20
			and aqua_ring.category == 2 and aqua_ring.type == TypeChart.TYPE_WATER)
	_chk("A.17 Aqua Ring is_aqua_ring + ignores_protect",
			aqua_ring.is_aqua_ring and aqua_ring.ignores_protect)

	var magnet_rise := _load_move(393)
	_chk("A.18 Magnet Rise acc=0/pp=10/STAT/Electric",
			magnet_rise.accuracy == 0 and magnet_rise.pp == 10
			and magnet_rise.category == 2 and magnet_rise.type == TypeChart.TYPE_ELECTRIC)
	_chk("A.19 Magnet Rise is_magnet_rise + ignores_protect",
			magnet_rise.is_magnet_rise and magnet_rise.ignores_protect)

	var smack_down := _load_move(479)
	_chk("A.20 Smack Down power=50/acc=100/pp=15/PHYS/Rock/damages_airborne",
			smack_down.power == 50 and smack_down.accuracy == 100 and smack_down.pp == 15
			and smack_down.category == 0 and smack_down.type == TypeChart.TYPE_ROCK
			and smack_down.damages_airborne)
	_chk("A.21 Smack Down is_smack_down", smack_down.is_smack_down)

	var electro := _load_move(486)
	_chk("A.22 Electro Ball power=1/acc=100/pp=10/SPEC/Electric/ballistic",
			electro.power == 1 and electro.accuracy == 100 and electro.pp == 10
			and electro.category == 1 and electro.type == TypeChart.TYPE_ELECTRIC
			and electro.ballistic_move)
	_chk("A.23 Electro Ball is_electro_ball", electro.is_electro_ball)

	var fell_stinger := _load_move(565)
	_chk("A.24 Fell Stinger power=50/acc=100/pp=25/PHYS/Bug/contact",
			fell_stinger.power == 50 and fell_stinger.accuracy == 100 and fell_stinger.pp == 25
			and fell_stinger.category == 0 and fell_stinger.type == TypeChart.TYPE_BUG
			and fell_stinger.makes_contact)
	_chk("A.25 Fell Stinger is_fell_stinger", fell_stinger.is_fell_stinger)


# ── Section B: Dream Eater ───────────────────────────────────────────────

func _test_dream_eater() -> void:
	var de := _load_move(138)

	# (i) fails outright (0 damage) against a non-sleeping target.
	var atk_i := _make_mon("DEAtk1", 300, 60, 60, 100, 60, 60)
	var def_i := _make_mon("DEDef1", 300, 60, 60, 60, 60, 50)
	atk_i.add_move(de)
	def_i.add_move(_load_move(45))  # Growl, harmless filler
	var events_i := []
	var bm1 := _make_bm()
	bm1._force_hit = true
	bm1.move_executed.connect(func(a, _d, m, amount):
		if a == atk_i and m == de and events_i.is_empty():
			events_i.append(amount))
	bm1.start_battle(atk_i, def_i)
	bm1.queue_free()
	_chk("B.01 Dream Eater deals 0 damage against a non-sleeping target",
			events_i.size() == 1 and events_i[0] == 0)

	# (ii) succeeds against a sleeping target, draining ~50% of damage dealt.
	var atk_ii := _make_mon("DEAtk2", 300, 60, 60, 100, 60, 60)
	var def_ii := _make_mon("DEDef2", 300, 60, 60, 60, 60, 50)
	atk_ii.add_move(de)
	def_ii.add_move(_load_move(45))
	def_ii.status = BattlePokemon.STATUS_SLEEP
	def_ii.sleep_turns = 5
	atk_ii.current_hp = 150
	var dealt := []
	var healed := [0]
	var bm2 := _make_bm()
	bm2._force_hit = true
	bm2._force_roll = 100
	bm2._force_crit = false
	bm2.move_executed.connect(func(a, _d, m, amount):
		if a == atk_ii and m == de and dealt.is_empty():
			dealt.append(amount))
	bm2.drain_heal.connect(func(a, amount): if a == atk_ii: healed[0] = amount)
	bm2.start_battle(atk_ii, def_ii)
	bm2.queue_free()
	_chk("B.02 Dream Eater deals real damage against a sleeping target",
			dealt.size() == 1 and dealt[0] > 0)
	_chk("B.03 Dream Eater drains exactly half of the damage dealt (drain_percent formula)",
			healed[0] == dealt[0] / 2)


# ── Section C: Torment ───────────────────────────────────────────────────

func _test_torment() -> void:
	var torment := _load_move(259)
	var tackle := _load_move(33)
	var ember := _load_move(52)

	# (i) blocks re-use of the exact same move the following turn.
	var atk_i := _make_mon("TormAtk1", 300, 60, 60, 60, 60, 50)
	var def_i := _make_mon("TormDef1", 300, 60, 60, 60, 60, 100)
	atk_i.add_move(torment)
	def_i.add_move(tackle)
	var skipped := [false]
	var bm1 := _make_bm()
	bm1._force_hit = true
	bm1.move_skipped.connect(func(a, reason):
		if a == def_i and reason == "tormented" and not skipped[0]: skipped[0] = true)
	bm1.start_battle(atk_i, def_i)
	bm1.queue_free()
	_chk("C.01 Torment blocks the target's own repeated move on a later turn",
			skipped[0] == true)

	# (ii) discriminator: a tormented mon CAN use a DIFFERENT move on the
	# very next turn without being skipped. Torment user is FASTER, so
	# def_ii is tormented before it has ever moved (last_move_used == null,
	# never blocked on its own first action regardless). Turn 1: def_ii
	# uses Tackle (queued); turn 2: def_ii uses Ember (queued, different
	# from last_move_used) — neither should ever be skipped.
	var atk_ii := _make_mon("TormAtk2", 300, 60, 60, 60, 60, 100)
	var def_ii := _make_mon("TormDef2", 300, 60, 60, 60, 60, 50)
	atk_ii.add_move(torment)
	def_ii.add_move(tackle)
	def_ii.add_move(ember)
	# Whole-battle-aggregation guard: the battle legitimately runs many more
	# turns after this (300 HP, ~27 dmg/hit), and once the queue drains,
	# def_ii's auto-selected repeat of Tackle DOES get correctly skipped
	# several turns later — a real, separate confirmation of C.01's own
	# mechanism, not a contradiction of this discriminator. Scoped via an
	# ordered timeline to only the events up to and including Ember's own
	# execution, isolating just the turn-2 scenario under test here.
	var bm2 := _make_bm()
	bm2._force_hit = true
	bm2.queue_move(1, 0)  # def_ii turn 1: Tackle
	bm2.queue_move(1, 1)  # def_ii turn 2: Ember (different move, never blocked)
	var timeline := []
	bm2.move_skipped.connect(func(a, reason):
		if a == def_ii and reason == "tormented": timeline.append("skipped"))
	bm2.move_executed.connect(func(a, _d, m, _amt):
		if a == def_ii and m == ember: timeline.append("ember_executed"))
	bm2.start_battle(atk_ii, def_ii)
	bm2.queue_free()
	var ember_idx: int = timeline.find("ember_executed")
	var skipped_before_ember: bool = ember_idx >= 0 and timeline.slice(0, ember_idx).has("skipped")
	_chk("C.02 discriminator: a tormented mon is never SKIPPED for using a DIFFERENT move",
			ember_idx >= 0 and not skipped_before_ember)


# ── Section D: Gyro Ball ─────────────────────────────────────────────────

func _test_gyro_ball() -> void:
	var gyro := _load_move(360)
	_chk("D.01 Gyro Ball power formula: user==0 speed guard -> 1",
			BattleManager._gyro_ball_power(0, 100) == 1)
	_chk("D.02 Gyro Ball power formula: equal speed -> 26 ((25*100/100)+1)",
			BattleManager._gyro_ball_power(100, 100) == 26)
	_chk("D.03 Gyro Ball power formula: target 4x faster -> 101 ((25*400/100)+1)",
			BattleManager._gyro_ball_power(100, 400) == 101)
	_chk("D.04 Gyro Ball power formula: capped at 150 for an extreme ratio",
			BattleManager._gyro_ball_power(50, 5000) == 150)

	# Full-battle confirmation: a slow attacker vs a fast defender deals
	# strictly more damage than a fast attacker vs a slow defender (same
	# pair of mons, roles reversed on speed).
	var slow := _make_mon("GyroSlow", 300, 100, 60, 60, 60, 20)
	var fast := _make_mon("GyroFast", 300, 60, 60, 60, 60, 200)
	slow.add_move(gyro)
	fast.add_move(_load_move(45))  # Growl, never damages
	var dmg_slow_attacker := []
	var bm1 := _make_bm()
	bm1._force_hit = true
	bm1._force_roll = 100
	bm1._force_crit = false
	bm1.move_executed.connect(func(a, _d, m, amount):
		if a == slow and m == gyro and dmg_slow_attacker.is_empty():
			dmg_slow_attacker.append(amount))
	bm1.start_battle(slow, fast)
	bm1.queue_free()

	var slow2 := _make_mon("GyroSlow2", 300, 100, 60, 60, 60, 200)
	var fast2 := _make_mon("GyroFast2", 300, 60, 60, 60, 60, 20)
	slow2.add_move(gyro)
	fast2.add_move(_load_move(45))
	var dmg_fast_attacker := []
	var bm2 := _make_bm()
	bm2._force_hit = true
	bm2._force_roll = 100
	bm2._force_crit = false
	bm2.move_executed.connect(func(a, _d, m, amount):
		if a == slow2 and m == gyro and dmg_fast_attacker.is_empty():
			dmg_fast_attacker.append(amount))
	bm2.start_battle(slow2, fast2)
	bm2.queue_free()
	_chk("D.05 Gyro Ball deals more damage when the USER is slower than the target",
			dmg_slow_attacker.size() == 1 and dmg_fast_attacker.size() == 1
			and dmg_slow_attacker[0] > dmg_fast_attacker[0])


# ── Section E: Electro Ball ──────────────────────────────────────────────

func _test_electro_ball() -> void:
	_chk("E.01 Electro Ball power formula: ratio 0 (target faster) -> 40",
			BattleManager._electro_ball_power(50, 200) == 40)
	_chk("E.02 Electro Ball power formula: ratio 1 (equal speed) -> 60",
			BattleManager._electro_ball_power(100, 100) == 60)
	_chk("E.03 Electro Ball power formula: ratio 2 -> 80",
			BattleManager._electro_ball_power(200, 100) == 80)
	_chk("E.04 Electro Ball power formula: ratio 3 -> 120",
			BattleManager._electro_ball_power(300, 100) == 120)
	_chk("E.05 Electro Ball power formula: ratio 4+ -> 150 (capped)",
			BattleManager._electro_ball_power(500, 100) == 150
			and BattleManager._electro_ball_power(999, 100) == 150)
	# Discriminator proving STEPPED/BANDED, not continuous: two different
	# ratios within the same band (2 and 2.9) must produce the IDENTICAL
	# power, unlike Gyro Ball's own continuous formula.
	_chk("E.06 discriminator: banded, not continuous — ratio 2 and ratio 2.9 " +
			"both land in the same band and produce IDENTICAL power",
			BattleManager._electro_ball_power(200, 100)
			== BattleManager._electro_ball_power(290, 100))


# ── Section F: Snore ─────────────────────────────────────────────────────

func _test_snore() -> void:
	var snore := _load_move(173)

	# (i) usable while genuinely asleep — bypasses the normal "can't move" block.
	var atk_i := _make_mon("SnoreAtk1", 300, 60, 60, 100, 60, 60)
	var def_i := _make_mon("SnoreDef1", 300, 60, 60, 60, 60, 50)
	atk_i.add_move(snore)
	def_i.add_move(_load_move(45))
	atk_i.status = BattlePokemon.STATUS_SLEEP
	atk_i.sleep_turns = 5
	var executed := [false]
	var bm1 := _make_bm()
	bm1._force_hit = true
	bm1.move_executed.connect(func(a, _d, m, _amt):
		if a == atk_i and m == snore: executed[0] = true)
	bm1.start_battle(atk_i, def_i)
	bm1.queue_free()
	_chk("F.01 Snore fires while the user is genuinely asleep (usable_while_asleep)",
			executed[0] == true)

	# (ii) discriminator: also usable while genuinely awake, no restriction.
	var atk_ii := _make_mon("SnoreAtk2", 300, 60, 60, 100, 60, 60)
	var def_ii := _make_mon("SnoreDef2", 300, 60, 60, 60, 60, 50)
	atk_ii.add_move(snore)
	def_ii.add_move(_load_move(45))
	var dealt := []
	var bm2 := _make_bm()
	bm2._force_hit = true
	bm2._force_roll = 100
	bm2._force_crit = false
	bm2.move_executed.connect(func(a, _d, m, amount):
		if a == atk_ii and m == snore and dealt.is_empty():
			dealt.append(amount))
	bm2.start_battle(atk_ii, def_ii)
	bm2.queue_free()
	_chk("F.02 discriminator: Snore also connects normally while genuinely awake",
			dealt.size() == 1 and dealt[0] > 0)


# ── Section G: Endure ────────────────────────────────────────────────────

func _test_endure() -> void:
	var endure := _load_move(203)

	# (i) guarantees survival at 1 HP against an otherwise-lethal hit.
	# Snapshotted via move_executed (fires AFTER the HP mutation), NOT the
	# `endured` signal itself (which fires BEFORE `target.current_hp` is
	# actually written — the same pitfall CLAUDE.md's own testing
	# conventions document for item_effect_triggered).
	var user_i := _make_mon("EndUser1", 300, 60, 60, 60, 60, 100)
	var foe_i := _make_mon("EndFoe1", 300, 200, 60, 60, 60, 50)
	user_i.add_move(endure)
	foe_i.add_move(_load_move(33))  # Tackle
	user_i.current_hp = 30
	var hp_after := [-1]
	var bm1 := _make_bm()
	bm1._force_hit = true
	bm1._force_roll = 100
	bm1._force_crit = false
	bm1.move_executed.connect(func(a, d, _m, _amt):
		if a == foe_i and d == user_i and hp_after[0] == -1:
			hp_after[0] = user_i.current_hp)
	bm1.start_battle(user_i, foe_i)
	bm1.queue_free()
	_chk("G.01 Endure guarantees survival at exactly 1 HP against a lethal hit",
			hp_after[0] == 1)

	# (ii) does NOT block the incoming hit itself (unlike Protect) — the
	# attacker's move still connects and deals real (pre-clamp) damage,
	# confirmed via the `endured` signal firing at all (proving the hit
	# landed and would have been lethal) rather than `move_missed`.
	var user_ii := _make_mon("EndUser2", 300, 60, 60, 60, 60, 100)
	var foe_ii := _make_mon("EndFoe2", 300, 200, 60, 60, 60, 50)
	user_ii.add_move(endure)
	foe_ii.add_move(_load_move(33))
	user_ii.current_hp = 30
	var missed := [false]
	var endured_fired := [false]
	var bm2 := _make_bm()
	bm2._force_hit = true
	bm2._force_roll = 100
	bm2._force_crit = false
	bm2.move_missed.connect(func(a, _reason): if a == foe_ii: missed[0] = true)
	bm2.endured.connect(func(mon): if mon == user_ii: endured_fired[0] = true)
	bm2.start_battle(user_ii, foe_ii)
	bm2.queue_free()
	_chk("G.02 discriminator: Endure does NOT block the incoming move (no move_missed " +
			"for the attacker) — only guarantees survival",
			missed[0] == false and endured_fired[0] == true)

	# (iii) correct chain position: Endure fires even for a Pokémon that
	# would ALSO qualify for Sturdy (full HP, Sturdy ability) — confirming
	# Endure is checked FIRST, matching source's real priority order. Low
	# base_hp + a maxed-out attacker guarantees a ONE-SHOT-lethal hit on
	# turn 1 (protect_consecutive == 0, `_roll_protect_success` is 100%
	# deterministic at that ramp tier, no RNG forcing needed) — avoiding any
	# reliance on later turns' own unforced consecutive-use fail-chance roll,
	# which has no forcing seam in this codebase.
	var user_iii := _make_mon("EndUser3", 10, 60, 60, 60, 60, 100)
	var foe_iii := _make_mon("EndFoe3", 300, 255, 60, 60, 60, 50)
	user_iii.add_move(endure)
	foe_iii.add_move(_load_move(33))
	var sturdy := AbilityData.new()
	sturdy.ability_id = AbilityManager.ABILITY_STURDY
	user_iii.ability = sturdy
	# user_iii stays at full HP (Sturdy's own gate), Endure should still be
	# the one that fires (distinguishable via the `endured` signal, since
	# Sturdy fires `ability_triggered(mon, "sturdy")` instead).
	var endured_iii := [false]
	var sturdy_fired := [false]
	var bm3 := _make_bm()
	bm3._force_hit = true
	bm3._force_roll = 100
	bm3._force_crit = false
	bm3.endured.connect(func(mon): if mon == user_iii and not endured_iii[0]: endured_iii[0] = true)
	bm3.ability_triggered.connect(func(mon, tag):
		if mon == user_iii and tag == "sturdy": sturdy_fired[0] = true)
	bm3.start_battle(user_iii, foe_iii)
	bm3.queue_free()
	_chk("G.03 Endure is checked BEFORE Sturdy in the survive-lethal-hit chain",
			endured_iii[0] == true and sturdy_fired[0] == false)


# ── Section H: Fell Stinger ──────────────────────────────────────────────

func _test_fell_stinger() -> void:
	var fell_stinger := _load_move(565)

	# (i) +3 Attack on a KO.
	var atk_i := _make_mon("FSAtk1", 300, 200, 60, 60, 60, 100)
	var def_i := _make_mon("FSDef1", 300, 60, 60, 60, 60, 50)
	atk_i.add_move(fell_stinger)
	def_i.add_move(_load_move(45))
	def_i.current_hp = 1
	var boost := [-1]
	var bm1 := _make_bm()
	bm1._force_hit = true
	bm1._force_roll = 100
	bm1._force_crit = false
	bm1.stat_stage_changed.connect(func(mon, stage, delta):
		if mon == atk_i and stage == BattlePokemon.STAGE_ATK and boost[0] == -1:
			boost[0] = delta)
	bm1.start_battle(atk_i, def_i)
	bm1.queue_free()
	_chk("H.01 Fell Stinger raises the user's own Attack by +3 on a KO", boost[0] == 3)

	# (ii) discriminator: no boost if the hit does NOT KO.
	var atk_ii := _make_mon("FSAtk2", 300, 60, 60, 60, 60, 100)
	var def_ii := _make_mon("FSDef2", 300, 300, 60, 60, 60, 50)
	atk_ii.add_move(fell_stinger)
	def_ii.add_move(_load_move(45))
	var boost2 := [-1]
	var bm2 := _make_bm()
	bm2._force_hit = true
	bm2._force_roll = 100
	bm2._force_crit = false
	bm2.stat_stage_changed.connect(func(mon, stage, delta):
		if mon == atk_ii and stage == BattlePokemon.STAGE_ATK and boost2[0] == -1:
			boost2[0] = delta)
	bm2.start_battle(atk_ii, def_ii)
	bm2.queue_free()
	_chk("H.02 discriminator: no Attack boost when the hit does NOT KO the target",
			boost2[0] == -1)


# ── Section I: Magnet Rise ───────────────────────────────────────────────

func _test_magnet_rise() -> void:
	var magnet_rise := _load_move(393)
	var earthquake := _load_move(89)

	var mon := _make_mon("MRMon")
	_chk("I.01 is_grounded is TRUE with no Magnet Rise active",
			AbilityManager.is_grounded(mon) == true)
	mon.magnet_rise_turns = 5
	_chk("I.02 is_grounded is FALSE while Magnet Rise is active",
			AbilityManager.is_grounded(mon) == false)
	_chk("I.03 blocks_move_type grants full Ground-move immunity while active",
			AbilityManager.blocks_move_type(mon, TypeChart.TYPE_GROUND) == true)

	# Full-battle confirmation: a Ground-type move deals 0 damage to a
	# Magnet-Rise'd target.
	var atk_i := _make_mon("MRAtk1", 300, 60, 60, 60, 60, 50)
	var def_i := _make_mon("MRDef1", 300, 60, 60, 60, 60, 100)
	atk_i.add_move(earthquake)
	def_i.add_move(magnet_rise)
	def_i.add_move(_load_move(45))
	var dealt := []
	var bm1 := _make_bm()
	bm1._force_hit = true
	bm1._force_roll = 100
	bm1._force_crit = false
	bm1.move_executed.connect(func(a, _d, m, amount):
		if a == atk_i and m == earthquake and dealt.size() < 2:
			dealt.append(amount))
	bm1.start_battle(atk_i, def_i)
	bm1.queue_free()
	_chk("I.04 a Ground-type move deals 0 damage to a Magnet-Rise'd target",
			dealt.size() >= 1 and dealt[dealt.size() - 1] == 0)


# ── Section J: Smack Down ────────────────────────────────────────────────

func _test_smack_down() -> void:
	var smack_down := _load_move(479)
	var earthquake := _load_move(89)

	var flying_mon := _make_mon("SDMon", 100, 60, 60, 60, 60, 60, TypeChart.TYPE_FLYING)
	_chk("J.01 a Flying-type is naturally immune to Ground moves (baseline)",
			AbilityManager.blocks_move_type(flying_mon, TypeChart.TYPE_GROUND) == false
			and TypeChart.get_effectiveness(TypeChart.TYPE_GROUND, flying_mon.species.types) == 0.0)
	flying_mon.smack_down_active = true
	_chk("J.02 is_grounded is TRUE once Smack Down is active",
			AbilityManager.is_grounded(flying_mon) == true)
	_chk("J.03 Ground-vs-Flying immunity is bypassed once Smack Down is active " +
			"(grounded_override)",
			TypeChart.get_effectiveness(TypeChart.TYPE_GROUND, flying_mon.species.types,
					false, false, true) > 0.0)

	# Full-battle confirmation: a Ground-type move connects against a
	# Flying-type target once Smack Down has hit it.
	var atk_i := _make_mon("SDAtk1", 300, 100, 60, 60, 60, 100)
	var def_i := _make_mon("SDDef1", 300, 60, 60, 60, 60, 50, TypeChart.TYPE_FLYING)
	atk_i.add_move(smack_down)
	atk_i.add_move(earthquake)
	def_i.add_move(_load_move(45))
	var dealt := []
	var bm1 := _make_bm()
	bm1._force_hit = true
	bm1._force_roll = 100
	bm1._force_crit = false
	bm1.queue_move(0, 0)  # atk_i turn 1: Smack Down
	bm1.queue_move(0, 1)  # atk_i turn 2: Earthquake
	bm1.move_executed.connect(func(a, _d, m, amount):
		if a == atk_i and m == earthquake and dealt.is_empty():
			dealt.append(amount))
	bm1.start_battle(atk_i, def_i)
	bm1.queue_free()
	_chk("J.04 Earthquake connects against a Smack-Down'd Flying-type target",
			dealt.size() == 1 and dealt[0] > 0)


# ── Section K: Ingrain ───────────────────────────────────────────────────

func _test_ingrain() -> void:
	var ingrain := _load_move(275)
	var roar := _load_move(46)

	# (i) grounds the user.
	var mon := _make_mon("IngMon", 100, 60, 60, 60, 60, 60, TypeChart.TYPE_FLYING)
	_chk("K.01 baseline: a Flying-type is ungrounded", AbilityManager.is_grounded(mon) == false)
	mon.ingrain_active = true
	_chk("K.02 is_grounded is TRUE once Ingrain is active", AbilityManager.is_grounded(mon) == true)

	# (ii) blocks voluntary switching.
	var mon2 := _make_mon("IngMon2")
	_chk("K.03 is_trapped is FALSE with no Ingrain active",
			AbilityManager.is_trapped(mon2, []) == false)
	mon2.ingrain_active = true
	_chk("K.04 is_trapped is TRUE once Ingrain is active",
			AbilityManager.is_trapped(mon2, []) == true)

	# (iii) end-of-turn self-heal of maxHP/16.
	var atk_iii := _make_mon("IngAtk3", 300, 60, 60, 60, 60, 100)
	var def_iii := _make_mon("IngDef3", 300, 60, 60, 60, 60, 50)
	atk_iii.add_move(ingrain)
	def_iii.add_move(_load_move(45))
	atk_iii.current_hp = 100
	var healed := [-1]
	var bm1 := _make_bm()
	bm1._force_hit = true
	bm1.ring_heal_tick.connect(func(mon3, amount):
		if mon3 == atk_iii and healed[0] == -1: healed[0] = amount)
	bm1.start_battle(atk_iii, def_iii)
	bm1.queue_free()
	_chk("K.05 Ingrain heals the user maxHP/16 at end of turn",
			healed[0] == atk_iii.max_hp / 16)

	# (iv) blocks being forced out by Roar.
	var atk_iv := _make_mon("IngAtk4", 300, 60, 60, 60, 60, 100)
	var def_iv := _make_mon("IngDef4", 300, 60, 60, 60, 60, 50)
	var bench_iv := _make_mon("IngBench4", 300, 60, 60, 60, 60, 50)
	atk_iv.add_move(roar)
	def_iv.add_move(ingrain)
	var blocked := [false]
	var switched := [false]
	var bm2 := _make_bm()
	bm2._force_hit = true
	bm2._force_roar_rng = 0
	bm2.move_effect_failed.connect(func(_a, reason):
		if reason == "ingrain_blocks_switch": blocked[0] = true)
	bm2.forced_switch.connect(func(_o, _n): switched[0] = true)
	bm2.start_battle_with_parties(
			BattleParty.single(atk_iv), _bench_party(def_iv, bench_iv))
	bm2.queue_free()
	_chk("K.06 Ingrain blocks the target from being forced out by Roar",
			blocked[0] == true and switched[0] == false)


# ── Section L: Aqua Ring ─────────────────────────────────────────────────

func _test_aqua_ring() -> void:
	var aqua_ring := _load_move(392)

	# (i) end-of-turn self-heal, same formula as Ingrain.
	var atk_i := _make_mon("ARAtk1", 300, 60, 60, 60, 60, 100)
	var def_i := _make_mon("ARDef1", 300, 60, 60, 60, 60, 50)
	atk_i.add_move(aqua_ring)
	def_i.add_move(_load_move(45))
	atk_i.current_hp = 100
	var healed := [-1]
	var bm1 := _make_bm()
	bm1._force_hit = true
	bm1.ring_heal_tick.connect(func(mon, amount):
		if mon == atk_i and healed[0] == -1: healed[0] = amount)
	bm1.start_battle(atk_i, def_i)
	bm1.queue_free()
	_chk("L.01 Aqua Ring heals the user maxHP/16 at end of turn",
			healed[0] == atk_i.max_hp / 16)

	# (ii) discriminator: does NOT ground the user or block switching, unlike Ingrain.
	var mon2 := _make_mon("ARMon2", 100, 60, 60, 60, 60, 60, TypeChart.TYPE_FLYING)
	mon2.aqua_ring_active = true
	_chk("L.02 discriminator: Aqua Ring does NOT ground the user (unlike Ingrain)",
			AbilityManager.is_grounded(mon2) == false)
	_chk("L.03 discriminator: Aqua Ring does NOT block voluntary switching (unlike Ingrain)",
			AbilityManager.is_trapped(mon2, []) == false)


# ── Section M: Payback ───────────────────────────────────────────────────

func _test_payback() -> void:
	var payback := _load_move(371)
	var tackle := _load_move(33)

	# Slow attacker, fast defender (always acts first). Turn 1: the defender
	# has already acted but ALSO just switched in this same turn (every
	# battle's own starting leads), so Payback should NOT double. A later
	# turn (no switching involved): the defender has already acted and did
	# NOT just switch in, so Payback SHOULD double. Comparing the first vs.
	# a later Payback hit isolates exactly the switched-in exemption.
	var atk := _make_mon("PBAtk", 300, 100, 60, 60, 60, 10)
	var def := _make_mon("PBDef", 300, 60, 60, 60, 60, 100)
	atk.add_move(payback)
	def.add_move(tackle)
	var hits := []
	var bm := _make_bm()
	bm._force_hit = true
	bm._force_roll = 100
	bm._force_crit = false
	bm.move_executed.connect(func(a, _d, m, amount):
		if a == atk and m == payback and hits.size() < 2:
			hits.append(amount))
	bm.start_battle(atk, def)
	bm.queue_free()
	_chk("M.01 Payback does NOT double on turn 1 despite the target already " +
			"having acted (target also just switched in), but DOES double on a " +
			"later turn once the target is no longer freshly switched in",
			hits.size() == 2 and absi(hits[1] - hits[0] * 2) <= 2)
