extends Node
# Story beats. data/story.json tags folders with an event id; room.gd calls
# Story.trigger(id) when the player reaches one. Each new beat is one line of
# data in story.json plus one case in the match below.

func trigger(event_id: String) -> void:
	match event_id:
		"analysis":
			if not Game.has_flag(Flag.ORANGE_UNLOCKED):
				Game.open_world("analysis")
		_:
			push_warning("Story: no handler for event '%s'" % event_id)

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
