extends CharacterBody2D


const SPEED = 500.0
var current_dir = "none"
var last_logged_dir := "none"
var last_walk_log := -999.0

func _ready():
	add_to_group("player")
	$AnimatedSprite2D.play("idle")
	
@export var world_id := "sandbox"   # set to "library" on the file room's Player

func _physics_process(delta):
	if Game.active_world != world_id:
		velocity = Vector2.ZERO
		play_anim(0)
		return
	Game.active_player = self
	if Game.input_locked:
		return   # a cutscene is moving the character
	player_movement(delta)

func player_movement(_delta):
	if Input.is_action_pressed("ui_right"):
		current_dir = "right"
		velocity.x = SPEED
		velocity.y = 0
		play_anim(1)
	elif Input.is_action_pressed("ui_left"):
		current_dir = "left"
		velocity.x = -SPEED
		velocity.y = 0
		play_anim(1)
	elif Input.is_action_pressed("ui_down"):
		current_dir = "down"
		velocity.x = 0
		velocity.y = SPEED
		play_anim(1)
	elif Input.is_action_pressed("ui_up"):
		current_dir = "up"
		velocity.x = 0
		velocity.y = -SPEED
		play_anim(1)
	else:
		velocity.x = 0
		velocity.y = 0
		play_anim(0)
	
	_track_movement(velocity != Vector2.ZERO)
	move_and_slide()

const WALK_LOG_COOLDOWN := 0.1

func _track_movement(moving: bool) -> void:
	Game.is_moving = moving
	var dir: String = current_dir if moving else "none"
	if dir == last_logged_dir:
		return
	last_logged_dir = dir
	Game.last_move_time = Game.elapsed
	Game.idle_logged = false
	if dir == "none":
		return
	if Game.elapsed - last_walk_log < WALK_LOG_COOLDOWN:
		return
	last_walk_log = Game.elapsed
	Game.say_random("walk_" + dir, {}, "action")

func play_anim(movement):
	var dir = current_dir
	var anim = $AnimatedSprite2D
	if movement == 1:
		if dir == "right":
			anim.play("walk-right")
		if dir == "left":
			anim.play("walk-left")
		if dir == "up" or dir == "down":
			anim.play("walk-up-down")
	elif movement == 0:
		anim.play("idle")
