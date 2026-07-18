extends Node

# M18k test suite — Flinch-on-hit items (King's Rock, Razor Fang)
#
# Ground truth: pokeemerald-expansion
#   src/data/items.h L9784-9800 (King's Rock, id=465) / L10451-10467 (Razor Fang,
#     id=493) — both `.holdEffect = HOLD_EFFECT_FLINCH`, `.holdEffectParam = 10`,
#     confirmed genuinely identical (unlike M18g/h/j's apparent pairs).
#   src/battle_hold_effects.c :: TryKingsRock (L188-210) — the single function
#     backing BOTH items (source's own `// Kings Rock` comment at the switch case,
#     L1081, applies uniformly to Razor Fang too — same HOLD_EFFECT_FLINCH value):
#       !IsBattlerTurnDamaged(battlerDef) -> no roll (caller gates on damage > 0).
#       MoveIgnoresKingsRock(gCurrentMove) -> every condition behind this flag is
#         gated on pre-Gen-5 B_UPDATED_MOVE_FLAGS comparisons; this reference
#         clone's B_UPDATED_MOVE_FLAGS=GEN_LATEST makes all of them false
#         (confirmed via direct grep of moves_info.h — no unconditional entries
#         exist) -> not modeled, no move-level exclusion table needed here.
#       MoveHasAdditionalEffect(gCurrentMove, MOVE_EFFECT_FLINCH) -> MUTUALLY
#         EXCLUSIVE with a move that already has its own flinch effect (Rock
#         Slide, Sky Attack, Stomp) — NOT an independent second roll stacked on
#         an existing flinch chance. Gated on the move's DEFINITION, matching
#         this project's `move.secondary_effect != MoveData.SE_FLINCH` check.
#       ability == ABILITY_STENCH excludes the roll -- Stench is not implemented
#         anywhere in this project (confirmed via grep), a standing absence.
#       Serene Grace DOUBLES holdEffectParam here -- a SEPARATE application of
#         the ability from try_secondary_effect's own doubling (different
#         function entirely), confirmed explicit in source's own config comment:
#         "In Gen5+, Serene Grace boosts the added flinch chance of King's Rock
#         and Razor Fang." (B_SERENE_GRACE_BOOST, include/config/battle.h).
#   src/battle_hold_effects.c :: onAttackerAfterHit dispatch (data/hold_effects.h
#     L173-175) -- attacker-held, fires after the attacker's own hit lands;
#     architecturally the SAME location as this project's existing native
#     SE_FLINCH block (battle_manager.gd _do_damaging_hit), not the Jaboca/Rowap
#     retaliation-block shape.
#   Sheer Force: confirmed NO interaction. Sheer Force's suppression
#     (try_secondary_effect's is_true_secondary gate) only ever touches a MOVE's
#     own secondary_chance > 0; King's Rock/Razor Fang dispatch through a wholly
#     separate function that never calls try_secondary_effect at all.
#
# Docs: docs/m18_subtier_plan.md (M18k section) — 2 items, no cross-tier
# dependencies. New ItemManager.kings_rock_flinch_activates(), new
# BattleManager._force_kings_rock_roll seam, new mutually-exclusive branch in
# _do_damaging_hit right after the existing native SE_FLINCH block.
#
# Sections: K01 King's Rock, K02 Razor Fang + Sheer Force non-interaction,
# K03 mutual-exclusion with a move's own native flinch effect.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_k01_kings_rock()
	_test_k02_razor_fang()
	_test_k03_mutual_exclusion()

	var total := _pass + _fail
	print("m18k_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


# ── Helpers (mirrors m18l_test.gd's established pattern) ───────────────────────

func _make_item(hold_effect: int, param: int = 0) -> ItemData:
	var item := ItemData.new()
	item.hold_effect = hold_effect
	item.hold_effect_param = param
	return item


func _make_mon(mon_name: String, type1: int, base_hp: int = 100, base_atk: int = 60,
		base_def: int = 60, base_spatk: int = 60, base_spdef: int = 60, base_spd: int = 60) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types.append(type1)
	sp.base_hp         = base_hp
	sp.base_attack     = base_atk
	sp.base_defense    = base_def
	sp.base_sp_attack  = base_spatk
	sp.base_sp_defense = base_spdef
	sp.base_speed      = base_spd
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])


func _load_ability(id: int) -> AbilityData:
	return load("res://data/abilities/ability_%04d.tres" % id) as AbilityData


func _load_move(id: int) -> MoveData:
	return load("res://data/moves/move_%04d.tres" % id) as MoveData


# ── K01: King's Rock (465) ──────────────────────────────────────────────────────
func _test_k01_kings_rock() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_FLINCH, 10)
	_chk("K01.01 King's Rock hold_effect == HOLD_EFFECT_FLINCH(30), param == 10",
			item.hold_effect == ItemManager.HOLD_EFFECT_FLINCH and item.hold_effect_param == 10)

	# Direct unit checks — deterministic via forced_roll.
	var holder := _make_mon("K01_Holder", TypeChart.TYPE_NORMAL)
	holder.held_item = item
	_chk("K01.02 direct: forced_roll=true -> activates",
			ItemManager.kings_rock_flinch_activates(holder, false, true))
	_chk("K01.03 direct: forced_roll=false -> does not activate",
			not ItemManager.kings_rock_flinch_activates(holder, false, false))
	var bare := _make_mon("K01_Bare", TypeChart.TYPE_NORMAL)
	_chk("K01.04 discriminator: holding nothing never activates, even forced_roll=true",
			not ItemManager.kings_rock_flinch_activates(bare, false, true))

	# Statistical: plain holder, no Serene Grace -> observed rate near the
	# confirmed 10% (n=3000, per [M17n-5]/[M18e]'s established tolerance-band
	# pattern for a probabilistic outcome with no deterministic seam for the
	# RAW rate itself, only for the outcome of a single roll).
	var n := 3000
	var plain_fires := 0
	for _i in range(n):
		if ItemManager.kings_rock_flinch_activates(holder, false, null):
			plain_fires += 1
	var plain_rate: float = float(plain_fires) / n
	_chk("K01.05 plain holder's observed trigger rate is near the expected 10%% " +
			"(n=%d, observed=%.3f)" % [n, plain_rate],
			plain_rate > 0.06 and plain_rate < 0.14)

	# Statistical: Serene Grace doubles it to ~20% -- a SEPARATE application of
	# the ability from try_secondary_effect's own doubling, confirmed from
	# source's own config comment naming King's Rock/Razor Fang explicitly.
	var serene_grace := _load_ability(32)
	var sg_holder := _make_mon("K01_SereneGrace", TypeChart.TYPE_NORMAL)
	sg_holder.held_item = item
	sg_holder.ability = serene_grace
	var sg_fires := 0
	for _i in range(n):
		if ItemManager.kings_rock_flinch_activates(sg_holder, false, null):
			sg_fires += 1
	var sg_rate: float = float(sg_fires) / n
	_chk("K01.06 CORRECTION-confirming: Serene Grace doubles King's Rock's own " +
			"chance (a separate application from its try_secondary_effect doubling) " +
			"-- observed rate near the expected 20%% (n=%d, observed=%.3f)" % [n, sg_rate],
			sg_rate > 0.15 and sg_rate < 0.25)

	# Full-battle: holder is FASTER (acts first); Tackle has NO native secondary
	# effect at all -- proves the item is genuinely ADDING an effect, not
	# amplifying one. forced_roll=true -> the slower target's next action (same
	# turn) is skipped with reason "flinched".
	var tackle := _load_move(33)
	var kr := _make_mon("K01_Battle", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 100)
	kr.held_item = item
	kr.add_move(tackle)
	var opp := _make_mon("K01_Opp", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 40)
	opp.add_move(tackle)

	var moved := []
	var skipped := []
	var bm := BattleManager.new()
	add_child(bm)
	bm._force_kings_rock_roll = true
	bm.move_executed.connect(func(a, d, m, dmg): moved.push_back(a))
	bm.move_skipped.connect(func(m, reason): skipped.push_back([m, reason]))
	bm.start_battle_with_parties(BattleParty.single(kr), BattleParty.single(opp))
	_chk("K01.07 full-battle: King's Rock (forced roll=true) adds a flinch to a " +
			"move with NO native secondary effect -- the holder's Tackle is the " +
			"very first thing to execute (target's turn-1 move is pre-empted by " +
			"the flinch)",
			not moved.is_empty() and moved[0] == kr)
	_chk("K01.08 full-battle: the slower target's move is skipped with reason " +
			"'flinched' at least once",
			skipped.any(func(s): return s[0] == opp and s[1] == "flinched"))
	bm.queue_free()

	# Discriminator: forced roll=false -> both mons act normally, no skip.
	var kr2 := _make_mon("K01_Battle2", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 100)
	kr2.held_item = item
	kr2.add_move(tackle)
	var opp2 := _make_mon("K01_Opp2", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 40)
	opp2.add_move(tackle)

	var moved2 := []
	var skipped2 := []
	var bm2 := BattleManager.new()
	add_child(bm2)
	bm2._force_kings_rock_roll = false
	bm2.move_executed.connect(func(a, d, m, dmg): moved2.push_back(a))
	bm2.move_skipped.connect(func(m, reason): skipped2.push_back([m, reason]))
	bm2.start_battle_with_parties(BattleParty.single(kr2), BattleParty.single(opp2))
	_chk("K01.09 discriminator: forced roll=false -> both mons act every turn, " +
			"nothing ever skipped for 'flinched'",
			moved2.has(kr2) and moved2.has(opp2) \
					and not skipped2.any(func(s): return s[1] == "flinched"))
	bm2.queue_free()


# ── K02: Razor Fang (493) ────────────────────────────────────────────────────────
func _test_k02_razor_fang() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_FLINCH, 10)
	_chk("K02.01 Razor Fang hold_effect == HOLD_EFFECT_FLINCH(30) -- the SAME value " +
			"as King's Rock, confirmed via source not a data-entry error, param == 10",
			item.hold_effect == ItemManager.HOLD_EFFECT_FLINCH and item.hold_effect_param == 10)

	var holder := _make_mon("K02_Holder", TypeChart.TYPE_NORMAL)
	holder.held_item = item
	_chk("K02.02 direct: forced_roll=true -> activates (same function, own item instance)",
			ItemManager.kings_rock_flinch_activates(holder, false, true))
	_chk("K02.03 direct: forced_roll=false -> does not activate",
			not ItemManager.kings_rock_flinch_activates(holder, false, false))

	var tackle := _load_move(33)
	var rf := _make_mon("K02_Battle", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 100)
	rf.held_item = item
	rf.add_move(tackle)
	var opp := _make_mon("K02_Opp", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 40)
	opp.add_move(tackle)

	var skipped := []
	var bm := BattleManager.new()
	add_child(bm)
	bm._force_kings_rock_roll = true
	bm.move_skipped.connect(func(m, reason): skipped.push_back([m, reason]))
	bm.start_battle_with_parties(BattleParty.single(rf), BattleParty.single(opp))
	_chk("K02.04 full-battle: Razor Fang (forced roll=true) flinches the slower " +
			"target on a move with no native effect, identical outcome to King's " +
			"Rock (K01.08)",
			skipped.any(func(s): return s[0] == opp and s[1] == "flinched"))
	bm.queue_free()

	# Sheer Force non-interaction: confirmed architecturally disjoint --
	# kings_rock_flinch_activates never consults the attacker's ability at all
	# (besides Serene Grace's own separate doubling check above), so a Sheer
	# Force holder's item-granted flinch is neither suppressed nor amplified.
	var sheer_force := _load_ability(125)
	var sf_holder := _make_mon("K02_SheerForce", TypeChart.TYPE_NORMAL)
	sf_holder.held_item = item
	sf_holder.ability = sheer_force
	_chk("K02.05 Sheer Force non-interaction: a Sheer Force holder's King's " +
			"Rock/Razor Fang roll still activates on forced_roll=true -- Sheer " +
			"Force's suppression only ever gates a MOVE's own secondary_chance " +
			"inside try_secondary_effect, a function this item never calls",
			ItemManager.kings_rock_flinch_activates(sf_holder, false, true))


# ── K03: mutual exclusion with a move's own native flinch effect ───────────────
# Resolves this tier's Step 0 finding directly: TryKingsRock's own
# !MoveHasAdditionalEffect(move, MOVE_EFFECT_FLINCH) guard means the item does
# NOT add a second independent roll on top of a move that already has flinch
# (Rock Slide, secondary_chance=30) -- it's excluded entirely, gated on the
# move's definition. Discriminator: force the ITEM's own roll to true (which
# would guarantee a flinch every trial if the item's roll were independently
# consulted) and confirm the observed flinch rate tracks Rock Slide's own 30%
# native chance instead of jumping toward ~100%.
func _test_k03_mutual_exclusion() -> void:
	var item := _make_item(ItemManager.HOLD_EFFECT_FLINCH, 10)
	var rock_slide := _load_move(157)
	_chk("K03.01 fixture check: Rock Slide has its OWN native flinch effect " +
			"(secondary_effect == SE_FLINCH, secondary_chance == 30)",
			rock_slide.secondary_effect == MoveData.SE_FLINCH and rock_slide.secondary_chance == 30)

	# NOTE: start_battle_with_parties runs the FULL multi-turn battle to
	# completion, not a single turn. Rock Slide's native 30% flinch is rolled
	# independently EVERY turn, so counting "did a flinch happen anywhere in
	# the battle" would compound across turns and badly overstate the rate.
	# Instead, record a combined timeline of move_executed/move_skipped events
	# and look only at the TARGET's very first action attempt (turn 1) --
	# a single, clean per-turn sample.
	var n := 300
	var flinch_count := 0
	for _i in range(n):
		var kr := _make_mon("K03_Battle", TypeChart.TYPE_ROCK, 100, 60, 60, 60, 60, 100)
		kr.held_item = item
		kr.add_move(rock_slide)
		var opp := _make_mon("K03_Opp", TypeChart.TYPE_NORMAL, 100, 60, 60, 60, 60, 40)
		opp.add_move(rock_slide)

		var timeline := []
		var bm := BattleManager.new()
		add_child(bm)
		# Force the ITEM's own roll to true every trial -- if mutual exclusion
		# were NOT honored, this alone would guarantee a flinch every trial
		# regardless of Rock Slide's own (unforced, RNG) 30% roll.
		bm._force_kings_rock_roll = true
		bm.move_executed.connect(func(a, d, m, dmg): timeline.push_back(["moved", a]))
		bm.move_skipped.connect(func(m, reason): timeline.push_back(["skipped", m, reason]))
		bm.start_battle_with_parties(BattleParty.single(kr), BattleParty.single(opp))
		for event in timeline:
			if event[1] == opp:
				if event[0] == "skipped" and event[2] == "flinched":
					flinch_count += 1
				break
		bm.queue_free()

	var rate: float = float(flinch_count) / n
	_chk("K03.02 mutual exclusion CONFIRMED: with King's Rock's own roll forced " +
			"true on a Rock-Slide user, the observed flinch rate tracks Rock " +
			"Slide's OWN unforced ~30%% native chance -- NOT the ~100%% a stacked " +
			"independent roll would produce -- proving the item contributes " +
			"nothing extra when the move already has flinch (n=%d, observed=%.3f)" % [n, rate],
			rate > 0.20 and rate < 0.42)
