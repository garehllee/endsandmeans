shader_type canvas_item;

// Drawn over the whole desktop while everything comes apart at the end. It
// looks like a graphics card failing: the screen is split into uneven
// rectangles, and each one goes wrong in its own way (or not at all) --
// fine horizontal streaks, rows smeared sideways, little blocks shuffled
// out of place, pixels speckled green / magenta / blue. All of it works at
// the scale of a few screen pixels.
//
// `amount` is how bad it is (0 is nothing). `seed` changes every frame or
// two (the fine noise); `patches` changes less often (which rectangles are
// broken, and how), so the damage jumps around in patches.
uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform float amount = 0.0;
uniform float seed = 0.0;
uniform float patches = 0.0;

float hash(vec2 p) {
	p = fract(p * vec2(443.897, 441.423));
	p += dot(p, p.yx + 19.19);
	return fract((p.x + p.y) * p.x);
}

// Which uneven rectangle a point is in: a coarse grid whose columns and rows
// are split again at random, so the pieces come in different sizes.
vec2 region(vec2 uv) {
	vec2 cell = floor(uv * vec2(6.0, 9.0));
	vec2 sub = vec2(2.0 + floor(hash(cell + patches) * 4.0), 1.0 + floor(hash(cell.yx - patches) * 5.0));
	return cell * 8.0 + floor(fract(uv * vec2(6.0, 9.0)) * sub);
}

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE;
	vec2 uv = SCREEN_UV;
	vec2 pix = floor(uv / px);                  // this screen pixel
	vec2 reg = region(uv);
	float r = hash(reg + patches * 1.37);
	float active = step(1.0 - amount * 0.75, hash(reg - patches * 0.71));
	float mode = floor(r * 5.0);                // what goes wrong here
	vec2 at = uv;
	vec3 speck = vec3(-1.0);

	if (active > 0.5) {
		if (mode < 1.0) {
			// rows smeared sideways: thin rows, each held for a run of pixels
			float row = floor(pix.y / (1.0 + floor(hash(reg) * 3.0)));
			float run = 4.0 + floor(hash(vec2(row, seed)) * 40.0);
			at.x = floor(pix.x / run) * run * px.x;
			at.x += (hash(vec2(row, reg.x)) - 0.5) * 60.0 * px.x;
		} else if (mode < 2.0) {
			// little blocks shuffled out of place
			vec2 block = floor(pix / vec2(8.0, 4.0));
			vec2 off = floor((vec2(hash(block + seed), hash(block - seed)) - 0.5) * vec2(12.0, 6.0));
			at += off * vec2(8.0, 4.0) * px * step(0.4, hash(block * 0.37 + patches));
		} else if (mode < 3.0) {
			// rows copied from a little higher or lower (text doubling up)
			float row = floor(pix.y / 2.0);
			at.y += floor((hash(vec2(row, patches)) - 0.5) * 24.0) * px.y * step(0.5, hash(vec2(row, seed)));
			at.x += floor((hash(vec2(reg.y, seed)) - 0.5) * 6.0) * 4.0 * px.x;
		} else if (mode < 4.0) {
			// speckled: tiny 2x1 dots of the broken colours
			vec2 d2 = floor(pix / vec2(2.0, 1.0));
			float h = hash(d2 + seed * 0.13);
			if (h > 0.55) {
				float which = hash(d2.yx - seed);
				speck = which < 0.3 ? vec3(0.1, 0.9, 0.1)
						: which < 0.55 ? vec3(0.85, 0.15, 0.9)
						: which < 0.75 ? vec3(0.1, 0.2, 0.95)
						: which < 0.9 ? vec3(1.0) : vec3(0.0);
			}
		}
		// mode 4: left alone, apart from the colour split below
	}

	// fine scanline streaks anywhere, thin and rare
	float line = floor(pix.y);
	if (hash(vec2(line, seed)) > 1.0 - amount * 0.03) {
		at.x += floor((hash(vec2(seed, line)) - 0.5) * 40.0) * px.x;
	}

	vec3 c = texture(screen_texture, at).rgb;
	if (active > 0.5) {
		float split = floor(1.0 + hash(reg + seed) * 3.0) * px.x;
		c.r = texture(screen_texture, at + vec2(split, 0.0)).r;
		c.b = texture(screen_texture, at - vec2(split, 0.0)).b;
	}
	if (speck.r >= 0.0) {
		// keep a little of what's underneath, like the picture showing through;
		// mostly where there's something to break (bare black stays nearly black)
		float there = step(0.08, max(c.r, max(c.g, c.b)));
		c = mix(c, speck, mix(0.12, 0.85, there));
	}
	COLOR = vec4(c, 1.0);
}
