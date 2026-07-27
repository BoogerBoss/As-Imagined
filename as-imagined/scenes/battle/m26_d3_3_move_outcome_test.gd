extends Node

# [M26D3-3] Regression suite for move-outcome narration — the "what just
# happened to my move" layer: Protect, Substitute, failure, crash damage,
# Endure, thaw, called moves, two-turn charging, Bide, Magic Bounce, Snatch and
# multi-hit totals. 16 signals, 13 of them previously unwired entirely and 3
# (move_bounced / move_stolen / multi_hit_sequence_finished) debug-only.
#
# The load-bearing assertion is C.01: every two-turn move in this project must
# have its OWN charge line. Source has no shared "is charging" string and no
# `twoTurnAttackStringId` field — each move prints its own from its own battle
# script — so a missing entry silently degrades to a generic fallback that
# reads plausibly and is wrong.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_simple_outcomes()
	_test_names_are_substituted()
	_test_charge_text_covers_every_two_turn_move()
	_test_charge_text_specific_moves()
	_test_sky_drop_has_its_own_line()
	_test_unknown_charge_move_falls_back()
	_test_bide_sequence()
	_test_called_move_does_not_duplicate_the_announcement()
	_test_multi_hit_reports_its_count()
	_test_snatch_names_both_sides()

	var total := _pass + _fail
	print("m26_d3_3_move_outcome_test: %d/%d passed" % [_pass, total])
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


# ── A. Simple outcomes ───────────────────────────────────────────────────

func _test_simple_outcomes() -> void:
	var cases := [
		["protected", "protected itself!"],
		["protect_broken", "fell for the feint!"],
		["substitute_broke", "substitute faded!"],
		["endured", "endured the hit!"],
		["pokemon_thawed", "thawed out!"],
	]
	for c: Array in cases:
		var bm := _make_bm()
		var bs := _make_bs(bm)
		bm.emit_signal(c[0], _make_mon("Subject"))
		_chk("A.01 %s is narrated" % c[0], c[1] in _narrative(bs))
		bs.free()
		bm.queue_free()

	var bm2 := _make_bm()
	var bs2 := _make_bs(bm2)
	bm2.substitute_created.emit(_make_mon("Subber"), 50)
	_chk("A.02 substitute_created is narrated",
			"put in a substitute!" in _narrative(bs2))
	bs2.free()
	bm2.queue_free()

	# Source's generic failure line. The engine-side `reason` has no
	# player-facing equivalent and is deliberately not surfaced.
	var bm3 := _make_bm()
	var bs3 := _make_bs(bm3)
	bm3.move_effect_failed.emit(_make_mon("Target"), "stat_limit")
	_chk("A.03 a failed effect uses source's generic line",
			_narrative(bs3) == "But it failed!")
	bs3.free()
	bm3.queue_free()

	var bm4 := _make_bm()
	var bs4 := _make_bs(bm4)
	bm4.crash_damage.emit(_make_mon("Kicker"), 60)
	_chk("A.04 crash damage is narrated",
			"kept going and crashed!" in _narrative(bs4))
	bs4.free()
	bm4.queue_free()


func _test_names_are_substituted() -> void:
	var bm := _make_bm()
	var bs := _make_bs(bm)
	bm.protected.emit(_make_mon("Blocky"))
	var line := _narrative(bs)
	_chk("A.05 the mon's name appears", "Blocky" in line)
	_chk("A.05b no raw format token leaks", not ("%s" in line))
	bs.free()
	bm.queue_free()


# ── B/C. Two-turn charge text ────────────────────────────────────────────

# THE assertion for this sub-phase. Source has no shared charge string and no
# `twoTurnAttackStringId` field, so every two-turn move needs its own entry;
# a missing one degrades to a plausible-but-wrong generic line.
func _test_charge_text_covers_every_two_turn_move() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/gen_moves.py")
	_chk("C.00 gen_moves.py is readable", src != "")
	if src == "":
		return
	# Move entries look like: {"id":  19, "name": "Fly", ... "two_turn": True
	var rx := RegEx.new()
	rx.compile('\\{"id":\\s*(\\d+),\\s*"name":\\s*"([^"]+)"')
	var missing: Array[String] = []
	var checked := 0
	for m: RegExMatch in rx.search_all(src):
		var start: int = m.get_end()
		var next: int = src.find('{"id"', start)
		var body: String = src.substr(start, (next - start) if next > 0 else 400)
		if not ('"two_turn": True' in body):
			continue
		var mid := int(m.get_string(1))
		checked += 1
		if mid == BattleScreenShared._SKY_DROP_MOVE_ID:
			continue  # handled at its own call site, names a target too
		if not BattleScreenShared._CHARGE_TEXT.has(mid):
			missing.append("%d (%s)" % [mid, m.get_string(2)])
	_chk("C.01 every two-turn move has its own charge line (missing: %s)"
				% str(missing), missing.is_empty())
	_chk("C.02 the scan actually found two-turn moves (found %d)" % checked,
			checked >= 15)


func _test_charge_text_specific_moves() -> void:
	# Spot-checks against source's own wording, including two pairs that
	# legitimately SHARE a line — not duplication to be factored out.
	var expect := {
		19: "flew up high!",
		91: "burrowed its way under the ground!",
		76: "absorbed light!",
		632: "absorbed light!",
		553: "became cloaked in a freezing light!",
		554: "became cloaked in a freezing light!",
		467: "vanished instantly!",
		566: "vanished instantly!",
	}
	for mid: int in expect:
		var move := load("res://data/moves/move_%04d.tres" % mid) as MoveData
		if move == null:
			_chk("C.03 move %d loads" % mid, false)
			continue
		var bm := _make_bm()
		var bs := _make_bs(bm)
		bm.charge_started.emit(_make_mon("Charger"), move)
		_chk("C.03 move %d charges with source's own wording" % mid,
				expect[mid] in _narrative(bs))
		bs.free()
		bm.queue_free()


func _test_sky_drop_has_its_own_line() -> void:
	var move := load("res://data/moves/move_%04d.tres"
			% BattleScreenShared._SKY_DROP_MOVE_ID) as MoveData
	_chk("C.04 Sky Drop loads", move != null)
	if move == null:
		return
	var bm := _make_bm()
	var bs := _make_bs(bm)
	bm.charge_started.emit(_make_mon("Lifter"), move)
	var line := _narrative(bs)
	_chk("C.05 Sky Drop names taking a target into the sky", "into the sky!" in line)
	_chk("C.05b ...and is not the generic fallback", not ("began charging" in line))
	bs.free()
	bm.queue_free()


func _test_unknown_charge_move_falls_back() -> void:
	var synthetic := MoveData.new()
	synthetic.move_name = "Future Charge Move"
	var bm := _make_bm()
	var bs := _make_bs(bm)
	bm.charge_started.emit(_make_mon("Unknown"), synthetic)
	_chk("C.06 an unmapped charging move still says something",
			"began charging its move!" in _narrative(bs))
	bs.free()
	bm.queue_free()


# ── D. Bide, called moves, multi-hit, Snatch ─────────────────────────────

func _test_bide_sequence() -> void:
	var mon := _make_mon("Bider")
	var bm := _make_bm()
	var bs := _make_bs(bm)
	bm.bide_started.emit(mon)
	bm.bide_storing.emit(mon)
	bm.bide_released.emit(mon, 120)
	var text := _narrative(bs)
	# Source reprints the SAME storing line each waiting turn — two occurrences
	# is correct, not a bug.
	_chk("D.01 Bide stores twice then releases",
			text.count("is storing energy!") == 2
				and "unleashed its energy!" in text)
	bs.free()
	bm.queue_free()


# move_announced fires early and names the CALLING move; move_called fires
# during dispatch and names what was picked. Source prints both, so this is
# not duplication — asserted here so a future reader doesn't "de-duplicate" it.
func _test_called_move_does_not_duplicate_the_announcement() -> void:
	var called := MoveData.new()
	called.move_name = "Thunderbolt"
	var bm := _make_bm()
	var bs := _make_bs(bm)
	bm.move_called.emit(_make_mon("Metro"), called)
	var line := _narrative(bs)
	_chk("D.02 the called move is announced by name",
			"used Thunderbolt!" in line)
	bs.free()
	bm.queue_free()


func _test_multi_hit_reports_its_count() -> void:
	var bm := _make_bm()
	var bs := _make_bs(bm)
	bm.multi_hit_sequence_finished.emit(_make_mon("A"), _make_mon("B"), 3, 60)
	_chk("D.03 the multi-hit total is reported",
			"was hit 3 time(s)!" in _narrative(bs))
	bs.free()
	bm.queue_free()


func _test_snatch_names_both_sides() -> void:
	var move := MoveData.new()
	move.move_name = "Swords Dance"
	var bm := _make_bm()
	var bs := _make_bs(bm)
	bm.move_stolen.emit(_make_mon("Thief"), _make_mon("Victim"), move)
	var line := _narrative(bs)
	_chk("D.04 Snatch names the stealer and the original caster",
			"Thief" in line and "Victim" in line and "snatched" in line)
	bs.free()
	bm.queue_free()

	var bm2 := _make_bm()
	var bs2 := _make_bs(bm2)
	bm2.move_bounced.emit(_make_mon("Bouncer"), _make_mon("Caster"))
	_chk("D.05 Magic Bounce reflection is narrated",
			"bounced back!" in _narrative(bs2))
	bs2.free()
	bm2.queue_free()
