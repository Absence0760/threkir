"""Export Grisnir's trot as the GLB the web 3D course preview draws (#1364).

    heavy blender -b <path>/grisnir.blend --python scripts/brand/export_grisnir_gltf.py -- [options]

The model (`grisnir.blend`) lives in the owner's private brand repo under
`social/brand/threkir/mascot/`; this public repo carries only the GLB this
script writes. The .blend is never edited: everything below happens in the
loaded copy and is thrown away when Blender quits.

Options:
    --out FILE     the optimised GLB (default apps/web/static/brand/grisnir/grisnir-trot.glb)
    --raw FILE     the unoptimised export gltfpack reads (default ~/.cache/grisnir-gltf/raw.glb)
    --simplify R   gltfpack triangle ratio (default 0.3)

What the GLB holds:
- One skinned mesh (every part joined), the 21-bone rig and one animation,
  `trot`: 15 frames at 30 fps (0.5 s, two cycles a second), the last key
  repeating the first so it loops. The origin is the ground contact point
  between the hooves, the goat faces glTF -Z (the model's +Y), up is +Y.
- No textures and no lights. The toon look is the model's own: the preview's
  renderer reads the part and the shading parameters from COLOR_0, encoded
  here, rather than from a glTF material, which cannot express a toon ramp:
    R  the horn's position from base (0) to tip (1), for the brand gradient
    G  the ink outline's width, as a share of `LINE_FULL` (0 draws no ink)
    B  the part, `index / 15`: see `PARTS` (the renderer keeps the same table)
- The model's inverted-hull ink meshes are dropped: the renderer extrudes the
  outline from the body itself, at the width G gives, which halves the file.

gltfpack then simplifies and quantizes it (KHR_mesh_quantization only, no
meshopt compression, so the preview needs no decoder).
"""
import bpy, os, subprocess, sys

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def opt(name, default):
    return argv[argv.index(name) + 1] if name in argv else default


REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.abspath(os.path.expanduser(opt("--out", os.path.join(REPO, "apps/web/static/brand/grisnir/grisnir-trot.glb"))))
RAW = os.path.abspath(os.path.expanduser(opt("--raw", "~/.cache/grisnir-gltf/raw.glb")))
SIMPLIFY = float(opt("--simplify", "0.3"))

# The part table. The order is the B channel's index, and the preview's
# renderer (`apps/web/src/lib/components/course_preview/mascot/palette.ts`)
# carries the same order with each part's toon colours.
PARTS = ["coat", "hoof", "horn", "tag", "ear_inner", "tag_glyph", "eye", "pupil"]
LINE_FULL = 0.02

scene = bpy.context.scene
rig = bpy.data.objects["GrisnirRig"]
gaits = __import__("json").loads(rig["gaits"])
frames = int(gaits["trot"]["frames"])

# The ink line each part carried: its *_ink twin's `line`, times the twin's
# per-vertex `hull_w` where it fades into a join.
ink_width = {}
for ob in list(bpy.data.objects):
    if ob.type == "MESH" and "ink_of" in ob.keys():
        base = float(ob["line"])
        vg = ob.vertex_groups.get("hull_w")
        per_vertex = None
        if vg is not None:
            per_vertex = [0.0] * len(ob.data.vertices)
            for v in ob.data.vertices:
                for g in v.groups:
                    if g.group == vg.index:
                        per_vertex[v.index] = g.weight
        ink_width[ob["ink_of"]] = (base, per_vertex)

for ob in list(bpy.data.objects):
    if ob.type == "MESH" and ("ink_of" in ob.keys() or ob.name.startswith("contact_shadow")):
        bpy.data.objects.remove(ob, do_unlink=True)

parts = [ob for ob in bpy.data.objects if ob.type == "MESH"]
for ob in parts:
    me = ob.data
    base, per_vertex = ink_width.get(ob.name, (0.0, None))
    horn_t = me.attributes.get("t")
    ids = [PARTS.index(m.name) for m in me.materials]
    attr = me.color_attributes.new("grisnir", "FLOAT_COLOR", "CORNER")
    for poly in me.polygons:
        part = ids[poly.material_index] / 15.0
        for li in poly.loop_indices:
            vi = me.loops[li].vertex_index
            t = horn_t.data[vi].value if horn_t is not None else 0.0
            w = base * (per_vertex[vi] if per_vertex is not None else 1.0)
            attr.data[li].color = (t, min(1.0, w / LINE_FULL), part, 1.0)
    me.color_attributes.active_color = attr
    me.color_attributes.render_color_index = me.color_attributes.find("grisnir")

flat = bpy.data.materials.new("grisnir")
for ob in parts:
    ob.data.materials.clear()
    ob.data.materials.append(flat)

with bpy.context.temp_override(
    active_object=parts[0], object=parts[0], selected_objects=parts, selected_editable_objects=parts
):
    bpy.ops.object.join()
body = parts[0]
body.name = body.data.name = "grisnir"

# The contact point between the hooves becomes the origin, as render_sprites.py
# turns the goat about it.
rig.location = (0.0, -float(rig.get("contact_y", 0.0)), 0.0)
rig.rotation_euler = (0.0, 0.0, 0.0)

for a in list(bpy.data.actions):
    if a.name != "trot":
        bpy.data.actions.remove(a)
trot = bpy.data.actions["trot"]
rig.animation_data.action = trot
if getattr(trot, "slots", None) and len(trot.slots):
    rig.animation_data.action_slot = trot.slots[0]
scene.render.fps = 30
scene.frame_start, scene.frame_end = 0, frames

os.makedirs(os.path.dirname(RAW), exist_ok=True)
bpy.ops.export_scene.gltf(
    filepath=RAW,
    export_format="GLB",
    use_selection=False,
    export_yup=True,
    export_apply=True,
    export_normals=True,
    export_texcoords=False,
    export_tangents=False,
    export_vertex_color="ACTIVE",
    export_materials="EXPORT",
    export_skins=True,
    export_def_bones=True,
    export_morph=False,
    export_animations=True,
    export_animation_mode="ACTIVE_ACTIONS",
    export_force_sampling=True,
    export_frame_range=True,
    export_anim_slide_to_zero=True,
    export_optimize_animation_size=False,
    export_lights=False,
    export_cameras=False,
)

os.makedirs(os.path.dirname(OUT), exist_ok=True)
subprocess.run(
    ["gltfpack", "-i", RAW, "-o", OUT, "-si", str(SIMPLIFY), "-kv", "-af", "30", "-vp", "12"],
    check=True,
)
print(f"GRISNIR_GLB {OUT} {os.path.getsize(OUT)} bytes (raw {os.path.getsize(RAW)})")
