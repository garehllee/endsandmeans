extends Control

@onready var windows: Control = $Windows

func _ready() -> void:
	Game.open_window_requested.connect(open_window)

func open_window(scene: PackedScene, pos: Vector2) -> Control:
	var w = scene.instantiate()
	windows.add_child(w)
	w.position = pos
	w.global_position = w._clamp_to_viewport(w.global_position)
	return w
