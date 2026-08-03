extends Node

## [M27K K-b] Player identity, the naming screen, and Oak's speech.
##
## The claims most worth pinning:
##
##   * gender is asked BEFORE the name, because the preset list is keyed on it;
##   * the preset MENU comes first and the keyboard only on NEW NAME — source
##     never opens a keyboard, and most real playthroughs never see one;
##   * the 7-character cap is source's `PLAYER_NAME_LENGTH`, enforced twice on
##     purpose (refuse the 8th keypress; truncate anything handed in);
##   * `{PLAYER}` now reads the chosen name, retiring a hardcode that lived in
##     three places agreeing by luck.

const EXPECTED_TOTAL := 46

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

	# ⚠️ SOURCE'S OWN CAP — PLAYER_NAME_LENGTH, global.h:159. Truncates rather
	# than refusing, so a caller that skips the screen cannot mint a name the
	# save format could not hold.
	_chk("A.06 the cap is source's 7", PlayerIdentity.NAME_LENGTH == 7)
	id.set_name("ABCDEFGHIJ")
	_chk("A.07 an over-long name is TRUNCATED, not rejected",
			id.name == "ABCDEFG" and id.name.length() == 7)
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

	# ⚠️ THE CAP REFUSES THE 8TH KEYPRESS. Enforced here as well as in
	# `sanitize`, deliberately — this is what makes the limit visible.
	for i in range(12):
		s.confirm()
	_chk("D.06 the 8th character is refused, not silently dropped",
			s.typed.length() == PlayerIdentity.NAME_LENGTH)

	var got: Array[String] = []
	s.name_chosen.connect(func(v: String) -> void: got.append(v))
	_chk("D.07 OK accepts what was typed", s.accept())
	_chk("D.08 reporting it and closing",
			got.size() == 1 and got[0].length() == 7 and not s.is_open)

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
