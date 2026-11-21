extends Control
class_name DesktopWindow

signal focused

@export var title_text := "untitled.txt"
@export var can_minimize := true    # off for minigames and other world windows
@export var draggable := true       # off for the ending, which fills the screen
@export var as_item := false        # an object on the desktop, not a program: no bar or frame, its name underneath

# The bar along the top: the window's icon, its name and the minimize button,
# all in the colour of the icon. Its outline and the frame's share the line
# between them.
const MIN_SIZE := 60.0              # the minimize button, right end of the bar
const MIN_PAD := 20.0
const TITLE_SIZE := 52              # shrinks to fit narrow windows
const ITEM_LABEL := 80.0            # an item's name, under it
const ITEM_LABEL_SIZE := 44         # the same as a minimized window's icon
@onready var bar: Panel = $Bar
@onready var title: RichTextLabel = $Bar/Title

var dragging := false
var grab_offset := Vector2.ZERO
var minimized := false
var _min_btn: TextureRect
var _min_press := false
var _min_icon: MinimizedIcon
var _home_pos := Vector2.ZERO

func _ready() -> void:
	if as_item:
		_dress_item()
	else:
		_dress_bar()
	global_position = _clamp_to_viewport(global_position)
	add_to_group("desktop_window")
	_apply_move_cursor(self)
	if can_minimize and not as_item:
		_min_btn = TextureRect.new()
		_min_btn.texture = MinimizeIcons.BUTTON
		_min_btn.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_min_btn.size = Vector2(MIN_SIZE, MIN_SIZE)
		_min_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_min_btn.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		bar.add_child(_min_btn)
	resized.connect(_place_bar)
	_place_bar.call_deferred()
	visibility_changed.connect(_on_visibility_changed)
	Game.world_opened.connect(func(_id: String, _p: Dictionary): _update_min_btn())
	Game.world_closed.connect(func(_id: String, _r: Dictionary): _update_min_btn())

func _dress_bar() -> void:
	var info := MinimizeIcons.for_title(title_text)
	var colour: Color = info["bar"]
	var box := (bar.get_theme_stylebox("panel") as StyleBoxFlat).duplicate() as StyleBoxFlat
	box.bg_color = colour
	bar.add_theme_stylebox_override("panel", box)
	var icon := $Bar/Icon as TextureRect
	icon.texture = info["tex"]
	icon.self_modulate = info["tint"]
	title.add_theme_color_override("default_color", MinimizeIcons.text_on(colour))
	title.text = "[u]" + title_text + "[/u]"

# Items keep the old look: the picture on its own, the name underlined below.
func _dress_item() -> void:
	can_minimize = false
	bar.visible = false
	var frame := $Frame as PanelContainer
	frame.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	frame.offset_top = 0.0
	frame.offset_bottom = -ITEM_LABEL
	title.reparent(self, false)
	title.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	title.offset_top = -ITEM_LABEL
	title.offset_bottom = 0.0
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("normal_font_size", ITEM_LABEL_SIZE)
	title.text = "[u]" + title_text + "[/u]"

func _place_bar() -> void:
	if as_item:
		return
	if _min_btn:
		_min_btn.position = Vector2(bar.size.x - MIN_PAD - MIN_SIZE, (bar.size.y - MIN_SIZE) * 0.5)
	# The name gets the room between the icon and the button, smaller if it must.
	var room := bar.size.x - title.offset_left - (MIN_PAD * 2.0 + MIN_SIZE if _min_btn else MIN_PAD)
	title.offset_right = -(bar.size.x - title.offset_left - room)
	var font := title.get_theme_font("normal_font")
	var px := TITLE_SIZE
	while px > 12 and font.get_string_size(title_text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > room - 12.0:
		px -= 2
	title.add_theme_font_size_override("normal_font_size", px)

func _apply_move_cursor(node: Node) -> void:
	if node is SubViewportContainer:
		node.mouse_filter = Control.MOUSE_FILTER_STOP   # must not be Ignore, or hover inside the viewport dies
	if node is Control and not node is ScrollBar and draggable:
		node.mouse_default_cursor_shape = Control.CURSOR_MOVE
	for child in node.get_children():
		_apply_move_cursor(child)

# No minimizing (and no button) while a minigame, choice screen or ending is open.
func _minimize_blocked() -> bool:
	return Game.active_world in ["analysis", "exploit", "ending"]

func _update_min_btn() -> void:
	if _min_btn:
		_min_btn.visible = not _minimize_blocked()

func _over_min_btn() -> bool:
	return _min_btn != null and _min_btn.visible and _min_btn.get_global_rect().has_point(get_global_mouse_position())

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
				dragging = draggable
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

# Shows the window for the first time (or again after being hidden), the way
# every "it just unlocked / arrived" window on the desktop does: try to land
# it somewhere that isn't already covered by another open window or desktop
# icon, falling back to dead center if nothing's free, then fade it in on
# top. Not used for restoring a minimized window -- that goes back to
# exactly where it was (see restore()).
func open_fresh(fade := 0.3) -> void:
	global_position = DesktopLayout.find_spot(size, global_position,
			DesktopLayout.occupied_rects(get_tree(), self), get_viewport_rect().size)
	visible = true
	modulate.a = 0.0
	bring_to_front()
	create_tween().tween_property(self, "modulate:a", 1.0, fade)

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
	if minimized or not can_minimize or not visible or _minimize_blocked():
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
	# where the window was (it's still fading out, so it doesn't count as in the way)
	icon.global_position = DesktopLayout.find_spot(icon.size, get_global_rect().get_center() - icon.size * 0.5,
			DesktopLayout.occupied_rects(get_tree(), icon, self), get_viewport_rect().size)
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
