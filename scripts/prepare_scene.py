#!/usr/bin/env python3
"""Export exact filament-test geometry to GLB and CC0 textures for Godot 4."""
import hashlib
import json
import pathlib
import shutil
import struct
import subprocess
import tempfile

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parents[1]
HOST_URL = "https://github.com/google/filament/releases/download/v1.78.1/filament-v1.78.1-linux.tgz"
HOST_SHA256 = "9e88f9d6aee7956c081448f237305988570a5bca76fed6e0d88ee1137110af1f"
CACHE = ROOT / ".deps"
DEST = ROOT / "assets/generated"
SURFACES = ("Ground", "Stone", "Bark", "Leaves", "Canopy")


def download(url, target, expected):
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.is_file() and hashlib.sha256(target.read_bytes()).hexdigest() == expected:
        return
    with tempfile.NamedTemporaryFile(dir=target.parent, delete=False) as tmp:
        temporary = pathlib.Path(tmp.name)
    try:
        subprocess.run(["curl", "-fLsS", "--retry", "3", "--connect-timeout", "20",
                        "--max-time", "300", url, "-o", str(temporary)], check=True)
        if hashlib.sha256(temporary.read_bytes()).hexdigest() != expected:
            raise ValueError(f"SHA-256 mismatch: {url}")
        temporary.replace(target)
    finally:
        temporary.unlink(missing_ok=True)


def pad(data, fill=b"\0"):
    return data + fill * (-len(data) % 4)


def build_glb(binary_geometry, sources, canopy_path, output):
    payload = bytearray()
    model = {
        "asset": {"version": "2.0", "generator": "filament-test exact geometry -> Godot"},
        "scene": 0, "scenes": [{"nodes": []}], "nodes": [],
        "meshes": [], "accessors": [], "bufferViews": [], "buffers": [{"byteLength": 0}],
        "materials": [], "images": [], "samplers": [{
            "magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497
        }], "textures": []
    }

    def append_view(content, stride=None, target=None):
        offset = len(payload)
        payload.extend(pad(content))
        view = {"buffer": 0, "byteOffset": offset, "byteLength": len(content)}
        if stride is not None:
            view["byteStride"] = stride
        if target is not None:
            view["target"] = target
        index = len(model["bufferViews"])
        model["bufferViews"].append(view)
        return index

    def accessor(view, offset, count, shape, kind=5126, limits=None):
        result = {"bufferView": view, "byteOffset": offset, "componentType": kind,
                  "count": count, "type": shape}
        if limits is not None:
            result["min"], result["max"] = limits
        index = len(model["accessors"])
        model["accessors"].append(result)
        return index

    def image(name, data, mime):
        view = append_view(data)
        index = len(model["images"])
        model["images"].append({
            "name": name, "bufferView": view, "mimeType": mime
        })
        model["textures"].append({"sampler": 0, "source": index})
        return index

    textures = {}
    for name in ("ground", "stone", "bark"):
        for channel in ("albedo", "normal", "arm"):
            key = f"{name}_{channel}"
            textures[key] = image(key, sources[key].read_bytes(), "image/jpeg")
    textures["canopy"] = image("pine_canopy", canopy_path.read_bytes(), "image/png")

    for name in ("ground", "stone", "bark"):
        pbr = {"baseColorTexture": {"index": textures[name + "_albedo"]},
               "metallicRoughnessTexture": {"index": textures[name + "_arm"]},
               "metallicFactor": 0.0, "roughnessFactor": 1.0}
        model["materials"].append({
            "name": name.capitalize(), "pbrMetallicRoughness": pbr,
            "normalTexture": {"index": textures[name + "_normal"]},
            "occlusionTexture": {"index": textures[name + "_arm"], "strength": 1.0}
        })
    model["materials"].append({
        "name": "Leaves", "doubleSided": True,
        "pbrMetallicRoughness": {"metallicFactor": 0.0, "roughnessFactor": 0.68}
    })
    model["materials"].append({
        "name": "Canopy", "doubleSided": True, "alphaMode": "MASK",
        "alphaCutoff": 0.4, "pbrMetallicRoughness": {
            "baseColorTexture": {"index": textures["canopy"]},
            "metallicFactor": 0.0, "roughnessFactor": 0.8
        }
    })
    with binary_geometry.open("rb") as source:
        def read(size):
            result = source.read(size)
            if len(result) != size:
                raise ValueError("Truncated geometry stream")
            return result

        if read(4) != b"GEO1":
            raise ValueError("Wrong geometry stream signature")
        batch_count = struct.unpack("<I", read(4))[0]
        if not 100 <= batch_count <= 500:
            raise ValueError(f"Unexpected batch count: {batch_count}")
        triangles = 0
        for batch in range(batch_count):
            surface, count, index_count = struct.unpack("<III", read(12))
            minimum, maximum = struct.unpack("<3f", read(12)), struct.unpack("<3f", read(12))
            if surface >= len(SURFACES) or count == 0 or index_count % 3:
                raise ValueError("Invalid generated mesh metadata")
            vertex_view = append_view(read(count * 64), 64, 34962)
            index_view = append_view(read(index_count * 4), target=34963)
            positions = accessor(vertex_view, 0, count, "VEC3", limits=(minimum, maximum))
            normals = accessor(vertex_view, 12, count, "VEC3")
            tangents = accessor(vertex_view, 24, count, "VEC4")
            uv = accessor(vertex_view, 40, count, "VEC2")
            colors = accessor(vertex_view, 48, count, "VEC4")
            indices = accessor(index_view, 0, index_count, "SCALAR", kind=5125)
            name = f"{SURFACES[surface]}_{batch:03d}"
            mesh_id = len(model["meshes"])
            model["meshes"].append({
                "name": name, "primitives": [{
                    "attributes": {"POSITION": positions, "NORMAL": normals,
                                   "TANGENT": tangents, "TEXCOORD_0": uv, "COLOR_0": colors},
                    "indices": indices, "material": surface, "mode": 4
                }]
            })
            model["nodes"].append({"name": name, "mesh": mesh_id})
            model["scenes"][0]["nodes"].append(mesh_id)
            triangles += index_count // 3
        if source.read(1):
            raise ValueError("Trailing geometry bytes")
    if not 300000 <= triangles <= 450000:
        raise ValueError(f"Unexpected scene triangle count: {triangles}")
    model["buffers"][0]["byteLength"] = len(payload)
    document = pad(json.dumps(model, separators=(",", ":"), allow_nan=False).encode(), b" ")
    body = pad(bytes(payload))
    header = struct.pack("<4sII", b"glTF", 2, 12 + 8 + len(document) + 8 + len(body))
    output.write_bytes(header + struct.pack("<I4s", len(document), b"JSON") + document
                       + struct.pack("<I4s", len(body), b"BIN\0") + body)
    print(f"GLB: {batch_count} batches, {triangles} triangles, {output.stat().st_size:,} bytes")


def main():
    manifest = json.loads((ROOT / "assets/sources.json").read_text())
    sources = {}
    for entry in manifest:
        ext = pathlib.PurePosixPath(entry["url"]).suffix
        target = CACHE / "sources" / (entry["name"] + ext)
        download(entry["url"], target, entry["sha256"])
        sources[entry["name"]] = target
        with Image.open(target) as photo:
            if photo.size != (1024, 1024):
                raise ValueError(f"Unexpected source dimensions: {entry['name']}")

    sdk_archive = CACHE / "filament-host-1.78.1.tgz"
    download(HOST_URL, sdk_archive, HOST_SHA256)
    sdk = CACHE / "host"
    headers = sdk / "filament/include"
    if not (headers / "math/vec3.h").is_file():
        sdk.mkdir(parents=True, exist_ok=True)
        subprocess.run(["tar", "--no-same-owner", "-xzf", str(sdk_archive), "-C", str(sdk)], check=True)
    if not (headers / "math/vec3.h").is_file():
        raise RuntimeError("Filament host SDK headers missing")

    DEST.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=CACHE) as tmp:
        temp = pathlib.Path(tmp)
        tool = temp / "export_geometry"
        subprocess.run(["g++", "-std=c++20", "-O2", "-Wall", "-Wextra",
                        "-I", str(headers), str(ROOT / "vendor/Geometry.cpp"),
                        str(ROOT / "scripts/export_geometry.cpp"), "-o", str(tool)], check=True)
        geometry = temp / "geometry.bin"
        subprocess.run([str(tool), str(geometry)], check=True)

        canopy = DEST / "canopy.png"
        with Image.open(sources["canopy"]) as picture:
            crop = next(item["crop"] for item in manifest if item["name"] == "canopy")
            picture.convert("RGBA").crop(crop).resize((1024, 1024), Image.Resampling.LANCZOS).save(canopy)
        shutil.copyfile(sources["environment"], DEST / "environment.hdr")
        output = DEST / "forest.glb"
        build_glb(geometry, sources, canopy, output)
    print("Godot scene assets ready.")


if __name__ == "__main__":
    main()
