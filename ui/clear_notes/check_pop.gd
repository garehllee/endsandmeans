extends Control
# A small check mark that floats up out of the pointer and fades away.

const TEXTURE := preload("res://art/ui/checkmark.png")

@export var size_px := 20.0
@export var rise := 60.0
@export var duration := 0.9

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 100

# Call after the node is in the tree and positioned.
func pop() -> void:
	var t := create_tween().set_parallel(true)
	t.tween_property(self, "position:y", position.y - rise, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "modulate:a", 0.0, duration * 0.6).set_delay(duration * 0.4)
	t.finished.connect(queue_free)

func _draw() -> void:
	draw_texture_rect(TEXTURE, Rect2(Vector2(-size_px, -size_px) * 0.5, Vector2(size_px, size_px)), false)
