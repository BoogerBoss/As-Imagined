extends Node

# [M22 Phase 1] Item action-queue infrastructure, proven with Potion alone —
# Step 0 + implementation. See docs/m22_recon.md for the full recon this
# session built against, and its own Step 0 re-verification section for what
# changed since that recon (nothing structural — every finding held).
#
# Confirmed via source (item_use.c, battle_main.c) and re-verified fresh this
# session, not just trusted from the recon snapshot:
#
# - Turn order: Item/Switch/Ball actions sort into ONE front tier, ordered by
#   raw battler index (NOT speed), entirely bypassing the priority/speed
#   comparator — this project's existing Switch-tier comparator code already
#   implemented and cited this exact source mechanism
#   (battle_main.c L4967-4990); generalized to include Item with a one-line
#   change (`_chosen_switch_slots[i] >= 0 or _chosen_items[i] != null`), no
#   new turn-order logic written.
# - Item targeting is a PARTY SLOT (BattleParty.members index), not a
#   combatant index — a real, source-confirmed distinction. Re-verified
#   Potion specifically: its own `.type = ITEM_USE_PARTY_MENU` (src/data/
#   items.h), NOT `ITEM_USE_BATTLER` (the "auto-select in singles, choose in
#   doubles" case X Attack uses) — confirming Potion's real scope DOES
#   include targeting a benched party member, in both singles AND doubles,
#   not just the active battler. This is NOT a bigger architectural lift than
#   active-only targeting would have been: BattleParty.members is a plain
#   Array, so resolving any party slot (active or benched) is the exact same
#   code path (`_parties[side].members[party_target]`) regardless of index —
#   confirmed no extra infrastructure needed, so full party-slot targeting
#   (including a benched-target test below) ships in this session rather than
#   being narrowed, per the recon's own proposed design.
# - A REAL PRE-EXISTING BUG, fixed here: `_phase_move_selection`'s choice-lock
#   and forced-Struggle overrides only guarded against `_chosen_switch_slots`,
#   not a queued item — both extended to also check `_chosen_items[i] == null`.
# - Two more real, analogous gaps found and fixed while auditing every
#   `_chosen_switch_slots[...]` read site for the same front-tier
#   generalization: `_apply_quash_bubble`'s defensive switch-guard and
#   `_is_last_to_move` (Analytic's own "am I the last to move" check) both
#   only recognized a later actor's switch as "not a pending move action" —
#   neither recognized an item action the same way, which `_is_last_to_move`
#   specifically would have gotten WRONG (not just defensively unreachable)
#   once item actions exist. Both now also check `_chosen_items`.
#
# Deliberately NOT built in Phase 1, per the recon's own proposed sequencing:
# Full Heal, X Attack, the Poké Ball placeholder, Dire Hit/Guard Spec. —
# Potion was Phase 1's ONE proof-of-concept item.
#
# [M22 Phase 2] Full Heal / X Attack / Poké Ball placeholder — the rest of
# the recon's own minimal representative set. Re-verified fresh from source
# (item_use.c, battle_script_commands.c, src/data/items.h,
# src/data/pokemon/item_effects.h), not assumed to mirror Potion uniformly:
#
# - Full Heal cures MORE than "all non-volatile status" — source's own
#   `gItemEffect_FullHeal[3] = ITEM3_STATUS_ALL` resolves (via
#   GetItemStatus1Mask) to STATUS1_ANY|STATUS1_TOXIC_COUNTER, AND
#   BS_ItemCureStatus separately calls ItemHealMonVolatile, which ALSO cures
#   confusion/infatuation for this item. Confirmed this project's own
#   architecture (BattleManager._clear_volatiles unconditionally zeroes both
#   confusion_turns and infatuated_by on every switch-out) makes source's
#   "active-battler-only" volatile-cure restriction moot — a benched
#   BattlePokemon here can never carry either state to begin with, so the
#   cure applies uniformly with zero behavioral difference from source.
# - X Attack raises Attack by +2 stages at this project's GEN_LATEST config
#   (X_ITEM_STAGES, src/data/items.h:13, B_X_ITEMS_BUFF>=GEN_7), NOT +1 —
#   confirmed, not assumed. Reuses StatusManager.apply_stat_change directly
#   (the same generic dispatch every stat-changing move already uses),
#   which already naturally no-ops at max stage — zero new stat-stage logic
#   needed. New ItemData.stat_boost_stage field added, deliberately
#   SEPARATE from ev_boost_stat (M20c) — the two use DIFFERENT stat
#   orderings (STAGE_* vs STAT_*) for different mechanics; conflating them
#   would silently reproduce this project's own documented Nature/Hidden-
#   Power "Speed ordering" pitfall.
# - The Poké Ball placeholder is a deliberate stub (ItemManager.attempt_catch
#   always returns false), matching the Drizzle/Drought "stub now, un-stub
#   at the same call site later" precedent (CLAUDE.md's own Build Order,
#   M8->M11) — M27 owns the real catch-rate formula. A REAL, newly-found
#   design wrinkle beyond Potion's own shape: a Poké Ball targets the
#   OPPONENT, not a party slot on the acting trainer's own side (source:
#   `.type = ITEM_USE_BAG_MENU`, no party-menu step at all, unlike Potion/
#   Full Heal's `ITEM_USE_PARTY_MENU` or X Attack's `ITEM_USE_BATTLER`) —
#   _do_item_use resolves the Ball's target via _chosen_targets (the SAME
#   combatant-index mechanism every foe-targeting MOVE already uses), not
#   party_target/_parties[side].members[...] at all.
# - Confirmed via direct source read that item consumption/bag-inventory
#   deduction is NOT modeled for ANY of these 4 items (matching Potion's own
#   Phase 1 precedent) — this project has no bag/inventory data structure at
#   all (docs/m25_bag_items_recon.md Section B.1), so there is nothing new
#   for the Poké Ball specifically to depend on here; this was re-confirmed,
#   not assumed, before implementing.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_data_integrity()
	_test_singles_basic_heal()
	_test_bench_targeting()
	_test_doubles_targeting()
	_test_already_full_hp_is_noop()
	_test_fainted_target_is_noop()
	_test_turn_order_item_ahead_of_faster_move()
	_test_turn_order_item_and_switch_same_tier_battler_order()
	_test_choice_lock_does_not_clobber_queued_item()
	_test_forced_struggle_does_not_clobber_queued_item()
	_test_negative_control_move_vs_move_unaffected()
	_test_negative_control_move_vs_switch_unaffected()
	_test_full_heal_data_integrity()
	_test_full_heal_cures_status_and_confusion_and_infatuation()
	_test_full_heal_already_healthy_is_noop()
	_test_full_heal_cures_active_ally_confusion_in_doubles()
	_test_x_attack_data_integrity()
	_test_x_attack_basic_boost()
	_test_x_attack_already_max_stage_is_noop()
	_test_x_attack_fainted_target_is_noop()
	_test_poke_ball_data_integrity()
	_test_poke_ball_always_fails_regardless_of_target_state()
	_test_poke_ball_targets_opponent_not_own_party()
	_test_poke_ball_doubles_target_choice()
	_test_poke_ball_shares_front_tier()

	var total := _pass + _fail
	print("m22_item_action_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


func _load_item(id: int) -> ItemData:
	return ItemRegistry.get_item(id)


func _make_mon(mon_name: String, base_hp: int = 100, spd: int = 60,
		mon_type: int = TypeChart.TYPE_NORMAL) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types = [mon_type]
	sp.base_hp = base_hp
	sp.base_attack = 60
	sp.base_defense = 60
	sp.base_sp_attack = 60
	sp.base_sp_defense = 60
	sp.base_speed = spd
	var mon := BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])
	# Every fixture gets a real move (Splash — a genuine no-op, zero HP/status
	# side effects) by default so queue_move(side, 0) is always valid without
	# confounding any of this file's own HP-delta assertions with unrelated
	# damage from an "opponent acts normally" filler turn. BattlePokemon.
	# from_species leaves moves=[] otherwise, and a null chosen_move reaching
	# PRE_MOVE_CHECKS/MOVE_EXECUTION would crash.
	mon.add_move(load("res://data/moves/move_0150.tres") as MoveData)
	return mon


# Runs phases DIRECTLY (no advance()/start_battle*) from MOVE_SELECTION
# through to (but not including) the NEXT turn's own MOVE_SELECTION — i.e.
# exactly one turn's worth of actions, sidestepping the documented whole-
# battle-aggregation pitfall entirely by construction rather than by
# snapshotting mid-battle. Caller must set bm._parties/_combatants/
# _active_per_side and populate _action_queues (via queue_item_for/queue_move/
# queue_switch_for) before calling this.
func _dispatch_one_turn(bm: BattleManager,
		start_phase: BattleManager.BattlePhase = BattleManager.BattlePhase.MOVE_SELECTION) -> void:
	bm._set_phase(start_phase)
	var guard := 0
	while bm.get_phase() != BattleManager.BattlePhase.END_OF_TURN and guard < 200:
		var phase_before: BattleManager.BattlePhase = bm.get_phase()
		bm._dispatch_phase()
		guard += 1
		if bm.get_phase() == phase_before:
			break
	if guard >= 200:
		push_error("_dispatch_one_turn: exceeded safety cap, phase=%d" % bm.get_phase())


# Pre-sizes every per-combatant chosen-action array to match _combatants —
# _phase_move_selection assigns into these by index without growing them, so
# they must already be the right size before it's ever called directly
# (start_battle*() normally does this; these direct-dispatch tests must do it
# themselves, matching the existing _dispatch_acupressure-style precedent).
func _init_chosen_arrays(bm: BattleManager) -> void:
	var n: int = bm._combatants.size()
	bm._chosen_moves = []
	bm._chosen_switch_slots = []
	bm._chosen_targets = []
	bm._chosen_items = []
	bm._chosen_item_targets = []
	for i in range(n):
		bm._chosen_moves.append(null)
		bm._chosen_switch_slots.append(-1)
		bm._chosen_targets.append(0)
		bm._chosen_items.append(null)
		bm._chosen_item_targets.append(-1)


func _make_singles_bm(attacker: BattlePokemon, bench: BattlePokemon,
		opponent: BattlePokemon) -> Dictionary:
	var bm := BattleManager.new()
	add_child(bm)
	var party0 := BattleParty.new()
	party0.members = [attacker, bench]
	party0.active_indices = [0]
	var party1 := BattleParty.single(opponent)
	bm._parties = [party0, party1]
	bm._combatants = [attacker, opponent]
	bm._active_per_side = 1
	_init_chosen_arrays(bm)
	return {"bm": bm, "party0": party0, "party1": party1}


# ── Section A: data integrity ────────────────────────────────────────────────

func _test_data_integrity() -> void:
	var potion := _load_item(28)
	_chk("Potion(28) loads as a real ItemData", potion != null)
	_chk("Potion battle_usage == BATTLE_USE_RESTORE_HP",
			potion.battle_usage == ItemManager.BATTLE_USE_RESTORE_HP)
	_chk("Potion hold_effect_param == 20 (flat heal amount)",
			potion.hold_effect_param == 20)
	_chk("Potion hold_effect == 0 (never held, matching source's real struct)",
			potion.hold_effect == 0)


# ── Section B: singles basic heal ────────────────────────────────────────────

func _test_singles_basic_heal() -> void:
	var atk := _make_mon("B_Atk", 100)
	var bench := _make_mon("B_Bench", 100)
	var opp := _make_mon("B_Opp", 100)
	atk.current_hp = 50
	var setup := _make_singles_bm(atk, bench, opp)
	var bm: BattleManager = setup["bm"]

	var healed_events: Array = []
	bm.item_healed.connect(func(mon, amount): healed_events.append([mon, amount]))
	var used_events: Array = []
	bm.item_action_used.connect(func(user, item, target): used_events.append([user, item, target]))

	bm.queue_item_for(0, 28)  # party_target defaults to the active slot (atk itself)
	bm.queue_move(1, 0)  # opponent just attacks normally
	_dispatch_one_turn(bm)

	_chk("singles basic heal: item_action_used fired exactly once",
			used_events.size() == 1)
	# [Verification pass] the item itself (index 1) was never actually checked
	# here despite the label claiming "user/item/target" — fixed to confirm
	# all three, not just user and target.
	_chk("singles basic heal: item_action_used named the real user/item/target",
			used_events.size() == 1 and used_events[0][0] == atk
			and used_events[0][1] == _load_item(28)
			and used_events[0][2] == atk)
	_chk("singles basic heal: item_healed fired with +20",
			healed_events.size() == 1 and healed_events[0][1] == 20)
	_chk("singles basic heal: attacker's current_hp is 70 (50+20)",
			atk.current_hp == 70)
	_chk("singles basic heal: bench mon untouched", bench.current_hp == bench.max_hp)


# ── Section C: bench targeting ───────────────────────────────────────────────

func _test_bench_targeting() -> void:
	var active_mon := _make_mon("C_Active", 100)
	var bench := _make_mon("C_Bench", 100)
	var opp := _make_mon("C_Opp", 100)
	bench.current_hp = 30
	var setup := _make_singles_bm(active_mon, bench, opp)
	var bm: BattleManager = setup["bm"]

	var healed_events: Array = []
	bm.item_healed.connect(func(mon, amount): healed_events.append([mon, amount]))

	bm.queue_item_for(0, 28, 1)  # party_target=1 -> the BENCHED mon, not the active one
	bm.queue_move(1, 0)
	_dispatch_one_turn(bm)

	_chk("bench targeting: item_healed fired on the BENCHED mon",
			healed_events.size() == 1 and healed_events[0][0] == bench)
	_chk("bench targeting: benched mon healed 30->50", bench.current_hp == 50)
	_chk("bench targeting: active mon untouched (was never the target)",
			active_mon.current_hp == active_mon.max_hp)


# ── Section D: doubles targeting ─────────────────────────────────────────────

func _test_doubles_targeting() -> void:
	var a0 := _make_mon("D_A0", 100)
	var a1 := _make_mon("D_A1", 100)
	var bench := _make_mon("D_Bench", 100)
	var b0 := _make_mon("D_B0", 100)
	var b1 := _make_mon("D_B1", 100)
	a1.current_hp = 40  # A1 is active but NOT the acting combatant (A0 is)

	var bm := BattleManager.new()
	add_child(bm)
	var party0 := BattleParty.new()
	party0.members = [a0, a1, bench]
	party0.active_indices = [0, 1]
	var party1 := BattleParty.new()
	party1.members = [b0, b1]
	party1.active_indices = [0, 1]
	bm._parties = [party0, party1]
	bm._combatants = [a0, a1, b0, b1]
	bm._active_per_side = 2
	_init_chosen_arrays(bm)

	var healed_events: Array = []
	bm.item_healed.connect(func(mon, amount): healed_events.append([mon, amount]))

	# A0 (combatant 0) uses the item, explicitly targeting A1 (party slot 1) --
	# the doubles-specific nuance: A0's TRAINER chooses which of its own two
	# active Pokémon (or the bench) receives the effect, independent of which
	# combatant is actually taking the "use item" action this turn.
	bm.queue_item_for(0, 28, 1)
	bm.queue_move_targeted(1, 0, 2)
	bm.queue_move_targeted(2, 0, 0)
	bm.queue_move_targeted(3, 0, 0)
	_dispatch_one_turn(bm)

	_chk("doubles targeting: item_healed fired on A1 (the chosen ally slot), not A0",
			healed_events.size() == 1 and healed_events[0][0] == a1)
	_chk("doubles targeting: A1 healed 40->60", a1.current_hp == 60)
	_chk("doubles targeting: A0 (the acting combatant) itself untouched",
			a0.current_hp == a0.max_hp)
	_chk("doubles targeting: bench mon untouched", bench.current_hp == bench.max_hp)


# ── Section E: Potion's own restrictions ─────────────────────────────────────

func _test_already_full_hp_is_noop() -> void:
	var atk := _make_mon("E1_Atk", 100)
	var bench := _make_mon("E1_Bench", 100)
	var opp := _make_mon("E1_Opp", 100)
	# atk is already at full HP -- source: item_use.c's CannotUseItemsInBattle,
	# EFFECT_ITEM_RESTORE_HP case: `hp == GetMonData(mon, MON_DATA_MAX_HP) -> cannotUse`.
	var setup := _make_singles_bm(atk, bench, opp)
	var bm: BattleManager = setup["bm"]

	var healed_events: Array = []
	bm.item_healed.connect(func(mon, amount): healed_events.append([mon, amount]))
	var used_events: Array = []
	bm.item_action_used.connect(func(user, item, target): used_events.append(target))

	bm.queue_item_for(0, 28)
	bm.queue_move(1, 0)
	_dispatch_one_turn(bm)

	_chk("already-full-HP: the action still resolves (item_action_used fires)",
			used_events.size() == 1)
	_chk("already-full-HP: no heal event fires (pure no-op, not an error)",
			healed_events.is_empty())
	_chk("already-full-HP: HP stays exactly at max, no overheal",
			atk.current_hp == atk.max_hp)


func _test_fainted_target_is_noop() -> void:
	var active_mon := _make_mon("E2_Active", 100)
	var fainted_bench := _make_mon("E2_Bench", 100)
	var opp := _make_mon("E2_Opp", 100)
	fainted_bench.current_hp = 0
	fainted_bench.fainted = true
	# Source: `hp == 0 -> cannotUse` (item_use.c, same EFFECT_ITEM_RESTORE_HP case).
	var setup := _make_singles_bm(active_mon, fainted_bench, opp)
	var bm: BattleManager = setup["bm"]

	var healed_events: Array = []
	bm.item_healed.connect(func(mon, amount): healed_events.append([mon, amount]))
	var used_events: Array = []
	bm.item_action_used.connect(func(user, item, target): used_events.append(target))

	bm.queue_item_for(0, 28, 1)  # targets the fainted bench mon specifically
	bm.queue_move(1, 0)
	_dispatch_one_turn(bm)

	# [Verification pass] added for consistency with E1's own thoroughness —
	# confirms the action still resolves as an attempt (distinct from being
	# silently rejected outright), even though its effect is correctly a no-op.
	_chk("fainted target: the action still resolves (item_action_used fires)",
			used_events.size() == 1)
	_chk("fainted target: no heal event fires", healed_events.is_empty())
	_chk("fainted target: current_hp stays at 0 (a Potion can't revive)",
			fainted_bench.current_hp == 0)


# ── Section F: turn-order generalization ─────────────────────────────────────

func _test_turn_order_item_ahead_of_faster_move() -> void:
	# The item-using combatant is deliberately much SLOWER than the move-using
	# opponent -- proving front-tier placement is independent of speed, not
	# just "usually resolves first because items also tend to be fast."
	var atk := _make_mon("F1_Atk", 100, 5)   # very slow
	var bench := _make_mon("F1_Bench", 100)
	var opp := _make_mon("F1_Opp", 100, 200)  # very fast
	var setup := _make_singles_bm(atk, bench, opp)
	var bm: BattleManager = setup["bm"]

	bm.queue_item_for(0, 28)
	bm.queue_move(1, 0)
	bm._phase_move_selection()
	bm._phase_priority_resolution()

	_chk("turn order: the slow item-user is still FIRST in _turn_order",
			bm._turn_order[0] == atk)
	_chk("turn order: the fast move-user is SECOND", bm._turn_order[1] == opp)


func _test_turn_order_item_and_switch_same_tier_battler_order() -> void:
	# Combatant 0 uses an item, combatant 1 (a doubles partner slot) switches --
	# both are front-tier actions; source places them in raw BATTLER-INDEX
	# order among themselves (battle_main.c L4967-4990), not speed order.
	var a0 := _make_mon("F2_A0", 100, 5)
	var a1 := _make_mon("F2_A1", 100, 200)  # much faster than a0, but still a switcher
	var a_bench := _make_mon("F2_ABench", 100)
	var b0 := _make_mon("F2_B0", 100)
	var b1 := _make_mon("F2_B1", 100)

	var bm := BattleManager.new()
	add_child(bm)
	var party0 := BattleParty.new()
	party0.members = [a0, a1, a_bench]
	party0.active_indices = [0, 1]
	var party1 := BattleParty.new()
	party1.members = [b0, b1]
	party1.active_indices = [0, 1]
	bm._parties = [party0, party1]
	bm._combatants = [a0, a1, b0, b1]
	bm._active_per_side = 2
	_init_chosen_arrays(bm)

	bm.queue_item_for(0, 28)
	bm.queue_switch_for(1, 2)  # a1 switches to the bench slot
	bm.queue_move_targeted(2, 0, 0)
	bm.queue_move_targeted(3, 0, 0)
	bm._phase_move_selection()
	bm._phase_priority_resolution()

	_chk("front tier: combatant 0 (item) sorts before combatant 1 (switch) -- battler order",
			bm._turn_order.find(a0) < bm._turn_order.find(a1))
	_chk("front tier: both front-tier actors sort before both move-users",
			bm._turn_order.find(a0) < bm._turn_order.find(b0)
			and bm._turn_order.find(a1) < bm._turn_order.find(b0))


# ── Section G: choice-lock / forced-Struggle fix ─────────────────────────────

func _test_choice_lock_does_not_clobber_queued_item() -> void:
	var atk := _make_mon("G1_Atk", 100)
	var bench := _make_mon("G1_Bench", 100)
	var opp := _make_mon("G1_Opp", 100)
	atk.current_hp = 50
	var tackle := load("res://data/moves/move_0033.tres") as MoveData  # Tackle
	atk.moves = [tackle]
	atk.current_pp = [tackle.pp]
	atk.choice_locked_move = tackle  # simulates a Choice-item lock already in effect
	var setup := _make_singles_bm(atk, bench, opp)
	var bm: BattleManager = setup["bm"]

	# [Verification pass] The ORIGINAL version of this test only checked the
	# dispatch OUTCOME (item_action_used fired, HP healed) — but
	# _phase_action_execution checks _chosen_items BEFORE it ever looks at
	# _chosen_moves, so that outcome is invariant regardless of whether the
	# choice-lock guard exists: even with the guard removed, _chosen_moves[0]
	# gets silently overwritten to `tackle` but _chosen_items[0] is untouched,
	# so the item branch still wins in _phase_action_execution and the test
	# would pass either way. Confirmed empirically (guard temporarily
	# stripped, suite still reported 33/33). The REAL, fix-specific property
	# is what _phase_move_selection itself leaves in _chosen_moves — this is
	# checked directly below, in addition to (not instead of) the dispatch-
	# outcome checks, which remain valid confirmations of the end-to-end
	# behavior even though they alone don't discriminate the fix.
	bm.queue_item_for(0, 28)
	bm.queue_move(1, 0)
	bm._phase_move_selection()
	_chk("choice-lock fix: _chosen_moves[0] stays null (NOT overwritten to the locked move)",
			bm._chosen_moves[0] == null)
	_chk("choice-lock fix: _chosen_items[0] still holds the queued item",
			bm._chosen_items[0] != null)

	var used_events: Array = []
	bm.item_action_used.connect(func(user, item, target): used_events.append(target))
	_dispatch_one_turn(bm, BattleManager.BattlePhase.PRIORITY_RESOLUTION)

	_chk("choice-lock fix: the queued item action was NOT overridden into the locked move",
			used_events.size() == 1)
	_chk("choice-lock fix: the item's heal actually applied", atk.current_hp == 70)


func _test_forced_struggle_does_not_clobber_queued_item() -> void:
	var atk := _make_mon("G2_Atk", 100)
	var bench := _make_mon("G2_Bench", 100)
	var opp := _make_mon("G2_Opp", 100)
	atk.current_hp = 50
	var tackle := load("res://data/moves/move_0033.tres") as MoveData
	atk.moves = [tackle]
	atk.current_pp = [0]  # every move at 0 PP -> _is_forced_struggle would fire
	var setup := _make_singles_bm(atk, bench, opp)
	var bm: BattleManager = setup["bm"]

	# Same fix-specific selection-phase check as the choice-lock test above —
	# see that test's own comment for why the dispatch-outcome checks alone
	# don't discriminate this fix.
	bm.queue_item_for(0, 28)
	bm.queue_move(1, 0)
	bm._phase_move_selection()
	_chk("forced-Struggle fix: _chosen_moves[0] stays null (NOT overwritten to Struggle)",
			bm._chosen_moves[0] == null)
	_chk("forced-Struggle fix: _chosen_items[0] still holds the queued item",
			bm._chosen_items[0] != null)

	var used_events: Array = []
	bm.item_action_used.connect(func(user, item, target): used_events.append(target))
	_dispatch_one_turn(bm, BattleManager.BattlePhase.PRIORITY_RESOLUTION)

	_chk("forced-Struggle fix: the queued item action was NOT overridden into Struggle",
			used_events.size() == 1)
	_chk("forced-Struggle fix: the item's heal actually applied", atk.current_hp == 70)


# ── Section H: negative controls ─────────────────────────────────────────────

func _test_negative_control_move_vs_move_unaffected() -> void:
	var atk := _make_mon("H1_Atk", 100, 100)
	var opp := _make_mon("H1_Opp", 100, 50)
	var bm := BattleManager.new()
	add_child(bm)
	var tackle := load("res://data/moves/move_0033.tres") as MoveData
	atk.moves = [tackle]
	atk.current_pp = [tackle.pp]
	opp.moves = [tackle]
	opp.current_pp = [tackle.pp]
	bm._parties = [BattleParty.single(atk), BattleParty.single(opp)]
	bm._combatants = [atk, opp]
	bm._active_per_side = 1
	_init_chosen_arrays(bm)

	bm.queue_move(0, 0)
	bm.queue_move(1, 0)
	bm._phase_move_selection()
	bm._phase_priority_resolution()

	_chk("negative control: ordinary move-vs-move turn order still speed-based (attacker first)",
			bm._turn_order[0] == atk)
	_chk("negative control: no combatant has a chosen item", bm._chosen_items[0] == null
			and bm._chosen_items[1] == null)


func _test_negative_control_move_vs_switch_unaffected() -> void:
	# [Verification pass] The ORIGINAL version of this fixture made the
	# SWITCHING mon (opp) faster than the move-user (atk) — meaning this test
	# would have passed even if the switch-tier mechanism were completely
	# disabled, since opp would still sort first by raw speed alone.
	# Confirmed empirically: with the front-tier check hardcoded to `false`
	# for both sides, this specific test still reported a pass while every
	# other turn-order test correctly failed. Fixed by making the SWITCHER
	# deliberately SLOWER than the move-user, so the assertion only holds if
	# switch-tier placement genuinely overrides speed.
	var atk := _make_mon("H2_Atk", 100, 200)  # fast, but only using a move
	var bench := _make_mon("H2_Bench", 100)
	var opp := _make_mon("H2_Opp", 100, 5)  # slow, but switching
	var bm := BattleManager.new()
	add_child(bm)
	var tackle := load("res://data/moves/move_0033.tres") as MoveData
	atk.moves = [tackle]
	atk.current_pp = [tackle.pp]
	var party1 := BattleParty.new()
	party1.members = [opp, bench]
	party1.active_indices = [0]
	bm._parties = [BattleParty.single(atk), party1]
	bm._combatants = [atk, opp]
	bm._active_per_side = 1
	_init_chosen_arrays(bm)

	bm.queue_move(0, 0)
	bm.queue_switch(1, 1)
	bm._phase_move_selection()
	bm._phase_priority_resolution()

	_chk("negative control: switch still sorts ahead of move (pre-existing behavior unchanged)",
			bm._turn_order[0] == opp)
	_chk("negative control: the switcher has no chosen item (still purely a switch)",
			bm._chosen_items[1] == null and bm._chosen_switch_slots[1] == 1)


# ── Section I: Full Heal (M22 Phase 2) ───────────────────────────────────────

func _test_full_heal_data_integrity() -> void:
	var full_heal := _load_item(48)
	_chk("Full Heal(48) loads as a real ItemData", full_heal != null)
	_chk("Full Heal battle_usage == BATTLE_USE_CURE_STATUS",
			full_heal.battle_usage == ItemManager.BATTLE_USE_CURE_STATUS)


func _test_full_heal_cures_status_and_confusion_and_infatuation() -> void:
	var atk := _make_mon("I1_Atk", 100)
	var bench := _make_mon("I1_Bench", 100)
	var opp := _make_mon("I1_Opp", 100)
	atk.status = BattlePokemon.STATUS_POISON
	atk.confusion_turns = 3
	atk.infatuated_by = opp  # some other mon infatuated atk
	var setup := _make_singles_bm(atk, bench, opp)
	var bm: BattleManager = setup["bm"]

	var cured_events: Array = []
	bm.party_status_cured.connect(func(mon): cured_events.append(mon))

	bm.queue_item_for(0, 48)
	bm.queue_move(1, 0)
	_dispatch_one_turn(bm)

	_chk("Full Heal: party_status_cured fired on the target",
			cured_events.size() == 1 and cured_events[0] == atk)
	_chk("Full Heal: non-volatile status cleared",
			atk.status == BattlePokemon.STATUS_NONE)
	_chk("Full Heal: confusion cleared (a real scope difference from Heal Bell)",
			atk.confusion_turns == 0)
	_chk("Full Heal: infatuation cleared (same scope difference)",
			atk.infatuated_by == null)


func _test_full_heal_already_healthy_is_noop() -> void:
	var atk := _make_mon("I2_Atk", 100)
	var bench := _make_mon("I2_Bench", 100)
	var opp := _make_mon("I2_Opp", 100)
	# atk has no status, no confusion, no infatuation -- nothing to cure.
	var setup := _make_singles_bm(atk, bench, opp)
	var bm: BattleManager = setup["bm"]

	var cured_events: Array = []
	bm.party_status_cured.connect(func(mon): cured_events.append(mon))
	var used_events: Array = []
	bm.item_action_used.connect(func(user, item, target): used_events.append(target))

	bm.queue_item_for(0, 48)
	bm.queue_move(1, 0)
	_dispatch_one_turn(bm)

	_chk("Full Heal already-healthy: the action still resolves (item_action_used fires)",
			used_events.size() == 1)
	_chk("Full Heal already-healthy: no cure event fires (pure no-op, not an error)",
			cured_events.is_empty())


# [M22 Final Review] The one genuinely un-exercised doubles scenario:
# Full Heal's confusion/infatuation cure specifically for an ACTIVE ALLY.
# Every other doubles-targeting proof (Section D, Poké Ball's own doubles
# test) already confirms the shared party_target resolution mechanism works
# correctly in doubles — that part is NOT re-tested here on purpose, it
# would be pure repetition. What's new: source's real ItemHealMonVolatile
# restricts the confusion/infatuation half to "the active battler OR its
# doubles partner" — in singles, the only non-self target is always
# BENCHED (confusion_turns/infatuated_by provably always 0 there, per
# _clear_volatiles), so Section I's own singles test can only ever prove
# the self-cure case. An ACTIVE ally is the one case where the target
# genuinely CAN carry nonzero confusion/infatuation — this test closes
# that specific gap.
func _test_full_heal_cures_active_ally_confusion_in_doubles() -> void:
	var a0 := _make_mon("I3_A0", 100)
	var a1 := _make_mon("I3_A1", 100)
	var a_bench := _make_mon("I3_ABench", 100)
	var b0 := _make_mon("I3_B0", 100)
	var b1 := _make_mon("I3_B1", 100)
	a1.confusion_turns = 3
	a1.infatuated_by = b0

	var bm := BattleManager.new()
	add_child(bm)
	var party0 := BattleParty.new()
	party0.members = [a0, a1, a_bench]
	party0.active_indices = [0, 1]
	var party1 := BattleParty.new()
	party1.members = [b0, b1]
	party1.active_indices = [0, 1]
	bm._parties = [party0, party1]
	bm._combatants = [a0, a1, b0, b1]
	bm._active_per_side = 2
	_init_chosen_arrays(bm)

	var cured_events: Array = []
	bm.party_status_cured.connect(func(mon): cured_events.append(mon))

	bm.queue_item_for(0, 48, 1)  # A0 uses Full Heal, targeting A1 (party slot 1)
	bm.queue_move_targeted(1, 0, 2)
	bm.queue_move_targeted(2, 0, 0)
	bm.queue_move_targeted(3, 0, 0)
	_dispatch_one_turn(bm)

	_chk("Full Heal doubles: party_status_cured fired on the active ally A1",
			cured_events.size() == 1 and cured_events[0] == a1)
	_chk("Full Heal doubles: active ally's confusion cleared",
			a1.confusion_turns == 0)
	_chk("Full Heal doubles: active ally's infatuation cleared",
			a1.infatuated_by == null)


# ── Section J: X Attack (M22 Phase 2) ────────────────────────────────────────

func _test_x_attack_data_integrity() -> void:
	var x_attack := _load_item(121)
	_chk("X Attack(121) loads as a real ItemData", x_attack != null)
	_chk("X Attack battle_usage == BATTLE_USE_INCREASE_STAT",
			x_attack.battle_usage == ItemManager.BATTLE_USE_INCREASE_STAT)
	_chk("X Attack stat_boost_stage == STAGE_ATK",
			x_attack.stat_boost_stage == BattlePokemon.STAGE_ATK)


func _test_x_attack_basic_boost() -> void:
	var atk := _make_mon("J1_Atk", 100)
	var bench := _make_mon("J1_Bench", 100)
	var opp := _make_mon("J1_Opp", 100)
	var setup := _make_singles_bm(atk, bench, opp)
	var bm: BattleManager = setup["bm"]

	var stage_events: Array = []
	bm.stat_stage_changed.connect(
			func(mon, stat_idx, actual): stage_events.append([mon, stat_idx, actual]))

	bm.queue_item_for(0, 121)
	bm.queue_move(1, 0)
	_dispatch_one_turn(bm)

	_chk("X Attack: stat_stage_changed fired with +2 on STAGE_ATK (not +1)",
			stage_events.size() == 1 and stage_events[0][0] == atk
			and stage_events[0][1] == BattlePokemon.STAGE_ATK
			and stage_events[0][2] == 2)
	_chk("X Attack: attacker's own Attack stage is now +2",
			atk.stat_stages[BattlePokemon.STAGE_ATK] == 2)


func _test_x_attack_already_max_stage_is_noop() -> void:
	var atk := _make_mon("J2_Atk", 100)
	var bench := _make_mon("J2_Bench", 100)
	var opp := _make_mon("J2_Opp", 100)
	atk.stat_stages[BattlePokemon.STAGE_ATK] = 6  # already maxed
	var setup := _make_singles_bm(atk, bench, opp)
	var bm: BattleManager = setup["bm"]

	var stage_events: Array = []
	bm.stat_stage_changed.connect(
			func(mon, stat_idx, actual): stage_events.append([mon, stat_idx, actual]))
	var used_events: Array = []
	bm.item_action_used.connect(func(user, item, target): used_events.append(target))

	bm.queue_item_for(0, 121)
	bm.queue_move(1, 0)
	_dispatch_one_turn(bm)

	_chk("X Attack already-maxed: the action still resolves", used_events.size() == 1)
	_chk("X Attack already-maxed: no stage-change event fires",
			stage_events.is_empty())
	_chk("X Attack already-maxed: stage stays at exactly +6, no overflow",
			atk.stat_stages[BattlePokemon.STAGE_ATK] == 6)


func _test_x_attack_fainted_target_is_noop() -> void:
	var active_mon := _make_mon("J3_Active", 100)
	var fainted_bench := _make_mon("J3_Bench", 100)
	var opp := _make_mon("J3_Opp", 100)
	fainted_bench.current_hp = 0
	fainted_bench.fainted = true
	var setup := _make_singles_bm(active_mon, fainted_bench, opp)
	var bm: BattleManager = setup["bm"]

	var stage_events: Array = []
	bm.stat_stage_changed.connect(
			func(mon, stat_idx, actual): stage_events.append([mon, stat_idx, actual]))

	bm.queue_item_for(0, 121, 1)  # targets the fainted bench mon specifically
	bm.queue_move(1, 0)
	_dispatch_one_turn(bm)

	_chk("X Attack fainted target: no stage-change event fires (source's hp==0 gate)",
			stage_events.is_empty())
	_chk("X Attack fainted target: stage stays at 0",
			fainted_bench.stat_stages[BattlePokemon.STAGE_ATK] == 0)


# ── Section K: Poké Ball placeholder (M22 Phase 2) ───────────────────────────

func _test_poke_ball_data_integrity() -> void:
	var poke_ball := _load_item(1)
	_chk("Poké Ball(1) loads as a real ItemData", poke_ball != null)
	_chk("Poké Ball battle_usage == BATTLE_USE_THROW_BALL",
			poke_ball.battle_usage == ItemManager.BATTLE_USE_THROW_BALL)


func _test_poke_ball_always_fails_regardless_of_target_state() -> void:
	# Deliberately lethal-HP + status-inflicted target -- proving the M22
	# stub never catches, not even in the "should be easy" case.
	var atk := _make_mon("K1_Atk", 100)
	var bench := _make_mon("K1_Bench", 100)
	var opp := _make_mon("K1_Opp", 100)
	opp.current_hp = 1
	opp.status = BattlePokemon.STATUS_SLEEP
	opp.sleep_turns = 3  # must be nonzero or opp wakes up during its own
	                     # pre-move check this same turn, confounding the assertion
	var setup := _make_singles_bm(atk, bench, opp)
	var bm: BattleManager = setup["bm"]

	var catch_events: Array = []
	bm.catch_attempted.connect(
			func(user, target, item, caught): catch_events.append([user, target, item, caught]))

	bm.queue_item_for(0, 1)
	bm.queue_move(1, 0)
	_dispatch_one_turn(bm)

	_chk("Poké Ball: catch_attempted fired exactly once",
			catch_events.size() == 1)
	_chk("Poké Ball: the catch always fails (M22 stub, not yet M27's real math)",
			catch_events.size() == 1 and catch_events[0][3] == false)
	_chk("Poké Ball: the target is completely untouched (no capture, no side effect)",
			opp.current_hp == 1 and opp.status == BattlePokemon.STATUS_SLEEP)


func _test_poke_ball_targets_opponent_not_own_party() -> void:
	# [Verification-standard check] The trickiest new assertion this session —
	# Poké Ball is the first item whose target ISN'T the acting trainer's own
	# party (a genuine design decision, not explicit in the recon). Verified
	# empirically, not just by inspection: temporarily reverting _do_item_use's
	# Ball branch to resolve its target via party_target/_parties[side].members
	# (the SAME resolution the other 3 items use) made this exact assertion
	# fail (catch_events[0] became atk or bench, never opp) while every other
	# assertion in this suite still passed — confirming this test is a real
	# discriminator of the fix, not incidentally true.
	var atk := _make_mon("K2_Atk", 100)
	var bench := _make_mon("K2_Bench", 100)
	var opp := _make_mon("K2_Opp", 100)
	var setup := _make_singles_bm(atk, bench, opp)
	var bm: BattleManager = setup["bm"]

	var catch_events: Array = []
	bm.catch_attempted.connect(func(user, target, item, caught): catch_events.append(target))

	bm.queue_item_for(0, 1)
	bm.queue_move(1, 0)
	_dispatch_one_turn(bm)

	_chk("Poké Ball: targets the OPPONENT (opp), not the user's own party",
			catch_events.size() == 1 and catch_events[0] == opp)


func _test_poke_ball_doubles_target_choice() -> void:
	var a0 := _make_mon("K3_A0", 100)
	var a1 := _make_mon("K3_A1", 100)
	var a_bench := _make_mon("K3_ABench", 100)
	var b0 := _make_mon("K3_B0", 100)
	var b1 := _make_mon("K3_B1", 100)

	var bm := BattleManager.new()
	add_child(bm)
	var party0 := BattleParty.new()
	party0.members = [a0, a1, a_bench]
	party0.active_indices = [0, 1]
	var party1 := BattleParty.new()
	party1.members = [b0, b1]
	party1.active_indices = [0, 1]
	bm._parties = [party0, party1]
	bm._combatants = [a0, a1, b0, b1]
	bm._active_per_side = 2
	_init_chosen_arrays(bm)

	var catch_events: Array = []
	bm.catch_attempted.connect(func(user, target, item, caught): catch_events.append(target))

	# A0 (combatant 0) throws a Ball explicitly targeting B1 (combatant index
	# 3), NOT the default first-opponent-slot (B0, combatant index 2) --
	# proving queue_item_for's new target_idx param genuinely drives which
	# opposing slot gets targeted, not just always the default.
	bm.queue_item_for(0, 1, -1, 3)
	bm.queue_move_targeted(1, 0, 2)
	bm.queue_move_targeted(2, 0, 0)
	bm.queue_move_targeted(3, 0, 0)
	_dispatch_one_turn(bm)

	_chk("Poké Ball doubles: explicit target_idx correctly picks B1, not the default B0",
			catch_events.size() == 1 and catch_events[0] == b1)


func _test_poke_ball_shares_front_tier() -> void:
	var atk := _make_mon("K4_Atk", 100, 5)   # very slow
	var bench := _make_mon("K4_Bench", 100)
	var opp := _make_mon("K4_Opp", 100, 200)  # very fast
	var setup := _make_singles_bm(atk, bench, opp)
	var bm: BattleManager = setup["bm"]

	bm.queue_item_for(0, 1)
	bm.queue_move(1, 0)
	bm._phase_move_selection()
	bm._phase_priority_resolution()

	_chk("Poké Ball turn order: the slow ball-thrower is still FIRST (front tier)",
			bm._turn_order[0] == atk)
