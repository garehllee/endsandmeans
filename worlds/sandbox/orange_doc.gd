extends Interactable

@export var window_scene: PackedScene

func _on_interact() -> void:
	Game.set_flag(Flag.TASK_RECEIVED)
	Game.open_window_requested.emit(window_scene, Vector2(100, -500))
