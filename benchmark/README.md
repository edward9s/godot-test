# Unified forest benchmark — implementation in progress

Schema version `1.0.0`. This branch is a work in progress; no Galaxy Tab S8 measurements or completed APK validation are claimed.

Each run directory contains `metadata.json`, `frames.csv`, `metrics.csv`, and `summary.json`.
The metadata and summary carry the same `schema_version`, `run_id`, `preset_id`, `valid`, and `invalid_reason`.
`test_compare.py::fixture()` is an executable **synthetic** schema example. Do not publish its numbers as device results.

## Statistics and clocks

Use a monotonic clock, collect application callback intervals only after a 30 second warmup, then measure at least 60 seconds. Reset camera and animation clock before warmup. Repeat each preset three times independently, restoring baseline settings between runs.

- Mean FPS = 1000 × sample count / sum of intervals in milliseconds.
- Mean frame time = sum / count.
- P50/P95/P99 use nearest rank: sorted intervals at `ceil(p × count) - 1`.
- 1% low FPS = 1000 / mean of the **slowest `ceil(count × .01)` intervals**.
- The first measured timestamp anchors the interval sequence and is not itself a sample.
- Application callback FPS is not presentation FPS. Unmeasured presentation FPS is `null`.
- Store actual CPU/GPU scopes, source API, and units. Never infer whole-frame GPU time from a slowest pass or sum potentially overlapping passes.

`frames.csv` columns:

```csv
frame_index,elapsed_ms,interval_ms,animation_seconds,cpu_scene_ms,cpu_effects_ms,cpu_submit_ms,cpu_wait_ms
```

Unsupported CPU values are empty. Nonempty CPU columns require a matching metric definition in metadata. `metrics.csv` is for asynchronous native observations:

```csv
sample_id,observed_frame,metric,value_ms
```

`observed_frame` identifies the application callback receiving the result, not the GPU execution frame. Deduplicate native samples before writing. Never emit zero as a substitute for unavailable timestamps.

## Comparison CLI

```sh
python3 -m unittest discover -s benchmark -p 'test_*.py'
python3 benchmark/compare.py exported-directory engine2.zip engine3.zip --validate-only
python3 benchmark/compare.py exported-directory engine2.zip engine3.zip --output comparison
```

The tool uses only the Python standard library. It recomputes statistics from raw intervals, checks dimensions and preset settings, rejects malformed data, groups backend / presentation policy / profiling / hardware / scene conditions, and writes `comparison.md` and `comparison.csv`.
Different builds or settings of the same engine refuse aggregation. Unknown actual presentation modes are isolated per engine, preventing unsupported cross-engine rankings. Three engines × three repetitions are needed for a complete comparison. CPU scopes are shown separately. GPU passes keep their names.

## Required physical-device verification

Pending: complete Android integration, release APK build/package checks, start/cancel/export and restore behavior, background/rotation invalidation, shader/reflection readiness, actual GPU timestamp support, repeated-run memory use, showcase vs Standard overhead, thermal behavior and matched screenshots at 38.52 seconds.

For Bevy's 8–9 FPS, independent resolution/shadow/AA/Bloom/effects tests can identify sensitivity to those workloads. Native render-world timings can separate preparation and submission scopes. These observations alone cannot prove shader ALU, texture bandwidth, occupancy, overdraw, driver stalls or CPU/GPU queue dependencies; AGI/Perfetto or supported vendor counters are still needed. Adreno GPU preprocessing support must be recorded from the actual Bevy adapter, not assumed from model name.

## Godot Android operation

Tap **Benchmark** below the FPS overlay. Each of the eight presets runs three times (initialization, 30 second warmup, 60 second measurement per run). The progress button cancels. **View results** reads saved summaries. **Export ZIP** opens Android's native document picker. Results remain locally if export fails. **Reference screenshot** freezes only the separate reference capture at 38.52 seconds, then restores showcase state.

Standard/Baseline keep the existing Mobile renderer quality: 2× MSAA, TAA off on Mobile, 4096 shadow atlas with four cascades and 48 m shadow distance, Bloom 0.065, fog and native materials. Forward+ uses its existing TAA/SSAO path. The no-AA preset disables every viewport AA setting; no-Bloom disables only Bloom; no-effects hides six batches and their three lights and skips the effects CPU update (foliage wind remains). The 65% preset scales each 3D axis; UI stays native.

CPU effect time is the raw monotonic span around `effects.animate`, not its smoothed HUD number. GPU Diagnostic enables `RenderingServer.viewport_set_measure_render_time`; Standard disables it, restoring the original showcase measurement afterward. Root viewport CPU and GPU API observations have no native sample identity, so repeated latest observations are explicitly documented. No pass times or presentation FPS are fabricated. Device thermal status is a pre-initialization snapshot.

Verified locally with Godot 4.7.2 headless: pure protocol tests, existing scene/effects/resolution tests, eight-preset synthetic export/restore integration, and Python validation of all eight exports. Headless tests validate behavior and data, not Android rendering performance. Android SAF, Java reflection metadata, viewport dimensions, native GPU timestamps and screenshots still require the target APK/device.

Sources: [Godot 4.7.2 RenderingServer](https://github.com/godotengine/godot/blob/4.7.2-stable/doc/classes/RenderingServer.xml), [native SAF dialog](https://github.com/godotengine/godot/blob/4.7.2-stable/doc/classes/DisplayServer.xml). Build provenance: run `python3 benchmark/build.py` before importing/exporting; the Android workflow does this automatically.
