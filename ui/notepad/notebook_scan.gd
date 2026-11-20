extends Node2D
class_name NotebookScan
# Every now and then something reads the notebook: an eye appears beside it,
# closed, opens, and a band of orange light sweeps down the page with the eye
# following it; then the eye closes and goes. (Purely something to see for
# now: the scan doesn't decide anything.)
#
# It lives on the notepad window, so it moves with it, and draws over the
# other windows.

const EYE_OPEN := preload("res://art/ui/eye/eye_open.png")
const EYE_CLOSED := preload("res://art/ui/eye/eye_closed.png")

@export var first_after := 25.0              # seconds into the game before the first scan
@export var every := Vector2(30.0, 60.0)     # seconds between scans
@export var line_height := 20.0
@export var line_color := Color(1.0, 0.63, 0.21, 0.6)   # orange at 60%
@export var eye_width := 220.0
@export var eye_gap := 24.0                  # between the window's edge and the eye
@export var fade_time := 0.3
@export var closed_hold := 0.4               # closed, before it opens
@export var open_hold := 0.35                # open, before it starts to read
@export var scan_time := 2.6                 # top of the page to the bottom
@export var end_hold := 0.3                  # at the bottom, before it closes
@export var shut_hold := 0.35                # closed again, before it goes

enum Step { WAIT, APPEAR, CLOSED, OPEN, SCAN, LINGER, SHUT, VANISH }

var _window: DesktopWindow
var _step := Step.WAIT
var _t := 0.0
var _wait := 0.0
var _alpha := 0.0
var _scan := 0.0            # 0 at the top of the page, 1 at the bottom
var _blink := 1.0           # the eye's height as it opens (squashed, then full)

func _ready() -> void:
	_window = get_parent() as DesktopWindow
	z_index = 20
	_wait = first_after

func _process(delta: float) -> void:
	if _step == Step.WAIT:
		if not Game.started or not _can_scan():
			return
		_wait -= delta
		if _wait <= 0.0:
			_go(Step.APPEAR)
		return
	if not _can_scan():
		_reset()
		return
	_t += delta
	match _step:
		Step.APPEAR:
			_alpha = clampf(_t / fade_time, 0.0, 1.0)
			if _t >= fade_time:
				_go(Step.CLOSED)
		Step.CLOSED:
			if _t >= closed_hold:
				_go(Step.OPEN)
				_blink = 0.35
		Step.OPEN:
			_blink = minf(1.0, 0.35 + _t / 0.15 * 0.65)
			if _t >= open_hold:
				_go(Step.SCAN)
		Step.SCAN:
			var k := clampf(_t / scan_time, 0.0, 1.0)
			_scan = k * k * (3.0 - 2.0 * k)
			if _t >= scan_time:
				_go(Step.LINGER)
		Step.LINGER:
			if _t >= end_hold:
				_go(Step.SHUT)
		Step.SHUT:
			if _t >= shut_hold:
				_go(Step.VANISH)
		Step.VANISH:
			_alpha = 1.0 - clampf(_t / fade_time, 0.0, 1.0)
			if _t >= fade_time:
				_reset()
	queue_redraw()

func _go(step: Step) -> void:
	_step = step
	_t = 0.0

func _reset() -> void:
	_step = Step.WAIT
	_t = 0.0
	_alpha = 0.0
	_scan = 0.0
	_blink = 1.0
	_wait = randf_range(every.x, every.y)
	queue_redraw()

# Only while the notebook is on screen and the game is being played.
func _can_scan() -> bool:
	return _window.visible and not _window.minimized and _window.modulate.a > 0.5 \
			and Game.active_world != "ending"

# The page: the window under its bar.
func _page() -> Rect2:
	var frame := _window.get_node("Frame") as Control
	return Rect2(frame.position, frame.size)

func _draw() -> void:
	if _step == Step.WAIT or _alpha <= 0.0:
		return
	var page := _page()
	var y := page.position.y + line_height * 0.5 + _scan * (page.size.y - line_height)
	if _step in [Step.SCAN, Step.LINGER]:
		draw_rect(Rect2(page.position.x, y - line_height * 0.5, page.size.x, line_height),
				Color(line_color, line_color.a * _alpha))
	# the eye: beside the window, on whichever side has room, level with the line
	var open := _step in [Step.OPEN, Step.SCAN, Step.LINGER]
	var tex := EYE_OPEN if open else EYE_CLOSED
	var size := Vector2(eye_width, eye_width * tex.get_height() / float(tex.get_width()))
	if open:
		size.y *= _blink
	var screen_w := get_viewport_rect().size.x
	var left_room := _window.global_position.x
	var right_room := screen_w - (_window.global_position.x + _window.size.x)
	var cx := -eye_gap - eye_width * 0.5
	if right_room > left_room:
		cx = _window.size.x + eye_gap + eye_width * 0.5
	draw_texture_rect(tex, Rect2(Vector2(cx, y) - size * 0.5, size), false, Color(1, 1, 1, _alpha))
