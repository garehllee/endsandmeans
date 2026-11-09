extends Node2D
class_name FileWall

signal entry_entered(entry: Dictionary, index: int)

@export var wall_size := Vector2(620, 390)
@export var floor_height := 230.0      # wall + floor should add up to one screen
@export var focus_strength := 5.0      # non-image strips open to this many resting widths
@export var min_open_width := 140.0    # ...but never less than this many px
@export var max_open_fraction := 0.85  # an open strip never takes more than this share of the wall
@export var smoothing := 10.0
@export var entry_margin := 40.0       # files: how close to the wall counts as "walked in"
@export var hallway_depth := 24.0      # folders: how far up the open strip before the room appears
@export var open_threshold := 0.85     # a folder strip is walkable once it's this open (0 to 1)
@export var solid_bottom := true       # root room only
@export var label_color := Color.WHITE
@export var label_size := 16
@export var font: Font
@export var folder_icon: Texture2D
@export var icon_size := 56.0
@export var edge_inset := 24.0   # about half the player's collision width, plus a few px
@export var near_distance := 200.0     # how close to the wall counts as "close enough" (scale up for bigger rooms)
@export var announce_cooldown := 1.5   # minimum seconds between lines, so sliding along the wall doesn't spam
@export var blink_color := Color.WHITE
@export var blink_alpha := 0.85
@export var blink_time := 0.14          # seconds per on or off phase

const SETTINGS := ["wall_size", "floor_height", "focus_strength", "min_open_width",
		"max_open_fraction", "smoothing", "entry_margin", "hallway_depth",
		"open_threshold", "label_color", "label_size", "font", "folder_icon", "icon_size",
		"edge_inset", "near_distance", "announce_cooldown"]

const PALETTES := [
	[Color("#ff00a0"), Color("9549ffff"), Color("3e63ffff")],
	[Color("a548ffff"), Color("00a4cfff"), Color("0bd500ff")],
	[Color("#3dff00"), Color("#00d0a0")],
	[Color("c30000ff"), Color("ff8bb1ff")],
	[Color("#2f6bff"), Color("#00f0ff"), Color("#3dff00")],
]
const IMAGE_EXTS := ["png", "jpg", "jpeg", "webp"]

const LUMINOSITY_CODE := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

float lum(vec3 c) { return dot(c, vec3(0.3, 0.59, 0.11)); }

vec3 clip_color(vec3 c) {
	float l = lum(c);
	float n = min(min(c.r, c.g), c.b);
	float x = max(max(c.r, c.g), c.b);
	if (n < 0.0) c = l + (c - l) * l / (l - n);
	if (x > 1.0) c = l + (c - l) * (1.0 - l) / (x - l);
	return c;
}

vec3 set_lum(vec3 c, float l) { return clip_color(c + (l - lum(c))); }

void fragment() {
	vec4 src = texture(TEXTURE, UV) * COLOR;
	vec3 back = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;
	// Luminosity: keep the backdrop's hue and saturation, take the icon's brightness.
	COLOR = vec4(set_lum(back, lum(src.rgb)), src.a);
}
"""

var _icons: Node2D

static var _tex_cache := {}   # path -> Texture2D, shared by every room

var active := true
var floor_grad := -1
var hallway_index := -1

var _gradients: Array[GradientTexture2D] = []
var _items: Array[Dictionary] = []
var _pending: Array[Dictionary] = []
var _shapes: Array[CollisionShape2D] = []
var _body: StaticBody2D
var _player: Node2D
var _focus := 0
var _inside := -1
var _announced := -1
var _last_announce := -999.0

var _blink_ids: Array[int] = []
var _blink_a := 0.0
var _blink_pending_ids: Array[int] = []
var _blink_pending_n := 0
var _blink_tween: Tween

func _ready() -> void:
	for p in PALETTES:
		var offs := PackedFloat32Array()
		for i in p.size():
			offs.append(i / float(p.size() - 1))
		var g := Gradient.new()
		g.offsets = offs
		g.colors = PackedColorArray(p)
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill_from = Vector2(0, 0)
		t.fill_to = Vector2(1, 0)     # left to right
		t.width = 128
		t.height = 8
		_gradients.append(t)
	_build_bounds()
	var shader := Shader.new()
	shader.code = LUMINOSITY_CODE
	var mat := ShaderMaterial.new()
	mat.shader = shader
	_icons = Node2D.new()
	_icons.material = mat
	_icons.draw.connect(_draw_icons)
	add_child(_icons)

func copy_settings_from(o: FileWall) -> void:
	for s in SETTINGS:
		set(s, o.get(s))

func level_height() -> float:
	return wall_size.y + floor_height

func gradient_of(index: int) -> int:
	return _items[index].grad

func _build_bounds() -> void:
	_body = StaticBody2D.new()
	add_child(_body)
	_add_box(Rect2(-20, 0, 20, level_height()))
	_add_box(Rect2(wall_size.x, 0, 20, level_height()))
	if solid_bottom:
		_add_box(Rect2(0, level_height(), wall_size.x, 20))

func _add_box(r: Rect2) -> CollisionShape2D:
	var s := RectangleShape2D.new()
	s.size = r.size
	var c := CollisionShape2D.new()
	c.shape = s
	c.position = r.get_center()
	_body.add_child(c)
	return c

func build(files: Array) -> void:
	_items.clear()
	_pending.clear()
	for c in _shapes:
		c.queue_free()
	_shapes.clear()
	_focus = 0
	_inside = -1
	hallway_index = -1
	var rest_w := wall_size.x / maxf(files.size(), 1)
	for i in files.size():
		var it := {
			"entry": files[i],
			"grad": randi() % _gradients.size(),
			"open": 0.0,        # 0 = closed, 1 = fully open (smoothed)
			"open_w": rest_w,   # width this strip opens to (smoothed)
			"tex": null,
			"x": i * rest_w,
			"w": rest_w,
		}
		_items.append(it)
		_shapes.append(_add_box(Rect2(i * rest_w, 0, rest_w, wall_size.y)))
		_request_texture(it)
	if files.is_empty():
		_shapes.append(_add_box(Rect2(0, 0, wall_size.x, wall_size.y)))
	_update_collision()
	queue_redraw()

func lock_hallway(index: int) -> void:
	hallway_index = index
	active = false
	queue_redraw()

func unlock() -> void:
	hallway_index = -1
	_inside = -1
	active = true
	queue_redraw()
	if not _blink_pending_ids.is_empty():
		var ids := _blink_pending_ids.duplicate()
		var n := _blink_pending_n
		_blink_pending_ids.clear()
		await get_tree().create_timer(0.4).timeout   # let the strips settle first
		_play_blink(ids, n)

func _process(delta: float) -> void:
	_poll_textures()
	if not active or _items.is_empty():
		return
	if _player == null:
		for n in get_tree().get_nodes_in_group("player"):
			if n.get_viewport() == get_viewport():
				_player = n
		if _player == null:
			return
	var p := to_local(_player.global_position)
	var n := _items.size()
	var rest_w := wall_size.x / n
	_announce_near(p)
	_check_entry(p)

	# Map the player's reachable x-range onto the full wall, so edge strips can be focused.
	var u := clampf((p.x - edge_inset) / maxf(wall_size.x - 2.0 * edge_inset, 1.0), 0.0, 1.0)
	var fx := u * wall_size.x
	_focus = n - 1
	for i in n:
		if fx < _items[i].x + _items[i].w:
			_focus = i
			break

	var k := 1.0 - exp(-smoothing * delta)
	var changed := false
	var open_sum := 0.0
	var closed_sum := 0.0
	for i in n:
		var it := _items[i]
		var target_o := 1.0 if i == _focus else 0.0
		var new_o := lerpf(it.open, target_o, k)
		var new_ow := lerpf(it.open_w, _open_width_for(it, rest_w), k)
		if absf(new_o - it.open) > 0.0005 or absf(new_ow - it.open_w) > 0.05:
			changed = true
		it.open = new_o
		it.open_w = new_ow
		open_sum += new_o * new_ow
		closed_sum += 1.0 - new_o

	if changed:
		_layout(open_sum, closed_sum)
		_update_collision()
		queue_redraw()
	_check_entry(p)

# Images open to their natural width at wall height; everything else to a default.
func _open_width_for(it: Dictionary, rest_w: float) -> float:
	var w := maxf(rest_w * focus_strength, min_open_width)
	var tex: Texture2D = it.tex
	if tex:
		w = wall_size.y * tex.get_width() / float(tex.get_height())
	return clampf(w, rest_w, wall_size.x * max_open_fraction)

# Each strip is a blend between its open width and one shared closed width,
# so all the closed strips are equal and the total always fills the wall.
func _layout(open_sum: float, closed_sum: float) -> void:
	var n := _items.size()
	var q := maxf(minf(wall_size.x / n, (wall_size.x - open_sum) / maxf(closed_sum, 0.001)), 1.0)
	var total := 0.0
	for it in _items:
		total += (it.open * it.open_w + (1.0 - it.open) * q) * it.get("shrink", 1.0)
	var s := wall_size.x / maxf(total, 0.001)
	var x := 0.0
	for it in _items:
		var w: float = (it.open * it.open_w + (1.0 - it.open) * q) * it.get("shrink", 1.0) * s
		it.x = x
		it.w = w
		x += w

func _update_collision() -> void:
	for i in _items.size():
		var it := _items[i]
		var c := _shapes[i]
		(c.shape as RectangleShape2D).size = Vector2(it.w, wall_size.y)
		c.position = Vector2(it.x + it.w * 0.5, wall_size.y * 0.5)
		var walkable: bool = it.entry.type == "folder" and it.open > open_threshold
		c.set_deferred("disabled", walkable)

func _check_entry(p: Vector2) -> void:
	if p.y > wall_size.y + entry_margin:
		_inside = -1
		return
	var it := _items[_focus]
	if it.get("closing", false):
		return
	if _inside == _focus or p.x < it.x - edge_inset or p.x > it.x + it.w + edge_inset:
		return
	var is_folder: bool = it.entry.type == "folder"
	if it.open <= (open_threshold if is_folder else 0.5):
		return
	if is_folder and p.y >= wall_size.y - hallway_depth:
		return
	_inside = _focus
	entry_entered.emit(it.entry, _focus)

func _draw() -> void:
	if floor_grad >= 0:
		draw_texture_rect(_gradients[floor_grad], Rect2(0, wall_size.y, wall_size.x, floor_height), false)
	for i in _items.size():
		var it := _items[i]
		var r := Rect2(it.x, 0.0, it.w, wall_size.y)
		var tex: Texture2D = it.tex
		var shut: float = it.get("shrink", 1.0)
		if shut < 1.0:
			# Sliding shut: the picture stays put and the strip's right edge slides left.
			var g: Texture2D = tex if tex else _gradients[it.grad]
			var gs := g.get_size()
			draw_texture_rect_region(g, r, Rect2(0, 0, gs.x * shut, gs.y))
		elif tex:
			draw_texture_rect(tex, r, false)   # whole image, squeezed horizontally, never cropped
		else:
			draw_texture_rect(_gradients[it.grad], r, false)
		if i in _blink_ids and _blink_a > 0.0:
			draw_rect(r, Color(blink_color, _blink_a))
	if hallway_index < 0:
		_draw_label()
	_icons.queue_redraw()

func _draw_icons() -> void:
	for i in _items.size():
		var it := _items[i]
		if it.entry.type == "folder" and i != hallway_index:
			_draw_folder_icon(it)

func _draw_folder_icon(it: Dictionary) -> void:
	var a := clampf((it.open - 0.3) / 0.5, 0.0, 1.0)
	if a <= 0.0:
		return
	var s := minf(icon_size, it.w * 0.8)
	var cx: float = it.x + it.w * 0.5
	if folder_icon:
		var ts := folder_icon.get_size()
		var sz := Vector2(s, s * ts.y / ts.x)
		_icons.draw_texture_rect(folder_icon, Rect2(Vector2(cx - sz.x * 0.5, wall_size.y - sz.y - 24.0), sz), false, Color(1, 1, 1, a))
	else:
		var h := s * 0.75
		var top := wall_size.y - h - 24.0
		_icons.draw_rect(Rect2(cx - s * 0.5, top - s * 0.12, s * 0.4, s * 0.15), Color(1.0, 0.9, 0.3, a))
		_icons.draw_rect(Rect2(cx - s * 0.5, top, s, h), Color(1.0, 0.85, 0.2, a))
		_icons.draw_rect(Rect2(cx - s * 0.5, top, s, h), Color(1, 1, 1, a), false, 2.0)
func _draw_label() -> void:
	if _items.is_empty() or _focus >= _items.size():
		return
	var it := _items[_focus]
	if it.open < 0.3:
		return
	var f := font if font else ThemeDB.fallback_font
	var text: String = it.entry.name
	var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, label_size).x
	var lx := clampf(it.x + it.w * 0.5 - tw * 0.5, 0.0, maxf(0.0, wall_size.x - tw))
	var y := wall_size.y + 22.0
	draw_string(f, Vector2(lx, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, label_size, label_color)
	draw_line(Vector2(lx, y + 3), Vector2(lx + tw, y + 3), label_color, 1.0)

# ---- image loading (background threads, cached) ----

func _request_texture(it: Dictionary) -> void:
	var path: String = it.entry.get("path", "")
	if not (path.get_extension().to_lower() in IMAGE_EXTS):
		return
	if _tex_cache.has(path):
		it.tex = _tex_cache[path]
	elif path.begins_with("res://"):
		if ResourceLoader.exists(path):
			ResourceLoader.load_threaded_request(path)
			_pending.append(it)
	elif FileAccess.file_exists(path):
		_pending.append(it)

func _poll_textures() -> void:
	if _pending.is_empty():
		return
	var did_external := false
	for it in _pending.duplicate():
		var path: String = it.entry.path
		var tex: Texture2D = _tex_cache.get(path)
		if tex == null:
			if path.begins_with("res://"):
				var status := ResourceLoader.load_threaded_get_status(path)
				if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
					continue
				if status == ResourceLoader.THREAD_LOAD_LOADED:
					tex = ResourceLoader.load_threaded_get(path) as Texture2D
			elif not did_external:
				did_external = true    # files outside res:// load one per frame
				var img := Image.load_from_file(path)
				if img:
					tex = ImageTexture.create_from_image(img)
			else:
				continue
		if tex:
			_tex_cache[path] = tex
			it.tex = tex
		_pending.erase(it)
		queue_redraw()
func _announce_near(p: Vector2) -> void:
	if p.y > wall_size.y + near_distance:
		_announced = -1        # walked away, so the next approach counts as new
		return
	var it := _items[_focus]
	if it.open < 0.6 or _announced == _focus:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_announce < announce_cooldown:
		return
	_announced = _focus
	_last_announce = now
	var name: String = it.entry.name
	var key := "folder_near"
	if it.entry.type == "file":
		key = "image_near" if it.entry.get("path", "").get_extension().to_lower() in IMAGE_EXTS else "file_near"
	Game.say_random(key, {"item": name})

func add_entry(entry: Dictionary) -> int:
	var rest_w := wall_size.x / (_items.size() + 1)
	var it := {
		"entry": entry,
		"grad": randi() % _gradients.size(),
		"open": 0.0,
		"open_w": rest_w,
		"tex": null,
		"x": wall_size.x,
		"w": 1.0,
	}
	_items.append(it)
	_shapes.append(_add_box(Rect2(0, 0, 1, wall_size.y)))
	_request_texture(it)
	var open_sum := 0.0
	var closed_sum := 0.0
	for item in _items:
		open_sum += item.open * item.open_w
		closed_sum += 1.0 - item.open
	_layout(open_sum, closed_sum)
	_update_collision()
	queue_redraw()
	return _items.size() - 1
# Blinks one strip. Waits until the room is active if it's currently locked as a hallway.
func blink_entry(index: int, times := 3) -> void:
	blink_entries([index], times)

# Blinks several strips together (same wait as above).
func blink_entries(indices: Array, times := 3) -> void:
	if hallway_index >= 0 or not active:
		for i in indices:
			if not i in _blink_pending_ids:
				_blink_pending_ids.append(i)
		_blink_pending_n = times
		return
	_play_blink(indices, times)

func _play_blink(indices: Array, times: int) -> void:
	if _blink_tween and _blink_tween.is_valid():
		_blink_tween.kill()
	_blink_ids.clear()
	for i in indices:
		_blink_ids.append(i)
	_blink_tween = create_tween()
	for i in times:
		_blink_tween.tween_method(_set_blink, 0.0, blink_alpha, blink_time)
		_blink_tween.tween_method(_set_blink, blink_alpha, 0.0, blink_time)
	_blink_tween.finished.connect(func(): _blink_ids.clear())

func _set_blink(v: float) -> void:
	_blink_a = v
	queue_redraw()

# Deletes a file or folder from this room: its strip slides shut like a door and
# the others close up to fill the gap. Await this to know when it's gone.
func remove_entry(entry_name: String, slide_time := 0.6) -> bool:
	var found: Dictionary = {}
	for it in _items:
		if it.entry.name == entry_name:
			found = it
			break
	if found.is_empty():
		return false
	found["closing"] = true
	found["shrink"] = 1.0
	_blink_ids.clear()
	_blink_pending_ids.clear()
	var t := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	t.tween_method(func(v: float):
		found["shrink"] = v
		_layout_now()
		queue_redraw(), 1.0, 0.0, slide_time)
	await t.finished
	var i := _items.find(found)
	if i < 0:
		return true
	_items.remove_at(i)
	_shapes[i].queue_free()
	_shapes.remove_at(i)
	_inside = -1
	_announced = -1
	_focus = clampi(_focus, 0, maxi(_items.size() - 1, 0))
	if _items.is_empty():
		_shapes.append(_add_box(Rect2(0, 0, wall_size.x, wall_size.y)))   # nothing left: solid wall
	else:
		_layout_now()
	queue_redraw()
	return true

func _layout_now() -> void:
	var open_sum := 0.0
	var closed_sum := 0.0
	for item in _items:
		open_sum += item.open * item.open_w
		closed_sum += 1.0 - item.open
	_layout(open_sum, closed_sum)
	_update_collision()
