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
print("Validated scene: all materials, source geometry and HDR environment present")
