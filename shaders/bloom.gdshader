shader_type canvas_item;

// A faint glow over the whole game, just for the feel of it: bright parts of
// the screen bleed a little light around themselves.
// Drawn last, over everything (see core/main.gd).
//
// It runs on every pixel of the screen every frame, so it takes as few
// samples as it can: the centre, four at half the radius and four at the
// full radius, turned 45 degrees from each other so they fill the circle.
uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform float strength = 0.14;        // how much glow is added
uniform float threshold = 0.72;       // only what's brighter than this glows
uniform float radius = 14.0;          // how far it spreads, in screen pixels

vec3 bright(vec3 c) {
	float l = max(c.r, max(c.g, c.b));
	return c * smoothstep(threshold, 1.0, l);
}

vec3 at(vec2 uv) {
	return bright(texture(screen_texture, uv).rgb);
}

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE * radius;
	vec2 uv = SCREEN_UV;
	vec3 base = texture(screen_texture, uv).rgb;
	vec3 glow = bright(base) * 0.16;
	vec2 i = px * 0.5 * 0.7071;
	glow += (at(uv + vec2(i.x, i.y)) + at(uv + vec2(-i.x, i.y))
			+ at(uv + vec2(i.x, -i.y)) + at(uv - i)) * 0.13;
	glow += (at(uv + vec2(px.x, 0.0)) + at(uv - vec2(px.x, 0.0))
			+ at(uv + vec2(0.0, px.y)) + at(uv - vec2(0.0, px.y))) * 0.08;
	// screen-blended, so it lifts the dark around bright things far more
	// than it brightens what's already bright
	vec3 g = clamp(glow * strength, 0.0, 1.0);
	COLOR = vec4(1.0 - (1.0 - base) * (1.0 - g), 1.0);
}
