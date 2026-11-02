extends DesktopWindow
class_name WorldWindow
# Base for any window that shows a world. It listens for Game.world_opened /
# Game.world_closed and shows or hides itself when its world_id matches.

@export var world_id := ""
@export var window_size := Vector2(1000, 1040)
@export var keep_open_when_closed := false   # library: true, analysis: false

func _ready() -> void:
	custom_minimum_size = window_size
	size = window_size
	super()
	visible = false
	Game.world_opened.connect(func(id: String, params: Dictionary): if id == world_id: _show(params))
	Game.world_closed.connect(func(id: String, result: Dictionary): if id == world_id: _hide(result))

func _show(_params: Dictionary) -> void:
	size = window_size
	if visible:
		bring_to_front()
		return
	visible = true
	modulate.a = 0.0
	bring_to_front()
	create_tween().tween_property(self, "modulate:a", 1.0, 0.3)

func _hide(_result: Dictionary) -> void:
	if keep_open_when_closed:
		get_parent().move_child(self, 0)
	else:
		var t := create_tween()
		t.tween_property(self, "modulate:a", 0.0, 0.3)
		t.tween_callback(func(): if Game.active_world != world_id: visible = false)
