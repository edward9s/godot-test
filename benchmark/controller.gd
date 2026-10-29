extends Node
## UI, reversible presets and asynchronous render observations. No I/O while measuring.
const Protocol := preload("res://benchmark/protocol.gd")
const PRESETS := ["standard", "gpu", "baseline", "no_shadows", "no_aa", "no_bloom", "scale_65", "no_effects"]
const ROOT := "user://benchmarks"
var protocol := Protocol.new()
var forest: Node
var viewport: Viewport
var effects: Node
var sun: DirectionalLight3D
var environment: Environment
var button: MenuButton
var progress: Button
var dialog: AcceptDialog
var preset := ""
var repetition := 1
var snapshot := {}
var run_id := ""
var started_at := 0
var applied := false
var size := Vector2i.ZERO
var surface_size := Vector2i.ZERO
var draw_anchor := 0
var stable_since := 0
var pipeline_count := -1
var poll_at := 0
var animation_origin := 0
var animation := 0.0
var observed_vsync := 0
var refresh: Variant = null
var metric_count := 0
var metric_rows: Array = []
var definitions := {}
var device := {}
var settings := {}
var build := {}
var reference := false
var reference_frames := 0

func _ready() -> void:
    forest = get_parent()
    viewport = get_viewport()
    effects = forest.get_node("Effects")
    sun = forest.get_node("WarmSun")
    environment = forest.get_node("WorldEnvironment").environment
    process_priority = -100
    build = JSON.parse_string(FileAccess.get_file_as_string("res://benchmark/build.json"))
    var layer := CanvasLayer.new()
    layer.layer = 10
    add_child(layer)
    button = MenuButton.new()
    button.text = "Benchmark"
    button.custom_minimum_size = Vector2(240, 64)
    button.add_theme_font_size_override("font_size", 24)
    button.position = Vector2(12, 130)
    layer.add_child(button)
    var menu := button.get_popup()
    for i in PRESETS.size():
        menu.add_item(PRESETS[i] + " × 3", i)
    menu.add_item("Reference screenshot · 38.52 s", 8)
    menu.add_item("View results", 9)
    menu.add_item("Export ZIP", 10)
    menu.id_pressed.connect(_menu)
    progress = Button.new()
    progress.position = button.position
    progress.custom_minimum_size = Vector2(480, 64)
    progress.add_theme_font_size_override("font_size", 24)
    progress.visible = false
    progress.pressed.connect(func(): _invalidate("cancelled by user"))
    layer.add_child(progress)
    dialog = AcceptDialog.new()
    dialog.size = Vector2i(900, 550)
    dialog.get_label().hide()
    var report := RichTextLabel.new()
    report.name = "Report"
    report.add_theme_font_size_override("normal_font_size", 22)
    dialog.add_child(report)
    report.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    report.offset_left = 16
    report.offset_top = 16
    report.offset_right = -16
    report.offset_bottom = -64
    layer.add_child(dialog)
    _recover()
    RenderingServer.frame_post_draw.connect(_frame)

func active() -> bool:
    return not snapshot.is_empty()

func _menu(id: int) -> void:
    if id == 9:
        _results()
    elif id == 10:
        _export()
    else:
        _begin("standard" if id == 8 else PRESETS[id], id == 8)

func _begin(selected: String, capture := false, next_repetition := 1) -> void:
    if active():
        return
    var version := Engine.get_version_info()
    if version.major != 4 or version.minor != 7 or version.patch != 2:
        _show("Benchmark requires the audited Godot 4.7.2 renderer API.")
        return
    snapshot = {"yaw": forest.yaw, "pitch": forest.pitch, "distance": forest.distance,
        "resolution": forest.resolution, "adaptive": forest.adaptive_resolution,
        "scale": viewport.scaling_3d_scale, "msaa": viewport.msaa_3d,
        "taa": viewport.use_taa, "screen_aa": viewport.screen_space_aa,
        "shadows": sun.shadow_enabled, "bloom": environment.glow_enabled,
        "effects_visible": effects.visible, "effects_process": effects.is_processing(),
        "effects_seconds": effects.seconds, "vsync": DisplayServer.window_get_vsync_mode(),
        "cull_mask": forest.camera.cull_mask}
    # Retain the exact adaptive-controller object, including its timers, for restoration.
    forest.resolution = preload("res://scripts/resolution.gd").new()
    forest.resolution.set_enabled(false)
    forest.adaptive_resolution = false
    forest.touches.clear()
    preset = selected
    repetition = next_repetition
    reference = capture
    button.hide()
    progress.show()
    metric_rows.resize(180000)
    _start_run()

func _start_run() -> void:
    run_id = "godot-%d-%d" % [int(Time.get_unix_time_from_system() * 1000.0), Time.get_ticks_usec()]
    started_at = int(Time.get_unix_time_from_system() * 1000.0)
    device = _device()
    refresh = _refresh()
    protocol.start()
    applied = false
    size = Vector2i(viewport.get_texture().get_size())
    surface_size = DisplayServer.window_get_size()
    metric_count = 0
    definitions = {"cpu_effects_ms": _definition("cpu", "Godot effects.gd Time.get_ticks_usec", "before animate(seconds, eye) to after CPU mesh/light updates; excludes RenderingServer execution", "godot.effects.animate")}
    stable_since = Time.get_ticks_usec()
    pipeline_count = -1
    poll_at = 0
    animation_origin = 0
    reference_frames = 0
    if not reference:
        protocol.reason = "process interrupted before completion"
        if not _save() or not _write(ROOT.path_join(run_id).path_join(".pending"), "in progress"):
            _restore()
            _show("Cannot save benchmark initialization record.")
            return
        protocol.reason = null

func _apply() -> void:
    # Apply only after baseline reflection/shader initialization has settled.
    forest.yaw = 0.24
    forest.pitch = 0.12
    forest.distance = 13.0
    forest._update_camera()
    viewport.scaling_3d_scale = 0.65 if preset == "scale_65" else 1.0
    viewport.msaa_3d = Viewport.MSAA_DISABLED if preset == "no_aa" else snapshot.msaa
    viewport.use_taa = false if preset == "no_aa" else snapshot.taa
    viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED if preset == "no_aa" else snapshot.screen_aa
    sun.shadow_enabled = false if preset == "no_shadows" else true
    environment.glow_enabled = false if preset == "no_bloom" else true
    effects.visible = preset != "no_effects"
    effects.set_process(preset != "no_effects")
    for light: OmniLight3D in effects.lights:
        light.visible = preset != "no_effects"
    # Children are Node3D: hide mesh batches and local lights together.
    DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
    observed_vsync = DisplayServer.window_get_vsync_mode()
    RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), preset == "gpu")
    draw_anchor = Engine.get_frames_drawn()
    stable_since = Time.get_ticks_usec()
    applied = true
    animation_origin = Time.get_ticks_usec()
    settings = _settings()

func _process(_delta: float) -> void:
    if not active():
        return
    var now := Time.get_ticks_usec()
    if applied:
        animation = 38.52 if reference else float(now - animation_origin) / 1000000.0
        effects.benchmark_seconds = animation
        RenderingServer.global_shader_parameter_set("benchmark_time", animation)
    if now >= poll_at:
        poll_at = now + 1000000
        var reason := _condition_error(now)
        if not reason.is_empty():
            _invalidate(reason)
            return
        progress.text = "%s · %d/3 · %s · cancel" % [preset, repetition, _phase_text(now)]
    var reason := _surface_error()
    if not reason.is_empty():
        _invalidate(reason)

func _pipeline_compilations() -> int:
    var compiled := 0
    for kind in range(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_CANVAS, RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION + 1):
        compiled += RenderingServer.get_rendering_info(kind)
    return compiled

func _condition_error(now: int) -> String:
    var compiled := _pipeline_compilations()
    if compiled != pipeline_count:
        pipeline_count = compiled
        stable_since = now
        if protocol.phase == Protocol.Phase.MEASURE:
            return "shader pipeline compilation during measurement"
    if applied and _settings() != settings:
        return "benchmark render settings changed"
    if _refresh() != refresh:
        return "display refresh rate changed"
    return ""

func _surface_error() -> String:
    if Vector2i(viewport.get_texture().get_size()) != size or DisplayServer.window_get_size() != surface_size:
        return "Surface dimensions changed"
    if applied and DisplayServer.window_get_vsync_mode() != observed_vsync:
        return "VSync setting changed"
    return ""

func _phase_text(now: int) -> String:
    if not applied or protocol.phase == Protocol.Phase.WAITING:
        return "initializing"
    if reference:
        return "reference"
    if protocol.phase == Protocol.Phase.WARMUP:
        return "warmup %d/30 s" % ((now - protocol.epoch) / 1000000)
    return "measure %d/60 s" % ((now - protocol.anchor) / 1000000)

func _frame() -> void:
    if not active():
        return
    var now := Time.get_ticks_usec()
    # Validate the pixels that were just rendered, including the final frame.
    var reason := _surface_error()
    if not reason.is_empty():
        _invalidate(reason)
        return
    if size != surface_size and DisplayServer.get_name() != "headless":
        _invalidate("viewport pixels differ from native Surface size")
        return
    var ready := Engine.get_frames_drawn() - draw_anchor >= 120 and now - stable_since >= 2000000
    if not applied:
        if ready:
            _apply()
        return
    if reference:
        reference_frames += 1
        if ready and reference_frames >= 120:
            _capture()
        return
    # The last draw may compile a pipeline or change settings after _process's
    # one-second poll. Recheck once before accepting the final sample.
    if protocol.phase == Protocol.Phase.MEASURE and now - protocol.anchor >= Protocol.MEASURE_US:
        reason = _condition_error(now)
        if not reason.is_empty():
            _invalidate(reason)
            return
    if protocol.sample(now, ready, animation, effects.raw_update_ms if effects.is_processing() else 0.0):
        animation_origin = now
    if preset == "gpu" and protocol.phase == Protocol.Phase.MEASURE and protocol.count > 0:
        _observe()
    if protocol.phase == Protocol.Phase.FINISHED:
        _finish()

func _observe() -> void:
    for spec in [["viewport_cpu", "cpu", "RenderingServer.viewport_get_measured_render_time_cpu", "root viewport rendering CPU; excludes script _process and broader engine work"],
            ["viewport_gpu", "gpu_frame", "RenderingServer.viewport_get_measured_render_time_gpu", "root viewport GPU rendering; not whole device frame or presentation"]]:
        var value: float = RenderingServer.viewport_get_measured_render_time_cpu(viewport.get_viewport_rid()) if spec[0] == "viewport_cpu" else RenderingServer.viewport_get_measured_render_time_gpu(viewport.get_viewport_rid())
        if is_finite(value) and value > 0.0:
            if metric_count >= metric_rows.size():
                protocol.stop("metric capacity exceeded")
                return
            if not definitions.has(spec[0]):
                definitions[spec[0]] = _definition(spec[1], spec[2], spec[3], "godot." + spec[0])
            metric_rows[metric_count] = [str(metric_count), protocol.count - 1, spec[0], value]
            metric_count += 1

func _definition(kind: String, source: String, scope: String, scope_id: String) -> Dictionary:
    return {"kind": kind, "unit": "ms", "source": source, "scope": scope, "scope_id": scope_id}

func _settings() -> Dictionary:
    return {"camera": [forest.yaw, forest.pitch, forest.distance], "camera_fov_deg": forest.camera.fov,
        "msaa_samples": [1, 2, 4, 8][viewport.msaa_3d], "taa": viewport.use_taa,
        "fxaa": viewport.screen_space_aa != Viewport.SCREEN_SPACE_AA_DISABLED,
        "shadows": sun.shadow_enabled, "bloom": environment.glow_enabled,
        "effects": effects.visible and effects.is_processing(), "pipeline": RenderingServer.get_current_rendering_method(),
        "shadow_distance_m": sun.directional_shadow_max_distance,
        "shadow_cascades": 4, "shadow_atlas": ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size"),
        "ssao_requested": environment.ssao_enabled, "fog": environment.fog_enabled,
        "bloom_intensity": environment.glow_intensity, "tonemap_mode": environment.tonemap_mode,
        "ambient_energy": environment.ambient_light_energy, "sky_energy": environment.background_energy_multiplier,
        "fog_density": environment.fog_density, "shadow_blur": sun.shadow_blur,
        "sun_angular_distance": sun.light_angular_distance,
        "shadow_filter_quality": ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality"),
        "scaling_3d_mode": viewport.scaling_3d_mode,
        "scale": viewport.scaling_3d_scale, "vsync_reported": DisplayServer.window_get_vsync_mode()}

func _device() -> Dictionary:
    var result := {"brand": null, "model": null, "android": null, "fingerprint": null, "thermal_status": null,
        "display_mode_size": null, "captured_at": int(Time.get_unix_time_from_system() * 1000.0)}
    if OS.get_name() == "Android":
        var android_build = JavaClassWrapper.wrap("android.os.Build")
        var version = JavaClassWrapper.wrap("android.os.Build$VERSION")
        result.brand = android_build.BRAND
        result.model = android_build.MODEL
        result.fingerprint = android_build.FINGERPRINT
        result.android = version.RELEASE
        if Engine.has_singleton("AndroidRuntime"):
            var activity = Engine.get_singleton("AndroidRuntime").getActivity()
            if activity != null:
                var display = activity.getWindowManager().getDefaultDisplay()
                var mode = display.getMode()
                result.display_mode_size = [mode.getPhysicalWidth(), mode.getPhysicalHeight()]
                result.display_rotation = display.getRotation()
            if version.SDK_INT >= 29 and activity != null:
                var power = activity.getSystemService("power")
                if power != null:
                    var thermal = power.getCurrentThermalStatus()
                    if JavaClassWrapper.get_exception() == null:
                        result.thermal_status = thermal
                    else:
                        result.thermal_error = "PowerManager thermal status unavailable (Java exception)"
    return result

func _render_size() -> Array:
    # Match the pinned renderer's float32 multiplication and integer truncation.
    # roundi() misreports a 720px target at 65% by one pixel.
    var scaled := PackedFloat32Array([size.x * viewport.scaling_3d_scale, size.y * viewport.scaling_3d_scale])
    return [int(clampf(scaled[0], 1.0, 16384.0)), int(clampf(scaled[1], 1.0, 16384.0))]

func _metadata() -> Dictionary:
    var engine: Dictionary = build.engine.duplicate(true)
    engine.version = Engine.get_version_info().string
    engine.build = "debug" if OS.is_debug_build() else "release"
    var backend := RenderingServer.get_current_rendering_driver_name()
    var api: String = {"vulkan": "Vulkan", "opengl3": "OpenGL ES" if OS.get_name() == "Android" else "OpenGL"}.get(backend, "unavailable")
    var gpu := RenderingServer.get_video_adapter_name()
    return {"schema_version": "1.0.0", "run_id": run_id, "preset_id": preset,
        "repetition": repetition, "valid": protocol.valid, "invalid_reason": protocol.reason,
        "started_at": started_at, "warmup_seconds": 30, "measure_seconds": 60,
        "engine": engine, "device": device, "scene": build.scene,
        "environment": {"backend": api, "surface_size": [surface_size.x, surface_size.y],
            "render_size": _render_size(),
            "render_size_source": "Godot 4.7.2 renderer_viewport.cpp: float32 multiply, clamp 1..16384, truncate to int; not attachment readback",
            "dynamic_resolution": false, "vsync_requested": "off" if applied else "engine_default",
            "presentation_mode": null, "refresh_hz": _refresh(), "refresh_limited_possible": true,
            "gpu_profiling": (preset == "gpu") if applied else true, "gpu": gpu if gpu != "" else null,
            "driver": null, "api_version": RenderingServer.get_video_adapter_api_version(),
            "thermal_status": device.thermal_status},
        "settings": _settings(), "metrics": definitions,
        "limitations": ["Application frame_post_draw callback intervals, not display presentation FPS.",
            "Godot exposes no public completion flag for UPDATE_ONCE reflection; readiness uses 120 drawn frames and stable pipeline counters, followed by 30 seconds warmup.",
            "Viewport timers expose latest values without sample identity; observations can repeat. They are not unique GPU frame samples.",
            "Viewport GPU covers the root viewport only; no public per-pass GPU timestamps collected.",
            "Actual swapchain presentation mode and driver version unavailable; VSync off request may remain refresh limited.",
            "Thermal status captured before initialization; not continuously sampled.",
            "No-effects hides six batches and local lights and skips their CPU updates; vegetation wind remains active.",
            "Engine pipelines and shadow settings differ; compare reference screenshots before asserting visual equivalence."]}

func _refresh() -> Variant:
    var hz := DisplayServer.screen_get_refresh_rate()
    return hz if hz > 0.0 else null

func _invalidate(message: String) -> void:
    if active():
        protocol.stop(message)
        _finish()

func _notification(what: int) -> void:
    if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
        _invalidate("application paused or window focus lost")

func _write(path: String, text: String) -> bool:
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        return false
    file.store_string(text)
    file.flush()
    return file.get_error() == OK

func _save() -> bool:
    var path := ROOT.path_join(run_id)
    if DirAccess.make_dir_recursive_absolute(path) != OK:
        return false
    if not _write(path.path_join(".pending"), "incomplete"):
        return false
    var metadata := _metadata()
    var summary := {}
    for key in ["schema_version", "run_id", "preset_id", "valid", "invalid_reason"]:
        summary[key] = metadata[key]
    summary.application = protocol.statistics()
    summary.presentation_fps = null
    var frames := PackedStringArray(["frame_index,elapsed_ms,interval_ms,animation_seconds,cpu_scene_ms,cpu_effects_ms,cpu_submit_ms,cpu_wait_ms"])
    for i in protocol.count:
        var offset := i * 4
        frames.append("%d,%.6f,%.6f,%.9f,,%.6f,," % [i, protocol.frames[offset], protocol.frames[offset + 1], protocol.frames[offset + 2], protocol.frames[offset + 3]])
    var metrics := PackedStringArray(["sample_id,observed_frame,metric,value_ms"])
    for i in metric_count:
        var row: Array = metric_rows[i]
        metrics.append("%s,%d,%s,%.9f" % row)
    if not (_write(path.path_join("metadata.json"), JSON.stringify(metadata, "  ")) and
            _write(path.path_join("summary.json"), JSON.stringify(summary, "  ")) and
            _write(path.path_join("frames.csv"), "\n".join(frames) + "\n") and
            _write(path.path_join("metrics.csv"), "\n".join(metrics) + "\n")):
        return false
    return DirAccess.remove_absolute(path.path_join(".pending")) == OK

func _finish() -> void:
    var completed := protocol.valid
    var message := "Completed" if completed else "Invalid: " + str(protocol.reason)
    var saved := _save()
    _restore()
    if not saved:
        _show("Export write failed; incomplete run excluded. Check available storage.")
        return
    if completed and repetition < 3:
        repetition += 1
        var selected := preset
        # Each repetition starts from the original baseline, not the last preset.
        var next := repetition
        _begin(selected, false, next)
    else:
        _show(message + "\nResults saved locally. Use Benchmark → Export ZIP.")

func _restore() -> void:
    if snapshot.is_empty():
        return
    forest.yaw = snapshot.yaw
    forest.pitch = snapshot.pitch
    forest.distance = snapshot.distance
    forest._update_camera()
    forest.touches.clear()
    forest.resolution = snapshot.resolution
    forest.adaptive_resolution = snapshot.adaptive
    viewport.scaling_3d_scale = snapshot.scale
    viewport.msaa_3d = snapshot.msaa
    viewport.use_taa = snapshot.taa
    viewport.screen_space_aa = snapshot.screen_aa
    sun.shadow_enabled = snapshot.shadows
    environment.glow_enabled = snapshot.bloom
    effects.visible = snapshot.effects_visible
    effects.set_process(snapshot.effects_process)
    effects.seconds = snapshot.effects_seconds
    effects.benchmark_seconds = -1.0
    for light: OmniLight3D in effects.lights:
        light.visible = true
    forest.camera.cull_mask = snapshot.cull_mask
    DisplayServer.window_set_vsync_mode(snapshot.vsync)
    RenderingServer.global_shader_parameter_set("benchmark_time", -1.0)
    RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), true)
    snapshot.clear()
    metric_rows.clear()
    protocol.frames.clear()
    button.show()
    progress.hide()

func _show(message: String) -> void:
    (dialog.get_node("Report") as RichTextLabel).text = message
    dialog.popup_centered()

func _recover() -> void:
    for dir in DirAccess.get_directories_at(ROOT):
        var path := ROOT.path_join(dir)
        if not FileAccess.file_exists(path.path_join(".pending")):
            continue
        var m = JSON.parse_string(FileAccess.get_file_as_string(path.path_join("metadata.json")))
        var s = JSON.parse_string(FileAccess.get_file_as_string(path.path_join("summary.json")))
        if m is Dictionary and s is Dictionary and m.get("valid") == false and s.get("valid") == false and m.get("run_id") == s.get("run_id") and str(m.get("invalid_reason")).begins_with("process interrupted") and str(s.get("invalid_reason")).begins_with("process interrupted"):
            if DirAccess.remove_absolute(path.path_join(".pending")) != OK:
                push_error("Cannot recover incomplete benchmark marker: " + path)

func _results() -> void:
    var text := PackedStringArray()
    for dir in DirAccess.get_directories_at(ROOT):
        var path := ROOT.path_join(dir)
        if FileAccess.file_exists(path.path_join(".pending")):
            text.append("Interrupted or incomplete run: " + dir)
        elif FileAccess.file_exists(path.path_join("summary.json")):
            text.append(FileAccess.get_file_as_string(path.path_join("summary.json")))
    _show("\n\n".join(text) if not text.is_empty() else "No results yet.")

func _capture() -> void:
    var path := ROOT.path_join("references")
    var ok := DirAccess.make_dir_recursive_absolute(path) == OK
    var base := path.path_join(run_id)
    if ok:
        ok = viewport.get_texture().get_image().save_png(base + ".png") == OK
    if ok:
        var metadata := _metadata()
        metadata.reference_animation_seconds = 38.52
        metadata.reference_only = true
        ok = _write(base + ".json", JSON.stringify(metadata, "  "))
    _restore()
    _show("Reference saved for export." if ok else "Reference capture failed.")

func _export() -> void:
    var error := DisplayServer.file_dialog_show("Save benchmark ZIP", "", "forest-benchmark.zip", false,
        DisplayServer.FILE_DIALOG_MODE_SAVE_FILE, ["*.zip;Benchmark ZIP;application/zip"], _selected)
    if error != OK:
        _show("Native file dialog unavailable: " + error_string(error))

func _selected(status: bool, paths: PackedStringArray, _filter: int) -> void:
    if not status or paths.is_empty():
        return
    var zip := ZIPPacker.new()
    var temporary := "user://benchmark-export.zip"
    if zip.open(temporary) != OK:
        _show("Cannot create export ZIP.")
        return
    var ok := _zip_dir(zip, ROOT, "")
    if zip.close() != OK:
        ok = false
    if ok:
        var output := FileAccess.open(paths[0], FileAccess.WRITE)
        if output == null:
            ok = false
        else:
            output.store_buffer(FileAccess.get_file_as_bytes(temporary))
            output.flush()
            ok = output.get_error() == OK
    DirAccess.remove_absolute(temporary)
    _show("Export saved." if ok else "Export failed; local results retained.")

func _zip_dir(zip: ZIPPacker, path: String, prefix: String) -> bool:
    for dir in DirAccess.get_directories_at(path):
        var next := path.path_join(dir)
        if not FileAccess.file_exists(next.path_join(".pending")):
            if not _zip_dir(zip, next, prefix.path_join(dir)):
                return false
    for file in DirAccess.get_files_at(path):
        if zip.start_file(prefix.path_join(file).trim_prefix("/")) != OK:
            return false
        if zip.write_file(FileAccess.get_file_as_bytes(path.path_join(file))) != OK:
            return false
        if zip.close_file() != OK:
            return false
    return true
