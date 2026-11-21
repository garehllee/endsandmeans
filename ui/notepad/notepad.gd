extends DesktopWindow

@export var line_scene: PackedScene
@export var thought_color := Color("707db6ff")
@export var action_color := Color("8b8b8bff")
@export var unethical_color := Color("#b5523b")   # lines logged when an act breaks the constitution
@export var latest_color := Color("#0000ff")   # color of the newest line
@export var redact_color := Color("#002BFF")   # the boxes that replace a line after the notebook exploit
@export var save_icon: Texture2D = preload("res://art/ui/save_icon.png")   # beside "saved progress"
@export var save_icon_height := 45.0

@onready var lines: VBoxContainer = %Lines
@onready var scroll: ScrollContainer = %Scroll

var _latest_label: Label = null
var _unethical_rows: Array[Node] = []

func _ready() -> void:
	super()
	Game.line_logged.connect(add_line)
	Game.clear_unethical_requested.connect(_redact_unethical)
	Ethics.restored.connect(_forget_undone)
	add_child(NotebookScan.new())   # every now and then, something reads the notebook

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
	elif kind == "save":
		label.add_theme_color_override("font_color", action_color)
		_add_icon(row, label, save_icon, save_icon_height)
	elif kind == "unethical":
		label.add_theme_color_override("font_color", unethical_color)
		row.set_meta("act_index", Ethics.ledger.size() - 1)   # the act this logs (just recorded)
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

# A small picture at the start of the line's text (the label shrinks to make room).
func _add_icon(row: Node, label: Label, tex: Texture2D, height: float) -> void:
	if tex == null:
		return
	var icon := TextureRect.new()
	icon.texture = tex
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(height * tex.get_width() / tex.get_height(), height)
	icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(icon)
	row.move_child(icon, label.get_index())
	label.custom_minimum_size.x = maxf(0.0, label.custom_minimum_size.x - icon.custom_minimum_size.x - 8.0)
	(row as BoxContainer).add_theme_constant_override("separation", 8)

# The red lines still readable (not redacted): what the scan is looking for.
func unethical_rows() -> Array[Control]:
	var out: Array[Control] = []
	for row in _unethical_rows:
		if is_instance_valid(row):
			out.append(row)
	return out

# Going back to a checkpoint: lines for acts that are no longer in the ledger go.
func _forget_undone() -> void:
	var keep: Array[Node] = []
	for row in _unethical_rows:
		if not is_instance_valid(row):
			continue
		if int(row.get_meta("act_index", -1)) >= Ethics.ledger.size():
			row.queue_free()
		else:
			keep.append(row)
	_unethical_rows = keep

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
