extends Node

# [M36 anim-turn fix] `gAnimMoveTurn` — the value `choosetwoturnanim` and
# `jumpifmoveturn` branch on, for the 36 move animations that read it.
#
# ⚠️ **THIS SUITE EXISTS BECAUSE THE SEAM HAD NO COVERAGE.**
# `m36b_anim_vm_test` already drives `AnimScriptVM.move_turn` directly and
# tests both `choosetwoturnanim` arms — correctly, and it passed throughout.
# What nothing tested was the value the battle screen FEEDS into it, which was
# wrong in two different ways at once and was found by play instead:
#
#   * multi-hit: a constant 0, so Comet Punch played `CometPunchLeft` on every
#     hit rather than alternating fists;
#   * two-turn: INVERTED, so the charge turn played `SolarBeamUnleash` and the
#     release turn played `SolarBeamSetUp`.
#
# Same shape as `[M27H H4]`'s `caught_pokemon()` bug: a guard on the callee
# cannot see a caller handing it the wrong value.
#
# Every assertion here is written from the NEGATION per M36 rule (7) — each
# one is chosen so the specific plausible WRONG version fails it, not merely
# so the correct version passes.
#
# Source: reset per move use `battle_script_commands.c:5999`; `= 1` on the
# release turn `battle_scripts_1.s:1867-1868`; incremented per animation
# played `battle_script_commands.c:1447`.

var _pass := 0
var _fail := 0

# Balance guard, per this project's Z.99 convention: a section that bails
# early would otherwise silently drop assertions and nothing would say so.
const EXPECTED_TOTAL := 16


func _ready() -> void:
	_test_section_a_multi_hit_alternates()
	_test_section_b_two_turn_charge_then_release()
	_test_section_c_the_screen_seam()

	_chk("Z.99 assertion count balances (%d of %d)" % [_pass + _fail, EXPECTED_TOTAL],
			_pass + _fail == EXPECTED_TOTAL - 1)

	var total := _pass + _fail
	print("m36_anim_turn_test: %d/%d passed" % [_pass, total])
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


func _make_bm() -> BattleManager:
	var bm := BattleManager.new()
	add_child(bm)
	return bm


# Neutral nature and zero IVs, per this project's own fixture convention —
# an unpinned stat is the flake class `[M18.5g]` root-caused.
func _make_mon(mon_name: String, type1: int, base_hp: int = 200,
		base_atk: int = 60, base_spd: int = 60) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types.append(type1)
	sp.base_hp = base_hp
	sp.base_attack = base_atk
	sp.base_defense = 60
	sp.base_sp_attack = 60
	sp.base_sp_defense = 60
	sp.base_speed = base_spd
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])


# An inert move for the punching bag, so the defender never ends the battle
# early and never contributes a `move_executed` this suite would have to
# filter out by accident rather than by design.
func _make_dummy_move() -> MoveData:
	var m := MoveData.new()
	m.move_name = "Nothing"
	m.type = TypeChart.TYPE_NORMAL
	m.power = 0
	m.accuracy = 0
	m.pp = 40
	return m


# ⚠️ `start_battle` runs the WHOLE battle, so a naive "record every event"
# recorder aggregates however many move uses happened to occur — the
# whole-battle-aggregation pitfall this project has hit repeatedly. This
# records only the FIRST monotonically-increasing run starting at 0, which is
# exactly one move use's worth of animations, and latches shut afterwards.
class TurnRecorder:
	var seq: Array[int] = []
	var _closed := false
	func record(value: int) -> void:
		if _closed:
			return
		if seq.is_empty():
			if value != 0:
				return  # not the start of a move use yet
			seq.append(value)
		elif value == seq[seq.size() - 1] + 1:
			seq.append(value)
		else:
			_closed = true


# ── Section A: multi-hit alternates ─────────────────────────────────────────
#
# Comet Punch's animation is `choosetwoturnanim CometPunchLeft,
# CometPunchRight`, selected on `move_turn & 1`. Source increments per
# animation played, so a 4-hit use must read 0, 1, 2, 3.

func _test_section_a_multi_hit_alternates() -> void:
	var comet_punch := _load_move(4)
	_chk("A.01 fixture is really a multi-hit move (else this section proves nothing)",
			comet_punch.multi_hit == true)

	var bm := _make_bm()
	bm._force_multi_hit_count = 4
	bm._force_hit = true
	var atk := _make_mon("AtkA", TypeChart.TYPE_NORMAL, 200, 60, 120)
	atk.add_move(comet_punch)
	var def := _make_mon("DefA", TypeChart.TYPE_NORMAL, 900, 60, 20)
	def.add_move(_make_dummy_move())

	var rec := TurnRecorder.new()
	bm.move_executed.connect(func(a, _d, _m, _dmg):
		if a == atk:
			rec.record(bm.anim_turn))
	bm.queue_move(0, 0)
	bm.queue_move(1, 0)
	bm.start_battle(atk, def)

	_chk("A.02 all four hits of one use were recorded (got %d)" % rec.seq.size(),
			rec.seq.size() == 4)
	# THE discriminator. The bug was a constant 0 — which satisfies "starts at
	# 0" and "is not empty", so neither of those would have caught it.
	_chk("A.03 the counter ADVANCES across hits rather than staying constant",
			rec.seq.size() == 4 and rec.seq[0] != rec.seq[3])
	# ⚠️ `rec.seq == [0, 1, 2, 3] as Array[int]` does NOT parse: `as` binds
	# looser than `==`, so it reads as `(rec.seq == [...]) as Array[int]` —
	# the same operator-precedence class this project already records for
	# string `+` against `%`. Bind the type to a local instead.
	var expected_seq: Array[int] = [0, 1, 2, 3]
	_chk("A.04 the exact per-hit sequence is 0,1,2,3 (got %s)" % str(rec.seq),
			rec.seq == expected_seq)
	# What the animation actually consumes: `& 1`. Asserted separately from the
	# raw values, because it is the property that makes the fists alternate and
	# a future off-by-one in the counter would still be caught here.
	var parity: Array = []
	for v in rec.seq:
		parity.append(v & 1)
	_chk("A.05 the arm chosen alternates left/right/left/right (got %s)" % str(parity),
			parity == [0, 1, 0, 1])


# ── Section B: two-turn charge then release ─────────────────────────────────
#
# Solar Beam's animation is `choosetwoturnanim SolarBeamSetUp,
# SolarBeamUnleash`. Source resets to 0 per move use and the release turn
# explicitly sets 1, so the charge turn plays SetUp and the release plays
# Unleash.

func _test_section_b_two_turn_charge_then_release() -> void:
	var solar_beam := _load_move(76)
	_chk("B.01 fixture is really a two-turn move (else this section proves nothing)",
			solar_beam.two_turn == true)

	var bm := _make_bm()
	bm._force_hit = true
	var atk := _make_mon("AtkB", TypeChart.TYPE_NORMAL, 400, 60, 120)
	atk.add_move(solar_beam)
	var def := _make_mon("DefB", TypeChart.TYPE_NORMAL, 900, 60, 20)
	def.add_move(_make_dummy_move())

	# Not the run-recorder: the two events here are 0 then 1, which IS a
	# monotonic run, but a third turn would begin another charge at 0 and the
	# recorder would latch. Capturing the first two of this attacker's events
	# directly says what is meant.
	var seen: Array[int] = []
	bm.move_executed.connect(func(a, _d, _m, _dmg):
		if a == atk and seen.size() < 2:
			seen.append(bm.anim_turn))
	bm.queue_move(0, 0)
	bm.queue_move(1, 0)
	bm.start_battle(atk, def)

	_chk("B.02 both the charge and the release turn were recorded (got %d)" % seen.size(),
			seen.size() == 2)
	_chk("B.03 the CHARGE turn reads 0, so choosetwoturnanim takes SolarBeamSetUp",
			seen.size() == 2 and seen[0] == 0)
	_chk("B.04 the RELEASE turn reads 1, so it takes SolarBeamUnleash",
			seen.size() == 2 and seen[1] == 1)
	# ⚠️ The bug was the pair INVERTED, not absent — so "charge is 0" and
	# "release is 1" each individually fail under it, but this states the
	# ordering as one claim so a future half-fix cannot look green.
	_chk("B.05 charge STRICTLY precedes release in value (the exact inversion that shipped)",
			seen.size() == 2 and seen[0] < seen[1])


# ── Section C: the screen seam ──────────────────────────────────────────────
#
# The half nothing covered. `_anim_turn_for` must read the engine's counter
# rather than deriving one, and must degrade rather than crash with no
# BattleManager — `_bm` is `@onready`, so it is null on an off-tree instance,
# which several suites construct deliberately.

func _test_section_c_the_screen_seam() -> void:
	var scene: PackedScene = load("res://scenes/battle/battle_screen_singles.tscn")
	var bs := scene.instantiate()
	_chk("C.01 the battle screen still exposes _anim_turn_for",
			bs.has_method("_anim_turn_for"))

	# Off-tree, so `_bm` is null. A crash here is the regression this guards.
	_chk("C.02 degrades to 0 with no BattleManager rather than erroring",
			bs._anim_turn_for(null) == 0)

	var bm := _make_bm()
	bs._bm = bm

	bm.anim_turn = 0
	_chk("C.03 reads the engine's counter (0)", bs._anim_turn_for(null) == 0)
	bm.anim_turn = 3
	# THE discriminator for this section. The old implementation derived the
	# value from the attacker's `charging_move` and could only ever answer 0 or
	# 1 — so a fixture using 0 or 1 could not tell the two apart. 3 is
	# unreachable by the old code by construction.
	_chk("C.04 reads a value the OLD derived boolean could never produce (3)",
			bs._anim_turn_for(null) == 3)

	# And it must not be reading the attacker at all any more.
	var charging := _make_mon("CharginC", TypeChart.TYPE_NORMAL)
	charging.charging_move = _load_move(76)
	bm.anim_turn = 0
	_chk("C.05 a CHARGING attacker no longer forces 1 — the inversion's own source",
			bs._anim_turn_for(charging) == 0)

	bs.free()
