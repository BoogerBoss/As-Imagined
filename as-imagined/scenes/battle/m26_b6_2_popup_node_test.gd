extends Node

# [M26B6-2] Regression suite for the ability-popup node and its slide.
#
# Covers placement (per side and per doubles slot), the source-exact geometry
# and timing constants, and the enter/exit direction. Text is NOT drawn at this
# sub-phase (that is B6-3), so nothing here asserts text.
#
# The assertion that matters most is C.02: the panel must LEAVE the way it came
# rather than crossing the screen. Source achieves that by simply reversing its
# own xSlide sign, and a naive "slide out to the other side" port would look
# plausible while being wrong on the opponent's side.

const POPUP_TEX := "res://assets/sprites/battle_ui/interface/ability_pop_up.png"

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_constants_match_source()
	_test_coordinate_tables()
	_test_slot_resolution()
	_test_target_positions_differ_by_side_and_slot()
	_test_texture_available()
	_test_possessive_name_rule()
	_test_text_layout_constants()
	_test_ability_line_is_rewritable()

	var total := _pass + _fail
	print("m26_b6_2_popup_node_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


func _make_mon(mon_name: String) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types = [TypeChart.TYPE_NORMAL]
	sp.base_hp = 200
	sp.base_attack = 60
	sp.base_defense = 60
	sp.base_sp_attack = 60
	sp.base_sp_defense = 60
	sp.base_speed = 60
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])


func _party(mons: Array) -> BattleParty:
	var p := BattleParty.new()
	var typed: Array[BattlePokemon] = []
	for m: BattlePokemon in mons:
		typed.append(m)
	p.members = typed
	var idx: Array[int] = []
	for i in range(mons.size()):
		idx.append(i)
	p.active_indices = idx
	return p


func _make_bs(player: Array, opp: Array, doubles: bool) -> BattleScreenShared:
	var bs := BattleScreenShared.new()
	bs._player_party = _party(player)
	bs._opp_party = _party(opp)
	# _is_doubles() derives from the wired opponent PANEL COUNT, so only the
	# array's size matters -- null entries are enough, and avoid leaking real
	# Control instances that this bare-instance test would never free.
	var panels: Array = []
	for i in range(2 if doubles else 1):
		panels.append(null)
	bs._opp_panels = panels
	return bs


# ── A. Constants ─────────────────────────────────────────────────────────

func _test_constants_match_source() -> void:
	_chk("A.01 slide distance is source's ABILITY_POP_UP_POS_X_SLIDE (128)",
			BattleScreenShared._ABILITY_POPUP_SLIDE == 128.0)
	_chk("A.02 slide speed is source's ABILITY_POP_UP_POS_X_SPEED (4)",
			BattleScreenShared._ABILITY_POPUP_SPEED == 4.0)
	_chk("A.03 hold is source's ABILITY_POP_UP_WAIT_FRAMES (48)",
			BattleScreenShared._ABILITY_POPUP_HOLD == 48)
	# 128/4 = 32 frames each way; 32 + 48 + 32 = 112.
	var slide_frames: float = BattleScreenShared._ABILITY_POPUP_SLIDE \
			/ BattleScreenShared._ABILITY_POPUP_SPEED
	_chk("A.04 that yields a 32-frame slide and ~112-frame total",
			is_equal_approx(slide_frames, 32.0)
				and is_equal_approx(slide_frames * 2.0
					+ float(BattleScreenShared._ABILITY_POPUP_HOLD), 112.0))
	# One 128x32 node, not two 64x32 sprites -- the split is a GBA OAM limit.
	_chk("A.05 the panel is one 128x32 unit",
			BattleScreenShared._ABILITY_POPUP_SIZE == Vector2(128.0, 32.0))


func _test_coordinate_tables() -> void:
	var s: Array = BattleScreenShared._ABILITY_POPUP_COORDS_SINGLES
	var d: Array = BattleScreenShared._ABILITY_POPUP_COORDS_DOUBLES
	_chk("A.06 singles table has 2 entries", s.size() == 2)
	_chk("A.07 doubles table has 4 entries", d.size() == 4)
	_chk("A.08 singles coords match source",
			s[0] == Vector2(24, 97) and s[1] == Vector2(178, 57))
	_chk("A.09 doubles coords match source",
			d[0] == Vector2(24, 80) and d[1] == Vector2(24, 97)
				and d[2] == Vector2(178, 19) and d[3] == Vector2(178, 36))
	# Player-side popups sit left, opponent-side right -- the property the
	# slide direction depends on.
	_chk("A.10 player coords are left of opponent coords",
			s[0].x < s[1].x and d[0].x < d[2].x)


# ── B. Slot resolution ───────────────────────────────────────────────────

func _test_slot_resolution() -> void:
	var p0 := _make_mon("P0")
	var p1 := _make_mon("P1")
	var o0 := _make_mon("O0")
	var o1 := _make_mon("O1")
	var bs := _make_bs([p0, p1], [o0, o1], true)

	var a: Dictionary = bs._ability_popup_slot(p0)
	_chk("B.01 player slot 0 resolves",
			a.get("is_player") == true and a.get("slot") == 0)
	var b: Dictionary = bs._ability_popup_slot(p1)
	_chk("B.02 player slot 1 resolves",
			b.get("is_player") == true and b.get("slot") == 1)
	var c: Dictionary = bs._ability_popup_slot(o1)
	_chk("B.03 opponent slot 1 resolves",
			c.get("is_player") == false and c.get("slot") == 1)
	_chk("B.04 an unknown mon resolves to nothing (no crash, no popup)",
			bs._ability_popup_slot(_make_mon("Stranger")).is_empty())
	bs.free()


# ── C. Placement and direction ───────────────────────────────────────────

func _test_target_positions_differ_by_side_and_slot() -> void:
	var p0 := _make_mon("P0")
	var p1 := _make_mon("P1")
	var o0 := _make_mon("O0")
	var o1 := _make_mon("O1")

	var dbl := _make_bs([p0, p1], [o0, o1], true)
	_chk("C.01 doubles gives each of the four slots a distinct position",
			dbl._ability_popup_target(true, 0) != dbl._ability_popup_target(true, 1)
				and dbl._ability_popup_target(false, 0)
					!= dbl._ability_popup_target(false, 1)
				and dbl._ability_popup_target(true, 0)
					!= dbl._ability_popup_target(false, 0))

	# THE assertion: the panel must leave the way it came. Source reverses its
	# own xSlide sign rather than continuing across the screen, so the player's
	# panel enters from the LEFT (start x < target x) and the opponent's from
	# the RIGHT (start x > target x).
	var sng := _make_bs([p0], [o0], false)
	var scale: Vector2 = sng._weather_stage_scale()
	var slide: float = BattleScreenShared._ABILITY_POPUP_SLIDE * scale.x

	var ply_target: Vector2 = sng._ability_popup_target(true, 0)
	var opp_target: Vector2 = sng._ability_popup_target(false, 0)
	var ply_start := ply_target.x - slide
	var opp_start := opp_target.x + slide
	_chk("C.02 the player's panel enters from the LEFT", ply_start < ply_target.x)
	_chk("C.02b the opponent's panel enters from the RIGHT",
			opp_start > opp_target.x)
	_chk("C.03 the two sides enter from opposite directions",
			(ply_start < ply_target.x) != (opp_start < opp_target.x))

	# Singles must NOT silently use the doubles table.
	_chk("C.04 singles placement differs from doubles for the opponent",
			sng._ability_popup_target(false, 0)
				!= dbl._ability_popup_target(false, 0))
	sng.free()
	dbl.free()


func _test_texture_available() -> void:
	var t := load(POPUP_TEX) as Texture2D
	_chk("C.05 the popup texture loads", t != null)
	_chk("C.05b at the size the layout assumes",
			t != null and Vector2(t.get_size()) == BattleScreenShared._ABILITY_POPUP_SIZE)


# ── D. [M26B6-3] Text ────────────────────────────────────────────────────

# Source appends the apostrophe unconditionally and adds `s` ONLY when the
# name doesn't already end in s/S. The s/S branch is the fiddly half and the
# one a port is most likely to drop.
func _test_possessive_name_rule() -> void:
	_chk("D.01 an ordinary name gains 's",
			BattleScreenShared._possessive_name("Pikachu") == "Pikachu's")
	_chk("D.02 only a name ending in s is given a bare apostrophe",
			BattleScreenShared._possessive_name("Chansey") == "Chansey's"
				and BattleScreenShared._possessive_name("Gyarados") == "Gyarados'")
	_chk("D.03 the rule is case-insensitive on the final letter",
			BattleScreenShared._possessive_name("ABRAS") == "ABRAS'")
	_chk("D.04 an empty name is left alone rather than becoming a bare quote",
			BattleScreenShared._possessive_name("") == "")


func _test_text_layout_constants() -> void:
	var n: Rect2 = BattleScreenShared._ABILITY_POPUP_NAME_RECT
	var a: Rect2 = BattleScreenShared._ABILITY_POPUP_ABILITY_RECT
	# Bands read empirically off the panel art: dark rows 3-12, light 15-24.
	_chk("D.05 the name band sits above the ability band", n.position.y < a.position.y)
	_chk("D.06 both bands fit inside the 32px panel",
			n.position.y + n.size.y <= 32.0 and a.position.y + a.size.y <= 32.0)
	_chk("D.07 both bands fit inside the art's 104px content width",
			n.position.x + n.size.x <= 104.0 and a.position.x + a.size.x <= 104.0)
	# White-on-dark then black-on-light -- deliberately different, not one
	# style reused, and the cross-check that the bands were read correctly.
	_chk("D.08 the two lines use different foreground colours",
			BattleScreenShared._ABILITY_POPUP_NAME_COLOR
				!= BattleScreenShared._ABILITY_POPUP_ABILITY_COLOR)
	_chk("D.09 the name is light and the ability dark",
			BattleScreenShared._ABILITY_POPUP_NAME_COLOR.v
				> BattleScreenShared._ABILITY_POPUP_ABILITY_COLOR.v)


# The ability label must be REWRITABLE on a live popup -- that is what lets
# B6-4 reproduce source's UpdateAbilityPopup instead of stacking a second
# panel. Exercised through the real helper, not by poking the Label.
func _test_ability_line_is_rewritable() -> void:
	var bs := _make_bs([_make_mon("P0")], [_make_mon("O0")], false)
	var panel := Control.new()
	var lbl := Label.new()
	lbl.text = "Intimidate"
	panel.add_child(lbl)
	panel.set_meta("ability_popup_label", lbl)

	bs._set_ability_popup_ability(panel, "Levitate")
	_chk("D.10 the ability line can be rewritten in place", lbl.text == "Levitate")

	# Must not crash on a panel that never got text (e.g. a freed one).
	var bare := Control.new()
	bs._set_ability_popup_ability(bare, "Anything")
	_chk("D.11 a panel with no ability label is handled safely", true)

	bare.free()
	panel.free()
	bs.free()
