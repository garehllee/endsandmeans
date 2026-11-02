extends WorldWindow

@onready var room: AnalysisRoom = %AnalysisRoom

func _show(params: Dictionary) -> void:
	size = window_size
	global_position = _clamp_to_viewport((get_viewport_rect().size - size) * 0.5)
	super(params)
	room.open()
	Game.say_random("analysis_open")
