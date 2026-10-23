shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;
uniform sampler2D pine_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
void vertex() {
    float phase = VERTEX.x * 0.71 + VERTEX.z * 0.49;
    float wind = sin(TIME * 1.2 + phase) + 0.35 * sin(TIME * 2.6 + phase * 2.0);
    VERTEX.xz += vec2(0.06, 0.025) * wind;
}
void fragment() {
    vec4 pine = texture(pine_texture, UV);
    ALBEDO = pine.rgb;
    ALPHA = pine.a;
    ALPHA_SCISSOR_THRESHOLD = 0.4;
    ROUGHNESS = 0.8;
    METALLIC = 0.0;
}
