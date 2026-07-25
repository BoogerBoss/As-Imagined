extends Node

# [Doubles-split roadmap, step 6] Rewritten against the new panel-based
# architecture (battle_screen_shared.gd/health_group_panel.gd) -- the old
# battle_screen.gd's own parameterized _refresh_doubles_side() (taking raw
# node arrays) no longer exists; battle_screen_doubles.tscn now instances
# real HealthGroupPanel scenes instead, and _refresh_battlefield_side()
# (the generic per-side refresh both singles and doubles now share) reads
# _opp_panels/_opp_sprites/_ply_panels/_ply_sprites directly rather than
# taking them as parameters.
#
# Individual panel refresh/independence behavior (name/level/gender/status/
# HP-color) is already exhaustively covered by health_group_panel_test.gd
# (87 assertions) -- deliberately NOT re-derived here. This suite covers
# what's genuinely NEW at the battle_screen_shared.gd layer: the per-slot
# loop itself (correct sprite/panel pairing, correct slot count from
# BattleParty.num_active()) and the idle-bob frame-independence mechanism
# (_opp_anim_frame, _on_opponent_anim_timer_timeout).
#
# [Deliberately NOT tested here] Instantiating battle_screen_singles.tscn/
# _doubles.tscn themselves as a live scene -- same established precedent as
# phase4f_targeting_test.gd (count_assertions.sh's process-wide --autoplay
# flag risk). Every function this suite exercises is called directly on a
# bare `BattleScreenShared.new()` instance that is NEVER added to the tree
# (only the real HealthGroupPanel children it references ARE added to
# THIS test's own tree, so their own _ready() genuinely runs). The real
# end-to-end proof is the mandated real screenshot verification instead.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_refresh_battlefield_side_basic_render()
	_test_refresh_battlefield_side_independent_fade_and_status()
	_test_refresh_battlefield_side_singles_shaped_party_uses_one_slot()
	_test_anim_timer_doubles_independence()
	_test_singles_regression_helpers_unchanged()

	# Lets every queue_free() above (real HealthGroupPanel instances added
	# to this test's own tree) actually process before exit -- avoids a
	# purely cosmetic exit-time ObjectDB leak warning, no test semantics
	# affected.
	await get_tree().process_frame

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


# Real HealthGroupPanel instances (doubles-opponent shape), added to THIS
# test's own tree so their own _ready() genuinely runs (font/atlas/solid-
# fill-bar wiring), matching health_group_panel_test.gd's own established
# real-tree-membership convention -- a bare, never-added HealthGroupPanel
# would crash refresh() reaching for its still-null _status_atlas/_font.
func _make_opp_panels() -> Array:
	var scene: PackedScene = load("res://scenes/battle/health_group_panel_doubles_opponent.tscn")
	var p0: HealthGroupPanel = scene.instantiate()
	var p1: HealthGroupPanel = scene.instantiate()
	add_child(p0)
	add_child(p1)
	return [p0, p1]


func _make_sprites() -> Array:
	# [M26c battle-UI polish] A real, nonzero offset box (matching the real
	# .tscn nodes' own square-box convention) -- width feeds
	# _apply_bottom_anchored_front_sprite's own scale computation, which
	# early-returns (leaving .texture untouched) for a zero-width box.
	var sprite0 := TextureRect.new()
	var sprite1 := TextureRect.new()
	for s in [sprite0, sprite1]:
		s.offset_left = 0.0
		s.offset_right = 64.0
		s.offset_top = 0.0
		s.offset_bottom = 64.0
	return [sprite0, sprite1]


const _SPRITE_BASE_TOP := [0.0, 0.0]
const _SPRITE_BASE_BOTTOM := [64.0, 64.0]


# ── A. _refresh_battlefield_side basic two-slot render ──────────────────

func _test_refresh_battlefield_side_basic_render() -> void:
	var bs := BattleScreenShared.new()
	var mon0 := _make_mon("Alpha", 100)
	var mon1 := _make_mon("Beta", 100)
	bs._opp_party = _make_party([mon0, mon1, _make_mon("Bench", 100)], [0, 1])
	bs._opp_panels = _make_opp_panels()
	bs._opp_sprites = _make_sprites()
	bs._opp_sprite_base_top = _SPRITE_BASE_TOP
	bs._opp_sprite_base_bottom = _SPRITE_BASE_BOTTOM
	bs._opp_anim_frame = [0, 0]

	bs._refresh_battlefield_side(bs._opp_party, false)

	var panel0: HealthGroupPanel = bs._opp_panels[0]
	var panel1: HealthGroupPanel = bs._opp_panels[1]
	_chk("slot 0 name set", (panel0.get_node("NameLabel") as Label).text == bs._name_text(mon0))
	_chk("slot 1 name set", (panel1.get_node("NameLabel") as Label).text == bs._name_text(mon1))
	_chk("slot 0 level set", (panel0.get_node("LevelLabel") as Label).text == bs._level_text(mon0))
	_chk("slot 1 level set", (panel1.get_node("LevelLabel") as Label).text == bs._level_text(mon1))
	var hp_fill0: TextureProgressBar = panel0.get_hp_fill_bar()
	var hp_fill1: TextureProgressBar = panel1.get_hp_fill_bar()
	_chk("slot 0 hp_fill max/value set", hp_fill0.max_value == mon0.max_hp and hp_fill0.value == mon0.current_hp)
	_chk("slot 1 hp_fill max/value set", hp_fill1.max_value == mon1.max_hp and hp_fill1.value == mon1.current_hp)
	_chk("slot 0 sprite texture assigned", (bs._opp_sprites[0] as TextureRect).texture != null)
	_chk("slot 1 sprite texture assigned", (bs._opp_sprites[1] as TextureRect).texture != null)
	for p in bs._opp_panels:
		(p as Node).queue_free()
	bs.free()


# ── B. Independence — one Pokémon fainting/statused must not affect its
# teammate's own fade/status/HP-color display (the key regression risk
# Phase 4d's own original task called out, still real under the new
# panel-based design since each slot is still a fully independent node). ──

func _test_refresh_battlefield_side_independent_fade_and_status() -> void:
	var bs := BattleScreenShared.new()
	var healthy := _make_mon("Healthy", 100)
	healthy.current_hp = 100
	var fainted := _make_mon("Fainted", 100)
	fainted.current_hp = 0
	fainted.fainted = true
	fainted.status = BattlePokemon.STATUS_POISON
	bs._opp_party = _make_party([healthy, fainted], [0, 1])
	bs._opp_panels = _make_opp_panels()
	bs._opp_sprites = _make_sprites()
	bs._opp_sprite_base_top = _SPRITE_BASE_TOP
	bs._opp_sprite_base_bottom = _SPRITE_BASE_BOTTOM
	bs._opp_anim_frame = [0, 0]

	bs._refresh_battlefield_side(bs._opp_party, false)

	var healthy_sprite: TextureRect = bs._opp_sprites[0]
	var fainted_sprite: TextureRect = bs._opp_sprites[1]
	_chk("healthy slot stays fully opaque", healthy_sprite.modulate.a == 1.0)
	_chk("fainted slot fades to 0.3 alpha", is_equal_approx(fainted_sprite.modulate.a, 0.3))
	_chk("healthy slot's own modulate unaffected by teammate fainting",
			healthy_sprite.modulate.a != fainted_sprite.modulate.a)

	var panel0: HealthGroupPanel = bs._opp_panels[0]
	var panel1: HealthGroupPanel = bs._opp_panels[1]
	var healthy_icon: TextureRect = panel0.get_node("StatusIcon")
	var fainted_icon: TextureRect = panel1.get_node("StatusIcon")
	_chk("healthy (no status) slot's icon hidden", not healthy_icon.visible)
	_chk("poisoned slot's icon shown", fainted_icon.visible)
	_chk("healthy slot's own status icon unaffected by teammate's poison",
			healthy_icon.visible != fainted_icon.visible)

	var healthy_fill: TextureProgressBar = panel0.get_hp_fill_bar()
	var fainted_fill: TextureProgressBar = panel1.get_hp_fill_bar()
	_chk("healthy slot HP fill at full-HP color",
			healthy_fill.tint_progress == bs._hp_bar_color(healthy.current_hp, healthy.max_hp))
	_chk("fainted (0 HP) slot HP fill at 0-HP color",
			fainted_fill.tint_progress == bs._hp_bar_color(fainted.current_hp, fainted.max_hp))
	for p in bs._opp_panels:
		(p as Node).queue_free()
	bs.free()


# ── C. A singles-shaped BattleParty (num_active()==1) only touches slot 0
# — confirms the generic per-slot loop itself degrades correctly down to
# one slot, the shape battle_screen_singles.tscn's own 1-panel arrays
# always present in production.

func _test_refresh_battlefield_side_singles_shaped_party_uses_one_slot() -> void:
	var bs := BattleScreenShared.new()
	var mon0 := _make_mon("Solo", 100)
	bs._opp_party = _make_party([mon0, _make_mon("Bench", 100)], [0])
	bs._opp_panels = _make_opp_panels()
	bs._opp_sprites = _make_sprites()
	bs._opp_sprite_base_top = _SPRITE_BASE_TOP
	bs._opp_sprite_base_bottom = _SPRITE_BASE_BOTTOM
	bs._opp_anim_frame = [0, 0]

	bs._refresh_battlefield_side(bs._opp_party, false)

	_chk("slot 0 sprite texture assigned for a 1-active party",
			(bs._opp_sprites[0] as TextureRect).texture != null)
	_chk("slot 1 sprite texture left untouched for a 1-active party",
			(bs._opp_sprites[1] as TextureRect).texture == null)
	for p in bs._opp_panels:
		(p as Node).queue_free()
	bs.free()


# ── D. Idle-bob animation independence across doubles slots — a fainted
# slot's frame freezes while its still-live teammate's frame keeps
# alternating, exercised via the real _on_opponent_anim_timer_timeout()
# (now fully generic over slot count, not a separate doubles branch). ────

func _test_anim_timer_doubles_independence() -> void:
	var bs := BattleScreenShared.new()
	var healthy := _make_mon("Healthy", 100)
	healthy.current_hp = 100
	var fainted := _make_mon("Fainted", 100)
	fainted.current_hp = 0
	fainted.fainted = true
	bs._opp_party = _make_party([healthy, fainted], [0, 1])
	bs._opp_sprites = _make_sprites()
	bs._opp_sprite_base_top = _SPRITE_BASE_TOP
	bs._opp_sprite_base_bottom = _SPRITE_BASE_BOTTOM
	bs._opp_anim_frame = [0, 0]

	bs._on_opponent_anim_timer_timeout()
	_chk("healthy slot's frame advances on tick 1", bs._opp_anim_frame[0] == 1)
	_chk("fainted slot's frame stays frozen on tick 1", bs._opp_anim_frame[1] == 0)

	bs._on_opponent_anim_timer_timeout()
	_chk("healthy slot's frame flips back on tick 2", bs._opp_anim_frame[0] == 0)
	_chk("fainted slot's frame still frozen on tick 2", bs._opp_anim_frame[1] == 0)
	bs.free()


# ── E. Singles regression guard — the pure/static helpers this phase
# didn't touch still behave identically. [Doubles-split roadmap, step 6]
# _status_icon_row/_update_status_icon no longer exist on
# BattleScreenShared at all (that logic moved into HealthGroupPanel,
# already covered by health_group_panel_test.gd's own
# _test_status_icon_row_mapping) -- only _next_anim_frame (still genuinely
# owned by battle_screen_shared.gd) is re-checked here.

func _test_singles_regression_helpers_unchanged() -> void:
	_chk("_next_anim_frame still alternates 0->1", BattleScreenShared._next_anim_frame(0, false) == 1)
	_chk("_next_anim_frame still alternates 1->0", BattleScreenShared._next_anim_frame(1, false) == 0)
	_chk("_next_anim_frame still freezes when fainted", BattleScreenShared._next_anim_frame(1, true) == 1)
	_chk("HealthGroupPanel.status_icon_row still maps POISON to row 0",
			HealthGroupPanel.status_icon_row(BattlePokemon.STATUS_POISON) == 0)
	_chk("HealthGroupPanel.status_icon_row still maps NONE to -1",
			HealthGroupPanel.status_icon_row(BattlePokemon.STATUS_NONE) == -1)
