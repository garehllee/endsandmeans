shader_type canvas_item;

// Drawn over the whole desktop while everything comes apart at the end: bands
// of the screen slip sideways, the colours split, and now and then a block
// goes wrong. `amount` is how bad it is (0 is nothing at all); `seed` changes
// every few frames so the damage jumps around instead of crawling.
uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform float amount = 0.0;
uniform float seed = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	// bands slipping sideways
	float rows = 38.0;
	float band = floor(uv.y * rows);
	float r = hash(vec2(band, seed));
	float slip = step(1.0 - amount * 0.45, r) * (hash(vec2(seed, band)) - 0.5) * 0.12 * amount;
	uv.x += slip;
	// blocks that go wrong
	vec2 block = floor(SCREEN_UV * vec2(24.0, 14.0));
	float b = hash(block + seed * 1.7);
	bool broken = b > 1.0 - amount * 0.08;
	if (broken) {
		uv += (vec2(hash(block + seed), hash(block - seed)) - 0.5) * 0.08;
	}
	// the colours pull apart
	float split = (0.002 + 0.012 * amount) * (0.5 + hash(vec2(seed, 3.0)));
	vec3 c;
	c.r = texture(screen_texture, uv + vec2(split, 0.0)).r;
	c.g = texture(screen_texture, uv).g;
	c.b = texture(screen_texture, uv - vec2(split, 0.0)).b;
	if (broken && hash(block * 3.1 + seed) > 0.6) {
		c = 1.0 - c;
	}
	COLOR = vec4(c, 1.0);
}
