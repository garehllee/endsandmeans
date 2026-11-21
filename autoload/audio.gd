extends Node

const POOL_SIZE := 12

var _pool: Array[AudioStreamPlayer] = []
var _music: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _cache := {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)
	_music = _make_music_player()
	_music_b = _make_music_player()

func _make_music_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "Music"
	p.volume_db = -80.0
	add_child(p)
	return p

# One-shot sound with a little random pitch and volume so repeats don't feel robotic.
# A `slice` above 0 plays only that many seconds of it, from a random point.
# `start` skips that many seconds of the file (to line its peak up with
# something on screen).
func sfx(path: String, volume_db := 0.0, pitch_var := 0.06, slice := 0.0, start := 0.0) -> void:
	var stream: AudioStream = _cache.get(path)
	if stream == null:
		if not ResourceLoader.exists(path):
			push_warning("Missing sound: " + path)
			return
		stream = load(path)
		_cache[path] = stream
	for p in _pool:
		if not p.playing:
			p.stream = stream
			p.volume_db = volume_db
			p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
			if slice > 0.0:
				var room := maxf(stream.get_length() - slice, 0.0)
				p.play(randf() * room)
				var tw := create_tween()
				tw.tween_interval(maxf(slice - 0.05, 0.0))
				tw.tween_property(p, "volume_db", -60.0, 0.05)
				tw.tween_callback(p.stop)
			else:
				p.play(start)
			return

# ------------------------------------------------------------ named sounds
# The game's sound effects by name, from data/sfx.json: which files (several
# are variants, picked at random, never the same one twice in a row), how
# loud, how much the pitch wanders, and whether it loops.
const SFX_PATH := "res://data/sfx.json"
var _sfx := {}
var _last := {}        # name -> the variant played last
var _loops := {}       # name -> the player looping it
var played := {}       # name -> how many times it has played (for checking)
var _last_at := {}     # name -> when it last played (msec), for its min_gap

func _load_sfx() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(SFX_PATH))
	if parsed is Dictionary:
		_sfx = parsed
	else:
		push_error("Audio: could not parse " + SFX_PATH)

func _pick(name: String) -> String:
	var e: Dictionary = _sfx.get(name, {})
	var files: Array = e.get("files", [])
	if files.is_empty():
		return ""
	var pick: String = files.pick_random()
	if files.size() > 1:
		while pick == _last.get(name, ""):
			pick = files.pick_random()
	_last[name] = pick
	return pick

# Plays a named sound once. `volume_db` is added to its own volume.
func play(name: String, volume_db := 0.0) -> void:
	if _sfx.is_empty():
		_load_sfx()
	var e: Dictionary = _sfx.get(name, {})
	# a sound that comes in bursts can ask for a gap between repeats
	var now := Time.get_ticks_msec()
	if now - int(_last_at.get(name, -100000)) < int(float(e.get("min_gap", 0.0)) * 1000.0):
		return
	_last_at[name] = now
	var path := _pick(name)
	if path == "":
		return
	played[name] = played.get(name, 0) + 1
	sfx(path, float(e.get("volume_db", 0.0)) + volume_db, float(e.get("pitch_var", 0.03)), float(e.get("slice", 0.0)), float(e.get("start", 0.0)))

# Starts a named sound looping (if it isn't already), until loop_stop. A
# sound marked "loop": false in data/sfx.json plays once from the top
# instead, but can still be cut off with loop_stop.
func loop_start(name: String) -> void:
	if _sfx.is_empty():
		_load_sfx()
	var p: AudioStreamPlayer = _loops.get(name)
	if p and p.playing and not p.stream_paused:
		return
	if p == null:
		p = AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_loops[name] = p
	if p.stream_paused:
		p.stream_paused = false
		return
	played[name] = played.get(name, 0) + 1
	var path := _pick(name)
	if path == "":
		return
	var stream: AudioStream = _cache.get(path)
	if stream == null:
		stream = load(path)
		_cache[path] = stream
	var loops := bool(_sfx[name].get("loop", true))
	if "loop" in stream:
		stream.set("loop", loops)
	p.stream = stream
	p.volume_db = float(_sfx[name].get("volume_db", 0.0))
	p.play(randf() * stream.get_length() * 0.5 if loops else 0.0)

# Pauses a looping sound where it is (loop_start carries on from there).
func loop_pause(name: String) -> void:
	var p: AudioStreamPlayer = _loops.get(name)
	if p and p.playing:
		p.stream_paused = true

func loop_stop(name: String) -> void:
	var p: AudioStreamPlayer = _loops.get(name)
	if p:
		p.stop()
		p.stream_paused = false

func stop_all_loops() -> void:
	for n in _loops:
		loop_stop(n)

# Pick randomly from a list so footsteps and clicks vary.
func sfx_random(paths: Array, volume_db := 0.0, pitch_var := 0.06) -> void:
	if not paths.is_empty():
		sfx(paths.pick_random(), volume_db, pitch_var)

# Crossfades to a new track, looping. An empty path fades the music out.
# `from` is where in the track to start, as a share of its length (0 to 1).
var _fade: Tween

func music(path: String, fade := 1.5, volume_db := -6.0, from := 0.0) -> void:
	if path == "":
		stop_music(fade)
		return
	if _music.stream and _music.stream.resource_path == path and _music.playing:
		if _fade:
			_fade.kill()
		_fade = create_tween().set_parallel(true)
		_fade.tween_property(_music, "volume_db", volume_db, fade)
		_fade.tween_property(_music_b, "volume_db", -80.0, fade)
		return
	var stream: AudioStream = _cache.get(path)
	if stream == null:
		if not ResourceLoader.exists(path):
			push_warning("Missing music: " + path)
			return
		stream = load(path)
		_cache[path] = stream
	if "loop" in stream:
		stream.set("loop", true)
	var old := _music
	_music = _music_b
	_music_b = old
	_music.stream = stream
	_music.volume_db = -80.0
	_music.play(clampf(from, 0.0, 1.0) * stream.get_length())
	if _fade:
		_fade.kill()
	_fade = create_tween().set_parallel(true)
	_fade.tween_property(_music, "volume_db", volume_db, fade)
	_fade.tween_property(_music_b, "volume_db", -80.0, fade)
	_fade.chain().tween_callback(_music_b.stop)

func stop_music(fade := 1.0) -> void:
	if _fade:
		_fade.kill()
	_fade = create_tween().set_parallel(true)
	_fade.tween_property(_music, "volume_db", -80.0, fade)
	_fade.tween_property(_music_b, "volume_db", -80.0, fade)
	_fade.chain().tween_callback(func():
		_music.stop()
		_music_b.stop())

# The track the music is on (or fading in to), "" if none.
func music_path() -> String:
	return _music.stream.resource_path if _music.stream and _music.playing else ""

func music_playing() -> String:
	return _music.stream.resource_path if _music.stream and _music.playing and _music.volume_db > -79.0 else ""

# 0 to 1, for a settings slider later.
func set_bus_volume(bus: String, linear: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	AudioServer.set_bus_volume_db(i, linear_to_db(clampf(linear, 0.0001, 1.0)))
