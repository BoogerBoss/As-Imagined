extends Node

# [M23.11 Phase 5c] Smoke test for the hit-effect dispatch engine --
# HitEffectRegistry's own pure lookup logic (move-id resolution, bespoke
# detection, generic type/category dispatch, frame-layout math) plus
# battle_screen.gd's singles/doubles sprite-node targeting helpers.
#
# [Deliberately NOT tested here] The actual Tween-driven node
# creation/animation (_play_multi_stage_strip_effect/_play_surf_effect) --
# same established precedent as phase4d_doubles_visual_test.gd's own doc
# comment: create_tween() requires the calling node to be inside a live
# SceneTree, and instantiating the real battle_screen.tscn here would hit
# this project's own --autoplay/get_tree().quit() collision (see that
# file's doc comment for the exact mechanism). The genuine end-to-end proof
# is this session's own real, non-headless screenshot verification
# (8 scenarios: 3 bespoke + 3 generic type/category combinations, singles
# and doubles) instead.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_move_id_of()
	_test_is_bespoke()
	_test_generic_texture_dispatch()
	_test_compute_frame_layout()
	_test_sprite_node_for_singles()
	_test_sprite_node_for_doubles()
	_test_field_slot_for()

	var total := _pass + _fail
	print("hit_effect_dispatch_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


# ── move_id_of / is_bespoke ─────────────────────────────────────────────

func _test_move_id_of() -> void:
	var flamethrower := MoveRegistry.get_move(53)
	var thunder := MoveRegistry.get_move(87)
	var surf := MoveRegistry.get_move(57)
	var tackle := MoveRegistry.get_move(33)

	_chk("move_id_of resolves Flamethrower's real file id",
			HitEffectRegistry.move_id_of(flamethrower) == 53)
	_chk("move_id_of resolves Thunder's real file id",
			HitEffectRegistry.move_id_of(thunder) == 87)
	_chk("move_id_of resolves Surf's real file id",
			HitEffectRegistry.move_id_of(surf) == 57)
	_chk("move_id_of resolves an ordinary move's id too (not bespoke-only)",
			HitEffectRegistry.move_id_of(tackle) == 33)
	_chk("move_id_of returns -1 for a null move", HitEffectRegistry.move_id_of(null) == -1)

	var unbacked := MoveData.new()
	_chk("move_id_of returns -1 for a move with no resource_path (never loaded from disk)",
			HitEffectRegistry.move_id_of(unbacked) == -1)


func _test_is_bespoke() -> void:
	_chk("53 (Flamethrower) is bespoke", HitEffectRegistry.is_bespoke(53))
	_chk("87 (Thunder) is bespoke", HitEffectRegistry.is_bespoke(87))
	_chk("57 (Surf) is bespoke", HitEffectRegistry.is_bespoke(57))
	_chk("33 (Tackle) is NOT bespoke", not HitEffectRegistry.is_bespoke(33))
	_chk("94 (Psychic) is NOT bespoke", not HitEffectRegistry.is_bespoke(94))
	_chk("an arbitrary unrelated id is NOT bespoke", not HitEffectRegistry.is_bespoke(9999))


# ── get_generic_texture dispatch ────────────────────────────────────────

func _make_move(type: int, category: int, stat_change_stat: int = -1) -> MoveData:
	var m := MoveData.new()
	m.type = type
	m.category = category
	m.stat_change_stat = stat_change_stat
	return m


func _test_generic_texture_dispatch() -> void:
	# Damaging moves dispatch on TYPE, not category.
	var fire_physical := _make_move(TypeChart.TYPE_FIRE, 0)
	var tex := HitEffectRegistry.get_generic_texture(fire_physical)
	_chk("Fire-type physical move dispatches to generic/fire.png",
			tex != null and tex.resource_path.ends_with("generic/fire.png"))

	var electric_special := _make_move(TypeChart.TYPE_ELECTRIC, 1)
	tex = HitEffectRegistry.get_generic_texture(electric_special)
	_chk("Electric-type special move dispatches to generic/electric.png",
			tex != null and tex.resource_path.ends_with("generic/electric.png"))

	var normal_physical := _make_move(TypeChart.TYPE_NORMAL, 0)
	tex = HitEffectRegistry.get_generic_texture(normal_physical)
	_chk("Normal-type physical move dispatches to generic/normal.png",
			tex != null and tex.resource_path.ends_with("generic/normal.png"))

	# STATUS moves dispatch on CATEGORY first, regardless of their own real
	# elemental type (Growl/Swords Dance are TYPE_NORMAL in the real
	# roster, Toxic is TYPE_POISON, etc.) -- the real bug this session's own
	# screenshot-verification driver caught and this test now guards
	# against regressing: checking .type first would make stat_shimmer/
	# status_puff almost unreachable, since nearly every status move still
	# carries a real type.
	var status_stat_raise := _make_move(TypeChart.TYPE_NORMAL, 2, BattlePokemon.STAGE_ATK)
	tex = HitEffectRegistry.get_generic_texture(status_stat_raise)
	_chk("A stat-changing status move (stat_change_stat >= 0) dispatches to stat_shimmer, NOT its own type",
			tex != null and tex.resource_path.ends_with("generic/stat_shimmer.png"))

	var status_non_stat := _make_move(TypeChart.TYPE_POISON, 2, -1)
	tex = HitEffectRegistry.get_generic_texture(status_non_stat)
	_chk("A non-stat-changing status move (e.g. Toxic-shaped) dispatches to status_puff, NOT its own type",
			tex != null and tex.resource_path.ends_with("generic/status_puff.png"))

	# TYPE_MYSTERY/TYPE_STELLAR (no curated generic sprite) fall back to
	# physical_impact for a damaging move.
	var typeless_damaging := _make_move(TypeChart.TYPE_MYSTERY, 0)
	tex = HitEffectRegistry.get_generic_texture(typeless_damaging)
	_chk("A damaging move with no curated type sprite falls back to physical_impact",
			tex != null and tex.resource_path.ends_with("generic/physical_impact.png"))

	_chk("get_generic_texture returns null for a null move",
			HitEffectRegistry.get_generic_texture(null) == null)


# ── compute_frame_layout ─────────────────────────────────────────────────

func _test_compute_frame_layout() -> void:
	var square := HitEffectRegistry.compute_frame_layout(Vector2(32, 32))
	_chk("single square frame -> frame_count 1", square["frame_count"] == 1)
	_chk("single square frame -> frame_size unchanged", square["frame_size"] == Vector2(32, 32))

	var vertical := HitEffectRegistry.compute_frame_layout(Vector2(32, 256))
	_chk("fire.png-shaped strip (32x256) -> 8 frames", vertical["frame_count"] == 8)
	_chk("fire.png-shaped strip -> 32x32 frame size", vertical["frame_size"] == Vector2(32, 32))
	_chk("fire.png-shaped strip -> vertical stacking", vertical["vertical"] == true)

	var horizontal := HitEffectRegistry.compute_frame_layout(Vector2(32, 16))
	_chk("dragon.png-shaped strip (32x16) -> 2 frames", horizontal["frame_count"] == 2)
	_chk("dragon.png-shaped strip -> 16x16 frame size", horizontal["frame_size"] == Vector2(16, 16))
	_chk("dragon.png-shaped strip -> horizontal stacking", horizontal["vertical"] == false)

	# steel.png's own real irregular shape (16x40 -- 40 is not a multiple
	# of 16) -- must fall back to ONE whole-image frame, not crop.
	var irregular := HitEffectRegistry.compute_frame_layout(Vector2(16, 40))
	_chk("steel.png-shaped irregular source -> frame_count 1 (no crop)", irregular["frame_count"] == 1)
	_chk("steel.png-shaped irregular source -> full size kept as one frame",
			irregular["frame_size"] == Vector2(16, 40))


# ── battle_screen.gd sprite-node targeting (pure lookup, no live tree
# required -- mirrors phase4d_doubles_visual_test.gd's own BattleScreen
# .new() + plain-node pattern) ──────────────────────────────────────────

static func _make_mon(mon_name: String) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types.append(TypeChart.TYPE_NORMAL)
	sp.base_hp = 100
	sp.base_attack = 80
	sp.base_defense = 80
	sp.base_sp_attack = 80
	sp.base_sp_defense = 80
	sp.base_speed = 80
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])


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


func _test_sprite_node_for_singles() -> void:
	var bs := BattleScreen.new()
	var ply := _make_mon("Ply")
	var opp := _make_mon("Opp")
	bs._player_party = _make_party([ply], [0])
	bs._opp_party = _make_party([opp], [0])
	bs._is_doubles_mode = false
	var ply_node := TextureRect.new()
	var opp_node := TextureRect.new()
	bs._player_sprite = ply_node
	bs._opponent_sprite = opp_node

	_chk("singles: player mon resolves to the singles player sprite node",
			bs._sprite_node_for(ply) == ply_node)
	_chk("singles: opponent mon resolves to the singles opponent sprite node",
			bs._sprite_node_for(opp) == opp_node)
	_chk("singles: null mon resolves to null", bs._sprite_node_for(null) == null)


func _test_sprite_node_for_doubles() -> void:
	var bs := BattleScreen.new()
	var ply0 := _make_mon("Ply0")
	var ply1 := _make_mon("Ply1")
	var opp0 := _make_mon("Opp0")
	var opp1 := _make_mon("Opp1")
	bs._player_party = _make_party([ply0, ply1], [0, 1])
	bs._opp_party = _make_party([opp0, opp1], [0, 1])
	bs._is_doubles_mode = true
	var ply_d0 := TextureRect.new()
	var ply_d1 := TextureRect.new()
	var opp_d0 := TextureRect.new()
	var opp_d1 := TextureRect.new()
	bs._ply_sprites_d = [ply_d0, ply_d1]
	bs._opp_sprites_d = [opp_d0, opp_d1]

	_chk("doubles: player slot 0 mon resolves to D0 node", bs._sprite_node_for(ply0) == ply_d0)
	_chk("doubles: player slot 1 mon resolves to D1 node", bs._sprite_node_for(ply1) == ply_d1)
	_chk("doubles: opponent slot 0 mon resolves to D0 node", bs._sprite_node_for(opp0) == opp_d0)
	_chk("doubles: opponent slot 1 mon resolves to D1 node", bs._sprite_node_for(opp1) == opp_d1)
	_chk("doubles: a benched (inactive) mon still resolves rather than crashing",
			bs._sprite_node_for(_make_mon("Benched")) != null)


func _test_field_slot_for() -> void:
	var bs := BattleScreen.new()
	var mon0 := _make_mon("A")
	var mon1 := _make_mon("B")
	var party := _make_party([mon0, mon1], [0, 1])
	_chk("_field_slot_for finds slot 0", bs._field_slot_for(mon0, party) == 0)
	_chk("_field_slot_for finds slot 1", bs._field_slot_for(mon1, party) == 1)
	_chk("_field_slot_for defaults to 0 for an unmatched mon",
			bs._field_slot_for(_make_mon("C"), party) == 0)
