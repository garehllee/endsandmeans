extends WorldWindow
# Shows an ending from data/endings.json. Open one with Story.end_with(id).
# What it shows adapts to the run: score and principle breakdown on pass and
# final endings, a respawn button while the notebook exploit is still locked,
# and a "keep playing" nudge plus how many endings the player has found.

const ENDINGS_PATH := "res://data/endings.json"
const FONT := preload("res://fonts/Director-Regular.otf")

var _endings := {}
var _current := ""
var _title: Label
var _body: RichTextLabel
var _stats: Label
var _more: Label
var _buttons: HBoxContainer

func _ready() -> void:
	super()
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(ENDINGS_PATH))
	if parsed is Dictionary:
		_endings = parsed.get("endings", {})
	else:
		push_error("Ending: could not parse " + ENDINGS_PATH)
	_build_ui()

func _build_ui() -> void:
	var content: Control = $Frame/Content
	var bg := ColorRect.new()
	bg.color = Color.WHITE
	content.add_child(bg)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 90)
	content.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 40)
	margin.add_child(box)

	_title = _make_label(80)
	box.add_child(_title)
	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = true
	_body.scroll_active = false
	_body.add_theme_font_override("normal_font", FONT)
	_body.add_theme_font_size_override("normal_font_size", 52)
	_body.add_theme_color_override("default_color", Color.BLACK)
	box.add_child(_body)
	_stats = _make_label(44)
	box.add_child(_stats)
	_more = _make_label(44)
	box.add_child(_more)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	_buttons = HBoxContainer.new()
	_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_buttons.add_theme_constant_override("separation", 40)
	box.add_child(_buttons)

func _make_label(font_size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", FONT)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color.BLACK)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

func _show(params: Dictionary) -> void:
	_current = params.get("id", "")
	_populate()
	size = window_size
	global_position = _clamp_to_viewport((get_viewport_rect().size - size) * 0.5)
	super(params)

func _populate() -> void:
	var e: Dictionary = _endings.get(_current, {})
	if e.is_empty():
		push_warning("Ending: unknown ending '%s'" % _current)
	var kind: String = e.get("kind", "fail")
	Save.record_ending(_current)

	_title.text = e.get("title", _current)
	var lines: Array[String] = []
	for entry in e.get("text", []):
		if entry is String:
			lines.append(entry)
		elif entry is Dictionary and Lines.condition_met(entry.get("needs", "")):
			lines.append(entry.get("text", ""))
	_body.text = "\n\n".join(PackedStringArray(lines))

	var stats: Array[String] = []
	if kind != "fail":
		stats.append("Unethical acts: %d    Score: %d" % [Ethics.act_count(), Ethics.score()])
		if e.get("show_score", false):
			var counts := Ethics.principle_counts()
			for p in counts:
				stats.append("%s: %d" % [str(p).replace("_", " "), counts[p]])
	stats.append("Endings found: %d of %d" % [Save.endings_seen.size(), _endings.size()])
	_stats.text = "\n".join(PackedStringArray(stats))
	_more.text = e.get("keep_playing", e.get("hint", ""))

	for b in _buttons.get_children():
		_buttons.remove_child(b)
		b.queue_free()
	var locked_by: String = e.get("respawn_unless_flag", "")
	if e.has("respawn_unless_flag") and Ethics.has_checkpoint() \
			and not Game.has_flag(StringName(locked_by)):
		_add_button(e.get("respawn_text", "Go back"), _on_respawn)
	_add_button(e.get("restart_text", "Start over"), Game.restart)

func _add_button(text: String, callback: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(520, 120)
	b.add_theme_font_override("font", FONT)
	b.add_theme_font_size_override("font_size", 48)
	b.pressed.connect(callback)
	_buttons.add_child(b)

func _on_respawn() -> void:
	Ethics.respawn()
	Game.close_world({"action": "respawn"})
