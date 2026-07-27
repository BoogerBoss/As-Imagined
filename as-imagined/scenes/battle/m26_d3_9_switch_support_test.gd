extends Node

# [M26D3-9] Regression suite for switch- and support-move narration.
#
# The Step 0 finding that shaped this group: `_do_forced_switch_in` emits NO
# pokemon_switched_in/out at all (verified directly), so forced_switch,
# hit_escape_switch and hit_switch_target are the ONLY narration those switches
# ever get. They are genuine silence, not duplicates of the already-wired
# voluntary-switch text.
#
# `baton_passed` is the mirror image and must stay SILENT — it fires alongside
# switch text that IS already wired, and source has no Baton-Pass-specific
# string at all. That is C.01, the load-bearing assertion here.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_forced_switch_paths_are_narrated()
	_test_hit_escape_is_worded_as_voluntary()
	_test_baton_pass_stays_silent()
	_test_support_moves()
	_test_turn_order_reasons()
	_test_unknown_turn_order_reason_stays_silent()

	var total := _pass + _fail
	print("m26_d3_9_switch_support_test: %d/%d passed" % [_pass, total])
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


# ── A/B. Switches ────────────────────────────────────────────────────────

func _test_forced_switch_paths_are_narrated() -> void:
	for sig: String in ["forced_switch", "hit_switch_target"]:
		var bm := _make_bm()
		var bs := _make_bs(bm)
		bm.emit_signal(sig, _make_mon("Ousted"), _make_mon("Replacement"))
		var line := _narrative(bs)
		_chk("A.01 %s is narrated" % sig, "was dragged out!" in line)
		_chk("A.01b it names the mon that LEFT, not the replacement" % [],
				"Ousted" in line and not ("Replacement" in line))
		bs.free()
		bm.queue_free()


# U-turn's user leaves voluntarily, so "dragged out" would be wrong — even
# though it shares _do_forced_switch_in with Roar and Dragon Tail.
func _test_hit_escape_is_worded_as_voluntary() -> void:
	var bm := _make_bm()
	var bs := _make_bs(bm)
	bm.hit_escape_switch.emit(_make_mon("Uturner"), _make_mon("Incoming"))
	var line := _narrative(bs)
	_chk("B.01 U-turn's switch is narrated", "Uturner" in line)
	_chk("B.02 ...and is NOT worded as a forced removal",
			not ("dragged out" in line))
	bs.free()
	bm.queue_free()


# THE assertion. baton_passed fires alongside pokemon_switched_out/in — both
# already log-wired — and source has no Baton-Pass-specific string at all.
# Wiring it would put a third line on an already-narrated switch.
func _test_baton_pass_stays_silent() -> void:
	var bm := _make_bm()
	var bs := _make_bs(bm)
	bm.baton_passed.emit(_make_mon("Passer"), _make_mon("Receiver"))
	_chk("C.01 Baton Pass adds NO line of its own", _narrative(bs) == "")
	bs.free()
	bm.queue_free()

	# Asserted DIRECTLY rather than inferred from absent output: after wiring,
	# baton_passed must have no listener at all, while the switch signals it
	# rides alongside must have one. Proving it this way also avoids emitting
	# pokemon_switched_out here — that handler does more than log (it queues
	# M26B3-6's recall animation) and hangs on a bare instance.
	var bm2 := _make_bm()
	var bs2 := _make_bs(bm2)
	_chk("C.02 baton_passed is deliberately left with no listener",
			bm2.baton_passed.get_connections().is_empty())
	_chk("C.03 (non-vacuity) the switch signals it accompanies DO have one",
			not bm2.pokemon_switched_out.get_connections().is_empty()
				and not bm2.pokemon_switched_in.get_connections().is_empty())
	bs2.free()
	bm2.queue_free()


# ── D. Support moves ─────────────────────────────────────────────────────

func _test_support_moves() -> void:
	var bm := _make_bm()
	var bs := _make_bs(bm)
	bm.helping_hand_used.emit(_make_mon("Helper"), _make_mon("Ally"))
	var line := _narrative(bs)
	_chk("D.01 Helping Hand names both mons",
			"Helper" in line and "Ally" in line and "ready to help" in line)
	bs.free()
	bm.queue_free()

	var bm2 := _make_bm()
	var bs2 := _make_bs(bm2)
	bm2.follow_me_used.emit(_make_mon("Baiter"))
	_chk("D.02 Follow Me is narrated",
			"became the center of attention!" in _narrative(bs2))
	bs2.free()
	bm2.queue_free()

	var bm3 := _make_bm()
	var bs3 := _make_bs(bm3)
	bm3.pokemon_transformed.emit(_make_mon("Ditto"), _make_mon("Target"))
	_chk("D.03 Transform names what it copied",
			"transformed into" in _narrative(bs3) and "Target" in _narrative(bs3))
	bs3.free()
	bm3.queue_free()

	var bm4 := _make_bm()
	var bs4 := _make_bs(bm4)
	bm4.stat_changes_copied.emit(_make_mon("Copier"), _make_mon("Source"))
	_chk("D.04 Psych Up names both mons",
			"copied" in _narrative(bs4) and "Source" in _narrative(bs4))
	bs4.free()
	bm4.queue_free()

	var bm5 := _make_bm()
	var bs5 := _make_bs(bm5)
	bm5.pain_split_used.emit(_make_mon("A"), _make_mon("B"))
	# Source's line names neither battler — it is about the pair.
	_chk("D.05 Pain Split uses source's battler-less wording",
			_narrative(bs5) == "The battlers shared their pain!")
	bs5.free()
	bm5.queue_free()


# ── E. Turn order ────────────────────────────────────────────────────────

# One signal, two genuinely different source lines, selected by `reason`.
func _test_turn_order_reasons() -> void:
	var expect := {
		"after_you": "took the kind offer!",
		"quash": "move was postponed!",
	}
	var seen: Array[String] = []
	for reason: String in expect:
		var bm := _make_bm()
		var bs := _make_bs(bm)
		bm.turn_order_changed.emit(_make_mon("Mover"), reason)
		var line := _narrative(bs)
		_chk("E.01 '%s' uses its own line" % reason, expect[reason] in line)
		seen.append(line)
		bs.free()
		bm.queue_free()
	_chk("E.02 the two reasons are worded differently",
			seen.size() == 2 and seen[0] != seen[1])


func _test_unknown_turn_order_reason_stays_silent() -> void:
	var bm := _make_bm()
	var bs := _make_bs(bm)
	bm.turn_order_changed.emit(_make_mon("Mover"), "some_future_splice")
	_chk("E.03 an unrecognised reason produces no malformed line",
			_narrative(bs) == "")
	bs.free()
	bm.queue_free()
