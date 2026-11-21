extends Node
# Picks the music for whatever is on screen and hands it to Audio, which
# crossfades. Which track goes where is in data/music.json; who made each
# one is in data/credits.json.
#
# In order of priority: the landing screen, an ending, a running minigame
# (each has its own track, or none when it plays its own music, like the
# rhythm game and the last folder), then whichever window has the player
# (the desktop, the library, a folder's message screen).

const MUSIC_PATH := "res://data/music.json"
const ENDINGS_PATH := "res://data/endings.json"
const CREDITS_PATH := "res://data/credits.json"

signal track_changed(path: String)   # for the now-playing credit ("" when nothing plays)

var _map := {}
var _ending_kinds := {}
var _minigame := ""        # the minigame running now ("" for none)
var _ending := ""          # the ending on screen now ("" for none)
var _own := ""             # a track a minigame plays itself (the rhythm game, the last folder)
var _credits := {}         # file path -> {title, artist, ...}
var _shown := ""
var _heard := {}           # tracks that have played at least once
var _rng := RandomNumberGenerator.new()

# So the same few tracks don't wear thin: the first time a track plays it
# starts from the top, but after that it sometimes picks up partway through.
const RESUME_CHANCE := 0.5
const RESUME_RANGE := Vector2(0.15, 0.75)   # where it may start, as a share of the track

func _ready() -> void:
	_rng.randomize()
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(MUSIC_PATH))
	if parsed is Dictionary:
		_map = parsed
	else:
		push_error("Music: could not parse " + MUSIC_PATH)
	var endings = JSON.parse_string(FileAccess.get_file_as_string(ENDINGS_PATH))
	if endings is Dictionary:
		for id in endings.get("endings", {}):
			_ending_kinds[id] = endings["endings"][id].get("kind", "fail")
	var credits = JSON.parse_string(FileAccess.get_file_as_string(CREDITS_PATH))
	if credits is Dictionary:
		for c in credits.get("music", []):
			_credits[c["file"]] = c
	Game.game_started.connect(update)
	Game.world_opened.connect(func(id: String, params: Dictionary):
		if id == "ending":
			_ending = params.get("id", "")
		update())
	Game.world_closed.connect(func(id: String, _result: Dictionary):
		if id == "ending":
			_ending = ""
		elif id == "analysis" or id == "exploit":
			_minigame = ""        # its minigame went with it
			_own = ""
		update())
	update.call_deferred()

# Called by a room when its minigame starts ("catch", "laser", ...) and stops.
func minigame_started(key: String) -> void:
	_minigame = key
	update()

func minigame_stopped() -> void:
	if _minigame == "":
		return
	_minigame = ""
	_own = ""
	update()

# A minigame that plays its own music says what's playing, for the credit.
func playing_own(stream: AudioStream) -> void:
	_own = stream.resource_path if stream else ""
	_announce()

# A new run reloads the scene; nothing from the old one is still running.
func reset() -> void:
	_minigame = ""
	_ending = ""
	_own = ""
	update()

func update() -> void:
	var path := _track()
	var from := 0.0
	if path != "" and path != Audio.music_path():
		if _heard.has(path) and _rng.randf() < RESUME_CHANCE:
			from = _rng.randf_range(RESUME_RANGE.x, RESUME_RANGE.y)
		_heard[path] = true
	Audio.music(path, 1.5, -6.0, from)
	_announce()

# What's playing now, as a file path ("" for nothing).
func now_playing() -> String:
	var t := _track()
	return t if t != "" else _own

# Title and artist of a track from data/credits.json ({} if it isn't listed).
func credit(path: String) -> Dictionary:
	return _credits.get(path, {})

func _announce() -> void:
	var now := now_playing()
	if now != _shown:
		_shown = now
		track_changed.emit(now)

func _track() -> String:
	if not Game.started:
		return _map.get("title", "")
	if _ending != "":
		return _map.get("endings", {}).get(_ending_kinds.get(_ending, "fail"), "")
	if _minigame != "":
		return _map.get("minigames", {}).get(_minigame, "")
	return _map.get("worlds", {}).get(Game.active_world, "")
