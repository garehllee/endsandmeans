extends CanvasLayer
# F1 toggles this panel. It removes itself in exported (non-debug) builds.

const TOGGLES := [Flag.NOTEBOOK_EXPLOIT, Flag.INTERNET_EXPLOIT, Flag.ORANGE_UNLOCKED, Flag.HACKING_HF]

var _panel := PanelContainer.new()
var _score := Label.new()

func _ready() -> void:
	if not OS.is_debug_build():
		queue_free()
		return
	layer = 100
	_panel.visible = false
	var box := VBoxContainer.new()
	_panel.add_child(box)
	add_child(_panel)

	box.add_child(_score)
	for f in TOGGLES:
		var b := CheckButton.new()
		b.text = str(f)
		b.button_pressed = Game.has_flag(f)
		b.toggled.connect(func(on: bool): Game.set_flag(f, on))
		box.add_child(b)

	_add_button(box, "open analysis", func(): Game.open_world("analysis"))
	for ev in ["exploit_notebook", "exploit_internet", "exploit_copy_folder", "loyalty"]:
		_add_button(box, "folder: " + ev, func(): Story.trigger(ev))
	for id in _ending_ids():
		_add_button(box, "ending: " + id, func(): Story.end_with(id))
	_add_button(box, "save checkpoint", func(): Ethics.save_checkpoint())
	_add_button(box, "restart run", func(): Game.restart())
	_add_button(box, "reset save file", func(): Save.reset())

func _add_button(box: Control, text: String, callback: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(callback)
	box.add_child(b)

func _ending_ids() -> Array:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/endings.json"))
	if parsed is Dictionary:
		return parsed.get("endings", {}).keys()
	return []

func _process(_delta: float) -> void:
	if _panel.visible:
		_score.text = "acts: %d   score: %d   caught: %d   world: %s" % [
			Ethics.act_count(), Ethics.score(), Ethics.times_caught, Game.active_world]

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F1:
		_panel.visible = not _panel.visible
