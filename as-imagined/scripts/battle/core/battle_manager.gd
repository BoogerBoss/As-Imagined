class_name BattleManager
extends Node

# M11: Field-wide weather constants — mirrors DamageCalculator.WEATHER_*.
# Defined here for callers who reference BattleManager directly (tests, UI).
# Source: include/constants/battle.h :: enum BattleWeather / B_WEATHER_* bitmask.
# In source, gBattleWeather is a bitmask; we use a plain int enum (one active at a time).
const WEATHER_NONE:      int = DamageCalculator.WEATHER_NONE
const WEATHER_RAIN:      int = DamageCalculator.WEATHER_RAIN
const WEATHER_SUN:       int = DamageCalculator.WEATHER_SUN
const WEATHER_SANDSTORM: int = DamageCalculator.WEATHER_SANDSTORM
const WEATHER_HAIL:      int = DamageCalculator.WEATHER_HAIL

# Duration of ability-set weather in turns (no held-item extension in M11 scope).
# Source: TryChangeBattleWeather (battle_util.c L1996): gBattleStruct->weatherDuration = 5.
const WEATHER_DURATION_DEFAULT: int = 5

enum BattlePhase {
	BATTLE_START,
	MOVE_SELECTION,
	PRIORITY_RESOLUTION,
	ACTION_EXECUTION,
	PRE_MOVE_CHECKS,
	MOVE_EXECUTION,
	FAINT_CHECK,
	END_OF_TURN,
	SWITCH_PROMPT,
	BATTLE_END_CHECK,
	BATTLE_END,
}

# Emitted whenever the phase changes (useful for debug / UI overlays).
signal phase_changed(new_phase: BattlePhase)

# Emitted when the state machine is waiting for external input before it can
# advance. The caller must supply inputs (e.g. chosen move index) and then
# call advance(). In M1 this is never emitted because moves are auto-selected.
signal action_needed(phase: BattlePhase)

# Battle event signals consumed by the UI / test runner.
signal move_executed(attacker: BattlePokemon, defender: BattlePokemon, move: MoveData, damage: int)
signal pokemon_fainted(pokemon: BattlePokemon)
signal battle_ended(winner_side: int)  # 0 = player/side-0 wins, 1 = opponent/side-1 wins
signal status_damage(pokemon: BattlePokemon, amount: int)  # end-of-turn status tick
signal move_skipped(pokemon: BattlePokemon, reason: String)  # sleep/freeze/para/confusion/flinch
signal confusion_self_hit(pokemon: BattlePokemon, damage: int)
signal pokemon_thawed(pokemon: BattlePokemon)  # freeze cleared mid-battle
signal move_missed(attacker: BattlePokemon, reason: String)  # "accuracy", "immune", or "semi_invulnerable"
signal stat_stage_changed(target: BattlePokemon, stat_idx: int, actual_change: int)
signal move_effect_failed(target: BattlePokemon, reason: String)  # "stat_limit", "immune", "already_status"
signal secondary_applied(target: BattlePokemon, effect: int)  # MoveData.SE_* value
# M6 signals
signal charge_started(attacker: BattlePokemon, move: MoveData)  # turn 1 of a two-turn move
signal recoil_damage(attacker: BattlePokemon, amount: int)       # attacker took recoil
signal drain_heal(attacker: BattlePokemon, amount: int)          # attacker healed via drain
# M8 signals
signal ability_triggered(pokemon: BattlePokemon, effect_key: String)      # any ability fires
# M7 signals
signal substitute_created(attacker: BattlePokemon, sub_hp: int)          # Substitute put up
signal substitute_broke(defender: BattlePokemon)                          # Substitute HP → 0
signal protected(defender: BattlePokemon)                                 # Protect succeeded
signal destiny_bond_set(attacker: BattlePokemon)                          # Destiny Bond activated
signal destiny_bond_triggered(fainted_mon: BattlePokemon, killer: BattlePokemon)  # DB KO
signal disabled(target: BattlePokemon, move: MoveData)                    # Disable applied
signal encored(target: BattlePokemon, move: MoveData)                     # Encore applied
signal infatuated(mon: BattlePokemon)                                     # M18.5d-2: Attract/Cute Charm applied
signal bide_started(attacker: BattlePokemon)                              # Bide setup turn
signal bide_storing(attacker: BattlePokemon)                              # Bide wait turn
signal bide_released(attacker: BattlePokemon, damage: int)                # Bide release
signal move_called(attacker: BattlePokemon, called_move: MoveData)        # Metronome called
# M9 signals
signal pokemon_switched_out(pokemon: BattlePokemon, side: int)            # left the field
signal pokemon_switched_in(pokemon: BattlePokemon, side: int, slot: int)  # entered the field
signal forced_switch(old_mon: BattlePokemon, new_mon: BattlePokemon)      # Roar/Whirlwind result; M18n: also Red Card/Eject Button
signal baton_passed(from_mon: BattlePokemon, to_mon: BattlePokemon)       # Baton Pass completed
signal replacement_needed(side: int)                                       # fainted, party not empty
# M11 signals
signal weather_set(by_pokemon: BattlePokemon, weather_type: int)          # weather changed
signal weather_expired(weather_type: int)                                  # weather duration ran out
signal weather_damage(pokemon: BattlePokemon, amount: int)                 # sandstorm/hail chip
# M18.5f signals
signal wrap_damage(pokemon: BattlePokemon, amount: int)                    # Bind/Wrap-family end-of-turn tick
signal wrap_ended(pokemon: BattlePokemon)                                  # trap duration ran out (broke free)
# M18.5g signal
signal multi_hit_sequence_finished(attacker: BattlePokemon, target: BattlePokemon, hits_landed: int, total_damage: int)  # whole multi-hit move resolved
# M17c signal
signal ability_healed(pokemon: BattlePokemon, amount: int)                 # Rain Dish/Ice Body/Dry Skin/Hospitality/Cheek Pouch
# M12 signals
signal item_consumed(pokemon: BattlePokemon, item: ItemData)               # one-use item activated
signal item_healed(pokemon: BattlePokemon, amount: int)                    # Leftovers / Sitrus Berry
signal item_damage(pokemon: BattlePokemon, amount: int)                    # Life Orb recoil
signal item_regenerated(pokemon: BattlePokemon, item: ItemData)            # M17n-7: Harvest
signal item_effect_triggered(pokemon: BattlePokemon, effect_key: String)   # M18o: generic item-effect-fired
                                                                             # signal (Focus Band's survive —
                                                                             # not consumed, so item_consumed
                                                                             # doesn't fit; mirrors
                                                                             # ability_triggered's shape for
                                                                             # items with no dedicated signal)
signal pp_restored(pokemon: BattlePokemon, move_index: int, new_pp: int)   # M18d: Leppa Berry
# M14b signals
signal helping_hand_used(user: BattlePokemon, ally: BattlePokemon)         # Helping Hand boosted ally
signal follow_me_used(user: BattlePokemon)                                 # Follow Me/Rage Powder active

signal screen_set(side: int, screen_name: String)                          # "reflect"/"light_screen"/"aurora_veil" went up
signal screen_expired(side: int, screen_name: String)                      # duration ran out
signal screens_broken(side: int)                                           # Brick Break cleared a side's screens

signal hazard_set(side: int, hazard_name: String, layers: int)             # Spikes/Toxic Spikes/Stealth Rock set (or stacked)
signal hazard_damage(pokemon: BattlePokemon, amount: int, hazard_name: String)  # switch-in hazard chip
signal hazard_status_applied(pokemon: BattlePokemon, status: int)          # Toxic Spikes poisoned/badly-poisoned a switch-in
signal hazard_absorbed(side: int, hazard_name: String)                     # grounded Poison-type absorbed Toxic Spikes
signal hazards_cleared(side: int, hazard_name: String)                     # Rapid Spin cleared one hazard type
signal trick_room_set()                                                    # Trick Room activated
signal trick_room_ended()                                                  # Trick Room deactivated (toggle-off or natural expiry)

# M16e signals
signal pain_split_used(attacker: BattlePokemon, defender: BattlePokemon)   # HP averaged between both
signal type_changed(pokemon: BattlePokemon, new_type: int)                 # Conversion / Conversion 2
signal stat_changes_copied(user: BattlePokemon, from_mon: BattlePokemon)   # Psych Up copied stat_stages (+ focus_energy)

signal ability_changed(pokemon: BattlePokemon, new_ability_id: int)       # M17h: Trace/Mummy/Receiver/Wandering Spirit

signal item_transferred(from_mon: BattlePokemon, to_mon: BattlePokemon, item: ItemData)  # M17j: Pickpocket/Magician/Symbiosis

signal move_bounced(holder: BattlePokemon, new_target: BattlePokemon)      # M17n-9: Magic Bounce reflected a status move


const MAX_PHASES_PER_ADVANCE: int = 4096

var _phase: BattlePhase = BattlePhase.BATTLE_START

# M9: per-side party objects. _combatants[i] = _parties[i].get_active().
var _parties: Array[BattleParty] = []
# Index 0 = player side, index 1 = opponent side — always the ACTIVE Pokémon.
var _combatants: Array[BattlePokemon] = []
var _turn_order: Array[BattlePokemon] = []
# Chosen move per combatant (null if that side is switching this turn).
var _chosen_moves: Array = []
# M9: switch slot per combatant (-1 = not switching, ≥0 = party slot to switch to).
var _chosen_switch_slots: Array[int] = []
# M9: actor→side map set at PRIORITY_RESOLUTION, used to recover side index mid-turn.
# Keyed by BattlePokemon object (the active mon at resolution time).
var _actor_sides: Dictionary = {}
var _current_actor_index: int = 0
var _is_advancing: bool = false

# M14a: number of active Pokémon per side (1 = singles, 2 = doubles).
# Governs combatant layout: _combatants[side * _active_per_side + field_slot].
var _active_per_side: int = 1

# M14a: per-actor combatant index (BattlePokemon → int 0..N-1).
# Set at PRIORITY_RESOLUTION alongside _actor_sides.
# Used wherever we need the combatant's position in _combatants (e.g. _chosen_moves lookup).
var _actor_indices: Dictionary = {}

# M14a: chosen target combatant index per actor this turn.
# _chosen_targets[combatant_idx] = the combatant index of the move's target.
# Defaults to the first opponent slot; overridden by queue_move_targeted actions.
var _chosen_targets: Array[int] = []

# M9: pre-queued action lists per combatant index.
# Each element: {"type": "switch", "slot": int} or {"type": "move", "index": int}
# or {"type": "move", "index": int, "target": int} for doubles.
# M14a: sized to 4 to support doubles (combatants 0-3). Singles only uses [0] and [1].
# Test suites fill these before start_battle*() to control turn order deterministically.
var _action_queues: Array = [[], [], [], []]

# M9: pre-queued replacement slots for SWITCH_PROMPT (faint replacement).
# -1 entry = auto-select first available non-fainted slot.
# M14a: indexed by combatant index (not side); [0]/[1] are singles-compatible.
var _replacement_queues: Array = [[], [], [], []]

# M9: forced RNG for Roar/Whirlwind candidate selection (for deterministic tests).
# -1 = use real RNG; ≥0 = index into candidates array.
var _force_roar_rng: int = -1

# Test seam: force accuracy check result for all moves this battle.
# null = use real RNG via StatusManager.check_accuracy; true = always hit; false = always miss.
# Mirrors the force_hit: Variant = null parameter already on StatusManager.check_accuracy.
# Use bm._force_hit = true in tests that need a guaranteed hit on a non-accuracy=0 move.
var _force_hit: Variant = null

# Test seam: force the damage roll for all damaging hits this battle.
# null = use real RNG (85-100 random roll, the same convention as _force_hit's null);
# 85-100 = pin to that exact roll. DamageCalculator.calculate's own force_roll param uses
# -1 as its "use real RNG" sentinel (int-typed, can't hold null), so this is converted at
# the _do_damaging_hit call site: _force_roll if _force_roll != null else -1.
# Use bm._force_roll = 100 in tests that need deterministic damage instead of a wide range.
var _force_roll: Variant = null

# Test seam: force the crit result for all damaging hits this battle.
# null = use real RNG; true = always crit; false = suppress crit (deterministic tests).
# Mirrors the force_crit: Variant = null parameter already on DamageCalculator.calculate —
# same null-sentinel convention on both sides, no conversion needed at the call site.
var _force_crit: Variant = null

# Test seam: force the contact-ability roll (Static / Flame Body trigger) for all
# damaging hits this battle.  null = use real RNG; true = always trigger; false = suppress.
# Mirrors force_contact_roll already accepted by AbilityManager.try_contact_effects —
# BM-9 fix threads this value through _do_damaging_hit so integration tests can control it.
var _force_contact_roll: Variant = null

# Test seam: force Magnitude's rolled power for all Magnitude uses this battle.
# null = use real RNG (weighted table roll); one of {10,30,50,70,90,110,150} = pin it.
# Mirrors the null-sentinel convention of the other _force_* seams above.
var _force_magnitude_power: Variant = null

# Test seam: force which candidate Conversion 2 picks from its resist-type pool.
# null = use real RNG (uniform pick, source's reject-already-had-types loop);
# else an index into the SORTED candidate list (ascending TypeChart.TYPE_* ids) after
# the user's current types have already been excluded — see _pick_conversion2_type().
var _force_conversion2_pick: Variant = null

# M17b: force which STAGE_* Moody raises (+2) / lowers (-1) this battle.
# null = use real RNG. Mirrors the null-sentinel convention of the other _force_* seams.
var _force_moody_raise: Variant = null
var _force_moody_lower: Variant = null

# M18c: force which STAGE_* Starf Berry raises (+2, or +4 under Ripen). Same
# null-sentinel seam shape as _force_moody_raise above.
var _force_starf_stat: Variant = null

# M17c: force Shed Skin's 1/3 end-of-turn status-cure roll and Healer's 30% roll.
var _force_shed_skin_roll: Variant = null
var _force_healer_roll: Variant = null
# M17c: force Effect Spore's 3-way contact roll (int 0-99) and Cursed Body's 30% roll.
var _force_effect_spore_roll: Variant = null
var _force_cursed_body_roll: Variant = null
# M17n-7: force Harvest's 50%-normally/100%-in-sun end-of-turn regeneration roll.
var _force_harvest_roll: Variant = null

# M17n-3: force Quick Draw's 30% per-battler-per-turn roll (evaluated once before the
# turn-order sort, same null-sentinel convention as the other _force_* roll seams).
var _force_quick_draw_roll: Variant = null

# M18l: force Quick Claw's 20% per-battler-per-turn roll, same shape/seam pattern as
# _force_quick_draw_roll immediately above — independent roll, independent seam.
var _force_quick_claw_roll: Variant = null

# M18k: force King's Rock/Razor Fang's flinch roll, same null-sentinel seam
# convention as the other _force_* roll seams. Independent of _force_quick_claw_roll —
# rolled per-hit in _do_damaging_hit, not per-turn before the sort.
var _force_kings_rock_roll: Variant = null

# M18o: force Focus Band's survive-lethal-hit roll, same null-sentinel seam
# convention as the other _force_* roll seams.
var _force_focus_band_roll: Variant = null

# [M18.5g] Pins the variable-hit roll (2/3/4/5) for a `multi_hit=true` move,
# same null-sentinel seam convention as every other _force_* roll above. Does
# NOT affect strike_count moves (Double Kick etc. — those have no roll to force)
# or Triple Kick/Axel's own per-hit accuracy rolls (use _force_hit for those,
# same seam every other accuracy check in this file already uses).
var _force_multi_hit_count: Variant = null

# M9: pre-queued Baton Pass target slots per combatant index (-1 = auto-select first valid).
# M14a: indexed by combatant index; singles uses [0] and [1].
var _baton_pass_queues: Array = [[], [], [], []]

# M10: per-side TrainerAI instances (null = human / test-queue side).
# Set before start_battle*() with set_trainer_ai(side, ai).
var _trainer_ais: Array = [null, null]

# M14b: tracks the last Pokémon to deal damage to each target this turn.
# Key: BattlePokemon (defender), Value: BattlePokemon (attacker that last hit them).
# Cleared at the start of each turn (PRIORITY_RESOLUTION).
# Used by Destiny Bond: when a Destiny Bond holder faints, the killer is _last_attacker
# rather than _get_first_opponent (which is wrong in doubles if the second slot lands the KO).
# Source: FAINT_BLOCK_TRY_DESTINY_BOND (battle_move_resolution.c L2953) uses gBattlerAttacker
#   global at time of lethal hit — equivalent to tracking last attacker per target.
var _last_attacker: Dictionary = {}

# M17n-8: companions to `_last_attacker` above, set at the exact same call sites, for
# Aftermath/Innards Out's on-faint retaliation. `_last_attacker_move` — the MoveData
# used for that last hit (Aftermath needs to know if it made contact). `_last_attacker_hp_before`
# — the defender's own HP immediately before that hit was applied (Innards Out's
# damage amount; NOT the move's raw calculated damage, which can exceed remaining HP
# on an overkill hit — see AbilityManager.faint_retaliation_damage's doc comment).
# Cleared alongside `_last_attacker` at the start of each turn.
var _last_attacker_move: Dictionary = {}
var _last_attacker_hp_before: Dictionary = {}

# M14b: per-side Follow Me/Rage Powder state. -1 = no Follow Me active this turn.
# Value = combatant index of the Pokémon that used Follow Me/Rage Powder.
# Source: gSideTimers[side].followmeTimer / followmeTarget (battle_main.c L5060–5061).
# Cleared at the start of each turn (PRIORITY_RESOLUTION / TurnValuesCleanUp equivalent).
var _follow_me_targets: Array[int] = [-1, -1]

# M14b: per-combatant Helping Hand boost flag for this turn.
# True = this combatant's ally used Helping Hand; next damaging move gets 1.5× base power.
# Source: gProtectStructs[battler].helpingHand (battle_util.c L6436).
# Cleared at the start of each turn (PRIORITY_RESOLUTION / TurnValuesCleanUp equivalent).
var _helping_hand: Array[bool] = [false, false, false, false]

# M11: Field-wide weather state. Weather is NOT per-Pokémon — it's a battle-field
# effect that persists through switches (gBattleWeather + gBattleStruct->weatherDuration).
# Source: gBattleWeather (battle_util.c global), weatherDuration (gBattleStruct field).
var weather: int = WEATHER_NONE
var weather_duration: int = 0  # turns remaining; 0 when no weather is active

# M16c: per-side screen conditions (Reflect / Light Screen / Aurora Veil).
# Indexed by SIDE (0/1) — always length 2 regardless of singles/doubles, same convention as
# _follow_me_targets above (doubles just means 2 field slots share one side's conditions).
# These are side-bound, not battler-bound: they persist across the owning side's switches
# (nothing in _clear_volatiles / _switch_out_clear touches this array — by construction,
# since those operate on BattlePokemon, not on BattleManager's side-indexed state) and only
# clear on expiry (duration reaching 0) or an explicit screen-removal move (Brick Break).
# Source: gSideStatuses[side] (bitmask) + gSideTimers[side].{reflectTimer,lightscreenTimer,
#   auroraVeilTimer} (include/battle.h). Turns-remaining ints here fold together the
#   presence bit and the timer into one field per condition (0 = not active).
#
# M16d: extended with entry hazards (Spikes/Toxic Spikes/Stealth Rock), reusing this exact
# per-side shape rather than inventing a new one (per M16c's explicit forward-compat note).
# Unlike the screens above, hazards have no natural duration — they persist until cleared
# by Rapid Spin or the battle ends, so they're stored as plain layer counts / a bool rather
# than turns-remaining. spikes_layers: 0-3. toxic_spikes_layers: 0-2. stealth_rock: bool
# (single application, no layers).
# Source: gSideTimers[side].{spikesAmount, toxicSpikesAmount} + gSideStatuses[side] &
#   SIDE_STATUS_STEALTH_ROCK (include/constants/battle.h).
var _side_conditions: Array = [
	{"reflect_turns": 0, "light_screen_turns": 0, "aurora_veil_turns": 0,
			"spikes_layers": 0, "toxic_spikes_layers": 0, "stealth_rock": false},
	{"reflect_turns": 0, "light_screen_turns": 0, "aurora_veil_turns": 0,
			"spikes_layers": 0, "toxic_spikes_layers": 0, "stealth_rock": false},
]

# M16d: Trick Room — genuinely per-BATTLE (not per-side, not per-Pokémon): reverses the
# speed tiebreak used in turn-order resolution while active. 0 = inactive.
# Source: gFieldStatuses & STATUS_FIELD_TRICK_ROOM (bitmask) + gFieldTimers.trickRoomTimer.
var trick_room_turns: int = 0

# M15 Task 3: Struggle instantiated in _ready(); used when all PP are depleted.
# Source: battle_main.c L4727–4728 — noValidMoves → MOVE_STRUGGLE substitution.
var _struggle_move: MoveData = null


func _ready() -> void:
	_struggle_move = MoveData.new()
	_struggle_move.move_name = "Struggle"
	_struggle_move.type = TypeChart.TYPE_MYSTERY
	_struggle_move.category = 0
	_struggle_move.power = 50
	_struggle_move.pp = 1
	_struggle_move.accuracy = 0
	_struggle_move.is_struggle = true
	_struggle_move.makes_contact = true


# ── Entry points ────────────────────────────────────────────────────────────────

# Backward-compat 1v1 entry point: wraps each BattlePokemon into a 1-member BattleParty.
# All M1-M8 test suites call this signature and are unaffected by M9 party logic.
func start_battle(player_pokemon: BattlePokemon, opponent_pokemon: BattlePokemon) -> void:
	start_battle_with_parties(
		BattleParty.single(player_pokemon),
		BattleParty.single(opponent_pokemon))


# M9 entry point: full party on each side (singles).
func start_battle_with_parties(player_party: BattleParty,
		opponent_party: BattleParty) -> void:
	_active_per_side = 1
	_parties = [player_party, opponent_party]
	_combatants = [player_party.get_active(), opponent_party.get_active()]
	_chosen_moves = [null, null]
	_chosen_switch_slots = [-1, -1]
	_chosen_targets = [1, 0]  # each targets the single opponent
	_set_phase(BattlePhase.BATTLE_START)
	advance()


# M14a entry point: 2v2 doubles. Each party must have active_indices = [0, 1].
# Combatant layout (side-grouped): [side0_slot0, side0_slot1, side1_slot0, side1_slot1].
# Source: gBattlerPositions — B_POSITION_PLAYER_LEFT=0, B_POSITION_PLAYER_RIGHT=2,
#   B_POSITION_OPPONENT_LEFT=1, B_POSITION_OPPONENT_RIGHT=3 (battle.h L1234).
#   We use side-grouped order (both player slots contiguous) rather than alternating.
func start_battle_doubles(player_party: BattleParty,
		opponent_party: BattleParty) -> void:
	_active_per_side = 2
	_parties = [player_party, opponent_party]
	_combatants = [
		player_party.get_active_at(0),
		player_party.get_active_at(1),
		opponent_party.get_active_at(0),
		opponent_party.get_active_at(1),
	]
	_chosen_moves   = [null, null, null, null]
	_chosen_switch_slots = [-1, -1, -1, -1]
	_chosen_targets = [2, 2, 0, 0]  # default: each targets first slot of opposing side
	_set_phase(BattlePhase.BATTLE_START)
	advance()


# ── Action queue API (called by tests before start or between turns) ─────────

func queue_switch(side: int, slot: int) -> void:
	_action_queues[side].append({"type": "switch", "slot": slot})


func queue_move(side: int, move_index: int) -> void:
	_action_queues[side].append({"type": "move", "index": move_index})


func queue_replacement(side: int, slot: int) -> void:
	_replacement_queues[side].append(slot)


func queue_baton_pass_target(side: int, slot: int) -> void:
	_baton_pass_queues[side].append(slot)


# M14a: doubles-aware queue APIs. combatant_idx is 0-3 in doubles.
# queue_move_targeted also allows an explicit target (opposing combatant index).
func queue_move_targeted(combatant_idx: int, move_index: int, target_idx: int) -> void:
	_action_queues[combatant_idx].append(
		{"type": "move", "index": move_index, "target": target_idx})

func queue_switch_for(combatant_idx: int, slot: int) -> void:
	_action_queues[combatant_idx].append({"type": "switch", "slot": slot})

func queue_replacement_for(combatant_idx: int, slot: int) -> void:
	_replacement_queues[combatant_idx].append(slot)


# M10: attach a TrainerAI to one side. null = human / test-queue control.
# Source: BattleAI_SetupFlags assigns AI flags per battler (battle_ai_main.c L302).
func set_trainer_ai(side: int, ai) -> void:
	_trainer_ais[side] = ai


# M11/M12: Attempt to set field weather. Returns true if weather changed.
# Source: TryChangeBattleWeather (battle_util.c L1969–2015):
#   — Returns FALSE if gBattleWeather already has the requested weather flag active.
#   — Duration = 8 if setter holds the matching rock item, else 5.
#     (M12: rock extension via ItemManager.weather_duration; by_pokemon=null → default 5.)
#   — Primal weather override logic: not in scope.
func try_set_weather(weather_type: int, by_pokemon: BattlePokemon = null) -> bool:
	if weather == weather_type:
		return false
	weather = weather_type
	weather_duration = ItemManager.weather_duration(
			by_pokemon, weather_type, _is_neutralizing_gas_active()) \
		if weather_type != WEATHER_NONE else 0
	return true


# M17n-10: Forecast — "weather just changed, notify all battlers" broadcast. Source:
# every actual weather-change call site in source invokes AbilityBattleEffects
# (ABILITYEFFECT_ON_WEATHER, ...) for the relevant battler(s)
# (battle_script_commands.c L11917, L12889); this project has 4 places `weather`
# actually changes (ability switch-in setter, Baton Pass inheritance, Sand Spit,
# natural end-of-turn expiration) and none of them previously gave any Pokémon a
# chance to react — this is that missing hook, called once from each of the 4 sites
# right after the change is confirmed real. Loops ALL live combatants (not just the
# mon that caused the change) since Forecast's holder may be on either side and may
# not be the one who changed the weather. Only Forecast reacts to this hook today;
# Protosynthesis (the other ability this hook was originally scoped to serve
# alongside, per `docs/m17n_recon.md`) is excluded from this project's scope, so this
# is self-contained with no cross-ability coordination needed.
func _notify_weather_changed() -> void:
	var ng_active: bool = _is_neutralizing_gas_active()
	var eff_weather: int = _effective_weather()
	for mon: BattlePokemon in _combatants:
		if mon.fainted:
			continue
		var new_type: int = AbilityManager.forecast_type(mon, ng_active, eff_weather)
		if new_type != TypeChart.TYPE_NONE and new_type not in mon.species.types:
			_set_mon_type(mon, new_type)
			type_changed.emit(mon, new_type)
			ability_triggered.emit(mon, "forecast")


# Pump the state machine until it reaches a terminal phase or a phase handler
# stops without changing phases (the future "waiting for input" shape).
func advance() -> void:
	if _is_advancing:
		return
	_is_advancing = true

	var phases_run := 0
	while _phase != BattlePhase.BATTLE_END and phases_run < MAX_PHASES_PER_ADVANCE:
		var phase_before: BattlePhase = _phase
		_dispatch_phase()
		phases_run += 1
		if _phase == phase_before:
			break

	_is_advancing = false


func _dispatch_phase() -> void:
	match _phase:
		BattlePhase.BATTLE_START:        _phase_battle_start()
		BattlePhase.MOVE_SELECTION:      _phase_move_selection()
		BattlePhase.PRIORITY_RESOLUTION: _phase_priority_resolution()
		BattlePhase.ACTION_EXECUTION:    _phase_action_execution()
		BattlePhase.PRE_MOVE_CHECKS:     _phase_pre_move_checks()
		BattlePhase.MOVE_EXECUTION:      _phase_move_execution()
		BattlePhase.FAINT_CHECK:         _phase_faint_check()
		BattlePhase.END_OF_TURN:         _phase_end_of_turn()
		BattlePhase.SWITCH_PROMPT:       _phase_switch_prompt()
		BattlePhase.BATTLE_END_CHECK:    _phase_battle_end_check()
		BattlePhase.BATTLE_END:          pass  # terminal — do nothing


func get_phase() -> BattlePhase:
	return _phase


# --- Phase handlers ---

func _phase_battle_start() -> void:
	# Fire switch-in hazard and ability effects for all starting Pokémon (they enter
	# simultaneously). Hazards before abilities — see _apply_switch_in_hazards for the
	# source-confirmed FIRST_EVENT_BLOCK ordering.
	# Source: AbilityBattleEffects(ABILITYEFFECT_ON_SWITCHIN, ...) (battle_util.c L3310)
	for i in range(_combatants.size()):
		var mon: BattlePokemon = _combatants[i]
		_reset_mon_type(mon)
		_apply_switch_in_hazards(mon, i / _active_per_side)
		_apply_switch_in_abilities(mon, i / _active_per_side)
	_set_phase(BattlePhase.MOVE_SELECTION)


func _phase_move_selection() -> void:
	# Determine action for each combatant. Priority order:
	# 1. Lock-in (charging / encored) — overrides queue and auto-select.
	# 2. Pre-queued action from _action_queues (for deterministic test control).
	# 3. TrainerAI decision (SMART/BASIC tiers).
	# 4. Auto-select: first available move.
	# Source: battle_main.c gLockedMoves + gBattleMons[].volatiles.encoredMove
	# M14a: iterates all combatants (2 in singles, 4 in doubles).
	#   _action_queues indexed by combatant index; side = combatant_idx / _active_per_side.
	for i in range(_combatants.size()):
		var mon: BattlePokemon = _combatants[i]
		_chosen_switch_slots[i] = -1
		_chosen_targets[i] = _default_target(i)
		# Skip fainted combatants (doubles: a slot can be empty with no bench replacement).
		if mon.fainted:
			_chosen_moves[i] = null
			continue
		var side: int = i / _active_per_side
		if mon.charging_move != null:
			_chosen_moves[i] = mon.charging_move
		elif mon.encored_move != null:
			_chosen_moves[i] = mon.encored_move
		elif not _action_queues[i].is_empty():
			var action: Dictionary = _action_queues[i].pop_front()
			if action["type"] == "switch":
				_chosen_switch_slots[i] = action["slot"]
				_chosen_moves[i] = null
			else:
				var idx: int = action.get("index", 0)
				_chosen_moves[i] = mon.moves[idx] if idx < mon.moves.size() else null
				if action.has("target"):
					_chosen_targets[i] = action["target"]
		elif _trainer_ais[side] != null:
			# TrainerAI decides. Source: ComputeAiBattlerDecisions (battle_ai_main.c L401).
			# M14c: doubles uses choose_action_doubles (per-slot target scoring);
			#   singles uses choose_action (single defender).
			var ai: TrainerAI = _trainer_ais[side]
			var action: Dictionary
			if _active_per_side == 2:
				# Doubles: pass both opponent slots so AI can pick (move, target) jointly.
				# Source: ChooseMoveOrAction_Doubles (battle_ai_main.c L918).
				var opp_start: int = (1 - side) * _active_per_side
				var ally_idx: int = side * _active_per_side + (1 - i % _active_per_side)
				action = ai.choose_action_doubles(
						mon,
						_combatants[ally_idx],
						_combatants[opp_start], opp_start,
						_combatants[opp_start + 1], opp_start + 1,
						_parties[side], _parties[1 - side], weather)
			else:
				# Singles: original path, unchanged.
				var opponent: BattlePokemon = _get_first_opponent(mon)
				action = ai.choose_action(
						mon, opponent, _parties[side], _parties[1 - side], weather)
			if action["type"] == "switch":
				_chosen_switch_slots[i] = action["slot"]
				_chosen_moves[i] = null
			else:
				var idx: int = action.get("index", 0)
				_chosen_moves[i] = mon.moves[idx] if idx < mon.moves.size() else null
				if action.has("target"):
					_chosen_targets[i] = action["target"]
		else:
			_chosen_moves[i] = mon.moves[0] if mon.moves.size() > 0 else null
		# M17f: Trapping check (Shadow Tag/Arena Trap/Magnet Pull) blocks VOLUNTARY
		# switch selection only. Source: battle_main.c L4230-4238 (B_ACTION_SWITCH case
		# in the switch-in-menu handler) gates the switch choice itself, before it's
		# accepted as this turn's action -- same shape here, gating _chosen_switch_slots
		# right after it's set from either the test queue or TrainerAI, before it's
		# treated as a real action. Forced switches (Roar/Whirlwind -> _do_forced_switch_in),
		# faint replacement (_phase_switch_prompt -> _do_switch_in), and Baton Pass (a move,
		# never touches _chosen_switch_slots) are untouched -- none of them route through
		# this block. A blocked switch falls back to the mon's first move, same fallback
		# already used above when nothing else picked an action.
		# M18r: Shed Shell — bypasses ability-based trapping for THIS voluntary-
		# switch gate specifically. Source: CanBattlerEscape's HOLD_EFFECT_SHED_SHELL
		# carve-out (battle_main.c L4234/4238). Forced switches (Roar/Whirlwind),
		# faint replacement, and Baton Pass never call is_trapped() at all (per its
		# own doc comment), so they're already correctly unaffected without a
		# Shed Shell check at those sites.
		if _chosen_switch_slots[i] >= 0 \
				and not ItemManager.holds_shed_shell(mon, _is_neutralizing_gas_active()) \
				and AbilityManager.is_trapped(
				mon, _get_live_opponents(mon), _is_neutralizing_gas_active()):
			_chosen_switch_slots[i] = -1
			_chosen_moves[i] = mon.moves[0] if mon.moves.size() > 0 else null
		# M12: Choice lock enforcement — overrides whatever path set above.
		# Source: gBattleStruct->chosenMovePositions[battler] checked in CanChooseMove.
		# Only applies when not switching and not already locked by a charge move.
		if mon.choice_locked_move != null and _chosen_switch_slots[i] < 0 \
				and mon.charging_move == null:
			_chosen_moves[i] = mon.choice_locked_move
		# M15 Task 3: Struggle override — all PP depleted forces Struggle.
		# Source: battle_main.c L4727-4728; CancelerPPDeduction skips Struggle (L979).
		if _is_forced_struggle(mon) and _chosen_switch_slots[i] < 0:
			_chosen_moves[i] = _struggle_move
	_set_phase(BattlePhase.PRIORITY_RESOLUTION)


func _phase_priority_resolution() -> void:
	# Clear per-turn volatiles at the start of each turn.
	# flinched: source battle_move_resolution.c :: CancelerFlinch — lasts exactly one turn.
	# protect_active: Protect/Detect block expires at the start of the next turn.
	# last_physical_damage / last_special_damage: Counter/Mirror Coat only counter damage
	#   received THIS turn; gProtectStructs is memset'd to 0 at turn start.
	# Source: battle_main.c L5036 — memset(&gProtectStructs[i], 0, sizeof(struct ProtectStruct))
	for mon: BattlePokemon in _combatants:
		mon.flinched = false
		mon.protect_active = false
		mon.last_physical_damage = 0
		mon.last_special_damage = 0
		mon.switched_in_this_turn = false
	# M14b: clear per-turn Follow Me, Helping Hand, and last-attacker state.
	# Source: TurnValuesCleanUp (battle_main.c L5022): memset gProtectStructs (helpingHand),
	#   gSideTimers[].followmeTimer = 0 (L5060–5061).
	_last_attacker.clear()
	_last_attacker_move.clear()
	_last_attacker_hp_before.clear()
	_follow_me_targets[0] = -1
	_follow_me_targets[1] = -1
	for _hi in range(_helping_hand.size()):
		_helping_hand[_hi] = false

	_turn_order = _combatants.duplicate()

	# Record actor→side and actor→combatant-index mappings before any switches.
	# _actor_sides: used for party lookup (0 or 1); _actor_indices: used for
	# _chosen_moves / _chosen_switch_slots / _chosen_targets indexing (0..3).
	# M14a: _actor_sides now stores the actual SIDE (i / _active_per_side),
	#   not the combatant index. Combatant index is in _actor_indices.
	_actor_sides = {}
	_actor_indices = {}
	for i in range(_combatants.size()):
		_actor_sides[_combatants[i]] = i / _active_per_side
		_actor_indices[_combatants[i]] = i

	var tiebreak: Dictionary = {}
	for mon in _combatants:
		tiebreak[mon] = randi()

	# M17n-3: Quick Draw's roll and Mycelium Might's status-move-gated slow-effect
	# must each be evaluated EXACTLY ONCE per battler per turn — not re-derived per
	# pairwise comparison, which could otherwise make the sort non-transitive — so
	# both are precomputed here into per-mon Dictionaries, the same pattern the
	# pre-rolled `tiebreak` dict right above already establishes. `ng_active` is
	# likewise hoisted so the comparator closure below can just read it (a safe,
	# read-only scalar capture — the documented lambda-scalar-capture pitfall only
	# bites on IN-closure mutation, never on reading a value fixed before the
	# closure is defined).
	var ng_active: bool = _is_neutralizing_gas_active()
	var quick_effect: Dictionary = {}
	var slow_effect: Dictionary = {}
	for mon in _combatants:
		var midx: int = _actor_indices.get(mon, _combatants.find(mon))
		var chosen_move: MoveData = \
				_chosen_moves[midx] if _chosen_switch_slots[midx] < 0 else null
		# M18l: Quick Claw (item) / Full Incense & Lagging Tail (item) OR'd in
		# alongside their ability equivalents — mirrors source's own
		# battler1HasQuickEffect = quickDraw || usedCustapBerry and
		# battler1HasSlowEffect = battler1HasStallingAbility || laggingTail
		# (battle_main.c L4786-4791): ability and item flags are combined into the
		# exact same boolean BEFORE the comparator ever runs, not checked separately.
		# M18c: Custap Berry — deterministic, HP-gated act-first, OR'd into the same
		# quick_effect boolean. Unlike Quick Claw (never consumed — not a berry),
		# Custap IS a berry and is consumed the moment it contributes to
		# quick_effect being true — evaluated/consumed exactly once here, matching
		# this precompute's own "exactly once per battler per turn" requirement
		# (the same reasoning [M17n-3] documented for why this loop exists at all).
		var custap_item: ItemData = ItemManager.custap_berry_activates(mon, ng_active)
		quick_effect[mon] = AbilityManager.quick_draw_activates(
				mon, chosen_move, ng_active, _force_quick_draw_roll) \
				or ItemManager.quick_claw_activates(mon, ng_active, _force_quick_claw_roll) \
				or custap_item != null
		if custap_item != null:
			_consume_item(mon)
		slow_effect[mon] = AbilityManager.has_slow_turn_order_effect(
				mon, chosen_move, ng_active) \
				or ItemManager.has_slow_turn_order_item(mon, ng_active)

	_turn_order.sort_custom(func(a: BattlePokemon, b: BattlePokemon) -> bool:
		# M14a: use _actor_indices (combatant index 0..N-1) to look up chosen actions,
		# not _actor_sides (which is now 0 or 1, not the combatant position).
		var ia: int = _actor_indices.get(a, _combatants.find(a))
		var ib: int = _actor_indices.get(b, _combatants.find(b))
		var a_switch: bool = _chosen_switch_slots[ia] >= 0
		var b_switch: bool = _chosen_switch_slots[ib] >= 0

		# M16e: Pursuit interception — a queued Pursuit move on the OPPOSING side of a
		# switcher must strike before the switch resolves, overriding the normal
		# switches-always-first rule. Source: Cmd_jumpifnopursuitswitchdmg
		# (battle_script_commands.c L8494) reorders the pursuer to the front right as the
		# switch action is about to run; GEN_LATEST (B_PURSUIT_TARGET >= GEN_4) means ANY
		# opposing Pursuit user intercepts, not only one that specifically targeted the
		# switcher. See _pursuit_targets_switcher() for the exact condition.
		if b_switch and not a_switch and _pursuit_targets_switcher(ia, ib):
			return true  # a (the pursuer) goes first
		if a_switch and not b_switch and _pursuit_targets_switcher(ib, ia):
			return false  # b (the pursuer) goes first

		# Switch actions before all move actions.
		# Source: battle_main.c L4967-4990 — items/switches placed before moves
		# in gActionsByTurnOrder; speed sort only runs between move actors (L5004-5015).
		if a_switch != b_switch:
			return a_switch  # a goes first if a is switching

		# Both switching: side 0 before side 1 (battler iteration order in source).
		if a_switch:
			return ia < ib

		# Both using moves: priority bracket → effective speed → pre-rolled tiebreak.
		# M16d: Trick Room inverts ONLY the speed tiebreak within a shared priority
		# bracket — priority itself is compared first and is completely unaffected.
		# Source: battle_main.c :: GetWhichBattlerFasterArgs (L4775-4821): `if (priority1
		#   == priority2) { ... speed comparison, inverted under STATUS_FIELD_TRICK_ROOM
		#   ... } else if (priority1 < priority2) strikesFirst = -1; else strikesFirst = 1;`
		#   — the priority branch runs first and never consults Trick Room at all.
		# M17n-3: effective priority now includes Gale Wings/Prankster/Triage's
		# per-move bonus (mirrors GetBattleMovePriority, battle_main.c L4735-4775),
		# not just the move's own raw data priority.
		var move_a: MoveData = _chosen_moves[ia]
		var move_b: MoveData = _chosen_moves[ib]
		var pa: int = (move_a.priority + AbilityManager.move_priority_bonus(a, move_a, ng_active)) \
				if move_a else 0
		var pb: int = (move_b.priority + AbilityManager.move_priority_bonus(b, move_b, ng_active)) \
				if move_b else 0
		if pa != pb:
			return pa > pb
		# M17n-3: Quick Draw (always first) / Stall & Mycelium Might (always last),
		# extended by M18l with Quick Claw / Full Incense / Lagging Tail (items,
		# OR'd into the same quick_effect/slow_effect dicts above) — all within a
		# tied priority bracket, checked strictly BEFORE the speed
		# comparison, mirroring source's own ordering exactly (battle_main.c
		# L4786-4800: quick-effect check, then slow-effect check, then speed).
		if quick_effect[a] and not quick_effect[b]:
			return true
		if quick_effect[b] and not quick_effect[a]:
			return false
		if slow_effect[a] and not slow_effect[b]:
			return false
		if slow_effect[b] and not slow_effect[a]:
			return true
		var eff_w: int = _effective_weather()
		var sa: int = StatusManager.effective_speed(a, eff_w, ng_active)
		var sb: int = StatusManager.effective_speed(b, eff_w, ng_active)
		if sa != sb:
			return sa < sb if trick_room_turns > 0 else sa > sb
		return tiebreak[a] > tiebreak[b]
	)
	_current_actor_index = 0
	_set_phase(BattlePhase.ACTION_EXECUTION)


func _phase_action_execution() -> void:
	# Skip fainted actors in a loop so the phase always changes.
	# M14a: in doubles a slot can be permanently fainted with no bench replacement,
	# so fainted skips may happen every turn. Re-dispatching to ACTION_EXECUTION would
	# trigger the advance() safety guard (_phase == phase_before → break), halting the
	# battle. A while loop here guarantees we exit with a different phase each dispatch.
	while _current_actor_index < _turn_order.size() \
			and _turn_order[_current_actor_index].fainted:
		_current_actor_index += 1

	if _current_actor_index >= _turn_order.size():
		_set_phase(BattlePhase.END_OF_TURN)
		return

	var actor: BattlePokemon = _turn_order[_current_actor_index]

	# M9/M14a: check if this actor chose to switch this turn.
	# Use combatant index (not side) to look up switch slots and invoke the switch.
	var actor_idx: int = _actor_indices.get(actor, _combatants.find(actor))
	if actor_idx >= 0 and _chosen_switch_slots[actor_idx] >= 0:
		var slot: int = _chosen_switch_slots[actor_idx]
		_chosen_switch_slots[actor_idx] = -1
		_do_voluntary_switch(actor_idx, slot)
		_current_actor_index += 1
		_set_phase(BattlePhase.FAINT_CHECK)
		return

	_set_phase(BattlePhase.PRE_MOVE_CHECKS)


func _phase_pre_move_checks() -> void:
	var actor: BattlePokemon = _turn_order[_current_actor_index]

	if actor.fainted:
		_set_phase(BattlePhase.MOVE_EXECUTION)
		return

	# Status pre-move checks — source: battle_move_resolution.c canceler chain
	# Order: sleep → freeze → confusion → paralysis → infatuation (matching source
	# canceler order — [M18.5d-2] added infatuation as the final check)
	# Pass chosen_move so pre_move_check gates the freeze block on !MoveThawsUser
	# (source L172); a thaws_user move skips the 20% roll and leaves the Pokémon
	# frozen-but-acting; check_user_thaw in MOVE_EXECUTION then thaws it.
	var chosen_move: MoveData = _chosen_moves[_combatants.find(actor)]
	var ng_active: bool = _is_neutralizing_gas_active()
	var check: Dictionary = StatusManager.pre_move_check(
			actor, null, null, null, null, chosen_move, ng_active)

	if check["self_hit_damage"] > 0:
		var dmg: int = check["self_hit_damage"]
		actor.current_hp = max(0, actor.current_hp - dmg)
		confusion_self_hit.emit(actor, dmg)

	if not check["can_move"]:
		var reason: String
		if check["loafing"]:
			reason = "loafing"
		elif check["flinched"]:
			reason = "flinched"
			# M17b: Steadfast — flinching raises the flinched Pokémon's own Speed +1.
			# Source: battle_move_resolution.c :: CancelerFlinch (L303-307).
			if AbilityManager.effective_ability_id(actor, ng_active) == AbilityManager.ABILITY_STEADFAST:
				var sf_actual: int = StatusManager.apply_stat_change(
						actor, BattlePokemon.STAGE_SPEED, 1, null, ng_active)
				if sf_actual != 0:
					stat_stage_changed.emit(actor, BattlePokemon.STAGE_SPEED, sf_actual)
					ability_triggered.emit(actor, "steadfast")
		elif actor.status == BattlePokemon.STATUS_PARALYSIS:
			reason = "paralyzed"
		elif actor.status == BattlePokemon.STATUS_SLEEP:
			reason = "asleep"
		elif actor.status == BattlePokemon.STATUS_FREEZE:
			reason = "frozen"
		elif check["infatuated_stuck"]:
			reason = "infatuated"
		else:
			reason = "confused"
		move_skipped.emit(actor, reason)
		_current_actor_index += 1
		_set_phase(BattlePhase.FAINT_CHECK)
		return

	_set_phase(BattlePhase.MOVE_EXECUTION)


func _phase_move_execution() -> void:
	var attacker: BattlePokemon = _turn_order[_current_actor_index]
	# M17g: computed once for the whole function — every ability check below (Baton
	# Pass switch-in, the generic stat-change handler, accuracy, Growth/Minimize/
	# Defense Curl self-buffs, type immunity) shares the same field-wide snapshot.
	var ng_active: bool = _is_neutralizing_gas_active()

	if attacker.fainted:
		_current_actor_index += 1
		_set_phase(BattlePhase.ACTION_EXECUTION)
		return

	# M14a: use combatant index for move/target lookup; derive side from that.
	var attacker_idx: int = _actor_indices.get(attacker, _combatants.find(attacker))
	var attacker_side: int = attacker_idx / _active_per_side
	var defender: BattlePokemon = _combatants[_chosen_targets[attacker_idx]]
	var move: MoveData = _chosen_moves[attacker_idx]

	# M14a: if chosen target fainted earlier in this turn (doubles only — in singles
	# the only opponent slot has a replacement or the battle has already ended),
	# redirect to the first non-fainted opposing slot.
	if defender.fainted:
		var opp_start: int = (1 - attacker_side) * _active_per_side
		var redirect: BattlePokemon = null
		for fi in range(_active_per_side):
			var cand: BattlePokemon = _combatants[opp_start + fi]
			if not cand.fainted:
				redirect = cand
				break
		if redirect == null:
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return
		defender = redirect

	# M14b: Follow Me / Rage Powder redirect — single-target damaging moves aimed at
	# a side with an active Follow Me user are redirected to that user instead.
	# Source: IsAffectedByFollowMe (battle_move_resolution.c L799):
	#   redirects TARGET_SELECTED/SMART/OPPONENT/RANDOM moves; spread moves bypass entirely.
	# Source: GetBattleMoveTarget (battle_util.c L5529): check fires at target resolution.
	# Only applies to moves with power > 0 (damaging). Status moves targeting the opponent
	# can also be redirected in source, but limit to damaging moves for M14b scope.
	# M17l: Propeller Tail / Stalwart bypass BOTH this AND the Lightning Rod/Storm Drain
	# redirect below entirely (source: IsAffectedByFollowMe's own gate, L809-810, and
	# HandleMoveTargetRedirection's redirect-loop condition, L872-873, both exclude a
	# Propeller-Tail/Stalwart-holding attacker identically).
	var followed_this_hit: bool = false
	if not move.is_spread and move.power > 0 and not AbilityManager.bypasses_redirection(attacker, ng_active):
		var def_side: int = 1 - attacker_side
		var fm_idx: int = _follow_me_targets[def_side]
		if fm_idx >= 0 and fm_idx < _combatants.size():
			var fm_user: BattlePokemon = _combatants[fm_idx]
			if not fm_user.fainted and fm_user != attacker:
				defender = fm_user
				followed_this_hit = true

		# M17l: Lightning Rod / Storm Drain redirect (doubles only) — only checked when
		# Follow Me/Rage Powder didn't already redirect this hit, matching source's
		# `gSideTimers[side].followmeTimer == 0` gate on entering this branch at all.
		if not followed_this_hit and _active_per_side > 1:
			var redirect_ally: BattlePokemon = _get_ally(defender)
			var redirect_target: BattlePokemon = AbilityManager.resolve_redirect_target(
					defender, redirect_ally, attacker, move.type, ng_active)
			if redirect_target != null:
				defender = redirect_target

	# M12: Set choice lock immediately when a choice-item holder commits to a move.
	# Source: ProcessChoiceItem in battle_script_commands.c — fires before accuracy check.
	# Not set during a charge lock (charging_move handles that separately).
	if move != null and (ItemManager.is_choice_item(attacker, ng_active) \
				or AbilityManager.effective_ability_id(attacker, ng_active) == AbilityManager.ABILITY_GORILLA_TACTICS) \
			and attacker.choice_locked_move == null and attacker.charging_move == null:
		attacker.choice_locked_move = move

	# M17n-4: Protean/Libero — user's own type changes to match the move it's about to
	# use. Source: CANCELER_PROTEAN sits early in source's canceler chain (after
	# CANCELER_BIDE, before CANCELER_CHARGING — well before CANCELER_ACCURACY_CHECK/
	# CANCELER_NOT_FULLY_PROTECTED), so this fires unconditionally once the move is
	# chosen, regardless of whether the move will later miss or get Protected — placed
	# here, immediately after choice-lock, as the earliest point in this function that
	# runs for every non-disabled move attempt.
	if move != null:
		var protean_type: int = AbilityManager.protean_new_type(attacker, move, ng_active)
		if protean_type != TypeChart.TYPE_NONE:
			_set_mon_type(attacker, protean_type)
			attacker.used_protean_libero = true
			type_changed.emit(attacker, protean_type)
			var pl_id: int = AbilityManager.effective_ability_id(attacker, ng_active)
			ability_triggered.emit(attacker, "protean" if pl_id == AbilityManager.ABILITY_PROTEAN else "libero")

	# M7: Clear destiny_bond when the user acts — the bond only covers until their next
	# move. Source: destinyBond decremented at end of user's move execution; == 0 → expired.
	attacker.destiny_bond = false

	# M7: Disabled move check — fires before thaw, before accuracy, before everything.
	# Source: battle_move_resolution.c :: CancelerDisabled (L318)
	# A Pokémon locked into a charging move cannot be stopped by Disable: CancelerCharging
	# overrides gCurrentMove before CancelerDisabled evaluates it in the source.
	if attacker.disabled_move != null and move == attacker.disabled_move and attacker.charging_move == null:
		move_skipped.emit(attacker, "disabled")
		_current_actor_index += 1
		_set_phase(BattlePhase.FAINT_CHECK)
		return

	# M18s: Assault Vest — status-category moves are unusable. Source:
	# CheckMoveLimitations's unusableMoves bitmask makes this a true menu-legality
	# restriction (battle_util.c L1622-1624); this project has no such menu-filter
	# architecture, so it's implemented at execution time instead, matching the
	# exact fail-at-execution shape Disable (directly above) already established —
	# see ItemManager.holds_assault_vest's own doc comment for the full rationale.
	if move.category == 2 and ItemManager.holds_assault_vest(attacker, ng_active):
		move_skipped.emit(attacker, "assault_vest")
		_current_actor_index += 1
		_set_phase(BattlePhase.FAINT_CHECK)
		return

	# User-thaw: frozen Pokémon using a thawsUser move thaws before dealing damage.
	# Source: battle_move_resolution.c :: CancelerThaw (L586–622)
	if StatusManager.check_user_thaw(attacker, move):
		pokemon_thawed.emit(attacker)

	# M18u: Metronome item — consecutive-same-move-use counter, compared against
	# `attacker.last_move_used` BEFORE it gets overwritten for this move (every
	# `last_move_used = move` assignment site in this function runs LATER than
	# this point). Source colocates its own reset check at this exact spot,
	# immediately before PP deduction (battle_move_resolution.c L1006-1008) — see
	# HOLD_EFFECT_METRONOME's own doc comment for the simplified-reset-condition
	# caveat (this project only resets on a differing move, not source's broader
	# "OR unableToUseMove"). A FURTHER simplification from this project's early-
	# return architecture, not just the condition itself: a turn blocked EARLIER
	# than this point (Disabled, Assault-Vest-blocked) never reaches this check at
	# all, so the counter freezes at its prior value that turn rather than
	# resetting — source's single linear canceler pipeline always reaches an
	# equivalent point regardless of block reason; this project's early-return
	# shape does not. Flagged, not built around, given how many distinct block
	# reasons a fully faithful reset would need to intercept.
	if move == attacker.last_move_used:
		attacker.metronome_item_counter += 1
	else:
		attacker.metronome_item_counter = 0

	# M15 Task 3: Decrement PP (charge turn only for two-turn moves; never for Struggle).
	# Source: battle_script_commands.c :: Cmd_decrementmovepointvalue (L5960);
	#   CancelerPPDeduction skips if cv->move == MOVE_STRUGGLE (L979).
	# M17n-10: Pressure widens this to more than 1 PP — see
	# AbilityManager.pressure_pp_cost's own doc comment for the full source citation.
	if not move.is_struggle and attacker.charging_move == null:
		var move_idx: int = attacker.moves.find(move)
		if move_idx >= 0:
			var pp_cost: int = AbilityManager.pressure_pp_cost(
					move, attacker, defender, attacker_side, _combatants, _active_per_side, ng_active)
			attacker.use_pp(move_idx, pp_cost)

	# M18d: Leppa Berry — checked once per own move use, same MoveEnd cadence as
	# source's MoveEndSprayLeppaBlunder step. Scans ALL of the attacker's moves for
	# the FIRST zero-PP slot in move order (not necessarily the move just used,
	# matching ItemRestorePp's own scan-and-break loop exactly) — independent of
	# whether this specific use just deducted PP, matching source.
	var leppa_trigger: Dictionary = ItemManager.leppa_berry_restore(attacker, ng_active,
			AbilityManager.is_unnerve_active(_get_live_opponents(attacker), ng_active))
	if not leppa_trigger.is_empty():
		var lp_idx: int = leppa_trigger["move_index"]
		var lp_new_pp: int = min(attacker.moves[lp_idx].pp,
				attacker.current_pp[lp_idx] + leppa_trigger["amount"])
		attacker.current_pp[lp_idx] = lp_new_pp
		pp_restored.emit(attacker, lp_idx, lp_new_pp)
		_consume_item(attacker)

	# ── Two-turn charge/release ───────────────────────────────────────────────
	# Source: battle_move_resolution.c :: CancelerCharging (L1737)
	# Solar Beam shortcut: skip charge turn entirely in harsh sun.
	# Source: CanTwoTurnMoveFireThisTurn (L1664) — returns TRUE when
	#   weather & B_WEATHER_SUN and move has twoTurnAttackWeather == B_WEATHER_SUN.
	#   Semi-inv moves (Fly/Dig/Dive/Bounce) can NEVER fire early.
	var _solar_skip: bool = (
		move.is_solar_beam
		and attacker.charging_move == null
		and weather == WEATHER_SUN
	)
	# M18r: Power Herb — skips the charge turn of ANY two-turn move once, not
	# just Solar Beam in sun. Source: CancelerCharging's Power Herb branch
	# (battle_move_resolution.c L1778) is an `else if` checked only when
	# CanTwoTurnMoveFireThisTurn (the Solar-Beam-in-sun case) already failed —
	# `not _solar_skip` reproduces that ordering. No charge-turn stat boost
	# (Skull Bash) applies on a Power-Herb-skipped turn — source's Power Herb
	# branch is a structurally separate arm from the charge-setup branch that
	# grants it, and this project's `not _power_herb_skip` gate below excludes
	# the whole two-turn block the same way `not _solar_skip` already does.
	var _power_herb_skip: bool = (
		not _solar_skip
		and attacker.charging_move == null
		and ItemManager.holds_power_herb(attacker, ng_active)
	)
	if _power_herb_skip:
		_consume_item(attacker)
		item_effect_triggered.emit(attacker, "power_herb")
	if move.two_turn and not move.is_bide and not _solar_skip and not _power_herb_skip:
		if attacker.charging_move == null:
			# Charge-turn stat boost (Skull Bash: +1 Defense on charge turn only).
			# Source: moves_info.h MOVE_SKULL_BASH additionalEffects
			#   {MOVE_EFFECT_STAT_PLUS, .defense=1, .self=TRUE, .onChargeTurnOnly=TRUE}
			if move.charge_turn_defense_boost > 0:
				var actual_boost: int = StatusManager.apply_stat_change(
					attacker, BattlePokemon.STAGE_DEF, move.charge_turn_defense_boost, null, ng_active)
				if actual_boost != 0:
					stat_stage_changed.emit(attacker, BattlePokemon.STAGE_DEF, actual_boost)
			attacker.charging_move = move
			attacker.semi_invulnerable = move.semi_inv_state
			charge_started.emit(attacker, move)
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return
		else:
			attacker.charging_move = null
			attacker.semi_invulnerable = MoveData.SEMI_INV_NONE

	# ── Bide state machine ────────────────────────────────────────────────────
	# Source: battle_move_resolution.c :: CancelerBide (L1106)
	#   bideTurns=2 on setup; each activation decrements; release when bideTurns→0.
	#   Damage is accumulated from direct hits (not hits to substitute) via
	#   battle_script_commands.c L1634: gBideDmg[battler] += moveDamage.
	# gLastMoves[] is updated for Bide just like any other move.
	if move.is_bide:
		attacker.last_move_used = move
		if attacker.bide_turns == 0:
			# Turn 1: set up Bide — lock move via charging_move, set timer
			attacker.bide_turns = 2
			attacker.bide_damage = 0
			attacker.charging_move = move
			bide_started.emit(attacker)
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return
		else:
			attacker.bide_turns -= 1
			if attacker.bide_turns > 0:
				# Storing energy — wait one more turn
				bide_storing.emit(attacker)
				move_executed.emit(attacker, defender, move, 0)
				_current_actor_index += 1
				_set_phase(BattlePhase.FAINT_CHECK)
				return
			else:
				# Release turn — clear lock, deal 2× accumulated damage
				attacker.charging_move = null
				var bide_dmg: int = attacker.bide_damage * 2
				attacker.bide_damage = 0
				if bide_dmg == 0:
					move_effect_failed.emit(attacker, "bide_no_energy")
					move_executed.emit(attacker, defender, move, 0)
				else:
					_apply_fixed_dmg_to_target(attacker, defender, move, bide_dmg)
					bide_released.emit(attacker, bide_dmg)
				_current_actor_index += 1
				_set_phase(BattlePhase.FAINT_CHECK)
				return

	# ── Protect / Detect ──────────────────────────────────────────────────────
	# Source: battle_util.c :: CanUseMoveConsecutively (L10862)
	# Fires BEFORE accuracy check; success sets protect_active which blocks incoming moves.
	if move.is_protect:
		if _roll_protect_success(attacker.protect_consecutive):
			attacker.protect_active = true
			attacker.protect_consecutive += 1
			protected.emit(attacker)
		else:
			attacker.protect_consecutive = 0
			move_effect_failed.emit(attacker, "protect_failed")
		move_executed.emit(attacker, defender, move, 0)
		attacker.last_move_used = move
		_current_actor_index += 1
		_set_phase(BattlePhase.FAINT_CHECK)
		return

	# ── Protect blocking ──────────────────────────────────────────────────────
	# Source: battle_move_resolution.c :: CancelerTargetFailure :: IsBattlerProtected (L2009)
	# Fires between semi-inv check and accuracy check.
	# Moves with ignores_protect bypass this (e.g. Feint — M8+ scope; Roar/Whirlwind).
	if defender.protect_active and not move.ignores_protect:
		move_missed.emit(attacker, "protected")
		_current_actor_index += 1
		_set_phase(BattlePhase.FAINT_CHECK)
		return

	# ── OHKO (Guillotine / Horn Drill / Fissure / Sheer Cold) ─────────────────
	# Source: battle_util.c :: DoesOHKOMoveMissTarget (L10378)
	# Bypasses normal accuracy check entirely; has its own level-based formula.
	# Protect already blocked above; type immunity checked here before level fail.
	# On hit: damage = defender.current_hp regardless of stats.
	# Source: battle_util.c L7696: case EFFECT_OHKO: dmg = gBattleMons[ctx->battlerDef].hp
	if move.is_ohko:
		# Type immunity (ability-based and type chart) — same checks as damaging moves.
		if AbilityManager.blocks_move_type(defender, move.type, ng_active, attacker):
			move_missed.emit(attacker, "immune")
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return
		if move.type != TypeChart.TYPE_NONE:
			# M18t: same Iron Ball override DamageCalculator applies for ordinary
			# damaging moves — an OHKO Ground move (Fissure) against an
			# Iron-Ball-holding Flying-type must also bypass the raw Ground-vs-
			# Flying 0x table entry.
			var ohko_iron_ball_grounded: bool = ItemManager.holds_iron_ball(defender, ng_active)
			var ohko_eff: float = TypeChart.get_effectiveness(
					move.type, defender.species.types, false, false, ohko_iron_ball_grounded)
			if ohko_eff == 0.0:
				move_missed.emit(attacker, "immune")
				_current_actor_index += 1
				_set_phase(BattlePhase.FAINT_CHECK)
				return
		# Semi-invulnerable check: OHKO moves respect semi-invulnerability like normal moves.
		# Source: CancelerAccuracyCheck (battle_move_resolution.c L1993) — fires before OHKO check.
		# Fissure has damages_underground=true so it can hit Dig users.
		if _force_hit == null and defender.semi_invulnerable != MoveData.SEMI_INV_NONE:
			var ohko_can_hit: bool = (
				(defender.semi_invulnerable == MoveData.SEMI_INV_UNDERGROUND and move.damages_underground) or
				(defender.semi_invulnerable == MoveData.SEMI_INV_ON_AIR and move.damages_airborne) or
				(defender.semi_invulnerable == MoveData.SEMI_INV_UNDERWATER and move.damages_underwater))
			if not ohko_can_hit:
				move_missed.emit(attacker, "semi_invulnerable")
				attacker.last_move_used = move
				_current_actor_index += 1
				_set_phase(BattlePhase.FAINT_CHECK)
				return
		# Level check: fail if defender.level > attacker.level.
		# Source: DoesOHKOMoveMissTarget L10382: battlerDef.level > battlerAtk.level → fail.
		if defender.level > attacker.level:
			move_missed.emit(attacker, "ohko_failed")
			attacker.last_move_used = move
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return
		# M17n-5: Sturdy blocks OHKO moves outright — unconditional, any HP (distinct
		# from its OTHER half, surviving an ordinary lethal hit at full HP, in
		# _do_damaging_hit below). Source: battle_util.c L10399-10403, checked
		# immediately after the level check, before the custom accuracy roll.
		if AbilityManager.effective_ability_id(defender, ng_active, attacker) == AbilityManager.ABILITY_STURDY:
			move_missed.emit(attacker, "sturdy_blocks_ohko")
			attacker.last_move_used = move
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return
		# Custom accuracy roll: odds = move.accuracy + (atk.level − def.level), vs randi() % 100.
		# Source: DoesOHKOMoveMissTarget L10390: odds = GetMoveAccuracy + (atk.level − def.level).
		var ohko_acc: int = move.accuracy + (attacker.level - defender.level)
		var ohko_hit: bool
		if _force_hit != null:
			ohko_hit = bool(_force_hit)
		else:
			ohko_hit = randi() % 100 < ohko_acc
		if not ohko_hit:
			move_missed.emit(attacker, "accuracy")
			attacker.last_move_used = move
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return
		# Hit! Deal defender.current_hp as damage (instant KO).
		_last_attacker[defender] = attacker
		_last_attacker_move[defender] = move
		_last_attacker_hp_before[defender] = defender.current_hp
		_apply_fixed_dmg_to_target(attacker, defender, move, defender.current_hp)
		attacker.last_move_used = move
		_current_actor_index += 1
		_set_phase(BattlePhase.FAINT_CHECK)
		return

	# ── Rollout / Ice Ball power scaling ──────────────────────────────────────
	# Source: battle_util.c :: CalcRolloutBasePower (L6034-6042):
	#   basePower = move.power; basePower <<= rolloutTimer; if (defenseCurl) basePower *= 2.
	# rollout_turns holds the pre-hit consecutive-use count (0 = fresh start), carried over
	# from the previous turn's post-hit bookkeeping below. Computed before the accuracy
	# check since the power for THIS hit doesn't depend on this hit's own outcome.
	# _dmg_power_override feeds _do_damaging_hit below; -1 = use move.power unmodified.
	var _dmg_power_override: int = -1
	if move.is_rollout:
		var _rb_power: int = move.power
		for _ri in range(attacker.rollout_turns):
			_rb_power *= 2
		if attacker.defense_curled:
			_rb_power *= 2
		attacker.rollout_base_power = _rb_power
		_dmg_power_override = _rb_power

	# ── Magnitude: roll variable base power once per use ──────────────────────
	# Source: battle_move_resolution.c :: CalculateMagnitudeDamage (L5196-5234) — weighted
	#   table {10,30,50,70,90,110,150} with bands {5,10,20,30,20,10,5}% respectively.
	if move.is_magnitude:
		_dmg_power_override = _roll_magnitude_power()

	# ── Pursuit: doubled power if the target is switching out this turn ──────
	# Source: battle_util.c L6180-6182 (EFFECT_PURSUIT base-power case).
	#   Turn-order interception (executing before the switch) is handled in
	#   _phase_priority_resolution's sort_custom — by the time this runs, Pursuit's
	#   target hasn't actually switched yet, so _chosen_switch_slots is still set for the
	#   pursued switcher (it's only cleared when ITS OWN switch action executes, which
	#   happens AFTER the intercepting Pursuit user's action per the reordering above).
	if move.is_pursuit:
		var _pursuit_def_idx: int = _combatants.find(defender)
		if _pursuit_def_idx >= 0 and _chosen_switch_slots[_pursuit_def_idx] >= 0:
			_dmg_power_override = move.power * 2

	# ── Low Kick / Grass Knot: power from the TARGET's own weight only ───────
	# Source: battle_util.c, case EFFECT_LOW_KICK (L6216-6225).
	if move.is_low_kick_power:
		_dmg_power_override = _low_kick_power(defender.species.weight)

	# ── Heavy Slam / Heat Crash: power from the attacker/target weight ratio ─
	# Source: battle_util.c, case EFFECT_HEAT_CRASH (L6227-6233).
	if move.is_heat_crash_power:
		_dmg_power_override = _heat_crash_power(attacker.species.weight, defender.species.weight)

	# ── Return / Pika Papow / Veevee Volley: power from the attacker's own
	# friendship ──────────────────────────────────────────────────────────────
	# Source: battle_util.c, case EFFECT_RETURN (L6148-6150).
	if move.is_return_power:
		_dmg_power_override = _return_power(attacker.friendship)

	# ── Frustration: power from the INVERSE of the attacker's own friendship ─
	# Source: battle_util.c, case EFFECT_FRUSTRATION (L6151-6153).
	if move.is_frustration_power:
		_dmg_power_override = _frustration_power(attacker.friendship)

	# ── Priority-move-block (Dazzling / Queenly Majesty / Armor Tail) ────────────
	# Source: battle_move_resolution.c :: CancelerPriorityBlock (L1511-1548), dispatched
	# BEFORE CancelerAccuracyCheck in source's canceler chain — inserted at the same
	# relative point here. Side-wide: checks both the move's actual target and that
	# target's doubles partner.
	if AbilityManager.blocks_priority_move(defender, _get_ally(defender), attacker, move, ng_active):
		move_effect_failed.emit(attacker, "priority_blocked")
		ability_triggered.emit(defender, "dazzling_family")
		move_executed.emit(attacker, defender, move, 0)
		attacker.last_move_used = move
		_current_actor_index += 1
		_set_phase(BattlePhase.FAINT_CHECK)
		return

	# ── Move-flag immunity (Soundproof / Bulletproof) ────────────────────────────
	# Source: battle_util.c :: CanAbilityAbsorbMove (L2282-2289) — same dispatch group
	# as Levitate/the absorb family, checked here (not inside DamageCalculator) since
	# it must apply uniformly to BOTH damaging AND status moves (Growl/Roar/Whirlwind
	# are all sound_move status moves) — one choke point, not two.
	if AbilityManager.blocks_move_flag(defender, move, ng_active, attacker):
		move_effect_failed.emit(defender, "move_flag_blocked")
		ability_triggered.emit(defender, "soundproof_bulletproof")
		move_executed.emit(attacker, defender, move, 0)
		attacker.last_move_used = move
		_current_actor_index += 1
		_set_phase(BattlePhase.FAINT_CHECK)
		return

	# ── Accuracy check ────────────────────────────────────────────────────────
	# Source: battle_script_commands.c :: Cmd_accuracycheck (L1058)
	# Includes semi-invulnerable miss check (source: CancelerAccuracyCheck L1993).
	# M18c: Micle Berry's boost applies to exactly this one check, hit or miss —
	# clear it unconditionally right after, consuming it here regardless of outcome.
	# M18j: Zoom Lens needs to know whether the TARGET has already acted this
	# turn — resolved via the same _turn_order/_current_actor_index position
	# tracking _is_last_to_move already established for Analytic ([M17n-5]).
	var m18c_accuracy_hit: bool = StatusManager.check_accuracy(
			attacker, defender, move, _force_hit, ng_active, _effective_weather(),
			_has_target_already_acted(defender))
	attacker.micle_boost_active = false
	if not m18c_accuracy_hit:
		# Source: SetSameMoveTurnValues, case EFFECT_ROLLOUT (L4899): increment requires
		#   IsAnyTargetAffected() — a miss resets the consecutive-hit counter to 0.
		if move.is_rollout:
			attacker.rollout_turns = 0
		move_missed.emit(attacker, "accuracy")
		# M18r: Blunder Policy — +2 Speed on the holder when its own move misses
		# via THIS accuracy check specifically. OHKO moves never reach this point
		# at all (move.is_ohko returns early at the OHKO block above, L1098), so
		# no separate exclusion check is needed here — it's structural, matching
		# source's `moveEffect != EFFECT_OHKO` guard by construction rather than
		# by an explicit runtime check.
		if ItemManager.holds_blunder_policy(attacker, ng_active):
			var bp_actual: int = StatusManager.apply_stat_change(
					attacker, BattlePokemon.STAGE_SPEED, 2, null, ng_active)
			if bp_actual != 0:
				stat_stage_changed.emit(attacker, BattlePokemon.STAGE_SPEED, bp_actual)
				_consume_item(attacker)
		_current_actor_index += 1
		_set_phase(BattlePhase.FAINT_CHECK)
		return

	# ── Roar / Whirlwind ─────────────────────────────────────────────────────
	# Source: data/moves_info.h MOVE_ROAR / MOVE_WHIRLWIND :: .effect = EFFECT_ROAR
	# Source: battle_script_commands.c L7421 — gProtectStructs[target].forcedSwitch = TRUE
	# Fails if defender has no valid non-fainted switch-in (no party members left).
	# priority = -6 means Roar/Whirlwind always go last; they bypass Protect/Substitute.
	if move.is_roar:
		# M17n-10: Guard Dog blocks the forced switch entirely — see
		# AbilityManager.blocks_forced_switch's own doc comment for the source
		# citation. Checked before the party-slot lookup below since a blocked Roar
		# never needs one.
		if AbilityManager.blocks_forced_switch(defender, attacker, ng_active):
			move_effect_failed.emit(attacker, "guard_dog_blocks_switch")
			ability_triggered.emit(defender, "guard_dog")
			move_executed.emit(attacker, defender, move, 0)
			attacker.last_move_used = move
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return
		var def_side: int = 1 - attacker_side
		var def_party: BattleParty = _parties[def_side]
		var rand_slot: int = def_party.get_random_non_fainted_not_active(_force_roar_rng)
		if rand_slot < 0:
			move_effect_failed.emit(attacker, "no_switch_target")
		else:
			var old_defender: BattlePokemon = defender
			# M14b: force out the targeted combatant's field slot, not always slot 0.
			# Source: Cmd_BS_JumpIfRoarFails (battle_script_commands.c L7426):
			#   gProtectStructs[gBattlerTarget].forcedSwitch = TRUE — applies to the
			#   actual targeted battler, not a hardcoded position.
			var def_field_slot: int = _combatants.find(defender) % _active_per_side
			_do_forced_switch_in(def_side, rand_slot, def_field_slot)
			forced_switch.emit(old_defender, _parties[def_side].get_active_at(def_field_slot))
		move_executed.emit(attacker, defender, move, 0)
		attacker.last_move_used = move
		_current_actor_index += 1
		_set_phase(BattlePhase.FAINT_CHECK)
		return

	# ── Baton Pass ────────────────────────────────────────────────────────────
	# Source: data/moves_info.h MOVE_BATON_PASS :: .effect = EFFECT_BATON_PASS
	# Source: battle_main.c :: SwitchInClearSetData (L3117) — stat stages preserved,
	#   confusionTurns / substituteHP explicitly re-applied (L3146–3185).
	# Fails if attacker's party has no valid switch-in target.
	# Switch-in abilities (Intimidate) fire for the incoming Pokémon.
	if move.is_baton_pass:
		var att_party: BattleParty = _parties[attacker_side]
		if not att_party.has_valid_switch_target():
			move_effect_failed.emit(attacker, "no_switch_target")
			move_executed.emit(attacker, defender, move, 0)
			attacker.last_move_used = move
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return
		var saved: Dictionary = _baton_pass_save(attacker)
		# M17i: Regenerator/Natural Cure fire here too — source's BattleScript_EffectBatonPass
		# reaches the same `switchoutabilities BS_ATTACKER` call as an ordinary switch.
		_apply_switch_out_abilities(attacker)
		_switch_out_clear(attacker)
		# Determine which slot to bring in.
		var bp_slot: int = _get_baton_pass_slot(attacker_idx)
		var bp_field_slot: int = attacker_idx % _active_per_side
		att_party.active_indices[bp_field_slot] = bp_slot
		_combatants[attacker_idx] = att_party.get_active_at(bp_field_slot)
		var incoming: BattlePokemon = _combatants[attacker_idx]
		_baton_pass_apply(incoming, saved)
		_reset_mon_type(incoming)
		pokemon_switched_out.emit(attacker, attacker_side)
		pokemon_switched_in.emit(incoming, attacker_side, bp_slot)
		baton_passed.emit(attacker, incoming)
		# Switch-in hazards then abilities fire for the incoming Pokémon.
		_apply_switch_in_hazards(incoming, attacker_side)
		# M17g: recomputed fresh (not the outer `ng_active`) since `incoming` has just
		# replaced `attacker` in `_combatants` — if `incoming` itself holds Neutralizing
		# Gas, it should already suppress its own switch-in triggers' evaluation here,
		# matching source's switch-in dispatch order (Neutralizing Gas's own activation
		# is processed before ABILITYEFFECT_ON_SWITCHIN — battle_switch_in.c L56/L277).
		var bp_ng_active: bool = _is_neutralizing_gas_active()
		var bp_si_result: Dictionary = AbilityManager.try_switch_in(
				incoming, defender, _get_ally(defender), bp_ng_active)
		if bp_si_result["atk_change"] != 0:
			stat_stage_changed.emit(defender, BattlePokemon.STAGE_ATK, bp_si_result["atk_change"])
			ability_triggered.emit(incoming, "intimidate")
		if bp_si_result["opponent_guard_dog_change"] != 0:
			stat_stage_changed.emit(defender, BattlePokemon.STAGE_ATK, bp_si_result["opponent_guard_dog_change"])
			ability_triggered.emit(defender, "guard_dog")
			ability_triggered.emit(incoming, "intimidate")
		if bp_si_result["mirror_armor_reflect_change"] != 0:
			stat_stage_changed.emit(incoming, BattlePokemon.STAGE_ATK, bp_si_result["mirror_armor_reflect_change"])
			ability_triggered.emit(bp_si_result["mirror_armor_holder"], "mirror_armor")
			ability_triggered.emit(incoming, "intimidate")
		if bp_si_result["opponent_speed_change"] != 0:
			stat_stage_changed.emit(defender, BattlePokemon.STAGE_SPEED, bp_si_result["opponent_speed_change"])
			ability_triggered.emit(defender, "rattled")
		if bp_si_result["opponent_defiant_change"] != 0:
			stat_stage_changed.emit(defender, bp_si_result["opponent_defiant_stat"], bp_si_result["opponent_defiant_change"])
			ability_triggered.emit(defender, "defiant_competitive")
		if bp_si_result["cured_own_poison"]:
			ability_triggered.emit(incoming, "pastel_veil")
		if bp_si_result["cured_status"]:
			ability_triggered.emit(incoming, "immunity_family_cure")
		if bp_si_result["cured_confusion"]:
			ability_triggered.emit(incoming, "own_tempo_cure")
		if bp_si_result["cured_infatuation"]:
			ability_triggered.emit(incoming, "oblivious_cure")
		var bp_sss_actual: int = AbilityManager.try_switch_in_evasion(incoming, defender, bp_ng_active)
		if bp_sss_actual != 0:
			stat_stage_changed.emit(defender, BattlePokemon.STAGE_EVASION, bp_sss_actual)
			ability_triggered.emit(incoming, "supersweet_syrup")
		var bp_set_w: int = AbilityManager.get_switch_in_weather(incoming, bp_ng_active)
		if bp_set_w != WEATHER_NONE and try_set_weather(bp_set_w, incoming):
			weather_set.emit(incoming, bp_set_w)
			_notify_weather_changed()
		# M17h: Trace is NOT wired into this separate Baton Pass switch-in block, the
		# SAME known, already-documented simplification `[M17b]` accepted for Download
		# and `[M17c]` accepted for Hospitality in this exact code path — not a new gap
		# introduced by this tier. M17n-10: Screen Cleaner joins this same known-gap
		# list (also not wired here) — Guard Dog, by contrast, needed no separate
		# wiring since it lives inside the shared `try_switch_in` call just above and
		# is handled by the `opponent_guard_dog_change` branch immediately above this.
		# M17n-11: Costar joins Screen Cleaner's known-gap list (not wired into this
		# Baton Pass block either); Mirror Armor, like Guard Dog, needed no separate
		# wiring for the SAME reason (lives inside the shared `try_switch_in` call,
		# handled by the `mirror_armor_reflect_change` branch immediately above).
		move_executed.emit(attacker, defender, move, 0)
		_current_actor_index += 1
		_set_phase(BattlePhase.FAINT_CHECK)
		return

	# ── Metronome: select random move and execute it ──────────────────────────
	# Source: battle_move_resolution.c :: GetMetronomeMove (L4998)
	#   Picks a random move not banned by metronomeBanned flag (BAN_METRONOME in our system).
	# The called move replaces the original move object for the remainder of the execution path —
	# it routes through all normal effect handlers (damage, status, stat change, etc.).
	# `move_called` signal fires with the chosen move before execution.
	# If pool is empty (degenerate case): `move_effect_failed("metronome_no_moves")`.
	# `last_move_used` is set to the ORIGINAL Metronome move (not the called move) — consistent with
	# source where gLastMoves[] tracks the move slot used, not the called move.
	# Wait: actually the code sets `attacker.last_move_used = move` AFTER the Metronome redirect,
	# where `move` has been overwritten with the called move. This means last_move_used = called move.
	# This is fine for M7; revisit if Encore/Disable interactions with Metronome-called moves matter.
	if move.is_metronome:
		var called_move: MoveData = _pick_metronome_move()
		if called_move == null:
			move_effect_failed.emit(attacker, "metronome_no_moves")
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return
		move_called.emit(attacker, called_move)
		move = called_move  # redirect to the called move for the rest of execution

	# ── Rollout / Ice Ball: interruption reset ────────────────────────────────
	# Source: battle_move_resolution.c :: SetSameMoveTurnValues `default` case
	#   (L4915-4917): using any move OTHER than Rollout unconditionally resets
	#   rolloutTimer to 0 — this is how switching moves breaks the power streak.
	if not move.is_rollout:
		attacker.rollout_turns = 0

	# Track the last move used by this Pokémon (for Disable / Encore targeting).
	# Source: gLastMoves[] is set after each successful move execution.
	attacker.last_move_used = move

	# ── Counter / Mirror Coat ─────────────────────────────────────────────────
	# Source: battle_util.c :: EFFECT_REFLECT_DAMAGE (L7670)
	#   damage = (physicalDmg - 1) * 200 / 100; physicalDmg = actual_damage + 1
	# Fail condition: no physical (Counter) or special (Mirror Coat) damage received
	#   this turn.  gProtectStructs[attacker].physicalDmg > 0.
	# In our system: last_physical_damage > 0 / last_special_damage > 0.
	if move.counter:
		if attacker.last_physical_damage == 0:
			move_effect_failed.emit(attacker, "no_damage_to_counter")
			move_executed.emit(attacker, defender, move, 0)
		else:
			_apply_fixed_dmg_to_target(attacker, defender, move, attacker.last_physical_damage * 2)
		_current_actor_index += 1
		_set_phase(BattlePhase.FAINT_CHECK)
		return

	if move.mirror_coat:
		if attacker.last_special_damage == 0:
			move_effect_failed.emit(attacker, "no_damage_to_counter")
			move_executed.emit(attacker, defender, move, 0)
		else:
			_apply_fixed_dmg_to_target(attacker, defender, move, attacker.last_special_damage * 2)
		_current_actor_index += 1
		_set_phase(BattlePhase.FAINT_CHECK)
		return

	if move.power > 0:
		# ── Damaging move ──────────────────────────────────────────────────────
		# M14b: spread moves hit all live opposing combatants independently.
		# Source: IsSpreadMove (include/battle.h L1163): TARGET_BOTH or TARGET_FOES_AND_ALLY.
		# Source: IsDoubleSpreadMove (battle_util.c L10662): numSpreadTargets > 1 AND spread.
		# Each target gets a full independent calc (accuracy, damage, secondary effects).
		if move.is_spread and _active_per_side > 1:
			# Count live targets on opposing side to determine if spread reduction applies.
			# Source: GetMoveTargetCount (battle_util.c L5982): counts non-absent (non-fainted).
			# Immune targets are alive → still count → spread reduction applies even if immune.
			var opp_start: int = (1 - attacker_side) * _active_per_side
			var live_target_count: int = 0
			for _fi in range(_active_per_side):
				var _c: BattlePokemon = _combatants[opp_start + _fi]
				if not _c.fainted and _c.current_hp > 0:
					live_target_count += 1
			var spread_dmg_reduction: bool = live_target_count >= 2
			var hh_boost: bool = _helping_hand[attacker_idx]
			for _fi in range(_active_per_side):
				var tgt: BattlePokemon = _combatants[opp_start + _fi]
				if tgt.fainted or tgt.current_hp <= 0:
					continue
				_do_damaging_hit(attacker, tgt, move, spread_dmg_reduction, hh_boost,
						_dmg_power_override)
		elif move.multi_hit or move.strike_count > 1:
			# [M18.5g] Multi-hit moves (Bullet Seed/Double Kick/Triple Kick/etc. family)
			# — see _do_multi_hit_sequence's own doc comment for the full mechanism.
			# None of the 31 in-scope moves are also spread moves (TARGET_SELECTED
			# throughout; Dragon Darts' TARGET_SMART doubles-redirect is a separate,
			# flagged-not-built doubles-only nuance — see gen_moves.py's own comment),
			# so this branch and the spread branch above are mutually exclusive in
			# practice, not just by construction.
			var hh_boost: bool = _helping_hand[attacker_idx]
			_do_multi_hit_sequence(attacker, defender, move, hh_boost, _dmg_power_override)
		else:
			# Single-target damaging move.
			var hh_boost: bool = _helping_hand[attacker_idx]
			_do_damaging_hit(attacker, defender, move, false, hh_boost, _dmg_power_override)

		# ── Rollout / Ice Ball: advance the consecutive-hit counter ───────────────
		# Source: SetSameMoveTurnValues, case EFFECT_ROLLOUT (L4899-4909): a successful
		#   hit increments rolloutTimer; reaching 5 resets it back to 0 (fresh start on the
		#   next use). The accuracy-check branch above already handles the miss-reset case.
		if move.is_rollout:
			attacker.rollout_turns += 1
			if attacker.rollout_turns >= 5:
				attacker.rollout_turns = 0
		# M15 Task 3: Struggle recoil — 1/4 max HP (not % of damage dealt).
		# Source: BattleScript_EffectRecoilHP (battle_script_commands.c L2534–2543).
		if move.is_struggle and not attacker.fainted:
			var struggle_recoil: int = max(1, attacker.max_hp / 4)
			attacker.current_hp = max(0, attacker.current_hp - struggle_recoil)
			recoil_damage.emit(attacker, struggle_recoil)
	else:
		# ── Status / stat-change / unique-effect move ─────────────────────────

		# ── Helping Hand ──────────────────────────────────────────────────────
		# Grants the user's ally a 1.5× base-power boost on their next damaging move.
		# Source: Cmd_trysethelpinghand (battle_script_commands.c L8850):
		#   fails if not doubles, ally is fainted, or ally has already acted this turn.
		#   Sets gProtectStructs[ally].helpingHand++ (cleared by TurnValuesCleanUp EOT).
		# Source: target = TARGET_ALLY (Gen 4+), priority = +5.
		if move.is_helping_hand:
			if _active_per_side < 2:
				move_effect_failed.emit(attacker, "not_doubles")
			else:
				var ally_idx: int = attacker_side * _active_per_side \
						+ (1 - attacker_idx % _active_per_side)
				var ally: BattlePokemon = _combatants[ally_idx]
				var ally_turn_pos: int = _turn_order.find(ally)
				var ally_has_acted: bool = ally_turn_pos >= 0 \
						and ally_turn_pos <= _current_actor_index
				if ally.fainted or ally_has_acted:
					move_effect_failed.emit(attacker, "helping_hand_failed")
				else:
					_helping_hand[ally_idx] = true
					helping_hand_used.emit(attacker, ally)
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Follow Me / Rage Powder ───────────────────────────────────────────
		# Redirects all incoming single-target moves toward the user this turn.
		# Source: Cmd_setforcedtarget (battle_script_commands.c L8748):
		#   gSideTimers[user_side].followmeTimer = 1; followmeTarget = user.
		# Source: target = TARGET_USER, priority = +2.
		if move.is_follow_me:
			_follow_me_targets[attacker_side] = attacker_idx
			follow_me_used.emit(attacker)
			move_executed.emit(attacker, attacker, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Substitute creation ───────────────────────────────────────────────
		# Source: battle_script_commands.c :: Cmd_setsubstitute (L7807)
		#   hp = maxHP / 4; fails if hp == 0 or current_hp <= hp.
		if move.creates_substitute:
			var sub_hp: int = attacker.max_hp / 4
			if attacker.substitute_hp > 0:
				move_effect_failed.emit(attacker, "already_substitute")
			elif attacker.current_hp <= sub_hp:
				move_effect_failed.emit(attacker, "not_enough_hp")
			else:
				attacker.current_hp -= sub_hp
				attacker.substitute_hp = sub_hp
				substitute_created.emit(attacker, sub_hp)
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Destiny Bond ──────────────────────────────────────────────────────
		# Source: battle_scripts_1.s :: BattleScript_EffectDestinyBond
		#   setvolatile BS_ATTACKER, VOLATILE_DESTINY_BOND, 2
		# Fail: consecutive use (Gen 7+) — source: DoesDestinyBondFail checks destinyBond > 0.
		# We clear destiny_bond at the START of the user's action, so if they use it again
		# on the same turn it's already clear. The consecutive-fail applies turn-to-turn:
		# after destiny_bond is set (true) and then cleared (act), re-using immediately
		# was handled by the clear-on-act logic. For test coverage, we'll check a flag
		# on the attacker.
		if move.destiny_bond:
			# Note: destiny_bond is cleared at the top of this function (attacker.destiny_bond=false).
			# A second consecutive Destiny Bond use on the SAME turn can't happen in 1v1.
			# "Consecutive" in source means using it AFTER the first expires; for M7 simplicity,
			# always succeed (the fail case requires multi-turn tracking not worth the complexity).
			attacker.destiny_bond = true
			destiny_bond_set.emit(attacker)
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# M17n-1: Aroma Veil (self OR ally, IsAbilityOnSide-shaped) blocks Disable and
		# Encore outright — see MoveData.blocked_by_aroma_veil's doc comment for the
		# source-verified AI-vs-execution-engine discrepancy this is built against.
		var defender_ally_av: BattlePokemon = _get_ally(defender)
		var aroma_veil_blocks: bool = move.blocked_by_aroma_veil and (
				AbilityManager.effective_ability_id(defender, ng_active, attacker) == AbilityManager.ABILITY_AROMA_VEIL
				or (defender_ally_av != null and not defender_ally_av.fainted
						and AbilityManager.effective_ability_id(defender_ally_av, ng_active, attacker) == AbilityManager.ABILITY_AROMA_VEIL))

		# ── Disable ───────────────────────────────────────────────────────────
		# Source: battle_script_commands.c :: Cmd_disablelastusedattack (L7898)
		#   disabledMove = lastMoves[target]; disableTimer = 4 (Gen 5+)
		# Disable ignores substitute — source: moves_info.h MOVE_DISABLE.ignoresSubstitute=TRUE
		if move.is_disable:
			if aroma_veil_blocks:
				move_effect_failed.emit(defender, "aroma_veil_blocked")
				ability_triggered.emit(defender, "aroma_veil")
			elif defender.last_move_used == null or defender.disabled_move != null:
				move_effect_failed.emit(defender, "disable_failed")
			else:
				defender.disabled_move = defender.last_move_used
				defender.disable_turns = 4
				disabled.emit(defender, defender.disabled_move)
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Encore ────────────────────────────────────────────────────────────
		# Source: battle_script_commands.c :: Cmd_trysetencore (L7924)
		#   encoreTimer = 3 (target already acted; B_ENCORE_TIMER=4, minus 1)
		# Fails if: no last move, already encored, last move is encore-banned.
		# Blocked by substitute (Encore is NOT in ignoresSubstitute list).
		if move.is_encore:
			if aroma_veil_blocks:
				move_effect_failed.emit(defender, "aroma_veil_blocked")
				ability_triggered.emit(defender, "aroma_veil")
				move_executed.emit(attacker, defender, move, 0)
				_current_actor_index += 1
				_set_phase(BattlePhase.FAINT_CHECK)
				return
			# M17n-9: Infiltrator bypasses Substitute for every move (source's shared
			# IsSubstituteProtected chokepoint), Encore included.
			if defender.substitute_hp > 0 and not move.ignores_substitute \
					and not AbilityManager.bypasses_infiltrator_barriers(attacker, ng_active):
				move_missed.emit(attacker, "substitute")
			elif (defender.last_move_used == null
					or defender.encored_move != null
					or (defender.last_move_used.ban_flags & MoveData.BAN_ENCORE) != 0):
				move_effect_failed.emit(defender, "encore_failed")
			else:
				defender.encored_move = defender.last_move_used
				defender.encore_turns = 3
				encored.emit(defender, defender.encored_move)
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Attract ───────────────────────────────────────────────────────────
		# Source: battle_scripts_1.s :: BattleScript_EffectAttract (L2220+) ->
		#   Cmd_tryinfatuating (battle_script_commands.c L7613-7650). NOT the same
		# command as Disable/Encore's own `aroma_veil_blocks` var above -- Attract
		# needs Oblivious in the same gate as Aroma Veil, a combination that single
		# flag's shape doesn't cover, so this uses the dedicated
		# StatusManager.try_apply_attract / AbilityManager.attract_block_reason pair
		# instead (see move_data.gd's blocked_by_aroma_veil doc comment for the full
		# citation and the [M17n-1] mis-citation this tier corrected).
		# ignores_substitute=true in source (moves.json), matching Disable's own
		# shape above -- no substitute check needed here, unlike Encore's.
		if move.is_attract:
			var attract_result: String = StatusManager.try_apply_attract(
					defender, attacker, _get_ally(defender), ng_active, attacker, move)
			match attract_result:
				"oblivious", "aroma_veil":
					move_effect_failed.emit(defender, "attract_blocked")
					ability_triggered.emit(defender, attract_result)
				"already_infatuated", "not_opposite_gender":
					move_effect_failed.emit(defender, "attract_failed")
				_:
					infatuated.emit(defender)
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Restore HP (Recover / Slack Off / Heal Order) ─────────────────────
		# Source: battle_script_commands.c :: Cmd_tryhealhalfhealth (L7016)
		#   heal = GetNonDynamaxMaxHP(target) / 2; fails if current_hp == max_hp.
		if move.is_restore_hp:
			if attacker.current_hp >= attacker.max_hp:
				move_effect_failed.emit(attacker, "already_full_hp")
			else:
				var restore_heal: int = max(1, attacker.max_hp / 2)
				attacker.current_hp = min(attacker.max_hp, attacker.current_hp + restore_heal)
				drain_heal.emit(attacker, restore_heal)
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Focus Energy ──────────────────────────────────────────────────────
		# Source: battle_script_commands.c :: Cmd_setfocusenergy (L7718)
		#   volatiles.focusEnergy = TRUE; fails if already set.
		# Crit stage boost wired in DamageCalculator._roll_crit (+2 stages).
		if move.is_focus_energy:
			if attacker.focus_energy:
				move_effect_failed.emit(attacker, "already_focus_energy")
			else:
				attacker.focus_energy = true
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Growth ────────────────────────────────────────────────────────────
		# Source: moves_info.h MOVE_GROWTH (L2003): B_UPDATED_MOVE_DATA >= GEN_5 →
		#   raises ATK +1 AND SpATK +1 (Gen 5+). In harsh sun: +2 to both.
		# Source: battle_stat_change.c :: AdjustStatStage (L800):
		#   if EFFECT_GROWTH and weather == B_WEATHER_SUN → stage = 2.
		if move.is_growth:
			var growth_amt: int = 2 if weather == WEATHER_SUN else 1
			var g_atk: int = StatusManager.apply_stat_change(
					attacker, BattlePokemon.STAGE_ATK, growth_amt, null, ng_active)
			if g_atk != 0:
				stat_stage_changed.emit(attacker, BattlePokemon.STAGE_ATK, g_atk)
			var g_spatk: int = StatusManager.apply_stat_change(
					attacker, BattlePokemon.STAGE_SPATK, growth_amt, null, ng_active)
			if g_spatk != 0:
				stat_stage_changed.emit(attacker, BattlePokemon.STAGE_SPATK, g_spatk)
			if g_atk == 0 and g_spatk == 0:
				move_effect_failed.emit(attacker, "stat_limit")
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Minimize ──────────────────────────────────────────────────────────
		# Source: moves_info.h MOVE_MINIMIZE additionalEffects {STAT_CHANGE_EFFECT_PLUS,
		#   .evasion = 2} (B_MINIMIZE_EVASION >= GEN_5, GEN_LATEST config).
		# Source: battle_stat_change.c :: SetAdditionalEffectsOnStatChange, case
		#   EFFECT_MINIMIZE (L1000): volatiles.minimize = TRUE only if the evasion raise
		#   actually succeeded (MOVE_RESULT_STAT_CHANGED).
		if move.is_minimize:
			var min_actual: int = StatusManager.apply_stat_change(
					attacker, BattlePokemon.STAGE_EVASION, 2, null, ng_active)
			if min_actual != 0:
				stat_stage_changed.emit(attacker, BattlePokemon.STAGE_EVASION, min_actual)
				attacker.minimized = true
			else:
				move_effect_failed.emit(attacker, "stat_limit")
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Defense Curl ──────────────────────────────────────────────────────
		# Source: moves_info.h MOVE_DEFENSE_CURL additionalEffects
		#   {STAT_CHANGE_EFFECT_PLUS, .defense = 1}.
		# Source: battle_stat_change.c :: SetAdditionalEffectsOnStatChange, case
		#   EFFECT_DEFENSE_CURL (L997): volatiles.defenseCurl = TRUE unconditionally,
		#   regardless of whether the Defense raise itself succeeded.
		if move.is_defense_curl:
			var dc_actual: int = StatusManager.apply_stat_change(
					attacker, BattlePokemon.STAGE_DEF, 1, null, ng_active)
			if dc_actual != 0:
				stat_stage_changed.emit(attacker, BattlePokemon.STAGE_DEF, dc_actual)
			else:
				move_effect_failed.emit(attacker, "stat_limit")
			attacker.defense_curled = true
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Reflect ───────────────────────────────────────────────────────────
		# Source: battle_script_commands.c :: TrySetReflect (L2088-2106): fails (does not
		#   refresh) if SIDE_STATUS_REFLECT already set on the caster's side; else sets it
		#   with a 5-turn timer.
		if move.is_reflect:
			if _side_conditions[attacker_side]["reflect_turns"] > 0:
				move_effect_failed.emit(attacker, "already_reflect")
			else:
				# M18r: Light Clay — 8 turns instead of 5. Source: TrySetReflect
				# (battle_script_commands.c L2088-2106), checked on the SETTER.
				_side_conditions[attacker_side]["reflect_turns"] = \
						ItemManager.screen_turns(attacker, 5, ng_active)
				screen_set.emit(attacker_side, "reflect")
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Light Screen ─────────────────────────────────────────────────────
		# Source: battle_script_commands.c :: TrySetLightScreen (L2109-2127): same shape as
		#   TrySetReflect but SIDE_STATUS_LIGHTSCREEN / lightscreenTimer.
		if move.is_light_screen:
			if _side_conditions[attacker_side]["light_screen_turns"] > 0:
				move_effect_failed.emit(attacker, "already_light_screen")
			else:
				# M18r: Light Clay — 8 turns instead of 5. Source: TrySetLightScreen
				# (battle_script_commands.c L2109-2127), checked on the SETTER.
				_side_conditions[attacker_side]["light_screen_turns"] = \
						ItemManager.screen_turns(attacker, 5, ng_active)
				screen_set.emit(attacker_side, "light_screen")
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Aurora Veil ──────────────────────────────────────────────────────
		# Source: battle_move_resolution.c (L1191-1193): fails outright unless
		#   GetWeather() & B_WEATHER_ICY_ANY — checked BEFORE the "already up" check (this
		#   project only models Hail, no separate Snow weather, so the gate is
		#   weather == WEATHER_HAIL). Source: BS_SetAuroraVeil (L13439-13462): fails only if
		#   SIDE_STATUS_AURORA_VEIL already set — independent of Reflect/Light Screen, so it
		#   can be set even if either (or both) of those are already up on the same side.
		if move.is_aurora_veil:
			if weather != WEATHER_HAIL:
				move_effect_failed.emit(attacker, "no_hail")
			elif _side_conditions[attacker_side]["aurora_veil_turns"] > 0:
				move_effect_failed.emit(attacker, "already_aurora_veil")
			else:
				# M18r: Light Clay — 8 turns instead of 5. Source: BS_SetAuroraVeil
				# (battle_script_commands.c L13439-13462), checked on the SETTER.
				_side_conditions[attacker_side]["aurora_veil_turns"] = \
						ItemManager.screen_turns(attacker, 5, ng_active)
				screen_set.emit(attacker_side, "aurora_veil")
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Spikes ────────────────────────────────────────────────────────────
		# Source: battle_script_commands.c :: Cmd_trysetspikes (L8373-8390): targets the
		#   OPPONENT's side (opposite of Reflect/Light Screen/Aurora Veil, which target the
		#   caster's own side); fails at 3 layers, else increments.
		if move.is_spikes:
			var spikes_side: int = 1 - attacker_side
			if _side_conditions[spikes_side]["spikes_layers"] >= 3:
				move_effect_failed.emit(attacker, "spikes_maxed")
			else:
				_side_conditions[spikes_side]["spikes_layers"] += 1
				hazard_set.emit(spikes_side, "spikes", _side_conditions[spikes_side]["spikes_layers"])
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Toxic Spikes ──────────────────────────────────────────────────────
		# Source: battle_script_commands.c :: Cmd_settoxicspikes (L9043-9059): targets the
		#   OPPONENT's side; fails at 2 layers, else increments.
		if move.is_toxic_spikes:
			var tspikes_side: int = 1 - attacker_side
			if _side_conditions[tspikes_side]["toxic_spikes_layers"] >= 2:
				move_effect_failed.emit(attacker, "toxic_spikes_maxed")
			else:
				_side_conditions[tspikes_side]["toxic_spikes_layers"] += 1
				hazard_set.emit(tspikes_side, "toxic_spikes",
						_side_conditions[tspikes_side]["toxic_spikes_layers"])
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Stealth Rock ──────────────────────────────────────────────────────
		# Source: battle_script_commands.c :: MOVE_EFFECT_STEALTH_ROCK case (L2707-2712):
		#   targets the OPPONENT's side; single application — fails if already up (no layers).
		if move.is_stealth_rock:
			var srock_side: int = 1 - attacker_side
			if _side_conditions[srock_side]["stealth_rock"]:
				move_effect_failed.emit(attacker, "stealth_rock_already_set")
			else:
				_side_conditions[srock_side]["stealth_rock"] = true
				hazard_set.emit(srock_side, "stealth_rock", 1)
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Trick Room ────────────────────────────────────────────────────────
		# Source: battle_script_commands.c :: HandleRoomMove (L9116-9121): TOGGLES rather
		#   than failing — using it again while active cancels it immediately instead of
		#   refreshing the timer.
		if move.is_trick_room:
			if trick_room_turns > 0:
				trick_room_turns = 0
				trick_room_ended.emit()
			else:
				trick_room_turns = 5
				trick_room_set.emit()
				# M18r: Room Service — fires for EVERY battler already on the field
				# (including the Trick Room user itself) the instant Trick Room is
				# SET, not just on a later switch-in. Source:
				# BattleScript_EffectTrickRoom unconditionally calls
				# BattleScript_TryRoomServiceLoop right after setroom
				# (data/battle_scripts_1.s L1296-1304) — a correction to this
				# tier's own plan doc, which named only the switch-in half. The
				# OTHER half (switch-in while Trick Room is already active) is
				# wired separately at the switch-in ability block.
				for rs_mon: BattlePokemon in _combatants:
					if rs_mon.fainted:
						continue
					if ItemManager.holds_room_service(rs_mon, ng_active):
						var rs_actual: int = StatusManager.apply_stat_change(
								rs_mon, BattlePokemon.STAGE_SPEED, -1, null, ng_active)
						if rs_actual != 0:
							stat_stage_changed.emit(rs_mon, BattlePokemon.STAGE_SPEED, rs_actual)
							_consume_item(rs_mon)
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Pain Split ────────────────────────────────────────────────────────
		# Source: battle_script_commands.c :: Cmd_painsplitdmgcalc (L7989-8006):
		#   hpDiff = (attacker.hp + target.hp) / 2 (integer division, floor). Both mons'
		#   current HP become hpDiff (final HP = min(hpDiff, own maxHP) reproduces source's
		#   PassiveDataHpUpdate: negative delta = heal clamped to maxHP, positive delta =
		#   damage — never reaches 0 since floor((a+b)/2) >= 1 whenever a,b >= 1).
		# Blocked by the target's Substitute — Pain Split has no ignoresSubstitute flag.
		if move.is_pain_split:
			# M17n-9: Infiltrator bypasses Substitute here too (shared chokepoint).
			if defender.substitute_hp > 0 and not move.ignores_substitute \
					and not AbilityManager.bypasses_infiltrator_barriers(attacker, ng_active):
				move_missed.emit(attacker, "substitute")
			else:
				var hp_diff: int = (attacker.current_hp + defender.current_hp) / 2
				attacker.current_hp = min(attacker.max_hp, hp_diff)
				defender.current_hp = min(defender.max_hp, hp_diff)
				pain_split_used.emit(attacker, defender)
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Conversion ────────────────────────────────────────────────────────
		# Source: battle_script_commands.c :: Cmd_tryconversiontypechange (L7449-7482),
		#   B_UPDATED_CONVERSION >= GEN_6 (GEN_LATEST) branch: user's type ← type of their
		#   FIRST populated move slot (literal moves[0] scan, no Curse/Struggle special
		#   case). Fails if the user is already that type. SET_BATTLER_TYPE makes the user
		#   mono-typed — this project models mono-type as [type, TYPE_NONE], matching the
		#   existing PokemonSpecies.types convention (see get_effectiveness's TYPE_NONE
		#   skip), not source's literal both-slots-equal representation (equivalent result).
		if move.is_conversion:
			var conv_type: int = TypeChart.TYPE_NONE
			for m: MoveData in attacker.moves:
				if m != null:
					conv_type = m.type
					break
			if conv_type == TypeChart.TYPE_NONE or conv_type in attacker.species.types:
				move_effect_failed.emit(attacker, "conversion_failed")
			else:
				_set_mon_type(attacker, conv_type)
				type_changed.emit(attacker, conv_type)
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Conversion 2 ──────────────────────────────────────────────────────
		# Source: battle_script_commands.c :: Cmd_settypetorandomresistance (L8009-8077),
		#   GEN_LATEST (B_UPDATED_CONVERSION_2 >= GEN_5) branch: uses the TARGET's last
		#   successfully used move — this project's existing `last_move_used` field reused
		#   directly, NOT a "last hit the user" tracker (that was the pre-Gen5 behavior;
		#   the move's flavor text is stale relative to GEN_LATEST config). Fails if the
		#   target has no last move, or that move's type is None/Mystery/Stellar, or every
		#   resisting type is one the user already has. Selection among multiple valid
		#   resisting types is uniform random (source rejection-samples, not "first found").
		#   Ignores Protect and Substitute (both explicit flags in source).
		if move.is_conversion2:
			var c2_move: MoveData = defender.last_move_used
			if c2_move == null or c2_move.type == TypeChart.TYPE_NONE \
					or c2_move.type == TypeChart.TYPE_MYSTERY or c2_move.type == TypeChart.TYPE_STELLAR:
				move_effect_failed.emit(attacker, "conversion2_failed")
			else:
				var c2_chosen: int = _pick_conversion2_type(attacker, c2_move.type)
				if c2_chosen < 0:
					move_effect_failed.emit(attacker, "conversion2_failed")
				else:
					_set_mon_type(attacker, c2_chosen)
					type_changed.emit(attacker, c2_chosen)
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Psych Up ──────────────────────────────────────────────────────────
		# Source: battle_script_commands.c :: Cmd_copyfoestats (L8555-8575): copies all 7
		#   stat stages from the target onto the user (full overwrite, including negative
		#   stages); ALSO copies the target's focus_energy crit-boost volatile (Gen6+ —
		#   B_PSYCH_UP_CRIT_RATIO = GEN_LATEST — confirmed from source, not assumed; source
		#   also copies dragonCheer/bonusCritStages, unimplemented here so no-op).
		#   Always hits (accuracy=0, already passed by the generic accuracy check above);
		#   ignores Protect (checked earlier in this function) and Substitute (explicit
		#   ignoresSubstitute=TRUE in source — deliberately no substitute check here).
		if move.is_psych_up:
			for _pi in range(attacker.stat_stages.size()):
				attacker.stat_stages[_pi] = defender.stat_stages[_pi]
			attacker.focus_energy = defender.focus_energy
			stat_changes_copied.emit(attacker, defender)
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		var foe_targeting: bool = not move.stat_change_self

		# M17n-9: Magic Bounce — reflects the move back at its own user BEFORE the
		# Substitute/type-immunity/Prankster gates below even run (a bounced move
		# never resolves against the original defender at all). Scoped to this
		# project's `move.bounceable` subset (see AbilityManager.bounces_status_move's
		# doc comment for the full source-derived move list and exclusions). A single
		# non-recursive attacker/defender swap correctly yields "only one bounce ever"
		# even in a Magic-Bounce-vs-Magic-Bounce matchup, and — since this check runs
		# before `blocks_prankster_move` further below — a Dark-type Magic Bounce
		# holder correctly bounces a Prankster-boosted status move rather than the
		# Prankster-Dark-immunity gate eating it as a no-op first (source:
		# CanTargetBlockPranksterMove, battle_util.c L2203-2210).
		if foe_targeting and move.bounceable \
				and AbilityManager.bounces_status_move(defender, ng_active, attacker, move):
			move_bounced.emit(defender, attacker)
			ability_triggered.emit(defender, "magic_bounce")
			var bounce_holder: BattlePokemon = defender
			defender = attacker
			attacker = bounce_holder

		# Substitute blocks most foe-targeting status moves (not self-targeting, not
		# ignoresSubstitute moves like Disable which is handled above).
		# Source: IsSubstituteProtected → returns TRUE unless MoveIgnoresSubstitute.
		# M17n-9: Infiltrator bypasses this too (shared IsSubstituteProtected chokepoint).
		if foe_targeting and defender.substitute_hp > 0 and not move.ignores_substitute \
				and not AbilityManager.bypasses_infiltrator_barriers(attacker, ng_active):
			move_missed.emit(attacker, "substitute")
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# Type immunity check for foe-targeting moves.
		# M17n-8: Corrosion bypasses this specifically for a Poison-type status move
		# (Toxic) that would otherwise be blocked by Steel's (or, in principle,
		# Poison's own) type-chart immunity to Poison-type moves — source-confirmed:
		# `CanSetNonVolatileStatus`'s ABILITY_CORROSION check (battle_util.c L5250) is
		# the ONLY reference to Corrosion anywhere in source, and its own failure
		# branch uses `BattleScript_NotAffected` — the identical "doesn't affect"
		# script a flat type immunity uses — confirming status-inflicting moves in
		# real source are gated by THIS status-specific check, not a separate general
		# type-effectiveness block gets applied downstream of it. This project's own
		# blanket type-immunity gate here (correct for e.g. Thunder Wave vs a
		# Ground-type target, which has no analogous ability bypass) would otherwise
		# incorrectly block Toxic before it ever reaches `try_apply_status`'s own
		# Corrosion-aware check below. Scoped narrowly to Poison-type moves only —
		# Corrosion does not grant any other type a wider immunity bypass.
		var corrosion_bypasses_type_gate: bool = move.type == TypeChart.TYPE_POISON \
				and AbilityManager.bypasses_poison_steel_immunity(attacker, ng_active)
		if foe_targeting and move.type != TypeChart.TYPE_NONE and not corrosion_bypasses_type_gate:
			var eff: float = TypeChart.get_effectiveness(move.type, defender.species.types)
			if eff == 0.0:
				move_missed.emit(attacker, "immune")
				_current_actor_index += 1
				_set_phase(BattlePhase.FAINT_CHECK)
				return

		# M17n-3 follow-up: a Prankster-boosted status move fails against a Dark-type
		# target (Gen 7+). Source: BlocksPrankster (battle_util.c L9234-9252), an
		# execution-time canceler positioned alongside the type-immunity check above.
		if foe_targeting and AbilityManager.blocks_prankster_move(attacker, defender, move, ng_active):
			move_effect_failed.emit(defender, "prankster_dark_immune")
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		if move.stat_change_stat >= 0:
			var stat_target: BattlePokemon = attacker if move.stat_change_self else defender
			# M17n-11: Mirror Armor — a non-self-inflicted stat DECREASE targeting a
			# Mirror Armor holder redirects onto the attacker instead, applied as a
			# direct write (matching source's SetStatChange2 raw-write shape, which
			# does not re-enter the reactive Defiant/Competitive/Opportunist checks
			# below) rather than falling through to the normal apply_stat_change path.
			if not move.stat_change_self and move.stat_change_amount < 0 \
					and AbilityManager.mirror_armor_reflects(stat_target, attacker, ng_active, attacker):
				var reflected: int = StatusManager.apply_stat_change(
						attacker, move.stat_change_stat, move.stat_change_amount, null, ng_active)
				if reflected == 0:
					move_effect_failed.emit(attacker, "stat_limit")
				else:
					stat_stage_changed.emit(attacker, move.stat_change_stat, reflected)
				ability_triggered.emit(stat_target, "mirror_armor")
				move_executed.emit(attacker, defender, move, 0)
				_current_actor_index += 1
				_set_phase(BattlePhase.FAINT_CHECK)
				return
			# M17g: `attacker` threaded through here (not just `ng_active`) — this is
			# THE genuine "a move's stat effect landing on a target" call site, where
			# Mold Breaker's attacker-scoped bypass of Simple/Contrary/Clear Body/White
			# Smoke/Hyper Cutter/Big Pecks/Keen Eye/Flower Veil actually matters. Safe to
			# pass even for stat_change_self (Swords Dance etc.): effective_ability_id's
			# own `attacker != mon` guard already skips Mold Breaker when stat_target is
			# the attacker itself, matching source's CanBreakThroughAbility exactly.
			var actual: int = StatusManager.apply_stat_change(
					stat_target, move.stat_change_stat, move.stat_change_amount,
					null, ng_active, attacker)
			if actual == 0:
				move_effect_failed.emit(stat_target, "stat_limit")
			else:
				stat_stage_changed.emit(stat_target, move.stat_change_stat, actual)
				# M17b: Defiant/Competitive — only for a decrease caused by an
				# OPPONENT's move (not stat_change_self, e.g. Swords Dance).
				# Source: battle_util.c :: ShouldDefiantCompetitiveActivate (L1149-1168).
				if actual < 0 and not move.stat_change_self:
					var defiant_stat: int = AbilityManager.defiant_competitive_stat(stat_target, ng_active)
					if defiant_stat != -1:
						var defiant_actual: int = StatusManager.apply_stat_change(stat_target, defiant_stat, 2, null, ng_active)
						if defiant_actual != 0:
							stat_stage_changed.emit(stat_target, defiant_stat, defiant_actual)
							ability_triggered.emit(stat_target, "defiant_competitive")
				# M17n-8: Opportunist — copies the SAME stage increase onto any live
				# opponent (relative to `stat_target`, the mon whose stat just rose) that
				# holds it, immediately. Source: battle_stat_change.c L420-441 — checked
				# ONLY in the stat-INCREASE path (never decreases), loops every battler on
				# the OPPOSING side of `stat_target` (`IsBattlerAlly` skip — the holder can
				# never react to its own side's raise, including its own, by construction).
				# Unlike Defiant/Competitive above, NOT gated on `move.stat_change_self` —
				# source's real check fires for a self-targeted raise (Swords Dance) just
				# as much as an opponent-targeted one; what matters is which SIDE the
				# raised mon is on, not whether the move that raised it was self-targeted.
				# No infinite-loop risk: the copied change below calls
				# StatusManager.apply_stat_change directly, never re-entering this same
				# dispatch block, so Opportunist's own copy can't re-trigger itself.
				# Known simplification (documented, not silently dropped): wired into
				# this primary move-driven stat-increase call site only, mirroring
				# Defiant/Competitive's own established precedent of not retrofitting
				# into every apply_stat_change call site — ability-driven stat increases
				# (Moxie, Weak Armor's Speed+2, Download, etc.) and Baton-Pass/Psych-Up
				# stage copies are NOT currently covered.
				if actual > 0:
					for opp: BattlePokemon in _get_live_opponents(stat_target):
						if AbilityManager.effective_ability_id(opp, ng_active) == AbilityManager.ABILITY_OPPORTUNIST:
							var opp_actual: int = StatusManager.apply_stat_change(
									opp, move.stat_change_stat, actual, null, ng_active)
							if opp_actual != 0:
								stat_stage_changed.emit(opp, move.stat_change_stat, opp_actual)
								ability_triggered.emit(opp, "opportunist")
						# M18m: Mirror Herb — confirmed a genuine structural twin of
						# Opportunist AT THE SOURCE LEVEL (battle_stat_change.c
						# L430-449 checks both in the literal same loop), so it
						# correctly inherits the identical "primary move-driven
						# stat increases only" scope limit documented above — not
						# a new simplification. Source queues-and-batches the copy
						# until MoveEnd (single-use, unlike permanent Opportunist);
						# simplified here to an immediate copy-and-consume, since
						# this project's one-stat-per-move architecture means a
						# second qualifying trigger could never occur before the
						# item is already spent — see HOLD_EFFECT_MIRROR_HERB's
						# own doc comment for the full rationale.
						if ItemManager.holds_mirror_herb(opp, ng_active):
							var mh_actual: int = StatusManager.apply_stat_change(
									opp, move.stat_change_stat, actual, null, ng_active)
							if mh_actual != 0:
								stat_stage_changed.emit(opp, move.stat_change_stat, mh_actual)
							_consume_item(opp)
		elif move.secondary_effect != MoveData.SE_NONE:
			var applied: bool = StatusManager.try_secondary_effect(attacker, defender, move, null, ng_active, _effective_weather())
			if applied:
				secondary_applied.emit(defender, move.secondary_effect)
				# Synchronize: defender received a primary status — check back-reflect.
				_try_synchronize(defender, attacker, _se_to_status(move.secondary_effect))
				# M12: Lum Berry (+ M18b: Cheri/Chesto/Pecha/Rawst/Aspear) cures status
				# inflicted by status move primary effect.
				# M17n-7: Unnerve — blocks this berry while any of defender's opponents has it.
				if ItemManager.status_cure_berry_cures(defender, ng_active,
						AbilityManager.is_unnerve_active(_get_live_opponents(defender), ng_active)):
					defender.status = BattlePokemon.STATUS_NONE
					_consume_item(defender)
				# M18b: Persim Berry cures confusion inflicted the same way — a SEPARATE
				# check since confusion is a volatile (confusion_turns), not `.status`;
				# both checks are self-guarding (each returns false unless its own
				# specific hold_effect+condition match), so running both unconditionally
				# is correct and never double-fires.
				elif ItemManager.confusion_cure_berry_cures(defender, ng_active,
						AbilityManager.is_unnerve_active(_get_live_opponents(defender), ng_active)):
					defender.confusion_turns = 0
					_consume_item(defender)
			else:
				move_effect_failed.emit(defender, "immune")

		move_executed.emit(attacker, defender, move, 0)

	_current_actor_index += 1
	_set_phase(BattlePhase.FAINT_CHECK)


func _phase_faint_check() -> void:
	# Capture and process any new faints (hp == 0 and not yet marked fainted).
	# Track whether ANY new faint occurred this tick — only these warrant SWITCH_PROMPT.
	# Previously-fainted slots (fainted=true from an earlier turn) must NOT re-trigger
	# SWITCH_PROMPT or the doubles no-bench scenario loops forever: every post-turn-1
	# action would jump back to SWITCH_PROMPT because B0.fainted is still true.
	var any_new_faint := false
	for combatant: BattlePokemon in _combatants:
		if combatant.current_hp <= 0 and not combatant.fainted:
			any_new_faint = true
			# Capture before clearing: Destiny Bond check.
			# Source: battle_main.c :: FAINT_BLOCK_TRY_DESTINY_BOND (battle_move_resolution.c L2953)
			#   If the fainted mon had destinyBond active, the Pokémon who KO'd it also faints.
			var had_destiny_bond: bool = combatant.destiny_bond
			combatant.fainted = true
			# Clear ALL volatiles on faint.
			# Source: FaintClearSetData in battle_main.c clears gBattleMons[].volatiles.
			_clear_volatiles(combatant)
			pokemon_fainted.emit(combatant)
			# M17b: Moxie — Attack +1 for whoever's hit caused this faint.
			# Source: battle_util.c L4467-4472; killer lookup reuses M14b's _last_attacker.
			var moxie_killer: BattlePokemon = _last_attacker.get(combatant, null)
			var moxie_actual: int = AbilityManager.moxie_boost(moxie_killer, _is_neutralizing_gas_active())
			if moxie_actual != 0:
				stat_stage_changed.emit(moxie_killer, BattlePokemon.STAGE_ATK, moxie_actual)
				ability_triggered.emit(moxie_killer, "moxie")
			# M17h: Receiver / Power of Alchemy — doubles-only (via _get_ally, which is
			# already null in singles — same gating shape as M17c's Hospitality), copies
			# THIS fainted mon's ability onto its surviving ally if that ally holds
			# Receiver/Power of Alchemy. Source: `tryactivatereceiver BS_FAINTED`
			# (data/battle_scripts_1.s L2739), part of the shared BattleScript_FaintBattler
			# every faint runs through — this project fires it from the same
			# pokemon_fainted-adjacent point M17b's Moxie already established.
			var receiver_ally: BattlePokemon = _get_ally(combatant)
			var received_id: int = AbilityManager.try_receiver_copy(
					combatant, receiver_ally, _is_neutralizing_gas_active())
			if received_id != -1:
				ability_changed.emit(receiver_ally, received_id)
				ability_triggered.emit(receiver_ally, "receiver_power_of_alchemy")
			# Destiny Bond: KO the Pokémon that dealt the fatal blow (if still standing).
			# M14b: use _last_attacker[combatant] rather than _get_first_opponent — in doubles
			# the fatal hit may come from the second opposing slot, not the first.
			# Source: FAINT_BLOCK_TRY_DESTINY_BOND (battle_move_resolution.c L2953):
			#   checks gBattlerAttacker (the attacker that caused the faint), not a side index.
			if had_destiny_bond:
				var killer: BattlePokemon = _last_attacker.get(combatant, null)
				if killer == null:
					killer = _get_first_opponent(combatant)  # fallback for edge cases
				if not killer.fainted:
					killer.current_hp = 0
					killer.fainted = true
					_clear_volatiles(killer)
					destiny_bond_triggered.emit(combatant, killer)
					pokemon_fainted.emit(killer)

			# M17n-8: Aftermath / Innards Out — retaliate against whoever's hit caused
			# this faint. Independent lookup from Destiny Bond's own `killer` above
			# (that one is scoped to `if had_destiny_bond:` and may fall back to
			# `_get_first_opponent`, which Aftermath/Innards Out must NOT do — source
			# requires the actual attacker of the fatal hit, never a same-side fallback).
			var retal_killer: BattlePokemon = _last_attacker.get(combatant, null)
			var retal_move: MoveData = _last_attacker_move.get(combatant, null)
			var retal_hp_before: int = _last_attacker_hp_before.get(combatant, 0)
			var retal_ng_active: bool = _is_neutralizing_gas_active()
			var retaliation: Dictionary = AbilityManager.faint_retaliation_damage(
					combatant, retal_killer, retal_move, retal_hp_before, retal_ng_active,
					AbilityManager.is_damp_active(_combatants, retal_ng_active))
			if not retaliation.is_empty():
				var retal_dmg: int = retaliation["damage"]
				retal_killer.current_hp = max(0, retal_killer.current_hp - retal_dmg)
				recoil_damage.emit(retal_killer, retal_dmg)
				ability_triggered.emit(combatant, retaliation["ability_name"])
				if retal_killer.current_hp <= 0 and not retal_killer.fainted:
					retal_killer.fainted = true
					_clear_volatiles(retal_killer)
					pokemon_fainted.emit(retal_killer)

	# M18m: White Herb / Eject Pack — this function is BattleManager's own
	# MoveEnd-equivalent checkpoint (runs once per resolved move regardless of
	# outcome, since _set_phase(FAINT_CHECK) is the universal next-phase call
	# from every move-execution exit path) — the closest match to source's own
	# MoveEndItemOnStatChange granularity (battle_move_resolution.c L4091-4110),
	# which both items are dispatched from. Runs AFTER the fainting loop above
	# so `.fainted` is already correctly updated for this same resolution
	# (avoiding the current_hp-vs-.fainted pitfall by construction, not by a
	# current_hp check here).
	var m18m_ng_active: bool = _is_neutralizing_gas_active()
	for mon: BattlePokemon in _combatants:
		if mon.fainted:
			continue
		# White Herb: UNCONDITIONAL scan of every stat stage, every checkpoint —
		# genuinely NOT gated on "a decrease just happened this move," unlike
		# Eject Pack below. Source: RestoreWhiteHerbStats (battle_hold_effects.c
		# L148-164).
		if ItemManager.holds_white_herb(mon, m18m_ng_active):
			var any_reset := false
			for i in range(mon.stat_stages.size()):
				if mon.stat_stages[i] < 0:
					var wh_before: int = mon.stat_stages[i]
					mon.stat_stages[i] = 0
					stat_stage_changed.emit(mon, i, 0 - wh_before)
					any_reset = true
			if any_reset:
				_consume_item(mon)
		# M18v: Mental Herb — same UNCONDITIONAL per-checkpoint scan shape as
		# White Herb above (source's TryMentalHerb, battle_hold_effects.c
		# L416-476, never gates on "just happened this move" either). Cures
		# BOTH Disable and Encore in this one check if either is currently
		# active — matching source's own single `effect` flag covering
		# however many of its (up to 6, of which this project implements 2)
		# conditions matched — consumed ONCE regardless of whether one or
		# both fired.
		if ItemManager.holds_mental_herb(mon, m18m_ng_active):
			var mh_cured := false
			if mon.disable_turns > 0:
				mon.disabled_move = null
				mon.disable_turns = 0
				item_effect_triggered.emit(mon, "mental_herb_disable")
				mh_cured = true
			if mon.encore_turns > 0:
				mon.encored_move = null
				mon.encore_turns = 0
				item_effect_triggered.emit(mon, "mental_herb_encore")
				mh_cured = true
			if mh_cured:
				_consume_item(mon)
		# Eject Pack: only if a decrease was JUST applied since the last
		# checkpoint (snapshot-diff against `eject_pack_snapshot`) — reproduces
		# source's `tryEjectPack` volatile flag shape. Any source (the holder's
		# own move, an opponent's move, hazards, etc.) — confirmed NOT
		# opponent-only. Reuses `_do_forced_switch_in` and the random-
		# replacement-pick shape [M18n]'s Red Card/Eject Button already
		# established — NOT Guard-Dog-blockable (self-switch, not a forced-out-
		# by-opponent case).
		if ItemManager.holds_eject_pack(mon, m18m_ng_active):
			var ep_decreased := false
			for i in range(mon.stat_stages.size()):
				if mon.stat_stages[i] < mon.eject_pack_snapshot[i]:
					ep_decreased = true
					break
			if ep_decreased:
				var ep_idx: int = _combatants.find(mon)
				var ep_side: int = ep_idx / _active_per_side
				var ep_field_slot: int = ep_idx % _active_per_side
				var ep_slot: int = _parties[ep_side].get_random_non_fainted_not_active(_force_roar_rng)
				if ep_slot >= 0:
					var ep_old_holder: BattlePokemon = mon
					_consume_item(mon)
					_do_forced_switch_in(ep_side, ep_slot, ep_field_slot)
					forced_switch.emit(ep_old_holder, _parties[ep_side].get_active_at(ep_field_slot))
		mon.eject_pack_snapshot = mon.stat_stages.duplicate()

	# If any new faint occurred this tick, go to SWITCH_PROMPT.
	# M9: SWITCH_PROMPT handles replacements and checks full-party faint.
	if any_new_faint:
		_set_phase(BattlePhase.SWITCH_PROMPT)
		return

	# Nobody newly fainted — continue the action execution loop or move to end of turn.
	if _current_actor_index < _turn_order.size():
		_set_phase(BattlePhase.ACTION_EXECUTION)
	else:
		_set_phase(BattlePhase.END_OF_TURN)


func _phase_end_of_turn() -> void:
	# M17g: computed once for the whole end-of-turn tick — Poison Heal, Truant's
	# implicit gate (via pre_move_check next turn), and every ABILITYEFFECT_ENDTURN
	# ability below share this same field-wide snapshot.
	var ng_active: bool = _is_neutralizing_gas_active()
	# ── M11: Weather duration tick (ENDTURN_WEATHER, position 2 in source handler table) ──
	# Source: HandleEndTurnWeather → EndOrContinueWeather (battle_util.c L244):
	#   if (weatherDuration > 0 && --weatherDuration == 0) → gBattleWeather = B_WEATHER_NONE
	# Tick fires BEFORE weather chip damage and BEFORE status damage.
	if weather != WEATHER_NONE and weather_duration > 0:
		weather_duration -= 1
		if weather_duration == 0:
			var expired_w: int = weather
			weather = WEATHER_NONE
			weather_expired.emit(expired_w)
			_notify_weather_changed()

	# ── M11: Weather chip damage (ENDTURN_WEATHER_DAMAGE, position 3) ────────────────────
	# Source: HandleEndTurnWeatherDamage (battle_end_turn.c L100–186).
	# Fires BEFORE poison/burn (ENDTURN_POISON=12, ENDTURN_BURN=13 in handler table).
	# SANDSTORM: immune if any type is Rock(6)/Ground(5)/Steel(9), or semi-invulnerable,
	#   or ability is Sand Veil/Sand Force/Sand Rush/Overcoat.
	#   Source: IS_BATTLER_ANY_TYPE(battler, TYPE_ROCK, TYPE_GROUND, TYPE_STEEL) (L148);
	#   ability exemptions at L144-147.
	#   [M17n-2] FOLLOW-UP FIX (post-[M17n-6]): this comment previously (and wrongly)
	#   stated "Sand Veil/Sand Rush do NOT grant sandstorm-chip immunity" — that was
	#   [M17n-2]'s own original conclusion, confirmed WRONG during [M17n-6]'s Overcoat
	#   work and fixed here (see docs/decisions.md's [M17n-2] follow-up subsection).
	#   Sand Veil/Sand Force/Sand Rush DO grant sandstorm-chip immunity, matching
	#   Overcoat's existing shape — see AbilityManager.blocks_weather_chip_damage.
	# HAIL: immune if any type is Ice(16), or semi-invulnerable, or ability is Snow
	#   Cloak/Overcoat. Source: IS_BATTLER_OF_TYPE(battler, TYPE_ICE) (L171); ability
	#   exemption at L166. Magic Guard also appears in source's exemption chain
	#   (L150, L167) — implemented as of [M17n-9], gated inside
	#   _is_weather_damage_immune via AbilityManager.blocks_indirect_damage.
	# Damage = maxHP / 16 (integer division). Source: GetNonDynamaxMaxHP(battler) / 16 (L154, L177).
	# M17n-2: `weather` here is intentionally the RAW field, not `_effective_weather()`
	# — Air Lock/Cloud Nine negation is applied via the `eff_weather` local below,
	# computed once and reused for both the outer gate and the per-mon immunity check.
	var eff_weather: int = _effective_weather()
	if eff_weather == WEATHER_SANDSTORM or eff_weather == WEATHER_HAIL:
		for mon: BattlePokemon in _turn_order:
			if mon.fainted:
				continue
			if _is_weather_damage_immune(mon, eff_weather, ng_active):
				continue
			var chip: int = mon.max_hp / 16
			if chip > 0:
				mon.current_hp = max(0, mon.current_hp - chip)
				weather_damage.emit(mon, chip)
				if mon.current_hp == 0:
					mon.fainted = true
					pokemon_fainted.emit(mon)

	# ── Status damage (ENDTURN_POISON=12, ENDTURN_BURN=13 in source handler table) ────────
	# Apply end-of-turn status damage in speed order (matching source ENDTURN_POISON
	# and ENDTURN_BURN handlers in battle_end_turn.c which iterate by battler order).
	# Source: battle_end_turn.c :: HandleEndTurnPoison (L517), HandleEndTurnBurn (L565)
	for mon: BattlePokemon in _turn_order:
		if mon.fainted:
			continue
		var dmg: int = StatusManager.end_of_turn_damage(mon, ng_active)
		if dmg > 0:
			mon.current_hp = max(0, mon.current_hp - dmg)
			status_damage.emit(mon, dmg)
			if mon.current_hp == 0:
				mon.fainted = true
				pokemon_fainted.emit(mon)
		elif dmg < 0:
			# M17d: Poison Heal — negative return means heal, not damage.
			mon.current_hp = min(mon.max_hp, mon.current_hp - dmg)
			ability_healed.emit(mon, -dmg)
			ability_triggered.emit(mon, "poison_heal")

	# ── [M18.5f] Bind/Wrap-family recurring damage (ENDTURN_WRAP, source's handler
	# table slot right after Burn/Frostbite/Nightmare/Curse, before Salt Cure) ──────
	# Source: HandleEndTurnWrap (battle_end_turn.c L649-687). Deliberate off-by-one
	# vs. a naive decrement-then-check-zero shape: source checks wrapTurns != 0
	# BEFORE decrementing, so a fresh N-turn trap deals damage on N separate end-of-
	# turns (turns 1..N all decrement-and-damage, since the check reads the PRE-
	# decrement value each time), and only breaks free — no damage, just the "ends"
	# message — on the (N+1)th end-of-turn once wrapTurns is already 0. Reproduced
	# here by checking wrapped_turns BEFORE decrementing, matching source's exact
	# ordering, rather than the simpler "decrement then clear at 0" shape this
	# project's own disable_turns/encore_turns use (those don't have this same
	# extra-silent-tick nuance in source). wrapped_turns decrements UNCONDITIONALLY
	# even under Magic Guard (only the damage itself is suppressed — same
	# "counter still ticks" shape as toxic_counter above). maxHP/8, B_BINDING_DAMAGE
	# >= GEN_6 branch (this project's default config) — Binding Band's maxHP/6
	# variant is out of scope (item unbuilt, flagged alongside Grip Claw for M18.5i).
	for mon: BattlePokemon in _turn_order:
		if mon.fainted or mon.wrapped_by == null:
			continue
		if mon.wrapped_turns <= 0:
			mon.wrapped_by = null
			wrap_ended.emit(mon)
			continue
		mon.wrapped_turns -= 1
		if AbilityManager.blocks_indirect_damage(mon, ng_active):
			continue
		var wrap_dmg: int = max(1, mon.max_hp / 8)
		mon.current_hp = max(0, mon.current_hp - wrap_dmg)
		wrap_damage.emit(mon, wrap_dmg)
		if mon.current_hp == 0:
			mon.fainted = true
			pokemon_fainted.emit(mon)

	# M12: Leftovers EOT heal (FIRST_EVENT_BLOCK_HEAL_ITEMS, after status damage).
	# Source: TryLeftovers (battle_hold_effects.c L634–648); fires via FIRST_EVENT_BLOCK_HEAL_ITEMS
	#   which is position 19 in battle_end_turn.c handler table (after ENDTURN_BURN=13).
	for mon: BattlePokemon in _combatants:
		if mon.fainted:
			continue
		var lft_heal: int = ItemManager.leftovers_heal(mon, ng_active)
		if lft_heal > 0:
			mon.current_hp = min(mon.max_hp, mon.current_hp + lft_heal)
			item_healed.emit(mon, lft_heal)

	# M18r: Black Sludge — same EOT neighborhood Leftovers occupies. Poison-type
	# holder: heals maxHP/16 (reuses TryLeftovers exactly, no Magic Guard
	# interaction since it's a heal). Non-Poison holder: DAMAGES maxHP/8 (NOT
	# 1/16 — see HOLD_EFFECT_BLACK_SLUDGE's own doc comment for the source
	# citation correcting this tier's own plan doc), gated by Magic Guard on the
	# damage side only, matching every other indirect-damage source's call-site
	# pattern (Jaboca/Rowap, sandstorm/hail chip).
	for mon: BattlePokemon in _combatants:
		if mon.fainted:
			continue
		var bs_heal: int = ItemManager.black_sludge_heal(mon, ng_active)
		if bs_heal > 0:
			mon.current_hp = min(mon.max_hp, mon.current_hp + bs_heal)
			item_healed.emit(mon, bs_heal)
			continue
		var bs_dmg: int = ItemManager.black_sludge_damage(mon, ng_active)
		if bs_dmg > 0 and not AbilityManager.blocks_indirect_damage(mon, ng_active):
			mon.current_hp = max(0, mon.current_hp - bs_dmg)
			item_damage.emit(mon, bs_dmg)
			if mon.current_hp == 0:
				mon.fainted = true
				pokemon_fainted.emit(mon)

	# M18p: Sticky Barb's end-of-turn self-damage half (TryStickyBarbOnEndTurn) — NOT
	# contact-related at all, unconditional every end of turn, gated by the HOLDER's
	# own Magic Guard (unlike Rocky Helmet's attacker-side gate above). Source
	# dispatches this via IsOrbsActivation alongside Flame/Toxic Orb, but it's
	# mechanically identical in shape to Black Sludge's damage half just above, so
	# it's placed in that neighborhood instead.
	for mon: BattlePokemon in _combatants:
		if mon.fainted:
			continue
		var sb_dmg: int = ItemManager.sticky_barb_damage(mon, ng_active)
		if sb_dmg > 0 and not AbilityManager.blocks_indirect_damage(mon, ng_active):
			mon.current_hp = max(0, mon.current_hp - sb_dmg)
			item_damage.emit(mon, sb_dmg)
			if mon.current_hp == 0:
				mon.fainted = true
				pokemon_fainted.emit(mon)

	# M18i: Status Orbs (Flame Orb/Toxic Orb) — checked EVERY end of turn (no
	# turn-counter mechanic exists in source; see ItemManager.status_orb_status's
	# own doc comment), same THIRD_EVENT_BLOCK_ITEMS neighborhood Leftovers
	# occupies. Applies through StatusManager.try_apply_status — the SAME
	# function moves use — passing the holder as its own `attacker`, mirroring
	# source's self-referential CanBeBurned/CanBePoisoned call shape so existing
	# type immunities compose for free.
	for mon: BattlePokemon in _combatants:
		if mon.fainted:
			continue
		var orb_status: int = ItemManager.status_orb_status(mon, ng_active)
		if orb_status != BattlePokemon.STATUS_NONE:
			if StatusManager.try_apply_status(mon, orb_status, null, null, ng_active, mon):
				secondary_applied.emit(mon, _status_to_se(orb_status))

	# M7: Decrement Disable and Encore turn counters.
	# Source: battle_end_turn.c :: HandleTurnStartFunctionOrder (Disable/Encore decrements)
	for mon: BattlePokemon in _combatants:
		if mon.fainted:
			continue
		if mon.disable_turns > 0:
			mon.disable_turns -= 1
			if mon.disable_turns == 0:
				mon.disabled_move = null
		if mon.encore_turns > 0:
			mon.encore_turns -= 1
			if mon.encore_turns == 0:
				mon.encored_move = null

	# M16c: Decrement Reflect/Light Screen/Aurora Veil timers, both sides.
	# Source: battle_end_turn.c :: HandleEndTurnSecondEventBlock, cases
	#   SECOND_EVENT_BLOCK_REFLECT / _LIGHT_SCREEN / _AURORA_VEIL (L1025-1127): decrement;
	#   at 0, clear the side-status bit and fire the "wore off" message.
	for side in range(2):
		var sc: Dictionary = _side_conditions[side]
		if sc["reflect_turns"] > 0:
			sc["reflect_turns"] -= 1
			if sc["reflect_turns"] == 0:
				screen_expired.emit(side, "reflect")
		if sc["light_screen_turns"] > 0:
			sc["light_screen_turns"] -= 1
			if sc["light_screen_turns"] == 0:
				screen_expired.emit(side, "light_screen")
		if sc["aurora_veil_turns"] > 0:
			sc["aurora_veil_turns"] -= 1
			if sc["aurora_veil_turns"] == 0:
				screen_expired.emit(side, "aurora_veil")

	# M16d: Decrement Trick Room's field-wide timer.
	# Source: battle_end_turn.c L1146 — gFieldStatuses &= ~STATUS_FIELD_TRICK_ROOM at 0.
	# Note: entry hazards (Spikes/Toxic Spikes/Stealth Rock) have NO natural duration —
	# they persist until Rapid Spin clears them or the battle ends, so nothing to decrement.
	if trick_room_turns > 0:
		trick_room_turns -= 1
		if trick_room_turns == 0:
			trick_room_ended.emit()

	# End-of-turn ability effects (Speed Boost, M17b: Moody)
	# Source: AbilityBattleEffects(ABILITYEFFECT_ENDTURN, ...) (battle_util.c L3605)
	var eot_eff_weather: int = _effective_weather()
	for mon: BattlePokemon in _combatants:
		if mon.fainted:
			continue
		var eot_result: Dictionary = AbilityManager.try_end_of_turn(
				mon, _force_moody_raise, _force_moody_lower, eot_eff_weather, _get_ally(mon),
				_force_shed_skin_roll, _force_healer_roll, ng_active)
		var spd_actual: int = eot_result["speed_boost_change"]
		if spd_actual != 0:
			stat_stage_changed.emit(mon, BattlePokemon.STAGE_SPEED, spd_actual)
			ability_triggered.emit(mon, "speed_boost")
		if eot_result["moody_raised_stat"] != -1 and eot_result["moody_raised_amount"] != 0:
			stat_stage_changed.emit(mon, eot_result["moody_raised_stat"], eot_result["moody_raised_amount"])
			ability_triggered.emit(mon, "moody")
		if eot_result["moody_lowered_stat"] != -1 and eot_result["moody_lowered_amount"] != 0:
			stat_stage_changed.emit(mon, eot_result["moody_lowered_stat"], eot_result["moody_lowered_amount"])
			ability_triggered.emit(mon, "moody")
		# M17c: Rain Dish / Ice Body / Dry Skin end-of-turn heal or (Dry Skin only) sun damage.
		if eot_result["heal_amount"] > 0:
			mon.current_hp = min(mon.max_hp, mon.current_hp + eot_result["heal_amount"])
			ability_healed.emit(mon, eot_result["heal_amount"])
			ability_triggered.emit(mon, "rain_dish_ice_body_dry_skin")
		if eot_result["damage_amount"] > 0:
			mon.current_hp = max(0, mon.current_hp - eot_result["damage_amount"])
			weather_damage.emit(mon, eot_result["damage_amount"])
			var eot_dmg_tag: String = "solar_power" \
					if AbilityManager.effective_ability_id(mon, ng_active) == AbilityManager.ABILITY_SOLAR_POWER \
					else "dry_skin"
			ability_triggered.emit(mon, eot_dmg_tag)
		# M17c: Hydration / Shed Skin cure the holder's own status.
		if eot_result["cured_status"]:
			mon.status = BattlePokemon.STATUS_NONE
			mon.toxic_counter = 0
			ability_triggered.emit(mon, "hydration_shed_skin")
		# M17c: Healer cures the ally's status (doubles-only).
		if eot_result["healed_ally_status"]:
			var healer_ally: BattlePokemon = _get_ally(mon)
			healer_ally.status = BattlePokemon.STATUS_NONE
			healer_ally.toxic_counter = 0
			ability_triggered.emit(mon, "healer")
		# M17n-5: Slow Start's 5-turn timer just hit 0 — fires once, the turn its
		# Atk/Speed penalty ends.
		if eot_result["slow_start_ended"]:
			ability_triggered.emit(mon, "slow_start_ended")

		# M17n-7: Harvest — regenerate the last consumed berry back onto held_item.
		# Does NOT clear last_consumed_berry (see BattlePokemon's own doc comment —
		# source doesn't either; self-consistent since `held_item != null` afterward
		# blocks Harvest from re-firing until the item is removed again, at which
		# point _consume_item overwrites last_consumed_berry with whatever was just
		# eaten anyway).
		if AbilityManager.harvest_activates(mon, eot_eff_weather, ng_active, _force_harvest_roll):
			mon.held_item = mon.last_consumed_berry
			item_regenerated.emit(mon, mon.held_item)
			ability_triggered.emit(mon, "harvest")

		# M17n-7: Cud Chew — arm/fire one-turn cycle. Firing re-runs the tracked
		# berry's effect via the SAME ItemManager functions normal consumption uses
		# (only one of the three will actually match the berry's real hold_effect;
		# Resist Berry deliberately has no re-trigger path here at all — it has no
		# context-independent re-check to perform, confirmed absent from source).
		# M18b: added the third (confusion_cure_berry_cures) branch for Persim Berry —
		# status_cure_berry_cures/hp_threshold_berry_heal already cover the other 22
		# new M18b items automatically, since both were extended in place rather than
		# replaced; only Persim's confusion-based cure needed a genuinely new function
		# this chain didn't already call.
		match AbilityManager.cud_chew_check(mon, ng_active):
			"arm":
				mon.cud_chew_armed = true
			"fire":
				mon.cud_chew_armed = false
				var cc_berry: ItemData = mon.last_consumed_berry
				mon.last_consumed_berry = null
				var cc_unnerve: bool = AbilityManager.is_unnerve_active(
						_get_live_opponents(mon), ng_active)
				var cc_heal: int = ItemManager.hp_threshold_berry_heal(mon, ng_active, cc_unnerve, cc_berry)
				if cc_heal > 0:
					mon.current_hp = min(mon.max_hp, mon.current_hp + cc_heal)
					item_healed.emit(mon, cc_heal)
					ability_triggered.emit(mon, "cud_chew")
				elif ItemManager.status_cure_berry_cures(mon, ng_active, cc_unnerve, cc_berry):
					mon.status = BattlePokemon.STATUS_NONE
					ability_triggered.emit(mon, "cud_chew")
				elif ItemManager.confusion_cure_berry_cures(mon, ng_active, cc_unnerve, cc_berry):
					mon.confusion_turns = 0
					ability_triggered.emit(mon, "cud_chew")

	# Route through SWITCH_PROMPT even after EOT so any EOT faint gets a replacement.
	_set_phase(BattlePhase.SWITCH_PROMPT)


func _phase_switch_prompt() -> void:
	# For each fainted combatant, send in a replacement if one is available.
	# Source: battle_main.c :: L3671+, monToSwitchIntoId, SwitchInClearSetData.
	# M14a: iterates all combatants (not just parties); supports doubles where
	#   one side can have a fainted slot with no bench (other active slot still fights).
	for ci in range(_combatants.size()):
		var mon: BattlePokemon = _combatants[ci]
		if not mon.fainted:
			continue
		var side: int = ci / _active_per_side
		var party: BattleParty = _parties[side]
		if party.is_fully_fainted():
			continue  # no replacements; BATTLE_END_CHECK will declare winner
		# Determine replacement slot (-1 = no bench member available).
		var slot: int = _get_replacement_slot(ci)
		if slot < 0:
			continue  # all surviving party members are already active (doubles)
		_do_switch_in(ci, slot)
		replacement_needed.emit(side)
	_set_phase(BattlePhase.BATTLE_END_CHECK)


func _phase_battle_end_check() -> void:
	# M9: check whether a WHOLE PARTY is fainted (not just the active member).
	# Source: M1 intent — BATTLE_END_CHECK originally checked gBattleMons[].hp,
	# which covers only the active slot; M9 extends to the full party.
	for i in range(_parties.size()):
		if _parties[i].is_fully_fainted():
			_set_phase(BattlePhase.BATTLE_END)
			battle_ended.emit(1 - i)  # the other side wins
			return
	# No side fully fainted — start the next turn.
	_set_phase(BattlePhase.MOVE_SELECTION)


# --- Helpers ---

func _set_phase(p: BattlePhase) -> void:
	_phase = p
	phase_changed.emit(p)


# M14a: returns the first active mon on the opposing side.
# In singles: identical to the old binary _get_opponent.
# In doubles: returns field slot 0 of the opposing side.
# Used for Destiny Bond fallback, singles AI targeting, and faint-replacement AI.
# Intimidate switch-in now uses _apply_switch_in_abilities (loops all live opponents).
func _get_first_opponent(mon: BattlePokemon) -> BattlePokemon:
	var idx: int = _combatants.find(mon)
	var side: int = idx / _active_per_side if idx >= 0 else 0
	return _combatants[(1 - side) * _active_per_side]


# M17a: returns mon's doubles partner (same side, other field slot), or null in singles
# (_active_per_side <= 1) or if the ally has fainted. Reuses the same _combatants/
# _active_per_side layout M14a already built — not new infrastructure, just a missing
# convenience accessor alongside _get_first_opponent. Needed for Battery/Power Spot/
# Steely Spirit's ally-aura power boost (docs/m17_recon.md Section 9 Bucket A).
func _get_ally(mon: BattlePokemon) -> BattlePokemon:
	if _active_per_side <= 1:
		return null
	var idx: int = _combatants.find(mon)
	if idx < 0:
		return null
	var side: int = idx / _active_per_side
	var local_slot: int = idx % _active_per_side
	for other_local in range(_active_per_side):
		if other_local == local_slot:
			continue
		var ally: BattlePokemon = _combatants[side * _active_per_side + other_local]
		if not ally.fainted:
			return ally
	return null


# M17f: live (non-fainted, opposing-side) combatants for mon — same loop shape as
# _apply_switch_in_abilities's live_opponents gathering. Used by the voluntary-switch
# trapping gate (AbilityManager.is_trapped) in _phase_move_selection.
func _get_live_opponents(mon: BattlePokemon) -> Array:
	var idx: int = _combatants.find(mon)
	var side: int = idx / _active_per_side if idx >= 0 else 0
	var opponents: Array = []
	for j in range(_combatants.size()):
		if j / _active_per_side == side:
			continue
		var opp: BattlePokemon = _combatants[j]
		if opp.fainted or opp.current_hp == 0:
			continue
		opponents.append(opp)
	return opponents


# M17g: whether Neutralizing Gas is active anywhere on the field right now — checked
# across ALL live combatants (both sides), unlike _get_live_opponents (one side only),
# since Neutralizing Gas suppresses field-wide including the holder's own side.
func _is_neutralizing_gas_active() -> bool:
	return AbilityManager.is_neutralizing_gas_active(_combatants)


# M17n-2: whether Air Lock/Cloud Nine is active anywhere on the field right now — same
# field-wide shape as _is_neutralizing_gas_active above.
func _is_weather_negated() -> bool:
	return AbilityManager.is_weather_negated(_combatants, _is_neutralizing_gas_active())


# M17n-2: the weather value every ability-facing weather check should read, mirroring
# source's GetWeather() (battle_util.c L9274-9279): WEATHER_NONE whenever Air
# Lock/Cloud Nine is active anywhere, otherwise the real field `weather`. Substituted
# at every call site that threads `weather` into an ability-facing function
# (DamageCalculator.calculate, AbilityManager.try_end_of_turn, StatusManager.
# try_secondary_effect/check_accuracy, StatusManager.effective_speed, and the
# end-of-turn sandstorm/hail chip-damage check) — this ONE substitution point is what
# makes Air Lock/Cloud Nine's negation comprehensive across every existing
# weather-conditional ability (Flower Gift, Solar Power, Dry Skin, Slush Rush, Leaf
# Guard) as well as this tier's own three new abilities, without touching any of
# THEIR individual implementations. Deliberately NOT substituted at the two
# TrainerAI call sites (`[M17c]`'s existing documented simplification) or at the three
# pure MOVE-mechanic weather checks (Solar Beam's charge-skip, Growth's power-doubling,
# Aurora Veil's hail requirement) — see AbilityManager.is_weather_negated's doc comment.
func _effective_weather() -> int:
	return WEATHER_NONE if _is_weather_negated() else weather


# Fire switch-in ability effects for new_mon against all live opposing combatants.
# Source: AbilityBattleEffects ABILITYEFFECT_ON_SWITCHIN (battle_util.c L3310–3323):
#   for i in 0..gBattlersCount: if IsBattlerAlly(battler,i) || !IsBattlerAlive(i): continue
#   SetStatChange(i, STAT_ATK, -1); then BattleScriptCall(BattleScript_IntimidateActivates).
# Loop shape: iterate ALL _combatants and filter by side — mirrors source loop exactly.
#   (Not "iterate only the opposing half") so the logic stays correct under layout changes.
# ability_triggered fires once per activation (one BattleScriptCall in source), not per target.
# Gen 8 Intimidate immunity (Inner Focus, Scrappy, Own Tempo, Oblivious, Guard Dog) is
#   intentionally omitted — none of those abilities exist in this codebase. Port when added.
#   See decisions.md [M14x Intimidate doubles + Gen 8 immunity].
# M16d: entry hazard damage/status on switch-in (Spikes, Toxic Spikes, Stealth Rock).
# Called at every switch-in site — voluntary switch, forced switch (Roar/Whirlwind), faint
# replacement, and the initial battle-start send-out — same call pattern as
# _apply_switch_in_abilities. Source ordering confirmed: hazards fire BEFORE switch-in
# abilities (FIRST_EVENT_BLOCK_HAZARDS precedes FIRST_EVENT_BLOCK_GENERAL_ABILITIES /
# FIRST_EVENT_BLOCK_IMMUNITY_ABILITIES in battle_switch_in.c), so this is called before
# _apply_switch_in_abilities at each call site.
# Source: battle_switch_in.c :: TryHazardsOnSwitchIn (L306-378). All three hazard types are
# checked in a fixed order here (Spikes → Toxic Spikes → Stealth Rock) rather than
# replicating source's per-side setter-order queue — this produces identical final HP
# outcomes since independent sequential HP subtractions commute; a faint partway through
# still correctly stops further hazard checks (mirrors IsBattlerAffectedByHazards's
# IsBattlerAlive gate on every hazard type).
func _apply_switch_in_hazards(new_mon: BattlePokemon, mon_side: int) -> void:
	if new_mon.fainted:
		return
	var sc: Dictionary = _side_conditions[mon_side]
	var ng_active: bool = _is_neutralizing_gas_active()
	var grounded: bool = AbilityManager.is_grounded(new_mon, ng_active)
	# Follow-up fixes session, 2026-07-02: Heavy Duty Boots — full immunity to all three
	# hazard types, applied as one shared gate (see ItemManager.is_hazard_immune for the
	# source citation and the Toxic-Spikes-absorb-still-applies nuance).
	var hazard_immune: bool = ItemManager.is_hazard_immune(new_mon, ng_active)

	# M17n-9: Magic Guard — blocks Spikes and Stealth Rock damage below (source:
	# TryHazardsOnSwitchIn, HAZARDS_SPIKES L317-318 and HAZARDS_STEALTH_ROCK L369),
	# but deliberately NOT Toxic Spikes' poison infliction — Toxic Spikes has no
	# such check in source (HAZARDS_TOXIC_SPIKES, L336-359), matching real Magic
	# Guard's own scope: it blocks indirect DAMAGE, not status infliction itself
	# (the resulting residual damage each end-of-turn is already blocked via
	# StatusManager.end_of_turn_damage's own Magic Guard gate).
	var magic_guard_active: bool = AbilityManager.blocks_indirect_damage(new_mon, ng_active)

	# Spikes — grounded-only. Source: TryHazardsOnSwitchIn, case HAZARDS_SPIKES (L306-315):
	#   spikesDmg = maxHP / ((5 - spikesAmount) * 2).
	if sc["spikes_layers"] > 0 and grounded and not hazard_immune and not magic_guard_active:
		var spikes_dmg: int = new_mon.max_hp / ((5 - sc["spikes_layers"]) * 2)
		if spikes_dmg > 0:
			new_mon.current_hp = max(0, new_mon.current_hp - spikes_dmg)
			hazard_damage.emit(new_mon, spikes_dmg, "spikes")
			if new_mon.current_hp == 0:
				new_mon.fainted = true
				pokemon_fainted.emit(new_mon)

	# Toxic Spikes — grounded-only; a grounded Poison-type ABSORBS (clears) it instead of
	# being poisoned — this happens regardless of Heavy Duty Boots (source checks
	# IS_BATTLER_OF_TYPE(POISON) in an earlier branch than the boots gate), so hazard_immune
	# must NOT be applied to the absorb branch, only to the "would be poisoned" branch.
	# Source: TryHazardsOnSwitchIn, case HAZARDS_TOXIC_SPIKES (L328-359).
	if not new_mon.fainted and sc["toxic_spikes_layers"] > 0:
		if TypeChart.TYPE_POISON in new_mon.species.types:
			sc["toxic_spikes_layers"] = 0
			hazard_absorbed.emit(mon_side, "toxic_spikes")
		elif grounded and not hazard_immune:
			var ts_status: int = BattlePokemon.STATUS_TOXIC if sc["toxic_spikes_layers"] >= 2 \
					else BattlePokemon.STATUS_POISON
			# Reuses StatusManager.try_apply_status — already encodes Poison/Steel-type
			# immunity, the one-major-status-at-a-time guard (M3), and (M17b) Pastel
			# Veil's ally-wide poison immunity, so Toxic Spikes correctly can't poison a
			# Steel-type, an already-statused Pokémon, or a Pastel-Veil-protected one,
			# without re-deriving those checks here.
			if StatusManager.try_apply_status(new_mon, ts_status, null, _get_ally(new_mon), ng_active):
				hazard_status_applied.emit(new_mon, ts_status)

	# Stealth Rock — NOT grounded-gated (hits Flying-types and Levitate holders too), but
	# IS gated by Heavy Duty Boots (unconditional block, no type check involved — the boots
	# gate is checked before Stealth Rock even computes its damage in source).
	# Source: TryHazardsOnSwitchIn, case HAZARDS_STEALTH_ROCK (L369-378);
	#   GetStealthHazardDamageByTypesAndHP (L8317-8353).
	if not new_mon.fainted and sc["stealth_rock"] and not hazard_immune and not magic_guard_active:
		var srock_eff: float = TypeChart.get_effectiveness(TypeChart.TYPE_ROCK, new_mon.species.types)
		var srock_dmg: int = _stealth_rock_damage(srock_eff, new_mon.max_hp)
		if srock_dmg > 0:
			new_mon.current_hp = max(0, new_mon.current_hp - srock_dmg)
			hazard_damage.emit(new_mon, srock_dmg, "stealth_rock")
			if new_mon.current_hp == 0:
				new_mon.fainted = true
				pokemon_fainted.emit(new_mon)


# M16d: Stealth Rock's type-effectiveness-based damage table.
# Source: battle_util.c :: GetStealthHazardDamageByTypesAndHP (L8317-8353):
#   0×→0, 0.25×→maxHP/32, 0.5×→maxHP/16, 1×→maxHP/8, 2×→maxHP/4, 4×→maxHP/2
#   (each nonzero case floors to a minimum of 1).
func _stealth_rock_damage(effectiveness: float, max_hp: int) -> int:
	var dmg: int = 0
	if effectiveness == 0.25:
		dmg = max_hp / 32
	elif effectiveness == 0.5:
		dmg = max_hp / 16
	elif effectiveness == 1.0:
		dmg = max_hp / 8
	elif effectiveness == 2.0:
		dmg = max_hp / 4
	elif effectiveness == 4.0:
		dmg = max_hp / 2
	if dmg == 0 and effectiveness != 0.0:
		dmg = 1
	return dmg


func _apply_switch_in_abilities(new_mon: BattlePokemon, mon_side: int) -> void:
	var any_intimidated := false
	var live_opponents: Array = []
	# M17g: new_mon is already in _combatants by the time this runs, so this correctly
	# reflects new_mon's own Neutralizing Gas if it just switched in with it — matching
	# source's dispatch order (Neutralizing Gas's own activation is processed before
	# ABILITYEFFECT_ON_SWITCHIN — battle_switch_in.c L56/L277).
	var ng_active: bool = _is_neutralizing_gas_active()
	# M18w: Red Orb / Blue Orb — ability-set on switch-in, gated per-species (see
	# ItemManager.primal_orb_target_ability_id's own doc comment for the full
	# scope correction: this is ability-set ONLY, not a species/stat/type swap).
	# Deliberately FIRST in this function, before Screen Cleaner/Drizzle/etc. —
	# source dispatches TryPrimalReversion at FIRST_EVENT_BLOCK_GENERAL_ABILITIES,
	# strictly before the general ABILITYEFFECT_ON_SWITCHIN block every other
	# switch-in ability check here belongs to (battle_switch_in.c L275-278), so
	# every later check in this function correctly sees the NEW ability already
	# in place. First production-code load of an AbilityData resource by a fixed
	# ID rather than copied from another BattlePokemon's already-set field (Trace/
	# Mummy both copy; no prior precedent for a fresh load existed here).
	var orb_ability_id: int = ItemManager.primal_orb_target_ability_id(new_mon, ng_active)
	if orb_ability_id != -1:
		var orb_ability: AbilityData = load("res://data/abilities/ability_%04d.tres" % orb_ability_id) as AbilityData
		new_mon.ability = orb_ability
		ability_changed.emit(new_mon, orb_ability_id)
	# M18u: Berserk Gene — switch-in only (no re-trigger later; confirmed absent
	# from ItemBattleEffects' onEffect dispatch). Entirely NO-OP (no consumption,
	# no confusion attempt) if Attack is already at +6 — source's CompareStat
	# guard wraps the WHOLE function, not just the stat-change call (see
	# HOLD_EFFECT_BERSERK_GENE's own doc comment). Consumed regardless of whether
	# confusion actually lands (Own Tempo may block it) — `removeitem` sits at
	# the battle script's shared end label all three branches reach.
	if ItemManager.holds_berserk_gene(new_mon, ng_active) \
			and new_mon.stat_stages[BattlePokemon.STAGE_ATK] < 6:
		var bg_actual: int = StatusManager.apply_stat_change(
				new_mon, BattlePokemon.STAGE_ATK, 2, null, ng_active)
		if bg_actual != 0:
			stat_stage_changed.emit(new_mon, BattlePokemon.STAGE_ATK, bg_actual)
		if StatusManager.try_apply_confusion(new_mon, null, ng_active, null, null, true):
			secondary_applied.emit(new_mon, MoveData.SE_CONFUSION)
		_consume_item(new_mon)
	# M17n-10: Screen Cleaner — removes Reflect/Light Screen/Aurora Veil from BOTH
	# sides unconditionally on switch-in, not just the opponent's. Source:
	# TryRemoveScreens (battle_util.c L9001-9022) clears `SIDE_STATUS_SCREEN_ANY`
	# (Reflect|Light Screen|Aurora Veil — confirmed via include/constants/battle.h;
	# Safeguard/Mist are NOT included) from the holder's own side AND the opposing
	# side, reusing the exact same clear-and-signal shape Brick Break's
	# `move.breaks_screens` branch already established, just applied to both sides
	# instead of one.
	if AbilityManager.effective_ability_id(new_mon, ng_active) == AbilityManager.ABILITY_SCREEN_CLEANER:
		var opp_side: int = 1 - mon_side
		for side in [mon_side, opp_side]:
			var side_sc: Dictionary = _side_conditions[side]
			if side_sc["reflect_turns"] > 0 or side_sc["light_screen_turns"] > 0 \
					or side_sc["aurora_veil_turns"] > 0:
				side_sc["reflect_turns"] = 0
				side_sc["light_screen_turns"] = 0
				side_sc["aurora_veil_turns"] = 0
				screens_broken.emit(side)
		ability_triggered.emit(new_mon, "screen_cleaner")
	for j in range(_combatants.size()):
		if j / _active_per_side == mon_side:  # IsBattlerAlly: same side → skip
			continue
		var opp: BattlePokemon = _combatants[j]
		if opp.fainted or opp.current_hp == 0:  # !IsBattlerAlive: skip
			continue
		live_opponents.append(opp)
		var opp_ally: BattlePokemon = _get_ally(opp)
		var si_result: Dictionary = AbilityManager.try_switch_in(new_mon, opp, opp_ally, ng_active)
		if si_result["atk_change"] != 0:
			stat_stage_changed.emit(opp, BattlePokemon.STAGE_ATK, si_result["atk_change"])
			any_intimidated = true
		if si_result["opponent_guard_dog_change"] != 0:
			stat_stage_changed.emit(opp, BattlePokemon.STAGE_ATK, si_result["opponent_guard_dog_change"])
			ability_triggered.emit(opp, "guard_dog")
			any_intimidated = true
		if si_result["mirror_armor_reflect_change"] != 0:
			stat_stage_changed.emit(new_mon, BattlePokemon.STAGE_ATK, si_result["mirror_armor_reflect_change"])
			ability_triggered.emit(si_result["mirror_armor_holder"], "mirror_armor")
			any_intimidated = true
		if si_result["opponent_speed_change"] != 0:
			stat_stage_changed.emit(opp, BattlePokemon.STAGE_SPEED, si_result["opponent_speed_change"])
			ability_triggered.emit(opp, "rattled")
		if si_result["opponent_defiant_change"] != 0:
			stat_stage_changed.emit(opp, si_result["opponent_defiant_stat"], si_result["opponent_defiant_change"])
			ability_triggered.emit(opp, "defiant_competitive")
		if si_result["cured_own_poison"]:
			ability_triggered.emit(new_mon, "pastel_veil")
		if si_result["cured_status"]:
			ability_triggered.emit(new_mon, "immunity_family_cure")
		if si_result["cured_confusion"]:
			ability_triggered.emit(new_mon, "own_tempo_cure")
		if si_result["cured_infatuation"]:
			ability_triggered.emit(new_mon, "oblivious_cure")
		# M17b: Supersweet Syrup — same per-opponent loop shape as Intimidate, one-time only.
		var sss_actual: int = AbilityManager.try_switch_in_evasion(new_mon, opp, ng_active)
		if sss_actual != 0:
			stat_stage_changed.emit(opp, BattlePokemon.STAGE_EVASION, sss_actual)
			ability_triggered.emit(new_mon, "supersweet_syrup")
	if any_intimidated:
		ability_triggered.emit(new_mon, "intimidate")
	# M17b: Download — needs the combined opposing side, not a per-opponent loop.
	var download_stage: int = AbilityManager.download_stat(new_mon, live_opponents, ng_active)
	if download_stage != -1:
		var dl_actual: int = StatusManager.apply_stat_change(new_mon, download_stage, 1, null, ng_active)
		if dl_actual != 0:
			stat_stage_changed.emit(new_mon, download_stage, dl_actual)
			ability_triggered.emit(new_mon, "download")
	# M17h: Trace — same "sees all live opponents at once" shape as Download, not the
	# per-opponent Intimidate-style loop above (source picks between exactly the two
	# opposing field slots, matching what live_opponents already contains in doubles).
	var traced_id: int = AbilityManager.try_trace(new_mon, live_opponents, ng_active)
	if traced_id != -1:
		ability_changed.emit(new_mon, traced_id)
		ability_triggered.emit(new_mon, "trace")
	# M11: Drizzle / Drought — set field weather on switch-in.
	# Source: ABILITY_DRIZZLE / ABILITY_DROUGHT case in ABILITYEFFECT_ON_SWITCHIN
	#   calls TryChangeBattleWeather (battle_util.c L3213, L3242).
	var set_w: int = AbilityManager.get_switch_in_weather(new_mon, ng_active)
	if set_w != WEATHER_NONE and try_set_weather(set_w, new_mon):
		weather_set.emit(new_mon, set_w)
		_notify_weather_changed()
	# M17c: Hospitality — doubles-only, heals the switching-in Pokémon's own ally.
	var new_mon_ally: BattlePokemon = _get_ally(new_mon)
	var hosp_heal: int = AbilityManager.try_switch_in_ally_heal(new_mon, new_mon_ally, ng_active)
	if hosp_heal > 0:
		new_mon_ally.current_hp = min(new_mon_ally.max_hp, new_mon_ally.current_hp + hosp_heal)
		ability_healed.emit(new_mon_ally, hosp_heal)
		ability_triggered.emit(new_mon, "hospitality")
	# M17n-11: Costar -- doubles-only, copies the ally's current stat stages +
	# focus_energy onto the holder. Reuses the existing stat_changes_copied
	# signal M16e's Psych Up already established for the identical
	# "stat-stage-array copy" shape.
	if AbilityManager.try_costar_copy(new_mon, new_mon_ally, ng_active):
		stat_changes_copied.emit(new_mon, new_mon_ally)
		ability_triggered.emit(new_mon, "costar")
	# M17n-4: Multitype — type set from the holder's held Plate item, evaluated ONLY
	# at switch-in. Source's FORM_CHANGE_ITEM_HOLD dispatch is confirmed (via a full
	# enumeration of every TryBattleFormChange call site in battle_util.c) to be an
	# OVERWORLD-only trigger (party menu / PC box / script give-item) — never invoked
	# from any in-battle FORM_CHANGE_BATTLE_* dispatch — so a mid-battle held-item
	# change (Trick, Knock Off, this project's own Pickpocket/Magician/Symbiosis) does
	# NOT retype a Multitype holder. This corrects the tier's own recon assumption
	# ("checked whenever the held item changes"); confirmed by checking, not assumed.
	# Not gated on ng_active explicitly: AbilityData's cant_be_suppressed=true for
	# Multitype already makes effective_ability_id bypass Neutralizing Gas correctly.
	var mt_type: int = ItemManager.multitype_plate_type(new_mon, ng_active)
	if mt_type != TypeChart.TYPE_NONE \
			and AbilityManager.effective_ability_id(new_mon, ng_active) == AbilityManager.ABILITY_MULTITYPE:
		_set_mon_type(new_mon, mt_type)
		type_changed.emit(new_mon, mt_type)
	# M17n-10: Screen Cleaner — removes Reflect/Light Screen/Aurora Veil from BOTH
	# sides of the field on switch-in. Source: battle_util.c ABILITY_SCREEN_CLEANER
	# case (L3205-3210), calling the shared TryRemoveScreens (L9001-9017) — confirmed
	# from source to clear BOTH `battlerSide` and the opposing side, not just the
	# opponent's (a common point of confusion with this ability). `ability_triggered`
	# only fires if something was actually removed, matching source's own
	# `shouldAbilityTrigger && TryRemoveScreens(battler)` gate (no message on a no-op).
	if AbilityManager.effective_ability_id(new_mon, ng_active) == AbilityManager.ABILITY_SCREEN_CLEANER:
		var any_screen_removed := false
		for sc_side in range(2):
			var sc_screen: Dictionary = _side_conditions[sc_side]
			if sc_screen["reflect_turns"] > 0 or sc_screen["light_screen_turns"] > 0 \
					or sc_screen["aurora_veil_turns"] > 0:
				sc_screen["reflect_turns"] = 0
				sc_screen["light_screen_turns"] = 0
				sc_screen["aurora_veil_turns"] = 0
				screens_broken.emit(sc_side)
				any_screen_removed = true
		if any_screen_removed:
			ability_triggered.emit(new_mon, "screen_cleaner")
	# M18r: Room Service — the switch-in half (the OTHER trigger, "Trick Room just
	# SET," is wired at the Trick Room move-effect block itself, not here). Source:
	# hold_effects.h's HOLD_EFFECT_ROOM_SERVICE entry has .onSwitchIn=TRUE alongside
	# .onEffect=TRUE — a correction to this tier's own plan doc, which named only
	# this half.
	if trick_room_turns > 0 and ItemManager.holds_room_service(new_mon, ng_active):
		var rs_si_actual: int = StatusManager.apply_stat_change(
				new_mon, BattlePokemon.STAGE_SPEED, -1, null, ng_active)
		if rs_si_actual != 0:
			stat_stage_changed.emit(new_mon, BattlePokemon.STAGE_SPEED, rs_si_actual)
			_consume_item(new_mon)
	# M17n-10: Forecast — also checked at switch-in specifically (source:
	# battle_switch_in.c L412 calls ABILITYEFFECT_ON_WEATHER for the newly-arrived
	# battler, in addition to the field-wide broadcast on an actual weather CHANGE —
	# see _notify_weather_changed) — a Castform switching into already-active weather
	# picks up the correct form immediately rather than waiting for the next change.
	var switch_in_forecast_type: int = AbilityManager.forecast_type(new_mon, ng_active, _effective_weather())
	if switch_in_forecast_type != TypeChart.TYPE_NONE \
			and switch_in_forecast_type not in new_mon.species.types:
		_set_mon_type(new_mon, switch_in_forecast_type)
		type_changed.emit(new_mon, switch_in_forecast_type)
		ability_triggered.emit(new_mon, "forecast")


# M14a: default target combatant index for a given attacker.
# Returns the first field slot of the opposing side (combatant index).
# Overridden by queue_move_targeted "target" field or AI decision.
func _default_target(combatant_idx: int) -> int:
	var side: int = combatant_idx / _active_per_side
	return (1 - side) * _active_per_side


# Clear all volatile fields on a Pokémon (faint or switch-out, non-BP).
# Source: FaintClearSetData / SwitchInClearSetData (battle_main.c L3266, L3117)
func _clear_volatiles(mon: BattlePokemon) -> void:
	mon.confusion_turns = 0
	mon.flinched = false
	mon.charging_move = null
	mon.semi_invulnerable = MoveData.SEMI_INV_NONE
	mon.substitute_hp = 0
	mon.protect_active = false
	mon.destiny_bond = false
	mon.disabled_move = null
	mon.disable_turns = 0
	mon.encored_move = null
	mon.encore_turns = 0
	mon.bide_turns = 0
	mon.bide_damage = 0
	mon.focus_energy = false
	mon.micle_boost_active = false
	mon.minimized = false
	mon.defense_curled = false
	mon.rollout_turns = 0
	mon.rollout_base_power = 0
	mon.truant_loafing = false
	mon.flash_fire_active = false
	mon.slow_start_timer = 0
	mon.used_protean_libero = false
	# M17n-7: unburden_active/cud_chew_armed live in source's `volatiles` struct
	# (cleared on switch), unlike last_consumed_berry below, which is deliberately
	# party-state-scoped and NOT touched here — see BattlePokemon's own doc comments.
	mon.unburden_active = false
	mon.cud_chew_armed = false
	# [M18.5d-2] Attract's infatuation volatile — cured by switch-out/faint like
	# every other one-battle-stint volatile here (Step 0's confirmed cure condition,
	# `mon`'s OWN half). `mon.infatuated_by` is who INFATUATED `mon`, not who `mon`
	# infatuated — that's the OTHER direction, handled by the scan just below.
	mon.infatuated_by = null
	# [M18.5d-3] The reciprocal cure condition, closing the gap [M18.5d-2] flagged:
	# real source clears infatuation on every OTHER battler whose `infatuation`
	# points at THIS mon's slot the instant this mon leaves the field — TWO source
	# functions unified here (SwitchInClearSetData, battle_main.c L3167, called on
	# every switch-in whether voluntary or faint-replacement; FaintClearSetData,
	# L3281, called the instant a battler faints). Confirmed via this project's own
	# 4 real `_clear_volatiles` call sites (regular faint / Destiny-Bond-triggered
	# faint / Aftermath-Innards-Out-triggered faint, all inside the same
	# faint-detection loop; voluntary AND forced switch-out via `_switch_out_clear`)
	# that ONE unified scan here, rather than reproducing source's two separate
	# functions, correctly covers every real "this battler just left the field"
	# moment in this project's simpler single-threaded turn architecture — verified
	# each call site fires with `_combatants` still holding every OTHER currently-
	# active battler correctly (the switch-out case calls this BEFORE `_combatants`'
	# own slot gets reassigned to the replacement, confirmed by reading
	# `_do_voluntary_switch`/`_do_forced_switch_in` directly).
	for other: BattlePokemon in _combatants:
		if other != mon and other.infatuated_by == mon:
			other.infatuated_by = null

	# [M18.5f] Bind/Wrap-family trap — the direct parallel Step 0 confirmed exists:
	# real source clears wrapped on THIS mon's own departure (mon's own half, right
	# below) AND, via the SAME two source functions already unified into this one
	# chokepoint, on every OTHER battler this mon had trapped, the instant this mon
	# leaves the field (battle_main.c L3169-3170/L3283-3284 — literally the next two
	# lines after the infatuation clear above in both real source functions).
	# Reuses [M18.5d-3]'s reciprocal-scan pattern verbatim rather than inventing a
	# second shape for what is structurally the identical situation.
	mon.wrapped_by = null
	mon.wrapped_turns = 0
	for other: BattlePokemon in _combatants:
		if other != mon and other.wrapped_by == mon:
			other.wrapped_by = null
			other.wrapped_turns = 0


# M9: clear volatiles on switch-out (superset of _clear_volatiles: also resets
# stat stages and Counter/Mirror Coat per-turn trackers).
# Non-volatile status (burn/poison/paralysis/sleep/freeze) persists — SOURCE:
#   SwitchInClearSetData does NOT touch gBattleMons[battler].status1 (battle_main.c L3117-3264).
# Toxic counter persists — it is stored in STATUS1 bits 8-11 (STATUS1_TOXIC_COUNTER)
#   which SwitchInClearSetData does NOT clear. Gen 5+ behavior; confirmed no
#   B_TOXIC_COUNTER_RESET config flag in pokeemerald-expansion.
# Stat stages reset to 0 — SOURCE: SwitchInClearSetData L3124-3126 (except Baton Pass).
# protect_consecutive resets — the consecutive-use streak is per-battle-entry.
# M17i: Regenerator/Natural Cure — called at every site that reaches source's
# Cmd_switchoutabilities (voluntary switch, Roar/Whirlwind, Baton Pass), BEFORE
# _switch_out_clear, though ordering vs. that function doesn't actually matter here
# since _switch_out_clear never touches current_hp/status/toxic_counter. Deliberately
# NOT called from _do_switch_in (faint replacement) — a fainted mon never reaches
# source's returntoball/switchoutabilities at all.
func _apply_switch_out_abilities(mon: BattlePokemon) -> void:
	var so_result: Dictionary = AbilityManager.try_switch_out(mon, _is_neutralizing_gas_active())
	if so_result["healed_amount"] > 0:
		ability_healed.emit(mon, so_result["healed_amount"])
		ability_triggered.emit(mon, "regenerator")
	if so_result["cured_status"]:
		ability_triggered.emit(mon, "natural_cure")


func _switch_out_clear(mon: BattlePokemon) -> void:
	_clear_volatiles(mon)
	for _si in range(mon.stat_stages.size()):
		mon.stat_stages[_si] = 0
	mon.last_physical_damage = 0
	mon.last_special_damage = 0
	mon.protect_consecutive = 0
	mon.last_move_used = null
	# M12: Choice lock clears on switch-out (not on faint — fainted mon has no future turns).
	# Source: SwitchInClearSetData (battle_main.c L3117) clears chosenMovePositions.
	mon.choice_locked_move = null


# M9/M16e: save Baton Pass passable state before switch-out clearing.
# Passable fields derived from VOLATILE_DEFINITIONS V_BATON_PASSABLE entries
# (include/constants/battle.h L209-319) and explicit copies in SwitchInClearSetData (L3146-3185).
# From our implemented fields:
#   stat_stages     — NOT cleared for Baton Pass (L3122 guard)
#   confusion_turns — V_BATON_PASSABLE (VOLATILE_CONFUSION, L210)
#   substitute_hp   — explicitly copied at L3185
#   focus_energy    — V_BATON_PASSABLE (VOLATILE_FOCUS_ENERGY, L236). M9 predates Focus
#     Energy (added in M16a), so it was missing from the original passable set — added now
#     during M16e's Baton Pass review as the task explicitly asked to re-confirm the exact
#     passable list against every volatile currently implemented, not just the M9-era ones.
#     Every other V_BATON_PASSABLE volatile in source (leechSeed, perishSong, aquaRing,
#     root/ingrain, gastroAcid, embargo, telekinesis, magnetRise, healBlock, powerTrick,
#     noRetreat, escapePrevention, cursed, dragonCheer, mudSport, waterSport,
#     infiniteConfusion) has no corresponding field in this project — not a gap, since none
#     of those mechanics are implemented at all yet. minimized/defense_curled/destiny_bond/
#     protect_active/disabled_move/encored_move/rollout_turns are correctly NOT passed —
#     none of them appear in VOLATILE_DEFINITIONS' V_BATON_PASSABLE set.
func _baton_pass_save(mon: BattlePokemon) -> Dictionary:
	return {
		"stat_stages":     mon.stat_stages.duplicate(),
		"confusion_turns": mon.confusion_turns,
		"substitute_hp":   mon.substitute_hp,
		"focus_energy":    mon.focus_energy,
	}


# M9/M16e: apply saved Baton Pass passables to the incoming Pokémon.
func _baton_pass_apply(mon: BattlePokemon, data: Dictionary) -> void:
	var src: Array = data["stat_stages"]
	for _si in range(src.size()):
		mon.stat_stages[_si] = src[_si]
	mon.confusion_turns = data["confusion_turns"]
	mon.substitute_hp   = data["substitute_hp"]
	mon.focus_energy    = data["focus_energy"]


# M9/M14a: voluntary switch — switch-out cleanup, party update, switch-in ability.
# M14a: takes combatant_idx (0..N-1) instead of side, so doubles can switch
#   either field slot independently. side and field_slot are derived from combatant_idx.
func _do_voluntary_switch(combatant_idx: int, slot: int) -> void:
	var side: int = combatant_idx / _active_per_side
	var field_slot: int = combatant_idx % _active_per_side
	var old_mon: BattlePokemon = _combatants[combatant_idx]
	_apply_switch_out_abilities(old_mon)
	_switch_out_clear(old_mon)
	_parties[side].active_indices[field_slot] = slot
	_combatants[combatant_idx] = _parties[side].get_active_at(field_slot)
	var new_mon: BattlePokemon = _combatants[combatant_idx]
	new_mon.switched_in_this_turn = true
	_reset_mon_type(new_mon)
	pokemon_switched_out.emit(old_mon, side)
	pokemon_switched_in.emit(new_mon, side, slot)
	# Switch-in hazards then abilities fire for the incoming Pokémon.
	# Source: AbilityBattleEffects(ABILITYEFFECT_ON_SWITCHIN, ...) (battle_util.c L2960)
	_apply_switch_in_hazards(new_mon, side)
	_apply_switch_in_abilities(new_mon, side)


# M9/M14b: forced switch-in for Roar/Whirlwind — forces out the combatant at
# the given field_slot of the specified side.
# M14b: field_slot parameter defaults to 0 (singles-compatible) but is now passed
# correctly from Roar execution using the actual targeted combatant's field slot.
# Source: Cmd_BS_JumpIfRoarFails (battle_script_commands.c L7426): applies forced
#   switch to gBattlerTarget — the specific targeted combatant, not always position 0.
func _do_forced_switch_in(side: int, slot: int, field_slot: int = 0) -> void:
	var combatant_idx: int = side * _active_per_side + field_slot
	# M17i: Regenerator/Natural Cure fire here too — source's BattleScript_RoarSuccessRet
	# calls `switchoutabilities BS_TARGET`, confirming forced switch-outs are not exempt.
	_apply_switch_out_abilities(_combatants[combatant_idx])
	_switch_out_clear(_combatants[combatant_idx])
	_parties[side].active_indices[field_slot] = slot
	_combatants[combatant_idx] = _parties[side].get_active_at(field_slot)
	var new_mon: BattlePokemon = _combatants[combatant_idx]
	new_mon.switched_in_this_turn = true
	_reset_mon_type(new_mon)
	# Switch-in hazards then abilities fire for the forced-in Pokémon.
	_apply_switch_in_hazards(new_mon, side)
	_apply_switch_in_abilities(new_mon, side)


# M9/M14a: switch-in after faint (no switch-out clear; old mon already cleared on faint).
# M14a: takes combatant_idx so doubles can replace either field slot independently.
func _do_switch_in(combatant_idx: int, slot: int) -> void:
	var side: int = combatant_idx / _active_per_side
	var field_slot: int = combatant_idx % _active_per_side
	_parties[side].active_indices[field_slot] = slot
	_combatants[combatant_idx] = _parties[side].get_active_at(field_slot)
	var new_mon: BattlePokemon = _combatants[combatant_idx]
	new_mon.switched_in_this_turn = true
	_reset_mon_type(new_mon)
	pokemon_switched_in.emit(new_mon, side, slot)
	_apply_switch_in_hazards(new_mon, side)
	_apply_switch_in_abilities(new_mon, side)


# M9/M10/M14a: determine replacement slot — priority: test queue, then AI, then auto-select.
# M14a: takes combatant_idx; side derived internally. _replacement_queues indexed by
#   combatant_idx so queue_replacement(side, slot) and queue_replacement_for(idx, slot)
#   both work correctly (in singles, side == combatant_idx).
func _get_replacement_slot(combatant_idx: int) -> int:
	var side: int = combatant_idx / _active_per_side
	if not _replacement_queues[combatant_idx].is_empty():
		var slot: int = _replacement_queues[combatant_idx].pop_front()
		var party: BattleParty = _parties[side]
		if slot >= 0 and slot < party.members.size() and not party.members[slot].fainted:
			return slot
	# M10: AI chooses the best matchup replacement.
	# Source: Ai_InitPartyStruct + GetSwitchinCandidate SWITCHIN_CONSIDER_MOST_SUITABLE
	#   (battle_ai_switch.c L55+). AI has the opponent's data to make this choice.
	if _trainer_ais[side] != null:
		var opponent: BattlePokemon = _get_first_opponent(_combatants[combatant_idx])
		return _trainer_ais[side].choose_replacement(_parties[side], opponent)
	return _parties[side].get_first_non_fainted_not_active()


# M9/M14a: determine Baton Pass incoming slot from queue or auto-select first valid.
# M14a: takes combatant_idx; _baton_pass_queues indexed by combatant_idx.
#   In singles, combatant_idx == side so queue_baton_pass_target(side, slot) is compat.
func _get_baton_pass_slot(combatant_idx: int) -> int:
	var side: int = combatant_idx / _active_per_side
	if not _baton_pass_queues[combatant_idx].is_empty():
		var slot: int = _baton_pass_queues[combatant_idx].pop_front()
		var party: BattleParty = _parties[side]
		if slot >= 0 and slot < party.members.size() \
				and not party.active_indices.has(slot) \
				and not party.members[slot].fainted:
			return slot
	return _parties[side].get_first_non_fainted_not_active()


# M16e: true if the combatant at pursuer_idx has queued Pursuit AND the combatant at
# switcher_idx has a queued switch AND they're on opposing sides.
# Source: SetTargetToNextPursuiter (battle_util.c L9827): B_PURSUIT_TARGET >= GEN_4
#   (GEN_LATEST) means any opposing Pursuit user qualifies, not only one that specifically
#   targeted the switcher — so this deliberately does not check _chosen_targets.
func _pursuit_targets_switcher(pursuer_idx: int, switcher_idx: int) -> bool:
	var mv: MoveData = _chosen_moves[pursuer_idx]
	if mv == null or not mv.is_pursuit:
		return false
	if _chosen_switch_slots[switcher_idx] < 0:
		return false
	return (pursuer_idx / _active_per_side) != (switcher_idx / _active_per_side)


# M17n-5: Analytic's "is `mon` the last battler with a pending MOVE action this turn"
# check. Source: battle_util.c :: IsLastMonToMove (L1098-1115) — checked against the
# FINAL resolved turn order (`_turn_order`, already fully sorted by
# _phase_priority_resolution, including Trick Room/Pursuit/[M17n-3]'s priority
# abilities — NOT a raw speed comparison, confirmed via source rather than assumed).
# `_turn_order` holds BattlePokemon references directly (not combatant indices), so
# `mon`'s own position is found via `.find()`; later positions are checked against
# `_chosen_switch_slots` (via `_actor_indices`) to distinguish a still-pending MOVE
# action from a switch action or an already-fainted battler — mirrors source's own
# `gActionsByTurnOrder[i] == B_ACTION_USE_MOVE` check exactly.
func _is_last_to_move(mon: BattlePokemon) -> bool:
	var pos: int = _turn_order.find(mon)
	if pos == -1 or pos >= _turn_order.size() - 1:
		return true
	for i in range(pos + 1, _turn_order.size()):
		var other: BattlePokemon = _turn_order[i]
		if other.fainted:
			continue
		var oidx: int = _actor_indices.get(other, _combatants.find(other))
		if _chosen_switch_slots[oidx] < 0:
			return false  # a later battler still has a pending MOVE action
	return true


# M18j: Zoom Lens — has the TARGET already acted (had its own action resolved)
# this turn, at the moment the attacker's accuracy check runs? Source:
# HasBattlerActedThisTurn(battlerDef) (battle_util.c L10339-10340), checked via
# this project's own _turn_order/_current_actor_index position tracking, the
# same infrastructure `_is_last_to_move` above already established for
# Analytic ([M17n-5]). Source's secondary `isFirstTurn != 2` edge-case flag is
# deliberately NOT modeled — a documented simplification, not a silent omission.
func _has_target_already_acted(target: BattlePokemon) -> bool:
	var pos: int = _turn_order.find(target)
	if pos == -1:
		return false
	return pos < _current_actor_index


# M16e: Conversion 2's resist-type selection. Builds the candidate pool — types that
# resist type_to_resist at 0x or 0.5x, EXCLUDING types the user already has — then picks
# uniformly at random. Returns -1 if the pool is empty (matches source's fail case when
# the reject-already-had loop exhausts the resistTypes bitmask).
# Source: battle_script_commands.c :: Cmd_settypetorandomresistance (L8009-8077):
#   resistTypes built via GetTypeModifier == UQ_4_12(0) or UQ_4_12(0.5); loop does
#   `Random() % NUMBER_OF_MON_TYPES`, discarding user's-already-that-type picks.
# _force_conversion2_pick test seam: null = real RNG; else an index into the pool AFTER
# it's built in ascending TypeChart.TYPE_* id order (deterministic for tests).
func _pick_conversion2_type(user: BattlePokemon, type_to_resist: int) -> int:
	var candidates: Array = []
	for t in range(1, 20):  # TYPE_NORMAL(1)..TYPE_FAIRY(19); NUMBER_OF_MON_TYPES = 18
		if t == TypeChart.TYPE_MYSTERY:
			continue
		if TypeChart.TABLE[type_to_resist][t] <= 0.5 and not (t in user.species.types):
			candidates.append(t)
	if candidates.is_empty():
		return -1
	if _force_conversion2_pick != null:
		var idx: int = clampi(int(_force_conversion2_pick), 0, candidates.size() - 1)
		return candidates[idx]
	return candidates[randi() % candidates.size()]


# M16e: mono-types a Pokémon (Conversion / Conversion 2). Source's SET_BATTLER_TYPE sets
# both type slots to the same value; this project instead follows PokemonSpecies.types'
# existing convention of [type, TYPE_NONE] for a single-typed mon (equivalent result —
# get_effectiveness() skips the second type whenever it's TYPE_NONE). Uses resize + index
# assignment rather than a literal-array reassignment: GDScript 4.x typed Array[int]
# properties silently fail (or reject at parse time, per Array[int](...) constructor
# syntax) when reassigned from certain literal forms — see the M9 decisions.md note on
# typed Array assignment; loop/index assignment is the established safe pattern here.
func _set_mon_type(mon: BattlePokemon, new_type: int) -> void:
	if mon.species.types.size() < 2:
		mon.species.types.resize(2)
	mon.species.types[0] = new_type
	mon.species.types[1] = TypeChart.TYPE_NONE


# Follow-up fixes session, 2026-07-02: restores this Pokémon's natural species types on
# every switch-in, undoing any Conversion/Conversion 2 mutation from its last time on the
# field. Source: CopyMonAbilityAndTypesToBattleMon (battle_util.c L9365-9379) and
# Cmd_switchindataupdate (battle_script_commands.c L5030-5032) both repopulate
# gBattleMons[battler].types from GetSpeciesType() at every switch-in event — this project's
# BattlePokemon objects are long-lived (unlike source's per-slot repopulated struct), so the
# equivalent here is restoring from the `original_types` cache captured once at construction
# (see BattlePokemon.original_types) rather than a fresh species lookup, since `species.types`
# itself is the field _set_mon_type mutates and can no longer be trusted as "natural" once a
# Conversion has happened. A no-op for any Pokémon that has never used Conversion/Conversion 2.
# Called at all 5 switch-in sites, immediately before hazards/abilities evaluate the mon's
# type (same 5 sites _apply_switch_in_hazards was wired into during M16d — see that
# milestone's decisions.md entry for why there are 5, not 3).
func _reset_mon_type(mon: BattlePokemon) -> void:
	var orig: Array = mon.original_types
	mon.species.types.resize(orig.size())
	for _ti in range(orig.size()):
		mon.species.types[_ti] = orig[_ti]


# Gen 5+ protect success formula. First use: always succeeds.
# Subsequent consecutive uses: success chance = 1 / (3^n).
# Source: battle_util.c :: CanUseMoveConsecutively (L10862)
#   sGen5ProtectFailChances = {1, 3, 9, 27}
func _roll_protect_success(consecutive: int) -> bool:
	const DENOMS: Array = [1, 3, 9, 27]
	var idx: int = clampi(consecutive, 0, DENOMS.size() - 1)
	var denom: int = DENOMS[idx]
	return denom == 1 or (randi() % denom == 0)


# Magnitude's weighted base-power roll.
# Source: battle_move_resolution.c :: CalculateMagnitudeDamage (L5196-5234):
#   magnitude = RandomUniform(0, 99); weighted bands →
#   [0,5)=10, [5,15)=30, [15,35)=50, [35,65)=70, [65,85)=90, [85,95)=110, [95,100)=150.
# _force_magnitude_power test seam: null = real RNG; else pin to the forced value.
func _roll_magnitude_power() -> int:
	if _force_magnitude_power != null:
		return int(_force_magnitude_power)
	var roll: int = randi() % 100
	if roll < 5:
		return 10
	elif roll < 15:
		return 30
	elif roll < 35:
		return 50
	elif roll < 65:
		return 70
	elif roll < 85:
		return 90
	elif roll < 95:
		return 110
	else:
		return 150


# [M19-pre1] Low Kick / Grass Knot power lookup — the TARGET's own weight
# only (hectograms), NOT a ratio. Confirmed a genuinely different formula
# from _heat_crash_power below despite both being "weight-based."
# Source: sWeightToDamageTable, battle_util.c L6022-6029.
static func _low_kick_power(target_weight: int) -> int:
	if target_weight < 100:
		return 20
	elif target_weight < 250:
		return 40
	elif target_weight < 500:
		return 60
	elif target_weight < 1000:
		return 80
	elif target_weight < 2000:
		return 100
	else:
		return 120


# [M19-pre1] Heavy Slam / Heat Crash power lookup — the INTEGER RATIO of the
# attacker's weight to the target's weight (hectograms), indexed directly
# into a fixed table (capped at the table's last entry for ratio >= 5).
# Source: sHeatCrashPowerTable, battle_util.c L6027-6033.
static func _heat_crash_power(attacker_weight: int, target_weight: int) -> int:
	const TABLE: Array = [40, 40, 60, 80, 100, 120]
	var ratio: int = attacker_weight / target_weight
	return TABLE[clampi(ratio, 0, TABLE.size() - 1)]


# [M19-pre1] Return / Pika Papow / Veevee Volley power from the attacker's
# own friendship (0-255). A universal power==0→1 floor applies (source:
# battle_util.c L6371-6372, after the whole basePower switch) — friendship=0
# would otherwise compute power=0.
# Source: battle_util.c, case EFFECT_RETURN (L6148-6150).
static func _return_power(friendship: int) -> int:
	return maxi(1, 10 * friendship / 25)


# [M19-pre1] Frustration power — the INVERSE of _return_power: derived from
# (MAX_FRIENDSHIP - friendship), not friendship directly. Same power==0→1
# floor applies (friendship=255 would otherwise compute power=0).
# Source: battle_util.c, case EFFECT_FRUSTRATION (L6151-6153). MAX_FRIENDSHIP=255
# (include/constants/pokemon.h L223).
static func _frustration_power(friendship: int) -> int:
	return maxi(1, 10 * (255 - friendship) / 25)


# Synchronize back-reflect helper: if holder has Synchronize and received an eligible
# status from source, apply the same status back to source. Emits signals on fire.
# Source: TrySynchronizeActivation (battle_script_commands.c L2130)
func _try_synchronize(holder: BattlePokemon, source: BattlePokemon, applied_status: int) -> void:
	var back: int = AbilityManager.try_synchronize(holder, source, applied_status, _is_neutralizing_gas_active())
	if back != 0:
		secondary_applied.emit(source, _status_to_se(back))
		ability_triggered.emit(holder, "synchronize")


# Convert a BattlePokemon.STATUS_* to the closest MoveData.SE_* value.
# Used for signal emission when an ability or Synchronize applies a status.
func _se_to_status(se: int) -> int:
	match se:
		MoveData.SE_BURN:      return BattlePokemon.STATUS_BURN
		MoveData.SE_FREEZE:    return BattlePokemon.STATUS_FREEZE
		MoveData.SE_PARALYSIS: return BattlePokemon.STATUS_PARALYSIS
		MoveData.SE_SLEEP:     return BattlePokemon.STATUS_SLEEP
		MoveData.SE_TOXIC:     return BattlePokemon.STATUS_TOXIC
		MoveData.SE_POISON:    return BattlePokemon.STATUS_POISON
	return 0


func _status_to_se(status: int) -> int:
	match status:
		BattlePokemon.STATUS_BURN:      return MoveData.SE_BURN
		BattlePokemon.STATUS_PARALYSIS: return MoveData.SE_PARALYSIS
		# [M18.5g] Corrected: this used to collapse to SE_TOXIC ("no distinct SE for
		# regular poison") — now that SE_POISON exists (added for Twineedle), this
		# mapping is accurate for its OTHER two call sites too: contact status
		# (Poison Point/Poison Touch inflict regular STATUS_POISON, not Toxic — this
		# was silently mislabeling that signal before) and Synchronize reflection.
		# Verified no existing test asserts the old (wrong) SE_TOXIC value for either.
		BattlePokemon.STATUS_POISON:    return MoveData.SE_POISON
		BattlePokemon.STATUS_TOXIC:     return MoveData.SE_TOXIC
	return MoveData.SE_NONE


# Returns a random MoveData not banned from Metronome, or null if pool is empty.
# Source: battle_move_resolution.c :: GetMetronomeMove (L4998)
func _pick_metronome_move() -> MoveData:
	var dir: DirAccess = DirAccess.open("res://data/moves/")
	if dir == null:
		return null
	var pool: Array = []
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if fname.ends_with(".tres"):
			var m: MoveData = load("res://data/moves/" + fname) as MoveData
			if m != null and (m.ban_flags & MoveData.BAN_METRONOME) == 0:
				pool.append(m)
		fname = dir.get_next()
	dir.list_dir_end()
	if pool.is_empty():
		return null
	return pool[randi() % pool.size()]


# M11: Check whether a Pokémon is immune to weather chip damage.
# Source: HandleEndTurnWeatherDamage (battle_end_turn.c L143–182).
# Sandstorm: immune if any type is Rock(6), Ground(5), or Steel(9), OR semi-invulnerable.
# Hail:      immune if any type is Ice(16), OR semi-invulnerable.
# M17n-6: Overcoat — full weather-chip immunity (sandstorm and hail alike).
# [M17n-2] follow-up fix: Sand Veil/Sand Force/Sand Rush (sandstorm) and Snow Cloak
# (hail) ALSO grant chip immunity — corrects [M17n-2]'s original, since-confirmed-
# wrong conclusion that these abilities grant no such immunity. See
# AbilityManager.blocks_weather_chip_damage's doc comment for the full source
# citation and per-weather gating; `current_weather` (the already-effective-weather
# value this function's caller resolves) is threaded through so Sand Veil/Sand
# Force/Sand Rush don't incorrectly exempt hail, and Snow Cloak doesn't incorrectly
# exempt sandstorm. No Mold-Breaker/`attacker` param — see that function's own doc
# comment for why (end-of-turn ticks are outside any move-processing window).
func _is_weather_damage_immune(
		mon: BattlePokemon, current_weather: int, ng_active: bool = false) -> bool:
	if mon.semi_invulnerable != MoveData.SEMI_INV_NONE:
		return true
	if AbilityManager.blocks_weather_chip_damage(mon, ng_active, current_weather):
		return true
	# M17n-9: Magic Guard — full indirect-damage immunity, weather chip included.
	if AbilityManager.blocks_indirect_damage(mon, ng_active):
		return true
	# M18r: Safety Goggles — checked at the SAME source site Overcoat's own
	# weather-chip exemption occupies (battle_end_turn.c L151/L174).
	if ItemManager.holds_safety_goggles(mon, ng_active):
		return true
	var types: Array = mon.species.types
	match current_weather:
		WEATHER_SANDSTORM:
			for t in types:
				if t == TypeChart.TYPE_ROCK or t == TypeChart.TYPE_GROUND or t == TypeChart.TYPE_STEEL:
					return true
		WEATHER_HAIL:
			for t in types:
				if t == TypeChart.TYPE_ICE:
					return true
	return false


# M15 Task 3: Returns true when all move slots have 0 PP (or the Pokémon has no moves).
# Source: battle_main.c L4727-4728 — noValidMoves check before move substitution.
func _is_forced_struggle(mon: BattlePokemon) -> bool:
	if mon.moves.is_empty():
		return true
	for _pi in range(mon.current_pp.size()):
		if mon.current_pp[_pi] > 0:
			return false
	return true


# Apply a pre-calculated damage amount to defender, routing through substitute if active.
# Used by Counter, Mirror Coat, and Bide release (all skip the DamageCalculator formula).
func _apply_fixed_dmg_to_target(attacker: BattlePokemon, defender: BattlePokemon,
		move: MoveData, damage: int) -> void:
	# M17n-9: Infiltrator bypasses Substitute here too (Counter/Mirror Coat/Bide).
	if defender.substitute_hp > 0 and not move.ignores_substitute \
			and not AbilityManager.bypasses_infiltrator_barriers(attacker, _is_neutralizing_gas_active()):
		var sub_dmg: int = min(damage, defender.substitute_hp)
		defender.substitute_hp -= damage
		if defender.substitute_hp <= 0:
			defender.substitute_hp = 0
			substitute_broke.emit(defender)
		move_executed.emit(attacker, defender, move, sub_dmg)
	else:
		defender.current_hp = max(0, defender.current_hp - damage)
		move_executed.emit(attacker, defender, move, damage)


# [M18.5g] Resolves the hit count for a multi-hit move at the moment it's used.
# strike_count moves (fixed) return that value directly — the ONE exception is
# Triple Kick/Triple Axel, which also set strike_count=3 but can independently
# miss and stop early per hit (handled in the loop below, not here — this
# function only determines the MAXIMUM reachable hit count).
# multi_hit moves (variable) roll once: 35% 2 hits / 35% 3 hits / 15% 4 hits /
# 15% 5 hits (Gen5+ weighting — see MoveData.multi_hit's own doc comment for the
# full source citation and the older-branch note).
# [M18.5i] Skill Link/Loaded Dice wired in here, both scoped to TRUE variable
# multi_hit moves only — fixed strike_count moves return above, unconditionally,
# matching CancelerMultihitMoves' own if/else-if branch ordering
# (battle_move_resolution.c L2306-2346), where the ability/item checks live
# entirely inside the IsMultiHitMove() branch, never the GetMoveStrikeCount()
# one (Population Bomb is the sole strike_count exception, excluded from this
# project's roster entirely per [M18.5g]).
func _resolve_multi_hit_count(move: MoveData, attacker: BattlePokemon, ng_active: bool = false) -> int:
	if move.strike_count > 1:
		return move.strike_count
	if move.multi_hit:
		if _force_multi_hit_count != null:
			return int(_force_multi_hit_count)
		# Skill Link: forces the maximum — CancelerMultihitMoves' own
		# ABILITY_SKILL_LINK branch (battle_move_resolution.c L2331-2332),
		# checked BEFORE the item-based Loaded Dice roll, matching source's
		# own if/else-if precedence (though a mon can never hold both anyway —
		# one ability slot).
		if AbilityManager.effective_ability_id(attacker, ng_active) == AbilityManager.ABILITY_SKILL_LINK:
			return 5
		# Loaded Dice: re-rolls within [4,5] instead of the standard weighted
		# [2,5] distribution — SetRandomMultiHitCounter, battle_move_resolution.c
		# L2306-2307.
		var atk_item: ItemData = ItemManager.effective_held_item(attacker, ng_active)
		if atk_item != null and atk_item.hold_effect == ItemManager.HOLD_EFFECT_LOADED_DICE:
			return randi_range(4, 5)
		# RandomWeighted(RNG_HITS, 0, 0, 7, 7, 3, 3) → hits 2/3/4/5 at weights 7/7/3/3
		# (sum 20): battle_move_resolution.c L2311.
		var roll: int = randi() % 20
		if roll < 7:
			return 2
		elif roll < 14:
			return 3
		elif roll < 17:
			return 4
		else:
			return 5
	return 1


# [M18.5g] Resolves an entire multi-hit move (the 30 in-scope moves of the
# strike_count/multi_hit family — see MoveData's own doc comments for the full
# roster and Population Bomb's exclusion). Replaces a single _do_damaging_hit
# call with a loop, per Step 0's confirmed per-mechanism determination:
#
# - Accuracy: ONE check gates the whole sequence (already done by the caller,
#   before this function is ever reached) for every move EXCEPT Triple Kick/
#   Triple Axel (is_triple_kick), which roll independently on hits 2+ — source:
#   ShouldSkipAccuracyCalcPastFirstHit (battle_move_resolution.c L2137-2151).
# - Per-hit power: flat (move.power) for every move except Triple Kick/Axel,
#   which escalate ×hit_number (battle_util.c L6165-6167).
# - PP, turn-order bookkeeping (Rollout counter, _current_actor_index, phase
#   transition): untouched here — this function is a drop-in replacement for
#   ONE _do_damaging_hit call, so everything the caller does once-per-move
#   around that call site still only happens once.
# - Contact effects, King's Rock, recoil, drain+Liquid Ooze, the survive-
#   lethal-hit chain, hit-reactive abilities, Jaboca/Rowap, Rocky Helmet,
#   Sticky Barb, Magician, Air Balloon, Rapid Spin, secondary_effect (Twineedle's
#   poison chance): all fire PER HIT, for free, simply by calling
#   _do_damaging_hit once per iteration — source's own MoveEnd dispatch table
#   re-runs on every hit of a multi-hit sequence (confirmed via the `+=`
#   accumulation in MoveEndSetValues, battle_move_resolution.c L2490, which
#   would be meaningless if MoveEnd only ran once).
# - Shell Bell: the ONE confirmed exception to "just call it per hit" — source
#   accumulates `gBattleScripting.savedDmg` across every hit and only actually
#   triggers the heal once the sequence's own MoveEnd loop terminates. Passing
#   suppress_shell_bell=true to every per-hit call and manually applying ONE
#   heal from the accumulated total after the loop reproduces this exactly (a
#   per-hit heal would under-heal vs. the real total due to floor-division
#   truncation — five 7-damage hits under Shell Bell: 5×floor(7/8)=0 per-hit vs.
#   floor(35/8)=4 on the total).
# - Scale Shot (is_scale_shot): a one-time self stat change applied once after
#   the loop, gated on ≥1 hit landing — battle_move_resolution.c L3620-3628.
#
# Mid-sequence termination (source: MoveEndMultihitMove, battle_move_resolution.c
# L3224-3286), each verified independently rather than assumed uniform:
# - Target's current_hp reaches 0 (per this project's own "check current_hp, not
#   .fainted, for synchronous aliveness" convention): stop immediately, no
#   further hits, matching source's `!IsBattlerAlive(battlerDef) → counter = 0`.
# - Target's Substitute breaks on a given hit: that hit still lands (drains
#   substitute_hp, counts as landed) but the sequence stops there — the real
#   Pokémon behind a JUST-broken Substitute is never hit by the remaining
#   swings. Distinct from a Substitute merely ABSORBING a hit without breaking:
#   that case correctly CONTINUES the loop (a fresh Substitute can absorb
#   several hits of a multi-hit move before it finally breaks), so this checks
#   substitute_hp transitioning from >0 to <=0 specifically, not "was this hit
#   substitute-absorbed."
# - A wholly-blocked hit with NO Substitute involved (type immunity, Wonder
#   Guard, an absorb-family ability) returns 0 real damage and stops the
#   sequence after just the one attempt — source's top-level
#   `!IsBattlerUnaffectedByMove(battlerDef)` gate on the whole continuation
#   block. Distinguished from the Substitute-standing case above by checking
#   whether a Substitute was actually in play for this hit at all.
func _do_multi_hit_sequence(attacker: BattlePokemon, target: BattlePokemon,
		move: MoveData, helping_hand: bool, power_override: int) -> void:
	var ng_active: bool = _is_neutralizing_gas_active()
	var hit_count: int = _resolve_multi_hit_count(move, attacker, ng_active)
	var total_damage: int = 0
	var hits_landed: int = 0

	for hit_num in range(1, hit_count + 1):
		if target.current_hp <= 0:
			break

		var this_power_override: int = power_override
		if move.is_triple_kick:
			if hit_num > 1:
				var hit_ok: bool = StatusManager.check_accuracy(
						attacker, target, move, _force_hit, ng_active, _effective_weather(),
						_has_target_already_acted(target))
				if not hit_ok:
					move_missed.emit(attacker, "accuracy")
					break
			# Escalating power: hit 1 = ×1, hit 2 = ×2, hit 3 = ×3.
			this_power_override = move.power * hit_num

		var had_standing_sub: bool = target.substitute_hp > 0 and not move.ignores_substitute
		var dmg: int = _do_damaging_hit(
				attacker, target, move, false, helping_hand, this_power_override, true)
		total_damage += dmg
		hits_landed += 1

		if had_standing_sub:
			if target.substitute_hp <= 0:
				break  # the Substitute broke on this hit — sequence ends here
			# else: Substitute still standing — continue, dmg==0 here is expected,
			# not a sign of immunity.
		elif dmg == 0:
			break  # wholly blocked (type immunity / Wonder Guard / absorb family)

		if target.current_hp <= 0:
			break

	# Scale Shot: once, after the sequence, gated on at least one hit landing.
	if move.is_scale_shot and hits_landed > 0:
		var atk_def_actual: int = StatusManager.apply_stat_change(
				attacker, BattlePokemon.STAGE_DEF, -1, null, ng_active)
		if atk_def_actual != 0:
			stat_stage_changed.emit(attacker, BattlePokemon.STAGE_DEF, atk_def_actual)
		var atk_spd_actual: int = StatusManager.apply_stat_change(
				attacker, BattlePokemon.STAGE_SPEED, 1, null, ng_active)
		if atk_spd_actual != 0:
			stat_stage_changed.emit(attacker, BattlePokemon.STAGE_SPEED, atk_spd_actual)

	# Shell Bell: one heal from the accumulated total (see this function's own
	# doc comment for why per-hit healing would be wrong).
	if total_damage > 0:
		var shell_bell_amount: int = ItemManager.shell_bell_heal(attacker, total_damage, ng_active)
		if shell_bell_amount > 0:
			attacker.current_hp = min(attacker.max_hp, attacker.current_hp + shell_bell_amount)
			item_healed.emit(attacker, shell_bell_amount)

	multi_hit_sequence_finished.emit(attacker, target, hits_landed, total_damage)


# M14b: Execute one damaging hit from attacker onto target.
# Handles DamageCalculator call, substitute routing, Counter tracking, Bide accumulation,
# target-thaw, recoil, drain, secondary effects, contact abilities, item triggers, and
# _last_attacker tracking (used by Destiny Bond killer lookup in _phase_faint_check).
# is_spread: pass true when this is a spread move with ≥2 live targets → 0.75× reduction.
# helping_hand: pass true when attacker's ally used Helping Hand → 1.5× base power.
# power_override: M16b — pass ≥0 to override move.power for this hit (Rollout scaling,
#   Magnitude's rolled power). -1 (default) = use move.power.
# Source: battle_script_commands.c :: MoveDamageDataHpUpdate + downstream effect handlers.
func _do_damaging_hit(attacker: BattlePokemon, target: BattlePokemon,
		move: MoveData, is_spread: bool = false, helping_hand: bool = false,
		power_override: int = -1, suppress_shell_bell: bool = false) -> int:
	var target_idx: int = _combatants.find(target)
	var target_side: int = target_idx / _active_per_side
	var sc: Dictionary = _side_conditions[target_side]
	# M17g: computed once per hit — Neutralizing Gas suppresses every ability check
	# below field-wide (attacker's own abilities included), same as source's single
	# GetBattlerAbility chokepoint.
	var ng_active: bool = _is_neutralizing_gas_active()

	# M16c: Brick Break-style screen removal fires BEFORE this hit's own damage calc
	# (preAttackEffect=TRUE in source), so a screen this move itself breaks does NOT
	# reduce this hit's damage — `sc` is read fresh (already cleared) below.
	# Source: battle_script_commands.c :: MOVE_EFFECT_BREAK_SCREEN case (L3308-3336).
	if move.breaks_screens and (sc["reflect_turns"] > 0 or sc["light_screen_turns"] > 0
			or sc["aurora_veil_turns"] > 0):
		sc["reflect_turns"] = 0
		sc["light_screen_turns"] = 0
		sc["aurora_veil_turns"] = 0
		screens_broken.emit(target_side)

	# M16c: Reflect/Light Screen/Aurora Veil damage reduction. Resolved here (not inside
	# DamageCalculator, which is a stateless static utility with no access to side state)
	# and passed in as a pre-resolved bool + doubles flag.
	# Source: battle_util.c :: GetScreensModifier (L7347-7365): Aurora Veil applies
	#   regardless of category; Reflect only vs Physical, Light Screen only vs Special.
	#   The three do NOT stack multiplicatively — it's a plain OR, single ×0.5/×0.667 either way.
	var screen_active: bool = false
	if sc["aurora_veil_turns"] > 0:
		screen_active = true
	elif move.category == 0 and sc["reflect_turns"] > 0:
		screen_active = true
	elif move.category == 1 and sc["light_screen_turns"] > 0:
		screen_active = true
	# M17n-9: Infiltrator — the ATTACKER's moves ignore screens entirely (source:
	# GetScreensModifier, battle_util.c L7358-7362, unconditional ×1.0 override
	# checked before the reflect/light-screen/aurora-veil OR above).
	if AbilityManager.bypasses_infiltrator_barriers(attacker, ng_active):
		screen_active = false

	var roll: int = _force_roll if _force_roll != null else -1
	# M17n-2: pass the EFFECTIVE weather — Air Lock/Cloud Nine anywhere on the field
	# negates the raw multiplier AND every weather-conditional ability read through
	# this same value (Flower Gift, Solar Power, Dry Skin, Delta Stream), for free.
	var result: Dictionary = DamageCalculator.calculate(
			attacker, target, move, roll, _force_crit, _effective_weather(), is_spread, helping_hand,
			power_override, screen_active, _active_per_side > 1, _get_ally(attacker),
			_get_ally(target), ng_active, _is_last_to_move(attacker))
	var damage: int = result["damage"]

	# M17n-6: Wonder Guard — the block already happened inside DamageCalculator
	# (0 damage); this just gives tests/UI a signal-observable discriminator distinct
	# from ordinary type immunity (both return damage=0, but only this one sets
	# `wonder_guard_blocked`), matching the absorb-family's own precedent below.
	if result.get("wonder_guard_blocked", false):
		ability_triggered.emit(target, "wonder_guard")
		move_executed.emit(attacker, target, move, 0)
		return 0

	# M17l/M17m: absorb-family (Lightning Rod/Storm Drain/Sap Sipper/Motor Drive/
	# Well-Baked Body/Volt Absorb/Water Absorb/Dry Skin/Earth Eater/Flash Fire) — the
	# absorb (0 damage) already happened inside DamageCalculator; apply this ability's
	# specific side effect here, before the Substitute check below, since source's
	# ability-absorption takes effect independent of Substitute (the move never
	# actually "hits" a Substitute when absorbed this way).
	var absorb_result: Dictionary = result.get("absorb_result", {})
	if not absorb_result.is_empty():
		match absorb_result["kind"]:
			"stat":
				var stat: int = absorb_result["stat"]
				var amount: int = absorb_result["amount"]
				var actual: int = StatusManager.apply_stat_change(
						target, stat, amount, null, ng_active)
				if actual != 0:
					stat_stage_changed.emit(target, stat, actual)
				ability_triggered.emit(target, "absorb_stat_boost")
			"heal":
				if target.current_hp < target.max_hp:
					var heal_amt: int = max(1, target.max_hp / absorb_result["fraction"])
					target.current_hp = min(target.max_hp, target.current_hp + heal_amt)
					ability_healed.emit(target, heal_amt)
				ability_triggered.emit(target, "absorb_heal")
			"flag":
				target.flash_fire_active = true
				ability_triggered.emit(target, "flash_fire_boosted")
		move_executed.emit(attacker, target, move, 0)
		return 0

	# M16d: Rapid Spin — clears ONE hazard type from the ATTACKER's own side after dealing
	# damage. Fires even if the hit was absorbed by a Substitute (INCLUDING_SUBSTITUTES in
	# source), so this is placed before the went_to_sub branch below, gated only on damage>0.
	# Source: battle_move_resolution.c, case EFFECT_RAPID_SPIN (L3569-3574):
	#   IsAnyTargetTurnDamaged(battlerAtk, INCLUDING_SUBSTITUTES).
	# Source: battle_script_commands.c :: Cmd_rapidspinfree (L8578-8612): clears the FIRST
	#   matching hazard type only (Spikes → Toxic Spikes → Stealth Rock in this project's
	#   implemented subset), not all of them at once.
	if move.is_rapid_spin and damage > 0:
		var atk_idx: int = _combatants.find(attacker)
		var atk_side: int = atk_idx / _active_per_side
		var asc: Dictionary = _side_conditions[atk_side]
		if asc["spikes_layers"] > 0:
			asc["spikes_layers"] = 0
			hazards_cleared.emit(atk_side, "spikes")
		elif asc["toxic_spikes_layers"] > 0:
			asc["toxic_spikes_layers"] = 0
			hazards_cleared.emit(atk_side, "toxic_spikes")
		elif asc["stealth_rock"]:
			asc["stealth_rock"] = false
			hazards_cleared.emit(atk_side, "stealth_rock")

	# M18t: Air Balloon pops on ANY damaging hit landing on the holder — NOT
	# specifically a Ground move it just blocked (a blocked Ground hit deals 0
	# damage here, so it correctly never pops from the hit it just deflected).
	# Source's own `IsBattlerTurnDamaged(battler, INCLUDING_SUBSTITUTES)` means
	# this fires even through a Substitute, so — same reasoning and same
	# placement as Rapid Spin just above — this must be checked BEFORE the
	# went_to_sub early return below, gated only on damage > 0.
	if damage > 0 and ItemManager.holds_air_balloon(target, ng_active):
		_consume_item(target)
		item_effect_triggered.emit(target, "air_balloon_pop")

	# M17n-9: Infiltrator bypasses Substitute for damaging hits too (same shared
	# IsSubstituteProtected chokepoint source routes every substitute check through).
	var went_to_sub: bool = (target.substitute_hp > 0 and not move.ignores_substitute \
			and not AbilityManager.bypasses_infiltrator_barriers(attacker, ng_active))
	if went_to_sub:
		var sub_dmg: int = min(damage, target.substitute_hp)
		target.substitute_hp -= damage
		if target.substitute_hp <= 0:
			target.substitute_hp = 0
			substitute_broke.emit(target)
		move_executed.emit(attacker, target, move, sub_dmg)
		return 0

	# M17n-5/M18o: survive-a-lethal-hit chain — Sturdy, Focus Band, Focus Sash.
	# Source: battle_util.c L7962-7984 (the shared endure-check function every
	# lethal hit routes through) — `if (defender.hp > damage) return damage` (non-lethal,
	# skip); else Endure volatile → False Swipe → Sturdy (IsBattlerAtMaxHp gate,
	# B_STURDY >= GEN_5, satisfied at this project's GEN_LATEST) → Focus Band → Focus
	# Sash → affection, in that priority order, first match wins, `damage = hp - 1`.
	# This project has no Endure move, no False Swipe move, and no affection
	# mechanic — Sturdy/Focus Band/Focus Sash are the three reachable cases, and
	# this is a strict elif chain (first match wins), NOT three independent
	# checks — confirmed from source: a Pokemon with BOTH Sturdy and a held Focus
	# Sash never reaches the Focus Sash branch at all when Sturdy already fires,
	# so the item is not consumed, not "wasted," simply untouched by that hit.
	# Both `damage >= target.current_hp` checks below read target.current_hp
	# BEFORE it's reduced by this hit (the reduction happens several lines below)
	# — a pre-application lethality prediction on the target's own still-current
	# HP, not a post-hit aliveness check on a different Pokemon, so this has no
	# analogous timing bug to the current_hp-vs-.fainted convention.
	if damage >= target.current_hp and target.current_hp == target.max_hp \
			and AbilityManager.effective_ability_id(target, ng_active, attacker) == AbilityManager.ABILITY_STURDY:
		damage = target.current_hp - 1
		ability_triggered.emit(target, "sturdy")
	elif damage >= target.current_hp \
			and ItemManager.focus_band_activates(target, ng_active, _force_focus_band_roll):
		damage = target.current_hp - 1
		item_effect_triggered.emit(target, "focus_band")
	elif damage >= target.current_hp and target.current_hp == target.max_hp \
			and ItemManager.holds_focus_sash(target, ng_active):
		damage = target.current_hp - 1
		item_effect_triggered.emit(target, "focus_sash")
		_consume_item(target)

	var hp_before_hit: int = target.current_hp
	target.current_hp = max(0, target.current_hp - damage)
	move_executed.emit(attacker, target, move, damage)

	if damage > 0:
		# M14b: track for Destiny Bond killer lookup.
		_last_attacker[target] = attacker
		# M17n-8: companions for Aftermath/Innards Out (see their own doc comment).
		_last_attacker_move[target] = move
		_last_attacker_hp_before[target] = hp_before_hit
		if move.category == 0:
			target.last_physical_damage = damage
		else:
			target.last_special_damage = damage

	if target.bide_turns > 0 and damage > 0:
		target.bide_damage += damage

	if StatusManager.check_target_thaw(target, move, damage):
		pokemon_thawed.emit(target)

	# M17a: Rock Head blocks standard move recoil entirely (does not affect Struggle
	# recoil, handled separately above, or Life Orb recoil, an item effect).
	# Source: battle_move_resolution.c :: EFFECT_RECOIL handling (L3373-3396).
	if move.recoil_percent > 0 and damage > 0 and not AbilityManager.blocks_recoil(attacker, ng_active):
		var recoil: int = damage * move.recoil_percent / 100
		if recoil > 0:
			attacker.current_hp = max(0, attacker.current_hp - recoil)
			recoil_damage.emit(attacker, recoil)

	if move.drain_percent > 0 and damage > 0:
		var heal: int = damage * move.drain_percent / 100
		# M18q: Big Root — applied UNCONDITIONALLY, before the Liquid Ooze branch
		# below, matching source's exact ordering (GetDrainedBigRootHp is called
		# first inside SetHealScript, before the invert-vs-heal decision) — so a
		# Liquid-Ooze-inverted hit against a Big Root holder's own drain move is
		# ALSO boosted, since the multiply happens before the split. Held by the
		# ATTACKER (the one draining), not the drained target.
		heal = ItemManager.big_root_drain_heal(attacker, heal, ng_active)
		if heal > 0:
			# M17n-10: Liquid Ooze — the DRAINED Pokémon's own ability inverts the
			# attacker's heal into damage of the identical amount. Source: SetHealScript
			# (battle_move_resolution.c L2587-2599) — the SINGLE application point every
			# drain-percent move in this project's roster (Absorb/Mega Drain/Giga
			# Drain/Drain Punch) already funnels through; confirmed this is the one
			# central chokepoint before inverting here rather than duplicating drain
			# logic. Source's Dream Eater/Liquid-Ooze-pre-Gen5 carve-out is moot — Dream
			# Eater isn't implemented in this project (confirmed via grep).
			if AbilityManager.inverts_drain(target, ng_active):
				attacker.current_hp = max(0, attacker.current_hp - heal)
				recoil_damage.emit(attacker, heal)
				ability_triggered.emit(target, "liquid_ooze")
			else:
				attacker.current_hp = min(attacker.max_hp, attacker.current_hp + heal)
				drain_heal.emit(attacker, heal)

	# M18q: Shell Bell — heals the ATTACKER by a fraction of the FINAL damage just
	# dealt (this `damage` local is already post-crit/post-type-effectiveness/
	# post-item-and-ability-boosts by construction, matching source's own
	# gBattleScripting.savedDmg, set in the very first moveend state immediately
	# after damage is applied). Unconditioned on target.fainted — the classic use
	# case is healing off the killing blow itself. ItemManager.shell_bell_heal
	# already gates on not-already-at-max-HP and final_damage > 0 internally.
	# [M18.5g] suppress_shell_bell: multi-hit callers pass true here and instead
	# accumulate `damage` across every hit themselves, applying ONE Shell Bell heal
	# after the whole sequence completes. Source: `gBattleScripting.savedDmg +=
	# gBattleStruct->moveDamage[...]` (battle_move_resolution.c L2490, MoveEndSetValues
	# — re-runs every hit, ACCUMULATING) feeding a Shell Bell trigger that itself only
	# actually fires once the multi-hit sequence's own MoveEnd loop terminates — NOT
	# a per-hit heal of `floor(hit_damage/8)` each, which (confirmed via a concrete
	# counter-example: five 7-damage hits) would under-heal relative to
	# `floor(sum(hit_damage)/8)` due to per-hit floor-division truncation.
	if not suppress_shell_bell:
		var shell_bell_amount: int = ItemManager.shell_bell_heal(attacker, damage, ng_active)
		if shell_bell_amount > 0:
			attacker.current_hp = min(attacker.max_hp, attacker.current_hp + shell_bell_amount)
			item_healed.emit(attacker, shell_bell_amount)

	if damage > 0 and move.secondary_effect != MoveData.SE_NONE:
		var effect_hit: bool = StatusManager.try_secondary_effect(attacker, target, move, null, ng_active, _effective_weather())
		if effect_hit:
			if move.secondary_effect == MoveData.SE_FLINCH:
				var target_turn_pos: int = _turn_order.find(target)
				if target_turn_pos > _current_actor_index:
					target.flinched = true
					secondary_applied.emit(target, MoveData.SE_FLINCH)
			elif move.secondary_effect == MoveData.SE_WRAP:
				# [M18.5f] Deliberately its own branch, same reason SE_FLINCH gets one:
				# the "else" path below assumes the secondary effect just SET
				# target.status/confusion_turns (true for every SE_BURN..SE_CONFUSION
				# case, since try_apply_status/try_apply_confusion is what try_secondary_
				# effect called), then immediately checks target's CURRENT status/
				# confusion against a held cure-berry. SE_WRAP's own application
				# (try_apply_wrap) never touches status/confusion at all — routing it
				# through that shared branch would spuriously check (and potentially
				# cure-and-consume) whatever UNRELATED status the target already had
				# before this hit, which is wrong. secondary_applied is still emitted so
				# tests can snapshot the trap-applied moment the same way every other
				# secondary effect already supports.
				secondary_applied.emit(target, MoveData.SE_WRAP)
			else:
				secondary_applied.emit(target, move.secondary_effect)
				_try_synchronize(target, attacker, _se_to_status(move.secondary_effect))
				# M18b: Cheri/Chesto/Pecha/Rawst/Aspear (status_cure_berry_cures) and
				# Persim (confusion_cure_berry_cures) — same self-guarding-elif shape
				# as the status-move-primary path above.
				if ItemManager.status_cure_berry_cures(target, ng_active,
						AbilityManager.is_unnerve_active(_get_live_opponents(target), ng_active)):
					target.status = BattlePokemon.STATUS_NONE
					_consume_item(target)
				elif ItemManager.confusion_cure_berry_cures(target, ng_active,
						AbilityManager.is_unnerve_active(_get_live_opponents(target), ng_active)):
					target.confusion_turns = 0
					_consume_item(target)

	# M18k: King's Rock / Razor Fang — mutually exclusive with a move that already
	# carries its own native flinch effect (source: TryKingsRock's own
	# !MoveHasAdditionalEffect(move, MOVE_EFFECT_FLINCH) guard), so this is gated on
	# the move's secondary_effect NOT already being SE_FLINCH, not on whether that
	# native chance rolled true this turn. Same turn-order gate as the native case
	# above (a flinch that lands on a target who has already acted this turn does
	# nothing — they don't act again).
	if damage > 0 and move.secondary_effect != MoveData.SE_FLINCH \
			and ItemManager.kings_rock_flinch_activates(attacker, ng_active, _force_kings_rock_roll):
		var kr_turn_pos: int = _turn_order.find(target)
		if kr_turn_pos > _current_actor_index:
			target.flinched = true
			secondary_applied.emit(target, MoveData.SE_FLINCH)

	var contact_result: Dictionary = AbilityManager.try_contact_effects(
			attacker, target, move, damage, _force_contact_roll, _force_effect_spore_roll,
			ng_active, _get_ally(attacker))
	if contact_result["rough_skin_damage"] > 0:
		var rs_dmg: int = contact_result["rough_skin_damage"]
		attacker.current_hp = max(0, attacker.current_hp - rs_dmg)
		recoil_damage.emit(attacker, rs_dmg)
		ability_triggered.emit(target, contact_result["ability_name"])
	if contact_result["status_applied"] != 0:
		var contact_status: int = contact_result["status_applied"]
		# [M18.5g-followup-2] The afflicted battler is NOT always `attacker` — Poison
		# Touch (attacker-keyed) poisons `target`/defender, unlike every other ability
		# this dispatch covers (all defender-keyed, afflicting `attacker`). Derived from
		# the new "status_target" key rather than re-deriving it from ability_name here,
		# since try_contact_effects already knows definitively which battler it mutated.
		# status_source is simply the OTHER of the two battlers in this contact
		# interaction — the one whose ability actually fired / would receive a
		# Synchronize reflection back.
		var status_target: BattlePokemon = contact_result["status_target"]
		var status_source: BattlePokemon = target if status_target == attacker else attacker
		secondary_applied.emit(status_target, _status_to_se(contact_status))
		ability_triggered.emit(status_source, contact_result["ability_name"])
		_try_synchronize(status_target, status_source, contact_status)
		# M18b: contact abilities (Static/Flame Body/etc.) only ever inflict
		# non-volatile status, never confusion — no confusion_cure_berry_cures check
		# needed at this call site, unlike the two try_secondary_effect-adjacent
		# sites above.
		if ItemManager.status_cure_berry_cures(status_target, ng_active,
				AbilityManager.is_unnerve_active(_get_live_opponents(status_target), ng_active)):
			status_target.status = BattlePokemon.STATUS_NONE
			_consume_item(status_target)
	if contact_result["speed_change"] != 0:
		stat_stage_changed.emit(attacker, BattlePokemon.STAGE_SPEED, contact_result["speed_change"])
		ability_triggered.emit(target, contact_result["ability_name"])
	if contact_result["mummy_overwritten_ability"] != -1:
		ability_changed.emit(attacker, contact_result["mummy_overwritten_ability"])
		ability_triggered.emit(target, contact_result["ability_name"])
	if contact_result["wandering_spirit_swapped"]:
		# Both sides changed — attacker.ability/target.ability already hold the new
		# (post-swap) values at this point (AbilityManager.try_wandering_spirit_swap
		# mutates them directly), so both signals reflect the correct new IDs.
		ability_changed.emit(attacker, attacker.ability.ability_id)
		ability_changed.emit(target, target.ability.ability_id)
		ability_triggered.emit(target, contact_result["ability_name"])
	if contact_result["pickpocket_stole"]:
		# target (the Pickpocket holder) already holds the stolen item at this point
		# (AbilityManager._try_steal_item mutates it directly).
		item_transferred.emit(attacker, target, target.held_item)
		ability_triggered.emit(target, contact_result["ability_name"])
		_try_symbiosis(attacker)
	if contact_result["attract_inflicted"]:
		# [M18.5d-2] Cute Charm infatuated the ATTACKER (the one who made contact),
		# already mutated directly by StatusManager.try_apply_attract inside
		# try_contact_effects, matching this whole block's established
		# already-mutated-read-back-and-emit pattern.
		infatuated.emit(attacker)
		ability_triggered.emit(target, contact_result["ability_name"])

	# M18d: Jaboca Berry (physical) / Rowap Berry (special) — retaliation damage to
	# the ATTACKER on any hit of the matching move CATEGORY, regardless of contact
	# (a real correction — see ItemManager.jaboca_rowap_retaliation_damage's own
	# doc comment; this is NOT a contact-gated mechanism like Rough Skin/Iron Barbs
	# above, despite the superficial family resemblance). Gated on the ATTACKER
	# still being alive (current_hp > 0, not the holder/target — the holder can
	# faint from this very hit and Jaboca/Rowap still fires, matching source's
	# IsBattlerAlive(battlerAtk)-only check) and the attacker's own Magic Guard —
	# reusing [M17n-9]'s blocks_indirect_damage at this call site, matching how
	# every one of its other five call sites already consult it directly rather
	# than embedding the check inside the item function itself.
	if damage > 0 and attacker.current_hp > 0 \
			and not AbilityManager.blocks_indirect_damage(attacker, ng_active):
		var retaliation_dmg: int = ItemManager.jaboca_rowap_retaliation_damage(
				target, attacker, move, ng_active,
				AbilityManager.is_unnerve_active(_get_live_opponents(target), ng_active))
		if retaliation_dmg > 0:
			attacker.current_hp = max(0, attacker.current_hp - retaliation_dmg)
			item_damage.emit(attacker, retaliation_dmg)
			_consume_item(target)

	# M18p: Rocky Helmet — CONTACT-gated (unlike Jaboca/Rowap just above, which are
	# category-gated only) retaliation to the ATTACKER, maxHP/6, not consumed. Gated
	# on the attacker's own Magic Guard (same "who takes the damage owns the Magic
	# Guard check" shape [M18d] established) via move_triggers_contact_retaliation,
	# which also correctly exempts an attacker holding Protective Pads or Punching
	# Glove (on a punching move) or Long Reach.
	if damage > 0 and attacker.current_hp > 0 \
			and AbilityManager.move_triggers_contact_retaliation(attacker, move, ng_active) \
			and not AbilityManager.blocks_indirect_damage(attacker, ng_active):
		var rh_dmg: int = ItemManager.rocky_helmet_retaliation_damage(target, attacker, ng_active)
		if rh_dmg > 0:
			attacker.current_hp = max(0, attacker.current_hp - rh_dmg)
			item_damage.emit(attacker, rh_dmg)

	# M18p: Sticky Barb — CONTACT-gated transfer of the item from the holder onto the
	# attacker (bypasses Sticky Hold, see AbilityManager.try_sticky_barb_transfer's
	# own doc comment), only if the attacker currently holds nothing. No Magic Guard
	# interaction (this isn't damage) and no consumption call — the item just moves.
	if damage > 0 and attacker.current_hp > 0 \
			and AbilityManager.move_triggers_contact_retaliation(attacker, move, ng_active) \
			and ItemManager.holds_sticky_barb(target, ng_active):
		if AbilityManager.try_sticky_barb_transfer(attacker, target, ng_active):
			item_transferred.emit(target, attacker, attacker.held_item)

	# M17j: Magician — attacker's own ability firing after ANY damaging hit lands
	# (contact not required, unlike Pickpocket above) — genuinely attacker-keyed, so
	# dispatched directly here rather than through either defender-keyed dispatch above.
	if AbilityManager.try_magician(attacker, target, damage, ng_active):
		# attacker already holds the stolen item at this point.
		item_transferred.emit(target, attacker, attacker.held_item)
		ability_triggered.emit(attacker, "magician")
		_try_symbiosis(target)

	# M17b: non-contact-gated reactive stat abilities (Justified, Rattled, Water
	# Compaction, Stamina, Weak Armor, Anger Point, Berserk, Anger Shell, Steam Engine,
	# Thermal Exchange, Cotton Down) — fire on ANY damaging hit, not just contact.
	var hit_result: Dictionary = AbilityManager.try_hit_reactive_effects(
			attacker, target, move, damage, hp_before_hit, result["is_crit"],
			_force_cursed_body_roll, ng_active)
	if hit_result["justified_change"] != 0:
		stat_stage_changed.emit(target, BattlePokemon.STAGE_ATK, hit_result["justified_change"])
		ability_triggered.emit(target, "justified")
	if hit_result["rattled_change"] != 0:
		stat_stage_changed.emit(target, BattlePokemon.STAGE_SPEED, hit_result["rattled_change"])
		ability_triggered.emit(target, "rattled")
	if hit_result["water_compaction_change"] != 0:
		stat_stage_changed.emit(target, BattlePokemon.STAGE_DEF, hit_result["water_compaction_change"])
		ability_triggered.emit(target, "water_compaction")
	if hit_result["stamina_change"] != 0:
		stat_stage_changed.emit(target, BattlePokemon.STAGE_DEF, hit_result["stamina_change"])
		ability_triggered.emit(target, "stamina")
	if hit_result["weak_armor_def_change"] != 0 or hit_result["weak_armor_speed_change"] != 0:
		if hit_result["weak_armor_def_change"] != 0:
			stat_stage_changed.emit(target, BattlePokemon.STAGE_DEF, hit_result["weak_armor_def_change"])
		if hit_result["weak_armor_speed_change"] != 0:
			stat_stage_changed.emit(target, BattlePokemon.STAGE_SPEED, hit_result["weak_armor_speed_change"])
		ability_triggered.emit(target, "weak_armor")
	if hit_result["anger_point_change"] != 0:
		stat_stage_changed.emit(target, BattlePokemon.STAGE_ATK, hit_result["anger_point_change"])
		ability_triggered.emit(target, "anger_point")
	if hit_result["berserk_change"] != 0:
		stat_stage_changed.emit(target, BattlePokemon.STAGE_SPATK, hit_result["berserk_change"])
		ability_triggered.emit(target, "berserk")
	if not hit_result["anger_shell_changes"].is_empty():
		for stat_idx: int in hit_result["anger_shell_changes"]:
			stat_stage_changed.emit(target, stat_idx, hit_result["anger_shell_changes"][stat_idx])
		ability_triggered.emit(target, "anger_shell")
	if hit_result["steam_engine_change"] != 0:
		stat_stage_changed.emit(target, BattlePokemon.STAGE_SPEED, hit_result["steam_engine_change"])
		ability_triggered.emit(target, "steam_engine")
	if hit_result["thermal_exchange_change"] != 0:
		stat_stage_changed.emit(target, BattlePokemon.STAGE_ATK, hit_result["thermal_exchange_change"])
		ability_triggered.emit(target, "thermal_exchange")
	if hit_result["cotton_down_fired"]:
		var cd_ally: BattlePokemon = _get_ally(attacker)
		var cd_actual: int = StatusManager.apply_stat_change(attacker, BattlePokemon.STAGE_SPEED, -1, null, ng_active)
		if cd_actual != 0:
			stat_stage_changed.emit(attacker, BattlePokemon.STAGE_SPEED, cd_actual)
		if cd_ally != null and not cd_ally.fainted:
			var cd_ally_actual: int = StatusManager.apply_stat_change(cd_ally, BattlePokemon.STAGE_SPEED, -1, null, ng_active)
			if cd_ally_actual != 0:
				stat_stage_changed.emit(cd_ally, BattlePokemon.STAGE_SPEED, cd_ally_actual)
		ability_triggered.emit(target, "cotton_down")
	if hit_result["cursed_body_fired"]:
		attacker.disabled_move = move
		attacker.disable_turns = 4
		disabled.emit(attacker, move)
		ability_triggered.emit(target, "cursed_body")
	if hit_result["toxic_debris_fired"]:
		var td_idx: int = _combatants.find(attacker)
		var td_side: int = td_idx / _active_per_side
		var td_sc: Dictionary = _side_conditions[td_side]
		if td_sc["toxic_spikes_layers"] < 2:
			td_sc["toxic_spikes_layers"] += 1
			hazard_set.emit(td_side, "toxic_spikes", td_sc["toxic_spikes_layers"])
			ability_triggered.emit(target, "toxic_debris")

	# M17n-2: Sand Spit — reuses the EXISTING try_set_weather (Drizzle/Drought/Sand
	# Stream's own function), which already no-ops if Sandstorm is already active, so
	# the signals only fire on an actual change.
	if hit_result["sand_spit_fired"] and try_set_weather(WEATHER_SANDSTORM, target):
		weather_set.emit(target, WEATHER_SANDSTORM)
		_notify_weather_changed()
		ability_triggered.emit(target, "sand_spit")

	# M17n-4: Color Change — target's own type changes to match the move that just hit
	# it. Reuses the existing _set_mon_type mutation + type_changed signal (same as
	# Conversion/Conversion 2 above), just triggered reactively instead of from the
	# move's own effect.
	if hit_result["color_change_new_type"] != TypeChart.TYPE_NONE:
		_set_mon_type(target, hit_result["color_change_new_type"])
		type_changed.emit(target, hit_result["color_change_new_type"])
		ability_triggered.emit(target, "color_change")

	if result.get("defender_item_consumed", false):
		_consume_item(target)

	if damage > 0 and not attacker.fainted:
		var lo_recoil: int = ItemManager.life_orb_recoil(attacker, ng_active)
		if lo_recoil > 0:
			attacker.current_hp = max(0, attacker.current_hp - lo_recoil)
			item_damage.emit(attacker, lo_recoil)

	if not target.fainted:
		# M17n-7: Unnerve — blocks Sitrus/Oran Berry while any of target's opponents has it.
		# M18b: renamed sitrus_heal var kept as-is for readability; the function itself
		# now also covers Oran Berry's flat heal (hp_threshold_berry_heal).
		var sitrus_heal: int = ItemManager.hp_threshold_berry_heal(target, ng_active,
				AbilityManager.is_unnerve_active(_get_live_opponents(target), ng_active))
		if sitrus_heal > 0:
			target.current_hp = min(target.max_hp, target.current_hp + sitrus_heal)
			item_healed.emit(target, sitrus_heal)
			_consume_item(target)

		# M18c: berry HP-threshold effects — same post-hit trigger point and same
		# Unnerve gate as Sitrus/Oran above (all 9 of these route through
		# ItemBattleEffects in source, the same general dispatcher Sitrus/Oran use;
		# Custap is the sole exception, handled separately in the turn-order
		# precompute below since it bypasses this gate entirely — see
		# ItemManager.custap_berry_activates's own doc comment).
		var m18c_unnerve: bool = AbilityManager.is_unnerve_active(_get_live_opponents(target), ng_active)

		var stat_trigger: Dictionary = ItemManager.stat_raise_berry_trigger(target, ng_active, m18c_unnerve)
		if not stat_trigger.is_empty():
			var stat_actual: int = StatusManager.apply_stat_change(
					target, stat_trigger["stat"], stat_trigger["amount"], null, ng_active)
			if stat_actual != 0:
				stat_stage_changed.emit(target, stat_trigger["stat"], stat_actual)
				_consume_item(target)

		var random_stat_trigger: Dictionary = ItemManager.random_stat_raise_berry_trigger(
				target, ng_active, m18c_unnerve, null, _force_starf_stat)
		if not random_stat_trigger.is_empty():
			var rs_actual: int = StatusManager.apply_stat_change(
					target, random_stat_trigger["stat"], random_stat_trigger["amount"], null, ng_active)
			if rs_actual != 0:
				stat_stage_changed.emit(target, random_stat_trigger["stat"], rs_actual)
				_consume_item(target)

		var lansat_item: ItemData = ItemManager.lansat_berry_trigger(target, ng_active, m18c_unnerve)
		if lansat_item != null:
			target.focus_energy = true
			ability_triggered.emit(target, "lansat_berry")
			_consume_item(target)

		var micle_item: ItemData = ItemManager.micle_berry_trigger(target, ng_active, m18c_unnerve)
		if micle_item != null:
			target.micle_boost_active = true
			ability_triggered.emit(target, "micle_berry")
			_consume_item(target)

		var enigma_heal: int = ItemManager.enigma_berry_heal(
				target, result.get("effectiveness", 0.0) > 1.0, ng_active, m18c_unnerve)
		if enigma_heal > 0:
			target.current_hp = min(target.max_hp, target.current_hp + enigma_heal)
			item_healed.emit(target, enigma_heal)
			_consume_item(target)

		# M18m: Weakness Policy — +2 Atk AND +2 SpAtk (both, unconditional) on
		# taking a super-effective hit. Source: TryWeaknessPolicy
		# (battle_hold_effects.c L256-269) — the SAME on-hit dispatch site
		# Enigma Berry directly above already occupies (IsBattlerTurnDamaged +
		# a super-effective check), reusing the exact same `result.get(
		# "effectiveness", 0.0) > 1.0` read. Consumed UNCONDITIONALLY once the
		# trigger condition is met — source sets `effect = ITEM_STATS_CHANGE`
		# regardless of whether either SetStatChange call actually changed
		# anything (e.g. both stats already at +6), a real difference from
		# [M18r]'s Blunder Policy, which only consumes if the stat genuinely
		# rose. Confirmed by reading TryWeaknessPolicy's own unconditional
		# `effect` assignment, not assumed to match Blunder Policy's shape.
		if result.get("effectiveness", 0.0) > 1.0 and ItemManager.holds_weakness_policy(target, ng_active):
			var wp_atk: int = StatusManager.apply_stat_change(
					target, BattlePokemon.STAGE_ATK, 2, null, ng_active)
			if wp_atk != 0:
				stat_stage_changed.emit(target, BattlePokemon.STAGE_ATK, wp_atk)
			var wp_spatk: int = StatusManager.apply_stat_change(
					target, BattlePokemon.STAGE_SPATK, 2, null, ng_active)
			if wp_spatk != 0:
				stat_stage_changed.emit(target, BattlePokemon.STAGE_SPATK, wp_spatk)
			_consume_item(target)

		# M18n: Red Card / Eject Button — forced-switch reactive items. Both gated on
		# `not target.fainted` (this same enclosing block) matching source's
		# IsBattlerAlive(holder) requirement; the Substitute-absorbed-hit exclusion is
		# already structurally guaranteed by the `went_to_sub` early return above this
		# function, with no extra check needed here. Reuses `_do_forced_switch_in`
		# ([M9]/[M14b], Roar/Whirlwind) directly, and `_force_roar_rng` for the
		# random-replacement pick — a deliberate reuse, not a new seam, since the
		# underlying party-random-pick mechanism (BattleParty.
		# get_random_non_fainted_not_active) is identical and already parametrized for
		# exactly this purpose.
		var attacker_idx: int = _combatants.find(attacker)
		var attacker_side: int = attacker_idx / _active_per_side
		var attacker_field_slot: int = attacker_idx % _active_per_side
		var target_field_slot: int = target_idx % _active_per_side

		# Eject Button: forces the HOLDER (target) itself to switch. NOT blocked by
		# Guard Dog — confirmed absent from source's TryEjectButton.
		if ItemManager.holds_eject_button(target, ng_active):
			var eb_slot: int = _parties[target_side].get_random_non_fainted_not_active(_force_roar_rng)
			if eb_slot >= 0:
				var old_holder: BattlePokemon = target
				_consume_item(target)
				_do_forced_switch_in(target_side, eb_slot, target_field_slot)
				forced_switch.emit(old_holder, _parties[target_side].get_active_at(target_field_slot))

		# Red Card: forces the ATTACKER to switch; the HOLDER (target) is the one
		# whose item is consumed. Requires the attacker to still be alive (source:
		# TryRedCard's own IsBattlerAlive(battlerAtk) gate — an attacker that fainted
		# from recoil/retaliation earlier in this same hit resolution does not get
		# forced to switch). Checked via current_hp > 0, NOT the `fainted` flag — the
		# same distinction [M18d]'s Jaboca/Rowap already established: `fainted` is only
		# set later in the separate FAINT_CHECK phase, so a same-resolution recoil/
		# retaliation death (like the attacker-faints-from-its-own-recoil case this
		# tier's own test exercises) would read as still-alive if checked via the flag.
		# Guard Dog on the ATTACKER blocks the SWITCH specifically — but the item still
		# consumes either way (source's no-switch branch,
		# BattleScript_RedCardActivationNoSwitch, is still an "activation"), matching
		# the confirmed distinction from the no-valid-target case below (which does
		# NOT consume at all).
		if ItemManager.holds_red_card(target, ng_active) and attacker.current_hp > 0:
			var rc_slot: int = _parties[attacker_side].get_random_non_fainted_not_active(_force_roar_rng)
			if rc_slot >= 0:
				_consume_item(target)
				if AbilityManager.blocks_forced_switch(attacker, target, ng_active):
					ability_triggered.emit(attacker, "guard_dog")
				else:
					var old_attacker: BattlePokemon = attacker
					_do_forced_switch_in(attacker_side, rc_slot, attacker_field_slot)
					forced_switch.emit(old_attacker, _parties[attacker_side].get_active_at(attacker_field_slot))

	# [M18.5g] Real HP damage dealt to the target by this hit — used by the multi-hit
	# loop to accumulate a running total for Shell Bell (see suppress_shell_bell
	# above) and to detect mid-sequence Substitute-break/faint termination. 0 in
	# every early-return path above (Wonder Guard/absorb/Substitute-absorbed — none
	# of those represent real HP loss on the actual target).
	return damage


# M12: Consume a held item (berries, Life Orb consumed indirectly by PP drain in source,
# but for our engine all one-use items use this path). Emits item_consumed signal.
# Source: ConsumeItem / RemoveBattlerItem (battle_util.c) called by TryCureAnyStatus etc.
func _consume_item(mon: BattlePokemon) -> void:
	var item: ItemData = mon.held_item
	mon.held_item = null
	item_consumed.emit(mon, item)
	var ng_active: bool = _is_neutralizing_gas_active()
	# M17n-7: Unburden — activates the moment the holder's OWN item is consumed.
	# Source: CheckSetUnburden, called from every item-removal site including the
	# berry-eating path this function represents. Fires for ANY item, berry or not
	# — confirmed from source, Unburden has no pocket gate.
	if AbilityManager.effective_ability_id(mon, ng_active) == AbilityManager.ABILITY_UNBURDEN:
		mon.unburden_active = true
	# M18-patch-1: this function is NOT berry-only — [M18n]'s Red Card/Eject Button
	# and [M18o]'s Focus Sash all reach it too. The "every item here is a berry"
	# assumption baked into this function's original [M17c]/[M17n-7] comments was
	# correct AT THE TIME (only Lum/Sitrus/resist berries existed) but went stale
	# once those three non-berry items were added; both Cheek Pouch (below) and the
	# `last_consumed_berry` tracker Harvest/Cud Chew read (ability_manager.gd) had
	# the identical bug, sharing this one assignment site as their fix point.
	# Source: TryCheekPouch (battle_script_commands.c:6175) gates directly on
	# `GetItemPocket(itemId) == POCKET_BERRIES` — mirrored here via `item.pocket`.
	var is_berry: bool = item.pocket == ItemManager.POCKET_BERRIES
	if is_berry:
		mon.last_consumed_berry = item
	# M17c: Cheek Pouch — heals maxHP/3 whenever the holder eats a REAL berry, not
	# any consumed item.
	if is_berry:
		var cp_heal: int = AbilityManager.cheek_pouch_heal(mon, ng_active)
		if cp_heal > 0:
			mon.current_hp = min(mon.max_hp, mon.current_hp + cp_heal)
			ability_healed.emit(mon, cp_heal)
			ability_triggered.emit(mon, "cheek_pouch")
	# M17j: Symbiosis — this function is the single existing choke point every item
	# consumption in this project already routes through (berries AND non-berries
	# alike), so wiring Symbiosis's check here covers every existing consumption
	# path with one change, matching source's own broad "ally just lost its item,
	# by any means" trigger shape. Symbiosis itself is NOT berry-gated in source —
	# confirmed via its own [M17j] entry, no change needed here.
	_try_symbiosis(mon)


# M17j: Symbiosis — called after `mon`'s held item was just removed by any means
# (consumption via _consume_item, or theft via Pickpocket/Magician). Checks the ALLY's
# ability (doubles-only; _get_ally already returns null in singles, so this is a
# guaranteed no-op there with zero extra plumbing, matching [M17c]'s Hospitality/[M17h]'s
# Receiver precedent).
func _try_symbiosis(mon: BattlePokemon) -> void:
	var ally: BattlePokemon = _get_ally(mon)
	if ally == null:
		return
	var given_item: ItemData = ally.held_item
	if AbilityManager.try_symbiosis(mon, ally, _is_neutralizing_gas_active()):
		item_transferred.emit(ally, mon, given_item)
		ability_triggered.emit(ally, "symbiosis")
