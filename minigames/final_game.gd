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

enum Stage { WAITING, ROOM, TRANSITION, BATTLE, BITE, DYING, FLASH, DOOR_ROOM, UNLOCK, ENTER, GLITCH, DONE }

const DARKEN_SHADER := preload("res://shaders/darken.gdshader")
const EXCLUSION_SHADER := preload("res://shaders/exclusion.gdshader")
const SHOW_ON_BLACK := preload("res://shaders/show_on_black.gdshader")
const HOVER_SHADER := preload("res://shaders/hover_outline.gdshader")
const HOVER_WIDTH := 6.0       # the outline when Hugging Face or the door can be used, room units
const DYING_TIME := 1.4        # Hugging Face strobing out after the bite
const BITE_HOLD := 0.35        # the mouse hangs on after the last chomp
const ENTER_PAUSE := 1.0       # through the door, before the glitch
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
	var pushed := false        # it has kicked the character already

# The character's box (picture units), measured from where the bug is drawn
# (Player.bug_box); the config's numbers are only a fallback.
var _half_w := 70.0
var _feet := 120.0
var _head := 170.0

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
var _shove := 0.0          # a beam threw the character: steering comes back slowly
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
var _trail_health := 6.0   # the white cells left behind when it's hit, which drain after
var _trail_wait := 0.0
var _last_health := 6
var _phase := 1
var _scenes: Node2D                 # the rest of the game glitching through the background
var _glitches: Array[Dictionary] = []
var _glitch_due := 0.0
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
var _bite_t := 0.0         # how far the jump and bite have got, in the bite's own (slowed) time
var _freeze_t := 0.0       # real seconds since everything stopped
var _dim_a := 0.0          # the black over the background during the bite
var _dim: Node2D
var _player_z := 0

# the door
var _door_open := false
var _key_t := 0.0

# screen-wide
var _white := 0.0          # white over everything
var _red := 0.0            # the red flash when Hugging Face goes down
var _dying_t := 0.0
var _gun_t := 0.0          # the water gun popping into the character's hand
var _hover_a := 0.0        # the blue outline on Hugging Face (white room) or the door
var _prop: Node2D          # Hugging Face in the white room, and the door: under the character
var _hf_pad: Texture2D     # padded copies, so the outline has room around them
var _door_pad: Texture2D
var _hf_pad_px := 0
var _door_pad_px := 0
var _pause_t := 0.0
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
	_scenes = _make_layer(0, _draw_scenes)     # over the footage, under everything else
	_back = _make_layer(0, _draw_back)
	_prop = _make_layer(0, _draw_prop)
	var hover := ShaderMaterial.new()
	hover.shader = HOVER_SHADER
	_prop.material = hover
	if config.hf_texture:
		_hf_pad_px = ceili(HOVER_WIDTH * config.hf_texture.get_width() / config.hf_width) + 3
		_hf_pad = _padded(config.hf_texture, _hf_pad_px)
	if config.door_texture:
		_door_pad_px = ceili(HOVER_WIDTH) + 3
		_door_pad = _padded(config.door_texture, _door_pad_px)
	_build_boxes()
	_dim = _make_layer(2, _draw_dim)     # under _front: the background darkens, not the fight
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

# A copy of the picture with see-through margin all round.
func _padded(tex: Texture2D, pad: int) -> Texture2D:
	var img := tex.get_image()
	if img == null:
		return tex
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var out := Image.create(img.get_width() + pad * 2, img.get_height() + pad * 2, false, Image.FORMAT_RGBA8)
	out.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(pad, pad))
	return ImageTexture.create_from_image(out)

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
	if _in_white_room() or _stage == Stage.FLASH and _black >= 0.99:
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

	# the server footage covers the window (it's cut to the window's shape already,
	# so it shows nearly whole and close to its own size)
	var vid := Vector2(1440, 1440)
	var cover := maxf(_arena.size.x / vid.x, _arena.size.y / vid.y)
	_server.size = vid * cover
	_server.position = _cam - _server.size * 0.5
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
	for n in [_scenes, _back, _prop, _dim, _front, _hud, _blue, _over]:
		if n:
			(n as Node2D).queue_redraw()

# ---------------------------------------------------------------- running
# The box matches the bug as it's drawn: its feet stand on the boxes, its
# head bumps what it touches, and it hangs off an edge only as far as it looks.
func _fit_box() -> void:
	_half_w = config.half_width
	_feet = config.feet
	_head = config.head
	if _player and _player.has_method("bug_box") and _s > 0.0:
		var b: Rect2 = _player.call("bug_box")
		_half_w = b.size.x * 0.5 * 0.9 / _s     # a little forgiving at the sides
		_feet = b.end.y / _s
		_head = -b.position.y / _s

func start(cfg: MinigameConfig) -> void:
	if not _built:
		prepare(cfg)
	if not _built:
		finished.emit(true)
		return
	_camera = get_parent().get_node_or_null("Camera2D") as Camera2D
	set_expand(_arena, 1.0)
	_fit_box()
	running = true
	_pos = config.spawn
	if _player:
		_player.platform_mode = true
		_player_scale = _player.scale
		_player_z = _player.z_index
		# stay right where the button was pressed (inside the room's walls)
		var r := config.walk_rect
		var here := _from_room(_player.position)
		_pos = Vector2(clampf(here.x, r.position.x, r.end.x), clampf(here.y, r.position.y, r.end.y))
	_pet = _pos + Vector2(-config.pet_gap, config.pet_foot)
	var mouse_at: Variant = Pets.mouse_position()
	if mouse_at is Vector2:
		_pet = _from_room(mouse_at)     # and the mouse where it was too
	_face = 1.0
	_dir = "right"
	_room_music.play()
	Music.playing_own(_room_music.stream)
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
		_player.z_index = _player_z

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
	_tick_bar(dt)
	_tick_scenes(dt)
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
			Stage.DYING:
				_tick_dying(dt)
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
	var near := false
	if _stage == Stage.ROOM and _room_a >= 0.9:
		near = _pos.distance_to(config.hf_pos) < config.talk_range
	elif _stage == Stage.DOOR_ROOM:
		near = _pos.distance_to(config.door_way + Vector2(0, 100)) < config.talk_range
	_hover_a = move_toward(_hover_a, 1.0 if near else 0.0, dt / 0.1)
	if _stage == Stage.BATTLE:
		_gun_t += dt
	_bar_a = move_toward(_bar_a, 1.0 if _stage in [Stage.BATTLE, Stage.BITE, Stage.DYING] else 0.0, dt * 2.5)
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
	# the fight's music starts the moment you talk to it; the room's cuts out
	_room_music.stop()
	_battle_music.volume_db = config.music_db
	_battle_music.play()
	Music.playing_own(_battle_music.stream)

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
	_trail_health = _shown_health
	_last_health = _health
	_make_start()
	_spawn_on(_clusters[0], config.start_x)
	_hf = Vector2(_pos.x + config.lead.x + 100.0, _pos.y)
	_hf_goal_y = _hf.y
	_pet = _pos + Vector2(-config.pet_gap, config.pet_foot)
	_server.visible = true
	_server.play()
	_black = 1.0
	create_tween().tween_property(self, "_black", 0.0, 0.5)
	_beat_floor = -999
	_beats = 0
	_scroll = config.window.x * 0.5
	_scroll_wait = config.scroll_delay
	_gun_t = -0.45

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
	_pos = Vector2(clampf(x, c.x0 + _half_w, c.x1 - _half_w), c.top - _feet)
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
	_shove = maxf(_shove - dt, 0.0)
	if _shove > 0.0:
		# thrown: you drift, and only slowly get your steering back
		var grip := 1.5 + 8.0 * (1.0 - _shove / maxf(config.shove_time, 0.01))
		_vel.x = lerpf(_vel.x, move * config.move_speed, 1.0 - exp(-grip * dt))
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
	_pos.x = maxf(_pos.x + _vel.x * dt, _view().position.x + _half_w)

	var was_feet := _pos.y + _feet
	_pos.y += _vel.y * dt
	var feet := _pos.y + _feet
	var landed := false
	if _vel.y >= 0.0:
		for c in _clusters:
			if _pos.x + _half_w <= c.x0 - 80.0 or _pos.x - _half_w >= c.x1 + 80.0:
				continue
			for r in c.boxes:
				if _pos.x + _half_w <= r.position.x or _pos.x - _half_w >= r.end.x:
					continue
				if was_feet <= r.position.y + LAND_TOLERANCE and feet >= r.position.y:
					_pos.y = r.position.y - _feet
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
	Audio.play("fall_heal")
	Game.say_random("platform_fall")

func _respawn_after_fall() -> void:
	var v := _view()
	var want := v.position.x + v.size.x * 0.22
	var pick: Cluster = _clusters[0]
	for c in _clusters:
		if c.x1 - _half_w > want:
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
	return absf((_pos.y + _feet) - (_hf_goal_y + _hf_half().y)) <= config.line_tolerance

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
				Audio.play("umbrella_block")
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
	Audio.play("watergun_shot")
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
	Audio.play("hf_hit")
	if _phase == 1 and _hits >= config.phase_one_hits:
		Audio.play("umbrella_open")
		_phase = 2
		_hits = 0
		_phase_flash = 1.0
		_beats = 0
	elif _health <= 0:
		_white_out()     # no mouse to finish it: the water does

func _white_out() -> void:
	_begin_dying()

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
	Audio.play("laser_warning")           # the same alert as the laser maze
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
	var fired := false
	for l in _lasers:
		if l.t < _warn_time() and l.t + dt >= _warn_time():
			fired = true                      # the warning's over: it shoots
		l.t += dt
		if l.t > _warn_time() + _fire_time() + 0.35:
			gone.append(l)
	for l in gone:
		_lasers.erase(l)
	if fired:
		Audio.play("hf_lasers")               # once a volley, as the beams go live
	if _dead > 0.0:
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
		if along < -_half_w or along > reach + _half_w:
			continue
		var side := v.cross(l.d)
		if absf(side) < l.w * 0.5 + _half_w * 0.6:
			_pushed(l, side, dt)

# Caught in a beam: a kick the way it's going, out of its side and up, the
# first time, then a steady shove for as long as you stay in it.
func _pushed(l: Laser, side: float, dt: float) -> void:
	# out of the side you're already on (the normal of d, pointing your way)
	var aside := Vector2(-l.d.y, l.d.x) * (-1.0 if side > 0.0 else 1.0)
	if not l.pushed:
		l.pushed = true
		Audio.play("knocked_back")
		var kick := l.d * config.push_along + aside * config.push_aside + Vector2(0.0, -config.push_lift)
		kick.y = minf(kick.y, config.push_down_max)
		_vel = kick if _vel.y > 0.0 else _vel * 0.3 + kick
		_grounded = false
		_coyote = 0.0
	_vel += (l.d + aside * 0.5) * config.push_force * dt
	_vel.y = minf(_vel.y, config.push_down_max * 1.4)
	_shove = config.shove_time

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
# Everything stops; the background darkens; then the mouse jumps, in slow
# motion at first and up to full speed while it's in the air.
func _begin_bite() -> void:
	_go(Stage.BITE)
	_lasers.clear()
	_bite_from = _pet
	_bite_t = 0.0
	_freeze_t = 0.0
	_hurt = 0.0
	_player_alpha = 1.0
	if _player:
		_player.set_motion(false, "right")
		_player_z = _player.z_index
		_player.z_index = 3              # over the darkening, with the fight
	_server.paused = true
	_battle_music.stream_paused = true
	create_tween().tween_property(self, "_dim_a", config.dim, config.dim_time)

# How fast the bite's time runs: stopped, then slow, easing up to full speed.
func _bite_rate() -> float:
	var t := _freeze_t - config.freeze_time
	if t < 0.0:
		return 0.0
	var k := clampf(t / maxf(config.slow_ramp, 0.01), 0.0, 1.0)
	return lerpf(config.slow_start, 1.0, k * k * (3.0 - 2.0 * k))

func _tick_bite(dt: float) -> void:
	_freeze_t += dt
	var rate := _bite_rate()
	if rate <= 0.0:
		return
	if _battle_music.stream_paused:
		_battle_music.stream_paused = false
	if _bite_t < config.lunge_time:
		_battle_music.pitch_scale = maxf(rate, 0.05)     # the music drags with it
	elif _server.paused:
		_server.paused = false                       # it lands: back to normal
		_battle_music.pitch_scale = 1.0
	dt *= rate
	_bite_t += dt
	_tick_hf(dt * 0.3)
	var lunge := config.lunge_time
	if _bite_t < lunge:
		var k := ease(_bite_t / lunge, 0.4)
		var to := _hf + Vector2(-_hf_half().x * 0.55, 10.0)
		_pet = _bite_from.lerp(to, k) + Vector2(0.0, -sin(k * PI) * 160.0)
	# the whole bite plays out: jaws open on the way, then 1, 2, and the chomp on 3
	if _bite_frame() >= 3:
		_begin_dying()

# Mouth open (frame 0) for the jump, then 1, 2, 3 once it gets there.
func _bite_frame() -> int:
	if _bite_t < config.lunge_time:
		return 0
	return clampi(1 + int((_bite_t - config.lunge_time) / maxf(config.bite_frame, 0.01)), 1, 3)

# Hugging Face goes down: one red flash, then it strobes as it fades out, and
# the window goes to black.
func _begin_dying() -> void:
	if _stage == Stage.BITE:
		Audio.play("mouse_bite")         # the chomp
	Audio.play("hf_strobe")
	_go(Stage.DYING)
	_server.paused = false
	_battle_music.stream_paused = false
	_battle_music.pitch_scale = 1.0
	var undim := create_tween()
	undim.tween_property(self, "_dim_a", 0.0, 0.4)
	undim.tween_callback(func():
		if _player and is_instance_valid(_player):
			_player.z_index = _player_z)
	_lasers.clear()
	_health = 0
	_dying_t = 0.0
	_shot_t = -1.0
	_red = 0.65
	create_tween().tween_property(self, "_red", 0.0, 0.35)
	create_tween().tween_property(_battle_music, "volume_db", -60.0, DYING_TIME + 0.6)
	if _player:
		_player.set_motion(false, "right")

func _tick_dying(dt: float) -> void:
	_dying_t += dt
	if _dying_t >= DYING_TIME:
		_go(Stage.FLASH)
		create_tween().tween_property(self, "_black", 1.0, 0.6)

# Strobing, and fading under it.
func _hf_dying_alpha() -> float:
	if fmod(_dying_t, 0.12) >= 0.06:
		return 0.0
	return clampf(1.0 - _dying_t / DYING_TIME, 0.0, 1.0)

func _mouse_biting() -> bool:
	return _stage == Stage.BITE or _stage == Stage.DYING and _dying_t < BITE_HOLD and _bite_t > 0.0

# ---------------------------------------------------------------- back in the white room
func _tick_flash() -> void:
	if _black < 0.99:
		return
	# everything swaps over while the window is black
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
	Music.playing_own(_room_music.stream)
	_go(Stage.DOOR_ROOM)
	create_tween().tween_property(self, "_black", 0.0, 0.8)

# The key floats to the handle, turns slowly, and the door swings open.
const KEY_FLY := 0.9
const KEY_TURN := 1.1
func _tick_unlock() -> void:
	_key_t = _stage_t
	if _stage_t >= KEY_FLY + KEY_TURN and not _door_open:
		_door_open = true
		Audio.play("door_unlock")
	if _stage_t >= KEY_FLY + KEY_TURN + 0.5:
		_go(Stage.ENTER)

# The character walks in, the mouse after it, and both fade away in the
# doorway. A pause, then the glitch.
func _tick_enter(dt: float) -> void:
	var goal := config.door_way
	var step := config.walk_speed * dt
	var arrived := false
	if absf(_pos.x - goal.x) > 2.0:
		_dir = "right" if goal.x > _pos.x else "left"
		_pos.x = move_toward(_pos.x, goal.x, step)
	elif absf(_pos.y - goal.y) > 2.0:
		_dir = "up"
		_pos.y = move_toward(_pos.y, goal.y, step)
	else:
		arrived = true
	if _player:
		_player.set_motion(not arrived, _dir if not arrived else "up")
	if not arrived:
		return
	var pet_in := _pet.distance_to(goal + Vector2(0.0, config.pet_foot * 0.5)) < 20.0 or _pet_tex == null
	if pet_in or _player_alpha < 1.0:
		_player_alpha = move_toward(_player_alpha, 0.0, dt / 0.8)
	if _player_alpha <= 0.0:
		_pause_t += dt
		if _pause_t >= ENTER_PAUSE:
			_go(Stage.GLITCH)
			_room_music.stop()
			_glitch.visible = true
			_glitch.finished.connect(_on_glitch_done, CONNECT_ONE_SHOT)
			_glitch.play()
			Audio.play("final_glitch")

# After the glitch the whole desktop fades to black. The ending opens under the
# black, which then lifts. (It lives on the tree's root, since this game is
# freed as soon as it reports finished.)
func _on_glitch_done() -> void:
	_go(Stage.DONE)
	running = false
	var layer := CanvasLayer.new()
	layer.layer = 120
	var black := ColorRect.new()
	black.color = Color(0, 0, 0, 0)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(black)
	get_tree().root.add_child(layer)
	var tw := black.create_tween()
	tw.tween_property(black, "color:a", 1.0, 1.2)
	tw.tween_callback(func(): finished.emit(true))
	tw.tween_interval(0.4)
	tw.tween_property(black, "color:a", 0.0, 1.0)
	tw.tween_callback(layer.queue_free)

# ---------------------------------------------------------------- the pet
func _follow_pet(dt: float) -> void:
	_pet_t += dt
	if _mouse_biting():
		return
	var fade := 1.0 if _stage != Stage.ENTER else _player_alpha
	if fade <= 0.0:
		return
	var target: Vector2
	if _stage == Stage.ENTER and _pos.distance_to(config.door_way) < 3.0:
		# the character's in the doorway: the mouse trots in after it
		target = config.door_way + Vector2(0.0, config.pet_foot * 0.5)
		var to2 := target - _pet
		_pet += to2.limit_length(config.walk_speed * 0.8 * dt)
		if absf(to2.x) > 8.0:
			_pet_flip = to2.x > 0.0
	elif _in_white_room():
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
	else:
		draw_rect(Rect2(_cam - _arena.size, _arena.size * 2.0), Color.BLACK)

# Hugging Face in the white room and the door, under the character, drawn
# through the outline shader: the outline comes up when you're close enough
# to use them.
func _draw_prop() -> void:
	if not _built or _expand < 0.999:
		return
	var mat := _prop.material as ShaderMaterial
	match _stage:
		Stage.ROOM, Stage.TRANSITION:
			var t := config.hf_texture
			if t == null:
				return
			var half := _hf_half()
			var k := half.x * 2.0 / float(t.get_width())       # picture units per texture pixel
			var rect := Rect2(config.hf_pos - half, half * 2.0).grow(_hf_pad_px * k)
			mat.set_shader_parameter("width", HOVER_WIDTH / k * _hover_a)
			_prop.draw_texture_rect(_hf_pad, Rect2(_to_room(rect.position), rect.size * _s), false, Color(1, 1, 1, _room_a))
		Stage.DOOR_ROOM, Stage.UNLOCK, Stage.ENTER, Stage.GLITCH, Stage.DONE:
			if _door_open:
				mat.set_shader_parameter("width", 0.0)
				var o := config.door_open_texture
				if o:
					_prop.draw_texture_rect(o, Rect2(_to_room(config.door_open_pos), o.get_size() * _s), false)
			elif _door_pad:
				mat.set_shader_parameter("width", HOVER_WIDTH * _hover_a)
				var at := config.door_pos - Vector2.ONE * _door_pad_px
				_prop.draw_texture_rect(_door_pad, Rect2(_to_room(at), _door_pad.get_size() * _s), false)

# Half black over the background (the servers, the boxes, the mouse waiting):
# everything under the fight itself.
func _draw_dim() -> void:
	if not _built or _expand < 0.999 or _dim_a <= 0.0:
		return
	_dim.draw_rect(Rect2(_cam - _arena.size, _arena.size * 2.0), Color(0, 0, 0, _dim_a))

func _draw_back() -> void:
	if not _built or _expand < 0.999 or _pet_tex == null or _mouse_biting():
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
		Stage.BATTLE, Stage.BITE, Stage.DYING:
			var a := _hf_dying_alpha() if _stage == Stage.DYING else 1.0
			if _hf_visible and a > 0.0:
				_draw_hf(_hf + Vector2(0.0, -absf(sin(_t * 7.0)) * 14.0), _phase == 2, a)
			_draw_gun()
			if _stage == Stage.BATTLE:
				_draw_water()
				_draw_lasers()
			if _mouse_biting():
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
	if config.gun_texture == null or _gun_t <= 0.0:
		return
	var side := _face
	var pop := ease(clampf(_gun_t / 0.25, 0.0, 1.0), 0.4)   # it pops into the hand as the fight starts
	var gw := config.gun_width * pop
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
	var at := from.lerp(to, ease(clampf(t / KEY_FLY, 0.0, 1.0), -2.0))
	var rot := ease(clampf((t - KEY_FLY) / KEY_TURN, 0.0, 1.0), -1.8) * PI * 0.5
	var a := 1.0 - clampf((t - KEY_FLY - KEY_TURN) / 0.3, 0.0, 1.0)
	var kw := 120.0
	var kh := kw * config.key_texture.get_height() / float(config.key_texture.get_width())
	_front.draw_set_transform(_to_room(at), rot, Vector2(_s, _s))
	# the key's teeth go into the handle, so its tip is what reaches it
	_front.draw_texture_rect(config.key_texture, Rect2(-kw * 0.9, -kh * 0.5, kw, kh), false, Color(1, 1, 1, a))
	_front.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# When Hugging Face is hit the bar drains a cell at a time, the lost cells
# staying white a moment and then draining after it. Healing (after a fall)
# just fills back up.
func _tick_bar(dt: float) -> void:
	var target := float(_health)
	if _health < _last_health:
		_trail_wait = config.trail_wait
	_last_health = _health
	_shown_health = move_toward(_shown_health, target, dt * config.drain_speed * (1.0 if _shown_health > target else 1.5))
	if _trail_health < _shown_health:
		_trail_health = _shown_health
	elif _trail_wait > 0.0:
		_trail_wait -= dt
	else:
		_trail_health = move_toward(_trail_health, _shown_health, dt * config.drain_speed)

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
	var trail_share := clampf(_trail_health / float(maxi(config.health, 1)), 0.0, 1.0)
	for i in range(cells, ceili(config.hp_cells * trail_share - 0.01)):
		var at2 := top + (config.cell_first + Vector2(config.cell_pitch * i, 0.0)) * k
		_hud.draw_rect(Rect2(_to_room(at2), config.cell_size * k * _s), Color(1, 1, 1, a))
	for i in cells:
		var at := top + (config.cell_first + Vector2(config.cell_pitch * i, 0.0)) * k
		_hud.draw_rect(Rect2(_to_room(at), config.cell_size * k * _s), col)
	# and underneath, the number, counting down with the bar
	var f: Font = config.hp_font if config.hp_font else (config.font if config.font else ThemeDB.fallback_font)
	var text := ("Hugging Face HP: %d/%d" % [roundi(config.hp_number * share), config.hp_number]).to_upper()
	var fs := 32
	var fit := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	fs = maxi(int(fs * config.label_width * k / maxf(fit, 1.0)), 8)
	# white on a black strip, tucked under the bar's left end
	var pad := Vector2(8.0, 4.0) * k
	var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var asc := f.get_ascent(fs)
	var desc := f.get_descent(fs)
	var strip := Rect2(top + Vector2(0.0, size.y), Vector2(tw + pad.x * 2.0, asc + desc + pad.y * 2.0))
	_hud.draw_rect(Rect2(_to_room(strip.position), strip.size * _s), Color(0, 0, 0, a))
	var base := strip.position + Vector2(pad.x, pad.y + asc)
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
	if _red > 0.0:
		_over.draw_rect(r, Color(1, 0, 0, _red))
	if _black > 0.0:
		_over.draw_rect(r, Color(0, 0, 0, _black))
	if _white > 0.0:
		_over.draw_rect(r, Color(1, 1, 1, _white))

# ---------------------------------------------------------------- the background breaking up
# Scenes from the rest of the game glitch in and out over the server footage:
# bands torn sideways, blocks out of place, now and then a whole scene in
# shredded strips, some split into red and cyan. Rare and faint at full
# health; constant and wild as it runs out, and wildest while it goes down.
func _chaos() -> float:
	if _stage == Stage.DYING:
		return 1.0
	var k := clampf(1.0 - _shown_health / maxf(float(config.health), 1.0), 0.0, 1.0)
	return k

func _tick_scenes(dt: float) -> void:
	var on := _built and _expand >= 0.999 and _stage in [Stage.BATTLE, Stage.BITE, Stage.DYING] \
			and not config.glitch_scenes.is_empty()
	if not on:
		_glitches.clear()
		return
	var k := _chaos()
	for g in _glitches:
		g["t"] += dt
	_glitches = _glitches.filter(func(g): return g["t"] < g["life"])
	var rate := lerpf(config.glitch_rate.x, config.glitch_rate.y, pow(k, 1.3))
	_glitch_due = minf(_glitch_due - dt, 1.6 / maxf(rate, 0.01))   # a hit speeds it up at once
	while _glitch_due <= 0.0:
		_glitch_due += randf_range(0.4, 1.6) / maxf(rate, 0.01)
		_spawn_glitch(k)

func _spawn_glitch(k: float) -> void:
	var tex: Texture2D = config.glitch_scenes.pick_random()
	var g := {"tex": tex, "t": 0.0, "split": randf() < k * 0.7,
		"life": lerpf(config.glitch_life.x, config.glitch_life.y, k) * randf_range(0.6, 1.4),
		"a": lerpf(config.glitch_alpha.x, config.glitch_alpha.y, k) * randf_range(0.7, 1.0)}
	var roll := randf()
	if roll < k * 0.3:
		# a whole scene, shredded into strips that slide apart
		g["kind"] = "full"
		var n := randi_range(4, 6 + int(10.0 * k))
		var cuts: Array[float] = [0.0, 1.0]
		for i in n - 1:
			cuts.append(randf())
		cuts.sort()
		var strips := []
		for i in cuts.size() - 1:
			strips.append([cuts[i], cuts[i + 1], randf_range(-1.0, 1.0) * (0.01 + 0.2 * k)])
		g["strips"] = strips
	elif roll < 0.65:
		# a band across the whole width, torn sideways
		g["kind"] = "band"
		var h := randf_range(0.02, 0.1 + 0.25 * k)
		var y := randf_range(0.0, 1.0 - h)
		g["strips"] = [[y, y + h, randf_range(-1.0, 1.0) * (0.02 + 0.15 * k)]]
	else:
		# a block of a scene somewhere it doesn't belong
		g["kind"] = "block"
		var size := Vector2(randf_range(0.08, 0.25 + 0.35 * k), randf_range(0.05, 0.15 + 0.3 * k))
		g["src"] = Rect2(Vector2(randf() * (1.0 - size.x), randf() * (1.0 - size.y)), size)
		g["dst"] = Rect2(Vector2(randf() * (1.0 - size.x), randf() * (1.0 - size.y)), size)
	_glitches.append(g)

func _draw_scenes() -> void:
	if _glitches.is_empty():
		return
	var view := Rect2(_cam - _arena.size * 0.5, _arena.size)
	var k := _chaos()
	for g in _glitches:
		# it flickers more the worse things get
		if randf() < k * 0.35:
			continue
		var tex: Texture2D = g["tex"]
		var ts := tex.get_size()
		var a: float = g["a"]
		var parts := []                   # [destination share, source share]
		if g["kind"] == "block":
			parts.append([g["dst"], g["src"]])
		else:
			for st in g["strips"]:
				var y0: float = st[0]
				var y1: float = st[1]
				var dx: float = st[2]
				parts.append([Rect2(dx, y0, 1.0, y1 - y0), Rect2(0.0, y0, 1.0, y1 - y0)])
		for p in parts:
			var d: Rect2 = p[0]
			var s: Rect2 = p[1]
			var dst := Rect2(view.position + d.position * view.size, d.size * view.size)
			var src := Rect2(s.position * ts, s.size * ts)
			if g["split"]:
				var off := Vector2(view.size.x * 0.006 * (1.0 + 3.0 * k), 0.0)
				_scenes.draw_texture_rect_region(tex, Rect2(dst.position - off, dst.size), src, Color(1, 0.1, 0.2, a * 0.7))
				_scenes.draw_texture_rect_region(tex, Rect2(dst.position + off, dst.size), src, Color(0.1, 1, 1, a * 0.7))
			else:
				_scenes.draw_texture_rect_region(tex, dst, src, Color(1, 1, 1, a))
