extends SceneTree
## Exercise the imported scene: the glTF alone does not activate vertex tints.
var surfaces := 0
var foliage := 0

func _initialize() -> void:
    call_deferred("_test")

func _test() -> void:
    var scene := load("res://scenes/main.tscn").instantiate() as Node3D
    root.add_child(scene)
    scene.get_node("Effects").set_process(false)
    _inspect(scene)
    assert(surfaces > 100 and foliage > 10)
    assert(root.get_camera_3d() != null)
    assert(ProjectSettings.get_setting("rendering/renderer/rendering_method") == "forward_plus")
    assert(ProjectSettings.get_setting("rendering/renderer/rendering_method.mobile") == "mobile")
    var forward := RenderingServer.get_current_rendering_method() == "forward_plus"
    assert(root.use_taa == forward)
    assert(scene.get_node("WorldEnvironment").environment.ssao_enabled == forward)
    var sun := scene.get_node("WarmSun") as DirectionalLight3D
    assert(is_equal_approx(sun.light_angular_distance, 1.06 if forward else 0.0))
    assert(sun.shadow_enabled and sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS)
    assert(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size.mobile") == 4096)
    assert(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality.mobile") == 2)
    print("Scene passed: imported PBR tints, animated double-sided shadow casters and orbit camera")
    scene.queue_free()
    quit()

func _inspect(node: Node) -> void:
    if node is MeshInstance3D and not node.get_parent().name == "Effects":
        var mesh := node as MeshInstance3D
        if mesh.name.begins_with("Leaves_") or mesh.name.begins_with("Canopy_"):
            foliage += 1
            assert(mesh.get_active_material(0) is ShaderMaterial)
            assert(mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED)
            assert(mesh.extra_cull_margin >= 0.12 - 0.00001)
        else:
            surfaces += 1
            var material := mesh.get_active_material(0) as StandardMaterial3D
            assert(material.vertex_color_use_as_albedo and not material.vertex_color_is_srgb)
            assert(material.normal_enabled and material.ao_enabled)
    for child in node.get_children():
        _inspect(child)
