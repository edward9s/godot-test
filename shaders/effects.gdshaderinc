render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;
uniform float seconds = 0.0;
#if EFFECT_KIND == 0 || EFFECT_KIND == 1 || EFFECT_KIND == 4
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x),
        mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float turbulence(vec2 p) {
    return noise(p) * 0.57 + noise(p * 2.03 + 7.0) * 0.28 + noise(p * 4.11) * 0.15;
}
#endif
void fragment() {
    if (COLOR.a < 0.003) { discard; }
    vec2 p = UV * 2.0 - 1.0;
    vec3 color = COLOR.rgb;
    float mask = 0.0;
    float energy = 1.0;
#if EFFECT_KIND == 0
    float n = turbulence(UV * vec2(4, 5) - vec2(0, seconds * 2.8));
    float taper = 1.0 - UV.y * 0.65;
    mask = (1.0 - smoothstep(0.15, 1.0, length(vec2(p.x / taper, p.y)))) * smoothstep(0.15, 0.65, n);
    energy = 1.25;
#elif EFFECT_KIND == 1
    float n = turbulence(UV * 5.0 - vec2(seconds * 0.6));
    mask = (1.0 - smoothstep(0.35, 1.0, length(p))) * smoothstep(0.1, 0.7, n);
    color *= mix(0.35, 1.0, n);
    energy = 1.56;
#elif EFFECT_KIND == 2
    mask = 1.0 - smoothstep(0.15, 1.0, length(p));
#elif EFFECT_KIND == 3
    float core = 1.0 - smoothstep(0.03, 0.18, abs(p.x));
    mask = exp(-abs(p.x) * 4.0);
    color = mix(color, vec3(0.92, 0.96, 1.0), core);
    energy = 7.3 * (0.3 + core * 0.7);
#elif EFFECT_KIND == 4
    float n = turbulence(UV * 4.0 + vec2(seconds * 0.12, -seconds * 0.2));
    mask = (1.0 - smoothstep(0.25, 1.0, length(p))) * smoothstep(0.12, 0.7, n);
    color *= 0.5 + 0.9 * n + 0.25 * UV.y;
#endif
    ALPHA = clamp(mask * COLOR.a, 0.0, 1.0);
    if (ALPHA < 0.003) { discard; }
    ALBEDO = color * energy;
}
