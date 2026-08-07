extends Control
class_name OutlineLabel

## A fixed-content pixel-font label with a real visible stroke.
##
## Godot's `font_outline_color`/`outline_size` theme properties do not
## render for BitmapFont-loaded fonts (no SDF data behind them --
## confirmed empirically: a bright red outline_size=6 produced zero
## visible pixels against this project's `.fnt` fonts). The stroke is
## faked the way pixel-art UIs conventionally do it: four small-offset
## copies of the text, in the stroke color, drawn behind a foreground
## copy in the real font color.

@onready var _fg: Label = $Fg
@onready var _shadow_up: Label = $ShadowUp
@onready var _shadow_down: Label = $ShadowDown
@onready var _shadow_left: Label = $ShadowLeft
@onready var _shadow_right: Label = $ShadowRight

var text: String = "":
	set(value):
		text = value
		_apply_text()


func _ready() -> void:
	_apply_text()


func _apply_text() -> void:
	if _fg == null:
		return
	_fg.text = text
	_shadow_up.text = text
	_shadow_down.text = text
	_shadow_left.text = text
	_shadow_right.text = text
