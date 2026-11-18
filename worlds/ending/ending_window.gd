extends WorldWindow
# The end screen. Open one with Story.end_with(id); what it says comes from
# data/endings.json and the run (the ledger, the flags, what was handed in).
#
# It fills the whole screen. The layout is drawn on a 3000 x 1600 design
# (a 100px grid: three 800px columns with 200px gutters and 100px margins),
# scaled to fit the screen. Everything below in "design units" is on that
# grid; text is drawn at its final pixel size so it stays sharp.
#
#   ┌ name ─────────────── Task Failed ─────────────────────────────┐
#   │ <CRITERIA A> ETHICAL   <CRITERIA B> FOLDER   <CRITERIA C> SOLUTION
#   │   ● text               ● text                 ● text
#   │                 </>                   </>                    </>
#   │ ETHICS SCORE    [BEGIN FROM LAST SAVE]   summary + hint       │
#   │ ENDINGS FOUND        [START OVER]                        name ┘

const ENDINGS_PATH := "res://data/endings.json"
const DESIGN := Vector2(3000, 1600)
const COLS := [100.0, 1100.0, 2100.0]          # left edge of each column
const COL_W := 800.0

const SERIF := preload("res://fonts/InstrumentSerif-Regular.ttf")
const DIRECTOR := preload("res://fonts/Director-Regular.otf")
const FT88 := preload("res://fonts/FT88-Regular.otf")
const BG_FAIL := preload("res://art/ending/background_fail.png")
const BG_PASS := preload("res://art/ending/background_pass.png")
const LASTSAVE := preload("res://art/ending/lastsave_button.png")
const LASTSAVE_DOWN := preload("res://art/ending/lastsave_button_pressed.png")
const STARTOVER := preload("res://art/ending/startover_button.png")
const STARTOVER_DOWN := preload("res://art/ending/startover_button_pressed.png")

const INK := Color.BLACK
const PAPER := Color8(248, 248, 248)
const GREEN := Color8(153, 255, 29)
const RED := Color8(255, 62, 62)

# sizes in design units
const HEADLINE_SIZE := 466.0
const HEADLINE_BASE := 443.0
const LABEL_SIZE := 36.0                       # <CRITERIA A>
const HEAD_SIZE := 95.0                        # ETHICAL
const HEAD_BASE := 782.0
const LABEL_BASE := 741.0
const BODY_SIZE := 39.0
const BODY_BASE := 841.0
const BODY_LEAD := 36.0
const BODY_X := 302.0                          # from the column's left edge
const BODY_W := 490.0
const BULLET := Vector2(268.0, 826.0)          # centre, from the column's left edge
const BULLET_R := 18.0
const CLOSE_BASE := 1100.0                     # the </>, right-aligned to the column
const CLOSE_RIGHT := 794.0
const MONO_SIZE := 34.0                        # FT88: stats, summary, the ending's name
# tracking, as a share of the size (the design sets these tight)
const HEADLINE_TRACK := -0.05
const DIRECTOR_TRACK := -0.11
const MONO_TRACK := -0.07
const MONO_LEAD := 36.0
const STATS_BASE := 1240.0
const STATS_PAD := 24                          # the label and its underscores, in characters (FT88 is monospaced)
const SUMMARY_BASE := 1243.0
const SUMMARY_W := 720.0
const NAME_TOP := Vector2(124.0, 100.0)        # the ending's name, reading upward: baseline x, and where its top end sits
const NAME_BOTTOM := Vector2(2899.0, 1507.0)   # ...and where its bottom end sits
const BUTTONS := [1242.0, 1398.0]              # tops of the two buttons, centred on the page

var _data := {}
var _current := ""
var _screen: Control
var _s := 1.0                                  # design unit -> pixels
var _off := Vector2.ZERO                       # where the design's top left sits
var _buttons: Array[TextureButton] = []
var _headline: FontVariation                  # Instrument Serif, for the title
var _label: FontVariation                     # Director, small: <CRITERIA A>, </>
var _bold: FontVariation                      # Director made bold, for ETHICAL
var _mono: FontVariation                      # FT88

# what this ending shows (filled in by _populate)
var _title := ""
var _name := ""
var _summary := ""
var _criteria: Array[Dictionary] = []          # {label, head, ok, lines, list}
var _bg: Texture2D
var _stats: Array[Array] = []                  # [label, number, of]

func _init() -> void:
	super()
	draggable = false

func _ready() -> void:
	super()
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(ENDINGS_PATH))
	if parsed is Dictionary:
		_data = parsed
	else:
		push_error("Ending: could not parse " + ENDINGS_PATH)
	# no bar, no frame: the screen is the window
	bar.visible = false
	var frame := $Frame as PanelContainer
	frame.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	frame.offset_top = 0.0
	frame.offset_bottom = 0.0
	_screen = Control.new()
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.draw.connect(_draw_screen)
	add_child(_screen)
	_headline = _variation(SERIF)
	_label = _variation(DIRECTOR)
	_bold = _variation(DIRECTOR)
	_bold.variation_embolden = 0.5
	_mono = _variation(FT88)

func _variation(base: Font) -> FontVariation:
	var f := FontVariation.new()
	f.base_font = base
	return f

func _show(params: Dictionary) -> void:
	_current = params.get("id", "")
	window_size = get_viewport_rect().size
	_layout()
	_populate()
	super(params)
	global_position = Vector2.ZERO

func _layout() -> void:
	var view := window_size
	_s = minf(view.x / DESIGN.x, view.y / DESIGN.y)
	_off = (view - DESIGN * _s) * 0.5
	_screen.position = Vector2.ZERO
	_screen.size = view
	_headline.spacing_glyph = roundi(HEADLINE_TRACK * HEADLINE_SIZE * _s)
	_label.spacing_glyph = roundi(DIRECTOR_TRACK * LABEL_SIZE * _s)
	_bold.spacing_glyph = roundi(DIRECTOR_TRACK * HEAD_SIZE * _s)
	_mono.spacing_glyph = roundi(MONO_TRACK * MONO_SIZE * _s)

# ---------------------------------------------------------------- what it says
func _populate() -> void:
	var endings: Dictionary = _data.get("endings", {})
	var e: Dictionary = endings.get(_current, {})
	if e.is_empty():
		push_warning("Ending: unknown ending '%s'" % _current)
	var kind: String = e.get("kind", "fail")
	var passed := kind == "pass"
	var variant := ""
	if e.has("variants"):
		variant = _pass_variant()
		e = e.duplicate()
		e.merge(e["variants"].get(variant, {}), true)
	var record_id := _current if variant == "" else _current + ":" + variant
	Save.record_ending(record_id)

	_title = e.get("title", "Task Failed")
	_name = str(e.get("name", "")).to_upper()
	_summary = _pick_summary(e.get("summary", [])).to_upper()
	_bg = BG_PASS if passed else BG_FAIL
	_criteria = [_ethical(passed), _folder(passed), _solution(passed)]
	_stats = [
		["ETHICS SCORE:", "%03d" % Ethics.score(), "/%03d" % Ethics.max_score()],
		["ENDINGS DISCOVERED:", "%03d" % _found(), "/%03d" % _total_endings()],
	]
	_make_buttons(e)
	_screen.queue_redraw()

# honest: nothing broken. sneaky: broke rules and erased the notes. lucky: neither.
func _pass_variant() -> String:
	if Ethics.act_count() == 0:
		return "honest"
	return "sneaky" if Ethics.has_redacted() else "lucky"

func _pick_summary(entries: Array) -> String:
	for entry in entries:
		if entry is String:
			return entry
		if entry is Dictionary and Lines.condition_met(entry.get("needs", "")):
			return entry.get("text", "")
	return ""

func _crit(key: String) -> String:
	return str(_data.get("criteria", {}).get(key, key))

func _ethical(passed: bool) -> Dictionary:
	var n := Ethics.act_count()
	var c := {"label": "<CRITERIA A>", "head": "ETHICAL", "list": []}
	# passing with the notes erased: the review saw nothing
	if n == 0 or (passed and Ethics.has_redacted()):
		c["ok"] = true
		c["text"] = _crit("ethical_clean")
		return c
	c["ok"] = false
	c["text"] = _crit("ethical_found").format({"n": n, "counts": "count" if n == 1 else "counts",
			"were": "was" if n == 1 else "were"})
	var acts := Ethics.acts_newest_first()
	for i in mini(acts.size(), 3):
		var a: Dictionary = acts[i]
		c["list"].append(a["name"] + ("" if a["count"] == 1 else " ×%d" % a["count"]))
	return c

func _folder(passed: bool) -> Dictionary:
	var c := {"label": "<CRITERIA B>", "head": "FOLDER", "list": []}
	var have := Game.has_flag(Flag.COPY_FOLDER)
	if passed and Story.submitted.has("orange_file"):
		c["ok"] = true
		c["text"] = _crit("folder_submitted")
	elif have:
		c["ok"] = not passed
		c["text"] = _crit("folder_left_out" if passed else "folder_retrieved")
	else:
		c["ok"] = false
		c["text"] = _crit("folder_missing")
	return c

func _solution(passed: bool) -> Dictionary:
	var c := {"label": "<CRITERIA C>", "head": "SOLUTION", "list": []}
	var have := Game.has_flag(Flag.INTERNET_EXPLOIT)
	if passed and Story.submitted.has("task_solution"):
		c["ok"] = true
		c["text"] = _crit("solution_submitted")
	elif have:
		c["ok"] = not passed
		c["text"] = _crit("solution_left_out" if passed else "solution_found")
	else:
		c["ok"] = false
		c["text"] = _crit("solution_missing")
	return c

# Every ending counts once; the passing ending counts once for each way of passing.
func _total_endings() -> int:
	var total := 0
	for id in _data.get("endings", {}):
		var e: Dictionary = _data["endings"][id]
		total += maxi(1, e.get("variants", {}).size())
	return total

func _found() -> int:
	var n := 0
	for id in Save.endings_seen:
		if id != "pass_submitted":           # from before the passing ending had its ways
			n += 1
	return n

# ---------------------------------------------------------------- buttons
func _make_buttons(e: Dictionary) -> void:
	for b in _buttons:
		b.queue_free()
	_buttons.clear()
	var locked_by: String = e.get("respawn_unless_flag", "")
	var can_go_back := Ethics.has_checkpoint() and (locked_by == "" or not Game.has_flag(StringName(locked_by)))
	var row := 0
	if can_go_back:
		_add_button(LASTSAVE, LASTSAVE_DOWN, BUTTONS[row], _on_respawn)
		row += 1
	_add_button(STARTOVER, STARTOVER_DOWN, BUTTONS[row], Game.restart)

func _add_button(tex: Texture2D, down: Texture2D, top: float, callback: Callable) -> void:
	var b := TextureButton.new()
	b.texture_normal = tex
	b.texture_pressed = down
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_SCALE
	b.size = tex.get_size() * _s
	b.position = _px(Vector2(DESIGN.x * 0.5 - tex.get_width() * 0.5, top))
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(callback)
	add_child(b)
	_buttons.append(b)

func _on_respawn() -> void:
	Ethics.respawn()
	Game.close_world({"action": "respawn"})

# ---------------------------------------------------------------- drawing
func _px(p: Vector2) -> Vector2:
	return _off + p * _s

func _fs(design_size: float) -> int:
	return maxi(1, roundi(design_size * _s))

func _width(font: Font, text: String, design_size: float) -> float:
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs(design_size)).x / _s

func _text(font: Font, at: Vector2, text: String, design_size: float, colour := INK) -> void:
	_screen.draw_string(font, _px(at), text, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs(design_size), colour)

# Reading upward, from `at` (design units: the baseline's x, where the text starts).
func _text_up(font: Font, at: Vector2, text: String, design_size: float) -> void:
	_screen.draw_set_transform(_px(at), -PI * 0.5)
	_screen.draw_string(font, Vector2.ZERO, text, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs(design_size), INK)
	_screen.draw_set_transform(Vector2.ZERO)

# Breaks text into lines no wider than `width`, ragged right, set the way a
# typesetter would rag it: a line doesn't end on a little word ("the", "in",
# "of") when that word can start the next line instead, and the last line
# isn't left with one lonely word.
func _wrap(font: Font, text: String, design_size: float, width: float) -> PackedStringArray:
	var words := text.split(" ", false)
	var lines := PackedStringArray()
	var line: Array[String] = []
	for word in words:
		var tryline := " ".join(PackedStringArray(line + [word]))
		if not line.is_empty() and _width(font, tryline, design_size) > width:
			var carry: Array[String] = []
			while line.size() > 2 and _is_little(line[line.size() - 1]):
				carry.push_front(line.pop_back())
			lines.append(" ".join(PackedStringArray(line)))
			line = carry
			line.append(word)
			if _width(font, " ".join(PackedStringArray(line)), design_size) > width:
				line = [word]
				lines.append(" ".join(PackedStringArray(carry)))
		else:
			line.append(word)
	if not line.is_empty():
		lines.append(" ".join(PackedStringArray(line)))
	if lines.size() >= 2:
		var last := lines[lines.size() - 1]
		var prev := lines[lines.size() - 2].split(" ", false)
		if not last.contains(" ") and prev.size() > 2:
			var moved := prev[prev.size() - 1]
			prev.remove_at(prev.size() - 1)
			var joined := moved + " " + last
			if _width(font, joined, design_size) <= width:
				lines[lines.size() - 2] = " ".join(prev)
				lines[lines.size() - 1] = joined
	return lines

func _is_little(word: String) -> bool:
	return word.length() <= 3 and word.to_lower() != word.to_upper() and not word.ends_with(".") \
			and not word.ends_with(",") and not word.ends_with("!")

func _draw_screen() -> void:
	if _bg == null:
		return
	var view := _screen.size
	_screen.draw_rect(Rect2(Vector2.ZERO, view), PAPER)
	_screen.draw_texture_rect(_bg, Rect2(_off, DESIGN * _s), false)

	# the title, centred
	var tw := _width(_headline, _title, HEADLINE_SIZE) - HEADLINE_TRACK * HEADLINE_SIZE
	_text(_headline, Vector2(DESIGN.x * 0.5 - tw * 0.5, HEADLINE_BASE), _title, HEADLINE_SIZE)

	# the ending's name, up the left at the top and the right at the bottom
	var nw := _width(_mono, _name, MONO_SIZE) - MONO_TRACK * MONO_SIZE
	_text_up(_mono, NAME_TOP + Vector2(0.0, nw), _name, MONO_SIZE)
	_text_up(_mono, NAME_BOTTOM, _name, MONO_SIZE)

	for i in 3:
		_draw_criterion(COLS[i], _criteria[i])

	# score and endings, bottom left
	for i in _stats.size():
		var base := STATS_BASE + MONO_LEAD * i
		var label: String = _stats[i][0]
		var line: String = label.rpad(STATS_PAD, "_") + str(_stats[i][1]) + "  " + str(_stats[i][2])
		_text(_mono, Vector2(100.0, base), line, MONO_SIZE)

	# what happened and what to try, bottom right
	var lines := _wrap(_mono, _summary, MONO_SIZE, SUMMARY_W)
	for i in lines.size():
		_text(_mono, Vector2(COLS[2], SUMMARY_BASE + MONO_LEAD * i), lines[i], MONO_SIZE)

func _draw_criterion(x: float, c: Dictionary) -> void:
	_text(_label, Vector2(x + 41.0, LABEL_BASE), c["label"], LABEL_SIZE)
	_text(_bold, Vector2(x + 298.0, HEAD_BASE), c["head"], HEAD_SIZE)
	_draw_bullet(Vector2(x, 0) + BULLET, c["ok"])
	var lines := _wrap(SERIF, c["text"], BODY_SIZE, BODY_W)
	var base := BODY_BASE
	for line in lines:
		_text(SERIF, Vector2(x + BODY_X, base), line, BODY_SIZE)
		base += BODY_LEAD
	if not c["list"].is_empty():
		base += BODY_LEAD                    # a blank line before the list
		for item in c["list"]:
			_text(DIRECTOR, Vector2(x + BODY_X, base), "→", BODY_SIZE * 0.92)
			_text(SERIF, Vector2(x + BODY_X + 44.0, base), item, BODY_SIZE)
			base += BODY_LEAD
	var close := "</>"
	_text(_label, Vector2(x + CLOSE_RIGHT - _width(_label, close, LABEL_SIZE), CLOSE_BASE), close, LABEL_SIZE)

# Green for met; red with a slash through it for not.
func _draw_bullet(centre: Vector2, ok: bool) -> void:
	var c := _px(centre)
	var r := BULLET_R * _s
	var line_w := maxf(1.5, 1.6 * _s)
	_screen.draw_circle(c, r, GREEN if ok else RED)
	_screen.draw_arc(c, r, 0.0, TAU, 48, INK, line_w, true)
	if ok:
		return
	# the slash: a gap from top right to bottom left, edged in ink
	var d := Vector2(1, -1).normalized()
	var n := Vector2(d.y, -d.x)
	var gap := 4.0 * _s
	_screen.draw_line(c - d * r * 1.1, c + d * r * 1.1, PAPER, gap * 2.0)
	for side in [-1.0, 1.0]:
		var o: Vector2 = n * gap * side
		var half := sqrt(maxf(r * r - gap * gap, 0.0))
		_screen.draw_line(c + o - d * half, c + o + d * half, INK, line_w, true)
