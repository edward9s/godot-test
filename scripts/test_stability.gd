extends SceneTree
## Vulkan soak tests: --script scripts/test_stability.gd -- effects 3600 mobile
## or --script scripts/test_stability.gd -- scene 180 forward_plus
const Effects := preload("res://scripts/effects.gd")
var effects: Node3D
var scene: Node3D
var frame := 0
var limit := 0
var mode := ""
var handles: Array[RID] = []
var memory := -1.0
var buffers := -1.0

func _initialize() -> void:
    call_deferred("_setup")

func _setup() -> void:
    var args := OS.get_cmdline_user_args()
    assert(args.size() == 3)
    mode = args[0]
    limit = int(args[1])
    assert(mode in ["effects", "scene"] and limit >= 180)
    assert(DisplayServer.get_name() != "headless", "Stability tests require actual Vulkan rendering")
    assert(args[2] in ["forward_plus", "mobile"])
    assert(RenderingServer.get_current_rendering_method() == args[2], "Wrong renderer for stability test")
    root.size = Vector2i(640, 360) if mode == "scene" else Vector2i(320, 180)
    if mode == "scene":
        scene = load("res://scenes/main.tscn").instantiate()
        root.add_child(scene)
        effects = scene.get_node("Effects")
        assert(root.use_taa == (args[2] == "forward_plus"))
        assert(scene.get_node("WorldEnvironment").environment.ssao_enabled == (args[2] == "forward_plus"))
    else:
        var camera := Camera3D.new()
        root.add_child(camera)
        camera.position = Vector3(3.07, 3.16, 9.54)
        camera.look_at(Vector3(0, 1.6, -3))
        effects = Effects.new()
        root.add_child(effects)
    effects.set_process(false)
    effects.animate(0.0, root.get_camera_3d().global_position)
    for batch in effects.batches:
        handles.append(batch.mesh.get_rid())
    process_frame.connect(_step)

func _step() -> void:
    if scene != null:
        scene.yaw += 0.001
        scene._update_camera()
    var time := frame * (0.25 if mode == "scene" else 1.0 / 60.0)
    effects.animate(time, root.get_camera_3d().global_position)
    for i in range(6):
        assert(effects.batches[i].mesh.get_rid() == handles[i])
        assert(effects.batches[i].mesh.get_surface_count() == 1)
    if frame == 120:
        memory = Performance.get_monitor(Performance.MEMORY_STATIC)
        buffers = Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED)
    if frame % 300 == 0 or frame == limit - 1:
        print("Stability ", mode, " frame=", frame, " memory=", Performance.get_monitor(Performance.MEMORY_STATIC),
            " buffers=", Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED))
    frame += 1
    if frame == limit:
        # Allow bounded renderer/font caches after warm-up, not cumulative growth.
        assert(Performance.get_monitor(Performance.MEMORY_STATIC) - memory < 16 * 1024 * 1024)
        assert(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) - buffers < 16 * 1024 * 1024)
        assert(_check_uploads())
        print("Stability passed: ", mode, " ", frame, " frames, fixed meshes, bounded memory, matching GPU data; renderer=", RenderingServer.get_current_rendering_method())
        quit()

func _check_uploads() -> bool:
    # Read the actual GPU buffers after many updates, including water normals/UVs.
    for batch in effects.batches:
        var arrays: Array = batch.mesh.surface_get_arrays(0)
        var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
        var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
        var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
        for i in range(vertices.size()):
            assert(vertices[i].distance_to(batch.vertices[i]) < 0.0001)
            assert(uvs[i].distance_to(batch.uvs[i]) < 0.0001)
            for channel in range(4):
                assert(absf(colors[i][channel] - clampf(batch.colors[i][channel], 0.0, 1.0)) < 1.01 / 255.0)
        if batch.lit:
            var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
            var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
            for i in range(vertices.size()):
                assert(normals[i].distance_to(batch.normals[i]) < 0.001)
                assert(absf(tangents[i * 4 + 3] + 1.0) < 0.001)
                for axis in range(3):
                    assert(absf(tangents[i * 4 + axis] - batch.tangents[i * 4 + axis]) < 0.001)
    return true
