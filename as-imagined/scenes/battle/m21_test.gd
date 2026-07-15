extends Node

# [M21] Doubles interaction cleanup — bundle-safe group: items 1, 2, 3, 4,
# 5, 7, 8, 9, 10 from the M21 recon inventory (item 6, Guard Dog + Flower
# Veil ally tie-break, explicitly EXCLUDED this session per Rob's own
# decision — low value/niche, recorded in docs/decisions.md, not an
# oversight). The turn-order-splice trio (Round/Shell Trap/Quash) remains
# deferred to its own dedicated future session.
#
# Full Step-0 source citations for every item live in docs/decisions.md's
# own [M21] entry — not repeated here in full.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_item7_choose_replacement_doubles_slot_exclusion()
	_test_item7_best_switch_target_doubles_slot_exclusion()
	_test_item7_negative_control_singles_unaffected()

	_test_item3_red_card_double_trigger_guard()
	_test_item3_negative_control_single_holder()

	_test_item1_shell_bell_skipped_when_red_card_switches_attacker()
	_test_item1_life_orb_recoil_skipped_when_red_card_switches_attacker()
	_test_item1_negative_control_shell_bell_heals_normally()

	_test_item4_self_destruct_hits_ally_in_doubles()
	_test_item4_negative_control_singles_no_ally()

	# [M21] Item 8 (Trick Room x Pursuit doubles) was found during this
	# session's own Step 0 to be genuinely non-deterministic in doubles (a
	# real bug — Godot's `sort_custom` combined with the comparator's
	# non-transitive Pursuit-intercept override — not just an untested-but-
	# correct gap). No passing test is shipped this session, since any
	# "passing" result would misrepresent reliability that doesn't exist.
	# Folded into the deferred turn-order-splice session per Rob's own
	# decision — see docs/decisions.md's [M21] entry for the full citation,
	# repro, and the corrected (broader-than-first-assessed) diagnosis.

	_test_item9_snatch_beats_magic_bounce_in_doubles()

	_test_item2_shell_bell_heals_once_from_accumulated_total()
	_test_item2_life_orb_recoils_once_not_per_target()
	_test_item2_one_target_immune_still_accumulates_correctly()
	_test_item2_one_target_already_fainted_still_accumulates_correctly()
	_test_item2_ally_hit_damage_included_in_accumulated_total()
	_test_item2_negative_control_single_target_unchanged()

	var total := _pass + _fail
	print("m21_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


func _make_mon(mon_name: String, mon_type: int, move_type: int = -1,
		power: int = 60) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types = [mon_type]
	sp.base_hp = 100
	sp.base_attack = 60
	sp.base_defense = 60
	sp.base_sp_attack = 60
	sp.base_sp_defense = 60
	sp.base_speed = 60
	var mon := BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])
	if move_type >= 0:
		var mv := MoveData.new()
		mv.move_name = mon_name + "Move"
		mv.type = move_type
		mv.category = 0  # Physical
		mv.power = power
		mv.pp = 15
		mon.add_move(mv)
	return mon


func _doubles_party(m0: BattlePokemon, m1: BattlePokemon,
		bench: Array = []) -> BattleParty:
	var p := BattleParty.new()
	var all_members: Array[BattlePokemon] = [m0, m1]
	for b: BattlePokemon in bench:
		all_members.append(b)
	p.members = all_members
	p.active_indices.append(1)  # starts as [0], becomes [0, 1]
	return p


func _load_move(id: int) -> MoveData:
	return load("res://data/moves/move_%04d.tres" % id) as MoveData


func _load_item(id: int) -> ItemData:
	return ItemRegistry.get_item(id)


func _make_spread(move_name: String, power: int) -> MoveData:
	var m := MoveData.new()
	m.move_name = move_name
	m.power = power
	m.type = TypeChart.TYPE_NORMAL
	m.category = 0
	m.accuracy = 100
	m.is_spread = true
	return m


# ── Item 7: TrainerAI active_index bug ─────────────────────────────────────
#
# Bug: choose_replacement/_best_switch_target checked `i == my_party
# .active_index` (only active_indices[0]) instead of excluding ALL active
# slots. In a doubles battle with both slots alive, the AI could recommend
# "switching in" a mon that's already active in the OTHER slot.
# get_first_non_fainted_not_active (the final fallback) was already fixed
# to check ALL active_indices; these two AI-driven paths, checked FIRST
# before that fallback, were not (docs/decisions.md's [M21] entry has the
# full trace of both reachable call paths: choose_action_doubles's
# proactive-switch check, and _get_replacement_slot's faint-replacement).

func _test_item7_choose_replacement_doubles_slot_exclusion() -> void:
	var ai := TrainerAI.new()
	var opponent := _make_mon("Opponent", TypeChart.TYPE_GRASS)

	# Slot 0: about to be replaced (irrelevant to the type-effectiveness
	# scan itself, but present as a real party member).
	var m0 := _make_mon("Slot0", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NORMAL)
	# Slot 1: ALREADY ACTIVE, holds a Fire move (2x super effective vs
	# Grass) -- objectively the "best" type matchup in the party.
	var m1 := _make_mon("Slot1Active", TypeChart.TYPE_FIRE, TypeChart.TYPE_FIRE)
	# Bench: a weaker (neutral) matchup, but the ONLY legitimate candidate
	# since m1 is already on the field.
	var bench := _make_mon("Bench", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NORMAL)

	var party := _doubles_party(m0, m1, [bench])
	var chosen: int = ai.choose_replacement(party, opponent)

	_chk("item 7 (choose_replacement): does NOT recommend slot 1 (m1), which is already active in the other doubles slot",
			chosen != 1)
	_chk("item 7 (choose_replacement): correctly picks the bench mon (index 2) instead, despite its worse type matchup",
			chosen == 2)


func _test_item7_best_switch_target_doubles_slot_exclusion() -> void:
	var ai := TrainerAI.new()
	ai.tier = TrainerAI.Tier.SMART
	var opponent := _make_mon("Opponent", TypeChart.TYPE_GRASS)

	var m0 := _make_mon("Slot0", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NORMAL)
	var m1 := _make_mon("Slot1Active", TypeChart.TYPE_FIRE, TypeChart.TYPE_FIRE)
	var bench := _make_mon("Bench", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NORMAL)
	var party := _doubles_party(m0, m1, [bench])

	var chosen: int = ai._best_switch_target(party, opponent)
	_chk("item 7 (_best_switch_target): does NOT recommend slot 1 (m1), which is already active",
			chosen != 1)
	_chk("item 7 (_best_switch_target): correctly picks the bench mon (index 2) instead",
			chosen == 2)


func _test_item7_negative_control_singles_unaffected() -> void:
	# Plain singles scenario (BattleParty.single-style, one active slot,
	# one bench mon) -- confirms the fix doesn't disturb ordinary singles
	# replacement/switch-target selection, which was already correct.
	var ai := TrainerAI.new()
	var opponent := _make_mon("Opponent", TypeChart.TYPE_GRASS)
	var active := _make_mon("Active", TypeChart.TYPE_NORMAL, TypeChart.TYPE_NORMAL)
	var bench := _make_mon("Bench", TypeChart.TYPE_FIRE, TypeChart.TYPE_FIRE)

	var party := BattleParty.new()
	var members: Array[BattlePokemon] = [active, bench]
	party.members = members

	var chosen: int = ai.choose_replacement(party, opponent)
	_chk("item 7 negative control: ordinary singles replacement still picks the bench mon (index 1) normally",
			chosen == 1)


# ── Item 3: Red Card double-trigger guard ──────────────────────────────────
#
# Source (battle_move_resolution.c): TryRedCard (L3732-3755) sets
# gBattleStruct->redCardActivated = TRUE (L3741) the moment a valid
# replacement slot is found (CanBattlerSwitch succeeds), BEFORE the Guard
# Dog check even runs -- and MoveEndCardButton (L3777-3805) re-checks that
# flag (L3736) on every subsequent battler it scans this same move,
# preventing a SECOND Red Card holder from also forcing the same attacker
# to switch. The flag resets to FALSE (L3801) once the scan finishes --
# i.e. scoped to one move's own resolution, not one turn.

func _test_item3_red_card_double_trigger_guard() -> void:
	var spread := _make_spread("Spread", 40)
	var tackle := _load_move(33)

	# A1 deliberately gets a STATUS move (power=0), not Tackle -- Red Card's
	# own gate requires the target to have taken DAMAGE this action
	# (IsBattlerTurnDamaged). Giving A1 a damaging move would let it
	# independently trigger a SECOND, legitimate (not buggy) Red Card
	# consumption on its own separate action later this same turn,
	# contaminating this test's specific "did A0's ONE spread move
	# double-trigger" measurement -- a fresh instance of this project's
	# own documented whole-battle-aggregation testing pitfall, caught here
	# before trusting a false-looking failure.
	var status_move := MoveData.new()
	status_move.move_name = "Growl"
	status_move.power = 0
	status_move.category = 2
	status_move.accuracy = 100

	var a0 := _make_mon("A0", TypeChart.TYPE_NORMAL, -1)
	a0.add_move(spread)
	var a1 := _make_mon("A1", TypeChart.TYPE_NORMAL, -1)
	a1.add_move(status_move)
	var a0_bench := _make_mon("A0Bench", TypeChart.TYPE_NORMAL, -1)
	a0_bench.add_move(tackle)

	var b0 := _make_mon("B0", TypeChart.TYPE_NORMAL, -1)
	b0.held_item = _load_item(498)
	b0.add_move(tackle)
	var b1 := _make_mon("B1", TypeChart.TYPE_NORMAL, -1)
	b1.held_item = _load_item(498)
	b1.add_move(tackle)
	# Give both opponents generous HP so the spread hit never faints them --
	# Red Card requires the TARGET to have survived the hit
	# (IsBattlerTurnDamaged), not just been hit.
	for mon in [b0, b1]:
		mon.max_hp = 250
		mon.current_hp = 250

	# Snapshot both holders' item state at the EXACT instant A0's own
	# forced-switch fires (the direct result of A0's ONE spread move) --
	# not after the whole (possibly multi-turn) battle completes. A0's
	# replacement (A0Bench) could legitimately consume the surviving
	# holder's OWN Red Card on a LATER, separate turn/action, which would
	# make a post-battle read of held_item wrongly show BOTH consumed --
	# a fresh instance of the documented whole-battle-aggregation pitfall,
	# avoided here via first-occurrence signal-snapshotting instead.
	var switches: Array = []
	var snapshot: Array = [null]  # Array-wrapped for lambda-capture-by-reference
	var bm := BattleManager.new()
	add_child(bm)
	bm.forced_switch.connect(func(o, n):
		switches.append([o, n])
		if o == a0 and snapshot[0] == null:
			snapshot[0] = [b0.held_item == null, b1.held_item == null]
	)
	bm.start_battle_doubles(_doubles_party(a0, a1, [a0_bench]), _doubles_party(b0, b1))

	_chk("item 3: A0 (the original attacker) was forced to switch EXACTLY ONCE, not twice, despite both B0 and B1 holding Red Card",
			switches.filter(func(e): return e[0] == a0).size() == 1)
	_chk("item 3: at the exact moment of A0's own forced switch, exactly ONE of the two Red Card holders had consumed its item (the other's second trigger this same move was correctly blocked)",
			snapshot[0] != null and snapshot[0][0] != snapshot[0][1])
	bm.queue_free()


func _test_item3_negative_control_single_holder() -> void:
	# A single Red Card holder (singles battle) still triggers normally --
	# confirms the new guard doesn't accidentally block the ordinary,
	# already-shipped single-holder case.
	var tackle := _load_move(33)
	var atk := _make_mon("Atk", TypeChart.TYPE_NORMAL, -1)
	atk.add_move(tackle)
	var atk_bench := _make_mon("AtkBench", TypeChart.TYPE_NORMAL, -1)
	var holder := _make_mon("Holder", TypeChart.TYPE_NORMAL, -1)
	holder.held_item = _load_item(498)
	holder.add_move(tackle)
	holder.max_hp = 250
	holder.current_hp = 250

	var switches: Array = []
	var bm := BattleManager.new()
	add_child(bm)
	bm.forced_switch.connect(func(o, n): switches.append([o, n]))
	var atk_party := BattleParty.new()
	var members: Array[BattlePokemon] = [atk, atk_bench]
	atk_party.members = members
	bm.start_battle_with_parties(atk_party, BattleParty.single(holder))

	_chk("item 3 negative control: a single Red Card holder still forces the attacker to switch normally",
			switches.any(func(e): return e[0] == atk))
	_chk("item 3 negative control: the single holder's item is consumed",
			holder.held_item == null)
	bm.queue_free()


# ── Item 1: Shell Bell / Life Orb + Red Card interaction ───────────────────
#
# Source (battle_hold_effects.c): TryShellBell (L526-545) and TryLifeOrb
# (L547-559) BOTH check `!gBattleStruct->battlerState[battlerAtk]
# .redCardSwitched` -- confirmed via direct citation this applies to BOTH
# items identically, not just Shell Bell as originally flagged. This flag
# (set at battle_script_commands.c L7421, only when the attacker ACTUALLY
# switches out -- not the Guard-Dog-blocked "activated but no switch"
# case) is narrower than `redCardActivated` (item 3's own guard). Source's
# real MoveEnd dispatch table processes MOVEEND_CARD_BUTTON BEFORE
# MOVEEND_LIFE_ORB_SHELL_BELL (battle_move_resolution.c L4389/L4391), so an
# attacker flung out of the field by Red Card never gets its own Shell Bell
# heal or Life Orb recoil from the very hit that got it switched out.

func _test_item1_shell_bell_skipped_when_red_card_switches_attacker() -> void:
	var tackle := _load_move(33)
	var atk := _make_mon("Atk", TypeChart.TYPE_NORMAL, -1)
	atk.add_move(tackle)
	atk.held_item = _load_item(473)  # Shell Bell
	atk.max_hp = 200
	atk.current_hp = 100  # damaged beforehand, so a heal would be visible if it fired
	var atk_bench := _make_mon("AtkBench", TypeChart.TYPE_NORMAL, -1)

	var holder := _make_mon("Holder", TypeChart.TYPE_NORMAL, -1)
	holder.held_item = _load_item(498)  # Red Card
	holder.add_move(tackle)
	holder.max_hp = 250
	holder.current_hp = 250

	# ATK could later cycle back into the active slot via faint-replacement
	# (e.g. if AtkBench eventually faints) and legitimately earn a real,
	# UNRELATED Shell Bell heal many turns later -- a fresh instance of the
	# documented whole-battle-aggregation pitfall. A first draft of this
	# test tracked only "switch"/"healed" events and assumed adjacency in
	# that timeline meant temporal adjacency -- but `pokemon_switched_in`
	# (ATK legitimately returning via faint-replacement) isn't a
	# `forced_switch` event, so it was invisible to that timeline, making a
	# LATER legitimate heal look falsely adjacent to the original Red-Card
	# switch-out. Fixed by also tracking every return-to-field for ATK, and
	# only inspecting the window strictly BETWEEN the switch-out and ATK's
	# own next return (if any) -- zero heal-for-ATK events must appear in
	# that specific window; anything after ATK is back on the field again
	# is legitimate, separate activity.
	var timeline: Array = []
	var bm := BattleManager.new()
	add_child(bm)
	bm.item_healed.connect(func(p, amt): timeline.append(["healed", p, amt]))
	bm.forced_switch.connect(func(o, n): timeline.append(["switch_out", o, n]))
	bm.pokemon_switched_in.connect(func(p, _side, _slot): timeline.append(["switch_in", p]))
	var atk_party := BattleParty.new()
	var members: Array[BattlePokemon] = [atk, atk_bench]
	atk_party.members = members
	bm.start_battle_with_parties(atk_party, BattleParty.single(holder))

	var switch_out_idx: int = -1
	for i in range(timeline.size()):
		if timeline[i][0] == "switch_out" and timeline[i][1] == atk:
			switch_out_idx = i
			break
	_chk("item 1: Red Card still forces ATK to switch (sanity check the scenario is real)",
			switch_out_idx >= 0)
	var return_idx: int = timeline.size()
	if switch_out_idx >= 0:
		for i in range(switch_out_idx + 1, timeline.size()):
			if timeline[i][0] == "switch_in" and timeline[i][1] == atk:
				return_idx = i
				break
	var bad_heal: bool = false
	if switch_out_idx >= 0:
		for i in range(switch_out_idx + 1, return_idx):
			if timeline[i][0] == "healed" and timeline[i][1] == atk:
				bad_heal = true
				break
	_chk("item 1: ATK's own Shell Bell did NOT heal it on the hit that got it Red-Card-switched out (checked up until ATK's own next legitimate return to the field, if any)",
			not bad_heal)
	bm.queue_free()


func _test_item1_life_orb_recoil_skipped_when_red_card_switches_attacker() -> void:
	var tackle := _load_move(33)
	var atk := _make_mon("Atk", TypeChart.TYPE_NORMAL, -1)
	atk.add_move(tackle)
	atk.held_item = _load_item(479)  # Life Orb
	atk.max_hp = 200
	atk.current_hp = 200
	var atk_bench := _make_mon("AtkBench", TypeChart.TYPE_NORMAL, -1)

	var holder := _make_mon("Holder", TypeChart.TYPE_NORMAL, -1)
	holder.held_item = _load_item(498)  # Red Card
	holder.add_move(tackle)
	holder.max_hp = 250
	holder.current_hp = 250

	# Same whole-battle-aggregation risk and same window-bounded fix as the
	# Shell Bell test above -- ATK's own Life Orb could otherwise fire
	# legitimately again on a later, unrelated turn after cycling back in
	# via faint-replacement (a `pokemon_switched_in` event, not a
	# `forced_switch` one -- tracked explicitly so the check's window ends
	# the instant ATK legitimately returns to the field).
	var timeline: Array = []
	var bm := BattleManager.new()
	add_child(bm)
	bm.item_damage.connect(func(p, amt): timeline.append(["damage", p, amt]))
	bm.forced_switch.connect(func(o, n): timeline.append(["switch_out", o, n]))
	bm.pokemon_switched_in.connect(func(p, _side, _slot): timeline.append(["switch_in", p]))
	var atk_party := BattleParty.new()
	var members: Array[BattlePokemon] = [atk, atk_bench]
	atk_party.members = members
	bm.start_battle_with_parties(atk_party, BattleParty.single(holder))

	var switch_out_idx: int = -1
	for i in range(timeline.size()):
		if timeline[i][0] == "switch_out" and timeline[i][1] == atk:
			switch_out_idx = i
			break
	_chk("item 1: Red Card still forces ATK to switch (Life Orb scenario)",
			switch_out_idx >= 0)
	var return_idx: int = timeline.size()
	if switch_out_idx >= 0:
		for i in range(switch_out_idx + 1, timeline.size()):
			if timeline[i][0] == "switch_in" and timeline[i][1] == atk:
				return_idx = i
				break
	var bad_recoil: bool = false
	if switch_out_idx >= 0:
		for i in range(switch_out_idx + 1, return_idx):
			if timeline[i][0] == "damage" and timeline[i][1] == atk:
				bad_recoil = true
				break
	_chk("item 1: ATK's own Life Orb recoil did NOT fire on the hit that got it Red-Card-switched out (checked up until ATK's own next legitimate return to the field, if any)",
			not bad_recoil)
	bm.queue_free()


func _test_item1_negative_control_shell_bell_heals_normally() -> void:
	# Same Shell Bell setup, but the target does NOT hold Red Card --
	# confirms the relocation didn't break Shell Bell's own ordinary,
	# already-shipped heal behavior.
	var tackle := _load_move(33)
	var atk := _make_mon("Atk", TypeChart.TYPE_NORMAL, -1)
	atk.add_move(tackle)
	atk.held_item = _load_item(473)  # Shell Bell
	atk.max_hp = 200
	atk.current_hp = 100

	var plain := _make_mon("Plain", TypeChart.TYPE_NORMAL, -1)
	plain.add_move(tackle)
	plain.max_hp = 250
	plain.current_hp = 250

	var healed_events: Array = []
	var bm := BattleManager.new()
	add_child(bm)
	bm.item_healed.connect(func(p, amt): healed_events.append([p, amt]))
	bm.start_battle_with_parties(BattleParty.single(atk), BattleParty.single(plain))

	_chk("item 1 negative control: without Red Card involved, Shell Bell still heals ATK normally",
			healed_events.any(func(e): return e[0] == atk and e[1] > 0))
	bm.queue_free()


# ── Item 4: Self-Destruct/Explosion ally-hit ───────────────────────────────
#
# Source (moves_info.h): both Self-Destruct(120)/Explosion(153) carry
# `.target = TARGET_FOES_AND_ALLY`. Confirmed via battle_move_resolution.c
# L920-933 (CancelerSetTargets) this hits EVERY other battler in doubles --
# both opponents AND the user's own ally. Confirmed via battle_util.c
# L5993-5996 (GetMoveTargetCount) the ally counts as a THIRD target, and
# L7220-7230 (GetTargetDamageModifier) the SAME flat 0.75x reduction
# applies whether 2 or 3 targets are actually hit at this project's
# GEN_LATEST config (B_MULTIPLE_TARGETS_DMG>=GEN_4) -- no separate value
# needed. A0 can only ever land ONE hit with this move (is_self_faint means
# it faints immediately after), so filtering to attacker==a0 is safe from
# the whole-battle-aggregation pitfall by construction -- there is no
# possible SECOND, later A0-attributed hit for this move to aggregate with.

func _test_item4_self_destruct_hits_ally_in_doubles() -> void:
	var tackle := _load_move(33)
	var self_destruct := _load_move(120)

	var a0 := _make_mon("A0", TypeChart.TYPE_NORMAL, -1)
	a0.add_move(self_destruct)
	a0.max_hp = 300
	a0.current_hp = 300
	var a1 := _make_mon("A1", TypeChart.TYPE_NORMAL, -1)
	a1.add_move(tackle)
	a1.max_hp = 300
	a1.current_hp = 300

	var b0 := _make_mon("B0", TypeChart.TYPE_NORMAL, -1)
	b0.add_move(tackle)
	b0.max_hp = 300
	b0.current_hp = 300
	var b1 := _make_mon("B1", TypeChart.TYPE_NORMAL, -1)
	b1.add_move(tackle)
	b1.max_hp = 300
	b1.current_hp = 300

	var a0_hits: Dictionary = {}  # defender -> damage, first occurrence only
	var bm := BattleManager.new()
	add_child(bm)
	bm.move_executed.connect(func(attacker, defender, mv, dmg):
		if attacker == a0 and mv == self_destruct and not a0_hits.has(defender):
			a0_hits[defender] = dmg
	)
	bm.start_battle_doubles(_doubles_party(a0, a1), _doubles_party(b0, b1))

	_chk("item 4: Self-Destruct hit BOTH opponents (B0 and B1)",
			a0_hits.has(b0) and a0_hits.has(b1) and a0_hits[b0] > 0 and a0_hits[b1] > 0)
	_chk("item 4: Self-Destruct ALSO hit A0's own ally (A1) -- the ally-hit half this item builds",
			a0_hits.has(a1) and a0_hits[a1] > 0)
	_chk("item 4: A0 itself still faints (is_self_faint, already-shipped behavior unaffected)",
			a0.fainted)
	bm.queue_free()


func _test_item4_negative_control_singles_no_ally() -> void:
	# In singles (_active_per_side == 1), there is no ally slot at all --
	# confirms the new ally-hit code path doesn't crash or misbehave when
	# there's nobody to hit.
	var self_destruct := _load_move(120)
	var tackle := _load_move(33)
	var a0 := _make_mon("A0", TypeChart.TYPE_NORMAL, -1)
	a0.add_move(self_destruct)
	var b0 := _make_mon("B0", TypeChart.TYPE_NORMAL, -1)
	b0.add_move(tackle)
	b0.max_hp = 300
	b0.current_hp = 300

	var hit_b0: Array = [false]
	var bm := BattleManager.new()
	add_child(bm)
	bm.move_executed.connect(func(attacker, defender, mv, dmg):
		if attacker == a0 and mv == self_destruct and defender == b0 and dmg > 0:
			hit_b0[0] = true
	)
	bm.start_battle_with_parties(BattleParty.single(a0), BattleParty.single(b0))

	_chk("item 4 negative control: singles Self-Destruct still hits the sole opponent normally, no crash",
			hit_b0[0])
	bm.queue_free()


# ── Item 8: Trick Room x Pursuit doubles — NO TEST SHIPPED, see below ──────
#
# `m16_review_test.gd`'s own Area 3 explicitly scoped "Doubles x Trick Room
# x Pursuit" OUT — singles-only, flagged in docs/decisions.md's [M16 Review]
# entry as untested rather than unbuilt (mechanism "believed correct by
# construction"). This session's own Step 0 found that belief was WRONG:
# Godot's `sort_custom` is an unstable algorithm with no transitivity
# guarantee, and the comparator's Pursuit-intercept override
# (`_phase_priority_resolution`'s sort_custom, checked against
# `_pursuit_targets_switcher`) is only valid for the SPECIFIC pair being
# compared — it does not hold up transitively once a third/fourth
# combatant is present. A first attempt at a regression test (using a
# same-side speed tie between the Pursuit user and its own ally) failed;
# removing that tie was assumed to be the fix, but a direct isolation
# rerun (3x with only this test enabled) proved the failure is genuinely
# NON-DETERMINISTIC even with fully distinct speeds and no ties anywhere —
# passed, failed, passed again across identical reruns. This is a real,
# deeper bug than "avoid ties," not something this session's own bundle-
# safe scope can respons­ibly fix or reliably test. Per Rob's own decision,
# folded into the deferred turn-order-splice session (alongside Round/
# Shell Trap/Quash) rather than shipping a test that would sometimes pass
# and sometimes fail for reasons unrelated to the code under test — see
# docs/decisions.md's [M21] entry for the full citation, repro, and the
# corrected diagnosis.


# ── Item 9: Snatch vs Magic Coat/Bounce doubles ordering test ──────────────
#
# Source-confirmed ordering (docs/decisions.md's own M19 Snatch entry):
# Snatch's own steal check (`battle_manager.gd`'s `move.snatch_affected`
# block) runs, and reassigns BOTH attacker and defender to the thief,
# BEFORE the shared Magic Bounce/Magic Coat swap check reached later in the
# same function -- so a Snatch user always gets first claim.
#
# REAL FINDING from this session's own Step 0 (re-verified, not assumed):
# this exact race is STRUCTURALLY UNREACHABLE with any real move currently
# in this project's roster. `snatch_affected` moves are, per this project's
# own established finding, exclusively self/field-targeting (buffs, heals,
# screens) -- and `bounceable` moves are, by Magic Bounce's own definition,
# exclusively FOE-targeting (a move that affects an opponent, reflected
# back at its own caster). No move can be both at once; confirmed via a
# direct programmatic scan of all 717 `gen_moves.py` entries -- ZERO carry
# both flags simultaneously. This test therefore uses a SYNTHETIC MoveData
# (both flags forced on) purely to exercise the two code paths' real
# relative ORDER, matching this project's own established precedent for
# ability/flag combinations no real move yet exercises (e.g. `[M17n-5]`'s
# synthetic Strong Jaw/Sharpness/Mega Launcher tests). Not a claim that
# this scenario can occur in real play with this project's current move
# roster -- purely a code-path-ordering proof, doubles-shaped per the
# recon's own request.

func _test_item9_snatch_beats_magic_bounce_in_doubles() -> void:
	var snatch := _load_move(289)
	var tackle := _load_move(33)
	var magic_bounce: AbilityData = load("res://data/abilities/ability_0156.tres") as AbilityData

	# Synthetic status move: BOTH snatch_affected AND bounceable, a
	# combination no real move in this roster carries (see header comment).
	var synth := MoveData.new()
	synth.move_name = "SynthSnatchable"
	synth.category = 2  # Status
	synth.accuracy = 100
	synth.pp = 10
	synth.snatch_affected = true
	synth.bounceable = true

	var a0 := _make_mon("A0", TypeChart.TYPE_NORMAL, -1)
	a0.add_move(snatch)
	a0.speed = 100  # acts first, arms snatch_active before B0's own action
	var a1 := _make_mon("A1", TypeChart.TYPE_NORMAL, -1)
	a1.add_move(tackle)
	a1.speed = 50

	var b0 := _make_mon("B0", TypeChart.TYPE_NORMAL, -1)
	b0.add_move(synth)
	b0.speed = 40
	var b1 := _make_mon("B1MagicBounce", TypeChart.TYPE_NORMAL, -1)
	b1.add_move(tackle)
	b1.ability = magic_bounce
	b1.speed = 30

	var stolen_events: Array = []
	var bounced_events: Array = []
	var bm := BattleManager.new()
	add_child(bm)
	bm.move_stolen.connect(func(stealer, caster, mv): stolen_events.append([stealer, caster, mv]))
	bm.move_bounced.connect(func(holder, new_target): bounced_events.append([holder, new_target]))
	bm.queue_move_targeted(0, 0, 2)  # A0 (idx 0) uses Snatch (self/field move; target index required but semantically unused)
	bm.queue_move_targeted(2, 0, 3)  # B0 (idx 2) uses the synthetic move at B1 (idx 3, Magic Bounce holder)
	bm.start_battle_doubles(_doubles_party(a0, a1), _doubles_party(b0, b1))

	_chk("item 9: Snatch (A0) successfully stole B0's synthetic move",
			stolen_events.any(func(e): return e[0] == a0 and e[1] == b0 and e[2] == synth))
	_chk("item 9: Magic Bounce (B1) never got a chance to bounce it -- Snatch's own reassignment happened first, so B1 (the original intended target) is never reached by the Magic Bounce check at all",
			not bounced_events.any(func(e): return e[0] == b1))
	bm.queue_free()


# ── Item 2: Shell Bell / Life Orb spread-move damage accumulation ─────────
#
# Source: `gBattleScripting.savedDmg` accumulates across ALL targets of a
# spread move before Shell Bell/Life Orb's own MoveEnd effect ever runs
# (battle_move_resolution.c L4389-4391, the same once-per-move MoveEnd
# timing already established for multi-hit moves). This project's own
# per-target `_do_damaging_hit` dispatch previously healed/recoiled once
# PER TARGET instead of once per whole move -- fixed by accumulating
# `spread_total_damage`/`spread_hits_landed` across the spread loop
# (including the ally, for TARGET_FOES_AND_ALLY moves) and applying ONE
# combined heal/recoil after it, mirroring `_do_multi_hit_sequence`'s own
# already-correct precedent for Shell Bell (and now, also fixed here,
# for Life Orb -- a genuinely separate bug found this session: Life Orb's
# recoil is FLAT maxHP/10, not damage-proportional, so its own bug was
# REPEATING the flat deduction per target rather than under-counting via
# floor-division truncation like Shell Bell's).

func _make_mon_stats(mon_name: String, mon_type: int,
		base_atk: int = 60, base_def: int = 60) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types = [mon_type]
	sp.base_hp = 100
	sp.base_attack = base_atk
	sp.base_defense = base_def
	sp.base_sp_attack = 60
	sp.base_sp_defense = 60
	sp.base_speed = 60
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])


func _make_spread_dmg(power: int) -> MoveData:
	var m := MoveData.new()
	m.move_name = "SynthSpread"
	m.type = TypeChart.TYPE_NORMAL
	m.category = 0
	m.power = power
	m.accuracy = 100
	m.is_spread = true
	return m


# Direct single-dispatch helper for a 4-combatant doubles scenario — resolves
# exactly ONE `_phase_move_execution()` call for A0 (idx 0) using `move`,
# bypassing the full multi-turn battle loop entirely. This sidesteps the
# whole-battle-aggregation pitfall by construction (no later turns exist to
# produce additional, legitimate events to confuse a "did this happen once"
# assertion) — matching this project's own established direct-dispatch
# convention (see e.g. ban_flag_audit_test.gd's `_dispatch_move`,
# d4_bundle9_test.gd's C.10/C.11). Connects move_executed/item_healed/
# item_damage BEFORE dispatch, filling the caller-provided Dictionary/Array
# (passed by reference) so the caller can inspect results afterward.
func _dispatch_doubles_spread_with_signals(a0: BattlePokemon, a1: BattlePokemon,
		b0: BattlePokemon, b1: BattlePokemon, move: MoveData,
		per_target_dmg: Dictionary, healed_events: Array, damage_events: Array) -> BattleManager:
	var bm := BattleManager.new()
	add_child(bm)
	bm._force_roll = 100
	bm._force_crit = false
	bm.move_executed.connect(func(atk, d, mv, dmg):
		if atk == a0 and mv == move and not per_target_dmg.has(d):
			per_target_dmg[d] = dmg
	)
	bm.item_healed.connect(func(p, amt): healed_events.append([p, amt]))
	bm.item_damage.connect(func(p, amt): damage_events.append([p, amt]))
	var combatants: Array[BattlePokemon] = [a0, a1, b0, b1]
	bm._combatants = combatants
	bm._active_per_side = 2
	var actor_indices := {}
	for i in range(4):
		actor_indices[combatants[i]] = i
	bm._actor_indices = actor_indices
	bm._chosen_moves = [move, null, null, null]
	bm._chosen_switch_slots = [-1, -1, -1, -1]
	bm._chosen_targets = [2, 3, 0, 0]
	bm._turn_order = combatants.duplicate()
	bm._current_actor_index = 0
	bm._phase_move_execution()
	return bm


func _test_item2_shell_bell_heals_once_from_accumulated_total() -> void:
	var spread := _make_spread_dmg(40)
	var a0 := _make_mon("A0", TypeChart.TYPE_NORMAL, -1)
	a0.add_move(spread)
	a0.held_item = _load_item(473)  # Shell Bell
	a0.max_hp = 300
	a0.current_hp = 100  # below max, so a heal is visible if it fires
	var a1 := _make_mon("A1", TypeChart.TYPE_NORMAL, -1)

	var b0 := _make_mon_stats("B0", TypeChart.TYPE_NORMAL, 60, 60)
	b0.max_hp = 300
	b0.current_hp = 300
	var b1 := _make_mon_stats("B1", TypeChart.TYPE_NORMAL, 60, 70)
	b1.max_hp = 300
	b1.current_hp = 300

	var per_target_dmg: Dictionary = {}
	var healed_events: Array = []
	var bm := _dispatch_doubles_spread_with_signals(a0, a1, b0, b1, spread, per_target_dmg, healed_events, [])

	var dmg0: int = per_target_dmg.get(b0, 0)
	var dmg1: int = per_target_dmg.get(b1, 0)
	_chk("item 2 setup sanity: both targets took real, nonzero damage",
			dmg0 > 0 and dmg1 > 0)
	var sum_then_floor: int = (dmg0 + dmg1) / 8
	var floor_then_sum: int = (dmg0 / 8) + (dmg1 / 8)
	_chk("item 2 setup sanity: chosen damage values make sum-then-floor and floor-then-sum genuinely differ (a real discriminator, not a coincidence)",
			sum_then_floor != floor_then_sum)
	_chk("item 2: Shell Bell fired EXACTLY ONCE for A0 from this one spread-move use hitting both targets (not once per target)",
			healed_events.size() == 1 and healed_events[0][0] == a0)
	_chk("item 2: that single heal equals floor(SUM of both hits / 8), not the sum of two independently-floored per-hit heals",
			healed_events.size() == 1 and healed_events[0][1] == sum_then_floor)
	bm.queue_free()


func _test_item2_life_orb_recoils_once_not_per_target() -> void:
	var spread := _make_spread_dmg(40)
	var a0 := _make_mon("A0", TypeChart.TYPE_NORMAL, -1)
	a0.add_move(spread)
	a0.held_item = _load_item(479)  # Life Orb
	a0.max_hp = 300
	a0.current_hp = 300
	var a1 := _make_mon("A1", TypeChart.TYPE_NORMAL, -1)

	var b0 := _make_mon("B0", TypeChart.TYPE_NORMAL, -1)
	b0.max_hp = 300
	b0.current_hp = 300
	var b1 := _make_mon("B1", TypeChart.TYPE_NORMAL, -1)
	b1.max_hp = 300
	b1.current_hp = 300

	var per_target_dmg: Dictionary = {}
	var damage_events: Array = []
	var bm := _dispatch_doubles_spread_with_signals(a0, a1, b0, b1, spread, per_target_dmg, [], damage_events)

	var lo_events_for_a0: Array = damage_events.filter(func(e): return e[0] == a0)
	_chk("item 2: Life Orb recoils A0 EXACTLY ONCE for this one spread-move use (not once per target hit)",
			lo_events_for_a0.size() == 1 and lo_events_for_a0[0][1] == max(1, a0.max_hp / 10))
	bm.queue_free()


func _test_item2_one_target_immune_still_accumulates_correctly() -> void:
	# B0 is Ghost-type (immune to a Normal-type spread move -- 0 damage,
	# still counts toward live_target_count per source, but contributes
	# nothing to the accumulated total). B1 is Normal-type (takes real
	# damage). Shell Bell should still heal off B1's own damage alone.
	var spread := _make_spread_dmg(40)
	var a0 := _make_mon("A0", TypeChart.TYPE_NORMAL, -1)
	a0.add_move(spread)
	a0.held_item = _load_item(473)  # Shell Bell
	a0.max_hp = 300
	a0.current_hp = 100
	var a1 := _make_mon("A1", TypeChart.TYPE_NORMAL, -1)

	var b0 := _make_mon("B0Ghost", TypeChart.TYPE_GHOST, -1)
	b0.max_hp = 300
	b0.current_hp = 300
	var b1 := _make_mon("B1", TypeChart.TYPE_NORMAL, -1)
	b1.max_hp = 300
	b1.current_hp = 300

	var per_target_dmg: Dictionary = {}
	var healed_events: Array = []
	var bm := _dispatch_doubles_spread_with_signals(a0, a1, b0, b1, spread, per_target_dmg, healed_events, [])

	_chk("item 2 (immune target): B0 (Ghost) took 0 damage from the Normal-type spread move",
			per_target_dmg.get(b0, -1) == 0)
	_chk("item 2 (immune target): B1 took real damage",
			per_target_dmg.get(b1, 0) > 0)
	_chk("item 2 (immune target): Shell Bell still fires exactly once for A0, correctly off B1's damage alone (the immune hit contributes nothing but doesn't break accumulation)",
			healed_events.size() == 1 and healed_events[0][0] == a0
					and healed_events[0][1] == per_target_dmg.get(b1, 0) / 8)
	bm.queue_free()


func _test_item2_one_target_already_fainted_still_accumulates_correctly() -> void:
	# B0 starts already fainted (excluded from the spread hit entirely,
	# per the existing `tgt.fainted` skip) -- confirms accumulation across
	# the remaining live target (B1) still works normally with one target
	# missing from the field.
	var spread := _make_spread_dmg(40)
	var a0 := _make_mon("A0", TypeChart.TYPE_NORMAL, -1)
	a0.add_move(spread)
	a0.held_item = _load_item(473)  # Shell Bell
	a0.max_hp = 300
	a0.current_hp = 100
	var a1 := _make_mon("A1", TypeChart.TYPE_NORMAL, -1)

	var b0 := _make_mon("B0Fainted", TypeChart.TYPE_NORMAL, -1)
	b0.current_hp = 0
	b0.fainted = true
	var b1 := _make_mon("B1", TypeChart.TYPE_NORMAL, -1)
	b1.max_hp = 300
	b1.current_hp = 300

	var per_target_dmg: Dictionary = {}
	var healed_events: Array = []
	var bm := _dispatch_doubles_spread_with_signals(a0, a1, b0, b1, spread, per_target_dmg, healed_events, [])

	_chk("item 2 (fainted target): B0 (already fainted) was never hit at all",
			not per_target_dmg.has(b0))
	_chk("item 2 (fainted target): Shell Bell still fires exactly once for A0, off B1's damage alone",
			healed_events.size() == 1 and healed_events[0][0] == a0
					and healed_events[0][1] == per_target_dmg.get(b1, 0) / 8)
	bm.queue_free()


func _test_item2_ally_hit_damage_included_in_accumulated_total() -> void:
	# Self-Destruct(120) hits both opponents AND the user's own ally
	# (item 4's own TARGET_FOES_AND_ALLY fix) -- confirms the ally's own
	# damage is correctly folded into the SAME accumulated total this
	# item's fix computes, not handled via some separate, disconnected path.
	var self_destruct := _load_move(120)
	var a0 := _make_mon("A0", TypeChart.TYPE_NORMAL, -1)
	a0.add_move(self_destruct)
	a0.held_item = _load_item(473)  # Shell Bell
	a0.max_hp = 300
	a0.current_hp = 100
	var a1 := _make_mon_stats("A1", TypeChart.TYPE_NORMAL, 60, 60)
	a1.max_hp = 300
	a1.current_hp = 300

	var b0 := _make_mon_stats("B0", TypeChart.TYPE_NORMAL, 60, 70)
	b0.max_hp = 300
	b0.current_hp = 300
	var b1 := _make_mon_stats("B1", TypeChart.TYPE_NORMAL, 60, 80)
	b1.max_hp = 300
	b1.current_hp = 300

	var per_target_dmg: Dictionary = {}
	var healed_events: Array = []
	var bm := _dispatch_doubles_spread_with_signals(a0, a1, b0, b1, self_destruct, per_target_dmg, healed_events, [])

	var expected_total: int = per_target_dmg.get(b0, 0) + per_target_dmg.get(b1, 0) + per_target_dmg.get(a1, 0)
	_chk("item 2 (ally-hit case) setup sanity: all 3 targets (B0, B1, A1) took real damage from Self-Destruct",
			per_target_dmg.get(b0, 0) > 0 and per_target_dmg.get(b1, 0) > 0 and per_target_dmg.get(a1, 0) > 0)
	_chk("item 2 (ally-hit case): Shell Bell fires once for A0, off the FULL 3-target total (both opponents AND the ally), not just the 2 opponents",
			healed_events.size() == 1 and healed_events[0][0] == a0
					and healed_events[0][1] == expected_total / 8)
	bm.queue_free()


func _test_item2_negative_control_single_target_unchanged() -> void:
	# Ordinary singles Shell Bell/Life Orb behavior (no spread move
	# involved at all) must remain completely unaffected by this fix.
	var tackle := _load_move(33)
	var a0 := _make_mon("A0", TypeChart.TYPE_NORMAL, -1)
	a0.add_move(tackle)
	a0.held_item = _load_item(473)  # Shell Bell
	a0.max_hp = 300
	a0.current_hp = 100
	var b0 := _make_mon("B0", TypeChart.TYPE_NORMAL, -1)
	b0.max_hp = 300
	b0.current_hp = 300

	var healed_events: Array = []
	var bm := BattleManager.new()
	add_child(bm)
	bm.item_healed.connect(func(p, amt): healed_events.append([p, amt]))
	bm.start_battle_with_parties(BattleParty.single(a0), BattleParty.single(b0))

	_chk("item 2 negative control: ordinary singles Shell Bell still heals normally (unaffected by the spread-accumulation fix)",
			healed_events.any(func(e): return e[0] == a0 and e[1] > 0))
	bm.queue_free()
