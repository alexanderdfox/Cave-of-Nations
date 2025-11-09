#!/usr/bin/env python3
import json
import os
import zipfile

BLOCKS = {
    "SoilBlock": {"color": (0.52, 0.33, 0.18)},
    "RockBlock": {"color": (0.35, 0.35, 0.4)},
    "RelicBlock": {"color": (0.93, 0.78, 0.25)},
    "TunnelBlock": {"color": (0.10, 0.10, 0.12)},
    "DenBlock": {"color": (0.88, 0.70, 0.50)},
    "PipestoneBlock": {"color": (0.72, 0.18, 0.20)},
}

CUBE_SIZE = 0.98
CUBE_TRIANGLES = [
    (0, 1, 2), (0, 2, 3),  # front (-Z)
    (4, 6, 5), (4, 7, 6),  # back (+Z)
    (4, 5, 1), (4, 1, 0),  # bottom (-Y)
    (3, 2, 6), (3, 6, 7),  # top (+Y)
    (1, 5, 6), (1, 6, 2),  # right (+X)
    (4, 0, 3), (4, 3, 7),  # left (-X)
]
CUBE_NORMALS = [
    (0, 0, -1), (0, 0, -1),
    (0, 0, 1), (0, 0, 1),
    (0, -1, 0), (0, -1, 0),
    (0, 1, 0), (0, 1, 0),
    (1, 0, 0), (1, 0, 0),
    (-1, 0, 0), (-1, 0, 0),
]


def build_cube_payload(color: tuple[float, float, float], size: float = CUBE_SIZE) -> str:
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

    counts = ", ".join("3" for _ in CUBE_TRIANGLES)
    indices = ", ".join(str(i) for tri in CUBE_TRIANGLES for i in tri)
    normals = []
    for normal in CUBE_NORMALS:
        normals.extend([normal, normal, normal])
    normals_str = ", ".join(fmt(n) for n in normals)

    return f"""#usda 1.0
(
    metersPerUnit = 1
)

def Xform "Root" {{
    def Mesh "Block" {{
        uniform token subdivisionScheme = "none"
        point3f[] points = [{", ".join(fmt(p) for p in points)}]
        int[] faceVertexCounts = [{counts}]
        int[] faceVertexIndices = [{indices}]
        float3[] extent = [{fmt((-half, -half, -half))}, {fmt((half, half, half))}]
        rel material:binding = </Root/Material>
    }}

    def Material "Material" {{
        token outputs:surface.connect = </Root/Material/PreviewSurface.outputs:surface>
        def Shader "PreviewSurface" {{
            uniform token info:id = "UsdPreviewSurface"
            color3f inputs:diffuseColor = ({color[0]:.3f}, {color[1]:.3f}, {color[2]:.3f})
            float inputs:roughness = 0.4
            float inputs:metallic = 0.0
            token outputs:surface
        }}
    }}
}}
"""


def main() -> None:
    root = os.path.join(os.getcwd(), "Sources", "CaveOfNationsApp", "Resources", "Blocks")
    os.makedirs(root, exist_ok=True)

    for name, info in BLOCKS.items():
        usdz_path = os.path.join(root, f"{name}.usdz")
        payload = build_cube_payload(info["color"])
        with zipfile.ZipFile(usdz_path, "w", compression=zipfile.ZIP_STORED) as archive:
            archive.writestr("default.usda", payload)
        print(f"Generated {usdz_path}")


if __name__ == "__main__":
    main()
