#!/usr/bin/env python3
import argparse
import os
import tempfile
import zipfile

import numpy as np
import trimesh

USD_TEMPLATE = """#usda 1.0
(
    metersPerUnit = 1
)

def Xform \"Root\" {{
    def Mesh \"Stone\" {{
        point3f[] points = [
{points}
        ]
        int[] faceVertexCounts = [{face_counts}]
        int[] faceVertexIndices = [{indices}]
        uniform token subdivisionScheme = \"none\"
        rel material:binding = </Root/Material>
    }}

    def Material \"Material\" {{
        token outputs:surface.connect = </Root/Material/PreviewSurface.outputs:surface>
        def Shader \"PreviewSurface\" {{
            uniform token info:id = \"UsdPreviewSurface\"
            color3f inputs:diffuseColor = ({color})
            float inputs:metallic = 0
            float inputs:roughness = 0.8
            token outputs:surface
        }}
    }}
}}
"""

parser = argparse.ArgumentParser(description="Convert 3MF mesh into USDZ")
parser.add_argument("input", help="Path to .3mf file")
parser.add_argument("output", help="Path to .usdz output")
parser.add_argument("--color", default="0.6, 0.6, 0.6", help="RGB diffuse color e.g. '0.7,0.5,0.4'")
parser.add_argument("--target-faces", type=int, default=20000, help="Approximate number of faces after simplification")
parser.add_argument("--center", action="store_true", help="Center mesh around the origin before export")
parser.add_argument("--target-size", type=float, default=0.98, help="Longest edge after normalization")
args = parser.parse_args()

input_path = os.path.abspath(args.input)
output_path = os.path.abspath(args.output)

if not os.path.exists(input_path):
    raise SystemExit(f"Input not found: {input_path}")

mesh = trimesh.load(input_path)
if mesh.is_empty:
    raise SystemExit("Mesh is empty after loading 3MF")

if isinstance(mesh, trimesh.Scene):
    mesh = trimesh.util.concatenate(mesh.dump())

if args.target_faces and len(mesh.faces) > args.target_faces:
    try:
        mesh = mesh.simplify_quadratic_decimation(args.target_faces)
    except BaseException as exc:
        print(f"Warning: simplification failed ({exc}), using sampled subset of faces", flush=True)
        step = max(1, len(mesh.faces) // args.target_faces)
        face_indices = np.arange(0, len(mesh.faces), step)
        mesh = mesh.submesh([face_indices], append=True)
        if len(mesh.faces) > args.target_faces:
            mesh = mesh.submesh([np.arange(args.target_faces)], append=True)
        mesh.remove_unreferenced_vertices()

if args.center:
    mesh.vertices -= mesh.center_mass

if args.target_size:
    bounds = mesh.bounds
    extents = bounds[1] - bounds[0]
    longest = float(np.max(extents))
    if longest > 0:
        scale = args.target_size / longest
        mesh.apply_scale(scale)

verts = np.asarray(mesh.vertices)
faces = np.asarray(mesh.faces)

def format_points(array):
    lines = []
    for v in array:
        lines.append(f"            ({v[0]:.4f}, {v[1]:.4f}, {v[2]:.4f})")
    return "\n".join(lines)

face_counts = ", ".join(["3"] * len(faces))
indices = ", ".join(str(idx) for face in faces for idx in face)
color = args.color
if os.path.exists(output_path):
    os.remove(output_path)

usda_content = USD_TEMPLATE.format(
    points=format_points(verts),
    face_counts=face_counts,
    indices=indices,
    color=color
)

with zipfile.ZipFile(output_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
    archive.writestr("default.usda", usda_content)

print(f"Converted {input_path} -> {output_path}")
