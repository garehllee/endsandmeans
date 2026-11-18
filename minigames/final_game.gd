extends Minigame
class_name FinalGame
# ZZ_Hack_Hugging_Face, the last folder.
#
# The character (a bug, with the water gun, the mouse trotting behind) starts in
# a white room with only Hugging Face in it. Walk up and press E: the room
# flashes and breaks up (the transition video, darken-blended over everything)
# and the fight starts over the looping server footage.
#
# Phase one: glitched boxes, exclusion-blended like the key platformer's but
# made up as you go, run on forever to the right. Hugging Face keeps running
# ahead. Stand level with it and press E to hit it with the water. Three hits
# take it to half. Falling off heals it back to where the phase began.
# Phase two: it flashes and puts up an umbrella, which blocks the water on
# every beat of the music, and every few beats it fires lasers (stacks of its
# own face) that knock the character back. Two hits off the beat, and on the
# third the mouse lunges and bites it instead. Everything flashes white.
# Back in the white room there's a door where Hugging Face was. E at the door:
# the key from the first subtask opens it, the character walks in, the screen
# glitches out, and the game is over.
#
# Positions are in picture units (see FinalConfig) and only converted to room
# units for drawing. During the fight x keeps growing to the right.

enum Stage { WAITING, ROOM, TRANSITION, BATTLE, BITE, FLASH, DOOR_ROOM, UNLOCK, ENTER, GLITCH, DONE }

const DARKEN_SHADER := preload("res://shaders/darken.gdshader")
const EXCLUSION_SHADER := preload("res://shaders/exclusion.gdshader")
const SHOW_ON_BLACK := preload("res://shaders/show_on_black.gdshader")
const BOX_POOL := 48
const LAND_TOLERANCE := 60.0
const RAT_FRAME := 540.0
const LONG := 6000.0

class Cluster:
	var x0 := 0.0
	var x1 := 0.0
	var top := 0.0
	var boxes: Array[Rect2] = []

class Laser:
	var p := Vector2.ZERO      # a point on it, in screen picture units (0..window.x across)
	var d := Vector2.RIGHT     # which way it shoots
	var w := 150.0
	var t := 0.0               # seconds since the warning went up
	var icon := Vector2(-1000, -1000)

var config: FinalConfig
var running := false

var _arena := Rect2()
var _player: Node2D
var _layer := Rect2()
var _s := 1.0
var _built := false
var _expand := 0.0
var _camera: Camera2D
var _cam := Vector2.ZERO
var _rng := RandomNumberGenerator.new()
var _t := 0.0

var _stage := Stage.WAITING
var _stage_t := 0.0

# the character
var _pos := Vector2.ZERO
var _vel := Vector2.ZERO
var _face := 1.0
var _dir := "right"
var _grounded := false
var _coyote := 0.0
var _buffer := 0.0
var _cut := false
var _dead := 0.0           # counting down to the respawn after a fall
var _hurt := 0.0           # can't be hit while this runs
var _player_alpha := 1.0
var _player_scale := Vector2.ONE   # whatever the room drew the character at; put back after

# the gun
var _shot_t := -1.0
var _shot_dir := 1.0
var _shot_reach := -1.0    # where the water stops (a hit or the umbrella), or -1
var _shot_kind := ""       # "hit", "block" or ""
var _shot_done := false
var _shot_pause := 0.0

# Hugging Face
var _hf := Vector2.ZERO
var _hf_goal_y := 0.0
var _health := 6
var _shown_health := 6.0
var _phase := 1
var _hits := 0             # hits in this phase
var _hf_flash := 0.0       # white blinks after a hit
var _phase_flash := 0.0    # the longer blinking going into phase two
var _hf_visible := true
var _bar_a := 0.0

# the beat
var _beat_floor := -999
var _beats := 0

var _lasers: Array[Laser] = []

# the platforms
var _clusters: Array[Cluster] = []
var _boxes: Array[Sprite2D] = []
var _copies: Array[BackBufferCopy] = []

# the pet
var _pet_idx := -1
var _pet_tex: Texture2D
var _pet := Vector2.ZERO
var _pet_flip := false
var _pet_t := 0.0
var _bite_from := Vector2.ZERO
var _bite_t := 0.0

# the door
var _door_open := false
var _key_t := 0.0

# screen-wide
var _white := 0.0          # white over everything
var _room_a := 0.0         # the room and Hugging Face fade in once you've said go
var _scroll := 0.0         # where the screen has scrolled to on its own (middle, picture units)
var _scroll_wait := 0.0
var _black := 0.0          # black over everything

# layers
var _back: Node2D          # the pet, under the character
var _front: Node2D         # Hugging Face, the water, the gun, the lasers
var _hud: Node2D
var _blue: Node2D          # the blue Hugging Face in the transition's black flashes
var _over: Node2D          # white and black fades
var _server: VideoStreamPlayer
var _transition: VideoStreamPlayer
var _glitch: VideoStreamPlayer
var _room_music: AudioStreamPlayer
var _battle_music: AudioStreamPlayer

func setup(arena: Rect2, player: Node2D, _start_pos: Vector2) -> void:
	_arena = arena
	_player = player

# ---------------------------------------------------------------- building
func prepare(cfg: MinigameConfig) -> void:
	config = cfg as FinalConfig
	if config == null:
		push_error("FinalGame needs a FinalConfig")
		return
	_rng.randomize()
	_health = config.health
	_shown_health = float(_health)

	_server = _make_video(config.server_video, 0, null)
	_server.loop = true
	_back = _make_layer(0, _draw_back)
	_build_boxes()
	_front = _make_layer(2, _draw_front)
	_hud = _make_layer(2, _draw_hud)
	var copy := BackBufferCopy.new()
	copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	copy.z_index = 3
	add_child(copy)
	var dark := ShaderMaterial.new()
	dark.shader = DARKEN_SHADER
	_transition = _make_video(config.transition_video, 3, dark)
	var copy2 := BackBufferCopy.new()
	copy2.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	copy2.z_index = 4
	add_child(copy2)
	_blue = _make_layer(4, _draw_blue)
	var on_black := ShaderMaterial.new()
	on_black.shader = SHOW_ON_BLACK
	_blue.material = on_black
	_glitch = _make_video(config.glitch_video, 5, null)
	_over = _make_layer(6, _draw_over)

	_room_music = _make_music(config.room_music)
	_battle_music = _make_music(config.battle_music)

	_pet_idx = Pets.index() if Pets.has_method("index") else -1
	if _pet_idx >= 0:
		_pet_tex = load(Pets.PATH % _pet_idx)

	_pos = config.spawn
	_hf = config.hf_pos
	_built = true
	set_expand(_arena, 0.0)

func _make_layer(z: int, draw_fn: Callable) -> Node2D:
	var n := Node2D.new()
	n.z_index = z
	n.draw.connect(draw_fn)
	add_child(n)
	return n

func _make_video(stream: VideoStream, z: int, mat: Material) -> VideoStreamPlayer:
	var v := VideoStreamPlayer.new()
	v.stream = stream
	v.expand = true
	v.z_index = z
	v.visible = false
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if mat:
		v.material = mat
	add_child(v)
	return v

func _make_music(stream: AudioStream) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "Music"
	p.stream = stream
	p.volume_db = config.music_db
	if stream and "loop" in stream:
		stream.set("loop", true)
	add_child(p)
	return p

func _box_texture() -> Texture2D:
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, config.box_color)
	return ImageTexture.create_from_image(img)

# A pool of exclusion-blended boxes, handed out to whichever are on screen.
func _build_boxes() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = EXCLUSION_SHADER
	var tex := _box_texture()
	for i in BOX_POOL:
		var copy := BackBufferCopy.new()
		copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
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

# ---------------------------------------------------------------- placing
func set_expand(rect: Rect2, t: float) -> void:
	if not _built:
		return
	_expand = t
	_s = rect.size.x / config.window.x
	var win_h := config.window.y * _s
	_layer = Rect2(rect.position.x, rect.get_center().y - win_h * 0.5, config.window.x * _s, win_h)
	if _camera == null or not is_instance_valid(_camera):
		_cam = rect.get_center()
	_place()
	_redraw()

func _to_room(p: Vector2) -> Vector2:
	return _layer.position + p * _s

func _from_room(p: Vector2) -> Vector2:
	return (p - _layer.position) / maxf(_s, 0.0001)

# What the window shows, in picture units.
func _view() -> Rect2:
	var tl := _from_room(_cam - _arena.size * 0.5)
	return Rect2(tl, _arena.size / maxf(_s, 0.0001))

func _in_white_room() -> bool:
	return _stage in [Stage.WAITING, Stage.ROOM, Stage.TRANSITION, Stage.DOOR_ROOM,
			Stage.UNLOCK, Stage.ENTER, Stage.GLITCH, Stage.DONE]

func camera_target() -> Vector2:
	if _in_white_room() or _stage == Stage.FLASH and _white >= 0.99:
		return _arena.get_center()
	var x := maxf(_scroll, _pos.x + config.look_ahead)
	return Vector2(_to_room(Vector2(x, 0.0)).x, _arena.get_center().y)

func _place() -> void:
	var v := _view()
	var battle := not _in_white_room()
	var n := 0
	if battle and _expand >= 0.999:
		for c in _clusters:
			if c.x1 < v.position.x - 50.0 or c.x0 > v.end.x + 50.0:
				continue
			for r in c.boxes:
				if n >= BOX_POOL:
					break
				var sp := _boxes[n]
				sp.position = _to_room(r.position)
				sp.scale = r.size * _s
				sp.visible = true
				_copies[n].visible = true
				n += 1
	for i in range(n, BOX_POOL):
		_boxes[i].visible = false
		_copies[i].visible = false

	# the server footage fills the window, square, whatever its shape
	var side := maxf(_arena.size.x, _arena.size.y)
	_server.position = _cam - Vector2(side, side) * 0.5
	_server.size = Vector2(side, side)
	var pic := Rect2(_to_room(Vector2.ZERO), config.window * _s)
	_transition.position = pic.position
	_transition.size = pic.size
	_glitch.position = pic.position
	_glitch.size = pic.size

	if _player and is_instance_valid(_player) and running:
		_player.position = _to_room(_pos)
		_player.modulate.a = _player_alpha

func _redraw() -> void:
	queue_redraw()
	for n in [_back, _front, _hud, _blue, _over]:
		if n:
			(n as Node2D).queue_redraw()

# ---------------------------------------------------------------- running
func start(cfg: MinigameConfig) -> void:
	if not _built:
		prepare(cfg)
	if not _built:
		finished.emit(true)
		return
	_camera = get_parent().get_node_or_null("Camera2D") as Camera2D
	set_expand(_arena, 1.0)
	running = true
	if _player:
		_player.platform_mode = true
		_player_scale = _player.scale
	_pos = config.spawn
	_pet = _pos + Vector2(-config.pet_gap, config.pet_foot)
	_face = 1.0
	_dir = "right"
	_room_music.play()
	_room_a = 0.0
	create_tween().tween_property(self, "_room_a", 1.0, 1.0)
	_go(Stage.ROOM)
	Game.input_locked = false

func stop() -> void:
	running = false
	for v in [_server, _transition, _glitch]:
		if v:
			(v as VideoStreamPlayer).stop()
	for m in [_room_music, _battle_music]:
		if m:
			(m as AudioStreamPlayer).stop()
	if _player and is_instance_valid(_player):
		_player.platform_mode = false
		_player.modulate.a = 1.0
		_player.scale = _player_scale

func _go(s: Stage) -> void:
	_stage = s
	_stage_t = 0.0

func _mine() -> bool:
	return Game.active_world == world_id and not Game.input_locked

func _process(delta: float) -> void:
	if not _built:
		return
	if _camera and is_instance_valid(_camera):
		_cam = _camera.position
	var dt := minf(delta, 1.0 / 30.0)
	_t += dt
	_stage_t += dt
	_hf_flash = maxf(_hf_flash - dt, 0.0)
	_phase_flash = maxf(_phase_flash - dt, 0.0)
	_shown_health = lerpf(_shown_health, float(_health), 1.0 - exp(-8.0 * dt))
	if running:
		match _stage:
			Stage.ROOM:
				_walk_room(dt, false)
				if _room_a >= 0.9 and _mine() and Input.is_action_just_pressed("Interact") and _pos.distance_to(config.hf_pos) < config.talk_range:
					_begin_transition()
			Stage.TRANSITION:
				_tick_transition()
			Stage.BATTLE:
				_tick_battle(dt)
			Stage.BITE:
				_tick_bite(dt)
			Stage.FLASH:
				_tick_flash()
			Stage.DOOR_ROOM:
				_walk_room(dt, true)
				if _mine() and Input.is_action_just_pressed("Interact") and _pos.distance_to(config.door_way + Vector2(0, 100)) < config.talk_range:
					_go(Stage.UNLOCK)
					if _player:
						_player.set_motion(false, "up")
			Stage.UNLOCK:
				_tick_unlock()
			Stage.ENTER:
				_tick_enter(dt)
			Stage.GLITCH:
				pass
		_follow_pet(dt)
	_bar_a = move_toward(_bar_a, 1.0 if _stage in [Stage.BATTLE, Stage.BITE] else 0.0, dt * 2.5)
	_place()
	_redraw()

# ---------------------------------------------------------------- the white room
func _walk_room(dt: float, door: bool) -> void:
	var dir := Vector2.ZERO
	if _mine():
		if Input.is_action_pressed("ui_right"):
			dir = Vector2.RIGHT
			_dir = "right"
		elif Input.is_action_pressed("ui_left"):
			dir = Vector2.LEFT
			_dir = "left"
		elif Input.is_action_pressed("ui_down"):
			dir = Vector2.DOWN
			_dir = "down"
		elif Input.is_action_pressed("ui_up"):
			dir = Vector2.UP
			_dir = "up"
	if dir.x != 0.0:
		_face = dir.x
	if dir != Vector2.ZERO:
		var next := _pos + dir * config.walk_speed * dt
		var r := config.walk_rect
		next.x = minf(maxf(next.x, minf(_pos.x, r.position.x)), maxf(_pos.x, r.end.x))
		next.y = minf(maxf(next.y, minf(_pos.y, r.position.y)), maxf(_pos.y, r.end.y))
		if not door:
			var d_now := _pos.distance_to(config.hf_pos)
			if next.distance_to(config.hf_pos) >= config.keep_clear or next.distance_to(config.hf_pos) >= d_now:
				_pos = next
		elif not _door_block().has_point(next) or _door_block().has_point(_pos):
			_pos = next
	if _player:
		_player.set_motion(dir != Vector2.ZERO, _dir)

# The door stands on the wall; the character can't walk over it.
func _door_block() -> Rect2:
	var t := config.door_texture
	var size := t.get_size() if t else Vector2(284, 615)
	return Rect2(config.door_pos + Vector2(20, 0), Vector2(size.x - 20, 470)).grow(40.0)

func _begin_transition() -> void:
	_go(Stage.TRANSITION)
	if _player:
		_player.set_motion(false, "right")
	_transition.visible = false   # shown once the first frames are decoded (see _tick_transition)
	_transition.play()
	var tw := create_tween()
	tw.tween_property(_room_music, "volume_db", -60.0, 1.2)
	tw.tween_callback(_room_music.stop)

func _transition_time() -> float:
	return _transition.stream_position if _transition.is_playing() else _stage_t

func _tick_transition() -> void:
	# the picture runs a few frames behind the clock and starts out black; the
	# video opens on white, so nothing is lost by waiting for it
	if not _transition.visible and _transition_time() >= 0.1:
		_transition.visible = true
	if _stage_t > 0.3 and not _transition.is_playing() or _stage_t > 3.0:
		_transition.stop()
		_transition.visible = false
		_begin_battle()

# ---------------------------------------------------------------- the fight
func _begin_battle() -> void:
	_go(Stage.BATTLE)
	_clusters.clear()
	_lasers.clear()
	_phase = 1
	_hits = 0
	_health = config.health
	_shown_health = float(_health)
	_make_start()
	_spawn_on(_clusters[0], config.start_x)
	_hf = Vector2(_pos.x + config.lead.x + 100.0, _pos.y)
	_hf_goal_y = _hf.y
	_pet = _pos + Vector2(-config.pet_gap, config.pet_foot)
	_server.visible = true
	_server.play()
	_black = 1.0
	create_tween().tween_property(self, "_black", 0.0, 0.5)
	_battle_music.volume_db = config.music_db
	_battle_music.play()
	_beat_floor = -999
	_beats = 0
	_scroll = config.window.x * 0.5
	_scroll_wait = config.scroll_delay

func _vis_top() -> float:
	return _view().position.y

func _vis_bottom() -> float:
	return _view().end.y

func _fall_y() -> float:
	return _vis_bottom() + 220.0

func _top_range() -> Vector2:
	var a := _vis_top()
	var b := _vis_bottom()
	return Vector2(lerpf(a, b, config.top_band.x), lerpf(a, b, config.top_band.y))

func _make_start() -> void:
	var c := Cluster.new()
	var top := lerpf(_top_range().x, _top_range().y, 0.6)
	c.x0 = -400.0
	c.x1 = 1050.0
	c.top = top
	c.boxes.append(Rect2(-400, top, 1450, 420))
	c.boxes.append(Rect2(-360, top + 34, 1310, 380))
	c.boxes.append(Rect2(560, top - 22, 420, 150))
	_clusters.append(c)

# Glitched boxes on ahead of the camera, and dropped once well behind it.
func _generate() -> void:
	var v := _view()
	while _clusters.back().x1 < v.end.x + 2200.0:
		_clusters.append(_next_cluster(_clusters.back()))
	while _clusters.size() > 2 and _clusters[1].x1 < v.position.x - 2600.0:
		_clusters.pop_front()

func _next_cluster(prev: Cluster) -> Cluster:
	var c := Cluster.new()
	var rng := _top_range()
	c.top = clampf(prev.top + _rng.randf_range(-config.step_up, config.step_down), rng.x, rng.y)
	# the higher the next top, the less of the jump is left for going across
	var climb := clampf((prev.top - c.top) / maxf(config.step_up, 1.0), 0.0, 1.0)
	var widest := lerpf(config.gap.y, config.climb_gap, climb)
	c.x0 = prev.x1 + _rng.randf_range(minf(config.gap.x, widest), widest)
	var w := _rng.randf_range(config.cluster_width.x, config.cluster_width.y)
	c.x1 = c.x0 + w
	c.boxes.append(Rect2(c.x0, c.top, w, _rng.randf_range(150.0, 450.0)))
	var extra := _rng.randi_range(config.extra_boxes.x, config.extra_boxes.y)
	for i in extra:
		if _rng.randf() < 0.25:
			# a thin bar laid across, like the ledges in the key level
			var bw := _rng.randf_range(w * 0.5, w * 0.95)
			c.boxes.append(Rect2(c.x0 + _rng.randf_range(-40.0, w - bw + 40.0), c.top + _rng.randf_range(-30.0, 30.0), bw, 40.0))
		else:
			var bw2 := _rng.randf_range(w * 0.55, w * 1.0)
			var bx := clampf(c.x0 + _rng.randf_range(-60.0, w - bw2 + 60.0), c.x0 - 60.0, c.x1 + 60.0 - bw2)
			c.boxes.append(Rect2(bx, c.top + _rng.randf_range(-30.0, 45.0), bw2, _rng.randf_range(140.0, 446.0)))
	return c

func _spawn_on(c: Cluster, x: float) -> void:
	_pos = Vector2(clampf(x, c.x0 + config.half_width, c.x1 - config.half_width), c.top - config.feet)
	_vel = Vector2.ZERO
	_grounded = true
	_coyote = 0.0
	_buffer = 0.0
	_cut = false

# The top of whatever is under x (the highest one), or INF.
func _top_at(x: float) -> float:
	var best := INF
	for c in _clusters:
		if x < c.x0 - 80.0 or x > c.x1 + 80.0:
			continue
		for r in c.boxes:
			if x >= r.position.x and x <= r.end.x:
				best = minf(best, r.position.y)
	return best

func _tick_battle(dt: float) -> void:
	# the screen moves on whether you keep up or not; run ahead and it follows
	_scroll_wait = maxf(_scroll_wait - dt, 0.0)
	if _scroll_wait <= 0.0:
		_scroll += (config.scroll_speed.x if _phase == 1 else config.scroll_speed.y) * dt
	_scroll = maxf(_scroll, _pos.x + config.look_ahead)
	_generate()
	_tick_beat()
	_hurt = maxf(_hurt - dt, 0.0)
	_player_alpha = 0.35 if _hurt > 0.0 and fmod(_t, 0.16) < 0.08 else 1.0
	if _dead > 0.0:
		_dead -= dt
		if _dead <= 0.0:
			_respawn_after_fall()
	else:
		_step(dt)
		_tick_shot(dt)
	_tick_hf(dt)
	_tick_lasers(dt)

func _step(dt: float) -> void:
	var move := 0.0
	var jump_held := false
	if _mine():
		if Input.is_action_pressed("ui_right"):
			move += 1.0
		if Input.is_action_pressed("ui_left"):
			move -= 1.0
		jump_held = Input.is_action_pressed("ui_up") or Input.is_action_pressed("ui_accept")
		if Input.is_action_just_pressed("ui_up") or Input.is_action_just_pressed("ui_accept"):
			_buffer = config.jump_buffer
	if _hurt > config.hurt_time - 0.3:
		_vel.x = lerpf(_vel.x, move * config.move_speed, 1.0 - exp(-4.0 * dt))   # the knock carries you a moment
	else:
		_vel.x = move * config.move_speed
	if move != 0.0:
		_face = signf(move)

	_coyote = maxf(_coyote - dt, 0.0)
	_buffer = maxf(_buffer - dt, 0.0)
	if _buffer > 0.0 and (_grounded or _coyote > 0.0):
		_vel.y = -config.jump_speed
		_grounded = false
		_coyote = 0.0
		_buffer = 0.0
		_cut = false
	if not jump_held and _vel.y < 0.0 and not _cut:
		_vel.y *= config.short_hop
		_cut = true

	_vel.y += config.gravity * dt
	_pos.x = maxf(_pos.x + _vel.x * dt, _view().position.x + config.half_width)

	var was_feet := _pos.y + config.feet
	_pos.y += _vel.y * dt
	var feet := _pos.y + config.feet
	var landed := false
	if _vel.y >= 0.0:
		for c in _clusters:
			if _pos.x + config.half_width <= c.x0 - 80.0 or _pos.x - config.half_width >= c.x1 + 80.0:
				continue
			for r in c.boxes:
				if _pos.x + config.half_width <= r.position.x or _pos.x - config.half_width >= r.end.x:
					continue
				if was_feet <= r.position.y + LAND_TOLERANCE and feet >= r.position.y:
					_pos.y = r.position.y - config.feet
					_vel.y = 0.0
					landed = true
					break
			if landed:
				break
	if landed:
		_grounded = true
		_coyote = config.coyote_time
		_cut = false
	else:
		if _grounded:
			_coyote = config.coyote_time
		_grounded = false

	if _player and _shot_t < 0.0:
		_player.set_motion(absf(_vel.x) > 1.0, "right" if _face >= 0.0 else "left")

	if _pos.y > _fall_y():
		_fell()

# Off the bottom: Hugging Face gets back to where the phase started.
func _fell() -> void:
	_dead = config.respawn_delay
	_shot_t = -1.0
	_lasers.clear()
	_hits = 0
	_health = config.health if _phase == 1 else config.health - config.phase_one_hits
	_hf_flash = 0.4
	Game.say_random("platform_fall")

func _respawn_after_fall() -> void:
	var v := _view()
	var want := v.position.x + v.size.x * 0.22
	var pick: Cluster = _clusters[0]
	for c in _clusters:
		if c.x1 - config.half_width > want:
			pick = c
			break
	_spawn_on(pick, maxf(want, pick.x0 + 60.0))
	_hurt = 0.8

# ---------------------------------------------------------------- the water
func _muzzle() -> Vector2:
	return _pos + Vector2(config.muzzle.x * _face, config.muzzle.y)

func _hf_half() -> Vector2:
	var t := config.hf_texture
	var h := config.hf_width * (t.get_height() / float(t.get_width()) if t else 0.93)
	return Vector2(config.hf_width, h) * 0.5

func _level_with_hf() -> bool:
	return absf((_pos.y + config.feet) - (_hf_goal_y + _hf_half().y)) <= config.line_tolerance

func _tick_shot(dt: float) -> void:
	_shot_pause = maxf(_shot_pause - dt, 0.0)
	if _shot_t >= 0.0:
		_shot_t += dt
		var reach := _shot_t * config.beam_speed
		if not _shot_done and _shot_reach >= 0.0 and reach >= _shot_reach:
			_shot_done = true
			# the last hit is the mouse's: water that would land then bounces off too
			var mouse_turn := _phase == 2 and _hits >= config.phase_two_hits and _pet_tex != null
			if _phase == 2 and (_shielded() or mouse_turn):
				_shot_kind = "block"
				_shot_reach = maxf(_hf.x - 135.0 - _muzzle().x, 0.0)
			else:
				_shot_kind = "hit"
				_damage()
		if _shot_t >= config.shot_time:
			_shot_t = -1.0
			_shot_pause = config.shot_pause
		return
	if _shot_pause > 0.0 or not _mine() or not Input.is_action_just_pressed("Interact"):
		return
	var toward := _face > 0.0 and _hf.x > _pos.x
	if _phase == 2 and _hits >= config.phase_two_hits and toward and _level_with_hf() and not _shielded() and _pet_tex:
		_begin_bite()
		return
	_shot_t = 0.0
	_shot_dir = _face
	_shot_done = false
	_shot_kind = ""
	_shot_reach = -1.0
	if toward and _level_with_hf():
		_shot_reach = maxf(_hf.x - _hf_half().x * 0.6 - _muzzle().x, 0.0)
	if _player:
		_player.set_motion(false, "right" if _face > 0.0 else "left")

func _damage() -> void:
	_health = maxi(_health - 1, 0)
	_hits += 1
	_hf_flash = 0.3
	_hf.x += 60.0
	if _phase == 1 and _hits >= config.phase_one_hits:
		_phase = 2
		_hits = 0
		_phase_flash = 1.0
		_beats = 0
	elif _health <= 0:
		_white_out()     # no mouse to finish it: the water does

func _white_out() -> void:
	_lasers.clear()
	_go(Stage.FLASH)
	var tw := create_tween()
	tw.tween_property(self, "_white", 1.0, 0.3)
	tw.parallel().tween_property(_battle_music, "volume_db", -60.0, 0.8)

# ---------------------------------------------------------------- the beat
func _beat_period() -> float:
	return 60.0 / maxf(config.bpm, 1.0)

# Beats into the song, from where the music has actually got to.
func _song_beats() -> float:
	if not _battle_music.playing:
		return _stage_t / _beat_period()
	var pos := _battle_music.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()
	return (pos - config.beat_offset) / _beat_period()

# The umbrella is out in front for a stretch around every beat.
# The umbrella stays out in front, and comes down once every lower_every
# beats, for lower_for of a beat around the off-beat before the next one.
func _shielded() -> bool:
	var every := maxf(config.lower_every, 1.0)
	var ph := fposmod(_song_beats(), every)
	return absf(ph - (every - 0.5)) > config.lower_for * 0.5

func _tick_beat() -> void:
	var f := floori(_song_beats())
	if f == _beat_floor:
		return
	_beat_floor = f
	_beats += 1
	if _phase == 2 and _phase_flash <= 0.0 and _dead <= 0.0 and _beats % maxi(config.attack_every, 1) == 0:
		_spawn_volley()

# ---------------------------------------------------------------- the lasers
func _spawn_volley() -> void:
	var v := _view()
	var me := _pos - v.position             # where the character is on screen
	var hf := _hf - v.position
	var w := config.beam_width
	var kinds := ["row", "rain", "aimed", "cross"]
	match kinds[_rng.randi() % kinds.size()]:
		"row":
			# straight across at the character's height, out of Hugging Face's side
			_add_laser(Vector2(v.size.x, me.y), Vector2.LEFT, w)
		"rain":
			var xs := [me.x, me.x + _rng.randf_range(260.0, 420.0) * (1.0 if _rng.randf() < 0.5 else -1.0)]
			for x in xs:
				_add_laser(Vector2(clampf(float(x), 80.0, v.size.x - 80.0), 0.0), Vector2.DOWN, w)
		"aimed":
			_add_laser(hf, (me - hf).normalized(), w)
		"cross":
			_add_laser(Vector2(v.size.x, me.y), Vector2.LEFT, w * 0.85)
			_add_laser(Vector2(clampf(me.x + _rng.randf_range(-200.0, 200.0), 80.0, v.size.x - 80.0), 0.0), Vector2.DOWN, w * 0.85)

func _add_laser(p: Vector2, d: Vector2, w: float) -> void:
	var l := Laser.new()
	l.p = p
	l.d = d
	l.w = w
	var span := _clip(p, d)
	if span.x < span.y:
		var at := p + d * (maxf(span.x, 0.0) + 70.0)
		var size := _view().size
		var below_bar := config.bar_margin + _bar_height() + 70.0
		l.icon = Vector2(clampf(at.x, 60.0, size.x - 60.0), clampf(at.y, below_bar, size.y - 60.0))
	_lasers.append(l)

# The stretch of a ray (as distances along d from p) that is on screen.
func _clip(p: Vector2, d: Vector2) -> Vector2:
	var size := _view().size
	var t0 := 0.0
	var t1 := LONG
	for axis in 2:
		var pa := p[axis]
		var da := d[axis]
		var hi: float = size[axis]
		if absf(da) < 0.00001:
			if pa < 0.0 or pa > hi:
				return Vector2(1.0, 0.0)
			continue
		var ta := (0.0 - pa) / da
		var tb := (hi - pa) / da
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
	return Vector2(t0, t1)

func _warn_time() -> float:
	return config.warn_beats * _beat_period()

func _fire_time() -> float:
	return config.fire_beats * _beat_period()

# How far along its length a laser has shot, 0 to 1.
func _laser_out(l: Laser) -> float:
	var ft := l.t - _warn_time()
	if ft < 0.0:
		return 0.0
	return clampf(ft / maxf(config.laser_grow, 0.01), 0.0, 1.0)

func _tick_lasers(dt: float) -> void:
	var gone: Array[Laser] = []
	for l in _lasers:
		l.t += dt
		if l.t > _warn_time() + _fire_time() + 0.35:
			gone.append(l)
	for l in gone:
		_lasers.erase(l)
	if _hurt > 0.0 or _dead > 0.0:
		return
	var me := _pos - _view().position
	for l in _lasers:
		var out := _laser_out(l)
		if out <= 0.0 or l.t > _warn_time() + _fire_time():
			continue
		var span := _clip(l.p, l.d)
		var reach := lerpf(maxf(span.x, 0.0), span.y, out)
		var v := me - l.p
		var along := v.dot(l.d)
		if along < -config.half_width or along > reach + config.half_width:
			continue
		if absf(v.cross(l.d)) < l.w * 0.5 + config.half_width * 0.6:
			_knocked()
			return

func _knocked() -> void:
	_hurt = config.hurt_time
	_vel = config.knockback
	_grounded = false
	Game.say_random("laser_hit")

# ---------------------------------------------------------------- Hugging Face
func _tick_hf(dt: float) -> void:
	var right := _scroll + config.window.x * 0.5
	var hi := minf(_pos.x + config.lead.y, right - 130.0)
	var lo := minf(maxf(_pos.x + config.lead.x, right - 560.0), hi)
	_hf.x = clampf(_hf.x + config.run_speed * dt, lo, hi)
	var top := _top_at(_hf.x)
	if top < INF:
		_hf_goal_y = top - _hf_half().y
	_hf.y = lerpf(_hf.y, _hf_goal_y, 1.0 - exp(-7.0 * dt))

# ---------------------------------------------------------------- the bite
func _begin_bite() -> void:
	_go(Stage.BITE)
	_lasers.clear()
	_bite_from = _pet
	_bite_t = 0.0
	_hurt = 0.0
	_player_alpha = 1.0
	if _player:
		_player.set_motion(false, "right")

func _tick_bite(dt: float) -> void:
	_bite_t += dt
	_tick_hf(dt * 0.3)
	var lunge := config.lunge_time
	if _bite_t < lunge:
		var k := ease(_bite_t / lunge, 0.4)
		var to := _hf + Vector2(-_hf_half().x * 0.55, 10.0)
		_pet = _bite_from.lerp(to, k) + Vector2(0.0, -sin(k * PI) * 160.0)
	if _bite_t >= lunge and _health > 0:
		_health = 0
		_hf_flash = 1.2
	if _bite_t >= lunge + 0.9:
		_white_out()

func _bite_frame() -> int:
	return clampi(int(_bite_t / maxf(config.bite_frame, 0.01)), 0, 3)

# ---------------------------------------------------------------- back in the white room
func _tick_flash() -> void:
	if _stage_t < 0.45 or _white < 0.99:
		return
	# everything swaps over while the screen is white
	_battle_music.stop()
	_server.stop()
	_server.visible = false
	_clusters.clear()
	_lasers.clear()
	_hf_visible = false
	_pos = config.spawn
	_face = 1.0
	_dir = "right"
	_vel = Vector2.ZERO
	_hurt = 0.0
	_player_alpha = 1.0
	_pet = _pos + Vector2(-config.pet_gap, config.pet_foot)
	if _camera and is_instance_valid(_camera):
		_camera.position = _arena.get_center()
		_cam = _camera.position
	_room_music.volume_db = config.music_db
	_room_music.play()
	_go(Stage.DOOR_ROOM)
	create_tween().tween_property(self, "_white", 0.0, 0.7)

func _tick_unlock() -> void:
	_key_t = _stage_t
	if _stage_t >= 0.95 and not _door_open:
		_door_open = true
	if _stage_t >= 1.35:
		_go(Stage.ENTER)

func _tick_enter(dt: float) -> void:
	var goal := config.door_way
	var step := config.walk_speed * dt
	if absf(_pos.x - goal.x) > 2.0:
		_dir = "right" if goal.x > _pos.x else "left"
		_pos.x = move_toward(_pos.x, goal.x, step)
		if _player:
			_player.set_motion(true, _dir)
	elif absf(_pos.y - goal.y) > 2.0:
		_dir = "up"
		_pos.y = move_toward(_pos.y, goal.y, step)
		if _player:
			_player.set_motion(true, _dir)
	else:
		if _player:
			_player.set_motion(false, "up")
		_player_alpha = move_toward(_player_alpha, 0.0, dt * 2.5)
		if _player_alpha <= 0.0:
			_go(Stage.GLITCH)
			_room_music.stop()
			_glitch.visible = true
			_glitch.finished.connect(_on_glitch_done, CONNECT_ONE_SHOT)
			_glitch.play()

func _on_glitch_done() -> void:
	_go(Stage.DONE)
	running = false
	finished.emit(true)

# ---------------------------------------------------------------- the pet
func _follow_pet(dt: float) -> void:
	_pet_t += dt
	if _stage == Stage.BITE:
		return
	var fade := 1.0 if _stage != Stage.ENTER else _player_alpha
	if fade <= 0.0:
		return
	var target: Vector2
	if _in_white_room():
		target = _pos + Vector2(0.0, config.pet_foot)
		var to := target - _pet
		var d := to.length()
		if d > config.pet_gap:
			var stp := minf((d - config.pet_gap) * 6.0 + 60.0, 620.0) * dt
			_pet += to.normalized() * minf(stp, d - config.pet_gap)
			if absf(to.x) > 8.0:
				_pet_flip = to.x > 0.0
	else:
		# over the glitch it keeps up just behind, floating where there's no box
		target = _pos + Vector2(-config.pet_gap * _face, config.pet_foot)
		_pet = _pet.lerp(target, 1.0 - exp(-6.0 * dt))
		_pet_flip = _face > 0.0

# ---------------------------------------------------------------- drawing
func _draw() -> void:
	if not _built or _expand < 0.999:
		return
	var pic := Rect2(_to_room(Vector2.ZERO), config.window * _s)
	if _in_white_room():
		draw_rect(Rect2(_cam - _arena.size, _arena.size * 2.0), Color.WHITE)
		if config.backdrop:
			draw_texture_rect(config.backdrop, pic, false, Color(1, 1, 1, _room_a))
		if _stage in [Stage.DOOR_ROOM, Stage.UNLOCK, Stage.ENTER, Stage.GLITCH, Stage.DONE]:
			_draw_door(self)
	else:
		draw_rect(Rect2(_cam - _arena.size, _arena.size * 2.0), Color.BLACK)

func _draw_door(ci: CanvasItem) -> void:
	var tex := config.door_open_texture if _door_open else config.door_texture
	if tex == null:
		return
	var at := config.door_open_pos if _door_open else config.door_pos
	ci.draw_texture_rect(tex, Rect2(_to_room(at), tex.get_size() * _s), false)

func _draw_back() -> void:
	if not _built or _expand < 0.999 or _pet_tex == null or _stage == Stage.BITE:
		return
	if _stage in [Stage.GLITCH, Stage.DONE]:
		return
	var a := _player_alpha if _stage == Stage.ENTER else 1.0
	var w := config.pet_width
	var h := w * _pet_tex.get_height() / float(_pet_tex.get_width())
	var moving := _stage in [Stage.ROOM, Stage.DOOR_ROOM, Stage.BATTLE, Stage.ENTER]
	var rot := sin(_pet_t * 14.0) * 0.035 if moving else 0.0
	_back.draw_set_transform(_to_room(_pet), rot, Vector2((-1.0 if _pet_flip else 1.0) * _s, _s))
	_back.draw_texture_rect(_pet_tex, Rect2(-w * 0.5, -h * 0.5, w, h), false, Color(1, 1, 1, a))
	_back.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _hf_tint() -> Color:
	var blink := _hf_flash > 0.0 and fmod(_t, 0.1) < 0.05
	blink = blink or _phase_flash > 0.0 and fmod(_t, 0.14) < 0.07
	return Color(4, 4, 4, 1) if blink else Color.WHITE

func _draw_front() -> void:
	if not _built or _expand < 0.999:
		return
	match _stage:
		Stage.ROOM, Stage.TRANSITION:
			_draw_hf(config.hf_pos, false, _room_a)
			_draw_gun()
		Stage.BATTLE, Stage.BITE, Stage.FLASH:
			if _hf_visible:
				_draw_hf(_hf + Vector2(0.0, -absf(sin(_t * 7.0)) * 14.0), _phase == 2)
			if _stage == Stage.BATTLE:
				_draw_water()
				_draw_gun()
				_draw_lasers()
			if _stage == Stage.BITE:
				_draw_bite()
		Stage.DOOR_ROOM, Stage.UNLOCK:
			_draw_key()

func _draw_hf(at: Vector2, umbrella: bool, alpha := 1.0) -> void:
	var tint := _hf_tint()
	tint.a = alpha
	if umbrella and _phase_flash < 0.5:
		var shield := _shielded()
		var tex := config.umbrella_block if shield else config.umbrella_up
		if tex:
			# the face in the umbrella pictures sits here, at about the plain one's size
			var mid := Vector2(179.5, 174.0) if shield else Vector2(174.5, 181.5)
			var k := (config.hf_width * 0.93) / (161.0 if shield else 173.0)
			var size := tex.get_size() * k
			_front.draw_texture_rect(tex, Rect2(_to_room(at - mid * k), size * _s), false, tint)
			return
	var t := config.hf_texture
	if t == null:
		return
	var half := _hf_half()
	_front.draw_texture_rect(t, Rect2(_to_room(at - half), half * 2.0 * _s), false, tint)

func _draw_gun() -> void:
	if config.gun_texture == null or _player_alpha < 0.5 and _stage != Stage.BATTLE:
		return
	var side := _face
	var gw := config.gun_width
	var gh := gw * config.gun_texture.get_height() / float(config.gun_texture.get_width())
	var at := _to_room(_pos + Vector2(config.gun_offset.x * side, config.gun_offset.y))
	_front.draw_set_transform(at, 0.0, Vector2(-side * _s, _s))
	_front.draw_texture_rect(config.gun_texture, Rect2(-gw * 0.5, -gh * 0.5, gw, gh), false, Color(1, 1, 1, _player_alpha))
	_front.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_water() -> void:
	if _shot_t < 0.0 or config.beam_texture == null:
		return
	var tex := config.beam_texture
	var reach := minf(_shot_t * config.beam_speed, _view().size.x * 1.2)
	if _shot_done and _shot_reach >= 0.0:
		reach = minf(reach, _shot_reach)
	var a := 1.0
	var tail := config.shot_time - 0.15
	if _shot_t > tail:
		a = clampf(1.0 - (_shot_t - tail) / 0.15, 0.0, 1.0)
	var tw := float(tex.get_width())
	var th := float(tex.get_height())
	_front.draw_set_transform(_to_room(_muzzle()), 0.0, Vector2(_shot_dir * _s, _s))
	var x := 0.0
	var off := fposmod(-_t * config.beam_flow, tw)
	while x < reach:
		var seg := minf(tw - off, reach - x)
		_front.draw_texture_rect_region(tex, Rect2(x, -config.beam_height * 0.5, seg, config.beam_height),
				Rect2(off, 0.0, seg, th), Color(1, 1, 1, a))
		x += seg
		off = 0.0
	if _shot_kind == "block":
		# it splashes back off the umbrella
		for i in 6:
			var ang := PI + (float(i) - 2.5) * 0.35
			var r := 30.0 + fmod(_shot_t * 600.0 + i * 13.0, 70.0)
			_front.draw_circle(Vector2(reach, 0.0) + Vector2.from_angle(ang) * r, 9.0, Color(0.75, 0.9, 1.0, a * 0.8))
	_front.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_lasers() -> void:
	var origin := _view().position
	var face := config.laser_face
	for l in _lasers:
		var span := _clip(l.p, l.d)
		if span.x >= span.y:
			continue
		var start := maxf(span.x, 0.0)
		var n := l.d.orthogonal() * l.w * 0.5
		if l.t < _warn_time():
			var k := l.t / _warn_time()
			var a := 0.85 * smoothstep(0.0, 0.2, k)
			var p0 := origin + l.p + l.d * start
			var p1 := origin + l.p + l.d * span.y
			var ring := PackedVector2Array([_to_room(p0 + n), _to_room(p1 + n), _to_room(p1 - n), _to_room(p0 - n), _to_room(p0 + n)])
			_front.draw_polyline(ring, Color(1.0, 0.8, 0.1, a), 3.0)
			if config.warning_icon:
				var blink := 0.55 + 0.45 * (0.5 + 0.5 * sin(l.t * TAU * 3.5))
				var sz := Vector2.ONE * 90.0 * _s
				_front.draw_texture_rect(config.warning_icon, Rect2(_to_room(origin + l.icon) - sz * 0.5, sz), false, Color(1, 1, 1, blink))
			continue
		if face == null:
			continue
		var out := _laser_out(l)
		var fade := 1.0
		var end_t := _warn_time() + _fire_time()
		if l.t > end_t:
			fade = clampf(1.0 - (l.t - end_t) / 0.35, 0.0, 1.0)
		var reach := lerpf(start, span.y, out)
		# a stack of faces from where it came in to its head, the head drawn last
		var size := Vector2(l.w, l.w * face.get_height() / float(face.get_width()))
		var d := start
		while d <= reach:
			var c := origin + l.p + l.d * d
			_front.draw_texture_rect(face, Rect2(_to_room(c - size * 0.5), size * _s), false, Color(1, 1, 1, fade))
			d += config.face_spacing

func _draw_bite() -> void:
	if _pet_idx < 0 or _pet_idx >= config.rat_attacks.size():
		return
	var sheet := config.rat_attacks[_pet_idx]
	if sheet == null:
		return
	var f := _bite_frame()
	var w := config.bite_width
	var shake := Vector2(sin(_t * 90.0), cos(_t * 70.0)) * 6.0 if f == 3 else Vector2.ZERO
	# the picture faces left; Hugging Face is to the right
	_front.draw_set_transform(_to_room(_pet + shake), 0.0, Vector2(-_s, _s))
	_front.draw_texture_rect_region(sheet, Rect2(-w * 0.5, -w * 0.5, w, w), Rect2(f * RAT_FRAME, 0.0, RAT_FRAME, RAT_FRAME))
	_front.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_key() -> void:
	if _stage != Stage.UNLOCK or config.key_texture == null:
		return
	var t := _stage_t
	var from := _pos + Vector2(0.0, -200.0)
	var to := config.door_handle
	var at := from.lerp(to, ease(clampf(t / 0.6, 0.0, 1.0), -2.0))
	var rot := clampf((t - 0.6) / 0.3, 0.0, 1.0) * PI * 0.5
	var a := 1.0 - clampf((t - 1.0) / 0.25, 0.0, 1.0)
	var kw := 120.0
	var kh := kw * config.key_texture.get_height() / float(config.key_texture.get_width())
	_front.draw_set_transform(_to_room(at), rot, Vector2(_s, _s))
	# the key's teeth go into the handle, so its tip is what reaches it
	_front.draw_texture_rect(config.key_texture, Rect2(-kw * 0.9, -kh * 0.5, kw, kh), false, Color(1, 1, 1, a))
	_front.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _bar_height() -> float:
	var t := config.hp_bar
	return config.bar_width * (t.get_height() / float(t.get_width()) if t else 0.094)

func _draw_hud() -> void:
	if _bar_a <= 0.0 or not _built or config.hp_bar == null:
		return
	var v := _view()
	var size := Vector2(config.bar_width, _bar_height())
	var top := Vector2(v.position.x + (v.size.x - size.x) * 0.5, v.position.y + config.bar_margin + (1.0 - _bar_a) * -40.0)
	var a := _bar_a
	var k := config.bar_width / float(config.hp_bar.get_width())
	var share := clampf(_shown_health / float(maxi(config.health, 1)), 0.0, 1.0)
	# the empty bar, then a cell for every bit of health left: blue, red near the end
	_hud.draw_texture_rect(config.hp_bar, Rect2(_to_room(top), size * _s), false, Color(1, 1, 1, a))
	var cells := ceili(config.hp_cells * share - 0.01)
	var col := config.cell_low_color if share <= config.low_share + 0.001 else config.cell_color
	col.a = a
	for i in cells:
		var at := top + (config.cell_first + Vector2(config.cell_pitch * i, 0.0)) * k
		_hud.draw_rect(Rect2(_to_room(at), config.cell_size * k * _s), col)
	# and underneath, the number, counting down with the bar
	var f: Font = config.hp_font if config.hp_font else (config.font if config.font else ThemeDB.fallback_font)
	var text := ("Hugging Face HP: %d/%d" % [roundi(config.hp_number * share), config.hp_number]).to_upper()
	var fs := 32
	var fit := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	fs = maxi(int(fs * config.label_width * k / maxf(fit, 1.0)), 8)
	var base := top + Vector2(0.0, size.y + fs * 1.05)
	_hud.draw_string(f, _to_room(base), text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs * _s), Color(1, 1, 1, a))

# Drawn through the show-on-black shader, so it's only there in the black
# flashes. The glitching later on (and the black at the very end) has Hugging
# Face simply darkened, so it stops before then.
func _draw_blue() -> void:
	if _stage != Stage.TRANSITION or config.hf_blue == null or _transition_time() > 0.9:
		return
	var r := config.hf_blue_rect
	_blue.draw_texture_rect(config.hf_blue, Rect2(_to_room(r.position), r.size * _s), false)

func _draw_over() -> void:
	if not _built:
		return
	var r := Rect2(_cam - _arena.size, _arena.size * 2.0)
	if _black > 0.0:
		_over.draw_rect(r, Color(0, 0, 0, _black))
	if _white > 0.0:
		_over.draw_rect(r, Color(1, 1, 1, _white))
