shader_type canvas_item;

// Drawn over the whole desktop while everything comes apart at the end. It
// looks like a graphics card failing: big ragged chunks of the screen go
// wrong, each in its own way --
//   rows smeared sideways, little blocks shuffled out of place, rows doubled
//   up, coloured speckle, pixel sorting (bright pixels dragged into streaks,
//   down or across), crushed colour with the channels swapped, and mosaic --
// while everything outside the chunks is left alone apart from the odd thin
// streak. The chunks are shapes from a noise field, cut on a coarse pixel
// grid so their edges are stepped and ragged rather than straight.
//
// `amount` is how bad it is (0 is nothing). `seed` changes every frame or
// two (the fine noise); `patches` changes less often (where the chunks are,
// and what each does), so the damage jumps around.
uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform float amount = 0.0;
uniform float seed = 0.0;
uniform float patches = 0.0;

float hash(vec2 p) {
	p = fract(p * vec2(443.897, 441.423));
	p += dot(p, p.yx + 19.19);
	return fract((p.x + p.y) * p.x);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float field(vec2 p) {
	return noise(p) * 0.6 + noise(p * 2.3 + 7.1) * 0.3 + noise(p * 5.1 - 3.7) * 0.1;
}

float lum(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

// Bright pixels dragged along `dir` (a step in uv): each pixel takes the
// brightest thing behind it, fading with distance, so light runs out in
// streaks the way sorted pixels do.
vec3 sorted(vec2 at, vec2 dir, float reach) {
	vec3 best = texture(screen_texture, at).rgb;
	float best_l = lum(best);
	for (int i = 1; i <= 24; i++) {
		float k = float(i) / 24.0;
		vec3 s = texture(screen_texture, at - dir * k * reach).rgb;
		float l = lum(s) * (1.0 - k * 0.55);
		if (l > best_l) {
			best_l = l;
			best = s * (1.0 - k * 0.35);
		}
	}
	return best;
}

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE;
	vec2 uv = SCREEN_UV;
	vec2 pix = floor(uv / px);
	float aspect = px.y / px.x;                 // screen width over height

	// the chunks: big ragged cells (a warped Voronoi pattern), looked up on
	// a coarse, wide grid so their edges come out stepped
	vec2 cell = floor(pix / vec2(24.0, 8.0)) * vec2(24.0, 8.0) * px;
	vec2 q = cell * vec2(aspect, 1.0) * 2.6;
	q += (vec2(field(q * 1.3 + patches), field(q * 1.3 - patches + 5.0)) - 0.5) * 1.4;
	vec2 base = floor(q);
	float best = 9.0;
	vec2 id = base;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 n = base + vec2(float(x), float(y));
			vec2 p = n + vec2(hash(n + patches * 0.17), hash(n.yx - patches * 0.29));
			float d = length(p - q);
			if (d < best) {
				best = d;
				id = n;
			}
		}
	}
	float active = step(hash(id * 1.71 + patches), amount * 0.65);
	float kind = hash(id * 0.93 - patches * 1.3);   // what this chunk does, and how
	float mode = floor(kind * 8.0);
	float sub = fract(kind * 8.0);                    // the variation within it

	vec2 at = uv;
	vec3 c = vec3(0.0);
	bool done = false;
	vec3 speck = vec3(-1.0);

	if (active > 0.5) {
		if (mode < 1.0) {
			// rows smeared sideways
			float row = floor(pix.y / 2.0);
			float run = 4.0 + floor(hash(vec2(row, seed)) * 48.0);
			at.x = floor(pix.x / run) * run * px.x + (hash(vec2(row, patches)) - 0.5) * 80.0 * px.x;
		} else if (mode < 2.0) {
			// little blocks shuffled out of place
			vec2 block = floor(pix / vec2(8.0, 4.0));
			vec2 off = floor((vec2(hash(block + seed), hash(block - seed)) - 0.5) * vec2(12.0, 6.0));
			at += off * vec2(8.0, 4.0) * px * step(0.4, hash(block * 0.37 + patches));
		} else if (mode < 3.0) {
			// rows doubled up from a little higher or lower
			float row = floor(pix.y / 2.0);
			at.y += floor((hash(vec2(row, patches)) - 0.5) * 30.0) * px.y * step(0.45, hash(vec2(row, seed)));
		} else if (mode < 4.0) {
			// coloured speckle
			vec2 d2 = floor(pix / vec2(2.0, 1.0));
			if (hash(d2 + seed * 0.13) > 0.55) {
				float which = hash(d2.yx - seed);
				speck = which < 0.3 ? vec3(0.1, 0.9, 0.1)
						: which < 0.55 ? vec3(0.85, 0.15, 0.9)
						: which < 0.75 ? vec3(0.1, 0.2, 0.95)
						: which < 0.9 ? vec3(1.0) : vec3(0.0);
			}
		} else if (mode < 5.0) {
			// pixel sorting, falling down the screen
			float col = floor(pix.x / 2.0);
			float reach = (60.0 + hash(vec2(col, patches)) * 260.0) * px.y;
			c = sorted(uv, vec2(0.0, 1.0), reach);
			done = true;
		} else if (mode < 6.0) {
			// pixel sorting, across
			float row = floor(pix.y / 2.0);
			float reach = (80.0 + hash(vec2(row, patches)) * 420.0) * px.x;
			float way = sub < 0.5 ? 1.0 : -1.0;
			c = sorted(uv, vec2(way, 0.0), reach);
			done = true;
		} else if (mode < 7.0) {
			// crushed colour, channels swapped
			vec3 s = texture(screen_texture, uv).rgb;
			s = floor(s * 3.0 + hash(pix + seed) * 0.6) / 3.0;
			float sw = sub;
			c = sw < 0.33 ? s.gbr : sw < 0.66 ? s.brg : s.rbg;
			done = true;
		} else {
			// mosaic: big flat squares
			float m = 6.0 + floor(sub * 3.0) * 6.0;
			at = (floor(pix / m) * m + m * 0.5) * px;
		}
	}

	// thin streaks anywhere, rare
	float line = floor(pix.y);
	if (!done && hash(vec2(line, seed)) > 1.0 - amount * 0.03) {
		at.x += floor((hash(vec2(seed, line)) - 0.5) * 40.0) * px.x;
	}

	if (!done) {
		c = texture(screen_texture, at).rgb;
		if (active > 0.5) {
			float split = floor(1.0 + hash(vec2(sub, seed)) * 3.0) * px.x;
			c.r = texture(screen_texture, at + vec2(split, 0.0)).r;
			c.b = texture(screen_texture, at - vec2(split, 0.0)).b;
		}
	}
	if (speck.r >= 0.0) {
		// mostly where there's something to break (bare black stays nearly black)
		float there = step(0.08, max(c.r, max(c.g, c.b)));
		c = mix(c, speck, mix(0.12, 0.85, there));
	}
	COLOR = vec4(c, 1.0);
}
