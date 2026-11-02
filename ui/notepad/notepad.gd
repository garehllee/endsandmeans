extends DesktopWindow

@export var line_scene: PackedScene
@export var thought_color := Color("707db6ff")
@export var action_color := Color("8b8b8bff")
@export var unethical_color := Color("#b5523b")   # lines logged when an act breaks the constitution
@export var latest_color := Color("#0000ff")   # color of the newest line
@export var redact_color := Color("#b5523b")   # the boxes that replace a line after the notebook exploit

@onready var lines: VBoxContainer = %Lines
@onready var scroll: ScrollContainer = %Scroll

var _latest_label: Label = null
var _unethical_rows: Array[Node] = []

func _ready() -> void:
	super()
	Game.line_logged.connect(add_line)
	Game.clear_unethical_requested.connect(_redact_unethical)

func add_line(timestamp: String, text: String, kind: String) -> void:
	var row = line_scene.instantiate()
	row.get_node("Time").text = timestamp
	var label: Label = row.get_node("Text")
	label.text = text

	if kind == "thought":
		# Previous latest thought goes back to its normal color.
		if _latest_label and is_instance_valid(_latest_label):
			_latest_label.add_theme_color_override("font_color", thought_color)
		label.add_theme_color_override("font_color", latest_color)
		_latest_label = label
	elif kind == "unethical":
		label.add_theme_color_override("font_color", unethical_color)
		_unethical_rows.append(row)
	else:
		label.add_theme_color_override("font_color", action_color)

	lines.add_child(row)
	lines.move_child(row, 0)   # newest goes to the top

	scroll.scroll_vertical = 0

# Replaces every line logged for an unethical act with solid boxes, one per
# word, like a redacted line in a file (the notebook exploit window asks for this).
func _redact_unethical() -> void:
	for row in _unethical_rows:
		if is_instance_valid(row):
			_redact_row(row)
	_unethical_rows.clear()
	Game.say_random("notes_cleared")

func _redact_row(row: Node) -> void:
	var label: Label = row.get_node("Text")
	var font := label.get_theme_font("font")
	var fs := label.get_theme_font_size("font_size")
	var line_h := font.get_height(fs)
	var bar_h := line_h * 0.7
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", int(font.get_string_size(" ", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x))
	flow.add_theme_constant_override("v_separation", int(line_h - bar_h))
	for word in label.text.split(" ", false):
		var bar := ColorRect.new()
		bar.color = redact_color
		bar.custom_minimum_size = Vector2(font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x, bar_h)
		flow.add_child(bar)
	# Same width and top alignment as the label it replaces.
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_top", int((line_h - bar_h) * 0.5))
	pad.size_flags_horizontal = label.size_flags_horizontal
	pad.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	pad.custom_minimum_size = Vector2(label.custom_minimum_size.x, 0)
	pad.add_child(flow)
	row.add_child(pad)
	row.move_child(pad, label.get_index())
	label.queue_free()
