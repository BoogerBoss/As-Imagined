class_name OakSpeechOverlay
extends CanvasLayer

## [M27K K-b visuals] Portrait presentation for `run_new_game()`.
##
## Source's real `oak_speech.c` draws these as BG2 tile-blits, not sprites
## (`LoadTrainerPic`/`CopyRectToBgTilemapBufferRect` — see
## `docs/m27k_oak_speech_visuals_recon.md` §A). A `TextureRect` swap is the
## direct Godot equivalent and simpler than the source technique, not a
## reduced one.
##
## Built in code rather than as a .tscn, matching every sibling field widget
## (`MessageBox`, `YesNoBox`, `NamingScreen`, ...) — none of them are .tscn
## either; this project's own established convention for this specific
## subsystem is code-built CanvasLayer widgets, not authored scenes.
##
## ⚠️ **DELIBERATE SCOPE**: the four portraits (Oak, Red, Leaf, the rival),
## the ball-release beat, and the ground platform are wired. **The tiled
## background scene is now wired too, 2026-08-06** — `oak_speech_bg.png` is
## decoded from source's real `oak_speech_bg.png`/`.bin` tile+tilemap pair
## (`scripts/gen_oak_speech_assets.py`, reusing `gen_battle_anim_backgrounds
## .py`'s own already-proven screen-entry decoder rather than a fourth
## hand-rolled copy of the technique) — closing the "no background" gap this
## comment used to flag as a separate, undecided task. The "shrink into the
## overworld" exit is a plain fade here, not source's BG-affine scale-down —
## recon §D already found no exotic GBA trick is actually needed to
## reproduce the BEAT, only the technique differs.
##
## ⚠️ **ALIGNMENT FIX, 2026-08-06.** The original layout picked the
## portrait's feet, the platform's own band, and the ball-release point as
## three INDEPENDENT offsets with no shared reference — they agreed with
## nothing but themselves. A real, reported bug, not a matter of taste: the
## portrait's own feet sat a full 162px above the platform's top edge (a
## visible floating gap), and the platform itself (3 tiles = 288px) was
## narrower than the gap BETWEEN the two gender-picker portraits (their
## outer edges span -352..352, 704px) — so during gender selection neither
## Red nor Leaf stood anywhere near it at all. Both are fixed by deriving
## every one of these offsets from ONE shared `_GROUND_Y` constant (the
## portrait's own feet line) instead of three independently-tuned numbers,
## and by widening the platform to 8 tiles (a left-cap + 6 repeated middles
## + a right-cap, the correct technique for stretching a 3-frame cap/
## middle/cap strip) so its footprint covers BOTH the solo portrait's stance
## and the full gender-picker span. The ball/mon release point is also
## shifted off-center (previously dead-centered under the solo portrait,
## which is what produced ~150px of the mon's own sprite drawing directly
## over Oak's lower body) so the two never compete for the same pixels.
##
## ⚠️ **THE PLATFORM IS 3 FRAMES SLICED FROM ONE SHEET, PLACED SIDE BY SIDE
## — NOT PORTED FROM SOURCE'S OWN 3-SPRITE PLACEMENT, WHICH THIS PROJECT
## DOESN'T PORT LITERALLY.** Source positions 3 separate platform OAM
## sprites at fixed GBA screen coordinates
## (`CreatePikachuOrPlatformSprites`, `oak_speech.c`) — this project's own
## established convention (`YesNoBox`'s own doc comment makes the same
## call) is to NOT port literal GBA tile coordinates onto a 1024×768
## canvas, so this reproduces the SHAPE (three tiles forming one strip)
## rather than the coordinates.
##
## ⚠️ **THE BALL RELEASES A RANDOM ROSTER SPECIES, NOT SOURCE'S FIXED
## NIDORAN♀ — Rob's own call, 2026-08-05, fully random across all 386,
## legendaries included.** There is no legendary/mythical tag anywhere in
## `pokemon.json`/`PokemonSpecies` to filter against even if a curated pool
## had been chosen instead — confirmed before asking, not assumed. **NO
## CRY PLAYS.** This project has zero audio playback anywhere (confirmed by
## a full grep immediately before writing this) — a real per-species cry
## library sits vendored and unwired at `assets/Essentials_v19.1/Audio/
## Cries/`, but standing up this project's first-ever audio system for one
## incidental beat was judged out of scope, matching the existing no-op
## precedent for `playfanfare`/`playse` already recorded against `[M27K
## K-a]`. Also NOT built: the reverse ball-RECALL animation source plays
## later (`Task_OakSpeech_ReturnNidoranFToPokeBall`) — this pass is the
## release only.
##
## ⚠️ **MOUSE ONLY, ON PURPOSE — Rob's own sequencing, 2026-08-05.** Every
## sibling field widget (`YesNoBox`, `FieldStartMenu`, ...) is driven purely
## by a central `move()`/`confirm()` dispatch in `overworld.gd`'s
## `_unhandled_input`, with zero mouse support anywhere in this subsystem —
## confirmed by a full grep before writing this file. This is the first
## mouse-clickable field widget. `move()`/`confirm()` are still exposed below,
## matching the sibling shape, so wiring keyboard/gamepad into the same
## central dispatch later is a plumbing change, not a redesign — but that
## wiring is deliberately NOT done in this pass, per Rob's own "in future"
## framing when this was scoped. Do not read the missing dispatch block as
## the same class of oversight `[M27L L2]` found and fixed for the gender
## question's own prior YesNoBox — it is a stated omission, not a silent one.

signal gender_chosen(boy: bool)

const PORTRAIT_SIZE := Vector2(192, 288)
const GENDER_GAP := 160.0

const _PORTRAITS := {
	"oak": "res://assets/sprites/oak_speech/oak.png",
	"red": "res://assets/sprites/oak_speech/red.png",
	"leaf": "res://assets/sprites/oak_speech/leaf.png",
	"rival": "res://assets/sprites/oak_speech/rival.png",
}

## Reuses the exact ball-sheet asset the battle send-out animation already
## loads (`battle_screen_shared.gd`'s own `_BALL_SPRITE`/`_BALL_FRAME_*`
## constants) — same file, same 2-frame closed/open layout — rather than
## importing a second copy or a second sheet convention.
const _BALL_SHEET := "res://assets/sprites/battle_ui/balls/poke.png"
const _BALL_FRAME_SIZE := 16
const _BALL_FRAME_CLOSED := 0
const _BALL_FRAME_OPEN := 1
const _BALL_DISPLAY_SIZE := 64.0
const _RELEASED_SPRITE_SIZE := Vector2(192, 192)

## The one shared reference every ground-level offset below derives from —
## where the portraits' own feet sit, relative to screen CENTER (matching
## every node in this file, all anchored via `PRESET_CENTER`). Chosen to
## leave the platform comfortably clear of the message box's own top edge
## (768/2 - (140 message-box height + 24 margin) = 220 from center — see
## `message_box.gd`'s own HEIGHT/MARGIN constants) while still reading as
## "standing near the bottom of the scene," matching source's own real
## framing (platform/characters occupy the lower ~40% of the screen).
const _GROUND_Y := 60.0

## Off-center so the mon never draws squarely over the (centered) solo
## portrait — previously both were centered on x=0, which put ~150px of the
## released sprite directly on top of Oak's own lower body. Vertically
## anchored to `_GROUND_Y` too, so it visibly stands on the same ground the
## portraits do rather than an independently-tuned offset.
const _RELEASE_OFFSET := Vector2(220.0, _GROUND_Y + 40.0)

## Confirmed 32×96 indexed PNG, three 32×32 frames stacked vertically —
## the same GBA stacked-frame convention documented in
## `docs/m27k_cinematic_recon.md`.
const _PLATFORM_SHEET := "res://assets/sprites/oak_speech/platform.png"
const _PLATFORM_FRAME_SIZE := 32
const _PLATFORM_TILE_DISPLAY := 96.0
## 8 tiles (a left-cap + 6 repeated middles + a right-cap — the correct way
## to stretch a 3-frame cap/middle/cap strip to arbitrary width) so the
## platform's own 768px footprint covers BOTH the solo portrait's stance
## AND the full span between the two gender-picker portraits (their outer
## edges sit at ±352 — see `_make_gender_button`'s own `GENDER_GAP`/
## `PORTRAIT_SIZE` math), rather than the original 3-tile/288px strip that
## covered neither.
const _PLATFORM_TILE_COUNT := 8
## Top edge sits just ABOVE the portraits' own feet line so the two visibly
## overlap by a few pixels (reads as "standing on the grass," not floating
## above it) — the direct fix for the ~162px gap the original independent
## offsets left between them.
const _PLATFORM_OFFSET := Vector2(0, _GROUND_Y - 6.0 + _PLATFORM_TILE_DISPLAY / 2.0)

## Real background scene, decoded from source's own `oak_speech_bg.png`/
## `.bin` tile+tilemap pair (`scripts/gen_oak_speech_assets.py`) — 256×160,
## stretched non-uniformly to fill the full canvas, matching this project's
## own established precedent for background art whose native aspect ratio
## doesn't match the 4:3 canvas (`[M26c-2]`'s battle-background compositing
## uses the identical non-uniform-stretch approach).
const _BACKGROUND_SHEET := "res://assets/sprites/oak_speech/oak_speech_bg.png"

var _background: TextureRect
var _solo: TextureRect
var _boy_button: TextureButton
var _girl_button: TextureButton
var _ball: TextureRect
var _released: TextureRect
var _platform: Array[TextureRect] = []
var _picking := false
## Cursor position for the still-unwired future keyboard pass: 0 = BOY (Red),
## 1 = GIRL (Leaf). Kept in step with hover so a later keyboard dispatch and
## the mouse can share one highlight without fighting each other.
var _index := 0


func _init() -> void:
	# Below every message/menu widget (lowest existing layer is 65) so the
	# message box and any prompt always draw on top of a portrait, matching
	# source's own layering (text box over character art).
	layer = 30


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Added FIRST of all, so it draws behind the platform, the portraits and
	# every other element — the scene backdrop, not a foreground piece.
	_background = TextureRect.new()
	_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background.stretch_mode = TextureRect.STRETCH_SCALE
	_background.texture = load(_BACKGROUND_SHEET)
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_background.visible = false
	root.add_child(_background)

	# Added next, so it draws behind every portrait/ball/released sprite —
	# it's the ground, not a foreground element. A left-cap + repeated
	# middles + a right-cap (see `_PLATFORM_TILE_COUNT`'s own doc comment).
	for i in range(_PLATFORM_TILE_COUNT):
		var frame := 1
		if i == 0:
			frame = 0
		elif i == _PLATFORM_TILE_COUNT - 1:
			frame = 2
		var tile := TextureRect.new()
		tile.set_anchors_preset(Control.PRESET_CENTER)
		tile.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tile.stretch_mode = TextureRect.STRETCH_SCALE
		tile.texture = _platform_frame(frame)
		var half_span: float = _PLATFORM_TILE_COUNT / 2.0
		var tile_left: float = _PLATFORM_OFFSET.x + (i - half_span) * _PLATFORM_TILE_DISPLAY
		tile.offset_left = tile_left
		tile.offset_right = tile_left + _PLATFORM_TILE_DISPLAY
		tile.offset_top = _PLATFORM_OFFSET.y - _PLATFORM_TILE_DISPLAY / 2.0
		tile.offset_bottom = _PLATFORM_OFFSET.y + _PLATFORM_TILE_DISPLAY / 2.0
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.visible = false
		root.add_child(tile)
		_platform.append(tile)

	_solo = TextureRect.new()
	_solo.set_anchors_preset(Control.PRESET_CENTER)
	_solo.offset_left = -PORTRAIT_SIZE.x / 2.0
	_solo.offset_right = PORTRAIT_SIZE.x / 2.0
	_solo.offset_top = _GROUND_Y - PORTRAIT_SIZE.y
	_solo.offset_bottom = _GROUND_Y
	_solo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_solo.stretch_mode = TextureRect.STRETCH_SCALE
	_solo.visible = false
	root.add_child(_solo)

	_boy_button = _make_gender_button(-GENDER_GAP - PORTRAIT_SIZE.x)
	_boy_button.pressed.connect(_on_boy_pressed)
	_boy_button.mouse_entered.connect(func(): _hover(0))
	root.add_child(_boy_button)

	_girl_button = _make_gender_button(GENDER_GAP)
	_girl_button.pressed.connect(_on_girl_pressed)
	_girl_button.mouse_entered.connect(func(): _hover(1))
	root.add_child(_girl_button)

	_ball = TextureRect.new()
	_ball.set_anchors_preset(Control.PRESET_CENTER)
	_ball.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_ball.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_ball.size = Vector2(_BALL_DISPLAY_SIZE, _BALL_DISPLAY_SIZE)
	_ball.pivot_offset = _ball.size * 0.5
	_ball.offset_left = _RELEASE_OFFSET.x - _ball.size.x / 2.0
	_ball.offset_right = _RELEASE_OFFSET.x + _ball.size.x / 2.0
	_ball.offset_top = _RELEASE_OFFSET.y - _ball.size.y / 2.0
	_ball.offset_bottom = _RELEASE_OFFSET.y + _ball.size.y / 2.0
	_ball.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ball.visible = false
	root.add_child(_ball)

	_released = TextureRect.new()
	_released.set_anchors_preset(Control.PRESET_CENTER)
	_released.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_released.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_released.size = _RELEASED_SPRITE_SIZE
	_released.pivot_offset = _released.size * 0.5
	_released.offset_left = _RELEASE_OFFSET.x - _released.size.x / 2.0
	_released.offset_right = _RELEASE_OFFSET.x + _released.size.x / 2.0
	_released.offset_top = _RELEASE_OFFSET.y - _released.size.y / 2.0
	_released.offset_bottom = _RELEASE_OFFSET.y + _released.size.y / 2.0
	_released.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_released.visible = false
	root.add_child(_released)


func _make_gender_button(left_offset: float) -> TextureButton:
	var b := TextureButton.new()
	b.set_anchors_preset(Control.PRESET_CENTER)
	b.offset_left = left_offset
	b.offset_right = left_offset + PORTRAIT_SIZE.x
	# Same feet line as the solo portrait (`_GROUND_Y`) — both stand on the
	# same platform, so both are pinned to the same reference.
	b.offset_top = _GROUND_Y - PORTRAIT_SIZE.y
	b.offset_bottom = _GROUND_Y
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_SCALE
	b.visible = false
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	return b


## Show one portrait alone (Oak's own lines, the confirmed player, the
## rival). `which` is a key into `_PORTRAITS` — "oak" / "red" / "leaf" /
## "rival".
func show_solo(which: String) -> void:
	_close_picker()
	if not _PORTRAITS.has(which):
		return
	_solo.texture = load(_PORTRAITS[which])
	_solo.visible = true
	_set_platform_visible(true)


func hide_all() -> void:
	_solo.visible = false
	_ball.visible = false
	_released.visible = false
	_set_platform_visible(false)
	_close_picker()


## Show Red and Leaf side by side and wait for a click on either. Returns
## true for BOY (Red), false for GIRL (Leaf) — the same polarity `YesNoBox`
## already carried for this exact question before this pass replaced it.
func pick_gender() -> bool:
	_solo.visible = false
	_boy_button.texture_normal = load(_PORTRAITS["red"])
	_girl_button.texture_normal = load(_PORTRAITS["leaf"])
	_boy_button.modulate = Color.WHITE
	_girl_button.modulate = Color.WHITE
	_boy_button.visible = true
	_girl_button.visible = true
	_set_platform_visible(true)
	_picking = true
	_index = 0
	var boy: bool = await gender_chosen
	return boy


## Toggles the whole ground scene — the background AND the platform strip
## standing on it — as one unit, since there's no scenario where a portrait
## is shown but the scene behind it isn't (the same reasoning this
## function's own pre-existing platform-toggle already used).
func _set_platform_visible(v: bool) -> void:
	_background.visible = v
	for tile in _platform:
		tile.visible = v


func _hover(index: int) -> void:
	_index = index
	_boy_button.modulate = Color(1.2, 1.2, 1.2) if index == 0 else Color.WHITE
	_girl_button.modulate = Color(1.2, 1.2, 1.2) if index == 1 else Color.WHITE


func _on_boy_pressed() -> void:
	if not _picking:
		return
	_close_picker()
	gender_chosen.emit(true)


func _on_girl_pressed() -> void:
	if not _picking:
		return
	_close_picker()
	gender_chosen.emit(false)


func _close_picker() -> void:
	_picking = false
	_boy_button.visible = false
	_girl_button.visible = false


## Move the cursor between the two portraits — NOT wired to any input
## dispatch yet (see the file-level doc comment). Exposed now so that wiring
## is the only remaining step later, matching `YesNoBox.move()`'s own shape.
func move(delta: int) -> void:
	if not _picking:
		return
	_hover(clampi(_index + delta, 0, 1))


## Confirm the hovered/cursored portrait. Same "not wired yet" caveat as
## `move()`.
func confirm() -> void:
	if not _picking:
		return
	if _index == 0:
		_on_boy_pressed()
	else:
		_on_girl_pressed()


## Fade the whole overlay out. Stands in for source's BG-affine
## shrink-into-the-overworld exit — recon confirmed no exotic GBA technique
## is actually load-bearing for the BEAT, only the mechanism differs
## (`docs/m27k_oak_speech_visuals_recon.md` §D).
func fade_out(duration: float = 0.6) -> void:
	var root: Control = get_child(0)
	var tw := create_tween()
	tw.tween_property(root, "modulate:a", 0.0, duration)
	await tw.finished
	hide_all()
	root.modulate.a = 1.0


## [M27K K-b visuals] The ball-release beat: a random roster species pops
## out of a Poké Ball. Stands in for `Task_OakSpeech_ReleaseNidoranFFrom
## PokeBall` — see the file-level doc comment for what's deliberately
## different (random species, no cry, no reverse recall).
##
## Picks its species the same way `RandomTeamGenerator.generate_team()`
## already does (`scripts/battle/core/random_team_generator.gd:41-56`) —
## pull a random entry from `PokemonRegistry.get_all_species()` and read
## its own `dex` field, rather than assuming dex ids are a contiguous
## `[1, 386]` range.
func release_random_pokemon() -> void:
	var pool: Array = PokemonRegistry.get_all_species()
	if pool.is_empty():
		return
	var entry: Dictionary = pool[randi() % pool.size()]
	var dex: int = int(entry.get("dex", -1))
	var tex := SpriteRegistry.get_front(dex)
	if tex == null:
		return

	_set_platform_visible(true)
	_ball.texture = _ball_frame(_BALL_FRAME_CLOSED)
	_ball.rotation = 0.0
	_ball.modulate.a = 1.0
	_ball.visible = true

	# A small wobble before opening — the same "something's about to happen"
	# beat every real ball-open plays, kept simple (three rotation tweens)
	# rather than pulling in the battle screen's own tuned send-out sequence,
	# which is not reusable outside battle without its slot/party scaffolding
	# (confirmed before writing this — see docs/m27k_oak_speech_visuals_recon.md).
	var wobble := create_tween()
	wobble.tween_property(_ball, "rotation", 0.35, 0.1)
	wobble.tween_property(_ball, "rotation", -0.35, 0.2)
	wobble.tween_property(_ball, "rotation", 0.0, 0.15)
	await wobble.finished

	_ball.texture = _ball_frame(_BALL_FRAME_OPEN)
	_released.texture = tex
	_released.scale = Vector2.ZERO
	_released.modulate.a = 0.0
	_released.visible = true
	var grow := create_tween()
	grow.set_parallel(true)
	grow.tween_property(_released, "scale", Vector2.ONE, 0.35)
	grow.tween_property(_released, "modulate:a", 1.0, 0.35)
	await grow.finished

	await get_tree().create_timer(1.2).timeout

	var out := create_tween()
	out.set_parallel(true)
	out.tween_property(_ball, "modulate:a", 0.0, 0.4)
	out.tween_property(_released, "modulate:a", 0.0, 0.4)
	await out.finished
	_ball.visible = false
	_released.visible = false


## Reuses the exact ball sheet/frame layout `battle_screen_shared.gd`'s own
## `_make_ball_sprite` already reads — same file, same 16px-frame, closed-
## then-open vertical layout.
func _ball_frame(frame: int) -> AtlasTexture:
	var sheet := load(_BALL_SHEET) as Texture2D
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = Rect2(0, frame * _BALL_FRAME_SIZE, _BALL_FRAME_SIZE, _BALL_FRAME_SIZE)
	return atlas


## Slice one of the platform sheet's 3 vertically-stacked 32×32 frames.
func _platform_frame(frame: int) -> AtlasTexture:
	var sheet := load(_PLATFORM_SHEET) as Texture2D
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = Rect2(0, frame * _PLATFORM_FRAME_SIZE,
			_PLATFORM_FRAME_SIZE, _PLATFORM_FRAME_SIZE)
	return atlas
