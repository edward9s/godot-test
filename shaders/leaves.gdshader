shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
void vertex() {
    float phase = VERTEX.x * 0.71 + VERTEX.z * 0.49;
    float wind = sin(TIME * 1.2 + phase) + 0.35 * sin(TIME * 2.6 + phase * 2.0);
    VERTEX.xz += vec2(0.06, 0.025) * wind * COLOR.a;
}
void fragment() {
    float vein = smoothstep(0.015, 0.045, abs(UV.x - 0.5));
    float ribs = 0.94 + 0.06 * sin((UV.y + abs(UV.x - 0.5) * 0.6) * 100.0);
    ALBEDO = COLOR.rgb * mix(1.25, ribs, vein);
    if (!FRONT_FACING) { NORMAL = -NORMAL; }
    BACKLIGHT = COLOR.rgb * 0.65 * 0.45;
    ROUGHNESS = 0.68;
    METALLIC = 0.0;
}

