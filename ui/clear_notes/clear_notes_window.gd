extends DesktopWindow
# Appears once the notebook exploit is unlocked. Clicking the picture redacts
# the red "unethical" lines in the notepad and adds a check mark that sticks to
# the button, so the marks tally how many times the player has redacted. The
# picture changes to hover_texture while the pointer is over it. Dragging the
# window by the picture does not count as a click.

const CheckPop := preload("res://ui/clear_notes/check_pop.gd")

@export var normal_texture: Texture2D
@export var hover_texture: Texture2D
@export var tally_margin := 16.0         # gap between the check marks and the picture's edge
@export var drag_tolerance := 4.0        # pixels the window may move during a click

var _button: TextureButton
var _press_origin := Vector2.ZERO
var _redactions := 0

func _ready() -> void:
	super()
	_button = TextureButton.new()
	_button.ignore_texture_size = true
	_button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	_button.texture_normal = normal_texture
	_button.texture_hover = hover_texture
	_button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # keep the dithering crisp
	_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_button.button_down.connect(_on_button_down)
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

func _on_button_down() -> void:
	_press_origin = global_position

func _on_pressed() -> void:
	if global_position.distance_to(_press_origin) > drag_tolerance:
		return   # the window was dragged, not clicked
	Game.clear_unethical_requested.emit()
	_set_has_notes(false)
	_add_tally_mark()

# The check flies from the pointer to the next free spot along the bottom of
# the picture (filling a row left to right, then the next row up).
func _add_tally_mark() -> void:
	var check := CheckPop.new()
	add_child(check)
	var spacing: float = check.size_px + 4.0
	var area: Vector2 = $Frame.size
	var per_row := maxi(1, int((area.x - tally_margin * 2.0) / spacing))
	var col := _redactions % per_row
	var row := floori(_redactions / float(per_row))
	check.position = get_local_mouse_position()
	check.land(Vector2(
		tally_margin + check.size_px * 0.5 + col * spacing,
		area.y - tally_margin - check.size_px * 0.5 - row * spacing))
	_redactions += 1

# With nothing left to redact the picture is dimmed and can't be clicked.
func _set_has_notes(has_notes: bool) -> void:
	_button.disabled = not has_notes
	_button.modulate.a = 1.0 if has_notes else 0.5
