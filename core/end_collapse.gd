extends Control
class_name EndCollapse
# What happens to the desktop when the game ends, before the ending shows:
# the open windows minimize one after another, left to right, and then each
# icon sets off across the screen leaving a trail of copies of itself behind
# (like a stuck window being dragged), faster and faster, while the picture
# glitches. When the ending opens, everything behind it fades to black.
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

@export var stagger := 0.16         # between one window minimizing and the next (left to right)
@export var stagger_jitter := 0.04  # a little either way, so it isn't mechanical
@export var settle := 0.45          # after the last one, before the copying starts
@export var copy_time := 2.6        # copying and glitching, before the ending opens
@export var trail_speed := Vector2(350, 2600)   # how fast each trail moves, at the start and at the end
@export var trail_step := 70.0      # a copy is left every this far along
@export var trail_turn := 0.9       # how hard the trails curve, radians a second
@export var max_copies := 700
@export var black_time := 0.8       # behind the ending: the copies fade to black over this long

var _ghosts: Array[Ghost] = []
var _hidden: Array[CanvasItem] = []  # windows and the icon layer, to bring back after
var _glitch: ColorRect
var _copy: BackBufferCopy             # grabs the screen just before the glitch draws
var _amount := 0.0
var _seed_t := 0.0
var _patch_t := 0.0
var _running := false
var _copying := false
var _copy_t := 0.0
var _trails: Array[Dictionary] = []   # {ghost, pos, angle, turn, since}: one per icon
var _black: ColorRect

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
	_black = ColorRect.new()
	_black.color = Color(0, 0, 0, 0)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_black)
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
	_glitch.size = size
	_black.size = size
	var windows := _open_windows()
	windows.sort_custom(func(a: DesktopWindow, b: DesktopWindow): return a.global_position.x < b.global_position.x)
	var last := 0.0
	for i in windows.size():
		var wait := maxf(0.0, i * stagger + randf_range(-stagger_jitter, stagger_jitter))
		last = maxf(last, wait)
		get_tree().create_timer(wait).timeout.connect(_minimize.bind(windows[i]))
	_take_icon_layer()
	await get_tree().create_timer(last + 0.3 + settle).timeout
	_start_trails()
	_copying = true
	_copy_t = 0.0
	_glitch.visible = true
	Audio.play("collapse")
	await get_tree().create_timer(copy_time).timeout
	_copying = false
	Game.input_locked = was_locked
	# the ending opens now; behind it, everything goes to black
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_black, "color:a", 1.0, black_time)
	tw.tween_property(self, "_amount", 0.0, black_time)

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
	_appear(g)
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
	move_child(_black, -1)
	_ghosts.append(g)
	return g

# A minimized window's icon settles in (no overshoot).
func _appear(g: Ghost) -> void:
	g.modulate.a = 0.0
	g.scale = Vector2.ONE * 0.85
	var tw := create_tween().set_parallel(true)
	tw.tween_property(g, "modulate:a", 1.0, 0.2)
	tw.tween_property(g, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

# Every icon gets a trail. They head out evenly spread around, away from the
# middle of the screen, each curving the same way.
func _start_trails() -> void:
	_trails.clear()
	var heads := _ghosts.duplicate()
	var centre := size * 0.5
	for i in heads.size():
		var g: Ghost = heads[i]
		var from_centre := g.position + g.size * 0.5 - centre
		var angle := from_centre.angle() if from_centre.length() > 50.0 else TAU * i / maxf(1.0, heads.size())
		_trails.append({"ghost": g, "pos": g.position, "angle": angle,
				"turn": trail_turn * (1.0 if i % 2 == 0 else -1.0), "since": 0.0})

func _on_screen(p: Vector2, s: Vector2) -> Vector2:
	var view := size
	return Vector2(clampf(p.x, -s.x * 0.3, view.x - s.x * 0.7), clampf(p.y, -s.y * 0.3, view.y - s.y * 0.7))

func _process(delta: float) -> void:
	if not _running:
		return
	if _copying:
		_copy_t += delta
		var k := clampf(_copy_t / copy_time, 0.0, 1.0)
		_amount = lerpf(0.05, 0.9, k * k) * (0.8 + 0.2 * randf())
		var speed := lerpf(trail_speed.x, trail_speed.y, k * k)
		for t in _trails:
			_move_trail(t, speed, delta)
		for g in _ghosts:
			if randf() < 0.006 * _amount:
				g.twitch(Vector2(randf_range(-40, 40), 0) * _amount, randf_range(0.04, 0.1))
	_seed_t -= delta
	if _seed_t <= 0.0:
		_seed_t = randf_range(0.03, 0.09)
		(_glitch.material as ShaderMaterial).set_shader_parameter("seed", randf() * 100.0)
	_patch_t -= delta
	if _patch_t <= 0.0:
		_patch_t = randf_range(0.12, 0.45)    # which parts of the screen are broken, and how
		(_glitch.material as ShaderMaterial).set_shader_parameter("patches", randf() * 100.0)
	(_glitch.material as ShaderMaterial).set_shader_parameter("amount", _amount)
	_glitch.visible = _amount > 0.005

# The trail moves on along its curve, bouncing off the edges of the screen,
# and leaves a copy every trail_step. The newest copy is always on top.
func _move_trail(t: Dictionary, speed: float, delta: float) -> void:
	var src: Ghost = t["ghost"]
	var step := speed * delta
	var travelled := 0.0
	while travelled < step:
		var d := minf(trail_step - float(t["since"]), step - travelled)
		var angle: float = t["angle"] + float(t["turn"]) * d / speed
		var p: Vector2 = t["pos"] + Vector2.from_angle(angle) * d
		# bounce
		var lo := -src.size * 0.2
		var hi := size - src.size * 0.8
		if p.x < lo.x or p.x > hi.x:
			angle = PI - angle
			p.x = clampf(p.x, lo.x, hi.x)
		if p.y < lo.y or p.y > hi.y:
			angle = -angle
			p.y = clampf(p.y, lo.y, hi.y)
		t["angle"] = angle
		t["pos"] = p
		t["since"] = float(t["since"]) + d
		travelled += d
		if float(t["since"]) >= trail_step - 0.001:
			t["since"] = 0.0
			if _ghosts.size() < max_copies:
				var g := _add_ghost(src.texture, src.tint, src.label, src.icon)
				g.position = p

# Going back to before it happened: the copies go and the windows come back.
func _restore() -> void:
	if not _running:
		return
	_running = false
	_copying = false
	_amount = 0.0
	_glitch.visible = false
	_trails.clear()
	create_tween().tween_property(_black, "color:a", 0.0, 0.3)
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
