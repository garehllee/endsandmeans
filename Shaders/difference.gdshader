shader_type canvas_item;

// Hint tells Godot to fetch the screen background behind this pixel
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

void fragment() {
    // 1. Get the color of the sprite/object texture
    vec4 base_color = texture(TEXTURE, UV);
    
    // 2. Get the color of the screen behind the object using SCREEN_UV
    vec4 screen_color = texture(screen_texture, SCREEN_UV);
    
    // 3. Calculate the absolute difference for RGB channels
    vec3 diff_rgb = abs(screen_color.rgb - base_color.rgb);
    
    // 4. Mix the difference with the background based on the object's alpha channel
    COLOR = vec4(mix(screen_color.rgb, diff_rgb, base_color.a), base_color.a);
}