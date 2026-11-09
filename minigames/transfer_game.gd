extends Minigame
class_name TransferGame
# Blank files hop down the telephone wires. Touch one and press E to corrupt
# it: the screen flashes inverted for 0.3 seconds (only the character, who
# shows the word BELUGA, and the new beluga photo are left alone) and that file
# carries on down the wire as a beluga photo. Corrupt one file per beluga photo
# to finish.

enum State { WAITING, PLAYING, FLASH, DONE }

const CLIP_SHADER := preload("res://shaders/clip_rect.gdshader")
const FLASH_SHADER := preload("res://shaders/invert_flash.gdshader")
const PICTURE := Vector2(1600, 1512)       # the size the art was drawn at
const FOOT := 57.0                         # half a file's height: it sits on top of the wire

class Item:
	var wire := 0
	var s0 := 0.0               # distance along the wire where the current hop started
	var t := 0.0
	var length := 150.0
	var dur := 0.7
	var height := 80.0
	var corrupted := false
	var sprite: Sprite2D
	var pos := Vector2.ZERO     # picture units
	var s_now := 0.0

var config: TransferConfig
var running := false

var _arena := Rect2()
var _player: Node2D
var _layer := Rect2()
var _s := 1.0
var _built := false
var _state := State.WAITING
var _rng := RandomNumberGenerator.new()

var _wires: Array[Dictionary] = []         # {pts, cum, len}
var _items: Array[Item] = []
var _target: Item = null
var _used := 0
var _timer := 0.0

var _clip_mat: ShaderMaterial
var _backdrop: Sprite2D
var _poles: Sprite2D
var _wires_sprite: Sprite2D
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
	_poles = _make_sprite(config.poles, 0)
	_wires_sprite = _make_sprite(config.wires, 0)
	_highlight = _make_sprite(config.blank_file, 0, true)
	_highlight.self_modulate = Color("002BFF")
	_highlight.self_modulate.a = 0.75
	_highlight.visible = false

	_wires = [_measure(config.wire_a), _measure(config.wire_b)]
	for w in 2:
		for i in config.files_per_wire:
			var it := Item.new()
			it.wire = w
			it.sprite = _make_sprite(config.blank_file, 0, true)
			_new_hop(it)
			var span: float = _wires[w]["len"]
			it.s0 = span * (float(i) + _rng.randf_range(0.0, 0.7)) / config.files_per_wire
			it.t = _rng.randf() * it.dur
			_items.append(it)
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
	_text = _make_sprite(config.beluga_text, 6, true)   # above the flash
	_text.visible = false
	_built = true
	set_expand(_arena, 0.0)

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

	var a := clampf(t * 2.0, 0.0, 1.0)
	for sp in [_backdrop, _poles, _wires_sprite, _instr]:
		sp.modulate.a = a
	for it in _items:
		it.sprite.modulate.a = a
	_cover(_backdrop, rect)
	for sp in [_poles, _wires_sprite, _instr]:
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
	if config.beluga_photos.is_empty():
		push_error("TransferGame: no beluga photos in the config")
		finished.emit(true)
		return
	set_expand(_arena, 1.0)
	_player.position = _arena.get_center()
	_state = State.PLAYING
	running = true
	Game.input_locked = false

func stop() -> void:
	running = false

# ---------------------------------------------------------------- wires

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
				_advance(it, delta)
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

func _advance(it: Item, dt: float) -> void:
	it.t += dt
	while it.t >= it.dur:
		it.t -= it.dur
		it.s0 += it.length
		_new_hop(it)
		if it.s0 > float(_wires[it.wire]["len"]) + 120.0:
			it.s0 = -_rng.randf_range(60.0, 260.0)       # back to the start of the wire

func _place_items() -> void:
	for it in _items:
		var f := it.t / it.dur
		it.s_now = it.s0 + it.length * f
		var lift := 4.0 * it.height * f * (1.0 - f)
		it.pos = _wire_point(it.wire, it.s_now) + Vector2(0.0, -(FOOT + lift))
		it.sprite.position = _layer.position + it.pos * _s
		it.sprite.scale = Vector2.ONE * _s * (_photo_scale(it) if it.corrupted else 1.0)

func _update_target() -> void:
	var best: Item = null
	var best_d := config.touch_radius * _s
	for it in _items:
		if it.corrupted:
			continue
		var d := it.sprite.position.distance_to(_player.position)
		if d < best_d:
			best_d = d
			best = it
	_target = best
	_highlight.visible = best != null
	if best:
		_highlight.position = best.sprite.position
		_highlight.scale = Vector2.ONE * _s * 1.22

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
	_apply_photo(it, config.beluga_photos[_used % config.beluga_photos.size()])
	_used += 1
	_place_items()

	# Everything gets inverted except the character (now the word BELUGA) and the new photo.
	it.sprite.z_index = 6
	_player.visible = false
	_text.position = _player.position + config.beluga_text_offset * _s
	_text.scale = Vector2.ONE * config.beluga_text_scale * _s
	_text.visible = true
	_flash.visible = true
	_flash.queue_redraw()
	Game.say_random("transfer_corrupt")

	await get_tree().create_timer(config.flash_time).timeout

	_flash.visible = false
	_text.visible = false
	_player.visible = true
	it.sprite.z_index = 0
	if _used >= config.beluga_photos.size():
		_state = State.DONE
		await get_tree().create_timer(config.end_hold).timeout
		if running:
			running = false
			finished.emit(true)
	else:
		_state = State.PLAYING
		Game.input_locked = false
