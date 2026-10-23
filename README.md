# Forest Ruins — Godot 4

Godot rendering of the same deterministic forest-ruins geometry used by [filament-test](https://github.com/edward9s/filament-test). The stone arches, forest, path, camera target, and source Poly Haven textures are carried across; lighting and tone mapping are engine-specific and cannot be pixel identical.

## Prepare scene

Requires Linux x86-64, Python 3.11+, `g++`, `curl`, `tar`, Pillow, and Godot 4.7.2. Generated assets are deliberately excluded from git.

```sh
python3 -m pip install Pillow==11.3.0
python3 scripts/prepare_scene.py
# Open project.godot in Godot 4.7.2, or run:
godot --headless --path . --editor --import --quit
```

The preparation script downloads SHA-256-verified CC0 Poly Haven imagery and the matching Filament 1.78.1 host SDK headers, compiles the **unmodified** `Geometry.cpp` from filament-test, and exports its deterministic ~230 spatial/material batches into a textured glTF binary. No native Filament code or SDL is shipped in the APK.

## Android

Use **Actions → Android test build → Run workflow** to generate a signed arm64 APK, published to the rolling `test-build` prerelease. The workflow is manual-only and uses the repository's existing `KEYSTORE_BASE64`, `STORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD` secrets. It never generates a signing identity. Build outputs replace the existing test prerelease rather than creating a new release per run. Package: `com.edward9s.godotforesttest`.

## Scene and controls

The same generated terrain, stones, two arches, surrounding trees, bark branches, canopy quads, ferns and ivy, and Poly Haven 1K PBR maps/HDRI are used. Sun direction matches Filament (`[-0.32,-0.82,-0.47]`), including cascaded dynamic shadows. Camera orbit: one-finger drag or left mouse; pinch or mouse wheel zoom. FPS is overlaid at top-left. Godot Mobile renderer is used for Android with ETC2/ASTC-compressed textures, PBR, HDR sky, glow, fog and cascaded sun shadows. Mobile does not support Forward+-only SSAO or TAA; MSAA remains enabled. Canopy and leaf geometry remain static to avoid rapid shadow-map shimmering on alpha-masked vegetation (stone, trees and grass still cast real-time shadows). The sun uses fixed-width filtered shadows instead of PCSS, with blended cascades and a 48 m shadow range. Warm sunlight is reduced from 3.5 to 2.2, HDR sky ambient light from 0.85 to 0.60, sky background intensity to 0.80 and camera exposure to 0.82 for a more subdued forest appearance. These are starting calibration values, not a measured color match. Actual Android performance depends on the device.

## Differences from Filament

Godot and Filament implement PBR response, IBL filtering, exposure, antialiasing and fog differently. Same source geometry and texture inputs enable close composition but do not promise pixel-for-pixel reproduction. Compare screenshots on the same device for final tuning.

## Asset credits

Poly Haven forest ground, mossy rock, bark, pine canopy and forest HDR: see `assets/CREDITS.md` and the hash manifest `assets/sources.json` (CC0 1.0). `vendor/Geometry.cpp` and `vendor/Geometry.h` originate from the owner's filament-test repository.
