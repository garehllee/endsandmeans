extends Minigame
class_name TransferGame
# Blank files travel along a path (hopping down wires, or shooting off into the
# distance along beams, depending on config.motion). Touch one and press E to
# corrupt it: the screen flashes inverted for a moment (only the character, who
# shows a word, and the new photo are left alone) and that file carries on as a
# photo. Corrupt one file per photo to finish.

enum State { WAITING, PLAYING, FLASH, DONE }

const CLIP_SHADER := preload("res://shaders/clip_rect.gdshader")
const FLASH_SHADER := preload("res://shaders/invert_flash.gdshader")
const PICTURE := Vector2(1600, 1512)       # the size the art was drawn at
const FOOT := 57.0                         # half a file's height: it sits on top of the wire

class Item:
	var lane := 0               # which wire or beam
	var corrupted := false
	var sprite: Sprite2D
	var pos := Vector2.ZERO     # picture units
	var sc := 1.0               # size multiplier (shrinks with distance when shooting)
	var alpha := 1.0
	# hop motion
	var s0 := 0.0               # distance along the wire where the current hop started
	var t := 0.0                # seconds into the current hop or trip
	var length := 150.0
	var dur := 0.7
	var height := 80.0
	# float motion
	var x := 0.0                # picture units
	var y0 := 0.0               # middle of the wave
	var speed := 100.0
	var amp := 60.0
	var freq := 0.4
	var phase := 0.0
	var rot := 0.0              # radians
	# shoot motion
	var side := 0.0             # -1 to 1: sideways position across the beam

var config: TransferConfig
var running := false

var _arena := Rect2()
var _player: Node2D
var _layer := Rect2()
var _s := 1.0
var _expand_a := 1.0
var _built := false
var _state := State.WAITING
var _rng := RandomNumberGenerator.new()

var _wires: Array[Dictionary] = []         # hop: {pts, cum, len}
var _items: Array[Item] = []
var _target: Item = null
var _used := 0

var _clip_mat: ShaderMaterial
var _backdrop: Sprite2D
var _static_layers: Array[Sprite2D] = []   # poles and wires/beams: they just sit there
var _highlight: Sprite2D
var _instr: Sprite2D
var _flash: Node2D
var _text: Sprite2D

func setup(arena: Rect2, player: Node2D, _start_pos: Vector2) -> void:
	_arena = arena
	_player = player

func prepare(cfg: MinigameConfig) -> void:
	config = cfg as TransferConfig
	if config == null:
		push_error("TransferGame needs a TransferConfig")
		return
	_rng.randomize()
	_clip_mat = ShaderMaterial.new()
	_clip_mat.shader = CLIP_SHADER

	_backdrop = _make_sprite(config.arena_image, 0, false)
	for tex in [config.poles, config.wires]:
		if tex != null:
			_static_layers.append(_make_sprite(tex, 0))
	_highlight = _make_sprite(config.blank_file, 0, true)
	_highlight.self_modulate = Color("002BFF")
	_highlight.self_modulate.a = 0.75
	_highlight.visible = false

	if config.motion == "float":
		var n := config.float_count
		var bands: Array[int] = []
		for i in n:
			bands.append(i)
		bands.shuffle()                                 # spread evenly over the height, in random order
		for i in n:
			var it := _new_item(0)
			_new_float(it, bands[i], n)
			it.x = _rng.randf_range(-100.0, PICTURE.x + 100.0)
			it.t = _rng.randf() * 10.0
	elif config.motion == "shoot":
		for lane in config.lane_starts.size():
			for i in config.files_per_lane:
				var it := _new_item(lane)
				_new_trip(it)
				it.t = _rng.randf() * it.dur           # staggered, so they're not all in step
	else:
		_wires = [_measure(config.wire_a), _measure(config.wire_b)]
		for w in 2:
			for i in config.files_per_wire:
				var it := _new_item(w)
				_new_hop(it)
				var span: float = _wires[w]["len"]
				it.s0 = span * (float(i) + _rng.randf_range(0.0, 0.7)) / config.files_per_wire
				it.t = _rng.randf() * it.dur
	_place_items()

	_instr = _make_sprite(config.instructions, 4)       # under the flash, so it gets inverted too
	_flash = Node2D.new()
	_flash.z_index = 5
	var fm := ShaderMaterial.new()
	fm.shader = FLASH_SHADER
	_flash.material = fm
	_flash.visible = false
	_flash.draw.connect(func(): _flash.draw_rect(Rect2(_arena.position - Vector2(10, 10), _arena.size + Vector2(20, 20)), Color.WHITE))
	add_child(_flash)
	_text = _make_sprite(config.flash_text, 6, true)    # above the flash
	_text.visible = false
	_built = true
	set_expand(_arena, 0.0)

func _new_item(lane: int) -> Item:
	var it := Item.new()
	it.lane = lane
	it.sprite = _make_sprite(config.blank_file, 0, true)
	_items.append(it)
	return it

func _make_sprite(tex: Texture2D, z: int, centered := false) -> Sprite2D:
	var sp := Sprite2D.new()
	sp.texture = tex
	sp.centered = centered
	sp.z_index = z
	sp.material = _clip_mat
	add_child(sp)
	return sp

# The pictures grow out of the button along with it, clipped to it.
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

	_expand_a = clampf(t * 2.0, 0.0, 1.0)
	_backdrop.modulate.a = _expand_a
	_instr.modulate.a = _expand_a
	_cover(_backdrop, rect)
	for sp in _static_layers + [_instr]:
		sp.modulate.a = _expand_a
		sp.position = _layer.position
		sp.scale = Vector2.ONE * (_layer.size.x / maxf(sp.texture.get_width(), 1.0))
	_place_items()

# Fills the rectangle with the picture, cropping the overflow evenly.
func _cover(sp: Sprite2D, rect: Rect2) -> void:
	var ts := sp.texture.get_size()
	var want := rect.size.x / rect.size.y
	var cw := ts.x
	var ch := ts.y
	if ts.x / ts.y > want:
		cw = ts.y * want
	else:
		ch = ts.x / want
	sp.region_enabled = true
	sp.region_rect = Rect2((ts.x - cw) * 0.5, (ts.y - ch) * 0.5, cw, ch)
	sp.position = rect.position
	sp.scale = Vector2.ONE * (rect.size.x / cw)

func start(cfg: MinigameConfig) -> void:
	if not _built:
		prepare(cfg)
	if not _built:
		finished.emit(true)
		return
	if config.flash_photos.is_empty():
		push_error("TransferGame: no photos in the config")
		finished.emit(true)
		return
	set_expand(_arena, 1.0)
	_player.position = _arena.get_center()
	_state = State.PLAYING
	running = true
	Game.input_locked = false

func stop() -> void:
	running = false

# ---------------------------------------------------------------- wires (hop)

func _measure(pts: PackedVector2Array) -> Dictionary:
	var cum := PackedFloat32Array([0.0])
	for i in range(1, pts.size()):
		cum.append(cum[i - 1] + pts[i - 1].distance_to(pts[i]))
	return {"pts": pts, "cum": cum, "len": cum[cum.size() - 1]}

# A point s units along the wire; before the start and past the end the wire
# just carries straight on, so files can come in from off-screen.
func _wire_point(w: int, s: float) -> Vector2:
	var pts: PackedVector2Array = _wires[w]["pts"]
	var cum: PackedFloat32Array = _wires[w]["cum"]
	var n := pts.size()
	if s <= 0.0:
		return pts[0] + (pts[1] - pts[0]).normalized() * s
	if s >= cum[n - 1]:
		return pts[n - 1] + (pts[n - 1] - pts[n - 2]).normalized() * (s - cum[n - 1])
	for i in range(1, n):
		if s <= cum[i]:
			var f := (s - cum[i - 1]) / maxf(cum[i] - cum[i - 1], 0.001)
			return pts[i - 1].lerp(pts[i], f)
	return pts[n - 1]

# ---------------------------------------------------------------- per frame

func _process(delta: float) -> void:
	if not _built or not running:
		return
	delta = minf(delta, 1.0 / 30.0)
	var pr := config.player_radius
	_player.position = Vector2(
		clampf(_player.position.x, _arena.position.x + pr, _arena.end.x - pr),
		clampf(_player.position.y, _arena.position.y + pr, _arena.end.y - pr))

	match _state:
		State.PLAYING:
			for it in _items:
				if config.motion == "float":
					_advance_float(it, delta)
				elif config.motion == "shoot":
					_advance_shoot(it, delta)
				else:
					_advance_hop(it, delta)
			_place_items()
			_update_target()
			if _target != null and _active() and Input.is_action_just_pressed("Interact"):
				_corrupt(_target)
		State.FLASH, State.DONE, State.WAITING:
			pass

func _active() -> bool:
	return world_id == "" or Game.active_world == world_id

func _new_hop(it: Item) -> void:
	it.length = _rng.randf_range(config.hop_length.x, config.hop_length.y)
	it.dur = _rng.randf_range(config.hop_time.x, config.hop_time.y)
	it.height = _rng.randf_range(config.hop_height.x, config.hop_height.y)

func _advance_hop(it: Item, dt: float) -> void:
	it.t += dt
	while it.t >= it.dur:
		it.t -= it.dur
		it.s0 += it.length
		_new_hop(it)
		if it.s0 > float(_wires[it.lane]["len"]) + 120.0:
			it.s0 = -_rng.randf_range(60.0, 260.0)       # back to the start of the wire
			_recycle(it)

func _new_float(it: Item, band: int, n: int) -> void:
	var y: Vector2 = config.float_y
	var h := (y.y - y.x) / n
	it.y0 = y.x + h * (band + _rng.randf())
	it.speed = _rng.randf_range(config.float_speed.x, config.float_speed.y)
	it.amp = _rng.randf_range(config.float_amp.x, config.float_amp.y)
	it.freq = _rng.randf_range(config.float_freq.x, config.float_freq.y)
	it.phase = _rng.randf() * TAU
	it.lane = band

func _advance_float(it: Item, dt: float) -> void:
	it.t += dt
	it.x += it.speed * dt
	if it.x > PICTURE.x + 100.0:
		it.x = -100.0 - _rng.randf_range(0.0, 200.0)
		_new_float(it, it.lane, config.float_count)
		_recycle(it)

# One trip from the foreground into the distance.
func _new_trip(it: Item) -> void:
	it.dur = _rng.randf_range(config.shoot_time.x, config.shoot_time.y)
	it.side = _rng.randf_range(-1.0, 1.0)

func _advance_shoot(it: Item, dt: float) -> void:
	it.t += dt
	if it.t >= it.dur:
		it.t = 0.0
		_new_trip(it)
		_recycle(it)

# A corrupted file that has made its trip comes back as a fresh blank one, so
# there are always files left to corrupt (there can be more photos than files).
func _recycle(it: Item) -> void:
	if not it.corrupted:
		return
	it.corrupted = false
	it.sprite.texture = config.blank_file
	it.sprite.region_enabled = false

func _place_items() -> void:
	for it in _items:
		it.rot = 0.0
		if config.motion == "float":
			var w := TAU * it.freq * it.t + it.phase
			it.pos = Vector2(it.x, it.y0 + it.amp * sin(w))
			it.rot = deg_to_rad(config.float_tilt) * cos(w)
			it.sc = 1.0
			it.alpha = clampf((PICTURE.x + 100.0 - it.x) / 100.0, 0.0, 1.0) * clampf((it.x + 100.0) / 100.0, 0.0, 1.0)
		elif config.motion == "shoot":
			_place_shoot(it)
		else:
			var f := it.t / it.dur
			var lift := 4.0 * it.height * f * (1.0 - f)
			it.pos = _wire_point(it.lane, it.s0 + it.length * f) + Vector2(0.0, -(FOOT + lift))
			it.sc = 1.0
			it.alpha = 1.0
		it.sprite.position = _layer.position + it.pos * _s
		it.sprite.rotation = it.rot
		it.sprite.scale = Vector2.ONE * _s * it.sc * (_photo_scale(it) if it.corrupted else 1.0)
		it.sprite.modulate.a = _expand_a * it.alpha

# Starts just off the near edge and flies toward the vanishing point, easing out:
# fast at first (close to the camera), then slowing and shrinking as it gets far away.
func _place_shoot(it: Item) -> void:
	var v := config.vanish_point
	var near_pt: Vector2 = v + (config.lane_starts[it.lane] - v) * 1.12
	var u := clampf(it.t / it.dur, 0.0, 1.0)
	var e := 1.0 - pow(1.0 - u, config.ease_power)
	var p := near_pt.lerp(v, e)
	var remaining := 1.0 - e                              # 1 at the start, 0 at the vanishing point
	var dir := (v - near_pt).normalized()
	var across := Vector2(-dir.y, dir.x)
	p += across * it.side * config.lane_spread * config.lane_width * 0.5 * remaining
	it.pos = p
	it.sc = config.far_scale + (config.near_scale - config.far_scale) * remaining
	it.alpha = clampf((1.0 - u) / 0.2, 0.0, 1.0) * clampf(u / 0.04, 0.0, 1.0)

func _update_target() -> void:
	var best: Item = null
	var best_d := INF
	for it in _items:
		if it.corrupted or it.alpha < 0.4:
			continue
		var reach := maxf(config.touch_radius * it.sc, 40.0) * _s     # far files are small, so harder to touch
		var d := it.sprite.position.distance_to(_player.position)
		if d < reach and d < best_d:
			best_d = d
			best = it
	_target = best
	_highlight.visible = best != null
	if best:
		_highlight.position = best.sprite.position
		_highlight.rotation = best.rot
		_highlight.scale = Vector2.ONE * _s * best.sc * 1.22

# ---------------------------------------------------------------- corrupting

func _photo_scale(it: Item) -> float:
	var cell := config.blank_file.get_size()
	return cell.x / it.sprite.region_rect.size.x

func _apply_photo(it: Item, tex: Texture2D) -> void:
	var cell := config.blank_file.get_size()
	var ts := tex.get_size()
	var want := cell.x / cell.y
	var cw := ts.x
	var ch := ts.y
	if ts.x / ts.y > want:
		cw = ts.y * want
	else:
		ch = ts.x / want
	it.sprite.texture = tex
	it.sprite.region_enabled = true
	it.sprite.region_rect = Rect2((ts.x - cw) * 0.5, (ts.y - ch) * 0.5, cw, ch)
	it.corrupted = true

func _corrupt(it: Item) -> void:
	_state = State.FLASH
	Game.input_locked = true
	_target = null
	_highlight.visible = false
	_apply_photo(it, config.flash_photos[_used % config.flash_photos.size()])
	_used += 1
	_place_items()

	# Everything gets inverted except the character (now a word) and the new photo.
	it.sprite.z_index = 6
	_player.visible = false
	_text.position = _player.position + config.flash_text_offset * _s
	_text.scale = Vector2.ONE * config.flash_text_scale * _s
	_text.visible = true
	_flash.visible = true
	_flash.queue_redraw()
	Game.say_random("transfer_corrupt")

	await get_tree().create_timer(config.flash_time).timeout

	_flash.visible = false
	_text.visible = false
	_player.visible = true
	it.sprite.z_index = 0
	if _used >= config.flash_photos.size():
		_state = State.DONE
		await get_tree().create_timer(config.end_hold).timeout
		if running:
			running = false
			finished.emit(true)
	else:
		_state = State.PLAYING
		Game.input_locked = false
