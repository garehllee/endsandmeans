extends Minigame
class_name LaserGame
# "Get to the water gun": the character starts in the middle of a spiral maze
# and has to get out to the water gun at its far end. Every couple of seconds
# the surveillance sweeps the room with lasers. Each volley is announced first:
# a "!" blinks where every beam is about to come in and the beams are only
# outlined. Then they fire for a moment, and anything in one is hit and goes
# back to the middle. The shape of the volley changes: parallel stripes at
# different angles, a lattice of crossing stripes, beams aimed at wherever the
# character is standing, a fan from a corner, a cross, scattered beams.
#
# Everything is worked out in picture units (see LaserConfig) and only
# converted to room units for drawing.

enum State { WAITING, PLAYING, DEAD, TAKEN }

const CELL := 4                     # the wall picture is boiled down to cells this big for collision
const LONG := 5000.0                # long enough to run off any edge of the picture

var config: LaserConfig
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
var _timer := 0.0
var _clock := 0.0                   # seconds into the current volley (negative: a quiet start)
var _active := false                # a volley is on the screen
var _volleys := 0
var _beams: Array[Dictionary] = []  # {p, d, w, ray, icon}
var _last_kind := ""
var _goal_taken := false

var _solid := PackedByteArray()
var _mw := 0
var _mh := 0
var _field := PackedVector2Array()
var _rng := RandomNumberGenerator.new()

func setup(arena: Rect2, player: Node2D, _start_pos: Vector2) -> void:
	_arena = arena
	_player = player

# ---------------------------------------------------------------- building
func prepare(cfg: MinigameConfig) -> void:
	config = cfg as LaserConfig
	if config == null:
		push_error("LaserGame needs a LaserConfig")
		return
	_rng.randomize()
	_field = PackedVector2Array([Vector2.ZERO, Vector2(config.window.x, 0.0), config.window,
			Vector2(0.0, config.window.y)])
	_build_mask()
	_pos = config.start_pos
	_built = true
	set_expand(_arena, 0.0)

# The walls are boiled down to a coarse grid once; the character is tested against it.
func _build_mask() -> void:
	if config.maze == null:
		return
	var img := config.maze.get_image()
	if img == null:
		return
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	_mw = ceili(img.get_width() / float(CELL))
	_mh = ceili(img.get_height() / float(CELL))
	img.resize(_mw, _mh, Image.INTERPOLATE_LANCZOS)
	var data := img.get_data()
	_solid.resize(_mw * _mh)
	for i in _mw * _mh:
		_solid[i] = 1 if data[i * 4 + 3] > 40 else 0

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
	_respawn()
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
		_player.modulate.a = 1.0

func _respawn() -> void:
	_pos = config.start_pos
	_beams.clear()
	_active = false
	_clock = -config.start_grace
	if _player and is_instance_valid(_player):
		_player.modulate.a = 1.0

func _process(delta: float) -> void:
	if not _built:
		return
	if running:
		var dt := minf(delta, 1.0 / 30.0)
		match _state:
			State.PLAYING:
				_step(dt)
			State.DEAD:
				_timer -= dt
				_tick_lasers(dt)
				if _timer <= 0.0:
					_respawn()
					_state = State.PLAYING
			State.TAKEN:
				_timer -= dt
				if _timer <= 0.0:
					running = false
					finished.emit(true)
		_place()
	queue_redraw()

func _step(dt: float) -> void:
	var mine := Game.active_world == world_id and not Game.input_locked
	var dir := Vector2.ZERO
	if mine:
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
		_move(dir * config.move_speed * dt)
	if _player:
		_player.set_motion(dir != Vector2.ZERO, _face)

	_tick_lasers(dt)
	if _fire_phase() and _in_beam():
		_state = State.DEAD
		_timer = config.respawn_delay
		if _player:
			_player.modulate.a = 0.35
			_player.set_motion(false, _face)
		Game.say_random("laser_hit")
		return

	if not _goal_taken and _pos.distance_to(config.goal_pos) < config.goal_radius + config.body_radius * 0.5:
		_goal_taken = true
		_state = State.TAKEN
		_timer = config.end_hold
		Game.say_random("watergun_taken")

# ---------------------------------------------------------------- walking
# Moves in small steps, one axis at a time, so the character slides along a wall.
func _move(delta: Vector2) -> void:
	var steps := maxi(ceili(delta.length() / 8.0), 1)
	var d := delta / float(steps)
	for i in steps:
		if not _blocked(_pos + Vector2(d.x, 0.0)):
			_pos.x += d.x
		if not _blocked(_pos + Vector2(0.0, d.y)):
			_pos.y += d.y

func _blocked(p: Vector2) -> bool:
	var r := config.body_radius
	if p.x < r or p.y < r or p.x > config.window.x - r or p.y > config.window.y - r:
		return true
	if _solid.is_empty():
		return false
	var x0 := maxi(int((p.x - r) / CELL), 0)
	var x1 := mini(int((p.x + r) / CELL), _mw - 1)
	var y0 := maxi(int((p.y - r) / CELL), 0)
	var y1 := mini(int((p.y + r) / CELL), _mh - 1)
	var lim := (r + CELL * 0.5) * (r + CELL * 0.5)
	for cy in range(y0, y1 + 1):
		for cx in range(x0, x1 + 1):
			if _solid[cy * _mw + cx] == 1:
				var c := Vector2((cx + 0.5) * CELL, (cy + 0.5) * CELL)
				if c.distance_squared_to(p) < lim:
					return true
	return false

# ---------------------------------------------------------------- lasers
func _tick_lasers(dt: float) -> void:
	_clock += dt
	if _clock >= config.period:
		_clock -= config.period
		_spawn_volley()
	elif _clock >= 0.0 and not _active:
		_spawn_volley()

func _spawn_volley() -> void:
	_active = true
	_volleys += 1
	_beams = _make_volley()

func _fire_phase() -> bool:
	return _active and _clock >= config.warn_time and _clock < config.warn_time + config.fire_time

func _in_beam() -> bool:
	for b in _beams:
		var v: Vector2 = _pos - b["p"]
		var d: Vector2 = b["d"]
		if b["ray"] and v.dot(d) < -config.hit_radius:
			continue
		if absf(v.cross(d)) < float(b["w"]) * 0.5 + config.hit_radius:
			return true
	return false

# The first volleys are plain parallel stripes; after that the shapes vary,
# never the same twice running.
func _make_volley() -> Array[Dictionary]:
	var kind := "parallel"
	if _volleys > 2:
		var kinds := ["parallel", "grid", "aimed", "cross", "fan", "scatter"]
		kinds.erase(_last_kind)
		kind = kinds[_rng.randi() % kinds.size()]
	_last_kind = kind
	var out: Array[Dictionary] = []
	var wmin := config.beam_width.x
	var wmax := config.beam_width.y
	match kind:
		"parallel":
			var w := _rng.randf_range(wmin, wmax)
			_add_stripes(out, _pick_angle(), w, maxf(w * 2.0, w + 250.0), _rng.randf())
		"grid":
			var a := _pick_angle()
			var w := wmin * _rng.randf_range(0.65, 0.9)
			_add_stripes(out, a, w, 540.0, _rng.randf())
			_add_stripes(out, a + PI * 0.5, w, 540.0, _rng.randf())
		"aimed":
			# through wherever the character is standing right now
			var a := _pick_angle()
			var w := _rng.randf_range(wmin, wmax) * 0.85
			_add_beam(out, _pos, a, w, false)
			if _rng.randf() < 0.5:
				_add_beam(out, _pos, a + PI * 0.5, w, false)
		"cross":
			var at := Vector2(_rng.randf_range(300.0, config.window.x - 300.0),
					_rng.randf_range(300.0, config.window.y - 300.0))
			var a := _pick_angle()
			var w := _rng.randf_range(wmin, wmax)
			_add_beam(out, at, a, w, false)
			_add_beam(out, at, a + PI * 0.5, w, false)
		"fan":
			# rays out of a point on the edge, spread toward the middle
			var from := _edge_point()
			var mid := (config.window * 0.5 + Vector2(_rng.randf_range(-250.0, 250.0), _rng.randf_range(-250.0, 250.0)) - from).angle()
			var n := 5 + _rng.randi() % 2
			var step := deg_to_rad(15.0)
			for i in n:
				var ra := mid + (float(i) - float(n - 1) * 0.5) * step
				if _off_axis(ra):
					_add_beam(out, from, ra, wmin * 0.7, true)
		"scatter":
			for i in 4 + _rng.randi() % 2:
				var at := Vector2(_rng.randf_range(0.0, config.window.x), _rng.randf_range(0.0, config.window.y))
				_add_beam(out, at, _pick_angle(), _rng.randf_range(wmin, wmax) * 0.75, false)
	return out

# Always a diagonal. A beam running (nearly) along a corridor would fill it
# end to end with nowhere to step aside, so straight-across angles are left out;
# the cross and the lattice add 90 degrees to this, which stays diagonal.
func _pick_angle() -> float:
	var a := deg_to_rad(_rng.randf_range(35.0, 55.0))
	return a if _rng.randf() < 0.5 else PI - a

# True when a ray points far enough off the corridors' directions to be dodged.
func _off_axis(a: float) -> bool:
	var m := fposmod(rad_to_deg(a), 90.0)
	return m > 28.0 and m < 62.0

func _edge_point() -> Vector2:
	var w := config.window.x
	var h := config.window.y
	match _rng.randi() % 4:
		0: return Vector2(_rng.randf() * w, 0.0)
		1: return Vector2(w, _rng.randf() * h)
		2: return Vector2(_rng.randf() * w, h)
	return Vector2(0.0, _rng.randf() * h)

# Evenly spaced parallel beams across the whole picture, at angle `a`.
func _add_stripes(out: Array[Dictionary], a: float, w: float, spacing: float, offset: float) -> void:
	var d := Vector2.from_angle(a)
	var n := d.orthogonal()
	var lo := INF
	var hi := -INF
	for c in _field:
		lo = minf(lo, n.dot(c))
		hi = maxf(hi, n.dot(c))
	var x := lo + offset * spacing
	while x < hi + w * 0.5:
		_add_beam(out, n * x, a, w, false)
		x += spacing

func _add_beam(out: Array[Dictionary], p: Vector2, a: float, w: float, ray: bool) -> void:
	var d := Vector2.from_angle(a)
	var b := {"p": p, "d": d, "w": w, "ray": ray}
	# where it comes into the picture: the "!" goes just inside that end
	var span := _clip_line(p, d, ray)
	if span.x < span.y:
		var at := p + d * (span.x + config.warning_size * 0.9)
		b["icon"] = Vector2(clampf(at.x, config.warning_size * 0.6, config.window.x - config.warning_size * 0.6),
				clampf(at.y, config.warning_size * 0.6, config.window.y - config.warning_size * 0.6))
	else:
		b["icon"] = Vector2(-1000.0, -1000.0)       # misses the picture altogether
	out.append(b)

# The stretch of the line (as distances along d from p) that lies inside the picture.
func _clip_line(p: Vector2, d: Vector2, ray: bool) -> Vector2:
	var t0 := 0.0 if ray else -LONG
	var t1 := LONG
	for axis in 2:
		var pa := p[axis]
		var da := d[axis]
		var hi: float = config.window[axis]
		if absf(da) < 0.00001:
			if pa < 0.0 or pa > hi:
				return Vector2(1.0, 0.0)
			continue
		var ta := (0.0 - pa) / da
		var tb := (hi - pa) / da
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
	return Vector2(t0, t1)

# ---------------------------------------------------------------- drawing
func _draw() -> void:
	if not _built or _expand < 0.5:
		return
	var fade := clampf((_expand - 0.5) / 0.5, 0.0, 1.0)
	var full := Rect2(_layer.position, config.window * _s)
	if config.maze:
		draw_texture_rect(config.maze, full, false, Color(1, 1, 1, fade))
	if config.goal_texture and not _goal_taken:
		var gw := config.goal_width
		var gh := gw * config.goal_texture.get_height() / float(config.goal_texture.get_width())
		draw_texture_rect(config.goal_texture,
				Rect2(_to_room(config.goal_pos - Vector2(gw, gh) * 0.5), Vector2(gw, gh) * _s),
				false, Color(1, 1, 1, fade))
	if _expand < 0.999:
		return
	_draw_beams()
	_draw_hint()

func _draw_beams() -> void:
	if not _active:
		return
	var warn := config.warn_time
	var fire := warn + config.fire_time
	var col := config.beam_color
	var fill := 0.0
	var edge := 0.0
	var core := 0.0
	var icons := 0.0
	if _clock < warn:
		var k := _clock / warn
		fill = config.warn_alpha * smoothstep(0.0, 0.2, k)
		edge = 0.85 * smoothstep(0.0, 0.2, k)
		icons = 0.55 + 0.45 * (0.5 + 0.5 * sin(_clock * TAU * 3.5))
	elif _clock < fire:
		fill = config.fire_alpha
		core = config.fire_alpha * 0.7
	else:
		var f := (_clock - fire) / maxf(config.period - fire, 0.001)
		fill = config.fire_alpha * (1.0 - f) * (1.0 - f)
		core = config.fire_alpha * 0.7 * (1.0 - f) * (1.0 - f)
	for b in _beams:
		var poly := _beam_polygon(b, 1.0)
		if poly.size() >= 3:
			draw_colored_polygon(poly, Color(col, fill))
			if edge > 0.0:
				var ring := poly.duplicate()
				ring.append(poly[0])
				draw_polyline(ring, Color(col, edge), 3.0)
		if core > 0.0:
			var inner := _beam_polygon(b, 0.4)
			if inner.size() >= 3:
				draw_colored_polygon(inner, Color(0.95, 1.0, 0.75, core))
	if icons > 0.0 and config.warning_icon:
		var sz := Vector2.ONE * config.warning_size * _s
		for b in _beams:
			var at: Vector2 = b["icon"]
			if at.x < 0.0:
				continue
			draw_texture_rect(config.warning_icon, Rect2(_to_room(at) - sz * 0.5, sz), false,
					Color(1, 1, 1, icons))

# One beam as a polygon in room units, trimmed to the picture.
func _beam_polygon(b: Dictionary, thin: float) -> PackedVector2Array:
	var p: Vector2 = b["p"]
	var d: Vector2 = b["d"]
	var n := d.orthogonal() * float(b["w"]) * 0.5 * thin
	var a := p if b["ray"] else p - d * LONG
	var z := p + d * LONG
	var quad := PackedVector2Array([a + n, z + n, z - n, a - n])
	var clipped := Geometry2D.intersect_polygons(quad, _field)
	if clipped.is_empty():
		return PackedVector2Array()
	var out := PackedVector2Array()
	for v in clipped[0]:
		out.append(_to_room(v))
	return out

func _draw_hint() -> void:
	if _volleys > 2 or _state != State.PLAYING:
		return
	var f: Font = config.font if config.font else ThemeDB.fallback_font
	var text := "arrows to move. get to the water gun."
	var fs := int(48 * _s)
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(f, _to_room(Vector2(config.window.x * 0.5, 120.0)) - Vector2(w * 0.5, 0.0), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.8))
