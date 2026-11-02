extends Node2D
class_name AnalysisRoom

enum Phase { CHOOSE, EXPANDING, ARENA, HIT, DONE }

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
@export var folder_icon: Texture2D       # faded icon on the button, and the bouncing folders
@export var firewall_icon: Texture2D
@export var arena_image: Texture2D       # the picture the button fills with
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
@export var firewall_count := 8
@export var folder_count := 3
@export var icon_size := 125.0           # drawn size of bouncing icons
@export var hit_scale := 0.8             # hitbox as a fraction of the icon (lower = more forgiving)
@export var player_radius := 35.0
@export var speed_min := 220.0
@export var speed_max := 420.0
@export var safe_radius := 450.0         # icons never spawn this close to the player
@export var player_scale := 1.5
@export var blink_color := Color(1.0, 0.1, 0.1)
@export var blink_alpha := 0.6
@export var blink_time := 0.12           # seconds per on or off phase

class Btn:
	var label := ""
	var open := 0.0
	var rect := Rect2()

class Bouncer:
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var radius := 50.0
	var is_firewall := false

@onready var cam: Camera2D = $Camera2D
@onready var player: Node2D = $Player

var active := false
var _phase := Phase.CHOOSE
var _btns: Array[Btn] = []
var _bouncers: Array[Bouncer] = []
var _focus := -1
var _prev_focus := -1
var _content_bottom := 1500.0
var _expand_t := 0.0
var _a_from := Rect2()
var _arena := Rect2()
var _flash := 0.0
var _grad_tex: GradientTexture2D
var _chip_style := StyleBoxFlat.new()
var _start_pos := Vector2.ZERO

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
	_reset()
	active = true

func _reset() -> void:
	_phase = Phase.CHOOSE
	_expand_t = 0.0
	_flash = 0.0
	_focus = -1
	_prev_focus = -1
	_bouncers.clear()
	for b in _btns:
		b.open = 0.0
	player.position = Vector2(room_size.x * 0.5, player_start_y)
	_layout()
	cam.position = Vector2(room_size.x * 0.5, _view_h() * 0.5)

func _view_h() -> float:
	return get_viewport_rect().size.y / cam.zoom.y

# ---------- per frame ----------

func _process(delta: float) -> void:
	if Input.is_action_just_pressed("Interact"):
		print("analysis E | active=", active, " world=", Game.active_world, " locked=", Game.input_locked,
				" phase=", _phase, " focus=", _focus, " player=", player.position)
	if not active:
		return
	if _phase == Phase.CHOOSE:
		if Game.active_world == "analysis":
			_update_buttons(delta)
			if Input.is_action_just_pressed("Interact"):
				_try_interact()
		_clamp_player(Rect2(0.0, 0.0, room_size.x, _content_bottom))
	else:
		_layout()
		if _phase == Phase.ARENA:
			_update_arena(delta)
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
			Game.say_random("analysis_write_near")
		elif focus == 1:
			Game.say_random("analysis_later_near")
	var k := 1.0 - exp(-smoothing * delta)
	for i in _btns.size():
		_btns[i].open = lerpf(_btns[i].open, 1.0 if i == focus else 0.0, k)
	_layout()

func _try_interact() -> void:
	if _focus < 0:
		return
	var b: Btn = _btns[_focus]
	if b.open < 0.6 or not b.rect.has_point(player.position):
		return
	if _focus == 1:
		Game.say_random("analysis_later")
		_close(false)
	else:
		_begin_expand()

func _clamp_player(r: Rect2) -> void:
	player.position = Vector2(
		clampf(player.position.x, r.position.x + player_radius, r.end.x - player_radius),
		clampf(player.position.y, r.position.y + player_radius, r.end.y - player_radius))

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
	else:
		target = _arena.get_center().y
	cam.position.x = room_size.x * 0.5
	cam.position.y = lerpf(cam.position.y, target, 1.0 - exp(-camera_follow * delta))

# ---------- expanding into the game ----------

func _begin_expand() -> void:
	_phase = Phase.EXPANDING
	Game.input_locked = true
	_start_pos = player.position 
	var vh := _view_h()
	_arena = Rect2(0.0, cam.position.y - vh * 0.5, room_size.x, vh)
	_a_from = _btns[0].rect
	_expand_t = 0.0
	var t := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(self, "_expand_t", 1.0, expand_time)
	t.finished.connect(_start_arena)

func _start_arena() -> void:
	_phase = Phase.ARENA
	# Stay where the button was pressed (kept inside the arena, just in case).
	_start_pos = Vector2(
		clampf(_start_pos.x, _arena.position.x + player_radius, _arena.end.x - player_radius),
		clampf(_start_pos.y, _arena.position.y + player_radius, _arena.end.y - player_radius))
	player.position = _start_pos
	_spawn_bouncers()
	Game.input_locked = false
	Game.say_random("analysis_start")

func _spawn_bouncers() -> void:
	_bouncers.clear()
	for i in firewall_count + folder_count:
		var bn := Bouncer.new()
		bn.is_firewall = i < firewall_count
		bn.radius = icon_size * 0.5 * hit_scale
		var m := icon_size * 0.5
		for _try in 30:
			bn.pos = Vector2(
				randf_range(_arena.position.x + m, _arena.end.x - m),
				randf_range(_arena.position.y + m, _arena.end.y - m))
			if bn.pos.distance_to(_start_pos) > safe_radius:
				break
		bn.vel = Vector2.from_angle(randf() * TAU) * randf_range(speed_min, speed_max)
		_bouncers.append(bn)

func _update_arena(delta: float) -> void:
	var m := icon_size * 0.5
	for bn in _bouncers:
		bn.pos += bn.vel * delta
		if bn.pos.x < _arena.position.x + m:
			bn.pos.x = _arena.position.x + m
			bn.vel.x = absf(bn.vel.x)
		elif bn.pos.x > _arena.end.x - m:
			bn.pos.x = _arena.end.x - m
			bn.vel.x = -absf(bn.vel.x)
		if bn.pos.y < _arena.position.y + m:
			bn.pos.y = _arena.position.y + m
			bn.vel.y = absf(bn.vel.y)
		elif bn.pos.y > _arena.end.y - m:
			bn.pos.y = _arena.end.y - m
			bn.vel.y = -absf(bn.vel.y)
	_clamp_player(_arena)
	for bn in _bouncers:
		if player.position.distance_to(bn.pos) < bn.radius + player_radius:
			if bn.is_firewall:
				_hit()
			else:
				_catch()
			return

func _hit() -> void:
	_phase = Phase.HIT
	Game.input_locked = true
	Game.say_random("firewall_hit")
	for i in 2:
		_flash = blink_alpha
		await get_tree().create_timer(blink_time).timeout
		_flash = 0.0
		await get_tree().create_timer(blink_time).timeout
		if not active or _phase != Phase.HIT:
			return
	_start_arena()

func _catch() -> void:
	_phase = Phase.DONE
	Game.input_locked = true
	Game.flags["orange_unlocked"] = true
	Game.say_random("folder_caught")
	await get_tree().create_timer(1.0).timeout
	_close(true)

func _close(caught: bool) -> void:
	active = false
	Game.input_locked = false
	Game.close_analysis(caught)

# ---------- drawing ----------

func _draw() -> void:
	var f: Font = ui_font if ui_font else ThemeDB.fallback_font
	var m: Font = mono_font if mono_font else ThemeDB.fallback_font
	draw_rect(Rect2(-100, -100, room_size.x + 200, _content_bottom + 200), Color.WHITE)

	draw_string(f, Vector2(0, title_y), intro_title, HORIZONTAL_ALIGNMENT_CENTER,
			room_size.x, title_size, Color.BLACK)
	_draw_chip(m)
	draw_multiline_string(f, Vector2(60, message_y), message, HORIZONTAL_ALIGNMENT_CENTER,
			room_size.x - 120.0, message_size, -1, Color.BLACK)

	for i in _btns.size():
		_draw_button(i, _btns[i], f, m)
	for bn in _bouncers:
		_draw_bouncer(bn)
	if _flash > 0.0:
		draw_rect(_arena, Color(blink_color, _flash))
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
		draw_texture_rect(_grad_tex, r, false, Color(1, 1, 1, o))
		if arena_image and _expand_t > 0.0:
			draw_texture_rect_region(arena_image, r, _cover_region(arena_image, r),
					Color(1, 1, 1, _expand_t))
	else:
		draw_rect(r, Color(0.851, 0.851, 0.851, o))
	if i != 0 or _expand_t < 1.0:
		draw_rect(r, Color.BLACK, false, 2.0)

	var fade := 1.0 - _expand_t if i == 0 else 1.0
	var text_y := r.position.y + r.size.y * lerpf(0.5, 0.81, o if i == 0 else 0.0)
	draw_string(f, Vector2(r.position.x, text_y + button_font_size * 0.35), b.label,
			HORIZONTAL_ALIGNMENT_CENTER, r.size.x, button_font_size, Color(0, 0, 0, fade))

	if i == 0:
		var a := clampf((o - 0.4) / 0.5, 0.0, 1.0) * fade
		if a > 0.0:
			var cx := r.get_center().x
			var ih := icon_width * 0.78
			var top := r.position.y + r.size.y * 0.12
			if folder_icon:
				ih = icon_width * folder_icon.get_height() / float(folder_icon.get_width())
				draw_texture_rect(folder_icon, Rect2(cx - icon_width * 0.5, top, icon_width, ih),
						false, Color(1, 1, 1, a * 0.45))
			else:
				draw_rect(Rect2(cx - icon_width * 0.5, top, icon_width, ih), Color(1, 1, 1, a * 0.45))
			var lw := m.get_string_size(new_folder_name, HORIZONTAL_ALIGNMENT_LEFT, -1, small_size).x
			var ly := r.position.y + r.size.y * 0.54
			var col := Color(0, 0, 0, a)
			draw_string(m, Vector2(cx - lw * 0.5, ly), new_folder_name,
					HORIZONTAL_ALIGNMENT_LEFT, -1, small_size, col)
			draw_line(Vector2(cx - lw * 0.5, ly + 5), Vector2(cx + lw * 0.5, ly + 5), col, 2.0)

func _draw_bouncer(bn: Bouncer) -> void:
	var tex: Texture2D = firewall_icon if bn.is_firewall else folder_icon
	var sz := Vector2(icon_size, icon_size)
	if tex:
		sz.y = icon_size * tex.get_height() / float(tex.get_width())
		draw_texture_rect(tex, Rect2(bn.pos - sz * 0.5, sz), false)
	else:
		draw_rect(Rect2(bn.pos - sz * 0.5, sz), Color("#b5523b") if bn.is_firewall else Color("#c9c9c9"))

func _cover_region(tex: Texture2D, r: Rect2) -> Rect2:
	var ts := tex.get_size()
	var target := r.size.x / r.size.y
	if ts.x / ts.y > target:
		var w := ts.y * target
		return Rect2((ts.x - w) * 0.5, 0.0, w, ts.y)
	var h := ts.x / target
	return Rect2(0.0, (ts.y - h) * 0.5, ts.x, h)
