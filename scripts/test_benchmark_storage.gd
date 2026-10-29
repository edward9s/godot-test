extends SceneTree
## Run with an isolated XDG_DATA_HOME so this exercises an actual first launch.
const Controller := preload("res://benchmark/controller.gd")

func _initialize() -> void:
    assert(not DirAccess.dir_exists_absolute(Controller.ROOT), "Storage test requires a fresh user profile")
    call_deferred("_test")

func _test() -> void:
    var scene: Node = load("res://scenes/main.tscn").instantiate()
    root.add_child(scene)
    var controller: Node = scene.benchmark
    assert(DirAccess.dir_exists_absolute(Controller.ROOT))
    assert(DirAccess.get_directories_at(Controller.ROOT).is_empty())
    var zip := ZIPPacker.new()
    assert(zip.open("user://first-launch.zip") == OK)
    assert(controller._zip_dir(zip, Controller.ROOT, ""))
    assert(zip.close() == OK)
    print("Benchmark storage passed: fresh launch, empty storage and export traversal")
    scene.queue_free()
    await process_frame
    quit()
