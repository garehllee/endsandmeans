shader_type canvas_item;

// Turns the blue character orange: red and blue trade places, and the green
// comes down a little so the blue (38, 74, 255) lands on the orange (255, 69, 0).
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	COLOR = vec4(c.b, c.g * 0.93, 0.0, c.a);
}
