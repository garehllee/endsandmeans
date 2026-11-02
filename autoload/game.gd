extends Node

# ---------------------------------------------------------------- signals
signal line_logged(timestamp: String, text: String, kind: String)
signal open_window_requested(scene: PackedScene, pos: Vector2)

# Generic world switching (replaces the per-window signals).
signal world_opened(id: String, params: Dictionary)
signal world_closed(id: String, result: Dictionary)

signal flag_changed(flag: StringName, value: bool)

# ---------------------------------------------------------------- state
var active_world := "sandbox"      # which world currently takes input
var active_player: Node2D = null
var input_locked := false          # true during cutscenes
var elapsed := 0.0
var flags := {}                    # story flags only; use has_flag / set_flag
var seen := {}                     # one-time lines (say_once), kept apart from flags
var intro_done := false
var is_moving := false
var last_move_time := 0.0
var idle_logged := false
var candidates: Array = []
var active_interactable: Node = null

const IDLE_SECONDS := 15.0
var _last_pick := {}
var _world_stack: Array[String] = []

func _process(delta: float) -> void:
	elapsed += delta
	if intro_done and not is_moving and not idle_logged \
			and elapsed - last_move_time > IDLE_SECONDS:
		idle_logged = true
		say_random("idle")
	_update_active_interactable()

# ---------------------------------------------------------------- notepad lines
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
	if seen.has(key):
		return
	seen[key] = true
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

# ---------------------------------------------------------------- flags
func has_flag(f: StringName) -> bool:
	return flags.get(f, false)

func set_flag(f: StringName, value := true) -> void:
	if flags.get(f, false) == value:
		return
	flags[f] = value
	flag_changed.emit(f, value)

# ---------------------------------------------------------------- worlds
# The stack makes nesting automatic: closing "analysis" returns to "library",
# closing "library" returns to "sandbox".
func open_world(id: String, params := {}) -> void:
	if id == active_world:
		return
	_world_stack.append(active_world)
	active_world = id
	world_opened.emit(id, params)
	_legacy_opened(id)

func close_world(result := {}) -> void:
	if _world_stack.is_empty():
		push_warning("close_world() called with no world open")
		return
	var closed := active_world
	active_world = _world_stack.pop_back()
	world_closed.emit(closed, result)
	_legacy_closed(closed, result)

# ---------------------------------------------------------------- interactables
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
	if best == active_interactable:
		return
	if active_interactable:
		active_interactable.set_active(false)
	active_interactable = best
	if best:
		best.set_active(true)

# ================================================================
# TEMPORARY LEGACY BRIDGE
# Keeps the old scripts working until you migrate them. Delete this whole
# section once nothing calls enter_library / exit_library / open_analysis /
# close_analysis or connects to the four old signals below.
# ================================================================
signal library_entered
signal library_exited
signal analysis_requested
signal analysis_closed(caught: bool)

func enter_library() -> void:
	open_world("library")

func exit_library() -> void:
	close_world()

func open_analysis() -> void:
	open_world("analysis")

func close_analysis(caught: bool) -> void:
	close_world({"caught": caught})

func _legacy_opened(id: String) -> void:
	match id:
		"library": library_entered.emit()
		"analysis": analysis_requested.emit()

func _legacy_closed(id: String, result: Dictionary) -> void:
	match id:
		"library": library_exited.emit()
		"analysis": analysis_closed.emit(result.get("caught", false))
