extends SceneTree
## Run after import: godot --headless --path . --script scripts/test_effects.gd
const Effects := preload("res://scripts/effects.gd")

func _initialize() -> void:
    call_deferred("_test")

func _test() -> void:
    var effects := Effects.new()
    root.add_child(effects)
    effects.set_process(false)
    var eye := Vector3(3.07, 3.16, 9.54)
    for time in [0.0, 0.12, 0.3, 1.8, 4.8, 5.4, 10.8, 108.0]:
        effects.animate(time, eye)
        for kind in range(6):
            var mesh: ImmediateMesh = effects.meshes[kind]
            assert(mesh.get_surface_count() == 1)
            var arrays := mesh.surface_get_arrays(0)
            var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
            assert(vertices.size() == Effects.COUNTS[kind] * 6)
            for vertex in vertices:
                assert(vertex.is_finite())
            for i in range(0, vertices.size(), 3):
                assert((vertices[i + 1] - vertices[i]).cross(vertices[i + 2] - vertices[i]).length() > 0.000001)
        assert(effects.lights[0].light_energy > 0.0)
    effects.animate(1.8, eye)
    var before := effects.meshes[0].surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array
    effects.animate(1.8, eye)
    assert(before == effects.meshes[0].surface_get_arrays(0)[Mesh.ARRAY_VERTEX])
    effects.animate(1.9, eye)
    assert(before != effects.meshes[0].surface_get_arrays(0)[Mesh.ARRAY_VERTEX])
    # At idle, explosion and lightning particles must be fully transparent.
    effects.animate(3.0, eye)
    for kind in [Effects.Kind.BLAST, Effects.Kind.LIGHTNING]:
        var colors: PackedColorArray = effects.meshes[kind].surface_get_arrays(0)[Mesh.ARRAY_COLOR]
        for color in colors:
            assert(color.a < 0.003)
    assert(Effects.lightning_pulse(0.12) > 0.99)
    assert(Effects.lightning_pulse(1.8) < 0.003)
    assert(absf(Effects.blast_age(5.4)) < 0.000001)
    # Confirm 32-bit source seeds and source sites, independent of the port.
    assert(absf(Effects.random(1) - 0.40834903717041016) < 0.000001)
    assert(Effects.origin(Effects.Kind.FIRE).is_equal_approx(Vector3(-3.2, 0.0, 3.1)))
    for a in [0, 1, 2, 3, 4]:
        for b in range(a + 1, 5):
            assert(Effects.origin(a).distance_to(Effects.origin(b)) > 3.0)
    # First source quad per batch, exported independently by the original C++
    # effectMeshes(0.3f, {3.07f, 3.16f, 9.54f}); account for Godot winding.
    var reference: Array = JSON.parse_string(FileAccess.get_file_as_string("res://scripts/effects_reference.json"))
    effects.animate(0.3, eye)
    var winding := [0, 3, 2, 0, 2, 1]
    for kind in range(6):
        var positions: PackedVector3Array = effects.meshes[kind].surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
        for i in range(6):
            var p: Array = reference[kind][winding[i]]
            assert(positions[i].distance_to(Vector3(p[0], p[1], p[2])) < 0.001)
    effects.queue_free()
    print("Effects passed: topology, finite geometry, loop boundaries, determinism, timing, seeds and sites")
    quit()
