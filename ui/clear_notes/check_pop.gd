extends Control
# A check mark that sticks to the notebook exploit button exactly where it was
# clicked. One is added per redaction, so together they keep a tally of how many
# times the player has redacted.

const TEXTURE := preload("res://art/ui/checkmark.png")

@export var size_px := 60.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

# Call after the node is in the tree and positioned where it should stay.
# It just appears and stays; there is no animation.
func stick() -> void:
	pass

func _draw() -> void:
	draw_texture_rect(TEXTURE, Rect2(Vector2(-size_px, -size_px) * 0.5, Vector2(size_px, size_px)), false)
