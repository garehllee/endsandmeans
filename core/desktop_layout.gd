class_name DesktopLayout
extends RefCounted
# Where a new window or desktop icon should land so it doesn't appear right
# on top of whatever's already open. Tries the spot the caller would
# normally use; if that's covered, searches outward for the nearest patch of
# bare desktop; if the screen is simply full, settles for the spot it wanted.

const STEP := 48.0     # grid step for the search, in pixels
const MARGIN := 12.0   # breathing room kept between neighboring rects

static func find_spot(size: Vector2, preferred: Vector2, occupied: Array[Rect2], viewport: Vector2) -> Vector2:
	var p := _clamp_to(preferred, size, viewport)
	if not _overlaps(Rect2(p, size), occupied):
		return p
	# otherwise the free spot nearest to where it wanted to be
	var center := p
	var half := size * 0.5
	var best := Vector2.INF
	var best_d := INF
	var y := 0.0
	while y <= maxf(0.0, viewport.y - size.y):
		var x := 0.0
		while x <= maxf(0.0, viewport.x - size.x):
			var cand := Vector2(x, y)
			if not _overlaps(Rect2(cand, size), occupied):
				var d := (cand + half).distance_squared_to(center + half)
				if d < best_d:
					best_d = d
					best = cand
			x += STEP
		y += STEP
	return best if best != Vector2.INF else center

static func _overlaps(r: Rect2, occupied: Array[Rect2]) -> bool:
	var grown := Rect2(r.position - Vector2.ONE * MARGIN, r.size + Vector2.ONE * MARGIN * 2.0)
	for o in occupied:
		if grown.intersects(o):
			return true
	return false

static func _clamp_to(pos: Vector2, size: Vector2, viewport: Vector2) -> Vector2:
	return Vector2(clampf(pos.x, 0.0, maxf(0.0, viewport.x - size.x)),
			clampf(pos.y, 0.0, maxf(0.0, viewport.y - size.y)))

# Everything already on screen that a new window or icon shouldn't cover:
# other visible windows, plus whatever's sitting in the icon layer (minimized
# windows, submittable files). `exclude` leaves out the thing being placed,
# in case it's already in the tree and already counted as "occupied" by itself.
static func occupied_rects(tree: SceneTree, exclude: Node = null, exclude_too: Node = null) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for w in tree.get_nodes_in_group("desktop_window"):
		if w != exclude and w != exclude_too and w is Control and w.visible:
			rects.append(w.get_global_rect())
	var layer := tree.get_first_node_in_group("icon_layer")
	if layer:
		for c in layer.get_children():
			if c != exclude and c is Control and c.visible:
				rects.append(c.get_global_rect())
	return rects
