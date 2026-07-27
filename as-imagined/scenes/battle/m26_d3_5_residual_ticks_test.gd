extends Node

# [M26D3-5] Regression suite for residual damage/heal tick narration:
# Curse, Nightmare, Leech Seed, the Bind/Wrap family, Aqua Ring/Ingrain, and
# the three PP signals (Grudge, Spite, Leppa Berry).
#
# These fire EVERY turn while their volatile is up, which makes them the group
# most likely to affect turn length — see docs/m26_d3_recon.md §7(3).
#
# Two load-bearing assertions:
#   D.01 — `passive_hp_lost` must stay SILENT. Source prints ONE combined line
#          for Belly Drum's cost AND effect, and this project already narrates
#          the effect, so a separate HP line would both invent text and
#          double-report one event.
#   C.01 — Aqua Ring and Ingrain share a signal but NOT a line; the holder's
#          own flags must disambiguate them.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_simple_ticks()
	_test_wrap_family()
	_test_ring_disambiguation()
	_test_pp_signals()
	_test_passive_hp_loss_stays_silent()

	var total := _pass + _fail
	print("m26_d3_5_residual_ticks_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


func _make_mon(mon_name: String) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types = [TypeChart.TYPE_NORMAL]
	sp.base_hp = 300
	sp.base_attack = 60
	sp.base_defense = 60
	sp.base_sp_attack = 60
	sp.base_sp_defense = 60
	sp.base_speed = 60
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])


func _make_bm() -> BattleManager:
	var bm := BattleManager.new()
	add_child(bm)
	return bm


func _make_bs(bm: BattleManager) -> BattleScreenShared:
	var bs := BattleScreenShared.new()
	var pp := BattleParty.new()
	pp.active_indices = []
	bs._player_party = pp
	bs._opp_party = BattleParty.new()
	bs._opp_party.active_indices = []
	bs._bm = bm
	bs._wire_log_signals()
	return bs


func _narrative(bs: BattleScreenShared) -> String:
	var out := ""
	for entry: Dictionary in bs._debug_entries:
		if entry["category"] == BattleScreenShared.DebugCategory.NARRATIVE:
			out += str(entry["text"]) + "\n"
	return out.strip_edges()


# ── A/B. Simple ticks ────────────────────────────────────────────────────

func _test_simple_ticks() -> void:
	var cases := [
		["curse_damage", "afflicted by the curse!"],
		["nightmare_damage", "locked in a nightmare!"],
	]
	for c: Array in cases:
		var bm := _make_bm()
		var bs := _make_bs(bm)
		bm.emit_signal(c[0], _make_mon("Sufferer"), 25)
		_chk("A.01 %s is narrated" % c[0], c[1] in _narrative(bs))
		bs.free()
		bm.queue_free()

	var bm2 := _make_bm()
	var bs2 := _make_bs(bm2)
	bm2.leech_seed_drained.emit(_make_mon("Seeded"), _make_mon("Seeder"), 20)
	var line := _narrative(bs2)
	_chk("A.02 Leech Seed names the drained mon, not the beneficiary",
			"Seeded" in line and "sapped by Leech Seed!" in line)
	_chk("A.02b ...and does not name the source", not ("Seeder" in line))
	bs2.free()
	bm2.queue_free()


func _test_wrap_family() -> void:
	var bm := _make_bm()
	var bs := _make_bs(bm)
	bm.wrap_damage.emit(_make_mon("Bound"), 15)
	_chk("B.01 the binding tick is narrated", "is hurt by the attack!" in _narrative(bs))
	bs.free()
	bm.queue_free()

	var bm2 := _make_bm()
	var bs2 := _make_bs(bm2)
	bm2.wrap_ended.emit(_make_mon("Bound"))
	_chk("B.02 breaking free is narrated", "was freed!" in _narrative(bs2))
	bs2.free()
	bm2.queue_free()


# ── C. Aqua Ring vs Ingrain ──────────────────────────────────────────────

# One signal, two DIFFERENT source lines. Ingrain is checked first because a
# mon can legitimately have both active.
func _test_ring_disambiguation() -> void:
	var ing := _make_mon("Rooted")
	ing.ingrain_active = true
	var bm := _make_bm()
	var bs := _make_bs(bm)
	bm.ring_heal_tick.emit(ing, 20)
	_chk("C.01 Ingrain uses its own line",
			"absorbed nutrients with its roots!" in _narrative(bs))
	bs.free()
	bm.queue_free()

	var aqua := _make_mon("Watery")
	aqua.aqua_ring_active = true
	var bm2 := _make_bm()
	var bs2 := _make_bs(bm2)
	bm2.ring_heal_tick.emit(aqua, 20)
	_chk("C.02 Aqua Ring uses its own, different line",
			"veil of water restored" in _narrative(bs2))
	bs2.free()
	bm2.queue_free()

	var both := _make_mon("BothRings")
	both.ingrain_active = true
	both.aqua_ring_active = true
	var bm3 := _make_bm()
	var bs3 := _make_bs(bm3)
	bm3.ring_heal_tick.emit(both, 20)
	_chk("C.03 with both active, Ingrain wins (documented precedence)",
			"absorbed nutrients" in _narrative(bs3))
	bs3.free()
	bm3.queue_free()


# ── D. PP signals ────────────────────────────────────────────────────────

func _test_pp_signals() -> void:
	var move := MoveData.new()
	move.move_name = "Tackle"

	var bm := _make_bm()
	var bs := _make_bs(bm)
	bm.pp_drained.emit(_make_mon("Killer"), move)
	_chk("D.01 Grudge's PP drain names the move",
			"lost all of Tackle's PP due to the grudge!" in _narrative(bs))
	bs.free()
	bm.queue_free()

	var bm2 := _make_bm()
	var bs2 := _make_bs(bm2)
	bm2.pp_reduced.emit(_make_mon("Spited"), move, 4)
	_chk("D.02 Spite reports the amount and the move",
			"lost 4 PP from Tackle!" in _narrative(bs2))
	bs2.free()
	bm2.queue_free()

	var bm3 := _make_bm()
	var bs3 := _make_bs(bm3)
	bm3.pp_restored.emit(_make_mon("Leppa"), 0, 10)
	_chk("D.03 Leppa Berry's restore is narrated",
			"restored PP to its move!" in _narrative(bs3))
	bs3.free()
	bm3.queue_free()


# THE assertion. Source prints ONE combined line for Belly Drum's HP cost AND
# its effect ("cut its own HP and maximized its Attack!"), and this project
# already narrates the effect half via stat_stage_changed. A standalone
# "lost HP" line would invent text AND double-report one event.
func _test_passive_hp_loss_stays_silent() -> void:
	var bm := _make_bm()
	var bs := _make_bs(bm)
	bm.passive_hp_lost.emit(_make_mon("Drummer"), 150)
	_chk("D.04 an HP cost stays SILENT — the effect line already covers it",
			_narrative(bs) == "")
	bs.free()
	bm.queue_free()
