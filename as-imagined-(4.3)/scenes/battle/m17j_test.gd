extends Node

# M17j test suite — Item-transfer primitive (new infrastructure): Pickpocket, Sticky
# Hold, Magician, Symbiosis.
#
# Scope: the 4 abilities locked in docs/decisions.md [M17j] (Step 0 re-verified all four
# IDs against Section 13's exclusion sweep — none needed correction):
#   Sticky Hold (60)  — passive; BLOCKS item removal (not a transfer trigger itself),
#                        gates the shared steal primitive Pickpocket/Magician both use.
#   Pickpocket  (124) — on being hit by a contact move, steals the ATTACKER's item, if
#                        the holder itself has none.
#   Magician    (170) — on landing ANY damaging hit (contact NOT required — verified
#                        from source), steals the TARGET's item, if the holder itself
#                        has none. Genuinely attacker-keyed, unlike every existing entry
#                        in try_contact_effects/try_hit_reactive_effects.
#   Symbiosis   (180) — passive, doubles-only; when an ally's held item is removed by
#                        ANY means, gives its own item to that ally.
#
# New infrastructure: AbilityManager._try_steal_item(stealer, victim, ng_active) is the
# shared low-level primitive (mirrors source's StealTargetItem) that both Pickpocket's
# inline branch in try_contact_effects and try_magician() call into — Sticky Hold's
# block lives in exactly this one place, not duplicated per-ability. Symbiosis uses a
# separate one-directional "give" primitive (mirrors source's BestowItem) since Sticky
# Hold does NOT gate a voluntary give — see try_symbiosis's doc comment.
#
# Source-verified correction worth flagging: the natural (and this tier's own task)
# framing of the Sticky-Hold-blocks-Pickpocket test as "Sticky Hold as the DEFENDER
# against an attacking Pickpocket holder" doesn't match source's actual mechanic —
# Pickpocket's holder is ALWAYS the one hit (the defender role, reacting to a contact
# hit), stealing FROM whoever attacked it. So the real test setup is: Sticky Hold on the
# ATTACKER (protecting the attacker's own item from the Pickpocket-holding DEFENDER that
# just hit it), confirmed directly from battle_move_resolution.c L3944-3984 and tested
# accordingly in Section 6 below.
#
# Sticky Hold correctly carries breakable=true (source-verified, src/data/abilities.h
# L459-465), but this has no reachable consumer among these four abilities' own
# dispatches in this project — Mold-Breaker-bypasses-Sticky-Hold requires the CURRENT
# move's attacker to itself hold Mold Breaker while a DIFFERENT battler holds Sticky
# Hold, which can't happen through Pickpocket/Magician's own triggers (each occupies its
# own holder's one ability slot). This would only become reachable once a Knock-Off/
# Thief/Covet-style MOVE exists — none does yet in this project's roster (confirmed via
# grep) — so this interaction is untested-but-implemented, not silently dropped.
#
# Testing conventions applied throughout (CLAUDE.md):
#   - Signal-snapshot, not post-battle state.
#   - Array-wrapper for any lambda reporting a scalar back to the enclosing test function.
#   - Type immunity precedes ability logic: Section 3's Magician-vs-0x-effectiveness test
#     uses a real DamageCalculator.calculate() call (Ground-type Earthquake vs a
#     Flying-type defender) rather than just passing damage=0 manually, so the test
#     actually exercises the early-return path, not just asserts a hardcoded value.
#
# Ground truth: pokeemerald_expansion src/battle_move_resolution.c :: MoveEndPickpocket
#   (L3944-3984); src/battle_util.c :: ABILITY_MAGICIAN case (L4399-4465),
#   TryTriggerSymbiosis/TrySymbiosis (L9962-9990), BestowItem (L9998-10011);
#   src/battle_script_commands.c :: StealTargetItem (L2055-2087).

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_section_1_ability_data()
	_test_section_2_pickpocket_unit()
	_test_section_3_magician_unit()
	_test_section_4_symbiosis_unit()
	_test_section_5_pickpocket_full_battle()
	_test_section_6_sticky_hold_blocks_pickpocket_full_battle()
	_test_section_7_magician_full_battle()
	_test_section_8_symbiosis_full_battle_doubles()
	_test_section_9_neutralizing_gas_suppression()
	_test_section_10_multitype_plate_exclusion()

	var total := _pass + _fail
	print("m17j_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL: " + label)


func _load_ability(id: int) -> AbilityData:
	return load("res://data/abilities/ability_%04d.tres" % id) as AbilityData


func _load_move(id: int) -> MoveData:
	return load("res://data/moves/move_%04d.tres" % id) as MoveData


func _make_item(name: String) -> ItemData:
	var item := ItemData.new()
	item.item_name = name
	return item


func _make_mon(mon_name: String, types: Array[int], hp: int = 100, atk: int = 80,
		def_stat: int = 80, spatk: int = 80, spdef: int = 80, spd: int = 80) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types = types
	sp.base_hp = hp
	sp.base_attack = atk
	sp.base_defense = def_stat
	sp.base_sp_attack = spatk
	sp.base_sp_defense = spdef
	sp.base_speed = spd
	return BattlePokemon.from_species(sp, 50)


func _doubles_party(m0: BattlePokemon, m1: BattlePokemon) -> BattleParty:
	var p := BattleParty.new()
	p.members = [m0, m1]
	p.active_indices.append(1)
	return p


# ── Section 1: Ability data spot-checks ──────────────────────────────────────

func _test_section_1_ability_data() -> void:
	var sticky_hold := _load_ability(60)
	_chk("S1.01 Sticky Hold id=60", sticky_hold.ability_id == 60)
	_chk("S1.02 Sticky Hold breakable=true (source-verified, no reachable consumer yet)",
			sticky_hold.breakable)
	_chk("S1.03 Sticky Hold has no other cant_be_* flags",
			not sticky_hold.cant_be_copied and not sticky_hold.cant_be_swapped
			and not sticky_hold.cant_be_traced and not sticky_hold.cant_be_suppressed
			and not sticky_hold.cant_be_overwritten)

	var pickpocket := _load_ability(124)
	_chk("S1.04 Pickpocket id=124", pickpocket.ability_id == 124)
	_chk("S1.05 Pickpocket has no cant_be_*/breakable flags",
			not pickpocket.cant_be_suppressed and not pickpocket.breakable)

	var magician := _load_ability(170)
	_chk("S1.06 Magician id=170", magician.ability_id == 170)
	_chk("S1.07 Magician has no cant_be_*/breakable flags",
			not magician.cant_be_suppressed and not magician.breakable)

	var symbiosis := _load_ability(180)
	_chk("S1.08 Symbiosis id=180", symbiosis.ability_id == 180)
	_chk("S1.09 Symbiosis has no cant_be_*/breakable flags",
			not symbiosis.cant_be_suppressed and not symbiosis.breakable)


# ── Section 2: Pickpocket — direct unit tests (via try_contact_effects) ─────

func _test_section_2_pickpocket_unit() -> void:
	var tackle := _load_move(33)
	var flamethrower := _load_move(53)
	var pickpocket := _load_ability(124)
	var intimidate := _load_ability(22)

	# (i) Ordinary steal on a damaging contact hit.
	var holder_i := _make_mon("PPHolder1", [TypeChart.TYPE_NORMAL])
	holder_i.ability = pickpocket
	var attacker_i := _make_mon("PPAttacker1", [TypeChart.TYPE_NORMAL])
	attacker_i.held_item = _make_item("Leftovers")

	var result_i: Dictionary = AbilityManager.try_contact_effects(attacker_i, holder_i, tackle, 10)
	_chk("S2.01 Pickpocket steals on a damaging contact hit", result_i["pickpocket_stole"])
	_chk("S2.02 holder now has the attacker's item",
			holder_i.held_item != null and holder_i.held_item.item_name == "Leftovers")
	_chk("S2.03 attacker's item is now null", attacker_i.held_item == null)

	# (ii) Does NOT trigger if the Pickpocket holder already has an item.
	var holder_ii := _make_mon("PPHolder2", [TypeChart.TYPE_NORMAL])
	holder_ii.ability = pickpocket
	holder_ii.held_item = _make_item("OwnItem")
	var attacker_ii := _make_mon("PPAttacker2", [TypeChart.TYPE_NORMAL])
	attacker_ii.held_item = _make_item("Leftovers")
	var result_ii: Dictionary = AbilityManager.try_contact_effects(attacker_ii, holder_ii, tackle, 10)
	_chk("S2.04 Pickpocket does NOT steal when the holder already has an item",
			not result_ii["pickpocket_stole"])
	_chk("S2.05 attacker's item is unchanged",
			attacker_ii.held_item != null and attacker_ii.held_item.item_name == "Leftovers")

	# (iii) Does NOT trigger on a non-contact move.
	var holder_iii := _make_mon("PPHolder3", [TypeChart.TYPE_NORMAL])
	holder_iii.ability = pickpocket
	var attacker_iii := _make_mon("PPAttacker3", [TypeChart.TYPE_NORMAL])
	attacker_iii.held_item = _make_item("Leftovers")
	var result_iii: Dictionary = AbilityManager.try_contact_effects(
			attacker_iii, holder_iii, flamethrower, 10)
	_chk("S2.06 Pickpocket does NOT trigger on a non-contact move",
			not result_iii["pickpocket_stole"])

	# (iv) Does NOT trigger when damage is 0.
	var holder_iv := _make_mon("PPHolder4", [TypeChart.TYPE_NORMAL])
	holder_iv.ability = pickpocket
	var attacker_iv := _make_mon("PPAttacker4", [TypeChart.TYPE_NORMAL])
	attacker_iv.held_item = _make_item("Leftovers")
	var result_iv: Dictionary = AbilityManager.try_contact_effects(attacker_iv, holder_iv, tackle, 0)
	_chk("S2.07 Pickpocket does NOT trigger when damage is 0", not result_iv["pickpocket_stole"])

	# (v) Attacker has no item: no-op, non-Pickpocket-holder: no-op.
	var holder_v := _make_mon("PPHolder5", [TypeChart.TYPE_NORMAL])
	holder_v.ability = pickpocket
	var attacker_v := _make_mon("PPAttacker5", [TypeChart.TYPE_NORMAL])
	var result_v: Dictionary = AbilityManager.try_contact_effects(attacker_v, holder_v, tackle, 10)
	_chk("S2.08 Pickpocket does NOT trigger when the attacker has no item",
			not result_v["pickpocket_stole"])

	var non_holder := _make_mon("NonPPHolder", [TypeChart.TYPE_NORMAL])
	non_holder.ability = intimidate
	var attacker_vi := _make_mon("PPAttacker6", [TypeChart.TYPE_NORMAL])
	attacker_vi.held_item = _make_item("Leftovers")
	var result_vi: Dictionary = AbilityManager.try_contact_effects(attacker_vi, non_holder, tackle, 10)
	_chk("S2.09 non-Pickpocket-holder: no-op", not result_vi["pickpocket_stole"])


# ── Section 3: Magician — direct unit tests ──────────────────────────────────

func _test_section_3_magician_unit() -> void:
	var tackle := _load_move(33)
	var flamethrower := _load_move(53)
	var earthquake := _load_move(89)
	var magician := _load_ability(170)

	# (i) Ordinary steal on a damaging hit — non-contact move works too.
	var attacker_i := _make_mon("MagAtk1", [TypeChart.TYPE_NORMAL])
	attacker_i.ability = magician
	var target_i := _make_mon("MagTarget1", [TypeChart.TYPE_NORMAL])
	target_i.held_item = _make_item("Sitrus Berry")

	_chk("S3.01 Magician steals on a non-contact damaging hit",
			AbilityManager.try_magician(attacker_i, target_i, 10))
	_chk("S3.02 attacker now has the target's item",
			attacker_i.held_item != null and attacker_i.held_item.item_name == "Sitrus Berry")
	_chk("S3.03 target's item is now null", target_i.held_item == null)

	# (ii) Does NOT trigger if the Magician holder already has an item.
	var attacker_ii := _make_mon("MagAtk2", [TypeChart.TYPE_NORMAL])
	attacker_ii.ability = magician
	attacker_ii.held_item = _make_item("OwnItem")
	var target_ii := _make_mon("MagTarget2", [TypeChart.TYPE_NORMAL])
	target_ii.held_item = _make_item("Sitrus Berry")
	_chk("S3.04 Magician does NOT steal when the holder already has an item",
			not AbilityManager.try_magician(attacker_ii, target_ii, 10))

	# (iii) Does NOT trigger when damage is 0 (e.g. a miss).
	var attacker_iii := _make_mon("MagAtk3", [TypeChart.TYPE_NORMAL])
	attacker_iii.ability = magician
	var target_iii := _make_mon("MagTarget3", [TypeChart.TYPE_NORMAL])
	target_iii.held_item = _make_item("Sitrus Berry")
	_chk("S3.05 Magician does NOT trigger when damage is 0",
			not AbilityManager.try_magician(attacker_iii, target_iii, 0))

	# (iv) Does NOT trigger when the target has no item.
	var attacker_iv := _make_mon("MagAtk4", [TypeChart.TYPE_NORMAL])
	attacker_iv.ability = magician
	var target_iv := _make_mon("MagTarget4", [TypeChart.TYPE_NORMAL])
	_chk("S3.06 Magician does NOT trigger when the target has no item",
			not AbilityManager.try_magician(attacker_iv, target_iv, 10))

	# (v) Non-Magician-holder: no-op.
	var non_holder := _make_mon("NonMagHolder", [TypeChart.TYPE_NORMAL])
	var target_v := _make_mon("MagTarget5", [TypeChart.TYPE_NORMAL])
	target_v.held_item = _make_item("Sitrus Berry")
	_chk("S3.07 non-Magician-holder: no-op", not AbilityManager.try_magician(non_holder, target_v, 10))

	# (vi) Type-immunity-precedes-ability-logic: a real 0x-effectiveness hit (Ground-type
	# Earthquake vs a Flying-type defender) must deal 0 damage via the actual
	# DamageCalculator, and Magician must not fire off that 0 damage — not a hand-set
	# damage=0 stand-in, the real early-return path.
	var attacker_vi := _make_mon("MagAtk6", [TypeChart.TYPE_NORMAL], 100, 100)
	attacker_vi.ability = magician
	var flying_target := _make_mon("MagFlyingTarget", [TypeChart.TYPE_FLYING], 100, 60, 60)
	flying_target.held_item = _make_item("Sitrus Berry")
	var calc_result: Dictionary = DamageCalculator.calculate(attacker_vi, flying_target, earthquake, 100, false)
	_chk("S3.08 Ground-type Earthquake deals 0 damage to a Flying-type defender (baseline check)",
			calc_result["damage"] == 0)
	_chk("S3.09 Magician does NOT steal off a 0x-effectiveness (0 damage) hit",
			not AbilityManager.try_magician(attacker_vi, flying_target, calc_result["damage"]))
	_chk("S3.10 the Flying-type target's item is untouched",
			flying_target.held_item != null and flying_target.held_item.item_name == "Sitrus Berry")


# ── Section 4: Symbiosis — direct unit tests ─────────────────────────────────

func _test_section_4_symbiosis_unit() -> void:
	var symbiosis := _load_ability(180)
	var intimidate := _load_ability(22)

	# (i) Ordinary case: ally gives its item to the now-itemless mon.
	var mon_i := _make_mon("SymMon1", [TypeChart.TYPE_NORMAL])
	var ally_i := _make_mon("SymAlly1", [TypeChart.TYPE_NORMAL])
	ally_i.ability = symbiosis
	ally_i.held_item = _make_item("Oran Berry")
	_chk("S4.01 Symbiosis passes the ally's item to the itemless mon",
			AbilityManager.try_symbiosis(mon_i, ally_i))
	_chk("S4.02 mon now holds what the ally had",
			mon_i.held_item != null and mon_i.held_item.item_name == "Oran Berry")
	_chk("S4.03 ally's item is now null", ally_i.held_item == null)

	# (ii) Does NOT trigger in singles (ally == null) — the exact value _get_ally returns there.
	var mon_ii := _make_mon("SymMon2", [TypeChart.TYPE_NORMAL])
	_chk("S4.04 Symbiosis does NOT trigger with ally == null (singles)",
			not AbilityManager.try_symbiosis(mon_ii, null))

	# (iii) Does NOT trigger if the Symbiosis holder has no item to give.
	var mon_iii := _make_mon("SymMon3", [TypeChart.TYPE_NORMAL])
	var ally_iii := _make_mon("SymAlly3", [TypeChart.TYPE_NORMAL])
	ally_iii.ability = symbiosis
	_chk("S4.05 Symbiosis does NOT trigger when the holder has no item",
			not AbilityManager.try_symbiosis(mon_iii, ally_iii))

	# (iv) Does NOT trigger if the receiving mon already has an item.
	var mon_iv := _make_mon("SymMon4", [TypeChart.TYPE_NORMAL])
	mon_iv.held_item = _make_item("AlreadyHasOne")
	var ally_iv := _make_mon("SymAlly4", [TypeChart.TYPE_NORMAL])
	ally_iv.ability = symbiosis
	ally_iv.held_item = _make_item("Oran Berry")
	_chk("S4.06 Symbiosis does NOT trigger when the receiving mon already has an item",
			not AbilityManager.try_symbiosis(mon_iv, ally_iv))

	# (v) Does NOT trigger if the ally doesn't hold Symbiosis.
	var mon_v := _make_mon("SymMon5", [TypeChart.TYPE_NORMAL])
	var ally_v := _make_mon("SymAlly5", [TypeChart.TYPE_NORMAL])
	ally_v.ability = intimidate
	ally_v.held_item = _make_item("Oran Berry")
	_chk("S4.07 Symbiosis does NOT trigger when the ally holds a different ability",
			not AbilityManager.try_symbiosis(mon_v, ally_v))


# ── Section 5: Pickpocket — full-battle integration ──────────────────────────

func _test_section_5_pickpocket_full_battle() -> void:
	var tackle := _load_move(33)
	var pickpocket := _load_ability(124)

	var holder := _make_mon("BattlePPHolder", [TypeChart.TYPE_NORMAL], 100, 40, 40, 40, 40, 40)
	holder.ability = pickpocket
	holder.add_move(tackle)
	var attacker := _make_mon("BattlePPAttacker", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 100)
	attacker.held_item = _make_item("Leftovers")
	attacker.add_move(tackle)

	var transfer_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.item_transferred.connect(func(f, t, i): transfer_events.push_back([f, t, i]))

	bm.start_battle_with_parties(BattleParty.single(attacker), BattleParty.single(holder))

	_chk("S5.01 item_transferred fired from attacker to holder (full battle)",
			transfer_events.any(func(e): return e[0] == attacker and e[1] == holder and e[2] != null and e[2].item_name == "Leftovers"))
	_chk("S5.02 holder ends up with the item", holder.held_item != null
			and holder.held_item.item_name == "Leftovers")
	_chk("S5.03 attacker's item is gone", attacker.held_item == null)

	bm.queue_free()


# ── Section 6: Sticky Hold blocks Pickpocket — full-battle integration ──────
#
# Source-verified correction: Pickpocket's holder is always the defender (the one hit),
# stealing FROM the attacker — so Sticky Hold must be on the ATTACKER (protecting its
# own item) to block the steal, not on the Pickpocket holder itself.

func _test_section_6_sticky_hold_blocks_pickpocket_full_battle() -> void:
	var tackle := _load_move(33)
	var pickpocket := _load_ability(124)
	var sticky_hold := _load_ability(60)

	var holder := _make_mon("BattlePPHolder2", [TypeChart.TYPE_NORMAL], 100, 40, 40, 40, 40, 40)
	holder.ability = pickpocket
	holder.add_move(tackle)
	var sticky_attacker := _make_mon("BattleStickyAttacker", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 100)
	sticky_attacker.ability = sticky_hold
	sticky_attacker.held_item = _make_item("Leftovers")
	sticky_attacker.add_move(tackle)

	var transfer_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.item_transferred.connect(func(f, t, i): transfer_events.push_back([f, t]))

	bm.start_battle_with_parties(BattleParty.single(sticky_attacker), BattleParty.single(holder))

	_chk("S6.01 Pickpocket did NOT steal from a Sticky-Hold-holding attacker",
			not transfer_events.any(func(e): return e[0] == sticky_attacker))
	_chk("S6.02 the Sticky Hold holder's item stayed put", sticky_attacker.held_item != null
			and sticky_attacker.held_item.item_name == "Leftovers")
	_chk("S6.03 the Pickpocket holder never gained an item", holder.held_item == null)

	bm.queue_free()


# ── Section 7: Magician — full-battle integration ────────────────────────────

func _test_section_7_magician_full_battle() -> void:
	var tackle := _load_move(33)
	var magician := _load_ability(170)

	var attacker := _make_mon("BattleMagAttacker", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 100)
	attacker.ability = magician
	attacker.add_move(tackle)
	var target := _make_mon("BattleMagTarget", [TypeChart.TYPE_NORMAL], 100, 40, 40, 40, 40, 40)
	target.held_item = _make_item("Sitrus Berry")
	target.add_move(tackle)

	var transfer_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.item_transferred.connect(func(f, t, i): transfer_events.push_back([f, t, i]))

	bm.start_battle_with_parties(BattleParty.single(attacker), BattleParty.single(target))

	_chk("S7.01 item_transferred fired from target to attacker (full battle)",
			transfer_events.any(func(e): return e[0] == target and e[1] == attacker and e[2] != null and e[2].item_name == "Sitrus Berry"))
	_chk("S7.02 attacker ends up with the item",
			attacker.held_item != null and attacker.held_item.item_name == "Sitrus Berry")

	bm.queue_free()


# ── Section 8: Symbiosis — full-battle integration (doubles) ────────────────
#
# Chains with Magician (Section 7): an opposing Magician holder steals the victim's
# item via a targeted contact hit, which removes it through the exact same
# BattleManager._do_damaging_hit path any item-removal would use — this then lets
# Symbiosis (held by the victim's ally) immediately hand over its own item.

func _test_section_8_symbiosis_full_battle_doubles() -> void:
	var tackle := _load_move(33)
	var magician := _load_ability(170)
	var symbiosis := _load_ability(180)

	var symbiosis_holder := _make_mon("BattleSymHolder", [TypeChart.TYPE_NORMAL], 100, 40, 100, 40, 100, 50)
	symbiosis_holder.ability = symbiosis
	symbiosis_holder.held_item = _make_item("Oran Berry")
	symbiosis_holder.add_move(tackle)

	var victim_mon := _make_mon("BattleSymVictim", [TypeChart.TYPE_NORMAL], 100, 40, 100, 40, 100, 40)
	victim_mon.held_item = _make_item("Victim Item")
	victim_mon.add_move(tackle)

	var magician_opp := _make_mon("BattleSymMagOpp", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 200)
	magician_opp.ability = magician
	magician_opp.add_move(tackle)
	var filler_opp := _make_mon("BattleSymFillerOpp", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 20)
	filler_opp.add_move(tackle)

	var transfer_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.item_transferred.connect(func(f, t, i): transfer_events.push_back([f, t, i]))

	# combatant indices in doubles: 0,1 = player side; 2,3 = opponent side (matches
	# doubles_test.gd's established D4 targeting convention).
	bm.queue_move_targeted(2, 0, 1)  # Turn 1: magician_opp (idx2) Tackles victim_mon (idx1).
	bm.start_battle_doubles(_doubles_party(symbiosis_holder, victim_mon),
			_doubles_party(magician_opp, filler_opp))

	_chk("S8.01 Magician stole victim_mon's item (chained trigger)",
			transfer_events.any(func(e): return e[0] == victim_mon and e[1] == magician_opp))
	_chk("S8.02 Symbiosis passed its item to the ally after the ally's item was stolen (full doubles battle)",
			transfer_events.any(func(e): return e[0] == symbiosis_holder and e[1] == victim_mon and e[2] != null and e[2].item_name == "Oran Berry"))

	bm.queue_free()


# ── Section 9: Neutralizing Gas suppresses all three trigger abilities ─────

func _test_section_9_neutralizing_gas_suppression() -> void:
	var tackle := _load_move(33)
	var pickpocket := _load_ability(124)
	var magician := _load_ability(170)
	var symbiosis := _load_ability(180)

	# (i) Pickpocket suppressed.
	var pp_holder := _make_mon("NGPPHolder", [TypeChart.TYPE_NORMAL])
	pp_holder.ability = pickpocket
	var pp_attacker := _make_mon("NGPPAttacker", [TypeChart.TYPE_NORMAL])
	pp_attacker.held_item = _make_item("Leftovers")
	var pp_result: Dictionary = AbilityManager.try_contact_effects(
			pp_attacker, pp_holder, tackle, 10, null, null, true)
	_chk("S9.01 Pickpocket suppressed by Neutralizing Gas (ng_active=true)",
			not pp_result["pickpocket_stole"])

	# (ii) Magician suppressed.
	var mag_attacker := _make_mon("NGMagAttacker", [TypeChart.TYPE_NORMAL])
	mag_attacker.ability = magician
	var mag_target := _make_mon("NGMagTarget", [TypeChart.TYPE_NORMAL])
	mag_target.held_item = _make_item("Sitrus Berry")
	_chk("S9.02 Magician suppressed by Neutralizing Gas (ng_active=true)",
			not AbilityManager.try_magician(mag_attacker, mag_target, 10, true))

	# (iii) Symbiosis suppressed.
	var sym_mon := _make_mon("NGSymMon", [TypeChart.TYPE_NORMAL])
	var sym_ally := _make_mon("NGSymAlly", [TypeChart.TYPE_NORMAL])
	sym_ally.ability = symbiosis
	sym_ally.held_item = _make_item("Oran Berry")
	_chk("S9.03 Symbiosis suppressed by Neutralizing Gas (ng_active=true)",
			not AbilityManager.try_symbiosis(sym_mon, sym_ally, true))


# ── Section 10: Multitype-Plate exclusion fix ────────────────────────────────
# Closes a real gap found while verifying the (separately-fixed) Trick/Switcheroo
# Multitype-Plate exclusion: source's CanBattlerGetOrLoseItem/
# DoesSpeciesUseHoldItemToChangeForm is called by CanStealItem (Pickpocket/Magician/
# Thief/Covet/Sticky Barb, all via the shared AbilityManager._try_steal_item) and by
# TryTriggerSymbiosis — not just Trick's own Cmd_tryswapitems. None of those had this
# check before this fix. Ground truth: battle_util.c L8686-8706 (CanBattlerGetOrLoseItem),
# L8378-8403 (DoesSpeciesUseHoldItemToChangeForm), L9188-9189 (CanStealItem's two calls),
# L9967-9968 (TryTriggerSymbiosis's two calls). See docs/decisions.md's Multitype-Plate
# fix entry for the full call-site derivation.
#
# A "Plate" item here is any ItemData with hold_effect == ItemManager.HOLD_EFFECT_PLATE,
# this project's own Multitype-linkage model (`[M17n-4]`) standing in for source's
# species-level form-change table lookup.

func _test_section_10_multitype_plate_exclusion() -> void:
	var tackle := _load_move(33)
	var pickpocket := _load_ability(124)
	var magician := _load_ability(170)
	var symbiosis := _load_ability(180)
	var multitype := _load_ability(121)

	# (i) Pickpocket: BLOCKED from stealing a Multitype holder's Plate.
	var mt_holder_i := _make_mon("MTPickpocketHolder", [TypeChart.TYPE_NORMAL])
	mt_holder_i.ability = pickpocket
	var mt_attacker_i := _make_mon("MTPickpocketAtk", [TypeChart.TYPE_NORMAL])
	mt_attacker_i.ability = multitype
	var plate_i := ItemData.new()
	plate_i.item_name = "Iron Plate"
	plate_i.hold_effect = ItemManager.HOLD_EFFECT_PLATE
	mt_attacker_i.held_item = plate_i
	var result_i: Dictionary = AbilityManager.try_contact_effects(
			mt_attacker_i, mt_holder_i, tackle, 10)
	_chk("S10.01 Pickpocket is BLOCKED from stealing a Multitype holder's Plate",
			not result_i["pickpocket_stole"])
	_chk("S10.02 the Multitype holder's Plate is untouched",
			mt_attacker_i.held_item != null and mt_attacker_i.held_item == plate_i)

	# (i-discriminator) Pickpocket still works normally against an ordinary item.
	var ord_holder_i := _make_mon("OrdPickpocketHolder", [TypeChart.TYPE_NORMAL])
	ord_holder_i.ability = pickpocket
	var ord_attacker_i := _make_mon("OrdPickpocketAtk", [TypeChart.TYPE_NORMAL])
	ord_attacker_i.held_item = _make_item("Leftovers")
	var result_i_ord: Dictionary = AbilityManager.try_contact_effects(
			ord_attacker_i, ord_holder_i, tackle, 10)
	_chk("S10.03 discriminator: Pickpocket still steals an ordinary (non-Plate/" +
			"non-Multitype) item normally",
			result_i_ord["pickpocket_stole"])

	# (ii) Magician: BLOCKED from stealing a Multitype holder's Plate.
	var mt_mag_attacker := _make_mon("MTMagAtk", [TypeChart.TYPE_NORMAL])
	mt_mag_attacker.ability = magician
	var mt_mag_target := _make_mon("MTMagTarget", [TypeChart.TYPE_NORMAL])
	mt_mag_target.ability = multitype
	var plate_ii := ItemData.new()
	plate_ii.item_name = "Splash Plate"
	plate_ii.hold_effect = ItemManager.HOLD_EFFECT_PLATE
	mt_mag_target.held_item = plate_ii
	_chk("S10.04 Magician is BLOCKED from stealing a Multitype holder's Plate",
			not AbilityManager.try_magician(mt_mag_attacker, mt_mag_target, 10))
	_chk("S10.05 the Multitype holder's Plate is untouched",
			mt_mag_target.held_item != null and mt_mag_target.held_item == plate_ii)

	# (ii-discriminator) Magician still works normally against an ordinary item.
	var ord_mag_attacker := _make_mon("OrdMagAtk", [TypeChart.TYPE_NORMAL])
	ord_mag_attacker.ability = magician
	var ord_mag_target := _make_mon("OrdMagTarget", [TypeChart.TYPE_NORMAL])
	ord_mag_target.held_item = _make_item("Sitrus Berry")
	_chk("S10.06 discriminator: Magician still steals an ordinary item normally",
			AbilityManager.try_magician(ord_mag_attacker, ord_mag_target, 10))

	# (iii) Thief/Covet (try_thief_steal, shares _try_steal_item with Pickpocket/Magician):
	# BLOCKED from stealing a Multitype holder's Plate.
	var mt_thief_attacker := _make_mon("MTThiefAtk", [TypeChart.TYPE_NORMAL])
	var mt_thief_target := _make_mon("MTThiefTarget", [TypeChart.TYPE_NORMAL])
	mt_thief_target.ability = multitype
	var plate_iii := ItemData.new()
	plate_iii.item_name = "Toxic Plate"
	plate_iii.hold_effect = ItemManager.HOLD_EFFECT_PLATE
	mt_thief_target.held_item = plate_iii
	_chk("S10.07 Thief/Covet is BLOCKED from stealing a Multitype holder's Plate",
			not AbilityManager.try_thief_steal(mt_thief_attacker, mt_thief_target))
	_chk("S10.08 the Multitype holder's Plate is untouched",
			mt_thief_target.held_item != null and mt_thief_target.held_item == plate_iii)

	# (iii-discriminator) Thief/Covet still works normally against an ordinary item.
	var ord_thief_attacker := _make_mon("OrdThiefAtk", [TypeChart.TYPE_NORMAL])
	var ord_thief_target := _make_mon("OrdThiefTarget", [TypeChart.TYPE_NORMAL])
	ord_thief_target.held_item = _make_item("Oran Berry")
	_chk("S10.09 discriminator: Thief/Covet still steals an ordinary item normally",
			AbilityManager.try_thief_steal(ord_thief_attacker, ord_thief_target))

	# (iv) Symbiosis: BLOCKED from GIVING a Plate to a Multitype receiver (the
	# reachable half — receiver is Multitype, real; the giver-loses-its-own-Plate half
	# is structurally unreachable in practice, since the giver's ability slot is
	# always Symbiosis itself, never simultaneously Multitype — matches the
	# already-documented Unburden precedent in try_symbiosis's own doc comment).
	var mt_sym_mon := _make_mon("MTSymMon", [TypeChart.TYPE_NORMAL])
	mt_sym_mon.ability = multitype
	var mt_sym_ally := _make_mon("MTSymAlly", [TypeChart.TYPE_NORMAL])
	mt_sym_ally.ability = symbiosis
	var plate_iv := ItemData.new()
	plate_iv.item_name = "Earth Plate"
	plate_iv.hold_effect = ItemManager.HOLD_EFFECT_PLATE
	mt_sym_ally.held_item = plate_iv
	_chk("S10.10 Symbiosis is BLOCKED from giving a Plate to a Multitype receiver",
			not AbilityManager.try_symbiosis(mt_sym_mon, mt_sym_ally))
	_chk("S10.11 the Symbiosis holder's Plate is untouched",
			mt_sym_ally.held_item != null and mt_sym_ally.held_item == plate_iv)

	# (iv-discriminator) Symbiosis still works normally against an ordinary item.
	var ord_sym_mon := _make_mon("OrdSymMon", [TypeChart.TYPE_NORMAL])
	var ord_sym_ally := _make_mon("OrdSymAlly", [TypeChart.TYPE_NORMAL])
	ord_sym_ally.ability = symbiosis
	ord_sym_ally.held_item = _make_item("Oran Berry")
	_chk("S10.12 discriminator: Symbiosis still gives an ordinary item normally",
			AbilityManager.try_symbiosis(ord_sym_mon, ord_sym_ally))
