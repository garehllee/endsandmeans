extends Minigame
class_name RhythmGame
# "Commit on the beat": a terminal log and a COMMIT button. The music loops
# and, on chosen beats, a command types itself into the terminal:
#     C:\ git commit -m "mute the audit log"
# When it is time to commit that line turns green and flashes. Press E on the
# beat and git answers with its output. Press too early or too late, or not at
# all, and it answers with an error and counts a bad commit. More than
# `max_bad` of those and the run fails: the bug comes apart, the branch is
# reset and the song starts over. Get through to the push and the game is won.
#
# Time comes from the music itself (where the player has got to in the song),
# so the beats on screen stay in step with what is heard.

enum State { WAITING, WALKING, PLAYING, FAILED, DONE }
enum { PENDING, GOOD, BAD }

const PROMPT := "C:\\ "
const FLASH_HZ := 9.0
const PRESS_SHOW := 0.12            # how long the button stays down after a press

var config: RhythmConfig
var running := false

var _arena := Rect2()
var _player: Node2D
var _layer := Rect2()               # where the picture's top left sits, in room units
var _s := 1.0                       # room units per picture unit
var _built := false
var _expand := 0.0
var _state := State.WAITING
var _start_room := Vector2.ZERO     # where the button was pressed, in room units
var _pos := Vector2.ZERO            # the character's middle while it walks over, picture units

var _music: AudioStreamPlayer
var _tick := 0.345                  # seconds per tick
var _time := 0.0                    # how far into the song we are, in seconds
var _loops := 0
var _last_pos := 0.0
var _wall := 0.0                    # plain seconds, for the flashing and the button
var _press_at := -10.0
var _timer := 0.0

var _lines: Array[Dictionary] = []  # {text, t0, dur, kind, cue}
var _cues: Array[Dictionary] = []   # {t, lead, grace, text, state, line}
var _events: Array[Dictionary] = [] # lines waiting for their moment: {t, ...}
var _next_event := 0
var _next_cue := 0
var _bad := 0
var _good := 0
var _rng := RandomNumberGenerator.new()

func setup(arena: Rect2, player: Node2D, start_pos: Vector2) -> void:
	_arena = arena
	_player = player
	_start_room = start_pos

# ---------------------------------------------------------------- building
func prepare(cfg: MinigameConfig) -> void:
	config = cfg as RhythmConfig
	if config == null:
		push_error("RhythmGame needs a RhythmConfig")
		return
	_rng.randomize()
	_tick = 60.0 / config.bpm
	_music = AudioStreamPlayer.new()
	_music.stream = config.music
	_music.volume_db = config.music_db
	if config.music and "loop" in config.music:
		config.music.set("loop", true)
	add_child(_music)
	_built = true
	set_expand(_arena, 0.0)

# Lays out the whole song: the opening lines and one command for every cue.
func _build_chart() -> void:
	_lines.clear()
	_cues.clear()
	_events.clear()
	_next_event = 0
	_next_cue = 0
	_bad = 0
	_good = 0
	_events.append({"t": 0.15, "dur": 0.8, "kind": "cmd", "text": PROMPT + "cd swarm\\task-4"})
	_events.append({"t": 1.25, "dur": 0.45, "kind": "cmd", "text": PROMPT + "git status"})
	_events.append({"t": 1.8, "dur": 0.1, "kind": "out",
			"text": "On branch main. %d changes to commit." % maxi(config.cues.size() - 1, 0)})
	var messages := Array(config.messages)
	messages.shuffle()
	var prev_t := -100.0
	for i in config.cues.size():
		var t := float(config.cues[i]) * _tick
		var gap := t - prev_t
		var next_gap := 100.0
		if i + 1 < config.cues.size():
			next_gap = float(config.cues[i + 1]) * _tick - t
		var text := ""
		if i == config.cues.size() - 1:
			text = PROMPT + "git push"
		elif gap < _tick * 2.5 and not config.quick_messages.is_empty():
			text = PROMPT + "git commit -m \"%s\"" % config.quick_messages[_rng.randi() % config.quick_messages.size()]
		else:
			text = PROMPT + "git commit -m \"%s\"" % messages[i % maxi(messages.size(), 1)]
		var lead := minf(config.type_lead, gap - config.tolerance - 0.12)
		_cues.append({
			"t": t,
			"lead": lead,
			# a late press still belongs to this commit until here; never into the next one's window
			"grace": maxf(config.tolerance, minf(config.late_grace, next_gap - config.tolerance - 0.02)),
			"text": text,
			"state": PENDING,
			"line": {},
		})
		_events.append({"t": t - lead, "dur": lead - config.tolerance, "kind": "cmd", "text": text, "cue": i})
		prev_t = t
	_events.sort_custom(func(a: Dictionary, b: Dictionary): return a["t"] < b["t"])

# ---------------------------------------------------------------- placing
func set_expand(rect: Rect2, t: float) -> void:
	if not _built:
		return
	_expand = t
	_s = rect.size.x / config.window.x
	var win_h := config.window.y * _s
	_layer = Rect2(rect.position.x, rect.get_center().y - win_h * 0.5, config.window.x * _s, win_h)
	queue_redraw()

func _to_room(p: Vector2) -> Vector2:
	return _layer.position + p * _s

# ---------------------------------------------------------------- running
func start(cfg: MinigameConfig) -> void:
	if not _built:
		prepare(cfg)
	if not _built:
		finished.emit(true)
		return
	set_expand(_arena, 1.0)
	running = true
	_pos = (_start_room - _layer.position) / maxf(_s, 0.0001)
	if _player:
		_player.platform_mode = true          # the character's own walking is switched off
	if config.walk_to_button:
		_state = State.WALKING                # it walks over to the button first
	else:
		_begin_song()
	Game.input_locked = false

func stop() -> void:
	running = false
	if _music:
		_music.stop()
	if _player and is_instance_valid(_player):
		_player.platform_mode = false
		_player.revive()

func _begin_song() -> void:
	_build_chart()
	_time = 0.0
	_loops = 0
	_last_pos = 0.0
	_music.volume_db = config.music_db
	_music.play(0.0)
	_state = State.PLAYING

func _process(delta: float) -> void:
	if not _built:
		return
	_wall += delta
	if running:
		match _state:
			State.WALKING:
				_walk(minf(delta, 1.0 / 30.0))
			State.PLAYING:
				_time = _song_time()
				_play()
			State.FAILED:
				_timer -= delta
				if _timer <= 0.0:
					if _player:
						_player.revive()
					_begin_song()
			State.DONE:
				_timer -= delta
				if _timer <= 0.0:
					running = false
					_music.stop()
					finished.emit(true)
	queue_redraw()

# The character walks to its spot by the button: across first, then up or down.
func _walk(dt: float) -> void:
	var to := config.stand_pos - _pos
	var step := config.walk_speed * dt
	var dir := "left"
	if absf(to.x) > 1.0:
		_pos.x = move_toward(_pos.x, config.stand_pos.x, step)
		dir = "right" if to.x > 0.0 else "left"
	elif absf(to.y) > 1.0:
		_pos.y = move_toward(_pos.y, config.stand_pos.y, step)
		dir = "down" if to.y > 0.0 else "up"
	else:
		_pos = config.stand_pos
		if _player:
			_player.position = _to_room(_pos)
			_player.set_motion(false, "left")       # facing the button
		_begin_song()
		return
	if _player:
		_player.position = _to_room(_pos)
		_player.set_motion(true, dir)

# Where the song has got to. The player's own position only moves in steps, so
# the time since the last audio mix is added and the output delay taken off.
func _song_time() -> float:
	if not _music.playing:
		return _time
	var pos := _music.get_playback_position()
	if pos < _last_pos - 1.0:
		_loops += 1                              # the loop came round
	_last_pos = pos
	var length := float(config.loop_ticks) * _tick
	var t := float(_loops) * length + pos + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()
	return maxf(t, _time)                        # never runs backwards

func _play() -> void:
	# lines whose moment has come
	while _next_event < _events.size() and _events[_next_event]["t"] <= _time:
		var e: Dictionary = _events[_next_event]
		_next_event += 1
		var line := {"text": e["text"], "t0": e["t"], "dur": e["dur"], "kind": e["kind"], "cue": e.get("cue", -1)}
		_lines.append(line)
		if line["cue"] >= 0:
			_cues[line["cue"]]["line"] = line

	if Game.active_world == world_id and not Game.input_locked and Input.is_action_just_pressed("Interact"):
		_press()
	if _state != State.PLAYING:
		return

	# a commit that never came
	if _next_cue < _cues.size():
		var c: Dictionary = _cues[_next_cue]
		if _time > c["t"] + c["grace"]:
			_resolve(c, false, "commit timed out")
	if _state != State.PLAYING:
		return

	if _next_cue >= _cues.size() and _time >= _cues.back()["t"] + float(config.end_ticks) * _tick:
		_state = State.DONE
		_timer = 0.9
		create_tween().tween_property(_music, "volume_db", -60.0, 0.85)

# ---------------------------------------------------------------- committing
func _press() -> void:
	_press_at = _wall
	if _next_cue >= _cues.size():
		return                                   # everything is in; the button does nothing more
	var c: Dictionary = _cues[_next_cue]
	var dt: float = _time - c["t"]
	if absf(dt) <= config.tolerance:
		_resolve(c, true, "")
	elif dt > 0.0:
		_resolve(c, false, "committed too late")
	elif dt >= -c["lead"]:
		_resolve(c, false, "committed too early")    # its line was already on the screen
	else:
		_strike("nothing to commit", {})

func _resolve(c: Dictionary, ok: bool, problem: String) -> void:
	c["state"] = GOOD if ok else BAD
	_next_cue += 1
	if ok:
		_good += 1
		var text := ""
		if c["text"].ends_with("git push"):
			text = "main -> main  (%d commits pushed)" % _good
		else:
			text = "[main %s] %d files changed, +%d -%d" % [_hash(), _rng.randi_range(1, 6),
					_rng.randi_range(3, 90), _rng.randi_range(0, 30)]
		_say_under(c["line"], text, "out")
	else:
		_strike(problem, c["line"])

# One more bad commit. Too many and the run is over.
func _strike(problem: String, under: Dictionary) -> void:
	_bad += 1
	_say_under(under, "error: %s (%d/%d)" % [problem, mini(_bad, config.max_bad + 1), config.max_bad], "err")
	if _bad > config.max_bad:
		_fail()

# Puts git's answer on the line below the command it belongs to.
func _say_under(line: Dictionary, text: String, kind: String) -> void:
	var out := {"text": text, "t0": _time, "dur": 0.1, "kind": kind, "cue": -1}
	var at := _lines.find(line) if not line.is_empty() else -1
	if at >= 0:
		_lines.insert(at + 1, out)
	else:
		_lines.append(out)

func _hash() -> String:
	var s := ""
	for i in 7:
		s += "0123456789abcdef"[_rng.randi() % 16]
	return s

func _fail() -> void:
	_state = State.FAILED
	_timer = 2.8
	_music.stop()
	_lines.append({"text": "fatal: too many bad commits", "t0": _time, "dur": 0.25, "kind": "err", "cue": -1})
	_lines.append({"text": PROMPT + "git reset --hard origin/main", "t0": _time + 0.5, "dur": 0.7, "kind": "cmd", "cue": -1})
	if _player:
		_player.die()                            # the bug comes apart
	Game.say_random("commit_failed")

# ---------------------------------------------------------------- drawing
func _draw() -> void:
	if not _built or _expand < 0.999:
		return
	var up := config.button_up
	var down := config.button_down if config.button_down else up
	var tex := down if _wall - _press_at < PRESS_SHOW else up
	if tex:
		draw_texture_rect(tex, Rect2(_to_room(config.button_pos), tex.get_size() * _s), false)
	_draw_countdown()
	_draw_terminal()

# The strip under the terminal: its cells fill one a beat over the beats before
# a commit, so the last one filling means "the next beat is yours". On that
# beat they all flash together with the line.
func _draw_countdown() -> void:
	var tex := config.countdown
	if tex == null:
		return
	var size := tex.get_size()
	draw_texture_rect(tex, Rect2(_to_room(config.countdown_pos), size * _s), false)
	if _state != State.PLAYING or _next_cue >= _cues.size():
		return
	var cells := maxi(config.countdown_cells, 1)
	var c: Dictionary = _cues[_next_cue]
	var beats_in: float = (_time - (float(c["t"]) - float(cells) * _tick)) / _tick   # 0 as the first cell's beat lands
	if beats_in < 0.0:
		return
	var alpha := 1.0
	if absf(_time - float(c["t"])) <= config.tolerance and fposmod(_wall * FLASH_HZ, 1.0) >= 0.6:
		alpha = 0.3                                # the off half of the flash
	var cell_w := size.x / float(cells)
	var inset := config.countdown_inset
	for i in cells:
		var grown := clampf((beats_in - float(i)) / 0.22, 0.0, 1.0)    # each one snaps full just after its beat
		if grown <= 0.0:
			break
		var at := config.countdown_pos + Vector2(cell_w * i + inset, inset)
		var full := Vector2(cell_w - inset * 2.0, size.y - inset * 2.0)
		draw_rect(Rect2(_to_room(at), Vector2(full.x * grown, full.y) * _s), Color(config.text_color, alpha))

func _draw_terminal() -> void:
	var f: Font = config.font if config.font else ThemeDB.fallback_font
	var fs := maxi(int(config.font_size * _s), 1)
	# after a fail the clock stops, so those last lines type by plain time instead
	var now := _time + (2.8 - _timer if _state == State.FAILED else 0.0)
	if _lines.is_empty():
		# nothing typed yet: a bare prompt with its cursor
		draw_string(f, _to_room(config.text_origin), PROMPT, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, config.text_color)
		if fposmod(_wall, 0.7) < 0.35:
			_draw_cursor(f, fs, PROMPT, 0, config.text_color)
		return
	var first := maxi(_lines.size() - config.rows, 0)
	for i in range(first, _lines.size()):
		var line: Dictionary = _lines[i]
		var row := i - first
		var text: String = line["text"]
		var dur: float = line["dur"]
		var shown := text
		if dur > 0.0:
			shown = text.substr(0, int(ceil(clampf((now - float(line["t0"])) / dur, 0.0, 1.0) * text.length())))
		var col := config.error_color if line["kind"] == "err" else config.text_color
		# time to commit: the line goes green and flashes
		var lit := false
		if _state == State.PLAYING and line["cue"] >= 0:
			var c: Dictionary = _cues[line["cue"]]
			if c["state"] == PENDING and absf(_time - c["t"]) <= config.tolerance:
				lit = fposmod(_wall * FLASH_HZ, 1.0) < 0.6
		var base := config.text_origin + Vector2(0.0, row * config.line_height)
		if lit:
			draw_rect(Rect2(_to_room(Vector2(config.row_left, base.y - 48.0)),
					Vector2(config.row_right - config.row_left, 64.0) * _s), config.text_color)
			col = config.panel_color
		draw_string(f, _to_room(base), shown, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		# the cursor sits after the newest command and blinks with the beat
		if i == _lines.size() - 1 and line["kind"] == "cmd":
			if _state != State.PLAYING or fposmod(_time / _tick, 1.0) < 0.5:
				_draw_cursor(f, fs, shown, row, col)

func _draw_cursor(f: Font, fs: int, before: String, row: int, col: Color) -> void:
	var w := f.get_string_size(before, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var base := config.text_origin + Vector2(0.0, row * config.line_height)
	var at := _to_room(base + Vector2(0.0, -45.0)) + Vector2(w + 20.0 * _s, 0.0)
	draw_rect(Rect2(at, Vector2(43.0, 58.0) * _s), col)
