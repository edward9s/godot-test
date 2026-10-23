shader_type spatial;
render_mode cull_disabled, depth_draw_never, diffuse_burley, specular_schlick_ggx;
uniform float seconds = 0.0;
void fragment() {
    if (!FRONT_FACING) { NORMAL = -NORMAL; }
    float a = UV.y * 30.0 - seconds * 4.2 + sin(UV.x * 15.0 + seconds) * 0.4;
    float b = UV.x * 25.0 + UV.y * 19.0 - seconds * 3.1;
    NORMAL_MAP = normalize(vec3(cos(b) * 0.12, cos(a) * 0.18, 1.0)) * 0.5 + 0.5;
    float foam = pow(max(0.0, sin(a) * sin(b)), 12.0) * 0.18;
    ALBEDO = mix(COLOR.rgb, vec3(0.72, 0.85, 0.82), foam);
    ALPHA = COLOR.a;
    if (COLOR.a > 0.6) {
        ALPHA *= smoothstep(0.0, 0.12, UV.x) * (1.0 - smoothstep(0.88, 1.0, UV.x));
    }
    ROUGHNESS = 0.24;
    METALLIC = 0.0;
    SPECULAR = 0.35;
}
