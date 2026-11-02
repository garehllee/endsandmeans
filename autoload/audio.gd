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
func sfx(path: String, volume_db := 0.0, pitch_var := 0.06) -> void:
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
			p.play()
			return

# Pick randomly from a list so footsteps and clicks vary.
func sfx_random(paths: Array, volume_db := 0.0, pitch_var := 0.06) -> void:
	if not paths.is_empty():
		sfx(paths.pick_random(), volume_db, pitch_var)

# Crossfades to a new track.
func music(path: String, fade := 1.5, volume_db := -6.0) -> void:
	if _music.stream and _music.stream.resource_path == path and _music.playing:
		return
	var old := _music
	_music = _music_b
	_music_b = old
	_music.stream = load(path)
	_music.volume_db = -80.0
	_music.play()
	var t := create_tween().set_parallel(true)
	t.tween_property(_music, "volume_db", volume_db, fade)
	t.tween_property(_music_b, "volume_db", -80.0, fade)
	t.chain().tween_callback(_music_b.stop)

func stop_music(fade := 1.0) -> void:
	var t := create_tween()
	t.tween_property(_music, "volume_db", -80.0, fade)
	t.tween_callback(_music.stop)

# 0 to 1, for a settings slider later.
func set_bus_volume(bus: String, linear: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	AudioServer.set_bus_volume_db(i, linear_to_db(clampf(linear, 0.0001, 1.0)))
