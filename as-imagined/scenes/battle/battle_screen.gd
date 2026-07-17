extends Control

# [M23.1] Bare-bones battle screen — proves M23.0a's async pause/resume
# mechanism end-to-end through real UI. Two hardcoded teams (hand-built
# BattlePokemon fixtures, following the exact pattern established across
# this project's own test suite — see e.g. scenes/battle/ai_test.gd's
# `_make_mon`/`_load_move` helpers, quoted and cited in docs/m23_recon.md's
# M23.1 section). Side 0 is human-controlled via M23.0a's
# `set_human_controlled`/`queue_*`/`advance()` contract; side 1 is a
# TrainerAI (SMART tier) — already-proven, pre-existing logic, nothing new
# built here. SINGLES (not doubles) — confirmed as this engine's dominant/
# default mode (105 of 126 test files use a singles entry point vs. 21
# doubles) and the simpler fit for a "bare-bones" first UI pass; see
# docs/m23_recon.md for the full confirmation.
#
# Deliberately minimal per scope: no battle log (M23.2), no persistence, no
# team builder (M23.3/M23.4), no animation — plain Button/Label nodes,
# rebuilt from scratch on every state change rather than trying to manage
# node visibility toggling, since that's simplest for a "bare-bones,
# functional buttons only" screen.

const POTION_ITEM_ID := 28
const FULL_HEAL_ITEM_ID := 48
const X_ATTACK_ITEM_ID := 121

@onready var _bm: BattleManager = $BattleManager
@onready var _status_label: Label = $VBox/StatusLabel
@onready var _side0_label: Label = $VBox/Side0Label
@onready var _side1_label: Label = $VBox/Side1Label
@onready var _button_area: VBoxContainer = $VBox/ButtonArea

var _player_party: BattleParty
var _opp_party: BattleParty
var _winner_side: int = -1

# Which sub-menu the MOVE_SELECTION main-action screen is currently showing.
# Irrelevant during SWITCH_PROMPT, which always shows the bench-picker
# directly (a mandatory faint replacement, no "back" option).
enum Menu { MAIN, SWITCH, ITEM }
var _menu: Menu = Menu.MAIN


func _ready() -> void:
	_build_teams()

	var ai := TrainerAI.new()
	ai.tier = TrainerAI.Tier.SMART
	_bm.set_trainer_ai(1, ai)
	_bm.set_human_controlled(0, true)
	_bm.battle_ended.connect(_on_battle_ended)

	# start_battle_with_parties() calls advance() internally — this already
	# stalls at MOVE_SELECTION (side 0 is human-controlled, nothing queued
	# yet) before this function returns.
	_bm.start_battle_with_parties(_player_party, _opp_party)
	_refresh_ui()


func _on_battle_ended(winner_side: int) -> void:
	_winner_side = winner_side


# ── Team fixtures ────────────────────────────────────────────────────────
# Exact pattern followed from scenes/battle/ai_test.gd's own `_make_mon`
# (PokemonSpecies.new() + manually-set base stats/types, then
# BattlePokemon.from_species(sp, level, nature, ivs)) and `_load_move`
# (load a real move .tres by ID) helpers — hand-built fixtures, no
# PokemonRegistry/species-data-converter involved (that's M23.3/M23.4,
# explicitly out of scope here).

func _make_mon(mon_name: String, type1: int, type2: int = TypeChart.TYPE_NONE,
		hp: int = 180, atk: int = 80, def_stat: int = 80,
		spatk: int = 80, spdef: int = 80, spd: int = 80) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types.append(type1)
	if type2 != TypeChart.TYPE_NONE:
		sp.types.append(type2)
	sp.base_hp = hp
	sp.base_attack = atk
	sp.base_defense = def_stat
	sp.base_sp_attack = spatk
	sp.base_sp_defense = spdef
	sp.base_speed = spd
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])


func _load_move(id: int) -> MoveData:
	return load("res://data/moves/move_%04d.tres" % id) as MoveData


func _build_teams() -> void:
	var blaze := _make_mon("Blaze", TypeChart.TYPE_FIRE, TypeChart.TYPE_NONE,
			180, 90, 70, 100, 70, 90)
	blaze.add_move(_load_move(52))   # Ember
	blaze.add_move(_load_move(53))   # Flamethrower
	blaze.add_move(_load_move(98))   # Quick Attack
	blaze.add_move(_load_move(14))   # Swords Dance

	var torrent := _make_mon("Torrent", TypeChart.TYPE_WATER, TypeChart.TYPE_NONE,
			190, 80, 80, 90, 90, 70)
	torrent.add_move(_load_move(55))  # Water Gun
	torrent.add_move(_load_move(57))  # Surf
	torrent.add_move(_load_move(44))  # Bite
	torrent.add_move(_load_move(33))  # Tackle

	_player_party = BattleParty.new()
	_player_party.members = [blaze, torrent]
	_player_party.active_indices = [0]

	var leaf := _make_mon("Leaf", TypeChart.TYPE_GRASS, TypeChart.TYPE_NONE,
			180, 85, 75, 85, 75, 85)
	leaf.add_move(_load_move(22))   # Vine Whip
	leaf.add_move(_load_move(75))   # Razor Leaf
	leaf.add_move(_load_move(45))   # Growl
	leaf.add_move(_load_move(33))   # Tackle

	var volt := _make_mon("Volt", TypeChart.TYPE_ELECTRIC, TypeChart.TYPE_NONE,
			170, 75, 65, 95, 75, 100)
	volt.add_move(_load_move(85))   # Thunderbolt
	volt.add_move(_load_move(86))   # Thunder Wave
	volt.add_move(_load_move(98))   # Quick Attack
	volt.add_move(_load_move(231))  # Iron Tail

	_opp_party = BattleParty.new()
	_opp_party.members = [leaf, volt]
	_opp_party.active_indices = [0]


# ── UI rendering ─────────────────────────────────────────────────────────
# Rebuilt from scratch on every state change rather than toggling
# visibility on pre-declared nodes — simplest correct approach for a
# bare-bones, no-animation screen whose available actions genuinely change
# shape (move/switch/item vs. a mandatory bench-picker vs. nothing at
# battle end).

func _refresh_ui() -> void:
	for child in _button_area.get_children():
		child.queue_free()

	var side0_mon: BattlePokemon = _player_party.get_active()
	var side1_mon: BattlePokemon = _opp_party.get_active()
	_side0_label.text = "%s  HP: %d/%d%s" % [
			side0_mon.species.species_name, side0_mon.current_hp, side0_mon.max_hp,
			" (fainted)" if side0_mon.fainted else ""]
	_side1_label.text = "%s  HP: %d/%d%s" % [
			side1_mon.species.species_name, side1_mon.current_hp, side1_mon.max_hp,
			" (fainted)" if side1_mon.fainted else ""]

	if _bm.get_phase() == BattleManager.BattlePhase.BATTLE_END:
		_status_label.text = ("You win!" if _winner_side == 0 else "You lose!")
		return

	if _bm.get_phase() == BattleManager.BattlePhase.SWITCH_PROMPT:
		_status_label.text = "%s fainted! Choose a replacement." % side0_mon.species.species_name
		_build_switch_buttons(true)
		return

	# MOVE_SELECTION (the only other phase this screen ever stalls at,
	# since side 0 is the only human-controlled side).
	match _menu:
		Menu.SWITCH:
			_status_label.text = "Choose a Pokémon to switch in."
			_build_switch_buttons(false)
		Menu.ITEM:
			_status_label.text = "Choose an item."
			_build_item_buttons()
		_:
			_status_label.text = "Choose an action for %s." % side0_mon.species.species_name
			_build_main_menu(side0_mon)


func _build_main_menu(side0_mon: BattlePokemon) -> void:
	for i in range(side0_mon.moves.size()):
		var move: MoveData = side0_mon.moves[i]
		if move == null:
			continue
		var btn := Button.new()
		btn.text = "%s (PP %d/%d)" % [move.move_name, side0_mon.current_pp[i], move.pp]
		btn.disabled = side0_mon.current_pp[i] <= 0
		btn.pressed.connect(_on_move_pressed.bind(i))
		_button_area.add_child(btn)

	var switch_btn := Button.new()
	switch_btn.text = "Switch"
	switch_btn.disabled = not _player_party.has_valid_switch_target()
	switch_btn.pressed.connect(func():
		_menu = Menu.SWITCH
		_refresh_ui())
	_button_area.add_child(switch_btn)

	var item_btn := Button.new()
	item_btn.text = "Item"
	item_btn.pressed.connect(func():
		_menu = Menu.ITEM
		_refresh_ui())
	_button_area.add_child(item_btn)


func _build_switch_buttons(is_forced_replacement: bool) -> void:
	for i in range(_player_party.members.size()):
		if _player_party.active_indices.has(i) or _player_party.members[i].fainted:
			continue
		var mon: BattlePokemon = _player_party.members[i]
		var btn := Button.new()
		btn.text = "%s  HP: %d/%d" % [mon.species.species_name, mon.current_hp, mon.max_hp]
		btn.pressed.connect(_on_switch_pressed.bind(i, is_forced_replacement))
		_button_area.add_child(btn)

	if not is_forced_replacement:
		var back_btn := Button.new()
		back_btn.text = "Back"
		back_btn.pressed.connect(func():
			_menu = Menu.MAIN
			_refresh_ui())
		_button_area.add_child(back_btn)


func _build_item_buttons() -> void:
	var potion_btn := Button.new()
	potion_btn.text = "Potion (heal)"
	potion_btn.pressed.connect(_on_item_pressed.bind(POTION_ITEM_ID))
	_button_area.add_child(potion_btn)

	var full_heal_btn := Button.new()
	full_heal_btn.text = "Full Heal (cure status)"
	full_heal_btn.pressed.connect(_on_item_pressed.bind(FULL_HEAL_ITEM_ID))
	_button_area.add_child(full_heal_btn)

	var x_attack_btn := Button.new()
	x_attack_btn.text = "X Attack (+1 Attack)"
	x_attack_btn.pressed.connect(_on_item_pressed.bind(X_ATTACK_ITEM_ID))
	_button_area.add_child(x_attack_btn)

	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.pressed.connect(func():
		_menu = Menu.MAIN
		_refresh_ui())
	_button_area.add_child(back_btn)


# ── Input handlers — the M23.0a external contract in action ────────────────
# Every handler below is the exact queue_*() + advance() pattern confirmed
# in docs/m23_recon.md (M23.0a's proof scene and M23.0b's own translation
# check): supply the human's action via the pre-existing queue API, call
# advance() to resume the paused battle loop, then re-render from whatever
# phase advance() left the battle in.

func _on_move_pressed(move_index: int) -> void:
	_bm.queue_move_targeted(0, move_index, 1)  # 1 = the opponent's active combatant (singles)
	_bm.advance()
	_menu = Menu.MAIN
	_refresh_ui()


func _on_switch_pressed(slot: int, is_forced_replacement: bool) -> void:
	if is_forced_replacement:
		_bm.queue_replacement_for(0, slot)
	else:
		_bm.queue_switch_for(0, slot)
	_bm.advance()
	_menu = Menu.MAIN
	_refresh_ui()


func _on_item_pressed(item_id: int) -> void:
	_bm.queue_item_for(0, item_id)
	_bm.advance()
	_menu = Menu.MAIN
	_refresh_ui()
