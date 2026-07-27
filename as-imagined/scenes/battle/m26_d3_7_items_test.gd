extends Node

# [M26D3-7] Regression suite for item-interaction narration. Nine signals, all
# previously DEBUG-ONLY — so stealing, swapping, Recycle, Harvest, Air Balloon
# popping and Focus Sash surviving all happened with no text in normal play.
#
# The load-bearing assertion is S.01: `item_consumed` must stay SILENT. It
# fires for every one-use item, but this project already narrates each
# consumption's own EFFECT (item_healed and status_cured are both log-wired,
# stat-raise berries surface via stat_stage_changed), and source prints ONE
# combined line per berry rather than an effect line plus a "used up" line.
# Wiring it would double-report every berry.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_steal_and_swap()
	_test_transfer_recycle_harvest()
	_test_item_damage()
	_test_item_effect_keys()
	_test_unknown_effect_key_stays_silent()
	_test_item_consumed_stays_silent()

	var total := _pass + _fail
	print("m26_d3_7_items_test: %d/%d passed" % [_pass, total])
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


func _make_item(item_name: String) -> ItemData:
	var it := ItemData.new()
	it.item_name = item_name
	return it


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


# ── A. Steal / swap ──────────────────────────────────────────────────────

func _test_steal_and_swap() -> void:
	var bm := _make_bm()
	var bs := _make_bs(bm)
	bm.item_stolen.emit(_make_mon("Thief"), _make_mon("Victim"))
	var line := _narrative(bs)
	_chk("A.01 a steal names both battlers",
			"Thief" in line and "Victim" in line and "stole" in line)
	bs.free()
	bm.queue_free()

	var bm2 := _make_bm()
	var bs2 := _make_bs(bm2)
	bm2.items_swapped.emit(_make_mon("Tricker"), _make_mon("Target"))
	_chk("A.02 Trick/Switcheroo is narrated",
			"switched items with its target!" in _narrative(bs2))
	bs2.free()
	bm2.queue_free()

	# Pluck/Bug Bite is consumed IN PLACE, not transferred — which is exactly
	# why source gives it its own line rather than reusing the steal one.
	var bm3 := _make_bm()
	var bs3 := _make_bs(bm3)
	bm3.berry_stolen_and_eaten.emit(_make_mon("Owner"), _make_mon("Plucker"),
			_make_item("Sitrus Berry"))
	var l3 := _narrative(bs3)
	_chk("A.03 Pluck names the eater and the berry",
			"Plucker" in l3 and "Sitrus Berry" in l3 and "stole and ate" in l3)
	_chk("A.03b ...and is worded differently from a plain steal",
			not ("switched items" in l3))
	bs3.free()
	bm3.queue_free()


# ── B. Transfer / Recycle / Harvest ──────────────────────────────────────

func _test_transfer_recycle_harvest() -> void:
	var bm := _make_bm()
	var bs := _make_bs(bm)
	bm.item_transferred.emit(_make_mon("Giver"), _make_mon("Taker"),
			_make_item("Leftovers"))
	var line := _narrative(bs)
	_chk("B.01 a transfer names the RECIPIENT and the item",
			"Taker" in line and "Leftovers" in line and "obtained" in line)
	bs.free()
	bm.queue_free()

	# Recycle's own string was the one the recon left unresolved
	# ("needs per-item confirmation"); it is source's "found one {item}!".
	var bm2 := _make_bm()
	var bs2 := _make_bs(bm2)
	bm2.item_recycled.emit(_make_mon("Recycler"), _make_item("Oran Berry"))
	_chk("B.02 Recycle uses source's own recovered-item wording",
			"found one Oran Berry!" in _narrative(bs2))
	bs2.free()
	bm2.queue_free()

	var bm3 := _make_bm()
	var bs3 := _make_bs(bm3)
	bm3.item_regenerated.emit(_make_mon("Harvester"), _make_item("Lum Berry"))
	_chk("B.03 Harvest is narrated distinctly from Recycle",
			"harvested its Lum Berry!" in _narrative(bs3))
	bs3.free()
	bm3.queue_free()


func _test_item_damage() -> void:
	var bm := _make_bm()
	var bs := _make_bs(bm)
	bm.item_damage.emit(_make_mon("Orbed"), 30)
	var line := _narrative(bs)
	_chk("B.04 item recoil is narrated", "was hurt by its held item!" in line)
	_chk("B.04b ...without leaking the raw amount", not ("30" in line))
	bs.free()
	bm.queue_free()


# ── C. Effect keys ───────────────────────────────────────────────────────

# Every key BattleManager can emit must have text, re-derived from source
# rather than kept as a hand list — the same guard shape as D3-1's A.02.
func _test_item_effect_keys() -> void:
	var src := FileAccess.get_file_as_string(
			"res://scripts/battle/core/battle_manager.gd")
	_chk("C.00 battle_manager.gd is readable", src != "")
	if src == "":
		return
	var rx := RegEx.new()
	rx.compile('item_effect_triggered\\.emit\\([^,]+,\\s*"([a-z_]+)"')
	var found: Dictionary = {}
	for m: RegExMatch in rx.search_all(src):
		found[m.get_string(1)] = true
	var missing: Array[String] = []
	for k: String in found:
		if not BattleScreenShared._ITEM_EFFECT_TEXT.has(k):
			missing.append(k)
	_chk("C.01 every emitted effect_key has text (missing: %s)" % str(missing),
			missing.is_empty())
	_chk("C.02 the scan found real keys (found %d)" % found.size(),
			found.size() >= 9)

	for key: String in found:
		var bm := _make_bm()
		var bs := _make_bs(bm)
		bm.item_effect_triggered.emit(_make_mon("Holder"), key)
		_chk("C.03 key '%s' produces a line" % key, _narrative(bs) != "")
		bs.free()
		bm.queue_free()


func _test_unknown_effect_key_stays_silent() -> void:
	var bm := _make_bm()
	var bs := _make_bs(bm)
	bm.item_effect_triggered.emit(_make_mon("Holder"), "some_future_key")
	_chk("C.04 an unrecognised key produces no malformed line",
			_narrative(bs) == "")
	bs.free()
	bm.queue_free()


# ── S. Deliberately silent ───────────────────────────────────────────────

func _test_item_consumed_stays_silent() -> void:
	var bm := _make_bm()
	var bs := _make_bs(bm)
	bm.item_consumed.emit(_make_mon("Eater"), _make_item("Sitrus Berry"))
	_chk("S.01 item_consumed is SILENT — the effect line already covers it",
			_narrative(bs) == "")
	_chk("S.02 ...and it genuinely has no listener",
			bm.item_consumed.get_connections().is_empty())
	# Non-vacuity: the effect signals that DO cover consumption are wired.
	_chk("S.03 (non-vacuity) item_healed and status_cured ARE wired",
			not bm.item_healed.get_connections().is_empty()
				and not bm.status_cured.get_connections().is_empty())
	bs.free()
	bm.queue_free()
