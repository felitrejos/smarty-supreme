"""Convert a glTF binary (GLB) model to USDZ for RealityKit and SceneKit.

    python glb_to_usdz.py model.glb model.usdz [--skip word ...] [--texture 512]

Needs `pip install usd-core trimesh pillow numpy`. Parts whose names contain a
--skip word are left out, and textures are downsized to --texture pixels.
"""
import argparse
import os
import tempfile

import numpy as np
import trimesh
from PIL import Image
from pxr import Gf, Sdf, Usd, UsdGeom, UsdShade, UsdUtils, Vt


def material(stage, path, mat, folder, size, index):
    shader_path = f"{path}/Surface"
    surface = UsdShade.Shader.Define(stage, shader_path)
    surface.CreateIdAttr("UsdPreviewSurface")
    surface.CreateInput("roughness", Sdf.ValueTypeNames.Float).Set(0.8)
    result = UsdShade.Material.Define(stage, path)
    result.CreateSurfaceOutput().ConnectToSource(surface.ConnectableAPI(), "surface")
    image = getattr(mat, "baseColorTexture", None)
    if image is None:
        factor = getattr(mat, "baseColorFactor", None)
        color = (np.array(factor[:3]) / 255.0) if factor is not None else np.array([0.5, 0.5, 0.5])
        surface.CreateInput("diffuseColor", Sdf.ValueTypeNames.Color3f).Set(Gf.Vec3f(*color))
        return result
    image = image.convert("RGBA")
    image.thumbnail((size, size))
    name = f"texture{index}.png"
    image.save(os.path.join(folder, name))
    reader = UsdShade.Shader.Define(stage, f"{path}/UV")
    reader.CreateIdAttr("UsdPrimvarReader_float2")
    reader.CreateInput("varname", Sdf.ValueTypeNames.Token).Set("st")
    texture = UsdShade.Shader.Define(stage, f"{path}/Texture")
    texture.CreateIdAttr("UsdUVTexture")
    texture.CreateInput("file", Sdf.ValueTypeNames.Asset).Set(name)
    texture.CreateInput("st", Sdf.ValueTypeNames.Float2).ConnectToSource(reader.ConnectableAPI(), "result")
    rgb = texture.CreateOutput("rgb", Sdf.ValueTypeNames.Float3)
    surface.CreateInput("diffuseColor", Sdf.ValueTypeNames.Color3f).ConnectToSource(rgb)
    alpha = np.asarray(image)[..., 3]
    if alpha.min() < 250:
        a = texture.CreateOutput("a", Sdf.ValueTypeNames.Float)
        surface.CreateInput("opacity", Sdf.ValueTypeNames.Float).ConnectToSource(a)
        surface.CreateInput("opacityThreshold", Sdf.ValueTypeNames.Float).Set(0.5)
    return result


def convert(source, target, skip, size):
    scene = trimesh.load(source)
    folder = tempfile.mkdtemp()
    usdc = os.path.join(folder, "model.usdc")
    stage = Usd.Stage.CreateNew(usdc)
    UsdGeom.SetStageUpAxis(stage, UsdGeom.Tokens.y)
    UsdGeom.SetStageMetersPerUnit(stage, 1)
    root = UsdGeom.Xform.Define(stage, "/Root")
    stage.SetDefaultPrim(root.GetPrim())
    kept = 0
    for index, node in enumerate(scene.graph.nodes_geometry):
        transform, geometry_name = scene.graph[node]
        if any(word.lower() in f"{node} {geometry_name}".lower() for word in skip):
            continue
        mesh = scene.geometry[geometry_name].copy()
        mesh.apply_transform(transform)
        path = f"/Root/Part{index}"
        usd = UsdGeom.Mesh.Define(stage, path)
        usd.CreatePointsAttr(Vt.Vec3fArray.FromNumpy(mesh.vertices.astype(np.float32)))
        usd.CreateFaceVertexCountsAttr(Vt.IntArray([3] * len(mesh.faces)))
        usd.CreateFaceVertexIndicesAttr(Vt.IntArray(mesh.faces.flatten().tolist()))
        usd.CreateNormalsAttr(Vt.Vec3fArray.FromNumpy(mesh.vertex_normals.astype(np.float32)))
        usd.SetNormalsInterpolation(UsdGeom.Tokens.vertex)
        usd.CreateSubdivisionSchemeAttr(UsdGeom.Tokens.none)
        uv = getattr(mesh.visual, "uv", None)
        if uv is not None:
            st = UsdGeom.PrimvarsAPI(usd).CreatePrimvar("st", Sdf.ValueTypeNames.TexCoord2fArray, UsdGeom.Tokens.vertex)
            st.Set(Vt.Vec2fArray.FromNumpy(uv.astype(np.float32)))
        mat = material(stage, f"{path}/Material", mesh.visual.material, folder, size, index)
        UsdShade.MaterialBindingAPI.Apply(usd.GetPrim()).Bind(mat)
        kept += 1
    stage.Save()
    UsdUtils.CreateNewUsdzPackage(usdc, target)
    print(f"{kept} parts -> {target}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("source")
    parser.add_argument("target")
    parser.add_argument("--skip", nargs="*", default=[])
    parser.add_argument("--texture", type=int, default=512)
    arguments = parser.parse_args()
    convert(arguments.source, arguments.target, arguments.skip, arguments.texture)
