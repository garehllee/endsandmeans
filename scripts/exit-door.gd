extends Interactable

@export var open_texture: Texture2D          # optional "door open" art
@export var enter_offset := Vector2(0, -20)  # where the character walks to, relative to the door
@export var walk_time := 0.7

var _closed_texture: Texture2D
var _closed_scale: Vector2

func _ready() -> void:
	super()
	_closed_texture = visual.texture
	_closed_scale = visual.scale

func _on_interact() -> void:
	var p: Node2D = Game.active_player
	if p == null or Game.input_locked:
		return
	Game.input_locked = true
	Game.is_moving = false
	var start_scale := p.scale

	_set_door_open(true)
	await get_tree().create_timer(0.3).timeout

	# Walk into the doorway, shrinking and fading.
	p.current_dir = "up"
	p.play_anim(1)
	var t := create_tween().set_parallel(true)
	t.tween_property(p, "global_position", global_position + enter_offset, walk_time)
	t.tween_property(p, "scale", start_scale * 0.7, walk_time)
	t.tween_property(p, "modulate:a", 0.0, walk_time * 0.5).set_delay(walk_time * 0.5)
	await t.finished

	p.play_anim(0)
	# Reset the library character so it's ready for the next visit.
	p.scale = start_scale
	Game.exit_library()   # hides the window and brings the sandbox character back
	_set_door_open(false)

func _set_door_open(open: bool) -> void:
	if open_texture:
		visual.texture = open_texture if open else _closed_texture
	else:
		# No art yet: the door "swings" by squashing sideways.
		var target := _closed_scale.x * (0.25 if open else 1.0)
		create_tween().tween_property(visual, "scale:x", target, 0.3)
