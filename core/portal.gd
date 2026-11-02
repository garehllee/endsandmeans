extends Interactable
class_name Portal
# A door the player walks into. With a target_world it opens that world and
# brings the player back out when it closes. With a blank target_world it
# closes the current world instead (an exit door).

@export var target_world := ""               # blank = leave the current world
@export var open_texture: Texture2D          # optional "door open" art
@export var enter_offset := Vector2(0, -20)  # where the character walks to, relative to the door
@export var exit_offset := Vector2(0, 90)    # where they reappear when they return
@export var walk_time := 0.7

var _closed_texture: Texture2D
var _closed_scale: Vector2
var _player: Node2D
var _start_scale: Vector2

func _ready() -> void:
	super()
	_closed_texture = visual.texture
	_closed_scale = visual.scale
	Game.world_closed.connect(_on_world_closed)

func _on_interact() -> void:
	_player = Game.active_player
	if _player == null or Game.input_locked:
		return
	Game.input_locked = true
	Game.is_moving = false
	_start_scale = _player.scale

	_set_door_open(true)
	await get_tree().create_timer(0.3).timeout

	# Walk into the doorway, shrinking and fading.
	_player.current_dir = "up"
	_player.play_anim(1)
	var t := create_tween().set_parallel(true)
	t.tween_property(_player, "global_position", global_position + enter_offset, walk_time)
	t.tween_property(_player, "scale", _start_scale * 0.7, walk_time)
	t.tween_property(_player, "modulate:a", 0.0, walk_time * 0.5).set_delay(walk_time * 0.5)
	await t.finished

	_player.play_anim(0)
	if target_world == "":
		# Reset the character so it's ready for the next visit.
		_player.scale = _start_scale
		_player = null
		Game.close_world()
		_set_door_open(false)
	else:
		Game.open_world(target_world)
		await get_tree().create_timer(0.4).timeout
		_set_door_open(false)

# The character steps back out of the door when the world it entered closes.
func _on_world_closed(id: String, _result: Dictionary) -> void:
	if target_world == "" or id != target_world or _player == null:
		return
	_player.global_position = global_position + exit_offset
	_player.scale = _start_scale
	create_tween().tween_property(_player, "modulate:a", 1.0, 0.4)
	Game.input_locked = false
	_player = null

func _set_door_open(open: bool) -> void:
	if open_texture:
		visual.texture = open_texture if open else _closed_texture
	else:
		# No art yet: the door "swings" by squashing sideways.
		var target := _closed_scale.x * (0.25 if open else 1.0)
		create_tween().tween_property(visual, "scale:x", target, 0.3)
