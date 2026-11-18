extends Control

@onready var windows: Control = $Windows

func _ready() -> void:
	Game.open_window_requested.connect(open_window)
	var collapse := EndCollapse.new()
	windows.add_child(collapse)
	windows.move_child(collapse, 0)
	if not Game.started:
		add_child(preload("res://ui/landing/landing.gd").new())

func open_window(scene: PackedScene, pos: Vector2) -> Control:
	var w = scene.instantiate()
	windows.add_child(w)
	w.position = pos
	w.global_position = DesktopLayout.find_spot(w.size, w._clamp_to_viewport(w.global_position),
			DesktopLayout.occupied_rects(get_tree(), w), get_viewport_rect().size)
	return w
