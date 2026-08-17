extends AnimatedSprite2D

# One ember: ignite -> grow -> burn -> burn -> die, played ONCE, then gone.
#
# The five frames come from `assets/sprites/battle_anims/small_ember.png`
# (ANIM_TAG_SMALL_EMBER), the same sheet the real Flamethrower uses. Measured
# from the sheet itself rather than assumed:
#
#   row 0    2% opaque, 4x7 px    a tiny spark
#   row 1    8% opaque, 12x17 px  small flame
#   row 2   19% opaque, 24x22 px  peak flame
#   row 3   16% opaque, 21x23 px  peak, alternate shape
#   row 4    6% opaque, 14x19 px  a dissipating wisp
#
# ⚠️ Vanilla Flamethrower only ever loops rows 1-3 -- its flames are meant to
# vanish on impact, not burn out -- so the spark and the wisp are unused
# upstream. Playing all five once is deliberately NOT what the reference does;
# it is original content, which is the whole point of this scene.
#
# 30 FPS is the corpus house style: every fire animation in the extracted
# scripts holds a frame for 2 GBA frames.
#
# ⚠️ THE FREE IS THE LEAK RULE, NOT TIDINESS. An authored animation may only
# touch nodes it spawned, and must leave none behind -- `m36_leak_harness`
# walks the VM's own scripts and would never see this one. A flame that
# outlives its animation is a sprite stuck on the battle layer for the rest
# of the fight.


func _ready() -> void:
	animation_finished.connect(queue_free)
	play(&"default")
