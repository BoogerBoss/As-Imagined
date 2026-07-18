class_name BattleScreen
extends Control

# [M23.6] `class_name` added so battle_setup_screen.gd can call this
# script's static fixture-team builders (BattleScreen.build_fixture_opp
# _party(), etc.) without needing to instantiate a scene — a small,
# purely-additive declaration (registers a global identifier, changes no
# runtime behavior) rather than a rewrite; every other class in this
# project already uses class_name, this file was simply the one exception.
#
# [M23.1] Bare-bones battle screen — proves M23.0a's async pause/resume
# mechanism end-to-end through real UI. Two hardcoded teams (hand-built
# BattlePokemon fixtures, following the exact pattern established across
# this project's own test suite — see e.g. scenes/battle/ai_test.gd's
# `_make_mon`/`_load_move` helpers, quoted and cited in docs/m23_recon.md's
# M23.1 section). Side 0 is human-controlled via M23.0a's
# `set_human_controlled`/`queue_*`/`advance()` contract; side 1 is a
# TrainerAI (SMART tier) — already-proven, pre-existing logic, nothing new
# built here. SINGLES (not doubles) — confirmed as this engine's dominant/
# default mode (105 of 126 test files use a singles entry point vs. 21
# doubles) and the simpler fit for a "bare-bones" first UI pass; see
# docs/m23_recon.md for the full confirmation.
#
# [M23.2] Added a scrolling battle log (see the "Battle log" section below)
# — additive only, the M23.1 status/HP labels and button-driven flow are
# completely unchanged. Still no persistence, no team builder (M23.3/M23.4),
# no animation — plain Button/Label/RichTextLabel nodes, rebuilt from
# scratch on every state change rather than trying to manage node
# visibility toggling, since that's simplest for a "bare-bones, functional
# buttons only" screen.
#
# [M23.6] `_ready()` now checks BattleSetupContext (scripts/battle/core/
# battle_setup_context.gd) for externally-supplied teams BEFORE falling
# back to this file's own hardcoded Blaze/Torrent-vs-Leaf/Volt fixture —
# see `_ready()`'s own comment for the exact injection mechanism. This is
# the ONLY behavioral change `_ready()` itself gained; the queue_*()/
# advance() contract, the --autoplay path, and every button handler below
# are byte-for-byte unchanged. `_build_teams()` was split into two static
# functions (`build_fixture_player_party`/`build_fixture_opp_party`) so
# battle_setup_screen.gd's own "Quick Test" opponent option can reuse the
# EXACT same hardcoded Leaf/Volt data with zero duplication — `_build_teams
# ()` itself still exists, now just a 2-line instance wrapper calling both,
# preserving the fallback path's own behavior exactly.

const POTION_ITEM_ID := 28
const FULL_HEAL_ITEM_ID := 48
const X_ATTACK_ITEM_ID := 121

# [M23.2] Human-readable names for BattlePokemon.STAGE_* (stat_stage_changed's
# own stat_idx) — index-matched, not a Dictionary, since STAGE_* is already a
# dense 0-6 int enum.
const _STAGE_NAMES: Array[String] = [
	"Attack", "Defense", "Sp. Atk", "Sp. Def", "Speed", "Accuracy", "Evasion"]

# [M23.2 addendum] Display text for the field/side-wide signals wired below.
# Weather text deliberately ignores which Pokémon/move caused it (matches
# this screen's own "plain text, no filtering" scope) — dictionaries here
# key off the same string tags BattleManager's own signals already use
# ("spikes"/"reflect"/etc — see battle_manager.gd's own hazard_set/screen_set
# emit call sites), not new tags invented for this screen.
const _WEATHER_START_TEXT: Dictionary = {
	DamageCalculator.WEATHER_RAIN: "It started to rain!",
	DamageCalculator.WEATHER_SUN: "The sunlight turned harsh!",
	DamageCalculator.WEATHER_SANDSTORM: "A sandstorm kicked up!",
	DamageCalculator.WEATHER_HAIL: "It started to hail!",
	DamageCalculator.WEATHER_STRONG_WINDS: "Mysterious strong winds are protecting the sky!",
}
const _WEATHER_END_TEXT: Dictionary = {
	DamageCalculator.WEATHER_RAIN: "The rain stopped.",
	DamageCalculator.WEATHER_SUN: "The sunlight faded.",
	DamageCalculator.WEATHER_SANDSTORM: "The sandstorm subsided.",
	DamageCalculator.WEATHER_HAIL: "The hail stopped.",
	DamageCalculator.WEATHER_STRONG_WINDS: "The mysterious air currents faded.",
}
const _HAZARD_NAMES: Dictionary = {
	"spikes": "Spikes", "toxic_spikes": "Toxic Spikes",
	"stealth_rock": "Stealth Rock", "sticky_web": "Sticky Web",
}
const _SCREEN_NAMES: Dictionary = {
	"reflect": "Reflect", "light_screen": "Light Screen", "aurora_veil": "Aurora Veil",
}

# [ability_triggered message quality pass] Full lookup table for every
# effect_key value battle_manager.gd's own ability_triggered.emit(...) call
# sites actually produce — both literal string arguments (grepped directly)
# and the handful of dynamically-resolved ones (eot_dmg_tag ∈ {"solar_power",
# "dry_skin"}; contact_result["ability_name"] ∈ {"poison_touch",
# "pickpocket", "tangling_hair", "gooey", "iron_barbs", "rough_skin",
# "static", "flame_body", "poison_point", "cute_charm", "effect_spore",
# "wandering_spirit", "lingering_aroma", "mummy"}; retaliation["ability_name"]
# ∈ {"aftermath", "innards_out"}; attract_result ∈ {"oblivious", "aroma_veil"}
# — both already covered by their own literal-string entries below) — traced
# by reading every call site's surrounding source, not guessed from the key
# name alone. %s is always filled with _mon_label(pokemon) — the Pokémon
# battle_manager.gd itself attributes the trigger to (which is not always
# the "obvious" side — e.g. "damp" fires on the blocked ATTACKER, not the
# Damp holder; contact_result's poison_touch/pickpocket/etc. fire on
# whichever combatant _phase_move_execution resolved as this ability's own
# holder, correctly attacker- or defender-side per ability).
#
# Several keys are used across 2+ mechanically-different call sites, OR
# collapse multiple distinct abilities under one shared string (documented
# per-key in each call site's own comment) — where the key alone can't
# disambiguate WHICH sub-case fired, the message below uses the most
# accurate GENERIC phrasing that stays true for every sub-case, rather than
# guessing a specific one incorrectly (flagged, not silently narrowed):
# "guard_dog" (3 shapes: blocks a Roar/Whirlwind-forced switch, blocks a
# Red-Card-forced switch, OR reverses Intimidate into a self-buff on
# switch-in), "moody"/"defiant_competitive"/"download" (which stat, and
# raise-vs-lower for Moody, isn't in the key), "hydration_shed_skin"/
# "immunity_family_cure"/"rain_dish_ice_body_dry_skin"/"absorb_stat_boost"/
# "absorb_heal" (which of 2-6 bundled abilities fired isn't in the key),
# "dazzling_family"/"soundproof_bulletproof" (which of 2-3 bundled abilities
# blocked isn't in the key), "effect_spore" (which of poison/sleep/paralysis
# — the accompanying buffered secondary_applied line already shows the
# specific status right after this one, so the ability line itself doesn't
# need to repeat it).
const _ABILITY_TRIGGER_TEXT: Dictionary = {
	"absorb_heal": "%s's ability absorbed the move and restored HP!",
	"absorb_stat_boost": "%s's ability absorbed the move and boosted a stat!",
	"aftermath": "%s's Aftermath hurt the attacker as it fainted!",
	"anger_point": "%s's Anger Point maxed out its Attack!",
	"anger_shell": "%s's Anger Shell shuffled its stats!",
	"aroma_veil": "%s's Aroma Veil blocked the move!",
	"berserk": "%s's Berserk raised its Sp. Atk!",
	"cheek_pouch": "%s's Cheek Pouch restored some HP!",
	"color_change": "%s's Color Change changed its type to match the move!",
	"costar": "%s's Costar copied its ally's stat changes!",
	"cotton_down": "%s's Cotton Down lowered the attacker's Speed!",
	"cud_chew": "%s's Cud Chew re-triggered its berry!",
	"cursed_body": "%s's Cursed Body disabled the attacker's move!",
	"cute_charm": "%s's Cute Charm infatuated the attacker!",
	"damp": "%s's move was prevented by Damp!",
	"dazzling_family": "%s blocked the priority move with its ability!",
	"defiant_competitive": "%s's ability sharply raised a stat after being lowered!",
	"download": "%s's Download boosted one of its stats!",
	"dry_skin": "%s's Dry Skin was hurt by the sun!",
	"effect_spore": "%s's Effect Spore afflicted the attacker!",
	"flame_body": "%s's Flame Body burned the attacker!",
	"flash_fire_boosted": "%s's Flash Fire absorbed the Fire-type move!",
	"forecast": "%s's Forecast changed its type to match the weather!",
	"gooey": "%s's Gooey lowered the attacker's Speed!",
	"guard_dog": "%s's Guard Dog activated!",
	"harvest": "%s's Harvest regrew its held berry!",
	"healer": "%s's Healer cured its ally's status!",
	"hospitality": "%s's Hospitality healed its ally!",
	"hydration_shed_skin": "%s's ability cured its own status!",
	"immunity_family_cure": "%s's ability cured its own status!",
	"innards_out": "%s's Innards Out hurt the attacker as it fainted!",
	"insomnia_protects": "%s's ability kept it from falling asleep!",
	"intimidate": "%s's Intimidate lowered the opposing Pokémon's Attack!",
	"iron_barbs": "%s's Iron Barbs hurt the attacker!",
	"justified": "%s's Justified raised its Attack!",
	"lansat_berry": "%s's Lansat Berry sharply raised its critical-hit ratio!",
	"libero": "%s's Libero changed its type to match the move!",
	"lingering_aroma": "%s's Lingering Aroma overwrote the attacker's ability!",
	"liquid_ooze": "%s's Liquid Ooze turned the drain into damage!",
	"magic_bounce": "%s's Magic Bounce reflected the move!",
	"magic_coat": "%s's Magic Coat reflected the move!",
	"magician": "%s's Magician stole the target's item!",
	"micle_berry": "%s's Micle Berry boosted its accuracy!",
	"mirror_armor": "%s's Mirror Armor reflected the stat change!",
	"moody": "%s's Moody shuffled its stats!",
	"moxie": "%s's Moxie raised its Attack after a KO!",
	"mummy": "%s's Mummy overwrote the attacker's ability!",
	"natural_cure": "%s's Natural Cure cured its status as it left the field!",
	"oblivious": "%s's Oblivious blocked the move!",
	"oblivious_cure": "%s's Oblivious cured its infatuation!",
	"opportunist": "%s's Opportunist copied the opponent's stat rise!",
	"own_tempo": "%s's Own Tempo prevented the move's effect!",
	"own_tempo_cure": "%s's Own Tempo cured its confusion!",
	"pastel_veil": "%s's Pastel Veil cured its poison!",
	"pickpocket": "%s's Pickpocket stole the attacker's item!",
	"poison_heal": "%s's Poison Heal activated instead of taking damage!",
	"poison_point": "%s's Poison Point poisoned the attacker!",
	"poison_touch": "%s's Poison Touch poisoned its target!",
	"protean": "%s's Protean changed its type to match the move!",
	"rain_dish_ice_body_dry_skin": "%s's ability restored some HP!",
	"rattled": "%s's Rattled raised its Speed!",
	"receiver_power_of_alchemy": "%s copied its fainted ally's ability!",
	"regenerator": "%s's Regenerator restored some HP as it left the field!",
	"rough_skin": "%s's Rough Skin hurt the attacker!",
	"sand_spit": "%s's Sand Spit whipped up a sandstorm!",
	"screen_cleaner": "%s's Screen Cleaner cleared the screens!",
	"slow_start_ended": "%s's Slow Start wore off!",
	"solar_power": "%s's Solar Power drained its own HP in the sun!",
	"soundproof_bulletproof": "%s's ability made it immune to the move!",
	"speed_boost": "%s's Speed Boost raised its Speed!",
	"stamina": "%s's Stamina raised its Defense!",
	"static": "%s's Static paralyzed the attacker!",
	"steadfast": "%s's Steadfast raised its Speed!",
	"steam_engine": "%s's Steam Engine sharply raised its Speed!",
	"sticky_hold": "%s's Sticky Hold prevented the item from being stolen!",
	"sturdy": "%s's Sturdy endured the hit!",
	"supersweet_syrup": "%s's Supersweet Syrup lowered the opposing Pokémon's evasiveness!",
	"symbiosis": "%s's Symbiosis passed its item to its ally!",
	"synchronize": "%s's Synchronize passed the status back!",
	"tangling_hair": "%s's Tangling Hair lowered the attacker's Speed!",
	"thermal_exchange": "%s's Thermal Exchange raised its Attack!",
	"toxic_debris": "%s's Toxic Debris scattered Toxic Spikes at the attacker's feet!",
	"trace": "%s's Trace copied the opponent's ability!",
	"wandering_spirit": "%s's Wandering Spirit swapped abilities with the attacker!",
	"water_compaction": "%s's Water Compaction raised its Defense!",
	"weak_armor": "%s's Weak Armor lowered its Defense and raised its Speed!",
	"wonder_guard": "%s's Wonder Guard blocked the non-super-effective hit!",
}

@onready var _bm: BattleManager = $BattleManager
@onready var _status_label: Label = $VBox/StatusLabel
@onready var _side0_label: Label = $VBox/Side0Label
@onready var _side1_label: Label = $VBox/Side1Label
@onready var _log_label: RichTextLabel = $VBox/LogLabel
@onready var _button_area: VBoxContainer = $VBox/ButtonArea

# [M23.11 Phase 4a] Visual battle stage -- additive alongside the existing
# text-based UI above, not a replacement (Side0Label/Side1Label/LogLabel
# stay exactly as they are, per this phase's own explicit scope).
@onready var _opponent_sprite: TextureRect = $BattleStage/OpponentSprite
@onready var _player_sprite: TextureRect = $BattleStage/PlayerSprite

# [M23.11 Phase 4b] Real health-box art replacing Phase 4a's plain
# ProgressBar placeholders -- see _setup_health_ui()'s own doc comment for
# the asset structure this relies on.
@onready var _opponent_health_bg: TextureRect = $BattleStage/OpponentHealthGroup/Background
@onready var _opponent_status_icon: TextureRect = $BattleStage/OpponentHealthGroup/StatusIcon
@onready var _opponent_hp_label: TextureRect = $BattleStage/OpponentHealthGroup/HpLabel
@onready var _opponent_hp_fill: TextureProgressBar = $BattleStage/OpponentHealthGroup/HpFill
@onready var _player_health_bg: TextureRect = $BattleStage/PlayerHealthGroup/Background
@onready var _player_status_icon: TextureRect = $BattleStage/PlayerHealthGroup/StatusIcon
@onready var _player_hp_label: TextureRect = $BattleStage/PlayerHealthGroup/HpLabel
@onready var _player_hp_fill: TextureProgressBar = $BattleStage/PlayerHealthGroup/HpFill

var _opponent_status_atlas: AtlasTexture
var _player_status_atlas: AtlasTexture

# [M23.11 Phase 4c] Idle-bob animation -- front sprite (opponent) ONLY, see
# _setup_health_ui() area's own doc comment on _next_anim_frame() for why
# the back sprite (player) is deliberately excluded.
@onready var _opponent_anim_timer: Timer = $OpponentAnimTimer
var _opponent_anim_frame: int = 0

var _player_party: BattleParty
var _opp_party: BattleParty
var _winner_side: int = -1

# [M23.2 addendum] Log-ordering fix — see _flush_pending_effect_lines()'s own
# doc comment for the full mechanism.
var _pending_effect_lines: Array[String] = []

# Which sub-menu the MOVE_SELECTION main-action screen is currently showing.
# Irrelevant during SWITCH_PROMPT, which always shows the bench-picker
# directly (a mandatory faint replacement, no "back" option).
enum Menu { MAIN, SWITCH, ITEM }
var _menu: Menu = Menu.MAIN


func _ready() -> void:
	_setup_health_ui()
	_opponent_anim_timer.timeout.connect(_on_opponent_anim_timer_timeout)

	# [M23.6 injection point] BattleSetupContext is a plain static-var
	# holder (scripts/battle/core/battle_setup_context.gd, class_name
	# BattleSetupContext extends RefCounted) — GDScript class-level statics
	# persist for the whole process regardless of scene tree, so
	# battle_setup_screen.gd can populate it, call change_scene_to_file to
	# this scene, and this fresh instance's own _ready() picks the data up
	# here with zero coupling beyond the one shared static-holder class.
	# Consumed (cleared) immediately after reading so a LATER direct launch
	# of this scene (e.g. re-running it from the editor, or this exact
	# --autoplay sweep invocation below) never accidentally reuses stale
	# data from an earlier setup. When nothing is pending — the case for
	# every pre-existing caller, including the sweep's own direct
	# `battle_screen.tscn` invocation — this falls through to the exact
	# same hardcoded-fixture path M23.1 always used.
	if BattleSetupContext.has_pending():
		_player_party = BattleSetupContext.player_party
		_opp_party = BattleSetupContext.opp_party
		BattleSetupContext.clear()
	else:
		_build_teams()

	var ai := TrainerAI.new()
	ai.tier = TrainerAI.Tier.SMART
	_bm.set_trainer_ai(1, ai)
	_bm.set_human_controlled(0, true)
	_bm.battle_ended.connect(_on_battle_ended)

	# [M23.2] Wired unconditionally — interactive AND autoplay both populate
	# the log (see _wire_log_signals's own doc comment for the reasoning on
	# why autoplay isn't special-cased here).
	_wire_log_signals()

	# start_battle_with_parties() calls advance() internally — this already
	# stalls at MOVE_SELECTION (side 0 is human-controlled, nothing queued
	# yet) before this function returns.
	_bm.start_battle_with_parties(_player_party, _opp_party)

	# [Autoplay] No existing CLI-arg/env-var convention exists anywhere in
	# this codebase for a headless-vs-interactive toggle — every one of the
	# 137 pre-existing test scenes is ALWAYS in "test mode," so there was
	# nothing to match. This is a deliberate, explicit CLI flag (not
	# implicit `DisplayServer.get_name() == "headless"` detection), matching
	# the task's own explicit ask — flagged here as the proposed convention
	# for any future scene needing the same toggle. Checked via
	# `OS.get_cmdline_args()` (includes trailing custom args regardless of
	# whether Godot recognizes them), not `get_cmdline_user_args()`, since
	# either works identically for an unrecognized flag like this one and
	# the former needs no `--` separator convention to be established.
	if "--autoplay" in OS.get_cmdline_args():
		_run_autoplay()
		return

	_refresh_ui()


# ── Autoplay (headless plumbing check for the test sweep) ──────────────────
# Bypasses waiting on real Button.pressed signals entirely — drives the exact
# same queue_*()/advance() contract the interactive handlers below use, always
# picking the first legal option (a move with PP remaining, else whatever's
# queued falls through to the engine's own Struggle-forcing logic; the first
# available bench slot for a mandatory faint replacement). Deliberately dumb/
# fast/deterministic: this proves the async loop completes headlessly through
# the real production code path, not that the AI plays well.

func _run_autoplay() -> void:
	var guard := 0
	while _bm.get_phase() != BattleManager.BattlePhase.BATTLE_END and guard < 200:
		guard += 1
		match _bm.get_phase():
			BattleManager.BattlePhase.MOVE_SELECTION:
				var mon: BattlePokemon = _player_party.get_active()
				var move_idx := _first_usable_move_index(mon)
				_bm.queue_move_targeted(0, max(move_idx, 0), 1)
			BattleManager.BattlePhase.SWITCH_PROMPT:
				var slot := _first_switch_slot()
				if slot >= 0:
					_bm.queue_replacement_for(0, slot)
			_:
				pass
		_bm.advance()

	var reached_end: bool = _bm.get_phase() == BattleManager.BattlePhase.BATTLE_END
	var valid_winner: bool = _winner_side == 0 or _winner_side == 1
	var passed := 1 if (reached_end and valid_winner) else 0
	print("battle_screen_autoplay: %d/1 passed" % passed)
	if passed == 0:
		print("FAILED")
	get_tree().quit(0 if passed == 1 else 1)


func _first_usable_move_index(mon: BattlePokemon) -> int:
	for i in range(mon.moves.size()):
		if mon.moves[i] != null and mon.current_pp[i] > 0:
			return i
	return -1


func _first_switch_slot() -> int:
	for i in range(_player_party.members.size()):
		if not _player_party.active_indices.has(i) and not _player_party.members[i].fainted:
			return i
	return -1


func _on_battle_ended(winner_side: int) -> void:
	_winner_side = winner_side
	_log("You win!" if winner_side == 0 else "You lose!")


# ── Battle log [M23.2, broadened in the M23.2 addendum] ────────────────────
# Additive only — the M23.1 status/HP labels and every button/menu code path
# above are completely unchanged. Wired to the EXISTING signal surface
# (BattleManager emits ~110 signals in total; nothing new was added here,
# per this task's own explicit constraint) rather than every one of them.
# M23.2 wired ~16 signals covering moves/damage/faints/switches/items/status.
# [M23.2 addendum] broadens coverage with 13 more: weather_set/weather_expired/
# weather_damage, hazard_set/hazard_damage/hazard_status_applied/
# hazard_absorbed/hazards_cleared, screen_set/screen_expired/screens_broken,
# ability_triggered/ability_healed — these were excluded from M23.2 only
# because this screen's fixed 2v2 roster (no items/abilities/hazard-setting
# moves in the original build) didn't happen to trigger them, NOT because
# they're doubles-specific — confirmed by direct signature inspection: every
# one of the 13 is keyed by `side: int` (0/1) or a single `pokemon`, with no
# ally-slot/field-position parameter, so all are singles-safe. Still
# deliberately NOT wired: genuine doubles-only signals (spread/ally-targeting
# events) and the long tail of move-specific one-off signals (Bide,
# Substitute, delayed-effect scheduling, etc.) — none reachable by this
# screen's current fixed roster; adding coverage for any of them later is a
# one-line `_bm.SIGNAL.connect(...)` addition, not a redesign.
#
# `ability_triggered`'s own `effect_key` is a slug string with ~50 distinct
# values across the whole ability roster (e.g. "moxie", "guard_dog",
# "cud_chew") — rather than hand-authoring bespoke text for each (which would
# also silently go stale the next time a new ability ships), this screen
# formats it generically ("<Mon>'s <effect key with underscores replaced by
# spaces> activated!") — readable, always in sync with the real signal
# surface, though less polished than a per-ability phrase. Flagged as a
# reasonable simplification, not silently under-scoped.
#
# [Autoplay decision] Wired UNCONDITIONALLY, in both the interactive and
# `--autoplay` paths — no branching on the flag at all. Reasoning: the task
# itself named "useful for debugging failures" as a reason FOR populating
# during autoplay, and connecting ~16 signal handlers plus appending short
# text lines has no meaningful performance cost (a typical autoplay run is
# ~13 turns; string concatenation on a RichTextLabel is not the kind of
# per-frame cost this project's own performance-sensitive code — the
# battle engine itself — needs to worry about). Keeping one code path
# (always wired) is also simpler than adding a second conditional branch
# for a negligible-cost feature.

func _wire_log_signals() -> void:
	_bm.move_executed.connect(_on_log_move_executed)
	_bm.move_missed.connect(func(attacker: BattlePokemon, _reason: String):
		_log("%s's attack missed!" % _mon_label(attacker)))
	_bm.move_missed_target.connect(func(_attacker: BattlePokemon, target: BattlePokemon, _reason: String):
		_log("%s avoided the attack!" % _mon_label(target)))
	_bm.pokemon_fainted.connect(func(mon: BattlePokemon):
		_log("%s fainted!" % _mon_label(mon)))
	_bm.pokemon_switched_out.connect(func(mon: BattlePokemon, _side: int):
		_log("%s was withdrawn!" % _mon_label(mon)))
	_bm.pokemon_switched_in.connect(func(mon: BattlePokemon, _side: int, _slot: int):
		_log("Go, %s!" % _mon_label(mon)))
	_bm.stat_stage_changed.connect(_on_log_stat_stage_changed)
	_bm.secondary_applied.connect(_on_log_secondary_applied)
	_bm.status_cured.connect(func(mon: BattlePokemon):
		_log("%s's status was cured!" % _mon_label(mon)))
	_bm.party_status_cured.connect(func(mon: BattlePokemon):
		_log("%s's status was cured!" % _mon_label(mon)))
	_bm.item_action_used.connect(func(user: BattlePokemon, item: ItemData, _target: BattlePokemon):
		_log("%s used %s!" % [_mon_label(user), item.item_name]))
	_bm.item_healed.connect(func(mon: BattlePokemon, amount: int):
		_log("%s recovered %d HP!" % [_mon_label(mon), amount]))
	_bm.recoil_damage.connect(func(mon: BattlePokemon, amount: int):
		_log("%s was hurt by recoil! (%d damage)" % [_mon_label(mon), amount]))
	_bm.drain_heal.connect(func(mon: BattlePokemon, amount: int):
		_log("%s had its energy drained! (%d HP)" % [_mon_label(mon), amount]))
	_bm.status_damage.connect(func(mon: BattlePokemon, amount: int):
		_log("%s was hurt by its status! (%d damage)" % [_mon_label(mon), amount]))
	_bm.confusion_self_hit.connect(func(mon: BattlePokemon, amount: int):
		_log("%s hurt itself in confusion! (%d damage)" % [_mon_label(mon), amount]))

	# [M23.2 addendum] Weather.
	_bm.weather_set.connect(func(_by_pokemon: BattlePokemon, weather_type: int):
		_log(_WEATHER_START_TEXT.get(weather_type, "The weather changed!")))
	_bm.weather_expired.connect(func(weather_type: int):
		_log(_WEATHER_END_TEXT.get(weather_type, "The weather returned to normal.")))
	_bm.weather_damage.connect(func(mon: BattlePokemon, amount: int):
		_log("%s was buffeted by the weather! (%d damage)" % [_mon_label(mon), amount]))

	# [M23.2 addendum] Hazards.
	_bm.hazard_set.connect(func(side: int, hazard_name: String, _layers: int):
		_log("%s was set on %s side!" % [_HAZARD_NAMES.get(hazard_name, hazard_name), _side_label(side)]))
	_bm.hazard_damage.connect(func(mon: BattlePokemon, amount: int, hazard_name: String):
		_log("%s was hurt by %s! (%d damage)" % [_mon_label(mon), _HAZARD_NAMES.get(hazard_name, hazard_name), amount]))
	_bm.hazard_status_applied.connect(func(mon: BattlePokemon, status: int):
		_log("%s was %s by the hazard!" % [_mon_label(mon), _status_name(status)]))
	_bm.hazard_absorbed.connect(func(side: int, hazard_name: String):
		_log("%s was absorbed on %s side!" % [_HAZARD_NAMES.get(hazard_name, hazard_name), _side_label(side)]))
	_bm.hazards_cleared.connect(func(side: int, hazard_name: String):
		_log("%s was cleared from %s side!" % [_HAZARD_NAMES.get(hazard_name, hazard_name), _side_label(side)]))

	# [M23.2 addendum] Screens.
	_bm.screen_set.connect(func(side: int, screen_name: String):
		_log("%s went up on %s side!" % [_SCREEN_NAMES.get(screen_name, screen_name), _side_label(side)]))
	_bm.screen_expired.connect(func(side: int, screen_name: String):
		_log("%s wore off on %s side!" % [_SCREEN_NAMES.get(screen_name, screen_name), _side_label(side)]))
	_bm.screens_broken.connect(func(side: int):
		_log("The screens shattered on %s side!" % _side_label(side)))

	# [ability_triggered message quality pass] Readable per-key text, not a
	# generic underscore-to-space formatter — see _on_log_ability_triggered.
	_bm.ability_triggered.connect(_on_log_ability_triggered)
	_bm.ability_healed.connect(_on_log_ability_healed)


func _on_log_move_executed(attacker: BattlePokemon, _defender: BattlePokemon,
		move: MoveData, damage: int) -> void:
	var text: String
	if damage > 0:
		text = "%s used %s! (%d damage)" % [_mon_label(attacker), move.move_name, damage]
	else:
		text = "%s used %s!" % [_mon_label(attacker), move.move_name]
	# [M23.2 addendum] Append this cause line directly (bypassing _log()'s own
	# auto-flush) so it lands BEFORE any already-buffered effect line, then
	# flush those effects after it — see _flush_pending_effect_lines()'s doc
	# comment for why this reordering is needed at all.
	_log_label.text += text + "\n"
	_flush_pending_effect_lines()


func _on_log_stat_stage_changed(target: BattlePokemon, stat_idx: int, actual_change: int) -> void:
	if actual_change == 0:
		return
	var stat_name: String = _STAGE_NAMES[stat_idx] if stat_idx < _STAGE_NAMES.size() else "stat"
	var verb := "rose" if actual_change > 0 else "fell"
	_pending_effect_lines.append("%s's %s %s!" % [_mon_label(target), stat_name, verb])


func _on_log_secondary_applied(target: BattlePokemon, effect: int) -> void:
	var text := ""
	match effect:
		MoveData.SE_BURN:
			text = "was burned"
		MoveData.SE_FREEZE:
			text = "was frozen solid"
		MoveData.SE_PARALYSIS:
			text = "was paralyzed"
		MoveData.SE_SLEEP:
			text = "fell asleep"
		MoveData.SE_POISON:
			text = "was poisoned"
		MoveData.SE_TOXIC:
			text = "was badly poisoned"
		MoveData.SE_CONFUSION:
			text = "became confused"
		MoveData.SE_FLINCH:
			text = "flinched"
		_:
			return
	_pending_effect_lines.append("%s %s!" % [_mon_label(target), text])


func _on_log_ability_healed(mon: BattlePokemon, amount: int) -> void:
	if amount > 0:
		_log("%s recovered %d HP from its ability!" % [_mon_label(mon), amount])
	elif amount < 0:
		_log("%s was hurt by its ability! (%d damage)" % [_mon_label(mon), -amount])


# [ability_triggered message quality pass] Looks up a readable message from
# _ABILITY_TRIGGER_TEXT; falls back to the old generic underscore-to-space
# formatter for any effect_key not in the table (requirement 4 — nothing
# silently breaks if a key is missed here or a new one is added to
# battle_manager.gd later).
func _on_log_ability_triggered(mon: BattlePokemon, effect_key: String) -> void:
	var template: Variant = _ABILITY_TRIGGER_TEXT.get(effect_key, null)
	if template != null:
		_log(template % _mon_label(mon))
	else:
		_log("%s's %s activated!" % [_mon_label(mon), effect_key.replace("_", " ")])


func _status_name(status: int) -> String:
	match status:
		BattlePokemon.STATUS_BURN: return "burned"
		BattlePokemon.STATUS_FREEZE: return "frozen solid"
		BattlePokemon.STATUS_PARALYSIS: return "paralyzed"
		BattlePokemon.STATUS_POISON: return "poisoned"
		BattlePokemon.STATUS_TOXIC: return "badly poisoned"
		BattlePokemon.STATUS_SLEEP: return "put to sleep"
		_: return "afflicted"


func _side_label(side: int) -> String:
	return "your" if side == 0 else "the foe's"


func _mon_label(mon: BattlePokemon) -> String:
	if _player_party.members.has(mon):
		return "Your %s" % mon.species.species_name
	return "Foe %s" % mon.species.species_name


# [M23.2 addendum] Log-ordering fix. secondary_applied/stat_stage_changed can
# fire BEFORE their own causing move_executed within BattleManager's pure
# single-target status-move dispatch (battle_manager.gd's own
# "elif move.secondary_effect != MoveData.SE_NONE:"/"if move.stat_change_stat
# >= 0:" branches both emit their effect signal, THEN emit move_executed at
# the end of the same synchronous block — confirmed by direct source read,
# not assumed) — this is what produced the M23.2-flagged "paralyzed" line
# appearing before its own "used Thunder Wave!" line. The DAMAGING-hit path
# (_do_damaging_hit) does NOT have this problem — move_executed already fires
# immediately after HP is reduced, with any post-hit secondary effects
# (SE_FLINCH, on-hit stat drops, etc.) emitted afterward in that function, so
# no reordering is needed there.
#
# Fix, scoped narrowly per this task's own "simplest mechanism, no large
# architectural change" instruction: _on_log_secondary_applied/
# _on_log_stat_stage_changed no longer log immediately — they buffer their
# line into _pending_effect_lines instead. _log() (the sink every OTHER
# handler still calls directly) flushes that buffer BEFORE appending its own
# new line, so a buffered line is never silently dropped or permanently
# stuck — it just surfaces at the very next log event, in its original
# relative position, UNLESS that next event is specifically the causing
# move_executed. _on_log_move_executed is the one exception: it appends its
# own cause line first (bypassing _log()'s auto-flush), THEN flushes —
# swapping the order only in exactly the case that needed swapping.
func _flush_pending_effect_lines() -> void:
	for line in _pending_effect_lines:
		_log_label.text += line + "\n"
	_pending_effect_lines.clear()


func _log(text: String) -> void:
	_flush_pending_effect_lines()
	_log_label.text += text + "\n"


# ── Team fixtures ────────────────────────────────────────────────────────
# Exact pattern followed from scenes/battle/ai_test.gd's own `_make_mon`
# (PokemonSpecies.new() + manually-set base stats/types, then
# BattlePokemon.from_species(sp, level, nature, ivs)) and `_load_move`
# (load a real move .tres by ID) helpers — hand-built fixtures, no
# PokemonRegistry/species-data-converter involved (that's M23.3/M23.4,
# explicitly out of scope here).

static func _make_mon(mon_name: String, type1: int, type2: int = TypeChart.TYPE_NONE,
		hp: int = 180, atk: int = 80, def_stat: int = 80,
		spatk: int = 80, spdef: int = 80, spd: int = 80) -> BattlePokemon:
	var sp := PokemonSpecies.new()
	sp.species_name = mon_name
	sp.types.append(type1)
	if type2 != TypeChart.TYPE_NONE:
		sp.types.append(type2)
	sp.base_hp = hp
	sp.base_attack = atk
	sp.base_defense = def_stat
	sp.base_sp_attack = spatk
	sp.base_sp_defense = spdef
	sp.base_speed = spd
	return BattlePokemon.from_species(sp, 50, BattlePokemon.NATURE_HARDY, [0, 0, 0, 0, 0, 0])


static func _load_move(id: int) -> MoveData:
	return load("res://data/moves/move_%04d.tres" % id) as MoveData


# [M23.6] Split out of the former single `_build_teams()` so
# battle_setup_screen.gd's "Quick Test" opponent option can reuse the exact
# same hardcoded Leaf/Volt data with zero duplication/drift risk. Static —
# no instance state involved, matching `_make_mon`/`_load_move` above.
static func build_fixture_player_party() -> BattleParty:
	var blaze := _make_mon("Blaze", TypeChart.TYPE_FIRE, TypeChart.TYPE_NONE,
			180, 90, 70, 100, 70, 90)
	blaze.add_move(_load_move(52))   # Ember
	blaze.add_move(_load_move(53))   # Flamethrower
	blaze.add_move(_load_move(98))   # Quick Attack
	blaze.add_move(_load_move(14))   # Swords Dance

	var torrent := _make_mon("Torrent", TypeChart.TYPE_WATER, TypeChart.TYPE_NONE,
			190, 80, 80, 90, 90, 70)
	torrent.add_move(_load_move(55))  # Water Gun
	torrent.add_move(_load_move(57))  # Surf
	torrent.add_move(_load_move(44))  # Bite
	torrent.add_move(_load_move(33))  # Tackle

	var party := BattleParty.new()
	party.members = [blaze, torrent]
	party.active_indices = [0]
	return party


static func build_fixture_opp_party() -> BattleParty:
	var leaf := _make_mon("Leaf", TypeChart.TYPE_GRASS, TypeChart.TYPE_NONE,
			180, 85, 75, 85, 75, 85)
	leaf.add_move(_load_move(22))   # Vine Whip
	leaf.add_move(_load_move(75))   # Razor Leaf
	leaf.add_move(_load_move(45))   # Growl
	leaf.add_move(_load_move(33))   # Tackle

	var volt := _make_mon("Volt", TypeChart.TYPE_ELECTRIC, TypeChart.TYPE_NONE,
			170, 75, 65, 95, 75, 100)
	volt.add_move(_load_move(85))   # Thunderbolt
	volt.add_move(_load_move(86))   # Thunder Wave
	volt.add_move(_load_move(98))   # Quick Attack
	volt.add_move(_load_move(231))  # Iron Tail

	var party := BattleParty.new()
	party.members = [leaf, volt]
	party.active_indices = [0]
	return party


func _build_teams() -> void:
	_player_party = build_fixture_player_party()
	_opp_party = build_fixture_opp_party()


# ── UI rendering ─────────────────────────────────────────────────────────
# Rebuilt from scratch on every state change rather than toggling
# visibility on pre-declared nodes — simplest correct approach for a
# bare-bones, no-animation screen whose available actions genuinely change
# shape (move/switch/item vs. a mandatory bench-picker vs. nothing at
# battle end).

# [M23.11 Phase 4a] SpriteRegistry itself is a pure lookup (returns null
# for an unresolvable dex, e.g. dex 0 -- battle_screen.gd's own hardcoded
# fixture teams, built via plain PokemonSpecies.new() rather than
# PokemonFactory, never set national_dex_num). This screen decides the
# fallback: dex 0's own "unknown" silhouette sprite, resolved through the
# exact same registry call rather than a separately-preloaded texture.
func _sprite_or_fallback_front(dex: int, frame: int = 0) -> Texture2D:
	var tex := SpriteRegistry.get_front(dex, frame)
	return tex if tex != null else SpriteRegistry.get_front(0, frame)


func _sprite_or_fallback_back(dex: int) -> Texture2D:
	var tex := SpriteRegistry.get_back(dex)
	return tex if tex != null else SpriteRegistry.get_back(0)


# [M23.11 Phase 4c] Idle-bob animation, front sprite (opponent) only.
#
# Front-only, not both sprites -- confirmed via direct source inspection
# (see SpriteRegistry.get_back()'s own doc comment) that back sprites
# don't use frame-swap idle animation in the real engine at all (a single
# positional `backAnimId` effect on ONE static frame, no `backAnimFrames`
# array field exists in the species struct) -- this is a deliberate,
# source-grounded narrowing of this phase's own "convert the static
# frame-0 Pokémon sprites" framing to the one sprite that actually has
# real 2-frame idle content to alternate.
#
# 0.5s per frame -- matches the task's own suggested default and is a
# reasonable approximation of typical GBA idle pacing; the real engine's
# own per-species ANIMCMD_FRAME durations vary slightly (e.g. Bulbasaur's
# own frontAnimFrames holds each frame for 30 ticks at a 60Hz-ish tick
# rate, close to 0.5s) but weren't replicated exactly per-species, since
# this phase's own scope is the frame alternation itself, not
# reproducing each species' individual timing.
#
# A fainted Pokémon's sprite freezes on its current frame rather than
# continuing to alternate -- consistent with Phase 4a's own fade-on-faint
# treatment (a half-transparent sprite that kept bobbing would look
# wrong; real games don't animate a fainted sprite either). Pure/static
# so a smoke test can call it directly without a live Timer/scene tree,
# matching _status_icon_row()'s own precedent from Phase 4b.
static func _next_anim_frame(current_frame: int, is_fainted: bool) -> int:
	if is_fainted:
		return current_frame
	return 1 - current_frame


func _on_opponent_anim_timer_timeout() -> void:
	if _opp_party == null:
		return
	var side1_mon: BattlePokemon = _opp_party.get_active()
	if side1_mon == null:
		return
	_opponent_anim_frame = _next_anim_frame(_opponent_anim_frame, side1_mon.fainted)
	_opponent_sprite.texture = _sprite_or_fallback_front(
			side1_mon.species.national_dex_num, _opponent_anim_frame)


# [M23.11 Phase 4a] Green/yellow/red HP-fraction threshold -- applied via
# TextureProgressBar.tint_progress as of Phase 4b (was modulate on a plain
# ProgressBar before); the function itself is unchanged, only what
# property consumes its return value changed.
func _hp_bar_color(current: int, max_hp: int) -> Color:
	if max_hp <= 0:
		return Color(1, 1, 1)
	var frac := float(current) / float(max_hp)
	if frac > 0.5:
		return Color(0.2, 0.8, 0.2)
	elif frac > 0.2:
		return Color(0.9, 0.8, 0.1)
	return Color(0.9, 0.2, 0.2)


# [M23.11 Phase 4b] hpbar.png (assets/sprites/battle_ui/interface/) is a
# single 96x8 sheet: a fixed "HP" text glyph in its own left 24x8 region,
# followed by a 72x8 notched fill region -- confirmed via direct pixel
# inspection, not assumed. These are sliced as two SEPARATE AtlasTextures
# (not one texture_progress covering the whole sheet) specifically so the
# "HP" label stays fully visible at any HP fraction -- a single combined
# region would incorrectly shrink the label itself as HP drops, since
# TextureProgressBar's fill clipping operates on its own texture's full
# width.
const _HP_LABEL_REGION := Rect2(0, 0, 24, 8)
const _HP_FILL_REGION := Rect2(24, 0, 72, 8)

# [M23.11 Phase 4b] status.png/status2.png (assets/sprites/battle_ui/
# interface/) are both the same 24x48 sheet -- 6 stacked 24x8 status
# badges (PSN/PAR/SLP/FRZ/BRN/FRB), confirmed via direct pixel inspection.
# status2.png (not status.png) is used for the opponent side, per the
# reference engine's own source comment (src/graphics.c:722) confirming
# status2/3/4.png are "duplicate sets of graphics... for the
# opponent/partner Pokémon" -- functionally identical art, just a
# different source file, matching that comment's own intent rather than
# reusing status.png for both sides.
const _STATUS_ICON_SIZE := Vector2(24, 8)


# [M23.11 Phase 4b] Maps a BattlePokemon.STATUS_* value to its 0-indexed
# row within the 6-row status icon sheet, or -1 for "no icon" (STATUS_
# NONE). STATUS_TOXIC deliberately shares STATUS_POISON's row -- the
# sprite sheet has no separate "badly poisoned" badge, matching the real
# game's own HUD. Static (not an instance method) so a smoke test can call
# it directly without instantiating the scene, matching this file's own
# existing static-helper convention (_make_mon/_load_move/
# build_fixture_player_party).
static func _status_icon_row(status: int) -> int:
	match status:
		BattlePokemon.STATUS_POISON, BattlePokemon.STATUS_TOXIC:
			return 0
		BattlePokemon.STATUS_PARALYSIS:
			return 1
		BattlePokemon.STATUS_SLEEP:
			return 2
		BattlePokemon.STATUS_FREEZE:
			return 3
		BattlePokemon.STATUS_BURN:
			return 4
		_:
			return -1


# [M23.11 Phase 4b] One-time wiring, called from _ready() -- every texture
# assigned here is FIXED (the health-box frame, the HP label/fill regions)
# except the two status-icon AtlasTextures, which are created once here
# and have their own .region mutated per-refresh in _update_status_icon()
# (safe: each is a freshly-created instance this script alone owns, not a
# cached/shared Resource from load(), so mutating its .region can't leak
# into any other consumer).
func _setup_health_ui() -> void:
	_opponent_health_bg.texture = load("res://assets/sprites/battle_ui/interface/healthbox_singles_opponent.png")
	_player_health_bg.texture = load("res://assets/sprites/battle_ui/interface/healthbox_singles_player.png")

	var hpbar_sheet: Texture2D = load("res://assets/sprites/battle_ui/interface/hpbar.png")

	var hp_label_atlas := AtlasTexture.new()
	hp_label_atlas.atlas = hpbar_sheet
	hp_label_atlas.region = _HP_LABEL_REGION
	_opponent_hp_label.texture = hp_label_atlas
	_player_hp_label.texture = hp_label_atlas

	var hp_fill_atlas := AtlasTexture.new()
	hp_fill_atlas.atlas = hpbar_sheet
	hp_fill_atlas.region = _HP_FILL_REGION
	_opponent_hp_fill.texture_progress = hp_fill_atlas
	_player_hp_fill.texture_progress = hp_fill_atlas
	_opponent_hp_fill.fill_mode = TextureProgressBar.FILL_LEFT_TO_RIGHT
	_player_hp_fill.fill_mode = TextureProgressBar.FILL_LEFT_TO_RIGHT

	var opponent_status_sheet: Texture2D = load("res://assets/sprites/battle_ui/interface/status2.png")
	_opponent_status_atlas = AtlasTexture.new()
	_opponent_status_atlas.atlas = opponent_status_sheet
	_opponent_status_atlas.region = Rect2(Vector2.ZERO, _STATUS_ICON_SIZE)
	_opponent_status_icon.texture = _opponent_status_atlas

	var player_status_sheet: Texture2D = load("res://assets/sprites/battle_ui/interface/status.png")
	_player_status_atlas = AtlasTexture.new()
	_player_status_atlas.atlas = player_status_sheet
	_player_status_atlas.region = Rect2(Vector2.ZERO, _STATUS_ICON_SIZE)
	_player_status_icon.texture = _player_status_atlas


func _update_status_icon(icon_node: TextureRect, atlas: AtlasTexture, status: int) -> void:
	var row := _status_icon_row(status)
	if row < 0:
		icon_node.visible = false
		return
	icon_node.visible = true
	atlas.region = Rect2(0, row * _STATUS_ICON_SIZE.y, _STATUS_ICON_SIZE.x, _STATUS_ICON_SIZE.y)


func _refresh_ui() -> void:
	for child in _button_area.get_children():
		child.queue_free()

	var side0_mon: BattlePokemon = _player_party.get_active()
	var side1_mon: BattlePokemon = _opp_party.get_active()
	_side0_label.text = "%s  HP: %d/%d%s" % [
			side0_mon.species.species_name, side0_mon.current_hp, side0_mon.max_hp,
			" (fainted)" if side0_mon.fainted else ""]
	_side1_label.text = "%s  HP: %d/%d%s" % [
			side1_mon.species.species_name, side1_mon.current_hp, side1_mon.max_hp,
			" (fainted)" if side1_mon.fainted else ""]

	# [M23.11 Phase 4a] Visual sprite/HP-bar sync -- _refresh_ui() is
	# already the single call point that runs after every state change
	# (move resolution, switches, item use, battle end), so no new
	# BattleManager signal wiring is needed for this.
	#
	# [M23.11 Phase 4c] Every state-driven refresh (a switch, a new battle,
	# etc.) resets the idle-bob back to frame 0 -- a genuinely new/changed
	# Pokémon shouldn't pick up mid-bob on whatever frame the PREVIOUS
	# occupant happened to be on. The timer-driven _on_opponent_anim_timer
	# _timeout() continues alternating from this reset point independently.
	_opponent_anim_frame = 0
	_opponent_sprite.texture = _sprite_or_fallback_front(side1_mon.species.national_dex_num, _opponent_anim_frame)
	_opponent_sprite.modulate = Color(1, 1, 1, 0.3) if side1_mon.fainted else Color(1, 1, 1, 1)
	_opponent_hp_fill.max_value = side1_mon.max_hp
	_opponent_hp_fill.value = side1_mon.current_hp
	_opponent_hp_fill.tint_progress = _hp_bar_color(side1_mon.current_hp, side1_mon.max_hp)
	_update_status_icon(_opponent_status_icon, _opponent_status_atlas, side1_mon.status)

	_player_sprite.texture = _sprite_or_fallback_back(side0_mon.species.national_dex_num)
	_player_sprite.modulate = Color(1, 1, 1, 0.3) if side0_mon.fainted else Color(1, 1, 1, 1)
	_player_hp_fill.max_value = side0_mon.max_hp
	_player_hp_fill.value = side0_mon.current_hp
	_player_hp_fill.tint_progress = _hp_bar_color(side0_mon.current_hp, side0_mon.max_hp)
	_update_status_icon(_player_status_icon, _player_status_atlas, side0_mon.status)

	if _bm.get_phase() == BattleManager.BattlePhase.BATTLE_END:
		_status_label.text = ("You win!" if _winner_side == 0 else "You lose!")
		_build_battle_end_buttons()
		return

	if _bm.get_phase() == BattleManager.BattlePhase.SWITCH_PROMPT:
		_status_label.text = "%s fainted! Choose a replacement." % side0_mon.species.species_name
		_build_switch_buttons(true)
		return

	# MOVE_SELECTION (the only other phase this screen ever stalls at,
	# since side 0 is the only human-controlled side).
	match _menu:
		Menu.SWITCH:
			_status_label.text = "Choose a Pokémon to switch in."
			_build_switch_buttons(false)
		Menu.ITEM:
			_status_label.text = "Choose an item."
			_build_item_buttons()
		_:
			_status_label.text = "Choose an action for %s." % side0_mon.species.species_name
			_build_main_menu(side0_mon)


# [M23.7 — real integration gap found and closed] Before this session,
# reaching BATTLE_END was a genuine dead end: `_refresh_ui()` clears
# `_button_area` at the top of every call and, on this specific branch,
# returned immediately afterward with nothing added back — confirmed via a
# real button-press walkthrough (not assumed) that this left ZERO buttons
# on screen, no way to play again or navigate anywhere, forcing the
# process to be killed to escape. Closed with the smallest addition that
# fits this file's own established "rebuild button_area from scratch"
# pattern exactly — no new .tscn nodes needed, since `_button_area` is
# already fully dynamic. Routes to battle_setup_screen.tscn (not straight
# back into another battle) so win/loss result stays visible for a beat
# and the player can freely reconfigure format/teams before their next
# battle, mirroring the same screen every OTHER path into a battle already
# goes through.
func _build_battle_end_buttons() -> void:
	var play_again_btn := Button.new()
	play_again_btn.text = "Play Again"
	play_again_btn.pressed.connect(_on_play_again_pressed)
	_button_area.add_child(play_again_btn)


func _on_play_again_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/battle/battle_setup_screen.tscn")


func _build_main_menu(side0_mon: BattlePokemon) -> void:
	for i in range(side0_mon.moves.size()):
		var move: MoveData = side0_mon.moves[i]
		if move == null:
			continue
		var btn := Button.new()
		btn.text = "%s (PP %d/%d)" % [move.move_name, side0_mon.current_pp[i], move.pp]
		btn.disabled = side0_mon.current_pp[i] <= 0
		btn.pressed.connect(_on_move_pressed.bind(i))
		_button_area.add_child(btn)

	var switch_btn := Button.new()
	switch_btn.text = "Switch"
	switch_btn.disabled = not _player_party.has_valid_switch_target()
	switch_btn.pressed.connect(func():
		_menu = Menu.SWITCH
		_refresh_ui())
	_button_area.add_child(switch_btn)

	var item_btn := Button.new()
	item_btn.text = "Item"
	item_btn.pressed.connect(func():
		_menu = Menu.ITEM
		_refresh_ui())
	_button_area.add_child(item_btn)


func _build_switch_buttons(is_forced_replacement: bool) -> void:
	for i in range(_player_party.members.size()):
		if _player_party.active_indices.has(i) or _player_party.members[i].fainted:
			continue
		var mon: BattlePokemon = _player_party.members[i]
		var btn := Button.new()
		btn.text = "%s  HP: %d/%d" % [mon.species.species_name, mon.current_hp, mon.max_hp]
		btn.pressed.connect(_on_switch_pressed.bind(i, is_forced_replacement))
		_button_area.add_child(btn)

	if not is_forced_replacement:
		var back_btn := Button.new()
		back_btn.text = "Back"
		back_btn.pressed.connect(func():
			_menu = Menu.MAIN
			_refresh_ui())
		_button_area.add_child(back_btn)


func _build_item_buttons() -> void:
	var potion_btn := Button.new()
	potion_btn.text = "Potion (heal)"
	potion_btn.pressed.connect(_on_item_pressed.bind(POTION_ITEM_ID))
	_button_area.add_child(potion_btn)

	var full_heal_btn := Button.new()
	full_heal_btn.text = "Full Heal (cure status)"
	full_heal_btn.pressed.connect(_on_item_pressed.bind(FULL_HEAL_ITEM_ID))
	_button_area.add_child(full_heal_btn)

	var x_attack_btn := Button.new()
	x_attack_btn.text = "X Attack (+1 Attack)"
	x_attack_btn.pressed.connect(_on_item_pressed.bind(X_ATTACK_ITEM_ID))
	_button_area.add_child(x_attack_btn)

	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.pressed.connect(func():
		_menu = Menu.MAIN
		_refresh_ui())
	_button_area.add_child(back_btn)


# ── Input handlers — the M23.0a external contract in action ────────────────
# Every handler below is the exact queue_*() + advance() pattern confirmed
# in docs/m23_recon.md (M23.0a's proof scene and M23.0b's own translation
# check): supply the human's action via the pre-existing queue API, call
# advance() to resume the paused battle loop, then re-render from whatever
# phase advance() left the battle in.

func _on_move_pressed(move_index: int) -> void:
	_bm.queue_move_targeted(0, move_index, 1)  # 1 = the opponent's active combatant (singles)
	_bm.advance()
	_menu = Menu.MAIN
	_refresh_ui()


func _on_switch_pressed(slot: int, is_forced_replacement: bool) -> void:
	if is_forced_replacement:
		_bm.queue_replacement_for(0, slot)
	else:
		_bm.queue_switch_for(0, slot)
	_bm.advance()
	_menu = Menu.MAIN
	_refresh_ui()


func _on_item_pressed(item_id: int) -> void:
	_bm.queue_item_for(0, item_id)
	_bm.advance()
	_menu = Menu.MAIN
	_refresh_ui()
