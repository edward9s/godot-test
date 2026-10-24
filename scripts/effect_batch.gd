extends RefCounted
## Fixed topology and GPU buffers. Only upload bytes after the first frame.
## The uncompressed buffer layout is checked against Godot before each surface is used.

var mesh := ArrayMesh.new()
var vertices := PackedVector3Array()
var indices := PackedInt32Array()
var initialized := false
var colors := PackedColorArray()
var uvs := PackedVector2Array()
var normals := PackedVector3Array()
var tangents := PackedFloat32Array()
var attributes := PackedByteArray()
var orientations := PackedByteArray()
var cursor := 0
var material: Material
var lit: bool

func _init(quads: int, shader: Material, bounds: AABB, lighting: bool) -> void:
    material = shader
    lit = lighting
    var count := quads * 4
    indices.resize(quads * 6)
    for quad in range(quads):
        for i in range(6):
            indices[quad * 6 + i] = quad * 4 + [0, 1, 2, 0, 2, 3][i]
    vertices.resize(count)
    colors.resize(count)
    uvs.resize(count)
    attributes.resize(count * 12) # RGBA8 + two float32 UVs.
    if lit:
        normals.resize(count)
        tangents.resize(count * 4)
        orientations.resize(count * 8) # Octahedral normal and signed tangent.
    mesh.custom_aabb = bounds

func begin() -> void:
    cursor = 0

func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color, uv: Rect2) -> void:
    assert(cursor + 4 <= vertices.size(), "Effect topology exceeded its fixed buffer")
    var rgba := int(clampf(color.r * 255.0, 0, 255)) | (int(clampf(color.g * 255.0, 0, 255)) << 8) \
        | (int(clampf(color.b * 255.0, 0, 255)) << 16) | (int(clampf(color.a * 255.0, 0, 255)) << 24)
    var normal := Vector3.UP
    var tangent := Vector3.RIGHT
    var packed_normal := 0
    var packed_tangent := 0
    if lit:
        normal = (b - a).cross(d - a).normalized()
        tangent = (b - a).normalized()
        packed_normal = _oct(normal.octahedron_encode())
        # Godot 4.7.2 Vector3::octahedron_tangent_encode, with handedness -1.
        var oct := tangent.octahedron_encode()
        oct.y = 1.0 - (maxf(oct.y, 1.0 / 32767.0) * 0.5 + 0.5)
        packed_tangent = _oct(oct)
        if packed_tangent == 0xffff0000:
            packed_tangent = 0xffffffff
    # Four shared corners retain the same two clockwise triangles.
    vertices[cursor] = a
    vertices[cursor + 1] = d
    vertices[cursor + 2] = c
    vertices[cursor + 3] = b
    if not initialized:
        uvs[cursor] = uv.position
        uvs[cursor + 1] = Vector2(uv.position.x, uv.end.y)
        uvs[cursor + 2] = uv.end
        uvs[cursor + 3] = Vector2(uv.end.x, uv.position.y)
        for i in range(cursor, cursor + 4):
            attributes.encode_float(i * 12 + 4, uvs[i].x)
            attributes.encode_float(i * 12 + 8, uvs[i].y)
    else:
        assert(uvs[cursor] == uv.position and uvs[cursor + 2] == uv.end, "Fixed effect UVs changed")
    for i in range(cursor, cursor + 4):
        colors[i] = color
        attributes.encode_u32(i * 12, rgba)
        if lit:
            normals[i] = normal
            tangents[i * 4] = tangent.x
            tangents[i * 4 + 1] = tangent.y
            tangents[i * 4 + 2] = tangent.z
            tangents[i * 4 + 3] = -1.0
            orientations.encode_u32(i * 8, packed_normal)
            orientations.encode_u32(i * 8 + 4, packed_tangent)
    cursor += 4

static func _oct(value: Vector2) -> int:
    return int(clampf(value.x * 65535.0, 0, 65535)) | (int(clampf(value.y * 65535.0, 0, 65535)) << 16)

func upload() -> void:
    assert(cursor == vertices.size(), "Effect topology did not fill its fixed buffer")
    if not initialized:
        var arrays: Array = []
        arrays.resize(Mesh.ARRAY_MAX)
        arrays[Mesh.ARRAY_INDEX] = indices
        arrays[Mesh.ARRAY_VERTEX] = vertices
        arrays[Mesh.ARRAY_COLOR] = colors
        arrays[Mesh.ARRAY_TEX_UV] = uvs
        if lit:
            arrays[Mesh.ARRAY_NORMAL] = normals
            arrays[Mesh.ARRAY_TANGENT] = tangents
        mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE)
        mesh.surface_set_material(0, material)
        var format := mesh.surface_get_format(0)
        var count := vertices.size()
        assert(RenderingServer.mesh_surface_get_format_vertex_stride(format, count) == 12)
        assert(RenderingServer.mesh_surface_get_format_attribute_stride(format, count) == 12)
        assert(RenderingServer.mesh_surface_get_format_offset(format, count, Mesh.ARRAY_COLOR) == 0)
        assert(RenderingServer.mesh_surface_get_format_offset(format, count, Mesh.ARRAY_TEX_UV) == 4)
        if lit:
            assert(RenderingServer.mesh_surface_get_format_normal_tangent_stride(format, count) == 8)
            assert(RenderingServer.mesh_surface_get_format_offset(format, count, Mesh.ARRAY_NORMAL) == count * 12)
            assert(RenderingServer.mesh_surface_get_format_offset(format, count, Mesh.ARRAY_TANGENT) == count * 12 + 4)
        initialized = true
    else:
        mesh.surface_update_vertex_region(0, 0, vertices.to_byte_array())
        if lit:
            mesh.surface_update_vertex_region(0, vertices.size() * 12, orientations)
        mesh.surface_update_attribute_region(0, 0, attributes)
