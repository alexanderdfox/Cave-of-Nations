#!/usr/bin/env python3
"""Simplify a USD or USDC mesh into a lightweight colored cube USDZ.

This script does not attempt to preserve the original high-poly geometry.
Instead, it verifies that the source file exists and then emits a minimal
0.98m cube mesh with the requested diffuse color, matching the size of the
other block assets in Cave of Nations. The resulting USDZ is typically only
~1 KB, solving both scale and file-size concerns.

Usage:
    python convert_usdc_to_block.py PipestoneBlock.usdc \
        Sources/CaveOfNationsApp/Resources/Blocks/PipestoneBlock.usdz \
        --color 0.72 0.18 0.2
"""

import argparse
import os
import zipfile
from pathlib import Path

DEFAULT_SIZE = 0.98
DEFAULT_COLOR = (0.72, 0.18, 0.2)
TRIANGLES = [
    (0, 1, 2), (0, 2, 3),
    (4, 6, 5), (4, 7, 6),
    (4, 5, 1), (4, 1, 0),
    (3, 2, 6), (3, 6, 7),
    (1, 5, 6), (1, 6, 2),
    (4, 0, 3), (4, 3, 7),
]


def build_cube_usda(size: float, color: tuple[float, float, float]) -> str:
    half = size / 2.0
    points = [
        (-half, -half, -half),
        (half, -half, -half),
        (half, half, -half),
        (-half, half, -half),
        (-half, -half, half),
        (half, -half, half),
        (half, half, half),
        (-half, half, half),
    ]

    def fmt(vec: tuple[float, float, float]) -> str:
        return f"({vec[0]:.4f}, {vec[1]:.4f}, {vec[2]:.4f})"

    counts_str = ", ".join("3" for _ in TRIANGLES)
    indices_str = ", ".join(str(i) for tri in TRIANGLES for i in tri)

    r, g, b = color
    return f"""#usda 1.0
(
    metersPerUnit = 1
)

def Xform "Root" {{
    def Mesh "PipestoneBlock" {{
        uniform token subdivisionScheme = "none"
        point3f[] points = [{", ".join(fmt(p) for p in points)}]
        int[] faceVertexCounts = [{counts_str}]
        int[] faceVertexIndices = [{indices_str}]
        float3[] extent = [{fmt((-half, -half, -half))}, {fmt((half, half, half))}]
        rel material:binding = </Root/Material>
    }}

    def Material "Material" {{
        token outputs:surface.connect = </Root/Material/PreviewSurface.outputs:surface>
        def Shader "PreviewSurface" {{
            uniform token info:id = "UsdPreviewSurface"
            color3f inputs:diffuseColor = ({r:.3f}, {g:.3f}, {b:.3f})
            float inputs:roughness = 0.4
            float inputs:metallic = 0.0
            token outputs:surface
        }}
    }}
}}
"""


def main() -> None:
    parser = argparse.ArgumentParser(description="Convert a heavy USD/USDC block into a simple cube USDZ")
    parser.add_argument("source", help="Path to the source USD/USDC file (used for existence check)")
    parser.add_argument("destination", help="Output USDZ path")
    parser.add_argument("--size", type=float, default=DEFAULT_SIZE, help="Cube edge length in meters")
    parser.add_argument("--color", nargs=3, type=float, metavar=("R", "G", "B"), default=DEFAULT_COLOR,
                        help="Diffuse color components (0-1 range)")
    args = parser.parse_args()

    source_path = Path(args.source)
    if not source_path.exists():
        raise SystemExit(f"Source file not found: {source_path}")

    dest_path = Path(args.destination)
    dest_path.parent.mkdir(parents=True, exist_ok=True)

    usda_content = build_cube_usda(args.size, tuple(args.color))

    with zipfile.ZipFile(dest_path, "w", compression=zipfile.ZIP_STORED) as archive:
        archive.writestr("default.usda", usda_content)

    print(f"Created {dest_path} (size: {dest_path.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
