extends Control

# [M23.6] Battle setup / format selection — UI glue connecting M23.4/M23.5's
# team-builder-and-roster output to M23.1's already-proven battle screen.
# Picks (format, player team source, opponent team source), resolves both
# sides into real BattleParty instances, hands them to battle_screen.gd via
# BattleSetupContext (scripts/battle/core/battle_setup_context.gd — see
# that file's own doc comment for the hand-off mechanism), and transitions
# via change_scene_to_file. Does not itself touch battle_manager.gd,
# pokemon_factory.gd, team_builder_screen.gd's or roster_screen.gd's core
# logic — pure composition of already-built pieces.
#
# [Doubles status — RE-ENABLED, M23.11 Phase 4e] The Singles/Doubles toggle
# is now fully functional — both hard blockers this file's own original
# comment cited (the 4-combatant menu/targeting layer, and the visual
# sprite/health-box layer) shipped in Phase 4f and Phase 4d respectively,
# confirmed working together end-to-end via Phase 4d's own screenshot
# verification. Selecting Doubles no longer disables Launch; `_on_launch
# _pressed` instead reshapes whichever party each dropdown resolves to into
# a 2-active-slot BattleParty (see `_make_doubles_shaped`) and hands off via
# `BattleSetupContext.set_pending(..., true)`, exactly the mechanism
# `_scratch_screenshot_phase4d.gd`'s disposable driver used manually last
# session — this session wires the SAME hand-off through the real UI flow.
#
# [UI mechanism] Matches M23.1/M23.4/M23.5's shared-Theme + plain-Control-
# node convention. Two OptionButtons (player/opponent team source) rather
# than, say, a full roster-browser embed — this screen's whole job is
# picking WHICH already-built thing to use, not building anything new
# (that's team_builder_screen.gd/roster_screen.gd's job); a flat dropdown
# per side is the smallest correct mechanism for "pick one of N options."
# A "Refresh Team Lists" button re-populates both dropdowns from disk (no
# file-watching exists anywhere in this project) for the realistic case of
# saving a new team via the roster screen in an earlier visit, then
# returning here later in the same session.

enum Format { SINGLES, DOUBLES }

const _OPTION_RANDOM := "__random__"
const _OPTION_FIXTURE := "__fixture__"

@onready var _status_label: Label = $Scroll/VBox/StatusLabel
@onready var _format_toggle_button: Button = $Scroll/VBox/FormatRow/FormatToggleButton
@onready var _player_option: OptionButton = $Scroll/VBox/PlayerRow/PlayerTeamOptionButton
@onready var _opponent_option: OptionButton = $Scroll/VBox/OpponentRow/OpponentTeamOptionButton
@onready var _background_option: OptionButton = $Scroll/VBox/BackgroundRow/BackgroundOptionButton
@onready var _refresh_button: Button = $Scroll/VBox/RefreshButton
@onready var _manage_teams_button: Button = $Scroll/VBox/ManageTeamsButton
@onready var _launch_button: Button = $Scroll/VBox/LaunchButton

var _format: Format = Format.SINGLES


func _ready() -> void:
	_format_toggle_button.pressed.connect(_on_format_toggle_pressed)
	_refresh_button.pressed.connect(_refresh_team_lists)
	_manage_teams_button.pressed.connect(_on_manage_teams_pressed)
	_launch_button.pressed.connect(_on_launch_pressed)
	_refresh_team_lists()
	_populate_background_options()

	# [Autoplay — matches the M23.1-addendum precedent] Without this, a
	# direct sweep invocation of this scene idles forever with no
	# get_tree().quit() of its own, silently burning the sweep script's own
	# 25s per-scene timeout for zero assertions — the exact gap that
	# session's own entry closed for battle_screen.tscn. Deliberately does
	# NOT transition into battle_screen.tscn (no real change_scene_to_file
	# call here) — that would hand this file's own sweep-log section a
	# `battle_screen_autoplay` line instead of one attributable to THIS
	# scene, and would nest two scenes' autoplay logic inside one sweep
	# invocation. Instead this is a genuine, self-contained smoke check of
	# this screen's own mechanics: dropdowns actually populated, and both
	# the default player and opponent selections actually resolve to a
	# real, non-empty BattleParty via the exact same `_resolve_party` path
	# a real Launch press would use.
	# [Real bug found and fixed via this session's own m23_6_battle_setup
	# _test.gd Section 5] `--autoplay` is a process-wide CLI flag, not a
	# scene-scoped one — OS.get_cmdline_args() reads the whole process'
	# argv regardless of which scene is asking. Section 5 embeds a real
	# battle_setup_screen instance as a CHILD (to test _resolve_party etc.
	# without a real scene transition — see this file's own top-of-file
	# note); under the sweep's own unconditional --autoplay flag, that
	# embedded child's `_ready()` was ALSO seeing the flag and firing this
	# same autoplay path, printing a second "battle_setup_screen_autoplay:
	# 1/1 passed" line that the sweep script's regex then summed into
	# m23_6's own total (104 real assertions + 1 leaked autoplay pass =
	# 105 reported, silently wrong). Fixed by additionally requiring this
	# instance to actually BE the tree's current scene — true for a real
	# direct/sweep launch of this .tscn, false for any embedded/child
	# instantiation like the test's own.
	if "--autoplay" in OS.get_cmdline_args() and get_tree().current_scene == self:
		_run_autoplay()


func _run_autoplay() -> void:
	var dropdowns_ok: bool = (_player_option.item_count > 0 and _opponent_option.item_count > 0
			and _background_option.item_count > 0)
	var player_party := _resolve_party(_player_option, false)
	var opp_party := _resolve_party(_opponent_option, true)
	var resolved_ok: bool = (player_party != null and not player_party.members.is_empty()
			and opp_party != null and not opp_party.members.is_empty())
	var passed := 1 if (dropdowns_ok and resolved_ok) else 0
	print("battle_setup_screen_autoplay: %d/1 passed" % passed)
	if passed == 0:
		print("FAILED")
	get_tree().quit(0 if passed == 1 else 1)


# ── Format toggle ─────────────────────────────────────────────────────────

func _on_format_toggle_pressed() -> void:
	_format = Format.DOUBLES if _format == Format.SINGLES else Format.SINGLES
	_format_toggle_button.text = "Doubles" if _format == Format.DOUBLES else "Singles"
	# [M23.11 Phase 4e] Doubles no longer disables Launch — see this file's
	# own top-of-file doc comment for why both blockers this message used to
	# cite are closed. Status text stays the same neutral "set up a battle"
	# framing either way; `_on_launch_pressed` reports a specific error only
	# if a chosen team turns out too small for doubles.
	_status_label.text = "Set up a battle."
	_launch_button.disabled = false


# ── Roster navigation [M23.7] ────────────────────────────────────────────
# [Real integration gap found and closed by M23.7's own end-to-end
# walkthrough] Before this session, NOTHING in this project's real game
# flow (main.tscn -> this screen) linked to scenes/team_builder/
# roster_screen.tscn at all — roster_screen.tscn/team_builder_screen.tscn
# were only ever reachable by launching them directly (editor/command
# line) or from test scripts. A player using only real UI navigation could
# never build or save a team in the first place. Closed with the smallest
# possible addition: one button, one real change_scene_to_file call —
# mirroring this screen's own Launch button's exact mechanism. Returning
# from roster_screen.tscn (its own new Back button, see that file's own
# M23.7 note) lands back on a FRESH instance of this screen, whose _ready()
# already unconditionally calls _refresh_team_lists() — so a newly-saved
# team is picked up for free, no extra plumbing needed.

func _on_manage_teams_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/team_builder/roster_screen.tscn")


# ── Team-source dropdowns ─────────────────────────────────────────────────

func _refresh_team_lists() -> void:
	var saved_teams: Array[Dictionary] = []
	for summary in TeamStorage.list_teams():
		if not summary["corrupted"]:
			saved_teams.append(summary)

	_player_option.clear()
	_player_option.add_item("Random Team", 0)
	_player_option.set_item_metadata(0, {"type": _OPTION_RANDOM})
	for summary in saved_teams:
		var idx := _player_option.item_count
		_player_option.add_item("%s (%d member%s)" % [
			summary["name"], summary["member_count"], "" if summary["member_count"] == 1 else "s"], idx)
		_player_option.set_item_metadata(idx, {"type": "saved", "id": summary["id"]})
	# [Fallback requirement] If at least one saved team exists, default the
	# player's own pick to the first one rather than Random — Random only
	# needs to be the DEFAULT when there's genuinely nothing saved to pick.
	_player_option.select(1 if saved_teams.size() > 0 else 0)

	_opponent_option.clear()
	_opponent_option.add_item("Random Team", 0)
	_opponent_option.set_item_metadata(0, {"type": _OPTION_RANDOM})
	_opponent_option.add_item("Quick Test (Leaf & Volt fixture)", 1)
	_opponent_option.set_item_metadata(1, {"type": _OPTION_FIXTURE})
	for summary in saved_teams:
		var idx := _opponent_option.item_count
		_opponent_option.add_item("%s (%d member%s)" % [
			summary["name"], summary["member_count"], "" if summary["member_count"] == 1 else "s"], idx)
		_opponent_option.set_item_metadata(idx, {"type": "saved", "id": summary["id"]})
	_opponent_option.select(0)

	_status_label.text = "Set up a battle. (%d saved team%s found)" % [
		saved_teams.size(), "" if saved_teams.size() == 1 else "s"]


# ── Background picker [M23.11 Phase 5a] ─────────────────────────────────
# A manual picker, not tied to any overworld/terrain concept (that's M26's
# future job — see docs/m23_11_phase5_recon.md Section 0 item 3) and not a
# single hardcoded default. Populated once from BattleBackgroundRegistry's
# own directory scan rather than a hardcoded 11-name list, so a future
# background added to assets/sprites/battle_backgrounds/ shows up here
# automatically without touching this file. Unlike the team dropdowns,
# this never needs re-populating mid-session (the background asset
# directory isn't user-editable at runtime the way saved teams are), so
# it's populated once in _ready() rather than folded into
# _refresh_team_lists().
func _populate_background_options() -> void:
	_background_option.clear()
	var ids := BattleBackgroundRegistry.list_background_ids()
	for id in ids:
		var idx := _background_option.item_count
		_background_option.add_item(BattleBackgroundRegistry.display_name(id), idx)
		_background_option.set_item_metadata(idx, id)
	if _background_option.item_count > 0:
		_background_option.select(0)


func _selected_background_id() -> String:
	if _background_option.item_count == 0 or _background_option.selected < 0:
		return ""
	return _background_option.get_item_metadata(_background_option.selected)


# ── Resolving a dropdown selection into a real BattleParty ────────────────

func _resolve_party(option: OptionButton, allow_fixture: bool) -> BattleParty:
	if option.item_count == 0 or option.selected < 0:
		return null
	var meta: Dictionary = option.get_item_metadata(option.selected)
	match meta.get("type", ""):
		_OPTION_RANDOM:
			return RandomTeamGenerator.generate_team()
		_OPTION_FIXTURE:
			return BattleScreen.build_fixture_opp_party() if allow_fixture else null
		"saved":
			return _build_saved_party(meta.get("id", ""))
		_:
			return null


func _build_saved_party(id: String) -> BattleParty:
	var team := TeamStorage.load_team(id)
	if team.is_empty():
		return null
	var members: Array[BattlePokemon] = []
	for spec in team.get("members", []):
		var bp: BattlePokemon = TeamStorage.build_member(spec)
		if bp != null:
			members.append(bp)
	if members.is_empty():
		return null
	var party := BattleParty.new()
	party.members = members
	party.active_indices = [0]
	return party


# ── Launch ──────────────────────────────────────────────────────────────

# [M23.11 Phase 4e] Every party this screen can resolve (`RandomTeamGenerator
# .generate_team`, `_build_saved_party`, `BattleScreen.build_fixture_opp
# _party`) always builds `active_indices = [0]` — a singles-only assumption
# baked into each of those functions individually, not something this screen
# can control from the outside except by re-assigning `active_indices`
# after the fact. Reshapes to 2 active slots when the party has enough
# members; returns null (caller shows a friendly error) rather than
# guessing/padding when it doesn't — a 1-member saved team genuinely can't
# field a doubles side.
func _make_doubles_shaped(party: BattleParty) -> BattleParty:
	if party == null or party.members.size() < 2:
		return null
	var doubles_indices: Array[int] = [0, 1]
	party.active_indices = doubles_indices
	return party


func _on_launch_pressed() -> void:
	var player_party := _resolve_party(_player_option, false)
	if player_party == null or player_party.members.is_empty():
		_status_label.text = "Couldn't build your team — pick a different option and try again."
		return

	var opp_party := _resolve_party(_opponent_option, true)
	if opp_party == null or opp_party.members.is_empty():
		_status_label.text = "Couldn't build the opponent's team — pick a different option and try again."
		return

	if _format == Format.DOUBLES:
		player_party = _make_doubles_shaped(player_party)
		if player_party == null:
			_status_label.text = "Your team needs at least 2 Pokémon for a Doubles battle — pick a different option or switch to Singles."
			return
		opp_party = _make_doubles_shaped(opp_party)
		if opp_party == null:
			_status_label.text = "The opponent's team needs at least 2 Pokémon for a Doubles battle — pick a different option or switch to Singles."
			return

	BattleSetupContext.set_pending(player_party, opp_party, _format == Format.DOUBLES,
			_selected_background_id())
	get_tree().change_scene_to_file("res://scenes/battle/battle_screen.tscn")
