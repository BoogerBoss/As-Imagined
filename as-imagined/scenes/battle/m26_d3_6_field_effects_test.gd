extends Node

# [M26D3-6] Regression suite for field- and delayed-effect narration.
#
# All ten signals here were DEBUG-ONLY before this sub-phase — wired to the F3
# overlay, which is off by default — so Trick Room, Tailwind, Safeguard, Mist,
# Mud/Water Sport, Wish, Future Sight and Healing Wish / Lunar Dance were
# completely unannounced in normal play despite being strategically
# significant. See docs/m26_d3_recon.md §1: the "debug-only" population was the
# single biggest thing the original 2026-07-25 audit missed.
#
# The load-bearing assertion is C.01: `wish_scheduled` must stay SILENT,
# because source's own BattleScript_EffectWish contains no printstring at all.
# It is the one signal in this group that would be easy — and wrong — to wire
# by symmetry with future_sight_scheduled.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_trick_room()
	_test_side_conditions_set()
	_test_side_conditions_expired()
	_test_side_label_reads_correctly_for_both_sides()
	_test_field_sports()
	_test_future_sight_both_ends()
	_test_wish_resolution_only()
	_test_healing_wish_and_lunar_dance()
	_test_unknown_names_stay_silent()
	_test_real_battle_end_to_end()

	var total := _pass + _fail
	print("m26_d3_6_field_effects_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


# ── Fixtures ─────────────────────────────────────────────────────────────

func _make_mon(mon_name: String) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types = [TypeChart.TYPE_NORMAL]
	sp.base_hp = 300
	sp.base_attack = 60
	sp.base_defense = 60
	sp.base_sp_attack = 60
	sp.base_sp_defense = 60
	sp.base_speed = 60
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])


func _make_bm() -> BattleManager:
	var bm := BattleManager.new()
	add_child(bm)
	return bm


func _make_bs(bm: BattleManager, player: BattlePokemon = null) -> BattleScreenShared:
	var bs := BattleScreenShared.new()
	var pp := BattleParty.new()
	if player != null:
		var members: Array[BattlePokemon] = [player]
		pp.members = members
		pp.active_indices = [0]
	else:
		pp.active_indices = []
	bs._player_party = pp
	bs._opp_party = BattleParty.new()
	bs._opp_party.active_indices = []
	bs._bm = bm
	bs._wire_log_signals()
	return bs


func _narrative(bs: BattleScreenShared) -> String:
	var out := ""
	for entry: Dictionary in bs._debug_entries:
		if entry["category"] == BattleScreenShared.DebugCategory.NARRATIVE:
			out += str(entry["text"]) + "\n"
	return out.strip_edges()


# ── A. Trick Room ────────────────────────────────────────────────────────

func _test_trick_room() -> void:
	var bm := _make_bm()
	var bs := _make_bs(bm)
	bm.trick_room_set.emit()
	_chk("A.01 Trick Room going up is announced",
			_narrative(bs) == "The dimensions were twisted!")
	bs.free()
	bm.queue_free()

	var bm2 := _make_bm()
	var bs2 := _make_bs(bm2)
	bm2.trick_room_ended.emit()
	# This one matches source's own wording exactly — it needs no caster name.
	_chk("A.02 Trick Room ending matches source's wording verbatim",
			_narrative(bs2) == "The twisted dimensions returned to normal!")
	bs2.free()
	bm2.queue_free()


# ── B. Side conditions and sports ────────────────────────────────────────

func _test_side_conditions_set() -> void:
	var expect := {
		"tailwind": "The Tailwind blew from behind your team!",
		"safeguard": "your team cloaked itself in a mystical veil!",
		"mist": "your team became shrouded in mist!",
	}
	for name: String in expect:
		var bm := _make_bm()
		var bs := _make_bs(bm)
		bm.side_condition_set.emit(0, name)
		_chk("B.01 '%s' going up is announced" % name, _narrative(bs) == expect[name])
		bs.free()
		bm.queue_free()


func _test_side_conditions_expired() -> void:
	for name: String in ["tailwind", "safeguard", "mist"]:
		var bm := _make_bm()
		var bs := _make_bs(bm)
		bm.side_condition_expired.emit(0, name)
		var line := _narrative(bs)
		_chk("B.02 '%s' expiring is announced" % name, line != "")
		_chk("B.02b ...and is worded differently from its own set line" % [],
				line != BattleScreenShared._SIDE_CONDITION_SET_TEXT.get(name, "") % "your")
		bs.free()
		bm.queue_free()


# _side_label() yields "your" / "the foe's", which must read grammatically in
# the "%s team" slot these templates use.
func _test_side_label_reads_correctly_for_both_sides() -> void:
	var bm := _make_bm()
	var bs := _make_bs(bm)
	bm.side_condition_set.emit(1, "tailwind")
	_chk("B.03 the opposing side reads grammatically",
			_narrative(bs) == "The Tailwind blew from behind the foe's team!")
	bs.free()
	bm.queue_free()


func _test_field_sports() -> void:
	var expect := {
		"mud_sport": "Electricity's power was weakened!",
		"water_sport": "Fire's power was weakened!",
	}
	for name: String in expect:
		var bm := _make_bm()
		var bs := _make_bs(bm)
		bm.field_sport_set.emit(name)
		# Source phrases these as a statement about the weakened TYPE, not
		# about the user or the side — reproduced rather than "improved".
		_chk("B.04 '%s' announces the weakened type" % name,
				_narrative(bs) == expect[name])
		bs.free()
		bm.queue_free()


# ── C. Delayed effects ───────────────────────────────────────────────────

func _test_future_sight_both_ends() -> void:
	var caster := _make_mon("Seer")
	var target := _make_mon("Victim")
	var move := MoveData.new()
	move.move_name = "Future Sight"

	var bm := _make_bm()
	var bs := _make_bs(bm, caster)
	bm.future_sight_scheduled.emit(caster, target, move)
	_chk("C.01 Future Sight announces its cast",
			"foresaw an attack!" in _narrative(bs))
	bs.free()
	bm.queue_free()

	var bm2 := _make_bm()
	var bs2 := _make_bs(bm2, caster)
	bm2.future_sight_resolved.emit(caster, target, move, 40)
	var line := _narrative(bs2)
	_chk("C.02 ...and its resolution, naming the move",
			"took the Future Sight attack!" in line and "Victim" in line)
	bs2.free()
	bm2.queue_free()

	# The signal fires even at damage 0 (fizzle / immune / fainted), per its
	# own documented contract — the line must still appear.
	var bm3 := _make_bm()
	var bs3 := _make_bs(bm3, caster)
	bm3.future_sight_resolved.emit(caster, target, move, 0)
	_chk("C.03 a 0-damage resolution is still announced", _narrative(bs3) != "")
	bs3.free()
	bm3.queue_free()


# THE assertion for this sub-phase. BattleScript_EffectWish is
# `attackcanceler / trywish / attackanimation / MoveEnd` — no printstring at
# all — so source is genuinely SILENT when Wish is cast, and only announces the
# resolution. Wiring wish_scheduled by symmetry with future_sight_scheduled
# would be inventing dialogue the reference does not have.
func _test_wish_resolution_only() -> void:
	var mon := _make_mon("Wisher")

	var bm := _make_bm()
	var bs := _make_bs(bm, mon)
	bm.wish_scheduled.emit(mon)
	_chk("C.04 casting Wish stays SILENT, matching source's own script",
			_narrative(bs) == "")
	bs.free()
	bm.queue_free()

	var bm2 := _make_bm()
	var bs2 := _make_bs(bm2, mon)
	bm2.wish_resolved.emit(mon, 50)
	_chk("C.05 ...but the resolution IS announced",
			"wish came true!" in _narrative(bs2))
	bs2.free()
	bm2.queue_free()


func _test_healing_wish_and_lunar_dance() -> void:
	var mon := _make_mon("Reviver")
	var expect := {
		"healing_wish": "The healing wish came true for",
		"lunar_dance": "became cloaked in mystical moonlight!",
	}
	for kind: String in expect:
		var bm := _make_bm()
		var bs := _make_bs(bm, mon)
		bm.healing_wish_activated.emit(mon, kind, 100, true, false)
		_chk("C.06 '%s' uses its own distinct source line" % kind,
				expect[kind] in _narrative(bs))
		bs.free()
		bm.queue_free()


# ── D. Robustness ────────────────────────────────────────────────────────

# These handlers look their text up by name; an unrecognised name must produce
# nothing rather than a malformed line. Screens and hazards deliberately do NOT
# come through side_condition_set (they have their own already-wired signals),
# so a stray name here should stay silent.
func _test_unknown_names_stay_silent() -> void:
	var bm := _make_bm()
	var bs := _make_bs(bm)
	bm.side_condition_set.emit(0, "some_future_condition")
	bm.side_condition_expired.emit(0, "some_future_condition")
	bm.field_sport_set.emit("some_future_sport")
	bm.healing_wish_activated.emit(_make_mon("X"), "some_future_kind", 0, false, false)
	_chk("D.01 unrecognised names produce no malformed output", _narrative(bs) == "")
	bs.free()
	bm.queue_free()


# ── E. End to end ────────────────────────────────────────────────────────

# Proves a line reaches the log from real gameplay. Trick Room is used because
# it is a plain status move with no RNG and no target dependency.
func _test_real_battle_end_to_end() -> void:
	var atk := _make_mon("RoomMaker")
	var def := _make_mon("Foe")
	var trick_room := load("res://data/moves/move_0433.tres") as MoveData
	_chk("E.01 (precondition) Trick Room loads from real data", trick_room != null)
	if trick_room == null:
		return
	atk.add_move(trick_room)
	def.add_move(trick_room)

	var bm := _make_bm()
	var bs := _make_bs(bm, atk)
	bm.start_battle(atk, def)
	_chk("E.02 a real Trick Room use is narrated",
			"dimensions were twisted" in _narrative(bs))
	bs.free()
	bm.queue_free()
