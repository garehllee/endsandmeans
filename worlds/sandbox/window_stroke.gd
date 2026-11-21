extends Panel
# The window in the first room. It opens by itself when the character comes
# close, and shuts again when they walk away.

@export var open_share: float = 0.2     # how much of its height is left when it's open
@export var tween_duration: float = 0.5
@export var open_range := 260.0         # how close the character has to be (world units, from the window's edge)

var default_height: float
var window_rect: Rect2
var is_open_state := false   # true = compressed
var current_tween: Tween
var _player: Node2D

func _ready() -> void:
	# Wait one frame so layout/anchors have settled
	await get_tree().process_frame
	default_height = size.y
	window_rect = Rect2(global_position, Vector2(size.x, default_height))

	var color_rect := get_node_or_null("window2") as Control
	if color_rect:
		color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		color_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	else:
		push_error("'window2' ColorRect not found under window_stroke!")

const WINDOW_COOLDOWN := 5
var last_window_open = -999

func _process(_delta: float) -> void:
	if default_height <= 0.0:
		return
	if _player == null or not is_instance_valid(_player):
		_player = _find_player()
		if _player == null:
			return
	# measured from the window's ORIGINAL rect, so shrinking doesn't flicker
	var p := _player.global_position
	var nearest := Vector2(clampf(p.x, window_rect.position.x, window_rect.end.x),
			clampf(p.y, window_rect.position.y, window_rect.end.y))
	var near := p.distance_to(nearest) <= open_range
	if near != is_open_state:
		if near and Game.active_world == "sandbox":
			Audio.play("sandbox_window")
		if near and Game.elapsed - last_window_open > WINDOW_COOLDOWN:
			Game.say_random("window_hover")
			last_window_open = Game.elapsed
		is_open_state = near
		animate_height(default_height * open_share if near else default_height)

# The character in this room (each world has its own).
func _find_player() -> Node2D:
	var room := get_parent()
	for n in get_tree().get_nodes_in_group("player"):
		if room.is_ancestor_of(n):
			return n
	return null

func animate_height(target_y: float) -> void:
	if current_tween and current_tween.is_valid():
		current_tween.kill()
	current_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	current_tween.tween_property(self, "size:y", target_y, tween_duration)
