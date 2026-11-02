extends Control
# A check mark that flies from the pointer to its spot on the notebook exploit
# button and stays there. One is added per redaction, so together they keep a
# tally of how many times the player has redacted.

const TEXTURE := preload("res://art/ui/checkmark.png")

@export var size_px := 60.0
@export var travel_time := 0.4

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

# Call after the node is in the tree and positioned at the pointer. target is
# where it settles, in the same coordinates as position.
func land(target: Vector2) -> void:
	scale = Vector2.ONE * 1.4
	var t := create_tween().set_parallel(true)
	t.tween_property(self, "position", target, travel_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "scale", Vector2.ONE, travel_time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _draw() -> void:
	draw_texture_rect(TEXTURE, Rect2(Vector2(-size_px, -size_px) * 0.5, Vector2(size_px, size_px)), false)
