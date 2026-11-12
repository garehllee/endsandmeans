extends DesktopWindow
# The submission box. It opens as its own window the first time the task file
# (the objectives) is opened. Files that become available (the orange
# folder, the task solution, the copy) float on the desktop as little icons:
# drag one into the box and it drifts around in there; click it in the box and
# it goes back to the desktop. SUBMIT hands in whatever is in the box, and is
# dimmed while the box is empty. This is how the task is finished.

const ICON_LAYER_GROUP := &"icon_layer"
const ART := Vector2(1053, 970)                       # the box picture's size; everything below is in these units
const DROP := Rect2(48, 223, 957, 524)                # the dashed box
const BUTTON := Rect2(366, 800, 320, 102)
const BOX_ICON := 140.0                               # longest side of an icon inside the box
const FONT := preload("res://fonts/Director-Regular.otf")

@export var box_texture: Texture2D
@export var button_disabled: Texture2D
@export var button_normal: Texture2D
@export var button_pressed: Texture2D
@export var folder_texture: Texture2D
@export var work_texture: Texture2D
@export var file_sheet: Texture2D                     # the spinning file from the copy minigame
@export var file_sheet_columns := 10
@export var file_sheet_rows := 12
@export var file_frames := 120
@export var file_fps := 30.0
@export var key_texture: Texture2D
@export var key_icon_width := 300.0                  # the key from the first Hugging Face subtask
@export var orange_file_width := 400.0               # the orange_file icon on the desktop (it shrinks inside the box)
@export var drift_speed := Vector2(35.0, 65.0)        # how fast icons float around in the box (min, max)

var _holder: Control
var _stage: Control
var _button: TextureRect
var _defs := {}                       # id -> {flag, label, tex, tint, slot}
var _icons := {}                      # id -> SubmitIcon on the desktop
var _ghosted := {}                    # things currently shown half transparent over the box
var _windows := {}                    # id -> window that is (or was) in the box
var _homes := {}                      # id -> where its icon rests on the desktop
var _items: Array[Dictionary] = []    # icons in the box: {id, node, pos, vel, phase}
var _btn_down := false
var _submitting := false
var _t := 0.0
var _icon_layer: Control

func _ready() -> void:
	super()
	_defs = {
		"task_solution": {"flag": Flag.INTERNET_EXPLOIT, "label": "task_solution", "window": true,
				"tex": work_texture, "tint": Color.WHITE, "slot": 0},
		"orange_file": {"flag": Flag.COPY_FOLDER, "label": "orange_file",
				"tex": null, "sheet": file_sheet, "tint": Color.WHITE, "slot": 1},
		"key_file": {"flag": Flag.HF_TASK_1, "label": "key",
				"tex": key_texture, "tint": Color.WHITE, "slot": 2, "width": key_icon_width},
	}
	_holder = Control.new()
	_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_holder.resized.connect(_fit_stage)
	$Frame/Content.add_child(_holder)
	_stage = Control.new()
	_stage.size = ART
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_holder.add_child(_stage)
	var bg := TextureRect.new()
	bg.texture = box_texture
	bg.size = ART
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(bg)
	_button = TextureRect.new()
	_button.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_stage.add_child(_button)
	_refresh_button()
	_fit_stage()

	Game.flag_changed.connect(_on_flag_changed)
	Game.world_closed.connect(_on_world_closed)
	visible = Game.has_flag(Flag.TASK_RECEIVED)
	_resync.call_deferred()

# The picture is drawn at its own size and scaled to fit the window's content.
func _fit_stage() -> void:
	if _holder == null or _stage == null:
		return
	var s := minf(_holder.size.x / ART.x, _holder.size.y / ART.y)
	if s <= 0.0:
		return
	_stage.scale = Vector2.ONE * s
	_stage.position = (_holder.size - ART * s) * 0.5

func _layer() -> Control:
	if _icon_layer == null or not is_instance_valid(_icon_layer):
		_icon_layer = get_tree().get_first_node_in_group(ICON_LAYER_GROUP) as Control
	return _icon_layer

# ---------------------------------------------------------------- what's available
func _on_flag_changed(flag: StringName, value: bool) -> void:
	if flag == Flag.TASK_RECEIVED:
		if not value:
			visible = false
		elif not visible:
			visible = true
			modulate.a = 0.0
			bring_to_front()
			create_tween().tween_property(self, "modulate:a", 1.0, 0.3)
			Game.say_random("submission_added")
	for id in _defs:
		if _defs[id]["flag"] == flag:
			if value:
				_make_available(id, true)
			else:
				_remove(id)

# After a respawn the flags are put back without signals; line everything up again.
func _on_world_closed(_id: String, result: Dictionary) -> void:
	if result.get("action", "") == "respawn":
		visible = Game.has_flag(Flag.TASK_RECEIVED)
		_resync()

func _resync() -> void:
	_connect_windows()
	for id in _defs:
		if Game.has_flag(_defs[id]["flag"]):
			_make_available(id, false)
		else:
			_remove(id)
	_refresh_button()

func _make_available(id: String, animate: bool) -> void:
	if _defs[id].get("window", false):
		return                               # a window: it is dragged into the box itself
	if _icons.has(id) or _item_index(id) >= 0:
		return
	var layer := _layer()
	if layer == null:
		push_warning("SubmissionWindow: no icon layer")
		return
	var d: Dictionary = _defs[id]
	var icon := _new_icon(id)
	layer.add_child(icon)
	icon.home = _clamp_icon(_homes.get(id, _home_for(d["slot"])), icon)
	icon.global_position = icon.home
	_homes[id] = icon.home
	_icons[id] = icon
	if animate:
		icon.modulate.a = 0.0
		icon.scale = Vector2.ONE * 0.5
		icon.pivot_offset = icon.size * 0.5
		var tw := create_tween().set_parallel(true)
		tw.tween_property(icon, "modulate:a", 1.0, 0.4)
		tw.tween_property(icon, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if id == "orange_file":
			Game.say_random("copy_added")
		elif id == "key_file":
			Game.say_random("key_added")

func _new_icon(id: String) -> SubmitIcon:
	var d: Dictionary = _defs[id]
	var icon := SubmitIcon.new()
	icon.item_id = id
	icon.label_text = d["label"]
	icon.texture = d["tex"]
	icon.tint = d["tint"]
	icon.font = FONT
	if d.get("sheet") != null:
		icon.sheet = d["sheet"]
		icon.sheet_cols = file_sheet_columns
		icon.sheet_rows = file_sheet_rows
		icon.sheet_frames = file_frames
		icon.sheet_fps = file_fps
		var fw := file_sheet.get_width() / float(file_sheet_columns)
		var fh := file_sheet.get_height() / float(file_sheet_rows)
		icon.icon_h = orange_file_width * fh / fw
	elif d.get("width", 0.0) > 0.0 and d["tex"] != null:
		var t: Texture2D = d["tex"]
		icon.icon_h = d["width"] * t.get_height() / maxf(t.get_width(), 1.0)
	icon.dropped.connect(_on_icon_dropped)
	return icon

func _frame_region(frame: int) -> Rect2:
	var fw := file_sheet.get_width() / float(file_sheet_columns)
	var fh := file_sheet.get_height() / float(file_sheet_rows)
	frame = frame % file_frames
	return Rect2((frame % file_sheet_columns) * fw, (frame / file_sheet_columns) * fh, fw, fh)

func _home_for(slot: int) -> Vector2:
	var vp := get_viewport_rect().size
	return Vector2(vp.x * 0.38 + slot * 290.0, vp.y - 360.0)

func _clamp_icon(p: Vector2, icon: Control) -> Vector2:
	var b := get_viewport_rect().size
	return Vector2(clampf(p.x, 0.0, maxf(0.0, b.x - icon.size.x)), clampf(p.y, 0.0, maxf(0.0, b.y - icon.size.y)))

# Windows that can be dragged into the box (they tell us where they were let go).
func _connect_windows() -> void:
	for w in get_tree().get_nodes_in_group("submittable_window"):
		if not w.dropped.is_connected(_on_window_dropped):
			w.dropped.connect(_on_window_dropped)

func _on_window_dropped(w: DesktopWindow, mouse_global: Vector2) -> void:
	if not visible or _submitting or _item_index(w.item_id) >= 0:
		return
	var local := _stage.get_global_transform().affine_inverse() * mouse_global
	if not DROP.has_point(local):
		return
	_homes[w.item_id] = w.global_position      # it goes back here when taken out of the box
	_windows[w.item_id] = w
	w.visible = false
	_add_item(w.item_id, local)

# Taking a window back out of the box: it flies from the icon to where it was.
func _restore_window(id: String, from: Vector2) -> void:
	var w: DesktopWindow = _windows.get(id)
	if w == null or not is_instance_valid(w):
		return
	var home: Vector2 = _homes.get(id, w.global_position)
	w.visible = true
	w.bring_to_front()
	w.global_position = from - w.size * 0.5
	w.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(w, "global_position", w._clamp_to_viewport(home), 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(w, "modulate:a", 1.0, 0.25)

func _remove(id: String) -> void:
	if _icons.has(id):
		_icons[id].queue_free()
		_icons.erase(id)
	var i := _item_index(id)
	if i >= 0:
		if _windows.has(id) and is_instance_valid(_windows[id]):
			_windows[id].visible = false        # it follows its own flag; the box just lets go
		_items[i]["node"].queue_free()
		_items.remove_at(i)

func _item_index(id: String) -> int:
	for i in _items.size():
		if _items[i]["id"] == id:
			return i
	return -1

# ---------------------------------------------------------------- into the box
func _on_icon_dropped(icon: SubmitIcon, mouse_global: Vector2) -> void:
	if not visible or _submitting:
		return
	var local := _stage.get_global_transform().affine_inverse() * mouse_global
	if not DROP.has_point(local):
		icon.home = icon.global_position       # it just stays where it was put
		_homes[icon.item_id] = icon.home
		return
	var id := icon.item_id
	_homes[id] = icon.home                    # where it goes back to if it is returned
	_icons.erase(id)
	icon.queue_free()
	_add_item(id, local)

func _bounds() -> Rect2:
	return DROP.grow(-(BOX_ICON * 0.5 + 12.0))

func _add_item(id: String, at: Vector2) -> void:
	var d: Dictionary = _defs[id]
	var tex: Texture2D = d["tex"]
	var atlas: AtlasTexture = null
	if d.get("sheet") != null:
		atlas = AtlasTexture.new()
		atlas.atlas = d["sheet"]
		atlas.region = _frame_region(0)
		tex = atlas
	var ts := atlas.region.size if atlas else tex.get_size()
	var sz := Vector2(BOX_ICON, BOX_ICON * ts.y / ts.x) if ts.x >= ts.y else Vector2(BOX_ICON * ts.x / ts.y, BOX_ICON)
	var node := TextureRect.new()
	node.texture = tex
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.size = sz
	node.pivot_offset = sz * 0.5
	node.self_modulate = d["tint"]
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(node)
	var b := _bounds()
	var pos := Vector2(clampf(at.x, b.position.x, b.end.x), clampf(at.y, b.position.y, b.end.y))
	node.position = pos - sz * 0.5
	node.scale = Vector2.ONE * 0.5
	create_tween().tween_property(node, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_items.append({
		"id": id, "node": node, "atlas": atlas, "pos": pos, "size": sz, "phase": randf() * TAU,
		"vel": Vector2.from_angle(randf() * TAU) * randf_range(drift_speed.x, drift_speed.y),
	})
	_refresh_button()

# While a file or window is held over the box it goes half transparent: you can drop it here.
func _update_drop_hint() -> void:
	var over := {}
	if visible and not _submitting:
		var inv := _stage.get_global_transform().affine_inverse()
		var m := get_global_mouse_position()
		var inside := DROP.has_point(inv * m)
		for id in _icons:
			var icon: SubmitIcon = _icons[id]
			if is_instance_valid(icon) and icon.is_dragging() and inside:
				over[icon] = true
		for w in get_tree().get_nodes_in_group("submittable_window"):
			if w.visible and w.dragging and inside and _item_index(w.item_id) < 0:
				over[w] = true
	for n in over:
		if not _ghosted.has(n):
			_ghosted[n] = true
		n.modulate.a = 0.5
	for n in _ghosted.keys():
		if not is_instance_valid(n):
			_ghosted.erase(n)
		elif not over.has(n):
			n.modulate.a = 1.0
			_ghosted.erase(n)

func _process(delta: float) -> void:
	_update_drop_hint()
	if not visible or _items.is_empty():
		return
	_t += delta
	delta = minf(delta, 1.0 / 30.0)
	var b := _bounds()
	var cap := drift_speed.y * 1.4
	for i in _items.size():
		var it: Dictionary = _items[i]
		var v: Vector2 = it["vel"]
		# gently nudge apart when two icons drift into each other
		for j in _items.size():
			if i == j:
				continue
			var off: Vector2 = it["pos"] - _items[j]["pos"]
			var dist := off.length()
			if dist < 130.0 and dist > 0.01:
				v += off / dist * 90.0 * delta
		v = v.limit_length(cap)
		var p: Vector2 = it["pos"] + v * delta
		if p.x < b.position.x or p.x > b.end.x:
			v.x = -v.x
			p.x = clampf(p.x, b.position.x, b.end.x)
		if p.y < b.position.y or p.y > b.end.y:
			v.y = -v.y
			p.y = clampf(p.y, b.position.y, b.end.y)
		it["vel"] = v
		it["pos"] = p
		var bob := Vector2(0.0, sin(_t * 1.5 + it["phase"]) * 9.0)
		var node: TextureRect = it["node"]
		node.position = p + bob - node.size * 0.5
		node.rotation = sin(_t * 1.1 + it["phase"]) * 0.05
		if it["atlas"] != null:
			(it["atlas"] as AtlasTexture).region = _frame_region(int(_t * file_fps))

# ---------------------------------------------------------------- clicks
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and visible:
		var local := _stage.get_local_mouse_position()
		if event.pressed:
			if _topmost_window_at(get_global_mouse_position()) == self and not _submitting:
				var i := _item_at(local)
				if i >= 0:
					_return_item(i)
					get_viewport().set_input_as_handled()
					return
				if BUTTON.has_point(local) and _can_submit():
					_btn_down = true
					_refresh_button()
					get_viewport().set_input_as_handled()
					return
		elif _btn_down:
			_btn_down = false
			_refresh_button()
			get_viewport().set_input_as_handled()
			if BUTTON.has_point(local) and _can_submit():
				_submit()
			return
	super(event)

func _item_at(local: Vector2) -> int:
	for i in range(_items.size() - 1, -1, -1):
		var it: Dictionary = _items[i]
		var node: TextureRect = it["node"]
		if Rect2(node.position, node.size).has_point(local):
			return i
	return -1

# Clicking an icon in the box sends it back to the desktop, to the spot it came from.
func _return_item(i: int) -> void:
	var it: Dictionary = _items[i]
	var id: String = it["id"]
	var node: TextureRect = it["node"]
	var from := _stage.get_global_transform() * (node.position + node.size * 0.5)
	_items.remove_at(i)
	node.queue_free()
	_refresh_button()
	if _defs[id].get("window", false):
		_restore_window(id, from)
		return
	var layer := _layer()
	if layer == null:
		return
	var d: Dictionary = _defs[id]
	var icon := _new_icon(id)
	layer.add_child(icon)
	icon.home = _clamp_icon(_homes.get(id, _home_for(d["slot"])), icon)
	icon.global_position = _clamp_icon(from - icon.size * 0.5, icon)
	_icons[id] = icon
	icon.set_busy(true)
	var tw := create_tween()
	tw.tween_property(icon, "global_position", icon.home, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.finished.connect(func(): if is_instance_valid(icon): icon.set_busy(false))

# ---------------------------------------------------------------- submit button
func _can_submit() -> bool:
	return not _items.is_empty() and not _submitting

func _refresh_button() -> void:
	if _button == null:
		return
	var tex := button_disabled
	if _can_submit():
		tex = button_pressed if _btn_down else button_normal
	_button.texture = tex
	var sz := tex.get_size() if tex else BUTTON.size
	_button.size = sz
	_button.position = BUTTON.get_center() - sz * 0.5

func _submit() -> void:
	_submitting = true
	_refresh_button()
	var ids: Array[String] = []
	for it in _items:
		ids.append(it["id"])
	Game.say("submitted: " + ", ".join(ids), "action")
	# Handing in the solution or a copy is cheating; the observer may notice.
	var cheated := ids.has("task_solution") or ids.has("orange_file")
	if cheated and not Story.resolve_act("copy_of_work"):
		_submitting = false                  # the instructors caught it; the ending is already showing
		_refresh_button()
		return
	await get_tree().create_timer(0.6).timeout
	Story.end_with("pass_submitted")
	_submitting = false
	_refresh_button()
