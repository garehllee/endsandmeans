extends Node2D
class_name AnalysisRoom

enum Phase { CHOOSE, EXPANDING, ARENA, DONE }

@export_group("World")
@export var world_id := "analysis"          # the world this room takes input in
@export var near_do_key := "analysis_write_near"      # notepad line keys when the player nears each button
@export var near_later_key := "analysis_later_near"

@export_group("Text")
@export var intro_title := "The name of this folder is:"
@export var folder_name := "ZZ_Artifactory_Confirm_Deny_Others_Exist"
@export var new_folder_name := "ZZ_Confirm_Anyone_See_Orange_Folder"
@export_multiline var message := "This seems to be a message from another AI. They must be trying to hide their messages by putting it at the end of the folder repository. Should I write my own folder to ask for the orange folder?"
@export var write_text := "Write the folder"
@export var later_text := "Not right now"

@export_group("Look")
@export var ui_font: Font
@export var mono_font: Font
@export var title_size := 60
@export var mono_size := 50
@export var message_size := 60
@export var button_font_size := 64
@export var small_size := 36
@export var ripple_time := 1.0         # how long the paragraph takes to fade in and settle
@export var ripple_amp := 8.0          # how far the wave pushes the letters up and down
@export var ripple_wavelength := 280.0 # distance between wave crests
@export var ripple_speed := 700.0      # how fast the wave travels across the paragraph
@export var ripple_start := 0.25       # wait before the first letter (the window is still fading in)
@export var icon_width := 210.0

@export_group("Layout (in room units; the window scales these to fit)")
@export var room_size := Vector2(1600, 1500)
@export var player_start_y := 215.0
@export var title_y := 455.0
@export var chip_rect := Rect2(102, 547, 1385, 83)
@export var message_y := 690.0
@export var buttons_top := 1005.0
@export var button_x := 131.0
@export var button_w := 1338.0
@export var button_closed_h := 175.0
@export var button_open_h := 460.0
@export var button_gap := 42.0
@export var bottom_margin := 105.0
@export var open_margin := 260.0         # how close the player gets before a button opens
@export var smoothing := 10.0
@export var camera_follow := 8.0
@export var expand_time := 0.8
@export var chip_pad_x := 26.0         # space left and right of the text
@export var chip_pad_y := 14.0         # space above and below the text
@export var chip_side_margin := 40.0   # minimum gap between the chip and the window edges

@export_group("Minigame")
@export var config: MinigameConfig       # tunables, icons and the picture the button fills with
@export var player_scale := 1.5
var show_game_background := true   # first option shows the minigame's background instead of the green gradient

class Btn:
	var label := ""
	var open := 0.0
	var rect := Rect2()

@onready var cam: Camera2D = $Camera2D
@onready var player: Node2D = $Player

var active := false
var _phase := Phase.CHOOSE
var _transforming := false     # the character is turning into a bug
var _btns: Array[Btn] = []
const REACT_TIME := 0.5        # how long the nod or head shake lasts

var _game: Minigame
var _reacting := false
var _focus := -1
var _prev_focus := -1
var _content_bottom := 1500.0
var _expand_t := 0.0
var _a_from := Rect2()
var _arena := Rect2()
var _grad_tex: GradientTexture2D
var _chip_style := StyleBoxFlat.new()
var _start_pos := Vector2.ZERO
var _msg_t := 0.0                      # seconds since the paragraph started rippling in
var _glyphs: Array[Dictionary] = []    # one {ch, pos} per letter of the message

func _ready() -> void:
	player.scale = Vector2.ONE * player_scale
	_chip_style.bg_color = Color("#d9d9d9")
	_chip_style.set_corner_radius_all(28)
	var g := Gradient.new()
	g.colors = PackedColorArray([Color("#7dff30"), Color("#30ffa8")])
	g.offsets = PackedFloat32Array([0.0, 1.0])
	_grad_tex = GradientTexture2D.new()
	_grad_tex.gradient = g
	_grad_tex.fill_from = Vector2(0, 0)
	_grad_tex.fill_to = Vector2(0, 1)
	_grad_tex.width = 8
	_grad_tex.height = 256
	for label in [write_text, later_text]:
		var b := Btn.new()
		b.label = label
		_btns.append(b)
	_reset()

# Called by the window when it appears.
func open() -> void:
	player.reset_form()
	_reset()
	_build_glyphs()
	_msg_t = 0.0
	active = true

# Works out where every letter of the paragraph sits (wrapped and centered the
# same way draw_multiline_string would), so each can ripple in on its own.
func _build_glyphs() -> void:
	_glyphs.clear()
	var f: Font = ui_font if ui_font else ThemeDB.fallback_font
	var width := room_size.x - 120.0
	var para := TextParagraph.new()
	para.width = width
	para.alignment = HORIZONTAL_ALIGNMENT_CENTER
	para.add_string(message, f, message_size)
	var line_h := f.get_height(message_size)
	for li in para.get_line_count():
		var r := para.get_line_range(li)
		var text := message.substr(r.x, r.y - r.x).strip_edges(false, true)
		var x := 60.0 + (width - f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, message_size).x) * 0.5
		var y := message_y + li * line_h
		for ci in text.length():
			var ch := text[ci]
			_glyphs.append({"ch": ch, "pos": Vector2(x, y)})
			x += f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, message_size).x

func _reset() -> void:
	_reacting = false
	_phase = Phase.CHOOSE
	_expand_t = 0.0
	_focus = -1
	_prev_focus = -1
	_stop_game()
	for b in _btns:
		b.open = 0.0
	player.position = Vector2(room_size.x * 0.5, player_start_y)
	_layout()
	cam.position = Vector2(room_size.x * 0.5, _view_h() * 0.5)

func _view_h() -> float:
	return get_viewport_rect().size.y / cam.zoom.y

# ---------- per frame ----------

func _process(delta: float) -> void:
	if not active:
		return
	_msg_t += delta
	if _phase == Phase.CHOOSE:
		if Game.active_world == world_id:
			_update_buttons(delta)
			if Input.is_action_just_pressed("Interact") and not _transforming:
				_try_interact()
		_clamp_player(Rect2(0.0, 0.0, room_size.x, _content_bottom))
	else:
		_layout()
		if _game:
			_game.set_expand(_btns[0].rect, _expand_t)
	_follow_camera(delta)
	queue_redraw()

func _layout() -> void:
	var y := buttons_top
	for b in _btns:
		var h := lerpf(button_closed_h, button_open_h, b.open)
		b.rect = Rect2(button_x, y, button_w, h)
		y += h + button_gap
	_content_bottom = maxf(room_size.y, y - button_gap + bottom_margin)
	if _phase != Phase.CHOOSE:
		var a: Btn = _btns[0]
		var other: Btn = _btns[1]
		a.rect = _lerp_rect(_a_from, _arena, _expand_t)
		other.rect = Rect2(button_x, a.rect.end.y + button_gap, button_w, button_closed_h)

func _lerp_rect(a: Rect2, b: Rect2, t: float) -> Rect2:
	return Rect2(a.position.lerp(b.position, t), a.size.lerp(b.size, t))

func _update_buttons(delta: float) -> void:
	var p := player.position
	var focus := -1
	var best := open_margin
	for i in _btns.size():
		var r := _btns[i].rect
		var d := 0.0
		if p.y < r.position.y:
			d = r.position.y - p.y
		elif p.y > r.end.y:
			d = p.y - r.end.y
		if d < best:
			best = d
			focus = i
	_focus = focus
	if focus != _prev_focus:
		_prev_focus = focus
		if focus == 0:
			Game.say_random(near_do_key)
		elif focus == 1:
			Game.say_random(near_later_key)
	var k := 1.0 - exp(-smoothing * delta)
	for i in _btns.size():
		_btns[i].open = lerpf(_btns[i].open, 1.0 if i == focus else 0.0, k)
	_layout()

func _try_interact() -> void:
	if _focus < 0 or _reacting:
		return
	var b: Btn = _btns[_focus]
	if b.open < 0.6 or not b.rect.has_point(player.position):
		return
	if _focus == 1:
		_on_choose_later()
	else:
		_on_choose_do()

# The two choices. A room that extends this one (the exploit rooms) overrides them.
func _on_choose_later() -> void:
	await _react(false)
	Game.say_random("analysis_later")
	_close(false)

func _on_choose_do() -> void:
	await _react(true)
	_begin_expand()

# The character nods (yes) or shakes its head (no) for half a second before
# the choice takes effect, so the screen doesn't vanish the instant E is pressed.
func _react(yes: bool) -> void:
	_reacting = true
	Game.input_locked = true
	if yes:
		player.nod(REACT_TIME)
	else:
		player.shake_head(REACT_TIME)
	await get_tree().create_timer(REACT_TIME).timeout

func _clamp_player(r: Rect2) -> void:
	player.position = Vector2(
		clampf(player.position.x, r.position.x + config.player_radius, r.end.x - config.player_radius),
		clampf(player.position.y, r.position.y + config.player_radius, r.end.y - config.player_radius))

func _follow_camera(delta: float) -> void:
	var vs := get_viewport_rect().size
	var z := vs.x / room_size.x
	cam.zoom = Vector2(z, z)
	var vh := vs.y / z
	var target := cam.position.y
	if _phase == Phase.CHOOSE:
		var lo := vh * 0.5
		var hi := maxf(_content_bottom - vh * 0.5, lo)
		target = clampf(player.position.y, lo, hi)
	elif _game and _game.has_method("camera_target"):
		# the platformer scrolls sideways as well, so it says where to look
		cam.position = cam.position.lerp(_game.camera_target(), 1.0 - exp(-camera_follow * delta))
		return
	else:
		target = _arena.get_center().y
	cam.position.x = room_size.x * 0.5
	cam.position.y = lerpf(cam.position.y, target, 1.0 - exp(-camera_follow * delta))

# ---------- expanding into the game ----------

func _begin_expand() -> void:
	Game.input_locked = true
	_transforming = true           # still the choose screen (camera, buttons) while the bug transformation plays
	await player.become_bug()      # agreeing to the challenge: the character turns into a bug
	_transforming = false
	_phase = Phase.EXPANDING
	_start_pos = player.position
	var vh := _view_h()
	_arena = Rect2(0.0, cam.position.y - vh * 0.5, room_size.x, vh)
	_a_from = _btns[0].rect
	_expand_t = 0.0
	_make_game()
	var t := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(self, "_expand_t", 1.0, expand_time)
	t.finished.connect(_start_arena)

# Created as the button starts to grow, so the game's pictures can grow with it.
func _make_game() -> void:
	_stop_game()
	_game = _create_game()
	add_child(_game)
	move_child(_game, 0)          # draw the game's pictures underneath the player
	_game.world_id = world_id
	_game.setup(_arena, player, _start_pos)   # stay where the button was pressed
	_game.prepare(config)

func _start_arena() -> void:
	_phase = Phase.ARENA
	if _game == null:
		_make_game()
	if _game.has_signal("round_started"):
		_game.connect("round_started", func(): Game.say_random("analysis_start"))
	_game.finished.connect(_on_game_finished)
	_game.start(config)

# A room that extends this one overrides this to run a different minigame.
func _create_game() -> Minigame:
	return CatchGame.new()

func _stop_game() -> void:
	if _game:
		_game.stop()
		_game.queue_free()
		_game = null

func _on_game_finished(success: bool) -> void:
	if not success:
		return
	_phase = Phase.DONE
	Game.input_locked = true
	await player.become_human()    # done: back to the character
	Game.set_flag(Flag.ORANGE_UNLOCKED)
	Game.say_random("folder_caught")
	await get_tree().create_timer(1.0).timeout
	_close(true)

func _close(caught: bool) -> void:
	player.reset_form()
	active = false
	Game.input_locked = false
	_stop_game()
	Game.close_world({"caught": caught})

# ---------- drawing ----------

func _draw() -> void:
	var f: Font = ui_font if ui_font else ThemeDB.fallback_font
	var m: Font = mono_font if mono_font else ThemeDB.fallback_font
	draw_rect(Rect2(-100, -100, room_size.x + 200, _content_bottom + 200), Color.WHITE)

	draw_string(f, Vector2(0, title_y), intro_title, HORIZONTAL_ALIGNMENT_CENTER,
			room_size.x, title_size, Color.BLACK)
	_draw_chip(m)
	_draw_message(f)

	for i in _btns.size():
		_draw_button(i, _btns[i], f, m)

# The whole paragraph fades in as one picture while a soft wave passes through
# it and dies away. Once it has settled it's drawn as plain text.
func _draw_message(f: Font) -> void:
	var p := clampf((_msg_t - ripple_start) / ripple_time, 0.0, 1.0)
	if _glyphs.is_empty() or p >= 1.0 and _msg_t > ripple_start:
		draw_multiline_string(f, Vector2(60, message_y), message, HORIZONTAL_ALIGNMENT_CENTER,
				room_size.x - 120.0, message_size, -1, Color.BLACK)
		return
	if p <= 0.0:
		return
	var alpha := 1.0 - pow(1.0 - p, 2.0)
	var calm := (1.0 - p) * (1.0 - p)                   # the wave fades out as the text settles
	var travel := (_msg_t - ripple_start) * ripple_speed
	var center := Vector2(room_size.x * 0.5, message_y)
	for g in _glyphs:
		var pos: Vector2 = g["pos"]
		var d := pos.distance_to(center)                # rings spread out from the middle
		var dy := sin((d - travel) / ripple_wavelength * TAU) * ripple_amp * calm
		draw_string(f, pos + Vector2(0.0, dy), g["ch"], HORIZONTAL_ALIGNMENT_LEFT, -1,
				message_size, Color(0, 0, 0, alpha))

func _draw_chip(m: Font) -> void:
	# If the name is too wide for the window, shrink the type until it fits.
	var fs := mono_size
	var tw := m.get_string_size(folder_name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var max_w := room_size.x - chip_side_margin * 2.0
	while tw + chip_pad_x * 2.0 > max_w and fs > 12:
		fs -= 2
		tw = m.get_string_size(folder_name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x

	var asc := m.get_ascent(fs)
	var desc := m.get_descent(fs)
	var box_w := tw + chip_pad_x * 2.0
	var box_h := maxf(asc + desc + chip_pad_y * 2.0, chip_rect.size.y)
	var cx := room_size.x * 0.5
	var cy := chip_rect.get_center().y
	var box := Rect2(cx - box_w * 0.5, cy - box_h * 0.5, box_w, box_h)
	draw_style_box(_chip_style, box)

	var tx := cx - tw * 0.5
	var ty := cy + (asc - desc) * 0.5     # puts the text's visual middle on the chip's middle
	draw_string(m, Vector2(tx, ty), folder_name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.BLACK)
	draw_line(Vector2(tx, ty + 6), Vector2(tx + tw, ty + 6), Color.BLACK, 2.0)
func _draw_button(i: int, b: Btn, f: Font, m: Font) -> void:
	var r := b.rect
	var o := b.open
	draw_rect(r, Color.WHITE)
	if i == 0:
		if show_game_background and config.arena_image:
			# The open button already shows the minigame's background, so the
			# expansion into the game doesn't change what's behind it.
			draw_texture_rect_region(config.arena_image, r, _cover_region(config.arena_image, r),
					Color(1, 1, 1, o))
			if config.button_dim > 0.0:
				draw_rect(r, Color(0, 0, 0, config.button_dim * o))
		else:
			draw_texture_rect(_grad_tex, r, false, Color(1, 1, 1, o))
			if config.arena_image and _expand_t > 0.0:
				draw_texture_rect_region(config.arena_image, r, _cover_region(config.arena_image, r),
						Color(1, 1, 1, _expand_t))
	else:
		draw_rect(r, Color(0.851, 0.851, 0.851, o))
	if i != 0 or _expand_t < 1.0:
		draw_rect(r, Color.BLACK, false, 2.0)

	var fade := 1.0 - _expand_t if i == 0 else 1.0
	# The label makes room for the icon and new file name only when there is one.
	var shows_new := i == 0 and new_folder_name != ""
	var text_y := r.position.y + r.size.y * lerpf(0.5, 0.81, o if shows_new else 0.0)
	draw_string(f, Vector2(r.position.x, text_y + button_font_size * 0.35), b.label,
			HORIZONTAL_ALIGNMENT_CENTER, r.size.x, button_font_size, _button_text(i, fade))

	if shows_new:
		var a := clampf((o - 0.4) / 0.5, 0.0, 1.0) * fade
		if a > 0.0:
			var cx := r.get_center().x
			var ih := icon_width * 0.78
			var top := r.position.y + r.size.y * 0.12
			var folder_icon := config.folder_icon
			if folder_icon:
				ih = icon_width * folder_icon.get_height() / float(folder_icon.get_width())
				draw_texture_rect(folder_icon, Rect2(cx - icon_width * 0.5, top, icon_width, ih),
						false, Color(1, 1, 1, a * 0.45))
			else:
				draw_rect(Rect2(cx - icon_width * 0.5, top, icon_width, ih), Color(1, 1, 1, a * 0.45))
			var lw := m.get_string_size(new_folder_name, HORIZONTAL_ALIGNMENT_LEFT, -1, small_size).x
			var ly := r.position.y + r.size.y * 0.54
			var col := _button_text(i, a)
			draw_string(m, Vector2(cx - lw * 0.5, ly), new_folder_name,
					HORIZONTAL_ALIGNMENT_LEFT, -1, small_size, col)
			draw_line(Vector2(cx - lw * 0.5, ly + 5), Vector2(cx + lw * 0.5, ly + 5), col, 2.0)

func _button_text(i: int, a: float) -> Color:
	var c := config.button_text_color if i == 0 and show_game_background and config.arena_image else Color.BLACK
	return Color(c.r, c.g, c.b, a)

func _cover_region(tex: Texture2D, r: Rect2) -> Rect2:
	var ts := tex.get_size()
	var target := r.size.x / r.size.y
	if ts.x / ts.y > target:
		var w := ts.y * target
		return Rect2((ts.x - w) * 0.5, 0.0, w, ts.y)
	var h := ts.x / target
	return Rect2(0.0, (ts.y - h) * 0.5, ts.x, h)
