extends Minigame
class_name InternetGame
# "Internet access": the earth spins with a computer riding around it. Get close
# to the computer and press E to catch it, then mash E to push the connection
# through frame by frame; when the last frame lands the outro plays and the
# game ends with success.
#
# Phases, in order: loop (and loop hover) -> transition -> click frames -> outro.
# Frames are loaded a couple at a time, only for the phase that's about to play,
# so the whole sheet is never in memory at once.

enum State { LOADING, LOOP, FINISH_LOOP, TRANSITION, CLICK, OUTRO, DONE }

const CLIP_SHADER := preload("res://shaders/clip_rect.gdshader")

var config: InternetConfig
var running := false

var _arena := Rect2()
var _player: Node2D
var _rect := Rect2()                   # the area the pictures fill right now (grows with the button)
var _s := 1.0                          # room units per frame pixel
var _layer := Rect2()                  # where the frame sits, in room units
var _frame_px := Vector2(800, 756)
var _hover_data := {}                  # loop frame number (as text) -> {x, y, w, h, cx, cy} in frame pixels
var _counts := {}                      # frames in each phase

var _state := State.LOADING
var _t := 0.0                          # seconds into the current animation
var _shown := ""                       # path of the frame on screen, so we only swap when it changes
var _click_i := 0
var _click_wait := -1.0                # counts down after the last click frame
var _hold := -1.0                      # counts down at the end of the outro
var _hovering := false
var _finish_pos := 0.0                 # loop position (in frames) at which the transition starts
var _built := false

var _tex := {}                         # path -> Texture2D
var _queue: Array = []                 # [path, phase] waiting to load
var _remaining := {}                   # phase -> files still to load
var _queued := {}                      # phase -> true once requested

var _clip_mat: ShaderMaterial
var _frame_sprite: Sprite2D
var _hover_sprite: Sprite2D
var _loading_sprite: Sprite2D
var _instr_a: Sprite2D
var _instr_b: Sprite2D

func setup(arena: Rect2, player: Node2D, _start_pos: Vector2) -> void:
	_arena = arena
	_player = player

func prepare(cfg: MinigameConfig) -> void:
	config = cfg as InternetConfig
	if config == null:
		push_error("InternetGame needs an InternetConfig")
		return
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(config.frames_dir + "/frames.json"))
	if not manifest is Dictionary:
		push_error("InternetGame: run tools/build_internet_frames.py (no frames.json found)")
		return
	_frame_px = Vector2(manifest["frame"][0], manifest["frame"][1])
	_hover_data = manifest["hover"]
	for phase in ["loop", "transition", "click", "outro"]:
		_counts[phase] = int(manifest[phase])

	_clip_mat = ShaderMaterial.new()
	_clip_mat.shader = CLIP_SHADER
	_frame_sprite = _make_sprite(0)
	_hover_sprite = _make_sprite(0)
	_hover_sprite.visible = false
	_loading_sprite = _make_sprite(0)
	_loading_sprite.centered = true
	_loading_sprite.texture = config.loading_image
	_loading_sprite.self_modulate.a = 0.0
	_instr_a = _make_sprite(20)
	_instr_a.texture = config.instructions_a
	_instr_b = _make_sprite(20)
	_instr_b.texture = config.instructions_b
	_instr_b.self_modulate.a = 0.0

	_request("loop")
	_load_one()                                   # frame 0 right away, so there's a picture during the expand
	_show_frame(_path("loop", 0))
	_built = true
	set_expand(_arena, 0.0)

func _make_sprite(z: int) -> Sprite2D:
	var sp := Sprite2D.new()
	sp.centered = false
	sp.z_index = z
	sp.material = _clip_mat
	add_child(sp)
	return sp

# The pictures grow out of the button along with it, clipped to it.
func set_expand(rect: Rect2, t: float) -> void:
	if not _built:
		return
	_rect = rect
	_s = rect.size.x / _frame_px.x
	var size := _frame_px * _s
	_layer = Rect2(rect.position.x, rect.get_center().y - size.y * 0.5, size.x, size.y)

	var gt := get_global_transform()
	var tl := gt * rect.position
	var br := gt * rect.end
	_clip_mat.set_shader_parameter("clip_rect", Vector4(tl.x, tl.y, br.x - tl.x, br.y - tl.y))

	var a := clampf(t * 2.0, 0.0, 1.0)
	for sp in [_frame_sprite, _hover_sprite, _loading_sprite, _instr_a, _instr_b]:
		sp.modulate.a = a
	_frame_sprite.position = _layer.position
	_frame_sprite.scale = Vector2.ONE * _s
	_place_instructions(_instr_a)
	_place_instructions(_instr_b)
	_loading_sprite.position = _layer.position + _layer.size * config.loading_center
	if _loading_sprite.texture:
		var grow := rect.size.x / maxf(_arena.size.x, 1.0)       # the ring grows with the button too
		_loading_sprite.scale = Vector2.ONE * (config.loading_size * grow / _loading_sprite.texture.get_width())
	queue_redraw()

func _place_instructions(sp: Sprite2D) -> void:
	if sp.texture == null:
		return
	sp.position = _layer.position
	sp.scale = Vector2.ONE * (_layer.size.x / sp.texture.get_width())

func start(cfg: MinigameConfig) -> void:
	if not _built:
		prepare(cfg)
	if not _built:
		finished.emit(true)
		return
	set_expand(_arena, 1.0)
	_player.position = _arena.get_center()
	_t = 0.0
	running = true
	Game.input_locked = false

func stop() -> void:
	running = false

func _draw() -> void:
	if _built:
		draw_rect(_rect, Color.BLACK)      # behind the frame, in case the arena is taller than the picture

# ---------------------------------------------------------------- per frame

func _process(delta: float) -> void:
	if not _built:
		return
	_load_some()
	if not running:
		return
	var pr := config.player_radius
	_player.position = Vector2(
		clampf(_player.position.x, _arena.position.x + pr, _arena.end.x - pr),
		clampf(_player.position.y, _arena.position.y + pr, _arena.end.y - pr))
	var pressed := _active() and Input.is_action_just_pressed("Interact")

	match _state:
		State.LOADING:
			if _is_loaded("loop"):
				_state = State.LOOP
				_t = 0.0
		State.LOOP:
			_t += delta
			var n: int = _counts["loop"]
			var i := int(_t * config.loop_fps) % n
			_show_frame(_path("loop", i))
			_update_hover(i)
			if _hovering and pressed:
				_state = State.FINISH_LOOP
				_finish_pos = (floorf(_t * config.loop_fps / n) + 1.0) * n    # the end of this lap
				_request("transition")
		State.FINISH_LOOP:
			# Keep playing to the end of the loop so the globe doesn't jump.
			_t += delta
			var n: int = _counts["loop"]
			var i := int(_t * config.loop_fps) % n
			if _t * config.loop_fps >= _finish_pos:
				_begin_transition()
			else:
				_show_frame(_path("loop", i))
				_update_hover(i, true)
		State.TRANSITION:
			_t += delta
			var i := int(_t * config.transition_fps)
			if i >= _counts["transition"]:
				_begin_click()
			else:
				_show_frame(_path("transition", i))
		State.CLICK:
			_loading_sprite.rotation += TAU * config.loading_spin * delta
			if _click_wait >= 0.0:
				_click_wait -= delta
				if _click_wait < 0.0:
					_begin_outro()
			elif pressed:
				_click_i += 1
				_show_frame(_path("click", _click_i))
				if _click_i >= _counts["click"] - 1:
					_click_wait = config.click_end_delay
		State.OUTRO:
			_t += delta
			var i := int(_t * config.outro_fps)
			if i >= _counts["outro"]:
				_show_frame(_path("outro", _counts["outro"] - 1))
				_hold = config.outro_hold
				_state = State.DONE
				Game.input_locked = true
			else:
				_show_frame(_path("outro", i))
		State.DONE:
			_hold -= delta
			if _hold <= 0.0 and running:
				running = false
				finished.emit(true)

func _active() -> bool:
	return world_id == "" or Game.active_world == world_id

# ---------------------------------------------------------------- phases

# Waits here (holding the last picture) until the next phase's frames are loaded.
func _begin_transition() -> void:
	_request("transition")
	_request("click")
	if not _is_loaded("transition"):
		return
	_hover_sprite.visible = false
	_hover_sprite.texture = null
	_state = State.TRANSITION
	_t = 0.0
	_fade(_instr_a, 0.0, 0.3)
	_show_frame(_path("transition", 0))
	_free("loop")

func _begin_click() -> void:
	_request("click")
	if not _is_loaded("click"):
		return
	_state = State.CLICK
	_click_i = 0
	_click_wait = -1.0
	_show_frame(_path("click", 0))
	_fade(_instr_b, 1.0, 0.3)
	_fade(_loading_sprite, 1.0, 0.3)
	_request("outro")
	_free("transition")

func _begin_outro() -> void:
	if not _is_loaded("outro"):
		_click_wait = 0.05           # try again shortly
		return
	_state = State.OUTRO
	_t = 0.0
	_fade(_instr_b, 0.0, 0.25)
	_fade(_loading_sprite, 0.0, 0.25)
	_show_frame(_path("outro", 0))
	_free("click")

func _fade(sp: Sprite2D, to: float, time: float) -> void:
	create_tween().tween_property(sp, "self_modulate:a", to, time)

# The computer highlights white when the player is close enough to catch it.
func _update_hover(frame: int, keep := false) -> void:
	var d = _hover_data.get(str(frame))
	var near := false
	if d != null:
		var c: Vector2 = _layer.position + Vector2(d["cx"], d["cy"]) * _s
		near = keep or _player.position.distance_to(c) < config.hover_radius
	_hovering = near
	_hover_sprite.visible = near
	if near:
		var tex: Texture2D = _tex.get(_hover_path(frame))
		if tex:
			_hover_sprite.texture = tex
			_hover_sprite.position = _layer.position + Vector2(d["x"], d["y"]) * _s
			_hover_sprite.scale = Vector2.ONE * _s
		else:
			_hover_sprite.visible = false

func _show_frame(path: String) -> void:
	if path == _shown:
		return
	var tex: Texture2D = _tex.get(path)
	if tex:
		_shown = path
		_frame_sprite.texture = tex

# ---------------------------------------------------------------- loading

func _path(phase: String, i: int) -> String:
	return "%s/%s_%03d.png" % [config.frames_dir, phase, i]

func _hover_path(i: int) -> String:
	return "%s/hover_%03d.png" % [config.frames_dir, i]

func _phase_paths(phase: String) -> Array:
	var out := []
	for i in _counts[phase]:
		out.append(_path(phase, i))
	if phase == "loop":
		for k in _hover_data:
			out.append(_hover_path(int(k)))
	return out

func _request(phase: String) -> void:
	if _queued.has(phase):
		return
	_queued[phase] = true
	var paths := _phase_paths(phase)
	_remaining[phase] = paths.size()
	for p in paths:
		_queue.append([p, phase])

func _is_loaded(phase: String) -> bool:
	return _queued.has(phase) and _remaining.get(phase, 1) == 0

func _load_some() -> void:
	for _i in config.loads_per_frame:
		_load_one()

func _load_one() -> void:
	if _queue.is_empty():
		return
	var e: Array = _queue.pop_front()
	_tex[e[0]] = load(e[0])
	_remaining[e[1]] -= 1

# Lets go of a phase's pictures once it has played.
func _free(phase: String) -> void:
	for p in _phase_paths(phase):
		_tex.erase(p)
