#!/usr/bin/env python3
"""Fail early if the generated glTF drops source meshes, images or indices."""
import json
import pathlib
import struct

root = pathlib.Path(__file__).resolve().parents[1] / "assets/generated"
glb = (root / "forest.glb").read_bytes()
assert glb[:4] == b"glTF", "Not a glTF binary"
magic, version, length = struct.unpack_from("<4sII", glb)
assert version == 2 and length == len(glb)
size, kind = struct.unpack_from("<I4s", glb, 12)
assert kind == b"JSON"
document = json.loads(glb[20:20 + size])
meshes = document["meshes"]
assert 100 <= len(meshes) <= 500, len(meshes)
assert len(document["materials"]) == 5
assert len(document["images"]) == 10
assert sum(
    document["accessors"][mesh["primitives"][0]["indices"]]["count"] // 3
    for mesh in meshes
) >= 300000
for name in ["Ground", "Stone", "Bark", "Leaves", "Canopy"]:
    assert any(mesh["name"].startswith(name + "_") for mesh in meshes), name
assert (root / "canopy.png").stat().st_size > 10_000
assert (root / "environment.hdr").stat().st_size > 10_000
# Guard against visual "fixes" that silently remove the source's animated vegetation.
project = pathlib.Path(__file__).resolve().parents[1]
for name in ("canopy", "leaves"):
    shader = (project / "shaders" / (name + ".gdshader")).read_text()
    assert "void vertex()" in shader and "TIME" in shader and "VERTEX.xz +=" in shader, (
        f"{name} wind deformation must remain enabled"
    )
settings = (project / "project.godot").read_text()
assert "directional_shadow/size.mobile=4096" in settings
assert "directional_shadow/soft_shadow_filter_quality.mobile=2" in settings
print("Validated scene: geometry, HDR, animated foliage and Mobile shadow quality")
