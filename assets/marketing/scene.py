"""Blender scene for the public pages' terrain art.

A night-lit landscape built from `terrain.height()`, with contour lines drawn
into the ground material and the route from `terrain.route()` glowing across
it in the wordmark's ember -> magenta ramp. Two cameras frame the same scene:

    hero   2400x860   landing hero, a wide band behind the product shot
    panel  1200x1500  the sign-up / sign-in brand panel

Run through gen-marketing.sh, which also post-processes the PNGs. Directly:

    blender -b --factory-startup --python assets/marketing/scene.py
    SHOTS=hero SCALE=25 SAMPLES=16 blender -b --factory-startup --python assets/marketing/scene.py

Output: assets/marketing/out/<shot>.png (gitignored).
Prefers OptiX, then CUDA, and falls back to the CPU with OIDN denoising when
no GPU is usable, so a driver hiccup costs time rather than the render.
"""
import math
import os
import sys

import bpy
from mathutils import Vector

BASE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, BASE)
import terrain  # noqa: E402

OUT = os.path.join(BASE, "out")
os.makedirs(OUT, exist_ok=True)

SHOTS = [s for s in os.environ.get("SHOTS", "hero,panel").split(",") if s]
SAMPLES = int(os.environ.get("SAMPLES", "96"))
SCALE = int(os.environ.get("SCALE", "100"))
GRID = int(os.environ.get("GRID", "260"))


def srgb(hex_colour, alpha=1.0):
    h = hex_colour.lstrip("#")
    out = []
    for i in (0, 2, 4):
        c = int(h[i:i + 2], 16) / 255
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return (*out, alpha)


# Brand anchors: the wordmark ramp, the hero ramp's plums, the app teal.
EMBER = srgb("#FE5932")
MAGENTA = srgb("#A01E77")
PLUM_DEEP = srgb("#140A18")
PLUM = srgb("#3A0F33")
PLUM_HOT = srgb("#6E1450")
GROUND = srgb("#1B0D1F")
RIDGE = srgb("#3B2238")
TEAL = srgb("#2C5F6E")


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def link(obj):
    bpy.context.scene.collection.objects.link(obj)
    return obj


def terrain_mesh():
    n = GRID
    verts, faces = [], []
    for j in range(n + 1):
        y = terrain.Y_MIN + (terrain.Y_MAX - terrain.Y_MIN) * j / n
        for i in range(n + 1):
            x = terrain.X_MIN + (terrain.X_MAX - terrain.X_MIN) * i / n
            verts.append((x, y, terrain.height(x, y)))
    for j in range(n):
        for i in range(n):
            a = j * (n + 1) + i
            faces.append((a, a + 1, a + n + 2, a + n + 1))
    mesh = bpy.data.meshes.new("terrain")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    for poly in mesh.polygons:
        poly.use_smooth = True
    return link(bpy.data.objects.new("terrain", mesh))


def tube_mesh(points, radius, sides=10):
    """A tube along `points` with u = normalised arc length in its UV map."""
    lengths = [0.0]
    for a, b in zip(points, points[1:]):
        lengths.append(lengths[-1] + (Vector(b) - Vector(a)).length)
    total = lengths[-1] or 1.0

    verts, faces, uvs = [], [], []
    normal = Vector((0, 0, 1))
    for k, p in enumerate(points):
        p = Vector(p)
        nxt = Vector(points[min(k + 1, len(points) - 1)])
        prv = Vector(points[max(k - 1, 0)])
        tangent = (nxt - prv).normalized()
        # Parallel transport keeps the ring from twisting along the curve.
        normal = (normal - tangent * normal.dot(tangent)).normalized()
        binormal = tangent.cross(normal)
        for s in range(sides):
            a = math.tau * s / sides
            verts.append(p + (normal * math.cos(a) + binormal * math.sin(a)) * radius)
    for k in range(len(points) - 1):
        for s in range(sides):
            a = k * sides + s
            b = k * sides + (s + 1) % sides
            faces.append((a, b, b + sides, a + sides))
            u0, u1 = lengths[k] / total, lengths[k + 1] / total
            uvs.append([(u0, 0), (u0, 1), (u1, 1), (u1, 0)])

    mesh = bpy.data.meshes.new("route")
    mesh.from_pydata([tuple(v) for v in verts], [], faces)
    layer = mesh.uv_layers.new(name="UVMap")
    for poly, corners in zip(mesh.polygons, uvs):
        for loop_index, uv in zip(poly.loop_indices, corners):
            layer.data[loop_index].uv = uv
    for poly in mesh.polygons:
        poly.use_smooth = True
    mesh.update()
    return link(bpy.data.objects.new("route", mesh))


def material(name):
    mat = bpy.data.materials.new(name)
    try:
        mat.use_nodes = True
    except Exception:
        pass
    return mat, mat.node_tree.nodes, mat.node_tree.links


def terrain_material():
    mat, nodes, links = material("ground")
    nodes.clear()
    out = nodes.new("ShaderNodeOutputMaterial")

    geo = nodes.new("ShaderNodeNewGeometry")
    xyz = nodes.new("ShaderNodeSeparateXYZ")
    links.new(geo.outputs["Position"], xyz.inputs[0])

    # Height tint: plum valleys, dusty mauve ridges.
    hmap = nodes.new("ShaderNodeMapRange")
    hmap.inputs["From Min"].default_value = -1.0
    hmap.inputs["From Max"].default_value = 3.5
    links.new(xyz.outputs["Z"], hmap.inputs["Value"])
    tint = nodes.new("ShaderNodeValToRGB")
    tint.color_ramp.elements[0].color = GROUND
    tint.color_ramp.elements[1].color = RIDGE
    links.new(hmap.outputs["Result"], tint.inputs["Fac"])

    # Contour lines: one every 1/LINES of height, as a thin smoothstep band.
    scale = nodes.new("ShaderNodeMath")
    scale.operation = "MULTIPLY"
    scale.inputs[1].default_value = 4.0
    links.new(xyz.outputs["Z"], scale.inputs[0])
    frac = nodes.new("ShaderNodeMath")
    frac.operation = "FRACT"
    links.new(scale.outputs[0], frac.inputs[0])
    centre = nodes.new("ShaderNodeMath")
    centre.operation = "SUBTRACT"
    centre.inputs[1].default_value = 0.5
    links.new(frac.outputs[0], centre.inputs[0])
    dist = nodes.new("ShaderNodeMath")
    dist.operation = "ABSOLUTE"
    links.new(centre.outputs[0], dist.inputs[0])
    band = nodes.new("ShaderNodeMapRange")
    band.interpolation_type = "SMOOTHSTEP"
    band.inputs["From Min"].default_value = 0.47
    band.inputs["From Max"].default_value = 0.5
    links.new(dist.outputs[0], band.inputs["Value"])

    # Lines fade with distance so the far ridges don't moire.
    cam = nodes.new("ShaderNodeCameraData")
    near = nodes.new("ShaderNodeMapRange")
    near.interpolation_type = "SMOOTHSTEP"
    near.inputs["From Min"].default_value = 26.0
    near.inputs["From Max"].default_value = 6.0
    links.new(cam.outputs["View Distance"], near.inputs["Value"])
    strength = nodes.new("ShaderNodeMath")
    strength.operation = "MULTIPLY"
    links.new(band.outputs["Result"], strength.inputs[0])
    links.new(near.outputs["Result"], strength.inputs[1])
    gain = nodes.new("ShaderNodeMath")
    gain.operation = "MULTIPLY"
    gain.inputs[1].default_value = 0.6
    links.new(strength.outputs[0], gain.inputs[0])

    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Roughness"].default_value = 0.92
    bsdf.inputs["Emission Color"].default_value = MAGENTA
    links.new(tint.outputs["Color"], bsdf.inputs["Base Color"])
    links.new(gain.outputs[0], bsdf.inputs["Emission Strength"])

    # Distance fog toward the horizon colour, so depth reads as atmosphere.
    fog = nodes.new("ShaderNodeMapRange")
    fog.interpolation_type = "SMOOTHSTEP"
    fog.inputs["From Min"].default_value = 9.0
    fog.inputs["From Max"].default_value = 34.0
    fog.inputs["To Max"].default_value = 0.92
    links.new(cam.outputs["View Distance"], fog.inputs["Value"])
    haze = nodes.new("ShaderNodeEmission")
    haze.inputs["Color"].default_value = PLUM_HOT
    haze.inputs["Strength"].default_value = 0.55
    mix = nodes.new("ShaderNodeMixShader")
    links.new(fog.outputs["Result"], mix.inputs["Fac"])
    links.new(bsdf.outputs["BSDF"], mix.inputs[1])
    links.new(haze.outputs["Emission"], mix.inputs[2])
    links.new(mix.outputs["Shader"], out.inputs["Surface"])
    return mat


def route_material():
    mat, nodes, links = material("route")
    nodes.clear()
    out = nodes.new("ShaderNodeOutputMaterial")
    uv = nodes.new("ShaderNodeUVMap")
    uv.uv_map = "UVMap"
    xyz = nodes.new("ShaderNodeSeparateXYZ")
    links.new(uv.outputs["UV"], xyz.inputs[0])
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = EMBER
    ramp.color_ramp.elements[1].color = MAGENTA
    links.new(xyz.outputs["X"], ramp.inputs["Fac"])
    emit = nodes.new("ShaderNodeEmission")
    emit.inputs["Strength"].default_value = 4.5
    links.new(ramp.outputs["Color"], emit.inputs["Color"])
    links.new(emit.outputs["Emission"], out.inputs["Surface"])
    return mat


def glow_material(name, colour, strength):
    mat, nodes, links = material(name)
    nodes.clear()
    out = nodes.new("ShaderNodeOutputMaterial")
    emit = nodes.new("ShaderNodeEmission")
    emit.inputs["Color"].default_value = colour
    emit.inputs["Strength"].default_value = strength
    links.new(emit.outputs["Emission"], out.inputs["Surface"])
    return mat


def markers(points):
    start = Vector(points[0])
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.16, location=start + Vector((0, 0, 0.12)))
    bpy.context.active_object.data.materials.append(glow_material("start", EMBER, 12.0))
    bpy.ops.mesh.primitive_torus_add(
        major_radius=0.5, minor_radius=0.025, location=start + Vector((0, 0, 0.03))
    )
    bpy.context.active_object.data.materials.append(glow_material("ring", EMBER, 5.0))
    end = Vector(points[-1])
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.14, location=end + Vector((0, 0, 0.1)))
    bpy.context.active_object.data.materials.append(glow_material("finish", MAGENTA, 12.0))


def world():
    w = bpy.data.worlds.new("sky")
    try:
        w.use_nodes = True
    except Exception:
        pass
    nodes, links = w.node_tree.nodes, w.node_tree.links
    nodes.clear()
    out = nodes.new("ShaderNodeOutputWorld")
    coord = nodes.new("ShaderNodeTexCoord")
    xyz = nodes.new("ShaderNodeSeparateXYZ")
    links.new(coord.outputs["Generated"], xyz.inputs[0])
    span = nodes.new("ShaderNodeMapRange")
    span.inputs["From Min"].default_value = -0.02
    span.inputs["From Max"].default_value = 0.55
    links.new(xyz.outputs["Z"], span.inputs["Value"])
    ramp = nodes.new("ShaderNodeValToRGB")
    els = ramp.color_ramp.elements
    els[0].position, els[0].color = 0.0, srgb("#B8325A")
    els[1].position, els[1].color = 1.0, PLUM_DEEP
    mid = els.new(0.12)
    mid.color = PLUM_HOT
    upper = els.new(0.42)
    upper.color = PLUM
    links.new(span.outputs["Result"], ramp.inputs["Fac"])
    bg = nodes.new("ShaderNodeBackground")
    bg.inputs["Strength"].default_value = 1.0
    links.new(ramp.outputs["Color"], bg.inputs["Color"])
    links.new(bg.outputs["Background"], out.inputs["Surface"])
    bpy.context.scene.world = w


def lights():
    rim = bpy.data.lights.new("rim", "SUN")
    rim.energy = 2.2
    rim.color = srgb("#FF7A8A")[:3]
    rim.angle = math.radians(6)
    obj = link(bpy.data.objects.new("rim", rim))
    obj.rotation_euler = (math.radians(-78), 0, math.radians(8))

    fill = bpy.data.lights.new("fill", "SUN")
    fill.energy = 0.35
    fill.color = TEAL[:3]
    obj = link(bpy.data.objects.new("fill", fill))
    obj.rotation_euler = (math.radians(52), 0, math.radians(-35))


def camera(name, location, target, lens):
    data = bpy.data.cameras.new(name)
    data.lens = lens
    data.clip_end = 200
    cam = link(bpy.data.objects.new(name, data))
    cam.location = location
    direction = Vector(target) - Vector(location)
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    return cam


def configure_device(scene):
    scene.render.engine = "CYCLES"
    prefs = bpy.context.preferences.addons["cycles"].preferences
    for kind in ("OPTIX", "CUDA"):
        try:
            prefs.compute_device_type = kind
            prefs.get_devices()
        except Exception:
            continue
        gpus = [d for d in prefs.devices if d.type == kind]
        if gpus:
            for d in prefs.devices:
                d.use = d.type == kind
            scene.cycles.device = "GPU"
            print(f"== device: {kind} ({', '.join(d.name for d in gpus)})")
            return
    scene.cycles.device = "CPU"
    print("== device: CPU (no usable GPU)")


SHOT_SPECS = {
    "hero": dict(location=(0.4, -12.5, 2.4), target=(0.6, 6.0, -0.36), lens=26, res=(2400, 860)),
    "panel": dict(location=(-6.2, -10.0, 4.6), target=(0.8, 3.0, -0.4), lens=34, res=(1200, 1500)),
}


def main():
    reset()
    scene = bpy.context.scene
    configure_device(scene)
    scene.cycles.samples = SAMPLES
    scene.cycles.use_denoising = True
    scene.cycles.max_bounces = 4
    scene.view_settings.view_transform = "Standard"
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"
    scene.render.resolution_percentage = SCALE

    ground = terrain_mesh()
    ground.data.materials.append(terrain_material())
    path = terrain.route()
    line = tube_mesh(path, radius=0.045)
    line.data.materials.append(route_material())
    markers(path)
    world()
    lights()

    for shot in SHOTS:
        spec = SHOT_SPECS[shot]
        scene.camera = camera(shot, spec["location"], spec["target"], spec["lens"])
        scene.render.resolution_x, scene.render.resolution_y = spec["res"]
        scene.render.filepath = os.path.join(OUT, f"{shot}.png")
        print(f"== rendering {shot} at {SCALE}% / {SAMPLES} spp")
        bpy.ops.render.render(write_still=True)
    print("DONE")


main()
