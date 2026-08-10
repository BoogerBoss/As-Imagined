class_name AudioMap
extends RefCounted

## [M27R 7a-1] Source audio constant -> real asset on disk, in one place.
##
## The counterpart to `GameAudio`: that file is the PLAYER, this one is the
## CONTENT. Kept apart for the same reason `FieldSpecials` is kept out of
## `ScriptVM` — the mechanism should not know the catalogue, and a new sound is
## then a one-line edit here rather than a change to playback code.
##
## ⚠️ **THREE ASSET CLASSES, AND ONLY TWO OF THEM EXIST TODAY.** SE and ME are
## the vendored Essentials pack, already imported and playable. BGM is a STUB
## (Rob's call, 2026-08-08): the names resolve to a folder Rob will supply, so
## `playbgm` is wired end to end and simply finds nothing until it lands. That
## is deliberate — see `BGM_DIR`.
##
## ⚠️ **THE ESSENTIALS SE/ME ARE NOT MIDI RENDERS, AND THAT MATTERS.** Measured
## 2026-08-08: every cry is 8-bit mono at 10512 Hz (GBA DirectSound sample
## format — raw ROM sample data, and cries were never sequenced to begin with),
## and every SE/ME ogg carries a 65456 Hz rate, which is a GBA-domain capture
## rate rather than the 44100/48000 a soundfont render produces. So these sound
## like the real game. The timbre caveat recorded against the 32 unrendered
## `.mid` BGM files does NOT carry over to anything in this table.


## The vendored Essentials pack. Both directories are tracked and every file in
## them already carries a Godot `.import` sidecar, so these load as-is.
const SE_DIR := "res://assets/Essentials_v19.1/Audio/SE/"
const ME_DIR := "res://assets/Essentials_v19.1/Audio/ME/"

## ⚠️ **DOES NOT EXIST YET, BY DESIGN — this is the stub seam.** Rob supplies a
## BGM folder later; until then `GameAudio` resolves a track, finds no file,
## records the cue and plays silence. Nothing here needs changing when the
## folder arrives, provided the stems below match the filenames in it.
##
## Deliberately NOT pointed at `assets/Essentials_v19.1/Audio/BGM/`: 32 of
## those 35 files are `.mid`, which Godot cannot play and which carry no
## `.import` sidecar — inert bytes, not a fallback.
const BGM_DIR := "res://assets/audio/bgm/"

## [M27R 7c] Per-species cries, keyed by national dex number — the same
## `cry_%04d` convention the sprite pull already uses, so nothing has to carry a
## name→file mapping at runtime. Pulled from the REFERENCE tree (authentic
## 8-bit mono 10512 Hz GBA rips), not the vendored Essentials pack.
const CRY_DIR := "res://assets/audio/cries/"


## `playse` — source constant -> Essentials filename.
##
## ⚠️ **EVERY MAPPING BELOW IS TAKEN FROM SOURCE'S OWN COMMENT OR CALL SITE, NOT
## FROM THE NAME.** `songs.h` annotates several of these itself, which is the
## only reason the less obvious ones are not guesses:
##
##   * `SE_PIN`     — songs.h:27 says *"General 'good', commonly for '!'"*, so
##                    it is the exclamation-mark pop, not a generic confirm.
##   * `SE_BOO`     — songs.h:28 says *"General 'bad'"*.
##   * `SE_CLICK`   — songs.h:42 `SE_TK_KASYA`, a click.
##   * `SE_EXIT`    — songs.h:15 `SE_KAIDAN` ("stairs"), and its real call sites
##                    are `field_screen_effect.c:536,654` — the warp EXIT, which
##                    is why this is the door sound and not a menu-close.
##   * `SE_SHOP`    — `item_menu.c:2286`, played on a purchase.
##   * `SE_PC_ON`   — the PC powering up.
##   * `SE_WALL_HIT` — `field_player_avatar.c:1425,1459`, the bump.
##   * `SE_LEDGE`    — songs.h:16 `SE_DANSA`; `field_player_avatar.c:1347,1890`,
##                     the ledge hop.
##   * `SE_SAVE`     — played on a successful save (`hall_of_fame_frlg.c:471`
##                     and others). Essentials files it under ME, but it is one
##                     short cue for one moment, so it lives here with the rest
##                     of the one-shots rather than in the fanfare channel that
##                     ducks music.
##
## ⚠️ **[M27R 7a-2] ONE DELIBERATE DIVERGENCE: SOURCE USES `SE_SELECT` FOR BOTH
## CURSOR MOVEMENT AND CONFIRM, AND THIS SPLITS THEM.** A Gen 3 menu plays the
## same blip for moving and for choosing. Essentials ships two distinct sounds,
## and one heavier sound repeated on every cursor step is noticeably harsher
## than the split — so movement takes `SE_SELECT` (the light blip) and confirm
## takes `SE_CLICK` (the decision sound). Both are real source constants already
## reached by the corridor, so nothing is invented; only which one fires where.
## Reverting is a two-line change here, with no call site touched.
const SE := {
	"SE_PIN": "Exclaim.wav",
	"SE_BOO": "GUI sel buzzer.ogg",
	"SE_CLICK": "GUI sel decision.ogg",
	"SE_EXIT": "Door exit.ogg",
	"SE_PC_ON": "PC open.ogg",
	"SE_SHOP": "Mart buy item.ogg",
	# [M27R 7a-2] Code-driven cues — no script names these, so they fire from
	# real call sites rather than from an opcode argument.
	"SE_SELECT": "GUI sel cursor.ogg",
	"SE_WALL_HIT": "Player bump.ogg",
	"SE_LEDGE": "Player jump.ogg",
	"SE_DOOR": "Door enter.ogg",
	# ⚠️ The SE, not the ME. Essentials ships BOTH a `SE/GUI save choice.ogg`
	# and a longer `ME/GUI save game.ogg` jingle; source's `SE_SAVE` is an SE
	# played as a one-shot, so this matches it rather than ducking the music for
	# a save. The ME jingle stays available if Rob prefers the bigger beat —
	# that is a one-line change here plus `play_se` -> `play_fanfare` at the
	# single call site in `FieldNativeEvents`.
	"SE_SAVE": "GUI save choice.ogg",

	# [M27R 7a-3] Battle effects. Shared with the simulator, which is why they
	# live in the one catalogue rather than beside the battle screen.
	#
	# ⚠️ Damage has THREE variants and picking between them is the whole tier:
	# a super-effective hit that sounds like a resisted one is the single most
	# noticeable audio error in a battle.
	"SE_DAMAGE_NORMAL": "Battle damage normal.ogg",
	"SE_DAMAGE_SUPER": "Battle damage super.ogg",
	"SE_DAMAGE_WEAK": "Battle damage weak.ogg",
	"SE_BALL_THROW": "Battle throw.ogg",
	"SE_BALL_HIT": "Battle ball hit.ogg",
	"SE_BALL_SHAKE": "Battle ball shake.ogg",
	"SE_BALL_CLICK": "Battle catch click.ogg",
	"SE_BALL_DROP": "Battle ball drop.ogg",
	"SE_RECALL": "Battle recall.ogg",
	"SE_SEND_OUT": "Battle jump to ball.ogg",
	"SE_FLEE": "Battle flee.ogg",
}


## `playfanfare` — source constant -> Essentials ME jingle.
##
## ⚠️ **TWO CORRIDOR FANFARES HAVE NO ESSENTIALS COUNTERPART AND ARE DELIBERATELY
## ABSENT**: `MUS_LEVEL_UP` (4 corridor uses) and `MUS_RG_DEX_RATING` (1). The
## pack ships no level-up or dex-rating jingle, and borrowing a neighbouring one
## would put the wrong sound on a beat rather than no sound. They resolve to ""
## and play silence — `waitfanfare` still releases immediately, so a script
## never stalls on one. Listed here as a comment rather than omitted silently so
## the gap is a recorded decision; closing it needs an asset, not code.
##
## `MUS_OBTAIN_TMHM` is a DISCLOSED APPROXIMATION: FRLG has its own TM jingle,
## Essentials does not, so it borrows the ordinary item jingle. That is a
## near-miss rather than a wrong note, which is the line the two above fail.
const ME := {
	"MUS_RG_OBTAIN_KEY_ITEM": "Key item get.ogg",
	"MUS_HEAL": "Pkmn healing.ogg",
	"MUS_EVOLVED": "Evolution success.ogg",
	"MUS_OBTAIN_TMHM": "Item get.ogg",
	# Wired ahead of their call sites — [M27R 7a-2] adds the code-side hooks.
	"MUS_OBTAIN_ITEM": "Item get.ogg",
	"MUS_OBTAIN_BADGE": "Badge get.ogg",
	"MUS_VICTORY_TRAINER": "Battle victory trainer.ogg",
	"MUS_VICTORY_GYM_LEADER": "Battle victory leader.ogg",
	"MUS_VICTORY_WILD": "Battle victory wild.ogg",
	"MUS_RG_CAUGHT_INTRO": "Battle capture success.ogg",
	"MUS_OBTAIN_B_POINTS": "Pkmn get.ogg",
}


## `playbgm` — source constant -> a FILE STEM in `BGM_DIR`.
##
## ⚠️ **STEMS, NOT FILENAMES, because the extension is Rob's to choose.**
## `GameAudio` tries each of `BGM_EXTS` in order, so an `.ogg` or a `.wav`
## folder both work with no edit here.
##
## The six below are every `playbgm` argument the 32-map corridor actually
## reaches (measured against `data/map_scripts.json`, walking 762 reachable
## labels). Everything else in the region resolves to "" and plays silence.
const BGM := {
	"MUS_POKE_CENTER": "poke_center",
	"MUS_FOLLOW_ME": "follow_me",
	"MUS_RG_ENCOUNTER_RIVAL": "encounter_rival",
	"MUS_RG_RIVAL_EXIT": "rival_exit",
	"MUS_RG_OAK": "oak",
	"MUS_RG_JIGGLYPUFF": "jigglypuff",
}

## Tried in order against a stem. `.ogg` first because it is what the rest of
## this project's audio already is.
const BGM_EXTS := [".ogg", ".wav", ".mp3"]


## Resolve a `playse` constant. "" when unmapped — never an error, because an
## unmapped sound must degrade to silence rather than halt a script.
static func se_path(name: String) -> String:
	var f: String = SE.get(name, "")
	return "" if f.is_empty() else SE_DIR + f


## Resolve a `playfanfare` constant. "" when unmapped (see ME's own note).
static func me_path(name: String) -> String:
	var f: String = ME.get(name, "")
	return "" if f.is_empty() else ME_DIR + f


## Resolve a `playbgm` constant to a real file, or "" if the track is unmapped
## OR the asset folder has not been supplied yet.
##
## ⚠️ Those two cases are deliberately NOT distinguished in the return value —
## both mean "play silence" — but they ARE distinguished by `bgm_intent`, which
## is what a test asserts against so the stub can be proven wired before a
## single asset exists.
static func bgm_path(name: String) -> String:
	var stem: String = BGM.get(name, "")
	if stem.is_empty():
		return ""
	for ext in BGM_EXTS:
		var p: String = BGM_DIR + stem + ext
		if ResourceLoader.exists(p):
			return p
	return ""


## Where a track WOULD live. Non-empty for every mapped name whether or not the
## file exists — the stub's own observable contract.
static func bgm_intent(name: String) -> String:
	var stem: String = BGM.get(name, "")
	return "" if stem.is_empty() else BGM_DIR + stem + BGM_EXTS[0]


## Path to a species' cry, or "" when there is none.
##
## ⚠️ Keyed on DEX, never on name. The name route is where the gendered Nidoran
## collide — the same collision `[M27B Step 4]` paid for once — and the
## generator has already resolved it, so nothing downstream needs to know.
static func cry_path(dex: int) -> String:
	if dex <= 0:
		return ""
	return CRY_DIR + "cry_%04d.wav" % dex


## [M27R 7a-3] Which damage sound a hit makes.
##
## ⚠️ **THE THRESHOLDS ARE THE TIER.** A super-effective hit that sounds
## resisted is the most audible mistake a battle can make, and effectiveness
## arrives as a float multiplier rather than a category — 0.25, 0.5, 1, 2, 4 —
## so the split has to be made somewhere. Above 1 is super, below is weak,
## exactly 1 is normal. An immune hit (0) makes no damage sound at all, because
## no damage happened.
static func damage_se(effectiveness: float) -> String:
	if effectiveness <= 0.0:
		return ""
	if effectiveness > 1.0:
		return "SE_DAMAGE_SUPER"
	if effectiveness < 1.0:
		return "SE_DAMAGE_WEAK"
	return "SE_DAMAGE_NORMAL"


## The sounds a capture attempt makes, in order.
##
## ⚠️ **THE SHAKE COUNT DRIVES IT, and `[M27H H4]` already emits one** — that
## tier recorded the count specifically so a future animation would have
## nothing to retrofit. 0-2 shakes is a break-free and ends on the ball
## bursting open; 3 is a capture and ends on the click.
static func catch_sequence(shakes: int, caught: bool) -> Array[String]:
	var out: Array[String] = ["SE_BALL_THROW", "SE_BALL_HIT"]
	for i in range(maxi(0, shakes)):
		out.append("SE_BALL_SHAKE")
	out.append("SE_BALL_CLICK" if caught else "SE_BALL_DROP")
	return out
