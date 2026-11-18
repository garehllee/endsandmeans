shader_type canvas_item;

// The folder's thumbnail, drawn over the game while it starts, and the game
// rippling in through it: a ring spreads out from the middle, and behind it
// the game shows through, pushed in and out by a wave that dies away as it
// settles (like the paragraph on the choice screen).
uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform float progress = 0.0;            // 0: all thumbnail, 1: all game
uniform float travel = 0.0;              // how far the wave has gone, in the rect's units
uniform vec2 rect_size = vec2(1600.0, 900.0);
uniform vec4 region = vec4(0.0, 0.0, 1.0, 1.0);   // the part of the thumbnail drawn (UV pos, UV size)
uniform float amp = 24.0;                // screen pixels the wave pushes the game
uniform float wavelength = 220.0;
uniform float band = 260.0;              // how soft the edge of the ring is

void fragment() {
	vec2 local = (UV - region.xy) / region.zw;
	vec2 p = local * rect_size;
	vec2 c = rect_size * 0.5;
	float d = length(p - c);
	float front = progress * (length(c) + band);
	float reveal = clamp((front - d) / band, 0.0, 1.0);
	float calm = (1.0 - progress) * (1.0 - progress);
	vec2 dir = d > 0.001 ? (p - c) / d : vec2(0.0);
	float wave = sin((d - travel) / wavelength * 6.2831853) * amp * calm;
	vec3 game = texture(screen_texture, SCREEN_UV + dir * wave * SCREEN_PIXEL_SIZE).rgb;
	vec3 thumb = texture(TEXTURE, UV).rgb;
	COLOR = vec4(mix(thumb, game, reveal), 1.0);
}
