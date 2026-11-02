extends Node2D

@export var tree_path := "res://data/tree_thumbs.json"
@export var story_path := "res://data/story.json"
@export var camera_follow := 8.0

@onready var wall: FileWall = $Wall
@onready var player: Node2D = $Player
@onready var cam: Camera2D = $Camera2D

const ORANGE_FOLDER := {"name": "ZZ_Confirm_Anyone_See_Orange_Folder", "type": "folder", "children": []}

# walls[0] is the root room; each folder you enter adds a room above it.
var walls: Array[FileWall] = []

func _ready() -> void:
	player.z_index = 10
	var tree = JSON.parse_string(FileAccess.get_file_as_string(tree_path))
	var story = JSON.parse_string(FileAccess.get_file_as_string(story_path))
	var events: Dictionary = story.get("events", {}) if story is Dictionary else {}
	_tag_events(tree, events)
	wall.entry_entered.connect(_on_entry_entered.bind(wall))
	wall.build(tree.get("children", []))
	walls.append(wall)
	player.global_position = $Spawn.global_position
	_follow_camera(999.0)   # snap on the first frame
	Game.world_opened.connect(_on_world_opened)
	Game.world_closed.connect(_on_world_closed)

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

func _on_world_closed(id: String, result: Dictionary) -> void:
	if id != "analysis":
		return
	create_tween().tween_property(player, "modulate:a", 1.0, 0.3)
	if result.get("caught", false):
		var idx: int = walls[0].add_entry(ORANGE_FOLDER.duplicate(true))
		walls[0].blink_entry(idx, 3)
		Game.say_random("orange_added")

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
	if entry.get("event", "") != "":
		child.set_meta("event", entry["event"])
	child.active = false
	parent_wall.lock_hallway(index)
	walls.append(child)

func _leave_child() -> void:
	var child: FileWall = walls.pop_back()
	child.queue_free()
	walls.back().unlock()
	Game.say_random("folder_leave")

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
