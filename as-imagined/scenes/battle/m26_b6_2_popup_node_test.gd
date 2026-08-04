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
	_test_render_geometry_uniform_and_center_anchored()
	_test_popup_font_contexts()
	await _test_trigger_wiring_and_guard()

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
	# [M26B6-2.1] The slide is scaled by the art's own uniform render scale,
	# not the stage scale — see _play_ability_popup's own comment.
	var slide: float = BattleScreenShared._ABILITY_POPUP_SLIDE \
			* BattleScreenShared._ABILITY_POPUP_RENDER_SCALE

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


# ── E. [M26B6-2.1] Render geometry — uniform 4x, center-anchored ─────────

func _test_render_geometry_uniform_and_center_anchored() -> void:
	_chk("E.01 render scale is the uniform GBA-art 4x",
			BattleScreenShared._ABILITY_POPUP_RENDER_SCALE == 4.0)

	var p0 := _make_mon("P0")
	var o0 := _make_mon("O0")
	var sng := _make_bs([p0], [o0], false)

	var rect: Rect2 = sng._ability_popup_rest_rect(false, 0)
	_chk("E.02 the panel renders at exactly 4x its 128x32 art",
			rect.size == Vector2(512.0, 128.0))
	_chk("E.03 the rest rect is CENTERED on the target point",
			rect.get_center().is_equal_approx(sng._ability_popup_target(false, 0)))

	# The regression that must not return: pokeemerald sprite coords are
	# CENTERS, and the popup is a two-sprite pair whose own center is
	# (table.x + 32, table.y). The first cut read the table as the panel's
	# top-left, parking the popup 32 GBA px right and 16 low. On a bare
	# instance the stage scale is ONE, so the target is directly comparable
	# to the table in GBA units.
	_chk("E.04 singles-opponent target is the sprite-PAIR center (table + (32,0))",
			sng._ability_popup_target(false, 0)
				== BattleScreenShared._ABILITY_POPUP_COORDS_SINGLES[1] + Vector2(32.0, 0.0))
	_chk("E.05 singles-player target likewise",
			sng._ability_popup_target(true, 0)
				== BattleScreenShared._ABILITY_POPUP_COORDS_SINGLES[0] + Vector2(32.0, 0.0))
	sng.free()


# ── F. [M26B6-3.1] Popup font contexts — baked colours, no overrides ─────

func _test_popup_font_contexts() -> void:
	var name_font := FontFile.new()
	_chk("F.01 the popup NAME font context loads",
			name_font.load_bitmap_font("res://assets/fonts/latin_small_popup_name.fnt") == OK)
	var ability_font := FontFile.new()
	_chk("F.02 the popup ABILITY font context loads",
			ability_font.load_bitmap_font("res://assets/fonts/latin_small_popup_ability.fnt") == OK)

	# Two genuinely distinct bakes, not one file emitted twice — the atlases
	# must differ (near-white-on-dark vs black-on-light glyph pixels).
	var name_png := FileAccess.get_file_as_bytes("res://assets/fonts/latin_small_popup_name.png")
	var ability_png := FileAccess.get_file_as_bytes("res://assets/fonts/latin_small_popup_ability.png")
	_chk("F.03 the two contexts are genuinely different bakes",
			not name_png.is_empty() and name_png != ability_png)

	var p0 := _make_mon("Pika")
	var o0 := _make_mon("O0")
	var sng := _make_bs([p0], [o0], false)
	sng._load_battle_fonts()
	_chk("F.04 _load_battle_fonts populates both popup fonts with real scaling",
			sng._font_popup_name != null and sng._font_popup_ability != null
				and sng._font_popup_name.fixed_size_scale_mode == 2
				and sng._font_popup_ability.fixed_size_scale_mode == 2)

	var panel := Control.new()
	sng._build_ability_popup_text(panel, p0,
			Vector2(BattleScreenShared._ABILITY_POPUP_RENDER_SCALE,
					BattleScreenShared._ABILITY_POPUP_RENDER_SCALE))
	var name_lbl: Label = panel.get_child(0)
	var ability_lbl: Label = panel.get_child(1)
	_chk("F.05 the name label uses the NAME context and the ability label the ABILITY context",
			name_lbl.get_theme_font("font") == sng._font_popup_name
				and ability_lbl.get_theme_font("font") == sng._font_popup_ability)

	# THE guard: no font_color/font_shadow_color overrides may exist. Godot's
	# overrides MULTIPLY against baked glyph pixels rather than replacing
	# them — reintroducing one is exactly what made the first cut's text
	# read muddy (the M25h-1.2 message-box trap in popup form).
	_chk("F.06 no colour override on either label (colours live in the bake)",
			not name_lbl.has_theme_color_override("font_color")
				and not ability_lbl.has_theme_color_override("font_color")
				and not name_lbl.has_theme_color_override("font_shadow_color")
				and not ability_lbl.has_theme_color_override("font_shadow_color"))

	# Uniform 4x makes the band/font math exact: 10-row bands scale to 40px,
	# fitting the native-13 font at exactly 3x = 39 under the standing
	# integer-multiple-only invariant.
	_chk("F.07 band height at 4x fits the font at an exact 3x multiple (39 in 40)",
			name_lbl.get_theme_font_size("font_size") == 39)
	panel.free()
	sng.free()


# ── G. [M26B6-4] Trigger wiring, key policy, and the per-battler guard ───

func _test_trigger_wiring_and_guard() -> void:
	# G.01 — the deliberate ~33% pacing deviation (Rob, 2026-08-03). Source's
	# own constants stay untouched above; ONE factor carries the whole
	# deviation, and the resulting total is ~74.7 frames (~1.25 s).
	_chk("G.01 time scale is 2/3 and yields a ~74.7-frame total",
			is_equal_approx(BattleScreenShared._ABILITY_POPUP_TIME_SCALE, 2.0 / 3.0)
				and is_equal_approx(
					(32.0 * 2.0 + 48.0) * BattleScreenShared._ABILITY_POPUP_TIME_SCALE,
					74.0 + 2.0 / 3.0))

	# G.02 — the exclusion set is EXACTLY the five keys the source audit
	# failed: two items, one move, and the two switch-out abilities whose
	# source handling is pure C with no battle script (no popup exists).
	var excl: Dictionary = BattleScreenShared._ABILITY_POPUP_EXCLUDED_KEYS
	_chk("G.02 exclusion set is exactly the 5 audited non-popup keys",
			excl.size() == 5 and excl.has("lansat_berry") and excl.has("micle_berry")
				and excl.has("magic_coat") and excl.has("natural_cure")
				and excl.has("regenerator"))

	# G.03 — data-driven audit guard: re-derive the emit surface from
	# battle_manager.gd itself. A NEW emit site or key fails here until it
	# has been classified against source (the D3-style discipline). Counts
	# pinned at the 2026-08-03 audit: 109 sites, 68 literal keys, 10
	# variable-carrying sites.
	var src := FileAccess.get_file_as_string("res://scripts/battle/core/battle_manager.gd")
	var site_re := RegEx.create_from_string("ability_triggered\\.emit\\(([^)]*)\\)")
	var key_re := RegEx.create_from_string(",\\s*\"([^\"]+)\"")
	var sites := site_re.search_all(src)
	var lit := {}
	var variable_sites := 0
	for m in sites:
		var km := key_re.search(m.get_string(1))
		if km != null:
			lit[km.get_string(1)] = true
		else:
			variable_sites += 1
	_chk("G.03 emit surface matches the audited 109 sites / 68 literal keys / 10 variable sites",
			sites.size() == 109 and lit.size() == 68 and variable_sites == 10)
	var unclassified: Array = []
	for k: String in lit:
		# Every literal key must be either popped (default) or explicitly
		# excluded — an excluded key that no longer exists is equally a bug.
		if excl.has(k):
			unclassified.append("")  # excluded and present: fine
	for k: String in excl:
		if k != "natural_cure" and k != "regenerator" and k != "magic_coat" \
				and not lit.has(k):
			unclassified.append(k)
	_chk("G.03b every non-variable excluded key exists in the emit surface",
			unclassified.filter(func(x): return x != "").is_empty())

	# G.04 — the handler's own policy: included keys queue a banner beat,
	# excluded keys and null mons queue nothing.
	var p0 := _make_mon("P0")
	var o0 := _make_mon("O0")
	var pol := _make_bs([p0], [o0], false)
	pol._on_popup_ability_triggered(p0, "intimidate")
	pol._on_popup_ability_triggered(p0, "lansat_berry")
	pol._on_popup_ability_triggered(null, "intimidate")
	var popup_beats: Array = pol._pending_beats.filter(
			func(b): return b.get("kind") == "ability_popup")
	_chk("G.04 included key queues exactly one banner beat; excluded/null queue none",
			popup_beats.size() == 1 and popup_beats[0].get("mon") == p0)
	pol.free()

	# G.05 — the one-popup-per-battler guard, live: a second trigger for the
	# same mon REWRITES the live panel's ability line instead of stacking.
	var g_p0 := _make_mon("Gyarados")
	var ab := AbilityData.new()
	ab.ability_name = "Intimidate"
	g_p0.ability = ab
	var g_o0 := _make_mon("O0")
	var bs := _make_bs([g_p0], [g_o0], false)
	var layer := Control.new()
	layer.size = Vector2(960.0, 480.0)
	bs._effect_layer = layer
	# _play_ability_popup's create_tween() call needs a live SceneTree, but
	# only reachable via the node the tween is created ON (panel, added as a
	# child of _effect_layer). Adding `layer` to this test's own tree gives
	# every node parented under it (including panels _play_ability_popup
	# creates later) that live tree — WITHOUT adding `bs` itself, which is a
	# bare BattleScreenShared.new() instance whose _ready() assumes the real
	# .tscn's node tree exists and crashes on null @onready refs otherwise.
	add_child(layer)

	bs._play_ability_popup(g_p0)  # fire-and-forget, panel exists synchronously
	_chk("G.05 first trigger creates one live panel",
			layer.get_child_count() == 1
				and bs._active_ability_popups.get(g_p0) == layer.get_child(0))
	var ab2 := AbilityData.new()
	ab2.ability_name = "Moxie"
	g_p0.ability = ab2
	bs._play_ability_popup(g_p0)
	_chk("G.05b second trigger does NOT stack a second panel",
			layer.get_child_count() == 1)
	var panel: Control = layer.get_child(0)
	var lbl: Label = panel.get_meta("ability_popup_label")
	_chk("G.05c ...it rewrites the live panel's ability line (UpdateAbilityPopup)",
			lbl != null and lbl.text == "Moxie")

	# G.06 — battle-end teardown kills the popup's tween via the shared
	# meta key and drops the guard reference (the B6-2 gap this closes).
	_chk("G.06 popup tween is registered under the teardown's own meta key",
			panel.get_meta("_hit_effect_tween", null) is Tween)
	bs._clear_active_hit_effects()
	_chk("G.06b teardown frees the panel and clears the guard",
			layer.get_child_count() == 0 and bs._active_ability_popups.is_empty())
	remove_child(bs)
	bs.free()
