extends Node

# [M20c] EV-gain grant logic — the last piece of M20's original 4-part
# sequence (data pipeline -> core dispatch -> EV-gain grant logic ->
# level-up move learning; the other 3 shipped in M20a/[M20 EXP
# implementation]/M20b).
#
# Full source citations live in docs/decisions.md's `[M20c]` entry — not
# repeated here in full, only the load-bearing facts this suite exists to
# prove:
#  - EVs are granted at FULL base yield to every eligible recipient,
#    regardless of participant count — NO analog of Exp's own custom
#    100/65/55/50/45/40% distribution table applies to EVs (source's
#    MonGainEVs takes no participant-count parameter at all).
#  - Formula/order exactly as traced: base ev_yield_X -> Power Item +8 to
#    its one targeted stat -> Macho Brace x2 -> clamp vs remaining TOTAL
#    cap room (510) -> clamp vs remaining PER-STAT cap room (252) -> add.
#  - Iterates in THIS PROJECT'S OWN STAT_* order (HP/ATK/DEF/SPATK/SPDEF/
#    SPEED), not source's raw enum order — matters when the total cap is
#    hit mid-loop (the loop breaks ENTIRELY, no partial credit to
#    remaining stats that event).
#  - EV-eligibility is the SAME `alive_participants` set already computed
#    for Exp — traced and confirmed identical, not a separate mechanism.
#  - Granting EVs alone does NOT retroactively recompute current battle
#    stats — only `_check_level_up`'s own `_calculate_stats()` call does
#    that, matching source exactly.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_data_integrity()
	_test_basic_grant()
	_test_full_value_always_vs_exp_distribution()
	_test_per_stat_cap()
	_test_total_cap_breaks_loop_in_stat_order()
	_test_power_item_bonus()
	_test_macho_brace_doubling()
	_test_power_item_and_macho_brace_are_mutually_exclusive()
	_test_max_level_still_gains_evs()
	_test_evs_do_not_retroactively_change_stats()
	_test_klutz_suppresses_item_bonus()
	_test_player_side_faint_negative_control()

	var total := _pass + _fail
	print("m20c_test: %d/%d passed" % [_pass, total])
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


# Synthetic species with fully controllable ev_yield_* — same convention
# m20_exp_test.gd's own `_make_mon` established for exp_yield.
func _make_mon(mon_name: String, level: int,
		ev_yields: Array = [0, 0, 0, 0, 0, 0]) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types = [TypeChart.TYPE_NORMAL]
	sp.base_hp = 100
	sp.base_attack = 60
	sp.base_defense = 60
	sp.base_sp_attack = 60
	sp.base_sp_defense = 60
	sp.base_speed = 60
	sp.ev_yield_hp  = ev_yields[0]
	sp.ev_yield_atk = ev_yields[1]
	sp.ev_yield_def = ev_yields[2]
	sp.ev_yield_spa = ev_yields[3]
	sp.ev_yield_spd = ev_yields[4]
	sp.ev_yield_spe = ev_yields[5]
	return BattlePokemon.from_species(sp, level, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])


# ── Section A: data integrity ─────────────────────────────────────────────

func _test_data_integrity() -> void:
	_chk("A.1 EV_CAP_PER_STAT == 252 (Gen VI+, P_EV_CAP=GEN_LATEST at this project's config)",
			BattleManager.EV_CAP_PER_STAT == 252)
	_chk("A.2 EV_CAP_TOTAL == 510",
			BattleManager.EV_CAP_TOTAL == 510)
	_chk("A.3 POWER_ITEM_EV_BONUS == 8 (I_POWER_ITEM_BOOST>=GEN_7 at this project's config)",
			BattleManager.POWER_ITEM_EV_BONUS == 8)
	_chk("A.4 ItemData.ev_boost_stat defaults to -1 (not applicable)",
			ItemData.new().ev_boost_stat == -1)
	var power_weight: ItemData = ItemRegistry.get_item(419)
	_chk("A.5 Power Weight (419): ev_boost_stat == STAT_HP (0)",
			power_weight.ev_boost_stat == 0 and power_weight.hold_effect == ItemManager.HOLD_EFFECT_POWER_ITEM)
	var power_lens: ItemData = ItemRegistry.get_item(422)
	_chk("A.6 Power Lens (422): ev_boost_stat == STAT_SPATK (3), matching THIS PROJECT'S own STAT_ order, not source's raw enum order",
			power_lens.ev_boost_stat == 3)
	var power_anklet: ItemData = ItemRegistry.get_item(424)
	_chk("A.7 Power Anklet (424): ev_boost_stat == STAT_SPEED (5)",
			power_anklet.ev_boost_stat == 5)
	var macho_brace: ItemData = ItemRegistry.get_item(418)
	_chk("A.8 Macho Brace (418): ev_boost_stat stays -1 (not a Power Item, not stat-specific)",
			macho_brace.ev_boost_stat == -1 and macho_brace.hold_effect == ItemManager.HOLD_EFFECT_MACHO_BRACE)


# ── Section B: basic grant ─────────────────────────────────────────────────

func _test_basic_grant() -> void:
	var bm := _make_bm()
	var recipient := _make_mon("Recipient", 10)
	var fainted := _make_mon("Fainted", 10, [0, 0, 0, 1, 0, 0])  # yields 1 SPATK EV
	var gains: Array = []
	bm.ev_gained.connect(func(_p, stat_idx, amount): gains.append([stat_idx, amount]))
	bm._grant_evs(recipient, fainted.species)
	_chk("basic grant: recipient.evs[SPATK] increased by exactly 1",
			recipient.evs[BattlePokemon.STAT_SPATK] == 1)
	_chk("basic grant: every other stat stays at 0",
			recipient.evs[BattlePokemon.STAT_HP] == 0
			and recipient.evs[BattlePokemon.STAT_ATK] == 0
			and recipient.evs[BattlePokemon.STAT_DEF] == 0
			and recipient.evs[BattlePokemon.STAT_SPDEF] == 0
			and recipient.evs[BattlePokemon.STAT_SPEED] == 0)
	_chk("basic grant: ev_gained fired exactly once, for STAT_SPATK amount 1",
			gains == [[BattlePokemon.STAT_SPATK, 1]])


# ── Section C: full-value-always vs Exp's own distribution (KEY DISCRIMINATOR) ──

func _test_full_value_always_vs_exp_distribution() -> void:
	var bm := _make_bm()
	var a := _make_mon("A", 10)
	var b := _make_mon("B", 10)
	var fainted := _make_mon("Fainted", 10, [1, 1, 1, 1, 1, 1])  # 1 EV to every stat

	bm._exp_participants = [[0, 1]]
	bm._parties = [BattleParty.new(), BattleParty.single(fainted)]
	bm._parties[0].members = [a, b]
	bm._active_per_side = 1
	bm._combatants = [a, fainted]

	var exp_gains: Array = []
	bm.exp_gained.connect(func(p, amount): exp_gains.append([p, amount]))
	bm._award_exp_for_fainted_opponent(fainted)

	_chk("full-value-always: BOTH participants got the FULL, undivided EV yield (1 in every stat), despite 2 participants sharing the kill",
			a.evs == [1, 1, 1, 1, 1, 1] and b.evs == [1, 1, 1, 1, 1, 1])
	_chk("full-value-always vs Exp's own 65%-for-2-participants distribution: the two recipients' EXP amounts are IDENTICAL to each other (both scaled by the same distribution %), proving EVs are NOT similarly scaled -- if EVs used the same distribution model, this test's own recipients would show a reduced (non-full) EV total instead of the full [1,1,1,1,1,1] just confirmed above",
			exp_gains.size() == 2 and exp_gains[0][1] == exp_gains[1][1])


# ── Section D: both cap types independently ────────────────────────────────

func _test_per_stat_cap() -> void:
	var bm := _make_bm()
	var recipient := _make_mon("Recipient", 10)
	recipient.evs[BattlePokemon.STAT_DEF] = 251
	var fainted := _make_mon("Fainted", 10, [0, 0, 3, 0, 0, 0])  # yields 3 DEF EVs
	bm._grant_evs(recipient, fainted.species)
	_chk("per-stat cap: 251 + 3 would be 254, clamped to exactly 252 (not 254)",
			recipient.evs[BattlePokemon.STAT_DEF] == 252)


func _test_total_cap_breaks_loop_in_stat_order() -> void:
	var bm := _make_bm()
	var recipient := _make_mon("Recipient", 10)
	# total EVs = 252+252+4 = 508, well under any single stat's own 252 cap
	# individually except HP/ATK (already maxed).
	recipient.evs = [252, 252, 4, 0, 0, 0]
	# Yields 1 EV each to DEF(idx2)/SPATK(idx3)/SPDEF(idx4), in THIS
	# PROJECT'S OWN STAT_ order. 508 -> DEF fills to 509 -> SPATK fills to
	# 510 (== EV_CAP_TOTAL, no clamp triggered since it's not OVER 510) ->
	# loop breaks BEFORE ever reaching SPDEF, which gets nothing despite
	# the species yielding for it.
	var fainted := _make_mon("Fainted", 10, [0, 0, 1, 1, 1, 0])
	var gains: Array = []
	bm.ev_gained.connect(func(_p, stat_idx, amount): gains.append([stat_idx, amount]))
	bm._grant_evs(recipient, fainted.species)
	_chk("total cap: DEF (processed first in STAT_ order) gained its full +1 (4->5)",
			recipient.evs[BattlePokemon.STAT_DEF] == 5)
	_chk("total cap: SPATK (processed second) gained its full +1 (0->1), reaching exactly 510 total",
			recipient.evs[BattlePokemon.STAT_SPATK] == 1)
	_chk("total cap: SPDEF (processed LAST in STAT_ order) got NOTHING -- the loop broke entirely once total hit 510, no partial credit",
			recipient.evs[BattlePokemon.STAT_SPDEF] == 0)
	_chk("total cap: exactly 2 ev_gained events fired (DEF, SPATK) -- none for SPDEF",
			gains == [[BattlePokemon.STAT_DEF, 1], [BattlePokemon.STAT_SPATK, 1]])


# ── Section E: Power Item / Macho Brace ────────────────────────────────────

func _test_power_item_bonus() -> void:
	var bm := _make_bm()
	var recipient := _make_mon("Recipient", 10)
	recipient.held_item = ItemRegistry.get_item(422)  # Power Lens -> SPATK
	var fainted := _make_mon("Fainted", 10, [0, 0, 0, 2, 0, 0])  # yields 2 SPATK EVs
	bm._grant_evs(recipient, fainted.species)
	_chk("Power Item: base yield (2) + POWER_ITEM_EV_BONUS (8) = 10 SPATK EVs, added BEFORE any cap clamp",
			recipient.evs[BattlePokemon.STAT_SPATK] == 10)
	_chk("Power Item: does NOT affect a different stat's own yield (0 elsewhere)",
			recipient.evs[BattlePokemon.STAT_DEF] == 0)


func _test_macho_brace_doubling() -> void:
	var bm := _make_bm()
	var recipient := _make_mon("Recipient", 10)
	recipient.held_item = ItemRegistry.get_item(418)  # Macho Brace
	var fainted := _make_mon("Fainted", 10, [0, 1, 0, 0, 0, 2])  # yields 1 ATK, 2 SPEED
	bm._grant_evs(recipient, fainted.species)
	_chk("Macho Brace: doubles EVERY stat's own yield (1*2=2 ATK, 2*2=4 SPEED)",
			recipient.evs[BattlePokemon.STAT_ATK] == 2
			and recipient.evs[BattlePokemon.STAT_SPEED] == 4)


func _test_power_item_and_macho_brace_are_mutually_exclusive() -> void:
	# A single held item can only carry ONE hold_effect value -- Power Item
	# and Macho Brace can never combine on the same recipient in this
	# project (matches source's own real item roster: no item is both).
	# Confirms holding one doesn't accidentally also trigger the other's logic.
	var bm := _make_bm()
	var power_holder := _make_mon("PowerHolder", 10)
	power_holder.held_item = ItemRegistry.get_item(422)  # Power Lens
	var fainted := _make_mon("Fainted", 10, [0, 0, 0, 1, 0, 0])
	bm._grant_evs(power_holder, fainted.species)
	_chk("Power Item alone: +8 bonus applied, but NOT additionally doubled (1+8=9, not 18)",
			power_holder.evs[BattlePokemon.STAT_SPATK] == 9)

	var macho_holder := _make_mon("MachoHolder", 10)
	macho_holder.held_item = ItemRegistry.get_item(418)  # Macho Brace
	var fainted2 := _make_mon("Fainted2", 10, [0, 0, 0, 1, 0, 0])
	bm._grant_evs(macho_holder, fainted2.species)
	_chk("Macho Brace alone: x2 applied, but NOT additionally +8 (1*2=2, not 10)",
			macho_holder.evs[BattlePokemon.STAT_SPATK] == 2)


# ── Section F: max-level-still-gains-EVs ───────────────────────────────────

func _test_max_level_still_gains_evs() -> void:
	var bm := _make_bm()
	var recipient := _make_mon("Recipient", 100)
	var fainted := _make_mon("Fainted", 100, [0, 0, 0, 0, 0, 3])  # yields 3 SPEED
	fainted.current_hp = 1

	bm._exp_participants = [[0]]
	bm._parties = [BattleParty.single(recipient), BattleParty.single(fainted)]
	bm._combatants = [recipient, fainted]
	bm._active_per_side = 1

	bm._award_exp_for_fainted_opponent(fainted)
	_chk("max-level recipient: still gains the full EV yield even though it can never level up further",
			recipient.evs[BattlePokemon.STAT_SPEED] == 3)
	_chk("max-level recipient: level correctly stays at 100 (no level-up possible)",
			recipient.level == 100)


# ── Section G: EVs don't retroactively change stats ────────────────────────

func _test_evs_do_not_retroactively_change_stats() -> void:
	var bm := _make_bm()
	# Level 50 + a 20-EV yield in every stat (well under both caps, so the
	# grant lands at exactly 20 with no clamping) guarantees the resulting
	# floor(ev/4) shift is large enough to move `_stat_formula`'s own
	# integer-floored result -- a smaller level/yield combination can
	# floor away to an identical value, which would make this
	# discriminator vacuous rather than a real proof.
	var recipient := _make_mon("Recipient", 50)
	var stats_before := [recipient.attack, recipient.defense, recipient.sp_attack,
			recipient.sp_defense, recipient.speed, recipient.max_hp]

	var fainted := _make_mon("Fainted", 50, [20, 20, 20, 20, 20, 20])
	bm._grant_evs(recipient, fainted.species)

	_chk("EVs recorded (evs[] changed)",
			recipient.evs == [20, 20, 20, 20, 20, 20])
	_chk("granting EVs alone does NOT retroactively recompute current battle stats -- source only recomputes at level-up/switch-in, never on a bare EV change",
			recipient.attack == stats_before[0] and recipient.defense == stats_before[1]
			and recipient.sp_attack == stats_before[2] and recipient.sp_defense == stats_before[3]
			and recipient.speed == stats_before[4] and recipient.max_hp == stats_before[5])

	# Discriminator: once a stat recalculation DOES fire for the same
	# recipient (the exact same `_calculate_stats()` call `_check_level_up`
	# itself uses on a real level-up), the already-granted EVs are
	# correctly reflected (proving they were real, not silently dropped --
	# just not applied until the next recalc). Called directly here rather
	# than through `_check_level_up`/growth-curve derivation, since this
	# fixture's synthetic species has no real dex/growth-rate data to
	# level up against -- that whole mechanism is `[M20b]`'s own concern,
	# already tested there; this test isolates the EV-visibility claim only.
	recipient._calculate_stats()
	_chk("once stats recompute, the earlier-granted EVs are now reflected (attack changed from before)",
			recipient.attack != stats_before[0])


# ── Section H: Klutz suppression (Klutz is already implemented; the item
# bonus should be suppressed the same way every other item effect is) ──────

func _test_klutz_suppresses_item_bonus() -> void:
	var bm := _make_bm()
	var recipient := _make_mon("Recipient", 10)
	recipient.held_item = ItemRegistry.get_item(422)  # Power Lens
	recipient.ability = load("res://data/abilities/ability_0103.tres") as AbilityData  # Klutz
	var fainted := _make_mon("Fainted", 10, [0, 0, 0, 1, 0, 0])
	bm._grant_evs(recipient, fainted.species)
	_chk("Klutz suppresses the Power Item bonus: only the base yield (1) is granted, not 1+8",
			recipient.evs[BattlePokemon.STAT_SPATK] == 1)


# ── Negative control ────────────────────────────────────────────────────────

func _test_player_side_faint_negative_control() -> void:
	var bm := _make_bm()
	var a := _make_mon("A", 10)
	var opponent := _make_mon("Opponent", 10, [1, 1, 1, 1, 1, 1])

	bm._exp_participants = [[0]]
	bm._parties = [BattleParty.single(a), BattleParty.single(opponent)]
	bm._active_per_side = 1
	bm._combatants = [a, opponent]

	a.current_hp = 0  # A (player side) is the one that fainted, not the opponent
	bm._award_exp_for_fainted_opponent(a)
	_chk("negative control: a player-side faint awards no EVs to anyone",
			a.evs == [0, 0, 0, 0, 0, 0] and opponent.evs == [0, 0, 0, 0, 0, 0])
