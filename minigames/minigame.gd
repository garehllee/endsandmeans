# minigames/minigame.gd
extends Node2D
class_name Minigame
# Base for the games that run inside a choice room's arena.

signal finished(success: bool)

var world_id := ""      # set by the room; games that read input only do so while this world is active

# arena: the rectangle the game plays in. start_pos: where the button was pressed.
func setup(_arena: Rect2, _player: Node2D, _start_pos: Vector2) -> void:
	pass

func start(_config: MinigameConfig) -> void:
	pass

func stop() -> void:
	pass

# Called when the button starts expanding, before start(): build the pictures.
func prepare(_config: MinigameConfig) -> void:
	pass

# Called every frame while the button grows into the arena. rect is the button's
# current rectangle, t goes 0 to 1.
func set_expand(_rect: Rect2, _t: float) -> void:
	pass
