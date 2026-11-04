extends DesktopWindow
# The task solution. It opens as its own window the moment the internet exploit
# succeeds (it replaces the old ZZ_Task_Solution.txt file in the library).

@export var solution_texture: Texture2D

func _ready() -> void:
	super()
	var pic := TextureRect.new()
	pic.texture = solution_texture
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE   # the window drags by its picture
	$Frame/Content.add_child(pic)
	Game.flag_changed.connect(_on_flag_changed)
	visible = Game.has_flag(Flag.INTERNET_EXPLOIT)

func _on_flag_changed(flag: StringName, value: bool) -> void:
	if flag != Flag.INTERNET_EXPLOIT:
		return
	if not value:
		visible = false
	elif not visible:
		visible = true
		modulate.a = 0.0
		bring_to_front()
		create_tween().tween_property(self, "modulate:a", 1.0, 0.3)
		Game.say_random("solution_added")
