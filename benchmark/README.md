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

Verified locally with Godot 4.7.2 headless: pure protocol tests, existing scene/effects/resolution tests, eight-preset synthetic export/restore integration, and Python validation of all eight exports. Headless tests validate behavior and data, not Android rendering performance. An unsigned Release APK was also exported locally and passed ABI/DEX/benchmark-script/provenance packaging checks. The exporter workflow now writes Godot 4.7’s versioned editor settings filename. Repository-key signing, Android SAF, Java reflection metadata, native viewport dimensions, GPU timestamps and screenshots still require the target APK/device.

Sources: [Godot 4.7.2 RenderingServer](https://github.com/godotengine/godot/blob/4.7.2-stable/doc/classes/RenderingServer.xml), [native SAF dialog](https://github.com/godotengine/godot/blob/4.7.2-stable/doc/classes/DisplayServer.xml). Build provenance: run `python3 benchmark/build.py` before importing/exporting; the Android workflow does this automatically.

Formal JSON schemas: `metadata.schema.json`, `summary.schema.json`. The CLI also checks CSV timelines, scope definitions, preset conditions and recomputed statistics. Run `python3 benchmark/examples.py /tmp/forest-examples` for nine clearly marked synthetic runs plus an example Markdown/CSV report.

## Galaxy Tab S8 procedure (all three APKs)

1. Install matching Release APKs built from the three PR branches, with validation, Vulkan queue waits and pipeline statistics disabled. Record APK hashes and build commits. Use the same landscape orientation, screen mode/refresh, brightness and thermal starting condition; close background workloads. Filament: select Vulkan to compare Vulkan results; keep GLES in its own group.
2. Take a Reference screenshot at 38.52 s in each APK at the same native Surface size. Export settings and inspect materials, shadows, foliage, water, particles, exposure and postprocessing differences. Existing native pipelines differ; matching option names do not prove image equality.
3. Run Standard (three repetitions automatically). Do not touch camera or change display settings. Initialization and 30 s warmup precede each 60 s measurement. Let the tablet cool consistently between engine/preset batches. Keep all repetitions, including invalid runs with reasons.
4. Run GPU Diagnostic separately. Export each ZIP through Android's document picker. GPU Diagnostic FPS must remain separate from Standard. Check actual MSAA, Surface/3D sizes, GPU timestamp availability and profiling flags.
5. Run each Bottleneck preset independently (baseline, no shadows, no AA, no Bloom, fixed 65% axes, no effects). Restore to showcase after each group. Compare deltas only within matching backend/build/device/presentation conditions. A/B effects identify sensitivity, not unique hardware causes.
6. Validate and report using `python3 benchmark/compare.py exports/*.zip --output tab-s8`. Unknown actual presentation modes intentionally prevent a formal cross-engine ranking; the report still exposes each engine's observations/scopes.
7. Validate cancellation, background/resume, Surface resize, refresh change and settings changes; affected runs must be invalid. Repeat tests and watch memory/thermal behavior. Measure showcase vs Standard overhead and GPU Diagnostic overhead separately. These checks are pending until done on hardware.

No Galaxy Tab S8 is attached to this environment. No tablet FPS, screenshot equivalence or overhead acceptance is claimed.

The report also provides a separate within-engine A/B sensitivity table. It only allows the selected setting to differ and keeps GPU Diagnostic deltas explicitly labeled profiling overhead; it does not turn those deltas into a unique hardware diagnosis.

APK contents are checked with `python3 benchmark/check_apk.py ENGINE path.apk --commit SHA`: arm64 ELF, DEX integrity, runtime bridge/scripts, required scene assets and baked commit. This supplements the existing signer/zip alignment checks; it does not replace them.

Before warmup, each real run saves an empty invalid snapshot marked in progress. On next launch, a complete snapshot left by a process interruption becomes an invalid result with its reason; partially written files remain excluded and are identified as incomplete in the results viewer. No journal/disk updates occur during measurement. Reference captures are separate and create no benchmark run journal.
