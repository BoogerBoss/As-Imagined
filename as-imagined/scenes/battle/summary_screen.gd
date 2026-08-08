extends Control
class_name SummaryScreen

# [M26E4-2] A genuine separate full-screen Summary/Stats view, matching
# source's own real architecture (`CursorCb_Summary` ->
# `ShowPokemonSummaryScreen(SUMMARY_MODE_LOCK_MOVES, party, slot, max,
# CB2_ReturnToPartyMenuFromSummaryScreen)`, docs/m26_e4_recon.md §1.3) -- the
# same overlay-not-scene-swap pattern already established by ItemSelectScreen/
# SwitchSelectScreen (BattleManager lives inside the battle scene and must
# survive the round trip; see item_select_screen.gd's own doc comment for the
# full rationale, unchanged here).
#
# [Built battle-agnostic, per M27I's own "built once and shared" commitment
# (docs/m26_e4_recon.md §5)] Constructed over a plain BattleParty + a start
# index -- no BattleManager coupling of any kind. `_parent_bs` is used ONLY
# for its already-shared display/chrome helpers (`_name_text`/`_level_text`/
# `_gender_glyph`/`_style_menu_button`/`_strip_button_chrome`/
# `_wire_cursor_group`/`_type_badge_texture`/`_category_icon_texture`), every
# one of which is already screen-agnostic itself -- so this screen has no
# dependency on being opened from inside a live battle and can be reused
# unchanged by a future non-battle Pokémon-storage/roster context.
#
# [Real source citation -- LOCK_MOVES mode, §1.3] "LOCK_MOVES only disables
# move reordering (and relearn/rename prompts): all four pages stay
# reachable, and Up/Down cycles party mons (eggs skipped off-INFO; range =
# own side)." This project has no egg concept at all, so mon-cycling here is
# a plain wraparound cycle over every member of the supplied party with
# nothing to skip. Move reordering/relearning/renaming were never built in
# the first place (no such mechanism exists anywhere in this project), so
# there is nothing LOCK_MOVES needs to actively suppress -- the mode name is
# not modeled as a real flag, since every future consumer of this same
# screen would want the identical (no-reorder) behavior for the same
# real-data-integrity reason.
#
# [Real source citation -- pages clamp, don't wrap, §3] "pages clamp (no
# wrap), Up/Down cycles mons, L/R changes page." Reproduced exactly: L/R
# (here, two page-nav buttons) stop at page 1/4 rather than wrapping back
# around to the other end; mon-cycling DOES wrap (source's own Up/Down at
# the party's own first/last member wraps to the opposite end -- confirmed
# via the recipe's own `pbChangePokemon` looping index arithmetic).
#
# [Return-path contract, §1.3] "On close, gLastViewedMonIndex is handed back
# so the party cursor follows the viewed mon, and the party menu reopens
# directly into the action submenu." Reproduced via the `closed(last_viewed_
# slot)` signal -- SwitchSelectScreen (this screen's own E3 entry point) is
# responsible for moving its own cursor to `last_viewed_slot` and reopening
# its action submenu there, exactly matching this source behavior (a
# separate concern from this screen, which only ever reports which slot it
# was last showing).
#
# [Real scene-tree-visible UI -- Rob's own standing preference] Every fixed-
# position/fixed-content element (background, mon sprite, every chrome/
# SKILLS/MOVES label, every icon, every nav/row button) is a REAL node
# authored directly in summary_screen.tscn -- position, size, default
# texture, and font are all editable there in the Godot editor. This script
# only BINDS to those already-existing nodes (`_bind_nodes`, called from
# `setup()` via plain `$NodeName` lookups -- deliberately NOT `@onready`,
# since `@onready` only resolves once a node's branch actually enters the
# live SceneTree, and this screen is routinely instantiated and driven
# directly in tests, and even in production is `add_child()`ed by a
# SwitchSelectScreen that is ITSELF frequently off-tree in this project's own
# established bare-instance test convention -- `$NodeName` resolution via
# plain `get_node()` has no such liveness requirement), applies whatever
# RUNTIME-only behavior still needs `_parent_bs` (button chrome-stripping/
# color states, the shared "▶" cursor group -- both genuinely behavioral, not
# positional, so they stay in code), and updates `.text`/`.texture`/color
# overrides per the current page/mon/selection in `_refresh()`.
#
# [E4-3 scope -- SKILLS + MOVES(+detail) dynamic content] Everything on this
# page is source-verified directly against 001_Summary.rb's own `drawPageTwo`
# (SKILLS)/`drawPageThree`+`drawSelectedMove` (MOVES) functions, not
# estimated from the earlier recon prose summary -- see the per-section doc
# comments below for exact citations, including one real correction: §1.2's
# own prose lists "EXP points, NEXT LV." as SKILLS-page content, but the real
# recipe (`drawPageOne`, line ~451-473) draws EXP on the INFO page instead.
# EXP is therefore deliberately NOT built here -- it belongs to E4-4's own
# INFO-page work, not a scope cut from this session.
#
# INFO page's own dynamic content (types, ability text on INFO specifically,
# OT/memo reserved slots) and the EVS-IVS page remain E4-4's job, unbuilt
# here.


const _SUMMARY_DIR := "res://assets/sprites/battle_ui/summary/"

# [M26 Fire-Red art swap] The real architecture (see
# gen_summary_screen_sprites_frlg.py's own doc comment for the full source
# citation, including the Step-0 tilemap-naming disambiguation and the
# empirically-confirmed absolute-palette-index decode rule): `_portrait_
# base` is ALWAYS `summary_frlg_frame_base.png` (the real Fire Red INFO
# tilemap -- BG3, never swapped, the persistent portrait column every page
# shows through), and `_page_overlay` is the CURRENT page's own content,
# drawn on top of it (BG1, real per-page tilemap) -- empty string means
# "no overlay, the base layer alone is correct" (INFO itself; CONTEST_
# MOVES/egg are permanently out of this project's own locked scope).
#
# [Full swap, this session] Every entry below is now Fire-Red-sourced,
# including EVS-IVS -- pulled as bonus scope alongside the required INFO/
# SKILLS/MOVES set (Fire Red's own real EV/IV summary page exists in the
# `pokefirered-expansion` fork this project sources from; vanilla
# pokefirered lacks it). This is a background-only swap -- no new EVS-IVS
# DYNAMIC content (stat/EV/IV values) is built this session, matching how
# the page's own reserved slot sat unwired before this swap too; that
# remains E4-4's own future job.
const _PAGE_OVERLAY := [
	"",  # INFO -- the base layer already IS the real INFO page.
	"summary_frlg_page_skills.png",
	"summary_frlg_page_moves.png",
	"summary_frlg_page_evs_ivs.png",
]
const _PAGE_NAMES := ["INFO", "SKILLS", "MOVES", "EVS/IVS"]
const NUM_PAGES := 4
const _PAGE_INFO := 0
const _PAGE_SKILLS := 1
const _PAGE_MOVES := 2

# [Real source colors, 001_Summary.rb drawPageTwo/drawPageThree/
# drawSelectedMove -- sampled directly from the recipe's own Color.new(...)
# literals, not invented] Neutral stat/nature/ribbon/ability-description
# text.
const _COLOR_NEUTRAL_FG := Color8(0, 0, 0)
const _COLOR_NEUTRAL_SHADOW := Color8(214, 214, 206)
# A nature-raised stat.
const _COLOR_RAISED_FG := Color8(224, 8, 8)
const _COLOR_RAISED_SHADOW := Color8(248, 184, 112)
# A nature-lowered stat.
const _COLOR_LOWERED_FG := Color8(24, 160, 208)
const _COLOR_LOWERED_SHADOW := Color8(136, 240, 248)
# Ability/move NAME text.
#
# [Fire-Red-source correction] Real source (`sPrintMoveTextColors`,
# MOVE_TEXT_COLOR_0) always colors the move name with a fixed LIGHT_GREEN/
# BLUE pair, regardless of PP tier -- resolving that against this
# specific window's own active palette wasn't traced here. The concrete,
# confirmed bug this replaces: the PREVIOUS near-white pair
# (248,248,248 fg / 96,96,96 shadow) was invisible against the MOVES
# page's own light mint/white row background (242,248,248) -- near-zero
# contrast, found via screenshot. Switched to this pack's own established
# dark-on-light convention (matching DexLabel/ItemLabel/etc.) for
# guaranteed legibility; matching source's exact literal RGB is a
# separate, not-yet-done follow-up.
const _COLOR_NAME_FG := Color8(0, 0, 0)
const _COLOR_NAME_SHADOW := Color8(214, 214, 206)
# The 4-tier PP color ramp, exact `ppBase`/`ppShadow` arrays (both
# drawPageThree and drawSelectedMove define the identical literal array) --
# index 0 = more than half remaining, 1 = half or less, 2 = a quarter or
# less, 3 = zero.
const _PP_TIER_FG := [Color8(74, 74, 74), Color8(248, 192, 0),
		Color8(247, 132, 49), Color8(248, 8, 8)]
const _PP_TIER_SHADOW := [Color8(222, 222, 222), Color8(239, 239, 173),
		Color8(248, 184, 112), Color8(248, 184, 112)]
# Power/accuracy text in the move-detail panel -- literally the same pair as
# PP tier 0 (`base`/`shadow` re-declared identically in drawSelectedMove).
const _COLOR_DETAIL_FG := Color8(74, 74, 74)
const _COLOR_DETAIL_SHADOW := Color8(222, 222, 222)

# [M26E4 rework, Phase 3 -- cursor-convention decision] Source shows which
# move is selected via a real sprite-based selection box
# (`move_select.png`, a 4-part triangle+outline composite) -- neither
# pulled nor consumed by this project yet, matching Phase 1's own "cursor
# and EXP-bar tiles deferred to later phases" scope note; pulling and
# compositing that asset is real scope beyond a repositioning pass. In its
# place, a cheap text-color highlight on the selected row's own name label
# signals which move's detail panel is currently open. Move rows are
# deliberately NOT run through the shared "▶" cursor-group convention (see
# _wire_behavior()'s own doc comment) -- that's for a list of mutually
# exclusive actions, not this row's own toggle-a-detail-panel behavior.
const _COLOR_SELECTED_NAME_FG := Color8(248, 208, 8)
const _COLOR_SELECTED_NAME_SHADOW := Color8(96, 72, 0)

signal closed(last_viewed_slot: int)

# [Doubles-split roadmap parity] Deliberately UNTYPED -- see
# item_select_screen.gd's own identical field for the full rationale.
var _parent_bs = null
var _party: BattleParty = null
var _mon_index: int = 0
var _page: int = 0

# [E4-3] Which of the current mon's own move slots (0-3) is showing its
# detail panel, or -1 for none -- a real toggle (source's own USE/B-button
# mode switch), reset whenever the page or the viewed mon changes (matching
# source: leaving the MOVES page or switching to a different Pokémon always
# drops back to the plain list view, never carries a stale selection to a
# context it no longer applies to).
var _selected_move_index: int = -1

# [Real scene-tree-visible UI] Bound (not `@onready`) from the real nodes
# authored in summary_screen.tscn -- see this file's own header doc comment
# for why `@onready` is deliberately avoided here.
var _portrait_base: TextureRect = null
var _page_overlay: TextureRect = null
var _mon_sprite: TextureRect = null
var _page_name_label: Label = null
var _nickname_label: Label = null
var _species_label: Label = null
var _level_label: Label = null
var _dex_label: Label = null
var _gender_label: Label = null
var _item_label: Label = null
var _ot_name_label: Label = null
var _ot_id_label: Label = null

# [INFO page real content] The 5 real gray-pill labels ("No."/"Name"/"OT"/
# "ID No."/"Item") on the INFO page's own right pane -- this pack's own
# background art (summary_frlg_frame_base.png) has 6 evenly-spaced gray
# pills here identical in shape to the SKILLS page's stat-name pills, but
# ships them blank (same "labels are baked separately, this pack ships
# none" situation SKILLS' own stat names were in before that page's own
# fix). Only 5 of the 6 have real content to show (Dex#/Species/OT Name/
# OT ID#/Item, per pokemon_summary_screen.c's real PrintInfoPage) -- the
# 6th pill has no real source-confirmed content and is deliberately left
# blank rather than guessed at.
var _info_pill_labels: Array[OutlineLabel] = []

var _prev_page_btn: Button = null
var _next_page_btn: Button = null
var _prev_mon_btn: Button = null
var _next_mon_btn: Button = null
var _close_btn: Button = null

# [E4-3, SKILLS] Nature-colorable stat value labels, indexed to match
# BattlePokemon.STAT_* (HP/ATK/DEF/SPATK/SPDEF/SPEED) for a direct lookup in
# _refresh() rather than 6 separate named branches. NatureLabel/
# AbilityNameLabel/AbilityDescLabel were removed in the M26E4 rework --
# see _refresh_skills_page()'s own doc comment for the real source
# citation (neither is real SKILLS-page content).
var _ribbons_label: Label = null
var _stat_value_labels: Array[Label] = []

# [M26E4 rework -- real source citation, pokemon_summary_screen.c's
# `PSS_LABEL_WINDOW_POKEMON_SKILLS_STATS_LEFT/RIGHT`] The stat NAMES
# ("HP"/"ATTACK"/"DEFENSE"/"SP. ATK"/"SP. DEF"/"SPEED") are printed via
# `PrintTextOnWindow` onto a real BG0 text window in source -- confirmed by
# directly dumping page_skills.bin's own tile indices for that region: it's
# just repeating box-fill/border tiles (35/36/51/52/108/109), zero glyph
# variety, unlike the ITEM/RIBBON header row's genuinely varied tile
# indices. So this text can never come from the decoded overlay PNG --
# it's static (never varies per-mon), so unlike the value labels these
# never need a `.text` write in _refresh_skills_page(), only a visibility
# toggle. Indexed to match BattlePokemon.STAT_* the same as
# _stat_value_labels, for a shared toggle loop.
var _stat_name_labels: Array[OutlineLabel] = []

# [E4-3, MOVES] One entry per move row (index-aligned with the mon's own
# `.moves`/`.current_pp` arrays), each a {button, type_icon, name_label,
# pp_label} dictionary -- built once in _bind_nodes(), read directly rather
# than via 4 sets of named fields.
var _move_rows: Array[Dictionary] = []

var _move_detail_power_label: Label = null
var _move_detail_accuracy_label: Label = null
var _move_detail_category_icon: TextureRect = null
var _move_detail_desc_label: Label = null
# [Fire-Red-source correction] Real "POWER"/"ACCURACY" label pills, baked
# into summary_frlg_page_movedetail.png's own gray pills (same blank-pill
# pattern as SKILLS' stat names) -- only shown alongside the move-detail
# view.
var _move_detail_pill_labels: Array[OutlineLabel] = []


func setup(parent_bs, party: BattleParty, start_index: int) -> void:
	# [M26A1 / 3:2 Phase 3] Letterboxed at an honest integer 2x rather than
	# stretched to 3:2 — see `UiLetterbox`. Applied here rather than in the
	# `.tscn` so all three screens share ONE mechanism, including
	# `switch_select_screen`, which has no tree to author it into.
	UiLetterbox.apply(self)
	var _backdrop := get_node_or_null("Backdrop") as Control
	if _backdrop != null:
		UiLetterbox.expand_to_viewport(_backdrop)
	_parent_bs = parent_bs
	_party = party
	_mon_index = clampi(start_index, 0, max(0, party.members.size() - 1))
	_bind_nodes()
	_wire_behavior()
	_refresh()


func _bind_nodes() -> void:
	_portrait_base = $GbaLayer/PortraitBase
	_page_overlay = $GbaLayer/PageOverlay
	_mon_sprite = $GbaLayer/MonSprite
	_page_name_label = $GbaLayer/PageNameLabel
	_nickname_label = $GbaLayer/NicknameLabel
	_species_label = $GbaLayer/SpeciesLabel
	_level_label = $GbaLayer/LevelLabel
	_dex_label = $GbaLayer/DexLabel
	_gender_label = $GbaLayer/GenderLabel
	_item_label = $GbaLayer/ItemLabel
	_ot_name_label = $GbaLayer/OtNameLabel
	_ot_id_label = $GbaLayer/OtIdLabel
	_info_pill_labels = [$GbaLayer/DexNumberPillLabel, $GbaLayer/NamePillLabel,
			$GbaLayer/OtPillLabel, $GbaLayer/IdNoPillLabel, $GbaLayer/ItemPillLabel]

	_prev_page_btn = $PrevPageButton
	_next_page_btn = $NextPageButton
	_prev_mon_btn = $PrevMonButton
	_next_mon_btn = $NextMonButton
	_close_btn = $CloseButton

	_ribbons_label = $GbaLayer/RibbonsLabel
	# [BattlePokemon.STAT_* order: HP, ATK, DEF, SPATK, SPDEF, SPEED]
	_stat_value_labels = [$GbaLayer/HpValueLabel, $GbaLayer/AtkValueLabel, $GbaLayer/DefValueLabel,
			$GbaLayer/SpAtkValueLabel, $GbaLayer/SpDefValueLabel, $GbaLayer/SpeedValueLabel]
	_stat_name_labels = [$GbaLayer/HpNameLabel, $GbaLayer/AtkNameLabel, $GbaLayer/DefNameLabel,
			$GbaLayer/SpAtkNameLabel, $GbaLayer/SpDefNameLabel, $GbaLayer/SpeedNameLabel]

	_move_rows = []
	for i in range(1, 5):
		_move_rows.append({
			"button": get_node("GbaLayer/MoveRow%dButton" % i),
			"type_icon": get_node("GbaLayer/MoveRow%dTypeIcon" % i),
			"name_label": get_node("GbaLayer/MoveRow%dNameLabel" % i),
			"pp_label": get_node("GbaLayer/MoveRow%dPpLabel" % i),
		})

	_move_detail_power_label = $GbaLayer/MoveDetailPowerLabel
	_move_detail_accuracy_label = $GbaLayer/MoveDetailAccuracyLabel
	_move_detail_category_icon = $GbaLayer/MoveDetailCategoryIcon
	_move_detail_desc_label = $GbaLayer/MoveDetailDescLabel
	_move_detail_pill_labels = [$GbaLayer/MoveDetailPowerPillLabel, $GbaLayer/MoveDetailAccuracyPillLabel]


# Runtime-only behavior that still genuinely needs `_parent_bs` (button
# chrome-stripping/hover-color states, the shared "▶" cursor group) --
# unlike position/font/default-text, none of this is something Rob would
# want to hand-tune in the editor, so it stays here rather than in the
# .tscn.
func _wire_behavior() -> void:
	_prev_page_btn.pressed.connect(_on_prev_page_pressed)
	_next_page_btn.pressed.connect(_on_next_page_pressed)
	_prev_mon_btn.pressed.connect(_on_prev_mon_pressed)
	_next_mon_btn.pressed.connect(_on_next_mon_pressed)
	_close_btn.pressed.connect(_on_close_pressed)

	for i in range(_move_rows.size()):
		var btn: Button = _move_rows[i]["button"]
		btn.pressed.connect(_on_move_row_pressed.bind(i))

	if _parent_bs == null:
		return
	var nav_buttons: Array[Button] = [_prev_page_btn, _next_page_btn,
			_prev_mon_btn, _next_mon_btn, _close_btn]
	for btn in nav_buttons:
		_parent_bs._style_menu_button(btn)
		_parent_bs._strip_button_chrome(btn)
	_parent_bs._wire_cursor_group(nav_buttons)

	# [E4-3] Move rows are plain click targets (their own real text/icon
	# comes from sibling Label/TextureRect nodes on top, matching
	# SwitchSelectScreen's own established "Button underneath, visual
	# overlay children on top" shape) -- chrome-stripped so Godot's default
	# flat-grey Button panel doesn't paint over the row's real content, but
	# deliberately NOT run through _wire_cursor_group: that "▶" shared-
	# selection convention is for a list of MUTUALLY EXCLUSIVE actions
	# (Fight/Item/Switch/Run-style), not this row's own toggle-a-detail-
	# panel behavior.
	for row in _move_rows:
		_parent_bs._strip_button_chrome(row["button"])


func _refresh() -> void:
	if _party == null or _party.members.is_empty():
		return
	var mon: BattlePokemon = _party.members[_mon_index]

	# [M26E4 rework] `_portrait_base` never changes -- it's set once in the
	# .tscn to the real, always-visible portrait/frame layer (see
	# gen_summary_screen_sprites_frlg.py's own doc comment, as of the M26
	# Fire-Red art swap). Only the page-specific overlay drawn on top of it
	# swaps here.
	#
	# [Fire-Red-source correction -- supersedes every earlier version of
	# this comment] Two prior sessions both concluded the move-detail view
	# never swaps backgrounds, first against Emerald's own
	# page_battle_moves.bin, then (wrongly) claimed re-confirmed against
	# Fire Red too. Direct read of Fire Red's own
	# `PokeSum_CopyNewBgTilemapBeforePageFlip` proves otherwise:
	# `PSS_PAGE_MOVES_INFO` loads `sBgTilemap_MovesInfoPage` (aliased
	# `gSummaryScreen_PageMovesInfo_Tilemap` elsewhere in the same file),
	# a real, distinct tilemap from the plain list's own
	# `sBgTilemap_MovesPage`. The asset for this was already pulled and
	# sitting unused on disk (`summary_frlg_page_movedetail.png`, from the
	# pack's own `bg_movedetail.png`) -- confirmed via direct pixel
	# measurement to be a genuinely different layout: real POWER/ACCURACY
	# label pills with their own value boxes, and a properly-bounded ruled
	# description area distinct from the label rows above it (unlike the
	# plain MOVES overlay, which has none of this).
	var showing_move_detail: bool = _page == _PAGE_MOVES and _selected_move_index >= 0
	var overlay_file: String = "summary_frlg_page_movedetail.png" if showing_move_detail \
			else _PAGE_OVERLAY[_page]
	_page_overlay.texture = load(_SUMMARY_DIR + overlay_file) if not overlay_file.is_empty() else null
	_page_name_label.text = _PAGE_NAMES[_page]

	var dex: int = mon.species.national_dex_num if mon.species != null else 0
	_mon_sprite.texture = SpriteRegistry.get_front(dex)
	# [Flagged, NOT fixed -- real source finding, out of this pass's own
	# scope] `PokeSum_HideSpritesBeforePageFlip`/`ShowSpritesBeforePageFlip`
	# confirm source shows the BIG portrait sprite (`monPicSpriteId`)
	# during MOVES_INFO (move-selected) -- same as every other page, not
	# hidden -- so `_mon_sprite` is deliberately left showing here,
	# unconditionally, matching that. The real, more involved finding
	# underneath: on the PLAIN MOVES LIST (not detail), source hides that
	# same big sprite and shows a separate SMALL ICON sprite instead
	# (`monIconSpriteId`) -- this project shows the big portrait
	# unconditionally on every page including plain MOVES, which is a real
	# mismatch there too, but building a second per-species icon-sprite
	# path is a bigger, separate item than this pass's scope.

	var name_text: String = _parent_bs._name_text(mon) if _parent_bs != null \
			else (mon.species.species_name if mon.species != null else "?")
	_nickname_label.text = name_text
	_level_label.text = _parent_bs._level_text(mon) if _parent_bs != null else "Lv%d" % mon.level
	_gender_label.text = _parent_bs._gender_glyph(mon.gender) if _parent_bs != null else ""

	# [INFO page real content -- corrects an earlier Emerald-sourced
	# assumption] Species name/Dex#/OT Name/OT ID#/Held Item are real
	# `pokemon_summary_screen.c` `PrintInfoPage()` right-pane content,
	# confirmed directly against Fire Red's own source -- NOT
	# 001_Summary.rb's Emerald-shaped recipe this screen's SKILLS-page doc
	# comments elsewhere are sourced from. Emerald's own PrintHeldItemName
	# puts Item on the SKILLS page instead -- a real, confirmed difference
	# between the two engines (Emerald's summary screen also shows
	# Ability name+description on INFO via `PSS_DATA_WINDOW_INFO_ABILITY`,
	# which has NO equivalent anywhere in Fire Red's own file at all), not
	# an inconsistency to "fix" back toward Emerald now that this screen's
	# art is Fire-Red-sourced. INFO-page only, unlike Nickname/Level/
	# Gender/PageName above, which really are drawn on every page.
	var showing_info: bool = _page == _PAGE_INFO
	_species_label.text = mon.species.species_name if mon.species != null else "?"
	_species_label.visible = showing_info
	_dex_label.text = "%03d" % dex
	_dex_label.visible = showing_info

	# [Disclosed simplification] Source's real OT Name/OT ID# belong to
	# whoever caught/received THIS specific Pokemon -- this project tracks
	# no such per-mon ownership data at all (no trade system's own "OT"
	# concept, no wild-caught-vs-gift distinction on BattlePokemon). Always
	# shows the CURRENT player's own identity instead, via the same
	# TextBuffers.active_identity() seam the {PLAYER} substitution already
	# uses everywhere else -- correct for the overwhelmingly common case
	# (viewing your own party) and a stated stand-in, not a claim of full
	# accuracy, for anything else (e.g. a post-trade Pokemon whose real OT
	# would differ).
	var identity: PlayerIdentity = TextBuffers.active_identity()
	_ot_name_label.text = identity.display_name() if identity != null else TextBuffers.PLAYER_NAME
	_ot_name_label.visible = showing_info
	_ot_id_label.text = "%05d" % (identity.ensure_trainer_id() if identity != null else 0)
	_ot_id_label.visible = showing_info

	_item_label.text = mon.held_item.item_name if mon.held_item != null else "None"
	_item_label.visible = showing_info

	for lbl in _info_pill_labels:
		lbl.visible = showing_info

	_prev_page_btn.disabled = _page <= 0
	_next_page_btn.disabled = _page >= NUM_PAGES - 1
	var cyclable: bool = _party.members.size() > 1
	_prev_mon_btn.disabled = not cyclable
	_next_mon_btn.disabled = not cyclable

	_refresh_skills_page(mon)
	_refresh_moves_page(mon)


# [M26E4 rework -- real source citation, pokemon_summary_screen.c's own
# `sSummaryTemplate`/`sPageSkillsTemplate` window arrays, NOT
# 001_Summary.rb's recipe] The real SKILLS page has no "Nature: X" text
# box anywhere. Real SKILLS content is: ribbon count ("None" always --
# this project has no ribbon system of any kind, so the count branch is
# unreachable by construction, not a simplification), and the stat table
# with nature up/down coloring (HP NEVER colored -- source's own
# `nature_for_stats.stat_changes` loop never touches :HP).
#
# [Fire-Red-source correction, superseding this comment's own earlier
# text] Held Item and Ability were both previously described here as real
# SKILLS/INFO-page content respectively, per Emerald's own
# `sPageSkillsTemplate`/`PSS_DATA_WINDOW_INFO_ABILITY` -- true for
# Emerald, but this screen's art is Fire-Red-sourced, and Fire Red's own
# `pokemon_summary_screen.c` puts Item on INFO instead (see `_refresh()`'s
# own INFO-page block) and has no Ability display anywhere on the screen
# at all. Nature's own name is real Fire Red INFO-page content too, inside
# a Trainer Memo flavor sentence (`PokeSum_PrintTrainerMemo`) that also
# needs Met Level/Met Location -- neither tracked anywhere in this
# project yet, so that sentence stays deferred, not built here.
func _refresh_skills_page(mon: BattlePokemon) -> void:
	var showing: bool = _page == _PAGE_SKILLS
	_ribbons_label.visible = showing
	for lbl in _stat_value_labels:
		lbl.visible = showing
	for lbl in _stat_name_labels:
		lbl.visible = showing
	if not showing:
		return

	_ribbons_label.text = "None"

	# [text alignment/size follow-up] `_stat_name_labels` was already
	# built and page-gated, but nothing ever set `.text` on it -- the 6
	# gray pills rendered genuinely blank, matching what the user
	# reported ("no HP attack defense etc"). Real source strings + row
	# order confirmed directly from 001_Summary.rb's own `drawPageTwo`
	# (`textpos` -- "HP"/"Attack"/"Defense"/"Sp. Atk"/"Sp. Def"/"Speed",
	# same [HP,ATK,DEF,SPATK,SPDEF,SPEED] order `_stat_name_labels`
	# itself is already built in).
	const _STAT_NAMES := ["HP", "ATTACK", "DEFENSE", "SP. ATK", "SP. DEF", "SPEED"]
	for i in range(_stat_name_labels.size()):
		_stat_name_labels[i].text = _STAT_NAMES[i]

	var pair: Array[int] = BattlePokemon._nature_stat_pair(mon.nature)
	var raised_stat: int = pair[0]
	var lowered_stat: int = pair[1]
	var stat_values := [
		"%d/%d" % [mon.current_hp, mon.max_hp],
		str(mon.attack), str(mon.defense),
		str(mon.sp_attack), str(mon.sp_defense), str(mon.speed),
	]
	for i in range(_stat_value_labels.size()):
		var lbl: Label = _stat_value_labels[i]
		lbl.text = stat_values[i]
		# [HP never colored, per source] STAT_HP (0) is deliberately
		# excluded from the raised/lowered check even though a nature could
		# theoretically match index 0 -- it never can, since
		# _nature_stat_pair() only ever returns STAT_ATK..STAT_SPEED, but
		# the exclusion is stated explicitly here so it can't be "corrected"
		# away by someone reading only this loop.
		if i != BattlePokemon.STAT_HP and i == raised_stat:
			lbl.add_theme_color_override("font_color", _COLOR_RAISED_FG)
			lbl.add_theme_color_override("font_shadow_color", _COLOR_RAISED_SHADOW)
		elif i != BattlePokemon.STAT_HP and i == lowered_stat:
			lbl.add_theme_color_override("font_color", _COLOR_LOWERED_FG)
			lbl.add_theme_color_override("font_shadow_color", _COLOR_LOWERED_SHADOW)
		else:
			lbl.add_theme_color_override("font_color", _COLOR_NEUTRAL_FG)
			lbl.add_theme_color_override("font_shadow_color", _COLOR_NEUTRAL_SHADOW)


# [E4-3, MOVES -- real source citation, 001_Summary.rb drawPageThree] 4 rows,
# each a type badge + name + PP, PP colored via the real 4-tier ramp. An
# empty move slot shows "-"/"--" in tier-0 gray with no type icon and a
# disabled (unclickable) row, matching source's own else-branch exactly.
func _refresh_moves_page(mon: BattlePokemon) -> void:
	var showing: bool = _page == _PAGE_MOVES
	for row in _move_rows:
		(row["button"] as Button).visible = showing
		(row["type_icon"] as TextureRect).visible = showing
		(row["name_label"] as Label).visible = showing
		(row["pp_label"] as Label).visible = showing
	if not showing:
		_selected_move_index = -1
		_set_move_detail_visible(false)
		return

	for i in range(_move_rows.size()):
		var row: Dictionary = _move_rows[i]
		var btn: Button = row["button"]
		var type_icon: TextureRect = row["type_icon"]
		var name_label: Label = row["name_label"]
		var pp_label: Label = row["pp_label"]

		if i < mon.moves.size():
			var move: MoveData = mon.moves[i]
			var current_pp: int = mon.current_pp[i] if i < mon.current_pp.size() else 0
			btn.disabled = false
			type_icon.visible = true
			type_icon.texture = _parent_bs._type_badge_texture(move.type) if _parent_bs != null else null
			name_label.text = move.move_name
			# [Phase 3 cursor convention -- see _COLOR_SELECTED_NAME_FG's own
			# doc comment] The open row's name highlights; every other row
			# stays the normal name color.
			if i == _selected_move_index:
				name_label.add_theme_color_override("font_color", _COLOR_SELECTED_NAME_FG)
				name_label.add_theme_color_override("font_shadow_color", _COLOR_SELECTED_NAME_SHADOW)
			else:
				name_label.add_theme_color_override("font_color", _COLOR_NAME_FG)
				name_label.add_theme_color_override("font_shadow_color", _COLOR_NAME_SHADOW)
			var tier: int = _pp_tier(current_pp, move.pp)
			pp_label.text = "%d/%d" % [current_pp, move.pp]
			pp_label.add_theme_color_override("font_color", _PP_TIER_FG[tier])
			pp_label.add_theme_color_override("font_shadow_color", _PP_TIER_SHADOW[tier])
		else:
			btn.disabled = true
			type_icon.visible = false
			name_label.text = "-"
			name_label.add_theme_color_override("font_color", _COLOR_NAME_FG)
			name_label.add_theme_color_override("font_shadow_color", _COLOR_NAME_SHADOW)
			pp_label.text = "--"
			pp_label.add_theme_color_override("font_color", _PP_TIER_FG[0])
			pp_label.add_theme_color_override("font_shadow_color", _PP_TIER_SHADOW[0])

	if _selected_move_index >= 0 and _selected_move_index < mon.moves.size():
		_refresh_move_detail(mon, _selected_move_index)
		_set_move_detail_visible(true)
	else:
		_selected_move_index = -1
		_set_move_detail_visible(false)


# [Fire-Red-source correction, supersedes this comment's own earlier
# 001_Summary.rb/Emerald-sourced version] Real source is
# `BufferMonMoveI` (pokemon_summary_screen.c): power shows "---" for
# `power <= 1` -- BOTH a true status move (power 0) AND a move whose real
# power is computed dynamically (power 1, this project's own established
# sentinel for Magnitude/Low Kick/etc.) get the SAME "---", no distinct
# "???" branch. Grepped directly for the "display_damage=="Variable
# power move"" citation this comment used to carry -- it appears nowhere
# in Fire Red's own reference tree at all, likely an Emerald-plugin-only
# concept that never carried over. Accuracy shows "---" for a move that
# never rolls one (accuracy==0). Neither string carries a "Pow "/"Acc "
# prefix or a "%" sign in source -- those come from the real POWER/
# ACCURACY label pills now baked into summary_frlg_page_movedetail.png's
# own gray pills instead (matching the HP/ATTACK/etc. pattern already
# established on SKILLS), and accuracy is a bare number in source, no
# percent sign anywhere in `moveAccuracyStrBufs`.
func _refresh_move_detail(mon: BattlePokemon, index: int) -> void:
	var move: MoveData = mon.moves[index]

	_move_detail_power_label.text = "---" if move.power <= 1 else str(move.power)
	_move_detail_accuracy_label.text = "---" if move.accuracy == 0 else str(move.accuracy)

	_move_detail_category_icon.texture = _parent_bs._category_icon_texture(move.category) \
			if _parent_bs != null else null
	_move_detail_desc_label.text = move.description


func _set_move_detail_visible(value: bool) -> void:
	_move_detail_power_label.visible = value
	_move_detail_accuracy_label.visible = value
	_move_detail_category_icon.visible = value
	_move_detail_desc_label.visible = value
	for lbl in _move_detail_pill_labels:
		lbl.visible = value


# [Fire-Red-source correction, supersedes this comment's own earlier
# 001_Summary.rb/Emerald-sourced version, which also claimed "transliterated
# exactly, not approximated" while actually being a plain proportional
# approximation] Real source is `GetMoveTextColor`
# (pokemon_summary_screen.c) -- and it is NOT purely proportional: maxPP==3
# and maxPP==2 are each explicitly special-cased rather than falling out of
# the general curPP<=maxPP/4 / curPP<=maxPP/2 formula. The general formula
# alone gets maxPP=3,curPP=2 wrong (computes tier 0/"full"; source says
# tier 2/"getting low"), which is exactly the case these two branches exist
# to cover -- confirmed by hand-checking every (maxPP, curPP) pair the two
# special cases touch against the general formula's own answer.
static func _pp_tier(current_pp: int, total_pp: int) -> int:
	if total_pp <= 0 or current_pp == total_pp:
		return 0
	if current_pp == 0:
		return 3
	if total_pp == 3:
		if current_pp == 2:
			return 2
		elif current_pp == 1:
			return 1
		return 0
	if total_pp == 2:
		if current_pp == 1:
			return 1
		return 0
	if current_pp * 4 <= total_pp:
		return 2
	elif current_pp * 2 <= total_pp:
		return 1
	return 0


func _on_prev_page_pressed() -> void:
	if _page > 0:
		_page -= 1
		_selected_move_index = -1
		_refresh()


func _on_next_page_pressed() -> void:
	if _page < NUM_PAGES - 1:
		_page += 1
		_selected_move_index = -1
		_refresh()


# [Real source, §3] Mon-cycling wraps (unlike page navigation, which
# clamps) -- pbChangePokemon's own looping index arithmetic at either end
# of the party.
func _on_prev_mon_pressed() -> void:
	if _party.members.size() <= 1:
		return
	_mon_index = (_mon_index - 1 + _party.members.size()) % _party.members.size()
	_selected_move_index = -1
	_refresh()


func _on_next_mon_pressed() -> void:
	if _party.members.size() <= 1:
		return
	_mon_index = (_mon_index + 1) % _party.members.size()
	_selected_move_index = -1
	_refresh()


# [E4-3] A real toggle -- source's own USE-opens/B-closes move-selection
# sub-mode, reproduced here as click-to-open/click-again-to-close on the
# same row (this project's established "everything is a real clickable
# button, no separate D-pad mode" convention, per every other overlay
# screen).
func _on_move_row_pressed(index: int) -> void:
	_selected_move_index = -1 if _selected_move_index == index else index
	_refresh()


func _on_close_pressed() -> void:
	closed.emit(_mon_index)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo
			and (event as InputEventKey).keycode == KEY_ESCAPE):
		return
	get_viewport().set_input_as_handled()
	_on_close_pressed()
