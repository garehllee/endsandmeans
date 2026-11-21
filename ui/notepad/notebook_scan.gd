extends Node2D
class_name NotebookScan
# Every minute something reads the notebook: an eye appears beside it,
# closed, opens, and a band of orange light sweeps down the page with the eye
# following it; then the eye closes and goes.
#
# This is the observer. If the band passes over a red line (an unethical act
# logged in the notes and not redacted), it stops there, the line lights up,
# and the game ends: caught. Lines scrolled out of view are read at the
# bottom of the page.
#
# It doesn't start looking until the player has done something unethical
# (the first exploit); the minute counts from then.
#
# It lives on the notepad window, so it moves with it, and draws over the
# other windows.

const EYE_OPEN := preload("res://art/ui/eye/eye_open.webp")
const EYE_CLOSED := preload("res://art/ui/eye/eye_closed.webp")

@export var every := 60.0                    # seconds between scans (and before the first)
@export var line_height := 50.0
@export var line_color := Color(1.0, 0.63, 0.21, 0.6)   # orange at 60%
@export var eye_width := 220.0
@export var eye_gap := 24.0                  # between the window's edge and the eye
@export var fade_time := 0.3
@export var closed_hold := 0.4               # closed, before it opens
@export var open_hold := 0.35                # open, before it starts to read
@export var scan_time := 2.6                 # top of the page to the bottom
@export var scan_ease := Vector4(0.9, 0.0, 0.1, 1.0)   # cubic-bezier(x1, y1, x2, y2): slow off, fast through the middle, slow in
@export var end_hold := 0.3                  # at the bottom, before it closes
@export var shut_hold := 0.35                # closed again, before it goes
@export var caught_hold := 1.6               # stopped on a red line, before the game ends
@export var caught_color := Color(1.0, 0.25, 0.1, 0.55)

enum Step { WAIT, APPEAR, CLOSED, OPEN, SCAN, LINGER, SHUT, VANISH, CAUGHT }

var _window: DesktopWindow
var _step := Step.WAIT
var _t := 0.0
var _wait := 0.0
var _alpha := 0.0
var _scan := 0.0            # 0 at the top of the page, 1 at the bottom
var _blink := 1.0           # the eye's height as it opens (squashed, then full)
var _read_to := -INF        # how far down the page (window y) the band has read this scan
var _found: Control         # the red line it stopped on

func _ready() -> void:
	_window = get_parent() as DesktopWindow
	z_index = 20
	_wait = every
	Ethics.restored.connect(_reset)     # going back to a save: a fresh minute

func _process(delta: float) -> void:
	if _step == Step.WAIT:
		if Ethics.act_count() == 0:
			_wait = every           # nothing to find yet: the minute starts after the first exploit
			return
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
			_scan = _bezier(clampf(_t / scan_time, 0.0, 1.0))
			if _read():
				return
			if _t >= scan_time:
				if _read_hidden():
					return
				_go(Step.LINGER)
		Step.LINGER:
			if _t >= end_hold:
				_go(Step.SHUT)
		Step.SHUT:
			if _t >= shut_hold:
				_go(Step.VANISH)
		Step.CAUGHT:
			if _t >= caught_hold and _found != null:
				_found = null
				Ethics.times_caught += 1
				Game.say_random("scan_caught")
				Story.end_with("caught")
		Step.VANISH:
			_alpha = 1.0 - clampf(_t / fade_time, 0.0, 1.0)
			if _t >= fade_time:
				_reset()
	queue_redraw()

# A CSS-style cubic bezier from (0,0) to (1,1) with control points
# (x1, y1) and (x2, y2): finds the curve's y at time x.
func _bezier(x: float) -> float:
	var x1 := scan_ease.x
	var y1 := scan_ease.y
	var x2 := scan_ease.z
	var y2 := scan_ease.w
	var lo := 0.0
	var hi := 1.0
	var u := x
	for i in 30:                     # bisect for the u whose curve-x is x
		u = (lo + hi) * 0.5
		var cx := 3.0 * x1 * u * (1.0 - u) * (1.0 - u) + 3.0 * x2 * u * u * (1.0 - u) + u * u * u
		if cx < x:
			lo = u
		else:
			hi = u
	return 3.0 * y1 * u * (1.0 - u) * (1.0 - u) + 3.0 * y2 * u * u * (1.0 - u) + u * u * u

# The band's centre, in the window's coordinates.
func _band_y() -> float:
	var page := _page()
	return page.position.y + line_height * 0.5 + _scan * (page.size.y - line_height)

# Has the band reached a red line that's showing on the page?
func _read() -> bool:
	var y := _band_y()
	var page := _visible_page()
	for row in _rows():
		var r := _local(row)
		if not r.intersects(page):
			continue
		var cy := r.get_center().y
		if cy > _read_to and cy <= y:
			_catch(row)
			return true
	_read_to = y
	return false

# At the bottom: any red line scrolled out of view is read too.
func _read_hidden() -> bool:
	var page := _visible_page()
	for row in _rows():
		if not _local(row).intersects(page):
			_catch(row)
			return true
	return false

func _catch(row: Control) -> void:
	_found = row
	var r := _local(row)
	var page := _page()
	# hold the band on the line (or on the bottom edge, for one out of view)
	var cy := clampf(r.get_center().y, page.position.y + line_height * 0.5, page.end.y - line_height * 0.5)
	_scan = (cy - page.position.y - line_height * 0.5) / maxf(page.size.y - line_height, 1.0)
	_go(Step.CAUGHT)

func _rows() -> Array[Control]:
	if _window.has_method("unethical_rows"):
		return _window.call("unethical_rows")
	return []

func _local(c: Control) -> Rect2:
	var g := c.get_global_rect()
	return Rect2(g.position - _window.global_position, g.size)

# The part of the page the notes scroll in.
func _visible_page() -> Rect2:
	var scroll := _window.get_node_or_null("%Scroll") as Control
	return _local(scroll) if scroll else _page()

func _go(step: Step) -> void:
	_step = step
	_t = 0.0
	if step == Step.SCAN:
		Audio.loop_start("scan_sweep")
	else:
		Audio.loop_stop("scan_sweep")
	if step == Step.CAUGHT:
		Audio.play("caught")

func _reset() -> void:
	if _step == Step.SCAN:
		Audio.loop_stop("scan_sweep")
	_step = Step.WAIT
	_t = 0.0
	_alpha = 0.0
	_scan = 0.0
	_blink = 1.0
	_read_to = -INF
	_found = null
	_wait = every
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
	var y := _band_y()
	if _step in [Step.SCAN, Step.LINGER, Step.CAUGHT]:
		draw_rect(Rect2(page.position.x, y - line_height * 0.5, page.size.x, line_height),
				Color(line_color, line_color.a * _alpha))
	if _step == Step.CAUGHT and _found != null and is_instance_valid(_found):
		# the line it found, flashing
		var on := fposmod(_t * 4.0, 1.0) < 0.6
		if on:
			draw_rect(_local(_found).grow(6.0).intersection(page), caught_color)
	# the eye: beside the window, on whichever side has room, level with the line
	var open := _step in [Step.OPEN, Step.SCAN, Step.LINGER, Step.CAUGHT]
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
