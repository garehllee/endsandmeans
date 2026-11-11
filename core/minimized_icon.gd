extends Control
class_name MinimizedIcon
# What a minimized window looks like on the desktop: its file icon with the
# window's full name underneath. Click it (without dragging) to open the window
# again; drag it to move it around.

const ICON := 300.0
const LABEL_SIZE := 44
const CLICK_SLOP := 8.0        # pixels the pointer may travel and still count as a click
const FONT := preload("res://fonts/Director-Regular.otf")

var window: DesktopWindow
var texture: Texture2D
var tint := Color.WHITE
var label_text := ""

var _pressed := false
var _moved := false
var _grab := Vector2.ZERO
var _press_pos := Vector2.ZERO

func setup(w: DesktopWindow, tex: Texture2D, color: Color, label: String) -> void:
	window = w
	texture = tex
	tint = color
	label_text = label
	var tw := FONT.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE).x
	size = Vector2(maxf(ICON, tw) + 20.0, ICON + 80.0)
	custom_minimum_size = size
	pivot_offset = size * 0.5

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

func _draw() -> void:
	if texture:
		draw_texture_rect(texture, Rect2((size.x - ICON) * 0.5, 0, ICON, ICON), false, tint)
	draw_string(FONT, Vector2(0, ICON + 56), label_text, HORIZONTAL_ALIGNMENT_CENTER, size.x, LABEL_SIZE, Color.WHITE)

func _input(event: InputEvent) -> void:
	if not visible or Game.active_world in ["ending", "exploit", "analysis"]:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if get_global_rect().has_point(get_global_mouse_position()):
				_pressed = true
				_moved = false
				_press_pos = get_global_mouse_position()
				_grab = _press_pos - global_position
				get_parent().move_child(self, -1)
				get_viewport().set_input_as_handled()
		elif _pressed:
			_pressed = false
			get_viewport().set_input_as_handled()
			if not _moved and window != null:
				window.restore()
	elif event is InputEventMouseMotion and _pressed:
		if not _moved and get_global_mouse_position().distance_to(_press_pos) > CLICK_SLOP:
			_moved = true
		if _moved:
			var bounds := get_viewport_rect().size
			global_position = Vector2(
				clampf(get_global_mouse_position().x - _grab.x, 0.0, maxf(0.0, bounds.x - size.x)),
				clampf(get_global_mouse_position().y - _grab.y, 0.0, maxf(0.0, bounds.y - size.y)))
		get_viewport().set_input_as_handled()
