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
