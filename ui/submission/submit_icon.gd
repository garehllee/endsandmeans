extends Control
class_name SubmitIcon
# A small file on the desktop that can be dragged into the submission box. It
# floats gently while it sits there. When it is let go, `dropped` tells the
# submission window where, and the window decides if it landed in the box.

signal dropped(icon: SubmitIcon, mouse_global: Vector2)

const ICON_H := 130.0
const LABEL_SIZE := 38

var item_id := ""
var label_text := ""
var texture: Texture2D
var tint := Color.WHITE
var sheet: Texture2D           # optional: an animated sprite sheet drawn instead of `texture`
var sheet_cols := 1
var sheet_rows := 1
var sheet_frames := 1
var sheet_fps := 30.0
var icon_h := ICON_H           # drawn height of the picture
var home := Vector2.ZERO       # where it sits on the desktop; it flies back here when returned
var font: Font

var _dragging := false
var _grab := Vector2.ZERO
var _t := 0.0
var _phase := randf() * TAU
var _busy := false             # true while it is flying in or out (can't be grabbed)

func _ready() -> void:
	custom_minimum_size = Vector2(maxf(240.0, icon_h * 1.6), icon_h + 70.0)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

func is_dragging() -> bool:
	return _dragging

func set_busy(b: bool) -> void:
	_busy = b

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _draw() -> void:
	var bob := 0.0                 # sits still
	var a := 0.85 if _dragging else 1.0
	if sheet:
		var fw := sheet.get_width() / float(sheet_cols)
		var fh := sheet.get_height() / float(sheet_rows)
		var fr := int(_t * sheet_fps) % sheet_frames
		var w := icon_h * fw / fh
		draw_texture_rect_region(sheet, Rect2((size.x - w) * 0.5, bob, w, icon_h),
				Rect2((fr % sheet_cols) * fw, (fr / sheet_cols) * fh, fw, fh), Color(tint.r, tint.g, tint.b, a))
	elif texture:
		var ts := texture.get_size()
		var w := icon_h * ts.x / ts.y
		draw_texture_rect(texture, Rect2((size.x - w) * 0.5, bob, w, icon_h), false,
				Color(tint.r, tint.g, tint.b, a))
	var f: Font = font if font else ThemeDB.fallback_font
	var pos := Vector2(0, icon_h + 50 + bob)
	draw_string(f, pos, label_text, HORIZONTAL_ALIGNMENT_CENTER, size.x, LABEL_SIZE, Color.WHITE)

func _input(event: InputEvent) -> void:
	if not visible or _busy or Game.active_world in ["ending", "exploit", "analysis"]:
		return   # not while a choice screen, minigame or ending is covering the desktop
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if get_global_rect().has_point(get_global_mouse_position()):
				_dragging = true
				_grab = get_global_mouse_position() - global_position
				get_parent().move_child(self, -1)            # above the other icons
				get_viewport().set_input_as_handled()        # so no window under it starts dragging
		elif _dragging:
			_dragging = false
			get_viewport().set_input_as_handled()
			dropped.emit(self, get_global_mouse_position())
	elif event is InputEventMouseMotion and _dragging:
		var bounds := get_viewport_rect().size
		global_position = Vector2(
			clampf(get_global_mouse_position().x - _grab.x, 0.0, maxf(0.0, bounds.x - size.x)),
			clampf(get_global_mouse_position().y - _grab.y, 0.0, maxf(0.0, bounds.y - size.y)))
		get_viewport().set_input_as_handled()
