extends Minigame
class_name CopyGame
# Keep the spinning file in the air by bouncing it off the character's head and
# steer it into the door on the right. The door opens as the file gets close;
# touching the doorway wins, and the file slides in. If the file hits the floor
# it drops back in from the top-left and you try again.

enum State { WAITING, PLAYING, DROPPED, ENTERING, DONE }

const CLIP_SHADER := preload("res://shaders/clip_rect.gdshader")
const PICTURE := Vector2(1600, 1512)       # the size the art was drawn at

var config: CopyConfig
var running := false

var _arena := Rect2()
var _player: Node2D
var _layer := Rect2()                      # where the picture sits, in room units
var _s := 1.0                              # room units per picture unit
var _built := false

var _state := State.WAITING
var _pos := Vector2.ZERO                   # the file
var _vel := Vector2.ZERO
var _spin := 0.0
var _timer := 0.0
var _prev_player := Vector2.INF
var _player_vel := Vector2.ZERO
var _door_is_open := false

var _clip_mat: ShaderMaterial
var _door: Sprite2D
var _file: Sprite2D
var _instr: Sprite2D

func setup(arena: Rect2, player: Node2D, _start_pos: Vector2) -> void:
	_arena = arena
	_player = player      # the character stays where it was when the challenge was accepted

func prepare(cfg: MinigameConfig) -> void:
	config = cfg as CopyConfig
	if config == null:
		push_error("CopyGame needs a CopyConfig")
		return
	_clip_mat = ShaderMaterial.new()
	_clip_mat.shader = CLIP_SHADER
	_door = _make_sprite(0)
	_door.texture = config.door_closed
	_door.centered = true
	_file = _make_sprite(1)                      # above the character
	_file.centered = true
	_file.texture = config.file_sheet
	_file.hframes = config.file_sheet_columns
	_file.vframes = config.file_sheet_rows
	_file.visible = false
	_instr = _make_sprite(20)
	_instr.texture = config.instructions
	_built = true
	set_expand(_arena, 0.0)

func _make_sprite(z: int) -> Sprite2D:
	var sp := Sprite2D.new()
	sp.z_index = z
	sp.material = _clip_mat
	add_child(sp)
	return sp

# The door and instructions grow out of the button along with it.
func set_expand(rect: Rect2, t: float) -> void:
	if not _built:
		return
	_s = rect.size.x / PICTURE.x
	var size := PICTURE * _s
	_layer = Rect2(rect.position.x, rect.get_center().y - size.y * 0.5, size.x, size.y)

	var gt := get_global_transform()
	var tl := gt * rect.position
	var br := gt * rect.end
	_clip_mat.set_shader_parameter("clip_rect", Vector4(tl.x, tl.y, br.x - tl.x, br.y - tl.y))

	var a := clampf(t * 2.0, 0.0, 1.0)
	_door.modulate.a = a
	_instr.modulate.a = a
	_door.position = _to_room(config.door_position)
	_door.scale = Vector2.ONE * _s
	_instr.centered = false
	_instr.position = _layer.position
	_instr.scale = Vector2.ONE * (_layer.size.x / maxf(_instr.texture.get_width(), 1.0))
	_update_file_visual()
	queue_redraw()

func start(cfg: MinigameConfig) -> void:
	if not _built:
		prepare(cfg)
	if not _built:
		finished.emit(true)
		return
	set_expand(_arena, 1.0)
	# The character stays put; just keep it inside the arena.
	var pr := config.player_radius
	_player.position = Vector2(
		clampf(_player.position.x, _arena.position.x + pr, _arena.end.x - pr),
		clampf(_player.position.y, _arena.position.y + pr, _arena.end.y - pr))
	_prev_player = _player.position
	_spawn_file()
	_state = State.WAITING
	_timer = 0.6                       # a beat before the first drop
	running = true
	Game.input_locked = false

func stop() -> void:
	running = false

func _to_room(p: Vector2) -> Vector2:
	return _layer.position + p * _s

# ---------------------------------------------------------------- per frame

func _process(delta: float) -> void:
	if not _built or not running:
		return
	delta = minf(delta, 1.0 / 30.0)
	var pr := config.player_radius
	_player.position = Vector2(
		clampf(_player.position.x, _arena.position.x + pr, _arena.end.x - pr),
		clampf(_player.position.y, _arena.position.y + pr, _arena.end.y - pr))
	if delta > 0.0:
		var v := (_player.position - _prev_player) / delta
		_player_vel = _player_vel.lerp(v, 0.5)        # smooth, so one odd frame doesn't launch the file
	_prev_player = _player.position

	_spin += delta * config.file_fps
	match _state:
		State.WAITING:
			_timer -= delta
			if _timer <= 0.0:
				_state = State.PLAYING
		State.PLAYING:
			var steps := 3
			for _i in steps:
				_step(delta / steps)
				if _state != State.PLAYING:
					break
			_update_door()
		State.DROPPED:
			_timer -= delta
			if _timer <= 0.0:
				_spawn_file()
				_state = State.WAITING
				_timer = 0.3
		State.ENTERING, State.DONE:
			pass
	_update_file_visual()
	if config.debug_draw:
		queue_redraw()

func _spawn_file() -> void:
	_pos = Vector2(_layer.position.x + config.file_spawn_x * _s, _arena.position.y - config.file_radius * _s * 2.0)
	_vel = Vector2.ZERO
	_file.modulate.a = 1.0
	_file.scale = Vector2.ONE * _file_scale()
	_file.visible = true

func _file_scale() -> float:
	var cell_w := config.file_sheet.get_width() / float(config.file_sheet_columns)
	return config.file_width * _s / cell_w

func _step(dt: float) -> void:
	var r := config.file_radius * _s
	_vel.y += config.gravity * _s * dt
	_vel.x *= maxf(1.0 - config.side_drag * dt, 0.0)
	_pos += _vel * dt

	# The head: bounce off it like a ball.
	var head := _player.position + config.head_offset * _s
	var hr := config.head_radius * _s
	var d := _pos - head
	var dist := d.length()
	if dist < r + hr and dist > 0.001:
		var n := d / dist
		_pos = head + n * (r + hr)
		var rel := _vel - _player_vel
		var vn := rel.dot(n)
		if vn < 0.0:
			var old_x := _vel.x
			rel -= (1.0 + config.bounce) * vn * n
			_vel = rel + _player_vel
			_vel.x = lerpf(old_x, _vel.x, config.side_response)    # vertical bounce stays; sideways is tamed
			_vel.x += n.x * config.header_push * _s          # off-center hits send it sideways
			if n.y < -0.25:
				_vel.y = minf(_vel.y, -config.min_bounce_speed * _s)

	# Side walls and the ceiling keep it in play.
	if _pos.x < _arena.position.x + r:
		_pos.x = _arena.position.x + r
		_vel.x = absf(_vel.x) * config.wall_bounce
	elif _pos.x > _arena.end.x - r:
		_pos.x = _arena.end.x - r
		_vel.x = -absf(_vel.x) * config.wall_bounce
	if _pos.y < _arena.position.y + r and _vel.y < 0.0 and _pos.y > _arena.position.y:
		_pos.y = _arena.position.y + r
		_vel.y = absf(_vel.y) * config.wall_bounce

	# The floor: dropped.
	if _pos.y > _arena.end.y - r * 0.5:
		_dropped()
		return

	# The doorway: won.
	if _touches_door(r):
		_enter_door()

func _door_rect() -> Rect2:
	return Rect2(_to_room(config.door_body.position), config.door_body.size * _s)

func _touches_door(r: float) -> bool:
	var rect := _door_rect()
	var closest := Vector2(clampf(_pos.x, rect.position.x, rect.end.x), clampf(_pos.y, rect.position.y, rect.end.y))
	return _pos.distance_to(closest) < r

func _update_door() -> void:
	var open := _pos.distance_to(_to_room(config.door_position)) < config.door_open_radius * _s
	_set_door(open)

func _set_door(open: bool) -> void:
	if open == _door_is_open:
		return
	_door_is_open = open
	_door.texture = config.door_open if open else config.door_closed

func _dropped() -> void:
	_state = State.DROPPED
	_timer = config.respawn_delay
	_set_door(false)
	create_tween().tween_property(_file, "modulate:a", 0.0, 0.25)
	Game.say_random("copy_drop")

# The file slides into the doorway, shrinking and fading, then the door closes.
func _enter_door() -> void:
	_state = State.ENTERING
	Game.input_locked = true
	_set_door(true)
	var target := _to_room(config.door_body.get_center())
	var t := create_tween().set_parallel(true)
	t.tween_property(self, "_pos", target, config.enter_time).set_trans(Tween.TRANS_SINE)
	t.tween_property(_file, "scale", _file.scale * 0.35, config.enter_time)
	t.tween_property(_file, "modulate:a", 0.0, config.enter_time * 0.5).set_delay(config.enter_time * 0.5)
	await t.finished
	await get_tree().create_timer(0.15).timeout
	_set_door(false)
	await get_tree().create_timer(0.45).timeout
	_state = State.DONE
	if running:
		running = false
		finished.emit(true)

func _update_file_visual() -> void:
	if _file == null or not _built:
		return
	_file.position = _pos
	_file.frame = int(_spin) % config.file_frames

func _draw() -> void:
	if not _built:
		return
	if config.debug_draw and running:
		draw_circle(_pos, config.file_radius * _s, Color(1, 0, 0, 0.35))
		draw_circle(_player.position + config.head_offset * _s, config.head_radius * _s, Color(0, 0, 1, 0.35))
		draw_rect(_door_rect(), Color(0, 1, 0, 0.3))
