extends Node

## [M27K K-b] Player identity, the naming screen, and Oak's speech.
##
## The claims most worth pinning:
##
##   * gender is asked BEFORE the name, because the preset list is keyed on it;
##   * the preset MENU comes first and the keyboard only on NEW NAME — source
##     never opens a keyboard, and most real playthroughs never see one;
##   * the cap is 12, deliberately NOT source's 7 (Rob's call — see
##     `PlayerIdentity`'s header), enforced twice on purpose: refuse the keypress
##     past it, and truncate anything handed in;
##   * `{PLAYER}` now reads the chosen name, retiring a hardcode that lived in
##     three places agreeing by luck.

const EXPECTED_TOTAL := 65

## Comfortably past the cap, so the refusal is what stops it and not the loop.
const NAME_OVERFILL := 20

var _total := 0
var _failed := 0
var _gated := 0


func _chk(label: String, cond: bool) -> void:
	_total += 1
	if not cond:
		_failed += 1
		print("FAILED: %s" % label)


func _screen() -> NamingScreen:
	var s := NamingScreen.new()
	add_child(s)
	return s


func _ready() -> void:
	_test_identity()
	_test_presets()
	_test_choices_mode()
	_test_keyboard()
	_test_placeholders()
	await _test_oak_speech_overlay()
	await _test_ball_release()
	await _test_name_confirm_and_lets_go_portrait()

	var accounted := _total + _gated
	_chk("Z.99 every expected assertion ran (%d + %d gated == %d)"
			% [_total, _gated, EXPECTED_TOTAL], accounted == EXPECTED_TOTAL)
	print("m27k_newgame_test: %d/%d passed" % [_total - _failed, _total])
	get_tree().quit()


## --- A. identity ---
func _test_identity() -> void:
	var id := PlayerIdentity.new()
	_chk("A.01 nobody is named until a new game says so", not id.is_named())
	_chk("A.02 but {PLAYER} still reads as a name, not a blank",
			id.display_name() != "")
	_chk("A.03 and so does the rival", id.display_rival_name() != "")

	id.set_name("ROB")
	_chk("A.04 a name sticks", id.name == "ROB" and id.is_named())
	_chk("A.05 and {PLAYER} reads it", id.display_name() == "ROB")

	# ⚠️ THE CAP IS DELIBERATELY NOT SOURCE'S 7 — see PlayerIdentity's own
	# header. Source's limit is a GBA save-block field width this project does
	# not share; 12 matches POKEMON_NAME_LENGTH so there is one name bound, not
	# two. Truncates rather than refusing, so a caller that skips the screen
	# cannot mint a name the save could not hold.
	_chk("A.06 the cap is 12, not source's 7", PlayerIdentity.NAME_LENGTH == 12)
	id.set_name("ABCDEFGHIJKLMNOP")
	_chk("A.07 an over-long name is TRUNCATED, not rejected",
			id.name == "ABCDEFGHIJKL" and id.name.length() == 12)
	id.set_name("ABCDEFGH")
	_chk("A.07b and a name that would have failed source's 7 now fits",
			id.name == "ABCDEFGH")
	id.set_name("   ")
	_chk("A.08 whitespace-only is no name at all", id.name == "")

	# The back pic is gender's, not a constant — this retires
	# `_PLAYER_BACK_PIC`'s own hardcode.
	id.gender = PlayerIdentity.Gender.GIRL
	var girl_pic := id.back_pic_stem()
	id.gender = PlayerIdentity.Gender.BOY
	_chk("A.09 the back sprite follows gender",
			girl_pic != id.back_pic_stem() and girl_pic == "leaf")


## --- B. the preset lists ---
func _test_presets() -> void:
	var id := PlayerIdentity.new()
	id.gender = PlayerIdentity.Gender.BOY
	var male := id.name_choices()
	id.gender = PlayerIdentity.Gender.GIRL
	var female := id.name_choices()
	# ⚠️ THIS IS WHY GENDER IS ASKED FIRST. The lists genuinely differ, so a
	# name chosen before the gender would be chosen from the wrong one.
	_chk("B.01 the two preset lists are genuinely different", male != female)
	_chk("B.02 both are source-sized (19 each)",
			male.size() == 19 and female.size() == 19)
	_chk("B.03 the rival gets its OWN list, not the male one",
			PlayerIdentity.RIVAL_NAMES != male
			and PlayerIdentity.RIVAL_NAMES.size() == 8)
	# The LeafGreen set, chosen to agree with the Leaf back sprite.
	_chk("B.04 the version-gated head is LeafGreen's, not FireRed's",
			male[0] == "GREEN" and male[1] == "LEAF" and not "RED" in male)
	_chk("B.05 every preset already fits the cap",
			_all_fit(male) and _all_fit(female)
			and _all_fit(PlayerIdentity.RIVAL_NAMES))


func _all_fit(names: PackedStringArray) -> bool:
	for n in names:
		if str(n).length() > PlayerIdentity.NAME_LENGTH:
			return false
	return true


## --- C. the preset menu ---
func _test_choices_mode() -> void:
	var s := _screen()
	s.open("Your name?", PlayerIdentity.MALE_NAMES)
	# ⚠️ SOURCE SHOWS THE MENU, NOT A KEYBOARD. Opening on the keyboard would
	# be a different game — most playthroughs take a preset and never type.
	_chk("C.01 it opens on the preset list", s.mode == NamingScreen.Mode.CHOICES)
	_chk("C.02 with NEW NAME at the head",
			str(s.row_texts()[0]).contains(PlayerIdentity.NEW_NAME))
	_chk("C.03 and the presets under it",
			str(s.row_texts()[1]).contains("GREEN"))
	_chk("C.04 the prompt says why it is open",
			s.prompt_text() == "Your name?")

	s.move(-1)
	_chk("C.05 up on the first row CLAMPS", s.choice_index == 0)
	s.move(1)
	_chk("C.06 down moves", s.choice_index == 1)

	var got: Array[String] = []
	s.name_chosen.connect(func(v: String) -> void: got.append(v))
	s.confirm()
	_chk("C.07 taking a preset reports it and closes",
			got.size() == 1 and got[0] == "GREEN" and not s.is_open)

	# NEW NAME is the only row that reaches the keyboard.
	var s2 := _screen()
	s2.open("Your name?", PlayerIdentity.MALE_NAMES)
	s2.confirm()
	_chk("C.08 NEW NAME opens the keyboard instead of choosing",
			s2.mode == NamingScreen.Mode.KEYBOARD and s2.is_open)
	_chk("C.09 and reports nothing yet", s2.typed == "")
	s.free(); s2.free()


## --- D. the keyboard ---
func _test_keyboard() -> void:
	var s := _screen()
	s.open("Your name?", PlayerIdentity.MALE_NAMES)
	s.confirm()  # NEW NAME

	_chk("D.01 the entry line shows the cap as underscores",
			s.entry_text().length() == PlayerIdentity.NAME_LENGTH)
	s.confirm()
	_chk("D.02 a keypress types a character", s.typed == "A")
	_chk("D.03 and the entry line shows it",
			s.entry_text().begins_with("A") and s.entry_text().contains("_"))
	s.backspace()
	_chk("D.04 B backspaces rather than cancelling", s.typed == "" and s.is_open)
	s.backspace()
	_chk("D.05 and backspacing an empty name is harmless", s.typed == "")

	# ⚠️ THE CAP REFUSES THE KEYPRESS PAST IT. Enforced here as well as in
	# `sanitize`, deliberately — this is what makes the limit visible. Reads the
	# constant, so raising the cap again cannot leave a stale literal behind.
	for i in range(NAME_OVERFILL):
		s.confirm()
	_chk("D.06 typing past the cap is refused, not silently dropped",
			s.typed.length() == PlayerIdentity.NAME_LENGTH)

	var got: Array[String] = []
	s.name_chosen.connect(func(v: String) -> void: got.append(v))
	_chk("D.07 OK accepts what was typed", s.accept())
	_chk("D.08 reporting it and closing",
			got.size() == 1 and got[0].length() == PlayerIdentity.NAME_LENGTH
			and not s.is_open)

	# An empty name is refused — a blank player renders every {PLAYER} as "".
	var s2 := _screen()
	s2.open("Your name?", PlayerIdentity.MALE_NAMES)
	s2.confirm()
	_chk("D.09 OK on an empty name is refused", not s2.accept())
	_chk("D.10 and the screen stays open", s2.is_open)

	# Pages cycle, and the cursor resets so it cannot point off the new page.
	var s3 := _screen()
	s3.open("Your name?", PlayerIdentity.MALE_NAMES)
	s3.confirm()
	s3.move(20)
	s3.next_page()
	s3.confirm()
	_chk("D.11 the second page types lowercase", s3.typed == "a")
	s3.next_page()
	s3.confirm()
	_chk("D.12 and the third digits/symbols", s3.typed == "a0")
	s.free(); s2.free(); s3.free()


## --- E. the placeholders this retires ---
func _test_placeholders() -> void:
	var prev := TextBuffers.identity
	var id := PlayerIdentity.new()
	id.set_name("ROB")
	id.set_rival_name("GARY")
	TextBuffers.identity = id
	var b := TextBuffers.new()
	# ⚠️ 1193 corpus uses of {PLAYER}, and until now every one read a constant.
	_chk("E.01 {PLAYER} reads the chosen name", b.expand("{PLAYER}") == "ROB")
	_chk("E.02 {RIVAL} reads the chosen rival", b.expand("{RIVAL}") == "GARY")
	_chk("E.03 in a real sentence, not just alone",
			b.expand("So your name is {PLAYER}.") == "So your name is ROB.")

	# With nobody named, the fallback must still read as a name — a debug boot
	# never runs the speech.
	TextBuffers.identity = null
	var b2 := TextBuffers.new()
	_chk("E.04 an unnamed session still renders a name, not a blank",
			b2.expand("{PLAYER}") != "" and b2.expand("{RIVAL}") != "")
	# And the two fallbacks agree with PlayerIdentity's own.
	TextBuffers.identity = PlayerIdentity.new()
	var b3 := TextBuffers.new()
	_chk("E.05 and agrees with PlayerIdentity's own fallback",
			b3.expand("{PLAYER}") == b2.expand("{PLAYER}"))
	TextBuffers.identity = prev

	# The overworld carries the speech and the flow.
	var ow: Node2D = load("res://scenes/overworld/overworld.tscn").instantiate() as Node2D
	_chk("E.06 the overworld runs a new game", ow.has_method("run_new_game"))
	_chk("E.07 and drives the naming screen", ow.has_method("_drive_naming"))
	# ⚠️ Source's own beats, in source's own order.
	_chk("E.08 the speech opens where source opens",
			str(ow.OAK_WELCOME).contains("Glad to meet you"))
	_chk("E.09 asks gender before the name",
			str(ow.OAK_ASK_GENDER).contains("boy")
			and str(ow.OAK_YOUR_NAME).contains("your name"))
	_chk("E.10 and closes on the legend line",
			str(ow.OAK_LETS_GO).contains("legend"))
	_chk("E.11 the name-back line is a placeholder, expanded at print time",
			str(ow.OAK_SO_YOUR_NAME).contains("{PLAYER}"))
	ow.free()


## --- F. [M27K K-b visuals] the portrait overlay ---
func _test_oak_speech_overlay() -> void:
	var overlay := OakSpeechOverlay.new()
	add_child(overlay)

	_chk("F.01 gender buttons start hidden",
			not overlay._boy_button.visible and not overlay._girl_button.visible)

	overlay.show_solo("oak")
	_chk("F.02 show_solo shows the requested portrait",
			overlay._solo.visible
			and overlay._solo.texture.resource_path.ends_with("oak.png"))
	# ⚠️ `_platform_frame()` always returns a real `AtlasTexture` OBJECT even
	# when its underlying sheet fails to load — a real regression this
	# session hit (a brand-new asset with no `.import` sidecar yet logs an
	# ERROR and loads as null, but wrapped inside a non-null AtlasTexture),
	# so `t.texture != null` alone is VACUOUS and would not have caught it.
	# `t.texture.atlas` is what actually holds the loaded sheet. Break-tested
	# by removing `platform.png.import` directly and confirming this line —
	# and only this line — goes red.
	_chk("F.02b the platform is %d tiles, each with a real loaded sheet" % OakSpeechOverlay._PLATFORM_TILE_COUNT,
			overlay._platform.size() == OakSpeechOverlay._PLATFORM_TILE_COUNT
			and overlay._platform.all(func(t): return t.texture != null and t.texture.atlas != null)
			and overlay._platform.all(func(t): return t.visible))

	overlay.hide_all()
	_chk("F.03 hide_all hides the solo portrait",
			not overlay._solo.visible)
	_chk("F.03b hide_all hides the platform too",
			overlay._platform.all(func(t): return not t.visible))

	# ⚠️ `pick_gender()` is a coroutine and GDScript requires the call site
	# itself to `await` it — so the click that answers it has to be queued
	# with `call_deferred` BEFORE the await, to land on the next idle frame
	# once `pick_gender()` has already opened the picker and is itself
	# waiting on `gender_chosen`.
	overlay._on_girl_pressed.call_deferred()
	var boy: bool = await overlay.pick_gender()
	_chk("F.04 pick_gender showed Red and Leaf, not a generic pair",
			overlay._boy_button.texture_normal.resource_path.ends_with("red.png")
			and overlay._girl_button.texture_normal.resource_path.ends_with("leaf.png"))
	# ⚠️ Mirrors the polarity YesNoBox carried for this exact question before
	# this pass replaced it — Red/BOY first, Leaf/GIRL second.
	_chk("F.05 choosing Leaf resolves to GIRL, not BOY", boy == false)
	_chk("F.06 the picker closes once chosen",
			not overlay._boy_button.visible and not overlay._girl_button.visible)

	overlay.queue_free()


## --- G. [M27K K-b visuals] the ball-release beat ---
func _test_ball_release() -> void:
	var overlay := OakSpeechOverlay.new()
	add_child(overlay)

	_chk("G.01 nothing is showing before the beat starts",
			not overlay._ball.visible and not overlay._released.visible)

	# ⚠️ Coroutines require `await` at their own call site (the same GDScript
	# rule `pick_gender()`'s own test above works around) — so the full ~2s
	# real sequence (wobble, open, grow, hold, fade) runs end to end here,
	# not a snapshot mid-flight.
	await overlay.release_random_pokemon()
	_chk("G.02 both the ball and the released sprite hide again once the beat ends",
			not overlay._ball.visible and not overlay._released.visible)
	_chk("G.03 a real species texture was assigned, not left null",
			overlay._released.texture != null)

	overlay.queue_free()


## --- H. [2026-08-06] the name-confirm/retry loop, and the "Let's go!" ---
## --- portrait fix, both driven through the REAL `run_new_game()` ---
##
## ⚠️ **DRIVEN END TO END ON PURPOSE, NOT RE-ASSERTED IN ISOLATION.** A test
## that simply called `overlay.show_solo("red" if boy else "leaf")` directly
## and checked the result would never touch `run_new_game()`'s own line —
## reverting the real fix would leave such a test green. The only genuine
## regression guard is driving the actual coroutine to the point where the
## fix lives, the same discipline this project's own CLAUDE.md calls "a
## guard whose injection you had to hand-pick is a guard you have not
## tested."

## Polls `cond` once per frame until it returns true, or gives up after
## `max_seconds` of real (wall-clock) time — NOT a frame count. Headless
## Godot runs uncapped, well past 60fps, so a frame-count budget silently
## represents far less real time than it looks like; `Time.get_ticks_msec()`
## is what makes this actually cover `fade_in`/`fade_out` (0.6s each) and
## the ball-release beat's own ~2.4s real sequence regardless of how fast
## the engine happens to be stepping frames.
func _wait_until(cond: Callable, max_seconds: float = 6.0) -> void:
	var deadline := Time.get_ticks_msec() + int(max_seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if cond.call():
			return
		await get_tree().process_frame


## Drains a `MessageBox` fully. `advance()` first skips typing (still open),
## then pages forward, finally closing on the last page — looping until it
## reports closed is robust to any page count.
func _advance_box(box: MessageBox) -> void:
	while box.advance():
		await get_tree().process_frame


func _test_name_confirm_and_lets_go_portrait() -> void:
	OverworldSession.reset()
	OverworldSession.pending_new_game = true
	var ow: Node2D = load("res://scenes/overworld/overworld.tscn").instantiate() as Node2D
	add_child(ow)

	_chk("H.01 the rival-confirm text is source's own, verbatim, and a placeholder",
			str(ow.OAK_CONFIRM_RIVAL_NAME).contains("{RIVAL}")
			and str(ow.OAK_CONFIRM_RIVAL_NAME).contains("was it"))

	# Let `_ready()`/`run_new_game.call_deferred()` fire, then work through
	# fade_in and the opening WELCOME/THIS_WORLD pages.
	await _wait_until(func(): return ow._box != null and ow._box.is_open)
	await _advance_box(ow._box)

	# The ball-release beat (~2s real, no `_box` interaction) — just wait for
	# the next box to open, same idiom Section G already uses for a real
	# multi-second sequence run to completion rather than skipped.
	await _wait_until(func(): return ow._box.is_open)
	await _advance_box(ow._box)  # INHABITED / I_STUDY / ABOUT_YOURSELF

	await _wait_until(func(): return ow._box.is_open)
	await _advance_box(ow._box)  # ASK_GENDER

	# Gender pick — GIRL this time (mirrors F.05's own polarity: pressing
	# Leaf resolves to GIRL, i.e. `boy == false`).
	await _wait_until(func(): return ow._oak_overlay._girl_button.visible)
	ow._oak_overlay._on_girl_pressed.call_deferred()

	await _wait_until(func(): return ow._box.is_open)  # YOUR_NAME
	await _advance_box(ow._box)

	# --- player name: first attempt, answer NO ---
	await _wait_until(func(): return ow._naming.is_open)
	ow._naming.move(1)
	ow._naming.confirm()
	await _wait_until(func(): return ow._yes_no != null and ow._yes_no.is_open)
	_chk("H.02 the confirmation opens with the box AND the yes/no both up",
			ow._box.is_open and ow._yes_no.is_open)
	await _wait_until(func(): return ow._yes_no.accepts_input)
	var first_name: String = OverworldSession.identity.name
	ow._yes_no.cancel()

	await _wait_until(func(): return ow._naming.is_open)
	_chk("H.03 saying NO reopens naming — the loop actually retries",
			ow._naming.is_open)

	# --- second attempt, a DIFFERENT preset, answer YES ---
	ow._naming.move(2)
	ow._naming.confirm()
	await _wait_until(func(): return ow._yes_no != null and ow._yes_no.is_open)
	await _wait_until(func(): return ow._yes_no.accepts_input)
	ow._yes_no.confirm()

	await _wait_until(func(): return not ow._yes_no.is_open and not ow._naming.is_open)
	var second_name: String = OverworldSession.identity.name
	_chk("H.04 saying YES commits the SECOND name, proving retry re-did naming",
			second_name != "" and second_name != first_name
			and second_name == OverworldSession.identity.name)

	# --- rival name: same shape, one round trip proves the same primitive ---
	await _wait_until(func(): return ow._box.is_open)  # RIVAL_INTRO / RIVAL_NAME
	await _advance_box(ow._box)

	await _wait_until(func(): return ow._naming.is_open)
	ow._naming.move(1)
	ow._naming.confirm()
	await _wait_until(func(): return ow._yes_no != null and ow._yes_no.is_open)
	await _wait_until(func(): return ow._yes_no.accepts_input)
	var first_rival: String = OverworldSession.identity.rival_name
	ow._yes_no.cancel()

	await _wait_until(func(): return ow._naming.is_open)
	_chk("H.05 the rival question retries the same way", ow._naming.is_open)

	ow._naming.move(2)
	ow._naming.confirm()
	await _wait_until(func(): return ow._yes_no != null and ow._yes_no.is_open)
	await _wait_until(func(): return ow._yes_no.accepts_input)
	ow._yes_no.confirm()

	await _wait_until(func(): return not ow._yes_no.is_open and not ow._naming.is_open)
	var second_rival: String = OverworldSession.identity.rival_name
	_chk("H.06 and commits the second rival name too",
			second_rival != "" and second_rival != first_rival)

	await _wait_until(func(): return ow._box.is_open)  # REMEMBER_RIVAL
	await _advance_box(ow._box)

	# --- the Let's Go line: THE ACTUAL FIX-1 REGRESSION GUARD ---
	await _wait_until(func(): return ow._box.is_open)  # LETS_GO
	_chk("H.07 the closing line shows the PLAYER's own portrait, not Oak's",
			ow._oak_overlay._solo.texture.resource_path.ends_with("leaf.png"))

	await _advance_box(ow._box)
	ow.queue_free()
