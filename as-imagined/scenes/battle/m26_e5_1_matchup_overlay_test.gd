extends Node

# [M26E5-1] Regression suite for the matchup overlay's own first phase:
# engine getters (get_side_condition_turns/_layers/_flag), the two display
# helpers (_stage_multiplier_text/_stage_text), the type-badge mapping
# helper (_type_badge_stem/_type_badge_texture -- C5's own wire-up), the
# MatchupOverlay skeleton itself (build/close, both on a bare off-tree
# instance per this project's own established convention), and the trigger
# wiring on BattleScreenShared (_on_info_tab_pressed/_on_matchup_overlay_
# closed). Scope of record: docs/m26_e5_recon.md. Six decisions resolved by
# Rob 2026-08-04 -- see matchup_overlay.gd's own header for the full list.
#
# [Deliberately NOT tested here] _info_tab_btn.disabled's own live wiring
# inside _refresh_ui() -- that function has a large web of OTHER @onready
# dependencies (_button_area/_new_button_area/_move_buttons/_top_*_btn/
# etc.) that would all need hand-wiring on a bare instance just to exercise
# one boolean assignment; _on_info_tab_pressed()'s own defensive phase
# re-check (tested below, section E) covers the actual gating BEHAVIOR
# regardless of the button's own visual state. Also not tested: the real
# on-screen visual result (real window art, legible text, correct
# placement) -- matches every prior M25h/M26E overlay suite's own
# established precedent of scoping automated coverage to pure logic +
# bare-instance direct calls.
#
# [M26E5-2 additions, sections G-L] Category-icon mapping (C4's own
# wire-up), the type-badge row, the stat-stage table, per-move rows, and the
# player/opponent panels these compose into (built via real BattlePokemon
# fixtures -- BattlePokemon.from_species plus real loaded MoveData/
# AbilityData/ItemData .tres resources, matching d3_batch_test.gd's own
# established _make_mon-via-from_species precedent rather than hand-rolling
# a fake mon shape). Doubles layout and opponent-panel polish remain E5-3's
# job -- get_active_player_mon/get_active_opponent_mon already collapse to
# "first active slot", exercised here as the correct SINGLES behavior only.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_side_condition_turns_reads()
	_test_side_condition_layers_reads()
	_test_side_condition_flag_reads()
	_test_side_condition_getters_degrade_safely_out_of_range()

	_test_stage_multiplier_text_all_thirteen_values()
	_test_stage_multiplier_text_clamps_out_of_range()
	_test_stage_text_format_and_clamp()

	_test_type_badge_stem_irregular_cases()
	_test_type_badge_stem_regular_case()
	_test_type_badge_stem_stellar_has_no_badge()
	_test_type_badge_texture_loads_a_real_file()

	_test_field_strip_weather_none_baseline()
	_test_field_strip_weather_active_shows_turns()
	_test_field_strip_trick_room_only_shown_when_active()
	_test_field_strip_per_side_screens_and_hazards()
	_test_field_strip_omits_inactive_conditions()

	_test_overlay_builds_on_a_bare_instance_with_null_parent()
	_test_overlay_close_button_emits_closed()
	_test_overlay_escape_key_emits_closed()

	_test_info_tab_press_opens_a_real_wired_overlay()
	_test_info_tab_press_is_idempotent_while_overlay_open()
	_test_info_tab_press_refuses_outside_move_selection()
	_test_matchup_overlay_closed_frees_the_overlay_and_clears_the_reference()

	_test_category_icon_stem_all_three()
	_test_category_icon_stem_unmapped_is_empty()
	_test_category_icon_texture_loads_a_real_file()

	_test_type_row_shows_a_badge_per_real_type()
	_test_type_row_mono_type_shows_one_badge()

	_test_stat_stage_table_shows_all_seven_rows_and_reflects_real_stages()

	_test_move_row_shows_full_detail_for_a_contact_physical_move()
	_test_move_row_shows_special_move_with_a_secondary_chance()
	_test_move_row_shows_a_status_move_with_no_power_and_a_guaranteed_effect()

	_test_player_panel_shows_full_detail()
	_test_opponent_panel_shows_name_types_and_stages_only()
	_test_player_panel_shows_fallback_text_when_no_item_or_ability()
	_test_player_panel_builds_safely_with_no_active_mon()
	_test_overlay_builds_safely_with_null_parent_panels_empty()

	_test_player_panel_doubles_shows_two_mon_columns()
	_test_opponent_panel_doubles_shows_two_mon_columns()
	_test_doubles_layout_derives_slot_count_from_party_not_active_per_side()
	_test_singles_still_shows_exactly_one_column_each_side()

	var total := _pass + _fail
	print("m26_e5_1_matchup_overlay_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, condition: bool) -> void:
	if condition:
		_pass += 1
	else:
		_fail += 1
		print("  FAIL: %s" % label)


# ── Fixtures ─────────────────────────────────────────────────────────────

func _make_bm(phase: int = BattleManager.BattlePhase.BATTLE_START) -> BattleManager:
	var bm := BattleManager.new()
	bm._phase = phase
	return bm


func _make_bs_with_bm(bm: BattleManager) -> BattleScreenShared:
	# [Same fixture shape as item_select_screen_test.gd's own
	# _make_battle_screen_with_font()] A real loaded font, not a bare
	# BattleScreenShared.new() -- MatchupOverlay._build() styles its header/
	# field-strip labels off _parent_bs._font_menu unconditionally once
	# _parent_bs != null, exactly matching ItemSelectScreen's own
	# established shape, so a fixture with no font loaded crashes on a null
	# "font" theme property the instant setup() runs. Confirmed by this
	# suite's own first run: "Required object 'rp_font' is null."
	var bs := BattleScreenShared.new()
	bs._bm = bm
	bs._font_menu = FontFile.new()
	bs._font_menu.load_bitmap_font("res://assets/fonts/latin_normal_menu.fnt")
	return bs


# [M26E5-2] Real, on-disk data -- Tackle (33, physical/contact/no secondary),
# Thunderbolt (85, special/no-contact/10% secondary), Toxic (92, status/0
# power/90 acc/guaranteed secondary_chance==0 badly-poisons-on-hit) -- picked
# specifically because between them they exercise every branch of
# _build_move_row's own Pow/Acc/Sec/Contact formatting.
func _load_move(id: int) -> MoveData:
	return load("res://data/moves/move_%04d.tres" % id) as MoveData


func _make_full_mon() -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = "Testmon"
	sp.types = [TypeChart.TYPE_ELECTRIC, TypeChart.TYPE_FLYING]
	sp.base_hp = 100
	sp.base_attack = 60
	sp.base_defense = 60
	sp.base_sp_attack = 90
	sp.base_sp_defense = 60
	sp.base_speed = 90
	var mon := BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])
	mon.moves = [_load_move(33), _load_move(85), _load_move(92)]
	mon.current_pp = [30, 10, 5]
	mon.ability = load("res://data/abilities/ability_0022.tres") as AbilityData  # Intimidate
	mon.held_item = load("res://data/items/item_0472.tres") as ItemData          # Leftovers
	mon.stat_stages[BattlePokemon.STAGE_ATK] = 2
	mon.stat_stages[BattlePokemon.STAGE_SPEED] = -1
	mon.current_hp = int(mon.max_hp / 2.0)
	return mon


func _make_simple_mon() -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = "Foemon"
	sp.types = [TypeChart.TYPE_WATER]
	sp.base_hp = 80
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])


func _make_bs_with_active_mons(player_mon: BattlePokemon, opponent_mon: BattlePokemon) -> BattleScreenShared:
	var bm := _make_bm(BattleManager.BattlePhase.MOVE_SELECTION)
	var player_party := BattleParty.new()
	player_party.members = [player_mon]
	player_party.active_indices = [0]
	var opponent_party := BattleParty.new()
	opponent_party.members = [opponent_mon]
	opponent_party.active_indices = [0]
	bm._parties = [player_party, opponent_party]
	var bs := _make_bs_with_bm(bm)
	bs._player_party = player_party  # _mon_label's own "Your X"/"Foe X" split reads this field
	bs._opp_party = opponent_party   # [M26E5-3] opponent panel now reads this directly too
	return bs


# [M26E5-3] Doubles fixture: 2 active slots per side. `_active_per_side` is
# set for realism (a real doubles battle sets it) but the overlay itself
# never reads it -- it derives slot count purely from `party.num_active()`,
# confirmed independently testable by NOT setting it at all in some of the
# tests below.
func _make_bs_with_doubles_active_mons(player_mons: Array, opponent_mons: Array) -> BattleScreenShared:
	var bm := _make_bm(BattleManager.BattlePhase.MOVE_SELECTION)
	bm._active_per_side = 2
	var player_party := BattleParty.new()
	player_party.members.assign(player_mons)
	player_party.active_indices.assign(range(player_mons.size()))
	var opponent_party := BattleParty.new()
	opponent_party.members.assign(opponent_mons)
	opponent_party.active_indices.assign(range(opponent_mons.size()))
	bm._parties = [player_party, opponent_party]
	var bs := _make_bs_with_bm(bm)
	bs._player_party = player_party
	bs._opp_party = opponent_party
	return bs


func _make_named_mon(mon_name: String, type_id: int) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types = [type_id]
	sp.base_hp = 80
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])


func _bare_overlay(bs) -> MatchupOverlay:
	var scene: PackedScene = load("res://scenes/battle/matchup_overlay.tscn")
	var overlay: MatchupOverlay = scene.instantiate()
	overlay.setup(bs)
	return overlay


# Recursively walks a node's children collecting every Label's own .text --
# panel content is a mix of plain Labels and HBoxContainer rows (type/move
# rows) that themselves hold Labels alongside TextureRects, so a flat
# get_children() scan would miss anything nested one level down.
func _collect_label_texts(node: Node) -> Array:
	var out := []
	for child in node.get_children():
		if child is Label:
			out.append(child.text)
		else:
			out.append_array(_collect_label_texts(child))
	return out


func _count_texture_rects(node: Node) -> int:
	var count := 0
	for child in node.get_children():
		if child is TextureRect:
			count += 1
	return count


# ── A. get_side_condition_turns/_layers/_flag ────────────────────────────

func _test_side_condition_turns_reads() -> void:
	var bm := _make_bm()
	bm._side_conditions[0]["tailwind_turns"] = 3
	bm._side_conditions[1]["reflect_turns"] = 5
	_chk("reads the player side's own tailwind turns",
			bm.get_side_condition_turns(0, "tailwind") == 3)
	_chk("reads the opponent side's own reflect turns independently",
			bm.get_side_condition_turns(1, "reflect") == 5)
	_chk("a condition that was never set reads 0, not a crash",
			bm.get_side_condition_turns(0, "light_screen") == 0)


func _test_side_condition_layers_reads() -> void:
	var bm := _make_bm()
	bm._side_conditions[0]["spikes_layers"] = 2
	bm._side_conditions[1]["toxic_spikes_layers"] = 1
	_chk("reads Spikes layers", bm.get_side_condition_layers(0, "spikes") == 2)
	_chk("reads Toxic Spikes layers independently",
			bm.get_side_condition_layers(1, "toxic_spikes") == 1)
	_chk("an unset layer count reads 0", bm.get_side_condition_layers(0, "toxic_spikes") == 0)


func _test_side_condition_flag_reads() -> void:
	var bm := _make_bm()
	bm._side_conditions[0]["stealth_rock"] = true
	bm._side_conditions[1]["sticky_web"] = true
	_chk("reads Stealth Rock", bm.get_side_condition_flag(0, "stealth_rock") == true)
	_chk("reads Sticky Web independently", bm.get_side_condition_flag(1, "sticky_web") == true)
	_chk("an unset flag reads false, not a crash",
			bm.get_side_condition_flag(0, "sticky_web") == false)


func _test_side_condition_getters_degrade_safely_out_of_range() -> void:
	var bm := _make_bm()
	_chk("turns getter degrades to 0 for a negative side index",
			bm.get_side_condition_turns(-1, "tailwind") == 0)
	_chk("layers getter degrades to 0 for an out-of-range side index",
			bm.get_side_condition_layers(2, "spikes") == 0)
	_chk("flag getter degrades to false for an out-of-range side index",
			bm.get_side_condition_flag(99, "stealth_rock") == false)


# ── B. _stage_multiplier_text / _stage_text ──────────────────────────────

func _test_stage_multiplier_text_all_thirteen_values() -> void:
	var bs := BattleScreenShared.new()
	# Hand-verified against DamageCalculator.STAGE_RATIOS directly (source:
	# gStatStageRatios) -- the exact reason 2 decimal places are mandatory,
	# not a display nicety: -6/-5/-4 collide at "0.3x" with only 1.
	var expected := {
		-6: "0.25x", -5: "0.29x", -4: "0.33x", -3: "0.40x", -2: "0.50x", -1: "0.67x",
		0: "1.00x", 1: "1.50x", 2: "2.00x", 3: "2.50x", 4: "3.00x", 5: "3.50x", 6: "4.00x",
	}
	var all_correct := true
	for stage in expected.keys():
		var actual: String = bs._stage_multiplier_text(stage)
		if actual != expected[stage]:
			all_correct = false
			print("    stage %d: expected %s, got %s" % [stage, expected[stage], actual])
	_chk("all 13 real stage multipliers render correctly and unambiguously", all_correct)


func _test_stage_multiplier_text_clamps_out_of_range() -> void:
	var bs := BattleScreenShared.new()
	_chk("a stage below -6 clamps to the real -6 endpoint",
			bs._stage_multiplier_text(-99) == bs._stage_multiplier_text(-6))
	_chk("a stage above +6 clamps to the real +6 endpoint",
			bs._stage_multiplier_text(99) == bs._stage_multiplier_text(6))


func _test_stage_text_format_and_clamp() -> void:
	var bs := BattleScreenShared.new()
	_chk("positive stage renders with an explicit +", bs._stage_text(1) == "+1")
	_chk("negative stage renders with -", bs._stage_text(-2) == "-2")
	_chk("zero stage renders as +0, not a bare 0 (unambiguous sign)", bs._stage_text(0) == "+0")
	_chk("clamps below -6", bs._stage_text(-99) == "-6")
	_chk("clamps above +6", bs._stage_text(99) == "+6")


# ── C. Type-badge mapping (C5's own wire-up) ─────────────────────────────

func _test_type_badge_stem_irregular_cases() -> void:
	_chk("Fighting maps to the real file stem \"fight\", not \"fighting\"",
			BattleScreenShared._type_badge_stem(TypeChart.TYPE_FIGHTING) == "fight")
	_chk("Mystery maps to \"mystery\" by name, not by lowercasing its \"???\" display name",
			BattleScreenShared._type_badge_stem(TypeChart.TYPE_MYSTERY) == "mystery")


func _test_type_badge_stem_regular_case() -> void:
	_chk("a regular type (Water) matches its own lowercased display name",
			BattleScreenShared._type_badge_stem(TypeChart.TYPE_WATER) == "water")
	_chk("another regular type (Dragon)",
			BattleScreenShared._type_badge_stem(TypeChart.TYPE_DRAGON) == "dragon")


func _test_type_badge_stem_stellar_has_no_badge() -> void:
	_chk("Stellar (Tera-exclusive, excluded project-wide) returns an empty stem, not a guess",
			BattleScreenShared._type_badge_stem(TypeChart.TYPE_STELLAR) == "")


func _test_type_badge_texture_loads_a_real_file() -> void:
	var bs := BattleScreenShared.new()
	var tex := bs._type_badge_texture(TypeChart.TYPE_FIRE)
	_chk("a regular type resolves to a real, loaded Texture2D", tex != null and tex is Texture2D)
	var no_tex := bs._type_badge_texture(TypeChart.TYPE_STELLAR)
	_chk("an unmapped type (Stellar) returns null rather than a broken load", no_tex == null)


# ── D. MatchupOverlay.field_strip_lines (pure content builder) ───────────

func _test_field_strip_weather_none_baseline() -> void:
	var bm := _make_bm()
	var lines := MatchupOverlay.field_strip_lines(bm)
	_chk("weather is always the first line, shown even when None",
			lines.size() >= 1 and lines[0] == "Weather: None")
	_chk("with nothing else active, weather is the ONLY line",
			lines.size() == 1)


func _test_field_strip_weather_active_shows_turns() -> void:
	var bm := _make_bm()
	bm.weather = DamageCalculator.WEATHER_SANDSTORM
	bm.weather_duration = 4
	var lines := MatchupOverlay.field_strip_lines(bm)
	_chk("an active weather shows its real name and real remaining turns",
			lines[0] == "Weather: Sandstorm (4 turns)")


func _test_field_strip_trick_room_only_shown_when_active() -> void:
	var bm := _make_bm()
	var lines_inactive := MatchupOverlay.field_strip_lines(bm)
	_chk("Trick Room at 0 turns produces no line at all",
			not lines_inactive.any(func(l): return l.begins_with("Trick Room")))
	bm.trick_room_turns = 5
	var lines_active := MatchupOverlay.field_strip_lines(bm)
	_chk("Trick Room active shows its real remaining turns",
			lines_active.has("Trick Room: 5 turns"))


func _test_field_strip_per_side_screens_and_hazards() -> void:
	var bm := _make_bm()
	bm._side_conditions[0]["reflect_turns"] = 6
	bm._side_conditions[0]["spikes_layers"] = 3
	bm._side_conditions[1]["light_screen_turns"] = 2
	bm._side_conditions[1]["sticky_web"] = true
	var lines := MatchupOverlay.field_strip_lines(bm)
	_chk("your side's active screen shows with the correct label and side prefix",
			lines.has("Your side — Reflect: 6 turns"))
	_chk("your side's active hazard layer count shows correctly",
			lines.has("Your side — Spikes: 3"))
	_chk("the opponent's side is tracked independently, not merged with yours",
			lines.has("Opponent's side — Light Screen: 2 turns"))
	_chk("a flag-shaped hazard (Sticky Web) shows with no numeric suffix at all",
			lines.has("Opponent's side — Sticky Web"))


func _test_field_strip_omits_inactive_conditions() -> void:
	var bm := _make_bm()
	bm._side_conditions[0]["tailwind_turns"] = 4
	# Every OTHER real condition on both sides stays at its zero/false
	# default -- confirms the "omit what's inactive" rule genuinely
	# filters, not just that it happens to include what's active.
	var lines := MatchupOverlay.field_strip_lines(bm)
	_chk("exactly weather + the one active condition, nothing else", lines.size() == 2)
	_chk("no stray line for an inactive condition (Safeguard, picked at random)",
			not lines.any(func(l): return "Safeguard" in l))


# ── E. MatchupOverlay skeleton — bare off-tree instance ──────────────────

func _test_overlay_builds_on_a_bare_instance_with_null_parent() -> void:
	var scene: PackedScene = load("res://scenes/battle/matchup_overlay.tscn")
	var overlay: MatchupOverlay = scene.instantiate()
	# The exact scenario that crashed the first draft (see matchup_overlay.
	# gd's own field doc comment): setup() called before the node has ever
	# entered a SceneTree, with no parent BattleScreenShared to style from.
	overlay.setup(null)
	_chk("builds without crashing on a bare, off-tree instance with a null parent", true)
	overlay.queue_free()


func _test_overlay_close_button_emits_closed() -> void:
	var scene: PackedScene = load("res://scenes/battle/matchup_overlay.tscn")
	var overlay: MatchupOverlay = scene.instantiate()
	overlay.setup(null)
	var closed_count := [0]
	overlay.closed.connect(func(): closed_count[0] += 1)
	overlay._on_close_pressed()
	_chk("pressing Close emits closed()", closed_count[0] == 1)
	overlay.queue_free()


func _test_overlay_escape_key_emits_closed() -> void:
	var scene: PackedScene = load("res://scenes/battle/matchup_overlay.tscn")
	var overlay: MatchupOverlay = scene.instantiate()
	overlay.setup(null)
	# [Real, already-documented gotcha in this project -- phase4e_message_
	# box_test.gd hit the identical shape] _unhandled_input calls
	# get_viewport(), which is null on a bare instance never added to any
	# tree at all. Added to THIS suite's own live tree (this Node is
	# already inside a real SceneTree by the time _ready() runs) rather
	# than left detached, matching that precedent exactly.
	add_child(overlay)
	var closed_count := [0]
	overlay.closed.connect(func(): closed_count[0] += 1)
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	overlay._unhandled_input(esc)
	_chk("ESC closes the overlay, matching Item/Switch's own established convention",
			closed_count[0] == 1)
	overlay.queue_free()


# ── F. BattleScreenShared's own trigger wiring ───────────────────────────

func _test_info_tab_press_opens_a_real_wired_overlay() -> void:
	var bm := _make_bm(BattleManager.BattlePhase.MOVE_SELECTION)
	var bs := _make_bs_with_bm(bm)

	bs._on_info_tab_pressed()

	_chk("_matchup_overlay is a real MatchupOverlay",
			bs._matchup_overlay != null and bs._matchup_overlay is MatchupOverlay)
	_chk("the overlay is a genuine child of the battle screen (not floating/detached)",
			bs._matchup_overlay.get_parent() == bs)


func _test_info_tab_press_is_idempotent_while_overlay_open() -> void:
	var bm := _make_bm(BattleManager.BattlePhase.MOVE_SELECTION)
	var bs := _make_bs_with_bm(bm)

	bs._on_info_tab_pressed()
	var first_overlay := bs._matchup_overlay
	bs._on_info_tab_pressed()

	_chk("the overlay instance is unchanged across a second press (no stacked duplicate)",
			bs._matchup_overlay == first_overlay)
	var overlay_children := 0
	for c in bs.get_children():
		if c is MatchupOverlay:
			overlay_children += 1
	_chk("exactly one overlay child exists on the battle screen", overlay_children == 1)


func _test_info_tab_press_refuses_outside_move_selection() -> void:
	# Decision 2 (Rob, 2026-08-04): command phase only for this first cut.
	# The button's own .disabled state is the primary UI-level guard (not
	# covered here -- see this file's own header), so this test confirms
	# the SAME rule is also enforced at the handler level, defensively, in
	# case anything ever calls this function directly (e.g. the TAB key).
	var bm := _make_bm(BattleManager.BattlePhase.ACTION_EXECUTION)
	var bs := _make_bs_with_bm(bm)

	bs._on_info_tab_pressed()

	_chk("no overlay opens outside the command phase", bs._matchup_overlay == null)


func _test_matchup_overlay_closed_frees_the_overlay_and_clears_the_reference() -> void:
	var bm := _make_bm(BattleManager.BattlePhase.MOVE_SELECTION)
	var bs := _make_bs_with_bm(bm)

	bs._on_info_tab_pressed()
	_chk("sanity: the overlay really did open first", bs._matchup_overlay != null)
	bs._on_matchup_overlay_closed()

	_chk("_matchup_overlay is cleared back to null after closing", bs._matchup_overlay == null)
	# A second close (e.g. a double-fired signal) must not error on an
	# already-null/already-freed reference.
	bs._on_matchup_overlay_closed()
	_chk("closing again when already closed is a safe no-op, not a crash", true)


# ── G. Category-icon mapping (C4's own wire-up) ──────────────────────────

func _test_category_icon_stem_all_three() -> void:
	_chk("Physical (0) maps to \"physical\"", BattleScreenShared._category_icon_stem(0) == "physical")
	_chk("Special (1) maps to \"special\"", BattleScreenShared._category_icon_stem(1) == "special")
	_chk("Status (2) maps to \"status\"", BattleScreenShared._category_icon_stem(2) == "status")


func _test_category_icon_stem_unmapped_is_empty() -> void:
	_chk("an out-of-range category returns an empty stem, not a guess",
			BattleScreenShared._category_icon_stem(99) == "")


func _test_category_icon_texture_loads_a_real_file() -> void:
	var bs := BattleScreenShared.new()
	var tex := bs._category_icon_texture(1)
	_chk("Special resolves to a real, loaded Texture2D", tex != null and tex is Texture2D)
	var no_tex := bs._category_icon_texture(99)
	_chk("an unmapped category returns null rather than a broken load", no_tex == null)


# ── H. Type-badge row ─────────────────────────────────────────────────────

func _test_type_row_shows_a_badge_per_real_type() -> void:
	var mon := _make_full_mon()  # dual-type Electric/Flying
	var overlay := _bare_overlay(_make_bs_with_bm(_make_bm()))
	var row := overlay._build_type_row(mon.species.types)
	_chk("a dual-type mon renders exactly 2 type badges", _count_texture_rects(row) == 2)
	overlay.queue_free()


func _test_type_row_mono_type_shows_one_badge() -> void:
	var opp := _make_simple_mon()  # mono Water
	var overlay := _bare_overlay(_make_bs_with_bm(_make_bm()))
	var row := overlay._build_type_row(opp.species.types)
	_chk("a mono-type mon renders exactly 1 type badge", _count_texture_rects(row) == 1)
	overlay.queue_free()


# ── I. Stat-stage table ───────────────────────────────────────────────────

func _test_stat_stage_table_shows_all_seven_rows_and_reflects_real_stages() -> void:
	var mon := _make_full_mon()  # Atk +2, Speed -1, everything else neutral
	var overlay := _bare_overlay(_make_bs_with_bm(_make_bm()))
	var table := overlay._build_stat_stage_table(mon)
	var texts := _collect_label_texts(table)
	_chk("all 7 stat rows are present, no more, no fewer", texts.size() == 7)
	_chk("a boosted stat shows its real stage and real multiplier", texts.has("Atk +2 (2.00x)"))
	_chk("a lowered stat shows its real stage and real multiplier", texts.has("Spe -1 (0.67x)"))
	_chk("a neutral stat shows +0 and 1.00x", texts.has("Def +0 (1.00x)"))
	_chk("Accuracy shows its raw stage only, no multiplier (decision 4)", texts.has("Acc +0"))
	_chk("Evasion shows its raw stage only, no multiplier (decision 4)", texts.has("Eva +0"))
	overlay.queue_free()


# ── J. Move rows ──────────────────────────────────────────────────────────

func _test_move_row_shows_full_detail_for_a_contact_physical_move() -> void:
	var mon := _make_full_mon()
	var overlay := _bare_overlay(_make_bs_with_bm(_make_bm()))
	var row := overlay._build_move_row(mon, 0)  # Tackle: PHYS/contact/pow40/acc100/no secondary
	var texts := _collect_label_texts(row)
	_chk("shows the move's real name", texts.has("Tackle"))
	_chk("shows PP as cur/max", texts.has("PP 30/35"))
	_chk("shows real power and accuracy together", texts.has("Pow 40 / Acc 100%"))
	_chk("a move with no secondary effect shows an em dash for chance", texts.has("Sec —"))
	_chk("a contact move is flagged Contact", texts.has("Contact"))
	_chk("both the category icon and type badge render as real textures",
			_count_texture_rects(row) == 2)
	overlay.queue_free()


func _test_move_row_shows_special_move_with_a_secondary_chance() -> void:
	var mon := _make_full_mon()
	var overlay := _bare_overlay(_make_bs_with_bm(_make_bm()))
	var row := overlay._build_move_row(mon, 1)  # Thunderbolt: SPEC/no-contact/10% secondary
	var texts := _collect_label_texts(row)
	_chk("shows the move's real name", texts.has("Thunderbolt"))
	_chk("shows its real 10% secondary-effect chance explicitly", texts.has("Sec 10%"))
	_chk("a non-contact move shows an em dash, not \"Contact\"", texts.has("—"))
	overlay.queue_free()


func _test_move_row_shows_a_status_move_with_no_power_and_a_guaranteed_effect() -> void:
	var mon := _make_full_mon()
	var overlay := _bare_overlay(_make_bs_with_bm(_make_bm()))
	var row := overlay._build_move_row(mon, 2)  # Toxic: STATUS/pow0/acc90/secondary_chance==0
	var texts := _collect_label_texts(row)
	_chk("a status move (power 0) shows an em dash for power, not a misleading 0",
			texts.has("Pow — / Acc 90%"))
	_chk("secondary_chance==0 with a real effect renders as guaranteed 100%, not 0%",
			texts.has("Sec 100%"))
	overlay.queue_free()


# ── K. Player/opponent panels, end to end ────────────────────────────────

func _test_player_panel_shows_full_detail() -> void:
	var mon := _make_full_mon()
	var opp := _make_simple_mon()
	var overlay := _bare_overlay(_make_bs_with_active_mons(mon, opp))
	var texts := _collect_label_texts(overlay._player_panel_box)
	_chk("player panel shows the mon's own side-prefixed label",
			texts.any(func(t): return t.begins_with("Your ")))
	_chk("player panel shows HP as cur/max", texts.has("HP %d/%d" % [mon.current_hp, mon.max_hp]))
	_chk("player panel shows the held item's real name", texts.has("Item: Leftovers"))
	_chk("player panel shows the ability's real name", texts.has("Ability: Intimidate"))
	_chk("player panel shows the ability's real populated description (unlike a move's)",
			texts.any(func(t): return t.contains("Lowers the opposing")))
	_chk("player panel shows all 3 real move names",
			texts.has("Tackle") and texts.has("Thunderbolt") and texts.has("Toxic"))
	overlay.queue_free()


func _test_opponent_panel_shows_name_types_and_stages_only() -> void:
	var mon := _make_full_mon()
	var opp := _make_simple_mon()
	var overlay := _bare_overlay(_make_bs_with_active_mons(mon, opp))
	var texts := _collect_label_texts(overlay._opponent_panel_box)
	_chk("opponent panel shows the mon's own side-prefixed label",
			texts.any(func(t): return t.begins_with("Foe ")))
	_chk("opponent panel does NOT show HP (brief's own info-asymmetry rule)",
			not texts.any(func(t): return t.begins_with("HP ")))
	_chk("opponent panel does NOT show a held-item line",
			not texts.any(func(t): return t.begins_with("Item:")))
	_chk("opponent panel does NOT show an ability line",
			not texts.any(func(t): return t.begins_with("Ability:")))
	_chk("opponent panel still shows its own stat-stage table",
			texts.has("Atk +0 (1.00x)"))
	overlay.queue_free()


func _test_player_panel_shows_fallback_text_when_no_item_or_ability() -> void:
	var sp := PokemonSpecies.new()
	sp.species_name = "Baremon"
	sp.types = [TypeChart.TYPE_NORMAL]
	sp.base_hp = 100
	var mon := BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])
	mon.moves = []
	mon.current_pp = []
	var opp := _make_simple_mon()
	var overlay := _bare_overlay(_make_bs_with_active_mons(mon, opp))
	var texts := _collect_label_texts(overlay._player_panel_box)
	_chk("no held item shows the explicit \"None\" fallback, not a crash", texts.has("Item: None"))
	_chk("no ability shows the em-dash fallback, not a crash", texts.has("Ability: —"))
	_chk("no ability means no description line is added either",
			not texts.any(func(t): return t.contains("Lowers")))
	overlay.queue_free()


func _test_player_panel_builds_safely_with_no_active_mon() -> void:
	var overlay := _bare_overlay(_make_bs_with_bm(_make_bm(BattleManager.BattlePhase.MOVE_SELECTION)))
	_chk("no active player party builds without crashing, panel stays empty",
			overlay._player_panel_box.get_child_count() == 0)
	overlay.queue_free()


func _test_overlay_builds_safely_with_null_parent_panels_empty() -> void:
	var overlay := _bare_overlay(null)
	_chk("player panel is empty with a null parent", overlay._player_panel_box.get_child_count() == 0)
	_chk("opponent panel is empty with a null parent", overlay._opponent_panel_box.get_child_count() == 0)
	overlay.queue_free()


# ── M. Doubles layout (E5-3) ──────────────────────────────────────────────

func _test_player_panel_doubles_shows_two_mon_columns() -> void:
	var slot0 := _make_full_mon()
	var slot1 := _make_named_mon("Benchmon", TypeChart.TYPE_GRASS)
	var opp0 := _make_named_mon("Foe0", TypeChart.TYPE_ROCK)
	var opp1 := _make_named_mon("Foe1", TypeChart.TYPE_ICE)
	var overlay := _bare_overlay(_make_bs_with_doubles_active_mons([slot0, slot1], [opp0, opp1]))
	var texts := _collect_label_texts(overlay._player_panel_box)
	_chk("doubles player panel shows the first active slot's own label",
			texts.any(func(t): return t.begins_with("Your Testmon")))
	_chk("doubles player panel shows the second active slot's own label",
			texts.any(func(t): return t.begins_with("Your Benchmon")))
	_chk("doubles player panel shows two independent HP lines, one per active slot",
			texts.filter(func(t): return t.begins_with("HP ")).size() == 2)
	overlay.queue_free()


func _test_opponent_panel_doubles_shows_two_mon_columns() -> void:
	var slot0 := _make_full_mon()
	var opp0 := _make_named_mon("Foe0", TypeChart.TYPE_ROCK)
	var opp1 := _make_named_mon("Foe1", TypeChart.TYPE_ICE)
	var overlay := _bare_overlay(_make_bs_with_doubles_active_mons([slot0], [opp0, opp1]))
	var texts := _collect_label_texts(overlay._opponent_panel_box)
	_chk("doubles opponent panel shows both active opponents' own labels",
			texts.any(func(t): return t.begins_with("Foe Foe0")) and
			texts.any(func(t): return t.begins_with("Foe Foe1")))
	_chk("doubles opponent panel still shows no HP lines for either slot (brief's own info-asymmetry rule)",
			not texts.any(func(t): return t.begins_with("HP ")))
	_chk("doubles opponent panel shows an independent stat-stage table per slot",
			texts.filter(func(t): return t.begins_with("Atk ")).size() == 2)
	overlay.queue_free()


# [M26E5-3] Deliberately builds a party shaped like doubles (2 members, 2
# active_indices) while leaving `bm._active_per_side` at its own default (1,
# singles) -- proves `_build_mon_columns` derives its column count from
# `party.num_active()` alone, never from `_active_per_side`.
func _test_doubles_layout_derives_slot_count_from_party_not_active_per_side() -> void:
	var bm := _make_bm(BattleManager.BattlePhase.MOVE_SELECTION)
	var player_party := BattleParty.new()
	player_party.members = [_make_full_mon(), _make_simple_mon()]
	player_party.active_indices = [0, 1]
	var opponent_party := BattleParty.new()
	opponent_party.members = [_make_simple_mon()]
	opponent_party.active_indices = [0]
	bm._parties = [player_party, opponent_party]
	var bs := _make_bs_with_bm(bm)
	bs._player_party = player_party
	bs._opp_party = opponent_party
	var overlay := _bare_overlay(bs)
	var texts := _collect_label_texts(overlay._player_panel_box)
	_chk("column count follows party.num_active() regardless of _active_per_side's own default",
			texts.any(func(t): return t.begins_with("Your Testmon")) and
			texts.any(func(t): return t.begins_with("Your Foemon")))
	overlay.queue_free()


func _test_singles_still_shows_exactly_one_column_each_side() -> void:
	var mon := _make_full_mon()
	var opp := _make_simple_mon()
	var overlay := _bare_overlay(_make_bs_with_active_mons(mon, opp))
	_chk("player panel box holds exactly one row (the mon-columns HBox)",
			overlay._player_panel_box.get_child_count() == 1)
	var player_row: Node = overlay._player_panel_box.get_child(0)
	_chk("that row holds exactly one column in singles", player_row.get_child_count() == 1)
	var opp_row: Node = overlay._opponent_panel_box.get_child(0)
	_chk("opponent row also holds exactly one column in singles", opp_row.get_child_count() == 1)
	overlay.queue_free()
