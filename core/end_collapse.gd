extends Control
class_name EndCollapse
# What happens to the desktop when the game ends, before the ending shows:
# every open window minimizes itself, each a moment apart, and then the icons
# start copying themselves all over the screen while the picture glitches.
# Story.end_with() waits for play() before it opens the ending. The windows
# come back when the ending closes (going back to before it happened);
# starting over reloads everything anyway.
#
# It sits at the bottom of the window layer, so the ending window opens on
# top of the mess.

const FONT := preload("res://fonts/Director-Regular.otf")
const GLITCH := preload("res://shaders/glitch.gdshader")
const ICON := 300.0                 # the same as a minimized window's icon
const LABEL_SIZE := 44

@export var stagger := 0.8          # the windows minimize somewhere in this long, one by one
@export var settle := 0.45          # after the last one, before the copying starts
@export var copy_time := 2.6        # copying and glitching, before the ending opens
@export var copy_rate := Vector2(6, 150)  # copies a second, at the start and at the end
@export var max_copies := 600
@export var near_share := 0.45      # how many copies land just beside the icon they copy
@export var calm_time := 0.6        # the glitch dies down this long once the ending is up

var _ghosts: Array[Ghost] = []
var _hidden: Array[CanvasItem] = []  # windows and the icon layer, to bring back after
var _glitch: ColorRect
var _copy: BackBufferCopy             # grabs the screen just before the glitch draws
var _amount := 0.0
var _seed_t := 0.0
var _running := false
var _copying := false
var _copy_t := 0.0
var _owed := 0.0

# One icon: a picture with its name underneath, like a minimized window.
class Ghost extends Control:
	var texture: Texture2D
	var tint := Color.WHITE
	var label := ""
	var icon := ICON
	var jitter := Vector2.ZERO
	var _jitter_t := 0.0

	func setup(tex: Texture2D, colour: Color, text: String, icon_size := ICON) -> void:
		texture = tex
		tint = colour
		label = text
		icon = icon_size
		var tw := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE).x
		size = Vector2(maxf(icon, tw) + 20.0, icon + 80.0)
		pivot_offset = size * 0.5
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func twitch(by: Vector2, time: float) -> void:
		jitter = by
		_jitter_t = time
		queue_redraw()

	func _process(delta: float) -> void:
		if _jitter_t > 0.0:
			_jitter_t -= delta
			if _jitter_t <= 0.0:
				jitter = Vector2.ZERO
				queue_redraw()

	func _draw() -> void:
		var o := jitter
		if texture:
			draw_texture_rect(texture, Rect2(o + Vector2((size.x - icon) * 0.5, 0), Vector2(icon, icon)), false, tint)
		draw_string(FONT, o + Vector2(0, icon + 56), label, HORIZONTAL_ALIGNMENT_CENTER, size.x, LABEL_SIZE, Color.WHITE)
		var lw := FONT.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE).x
		var ux := (size.x - lw) * 0.5
		draw_line(o + Vector2(ux, icon + 62.0), o + Vector2(ux + lw, icon + 62.0), Color.WHITE, 2.0)

func _ready() -> void:
	add_to_group("end_collapse")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_copy = BackBufferCopy.new()
	_copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	add_child(_copy)
	_glitch = ColorRect.new()
	_glitch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glitch.material = ShaderMaterial.new()
	(_glitch.material as ShaderMaterial).shader = GLITCH
	_glitch.visible = false
	add_child(_glitch)
	Game.world_closed.connect(func(id: String, _r: Dictionary): if id == "ending": _restore())

# Minimizes everything, copies it all over the screen, and returns when the
# ending should open.
func play() -> void:
	if _running:
		return
	_running = true
	var was_locked := Game.input_locked
	# the window layer has no size of its own: cover the screen explicitly
	global_position = Vector2.ZERO
	size = get_viewport_rect().size
	Game.input_locked = true
	move_to_front_of_windows()
	var windows := _open_windows()
	var last := 0.0
	for w in windows:
		var wait := randf() * stagger
		last = maxf(last, wait)
		get_tree().create_timer(wait).timeout.connect(_minimize.bind(w))
	_take_icon_layer()
	await get_tree().create_timer(last + 0.3 + settle).timeout
	_copying = true
	_copy_t = 0.0
	_glitch.size = size
	_glitch.visible = true
	await get_tree().create_timer(copy_time).timeout
	_copying = false
	Game.input_locked = was_locked
	create_tween().tween_property(self, "_amount", 0.0, calm_time)

# Just under the other windows, so the ending opens over the top.
func move_to_front_of_windows() -> void:
	get_parent().move_child(self, 0)

func _open_windows() -> Array[DesktopWindow]:
	var out: Array[DesktopWindow] = []
	for n in get_tree().get_nodes_in_group("desktop_window"):
		var w := n as DesktopWindow
		if w == null or not w.visible or w.modulate.a < 0.05:
			continue
		# a world window that's already on its way out (the exploit that just ended)
		if w is WorldWindow and not w.keep_open_when_closed and Game.active_world != w.world_id:
			continue
		out.append(w)
	return out

# The window fades away and its icon pops up where it was, as if minimized.
func _minimize(w: DesktopWindow) -> void:
	if not is_instance_valid(w):
		return
	var tex: Texture2D
	var tint := Color.WHITE
	if w.as_item and w.get("normal_texture") is Texture2D:
		tex = w.get("normal_texture")
	else:
		var info := MinimizeIcons.for_title(w.title_text)
		tex = info["tex"]
		tint = info["tint"]
	var g := _add_ghost(tex, tint, w.title_text)
	g.position = _on_screen(w.get_global_rect().get_center() - g.size * 0.5 - global_position, g.size)
	_pop(g)
	_hidden.append(w)
	var tw := create_tween()
	tw.tween_property(w, "modulate:a", 0.0, 0.18)
	tw.tween_callback(func(): w.visible = false)

# What's already sitting on the desktop (minimized windows, files) joins in.
func _take_icon_layer() -> void:
	var layer := get_tree().get_first_node_in_group("icon_layer") as Control
	if layer == null:
		return
	for c in layer.get_children():
		var icon := c as Control
		if icon == null or not icon.visible:
			continue
		var tex = icon.get("texture")
		if not tex is Texture2D:
			continue
		var colour = icon.get("tint")
		var text = icon.get("label_text")
		var size_h = icon.get("icon_h")
		var g := _add_ghost(tex, colour if colour is Color else Color.WHITE,
				text if text is String else "", size_h if size_h is float else ICON)
		g.position = icon.global_position - global_position
	_hidden.append(layer)
	layer.visible = false

func _add_ghost(tex: Texture2D, colour: Color, text: String, icon_size := ICON) -> Ghost:
	var g := Ghost.new()
	g.setup(tex, colour, text, icon_size)
	add_child(g)
	move_child(_copy, -1)          # the copies stay under the glitch
	move_child(_glitch, -1)
	_ghosts.append(g)
	return g

func _pop(g: Ghost) -> void:
	g.modulate.a = 0.0
	g.scale = Vector2.ONE * 0.6
	var tw := create_tween().set_parallel(true)
	tw.tween_property(g, "modulate:a", 1.0, 0.2)
	tw.tween_property(g, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _on_screen(p: Vector2, s: Vector2) -> Vector2:
	var view := size
	return Vector2(clampf(p.x, -s.x * 0.3, view.x - s.x * 0.7), clampf(p.y, -s.y * 0.3, view.y - s.y * 0.7))

func _process(delta: float) -> void:
	if not _running:
		return
	if _copying:
		_copy_t += delta
		var k := clampf(_copy_t / copy_time, 0.0, 1.0)
		_amount = lerpf(0.08, 1.0, k * k) * (0.6 + 0.4 * randf())
		if randf() < 0.04:
			_amount = 1.0            # a lurch
		_owed += lerpf(copy_rate.x, copy_rate.y, k * k) * delta
		while _owed >= 1.0 and _ghosts.size() < max_copies and not _ghosts.is_empty():
			_owed -= 1.0
			_copy_one()
		for g in _ghosts:
			if randf() < 0.015 * _amount:
				g.twitch(Vector2(randf_range(-60, 60), 0) * _amount, randf_range(0.04, 0.12))
	_seed_t -= delta
	if _seed_t <= 0.0:
		_seed_t = randf_range(0.03, 0.09)
		(_glitch.material as ShaderMaterial).set_shader_parameter("seed", randf() * 100.0)
	(_glitch.material as ShaderMaterial).set_shader_parameter("amount", _amount)
	_glitch.visible = _amount > 0.005

func _copy_one() -> void:
	var src: Ghost = _ghosts.pick_random()
	var g := _add_ghost(src.texture, src.tint, src.label, src.icon)
	var at: Vector2
	if randf() < near_share:
		at = src.position + Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized() * randf_range(80, 260)
	else:
		at = Vector2(randf() * size.x, randf() * size.y) - g.size * 0.5
	g.position = _on_screen(at, g.size)
	_pop(g)

# Going back to before it happened: the copies go and the windows come back.
func _restore() -> void:
	if not _running:
		return
	_running = false
	_copying = false
	_amount = 0.0
	_glitch.visible = false
	var ghosts := _ghosts.duplicate()
	_ghosts.clear()
	var tw := create_tween().set_parallel(true)
	for g in ghosts:
		tw.tween_property(g, "modulate:a", 0.0, 0.25)
	tw.chain().tween_callback(func():
		for g in ghosts:
			if is_instance_valid(g):
				g.queue_free())
	for item in _hidden:
		if not is_instance_valid(item):
			continue
		item.visible = true
		item.modulate.a = 0.0
		create_tween().tween_property(item, "modulate:a", 1.0, 0.3)
	_hidden.clear()
