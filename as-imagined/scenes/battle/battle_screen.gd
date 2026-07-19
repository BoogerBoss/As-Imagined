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

# [M23.11 Phase 4e] DialogueLabel (addons/dialogue_manager/dialogue_label.gd)
# rather than a plain RichTextLabel -- see _setup_message_box()'s own doc
# comment for the full reasoning. DialogueLabel `extends RichTextLabel` and
# adds nothing to its behavior unless its own `dialogue_line`/`type_out()`/
# `skip_typing()` API is used -- confirmed via direct source read, not
# assumed -- so every existing `.text +=` append site below (_log(),
# _flush_pending_effect_lines(), _on_log_move_executed()) is completely
# untouched: same property, same accumulating-scroll behavior, same
# queuing/sequencing/timing as every prior phase.
@onready var _log_label: DialogueLabel = $VBox/LogLabel
@onready var _button_area: VBoxContainer = $VBox/ButtonArea

# [M23.11 Phase 4a] Visual battle stage -- additive alongside the existing
# text-based UI above, not a replacement (Side0Label/Side1Label/LogLabel
# stay exactly as they are, per this phase's own explicit scope).
@onready var _background_rect: TextureRect = $BattleStage/Background
@onready var _opponent_sprite: TextureRect = $BattleStage/OpponentSprite
@onready var _player_sprite: TextureRect = $BattleStage/PlayerSprite

# [M23.11 Phase 5c] Hit-effect nodes are spawned/freed here at runtime --
# the LAST child of BattleStage in battle_screen.tscn, so every sprite/
# health-box added above it in the tree draws underneath for free (same
# "later sibling draws on top" convention Phase 5a's own Background doc
# comment already established), while VBox (message box/menu), a LATER
# sibling of BattleStage itself at the BattleScreen root, still always
# draws on top of anything here -- no z_index needed either direction.
@onready var _effect_layer: Control = $BattleStage/EffectLayer

# [M23.11 Phase 5c] Root nodes of any hit effect currently mid-animation --
# each entry removes itself the moment its own Tween finishes and frees it
# naturally (see the tree_exited.connect() at each spawn site), so this
# never grows across a real playthrough. Only exists so _on_battle_ended can
# force an immediate, SYNCHRONOUS free() of anything still animating right
# when the battle ends -- found necessary because --autoplay's own
# get_tree().quit() (called the instant BATTLE_END is reached, see
# _run_autoplay()) fires before a merely-queued queue_free() would ever
# actually run, which without this left Tween-owned TextureRect/
# AtlasTexture nodes alive at process exit (a real, new ObjectDB-leak
# warning this phase's own regression check caught -- confirmed absent on
# the pre-Phase-5c code via a direct git-stash comparison).
var _active_hit_effect_nodes: Array = []

# [M23.11 Phase 4b] Real health-box art replacing Phase 4a's plain
# ProgressBar placeholders -- see _setup_health_ui()'s own doc comment for
# the asset structure this relies on.
@onready var _opponent_health_group: Control = $BattleStage/OpponentHealthGroup
@onready var _opponent_health_bg: TextureRect = $BattleStage/OpponentHealthGroup/Background
@onready var _opponent_status_icon: TextureRect = $BattleStage/OpponentHealthGroup/StatusIcon
@onready var _opponent_hp_label: TextureRect = $BattleStage/OpponentHealthGroup/HpLabel
@onready var _opponent_hp_fill: TextureProgressBar = $BattleStage/OpponentHealthGroup/HpFill
@onready var _player_health_group: Control = $BattleStage/PlayerHealthGroup
@onready var _player_health_bg: TextureRect = $BattleStage/PlayerHealthGroup/Background
@onready var _player_status_icon: TextureRect = $BattleStage/PlayerHealthGroup/StatusIcon
@onready var _player_hp_label: TextureRect = $BattleStage/PlayerHealthGroup/HpLabel
@onready var _player_hp_fill: TextureProgressBar = $BattleStage/PlayerHealthGroup/HpFill

var _opponent_status_atlas: AtlasTexture
var _player_status_atlas: AtlasTexture

# [M23.11 Phase 4d] Doubles visual layer — 2 sprite/health-box groups per
# side, reusing the already-pulled healthbox_doubles_* art (see
# _setup_health_ui()'s own doc comment for the asset structure this relies
# on). Kept as plain (untyped) Array, not Array[TextureRect] — this
# project's own documented GDScript gotcha (typed-Array literal assignment
# can silently fail) applies to `@onready var x: Array[T] = [$A, $B]`
# specifically; a plain Array sidesteps it entirely since these are only
# ever indexed 0/1 within this script, never passed anywhere a strict
# element type matters. Populated once in _setup_health_ui() by
# _collect_doubles_nodes() — singles' own existing single-node fields
# above are completely untouched, this is purely additive.
var _opp_sprites_d: Array = []
var _opp_groups_d: Array = []
var _opp_bg_d: Array = []
var _opp_status_icon_d: Array = []
var _opp_status_atlas_d: Array = [null, null]
var _opp_hp_label_d: Array = []
var _opp_hp_fill_d: Array = []
# [M23.11 Phase 4d] Idle-bob frame state, one per doubles opponent slot —
# mirrors the singles-only `_opponent_anim_frame` below but per-slot, so
# one opponent fainting doesn't freeze/desync its still-live teammate's
# own animation (each slot's frame only advances/freezes based on THAT
# slot's own `mon.fainted`, exactly like the singles case already does).
var _opp_anim_frame_d: Array = [0, 0]

var _ply_sprites_d: Array = []
var _ply_groups_d: Array = []
var _ply_bg_d: Array = []
var _ply_status_icon_d: Array = []
var _ply_status_atlas_d: Array = [null, null]
var _ply_hp_label_d: Array = []
var _ply_hp_fill_d: Array = []

# [M23.11 Phase 4d] Set once in _ready() from BattleSetupContext.is_doubles
# (captured into the local `is_doubles_battle` there already) — governs
# which of the singles vs. doubles node sets is shown/refreshed for the
# whole battle (never changes mid-battle, so this is a plain one-shot flag
# rather than something recomputed every _refresh_ui() call).
var _is_doubles_mode: bool = false

# [M23.11 Phase 4c] Idle-bob animation -- front sprite (opponent) ONLY, see
# _setup_health_ui() area's own doc comment on _next_anim_frame() for why
# the back sprite (player) is deliberately excluded.
#
# [M25b bugfix] `one_shot = true` on this Timer in battle_screen.tscn (was
# unset, i.e. Godot's own default of continuous/repeating) -- confirmed via
# direct reference-source inspection (pokeemerald_expansion's own
# sprite.c: the AnimCmd interpreter sets `animEnded = TRUE` and stops
# advancing when it hits the ANIMCMD_END sentinel a species' own
# frontAnimFrames sequence ends with, no jump-back-to-start; and
# DoMonFrontSpriteAnimation in pokemon.c triggers it once, on a Pokémon's
# own appearance, not on a recurring timer) that the real games play this
# as a brief one-shot double-bob, not a forever-looping ambient "alive"
# indicator -- Phase 4c's own prior framing of this as deliberately
# continuous was an assumption that session made, not something it
# verified against source (unlike the front-only/frame-value parts of
# this same doc comment, which do cite source). Deliberately NOT expanded
# into a real per-switch-in replay/reveal system here -- that remains its
# own, separately-scoped future item; this is just "stop looping."
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
#
# [M23.11 Phase 4f] TARGET_SELECT — shown after picking a move that needs a
# foe/ally choice among 2+ live candidates (see BattleManager.get_live_targets'
# own doc comment for exactly which moves this applies to).
#
# [M25b] Real top-level Fight/Item/Switch/Run menu, replacing the old flat
# "every move button plus Switch/Item inline" MAIN screen (renamed TOP here)
# with a genuine two-tier structure matching the real games: TOP shows
# exactly the 4 top-level options; picking Fight drops into the NEW FIGHT
# state (the move list, previously shown directly on MAIN, unchanged in
# content — just moved one tier deeper). SWITCH/ITEM/TARGET_SELECT are
# otherwise unchanged in shape; only their own "Back" targets moved (see
# each button's own call site) to route to TOP (or, for TARGET_SELECT
# specifically, back to FIGHT — the immediate previous step — so picking a
# different move doesn't require re-entering Fight from TOP).
enum Menu { TOP, FIGHT, SWITCH, ITEM, TARGET_SELECT }
var _menu: Menu = Menu.TOP

# [M23.11 Phase 4f] _menu above is deliberately kept as ONE flat variable,
# not an Array[Menu] sized to num_active() field slots, even though this
# phase's own scoping report raised that as the expected shape — this
# screen only ever DISPLAYS one field slot's menu at a time (sequential
# decision-making, matching the reference engine's own real per-battler
# selection flow, not simultaneous side-by-side pickers), so there's no
# risk of one slot's menu state bleeding into another's. `_slot_acted`
# tracks which of _player_party's active field slots have already
# submitted an action THIS move-selection turn; `_current_action_field_slot
# ()` derives which slot _menu currently applies to. Reset together
# whenever a fresh turn is detected (see _ensure_slot_tracking_for_new_turn).
# In singles (num_active() == 1) this is a 1-element always-resetting array
# — _menu's own behavior is untouched from before this phase.
var _slot_acted: Array[bool] = []

# [M23.11 Phase 4f] Which move (by index into the acting mon's own moves
# array) is awaiting a target choice — only meaningful while
# _menu == Menu.TARGET_SELECT. -1 otherwise.
var _pending_move_index: int = -1


func _ready() -> void:
	_setup_health_ui()
	_setup_message_box()
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
	# [M23.11 Phase 4f] _is_doubles governs which BattleManager entry point
	# _ready() calls at the very end — captured here (before .clear() wipes
	# it) rather than read fresh later, matching how _player_party/_opp_party
	# are already consumed. Defaults false: every pre-existing caller
	# (the hardcoded fixture fallback below, and battle_setup_screen.gd's own
	# still-singles-only Launch button) leaves this at its default, so this
	# branch is unreachable except via a caller that deliberately sets
	# BattleSetupContext.is_doubles = true first (currently: this phase's own
	# scratch screenshot drivers and test suite only — see
	# docs/m23_recon.md's Phase 4f entry for why the real Doubles toggle
	# itself is NOT wired to this yet).
	# [M23.11 Phase 5a] Read the SAME way is_doubles_battle is above — a
	# local captured before .clear() wipes the static holder, not read
	# fresh later. "" (unset) covers every pre-existing caller (the
	# hardcoded-fixture fallback below, any direct/--autoplay launch of
	# this scene, and battle_setup_screen.gd callers from before this
	# session) and resolves to _apply_background()'s own documented
	# default rather than leaving the stage with no background at all.
	var background_id := ""
	var is_doubles_battle := false
	if BattleSetupContext.has_pending():
		_player_party = BattleSetupContext.player_party
		_opp_party = BattleSetupContext.opp_party
		is_doubles_battle = BattleSetupContext.is_doubles
		background_id = BattleSetupContext.background_id
		BattleSetupContext.clear()
	else:
		_build_teams()
	_apply_background(background_id)

	# [M23.11 Phase 4d] One-shot node-set toggle — singles nodes stay exactly
	# as before (visible, unchanged) when not in doubles; when in doubles,
	# they're hidden entirely and the D0/D1 node pairs (already default-
	# hidden in the .tscn) take over via _refresh_doubles_side()'s own
	# per-slot visibility below. Set here, once, rather than every
	# _refresh_ui() call, since the format never changes mid-battle.
	_is_doubles_mode = is_doubles_battle
	if _is_doubles_mode:
		_opponent_sprite.visible = false
		_opponent_health_group.visible = false
		_player_sprite.visible = false
		_player_health_group.visible = false

	var ai := TrainerAI.new()
	ai.tier = TrainerAI.Tier.SMART
	_bm.set_trainer_ai(1, ai)
	_bm.set_human_controlled(0, true)
	_bm.battle_ended.connect(_on_battle_ended)

	# [M23.2] Wired unconditionally — interactive AND autoplay both populate
	# the log (see _wire_log_signals's own doc comment for the reasoning on
	# why autoplay isn't special-cased here).
	_wire_log_signals()

	# [M23.11 Phase 5c] A SEPARATE connect() on the same move_executed signal
	# _wire_log_signals() already listens to above -- Godot signals support
	# multiple independent handlers, so this is purely additive and cannot
	# change _on_log_move_executed's own behavior/ordering. Wired
	# unconditionally (interactive + --autoplay both), matching every other
	# signal wire-up in this file.
	_bm.move_executed.connect(_on_hit_effect_move_executed)

	# start_battle_with_parties()/start_battle_doubles() both call advance()
	# internally — this already stalls at MOVE_SELECTION (side 0 is human-
	# controlled, nothing queued yet for at least one active slot) before
	# this function returns.
	if is_doubles_battle:
		_bm.start_battle_doubles(_player_party, _opp_party)
	else:
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
	_clear_active_hit_effects()


# [M23.11 Phase 5c] See _active_hit_effect_nodes' own doc comment.
# Synchronous free() (not queue_free()) -- must take effect before
# --autoplay's immediate get_tree().quit() on this same call stack.
func _clear_active_hit_effects() -> void:
	for node: Node in _active_hit_effect_nodes.duplicate():
		if is_instance_valid(node):
			# Kill the Tween BEFORE freeing its target node -- freeing first
			# left an already-queued tween_callback() step trying to run
			# against a freed node next frame (a real bug this phase's own
			# --autoplay smoke run caught: "Lambda capture ... was freed").
			var tween: Variant = node.get_meta("_hit_effect_tween", null)
			if tween is Tween and (tween as Tween).is_valid():
				(tween as Tween).kill()
			node.free()
	_active_hit_effect_nodes.clear()


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


# ── Hit effects [M23.11 Phase 5c] ───────────────────────────────────────────
# Wired as a second, independent handler on move_executed (see _ready()'s own
# connect() call) -- kept entirely separate from _on_log_move_executed/the
# message-log pipeline above, both so a bug here can't touch log text and so
# this can be reasoned about as one self-contained addition. Every function
# below is non-blocking: no `await` anywhere in this section, so a spawned
# effect's Tween runs independently of BattleManager's own turn/message
# sequencing -- the very next move_executed (or any other signal) fires and
# is handled immediately regardless of whether a previous effect is still
# animating. HitEffectRegistry (scripts/battle/core/hit_effect_registry.gd)
# owns the pure "which texture(s)" lookup; only node creation/animation
# lives here, matching how _apply_background() consumes
# BattleBackgroundRegistry.

func _on_hit_effect_move_executed(attacker: BattlePokemon, defender: BattlePokemon,
		move: MoveData, _damage: int) -> void:
	if move == null:
		return
	# Self-targeting moves (Swords Dance, Rest, etc.) resolve defender ==
	# attacker at the BattleManager layer already -- target_mon naturally
	# becomes the attacker in that case with no special-casing needed here.
	# A null defender (a handful of pure-field-effect moves) falls back to
	# the attacker's own position rather than skipping the effect outright.
	var target_mon: BattlePokemon = defender if defender != null else attacker
	var target_node := _sprite_node_for(target_mon)
	if target_node == null:
		return

	var move_id := HitEffectRegistry.move_id_of(move)
	match move_id:
		HitEffectRegistry.MOVE_ID_FLAMETHROWER:
			_play_multi_stage_strip_effect([HitEffectRegistry.get_flamethrower_texture()], target_node)
		HitEffectRegistry.MOVE_ID_THUNDER:
			_play_multi_stage_strip_effect(HitEffectRegistry.get_thunder_textures(), target_node)
		HitEffectRegistry.MOVE_ID_SURF:
			var attacker_is_player: bool = _player_party.members.has(attacker)
			_play_surf_effect(attacker_is_player, target_node)
		_:
			var tex := HitEffectRegistry.get_generic_texture(move)
			if tex != null:
				_play_multi_stage_strip_effect([tex], target_node)


# Resolves which field slot `mon` currently occupies within `party`'s own
# active_indices, for doubles targeting -- mirrors _refresh_doubles_side's
# own party.get_active_at(slot) reads. Defaults to slot 0 if not found
# (shouldn't happen for a mon that just executed/received a move, but keeps
# this a total function rather than returning -1 into an array index).
func _field_slot_for(mon: BattlePokemon, party: BattleParty) -> int:
	for slot in range(party.num_active()):
		if party.get_active_at(slot) == mon:
			return slot
	return 0


# Singles-vs-doubles-aware sprite-node lookup, reusing Phase 4d's own
# party/slot model rather than adding any new BattleManager-side targeting
# concept. Player-vs-opponent side is resolved the exact same way
# _mon_label() already does (_player_party.members.has(mon)).
func _sprite_node_for(mon: BattlePokemon) -> Control:
	if mon == null:
		return null
	var is_player: bool = _player_party.members.has(mon)
	if not _is_doubles_mode:
		return _player_sprite if is_player else _opponent_sprite
	var party: BattleParty = _player_party if is_player else _opp_party
	var slot := _field_slot_for(mon, party)
	var sprites: Array = _ply_sprites_d if is_player else _opp_sprites_d
	return sprites[slot] as Control


# Generic + Flamethrower + Thunder all share this ONE renderer -- Flamethrower
# is a single self-contained strip (the same shape as any generic pick, per
# 5b's own finding), and Thunder is just two strips played back to back on
# the same node (see HitEffectRegistry.get_thunder_textures()'s own doc
# comment on why no runtime palette compositing is actually needed). Surf is
# the one genuinely different shape -- see _play_surf_effect below.
#
# Builds one Tween per call: steps through every texture's own frame count
# (via HitEffectRegistry.compute_frame_layout), holds briefly, fades out,
# frees the node. A single-frame source (most of the 21 generic picks) still
# goes through this same loop with frame_count == 1 -- a one-iteration
# no-op step followed immediately by the hold, not a special case.
func _play_multi_stage_strip_effect(textures: Array, target: Control,
		frame_time: float = 0.05, hold_time: float = 0.12) -> void:
	if textures.is_empty() or target == null or _effect_layer == null:
		return
	var first_layout: Dictionary = HitEffectRegistry.compute_frame_layout(textures[0].get_size())
	var frame_size: Vector2 = first_layout["frame_size"]

	var rect := TextureRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.size = frame_size
	var atlas := AtlasTexture.new()
	atlas.atlas = textures[0]
	atlas.region = Rect2(Vector2.ZERO, frame_size)
	rect.texture = atlas
	_effect_layer.add_child(rect)
	rect.global_position = target.get_global_rect().get_center() - frame_size / 2.0

	var tween := create_tween()
	rect.set_meta("_hit_effect_tween", tween)
	_active_hit_effect_nodes.append(rect)
	rect.tree_exited.connect(func(): _active_hit_effect_nodes.erase(rect))
	for tex: Texture2D in textures:
		var layout: Dictionary = HitEffectRegistry.compute_frame_layout(tex.get_size())
		var f_size: Vector2 = layout["frame_size"]
		var f_count: int = layout["frame_count"]
		var vertical: bool = layout["vertical"]
		for f in range(f_count):
			var origin: Vector2 = Vector2(0, f * f_size.y) if vertical else Vector2(f * f_size.x, 0)
			tween.tween_callback(func():
				atlas.atlas = tex
				atlas.region = Rect2(origin, f_size)
				rect.size = f_size
				rect.global_position = target.get_global_rect().get_center() - f_size / 2.0)
			tween.tween_interval(frame_time)
	tween.tween_interval(hold_time)
	tween.tween_property(rect, "modulate:a", 0.0, 0.15)
	tween.tween_callback(rect.queue_free)


# Surf's genuinely different shape (see HitEffectRegistry.get_surf_texture's
# own doc comment + 5b's own "the session's real surprise" finding): a full
# uncropped 512x256 BG-layer canvas, not a sprite strip. Rendered as a
# clip_contents Control window (sized smaller than the canvas) with the full
# canvas panning horizontally underneath it -- "a brief scrolling pan across
# the canvas," confirmed as the natural fit for this asset's own shape
# rather than trying to force it through the same frame-slicing path as
# every sprite-shaped effect above.
func _play_surf_effect(attacker_is_player: bool, target: Control) -> void:
	if target == null or _effect_layer == null:
		return
	var tex := HitEffectRegistry.get_surf_texture(attacker_is_player)
	if tex == null:
		return

	var window_size := Vector2(120, 90)
	var clip := Control.new()
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.size = window_size
	_effect_layer.add_child(clip)
	clip.global_position = target.get_global_rect().get_center() - window_size / 2.0

	var pan_rect := TextureRect.new()
	pan_rect.texture = tex
	pan_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pan_rect.size = tex.get_size()
	clip.add_child(pan_rect)
	var canvas_size: Vector2 = tex.get_size()
	var start_x := 0.0
	var end_x := -(canvas_size.x - window_size.x)
	# NOT vertically centered -- confirmed via direct visual inspection this
	# session (the real screenshot-verification pass) that the actual
	# curling-wave detail sits in a narrow band near one edge of the
	# 512x256 canvas, with a large flat-blue field filling the rest (a
	# vertically-centered window landed squarely in that flat field,
	# showing a featureless blue rectangle instead of the wave) -- AND that
	# the two pulled variants are mirrored, not identically laid out:
	# water_player.png's crest sits at the TOP, water_opponent.png's sits
	# at the BOTTOM (thematically sensible -- the player's own wave crests
	# away from their side of the screen, toward the opponent, and vice
	# versa), so the anchor itself must follow attacker_is_player rather
	# than using one fixed offset for both.
	var y_offset := 0.0 if attacker_is_player else -(canvas_size.y - window_size.y)
	pan_rect.position = Vector2(start_x, y_offset)

	var tween := create_tween()
	clip.set_meta("_hit_effect_tween", tween)
	_active_hit_effect_nodes.append(clip)
	clip.tree_exited.connect(func(): _active_hit_effect_nodes.erase(clip))
	tween.tween_property(pan_rect, "position:x", end_x, 0.6).set_trans(Tween.TRANS_LINEAR)
	tween.tween_interval(0.1)
	tween.tween_property(clip, "modulate:a", 0.0, 0.15)
	tween.tween_callback(clip.queue_free)


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
	# [M23.11 Phase 4d] Doubles branch, checked first and returning early —
	# the singles branch below is completely untouched. Each doubles slot's
	# frame/fainted state is tracked and advanced fully independently (see
	# _opp_anim_frame_d's own doc comment), so one opponent fainting freezes
	# only its own sprite, never its still-live teammate's.
	if _is_doubles_mode:
		var active_count := _opp_party.num_active()
		for slot in range(2):
			if slot >= active_count:
				continue
			var mon: BattlePokemon = _opp_party.get_active_at(slot)
			_opp_anim_frame_d[slot] = _next_anim_frame(_opp_anim_frame_d[slot], mon.fainted)
			_opp_sprites_d[slot].texture = _sprite_or_fallback_front(
					mon.species.national_dex_num, _opp_anim_frame_d[slot])
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


# [M23.11 Phase 5a] One-time wiring, called from _ready(). BattleStage's
# own "Background" TextureRect (see battle_screen.tscn — the FIRST child
# of BattleStage, so every sprite/health-box/etc. added after it in the
# tree draws on top for free, no z_index needed) is left with no texture
# at scene-authoring time, since the actual choice depends on runtime
# picker/hand-off state, not something fixed at .tscn-authoring time —
# assigned here instead. "building" is the documented default for an
# unset/unresolvable id: it's the same background real source's own
# LoadBattleEnvironmentGfx() falls back to (BATTLE_ENVIRONMENT_PLAIN,
# which itself shares BUILDING's tiles — see gen_battle_backgrounds.py's
# own doc comment), and it's also BattleBackgroundRegistry's own
# alphabetically-first id, matching the manual picker's own default
# selection in battle_setup_screen.gd — so a direct/--autoplay launch of
# this scene (no picker ever run) renders the identical background a
# freshly-opened setup screen's own default pick would produce.
const _DEFAULT_BACKGROUND_ID := "building"


func _apply_background(background_id: String) -> void:
	var id := background_id if not background_id.is_empty() else _DEFAULT_BACKGROUND_ID
	var tex := BattleBackgroundRegistry.get_background_texture(id)
	if tex == null and id != _DEFAULT_BACKGROUND_ID:
		tex = BattleBackgroundRegistry.get_background_texture(_DEFAULT_BACKGROUND_ID)
	_background_rect.texture = tex


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

	# [M23.11 Phase 4d] Doubles node collection + wiring — see the field
	# declarations' own doc comment (near _is_doubles_mode) for why these are
	# plain Arrays. hpbar_sheet's two fixed-region atlases (hp_label_atlas/
	# hp_fill_atlas) are safely SHARED across every node here (singles' own
	# existing code already shares them between the opponent and player
	# nodes) since their .region never changes after creation. Status icons
	# are the one thing that CANNOT share an atlas instance across slots —
	# two doubles opponents can have different statuses simultaneously, and
	# mutating one shared atlas's .region would corrupt every node
	# displaying it — so each of the 4 doubles slots gets its own freshly-
	# created AtlasTexture, matching the singles opponent/player split
	# already established, just doubled.
	_opp_sprites_d = [$BattleStage/OpponentSpriteD0, $BattleStage/OpponentSpriteD1]
	_opp_groups_d = [$BattleStage/OpponentHealthGroupD0, $BattleStage/OpponentHealthGroupD1]
	_opp_bg_d = [$BattleStage/OpponentHealthGroupD0/Background, $BattleStage/OpponentHealthGroupD1/Background]
	_opp_status_icon_d = [$BattleStage/OpponentHealthGroupD0/StatusIcon, $BattleStage/OpponentHealthGroupD1/StatusIcon]
	_opp_hp_label_d = [$BattleStage/OpponentHealthGroupD0/HpLabel, $BattleStage/OpponentHealthGroupD1/HpLabel]
	_opp_hp_fill_d = [$BattleStage/OpponentHealthGroupD0/HpFill, $BattleStage/OpponentHealthGroupD1/HpFill]

	_ply_sprites_d = [$BattleStage/PlayerSpriteD0, $BattleStage/PlayerSpriteD1]
	_ply_groups_d = [$BattleStage/PlayerHealthGroupD0, $BattleStage/PlayerHealthGroupD1]
	_ply_bg_d = [$BattleStage/PlayerHealthGroupD0/Background, $BattleStage/PlayerHealthGroupD1/Background]
	_ply_status_icon_d = [$BattleStage/PlayerHealthGroupD0/StatusIcon, $BattleStage/PlayerHealthGroupD1/StatusIcon]
	_ply_hp_label_d = [$BattleStage/PlayerHealthGroupD0/HpLabel, $BattleStage/PlayerHealthGroupD1/HpLabel]
	_ply_hp_fill_d = [$BattleStage/PlayerHealthGroupD0/HpFill, $BattleStage/PlayerHealthGroupD1/HpFill]

	var doubles_opponent_bg: Texture2D = load("res://assets/sprites/battle_ui/interface/healthbox_doubles_opponent.png")
	var doubles_player_bg: Texture2D = load("res://assets/sprites/battle_ui/interface/healthbox_doubles_player.png")

	for i in range(2):
		_opp_bg_d[i].texture = doubles_opponent_bg
		_opp_hp_label_d[i].texture = hp_label_atlas
		_opp_hp_fill_d[i].texture_progress = hp_fill_atlas
		_opp_hp_fill_d[i].fill_mode = TextureProgressBar.FILL_LEFT_TO_RIGHT
		var opp_atlas_d := AtlasTexture.new()
		opp_atlas_d.atlas = opponent_status_sheet
		opp_atlas_d.region = Rect2(Vector2.ZERO, _STATUS_ICON_SIZE)
		_opp_status_atlas_d[i] = opp_atlas_d
		_opp_status_icon_d[i].texture = opp_atlas_d

		_ply_bg_d[i].texture = doubles_player_bg
		_ply_hp_label_d[i].texture = hp_label_atlas
		_ply_hp_fill_d[i].texture_progress = hp_fill_atlas
		_ply_hp_fill_d[i].fill_mode = TextureProgressBar.FILL_LEFT_TO_RIGHT
		var ply_atlas_d := AtlasTexture.new()
		ply_atlas_d.atlas = player_status_sheet
		ply_atlas_d.region = Rect2(Vector2.ZERO, _STATUS_ICON_SIZE)
		_ply_status_atlas_d[i] = ply_atlas_d
		_ply_status_icon_d[i].texture = ply_atlas_d


# [M23.11 Phase 4e] text_window/std.png's own fixed (non-stretching) corner
# size, in the TEXTURE's own pixel space -- confirmed via direct pixel
# inspection (numpy scanline), not assumed from the filename: pixels 0-1 are
# background-key green, 2-3 a dark border, 4 a light transition, then a flat
# 14x14 white interior (pixels 5-18), mirrored on the far edge. 5px on each
# side covers green+border+transition, leaving exactly the flat interior to
# stretch -- matches StyleBoxTexture's own texture_margin_* semantics.
const _MESSAGE_BOX_MARGIN := 5.0

# [M23.11 Phase 4e] The exact background-key color found in EVERY
# text_window/*.png file inspected (std.png, message_box.png, name_box.png,
# signpost.png, and all 20 numbered frame-style preview tiles) -- confirmed
# via direct pixel read, not assumed: RGB (115, 205, 164), alpha=255 (a
# fully OPAQUE mint green, not real PNG transparency -- these files have no
# "transparency" info in their PNG metadata at all). This is a classic
# GBA-era sprite-sheet background/canvas-key color from the original
# pokeemerald_expansion extraction, not an intentionally-visible color —
# using it as-is would render a visible green blob around every corner.
# Color-keyed to real alpha=0 at runtime (see _color_keyed_texture below)
# rather than pre-processing/overwriting the pulled asset file on disk, so
# the original pull stays byte-for-byte available for any future reprocessing.
const _MESSAGE_BOX_KEY_COLOR := Color8(115, 205, 164, 255)

# [M23.11 Phase 4e] Pure function (no scene/Image-loading side effects of its
# own) so a headless test can verify the color-matching logic directly
# without needing a real Image/texture round-trip. `is_equal_approx`'s
# default epsilon is far tighter than a single 8-bit channel step, so this
# is effectively an exact match — correct and sufficient here, since a
# palette-indexed PNG's background-key color is byte-identical across every
# pixel (confirmed directly against the real std.png asset in this phase's
# own test suite), not something that needs fuzzy tolerance.
static func _is_message_box_key_color(c: Color) -> bool:
	return c.is_equal_approx(_MESSAGE_BOX_KEY_COLOR)


# [M23.11 Phase 4e] Loads text_window/std.png, replaces every background-key
# pixel with real alpha=0 (see _MESSAGE_BOX_KEY_COLOR's own doc comment),
# and returns the result as a fresh ImageTexture. Runtime color-keying
# rather than an offline preprocessing script -- matches this file's own
# established "script controls final on-screen appearance" convention
# (the HP-bar/status-icon AtlasTexture slicing in _setup_health_ui above is
# the same shape: load the raw pulled art, transform it in code, never touch
# the file on disk).
static func _color_keyed_texture(source: Image) -> ImageTexture:
	var img := source.duplicate()
	img.convert(Image.FORMAT_RGBA8)
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			if _is_message_box_key_color(img.get_pixel(x, y)):
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)


# [M23.11 Phase 4e] Message-box authenticity via the real text_window art,
# using the now-enabled Dialogue Manager plugin's own DialogueLabel node
# class (see _log_label's own onready doc comment for why that's safe) --
# called once from _ready(), alongside _setup_health_ui().
#
# [Dialogue-Manager-vs-custom decision, stated here since this is the one
# call site it governs] Deliberately does NOT instantiate Dialogue Manager's
# own example_balloon.tscn / call DialogueManager.show_dialogue_balloon() --
# that API is shaped around ONE DialogueResource/DialogueLine at a time,
# gated on player input to advance to the next line (a genuine branching-
# conversation balloon). This screen's battle log is the opposite shape: an
# ACCUMULATING, non-blocking scroll of many short lines arriving in rapid
# succession (Phase 4f's per-slot doubles messages especially), which the
# task's own "must not regress queuing/sequencing/timing" constraint asks
# to preserve exactly as built across M23.2-4f. Forcing every log line
# through a synthetic DialogueLine + balloon-advance gate would be a large,
# genuinely risky rearchitecture for zero real benefit here (there is no
# authored branching content to gain from it) -- so the integration is
# scoped to what's actually a good fit: the DialogueLabel component class
# itself (a real Dialogue-Manager-provided RichTextLabel subclass, used
# here as a plain accumulating label, its own typewriter/dialogue-line API
# simply never invoked) plus the real text_window art as its background.
# Dialogue Manager's full balloon/branching machinery remains available,
# unused by this screen, for whatever future overworld NPC dialogue system
# M26 eventually builds -- see CLAUDE.md's "Project Roadmap" section.
func _setup_message_box() -> void:
	var raw_image: Image = load("res://assets/sprites/battle_ui/text_window/std.png").get_image()
	var keyed_texture: ImageTexture = _color_keyed_texture(raw_image)

	var box_style := StyleBoxTexture.new()
	box_style.texture = keyed_texture
	box_style.texture_margin_left = _MESSAGE_BOX_MARGIN
	box_style.texture_margin_top = _MESSAGE_BOX_MARGIN
	box_style.texture_margin_right = _MESSAGE_BOX_MARGIN
	box_style.texture_margin_bottom = _MESSAGE_BOX_MARGIN

	_log_label.add_theme_stylebox_override("normal", box_style)

	# [M23.11 Phase 4e — real bug found via screenshot verification] Without
	# this, the log's text rendered as invisible white-on-white: this
	# project's theme has no RichTextLabel font-color override at all, so
	# `_log_label` was relying on the engine default (light/white) being
	# visible against the SCREEN's own dark gray background -- true before
	# this function ran (LogLabel had no background of its own), false the
	# instant a real, opaque, light-interior text_window panel sits behind
	# it. A near-black color matches the real game's own dark-text-on-a-
	# light-box convention (the same cream/pale interior already used by
	# this project's healthbox art).
	_log_label.add_theme_color_override("default_color", Color(0.1, 0.1, 0.1))


func _update_status_icon(icon_node: TextureRect, atlas: AtlasTexture, status: int) -> void:
	var row := _status_icon_row(status)
	if row < 0:
		icon_node.visible = false
		return
	icon_node.visible = true
	atlas.region = Rect2(0, row * _STATUS_ICON_SIZE.y, _STATUS_ICON_SIZE.x, _STATUS_ICON_SIZE.y)


# [M23.11 Phase 4d] Generalized doubles per-side refresh — one function
# reused for BOTH sides (opponent/player) and BOTH slots, rather than
# hand-duplicating this logic 4 times, per this project's own "generalize,
# don't duplicate" instinct. The .tscn nodes themselves still had to be
# duplicated (a static scene tree has no runtime "instantiate N copies"
# equivalent short of manual PackedScene work, judged not worth the added
# complexity for a fixed maximum of 2 slots/side) — see docs/m23_recon.md's
# Phase 4d entry for the full generalize-vs-duplicate writeup.
#
# `slot < active_count` hiding: party.num_active() is fixed for the whole
# battle (2 for a real doubles battle, 1 for singles — active_indices never
# shrinks when a mon faints, matching this project's existing singles
# behavior of showing a fainted mon in place until it's switched), so this
# is really a doubles-vs-singles distinction rather than a per-turn count,
# but is written generically rather than assuming exactly 2.
#
# Each slot's own `mon.fainted`/`mon.status`/`mon.current_hp` drives ONLY
# that slot's own sprite/health-box state — one Pokémon fainting on a side
# cannot affect its still-live teammate's own fade/status/HP display, since
# each slot is processed as a fully independent iteration reading only that
# slot's own BattlePokemon instance.
func _refresh_doubles_side(party: BattleParty, is_player: bool, sprites: Array, groups: Array,
		status_icons: Array, status_atlases: Array, hp_fills: Array) -> void:
	var active_count := party.num_active()
	for slot in range(2):
		var visible_now: bool = slot < active_count
		sprites[slot].visible = visible_now
		groups[slot].visible = visible_now
		if not visible_now:
			continue
		var mon: BattlePokemon = party.get_active_at(slot)
		if is_player:
			sprites[slot].texture = _sprite_or_fallback_back(mon.species.national_dex_num)
		else:
			# [M23.11 Phase 4c precedent] Idle-bob is front-sprite (opponent)
			# only — reset this slot's own frame to 0 on every state-driven
			# refresh, matching the singles branch's identical reset above.
			_opp_anim_frame_d[slot] = 0
			sprites[slot].texture = _sprite_or_fallback_front(mon.species.national_dex_num, 0)
		sprites[slot].modulate = Color(1, 1, 1, 0.3) if mon.fainted else Color(1, 1, 1, 1)
		hp_fills[slot].max_value = mon.max_hp
		hp_fills[slot].value = mon.current_hp
		hp_fills[slot].tint_progress = _hp_bar_color(mon.current_hp, mon.max_hp)
		_update_status_icon(status_icons[slot], status_atlases[slot], mon.status)


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
	#
	# [M23.11 Phase 4d] Doubles branch — singles path below is completely
	# untouched (same lines, same order), matching this phase's own "singles
	# must remain the unchanged fast path" requirement.
	if _is_doubles_mode:
		_refresh_doubles_side(_opp_party, false, _opp_sprites_d, _opp_groups_d,
				_opp_status_icon_d, _opp_status_atlas_d, _opp_hp_fill_d)
		_refresh_doubles_side(_player_party, true, _ply_sprites_d, _ply_groups_d,
				_ply_status_icon_d, _ply_status_atlas_d, _ply_hp_fill_d)
	else:
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

	# [M23.11 Phase 4f] SWITCH_PROMPT (mandatory faint replacement) —
	# generalized to whichever player field slot currently has a fainted
	# active mon, not just field slot 0. Needs no stored "already handled"
	# tracking the way MOVE_SELECTION does below: once a replacement is
	# queued and advance() runs, that slot's active mon is no longer
	# fainted, so a fresh scan next refresh naturally finds the next
	# fainted slot (if a simultaneous doubles double-faint left one) or
	# nothing. Singles: _current_switch_prompt_field_slot() always returns
	# 0 or -1, identical in effect to the pre-4f hardcoded side0_mon check.
	if _bm.get_phase() == BattleManager.BattlePhase.SWITCH_PROMPT:
		var prompt_slot := _current_switch_prompt_field_slot()
		if prompt_slot < 0:
			# Defensive only — BattleManager wouldn't still be stalled at
			# SWITCH_PROMPT with a human-controlled side unless at least one
			# of its active slots were fainted and awaiting a reply.
			_status_label.text = "Waiting..."
			return
		var fainted_mon: BattlePokemon = _player_party.get_active_at(prompt_slot)
		_status_label.text = "%s fainted! Choose a replacement." % fainted_mon.species.species_name
		_build_switch_buttons(true, prompt_slot)
		return

	# [M23.11 Phase 4f] MOVE_SELECTION — iterates player field slots in
	# sequence, one menu shown at a time, until every active slot has
	# submitted an action this turn. Singles always has exactly one active
	# slot, so this collapses to the pre-4f single-slot flow with no
	# behavior change (see _ensure_slot_tracking_for_new_turn's own doc
	# comment).
	if _bm.get_phase() == BattleManager.BattlePhase.MOVE_SELECTION:
		_ensure_slot_tracking_for_new_turn()
		var field_slot := _current_action_field_slot()
		if field_slot < 0:
			# Every player-side slot already submitted an action this turn —
			# BattleManager just hasn't advanced past MOVE_SELECTION in this
			# exact call yet (the handler that set the last slot's action
			# already called advance() itself; nothing further to show here).
			_status_label.text = "Waiting..."
			return
		var acting_mon: BattlePokemon = _player_party.get_active_at(field_slot)
		match _menu:
			Menu.FIGHT:
				_status_label.text = "Choose a move for %s." % acting_mon.species.species_name
				_build_fight_menu(field_slot)
			Menu.SWITCH:
				_status_label.text = "Choose a Pokémon to switch in."
				_build_switch_buttons(false, field_slot)
			Menu.ITEM:
				_status_label.text = "Choose an item."
				_build_item_buttons(field_slot)
			Menu.TARGET_SELECT:
				var pending_move: MoveData = acting_mon.moves[_pending_move_index]
				_status_label.text = "Choose a target for %s." % pending_move.move_name
				_build_target_select_buttons(field_slot, _pending_move_index)
			_:
				_status_label.text = "Choose an action for %s." % acting_mon.species.species_name
				_build_top_menu(field_slot)


# [M23.11 Phase 4f] First player field slot with a fainted active mon
# needing a forced replacement, or -1 if none.
func _current_switch_prompt_field_slot() -> int:
	for slot in range(_player_party.num_active()):
		if _player_party.get_active_at(slot).fainted:
			return slot
	return -1


# [M23.11 Phase 4f] Detects a fresh MOVE_SELECTION turn (every slot already
# acted, or this is the very first call this battle) and resets the
# per-slot tracking for it. BattleManager's own equivalent internal state
# (_move_choice_resolved) isn't publicly readable, so this screen keeps its
# own mirror — see _slot_acted's own doc comment (near the Menu enum) for
# why a single flat _menu plus this array was chosen over a full per-slot
# Menu array.
func _ensure_slot_tracking_for_new_turn() -> void:
	var expected_size := _player_party.num_active()
	if _slot_acted.size() != expected_size or not _slot_acted.has(false):
		_slot_acted = []
		for i in range(expected_size):
			_slot_acted.append(false)
		_menu = Menu.TOP
		_pending_move_index = -1


# [M23.11 Phase 4f] First not-yet-acted, non-fainted player field slot this
# turn, or -1 if every active slot has already submitted an action (or, a
# defensive case that can't happen while BattleManager itself is still
# stalled at MOVE_SELECTION, if every slot happens to be fainted — that
# function resolves fainted combatants automatically with no stall).
# Mirrors BattleManager._phase_move_selection's own "skip fainted
# combatants" rule exactly.
func _current_action_field_slot() -> int:
	for slot in range(_slot_acted.size()):
		if _slot_acted[slot]:
			continue
		if _player_party.get_active_at(slot).fainted:
			_slot_acted[slot] = true
			continue
		# [M25a bugfix] A forced-Struggle slot (every move at 0 PP) is
		# already auto-resolved by BattleManager itself the moment
		# MOVE_SELECTION reaches it (is_forced_struggle()) -- it never waits
		# for a real player decision, matching the real games' own "no menu
		# shown at all" behavior. Without this check, this slot would still
		# read as unresolved here (nothing ever sets _slot_acted for it via
		# a button press) and the Fight menu would render with every move
		# button disabled and no way to actually act.
		if _bm.is_forced_struggle(_player_party.get_active_at(slot)):
			_slot_acted[slot] = true
			continue
		return slot
	return -1


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


# [M23.11 Phase 4f] field_slot replaces the old bare `side0_mon` param —
# reads _player_party.get_active_at(field_slot) instead of the singular
# get_active() accessor, so this works for either of a doubles battle's 2
# active slots. Singles: field_slot is always 0, byte-identical to before.
#
# [M25b] Real top-level Fight/Item/Switch/Run menu — the 4 real games'
# own top-level options, replacing the old single screen that showed every
# move button inline alongside Switch/Item. field_slot is threaded through
# unchanged into whichever sub-menu gets picked, exactly as it already was.
func _build_top_menu(field_slot: int) -> void:
	var fight_btn := Button.new()
	fight_btn.text = "Fight"
	fight_btn.pressed.connect(func():
		_menu = Menu.FIGHT
		_refresh_ui())
	_button_area.add_child(fight_btn)

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

	# [M25b] Temporary placeholder — NOT real flee logic (success chance,
	# speed comparison, trainer-battle refusal, etc. are all explicitly out
	# of scope this session, per this sub-phase's own locked scope note).
	# Exists because there is currently no way to exit an in-progress
	# battle at all otherwise. See _on_run_pressed's own doc comment for
	# exactly what it does.
	var run_btn := Button.new()
	run_btn.text = "Run"
	run_btn.pressed.connect(_on_run_pressed)
	_button_area.add_child(run_btn)


# [M25b] The move list — content unchanged from the old _build_main_menu's
# own move-button loop, just moved one tier deeper (behind Fight) and given
# its own "Back" button (returns to TOP), matching every other sub-menu's
# existing convention (_build_switch_buttons'/_build_item_buttons' own
# non-forced "Back" branches).
func _build_fight_menu(field_slot: int) -> void:
	var mon: BattlePokemon = _player_party.get_active_at(field_slot)
	for i in range(mon.moves.size()):
		var move: MoveData = mon.moves[i]
		if move == null:
			continue
		var btn := Button.new()
		btn.text = "%s (PP %d/%d)" % [move.move_name, mon.current_pp[i], move.pp]
		btn.disabled = mon.current_pp[i] <= 0
		btn.pressed.connect(_on_move_pressed.bind(field_slot, i))
		_button_area.add_child(btn)

	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.pressed.connect(func():
		_menu = Menu.TOP
		_refresh_ui())
	_button_area.add_child(back_btn)


# [M25b] Run placeholder — ends the current battle immediately and returns
# to the setup/home screen. Mirrors _on_play_again_pressed's own exact
# shape: a bare scene change is sufficient. BattleSetupContext is already
# cleared at CONSUMPTION time in _ready() (not at battle-end), so there's
# nothing stale left for the next launch to see regardless of how this
# battle ends; the whole current scene tree (BattleManager, timers,
# hit-effect nodes) is freed automatically by change_scene_to_file(). The
# one thing a normal battle-end (_on_battle_ended) does that this path
# wouldn't otherwise reach is _clear_active_hit_effects() — called
# explicitly here too, so a still-animating hit effect's Tween can't
# outlive the node it's driving for even one frame during the scene swap
# (matching the exact leak this project's own M25c session already found
# and fixed for the normal win/loss path).
func _on_run_pressed() -> void:
	_clear_active_hit_effects()
	get_tree().change_scene_to_file("res://scenes/battle/battle_setup_screen.tscn")


# [M23.11 Phase 4f] field_slot is the player's own active slot performing
# the switch (irrelevant for is_forced_replacement — SWITCH_PROMPT already
# resolves which slot via _current_switch_prompt_field_slot(), passed in
# by the caller either way) — needed so _on_switch_pressed can resolve the
# right combatant_idx for queue_switch_for/queue_replacement_for.
# [M25a bugfix] Pure/static so its "is there anything to show here" logic
# is directly unit-testable without a live scene tree (the button-building
# function itself touches @onready UI nodes and calls _refresh_ui(), which
# needs a real, running BattleScreen -- matching this project's own
# established precedent, e.g. _status_icon_row/_next_anim_frame, of pulling
# the PURE decision logic out into a small static helper rather than
# leaving it inline where only a real screenshot pass could exercise it).
static func _party_has_switch_candidate(party: BattleParty) -> bool:
	for i in range(party.members.size()):
		if not party.active_indices.has(i) and not party.members[i].fainted:
			return true
	return false


func _build_switch_buttons(is_forced_replacement: bool, field_slot: int) -> void:
	var any_candidate := _party_has_switch_candidate(_player_party)
	for i in range(_player_party.members.size()):
		if _player_party.active_indices.has(i) or _player_party.members[i].fainted:
			continue
		var mon: BattlePokemon = _player_party.members[i]
		var btn := Button.new()
		btn.text = "%s  HP: %d/%d" % [mon.species.species_name, mon.current_hp, mon.max_hp]
		btn.pressed.connect(_on_switch_pressed.bind(i, is_forced_replacement, field_slot))
		_button_area.add_child(btn)

	# [M25a bugfix] A forced replacement (SWITCH_PROMPT) with genuinely NO
	# valid bench candidate (e.g. a doubles battle where the only remaining
	# live party member is already active in the OTHER field slot) used to
	# leave this screen with zero buttons -- a real hardlock, since
	# BattleManager's own _phase_switch_prompt waits indefinitely for
	# queue_replacement_for() on a human-controlled side, and nothing could
	# ever call it. BattleManager already handles an explicit "no
	# replacement" submission correctly (_get_replacement_slot falls
	# through to BattleParty.get_first_non_fainted_not_active(), which
	# returns -1 and resolves this slot as "no replacement available" —
	# the same fallback the AI-driven path already relies on) — this just
	# needed to actually BE submitted rather than the player being left
	# with nothing to press. Auto-resolves the same turn a real player
	# would otherwise be stuck on, instead of requiring a button that
	# can't exist.
	if is_forced_replacement and not any_candidate:
		_bm.queue_replacement_for(field_slot, -1)
		_bm.advance()
		_refresh_ui()
		return

	if not is_forced_replacement:
		var back_btn := Button.new()
		back_btn.text = "Back"
		back_btn.pressed.connect(func():
			_menu = Menu.TOP
			_refresh_ui())
		_button_area.add_child(back_btn)


func _build_item_buttons(field_slot: int) -> void:
	var potion_btn := Button.new()
	potion_btn.text = "Potion (heal)"
	potion_btn.pressed.connect(_on_item_pressed.bind(POTION_ITEM_ID, field_slot))
	_button_area.add_child(potion_btn)

	var full_heal_btn := Button.new()
	full_heal_btn.text = "Full Heal (cure status)"
	full_heal_btn.pressed.connect(_on_item_pressed.bind(FULL_HEAL_ITEM_ID, field_slot))
	_button_area.add_child(full_heal_btn)

	var x_attack_btn := Button.new()
	x_attack_btn.text = "X Attack (+1 Attack)"
	x_attack_btn.pressed.connect(_on_item_pressed.bind(X_ATTACK_ITEM_ID, field_slot))
	_button_area.add_child(x_attack_btn)

	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.pressed.connect(func():
		_menu = Menu.TOP
		_refresh_ui())
	_button_area.add_child(back_btn)


# [M23.11 Phase 4f] Target-picker — one Button per live candidate returned
# by BattleManager.get_live_targets(mon, move) (see that function's own doc
# comment for exactly which candidates show up here: 2 live opponents for
# an ordinary foe-targeting move in doubles, or [self, ally] for
# TARGET_USER_OR_ALLY moves like Acupressure). Only ever built when
# _on_move_pressed has already confirmed candidates.size() > 1 — this
# function doesn't re-check ambiguity itself, matching every other
# _build_*_buttons function's existing "caller already decided to show
# this menu" convention.
func _build_target_select_buttons(field_slot: int, move_index: int) -> void:
	var mon: BattlePokemon = _player_party.get_active_at(field_slot)
	var move: MoveData = mon.moves[move_index]
	var candidates: Array[BattlePokemon] = _bm.get_live_targets(mon, move)
	for target_mon: BattlePokemon in candidates:
		var target_idx: int = _bm.get_combatant_index(target_mon)
		var btn := Button.new()
		btn.text = "%s  HP: %d/%d" % [_mon_label(target_mon), target_mon.current_hp, target_mon.max_hp]
		btn.pressed.connect(_on_target_selected.bind(field_slot, move_index, target_idx))
		_button_area.add_child(btn)

	# [M23.11 Phase 4f] Matches every other sub-menu's own "Back" convention
	# (_build_switch_buttons'/_build_item_buttons' non-forced branches) —
	# returns to the move list for this same slot without submitting an
	# action, so the player can pick a different move instead.
	# [M25b] Returns to FIGHT specifically (not all the way to TOP) — the
	# immediate previous step in the now-two-tier menu, so picking a
	# different move doesn't require re-entering Fight from the top menu.
	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.pressed.connect(func():
		_menu = Menu.FIGHT
		_pending_move_index = -1
		_refresh_ui())
	_button_area.add_child(back_btn)


# ── Input handlers — the M23.0a external contract in action ────────────────
# Every handler below is the exact queue_*() + advance() pattern confirmed
# in docs/m23_recon.md (M23.0a's proof scene and M23.0b's own translation
# check): supply the human's action via the pre-existing queue API, call
# advance() to resume the paused battle loop, then re-render from whatever
# phase advance() left the battle in.
#
# [M23.11 Phase 4f] Every handler below now takes field_slot, resolving
# combatant_idx as field_slot directly — side 0's own combatant_idx is
# always side*_active_per_side + field_slot = 0*_active_per_side +
# field_slot = field_slot, since this screen only ever acts for side 0.

# [M23.11 Phase 4f] Pure decision logic extracted to a static function,
# matching this file's own established testability convention
# (_status_icon_row/_next_anim_frame/_hp_bar_color) — lets a headless test
# exercise the "when do we show a target picker" boundary directly, with
# no scene/BattleManager needed at all. Spread/ally-inclusive moves
# (move.is_spread) already dispatch to every qualifying combatant in
# _phase_move_execution regardless of the target index passed to
# queue_move_targeted — never show a picker for them, matching the
# scoping report's own confirmed finding. Ambiguous single-target moves
# (2+ live foe candidates in doubles, or the TARGET_USER_OR_ALLY
# self-vs-ally choice) DO need one.
static func _needs_target_select(move: MoveData, candidate_count: int) -> bool:
	return not move.is_spread and candidate_count > 1


func _on_move_pressed(field_slot: int, move_index: int) -> void:
	var mon: BattlePokemon = _player_party.get_active_at(field_slot)
	var move: MoveData = mon.moves[move_index]
	var candidates: Array[BattlePokemon] = _bm.get_live_targets(mon, move)
	if _needs_target_select(move, candidates.size()):
		_menu = Menu.TARGET_SELECT
		_pending_move_index = move_index
		_refresh_ui()
		return
	# Singles (and any doubles case with only one valid/no candidate, e.g. a
	# TARGET_ALLY move auto-resolving to the lone live ally): preserve the
	# exact pre-4f default of targeting combatant 1 when there's nothing
	# more specific to resolve to (harmless for ally-exclusive moves, whose
	# own dispatch reads the ally directly rather than consulting this
	# target index at all).
	var target_idx := 1
	if not candidates.is_empty():
		target_idx = _bm.get_combatant_index(candidates[0])
	_dispatch_move(field_slot, move_index, target_idx)


# [M23.11 Phase 4f] Reached only from the target picker above, once the
# player has chosen among 2+ ambiguous candidates.
func _on_target_selected(field_slot: int, move_index: int, target_idx: int) -> void:
	_dispatch_move(field_slot, move_index, target_idx)


func _dispatch_move(field_slot: int, move_index: int, target_idx: int) -> void:
	var combatant_idx := field_slot
	_bm.queue_move_targeted(combatant_idx, move_index, target_idx)
	_bm.advance()
	_slot_acted[field_slot] = true
	_menu = Menu.TOP
	_pending_move_index = -1
	_refresh_ui()


func _on_switch_pressed(slot: int, is_forced_replacement: bool, field_slot: int) -> void:
	var combatant_idx := field_slot
	if is_forced_replacement:
		_bm.queue_replacement_for(combatant_idx, slot)
	else:
		_bm.queue_switch_for(combatant_idx, slot)
	_bm.advance()
	# [M23.11 Phase 4f] Forced replacement doesn't use _slot_acted at all
	# (see _current_switch_prompt_field_slot's own doc comment) — only a
	# voluntary switch, chosen from the MOVE_SELECTION main menu, counts as
	# this slot's action for the turn.
	if not is_forced_replacement:
		_slot_acted[field_slot] = true
	_menu = Menu.TOP
	_refresh_ui()


func _on_item_pressed(item_id: int, field_slot: int) -> void:
	var combatant_idx := field_slot
	_bm.queue_item_for(combatant_idx, item_id)
	_bm.advance()
	_slot_acted[field_slot] = true
	_menu = Menu.TOP
	_refresh_ui()
