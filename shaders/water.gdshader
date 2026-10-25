shader_type spatial;
render_mode blend_premul_alpha, cull_disabled, depth_draw_never, diffuse_burley, specular_schlick_ggx;
uniform float seconds = 0.0;
void fragment() {
    // Godot already orients NORMAL for cull_disabled before fragment().
    float a = UV.y * 30.0 - seconds * 4.2 + sin(UV.x * 15.0 + seconds) * 0.4;
    float b = UV.x * 25.0 + UV.y * 19.0 - seconds * 3.1;
    vec3 ripple = normalize(vec3(cos(b) * 0.12, cos(a) * 0.18, 1.0));
    NORMAL = normalize(mat3(TANGENT, BINORMAL, NORMAL) * ripple);
    float foam = pow(max(0.0, sin(a) * sin(b)), 12.0) * 0.18;
    float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 5.0);
    float opacity = mix(COLOR.a * 0.35, 0.9, fresnel);
    float edge = 1.0;
    if (COLOR.a > 0.6) {
        edge = smoothstep(0.0, 0.12, UV.x) * (1.0 - smoothstep(0.88, 1.0, UV.x));
        edge *= smoothstep(0.0, 0.04, UV.y) * (1.0 - smoothstep(0.96, 1.0, UV.y));
    }
    // Attenuate the water tint while retaining reflected light on a clear surface.
    ALBEDO = mix(COLOR.rgb, vec3(0.72, 0.85, 0.82), foam) * opacity;
    ALPHA = opacity * edge;
    PREMUL_ALPHA_FACTOR = edge;
    ROUGHNESS = 0.18;
    METALLIC = 0.0;
    SPECULAR = 0.35;
}
