extends Panel
# Script attached to "window_stroke"

@export var hover_y_percentage: float = 0.2
@export var tween_duration: float = 0.5

var default_height: float
var hover_rect: Rect2
var is_open_state := false   # true = compressed
var current_tween: Tween

func _ready() -> void:
	# Wait one frame so layout/anchors have settled
	await get_tree().process_frame
	default_height = size.y
	hover_rect = Rect2(global_position, Vector2(size.x, default_height))

	var color_rect := get_node_or_null("window2") as Control
	if color_rect:
		color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		color_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	else:
		push_error("'window2' ColorRect not found under window_stroke!")
	mouse_default_cursor_shape = Control.CURSOR_MOVE

const WINDOW_COOLDOWN := 5
var last_window_open = -999

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		# Test against the ORIGINAL rect so shrinking doesn't cause flicker
		var inside := hover_rect.has_point(get_global_mouse_position())
		if inside != is_open_state:
			if Game.elapsed - last_window_open > WINDOW_COOLDOWN:
				Game.say_random("window_hover")
				last_window_open = Game.elapsed
			is_open_state = inside
			animate_height(default_height * hover_y_percentage if inside else default_height)

func animate_height(target_y: float) -> void:
	if current_tween and current_tween.is_valid():
		current_tween.kill()
	current_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	current_tween.tween_property(self, "size:y", target_y, tween_duration)
