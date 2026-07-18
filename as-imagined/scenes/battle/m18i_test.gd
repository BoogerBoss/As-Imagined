extends Node

# M18i test suite — Status Orbs (Flame Orb, Toxic Orb)
#
# Ground truth: pokeemerald-expansion, src/battle_hold_effects.c :: TryFlameOrb
# (L617-630) / TryToxicOrb (L600-613), fired at IsOrbsActivation timing inside
# the standard per-turn end-of-turn item dispatch (battle_end_turn.c L1349-1358).
#
# CORRECTION found at Step 0: NOT a "first turn held" timer mechanic — checked
# EVERY end of turn, gated only by CanBeBurned/CanBePoisoned (the same
# immunity check a move would use). No turn counter exists in source at all;
# it only ever visibly fires once because the holder then HAS the status and
# StatusManager.try_apply_status's own "already has a status" gate blocks
# re-application. ItemManager.status_orb_status's signature has no turn
# parameter at all — structurally confirms it cannot be turn-gated.
#
# Confirmed NOT Unnerve-gated: Flame Orb/Toxic Orb are POCKET_ITEMS, not
# POCKET_BERRIES — IsUnnerveBlocked returns FALSE immediately for any
# non-berry item (confirmed via source, battle_util.c L333-343).
#
# Self-infliction reuses StatusManager.try_apply_status — the SAME function
# moves use — passing the holder as its own `attacker`, mirroring source's
# self-referential CanBeBurned(battler, battler, ability)/CanBePoisoned(battler,
# battler, ability, ability) call shape, so existing type immunities (Fire-type/
# burn, Poison-or-Steel-type/toxic) compose for free with zero new immunity
# logic — tested explicitly via discriminators below.
#
# Sections: I01 Flame Orb, I02 Toxic Orb.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_i01_flame_orb()
	_test_i02_toxic_orb()

	var total := _pass + _fail
	print("m18i_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


# ── Helpers (mirrors m18h_test.gd's established pattern) ───────────────────────

func _make_item(hold_effect: int) -> ItemData:
	var item := ItemData.new()
	item.hold_effect = hold_effect
	return item


func _make_mon(mon_name: String, type1: int, type2: int = TypeChart.TYPE_NONE) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types.append(type1)
	if type2 != TypeChart.TYPE_NONE:
		sp.types.append(type2)
	sp.base_hp         = 100
	sp.base_attack     = 60
	sp.base_defense    = 60
	sp.base_sp_attack  = 60
	sp.base_sp_defense = 60
	sp.base_speed      = 60
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])


func _make_move(move_name: String, move_type: int, category: int, power: int) -> MoveData:
	var m := MoveData.new()
	m.move_name        = move_name
	m.type             = move_type
	m.category         = category
	m.power            = power
	m.accuracy         = 100
	m.pp               = 40
	m.secondary_effect = MoveData.SE_NONE
	m.secondary_chance = 0
	m.two_turn         = false
	m.semi_inv_state   = MoveData.SEMI_INV_NONE
	m.stat_change_stat = -1
	return m


# ── I01: Flame Orb (445) — self-inflicts burn ───────────────────────────────
func _test_i01_flame_orb() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_FLAME_ORB)
	_chk("I01.01 Flame Orb hold_effect=FLAME_ORB(68)",
			item.hold_effect == ItemManager.HOLD_EFFECT_FLAME_ORB)

	var mon := _make_mon("I01_Mon", TypeChart.TYPE_NORMAL)
	mon.held_item = item
	_chk("I01.02 status_orb_status returns STATUS_BURN",
			ItemManager.status_orb_status(mon) == BattlePokemon.STATUS_BURN)

	var bare := _make_mon("I01_Bare", TypeChart.TYPE_NORMAL)
	_chk("I01.03 discriminator: holding nothing returns STATUS_NONE",
			ItemManager.status_orb_status(bare) == BattlePokemon.STATUS_NONE)

	# Direct unit confirmation: self-application via the SAME function moves
	# use, holder passed as its own attacker (mirrors source's self-referential
	# CanBeBurned call).
	var mon2 := _make_mon("I01_Mon2", TypeChart.TYPE_NORMAL)
	mon2.held_item = item
	var applied: bool = StatusManager.try_apply_status(mon2, BattlePokemon.STATUS_BURN,
			null, null, false, mon2)
	_chk("I01.04 direct: try_apply_status self-inflicts burn successfully",
			applied and mon2.status == BattlePokemon.STATUS_BURN)

	# CORRECTION-confirming discriminator: a Fire-type holder is IMMUNE to its
	# own Flame Orb — proves reuse of the real type-immunity check, not a bypass.
	var fire_mon := _make_mon("I01_FireMon", TypeChart.TYPE_FIRE)
	fire_mon.held_item = item
	var fire_applied: bool = StatusManager.try_apply_status(fire_mon, BattlePokemon.STATUS_BURN,
			null, null, false, fire_mon)
	_chk("I01.05 CORRECTION-confirming discriminator: a Fire-type holder is " +
			"IMMUNE to its own Flame Orb (same type immunity a move would hit)",
			not fire_applied and fire_mon.status == BattlePokemon.STATUS_NONE)

	# Full-battle: holder is NOT hit by anything status-related, confirms the
	# end-of-turn dispatch applies burn with no move involved at all.
	var battle_mon := _make_mon("I01_Battle", TypeChart.TYPE_NORMAL)
	battle_mon.held_item = item
	battle_mon.add_move(_make_move("I01_Tackle", TypeChart.TYPE_NORMAL, 0, 5))
	var opp := _make_mon("I01_Opp", TypeChart.TYPE_NORMAL)
	opp.add_move(_make_move("I01_OppTackle", TypeChart.TYPE_NORMAL, 0, 5))

	var bm := BattleManager.new()
	add_child(bm)
	bm._force_hit = true
	bm._force_crit = false
	bm.start_battle_with_parties(BattleParty.single(battle_mon), BattleParty.single(opp))
	_chk("I01.06 full-battle: Flame Orb burns the holder by end of turn 1, " +
			"with no move-based trigger at all",
			battle_mon.status == BattlePokemon.STATUS_BURN)
	bm.queue_free()


# ── I02: Toxic Orb (446) — self-inflicts badly-poisoned (STATUS_TOXIC) ─────────
func _test_i02_toxic_orb() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_TOXIC_ORB)
	_chk("I02.01 Toxic Orb hold_effect=TOXIC_ORB(69)",
			item.hold_effect == ItemManager.HOLD_EFFECT_TOXIC_ORB)

	var mon := _make_mon("I02_Mon", TypeChart.TYPE_NORMAL)
	mon.held_item = item
	_chk("I02.02 status_orb_status returns STATUS_TOXIC (badly poisoned), " +
			"NOT STATUS_POISON (regular poison)",
			ItemManager.status_orb_status(mon) == BattlePokemon.STATUS_TOXIC \
					and ItemManager.status_orb_status(mon) != BattlePokemon.STATUS_POISON)

	var bare := _make_mon("I02_Bare", TypeChart.TYPE_NORMAL)
	_chk("I02.03 discriminator: holding nothing returns STATUS_NONE",
			ItemManager.status_orb_status(bare) == BattlePokemon.STATUS_NONE)

	var mon2 := _make_mon("I02_Mon2", TypeChart.TYPE_NORMAL)
	mon2.held_item = item
	var applied: bool = StatusManager.try_apply_status(mon2, BattlePokemon.STATUS_TOXIC,
			null, null, false, mon2)
	_chk("I02.04 direct: try_apply_status self-inflicts STATUS_TOXIC, " +
			"toxic_counter initialized to 0 (first EOT tick increments to 1)",
			applied and mon2.status == BattlePokemon.STATUS_TOXIC and mon2.toxic_counter == 0)

	# CORRECTION-confirming discriminator: a Poison-type holder is IMMUNE to its
	# own Toxic Orb — proves reuse of the real type-immunity check.
	var poison_mon := _make_mon("I02_PoisonMon", TypeChart.TYPE_POISON)
	poison_mon.held_item = item
	var poison_applied: bool = StatusManager.try_apply_status(poison_mon, BattlePokemon.STATUS_TOXIC,
			null, null, false, poison_mon)
	_chk("I02.05 CORRECTION-confirming discriminator: a Poison-type holder is " +
			"IMMUNE to its own Toxic Orb",
			not poison_applied and poison_mon.status == BattlePokemon.STATUS_NONE)

	# A Steel-type holder is ALSO immune (same shared type-immunity gate as
	# regular poison — Poison OR Steel, not Poison-type-only).
	var steel_mon := _make_mon("I02_SteelMon", TypeChart.TYPE_STEEL)
	steel_mon.held_item = item
	var steel_applied: bool = StatusManager.try_apply_status(steel_mon, BattlePokemon.STATUS_TOXIC,
			null, null, false, steel_mon)
	_chk("I02.06 discriminator: a Steel-type holder is ALSO immune (shared " +
			"Poison-or-Steel gate, not Poison-type-only)",
			not steel_applied and steel_mon.status == BattlePokemon.STATUS_NONE)

	# Full-battle confirmation.
	var battle_mon := _make_mon("I02_Battle", TypeChart.TYPE_NORMAL)
	battle_mon.held_item = item
	battle_mon.add_move(_make_move("I02_Tackle", TypeChart.TYPE_NORMAL, 0, 5))
	var opp := _make_mon("I02_Opp", TypeChart.TYPE_NORMAL)
	opp.add_move(_make_move("I02_OppTackle", TypeChart.TYPE_NORMAL, 0, 5))

	var bm := BattleManager.new()
	add_child(bm)
	bm._force_hit = true
	bm._force_crit = false
	bm.start_battle_with_parties(BattleParty.single(battle_mon), BattleParty.single(opp))
	_chk("I02.07 full-battle: Toxic Orb badly-poisons the holder by end of turn 1",
			battle_mon.status == BattlePokemon.STATUS_TOXIC)
	bm.queue_free()
