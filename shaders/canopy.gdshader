shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;
uniform sampler2D pine_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
// Keep leaf geometry stationary while casting real-time shadows on Mobile.
// Animated vertex offsets cause alpha-masked shadow-map edges to change every frame.
void fragment() {
    vec4 pine = texture(pine_texture, UV);
    ALBEDO = pine.rgb;
    ALPHA = pine.a;
    ALPHA_SCISSOR_THRESHOLD = 0.4;
    ROUGHNESS = 0.8;
    METALLIC = 0.0;
}
