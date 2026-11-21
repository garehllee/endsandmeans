extends Interactable

@export var window_scene: PackedScene

func _on_interact() -> void:
	Audio.play("inspect")
	Game.open_window_requested.emit(window_scene, Vector2(100, -300))
