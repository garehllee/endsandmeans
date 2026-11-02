extends Control
# The check mark that bursts out of the pointer when the notebook exploit is
# clicked: it pops big, wobbles, springs up and drifts away while sparks fly out.

const TEXTURE := preload("res://art/ui/checkmark.png")

@export var size_px := 140.0
@export var rise := 190.0
@export var spark_count := 12
@export var spark_colors: Array[Color] = [Color("#2ecc40"), Color.WHITE, Color("#ffe14d")]

# 0 to 1 over the burst; drives the sparks.
var _burst := 0.0:
	set(value):
		_burst = value
		queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 100

# Call after the node is in the tree and positioned.
func pop() -> void:
	scale = Vector2.ZERO
	rotation = deg_to_rad(randf_range(18.0, 35.0)) * (1.0 if randf() < 0.5 else -1.0)
	var drift := randf_range(-50.0, 50.0)
	var start := position
	var t := create_tween().set_parallel(true)
	# Overshoot big, then squash back to normal size.
	t.tween_property(self, "scale", Vector2.ONE * 1.6, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "scale", Vector2.ONE, 0.2).set_delay(0.16).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	# Wobble upright like a spring.
	t.tween_property(self, "rotation", 0.0, 0.8).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	# Jump out fast, then ease away.
	t.tween_property(self, "position:y", start.y - rise, 1.0).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "position:x", start.x + drift, 1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "_burst", 1.0, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "modulate:a", 0.0, 0.35).set_delay(0.75)
	t.finished.connect(queue_free)

func _draw() -> void:
	if _burst > 0.0 and _burst < 1.0:
		for i in spark_count:
			var angle := TAU * i / spark_count + 0.3
			var radius := size_px * 0.5 + 16.0 + 130.0 * _burst
			var c: Color = spark_colors[i % spark_colors.size()]
			c.a = 1.0 - _burst
			draw_circle(Vector2.from_angle(angle) * radius, 3.0 + 9.0 * (1.0 - _burst), c)
	draw_texture_rect(TEXTURE, Rect2(Vector2(-size_px, -size_px) * 0.5, Vector2(size_px, size_px)), false)
