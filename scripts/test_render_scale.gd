extends SceneTree
## Exercise actual Vulkan buffer resizing and the native-resolution comparison button.
func _initialize() -> void:
    call_deferred("_test")

func _test() -> void:
    assert(DisplayServer.get_name() != "headless", "Resolution rendering needs a Vulkan display")
    root.size = Vector2i(640, 360)
    var scene := load("res://scenes/main.tscn").instantiate() as Node3D
    root.add_child(scene)
    var enabled: bool = scene.resolution.enabled
    assert(enabled == (RenderingServer.get_current_rendering_method() == "mobile"))
    scene.get_node("Effects").set_process(false)
    scene.get_node("Effects").animate(0.3, scene.camera.global_position)
    scene.set_process(false)
    for scale in [1.0, 0.65, 1.0]:
        root.scaling_3d_scale = scale
        for frame in range(8):
            await process_frame
        await RenderingServer.frame_post_draw
        var image := root.get_texture().get_image()
        assert(image.get_width() == 640 and image.get_height() == 360)
        var low := 1.0
        var high := 0.0
        # Sample the forest below the HUD, so text alone cannot pass this check.
        for y in range(120, 360, 40):
            for x in range(40, 640, 40):
                var luminance := image.get_pixel(x, y).get_luminance()
                low = minf(low, luminance)
                high = maxf(high, luminance)
        assert(high - low > 0.1, "Scene framebuffer is blank after resizing")
    scene.fps_button.pressed.emit()
    assert(scene.resolution.enabled != enabled and root.scaling_3d_scale == 1.0)
    scene.fps_button.pressed.emit()
    assert(scene.resolution.enabled == enabled and root.scaling_3d_scale == 1.0)
    print("Render scale passed: native/scaled/native forest framebuffers and HUD toggle; renderer=",
        RenderingServer.get_current_rendering_method())
    scene.queue_free()
    quit()
