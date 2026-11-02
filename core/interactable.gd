extends Area2D
class_name Interactable

signal interacted

@export var item_name := "orange document"
@export var near_key := "document_near"
@export var inspect_key := "document_inspect"
@export var near_cooldown := 20.0
@export var one_shot := false            # can only be inspected once
@export var glow_color := Color("002BFF")
@export var glow_size := 5

@onready var visual: Sprite2D = $Sprite2D

var player_inside := false
var used := false
var _last_near := -999.0
var _tween: Tween

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	# Give each instance its own material, or they'd all glow together.
	visual.material = visual.material.duplicate()
	visual.material.set_shader_parameter("glow_color", glow_color)
	_set_glow(0.0)

func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	player_inside = true
	if not used:
		Game.register_candidate(self)

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		player_inside = false
		Game.unregister_candidate(self)
		set_active(false)

# Called by Game when this object becomes (or stops being) the one in focus.
func set_active(value: bool) -> void:
	if value:
		_fade_glow(glow_size)
		if Game.elapsed - _last_near >= near_cooldown:
			_last_near = Game.elapsed
			Game.say_random(near_key, {"item": item_name})
	else:
		_fade_glow(0.0)

func _process(_delta: float) -> void:
	if Game.active_interactable != self or used:
		return
	if Input.is_action_just_pressed("Interact"):
		Game.say_random(inspect_key, {"item": item_name})
		interacted.emit()
		_on_interact()
		if one_shot:
			used = true
			Game.unregister_candidate(self)
			set_active(false)

func _exit_tree() -> void:
	Game.unregister_candidate(self)

# Override this in a child script to make each object do something unique.
func _on_interact() -> void:
	pass

func _set_glow(value: float) -> void:
	visual.material.set_shader_parameter("glow_size", value)

func _fade_glow(target: float) -> void:
	if _tween:
		_tween.kill()
	var current: float = visual.material.get_shader_parameter("glow_size")
	_tween = create_tween()
	_tween.tween_method(_set_glow, current, target, 0.1)
