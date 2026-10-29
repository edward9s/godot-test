extends SceneTree
## Exercise the actual frame callback without loading scene assets or writing results.
class Probe extends "res://benchmark/controller.gd":
    var compiled := 10
    var current_settings := {"shadows": true}
    var current_refresh := 60.0
    var failure := ""
    var finished := false

    func _pipeline_compilations() -> int:
        return compiled

    func _settings() -> Dictionary:
        return current_settings

    func _refresh() -> Variant:
        return current_refresh

    func _invalidate(message: String) -> void:
        failure = message
        protocol.stop(message)

    func _finish() -> void:
        finished = true

func _probe() -> Probe:
    var probe := Probe.new()
    probe.viewport = root
    probe.effects = Node.new()
    probe.size = Vector2i(root.get_texture().get_size())
    probe.surface_size = DisplayServer.window_get_size()
    probe.observed_vsync = DisplayServer.window_get_vsync_mode()
    probe.snapshot = {"active": true}
    probe.applied = true
    probe.settings = probe.current_settings.duplicate()
    probe.refresh = probe.current_refresh
    probe.pipeline_count = probe.compiled
    probe.protocol.start()
    probe.protocol.phase = probe.Protocol.Phase.MEASURE
    var now := Time.get_ticks_usec()
    probe.protocol.anchor = now - probe.Protocol.MEASURE_US
    probe.protocol.previous = now - 100000
    probe.stable_since = now - 3000000
    probe.draw_anchor = Engine.get_frames_drawn() - 120
    # The ordinary one-second poll has not run again before this final draw.
    probe.poll_at = now + 1000000
    return probe

func _initialize() -> void:
    call_deferred("_test")

func _test() -> void:
    for change in ["pipeline", "settings", "refresh", "surface", "none"]:
        var probe := _probe()
        match change:
            "pipeline": probe.compiled += 1
            "settings": probe.current_settings.shadows = false
            "refresh": probe.current_refresh = 120.0
            "surface": probe.size.x += 1
        probe._frame()
        if change == "none":
            assert(probe.finished and probe.protocol.valid and probe.failure.is_empty())
        else:
            assert(not probe.finished and not probe.protocol.valid)
            var expected := {"pipeline": "shader pipeline compilation during measurement",
                "settings": "benchmark render settings changed", "refresh": "display refresh rate changed",
                "surface": "Surface dimensions changed"}
            assert(probe.failure == expected[change])
        probe.effects.free()
        probe.free()
    print("Benchmark boundary passed: final-frame compilation, settings, refresh and Surface invalidation")
    quit()
