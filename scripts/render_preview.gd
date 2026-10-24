extends SceneTree
## Actual Forward+ framebuffer capture: godot --path . --script scripts/render_preview.gd -- output.png 0.3
func _initialize() -> void:
    call_deferred("_render")

func _render() -> void:
    var args := OS.get_cmdline_user_args()
    assert(args.size() == 2, "Expected output PNG path and scene time")
    var scene := load("res://scenes/main.tscn").instantiate() as Node3D
    root.add_child(scene)
    var effects := scene.get_node("Effects")
    effects.set_process(false)
    effects.animate(float(args[1]), scene.camera.global_position)
    # Let sky radiance, glow and TAA history converge before reading the framebuffer.
    for frame in range(48):
        await process_frame
    await RenderingServer.frame_post_draw
    var image := root.get_texture().get_image()
    var result := image.save_jpg(args[0], 0.92) if args[0].ends_with(".jpg") else image.save_png(args[0])
    assert(result == OK)
    print("Captured ", args[0])
    quit()
