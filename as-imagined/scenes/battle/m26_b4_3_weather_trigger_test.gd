extends Node

# [M26B4-3] Regression suite for weather-animation TRIGGER WIRING.
#
# Source fires a weather animation from three places and deliberately not from
# a fourth (docs/m26_b4_recon.md §2):
#   1. per turn while weather is active  -> BattleScript_WeatherContinues
#   2. weather set by an ABILITY         -> TryChangeBattleWeather's ability branch
#   3. weather set by a MOVE             -> the move's own animation, NOT the
#                                           `*_CONTINUES` one
#   4. weather ENDING                    -> no animation at all
#
# The headline assertion here is A.01: the per-turn animation beat must be
# queued AFTER the message beat, reproducing
# `printfromtable -> waitmessage -> playanimation_var`. Per M26G2, this suite
# class is structurally blind to sequencing unless ORDER is asserted
# explicitly — presence alone would pass just as happily with the two beats
# reversed, which would read as the animation playing before its own caption.

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_continues_queues_text_then_anim_in_that_order()
	_test_expiry_queues_no_animation()
	_test_ability_set_queues_an_animation()
	_test_move_driven_set_does_not_double_up()
	_test_setter_without_ability_is_safe()
	_test_weather_move_queues_a_weather_beat()
	_test_weather_move_needs_no_target_sprite()
	_test_snowscape_takes_the_id_specific_path()
	_test_non_weather_move_is_unaffected()

	var total := _pass + _fail
	print("m26_b4_3_weather_trigger_test: %d/%d passed" % [_pass, total])
	if _fail > 0:
		print("FAILED")
	get_tree().quit(0 if _fail == 0 else 1)


func _chk(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + label)


# ── Fixtures ─────────────────────────────────────────────────────────────

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
	return bs


# A weather move loaded from real data, so `weather_type` and the move id both
# come from the shipped .tres rather than a hand-built stand-in.
func _real_move(move_id: int) -> MoveData:
	return load("res://data/moves/move_%04d.tres" % move_id) as MoveData


func _beat_kinds(bs: BattleScreenShared) -> Array:
	var out := []
	for beat: Dictionary in bs._pending_beats:
		out.append(beat.get("kind", ""))
	return out


# ── A. Per-turn replay ───────────────────────────────────────────────────

# THE assertion for this sub-phase. Order, not presence.
func _test_continues_queues_text_then_anim_in_that_order() -> void:
	var bm := _make_bm()
	var bs := _make_bs(bm)
	bs._wire_log_signals()
	bm.weather_continues.emit(DamageCalculator.WEATHER_RAIN)
	var kinds := _beat_kinds(bs)
	_chk("A.01 exactly two beats queued (message, then animation)",
			kinds.size() == 2)
	_chk("A.01b the message beat is FIRST",
			kinds.size() == 2 and kinds[0] == "text")
	_chk("A.01c the animation beat is SECOND",
			kinds.size() == 2 and kinds[1] == "anim_async")
	_chk("A.01d the message beat carries the real continues line",
			bs._pending_beats.size() == 2
				and str(bs._pending_beats[0].get("text", "")) == "Rain continues to fall.")
	_chk("A.01e the animation beat carries a callable",
			bs._pending_beats.size() == 2
				and (bs._pending_beats[1].get("start") as Callable).is_valid())
	bs.free()
	bm.queue_free()


# BattleScript_WeatherFaded has no playanimation of any kind.
func _test_expiry_queues_no_animation() -> void:
	var bm := _make_bm()
	var bs := _make_bs(bm)
	bs._wire_log_signals()
	bm.weather_expired.emit(DamageCalculator.WEATHER_RAIN)
	var kinds := _beat_kinds(bs)
	_chk("A.02 weather ending queues a message but NO animation",
			kinds.has("text") and not kinds.has("anim_async"))
	bs.free()
	bm.queue_free()


# ── B. Weather set by an ability ─────────────────────────────────────────

func _test_ability_set_queues_an_animation() -> void:
	var bm := _make_bm()
	var bs := _make_bs(bm)
	bs._wire_log_signals()
	var setter := _make_mon("Drizzler")
	setter.ability = load("res://data/abilities/ability_%04d.tres"
			% AbilityManager.ABILITY_DRIZZLE) as AbilityData
	bm.weather_set.emit(setter, DamageCalculator.WEATHER_RAIN)
	_chk("B.01 an ability-driven weather set queues an animation beat",
			_beat_kinds(bs).has("anim_async"))
	bs.free()
	bm.queue_free()


# The move path already played the move's own animation, so `weather_set`
# must not add a second one on top.
func _test_move_driven_set_does_not_double_up() -> void:
	var bm := _make_bm()
	var bs := _make_bs(bm)
	bs._wire_log_signals()
	var setter := _make_mon("PlainMon")
	setter.ability = load("res://data/abilities/ability_%04d.tres"
			% AbilityManager.ABILITY_STATIC) as AbilityData
	bm.weather_set.emit(setter, DamageCalculator.WEATHER_RAIN)
	_chk("B.02 a non-weather-ability setter queues NO animation beat",
			not _beat_kinds(bs).has("anim_async"))
	bs.free()
	bm.queue_free()


func _test_setter_without_ability_is_safe() -> void:
	var bm := _make_bm()
	var bs := _make_bs(bm)
	bs._wire_log_signals()
	bm.weather_set.emit(null, DamageCalculator.WEATHER_SUN)
	_chk("B.03 a null setter neither crashes nor queues an animation",
			not _beat_kinds(bs).has("anim_async"))
	var mon := _make_mon("NoAbility")
	mon.ability = null
	bm.weather_set.emit(mon, DamageCalculator.WEATHER_SUN)
	_chk("B.04 a setter with no ability is likewise safe",
			not _beat_kinds(bs).has("anim_async"))
	bs.free()
	bm.queue_free()


# ── C. Weather set by a move ─────────────────────────────────────────────

func _test_weather_move_queues_a_weather_beat() -> void:
	for move_id: int in [201, 240, 241, 258]:  # Sandstorm, Rain Dance, Sunny Day, Hail
		var bm := _make_bm()
		var bs := _make_bs(bm)
		var mon := _make_mon("Caster")
		var move := _real_move(move_id)
		_chk("C.01 move %d really carries a weather_type" % move_id,
				move != null and move.weather_type != DamageCalculator.WEATHER_NONE)
		bs._on_hit_effect_move_executed(mon, mon, move, 0)
		_chk("C.02 move %d queues a weather animation beat" % move_id,
				_beat_kinds(bs) == ["anim_async"])
		bs.free()
		bm.queue_free()


# A weather animation is full-screen and has no target, so it must not be
# gated behind the target-sprite lookup that targeted hit effects need. On a
# bare instance _sprite_node_for() returns null, which is exactly the
# condition that used to swallow it.
func _test_weather_move_needs_no_target_sprite() -> void:
	var bm := _make_bm()
	var bs := _make_bs(bm)
	var mon := _make_mon("NoSpriteCaster")
	_chk("C.03 (precondition) no target sprite resolves on a bare instance",
			bs._sprite_node_for(mon) == null)
	bs._on_hit_effect_move_executed(mon, mon, _real_move(240), 0)
	_chk("C.04 the weather beat is queued anyway",
			_beat_kinds(bs) == ["anim_async"])
	bs.free()
	bm.queue_free()


# Snowscape sets WEATHER_HAIL here (the [D2 batch] collapse), so weather STATE
# cannot distinguish it — the dispatch must key on the move id instead.
func _test_snowscape_takes_the_id_specific_path() -> void:
	var snowscape := _real_move(809)
	_chk("C.05 Snowscape really sets WEATHER_HAIL in this project",
			snowscape != null and snowscape.weather_type == DamageCalculator.WEATHER_HAIL)
	_chk("C.06 its id matches the dispatch's own constant",
			HitEffectRegistry.move_id_of(snowscape) == BattleScreenShared._MOVE_ID_SNOWSCAPE)
	var bm := _make_bm()
	var bs := _make_bs(bm)
	var mon := _make_mon("SnowCaster")
	bs._on_hit_effect_move_executed(mon, mon, snowscape, 0)
	_chk("C.07 Snowscape still queues a weather animation beat",
			_beat_kinds(bs) == ["anim_async"])
	bs.free()
	bm.queue_free()


func _test_non_weather_move_is_unaffected() -> void:
	var bm := _make_bm()
	var bs := _make_bs(bm)
	var mon := _make_mon("Tackler")
	var tackle := MoveData.new()
	tackle.move_name = "Tackle"
	tackle.type = TypeChart.TYPE_NORMAL
	tackle.category = 0
	tackle.power = 40
	tackle.accuracy = 100
	tackle.pp = 35
	bs._on_hit_effect_move_executed(mon, mon, tackle, 10)
	_chk("C.08 a non-weather move queues no weather beat",
			not _beat_kinds(bs).has("anim_async"))
	bs.free()
	bm.queue_free()
