shader_type canvas_item;

uniform vec4 glow_color : source_color = vec4(0.0, 0.0, 1.0, 1.0);
uniform float glow_size = 0.0;

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE * glow_size;
	float a = 0.0;
	a += texture(TEXTURE, UV + vec2(px.x, 0.0)).a;
	a += texture(TEXTURE, UV + vec2(-px.x, 0.0)).a;
	a += texture(TEXTURE, UV + vec2(0.0, px.y)).a;
	a += texture(TEXTURE, UV + vec2(0.0, -px.y)).a;
	a += texture(TEXTURE, UV + vec2(px.x, px.y)).a;
	a += texture(TEXTURE, UV + vec2(-px.x, px.y)).a;
	a += texture(TEXTURE, UV + vec2(px.x, -px.y)).a;
	a += texture(TEXTURE, UV + vec2(-px.x, -px.y)).a;
	a = min(a, 1.0);
	vec4 c = texture(TEXTURE, UV);
	COLOR = mix(vec4(glow_color.rgb, a * glow_color.a), c, c.a);
}