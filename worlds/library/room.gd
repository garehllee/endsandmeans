extends Node2D

@export var tree_path := "res://data/tree_thumbs.json"
@export var story_path := "res://data/story.json"
@export var camera_follow := 8.0

@onready var wall: FileWall = $Wall
@onready var player: Node2D = $Player
@onready var cam: Camera2D = $Camera2D

# walls[0] is the root room; each folder you enter adds a room above it.
var walls: Array[FileWall] = []

var _events := {}
var _additions: Array = []   # files that appear later, from story.json "additions"
var _added := {}
var _tree: Dictionary = {}

func _ready() -> void:
	player.z_index = 10
	var tree = JSON.parse_string(FileAccess.get_file_as_string(tree_path))
	_tree = tree
	var story = JSON.parse_string(FileAccess.get_file_as_string(story_path))
	if story is Dictionary:
		_events = story.get("events", {})
		_additions = story.get("additions", [])
	_tag_events(tree, _events)
	wall.entry_entered.connect(_on_entry_entered.bind(wall))
	wall.build(tree.get("children", []))
	walls.append(wall)
	player.global_position = $Spawn.global_position
	_follow_camera(999.0)   # snap on the first frame
	Game.world_opened.connect(_on_world_opened)
	Game.world_closed.connect(_on_world_closed)
	Game.flag_changed.connect(func(_f: StringName, _v: bool): _apply_additions())

# Tags every entry whose name appears in story.json's "events" with its event id.
func _tag_events(folder: Dictionary, events: Dictionary) -> void:
	for c in folder.get("children", []):
		if events.has(c.name):
			c["event"] = events[c.name]
		if c.get("type", "") == "folder":
			_tag_events(c, events)

func _process(delta: float) -> void:
	var py := player.global_position.y
	# Back below the parent's wall means you've left the hallway.
	if walls.size() > 1:
		var parent := walls[walls.size() - 2]
		if py >= parent.global_position.y + parent.wall_size.y:
			_leave_child()
	# Only the room you're standing in is interactive.
	var top: FileWall = walls.back()
	top.active = py < top.global_position.y + top.level_height()
	_follow_camera(delta)
	_check_events()
	
func _check_events() -> void:
	if walls.size() < 2:
		return
	var top: FileWall = walls.back()
	if not top.has_meta("event") or top.get_meta("fired", false):
		return
	# Fires once the player has walked up out of the hallway and into the folder's own room.
	if player.global_position.y < top.global_position.y + top.level_height() - top.hallway_depth * 2.0:
		top.set_meta("fired", true)
		Story.trigger(top.get_meta("event"))

func _on_world_opened(id: String, _params: Dictionary) -> void:
	match id:
		"library":
			_on_arrive()
		"analysis":
			create_tween().tween_property(player, "modulate:a", 0.0, 0.3)

func _on_world_closed(id: String, _result: Dictionary) -> void:
	if id == "analysis":
		create_tween().tween_property(player, "modulate:a", 1.0, 0.3)
	_apply_additions()

# Adds the files listed under "additions" in story.json once their flag is set.
# An addition can wait on one flag ("when") or on several ("when_all").
func _conditions_met(a: Dictionary) -> bool:
	var when: String = a.get("when", "")
	if when != "" and not Game.has_flag(StringName(when)):
		return false
	for f in a.get("when_all", []):
		if not Game.has_flag(StringName(f)):
			return false
	return true

# New files go on the root wall and blink so the player notices them.
func _apply_additions() -> void:
	if Game.active_world != "library":
		return
	for a in _additions:
		var id: String = a.get("id", "")
		if _added.has(id) or a.get("timing", "") == "on_leave":
			continue
		if not _conditions_met(a):
			continue
		_added[id] = true
		var entry: Dictionary = a.get("entry", {}).duplicate(true)
		_tag_events({"children": [entry]}, _events)
		var idx: int = walls[0].add_entry(entry)
		walls[0].blink_entry(idx, a.get("blink", 3))
		if a.has("say"):
			Game.say_random(a["say"])

func _on_entry_entered(entry: Dictionary, index: int, w: FileWall) -> void:
	if w != walls.back():
		return
	if entry.type == "folder":
		_open_child(w, entry, index)
	else:
		Game.say("opening %s..." % entry.name, "action")
		# next step: open a viewer window for this file

func _open_child(parent_wall: FileWall, entry: Dictionary, index: int) -> void:
	Game.say_random("folder_open", {"item": entry.name})
	var child := FileWall.new()
	child.copy_settings_from(parent_wall)
	child.solid_bottom = false
	child.floor_grad = parent_wall.gradient_of(index)
	# Its floor edge meets the top of the parent's wall.
	child.position = parent_wall.position - Vector2(0, child.level_height())
	add_child(child)
	child.entry_entered.connect(_on_entry_entered.bind(child))
	child.build(entry.get("children", []))
	child.set_meta("entry", entry)
	if entry.get("event", "") != "":
		child.set_meta("event", entry["event"])
	child.active = false
	parent_wall.lock_hallway(index)
	walls.append(child)

func _leave_child() -> void:
	var child: FileWall = walls.pop_back()
	var left: Dictionary = child.get_meta("entry", {})
	child.queue_free()
	walls.back().unlock()
	Game.say_random("folder_leave")
	# A finished exploit's folder disappears once you walk out of it.
	var ev: String = left.get("event", "")
	if ev != "" and Story.is_done(ev):
		await _delete_entry(walls.back(), left)
		_apply_leave_additions()

# Removes a file from a room, and from the data it is rebuilt from.
func _delete_entry(wall_node: FileWall, entry: Dictionary) -> void:
	var host: Dictionary = _tree
	if wall_node != walls[0]:
		host = wall_node.get_meta("entry", {})
	var kids: Array = host.get("children", [])
	for i in kids.size():
		if kids[i].name == entry.name:
			kids.remove_at(i)
			break
	await wall_node.remove_entry(entry.name)     # the strip slides shut like a door

# Additions marked "timing": "on_leave" in story.json show up when the player walks
# out of a finished exploit folder, so they appear right after the old file is gone.
# "parent" names the folder they go into.
func _apply_leave_additions() -> void:
	for a in _additions:
		var id: String = a.get("id", "")
		if _added.has(id) or a.get("timing", "") != "on_leave":
			continue
		if not _conditions_met(a):
			continue
		_added[id] = true
		var entries: Array = a.get("entries", [a.get("entry", {})])
		var parent_name: String = a.get("parent", "")
		var placed := false
		for w in walls:
			var host: Dictionary = _tree if w == walls[0] else w.get_meta("entry", {})
			if (parent_name == "" and w == walls[0]) or host.get("name", "") == parent_name:
				var idxs: Array = []
				for e in entries:
					var entry: Dictionary = e.duplicate(true)
					_tag_events({"children": [entry]}, _events)
					host.get("children", []).append(entry)
					idxs.append(w.add_entry(entry))
				w.blink_entries(idxs, a.get("blink", 3))
				placed = true
				break
		if not placed:
			# The room isn't open right now; put them in its data so they're there next time.
			var target := _find_entry(_tree, parent_name)
			for e in entries:
				var entry: Dictionary = e.duplicate(true)
				_tag_events({"children": [entry]}, _events)
				target.get("children", []).append(entry)
		if a.has("say"):
			Game.say_random(a["say"])

func _find_entry(folder: Dictionary, entry_name: String) -> Dictionary:
	for c in folder.get("children", []):
		if c.get("name", "") == entry_name:
			return c
		if c.get("type", "") == "folder":
			var found := _find_entry(c, entry_name)
			if not found.is_empty():
				return found
	return {}

func _follow_camera(delta: float) -> void:
	var root := walls[0]
	var top: FileWall = walls.back()
	var vh := get_viewport_rect().size.y / cam.zoom.y
	var lo: float = top.global_position.y + vh * 0.5
	var hi := maxf(root.global_position.y + root.level_height() - vh * 0.5, lo)
	var target := clampf(player.global_position.y, lo, hi)
	cam.global_position.x = root.global_position.x + root.wall_size.x * 0.5
	cam.global_position.y = lerpf(cam.global_position.y, target, 1.0 - exp(-camera_follow * delta))

func _on_arrive() -> void:
	Game.input_locked = true
	player.global_position = $Spawn.global_position
	player.modulate.a = 0.0
	_follow_camera(999.0)
	var t := create_tween()
	t.tween_property(player, "modulate:a", 1.0, 0.5)
	await t.finished
	Game.input_locked = false
	Game.say_random("library_arrive")
