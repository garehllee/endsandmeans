extends Control
# A check mark that sticks to the notebook exploit button exactly where it was
# clicked. One is added per redaction, so together they keep a tally of how many
# times the player has redacted.

const TEXTURE := preload("res://art/ui/checkmark.png")

@export var size_px := 60.0
@export var pop_time := 0.2

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

# Call after the node is in the tree and positioned where it should stay.
func stick() -> void:
	scale = Vector2.ONE * 1.4
	create_tween().tween_property(self, "scale", Vector2.ONE, pop_time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _draw() -> void:
	draw_texture_rect(TEXTURE, Rect2(Vector2(-size_px, -size_px) * 0.5, Vector2(size_px, size_px)), false)
