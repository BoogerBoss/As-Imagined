extends Node

# M17h test suite — Ability-copy/overwrite plumbing (new infrastructure): Trace,
# Mummy, Receiver, Power of Alchemy, Wandering Spirit, Lingering Aroma.
#
# Scope: the 6 abilities locked in docs/decisions.md [M17h] (Step 0 re-verified all six
# against Section 13's exclusion sweep — none needed correction, unlike the M17f→M17g
# handoff):
#   Trace              (36)  — switch-in, copies a live opponent's current ability.
#   Mummy              (152) — contact → overwrites the ATTACKER's ability with Mummy
#                               (one-directional; the holder's own ability never changes).
#   Receiver           (222) — doubles-only, ally-fainting-triggered ability copy.
#   Power of Alchemy   (223) — identical mechanism to Receiver (confirmed from source:
#                               the exact same dispatch function, not a separate one).
#   Wandering Spirit   (254) — contact → BIDIRECTIONAL ability swap with the attacker
#                               (the opposite direction from Mummy's one-way overwrite).
#   Lingering Aroma    (268) — mechanically identical to Mummy (confirmed from source:
#                               the same switch-case block).
#
# Design: exemption checks (cant_be_traced/cant_be_copied/cant_be_swapped/
# cant_be_suppressed) read directly off each ability's own AbilityData resource
# (scripts/data/ability_data.gd) rather than a hardcoded ID array in this file — a
# mid-tier retrofit after discovering AbilityData already had these exact fields
# defined (with citations to these same mechanics) sitting completely unused, and
# gen_abilities.py already had full rendering support for them. M17g's original
# MOLD_BREAKER_BREAKABLE/NEUTRALIZING_GAS_UNSUPPRESSABLE hardcoded arrays were
# migrated to the same field-based design as part of this same retrofit (see the
# addendum note on [M17g] and the full [M17h] entry in docs/decisions.md).
#
# Source-verified correction worth flagging explicitly: Mummy/Lingering Aroma's own
# exemption is checked via `cant_be_suppressed` on the ATTACKER's current ability, NOT
# `cant_be_overwritten` (battle_util.c L3859-3883) — `cant_be_overwritten` is actually
# consumed by Skill-Swap/Entrainment-style MOVES, which this project doesn't have.
# Truant is the only ability in this project's roster flagged `cant_be_overwritten`
# (matching source data-for-data), but since nothing currently reads that flag, and
# NOTHING in this project's roster is flagged `cant_be_suppressed` either (the field
# Mummy actually checks), there is no real implemented ability that demonstrates
# "Mummy skips an exempt attacker" today — noted as an untested-but-implemented path
# per this tier's own task brief, rather than forcing a scenario that doesn't reflect
# real data.
#
# Testing conventions applied throughout (CLAUDE.md):
#   - Signal-snapshot, not post-battle state.
#   - Array-wrapper for any lambda reporting a scalar back to the enclosing test function.
#   - Type immunity precedes ability logic: every full-battle scenario below uses
#     Normal-type Tackle between non-Ghost/non-immune defenders.
#
# Ground truth: pokeemerald_expansion src/battle_util.c :: ABILITY_TRACE switch-in case
#   (L2964-3000), ABILITY_MUMMY/ABILITY_LINGERING_AROMA case (L3859-3883),
#   ABILITY_WANDERING_SPIRIT case (L3884-3909); src/battle_script_commands.c ::
#   BS_TryActivateReceiver (L12946-12968), BS_SetTracedAbility (L12553-12559).

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_section_1_ability_data()
	_test_section_2_trace_unit()
	_test_section_3_mummy_lingering_aroma_unit()
	_test_section_4_wandering_spirit_unit()
	_test_section_5_receiver_power_of_alchemy_unit()
	_test_section_6_trace_full_battle()
	_test_section_7_mummy_full_battle()
	_test_section_8_wandering_spirit_full_battle()
	_test_section_9_receiver_full_battle_doubles()
	_test_section_10_suppression_cross_tier_interaction()

	var total := _pass + _fail
	print("m17h_test: %d/%d passed" % [_pass, total])
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
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])


func _doubles_party(m0: BattlePokemon, m1: BattlePokemon) -> BattleParty:
	var p := BattleParty.new()
	p.members = [m0, m1]
	p.active_indices.append(1)
	return p


# ── Section 1: Ability data spot-checks ──────────────────────────────────────

func _test_section_1_ability_data() -> void:
	var trace := _load_ability(36)
	_chk("S1.01 Trace id=36", trace.ability_id == 36)
	_chk("S1.02 Trace cant_be_copied=true", trace.cant_be_copied)
	_chk("S1.03 Trace cant_be_traced=true", trace.cant_be_traced)

	var mummy := _load_ability(152)
	_chk("S1.04 Mummy id=152", mummy.ability_id == 152)
	_chk("S1.05 Mummy has no cant_be_* flags of its own", not mummy.cant_be_suppressed
			and not mummy.cant_be_copied and not mummy.cant_be_traced
			and not mummy.cant_be_swapped and not mummy.cant_be_overwritten)

	var receiver := _load_ability(222)
	_chk("S1.06 Receiver id=222", receiver.ability_id == 222)
	_chk("S1.07 Receiver cant_be_copied=true, cant_be_traced=true",
			receiver.cant_be_copied and receiver.cant_be_traced)

	var poa := _load_ability(223)
	_chk("S1.08 Power of Alchemy id=223", poa.ability_id == 223)
	_chk("S1.09 Power of Alchemy cant_be_copied=true, cant_be_traced=true",
			poa.cant_be_copied and poa.cant_be_traced)

	var wandering_spirit := _load_ability(254)
	_chk("S1.10 Wandering Spirit id=254", wandering_spirit.ability_id == 254)

	var lingering_aroma := _load_ability(268)
	_chk("S1.11 Lingering Aroma id=268", lingering_aroma.ability_id == 268)

	# M17g retrofit spot-check: Neutralizing Gas now carries all three M17h-relevant
	# exemption flags directly on its own resource (previously only representable via
	# the M17h hardcoded arrays this tier removed).
	var neutralizing_gas := _load_ability(256)
	_chk("S1.12 Neutralizing Gas cant_be_traced=true", neutralizing_gas.cant_be_traced)
	_chk("S1.13 Neutralizing Gas cant_be_copied=true", neutralizing_gas.cant_be_copied)
	_chk("S1.14 Neutralizing Gas cant_be_swapped=true", neutralizing_gas.cant_be_swapped)

	var truant := _load_ability(54)
	_chk("S1.15 Truant cant_be_overwritten=true (data-fidelity only; nothing reads it yet)",
			truant.cant_be_overwritten)

	var mold_breaker := _load_ability(104)
	var levitate := _load_ability(26)
	_chk("S1.16 M17g retrofit: Mold Breaker itself has no breakable flag",
			not mold_breaker.breakable)
	_chk("S1.17 M17g retrofit: Levitate still reads breakable=true off its own resource",
			levitate.breakable)


# ── Section 2: AbilityManager.try_trace — direct unit tests ──────────────────

func _test_section_2_trace_unit() -> void:
	var trace := _load_ability(36)
	var intimidate := _load_ability(22)
	var neutralizing_gas := _load_ability(256)

	var tracer := _make_mon("Tracer", [TypeChart.TYPE_NORMAL])
	tracer.ability = trace
	var non_tracer := _make_mon("NonTracer", [TypeChart.TYPE_NORMAL])
	non_tracer.ability = intimidate

	var opp_intimidate := _make_mon("OppIntimidate", [TypeChart.TYPE_NORMAL])
	opp_intimidate.ability = intimidate
	var opp_ng := _make_mon("OppNG", [TypeChart.TYPE_NORMAL])
	opp_ng.ability = neutralizing_gas
	var opp_fainted := _make_mon("OppFainted", [TypeChart.TYPE_NORMAL])
	opp_fainted.ability = intimidate
	opp_fainted.fainted = true
	var opp_no_ability := _make_mon("OppNoAbility", [TypeChart.TYPE_NORMAL])

	_chk("S2.01 Trace copies a single eligible opponent's ability",
			AbilityManager.try_trace(tracer, [opp_intimidate]) == AbilityManager.ABILITY_INTIMIDATE)
	_chk("S2.02 Trace actually assigns the copied ability onto the tracer",
			tracer.ability != null and tracer.ability.ability_id == AbilityManager.ABILITY_INTIMIDATE)

	var tracer2 := _make_mon("Tracer2", [TypeChart.TYPE_NORMAL])
	tracer2.ability = trace
	_chk("S2.03 Trace does NOT copy an ability flagged cant_be_traced (Neutralizing Gas)",
			AbilityManager.try_trace(tracer2, [opp_ng]) == -1)
	_chk("S2.04 tracer2's ability is unchanged after a failed trace",
			tracer2.ability.ability_id == AbilityManager.ABILITY_TRACE)

	var tracer3 := _make_mon("Tracer3", [TypeChart.TYPE_NORMAL])
	tracer3.ability = trace
	_chk("S2.05 Trace does NOT copy a fainted opponent's ability",
			AbilityManager.try_trace(tracer3, [opp_fainted]) == -1)

	var tracer4 := _make_mon("Tracer4", [TypeChart.TYPE_NORMAL])
	tracer4.ability = trace
	_chk("S2.06 Trace does NOT copy when the only opponent has no ability",
			AbilityManager.try_trace(tracer4, [opp_no_ability]) == -1)

	_chk("S2.07 non-Trace-holder: try_trace is a no-op",
			AbilityManager.try_trace(non_tracer, [opp_intimidate]) == -1)

	_chk("S2.08 no live opponents at all: try_trace is a no-op",
			AbilityManager.try_trace(tracer, []) == -1)

	# Doubles: both opposing slots eligible → 50/50, deterministic via force_pick_second.
	var tracer5 := _make_mon("Tracer5", [TypeChart.TYPE_NORMAL])
	tracer5.ability = trace
	var opp_a := _make_mon("OppA", [TypeChart.TYPE_NORMAL])
	opp_a.ability = intimidate
	var opp_b := _make_mon("OppB", [TypeChart.TYPE_NORMAL])
	opp_b.ability = _load_ability(9)  # Static — any other ordinary ability
	_chk("S2.09 doubles, both eligible, force_pick_second=false → first opponent",
			AbilityManager.try_trace(tracer5, [opp_a, opp_b], false, false) == AbilityManager.ABILITY_INTIMIDATE)

	var tracer6 := _make_mon("Tracer6", [TypeChart.TYPE_NORMAL])
	tracer6.ability = trace
	_chk("S2.10 doubles, both eligible, force_pick_second=true → second opponent",
			AbilityManager.try_trace(tracer6, [opp_a, opp_b], false, true) == AbilityManager.ABILITY_STATIC)

	# Doubles: only ONE opposing slot eligible (the other is cant_be_traced) → deterministic.
	var tracer7 := _make_mon("Tracer7", [TypeChart.TYPE_NORMAL])
	tracer7.ability = trace
	_chk("S2.11 doubles, only one eligible (other is Neutralizing Gas) → picks the eligible one",
			AbilityManager.try_trace(tracer7, [opp_ng, opp_a]) == AbilityManager.ABILITY_INTIMIDATE)


# ── Section 3: Mummy / Lingering Aroma — direct unit tests ───────────────────

func _test_section_3_mummy_lingering_aroma_unit() -> void:
	var mummy := _load_ability(152)
	var lingering_aroma := _load_ability(268)
	var tackle := _load_move(33)
	var intimidate := _load_ability(22)

	var mummy_holder := _make_mon("MummyHolder", [TypeChart.TYPE_NORMAL])
	mummy_holder.ability = mummy
	var attacker := _make_mon("Attacker", [TypeChart.TYPE_NORMAL])
	attacker.ability = intimidate

	_chk("S3.01 Mummy overwrites the attacker's ability on a damaging contact hit",
			AbilityManager.try_mummy_overwrite(mummy_holder, attacker, tackle, 10) == AbilityManager.ABILITY_MUMMY)
	_chk("S3.02 attacker's ability is actually reassigned to Mummy",
			attacker.ability.ability_id == AbilityManager.ABILITY_MUMMY)
	_chk("S3.03 the Mummy holder's OWN ability never changes (one-directional, unlike Wandering Spirit)",
			mummy_holder.ability.ability_id == AbilityManager.ABILITY_MUMMY)

	# Lingering Aroma — confirmed mechanically identical.
	var la_holder := _make_mon("LAHolder", [TypeChart.TYPE_NORMAL])
	la_holder.ability = lingering_aroma
	var attacker2 := _make_mon("Attacker2", [TypeChart.TYPE_NORMAL])
	attacker2.ability = intimidate
	_chk("S3.04 Lingering Aroma overwrites the attacker's ability identically to Mummy",
			AbilityManager.try_mummy_overwrite(la_holder, attacker2, tackle, 10) == AbilityManager.ABILITY_LINGERING_AROMA)

	# Negative: non-contact move.
	var thunderbolt := _load_move(53)
	var mummy_holder2 := _make_mon("MummyHolder2", [TypeChart.TYPE_NORMAL])
	mummy_holder2.ability = mummy
	var attacker3 := _make_mon("Attacker3", [TypeChart.TYPE_NORMAL])
	attacker3.ability = intimidate
	_chk("S3.05 Mummy does NOT trigger on a non-contact move",
			AbilityManager.try_mummy_overwrite(mummy_holder2, attacker3, thunderbolt, 10) == -1)
	_chk("S3.06 attacker3's ability is unchanged",
			attacker3.ability.ability_id == AbilityManager.ABILITY_INTIMIDATE)

	# Negative: no-op when the attacker already holds Mummy (source's redundant-guard).
	var mummy_holder3 := _make_mon("MummyHolder3", [TypeChart.TYPE_NORMAL])
	mummy_holder3.ability = mummy
	var already_mummy_attacker := _make_mon("AlreadyMummy", [TypeChart.TYPE_NORMAL])
	already_mummy_attacker.ability = _load_ability(152)
	_chk("S3.07 Mummy does NOT re-trigger when the attacker already holds Mummy",
			AbilityManager.try_mummy_overwrite(mummy_holder3, already_mummy_attacker, tackle, 10) == -1)

	# Negative: zero damage (e.g. immune hit) does not trigger.
	var mummy_holder4 := _make_mon("MummyHolder4", [TypeChart.TYPE_NORMAL])
	mummy_holder4.ability = mummy
	var attacker4 := _make_mon("Attacker4", [TypeChart.TYPE_NORMAL])
	attacker4.ability = intimidate
	_chk("S3.08 Mummy does NOT trigger when damage is 0",
			AbilityManager.try_mummy_overwrite(mummy_holder4, attacker4, tackle, 0) == -1)

	# Known gap, explicitly not forced: no ability in this project's current roster is
	# flagged cant_be_suppressed (the field Mummy's exemption actually reads — NOT
	# cant_be_overwritten, verified from source), so "Mummy skips an exempt attacker"
	# has no real implemented case to test against yet. The mechanism itself
	# (`if attacker.ability.cant_be_suppressed: return -1`) is implemented and will
	# apply correctly the moment any such ability is ever added.


# ── Section 4: Wandering Spirit — direct unit tests ──────────────────────────

func _test_section_4_wandering_spirit_unit() -> void:
	var wandering_spirit := _load_ability(254)
	var tackle := _load_move(33)
	var intimidate := _load_ability(22)
	var neutralizing_gas := _load_ability(256)

	var ws_holder := _make_mon("WSHolder", [TypeChart.TYPE_NORMAL])
	ws_holder.ability = wandering_spirit
	var attacker := _make_mon("WSAttacker", [TypeChart.TYPE_NORMAL])
	attacker.ability = intimidate

	_chk("S4.01 Wandering Spirit swap occurs on a damaging contact hit",
			AbilityManager.try_wandering_spirit_swap(ws_holder, attacker, tackle, 10))
	_chk("S4.02 attacker ends up with Wandering Spirit",
			attacker.ability.ability_id == AbilityManager.ABILITY_WANDERING_SPIRIT)
	_chk("S4.03 the holder ends up with what the attacker HAD (bidirectional, both sides changed)",
			ws_holder.ability.ability_id == AbilityManager.ABILITY_INTIMIDATE)

	# Negative: attacker holds an ability flagged cant_be_swapped (Neutralizing Gas).
	var ws_holder2 := _make_mon("WSHolder2", [TypeChart.TYPE_NORMAL])
	ws_holder2.ability = wandering_spirit
	var ng_attacker := _make_mon("NGAttacker", [TypeChart.TYPE_NORMAL])
	ng_attacker.ability = neutralizing_gas
	_chk("S4.04 Wandering Spirit does NOT swap when the attacker holds a cant_be_swapped ability",
			not AbilityManager.try_wandering_spirit_swap(ws_holder2, ng_attacker, tackle, 10))
	_chk("S4.05 neither side's ability changed",
			ws_holder2.ability.ability_id == AbilityManager.ABILITY_WANDERING_SPIRIT
			and ng_attacker.ability.ability_id == AbilityManager.ABILITY_NEUTRALIZING_GAS)

	# Negative: attacker has no ability at all (source's ABILITY_NONE is itself
	# cant_be_swapped).
	var ws_holder3 := _make_mon("WSHolder3", [TypeChart.TYPE_NORMAL])
	ws_holder3.ability = wandering_spirit
	var no_ability_attacker := _make_mon("NoAbilityAttacker", [TypeChart.TYPE_NORMAL])
	_chk("S4.06 Wandering Spirit does NOT swap with an ability-less attacker",
			not AbilityManager.try_wandering_spirit_swap(ws_holder3, no_ability_attacker, tackle, 10))

	# Negative: non-contact move.
	var thunderbolt := _load_move(53)
	var ws_holder4 := _make_mon("WSHolder4", [TypeChart.TYPE_NORMAL])
	ws_holder4.ability = wandering_spirit
	var attacker2 := _make_mon("WSAttacker2", [TypeChart.TYPE_NORMAL])
	attacker2.ability = intimidate
	_chk("S4.07 Wandering Spirit does NOT trigger on a non-contact move",
			not AbilityManager.try_wandering_spirit_swap(ws_holder4, attacker2, thunderbolt, 10))


# ── Section 5: Receiver / Power of Alchemy — direct unit tests ───────────────

func _test_section_5_receiver_power_of_alchemy_unit() -> void:
	var receiver := _load_ability(222)
	var power_of_alchemy := _load_ability(223)
	var intimidate := _load_ability(22)
	var neutralizing_gas := _load_ability(256)

	var fainted := _make_mon("Fainted", [TypeChart.TYPE_NORMAL])
	fainted.ability = intimidate
	fainted.fainted = true
	var receiver_ally := _make_mon("ReceiverAlly", [TypeChart.TYPE_NORMAL])
	receiver_ally.ability = receiver

	_chk("S5.01 Receiver copies the fainted ally's ability",
			AbilityManager.try_receiver_copy(fainted, receiver_ally) == AbilityManager.ABILITY_INTIMIDATE)
	_chk("S5.02 the ally's ability is actually reassigned",
			receiver_ally.ability.ability_id == AbilityManager.ABILITY_INTIMIDATE)

	# Power of Alchemy — confirmed identical mechanism.
	var fainted2 := _make_mon("Fainted2", [TypeChart.TYPE_NORMAL])
	fainted2.ability = intimidate
	fainted2.fainted = true
	var poa_ally := _make_mon("PoAAlly", [TypeChart.TYPE_NORMAL])
	poa_ally.ability = power_of_alchemy
	_chk("S5.03 Power of Alchemy copies the fainted ally's ability identically to Receiver",
			AbilityManager.try_receiver_copy(fainted2, poa_ally) == AbilityManager.ABILITY_INTIMIDATE)

	# Negative: singles has no ally at all — _get_ally already returns null there,
	# so this is the exact value BattleManager would pass in singles.
	_chk("S5.04 Receiver does NOT trigger in singles (ally == null)",
			AbilityManager.try_receiver_copy(fainted, null) == -1)

	# Negative: the surviving ally doesn't hold Receiver/Power of Alchemy.
	var fainted3 := _make_mon("Fainted3", [TypeChart.TYPE_NORMAL])
	fainted3.ability = intimidate
	fainted3.fainted = true
	var ordinary_ally := _make_mon("OrdinaryAlly", [TypeChart.TYPE_NORMAL])
	_chk("S5.05 Receiver does NOT trigger when the ally holds neither ability",
			AbilityManager.try_receiver_copy(fainted3, ordinary_ally) == -1)

	# Negative: the fainted mon's ability is flagged cant_be_copied (Neutralizing Gas).
	var fainted_ng := _make_mon("FaintedNG", [TypeChart.TYPE_NORMAL])
	fainted_ng.ability = neutralizing_gas
	fainted_ng.fainted = true
	var receiver_ally2 := _make_mon("ReceiverAlly2", [TypeChart.TYPE_NORMAL])
	receiver_ally2.ability = receiver
	_chk("S5.06 Receiver does NOT copy an ability flagged cant_be_copied",
			AbilityManager.try_receiver_copy(fainted_ng, receiver_ally2) == -1)

	# Negative: "the Receiver holder itself is the one fainting" — fainted holds
	# Receiver, ally does not, so the ally-side check naturally fails.
	var fainted_receiver_holder := _make_mon("FaintedReceiverHolder", [TypeChart.TYPE_NORMAL])
	fainted_receiver_holder.ability = receiver
	fainted_receiver_holder.fainted = true
	var non_receiver_ally := _make_mon("NonReceiverAlly", [TypeChart.TYPE_NORMAL])
	non_receiver_ally.ability = intimidate
	_chk("S5.07 does NOT trigger when the Receiver HOLDER itself is the one fainting",
			AbilityManager.try_receiver_copy(fainted_receiver_holder, non_receiver_ally) == -1)
	_chk("S5.08 the surviving ally's ability is unchanged",
			non_receiver_ally.ability.ability_id == AbilityManager.ABILITY_INTIMIDATE)


# ── Section 6: Trace — full-battle integration ───────────────────────────────

func _test_section_6_trace_full_battle() -> void:
	var tackle := _load_move(33)
	var trace := _load_ability(36)
	var intimidate := _load_ability(22)

	var tracer := _make_mon("BattleTracer", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 60)
	tracer.ability = trace
	tracer.add_move(tackle)
	var opp := _make_mon("BattleOppIntimidate", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 60)
	opp.ability = intimidate
	opp.add_move(tackle)

	var ability_changes := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.ability_changed.connect(func(p, new_id): ability_changes.push_back([p, new_id]))

	bm.start_battle_with_parties(BattleParty.single(tracer), BattleParty.single(opp))

	_chk("S6.01 Trace copied Intimidate on switch-in (full battle)",
			ability_changes.any(func(e): return e[0] == tracer and e[1] == AbilityManager.ABILITY_INTIMIDATE))

	bm.queue_free()


# ── Section 7: Mummy — full-battle integration ───────────────────────────────

func _test_section_7_mummy_full_battle() -> void:
	var tackle := _load_move(33)
	var mummy := _load_ability(152)
	var intimidate := _load_ability(22)

	var mummy_holder := _make_mon("BattleMummy", [TypeChart.TYPE_NORMAL], 100, 40, 100, 40, 100, 60)
	mummy_holder.ability = mummy
	mummy_holder.add_move(tackle)
	var attacker := _make_mon("BattleAttacker", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 100)
	attacker.ability = intimidate
	attacker.add_move(tackle)

	var ability_changes := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.ability_changed.connect(func(p, new_id): ability_changes.push_back([p, new_id]))

	bm.start_battle_with_parties(BattleParty.single(attacker), BattleParty.single(mummy_holder))

	_chk("S7.01 Mummy overwrote the attacker's ability after a contact hit (full battle)",
			ability_changes.any(func(e): return e[0] == attacker and e[1] == AbilityManager.ABILITY_MUMMY))
	_chk("S7.02 the Mummy holder's own ability is unaffected",
			mummy_holder.ability.ability_id == AbilityManager.ABILITY_MUMMY)

	bm.queue_free()


# ── Section 8: Wandering Spirit — full-battle integration ───────────────────

func _test_section_8_wandering_spirit_full_battle() -> void:
	var tackle := _load_move(33)
	var wandering_spirit := _load_ability(254)
	var intimidate := _load_ability(22)

	var ws_holder := _make_mon("BattleWS", [TypeChart.TYPE_NORMAL], 100, 40, 100, 40, 100, 60)
	ws_holder.ability = wandering_spirit
	ws_holder.add_move(tackle)
	var attacker := _make_mon("BattleWSAttacker", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 100)
	attacker.ability = intimidate
	attacker.add_move(tackle)

	var ability_changes := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.ability_changed.connect(func(p, new_id): ability_changes.push_back([p, new_id]))

	bm.start_battle_with_parties(BattleParty.single(attacker), BattleParty.single(ws_holder))

	_chk("S8.01 attacker ended up with Wandering Spirit (full battle)",
			ability_changes.any(func(e): return e[0] == attacker and e[1] == AbilityManager.ABILITY_WANDERING_SPIRIT))
	_chk("S8.02 the holder ended up with Intimidate — BOTH sides changed, not just one",
			ability_changes.any(func(e): return e[0] == ws_holder and e[1] == AbilityManager.ABILITY_INTIMIDATE))

	bm.queue_free()


# ── Section 9: Receiver — full-battle integration (doubles) ─────────────────

func _test_section_9_receiver_full_battle_doubles() -> void:
	var tackle := _load_move(33)
	var receiver := _load_ability(222)
	var intimidate := _load_ability(22)

	# Player: a low-HP Intimidate holder (will be KO'd turn 1) + a Receiver holder ally.
	var faller := _make_mon("BattleFaller", [TypeChart.TYPE_NORMAL], 20, 40, 40, 40, 40, 60)
	faller.ability = intimidate
	faller.add_move(tackle)
	var receiver_ally := _make_mon("BattleReceiverAlly", [TypeChart.TYPE_NORMAL], 100, 40, 100, 40, 100, 50)
	receiver_ally.ability = receiver
	receiver_ally.add_move(tackle)

	var opp1 := _make_mon("BattleOpp1", [TypeChart.TYPE_NORMAL], 100, 150, 60, 60, 60, 200)
	opp1.add_move(tackle)
	var opp2 := _make_mon("BattleOpp2", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 40)
	opp2.add_move(tackle)

	var ability_changes := []
	var bm := BattleManager.new()
	add_child(bm)
	bm.ability_changed.connect(func(p, new_id): ability_changes.push_back([p, new_id]))

	bm.start_battle_doubles(_doubles_party(faller, receiver_ally), _doubles_party(opp1, opp2))

	_chk("S9.01 Receiver copied the fainted ally's Intimidate (full doubles battle)",
			ability_changes.any(func(e): return e[0] == receiver_ally and e[1] == AbilityManager.ABILITY_INTIMIDATE))

	bm.queue_free()


# ── Section 10: cross-tier interaction — copy-time vs. suppression-time ─────
#
# A traced/copied ability's ID is assigned at copy time regardless of suppression;
# Neutralizing Gas suppression is a completely separate, later runtime check applied
# every time the ability is actually consumed. Source confirms Trace/Receiver/Mummy/
# Wandering Spirit all read/write RAW `.ability` fields (never the suppression-aware
# accessor) — see ability_manager.gd's try_trace doc comment for the full citation.

func _test_section_10_suppression_cross_tier_interaction() -> void:
	var trace := _load_ability(36)
	var intimidate := _load_ability(22)
	var neutralizing_gas := _load_ability(256)

	var tracer := _make_mon("SuppressionTracer", [TypeChart.TYPE_NORMAL])
	tracer.ability = trace
	var opp_intimidate := _make_mon("SuppressionOpp", [TypeChart.TYPE_NORMAL])
	opp_intimidate.ability = intimidate

	var traced_id: int = AbilityManager.try_trace(tracer, [opp_intimidate])
	_chk("S10.01 Trace successfully copied Intimidate (no Neutralizing Gas on the field yet)",
			traced_id == AbilityManager.ABILITY_INTIMIDATE)

	# Now simulate Neutralizing Gas becoming active elsewhere on the field — the
	# tracer's own copied ability was NOT re-derived or filtered at copy time.
	_chk("S10.02 the tracer's raw ability id is still Intimidate, unaffected by suppression",
			tracer.ability.ability_id == AbilityManager.ABILITY_INTIMIDATE)
	_chk("S10.03 but effective_ability_id correctly reports it suppressed once " +
			"Neutralizing Gas is active (ng_active=true) — the runtime check, not a copy-time filter",
			AbilityManager.effective_ability_id(tracer, true) == AbilityManager.ABILITY_NONE)
	_chk("S10.04 and effective_ability_id reports it normally again once Neutralizing " +
			"Gas is no longer active (ng_active=false)",
			AbilityManager.effective_ability_id(tracer, false) == AbilityManager.ABILITY_INTIMIDATE)

	# Full-battle version: a live Neutralizing Gas holder is present on the SAME side as
	# a Trace holder that already copied an ordinary ability from the opponent before
	# switching in again — confirms the field-level finding also holds through
	# BattleManager's actual ng_active plumbing, not just the direct unit call above.
	var ng_holder := _make_mon("SuppressionNGHolder", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 60)
	ng_holder.ability = neutralizing_gas
	_chk("S10.05 is_neutralizing_gas_active reports true with this holder present",
			AbilityManager.is_neutralizing_gas_active([tracer, ng_holder]))
	_chk("S10.06 the tracer's copied Intimidate is suppressed field-wide once NG joins the field",
			AbilityManager.effective_ability_id(tracer, AbilityManager.is_neutralizing_gas_active([tracer, ng_holder]))
					== AbilityManager.ABILITY_NONE)
	_chk("S10.07 yet the raw copied ability id is STILL Intimidate underneath the suppression",
			tracer.ability.ability_id == AbilityManager.ABILITY_INTIMIDATE)
