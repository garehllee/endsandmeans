shader_type canvas_item;

// A solid outline around whatever's drawn, for "you can use this" (the same
// blue as the glow on the desk's interactables). width is in the texture's
// own pixels; 0 draws the picture plain. The picture needs see-through
// margin around it for the line to fit.
uniform vec4 line_color : source_color = vec4(0.0, 0.169, 1.0, 1.0);
uniform float width = 0.0;

varying vec4 tint;   // the draw's own colour (its fade), before the texture is mixed in

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float a = 0.0;
	if (width > 0.0) {
		for (int i = 0; i < 16; i++) {
			float ang = float(i) * 0.39269908;
			vec2 dir = vec2(cos(ang), sin(ang)) * TEXTURE_PIXEL_SIZE * width;
			a = max(a, texture(TEXTURE, UV + dir).a);
			a = max(a, texture(TEXTURE, UV + dir * 0.5).a);
		}
	}
	vec4 line = vec4(line_color.rgb, a * line_color.a);
	COLOR = mix(line, c, c.a) * tint;
}
