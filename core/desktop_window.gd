extends Control
class_name DesktopWindow

signal focused

@export var title_text := "untitled.txt"
@onready var title: RichTextLabel = $Title

var dragging := false
var grab_offset := Vector2.ZERO

func _ready() -> void:
	title.text = "[u]" + title_text + "[/u]"
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	global_position = _clamp_to_viewport(global_position)
	_apply_move_cursor(self) 

func _apply_move_cursor(node: Node) -> void:
	if node is SubViewportContainer:
		node.mouse_filter = Control.MOUSE_FILTER_STOP   # must not be Ignore, or hover inside the viewport dies
	if node is Control and not node is ScrollBar:
		node.mouse_default_cursor_shape = Control.CURSOR_MOVE
	for child in node.get_children():
		_apply_move_cursor(child)

func _input(event: InputEvent) -> void:
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
