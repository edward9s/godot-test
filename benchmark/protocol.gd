extends RefCounted
## Pure monotonic protocol. A frame interval spans successive application callbacks.
const WARMUP_US := 30000000
const MEASURE_US := 60000000
const CAPACITY := 36000
enum Phase { IDLE, WAITING, WARMUP, MEASURE, FINISHED }
var phase := Phase.IDLE
var epoch := 0
var previous := 0
var anchor := 0
var count := 0
var frames := PackedFloat64Array() # elapsed, interval, animation, effects CPU
var valid := false
var reason: Variant = null

func start() -> void:
    frames.resize(CAPACITY * 4)
    count = 0
    epoch = 0
    previous = 0
    anchor = 0
    valid = false
    reason = null
    phase = Phase.WAITING

func stop(message: String) -> void:
    valid = false
    reason = message
    phase = Phase.FINISHED

func sample(now: int, ready: bool, animation: float, effects_ms: float) -> bool:
    if phase == Phase.WAITING:
        if ready:
            epoch = now
            previous = now
            phase = Phase.WARMUP
            return true # Reset animation clock to zero at the start of warmup.
    elif phase == Phase.WARMUP or phase == Phase.MEASURE:
        if now <= previous:
            stop("nonmonotonic application clock")
            return false
        if not ready:
            if phase == Phase.MEASURE:
                stop("initialization or shader compilation during measurement")
            else:
                phase = Phase.WAITING
            return false
        if phase == Phase.WARMUP:
            previous = now
            if now - epoch >= WARMUP_US:
                phase = Phase.MEASURE
                anchor = now
        else:
            if count >= CAPACITY:
                stop("frame capacity exceeded")
                return false
            var offset := count * 4
            frames[offset] = float(now - anchor) / 1000.0
            frames[offset + 1] = float(now - previous) / 1000.0
            frames[offset + 2] = animation
            frames[offset + 3] = effects_ms
            count += 1
            previous = now
            if now - anchor >= MEASURE_US:
                valid = true
                phase = Phase.FINISHED
    return false

func statistics() -> Variant:
    if count == 0:
        return null
    var intervals := PackedFloat64Array()
    intervals.resize(count)
    for i in count:
        intervals[i] = frames[i * 4 + 1]
    return calculate(intervals)

static func calculate(intervals: PackedFloat64Array) -> Dictionary:
    if intervals.is_empty():
        return {}
    var sorted := intervals.duplicate()
    sorted.sort()
    var total := 0.0
    for value in sorted:
        if not is_finite(value) or value <= 0.0:
            return {}
        total += value
    var n := sorted.size()
    var tail_count := ceili(n * 0.01)
    var tail := 0.0
    for i in range(n - tail_count, n):
        tail += sorted[i]
    return {"sample_count": n, "duration_ms": total, "average_fps": 1000.0 * n / total,
        "low_1_fps": 1000.0 * tail_count / tail, "mean_ms": total / n,
        "p50_ms": sorted[ceili(n * 0.50) - 1], "p95_ms": sorted[ceili(n * 0.95) - 1],
        "p99_ms": sorted[ceili(n * 0.99) - 1], "max_ms": sorted[n - 1]}
