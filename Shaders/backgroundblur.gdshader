shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float blur_amount : hint_range(0.0, 5.0) = 10.0;

void fragment() {
    // Sample the screen texture with a level of detail (LOD) for blurring
    vec3 col = textureLod(screen_texture, SCREEN_UV, blur_amount).rgb;
    COLOR.rgb = col;
}