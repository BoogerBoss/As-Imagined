@icon("res://icon.svg")
class_name TextTyper
extends RichTextLabel

## [M27F] Typewriter text for the overworld message box.
##
## VENDORED from `addons/dialogue_manager/dialogue_label.gd` (v3.10.2), not
## subclassed and not called into. Line references below are to that original.
##
## WHY VENDOR RATHER THAN USE THE PLUGIN — the reason is the CONTRACT, not the
## line count. `DialogueLabel.type_out()` does not type `.text`; it reads a
## `dialogue_line` object, and does so from four places:
##
##     :93   dialogue_line.text              (via _update_text, which OVERWRITES
##                                            anything you assigned to .text)
##     :160  dialogue_line.speeds            (per character)
##     :175  dialogue_line.inline_mutations  (per character)
##     :182  dialogue_line.extra_game_states (+ Engine.get_singleton("DialogueManager"))
##
## `var dialogue_line` is declared UNTYPED, so a stand-in object with those four
## fields works — but that is duck-typing into a private seam, not a supported
## integration point. The plugin's own v3.8.0 changelog rewrote this exact
## interaction ("make dialogue label use _update_text() when setting text in
## type_out()"), so upstream releases are as likely to break a stand-in silently
## as to fix anything for us, with no changelog entry that would mention us.
## Vendoring turns a live tripwire into a diff we control.
##
## DELIBERATELY NOT PORTED — the auto-pause model (`pause_at_characters`,
## `skip_pause_at_abbreviations`, `_should_auto_pause`, ~50 lines). That is prose
## typography: pause on ".?!", skip abbreviations, skip decimals. The reference
## does not do it — FRLG types at a constant rate and stops on the `\p` control
## code, which is explicit in the text and which the caller pages on. Porting a
## pause model in order to switch it off would be carrying a convention we
## actively do not want.
##
## Also dropped: `speeds` and `inline_mutations` (compiler-produced, and there is
## no compiler here), `@tool`, and the addon-relative icon.
##
## PORTED VERBATIM, deliberately — the two details worth not rediscovering:
##   * `_type_next`'s catch-up recursion (:150-154), which types several
##     characters in one frame when a frame ran long. Without it, typing speed
##     silently becomes frame-rate dependent.
##   * the `visible_characters >= parsed_text.length()` guard (:196), which
##     exists because visible_characters can exceed the text after a
##     translation event shortens it mid-type.

## Emitted per character. For a future text-blip SFX (this project has no audio).
signal spoke(letter: String, letter_index: int)
signal started_typing()
signal finished_typing()
signal skipped_typing()

## Seconds per character. The reference's own rate is frame-locked; this is a
## feel value, tuned by eye, per this project's convention for such constants.
@export var seconds_per_step: float = 0.02

var _is_typing := false
var _waiting_seconds := 0.0


## True while characters are still being revealed.
var is_typing: bool:
	get:
		return _is_typing


func _process(delta: float) -> void:
	if not _is_typing:
		return
	if visible_ratio < 1.0:
		if _waiting_seconds > 0.0:
			_waiting_seconds -= delta
		if _waiting_seconds <= 0.0:
			_type_next(delta, _waiting_seconds)
	else:
		_finish()


## Begin typing `new_text`. Unlike the original, the text is a PARAMETER rather
## than read off a line object — that indirection existed to carry compiler
## output we do not have.
func type_out(new_text: String) -> void:
	text = new_text
	visible_characters = 0
	visible_ratio = 0.0
	_waiting_seconds = 0.0
	_is_typing = true
	started_typing.emit()
	if get_total_character_count() == 0 or seconds_per_step <= 0.0:
		visible_characters = get_total_character_count()
		_finish()


## Reveal everything immediately — the player pressed the button mid-type.
func skip_typing() -> void:
	if not _is_typing:
		return
	visible_characters = get_total_character_count()
	skipped_typing.emit()
	_finish()


func _finish() -> void:
	if not _is_typing:
		return
	_is_typing = false
	finished_typing.emit()


## Ported from the original's `_type_next` (:129-154).
##
## The recursion at the tail is the catch-up: if the time this character costs
## still fits inside the frame we are already in, type the next one now instead
## of waiting a frame. Dropping it would make the type rate depend on frame rate.
func _type_next(delta: float, seconds_needed: float) -> void:
	if visible_characters >= get_total_character_count():
		return
	visible_characters += 1
	var parsed := get_parsed_text()
	# Guard ported verbatim (:196): visible_characters can exceed the parsed text
	# if a translation event shortens it while typing.
	if visible_characters <= parsed.length():
		spoke.emit(parsed[visible_characters - 1], visible_characters - 1)
	seconds_needed += seconds_per_step
	if seconds_needed > delta:
		_waiting_seconds += seconds_needed
	else:
		_type_next(delta, seconds_needed)
