"""Render the Grisnir app exports from the mascot's Blender model.

    heavy blender -b <path>/grisnir.blend --python scripts/brand/render_mascot.py -- [options]

The model (`grisnir.blend`) lives in the owner's private brand repo under
`social/brand/threkir/mascot/`; this public repo carries only what this script
writes. Every image is rendered from the model at the size it ships at: nothing
is scaled down from a larger still.

Options:
    --out DIR      where the raw renders go (default ~/.cache/grisnir-render/raw)
    --only WHAT    badge | rest | all (default all)
    --preview      one 512 px render of each pose, for look-dev

Poses:
    badge   the standing 3/4 view, for a corner of a share card
    rest    lying down with the legs folded under, for rest days

Each pose is posed here from the rig's rest pose; the .blend is never edited.
The camera is orthographic and fitted to the posed goat, Eevee with the
model's own flat toon shading, film transparent. `render_mascot.sh` trims
the transparent margin and writes the PNG and WebP exports.
"""
import bpy, json, math, os, sys
from mathutils import Vector
from bpy_extras.object_utils import world_to_camera_view

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def opt(name, default):
    return argv[argv.index(name) + 1] if name in argv else default


OUT = os.path.abspath(os.path.expanduser(opt("--out", "~/.cache/grisnir-render/raw")))
ONLY = opt("--only", "all")
PREVIEW = "--preview" in argv

# Square render size per export, in px. The shell wrapper trims the margin, so
# the shipped file is a little smaller than this; README.md lists the results.
SIZES = {
    "badge": [256],
    "rest": [192, 384],
}
# The outline is an inverted hull sized in model units, so a small render needs
# a heavier line to hold the same drawn weight (render_sprites.py uses 1.6 for
# its 256 px sprites).
def ink_for(px):
    return 1.7 if px <= 192 else 1.35 if px <= 384 else 1.1


scene = bpy.context.scene
rig = bpy.data.objects["GrisnirRig"]
cam = bpy.data.objects.new("mascot_cam", bpy.data.cameras.new("mascot_cam"))
scene.collection.objects.link(cam)
scene.camera = cam
cam.data.type = "ORTHO"
cam.data.clip_start, cam.data.clip_end = 0.1, 100

scene.eevee.taa_render_samples = 32
scene.render.filter_size = 1.0
scene.render.film_transparent = True
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"
scene.render.image_settings.compression = 90


def aim(tilt, target, ortho, dist=20.0):
    t = math.radians(tilt)
    cam.rotation_euler = (t, 0, 0)
    cam.location = Vector(target) + dist * Vector((0, -math.sin(t), math.cos(t)))
    cam.data.ortho_scale = ortho


def line_weight(factor):
    for ob in scene.objects:
        if "line" in ob.keys() and "hull" in ob.modifiers:
            base = float(ob["line"])
            ob.modifiers["hull"].strength = -base * (factor if base >= 0.008 else 1.0)


def mesh_points():
    dg = bpy.context.evaluated_depsgraph_get()
    pts = []
    for ob in scene.objects:
        if ob.type == "MESH" and not ob.name.startswith("contact_shadow") and not ob.hide_render:
            ev = ob.evaluated_get(dg)
            me = ev.to_mesh()
            pts += [ev.matrix_world @ v.co for v in me.vertices]
            ev.to_mesh_clear()
    return pts


def frame_fit(tilt, margin):
    aim(tilt, (0, 0, 0), 10)
    bpy.context.view_layer.update()
    pts = [world_to_camera_view(scene, cam, p) for p in mesh_points()]
    xs, ys = [p.x for p in pts], [p.y for p in pts]
    cx, cy = (min(xs) + max(xs)) / 2 - 0.5, (min(ys) + max(ys)) / 2 - 0.5
    ext = max(max(xs) - min(xs), max(ys) - min(ys)) * 10 * margin
    t = math.radians(tilt)
    right, up = Vector((1, 0, 0)), Vector((0, math.cos(t), math.sin(t)))
    aim(tilt, right * cx * 10 + up * cy * 10, ext)


# ------------------------------------------------------------------ posing
rig.animation_data.action = None
pb = rig.pose.bones
for b in pb:
    b.rotation_mode = "XYZ"


def reset():
    for b in pb:
        b.location = (0, 0, 0)
        b.rotation_euler = (0, 0, 0)


def yz_angle(bone):
    """A rest bone's direction in the side (y, z) plane: the leg bones bend
    about the model's X axis only, because the legs stand straight down."""
    d = bone.tail_local - bone.head_local
    return math.atan2(d.z, d.y)


LEG_SEGMENTS = {
    "fore": ["upper", "fore", "cannon", "hoof"],
    "hind": ["thigh", "shank", "cannon", "hoof"],
}


def set_leg(leg, kind, absolute_deg):
    """Pose one leg by the absolute side-plane angle of each segment, the way
    the rig's own gait code does: each bone turns by its change in angle less
    its parent's."""
    prev = 0.0
    for seg, a in zip(LEG_SEGMENTS[kind], absolute_deg):
        bone = rig.data.bones[f"{leg}_{seg}"]
        delta = math.radians(a) - yz_angle(bone)
        pb[f"{leg}_{seg}"].rotation_euler = (delta - prev, 0, 0)
        prev = delta


def heading(h):
    rig.rotation_euler = (0, 0, -math.radians(h))


def pose_badge():
    reset()
    heading(145)


# Lying down (sternal, as goats rest): the body lowered to the ground, the
# forelegs folded at the knee under the chest, the hind legs folded forward
# beside the belly. The legs stay in their own planes, never splayed out.
REST_DROP = 0.41


def pose_rest():
    reset()
    heading(112)
    pb["body"].location = (0, 0, -REST_DROP)
    for leg in ("FL", "FR"):
        set_leg(leg, "fore", [-100, -4, 178, 172])
    for leg in ("HL", "HR"):
        set_leg(leg, "hind", [-44, -172, -8, -24])
    # The head carried a touch lower and turned a little toward the viewer:
    # settled, not asleep.
    pb["neck"].rotation_euler = (math.radians(-6), 0, math.radians(14))
    pb["head"].rotation_euler = (math.radians(4), 0, 0)


POSES = {
    "badge": (pose_badge, 76, 1.06),
    "rest": (pose_rest, 72, 1.06),
}


def render(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


made = {}
for name, (pose, tilt, margin) in POSES.items():
    if ONLY not in ("all", name):
        continue
    pose()
    scene.frame_set(0)
    # The fit reads normalised camera coordinates, so it needs the square
    # aspect the renders use.
    scene.render.resolution_x = scene.render.resolution_y = 512
    bpy.context.view_layer.update()
    frame_fit(tilt, margin)
    for px in ([512] if PREVIEW else SIZES[name]):
        line_weight(ink_for(px))
        scene.render.resolution_x = scene.render.resolution_y = px
        path = os.path.join(OUT, f"{name}-{px}.png")
        render(path)
        made.setdefault(name, []).append(path)

with open(os.path.join(OUT, "renders.json"), "w") as fh:
    json.dump(made, fh, indent=1)
print("RENDERED", sum(len(v) for v in made.values()), "images to", OUT)
