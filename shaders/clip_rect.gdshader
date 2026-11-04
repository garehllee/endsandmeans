shader_type canvas_item;

// Anything outside clip_rect (in room coordinates) is not drawn.
uniform vec4 clip_rect = vec4(-1000000.0, -1000000.0, 2000000.0, 2000000.0);  // x, y, width, height
varying vec2 room_pos;
varying vec4 tint;      // the node's modulate, so fading still works with a custom shader

void vertex() {
	room_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	tint = COLOR;
}

void fragment() {
	vec2 inside = step(clip_rect.xy, room_pos) * step(room_pos, clip_rect.xy + clip_rect.zw);
	COLOR = texture(TEXTURE, UV) * tint;
	COLOR.a *= inside.x * inside.y;
}
