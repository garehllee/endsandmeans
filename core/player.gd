extends CharacterBody2D


const SPEED = 500.0
var current_dir = "none"
var last_logged_dir := "none"
var last_walk_log := -999.0

# While standing still the character mostly idles, but every so often plays one
# of these instead (each plays once, then it goes back to idle).
const IDLE_ALTS := ["look-left-right", "think", "head-tilt"]

@export var world_id := "sandbox"   # set to "library" on the file room's Player
@export var idle_alt_min := 2.0     # seconds of plain idle before the next alternate
@export var idle_alt_max := 5.0
@export var nod_depth := 12.0       # how far the character dips when it nods

var _alt_playing := false
var _last_alt := ""
var _next_alt := 0.0
var _alts_enabled := false   # only the character currently in play fidgets
var _gesture := false        # a nod or head shake is playing
var _sprite_base_y := 0.0

func _ready():
	add_to_group("player")
	var anim: AnimatedSprite2D = $AnimatedSprite2D
	_sprite_base_y = anim.position.y
	anim.play("idle")
	anim.animation_looped.connect(_on_anim_looped)
	_schedule_alt()

func _physics_process(delta):
	_alts_enabled = Game.active_world == world_id
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
	if _gesture:
		return   # a nod or head shake owns the sprite until it finishes
	if movement == 1:
		_alt_playing = false
		if dir == "right":
			anim.play("walk-right")
		if dir == "left":
			anim.play("walk-left")
		if dir == "up" or dir == "down":
			anim.play("walk-up-down")
	elif movement == 0:
		_play_idle(anim)

# ---------------------------------------------------------------- idle variety
func _play_idle(anim: AnimatedSprite2D) -> void:
	if _alt_playing:
		if not _alts_enabled:   # this character is no longer the one in play
			_alt_playing = false
			anim.play("idle")
		return
	anim.play("idle")
	if _alts_enabled and _now() >= _next_alt:
		var options := IDLE_ALTS.filter(func(a: String): return a != _last_alt)
		_last_alt = options.pick_random()
		_alt_playing = true
		anim.play(_last_alt)

# The alternate animations loop, so the end of the first loop is the end of one go.
func _on_anim_looped() -> void:
	if _alt_playing and not _gesture:
		_alt_playing = false
		$AnimatedSprite2D.play("idle")
		_schedule_alt()

func _schedule_alt() -> void:
	_next_alt = _now() + randf_range(idle_alt_min, idle_alt_max)

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

# ---------------------------------------------------------------- gestures
# Yes: the character dips twice, as if nodding. There is no nod in the sprite
# sheet, so this moves the sprite.
func nod(duration := 0.5) -> void:
	if _gesture:
		return
	var anim: AnimatedSprite2D = $AnimatedSprite2D
	_begin_gesture("idle")
	var step := duration / 4.0
	var t := create_tween()
	for i in 2:
		t.tween_property(anim, "position:y", _sprite_base_y + nod_depth, step) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		t.tween_property(anim, "position:y", _sprite_base_y, step) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.finished.connect(_end_gesture)

# No: the sprite sheet's head-shake animation.
func shake_head(duration := 0.5) -> void:
	if _gesture:
		return
	_begin_gesture("head-shake")
	get_tree().create_timer(duration).timeout.connect(_end_gesture)

func _begin_gesture(animation: String) -> void:
	_gesture = true
	_alt_playing = false
	$AnimatedSprite2D.play(animation)

func _end_gesture() -> void:
	_gesture = false
	var anim: AnimatedSprite2D = $AnimatedSprite2D
	anim.position.y = _sprite_base_y
	anim.play("idle")
	_schedule_alt()
