extends Node

# M17n-11 test suite — Group 8, "unique/standalone" part 2 (the FINAL M17n
# sub-tier): Comatose, Costar, Wonder Skin, Mirror Armor.
#
# IDs re-verified fresh against include/constants/abilities.h: Comatose=213,
# Costar=294, Wonder Skin=147, Mirror Armor=240.
#
# Comatose: source touches ~8 call sites (Sleep Talk/Snore's "user must be asleep"
# gate, Rest's "already asleep" failure, Nightmare's continued damage, Wake-Up
# Slap-style double-damage-vs-asleep, an AI scoring case, a Battle Pike case, a
# Transform+Gastro-Acid edge case) — but a full roster grep confirms NONE of Sleep
# Talk/Snore/Rest/Nightmare/Wake-Up-Slap exist in this project's 91-move roster, and
# Transform/Gastro Acid don't exist either. The ONLY genuinely implementable piece is
# full non-volatile-status immunity — confirmed via source to be the EXACT SAME case
# branch as Purifying Salt (`[M17b]`), not just similarly shaped
# (`abilityDef == ABILITY_COMATOSE || abilityDef == ABILITY_PURIFYING_SALT`,
# battle_util.c L5359-5361). Confusion is a VOLATILE status, handled by a completely
# separate function in source with no Comatose mention anywhere — Comatose does NOT
# block confusion (unlike Own Tempo/Oblivious). Comatose is NOT `breakable` in
# source (unlike Purifying Salt, which is) — confirmed via the SAME
# `effective_ability_id` call already correctly yielding per-ability Mold-Breaker
# behavior with no extra branching needed. `cant_be_suppressed=true`, so
# Neutralizing Gas never suppresses it either — the only ability in this project's
# M17n-10/M17n-11 pair with that exemption confirmed reachable.
#
# Costar: switch-in, doubles-only, copies the ally's CURRENT stat stages (all 7) +
# focus_energy onto the holder, gated on `BattlerHasCopyableChanges` (source:
# battle_util.c L5964-5979 — true if the ally has ANY non-default stage or
# focusEnergy/dragonCheer/bonusCritStages; the latter two aren't implemented here).
# A confirmed no-op (no copy, no message) if the ally has nothing worth copying —
# not a reset-to-zero of the holder's own pre-existing stages. Reuses `[M16e]`'s
# Psych Up stat-stage-array-copy shape exactly. `_get_ally` already returns null in
# singles with zero extra plumbing, matching `[M17c]`'s Hospitality precedent.
#
# Wonder Skin: floors a STATUS move's own accuracy stat to 50 (battle_util.c
# L10275-10276: `if (defAbility == ABILITY_WONDER_SKIN && IsBattleMoveStatus(move)
# && moveAcc > 50) moveAcc = 50;`) BEFORE the stage-ratio multiplication — this is a
# floor on the move's OWN accuracy value fed into the normal pipeline, not a flat
# final-chance override, so an attacker's other accuracy-boosting abilities/stages
# still apply multiplicatively on top of the floored value. Never affects damaging
# moves. Never RAISES an already-≤50%-accuracy status move — confirmed via a
# synthetic MoveData, since no move in this project's roster has non-100%,
# sub-50%-or-otherwise accuracy in the status category. `.breakable=TRUE`.
#
# Mirror Armor: a non-self-inflicted stat DECREASE targeting the holder redirects
# onto whoever caused it (same stage/amount, NOT reversed in sign — a genuinely
# different shape from Guard Dog's own Intimidate-specific +1 reversal). Source:
# `IsMirrorArmorReflected` (battle_stat_change.c L742-744) confirms a
# SELF-inflicted drop (`battlerAtk == battlerDef`) is NEVER redirected — applies to
# the holder itself like normal; tested via a synthetic self-lowering MoveData since
# this project's roster has no Overheat/Draco-Meteor/Close-Combat equivalent.
# Confirmed architecturally independent from `[M17n-10]`'s Guard Dog: a single mon
# can only hold one ability, so the two never compete for the SAME Intimidate
# event — in doubles, one opponent's Guard Dog and the OTHER opponent's Mirror Armor
# each resolve independently against the same Intimidate switch-in. Mirror Armor's
# Intimidate-specific redirect (in `try_switch_in`) is, like Guard Dog's own
# equivalent, NOT Mold-Breaker-aware — traced the same `moldBreakerActive` source
# set-site (battle_util.c L9799) confirming it's never active outside a
# move-processing window, which a switch-in trigger structurally isn't. The
# MOVE-based redirect (in `_phase_move_execution`), by contrast, IS Mold-Breaker-aware
# since it fires during real move resolution. `.breakable=TRUE`.
#
# Testing conventions applied throughout (CLAUDE.md):
#   - Signal-snapshot, not post-battle state.
#   - Lambda-captured scalars wrapped in single-element Arrays.
#   - Type immunity precedes ability logic: neutral Normal-vs-Normal matchups.
#   - Pairwise damage/accuracy statistical comparisons use wide margins (matching
#     `[M17n-5]`'s Super Luck precedent) since no deterministic accuracy-roll seam
#     exists in this codebase (only force_hit=true/false, which bypasses the roll
#     entirely and can't measure a rate).
#   - _force_hit = true on any non-accuracy-related mechanism probe.
#
# Ground truth: pokeemerald_expansion src/battle_util.c (Comatose's
#   CanSetNonVolatileStatus branch L5359-5361, BattlerHasCopyableChanges
#   L5964-5979, Wonder Skin's GetTotalAccuracy L10275-10276, moldBreakerActive
#   set-site L9799); src/battle_stat_change.c (IsMirrorArmorReflected L742-790);
#   src/data/abilities.h (all 4 ability data entries).

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_section_1_ability_data()
	_test_section_2_comatose()
	_test_section_3_costar_unit()
	_test_section_4_costar_full_battle()
	_test_section_5_wonder_skin()
	_test_section_6_mirror_armor_unit()
	_test_section_7_mirror_armor_full_battle()
	_test_section_8_mirror_armor_intimidate()
	_test_section_9_guard_dog_mirror_armor_independence()
	_test_section_10_mold_breaker_and_neutralizing_gas()
	_test_section_11_negative_control()

	var total := _pass + _fail
	print("m17n11_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL: " + label)


# ── Helpers ───────────────────────────────────────────────────────────────────

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


func _make_bm() -> BattleManager:
	var bm := BattleManager.new()
	add_child(bm)
	return bm


func _doubles_party(m0: BattlePokemon, m1: BattlePokemon) -> BattleParty:
	var p := BattleParty.new()
	p.members = [m0, m1]
	p.active_indices.append(1)
	return p


# ── Section 1: Ability data spot-checks ──────────────────────────────────────

func _test_section_1_ability_data() -> void:
	var comatose := _load_ability(213)
	_chk("S1.01 Comatose id=213, all five M17h exemption flags, NOT breakable",
			comatose.ability_id == 213 and comatose.cant_be_copied and comatose.cant_be_swapped
					and comatose.cant_be_traced and comatose.cant_be_suppressed
					and comatose.cant_be_overwritten and not comatose.breakable)

	var costar := _load_ability(294)
	_chk("S1.02 Costar id=294, not breakable, not cant_be_suppressed",
			costar.ability_id == 294 and not costar.breakable and not costar.cant_be_suppressed)

	var wonder_skin := _load_ability(147)
	_chk("S1.03 Wonder Skin id=147, IS breakable",
			wonder_skin.ability_id == 147 and wonder_skin.breakable == true)

	var mirror_armor := _load_ability(240)
	_chk("S1.04 Mirror Armor id=240, IS breakable",
			mirror_armor.ability_id == 240 and mirror_armor.breakable == true)


# ── Section 2: Comatose ───────────────────────────────────────────────────────

func _test_section_2_comatose() -> void:
	var comatose := _load_ability(213)

	var burn_mon := _make_mon("ComatoseBurn", [TypeChart.TYPE_NORMAL])
	burn_mon.ability = comatose
	_chk("S2.01 Comatose blocks BURN infliction",
			not StatusManager.try_apply_status(burn_mon, BattlePokemon.STATUS_BURN))

	var poison_mon := _make_mon("ComatosePoison", [TypeChart.TYPE_NORMAL])
	poison_mon.ability = comatose
	_chk("S2.02 Comatose blocks POISON infliction",
			not StatusManager.try_apply_status(poison_mon, BattlePokemon.STATUS_POISON))

	var para_mon := _make_mon("ComatosePara", [TypeChart.TYPE_NORMAL])
	para_mon.ability = comatose
	_chk("S2.03 Comatose blocks PARALYSIS infliction",
			not StatusManager.try_apply_status(para_mon, BattlePokemon.STATUS_PARALYSIS))

	var freeze_mon := _make_mon("ComatoseFreeze", [TypeChart.TYPE_NORMAL])
	freeze_mon.ability = comatose
	_chk("S2.04 Comatose blocks FREEZE infliction",
			not StatusManager.try_apply_status(freeze_mon, BattlePokemon.STATUS_FREEZE))

	var sleep_mon := _make_mon("ComatoseSleep", [TypeChart.TYPE_NORMAL])
	sleep_mon.ability = comatose
	_chk("S2.05 Comatose blocks SLEEP infliction too (it's never genuinely asleep)",
			not StatusManager.try_apply_status(sleep_mon, BattlePokemon.STATUS_SLEEP))

	var toxic_mon := _make_mon("ComatoseToxic", [TypeChart.TYPE_NORMAL])
	toxic_mon.ability = comatose
	_chk("S2.06 Comatose blocks TOXIC infliction",
			not StatusManager.try_apply_status(toxic_mon, BattlePokemon.STATUS_TOXIC))

	# Discriminator: a plain Pokémon is NOT immune.
	var plain_mon := _make_mon("ComatosePlain", [TypeChart.TYPE_NORMAL])
	_chk("S2.07 discriminator: a plain Pokémon CAN be poisoned",
			StatusManager.try_apply_status(plain_mon, BattlePokemon.STATUS_POISON))

	# Discriminator: Comatose does NOT block confusion (a volatile, not a
	# non-volatile status — confirmed absent from source's confusion-handling
	# function entirely).
	var confusion_mon := _make_mon("ComatoseConfusion", [TypeChart.TYPE_NORMAL])
	confusion_mon.ability = comatose
	_chk("S2.08 discriminator: Comatose does NOT block confusion (a separate, " +
			"volatile status)",
			StatusManager.try_apply_confusion(confusion_mon))


# ── Section 3: Costar — direct unit tests ────────────────────────────────────

func _test_section_3_costar_unit() -> void:
	var costar := _load_ability(294)

	# (i) Ally with real stat changes: full copy.
	var holder_i := _make_mon("CostarHolder1", [TypeChart.TYPE_NORMAL])
	holder_i.ability = costar
	var ally_i := _make_mon("CostarAlly1", [TypeChart.TYPE_NORMAL])
	ally_i.stat_stages[BattlePokemon.STAGE_ATK] = 2
	ally_i.stat_stages[BattlePokemon.STAGE_SPEED] = -1
	ally_i.focus_energy = true
	var copied_i: bool = AbilityManager.try_costar_copy(holder_i, ally_i)
	_chk("S3.01 Costar copy reports true when the ally has real changes", copied_i)
	_chk("S3.02 Costar copies the Attack stage exactly",
			holder_i.stat_stages[BattlePokemon.STAGE_ATK] == 2)
	_chk("S3.03 Costar copies the Speed stage exactly",
			holder_i.stat_stages[BattlePokemon.STAGE_SPEED] == -1)
	_chk("S3.04 Costar copies focus_energy", holder_i.focus_energy == true)

	# (ii) Ally with NOTHING to copy: confirmed no-op (not a reset).
	var holder_ii := _make_mon("CostarHolder2", [TypeChart.TYPE_NORMAL])
	holder_ii.ability = costar
	holder_ii.stat_stages[BattlePokemon.STAGE_DEF] = 3  # pre-existing own stage
	var ally_ii := _make_mon("CostarAlly2", [TypeChart.TYPE_NORMAL])
	var copied_ii: bool = AbilityManager.try_costar_copy(holder_ii, ally_ii)
	_chk("S3.05 Costar copy reports false when the ally has nothing copyable",
			not copied_ii)
	_chk("S3.06 the holder's own PRE-EXISTING stage is untouched by the no-op " +
			"(not reset to zero)", holder_ii.stat_stages[BattlePokemon.STAGE_DEF] == 3)

	# (iii) Singles: ally is null, guaranteed no-op, no crash.
	var holder_iii := _make_mon("CostarHolder3", [TypeChart.TYPE_NORMAL])
	holder_iii.ability = costar
	_chk("S3.07 Costar copy reports false with a null ally (singles), no crash",
			not AbilityManager.try_costar_copy(holder_iii, null))

	# Discriminator: a plain Pokémon never copies anything.
	var plain_holder := _make_mon("CostarPlain", [TypeChart.TYPE_NORMAL])
	var ally_plain := _make_mon("CostarAllyPlain", [TypeChart.TYPE_NORMAL])
	ally_plain.stat_stages[BattlePokemon.STAGE_ATK] = 3
	_chk("S3.08 discriminator: a non-Costar holder never copies",
			not AbilityManager.try_costar_copy(plain_holder, ally_plain))


# ── Section 4: Costar — full-battle doubles switch-in ────────────────────────

func _test_section_4_costar_full_battle() -> void:
	var costar := _load_ability(294)
	var tackle := _load_move(33)

	var holder := _make_mon("CostarBattleHolder", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 100)
	holder.ability = costar
	holder.add_move(tackle)
	var ally := _make_mon("CostarBattleAlly", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 20)
	ally.stat_stages[BattlePokemon.STAGE_ATK] = 1
	ally.add_move(tackle)
	var opp0 := _make_mon("CostarBattleOpp1", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 60)
	opp0.add_move(tackle)
	var opp1 := _make_mon("CostarBattleOpp2", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 60)
	opp1.add_move(tackle)

	var bm := _make_bm()
	var copy_events := []
	bm.stat_changes_copied.connect(func(user, from_mon): copy_events.append([user, from_mon]))
	bm.start_battle_doubles(_doubles_party(holder, ally), _doubles_party(opp0, opp1))

	_chk("S4.01 Costar's stat_changes_copied fires with the holder as user and the " +
			"ally as from_mon",
			copy_events.any(func(e): return e[0] == holder and e[1] == ally))
	bm.queue_free()


# ── Section 5: Wonder Skin — accuracy floor ──────────────────────────────────

func _test_section_5_wonder_skin() -> void:
	var wonder_skin := _load_ability(147)
	var mold_breaker := _load_ability(104)
	var growl := _load_move(45)  # status, accuracy=100
	var tackle := _load_move(33)  # damaging, accuracy=100

	var ws_holder := _make_mon("WonderSkinHolder", [TypeChart.TYPE_NORMAL])
	ws_holder.ability = wonder_skin
	var plain_defender := _make_mon("WonderSkinPlainDef", [TypeChart.TYPE_NORMAL])
	var attacker := _make_mon("WonderSkinAtk", [TypeChart.TYPE_NORMAL])

	var n := 2000
	var ws_hits := 0
	var plain_hits := 0
	var ws_damage_hits := 0
	for _i in range(n):
		if StatusManager.check_accuracy(attacker, ws_holder, growl):
			ws_hits += 1
		if StatusManager.check_accuracy(attacker, plain_defender, growl):
			plain_hits += 1
		if StatusManager.check_accuracy(attacker, ws_holder, tackle):
			ws_damage_hits += 1

	var ws_rate: float = float(ws_hits) / n
	var plain_rate: float = float(plain_hits) / n
	var ws_damage_rate: float = float(ws_damage_hits) / n
	_chk("S5.01 Wonder Skin floors Growl's (100%% acc status move) hit rate near " +
			"50%% (n=%d, observed=%.3f)" % [n, ws_rate],
			ws_rate > 0.42 and ws_rate < 0.58)
	_chk("S5.02 discriminator: a plain defender's Growl hit rate stays near 100%% " +
			"(n=%d, observed=%.3f)" % [n, plain_rate], plain_rate > 0.95)
	_chk("S5.03 discriminator: a DAMAGING move (Tackle) against the same Wonder " +
			"Skin holder is completely unaffected, staying near 100%% " +
			"(n=%d, observed=%.3f)" % [n, ws_damage_rate], ws_damage_rate > 0.95)

	# Discriminator: an already-≤50%-accuracy status move is NOT raised to 50% (its
	# own lower accuracy stands). No move in this project's roster has this shape —
	# a synthetic MoveData is used, matching the established precedent (`[M17n-5]`'s
	# Strong Jaw/Sharpness/Mega Launcher tests) for probing a mechanism the current
	# roster can't otherwise exercise.
	var low_acc_status := MoveData.new()
	low_acc_status.move_name = "TestLowAccStatus"
	low_acc_status.category = 2
	low_acc_status.accuracy = 30
	var low_acc_hits := 0
	for _i in range(n):
		if StatusManager.check_accuracy(attacker, ws_holder, low_acc_status):
			low_acc_hits += 1
	var low_acc_rate: float = float(low_acc_hits) / n
	_chk("S5.04 an already-30%%-accuracy status move is NOT raised to 50%% by " +
			"Wonder Skin (stays near 30%%, n=%d, observed=%.3f)" % [n, low_acc_rate],
			low_acc_rate > 0.24 and low_acc_rate < 0.36)

	# Mold Breaker bypass.
	var mb_attacker := _make_mon("WonderSkinMBAtk", [TypeChart.TYPE_NORMAL])
	mb_attacker.ability = mold_breaker
	var mb_hits := 0
	for _i in range(n):
		if StatusManager.check_accuracy(mb_attacker, ws_holder, growl):
			mb_hits += 1
	var mb_rate: float = float(mb_hits) / n
	_chk("S5.05 a Mold-Breaker attacker bypasses Wonder Skin entirely (Growl's hit " +
			"rate returns to near 100%%, n=%d, observed=%.3f)" % [n, mb_rate],
			mb_rate > 0.95)


# ── Section 6: Mirror Armor — direct unit tests ──────────────────────────────

func _test_section_6_mirror_armor_unit() -> void:
	var mirror_armor := _load_ability(240)
	var mold_breaker := _load_ability(104)

	var holder := _make_mon("MAUnitHolder1", [TypeChart.TYPE_NORMAL])
	holder.ability = mirror_armor
	var source := _make_mon("MAUnitSource1", [TypeChart.TYPE_NORMAL])
	_chk("S6.01 mirror_armor_reflects true for a Mirror Armor holder vs a distinct source",
			AbilityManager.mirror_armor_reflects(holder, source))

	_chk("S6.02 mirror_armor_reflects false when target == source (self-inflicted)",
			not AbilityManager.mirror_armor_reflects(holder, holder))

	var plain_target := _make_mon("MAUnitPlain", [TypeChart.TYPE_NORMAL])
	_chk("S6.03 mirror_armor_reflects false for a plain (non-Mirror-Armor) target",
			not AbilityManager.mirror_armor_reflects(plain_target, source))

	var mb_source := _make_mon("MAUnitMBSource", [TypeChart.TYPE_NORMAL])
	mb_source.ability = mold_breaker
	_chk("S6.04 mirror_armor_reflects false when source has Mold Breaker " +
			"(Mirror Armor IS breakable)",
			not AbilityManager.mirror_armor_reflects(holder, mb_source, false, mb_source))


# ── Section 7: Mirror Armor — full-battle move-based reflection ─────────────

func _test_section_7_mirror_armor_full_battle() -> void:
	var mirror_armor := _load_ability(240)
	var growl := _load_move(45)

	# (i) Growl against a Mirror Armor holder: the ATTACKER's own Attack drops
	# instead of the holder's.
	var atk_i := _make_mon("MABattleAtk1", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 100)
	atk_i.add_move(growl)
	var holder_i := _make_mon("MABattleHolder1", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 20)
	holder_i.ability = mirror_armor
	holder_i.add_move(_load_move(33))  # harmless Tackle, isolates to one Growl this turn

	var bm_i := _make_bm()
	bm_i._force_hit = true
	var stat_events_i := []
	var trig_events_i := []
	bm_i.stat_stage_changed.connect(func(t, s, a): stat_events_i.append([t, s, a]))
	bm_i.ability_triggered.connect(func(m, tag): trig_events_i.append([m, tag]))
	bm_i.start_battle(atk_i, holder_i)

	_chk("S7.01 the FIRST stat_stage_changed lands on the ORIGINAL ATTACKER, not " +
			"the Mirror Armor holder",
			not stat_events_i.is_empty() and stat_events_i[0][0] == atk_i
					and stat_events_i[0][1] == BattlePokemon.STAGE_ATK and stat_events_i[0][2] == -1)
	_chk("S7.02 the Mirror Armor holder's own Attack is never lowered",
			not stat_events_i.any(func(e): return e[0] == holder_i))
	_chk("S7.03 ability_triggered fires with the mirror_armor tag on the holder",
			trig_events_i.any(func(e): return e[0] == holder_i and e[1] == "mirror_armor"))
	bm_i.queue_free()

	# (ii) Discriminator: a plain defender's Growl lowers ITS OWN Attack as normal.
	var atk_ii := _make_mon("MABattleAtk2", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 100)
	atk_ii.add_move(growl)
	var plain_def_ii := _make_mon("MABattlePlainDef2", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 20)
	plain_def_ii.add_move(_load_move(33))

	var bm_ii := _make_bm()
	bm_ii._force_hit = true
	var stat_events_ii := []
	bm_ii.stat_stage_changed.connect(func(t, s, a): stat_events_ii.append([t, s, a]))
	bm_ii.start_battle(atk_ii, plain_def_ii)

	_chk("S7.04 discriminator: a plain defender's Attack DROPS from Growl as normal",
			not stat_events_ii.is_empty() and stat_events_ii[0][0] == plain_def_ii)
	bm_ii.queue_free()

	# (iii) Self-inflicted drop is NOT reflected: a synthetic self-lowering move
	# used by the Mirror Armor holder itself just applies to the holder normally.
	# No move in this project's roster self-lowers a stat (confirmed via grep), so a
	# synthetic MoveData is used, matching this session's Wonder Skin precedent.
	var self_lower := MoveData.new()
	self_lower.move_name = "TestSelfLower"
	self_lower.category = 2
	self_lower.accuracy = 0  # always hits
	self_lower.stat_change_stat = BattlePokemon.STAGE_SPATK
	self_lower.stat_change_amount = -2
	self_lower.stat_change_self = true

	var holder_iii := _make_mon("MABattleHolder3", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 100)
	holder_iii.ability = mirror_armor
	holder_iii.add_move(self_lower)
	var opp_iii := _make_mon("MABattleOpp3", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 20)
	opp_iii.add_move(_load_move(33))

	var bm_iii := _make_bm()
	var stat_events_iii := []
	bm_iii.stat_stage_changed.connect(func(t, s, a): stat_events_iii.append([t, s, a]))
	bm_iii.start_battle(holder_iii, opp_iii)

	_chk("S7.05 a self-inflicted stat drop on the Mirror Armor holder itself is " +
			"NOT reflected — it applies to the holder normally",
			stat_events_iii.any(func(e): return e[0] == holder_iii and e[1] == BattlePokemon.STAGE_SPATK and e[2] == -2))
	_chk("S7.06 the opponent's Sp. Atk is never touched by the holder's own " +
			"self-inflicted drop", not stat_events_iii.any(func(e): return e[0] == opp_iii))
	bm_iii.queue_free()


# ── Section 8: Mirror Armor — Intimidate-specific full-battle test ──────────

func _test_section_8_mirror_armor_intimidate() -> void:
	var mirror_armor := _load_ability(240)
	var intimidate := _load_ability(22)
	var tackle := _load_move(33)

	var intim_holder := _make_mon("MAIntimAtk", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 100)
	intim_holder.ability = intimidate
	intim_holder.add_move(tackle)
	var ma_holder := _make_mon("MAIntimDef", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 20)
	ma_holder.ability = mirror_armor
	ma_holder.add_move(tackle)

	var bm := _make_bm()
	var stat_events := []
	var trig_events := []
	bm.stat_stage_changed.connect(func(t, s, a): stat_events.append([t, s, a]))
	bm.ability_triggered.connect(func(m, tag): trig_events.append([m, tag]))
	bm.start_battle(intim_holder, ma_holder)

	_chk("S8.01 Intimidate's drop reflects onto the SWITCHING-IN Intimidate holder's " +
			"own Attack, not the Mirror Armor holder's",
			stat_events.any(func(e): return e[0] == intim_holder and e[1] == BattlePokemon.STAGE_ATK and e[2] == -1))
	_chk("S8.02 the Mirror Armor holder's own Attack is never lowered by its own " +
			"Intimidate reflection", not stat_events.any(func(e): return e[0] == ma_holder))
	_chk("S8.03 ability_triggered fires the mirror_armor tag on the Mirror Armor holder",
			trig_events.any(func(e): return e[0] == ma_holder and e[1] == "mirror_armor"))
	bm.queue_free()


# ── Section 9: Guard Dog / Mirror Armor architectural independence (doubles) ─

func _test_section_9_guard_dog_mirror_armor_independence() -> void:
	var guard_dog := _load_ability(275)
	var mirror_armor := _load_ability(240)
	var intimidate := _load_ability(22)
	var tackle := _load_move(33)

	# One opposing slot holds Guard Dog, the other holds Mirror Armor. A single
	# Intimidate switch-in should trigger BOTH independently: Guard Dog raises its
	# own holder's Attack; Mirror Armor reflects onto the Intimidate switcher's
	# Attack. Confirms the two mechanisms don't conflict or double-fire.
	var intim_mon := _make_mon("GDMAIntim", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 100)
	intim_mon.ability = intimidate
	intim_mon.add_move(tackle)
	var intim_ally := _make_mon("GDMAIntimAlly", [TypeChart.TYPE_NORMAL], 100, 60, 60, 60, 60, 20)
	intim_ally.add_move(tackle)
	var gd_opp := _make_mon("GDMAGuardDogOpp", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 60)
	gd_opp.ability = guard_dog
	gd_opp.add_move(tackle)
	var ma_opp := _make_mon("GDMAMirrorArmorOpp", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 60)
	ma_opp.ability = mirror_armor
	ma_opp.add_move(tackle)

	var bm := _make_bm()
	var stat_events := []
	bm.stat_stage_changed.connect(func(t, s, a): stat_events.append([t, s, a]))
	bm.start_battle_doubles(_doubles_party(intim_mon, intim_ally), _doubles_party(gd_opp, ma_opp))

	_chk("S9.01 Guard Dog's holder gets its own +1 Attack raise",
			stat_events.any(func(e): return e[0] == gd_opp and e[1] == BattlePokemon.STAGE_ATK and e[2] == 1))
	_chk("S9.02 Mirror Armor's holder never has its own Attack lowered",
			not stat_events.any(func(e): return e[0] == ma_opp))
	_chk("S9.03 the Intimidate switcher's Attack drops exactly ONCE (from Mirror " +
			"Armor's reflection), not twice",
			stat_events.filter(func(e): return e[0] == intim_mon and e[1] == BattlePokemon.STAGE_ATK and e[2] == -1).size() == 1)
	bm.queue_free()


# ── Section 10: Mold Breaker / Neutralizing Gas suppression matrix ──────────

func _test_section_10_mold_breaker_and_neutralizing_gas() -> void:
	# Comatose: NOT breakable, but cant_be_suppressed=true — confirm both halves.
	var comatose := _load_ability(213)
	var mold_breaker := _load_ability(104)
	var co_mon := _make_mon("NGComatose", [TypeChart.TYPE_NORMAL])
	co_mon.ability = comatose
	var mb_attacker := _make_mon("NGComatoseMBAtk", [TypeChart.TYPE_NORMAL])
	mb_attacker.ability = mold_breaker
	_chk("S10.01 Comatose is NOT bypassed by Mold Breaker (not breakable) — status " +
			"immunity still holds",
			not StatusManager.try_apply_status(co_mon, BattlePokemon.STATUS_BURN, null, null, false, mb_attacker))
	_chk("S10.02 Comatose is NOT suppressed by Neutralizing Gas (cant_be_suppressed) " +
			"— status immunity still holds",
			not StatusManager.try_apply_status(co_mon, BattlePokemon.STATUS_BURN, null, null, true))

	# Costar: no breakable/cant_be_suppressed flags — suppressible by NG.
	var costar := _load_ability(294)
	var co_holder := _make_mon("NGCostar", [TypeChart.TYPE_NORMAL])
	co_holder.ability = costar
	var co_ally := _make_mon("NGCostarAlly", [TypeChart.TYPE_NORMAL])
	co_ally.stat_stages[BattlePokemon.STAGE_ATK] = 2
	_chk("S10.03 Costar suppressed by Neutralizing Gas: try_costar_copy false",
			not AbilityManager.try_costar_copy(co_holder, co_ally, true))

	# Wonder Skin: breakable, suppressible by NG (generic).
	var wonder_skin := _load_ability(147)
	var ws_mon := _make_mon("NGWonderSkin", [TypeChart.TYPE_NORMAL])
	ws_mon.ability = wonder_skin
	_chk("S10.04 Wonder Skin suppressed by Neutralizing Gas",
			AbilityManager.effective_ability_id(ws_mon, true) != AbilityManager.ABILITY_WONDER_SKIN)

	# Mirror Armor: breakable, suppressible by NG (generic).
	var mirror_armor := _load_ability(240)
	var ma_mon := _make_mon("NGMirrorArmor", [TypeChart.TYPE_NORMAL])
	ma_mon.ability = mirror_armor
	var some_source := _make_mon("NGMirrorArmorSource", [TypeChart.TYPE_NORMAL])
	_chk("S10.05 Mirror Armor suppressed by Neutralizing Gas: mirror_armor_reflects false",
			not AbilityManager.mirror_armor_reflects(ma_mon, some_source, true))


# ── Section 11: Negative control ─────────────────────────────────────────────

func _test_section_11_negative_control() -> void:
	var plain_atk := _make_mon("NegCtrlAtk11", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 100)
	plain_atk.add_move(_load_move(45))  # Growl
	var plain_def := _make_mon("NegCtrlDef11", [TypeChart.TYPE_NORMAL], 100, 80, 60, 60, 60, 20)
	plain_def.add_move(_load_move(33))

	var bm := _make_bm()
	bm._force_hit = true
	var stat_events := []
	bm.stat_stage_changed.connect(func(t, s, a): stat_events.append([t, s, a]))
	bm.start_battle(plain_atk, plain_def)

	_chk("S11.01 two plain Pokémon: Growl lowers the DEFENDER's Attack as normal",
			not stat_events.is_empty() and stat_events[0][0] == plain_def
					and stat_events[0][2] == -1)
	bm.queue_free()

	_chk("S11.02 try_apply_status not blocked for a plain Pokémon with no ability",
			StatusManager.try_apply_status(_make_mon("NegCtrlPlain1", [TypeChart.TYPE_NORMAL]),
					BattlePokemon.STATUS_POISON))
	_chk("S11.03 try_costar_copy false for a plain Pokémon",
			not AbilityManager.try_costar_copy(
					_make_mon("NegCtrlPlain2", [TypeChart.TYPE_NORMAL]),
					_make_mon("NegCtrlPlain3", [TypeChart.TYPE_NORMAL])))
	_chk("S11.04 mirror_armor_reflects false for a plain Pokémon",
			not AbilityManager.mirror_armor_reflects(
					_make_mon("NegCtrlPlain4", [TypeChart.TYPE_NORMAL]),
					_make_mon("NegCtrlPlain5", [TypeChart.TYPE_NORMAL])))
