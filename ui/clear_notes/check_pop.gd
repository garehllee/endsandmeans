extends Control
# A green check mark that pops out of the pointer, floats up and fades away.
# Drawn with lines (not an emoji) so it looks the same in web builds, which
# have no system emoji font.

@export var color := Color("#2ecc40")
@export var outline := Color.WHITE
@export var rise := 120.0
@export var thickness := 12.0

const POINTS := [Vector2(-24, 2), Vector2(-8, 20), Vector2(26, -20)]

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 100

# Call after the node is in the tree and positioned.
func pop() -> void:
	scale = Vector2.ZERO
	var t := create_tween().set_parallel(true)
	t.tween_property(self, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "position:y", position.y - rise, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "modulate:a", 0.0, 0.3).set_delay(0.5)
	t.finished.connect(queue_free)

func _draw() -> void:
	_stroke(outline, thickness + 8.0)
	_stroke(color, thickness)

func _stroke(c: Color, w: float) -> void:
	draw_polyline(PackedVector2Array(POINTS), c, w)
	for p in POINTS:
		draw_circle(p, w * 0.5, c)
