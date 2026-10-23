shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
// Keep leaf geometry stationary while casting real-time shadows on Mobile.
// Animated vertex offsets cause alpha-masked shadow-map edges to change every frame.
void fragment() {
    float vein = smoothstep(0.015, 0.045, abs(UV.x - 0.5));
    float ribs = 0.94 + 0.06 * sin((UV.y + abs(UV.x - 0.5) * 0.6) * 100.0);
    ALBEDO = COLOR.rgb * mix(1.25, ribs, vein);
    ROUGHNESS = 0.68;
    METALLIC = 0.0;
}
