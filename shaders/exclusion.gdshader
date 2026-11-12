shader_type canvas_item;

// Exclusion blend: each box lays itself over whatever is already behind it,
// with the result  back + box - 2 * back * box.  Unlike difference it never
// goes fully black where two boxes overlap, so they read as separate
// rectangles stacked on top of one another rather than cut-outs of each other.
uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;

void fragment() {
	vec4 box = texture(TEXTURE, UV);
	vec3 back = texture(screen_texture, SCREEN_UV).rgb;
	vec3 ex = back + box.rgb - 2.0 * back * box.rgb;
	COLOR = vec4(ex, box.a);
}
