extends SceneTree
## Headless CPU benchmark only. This does not measure GPU time or tablet FPS.
const Effects := preload("res://scripts/effects.gd")
const FRAMES := 324 # A complete 5.4-second explosion cycle at 60 updates/second.

func _initialize() -> void:
    call_deferred("_bench")

func _bench() -> void:
    assert(DisplayServer.get_name() == "headless", "Use --headless for the CPU benchmark")
    var effects := Effects.new()
    root.add_child(effects)
    effects.set_process(false)
    var eye := Vector3(3.07, 3.16, 9.54)
    for i in range(30):
        effects.animate(float(i) / 60.0, eye)
    var samples: Array[float] = []
    for run in range(5):
        var start := Time.get_ticks_usec()
        for i in range(FRAMES):
            effects.animate(float(i) / 60.0, eye)
        samples.append(float(Time.get_ticks_usec() - start) / FRAMES / 1000.0)
    print("Benchmark effects: ms/update samples=", samples)
    samples.sort()
    print("Benchmark effects: median=", samples[2], " ms/update; CPU only, not FPS")
    effects.queue_free()
    quit()
