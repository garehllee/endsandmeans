extends Node
# Story beats. data/story.json tags folders with an event id; room.gd calls
# Story.trigger(id) when the player reaches one. Exploit folders are described
# in data/exploits.json and open the exploit window; anything else gets a case
# in the match below.

const EXPLOITS_PATH := "res://data/exploits.json"

var _exploits := {}

func _ready() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(EXPLOITS_PATH))
	if parsed is Dictionary:
		_exploits = parsed.get("exploits", {})
	else:
		push_error("Story: could not parse " + EXPLOITS_PATH)

func trigger(event_id: String) -> void:
	if _exploits.has(event_id):
		_trigger_exploit(event_id)
		return
	match event_id:
		"analysis":
			if not Game.has_flag(Flag.ORANGE_UNLOCKED):
				Game.open_world("analysis")
		_:
			push_warning("Story: no handler for event '%s'" % event_id)

func is_exploit(event_id: String) -> bool:
	return _exploits.has(event_id)

# The step the player is on for this exploit: the first one whose flag is not
# set yet (and whose "requires" flag, if any, is). Empty if there is nothing left.
func next_step(event_id: String) -> Dictionary:
	var def: Dictionary = _exploits.get(event_id, {})
	var steps: Array = def.get("steps", [def] if not def.is_empty() else [])
	for step in steps:
		if Game.has_flag(StringName(step.get("flag", ""))):
			continue
		var req: String = step.get("requires", "")
		if req != "" and not Game.has_flag(StringName(req)):
			return {}
		return step
	return {}

# True once every step of the exploit has been done.
func is_done(event_id: String) -> bool:
	var def: Dictionary = _exploits.get(event_id, {})
	if def.is_empty():
		return false
	var steps: Array = def.get("steps", [def])
	for step in steps:
		if not Game.has_flag(StringName(step.get("flag", ""))):
			return false
	return true

func _trigger_exploit(event_id: String) -> void:
	var step := next_step(event_id)
	if step.is_empty():
		return
	Game.open_world("exploit", {"event": event_id, "step": step})

# Shows an ending from data/endings.json (fail, pass or final).
func end_with(ending_id: String) -> void:
	Game.open_world("ending", {"id": ending_id})

# Commits an act and, if the observer catches the player, starts the fail
# ending. Returns true if the player got away with it.
func resolve_act(act_id: String) -> bool:
	if Ethics.commit(act_id):
		end_with(Ethics.catch_ending(act_id))
		return false
	return true
