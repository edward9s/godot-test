extends SceneTree
const Resolution := preload("res://scripts/resolution.gd")

func _initialize() -> void:
    var resolution := Resolution.new()
    # A slow CPU or VSync delay with no GPU timing must not reduce image quality.
    resolution.set_enabled(true)
    for i in range(300):
        assert(resolution.sample(0.1, 0.0) == 1.0)
    # Sustained GPU overload stays within the source renderer's lower bound.
    for i in range(300):
        var scale := resolution.sample(0.1, 40.0)
        assert(scale >= 0.65 and scale <= 1.0)
    assert(is_equal_approx(resolution.scale(), 0.65))
    # Hysteresis holds resolution through timing noise near the frame budget.
    for i in range(300):
        assert(is_equal_approx(resolution.sample(0.1, 16.0), 0.65))
    # GPU headroom restores the original full resolution.
    for i in range(300):
        resolution.sample(0.1, 8.0)
    assert(resolution.scale() == 1.0)
    # Native mode stays native even if the GPU is slow.
    resolution.set_enabled(false)
    for i in range(300):
        assert(resolution.sample(0.1, 100.0) == 1.0)
    # Ignore startup pipeline compilation and queued timestamps after enabling.
    resolution.set_enabled(true)
    for i in range(10):
        assert(resolution.sample(0.1, 100.0) == 1.0)
    print("Resolution passed: GPU budget, bounds, recovery, hysteresis, native mode and unavailable timestamps")
    quit()
