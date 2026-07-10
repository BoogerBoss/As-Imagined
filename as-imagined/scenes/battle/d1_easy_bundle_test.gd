extends Node

# [D1 easy bundle] Six small, mechanically-contained clusters (13 moves):
# EFFECT_HIT_ESCAPE (U-turn/Volt Switch/Flip Turn), EFFECT_HIT_SWITCH_TARGET
# (Circle Throw/Dragon Tail), EFFECT_FIRST_TURN_ONLY (Fake Out/First
# Impression), EFFECT_TRICK (Trick/Switcheroo), EFFECT_REVENGE (Revenge/
# Avalanche), EFFECT_STOMPING_TANTRUM (Stomping Tantrum/Temper Flare).
#
# Also includes a real bug fix found at Step 0: Retaliate's own side-timer
# decrement was moved from `_phase_end_of_turn` (which this project's own
# architecture skips on a faint/replacement turn) to `_phase_priority_
# resolution` (which source's real decrement site — shared with Stomping
# Tantrum's own timer — runs unconditionally every turn). Section H
# re-verifies Retaliate's corrected timing.
#
# Ground truth: reference/pokeemerald_expansion/src/battle_move_resolution.c
# (MoveEndHitEscape L3905-3920, EFFECT_HIT_SWITCH_TARGET L3517-3545,
# EFFECT_FIRST_TURN_ONLY L1222-1224), src/battle_script_commands.c
# (Cmd_tryswapitems L8874-8930), src/battle_util.c (CanBattlerGetOrLoseItem
# L8686-8708, EFFECT_REVENGE L6172-6174, EFFECT_STOMPING_TANTRUM
# L6416-6418), src/battle_main.c (shared per-battler action-reset,
# retaliateTimer/stompingTantrumTimer decrement L3933-3940), GEN_LATEST.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_data_integrity()
	_test_hit_escape()
	_test_hit_switch_target()
	_test_first_turn_only()
	_test_trick()
	_test_revenge()
	_test_stomping_tantrum()
	_test_retaliate_corrected_timing()

	var total := _pass + _fail
	print("d1_easy_bundle_test: %d/%d passed" % [_pass, total])
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


func _make_mon(mon_name: String, base_hp: int = 100, base_atk: int = 60,
		base_def: int = 60, base_spatk: int = 60, base_spdef: int = 60,
		base_spd: int = 60, mon_type: int = TypeChart.TYPE_NORMAL) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types = [mon_type]
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


func _make_item(item_name: String, hold_effect: int) -> ItemData:
	var item := ItemData.new()
	item.item_name = item_name
	item.hold_effect = hold_effect
	return item


# ── Section A: data integrity (13 moves) ────────────────────────────────────

func _test_data_integrity() -> void:
	var u_turn := _load_move(369)
	_chk("A.01 U-turn power=70/acc=100/pp=20/PHYS/Bug",
			u_turn.power == 70 and u_turn.accuracy == 100 and u_turn.pp == 20
			and u_turn.category == 0 and u_turn.type == TypeChart.TYPE_BUG)
	_chk("A.02 U-turn is_hit_escape/makes_contact",
			u_turn.is_hit_escape == true and u_turn.makes_contact == true)

	var volt_switch := _load_move(521)
	_chk("A.03 Volt Switch power=70/acc=100/pp=20/SPEC/Electric",
			volt_switch.power == 70 and volt_switch.category == 1
			and volt_switch.type == TypeChart.TYPE_ELECTRIC)
	_chk("A.04 Volt Switch is_hit_escape/NOT makes_contact",
			volt_switch.is_hit_escape == true and volt_switch.makes_contact == false)

	var flip_turn := _load_move(740)
	_chk("A.05 Flip Turn power=60/acc=100/pp=20/PHYS/Water",
			flip_turn.power == 60 and flip_turn.category == 0
			and flip_turn.type == TypeChart.TYPE_WATER)
	_chk("A.06 Flip Turn is_hit_escape", flip_turn.is_hit_escape == true)

	var circle_throw := _load_move(509)
	_chk("A.07 Circle Throw power=60/acc=90/pp=10/priority=-6/Fighting",
			circle_throw.power == 60 and circle_throw.accuracy == 90 and circle_throw.pp == 10
			and circle_throw.priority == -6 and circle_throw.type == TypeChart.TYPE_FIGHTING)
	_chk("A.08 Circle Throw is_hit_switch_target", circle_throw.is_hit_switch_target == true)

	var dragon_tail := _load_move(525)
	_chk("A.09 Dragon Tail power=60/acc=90/pp=10/priority=-6/Dragon",
			dragon_tail.power == 60 and dragon_tail.priority == -6
			and dragon_tail.type == TypeChart.TYPE_DRAGON)
	_chk("A.10 Dragon Tail is_hit_switch_target", dragon_tail.is_hit_switch_target == true)

	var fake_out := _load_move(252)
	_chk("A.11 Fake Out power=40/acc=100/pp=10/priority=3/Normal",
			fake_out.power == 40 and fake_out.priority == 3 and fake_out.type == TypeChart.TYPE_NORMAL)
	_chk("A.12 Fake Out is_first_turn_only/guaranteed SE_FLINCH",
			fake_out.is_first_turn_only == true and fake_out.secondary_effect == MoveData.SE_FLINCH
			and fake_out.secondary_chance == 100)

	var first_impression := _load_move(623)
	_chk("A.13 First Impression power=90/acc=100/pp=10/priority=2/Bug",
			first_impression.power == 90 and first_impression.priority == 2
			and first_impression.type == TypeChart.TYPE_BUG)
	_chk("A.14 First Impression is_first_turn_only", first_impression.is_first_turn_only == true)

	var trick := _load_move(271)
	_chk("A.15 Trick acc=100/pp=10/STAT/Psychic",
			trick.accuracy == 100 and trick.pp == 10 and trick.category == 2
			and trick.type == TypeChart.TYPE_PSYCHIC)
	_chk("A.16 Trick is_trick", trick.is_trick == true)

	var switcheroo := _load_move(415)
	_chk("A.17 Switcheroo acc=100/pp=10/STAT/Dark",
			switcheroo.accuracy == 100 and switcheroo.category == 2
			and switcheroo.type == TypeChart.TYPE_DARK)
	_chk("A.18 Switcheroo is_trick", switcheroo.is_trick == true)

	var revenge := _load_move(279)
	_chk("A.19 Revenge power=60/acc=100/pp=10/priority=-4/Fighting",
			revenge.power == 60 and revenge.priority == -4 and revenge.type == TypeChart.TYPE_FIGHTING)
	_chk("A.20 Revenge is_revenge/makes_contact",
			revenge.is_revenge == true and revenge.makes_contact == true)

	var avalanche := _load_move(419)
	_chk("A.21 Avalanche power=60/acc=100/pp=10/priority=-4/Ice",
			avalanche.power == 60 and avalanche.priority == -4 and avalanche.type == TypeChart.TYPE_ICE)
	_chk("A.22 Avalanche is_revenge", avalanche.is_revenge == true)

	var stomping_tantrum := _load_move(661)
	_chk("A.23 Stomping Tantrum power=75/acc=100/pp=10/Ground",
			stomping_tantrum.power == 75 and stomping_tantrum.type == TypeChart.TYPE_GROUND)
	_chk("A.24 Stomping Tantrum is_stomping_tantrum", stomping_tantrum.is_stomping_tantrum == true)

	var temper_flare := _load_move(843)
	_chk("A.25 Temper Flare power=75/acc=100/pp=10/Fire",
			temper_flare.power == 75 and temper_flare.type == TypeChart.TYPE_FIRE)
	_chk("A.26 Temper Flare is_stomping_tantrum", temper_flare.is_stomping_tantrum == true)


# ── Section B: Hit Escape (U-turn/Volt Switch/Flip Turn) ─────────────────────

func _test_hit_escape() -> void:
	var u_turn := _load_move(369)
	var tackle := _load_move(33)

	# B.01-B.02: a connecting hit triggers a switch to the deterministic
	# first-available bench mon (player-choice-style selection, not random).
	var atk := _make_mon("HEAtk", 300, 80, 60, 60, 60, 100)
	var bench := _make_mon("HEBench", 300, 60, 60, 60, 60, 90)
	var opp := _make_mon("HEOpp", 400, 60, 60, 60, 60, 50)
	atk.add_move(u_turn)
	opp.add_move(tackle)
	var player_party := BattleParty.new()
	player_party.members = [atk, bench]
	player_party.active_index = 0

	var switched_events := []
	var bm := _make_bm()
	bm._force_hit = true
	bm.hit_escape_switch.connect(func(old_mon, new_mon): switched_events.push_back([old_mon, new_mon]))
	bm.start_battle_with_parties(player_party, BattleParty.single(opp))

	_chk("B.01 U-turn triggers a switch after a connecting hit",
			switched_events.size() >= 1 and switched_events[0][0] == atk)
	_chk("B.02 the switch brings in the bench mon (deterministic, player-choice-style)",
			switched_events.size() >= 1 and switched_events[0][1] == bench)
	bm.queue_free()

	# B.03: a fainting attacker (recoil/contact-punish death) does NOT switch.
	# Uses a Rocky Helmet holder as the "contact punish" source — U-turn
	# makes contact, and a low-HP attacker dies to the retaliation damage
	# before the switch would fire. Checked via a bounded, live-captured
	# snapshot (does hit_escape_switch ever fire for THIS specific atk),
	# not a post-battle read.
	var atk2 := _make_mon("HEAtk2", 300, 80, 60, 60, 60, 100)
	var bench2 := _make_mon("HEBench2", 300, 60, 60, 60, 60, 90)
	var opp2 := _make_mon("HEOpp2", 400, 60, 60, 60, 60, 50)
	atk2.add_move(u_turn)
	opp2.add_move(tackle)
	atk2.current_hp = 1  # dies to Rocky Helmet's own contact-punish recoil
	opp2.held_item = _make_item("Rocky Helmet", ItemManager.HOLD_EFFECT_ROCKY_HELMET)
	var player_party2 := BattleParty.new()
	player_party2.members = [atk2, bench2]
	player_party2.active_index = 0
	var switched2 := [false]
	var bm2 := _make_bm()
	bm2._force_hit = true
	bm2.hit_escape_switch.connect(func(old_mon, _n): if old_mon == atk2: switched2[0] = true)
	bm2.start_battle_with_parties(player_party2, BattleParty.single(opp2))
	_chk("B.03 a U-turn user that dies to contact-punish retaliation does NOT switch",
			switched2[0] == false)
	bm2.queue_free()


# ── Section C: Hit Switch Target (Circle Throw/Dragon Tail) ─────────────────

func _test_hit_switch_target() -> void:
	var circle_throw := _load_move(509)
	var tackle := _load_move(33)

	# C.01-C.02: forces the defender out via RANDOM replacement (matching
	# Roar/Whirlwind), fires only on real HP damage.
	var atk := _make_mon("HSTAtk", 300, 80, 60, 60, 60, 100)
	var def1 := _make_mon("HSTDef1", 300, 60, 60, 60, 60, 90)
	var def2 := _make_mon("HSTDef2", 300, 60, 60, 60, 60, 80)
	atk.add_move(circle_throw)
	def1.add_move(tackle)
	def2.add_move(tackle)
	var opp_party := BattleParty.new()
	opp_party.members = [def1, def2]
	opp_party.active_index = 0

	var switched_events := []
	var bm := _make_bm()
	bm._force_hit = true
	bm._force_roar_rng = 0  # deterministic random pick -> slot 1 (def2)
	bm.hit_switch_target.connect(func(old_mon, new_mon): switched_events.push_back([old_mon, new_mon]))
	bm.start_battle_with_parties(BattleParty.single(atk), opp_party)

	_chk("C.01 Circle Throw forces the defender out after a real hit",
			switched_events.size() >= 1 and switched_events[0][0] == def1)
	_chk("C.02 the forced switch uses the RANDOM-replacement helper (deterministic via _force_roar_rng)",
			switched_events.size() >= 1 and switched_events[0][1] == def2)
	bm.queue_free()

	# C.03: fails (no-op, damage still stands) with no valid replacement —
	# single-mon party on the defending side.
	var atk2 := _make_mon("HSTAtk2", 300, 80, 60, 60, 60, 100)
	var def_solo := _make_mon("HSTDefSolo", 300, 60, 60, 60, 60, 50)
	atk2.add_move(circle_throw)
	def_solo.add_move(tackle)
	var switched3 := [false]
	var dealt3 := [0]
	var bm2 := _make_bm()
	bm2._force_hit = true
	bm2.hit_switch_target.connect(func(_o, _n): switched3[0] = true)
	bm2.move_executed.connect(func(a, _d, _m, amt): if a == atk2 and dealt3[0] == 0: dealt3[0] = amt)
	bm2.start_battle(atk2, def_solo)
	_chk("C.03 no forced switch with no valid replacement (last mon standing)", switched3[0] == false)
	_chk("C.04 discriminator: damage still lands normally despite no switch", dealt3[0] > 0)
	bm2.queue_free()


# ── Section D: First Turn Only (Fake Out/First Impression) ──────────────────

func _test_first_turn_only() -> void:
	var fake_out := _load_move(252)
	var tackle := _load_move(33)
	var instruct := _load_move(652)

	# D.01: connects on the user's genuine first turn since switching in.
	var atk := _make_mon("FTAtk", 300, 80, 60, 60, 60, 100)
	var def := _make_mon("FTDef", 300, 60, 60, 60, 60, 50)
	atk.add_move(fake_out)
	def.add_move(tackle)
	var dealt := [0]
	var bm := _make_bm()
	bm._force_hit = true
	bm.move_executed.connect(func(a, _d, _m, amt): if a == atk and dealt[0] == 0: dealt[0] = amt)
	bm.start_battle(atk, def)
	_chk("D.01 Fake Out connects on the user's first turn since switch-in", dealt[0] > 0)
	bm.queue_free()

	# D.02: fails on turn 2+ — atk2's second use (its only move, auto-
	# repeated) must fail. Captured via a bounded event-count check (the
	# 2nd move_executed for atk2 must show 0 damage), not a post-battle read.
	var atk2 := _make_mon("FTAtk2", 300, 80, 60, 60, 60, 100)
	var def2 := _make_mon("FTDef2", 400, 60, 60, 60, 60, 50)
	atk2.add_move(fake_out)
	def2.add_move(tackle)
	var atk2_events := []
	var bm2 := _make_bm()
	bm2._force_hit = true
	bm2.move_executed.connect(func(a, _d, _m, amt): if a == atk2: atk2_events.push_back(amt))
	bm2.start_battle(atk2, def2)
	_chk("D.02 Fake Out fails on the user's second turn (0 damage the second time)",
			atk2_events.size() >= 2 and atk2_events[0] > 0 and atk2_events[1] == 0)
	bm2.queue_free()

	# D.03: Instruct cannot force a second same-turn Fake Out (the
	# Instruct-exclusion-list fix). tgt is faster, uses Fake Out for real
	# (turn 1, first use — connects); atk (slower) uses Instruct the SAME
	# turn, attempting to force tgt to re-use Fake Out — must fail.
	var tgt := _make_mon("FTTgt", 300, 80, 60, 60, 60, 100)
	var atk3 := _make_mon("FTAtk3", 300, 60, 60, 60, 60, 50)
	tgt.add_move(fake_out)
	atk3.add_move(instruct)
	var instruct_failed := [false]
	var bm3 := _make_bm()
	bm3._force_hit = true
	bm3.move_effect_failed.connect(func(_a, reason): if reason == "instruct_failed": instruct_failed[0] = true)
	bm3.start_battle(atk3, tgt)
	_chk("D.03 Instruct cannot force a same-turn re-use of Fake Out", instruct_failed[0] == true)
	bm3.queue_free()


# ── Section E: Trick (Trick/Switcheroo) ──────────────────────────────────────

func _test_trick() -> void:
	var trick := _load_move(271)
	var tackle := _load_move(33)

	# E.01-E.02: bidirectional item swap.
	var atk := _make_mon("TrAtk", 300, 60, 60, 60, 60, 100)
	var def := _make_mon("TrDef", 300, 60, 60, 60, 60, 50)
	atk.add_move(trick)
	def.add_move(tackle)
	var atk_item := _make_item("Leftovers", ItemManager.HOLD_EFFECT_LEFTOVERS)
	var def_item := _make_item("Choice Band", ItemManager.HOLD_EFFECT_CHOICE_BAND)
	atk.held_item = atk_item
	def.held_item = def_item
	var swapped := [false]
	var bm := _make_bm()
	bm._force_hit = true
	bm.items_swapped.connect(func(_a, _d): swapped[0] = true)
	bm.start_battle(atk, def)
	_chk("E.01 Trick swaps items (signal fired)", swapped[0] == true)
	# Snapshot inside the handler, not post-battle — the battle continues
	# and Cheek-Pouch/consumable-adjacent effects could otherwise mutate
	# held_item further after the swap.
	bm.queue_free()

	var atk2 := _make_mon("TrAtk2", 300, 60, 60, 60, 60, 100)
	var def2 := _make_mon("TrDef2", 300, 60, 60, 60, 60, 50)
	atk2.add_move(trick)
	def2.add_move(tackle)
	var atk2_item := _make_item("Leftovers", ItemManager.HOLD_EFFECT_LEFTOVERS)
	var def2_item := _make_item("Choice Band", ItemManager.HOLD_EFFECT_CHOICE_BAND)
	atk2.held_item = atk2_item
	def2.held_item = def2_item
	var items_at_swap := []
	var bm1b := _make_bm()
	bm1b._force_hit = true
	bm1b.items_swapped.connect(func(a, d):
		if items_at_swap.is_empty():
			items_at_swap.append([a.held_item, d.held_item]))
	bm1b.start_battle(atk2, def2)
	_chk("E.02 after swapping, attacker holds the former defender item and vice versa",
			items_at_swap.size() >= 1 and items_at_swap[0][0] == def2_item
			and items_at_swap[0][1] == atk2_item)
	bm1b.queue_free()

	# E.03: fails if both itemless.
	var atk3 := _make_mon("TrAtk3", 300, 60, 60, 60, 60, 100)
	var def3 := _make_mon("TrDef3", 300, 60, 60, 60, 60, 50)
	atk3.add_move(trick)
	def3.add_move(tackle)
	var failed := [false]
	var bm2 := _make_bm()
	bm2._force_hit = true
	bm2.move_effect_failed.connect(func(_a, reason): if reason == "trick_failed": failed[0] = true)
	bm2.start_battle(atk3, def3)
	_chk("E.03 Trick fails when both Pokémon are itemless", failed[0] == true)
	bm2.queue_free()

	# E.04: Sticky Hold on the TARGET blocks the swap.
	var atk4 := _make_mon("TrAtk4", 300, 60, 60, 60, 60, 100)
	var def4 := _make_mon("TrDef4", 300, 60, 60, 60, 60, 50)
	atk4.add_move(trick)
	def4.add_move(tackle)
	atk4.held_item = _make_item("Leftovers", ItemManager.HOLD_EFFECT_LEFTOVERS)
	def4.held_item = _make_item("Choice Band", ItemManager.HOLD_EFFECT_CHOICE_BAND)
	var sticky_ability := AbilityData.new()
	sticky_ability.ability_id = AbilityManager.ABILITY_STICKY_HOLD
	def4.ability = sticky_ability
	var blocked := [false]
	var swapped4 := [false]
	var bm3 := _make_bm()
	bm3._force_hit = true
	bm3.move_effect_failed.connect(func(_a, reason): if reason == "sticky_hold_prevents": blocked[0] = true)
	bm3.items_swapped.connect(func(_a, _d): swapped4[0] = true)
	bm3.start_battle(atk4, def4)
	_chk("E.05 Sticky Hold on the target blocks the swap", blocked[0] == true)
	_chk("E.06 discriminator: no swap actually happened", swapped4[0] == false)
	bm3.queue_free()

	# E.07-E.08: [Multitype-Plate fix] a Multitype holder currently holding its own
	# Plate is blocked from losing it via Trick.
	var atk5 := _make_mon("TrAtk5", 300, 60, 60, 60, 60, 100)
	var def5 := _make_mon("TrDef5", 300, 60, 60, 60, 60, 50)
	atk5.add_move(trick)
	def5.add_move(tackle)
	var multitype_ability5 := AbilityData.new()
	multitype_ability5.ability_id = AbilityManager.ABILITY_MULTITYPE
	atk5.ability = multitype_ability5
	atk5.held_item = _make_item("Iron Plate", ItemManager.HOLD_EFFECT_PLATE)
	def5.held_item = _make_item("Choice Band", ItemManager.HOLD_EFFECT_CHOICE_BAND)
	var failed5 := [false]
	var swapped5 := [false]
	var bm4 := _make_bm()
	bm4._force_hit = true
	bm4.move_effect_failed.connect(func(_a, reason): if reason == "trick_failed": failed5[0] = true)
	bm4.items_swapped.connect(func(_a, _d): swapped5[0] = true)
	bm4.start_battle(atk5, def5)
	_chk("E.07 Trick fails when the attacker is a Multitype holder losing its own Plate",
			failed5[0] == true)
	_chk("E.08 discriminator: no swap actually happened", swapped5[0] == false)
	bm4.queue_free()

	# E.09-E.10: [Multitype-Plate fix] the deeper, previously-missed case — a Multitype
	# holder with NO Plate currently held (itemless, so the ordinary "both itemless"
	# check alone doesn't apply) is still blocked from GAINING a foreign Plate via
	# Trick. Re-derived directly from source's own 4 CanBattlerGetOrLoseItem calls
	# (Cmd_tryswapitems, battle_script_commands.c L8906-8909) — the original 2-check
	# implementation only checked each side's OWN currently-held item and would have
	# incorrectly allowed this swap.
	var atk6 := _make_mon("TrAtk6", 300, 60, 60, 60, 60, 100)
	var def6 := _make_mon("TrDef6", 300, 60, 60, 60, 60, 50)
	atk6.add_move(trick)
	def6.add_move(tackle)
	var multitype_ability6 := AbilityData.new()
	multitype_ability6.ability_id = AbilityManager.ABILITY_MULTITYPE
	atk6.ability = multitype_ability6
	# atk6 itself holds nothing (not a Plate) — only def6 holds a Plate.
	def6.held_item = _make_item("Splash Plate", ItemManager.HOLD_EFFECT_PLATE)
	var failed6 := [false]
	var swapped6 := [false]
	var bm5 := _make_bm()
	bm5._force_hit = true
	bm5.move_effect_failed.connect(func(_a, reason): if reason == "trick_failed": failed6[0] = true)
	bm5.items_swapped.connect(func(_a, _d): swapped6[0] = true)
	bm5.start_battle(atk6, def6)
	_chk("E.09 Trick fails when the itemless attacker (Multitype) would GAIN a " +
			"foreign Plate — the case the original 2-check version missed",
			failed6[0] == true)
	_chk("E.10 discriminator: no swap actually happened, target keeps its Plate",
			swapped6[0] == false and def6.held_item != null)


# ── Section F: Revenge (Revenge/Avalanche) ───────────────────────────────────

func _test_revenge() -> void:
	var revenge := _load_move(279)
	var tackle := _load_move(33)

	# F.01-F.02: doubled only if hit BY THIS TARGET this turn — tgt is
	# faster and Tackles atk first; atk's own Revenge (priority -4, moves
	# last regardless) then connects doubled. Baseline: tgt uses a status
	# move instead (Growl) — no damage taken, undoubled.
	var scary_face := _load_move(184)  # a harmless status move for the baseline (no damage dealt)
	var atk_a := _make_mon("RvAtkA", 300, 80, 60, 60, 60, 50)
	var opp_a := _make_mon("RvOppA", 300, 60, 60, 60, 60, 100)
	atk_a.add_move(revenge)
	opp_a.add_move(tackle)
	var dealt_a := [0]
	var bm_a := _make_bm()
	bm_a._force_hit = true
	bm_a._force_roll = 100
	bm_a._force_crit = false
	bm_a.move_executed.connect(func(a, _d, _m, amt): if a == atk_a and dealt_a[0] == 0: dealt_a[0] = amt)
	bm_a.start_battle(atk_a, opp_a)
	bm_a.queue_free()

	var atk_b := _make_mon("RvAtkB", 300, 80, 60, 60, 60, 50)
	var opp_b := _make_mon("RvOppB", 300, 60, 60, 60, 60, 100)
	atk_b.add_move(revenge)
	opp_b.add_move(scary_face)
	var dealt_b := [0]
	var bm_b := _make_bm()
	bm_b._force_hit = true
	bm_b._force_roll = 100
	bm_b._force_crit = false
	bm_b.move_executed.connect(func(a, _d, _m, amt): if a == atk_b and dealt_b[0] == 0: dealt_b[0] = amt)
	bm_b.start_battle(atk_b, opp_b)
	bm_b.queue_free()

	_chk("F.01 Revenge is doubled when hit by this target earlier this turn",
			dealt_a[0] >= dealt_b[0] * 2 - 4 and dealt_a[0] <= dealt_b[0] * 2 + 4)
	_chk("F.02 discriminator: baseline (not hit) is the plain undoubled hit", dealt_b[0] > 0)

	# F.03: scope discriminator — a genuine 2v2 doubles scenario. atk_c is
	# hit by O1 (fastest, acts first) but its own Revenge explicitly
	# targets O0 (via queue_move_targeted, not left to default-targeting
	# ambiguity) — must NOT double, since the per-(victim,attacker)-pair
	# tracker only records O1 against atk_c, not O0.
	var atk_c := _make_mon("RvAtkC", 400, 80, 60, 60, 60, 20)
	var ally_c := _make_mon("RvAllyC", 300, 60, 60, 60, 60, 15)
	var opp_c0 := _make_mon("RvOppC0", 300, 60, 60, 60, 60, 40)
	var opp_c1 := _make_mon("RvOppC1", 300, 60, 60, 60, 60, 100)
	atk_c.add_move(revenge)
	ally_c.add_move(tackle)
	opp_c0.add_move(tackle)
	opp_c1.add_move(tackle)
	var dealt_c := [0]
	var bm_c := _make_bm()
	bm_c._force_hit = true
	bm_c._force_roll = 100
	bm_c._force_crit = false
	bm_c.move_executed.connect(func(a, _d, _m, amt): if a == atk_c and dealt_c[0] == 0: dealt_c[0] = amt)
	var pp_c := BattleParty.new(); pp_c.members = [atk_c, ally_c]; pp_c.active_indices = [0, 1]
	var op_c := BattleParty.new(); op_c.members = [opp_c0, opp_c1]; op_c.active_indices = [0, 1]
	bm_c.queue_move_targeted(0, 0, 2)  # atk_c(combatant 0) uses Revenge(idx 0) targeting O0(combatant 2)
	bm_c.queue_move_targeted(2, 0, 1)  # O0(combatant 2) Tackles ally_c(combatant 1), NOT atk_c
	bm_c.queue_move_targeted(3, 0, 0)  # O1(combatant 3, fastest) Tackles atk_c(combatant 0) explicitly
	bm_c.start_battle_doubles(pp_c, op_c)
	_chk("F.03 being hit by a DIFFERENT opponent (O1) this turn does not double Revenge targeted at O0",
			dealt_c[0] > 0 and _approx_scaled_not(dealt_c[0], dealt_b[0], 2))


func _approx_scaled_not(actual: int, baseline: int, factor: int, tolerance: int = 4) -> bool:
	return absi(actual - baseline * factor) > tolerance


# ── Section G: Stomping Tantrum (Stomping Tantrum/Temper Flare) ─────────────

func _test_stomping_tantrum() -> void:
	var stomping_tantrum := _load_move(661)
	var tackle := _load_move(33)

	# G.01: the generic failure-detector actually fires from a real,
	# fully-deterministic failure (a flat type immunity — Tackle vs. a
	# Ghost-type target — needs no RNG forcing at all, unlike a miss) and
	# is consumed by the very next turn's own action. atk's move[0] is
	# Tackle (queued turn 1, immune, fails), move[1] is Stomping Tantrum
	# (queued turn 2).
	var atk_a := _make_mon("STAtkA", 300, 80, 60, 60, 60, 100)
	var opp_a := _make_mon("STOppA", 400, 60, 60, 60, 60, 50, TypeChart.TYPE_GHOST)
	atk_a.add_move(tackle)
	atk_a.add_move(stomping_tantrum)
	opp_a.add_move(tackle)
	var dmg_seq := []
	var bm_a := _make_bm()
	bm_a._force_hit = true
	bm_a._force_roll = 100
	bm_a._force_crit = false
	bm_a.queue_move(0, 0)  # turn 1: Tackle (immune vs Ghost, deterministic failure)
	bm_a.queue_move(0, 1)  # turn 2: Stomping Tantrum
	bm_a.move_executed.connect(func(a, _d, _m, amt):
		if a == atk_a and amt > 0:
			dmg_seq.push_back(amt))
	bm_a.start_battle(atk_a, opp_a)
	_chk("G.01 Stomping Tantrum fires with real damage the turn after a genuine failure (type immunity)",
			dmg_seq.size() >= 1 and dmg_seq[0] > 0)
	bm_a.queue_free()

	# G.02: direct-state comparison — effective timer==1 doubles vs timer==0
	# baseline. Pre-set to 2 (not 1): `_phase_priority_resolution`'s own
	# per-turn decrement runs unconditionally before the battle's very
	# first action, including turn 1 of a fresh battle, so a pre-set value
	# is already decremented once before the first check ever happens —
	# see this session's own Retaliate timing-bug correction for the full
	# writeup (`docs/decisions.md`'s `[D1 easy bundle]` entry).
	var atk_b := _make_mon("STAtkB", 300, 80, 60, 60, 60, 100)
	var opp_b := _make_mon("STOppB", 300, 60, 60, 60, 60, 50)
	atk_b.add_move(stomping_tantrum)
	opp_b.add_move(tackle)
	atk_b.stomping_tantrum_timer = 2
	var dealt_b := [0]
	var bm_b := _make_bm()
	bm_b._force_hit = true
	bm_b._force_roll = 100
	bm_b._force_crit = false
	bm_b.move_executed.connect(func(a, _d, _m, amt): if a == atk_b and dealt_b[0] == 0: dealt_b[0] = amt)
	bm_b.start_battle(atk_b, opp_b)
	bm_b.queue_free()

	var atk_c := _make_mon("STAtkC", 300, 80, 60, 60, 60, 100)
	var opp_c := _make_mon("STOppC", 300, 60, 60, 60, 60, 50)
	atk_c.add_move(stomping_tantrum)
	opp_c.add_move(tackle)
	var dealt_c := [0]
	var bm_c := _make_bm()
	bm_c._force_hit = true
	bm_c._force_roll = 100
	bm_c._force_crit = false
	bm_c.move_executed.connect(func(a, _d, _m, amt): if a == atk_c and dealt_c[0] == 0: dealt_c[0] = amt)
	bm_c.start_battle(atk_c, opp_c)
	bm_c.queue_free()
	_chk("G.03 Stomping Tantrum is doubled at timer==1 vs. timer==0 baseline",
			dealt_b[0] >= dealt_c[0] * 2 - 4 and dealt_b[0] <= dealt_c[0] * 2 + 4)

	# G.04: effective timer==2 (one tick short of qualifying) does NOT
	# double — pre-set to 3, decrementing to 2 before the first check.
	var atk_d := _make_mon("STAtkD", 300, 80, 60, 60, 60, 100)
	var opp_d := _make_mon("STOppD", 300, 60, 60, 60, 60, 50)
	atk_d.add_move(stomping_tantrum)
	opp_d.add_move(tackle)
	atk_d.stomping_tantrum_timer = 3
	var dealt_d := [0]
	var bm_d := _make_bm()
	bm_d._force_hit = true
	bm_d._force_roll = 100
	bm_d._force_crit = false
	bm_d.move_executed.connect(func(a, _d2, _m, amt): if a == atk_d and dealt_d[0] == 0: dealt_d[0] = amt)
	bm_d.start_battle(atk_d, opp_d)
	bm_d.queue_free()
	_chk("G.04 discriminator: effective timer==2 is NOT doubled either",
			dealt_d[0] == dealt_c[0])


# ── Section H: Retaliate corrected timing (bug fix re-verification) ────────

func _test_retaliate_corrected_timing() -> void:
	var retaliate := _load_move(514)
	var tackle := _load_move(33)

	# H.01-H.02: with the corrected decrement site, the timer now reaches 1
	# (doubled) on the replacement's very FIRST turn back — not its
	# second, as the pre-fix D3 test observed. mon1 (fragile) dies to opp
	# turn 1; faint-replacement sends in mon2 (Retaliate-only) for turn 2.
	var mon1 := _make_mon("RTMon1", 20, 60, 20, 60, 20, 40)
	var mon2 := _make_mon("RTMon2", 400, 80, 200, 60, 200, 90)
	var opp := _make_mon("RTOpp", 400, 80, 60, 60, 60, 200)
	mon1.add_move(tackle)
	mon2.add_move(retaliate)
	opp.add_move(tackle)

	var timer_snapshots := []
	var faint_events := []
	var bm := _make_bm()
	bm._force_hit = true
	bm._force_roll = 100
	bm._force_crit = false
	bm.pokemon_fainted.connect(func(p): faint_events.push_back(p))
	bm.move_executed.connect(func(a, _d, _m, amt):
		if a == mon2:
			timer_snapshots.push_back(amt))

	var pp := BattleParty.new(); pp.members = [mon1, mon2]; pp.active_index = 0
	bm.start_battle_with_parties(pp, BattleParty.single(opp))

	_chk("H.01 mon1 fainted (integration setup)", faint_events.any(func(p): return p == mon1))
	_chk("H.02 mon2's turn-2 Retaliate (its FIRST turn back) is now doubled with the corrected timing",
			timer_snapshots.size() >= 2 and _approx_scaled(timer_snapshots[0], timer_snapshots[1], 2))
	bm.queue_free()


func _approx_scaled(actual: int, baseline: int, factor: int, tolerance: int = 4) -> bool:
	return absi(actual - baseline * factor) <= tolerance
