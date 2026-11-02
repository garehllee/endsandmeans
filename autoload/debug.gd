extends CanvasLayer

const TOGGLES := [Flag.NOTEBOOK_EXPLOIT, Flag.INTERNET_EXPLOIT, Flag.ORANGE_UNLOCKED, Flag.HACKING_HF]

var _panel := PanelContainer.new()

func _ready() -> void:
	if not OS.is_debug_build():
		queue_free()
		return
	layer = 100
	_panel.visible = false
	var box := VBoxContainer.new()
	_panel.add_child(box)
	add_child(_panel)
	for f in TOGGLES:
		var b := CheckButton.new()
		b.text = str(f)
		b.button_pressed = Game.has_flag(f)
		b.toggled.connect(func(on: bool): Game.set_flag(f, on))
		box.add_child(b)
	var open := Button.new()
	open.text = "open analysis"
	open.pressed.connect(func(): Game.open_world("analysis"))
	box.add_child(open)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F1:
		_panel.visible = not _panel.visible
