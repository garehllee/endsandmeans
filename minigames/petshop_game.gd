extends Minigame
class_name PetShopGame
# "Virtual pet shop": mice wander a shop floor. Left alone they mostly sit and
# now and then scoot somewhere. When the character gets close they bolt, though
# once in a while (5% of the time they make up their mind) one walks up to the
# character instead. Touch a mouse and press E to adopt it. That mouse then
# follows the character everywhere (see autoload/pets.gd).
#
# The character walks the way it always does; this game only keeps it on the
# shop floor. Everything is worked out in picture units (see PetShopConfig) and
# only converted to room units for drawing.

enum State { WAITING, PLAYING, ADOPTING }

class Mouse:
	var index := 0
	var pos := Vector2.ZERO
	var dir := Vector2.ZERO
	var speed := 0.0
	var timer := 0.0
	var phase := 0.0
	var face_right := false
	var sprite: Sprite2D

var config: PetShopConfig
var running := false

var _arena := Rect2()
var _player: Node2D
var _layer := Rect2()               # where the picture's top left sits, in room units
var _s := 1.0                       # room units per picture unit
var _built := false
var _expand := 0.0
var _state := State.WAITING
var _mice: Array[Mouse] = []
var _touching: Mouse = null
var _prev := Vector2.ZERO           # where the character was last frame, in picture units
var _timer := 0.0
var _t := 0.0
var _hearts: Array[Dictionary] = []   # {pos, vel, age, life, size, sway, color}
var _heart_layer: Node2D              # draws the hearts over the mice

func setup(arena: Rect2, player: Node2D, _start_pos: Vector2) -> void:
	_arena = arena
	_player = player

# ---------------------------------------------------------------- building
func prepare(cfg: MinigameConfig) -> void:
	config = cfg as PetShopConfig
	if config == null or config.mice.is_empty():
		push_error("PetShopGame needs a PetShopConfig with mice")
		return
	for i in config.mouse_starts.size():
		var m := Mouse.new()
		m.index = i % config.mice.size()
		m.pos = config.mouse_starts[i]
		m.timer = randf_range(0.2, 1.2)
		m.phase = randf() * TAU
		m.face_right = randf() < 0.5
		m.sprite = Sprite2D.new()
		m.sprite.texture = config.mice[m.index]
		m.sprite.visible = false
		add_child(m.sprite)
		_mice.append(m)
	_heart_layer = Node2D.new()
	_heart_layer.draw.connect(_draw_hearts)
	add_child(_heart_layer)              # after the mice, so the hearts are on top of them
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

func _to_room(p: Vector2) -> Vector2:
	return _layer.position + p * _s

func _to_picture(p: Vector2) -> Vector2:
	return (p - _layer.position) / maxf(_s, 0.0001)

func _place() -> void:
	for m in _mice:
		if m.sprite == null or m.sprite == _adopted_sprite:
			continue
		var tex := m.sprite.texture
		var k := config.mouse_width / float(tex.get_width()) * _s
		var lift := 1.0
		if m == _touching:
			lift = 1.1 + 0.04 * sin(_t * 14.0)         # the one in reach swells a little
		m.sprite.scale = Vector2.ONE * k * lift
		m.sprite.flip_h = m.face_right                  # the pictures face left
		m.sprite.position = _to_room(m.pos)
		m.sprite.rotation = sin(_t * 14.0 + m.phase) * config.wiggle if m.speed > 0.0 else 0.0
		m.sprite.modulate = Color(1.25, 1.25, 1.25, 1.0) if m == _touching else Color.WHITE
		m.sprite.visible = _expand >= 0.999

# ---------------------------------------------------------------- running
func start(cfg: MinigameConfig) -> void:
	if not _built:
		prepare(cfg)
	if not _built:
		finished.emit(true)
		return
	set_expand(_arena, 1.0)
	_prev = _player_pos()                # the character stays where the button was pressed
	_state = State.PLAYING
	running = true
	Game.input_locked = false

func stop() -> void:
	running = false

func _process(delta: float) -> void:
	if not _built:
		return
	_t += delta
	if running:
		var dt := minf(delta, 1.0 / 30.0)
		var pp := _player_pos()
		if _state == State.PLAYING:
			_keep_player_on_floor()
			pp = _player_pos()
		for m in _mice:
			if m.sprite != _adopted_sprite:
				_update_mouse(m, pp, dt)
		if _state == State.PLAYING:
			_find_touching(pp)
			if _touching and Game.active_world == world_id and not Game.input_locked \
					and Input.is_action_just_pressed("Interact"):
				_adopt(_touching)
		elif _state == State.ADOPTING:
			_timer -= dt
			if _timer <= 0.0:
				running = false
				finished.emit(true)
	_place()
	_tick_hearts(delta)

func _player_pos() -> Vector2:
	return _to_picture(_player.position) if _player else _prev

# Keeps the character on the shop floor. If it starts off the floor (where the
# button was) it is left alone, it just can't go any farther out.
func _keep_player_on_floor() -> void:
	var r := config.walk_rect
	var p := _to_picture(_player.position)
	p.x = minf(maxf(p.x, minf(_prev.x, r.position.x)), maxf(_prev.x, r.end.x))
	p.y = minf(maxf(p.y, minf(_prev.y, r.position.y)), maxf(_prev.y, r.end.y))
	_prev = p
	_player.position = _to_room(p)

# ---------------------------------------------------------------- the mice
func _update_mouse(m: Mouse, pp: Vector2, dt: float) -> void:
	m.timer -= dt
	var to_p := pp - m.pos
	if m.timer <= 0.0:
		_decide(m, to_p)
	if m.speed > 0.0:
		var r := config.mouse_rect
		var next := m.pos + m.dir * m.speed * dt
		# each axis is held inside the shop on its own, so a mouse slides along a wall
		m.pos = Vector2(clampf(next.x, r.position.x, r.end.x), clampf(next.y, r.position.y, r.end.y))
		if absf(m.dir.x) > 0.15:
			m.face_right = m.dir.x > 0.0              # it faces the way it is going

func _decide(m: Mouse, to_p: Vector2) -> void:
	var d := to_p.length()
	m.timer = randf_range(config.decision_time.x, config.decision_time.y)
	if d < config.flee_radius:
		if randf() < config.approach_chance:
			m.dir = to_p.normalized() if d > 1.0 else Vector2.RIGHT
			m.speed = config.approach_speed
		else:
			var away := (-to_p).normalized() if d > 1.0 else Vector2.from_angle(randf() * TAU)
			m.dir = away.rotated(randf_range(-0.55, 0.55))
			m.speed = config.flee_speed * randf_range(0.85, 1.0)
			_along_walls(m, away)
	elif randf() < config.scoot_chance:
		m.dir = Vector2.from_angle(randf() * TAU)
		m.speed = config.scoot_speed
		m.timer = randf_range(config.scoot_time.x, config.scoot_time.y)
		_along_walls(m, m.dir)
	else:
		m.speed = 0.0
		m.timer = randf_range(config.idle_time.x, config.idle_time.y)

# A mouse at a wall that would run into it runs along it instead, the way that
# takes it farther from `away`.
func _along_walls(m: Mouse, away: Vector2) -> void:
	var r := config.mouse_rect.grow(-config.wall_margin)
	if (m.pos.x <= r.position.x and m.dir.x < 0.0) or (m.pos.x >= r.end.x and m.dir.x > 0.0):
		m.dir = Vector2(0.0, signf(away.y) if absf(away.y) > 0.2 else (1.0 if randf() < 0.5 else -1.0))
	if (m.pos.y <= r.position.y and m.dir.y < 0.0) or (m.pos.y >= r.end.y and m.dir.y > 0.0):
		m.dir = Vector2(signf(away.x) if absf(away.x) > 0.2 else (1.0 if randf() < 0.5 else -1.0), 0.0)

func _find_touching(pp: Vector2) -> void:
	_touching = null
	var best := config.touch_radius
	for m in _mice:
		var d := m.pos.distance_to(pp)
		if d < best:
			best = d
			_touching = m

# ---------------------------------------------------------------- adopting
var _adopted_sprite: Sprite2D

func _adopt(m: Mouse) -> void:
	_state = State.ADOPTING
	_timer = config.adopt_hold
	_adopted_sprite = m.sprite
	m.sprite.visible = false             # the pet carries on from where it stood
	_touching = null
	Game.input_locked = true
	Game.say_random("mouse_adopted")
	Pets.adopt(m.index, _to_room(m.pos), m.face_right)
	_burst_hearts(m.pos)

# ---------------------------------------------------------------- hearts
func _burst_hearts(at: Vector2) -> void:
	for i in 4:
		_hearts.append({
			"pos": at + Vector2(randf_range(-30.0, 30.0), randf_range(-50.0, -10.0)),
			"vel": Vector2(randf_range(-90.0, 90.0), randf_range(-280.0, -170.0)),
			"age": -randf_range(0.0, 0.25),               # they don't all leave at once
			"life": randf_range(0.9, 1.3),
			"size": randf_range(22.0, 32.0),           # small: half the width they were
			"sway": randf() * TAU,
		})

func _tick_hearts(delta: float) -> void:
	for h in _hearts:
		h["age"] += delta
		if h["age"] > 0.0:
			h["vel"] = (h["vel"] as Vector2) * (1.0 - 1.6 * delta)       # they slow as they rise
			h["pos"] += (h["vel"] as Vector2) * delta + Vector2(sin(h["age"] * 7.0 + h["sway"]) * 24.0 * delta, 0.0)
	_hearts = _hearts.filter(func(h: Dictionary): return h["age"] < h["life"])
	if _heart_layer:
		_heart_layer.queue_redraw()

func _draw_hearts() -> void:
	if config.heart == null:
		return
	for h in _hearts:
		var age: float = h["age"]
		if age <= 0.0:
			continue
		var life: float = h["life"]
		var pop := clampf(age / 0.18, 0.0, 1.0)                 # pops in
		var fade := clampf((life - age) / (life * 0.4), 0.0, 1.0) # fades out over the last stretch
		var sz: float = h["size"] * (0.4 + 0.6 * pop) * _s
		_heart_layer.draw_texture_rect(config.heart,
				Rect2(_to_room(h["pos"]) - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), false, Color(1, 1, 1, fade))
