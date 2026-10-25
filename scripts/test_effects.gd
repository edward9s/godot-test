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
            assert(effects.materials[kind].shader == Effects.SHADERS[kind])
            var batch = effects.batches[kind]
            assert(batch.mesh.get_surface_count() == 1)
            var vertices: PackedVector3Array = batch.vertices
            assert(vertices.size() == Effects.COUNTS[kind] * 4)
            var indices: PackedInt32Array = batch.indices
            assert(indices.size() == Effects.COUNTS[kind] * 6)
            for vertex in vertices:
                assert(vertex.is_finite())
            for i in range(0, indices.size(), 3):
                assert((vertices[indices[i + 1]] - vertices[indices[i]]).cross(
                    vertices[indices[i + 2]] - vertices[indices[i]]).length() > 0.000001)
        assert(effects.lights[0].light_energy > 0.0)
    effects.animate(1.8, eye)
    var before := effects.batches[0].vertices.duplicate() as PackedVector3Array
    effects.animate(1.8, eye)
    assert(before == effects.batches[0].vertices)
    effects.animate(1.9, eye)
    assert(before != effects.batches[0].vertices)
    # Fully discarded effects must not submit a draw or upload stale geometry.
    effects.animate(3.0, eye)
    for kind in [Effects.Kind.BLAST, Effects.Kind.LIGHTNING]:
        assert(not effects.instances[kind].visible)
        assert(effects.batches[kind].cursor == 0)
    effects.animate(0.3, eye)
    for kind in [Effects.Kind.BLAST, Effects.Kind.LIGHTNING]:
        assert(effects.instances[kind].visible)
        assert(effects.batches[kind].cursor == effects.batches[kind].vertices.size())
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
        var positions: PackedVector3Array = effects.batches[kind].vertices
        var indices: PackedInt32Array = effects.batches[kind].indices
        for i in range(6):
            var p: Array = reference[kind][winding[i]]
            assert(positions[indices[i]].distance_to(Vector3(p[0], p[1], p[2])) < 0.001)
    effects.queue_free()
    print("Effects passed: topology, finite geometry, loop boundaries, determinism, timing, seeds and sites")
    quit()
