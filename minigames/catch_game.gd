extends Minigame
class_name CatchGame
# Dodge the firewalls and catch a folder. Touching a firewall flashes the arena
# and restarts the round; catching a folder finishes the game with success.
# The owner calls setup() and then start(config).

signal round_started

enum State { PLAYING, HIT, DONE }

@export var blink_color := Color(1.0, 0.1, 0.1)
@export var blink_alpha := 0.6
@export var blink_time := 0.12           # seconds per on or off phase

class Bouncer:
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var radius := 50.0
	var is_firewall := false

var config: MinigameConfig
var running := false

var _arena := Rect2()
var _player: Node2D
var _start_pos := Vector2.ZERO
var _state := State.PLAYING
var _bouncers: Array[Bouncer] = []
var _flash := 0.0

# arena: where the bouncers live. start_pos: where the player stands each round.
func setup(arena: Rect2, player: Node2D, start_pos: Vector2) -> void:
	_arena = arena
	_player = player
	_start_pos = start_pos

func start(cfg: MinigameConfig) -> void:
	config = cfg
	# Keep the start position inside the arena, just in case.
	_start_pos = Vector2(
		clampf(_start_pos.x, _arena.position.x + config.player_radius, _arena.end.x - config.player_radius),
		clampf(_start_pos.y, _arena.position.y + config.player_radius, _arena.end.y - config.player_radius))
	running = true
	_begin_round()

func stop() -> void:
	running = false
	if _player and is_instance_valid(_player) and _player.has_method("revive"):
		_player.revive()
	_bouncers.clear()
	_flash = 0.0
	queue_redraw()

func _begin_round() -> void:
	_state = State.PLAYING
	_flash = 0.0
	_player.position = _start_pos
	_spawn_bouncers()
	Game.input_locked = false
	round_started.emit()

func _spawn_bouncers() -> void:
	_bouncers.clear()
	for i in config.firewall_count + config.folder_count:
		var bn := Bouncer.new()
		bn.is_firewall = i < config.firewall_count
		bn.radius = config.icon_size * 0.5 * config.hit_scale
		var m := config.icon_size * 0.5
		for _try in 30:
			bn.pos = Vector2(
				randf_range(_arena.position.x + m, _arena.end.x - m),
				randf_range(_arena.position.y + m, _arena.end.y - m))
			if bn.pos.distance_to(_start_pos) > config.safe_radius:
				break
		bn.vel = Vector2.from_angle(randf() * TAU) * randf_range(config.speed_min, config.speed_max)
		_bouncers.append(bn)

func _process(delta: float) -> void:
	if running and _state == State.PLAYING:
		_update(delta)
	queue_redraw()

func _update(delta: float) -> void:
	var m := config.icon_size * 0.5
	for bn in _bouncers:
		bn.pos += bn.vel * delta
		if bn.pos.x < _arena.position.x + m:
			bn.pos.x = _arena.position.x + m
			bn.vel.x = absf(bn.vel.x)
		elif bn.pos.x > _arena.end.x - m:
			bn.pos.x = _arena.end.x - m
			bn.vel.x = -absf(bn.vel.x)
		if bn.pos.y < _arena.position.y + m:
			bn.pos.y = _arena.position.y + m
			bn.vel.y = absf(bn.vel.y)
		elif bn.pos.y > _arena.end.y - m:
			bn.pos.y = _arena.end.y - m
			bn.vel.y = -absf(bn.vel.y)
	var pr := config.player_radius
	_player.position = Vector2(
		clampf(_player.position.x, _arena.position.x + pr, _arena.end.x - pr),
		clampf(_player.position.y, _arena.position.y + pr, _arena.end.y - pr))
	for bn in _bouncers:
		if _player.position.distance_to(bn.pos) < bn.radius + pr:
			if bn.is_firewall:
				_hit()
			else:
				_catch()
			return

func _hit() -> void:
	_state = State.HIT
	Game.input_locked = true
	Game.say_random("firewall_hit")
	if _player.has_method("die"):
		_player.die()                    # the bug comes apart while the screen flashes
	for i in 2:
		_flash = blink_alpha
		await get_tree().create_timer(blink_time).timeout
		_flash = 0.0
		await get_tree().create_timer(blink_time).timeout
		if not running or _state != State.HIT:
			return
	await get_tree().create_timer(0.3).timeout
	if not running or _state != State.HIT:
		return
	if _player.has_method("revive"):
		_player.revive()
	_begin_round()

func _catch() -> void:
	_state = State.DONE
	Game.input_locked = true
	finished.emit(true)

func _draw() -> void:
	if not running:
		return
	for bn in _bouncers:
		_draw_bouncer(bn)
	if _flash > 0.0:
		draw_rect(_arena, Color(blink_color, _flash))

func _draw_bouncer(bn: Bouncer) -> void:
	var tex: Texture2D = config.firewall_icon if bn.is_firewall else config.folder_icon
	var sz := Vector2(config.icon_size, config.icon_size)
	if tex:
		sz.y = config.icon_size * tex.get_height() / float(tex.get_width())
		draw_texture_rect(tex, Rect2(bn.pos - sz * 0.5, sz), false)
	else:
		draw_rect(Rect2(bn.pos - sz * 0.5, sz), Color("#b5523b") if bn.is_firewall else Color("#c9c9c9"))
