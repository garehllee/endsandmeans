shader_type canvas_item;

// The "corrupt" flash. Draw this over everything and it recolors what is
// underneath it:
//   1. a solid #636363 layer in Luminosity blend mode (every pixel keeps its
//      own hue and saturation but takes the luminosity of #636363),
//   2. a solid white layer in Difference blend mode (which inverts the result).
// Godot has no built-in blend modes like these, so the maths is done here.
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform vec3 gray : source_color = vec3(0.388235, 0.388235, 0.388235);   // #636363

float lum(vec3 c) {
	return dot(c, vec3(0.3, 0.59, 0.11));
}

vec3 clip_color(vec3 c) {
	float l = lum(c);
	float n = min(min(c.r, c.g), c.b);
	float x = max(max(c.r, c.g), c.b);
	if (n < 0.0) {
		c = l + (c - l) * l / (l - n);
	}
	if (x > 1.0) {
		c = l + (c - l) * (1.0 - l) / (x - l);
	}
	return c;
}

vec3 set_lum(vec3 c, float l) {
	return clip_color(c + (l - lum(c)));
}

void fragment() {
	vec3 back = texture(screen_tex, SCREEN_UV).rgb;
	vec3 flat_lum = set_lum(back, lum(gray));          // luminosity blend with #636363
	COLOR = vec4(abs(flat_lum - vec3(1.0)), 1.0);      // difference blend with white
}
