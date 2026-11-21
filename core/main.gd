extends Control

@onready var windows: Control = $Windows

func _ready() -> void:
	Game.open_window_requested.connect(open_window)
	var collapse := EndCollapse.new()
	windows.add_child(collapse)
	windows.move_child(collapse, 0)
	var now_playing := NowPlaying.new()
	add_child(now_playing)
	move_child(now_playing, 0)                # on the desktop, under the windows
	if not Game.started:
		add_child(preload("res://ui/landing/landing.gd").new())
	_add_bloom()

# A faint glow over everything, on the topmost layer.
func _add_bloom() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 128
	var copy := BackBufferCopy.new()
	copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	layer.add_child(copy)
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/bloom.gdshader")
	rect.material = mat
	layer.add_child(rect)
	add_child(layer)

func open_window(scene: PackedScene, pos: Vector2) -> Control:
	var w = scene.instantiate()
	windows.add_child(w)
	w.position = pos
	w.global_position = DesktopLayout.find_spot(w.size, w._clamp_to_viewport(w.global_position),
			DesktopLayout.occupied_rects(get_tree(), w), get_viewport_rect().size)
	return w
