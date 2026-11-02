# minigames/minigame.gd
extends Node2D
class_name Minigame
# Base for the games that run inside a choice room's arena.

signal finished(success: bool)

# arena: the rectangle the game plays in. start_pos: where the button was pressed.
func setup(_arena: Rect2, _player: Node2D, _start_pos: Vector2) -> void:
	pass

func start(_config: MinigameConfig) -> void:
	pass

func stop() -> void:
	pass
