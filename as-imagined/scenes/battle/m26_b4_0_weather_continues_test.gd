extends Node

# [M26B4-0] Regression suite for the per-turn "weather is still active"
# signal and message.
#
# Source: EndOrContinueWeather (battle_util.c L244-270), driven every turn from
# HandleEndTurnWeather (battle_end_turn.c L94-97). Its ELSE branch fires
# BattleScript_WeatherContinues (battle_scripts_1.s L3156), which prints from
# gWeatherTurnStringIds AND (M26B4-3, not built yet) replays the weather
# animation. This is source's ENTIRE mechanism for communicating that weather
# is still active — there is no persistent weather renderer anywhere in the
# reference. Full recon: docs/m26_b4_recon.md.
#
# Before this sub-phase this project had no per-turn weather signal or message
# of ANY kind: weather_set / weather_expired / weather_damage existed, and a
# turn where weather merely persisted emitted nothing at all.
#
# The single most important assertion here is C.02 — that weather_continues
# does NOT fire on the turn weather expires. That is the discriminator between
# a correct implementation and one that simply emits on every tick.

var _pass := 0
var _fail := 0


func _ready() -> void:
	# A — signal shape
	_test_signal_exists_with_expected_shape()
	# B — text table
	_test_continues_text_covers_every_weather_this_project_has()
	_test_continues_text_is_distinct_from_start_and_end_text()
	# C — emit behaviour
	_test_fires_on_a_persisting_turn()
	_test_does_not_fire_on_the_expiry_turn()
	_test_does_not_fire_when_no_weather_is_active()
	_test_full_five_turn_sequence_emits_four_continues_then_one_expiry()
	_test_permanent_weather_continues_and_never_expires()
	# D — ordering against source's own handler table
	_test_continues_fires_before_weather_chip_damage()
	# E — UI wiring
	_test_log_line_for_every_weather_type()
	_test_log_falls_back_for_an_unknown_weather_type()
	_test_debug_entry_lands_in_durations_category()
	# F — end to end
	_test_real_battle_end_to_end()

	var total := _pass + _fail
	print("m26_b4_0_weather_continues_test: %d/%d passed" % [_pass, total])
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

func _make_mon(mon_name: String, hp: int = 300) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	# Normal-type: immune to neither sandstorm nor hail chip, so the chip-damage
	# ordering test in section D has something real to observe.
	sp.types = [TypeChart.TYPE_NORMAL]
	sp.base_hp = hp
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


# Minimal state for a direct _phase_end_of_turn() call, matching the
# established convention (d4_bundle7_test.gd B.05, d4_bundle6_test.gd,
# delayed_effect_test.gd). Deliberately does NOT touch _side_conditions —
# [D4 Bundle 6] hit a real crash overwriting its default with empty dicts.
func _make_ticking_bm(weather_type: int, duration: int) -> BattleManager:
	var a := _make_mon("TickA")
	var b := _make_mon("TickB")
	var bm := _make_bm()
	bm._combatants = [a, b]
	bm._active_per_side = 1
	bm._turn_order = [a, b]
	bm.weather = weather_type
	bm.weather_duration = duration
	return bm


# `player` is only needed by the section F end-to-end test, where a REAL battle
# runs and unrelated log handlers (move_announced, faint) call _mon_label(),
# which dereferences both parties. Sections B/E emit weather_continues directly
# and never reach those handlers, so they can pass null.
#
# The empty-BattleParty shape below is m25c_message_log_test.gd's own
# hard-won convention, reproduced rather than re-derived: BattleParty.new()'s
# default active_indices is [0] (NOT empty) while members defaults to [], so
# num_active() returns 1 and _field_slot_for indexes into an empty array.
# Clearing active_indices explicitly keeps num_active() at a genuine 0.
func _make_bs(player: BattlePokemon = null) -> BattleScreenShared:
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
	return bs


# Mirrors m25c_message_log_test.gd's own helper: the merged M26b log sink is
# the category-tagged _debug_entries history, not a Label.
func _narrative_text(bs: BattleScreenShared) -> String:
	var out := ""
	for entry: Dictionary in bs._debug_entries:
		if entry["category"] == BattleScreenShared.DebugCategory.NARRATIVE:
			out += str(entry["text"]) + "\n"
	return out


# ── A. Signal shape ──────────────────────────────────────────────────────

func _test_signal_exists_with_expected_shape() -> void:
	var bm := _make_bm()
	var found := {}
	for sig: Dictionary in bm.get_signal_list():
		if sig["name"] == "weather_continues":
			found = sig
	_chk("A.01 BattleManager declares weather_continues", not found.is_empty())
	if not found.is_empty():
		var args: Array = found["args"]
		_chk("A.02 weather_continues takes exactly one arg", args.size() == 1)
		_chk("A.03 that arg is the weather type",
				args.size() == 1 and args[0]["name"] == "weather_type")
	bm.queue_free()


# ── B. Text table ────────────────────────────────────────────────────────

func _test_continues_text_covers_every_weather_this_project_has() -> void:
	var t: Dictionary = BattleScreenShared._WEATHER_CONTINUES_TEXT
	# Exactly the five real weathers this project implements — source's own
	# DOWNPOUR/SNOW/FOG entries have no equivalent here (no downpour, no fog,
	# and [D2 batch] permanently collapsed Snow into WEATHER_HAIL).
	_chk("B.01 rain line matches source's STRINGID_RAINCONTINUES",
			t.get(DamageCalculator.WEATHER_RAIN) == "Rain continues to fall.")
	_chk("B.02 sun line matches source's STRINGID_SUNLIGHTSTRONG",
			t.get(DamageCalculator.WEATHER_SUN) == "The sunlight is strong.")
	_chk("B.03 sandstorm line matches source's STRINGID_SANDSTORMRAGES",
			t.get(DamageCalculator.WEATHER_SANDSTORM) == "The sandstorm is raging.")
	_chk("B.04 hail line matches source's STRINGID_HAILCONTINUES",
			t.get(DamageCalculator.WEATHER_HAIL) == "The hail is crashing down.")
	_chk("B.05 strong winds line matches source's STRINGID_MYSTERIOUSAIRCURRENTBLOWSON",
			t.get(DamageCalculator.WEATHER_STRONG_WINDS)
				== "The mysterious strong winds blow on regardless!")
	_chk("B.06 table covers exactly the 5 weathers this project implements",
			t.size() == 5)


# Guards against a copy-paste of the start/end tables — these are three
# genuinely different message sets in source, not one reused string.
func _test_continues_text_is_distinct_from_start_and_end_text() -> void:
	var cont: Dictionary = BattleScreenShared._WEATHER_CONTINUES_TEXT
	var start: Dictionary = BattleScreenShared._WEATHER_START_TEXT
	var ends: Dictionary = BattleScreenShared._WEATHER_END_TEXT
	var all_distinct := true
	for k: int in cont:
		if cont[k] == start.get(k) or cont[k] == ends.get(k):
			all_distinct = false
	_chk("B.07 every continues line differs from its own start and end line",
			all_distinct)


# ── C. Emit behaviour ────────────────────────────────────────────────────

func _test_fires_on_a_persisting_turn() -> void:
	var bm := _make_ticking_bm(DamageCalculator.WEATHER_RAIN, 5)
	var got := []
	bm.weather_continues.connect(func(w: int): got.append(w))
	bm._phase_end_of_turn()
	_chk("C.01 weather_continues fires once on a persisting turn", got.size() == 1)
	_chk("C.01b it carries the active weather type",
			got.size() == 1 and got[0] == DamageCalculator.WEATHER_RAIN)
	_chk("C.01c the duration still decremented", bm.weather_duration == 4)
	_chk("C.01d weather is still active", bm.weather == DamageCalculator.WEATHER_RAIN)
	bm.queue_free()


# THE discriminator for this sub-phase. Source's condition is
# `weatherDuration > 0 && --weatherDuration == 0`, an if/ELSE — the turn weather
# runs out takes the "faded" branch and must NOT also announce that it continues.
func _test_does_not_fire_on_the_expiry_turn() -> void:
	var bm := _make_ticking_bm(DamageCalculator.WEATHER_SUN, 1)
	var continued := []
	var expired := []
	bm.weather_continues.connect(func(w: int): continued.append(w))
	bm.weather_expired.connect(func(w: int): expired.append(w))
	bm._phase_end_of_turn()
	_chk("C.02 weather_continues does NOT fire on the expiry turn",
			continued.is_empty())
	_chk("C.02b weather_expired fires instead",
			expired.size() == 1 and expired[0] == DamageCalculator.WEATHER_SUN)
	_chk("C.02c weather really cleared", bm.weather == DamageCalculator.WEATHER_NONE)
	bm.queue_free()


func _test_does_not_fire_when_no_weather_is_active() -> void:
	var bm := _make_ticking_bm(DamageCalculator.WEATHER_NONE, 0)
	var got := []
	bm.weather_continues.connect(func(w: int): got.append(w))
	bm._phase_end_of_turn()
	_chk("C.03 no weather -> no continues signal", got.is_empty())
	bm.queue_free()


# The whole lifecycle in one pass: a 5-turn weather announces itself as
# continuing on turns 1-4 and fades on turn 5 — never both on one turn, and
# never silent on a turn where it is still up.
func _test_full_five_turn_sequence_emits_four_continues_then_one_expiry() -> void:
	var bm := _make_ticking_bm(DamageCalculator.WEATHER_SANDSTORM, 5)
	var timeline := []
	bm.weather_continues.connect(func(_w: int): timeline.append("continues"))
	bm.weather_expired.connect(func(_w: int): timeline.append("expired"))
	for _i in range(5):
		bm._phase_end_of_turn()
	_chk("C.04 five ticks produce exactly 5 events", timeline.size() == 5)
	_chk("C.04b the first four are 'continues'",
			timeline.size() == 5
				and timeline.slice(0, 4) == ["continues", "continues", "continues", "continues"])
	_chk("C.04c the fifth is 'expired'",
			timeline.size() == 5 and timeline[4] == "expired")
	bm.queue_free()


# Source's short-circuit (`weatherDuration > 0 && ...`) sends permanent
# (duration-0) weather to the continues branch without decrementing. That case
# is currently UNREACHABLE in production here — weather_duration is assigned at
# exactly one site and is never 0 for a real weather, because primal weather is
# not modelled as permanent ([D2 batch]'s own flagged gap). Asserted anyway so
# that whenever primal permanence IS built, this behaviour is already correct
# and pinned rather than rediscovered.
func _test_permanent_weather_continues_and_never_expires() -> void:
	var bm := _make_ticking_bm(DamageCalculator.WEATHER_RAIN, 0)
	var continued := []
	var expired := []
	bm.weather_continues.connect(func(_w: int): continued.append("c"))
	bm.weather_expired.connect(func(_w: int): expired.append("e"))
	bm._phase_end_of_turn()
	bm._phase_end_of_turn()
	_chk("C.05 permanent weather announces itself every turn", continued.size() == 2)
	_chk("C.05b permanent weather never expires", expired.is_empty())
	_chk("C.05c duration stays pinned at 0", bm.weather_duration == 0)
	_chk("C.05d weather stays active", bm.weather == DamageCalculator.WEATHER_RAIN)
	bm.queue_free()


# ── D. Ordering ──────────────────────────────────────────────────────────

# Source's end-turn handler table runs HandleEndTurnWeather (which is what
# announces the continue) strictly BEFORE HandleEndTurnWeatherDamage. Asserted
# as a real ordered timeline rather than presence alone — per M26G2, this suite
# class is structurally blind to sequencing unless order is checked explicitly.
func _test_continues_fires_before_weather_chip_damage() -> void:
	var bm := _make_ticking_bm(DamageCalculator.WEATHER_SANDSTORM, 5)
	var timeline := []
	bm.weather_continues.connect(func(_w: int): timeline.append("continues"))
	bm.weather_damage.connect(func(_m: BattlePokemon, _a: int): timeline.append("damage"))
	bm._phase_end_of_turn()
	_chk("D.01 sandstorm chip damage actually happened (test is not vacuous)",
			timeline.has("damage"))
	_chk("D.02 the continues announcement precedes the chip damage",
			timeline.has("continues") and timeline.has("damage")
				and timeline.find("continues") < timeline.find("damage"))
	bm.queue_free()


# ── E. UI wiring ─────────────────────────────────────────────────────────

func _test_log_line_for_every_weather_type() -> void:
	for weather_type: int in BattleScreenShared._WEATHER_CONTINUES_TEXT:
		var bm := _make_bm()
		var bs := _make_bs()
		bs._bm = bm
		bs._wire_log_signals()
		bm.weather_continues.emit(weather_type)
		var expected: String = BattleScreenShared._WEATHER_CONTINUES_TEXT[weather_type]
		_chk("E.01 weather %d logs its own continues line" % weather_type,
				_narrative_text(bs) == expected + "\n")
		bs.free()
		bm.queue_free()


func _test_log_falls_back_for_an_unknown_weather_type() -> void:
	var bm := _make_bm()
	var bs := _make_bs()
	bs._bm = bm
	bs._wire_log_signals()
	bm.weather_continues.emit(9999)
	_chk("E.02 an unrecognised weather falls back rather than logging nothing",
			_narrative_text(bs) == "The weather continues.\n")
	bs.free()
	bm.queue_free()


func _test_debug_entry_lands_in_durations_category() -> void:
	var bm := _make_bm()
	bm.weather = DamageCalculator.WEATHER_HAIL
	bm.weather_duration = 3
	var bs := _make_bs()
	bs._bm = bm
	bs._wire_debug_signals()
	bm.weather_continues.emit(DamageCalculator.WEATHER_HAIL)
	var durations := []
	for entry: Dictionary in bs._debug_entries:
		if entry["category"] == BattleScreenShared.DebugCategory.DURATIONS:
			durations.append(str(entry["text"]))
	_chk("E.03 a DURATIONS debug entry is recorded", durations.size() == 1)
	_chk("E.03b it reports the remaining turn count",
			durations.size() == 1 and "3" in durations[0])
	bs.free()
	bm.queue_free()


# ── F. End to end ────────────────────────────────────────────────────────

# Proves the signal fires from genuine gameplay through the real end-of-turn
# phase — not just that a hand-driven _phase_end_of_turn() call works.
func _test_real_battle_end_to_end() -> void:
	var atk := _make_mon("RealA", 400)
	var def := _make_mon("RealB", 400)
	var rain := MoveData.new()
	rain.move_name = "Rain Dance"
	rain.type = TypeChart.TYPE_WATER
	rain.category = 2  # status
	rain.power = 0
	rain.accuracy = 0
	rain.pp = 10
	rain.weather_type = DamageCalculator.WEATHER_RAIN
	atk.add_move(rain)
	def.add_move(rain)

	var bm := _make_bm()
	var bs := _make_bs(atk)
	bs._bm = bm
	bs._wire_log_signals()
	var continued := []
	bm.weather_continues.connect(func(w: int): continued.append(w))
	bm.start_battle(atk, def)

	_chk("F.01 weather_continues fires during a real battle", continued.size() > 0)
	_chk("F.01b it reports rain",
			continued.size() > 0 and continued[0] == DamageCalculator.WEATHER_RAIN)
	_chk("F.02 the real continues line reached the battle log",
			"Rain continues to fall." in _narrative_text(bs))
	bs.free()
	bm.queue_free()
