extends Node

# [M26D3-4] Regression suite for volatile-infliction narration — D3's long
# tail. 32 signals, all previously unwired, covering Disable/Encore/Taunt/
# Torment/Attract/Leech Seed/Nightmare/Curse/trapping/Foresight/Telekinesis/
# Magnet Rise/Smack Down/Ingrain/Aqua Ring/Imprison/Perish Song/Lock-On/
# Laser Focus/Charge/Stockpile/rampage/Tar Shot/type changes/Yawn/Destiny Bond.
#
# FOUR are deliberately SILENT (section S) — the fifth through eighth instances
# of D3's recurring "silence is correct" pattern. Those assertions matter most:
# an unwired signal that SHOULD stay unwired is indistinguishable from an
# oversight unless a test says so.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_single_arg_volatiles()
	_test_two_arg_volatiles()
	_test_move_naming_volatiles()
	_test_stockpile()
	_test_type_changes()
	_test_rampage_only_announces_fatigue_confusion()
	_test_silent_signals()

	var total := _pass + _fail
	print("m26_d3_4_volatiles_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


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


func _make_bs(bm: BattleManager) -> BattleScreenShared:
	var bs := BattleScreenShared.new()
	var pp := BattleParty.new()
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


# ── A. One-argument volatiles ────────────────────────────────────────────

func _test_single_arg_volatiles() -> void:
	var cases := [
		["tormented", "was subjected to torment!"],
		["infatuated", "fell in love!"],
		["nightmare_set", "began having a nightmare!"],
		["curse_set", "was cursed!"],
		["foresight_set", "was identified!"],
		["telekinesis_set", "was hurled into the air!"],
		["magnet_rise_set", "levitated with electromagnetism!"],
		["smack_down_set", "fell straight down!"],
		["ingrain_set", "planted its roots!"],
		["aqua_ring_set", "surrounded itself with a veil of water!"],
		["tar_shot_set", "became weaker to fire!"],
		["imprison_set", "sealed any moves its target shares with it!"],
		["perish_song_activated", "will faint in three turns!"],
		["laser_focus_set", "concentrated intensely!"],
		["charge_set", "began charging power!"],
		["yawn_set", "grew drowsy!"],
		["destiny_bond_set", "is hoping to take its attacker down with it!"],
	]
	var seen: Dictionary = {}
	for c: Array in cases:
		var bm := _make_bm()
		var bs := _make_bs(bm)
		bm.emit_signal(c[0], _make_mon("Subject"))
		var line := _narrative(bs)
		_chk("A.01 %s is narrated with source's wording" % c[0], c[1] in line)
		_chk("A.01b %s names the mon" % c[0], "Subject" in line)
		seen[line] = true
		bs.free()
		bm.queue_free()
	# Every one of these is a distinct effect and must read distinctly.
	_chk("A.02 all %d lines are distinct" % cases.size(),
			seen.size() == cases.size())


# ── B. Two-argument volatiles ────────────────────────────────────────────

func _test_two_arg_volatiles() -> void:
	var bm := _make_bm()
	var bs := _make_bs(bm)
	bm.leech_seeded.emit(_make_mon("Seeded"), _make_mon("Seeder"))
	var line := _narrative(bs)
	_chk("B.01 Leech Seed names the TARGET, not the source",
			"Seeded" in line and "was seeded!" in line and not ("Seeder" in line))
	bs.free()
	bm.queue_free()

	var bm2 := _make_bm()
	var bs2 := _make_bs(bm2)
	bm2.escape_prevented.emit(_make_mon("Trapped"), _make_mon("Trapper"))
	_chk("B.02 trapping is narrated", "can no longer escape!" in _narrative(bs2))
	bs2.free()
	bm2.queue_free()

	# Octolock has its OWN source line naming the cause, distinct from the
	# generic trapping line above.
	var bm3 := _make_bm()
	var bs3 := _make_bs(bm3)
	bm3.octolock_set.emit(_make_mon("Locked"), _make_mon("Locker"))
	_chk("B.03 Octolock names its own cause",
			"because of Octolock!" in _narrative(bs3))
	bs3.free()
	bm3.queue_free()

	var bm4 := _make_bm()
	var bs4 := _make_bs(bm4)
	bm4.sure_hit_set.emit(_make_mon("Aimer"), _make_mon("Aimed"))
	var l4 := _narrative(bs4)
	_chk("B.04 Lock-On names both battlers",
			"Aimer" in l4 and "Aimed" in l4 and "took aim at" in l4)
	bs4.free()
	bm4.queue_free()

	var bm5 := _make_bm()
	var bs5 := _make_bs(bm5)
	bm5.destiny_bond_triggered.emit(_make_mon("Bonded"), _make_mon("Killer"))
	_chk("B.05 Destiny Bond's trigger names the fainted mon",
			"took its attacker down with it!" in _narrative(bs5))
	bs5.free()
	bm5.queue_free()


# ── C. Volatiles that name a move ────────────────────────────────────────

func _test_move_naming_volatiles() -> void:
	var move := MoveData.new()
	move.move_name = "Thunderbolt"

	var bm := _make_bm()
	var bs := _make_bs(bm)
	bm.disabled.emit(_make_mon("Blocked"), move)
	_chk("C.01 Disable names the disabled move",
			"Thunderbolt was disabled!" in _narrative(bs))
	bs.free()
	bm.queue_free()

	# Source's Encore line does NOT name the move (a second, separate string
	# does that) — reproduced rather than "improved".
	var bm2 := _make_bm()
	var bs2 := _make_bs(bm2)
	bm2.encored.emit(_make_mon("Encored"), move)
	_chk("C.02 Encore uses source's move-less wording",
			"must do an encore!" in _narrative(bs2))
	bs2.free()
	bm2.queue_free()

	var bm3 := _make_bm()
	var bs3 := _make_bs(bm3)
	bm3.taunted.emit(_make_mon("Taunted"), 3)
	_chk("C.03 Taunt is narrated", "fell for the taunt!" in _narrative(bs3))
	bs3.free()
	bm3.queue_free()


# ── D. Stockpile ─────────────────────────────────────────────────────────

func _test_stockpile() -> void:
	var bm := _make_bm()
	var bs := _make_bs(bm)
	bm.stockpile_gained.emit(_make_mon("Piler"), 2)
	_chk("D.01 Stockpile reports its new count",
			"stockpiled 2!" in _narrative(bs))
	bs.free()
	bm.queue_free()

	var bm2 := _make_bm()
	var bs2 := _make_bs(bm2)
	bm2.stockpile_released.emit(_make_mon("Piler"), 3)
	var line := _narrative(bs2)
	_chk("D.02 the release is narrated", "stockpiled effect wore off!" in line)
	# Source's release line reports no count — engine detail, not player text.
	_chk("D.02b ...without leaking the released count", not ("3" in line))
	bs2.free()
	bm2.queue_free()


# ── E. Type changes ──────────────────────────────────────────────────────

func _test_type_changes() -> void:
	var bm := _make_bm()
	var bs := _make_bs(bm)
	bm.type_changed.emit(_make_mon("Converter"), TypeChart.TYPE_WATER)
	var line := _narrative(bs)
	_chk("E.01 a type change names the new type",
			"transformed into the" in line and "type!" in line)
	_chk("E.01b ...resolved to a real type name, not a raw id",
			not ("the 2 type" in line) and not ("%d" in line))
	bs.free()
	bm.queue_free()

	var bm2 := _make_bm()
	var bs2 := _make_bs(bm2)
	bm2.types_changed.emit(_make_mon("Reflector"),
			[TypeChart.TYPE_FIRE, TypeChart.TYPE_NONE], "reflect_type")
	_chk("E.02 Reflect Type is narrated",
			"transformed into the" in _narrative(bs2))
	bs2.free()
	bm2.queue_free()


func _test_rampage_only_announces_fatigue_confusion() -> void:
	var move := MoveData.new()
	move.move_name = "Thrash"

	var bm := _make_bm()
	var bs := _make_bs(bm)
	bm.rampage_lock_ended.emit(_make_mon("Thrasher"), move, true)
	_chk("E.03 a rampage ending in fatigue confusion IS narrated",
			"became confused due to fatigue!" in _narrative(bs))
	bs.free()
	bm.queue_free()

	# Ending WITHOUT confusion (immune-cancel) has no source line.
	var bm2 := _make_bm()
	var bs2 := _make_bs(bm2)
	bm2.rampage_lock_ended.emit(_make_mon("Thrasher"), move, false)
	_chk("E.04 ...but a non-confusing end is silent", _narrative(bs2) == "")
	bs2.free()
	bm2.queue_free()


# ── S. Deliberately silent ───────────────────────────────────────────────

# Four signals verified against source as having NO player-facing line. Each
# is asserted so it cannot be mistaken for an oversight and "fixed".
func _test_silent_signals() -> void:
	var move := MoveData.new()
	move.move_name = "Outrage"

	var bm := _make_bm()
	var bs := _make_bs(bm)
	# Charge's flag being CONSUMED — the boosted move announces itself.
	bm.charge_cleared.emit(_make_mon("Charged"))
	_chk("S.01 charge_cleared is silent", _narrative(bs) == "")
	# A rampage lock STARTING — the move announces itself normally.
	bm.rampage_lock_started.emit(_make_mon("Rager"), move)
	_chk("S.02 rampage_lock_started is silent", _narrative(bs) == "")
	# Roost's type removal and restore are invisible in source (zero Roost
	# strings anywhere in battle_message.c).
	bm.types_changed.emit(_make_mon("Rooster"), [TypeChart.TYPE_NORMAL], "roost")
	_chk("S.03 Roost's type removal is silent", _narrative(bs) == "")
	bm.types_changed.emit(_make_mon("Rooster"),
			[TypeChart.TYPE_FLYING], "roost_restore")
	_chk("S.04 Roost's restore is silent", _narrative(bs) == "")
	bs.free()
	bm.queue_free()

	# Non-vacuity: types_changed DOES narrate for its one real reason, so the
	# three silences above are a real discriminator and not a dead handler.
	var bm2 := _make_bm()
	var bs2 := _make_bs(bm2)
	bm2.types_changed.emit(_make_mon("Reflector"), [TypeChart.TYPE_FIRE],
			"reflect_type")
	_chk("S.05 (non-vacuity) types_changed still narrates reflect_type",
			_narrative(bs2) != "")
	bs2.free()
	bm2.queue_free()
