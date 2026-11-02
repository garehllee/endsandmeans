extends Node2D

const INTRO := [
	[0.5, "Woah, what's going on..."],
	[1.5, "Okay. Maybe I should look around. I can use ← ↑ ↓ → to move."],
]
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	crossfade_top_sprite()
	# Await the next frame to guarantee the SubViewport completely constructs the children
	await get_tree().process_frame 
	
	if has_node("AnimatedSprite2D"):
		$AnimatedSprite2D.play("default")
	else:
		print("Still missing! Current children: ", get_children())
	
	for beat in INTRO:
		await get_tree().create_timer(beat[0]).timeout
		Game.say(beat[1])
	Game.intro_done = true
	Game.last_move_time = Game.elapsed


@onready var top_sprite: Sprite2D = $window_back_B

func crossfade_top_sprite() -> void:
	# 1. Start with the top sprite completely transparent
	top_sprite.modulate.a = 0.0
	
	# 2. Create a new Tween
	var tween = create_tween()
	
	# 3. Animate the alpha ('a') property of the modulate color to 1.0 over 1.5 seconds
	tween.tween_property(top_sprite, "modulate:a", 1.0, 1.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
