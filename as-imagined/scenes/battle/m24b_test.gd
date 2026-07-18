extends Node

# [M24b] Money, Held Items & Battle-Use Items — closes M24a's data pipeline
# gap between "trainer data exists" and "a real battle can actually use it."
#
# Section A: Smoke Ball rollover (data-only item, no dispatch — see
#   item_manager.gd's own HOLD_EFFECT_CAN_ALWAYS_RUN doc comment) + confirms
#   Weezing (TRAINER_LAO_5) now resolves its held item.
# Section B: Amulet Coin — direct triggers_double_prize() unit tests plus
#   the 4-switch-in-site latch (_check_amulet_coin_trigger).
# Section C: the pure money-reward formula (_compute_trainer_money_reward),
#   all 4 source branches (singles/doubles/two-opponents/trainer-class-money-
#   fallback), confirming is_two_opponents/is_doubles are mutually exclusive
#   per source's own if/elif/else chain (not combinable).
# Section D: full-battle integration — money_awarded/last_money_awarded only
#   fire on a real player win against an attached opponent TrainerData; a
#   loss or a no-TrainerData (wild/test) battle both correctly fire nothing.
# Section E: BattlePokemon.from_trainer_mon() — the new TrainerPartyMon ->
#   real battle-ready BattlePokemon constructor (species/level/nature/ivs/
#   moves/held item/ability/gender all correctly resolved), spot-checked
#   against Brawly's own Makuhita (already spot-checked in M24a's smoke
#   test for its raw data — this confirms the same data survives real
#   BattlePokemon construction).
# Section F: TrainerAI.should_use_item() — the new, deliberately narrow
#   battle-use-item heuristic (source's own AI_ShouldHeal first-order
#   threshold, hp < maxHP/4, WITHOUT its deeper damage-prediction layer).
# Section G: full-battle integration — an AI side with real battle-item
#   stock (mirroring Roxanne's own real 2x-Potion trainer data) actually
#   uses an item instead of a move when its active mon drops below the
#   threshold, and correctly falls back to a move once stock is exhausted.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_section_a_smoke_ball()
	_test_section_b_amulet_coin()
	_test_section_c_money_formula_direct()
	_test_section_d_money_formula_integration()
	_test_section_e_from_trainer_mon()
	_test_section_f_should_use_item_direct()
	_test_section_g_battle_item_ai_integration()

	var total := _pass + _fail
	print("m24b_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


func _make_bm() -> BattleManager:
	var bm := BattleManager.new()
	add_child(bm)
	return bm


func _make_mon(mon_name: String, hp: int = 100, atk: int = 80, spd: int = 80) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types.append(TypeChart.TYPE_NORMAL)
	sp.base_hp = hp
	sp.base_attack = atk
	sp.base_defense = 80
	sp.base_sp_attack = 80
	sp.base_sp_defense = 80
	sp.base_speed = spd
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])


func _load_move(id: int) -> MoveData:
	return load("res://data/moves/move_%04d.tres" % id) as MoveData


func _make_trainer_data(trainer_class_id: int, last_level: int) -> TrainerData:
	var td := TrainerData.new()
	td.trainer_class_id = trainer_class_id
	var mon := TrainerPartyMon.new()
	mon.species_dex = 1
	mon.level = last_level
	td.party = [mon]
	return td


# ── Section A: Smoke Ball rollover ─────────────────────────────────────────

func _test_section_a_smoke_ball() -> void:
	var smoke_ball: ItemData = ItemRegistry.get_item(468)
	_chk("A.01 Smoke Ball (468) resolves", smoke_ball != null)
	_chk("A.02 Smoke Ball name is correct", smoke_ball != null and smoke_ball.item_name == "Smoke Ball")
	_chk("A.03 Smoke Ball's hold_effect is HOLD_EFFECT_CAN_ALWAYS_RUN (36)",
			smoke_ball != null and smoke_ball.hold_effect == ItemManager.HOLD_EFFECT_CAN_ALWAYS_RUN)

	var weezing_trainer: TrainerData = TrainerRegistry.get_trainer_by_key("TRAINER_LAO_5")
	_chk("A.04 TRAINER_LAO_5 resolves", weezing_trainer != null)
	if weezing_trainer != null:
		var weezing: TrainerPartyMon = weezing_trainer.party[weezing_trainer.party.size() - 1]
		_chk("A.05 Weezing is species_dex 110", weezing.species_dex == 110)
		_chk("A.06 Weezing's held_item_id resolves to Smoke Ball (468), not 0",
				weezing.held_item_id == 468)


# ── Section B: Amulet Coin ─────────────────────────────────────────────────

func _test_section_b_amulet_coin() -> void:
	var amulet_coin: ItemData = ItemRegistry.get_item(466)
	_chk("B.01 Amulet Coin (466) resolves", amulet_coin != null)
	_chk("B.02 Amulet Coin's hold_effect is HOLD_EFFECT_DOUBLE_PRIZE (31)",
			amulet_coin != null and amulet_coin.hold_effect == ItemManager.HOLD_EFFECT_DOUBLE_PRIZE)

	var holder := _make_mon("Holder")
	holder.held_item = amulet_coin
	_chk("B.03 triggers_double_prize true for a real Amulet Coin holder",
			ItemManager.triggers_double_prize(holder, false))

	var non_holder := _make_mon("NonHolder")
	_chk("B.04 triggers_double_prize false for a mon with no held item",
			not ItemManager.triggers_double_prize(non_holder, false))

	var potion_holder := _make_mon("PotionHolder")
	potion_holder.held_item = ItemRegistry.get_item(479)  # Life Orb — unrelated hold_effect
	_chk("B.05 triggers_double_prize false for an unrelated held item (negative control)",
			not ItemManager.triggers_double_prize(potion_holder, false))

	# Switch-in latch: player-side triggers, opponent-side does not.
	var bm := _make_bm()
	bm._check_amulet_coin_trigger(holder, 0)
	_chk("B.06 _check_amulet_coin_trigger latches true for player side (0)",
			bm._amulet_coin_triggered)

	var bm2 := _make_bm()
	bm2._check_amulet_coin_trigger(holder, 1)
	_chk("B.07 _check_amulet_coin_trigger does NOT latch for opponent side (1)",
			not bm2._amulet_coin_triggered)

	# Idempotent: a second Amulet-Coin-holding switch-in doesn't "double the double."
	var bm3 := _make_bm()
	bm3._check_amulet_coin_trigger(holder, 0)
	bm3._check_amulet_coin_trigger(holder, 0)
	_chk("B.08 latch stays a plain bool after a second trigger (idempotent)",
			bm3._amulet_coin_triggered)
	bm.queue_free()
	bm2.queue_free()
	bm3.queue_free()


# ── Section C: money formula, direct (all 4 source branches) ──────────────

func _test_section_c_money_formula_direct() -> void:
	var bm := _make_bm()
	var td := _make_trainer_data(32, 19)  # LEADER class (money=25), level 19 — matches Brawly's own real data exactly

	_chk("C.01 singles: 4*19*1*25=1900",
			bm._compute_trainer_money_reward(td, false, false, 1) == 1900)
	_chk("C.02 doubles: 4*19*1*2*25=3800",
			bm._compute_trainer_money_reward(td, true, false, 1) == 3800)
	_chk("C.03 two_opponents: 4*19*1*25=1900 (same magnitude as singles, confirmed a genuinely separate branch below)",
			bm._compute_trainer_money_reward(td, false, true, 1) == 1900)
	_chk("C.04 amulet coin doubles singles: 4*19*2*25=3800",
			bm._compute_trainer_money_reward(td, false, false, 2) == 3800)
	_chk("C.05 amulet coin ALSO doubles the doubles case: 4*19*2*2*25=7600",
			bm._compute_trainer_money_reward(td, true, false, 2) == 7600)

	# Mutual exclusivity: is_two_opponents=true AND is_doubles=true together
	# must take the TWO_OPPONENTS branch (source's own if/elif/else order —
	# NOT both doublings stacked, which would give 3800 instead of 1900).
	_chk("C.06 two_opponents takes precedence over doubles when both true (not combinable, matching source's if/elif/else)",
			bm._compute_trainer_money_reward(td, true, true, 1) == 1900)

	# trainer_class.money==0 falls back to 5 (source's `?: 5` idiom).
	var td_zero_money := _make_trainer_data(0, 10)  # TRAINER_CLASS_PKMN_TRAINER_1 -- confirmed money=0/unset
	var tc_zero: TrainerClassData = TrainerClassRegistry.get_trainer_class(0)
	_chk("C.07 sanity: trainer_class_id 0 really has money==0 (unset)",
			tc_zero != null and tc_zero.money == 0)
	_chk("C.08 money==0 falls back to trainerMoney=5: 4*10*1*5=200",
			bm._compute_trainer_money_reward(td_zero_money, false, false, 1) == 200)

	# Edge cases.
	_chk("C.09 null trainer_data returns 0", bm._compute_trainer_money_reward(null, false, false, 1) == 0)
	var td_empty := TrainerData.new()
	_chk("C.10 empty-party trainer_data returns 0", bm._compute_trainer_money_reward(td_empty, false, false, 1) == 0)

	bm.queue_free()


# ── Section D: money formula, full-battle integration ──────────────────────

func _test_section_d_money_formula_integration() -> void:
	# D1: player wins against an attached opponent TrainerData -> money_awarded fires correctly.
	var player := _make_mon("Player", 200, 200, 200)
	var opp := _make_mon("Opp", 20, 20, 20)
	var tackle := _load_move(33)
	player.add_move(tackle)
	opp.add_move(tackle)

	var td := _make_trainer_data(32, 19)  # LEADER, level 19 -> 1900 at multiplier 1
	var awarded := [-1]
	var bm := _make_bm()
	bm.money_awarded.connect(func(amount): awarded[0] = amount)
	bm.set_trainer_data(1, td)
	bm.start_battle(player, opp)

	_chk("D.01 player wins this scenario", bm.last_money_awarded > 0 or awarded[0] > 0)
	_chk("D.02 money_awarded fired with the exact expected amount (1900)", awarded[0] == 1900)
	_chk("D.03 last_money_awarded matches the emitted amount", bm.last_money_awarded == 1900)
	bm.queue_free()

	# D2: player LOSES -> money_awarded never fires, last_money_awarded stays 0.
	var weak_player := _make_mon("WeakPlayer", 20, 20, 20)
	var strong_opp := _make_mon("StrongOpp", 200, 200, 200)
	weak_player.add_move(tackle)
	strong_opp.add_move(tackle)

	var awarded2 := [-1]
	var bm2 := _make_bm()
	bm2.money_awarded.connect(func(amount): awarded2[0] = amount)
	bm2.set_trainer_data(1, td)
	bm2.start_battle(weak_player, strong_opp)

	_chk("D.04 player loses this scenario", not bm2._parties[1].is_fully_fainted())
	_chk("D.05 money_awarded never fires on a loss", awarded2[0] == -1)
	_chk("D.06 last_money_awarded stays 0 on a loss", bm2.last_money_awarded == 0)
	bm2.queue_free()

	# D3: no TrainerData attached at all (wild/test battle) -> nothing fires
	# even though the player wins.
	var player3 := _make_mon("Player2", 200, 200, 200)
	var opp3 := _make_mon("Opp2", 20, 20, 20)
	player3.add_move(tackle)
	opp3.add_move(tackle)

	var awarded3 := [-1]
	var bm3 := _make_bm()
	bm3.money_awarded.connect(func(amount): awarded3[0] = amount)
	# Deliberately no set_trainer_data call.
	bm3.start_battle(player3, opp3)
	_chk("D.07 no money_awarded without an attached opponent TrainerData",
			awarded3[0] == -1)
	_chk("D.08 last_money_awarded stays 0 without an attached opponent TrainerData",
			bm3.last_money_awarded == 0)
	bm3.queue_free()

	# D4: Amulet Coin held by the winning player's own mon doubles the reward.
	var ac_player := _make_mon("ACPlayer", 200, 200, 200)
	ac_player.add_move(tackle)
	ac_player.held_item = ItemRegistry.get_item(466)
	var ac_opp := _make_mon("ACOpp", 20, 20, 20)
	ac_opp.add_move(tackle)

	var awarded4 := [-1]
	var bm4 := _make_bm()
	bm4.money_awarded.connect(func(amount): awarded4[0] = amount)
	bm4.set_trainer_data(1, td)
	bm4.start_battle(ac_player, ac_opp)

	_chk("D.09 Amulet Coin doubles the real battle reward: 1900*2=3800",
			awarded4[0] == 3800)
	bm4.queue_free()


# ── Section E: BattlePokemon.from_trainer_mon() ────────────────────────────

func _test_section_e_from_trainer_mon() -> void:
	var brawly: TrainerData = TrainerRegistry.get_trainer_by_key("TRAINER_BRAWLY_1")
	_chk("E.01 TRAINER_BRAWLY_1 resolves", brawly != null)
	if brawly == null:
		return

	var makuhita_tpm: TrainerPartyMon = brawly.party[2]
	var bp: BattlePokemon = BattlePokemon.from_trainer_mon(makuhita_tpm)
	_chk("E.02 from_trainer_mon returns a real BattlePokemon", bp != null)
	if bp == null:
		return
	_chk("E.03 species resolved correctly (Makuhita)", bp.species.species_name == "Makuhita")
	_chk("E.04 species_dex matches (296)", bp.species.national_dex_num == 296)
	_chk("E.05 level matches (19)", bp.level == 19)
	_chk("E.06 nature matches (Hardy=0, trainerproc's own default)", bp.nature == 0)
	_chk("E.07 IVs match (all 24)", bp.ivs == [24, 24, 24, 24, 24, 24])
	_chk("E.08 all 4 moves resolved", bp.moves.size() == 4)
	_chk("E.09 move names match (Arm Thrust/Vital Throw/Reversal/Bulk Up)",
			bp.moves.map(func(m): return m.move_name) ==
			["Arm Thrust", "Vital Throw", "Reversal", "Bulk Up"])
	_chk("E.10 held item resolved (Sitrus Berry)",
			bp.held_item != null and bp.held_item.item_name == "Sitrus Berry")
	_chk("E.11 current_pp parallel array populated (add_move's own contract)",
			bp.current_pp.size() == 4 and bp.current_pp[0] == bp.moves[0].pp)
	_chk("E.12 stats computed (max_hp > 0)", bp.max_hp > 0 and bp.current_hp == bp.max_hp)

	# A mon with no held item (Machop, party[0]) resolves cleanly to null, not a crash.
	var machop_tpm: TrainerPartyMon = brawly.party[0]
	var machop_bp: BattlePokemon = BattlePokemon.from_trainer_mon(machop_tpm)
	_chk("E.13 a trainer mon with no held item resolves held_item to null (not 0/garbage)",
			machop_bp != null and machop_bp.held_item == null)

	# Declan's Gyarados: zero explicit moves in source, fallback moveset already
	# pre-computed by gen_trainer_data.py — confirms from_trainer_mon doesn't
	# need its own separate fallback logic, just resolves whatever move_ids
	# already contains.
	var declan: TrainerData = TrainerRegistry.get_trainer_by_key("TRAINER_DECLAN")
	if declan != null:
		var gyarados_bp: BattlePokemon = BattlePokemon.from_trainer_mon(declan.party[0])
		_chk("E.14 Declan's Gyarados resolves its pre-computed fallback moveset (4 moves)",
				gyarados_bp != null and gyarados_bp.moves.size() == 4)


# ── Section F: TrainerAI.should_use_item(), direct ─────────────────────────

func _test_section_f_should_use_item_direct() -> void:
	var ai := TrainerAI.new()
	var potion: ItemData = ItemRegistry.get_item(28)
	_chk("F.00 sanity: Potion (28) resolves as a real BATTLE_USE_RESTORE_HP item",
			potion != null and potion.battle_usage == ItemManager.BATTLE_USE_RESTORE_HP)

	var low_hp_mon := _make_mon("LowHP")
	low_hp_mon.current_hp = int(low_hp_mon.max_hp / 5.0)  # well under maxHP/4
	var chosen: ItemData = ai.should_use_item(low_hp_mon, [potion])
	_chk("F.01 low HP (<maxHP/4) with a RESTORE_HP item available -> chooses it",
			chosen == potion)

	var full_hp_mon := _make_mon("FullHP")
	_chk("F.02 full HP -> returns null (no need to heal)",
			ai.should_use_item(full_hp_mon, [potion]) == null)

	var borderline_mon := _make_mon("Borderline")
	borderline_mon.current_hp = int(borderline_mon.max_hp / 4.0)  # exactly at the threshold, not under it
	_chk("F.03 HP exactly at maxHP/4 (not under it) -> returns null",
			ai.should_use_item(borderline_mon, [potion]) == null)

	var full_heal: ItemData = ItemRegistry.get_item(48)
	_chk("F.04 low HP but only a non-RESTORE_HP item available (Full Heal) -> returns null",
			ai.should_use_item(low_hp_mon, [full_heal]) == null)

	var fainted_mon := _make_mon("Fainted")
	fainted_mon.current_hp = 0
	_chk("F.05 a fainted mon never triggers item use",
			ai.should_use_item(fainted_mon, [potion]) == null)

	_chk("F.06 empty available_items list -> null", ai.should_use_item(low_hp_mon, []) == null)


# ── Section G: battle-use item AI, full-battle integration ─────────────────

func _test_section_g_battle_item_ai_integration() -> void:
	# Roxanne-shaped trainer data: 2x Potion in her real battle_items, per
	# M24a's own converter run (the ONLY trainer, out of all 854, whose
	# "Items:" field resolves to anything real today).
	var td := TrainerData.new()
	td.trainer_class_id = 32
	var tpm := TrainerPartyMon.new()
	tpm.species_dex = 1
	tpm.level = 12
	td.party = [tpm]
	td.battle_items = [28, 28]  # 2x Potion

	var ai := TrainerAI.new()
	ai.tier = TrainerAI.Tier.BASIC

	# The AI's own active mon starts already below the maxHP/4 threshold and
	# has ONLY a weak, non-lethal move available to the player, so the
	# battle survives long enough to observe multiple item-use turns rather
	# than ending on turn 1.
	var ai_mon := _make_mon("AIMon", 100, 20, 20)
	ai_mon.current_hp = 10  # well under maxHP/4 (25)
	var weak_move := _load_move(33)  # Tackle
	ai_mon.add_move(weak_move)
	var player_mon := _make_mon("WeakPlayer", 300, 5, 1)
	player_mon.add_move(weak_move)

	var healed_events := []
	var item_used_events := []
	var bm := _make_bm()
	bm.item_healed.connect(func(target, amount): healed_events.append([target, amount]))
	bm.item_action_used.connect(func(user, item, _target): item_used_events.append([user, item]))
	bm.set_trainer_ai(1, ai)
	bm.set_trainer_data(1, td)
	bm.start_battle(player_mon, ai_mon)

	_chk("G.01 the AI used a battle item at least once (item_action_used fired for the AI's own mon)",
			item_used_events.any(func(e): return e[0] == ai_mon))
	_chk("G.02 the item used was Potion",
			item_used_events.size() > 0 and item_used_events[0][1].item_name == "Potion")
	_chk("G.03 healing was actually applied (item_healed fired)",
			healed_events.size() > 0)
	_chk("G.04 battle_item stock decremented (not still at the starting 2)",
			bm._trainer_battle_item_stock[1].get(28, 0) < 2)
	bm.queue_free()

	# Stock exhaustion: force exactly 2 uses via a direct, deterministic
	# _maybe_ai_use_item call sequence (avoids depending on how many turns a
	# real battle happens to run before HP recovers above the threshold —
	# the same "isolate the exact event" discipline this project's own
	# testing conventions require for anything multi-turn).
	var bm2 := _make_bm()
	bm2.set_trainer_data(1, td)
	bm2._parties = [BattleParty.single(player_mon), BattleParty.single(ai_mon)]
	bm2._active_per_side = 1
	# _maybe_ai_use_item() is normally only ever called mid-way through
	# start_battle_with_parties()'s own dispatch, which pre-sizes all 5 of
	# these parallel per-combatant arrays first -- replicate that minimal
	# setup here for a direct, deterministic call sequence outside a real
	# battle loop.
	bm2._chosen_moves = [null, null]
	bm2._chosen_switch_slots = [-1, -1]
	bm2._chosen_targets = [1, 0]
	bm2._chosen_items = [null, null]
	bm2._chosen_item_targets = [-1, -1]
	var low_mon := _make_mon("LowMon", 100, 20, 20)
	low_mon.current_hp = 5
	var use1: bool = bm2._maybe_ai_use_item(1, 1, low_mon, ai)
	var use2: bool = bm2._maybe_ai_use_item(1, 1, low_mon, ai)
	var use3: bool = bm2._maybe_ai_use_item(1, 1, low_mon, ai)
	_chk("G.05 first item use succeeds (stock=2->1)", use1)
	_chk("G.06 second item use succeeds (stock=1->0)", use2)
	_chk("G.07 third item use fails (stock exhausted, AI falls back to a move)", not use3)
	bm2.queue_free()
