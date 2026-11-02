extends DesktopWindow

const WINDOW_SIZE := Vector2(2000, 1916)   # 2000 x 1876 content + 40px title strip

@onready var room: AnalysisRoom = %AnalysisRoom

func _ready() -> void:
	custom_minimum_size = WINDOW_SIZE
	size = WINDOW_SIZE
	super()
	visible = false
	Game.analysis_requested.connect(_open)
	Game.analysis_closed.connect(_close)

func _open() -> void:
	size = WINDOW_SIZE
	global_position = _clamp_to_viewport((get_viewport_rect().size - size) * 0.5)
	visible = true
	modulate.a = 0.0
	bring_to_front()
	create_tween().tween_property(self, "modulate:a", 1.0, 0.3)
	room.open()
	Game.say_random("analysis_open")

func _close(_caught: bool) -> void:
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.3)
	await t.finished
	if not room.active:
		visible = false
