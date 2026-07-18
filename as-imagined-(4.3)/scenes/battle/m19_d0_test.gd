extends Node

# [D0] Priority unblock: Leech Seed(73), Haze(114), Aromatherapy(312), Heal
# Bell(215) — resolves Bucket 4's M19-blocked-on-other-tier4 gate.
# Plus two "already-free" pairs confirmed by last session's Section D recon:
# Follow Me(266)/Rage Powder(476) (mechanism already built, M14b) and
# Soft-Boiled(135)/Milk Drink(208) (EFFECT_SOFTBOILED, identical to the
# already-implemented EFFECT_RESTORE_HP family).
# Plus the 3 moves M19-blocked-on-other-tier4 was itself gated on, now
# unblocked and trivially cheap: Sappy Seed(685), Freezy Frost(686),
# Sparkly Swirl(687).
#
# Ground truth: reference/pokeemerald_expansion/src/battle_script_commands.c
# (Cmd_setseeded L7061-7080, Cmd_normalisebuffs L7217-7224,
# Cmd_healpartystatus L8259-8340), src/battle_end_turn.c
# (HandleEndTurnLeechSeed L476-509), src/data/moves_info.h, GEN_LATEST config.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_data_integrity()
	_test_leech_seed_apply_unit()
	_test_leech_seed_eot_full_battle()
	_test_leech_seed_reciprocal_clear()
	_test_haze_full_battle()
	_test_heal_bell_party_wide()
	_test_heal_bell_soundproof_partner_asymmetry()
	_test_follow_me_rage_powder()
	_test_soft_boiled_milk_drink()
	_test_on_hit_secondaries()

	var total := _pass + _fail
	print("m19_d0_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


func _load_move(id: int) -> MoveData:
	return load("res://data/moves/move_%04d.tres" % id) as MoveData


func _load_item(id: int) -> ItemData:
	return load("res://data/items/item_%04d.tres" % id) as ItemData


func _load_ability(id: int) -> AbilityData:
	return load("res://data/abilities/ability_%04d.tres" % id) as AbilityData


func _make_mon(mon_name: String, types: Array[int], base_hp: int = 100, base_atk: int = 60,
		base_def: int = 60, base_spatk: int = 60, base_spdef: int = 60,
		base_spd: int = 60) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types = types
	sp.base_hp         = base_hp
	sp.base_attack     = base_atk
	sp.base_defense    = base_def
	sp.base_sp_attack  = base_spatk
	sp.base_sp_defense = base_spdef
	sp.base_speed      = base_spd
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])


func _make_bm() -> BattleManager:
	var bm := BattleManager.new()
	add_child(bm)
	return bm


func _doubles_party(m0: BattlePokemon, m1: BattlePokemon) -> BattleParty:
	var p := BattleParty.new()
	p.members = [m0, m1]
	p.active_indices.append(1)
	return p


# ── Section A: data integrity (all 11 moves) ────────────────────────────────

func _test_data_integrity() -> void:
	var leech_seed := _load_move(73)
	_chk("A.01 73 Leech Seed: Grass/status/acc90/pp10, is_leech_seed, bounceable, " +
			"NOT ignores_protect",
			leech_seed.type == TypeChart.TYPE_GRASS and leech_seed.accuracy == 90
					and leech_seed.pp == 10 and leech_seed.is_leech_seed
					and leech_seed.bounceable and not leech_seed.ignores_protect)

	var haze := _load_move(114)
	_chk("A.02 114 Haze: Ice/status/acc0/pp30, is_haze, ignores_protect",
			haze.type == TypeChart.TYPE_ICE and haze.accuracy == 0 and haze.pp == 30
					and haze.is_haze and haze.ignores_protect)

	var heal_bell := _load_move(215)
	_chk("A.03 215 Heal Bell: Normal/status/pp5, is_heal_bell, sound_move=TRUE",
			heal_bell.type == TypeChart.TYPE_NORMAL and heal_bell.pp == 5
					and heal_bell.is_heal_bell and heal_bell.sound_move)
	var aromatherapy := _load_move(312)
	_chk("A.04 312 Aromatherapy: Grass/status/pp5, is_heal_bell, NOT sound_move " +
			"(the key asymmetry with Heal Bell)",
			aromatherapy.type == TypeChart.TYPE_GRASS and aromatherapy.pp == 5
					and aromatherapy.is_heal_bell and not aromatherapy.sound_move)

	var follow_me := _load_move(266)
	_chk("A.05 266 Follow Me: Normal/status/pp20/prio2, is_follow_me, NOT powder_move",
			follow_me.type == TypeChart.TYPE_NORMAL and follow_me.pp == 20
					and follow_me.priority == 2 and follow_me.is_follow_me
					and not follow_me.powder_move)
	var rage_powder := _load_move(476)
	_chk("A.06 476 Rage Powder: Bug/status/pp20/prio2, is_follow_me, powder_move=TRUE " +
			"(the key asymmetry with Follow Me)",
			rage_powder.type == TypeChart.TYPE_BUG and rage_powder.pp == 20
					and rage_powder.priority == 2 and rage_powder.is_follow_me
					and rage_powder.powder_move)

	var soft_boiled := _load_move(135)
	_chk("A.07 135 Soft-Boiled: Normal/status/pp5, is_restore_hp, healing_move",
			soft_boiled.type == TypeChart.TYPE_NORMAL and soft_boiled.pp == 5
					and soft_boiled.is_restore_hp and soft_boiled.healing_move)
	var milk_drink := _load_move(208)
	_chk("A.08 208 Milk Drink: Normal/status/pp5, is_restore_hp, healing_move " +
			"(genuinely identical data to Soft-Boiled, confirmed individually)",
			milk_drink.type == TypeChart.TYPE_NORMAL and milk_drink.pp == 5
					and milk_drink.is_restore_hp and milk_drink.healing_move)

	var sappy_seed := _load_move(685)
	_chk("A.09 685 Sappy Seed: 100/90/10 Grass physical, is_leech_seed_on_hit",
			sappy_seed.power == 100 and sappy_seed.accuracy == 90 and sappy_seed.pp == 10
					and sappy_seed.type == TypeChart.TYPE_GRASS and sappy_seed.category == 0
					and sappy_seed.is_leech_seed_on_hit)
	var freezy_frost := _load_move(686)
	_chk("A.10 686 Freezy Frost: 100/90/10 Ice special, is_haze_on_hit",
			freezy_frost.power == 100 and freezy_frost.accuracy == 90 and freezy_frost.pp == 10
					and freezy_frost.type == TypeChart.TYPE_ICE and freezy_frost.category == 1
					and freezy_frost.is_haze_on_hit)
	var sparkly_swirl := _load_move(687)
	_chk("A.11 687 Sparkly Swirl: 120/85/5 Fairy special, is_heal_bell_on_hit",
			sparkly_swirl.power == 120 and sparkly_swirl.accuracy == 85 and sparkly_swirl.pp == 5
					and sparkly_swirl.type == TypeChart.TYPE_FAIRY and sparkly_swirl.category == 1
					and sparkly_swirl.is_heal_bell_on_hit)


# ── Section B: StatusManager.try_apply_leech_seed direct unit tests ─────────

func _test_leech_seed_apply_unit() -> void:
	var victim := _make_mon("B1Victim", [TypeChart.TYPE_NORMAL])
	var source := _make_mon("B1Source", [TypeChart.TYPE_NORMAL])
	_chk("B.01 first application succeeds",
			StatusManager.try_apply_leech_seed(victim, source) == true)
	_chk("B.02 leeched_by now points at the source",
			victim.leeched_by == source)

	var other_source := _make_mon("B2Other", [TypeChart.TYPE_NORMAL])
	_chk("B.03 discriminator: already-seeded is a no-op (returns false, does NOT " +
			"overwrite the existing source)",
			StatusManager.try_apply_leech_seed(victim, other_source) == false
					and victim.leeched_by == source)

	var grass_victim := _make_mon("B4GrassVictim", [TypeChart.TYPE_GRASS])
	_chk("B.04 discriminator: a Grass-type target is immune (own dedicated check, " +
			"NOT the general type-effectiveness gate)",
			StatusManager.try_apply_leech_seed(grass_victim, source) == false
					and grass_victim.leeched_by == null)


# ── Section C: Leech Seed — end-of-turn drain, full battle ──────────────────

func _test_leech_seed_eot_full_battle() -> void:
	var leech_seed := _load_move(73)
	var splash := MoveData.new()
	splash.move_name = "Splash"
	splash.type = TypeChart.TYPE_NORMAL
	splash.category = 2
	splash.accuracy = 0
	splash.pp = 40

	# (i) Ordinary drain tick: seeded mon loses maxHP/8, seeder heals the same amount.
	var atk := _make_mon("C1Atk", [TypeChart.TYPE_GRASS], 200, 60, 60, 60, 60, 100)
	atk.add_move(leech_seed)
	atk.current_hp = 50
	var def := _make_mon("C1Def", [TypeChart.TYPE_WATER], 200, 10, 60, 10, 60, 40)
	def.add_move(splash)
	var bm := _make_bm()
	var drained := [false, -1, -1]
	bm.leech_seed_drained.connect(func(target, source, amount):
		if not drained[0]:
			drained[0] = true
			drained[1] = target.current_hp
			drained[2] = amount)
	bm.queue_move(1, 0)
	bm.start_battle_with_parties(BattleParty.single(atk), BattleParty.single(def))
	var expected_drain: int = max(1, def.max_hp / 8)
	_chk("C.01 Leech Seed's end-of-turn tick drains maxHP/8 from the seeded mon and " +
			"heals the seeder by the same amount (expected drain=%d, event=%s)" \
					% [expected_drain, drained],
			drained[0] == true and drained[2] == expected_drain)

	# (ii) Big Root boosts the SEEDER's heal (a real correction to [M18q]'s own
	# "move-drain only" scope note — confirmed at Step 0 this session).
	var atk2 := _make_mon("C2Atk", [TypeChart.TYPE_GRASS], 200, 60, 60, 60, 60, 100)
	atk2.add_move(leech_seed)
	atk2.current_hp = 50
	atk2.held_item = _load_item(491)  # Big Root
	var def2 := _make_mon("C2Def", [TypeChart.TYPE_WATER], 200, 10, 60, 10, 60, 40)
	def2.add_move(splash)
	var bm2 := _make_bm()
	var drained2 := [false, -1]
	bm2.leech_seed_drained.connect(func(_t, _s, amount):
		if not drained2[0]:
			drained2[0] = true
			drained2[1] = amount)
	bm2.queue_move(1, 0)
	bm2.start_battle_with_parties(BattleParty.single(atk2), BattleParty.single(def2))
	var expected_boosted: int = max(1, def2.max_hp / 8) * 1300 / 1000
	_chk("C.02 Big Root boosts the seeder's heal to 130%% (expected=%d, got=%s)" \
					% [expected_boosted, drained2],
			drained2[0] == true and drained2[1] == expected_boosted)

	# (iii) Liquid Ooze on the SEEDED mon inverts the seeder's heal into damage of
	# the same amount.
	var atk3 := _make_mon("C3Atk", [TypeChart.TYPE_GRASS], 200, 60, 60, 60, 60, 100)
	atk3.add_move(leech_seed)
	var def3 := _make_mon("C3Def", [TypeChart.TYPE_WATER], 200, 10, 60, 10, 60, 40)
	def3.add_move(splash)
	def3.ability = _load_ability(64)  # Liquid Ooze
	var bm3 := _make_bm()
	bm3.queue_move(1, 0)
	bm3.start_battle_with_parties(BattleParty.single(atk3), BattleParty.single(def3))
	_chk("C.03 discriminator: Liquid Ooze on the SEEDED mon inverts the seeder's " +
			"heal into damage — the seeder ends up damaged, not healed " +
			"(atk3.current_hp=%d, max=%d)" % [atk3.current_hp, atk3.max_hp],
			atk3.current_hp < atk3.max_hp)

	# (iv) Magic Guard on the SEEDED mon blocks the whole tick — no damage to the
	# seeded mon AND no heal to the seeder.
	var atk4 := _make_mon("C4Atk", [TypeChart.TYPE_GRASS], 200, 60, 60, 60, 60, 100)
	atk4.add_move(leech_seed)
	atk4.current_hp = 50
	var def4 := _make_mon("C4Def", [TypeChart.TYPE_WATER], 200, 10, 60, 10, 60, 40)
	def4.add_move(splash)
	def4.ability = _load_ability(98)  # Magic Guard
	var bm4 := _make_bm()
	var drained4 := [false]
	bm4.leech_seed_drained.connect(func(_t, _s, _a): drained4[0] = true)
	bm4.queue_move(1, 0)
	bm4.start_battle_with_parties(BattleParty.single(atk4), BattleParty.single(def4))
	_chk("C.04 Magic Guard on the seeded mon blocks the entire tick (no drain event " +
			"fired at all)",
			drained4[0] == false)


func _test_leech_seed_reciprocal_clear() -> void:
	var source := _make_mon("D1Source", [TypeChart.TYPE_NORMAL])
	var victim := _make_mon("D1Victim", [TypeChart.TYPE_NORMAL])
	victim.leeched_by = source
	var bm := _make_bm()
	bm._combatants = [victim, source]
	bm._clear_volatiles(source)  # the SOURCE leaves, not the victim
	_chk("D.01 the SOURCE battler leaving the field cures the VICTIM's leeched_by",
			victim.leeched_by == null)

	var source2 := _make_mon("D2Source", [TypeChart.TYPE_NORMAL])
	var victim2 := _make_mon("D2Victim", [TypeChart.TYPE_NORMAL])
	var bystander2 := _make_mon("D2Bystander", [TypeChart.TYPE_NORMAL])
	victim2.leeched_by = source2
	var bm2 := _make_bm()
	bm2._combatants = [victim2, source2, bystander2]
	bm2._clear_volatiles(bystander2)
	_chk("D.02 discriminator: an unrelated third battler leaving does NOT cure the seed",
			victim2.leeched_by == source2)

	var source3 := _make_mon("D3Source", [TypeChart.TYPE_NORMAL])
	var victim3 := _make_mon("D3Victim", [TypeChart.TYPE_NORMAL])
	victim3.leeched_by = source3
	var bm3 := _make_bm()
	bm3._combatants = [victim3, source3]
	bm3._clear_volatiles(victim3)  # the VICTIM's own departure
	_chk("D.03 the victim's own departure clears its own leeched_by",
			victim3.leeched_by == null)


# ── Section E: Haze — both-sides scope discriminator vs Clear Smog ──────────

func _test_haze_full_battle() -> void:
	var haze := _load_move(114)
	var swords_dance := MoveData.new()
	swords_dance.move_name = "Swords Dance"
	swords_dance.type = TypeChart.TYPE_NORMAL
	swords_dance.category = 2
	swords_dance.accuracy = 0
	swords_dance.pp = 20
	swords_dance.stat_change_stat = 0  # STAGE_ATK
	swords_dance.stat_change_amount = 2
	swords_dance.stat_change_self = true

	var atk := _make_mon("E1Atk", [TypeChart.TYPE_ICE], 100, 60, 60, 60, 60, 40)
	atk.add_move(haze)
	atk.stat_stages[0] = 3  # attacker's OWN Attack stage, pre-set
	var def := _make_mon("E1Def", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 100)
	def.add_move(swords_dance)
	var bm := _make_bm()
	var events := []
	bm.stat_stage_changed.connect(func(mon, stat, delta): events.push_back([mon, stat, delta]))
	bm.queue_move(1, 0)  # atk uses Haze on turn 1 (def is faster, uses Swords Dance first)
	bm.start_battle_with_parties(BattleParty.single(atk), BattleParty.single(def))
	_chk("E.01 Haze resets the ATTACKER'S OWN stat stage too, not just the target's " +
			"(a real both-sides scope, unlike Clear Smog's single-target reset) — " +
			"atk.stat_stages[0]=%d" % [atk.stat_stages[0]],
			atk.stat_stages[0] == 0)
	_chk("E.02 Haze ALSO resets the opponent's stat stage from Swords Dance " +
			"(def.stat_stages[0]=%d)" % [def.stat_stages[0]],
			def.stat_stages[0] == 0)


# ── Section F: Heal Bell / Aromatherapy — party-wide cure ───────────────────

func _test_heal_bell_party_wide() -> void:
	var heal_bell := _load_move(215)
	var splash := MoveData.new()
	splash.move_name = "Splash"
	splash.type = TypeChart.TYPE_NORMAL
	splash.category = 2
	splash.accuracy = 0
	splash.pp = 40

	var healer := _make_mon("F1Healer", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 100)
	healer.add_move(heal_bell)
	healer.status = BattlePokemon.STATUS_PARALYSIS
	var bench := _make_mon("F1Bench", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 60)
	bench.status = BattlePokemon.STATUS_BURN
	var opp := _make_mon("F1Opp", [TypeChart.TYPE_NORMAL], 100, 10, 60, 10, 60, 40)
	opp.add_move(splash)

	var cured := []
	var bm := _make_bm()
	bm.party_status_cured.connect(func(mon): cured.push_back(mon))
	var own_party := BattleParty.new()
	own_party.members = [healer, bench]
	bm.queue_move(1, 0)
	bm.start_battle_with_parties(own_party, BattleParty.single(opp))
	_chk("F.01 Heal Bell cures the ACTIVE healer's own status",
			healer.status == BattlePokemon.STATUS_NONE)
	_chk("F.02 Heal Bell ALSO cures a BENCH member's status — genuinely party-wide, " +
			"not just the active battler (bench.status=%d)" % [bench.status],
			bench.status == BattlePokemon.STATUS_NONE)
	_chk("F.03 both cures fired the party_status_cured signal",
			cured.any(func(m): return m == healer) and cured.any(func(m): return m == bench))


func _test_heal_bell_soundproof_partner_asymmetry() -> void:
	var heal_bell := _load_move(215)
	var aromatherapy := _load_move(312)
	var splash := MoveData.new()
	splash.move_name = "Splash"
	splash.type = TypeChart.TYPE_NORMAL
	splash.category = 2
	splash.accuracy = 0
	splash.pp = 40

	# (i) Heal Bell (a sound move): the healer itself is cured UNCONDITIONALLY
	# (bypasses its own Soundproof, Gen9 rule), but its DOUBLES PARTNER holding
	# Soundproof is NOT cured — the one case where Soundproof can actually block
	# this move at this project's GEN_LATEST config.
	var healer := _make_mon("G1Healer", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 100)
	healer.add_move(heal_bell)
	healer.status = BattlePokemon.STATUS_PARALYSIS
	healer.ability = _load_ability(43)  # Soundproof, on the healer itself
	var partner := _make_mon("G1Partner", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 90)
	partner.status = BattlePokemon.STATUS_BURN
	partner.ability = _load_ability(43)  # Soundproof, on the doubles partner
	partner.add_move(splash)
	var opp0 := _make_mon("G1Opp0", [TypeChart.TYPE_NORMAL], 100, 10, 60, 10, 60, 40)
	opp0.add_move(splash)
	var opp1 := _make_mon("G1Opp1", [TypeChart.TYPE_NORMAL], 100, 10, 60, 10, 60, 40)
	opp1.add_move(splash)

	var bm := _make_bm()
	bm.queue_move(1, 0)
	bm.start_battle_doubles(_doubles_party(healer, partner), _doubles_party(opp0, opp1))
	_chk("G.01 Heal Bell cures the HEALER ITSELF even though it holds Soundproof " +
			"(Gen9 rule: always affects the user)",
			healer.status == BattlePokemon.STATUS_NONE)
	_chk("G.02 discriminator: Heal Bell does NOT cure its DOUBLES PARTNER, which " +
			"holds Soundproof and Heal Bell IS a sound move (partner.status=%d)" \
					% [partner.status],
			partner.status == BattlePokemon.STATUS_BURN)

	# (ii) Aromatherapy (NOT a sound move): the same Soundproof-holding partner
	# IS cured this time — the key same-effect-different-flag asymmetry.
	var healer2 := _make_mon("G2Healer", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 100)
	healer2.add_move(aromatherapy)
	var partner2 := _make_mon("G2Partner", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 90)
	partner2.status = BattlePokemon.STATUS_BURN
	partner2.ability = _load_ability(43)  # Soundproof
	partner2.add_move(splash)
	var opp2 := _make_mon("G2Opp0", [TypeChart.TYPE_NORMAL], 100, 10, 60, 10, 60, 40)
	opp2.add_move(splash)
	var opp3 := _make_mon("G2Opp1", [TypeChart.TYPE_NORMAL], 100, 10, 60, 10, 60, 40)
	opp3.add_move(splash)

	var bm2 := _make_bm()
	bm2.queue_move(1, 0)
	bm2.start_battle_doubles(_doubles_party(healer2, partner2), _doubles_party(opp2, opp3))
	_chk("G.03 discriminator: Aromatherapy (NOT a sound move) DOES cure a " +
			"Soundproof-holding doubles partner — the exact asymmetry with Heal " +
			"Bell above (partner2.status=%d)" % [partner2.status],
			partner2.status == BattlePokemon.STATUS_NONE)


# ── Section H: Follow Me / Rage Powder ───────────────────────────────────────

func _test_follow_me_rage_powder() -> void:
	var follow_me := _load_move(266)
	var tackle := _load_move(33)

	# (i) Confirm the already-built redirect mechanism fires against the real
	# Follow Me data entry (the mechanism itself is already proven by [M14b]/
	# [M17l]'s own suites — this just confirms the new data wires into it).
	var fm_user := _make_mon("H1FMUser", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 100)
	fm_user.add_move(follow_me)
	var fm_ally := _make_mon("H1FMAlly", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 40)
	fm_ally.add_move(tackle)
	var opp0 := _make_mon("H1Opp0", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 50)
	opp0.add_move(tackle)
	var opp1 := _make_mon("H1Opp1", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 50)
	opp1.add_move(tackle)

	var used := [false]
	var bm := _make_bm()
	bm.follow_me_used.connect(func(_u): used[0] = true)
	bm.queue_move(1, 0)
	bm.start_battle_doubles(_doubles_party(fm_user, fm_ally), _doubles_party(opp0, opp1))
	_chk("H.01 Follow Me's real data entry fires the existing follow_me_used dispatch",
			used[0] == true)

	# (ii) Rage Powder is blocked outright for a Grass-type user (powder_move=TRUE,
	# self-targeted, so the existing blocks_move_flag gate resolves defender==
	# attacker and correctly blocks it — zero new code, confirmed at Step 0).
	var rage_powder := _load_move(476)
	var rp_user := _make_mon("H2RPUser", [TypeChart.TYPE_GRASS], 100, 60, 60, 60, 60, 100)
	rp_user.add_move(rage_powder)
	var rp_ally := _make_mon("H2RPAlly", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 40)
	rp_ally.add_move(tackle)
	var opp2 := _make_mon("H2Opp0", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 50)
	opp2.add_move(tackle)
	var opp3 := _make_mon("H2Opp1", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 50)
	opp3.add_move(tackle)

	var used2 := [false]
	var blocked2 := [false]
	var bm2 := _make_bm()
	bm2.follow_me_used.connect(func(_u): used2[0] = true)
	bm2.move_effect_failed.connect(func(mon, reason):
		if mon == rp_user and reason == "move_flag_blocked":
			blocked2[0] = true)
	bm2.queue_move(1, 0)
	bm2.start_battle_doubles(_doubles_party(rp_user, rp_ally), _doubles_party(opp2, opp3))
	_chk("H.02 discriminator: a Grass-type user's Rage Powder is blocked outright " +
			"(the general powder-move immunity gate, reused for free)",
			blocked2[0] == true and used2[0] == false)


# ── Section I: Soft-Boiled / Milk Drink ──────────────────────────────────────

func _test_soft_boiled_milk_drink() -> void:
	var soft_boiled := _load_move(135)
	var milk_drink := _load_move(208)
	var tackle := _load_move(33)

	for pair in [["I1", soft_boiled], ["I2", milk_drink]]:
		var prefix: String = pair[0]
		var move: MoveData = pair[1]
		var atk := _make_mon(prefix + "Atk", [TypeChart.TYPE_NORMAL], 200, 60, 60, 60, 60, 100)
		atk.add_move(move)
		atk.current_hp = 50
		var def := _make_mon(prefix + "Def", [TypeChart.TYPE_NORMAL], 200, 10, 60, 10, 60, 40)
		def.add_move(tackle)
		var bm := _make_bm()
		var healed := [false, -1]
		bm.drain_heal.connect(func(mon, amt):
			if mon == atk and not healed[0]:
				healed[0] = true
				healed[1] = amt)
		bm.start_battle(atk, def)
		var expected: int = max(1, atk.max_hp / 2)
		_chk("%s.01 %s heals exactly max_hp/2 through the real dispatch (expected=%d, got=%s)" \
						% [prefix, move.move_name, expected, healed],
				healed[0] == true and healed[1] == expected)


# ── Section J: Sappy Seed / Freezy Frost / Sparkly Swirl — on-hit secondaries ─

func _test_on_hit_secondaries() -> void:
	var sappy_seed := _load_move(685)
	var freezy_frost := _load_move(686)
	var sparkly_swirl := _load_move(687)
	var splash := MoveData.new()
	splash.move_name = "Splash"
	splash.type = TypeChart.TYPE_NORMAL
	splash.category = 2
	splash.accuracy = 0
	splash.pp = 40

	# (i) Sappy Seed: damage AND Leech Seed on the target, in one hit.
	var atk := _make_mon("J1Atk", [TypeChart.TYPE_GRASS], 100, 100, 60, 60, 60, 100)
	atk.add_move(sappy_seed)
	var def := _make_mon("J1Def", [TypeChart.TYPE_WATER], 300, 60, 60, 60, 60, 40)
	def.add_move(splash)
	var bm := _make_bm()
	bm._force_hit = true
	var seeded := [false]
	bm.leech_seeded.connect(func(target, _source):
		if target == def:
			seeded[0] = true)
	var damaged := [false, -1]
	bm.move_executed.connect(func(a, _d, _m, amt):
		if a == atk and not damaged[0]:
			damaged[0] = true
			damaged[1] = amt)
	bm.start_battle(atk, def)
	_chk("J.01 Sappy Seed deals real damage AND seeds the target in one hit " +
			"(damage=%s, seeded=%s)" % [damaged, seeded],
			damaged[0] == true and damaged[1] > 0 and seeded[0] == true)

	# (ii) Freezy Frost: damage AND resets EVERY battler's stat stages, including
	# the attacker's own (the same both-sides scope as Haze itself).
	var atk2 := _make_mon("J2Atk", [TypeChart.TYPE_ICE], 100, 100, 60, 60, 60, 100)
	atk2.add_move(freezy_frost)
	atk2.stat_stages[0] = 2
	var def2 := _make_mon("J2Def", [TypeChart.TYPE_NORMAL], 300, 60, 60, 60, 60, 40)
	def2.stat_stages[1] = -1
	def2.add_move(splash)
	var bm2 := _make_bm()
	bm2._force_hit = true
	bm2.start_battle(atk2, def2)
	_chk("J.02 Freezy Frost's on-hit Haze secondary resets the ATTACKER'S OWN " +
			"stat stage too (atk2.stat_stages[0]=%d)" % [atk2.stat_stages[0]],
			atk2.stat_stages[0] == 0)
	_chk("J.03 Freezy Frost ALSO resets the target's stat stage (def2.stat_stages[1]=%d)" \
					% [def2.stat_stages[1]],
			def2.stat_stages[1] == 0)

	# (iii) Sparkly Swirl: damage dealt to the TARGET, but the cure applies to the
	# ATTACKER'S OWN party (a bench member), matching source's own gBattlerAttacker
	# scoping regardless of the move's `.self` flag.
	var atk3 := _make_mon("J3Atk", [TypeChart.TYPE_FAIRY], 100, 100, 60, 60, 60, 100)
	atk3.add_move(sparkly_swirl)
	var atk3_bench := _make_mon("J3AtkBench", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 60)
	atk3_bench.status = BattlePokemon.STATUS_BURN
	var def3 := _make_mon("J3Def", [TypeChart.TYPE_WATER], 300, 60, 60, 60, 60, 40)
	def3.add_move(splash)
	var bm3 := _make_bm()
	bm3._force_hit = true
	var own_party3 := BattleParty.new()
	own_party3.members = [atk3, atk3_bench]
	bm3.start_battle_with_parties(own_party3, BattleParty.single(def3))
	_chk("J.04 Sparkly Swirl's on-hit Aromatherapy secondary cures the ATTACKER'S " +
			"OWN bench member, even though the move damages an opponent " +
			"(atk3_bench.status=%d)" % [atk3_bench.status],
			atk3_bench.status == BattlePokemon.STATUS_NONE)
