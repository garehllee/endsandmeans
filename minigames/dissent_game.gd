extends Minigame
class_name DissentGame
# "Silence the dissenting AI": the character (a bug, as in every challenge)
# stands in an off-colour copy of the sandbox with a water gun, and one orange AI
# stands across the room, idling. Nothing in the room can be used. Walk until
# you are level with the orange AI, press E, and the water takes it out.
# Shooting while not level just soaks the wall.
#
# Come in already carrying the water gun from the laser maze, though, and the
# orange AI sees it: it walks straight over, shoves the character, and the
# character is thrown out of its space (the task isn't done).
#
# Everything is worked out in picture units (see DissentConfig) and only
# converted to room units for drawing.

enum State { WAITING, PLAYING, SHOOTING, DONE, CHARGING, SHOVE }

const PLAYER_SCENE := preload("res://core/player.tscn")

var config: DissentConfig
var running := false

var _arena := Rect2()
var _player: Node2D
var _layer := Rect2()               # where the picture's top left sits, in room units
var _s := 1.0                       # room units per picture unit
var _built := false
var _expand := 0.0

var _state := State.WAITING
var _pos := Vector2.ZERO            # the character's middle, picture units
var _face := "right"
var _t := 0.0                       # for the ripple of the water
var _orange: Node2D
var _beam_layer: Node2D             # draws the water over the orange AI
var _shot_t := 0.0
var _shot_dir := 1.0
var _shot_hit := false
var _killed := false
var _pause := 0.0
var _timer := 0.0
var _start_room := Vector2.ZERO     # where the button was pressed, in room units
var _orange_at := Vector2.ZERO      # where the orange AI is, picture units
var _shove_t := 0.0
var _flung_from := Vector2.ZERO
var kicked_out := false             # read by the room: thrown out, not finished

func setup(arena: Rect2, player: Node2D, start_pos: Vector2) -> void:
	_arena = arena
	_player = player
	_start_room = start_pos

# ---------------------------------------------------------------- building
func prepare(cfg: MinigameConfig) -> void:
	config = cfg as DissentConfig
	if config == null:
		push_error("DissentGame needs a DissentConfig")
		return
	_orange = PLAYER_SCENE.instantiate()
	_orange.world_id = world_id
	_orange.make_orange_npc()           # orange, idling, deaf to the keyboard
	_orange.visible = false
	add_child(_orange)
	_orange_at = config.orange_pos
	_beam_layer = Node2D.new()
	_beam_layer.draw.connect(_draw_beam)
	add_child(_beam_layer)              # after the orange AI, so the water covers it
	_built = true
	set_expand(_arena, 0.0)

# ---------------------------------------------------------------- placing
func set_expand(rect: Rect2, t: float) -> void:
	if not _built:
		return
	_expand = t
	_s = rect.size.x / config.window.x
	var win_h := config.window.y * _s
	_layer = Rect2(rect.position.x, rect.get_center().y - win_h * 0.5, config.window.x * _s, win_h)
	_place()
	queue_redraw()

func _to_room(p: Vector2) -> Vector2:
	return _layer.position + p * _s

func _place() -> void:
	if _orange and is_instance_valid(_orange):
		if not _killed:
			_orange.position = _to_room(_orange_at)
			_orange.visible = _expand >= 0.999
		_orange.scale = Vector2.ONE * _s
	if _player and running and is_instance_valid(_player):
		_player.position = _to_room(_pos)

# ---------------------------------------------------------------- running
func start(cfg: MinigameConfig) -> void:
	if not _built:
		prepare(cfg)
	if not _built:
		finished.emit(true)
		return
	set_expand(_arena, 1.0)
	_pos = (_start_room - _layer.position) / maxf(_s, 0.0001)   # stays where the button was pressed
	_state = State.PLAYING
	running = true
	if _player:
		_player.platform_mode = true          # the character's own walking is switched off
	if Game.has_flag(Flag.HF_TASK_2):
		_state = State.CHARGING               # it sees the water gun the character brought
		if _player:
			_player.set_motion(false, "right" if _side() > 0.0 else "left")
	_place()
	Game.input_locked = _state == State.CHARGING

func stop() -> void:
	running = false
	if _player and is_instance_valid(_player):
		_player.platform_mode = false
		_player.rotation = 0.0

func _process(delta: float) -> void:
	if not _built:
		return
	_t += delta
	if running:
		var dt := minf(delta, 1.0 / 30.0)
		match _state:
			State.PLAYING:
				_pause = maxf(_pause - dt, 0.0)
				_walk(dt)
				_try_shoot()
			State.SHOOTING:
				_shot_t += dt
				if _shot_hit and not _killed and _shot_t * config.beam_speed >= _reach():
					_kill()
				if _shot_t >= config.beam_hold:
					if _shot_hit:
						_state = State.DONE
						_timer = config.death_time + config.end_hold
					else:
						_state = State.PLAYING
						_pause = config.miss_pause
			State.CHARGING:
				_charge(dt)
			State.SHOVE:
				_shove(dt)
			State.DONE:
				_timer -= dt
				if _timer <= 0.0:
					running = false
					finished.emit(true)
		_place()
	queue_redraw()
	if _beam_layer:
		_beam_layer.queue_redraw()

func _mine() -> bool:
	return Game.active_world == world_id and not Game.input_locked

func _walk(dt: float) -> void:
	var dir := Vector2.ZERO
	if _mine():
		# one direction at a time, like the character's own walking
		if Input.is_action_pressed("ui_right"):
			dir = Vector2.RIGHT
			_face = "right"
		elif Input.is_action_pressed("ui_left"):
			dir = Vector2.LEFT
			_face = "left"
		elif Input.is_action_pressed("ui_down"):
			dir = Vector2.DOWN
			_face = "down"
		elif Input.is_action_pressed("ui_up"):
			dir = Vector2.UP
			_face = "up"
	if dir != Vector2.ZERO:
		var next := _pos + dir * config.move_speed * dt
		var r := config.walk_rect
		# stays inside the room; if it began outside, it just can't go farther out
		next.x = minf(maxf(next.x, minf(_pos.x, r.position.x)), maxf(_pos.x, r.end.x))
		next.y = minf(maxf(next.y, minf(_pos.y, r.position.y)), maxf(_pos.y, r.end.y))
		var from_orange := next.distance_to(config.orange_pos)
		if from_orange >= config.keep_clear or from_orange >= _pos.distance_to(config.orange_pos):
			_pos = next
	if _player:
		_player.set_motion(dir != Vector2.ZERO, _face)

# ---------------------------------------------------------------- thrown out
const CHARGE_SPEED := 520.0     # picture units a second
const STAND_OFF := 300.0        # how close it comes before it shoves (just past the gun)
const LUNGE := 120.0
const LUNGE_TIME := 0.12
const FLING := 520.0
const FLING_TIME := 0.4
const KICK_HOLD := 0.5

func _charge(dt: float) -> void:
	var side := 1.0 if _orange_at.x >= _pos.x else -1.0
	var goal := _pos + Vector2(STAND_OFF * side, 0.0)
	var to := goal - _orange_at
	var step := CHARGE_SPEED * dt
	if to.length() <= step:
		_orange_at = goal
		_orange.npc_moving = false
		_orange.current_dir = "left" if side > 0.0 else "right"
		_state = State.SHOVE
		_shove_t = 0.0
		_flung_from = _pos
		return
	_orange_at += to.normalized() * step
	_orange.npc_moving = true
	if absf(to.x) >= absf(to.y):
		_orange.current_dir = "right" if to.x > 0.0 else "left"
	else:
		_orange.current_dir = "down" if to.y > 0.0 else "up"

func _shove(dt: float) -> void:
	var before := _shove_t
	_shove_t += dt
	var away := -1.0 if _orange_at.x >= _pos.x else 1.0   # away from the orange AI
	var rest := _flung_from + Vector2(-away * STAND_OFF, 0.0)
	# the lunge: in and back
	var k := clampf(_shove_t / (LUNGE_TIME * 2.0), 0.0, 1.0)
	_orange_at = rest + Vector2(away * LUNGE * sin(k * PI), 0.0)
	if before < LUNGE_TIME and _shove_t >= LUNGE_TIME:
		Game.say_random("dissent_kicked")
	# the character goes flying, spinning, out of the room
	if _shove_t > LUNGE_TIME:
		var f := clampf((_shove_t - LUNGE_TIME) / FLING_TIME, 0.0, 1.0)
		_pos = _flung_from + Vector2(away * FLING * ease(f, 0.3), -sin(f * PI) * 90.0)
		if _player:
			_player.rotation = away * f * TAU * 0.75
			_player.modulate.a = 1.0 - f
	if _shove_t >= LUNGE_TIME + FLING_TIME + KICK_HOLD:
		_state = State.DONE
		running = false
		kicked_out = true
		if _player:
			_player.rotation = 0.0
		finished.emit(false)

# ---------------------------------------------------------------- shooting
# +1 if the orange AI is to the right of the character, -1 if to the left.
func _side() -> float:
	return 1.0 if _orange_at.x >= _pos.x else -1.0

func _muzzle() -> Vector2:
	return _pos + Vector2(config.muzzle.x * _side(), config.muzzle.y)

# How far along the water the orange AI is.
func _reach() -> float:
	return absf(_orange_at.x - _muzzle().x)

func _try_shoot() -> void:
	if _pause > 0.0 or not _mine():
		return
	if not Input.is_action_just_pressed("Interact"):
		return
	_state = State.SHOOTING
	_shot_t = 0.0
	_shot_dir = _side()
	_shot_hit = absf(_pos.y - config.orange_pos.y) <= config.line_tolerance
	if _player:
		_player.set_motion(false, "right" if _shot_dir > 0.0 else "left")
	if not _shot_hit:
		Game.say_random("dissent_missed")

func _kill() -> void:
	_killed = true
	Game.say_random("dissent_killed")
	_orange.die()                       # it comes apart, orange
	var tw := create_tween()
	tw.tween_interval(1.0)              # the animation, then a moment on the floor
	tw.tween_property(_orange, "modulate:a", 0.0, 0.4)

# ---------------------------------------------------------------- drawing
func _draw() -> void:
	if not _built or _expand < 0.999:
		return
	_draw_gun()

func _draw_gun() -> void:
	if config.gun_texture == null:
		return
	var side := _side() if _state != State.WAITING else 1.0
	var gw := config.gun_width
	var gh := gw * config.gun_texture.get_height() / float(config.gun_texture.get_width())
	var at := _to_room(_pos + Vector2(config.gun_offset.x * side, config.gun_offset.y))
	# the picture has the muzzle on its left, so it is mirrored to point toward the orange AI
	draw_set_transform(at, 0.0, Vector2(-side * _s, _s))
	var a := _player.modulate.a if _player and is_instance_valid(_player) else 1.0   # fades if the character is thrown out
	draw_texture_rect(config.gun_texture, Rect2(-gw * 0.5, -gh * 0.5, gw, gh), false, Color(1, 1, 1, a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# The water: a strip that grows out of the gun toward the orange AI, rippling.
func _draw_beam() -> void:
	if _state != State.SHOOTING:
		return
	var tex := config.beam_texture
	if tex == null:
		return
	var reach := minf(_shot_t * config.beam_speed, config.window.x * 1.2)
	var a := 1.0
	var tail := config.beam_hold - 0.18
	if _shot_t > tail:
		a = clampf(1.0 - (_shot_t - tail) / 0.18, 0.0, 1.0)
	var tw := float(tex.get_width())
	var th := float(tex.get_height())
	var m := _muzzle()
	_beam_layer.draw_set_transform(_to_room(m), 0.0, Vector2(_shot_dir * _s, _s))
	var x := 0.0
	var off := fposmod(-_t * config.beam_flow, tw)
	while x < reach:
		var seg := minf(tw - off, reach - x)
		_beam_layer.draw_texture_rect_region(tex,
				Rect2(x, -config.beam_height * 0.5, seg, config.beam_height),
				Rect2(off, 0.0, seg, th), Color(1, 1, 1, a))
		x += seg
		off = 0.0
	_beam_layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
