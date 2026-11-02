extends DesktopWindow

const WINDOW_SIZE := Vector2(2000, 2040)

func _ready() -> void:
	custom_minimum_size = WINDOW_SIZE
	size = WINDOW_SIZE
	super()
	visible = false   # hidden only until the first time you open it
	Game.library_entered.connect(_show_window)
	Game.library_exited.connect(_send_to_back)

func _show_window() -> void:
	size = WINDOW_SIZE
	if visible:
		# Already open in the background: just bring it forward.
		bring_to_front()
		return
	visible = true
	modulate.a = 0.0
	bring_to_front()
	create_tween().tween_property(self, "modulate:a", 1.0, 0.3)

func _send_to_back() -> void:
	get_parent().move_child(self, 0)
