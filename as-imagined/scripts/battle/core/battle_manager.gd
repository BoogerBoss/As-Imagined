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

# [M20] I.1: Gen VII+ level-difference scaling table, ported VERBATIM from
# source (`sExperienceScalingFactors`, battle_script_commands.c:100-311) —
# NOT recomputed from sqrt() at runtime. Source's own comment states this
# returns `(i^2.5)/4`; verified numerically against 6 spot-checked entries
# (i=2,11,20,100,150,210) before trusting it — see docs/decisions.md's
# `[M20 EXP design]` entry for the full verification, including why the
# `/4` is real and material (NOT a constant that cancels out of the ratio),
# making a live floor(sqrt(i)*i^2) recomputation produce WRONG results.
# Indexed 0-210 (covers every `level+level+10` combination up to level 100
# twice over). Used as EXP_SCALING_FACTORS[A] / EXP_SCALING_FACTORS[C] in
# `_compute_exp_award`, mirroring ApplyExperienceMultipliers:11188-11198's
# `value *= table[A]; value /= table[C]; value += 1` exactly.
const EXP_SCALING_FACTORS: Array[int] = [
	0, 0, 1, 3, 8, 13, 22, 32, 45, 60, 79, 100, 124, 152, 183, 217, 256, 297,
	343, 393, 447, 505, 567, 634, 705, 781, 861, 946, 1037, 1132, 1232, 1337,
	1448, 1563, 1685, 1811, 1944, 2081, 2225, 2374, 2529, 2690, 2858, 3031,
	3210, 3396, 3587, 3786, 3990, 4201, 4419, 4643, 4874, 5112, 5357, 5608,
	5866, 6132, 6404, 6684, 6971, 7265, 7566, 7875, 8192, 8515, 8847, 9186,
	9532, 9886, 10249, 10619, 10996, 11382, 11776, 12178, 12588, 13006,
	13433, 13867, 14310, 14762, 15222, 15690, 16167, 16652, 17146, 17649,
	18161, 18681, 19210, 19748, 20295, 20851, 21417, 21991, 22574, 23166,
	23768, 24379, 25000, 25629, 26268, 26917, 27575, 28243, 28920, 29607,
	30303, 31010, 31726, 32452, 33188, 33934, 34689, 35455, 36231, 37017,
	37813, 38619, 39436, 40262, 41099, 41947, 42804, 43673, 44551, 45441,
	46340, 47251, 48172, 49104, 50046, 50999, 51963, 52938, 53924, 54921,
	55929, 56947, 57977, 59018, 60070, 61133, 62208, 63293, 64390, 65498,
	66618, 67749, 68891, 70045, 71211, 72388, 73576, 74777, 75989, 77212,
	78448, 79695, 80954, 82225, 83507, 84802, 86109, 87427, 88758, 90101,
	91456, 92823, 94202, 95593, 96997, 98413, 99841, 101282, 102735, 104201,
	105679, 107169, 108672, 110188, 111716, 113257, 114811, 116377, 117956,
	119548, 121153, 122770, 124401, 126044, 127700, 129369, 131052, 132747,
	134456, 136177, 137912, 139660, 141421, 143195, 144983, 146784, 148598,
	150426, 152267, 154122, 155990, 157872, 159767,
]

# [M20] I.2: custom participant-count distribution table (original design,
# NOT source-verified — see docs/m20_recon.md Section I.2). Keyed by however
# many currently-alive participants (Section G1's eligibility rules,
# unchanged) share this specific opponent kill.
const DISTRIBUTION_PERCENT: Dictionary = {
	1: 100,
	2: 65,
	3: 55,
	4: 50,
	5: 45,
	6: 40,
}

# [M20] I.4: Difficulty Setting — a single mutually-exclusive enum (matching
# this file's own BattlePhase convention), applied as the LAST multiplicative
# step in Exp computation. Custom design, no source equivalent
# (docs/m20_recon.md Section I.4).
enum DifficultyMode {
	NORMAL,
	HARD,
	CASUAL,
}

const DIFFICULTY_PERCENT: Dictionary = {
	DifficultyMode.NORMAL: 100,
	DifficultyMode.HARD: 50,
	DifficultyMode.CASUAL: 135,
}

# [M20c] EV-gain caps — source-verified at this project's real config:
# MAX_PER_STAT_EVS = (P_EV_CAP >= GEN_6) ? 252 : 255 → 252 here
# (`include/config/pokemon.h:55`, GEN_LATEST=GEN_9); MAX_TOTAL_EVS = 510
# unconditionally (`include/constants/pokemon.h:230-231`). No badge-
# gated progressive cap is needed — source's own `GetCurrentEVCap()`
# defaults to `B_EV_CAP_TYPE == EV_CAP_NONE`, which falls through to the
# flat 510 regardless (`src/caps.c:85-117`); this project has no
# badge/overworld-save-flag system to gate on anyway.
const EV_CAP_PER_STAT: int = 252
const EV_CAP_TOTAL: int = 510

# [M20c] Power Item's flat EV bonus to its one targeted stat — source:
# `POWER_ITEM_BOOST = (I_POWER_ITEM_BOOST >= GEN_7) ? 8 : 4`
# (`src/data/items.h:11`), 8 at this project's GEN_LATEST config.
const POWER_ITEM_EV_BONUS: int = 8

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
signal exp_gained(recipient: BattlePokemon, amount: int)  # [M20] I.1/I.2/I.4
signal level_up(pokemon: BattlePokemon, new_level: int)  # [M20b] fired once per level crossed
signal ev_gained(recipient: BattlePokemon, stat_idx: int, amount: int)  # [M20c] fired once per stat actually increased
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
signal crash_damage(attacker: BattlePokemon, amount: int)  # [M19-recoil-on-miss] Jump Kick-family crashed
signal drain_heal(attacker: BattlePokemon, amount: int)          # attacker healed via drain
# M8 signals
signal ability_triggered(pokemon: BattlePokemon, effect_key: String)      # any ability fires
# M7 signals
signal substitute_created(attacker: BattlePokemon, sub_hp: int)          # Substitute put up
signal substitute_broke(defender: BattlePokemon)                          # Substitute HP → 0
signal protected(defender: BattlePokemon)                                 # Protect succeeded
signal protect_broken(defender: BattlePokemon)  # [M19-break-protect] Feint-family broke an active Protect
signal destiny_bond_set(attacker: BattlePokemon)                          # Destiny Bond activated
signal destiny_bond_triggered(fainted_mon: BattlePokemon, killer: BattlePokemon)  # DB KO
signal disabled(target: BattlePokemon, move: MoveData)                    # Disable applied
signal encored(target: BattlePokemon, move: MoveData)                     # Encore applied
signal taunted(target: BattlePokemon, turns: int)                         # [D4 bundle] Taunt applied
signal infatuated(mon: BattlePokemon)                                     # M18.5d-2: Attract/Cute Charm applied
signal tormented(target: BattlePokemon)                                   # [D4 CHEAP bundle] Torment applied
signal magnet_rise_set(mon: BattlePokemon)                                # [D4 CHEAP bundle] Magnet Rise applied
signal smack_down_set(mon: BattlePokemon)                                 # [D4 CHEAP bundle] Smack Down applied
signal ingrain_set(mon: BattlePokemon)                                    # [D4 CHEAP bundle] Ingrain applied
signal aqua_ring_set(mon: BattlePokemon)                                  # [D4 CHEAP bundle] Aqua Ring applied
signal ring_heal_tick(mon: BattlePokemon, amount: int)                    # [D4 CHEAP bundle] Aqua Ring/Ingrain end-of-turn heal fired
signal endured(mon: BattlePokemon)                                        # [D4 CHEAP bundle] Endure guaranteed 1 HP survival
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
signal curse_damage(pokemon: BattlePokemon, amount: int)                   # [D4 Bundle 7] Curse's own end-of-turn tick
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
signal move_learned(pokemon: BattlePokemon, slot: int, new_move: MoveData)  # Mimic/Sketch overwrote a move slot, or M20b level-up learned/replaced one
signal move_learn_skipped(pokemon: BattlePokemon, move: MoveData)  # [M20b] 4 moves already known, no forced replacement slot set
signal perish_song_activated(pokemon: BattlePokemon)  # Perish Song set a 3-turn countdown on this combatant
signal pokemon_transformed(pokemon: BattlePokemon, copied_from: BattlePokemon)  # Transform succeeded
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
signal berry_stolen_and_eaten(victim: BattlePokemon, beneficiary: BattlePokemon, item: ItemData)  # [M19-berry-steal] Pluck/Bug Bite — consumed in place, NOT a possession transfer like item_transferred above

signal move_bounced(holder: BattlePokemon, new_target: BattlePokemon)      # M17n-9: Magic Bounce reflected a status move

signal status_cured(pokemon: BattlePokemon)  # [Bucket 4 cheapest singles] Sparkling Aria cured the TARGET's own status
signal item_recycled(mon: BattlePokemon, item: ItemData)  # [D4 bundle 3] Recycle restored the user's last-used item
signal passive_hp_lost(mon: BattlePokemon, amount: int)  # [D4 bundle 3] Belly Drum/Fillet Away/Clangorous Soul's own HP cost
signal nightmare_set(target: BattlePokemon)  # [D4 bundle 3] Nightmare applied
signal nightmare_damage(target: BattlePokemon, amount: int)  # [D4 bundle 3] Nightmare's end-of-turn tick fired
signal pp_reduced(target: BattlePokemon, move: MoveData, amount: int)  # [D4 bundle 3] Spite reduced the target's last-used move's PP

signal rampage_lock_started(attacker: BattlePokemon, move: MoveData)  # [M19-rampage] lock just initiated (Thrash family or Uproar)
signal rampage_lock_ended(attacker: BattlePokemon, move: MoveData, confused: bool)  # [M19-rampage] lock just cleared (counter hit 0, or immune-cancel)

signal escape_prevented(target: BattlePokemon, source: BattlePokemon)  # [M19f] Mean Look/Block/Spider Web/Spirit Shackle set the target's escape_prevented_by

signal leech_seeded(target: BattlePokemon, source: BattlePokemon)  # [D0] Leech Seed/Sappy Seed set the target's leeched_by
signal leech_seed_drained(target: BattlePokemon, source: BattlePokemon, amount: int)  # [D0] end-of-turn Leech Seed tick fired (heal or, under Liquid Ooze, damage to source)
signal party_status_cured(pokemon: BattlePokemon)  # [D0] Heal Bell/Aromatherapy/Sparkly Swirl cured one party member's status

signal sure_hit_set(attacker: BattlePokemon, target: BattlePokemon)  # [D1] Lock-On/Mind Reader set the attacker's sure_hit_target
signal item_stolen(stealer: BattlePokemon, victim: BattlePokemon)  # [D1] Thief/Covet stole the target's held item

signal foresight_set(target: BattlePokemon)  # [D2 batch 2] Foresight/Odor Sleuth set the target's foresight_active
signal telekinesis_set(target: BattlePokemon)  # [D4 Bundle 6] Telekinesis set the target's telekinesis_turns
signal octolock_set(target: BattlePokemon, caster: BattlePokemon)  # [D4 Bundle 6] Octolock set the target's octolocked_by
signal tar_shot_set(target: BattlePokemon)  # [D2 batch 2] Tar Shot set the target's tar_shot_active
signal curse_set(target: BattlePokemon)  # [D4 Bundle 7] Curse (Ghost-type user) set the target's cursed
signal pp_drained(mon: BattlePokemon, move: MoveData)  # [D4 Bundle 7] Grudge drained the killer's move to 0 PP
signal imprison_set(mon: BattlePokemon)  # [D4 Bundle 8] Imprison set the caster's imprison_active
signal move_stolen(stealer: BattlePokemon, original_caster: BattlePokemon, move: MoveData)  # [D4 Bundle 8] Snatch intercepted a status move

signal turn_order_changed(mover: BattlePokemon, reason: String)  # [D3] After You ("after_you") / Quash ("quash") successfully reordered _turn_order

signal future_sight_scheduled(caster: BattlePokemon, target: BattlePokemon, move: MoveData)  # [Delayed-effect family] cast-time schedule
signal future_sight_resolved(caster: BattlePokemon, target: BattlePokemon, move: MoveData, damage: int)  # fires even at damage=0 (fizzle/faint/immune)
signal wish_scheduled(caster: BattlePokemon)  # [Delayed-effect family] cast-time schedule
signal wish_resolved(recipient: BattlePokemon, healed: int)  # fires even at healed=0 (already full HP / slot empty never reached)
signal yawn_set(target: BattlePokemon)  # [Delayed-effect family] Yawn's cast-time 2-turn counter start
signal healing_wish_activated(recipient: BattlePokemon, kind: String, healed: int, cured: bool, pp_restored: bool)  # [Delayed-effect family] "healing_wish"/"lunar_dance" consumed at switch-in

signal hit_escape_switch(old_mon: BattlePokemon, new_mon: BattlePokemon)  # [D1 easy bundle] U-turn/Volt Switch/Flip Turn's own voluntary-style switch fired
signal hit_switch_target(old_mon: BattlePokemon, new_mon: BattlePokemon)  # [D1 easy bundle] Circle Throw/Dragon Tail forced the defender out
signal items_swapped(attacker: BattlePokemon, defender: BattlePokemon)  # [D1 easy bundle] Trick/Switcheroo successfully swapped held items

signal side_condition_set(side: int, condition_name: String)  # [D4 Bundle 4] Tailwind/Safeguard/Mist went up ("tailwind"/"safeguard"/"mist")
signal side_condition_expired(side: int, condition_name: String)  # [D4 Bundle 4] duration ran out
signal stockpile_gained(mon: BattlePokemon, count: int)  # [D4 Bundle 4] Stockpile stacked (new count)
signal stockpile_released(mon: BattlePokemon, count: int)  # [D4 Bundle 4] Spit Up/Swallow consumed all stacks (count released)

signal field_sport_set(sport_name: String)  # [D4 Bundle 5] Mud Sport/Water Sport went up ("mud_sport"/"water_sport")
signal types_changed(mon: BattlePokemon, new_types: Array, reason: String)  # [D4 Bundle 5] Reflect Type ("reflect_type") / Roost's one-turn removal ("roost") / Roost's end-of-turn restore ("roost_restore")
signal charge_set(mon: BattlePokemon)  # [D4 Bundle 5] Charge set the user's charged flag
signal laser_focus_set(mon: BattlePokemon)  # [D4 Bundle 5] Laser Focus set the user's 2-turn guaranteed-crit window


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

# [D4 Bundle 6] Test seam: force Present's 0-255 roll. null = use real RNG.
# < 102 = 40 power, < 178 = 80 power, < 204 = 120 power, else = heal branch.
var _force_present_roll: Variant = null

# [M20b] Level-up move-learning: which slot (0-3) to overwrite when a
# Pokémon already knows 4 moves and would learn a new one. null = this
# project has no UI yet (M23 is still ahead) to run the real yes/no +
# replace-which-slot prompt, so the default is auto-skip (move_learn_skipped
# fires, nothing changes). Set to 0-3 to force a specific slot to be
# overwritten instead — wired now, not deferred, per Rob's explicit
# instruction, mirroring forced_nature/forced_ivs' forcing-seam shape.
var _force_move_replacement_slot: Variant = null

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

# [D4 Bundle 4] Copycat's own global "last move that actually landed, by
# ANYONE this battle" tracker. Source: gLastUsedMove (battle_move_resolution.c
# L3034-3039), gated on `!unableToUseMove && !IsBattlerUnaffectedByMove &&
# IsBattlerAlive` — genuinely DISTINCT from this project's per-mon
# `BattlePokemon.last_move_used` (set unconditionally on nearly every
# dispatch path, hit or miss alike; see that field's own doc comment).
# Battle-scoped by construction: a plain instance var on BattleManager, never
# reset mid-battle, and every test in this codebase creates a fresh
# `BattleManager.new()` per battle (confirmed via a repo-wide grep before
# relying on this) — so it cannot leak state across separate battles without
# also requiring a deliberate cross-instance reuse this project's own test
# convention never does. Updated in `_do_damaging_hit` at the same `damage >
# 0` gate Rapid Spin/Air Balloon already use (INCLUDING a Substitute-absorbed
# hit, matching source's own scope) — a disclosed, NOT silently assumed,
# simplification: this project has no single chokepoint every move type
# passes through (each status-move effect resolves via its own ad-hoc
# dispatch branch), so only ordinary DAMAGING hits update this tracker; a
# landed status move (e.g. a successful Growl) is not reflected here.
var _last_landed_move_anyone: MoveData = null

# [D4 Bundle 4] Me First's own ×1.5 power boost — a per-ACTION flag (not
# per-turn like Helping Hand, which is set by an ally's PRIOR action this
# same turn), reset at the top of every `_phase_move_execution` call
# alongside `_current_action_failed`. Threaded into `_do_damaging_hit`/
# `DamageCalculator.calculate` the same way `_helping_hand[attacker_idx]`
# already is — same base-power-modifier pipeline stage, source-confirmed
# (battle_util.c L6443-6444).
var _me_first_boost_active: bool = false

# M14b: per-side Follow Me/Rage Powder state. -1 = no Follow Me active this turn.
# Value = combatant index of the Pokémon that used Follow Me/Rage Powder.
# Source: gSideTimers[side].followmeTimer / followmeTarget (battle_main.c L5060–5061).
# Cleared at the start of each turn (PRIORITY_RESOLUTION / TurnValuesCleanUp equivalent).
var _follow_me_targets: Array[int] = [-1, -1]

# [D4 Bundle 8] Snatch: whether ANY steal has already happened this turn
# (source: `snatchedMoveIsUsed`, a global per-turn guard, NOT per-snatcher).
# Cleared at the start of each turn alongside _follow_me_targets above.
var _snatch_used_this_turn: bool = false

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

# [M20] I.4: Difficulty Setting — per-BattleManager-instance for now, the only
# option available given this project has no persistent save/settings layer
# yet (M32). Flagged for future migration once that layer exists, mirroring
# `forced_nature`/`forced_ivs`'s own "built now, consumed later" precedent.
var difficulty_mode: int = DifficultyMode.NORMAL

# [M20] Exp-participant tracking, per OPPONENT field slot — mirrors source's
# gSentPokesToOpponent[flank] (battle_util.c:1207-1234). Each entry is an
# Array[int] of the PLAYER's own party indices that have been active against
# whichever mon currently occupies that opponent field slot, since it last
# changed. Reset via `_reset_exp_participants_for_opponent_slot` whenever a
# NEW opponent occupies that slot; added to (never removed) via
# `_add_exp_participant` whenever ANY player mon switches in. Membership
# persists across a participant's own later fainting — eligibility to
# actually RECEIVE Exp is governed separately, by aliveness at award time
# (see `_award_exp_for_fainted_opponent`). See docs/m20_recon.md Section G1
# for the full source citations this reproduces.
var _exp_participants: Array = []

# [Batch fix] Whether the CURRENTLY active `weather` was set by one of the 3
# Primal-weather abilities (Desolate Land/Primordial Sea/Delta Stream). Since
# `[M17d]` deliberately reuses the plain WEATHER_SUN/WEATHER_RAIN/
# WEATHER_STRONG_WINDS values for Primal weather rather than adding a
# separate "Primal" flag (no separate value exists to test directly, unlike
# source's own `gBattleWeather & B_WEATHER_PRIMAL_ANY` bit check), this is
# the proxy `try_set_weather`'s own refuse-to-overwrite gate reads. Set only
# on ability-driven `try_set_weather` calls (see that function's own doc
# comment) — a move-driven weather-set (Sandstorm/Rain Dance/etc.) always
# clears it back to false, matching source's own ABILITY_NONE-passed calls
# never counting as a Primal setter.
var _weather_is_primal: bool = false

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
# [D4 Bundle 4] Extended with Tailwind/Safeguard/Mist (turn counters, same
# shape as the screens above) and Sticky Web (a genuine hazard — layers=1
# max, like Stealth Rock — but its own switch-in effect applies via the FULL
# stat-change pipeline rather than a raw hazard tick, so `sticky_web_setter`
# records WHO set it, the same attribution source's own `stickyWebBattlerId`
# provides, needed for Mirror Armor/Defiant to correctly attribute the drop).
var _side_conditions: Array = [
	{"reflect_turns": 0, "light_screen_turns": 0, "aurora_veil_turns": 0,
			"spikes_layers": 0, "toxic_spikes_layers": 0, "stealth_rock": false,
			"tailwind_turns": 0, "safeguard_turns": 0, "mist_turns": 0,
			"sticky_web": false, "sticky_web_setter": null},
	{"reflect_turns": 0, "light_screen_turns": 0, "aurora_veil_turns": 0,
			"spikes_layers": 0, "toxic_spikes_layers": 0, "stealth_rock": false,
			"tailwind_turns": 0, "safeguard_turns": 0, "mist_turns": 0,
			"sticky_web": false, "sticky_web_setter": null},
]

# [D3 turn-order/event-tracker batch] Retaliate's side-wide "an ally fainted
# last turn" timer — mirrors _side_conditions' per-side shape. 2 = set this
# turn (not yet doubled); 1 = one turn boundary has passed (doubles);
# 0 = inactive. Set in _phase_faint_check, decremented once per turn in
# _phase_end_of_turn. Source: gSideTimers[side].retaliateTimer.
var _retaliate_timer: Array[int] = [0, 0]

# [D3 turn-order/event-tracker batch] Echoed Voice's FIELD-WIDE (not
# per-side, not per-mon) consecutive-use counter and its per-turn "was it
# used at all this turn" flag. Updated once per turn in _phase_end_of_turn:
# increments (capped 4) and resets the flag if the flag was set; otherwise
# resets straight to 0. Source: gBattleStruct->echoedVoiceCounter /
# ->incrementEchoedVoice.
var _echoed_voice_counter: int = 0
var _echoed_voice_used_this_turn: bool = false

# [D4 Bundle 5] Mud Sport(300)/Water Sport(346) — FIELD-WIDE (not per-side,
# not per-mon) 5-turn timers, mirroring `_echoed_voice_counter`'s own
# battle-wide (not `_side_conditions`-indexed) shape. Confirmed via source
# (moves_info.h MOVE_MUD_SPORT/MOVE_WATER_SPORT: .target = TARGET_FIELD)
# this is genuinely field-wide, not per-side like Tailwind/Safeguard/Mist.
# Source: Cmd_settypebasedhalvers (battle_script_commands.c L9463-9500),
# gFieldTimers.mudSportTimer/waterSportTimer = 5 (B_SPORT_TURNS >= GEN_6,
# this project's config); HandleEndTurnMudSport/HandleEndTurnWaterSport
# (battle_end_turn.c L1184-1198).
var _mud_sport_turns: int = 0
var _water_sport_turns: int = 0

# [Delayed-effect family] Future Sight/Doom Desire — keyed by the TARGET's
# combatant index (matching source's own per-slot gBattleStruct->futureSight
# storage). Value: {"counter": int, "caster": BattlePokemon, "move": MoveData}.
# Decremented once per turn in _phase_end_of_turn; resolves (via the normal
# _do_damaging_hit chokepoint) against whoever occupies the target slot when
# the counter reaches 0.
var _future_sight_pending: Dictionary = {}

# [Delayed-effect family] Wish — keyed by the CASTER's OWN combatant index
# (the slot Wish heals, not a target). Value: {"counter": int, "caster":
# BattlePokemon}. Heal amount is always the caster's own max HP / 2, fixed
# at cast time via the stored reference — not the eventual recipient's.
var _wish_pending: Dictionary = {}

# [Delayed-effect family] Healing Wish/Lunar Dance — keyed by the FAINTED
# user's own combatant index (the slot the effect is stored on). Value:
# "healing_wish" or "lunar_dance". Consumed by the next switch-in on that
# slot via any method (voluntary/forced/faint-replacement).
var _stored_healing_effect: Dictionary = {}

# M16d: Trick Room — genuinely per-BATTLE (not per-side, not per-Pokémon): reverses the
# speed tiebreak used in turn-order resolution while active. 0 = inactive.
# Source: gFieldStatuses & STATUS_FIELD_TRICK_ROOM (bitmask) + gFieldTimers.trickRoomTimer.
var trick_room_turns: int = 0

# M15 Task 3: Struggle instantiated in _ready(); used when all PP are depleted.
# Source: battle_main.c L4727–4728 — noValidMoves → MOVE_STRUGGLE substitution.
var _struggle_move: MoveData = null

# [D1 easy bundle] Stomping Tantrum/Temper Flare's own "did my move fail"
# detector — a best-effort GENERIC tracker rather than touching every one
# of this codebase's dozens of individual failure-emission call sites
# (source's own `ShouldSetStompingTantrumTimer` is a single general-purpose
# MoveEnd hook every move effect passes through; this project's dispatch
# has no equivalent single chokepoint). Self-connects to this class's own
# `move_missed`/`move_effect_failed` signals — reset at the start of each
# action in `_phase_move_execution`, consulted once at the top of
# `_phase_faint_check` (the one universal point every action's resolution
# — success or failure, from any of the dozens of early-return paths —
# always reaches next), then applied to whoever just acted.
var _current_action_failed: bool = false

# [D1 easy bundle] Set true by `_phase_battle_start` (once, at the very
# start of a battle) — consumed by `_phase_priority_resolution`'s own
# per-turn reset loop to mark the STARTING leads as having "just switched
# in" for turn 1 specifically, closing the real gap described at both of
# those sites' own doc comments.
var _pending_initial_switch_in: bool = false


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
	move_missed.connect(func(_a, _reason): _current_action_failed = true)
	move_effect_failed.connect(func(_a, _reason): _current_action_failed = true)


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
#   — [Batch fix] Primal weather override logic: refuses to overwrite an active
#     Primal weather (Desolate Land/Primordial Sea/Delta Stream) unless the new
#     setter is ALSO one of those three abilities — a gap flagged since `[M17d]`,
#     now closed. `by_ability`: true for every ability-driven call site (switch-in
#     setters, Baton Pass inheritance, Sand Spit) — matches source passing a real
#     `enum Ability` for those and `ABILITY_NONE` for move-driven weather (Sandstorm/
#     Rain Dance/etc., which therefore NEVER counts as a Primal-capable setter, same
#     as source). FLAGGED, not fixed: this project's weather_duration is never
#     "permanent" the way source's own Primal weather is (weatherDuration=0, no
#     countdown at all) — a separate, deeper pre-existing gap this fix doesn't
#     address; Primal weather set here still decrements on the normal 5/8-turn timer.
func try_set_weather(weather_type: int, by_pokemon: BattlePokemon = null,
		by_ability: bool = true) -> bool:
	if weather == weather_type:
		return false
	var setter_id: int = by_pokemon.ability.ability_id \
			if (by_ability and by_pokemon != null and by_pokemon.ability != null) else -1
	var setter_is_primal: bool = setter_id == AbilityManager.ABILITY_DESOLATE_LAND \
			or setter_id == AbilityManager.ABILITY_PRIMORDIAL_SEA \
			or setter_id == AbilityManager.ABILITY_DELTA_STREAM
	if _weather_is_primal and weather != WEATHER_NONE and not setter_is_primal:
		return false
	weather = weather_type
	_weather_is_primal = setter_is_primal
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
	# [M20] Exp-participant tracking, initial state — mirrors source's
	# ResetSentPokesToOpponentValue (battle_util.c:1193-1204): every opponent
	# field slot starts out tracking whichever PLAYER combatants are the
	# starting leads.
	_exp_participants = []
	for _f in range(_active_per_side):
		_exp_participants.append(_parties[0].active_indices.duplicate())
	# Fire switch-in hazard and ability effects for all starting Pokémon (they enter
	# simultaneously). Hazards before abilities — see _apply_switch_in_hazards for the
	# source-confirmed FIRST_EVENT_BLOCK ordering.
	# Source: AbilityBattleEffects(ABILITYEFFECT_ON_SWITCHIN, ...) (battle_util.c L3310)
	for i in range(_combatants.size()):
		var mon: BattlePokemon = _combatants[i]
		_reset_mon_species(mon)
		_reset_mon_stats(mon)
		_reset_mon_type(mon)
		_reset_mon_ability(mon)
		_reset_mon_mimicked_move(mon)
		_reset_mon_transform(mon)
		_apply_switch_in_hazards(mon, i / _active_per_side)
		_apply_switch_in_abilities(mon, i / _active_per_side)
	# [D1 easy bundle] A REAL, previously-latent gap found and fixed here:
	# `switched_in_this_turn` was only ever set TRUE by the mid-battle
	# switch-in functions — the starting leads never got it set at all,
	# meaning Fake Out/First Impression could never connect on a lead's own
	# first turn, and Stakeout/Speed Boost (the two existing consumers of
	# this flag) were silently reading a permanently-false value for every
	# battle's own opening turn. Setting it here alone isn't enough, since
	# `_phase_priority_resolution`'s own per-turn reset (which unconditionally
	# clears this flag for every combatant, every turn) runs AFTER this
	# phase but BEFORE turn 1's own actions — see `_pending_initial_switch_in`
	# there for the other half of this fix.
	_pending_initial_switch_in = true
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
		elif mon.locked_move != null:
			# [M19-rampage] Forced-move-repeat lock (Thrash/Petal Dance/Outrage/
			# Raging Fury/Uproar) — same override shape as charging_move, checked
			# right after it. Source: battle_util.c L390-392, HandleAction_UseMove
			# forces gCurrentMove=gLockedMoves whenever multipleTurns is set.
			_chosen_moves[i] = mon.locked_move
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
		mon.protect_method = BattlePokemon.PROTECT_METHOD_NONE
		# [D4 CHEAP bundle] Endure: same single-turn-only expiry shape as
		# protect_active just above, but a genuinely separate field (see
		# BattlePokemon.endure_active's own doc comment).
		mon.endure_active = false
		# [D4 bundle] Magic Coat: same single-turn-only expiry shape as
		# protect_active just above (also cleared immediately on a
		# successful bounce, at the swap site itself, if it fires earlier).
		mon.magic_coat_active = false
		mon.last_physical_damage = 0
		mon.last_special_damage = 0
		mon.last_hit_was_special = false
		# [D4 Bundle 7] Shell Trap: same single-turn-only per-battler
		# gProtectStructs shape as protect_active/endure_active above.
		mon.shell_trap_armed = false
		# [D4 Bundle 8] Snatch: same single-turn-only shape as shell_trap_armed
		# just above (gProtectStructs' own stealMove field, memset every turn).
		mon.snatch_active = false
		# [D1 easy bundle] The starting leads count as having "just switched
		# in" for turn 1 specifically (`_pending_initial_switch_in`, set by
		# `_phase_battle_start`) — every other turn resets normally to false.
		mon.switched_in_this_turn = _pending_initial_switch_in
		# [M19-stat-raised-trigger] same memset'd-per-turn gProtectStructs field.
		mon.stat_raised_this_turn = false
		# [D3 turn-order/event-tracker batch] Lash Out's own decrease-side mirror.
		mon.stat_lowered_this_turn = false
		# [D1 easy bundle] Revenge/Avalanche's own "who hit me this turn" list.
		mon.hit_by_this_turn = []
		# [D1 easy bundle] Stomping Tantrum's own counter, decremented here —
		# a CORRECTION applied in this same session: this is the same site
		# source's own `battle_main.c` per-battler action-reset uses for
		# BOTH stompingTantrumTimer and retaliateTimer (confirmed via direct
		# source read), which runs unconditionally every turn (never
		# skipped, unlike this project's own `_phase_end_of_turn` — see
		# `_retaliate_timer`'s own decrement just below, moved here from
		# `_phase_end_of_turn` for the identical reason). See
		# MoveData.is_stomping_tantrum's own doc comment for the full
		# timing-bug writeup.
		if mon.stomping_tantrum_timer > 0:
			mon.stomping_tantrum_timer -= 1
	# [D1 easy bundle] Consume the initial-switch-in flag — only turn 1
	# marks the starting leads this way; every subsequent turn resets
	# normally via the loop above.
	_pending_initial_switch_in = false
	# [D1 easy bundle] Retaliate's side-wide timer — MOVED here from
	# `_phase_end_of_turn` (a real bug fix, not a new feature): source's own
	# decrement for `retaliateTimer` lives in the SAME per-battler action-
	# reset function `stompingTantrumTimer` uses (`battle_main.c`
	# L3939-3940), which runs unconditionally at the start of every turn.
	# `_phase_end_of_turn`, by contrast, is confirmed (via `[D3 turn-order/
	# event-tracker batch]`'s own empirical test) to be SKIPPED for the turn
	# a faint/replacement occurs in — a project-specific architectural quirk
	# source doesn't share. Decrementing there meant Retaliate under-doubled
	# by one full turn boundary after a faint; this fixes it to match
	# source's real timing exactly. See docs/decisions.md's
	# `[D1 easy bundle]` entry for the full writeup and the D3 test's own
	# corrected assertions.
	for _rt_side in range(2):
		if _retaliate_timer[_rt_side] > 0:
			_retaliate_timer[_rt_side] -= 1
	# M14b: clear per-turn Follow Me, Helping Hand, and last-attacker state.
	# Source: TurnValuesCleanUp (battle_main.c L5022): memset gProtectStructs (helpingHand),
	#   gSideTimers[].followmeTimer = 0 (L5060–5061).
	_last_attacker.clear()
	_last_attacker_move.clear()
	_last_attacker_hp_before.clear()
	# [D4 Bundle 8] Snatch: only ONE steal can happen per turn TOTAL (source:
	# `snatchedMoveIsUsed`, a global per-turn guard, NOT per-snatcher — see
	# MoveData.is_snatch's own doc comment for the full source citation).
	_snatch_used_this_turn = false
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
		var sa: int = StatusManager.effective_speed(a, eff_w, ng_active,
				_side_conditions[ia / _active_per_side]["tailwind_turns"] > 0)
		var sb: int = StatusManager.effective_speed(b, eff_w, ng_active,
				_side_conditions[ib / _active_per_side]["tailwind_turns"] > 0)
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

	# [D4 Bundle 9] Sky Drop: a mon currently held aloft cannot act at all —
	# checked BEFORE every other pre-move status check (no sleep/freeze/
	# confusion/paralysis counter ticks for this skipped action), matching
	# source's own EARLIEST canceler position (`CancelerSkyDrop`,
	# battle_move_resolution.c L76-85 — position 3 in the whole canceler
	# chain, well ahead of CANCELER_ASLEEP_OR_FROZEN at position 6). See
	# MoveData.is_sky_drop's own doc comment for the full citation.
	if actor.semi_invulnerable == MoveData.SEMI_INV_SKY_DROP_TARGET:
		move_skipped.emit(actor, "sky_drop_held")
		_current_actor_index += 1
		_set_phase(BattlePhase.FAINT_CHECK)
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
		if check["recharging"]:
			reason = "recharging"
		elif check["loafing"]:
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

		_cancel_charge_if_needed(actor, reason)

		move_skipped.emit(actor, reason)
		_current_actor_index += 1
		_set_phase(BattlePhase.FAINT_CHECK)
		return

	_set_phase(BattlePhase.MOVE_EXECUTION)


# [Charge-cancellation fix] Truant/Flinch/Paralysis/Infatuation cancel an
# in-progress two-turn/semi-invulnerable charge outright — source:
# CancelerTruant (battle_move_resolution.c L258-270), CancelerFlinch
# (L298-316), CancelerParalyzed (L446-456), CancelerInfatuation (L458-470),
# each of which calls CancelMultiTurnMoves(battlerAtk) (battle_util.c
# L1076-1093), clearing multipleTurns + semiInvulnerable unconditionally.
# Sleep/Frozen's own canceler (CancelerAsleepOrFrozen, L118-186) and
# Confusion's self-hit branch (CancelerConfused, L389-415) never call it —
# confirmed via direct read, no cancel for those three, so `reason` is
# deliberately checked against only these four strings, not "every failure
# reason." Extracted into its own function (rather than left inline in
# _phase_pre_move_checks) so it's directly unit-testable without needing new
# RNG-forcing seams for the paralysis/infatuation rolls.
func _cancel_charge_if_needed(actor: BattlePokemon, reason: String) -> void:
	if actor.charging_move == null:
		return
	if reason != "loafing" and reason != "flinched" \
			and reason != "paralyzed" and reason != "infatuated":
		return
	# Sky Drop needs one extra piece ordinary two-turn moves don't: source's
	# own CancelMultiTurnMoves clears only the ATTACKER's state, and has no
	# path that releases an orphaned held target — confirmed a genuine,
	# non-self-healing soft-lock in source (the attacker isn't even forced to
	# reselect Sky Drop next turn under free move selection, and
	# HandleSkyDropResult's own fall-through just fails a retry against the
	# same target without freeing it — see _release_sky_drop_target's own doc
	# comment for the full citation trail). This project deliberately does
	# NOT reproduce that soft-lock.
	if actor.sky_drop_target != null:
		_release_sky_drop_target(actor, false)
	actor.charging_move = null
	actor.semi_invulnerable = MoveData.SEMI_INV_NONE


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

	# [D1 easy bundle] Reset Stomping Tantrum's own generic failure detector
	# at the start of THIS action, before any dispatch below can set it.
	_current_action_failed = false
	# [D4 Bundle 4] Reset Me First's own per-action power-boost flag — mirrors
	# the reset just above; set later in THIS SAME function call if the Me
	# First branch triggers, read further down wherever the (possibly
	# reassigned) move's damage is actually dealt.
	_me_first_boost_active = false

	# M14a: use combatant index for move/target lookup; derive side from that.
	var attacker_idx: int = _actor_indices.get(attacker, _combatants.find(attacker))
	var attacker_side: int = attacker_idx / _active_per_side
	var defender: BattlePokemon = _combatants[_chosen_targets[attacker_idx]]
	var move: MoveData = _chosen_moves[attacker_idx]

	# [D4 Bundle 9] Sky Drop — dedicated two-phase dispatch (NOT the generic
	# `move.two_turn` block further below — Sky Drop's own fail conditions,
	# target-side state, and reciprocal-release shape are genuinely
	# different). See MoveData.is_sky_drop's own doc comment for the full
	# source citation.
	if move.is_sky_drop:
		if attacker.charging_move != null:
			# Turn 2: release. Clear the attacker's own state FIRST, matching
			# source's exact ordering (HandleSkyDropResult, "Second turn"
			# branch clears multipleTurns/semiInvulnerable/skyDropTarget
			# before checking whether the target is still there).
			attacker.charging_move = null
			attacker.semi_invulnerable = MoveData.SEMI_INV_NONE
			attacker.sky_drop_target = null
			if defender.semi_invulnerable != MoveData.SEMI_INV_SKY_DROP_TARGET:
				# Target already left the field via some other route
				# (_clear_volatiles already cleared its own semi_invulnerable
				# generically) — fails gracefully, no damage. Source:
				# BattleScript_SkyDropNoTarget.
				move_effect_failed.emit(attacker, "sky_drop_no_target")
				move_executed.emit(attacker, defender, move, 0)
				attacker.last_move_used = move
				_current_actor_index += 1
				_set_phase(BattlePhase.FAINT_CHECK)
				return
			defender.semi_invulnerable = MoveData.SEMI_INV_NONE
			# Fall through: the rest of this function resolves an ordinary
			# damaging hit against `defender` (accuracy/damage/secondary
			# effects all apply normally, matching source's release turn).
		else:
			# Turn 1: setup. Ally-targeting is N/A in this project's
			# singles-only scope (defender is always the opposing side) —
			# not modeled, matching this project's established precedent for
			# other singles-only simplifications.
			if defender.semi_invulnerable != MoveData.SEMI_INV_NONE:
				move_effect_failed.emit(attacker, "sky_drop_already_semi_invulnerable")
				move_executed.emit(attacker, defender, move, 0)
				attacker.last_move_used = move
				_current_actor_index += 1
				_set_phase(BattlePhase.FAINT_CHECK)
				return
			if defender.substitute_hp > 0:
				move_effect_failed.emit(attacker, "sky_drop_substitute_blocks")
				move_executed.emit(attacker, defender, move, 0)
				attacker.last_move_used = move
				_current_actor_index += 1
				_set_phase(BattlePhase.FAINT_CHECK)
				return
			if defender.species.weight >= 2000:
				move_effect_failed.emit(attacker, "sky_drop_too_heavy")
				move_executed.emit(attacker, defender, move, 0)
				attacker.last_move_used = move
				_current_actor_index += 1
				_set_phase(BattlePhase.FAINT_CHECK)
				return
			# CancelMultiTurnMoves(defender) — source cancels the TARGET's own
			# multi-turn state when grabbed (battle_util.c L1076-1093), and
			# flags an interrupted rampage for a confuse-on-drop later.
			if defender.rampage_turns > 0:
				defender.confuse_after_drop = true
			defender.locked_move = null
			defender.rampage_turns = 0
			defender.uproar_turns = 0
			defender.charging_move = null
			defender.semi_invulnerable = MoveData.SEMI_INV_NONE
			attacker.charging_move = move
			attacker.sky_drop_target = defender
			attacker.semi_invulnerable = MoveData.SEMI_INV_SKY_DROP_ATTACKER
			defender.semi_invulnerable = MoveData.SEMI_INV_SKY_DROP_TARGET
			charge_started.emit(attacker, move)
			move_executed.emit(attacker, defender, move, 0)
			attacker.last_move_used = move
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

	# [M19-self-faint] Self-Destruct/Explosion — Damp blocks the move
	# entirely, a simplified EXECUTION-time translation of source's
	# SELECTION-time `.dampBanned` legality flag (this project has no
	# move-selection legality filter to grey the move out at menu time).
	# Reuses the pre-existing AbilityManager.is_damp_active (built for
	# `[M17n-8]`'s Aftermath) directly — no new ability logic needed.
	if move.is_self_faint and AbilityManager.is_damp_active(_combatants, ng_active):
		move_effect_failed.emit(attacker, "damp_blocks_explosion")
		ability_triggered.emit(attacker, "damp")
		move_executed.emit(attacker, defender, move, 0)
		attacker.last_move_used = move
		_current_actor_index += 1
		_set_phase(BattlePhase.FAINT_CHECK)
		return
	# [M19-self-faint] Unconditional self-faint — happens regardless of
	# whether the hit ultimately lands. Source: CancelerExplosion
	# (battle_move_resolution.c L1841-1848) is a PRE-MOVE canceler that
	# zeroes the user's HP BEFORE accuracy/damage resolution even runs, not
	# a post-hit consequence. The move still computes and deals its own
	# damage normally afterward, using the attacker's pre-faint stats — this
	# project's existing FAINT_CHECK phase (which runs generically after
	# every resolved action) picks up the HP=0 state and processes the
	# actual faint/removal correctly with no special code needed.
	if move.is_self_faint:
		attacker.current_hp = 0

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
	# [D1] Snipe Shot(691) bypasses both the same way, via its own MOVE-level
	# ignores_redirection flag rather than an ability.
	var followed_this_hit: bool = false
	if not move.is_spread and move.power > 0 and not AbilityManager.bypasses_redirection(attacker, ng_active, move):
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

	# [Bucket 4 cheapest singles] Rage: clear rage_active at the START of any turn
	# where the chosen move ISN'T Rage itself (source: battle_main.c L5269-5270,
	# checked once per battler before any move resolves that turn). Left untouched
	# when Rage IS the chosen move — the set-on-hit branch further down (inside
	# _do_damaging_hit) re-establishes it fresh after a successful hit regardless.
	if not move.is_rage:
		attacker.rage_active = false

	# [Bucket 4 cheapest singles] Throat Chop: blocks the HOLDER's own sound moves
	# for as long as throat_chop_turns > 0 — reproduced at this "chosen, then
	# fails at execution" insertion point, same shape as Disable/Assault Vest
	# immediately below. Source: battle_move_resolution.c L351.
	if move.sound_move and attacker.throat_chop_turns > 0:
		move_skipped.emit(attacker, "throat_chop")
		_current_actor_index += 1
		_set_phase(BattlePhase.FAINT_CHECK)
		return

	# [Bucket 4 cheapest singles] Blood Moon: fails if this exact move was the
	# user's own last move used — see MoveData.cant_use_twice's own doc comment
	# for the selection-vs-execution-time implementation-shape rationale.
	if move.cant_use_twice and attacker.last_move_used == move:
		move_skipped.emit(attacker, "cant_use_twice")
		_current_actor_index += 1
		_set_phase(BattlePhase.FAINT_CHECK)
		return

	# [D4 CHEAP bundle] Torment: the TARGET-inflicted mirror of Blood Moon's
	# cant_use_twice above — see BattlePokemon.tormented's own doc comment
	# for the full source citation. This project has no menu-legality/
	# Struggle-fallback architecture (confirmed absent for every other
	# execution-time move restriction), so a tormented mon with no other
	# legal move simply has its turn skipped, matching this project's
	# existing behavior for Disable/Taunt/Assault Vest/Blood Moon.
	if attacker.tormented and attacker.last_move_used == move:
		move_skipped.emit(attacker, "tormented")
		_current_actor_index += 1
		_set_phase(BattlePhase.FAINT_CHECK)
		return

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

	# [D4 bundle] Taunt — blocks any STATUS-category move the HOLDER attempts,
	# checked at execution time (same insertion point as Assault Vest just
	# above, confirmed from source to be an execution-time canceler check,
	# not a selection-time filter — a status move already queued this turn
	# is still blocked if Taunt landed before it resolves). See
	# MoveData.is_taunt's own doc comment for the full citation.
	if move.category == 2 and attacker.taunt_turns > 0:
		move_skipped.emit(attacker, "taunt")
		_current_actor_index += 1
		_set_phase(BattlePhase.FAINT_CHECK)
		return

	# [D4 Bundle 8] Imprison — blocks USING a move any OPPOSING Imprison-
	# holder also knows, checked at execution time (same insertion point
	# and shape as Assault Vest/Taunt just above — this project's own
	# established execution-time-only pattern for every move restriction
	# source implements as a menu-legality filter). See
	# MoveData.is_imprison's own doc comment for the full source citation.
	var imprisoned_by_opponent: bool = false
	for opp: BattlePokemon in _get_live_opponents(attacker):
		if opp.imprison_active and opp.moves.has(move):
			imprisoned_by_opponent = true
			break
	if imprisoned_by_opponent:
		move_skipped.emit(attacker, "imprison")
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
			# [D4 Bundle 7] Last Resort — mark THIS slot as used, unconditional
			# on hit/miss/fail, at the SAME point PP is deducted (matching
			# source's CancelerAttackstring, which runs before any Mirror-
			# Move/Metronome/Sleep-Talk reassignment of `move`/`attacker`
			# below in this function — see MoveData.is_last_resort's own doc
			# comment for the full source citation).
			if move_idx < attacker.used_move_slots.size():
				attacker.used_move_slots[move_idx] = true

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
	# [M19-charge-turn-spatk-boost] Electro Shot — same shortcut SHAPE as
	# Solar Beam's own sun-skip above, but gated on RAIN instead. Source's
	# CanTwoTurnMoveFireThisTurn reads move.twoTurnAttackWeather generically
	# (B_WEATHER_SUN for Solar Beam, B_WEATHER_RAIN for Electro Shot) — a
	# PARALLEL field/check, deliberately not generalizing is_solar_beam
	# itself, to avoid any risk to Solar Beam's own already-working behavior
	# (per the task's own explicit preference for a parallel field here).
	var _rain_skip: bool = (
		move.skips_charge_in_rain
		and attacker.charging_move == null
		and weather == WEATHER_RAIN
	)
	var _weather_skip: bool = _solar_skip or _rain_skip
	# M18r: Power Herb — skips the charge turn of ANY two-turn move once, not
	# just Solar Beam in sun. Source: CancelerCharging's Power Herb branch
	# (battle_move_resolution.c L1778) is an `else if` checked only when
	# CanTwoTurnMoveFireThisTurn (the Solar-Beam-in-sun/Electro-Shot-in-rain
	# case) already failed — `not _weather_skip` reproduces that ordering.
	# No charge-turn stat boost (Skull Bash/Meteor Beam/Electro Shot)
	# applies on a Power-Herb-skipped turn — source's Power Herb branch is a
	# structurally separate arm from the charge-setup branch that grants it,
	# and this project's `not _power_herb_skip` gate below excludes the
	# whole two-turn block the same way `not _weather_skip` already does.
	var _power_herb_skip: bool = (
		not _weather_skip
		and attacker.charging_move == null
		and ItemManager.holds_power_herb(attacker, ng_active)
	)
	if _power_herb_skip:
		_consume_item(attacker)
		item_effect_triggered.emit(attacker, "power_herb")
	if move.two_turn and not move.is_bide and not _weather_skip and not _power_herb_skip:
		if attacker.charging_move == null:
			# Charge-turn stat boost (Skull Bash: +1 Defense on charge turn only).
			# Source: moves_info.h MOVE_SKULL_BASH additionalEffects
			#   {MOVE_EFFECT_STAT_PLUS, .defense=1, .self=TRUE, .onChargeTurnOnly=TRUE}
			if move.charge_turn_defense_boost > 0:
				var actual_boost: int = StatusManager.apply_stat_change(
					attacker, BattlePokemon.STAGE_DEF, move.charge_turn_defense_boost, null, ng_active)
				if actual_boost != 0:
					stat_stage_changed.emit(attacker, BattlePokemon.STAGE_DEF, actual_boost)
			# [M19-charge-turn-spatk-boost] Meteor Beam/Electro Shot: +1
			# Sp.Atk on the charge turn only — a PARALLEL field to
			# charge_turn_defense_boost above (not a generalized "which
			# stat" param), matching the task's own explicit preference to
			# avoid any risk to Skull Bash's already-working behavior.
			# Source: moves_info.h MOVE_METEOR_BEAM/MOVE_ELECTRO_SHOT
			#   additionalEffects {MOVE_EFFECT_STAT_PLUS, .spAtk=1, .self=TRUE,
			#   .onChargeTurnOnly=TRUE}.
			if move.charge_turn_spatk_boost > 0:
				var actual_spatk_boost: int = StatusManager.apply_stat_change(
					attacker, BattlePokemon.STAGE_SPATK, move.charge_turn_spatk_boost, null, ng_active)
				if actual_spatk_boost != 0:
					stat_stage_changed.emit(attacker, BattlePokemon.STAGE_SPATK, actual_spatk_boost)
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
			# [D4 CHEAP bundle] Endure takes a genuinely SEPARATE branch here,
			# matching source's own Cmd_setprotectlike exactly (see
			# BattlePokemon.PROTECT_METHOD_ENDURE's own doc comment) — it sets
			# ONLY endure_active, never protect_active/protect_method, so it
			# never blocks the incoming hit. The consecutive-use counter below
			# is still shared/unconditional either way.
			if move.protect_method == BattlePokemon.PROTECT_METHOD_ENDURE:
				attacker.endure_active = true
				attacker.protect_consecutive += 1
				# Reuses the same "protect-family move successfully set up"
				# signal Protect/Detect/Spiky Shield/etc. use — `endured` (below)
				# is reserved for the SEPARATE "actually saved a lethal hit"
				# event, which may never fire even after a successful use.
				# protect_consecutive incremented BEFORE this emit, matching
				# the pre-existing ordering every listener (incl. tier4_test's
				# own S4.04) already relies on.
				protected.emit(attacker)
			else:
				attacker.protect_active = true
				# [M19c] Which variant — see BattlePokemon.protect_method's own doc
				# comment. Left at PROTECT_METHOD_NONE for plain Protect/Detect.
				attacker.protect_method = move.protect_method
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
	# [M19c] Now routes through _is_protected_from, which also covers the 7
	# new Protect-family variants (Obstruct/Silk Trap's non-status-only gate,
	# Wide Guard/Quick Guard's side-wide conditional gate) — see that
	# function's own doc comment for the full source citations.
	if _is_protected_from(attacker, defender, move, ng_active):
		move_missed.emit(attacker, "protected")
		# [M19-recoil-on-miss] Protect block is one of the 4 "unaffected"
		# reasons that trigger crash damage (see crashes_on_miss's doc comment).
		if move.crashes_on_miss:
			_apply_crash_damage(attacker, ng_active)
		# [D4 Bundle 5] Steel Beam — unconditional self-recoil fires even when
		# blocked by Protect (see MoveData.is_steel_beam's own doc comment).
		if move.is_steel_beam:
			_apply_max_hp_50_recoil(attacker, ng_active)
		# [M19c] Spiky Shield/Baneful Bunker/Burning Bulwark/Obstruct/Silk
		# Trap's own contact-punish retaliation — fires only when the BLOCKED
		# move actually made contact (see the helper's own doc comment).
		_apply_protect_contact_punish(attacker, defender, move, ng_active)
		_current_actor_index += 1
		_set_phase(BattlePhase.FAINT_CHECK)
		return

	# [D1 easy bundle] Fake Out / First Impression — fails unless this is
	# the user's first action since switching in. Reuses the existing
	# `switched_in_this_turn` flag directly (zero new tracking state); the
	# Instruct-double-fire loophole is closed separately via Instruct's own
	# exclusion list (see is_first_turn_only below). See
	# MoveData.is_first_turn_only's own doc comment for full source
	# citations.
	if move.is_first_turn_only and not attacker.switched_in_this_turn:
		move_effect_failed.emit(attacker, "first_turn_only_failed")
		move_executed.emit(attacker, defender, move, 0)
		attacker.last_move_used = move
		_current_actor_index += 1
		_set_phase(BattlePhase.FAINT_CHECK)
		return

	# [D1] Sucker Punch / Thunderclap — fails if the target has already
	# acted this turn, OR if the target's own CHOSEN move is status-category.
	# Source: battle_move_resolution.c L1387-1394. Reuses [M18j]'s existing
	# _has_target_already_acted turn-position helper directly. Me First's
	# own source exemption is permanently moot here (unimplemented).
	if move.is_sucker_punch:
		var sp_def_idx: int = _combatants.find(defender)
		var sp_def_move: MoveData = _chosen_moves[sp_def_idx] if sp_def_idx >= 0 else null
		if _has_target_already_acted(defender) \
				or (sp_def_move != null and sp_def_move.category == 2):  # 2 = STAT/status category
			move_effect_failed.emit(attacker, "sucker_punch_failed")
			move_executed.emit(attacker, defender, move, 0)
			attacker.last_move_used = move
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

	# [D3 turn-order/event-tracker batch] After You — push the target to act
	# IMMEDIATELY NEXT. Fails if the target has already acted this turn.
	# See MoveData.is_after_you's own doc comment for full source citations.
	if move.is_after_you:
		var ay_pos: int = _turn_order.find(defender)
		if ay_pos == -1 or ay_pos <= _current_actor_index:
			move_effect_failed.emit(attacker, "after_you_failed")
			move_executed.emit(attacker, defender, move, 0)
			attacker.last_move_used = move
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return
		_turn_order.remove_at(ay_pos)
		_turn_order.insert(_current_actor_index + 1, defender)
		turn_order_changed.emit(defender, "after_you")
		move_executed.emit(attacker, defender, move, 0)
		attacker.last_move_used = move
		_current_actor_index += 1
		_set_phase(BattlePhase.FAINT_CHECK)
		return

	# [D3 turn-order/event-tracker batch] Quash — push the target to act LAST
	# among all remaining (not-yet-acted) battlers this turn. Fails if the
	# target has already acted. See MoveData.is_quash's own doc comment for
	# full source citations, including the doubles-simplification note.
	if move.is_quash:
		var qs_pos: int = _turn_order.find(defender)
		if qs_pos == -1 or qs_pos <= _current_actor_index:
			move_effect_failed.emit(attacker, "quash_failed")
			move_executed.emit(attacker, defender, move, 0)
			attacker.last_move_used = move
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return
		_turn_order.remove_at(qs_pos)
		_turn_order.append(defender)
		turn_order_changed.emit(defender, "quash")
		move_executed.emit(attacker, defender, move, 0)
		attacker.last_move_used = move
		_current_actor_index += 1
		_set_phase(BattlePhase.FAINT_CHECK)
		return

	# [D3 turn-order/event-tracker batch] Upper Hand — only connects if the
	# target's own CHOSEN (not-yet-executed) move has an ability-boosted
	# priority in [1, 3], the target hasn't already acted, and that move
	# isn't status-category. Re-checked fresh via the same
	# AbilityManager.move_priority_bonus function real turn-order sorting
	# uses. On failure the whole move fails — same shape as Sucker Punch
	# above. See MoveData.is_upper_hand's own doc comment for full source
	# citations.
	if move.is_upper_hand:
		var uh_def_idx: int = _combatants.find(defender)
		var uh_def_move: MoveData = _chosen_moves[uh_def_idx] if uh_def_idx >= 0 else null
		var uh_prio: int = -99
		if uh_def_move != null:
			uh_prio = uh_def_move.priority \
					+ AbilityManager.move_priority_bonus(defender, uh_def_move, ng_active)
		if uh_def_move == null or uh_prio < 1 or uh_prio > 3 \
				or _has_target_already_acted(defender) \
				or uh_def_move.category == 2:  # 2 = STAT/status category
			move_effect_failed.emit(attacker, "upper_hand_failed")
			move_executed.emit(attacker, defender, move, 0)
			attacker.last_move_used = move
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

	# [Delayed-effect family] Future Sight / Doom Desire — schedule a hit
	# that resolves 2 turns later against whoever occupies the target's
	# slot then. No accuracy roll, no immediate damage this turn. See
	# MoveData.is_future_sight's own doc comment for full source citations.
	if move.is_future_sight:
		var fs_target_idx: int = _combatants.find(defender)
		if _future_sight_pending.has(fs_target_idx):
			move_effect_failed.emit(attacker, "future_sight_already_pending")
		else:
			_future_sight_pending[fs_target_idx] = {
				"counter": 3, "caster": attacker, "move": move}
			future_sight_scheduled.emit(attacker, defender, move)
		move_executed.emit(attacker, defender, move, 0)
		attacker.last_move_used = move
		_current_actor_index += 1
		_set_phase(BattlePhase.FAINT_CHECK)
		return

	# [Delayed-effect family] Wish — schedule a heal that resolves 1 turn
	# later (counter=2, ticks once at the end of THIS turn too) against
	# whoever occupies the CASTER's OWN slot then. See MoveData.is_wish's
	# own doc comment for full source citations.
	if move.is_wish:
		if _wish_pending.has(attacker_idx):
			move_effect_failed.emit(attacker, "wish_already_pending")
		else:
			_wish_pending[attacker_idx] = {"counter": 2, "caster": attacker}
			wish_scheduled.emit(attacker)
		move_executed.emit(attacker, defender, move, 0)
		attacker.last_move_used = move
		_current_actor_index += 1
		_set_phase(BattlePhase.FAINT_CHECK)
		return

	# [Delayed-effect family] Yawn — a per-mon 2-turn drowsiness counter,
	# not part of the per-slot scheduler above. Fails if the target already
	# has one pending or already has ANY status. See MoveData.is_yawn's own
	# doc comment for full source citations.
	if move.is_yawn:
		if defender.yawn_turns > 0 or defender.status != BattlePokemon.STATUS_NONE:
			move_effect_failed.emit(attacker, "yawn_failed")
		else:
			defender.yawn_turns = 2
			yawn_set.emit(defender)
		move_executed.emit(attacker, defender, move, 0)
		attacker.last_move_used = move
		_current_actor_index += 1
		_set_phase(BattlePhase.FAINT_CHECK)
		return

	# [Delayed-effect family] Healing Wish / Lunar Dance — the user faints
	# to store a one-shot heal(+cure, +full PP for Lunar Dance) for
	# whoever next switches into that slot. Fails outright (no faint) if
	# there's no valid Pokémon to switch to. See MoveData.is_healing_wish/
	# is_lunar_dance's own doc comments for full source citations,
	# including the disclosed always-consume-next-switch-in simplification.
	if move.is_healing_wish or move.is_lunar_dance:
		if not _parties[attacker_side].has_valid_switch_target():
			move_effect_failed.emit(attacker, "healing_wish_no_switch_target")
			move_executed.emit(attacker, defender, move, 0)
			attacker.last_move_used = move
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return
		_stored_healing_effect[attacker_idx] = \
				"lunar_dance" if move.is_lunar_dance else "healing_wish"
		attacker.current_hp = 0
		move_executed.emit(attacker, defender, move, 0)
		attacker.last_move_used = move
		_current_actor_index += 1
		_set_phase(BattlePhase.FAINT_CHECK)
		return

	# [M19-steal-stats] Spectral Thief — steals the target's CURRENTLY
	# positive stat stages onto the attacker (removing them from the
	# target), for ALL 7 stages (Atk/Def/SpAtk/SpDef/Speed/Accuracy/Evasion
	# — confirmed via source's `NUM_BATTLE_STATS = NUM_STATS + 2`, which
	# INCLUDES Accuracy/Evasion, unlike Starf Berry's narrower 5-stat pool
	# that deliberately stops at plain `NUM_STATS`). Dispatched via
	# `.preAttackEffect = TRUE` in source — fires BEFORE this move's own
	# accuracy roll, UNCONDITIONAL on whether the subsequent hit connects
	# (confirmed: `IsBattlerUnaffectedByMove` at pre-attack-effect dispatch
	# time can only reflect ALREADY-resolved state — Protect, handled by
	# this block's own position right after the Protect-blocking check
	# above — and type immunity, checked below — never an accuracy roll
	# that hasn't happened yet). This is a genuinely DIFFERENT shape from
	# `AbilityManager`'s Opportunist (reacts to a fresh stat-RISE EVENT
	# elsewhere, copies the SAME delta without touching the original mon's
	# own stage) — Spectral Thief instead snapshots-and-TRANSFERS whatever
	# positive stages already exist at the moment of use, per stat,
	# zeroing the target's own stage in the process. `StatusManager.
	# apply_stat_change` is still the correct reusable PRIMITIVE for the
	# actual mutation on the attacker's side; the orchestration itself is
	# new. Per-stat gated on the ATTACKER's own stage for that stat not
	# already being at +6 (source: `gBattleMons[battlerAtk].statStages[stat]
	# != MAX_STAT_STAGE`) — confirmed a per-stat gate, not a whole-move
	# skip if any single stat happens to be maxed.
	# Type immunity blocks the steal specifically (not the whole move —
	# unlike Protect above, immunity doesn't fully abort the turn; the move
	# still proceeds to its own accuracy/damage resolution normally
	# afterward, matching this project's established general damaging-move
	# architecture for ordinary — non-OHKO — type immunity).
	# Source: battle_script_commands.c :: case MOVE_EFFECT_STEAL_STATS
	# (L3347-3366).
	if move.steals_positive_stat_stages:
		var steal_blocked: bool = TypeChart.get_effectiveness(
				move.type, defender.species.types, false, false,
				ItemManager.holds_iron_ball(defender, ng_active)) == 0.0
		if not steal_blocked:
			for stat_idx in range(defender.stat_stages.size()):
				var stolen_stage: int = defender.stat_stages[stat_idx]
				if stolen_stage > 0 and attacker.stat_stages[stat_idx] < 6:
					defender.stat_stages[stat_idx] = 0
					stat_stage_changed.emit(defender, stat_idx, -stolen_stage)
					var gained: int = StatusManager.apply_stat_change(
							attacker, stat_idx, stolen_stage, null, ng_active)
					if gained != 0:
						stat_stage_changed.emit(attacker, stat_idx, gained)

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

	# ── Fury Cutter: power scales with the consecutive-use counter ───────────
	# Source: CalcFuryCutterBasePower (battle_util.c L6046-6051) — see
	# MoveData.is_fury_cutter's own doc comment for the full citation.
	# Counter read BEFORE this hit's own increment/reset (applied further
	# down, after the hit resolves), matching source's own read-then-write
	# ordering exactly.
	if move.is_fury_cutter:
		_dmg_power_override = _fury_cutter_power(attacker.fury_cutter_counter)

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

	# [D4 Bundle 8] Round: doubles if the immediately-preceding resolved
	# action this turn was ALSO a landed Round. Reuses `_chosen_moves`
	# (was the previous actor's chosen move Round — correctly false for a
	# switch, since switch-choosing actors get `_chosen_moves[i] = null`)
	# combined with `_last_landed_move_anyone` (did it actually connect —
	# built for Copycat, `[D4 Bundle 4]`). DISCLOSED, NOT BUILT: source's
	# own turn-order self-promotion splice (`TryUpdateRoundTurnOrder`) is
	# gated entirely on `IsDoubleBattle()` — a genuine no-op in singles —
	# see MoveData.is_round's own doc comment for the full citation.
	if move.is_round and _current_actor_index > 0:
		var _round_prev: BattlePokemon = _turn_order[_current_actor_index - 1]
		var _round_prev_idx: int = _combatants.find(_round_prev)
		var _round_prev_chose_round: bool = _round_prev_idx >= 0 \
				and _round_prev_idx < _chosen_moves.size() \
				and _chosen_moves[_round_prev_idx] != null \
				and _chosen_moves[_round_prev_idx].is_round
		var _round_prev_landed: bool = _last_landed_move_anyone != null \
				and _last_landed_move_anyone.is_round
		if _round_prev_chose_round and _round_prev_landed:
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

	# [M19-hp-based-power] Flail / Reversal: power from the USER'S OWN
	# missing-HP fraction (stepped/banded, not continuous).
	# Source: battle_util.c, case EFFECT_FLAIL (L6138-6145).
	if move.is_flail_power:
		_dmg_power_override = _flail_power(attacker.current_hp, attacker.max_hp)

	# [D1 cheap clusters] Eruption / Water Spout / Dragon Energy: power from
	# the USER'S OWN current-HP fraction — CONTINUOUS (no banded table, no
	# floor-to-1 clamp), genuinely simpler than Flail/Reversal just above.
	# Source: battle_util.c, case EFFECT_POWER_BASED_ON_USER_HP (L6136-6137).
	if move.power_scales_with_user_hp:
		_dmg_power_override = move.power * attacker.current_hp / attacker.max_hp

	# [D1 cheap clusters] Wring Out / Crush Grip / Hard Press: power from the
	# TARGET'S OWN current-HP fraction — the mirror of the above.
	# Source: battle_util.c, case EFFECT_POWER_BASED_ON_TARGET_HP (L6192-6193).
	if move.power_scales_with_target_hp:
		_dmg_power_override = move.power * defender.current_hp / defender.max_hp

	# [D1 cheap clusters] Stored Power / Power Trip: power increases with the
	# USER'S OWN total positive stat-stage MAGNITUDE (summed across all 7
	# stats including Accuracy/Evasion, not a count of raised stats).
	# Source: battle_util.c, case EFFECT_STORED_POWER (L6240-6241), reusing
	# CountBattlerStatIncreases(battler, TRUE) (L5948-5961).
	if move.is_stored_power:
		_dmg_power_override = move.power + 20 * _positive_stat_stage_sum(attacker, true)

	# [D3 turn-order/event-tracker batch] Lash Out: doubled if the user's OWN
	# stat was lowered this turn, any source. See MoveData.is_lash_out's own
	# doc comment for full source citations.
	if move.is_lash_out and attacker.stat_lowered_this_turn:
		_dmg_power_override = move.power * 2

	# [D3 turn-order/event-tracker batch] Retaliate: doubled if a Pokémon on
	# the user's OWN SIDE fainted during the PREVIOUS turn. See
	# MoveData.is_retaliate's own doc comment for full source citations.
	if move.is_retaliate:
		var _rt_side: int = _combatants.find(attacker) / _active_per_side
		if _retaliate_timer[_rt_side] == 1:
			_dmg_power_override = move.power * 2

	# [D3 turn-order/event-tracker batch] Rage Fist: +50 power per prior hit
	# taken this battle (BattlePokemon.times_hit, a lifetime counter), capped
	# at 350. See MoveData.is_rage_fist's own doc comment for full source
	# citations.
	if move.is_rage_fist:
		_dmg_power_override = min(move.power + 50 * attacker.times_hit, 350)

	# [D3 turn-order/event-tracker batch] Echoed Voice: power scales with the
	# field-wide consecutive-use counter, and this same dispatch point marks
	# the move as "attempted this turn" for that counter's own end-of-turn
	# update (_phase_end_of_turn) — gated only on reaching this point (i.e.
	# not blocked by an earlier pre-move canceler), NOT on hit success,
	# matching source's `if (!unableToUseMove) incrementEchoedVoice = TRUE`.
	# See MoveData.is_echoed_voice's own doc comment for full source citations.
	if move.is_echoed_voice:
		_dmg_power_override = min(move.power * (1 + _echoed_voice_counter), 200)
		_echoed_voice_used_this_turn = true

	# [D1 easy bundle] Revenge / Avalanche: doubled if the user was hit BY
	# THIS SPECIFIC TARGET earlier this turn. See MoveData.is_revenge's own
	# doc comment for full source citations.
	if move.is_revenge and attacker.hit_by_this_turn.has(defender):
		_dmg_power_override = move.power * 2

	# [D4 bundle] Assurance: doubled if the TARGET was already hit THIS TURN
	# by ANYONE — a genuinely different trigger scope from Revenge just
	# above (which pairs specifically to the user's own attacker), despite
	# sharing the same `hit_by_this_turn` tracker. See MoveData.is_assurance's
	# own doc comment for the full source citation.
	if move.is_assurance and not defender.hit_by_this_turn.is_empty():
		_dmg_power_override = move.power * 2

	# [D1 easy bundle] Stomping Tantrum / Temper Flare: doubled if the
	# user's own previous move failed exactly one turn ago (counter==1).
	# See MoveData.is_stomping_tantrum's own doc comment for full source
	# citations, including the Retaliate timing-bug correction this tier
	# also applied.
	if move.is_stomping_tantrum and attacker.stomping_tantrum_timer == 1:
		_dmg_power_override = move.power * 2

	# [D1 EFFECT_DOUBLE_POWER_ON_ARG_STATUS] Hex/Venoshock/Smelling Salts/Barb
	# Barrage/Infernal Parade: doubled if the target's status matches
	# move.double_power_status_arg — see MoveData's own doc comment for the
	# per-move argument value and the Comatose-as-sleep proxy. Computed here,
	# strictly before _do_damaging_hit runs, so this can never double off a
	# status this same hit's own secondary effect (Barb Barrage's poison
	# chance, Infernal Parade's burn chance) is about to inflict. Smelling
	# Salts carries one further, move-specific exception: the double itself
	# is suppressed if blocked by a live, non-ignored Substitute (source:
	# battle_util.c L6188-6190) — checked here directly since only the power
	# computation, not the separate post-hit cure dispatch below, needs it
	# (that dispatch is naturally already gated on damage > 0, which
	# _do_damaging_hit never reports when a Substitute absorbed the hit).
	if move.is_double_power_on_status \
			and _status_matches_double_power_arg(defender, move.double_power_status_arg, ng_active):
		var _dps_sub_blocks_smelling_salts: bool = move.is_smelling_salts \
				and defender.substitute_hp > 0 and not move.ignores_substitute
		if not _dps_sub_blocks_smelling_salts:
			_dmg_power_override = move.power * 2

	# [D4 CHEAP bundle] Gyro Ball: power from the speed RATIO of
	# target-to-user, both sides read via StatusManager.effective_speed
	# (current, post-stage/status/weather/item speed — NOT base speed).
	# Source: battle_util.c, case EFFECT_GYRO_BALL (L6249-6263).
	if move.is_gyro_ball:
		var gb_eff_w: int = _effective_weather()
		var gb_def_idx: int = _combatants.find(defender)
		_dmg_power_override = _gyro_ball_power(
				StatusManager.effective_speed(attacker, gb_eff_w, ng_active,
						_side_conditions[attacker_side]["tailwind_turns"] > 0),
				StatusManager.effective_speed(defender, gb_eff_w, ng_active,
						_side_conditions[gb_def_idx / _active_per_side]["tailwind_turns"] > 0))

	# [D4 CHEAP bundle] Electro Ball: a genuinely different, STEPPED/BANDED
	# formula from Gyro Ball's continuous one — the INVERSE ratio direction
	# (user-to-target, not target-to-user), indexed into a fixed table.
	# Source: battle_util.c, case EFFECT_ELECTRO_BALL (L6243-6248);
	# sSpeedDiffPowerTable (L6032): {40, 60, 80, 120, 150}.
	if move.is_electro_ball:
		var eb_eff_w: int = _effective_weather()
		var eb_def_idx: int = _combatants.find(defender)
		_dmg_power_override = _electro_ball_power(
				StatusManager.effective_speed(attacker, eb_eff_w, ng_active,
						_side_conditions[attacker_side]["tailwind_turns"] > 0),
				StatusManager.effective_speed(defender, eb_eff_w, ng_active,
						_side_conditions[eb_def_idx / _active_per_side]["tailwind_turns"] > 0))

	# [D4 CHEAP bundle] Payback: power doubles if the TARGET has already
	# acted this turn AND did NOT just switch in this turn — a genuinely
	# conditional formula at this project's GEN_LATEST config
	# (B_PAYBACK_SWITCH_BOOST >= GEN_5), re-derived from source rather than
	# assumed a flat "target already moved" shape.
	# Source: battle_util.c, case EFFECT_PAYBACK (L6273-6283);
	# include/config/battle.h L32.
	if move.is_payback and _has_target_already_acted(defender) and not defender.switched_in_this_turn:
		_dmg_power_override = move.power * 2

	# [D4 bundle 3] Facade: doubles power if the user has Burn/Poison/
	# Toxic/Paralysis — confirmed NOT Sleep/Freeze. The burn-halving bypass
	# is a SEPARATE, independent mechanism (DamageCalculator.calculate's
	# own burn-modifier check) — this is only the power-double half.
	# Source: battle_util.c, case EFFECT_FACADE (L6393-6396).
	if move.is_facade and (attacker.status == BattlePokemon.STATUS_BURN \
			or attacker.status == BattlePokemon.STATUS_POISON \
			or attacker.status == BattlePokemon.STATUS_TOXIC \
			or attacker.status == BattlePokemon.STATUS_PARALYSIS):
		_dmg_power_override = move.power * 2

	# [D4 Bundle 6] Brine: power doubles if the target's HP is at or below 50%.
	if move.is_brine and defender.current_hp * 2 <= defender.max_hp:
		_dmg_power_override = move.power * 2

	# [D4 Bundle 6] Knock Off: power x1.5 if the target's item is actually
	# removable right now (Sticky Hold / form-lock gated) — computed here,
	# before the hit, matching source; the actual removal happens after a
	# connecting hit, further down.
	if move.is_knock_off and AbilityManager.can_remove_item(defender, ng_active):
		_dmg_power_override = int(move.power * 1.5)

	# [D4 Bundle 6] Acrobatics: power doubles if the user holds no item.
	if move.is_acrobatics and attacker.held_item == null:
		_dmg_power_override = move.power * 2

	# [D4 Bundle 6] Punishment: power = 60 + 20 x the target's positive
	# stat-stage COUNT, capped at 200.
	if move.is_punishment:
		var pun_count: int = 0
		for pun_stage in defender.stat_stages:
			if pun_stage > 0:
				pun_count += 1
		_dmg_power_override = min(60 + 20 * pun_count, 200)

	# [D4 Bundle 6] Present: a flat 0-255 uniform roll, split 102/76/26/51
	# into power bands 40/80/120/heal. `_present_heal_branch` is consumed
	# just below, inside the `if move.power > 0:` branch, to bypass the
	# whole damaging dispatch and heal the target instead.
	var _present_heal_branch: bool = false
	if move.is_present:
		var pr_roll: int = _force_present_roll if _force_present_roll != null else randi() % 256
		if pr_roll < 102:
			_dmg_power_override = 40
		elif pr_roll < 178:
			_dmg_power_override = 80
		elif pr_roll < 204:
			_dmg_power_override = 120
		else:
			_present_heal_branch = true

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
	# [Perish Song] Exempted: this generic gate is single-`defender`-shaped and would
	# incorrectly block the WHOLE move (including the caster and every other
	# combatant) if the one arbitrary default `defender` happens to hold Soundproof —
	# a real bug caught by this move's own first test run. Perish Song's dispatch
	# (below, in the all-battlers cluster) already applies this exact same check
	# PER COMBATANT individually, which is the only correct shape for a move that
	# was never single-target to begin with.
	if not move.is_perish_song and AbilityManager.blocks_move_flag(defender, move, ng_active, attacker):
		move_effect_failed.emit(defender, "move_flag_blocked")
		ability_triggered.emit(defender, "soundproof_bulletproof")
		move_executed.emit(attacker, defender, move, 0)
		attacker.last_move_used = move
		_current_actor_index += 1
		_set_phase(BattlePhase.FAINT_CHECK)
		return

	# ── Type immunity pre-check (crashes_on_miss moves only) ─────────────────
	# Source: MOVE_RESULT_DOESNT_AFFECT_FOE is one of the 4 "unaffected" reasons
	# gating crash damage (see MoveData.crashes_on_miss's own doc comment). This
	# project's GENERAL damaging-move path has no separate pre-accuracy immunity
	# check — an ordinary 0x-effectiveness hit just flows through
	# DamageCalculator.calculate as damage=0, with no distinct signal — so this
	# explicit pre-check exists ONLY for crashes_on_miss moves, mirroring the
	# OHKO block's own immune pre-check above rather than changing the general
	# damaging-move path for every other move in the roster.
	if move.crashes_on_miss and AbilityManager.blocks_move_type(defender, move.type, ng_active, attacker):
		move_missed.emit(attacker, "immune")
		_apply_crash_damage(attacker, ng_active)
		attacker.last_move_used = move
		_current_actor_index += 1
		_set_phase(BattlePhase.FAINT_CHECK)
		return
	if move.crashes_on_miss and move.type != TypeChart.TYPE_NONE:
		var crash_eff: float = TypeChart.get_effectiveness(
				move.type, defender.species.types, false, false,
				ItemManager.holds_iron_ball(defender, ng_active))
		if crash_eff == 0.0:
			move_missed.emit(attacker, "immune")
			_apply_crash_damage(attacker, ng_active)
			attacker.last_move_used = move
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

	# ── Dream Eater: fails outright against a non-sleeping target ────────────
	# Source: data/battle_scripts_1.s :: BattleScript_EffectDreamEater
	# (BattleScript_DreamEaterSleepCheck, L1614-1624) — `jumpifstatus BS_TARGET,
	# STATUS1_SLEEP` / `jumpifability BS_TARGET, ABILITY_COMATOSE` else
	# BattleScript_DoesntAffectTargetAtkString (zero damage, not merely "skip
	# the drain" — confirmed from source, not assumed). Checked BEFORE the
	# accuracy roll — this failure path never rolls accuracy at all.
	if move.requires_target_asleep:
		var dream_eater_ok: bool = defender.status == BattlePokemon.STATUS_SLEEP \
				or AbilityManager.effective_ability_id(defender, ng_active, attacker) == AbilityManager.ABILITY_COMATOSE
		if not dream_eater_ok:
			move_missed.emit(attacker, "doesnt_affect")
			move_executed.emit(attacker, defender, move, 0)
			attacker.last_move_used = move
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

	# [D4 Bundle 6] Belch: fails outright unless the user has EVER consumed a
	# real berry this battle. Checked BEFORE the accuracy roll, same shape as
	# Dream Eater's own fail check above.
	if move.is_belch and attacker.last_consumed_berry == null:
		move_effect_failed.emit(attacker, "belch_no_berry_eaten")
		move_executed.emit(attacker, defender, move, 0)
		attacker.last_move_used = move
		_current_actor_index += 1
		_set_phase(BattlePhase.FAINT_CHECK)
		return

	# [D4 Bundle 6] Poltergeist: fails outright if the target holds no item.
	# Checked BEFORE the accuracy roll, same shape as Belch/Dream Eater above.
	if move.is_poltergeist and defender.held_item == null:
		move_effect_failed.emit(attacker, "poltergeist_no_item")
		move_executed.emit(attacker, defender, move, 0)
		attacker.last_move_used = move
		_current_actor_index += 1
		_set_phase(BattlePhase.FAINT_CHECK)
		return
	# [D4 Bundle 7] Focus Punch: fails outright (no damage, PP already spent
	# above) if the user took ANY damage this turn before its own turn came
	# up — reuses hit_by_this_turn directly. Checked BEFORE the accuracy
	# roll, same shape as Belch/Poltergeist/Dream Eater above. See
	# MoveData.is_focus_punch's own doc comment for the full source citation.
	if move.is_focus_punch and not attacker.hit_by_this_turn.is_empty():
		move_effect_failed.emit(attacker, "focus_punch_lost_focus")
		move_executed.emit(attacker, defender, move, 0)
		attacker.last_move_used = move
		_current_actor_index += 1
		_set_phase(BattlePhase.FAINT_CHECK)
		return

	# [D4 Bundle 7] Last Resort: fails unless every OTHER known move slot has
	# been used since this mon's last switch-in, AND it knows at least 2
	# moves total. See BattlePokemon.used_move_slots' own doc comment for the
	# full source citation (including the real correction that this tracker
	# resets on switch-out).
	if move.is_last_resort:
		var lr_ok: bool = attacker.moves.size() >= 2
		if lr_ok:
			for lr_i in range(attacker.moves.size()):
				if attacker.moves[lr_i] == move:
					continue
				if lr_i >= attacker.used_move_slots.size() or not attacker.used_move_slots[lr_i]:
					lr_ok = false
					break
		if not lr_ok:
			move_effect_failed.emit(attacker, "last_resort_not_ready")
			move_executed.emit(attacker, defender, move, 0)
			attacker.last_move_used = move
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

	# [D4 Bundle 7] Shell Trap: fails ("Shell Trap didn't work!") unless
	# armed by a physical hit landing before this mon's own turn this same
	# turn (shell_trap_armed, set reactively — see MoveData.is_shell_trap's
	# own doc comment for the full source citation and the priority-(-3)
	# by-construction argument). If armed, falls through to the ordinary
	# accuracy check + hit below, exactly like a normal move.
	if move.is_shell_trap and not attacker.shell_trap_armed:
		move_effect_failed.emit(attacker, "shell_trap_didnt_work")
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
		# [D4 Bundle 5] Fury Cutter — same reset-on-miss shape as Rollout above.
		if move.is_fury_cutter:
			attacker.fury_cutter_counter = 0
		# [D4 Bundle 5] Steel Beam — unconditional self-recoil fires even on a
		# missed hit (see MoveData.is_steel_beam's own doc comment).
		if move.is_steel_beam:
			_apply_max_hp_50_recoil(attacker, ng_active)
		# [M19-rampage] A miss does NOT cancel a CONTINUING rampage/Uproar lock —
		# the counter still decrements and (rampage only) still self-confuses on
		# schedule regardless of whether this turn's hit connected. A first-use
		# miss never sets the lock at all (only reached here if already locked
		# from an earlier turn's successful hit). Source: MoveEndRampage/the
		# Uproar end-of-turn decrement both run independent of accuracy outcome.
		if (move.is_rampage or move.is_uproar) and attacker.locked_move == move:
			if move.is_rampage:
				attacker.rampage_turns -= 1
				if attacker.rampage_turns <= 0:
					attacker.locked_move = null
					var confused_on_miss: bool = StatusManager.try_apply_confusion(
							attacker, null, ng_active)
					if confused_on_miss:
						secondary_applied.emit(attacker, MoveData.SE_CONFUSION)
					rampage_lock_ended.emit(attacker, move, confused_on_miss)
			else:
				attacker.uproar_turns -= 1
				if attacker.uproar_turns <= 0:
					attacker.locked_move = null
					rampage_lock_ended.emit(attacker, move, false)
		move_missed.emit(attacker, "accuracy")
		# [M19-recoil-on-miss] An accuracy-roll miss (or a semi-invulnerable
		# dodge — both report "accuracy" from this same site) is one of the 4
		# "unaffected" reasons that trigger crash damage.
		if move.crashes_on_miss:
			_apply_crash_damage(attacker, ng_active)
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
		# never needs one. [D4 CHEAP bundle]: Ingrain blocks it too (a plain
		# volatile check, not ability-driven — see that function's own doc
		# comment), so the failure reason/signal distinguishes which one fired.
		if AbilityManager.blocks_forced_switch(defender, attacker, ng_active):
			if defender.ingrain_active:
				move_effect_failed.emit(attacker, "ingrain_blocks_switch")
			else:
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

	# [D4 Bundle 8] Snatch: intercepts the next snatch_affected move used by
	# ANYONE this turn, reassigning attacker (and attacker_idx/attacker_side,
	# since this is the FIRST call-a-move mechanic in this project to
	# reassign the ATTACKER itself rather than just move/defender) to
	# whichever earlier-in-turn-order combatant is still armed. Every
	# snatchable move in this project's roster is self/field-targeting
	# (buffs, heals, screens, Substitute, party-wide cures), so collapsing
	# BOTH attacker and defender onto the thief matches source's own
	# `battlerAtk == battlerDef` handling and needs no per-move branching.
	# Only ONE steal per turn total (`_snatch_used_this_turn`, a global
	# guard — NOT per-snatcher; see MoveData.is_snatch's own doc comment
	# for the full source citation).
	if move.snatch_affected and not _snatch_used_this_turn:
		var _snatch_thief: BattlePokemon = null
		for _si in range(_current_actor_index):
			var _snatch_cand: BattlePokemon = _turn_order[_si]
			if _snatch_cand.snatch_active and _snatch_cand != attacker:
				_snatch_thief = _snatch_cand
				break
		if _snatch_thief != null:
			_snatch_thief.snatch_active = false
			_snatch_used_this_turn = true
			move_stolen.emit(_snatch_thief, attacker, move)
			attacker = _snatch_thief
			defender = _snatch_thief
			attacker_idx = _actor_indices.get(attacker, _combatants.find(attacker))
			attacker_side = attacker_idx / _active_per_side

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
		_reset_mon_species(incoming)
		_reset_mon_stats(incoming)
		_reset_mon_type(incoming)
		_reset_mon_ability(incoming)
		_reset_mon_mimicked_move(incoming)
		_reset_mon_transform(incoming)
		# [M20] Exp-participant tracking — see _do_voluntary_switch's own comment.
		if attacker_side == 0:
			_add_exp_participant(bp_slot)
		else:
			_reset_exp_participants_for_opponent_slot(bp_field_slot)
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

	# ── Teleport / Chilly Reception: unconditional self-switch, no stat pass ──
	# See MoveData.is_teleport's/is_chilly_reception's own doc comments for the
	# full source citation (both bypass trapping via the same
	# SWITCH_IGNORE_ESCAPE_PREVENTION flag Baton Pass uses, and neither passes
	# stat stages/volatiles the way Baton Pass does — a plain `_do_voluntary_switch`
	# reuse, not the heavier Baton Pass apparatus above). Chilly Reception's own
	# weather-set is handled by the ordinary weather-setting dispatch further
	# below (in the status-move branch) since power==0 for it; this block only
	# needs to fire the switch itself once execution reaches this point again
	# on the SAME action — so instead both moves are dispatched fully here,
	# right where the switch needs to happen, with Chilly Reception's weather
	# attempted first.
	if move.is_teleport or move.is_chilly_reception:
		if move.is_chilly_reception:
			if try_set_weather(WEATHER_HAIL, attacker, false):
				weather_set.emit(attacker, WEATHER_HAIL)
				_notify_weather_changed()
		var tp_party: BattleParty = _parties[attacker_side]
		if not tp_party.has_valid_switch_target():
			move_effect_failed.emit(attacker, "no_switch_target")
			move_executed.emit(attacker, defender, move, 0)
			attacker.last_move_used = move
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return
		var tp_slot: int = _get_replacement_slot(attacker_idx)
		_do_voluntary_switch(attacker_idx, tp_slot)
		move_executed.emit(attacker, defender, move, 0)
		_current_actor_index += 1
		_set_phase(BattlePhase.FAINT_CHECK)
		return

	# ── Mirror Move: repeat the move that most recently hit the user this turn ─
	# Source: battle_move_resolution.c :: GetMirrorMoveMove (L4966-4993) reads
	#   gBattleStruct->lastTakenMove[gBattlerAttacker] — the move that hit the
	#   MIRROR MOVE USER, NOT the target's own last-used move (a genuinely
	#   different tracking axis — confirmed via direct source read, not
	#   assumed). Reuses this project's existing `_last_attacker_move`/
	#   `_last_attacker` dictionaries directly (already built for Destiny
	#   Bond/Aftermath/Innards Out, cleared every turn — see
	#   BattleManager._phase_priority_resolution) — zero new tracking state
	#   needed. `defender` is reassigned to whoever actually hit the user
	#   (not necessarily the same as the originally-resolved target, relevant
	#   in doubles), same "reassign and fall through" shape Metronome below
	#   uses — confirmed from source both dispatch through the identical
	#   `CancelerCallSubmove` mechanism (L523-553).
	if move.is_mirror_move:
		var mirrored_move: MoveData = _last_attacker_move.get(attacker, null)
		if mirrored_move == null:
			move_effect_failed.emit(attacker, "mirror_move_failed")
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return
		move_called.emit(attacker, mirrored_move)
		move = mirrored_move
		defender = _last_attacker.get(attacker, defender)

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

	# [D4 bundle] Sleep Talk: same reassignment shape as Metronome just above,
	# but the pool is the ATTACKER's own moveset, not the global move list.
	# `usable_while_asleep` only bypasses `pre_move_check`'s sleep block — it
	# does NOT mean the attacker really IS asleep (e.g. a test or an AI edge
	# case could still reach this dispatch while awake). Source's own
	# GetSleepTalkMove checks "is the user asleep or Comatose" as its OWN
	# first gate, independent of that bypass — reproduced inside
	# `_pick_sleep_talk_move` itself, not assumed for free.
	if move.is_sleep_talk:
		var st_called_move: MoveData = _pick_sleep_talk_move(attacker, ng_active)
		if st_called_move == null:
			move_effect_failed.emit(attacker, "sleep_talk_no_moves")
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return
		move_called.emit(attacker, st_called_move)
		move = st_called_move

	# ── Copycat: repeat the last move that actually landed, by ANYONE ────────
	# Source: GetCopycatMove (battle_move_resolution.c L5132-5140): reads
	#   `_last_landed_move_anyone` (this project's own battle-wide analog of
	#   gLastUsedMove — see that field's own doc comment for the full
	#   gating-condition citation and its disclosed status-move-coverage gap),
	#   excluded if `copycatBanned` (BAN_COPYCAT).
	if move.is_copycat:
		var cc_called_move: MoveData = _pick_copycat_move()
		if cc_called_move == null:
			move_effect_failed.emit(attacker, "copycat_failed")
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return
		move_called.emit(attacker, cc_called_move)
		move = cc_called_move

	# ── Me First: steal the target's chosen move before it acts, at ×1.5 ─────
	# Source: GetMeFirstMove (battle_move_resolution.c L5143-5151): fails if
	#   the target's own chosen move is a status move, `meFirstBanned`
	#   (BAN_ME_FIRST), or the target has already acted this turn
	#   (`_has_target_already_acted` — NO turn-order pre-emption needed at
	#   all, confirmed via Step 0 source read; whether Me First "works" is
	#   purely a function of the EXISTING speed/priority-driven turn order).
	#   The ×1.5 power boost is applied later, at the same base-power-
	#   modifier pipeline stage Helping Hand occupies (see
	#   `_me_first_boost_active`'s own doc comment).
	if move.is_me_first:
		var mf_defender_idx: int = _actor_indices.get(defender, _combatants.find(defender))
		var mf_target_move: MoveData = _chosen_moves[mf_defender_idx]
		var mf_fail: bool = (mf_target_move == null
				or mf_target_move.category == 2
				or (mf_target_move.ban_flags & MoveData.BAN_ME_FIRST) != 0
				or _has_target_already_acted(defender))
		if mf_fail:
			move_effect_failed.emit(attacker, "me_first_failed")
			move_executed.emit(attacker, defender, move, 0)
			attacker.last_move_used = move
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return
		move_called.emit(attacker, mf_target_move)
		move = mf_target_move
		_me_first_boost_active = true

	# ── Assist: use a random move from the user's OWN bench ──────────────────
	# Source: GetAssistMove (battle_move_resolution.c L5029-5075): scans every
	#   non-active, non-fainted party member's moveset, excluding `assistBanned`
	#   (BAN_ASSIST) moves, and picks uniformly at random.
	if move.is_assist:
		var as_called_move: MoveData = _pick_assist_move(attacker)
		if as_called_move == null:
			move_effect_failed.emit(attacker, "assist_failed")
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return
		move_called.emit(attacker, as_called_move)
		move = as_called_move

	# ── Instruct: force the TARGET to immediately re-use its own last move ───
	# Source: battle_script_commands.c :: BS_TryInstruct (L13149-13195). Unlike
	# Mirror Move/Metronome above (which only reassign `defender`/`move`),
	# Instruct reassigns `attacker` itself — the instructed Pokémon becomes the
	# one actually executing the move, matching source's own
	# `copybyte gBattlerAttacker, gBattlerTarget` — so `attacker_idx`/
	# `attacker_side` are recomputed too, keeping every downstream per-side/
	# per-battler lookup consistent. New defender = the ORIGINAL attacker (the
	# Instruct user) — exact in singles (the only valid opposing target
	# anyway); a known simplification in doubles, where source tracks a real
	# backUpTarget that could be an ally instead. The instructed move costs NO
	# PP (this dispatch point sits after the normal PP-deduction block above,
	# the same "called move" shape Mirror Move/Metronome already establish).
	# See MoveData.is_instruct's own doc comment for the full exclusion list.
	if move.is_instruct:
		var instr_last: MoveData = defender.last_move_used
		var instr_idx: int = defender.moves.find(instr_last) if instr_last != null else -1
		var instr_fail: bool = (instr_last == null
				or instr_idx < 0
				or defender.current_pp[instr_idx] <= 0
				or instr_last.two_turn
				or instr_last.is_recharge
				or instr_last.is_rollout
				or instr_last.is_metronome
				or instr_last.is_mirror_move
				or instr_last.is_bide
				or instr_last.protect_method == BattlePokemon.PROTECT_METHOD_OBSTRUCT
				or instr_last.is_rampage
				or instr_last.is_uproar
				or instr_last.is_first_turn_only
				or instr_last.is_transform
				or defender.bide_turns != 0)
		if instr_fail:
			move_effect_failed.emit(attacker, "instruct_failed")
			move_executed.emit(attacker, defender, move, 0)
			attacker.last_move_used = move
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return
		move_called.emit(attacker, instr_last)
		# The Instruct user's OWN last move is Instruct itself — must be set
		# BEFORE the attacker/defender swap below, since after the swap
		# `attacker` no longer refers to the Instruct user.
		attacker.last_move_used = move
		var instr_new_attacker: BattlePokemon = defender
		var instr_new_defender: BattlePokemon = attacker
		attacker = instr_new_attacker
		defender = instr_new_defender
		attacker_idx = _actor_indices.get(attacker, _combatants.find(attacker))
		attacker_side = attacker_idx / _active_per_side
		move = instr_last

	# ── Rollout / Ice Ball: interruption reset ────────────────────────────────
	# Source: battle_move_resolution.c :: SetSameMoveTurnValues `default` case
	#   (L4915-4917): using any move OTHER than Rollout unconditionally resets
	#   rolloutTimer to 0 — this is how switching moves breaks the power streak.
	if not move.is_rollout:
		attacker.rollout_turns = 0

	# [D4 Bundle 5] Fury Cutter — same "used a different move" reset shape as
	# Rollout above (source's own `default:` case resets both counters).
	if not move.is_fury_cutter:
		attacker.fury_cutter_counter = 0

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

	# [M19d] Metal Burst — same EFFECT_REFLECT_DAMAGE shape as Counter/Mirror
	# Coat, but reflects EITHER category at 1.5x (not 2x), whichever was hit
	# LAST this turn (BattlePokemon.last_hit_was_special) if both landed
	# (doubles). Source: GetReflectDamageMoveDamageCategory (battle_util.c
	# L306-320) — Counter/Mirror Coat's own single-category bitmask never
	# reaches this branch at all, only Metal Burst's dual-category one does.
	if move.metal_burst:
		if attacker.last_physical_damage == 0 and attacker.last_special_damage == 0:
			move_effect_failed.emit(attacker, "no_damage_to_counter")
			move_executed.emit(attacker, defender, move, 0)
		else:
			var base_dmg: int = (attacker.last_special_damage
					if attacker.last_hit_was_special and attacker.last_special_damage > 0
					else attacker.last_physical_damage)
			_apply_fixed_dmg_to_target(attacker, defender, move, base_dmg * 150 / 100)
		_current_actor_index += 1
		_set_phase(BattlePhase.FAINT_CHECK)
		return

	# ── Stockpile ─────────────────────────────────────────────────────────
	# Source: battle_move_resolution.c, case EFFECT_STOCKPILE (L1288-1291,
	#   4629-4631): fails at 3 stacks; else increments `stockpile_count`
	#   UNCONDITIONALLY and raises Def+SpDef +1 each via the ordinary
	#   generic stat-change pipeline (`_apply_one_stat_change_pair`, self-
	#   targeted — `move.stat_change_self` is set in data), so
	#   Contrary/Simple/Mist/Defiant/Opportunist/Mirror Herb all apply
	#   exactly as they would to any other self-raise. `stockpile_def_added`/
	#   `stockpile_spdef_added` only accumulate the ACTUAL returned delta
	#   (0 if capped or Contrary-inverted) — see BattlePokemon.
	#   stockpile_count's own doc comment for the full citation.
	if move.is_stockpile:
		if attacker.stockpile_count >= 3:
			move_effect_failed.emit(attacker, "stockpile_maxed")
		else:
			attacker.stockpile_count += 1
			var sp_def_actual: int = _apply_one_stat_change_pair(
					attacker, defender, move, BattlePokemon.STAGE_DEF, 1, ng_active)
			if sp_def_actual > 0:
				attacker.stockpile_def_added += sp_def_actual
			var sp_spdef_actual: int = _apply_one_stat_change_pair(
					attacker, defender, move, BattlePokemon.STAGE_SPDEF, 1, ng_active)
			if sp_spdef_actual > 0:
				attacker.stockpile_spdef_added += sp_spdef_actual
			stockpile_gained.emit(attacker, attacker.stockpile_count)
		move_executed.emit(attacker, defender, move, 0)
		_current_actor_index += 1
		_set_phase(BattlePhase.FAINT_CHECK)
		return

	# ── Spit Up / Swallow ─────────────────────────────────────────────────
	# Source: battle_move_resolution.c, case EFFECT_SPIT_UP/EFFECT_SWALLOW
	#   (L1296-1299): both fail outright at 0 stacks. Release-and-reset
	#   (MoveEndMoveBlock, L3416-3439) ALWAYS fires once the move is
	#   attempted at 1+ stacks — even if Swallow's own heal "fails" at full
	#   HP (Cmd_stockpiletohpheal, battle_script_commands.c L7168-7193,
	#   still zeroes `stockpileCounter` on ITS OWN fail branch) — so the
	#   stacks/stat-boost removal happens unconditionally below, outside
	#   either branch's own success/failure. The removal itself is a RAW,
	#   ungated stat decrease (no Mist/ability gate — source's own
	#   `SetStatChange` call for the undo has none), unlike the original
	#   raise above.
	# NOTE this dispatch MUST sit here, before the generic `move.power > 0`
	# damaging-move branch below — Spit Up carries a `power=1` PLACEHOLDER
	# (real power is 100*stockpile_count, computed here), the same
	# convention Sonic Boom/Dragon Rage/Night Shade/OHKO already use, all of
	# which are ALSO dispatched before this same generic branch for the
	# identical reason (a real bug caught during this bundle's own test
	# suite: Spit Up was originally placed AFTER this branch, so the
	# generic dispatch silently claimed it first, dealing a flat power=1
	# hit and never reaching the real 100×count logic at all).
	if move.is_spit_up or move.is_swallow:
		if attacker.stockpile_count == 0:
			move_effect_failed.emit(attacker, "stockpile_empty")
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return
		# [D4 Bundle 4] Spit Up's own `_do_damaging_hit` call already emits
		# `move_executed` internally (with the real damage dealt) — do NOT
		# re-emit it below for that branch, unlike Swallow (a pure status-
		# style effect with no damaging-hit call of its own).
		var sp_already_emitted: bool = false
		if move.is_spit_up:
			var spit_power: int = 100 * attacker.stockpile_count
			_do_damaging_hit(attacker, defender, move, false, false, spit_power)
			sp_already_emitted = true
		else:
			if attacker.current_hp >= attacker.max_hp:
				move_effect_failed.emit(attacker, "already_full_hp")
			else:
				# 1 stack → 1/4, 2 stacks → 1/2, 3 stacks → full (1/1).
				var swallow_divisor: Array = [0, 4, 2, 1]
				var swallow_heal: int = max(
						1, attacker.max_hp / swallow_divisor[attacker.stockpile_count])
				attacker.current_hp = min(attacker.max_hp, attacker.current_hp + swallow_heal)
				drain_heal.emit(attacker, swallow_heal)
		var released_count: int = attacker.stockpile_count
		attacker.stockpile_count = 0
		if attacker.stockpile_def_added > 0:
			var def_removed: int = StatusManager.apply_stat_change(
					attacker, BattlePokemon.STAGE_DEF, -attacker.stockpile_def_added, null, ng_active)
			if def_removed != 0:
				stat_stage_changed.emit(attacker, BattlePokemon.STAGE_DEF, def_removed)
			attacker.stockpile_def_added = 0
		if attacker.stockpile_spdef_added > 0:
			var spdef_removed: int = StatusManager.apply_stat_change(
					attacker, BattlePokemon.STAGE_SPDEF, -attacker.stockpile_spdef_added, null, ng_active)
			if spdef_removed != 0:
				stat_stage_changed.emit(attacker, BattlePokemon.STAGE_SPDEF, spdef_removed)
			attacker.stockpile_spdef_added = 0
		stockpile_released.emit(attacker, released_count)
		if not sp_already_emitted:
			move_executed.emit(attacker, defender, move, 0)
		_current_actor_index += 1
		_set_phase(BattlePhase.FAINT_CHECK)
		return

	# [D1 easy bundle] Captured only by the ordinary single-target branch
	# below — After You/Quash-adjacent single-target-only moves are the
	# only members of EFFECT_HIT_ESCAPE/EFFECT_HIT_SWITCH_TARGET, so
	# spread/multi-hit never need these. `he_sub_before` snapshots the
	# defender's Substitute HP BEFORE the hit so a Substitute-absorbed hit
	# (which _do_damaging_hit reports as 0 direct damage) can still be
	# told apart from a truly-immune/fully-blocked hit — see
	# MoveData.is_hit_escape's own doc comment for why this distinction
	# matters (source's own INCLUDING_SUBSTITUTES check).
	var he_single_dmg: int = -1
	var he_sub_before: int = -1
	if move.power > 0:
		# [D4 Bundle 6] Present: heal branch bypasses the whole damaging
		# dispatch — heals the TARGET max_hp/4 (type effectiveness never
		# computed, matching source's ignoreTypeCalc), fails with
		# "already at full HP" if capped.
		if move.is_present and _present_heal_branch:
			if defender.current_hp >= defender.max_hp:
				move_effect_failed.emit(defender, "already_full_hp")
			else:
				var pr_heal: int = max(1, defender.max_hp / 4)
				defender.current_hp = min(defender.max_hp, defender.current_hp + pr_heal)
				drain_heal.emit(defender, pr_heal)
			move_executed.emit(attacker, defender, move, 0)
			attacker.last_move_used = move
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# [D4 Bundle 7] Pollen Puff: if the chosen target is an ally
		# (doubles only — never reachable in singles), jumps straight to
		# Heal Pulse's own formula instead of dealing damage (source:
		# BattleScript_EffectHitEnemyHealAlly, `jumpiftargetally
		# BattleScript_EffectHealPulse` — literally calls Heal Pulse's own
		# script, not just its formula). No pulse_move flag on this move
		# (confirmed absent), so no Mega Launcher interaction.
		if move.is_pollen_puff and defender == _get_ally(attacker):
			if defender.current_hp >= defender.max_hp:
				move_effect_failed.emit(defender, "already_full_hp")
			else:
				var pp_heal: int = max(1, int(defender.max_hp * 0.5))
				defender.current_hp = min(defender.max_hp, defender.current_hp + pp_heal)
				drain_heal.emit(defender, pp_heal)
			move_executed.emit(attacker, defender, move, 0)
			attacker.last_move_used = move
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

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
						_dmg_power_override, false, _me_first_boost_active)
		elif move.multi_hit or move.strike_count > 1:
			# [M18.5g] Multi-hit moves (Bullet Seed/Double Kick/Triple Kick/etc. family)
			# — see _do_multi_hit_sequence's own doc comment for the full mechanism.
			# None of the 31 in-scope moves are also spread moves (TARGET_SELECTED
			# throughout; Dragon Darts' TARGET_SMART doubles-redirect is a separate,
			# flagged-not-built doubles-only nuance — see gen_moves.py's own comment),
			# so this branch and the spread branch above are mutually exclusive in
			# practice, not just by construction.
			var hh_boost: bool = _helping_hand[attacker_idx]
			_do_multi_hit_sequence(attacker, defender, move, hh_boost, _dmg_power_override,
					_me_first_boost_active)
		else:
			# Single-target damaging move.
			var hh_boost: bool = _helping_hand[attacker_idx]
			he_sub_before = defender.substitute_hp
			he_single_dmg = _do_damaging_hit(attacker, defender, move, false, hh_boost,
					_dmg_power_override, false, _me_first_boost_active)

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

		# [D1 easy bundle] U-turn / Volt Switch / Flip Turn — the attacker
		# gets a voluntary-style switch prompt after a hit that connected
		# (real HP damage OR a Substitute absorption — INCLUDING_SUBSTITUTES
		# in source), as long as the attacker is still alive (a recoil/
		# contact-punish death correctly blocks it) and no other switch is
		# already pending this action. Reuses `_get_replacement_slot`'s own
		# test-queue → AI-choice → deterministic-first-available chain —
		# the SAME player-choice selection faint-replacement already uses —
		# NOT Red Card's random pick, since this is a voluntary-style
		# switch the user's own trainer chooses, not a forced one. See
		# MoveData.is_hit_escape's own doc comment for full source citations.
		var he_connected: bool = he_single_dmg > 0 \
				or (he_sub_before > 0 and defender.substitute_hp < he_sub_before)

		# [D4 Bundle 5] Fury Cutter — increment-or-wrap the consecutive-hit
		# counter. Source: SetSameMoveTurnValues, case EFFECT_FURY_CUTTER
		# (battle_move_resolution.c L4893-4897) — see MoveData.is_fury_cutter's
		# own doc comment for the full citation, including the confirmed
		# wrap-to-0 (not plateau) behavior once the counter reaches 5.
		if move.is_fury_cutter:
			if he_connected and attacker.fury_cutter_counter < 5:
				attacker.fury_cutter_counter += 1
			else:
				attacker.fury_cutter_counter = 0

		# [D4 Bundle 5] Steel Beam — unconditional self-recoil, same amount
		# and gate regardless of whether this hit connected (see
		# MoveData.is_steel_beam's own doc comment).
		if move.is_steel_beam:
			_apply_max_hp_50_recoil(attacker, ng_active)

		# [D4 Bundle 5] Charge — consumed the instant a genuinely LATER
		# Electric-type move is used, AFTER that move's own damage has
		# already been computed (DamageCalculator.calculate reads
		# `attacker.charged` during `_do_damaging_hit` above — clearing it
		# any earlier would rob the very move that's supposed to consume
		# it of its own boost). See BattlePokemon.charged's own doc comment
		# for the source-verified consumption timing. A disclosed
		# simplification: checks the move's own declared type, not any
		# ability-mutated effective type (Galvanize/Normalize's mutation is
		# computed only inside DamageCalculator.calculate, not threaded
		# back out to this point).
		if attacker.charged and move.type == TypeChart.TYPE_ELECTRIC:
			attacker.charged = false

		if move.is_hit_escape and he_connected and attacker.current_hp > 0:
			var he_slot: int = _get_replacement_slot(attacker_idx)
			if he_slot >= 0:
				var he_old_mon: BattlePokemon = attacker
				_do_forced_switch_in(attacker_side, he_slot, attacker_idx % _active_per_side)
				hit_escape_switch.emit(he_old_mon, _combatants[attacker_idx])

		# [D1 easy bundle] Circle Throw / Dragon Tail — forces the DEFENDER
		# out after a hit that dealt REAL HP damage — EXCLUDING a
		# Substitute absorption (the opposite of Hit Escape's own
		# inclusive check, confirmed from source). Reuses `_do_forced_
		# switch_in` + the same random-replacement helper Roar/Whirlwind/
		# Red Card already use (a genuinely forced switch, not a player
		# choice). No-ops (damage still stands) if there's no valid
		# replacement on the defender's side, or if Guard Dog blocks it.
		# See MoveData.is_hit_switch_target's own doc comment for full
		# source citations.
		if move.is_hit_switch_target and he_single_dmg > 0 and not defender.fainted \
				and attacker.current_hp > 0 \
				and not AbilityManager.blocks_forced_switch(defender, attacker, ng_active):
			var hst_def_idx: int = _combatants.find(defender)
			var hst_side: int = 1 - attacker_side
			var hst_field_slot: int = hst_def_idx % _active_per_side
			var hst_slot: int = _parties[hst_side].get_random_non_fainted_not_active(_force_roar_rng)
			if hst_slot >= 0:
				var hst_old_def: BattlePokemon = defender
				_do_forced_switch_in(hst_side, hst_slot, hst_field_slot)
				hit_switch_target.emit(hst_old_def, _combatants[hst_def_idx])
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

		# [D4 bundle] Magic Coat — self-targeted, sets a single-turn volatile
		# consumed by the Magic Bounce swap further below (extended with an
		# OR condition rather than a second parallel swap). See
		# MoveData.is_magic_coat's own doc comment for the full citation.
		if move.is_magic_coat:
			attacker.magic_coat_active = true
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Follow Me / Rage Powder ───────────────────────────────────────────
		# Redirects all incoming single-target moves toward the user this turn.
		# Source: Cmd_setforcedtarget (battle_script_commands.c L8748):
		#   gSideTimers[user_side].followmeTimer = 1; followmeTarget = user.
		# Source: target = TARGET_USER, priority = +2.
		# [D0] Rage Powder's powder_move=TRUE (Follow Me lacks it) — a REAL
		# correction to this sub-group's own Step 0 assumption: the general
		# blocks_move_flag gate much earlier in this function checks `defender`,
		# which for this self-targeted move resolves to whatever the default
		# target-selection logic picked (the opponent), NOT the user itself —
		# it does NOT grant Grass-type/Overcoat immunity here "for free" as
		# originally assumed. Checked explicitly against the ATTACKER here
		# instead, reusing the identical AbilityManager.blocks_move_flag
		# function with the attacker passed in the defender-role parameter.
		if move.is_follow_me:
			if move.powder_move and AbilityManager.blocks_move_flag(attacker, move, ng_active, attacker):
				move_effect_failed.emit(attacker, "move_flag_blocked")
				move_executed.emit(attacker, attacker, move, 0)
				_current_actor_index += 1
				_set_phase(BattlePhase.FAINT_CHECK)
				return
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

		# ── Torment ───────────────────────────────────────────────────────────
		# Source: data/battle_scripts_1.s :: BattleScript_EffectTorment
		#   (L2453-2462); battle_script_commands.c :: Cmd_settorment (L8795-8809)
		# Fails if the target is already tormented. Blocked by Substitute (no
		# ignoresSubstitute flag). See BattlePokemon.tormented's own doc comment
		# for the execution-time block this infliction feeds.
		if move.is_torment:
			if aroma_veil_blocks:
				move_effect_failed.emit(defender, "aroma_veil_blocked")
				ability_triggered.emit(defender, "aroma_veil")
				move_executed.emit(attacker, defender, move, 0)
				_current_actor_index += 1
				_set_phase(BattlePhase.FAINT_CHECK)
				return
			if defender.substitute_hp > 0 and not move.ignores_substitute \
					and not AbilityManager.bypasses_infiltrator_barriers(attacker, ng_active):
				move_missed.emit(attacker, "substitute")
			elif defender.tormented:
				move_effect_failed.emit(defender, "torment_failed")
			else:
				defender.tormented = true
				tormented.emit(defender)
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Purify ───────────────────────────────────────────────────────────
		# Source: data/battle_scripts_1.s :: BattleScript_EffectPurify
		#   (L771-783). Fails outright (no cure attempt) if the target has no
		#   status at all. Only cures, THEN attempts a separate half-HP
		#   self-heal on the ATTACKER (its own independent already-at-full-HP
		#   fail case, which does not undo the cure).
		if move.is_purify:
			if defender.substitute_hp > 0 and not move.ignores_substitute \
					and not AbilityManager.bypasses_infiltrator_barriers(attacker, ng_active):
				move_missed.emit(attacker, "substitute")
			elif defender.status == BattlePokemon.STATUS_NONE:
				move_effect_failed.emit(defender, "purify_failed")
			else:
				defender.status = BattlePokemon.STATUS_NONE
				defender.toxic_counter = 0
				status_cured.emit(defender)
				if attacker.current_hp < attacker.max_hp:
					var purify_heal: int = max(1, attacker.max_hp / 2)
					attacker.current_hp = min(attacker.max_hp, attacker.current_hp + purify_heal)
					drain_heal.emit(attacker, purify_heal)
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Memento ──────────────────────────────────────────────────────────
		# Source: data/battle_scripts_1.s :: BattleScript_EffectMemento
		#   (L117-121) — stat-drop THEN self-faint, in that order. The
		#   stat-drop is gated by the Substitute check below; the self-faint
		#   is UNCONDITIONAL (Substitute protects the target, not the
		#   attacker from its own move's self-consequence) — matches the
		#   move's own well-established behavior of the user always fainting.
		if move.is_memento:
			if defender.substitute_hp > 0 and not move.ignores_substitute \
					and not AbilityManager.bypasses_infiltrator_barriers(attacker, ng_active):
				move_missed.emit(attacker, "substitute")
			else:
				_apply_stat_change_effect(attacker, defender, move, ng_active)
			# [M19-self-faint]-established shape: set current_hp = 0 only —
			# the generic FAINT_CHECK phase (which runs after every resolved
			# action) picks this up and handles .fainted/pokemon_fainted
			# itself, matching Self-Destruct/Explosion's own precedent
			# exactly (no synchronous double-fire here).
			attacker.current_hp = 0
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Nightmare ────────────────────────────────────────────────────────
		# Source: data/battle_scripts_1.s :: BattleScript_EffectNightmare
		#   (L2114-2121). Fails if already nightmared, fails if the target
		#   isn't asleep/Comatose — reuses Dream Eater's own gate shape.
		if move.is_nightmare:
			if defender.substitute_hp > 0 and not move.ignores_substitute \
					and not AbilityManager.bypasses_infiltrator_barriers(attacker, ng_active):
				move_missed.emit(attacker, "substitute")
			elif defender.nightmare_active:
				move_effect_failed.emit(defender, "nightmare_failed")
			else:
				var nm_asleep: bool = defender.status == BattlePokemon.STATUS_SLEEP \
						or AbilityManager.effective_ability_id(defender, ng_active, attacker) == AbilityManager.ABILITY_COMATOSE
				if nm_asleep:
					defender.nightmare_active = true
					nightmare_set.emit(defender)
				else:
					move_effect_failed.emit(defender, "nightmare_failed")
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Spite ────────────────────────────────────────────────────────────
		# Source: battle_script_commands.c :: Cmd_tryspiteppreduce
		#   (L8190-8250). -4 PP (this project's GEN_LATEST config), floored
		#   at 0. Fails if the target has no last-used move, that move's
		#   slot can't be found, or its PP is already 0. Ignores Substitute
		#   (own flag — no Substitute check here, matching source).
		if move.is_spite:
			var spite_slot: int = -1
			if defender.last_move_used != null:
				spite_slot = defender.moves.find(defender.last_move_used)
			if spite_slot == -1 or defender.current_pp[spite_slot] <= 0:
				move_effect_failed.emit(defender, "spite_failed")
			else:
				var spite_amount: int = min(4, defender.current_pp[spite_slot])
				defender.current_pp[spite_slot] -= spite_amount
				pp_reduced.emit(defender, defender.last_move_used, spite_amount)
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Curse ─────────────────────────────────────────────────────────────
		# [D4 Bundle 7] Source: Cmd_cursetarget (battle_script_commands.c
		#   L8351-8369) — genuinely TWO different scripts, not one script with
		#   a conditional. Ghost-type user: fails if the target is already
		#   cursed; else costs the USER maxHP/2 (floor) and curses the target
		#   (ticked maxHP/4 at end of turn, Magic-Guard-gated). Never calls
		#   typecalc (same gap as Foresight/Purify/Nightmare/Spite/Reflect
		#   Type/Toxic Thread/Venom Drench) — no type-immunity check at all,
		#   handled here by simply never computing one. Non-Ghost user: self
		#   +1 Atk/+1 Def/-1 Speed instead (defender is irrelevant) — reuses
		#   the existing generic multi-stat dispatch via `stat_change_self=
		#   true` in this move's own data, the same Bucket-3 shape every
		#   other plain multi-stat move uses.
		if move.is_curse:
			if attacker.species.types.has(TypeChart.TYPE_GHOST):
				if defender.substitute_hp > 0 and not move.ignores_substitute \
						and not AbilityManager.bypasses_infiltrator_barriers(attacker, ng_active):
					move_missed.emit(attacker, "substitute")
				elif defender.cursed:
					move_effect_failed.emit(defender, "curse_failed")
				else:
					var curse_cost: int = attacker.max_hp / 2
					attacker.current_hp = max(0, attacker.current_hp - curse_cost)
					defender.cursed = true
					curse_set.emit(defender)
			else:
				_apply_stat_change_effect(attacker, defender, move, ng_active)
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Grudge ────────────────────────────────────────────────────────────
		# [D4 Bundle 7] Self-targeted; simply arms grudge_active — the actual
		# PP-drain effect is entirely reactive, dispatched at the faint-check
		# chokepoint (see MoveData.is_grudge's own doc comment for the full
		# source citation). Always succeeds when cast (source sets the
		# volatile unconditionally).
		if move.is_grudge:
			attacker.grudge_active = true
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Snatch ────────────────────────────────────────────────────────────
		# [D4 Bundle 8] Fails if the caster is the last to move this turn
		# (nothing left to steal from) — reuses the existing `_is_last_to_move`
		# built for Analytic. See MoveData.is_snatch's own doc comment for the
		# full source citation.
		if move.is_snatch:
			if _is_last_to_move(attacker):
				move_effect_failed.emit(attacker, "snatch_failed")
			else:
				attacker.snatch_active = true
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return


		# ── Mean Look family (Spider Web / Mean Look / Block) ──────────────────
		# Source: EFFECT_MEAN_LOOK -> BattleScript_EffectMeanLook
		#   (data/battle_scripts_1.s L2100-2112): seteffectprimary ...
		#   MOVE_EFFECT_PREVENT_ESCAPE -- the same underlying mechanism
		#   Spirit Shackle sets as a damaging move's secondary (see this
		#   project's own SE_PREVENT_ESCAPE dispatch in _do_damaging_hit).
		# Self-contained early return (matching Disable/Encore's own shape)
		# rather than falling through to the shared foe_targeting/Magic-Bounce/
		# Substitute/type-immunity block further below, since these 3 moves
		# need their own Ghost-type immunity check that block doesn't provide.
		if move.is_mean_look:
			# magicCoatAffected=TRUE in source -- replicate the shared Magic
			# Bounce swap here since this block doesn't fall through to the
			# later shared check.
			if AbilityManager.bounces_status_move(defender, ng_active, attacker, move):
				move_bounced.emit(defender, attacker)
				ability_triggered.emit(defender, "magic_bounce")
				var mean_look_bounce_holder: BattlePokemon = defender
				defender = attacker
				attacker = mean_look_bounce_holder
			if defender.substitute_hp > 0 and not move.ignores_substitute \
					and not AbilityManager.bypasses_infiltrator_barriers(attacker, ng_active):
				move_missed.emit(attacker, "substitute")
			elif TypeChart.TYPE_GHOST in defender.species.types:
				# Move-script-level Ghost immunity at this project's GEN_LATEST
				# config (B_GHOSTS_ESCAPE/B_UPDATED_MOVE_FLAGS >= GEN_6) --
				# NOT the general type-effectiveness gate (Spider Web is
				# Bug-type, only 0.5x vs Ghost on the chart, not a 0x
				# immunity -- see move_data.gd's is_mean_look doc comment).
				move_effect_failed.emit(defender, "ghost_immune")
			elif not StatusManager.try_apply_escape_prevention(defender, attacker):
				move_effect_failed.emit(defender, "already_trapped")
			else:
				escape_prevented.emit(defender, attacker)
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Leech Seed ────────────────────────────────────────────────────────
		# Source: Cmd_setseeded (battle_script_commands.c L7061-7080) — see
		# MoveData.is_leech_seed's own doc comment for the full citation. Its own
		# dedicated Grass-immune check (inside try_apply_leech_seed) is NOT the
		# general type-effectiveness gate, matching the is_mean_look precedent
		# just above — self-contained early return rather than falling through
		# to the shared foe_targeting block further below.
		if move.is_leech_seed:
			if AbilityManager.bounces_status_move(defender, ng_active, attacker, move):
				move_bounced.emit(defender, attacker)
				ability_triggered.emit(defender, "magic_bounce")
				var leech_seed_bounce_holder: BattlePokemon = defender
				defender = attacker
				attacker = leech_seed_bounce_holder
			if defender.substitute_hp > 0 and not move.ignores_substitute \
					and not AbilityManager.bypasses_infiltrator_barriers(attacker, ng_active):
				move_missed.emit(attacker, "substitute")
			elif not StatusManager.try_apply_leech_seed(defender, attacker):
				move_effect_failed.emit(defender, "leech_seed_failed")
			else:
				leech_seeded.emit(defender, attacker)
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

		# ── Weather-conditional heal (Morning Sun / Synthesis / Moonlight / Shore Up) ─
		# Source: battle_script_commands.c :: Cmd_recoverbasedonsunlight
		#   (L8622-8689) -- ONE shared function backing all 4 moves. Fails if
		#   already at full HP, same shape as is_restore_hp above.
		if move.heals_based_on_weather:
			if attacker.current_hp >= attacker.max_hp:
				move_effect_failed.emit(attacker, "already_full_hp")
			else:
				var weather_heal: int = _weather_heal_amount(attacker, move, ng_active)
				attacker.current_hp = min(attacker.max_hp, attacker.current_hp + weather_heal)
				drain_heal.emit(attacker, weather_heal)
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Heal Pulse ────────────────────────────────────────────────────────
		# Source: BS_TryHealPulse (battle_script_commands.c L11645-11663): heals
		#   the SELECTED TARGET (not the user) 50% max HP, or 75% if the
		#   ATTACKER holds Mega Launcher and this move is `pulse_move` — a
		#   HARDCODED special case inside the heal calc itself, NOT the generic
		#   pulse-move damage multiplier (moot anyway, power=0). Fails if the
		#   target is already at full HP.
		if move.is_heal_pulse:
			if defender.current_hp >= defender.max_hp:
				move_effect_failed.emit(defender, "already_full_hp")
			else:
				var hp_heal_frac: float = 0.75 if (
						AbilityManager.effective_ability_id(attacker, ng_active) \
								== AbilityManager.ABILITY_MEGA_LAUNCHER \
						and move.pulse_move) else 0.5
				var hp_heal: int = max(1, int(defender.max_hp * hp_heal_frac))
				defender.current_hp = min(defender.max_hp, defender.current_hp + hp_heal)
				drain_heal.emit(defender, hp_heal)
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Life Dew ──────────────────────────────────────────────────────────
		# Source: BattleScript_EffectLifeDew (data/battle_scripts_1.s L704-727):
		#   heals the user 25% max HP if not full; INDEPENDENTLY, if a live
		#   ally exists and isn't full, heals the ally 25% max HP too (a no-op,
		#   not a failure, in singles where no ally exists). The WHOLE move
		#   only fails if NEITHER side has anything to heal.
		if move.is_life_dew:
			var ld_ally: BattlePokemon = _get_ally(attacker)
			var ld_user_full: bool = attacker.current_hp >= attacker.max_hp
			var ld_ally_healable: bool = ld_ally != null and ld_ally.current_hp < ld_ally.max_hp
			if ld_user_full and not ld_ally_healable:
				move_effect_failed.emit(attacker, "already_full_hp")
			else:
				if not ld_user_full:
					var ld_user_heal: int = max(1, attacker.max_hp / 4)
					attacker.current_hp = min(attacker.max_hp, attacker.current_hp + ld_user_heal)
					drain_heal.emit(attacker, ld_user_heal)
				if ld_ally_healable:
					var ld_ally_heal: int = max(1, ld_ally.max_hp / 4)
					ld_ally.current_hp = min(ld_ally.max_hp, ld_ally.current_hp + ld_ally_heal)
					drain_heal.emit(ld_ally, ld_ally_heal)
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Heal Bell / Aromatherapy ────────────────────────────────────────────
		# Source: Cmd_healpartystatus (battle_script_commands.c L8259-8340) — see
		# MoveData.is_heal_bell's own doc comment for the full Soundproof-partner
		# asymmetry citation. Never "fails" outright (source has no failure branch
		# for this effect — always resolves, even if nothing was actually cured).
		if move.is_heal_bell:
			_apply_heal_bell(attacker, move.sound_move, ng_active)
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Haze ──────────────────────────────────────────────────────────────
		# Source: Cmd_normalisebuffs (battle_script_commands.c L7217-7224) —
		# resets EVERY live battler on the field (both sides), not one target.
		# See MoveData.is_haze's own doc comment for the full citation.
		if move.is_haze:
			for mon: BattlePokemon in _combatants:
				if not mon.fainted:
					_reset_stat_stages(mon)
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Perish Song ─────────────────────────────────────────────────────
		# Source: Cmd_trysetperishsong (battle_script_commands.c L8400-8424) —
		# see MoveData.is_perish_song's own doc comment for the full citation
		# on the per-target exclusions and the all-unaffected fail condition.
		if move.is_perish_song:
			var ps_any_affected := false
			for ps_mon: BattlePokemon in _combatants:
				if ps_mon.fainted:
					continue
				if ps_mon.perish_song_active:
					continue
				if AbilityManager.blocks_move_flag(ps_mon, move, ng_active, attacker):
					continue
				if AbilityManager.blocks_prankster_move(attacker, ps_mon, move, ng_active):
					continue
				ps_mon.perish_song_active = true
				ps_mon.perish_song_timer = 3
				ps_any_affected = true
				perish_song_activated.emit(ps_mon)
			if not ps_any_affected:
				move_effect_failed.emit(attacker, "perish_song_failed")
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Defog ─────────────────────────────────────────────────────────────
		# Source: TryDefogClear (battle_script_commands.c L6755-6793) — see
		# MoveData.is_defog's own doc comment for the full citation. Clears the
		# TARGET's own side's screens (Reflect/Light Screen/Aurora Veil — the
		# same reciprocal logic `breaks_screens`/Brick Break already uses,
		# `[M16c]`), clears hazards from BOTH sides, then applies the
		# guaranteed foe-targeting evasion -1 via the ordinary generic dispatch.
		if move.is_defog:
			var defog_def_idx: int = _combatants.find(defender)
			var defog_def_side: int = defog_def_idx / _active_per_side
			var defog_dsc: Dictionary = _side_conditions[defog_def_side]
			if defog_dsc["reflect_turns"] > 0 or defog_dsc["light_screen_turns"] > 0 \
					or defog_dsc["aurora_veil_turns"] > 0:
				defog_dsc["reflect_turns"] = 0
				defog_dsc["light_screen_turns"] = 0
				defog_dsc["aurora_veil_turns"] = 0
				screens_broken.emit(defog_def_side)
			for defog_side_i in range(_side_conditions.size()):
				_clear_all_hazards(defog_side_i)
			_apply_stat_change_effect(attacker, defender, move, ng_active)
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Tidy Up ───────────────────────────────────────────────────────────
		# Source: TryTidyUpClear (battle_script_commands.c L6801-6825) — see
		# MoveData.is_tidy_up's own doc comment for the full citation. Clears
		# hazards from BOTH sides AND every Substitute currently on the field
		# (a real finding beyond the D2 recon's own "hazards + self stat-raise"
		# framing), then always applies the self Atk+1/Speed+1 raise regardless
		# of what (if anything) was cleared.
		if move.is_tidy_up:
			for tidy_side_i in range(_side_conditions.size()):
				_clear_all_hazards(tidy_side_i)
			for tidy_mon: BattlePokemon in _combatants:
				if tidy_mon.substitute_hp > 0:
					tidy_mon.substitute_hp = 0
					substitute_broke.emit(tidy_mon)
			_apply_stat_change_effect(attacker, defender, move, ng_active)
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Weather-setting (Sandstorm / Rain Dance / Sunny Day / Hail / Snowscape) ──
		# Source: Cmd_setfieldweather -> TryChangeBattleWeather(battler,
		# move.argument.weatherType, ABILITY_NONE) — the SAME function
		# ability-triggered weather-setting already calls. Reuses
		# try_set_weather directly, passing by_ability=false (matches source's
		# own ABILITY_NONE — a move can never count as a Primal-capable
		# setter, `[Batch fix]`). Never "fails" outright at this project's
		# dispatch level (try_set_weather itself just no-ops if the same
		# weather is already active, or if an active Primal weather refuses
		# the overwrite).
		if move.weather_type != WEATHER_NONE:
			if try_set_weather(move.weather_type, attacker, false):
				weather_set.emit(attacker, move.weather_type)
				_notify_weather_changed()
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Mud Sport / Water Sport ──────────────────────────────────────────
		# Source: Cmd_settypebasedhalvers (battle_script_commands.c
		# L9463-9500) — FIELD-WIDE (not per-side) 5-turn timers; see
		# MoveData.is_mud_sport/is_water_sport's own doc comment for the full
		# citation, including the x0.33 (not x0.5) reduction correction.
		# Fails outright (no refresh) if already active.
		if move.is_mud_sport:
			if _mud_sport_turns > 0:
				move_effect_failed.emit(attacker, "mud_sport_failed")
			else:
				_mud_sport_turns = 5
				field_sport_set.emit("mud_sport")
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		if move.is_water_sport:
			if _water_sport_turns > 0:
				move_effect_failed.emit(attacker, "water_sport_failed")
			else:
				_water_sport_turns = 5
				field_sport_set.emit("water_sport")
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Charge ────────────────────────────────────────────────────────────
		# Source: EFFECT_CHARGE (battle_move_resolution.c L4728-4739), shares
		# BattleScript_EffectStatChange with Autotomize/Strength Sap — the
		# Sp. Def+1 self-raise is handled by the generic `stat_change_stat`
		# dispatch further below; this block ONLY sets the persistent
		# power-doubling flag (`attacker.charged`), consumed inside
		# DamageCalculator.calculate and cleared by BattleManager immediately
		# after the next Electric-type move resolves (see
		# BattlePokemon.charged's own doc comment for the source-verified
		# consumption timing, including the deliberately-preserved
		# comment-vs-code divergence).
		if move.is_charge:
			attacker.charged = true
			charge_set.emit(attacker)

		# ── Laser Focus ───────────────────────────────────────────────────────
		# Source: trysetvolatile VOLATILE_LASER_FOCUS (battle_script_commands.c
		# L9271-9280) — fails if already active (BattleScript_ButItFailed via
		# `trysetvolatile`'s own already-set gate). See
		# MoveData.is_laser_focus's own doc comment for the full citation.
		if move.is_laser_focus:
			if attacker.laser_focus_turns > 0:
				move_effect_failed.emit(attacker, "laser_focus_failed")
			else:
				attacker.laser_focus_turns = 2
				laser_focus_set.emit(attacker)
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Roost ─────────────────────────────────────────────────────────────
		# Source: BattleScript_EffectRoost (data/battle_scripts_1.s
		# L1410-1414) — heals 50% max HP (fails outright if already full,
		# same shape as is_restore_hp) AND removes the Flying type for
		# exactly the rest of this turn. See MoveData.is_roost's own doc
		# comment for the full citation, including the mutate-and-restore
		# design (this project has no query-time type-overlay
		# infrastructure) and the confirmed mono-Flying->Normal (not
		# typeless) case at this project's config.
		if move.is_roost:
			if attacker.current_hp >= attacker.max_hp:
				move_effect_failed.emit(attacker, "already_full_hp")
			else:
				var roost_heal: int = max(1, attacker.max_hp / 2)
				attacker.current_hp = min(attacker.max_hp, attacker.current_hp + roost_heal)
				drain_heal.emit(attacker, roost_heal)
			var roost_types: Array = attacker.species.types.duplicate()
			if TypeChart.TYPE_FLYING in roost_types:
				attacker.roost_pre_types = roost_types.duplicate()
				attacker.roost_active = true
				var roost_flying_count: int = 0
				for _rt in roost_types:
					if _rt == TypeChart.TYPE_FLYING:
						roost_flying_count += 1
				# [D4 Bundle 5] B_ROOST_PURE_FLYING=GEN_LATEST at this
				# project's config — a mono-Flying user becomes pure
				# NORMAL-type for the turn, NOT typeless.
				var roost_new_types: Array = [TypeChart.TYPE_NORMAL] \
						if roost_flying_count == roost_types.size() \
						else roost_types.filter(func(_t): return _t != TypeChart.TYPE_FLYING)
				_set_mon_type_array(attacker, roost_new_types)
				types_changed.emit(attacker, roost_new_types, "roost")
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

		# ── Magnet Rise ──────────────────────────────────────────────────────
		# Source: data/battle_scripts_1.s :: BattleScript_EffectMagnetRise
		#   (L1285-1294); battle_script_commands.c, case VOLATILE_MAGNET_RISE
		#   (Cmd_trysetvolatile, L9277-9280). Fails if already active, or if
		#   the user has Ingrain or Smack Down active (can't levitate while
		#   forcibly grounded). See BattlePokemon.magnet_rise_turns's own doc
		#   comment for the AbilityManager.is_grounded priority-tier insertion.
		if move.is_magnet_rise:
			if attacker.magnet_rise_turns > 0 or attacker.ingrain_active or attacker.smack_down_active:
				move_effect_failed.emit(attacker, "magnet_rise_failed")
			else:
				attacker.magnet_rise_turns = 5
				magnet_rise_set.emit(attacker)
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Ingrain ──────────────────────────────────────────────────────────
		# Source: data/battle_scripts_1.s L2555 (trysetvolatile ...
		#   VOLATILE_ROOT); battle_end_turn.c :: HandleEndTurnIngrain
		#   (L457-474); battle_util.c L4953 (CanBattlerEscape's own root
		#   check). See BattlePokemon.ingrain_active's own doc comment for
		#   the full 3-piece composite mechanism. Fails if already rooted.
		if move.is_ingrain:
			if attacker.ingrain_active:
				move_effect_failed.emit(attacker, "ingrain_failed")
			else:
				attacker.ingrain_active = true
				ingrain_set.emit(attacker)
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Aqua Ring ────────────────────────────────────────────────────────
		# Source: battle_end_turn.c :: HandleEndTurnAquaRing (L438-455) — the
		#   literal same GetDrainedBigRootHp(battler, GetNonDynamaxMaxHP(
		#   battler)/16) call Ingrain's own heal uses. Fails if already active.
		if move.is_aqua_ring:
			if attacker.aqua_ring_active:
				move_effect_failed.emit(attacker, "aqua_ring_failed")
			else:
				attacker.aqua_ring_active = true
				aqua_ring_set.emit(attacker)
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Splash ───────────────────────────────────────────────────────────
		# Source: data/battle_scripts_1.s :: BattleScript_EffectDoNothing
		#   (L1945-1952) — genuinely does nothing at all.
		if move.is_do_nothing:
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Refresh ──────────────────────────────────────────────────────────
		# Source: battle_script_commands.c :: Cmd_curestatuswithmove
		#   (L8758-8790) — cures Burn/Poison/Toxic/Paralysis ONLY, confirmed
		#   NOT Sleep/Freeze (STATUS1_CAN_MOVE). See MoveData.is_refresh's own
		#   doc comment for the full citation.
		if move.is_refresh:
			var refresh_curable: bool = attacker.status == BattlePokemon.STATUS_BURN \
					or attacker.status == BattlePokemon.STATUS_POISON \
					or attacker.status == BattlePokemon.STATUS_TOXIC \
					or attacker.status == BattlePokemon.STATUS_PARALYSIS
			if refresh_curable:
				attacker.status = BattlePokemon.STATUS_NONE
				attacker.toxic_counter = 0
				status_cured.emit(attacker)
			else:
				move_effect_failed.emit(attacker, "refresh_failed")
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Take Heart ───────────────────────────────────────────────────────
		# Source: battle_move_resolution.c, case EFFECT_TAKE_HEART
		#   (L4653-4680): `if (WillAnyStatChange() || status1 != 0)` — an OR,
		#   so it still succeeds and cures status even when both stages are
		#   already at +6. Cures ANY status (unlike Refresh's narrower
		#   scope), then raises Attack + Sp.Atk by 1 each — confirmed via
		#   source's own data table, NOT Sp.Atk/Sp.Def. See MoveData.
		#   is_take_heart's own doc comment for the full citation.
		if move.is_take_heart:
			var th_had_status: bool = attacker.status != BattlePokemon.STATUS_NONE
			var th_atk_room: bool = attacker.stat_stages[BattlePokemon.STAGE_ATK] < 6
			var th_spatk_room: bool = attacker.stat_stages[BattlePokemon.STAGE_SPATK] < 6
			if th_had_status or th_atk_room or th_spatk_room:
				if th_had_status:
					attacker.status = BattlePokemon.STATUS_NONE
					attacker.toxic_counter = 0
					status_cured.emit(attacker)
				var th_atk: int = StatusManager.apply_stat_change(
						attacker, BattlePokemon.STAGE_ATK, 1, null, ng_active)
				if th_atk != 0:
					stat_stage_changed.emit(attacker, BattlePokemon.STAGE_ATK, th_atk)
				var th_spatk: int = StatusManager.apply_stat_change(
						attacker, BattlePokemon.STAGE_SPATK, 1, null, ng_active)
				if th_spatk != 0:
					stat_stage_changed.emit(attacker, BattlePokemon.STAGE_SPATK, th_spatk)
			else:
				move_effect_failed.emit(attacker, "take_heart_failed")
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Recycle ──────────────────────────────────────────────────────────
		# Source: battle_script_commands.c :: Cmd_tryrecycleitem
		#   (L9577-9603). Restores BattlePokemon.last_used_item — see its own
		#   doc comment for the real-correction citation (broader than
		#   last_consumed_berry).
		if move.is_recycle:
			if attacker.last_used_item != null and attacker.held_item == null:
				attacker.held_item = attacker.last_used_item
				attacker.last_used_item = null
				item_recycled.emit(attacker, attacker.held_item)
			else:
				move_effect_failed.emit(attacker, "recycle_failed")
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Belly Drum / Fillet Away / Clangorous Soul ─────────────────────────
		# Source: battle_move_resolution.c, cases EFFECT_BELLY_DRUM/
		#   EFFECT_STAT_CHANGE_HALF_HP/EFFECT_CLANGOROUS_SOUL (L4696-4731):
		#   `WillAnyStatChange() && Try*Hp(...)` — an AND, so this hard-fails
		#   with ZERO HP cost and ZERO stat change unless BOTH the stat
		#   change would do something AND current_hp is STRICTLY greater
		#   than the HP fraction. See MoveData.hp_cost_stat_boost's own doc
		#   comment for the full per-move citation and the Contrary-safe
		#   STAT_CHANGE_FORCE_MAX=12 encoding for Belly Drum.
		if move.hp_cost_stat_boost:
			var hcb_would_change: bool = attacker.stat_stages[move.stat_change_stat] < 6
			for hcb_extra_stat: int in move.extra_stat_change_stats:
				if attacker.stat_stages[hcb_extra_stat] < 6:
					hcb_would_change = true
			var hcb_cost: int = attacker.max_hp / move.hp_cost_divisor
			if hcb_cost == 0:
				hcb_cost = 1
			if hcb_would_change and attacker.current_hp > hcb_cost:
				attacker.current_hp -= hcb_cost
				passive_hp_lost.emit(attacker, hcb_cost)
				_apply_stat_change_effect(attacker, attacker, move, ng_active)
			else:
				move_effect_failed.emit(attacker, "stat_change_failed")
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Rest ──────────────────────────────────────────────────────────────
		# See MoveData.is_rest's own doc comment for the full source citation.
		# All 3 fail conditions checked BEFORE any heal/status-clear happens.
		if move.is_rest:
			var rest_id: int = AbilityManager.effective_ability_id(attacker, ng_active)
			if attacker.status == BattlePokemon.STATUS_SLEEP or rest_id == AbilityManager.ABILITY_COMATOSE:
				move_effect_failed.emit(attacker, "rest_already_asleep")
			elif attacker.current_hp >= attacker.max_hp:
				move_effect_failed.emit(attacker, "already_full_hp")
			elif rest_id == AbilityManager.ABILITY_INSOMNIA or rest_id == AbilityManager.ABILITY_VITAL_SPIRIT \
					or rest_id == AbilityManager.ABILITY_PURIFYING_SALT:
				move_effect_failed.emit(attacker, "rest_blocked_by_ability")
				ability_triggered.emit(attacker, "insomnia_protects")
			else:
				attacker.status = BattlePokemon.STATUS_NONE
				var rest_heal: int = attacker.max_hp - attacker.current_hp
				attacker.current_hp = attacker.max_hp
				if rest_heal > 0:
					drain_heal.emit(attacker, rest_heal)
				StatusManager.try_apply_status(attacker, BattlePokemon.STATUS_SLEEP, 2, null, ng_active, attacker)
				secondary_applied.emit(attacker, MoveData.SE_SLEEP)
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Acupressure ───────────────────────────────────────────────────────
		# See MoveData.is_acupressure's own doc comment for the full citation.
		if move.is_acupressure:
			var acu_candidates: Array = []
			for acu_stat in range(7):  # STAGE_ATK..STAGE_EVASION, all 7
				if attacker.stat_stages[acu_stat] < 6:
					acu_candidates.append(acu_stat)
			if acu_candidates.is_empty():
				move_effect_failed.emit(attacker, "stat_limit")
			else:
				var acu_stat_pick: int = acu_candidates[randi() % acu_candidates.size()]
				var acu_actual: int = StatusManager.apply_stat_change(
						attacker, acu_stat_pick, 2, null, ng_active)
				if acu_actual != 0:
					stat_stage_changed.emit(attacker, acu_stat_pick, acu_actual)
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Stuff Cheeks ──────────────────────────────────────────────────────
		# See MoveData.is_stuff_cheeks's own doc comment for the full citation.
		if move.is_stuff_cheeks:
			if attacker.held_item == null or attacker.held_item.pocket != ItemManager.POCKET_BERRIES:
				move_effect_failed.emit(attacker, "stuff_cheeks_no_berry")
			else:
				var sc_result: Dictionary = ItemManager.steal_and_eat_berry_effect(
						attacker, attacker.held_item, ng_active)
				var sc_berry: ItemData = attacker.held_item
				_consume_item(attacker)
				match sc_result.get("kind", ""):
					"heal":
						attacker.current_hp = min(attacker.max_hp, attacker.current_hp + sc_result["amount"])
						drain_heal.emit(attacker, sc_result["amount"])
					"cure_status":
						attacker.status = BattlePokemon.STATUS_NONE
					"cure_confusion":
						attacker.confusion_turns = 0
					"stat":
						var sc_actual: int = StatusManager.apply_stat_change(
								attacker, sc_result["stat"], sc_result["amount"], null, ng_active)
						if sc_actual != 0:
							stat_stage_changed.emit(attacker, sc_result["stat"], sc_actual)
				item_effect_triggered.emit(attacker, "stuff_cheeks_berry")
				var sc_def_actual: int = StatusManager.apply_stat_change(
						attacker, BattlePokemon.STAGE_DEF, 2, null, ng_active)
				if sc_def_actual != 0:
					stat_stage_changed.emit(attacker, BattlePokemon.STAGE_DEF, sc_def_actual)
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── No Retreat ────────────────────────────────────────────────────────
		# See MoveData.is_no_retreat's own doc comment for the full citation.
		if move.is_no_retreat:
			if attacker.no_retreat_active:
				move_effect_failed.emit(attacker, "no_retreat_already_used")
				move_executed.emit(attacker, defender, move, 0)
				_current_actor_index += 1
				_set_phase(BattlePhase.FAINT_CHECK)
				return
			attacker.no_retreat_active = true
			_apply_stat_change_effect(attacker, attacker, move, ng_active)
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Imprison ──────────────────────────────────────────────────────────
		# [D4 Bundle 8] Fails only if already active (permanent, no natural
		# expiry). See MoveData.is_imprison's own doc comment for the full
		# source citation.
		if move.is_imprison:
			if attacker.imprison_active:
				move_effect_failed.emit(attacker, "imprison_already_used")
			else:
				attacker.imprison_active = true
				imprison_set.emit(attacker)
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

		# ── Tailwind ──────────────────────────────────────────────────────────
		# Source: Cmd_settailwind (battle_script_commands.c L8172-8187): fails if
		#   already up on the caster's own side; else 4-turn timer (this project's
		#   Gen5+ config; source's pre-Gen5 branch is 3, not modeled).
		if move.is_tailwind:
			if _side_conditions[attacker_side]["tailwind_turns"] > 0:
				move_effect_failed.emit(attacker, "already_tailwind")
			else:
				_side_conditions[attacker_side]["tailwind_turns"] = 4
				side_condition_set.emit(attacker_side, "tailwind")
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Safeguard ─────────────────────────────────────────────────────────
		# Source: Cmd_setsafeguard (battle_script_commands.c L8480-8495): fails if
		#   already up on the caster's own side; else 5-turn timer. Blocks status
		#   infliction AND confusion on the protected side — see
		#   StatusManager.try_apply_status/try_apply_confusion's own Safeguard gate.
		if move.is_safeguard:
			if _side_conditions[attacker_side]["safeguard_turns"] > 0:
				move_effect_failed.emit(attacker, "already_safeguard")
			else:
				_side_conditions[attacker_side]["safeguard_turns"] = 5
				side_condition_set.emit(attacker_side, "safeguard")
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Mist ──────────────────────────────────────────────────────────────
		# Source: Cmd_setmist (battle_script_commands.c L7700-7715): fails if
		#   already up on the caster's own side; else 5-turn timer. Blocks a
		#   stat DECREASE on the protected side — see
		#   `_apply_one_stat_change_pair`'s own Mist gate, checked BEFORE the
		#   Mirror-Armor/ability-block chain, matching source's own
		#   IsMistProtected-first ordering in CanDecreaseStat.
		if move.is_mist:
			if _side_conditions[attacker_side]["mist_turns"] > 0:
				move_effect_failed.emit(attacker, "already_mist")
			else:
				_side_conditions[attacker_side]["mist_turns"] = 5
				side_condition_set.emit(attacker_side, "mist")
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Sticky Web ────────────────────────────────────────────────────────
		# Source: Cmd_setstickyweb (battle_script_commands.c L8691-8707): targets
		#   the OPPONENT's side (same as Spikes/Toxic Spikes/Stealth Rock); single
		#   application (no layers, like Stealth Rock) — fails if already up.
		#   `sticky_web_setter` records the setter for Mirror Armor/Defiant
		#   attribution at switch-in, mirroring source's own `stickyWebBattlerId`.
		if move.is_sticky_web:
			var sw_side: int = 1 - attacker_side
			if _side_conditions[sw_side]["sticky_web"]:
				move_effect_failed.emit(attacker, "sticky_web_already_set")
			else:
				_side_conditions[sw_side]["sticky_web"] = true
				_side_conditions[sw_side]["sticky_web_setter"] = attacker
				hazard_set.emit(sw_side, "sticky_web", 1)
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

		# [M19-ally-targeting-stat-change] Aromatic Mist(597)/Coaching(739) —
		# TARGET_ALLY ONLY, never self, never opponent. Fails entirely if not
		# in doubles or the ally has fainted — matching Helping Hand's own
		# established "not doubles" shape, the only other TARGET_ALLY move
		# this project has (`_get_ally` already returns null for both cases,
		# no separate fainted check needed here). Deliberately dispatched
		# BEFORE the foe_targeting/Magic-Bounce/Substitute/type-immunity
		# block below — none of that applies to an ally-targeting move, the
		# same reasoning Helping Hand's own early-return already established.
		# Reuses `_apply_stat_change_effect` directly, passing the ally in
		# place of `defender` — `stat_change_self` is FALSE for these moves
		# in their own data (matching source's TARGET_ALLY, not TARGET_USER),
		# so the shared per-pair dispatch correctly lands the change on
		# whichever BattlePokemon is passed as the second argument. Coaching's
		# own 2-stat payload (Atk+1, Def+1) reuses the pre-existing
		# `extra_stat_change_stats` multi-stat mechanism (`[Bucket 3
		# multi-stat]`) with zero further changes needed.
		# Source: moves_info.h MOVE_AROMATIC_MIST/MOVE_COACHING: .target = TARGET_ALLY.
		if move.stat_change_target_ally:
			var ally_target: BattlePokemon = _get_ally(attacker)
			if ally_target == null:
				move_effect_failed.emit(attacker, "not_doubles")
			else:
				_apply_stat_change_effect(attacker, ally_target, move, ng_active)
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
		# [D4 bundle] Magic Coat extends this same swap with an OR condition
		# (not a second parallel swap) — confirmed from source
		# (MoveEndBouncedMove) that Magic Bounce and Magic Coat share the
		# literal same bounce dispatch, so reusing this exact swap inherits
		# its already-tested single-non-recursive-bounce guarantee for free,
		# including the Magic-Coat-reflected-onto-a-Magic-Bounce-holder edge
		# case. Cleared immediately on fire so it can't reflect a second
		# status move later the same turn.
		var mc_active: bool = defender.magic_coat_active
		if foe_targeting and move.bounceable \
				and (AbilityManager.bounces_status_move(defender, ng_active, attacker, move) \
						or mc_active):
			move_bounced.emit(defender, attacker)
			if mc_active:
				defender.magic_coat_active = false
				ability_triggered.emit(defender, "magic_coat")
			else:
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
		# [D2 batch 2] A real bug found while building Foresight(193)/Odor
		# Sleuth(316): confirmed via a direct read of BattleScript_
		# EffectForesight (data/battle_scripts_1.s L2165-2174) that its own
		# script never calls `typecalc` anywhere — meaning in the real
		# reference engine this move is NEVER subject to any type-immunity
		# check at all, including against its own primary use case (a
		# Ghost-type target that would otherwise be immune to a Normal-type
		# move). This project's own general gate below was over-generalized
		# to apply to every foe-targeting move with a real type; narrowly
		# exempting `is_foresight` here, matching the existing
		# `corrosion_bypasses_type_gate` precedent's own scoping shape,
		# rather than a blanket change. That entry's own comment flagged as
		# an open question whether any OTHER already-shipped move shares
		# this gap — [D4 bundle 3] resolved it: Purify(648, Poison-type),
		# Nightmare(171, Ghost-type — its own primary use case is a
		# Ghost-vs-Normal-immune target, the exact same shape as Foresight's
		# own bug), and Spite(180, Ghost-type) all confirmed via direct
		# source read to likewise never call `typecalc` in their own
		# scripts. (Memento(262, Dark-type) shares the same gap in
		# principle, but is provably unreachable in practice — no type in
		# this project's own chart is immune to Dark-type moves — so it's
		# deliberately left off this list rather than added for no
		# behavioral effect.)
		# [D4 Bundle 5] Reflect Type(513) — confirmed via direct source read
		# (BattleScript_EffectReflectType, data/battle_scripts_1.s L991-999)
		# that this move's own script never calls `typecalc` either — same
		# exemption shape as Foresight/Purify/Nightmare/Spite just below.
		# [D4 Bundle 6] Toxic Thread(635)/Venom Drench(599) — both share
		# `BattleScript_EffectStatChange` (data/battle_scripts_1.s L75-78:
		# attackcanceler + trymovestatchanges + MoveEnd, no typecalc call),
		# confirmed via source's own test suite (toxic_thread.c: "Toxic
		# Thread still lowers speed if the target can't be Poisoned [a
		# Steel-type]"). That entry flagged, but did not audit, whether the
		# rest of this project's already-shipped EFFECT_STAT_CHANGE-family
		# roster shares the same gap.
		# [EFFECT_STAT_CHANGE audit] Resolved: every move whose real script
		# maps to BattleScript_EffectStatChange (EFFECT_STAT_CHANGE,
		# EFFECT_STAT_CHANGE_ON_STATUS, EFFECT_TOXIC_THREAD, and
		# EFFECT_STAT_CHANGE_MAGNETIC all share that literal script per
		# src/data/battle_move_effects.h) never calls typecalc — confirmed by
		# reading Cmd_trymovestatchanges/DoStatChange directly
		# (battle_script_commands.c L10744-10752, battle_move_resolution.c
		# L4823-4863), neither of which contains any type-effectiveness call.
		# Programmatically derived the full 56-move EFFECT_STAT_CHANGE roster
		# from source, narrowed to the 25 already-implemented, genuinely
		# foe/selected-targeting members (self-targeting moves never reach
		# this gate since foe_targeting = not stat_change_self; Howl/Aromatic
		# Mist/Coaching are ally-targeting and dispatch through a separate,
		# earlier bypass), then cross-checked each move's own type against
		# this project's actual TypeChart.TABLE for a real 0.0x cell. 16 are
		# CONFIRMED AFFECTED (a real 0x matchup exists and the move was
		# reaching this gate unexempted): Sand Attack(28, vs Flying), Tail
		# Whip/Leer/Growl/Screech/Smokescreen/Flash/Scary Face/Sweet Scent/
		# Tickle/Noble Roar/Play Nice/Confide/Tearful Look (all Normal-type,
		# vs Ghost), Eerie Impulse(598, vs Ground), Kinesis(134, vs Dark) —
		# each confirmed to carry only a single, non-probabilistic stat-change
		# additionalEffect (no separate typecalc-requiring secondary), so no
		# genuine per-move exception was found within this batch. New shared
		# MoveData.stat_change_bypasses_type_gate flag (one field for the
		# whole newly-confirmed family, rather than 16 more single-purpose is_*
		# dispatch flags like Foresight/Toxic Thread/etc. carry, since none of
		# these 16 need a dedicated dispatch branch — they already run through
		# the fully generic stat_change_stat/amount mechanism). The remaining 9
		# candidates (String Shot/Cotton Spore/Charm/Feather Dance/Fake Tears/
		# Metal Sound/Baby-Doll Eyes/Decorate/Spicy Extract) share the
		# identical latent gap in principle, but are each provably UNREACHABLE
		# — their own type's row in this project's TypeChart.TABLE contains no
		# 0.0x cell at all — so, matching the established Memento precedent,
		# they are deliberately left unexempted rather than flagged for zero
		# behavioral effect.
		if foe_targeting and move.type != TypeChart.TYPE_NONE \
				and not corrosion_bypasses_type_gate and not move.is_foresight \
				and not move.is_purify and not move.is_nightmare and not move.is_spite \
				and not move.is_reflect_type and not move.is_toxic_thread \
				and not move.is_venom_drench and not move.is_transform \
				and not move.stat_change_bypasses_type_gate:
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

		# ── Reflect Type ──────────────────────────────────────────────────────
		# Source: BS_TryReflectType (battle_script_commands.c L11488-11531) —
		# see MoveData.is_reflect_type's own doc comment for the full
		# citation, including the ability-keyed (not species-keyed)
		# Multitype exclusion and the new `_set_mon_type_array` sibling
		# function. `ignores_substitute=true` in this move's own data
		# already exempted it from the Substitute check above.
		if move.is_reflect_type:
			if AbilityManager.effective_ability_id(defender, ng_active, attacker) \
					== AbilityManager.ABILITY_MULTITYPE:
				move_effect_failed.emit(attacker, "reflect_type_failed")
			else:
				var rt_types: Array = defender.species.types.duplicate()
				_set_mon_type_array(attacker, rt_types)
				types_changed.emit(attacker, rt_types, "reflect_type")
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Strength Sap ──────────────────────────────────────────────────────
		# Source: CheckSpecificMoveCondition/SetStrengthSapHealing
		# (battle_stat_change.c L50-113) — see MoveData.is_strength_sap's own
		# doc comment for the full citation, including the confirmed
		# heal-gated-on-the-lower-succeeding fork (NOT independent — if the
		# TARGET's Attack is already at -6, NEITHER the heal NOR the lower
		# happens). Falls through the shared foe_targeting/Magic-Bounce/
		# Substitute/type-immunity gates above like any ordinary
		# foe-targeting status move (no ignores_substitute flag; no
		# type-immunity exemption needed — Grass has no blanket type-chart
		# immunity).
		if move.is_strength_sap:
			if defender.stat_stages[BattlePokemon.STAGE_ATK] <= -6:
				move_effect_failed.emit(defender, "stat_wont_change")
			else:
				var ss_eff_atk: int = DamageCalculator._apply_stage(
						defender.attack, defender.stat_stages[BattlePokemon.STAGE_ATK])
				if attacker.current_hp < attacker.max_hp:
					attacker.current_hp = min(attacker.max_hp, attacker.current_hp + ss_eff_atk)
					drain_heal.emit(attacker, ss_eff_atk)
				_apply_one_stat_change_pair(attacker, defender, move,
						BattlePokemon.STAGE_ATK, -1, ng_active)
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Topsy-Turvy ───────────────────────────────────────────────────────
		# Source: BattleScript_EffectTopsyTurvy (data/battle_scripts_1.s
		# L1025-1040) / BS_InvertStatStages (battle_script_commands.c
		# L13064-13074) — see MoveData.is_topsy_turvy's own doc comment for
		# the full citation. Falls through the shared foe_targeting/
		# Magic-Bounce/Substitute gates above (no ignores_substitute flag;
		# no type-immunity concern — Dark has no blanket type-chart
		# immunity, matching the Memento precedent).
		if move.is_topsy_turvy:
			if not _invert_stat_stages(defender):
				move_effect_failed.emit(defender, "topsy_turvy_failed")
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Lock-On / Mind Reader ────────────────────────────────────────────
		# Source: Cmd_setalwayshitflag (battle_script_commands.c L8089-8102) —
		# see MoveData.is_lock_on's own doc comment for the full citation.
		# Falls through the shared Substitute/type-immunity gates above like
		# any ordinary foe-targeting status move (no bespoke immunity of its
		# own, unlike Leech Seed/Mean Look).
		if move.is_lock_on:
			if attacker.sure_hit_target != null:
				move_effect_failed.emit(attacker, "lock_on_already_active")
			else:
				attacker.sure_hit_target = defender
				attacker.sure_hit_turns = 2
				sure_hit_set.emit(attacker, defender)
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Foresight / Odor Sleuth ────────────────────────────────────────────
		# Source: BattleScript_EffectForesight (data/battle_scripts_1.s
		# L2165-2174) — see MoveData.is_foresight's own doc comment for the
		# full citation. Falls through the shared Substitute/type-immunity
		# gates above like Lock-On (ignores_substitute=TRUE on this move's
		# own data handles the Substitute bypass at that earlier checkpoint).
		if move.is_foresight:
			if defender.foresight_active:
				move_effect_failed.emit(attacker, "foresight_already_active")
			else:
				defender.foresight_active = true
				foresight_set.emit(defender)
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Telekinesis ───────────────────────────────────────────────────────
		# See MoveData.is_telekinesis's own doc comment for the full citation.
		# Falls through the shared gates above like Lock-On/Foresight.
		if move.is_telekinesis:
			if defender.telekinesis_turns > 0:
				move_effect_failed.emit(attacker, "telekinesis_already_active")
			else:
				defender.telekinesis_turns = 3
				telekinesis_set.emit(defender)
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Octolock ──────────────────────────────────────────────────────────
		# See MoveData.is_octolock's own doc comment for the full citation
		# (including the confirmed-does-NOT-trap finding).
		if move.is_octolock:
			if defender.octolocked_by != null:
				move_effect_failed.emit(attacker, "octolock_already_active")
			else:
				defender.octolocked_by = attacker
				octolock_set.emit(defender, attacker)
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Psycho Shift ──────────────────────────────────────────────────────
		# See MoveData.is_psycho_shift's own doc comment for the full citation.
		if move.is_psycho_shift:
			if attacker.status == BattlePokemon.STATUS_NONE:
				move_effect_failed.emit(attacker, "psycho_shift_no_status")
			elif defender.status != BattlePokemon.STATUS_NONE:
				move_effect_failed.emit(attacker, "psycho_shift_target_has_status")
			else:
				var ps_status: int = attacker.status
				var ps_safeguard: bool = _is_safeguard_active_for(attacker, defender, ng_active)
				if StatusManager.try_apply_status(defender, ps_status, null, null, ng_active,
						attacker, DamageCalculator.WEATHER_NONE, null, false, ps_safeguard):
					secondary_applied.emit(defender, _status_to_se(ps_status))
					_try_synchronize(defender, attacker, ps_status)
					attacker.status = BattlePokemon.STATUS_NONE
				else:
					move_effect_failed.emit(attacker, "psycho_shift_failed")
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Toxic Thread ──────────────────────────────────────────────────────
		# See MoveData.is_toxic_thread's own doc comment for the full citation
		# — poison and the Speed drop are INDEPENDENT; the move only fails if
		# NEITHER does anything.
		if move.is_toxic_thread:
			var tt_safeguard: bool = _is_safeguard_active_for(attacker, defender, ng_active)
			var tt_poisoned: bool = StatusManager.try_apply_status(defender, BattlePokemon.STATUS_POISON,
					null, null, ng_active, attacker, DamageCalculator.WEATHER_NONE, null, false, tt_safeguard)
			if tt_poisoned:
				secondary_applied.emit(defender, MoveData.SE_POISON)
				_try_synchronize(defender, attacker, BattlePokemon.STATUS_POISON)
			var tt_stat_actual: int = _apply_one_stat_change_pair(
					attacker, defender, move, BattlePokemon.STAGE_SPEED, -1, ng_active)
			if not tt_poisoned and tt_stat_actual == 0:
				move_effect_failed.emit(attacker, "toxic_thread_failed")
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Venom Drench ────────────────────────────────────────────────────────
		# See MoveData.is_venom_drench's own doc comment for the full citation
		# — TARGET_BOTH (spread, opponents only), independently gated per
		# opponent on their own current Poison/Toxic status.
		if move.is_venom_drench:
			var vd_any: bool = false
			for vd_opp: BattlePokemon in _get_live_opponents(attacker):
				if vd_opp.status != BattlePokemon.STATUS_POISON and vd_opp.status != BattlePokemon.STATUS_TOXIC:
					continue
				var vd_atk: int = _apply_one_stat_change_pair(
						attacker, vd_opp, move, BattlePokemon.STAGE_ATK, -1, ng_active)
				var vd_spatk: int = _apply_one_stat_change_pair(
						attacker, vd_opp, move, BattlePokemon.STAGE_SPATK, -1, ng_active)
				var vd_speed: int = _apply_one_stat_change_pair(
						attacker, vd_opp, move, BattlePokemon.STAGE_SPEED, -1, ng_active)
				if vd_atk != 0 or vd_spatk != 0 or vd_speed != 0:
					vd_any = true
			if not vd_any:
				move_effect_failed.emit(attacker, "venom_drench_failed")
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Parting Shot ──────────────────────────────────────────────────────
		# See MoveData.is_parting_shot's own doc comment for the full citation
		# — the switch is GATED ON the stat-lower actually landing (Gen7+),
		# the opposite of Memento's independence.
		if move.is_parting_shot:
			var ps2_atk: int = _apply_one_stat_change_pair(
					attacker, defender, move, BattlePokemon.STAGE_ATK, -1, ng_active)
			var ps2_spatk: int = _apply_one_stat_change_pair(
					attacker, defender, move, BattlePokemon.STAGE_SPATK, -1, ng_active)
			if ps2_atk != 0 or ps2_spatk != 0:
				var ps2_party: BattleParty = _parties[attacker_side]
				if ps2_party.has_valid_switch_target():
					var ps2_slot: int = _get_replacement_slot(attacker_idx)
					_do_voluntary_switch(attacker_idx, ps2_slot)
			else:
				move_effect_failed.emit(attacker, "parting_shot_failed")
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# [D4 bundle] Taunt ──────────────────────────────────────────────────
		# Falls through the shared Magic-Bounce/Magic-Coat/Substitute/type-
		# immunity/Prankster gates above like Lock-On/Foresight (this move's
		# own `ignores_substitute = true` handles the Substitute bypass at
		# that earlier checkpoint; `bounceable = true` lets it reach Magic
		# Bounce/Magic Coat above like any other reflectable status move).
		# `aroma_veil_blocks` was already computed generically off
		# `move.blocked_by_aroma_veil` near the top of this branch — reused
		# here directly, not recomputed. See MoveData.is_taunt's own doc
		# comment for the full citation, including the duration formula.
		if move.is_taunt:
			if aroma_veil_blocks:
				move_effect_failed.emit(defender, "aroma_veil_blocked")
				ability_triggered.emit(defender, "aroma_veil")
			elif AbilityManager.effective_ability_id(defender, ng_active, attacker) \
					== AbilityManager.ABILITY_OBLIVIOUS:
				move_effect_failed.emit(defender, "oblivious_blocks")
				ability_triggered.emit(defender, "oblivious")
			elif defender.taunt_turns > 0:
				move_effect_failed.emit(defender, "taunt_failed")
			else:
				var taunt_turn_pos: int = _turn_order.find(defender)
				var taunt_has_acted: bool = taunt_turn_pos >= 0 \
						and taunt_turn_pos <= _current_actor_index
				defender.taunt_turns = 4 if taunt_has_acted else 3
				taunted.emit(defender, defender.taunt_turns)
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Tar Shot ──────────────────────────────────────────────────────────
		# Source: battle_stat_change.c :: case EFFECT_TAR_SHOT (L165-173) —
		# see MoveData.is_tar_shot's own doc comment for the full citation.
		# Confirmed an ALL-OR-NOTHING gate, not "skip the flag but still drop
		# Speed": source bundles the flag-set and the -1 Speed as ONE single
		# `additionalEffects` entry (`st->additionalEffectTriggers` gates the
		# WHOLE move's success, traced to `StatChangeCanAnyChange`,
		# battle_move_resolution.c L4522-4549 — `MOVE_RESULT_ATTEMPT_STAT_
		# CHANGE` only if `additionalEffectTriggers` is true) — an already-
		# tar-shot'd target blocks the Speed drop too, not just the
		# already-set flag.
		if move.is_tar_shot:
			if defender.tar_shot_active:
				move_effect_failed.emit(attacker, "tar_shot_already_active")
			else:
				defender.tar_shot_active = true
				tar_shot_set.emit(defender)
				_apply_stat_change_effect(attacker, defender, move, ng_active)
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Swagger / Flatter ────────────────────────────────────────────────
		# Source: battle_stat_change.c :: case EFFECT_SWAGGER (L147-156) — see
		# MoveData.is_swagger's own doc comment for the full citation and the
		# real correction found at Step 0 (Own Tempo blocks the ENTIRE move,
		# not just the confusion — checked here BEFORE either half, rather
		# than relying on try_apply_confusion's own independent Own-Tempo
		# gate, which alone would still let the stat raise through).
		if move.is_swagger:
			if AbilityManager.effective_ability_id(defender, ng_active, attacker) \
					== AbilityManager.ABILITY_OWN_TEMPO:
				move_effect_failed.emit(defender, "own_tempo_prevents")
				ability_triggered.emit(defender, "own_tempo")
			else:
				# Reuses _apply_one_stat_change_pair (not a raw apply_stat_change
				# call) so Opportunist/Mirror Herb's own "opponent's stat rose"
				# reactive triggers still fire correctly for Swagger's raise,
				# exactly as they would for any other foe-targeting stat-raise.
				_apply_one_stat_change_pair(attacker, defender, move,
						move.stat_change_stat, move.stat_change_amount, ng_active)
				if StatusManager.try_apply_confusion(defender, null, ng_active, attacker, move):
					secondary_applied.emit(defender, MoveData.SE_CONFUSION)
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Trick / Switcheroo ─────────────────────────────────────────────────
		# Source: battle_script_commands.c :: Cmd_tryswapitems (L8874-8930) —
		# see MoveData.is_trick's own doc comment for the full citation,
		# including the Multitype-Plate exclusion and the Sticky-Hold-on-
		# target-only scoping. Falls through the shared foe-targeting/
		# Substitute/type-immunity gates above like any ordinary status move
		# (this move does NOT carry ignoresSubstitute, unlike Foresight/Tar
		# Shot just above).
		# [Multitype-Plate fix] Re-derived directly against source's own 4
		# `CanBattlerGetOrLoseItem` calls (not just the 2 this project originally
		# implemented) — each side must be checked against BOTH losing its own item
		# AND gaining the other's, via the shared `AbilityManager.is_form_locked_by_item`.
		# A Multitype holder with no Plate currently held can still block a Trick that
		# would hand it a foreign Plate — a real, source-confirmed case the original
		# 2-check version missed. See decisions.md for the full derivation.
		if move.is_trick:
			var trick_both_itemless: bool = \
					attacker.held_item == null and defender.held_item == null
			var trick_blocked: bool = \
					AbilityManager.is_form_locked_by_item(attacker, attacker.held_item, ng_active) \
					or AbilityManager.is_form_locked_by_item(attacker, defender.held_item, ng_active) \
					or AbilityManager.is_form_locked_by_item(defender, defender.held_item, ng_active) \
					or AbilityManager.is_form_locked_by_item(defender, attacker.held_item, ng_active)
			if trick_both_itemless or trick_blocked:
				move_effect_failed.emit(attacker, "trick_failed")
			elif AbilityManager.effective_ability_id(defender, ng_active, attacker) \
					== AbilityManager.ABILITY_STICKY_HOLD:
				move_effect_failed.emit(attacker, "sticky_hold_prevents")
				ability_triggered.emit(defender, "sticky_hold")
			else:
				var trick_old_atk_item: ItemData = attacker.held_item
				attacker.held_item = defender.held_item
				defender.held_item = trick_old_atk_item
				items_swapped.emit(attacker, defender)
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Role Play / Skill Swap / Worry Seed / Heart Swap ──────────────────
		# Source: see MoveData.is_role_play/is_skill_swap/overwrite_target_
		# ability_id/is_heart_swap's own doc comments for full citations. All
		# 4 fall through the shared foe_targeting/Magic-Bounce/Substitute/
		# type-immunity/Prankster gates above like any ordinary foe-targeting
		# status move — `ignores_substitute`/`ignores_protect`/`bounceable`
		# per-move data flags (set individually, confirmed non-uniform within
		# this family at Step 0) already make each move's own real exemptions
		# take effect at the correct earlier checkpoint.
		if move.is_role_play:
			if AbilityManager.try_role_play(attacker, defender):
				ability_changed.emit(attacker, attacker.ability.ability_id)
			else:
				move_effect_failed.emit(attacker, "role_play_failed")
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		if move.is_skill_swap:
			if AbilityManager.try_skill_swap(attacker, defender):
				ability_changed.emit(attacker, attacker.ability.ability_id)
				ability_changed.emit(defender, defender.ability.ability_id)
			else:
				move_effect_failed.emit(attacker, "skill_swap_failed")
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		if move.overwrite_target_ability_id >= 0:
			if AbilityManager.try_worry_seed_overwrite(defender, move.overwrite_target_ability_id):
				ability_changed.emit(defender, defender.ability.ability_id)
			else:
				move_effect_failed.emit(defender, "overwrite_ability_failed")
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		if move.is_heart_swap:
			var hs_attacker_stages: Array = attacker.stat_stages.duplicate()
			attacker.stat_stages = defender.stat_stages.duplicate()
			defender.stat_stages = hs_attacker_stages
			stat_changes_copied.emit(attacker, defender)
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Mimic / Sketch ─────────────────────────────────────────────────
		# Source: Cmd_mimicattackcopy (battle_script_commands.c L7843-7879) /
		# Cmd_copymovepermanently (L8101-8144) — see MoveData.is_mimic/
		# is_sketch's own doc comments for the full citation. Both reuse
		# `defender.last_move_used` directly for "the target's last move"
		# (confirmed equivalent to source's gLastMoves/gLastPrintedMoves for
		# every scenario this project can produce).
		if move.is_mimic:
			var mimic_slot: int = attacker.moves.find(move)
			var mimic_target: MoveData = defender.last_move_used
			var mimic_ok: bool = (mimic_slot >= 0 and mimic_target != null
					and (mimic_target.ban_flags & MoveData.BAN_MIMIC) == 0
					and not attacker.moves.has(mimic_target)
					and not attacker.transformed)
			if mimic_ok:
				attacker.mimicked_slot = mimic_slot
				attacker.mimicked_original_move = move
				attacker.mimicked_original_pp = attacker.current_pp[mimic_slot]
				attacker.moves[mimic_slot] = mimic_target
				attacker.current_pp[mimic_slot] = min(mimic_target.pp, 5)
				move_learned.emit(attacker, mimic_slot, mimic_target)
			else:
				move_effect_failed.emit(attacker, "mimic_failed")
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		if move.is_sketch:
			var sketch_slot: int = attacker.moves.find(move)
			var sketch_target: MoveData = defender.last_move_used
			var sketch_already_known := false
			for _si in range(attacker.moves.size()):
				if attacker.moves[_si].is_sketch:
					continue
				if attacker.moves[_si] == sketch_target:
					sketch_already_known = true
					break
			var sketch_ok: bool = (sketch_slot >= 0 and sketch_target != null
					and (sketch_target.ban_flags & MoveData.BAN_SKETCH) == 0
					and not sketch_already_known
					and not attacker.transformed)
			if sketch_ok:
				attacker.moves[sketch_slot] = sketch_target
				attacker.current_pp[sketch_slot] = sketch_target.pp
				move_learned.emit(attacker, sketch_slot, sketch_target)
			else:
				move_effect_failed.emit(attacker, "sketch_failed")
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		# ── Transform ─────────────────────────────────────────────────────
		# Source: Cmd_transformdataexecution (battle_script_commands.c
		# L7747-7823) — see MoveData.is_transform's own doc comment for the
		# full citation of every field copied/excluded and every design
		# decision behind the snapshot/restore shape (species duplicate-and-
		# substitute for the shared-Resource hazard, raw ability copy not
		# effective_ability_id, times_hit's deliberate permanence, etc.).
		if move.is_transform:
			var xform_fail: bool = (defender.semi_invulnerable != MoveData.SEMI_INV_NONE
					or defender.transformed
					or attacker.transformed
					or (defender.substitute_hp > 0 and not move.ignores_substitute))
			if xform_fail:
				move_effect_failed.emit(attacker, "transform_failed")
			else:
				attacker.transformed = true
				# [M19.5 Task 2] If the attacker has an ACTIVE Mimic overlay
				# (mimicked_slot >= 0 — it used Mimic earlier this same
				# stint and hasn't switched out since), restore that slot
				# back to Mimic itself FIRST, before snapshotting. Without
				# this, pre_transform_moves would capture the temporarily-
				# mimicked move (e.g. "Water Gun") rather than Mimic, and
				# clearing mimicked_slot below would then permanently lose
				# the only record that a restore-to-Mimic was ever owed —
				# on a later switch-out+in, _reset_mon_mimicked_move would
				# no-op (mimicked_slot already -1) and _reset_mon_transform
				# would restore the moveset to the wrongly-snapshotted
				# mimicked move instead of Mimic. Source avoids this by
				# construction (Mimic and Transform are both ephemeral
				# mutations of the same temp struct, discarded wholesale via
				# a fresh party-record re-derivation on switch-in) — this
				# project's own per-mechanic snapshot fields need this one
				# explicit ordering fix to compose correctly when Mimic sits
				# underneath Transform on the same mon.
				if attacker.mimicked_slot >= 0:
					_reset_mon_mimicked_move(attacker)
				# Cast-time snapshot — NOT construction-time, since PP is
				# consumed as the battle progresses (see BattlePokemon
				# .pre_transform_moves's own doc comment).
				attacker.pre_transform_moves = attacker.moves.duplicate()
				attacker.pre_transform_pp = attacker.current_pp.duplicate()
				# Source explicitly resets these 3 attacker-own trackers on
				# a successful Transform (disabledMove/disableTimer/
				# mimickedMoves/usedMoves).
				attacker.disabled_move = null
				attacker.disable_turns = 0
				attacker.mimicked_slot = -1
				attacker.mimicked_original_move = null
				attacker.mimicked_original_pp = 0
				for _ui in range(attacker.used_move_slots.size()):
					attacker.used_move_slots[_ui] = false
				# Species: duplicate-and-substitute, NOT a bare reference —
				# sharing the actual Resource object would let a later
				# type-mutating ability/move on the transformed attacker
				# (Color Change/Conversion/Protean/etc.) corrupt the REAL
				# target's own species.types in place via
				# _set_mon_type/_set_mon_type_array's existing in-place
				# mutation. Matches the established Normalize/Hidden Power/
				# Foul Play/Body Press/Photon Geyser shallow-duplicate
				# pattern, plus this codebase's own established paranoia of
				# explicitly re-duplicating the nested `types` array rather
				# than trusting Resource.duplicate() alone (same as
				# original_types/Roost/Reflect Type).
				var xform_species: PokemonSpecies = defender.species.duplicate()
				xform_species.types = defender.species.types.duplicate()
				attacker.species = xform_species
				# Computed stats — confirmed via source's own struct field
				# order to be the TARGET's calculated attack/defense/speed/
				# spAttack/spDefense values, NOT hp/maxHP/level/friendship
				# (all sit after the copied byte range in source's struct).
				attacker.attack = defender.attack
				attacker.defense = defender.defense
				attacker.sp_attack = defender.sp_attack
				attacker.sp_defense = defender.sp_defense
				attacker.speed = defender.speed
				# Stat stages ARE within the copied byte range in source —
				# confirmed, not assumed. No dedicated reset is needed for
				# this project's own copy: _switch_out_clear already
				# unconditionally zeroes every mon's stat_stages on
				# switch-out regardless of cause.
				attacker.stat_stages = defender.stat_stages.duplicate()
				# RAW reference copy through the normal setter — NOT
				# AbilityManager.effective_ability_id. Copying a
				# Neutralizing-Gas-suppressed/resolved-to-none value would
				# be permanently wrong once NG later left the field;
				# suppression correctly re-applies on every future read via
				# the normal accessor, same as every other battler.
				attacker.ability = defender.ability
				# Moves: container copy only — sharing the actual MoveData
				# Resource references is safe (nothing in this codebase
				# ever mutates a MoveData Resource in place).
				attacker.moves = defender.moves.duplicate()
				var xform_pp: Array[int] = []
				for _mi in range(attacker.moves.size()):
					xform_pp.append(min(attacker.moves[_mi].pp, 5))
				attacker.current_pp = xform_pp
				# Explicit special-case copy in source, separate from the
				# general struct-copy — writes into the attacker's own
				# PERSISTENT record with no restoration anywhere, so this
				# is correctly PERMANENT (not restored on switch-out, unlike
				# every other field above). Confirmed source behavior, not
				# a bug to fix.
				attacker.times_hit = defender.times_hit
				pokemon_transformed.emit(attacker, defender)
			move_executed.emit(attacker, defender, move, 0)
			_current_actor_index += 1
			_set_phase(BattlePhase.FAINT_CHECK)
			return

		if move.stat_change_stat >= 0:
			# [M19-secondary-stat-on-hit]: extracted into _apply_stat_change_effect
			# (below) so the new damage-move secondary-stat-change dispatch in
			# _do_damaging_hit can reuse the exact same Mirror Armor / Defiant-
			# Competitive / Opportunist / Mirror Herb logic rather than re-deriving
			# it. Behavior of this call site is unchanged — see that function's own
			# doc comment for the original per-mechanism source citations.
			_apply_stat_change_effect(attacker, defender, move, ng_active)
			# [M19-ally-targeting-stat-change] Howl(336) — TARGET_USER_AND_ALLY
			# at this project's GEN_LATEST config: the self half above is an
			# ordinary self-buff (stat_change_self=True, already correctly
			# handled by the general dispatch); this bolts on the SAME stat
			# change to the user's own ally too, a genuine no-op in singles
			# (_get_ally returns null there) and the only difference from a
			# plain self-buff move in doubles.
			# Source: moves_info.h MOVE_HOWL: .target = B_UPDATED_MOVE_DATA
			#   >= GEN_8 ? TARGET_USER_AND_ALLY : TARGET_USER.
			if move.also_boosts_ally:
				var howl_ally: BattlePokemon = _get_ally(attacker)
				if howl_ally != null:
					var ally_actual: int = StatusManager.apply_stat_change(
							howl_ally, move.stat_change_stat, move.stat_change_amount,
							null, ng_active, attacker)
					if ally_actual != 0:
						stat_stage_changed.emit(howl_ally, move.stat_change_stat, ally_actual)
		elif move.secondary_effect != MoveData.SE_NONE:
			var applied: bool = StatusManager.try_secondary_effect(attacker, defender, move, null, ng_active, _effective_weather(), _is_uproar_active(), null, _is_safeguard_active_for(attacker, defender, ng_active))
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
	# [D1 easy bundle] Consume Stomping Tantrum's own generic failure flag —
	# read-then-reset here, the one universal point every action's
	# resolution (success or failure, from any of `_phase_move_execution`'s
	# dozens of early-return paths) always reaches next. Gating on
	# `_current_action_failed` itself guarantees this specific
	# `_phase_faint_check` call is the one immediately following a move-
	# execution call (the flag is reset to false at the start of every
	# `_phase_move_execution`, and consumed exactly once here), so
	# `_turn_order[_current_actor_index - 1]` safely identifies whoever
	# just acted rather than risking a stale read from some other phase
	# (e.g. end-of-turn status damage) that also transitions to FAINT_CHECK.
	if _current_action_failed:
		_current_action_failed = false
		var st_actor_pos: int = _current_actor_index - 1
		if st_actor_pos >= 0 and st_actor_pos < _turn_order.size():
			var st_mover: BattlePokemon = _turn_order[st_actor_pos]
			if not st_mover.fainted:
				st_mover.stomping_tantrum_timer = 2

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
			# [D4 Bundle 7] Grudge — capture BEFORE _clear_volatiles wipes it,
			# same reasoning as had_destiny_bond just above.
			var had_grudge: bool = combatant.grudge_active
			combatant.fainted = true
			# Clear ALL volatiles on faint.
			# Source: FaintClearSetData in battle_main.c clears gBattleMons[].volatiles.
			_clear_volatiles(combatant)
			pokemon_fainted.emit(combatant)
			_award_exp_for_fainted_opponent(combatant)
			# [D3 turn-order/event-tracker batch] Retaliate — set the FAINTED
			# mon's own side's timer to 2 (side-wide, never the opposing side).
			# See MoveData.is_retaliate's own doc comment for full source citations.
			var _rt_faint_side: int = _combatants.find(combatant) / _active_per_side
			_retaliate_timer[_rt_faint_side] = 2
			# M17b: Moxie — Attack +1 for whoever's hit caused this faint.
			# Source: battle_util.c L4467-4472; killer lookup reuses M14b's _last_attacker.
			var moxie_killer: BattlePokemon = _last_attacker.get(combatant, null)
			var moxie_actual: int = AbilityManager.moxie_boost(moxie_killer, _is_neutralizing_gas_active())
			if moxie_actual != 0:
				stat_stage_changed.emit(moxie_killer, BattlePokemon.STAGE_ATK, moxie_actual)
				ability_triggered.emit(moxie_killer, "moxie")
			# [D4 CHEAP bundle] Fell Stinger — Attack +3 for whoever's move JUST
			# KO'd this mon, at the same killer-lookup chokepoint Moxie uses
			# above, but keyed on the KILLING MOVE (_last_attacker_move) rather
			# than the killer's ability. Already-maxed Attack is a natural
			# no-op via apply_stat_change's own clamp. See MoveData.
			# is_fell_stinger's own doc comment for the full source citation.
			var fs_killer_move: MoveData = _last_attacker_move.get(combatant, null)
			if fs_killer_move != null and fs_killer_move.is_fell_stinger and moxie_killer != null:
				var fs_actual: int = StatusManager.apply_stat_change(
						moxie_killer, BattlePokemon.STAGE_ATK, 3, null, _is_neutralizing_gas_active())
				if fs_actual != 0:
					stat_stage_changed.emit(moxie_killer, BattlePokemon.STAGE_ATK, fs_actual)
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
					_award_exp_for_fainted_opponent(killer)

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
					_award_exp_for_fainted_opponent(retal_killer)

			# [D4 Bundle 7] Grudge — reuses the SAME retal_killer/retal_move
			# lookup Aftermath/Innards Out just used above (FAINT_BLOCK_DO_
			# GRUDGE, battle_move_resolution.c L2931-2949): if the fainted
			# mon had cast Grudge, drains the killer's own move (the exact
			# slot used) to 0 PP. Excludes an ally kill, Struggle, and
			# Future Sight/Doom Desire (the shared is_future_sight flag) —
			# see MoveData.is_grudge's own doc comment for the full citation.
			if had_grudge and retal_killer != null and not retal_killer.fainted \
					and retal_move != null and not retal_move.is_struggle \
					and not retal_move.is_future_sight:
				var grudge_same_side: bool = _combatants.find(combatant) / _active_per_side \
						== _combatants.find(retal_killer) / _active_per_side
				if not grudge_same_side:
					var grudge_slot: int = retal_killer.moves.find(retal_move)
					if grudge_slot >= 0 and grudge_slot < retal_killer.current_pp.size():
						retal_killer.current_pp[grudge_slot] = 0
						pp_drained.emit(retal_killer, retal_move)

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

	# ── [D4 Bundle 5] Mud Sport / Water Sport — FIELD-WIDE 5-turn countdown ──
	# Source: HandleEndTurnMudSport/HandleEndTurnWaterSport (battle_end_turn.c
	# L1184-1198) — see the `_mud_sport_turns`/`_water_sport_turns` fields'
	# own doc comment for the full citation.
	if _mud_sport_turns > 0:
		_mud_sport_turns -= 1
	if _water_sport_turns > 0:
		_water_sport_turns -= 1

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
					_award_exp_for_fainted_opponent(mon)

	# ── [D4 CHEAP bundle] Aqua Ring / Ingrain end-of-turn self-heal
	# (ENDTURN_AQUA_RING=1557, ENDTURN_INGRAIN=1558 in source's own handler
	# table — both BEFORE ENDTURN_LEECH_SEED=1559, matching this insertion
	# point) ───────────────────────────────────────────────────────────────
	# Source: battle_end_turn.c :: HandleEndTurnAquaRing (L438-455) /
	#   HandleEndTurnIngrain (L457-474) — the literal same maxHP/16 formula,
	#   Big-Root-boosted, gated on not already at max HP. Magic Guard has no
	#   interaction here (a heal, not indirect damage) — confirmed from
	#   source (neither function checks it), matching Leftovers' own
	#   precedent.
	for mon: BattlePokemon in _combatants:
		if mon.fainted or mon.current_hp >= mon.max_hp:
			continue
		if not (mon.aqua_ring_active or mon.ingrain_active):
			continue
		var ring_heal: int = ItemManager.big_root_drain_heal(mon, mon.max_hp / 16, ng_active)
		mon.current_hp = min(mon.max_hp, mon.current_hp + ring_heal)
		ring_heal_tick.emit(mon, ring_heal)

	# ── [D0] Leech Seed drain (ENDTURN_LEECH_SEED=11, BEFORE Poison/Burn=12/13
	# in source's own handler table) ──────────────────────────────────────────
	# Source: HandleEndTurnLeechSeed (battle_end_turn.c L476-509). Drain amount
	# is maxHP/8 of the SEEDED battler (`mon` here), Magic-Guard-blocked on the
	# SEEDED battler (skips the whole tick, no damage AND no heal). Big Root
	# (a real correction to [M18q]'s own "move-drain only" scope note — see
	# MoveData.is_leech_seed's doc comment) boosts the SEEDER's heal; Liquid
	# Ooze is checked on the SEEDED battler and inverts the SEEDER's heal into
	# damage of the identical amount if present (the drained mon's own ability
	# protecting itself, the same shape Giga Drain's own Liquid Ooze check
	# already established). Both seeder and seeded must still be present —
	# already guaranteed by _clear_volatiles' own reciprocal clear (a fainted/
	# switched-out seeder's leftover victims are cleared the instant it leaves).
	for mon: BattlePokemon in _turn_order:
		if mon.fainted or mon.leeched_by == null:
			continue
		var seeder: BattlePokemon = mon.leeched_by
		if seeder.fainted:
			continue
		if AbilityManager.blocks_indirect_damage(mon, ng_active):
			continue
		var seed_drain: int = max(1, mon.max_hp / 8)
		mon.current_hp = max(0, mon.current_hp - seed_drain)
		var seed_heal: int = ItemManager.big_root_drain_heal(seeder, seed_drain, ng_active)
		if AbilityManager.inverts_drain(mon, ng_active):
			seeder.current_hp = max(0, seeder.current_hp - seed_heal)
		else:
			seeder.current_hp = min(seeder.max_hp, seeder.current_hp + seed_heal)
		leech_seed_drained.emit(mon, seeder, seed_heal)
		if mon.current_hp == 0:
			mon.fainted = true
			pokemon_fainted.emit(mon)
			_award_exp_for_fainted_opponent(mon)

	# ── [D1] Lock-On / Mind Reader — 2-tick countdown ─────────────────────────
	# Source: battle_end_turn.c L68-69: `if (lockOn > 0 && --lockOn == 0)
	# battlerWithSureHit = 0`. Cleared after exactly one full extra turn.
	for mon: BattlePokemon in _turn_order:
		if mon.sure_hit_target != null:
			mon.sure_hit_turns -= 1
			if mon.sure_hit_turns <= 0:
				mon.sure_hit_target = null
				mon.sure_hit_turns = 0

	# ── [D4 CHEAP bundle] Magnet Rise — 5-turn countdown ──────────────────────
	# Source: battle_end_turn.c :: HandleEndTurnMagnetRise (L848-855):
	#   `if (magnetRiseTimer > 0 && --magnetRiseTimer == 0) volatiles.magnetRise = FALSE`.
	for mon: BattlePokemon in _turn_order:
		if mon.magnet_rise_turns > 0:
			mon.magnet_rise_turns -= 1

	# ── [D4 Bundle 5] Roost — restore the pre-mutation type snapshot at the
	# END of the SAME turn it was used (HandleEndTurnRoost, battle_end_turn.c
	# L1005-1013) — see BattlePokemon.roost_active's own doc comment for the
	# full mutate-and-restore design rationale.
	for mon: BattlePokemon in _turn_order:
		if mon.roost_active:
			_set_mon_type_array(mon, mon.roost_pre_types)
			types_changed.emit(mon, mon.roost_pre_types, "roost_restore")
			mon.roost_active = false
			mon.roost_pre_types = []

	# ── [D4 Bundle 5] Laser Focus — flat, UNCONDITIONAL 2-turn countdown,
	# decremented regardless of whether the holder even attacked this turn.
	# Source: battle_end_turn.c L74-75.
	for mon: BattlePokemon in _turn_order:
		if mon.laser_focus_turns > 0:
			mon.laser_focus_turns -= 1

	# ── [D4 Bundle 6] Telekinesis — 3-turn countdown, same shape as Magnet
	# Rise above. Source: battle_end_turn.c :: HandleEndTurnTelekinesis.
	for mon: BattlePokemon in _turn_order:
		if mon.telekinesis_turns > 0:
			mon.telekinesis_turns -= 1

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
				_award_exp_for_fainted_opponent(mon)
		elif dmg < 0:
			# M17d: Poison Heal — negative return means heal, not damage.
			mon.current_hp = min(mon.max_hp, mon.current_hp - dmg)
			ability_healed.emit(mon, -dmg)
			ability_triggered.emit(mon, "poison_heal")

	# ── [D4 bundle 3] Nightmare recurring damage (ENDTURN_NIGHTMARE, right
	# before ENDTURN_WRAP in source's own handler table) ──────────────────────
	# Source: HandleEndTurnNightmare (battle_end_turn.c L610-633). Sleep
	# status is RE-CHECKED every turn (not just at application) — if the
	# target has woken up or lost Comatose, this silently clears with no
	# damage that turn rather than re-attempting. Magic Guard blocks the
	# damage (indirect-damage class).
	for mon: BattlePokemon in _turn_order:
		if mon.fainted or not mon.nightmare_active:
			continue
		var nm_still_asleep: bool = mon.status == BattlePokemon.STATUS_SLEEP \
				or AbilityManager.effective_ability_id(mon, ng_active) == AbilityManager.ABILITY_COMATOSE
		if not nm_still_asleep:
			mon.nightmare_active = false
			continue
		if AbilityManager.blocks_indirect_damage(mon, ng_active):
			continue
		var nm_dmg: int = max(1, mon.max_hp / 4)
		mon.current_hp = max(0, mon.current_hp - nm_dmg)
		nightmare_damage.emit(mon, nm_dmg)
		if mon.current_hp == 0:
			mon.fainted = true
			pokemon_fainted.emit(mon)
			_award_exp_for_fainted_opponent(mon)

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
			_award_exp_for_fainted_opponent(mon)

	# ── [D4 Bundle 6] Octolock — recurring -1 Def/-1 Sp. Defense tick,
	# positioned right after Wrap (source: battle_end_turn.c's own handler
	# table has ENDTURN_OCTOLOCK immediately after ENDTURN_WRAP/ENDTURN_
	# SALT_CURE) and gated on the target still being alive — matters
	# observably here, unlike Magnet Rise/Roost/Laser Focus/Telekinesis's own
	# pure decrements above, since a mon that fainted from poison/burn/wrap
	# this same tick must not also take the Octolock stat-lower.
	# Source: HandleEndTurnOctolock (battle_end_turn.c L715-724).
	for mon: BattlePokemon in _turn_order:
		if mon.fainted or mon.octolocked_by == null:
			continue
		var ol_def: int = StatusManager.apply_stat_change(mon, BattlePokemon.STAGE_DEF, -1, null, ng_active)
		if ol_def != 0:
			stat_stage_changed.emit(mon, BattlePokemon.STAGE_DEF, ol_def)
		var ol_spdef: int = StatusManager.apply_stat_change(mon, BattlePokemon.STAGE_SPDEF, -1, null, ng_active)
		if ol_spdef != 0:
			stat_stage_changed.emit(mon, BattlePokemon.STAGE_SPDEF, ol_spdef)

	# [D4 Bundle 7] Curse (Ghost-type user's half) — recurring maxHP/4 tick
	# on the cursed mon, Magic-Guard-gated. No back-reference to the caster
	# to check (see BattlePokemon.cursed's own doc comment for why this is
	# simpler than Leech Seed's shape). Source: HandleEndTurnCurse
	# (battle_end_turn.c L635-650).
	for mon: BattlePokemon in _turn_order:
		if mon.fainted or not mon.cursed or AbilityManager.blocks_indirect_damage(mon, ng_active):
			continue
		var curse_tick_dmg: int = mon.max_hp / 4
		mon.current_hp = max(0, mon.current_hp - curse_tick_dmg)
		curse_damage.emit(mon, curse_tick_dmg)
		if mon.current_hp == 0:
			mon.fainted = true
			pokemon_fainted.emit(mon)
			_award_exp_for_fainted_opponent(mon)

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
				_award_exp_for_fainted_opponent(mon)

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
				_award_exp_for_fainted_opponent(mon)

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
		# [Bucket 4 cheapest singles] Throat Chop: same decrement shape as
		# Disable/Encore above. Source: battle_end_turn.c L61-63/L1280-1311.
		if mon.throat_chop_turns > 0:
			mon.throat_chop_turns -= 1
		# [D4 bundle] Taunt: same decrement shape as Disable/Encore/Throat
		# Chop above — confirmed individually that source's own decrement
		# site (battle_end_turn.c L762) lives in this same file/category,
		# not the separate per-battler-action-reset site
		# stomping_tantrum_timer/_retaliate_timer needed.
		if mon.taunt_turns > 0:
			mon.taunt_turns -= 1
		# [Delayed-effect family] Yawn: same decrement shape as the above,
		# but hitting 0 triggers a completely fresh sleep-infliction
		# attempt (all immunity checks re-derived at THIS moment, not
		# locked in at cast time) via the existing status pipeline. See
		# MoveData.is_yawn's own doc comment for full source citations.
		if mon.yawn_turns > 0:
			mon.yawn_turns -= 1
			if mon.yawn_turns == 0:
				if StatusManager.try_apply_status(mon, BattlePokemon.STATUS_SLEEP,
						null, _get_ally(mon), ng_active, null, _effective_weather(), null,
						_is_uproar_active()):
					secondary_applied.emit(mon, MoveData.SE_SLEEP)
		# [Perish Song] Checked BEFORE decrementing (matching the exact
		# off-by-one shape source's own HandleEndTurnPerishSong uses,
		# battle_end_turn.c L979-996): a timer of 3 ticks 3→2→1→0 across 3
		# end-of-turn passes (message-only in source, no state change here
		# beyond the decrement itself), then the 4th pass — timer already
		# 0 — deals the fatal blow. Damage is a direct HP-zero, the same
		# shape Self-Destruct/Explosion already use, not a real damage-calc
		# call (source: `SetPassiveDamageAmount(battler, hp)`, i.e. exactly
		# the holder's own current HP).
		if mon.perish_song_active:
			if mon.perish_song_timer <= 0:
				mon.perish_song_active = false
				mon.current_hp = 0
				mon.fainted = true
				pokemon_fainted.emit(mon)
				_award_exp_for_fainted_opponent(mon)
			else:
				mon.perish_song_timer -= 1

	# [Delayed-effect family] Future Sight / Doom Desire — decrement each
	# pending slot's counter once per turn; resolve (via the normal
	# _do_damaging_hit chokepoint) against whoever occupies that slot when
	# it hits 0. See MoveData.is_future_sight's own doc comment for full
	# source citations.
	for fs_target_idx: int in _future_sight_pending.keys().duplicate():
		var fs_entry: Dictionary = _future_sight_pending[fs_target_idx]
		fs_entry["counter"] -= 1
		if fs_entry["counter"] <= 0:
			_future_sight_pending.erase(fs_target_idx)
			if fs_target_idx < 0 or fs_target_idx >= _combatants.size():
				continue
			var fs_target: BattlePokemon = _combatants[fs_target_idx]
			if fs_target.fainted:
				continue
			var fs_caster: BattlePokemon = fs_entry["caster"]
			var fs_move: MoveData = fs_entry["move"]
			var fs_damage: int = _do_damaging_hit(fs_caster, fs_target, fs_move)
			future_sight_resolved.emit(fs_caster, fs_target, fs_move, fs_damage)

	# [Delayed-effect family] Wish — decrement each pending slot's counter
	# once per turn; resolve (a flat heal, caster's own max HP / 2) against
	# whoever occupies the CASTER's OWN slot when it hits 0. See
	# MoveData.is_wish's own doc comment for full source citations.
	for wish_slot_idx: int in _wish_pending.keys().duplicate():
		var wish_entry: Dictionary = _wish_pending[wish_slot_idx]
		wish_entry["counter"] -= 1
		if wish_entry["counter"] <= 0:
			_wish_pending.erase(wish_slot_idx)
			if wish_slot_idx < 0 or wish_slot_idx >= _combatants.size():
				continue
			var wish_recipient: BattlePokemon = _combatants[wish_slot_idx]
			if wish_recipient.fainted:
				continue
			var wish_caster: BattlePokemon = wish_entry["caster"]
			var wish_heal: int = wish_caster.max_hp / 2
			var wish_actual: int = 0
			if wish_recipient.current_hp < wish_recipient.max_hp:
				wish_actual = min(wish_heal, wish_recipient.max_hp - wish_recipient.current_hp)
				wish_recipient.current_hp += wish_actual
			wish_resolved.emit(wish_recipient, wish_actual)

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
		# [D4 Bundle 4] Tailwind/Safeguard/Mist — same decrement shape as the
		# screens above, just a different side-status bit/timer in source.
		if sc["tailwind_turns"] > 0:
			sc["tailwind_turns"] -= 1
			if sc["tailwind_turns"] == 0:
				side_condition_expired.emit(side, "tailwind")
		if sc["safeguard_turns"] > 0:
			sc["safeguard_turns"] -= 1
			if sc["safeguard_turns"] == 0:
				side_condition_expired.emit(side, "safeguard")
		if sc["mist_turns"] > 0:
			sc["mist_turns"] -= 1
			if sc["mist_turns"] == 0:
				side_condition_expired.emit(side, "mist")

	# [D1 easy bundle] Retaliate's own decrement was MOVED to
	# `_phase_priority_resolution` (a bug fix — see that site's own doc
	# comment for the full writeup); it no longer lives here.

	# [D3 turn-order/event-tracker batch] Echoed Voice: increment (capped 4)
	# if used this turn, else reset to 0. Source: battle_end_turn.c L79-88.
	if _echoed_voice_used_this_turn:
		if _echoed_voice_counter < 4:
			_echoed_voice_counter += 1
		_echoed_voice_used_this_turn = false
	else:
		_echoed_voice_counter = 0

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


# [D4 Bundle 4] Safeguard — is `defender`'s side protected against a status/
# confusion infliction from `attacker` right now? Source: IsSafeguardProtected
# (battle_util.c L5224-5231): protected if the side's SIDE_STATUS_SAFEGUARD is
# up, UNLESS the attacker is on a DIFFERENT side and holds Infiltrator (an
# ally-inflicted status — including self — is still protected, since source's
# own ally-check short-circuits to "protected" before the Infiltrator check
# is ever reached).
func _is_safeguard_active_for(attacker: BattlePokemon, defender: BattlePokemon, ng_active: bool) -> bool:
	var def_idx: int = _actor_indices.get(defender, _combatants.find(defender))
	var def_side: int = def_idx / _active_per_side
	if _side_conditions[def_side]["safeguard_turns"] <= 0:
		return false
	var atk_idx: int = _actor_indices.get(attacker, _combatants.find(attacker))
	var atk_side: int = atk_idx / _active_per_side
	if atk_side != def_side and AbilityManager.bypasses_infiltrator_barriers(attacker, ng_active):
		return false
	return true


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


# [M20] Resets ONE opponent field slot's tracked participant list to whichever
# PLAYER combatants are CURRENTLY active — called whenever a new opponent
# occupies that slot (switch-in, forced switch-in, faint replacement, Baton
# Pass). Mirrors source's OpponentSwitchInResetSentPokesToOpponentValue
# (battle_util.c:1207-1222).
func _reset_exp_participants_for_opponent_slot(field_slot: int) -> void:
	while _exp_participants.size() <= field_slot:
		_exp_participants.append([])
	_exp_participants[field_slot] = _parties[0].active_indices.duplicate()


# [M20] Adds a PLAYER party index to EVERY currently-tracked opponent field
# slot's participant list — called whenever any player mon switches in.
# Mirrors source's UpdateSentPokesToOpponentValue's player-switch branch
# (battle_util.c:1224-1234): a new player combatant becomes a participant
# against EVERY opponent currently on the field, not just one flank.
func _add_exp_participant(player_party_index: int) -> void:
	for f in range(_exp_participants.size()):
		if not _exp_participants[f].has(player_party_index):
			_exp_participants[f].append(player_party_index)


# [M20] I.1: Gen VII+ base per-recipient Exp value (source-verified — see
# docs/decisions.md's `[M20 EXP design]` entry for the full citation trail),
# then I.2 (custom participant-count distribution %) and I.4 (Difficulty
# Setting %) applied as two further truncating integer multiplies, in that
# exact order (base -> distribution -> difficulty). B carries zero modifiers
# this session (Lucky Egg/Traded/Affection/Exp Charm/unevolved-bonus all
# confirmed unbuilt in this project — see the recon's own I.1 writeup).
func _compute_exp_award(fainted: BattlePokemon, recipient: BattlePokemon,
		participant_count: int) -> int:
	var fainted_level: int = fainted.level
	var b: int = (fainted.species.exp_yield * fainted_level) / 5
	var max_index: int = EXP_SCALING_FACTORS.size() - 1
	var a_index: int = clampi(fainted_level * 2 + 10, 0, max_index)
	var c_index: int = clampi(fainted_level + recipient.level + 10, 0, max_index)
	var value: int = (b * EXP_SCALING_FACTORS[a_index]) / EXP_SCALING_FACTORS[c_index]
	value += 1
	var dist_pct: int = DISTRIBUTION_PERCENT.get(participant_count, DISTRIBUTION_PERCENT[6])
	value = (value * dist_pct) / 100
	var diff_pct: int = DIFFICULTY_PERCENT.get(difficulty_mode, 100)
	value = (value * diff_pct) / 100
	return value


# [M20] Awards Exp to every currently-alive tracked participant when an
# OPPONENT-side (side 1) Pokémon faints — mirrors source's
# `IsOnPlayerSide(gBattlerFainted)` gate in Cmd_getexp (a player-side faint
# never awards Exp; a no-op here by construction since `side != 1` returns
# early). Eligibility is Section G1's two-layer rule: tracked in
# `_exp_participants[field_slot]` (ever active against this specific
# opponent instance) AND alive right now (`current_hp > 0` — this project's
# own standing convention is to check current_hp directly rather than
# `.fainted` for a synchronous within-function aliveness check, since
# `.fainted` is only set later in a separate phase for some callers).
# Called from every `pokemon_fainted.emit(...)` site in this file.
func _award_exp_for_fainted_opponent(fainted: BattlePokemon) -> void:
	var idx: int = _combatants.find(fainted)
	if idx < 0:
		return
	var side: int = idx / _active_per_side
	if side != 1:
		return
	var field_slot: int = idx % _active_per_side
	if field_slot >= _exp_participants.size():
		return
	var player_party: BattleParty = _parties[0]
	var alive_participants: Array = []
	for party_idx in _exp_participants[field_slot]:
		var member: BattlePokemon = player_party.members[party_idx]
		if member.current_hp > 0:
			alive_participants.append(member)
	if alive_participants.is_empty():
		return
	var participant_count: int = alive_participants.size()
	for recipient: BattlePokemon in alive_participants:
		var amount: int = _compute_exp_award(fainted, recipient, participant_count)
		recipient.current_exp += amount
		exp_gained.emit(recipient, amount)
		_check_level_up(recipient)
		# [M20c] EV-gain reuses this exact same `alive_participants` set —
		# confirmed via direct source trace (`Cmd_getexp`, battle_script_
		# commands.c:3887-3900) that the true recipient candidate list
		# (IsValidForBattle AND sent-in-or-Exp-Share) is built ONCE per
		# fainted-opponent event and is IDENTICAL for both Exp and EV
		# grants — source's "max-level mon still gets EVs but 0 Exp"
		# behavior is a difference in OUTPUT VALUE for one specific
		# recipient category, not a different INPUT SET. This project's
		# own Exp dispatch has no max-level special case at all (a
		# level-100 recipient still receives a (harmless) Exp award,
		# per `[M20b]`'s own `_check_level_up` early-return), so there is
		# no divergence to reconcile here in practice either — no
		# separate EV-eligible tracking exists or is needed.
		_grant_evs(recipient, fainted.species)


# [M20c] Grants EVs to one recipient from the fainted opponent's species —
# mirrors source's real MonGainEVs (pokemon.c:5049-5152) exactly: base
# ev_yield_X (Pokerus's x2 multiplier is permanently excluded — no
# infrastructure exists for it, matching the Rare-Candy/level-cap
# out-of-scope precedent) -> Power Item +8 to its one specific targeted
# stat (POWER_ITEM_EV_BONUS, checked BEFORE Macho Brace) -> Macho Brace x2
# of the (possibly-already-boosted) total -> clamp against remaining TOTAL
# cap room (EV_CAP_TOTAL=510) -> clamp against remaining PER-STAT cap room
# (EV_CAP_PER_STAT=252) -> add. No participant-count distribution applies
# (confirmed doubly from source — MonGainEVs takes no participant-count
# parameter at all) — full base yield per eligible recipient, unlike Exp's
# own custom distribution table.
#
# Iterates in THIS PROJECT'S OWN STAT_* order (HP=0/ATK=1/DEF=2/SPATK=3/
# SPDEF=4/SPEED=5), NOT a transcription of source's raw `enum Stat` loop
# order (which places Speed before SpAtk/SpDef) — matters for which stat
# gets shortchanged once the total cap is nearly hit, since the loop
# breaks ENTIRELY the instant total EVs reach the cap (no partial credit
# to remaining stats that same event, matching source's own early `break`).
#
# Confirmed and worth noting for future test-writing: granting EVs here
# does NOT retroactively change `recipient`'s current battle stats unless
# a level-up ALSO fires this same event (`_check_level_up`, called just
# above, is the only thing that ever calls `_calculate_stats()`) — matches
# source exactly (stats only recompute at level-up/switch-in, never on a
# bare EV change).
func _grant_evs(recipient: BattlePokemon, fainted_species: PokemonSpecies) -> void:
	var yields: Array[int] = [
		fainted_species.ev_yield_hp, fainted_species.ev_yield_atk,
		fainted_species.ev_yield_def, fainted_species.ev_yield_spa,
		fainted_species.ev_yield_spd, fainted_species.ev_yield_spe,
	]
	var total_evs: int = 0
	for v in recipient.evs:
		total_evs += v
	var item: ItemData = ItemManager.effective_held_item(recipient, _is_neutralizing_gas_active())
	for stat_idx in range(6):
		if total_evs >= EV_CAP_TOTAL:
			break
		var increase: int = yields[stat_idx]
		if item != null and item.hold_effect == ItemManager.HOLD_EFFECT_POWER_ITEM \
				and item.ev_boost_stat == stat_idx:
			increase += POWER_ITEM_EV_BONUS
		if item != null and item.hold_effect == ItemManager.HOLD_EFFECT_MACHO_BRACE:
			increase *= 2
		if total_evs + increase > EV_CAP_TOTAL:
			increase = EV_CAP_TOTAL - total_evs
		if recipient.evs[stat_idx] + increase > EV_CAP_PER_STAT:
			increase = EV_CAP_PER_STAT - recipient.evs[stat_idx]
		if increase <= 0:
			continue
		recipient.evs[stat_idx] += increase
		total_evs += increase
		ev_gained.emit(recipient, stat_idx, increase)


# [M20b] Derives the recipient's new level from its (now-updated) current_exp
# total via a fresh re-scan of the growth-rate curve — mirroring source's real
# GetLevelFromMonExp (pokemon.c:1466-1476), which is a monotonic re-derivation
# from the total, NOT an increment-and-check-once loop. This means a single
# large Exp award that crosses several level thresholds at once is handled
# correctly in one pass, exactly like source. Growth rate and learnset are
# both read FRESH from PokemonRegistry by the recipient's CURRENT
# species.national_dex_num every time (never cached on the instance) — see
# docs/m20_recon.md's M20b Section 4 for why this matters: it keeps this path
# automatically safe for a future evolution mechanic (M26) without any
# rework, since there's no stale species/learnset snapshot anywhere to
# invalidate.
#
# For each level actually crossed: snapshot old_max_hp -> mutate level ->
# recompute stats via the pre-existing, already-correct `_calculate_stats()`
# -> apply the HP delta exactly as source does (`CalculateMonStats`,
# pokemon.c:1429-1448): a flat ADDITIVE increase to current_hp equal to
# however much max_hp just went up, clamped to the new max — not a
# proportional heal, not a full heal, not left untouched. Then attempts to
# learn every learnset entry at that exact level (a single level can teach
# more than one move — e.g. Bulbasaur's own level 15 entry teaches both
# Poison Powder and Sleep Powder — each processed independently in learnset
# order, matching source's own per-level move-learning loop).
func _check_level_up(recipient: BattlePokemon) -> void:
	if recipient.species == null or recipient.level >= 100:
		return
	var dex: int = recipient.species.national_dex_num
	var species_data: Dictionary = PokemonRegistry.get_species(dex)
	var growth_rate: String = species_data.get("growth_rate", "")
	var new_level: int = recipient.level
	while new_level < 100 \
			and PokemonRegistry.get_exp_for_level(growth_rate, new_level + 1) > 0 \
			and PokemonRegistry.get_exp_for_level(growth_rate, new_level + 1) <= recipient.current_exp:
		new_level += 1
	if new_level <= recipient.level:
		return
	var learnset: Array = PokemonRegistry.get_learnset(dex)
	for lvl in range(recipient.level + 1, new_level + 1):
		var old_max_hp: int = recipient.max_hp
		recipient.level = lvl
		recipient._calculate_stats()
		if recipient.max_hp > old_max_hp:
			recipient.current_hp += (recipient.max_hp - old_max_hp)
		if recipient.current_hp > recipient.max_hp:
			recipient.current_hp = recipient.max_hp
		level_up.emit(recipient, lvl)
		for entry: Dictionary in learnset:
			if int(entry.get("level", -1)) == lvl:
				_try_learn_move_at_level(recipient, int(entry.get("move_id", -1)))


# [M20b] Mirrors source's 3-way MonTryLearningNewMove branch
# (Cmd_handlelearnnewmove, battle_script_commands.c:5553-5615): already known
# -> no-op; fewer than 4 moves known -> auto-learn into the next open slot;
# already at 4 moves -> source runs a real yes/no + replace-which-slot player
# prompt this project has no UI for yet (M23 is still ahead), so the default
# is auto-skip (move_learn_skipped fires, nothing changes) UNLESS
# `_force_move_replacement_slot` is set (0-3), which forces that specific
# slot to be overwritten instead — see that var's own doc comment.
func _try_learn_move_at_level(recipient: BattlePokemon, move_id: int) -> void:
	if move_id <= 0:
		return
	var candidate: MoveData = MoveRegistry.get_move(move_id)
	if candidate == null:
		return
	if recipient.moves.has(candidate):
		return
	if recipient.moves.size() < 4:
		recipient.add_move(candidate)
		move_learned.emit(recipient, recipient.moves.size() - 1, candidate)
		return
	if _force_move_replacement_slot != null:
		var slot: int = clampi(int(_force_move_replacement_slot), 0, 3)
		recipient.replace_move(slot, candidate)
		move_learned.emit(recipient, slot, candidate)
	else:
		move_learn_skipped.emit(recipient, candidate)


# M17g: whether Neutralizing Gas is active anywhere on the field right now — checked
# across ALL live combatants (both sides), unlike _get_live_opponents (one side only),
# since Neutralizing Gas suppresses field-wide including the holder's own side.
func _is_neutralizing_gas_active() -> bool:
	return AbilityManager.is_neutralizing_gas_active(_combatants)


# [M19-rampage] whether Uproar's lock is active on ANY live combatant right now —
# field-wide (both sides), same shape as _is_neutralizing_gas_active above.
# Source: UproarWakeUpCheck (battle_script_commands.c L7130-7149) scans
# `i < gBattlersCount`, not just one side.
func _is_uproar_active() -> bool:
	for mon in _combatants:
		if not mon.fainted and mon.uproar_turns > 0:
			return true
	return false


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


# [M19e] Morning Sun/Synthesis/Moonlight/Shore Up's shared weather-conditional
# heal amount. Source: Cmd_recoverbasedonsunlight (battle_script_commands.c
# L8622-8689), the B_TIME_OF_DAY_HEALING_MOVES != GEN_2 branch (this project's
# GEN_LATEST config always takes this branch, never the Gen-2 time-of-day one).
func _weather_heal_amount(mon: BattlePokemon, move: MoveData, ng_active: bool) -> int:
	var eff_weather: int = _effective_weather()
	if move.weather_heal_has_quarter_branch \
			and ItemManager.blocks_weather_modifier(mon, ng_active) \
			and eff_weather in [WEATHER_SUN, WEATHER_RAIN]:
		# Source: GetAttackerWeather's own Utility Umbrella branch strips SUN
		# and RAIN specifically (`weather & ~(SUN|RAIN)`), never Sandstorm/
		# Hail — only relevant to the 3 sun-based moves; Shore Up's own
		# branch never references Umbrella at all.
		eff_weather = WEATHER_NONE
	if eff_weather == move.weather_heal_boost_type:
		return max(1, mon.max_hp * 2 / 3)
	if not move.weather_heal_has_quarter_branch:
		# Shore Up: no 1/4 branch exists at all — anything other than its own
		# boost weather (Sandstorm) falls straight to the plain 1/2 heal.
		return max(1, mon.max_hp / 2)
	if eff_weather == WEATHER_NONE or eff_weather == DamageCalculator.WEATHER_STRONG_WINDS:
		# Source: healingWeather = attackerWeather & ~B_WEATHER_STRONG_WINDS,
		# stripped BEFORE the "!(healingWeather & ANY)" check — Strong Winds
		# (Delta Stream) is treated as "no weather" for this formula
		# specifically, distinct from Rain/Sandstorm/Hail below.
		return max(1, mon.max_hp / 2)
	return max(1, mon.max_hp / 4)


# [Bucket 4 cheapest singles]/[D0] Resets ALL 7 of mon's stat stages to
# exactly 0 — an absolute reset, not a relative stat_change_amount delta.
# Extracted from Clear Smog's own original inline implementation so Haze
# (D0) and Freezy Frost's on-hit secondary can reuse it verbatim, looped
# over every combatant instead of one target. No-ops (including no signal)
# if every stat was already 0, matching source's own pre-check exactly.
func _reset_stat_stages(mon: BattlePokemon) -> void:
	var any_nonzero: bool = false
	for i in range(mon.stat_stages.size()):
		if mon.stat_stages[i] != 0:
			any_nonzero = true
			break
	if not any_nonzero:
		return
	for i in range(mon.stat_stages.size()):
		if mon.stat_stages[i] != 0:
			var delta: int = -mon.stat_stages[i]
			mon.stat_stages[i] = 0
			stat_stage_changed.emit(mon, i, delta)


# [D4 Bundle 5] Topsy-Turvy(576) — inverts the SIGN of every one of mon's
# current stat stages (`new = -old`, cleanly symmetric at both +6/-6 caps —
# BS_InvertStatStages, battle_script_commands.c L13064-13074). Returns
# whether ANY stat was actually inverted, matching source's own fail
# condition exactly: fails ONLY if all 7 stats (this project's own 7-entry
# stat_stages array — Atk/Def/SpAtk/SpDef/Speed/Accuracy/Evasion) are
# already at stage 0 (BattleScript_EffectTopsyTurvy, data/
# battle_scripts_1.s L1025-1040 — succeeds if even ONE is non-neutral).
func _invert_stat_stages(mon: BattlePokemon) -> bool:
	var any_nonzero: bool = false
	for i in range(mon.stat_stages.size()):
		if mon.stat_stages[i] != 0:
			any_nonzero = true
			break
	if not any_nonzero:
		return false
	for i in range(mon.stat_stages.size()):
		if mon.stat_stages[i] != 0:
			var new_stage: int = -mon.stat_stages[i]
			var delta: int = new_stage - mon.stat_stages[i]
			mon.stat_stages[i] = new_stage
			stat_stage_changed.emit(mon, i, delta)
	return true


# [D2 batch] Clears EVERY hazard type on one side at once (Spikes/Toxic
# Spikes/Stealth Rock) — used by Defog/Tidy Up, both of which clear
# everything clearable in a single move use, unlike Rapid Spin/Mortal Spin's
# own one-hazard-at-a-time clear (`is_rapid_spin`, `[M16d]`). Emits
# `hazards_cleared` once per hazard type actually present, matching Rapid
# Spin's own per-type signal shape.
func _clear_all_hazards(side: int) -> void:
	var sc: Dictionary = _side_conditions[side]
	if sc["spikes_layers"] > 0:
		sc["spikes_layers"] = 0
		hazards_cleared.emit(side, "spikes")
	if sc["toxic_spikes_layers"] > 0:
		sc["toxic_spikes_layers"] = 0
		hazards_cleared.emit(side, "toxic_spikes")
	if sc["stealth_rock"]:
		sc["stealth_rock"] = false
		hazards_cleared.emit(side, "stealth_rock")


# [D0] Heal Bell(215)/Aromatherapy(312)/Sparkly Swirl(687)'s shared
# party-wide status cure. Source: Cmd_healpartystatus (battle_script_commands.c
# L8259-8340) — cures EVERY real party member's status1, not just the
# active battler. A REAL, confirmed asymmetry at this project's GEN_LATEST
# config (B_HEAL_BELL_SOUNDPROOF >= GEN_8, "in Gen9 it always affects the
# user"): the healer ITSELF and every OTHER party member (bench mons) are
# cured UNCONDITIONALLY, bypassing Soundproof entirely — but the healer's
# DOUBLES PARTNER specifically stays gated by ITS OWN Soundproof, and only
# for a sound move (Heal Bell; Aromatherapy/Sparkly Swirl are not sound
# moves, so `is_sound_move=false` for both never blocks the partner
# either). `healer` may be the user of a pure-status Heal Bell/Aromatherapy
# (attacker == healer) or Sparkly Swirl's own attacker (damage dealt to an
# opponent, but the cure applies to the ATTACKER's own party regardless).
func _apply_heal_bell(healer: BattlePokemon, is_sound_move: bool, ng_active: bool) -> void:
	var idx: int = _combatants.find(healer)
	if idx < 0:
		return
	var side: int = idx / _active_per_side
	var party: BattleParty = _parties[side]
	var partner: BattlePokemon = _get_ally(healer)
	for member: BattlePokemon in party.members:
		if member == partner and member != healer:
			if is_sound_move and AbilityManager.effective_ability_id(member, ng_active) \
					== AbilityManager.ABILITY_SOUNDPROOF:
				continue
		if member.status != BattlePokemon.STATUS_NONE:
			member.status = BattlePokemon.STATUS_NONE
			party_status_cured.emit(member)


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
				_award_exp_for_fainted_opponent(new_mon)

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
				_award_exp_for_fainted_opponent(new_mon)

	# [D4 Bundle 4] Sticky Web — grounded-only (like Spikes), gated by Heavy
	# Duty Boots, but deliberately NOT Magic Guard (this is a stat-stage
	# drop, not indirect damage — Magic Guard's own scope never covers stat
	# changes). Applies via the FULL stat-change pipeline
	# (`_apply_one_stat_change_pair`, via a throwaway foe-targeted MoveData)
	# so Mist/Defiant/Competitive/Mirror Armor/Opportunist/Mirror Herb all
	# react exactly as they would to a move-inflicted drop — source confirms
	# this switch-in effect dispatches through the ordinary `SetStatChange`+
	# battle-script stat-buff pipeline, not a raw hazard tick (see
	# MoveData.is_sticky_web's own doc comment for the full citation).
	# Source: battle_switch_in.c L328-333.
	if not new_mon.fainted and sc["sticky_web"] and grounded and not hazard_immune:
		var sw_dummy_move := MoveData.new()
		sw_dummy_move.stat_change_self = false
		_apply_one_stat_change_pair(sc["sticky_web_setter"], new_mon, sw_dummy_move,
				BattlePokemon.STAGE_SPEED, -1, ng_active)


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


# [Delayed-effect family] Healing Wish / Lunar Dance — consumes a stored
# one-shot heal(+cure, +full-PP for Lunar Dance) on the combatant slot's
# NEXT switch-in, by any method. A disclosed simplification confirmed
# with Rob: always consumes on this very switch-in regardless of whether
# the recipient needed it (real source at Gen8+ config lets it persist
# until a later switch-in actually benefits). See MoveData.is_healing_wish's
# own doc comment for full source citations.
func _apply_stored_healing_effect(new_mon: BattlePokemon, combatant_idx: int) -> void:
	if not _stored_healing_effect.has(combatant_idx):
		return
	var kind: String = _stored_healing_effect[combatant_idx]
	_stored_healing_effect.erase(combatant_idx)
	var healed: int = 0
	if new_mon.current_hp < new_mon.max_hp:
		healed = new_mon.max_hp - new_mon.current_hp
		new_mon.current_hp = new_mon.max_hp
	var cured: bool = new_mon.status != BattlePokemon.STATUS_NONE
	new_mon.status = BattlePokemon.STATUS_NONE
	var pp_restored: bool = false
	if kind == "lunar_dance":
		for i in range(new_mon.current_pp.size()):
			if new_mon.current_pp[i] < new_mon.moves[i].pp:
				pp_restored = true
			new_mon.current_pp[i] = new_mon.moves[i].pp
	healing_wish_activated.emit(new_mon, kind, healed, cured, pp_restored)


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


# [Charge-cancellation fix] Shared core of Sky Drop's reciprocal target-release.
# Used from two call sites with different confuse-after-drop behavior:
#   1. _clear_volatiles' attacker-faint/switch-out case (apply_confuse_after_drop=
#      true) — matches source's dedicated Cmd_tryconfusionafterskydrop
#      (battle_script_commands.c L10707-10740), called only from the BS_FAINTED
#      script path (data/battle_scripts_1.s L2733).
#   2. The new pre-move-check-triggered release in _phase_pre_move_checks
#      (Truant/Flinch/Paralysis/Infatuation on the attacker's own release turn;
#      apply_confuse_after_drop=false) — source has no equivalent path for this
#      trigger at all (a confirmed soft-lock, not silently ported here), and
#      HandleSkyDropResult's own NORMAL "second turn" success branch
#      (battle_move_resolution.c L1678-1694) never checks confuseAfterDrop
#      either — confirmed via direct read that this flag is faint-specific, not
#      a general "target released" consequence, so it must NOT fire from this
#      second call site.
func _release_sky_drop_target(mon: BattlePokemon, apply_confuse_after_drop: bool) -> void:
	var held: BattlePokemon = mon.sky_drop_target
	mon.sky_drop_target = null
	if held == null:
		return
	if held.semi_invulnerable == MoveData.SEMI_INV_SKY_DROP_TARGET:
		held.semi_invulnerable = MoveData.SEMI_INV_NONE
		if apply_confuse_after_drop and held.confuse_after_drop:
			held.confuse_after_drop = false
			if StatusManager.try_apply_confusion(held):
				secondary_applied.emit(held, MoveData.SE_CONFUSION)


# Clear all volatile fields on a Pokémon (faint or switch-out, non-BP).
# Source: FaintClearSetData / SwitchInClearSetData (battle_main.c L3266, L3117)
func _clear_volatiles(mon: BattlePokemon) -> void:
	mon.confusion_turns = 0
	mon.flinched = false
	mon.charging_move = null
	# [M19-rampage] Cleared unconditionally on faint/switch-out, same as
	# charging_move — source's CancelMultiTurnMoves is called at every faint/
	# switch site, mirrored here by _clear_volatiles' own existing call sites.
	mon.locked_move = null
	mon.rampage_turns = 0
	mon.uproar_turns = 0
	mon.semi_invulnerable = MoveData.SEMI_INV_NONE
	mon.substitute_hp = 0
	mon.protect_active = false
	mon.protect_method = BattlePokemon.PROTECT_METHOD_NONE
	mon.endure_active = false
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
	# [M19-recharge] Cleared unconditionally on faint/switch-out — source's
	# rechargeTimer lives in the same bulk-memset Volatiles struct as every
	# other field cleared in this function.
	mon.must_recharge = false
	mon.used_protean_libero = false
	# M17n-7: unburden_active/cud_chew_armed live in source's `volatiles` struct
	# (cleared on switch), unlike last_consumed_berry below, which is deliberately
	# party-state-scoped and NOT touched here — see BattlePokemon's own doc comments.
	mon.unburden_active = false
	mon.cud_chew_armed = false
	# [Bucket 4 cheapest singles] Rage/Throat Chop — both live in source's
	# `volatiles` struct, cleared here like every other switch-scoped volatile.
	mon.rage_active = false
	mon.throat_chop_turns = 0
	# [D4 bundle] Taunt/Magic Coat — same switch-cleared shape as
	# throat_chop_turns/disable_turns above and protect_active earlier in
	# this function, respectively.
	mon.taunt_turns = 0
	mon.magic_coat_active = false
	# [Delayed-effect family] Yawn's own 2-turn counter — same switch-cleared
	# shape as throat_chop_turns/disable_turns above.
	mon.yawn_turns = 0
	# [D1 easy bundle] Stomping Tantrum's own counter — source itself clears
	# this exact state on switch-out (battle_main.c L3214), same shape as
	# throat_chop_turns/yawn_turns above.
	mon.stomping_tantrum_timer = 0
	# [D4 Bundle 4] Stockpile family — all three live in source's per-battler
	# `volatiles` struct, cleared here like every other switch-scoped field.
	mon.stockpile_count = 0
	mon.stockpile_def_added = 0
	mon.stockpile_spdef_added = 0
	# [D2 batch 2] Tar Shot/Foresight — both permanent per-mon volatiles
	# (no turn counter), cleared on switch-out like every other
	# `volatiles`-struct field here.
	mon.tar_shot_active = false
	mon.foresight_active = false
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

	# [M19f] Mean Look/Block/Spider Web/Spirit Shackle's escape-prevention trap —
	# the THIRD move-based trapping source using this exact reciprocal-clear
	# shape (source: battle_main.c L3128-3129/L3139-3140/L3279-3280 — the same
	# two switch-out/faint functions [M18.5d-3]/[M18.5f] already unified into
	# this one chokepoint, literally the next lines after wrapped's own clear
	# in real source). No turn counter to reset (escape_prevented_by has none —
	# unlike wrapped_by, this trap is permanent until cleared, not time-limited).
	mon.escape_prevented_by = null
	for other: BattlePokemon in _combatants:
		if other != mon and other.escape_prevented_by == mon:
			other.escape_prevented_by = null

	# [D0] Leech Seed — the FOURTH move-based volatile using this exact
	# reciprocal-clear shape (source: battle_main.c's own leechSeed clear sits
	# in the identical two switch-out/faint functions [M18.5d-3]/[M18.5f]/
	# [M19f] already unified into this one chokepoint). `mon.leeched_by` is
	# who seeded `mon` (mon's own half, cured on mon's own departure); the
	# scan below is the reciprocal half — every OTHER battler `mon` had
	# seeded stops draining to `mon` once `mon` itself leaves the field, since
	# there's no one left to drain TO.
	mon.leeched_by = null
	for other: BattlePokemon in _combatants:
		if other != mon and other.leeched_by == mon:
			other.leeched_by = null

	# [D1] Lock-On/Mind Reader — the FIFTH move/ability-based volatile using
	# this reciprocal-clear shape, and the first held on the SOURCE side of
	# the relationship (`sure_hit_target` lives on the ATTACKER, pointing at
	# its guaranteed-hit victim) rather than the victim side. `mon`'s own
	# departure clears its own outgoing lock (base case, mirrors
	# charging_move/etc. just above); the scan below is the reciprocal half —
	# any OTHER battler's lock ONTO `mon` is meaningless once `mon` itself
	# leaves the field. Source: battle_main.c L3131-3132/L3277-3278.
	mon.sure_hit_target = null
	mon.sure_hit_turns = 0
	for other: BattlePokemon in _combatants:
		if other != mon and other.sure_hit_target == mon:
			other.sure_hit_target = null
			other.sure_hit_turns = 0

	# [D4 CHEAP bundle] Torment/Magnet Rise/Smack Down/Ingrain/Aqua Ring — all
	# five live in source's same bulk-memset `volatiles` struct, cleared here
	# like every other switch-scoped field above. None of the five need a
	# reciprocal cross-battler scan (all self-contained per-mon state, unlike
	# wrapped_by/escape_prevented_by/leeched_by/sure_hit_target just above).
	mon.tormented = false
	mon.magnet_rise_turns = 0
	mon.smack_down_active = false
	mon.ingrain_active = false
	mon.aqua_ring_active = false
	# [D4 bundle 3] Nightmare — same switch-scoped shape as the five above.
	# last_used_item is deliberately NOT reset here — see its own doc
	# comment (persists across switches, matching last_consumed_berry's
	# established precedent).
	mon.nightmare_active = false
	# [D4 Bundle 5] Roost/Charge/Laser Focus/Fury Cutter — all four live in
	# source's same bulk-memset `volatiles` struct, cleared here like every
	# other switch-scoped field above. None need a reciprocal cross-battler
	# scan (all self-contained per-mon state).
	mon.roost_active = false
	mon.roost_pre_types = []
	mon.charged = false
	mon.laser_focus_turns = 0
	mon.fury_cutter_counter = 0

	# [D4 Bundle 6] Telekinesis/No Retreat — self-contained per-mon state,
	# same switch-scoped shape as the block above (no reciprocal scan needed).
	mon.telekinesis_turns = 0
	mon.no_retreat_active = false

	# [D4 Bundle 6] Octolock — the SIXTH move-based volatile using the
	# reciprocal-clear shape (source: CanBattlerEscape's own doc comment on
	# `is_octolock` notwithstanding, `octolockedBy` still lives in the same
	# bulk-cleared struct source clears on switch-out/faint, battle_main.c
	# L3173-3174/L3287-3288). `mon.octolocked_by` is who octolocked `mon`
	# (mon's own half); the scan below stops any OTHER battler `mon` had
	# octolocked once `mon` itself leaves the field.
	mon.octolocked_by = null
	for other: BattlePokemon in _combatants:
		if other != mon and other.octolocked_by == mon:
			other.octolocked_by = null

	# [D4 Bundle 7] Curse/Grudge — self-contained per-mon state, same
	# switch-scoped shape as the D4-Bundle-5/6 blocks above (no reciprocal
	# scan needed — Curse's own tick has no back-reference to the caster).
	mon.cursed = false
	mon.grudge_active = false
	# [D4 Bundle 7] Last Resort — per-switch-in-stint tracker, reset to an
	# all-false array sized to this mon's own move count (see
	# BattlePokemon.used_move_slots' own doc comment for the source citation
	# confirming this resets on switch-out, unlike times_hit).
	mon.used_move_slots = []
	for _i in range(mon.moves.size()):
		mon.used_move_slots.append(false)
	# [D4 Bundle 8] Imprison — self-contained per-mon state, same
	# switch-scoped shape as No Retreat's own permanent flag.
	mon.imprison_active = false

	# [D4 Bundle 9] Sky Drop — `confuse_after_drop` is self-contained per-mon
	# state (no reciprocal scan needed for it specifically). `sky_drop_target`
	# is the SEVENTH move-based volatile using the reciprocal-clear shape, but
	# in the SOURCE direction (mirrors sure_hit_target's own direction, not
	# wrapped_by/octolocked_by's victim direction): if `mon` itself is
	# currently holding a target aloft and leaves the field (faints) before
	# releasing it, that target must be freed immediately — source's
	# dedicated `Cmd_tryconfusionafterskydrop` (battle_script_commands.c
	# L10710-10740), not the generic per-battler faint/switch cleanup. This
	# is the reciprocal half of the relationship the base clear above already
	# handles for `mon`'s OWN semi_invulnerable (covers `mon` itself being the
	# one released, whichever side of the hold it was on) — this block
	# additionally frees whoever `mon` was holding.
	mon.confuse_after_drop = false
	_release_sky_drop_target(mon, true)


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
	mon.last_hit_was_special = false
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
	_reset_mon_species(new_mon)
	_reset_mon_stats(new_mon)
	_reset_mon_type(new_mon)
	_reset_mon_ability(new_mon)
	_reset_mon_mimicked_move(new_mon)
	_reset_mon_transform(new_mon)
	# [M20] Exp-participant tracking: a player switch-in adds to every tracked
	# opponent's participant list; an opponent switch-in resets its own slot.
	if side == 0:
		_add_exp_participant(slot)
	else:
		_reset_exp_participants_for_opponent_slot(field_slot)
	pokemon_switched_out.emit(old_mon, side)
	pokemon_switched_in.emit(new_mon, side, slot)
	# Switch-in hazards then abilities fire for the incoming Pokémon.
	# Source: AbilityBattleEffects(ABILITYEFFECT_ON_SWITCHIN, ...) (battle_util.c L2960)
	_apply_switch_in_hazards(new_mon, side)
	_apply_switch_in_abilities(new_mon, side)
	_apply_stored_healing_effect(new_mon, combatant_idx)


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
	_reset_mon_species(new_mon)
	_reset_mon_stats(new_mon)
	_reset_mon_type(new_mon)
	_reset_mon_ability(new_mon)
	_reset_mon_mimicked_move(new_mon)
	_reset_mon_transform(new_mon)
	# [M20] Exp-participant tracking — see _do_voluntary_switch's own comment.
	if side == 0:
		_add_exp_participant(slot)
	else:
		_reset_exp_participants_for_opponent_slot(field_slot)
	# Switch-in hazards then abilities fire for the forced-in Pokémon.
	_apply_switch_in_hazards(new_mon, side)
	_apply_switch_in_abilities(new_mon, side)
	_apply_stored_healing_effect(new_mon, combatant_idx)


# M9/M14a: switch-in after faint (no switch-out clear; old mon already cleared on faint).
# M14a: takes combatant_idx so doubles can replace either field slot independently.
func _do_switch_in(combatant_idx: int, slot: int) -> void:
	var side: int = combatant_idx / _active_per_side
	var field_slot: int = combatant_idx % _active_per_side
	_parties[side].active_indices[field_slot] = slot
	_combatants[combatant_idx] = _parties[side].get_active_at(field_slot)
	var new_mon: BattlePokemon = _combatants[combatant_idx]
	new_mon.switched_in_this_turn = true
	_reset_mon_species(new_mon)
	_reset_mon_stats(new_mon)
	_reset_mon_type(new_mon)
	_reset_mon_ability(new_mon)
	_reset_mon_mimicked_move(new_mon)
	_reset_mon_transform(new_mon)
	# [M20] Exp-participant tracking — see _do_voluntary_switch's own comment.
	if side == 0:
		_add_exp_participant(slot)
	else:
		_reset_exp_participants_for_opponent_slot(field_slot)
	pokemon_switched_in.emit(new_mon, side, slot)
	_apply_switch_in_hazards(new_mon, side)
	_apply_switch_in_abilities(new_mon, side)
	_apply_stored_healing_effect(new_mon, combatant_idx)


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


# [D4 Bundle 5] A NEW sibling to `_set_mon_type` above, rather than a
# signature change to it — Reflect Type(513) needs to copy a TARGET's full
# (possibly dual-type) type array onto the user, which `_set_mon_type`'s
# single-int signature can't represent (it always forces a mono-type
# result). Adding a separate function guarantees zero risk to any of
# `_set_mon_type`'s existing callers (Conversion/Conversion 2/Protean/
# Libero/Multitype/Forecast) — none of them are touched by this change at
# all. `new_types` may be length 1 or 2; `species.types` is resized to
# match exactly (unlike `_set_mon_type`, which always pads to length 2 with
# a TYPE_NONE filler — that established behavior for the single-type
# callers above is deliberately left untouched).
func _set_mon_type_array(mon: BattlePokemon, new_types: Array) -> void:
	mon.species.types.resize(new_types.size())
	for _ti in range(new_types.size()):
		mon.species.types[_ti] = new_types[_ti]


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


# [Ability-reset fix] Sibling to _reset_mon_type, called alongside it at every
# switch-in site (a separate function, not folded into _reset_mon_type
# itself, since that function's own name/scope is specifically about type —
# matches this project's established convention of several small parallel
# reset/apply functions called in sequence, e.g. _apply_switch_in_hazards/
# _apply_switch_in_abilities/_apply_stored_healing_effect). Reassigning
# `mon.ability = mon.original_ability` goes through the setter above but is a
# safe no-op re: capture (original_ability is already non-null by this point
# in every reachable case, so the guard correctly declines to re-capture).
# Source: SwitchInClearSetData (battle_main.c) — see `ability`'s own doc
# comment on BattlePokemon for the full citation.
func _reset_mon_ability(mon: BattlePokemon) -> void:
	mon.ability = mon.original_ability


# [Mimic/Sketch] Sibling to _reset_mon_type/_reset_mon_ability, called
# alongside them at every switch-in site — restores a Mimic'd move slot back
# to Mimic itself (matching source's own switch-IN-time restoration, not a
# switch-out one — SwitchInClearSetData reloads the whole struct from party
# data during the switch-IN process, battle_main.c). Sketch's own overwrite
# is deliberately never touched here (permanent, per its own doc comment).
func _reset_mon_mimicked_move(mon: BattlePokemon) -> void:
	if mon.mimicked_slot < 0:
		return
	mon.moves[mon.mimicked_slot] = mon.mimicked_original_move
	mon.current_pp[mon.mimicked_slot] = mon.mimicked_original_pp
	mon.mimicked_slot = -1
	mon.mimicked_original_move = null
	mon.mimicked_original_pp = 0


# [Transform] Sibling to _reset_mon_type/_reset_mon_ability/
# _reset_mon_mimicked_move — restores `.species` to the mon's TRUE original
# species object. MUST be called BEFORE _reset_mon_type at every switch-in
# site: _reset_mon_type patches `.types` on whatever species object is
# CURRENTLY referenced, so if species itself hasn't been restored yet, that
# patch would land on the (still Transform-copied, duplicated) species
# object instead of the mon's real one. A safe no-op for any Pokémon that
# has never used Transform (species already IS original_species by
# identity). Source: SwitchInClearSetData re-deriving the whole struct from
# the party record on every switch-in (battle_main.c) — see `species`'s own
# doc comment on BattlePokemon for the full citation.
func _reset_mon_species(mon: BattlePokemon) -> void:
	mon.species = mon.original_species


# [Transform] Sibling to _reset_mon_species above — restores the 5 computed
# stat fields from their construction-time captures. A safe no-op for any
# Pokémon that has never used Transform.
func _reset_mon_stats(mon: BattlePokemon) -> void:
	mon.attack = mon.original_attack
	mon.defense = mon.original_defense
	mon.sp_attack = mon.original_sp_attack
	mon.sp_defense = mon.original_sp_defense
	mon.speed = mon.original_speed


# [Transform] Sibling to _reset_mon_species/_reset_mon_stats — restores the
# whole moveset+PP from the cast-time snapshot and clears `transformed`. A
# safe no-op (early return) for any Pokémon that hasn't used Transform since
# its last switch-in. Deliberately does NOT touch `times_hit` — source's own
# copy (`GetBattlerPartyState(attacker)->timesGotHit = ...target...`) writes
# directly into the attacker's PERSISTENT party-level record, with no
# restoration anywhere in SwitchInClearSetData; this project's own
# `times_hit` is likewise deliberately excluded from every switch-cleared
# mechanism (Harvest's `last_consumed_berry` precedent), so Transform's own
# overwrite of it is correctly PERMANENT, not reverted here.
func _reset_mon_transform(mon: BattlePokemon) -> void:
	if not mon.transformed:
		return
	mon.moves = mon.pre_transform_moves
	mon.current_pp = mon.pre_transform_pp
	mon.pre_transform_moves = []
	mon.pre_transform_pp = []
	mon.transformed = false


# Gen 5+ protect success formula. First use: always succeeds.
# Subsequent consecutive uses: success chance = 1 / (3^n).
# Source: battle_util.c :: CanUseMoveConsecutively (L10862)
#   sGen5ProtectFailChances = {1, 3, 9, 27}
func _roll_protect_success(consecutive: int) -> bool:
	const DENOMS: Array = [1, 3, 9, 27]
	var idx: int = clampi(consecutive, 0, DENOMS.size() - 1)
	var denom: int = DENOMS[idx]
	return denom == 1 or (randi() % denom == 0)


# [M19c] Whether `move` is blocked by `defender`'s currently-active Protect
# state, covering all 8 Protect-family moves (Protect/Detect plus the 7 new
# variants). Source: battle_util.c's protect dispatch (L5783-5824) — one
# combined `isProtected` computation this project splits into single-target
# (checked only against `defender` itself) and side-wide (also checked
# against `defender`'s ally, source: `IsSideProtected`, L5748-5752 — reads
# the SAME per-battler `protected` field for either battler on the side, not
# a separate side-level flag) halves:
#   - PROTECT_METHOD_OBSTRUCT/SILK_TRAP: blocks only non-status moves
#     (`!IsBattleMoveStatus`) — confirmed a real narrowing from plain
#     Protect's "blocks everything," not assumed uniform with the other
#     single-target variants.
#   - PROTECT_METHOD_WIDE_GUARD: blocks only spread moves (`IsSpreadMove` —
#     this project's own `move.is_spread`, the same established
#     TARGET_BOTH/TARGET_FOES_AND_ALLY proxy already used elsewhere, e.g.
#     Self-Destruct/Explosion).
#   - PROTECT_METHOD_QUICK_GUARD: blocks only priority>0 moves, using the
#     SAME ability-boosted effective-priority computation
#     (`AbilityManager.move_priority_bonus`) `[M17k]`'s `blocks_priority_move`
#     already established for the identical `GetChosenMovePriority` source
#     function — not raw `move.priority` alone.
#   - Every other method (plain Protect/Detect, Spiky Shield, Baneful
#     Bunker, Burning Bulwark): blocks unconditionally, the `_` match branch.
func _is_protected_from(attacker: BattlePokemon, defender: BattlePokemon,
		move: MoveData, ng_active: bool) -> bool:
	if move.ignores_protect:
		return false
	if defender.protect_active:
		match defender.protect_method:
			BattlePokemon.PROTECT_METHOD_OBSTRUCT, BattlePokemon.PROTECT_METHOD_SILK_TRAP:
				if move.category != 2:  # 2 = Status
					return true
			BattlePokemon.PROTECT_METHOD_WIDE_GUARD:
				if move.is_spread:
					return true
			BattlePokemon.PROTECT_METHOD_QUICK_GUARD:
				if move.priority + AbilityManager.move_priority_bonus(attacker, move, ng_active) > 0:
					return true
			_:
				return true
	var ally: BattlePokemon = _get_ally(defender)
	if ally != null and not ally.fainted and ally.protect_active:
		if ally.protect_method == BattlePokemon.PROTECT_METHOD_WIDE_GUARD and move.is_spread:
			return true
		if ally.protect_method == BattlePokemon.PROTECT_METHOD_QUICK_GUARD \
				and move.priority + AbilityManager.move_priority_bonus(attacker, move, ng_active) > 0:
			return true
	return false


# [M19c] Spiky Shield/Baneful Bunker/Burning Bulwark/Obstruct/Silk Trap's own
# contact-punish retaliation against the attacker, fired only when the
# blocked move actually made contact. Source: MoveEndProtectLikeEffect
# (battle_move_resolution.c L2497-2568) — gated on
# `CanBattlerAvoidContactEffects` (this project's own
# `AbilityManager.move_triggers_contact_retaliation`, the SAME
# Protective-Pads-aware wrapper Rough Skin/Iron Barbs/Rocky Helmet already
# use — confirmed from source this is the wrapper-level check, not the
# narrower `move_makes_contact`).
#   - Spiky Shield: maxHP/8 recoil to the attacker, gated on the
#     ATTACKER's own Magic Guard.
#   - Baneful Bunker/Burning Bulwark: poisons/burns the attacker via the
#     existing `try_apply_status` (which already handles Poison/Steel and
#     Fire-type immunity, and the already-has-a-status guard) — reflects
#     back via Synchronize on the attacker's own side, matching this
#     project's established convention for contact-triggered status
#     infliction.
#   - Obstruct: -2 Def on the attacker. Silk Trap: -1 Speed on the attacker.
#     Both via the raw `StatusManager.apply_stat_change` primitive (handles
#     Clear Body/White Smoke/Contrary/etc. immunities) plus an inline
#     Defiant/Competitive reactive-trigger check, matching
#     `_apply_one_stat_change_pair`'s own established shape for "an
#     opponent just lowered my stat."
func _apply_protect_contact_punish(attacker: BattlePokemon, defender: BattlePokemon,
		move: MoveData, ng_active: bool) -> void:
	if not AbilityManager.move_triggers_contact_retaliation(attacker, move, ng_active):
		return
	match defender.protect_method:
		BattlePokemon.PROTECT_METHOD_SPIKY_SHIELD:
			if not AbilityManager.blocks_indirect_damage(attacker, ng_active):
				var dmg: int = max(1, attacker.max_hp / 8)
				attacker.current_hp = max(0, attacker.current_hp - dmg)
				recoil_damage.emit(attacker, dmg)
		BattlePokemon.PROTECT_METHOD_BANEFUL_BUNKER:
			if StatusManager.try_apply_status(attacker, BattlePokemon.STATUS_POISON, null, null, ng_active):
				secondary_applied.emit(attacker, MoveData.SE_POISON)
				_try_synchronize(attacker, defender, BattlePokemon.STATUS_POISON)
		BattlePokemon.PROTECT_METHOD_BURNING_BULWARK:
			if StatusManager.try_apply_status(attacker, BattlePokemon.STATUS_BURN, null, null, ng_active):
				secondary_applied.emit(attacker, MoveData.SE_BURN)
				_try_synchronize(attacker, defender, BattlePokemon.STATUS_BURN)
		BattlePokemon.PROTECT_METHOD_OBSTRUCT:
			_apply_protect_stat_punish(attacker, defender, BattlePokemon.STAGE_DEF, -2, ng_active)
		BattlePokemon.PROTECT_METHOD_SILK_TRAP:
			_apply_protect_stat_punish(attacker, defender, BattlePokemon.STAGE_SPEED, -1, ng_active)


# Shared by Obstruct/Silk Trap above — a direct stat-drop on the attacker
# plus the same Defiant/Competitive reactive-trigger check
# `_apply_one_stat_change_pair` already applies for "an opponent lowered my
# stat," reused inline here since this reactive effect isn't dispatched
# through that function's own `move.stat_change_stat`-keyed shape.
func _apply_protect_stat_punish(attacker: BattlePokemon, defender: BattlePokemon,
		stat: int, amount: int, ng_active: bool) -> void:
	var actual: int = StatusManager.apply_stat_change(attacker, stat, amount, null, ng_active, defender)
	if actual == 0:
		return
	stat_stage_changed.emit(attacker, stat, actual)
	var defiant_stat: int = AbilityManager.defiant_competitive_stat(attacker, ng_active)
	if defiant_stat != -1:
		var defiant_actual: int = StatusManager.apply_stat_change(attacker, defiant_stat, 2, null, ng_active)
		if defiant_actual != 0:
			stat_stage_changed.emit(attacker, defiant_stat, defiant_actual)
			ability_triggered.emit(attacker, "defiant_competitive")


# [M19-recoil-on-miss] Jump Kick/High Jump Kick/Axe Kick/Supercell Slam —
# flat 50% of the ATTACKER'S OWN max HP, gated only on Magic Guard (NOT Rock
# Head — a confirmed asymmetry with ordinary recoil; see MoveData.
# crashes_on_miss's own doc comment for the full source citation). Called
# from each of this project's "the attacker genuinely attempted the move but
# it didn't affect the target" dispatch points (Protect block, type
# immunity, accuracy miss) — never from a pre-move-cancel path, since those
# never reach move resolution at all.
func _apply_crash_damage(attacker: BattlePokemon, ng_active: bool) -> void:
	if AbilityManager.blocks_indirect_damage(attacker, ng_active):
		return
	var crash: int = attacker.max_hp / 2
	if crash > 0:
		attacker.current_hp = max(0, attacker.current_hp - crash)
		crash_damage.emit(attacker, crash)


# [D4 Bundle 5] Steel Beam(724) — EFFECT_MAX_HP_50_RECOIL. UNCONDITIONALLY
# applies ceil(maxHP/2) self-damage once the move is attempted, regardless
# of whether the hit connected, missed, or was Protect-blocked — gated only
# by Magic Guard (Rock Head is never checked). A deliberately NEW, separate
# helper from `_apply_crash_damage` just above — that one only fires on a
# FAILED hit and floors its fraction (attacker.max_hp/2); this one fires
# ALWAYS (called from the Protect-block/accuracy-miss early-return paths
# AND after a normal connecting hit) and rounds UP, matching source's own
# `(GetNonDynamaxMaxHP(atk)+1)/2` exactly (MoveEndAbsorb, battle_move_
# resolution.c L2642-2653). Guards `attacker.current_hp > 0` since a prior
# recoil/contact-punish could have already fainted the attacker earlier in
# this same resolution (the current_hp-vs-.fainted timing convention).
func _apply_max_hp_50_recoil(attacker: BattlePokemon, ng_active: bool) -> void:
	if attacker.current_hp <= 0 or AbilityManager.blocks_indirect_damage(attacker, ng_active):
		return
	var recoil: int = (attacker.max_hp + 1) / 2
	if recoil > 0:
		attacker.current_hp = max(0, attacker.current_hp - recoil)
		recoil_damage.emit(attacker, recoil)


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


# [D4 Bundle 5] Fury Cutter(210) power lookup — base 40 (this project's
# B_UPDATED_MOVE_DATA>=GEN_6 config), doubled once per current counter
# value, clamped at 160 total. `counter` is the value BEFORE this use's own
# increment (read fresh each use, matching source's own
# CalcFuryCutterBasePower, battle_util.c L6046-6051, which reads
# `volatiles.furyCutterCounter` at damage-calc time, before
# SetSameMoveTurnValues' own later increment/wrap runs at MoveEnd).
static func _fury_cutter_power(counter: int) -> int:
	var p: int = 40
	for _i in range(counter):
		p *= 2
	return min(p, 160)


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


# [M19-hp-based-power] Flail/Reversal power — a STEPPED/BANDED formula from
# the user's OWN missing-HP fraction, NOT continuous (confirmed from source,
# not assumed). hp_fraction = floor(current_hp * 48 / max_hp), floored up to
# 1 if current_hp > 0 but the division would otherwise round to 0; then the
# FIRST table threshold (ascending) the fraction is <= wins.
# Source: battle_util.c :: GetScaledHPFraction (battle_interface.c L2312-2320)
#   + sFlailHpScaleToPowerTable (battle_util.c L6011-6019):
#   {1:200, 4:150, 9:100, 16:80, 32:40, 48:20}.
static func _flail_power(current_hp: int, max_hp: int) -> int:
	const THRESHOLDS: Array = [1, 4, 9, 16, 32, 48]
	const POWERS: Array = [200, 150, 100, 80, 40, 20]
	var hp_fraction: int = current_hp * 48 / max_hp
	if hp_fraction == 0 and current_hp > 0:
		hp_fraction = 1
	for i in range(THRESHOLDS.size()):
		if hp_fraction <= THRESHOLDS[i]:
			return POWERS[i]
	return POWERS[POWERS.size() - 1]


# [D4 CHEAP bundle] Gyro Ball power — target-to-user speed ratio, continuous
# (not banded), capped at 150. attacker_speed == 0 short-circuits to a flat
# power of 1 (division-by-zero guard, not part of the capped formula).
# Source: battle_util.c, case EFFECT_GYRO_BALL (L6249-6263).
static func _gyro_ball_power(attacker_speed: int, defender_speed: int) -> int:
	if attacker_speed == 0:
		return 1
	return mini(150, (25 * defender_speed) / attacker_speed + 1)


# [D4 CHEAP bundle] Electro Ball power — user-to-target speed ratio (the
# INVERSE direction from Gyro Ball), STEPPED/BANDED via a fixed lookup
# table, confirmed genuinely different in shape from Gyro Ball's continuous
# formula rather than assumed mirrored.
# Source: battle_util.c, case EFFECT_ELECTRO_BALL (L6243-6248);
# sSpeedDiffPowerTable (L6032): {40, 60, 80, 120, 150}.
static func _electro_ball_power(attacker_speed: int, defender_speed: int) -> int:
	const TABLE: Array = [40, 60, 80, 120, 150]
	var ratio: int = attacker_speed / maxi(1, defender_speed)
	return TABLE[clampi(ratio, 0, TABLE.size() - 1)]


# [D1 cheap clusters] Stored Power / Power Trip's own power formula input —
# sums the MAGNITUDE of every positive stat stage (e.g. Atk+3 contributes 3,
# not 1), NOT a count of how many distinct stats are raised. `include_evasion_acc`
# mirrors source's own CountBattlerStatIncreases(battler, countEvasionAcc)
# parameter — TRUE for Stored Power/Power Trip, matching this project's
# 7-element stat_stages array (indices 0-4 = Atk/Def/SpAtk/SpDef/Speed,
# 5 = Accuracy, 6 = Evasion).
static func _positive_stat_stage_sum(mon: BattlePokemon, include_evasion_acc: bool) -> int:
	var total: int = 0
	var count: int = mon.stat_stages.size() if include_evasion_acc else BattlePokemon.STAGE_ACCURACY
	for i in range(count):
		if mon.stat_stages[i] > 0:
			total += mon.stat_stages[i]
	return total


# [D1 EFFECT_DOUBLE_POWER_ON_ARG_STATUS] Checks whether `defender`'s status
# matches `arg` (a BattlePokemon.STATUS_* value, or one of MoveData's two
# sentinels, STATUS_ARG_POISON_ANY/STATUS_ARG_ANY). A Comatose holder
# (`[M17n-11]`, full non-volatile-status immunity — `defender.status` is
# always STATUS_NONE for one) is treated as having STATUS_SLEEP for this
# check specifically, matching source's own
# `(status1 | (STATUS1_SLEEP * isComatose)) & argStatus` bitwise-OR — a
# real, source-confirmed interaction (currently reachable since Comatose
# already ships, `[M17n-11]`), not an assumed symmetry. Only Hex/Infernal
# Parade's STATUS_ARG_ANY can actually observe this proxy among this
# cluster's 5 moves (Comatose can only ever "have" SLEEP, never PARALYSIS/
# POISON specifically), but the check is implemented generally to stay
# source-faithful for any future STATUS_ARG_SLEEP-specific move too.
# Source: battle_util.c, case EFFECT_DOUBLE_POWER_ON_ARG_STATUS (L6187-6188).
static func _status_matches_double_power_arg(defender: BattlePokemon, arg: int,
		ng_active: bool) -> bool:
	if arg == -1:
		return false
	var effective_status: int = defender.status
	if effective_status == BattlePokemon.STATUS_NONE \
			and AbilityManager.effective_ability_id(defender, ng_active) == AbilityManager.ABILITY_COMATOSE:
		effective_status = BattlePokemon.STATUS_SLEEP
	if arg == MoveData.STATUS_ARG_ANY:
		return effective_status != BattlePokemon.STATUS_NONE
	elif arg == MoveData.STATUS_ARG_POISON_ANY:
		return effective_status == BattlePokemon.STATUS_POISON \
				or effective_status == BattlePokemon.STATUS_TOXIC
	else:
		return effective_status == arg


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
		# [D4 Bundle 6] Psycho Shift's own transfer can carry Sleep/Freeze too
		# (unlike this function's prior 4 callers) — added here rather than a
		# bespoke mapping at that one call site.
		BattlePokemon.STATUS_SLEEP:     return MoveData.SE_SLEEP
		BattlePokemon.STATUS_FREEZE:    return MoveData.SE_FREEZE
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


# [D4 bundle] Returns a random MoveData from the ATTACKER's OWN moveset not
# banned from Sleep Talk (ban_flags & BAN_SLEEP_TALK) and not a two-turn
# move (move.two_turn) — the two exclusions source actually checks
# (IsMoveSleepTalkBanned || twoTurnEffect); PP=0/choice-lock are NOT
# excluded, matching source's own bypass, satisfied for free since this
# scan does no PP/choice filtering at all. Returns null if every move is
# excluded, OR if the attacker isn't actually asleep/Comatose — source's
# own GetSleepTalkMove checks this as its FIRST gate, independent of
# `usable_while_asleep`'s pre_move_check bypass (which only lets the move
# execute while asleep, it doesn't guarantee the attacker still IS asleep
# by the time this runs).
# Source: battle_move_resolution.c :: GetSleepTalkMove (L5098-5127).
func _pick_sleep_talk_move(attacker: BattlePokemon, ng_active: bool) -> MoveData:
	if attacker.status != BattlePokemon.STATUS_SLEEP \
			and AbilityManager.effective_ability_id(attacker, ng_active) != AbilityManager.ABILITY_COMATOSE:
		return null
	var pool: Array = []
	for m: MoveData in attacker.moves:
		if m != null and (m.ban_flags & MoveData.BAN_SLEEP_TALK) == 0 and not m.two_turn:
			pool.append(m)
	if pool.is_empty():
		return null
	return pool[randi() % pool.size()]


# [D4 Bundle 4] Copycat: returns `_last_landed_move_anyone` unless it's null or
# `copycatBanned` (BAN_COPYCAT) — no randomness involved, unlike Metronome/
# Assist/Sleep Talk's own random pool picks.
# Source: GetCopycatMove (battle_move_resolution.c L5132-5140).
func _pick_copycat_move() -> MoveData:
	if _last_landed_move_anyone == null:
		return null
	if (_last_landed_move_anyone.ban_flags & MoveData.BAN_COPYCAT) != 0:
		return null
	return _last_landed_move_anyone


# [D4 Bundle 4] Assist: a random move from `attacker`'s OWN bench (non-active,
# non-fainted party members), excluding `assistBanned` (BAN_ASSIST) moves.
# Source: GetAssistMove (battle_move_resolution.c L5029-5075).
func _pick_assist_move(attacker: BattlePokemon) -> MoveData:
	var atk_idx: int = _actor_indices.get(attacker, _combatants.find(attacker))
	var atk_side: int = atk_idx / _active_per_side
	var party: BattleParty = _parties[atk_side]
	var pool: Array = []
	for i in range(party.members.size()):
		if party.active_indices.has(i):
			continue
		var mon: BattlePokemon = party.members[i]
		if mon == null or mon.fainted:
			continue
		for m: MoveData in mon.moves:
			if m != null and (m.ban_flags & MoveData.BAN_ASSIST) == 0:
				pool.append(m)
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
		move: MoveData, helping_hand: bool, power_override: int,
		me_first: bool = false) -> void:
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
				attacker, target, move, false, helping_hand, this_power_override, true, me_first)
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


# [M19-secondary-stat-on-hit] Shared EFFECT_STAT_CHANGE application — extracted
# from _phase_move_execution's pure-status-move dispatch (Growl, Swords Dance)
# so _do_damaging_hit's new damage-move secondary-stat-change dispatch (Iron
# Tail, Overheat) can reuse it exactly rather than re-deriving the Mirror Armor
# redirect / Defiant-Competitive / Opportunist / Mirror Herb logic. Handles
# self/foe targeting via move.stat_change_self, stage math via
# StatusManager.apply_stat_change, and all associated signal emission. Callers
# are responsible for their own move_executed/phase-transition bookkeeping —
# this function only applies the stat effect and emits stat/ability signals.
#
# [Bucket 3 multi-stat] Applies the PRIMARY pair (stat_change_stat/amount)
# then loops move.extra_stat_change_stats/amounts (Ancient Power's 5 stats,
# Shell Smash's mixed +2/-1, Spicy Extract's mixed +2/-2), running the exact
# same per-pair logic — including Mirror Armor/Defiant/Opportunist/Mirror
# Herb — independently for EACH pair, not once for the whole move. This is
# deliberate, not just convenient: Mirror Armor must redirect only the
# DECREASING component of a mixed-sign move (Spicy Extract's -2 Def
# redirects, its simultaneous +2 Atk does not), and real Defiant/Competitive
# behavior fires once per qualifying decrease, so a move lowering 2 stats at
# once against a Defiant holder correctly triggers it twice — confirmed
# against source, not assumed. stat_change_self is read once per move (self/
# foe never varies within one move's own stat sub-fields, confirmed via
# direct inspection of every multi-stat move in this project's roster) and
# threaded into every pair's application.
# See the original inline block (pre-[M19-secondary-stat-on-hit]) for the
# per-mechanism source citations this was ported from verbatim:
# M17n-11 (Mirror Armor), M17g (Mold Breaker threading), M17b (Defiant/
# Competitive), M17n-8 (Opportunist), M18m (Mirror Herb).
func _apply_stat_change_effect(attacker: BattlePokemon, defender: BattlePokemon, move: MoveData, ng_active: bool) -> void:
	_apply_one_stat_change_pair(attacker, defender, move, move.stat_change_stat, move.stat_change_amount, ng_active)
	for i in range(move.extra_stat_change_stats.size()):
		_apply_one_stat_change_pair(attacker, defender, move,
				move.extra_stat_change_stats[i], move.extra_stat_change_amounts[i], ng_active)


func _apply_one_stat_change_pair(attacker: BattlePokemon, defender: BattlePokemon, move: MoveData,
		stat: int, amount: int, ng_active: bool) -> int:
	var stat_target: BattlePokemon = attacker if move.stat_change_self else defender

	# [D4 Bundle 4] Mist — blocks ANY decrease (post-Simple/Contrary
	# adjustment) on the protected side, checked BEFORE Mirror Armor/the
	# ability-block chain below, matching source's own CanDecreaseStat
	# ordering (IsMistProtected is the FIRST check in that chain, ahead of
	# IsAbilityBlocked/IsMirrorArmorReflected — battle_stat_change.c
	# L316-321). An opposing Infiltrator holder bypasses it (source:
	# IsMistProtected, battle_stat_change.c L580-590); reuses
	# `bypasses_infiltrator_barriers` directly — that function's own doc
	# comment already anticipated this exact addition. Checked on the
	# ADJUSTED (post-Contrary) sign, not the raw `amount` — a genuinely
	# self-inflicted Contrary decrease against one's OWN Mist is still
	# blocked per source (IsBattlerAlly(battlerDef, battlerAtk) is
	# trivially TRUE when the two are the same battler), a real, source-
	# faithful edge case rather than a special-cased exemption.
	var adjusted_for_mist: int = AbilityManager.adjust_stat_stage_amount(
			stat_target, amount, ng_active, attacker)
	if adjusted_for_mist < 0:
		var mist_idx: int = _actor_indices.get(stat_target, _combatants.find(stat_target))
		var mist_side: int = mist_idx / _active_per_side
		if _side_conditions[mist_side]["mist_turns"] > 0 \
				and not AbilityManager.bypasses_infiltrator_barriers(attacker, ng_active):
			move_effect_failed.emit(stat_target, "mist_protected")
			return 0

	if not move.stat_change_self and amount < 0 \
			and AbilityManager.mirror_armor_reflects(stat_target, attacker, ng_active, attacker):
		var reflected: int = StatusManager.apply_stat_change(
				attacker, stat, amount, null, ng_active)
		if reflected == 0:
			move_effect_failed.emit(attacker, "stat_limit")
		else:
			stat_stage_changed.emit(attacker, stat, reflected)
		ability_triggered.emit(stat_target, "mirror_armor")
		return 0
	var actual: int = StatusManager.apply_stat_change(
			stat_target, stat, amount,
			null, ng_active, attacker)
	if actual == 0:
		move_effect_failed.emit(stat_target, "stat_limit")
	else:
		stat_stage_changed.emit(stat_target, stat, actual)
		if actual < 0 and not move.stat_change_self:
			var defiant_stat: int = AbilityManager.defiant_competitive_stat(stat_target, ng_active)
			if defiant_stat != -1:
				var defiant_actual: int = StatusManager.apply_stat_change(stat_target, defiant_stat, 2, null, ng_active)
				if defiant_actual != 0:
					stat_stage_changed.emit(stat_target, defiant_stat, defiant_actual)
					ability_triggered.emit(stat_target, "defiant_competitive")
		if actual > 0:
			for opp: BattlePokemon in _get_live_opponents(stat_target):
				if AbilityManager.effective_ability_id(opp, ng_active) == AbilityManager.ABILITY_OPPORTUNIST:
					var opp_actual: int = StatusManager.apply_stat_change(
							opp, stat, actual, null, ng_active)
					if opp_actual != 0:
						stat_stage_changed.emit(opp, stat, opp_actual)
						ability_triggered.emit(opp, "opportunist")
				if ItemManager.holds_mirror_herb(opp, ng_active):
					var mh_actual: int = StatusManager.apply_stat_change(
							opp, stat, actual, null, ng_active)
					if mh_actual != 0:
						stat_stage_changed.emit(opp, stat, mh_actual)
					_consume_item(opp)
	return actual


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
		power_override: int = -1, suppress_shell_bell: bool = false,
		me_first: bool = false) -> int:
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
			_get_ally(target), ng_active, _is_last_to_move(attacker), me_first,
			_mud_sport_turns > 0, _water_sport_turns > 0)
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

	# [D4 Bundle 4] Copycat's own global tracker — same `damage > 0`
	# (INCLUDING_SUBSTITUTES) gate as Rapid Spin/Air Balloon just above. See
	# `_last_landed_move_anyone`'s own doc comment for the full citation and
	# its disclosed status-move-coverage gap.
	if damage > 0:
		_last_landed_move_anyone = move

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

	# M17n-5/M18o/[D4 CHEAP bundle]: survive-a-lethal-hit chain — Endure,
	# Sturdy, Focus Band, Focus Sash.
	# Source: battle_util.c L7962-7984 (the shared endure-check function every
	# lethal hit routes through) — `if (defender.hp > damage) return damage` (non-lethal,
	# skip); else Endure volatile → False Swipe → Sturdy (IsBattlerAtMaxHp gate,
	# B_STURDY >= GEN_5, satisfied at this project's GEN_LATEST) → Focus Band → Focus
	# Sash → affection, in that priority order, first match wins, `damage = hp - 1`.
	# This project has no False Swipe move and no affection mechanic — Endure/
	# Sturdy/Focus Band/Focus Sash are the four reachable cases, and this is a
	# strict elif chain (first match wins), NOT four independent checks —
	# confirmed from source: a Pokemon with BOTH Sturdy and a held Focus
	# Sash never reaches the Focus Sash branch at all when Sturdy already fires,
	# so the item is not consumed, not "wasted," simply untouched by that hit.
	# Both `damage >= target.current_hp` checks below read target.current_hp
	# BEFORE it's reduced by this hit (the reduction happens several lines below)
	# — a pre-application lethality prediction on the target's own still-current
	# HP, not a post-hit aliveness check on a different Pokemon, so this has no
	# analogous timing bug to the current_hp-vs-.fainted convention.
	# [D4 Bundle 6] False Swipe: unconditionally floors the target at 1 HP,
	# checked first so the Endure/Sturdy/Focus Band/Focus Sash chain below
	# naturally no-ops afterward (damage no longer exceeds current_hp).
	if move.is_false_swipe and damage >= target.current_hp:
		damage = target.current_hp - 1

	if damage >= target.current_hp and target.endure_active:
		damage = target.current_hp - 1
		endured.emit(target)
	elif damage >= target.current_hp and target.current_hp == target.max_hp \
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
		# [D3 turn-order/event-tracker batch] Rage Fist's own lifetime counter —
		# incremented once per hit that actually deals damage, unconditional on
		# category/contact. See BattlePokemon.times_hit's own doc comment.
		target.times_hit += 1
		# [D1 easy bundle] Revenge/Avalanche's own per-(victim,attacker)-pair
		# tracker — recorded on the SAME chokepoint, unconditional on
		# category/contact. See BattlePokemon.hit_by_this_turn's own doc comment.
		if not target.hit_by_this_turn.has(attacker):
			target.hit_by_this_turn.append(attacker)
		if move.category == 0:
			target.last_physical_damage = damage
			target.last_hit_was_special = false
		else:
			target.last_special_damage = damage
			target.last_hit_was_special = true
		# [D4 Bundle 7] Shell Trap — armed reactively the instant TARGET takes a
		# PHYSICAL hit, unconditional on contact (unlike Beak Blast just below),
		# reusing the `move.category == 0` check already available at this
		# exact chokepoint (the same one Metal Burst's last_hit_was_special
		# reads). Gated on the TARGET's own chosen move this turn being Shell
		# Trap. See MoveData.is_shell_trap's own doc comment for the full
		# source citation.
		var st_idx: int = _combatants.find(target)
		var st_chosen: MoveData = _chosen_moves[st_idx] \
				if st_idx != -1 and st_idx < _chosen_moves.size() else null
		if st_chosen != null and st_chosen.is_shell_trap and move.category == 0:
			target.shell_trap_armed = true


	# [D4 Bundle 6] Knock Off: on a connecting hit, actually remove the
	# target's item (re-checked here, not just trusted from the pre-hit
	# power computation, since the target's ability/held item could
	# theoretically differ by the time the hit resolves). Deliberately does
	# NOT route through `_consume_item` — that function's Cheek Pouch heal
	# and `last_consumed_berry` tracking are both specifically for EATING a
	# berry, and Knock Off never does that (the item is knocked away, not
	# ingested) — only Unburden ("any item, berry or not") and Symbiosis
	# apply here, replicated directly.
	if move.is_knock_off and damage > 0 and AbilityManager.can_remove_item(target, ng_active):
		var knocked_item: ItemData = target.held_item
		target.held_item = null
		item_consumed.emit(target, knocked_item)
		item_effect_triggered.emit(attacker, "knock_off")
		if AbilityManager.effective_ability_id(target, ng_active) == AbilityManager.ABILITY_UNBURDEN:
			target.unburden_active = true
		_try_symbiosis(target)

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
	# [D4 Bundle 5] Chloroblast — SAME ceil(maxHP/2) formula as Steel Beam,
	# but dispatched through the ordinary hit-gated/Rock-Head-and-Magic-
	# Guard-blocked recoil shape (`AbilityManager.blocks_recoil`), a
	# confirmed real divergence from Steel Beam's own unconditional/
	# Magic-Guard-only dispatch — see MoveData.is_chloroblast's own doc
	# comment for the full citation.
	elif move.is_chloroblast and damage > 0 and not AbilityManager.blocks_recoil(attacker, ng_active):
		var cb_recoil: int = (attacker.max_hp + 1) / 2
		if cb_recoil > 0:
			attacker.current_hp = max(0, attacker.current_hp - cb_recoil)
			recoil_damage.emit(attacker, cb_recoil)

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

	# [Bucket 4 cheapest singles] Rage: sets rage_active on the ATTACKER after a
	# successful hit — guaranteed, no `.chance` field, so unconditional on
	# damage > 0 alone (not routed through try_secondary_effect). The REACTIVE
	# half (raising Attack when the holder itself is later hit) lives further
	# down, near the other hit-reactive triggers, since it's keyed on the
	# TARGET's own rage_active flag regardless of which move hits them.
	if damage > 0 and move.is_rage:
		attacker.rage_active = true

	# [M19-recharge] Sets on a successful, non-immune hit only — confirmed
	# from source a MISS does NOT set this (see MoveData.is_recharge's own
	# doc comment for the full citation). Consumed the NEXT time this
	# Pokémon would act, via StatusManager.pre_move_check.
	if damage > 0 and move.is_recharge:
		attacker.must_recharge = true

	# [M19-break-protect] Feint/Shadow Force/Phantom Force/Hyperspace Hole —
	# post-hit only (none of the 4 set preAttackEffect, so a miss never
	# breaks Protect — see MoveData.breaks_protect's own doc comment for the
	# full citation). Single-target scope: clears the DEFENDER's own
	# protect_active plus resets protect_consecutive (the Gen5+ 1/3^n
	# fail-chance ramp `_roll_protect_success` reads), matching source's
	# `protected = PROTECT_NONE; volatiles.consecutiveMoveUses = 0`. No-op
	# (and no signal) if the defender wasn't actually Protect-active —
	# mirrors source's own `i = FALSE` no-op-if-nothing-to-break shape.
	if damage > 0 and move.breaks_protect and target.protect_active:
		target.protect_active = false
		target.protect_consecutive = 0
		protect_broken.emit(target)

	# [Bucket 4 cheapest singles] Clear Smog: resets ALL of the target's stat
	# stages to exactly 0 — an absolute reset, not a relative stat_change_amount
	# delta, so this cannot reuse _apply_stat_change_effect at all.
	if damage > 0 and move.is_clear_smog:
		_reset_stat_stages(target)

	# [D0] Freezy Frost(686)'s on-hit secondary — the SAME `_reset_stat_stages`
	# primitive Haze(114)/Clear Smog reuse, but looped over EVERY live combatant
	# (both sides), matching Haze's own field-wide scope exactly. See
	# MoveData.is_haze_on_hit's own doc comment for the full source citation.
	if damage > 0 and move.is_haze_on_hit:
		for mon: BattlePokemon in _combatants:
			if not mon.fainted:
				_reset_stat_stages(mon)

	# [D0] Sappy Seed(685)'s on-hit secondary — Leech Seed applied to the
	# TARGET as a guaranteed additional effect on a successful hit. Reuses
	# StatusManager.try_apply_leech_seed verbatim (same Grass-immune/
	# already-seeded gate the primary Leech Seed(73) move uses).
	if damage > 0 and move.is_leech_seed_on_hit:
		if StatusManager.try_apply_leech_seed(target, attacker):
			leech_seeded.emit(target, attacker)

	# [D4 CHEAP bundle] Smack Down: forces the TARGET grounded for the rest
	# of the battle, clears its Magnet Rise timer, and knocks it out of the
	# air if it was mid-Fly. `damagesAirborne = TRUE` (existing generic
	# field) already lets this hit connect against a Fly-ing target in the
	# first place. See BattlePokemon.smack_down_active's own doc comment for
	# the full source citation.
	if damage > 0 and move.is_smack_down and target.current_hp > 0:
		if not target.smack_down_active:
			target.smack_down_active = true
			target.magnet_rise_turns = 0
			if target.semi_invulnerable == MoveData.SEMI_INV_ON_AIR:
				target.semi_invulnerable = MoveData.SEMI_INV_NONE
			smack_down_set.emit(target)

	# [D0] Sparkly Swirl(687)'s on-hit secondary — Aromatherapy's party-wide
	# cure applied to the ATTACKER'S OWN party (source's Cmd_healpartystatus
	# always operates on GetBattlerParty(gBattlerAttacker) regardless of the
	# move's own `.self = TRUE` flag — heals the attacker's side even though
	# the move damages an opponent). Reuses _apply_heal_bell verbatim.
	if damage > 0 and move.is_heal_bell_on_hit:
		_apply_heal_bell(attacker, false, ng_active)

	# [Bucket 4 cheapest singles] Incinerate: destroys (not consumes) the
	# target's held Berry — deliberately bypasses `_consume_item` (which would
	# incorrectly also trigger Cheek Pouch / register last_consumed_berry, per
	# MoveData.is_incinerate's own doc comment) and instead reproduces ONLY the
	# Unburden trigger source's own case calls directly. This project has no Gem
	# items, so the Gen6+ Gem half of source's condition is permanently moot.
	if damage > 0 and move.is_incinerate and target.held_item != null \
			and target.held_item.pocket == ItemManager.POCKET_BERRIES \
			and AbilityManager.effective_ability_id(target, ng_active) != AbilityManager.ABILITY_STICKY_HOLD:
		target.held_item = null
		if AbilityManager.effective_ability_id(target, ng_active) == AbilityManager.ABILITY_UNBURDEN:
			target.unburden_active = true
		item_effect_triggered.emit(target, "incinerate_destroyed")

	# [M19-berry-steal] Pluck/Bug Bite: steal the TARGET's berry and
	# immediately consume its effect on the ATTACKER — NOT a possession
	# transfer (the item is eaten in place, matching source's `consumeberry
	# BS_ATTACKER, FALSE`), and genuinely different from Incinerate just
	# above (which destroys with no beneficiary effect at all). A held
	# Jaboca/Rowap Berry specifically is EXEMPT from the steal — source's
	# own MOVE_EFFECT_BUG_BITE case checks this FIRST and lets Jaboca/Rowap's
	# own retaliation fire instead (already dispatched independently
	# elsewhere in this function, category-gated, not contact-gated).
	if damage > 0 and move.steals_and_eats_berry and target.held_item != null \
			and target.held_item.pocket == ItemManager.POCKET_BERRIES \
			and target.held_item.hold_effect != ItemManager.HOLD_EFFECT_JABOCA_BERRY \
			and target.held_item.hold_effect != ItemManager.HOLD_EFFECT_ROWAP_BERRY \
			and AbilityManager.effective_ability_id(target, ng_active) != AbilityManager.ABILITY_STICKY_HOLD:
		var stolen_item: ItemData = target.held_item
		target.held_item = null
		if AbilityManager.effective_ability_id(target, ng_active) == AbilityManager.ABILITY_UNBURDEN:
			target.unburden_active = true
		berry_stolen_and_eaten.emit(target, attacker, stolen_item)
		var eat_result: Dictionary = ItemManager.steal_and_eat_berry_effect(attacker, stolen_item, ng_active)
		if not eat_result.is_empty():
			match eat_result["kind"]:
				"heal":
					attacker.current_hp = min(attacker.max_hp, attacker.current_hp + eat_result["amount"])
					item_healed.emit(attacker, eat_result["amount"])
				"cure_status":
					attacker.status = BattlePokemon.STATUS_NONE
					status_cured.emit(attacker)
				"cure_confusion":
					attacker.confusion_turns = 0
					status_cured.emit(attacker)
				"stat":
					var stolen_actual: int = StatusManager.apply_stat_change(
							attacker, eat_result["stat"], eat_result["amount"], null, ng_active)
					if stolen_actual != 0:
						stat_stage_changed.emit(attacker, eat_result["stat"], stolen_actual)
		# [M17j] Symbiosis fires for the TARGET's own ally, since the
		# TARGET's item just vanished — same trigger source's
		# `trysymbiosis BS_TARGET` reaches right after the steal.
		_try_symbiosis(target)

	# [D1] Thief / Covet: steal the target's held item outright (possession
	# TRANSFER, not eaten in place — genuinely different from Pluck/Bug
	# Bite just above, and item-GENERAL with no Jaboca/Rowap exemption,
	# confirmed at Step 0 from CanStealItem's own real content). Directly
	# reuses AbilityManager.try_thief_steal (the Pickpocket/Magician
	# primitive) verbatim, gated on the attacker itself holding nothing.
	if damage > 0 and move.steals_item_if_itemless \
			and attacker.held_item == null and target.held_item != null:
		if AbilityManager.effective_ability_id(target, ng_active) == AbilityManager.ABILITY_STICKY_HOLD:
			ability_triggered.emit(target, "sticky_hold")
		elif AbilityManager.try_thief_steal(attacker, target, ng_active):
			item_stolen.emit(attacker, target)
			_try_symbiosis(target)

	# [Bucket 4 cheapest singles] Sparkling Aria: cures BURN specifically on the
	# TARGET (whoever this hit — the inverse of every existing self-cure
	# precedent), only if the target currently has it.
	if damage > 0 and move.is_sparkling_aria and target.status == BattlePokemon.STATUS_BURN:
		target.status = BattlePokemon.STATUS_NONE
		status_cured.emit(target)

	# [D1 EFFECT_DOUBLE_POWER_ON_ARG_STATUS] Smelling Salts: cures PARALYSIS
	# specifically on the TARGET, only if the target currently has it — same
	# shape as Sparkling Aria just above, mirrored rather than generalized
	# (no existing SE_* token represents "cure a status FROM the target").
	# Naturally already excluded when a live Substitute blocked the hit,
	# since damage > 0 only holds here when _do_damaging_hit reports a real
	# hit on the actual Pokémon — the power-double's OWN separate Substitute
	# exception lives in the pre-hit block above, see MoveData.
	# is_smelling_salts's own doc comment for the full citation.
	if damage > 0 and move.is_smelling_salts and target.status == BattlePokemon.STATUS_PARALYSIS:
		target.status = BattlePokemon.STATUS_NONE
		status_cured.emit(target)

	# [M19-rampage] Thrash/Petal Dance/Outrage/Raging Fury (is_rampage) and
	# Uproar (is_uproar) share ONE lock field (BattlePokemon.locked_move) but
	# distinct counters/end-of-lock behavior — see both flags' own MoveData
	# doc comments for the full source citations. Checked at this project's
	# closest per-hit-resolution granularity (this function runs once per own
	# move-use attempt that reaches damage calc), mirroring source's
	# MoveEndRampage/Uproar-decrement running once per move use.
	if move.is_rampage or move.is_uproar:
		# Source: MoveEndRampage's IsBattlerUnaffectedByMove branch — a
		# CONTINUING lock (turn 2+) cancels immediately WITHOUT self-confuse
		# when the current hit is fully unaffected by type immunity (e.g. the
		# opponent switched a Ghost-type in mid-Thrash). A first-use immune
		# hit never sets the lock in the first place (additionalEffects never
		# runs for a 0x hit in source), so this branch is a no-op unless
		# already locked to this exact move.
		if result.get("effectiveness", 1.0) == 0.0:
			if attacker.locked_move == move:
				attacker.locked_move = null
				attacker.rampage_turns = 0
				attacker.uproar_turns = 0
				rampage_lock_ended.emit(attacker, move, false)
		elif damage > 0:
			if attacker.locked_move != move:
				attacker.locked_move = move
				if move.is_rampage:
					attacker.rampage_turns = randi_range(2, 3)
				else:
					attacker.uproar_turns = 3
				rampage_lock_started.emit(attacker, move)
			if move.is_rampage:
				attacker.rampage_turns -= 1
				if attacker.rampage_turns <= 0:
					attacker.locked_move = null
					var confused_on_hit: bool = StatusManager.try_apply_confusion(
							attacker, null, ng_active)
					if confused_on_hit:
						secondary_applied.emit(attacker, MoveData.SE_CONFUSION)
					rampage_lock_ended.emit(attacker, move, confused_on_hit)
			else:
				attacker.uproar_turns -= 1
				if attacker.uproar_turns <= 0:
					attacker.locked_move = null
					rampage_lock_ended.emit(attacker, move, false)

	# [M19-secondary-stat-on-hit]: `move.stat_change_stat >= 0` is a second,
	# independent trigger alongside `secondary_effect != SE_NONE` — a damaging
	# move's secondary stat-change payload (Iron Tail, Overheat) has
	# secondary_effect == SE_NONE by construction, so without this OR the outer
	# gate would skip calling try_secondary_effect entirely for these moves,
	# even after that function's own internal gate (status_manager.gd) was
	# extended to accept them.
	if damage > 0 and (move.secondary_effect != MoveData.SE_NONE or move.stat_change_stat >= 0):
		var effect_hit: bool = StatusManager.try_secondary_effect(attacker, target, move, null, ng_active, _effective_weather(), _is_uproar_active(), null, _is_safeguard_active_for(attacker, target, ng_active))
		if effect_hit:
			if move.secondary_effect == MoveData.SE_FLINCH:
				var target_turn_pos: int = _turn_order.find(target)
				if target_turn_pos > _current_actor_index:
					target.flinched = true
					secondary_applied.emit(target, MoveData.SE_FLINCH)
			elif move.secondary_effect == MoveData.SE_NONE and move.stat_change_stat >= 0:
				# [M19-secondary-stat-on-hit]: deliberately its own branch, same
				# reason SE_FLINCH/SE_WRAP get one — the "else" path below assumes
				# the secondary effect just set target.status/confusion_turns, which
				# a stat change never does; _apply_stat_change_effect (shared with
				# the pure-status-move EFFECT_STAT_CHANGE dispatch — see that
				# function's doc comment for the Mirror Armor/Defiant/Opportunist/
				# Mirror Herb source citations) handles its own signal emission
				# (stat_stage_changed/move_effect_failed/ability_triggered), so no
				# secondary_applied/status-cure-berry check belongs here.
				_apply_stat_change_effect(attacker, target, move, ng_active)
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
			elif move.secondary_effect == MoveData.SE_PREVENT_ESCAPE:
				# [M19f] Spirit Shackle — same shape as SE_WRAP just above:
				# try_apply_escape_prevention (called inside try_secondary_effect's
				# own match above) already fully mutated target.escape_prevented_by
				# and reported its own "already trapped" no-op via its return value
				# (effect_hit == false skips this whole elif chain in that case);
				# this branch only emits the signal.
				secondary_applied.emit(target, MoveData.SE_PREVENT_ESCAPE)
				escape_prevented.emit(target, attacker)
			elif move.secondary_effect == MoveData.SE_TRAP_BOTH:
				# [M19f] Jaw Lock — both battlers already mutated inside
				# try_secondary_effect's own SE_TRAP_BOTH case above; this
				# branch only emits the two signals.
				secondary_applied.emit(target, MoveData.SE_TRAP_BOTH)
				escape_prevented.emit(target, attacker)
				escape_prevented.emit(attacker, target)
			elif move.secondary_effect == MoveData.SE_THROAT_CHOP:
				# [Bucket 4 cheapest singles] Deliberately its own branch, same reason
				# SE_FLINCH/SE_WRAP get one — the "else" path below assumes a status/
				# confusion field just got SET, which this never touches. No-refresh
				# gate matches source's own `if (throatChopTimer == 0)` check exactly.
				if target.throat_chop_turns == 0:
					target.throat_chop_turns = 2
					secondary_applied.emit(target, MoveData.SE_THROAT_CHOP)
			elif move.secondary_effect == MoveData.SE_EERIE_SPELL:
				# [Bucket 4 cheapest singles] Deliberately its own branch, same reason
				# as SE_THROAT_CHOP above. Reuses the pre-existing last_move_used
				# tracking — finds that move's own PP slot and deducts 3 (capped at
				# whatever PP remains, matching source's own ppToDeduct clamp; a no-op
				# if the target has no last_move_used or that move is already at 0 PP).
				if target.last_move_used != null:
					var eerie_idx: int = target.moves.find(target.last_move_used)
					if eerie_idx >= 0 and target.current_pp[eerie_idx] > 0:
						target.use_pp(eerie_idx, 3)
						secondary_applied.emit(target, MoveData.SE_EERIE_SPELL)
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

	# [Bucket 3 combined-secondary]: a SECOND, fully independent secondary-effect
	# roll (Thunder/Ice/Fire Fang's flinch, alongside their own status effect in
	# slot 1 above). Reproduced via a second try_secondary_effect call on a
	# shallow-duplicated MoveData (secondary_effect/secondary_chance overridden to
	# the slot-2 values) — the same "duplicate and substitute" pattern M17n-6
	# already established for move-type mutation, rather than changing
	# try_secondary_effect's own signature. This composes Serene Grace/Shield
	# Dust/Covert Cloak/Sheer Force correctly for free: each gate reads the
	# duplicated move's own (now slot-2) secondary_chance/secondary_effect, so a
	# Sheer-Force attacker independently suppresses BOTH rolls (matching source's
	# MoveIsAffectedBySheerForce, which flags the whole move once ANY additional
	# effect has chance > 0) and a Shield-Dust/Covert-Cloak defender independently
	# blocks both (matching source's blanket per-effect gate).
	if damage > 0 and move.secondary_effect_2 != MoveData.SE_NONE:
		var slot2_move: MoveData = move.duplicate()
		slot2_move.secondary_effect = move.secondary_effect_2
		slot2_move.secondary_chance = move.secondary_chance_2
		var effect2_hit: bool = StatusManager.try_secondary_effect(
				attacker, target, slot2_move, null, ng_active, _effective_weather(), false, null,
				_is_safeguard_active_for(attacker, target, ng_active))
		if effect2_hit:
			if move.secondary_effect_2 == MoveData.SE_FLINCH:
				var target_turn_pos2: int = _turn_order.find(target)
				if target_turn_pos2 > _current_actor_index:
					target.flinched = true
					secondary_applied.emit(target, MoveData.SE_FLINCH)
			else:
				secondary_applied.emit(target, move.secondary_effect_2)
				_try_synchronize(target, attacker, _se_to_status(move.secondary_effect_2))
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
	# native chance rolled true this turn — checked against BOTH slots now that a
	# move's native flinch can live in slot 2 (Thunder/Ice/Fire Fang) instead of
	# slot 1. Same turn-order gate as the native case above (a flinch that lands
	# on a target who has already acted this turn does nothing — they don't act
	# again).
	if damage > 0 and move.secondary_effect != MoveData.SE_FLINCH \
			and move.secondary_effect_2 != MoveData.SE_FLINCH \
			and ItemManager.kings_rock_flinch_activates(attacker, ng_active, _force_kings_rock_roll):
		var kr_turn_pos: int = _turn_order.find(target)
		if kr_turn_pos > _current_actor_index:
			target.flinched = true
			secondary_applied.emit(target, MoveData.SE_FLINCH)

	# [Bucket 3 screen+damage]: Glitzy Glow / Baddy Bad — a guaranteed, self-
	# targeted screen set on the ATTACKER's own side after dealing damage. No
	# .chance field in source (primary, not a true secondary), so this is
	# unconditional on damage > 0 alone, same as Rapid Spin/Air Balloon above —
	# not routed through try_secondary_effect at all, since Shield Dust/Sheer
	# Force/Serene Grace only ever gate TRUE (chance > 0) secondaries. Reuses the
	# exact same already-up no-refresh check and Light Clay duration extension
	# the pure-status-move is_reflect/is_light_screen branches use, just reached
	# from the damage-dispatch path since is_reflect/is_light_screen's own early-
	# return branch never deals damage at all (see MoveData's doc comment on
	# sets_reflect_on_hit/sets_light_screen_on_hit for the full source citation).
	if damage > 0 and (move.sets_reflect_on_hit or move.sets_light_screen_on_hit):
		var atk_idx2: int = _combatants.find(attacker)
		var atk_side2: int = atk_idx2 / _active_per_side
		var asc2: Dictionary = _side_conditions[atk_side2]
		if move.sets_reflect_on_hit:
			if asc2["reflect_turns"] > 0:
				move_effect_failed.emit(attacker, "already_reflect")
			else:
				asc2["reflect_turns"] = ItemManager.screen_turns(attacker, 5, ng_active)
				screen_set.emit(atk_side2, "reflect")
		if move.sets_light_screen_on_hit:
			if asc2["light_screen_turns"] > 0:
				move_effect_failed.emit(attacker, "already_light_screen")
			else:
				asc2["light_screen_turns"] = ItemManager.screen_turns(attacker, 5, ng_active)
				screen_set.emit(atk_side2, "light_screen")

	# [D2 batch] Stone Axe(758) / Ceaseless Edge(773) — a guaranteed on-hit
	# hazard set on the TARGET's own side (the opposite side from Glitzy Glow/
	# Baddy Bad's own self-side screens just above), gated on the hazard not
	# already being maxed — same layer-cap/emit shape the pure-status Spikes
	# (113)/Stealth Rock(446) moves already use. See MoveData.sets_
	# stealth_rock_on_hit/sets_spikes_on_hit's own doc comment for the full
	# source citation, including the flagged Sheer Force gap.
	if damage > 0 and (move.sets_stealth_rock_on_hit or move.sets_spikes_on_hit):
		var hz_def_idx: int = _combatants.find(target)
		var hz_def_side: int = hz_def_idx / _active_per_side
		var hzsc: Dictionary = _side_conditions[hz_def_side]
		if move.sets_stealth_rock_on_hit:
			if hzsc["stealth_rock"]:
				move_effect_failed.emit(attacker, "already_stealth_rock")
			else:
				hzsc["stealth_rock"] = true
				hazard_set.emit(hz_def_side, "stealth_rock", 1)
		if move.sets_spikes_on_hit:
			if hzsc["spikes_layers"] >= 3:
				move_effect_failed.emit(attacker, "already_spikes_max")
			else:
				hzsc["spikes_layers"] += 1
				hazard_set.emit(hz_def_side, "spikes", hzsc["spikes_layers"])

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

	# [D4 Bundle 7] Beak Blast — CONTACT-gated (source's own dispatch sits
	# behind the SAME CanBattlerAvoidContactEffects early-return the whole
	# Protect-family/Rocky-Helmet function above uses) reactive burn on the
	# ATTACKER, whenever the TARGET's own chosen move this turn is Beak
	# Blast. Reuses ordinary status application (respects Fire-type/Water
	# Veil immunity normally). See MoveData.is_beak_blast's own doc comment
	# for the full source citation and the by-construction turn-order
	# argument.
	if damage > 0 and target.current_hp > 0 \
			and AbilityManager.move_triggers_contact_retaliation(attacker, move, ng_active):
		var bb_idx: int = _combatants.find(target)
		var bb_chosen: MoveData = _chosen_moves[bb_idx] \
				if bb_idx != -1 and bb_idx < _chosen_moves.size() else null
		if bb_chosen != null and bb_chosen.is_beak_blast:
			if StatusManager.try_apply_status(attacker, BattlePokemon.STATUS_BURN, null, null, ng_active):
				secondary_applied.emit(attacker, MoveData.SE_BURN)

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

	# [Bucket 4 cheapest singles] Rage's reactive half: raises the ATK of whoever
	# currently holds rage_active by +1 whenever THEY take a damaging hit — not
	# gated on which move caused it, so this lives here alongside the other
	# hit-reactive triggers rather than inside move.is_rage's own set-on-hit
	# block above. Excludes self-hits (e.g. confusion) and ally-hits (doubles),
	# matching source's own `battlerAtk != battlerDef && !IsBattlerAlly` checks;
	# `apply_stat_change` already no-ops correctly at the +6 cap, matching
	# source's own CompareStat pre-check.
	if target.rage_active and damage > 0 and target.current_hp > 0 \
			and attacker != target and _get_ally(target) != attacker:
		var rage_change: int = StatusManager.apply_stat_change(
				target, BattlePokemon.STAGE_ATK, 1, null, ng_active)
		if rage_change != 0:
			stat_stage_changed.emit(target, BattlePokemon.STAGE_ATK, rage_change)

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
					# [D4 CHEAP bundle]: Ingrain blocks Red Card's forced switch too,
					# same distinction as the Roar dispatch above.
					if not attacker.ingrain_active:
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
	# [D4 bundle 3] Recycle's own broader tracker — ANY item removed here,
	# berry or not, EXCEPT a popped Air Balloon (source's own "cannot be
	# restored by any means" carve-out — see MoveData.is_recycle's doc
	# comment for the full citation). Corrosive Gas's own identical
	# exclusion is moot — this project doesn't implement that move.
	if item.hold_effect != ItemManager.HOLD_EFFECT_AIR_BALLOON:
		mon.last_used_item = item
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
