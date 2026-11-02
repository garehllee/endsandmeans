extends Minigame
class_name EraseGame
# Rub out the text. An eraser rides on the character's right side and wipes
# away whatever it passes over. Finishes with success once target_fraction of
# the text is gone.
#
# Layers, bottom to top: background (drawn by the room), erasable text,
# character, eraser, instructions.

const MASK_SHADER := preload("res://shaders/erase_mask.gdshader")
const CLIP_SHADER := preload("res://shaders/clip_rect.gdshader")

var config: EraseConfig
var running := false

var _arena := Rect2()
var _player: Node2D
var _layer := Rect2()                  # where the pictures sit, in room units
var _mask_w := 0
var _mask_h := 0
var _mask := PackedByteArray()         # 255 = still there, 0 = erased
var _is_text := PackedByteArray()      # 1 where the original text is
var _mask_img: Image
var _mask_tex: ImageTexture
var _text_total := 0
var _erased := 0
var _dirty := false
var _done := false
var _last := Vector2.INF
var _eraser_sprite: Sprite2D
var _text_sprite: Sprite2D
var _instr_sprite: Sprite2D
var _built := false

func setup(arena: Rect2, player: Node2D, _start_pos: Vector2) -> void:
	_arena = arena
	_player = player

func prepare(cfg: MinigameConfig) -> void:
	config = cfg as EraseConfig
	if config == null or config.text_layer == null:
		push_error("EraseGame needs an EraseConfig with a text_layer")
		return
	_build_layers()
	_built = true
	set_expand(_arena, 0.0)

# The text and instructions grow out of the button along with it.
func set_expand(rect: Rect2, t: float) -> void:
	if not _built:
		return
	var ts := config.text_layer.get_size()
	var s := rect.size.x / ts.x
	var pos := Vector2(rect.position.x, rect.get_center().y - ts.y * s * 0.5)
	var a := clampf(t * 2.0, 0.0, 1.0)
	# Clip to the growing button so nothing spills over the rest of the room.
	var gt := get_global_transform()
	var tl := gt * rect.position
	var br := gt * rect.end
	var clip := Vector4(tl.x, tl.y, br.x - tl.x, br.y - tl.y)
	for sp in [_text_sprite, _instr_sprite]:
		if sp:
			(sp.material as ShaderMaterial).set_shader_parameter("clip_rect", clip)
			sp.position = pos
			sp.scale = Vector2(s, s)
			sp.modulate.a = a

func start(cfg: MinigameConfig) -> void:
	if not _built:
		prepare(cfg)
	if not _built:
		finished.emit(true)
		return
	set_expand(_arena, 1.0)
	_eraser_sprite.visible = true
	_player.position = _arena.get_center()      # spawn in the middle
	_last = Vector2.INF
	_done = false
	running = true
	Game.input_locked = false

func stop() -> void:
	running = false

# 0 to 1: how much of the text is gone.
func progress() -> float:
	return float(_erased) / maxf(float(_text_total), 1.0)

func _build_layers() -> void:
	var ts := config.text_layer.get_size()
	var s := _arena.size.x / ts.x                      # fit the pictures to the arena's width
	var size := ts * s
	_layer = Rect2(_arena.position.x, _arena.position.y + (_arena.size.y - size.y) * 0.5, size.x, size.y)

	_mask_w = maxi(int(ts.x * config.mask_scale), 8)
	_mask_h = maxi(int(ts.y * config.mask_scale), 8)
	_mask = PackedByteArray()
	_mask.resize(_mask_w * _mask_h)
	_mask.fill(255)
	_mask_img = Image.create_from_data(_mask_w, _mask_h, false, Image.FORMAT_R8, _mask)
	_mask_tex = ImageTexture.create_from_image(_mask_img)

	# Which mask pixels hold text (so the 50% counts text, not empty space).
	var src := config.text_layer.get_image()
	src.convert(Image.FORMAT_RGBA8)
	src.resize(_mask_w, _mask_h, Image.INTERPOLATE_BILINEAR)
	var px := src.get_data()
	_is_text = PackedByteArray()
	_is_text.resize(_mask_w * _mask_h)
	_text_total = 0
	for i in _mask_w * _mask_h:
		if px[i * 4 + 3] > 100:
			_is_text[i] = 1
			_text_total += 1
	_erased = 0

	# Children draw in order: text, then (the room's player), then eraser, then instructions.
	_text_sprite = _make_sprite(config.text_layer, s, 0)
	var mat := ShaderMaterial.new()
	mat.shader = MASK_SHADER
	mat.set_shader_parameter("mask", _mask_tex)
	_text_sprite.material = mat

	_eraser_sprite = Sprite2D.new()
	_eraser_sprite.texture = config.eraser
	_eraser_sprite.scale = Vector2.ONE * config.eraser_scale
	_eraser_sprite.z_index = 1
	_eraser_sprite.visible = false     # appears when the game starts
	add_child(_eraser_sprite)

	if config.instructions:
		_instr_sprite = _make_sprite(config.instructions, s, 20)
		var im := ShaderMaterial.new()
		im.shader = CLIP_SHADER
		_instr_sprite.material = im

func _make_sprite(tex: Texture2D, s: float, z: int) -> Sprite2D:
	var sp := Sprite2D.new()
	sp.texture = tex
	sp.centered = false
	sp.position = _layer.position
	sp.scale = Vector2(s, s)
	sp.z_index = z
	add_child(sp)
	return sp

func _process(_delta: float) -> void:
	if not running:
		return
	var pr := config.player_radius
	_player.position = Vector2(
		clampf(_player.position.x, _arena.position.x + pr, _arena.end.x - pr),
		clampf(_player.position.y, _arena.position.y + pr, _arena.end.y - pr))
	var tip := _player.position + config.eraser_offset
	if _eraser_sprite:
		_eraser_sprite.position = tip
	if _done:
		return
	_erase_along(tip)
	if _dirty:
		_dirty = false
		_mask_img.set_data(_mask_w, _mask_h, false, Image.FORMAT_R8, _mask)
		_mask_tex.update(_mask_img)
		if progress() >= config.target_fraction:
			_done = true
			Game.input_locked = true
			finished.emit(true)

# Stamps every few units between the last position and this one so fast
# movement leaves a continuous trail.
func _erase_along(tip: Vector2) -> void:
	if _last == Vector2.INF:
		_last = tip
	var step := maxf(config.erase_radius * 0.4, 4.0)
	var dist := _last.distance_to(tip)
	var n := maxi(int(dist / step), 1)
	for i in n:
		_stamp(_last.lerp(tip, float(i + 1) / n))
	_last = tip

func _stamp(p: Vector2) -> void:
	var c := (p - _layer.position) / _layer.size * Vector2(_mask_w, _mask_h)
	var r := config.erase_radius / _layer.size.x * _mask_w
	var x0 := maxi(int(floor(c.x - r)), 0)
	var x1 := mini(int(ceil(c.x + r)), _mask_w - 1)
	var y0 := maxi(int(floor(c.y - r)), 0)
	var y1 := mini(int(ceil(c.y + r)), _mask_h - 1)
	var r2 := r * r
	for y in range(y0, y1 + 1):
		var dy := y - c.y
		for x in range(x0, x1 + 1):
			var dx := x - c.x
			if dx * dx + dy * dy > r2:
				continue
			var i := y * _mask_w + x
			if _mask[i] != 0:
				_mask[i] = 0
				_dirty = true
				if _is_text[i] == 1:
					_erased += 1
