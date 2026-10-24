extends RefCounted
## Match Filament's 65–100% range, using GPU time rather than VSync/CPU delays.
const MIN_LEVEL := 13
const MAX_LEVEL := 20
var enabled := false
var level := MAX_LEVEL
var wait := 2.0
var elapsed := 0.0
var total := 0.0
var samples := 0

func set_enabled(active: bool) -> void:
    enabled = active
    level = MAX_LEVEL
    wait = 2.0
    elapsed = 0.0
    total = 0.0
    samples = 0

func scale() -> float:
    return float(level) / MAX_LEVEL

func sample(delta: float, gpu_ms: float) -> float:
    assert(is_finite(delta) and delta >= 0.0)
    assert(is_finite(gpu_ms) and gpu_ms >= 0.0)
    if not enabled:
        return 1.0
    wait -= delta
    if wait > 0.0 or gpu_ms == 0.0:
        return scale()
    elapsed += delta
    total += gpu_ms
    samples += 1
    if elapsed < 0.5 or samples < 8:
        return scale()
    var average := total / samples
    var previous := level
    # A 60 FPS budget with separate down/up thresholds avoids resizing on noise.
    if average > 18.0:
        level = maxi(MIN_LEVEL, level - 1)
    elif average < 12.5:
        level = mini(MAX_LEVEL, level + 1)
    elapsed = 0.0
    total = 0.0
    samples = 0
    if level != previous:
        wait = 1.0 # Allow queued GPU queries and resized buffers to settle.
    return scale()
