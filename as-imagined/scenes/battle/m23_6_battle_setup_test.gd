extends Node

# [M23.6] Battle setup / format selection — automated headless test suite.
# Covers RandomTeamGenerator's legality (Sections 1-3), BattleSetupContext's
# hand-off mechanism in isolation (Section 4), and battle_setup_screen.gd's
# real button-driven dropdown/format-toggle behavior (Section 5).
#
# [Deliberately NOT tested here] Actually instantiating battle_screen.tscn
# (either directly or via a real Launch-button press/change_scene_to_file)
# — this project's own sweep script (scripts/count_assertions.sh) appends
# `--autoplay` to EVERY scene invocation unconditionally, including this
# test file's own process; if this suite embedded a battle_screen.tscn
# instance as a child, that instance's OWN `_ready()` would see
# `--autoplay` on the real process argv and call `_run_autoplay()`, which
# calls `get_tree().quit()` — silently killing this ENTIRE test process
# before its own later sections/summary line ever ran. The
# BattleSetupContext hand-off mechanism is trivial enough (plain static-var
# set/get/clear) to fully unit-test in isolation without touching
# battle_screen.tscn at all; the real end-to-end proof (a real
# battle_setup_screen → real battle_screen transition, actually reaching a
# playable screen with correct data) is covered by this session's manual
# verification instead — see docs/m23_recon.md's M23.6 section.

const _NAME_PREFIX := "__M23_6_TEST__"

var _pass := 0
var _fail := 0
var _cleanup_ids: Array[String] = []


func _ready() -> void:
	_test_section_1_team_size_and_clamping()
	_test_section_2_per_member_legality()
	_test_section_3_stat_formula_cross_check()
	_test_section_4_battle_setup_context()
	_test_section_5_setup_screen_ui()

	_cleanup()

	var total := _pass + _fail
	print("m23_6_battle_setup_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL: " + label)


func _cleanup() -> void:
	for id in _cleanup_ids:
		TeamStorage.delete_team(id)


# ── Section 1: team size / clamping ──────────────────────────────────────

func _test_section_1_team_size_and_clamping() -> void:
	var default_team := RandomTeamGenerator.generate_team()
	_chk("S1.01 default generate_team() produces a full 6-member team",
			default_team.members.size() == 6)

	var small_team := RandomTeamGenerator.generate_team(1)
	_chk("S1.02 generate_team(1) produces exactly 1 member", small_team.members.size() == 1)

	var mid_team := RandomTeamGenerator.generate_team(3)
	_chk("S1.03 generate_team(3) produces exactly 3 members", mid_team.members.size() == 3)

	var oversized_team := RandomTeamGenerator.generate_team(10)
	_chk("S1.04 generate_team(10) is clamped to the real 6-member team cap",
			oversized_team.members.size() == TeamStorage.MAX_TEAM_SIZE)

	var zero_team := RandomTeamGenerator.generate_team(0)
	_chk("S1.05 generate_team(0) is clamped up to at least 1 member", zero_team.members.size() >= 1)

	_chk("S1.06 active_indices defaults to [0] like every other BattleParty in this project",
			default_team.active_indices == [0])


# ── Section 2: per-member legality (moves/EVs/IVs/ability/level) ────────

func _test_section_2_per_member_legality() -> void:
	var min_level := 20
	var max_level := 40
	var team := RandomTeamGenerator.generate_team(6, min_level, max_level)
	_chk("S2.00 generated a 6-member team to inspect", team.members.size() == 6)

	for bp in team.members:
		var tag := "dex=%d" % bp.species.national_dex_num

		_chk("S2.01 [%s] species is real (national_dex_num resolves in PokemonRegistry)" % tag,
				not PokemonRegistry.get_species(bp.species.national_dex_num).is_empty())

		_chk("S2.02 [%s] level is within the requested [%d,%d] bound" % [tag, min_level, max_level],
				bp.level >= min_level and bp.level <= max_level)

		# Moves: real, legal for this species/level, no duplicates, <=4.
		var legal_pool: Array[int] = MovepoolResolver.legal_move_ids(bp.species.national_dex_num, bp.level)
		var seen_moves: Dictionary = {}
		var all_legal := true
		var all_unique := true
		for move in bp.moves:
			if move == null:
				continue
			var move_id := -1
			for candidate_id in legal_pool:
				var candidate: MoveData = MoveRegistry.get_move(candidate_id)
				if candidate != null and candidate.move_name == move.move_name:
					move_id = candidate_id
			if move_id == -1:
				all_legal = false
			if seen_moves.has(move.move_name):
				all_unique = false
			seen_moves[move.move_name] = true
		_chk("S2.03 [%s] every move is in the species' real legal pool at this level" % tag, all_legal)
		_chk("S2.04 [%s] no duplicate moves" % tag, all_unique)
		_chk("S2.05 [%s] moveset size is 0-4" % tag, bp.moves.size() <= 4)

		# EVs: real caps, matching BattleManager's own constants directly.
		var ev_total := 0
		var ev_per_stat_ok := true
		for v in bp.evs:
			ev_total += v
			if v < 0 or v > BattleManager.EV_CAP_PER_STAT:
				ev_per_stat_ok = false
		_chk("S2.06 [%s] EV total is within the real %d cap (got %d)" % [tag, BattleManager.EV_CAP_TOTAL, ev_total],
				ev_total <= BattleManager.EV_CAP_TOTAL)
		_chk("S2.07 [%s] every individual EV is within [0,%d]" % [tag, BattleManager.EV_CAP_PER_STAT], ev_per_stat_ok)
		_chk("S2.08 [%s] evs array has exactly 6 entries" % tag, bp.evs.size() == 6)

		# IVs: real 0-31 bounds.
		var iv_ok := true
		for v in bp.ivs:
			if v < 0 or v > 31:
				iv_ok = false
		_chk("S2.09 [%s] every IV is within [0,31]" % tag, iv_ok)
		_chk("S2.10 [%s] ivs array has exactly 6 entries" % tag, bp.ivs.size() == 6)

		# Ability: null, or a real nonzero slot the species actually has.
		# [Deliberately unconditional, not `if bp.ability != null:`-gated —
		# CLAUDE.md's own standing testing convention flags conditional
		# assertion counts as a real pitfall (a branch that doesn't always
		# execute changes this suite's own total assertion count run to
		# run, exactly what a first run of this test caught: 103/103 one
		# run, 104/104 the next, purely from whether a random team happened
		# to include an ability-less member). Folded into one always-fires
		# check instead.]
		var real_species: Dictionary = PokemonRegistry.get_species(bp.species.national_dex_num)
		var candidate_ids: Array = [
			int(real_species.get("ability1", 0)), int(real_species.get("ability2", 0)),
			int(real_species.get("ability_h", 0))]
		var ability_ok: bool = bp.ability == null or bp.ability.ability_id in candidate_ids
		_chk("S2.11 [%s] ability is null or one of this species' real ability slots" % tag, ability_ok)

		# Nature: a real value in [0,24].
		_chk("S2.12 [%s] nature is within [0,24]" % tag, bp.nature >= 0 and bp.nature <= 24)


# ── Section 3: stat-formula cross-check (deterministic via a fixed seed) ─

func _test_section_3_stat_formula_cross_check() -> void:
	seed(918273645)
	var team := RandomTeamGenerator.generate_team(3)
	_chk("S3.00 seeded generation still produced 3 members", team.members.size() == 3)

	for bp in team.members:
		# Independently-derived HP formula (documented directly in
		# battle_pokemon.gd's own _hp_formula comment: "Standard Pokémon HP
		# formula (Gen III+): floor((2*base + iv + floor(ev/4)) * level /
		# 100) + level + 10") — computed here from the BUILT BattlePokemon's
		# own recorded species/level/ivs/evs, NOT by re-calling any
		# BattlePokemon/PokemonFactory function, so this is a genuine
		# independent check, not a circular one.
		var base: int = bp.species.base_hp
		var iv: int = bp.ivs[BattlePokemon.STAT_HP]
		var ev: int = bp.evs[BattlePokemon.STAT_HP]
		var expected_hp: int = floori((2 * base + iv + floori(ev / 4.0)) * bp.level / 100.0) + bp.level + 10
		_chk("S3.01 [%s Lv.%d] max_hp matches the independently-computed HP formula (expected %d, got %d)" % [
				bp.species.species_name, bp.level, expected_hp, bp.max_hp],
				bp.max_hp == expected_hp)
		_chk("S3.02 [%s] current_hp starts at max_hp (freshly built)" % bp.species.species_name,
				bp.current_hp == bp.max_hp)


# ── Section 4: BattleSetupContext hand-off mechanism, in isolation ──────

func _test_section_4_battle_setup_context() -> void:
	_chk("S4.00 no pending context at suite start (clean state)", not BattleSetupContext.has_pending())

	var party_a := RandomTeamGenerator.generate_team(1)
	var party_b := RandomTeamGenerator.generate_team(1)
	BattleSetupContext.set_pending(party_a, party_b)
	_chk("S4.01 has_pending() is true after set_pending", BattleSetupContext.has_pending())
	_chk("S4.02 player_party is exactly the object passed in", BattleSetupContext.player_party == party_a)
	_chk("S4.03 opp_party is exactly the object passed in", BattleSetupContext.opp_party == party_b)

	BattleSetupContext.clear()
	_chk("S4.04 has_pending() is false after clear()", not BattleSetupContext.has_pending())
	_chk("S4.05 player_party is null after clear()", BattleSetupContext.player_party == null)
	_chk("S4.06 opp_party is null after clear()", BattleSetupContext.opp_party == null)


# ── Section 5: battle_setup_screen.gd — real UI, no scene transition ────

func _test_section_5_setup_screen_ui() -> void:
	# A real saved team to exercise the "saved" dropdown option against.
	var saved_id := TeamStorage.generate_id()
	_cleanup_ids.append(saved_id)
	var spec := {
		"dex": 1, "level": 25, "move_ids": [33, 45], "nature": BattlePokemon.NATURE_HARDY,
		"evs": [0, 0, 0, 0, 0, 0], "ivs": [31, 31, 31, 31, 31, 31],
		"ability_slot": PokemonFactory.ABILITY_SLOT_PRIMARY,
	}
	var saved_name := _NAME_PREFIX + "SetupScreen"
	TeamStorage.save_team(saved_id, saved_name, [spec])

	var scene: PackedScene = load("res://scenes/battle/battle_setup_screen.tscn")
	var setup := scene.instantiate()
	add_child(setup)

	var format_btn: Button = setup.get_node("Scroll/VBox/FormatRow/FormatToggleButton")
	var launch_btn: Button = setup.get_node("Scroll/VBox/LaunchButton")
	_chk("S5.01 starts in Singles with Launch enabled", format_btn.text == "Singles" and not launch_btn.disabled)

	format_btn.pressed.emit()
	_chk("S5.02 pressing the format toggle switches to Doubles", format_btn.text == "Doubles")
	_chk("S5.03 selecting Doubles disables Launch (not yet functional, per this session's own scope)",
			launch_btn.disabled)

	format_btn.pressed.emit()
	_chk("S5.04 toggling back to Singles re-enables Launch", format_btn.text == "Singles" and not launch_btn.disabled)

	var player_option: OptionButton = setup.get_node("Scroll/VBox/PlayerRow/PlayerTeamOptionButton")
	var opponent_option: OptionButton = setup.get_node("Scroll/VBox/OpponentRow/OpponentTeamOptionButton")
	_chk("S5.05 the player dropdown always offers 'Random Team'", player_option.get_item_text(0) == "Random Team")
	_chk("S5.06 the opponent dropdown offers both Random and the Quick Test fixture",
			opponent_option.get_item_text(0) == "Random Team"
			and opponent_option.get_item_text(1).begins_with("Quick Test"))

	var found_saved_in_player := false
	for i in range(player_option.item_count):
		if player_option.get_item_text(i).begins_with(saved_name):
			found_saved_in_player = true
			player_option.select(i)
	_chk("S5.07 the just-saved team appears in the player dropdown after Refresh", found_saved_in_player)

	# Resolve each option type directly (no Launch press — see this file's
	# own top-of-file note on why a real scene transition is avoided here).
	var random_party: BattleParty = setup._resolve_party(player_option, false)
	_chk("S5.08 resolving 'Random Team' produces a real, non-empty BattleParty",
			random_party != null and not random_party.members.is_empty())

	player_option.select(_index_with_text_prefix(player_option, saved_name))
	var saved_party: BattleParty = setup._resolve_party(player_option, false)
	_chk("S5.09 resolving the saved-team option produces a BattleParty matching what was saved",
			saved_party != null and saved_party.members.size() == 1
			and saved_party.members[0].species.national_dex_num == 1
			and saved_party.members[0].level == 25)

	opponent_option.select(1)  # Quick Test fixture
	var fixture_party: BattleParty = setup._resolve_party(opponent_option, true)
	_chk("S5.10 resolving the Quick Test fixture option produces Leaf & Volt",
			fixture_party != null and fixture_party.members.size() == 2
			and fixture_party.members[0].species.species_name == "Leaf"
			and fixture_party.members[1].species.species_name == "Volt")

	# [allow_fixture=false gate] The player side should never be able to
	# resolve the fixture option (it's never even offered in that
	# dropdown, but the resolver itself also refuses it defensively).
	var blocked_fixture: BattleParty = setup._resolve_party(opponent_option, false)
	_chk("S5.11 resolving the fixture option with allow_fixture=false is refused", blocked_fixture == null)

	setup.queue_free()


func _index_with_text_prefix(option: OptionButton, prefix: String) -> int:
	for i in range(option.item_count):
		if option.get_item_text(i).begins_with(prefix):
			return i
	return -1
