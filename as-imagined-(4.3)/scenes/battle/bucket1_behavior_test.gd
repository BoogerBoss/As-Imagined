extends Node

# [M21.5 Bucket 1 verification follow-up] Bucket 1's own implementation
# session (docs/m21_5_scope.md) shipped 71 field additions across 69 moves
# and 10 flag categories, but the test-audit-first pass performed there only
# repaired EXISTING data-integrity assertions that would otherwise have
# broken (m19_bucket1_test.gd's Feint Attack row, m19_bucket2_test.gd's 9
# token-list rows, m17n3_test.gd's Giga Drain row) — it never added NEW
# runtime-behavior tests proving each fixed flag's real consumer mechanism
# actually fires for the SPECIFIC move it was added to. Every pre-existing
# consumer test in this codebase (Iron Fist's own S3 in m17n5_test.gd,
# Sharpness's own S10, Triage's own S7, Stomp's own minimize test, Magic
# Bounce's own suite, Snatch's own (iii) case) uses either a synthetic
# MoveData or an already-correct move that predates this session — none of
# them touch Mega Punch/Headlong Rush/Aerial Ace/Absorb/Body Slam/Whirlpool/
# Tickle/Aqua Ring/Substitute/Growl specifically. This file closes that gap:
# one representative move per fixed flag category, proving the flag's own
# already-built consumer now recognizes the REAL `.tres` data Bucket 1
# regenerated, each with a negative control using an unaffected move.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_punching_move()
	_test_slicing_move()
	_test_healing_move()
	_test_double_power_on_minimized()
	_test_damages_underwater()
	_test_bounceable()
	_test_snatch_affected()
	_test_ignores_protect()
	_test_ignores_substitute()

	var total := _pass + _fail
	print("bucket1_behavior_test: %d/%d passed" % [_pass, total])
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


# One-action direct dispatch: bypasses full-battle nondeterminism/turn
# machinery, matching the established `_phase_move_execution()`-direct-call
# pattern (e.g. d4_bundle8_test.gd's Snatch case (ii)).
func _dispatch_one_action(atk: BattlePokemon, def: BattlePokemon,
		move: MoveData) -> BattleManager:
	var bm := _make_bm()
	bm._combatants = [atk, def]
	bm._turn_order = [atk, def]
	bm._active_per_side = 1
	bm._chosen_switch_slots = [-1, -1]
	bm._chosen_targets = [1, 0]
	bm._chosen_moves = [move, null]
	bm._current_actor_index = 0
	bm._phase_move_execution()
	return bm


# ── punching_move: Mega Punch(5) — Iron Fist's own power boost ─────────────

func _test_punching_move() -> void:
	var iron_fist := _load_ability(89)
	var mega_punch := _load_move(5)
	var tackle := _load_move(33)  # negative-control fixture: no punching_move

	var holder := _make_mon("PM_Holder")
	holder.ability = iron_fist
	var target := _make_mon("PM_Target")
	var plain := _make_mon("PM_Plain")

	var boosted: Dictionary = DamageCalculator.calculate(holder, target, mega_punch, 100, false)
	var unboosted: Dictionary = DamageCalculator.calculate(plain, target, mega_punch, 100, false)
	_chk("punching_move: Iron Fist boosts the REAL Mega Punch(5)'s damage",
			boosted["damage"] > unboosted["damage"])

	var holder_tackle: Dictionary = DamageCalculator.calculate(holder, target, tackle, 100, false)
	var plain_tackle: Dictionary = DamageCalculator.calculate(plain, target, tackle, 100, false)
	_chk("punching_move negative control: Iron Fist gives no boost on Tackle " +
			"(no punching_move)", holder_tackle["damage"] == plain_tackle["damage"])


# ── slicing_move: Aerial Ace(332) — Sharpness's own power boost ────────────

func _test_slicing_move() -> void:
	var sharpness := _load_ability(292)
	var aerial_ace := _load_move(332)
	var tackle := _load_move(33)

	var holder := _make_mon("SM_Holder")
	holder.ability = sharpness
	var target := _make_mon("SM_Target")
	var plain := _make_mon("SM_Plain")

	var boosted: Dictionary = DamageCalculator.calculate(holder, target, aerial_ace, 100, false)
	var unboosted: Dictionary = DamageCalculator.calculate(plain, target, aerial_ace, 100, false)
	_chk("slicing_move: Sharpness boosts the REAL Aerial Ace(332)'s damage",
			boosted["damage"] > unboosted["damage"])

	var holder_tackle: Dictionary = DamageCalculator.calculate(holder, target, tackle, 100, false)
	var plain_tackle: Dictionary = DamageCalculator.calculate(plain, target, tackle, 100, false)
	_chk("slicing_move negative control: Sharpness gives no boost on Tackle " +
			"(no slicing_move)", holder_tackle["damage"] == plain_tackle["damage"])


# ── healing_move: Absorb(71) — Triage's own +3 priority ────────────────────

func _test_healing_move() -> void:
	var triage := _load_ability(205)
	var absorb := _load_move(71)
	var tackle := _load_move(33)

	var holder := _make_mon("HM_Holder")
	holder.ability = triage

	_chk("healing_move: Triage grants +3 priority for the REAL Absorb(71)",
			AbilityManager.move_priority_bonus(holder, absorb, false) == 3)
	_chk("healing_move negative control: Triage grants +0 priority for Tackle " +
			"(no healing_move)", AbilityManager.move_priority_bonus(holder, tackle, false) == 0)


# ── double_power_on_minimized: Body Slam(34) — the Stomp-family post-roll ──
# ── modifier ────────────────────────────────────────────────────────────

func _test_double_power_on_minimized() -> void:
	var body_slam := _load_move(34)
	var tackle := _load_move(33)

	var atk := _make_mon("DPM_Atk")
	var minimized_def := _make_mon("DPM_MinDef")
	minimized_def.minimized = true
	var plain_def := _make_mon("DPM_PlainDef")
	plain_def.minimized = false

	var vs_minimized: Dictionary = DamageCalculator.calculate(atk, minimized_def, body_slam, 100, false)
	var vs_plain: Dictionary = DamageCalculator.calculate(atk, plain_def, body_slam, 100, false)
	_chk("double_power_on_minimized: the REAL Body Slam(34) deals more damage " +
			"to a minimized target", vs_minimized["damage"] > vs_plain["damage"])

	var tackle_vs_minimized: Dictionary = DamageCalculator.calculate(atk, minimized_def, tackle, 100, false)
	var tackle_vs_plain: Dictionary = DamageCalculator.calculate(atk, plain_def, tackle, 100, false)
	_chk("double_power_on_minimized negative control: Tackle (no flag) deals " +
			"the same damage regardless of minimized state",
			tackle_vs_minimized["damage"] == tackle_vs_plain["damage"])


# ── damages_underwater: Whirlpool(250) — the semi-invulnerable bypass ──────

func _test_damages_underwater() -> void:
	var whirlpool := _load_move(250)
	var tackle := _load_move(33)

	_chk("damages_underwater: the REAL Whirlpool(250) can hit a Dive user",
			StatusManager._can_hit_semi_invulnerable(whirlpool, MoveData.SEMI_INV_UNDERWATER))
	_chk("damages_underwater negative control: Tackle (no flag) cannot hit " +
			"a Dive user",
			not StatusManager._can_hit_semi_invulnerable(tackle, MoveData.SEMI_INV_UNDERWATER))


# ── bounceable: Tickle(321) — Magic Bounce's reflect-back swap ─────────────

func _test_bounceable() -> void:
	var magic_bounce := _load_ability(156)
	var tickle := _load_move(321)
	var leer := _load_move(43)  # negative control: bounceable already true, unaffected

	# Positive: Tickle now bounces (it did NOT before this session).
	var atk := _make_mon("BC_Atk")
	var def := _make_mon("BC_Def")
	def.ability = magic_bounce
	var bm := _dispatch_one_action(atk, def, tickle)
	# A successful bounce redirects Tickle's own -1 Atk/-1 Def onto the
	# ORIGINAL ATTACKER, not the Magic-Bounce holder — confirmed by the
	# attacker's own stages dropping instead of the defender's.
	_chk("bounceable: the REAL Tickle(321) bounces off Magic Bounce onto the attacker",
			atk.stat_stages[BattlePokemon.STAGE_ATK] == -1
			and atk.stat_stages[BattlePokemon.STAGE_DEF] == -1
			and def.stat_stages[BattlePokemon.STAGE_ATK] == 0)
	bm.queue_free()

	# Negative control: a move that was ALREADY bounceable before this
	# session (Leer) still bounces too — confirms the fix didn't disturb the
	# pre-existing mechanism, using a real already-correct move as the control
	# rather than a non-bounceable one (which would trivially not bounce).
	var atk2 := _make_mon("BC_Atk2")
	var def2 := _make_mon("BC_Def2")
	def2.ability = magic_bounce
	var bm2 := _dispatch_one_action(atk2, def2, leer)
	_chk("bounceable negative control: Leer (already-correct pre-session) " +
			"still bounces off Magic Bounce, confirming no regression",
			atk2.stat_stages[BattlePokemon.STAGE_DEF] == -1
			and def2.stat_stages[BattlePokemon.STAGE_DEF] == 0)
	bm2.queue_free()


# ── snatch_affected: Aqua Ring(392) — Snatch's steal-and-reassign ──────────
# Mirrors d4_bundle8_test.gd's own established (iii) pattern exactly, with a
# newly-fixed move (Aqua Ring) standing in for that test's Swords Dance
# (which was already snatch_affected=true before this session, fixed by
# [D4 Bundle 8], not Bucket 1).

func _test_snatch_affected() -> void:
	var snatch := _load_move(289)
	var aqua_ring := _load_move(392)

	var atk := _make_mon("SN_Atk", 300, 60, 60, 60, 60, 100)
	atk.add_move(snatch)
	var def := _make_mon("SN_Def", 300, 60, 60, 60, 60, 1)
	def.add_move(aqua_ring)
	var bm := _make_bm()
	# Snapshot at the FIRST Aqua Ring resolution via `move_executed`, not
	# post-battle state — `def`'s only move is Aqua Ring, so a full
	# `start_battle` would let it legitimately re-cast Aqua Ring on its own
	# later turn once the queue drains, setting `def.aqua_ring_active = true`
	# for real and making a post-battle read misreport the steal as having
	# failed. Matches d4_bundle8_test.gd's own established pattern for this
	# exact move (case iii, Swords Dance).
	var seen := [false]
	var atk_flag_after_first := [false]
	var def_flag_after_first := [false]
	bm.move_executed.connect(func(_a, _d, m, _amount):
		if m == aqua_ring and not seen[0]:
			seen[0] = true
			atk_flag_after_first[0] = atk.aqua_ring_active
			def_flag_after_first[0] = def.aqua_ring_active)
	bm.start_battle(atk, def)
	bm.queue_free()
	_chk("snatch_affected: the REAL Aqua Ring(392) is stolen — the SNATCHER " +
			"gets aqua_ring_active, not the original caster",
			atk_flag_after_first[0] == true and def_flag_after_first[0] == false)


# ── ignores_protect: Substitute(164) — bypasses the universal Protect gate ──

func _test_ignores_protect() -> void:
	var substitute_move := _load_move(164)
	var leer := _load_move(43)  # negative control: no ignores_protect

	# Positive: Substitute succeeds even though the (default) target is
	# currently protect_active — confirms Substitute's own dispatch, which
	# sits AFTER the universal `_is_protected_from` gate, is no longer
	# incorrectly blocked.
	var atk := _make_mon("IP_Atk")
	var def := _make_mon("IP_Def")
	def.protect_active = true
	var bm := _dispatch_one_action(atk, def, substitute_move)
	_chk("ignores_protect: the REAL Substitute(164) succeeds despite the " +
			"opponent's protect_active", atk.substitute_hp > 0)
	bm.queue_free()

	# Negative control: an ordinary foe-targeting move WITHOUT ignores_protect
	# (Leer) against the same protect_active defender is correctly blocked.
	var atk2 := _make_mon("IP_Atk2")
	var def2 := _make_mon("IP_Def2")
	def2.protect_active = true
	var missed := [false]
	var bm2 := _make_bm()
	bm2.move_missed.connect(func(_a, reason): if reason == "protected": missed[0] = true)
	bm2._combatants = [atk2, def2]
	bm2._turn_order = [atk2, def2]
	bm2._active_per_side = 1
	bm2._chosen_switch_slots = [-1, -1]
	bm2._chosen_targets = [1, 0]
	bm2._chosen_moves = [leer, null]
	bm2._current_actor_index = 0
	bm2._phase_move_execution()
	_chk("ignores_protect negative control: Leer (no ignores_protect) is " +
			"correctly blocked by the opponent's protect_active",
			missed[0] == true and def2.stat_stages[BattlePokemon.STAGE_DEF] == 0)
	bm2.queue_free()


# ── ignores_substitute: Growl(45) — bypasses the universal foe-targeting ───
# ── Substitute gate ─────────────────────────────────────────────────────

func _test_ignores_substitute() -> void:
	var growl := _load_move(45)
	var kinesis := _load_move(134)  # negative control: no ignores_substitute

	# Positive: Growl's stat drop lands on the defender even though it has
	# an active Substitute — confirms the generic foe-targeting Substitute
	# gate (StatusManager-adjacent, gated on foe_targeting) no longer blocks it.
	var atk := _make_mon("IS_Atk")
	var def := _make_mon("IS_Def")
	def.substitute_hp = 50
	var bm := _dispatch_one_action(atk, def, growl)
	_chk("ignores_substitute: the REAL Growl(45) lowers Attack through an " +
			"active Substitute", def.stat_stages[BattlePokemon.STAGE_ATK] == -1)
	bm.queue_free()

	# Negative control: Kinesis (no ignores_substitute) is correctly blocked
	# by the same Substitute state.
	var atk2 := _make_mon("IS_Atk2")
	var def2 := _make_mon("IS_Def2")
	def2.substitute_hp = 50
	var missed := [false]
	var bm2 := _make_bm()
	# Kinesis has 80% accuracy (unlike Growl's 100%) — force the hit so a
	# natural accuracy miss can't masquerade as the "substitute" miss reason
	# this assertion is actually checking for.
	bm2._force_hit = true
	bm2.move_missed.connect(func(_a, reason): if reason == "substitute": missed[0] = true)
	bm2._combatants = [atk2, def2]
	bm2._turn_order = [atk2, def2]
	bm2._active_per_side = 1
	bm2._chosen_switch_slots = [-1, -1]
	bm2._chosen_targets = [1, 0]
	bm2._chosen_moves = [kinesis, null]
	bm2._current_actor_index = 0
	bm2._phase_move_execution()
	_chk("ignores_substitute negative control: Kinesis (no ignores_substitute) " +
			"is correctly blocked by the same active Substitute",
			missed[0] == true and def2.stat_stages[BattlePokemon.STAGE_ACCURACY] == 0)
	bm2.queue_free()
