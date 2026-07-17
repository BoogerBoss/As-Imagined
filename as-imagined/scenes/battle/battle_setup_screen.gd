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
# [Doubles status — FLAGGED, NOT FUNCTIONAL] The Singles/Doubles toggle
# exists in the UI (FormatToggleButton), but selecting Doubles disables the
# Launch button and shows an explicit status message rather than
# attempting a broken launch. battle_screen.gd's entire UI (move/switch/
# item menus, single hardcoded opponent-index-1 targeting in every button
# handler, `start_battle_with_parties` — confirmed singles-only per M23.1's
# own recon) would need real doubles-specific rework — a 4-combatant
# menu/targeting layer — to make Doubles genuinely playable, which is
# explicitly out of this "mostly UI glue" milestone's scope. The toggle is
# real (state persists, the button visibly reflects it), just gated.
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
@onready var _refresh_button: Button = $Scroll/VBox/RefreshButton
@onready var _launch_button: Button = $Scroll/VBox/LaunchButton

var _format: Format = Format.SINGLES


func _ready() -> void:
	_format_toggle_button.pressed.connect(_on_format_toggle_pressed)
	_refresh_button.pressed.connect(_refresh_team_lists)
	_launch_button.pressed.connect(_on_launch_pressed)
	_refresh_team_lists()

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
	var dropdowns_ok: bool = _player_option.item_count > 0 and _opponent_option.item_count > 0
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
	if _format == Format.DOUBLES:
		_status_label.text = "Doubles battles aren't supported by the battle screen yet (flagged for a future milestone) — switch back to Singles to launch."
		_launch_button.disabled = true
	else:
		_status_label.text = "Set up a battle."
		_launch_button.disabled = false


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

func _on_launch_pressed() -> void:
	if _format == Format.DOUBLES:
		_status_label.text = "Doubles isn't supported yet — switch to Singles first."
		return

	var player_party := _resolve_party(_player_option, false)
	if player_party == null or player_party.members.is_empty():
		_status_label.text = "Couldn't build your team — pick a different option and try again."
		return

	var opp_party := _resolve_party(_opponent_option, true)
	if opp_party == null or opp_party.members.is_empty():
		_status_label.text = "Couldn't build the opponent's team — pick a different option and try again."
		return

	BattleSetupContext.set_pending(player_party, opp_party)
	get_tree().change_scene_to_file("res://scenes/battle/battle_screen.tscn")
