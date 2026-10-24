extends Node3D
## Animation equations, sites and seeds ported from filament-test PR #4.
## Six small batches; transparent puffs are sorted for the current camera.

enum Kind { FIRE, BLAST, SPRAY, LIGHTNING, SMOKE, WATER }
const PARTICLES := preload("res://shaders/effects.gdshader")
const WATER := preload("res://shaders/water.gdshader")
const Batch := preload("res://scripts/effect_batch.gd")
const SITES := [Vector2(-3.2, 3.1), Vector2(-6.3, -1.6), Vector2(3.5, 3.5),
    Vector2(6.3, -3.2), Vector2(-7.0, -6.2), Vector2(3.5, 3.5)]
const COUNTS := [78, 108, 45, 36, 52, 264]

var batches: Array[Batch] = []
var materials: Array[ShaderMaterial] = []
var lights: Array[OmniLight3D] = []
var seconds := 0.0
var update_ms := 0.0
var instances: Array[MeshInstance3D] = []
var origins := PackedVector3Array()
var jet := PackedVector3Array()
var sides := PackedVector3Array()
var ups := PackedVector3Array()
var ring := PackedVector2Array()
var water_points := PackedVector3Array()

static func origin(kind: int) -> Vector3:
    var site: Vector2 = SITES[kind]
    var hills := 0.36 * sin(site.x * 0.24) * cos(site.y * 0.18) + 0.12 * sin(site.x * 0.7 + site.y * 0.35)
    var blend := clampf(maxf(absf(site.x) - 6.0, absf(site.y + 3.0) - 7.0) / 5.0, 0.0, 1.0)
    return Vector3(site.x, hills * blend, site.y)

static func random(seed: int) -> float:
    var value := seed
    value = ((value ^ (value >> 16)) * 0x7feb352d) & 0xffffffff
    value = ((value ^ (value >> 15)) * 0x846ca68b) & 0xffffffff
    value = value ^ (value >> 16)
    return float(value >> 8) / 16777216.0

static func blast_age(time: float) -> float:
    return fmod(time, 5.4)

static func lightning_pulse(time: float) -> float:
    var phase := fmod(time, 4.8)
    return exp(-pow((phase - 0.12) / 0.055, 2.0)) + 0.75 * exp(-pow((phase - 0.3) / 0.08, 2.0))

func _ready() -> void:
    for kind in range(6):
        origins.append(origin(kind))
    for i in range(25):
        jet.append(_jet(i))
    for i in range(24):
        var tangent := (jet[i + 1] - jet[i]).normalized()
        var side := tangent.cross(Vector3.RIGHT).normalized()
        sides.append(side)
        ups.append(tangent.cross(side))
    for i in range(8):
        var angle := TAU * i / 8.0
        ring.append(Vector2(cos(angle), sin(angle)))
    water_points.resize(7 * 13)
    for kind in range(6):
        var material := ShaderMaterial.new()
        material.shader = WATER if kind == Kind.WATER else PARTICLES
        if kind != Kind.WATER:
            material.set_shader_parameter("kind", kind)
        materials.append(material)
        var bounds := AABB(origins[kind] - Vector3(8, 1, 8), Vector3(16, 24, 16))
        var batch := Batch.new(COUNTS[kind], material, bounds, kind == Kind.WATER)
        batches.append(batch)
        var instance := MeshInstance3D.new()
        instance.name = Kind.keys()[kind]
        instances.append(instance)
        instance.mesh = batch.mesh
        instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        add_child(instance)
    for kind in [Kind.FIRE, Kind.BLAST, Kind.LIGHTNING]:
        var light := OmniLight3D.new()
        light.position = origins[kind] + Vector3.UP
        light.omni_range = 6.0
        light.shadow_enabled = false
        light.light_volumetric_fog_energy = 0.0
        light.light_color = {Kind.FIRE: Color(1, 0.32, 0.06),
            Kind.BLAST: Color(1, 0.5, 0.1), Kind.LIGHTNING: Color(0.45, 0.65, 1)}[kind].linear_to_srgb()
        lights.append(light)
        add_child(light)

func _process(delta: float) -> void:
    seconds += delta
    var start := Time.get_ticks_usec()
    animate(seconds, get_viewport().get_camera_3d().global_position)
    update_ms = lerpf(update_ms, float(Time.get_ticks_usec() - start) / 1000.0, 0.1)

func _quad(batch: Batch, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
        color: Color, uv := Rect2(0, 0, 1, 1)) -> void:
    batch.quad(a, b, c, d, color, uv)

func _billboards(mesh: Batch, puffs: Array, eye: Vector3) -> void:
    puffs.sort_custom(func(a: Array, b: Array) -> bool:
        return (a[0] as Vector3).distance_squared_to(eye) > (b[0] as Vector3).distance_squared_to(eye))
    for puff: Array in puffs:
        var p: Vector3 = puff[0]
        var direction := (eye - p).normalized()
        if direction.is_zero_approx():
            direction = Vector3.BACK
        var right := Vector3.UP.cross(direction).normalized()
        if right.is_zero_approx():
            right = Vector3.RIGHT
        var x: Vector3 = right * puff[1] * 0.5
        var y: Vector3 = direction.cross(right).normalized() * puff[2] * 0.5
        _quad(mesh, p - x - y, p + x - y, p + x + y, p - x + y, puff[3])

func _ribbon(mesh: Batch, a: Vector3, b: Vector3, width: float, color: Color, eye: Vector3) -> void:
    var side := (b - a).cross(eye - (a + b) * 0.5).normalized()
    if side.is_zero_approx():
        side = Vector3.RIGHT
    side *= width * 0.5
    _quad(mesh, a - side, a + side, b + side, b - side, color)

func _bolt_point(i: int, strike: int) -> Vector3:
    var end := i == 0 or i == 18
    return origins[Kind.LIGHTNING] + Vector3(0.0 if end else (random(i + strike * 73 + 891) - 0.5) * 0.8,
        5.2 * (1.0 - float(i) / 18.0), 0.0 if end else (random(i + strike * 91 + 477) - 0.5) * 0.5)

func _water_point(x: int, z: int, time: float) -> Vector3:
    var u := float(x) / 6.0
    var v := float(z) / 12.0
    return origins[Kind.WATER] + Vector3((u - 0.5) * 1.45 + 0.75,
        -0.085 + 0.012 * sin(v * 25.0 - time * 4.0 + u * 8.0), v * 3.3 + 0.25)

func _jet(i: int) -> Vector3:
    var t := float(i) / 24.0
    return origins[Kind.WATER] + Vector3(t * 0.75, 1.15 + t * 0.55 - 1.8 * t * t, t * 1.45)

func animate(time: float, eye: Vector3) -> void:
    assert(is_finite(time) and time >= 0.0 and eye.is_finite())
    for kind in range(6):
        materials[kind].set_shader_parameter("seconds", time)
        batches[kind].begin()
    var puffs: Array = []
    var fire := origins[Kind.FIRE]
    for i in range(54):
        var seed := random(i + 1)
        var age := fmod(time * 0.75 + seed, 1.0)
        var angle := random(i + 91) * TAU
        var radius := (1.0 - age) * 0.35
        var p := fire + Vector3(cos(angle) * radius + 0.15 * sin(time * 2.0 + seed * 12.0),
            0.12 + age * 1.9, sin(angle) * radius)
        puffs.append([p, 0.48 * (1.0 - age) + 0.16, 0.7 * (1.0 - age) + 0.35,
            Color(1, 0.12 + 0.32 * (1.0 - age), 0.015, sin(PI * age) * 0.62)])
    for i in range(24):
        var seed := random(i + 901)
        var age := fmod(time * 0.3 + seed, 1.0)
        var angle := seed * TAU
        puffs.append([fire + Vector3(0.45 * sin(angle + age * 3.0), age * 3.0, 0.4 * cos(angle)),
            0.025, 0.09, Color(1, 0.4, 0.06, (1.0 - age) * 0.85)])
    _billboards(batches[Kind.FIRE], puffs, eye)
    puffs.clear()

    var blast := origins[Kind.BLAST]
    var age := blast_age(time)
    var fade := clampf(1.0 - age / 2.5, 0.0, 1.0)
    # Every fragment would be discarded below the shader's existing alpha threshold.
    instances[Kind.BLAST].visible = fade * 0.65 >= 0.003
    if instances[Kind.BLAST].visible or not batches[Kind.BLAST].initialized:
        for i in range(72):
            var angle := random(i + 1301) * TAU
            var lift := random(i + 701)
            var radius := sqrt(minf(age, 2.5)) * 1.25
            var p := blast + Vector3(cos(angle) * radius * (0.35 + lift * 0.65),
                0.6 + age * (1.4 + lift * 2.6), sin(angle) * radius)
            var size := 0.2 + minf(age, 2.5) * (0.5 + lift * 0.4)
            puffs.append([p, size, size, Color(1, 0.1 + 0.3 * fade, 0.012, fade * 0.65)])
        for i in range(36):
            var angle := random(i + 4101) * TAU
            var speed := 1.6 + random(i + 151) * 2.0
            var t := minf(age, 2.0)
            var p := blast + Vector3(cos(angle) * t * speed,
                maxf(0.04, t * (2.5 + random(i + 9) * 2.0) - 2.6 * t * t), sin(angle) * t * speed)
            puffs.append([p, 0.035, 0.15, Color(1, 0.6, 0.1, clampf(1.0 - age / 1.5, 0.0, 1.0))])
        _billboards(batches[Kind.BLAST], puffs, eye)
        puffs.clear()

    var water := origins[Kind.WATER]
    for i in range(45):
        var seed := random(i + 2001)
        var t := fmod(time * 1.5 + seed, 1.0)
        var angle := seed * TAU
        puffs.append([water + Vector3(0.75 + cos(angle) * t * 0.7,
            -0.07 + maxf(0.0, t * 1.3 - 1.25 * t * t), 1.45 + sin(angle) * t * 0.7),
            0.04 + 0.08 * t, 0.08 + 0.09 * t, Color(0.6, 0.8, 0.86, (1.0 - t) * 0.75)])
    _billboards(batches[Kind.SPRAY], puffs, eye)
    puffs.clear()
    for z in range(13):
        for x in range(7):
            water_points[z * 7 + x] = _water_point(x, z, time)
    for z in range(12):
        for x in range(6):
            _quad(batches[Kind.WATER], water_points[z * 7 + x], water_points[z * 7 + x + 1],
                water_points[(z + 1) * 7 + x + 1], water_points[(z + 1) * 7 + x], Color(0.065, 0.17, 0.16, 0.62),
                Rect2(float(x) / 6.0, float(z) / 12.0, 1.0 / 6.0, 1.0 / 12.0))
    for i in range(24):
        var radius := 0.048 + 0.006 * sin(time * 8.0 + i)
        var a := jet[i]
        var b := jet[i + 1]
        var side := sides[i]
        var up := ups[i]
        for j in range(8):
            var x := (side * ring[j].x + up * ring[j].y) * radius
            var next := (j + 1) % 8
            var y := (side * ring[next].x + up * ring[next].y) * radius
            _quad(batches[Kind.WATER], a + x, a + y, b + y, b + x, Color(0.16, 0.35, 0.38, 0.56),
                Rect2(float(j) / 8.0, float(i) / 24.0, 1.0 / 8.0, 1.0 / 24.0))

    var pulse := lightning_pulse(time)
    var strike := int(floor(time / 4.8))
    instances[Kind.LIGHTNING].visible = pulse >= 0.003
    if instances[Kind.LIGHTNING].visible or not batches[Kind.LIGHTNING].initialized:
        for i in range(18):
            _ribbon(batches[Kind.LIGHTNING], _bolt_point(i, strike), _bolt_point(i + 1, strike),
                0.1, Color(0.5, 0.7, 1, pulse), eye)
        for branch in range(3):
            var a := _bolt_point(4 + branch * 4, strike)
            for i in range(6):
                var b := a + Vector3((1.0 if branch % 2 else -1.0) * (0.13 + random(i + branch * 11) * 0.22),
                    -0.28, (random(i + 2) * 2.0 - 1.0) * 0.25)
                _ribbon(batches[Kind.LIGHTNING], a, b, 0.045, Color(0.35, 0.55, 1, pulse * (1.0 - float(i) / 7.0)), eye)
                a = b

    var smoke := origins[Kind.SMOKE]
    for i in range(52):
        var seed := random(i + 3001)
        var t := fmod(time * 0.12 + seed, 1.0)
        var angle := random(i + 1801) * TAU
        var size := 0.75 + t * 1.8
        var p := smoke + Vector3(t * 1.1 + sin(angle + time * 0.3) * (0.15 + t * 0.55),
            0.35 + t * 5.5, cos(angle + t * 2.0) * (0.2 + t * 0.55))
        var shade := 0.055 + t * 0.08
        puffs.append([p, size, size * 1.15, Color(shade, shade * 1.01, shade * 1.04, sin(PI * t) * 0.7)])
    _billboards(batches[Kind.SMOKE], puffs, eye)
    for kind in range(6):
        if instances[kind].visible or not batches[kind].initialized:
            batches[kind].upload()
    lights[0].light_energy = 1.2 * (1.0 + 0.13 * sin(time * 13.0) + 0.09 * sin(time * 23.0))
    lights[1].light_energy = 8.0 * exp(-blast_age(time) * 7.0)
    lights[2].light_energy = 4.0 * pulse
    lights[2].visible = pulse > 0.0
