shader_type canvas_item;

// Hides the parts of a picture that have been rubbed out.
// mask: white = still there, black = erased (low resolution is fine).
uniform sampler2D mask : filter_linear, repeat_disable;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	c.a *= texture(mask, UV).r;
	COLOR = c;
}
