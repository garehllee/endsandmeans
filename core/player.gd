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

# Bug form: while a minigame runs the character is a bug. The pictures come
# from the two sheets (frames of 400x378, drawn so the standing bug lines up
# with the character's idle pose).
const BUG_TRANSFORM := preload("res://art/player/bug_transition.png")
const BUG_WALK := preload("res://art/player/bug_walk.png")
const BUG_FRAME := Vector2(400, 378)
const BUG_SCALE := 0.4232
const BUG_OFFSET := Vector2(3.6, 2.0)
const BUG_FPS := 12.0
var _bug: AnimatedSprite2D
var _bug_active := false     # the character is a bug
var _bug_busy := false       # turning into (or back from) a bug

func _ready():
	add_to_group("player")
	var anim: AnimatedSprite2D = $AnimatedSprite2D
	_sprite_base_y = anim.position.y
	anim.play("idle")
	anim.animation_looped.connect(_on_anim_looped)
	_build_bug()
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
	if _bug_busy:
		return   # mid-transformation
	if _bug_active:
		if movement == 1:
			if _bug.animation != "walk" or not _bug.is_playing():
				_bug.play("walk")
		elif _bug.is_playing():
			_bug.stop()
			_bug.frame = 0
		return
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
	if _gesture or _bug_active or _bug_busy:
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
	if _gesture or _bug_active or _bug_busy:
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

# ---------------------------------------------------------------- bug form
func _build_bug() -> void:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	_add_bug_animation(frames, "transform", BUG_TRANSFORM, 10, 5, false)
	_add_bug_animation(frames, "walk", BUG_WALK, 7, 4, true)
	_bug = AnimatedSprite2D.new()
	_bug.sprite_frames = frames
	_bug.position = BUG_OFFSET
	_bug.scale = Vector2.ONE * BUG_SCALE
	_bug.visible = false
	add_child(_bug)

func _add_bug_animation(frames: SpriteFrames, anim_name: String, sheet: Texture2D, count: int, cols: int, loops: bool) -> void:
	frames.add_animation(anim_name)
	frames.set_animation_speed(anim_name, BUG_FPS)
	frames.set_animation_loop(anim_name, loops)
	for i in count:
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2((i % cols) * BUG_FRAME.x, (i / cols) * BUG_FRAME.y, BUG_FRAME.x, BUG_FRAME.y)
		frames.add_frame(anim_name, atlas)

# The character turns into a bug (finishes when the transformation has played).
func become_bug() -> void:
	if _bug_active or _bug_busy:
		return
	_bug_busy = true
	_gesture = false
	_alt_playing = false
	var human: AnimatedSprite2D = $AnimatedSprite2D
	human.position.y = _sprite_base_y
	human.visible = false
	_bug.visible = true
	_bug.play("transform")
	await _bug.animation_finished
	if not _bug_busy:
		return      # reset while it was playing
	_bug_active = true
	_bug_busy = false
	_bug.animation = "walk"
	_bug.frame = 0
	_bug.stop()

# And back again: the same transformation, played in reverse.
func become_human() -> void:
	if not _bug_active or _bug_busy:
		return
	_bug_active = false
	_bug_busy = true
	_bug.play_backwards("transform")
	await _bug.animation_finished
	if not _bug_busy:
		return
	reset_form()

# Straight back to the character, no animation (when a challenge is abandoned).
func reset_form() -> void:
	_bug_active = false
	_bug_busy = false
	if _bug:
		_bug.stop()
		_bug.visible = false
	var human: AnimatedSprite2D = $AnimatedSprite2D
	human.visible = true
	human.play("idle")
	_schedule_alt()
