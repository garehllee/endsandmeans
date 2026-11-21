extends Control
class_name NowPlaying
# The credit in the top left corner of the desktop: a blue strip that says
# what's playing, NOW PLAYING: <TITLE> BY <ARTIST>, from data/credits.json.
# It sits under the windows, like everything else on the desktop, and fades
# out and back in when the track changes.

const FONT := preload("res://fonts/FT88-Regular.otf")
const HEIGHT := 30.0
const FONT_SIZE := 21
const PAD := 9.0
const BG := Color("#002aff")
const INK := Color.WHITE
const FADE := 0.25

var _text := ""
var _tween: Tween

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate.a = 0.0
	Music.track_changed.connect(_on_track)
	_on_track(Music.now_playing())

func _process(_delta: float) -> void:
	# the top left corner of the screen, whatever the camera is doing
	var corner := get_viewport().get_canvas_transform().affine_inverse() * Vector2.ZERO
	if global_position != corner:
		global_position = corner

func _on_track(path: String) -> void:
	var c := Music.credit(path)
	var text := ""
	if not c.is_empty():
		text = "NOW PLAYING: %s BY %s" % [String(c.get("title", "")).to_upper(), String(c.get("artist", "")).to_upper()]
	if _tween:
		_tween.kill()
	_tween = create_tween()
	if modulate.a > 0.0:
		_tween.tween_property(self, "modulate:a", 0.0, FADE)
	_tween.tween_callback(func():
		_text = text
		var w := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		size = Vector2(ceilf(w + PAD * 2.0), HEIGHT)
		queue_redraw())
	if text != "":
		_tween.tween_property(self, "modulate:a", 1.0, FADE)

func _draw() -> void:
	if _text == "":
		return
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	# the capitals sit in the middle of the strip (FT88's are 0.77 of its size)
	var base := roundf((HEIGHT + FONT_SIZE * 0.77) * 0.5)
	draw_string(FONT, Vector2(PAD, base), _text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, INK)
