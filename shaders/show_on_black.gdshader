shader_type canvas_item;

// Only shows where the screen behind is (near enough) black. The blue Hugging
// Face in the transition uses it, so it appears exactly on the black flashes,
// whatever frame the video has actually got to.
uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	vec3 back = texture(screen_texture, SCREEN_UV).rgb;
	float dark = 1.0 - smoothstep(0.04, 0.16, max(back.r, max(back.g, back.b)));
	COLOR = vec4(c.rgb, c.a * dark);
}
