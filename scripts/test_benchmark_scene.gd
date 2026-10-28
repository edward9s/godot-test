extends SceneTree
## Functional export test. Synthetic timings are explicitly marked in the metadata.
var scene: Node
var controller: Node
var frames := 0
func _initialize() -> void:
    call_deferred("_start")
func _start() -> void:
    scene = load("res://scenes/main.tscn").instantiate()
    root.add_child(scene)
    controller = scene.benchmark
    # Test controller directly without waiting 90 seconds per preset.
    RenderingServer.frame_post_draw.disconnect(controller._frame)
    controller.set_process(false)
    for preset: String in controller.PRESETS:
        var original_scale: float = root.scaling_3d_scale
        var original_camera: Vector3 = scene.camera.position
        controller._begin(preset)
        controller._apply()
        assert(not scene.resolution.enabled)
        assert(scene.get_node("WarmSun").shadow_enabled == (preset != "no_shadows"))
        assert(is_equal_approx(root.scaling_3d_scale, 0.65 if preset == "scale_65" else 1.0))
        controller.protocol.sample(100, true, 0.0, 0.0)
        controller.protocol.sample(30000100, true, 30.0, 0.0)
        for i in 600:
            controller.protocol.sample(30100100 + i * 100000, true, 30.1 + i * 0.1, 0.1)
        var metadata: Dictionary = controller._metadata()
        metadata.test_data = true
        # The headless display has no native Surface (0x0). Explicit fixture pixels only.
        if DisplayServer.get_name() == "headless":
            metadata.environment.surface_size = [controller.size.x, controller.size.y]
        metadata.limitations.append("SYNTHETIC integration fixture; no hardware performance claim.")
        assert(controller._save())
        var folder: String = controller.ROOT.path_join(controller.run_id)
        assert(controller._write(folder.path_join("metadata.json"), JSON.stringify(metadata)))
        controller._restore()
        assert(is_equal_approx(root.scaling_3d_scale, original_scale))
        assert(scene.camera.position.is_equal_approx(original_camera))
        assert(not controller.active() and scene.get_node("Effects").benchmark_seconds < 0.0)
    controller._begin("standard", false, 2)
    assert(controller.repetition == 2)
    var interrupted: String = controller.ROOT.path_join(controller.run_id)
    assert(FileAccess.file_exists(interrupted.path_join(".pending")))
    controller._restore() # Simulate a new process before the final result write.
    var pending: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(interrupted.path_join("metadata.json")))
    pending.test_data = true
    pending.environment.surface_size = pending.environment.render_size
    assert(controller._write(interrupted.path_join("metadata.json"), JSON.stringify(pending)))
    controller._recover()
    assert(not FileAccess.file_exists(interrupted.path_join(".pending")))
    assert(not pending.valid and pending.repetition == 2 and str(pending.invalid_reason).begins_with("process interrupted"))
    print("Benchmark scene passed: eight presets, export and restoration (SYNTHETIC)")
    scene.queue_free()
    await process_frame
    quit()
