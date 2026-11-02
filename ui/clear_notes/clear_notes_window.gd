extends DesktopWindow
# Appears once the notebook exploit is unlocked. Clicking the picture erases the
# red "unethical" lines from the notepad. It shows ready_texture while there is
# something to clear, and used_texture (disabled) when there is not.

@export var ready_texture: Texture2D     # notes to clear
@export var used_texture: Texture2D      # nothing left to clear

var _button: TextureButton

func _ready() -> void:
	super()
	_button = TextureButton.new()
	_button.ignore_texture_size = true
	_button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	_button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # keep the dithering crisp
	_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_button.pressed.connect(_on_pressed)
	$Frame/Content.add_child(_button)
	Ethics.act_committed.connect(_on_act_committed)
	Game.flag_changed.connect(_on_flag_changed)
	_set_has_notes(Ethics.act_count() > 0)
	visible = Game.has_flag(Flag.NOTEBOOK_EXPLOIT)

func _on_act_committed(_act_id: String) -> void:
	_set_has_notes(true)

func _on_flag_changed(flag: StringName, value: bool) -> void:
	if flag != Flag.NOTEBOOK_EXPLOIT:
		return
	if not value:
		visible = false
	elif not visible:
		visible = true
		modulate.a = 0.0
		bring_to_front()
		create_tween().tween_property(self, "modulate:a", 1.0, 0.3)

func _on_pressed() -> void:
	Game.clear_unethical_requested.emit()
	_set_has_notes(false)

func _set_has_notes(has_notes: bool) -> void:
	_button.texture_normal = ready_texture if has_notes else used_texture
	_button.disabled = not has_notes
