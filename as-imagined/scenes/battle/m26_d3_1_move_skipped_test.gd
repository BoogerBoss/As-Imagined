extends Node

# [M26D3-1] Regression suite for `move_skipped` narration.
#
# `move_skipped(pokemon, reason)` carries SIXTEEN distinct outcomes on a single
# signal, and until this sub-phase it had NO listener of any kind — a Pokemon
# that could not move produced complete silence and the turn just passed, which
# reads as a bug rather than a mechanic. Scoped as the highest-leverage single
# dialogue fix in M26 (docs/m26_d3_recon.md §5).
#
# The reasons are NOT a hand-kept list here: A.01 re-derives them from
# BattleManager's own source and fails if any reason string exists that the
# text table does not cover. That is what stops this regressing the moment
# someone adds a 17th reason — which is exactly how the original silence would
# creep back in.

var _pass := 0
var _fail := 0

# Re-derived from battle_manager.gd in A.01; duplicated here only so the
# per-reason assertions can be written out explicitly.
const _EXPECTED_REASONS: Array[String] = [
	"recharging", "loafing", "flinched", "paralyzed", "asleep", "frozen",
	"infatuated", "confused", "disabled", "taunt", "tormented", "imprison",
	"throat_chop", "assault_vest", "cant_use_twice", "sky_drop_held",
]


func _ready() -> void:
	_test_every_real_reason_is_covered()
	_test_each_reason_produces_its_own_line()
	_test_names_are_substituted()
	_test_confusion_line_has_no_name_slot()
	_test_disclosed_generic_fallbacks()
	_test_unknown_reason_still_says_something()
	_test_debug_entry_is_tagged_rng()
	_test_real_battle_end_to_end()

	var total := _pass + _fail
	print("m26_d3_1_move_skipped_test: %d/%d passed" % [_pass, total])
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
	return bs


func _narrative_text(bs: BattleScreenShared) -> String:
	var out := ""
	for entry: Dictionary in bs._debug_entries:
		if entry["category"] == BattleScreenShared.DebugCategory.NARRATIVE:
			out += str(entry["text"]) + "\n"
	return out


# ── A. Coverage ──────────────────────────────────────────────────────────

# The guard that matters most. Re-derives every reason string BattleManager can
# actually emit — the 8 dedicated `move_skipped.emit(mon, "literal")` sites plus
# the 8 `reason = "literal"` assignments feeding the shared pre-move-check
# site — and fails if the text table misses any. Without this, adding a 17th
# reason silently reintroduces the exact silence this sub-phase removed.
func _test_every_real_reason_is_covered() -> void:
	var src := FileAccess.get_file_as_string(
			"res://scripts/battle/core/battle_manager.gd")
	_chk("A.01 battle_manager.gd is readable", src != "")
	if src == "":
		return

	var found: Dictionary = {}
	var direct := RegEx.new()
	direct.compile('move_skipped\\.emit\\([^,]+,\\s*"([a-z_]+)"')
	for m: RegExMatch in direct.search_all(src):
		found[m.get_string(1)] = true
	var assigned := RegEx.new()
	assigned.compile('reason\\s*=\\s*"([a-z_]+)"')
	for m: RegExMatch in assigned.search_all(src):
		found[m.get_string(1)] = true

	var missing: Array[String] = []
	for reason: String in found:
		if not BattleScreenShared._MOVE_SKIPPED_TEXT.has(reason):
			missing.append(reason)
	_chk("A.02 every reason BattleManager emits has narration text (missing: %s)"
				% str(missing), missing.is_empty())
	_chk("A.03 all 16 known reasons were re-derived from source (found %d)"
				% found.size(), found.size() == _EXPECTED_REASONS.size())
	for r: String in _EXPECTED_REASONS:
		_chk("A.04 reason '%s' is still emitted by BattleManager" % r, found.has(r))


# ── B. Per-reason text ───────────────────────────────────────────────────

func _test_each_reason_produces_its_own_line() -> void:
	var seen: Dictionary = {}
	for reason: String in _EXPECTED_REASONS:
		var bm := _make_bm()
		var bs := _make_bs(bm)
		bs._wire_log_signals()
		bm.move_skipped.emit(_make_mon("Skipper"), reason)
		var line := _narrative_text(bs).strip_edges()
		_chk("B.01 reason '%s' produces a non-empty line" % reason, line != "")
		seen[reason] = line
		bs.free()
		bm.queue_free()
	# The three disclosed fallbacks deliberately share one line; every other
	# reason must be distinguishable from every other.
	var distinct: Dictionary = {}
	for r: String in seen:
		distinct[seen[r]] = true
	_chk("B.02 the 16 reasons yield 14 distinct lines (3 share the disclosed fallback)",
			distinct.size() == 14)


func _test_names_are_substituted() -> void:
	var bm := _make_bm()
	var bs := _make_bs(bm)
	bs._wire_log_signals()
	bm.move_skipped.emit(_make_mon("Snorer"), "asleep")
	var line := _narrative_text(bs).strip_edges()
	_chk("B.03 the Pokemon's name is substituted in", "Snorer" in line)
	_chk("B.03b no raw format token leaks through", not ("%s" in line))
	_chk("B.04 the line matches source's own wording", line.ends_with("is fast asleep."))
	bs.free()
	bm.queue_free()


# Source's confusion line is "It hurt itself in its confusion!" — no name slot
# at all, unlike the other fifteen. A naive `template % name` would have thrown.
func _test_confusion_line_has_no_name_slot() -> void:
	var bm := _make_bm()
	var bs := _make_bs(bm)
	bs._wire_log_signals()
	bm.move_skipped.emit(_make_mon("Dizzy"), "confused")
	var line := _narrative_text(bs).strip_edges()
	_chk("B.05 the confusion line renders without a name",
			line == "It hurt itself in its confusion!")
	bs.free()
	bm.queue_free()


# Assault Vest / Blood Moon's twice-in-a-row / Sky-Drop-held have no dedicated
# STRINGID: source prevents those at SELECTION time, which this project has no
# equivalent for, so they fail at EXECUTION and fall back to source's own
# generic failure line. Asserted so the substitution stays a deliberate,
# visible decision rather than drifting into invented text.
func _test_disclosed_generic_fallbacks() -> void:
	for reason: String in ["assault_vest", "cant_use_twice", "sky_drop_held"]:
		_chk("B.06 '%s' uses source's generic failure line" % reason,
				BattleScreenShared._MOVE_SKIPPED_TEXT.get(reason) == "But it failed!")


func _test_unknown_reason_still_says_something() -> void:
	var bm := _make_bm()
	var bs := _make_bs(bm)
	bs._wire_log_signals()
	bm.move_skipped.emit(_make_mon("Mystery"), "some_future_reason")
	var line := _narrative_text(bs).strip_edges()
	_chk("B.07 an unrecognised reason degrades to a real line, not silence",
			line != "" and "Mystery" in line)
	bs.free()
	bm.queue_free()


# ── C. Debug panel ───────────────────────────────────────────────────────

func _test_debug_entry_is_tagged_rng() -> void:
	var bm := _make_bm()
	var bs := _make_bs(bm)
	bs._wire_debug_signals()
	bm.move_skipped.emit(_make_mon("Para"), "paralyzed")
	# NOTE: _wire_debug_signals() seeds its OWN RNG-tagged entry up front — the
	# standing "raw roll values aren't exposed" disclosure from M26A2. So the
	# count here is 2, not 1, and the one under test is the LAST. Asserting a
	# bare count would have been wrong; this cost a real debug cycle to find.
	var rng: Array[String] = []
	for entry: Dictionary in bs._debug_entries:
		if entry["category"] == BattleScreenShared.DebugCategory.RNG:
			rng.append(str(entry["text"]))
	_chk("C.01 a skipped move adds an RNG-category entry on top of the standing disclosure",
			rng.size() == 2)
	_chk("C.01b it names the mon and the raw reason",
			rng.size() >= 1 and "Para" in rng[-1] and "paralyzed" in rng[-1])
	bs.free()
	bm.queue_free()


# ── D. End to end ────────────────────────────────────────────────────────

# Proves the line reaches the log from real gameplay, not just from a
# hand-emitted signal.
#
# Uses RECHARGING rather than paralysis deliberately: this project has no
# forcing seam for the 25% full-paralysis roll (a real flake `[M17n-10]` already
# hit and worked around), whereas `must_recharge` is a plain bool and so is
# fully deterministic with no RNG involved at all.
func _test_real_battle_end_to_end() -> void:
	var atk := _make_mon("RealRecharge")
	var def := _make_mon("RealFoe")
	var tackle := MoveData.new()
	tackle.move_name = "Tackle"
	tackle.type = TypeChart.TYPE_NORMAL
	tackle.category = 0
	tackle.power = 40
	tackle.accuracy = 0
	tackle.pp = 35
	atk.add_move(tackle)
	def.add_move(tackle)
	atk.must_recharge = true

	var bm := _make_bm()
	var bs := _make_bs(bm, atk)
	bs._wire_log_signals()
	bm.start_battle(atk, def)

	_chk("D.01 a real recharge turn narrates it, through the live signal",
			"must recharge!" in _narrative_text(bs))
	bs.free()
	bm.queue_free()
