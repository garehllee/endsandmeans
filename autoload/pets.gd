extends Node
# The adopted mouse. Once the pet shop is done a mouse follows the character
# from room to room: whichever character is in play, the mouse is put into the
# same room as it, a little behind, and trots after it. Which mouse it is lives
# in a flag ("pet_mouse_<n>"), so it goes away when a run restarts.

const PATH := "res://art/pets/mouse_%d.png"
const COUNT := 6
const WIDTH := 120.0          # drawn width, the same as in the pet shop
const GAP := 135.0            # it keeps about this far from the character
const FOOT := 35.0            # down from the character's middle: the mouse stands on the floor
const SPEED := 620.0

var _idx := -1
var _mouse: Sprite2D
var _check := 0.0
var _t := 0.0
var _first := Vector2.ZERO    # where a just adopted mouse starts, if the shop has said
var _has_first := false

static func flag_for(i: int) -> StringName:
	return StringName("pet_mouse_%d" % i)

# The pet shop calls this with the mouse that was picked and where it stands
# (in the room the character is in).
func adopt(index: int, at: Vector2, face_right: bool) -> void:
	Game.set_flag(flag_for(index))
	_make(index)
	_first = at
	_has_first = true
	_mouse.flip_h = face_right

func has_pet() -> bool:
	return _mouse != null

func _make(index: int) -> void:
	if _mouse:
		_mouse.queue_free()
	_idx = index
	_mouse = Sprite2D.new()
	_mouse.texture = load(PATH % index)
	_mouse.visible = false

func _process(delta: float) -> void:
	_t += delta
	_check -= delta
	if _check <= 0.0:
		_check = 0.4
		_sync()
	if _mouse == null:
		return
	var p: Node2D = Game.active_player
	if p == null or not is_instance_valid(p):
		_mouse.visible = false
		return
	var parent := p.get_parent()
	if parent == null:
		return
	if _mouse.get_parent() != parent:
		if _mouse.get_parent():
			_mouse.get_parent().remove_child(_mouse)
		parent.add_child(_mouse)
		if _has_first:
			_mouse.position = _first
			_has_first = false
		else:
			_mouse.position = p.position + Vector2(-GAP * 0.9, FOOT)
	_mouse.z_index = p.z_index
	if _mouse.get_index() > p.get_index():
		parent.move_child(_mouse, p.get_index())      # drawn behind the character
	var tex := _mouse.texture
	_mouse.scale = Vector2.ONE * (WIDTH / float(tex.get_width())) * p.scale.x
	# hidden while a minigame is moving the character about by hand
	_mouse.visible = not p.platform_mode
	_follow(p, delta)

func _follow(p: Node2D, delta: float) -> void:
	var target := p.position + Vector2(0.0, FOOT * p.scale.x)
	var to := target - _mouse.position
	var d := to.length()
	var moving := false
	if d > GAP:
		var step := minf((d - GAP) * 6.0 + 60.0, SPEED) * delta
		_mouse.position += to.normalized() * minf(step, d - GAP)
		moving = true
		if absf(to.x) > 8.0:
			_mouse.flip_h = to.x > 0.0           # the picture faces left
	_mouse.rotation = sin(_t * 22.0) * 0.1 if moving else lerpf(_mouse.rotation, 0.0, 0.25)

# Keeps the mouse in step with the flags (restarting a run takes it away).
func _sync() -> void:
	var have := -1
	for i in COUNT:
		if Game.has_flag(flag_for(i)):
			have = i
			break
	if have < 0:
		if _mouse:
			_mouse.queue_free()
			_mouse = null
			_idx = -1
		return
	if _mouse == null or _idx != have:
		_make(have)
