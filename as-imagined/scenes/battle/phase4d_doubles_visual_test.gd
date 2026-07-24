extends Node

# [M23.11 Phase 4d] Test suite for the doubles visual layer added to
# battle_screen.gd/.tscn — 2 sprite/health-box groups per side, using the
# healthbox_doubles_* art.
#
# [Deliberately NOT tested here] Instantiating battle_screen.tscn itself —
# same established precedent as phase4f_targeting_test.gd (see that file's
# own doc comment): count_assertions.sh appends --autoplay to every scene
# invocation process-wide, and battle_screen.gd's _ready() checks
# OS.get_cmdline_args() globally, so embedding battle_screen.tscn as a
# child here would trigger _run_autoplay()'s get_tree().quit() and kill
# this whole process. Every function this suite exercises
# (_refresh_doubles_side, the doubles branch of
# _on_opponent_anim_timer_timeout, the doubles-node arrays built by
# _setup_health_ui/_collect_doubles_nodes) is called directly on a bare
# `BattleScreen.new()` instance that is NEVER added to the scene tree —
# its @onready vars (which need $BattleStage/... child nodes from the real
# .tscn) are therefore never touched by anything this suite calls, since
# _refresh_doubles_side/_on_opponent_anim_timer_timeout only read/write
# the plain instance fields and the node arguments passed in directly.
# The genuine end-to-end proof (real .tscn, real _ready(), real doubles
# battle) is the mandated real screenshot verification instead.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_doubles_art_dimensions()
	_test_refresh_doubles_side_basic_render()
	_test_refresh_doubles_side_independent_fade_and_status()
	_test_refresh_doubles_side_singles_shaped_party_hides_slot1()
	_test_anim_timer_doubles_independence()
	_test_singles_regression_helpers_unchanged()

	var total := _pass + _fail
	print("phase4d_doubles_visual_test: %d/%d passed" % [_pass, total])
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

static func _make_mon(mon_name: String, hp: int = 100) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types.append(TypeChart.TYPE_NORMAL)
	sp.base_hp = hp
	sp.base_attack = 80
	sp.base_defense = 80
	sp.base_sp_attack = 80
	sp.base_sp_defense = 80
	sp.base_speed = 80
	var mon := BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])
	# [M26c-1 follow-up] from_species() always rolls a real gender from the
	# class-default gender_ratio (~50/50) -- forced deterministic since
	# _name_text() now renders a trailing gender glyph and this suite's own
	# new name/level assertions need a stable expected string.
	mon.gender = BattlePokemon.GENDER_MALE
	return mon


static func _make_party(mons: Array, active: Array) -> BattleParty:
	var p := BattleParty.new()
	var typed_mons: Array[BattlePokemon] = []
	for m: BattlePokemon in mons:
		typed_mons.append(m)
	p.members = typed_mons
	var typed_active: Array[int] = []
	for i: int in active:
		typed_active.append(i)
	p.active_indices = typed_active
	return p


func _make_node_set() -> Dictionary:
	# [M26c battle-UI polish] Sprite nodes need a real, nonzero
	# offset_left/offset_right (a fake "authored" 64x64 box, matching the
	# real .tscn nodes' own square-box convention) -- width :=
	# offset_right - offset_left feeds _apply_bottom_anchored_front_sprite's
	# own scale computation, which early-returns (leaving .texture untouched)
	# for a zero-width box. offset_top/offset_bottom are likewise given a
	# real starting baseline (0..64) since callers now pass these as the
	# fixed "base_top"/"base_bottom" pair via BASE_TOP/BASE_BOTTOM below.
	var sprite0 := TextureRect.new()
	var sprite1 := TextureRect.new()
	for s in [sprite0, sprite1]:
		s.offset_left = 0.0
		s.offset_right = 64.0
		s.offset_top = 0.0
		s.offset_bottom = 64.0
	return {
		"sprites": [sprite0, sprite1],
		"groups": [Control.new(), Control.new()],
		"status_icons": [TextureRect.new(), TextureRect.new()],
		"status_atlases": [AtlasTexture.new(), AtlasTexture.new()],
		"hp_fills": [TextureProgressBar.new(), TextureProgressBar.new()],
		"name_labels": [Label.new(), Label.new()],  # [M25d, split M26c-1 follow-up]
		"level_labels": [Label.new(), Label.new()],  # [M25d, split M26c-1 follow-up]
	}


# [M26c battle-UI polish] Matches _make_node_set()'s own fake 64x64 sprite
# box baseline above -- passed as the new sprite_base_top/sprite_base_bottom
# params on every _refresh_doubles_side(..., is_player=false) call site
# below, mirroring how battle_screen.gd's own _setup_health_ui() captures
# the real .tscn nodes' baseline once before any mutation.
const _SPRITE_BASE_TOP := [0.0, 0.0]
const _SPRITE_BASE_BOTTOM := [64.0, 64.0]


# ── A. Doubles databox art — dimensions confirmed via direct load, not
# assumed from the earlier manual PIL inspection alone.
# [M26c-1] Retargeted to the real files _setup_health_ui() actually loads
# now (the Emerald UI Pack's own "thin" doubles boxes) — the old
# healthbox_doubles_*.png files are no longer referenced anywhere in
# battle_screen.gd, so asserting against them here would silently stop
# testing what's actually on screen. ────────────────────────────────────

func _test_doubles_art_dimensions() -> void:
	var opp_tex: Texture2D = load("res://assets/sprites/battle_ui/interface/databox_doubles_opponent.png")
	var ply_tex: Texture2D = load("res://assets/sprites/battle_ui/interface/databox_doubles_player.png")
	_chk("doubles opponent art loads", opp_tex != null)
	_chk("doubles player art loads", ply_tex != null)
	if opp_tex != null:
		_chk("doubles opponent art is 260x62", opp_tex.get_width() == 260 and opp_tex.get_height() == 62)
	if ply_tex != null:
		_chk("doubles player art is 260x62", ply_tex.get_width() == 260 and ply_tex.get_height() == 62)


# ── B. _refresh_doubles_side basic two-slot render ──────────────────────

func _test_refresh_doubles_side_basic_render() -> void:
	var bs := BattleScreen.new()
	var mon0 := _make_mon("Alpha", 100)
	var mon1 := _make_mon("Beta", 100)
	var party := _make_party([mon0, mon1, _make_mon("Bench", 100)], [0, 1])

	var nodes := _make_node_set()
	bs._refresh_doubles_side(party, false, nodes["sprites"], nodes["groups"],
			nodes["status_icons"], nodes["status_atlases"], nodes["hp_fills"],
			nodes["name_labels"], nodes["level_labels"],
			_SPRITE_BASE_TOP, _SPRITE_BASE_BOTTOM)

	_chk("slot 0 sprite visible", nodes["sprites"][0].visible)
	_chk("slot 1 sprite visible", nodes["sprites"][1].visible)
	_chk("slot 0 group visible", nodes["groups"][0].visible)
	_chk("slot 1 group visible", nodes["groups"][1].visible)
	# [M26c-1 follow-up] Split label wiring — name and level are set
	# independently (name gets the trailing gender glyph, level does not).
	_chk("slot 0 name label set independently of level label",
			nodes["name_labels"][0].text == bs._name_text(mon0))
	_chk("slot 1 name label set independently of level label",
			nodes["name_labels"][1].text == bs._name_text(mon1))
	_chk("slot 0 level label set independently of name label",
			nodes["level_labels"][0].text == bs._level_text(mon0))
	_chk("slot 1 level label set independently of name label",
			nodes["level_labels"][1].text == bs._level_text(mon1))
	# [from_species HP formula] max_hp is computed from base_hp/level/IVs, not
	# equal to the raw base_hp passed to _make_mon — checked against each
	# mon's own real .max_hp/.current_hp rather than a hardcoded 100.
	_chk("slot 0 hp_fill max/value set", nodes["hp_fills"][0].max_value == mon0.max_hp and nodes["hp_fills"][0].value == mon0.current_hp)
	_chk("slot 1 hp_fill max/value set", nodes["hp_fills"][1].max_value == mon1.max_hp and nodes["hp_fills"][1].value == mon1.current_hp)
	_chk("slot 0 sprite texture assigned", nodes["sprites"][0].texture != null)
	_chk("slot 1 sprite texture assigned", nodes["sprites"][1].texture != null)


# ── C. Independence — one Pokémon fainting/statused must not affect its
# teammate's own fade/status/HP-color display. This is the key regression
# risk this phase's own task explicitly called out. ────────────────────────

func _test_refresh_doubles_side_independent_fade_and_status() -> void:
	var bs := BattleScreen.new()
	var healthy := _make_mon("Healthy", 100)
	healthy.current_hp = 100
	var fainted := _make_mon("Fainted", 100)
	fainted.current_hp = 0
	fainted.fainted = true
	fainted.status = BattlePokemon.STATUS_POISON
	var party := _make_party([healthy, fainted], [0, 1])

	var nodes := _make_node_set()
	bs._refresh_doubles_side(party, false, nodes["sprites"], nodes["groups"],
			nodes["status_icons"], nodes["status_atlases"], nodes["hp_fills"],
			nodes["name_labels"], nodes["level_labels"],
			_SPRITE_BASE_TOP, _SPRITE_BASE_BOTTOM)

	var healthy_sprite: TextureRect = nodes["sprites"][0]
	var fainted_sprite: TextureRect = nodes["sprites"][1]
	_chk("healthy slot stays fully opaque", healthy_sprite.modulate.a == 1.0)
	_chk("fainted slot fades to 0.3 alpha", is_equal_approx(fainted_sprite.modulate.a, 0.3))
	_chk("healthy slot's own modulate unaffected by teammate fainting",
			healthy_sprite.modulate.a != fainted_sprite.modulate.a)

	var healthy_icon: TextureRect = nodes["status_icons"][0]
	var fainted_icon: TextureRect = nodes["status_icons"][1]
	_chk("healthy (no status) slot's icon hidden", not healthy_icon.visible)
	_chk("poisoned slot's icon shown", fainted_icon.visible)
	_chk("healthy slot's own status icon unaffected by teammate's poison",
			healthy_icon.visible != fainted_icon.visible)

	# [M26c-1] Compared against the real BattleScreen._hp_bar_color() function
	# rather than a hardcoded literal -- that function's own return values
	# changed (now the Emerald UI Pack's real sourced HP-bar colors) as part
	# of this session's databox art swap; this test cares that the doubles
	# refresh path calls it correctly, not what its own literal values are.
	var healthy_fill: TextureProgressBar = nodes["hp_fills"][0]
	var fainted_fill: TextureProgressBar = nodes["hp_fills"][1]
	_chk("healthy slot HP fill at full-HP color",
			healthy_fill.tint_progress == bs._hp_bar_color(healthy.current_hp, healthy.max_hp))
	_chk("fainted (0 HP) slot HP fill at 0-HP color",
			fainted_fill.tint_progress == bs._hp_bar_color(fainted.current_hp, fainted.max_hp))


# ── D. A singles-shaped BattleParty (num_active()==1) passed through the
# generalized doubles-side function correctly hides slot 1 — confirms the
# generalized logic itself degrades correctly, even though the real screen
# never actually routes a singles battle through this function (that's
# gated by _is_doubles_mode, tested separately via the real autoplay path).

func _test_refresh_doubles_side_singles_shaped_party_hides_slot1() -> void:
	var bs := BattleScreen.new()
	var mon0 := _make_mon("Solo", 100)
	var party := _make_party([mon0, _make_mon("Bench", 100)], [0])

	var nodes := _make_node_set()
	bs._refresh_doubles_side(party, true, nodes["sprites"], nodes["groups"],
			nodes["status_icons"], nodes["status_atlases"], nodes["hp_fills"],
			nodes["name_labels"], nodes["level_labels"],
			_SPRITE_BASE_TOP, _SPRITE_BASE_BOTTOM)

	_chk("slot 0 shown for a 1-active party", nodes["sprites"][0].visible)
	_chk("slot 0 group shown for a 1-active party", nodes["groups"][0].visible)
	_chk("slot 1 hidden for a 1-active party", not nodes["sprites"][1].visible)
	_chk("slot 1 group hidden for a 1-active party", not nodes["groups"][1].visible)


# ── E. Idle-bob animation independence across doubles slots — a fainted
# slot's frame freezes while its still-live teammate's frame keeps
# alternating, exercised via the real _on_opponent_anim_timer_timeout()
# doubles branch (called directly, bypassing the actual Timer node —
# matching this project's established "call the handler directly"
# testing convention). ─────────────────────────────────────────────────────

func _test_anim_timer_doubles_independence() -> void:
	var bs := BattleScreen.new()
	var healthy := _make_mon("Healthy", 100)
	healthy.current_hp = 100
	var fainted := _make_mon("Fainted", 100)
	fainted.current_hp = 0
	fainted.fainted = true
	var party := _make_party([healthy, fainted], [0, 1])

	bs._is_doubles_mode = true
	bs._opp_party = party
	var opp_sprite0 := TextureRect.new()
	var opp_sprite1 := TextureRect.new()
	for s in [opp_sprite0, opp_sprite1]:
		s.offset_left = 0.0
		s.offset_right = 64.0
		s.offset_top = 0.0
		s.offset_bottom = 64.0
	bs._opp_sprites_d = [opp_sprite0, opp_sprite1]
	# [M26c battle-UI polish] _on_opponent_anim_timer_timeout()'s doubles
	# branch now calls _apply_bottom_anchored_front_sprite(), which reads
	# these baseline arrays directly (see battle_screen.gd's own
	# _opp_sprite_d_base_top/_bottom doc comment) -- left at their default
	# empty-Array value here, indexing [slot] would be an out-of-bounds
	# error, matching _make_node_set()'s own fake 64x64 baseline above.
	bs._opp_sprite_d_base_top = _SPRITE_BASE_TOP
	bs._opp_sprite_d_base_bottom = _SPRITE_BASE_BOTTOM
	bs._opp_anim_frame_d = [0, 0]

	bs._on_opponent_anim_timer_timeout()
	_chk("healthy slot's frame advances on tick 1", bs._opp_anim_frame_d[0] == 1)
	_chk("fainted slot's frame stays frozen on tick 1", bs._opp_anim_frame_d[1] == 0)

	bs._on_opponent_anim_timer_timeout()
	_chk("healthy slot's frame flips back on tick 2", bs._opp_anim_frame_d[0] == 0)
	_chk("fainted slot's frame still frozen on tick 2", bs._opp_anim_frame_d[1] == 0)


# ── F. Singles regression guard — the pure/static helpers this phase
# didn't touch still behave identically (a cheap, redundant safety net
# alongside the real battle_screen_autoplay smoke test's own unchanged
# 1/1 pass, and the pre-existing phase4f_targeting_test.gd's own
# _test_needs_target_select). ───────────────────────────────────────────────

func _test_singles_regression_helpers_unchanged() -> void:
	_chk("_next_anim_frame still alternates 0->1", BattleScreen._next_anim_frame(0, false) == 1)
	_chk("_next_anim_frame still alternates 1->0", BattleScreen._next_anim_frame(1, false) == 0)
	_chk("_next_anim_frame still freezes when fainted", BattleScreen._next_anim_frame(1, true) == 1)
	_chk("_status_icon_row still maps POISON to row 0", BattleScreen._status_icon_row(BattlePokemon.STATUS_POISON) == 0)
	_chk("_status_icon_row still maps NONE to -1", BattleScreen._status_icon_row(BattlePokemon.STATUS_NONE) == -1)
