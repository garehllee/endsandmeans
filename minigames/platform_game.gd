extends Minigame
class_name PlatformGame
# "Retrieve the key": a platformer across the glitched boxes.
#
# The course is longer than the window. It starts cropped to the usual minigame
# window and the camera follows once the character runs to the right. The boxes
# are one-way: you stand on them and jump up through them from underneath. Fall
# off and the character goes back to the start, with the camera panning back.
# Reaching the key ends the game.
#
# Everything here is worked out in the level's own picture units (see
# PlatformConfig) and converted to room units only for drawing.

enum State { WAITING, PLAYING, DEAD, TAKEN }

const EXCLUSION_SHADER := preload("res://shaders/exclusion.gdshader")
const LAND_TOLERANCE := 60.0        # how far past the top edge a fall can be caught

var config: PlatformConfig
var running := false

var _arena := Rect2()
var _player: Node2D
var _layer := Rect2()               # where the level's top left sits, in room units
var _s := 1.0                       # room units per picture unit
var _built := false
var _expand := 0.0

var _state := State.WAITING
var _pos := Vector2.ZERO            # the character's middle, picture units
var _vel := Vector2.ZERO
var _grounded := false
var _coyote := 0.0
var _buffer := 0.0
var _cut := false                   # the rise has already been cut short
var _face := 1.0
var _timer := 0.0
var _cam := Vector2.ZERO
var _camera: Camera2D

var _boxes: Array[Sprite2D] = []
var _copies: Array[BackBufferCopy] = []
var _key: Sprite2D
var _code: Array[Dictionary] = []
var _shapes: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()

func setup(arena: Rect2, player: Node2D, _start_pos: Vector2) -> void:
	_arena = arena
	_player = player

# ---------------------------------------------------------------- building
func prepare(cfg: MinigameConfig) -> void:
	config = cfg as PlatformConfig
	if config == null:
		push_error("PlatformGame needs a PlatformConfig")
		return
	_rng.randomize()
	_build_boxes()
	_build_key()
	_build_code()
	_build_shapes()
	_pos = config.start_pos
	_built = true
	set_expand(_arena, 0.0)

# A flat picture of one colour, for the glitched boxes to be drawn with.
func _box_texture() -> Texture2D:
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, config.box_color)
	return ImageTexture.create_from_image(img)

# Every box is its own layer: each one is exclusion-blended over everything drawn
# behind it, the boxes before it included, so overlaps pile up and go glitchy.
# That means a fresh copy of the whole screen in front of each box; boxes that
# are off screen are switched off, so only the visible ones pay for it.
func _build_boxes() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = EXCLUSION_SHADER
	var tex := _box_texture()
	for i in config.platforms.size():
		var copy := BackBufferCopy.new()
		copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT   # the whole screen, so nothing stale is ever sampled
		copy.z_index = 1
		copy.visible = false
		add_child(copy)
		_copies.append(copy)
		var sp := Sprite2D.new()
		sp.texture = tex
		sp.centered = false
		sp.material = mat
		sp.z_index = 1
		sp.visible = false
		add_child(sp)
		_boxes.append(sp)

func _build_key() -> void:
	_key = Sprite2D.new()
	_key.texture = config.key_texture
	_key.centered = true
	_key.z_index = 2
	_key.visible = false
	add_child(_key)

# Most of the snippets come out small, a few come out huge.
func _code_size() -> float:
	var k := pow(_rng.randf(), config.code_small_bias)
	return lerpf(config.code_sizes.x, config.code_sizes.y, k)

func _build_code() -> void:
	var snippets := config.snippets
	if snippets.is_empty():
		return
	for i in config.code_layers:
		var d := {
			"text": snippets[i % snippets.size()],
			"size": _code_size(),
			"x": _rng.randf_range(-200.0, config.level_size.x),
			"y": _rng.randf_range(-100.0, config.level_size.y),
			"par": _rng.randf_range(config.code_parallax.x, config.code_parallax.y),
			"drift": _rng.randf_range(config.code_drift.x, config.code_drift.y) * (1.0 if _rng.randf() < 0.5 else -1.0),
			"speed": _rng.randf_range(config.type_speed.x, config.type_speed.y),
			"hold": _rng.randf_range(config.type_hold.x, config.type_hold.y),
			"phase": "in",
			"t": _rng.randf() * 2.0,
			"shown": 0.0,
		}
		_code.append(d)

func _build_shapes() -> void:
	if config.glitch_shapes.is_empty():
		return
	for i in config.shape_count:
		_shapes.append({
			"tex": config.glitch_shapes[i % config.glitch_shapes.size()],
			"x": _rng.randf_range(0.0, config.level_size.x),
			"y": _rng.randf_range(0.0, config.level_size.y),
			"rot": _rng.randf() * TAU,
			"spin": _rng.randf_range(-0.12, 0.12),
			"scale": _rng.randf_range(config.shape_scale.x, config.shape_scale.y),
			"par": _rng.randf_range(0.3, 0.8),
			"drift": _rng.randf_range(config.shape_drift.x, config.shape_drift.y) * (1.0 if _rng.randf() < 0.5 else -1.0),
		})

# ---------------------------------------------------------------- placing
# The level is drawn at the same scale as the other minigames: one screenful is
# `window` wide, and the course carries on past the right edge.
func set_expand(rect: Rect2, t: float) -> void:
	if not _built:
		return
	_expand = t
	_s = rect.size.x / config.window.x
	var win_h := config.window.y * _s
	_layer = Rect2(rect.position.x, rect.get_center().y - win_h * 0.5, config.level_size.x * _s, win_h)
	if _camera == null or not is_instance_valid(_camera):
		_cam = rect.get_center()
	_place()
	queue_redraw()

func _to_room(p: Vector2) -> Vector2:
	return _layer.position + p * _s

func _place() -> void:
	var show := _expand >= 0.999
	var view := Rect2(_cam.x - _arena.size.x * 0.6, _cam.y - _arena.size.y * 0.6,
			_arena.size.x * 1.2, _arena.size.y * 1.2)
	for i in _boxes.size():
		var r: Rect2 = config.platforms[i]
		var room := Rect2(_to_room(r.position), r.size * _s)
		var on := show and room.intersects(view)      # off-screen boxes cost nothing
		var sp: Sprite2D = _boxes[i]
		sp.visible = on
		sp.position = room.position
		sp.scale = r.size * _s          # the picture is one pixel, so this is its size
		var copy: BackBufferCopy = _copies[i]
		copy.visible = on
	if _key:
		_key.visible = show and _state != State.TAKEN
		_key.position = _to_room(config.key_pos)
		if _key.texture:
			_key.scale = Vector2.ONE * (config.key_width * _s / maxf(_key.texture.get_width(), 1.0))
	if _player and show:
		_player.position = _to_room(_pos)

# ---------------------------------------------------------------- running
func start(cfg: MinigameConfig) -> void:
	if not _built:
		prepare(cfg)
	if not _built:
		finished.emit(true)
		return
	_camera = get_parent().get_node_or_null("Camera2D") as Camera2D
	set_expand(_arena, 1.0)
	_respawn()
	_state = State.PLAYING
	running = true
	if _player:
		_player.platform_mode = true          # the character's own walking is switched off
	Game.input_locked = false

func stop() -> void:
	running = false
	if _player and is_instance_valid(_player):
		_player.platform_mode = false

func _respawn() -> void:
	_pos = config.start_pos
	_vel = Vector2.ZERO
	_grounded = false
	_coyote = 0.0
	_buffer = 0.0
	_cut = false

# Where the camera should sit, in room units. The room asks for this each frame.
func camera_target() -> Vector2:
	var half := _arena.size.x * 0.5
	var x := _to_room(_pos).x + _face * config.look_ahead * _s
	var right := _layer.position.x + _layer.size.x
	return Vector2(clampf(x, _layer.position.x + half, maxf(right - half, _layer.position.x + half)),
			_arena.get_center().y)

func _process(delta: float) -> void:
	if not _built:
		return
	if _camera and is_instance_valid(_camera):
		_cam = _camera.position
	_advance_background(delta)
	if running:
		match _state:
			State.PLAYING:
				_step(minf(delta, 1.0 / 30.0))
			State.DEAD:
				_timer -= delta
				if _timer <= 0.0:
					_respawn()
					_state = State.PLAYING
			State.TAKEN:
				_timer -= delta
				if _timer <= 0.0:
					running = false
					finished.emit(true)
	_place()
	queue_redraw()

func _step(dt: float) -> void:
	var mine := Game.active_world == world_id and not Game.input_locked
	var move := 0.0
	var jump_held := false
	if mine:
		if Input.is_action_pressed("ui_right"):
			move += 1.0
		if Input.is_action_pressed("ui_left"):
			move -= 1.0
		jump_held = Input.is_action_pressed("ui_up") or Input.is_action_pressed("ui_accept")
		if Input.is_action_just_pressed("ui_up") or Input.is_action_just_pressed("ui_accept"):
			_buffer = config.jump_buffer

	_vel.x = move * config.move_speed
	if move != 0.0:
		_face = signf(move)

	# jumping: a little grace after an edge, and a press just before landing counts
	_coyote = maxf(_coyote - dt, 0.0)
	_buffer = maxf(_buffer - dt, 0.0)
	if _buffer > 0.0 and (_grounded or _coyote > 0.0):
		_vel.y = -config.jump_speed
		_grounded = false
		_coyote = 0.0
		_buffer = 0.0
		_cut = false
	if not jump_held and _vel.y < 0.0 and not _cut:
		_vel.y *= config.short_hop            # letting go early makes a shorter hop
		_cut = true

	_vel.y += config.gravity * dt
	_pos.x = clampf(_pos.x + _vel.x * dt, config.half_width, config.level_size.x - config.half_width)

	var was_feet := _pos.y + config.feet
	_pos.y += _vel.y * dt
	var feet := _pos.y + config.feet
	var landed := false
	if _vel.y >= 0.0:
		for r in config.platforms:
			if _pos.x + config.half_width <= r.position.x or _pos.x - config.half_width >= r.end.x:
				continue
			# only from above: the soles were over the top edge a moment ago
			if was_feet <= r.position.y + LAND_TOLERANCE and feet >= r.position.y:
				_pos.y = r.position.y - config.feet
				_vel.y = 0.0
				landed = true
				break
	if landed:
		_grounded = true
		_coyote = config.coyote_time
		_cut = false
	else:
		if _grounded:
			_coyote = config.coyote_time      # just walked off an edge
		_grounded = false

	if _player:
		_player.set_motion(absf(_vel.x) > 1.0, "right" if _face >= 0.0 else "left")

	if _pos.y > config.fall_y:
		_state = State.DEAD
		_timer = config.respawn_delay
		Game.say_random("platform_fall")
		return
	if _takes_key():
		_state = State.TAKEN
		_timer = config.end_hold
		if _key:
			_key.visible = false
		Game.say_random("key_taken")

func _takes_key() -> bool:
	var k: Vector2 = config.key_pos
	return absf(k.x - _pos.x) < config.key_radius + config.half_width \
			and k.y > _pos.y - config.head - config.key_radius \
			and k.y < _pos.y + config.feet + config.key_radius

# ---------------------------------------------------------------- background
func _advance_background(delta: float) -> void:
	for d in _code:
		d["y"] = fposmod(d["y"] + d["drift"] * delta + 200.0, config.level_size.y + 400.0) - 200.0
		d["t"] += delta
		var text: String = d["text"]
		match d["phase"]:
			"in":
				d["shown"] = minf(d["shown"] + d["speed"] * delta, text.length())
				if d["shown"] >= text.length():
					d["phase"] = "hold"
					d["t"] = 0.0
			"hold":
				if d["t"] >= d["hold"]:
					d["phase"] = "out"
			"out":
				d["shown"] = maxf(d["shown"] - d["speed"] * delta, 0.0)
				if d["shown"] <= 0.0:
					# a new snippet somewhere else
					d["phase"] = "in"
					d["t"] = 0.0
					d["hold"] = _rng.randf_range(config.type_hold.x, config.type_hold.y)
					d["size"] = _code_size()
					d["x"] = _rng.randf_range(-200.0, config.level_size.x)
					d["y"] = _rng.randf_range(-100.0, config.level_size.y)
					if not config.snippets.is_empty():
						d["text"] = config.snippets[_rng.randi() % config.snippets.size()]
	for d in _shapes:
		d["y"] = fposmod(d["y"] + d["drift"] * delta + 400.0, config.level_size.y + 800.0) - 400.0
		d["rot"] = d["rot"] + d["spin"] * delta

# ---------------------------------------------------------------- drawing
func _draw() -> void:
	if not _built or _expand < 0.999:
		return      # the button is still growing; it shows the level's picture meanwhile
	# Black behind the whole course, a good way past both ends.
	draw_rect(Rect2(_layer.position - Vector2(_layer.size.x, 400.0),
			_layer.size + Vector2(_layer.size.x * 2.0, 800.0)), Color.BLACK)
	_draw_shapes()
	_draw_code()
	_draw_hint()

# How far the camera has scrolled from the start, in picture units.
func _scroll() -> float:
	return (_cam.x - _arena.size.x * 0.5 - _layer.position.x) / maxf(_s, 0.0001)

func _draw_shapes() -> void:
	var scroll := _scroll()
	for d in _shapes:
		var tex: Texture2D = d["tex"]
		if tex == null:
			continue
		var p := _to_room(Vector2(d["x"] + scroll * (1.0 - d["par"]), d["y"]))
		draw_set_transform(p, d["rot"], Vector2.ONE * (d["scale"] * _s))
		draw_texture(tex, -tex.get_size() * 0.5, Color(1, 1, 1, config.shape_alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_code() -> void:
	var f: Font = config.code_font if config.code_font else ThemeDB.fallback_font
	var scroll := _scroll()
	var left := _cam.x - _arena.size.x
	var right := _cam.x + _arena.size.x * 0.7
	for d in _code:
		var n := int(d["shown"])
		if n <= 0:
			continue
		var text: String = d["text"].substr(0, n)
		var p := _to_room(Vector2(d["x"] + scroll * (1.0 - d["par"]), d["y"]))
		if p.x < left or p.x > right:
			continue                      # off to the side; not worth drawing
		draw_multiline_string(f, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1,
				int(d["size"] * _s), -1, config.code_color)

func _draw_hint() -> void:
	var f: Font = config.code_font if config.code_font else ThemeDB.fallback_font
	var p := _to_room(config.start_pos + Vector2(-90, -300))
	draw_string(f, p, "arrows to run, up to jump", HORIZONTAL_ALIGNMENT_LEFT, -1,
			int(46 * _s), Color(1, 1, 1, 0.75))
