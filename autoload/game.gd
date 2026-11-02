extends Node

signal line_logged(timestamp: String, text: String, kind: String)
signal open_window_requested(scene: PackedScene, pos: Vector2)
signal library_entered
signal library_exited

var active_world := "sandbox"      # which world currently takes input
var active_player: Node2D = null
var input_locked := false          # true during cutscenes
var elapsed := 0.0
var flags := {}
var intro_done := false
var is_moving := false
var last_move_time := 0.0
var idle_logged := false
var candidates: Array = []
var active_interactable: Node = null

const IDLE_SECONDS := 15.0
var _last_pick := {}

func _process(delta: float) -> void:
	elapsed += delta
	if intro_done and not is_moving and not idle_logged \
			and elapsed - last_move_time > IDLE_SECONDS:
		idle_logged = true
		say_random("idle")
	_update_active_interactable()
	if Input.is_action_just_pressed("Interact"):
		print("interact pressed")

func timestamp() -> String:
	var s := int(elapsed)
	return "%d:%02d" % [floori(s / 60.0), s % 60]

# Write a fixed line. kind is "thought" or "action".
func say(text: String, kind := "thought") -> void:
	line_logged.emit(timestamp(), text, kind)

# Write a random line from Lines.DATA, filling in {placeholders}.
func say_random(key: String, vars := {}, kind := "thought") -> void:
	var text := pick(key)
	if text != "":
		say(text.format(vars), kind)

# Same, but only the first time (story beats).
func say_once(key: String, vars := {}, kind := "thought") -> void:
	if flags.has(key):
		return
	flags[key] = true
	say_random(key, vars, kind)

func pick(key: String) -> String:
	var options: Array = Lines.DATA.get(key, [])
	if options.is_empty():
		push_warning("No lines for key: " + key)
		return ""
	if options.size() == 1:
		return options[0]
	var last: int = _last_pick.get(key, -1)
	var i := randi() % options.size()
	while i == last:
		i = randi() % options.size()
	_last_pick[key] = i
	return options[i]
func register_candidate(i: Node) -> void:
	if not candidates.has(i):
		candidates.append(i)

func unregister_candidate(i: Node) -> void:
	candidates.erase(i)
	if active_interactable == i:
		active_interactable = null

func _update_active_interactable() -> void:
	var player := active_player
	var best: Node = null
	if player:
		var best_d := INF
		for c in candidates:
			if c.get_viewport() != player.get_viewport():
				continue
			var d: float = c.global_position.distance_squared_to(player.global_position)
			if d < best_d:
				best_d = d
				best = c
	# ...the rest of the function stays the same...
	if best == active_interactable:
		return
	if active_interactable:
		active_interactable.set_active(false)
	active_interactable = best
	if best:
		best.set_active(true)

func enter_library() -> void:
	active_world = "library"
	library_entered.emit()

func exit_library() -> void:
	active_world = "sandbox"
	library_exited.emit()

signal analysis_requested
signal analysis_closed(caught: bool)

func open_analysis() -> void:
	active_world = "analysis"
	analysis_requested.emit()

func close_analysis(caught: bool) -> void:
	active_world = "library"
	analysis_closed.emit(caught)
