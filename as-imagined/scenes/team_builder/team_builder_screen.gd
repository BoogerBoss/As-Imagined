extends Control

# [M23.4] Team builder core — species/moveset/item(-free)/ability/nature/EV/IV
# selection for ONE Pokémon at a time, producing a real BattlePokemon via
# PokemonFactory.create_battle_pokemon(). No team/roster list, no
# persistence (M23.5), no wiring into the battle screen (M23.6) — this
# screen's whole job ends the moment one validated BattlePokemon exists in
# memory (_built_pokemon below), per the roadmap's own explicit scope line.
#
# Follows M23.1/M23.2's established UI conventions (plain Control nodes +
# the shared scenes/main_theme.tres, rebuild-affected-areas-from-scratch on
# state change rather than visibility toggling) — see this file's own
# per-section comments for the couple of small, flagged deviations (SpinBox
# for numeric input, a ScrollContainer, since this screen has meaningfully
# more on-screen state than the battle screen's fixed button rows).
#
# [Held items] Deliberately NOT included — PokemonFactory.
# create_battle_pokemon has no item parameter (flagged as out of scope in
# its OWN doc comment, "add one in a future session if a caller needs it"),
# and the M23.4 task's own requirement list never asked for item selection
# either (only species/moveset/ability/nature/EV/IV). Not built here.
#
# [Species picker mechanism — flagged per the task's own instruction]
# Dex-number entry (LineEdit + Load button), not a searchable name list.
# 386 species is large enough that a live-filtering name search would be a
# meaningfully bigger UI component (a scrollable filtered ListBox, its own
# focus/selection handling) for a "core" milestone whose own explicit scope
# line is "one Pokémon at a time" — dex-number entry is the smallest
# correct mechanism that still lets any of the 386 species be built, and
# PokemonRegistry's own get_species()/smoke-test already treat dex number
# as the canonical species identifier throughout this project. Species name
# is shown immediately after a successful load so a builder isn't flying
# blind. A name-search picker is a reasonable follow-up if Rob wants one.
#
# [EV/IV input mechanism] SpinBox, not LineEdit + manual parsing/clamping.
# SpinBox's own min_value/max_value/step are a real, load-bearing legality
# mechanism here — a per-stat EV box is statically capped at 252 by the
# widget itself, an IV box at 31, and the *total* EV cap (510) is enforced
# dynamically by recomputing every other box's own max_value on each edit
# (see _on_ev_spinbox_changed) — the widget makes an over-cap value
# physically unenterable, not merely rejected after the fact, matching this
# milestone's own "the UI prevents it" requirement more directly than a
# free-text field ever could.
#
# [Move legality] Enforced by construction, not by validating a free
# choice: MovepoolResolver.legal_move_ids(dex, level) is the ONLY source
# populating the "available moves to add" dropdown, and an already-selected
# move is removed from that dropdown's own candidate list — so a move
# outside the real legal set, or a duplicate, is never an option to pick in
# the first place. See movepool_resolver.gd's own doc comment for the
# (flagged, conservative) legality policy get_learnable_moves()'s own data
# shape forces.
#
# [M23.5 addition — additive only, zero change to the building/validation
# logic above] `pokemon_built` and `get_current_spec()` exist purely so
# scenes/team_builder/roster_screen.gd can capture what was just built as a
# plain, serializable Dictionary (dex/level/move_ids/nature/evs/ivs/
# ability_slot — exactly PokemonFactory.create_battle_pokemon's own
# parameter list) without reaching into this screen's private widget state
# directly. `_on_build_pressed` itself is unchanged in behavior — it now
# reads its inputs via get_current_spec() instead of five separate local
# blocks, then additionally emits the new signal at the end. Confirmed via
# a full rerun that m23_4_team_builder_test.gd (44/44) is unaffected — it
# reads `_built_pokemon`/`_selected_move_ids` directly and never touches
# either new member.

const _NATURE_NAMES: Array[String] = [
	"Hardy", "Lonely", "Brave", "Adamant", "Naughty",
	"Bold", "Docile", "Relaxed", "Impish", "Lax",
	"Timid", "Hasty", "Serious", "Jolly", "Naive",
	"Modest", "Mild", "Quiet", "Bashful", "Rash",
	"Calm", "Gentle", "Sassy", "Careful", "Quirky",
]

const _ABILITY_SLOT_LABELS: Array[String] = ["Primary", "Secondary", "Hidden"]

const _EV_STAT_NAMES: Array[String] = ["HP", "Attack", "Defense", "Sp. Atk", "Sp. Def", "Speed"]

# [M23.5] Emitted at the end of a successful build, alongside the same spec
# get_current_spec() would return — lets a host screen (roster_screen.gd)
# react without polling.
signal pokemon_built(spec: Dictionary, bp: BattlePokemon)

@onready var _status_label: Label = $Scroll/VBox/StatusLabel
@onready var _species_line_edit: LineEdit = $Scroll/VBox/SpeciesRow/SpeciesLineEdit
@onready var _load_species_button: Button = $Scroll/VBox/SpeciesRow/LoadSpeciesButton
@onready var _species_info_label: Label = $Scroll/VBox/SpeciesRow/SpeciesInfoLabel
@onready var _level_spinbox: SpinBox = $Scroll/VBox/LevelRow/LevelSpinBox
@onready var _ability_option: OptionButton = $Scroll/VBox/AbilityRow/AbilityOptionButton
@onready var _nature_option: OptionButton = $Scroll/VBox/NatureRow/NatureOptionButton
@onready var _selected_moves_list: VBoxContainer = $Scroll/VBox/MovesSection/SelectedMovesList
@onready var _available_moves_option: OptionButton = $Scroll/VBox/MovesSection/AddMoveRow/AvailableMovesOptionButton
@onready var _add_move_button: Button = $Scroll/VBox/MovesSection/AddMoveRow/AddMoveButton
@onready var _ev_total_label: Label = $Scroll/VBox/EVSection/EVTotalLabel
@onready var _build_button: Button = $Scroll/VBox/BuildButton
@onready var _result_label: RichTextLabel = $Scroll/VBox/ResultLabel

var _ev_spinboxes: Array[SpinBox] = []
var _iv_spinboxes: Array[SpinBox] = []

var _current_dex: int = -1
var _current_species: PokemonSpecies = null
var _current_level: int = 50
var _legal_move_ids: Array[int] = []
var _selected_move_ids: Array[int] = []

var _updating_ev_bounds: bool = false

var _built_pokemon: BattlePokemon = null


func _ready() -> void:
	_ev_spinboxes = [
		$Scroll/VBox/EVSection/EVRowHP/SpinBox, $Scroll/VBox/EVSection/EVRowAtk/SpinBox,
		$Scroll/VBox/EVSection/EVRowDef/SpinBox, $Scroll/VBox/EVSection/EVRowSpAtk/SpinBox,
		$Scroll/VBox/EVSection/EVRowSpDef/SpinBox, $Scroll/VBox/EVSection/EVRowSpeed/SpinBox,
	]
	_iv_spinboxes = [
		$Scroll/VBox/IVSection/IVRowHP/SpinBox, $Scroll/VBox/IVSection/IVRowAtk/SpinBox,
		$Scroll/VBox/IVSection/IVRowDef/SpinBox, $Scroll/VBox/IVSection/IVRowSpAtk/SpinBox,
		$Scroll/VBox/IVSection/IVRowSpDef/SpinBox, $Scroll/VBox/IVSection/IVRowSpeed/SpinBox,
	]

	for i in range(_NATURE_NAMES.size()):
		_nature_option.add_item(_NATURE_NAMES[i], i)
	_nature_option.select(0)  # OptionButton doesn't auto-select on add_item.

	for sb in _ev_spinboxes:
		sb.value_changed.connect(func(_v): _on_ev_spinbox_changed())
	_on_ev_spinbox_changed()  # initialize the total label / bounds at all-zero.

	_load_species_button.pressed.connect(_on_load_species_pressed)
	_level_spinbox.value_changed.connect(_on_level_changed)
	_add_move_button.pressed.connect(_on_add_move_pressed)
	_build_button.pressed.connect(_on_build_pressed)

	_set_move_ui_enabled(false)


# ── Species loading ──────────────────────────────────────────────────────

func _on_load_species_pressed() -> void:
	var text := _species_line_edit.text.strip_edges()
	if not text.is_valid_int():
		_status_label.text = "Enter a valid dex number."
		return

	var dex := int(text)
	var species := PokemonFactory.build_species(dex)
	if species == null:
		_status_label.text = "No species found for dex #%d." % dex
		return

	_current_dex = dex
	_current_species = species
	_current_level = int(_level_spinbox.value)
	_selected_move_ids.clear()

	var types_text := TypeChart.type_name(species.types[0])
	if species.types.size() > 1:
		types_text += " / " + TypeChart.type_name(species.types[1])
	_species_info_label.text = "#%d %s (%s)" % [dex, species.species_name, types_text]
	_status_label.text = "Loaded %s. Pick a level, ability, nature, moves, EVs, and IVs." % species.species_name

	_rebuild_ability_options()
	_recompute_legal_moves()
	_set_move_ui_enabled(true)


func _on_level_changed(value: float) -> void:
	_current_level = int(value)
	if _current_dex < 0:
		return
	_recompute_legal_moves()


# ── Ability selection ────────────────────────────────────────────────────
# Populated ONLY with this species' real ability slots (id > 0) — a slot
# whose id is 0 ("None", every species has at least one empty slot) is
# never offered, matching PokemonFactory.create_battle_pokemon's own
# "id 0 means no ability" convention exactly (see that function's own doc
# comment) rather than inventing a separate "no ability" UI option.

func _rebuild_ability_options() -> void:
	_ability_option.clear()
	for slot in range(_current_species.abilities.size()):
		var ability_id: int = _current_species.abilities[slot]
		if ability_id <= 0:
			continue
		var ability_path := "res://data/abilities/ability_%04d.tres" % ability_id
		var ability_name := "Ability #%d" % ability_id
		if ResourceLoader.exists(ability_path):
			var data := ResourceLoader.load(ability_path) as AbilityData
			if data != null and not data.ability_name.is_empty():
				ability_name = data.ability_name
		var slot_label: String = _ABILITY_SLOT_LABELS[slot] if slot < _ABILITY_SLOT_LABELS.size() else "Slot %d" % slot
		_ability_option.add_item("%s (%s)" % [ability_name, slot_label], slot)
	if _ability_option.item_count > 0:
		_ability_option.select(0)  # OptionButton doesn't auto-select on add_item.


# ── Move selection ───────────────────────────────────────────────────────

func _set_move_ui_enabled(enabled: bool) -> void:
	_available_moves_option.disabled = not enabled
	_add_move_button.disabled = not enabled


func _recompute_legal_moves() -> void:
	_legal_move_ids = MovepoolResolver.legal_move_ids(_current_dex, _current_level)

	var removed: Array[String] = []
	var still_legal: Array[int] = []
	for move_id in _selected_move_ids:
		if move_id in _legal_move_ids:
			still_legal.append(move_id)
		else:
			var move: MoveData = MoveRegistry.get_move(move_id)
			removed.append(move.move_name if move != null else "move #%d" % move_id)
	_selected_move_ids = still_legal
	if not removed.is_empty():
		_status_label.text = "Level change made these illegal and removed them: %s" % ", ".join(removed)

	_refresh_move_ui()


func _refresh_move_ui() -> void:
	for child in _selected_moves_list.get_children():
		child.queue_free()
	for i in range(_selected_move_ids.size()):
		var move_id: int = _selected_move_ids[i]
		var move: MoveData = MoveRegistry.get_move(move_id)
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = "%s (PP %d)" % [move.move_name if move != null else "?", move.pp if move != null else 0]
		label.custom_minimum_size = Vector2(200, 0)
		row.add_child(label)
		var remove_btn := Button.new()
		remove_btn.text = "Remove"
		remove_btn.pressed.connect(_on_remove_move_pressed.bind(i))
		row.add_child(remove_btn)
		_selected_moves_list.add_child(row)

	_available_moves_option.clear()
	if _selected_move_ids.size() >= 4:
		_add_move_button.disabled = true
		_available_moves_option.disabled = true
		return
	_add_move_button.disabled = false
	_available_moves_option.disabled = false
	for move_id in _legal_move_ids:
		if move_id in _selected_move_ids:
			continue
		var move: MoveData = MoveRegistry.get_move(move_id)
		if move == null:
			continue
		_available_moves_option.add_item(move.move_name, move_id)
	if _available_moves_option.item_count > 0:
		_available_moves_option.select(0)  # OptionButton doesn't auto-select on add_item.


func _on_add_move_pressed() -> void:
	if _available_moves_option.item_count == 0 or _selected_move_ids.size() >= 4:
		return
	var move_id: int = _available_moves_option.get_item_id(_available_moves_option.selected)
	# [Redundant-but-cheap legality re-check] The dropdown already only ever
	# lists legal, not-yet-selected moves — this is a belt-and-suspenders
	# guard against a stale selection index, not evidence an illegal pick
	# was otherwise reachable.
	if move_id not in _legal_move_ids or move_id in _selected_move_ids:
		return
	_selected_move_ids.append(move_id)
	_refresh_move_ui()


func _on_remove_move_pressed(index: int) -> void:
	if index < 0 or index >= _selected_move_ids.size():
		return
	_selected_move_ids.remove_at(index)
	_refresh_move_ui()


# ── EV selection ─────────────────────────────────────────────────────────
# See this file's own top-of-file doc comment for why the total-EV cap
# (510) is enforced by dynamically shrinking every OTHER box's own
# max_value, rather than clamping after the fact.

func _on_ev_spinbox_changed() -> void:
	if _updating_ev_bounds:
		return
	_updating_ev_bounds = true

	var total := 0
	for sb in _ev_spinboxes:
		total += int(sb.value)

	for sb in _ev_spinboxes:
		var others: int = total - int(sb.value)
		var remaining_room: int = BattleManager.EV_CAP_TOTAL - others
		sb.max_value = clampi(remaining_room, 0, BattleManager.EV_CAP_PER_STAT)

	_ev_total_label.text = "Total: %d / %d" % [total, BattleManager.EV_CAP_TOTAL]
	_updating_ev_bounds = false


# ── Build ─────────────────────────────────────────────────────────────────

# [M23.5] The plain, serializable form of "everything needed to reconstruct
# this exact BattlePokemon via PokemonFactory.create_battle_pokemon" —
# deliberately shaped as that function's own parameter list (dex/level/
# move_ids/nature/evs/ivs/ability_slot) so a caller (roster_screen.gd) never
# has to know this screen's internal widget layout.
func get_current_spec() -> Dictionary:
	var nature: int = _nature_option.get_selected_id()
	var ability_slot: int = _ability_option.get_selected_id() if _ability_option.item_count > 0 else PokemonFactory.ABILITY_SLOT_PRIMARY

	var evs: Array = []
	for sb in _ev_spinboxes:
		evs.append(int(sb.value))
	var ivs: Array = []
	for sb in _iv_spinboxes:
		ivs.append(int(sb.value))

	return {
		"dex": _current_dex,
		"level": _current_level,
		"move_ids": _selected_move_ids.duplicate(),
		"nature": nature,
		"evs": evs,
		"ivs": ivs,
		"ability_slot": ability_slot,
	}


func _on_build_pressed() -> void:
	if _current_dex < 0:
		_status_label.text = "Load a species before building."
		return

	var spec := get_current_spec()
	var bp := PokemonFactory.create_battle_pokemon(
			spec["dex"], spec["level"], spec["move_ids"],
			spec["nature"], spec["ivs"], null, spec["evs"], spec["ability_slot"])

	if bp == null:
		_status_label.text = "Build failed — no species data for dex #%d." % _current_dex
		return

	_built_pokemon = bp
	_status_label.text = "Built %s! (see result below)" % bp.species.species_name
	_render_result(bp)
	pokemon_built.emit(spec, bp)


func _render_result(bp: BattlePokemon) -> void:
	var lines: Array[String] = []
	lines.append("[b]%s[/b] (Lv. %d, %s)" % [bp.species.species_name, bp.level, _NATURE_NAMES[bp.nature]])
	lines.append("Ability: %s" % (bp.ability.ability_name if bp.ability != null else "None"))
	lines.append("HP: %d/%d   Atk: %d   Def: %d   SpAtk: %d   SpDef: %d   Speed: %d" % [
		bp.current_hp, bp.max_hp, bp.attack, bp.defense, bp.sp_attack, bp.sp_defense, bp.speed])

	var ev_parts: Array[String] = []
	var iv_parts: Array[String] = []
	for i in range(6):
		ev_parts.append("%s %d" % [_EV_STAT_NAMES[i], bp.evs[i]])
		iv_parts.append("%s %d" % [_EV_STAT_NAMES[i], bp.ivs[i]])
	lines.append("EVs: " + ", ".join(ev_parts))
	lines.append("IVs: " + ", ".join(iv_parts))

	var move_parts: Array[String] = []
	for i in range(bp.moves.size()):
		var move: MoveData = bp.moves[i]
		if move != null:
			move_parts.append("%s (PP %d/%d)" % [move.move_name, bp.current_pp[i], move.pp])
	lines.append("Moves: " + (", ".join(move_parts) if not move_parts.is_empty() else "(none)"))

	_result_label.text = "\n".join(lines)
