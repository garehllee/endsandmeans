shader_type canvas_item;

// A faint glow over the whole game, just for the feel of it: bright parts of
// the screen bleed a little light around themselves.
// Drawn last, over everything (see core/main.gd).
uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform float strength = 0.14;        // how much glow is added
uniform float threshold = 0.72;       // only what's brighter than this glows
uniform float radius = 14.0;          // how far it spreads, in screen pixels

vec3 bright(vec2 uv) {
	vec3 c = texture(screen_texture, uv).rgb;
	float l = max(c.r, max(c.g, c.b));
	return c * smoothstep(threshold, 1.0, l);
}

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE * radius;
	vec3 base = texture(screen_texture, SCREEN_UV).rgb;
	// two rings of samples around the pixel, the inner one weighted more
	vec3 glow = bright(SCREEN_UV) * 0.16;
	for (int i = 0; i < 8; i++) {
		float a = float(i) * 0.785398 + 0.3927;
		vec2 d = vec2(cos(a), sin(a));
		glow += bright(SCREEN_UV + d * px * 0.5) * 0.065;
		glow += bright(SCREEN_UV + d * px) * 0.04;
	}
	// screen-blended, so it lifts the dark around bright things far more
	// than it brightens what's already bright
	vec3 g = clamp(glow * strength, 0.0, 1.0);
	COLOR = vec4(1.0 - (1.0 - base) * (1.0 - g), 1.0);
}
