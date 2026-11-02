shader_type canvas_item;

// Hides the parts of a picture that have been rubbed out.
// mask: white = still there, black = erased (low resolution is fine).
uniform sampler2D mask : filter_linear, repeat_disable;

// Anything outside clip_rect (in room coordinates) is not drawn.
uniform vec4 clip_rect = vec4(-1000000.0, -1000000.0, 2000000.0, 2000000.0);  // x, y, width, height
varying vec2 room_pos;

void vertex() {
	room_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec2 inside = step(clip_rect.xy, room_pos) * step(room_pos, clip_rect.xy + clip_rect.zw);
	c.a *= texture(mask, UV).r * inside.x * inside.y;
	COLOR = c;
}
