shader_type canvas_item;

// Darken blend: each pixel keeps whichever is darker, what's already on the
// screen or this picture. White leaves the scene alone, black wipes it out.
uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;

void fragment() {
	vec4 top = texture(TEXTURE, UV);
	vec3 back = texture(screen_texture, SCREEN_UV).rgb;
	COLOR = vec4(min(back, top.rgb), 1.0);
}
