# Forest Ruins — Godot 4

Godot rendering of the same deterministic forest-ruins geometry used by [filament-test](https://github.com/edward9s/filament-test). The stone arches, forest, path, camera target, and source Poly Haven textures are carried across; lighting and tone mapping are engine-specific and cannot be pixel identical.

![Actual Godot Forward+ render](docs/forest-preview.jpg)

Actual 1280×720 Vulkan render on Linux llvmpipe. The displayed FPS is software rendering performance, not an Android measurement.

## Prepare scene

Requires Linux x86-64, Python 3.11+, `g++`, `curl`, `tar`, Pillow, and Godot 4.7.2. Generated assets are deliberately excluded from git.

```sh
python3 -m pip install Pillow==11.3.0
python3 scripts/prepare_scene.py
# Open project.godot in Godot 4.7.2, or run:
godot --headless --path . --editor --import --quit
```

The preparation script downloads SHA-256-verified CC0 Poly Haven imagery and the matching Filament 1.78.1 host SDK headers, compiles the **unmodified** `Geometry.cpp` from filament-test's effects branch (`4d884ac5`), and exports its deterministic 232 spatial/material batches into a textured glTF binary. This includes the spring rock and vegetation clearance around the flowing water. No native Filament code or SDL is shipped in the APK.

## Android

Use **Actions → Android test build → Run workflow** to generate a signed arm64 APK, published to the rolling `test-build` prerelease. The workflow is manual-only and uses the repository's existing `KEYSTORE_BASE64`, `STORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD` secrets. It never generates a signing identity. Build outputs replace the existing test prerelease rather than creating a new release per run. Package: `com.edward9s.godotforesttest`.

## Scene and controls

The same generated terrain, stones, two arches, surrounding trees, bark branches, canopy quads, ferns and ivy, and Poly Haven 1K PBR maps/HDRI are used. Sun direction matches Filament (`[-0.32,-0.82,-0.47]`); linear source light colors are converted to Godot’s sRGB light properties. Camera orbit: one-finger drag or left mouse; pinch or mouse wheel zoom. FPS is overlaid at top-left.

Desktop and Android now use **Forward+** to support SSAO, TAA and PCSS sun shadows. SSAO uses the source's 0.75 m radius and 1.2 power, while the HDRI supplies diffuse ambient lighting and filtered reflections. TAA combines with 2× MSAA to reduce temporal aliasing on fine vegetation. Four blended shadow cascades cover 48 m using a 4096 atlas, including the Android override; split distances are 12%, 38% and 65%. Bias is explicitly 0.03 and normal bias 0.35, avoiding the default large normal offset that loses contact shadows on small leaves. PCSS uses a 1.06° angular diameter corresponding to the source's 0.53° solar radius. Shadow filter quality remains 2 on both platforms.

Imported ground, stone and bark materials explicitly enable the generator's linear vertex colors. Godot 4.7.2 leaves this material flag off after glTF import, losing the source tints and surface variation.

All original canopy and leaf wind deformation remains enabled in the color and shadow passes. Foliage casts double-sided shadows with a 0.12 m culling margin for wind. Back faces have corrected normals and a modest backlight term approximates the source's leaf transmission. Sky energy (0.50), ambient multiplier (0.18), warm sunlight (1.1), ACES tone mapping and fixed camera exposure (0.65) aim for a quieter forest rather than a washed-out clearing. Glow and distance fog remain enabled. These settings require a Vulkan-capable Android device and cost more GPU time than the previous Mobile renderer. FPS and physical-device comparison are needed to judge the tradeoff.

## Effects

The five displays follow [filament-test PR #4](https://github.com/edward9s/filament-test/pull/4), which was still unmerged when this port was made:

| Display | Position (x, z) | Animation |
| --- | --- | --- |
| Fire | −3.2, 3.1 | Continuous flames, rising embers, flickering local light |
| Explosion | −6.3, −1.6 | Expanding fireball and ballistic sparks every 5.4 seconds |
| Water | 3.5, 3.5 | Raised spring, tubular jet, shallow flowing sheet and splashes |
| Lightning | 6.3, −3.2 | Branching double strike every 4.8 seconds with local flash |
| Smoke | −7.0, −6.2 | Continuous drifting dense column |

`scripts/effects.gd` ports the deterministic seeds, equations, particle counts and sites. Six persistent `ArrayMesh` batches total 583 quads / 1,166 triangles. `scripts/effect_batch.gd` allocates each surface once and updates vertex/attribute buffer regions in place. Animation never clears or recreates GPU surfaces. Fixed bounds cover the entire motion; water normal and tangent buffers update with its geometry. Transparent puffs are sorted back to front for the orbit camera; water uses moving tangent normals, foam and HDR sky reflections. Fire, explosion and lightning animate three nearby point lights. Emission and light energies are calibrated in Godot units. No particle textures, physics or extra asset downloads are required.

Validate after generating and importing assets:

```sh
python3 scripts/check_scene.py
godot --headless --path . --script scripts/test_effects.gd
godot --headless --path . --script scripts/test_scene.gd
# Continuous Vulkan rendering; fail on growing memory or incorrect GPU uploads:
godot --path . --audio-driver Dummy --script scripts/test_stability.gd -- effects 3600
godot --path . --audio-driver Dummy --script scripts/test_stability.gd -- scene 180
# Actual framebuffer capture, with a Vulkan display:
godot --path . --script scripts/render_preview.gd -- /tmp/godot-effects.png 0.3
```

## Differences from Filament

Godot and Filament implement PBR response, IBL filtering, exposure, antialiasing and fog differently. Same source geometry and texture inputs enable close composition but do not promise pixel-for-pixel reproduction. Compare screenshots on the same device for final tuning.

## Asset credits

Poly Haven forest ground, mossy rock, bark, pine canopy and forest HDR: see `assets/CREDITS.md` and the hash manifest `assets/sources.json` (CC0 1.0). `vendor/Geometry.cpp`, `vendor/Geometry.h`, and the ported effects equations/shaders originate from the owner's filament-test repository.

