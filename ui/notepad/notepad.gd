extends DesktopWindow

@export var line_scene: PackedScene
@export var thought_color := Color("707db6ff")
@export var action_color := Color("8b8b8bff")
@export var unethical_color := Color("#b5523b")   # lines logged when an act breaks the constitution
@export var latest_color := Color("#0000ff")   # color of the newest line
@export var save_icon: Texture2D = preload("res://art/ui/save_icon.webp")   # beside "Saved progress"
@export var save_icon_height := 30.0

@onready var lines: VBoxContainer = %Lines
@onready var scroll: ScrollContainer = %Scroll

var _latest_label: Label = null

func _ready() -> void:
	super()
	add_to_group("notepad")          # Ethics saves and restores its lines with a checkpoint
	Game.line_logged.connect(add_line)
	Game.clear_unethical_requested.connect(_redact_unethical)
	add_child(NotebookScan.new())   # every now and then, something reads the notebook

func add_line(timestamp: String, text: String, kind: String) -> void:
	var row = line_scene.instantiate()
	row.set_meta("time", timestamp)
	row.set_meta("text", text)
	row.set_meta("kind", kind)
	# a thought about what the player is doing in an exploit, which erasing covers
	if kind == "thought" and (Game.telling or Game.active_world in ["exploit", "analysis"]):
		row.set_meta("telling", true)
	row.get_node("Time").text = timestamp
	var label: Label = row.get_node("Text")
	label.text = text

	if kind == "thought":
		# Previous latest thought goes back to its normal color.
		if _latest_label and is_instance_valid(_latest_label):
			_latest_label.add_theme_color_override("font_color", thought_color)
		label.add_theme_color_override("font_color", latest_color)
		_latest_label = label
	elif kind == "redacted":
		label.add_theme_color_override("font_color", action_color)
	elif kind == "save":
		label.add_theme_color_override("font_color", action_color)
		_add_icon(row, label, save_icon, save_icon_height)
	elif kind == "unethical":
		label.add_theme_color_override("font_color", unethical_color)
		row.set_meta("act_index", Ethics.ledger.size() - 1)   # the act this logs (just recorded)
	else:
		label.add_theme_color_override("font_color", action_color)

	lines.add_child(row)
	lines.move_child(row, 0)   # newest goes to the top

	scroll.scroll_vertical = 0

# Replaces every line logged for an unethical act with solid boxes, one per
# word, like a redacted line in a file (the notebook exploit window asks for this).
func _redact_unethical() -> void:
	var red := unethical_rows()
	for row in lines.get_children():
		if row.get_meta("telling", false) and row.get_meta("kind", "") == "thought" and not row.is_queued_for_deletion():
			red.append(row as Control)
	if not red.is_empty():
		Audio.play("redact")
	for row in red:
		_redact_row(row)
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
	# centred on the first line of text
	var holder := CenterContainer.new()
	holder.custom_minimum_size = Vector2(icon.custom_minimum_size.x,
			label.get_theme_font("font").get_height(label.get_theme_font_size("font_size")))
	holder.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	holder.add_child(icon)
	row.add_child(holder)
	row.move_child(holder, label.get_index())
	label.custom_minimum_size.x = maxf(0.0, label.custom_minimum_size.x - icon.custom_minimum_size.x - 8.0)
	(row as BoxContainer).add_theme_constant_override("separation", 8)

# The red lines still readable (not redacted): what the scan is looking for.
# Every line in the notepad is checked, so none can slip past.
func unethical_rows() -> Array[Control]:
	var out: Array[Control] = []
	for row in lines.get_children():
		if row.is_queued_for_deletion():
			continue
		if row.get_meta("kind", "") == "unethical":
			out.append(row as Control)
	return out

# ---------------------------------------------------------------- saving
# Every line, oldest first, for a checkpoint: what it said, when, what kind,
# and whether it has been redacted.
func save_lines() -> Array:
	var out := []
	var rows := lines.get_children()
	rows.reverse()                    # the newest is at the top
	for row in rows:
		if row.is_queued_for_deletion() or not row.has_meta("text"):
			continue
		out.append({"time": row.get_meta("time"), "text": row.get_meta("text"),
				"kind": row.get_meta("kind"), "act_index": row.get_meta("act_index", -1),
				"telling": row.get_meta("telling", false)})
	return out

# Going back to a checkpoint: the notepad becomes exactly what it was then.
func load_lines(saved: Array) -> void:
	for row in lines.get_children():
		lines.remove_child(row)
		row.queue_free()
	_latest_label = null
	for l in saved:
		add_line(l["time"], l["text"], l["kind"])
		var row := lines.get_child(0)
		if int(l["act_index"]) != -1:
			row.set_meta("act_index", l["act_index"])
		row.set_meta("telling", l.get("telling", false))

# A covered line stays readable, but only says something vague ("Dealt
# with."), in grey: the scan has nothing to find in it.
func _redact_row(row: Node) -> void:
	var text := Game.pick("notes_redacted")
	if text == "":
		text = "Dealt with."
	row.set_meta("text", text)
	row.set_meta("kind", "redacted")
	row.set_meta("telling", false)
	var label: Label = row.get_node("Text")
	label.text = text
	label.add_theme_color_override("font_color", action_color)
	if label == _latest_label:
		_latest_label = null
