extends CanvasLayer
# The landing screen on boot: the whole screen grey with the logo, and
# sandbox.exe drifting around like a DVD logo, turning slowly as it goes.
# Clicking it fades the landing away and starts the game (the notepad's
# first lines, moving with the arrows). Main only adds it once per launch;
# restarting a run doesn't bring it back.

const BG := Color("e7e7e7")
const LOGO := preload("res://art/landing/logo.png")
const ICON := preload("res://art/landing/sandbox_icon.png")
const LOGO_HEIGHT := 0.86      # of the screen's height
const ICON_SIZE := 560.0       # drawn width of the icon picture, pixels
const DISC := 128.0 / 317.0    # the disc's radius as a share of the picture (the rest is glow)
const SPEED := 230.0           # pixels a second
const SPIN := 0.25             # radians a second
const FADE := 0.7

var _canvas: Control
var _pos := Vector2.ZERO
var _vel := Vector2.ZERO
var _rot := 0.0
var _hover := 0.0
var _leaving := false

func _ready() -> void:
	layer = 110
	Game.input_locked = true
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP   # nothing under the landing can be clicked
	_canvas.draw.connect(_draw_landing)
	_canvas.gui_input.connect(_on_input)
	add_child(_canvas)
	var size := _screen()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_pos = size * Vector2(rng.randf_range(0.25, 0.75), rng.randf_range(0.25, 0.75))
	_vel = Vector2(1.0 if rng.randf() < 0.5 else -1.0, 1.0 if rng.randf() < 0.5 else -1.0).normalized() * SPEED
	_rot = rng.randf_range(0.0, TAU)

func _screen() -> Vector2:
	return _canvas.get_viewport_rect().size

func _radius() -> float:
	return ICON_SIZE * DISC

func _process(delta: float) -> void:
	var size := _screen()
	var r := _radius()
	if not _leaving:
		_pos += _vel * delta
		# bounce off the edges of the screen, the disc's edge touching them
		if _pos.x < r or _pos.x > size.x - r:
			_vel.x = absf(_vel.x) * (1.0 if _pos.x < r else -1.0)
		if _pos.y < r or _pos.y > size.y - r:
			_vel.y = absf(_vel.y) * (1.0 if _pos.y < r else -1.0)
		_pos = _pos.clamp(Vector2(r, r), size - Vector2(r, r))
		_rot += SPIN * delta
	var over := _over(_canvas.get_local_mouse_position())
	_hover = move_toward(_hover, 1.0 if over and not _leaving else 0.0, delta / 0.12)
	_canvas.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if over else Control.CURSOR_ARROW
	_canvas.queue_redraw()

func _over(p: Vector2) -> bool:
	return p.distance_to(_pos) <= _radius()

func _on_input(event: InputEvent) -> void:
	if _leaving:
		return
	var pressed := false
	var at := Vector2.ZERO
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		pressed = mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
		at = mb.position
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		pressed = st.pressed
		at = st.position
	if pressed and _over(at):
		_leave()

func _leave() -> void:
	_leaving = true
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := create_tween()
	tw.tween_property(_canvas, "modulate:a", 0.0, FADE).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func():
		Game.input_locked = false
		Game.start_game()
		queue_free())

func _draw_landing() -> void:
	var size := _screen()
	_canvas.draw_rect(Rect2(Vector2.ZERO, size), BG)
	var lh := size.y * LOGO_HEIGHT
	var lw := lh * LOGO.get_width() / float(LOGO.get_height())
	_canvas.draw_texture_rect(LOGO, Rect2((size - Vector2(lw, lh)) * 0.5, Vector2(lw, lh)), false)
	var s := ICON_SIZE * (1.0 + 0.06 * _hover)
	var h := s * ICON.get_height() / float(ICON.get_width())
	_canvas.draw_set_transform(_pos, _rot, Vector2.ONE)
	_canvas.draw_texture_rect(ICON, Rect2(-s * 0.5, -h * 0.5, s, h), false)
	_canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
