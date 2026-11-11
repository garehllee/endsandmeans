extends Control
class_name DesktopWindow

signal focused

@export var title_text := "untitled.txt"
@export var can_minimize := true    # off for minigames and other world windows

const MIN_SIZE := 50.0              # the minimize button, top right
const MIN_PAD := 25.0
@onready var title: RichTextLabel = $Title

var dragging := false
var grab_offset := Vector2.ZERO
var minimized := false
var _min_btn: TextureRect
var _min_press := false
var _min_icon: MinimizedIcon
var _home_pos := Vector2.ZERO

func _ready() -> void:
	title.text = "[u]" + title_text + "[/u]"
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	global_position = _clamp_to_viewport(global_position)
	_apply_move_cursor(self)
	if can_minimize:
		_min_btn = TextureRect.new()
		_min_btn.texture = MinimizeIcons.BUTTON
		_min_btn.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_min_btn.size = Vector2(MIN_SIZE, MIN_SIZE)
		_min_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_min_btn.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(_min_btn)
		resized.connect(_place_min_btn)
		_place_min_btn.call_deferred()
	visibility_changed.connect(_on_visibility_changed)

func _apply_move_cursor(node: Node) -> void:
	if node is SubViewportContainer:
		node.mouse_filter = Control.MOUSE_FILTER_STOP   # must not be Ignore, or hover inside the viewport dies
	if node is Control and not node is ScrollBar:
		node.mouse_default_cursor_shape = Control.CURSOR_MOVE
	for child in node.get_children():
		_apply_move_cursor(child)

func _place_min_btn() -> void:
	if _min_btn:
		_min_btn.position = Vector2(size.x - MIN_PAD - MIN_SIZE, MIN_PAD)

func _over_min_btn() -> bool:
	return _min_btn != null and _min_btn.get_global_rect().has_point(get_global_mouse_position())

func _input(event: InputEvent) -> void:
	if can_minimize and visible and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _over_min_btn() and _topmost_window_at(get_global_mouse_position()) == self:
				_min_press = true
				get_viewport().set_input_as_handled()   # not the start of a drag
				return
		elif _min_press:
			_min_press = false
			get_viewport().set_input_as_handled()
			if _over_min_btn():
				minimize()
			return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _topmost_window_at(get_global_mouse_position()) == self:
				bring_to_front()
				dragging = true
				grab_offset = get_global_mouse_position() - global_position
		else:
			dragging = false
	elif event is InputEventMouseMotion and dragging:
		global_position = _clamp_to_viewport(get_global_mouse_position() - grab_offset)

func bring_to_front() -> void:
	var p := get_parent()
	if p.get_child(-1) != self:
		p.move_child(self, -1)
	focused.emit()

func _topmost_window_at(point: Vector2) -> DesktopWindow:
	var siblings := get_parent().get_children()
	siblings.reverse()
	for s in siblings:
		if s is DesktopWindow and s.visible and s.get_global_rect().has_point(point):
			return s
	return null

func _clamp_to_viewport(pos: Vector2) -> Vector2:
	var bounds := get_viewport_rect().size
	return Vector2(
		clampf(pos.x, 0.0, maxf(0.0, bounds.x - size.x)),
		clampf(pos.y, 0.0, maxf(0.0, bounds.y - size.y))
	)

# ---------------------------------------------------------------- minimizing
# The window turns into its file icon on the desktop (see MinimizeIcons).
func minimize() -> void:
	if minimized or not can_minimize or not visible:
		return
	var layer := get_tree().get_first_node_in_group("icon_layer") as Control
	if layer == null:
		return
	minimized = true
	dragging = false
	_home_pos = global_position
	var info := MinimizeIcons.for_title(title_text)
	var icon := MinimizedIcon.new()
	icon.setup(self, info["tex"], info["tint"], title_text)
	layer.add_child(icon)
	icon.global_position = _free_spot(layer, icon, get_global_rect().get_center() - icon.size * 0.5)
	icon.modulate.a = 0.0
	icon.scale = Vector2.ONE * 0.6
	_min_icon = icon
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate:a", 0.0, 0.18)
	tw.tween_property(icon, "modulate:a", 1.0, 0.25)
	tw.tween_property(icon, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(func():
		if minimized:
			visible = false
			modulate.a = 1.0)

# A spot near `want` that doesn't sit on top of another minimized icon.
func _free_spot(layer: Control, icon: Control, want: Vector2) -> Vector2:
	var bounds := get_viewport_rect().size
	var p := Vector2(clampf(want.x, 0.0, maxf(0.0, bounds.x - icon.size.x)), clampf(want.y, 0.0, maxf(0.0, bounds.y - icon.size.y)))
	for attempt in 40:
		var clash := false
		for other in layer.get_children():
			if other is MinimizedIcon and other != icon and Rect2(p, icon.size).intersects(other.get_global_rect()):
				clash = true
				break
		if not clash:
			break
		p.x += icon.size.x + 20.0
		if p.x + icon.size.x > bounds.x:
			p.x = 20.0
			p.y = fposmod(p.y + icon.size.y + 20.0, maxf(1.0, bounds.y - icon.size.y))
	return p

# Clicking the icon opens the window again, where it was.
func restore() -> void:
	if not minimized:
		return
	minimized = false
	if _min_icon and is_instance_valid(_min_icon):
		_min_icon.queue_free()
	_min_icon = null
	global_position = _clamp_to_viewport(_home_pos)
	modulate.a = 0.0
	visible = true
	bring_to_front()
	create_tween().tween_property(self, "modulate:a", 1.0, 0.25)

# Something else showed the window (a world opening, a flag): it is no longer minimized.
func _on_visibility_changed() -> void:
	if visible and minimized:
		minimized = false
		if _min_icon and is_instance_valid(_min_icon):
			_min_icon.queue_free()
		_min_icon = null
