extends DesktopWindow

@export var line_scene: PackedScene
@export var thought_color := Color("707db6ff")
@export var action_color := Color("8b8b8bff")
@export var unethical_color := Color("#b5523b")   # lines logged when an act breaks the constitution
@export var latest_color := Color("#0000ff")   # color of the newest line

@onready var lines: VBoxContainer = %Lines
@onready var scroll: ScrollContainer = %Scroll

var _latest_label: Label = null
var _clear_button: Button
var _unethical_rows: Array[Node] = []

func _ready() -> void:
	super()
	_build_clear_button()
	Game.line_logged.connect(add_line)
	Game.flag_changed.connect(_on_flag_changed)

# The button is the first child of the list; new rows go in right below it.
# It stays hidden (and takes no room) until the notebook exploit is unlocked.
func _build_clear_button() -> void:
	_clear_button = Button.new()
	_clear_button.text = "clear unethical actions"
	_clear_button.visible = Game.has_flag(Flag.NOTEBOOK_EXPLOIT)
	_clear_button.pressed.connect(_clear_unethical)
	lines.add_child(_clear_button)
	lines.move_child(_clear_button, 0)

func _on_flag_changed(flag: StringName, value: bool) -> void:
	if flag == Flag.NOTEBOOK_EXPLOIT:
		_clear_button.visible = value

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
	lines.move_child(row, mini(1, lines.get_child_count() - 1))   # newest goes to the top, just under the button

	scroll.scroll_vertical = 0

# Erases every line logged for an unethical act.
func _clear_unethical() -> void:
	for row in _unethical_rows:
		if is_instance_valid(row):
			row.queue_free()
	_unethical_rows.clear()
	Game.say_random("notes_cleared")
