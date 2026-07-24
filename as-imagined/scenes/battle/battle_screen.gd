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

# [M26b] Log/debug-overlay merge — category-tagged entry data structure.
# Every line that used to go straight to the old always-visible LogLabel (or
# the old debug overlay's single replaced-wholesale Label) now becomes one
# entry in `_debug_entries` (see var declaration further down), tagged with
# a category from this enum and the real turn number it happened on. The
# full history is NEVER discarded — only what's currently RENDERED is
# filtered by `_debug_category_on`, so toggling a category or scrolling back
# through turns both read the exact same underlying data; nothing is
# recomputed or lost either way. Locked design: CLAUDE.md's own M26b entry.
enum DebugCategory {
	NARRATIVE,        # M25c's move-announcement/target-naming/damage-effectiveness text
	DAMAGE_MATH,       # M25d's existing power/accuracy/STAB/type/crit/roll/final-damage breakdown
	RNG,               # accuracy/secondary-proc/etc. — see _wire_debug_signals()'s own doc comment for the real data-availability gap here
	TURN_ORDER,        # speed/priority/Trick Room reasoning — real coverage limited to After You/Quash splices (turn_order_changed)
	DURATIONS,         # remaining-turn counters for screens/hazards/weather/Trick Room/Tailwind/Safeguard/Mist/Mud-Water Sport
	STAT_CHANGES,      # before->after stage values, not just a narrative "rose/fell" line
	ITEMS_BERRIES,     # real trigger context (HP at the moment an item/berry fired)
	MULTI_HIT,         # multi_hit_sequence_finished — aggregate only, see its own wiring doc comment
	DELAYED,           # Future Sight/Doom Desire/Wish/Yawn/Healing Wish/Lunar Dance scheduled<->resolved pairs
	ABILITY_IMMUNITY,  # ability_triggered/ability_healed — Mold Breaker/Neutralizing Gas/absorb outcomes etc.
	NICHE,             # low-traffic/situational: Leech Seed/Curse/Nightmare/Grudge ticks, item-transfer chains, Snatch/Magic Bounce redirection
}

# Stable render/toggle-row order — NOT the enum's own declaration order is
# relied on anywhere, this array is the single source of truth for display
# order.
const _DEBUG_CATEGORY_ORDER: Array[int] = [
	DebugCategory.NARRATIVE, DebugCategory.DAMAGE_MATH, DebugCategory.RNG,
	DebugCategory.TURN_ORDER, DebugCategory.DURATIONS, DebugCategory.STAT_CHANGES,
	DebugCategory.ITEMS_BERRIES, DebugCategory.MULTI_HIT, DebugCategory.DELAYED,
	DebugCategory.ABILITY_IMMUNITY, DebugCategory.NICHE,
]

const _DEBUG_CATEGORY_LABEL: Dictionary = {
	DebugCategory.NARRATIVE: "Narrative Text",
	DebugCategory.DAMAGE_MATH: "Damage Math",
	DebugCategory.RNG: "RNG & Probability",
	DebugCategory.TURN_ORDER: "Turn Order & Priority",
	DebugCategory.DURATIONS: "Durations & Field State",
	DebugCategory.STAT_CHANGES: "Stat Changes",
	DebugCategory.ITEMS_BERRIES: "Items & Berries",
	DebugCategory.MULTI_HIT: "Multi-Hit Detail",
	DebugCategory.DELAYED: "Delayed Effects",
	DebugCategory.ABILITY_IMMUNITY: "Ability & Immunity",
	DebugCategory.NICHE: "Niche/Situational",
}

# BBCode hex colors, one per category, so the merged history stays visually
# scannable once several categories are toggled on together.
const _DEBUG_CATEGORY_COLOR: Dictionary = {
	DebugCategory.NARRATIVE: "#dddddd",
	DebugCategory.DAMAGE_MATH: "#33cc66",
	DebugCategory.RNG: "#cc66ff",
	DebugCategory.TURN_ORDER: "#66ccff",
	DebugCategory.DURATIONS: "#ffcc66",
	DebugCategory.STAT_CHANGES: "#ff9966",
	DebugCategory.ITEMS_BERRIES: "#99ff99",
	DebugCategory.MULTI_HIT: "#ff6699",
	DebugCategory.DELAYED: "#66ffcc",
	DebugCategory.ABILITY_IMMUNITY: "#ffff66",
	DebugCategory.NICHE: "#999999",
}

# Default-on per the locked design: today's existing content (Narrative/
# Damage Math) plus every new category EXCEPT Niche/Situational, which is
# explicitly default-off (low traffic/relevance per the design's own text).
const _DEBUG_CATEGORY_DEFAULT_ON: Dictionary = {
	DebugCategory.NARRATIVE: true,
	DebugCategory.DAMAGE_MATH: true,
	DebugCategory.RNG: true,
	DebugCategory.TURN_ORDER: true,
	DebugCategory.DURATIONS: true,
	DebugCategory.STAT_CHANGES: true,
	DebugCategory.ITEMS_BERRIES: true,
	DebugCategory.MULTI_HIT: true,
	DebugCategory.DELAYED: true,
	DebugCategory.ABILITY_IMMUNITY: true,
	DebugCategory.NICHE: false,
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
# [M25h-1] Relocated from $VBox/StatusLabel into the new real-proportion
# bottom region (ActionRegion — anchor_top=0.75/anchor_bottom=0.95 in the
# .tscn, matching source's own B_WIN_MSG tilemapTop=15/height=4 tiles =
# y=120-152px of a 160px screen) — same node (unique_id unchanged), same
# role, just a new parent. Side0Label/Side1Label (confirmed redundant M23.2-era
# plain-text HP scaffolding, superseded by Phase 4b's real health-box HP
# bars, plus a confirmed real doubles bug — fed via BattlePokemon.get_active()
# which is hardcoded to get_active_at(0), so they never reflected field slot
# 1) are deleted outright, not relocated.
@onready var _status_label: Label = $ActionRegion/ActionPanel/ActionVBox/StatusLabel

# [M26b] The old always-visible VBox/LogLabel (DialogueLabel, M23.11 Phase
# 4e's real GBA message-box art) is retired outright — its whole node was
# removed from battle_screen.tscn. Every line it used to print now flows
# into the merged, category-tagged, F3-only debug/log system below instead
# (see the "Combat debug/log [M26b]" section further down this file). This
# is a deliberate, disclosed UX trade-off already locked into this project's
# own CLAUDE.md M26b design note: a player gets zero textual battle
# information without opening the F3 panel, off by default — revisit only
# if that proves a real problem in practice. `_color_keyed_texture`/
# `_is_message_box_key_color` (below) are NOT retired — ItemSelectScreen/
# SwitchSelectScreen both still call them directly for their own real
# window art.
# [M25h-1] Still used by SWITCH/ITEM only now (left inline/untouched per
# this sub-phase's own locked scope -- M25h-1.4/M25h-1.5 pulled those two
# out into real separate overlay screens; only their own top-level launcher
# buttons live here). TOP/FIGHT/TARGET_SELECT moved to _new_button_area/
# _new_button_grid below, inside the new real-proportion region -- see
# _new_button_grid's own onready doc comment (M26c-3) for exactly which
# menu uses which of the two.
#
# [M25h-1 anchor fix] `VBox`'s own .tscn anchors changed from a floating
# CENTER point (anchor_top=anchor_bottom=0.5, grow_vertical=BOTH) to a
# TOP-pinned point near the top of the screen (anchor_top=anchor_bottom=
# 0.04, grow_vertical=END) — found necessary via real screenshot
# verification, not assumed. With StatusLabel/Side0Label/Side1Label
# removed, VBox's total content shrank; under the OLD center-point/grow-
# BOTH anchoring this recentered the whole block, pulling `_button_area`'s
# own buttons up into LogLabel's own fixed 220px box for anything more than
# ~2 rows (confirmed: Item's real 4-button list visibly overlapped the
# log). LogLabel's own node/properties are still completely untouched (per
# this sub-phase's own explicit instruction), but its SCREEN POSITION did
# move — a deliberate, disclosed trade-off: pinning the top and moving the
# whole block higher was the only way to guarantee `_button_area` (still
# holding SWITCH/ITEM's real content) never overlaps either the log above
# it or ActionRegion below it, for every row-count SWITCH/ITEM can produce.
@onready var _button_area: VBoxContainer = $VBox/ButtonArea
@onready var _new_button_area: VBoxContainer = $ActionRegion/ActionPanel/ActionVBox/NewButtonArea
# [M26c-3] The real 2x2 grid — TOP (Fight/Bag/Pokémon/Run) and FIGHT
# (move-select) both build into this GridContainer(columns=2) instead of
# _new_button_area now, matching source's own confirmed real layout
# (ActionSelectionCreateCursorAt/MoveSelectionCreateCursorAt's identical
# bit-math tile-paste cursor: bit0=column, bit1=row — see _build_top_menu's
# own doc comment for the full source citation and cell-order mapping).
# TARGET_SELECT is untouched (still _new_button_area) — that screen's real
# source mechanism isn't a menu at all (a health-box bounce + D-pad cycle,
# M26c-4's own future job per M25h-3's audit), so it was never part of this
# grid regrid's scope.
@onready var _new_button_grid: GridContainer = $ActionRegion/ActionPanel/ActionVBox/NewButtonGrid
@onready var _action_panel: PanelContainer = $ActionRegion/ActionPanel

# [M25d, expanded M26b] Combat-debug/log overlay — a separate top-level node
# (drawn last, so it renders on top of both BattleStage's sprites/health-
# boxes and VBox's own menu column), deliberately not a child of either. Off
# by default (DebugOverlay.visible = false in the .tscn); toggled via F3,
# never via a gameplay button, so it has zero visual footprint for a normal
# player. [M26b] Now the SOLE textual battle-info surface (the old always-
# visible VBox/LogLabel was retired — see that var's own former doc comment
# above) — see the "Combat debug/log [M26b]" section further down this file
# for the category-tagged entry system feeding `_debug_body`.
@onready var _debug_overlay: Control = $DebugOverlay
@onready var _debug_toggle_row: HFlowContainer = $DebugOverlay/VBox/ToggleRow
@onready var _debug_body: RichTextLabel = $DebugOverlay/VBox/Scroll/Body

# [M23.11 Phase 4a] Visual battle stage -- additive alongside the existing
# text-based UI above, not a replacement (Side0Label/Side1Label stayed as
# they were at the time, per this phase's own explicit scope -- LogLabel
# itself was later retired outright by M26b, see above).
@onready var _background_rect: TextureRect = $BattleStage/Background
@onready var _opponent_sprite: TextureRect = $BattleStage/OpponentSprite
@onready var _player_sprite: TextureRect = $BattleStage/PlayerSprite

# [M26c battle-UI polish] Bottom-anchor baseline -- the opponent sprite box's
# own ORIGINAL (.tscn-authored) offset_top/offset_bottom, captured once in
# _setup_health_ui() before any species-driven texture/offset mutation ever
# happens. _apply_bottom_anchored_front_sprite() always computes a fresh
# offset_top/offset_bottom FROM this fixed baseline, never from the box's own
# current (possibly already-shifted-for-a-different-species) live offset --
# see that function's own doc comment for why the math needs a stable
# baseline. Doubles' own two slots get one baseline pair each.
var _opponent_sprite_base_top: float = 0.0
var _opponent_sprite_base_bottom: float = 0.0
var _opp_sprite_d_base_top: Array = []
var _opp_sprite_d_base_bottom: Array = []

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
@onready var _opponent_hp_fill: TextureProgressBar = $BattleStage/OpponentHealthGroup/HpFill
# [M25d, split M26c-1 follow-up] Name/level display — see _refresh_ui()'s
# own doc comment for why this is updated in lockstep with the HP bar (same
# call site, every state change) rather than only on switch-in, guaranteeing
# it can never lag. Split into two separate Label nodes (was one combined
# NameLevelLabel) so the gender symbol can be appended to the name text
# alone without disturbing the level text's own right-aligned position.
@onready var _opponent_name_label: Label = $BattleStage/OpponentHealthGroup/NameLabel
@onready var _opponent_gender_label: Label = $BattleStage/OpponentHealthGroup/GenderLabel
@onready var _opponent_level_label: Label = $BattleStage/OpponentHealthGroup/LevelLabel
@onready var _player_health_group: Control = $BattleStage/PlayerHealthGroup
@onready var _player_health_bg: TextureRect = $BattleStage/PlayerHealthGroup/Background
@onready var _player_status_icon: TextureRect = $BattleStage/PlayerHealthGroup/StatusIcon
@onready var _player_hp_fill: TextureProgressBar = $BattleStage/PlayerHealthGroup/HpFill
# [M26c-1] Real EXP bar — singles player only, matching the real games' own
# scope (never shown for the opponent's mon, never shown in doubles at all —
# see gen_databox_sprites.py's own doc comment: the pack ships no EXP-ledge
# variant for either the opponent box or the doubles "thin" box, confirming
# this isn't just a design choice made in isolation).
@onready var _player_exp_fill: TextureProgressBar = $BattleStage/PlayerHealthGroup/ExpFill
# [M26c-3] Numeric HP readout ("100/120") -- singles player only, matching
# the real games' own scope exactly (PrintHpOnHealthbox, battle_interface.c
# -- the player's own box always prints currHp/maxHp; the opponent's box
# only does under a debug-only "hpNumbersNoBars" flag this project doesn't
# model, and doubles boxes are gated behind that same flag too). Sits in
# the real vertical gap between the HP bar and the EXP bar below it.
@onready var _player_hp_number_label: Label = $BattleStage/PlayerHealthGroup/HpNumberLabel
@onready var _player_name_label: Label = $BattleStage/PlayerHealthGroup/NameLabel
@onready var _player_gender_label: Label = $BattleStage/PlayerHealthGroup/GenderLabel
@onready var _player_level_label: Label = $BattleStage/PlayerHealthGroup/LevelLabel

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
var _opp_hp_fill_d: Array = []
var _opp_name_label_d: Array = []  # [M25d, split M26c-1 follow-up]
var _opp_gender_label_d: Array = []  # [M26c battle-UI polish]
var _opp_level_label_d: Array = []  # [M25d, split M26c-1 follow-up]
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
var _ply_hp_fill_d: Array = []
var _ply_name_label_d: Array = []  # [M25d, split M26c-1 follow-up]
var _ply_gender_label_d: Array = []  # [M26c battle-UI polish]
var _ply_level_label_d: Array = []  # [M25d, split M26c-1 follow-up]

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

# [M25c] Effectiveness/crit data for the hit _on_log_move_executed is about
# to report — set by _on_hit_effectiveness_computed, which BattleManager
# fires (from _do_damaging_hit) immediately before the move_executed call it
# corresponds to, so this is always fresh by the time it's read. Never set
# for a non-damaging move (status moves never emit move_effectiveness_
# computed at all), matching that case's own silence requirement.
var _pending_hit_effectiveness: float = 1.0
var _pending_hit_is_crit: bool = false
var _pending_hit_has_data: bool = false

var _is_autoplay_run: bool = false

# [M26b] The full, permanently-accumulating category-tagged history — never
# discarded, never trimmed. `_debug_category_on` filters what's RENDERED
# only (see _render_debug_overlay()); scrolling back through turns and
# toggling a category on/off both read this exact same array. Each entry:
# {"turn": int, "category": DebugCategory, "text": String}. Toggle state is
# a plain in-memory var per the locked design (session-only — this project
# has no save/settings infrastructure yet, that's M33's own job).
var _debug_entries: Array[Dictionary] = []
var _debug_category_on: Dictionary = {}
var _current_debug_turn: int = 0

# [M25h-1.2] The real GBA bitmap fonts (see scripts/gen_battle_fonts.py's own
# doc comment for the full Step 0 sourcing) -- loaded once in _ready(),
# before any of _setup_health_ui()/_setup_action_region_panel()/the menu-
# button builders run, since all of them apply one of these three
# ("_setup_message_box()" was retired by M26b -- see that function's own
# former doc comment). Native pixel sizes are baked into the
# atlas itself (15 for both "normal"-derived fonts, 13 for "small") --
# `add_theme_font_size_override` is still set explicitly to that same
# native value at every call site rather than left at the theme's generic
# default (20), so nothing silently asks Godot to rescale a bitmap glyph
# and soften its pixel-perfect edges.
var _font_message: FontFile
var _font_menu: FontFile
var _font_healthbox: FontFile

const _FONT_NORMAL_SIZE := 15
const _FONT_SMALL_SIZE := 13


func _load_battle_fonts() -> void:
	_font_message = FontFile.new()
	_font_message.load_bitmap_font("res://assets/fonts/latin_normal_message.fnt")
	_font_menu = FontFile.new()
	_font_menu.load_bitmap_font("res://assets/fonts/latin_normal_menu.fnt")
	_font_healthbox = FontFile.new()
	_font_healthbox.load_bitmap_font("res://assets/fonts/latin_small_healthbox.fnt")
	# [M26c battle-UI polish] load_bitmap_font() leaves fixed_size_scale_mode
	# at its default (0, DISABLE) -- confirmed via a direct isolated probe
	# (four Labels sharing this font at font_size 9/13/24/48 rendered
	# PIXEL-IDENTICAL in size with scale_mode left at its default) that this
	# makes every Label using this font render its glyphs at the .fnt's own
	# native 13px size REGARDLESS of any theme_override_font_sizes/font_size
	# a Label requests -- the .tscn's own font_size values on the name/level
	# Labels (13 singles / 9 doubles pre-this-session) were therefore always
	# silently ignored for actual glyph size, real only for line-height/
	# layout metrics. Setting scale_mode=2 (confirmed via the same probe to
	# enable real proportional up/down scaling, matching this project's
	# established "requested-size bitmap-font scaling is an accepted,
	# already-used pattern" precedent -- see doubles' own pre-existing
	# smaller-than-native font_size=9) is required for the increased
	# font_size values below to have any visible effect at all.
	_font_healthbox.fixed_size_scale_mode = 2


# [M25h-1.2] Every menu Button (TOP/FIGHT/TARGET_SELECT/SWITCH/ITEM/battle-
# end) goes through this one helper -- see _build_top_menu's own doc comment
# for why source's real B_WIN_MOVE_NAME (FONT_NARROW) isn't reproduced
# separately: this project's move-name buttons are plain Buttons, not a
# dedicated GBA window, so they reuse this same "menu" context. Colors are
# baked into the atlas texture itself (see gen_battle_fonts.py), so every
# font_*_color override here is intentionally Color(1,1,1,1) -- a neutral,
# non-tinting modulate -- rather than an actual color choice; leaving Godot's
# own default (light grey) in place would multiply against the baked-in
# dark-grey/light-grey pixels and crush them. font_disabled_color keeps a
# partial-alpha fade (the one real color decision here) so a disabled button
# still reads as visibly different, matching Godot's own default disabled
# convention.
func _style_menu_button(btn: Button) -> void:
	# [M25h-1.2] Guards against _font_menu being unloaded -- the real
	# production caller (_ready()) always runs _load_battle_fonts() first,
	# but this project's own established test convention (m25b_menu_test.gd
	# and others) directly calls _build_top_menu()/_build_fight_menu()/etc.
	# on a bare BattleScreen.new() with no full _ready() pass, where a real
	# font resource was never a thing those tests needed or checked for.
	# Treated as a legitimate no-styling-yet state, not an error condition.
	if _font_menu == null:
		return
	btn.add_theme_font_override("font", _font_menu)
	btn.add_theme_font_size_override("font_size", _FONT_NORMAL_SIZE)
	btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	btn.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	btn.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 1))
	btn.add_theme_color_override("font_focus_color", Color(1, 1, 1, 1))
	btn.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.5))


# [M25h-1.3] Real right-pointing-triangle cursor glyph -- see
# gen_battle_fonts.py's own doc comment for the source citation (both of
# source's two distinct cursor mechanisms draw this same "▶" marker; this
# project reuses it via the exact same bitmap-font pipeline the surrounding
# menu text already goes through, rather than a separately-sourced sprite).
const _CURSOR_GLYPH := "▶"
const _CURSOR_PREFIX := _CURSOR_GLYPH + " "
const _CURSOR_BLANK := "  "

# One shared StyleBoxEmpty instance -- StyleBoxEmpty carries no per-instance
# state, so every stripped button safely reuses the same Resource rather
# than each allocating its own no-op box.
static var _empty_button_style: StyleBoxEmpty = StyleBoxEmpty.new()


# [M25h-1.3] Removes Godot's own default flat-grey Button chrome (normal/
# hover/pressed/focus/disabled) so the real window art already sitting
# behind these buttons (ActionPanel's text_window/1.png pull, M25h-1.1) is
# fully visible with nothing but text on it -- matching source's own real
# convention (the action-selection/move-select screens have no per-row
# button-background art at all; selection is indicated purely by the ▶
# cursor). Deliberately NOT applied to _button_area's own Switch/Item/
# battle-end buttons -- that old inline region has no real window art
# behind it at all (M25h-2/h-3's own future job), so stripping its chrome
# would drop its text onto the plain dark battle background with nothing
# to back it, a real legibility regression rather than a fix. See
# _build_switch_buttons'/_build_item_buttons'/_build_battle_end_buttons'
# own doc comments for this same boundary stated at their call sites.
func _strip_button_chrome(btn: Button) -> void:
	btn.add_theme_stylebox_override("normal", _empty_button_style)
	btn.add_theme_stylebox_override("hover", _empty_button_style)
	btn.add_theme_stylebox_override("pressed", _empty_button_style)
	btn.add_theme_stylebox_override("focus", _empty_button_style)
	btn.add_theme_stylebox_override("disabled", _empty_button_style)
	btn.add_theme_stylebox_override("hover_pressed", _empty_button_style)


# [M25h-1.3] Wires the shared selection cursor across one menu's own button
# group. Source always has SOME option selected the instant a menu opens
# (`initialCursorPos`/`gActionSelectionCursor[battler]`, both real fields
# with a real starting value, never an absent/no-selection state) -- so
# this defaults to index 0 immediately, rather than waiting for the first
# hover. Mouse-only: this project's menus have never wired keyboard/gamepad
# focus navigation (confirmed via a direct grep for grab_focus/
# focus_neighbor/ui_up/ui_down before this sub-phase touched anything --
# none exist anywhere in this file), so mouse hover is the one real,
# functional input method to track. The cursor never explicitly hides on
# mouse_exited -- matching source's own real behavior (the cursor always
# marks the current selection; moving the mouse off a list doesn't erase
# it, it simply stays wherever it last was), and incidentally sidesteps a
# flicker a naive show-on-enter/hide-on-exit pair would cause when the
# mouse crosses directly from one button to its neighbor.
func _wire_cursor_group(buttons: Array[Button]) -> void:
	for i in range(buttons.size()):
		var btn: Button = buttons[i]
		btn.set_meta("cursor_base_text", btn.text)
		btn.mouse_entered.connect(_set_cursor_selected.bind(buttons, i))
	if buttons.size() > 0:
		_set_cursor_selected(buttons, 0)


func _set_cursor_selected(buttons: Array[Button], selected_index: int) -> void:
	for i in range(buttons.size()):
		var btn: Button = buttons[i]
		var base_text: String = btn.get_meta("cursor_base_text")
		btn.text = (_CURSOR_PREFIX + base_text) if i == selected_index else (_CURSOR_BLANK + base_text)


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

# [M25h-1.4] The currently-open Item overlay, if any — see
# _build_item_buttons' own doc comment for why this needs an explicit
# idempotency guard rather than being rebuilt unconditionally like every
# other _build_*_buttons function.
var _item_select_overlay: Control = null

# [M25h-1.5] Same idempotency need as _item_select_overlay above, for the
# real Switch/Party overlay.
var _switch_select_overlay: Control = null

# [M26c-4] TARGET_SELECT click-to-target — real health-box hover zones
# instead of a text button per candidate, matching source's own real
# targeting cue in spirit (a bounce on the current candidate's health box)
# while staying mouse-only, since this project has no D-pad/keyboard
# navigation yet (M26d's own future job). See _build_target_select_buttons'
# own doc comment for the full source citation and design rationale.
#
# _target_select_wired tracks every health-group Control this session
# temporarily made clickable (mouse_filter STOP + 3 connected signals) so
# _clear_target_select_hover_wiring can precisely disconnect the exact
# bound Callables used and restore mouse_filter to IGNORE — these are
# PERSISTENT battlefield nodes (unlike _button_area/_new_button_area/
# _new_button_grid, which are freely rebuilt from scratch every refresh),
# so leaving a stale connection or a stuck STOP filter on one would leak
# into every future refresh, not just this one.
var _target_select_wired: Array[Dictionary] = []

# Which candidate currently has the hover-focus bounce/bob effect active,
# or null. Tracked (rather than trusting mouse_exited alone) so a
# _start_target_focus for a NEW candidate always tears down the OLD one
# first regardless of event ordering, and so a stray mouse_exited for a
# candidate that's no longer the focus (e.g. arriving after a newer
# mouse_entered already switched focus elsewhere) is a safe no-op.
var _target_focus_mon: BattlePokemon = null
var _target_focus_health_tween: Tween = null
var _target_focus_sprite_tween: Tween = null


func _ready() -> void:
	_load_battle_fonts()
	_setup_health_ui()
	_setup_action_region_panel()
	_setup_debug_overlay()
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

	# [M25c] Computed once, ahead of _wire_log_signals() below, since the very
	# first log lines (switch-in/hazard/ability messages from start_battle_*
	# a few lines down) already need to know whether to pace themselves.
	# Reused verbatim by the pre-existing "--autoplay" check further below
	# instead of re-deriving it a second time.
	_is_autoplay_run = "--autoplay" in OS.get_cmdline_args()

	# [M23.2, retargeted M26b] Wired unconditionally — interactive AND
	# autoplay both populate the merged debug/log history; only whether F3
	# is currently OPEN decides whether a new entry re-renders immediately
	# (see _add_debug_entry()'s own doc comment). "NARRATIVE" category —
	# today's move-announcement/damage/effectiveness text.
	_wire_log_signals()

	# [M26b] Every other category this design adds (RNG/Turn Order/
	# Durations/Stat Changes/Items & Berries/Multi-Hit/Delayed Effects/
	# Ability & Immunity/Niche) — kept in its own function, separate from
	# _wire_log_signals(), since that one function was already large before
	# this session and the two are conceptually distinct passes over the
	# same signal set.
	_wire_debug_signals()

	# [M23.11 Phase 5c] A SEPARATE connect() on the same move_executed signal
	# _wire_log_signals() already listens to above -- Godot signals support
	# multiple independent handlers, so this is purely additive and cannot
	# change _on_log_move_executed's own behavior/ordering. Wired
	# unconditionally (interactive + --autoplay both), matching every other
	# signal wire-up in this file.
	_bm.move_executed.connect(_on_hit_effect_move_executed)

	# [M25d, retargeted M26b] Combat-debug overlay — its own independent
	# connect(), same "additional listener on an existing signal" shape as
	# Phase 5c's hit-effect wiring immediately above. move_damage_breakdown
	# now feeds a DAMAGE_MATH-tagged entry into the same merged history
	# _wire_log_signals()/_wire_debug_signals() feed, rather than replacing
	# a separate Label wholesale.
	_bm.move_damage_breakdown.connect(_on_debug_move_damage_breakdown)

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
	if _is_autoplay_run:
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
	# [M26c-4] Defensive, matching _clear_active_hit_effects' own precedent
	# just above -- a focus tween is one more Tween object that could
	# otherwise outlive the node it's animating across a scene teardown.
	_clear_target_select_hover_wiring()


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
	# [M25c] turn_started/move_announced/move_effectiveness_computed are all
	# new this session — see each signal's own doc comment in battle_manager.gd
	# for exactly when/why each fires.
	_bm.turn_started.connect(_on_log_turn_started)
	_bm.move_announced.connect(_on_log_move_announced)
	_bm.move_effectiveness_computed.connect(_on_hit_effectiveness_computed)
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

	# [M26b] ability_triggered/ability_healed moved to _wire_debug_signals()
	# below — the locked design puts ability-trigger/immunity text in its own
	# "Ability & Immunity" category, not Narrative.


# [M26b] Turn separator is now structural, not a text line: _current_debug_
# turn is updated here and every subsequent _add_debug_entry() call stamps
# its entry with this value; _render_debug_overlay() inserts a visible
# "──── Turn N ────" separator itself whenever the rendered entry stream's
# own turn number changes, which correctly recomputes even after a category
# toggle hides some entries (since it's based on what's actually being
# rendered, not a fixed pre-baked text line).
func _on_log_turn_started(turn_number: int) -> void:
	_current_debug_turn = turn_number


# [M25c] Fires exactly once per action (see move_announced's own doc comment
# in battle_manager.gd) — this is the sole "used MOVE!" print site now;
# _on_log_move_executed below no longer prints it, so a 2-target spread hit
# (which fires move_executed twice) doesn't double-announce.
# Target naming: real pokeemerald_expansion phrasing never names a target in
# this line at all (STRINGID_USEDMOVE has no target slot) — this project
# deliberately goes further than that per its own explicit scope (naming the
# target reads better in a text-only log with no HP-bar-drain animation to
# supply that context visually). Named only when it's actually meaningful:
# omitted for a self-targeting move (defender == attacker, e.g. Swords
# Dance) and omitted for a spread hit (move.is_spread and doubles — no
# single "the target" exists; per-target detail comes from the damage/
# effectiveness lines below instead, once per real target).
func _on_log_move_announced(attacker: BattlePokemon, defender: BattlePokemon, move: MoveData) -> void:
	var text := "%s used %s" % [_mon_label(attacker), move.move_name]
	if defender != null and defender != attacker and not (move.is_spread and _is_doubles_mode):
		text += " on %s" % _mon_label(defender)
	_log(text + "!")


# [M25c] Buffers the effectiveness/crit result for the very next
# _on_log_move_executed call — always fires immediately before its
# corresponding move_executed within the same synchronous BattleManager call
# (see move_effectiveness_computed's own doc comment), so there is no
# ordering risk despite this being a separate handler.
func _on_hit_effectiveness_computed(_defender: BattlePokemon, effectiveness: float, is_crit: bool) -> void:
	_pending_hit_effectiveness = effectiveness
	_pending_hit_is_crit = is_crit
	_pending_hit_has_data = true


# [M25c] Fires once per TARGET (twice for a 2-target spread hit) — reports
# THIS hit's own crit/effectiveness/damage only; the shared "used MOVE!"
# announcement moved to _on_log_move_announced above. Phrasing/thresholds
# confirmed directly against reference/pokeemerald_expansion/src/battle_
# message.c: STRINGID_CRITICALHIT ("A critical hit!"), STRINGID_SUPEREFFECTIVE
# ("It's super effective!", >=2.0x), STRINGID_NOTVERYEFFECTIVE ("It's not
# very effective…", 0<x<1.0), STRINGID_ITDOESNTAFFECT ("It doesn't affect
# {target}…", exactly 0.0x — the real games DO name the target on this one
# line, unlike the super/not-very-effective lines, which name no one).
# Neutral (1.0x) stays silent on effectiveness, matching source exactly.
func _on_log_move_executed(_attacker: BattlePokemon, defender: BattlePokemon,
		_move: MoveData, damage: int) -> void:
	if _pending_hit_has_data:
		if _pending_hit_is_crit:
			_log("A critical hit!")
		if _pending_hit_effectiveness >= 2.0:
			_log("It's super effective!")
		elif _pending_hit_effectiveness == 0.0:
			_log("It doesn't affect %s…" % _mon_label(defender))
		elif _pending_hit_effectiveness < 1.0:
			_log("It's not very effective…")
		_pending_hit_has_data = false
	if damage > 0:
		_log("%s took %d damage!" % [_mon_label(defender), damage])
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


# [M26b] Retagged from Narrative into "Ability & Immunity" per the locked
# design — same text, new category.
func _on_log_ability_healed(mon: BattlePokemon, amount: int) -> void:
	if amount > 0:
		_add_debug_entry(DebugCategory.ABILITY_IMMUNITY,
				"%s recovered %d HP from its ability!" % [_mon_label(mon), amount])
	elif amount < 0:
		_add_debug_entry(DebugCategory.ABILITY_IMMUNITY,
				"%s was hurt by its ability! (%d damage)" % [_mon_label(mon), -amount])


# [ability_triggered message quality pass, retagged M26b] Looks up a readable
# message from _ABILITY_TRIGGER_TEXT; falls back to the old generic
# underscore-to-space formatter for any effect_key not in the table
# (requirement 4 — nothing silently breaks if a key is missed here or a new
# one is added to battle_manager.gd later). Now tagged "Ability & Immunity"
# instead of Narrative, per the locked M26b design.
func _on_log_ability_triggered(mon: BattlePokemon, effect_key: String) -> void:
	var template: Variant = _ABILITY_TRIGGER_TEXT.get(effect_key, null)
	if template != null:
		_add_debug_entry(DebugCategory.ABILITY_IMMUNITY, template % _mon_label(mon))
	else:
		_add_debug_entry(DebugCategory.ABILITY_IMMUNITY,
				"%s's %s activated!" % [_mon_label(mon), effect_key.replace("_", " ")])


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


# [M26c-4] Same singles-vs-doubles-aware lookup as _sprite_node_for, for a
# mon's own health-group Control instead of its sprite -- used to make the
# real health box itself the click/hover target for TARGET_SELECT.
func _health_group_for(mon: BattlePokemon) -> Control:
	if mon == null:
		return null
	var is_player: bool = _player_party.members.has(mon)
	if not _is_doubles_mode:
		return _player_health_group if is_player else _opponent_health_group
	var party: BattleParty = _player_party if is_player else _opp_party
	var slot := _field_slot_for(mon, party)
	var groups: Array = _ply_groups_d if is_player else _opp_groups_d
	return groups[slot] as Control


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


# [Split from _name_level_text, M26c-1 follow-up] The gender glyph is
# appended DIRECTLY after the name, no space — confirmed via source
# (reference/pokeemerald_expansion/src/battle_interface.c ::
# UpdateNickInHealthbox): `ptr = StringCopy(gDisplayedStringBattle,
# nickname)` returns a pointer immediately after the copied nickname, and
# `StringCopy(ptr, gText_HealthboxGender_Male/_Female/_None)` writes the
# glyph string starting exactly there — no separator of any kind. Source
# also has two gender-suppression special cases this project's simpler
# model doesn't need: the Nidoran M/F species-name-is-still-the-nickname
# check (this project has no nickname system at all — every mon is always
# shown by its own species name) and an opponent-side Ghost-illusion check
# (Illusion is a documented exclusion, `docs/m17_final_ledger.md`) — both
# structurally unreachable here, not silently dropped.
func _gender_glyph(gender: int) -> String:
	match gender:
		BattlePokemon.GENDER_MALE:
			return "♂"
		BattlePokemon.GENDER_FEMALE:
			return "♀"
		_:
			return ""


func _name_text(mon: BattlePokemon) -> String:
	return mon.species.species_name


# [M26c battle-UI polish] The gender glyph is now rendered by its own
# separate GenderLabel node, NOT appended into the name string -- per
# explicit request, so the glyph reads as a distinct element next to the
# name rather than part of the name text itself. Since the glyph's own
# horizontal position depends on how wide the (now-much-larger) name text
# renders, and Label offers no "size to content, then place a sibling right
# after it" layout primitive on its own, this measures the name's real
# rendered width via the SAME font/size the name label is using and places
# GenderLabel immediately after it -- recomputed on every call, so it stays
# correct across every font-size/box change this or a future session makes,
# rather than a hardcoded offset that would need re-tuning by hand.
# [M26c-2] level_label is optional (default null) so every pre-existing
# 3-arg caller/test is unaffected. When given, LevelLabel is ALSO
# repositioned dynamically, immediately after whichever of
# gender_label/name_label ends furthest right -- a fixed right-aligned box
# (this project's original design) overlaps the gender glyph for this
# project's own longest real species names (e.g. "Weepinbell"/"Aerodactyl",
# 10 characters) once the name font grew large enough to fill the box's
# top band, since the level box's own left edge never moved to make room.
# Positioning it dynamically, the same way gender_label already is, closes
# that gap by construction regardless of name length -- confirmed via a
# real screenshot with both 10-character worst-case names before this fix
# shipped (see this session's own scratch-driver verification).
#
# Clamped against the health group's own "Background" sibling's real width
# (read live, not hardcoded) -- an unclamped dynamic position pushed the
# level text past the databox's own right edge (and for the player group,
# off the visible screen entirely) for this project's longest real names,
# a real regression a follow-up screenshot caught. name_label's own parent
# is the health-group Control; falls back to no clamp when no "Background"
# sibling exists (e.g. this function's own bare-Label unit tests), matching
# this function's pre-clamp behavior for those callers.
func _position_gender_label(name_label: Label, gender_label: Label, mon: BattlePokemon,
		level_label: Label = null) -> void:
	var glyph := _gender_glyph(mon.gender)
	gender_label.text = glyph
	var font: Font = name_label.get_theme_font("font")
	if font == null:
		return
	var font_size: int = name_label.get_theme_font_size("font_size")
	var name_width: float = font.get_string_size(
			_name_text(mon), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var gap: float = font_size * 0.15
	var content_right: float = name_label.offset_left + name_width
	if not glyph.is_empty():
		gender_label.offset_top = name_label.offset_top
		gender_label.offset_bottom = name_label.offset_bottom
		gender_label.offset_left = name_label.offset_left + name_width + gap
		gender_label.offset_right = gender_label.offset_left + font_size * 1.2
		content_right = gender_label.offset_right
	if level_label != null:
		var level_width: float = font.get_string_size(
				_level_text(mon), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var desired_left: float = content_right + gap * 2.5
		var max_left: float = INF
		var parent := name_label.get_parent()
		if parent != null and parent.has_node("Background"):
			var background := parent.get_node("Background")
			max_left = background.offset_right - level_width - gap
		level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		level_label.offset_top = name_label.offset_top
		level_label.offset_bottom = name_label.offset_bottom
		level_label.offset_left = minf(desired_left, max_left)
		level_label.offset_right = level_label.offset_left + font_size * 4.0


# [M25d] "Lv" immediately followed by the number, no space — matches the
# real games' own exact convention (confirmed against reference/
# pokeemerald_expansion/src/battle_interface.c :: UpdateLvlInHealthbox,
# which writes `text[1] = CHAR_LV_2` directly followed by the level digits
# with nothing in between).
func _level_text(mon: BattlePokemon) -> String:
	return "Lv%d" % mon.level


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
		_add_debug_entry(DebugCategory.NARRATIVE, line)
	_pending_effect_lines.clear()


# [M26b] Every pre-existing call site below this function in the file is
# completely unchanged (text construction/wording/ordering all stayed
# exactly as M25c built it) — only WHERE the text ends up changed: it used
# to append straight to the always-visible LogLabel (with real-time paced
# reveal); it now becomes one NARRATIVE-tagged entry in the merged, F3-only
# debug/log history. Pacing (M25c's `_queue_log_line`/`_run_log_reveal`,
# 0.6s between lines) was deliberately dropped, not preserved — the merged
# view is an on-demand dev/inspection panel behind F3 (off by default), not
# a mandatory always-visible player experience, so there's no one "watching
# it happen live" to pace for; entries simply accumulate instantly as the
# engine resolves them, exactly like every non-Narrative category already
# does. This is a disclosed simplification versus the locked design's own
# text, which doesn't call for pacing at all in the merged view's spec.
func _log(text: String) -> void:
	_flush_pending_effect_lines()
	_add_debug_entry(DebugCategory.NARRATIVE, text)


# ── Combat debug/log [M26b] ──────────────────────────────────────────────
# The one shared sink every category-tagged handler in this file ultimately
# calls. Appends to the permanent `_debug_entries` history (never trimmed —
# see that var's own doc comment) and, only if the F3 panel is CURRENTLY
# open, re-renders immediately so an open panel always shows live data
# without needing to be closed and reopened.
func _add_debug_entry(category: int, text: String) -> void:
	_debug_entries.append({"turn": _current_debug_turn, "category": category, "text": text})
	if _debug_overlay != null and _debug_overlay.visible:
		_render_debug_overlay()


# Builds the toggle-button row once (default state per
# _DEBUG_CATEGORY_DEFAULT_ON) and configures the RichTextLabel body for
# BBCode + real scrolling (the "scrollable N-turn history" requirement —
# Godot's own ScrollContainer/RichTextLabel scrolling handles this natively
# over the full, never-discarded entry list; no separate windowing/
# "last N turns" trimming logic is needed). Guarded so a bare-instance test
# that never called _ready() (this project's own established convention)
# can still safely call _add_debug_entry()/_on_debug_category_toggled()
# without crashing on a null toggle-row/body.
func _setup_debug_overlay() -> void:
	for category in _DEBUG_CATEGORY_ORDER:
		_debug_category_on[category] = _DEBUG_CATEGORY_DEFAULT_ON[category]
	if _debug_toggle_row == null:
		return
	for category in _DEBUG_CATEGORY_ORDER:
		var cb := CheckBox.new()
		cb.text = _DEBUG_CATEGORY_LABEL[category]
		cb.button_pressed = _debug_category_on[category]
		cb.toggled.connect(_on_debug_category_toggled.bind(category))
		_debug_toggle_row.add_child(cb)
	if _debug_body != null:
		_debug_body.bbcode_enabled = true
		_debug_body.scroll_active = true


func _on_debug_category_toggled(pressed: bool, category: int) -> void:
	_debug_category_on[category] = pressed
	if _debug_overlay != null and _debug_overlay.visible:
		_render_debug_overlay()


# Filters the full, permanent `_debug_entries` history down to whatever's
# currently toggled on and rebuilds the displayed BBCode text from scratch —
# cheap enough for a single battle's worth of entries, and simplest to keep
# correct (no incremental-append bookkeeping to get wrong when a toggle
# flips). Inserts a turn separator whenever the RENDERED stream's own turn
# number changes (not a fixed pre-baked separator line), so toggling a
# category on/off recomputes separators correctly even though the
# underlying data never changes.
func _render_debug_overlay() -> void:
	if _debug_body == null:
		return
	var lines: Array[String] = []
	var last_turn := -1
	for entry in _debug_entries:
		var category: int = entry["category"]
		if not _debug_category_on.get(category, true):
			continue
		var turn: int = entry["turn"]
		if turn != last_turn:
			lines.append("[color=#888888]──── Turn %d ────[/color]" % turn)
			last_turn = turn
		lines.append("[color=%s]%s[/color]" % [_DEBUG_CATEGORY_COLOR.get(category, "#ffffff"), entry["text"]])
	_debug_body.text = "\n".join(lines)
	_debug_body.scroll_to_line(_debug_body.get_line_count())


# [M26b] Every category beyond Narrative/Damage Math. Grouped by real
# signal/data availability, confirmed via direct BattleManager source read
# before wiring anything (not assumed):
#
#   RNG & Probability — a REAL, MATERIAL GAP, disclosed rather than silently
#   worked around: raw roll values for accuracy/secondary-proc/confusion/
#   paralysis/flinch/speed-tie checks are NOT exposed anywhere in the
#   current codebase — the roll happens inside StatusManager/BattleManager
#   with only a boolean or reason-string ever crossing back out (confirmed:
#   `StatusManager.check_accuracy` returns bool only; `move_missed.emit(
#   attacker, "accuracy")` carries a reason string, no roll/threshold).
#   Building this fully would need new, separately-risked signal emissions
#   inside that RNG-consuming core logic — explicitly NOT done in this pass.
#   What IS wired below: the pass/fail OUTCOME of an accuracy check via the
#   existing move_missed/move_missed_target signals, tagged RNG, plus one
#   one-time disclosure entry so the gap is visible in the panel itself
#   rather than only in this comment.
#
#   Turn Order & Priority — real coverage limited to the splice-override
#   cases (After You/Quash) via the existing turn_order_changed signal.
#   Normal-case turn-order reasoning (speed comparison, priority bracket,
#   Trick Room inversion) has no exposing signal either — same gap shape as
#   RNG above, same disclosure treatment.
#
#   Durations & Field State / Stat Changes / Items & Berries / Multi-Hit
#   Detail / Delayed Effects / Ability & Immunity / Niche — all have real,
#   already-existing signals/fields to read (see each wiring block's own
#   comment for the specific source), no BattleManager changes needed.
func _wire_debug_signals() -> void:
	_add_debug_entry(DebugCategory.RNG,
			"[i]Raw roll values aren't exposed by the current engine — showing hit/miss outcomes only.[/i]")
	_add_debug_entry(DebugCategory.TURN_ORDER,
			"[i]Normal-case turn-order reasoning isn't exposed — showing only real After You/Quash splices.[/i]")

	# ── RNG & Probability (partial — see this function's own doc comment) ──
	# [Bugfix] move_missed's own `reason` is NOT always an RNG outcome — it's
	# a general "why didn't this move connect" tag covering 8 distinct cases
	# (confirmed via every move_missed.emit(...) call site in
	# battle_manager.gd): "protected"/"immune"/"doesnt_affect"/"substitute"/
	# "semi_invulnerable"/"ohko_failed"/"sturdy_blocks_ohko" are ALL
	# deterministic blocks with no roll involved at all — only "accuracy"
	# (used for both the ordinary accuracy check and the OHKO family's own
	# custom-formula roll, `battle_manager.gd`'s `DoesOHKOMoveMissTarget`
	# port) is a genuine probability outcome. The original version tagged
	# every reason as "accuracy check failed (%s)", which was actively wrong
	# for the 7 deterministic reasons and vacuously redundant for the one
	# real case ("accuracy check failed (accuracy)") — filtered to the one
	# reason that actually belongs under this category, and the now-
	# pointless self-referential parenthetical dropped entirely (there's
	# nothing else to report: the real roll value/threshold still isn't
	# exposed, per this function's own disclosure entry above).
	_bm.move_missed.connect(func(attacker: BattlePokemon, reason: String):
		if reason == "accuracy":
			_add_debug_entry(DebugCategory.RNG, "%s's accuracy check failed" % _mon_label(attacker)))
	_bm.move_missed_target.connect(func(attacker: BattlePokemon, target: BattlePokemon, reason: String):
		if reason == "accuracy":
			_add_debug_entry(DebugCategory.RNG,
					"%s's accuracy check failed against %s" % [_mon_label(attacker), _mon_label(target)]))
	_bm.secondary_applied.connect(func(target: BattlePokemon, _effect: int):
		_add_debug_entry(DebugCategory.RNG, "%s's secondary-effect roll succeeded" % _mon_label(target)))

	# ── Turn Order & Priority (partial — see this function's own doc comment) ──
	_bm.turn_order_changed.connect(func(mover: BattlePokemon, reason: String):
		_add_debug_entry(DebugCategory.TURN_ORDER, "%s's turn order changed (%s)" % [_mon_label(mover), reason]))

	# ── Durations & Field State — trick_room_turns/_side_conditions/
	# weather_duration are all real, already-tracked BattleManager fields;
	# reading them right after their own set/expire signal fires reports the
	# real starting/current duration, not a guessed one.
	_bm.trick_room_set.connect(func():
		_add_debug_entry(DebugCategory.DURATIONS, "Trick Room activated (%d turns)" % _bm.trick_room_turns))
	_bm.trick_room_ended.connect(func():
		_add_debug_entry(DebugCategory.DURATIONS, "Trick Room ended"))
	_bm.screen_set.connect(func(side: int, screen_name: String):
		var turns: int = _bm._side_conditions[side].get(screen_name + "_turns", 0)
		_add_debug_entry(DebugCategory.DURATIONS,
				"%s up on %s side (%d turns)" % [_SCREEN_NAMES.get(screen_name, screen_name), _side_label(side), turns]))
	_bm.screen_expired.connect(func(side: int, screen_name: String):
		_add_debug_entry(DebugCategory.DURATIONS,
				"%s expired on %s side" % [_SCREEN_NAMES.get(screen_name, screen_name), _side_label(side)]))
	_bm.hazard_set.connect(func(side: int, hazard_name: String, layers: int):
		_add_debug_entry(DebugCategory.DURATIONS,
				"%s set on %s side (layer %d)" % [_HAZARD_NAMES.get(hazard_name, hazard_name), _side_label(side), layers]))
	_bm.hazards_cleared.connect(func(side: int, hazard_name: String):
		_add_debug_entry(DebugCategory.DURATIONS,
				"%s cleared from %s side" % [_HAZARD_NAMES.get(hazard_name, hazard_name), _side_label(side)]))
	_bm.weather_set.connect(func(_by: BattlePokemon, weather_type: int):
		_add_debug_entry(DebugCategory.DURATIONS,
				"Weather %d set (%d turns)" % [weather_type, _bm.weather_duration]))
	_bm.weather_expired.connect(func(_weather_type: int):
		_add_debug_entry(DebugCategory.DURATIONS, "Weather expired"))
	_bm.side_condition_set.connect(func(side: int, condition_name: String):
		_add_debug_entry(DebugCategory.DURATIONS,
				"%s set on %s side" % [condition_name.capitalize(), _side_label(side)]))
	_bm.side_condition_expired.connect(func(side: int, condition_name: String):
		_add_debug_entry(DebugCategory.DURATIONS,
				"%s expired on %s side" % [condition_name.capitalize(), _side_label(side)]))
	_bm.field_sport_set.connect(func(sport_name: String):
		_add_debug_entry(DebugCategory.DURATIONS, "%s set (field-wide)" % sport_name.capitalize()))

	# ── Stat Changes — before->after stage values via stat_stage_changed's
	# own actual_change, computed at the UI layer (target.stat_stages[stat_idx]
	# is already the AFTER value by the time this signal fires).
	_bm.stat_stage_changed.connect(func(target: BattlePokemon, stat_idx: int, actual_change: int):
		if actual_change == 0:
			return
		var after: int = target.stat_stages[stat_idx]
		var before: int = after - actual_change
		var stat_name: String = _STAGE_NAMES[stat_idx] if stat_idx < _STAGE_NAMES.size() else "stat"
		_add_debug_entry(DebugCategory.STAT_CHANGES,
				"%s's %s: %+d -> %+d" % [_mon_label(target), stat_name, before, after]))

	# ── Items & Berries — real HP context (current/max) at the moment an
	# item/berry effect actually fired, not just that it fired.
	_bm.item_healed.connect(func(mon: BattlePokemon, amount: int):
		_add_debug_entry(DebugCategory.ITEMS_BERRIES,
				"%s's item healed %d (now %d/%d HP)" % [_mon_label(mon), amount, mon.current_hp, mon.max_hp]))
	_bm.item_damage.connect(func(mon: BattlePokemon, amount: int):
		_add_debug_entry(DebugCategory.ITEMS_BERRIES,
				"%s's item dealt %d (now %d/%d HP)" % [_mon_label(mon), amount, mon.current_hp, mon.max_hp]))
	_bm.item_consumed.connect(func(mon: BattlePokemon, item: ItemData):
		_add_debug_entry(DebugCategory.ITEMS_BERRIES,
				"%s consumed %s at %d/%d HP" % [_mon_label(mon), item.item_name, mon.current_hp, mon.max_hp]))
	_bm.item_action_used.connect(func(user: BattlePokemon, item: ItemData, target: BattlePokemon):
		_add_debug_entry(DebugCategory.ITEMS_BERRIES,
				"%s used %s on %s (%d/%d HP)" % [_mon_label(user), item.item_name, _mon_label(target), target.current_hp, target.max_hp]))
	_bm.item_effect_triggered.connect(func(mon: BattlePokemon, effect_key: String):
		_add_debug_entry(DebugCategory.ITEMS_BERRIES,
				"%s's item effect (%s) fired at %d/%d HP" % [_mon_label(mon), effect_key, mon.current_hp, mon.max_hp]))

	# ── Multi-Hit Detail — aggregate only (see multi_hit_sequence_finished's
	# own doc comment in battle_manager.gd: no per-hit breakdown signal
	# exists), disclosed inline rather than presented as complete.
	_bm.multi_hit_sequence_finished.connect(
			func(attacker: BattlePokemon, target: BattlePokemon, hits_landed: int, total_damage: int):
		_add_debug_entry(DebugCategory.MULTI_HIT,
				"%s's multi-hit vs %s: %d hits, %d total damage [i](aggregate only)[/i]"
						% [_mon_label(attacker), _mon_label(target), hits_landed, total_damage]))

	# ── Delayed Effects — real scheduled<->resolved signal pairs, correlated
	# here at the UI layer with zero BattleManager changes.
	_bm.future_sight_scheduled.connect(func(caster: BattlePokemon, target: BattlePokemon, move: MoveData):
		_add_debug_entry(DebugCategory.DELAYED,
				"%s scheduled %s against %s" % [_mon_label(caster), move.move_name, _mon_label(target)]))
	_bm.future_sight_resolved.connect(func(caster: BattlePokemon, target: BattlePokemon, move: MoveData, damage: int):
		_add_debug_entry(DebugCategory.DELAYED,
				"%s's scheduled %s resolved against %s: %d damage" % [_mon_label(caster), move.move_name, _mon_label(target), damage]))
	_bm.wish_scheduled.connect(func(caster: BattlePokemon):
		_add_debug_entry(DebugCategory.DELAYED, "%s scheduled Wish" % _mon_label(caster)))
	_bm.wish_resolved.connect(func(recipient: BattlePokemon, healed: int):
		_add_debug_entry(DebugCategory.DELAYED, "Wish resolved on %s: %d HP" % [_mon_label(recipient), healed]))
	_bm.yawn_set.connect(func(target: BattlePokemon):
		_add_debug_entry(DebugCategory.DELAYED, "%s scheduled to fall asleep (Yawn)" % _mon_label(target)))
	_bm.healing_wish_activated.connect(
			func(recipient: BattlePokemon, kind: String, healed: int, cured: bool, pp_restored: bool):
		_add_debug_entry(DebugCategory.DELAYED,
				"%s's %s resolved: %d HP, cured=%s, pp_restored=%s"
						% [_mon_label(recipient), kind, healed, cured, pp_restored]))

	# ── Ability & Immunity Interactions — Mold Breaker/Neutralizing Gas
	# suppressions and type-immunity absorb outcomes both already surface via
	# ability_triggered's own per-effect-key readable text (the same
	# lookup table _on_log_ability_triggered already uses) — no separate
	# mechanism needed, just a different category than Narrative.
	_bm.ability_triggered.connect(_on_log_ability_triggered)
	_bm.ability_healed.connect(_on_log_ability_healed)

	# ── Niche/Situational (default-off) — trapping-check reasoning has no
	# exposing signal (skipped, same gap shape as RNG/Turn Order above); the
	# rest are real, already-signaled mechanics.
	_bm.leech_seed_drained.connect(func(target: BattlePokemon, source: BattlePokemon, amount: int):
		_add_debug_entry(DebugCategory.NICHE,
				"Leech Seed: %s -> %s, %d" % [_mon_label(target), _mon_label(source), amount]))
	_bm.curse_damage.connect(func(mon: BattlePokemon, amount: int):
		_add_debug_entry(DebugCategory.NICHE, "%s's Curse tick: %d damage" % [_mon_label(mon), amount]))
	_bm.nightmare_damage.connect(func(target: BattlePokemon, amount: int):
		_add_debug_entry(DebugCategory.NICHE, "%s's Nightmare tick: %d damage" % [_mon_label(target), amount]))
	_bm.pp_drained.connect(func(mon: BattlePokemon, move: MoveData):
		_add_debug_entry(DebugCategory.NICHE, "%s's %s drained to 0 PP (Grudge)" % [_mon_label(mon), move.move_name]))
	_bm.pp_reduced.connect(func(target: BattlePokemon, move: MoveData, amount: int):
		_add_debug_entry(DebugCategory.NICHE,
				"%s's %s PP reduced by %d (Spite)" % [_mon_label(target), move.move_name, amount]))
	_bm.item_transferred.connect(func(from_mon: BattlePokemon, to_mon: BattlePokemon, item: ItemData):
		_add_debug_entry(DebugCategory.NICHE,
				"Item transferred: %s's %s -> %s" % [_mon_label(from_mon), item.item_name, _mon_label(to_mon)]))
	_bm.berry_stolen_and_eaten.connect(func(victim: BattlePokemon, beneficiary: BattlePokemon, item: ItemData):
		_add_debug_entry(DebugCategory.NICHE,
				"%s's %s stolen and eaten by %s" % [_mon_label(victim), item.item_name, _mon_label(beneficiary)]))
	_bm.item_stolen.connect(func(stealer: BattlePokemon, victim: BattlePokemon):
		_add_debug_entry(DebugCategory.NICHE, "%s stole %s's item" % [_mon_label(stealer), _mon_label(victim)]))
	_bm.items_swapped.connect(func(attacker: BattlePokemon, defender: BattlePokemon):
		_add_debug_entry(DebugCategory.NICHE,
				"Items swapped: %s <-> %s" % [_mon_label(attacker), _mon_label(defender)]))
	_bm.move_bounced.connect(func(holder: BattlePokemon, new_target: BattlePokemon):
		_add_debug_entry(DebugCategory.NICHE,
				"Move bounced by %s back at %s (Magic Bounce)" % [_mon_label(holder), _mon_label(new_target)]))
	_bm.move_stolen.connect(func(stealer: BattlePokemon, original_caster: BattlePokemon, move: MoveData):
		_add_debug_entry(DebugCategory.NICHE,
				"%s intercepted %s's %s (Snatch)" % [_mon_label(stealer), _mon_label(original_caster), move.move_name]))


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


# [M26c battle-UI polish] Bottom-anchors an opponent front-sprite box so its
# VISUAL bottom edge (the sprite's own real drawn-content bottom, not the
# 64x64 canvas's own bottom, which varies per species by however much
# transparent padding that species' own sprite art carries) always lands at
# the SAME fixed screen line regardless of which species is currently shown.
#
# `rect` keeps its own width fixed (`offset_left`/`offset_right` are never
# touched here) -- only `offset_top`/`offset_bottom` are recomputed, both
# derived from `base_top`/`base_bottom` (the box's own ORIGINAL, .tscn-
# authored offsets, captured once in _setup_health_ui() -- see that var's own
# doc comment for why a live/already-shifted offset can't be reused as the
# baseline).
#
# The real anchor mechanism is pokeemerald_expansion's own `frontPicYOffset`
# (see gen_sprite_y_offsets.py's doc comment for the full source citation:
# "the number of pixels between the drawn pixel area and the bottom edge" of
# the 64x64 source canvas) -- SpriteRegistry.get_front_y_offset(dex) exposes
# it dex-keyed. The box stays SQUARE (stretch_mode KEEP_ASPECT already set in
# the .tscn, unchanged here) and the source region stays the full, un-cropped
# 64x64 frame (idle-bob frame slicing untouched) -- so scale = box_width/64
# is constant regardless of species, and shifting the WHOLE box down by
# `y_offset * scale` exactly cancels out that species' own bottom padding,
# algebraically guaranteeing the sprite's own real content-bottom always
# lands at exactly `base_bottom` (worked out in full in this task's own
# planning -- content_bottom_screen simplifies to base_bottom for any
# y_offset, since the padding shifted INTO the box top is exactly what the
# whole-box downward shift adds back at the bottom).
func _apply_bottom_anchored_front_sprite(rect: TextureRect, dex: int, frame: int,
		base_top: float, base_bottom: float) -> void:
	rect.texture = _sprite_or_fallback_front(dex, frame)
	var width := rect.offset_right - rect.offset_left
	if width <= 0.0:
		return
	var scale := width / 64.0
	var shift := SpriteRegistry.get_front_y_offset(dex) * scale
	rect.offset_top = base_top + shift
	rect.offset_bottom = base_bottom + shift


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


# ── Combat-debug overlay [M25d, merged into the M26b history above] ────────
# [M26b] No longer replaces a dedicated Label wholesale — every real hit's
# breakdown becomes its own DAMAGE_MATH-tagged entry in the same permanent,
# never-discarded history every other category feeds, so a developer can
# scroll back through a whole battle's worth of breakdowns rather than only
# ever seeing the most recent one. In a 2v2 turn this means one entry per
# REAL damaging hit (up to 4 per turn, once per acting combatant).
func _on_debug_move_damage_breakdown(attacker: BattlePokemon, defender: BattlePokemon,
		move: MoveData, breakdown: Dictionary) -> void:
	_add_debug_entry(DebugCategory.DAMAGE_MATH, _format_debug_breakdown(attacker, defender, move, breakdown))


# Pure/static so a test can call it directly without a live signal round-trip
# -- matches _next_anim_frame's/_status_icon_row's own established
# precedent. `breakdown.get(..., default)` throughout: base_damage/
# stab_multiplier/roll are absent for the handful of fixed-damage/early-
# return moves that never reach DamageCalculator.calculate's main formula
# (Sonic Boom, Dragon Rage, OHKO, etc.) -- see move_damage_breakdown's own
# doc comment in battle_manager.gd for the full list of excluded cases.
# [M26b] The old leading "Combat Debug (F3 to toggle)" line was dropped —
# that's now the panel's own static Header label (shown once, not repeated
# per entry), since this text is now ONE entry among many in a scrolling
# history rather than the sole, wholesale-replaced content of the panel.
static func _format_debug_breakdown(attacker: BattlePokemon, defender: BattlePokemon,
		move: MoveData, breakdown: Dictionary) -> String:
	var atk_name: String = attacker.species.species_name
	var def_name: String = defender.species.species_name
	var lines: Array[String] = []
	lines.append("%s -> %s" % [atk_name, def_name])
	lines.append("Move: %s (Power %d, Acc %d)" % [move.move_name, move.power, move.accuracy])
	if breakdown.has("base_damage"):
		lines.append("Base damage: %d" % breakdown["base_damage"])
		lines.append("STAB: %.2fx" % (breakdown.get("stab_multiplier", 1.0) as float))
		lines.append("Type eff.: %.2fx" % (breakdown.get("effectiveness", 1.0) as float))
		lines.append("Crit: %s" % ("Yes" if breakdown.get("is_crit", false) else "No"))
		lines.append("Roll: %d%%" % (breakdown.get("roll", 100) as int))
	lines.append("Final damage: %d" % (breakdown.get("damage", 0) as int))
	return "\n".join(lines)


func _unhandled_input(event: InputEvent) -> void:
	# [M25d] Raw keycode check rather than an InputMap action -- this
	# project has no [input] section/action convention established yet
	# anywhere (confirmed via direct project.godot inspection before adding
	# this), so introducing one for a single debug toggle would be more
	# machinery than this task needs; a plain keycode check is the simplest
	# mechanism and stays entirely self-contained in this file.
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_F3:
		_debug_overlay.visible = not _debug_overlay.visible
		# [M26b] Re-render on open so a panel that accumulated entries while
		# closed shows them immediately, not just from the next new entry.
		if _debug_overlay.visible:
			_render_debug_overlay()


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
			_apply_bottom_anchored_front_sprite(_opp_sprites_d[slot], mon.species.national_dex_num,
					_opp_anim_frame_d[slot], _opp_sprite_d_base_top[slot], _opp_sprite_d_base_bottom[slot])
		return
	var side1_mon: BattlePokemon = _opp_party.get_active()
	if side1_mon == null:
		return
	_opponent_anim_frame = _next_anim_frame(_opponent_anim_frame, side1_mon.fainted)
	_apply_bottom_anchored_front_sprite(_opponent_sprite, side1_mon.species.national_dex_num,
			_opponent_anim_frame, _opponent_sprite_base_top, _opponent_sprite_base_bottom)


# [M23.11 Phase 4a, recolored M26c-1] Green/yellow/red HP-fraction
# threshold -- applied via TextureProgressBar.tint_progress as of Phase 4b
# (was modulate on a plain ProgressBar before); the function's own shape is
# unchanged, only the 3 return values changed. [M26c-1] Now the REAL sourced
# colors from the Emerald UI Pack's own Graphics/UI/Battle/overlay_hp.png
# (96x12 -- 3 stacked shadow/highlight color PAIRS, confirmed via direct
# pixel sampling, not invented) -- each threshold uses that pair's own
# brighter "highlight" value, matching how gen_databox_sprites.py's own doc
# comment explains this file was intentionally NOT pulled as a texture
# asset (it's flat, uniform color bands with no pixel detail worth
# preserving as a file -- a tinted solid fill reproduces it exactly).
func _hp_bar_color(current: int, max_hp: int) -> Color:
	if max_hp <= 0:
		return Color(1, 1, 1)
	var frac := float(current) / float(max_hp)
	if frac > 0.5:
		return Color8(115, 255, 173)
	elif frac > 0.2:
		return Color8(255, 231, 57)
	return Color8(255, 90, 57)


# [M26c-1] The Emerald UI Pack's own real EXP-bar color, sampled directly
# from Graphics/UI/Battle/overlay_exp.png (170x4, one single flat color --
# no shadow/highlight pair, unlike the HP bar's own 3-state bands, matching
# the real games' own EXP bar never changing color).
const _EXP_BAR_COLOR := Color8(66, 206, 255)


# [M26c-1] A tiny solid-color-tintable fill texture, generated once at
# runtime rather than pulled as an asset file -- both the HP bar and the
# new EXP bar are plain rectangular fills with no shape/border of their own
# (the pill/bar OUTLINE is now baked directly into the databox art itself,
# see gen_databox_sprites.py's own doc comment), so a 1x1 white pixel
# stretched by TextureProgressBar's own fill + recolored via tint_progress
# reproduces either bar exactly, matching this file's own established
# "generate simple textures in code, don't manage a file for it" precedent
# (_color_keyed_texture below does the equivalent transform for a different
# case). Replaces Phase 4b's old hpbar.png-sourced AtlasTexture fill
# region entirely -- that file (and its "HP" label region, now redundant
# since the new databox art bakes "HP" in directly) is no longer loaded
# anywhere in this script.
static func _solid_fill_texture() -> ImageTexture:
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	return ImageTexture.create_from_image(img)


# [Bugfix, found via real screenshot verification] TextureProgressBar does
# NOT stretch `texture_progress` to the control's own size by default --
# confirmed via a dedicated isolated repro scene: without `nine_patch_
# stretch`, the fill renders at the TEXTURE's own native pixel dimensions
# (clipped by the fill fraction), regardless of how big the control itself
# is -- for a 1x1 fill texture this meant NOTHING was visible at all (a
# "bar" 1 pixel wide, invisible at any zoom level a screenshot would catch).
# `nine_patch_stretch = true` with all 4 stretch margins at 0 (no fixed
# corners at all -- the whole texture is "middle," which is correct for a
# flat solid color with no border/corner art of its own) makes it behave
# the way a plain ColorRect would: genuinely stretched to fill the
# control's own real size. Applied uniformly to every HP/EXP fill bar
# (singles + doubles) via this one shared helper, rather than repeating
# the same 5 property assignments at each of the 7 call sites.
static func _configure_solid_fill_bar(bar: TextureProgressBar, fill_tex: Texture2D) -> void:
	bar.texture_progress = fill_tex
	bar.fill_mode = TextureProgressBar.FILL_LEFT_TO_RIGHT
	bar.nine_patch_stretch = true
	bar.stretch_margin_left = 0
	bar.stretch_margin_right = 0
	bar.stretch_margin_top = 0
	bar.stretch_margin_bottom = 0


# [M26c-1] Real progress-to-next-level fraction, reusing M20's own already-
# correct EXP infrastructure verbatim (mirrors BattleManager._check_level_up's
# exact pattern: growth rate read FRESH from PokemonRegistry by the mon's
# CURRENT species.national_dex_num, never cached/assumed on the instance —
# see that function's own doc comment for why this matters for a future
# evolution mechanic). Not static: no state needed beyond the parameter, but
# kept as an instance method to match _hp_bar_color's own established shape
# for the two sibling "compute a HP/EXP bar fraction" functions.
#
# [Disclosed fallback] A hand-built test fixture (this screen's own
# _make_mon-style fallback teams, built via PokemonSpecies.new() with no
# real national_dex_num) has no real registry entry to look up -- dex 0
# resolves to an empty Dictionary, growth_rate defaults to "", and
# PokemonRegistry.get_exp_for_level("", level) returns 0 for any level
# (confirmed via that function's own empty-curve early-return), making
# `needed` 0 and this function return 0.0 -- an empty bar, not a crash or a
# misleading fabricated value. Only a real PokemonFactory-built Pokémon
# (Team Builder, random teams, trainer battles) has real growth-rate data
# to show progress for.
func _exp_bar_fraction(mon: BattlePokemon) -> float:
	if mon.species == null or mon.level >= 100:
		return 0.0
	var dex: int = mon.species.national_dex_num
	var species_data: Dictionary = PokemonRegistry.get_species(dex)
	var growth_rate: String = species_data.get("growth_rate", "")
	var exp_this_level: int = PokemonRegistry.get_exp_for_level(growth_rate, mon.level)
	var exp_next_level: int = PokemonRegistry.get_exp_for_level(growth_rate, mon.level + 1)
	var needed: int = exp_next_level - exp_this_level
	if needed <= 0:
		return 0.0
	var into: int = mon.current_exp - exp_this_level
	return clampf(float(into) / float(needed), 0.0, 1.0)


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
# which itself shares BUILDING's tiles), and it's also BattleBackgroundRegistry's own
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
	# [M25h-1.2] Real bitmap font (FONT_SMALL, "healthbox" context -- see
	# gen_battle_fonts.py's own Step 0 citation for sHealthBoxTextColor).
	# Unlike the message/menu contexts, this one's own bulk-fill role is
	# genuinely TRANSPARENT (a real GBA sprite-palette-index-0 hardware
	# convention, not an opaque plaque color) -- confirmed via source, and
	# correct here too: these labels sit directly on top of the already-
	# pulled real health-box art (Phase 4b), which must stay visible through
	# the unlit parts of each glyph. font_size stays at each node's own
	# pre-existing value (13 singles / 9 doubles, a real-estate constraint
	# from M25d, not changed here) -- doubles' non-native-size scaling of a
	# 13px-native bitmap font is a disclosed minor softness, not a blocker.
	for label: Label in [_opponent_name_label, _opponent_gender_label, _opponent_level_label,
			_player_name_label, _player_gender_label, _player_level_label, _player_hp_number_label]:
		label.add_theme_font_override("font", _font_healthbox)
		label.add_theme_color_override("font_color", Color(1, 1, 1, 1))

	# [M26c-1] Real Emerald UI Pack databox art (see gen_databox_sprites.py's
	# own doc comment for the full Step 0 sourcing) — supersedes Phase 4b's
	# raw-pokeemerald-decode health-box art. "HP" is baked directly into
	# both files as real pixel art now, so the old separate HpLabel overlay
	# node is gone entirely (removed from battle_screen.tscn), not just
	# hidden. The Background nodes' own `texture` property is set directly
	# in battle_screen.tscn (an ExtResource reference), not here — a real
	# pulled asset needs to render live in the Godot editor viewport
	# without running the scene, which a script-only `load()` assignment
	# can't provide.
	var fill_tex := _solid_fill_texture()
	_configure_solid_fill_bar(_opponent_hp_fill, fill_tex)
	_configure_solid_fill_bar(_player_hp_fill, fill_tex)

	# [M26c-1] The new EXP bar — singles player only (see _player_exp_fill's
	# own onready doc comment for why). Same solid-fill-plus-tint mechanism
	# as the HP bar, just a fixed color rather than a threshold function.
	_configure_solid_fill_bar(_player_exp_fill, fill_tex)
	_player_exp_fill.tint_progress = _EXP_BAR_COLOR
	_player_exp_fill.min_value = 0.0
	_player_exp_fill.max_value = 1.0
	_player_exp_fill.step = 0.0

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
	# plain Arrays. `fill_tex` (the shared solid-color fill texture) is
	# safely SHARED across every node here (singles' own existing code
	# already shares it between the opponent and player nodes) since it
	# never changes after creation — only each node's own `tint_progress`
	# differs. Status icons are the one thing that CANNOT share an atlas
	# instance across slots —
	# two doubles opponents can have different statuses simultaneously, and
	# mutating one shared atlas's .region would corrupt every node
	# displaying it — so each of the 4 doubles slots gets its own freshly-
	# created AtlasTexture, matching the singles opponent/player split
	# already established, just doubled.
	# [M26c battle-UI polish] Bottom-anchor baselines, captured HERE (once,
	# before any species-driven texture/offset write ever touches these
	# nodes) rather than read lazily on first use -- _setup_health_ui() is
	# the first thing _ready() calls, guaranteeing every later
	# _apply_bottom_anchored_front_sprite() call always has a real, still-
	# original baseline to compute from.
	_opponent_sprite_base_top = _opponent_sprite.offset_top
	_opponent_sprite_base_bottom = _opponent_sprite.offset_bottom

	_opp_sprites_d = [$BattleStage/OpponentSpriteD0, $BattleStage/OpponentSpriteD1]
	_opp_sprite_d_base_top = [_opp_sprites_d[0].offset_top, _opp_sprites_d[1].offset_top]
	_opp_sprite_d_base_bottom = [_opp_sprites_d[0].offset_bottom, _opp_sprites_d[1].offset_bottom]
	_opp_groups_d = [$BattleStage/OpponentHealthGroupD0, $BattleStage/OpponentHealthGroupD1]
	_opp_bg_d = [$BattleStage/OpponentHealthGroupD0/Background, $BattleStage/OpponentHealthGroupD1/Background]
	_opp_status_icon_d = [$BattleStage/OpponentHealthGroupD0/StatusIcon, $BattleStage/OpponentHealthGroupD1/StatusIcon]
	_opp_hp_fill_d = [$BattleStage/OpponentHealthGroupD0/HpFill, $BattleStage/OpponentHealthGroupD1/HpFill]
	_opp_name_label_d = [$BattleStage/OpponentHealthGroupD0/NameLabel, $BattleStage/OpponentHealthGroupD1/NameLabel]
	_opp_gender_label_d = [$BattleStage/OpponentHealthGroupD0/GenderLabel, $BattleStage/OpponentHealthGroupD1/GenderLabel]
	_opp_level_label_d = [$BattleStage/OpponentHealthGroupD0/LevelLabel, $BattleStage/OpponentHealthGroupD1/LevelLabel]

	_ply_sprites_d = [$BattleStage/PlayerSpriteD0, $BattleStage/PlayerSpriteD1]
	_ply_groups_d = [$BattleStage/PlayerHealthGroupD0, $BattleStage/PlayerHealthGroupD1]
	_ply_bg_d = [$BattleStage/PlayerHealthGroupD0/Background, $BattleStage/PlayerHealthGroupD1/Background]
	_ply_status_icon_d = [$BattleStage/PlayerHealthGroupD0/StatusIcon, $BattleStage/PlayerHealthGroupD1/StatusIcon]
	_ply_hp_fill_d = [$BattleStage/PlayerHealthGroupD0/HpFill, $BattleStage/PlayerHealthGroupD1/HpFill]
	_ply_name_label_d = [$BattleStage/PlayerHealthGroupD0/NameLabel, $BattleStage/PlayerHealthGroupD1/NameLabel]
	_ply_gender_label_d = [$BattleStage/PlayerHealthGroupD0/GenderLabel, $BattleStage/PlayerHealthGroupD1/GenderLabel]
	_ply_level_label_d = [$BattleStage/PlayerHealthGroupD0/LevelLabel, $BattleStage/PlayerHealthGroupD1/LevelLabel]

	# [M25h-1.2, split M26c-1 follow-up] Same real bitmap font as the singles
	# name/level pair above, applied to all 4 doubles slots' 12 label nodes
	# now that the arrays exist.
	for label: Label in (_opp_name_label_d + _opp_gender_label_d + _opp_level_label_d
			+ _ply_name_label_d + _ply_gender_label_d + _ply_level_label_d):
		label.add_theme_font_override("font", _font_healthbox)
		label.add_theme_color_override("font_color", Color(1, 1, 1, 1))

	# [M26c-1] Real Emerald UI Pack doubles ("thin") databox art -- see
	# gen_databox_sprites.py's own doc comment: this pack ships no EXP-ledge
	# variant for either doubles box, confirming the EXP bar's own singles-
	# player-only scope isn't just a design choice made in isolation. Each
	# of the 4 doubles Background nodes' own `texture` property is set
	# directly in battle_screen.tscn, same reasoning as the singles pair
	# above -- not re-assigned here.
	for i in range(2):
		_configure_solid_fill_bar(_opp_hp_fill_d[i], fill_tex)
		var opp_atlas_d := AtlasTexture.new()
		opp_atlas_d.atlas = opponent_status_sheet
		opp_atlas_d.region = Rect2(Vector2.ZERO, _STATUS_ICON_SIZE)
		_opp_status_atlas_d[i] = opp_atlas_d
		_opp_status_icon_d[i].texture = opp_atlas_d

		_configure_solid_fill_bar(_ply_hp_fill_d[i], fill_tex)
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

# [M25h-1.1] text_window/1.png's own background-key color and margin —
# confirmed via direct pixel inspection, not assumed from std.png's own
# values (they differ): pixel 0 (a SINGLE pixel, not std.png's own 2px) is
# key color RGB (98, 197, 98) alpha=255, then a 5px decorative border/
# transition band (pixels 1-5), then a flat white interior starting at
# pixel 6 (12px wide, mirrored on the far edge: 1+5+12+5+1=24, matching the
# file's own 24x24 size exactly). This is `graphics/text_window/1.png` in
# source — `sWindowFrames[0]`, the file `LoadUserWindowBorderGfx` actually
# draws for the battle message/action-menu/move-select window border
# (`LoadBattleMenuWindowGfx` -> `LoadUserWindowBorderGfx` -> `LoadWindowGfx`
# indexed by `gSaveBlock2Ptr->optionsWindowFrameType`, defaulting to 0 on a
# fresh save per `new_game.c`) — confirmed directly against source, NOT the
# same asset Phase 4e's own `_MESSAGE_BOX_KEY_COLOR`/std.png pull used
# (that file is drawn by the separate `LoadStdWindowGfx` function instead,
# used elsewhere, not for battle's own message/action windows). Both files
# were already present in this project's own Phase 1 asset pull (the whole
# `text_window/` directory, all 20 numbered frames + std/message_box/
# name_box/signpost, was pulled then even though only std.png was ever
# actually wired up) — so this session needed zero new asset pull, only
# correctly identifying and applying the one that was always the real match.
const _ACTION_PANEL_KEY_COLOR := Color8(98, 197, 98, 255)
const _ACTION_PANEL_MARGIN := 6.0

# [M23.11 Phase 4e] Pure function (no scene/Image-loading side effects of its
# own) so a headless test can verify the color-matching logic directly
# without needing a real Image/texture round-trip. `is_equal_approx`'s
# default epsilon is far tighter than a single 8-bit channel step, so this
# is effectively an exact match — correct and sufficient here, since a
# palette-indexed PNG's background-key color is byte-identical across every
# pixel (confirmed directly against the real std.png asset in this phase's
# own test suite), not something that needs fuzzy tolerance.
# [M25h-1.1] Generalized to accept the key color explicitly rather than
# reading the module-level constant directly, so the same pure check works
# for text_window/1.png's own different key color too — every existing
# caller (still implicitly std.png-only, via _color_keyed_texture's own
# default) is unaffected.
static func _is_message_box_key_color(c: Color, key_color: Color = _MESSAGE_BOX_KEY_COLOR) -> bool:
	return c.is_equal_approx(key_color)


# [M23.11 Phase 4e] Loads text_window/std.png, replaces every background-key
# pixel with real alpha=0 (see _MESSAGE_BOX_KEY_COLOR's own doc comment),
# and returns the result as a fresh ImageTexture. Runtime color-keying
# rather than an offline preprocessing script -- matches this file's own
# established "script controls final on-screen appearance" convention
# (the HP-bar/status-icon AtlasTexture slicing in _setup_health_ui above is
# the same shape: load the raw pulled art, transform it in code, never touch
# the file on disk).
# [M25h-1.1] Gained an explicit key_color param (default preserves the
# original std.png-only behavior for _setup_message_box's own call site
# unchanged) so _setup_action_region_panel below can reuse this same
# function for text_window/1.png's own different key color instead of a
# near-duplicate copy.
static func _color_keyed_texture(source: Image, key_color: Color = _MESSAGE_BOX_KEY_COLOR) -> ImageTexture:
	var img := source.duplicate()
	img.convert(Image.FORMAT_RGBA8)
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			if _is_message_box_key_color(img.get_pixel(x, y), key_color):
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)


# [M23.11 Phase 4e, RETIRED by M26b] `_setup_message_box()` used to apply
# real text_window/std.png art + the real bitmap message font to the old
# always-visible VBox/LogLabel — removed outright along with that node (see
# the former `_log_label` onready var's own doc comment for the full
# reasoning). `_color_keyed_texture`/`_MESSAGE_BOX_MARGIN`/
# `_MESSAGE_BOX_KEY_COLOR` themselves are NOT retired — ItemSelectScreen/
# SwitchSelectScreen both still call `_color_keyed_texture` directly for
# their own real window art, and `_is_message_box_key_color`'s default
# key-color param still points at `_MESSAGE_BOX_KEY_COLOR`.


# [M25h-1.1] Real window art for the new shared bottom region (ActionRegion
# -> ActionPanel), built in M25h-1 with no visual styling at all. Uses
# text_window/1.png specifically, not std.png -- see _ACTION_PANEL_KEY_COLOR's
# own doc comment for the full source citation on why this is the real
# asset for B_WIN_MSG/B_WIN_ACTION_MENU/B_WIN_ACTION_PROMPT/move-select,
# not the file Phase 4e's own _setup_message_box already applied to the
# (separately-styled, untouched-by-this-session) log. PanelContainer
# (ActionPanel) rather than a raw stylebox on ActionVBox directly -- unlike
# Label/RichTextLabel, VBoxContainer has no "normal"/panel theme slot of
# its own; PanelContainer is the standard Godot container specifically for
# "a background panel behind a group of child controls, with automatic
# margin inset from the stylebox's own texture_margin values."
func _setup_action_region_panel() -> void:
	var raw_image: Image = load("res://assets/sprites/battle_ui/text_window/1.png").get_image()
	var keyed_texture: ImageTexture = _color_keyed_texture(raw_image, _ACTION_PANEL_KEY_COLOR)

	var panel_style := StyleBoxTexture.new()
	panel_style.texture = keyed_texture
	panel_style.texture_margin_left = _ACTION_PANEL_MARGIN
	panel_style.texture_margin_top = _ACTION_PANEL_MARGIN
	panel_style.texture_margin_right = _ACTION_PANEL_MARGIN
	panel_style.texture_margin_bottom = _ACTION_PANEL_MARGIN

	_action_panel.add_theme_stylebox_override("panel", panel_style)

	# [M25h-1.2] Real bitmap font -- StatusLabel shows the "What will X do?"
	# style prompt text, matching source's B_WIN_ACTION_PROMPT (the SAME
	# color context as B_WIN_MSG/LogLabel -- see gen_battle_fonts.py's own
	# Step 0 citation). Supersedes the flat near-black `font_color` fix
	# Phase 4e/M25h-1.1 originally applied here for the same reason
	# _setup_message_box's own updated comment explains: a real bitmap
	# font's pixels are already colored, so the override is now a neutral
	# Color(1,1,1,1) instead of a tint that would crush the baked-in red.
	_status_label.add_theme_font_override("font", _font_message)
	_status_label.add_theme_font_size_override("font_size", _FONT_NORMAL_SIZE)
	_status_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))


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
		status_icons: Array, status_atlases: Array, hp_fills: Array,
		name_labels: Array, level_labels: Array,
		sprite_base_top: Array = [], sprite_base_bottom: Array = [],
		gender_labels: Array = []) -> void:
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
			_apply_bottom_anchored_front_sprite(sprites[slot], mon.species.national_dex_num, 0,
					sprite_base_top[slot], sprite_base_bottom[slot])
		sprites[slot].modulate = Color(1, 1, 1, 0.3) if mon.fainted else Color(1, 1, 1, 1)
		hp_fills[slot].max_value = mon.max_hp
		hp_fills[slot].value = mon.current_hp
		hp_fills[slot].tint_progress = _hp_bar_color(mon.current_hp, mon.max_hp)
		_update_status_icon(status_icons[slot], status_atlases[slot], mon.status)
		name_labels[slot].text = _name_text(mon)
		level_labels[slot].text = _level_text(mon)
		if not gender_labels.is_empty():
			_position_gender_label(name_labels[slot], gender_labels[slot], mon, level_labels[slot])


func _refresh_ui() -> void:
	# [M25h-1, extended M26c-3] All three button areas are cleared
	# unconditionally every call — only whichever ones _menu actually needs
	# get repopulated below, so the others stay empty (visually absent)
	# rather than needing an explicit show/hide toggle. This is exactly
	# what makes the ITEM/SWITCH (old _button_area) <-> TOP/FIGHT (new
	# _new_button_grid) <-> TARGET_SELECT (new _new_button_area) hybrid
	# transitions work correctly with no special-casing: a Back button from
	# any region just sets _menu and calls _refresh_ui() as before. FIGHT is
	# the one state that repopulates TWO of the three at once (the real 2x2
	# move grid in _new_button_grid, plus a single Back button in
	# _new_button_area, rendered as the row immediately below the grid) —
	# see _build_fight_menu's own doc comment for why Back isn't a 5th grid
	# cell.
	for child in _button_area.get_children():
		child.queue_free()
	for child in _new_button_area.get_children():
		child.queue_free()
	for child in _new_button_grid.get_children():
		child.queue_free()
	# [M26c-4] TARGET_SELECT's own click/hover zones live on PERSISTENT
	# battlefield nodes (health groups), not a freely-rebuilt container —
	# see _clear_target_select_hover_wiring's own doc comment for why this
	# needs an explicit disconnect pass rather than a plain queue_free loop.
	_clear_target_select_hover_wiring()

	var side0_mon: BattlePokemon = _player_party.get_active()
	var side1_mon: BattlePokemon = _opp_party.get_active()

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
				_opp_status_icon_d, _opp_status_atlas_d, _opp_hp_fill_d, _opp_name_label_d, _opp_level_label_d,
				_opp_sprite_d_base_top, _opp_sprite_d_base_bottom, _opp_gender_label_d)
		_refresh_doubles_side(_player_party, true, _ply_sprites_d, _ply_groups_d,
				_ply_status_icon_d, _ply_status_atlas_d, _ply_hp_fill_d, _ply_name_label_d, _ply_level_label_d,
				[], [], _ply_gender_label_d)
	else:
		_opponent_anim_frame = 0
		_apply_bottom_anchored_front_sprite(_opponent_sprite, side1_mon.species.national_dex_num,
				_opponent_anim_frame, _opponent_sprite_base_top, _opponent_sprite_base_bottom)
		_opponent_sprite.modulate = Color(1, 1, 1, 0.3) if side1_mon.fainted else Color(1, 1, 1, 1)
		_opponent_hp_fill.max_value = side1_mon.max_hp
		_opponent_hp_fill.value = side1_mon.current_hp
		_opponent_hp_fill.tint_progress = _hp_bar_color(side1_mon.current_hp, side1_mon.max_hp)
		_update_status_icon(_opponent_status_icon, _opponent_status_atlas, side1_mon.status)
		_opponent_name_label.text = _name_text(side1_mon)
		_opponent_level_label.text = _level_text(side1_mon)
		_position_gender_label(_opponent_name_label, _opponent_gender_label, side1_mon, _opponent_level_label)

		_player_sprite.texture = _sprite_or_fallback_back(side0_mon.species.national_dex_num)
		_player_sprite.modulate = Color(1, 1, 1, 0.3) if side0_mon.fainted else Color(1, 1, 1, 1)
		_player_hp_fill.max_value = side0_mon.max_hp
		_player_hp_fill.value = side0_mon.current_hp
		_player_hp_fill.tint_progress = _hp_bar_color(side0_mon.current_hp, side0_mon.max_hp)
		_player_hp_number_label.text = "%d/%d" % [side0_mon.current_hp, side0_mon.max_hp]
		_update_status_icon(_player_status_icon, _player_status_atlas, side0_mon.status)
		_player_name_label.text = _name_text(side0_mon)
		_player_level_label.text = _level_text(side0_mon)
		_position_gender_label(_player_name_label, _player_gender_label, side0_mon, _player_level_label)
		_player_exp_fill.value = _exp_bar_fraction(side0_mon)

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
# [M25h-1.3] Deliberately NOT chrome-stripped/cursor-wired — this button
# lives in `_button_area` ($VBox/ButtonArea), which has no real window art
# behind it at all (unlike ActionPanel's own text_window/1.png pull). See
# _strip_button_chrome's own doc comment for why stripping chrome here
# would be a real legibility regression, not a fix.
func _build_battle_end_buttons() -> void:
	var play_again_btn := Button.new()
	_style_menu_button(play_again_btn)
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
# [M25b, regridded M26c-3] Real top-level Fight/Bag/Pokémon/Run menu — the
# 4 real games' own top-level options, replacing the old single screen that
# showed every move button inline alongside Switch/Item.
#
# [M26c-3] Laid out as a real 2x2 GRID now, not a vertical list — confirmed
# directly from source rather than assumed: `ActionSelectionCreateCursorAt`
# (battle_controller_player.c) positions its tile-paste cursor via
# `7 * (cursorPosition & 1) + 16, 35 + (cursorPosition & 2)` — bit 0 of the
# cursor position selects the COLUMN, bit 1 selects the ROW, giving a fixed
# 2x2 cell layout, not a scrollable list. The A_BUTTON dispatch switch in
# the same file confirms the real cell assignment: cursor 0 (top-left) =
# B_ACTION_USE_MOVE (Fight), 1 (top-right) = B_ACTION_USE_ITEM (Bag), 2
# (bottom-left) = B_ACTION_SWITCH (Pokémon), 3 (bottom-right) =
# B_ACTION_RUN (Run) — a genuinely different reading order from this
# project's own prior vertical Fight/Switch/Item/Run list (Item and Switch
# swap positions). `GridContainer(columns=2)` lays out children left-to-
# right, top-to-bottom as they're added, so adding them in exactly this
# order (Fight, Item, Switch, Run) reproduces the real cell grid with zero
# extra positioning code. D-pad-driven cursor movement (source's own
# `DPAD_LEFT/RIGHT/UP/DOWN` handlers, which XOR the relevant bit) is
# deliberately NOT reproduced here — this project's menus have no
# keyboard/gamepad navigation at all yet (confirmed via grep, M25h-1.3),
# that's M26d's own separate job; mouse hover already drives the same ▶
# cursor via `_wire_cursor_group` regardless of grid vs. list shape.
func _build_top_menu(field_slot: int) -> void:
	var fight_btn := Button.new()
	_style_menu_button(fight_btn)
	_strip_button_chrome(fight_btn)
	fight_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fight_btn.text = "Fight"
	fight_btn.pressed.connect(func():
		_menu = Menu.FIGHT
		_refresh_ui())
	_new_button_grid.add_child(fight_btn)

	# [M25h-1] Switch/Item still route to the old, untouched inline panels
	# (_button_area, in $VBox) -- pressing either of these buttons (now
	# living in the new region) transitions OUT of the new region into the
	# old one. _refresh_ui()'s own unconditional clear-all is what makes
	# this correct with zero special-casing. Real separate screens for both
	# are M25h-1.4/M25h-1.5's own job (already shipped) — this session only
	# moves WHERE their own launcher buttons live, not their own behavior.
	var item_btn := Button.new()
	_style_menu_button(item_btn)
	_strip_button_chrome(item_btn)
	item_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_btn.text = "Item"
	item_btn.pressed.connect(func():
		_menu = Menu.ITEM
		_refresh_ui())
	_new_button_grid.add_child(item_btn)

	var switch_btn := Button.new()
	_style_menu_button(switch_btn)
	_strip_button_chrome(switch_btn)
	switch_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	switch_btn.text = "Switch"
	switch_btn.disabled = not _player_party.has_valid_switch_target()
	switch_btn.pressed.connect(func():
		_menu = Menu.SWITCH
		_refresh_ui())
	_new_button_grid.add_child(switch_btn)

	# [M25b] Temporary placeholder — NOT real flee logic (success chance,
	# speed comparison, trainer-battle refusal, etc. are all explicitly out
	# of scope this session, per this sub-phase's own locked scope note).
	# Exists because there is currently no way to exit an in-progress
	# battle at all otherwise. See _on_run_pressed's own doc comment for
	# exactly what it does.
	var run_btn := Button.new()
	_style_menu_button(run_btn)
	_strip_button_chrome(run_btn)
	run_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	run_btn.text = "Run"
	run_btn.pressed.connect(_on_run_pressed)
	_new_button_grid.add_child(run_btn)

	# [M25h-1.3] Real ▶ cursor, defaulting to Fight (index 0) -- matches
	# source's own always-defined initial cursor position. Array order here
	# matches the grid's own real reading order (top-left, top-right,
	# bottom-left, bottom-right), same as the add_child order above.
	var top_buttons: Array[Button] = [fight_btn, item_btn, switch_btn, run_btn]
	_wire_cursor_group(top_buttons)


# [M25b, regridded M26c-3] The move list — content unchanged from the old
# _build_main_menu's own move-button loop, just moved one tier deeper
# (behind Fight).
#
# [M26c-3] Laid out as a real 2x2 grid now, matching source's own confirmed
# layout — see _build_top_menu's own doc comment for the full source
# citation (the same `ActionSelectionCreateCursorAt`-shaped bit-math cursor
# is used for move selection too, via the sibling `MoveSelectionCreateCursorAt`
# in the same file). Move slot index IS the grid cell index directly in
# source (`gMoveSelectionCursor` is both the move array index AND the
# cursor position the same bit-math decodes) — this project's own moves
# array is already in that exact order, so no remapping is needed: move 0
# lands top-left, move 1 top-right, move 2 bottom-left, move 3 bottom-
# right, purely as a side effect of adding them to a
# `GridContainer(columns=2)` in array order. A Pokémon with fewer than 4
# moves naturally leaves the trailing grid cell(s) empty (GridContainer
# just doesn't lay out a row/cell that has no child) — matching source's
# own real clamping behavior (`gNumberOfMovesToChoose`), which likewise
# never lets the cursor land on a slot with no real move.
#
# Back is deliberately NOT a 5th grid cell — source doesn't need one at
# all (B_BUTTON always cancels back to the action-selection grid, and this
# project has no keyboard input wired yet, M26d's own job), so a literal
# 5th cell would be a pure invention with no source basis, more visual
# noise than the real 2x2 core. Instead it reuses _new_button_area (the
# same VBoxContainer TARGET_SELECT/SWITCH/ITEM already used before this
# session), which renders as a single row directly below the grid in the
# same ActionVBox stack — a real, disclosed mouse-only concession, not a
# reproduction of anything in source.
func _build_fight_menu(field_slot: int) -> void:
	var mon: BattlePokemon = _player_party.get_active_at(field_slot)
	var fight_buttons: Array[Button] = []
	for i in range(mon.moves.size()):
		var move: MoveData = mon.moves[i]
		if move == null:
			continue
		var btn := Button.new()
		_style_menu_button(btn)
		_strip_button_chrome(btn)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.text = "%s (PP %d/%d)" % [move.move_name, mon.current_pp[i], move.pp]
		btn.disabled = mon.current_pp[i] <= 0
		btn.pressed.connect(_on_move_pressed.bind(field_slot, i))
		_new_button_grid.add_child(btn)
		fight_buttons.append(btn)

	var back_btn := Button.new()
	_style_menu_button(back_btn)
	_strip_button_chrome(back_btn)
	back_btn.text = "Back"
	back_btn.pressed.connect(func():
		_menu = Menu.TOP
		_refresh_ui())
	_new_button_area.add_child(back_btn)
	fight_buttons.append(back_btn)

	# [M25h-1.3] Real ▶ cursor, defaulting to the first move. One shared
	# cursor group spans both containers (grid cells + the Back row below
	# them) -- _wire_cursor_group only needs an ordered Array[Button], it
	# has no dependency on every button sharing one parent.
	_wire_cursor_group(fight_buttons)


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


# [M25h-1.5] Switch is now a real separate full-screen overlay
# (SwitchSelectScreen), matching source's own OpenPartyMenuToChooseMon/
# OpenPartyMenuInBattle architecture — see switch_select_screen.gd's own doc
# comment for the full rationale, identical in shape to M25h-1.4's Item
# overlay. Idempotent for the same reason as _build_item_buttons: _refresh_ui
# can legitimately re-enter this function while a switch/replacement is
# already being chosen (e.g. a doubles refresh triggered by the OTHER field
# slot mid-selection) — guarded so a second call never stacks a duplicate
# overlay on top of an already-open one.
#
# [M25a bugfix, preserved unchanged] A forced replacement (SWITCH_PROMPT)
# with genuinely NO valid bench candidate (e.g. a doubles battle where the
# only remaining live party member is already active in the OTHER field
# slot) used to leave the old inline screen with zero buttons -- a real
# hardlock, since BattleManager's own _phase_switch_prompt waits
# indefinitely for queue_replacement_for() on a human-controlled side, and
# nothing could ever call it. BattleManager already handles an explicit "no
# replacement" submission correctly (_get_replacement_slot falls through to
# BattleParty.get_first_non_fainted_not_active(), which returns -1 and
# resolves this slot as "no replacement available" — the same fallback the
# AI-driven path already relies on) — this just needed to actually BE
# submitted rather than the player being left with nothing to press.
# Auto-resolves the same turn a real player would otherwise be stuck on,
# instead of requiring a screen that can't show anything. This check runs
# BEFORE the overlay is ever opened, so the zero-candidate case never shows
# a screen at all (matching the old inline behavior exactly) rather than
# opening a real screen with zero rows and a stray Cancel.
func _build_switch_buttons(is_forced_replacement: bool, field_slot: int) -> void:
	if _switch_select_overlay != null and is_instance_valid(_switch_select_overlay):
		return

	var any_candidate := _party_has_switch_candidate(_player_party)
	if is_forced_replacement and not any_candidate:
		_bm.queue_replacement_for(field_slot, -1)
		_bm.advance()
		_refresh_ui()
		return

	var overlay_scene: PackedScene = load("res://scenes/battle/switch_select_screen.tscn")
	var overlay: SwitchSelectScreen = overlay_scene.instantiate()
	add_child(overlay)
	overlay.mon_chosen.connect(_on_switch_screen_mon_chosen.bind(is_forced_replacement, field_slot))
	overlay.cancelled.connect(_on_switch_screen_cancelled.bind(field_slot))
	overlay.setup(self, field_slot, is_forced_replacement)
	_switch_select_overlay = overlay


func _on_switch_screen_mon_chosen(slot: int, is_forced_replacement: bool, field_slot: int) -> void:
	_close_switch_select_overlay()
	_on_switch_pressed(slot, is_forced_replacement, field_slot)


func _on_switch_screen_cancelled(field_slot: int) -> void:
	_close_switch_select_overlay()
	_menu = Menu.TOP
	_refresh_ui()


func _close_switch_select_overlay() -> void:
	if _switch_select_overlay != null and is_instance_valid(_switch_select_overlay):
		_switch_select_overlay.queue_free()
	_switch_select_overlay = null


# [M25h-1.4] Item is now a real separate full-screen overlay (ItemSelectScreen)
# rather than an inline `_button_area` panel — see item_select_screen.gd's own
# doc comment for the full architecture rationale (a child overlay on the
# still-alive battle_screen instance, not a literal change_scene_to_file swap,
# since BattleManager must survive the trip). Idempotent: `_refresh_ui()` can
# legitimately re-enter this function while `_menu == Menu.ITEM` (e.g. a
# doubles-mode refresh triggered by the OTHER field slot while this one is
# still mid-selection) — guarded so a second call never stacks a duplicate
# overlay on top of an already-open one.
func _build_item_buttons(field_slot: int) -> void:
	if _item_select_overlay != null and is_instance_valid(_item_select_overlay):
		return
	var overlay_scene: PackedScene = load("res://scenes/battle/item_select_screen.tscn")
	var overlay: ItemSelectScreen = overlay_scene.instantiate()
	add_child(overlay)
	overlay.item_chosen.connect(_on_item_screen_item_chosen.bind(field_slot))
	overlay.cancelled.connect(_on_item_screen_cancelled.bind(field_slot))
	overlay.setup(self, field_slot)
	_item_select_overlay = overlay


func _on_item_screen_item_chosen(item_id: int, field_slot: int) -> void:
	_close_item_select_overlay()
	_on_item_pressed(item_id, field_slot)


func _on_item_screen_cancelled(field_slot: int) -> void:
	_close_item_select_overlay()
	_menu = Menu.TOP
	_refresh_ui()


func _close_item_select_overlay() -> void:
	if _item_select_overlay != null and is_instance_valid(_item_select_overlay):
		_item_select_overlay.queue_free()
	_item_select_overlay = null


# [M26c-4] Starts the hover-focus bounce/bob for `mon`, tearing down
# whatever candidate previously had it first (regardless of event
# ordering -- see _target_focus_mon's own field doc comment). Two visual
# treatments, chosen by which side `mon` is on, per Rob's own explicit
# design call:
#   - EITHER side's health box bounces (a small vertical position
#     ping-pong loop) -- this part is symmetric.
#   - The OPPONENT's sprite additionally cycles through its own real
#     2-frame idle-bob art (the same frames/anchoring
#     _apply_bottom_anchored_front_sprite already draws for the ambient
#     one-shot entry animation, M23.11 Phase 4c) -- reused here as a
#     repeating loop instead, since a real animation asset already exists
#     for front sprites.
#   - A PLAYER-side sprite (only reachable in doubles, e.g. Acupressure/
#     Helping Hand targeting an ally) instead gets the same positional
#     bob as the health box -- back sprites are single-frame everywhere
#     except Deoxys (SpriteRegistry's own doc comment), so there is no
#     second real frame to alternate to.
# Source itself uses a blink (SpriteCB_ShowAsMoveTarget/
# SpriteCB_BlinkVisible, battle_main.c) for the targeted sprite -- this is
# a deliberate, disclosed departure, reusing this project's own existing
# idle-bob asset instead of building a new blink effect from scratch.
func _start_target_focus(mon: BattlePokemon) -> void:
	_stop_target_focus()
	_target_focus_mon = mon

	var health_group := _health_group_for(mon)
	if health_group != null:
		var orig_y: float = health_group.position.y
		health_group.set_meta("_focus_orig_y", orig_y)
		var hb_tween := create_tween().set_loops()
		hb_tween.tween_property(health_group, "position:y", orig_y - 5.0, 0.15) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		hb_tween.tween_property(health_group, "position:y", orig_y, 0.15) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_target_focus_health_tween = hb_tween

	var sprite := _sprite_node_for(mon)
	if sprite == null:
		return
	var is_player: bool = _player_party.members.has(mon)
	if is_player:
		var orig_sy: float = sprite.position.y
		sprite.set_meta("_focus_orig_y", orig_sy)
		var sp_tween := create_tween().set_loops()
		sp_tween.tween_property(sprite, "position:y", orig_sy - 5.0, 0.15) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		sp_tween.tween_property(sprite, "position:y", orig_sy, 0.15) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_target_focus_sprite_tween = sp_tween
	else:
		var dex := mon.species.national_dex_num
		var base_top: float
		var base_bottom: float
		if _is_doubles_mode:
			var slot := _field_slot_for(mon, _opp_party)
			base_top = _opp_sprite_d_base_top[slot]
			base_bottom = _opp_sprite_d_base_bottom[slot]
		else:
			base_top = _opponent_sprite_base_top
			base_bottom = _opponent_sprite_base_bottom
		var frame_tween := create_tween().set_loops()
		frame_tween.tween_callback(_apply_bottom_anchored_front_sprite.bind(
				sprite, dex, 1, base_top, base_bottom)).set_delay(0.5)
		frame_tween.tween_callback(_apply_bottom_anchored_front_sprite.bind(
				sprite, dex, 0, base_top, base_bottom)).set_delay(0.5)
		_target_focus_sprite_tween = frame_tween


# [M26c-4] Kills both active tweens (if any) and restores every property
# they were animating back to its real pre-focus value -- position for the
# health box and (player-side only) the sprite; the opponent's own frame
# is reset to 0 via the same _apply_bottom_anchored_front_sprite call every
# other "state changed" refresh site already uses, not a position restore.
func _stop_target_focus() -> void:
	if _target_focus_health_tween != null and _target_focus_health_tween.is_valid():
		_target_focus_health_tween.kill()
	if _target_focus_sprite_tween != null and _target_focus_sprite_tween.is_valid():
		_target_focus_sprite_tween.kill()

	if _target_focus_mon != null:
		var health_group := _health_group_for(_target_focus_mon)
		if health_group != null and health_group.has_meta("_focus_orig_y"):
			health_group.position.y = health_group.get_meta("_focus_orig_y")

		var sprite := _sprite_node_for(_target_focus_mon)
		var is_player: bool = _player_party.members.has(_target_focus_mon)
		if sprite != null:
			if is_player and sprite.has_meta("_focus_orig_y"):
				sprite.position.y = sprite.get_meta("_focus_orig_y")
			elif not is_player:
				var dex := _target_focus_mon.species.national_dex_num
				if _is_doubles_mode:
					var slot := _field_slot_for(_target_focus_mon, _opp_party)
					_apply_bottom_anchored_front_sprite(sprite, dex, 0,
							_opp_sprite_d_base_top[slot], _opp_sprite_d_base_bottom[slot])
				else:
					_apply_bottom_anchored_front_sprite(sprite, dex, 0,
							_opponent_sprite_base_top, _opponent_sprite_base_bottom)

	_target_focus_mon = null
	_target_focus_health_tween = null
	_target_focus_sprite_tween = null


func _on_target_hover_entered(mon: BattlePokemon) -> void:
	_start_target_focus(mon)


func _on_target_hover_exited(mon: BattlePokemon) -> void:
	# Only reset if THIS candidate is still the one actually focused --
	# guards against a stray exit for a candidate that's no longer current
	# (e.g. arriving after a newer mouse_entered on a different candidate
	# already switched focus elsewhere).
	if _target_focus_mon == mon:
		_stop_target_focus()


func _on_target_hover_gui_input(event: InputEvent, field_slot: int, move_index: int, target_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_target_selected(field_slot, move_index, target_idx)


# [M26c-4] Unwires every health-group Control _build_target_select_buttons
# temporarily made clickable -- restores mouse_filter to IGNORE and
# disconnects the exact bound Callables that were connected (tracked in
# _target_select_wired, not re-derived), since these are PERSISTENT
# battlefield nodes, unlike _button_area/_new_button_area/_new_button_grid
# which are freely rebuilt from scratch every refresh. Called
# unconditionally at the top of every _refresh_ui(), the same "clear
# everything, only whichever _menu actually needs gets repopulated"
# pattern the other three button containers already use.
func _clear_target_select_hover_wiring() -> void:
	_stop_target_focus()
	for entry: Dictionary in _target_select_wired:
		var group: Control = entry["group"]
		if group == null or not is_instance_valid(group):
			continue
		group.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if group.mouse_entered.is_connected(entry["enter_cb"]):
			group.mouse_entered.disconnect(entry["enter_cb"])
		if group.mouse_exited.is_connected(entry["exit_cb"]):
			group.mouse_exited.disconnect(entry["exit_cb"])
		if group.gui_input.is_connected(entry["click_cb"]):
			group.gui_input.disconnect(entry["click_cb"])
	_target_select_wired.clear()


# [M23.11 Phase 4f, regridded M26c-4] Target-picker — real click/hover
# zones directly on each live candidate's own health box, returned by
# BattleManager.get_live_targets(mon, move) (see that function's own doc
# comment for exactly which candidates show up here: 2 live opponents for
# an ordinary foe-targeting move in doubles, or [self, ally] for
# TARGET_USER_OR_ALLY moves like Acupressure). Only ever built when
# _on_move_pressed has already confirmed candidates.size() > 1 — this
# function doesn't re-check ambiguity itself, matching every other
# _build_*_buttons function's existing "caller already decided to show
# this menu" convention.
#
# [M26c-4] Confirmed directly from source (HandleInputChooseTarget,
# battle_controller_player.c) that real targeting has no text menu at all
# — the game bounces the current candidate's health box and lets D-pad
# Left/Right/Up/Down cycle it between the 4 battle positions. This project
# has no D-pad/keyboard navigation anywhere yet (M26d's own future job,
# confirmed via the same grep M25h-1.3 already ran finding none exists),
# so this reproduces the SPATIAL part (click the Pokémon you want to hit,
# its health box bounces to confirm the hover) without the cycling input
# — a disclosed, deliberate mouse-only interim, not the full source
# mechanism. Each candidate's own health-group Control AND its sprite
# Control (both already uniquely-positioned, always-visible Controls per
# combatant — no new node needed) are temporarily made clickable via
# _target_select_wired, per explicit request: hovering OR clicking either
# the health bar or the Pokémon's own sprite triggers the same focus
# animation / submits the same target. Back stays a real Button (still
# the only way to cancel with no keyboard input to bind Back/B to).
func _build_target_select_buttons(field_slot: int, move_index: int) -> void:
	var mon: BattlePokemon = _player_party.get_active_at(field_slot)
	var move: MoveData = mon.moves[move_index]
	var candidates: Array[BattlePokemon] = _bm.get_live_targets(mon, move)
	for target_mon: BattlePokemon in candidates:
		var target_idx: int = _bm.get_combatant_index(target_mon)
		var enter_cb: Callable = _on_target_hover_entered.bind(target_mon)
		var exit_cb: Callable = _on_target_hover_exited.bind(target_mon)
		var click_cb: Callable = _on_target_hover_gui_input.bind(field_slot, move_index, target_idx)
		for zone: Control in [_health_group_for(target_mon), _sprite_node_for(target_mon)]:
			if zone == null:
				continue
			zone.mouse_filter = Control.MOUSE_FILTER_STOP
			zone.mouse_entered.connect(enter_cb)
			zone.mouse_exited.connect(exit_cb)
			zone.gui_input.connect(click_cb)
			_target_select_wired.append({
				"group": zone, "enter_cb": enter_cb, "exit_cb": exit_cb, "click_cb": click_cb,
			})

	# [M23.11 Phase 4f] Matches every other sub-menu's own "Back" convention
	# (_build_switch_buttons'/_build_item_buttons' non-forced branches) —
	# returns to the move list for this same slot without submitting an
	# action, so the player can pick a different move instead.
	# [M25b] Returns to FIGHT specifically (not all the way to TOP) — the
	# immediate previous step in the now-two-tier menu, so picking a
	# different move doesn't require re-entering Fight from the top menu.
	var back_btn := Button.new()
	_style_menu_button(back_btn)
	_strip_button_chrome(back_btn)
	back_btn.text = "Back"
	back_btn.pressed.connect(func():
		_menu = Menu.FIGHT
		_pending_move_index = -1
		_refresh_ui())
	_new_button_area.add_child(back_btn)

	# [M25h-1.3] Real ▶ cursor -- kept even for this single remaining
	# button so _base_text()'s established "every button always carries
	# either the real prefix or the blank one" assumption (relied on by
	# every existing test's own text-comparison helper) stays true.
	_wire_cursor_group([back_btn])


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
