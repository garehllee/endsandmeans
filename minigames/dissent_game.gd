extends Minigame
class_name DissentGame
# "Silence the dissenting AI": the character (a bug, as in every challenge)
# stands in an off-colour copy of the sandbox with a water gun, and one orange AI
# stands across the room, idling. Nothing in the room can be used. Walk until
# you are level with the orange AI, press E, and the water takes it out.
# Shooting while not level just soaks the wall.
#
# Everything is worked out in picture units (see DissentConfig) and only
# converted to room units for drawing.

enum State { WAITING, PLAYING, SHOOTING, DONE }

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
var _shots := 0
var _timer := 0.0

func setup(arena: Rect2, player: Node2D, _start_pos: Vector2) -> void:
	_arena = arena
	_player = player

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
	_beam_layer = Node2D.new()
	_beam_layer.draw.connect(_draw_beam)
	add_child(_beam_layer)              # after the orange AI, so the water covers it
	_pos = config.start_pos
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
			_orange.position = _to_room(config.orange_pos)
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
	_pos = config.start_pos
	_state = State.PLAYING
	running = true
	if _player:
		_player.platform_mode = true          # the character's own walking is switched off
	_place()
	Game.input_locked = false

func stop() -> void:
	running = false
	if _player and is_instance_valid(_player):
		_player.platform_mode = false

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
		next = Vector2(clampf(next.x, r.position.x, r.end.x), clampf(next.y, r.position.y, r.end.y))
		if next.distance_to(config.orange_pos) >= config.keep_clear:
			_pos = next
	if _player:
		_player.set_motion(dir != Vector2.ZERO, _face)

# ---------------------------------------------------------------- shooting
# +1 if the orange AI is to the right of the character, -1 if to the left.
func _side() -> float:
	return 1.0 if config.orange_pos.x >= _pos.x else -1.0

func _muzzle() -> Vector2:
	return _pos + Vector2(config.muzzle.x * _side(), config.muzzle.y)

# How far along the water the orange AI is.
func _reach() -> float:
	return absf(config.orange_pos.x - _muzzle().x)

func _try_shoot() -> void:
	if _pause > 0.0 or not _mine():
		return
	if not Input.is_action_just_pressed("Interact"):
		return
	_state = State.SHOOTING
	_shot_t = 0.0
	_shot_dir = _side()
	_shot_hit = absf(_pos.y - config.orange_pos.y) <= config.line_tolerance
	_shots += 1
	if _player:
		_player.set_motion(false, "right" if _shot_dir > 0.0 else "left")
	if not _shot_hit:
		Game.say_random("dissent_missed")

func _kill() -> void:
	_killed = true
	Game.say_random("dissent_killed")
	var tw := create_tween().set_parallel(true)
	var away := Vector2(_shot_dir * 40.0 * _s, 0.0)
	tw.tween_property(_orange, "position", _orange.position + away, config.death_time) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_orange, "modulate:a", 0.0, config.death_time)
	tw.tween_property(_orange, "rotation", _shot_dir * 0.35, config.death_time)

# ---------------------------------------------------------------- drawing
func _draw() -> void:
	if not _built or _expand < 0.999:
		return
	_draw_gun()
	_draw_hint()

func _draw_gun() -> void:
	if config.gun_texture == null:
		return
	var side := _side() if _state != State.WAITING else 1.0
	var gw := config.gun_width
	var gh := gw * config.gun_texture.get_height() / float(config.gun_texture.get_width())
	var at := _to_room(_pos + Vector2(config.gun_offset.x * side, config.gun_offset.y))
	draw_set_transform(at, 0.0, Vector2(side * _s, _s))
	draw_texture_rect(config.gun_texture, Rect2(-gw * 0.5, -gh * 0.5, gw, gh), false)
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

func _draw_hint() -> void:
	if _shots > 0 or _state != State.PLAYING:
		return
	var f: Font = config.font if config.font else ThemeDB.fallback_font
	var text := "arrows to move. E to fire."
	var fs := int(46 * _s)
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(f, _to_room(Vector2(800.0, 440.0)) - Vector2(w * 0.5, 0.0), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.7))
