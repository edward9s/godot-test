extends Node3D
## Forest geometry and textures come from filament-test's exact generator.

const FOREST := preload("res://assets/generated/forest.glb")
const CANOPY_IMAGE := preload("res://assets/generated/canopy.png")
const LEAVES_SHADER := preload("res://shaders/leaves.gdshader")
const CANOPY_SHADER := preload("res://shaders/canopy.gdshader")
const TARGET := Vector3(0.0, 1.6, -3.0)
const SUN_DIRECTION := Vector3(-0.32, -0.82, -0.47)

var yaw := 0.24
var pitch := 0.12
var distance := 13.0
var touches: Dictionary = {}
var camera: Camera3D
var fps_label: Label
var fps_elapsed := 0.0

func _ready() -> void:
    _create_environment()
    _create_sun()
    _create_scene()
    _create_camera()
    _create_fps()
    _update_camera()

func _create_scene() -> void:
    var forest := FOREST.instantiate()
    add_child(forest)
    var leaves_material := ShaderMaterial.new()
    leaves_material.shader = LEAVES_SHADER
    var canopy_material := ShaderMaterial.new()
    canopy_material.shader = CANOPY_SHADER
    canopy_material.set_shader_parameter("pine_texture", CANOPY_IMAGE)
    _replace_foliage_materials(forest, leaves_material, canopy_material)

func _replace_foliage_materials(node: Node, leaves_material: Material, canopy_material: Material) -> void:
    if node is MeshInstance3D:
        var mesh_instance := node as MeshInstance3D
        if mesh_instance.name.begins_with("Leaves_"):
            mesh_instance.set_surface_override_material(0, leaves_material)
        elif mesh_instance.name.begins_with("Canopy_"):
            mesh_instance.set_surface_override_material(0, canopy_material)
        elif mesh_instance.name.begins_with("Ground_"):
            mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    for child in node.get_children():
        _replace_foliage_materials(child, leaves_material, canopy_material)

func _create_environment() -> void:
    var panorama := PanoramaSkyMaterial.new()
    panorama.panorama = load("res://assets/generated/environment.hdr")
    var sky := Sky.new()
    sky.sky_material = panorama
    sky.radiance_size = Sky.RADIANCE_SIZE_256
    var environment := Environment.new()
    environment.background_mode = Environment.BG_SKY
    environment.sky = sky
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
    environment.reflected_light_source = Environment.REFLECTION_SOURCE_BG
    environment.ambient_light_energy = 0.85
    environment.tonemap_mode = Environment.TONE_MAPPER_AGX
    environment.glow_enabled = true
    environment.glow_intensity = 0.065
    environment.fog_enabled = true
    environment.fog_light_color = Color(0.36, 0.43, 0.44)
    environment.fog_density = 0.004
    var world := WorldEnvironment.new()
    world.environment = environment
    add_child(world)

func _create_sun() -> void:
    var sun := DirectionalLight3D.new()
    sun.name = "WarmSun"
    sun.light_color = Color(1.0, 0.88, 0.70)
    sun.light_energy = 3.5
    sun.light_angular_distance = 0.53
    sun.shadow_enabled = true
    sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
    sun.directional_shadow_max_distance = 65.0
    add_child(sun)
    sun.look_at(sun.global_position + SUN_DIRECTION, Vector3.UP)

func _create_camera() -> void:
    camera = Camera3D.new()
    camera.name = "OrbitCamera"
    camera.fov = 52.0
    camera.near = 0.1
    camera.far = 100.0
    camera.current = true
    add_child(camera)

func _create_fps() -> void:
    var overlay := CanvasLayer.new()
    overlay.name = "FPSOverlay"
    add_child(overlay)
    fps_label = Label.new()
    fps_label.position = Vector2(12.0, 12.0)
    fps_label.add_theme_font_size_override("font_size", 21)
    fps_label.add_theme_color_override("font_color", Color.WHITE)
    fps_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
    fps_label.add_theme_constant_override("shadow_offset_x", 2)
    fps_label.add_theme_constant_override("shadow_offset_y", 2)
    fps_label.text = "FPS: --"
    overlay.add_child(fps_label)

func _process(delta: float) -> void:
    fps_elapsed += delta
    if fps_elapsed >= 0.5:
        fps_elapsed = 0.0
        fps_label.text = "FPS: %d" % Engine.get_frames_per_second()

func _update_camera() -> void:
    var horizontal := distance * cos(pitch)
    camera.position = TARGET + Vector3(
        horizontal * sin(yaw), distance * sin(pitch), horizontal * cos(yaw)
    )
    camera.look_at(TARGET, Vector3.UP)

func _orbit(delta: Vector2) -> void:
    var size := get_viewport().get_visible_rect().size
    if size.x <= 0 or size.y <= 0:
        return
    yaw -= (delta.x / size.x) * 4.0
    pitch = clampf(pitch + (delta.y / size.y) * 2.0, 0.03, 0.85)
    _update_camera()

func _pinch_length() -> float:
    if touches.size() != 2:
        return 0.0
    var points := touches.values()
    return (points[0] as Vector2).distance_to(points[1] as Vector2)

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventScreenTouch:
        var touch := event as InputEventScreenTouch
        if touch.pressed:
            touches[touch.index] = touch.position
        else:
            touches.erase(touch.index)
    elif event is InputEventScreenDrag:
        var drag := event as InputEventScreenDrag
        if not touches.has(drag.index):
            return
        var previous := _pinch_length()
        touches[drag.index] = drag.position
        if touches.size() == 1:
            _orbit(drag.relative)
        elif touches.size() == 2:
            var current := _pinch_length()
            if previous > 1.0 and current > 1.0:
                distance = clampf(distance * previous / current, 4.0, 24.0)
                _update_camera()
    elif event is InputEventMouseMotion:
        if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
            _orbit((event as InputEventMouseMotion).relative)
    elif event is InputEventMouseButton and event.pressed:
        if event.button_index == MOUSE_BUTTON_WHEEL_UP:
            distance = maxf(4.0, distance - 1.0)
            _update_camera()
        elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            distance = minf(24.0, distance + 1.0)
            _update_camera()
