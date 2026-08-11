extends Node

# [M26c-1] Regression suite for the HP/name/level "databox" swap to the
# Emerald UI Pack's own real art (Graphics/UI/Battle/databox_*.png),
# superseding Phase 4b's raw-pokeemerald-decode health-box art, plus the
# new real EXP bar this session adds (singles player only, matching the
# pack's own real scope — see gen_databox_sprites.py's own doc comment).
#
# [Deliberately NOT tested here] Pixel-perfect internal layout (HP-bar/
# name/EXP-tab offsets within each box) — those were measured directly via
# PIL pixel inspection during this session's own Step 0 and are verified
# visually via the mandated real screenshot pass instead, matching this
# project's own established "measure roughly, verify visually, adjust only
# if proven necessary" convention (see e.g. M25h-1's own D1-clearance
# precedent).

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_databox_asset_dimensions()
	_test_hp_bar_color_real_sourced_values()
	_test_exp_bar_color_real_sourced_value()
	_test_exp_bar_fraction_unknown_species_returns_zero()
	_test_exp_bar_fraction_level_100_returns_zero()
	_test_exp_bar_fraction_real_species_midpoint()
	_test_exp_bar_fraction_real_species_at_threshold()
	_test_exp_bar_fraction_clamped_non_negative()
	_test_exp_to_next_unknown_species_returns_zero()
	_test_exp_to_next_level_100_returns_zero()
	_test_exp_to_next_real_species_exact_value()
	_test_exp_to_next_real_species_at_threshold()
	_test_real_scene_structure()
	_test_status_icon_default_preview_texture()
	_test_split_name_level_labels_exist()
	# [Healthbox geometry, live-reported] Table-vs-source, then scene-vs-table.
	_test_healthbox_table_matches_source_arithmetic()
	_test_panels_match_the_generated_healthbox_table()
	_test_level_labels_match_sources_own_fixed_right_edge()

	var total := _pass + _fail
	print("m26c1_databox_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


# ── 1. Real pack asset dimensions ────────────────────────────────────────

func _test_databox_asset_dimensions() -> void:
	var player: Texture2D = load("res://assets/sprites/battle_ui/interface/databox_player.png")
	var opponent: Texture2D = load("res://assets/sprites/battle_ui/interface/databox_opponent.png")
	var d_player: Texture2D = load("res://assets/sprites/battle_ui/interface/databox_doubles_player.png")
	var d_opponent: Texture2D = load("res://assets/sprites/battle_ui/interface/databox_doubles_opponent.png")
	_chk("databox_player.png loads", player != null)
	_chk("databox_opponent.png loads", opponent != null)
	_chk("databox_doubles_player.png loads", d_player != null)
	_chk("databox_doubles_opponent.png loads", d_opponent != null)
	if player != null:
		_chk("player box is 260x84 (the taller box, with the EXP ledge)",
				player.get_width() == 260 and player.get_height() == 84)
	if opponent != null:
		_chk("opponent box is 260x62 (no EXP ledge)",
				opponent.get_width() == 260 and opponent.get_height() == 62)
	if d_player != null:
		_chk("doubles player box is 260x62", d_player.get_width() == 260 and d_player.get_height() == 62)
	if d_opponent != null:
		_chk("doubles opponent box is 260x62", d_opponent.get_width() == 260 and d_opponent.get_height() == 62)


# ── 2. HP bar color thresholds — real sourced values, not invented ──────

func _test_hp_bar_color_real_sourced_values() -> void:
	var bs := BattleScreenShared.new()
	_chk(">50% HP uses the pack's real green highlight (115,255,173)",
			bs._hp_bar_color(51, 100) == Color8(115, 255, 173))
	_chk(">20% (and <=50%) HP uses the pack's real yellow highlight (255,231,57)",
			bs._hp_bar_color(21, 100) == Color8(255, 231, 57))
	_chk("<=20% HP uses the pack's real red highlight (255,90,57)",
			bs._hp_bar_color(20, 100) == Color8(255, 90, 57))
	_chk("max_hp<=0 degrades safely to plain white, not a crash",
			bs._hp_bar_color(0, 0) == Color(1, 1, 1))


# ── 3. EXP bar color — real sourced value ────────────────────────────────

func _test_exp_bar_color_real_sourced_value() -> void:
	# [Doubles-split roadmap, step 6] _EXP_BAR_COLOR moved from
	# BattleScreen(Shared) to HealthGroupPanel in step 5's dead-code cleanup
	# -- the fill-bar setup itself now lives entirely inside the panel
	# component, not the parent screen script.
	_chk("EXP bar tint matches the pack's own real overlay_exp.png color",
			HealthGroupPanel._EXP_BAR_COLOR == Color8(66, 206, 255))


# ── 4-8. _exp_bar_fraction ────────────────────────────────────────────────

func _test_exp_bar_fraction_unknown_species_returns_zero() -> void:
	var bs := BattleScreenShared.new()
	var sp := PokemonSpecies.new()
	sp.species_name = "Fixture"
	sp.types.append(TypeChart.TYPE_NORMAL)
	sp.base_hp = 100
	sp.base_attack = 80
	sp.base_defense = 80
	sp.base_sp_attack = 80
	sp.base_sp_defense = 80
	sp.base_speed = 80
	var mon := BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])
	# national_dex_num defaults to 0 -- no real PokemonRegistry entry exists,
	# matching this screen's own hand-built fixture teams exactly.
	_chk("a hand-built fixture mon (dex 0, no real growth-rate data) degrades to an empty bar, not a crash",
			bs._exp_bar_fraction(mon) == 0.0)


func _test_exp_bar_fraction_level_100_returns_zero() -> void:
	var bs := BattleScreenShared.new()
	var mon: BattlePokemon = PokemonFactory.create_battle_pokemon(1, 100)  # Bulbasaur
	_chk("a level-100 mon (nothing left to progress toward) returns an empty bar",
			bs._exp_bar_fraction(mon) == 0.0)


func _test_exp_bar_fraction_real_species_midpoint() -> void:
	var bs := BattleScreenShared.new()
	var mon: BattlePokemon = PokemonFactory.create_battle_pokemon(1, 10)  # Bulbasaur, real growth-rate data
	var species_data: Dictionary = PokemonRegistry.get_species(1)
	var growth_rate: String = species_data.get("growth_rate", "")
	var exp_this: int = PokemonRegistry.get_exp_for_level(growth_rate, 10)
	var exp_next: int = PokemonRegistry.get_exp_for_level(growth_rate, 11)
	mon.current_exp = exp_this + (exp_next - exp_this) / 2
	var frac := bs._exp_bar_fraction(mon)
	_chk("a real registry-backed mon exactly halfway to its next level reports ~0.5",
			is_equal_approx(frac, 0.5) or absf(frac - 0.5) < 0.05)


func _test_exp_bar_fraction_real_species_at_threshold() -> void:
	var bs := BattleScreenShared.new()
	var mon: BattlePokemon = PokemonFactory.create_battle_pokemon(1, 10)
	var species_data: Dictionary = PokemonRegistry.get_species(1)
	var growth_rate: String = species_data.get("growth_rate", "")
	mon.current_exp = PokemonRegistry.get_exp_for_level(growth_rate, 10)
	_chk("a mon sitting exactly at its own current level's threshold reports an empty bar",
			bs._exp_bar_fraction(mon) == 0.0)


func _test_exp_bar_fraction_clamped_non_negative() -> void:
	var bs := BattleScreenShared.new()
	var mon: BattlePokemon = PokemonFactory.create_battle_pokemon(1, 10)
	# A deliberately-out-of-normal-range value (current_exp below this
	# level's own threshold) -- shouldn't happen in real gameplay, but the
	# function must degrade safely (clamp to 0.0), not return a negative
	# fraction that would visually invert the bar.
	mon.current_exp = 0
	var frac := bs._exp_bar_fraction(mon)
	_chk("an out-of-range current_exp clamps to a non-negative fraction", frac >= 0.0)


# ── [M26E4-1] _exp_to_next — the "EXP points / NEXT LV." derivation ───────

func _test_exp_to_next_unknown_species_returns_zero() -> void:
	var bs := BattleScreenShared.new()
	var sp := PokemonSpecies.new()
	sp.species_name = "Fixture"
	sp.types.append(TypeChart.TYPE_NORMAL)
	sp.base_hp = 100
	sp.base_attack = 80
	sp.base_defense = 80
	sp.base_sp_attack = 80
	sp.base_sp_defense = 80
	sp.base_speed = 80
	var mon := BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])
	_chk("a hand-built fixture mon (dex 0, no real growth-rate data) degrades to 0, not a crash",
			bs._exp_to_next(mon) == 0)


func _test_exp_to_next_level_100_returns_zero() -> void:
	var bs := BattleScreenShared.new()
	var mon: BattlePokemon = PokemonFactory.create_battle_pokemon(1, 100)  # Bulbasaur
	_chk("a level-100 mon (nothing left to progress toward) returns 0",
			bs._exp_to_next(mon) == 0)


func _test_exp_to_next_real_species_exact_value() -> void:
	var bs := BattleScreenShared.new()
	var mon: BattlePokemon = PokemonFactory.create_battle_pokemon(1, 10)  # Bulbasaur, real growth-rate data
	var species_data: Dictionary = PokemonRegistry.get_species(1)
	var growth_rate: String = species_data.get("growth_rate", "")
	var exp_next: int = PokemonRegistry.get_exp_for_level(growth_rate, 11)
	mon.current_exp = exp_next - 37
	_chk("exp_to_next reports exactly source's own table[level+1] - exp",
			bs._exp_to_next(mon) == 37)


func _test_exp_to_next_real_species_at_threshold() -> void:
	var bs := BattleScreenShared.new()
	var mon: BattlePokemon = PokemonFactory.create_battle_pokemon(1, 10)
	var species_data: Dictionary = PokemonRegistry.get_species(1)
	var growth_rate: String = species_data.get("growth_rate", "")
	mon.current_exp = PokemonRegistry.get_exp_for_level(growth_rate, 11)
	_chk("a mon sitting exactly at its own next-level threshold reports 0 remaining",
			bs._exp_to_next(mon) == 0)


# ── 9-11. [Doubles-split roadmap, step 6] Retargeted from the old
# monolithic battle_screen.tscn (which combined singles OpponentHealthGroup/
# PlayerHealthGroup and doubles ...D0/...D1 groups behind an _is_doubles_mode
# flag) to the two real production scenes that replaced it,
# battle_screen_singles.tscn/battle_screen_doubles.tscn — each now instances
# a real, reusable HealthGroupPanel component (OpponentPanel0/PlayerPanel0
# in singles; OpponentPanel0/1/PlayerPanel0/1 in doubles) rather than
# inlining raw Background/NameLabel/StatusIcon/etc. nodes directly under
# battle_screen.gd itself.
#
# [Deliberately NOT re-tested here] The panel's own internal structure,
# _ready()-driven asset wiring (databox texture, status-icon default
# preview, EXP-fill color/range, font application), and refresh() behavior
# — health_group_panel_test.gd already covers all four panel variants for
# exactly this, and PackedScene.instantiate() without add_child() (required
# here per every other test in this file's own established --autoplay-race
# precedent) never fires NOTIFICATION_READY anyway, so HealthGroupPanel's
# own _ready() wiring couldn't be observed at this level even if re-tested.
# What IS unique to this level, and worth checking here: that each
# production scene instances the CORRECT panel template at the right node
# path (not the singles template pasted into the doubles scene or vice
# versa), that the ExpFill/no-ExpFill split lands on the right nodes in
# each real scene, and that BattleScreenShared._setup_health_ui() (the
# generic slot-probing loop that replaced the old per-field @onready
# wiring) discovers the correct number of panels per side for each format.

func _test_real_scene_structure() -> void:
	# [Established precedent — see m25b_menu_test.gd/phase4d_doubles_visual_
	# test.gd/phase4e_message_box_test.gd's own doc comments] Deliberately
	# NOT add_child()-ing either instantiated scene: count_assertions.sh
	# appends --autoplay process-wide, and battle_screen_shared.gd's own
	# _ready() ends by calling _run_autoplay() -> get_tree().quit() once a
	# real BattleManager child actually starts advancing — entering the
	# live tree here would race and kill this whole test process.
	# instantiate() DOES fully build the real node subtree (every child
	# node genuinely exists, including each panel's own static ExpFill
	# child where the .tscn declares one), it just never fires
	# NOTIFICATION_READY.
	var singles_scene: PackedScene = load("res://scenes/battle/battle_screen_singles.tscn")
	var singles: Node = singles_scene.instantiate()
	var doubles_scene: PackedScene = load("res://scenes/battle/battle_screen_doubles.tscn")
	var doubles: Node = doubles_scene.instantiate()

	_chk("singles OpponentPanel0 exists and is a real HealthGroupPanel",
			singles.has_node("BattleStage/OpponentPanel0")
			and singles.get_node("BattleStage/OpponentPanel0") is HealthGroupPanel)
	_chk("singles PlayerPanel0 exists and is a real HealthGroupPanel",
			singles.has_node("BattleStage/PlayerPanel0")
			and singles.get_node("BattleStage/PlayerPanel0") is HealthGroupPanel)
	for path in ["BattleStage/OpponentPanel0", "BattleStage/PlayerPanel0",
			"BattleStage/OpponentPanel1", "BattleStage/PlayerPanel1"]:
		_chk("doubles %s exists and is a real HealthGroupPanel" % path,
				doubles.has_node(path) and doubles.get_node(path) is HealthGroupPanel)

	_chk("singles PlayerPanel0 has a real ExpFill node",
			singles.has_node("BattleStage/PlayerPanel0/ExpFill"))
	_chk("singles OpponentPanel0 has NO ExpFill node (opponent mons never show an EXP bar)",
			not singles.has_node("BattleStage/OpponentPanel0/ExpFill"))
	for path in ["BattleStage/OpponentPanel0/ExpFill", "BattleStage/OpponentPanel1/ExpFill",
			"BattleStage/PlayerPanel0/ExpFill", "BattleStage/PlayerPanel1/ExpFill"]:
		_chk("doubles %s does NOT exist (no EXP bar in doubles at all)" % path,
				not doubles.has_node(path))

	# _setup_health_ui() is pure has_node()/get_node() slot-probing -- no
	# dependency on the panels' own _ready() having fired, safe to call
	# directly on these instantiated-but-not-tree-entered instances.
	singles._setup_health_ui()
	doubles._setup_health_ui()
	_chk("singles _setup_health_ui() discovers exactly 1 opponent panel",
			singles._opp_panels.size() == 1)
	_chk("singles _setup_health_ui() discovers exactly 1 player panel",
			singles._ply_panels.size() == 1)
	_chk("doubles _setup_health_ui() discovers exactly 2 opponent panels",
			doubles._opp_panels.size() == 2)
	_chk("doubles _setup_health_ui() discovers exactly 2 player panels",
			doubles._ply_panels.size() == 2)
	_chk("singles is not mistaken for doubles (_is_doubles() reads panel count, not a stored flag)",
			not singles._is_doubles())
	_chk("doubles is genuinely recognized as doubles",
			doubles._is_doubles())

	singles.queue_free()
	doubles.queue_free()


func _test_status_icon_default_preview_texture() -> void:
	# [Doubles-split roadmap, step 6] Each StatusIcon's own real
	# AtlasTexture-sourced-from-status.png/status2.png default preview is
	# now set once, inside the shared health_group_panel*.tscn templates
	# themselves (already covered per-variant by
	# health_group_panel_test.gd's own _test_ready_wires_default_databox_and_status
	# and its doubles-variant equivalent) -- confirmed here only at the
	# level unique to this file: that both real production scenes actually
	# instance those templates (not a stripped-down or stubbed copy) by
	# checking the StatusIcon node genuinely exists inside each real
	# instanced panel.
	var singles_scene: PackedScene = load("res://scenes/battle/battle_screen_singles.tscn")
	var singles: Node = singles_scene.instantiate()
	var doubles_scene: PackedScene = load("res://scenes/battle/battle_screen_doubles.tscn")
	var doubles: Node = doubles_scene.instantiate()

	for path in ["BattleStage/OpponentPanel0/StatusIcon", "BattleStage/PlayerPanel0/StatusIcon"]:
		_chk("singles %s exists" % path, singles.has_node(path))
	for path in ["BattleStage/OpponentPanel0/StatusIcon", "BattleStage/OpponentPanel1/StatusIcon",
			"BattleStage/PlayerPanel0/StatusIcon", "BattleStage/PlayerPanel1/StatusIcon"]:
		_chk("doubles %s exists" % path, doubles.has_node(path))

	singles.queue_free()
	doubles.queue_free()


func _test_split_name_level_labels_exist() -> void:
	# [Doubles-split roadmap, step 6] Same reasoning as the test above --
	# the NameLabel/LevelLabel split itself (and the old combined
	# NameLevelLabel node's absence) is already covered per-variant by
	# health_group_panel_test.gd; this confirms only that both real
	# production scenes instance panels carrying these real child nodes.
	var singles_scene: PackedScene = load("res://scenes/battle/battle_screen_singles.tscn")
	var singles: Node = singles_scene.instantiate()
	var doubles_scene: PackedScene = load("res://scenes/battle/battle_screen_doubles.tscn")
	var doubles: Node = doubles_scene.instantiate()

	var singles_groups := ["BattleStage/OpponentPanel0", "BattleStage/PlayerPanel0"]
	var doubles_groups := ["BattleStage/OpponentPanel0", "BattleStage/OpponentPanel1",
			"BattleStage/PlayerPanel0", "BattleStage/PlayerPanel1"]
	for group_path in singles_groups:
		_chk("singles %s/NameLabel exists" % group_path,
				singles.has_node(group_path + "/NameLabel"))
		_chk("singles %s/LevelLabel exists" % group_path,
				singles.has_node(group_path + "/LevelLabel"))
		_chk("singles %s/NameLevelLabel (the old combined node) no longer exists" % group_path,
				not singles.has_node(group_path + "/NameLevelLabel"))
	for group_path in doubles_groups:
		_chk("doubles %s/NameLabel exists" % group_path,
				doubles.has_node(group_path + "/NameLabel"))
		_chk("doubles %s/LevelLabel exists" % group_path,
				doubles.has_node(group_path + "/LevelLabel"))
		_chk("doubles %s/NameLevelLabel (the old combined node) no longer exists" % group_path,
				not doubles.has_node(group_path + "/NameLevelLabel"))

	singles.queue_free()
	doubles.queue_free()


# ── Healthbox geometry (scene vs the generated table) ────────────────────
#
# Reported from play: "the pokemon lv for the opponent clips into the right
# edge of the hp background. Can you resize the entire player panel and
# opponent panel to align with source scaled to our resolution."
#
# ⚠️ **THE SUBJECT HERE IS DRIFT, NOT PLACEMENT** -- the same reasoning
# `m26a1_battler_geometry_test` records for the battler sprites, and it
# applies harder to these six nodes, because this project has already lost a
# health-group node to a stray editor drag once (see
# `m25h1_bottom_region_test`'s own section 9 for that history). Getting six
# panels right is a generator run; keeping them right is this.
#
# Every assertion compares the SCENE against `HealthboxCoords`, which is the
# only pairing an editor drag can break. A number frozen here instead would
# just be hand-tuning one level removed.

const _PANEL_NODES := {
	"res://scenes/battle/battle_screen_singles.tscn": {
		"PlayerPanel0": "B_POSITION_PLAYER_LEFT",
		"OpponentPanel0": "B_POSITION_OPPONENT_LEFT",
	},
	"res://scenes/battle/battle_screen_doubles.tscn": {
		"PlayerPanel0": "B_POSITION_PLAYER_LEFT",
		"PlayerPanel1": "B_POSITION_PLAYER_RIGHT",
		"OpponentPanel0": "B_POSITION_OPPONENT_LEFT",
		"OpponentPanel1": "B_POSITION_OPPONENT_RIGHT",
	},
}


func _test_panels_match_the_generated_healthbox_table() -> void:
	var vw: float = float(ProjectSettings.get_setting(
			"display/window/size/viewport_width", 1200))
	var vh: float = float(ProjectSettings.get_setting(
			"display/window/size/viewport_height", 800))
	# ⚠️ Asserted, not assumed. The whole table is only arithmetic while the
	# canvas is a uniform GBA multiple; the generator refuses to run otherwise,
	# and this is the runtime half of that same check.
	var sx: float = vw / HealthboxCoords.GBA_SCREEN.x
	var sy: float = vh / HealthboxCoords.GBA_SCREEN.y
	_chk("the canvas is still a uniform GBA multiple, so the table is still arithmetic",
			is_equal_approx(sx, sy))

	for scene_path: String in _PANEL_NODES:
		var mode: Dictionary = HealthboxCoords.DOUBLES if "doubles" in scene_path \
				else HealthboxCoords.SINGLES
		var instance: Node = (load(scene_path) as PackedScene).instantiate()
		for node_name: String in _PANEL_NODES[scene_path]:
			var pos_key: String = _PANEL_NODES[scene_path][node_name]
			var panel: Control = instance.get_node("BattleStage/" + node_name)
			var want: Vector2 = HealthboxCoords.anchor_for(mode, pos_key)
			var tag: String = scene_path.get_file().trim_suffix(".tscn") + "/" + node_name
			# A POINT anchor: left == right and top == bottom. Godot's own
			# inspector will silently turn this into a stretched anchor if a
			# preset is applied, which changes what the offsets even mean.
			_chk("%s is a point anchor" % tag,
					is_equal_approx(panel.anchor_left, panel.anchor_right)
					and is_equal_approx(panel.anchor_top, panel.anchor_bottom))
			_chk("%s sits at the table's own anchor" % tag,
					abs(panel.anchor_left - want.x) < 0.0001
					and abs(panel.anchor_top - want.y) < 0.0001)
			# The art's WIDTH is what the generator matches exactly; height is
			# a disclosed consequence of the pack art's own aspect, so it is
			# deliberately NOT asserted against source here.
			var bg: TextureRect = panel.get_node("Background")
			var drawn_w: float = bg.size.x * panel.scale.x
			var want_w: float = HealthboxCoords.rect_for(mode, pos_key, sx).size.x
			_chk("%s draws its art at source's own width, scaled" % tag,
					abs(drawn_w - want_w) < 0.5)
			# ⚠️ **THE RECT'S SIZE IS ASSERTED, ITS ORIGIN DELIBERATELY IS NOT,
			# AND THE DIFFERENCE IS A REAL LIMITATION RATHER THAN AN OVERSIGHT.**
			# `_health_group_for()` hands this node to TARGET_SELECT as the
			# click/hover zone, so the rect wants to match the art. The SIZE now
			# does (it was 179x45 against art drawing 416x99 before this). The
			# ORIGIN cannot, while the four panel scenes lay their Background out
			# at a non-zero local offset -- the node origin has to sit where the
			# CHILD needs it, and for the singles panels that is 127px left / 88px
			# right of the art. Normalising each panel's Background to local (0,0)
			# would close it, and is not this change.
			_chk("%s's own rect is the size of the art it draws" % tag,
					abs(panel.size.x * panel.scale.x - drawn_w) < 0.5)
		instance.queue_free()


func _test_level_labels_match_sources_own_fixed_right_edge() -> void:
	# `UpdateLvlInHealthbox` (`battle_interface.c:862`) prints the level at
	# `32 - width` on the player side and `24 - width` on the opponent's --
	# a FIXED right edge minus the text's own width, into the second of the
	# healthbox's two 64-wide sprites.
	#
	# ⚠️ THE TWO SIDES DIFFER BY 8 GBA px AND THAT DIFFERENCE IS THE REPORTED
	# BUG. Both panels having "a right edge" is not enough; the opponent's has
	# to be the NEARER one, or the level runs into its own frame.
	var singles_ply: Control = (load(
			"res://scenes/battle/health_group_panel_player.tscn") as PackedScene).instantiate()
	var singles_opp: Control = (load(
			"res://scenes/battle/health_group_panel.tscn") as PackedScene).instantiate()
	for panel: Control in [singles_ply, singles_opp]:
		var lvl: Label = panel.get_node("LevelLabel")
		# The rule only means anything for a right-aligned label.
		_chk("%s's level label is right-aligned" % panel.name,
				lvl.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT)

	# Expressed as a fraction of each box's own width, which is the part that
	# transfers between source's art and this project's differently-shaped
	# redraw of it.
	var ply_bg: TextureRect = singles_ply.get_node("Background")
	var opp_bg: TextureRect = singles_opp.get_node("Background")
	var ply_lvl: Label = singles_ply.get_node("LevelLabel")
	var opp_lvl: Label = singles_opp.get_node("LevelLabel")
	var ply_frac: float = (ply_lvl.offset_right - ply_bg.offset_left) / ply_bg.size.x
	var opp_frac: float = (opp_lvl.offset_right - opp_bg.offset_left) / opp_bg.size.x
	_chk("the player's level edge is source's own 32-in-sprite-2 (92.2% of the box)",
			abs(ply_frac - 0.92233) < 0.002)
	_chk("the opponent's is source's own 24-in-sprite-2 (87.0% of the box)",
			abs(opp_frac - 0.87) < 0.002)
	_chk("...so the opponent's level sits FURTHER IN than the player's, which is the reported clip",
			opp_frac < ply_frac)
	# It must also actually be inside the art it is drawn over. The old
	# authored value put it at 94.2% of a box whose own frame ends sooner.
	_chk("the opponent's level edge is inside its own box",
			opp_lvl.offset_right < opp_bg.offset_left + opp_bg.size.x)

	singles_ply.queue_free()
	singles_opp.queue_free()


# ⚠️ **THIS EXISTS BECAUSE THE SCENE-VS-TABLE CHECK BELOW IS VACUOUS ON ITS
# OWN, AND ONLY AN INJECTION SHOWED IT.** `gen_healthbox_coords.py` writes the
# table AND the scenes from one computation, so if that computation is wrong
# the two still agree perfectly. Breaking the generator's footprint maths --
# `centre.x - SPRITE_W` instead of `- SPRITE_W / 2`, which moves every box 160
# real px left -- left all six of those assertions GREEN.
#
# So this one pins the TABLE against source's own numbers, transcribed by hand
# rather than re-derived, which is the only form that can disagree with the
# generator at all:
#
#   sBattlerHealthboxCoords (`battle_interface.c:829`) -- the CENTRE of the
#   LEFT of two 64-wide sprites -- minus half ONE sprite, plus the art's own
#   measured inset inside its OAM sheet (1, 2 on all four sheets).
#
#   singles  PLAYER   (158, 88) 64x64 -> foot (126, 56) -> art (127, 58) 103x36
#   singles  OPPONENT ( 44, 30) 64x32 -> foot ( 12, 14) -> art ( 13, 16) 100x28
#   doubles  PLAYER_L (159, 76) 64x32 -> foot (127, 60) -> art (128, 62) 100x25
#   doubles  PLAYER_R (171,101) 64x32 -> foot (139, 85) -> art (140, 87) 100x25
#   doubles  OPP_L    ( 44, 19) 64x32 -> foot ( 12,  3) -> art ( 13,  5) 100x25
#   doubles  OPP_R    ( 32, 44) 64x32 -> foot (  0, 28) -> art (  1, 30) 100x25
#
# The 64-vs-32 height split is not a typo: only the singles player box gets
# `oam.shape = ST_OAM_SQUARE`, which at that size bit is 64x64.
func _test_healthbox_table_matches_source_arithmetic() -> void:
	var want_singles := {
		"B_POSITION_PLAYER_LEFT": Rect2(127, 58, 103, 36),
		"B_POSITION_OPPONENT_LEFT": Rect2(13, 16, 100, 28),
	}
	var want_doubles := {
		"B_POSITION_PLAYER_LEFT": Rect2(128, 62, 100, 25),
		"B_POSITION_PLAYER_RIGHT": Rect2(140, 87, 100, 25),
		"B_POSITION_OPPONENT_LEFT": Rect2(13, 5, 100, 25),
		"B_POSITION_OPPONENT_RIGHT": Rect2(1, 30, 100, 25),
	}
	for pair: Array in [[want_singles, HealthboxCoords.SINGLES, "singles"],
			[want_doubles, HealthboxCoords.DOUBLES, "doubles"]]:
		var want: Dictionary = pair[0]
		var got: Dictionary = pair[1]
		_chk("%s table has exactly the four source positions" % pair[2],
				got.size() == 4 or (pair[2] == "singles" and got.size() == 2))
		for key: String in want:
			_chk("%s %s is source's own rect" % [pair[2], key],
					got.get(key, Rect2()) == want[key])
