extends Node

# [M25d] Regression suite for battle UI polish: the name/level display over
# the HP bar (singles + doubles + switch-in), and the combat-debug overlay
# (content formatting, default-hidden state, the F3 toggle, and one genuine
# end-to-end proof the new move_damage_breakdown signal actually fires from
# real gameplay).
#
# [Deliberately NOT tested here] _refresh_ui()/_refresh_doubles_side()'s own
# full live rendering — matches every prior M25 suite's established bare-
# instance convention (see m25b_menu_test.gd's own top doc comment); the
# real end-to-end proof is this session's own real screenshot verification
# (name/level correctness in both formats, a real switch-in updating the
# label, and the debug overlay's own content cross-checked pixel-for-pixel
# against the log's own numbers for the same hit).

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_name_level_text_format()
	_test_gender_glyph_variants()
	_test_debug_overlay_default_hidden()
	_test_debug_overlay_toggle_via_f3()
	_test_debug_overlay_ignores_other_keys()
	_test_format_debug_breakdown_full_content()
	_test_format_debug_breakdown_self_targeting_still_names_both()
	_test_format_debug_breakdown_missing_keys_fixed_damage_move()
	_test_damage_calculator_returns_new_breakdown_keys()
	_test_damage_calculator_stab_multiplier_neutral_for_off_type_move()
	_test_real_battle_end_to_end_debug_signal_wiring()

	var total := _pass + _fail
	print("m25d_ui_polish_test: %d/%d passed" % [_pass, total])
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

func _make_typed_mon(mon_name: String, type_id: int, lvl: int, hp: int = 150) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types = [type_id]
	sp.base_hp = hp
	sp.base_attack = 90
	sp.base_defense = 70
	sp.base_sp_attack = 90
	sp.base_sp_defense = 70
	sp.base_speed = 70
	var mon := BattlePokemon.from_species(sp, lvl, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])
	# [M26c-1 follow-up] from_species() always rolls a real gender from
	# PokemonSpecies.gender_ratio's own class default (127, ~50/50) --
	# forced deterministic here so every existing assertion in this file
	# (none of which cares about gender) stays stable across runs, now that
	# _name_text() renders a gender glyph. Tests that specifically exercise
	# the glyph override mon.gender directly afterward.
	mon.gender = BattlePokemon.GENDER_MALE
	return mon


func _make_move(move_name: String, type_id: int, power: int, accuracy: int = 0) -> MoveData:
	var m := MoveData.new()
	m.move_name = move_name
	m.type = type_id
	m.category = 1
	m.power = power
	m.accuracy = accuracy
	m.pp = 10
	return m


func _singles_party(mons: Array) -> BattleParty:
	var p := BattleParty.new()
	var typed: Array[BattlePokemon] = []
	for m: BattlePokemon in mons:
		typed.append(m)
	p.members = typed
	var idx: Array[int] = [0]
	p.active_indices = idx
	return p


# ── 1. Name/level text format ────────────────────────────────────────────
# [M26c-1 follow-up, updated M26c battle-UI polish] _name_level_text was
# split into _name_text (species name ALONE, per the follow-up request that
# the gender glyph render as its own separate element rather than being
# baked into the name string) and _level_text ("Lv" immediately followed by
# the number, no space). The glyph itself is still produced by
# _gender_glyph() and placed via the new _position_gender_label() helper —
# see the dedicated section below for glyph-content coverage.

func _test_name_level_text_format() -> void:
	var mon := _make_typed_mon("Charizard", TypeChart.TYPE_FIRE, 50)
	var bs := BattleScreen.new()
	_chk("name format is just the species name — no gender glyph baked in",
			bs._name_text(mon) == "Charizard")
	_chk("level format is 'LvN' — 'Lv' immediately followed by the number, no space",
			bs._level_text(mon) == "Lv50")

	var low_level := _make_typed_mon("Ratata", TypeChart.TYPE_NORMAL, 3)
	_chk("level format holds for a single-digit level too",
			bs._level_text(low_level) == "Lv3")


func _test_gender_glyph_variants() -> void:
	var bs := BattleScreen.new()
	var male_mon := _make_typed_mon("Nidoking", TypeChart.TYPE_POISON, 50)
	male_mon.gender = BattlePokemon.GENDER_MALE
	_chk("male gender's own glyph is ♂", bs._gender_glyph(male_mon.gender) == "♂")

	var female_mon := _make_typed_mon("Nidoqueen", TypeChart.TYPE_POISON, 50)
	female_mon.gender = BattlePokemon.GENDER_FEMALE
	_chk("female gender's own glyph is ♀", bs._gender_glyph(female_mon.gender) == "♀")

	var genderless_mon := _make_typed_mon("Magnemite", TypeChart.TYPE_ELECTRIC, 50)
	genderless_mon.gender = BattlePokemon.GENDER_GENDERLESS
	_chk("genderless has no glyph at all", bs._gender_glyph(genderless_mon.gender) == "")

	# [M26c battle-UI polish] _position_gender_label() places the separate
	# GenderLabel node's own text/offsets based on the name label's real
	# rendered width -- confirmed here directly on bare (unattached) Label
	# nodes given a real loaded font, without needing a live scene tree.
	var name_label := Label.new()
	name_label.text = bs._name_text(male_mon)
	name_label.offset_left = 100.0
	name_label.offset_top = 5.0
	name_label.offset_bottom = 45.0
	var font := FontFile.new()
	font.load_bitmap_font("res://assets/fonts/latin_small_healthbox.fnt")
	font.fixed_size_scale_mode = 2
	name_label.add_theme_font_override("font", font)
	name_label.add_theme_font_size_override("font_size", 40)
	var gender_label := Label.new()
	bs._position_gender_label(name_label, gender_label, male_mon)
	_chk("gender label text set to the real glyph", gender_label.text == "♂")
	_chk("gender label positioned strictly after the name label's own left edge",
			gender_label.offset_left > name_label.offset_left)
	_chk("gender label shares the name label's own top/bottom",
			gender_label.offset_top == name_label.offset_top
			and gender_label.offset_bottom == name_label.offset_bottom)

	var genderless_label := Label.new()
	bs._position_gender_label(name_label, genderless_label, genderless_mon)
	_chk("a genderless mon's gender label renders empty text",
			genderless_label.text == "")


# ── 2. Debug overlay is hidden by default ────────────────────────────────

func _test_debug_overlay_default_hidden() -> void:
	var scene: PackedScene = load("res://scenes/battle/battle_screen.tscn")
	var instance: Node = scene.instantiate()
	var overlay: Control = instance.get_node("SharedChrome/DebugOverlay")
	_chk("DebugOverlay is hidden by default, per this sub-phase's own locked scope",
			overlay.visible == false)
	instance.queue_free()


# ── 3-4. F3 toggle ────────────────────────────────────────────────────────

func _fake_key_event(code: Key, pressed: bool = true, echo: bool = false) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = pressed
	e.echo = echo
	return e


func _test_debug_overlay_toggle_via_f3() -> void:
	var bs := BattleScreen.new()
	bs._debug_overlay = Control.new()
	bs._debug_overlay.visible = false

	bs._unhandled_input(_fake_key_event(KEY_F3))
	_chk("F3 shows the overlay when it starts hidden", bs._debug_overlay.visible == true)

	bs._unhandled_input(_fake_key_event(KEY_F3))
	_chk("a second F3 press hides it again (a real toggle, not a one-way show)",
			bs._debug_overlay.visible == false)


func _test_debug_overlay_ignores_other_keys() -> void:
	var bs := BattleScreen.new()
	bs._debug_overlay = Control.new()
	bs._debug_overlay.visible = false

	bs._unhandled_input(_fake_key_event(KEY_F1))
	_chk("an unrelated key does not toggle the overlay", bs._debug_overlay.visible == false)

	bs._unhandled_input(_fake_key_event(KEY_F3, true, true))  # echo=true (held-key repeat)
	_chk("a key-repeat echo event does not toggle the overlay (would otherwise flicker while F3 is held)",
			bs._debug_overlay.visible == false)


# ── 5-7. Debug overlay content formatting ────────────────────────────────

func _test_format_debug_breakdown_full_content() -> void:
	var attacker := _make_typed_mon("Blastoise", TypeChart.TYPE_WATER, 50)
	var defender := _make_typed_mon("Charizard", TypeChart.TYPE_FIRE, 48)
	var move := _make_move("Water Gun", TypeChart.TYPE_WATER, 40, 100)
	var breakdown := {
		"damage": 62, "is_crit": true, "effectiveness": 2.0,
		"defender_item_consumed": false, "base_damage": 41,
		"stab_multiplier": 1.5, "roll": 92,
	}

	var text := BattleScreen._format_debug_breakdown(attacker, defender, move, breakdown)

	# [M26b] The old leading "Combat Debug (F3 to toggle)" line was dropped
	# from _format_debug_breakdown's own output — that's now the merged
	# panel's static Header label, shown once, not repeated per entry.
	_chk("debug text exactly reflects every field of the real breakdown dict passed in, not approximated",
			text == "Blastoise -> Charizard\nMove: Water Gun (Power 40, Acc 100)\n" \
					+ "Base damage: 41\nSTAB: 1.50x\nType eff.: 2.00x\nCrit: Yes\nRoll: 92%\nFinal damage: 62")


func _test_format_debug_breakdown_self_targeting_still_names_both() -> void:
	# A self-targeting/no-STAB/no-crit/neutral-effectiveness case, to confirm
	# the "No"/"1.00x" branches format correctly too (not just the "Yes"/
	# boosted-multiplier path exercised above).
	var attacker := _make_typed_mon("Snorlax", TypeChart.TYPE_NORMAL, 50)
	var defender := _make_typed_mon("Snorlax2", TypeChart.TYPE_NORMAL, 50)
	var move := _make_move("Tackle", TypeChart.TYPE_NORMAL, 40, 100)
	var breakdown := {
		"damage": 20, "is_crit": false, "effectiveness": 1.0,
		"defender_item_consumed": false, "base_damage": 20,
		"stab_multiplier": 1.5, "roll": 100,
	}

	var text := BattleScreen._format_debug_breakdown(attacker, defender, move, breakdown)

	_chk("a non-crit, neutral-effectiveness hit formats 'Crit: No' and 'Type eff.: 1.00x' exactly",
			"Crit: No" in text and "Type eff.: 1.00x" in text)


func _test_format_debug_breakdown_missing_keys_fixed_damage_move() -> void:
	# Mirrors a fixed-damage move (Sonic Boom/Dragon Rage/OHKO/etc.) whose own
	# DamageCalculator.calculate() early-return dict never reaches the main
	# formula, so base_damage/stab_multiplier/roll are genuinely absent —
	# per move_damage_breakdown's own doc comment, UI consumers must degrade
	# gracefully rather than crash.
	var attacker := _make_typed_mon("Voltorb", TypeChart.TYPE_ELECTRIC, 50)
	var defender := _make_typed_mon("Geodude", TypeChart.TYPE_GROUND, 50)
	var move := _make_move("Sonic Boom", TypeChart.TYPE_NORMAL, 1, 90)
	var breakdown := {"damage": 20, "is_crit": false, "effectiveness": 1.0}

	var text := BattleScreen._format_debug_breakdown(attacker, defender, move, breakdown)

	_chk("a fixed-damage move's breakdown (no base_damage/STAB/roll keys) formats without crashing",
			text == "Voltorb -> Geodude\nMove: Sonic Boom (Power 1, Acc 90)\nFinal damage: 20")


# ── 8-9. DamageCalculator's own new breakdown keys ───────────────────────

func _test_damage_calculator_returns_new_breakdown_keys() -> void:
	var attacker := _make_typed_mon("Gyarados", TypeChart.TYPE_WATER, 50)
	var defender := _make_typed_mon("Torkoal", TypeChart.TYPE_FIRE, 50)
	var move := _make_move("Water Gun", TypeChart.TYPE_WATER, 40, 100)

	var result: Dictionary = DamageCalculator.calculate(
			attacker, defender, move, 100, false, DamageCalculator.WEATHER_NONE)

	_chk("DamageCalculator.calculate now returns base_damage", result.has("base_damage"))
	_chk("DamageCalculator.calculate now returns stab_multiplier", result.has("stab_multiplier"))
	_chk("DamageCalculator.calculate now returns roll", result.has("roll"))
	_chk("a same-type move gets the real 1.5x STAB multiplier, reported as a plain float",
			result["stab_multiplier"] == 1.5)
	_chk("force_roll=100 is reported back verbatim as the roll actually used",
			result["roll"] == 100)
	_chk("base_damage is a positive int computed before STAB/type-eff/roll are applied",
			result["base_damage"] > 0 and result["base_damage"] is int)


func _test_damage_calculator_stab_multiplier_neutral_for_off_type_move() -> void:
	var attacker := _make_typed_mon("Pikachu", TypeChart.TYPE_ELECTRIC, 50)
	var defender := _make_typed_mon("Sandshrew", TypeChart.TYPE_GROUND, 50)
	var move := _make_move("Tackle", TypeChart.TYPE_NORMAL, 40, 100)  # off-type for an Electric attacker

	var result: Dictionary = DamageCalculator.calculate(
			attacker, defender, move, 100, false, DamageCalculator.WEATHER_NONE)

	_chk("an off-type move correctly reports no STAB (1.0x), not a stale/wrong multiplier",
			result["stab_multiplier"] == 1.0)


# ── 10. Real end-to-end proof: move_damage_breakdown actually fires from a
# genuine battle and reaches the overlay with exactly the real numbers. ──

func _test_real_battle_end_to_end_debug_signal_wiring() -> void:
	var attacker := _make_typed_mon("RealBlastoise", TypeChart.TYPE_WATER, 50)
	var defender := _make_typed_mon("RealCharizard", TypeChart.TYPE_FIRE, 50, 500)
	var atk_move := _make_move("Water Gun", TypeChart.TYPE_WATER, 40, 100)
	attacker.add_move(atk_move)
	var opp_move := _make_move("Tackle", TypeChart.TYPE_NORMAL, 0, 100)  # 0 power -> 0 damage, keeps attacker alive
	defender.add_move(opp_move)

	var bm := BattleManager.new()
	add_child(bm)
	bm.set_human_controlled(0, true)
	bm.set_human_controlled(1, true)
	bm._force_roll = 100
	bm._force_crit = true

	var bs := BattleScreen.new()
	bs._bm = bm
	bs._bm.move_damage_breakdown.connect(bs._on_debug_move_damage_breakdown)

	# [GDScript gotcha] A lambda captures a scalar local by VALUE, not by
	# reference — a plain `var real_damage := -1` reassigned inside the
	# lambda would only mutate the lambda's own private copy, never this
	# outer scope's variable. Wrapped in a 1-element Array (a RefCounted
	# object, captured by reference) to work around it.
	var real_damage := [-1]
	bm.move_executed.connect(func(atk: BattlePokemon, _def: BattlePokemon, mv: MoveData, dmg: int):
		if atk == attacker and mv == atk_move:
			real_damage[0] = dmg)

	bm.start_battle_with_parties(_singles_party([attacker]), _singles_party([defender]))
	bm.queue_move_targeted(0, 0, 1)
	bm.queue_move_targeted(1, 0, 0)
	bm.advance()

	# [M26b] No more single wholesale-replaced Label — the real breakdown now
	# lands as its own DAMAGE_MATH-tagged entry in the merged, permanent
	# `_debug_entries` history (bare `bs` here is never added to the
	# SceneTree, so `_debug_overlay` stays null and nothing auto-renders —
	# matching this project's own established bare-instance test convention
	# — but the entry itself is still appended regardless).
	var damage_math_text := _last_category_text(bs, BattleScreen.DebugCategory.DAMAGE_MATH)

	_chk("the real hit actually dealt damage (sanity check the scenario itself is valid)", real_damage[0] > 0)
	_chk("move_damage_breakdown reached the merged history via a genuine signal, naming the real attacker/defender",
			"RealBlastoise -> RealCharizard" in damage_math_text)
	_chk("the entry's own displayed final damage EXACTLY matches the real move_executed damage value, not approximated",
			("Final damage: %d" % real_damage[0]) in damage_math_text)
	_chk("the forced crit is reflected exactly (Crit: Yes)", "Crit: Yes" in damage_math_text)
	_chk("the real super-effective Water-vs-Fire matchup is reflected exactly (Type eff.: 2.00x)",
			"Type eff.: 2.00x" in damage_math_text)

	bm.queue_free()


# [M26b] Returns the most recently-appended entry's own text for a given
# category, or "" if none exists yet.
func _last_category_text(bs: BattleScreen, category: int) -> String:
	for i in range(bs._debug_entries.size() - 1, -1, -1):
		var entry: Dictionary = bs._debug_entries[i]
		if entry["category"] == category:
			return entry["text"]
	return ""
