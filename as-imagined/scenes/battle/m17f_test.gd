extends Node

# M17f test suite — Trapping check (new infrastructure): Shadow Tag / Arena Trap /
# Magnet Pull.
#
# Scope: the 3 abilities locked in docs/decisions.md [M17f]:
#   Shadow Tag  (23) — traps ALL opponents (Ghost-type exempt; mirror-match exempt).
#   Arena Trap  (71) — traps only GROUNDED opponents.
#   Magnet Pull (42) — traps only Steel-type opponents.
#
# New infrastructure: AbilityManager.is_trapped(mon, live_opponents) -> bool, wired into
# BattleManager._phase_move_selection right after a queued/AI-chosen voluntary switch
# sets _chosen_switch_slots — a blocked switch falls back to the mon's first move.
# Forced switches (Roar/Whirlwind), faint replacement, and Baton Pass are architecturally
# separate call paths (_do_forced_switch_in / _phase_switch_prompt / a move, never
# _chosen_switch_slots) and must remain completely unaffected.
#
# Testing conventions applied throughout (CLAUDE.md):
#   - Signal-snapshot, not post-battle state: all pass/fail checks read event arrays
#     populated by signal connections, not mutated post-battle fields.
#   - Array-wrapper for any lambda that needs to report a scalar back to the enclosing
#     test function.
#   - Type immunity precedes ability logic: every full-battle scenario below uses
#     Normal-type Tackle between non-Ghost defenders (Ghost/Normal immunity is the one
#     relevant immunity in this tier's type set — confirmed absent from every scripted
#     damage exchange; Ghost-type mons appear ONLY in the direct is_trapped unit tests,
#     which never call DamageCalculator).
#
# Ground truth: pokeemerald_expansion src/battle_util.c :: IsAbilityPreventingEscape
#   (L4917-4941), src/battle_main.c (L3993, L4230-4238 — selection-time gating).

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_section_1_ability_data()
	_test_section_2_is_trapped_unit()
	_test_section_3_shadow_tag_blocks_switch()
	_test_section_3b_arena_trap_flying_exempt()
	_test_section_3c_magnet_pull_steel_only()
	_test_section_3d_ghost_type_exempt_from_shadow_tag()
	_test_section_4_forced_switch_bypasses_trapping()
	_test_section_5_baton_pass_bypasses_trapping()
	_test_section_6_faint_replacement_bypasses_trapping()
	_test_section_7_holder_own_side_unaffected()

	var total := _pass + _fail
	print("m17f_test: %d/%d passed" % [_pass, total])
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


# ── Section 1: Ability data spot-checks ──────────────────────────────────────

func _test_section_1_ability_data() -> void:
	var shadow_tag := _load_ability(23)
	_chk("S1.01 Shadow Tag id=23", shadow_tag.ability_id == 23)
	var arena_trap := _load_ability(71)
	_chk("S1.02 Arena Trap id=71", arena_trap.ability_id == 71)
	var magnet_pull := _load_ability(42)
	_chk("S1.03 Magnet Pull id=42", magnet_pull.ability_id == 42)


# ── Section 2: AbilityManager.is_trapped — direct unit tests ─────────────────

func _test_section_2_is_trapped_unit() -> void:
	var shadow_tag := _load_ability(23)
	var arena_trap := _load_ability(71)
	var magnet_pull := _load_ability(42)
	var levitate := _load_ability(26)

	var normal_mon := _make_mon("Normal", [TypeChart.TYPE_NORMAL])
	var flying_mon := _make_mon("Flying", [TypeChart.TYPE_FLYING])
	var levitate_mon := _make_mon("LevitateMon", [TypeChart.TYPE_NORMAL])
	levitate_mon.ability = levitate
	var steel_mon := _make_mon("Steel", [TypeChart.TYPE_STEEL])
	var ghost_mon := _make_mon("Ghost", [TypeChart.TYPE_GHOST])
	var ghost_steel_mon := _make_mon("GhostSteel", [TypeChart.TYPE_GHOST, TypeChart.TYPE_STEEL])
	var shadow_tag_mon := _make_mon("ShadowTagMon", [TypeChart.TYPE_NORMAL])
	shadow_tag_mon.ability = shadow_tag

	var opp_shadow_tag := _make_mon("OppShadowTag", [TypeChart.TYPE_NORMAL])
	opp_shadow_tag.ability = shadow_tag
	var opp_arena_trap := _make_mon("OppArenaTrap", [TypeChart.TYPE_NORMAL])
	opp_arena_trap.ability = arena_trap
	var opp_magnet_pull := _make_mon("OppMagnetPull", [TypeChart.TYPE_NORMAL])
	opp_magnet_pull.ability = magnet_pull
	var opp_none := _make_mon("OppNone", [TypeChart.TYPE_NORMAL])

	_chk("S2.01 Shadow Tag traps a grounded Normal-type opponent",
			AbilityManager.is_trapped(normal_mon, [opp_shadow_tag]))
	_chk("S2.02 Arena Trap traps a grounded Normal-type opponent",
			AbilityManager.is_trapped(normal_mon, [opp_arena_trap]))
	_chk("S2.03 Arena Trap does NOT trap a Flying-type opponent",
			not AbilityManager.is_trapped(flying_mon, [opp_arena_trap]))
	_chk("S2.04 Arena Trap does NOT trap a Levitate holder",
			not AbilityManager.is_trapped(levitate_mon, [opp_arena_trap]))
	_chk("S2.05 Magnet Pull traps a Steel-type opponent",
			AbilityManager.is_trapped(steel_mon, [opp_magnet_pull]))
	_chk("S2.06 Magnet Pull does NOT trap a non-Steel opponent",
			not AbilityManager.is_trapped(normal_mon, [opp_magnet_pull]))
	_chk("S2.07 Ghost-type is exempt from Shadow Tag",
			not AbilityManager.is_trapped(ghost_mon, [opp_shadow_tag]))
	_chk("S2.08 Ghost-type is exempt from Arena Trap (even though grounded)",
			not AbilityManager.is_trapped(ghost_mon, [opp_arena_trap]))
	_chk("S2.09 Ghost-type is exempt from Magnet Pull (even dual Ghost/Steel)",
			not AbilityManager.is_trapped(ghost_steel_mon, [opp_magnet_pull]))
	_chk("S2.10 Shadow Tag mirror match: neither side traps the other",
			not AbilityManager.is_trapped(shadow_tag_mon, [opp_shadow_tag]))
	_chk("S2.11 No opposing ability: not trapped",
			not AbilityManager.is_trapped(normal_mon, [opp_none]))
	_chk("S2.12 Doubles-shape: trapped if ANY live opponent has a trapping ability",
			AbilityManager.is_trapped(normal_mon, [opp_none, opp_shadow_tag]))


# ── Section 3: Shadow Tag blocks a voluntary switch (full battle) ────────────

func _test_section_3_shadow_tag_blocks_switch() -> void:
	var tackle := _load_move(33)

	var trapper := _make_mon("Trapper", [TypeChart.TYPE_NORMAL], 60, 60, 40, 60, 40, 100)
	trapper.ability = _load_ability(23)
	trapper.add_move(tackle)

	var trapped := _make_mon("Trapped", [TypeChart.TYPE_NORMAL], 60, 60, 40, 60, 40, 50)
	trapped.add_move(tackle)
	var bench := _make_mon("Bench", [TypeChart.TYPE_NORMAL], 60, 60, 40, 60, 40, 50)
	bench.add_move(tackle)

	var switched_out := []
	var moves_used := []
	# Ordered log: the battle runs to completion, so Trapped may eventually faint from
	# ordinary combat and Bench may THEN legitimately switch in as a faint replacement
	# (Section 6 already confirms faint replacement bypasses trapping, correctly). The
	# blocked-switch claim is specifically "no VOLUNTARY switch-out ever happened" (S3.01,
	# via pokemon_switched_out, which faint replacement never emits — see
	# battle_manager.gd's _do_switch_in) plus "if Bench switched in at all, it was only
	# after Trapped's own faint, never as the immediate blocked turn-1 switch" (S3.02).
	var event_log := []  # [["fainted"|"switched_in", mon], ...]

	var bm := BattleManager.new()
	add_child(bm)
	bm.pokemon_switched_out.connect(func(p, s): switched_out.push_back([p, s]))
	bm.pokemon_switched_in.connect(func(p, s, sl): event_log.push_back(["switched_in", p]))
	bm.pokemon_fainted.connect(func(p): event_log.push_back(["fainted", p]))
	bm.move_executed.connect(func(a, d, m, dmg): moves_used.push_back(a))

	var opp_party := BattleParty.new()
	opp_party.members = [trapped, bench]
	opp_party.active_index = 0

	bm.queue_switch(1, 1)  # Turn 1: opponent tries to voluntarily switch to bench.
	bm.start_battle_with_parties(BattleParty.single(trapper), opp_party)

	_chk("S3.01 trapped opponent never switched out (no voluntary switch ever occurred)",
			not switched_out.any(func(e): return e[0] == trapped))
	_chk("S3.03 blocked switch fell back to a move (Trapped used Tackle instead)",
			moves_used.any(func(a): return a == trapped))

	var trapped_fainted_idx := -1
	var bench_switched_in_idx := -1
	for i in range(event_log.size()):
		if event_log[i][0] == "fainted" and event_log[i][1] == trapped:
			trapped_fainted_idx = i
		if event_log[i][0] == "switched_in" and event_log[i][1] == bench:
			bench_switched_in_idx = i
	_chk("S3.02 Bench, if it ever entered, only did so as a legitimate faint replacement " +
			"(after Trapped fainted) — never as the immediately-blocked turn-1 switch",
			bench_switched_in_idx == -1 or
			(trapped_fainted_idx >= 0 and bench_switched_in_idx > trapped_fainted_idx))

	bm.queue_free()


# ── Section 3B: Arena Trap does NOT trap a Flying-type opponent ─────────────

func _test_section_3b_arena_trap_flying_exempt() -> void:
	var tackle := _load_move(33)

	var trapper := _make_mon("Trapper2", [TypeChart.TYPE_NORMAL], 60, 60, 40, 60, 40, 100)
	trapper.ability = _load_ability(71)
	trapper.add_move(tackle)

	var flying_opp := _make_mon("FlyingOpp", [TypeChart.TYPE_FLYING], 60, 60, 40, 60, 40, 50)
	flying_opp.add_move(tackle)
	var bench := _make_mon("Bench2", [TypeChart.TYPE_NORMAL], 60, 60, 40, 60, 40, 50)
	bench.add_move(tackle)

	var switched_out := []
	var switched_in := []

	var bm := BattleManager.new()
	add_child(bm)
	bm.pokemon_switched_out.connect(func(p, s): switched_out.push_back([p, s]))
	bm.pokemon_switched_in.connect(func(p, s, sl): switched_in.push_back([p, s, sl]))

	var opp_party := BattleParty.new()
	opp_party.members = [flying_opp, bench]
	opp_party.active_index = 0

	bm.queue_switch(1, 1)  # Turn 1: ungrounded opponent switches — Arena Trap can't stop it.
	bm.start_battle_with_parties(BattleParty.single(trapper), opp_party)

	_chk("S3B.01 Flying-type opponent DID switch out despite Arena Trap",
			switched_out.any(func(e): return e[0] == flying_opp))
	_chk("S3B.02 bench DID switch in",
			switched_in.any(func(e): return e[0] == bench))

	bm.queue_free()


# ── Section 3C: Magnet Pull traps Steel-type only ────────────────────────────

func _test_section_3c_magnet_pull_steel_only() -> void:
	var tackle := _load_move(33)

	# (i) Steel-type opponent: blocked.
	var trapper_i := _make_mon("Trapper3i", [TypeChart.TYPE_NORMAL], 60, 60, 40, 60, 40, 100)
	trapper_i.ability = _load_ability(42)
	trapper_i.add_move(tackle)
	var steel_opp := _make_mon("SteelOpp", [TypeChart.TYPE_STEEL], 60, 60, 40, 60, 40, 50)
	steel_opp.add_move(tackle)
	var bench_i := _make_mon("Bench3i", [TypeChart.TYPE_NORMAL], 60, 60, 40, 60, 40, 50)
	bench_i.add_move(tackle)

	var switched_out_i := []
	var bm_i := BattleManager.new()
	add_child(bm_i)
	bm_i.pokemon_switched_out.connect(func(p, s): switched_out_i.push_back([p, s]))
	var opp_party_i := BattleParty.new()
	opp_party_i.members = [steel_opp, bench_i]
	opp_party_i.active_index = 0
	bm_i.queue_switch(1, 1)
	bm_i.start_battle_with_parties(BattleParty.single(trapper_i), opp_party_i)
	_chk("S3C.01 Steel-type opponent blocked from switching by Magnet Pull",
			not switched_out_i.any(func(e): return e[0] == steel_opp))
	bm_i.queue_free()

	# (ii) Non-Steel opponent: NOT blocked.
	var trapper_ii := _make_mon("Trapper3ii", [TypeChart.TYPE_NORMAL], 60, 60, 40, 60, 40, 100)
	trapper_ii.ability = _load_ability(42)
	trapper_ii.add_move(tackle)
	var normal_opp := _make_mon("NormalOpp", [TypeChart.TYPE_NORMAL], 60, 60, 40, 60, 40, 50)
	normal_opp.add_move(tackle)
	var bench_ii := _make_mon("Bench3ii", [TypeChart.TYPE_NORMAL], 60, 60, 40, 60, 40, 50)
	bench_ii.add_move(tackle)

	var switched_out_ii := []
	var bm_ii := BattleManager.new()
	add_child(bm_ii)
	bm_ii.pokemon_switched_out.connect(func(p, s): switched_out_ii.push_back([p, s]))
	var opp_party_ii := BattleParty.new()
	opp_party_ii.members = [normal_opp, bench_ii]
	opp_party_ii.active_index = 0
	bm_ii.queue_switch(1, 1)
	bm_ii.start_battle_with_parties(BattleParty.single(trapper_ii), opp_party_ii)
	_chk("S3C.02 non-Steel opponent switches freely despite Magnet Pull",
			switched_out_ii.any(func(e): return e[0] == normal_opp))
	bm_ii.queue_free()


# ── Section 3D: Ghost-type opponent is exempt from Shadow Tag (full battle) ──
#
# Section 2 already confirms this at the is_trapped() unit level (S2.07-S2.09); this
# closes the gap to a real _phase_move_selection voluntary-switch flow, using Shadow
# Tag specifically since it's the most totalizing of the three (traps everyone, no
# type/grounded condition of its own) — the strongest possible case for the Ghost gate
# to override. Source: battle_util.c :: IsAbilityPreventingEscape (L4919) and
# CanBattlerEscape (L4947) both gate on the SAME B_GHOSTS_ESCAPE >= GEN_6 check, one
# covering ability-based trapping and the other covering move-based trapping volatiles —
# confirming the exemption is uniform across trapping sources, not a Shadow-Tag-specific
# carve-out (see the extensibility comment on is_trapped() in ability_manager.gd).
#
# Type-immunity-precedes-ability-logic note (CLAUDE.md's third testing pitfall): Ghost is
# IMMUNE (0x) to Normal-type Tackle, which every other scenario in this suite uses. This
# scenario sidesteps that entirely rather than fighting around it — per this project's
# established action ordering (switches always resolve before moves), the queued switch
# on turn 1 is decided before any Tackle would ever be thrown at the Ghost-type mon, so
# it leaves the field without ever being a damage target. Mirrors Section 3B's structure
# (an ungrounded Flying-type opponent switching away from Arena Trap) exactly.

func _test_section_3d_ghost_type_exempt_from_shadow_tag() -> void:
	var tackle := _load_move(33)

	var trapper := _make_mon("Trapper3d", [TypeChart.TYPE_NORMAL], 60, 60, 40, 60, 40, 100)
	trapper.ability = _load_ability(23)
	trapper.add_move(tackle)

	var ghost_opp := _make_mon("GhostOpp", [TypeChart.TYPE_GHOST], 60, 60, 40, 60, 40, 50)
	ghost_opp.add_move(tackle)
	var bench := _make_mon("Bench3d", [TypeChart.TYPE_NORMAL], 60, 60, 40, 60, 40, 50)
	bench.add_move(tackle)

	var switched_out := []
	var switched_in := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.pokemon_switched_out.connect(func(p, s): switched_out.push_back([p, s]))
	bm.pokemon_switched_in.connect(func(p, s, sl): switched_in.push_back([p, s, sl]))

	var opp_party := BattleParty.new()
	opp_party.members = [ghost_opp, bench]
	opp_party.active_index = 0

	bm.queue_switch(1, 1)  # Turn 1: Ghost-type opponent switches — Shadow Tag can't stop it.
	bm.start_battle_with_parties(BattleParty.single(trapper), opp_party)

	_chk("S3D.01 Ghost-type opponent DID switch out despite Shadow Tag (full battle)",
			switched_out.any(func(e): return e[0] == ghost_opp))
	_chk("S3D.02 bench DID switch in for the Ghost-type opponent's side",
			switched_in.any(func(e): return e[0] == bench))

	bm.queue_free()


# ── Section 4: Forced switch (Roar) bypasses trapping entirely ──────────────

func _test_section_4_forced_switch_bypasses_trapping() -> void:
	var roar := _load_move(46)
	var tackle := _load_move(33)
	if roar == null:
		_chk("S4.0x Roar loaded (skip)", false)
		return

	# Player holds Shadow Tag (trapping the opponent) and Roars the opponent anyway —
	# forced switches must bypass trapping, same as source's CanBattlerEscape having no
	# ability check at all.
	var player := _make_mon("Player", [TypeChart.TYPE_NORMAL], 500, 200, 200, 80, 200, 200)
	player.ability = _load_ability(23)
	player.add_move(tackle)  # index 0: auto-select on later turns
	player.add_move(roar)    # index 1: queued turn 1

	var opp1 := _make_mon("Opp1", [TypeChart.TYPE_NORMAL], 160, 60, 60, 60, 60, 80)
	var opp2 := _make_mon("Opp2", [TypeChart.TYPE_NORMAL], 160, 60, 60, 60, 60, 80)
	opp1.add_move(tackle)
	opp2.add_move(tackle)
	opp2.current_hp = 1

	var forced_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.forced_switch.connect(func(old, nw): forced_events.push_back([old, nw]))
	bm._force_roar_rng = 0

	var opp_party := BattleParty.new()
	opp_party.members = [opp1, opp2]
	opp_party.active_index = 0

	bm.queue_move(0, 1)  # Turn 1: player Roars the (Shadow-Tag-trapped-by-itself) opp1.
	bm.start_battle_with_parties(BattleParty.single(player), opp_party)

	_chk("S4.01 Roar still force-switches a Pokémon trapped by the Roar user's own Shadow Tag",
			forced_events.any(func(e): return e[0] == opp1 and e[1] == opp2))

	bm.queue_free()


# ── Section 5: Baton Pass bypasses trapping entirely ─────────────────────────

func _test_section_5_baton_pass_bypasses_trapping() -> void:
	var baton_pass := _load_move(226)
	var tackle := _load_move(33)
	if baton_pass == null:
		_chk("S5.0x Baton Pass loaded (skip)", false)
		return

	var mon1 := _make_mon("BPUser", [TypeChart.TYPE_NORMAL], 160, 80, 100, 80, 100, 200)
	mon1.add_move(baton_pass)
	var mon2 := _make_mon("BPReceiver", [TypeChart.TYPE_NORMAL], 160, 200, 100, 80, 100, 201)
	mon2.add_move(tackle)

	# Opponent traps mon1 with Shadow Tag — Baton Pass (a move, not a switch action)
	# must still succeed.
	var opp := _make_mon("Opp", [TypeChart.TYPE_NORMAL], 160, 60, 60, 60, 60, 80)
	opp.ability = _load_ability(23)
	opp.add_move(tackle)
	opp.current_hp = 1

	var bp_events := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.baton_passed.connect(func(f, t): bp_events.push_back([f, t]))

	var player_party := BattleParty.new()
	player_party.members = [mon1, mon2]
	player_party.active_index = 0

	bm.queue_move(0, 0)  # Turn 1: mon1 uses Baton Pass despite being trapped by opp.
	bm.start_battle_with_parties(player_party, BattleParty.single(opp))

	_chk("S5.01 Baton Pass succeeds even though the user is trapped by the opponent",
			bp_events.any(func(e): return e[0] == mon1 and e[1] == mon2))

	bm.queue_free()


# ── Section 6: Faint replacement bypasses trapping entirely ─────────────────

func _test_section_6_faint_replacement_bypasses_trapping() -> void:
	var tackle := _load_move(33)

	var mon1 := _make_mon("Mon1Faints", [TypeChart.TYPE_NORMAL], 40, 40, 40, 40, 40, 80)
	mon1.add_move(tackle)
	var mon2 := _make_mon("Mon2In", [TypeChart.TYPE_NORMAL], 160, 200, 160, 80, 160, 201)
	mon2.add_move(tackle)

	# Opponent traps the player's side with Shadow Tag — a fainted replacement must
	# still be able to switch in.
	var opp1 := _make_mon("Opp1", [TypeChart.TYPE_NORMAL], 160, 200, 60, 80, 60, 200)
	opp1.ability = _load_ability(23)
	opp1.add_move(tackle)
	mon1.current_hp = 1  # opp1 KOs mon1 turn 1

	var switched_in := []
	var replacements := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.pokemon_switched_in.connect(func(p, s, sl): switched_in.push_back([p, s, sl]))
	bm.replacement_needed.connect(func(s): replacements.push_back(s))

	var player_party := BattleParty.new()
	player_party.members = [mon1, mon2]
	player_party.active_index = 0

	bm.start_battle_with_parties(player_party, BattleParty.single(opp1))

	_chk("S6.01 replacement_needed fired despite player's side being trapped",
			replacements.any(func(s): return s == 0))
	_chk("S6.02 mon2 switched in as a faint replacement despite the trap",
			switched_in.any(func(e): return e[0] == mon2 and e[1] == 0))

	bm.queue_free()


# ── Section 7: Trapping only restricts the OPPONENT, never the holder itself ─

func _test_section_7_holder_own_side_unaffected() -> void:
	var tackle := _load_move(33)

	var trapper := _make_mon("SelfSwitcher", [TypeChart.TYPE_NORMAL], 60, 60, 40, 60, 40, 100)
	trapper.ability = _load_ability(23)
	trapper.add_move(tackle)
	var bench := _make_mon("SelfBench", [TypeChart.TYPE_NORMAL], 60, 60, 40, 60, 40, 50)
	bench.add_move(tackle)

	var opp := _make_mon("Opp", [TypeChart.TYPE_NORMAL], 60, 60, 40, 60, 40, 50)
	opp.add_move(tackle)

	var switched_out := []
	var switched_in := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.pokemon_switched_out.connect(func(p, s): switched_out.push_back([p, s]))
	bm.pokemon_switched_in.connect(func(p, s, sl): switched_in.push_back([p, s, sl]))

	var player_party := BattleParty.new()
	player_party.members = [trapper, bench]
	player_party.active_index = 0

	bm.queue_switch(0, 1)  # Turn 1: the Shadow Tag HOLDER voluntarily switches itself out.
	bm.start_battle_with_parties(player_party, BattleParty.single(opp))

	_chk("S7.01 Shadow Tag holder can freely switch itself out",
			switched_out.any(func(e): return e[0] == trapper))
	_chk("S7.02 bench switched in for the holder's own side",
			switched_in.any(func(e): return e[0] == bench))

	bm.queue_free()
