"""Render the Grisnir app exports from the mascot's Blender model.

    heavy blender -b <path>/grisnir.blend --python scripts/brand/render_mascot.py -- [options]

The model (`grisnir.blend`) lives in the owner's private brand repo under
`social/brand/threkir/mascot/`; this public repo carries only what this script
writes. Every image is rendered from the model at the size it ships at: nothing
is scaled down from a larger still.

Options:
    --out DIR      where the raw renders go (default ~/.cache/grisnir-render/raw)
    --only WHAT    one pose name below, or all (default all)
    --preview      one 512 px render of each pose, for look-dev

Poses:
    badge   standing, a front 3/4 view, horns clear of the frame
    head    the same pose framed on the head and horns, for small sizes
    rest    lying down, legs folded under, head up, for rest days
    proud   a goat's hop (all four hooves tucked, off the ground), for milestones
    wait    standing beside a trail post, looking back at you, for empty states

Each pose is posed here from the rig's rest pose; the .blend is never edited.
The camera is orthographic and fitted to the posed goat, Eevee with the
model's own flat toon shading, film transparent. `render_mascot.sh` trims
the transparent margin and writes the PNG and WebP exports.
"""
import bpy, bmesh, json, math, os, sys
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
    "head": [128, 256],
    "rest": [192, 384],
    "proud": [192, 384],
    "wait": [192, 384],
}
# The outline is an inverted hull sized in model units, so a small render needs
# a heavier line to hold the same drawn weight (render_sprites.py uses 1.6 for
# its 256 px sprites). The head crop is drawn at a larger scale per px, so it
# needs less help.
def ink_for(px, close=False):
    if close:
        return 1.25 if px <= 128 else 1.0
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


HEAD_PARTS = ("head", "horn_", "ear_", "eye_", "lid_", "lidline_", "pupil_", "beard", "tag")


def mesh_points(head_only=False, shadow=False):
    dg = bpy.context.evaluated_depsgraph_get()
    pts = []
    for ob in scene.objects:
        if ob.type != "MESH" or ob.hide_render:
            continue
        if ob.name.startswith("contact_shadow") and not shadow:
            continue
        if head_only and not ob.name.startswith(HEAD_PARTS):
            continue
        ev = ob.evaluated_get(dg)
        me = ev.to_mesh()
        pts += [ev.matrix_world @ v.co for v in me.vertices]
        ev.to_mesh_clear()
    return pts


def frame_fit(tilt, margin, head_only=False, shadow=False, lift=0.0):
    """Fit the orthographic camera to the posed goat's ink hull (so the line
    weight must already be set). `lift` moves the frame's centre up by that
    fraction of its height, for a bust whose neck should run off the bottom."""
    aim(tilt, (0, 0, 0), 10)
    bpy.context.view_layer.update()
    pts = [world_to_camera_view(scene, cam, p) for p in mesh_points(head_only, shadow)]
    xs, ys = [p.x for p in pts], [p.y for p in pts]
    cx, cy = (min(xs) + max(xs)) / 2 - 0.5, (min(ys) + max(ys)) / 2 - 0.5
    ext = max(max(xs) - min(xs), max(ys) - min(ys)) * 10 * margin
    cy -= lift * ext / 10
    t = math.radians(tilt)
    right, up = Vector((1, 0, 0)), Vector((0, math.cos(t), math.sin(t)))
    aim(tilt, right * cx * 10 + up * cy * 10, ext)


# ------------------------------------------------------------------ posing
rig.animation_data.action = None
pb = rig.pose.bones
for b in pb:
    b.rotation_mode = "XYZ"


BODY = [ob for ob in scene.objects if ob.type == "MESH" and not ob.name.startswith(HEAD_PARTS)]


def bust(on):
    """The head crop draws the head and horns alone, as a face icon: with the
    body behind him the crop's edges cut a hard white block out of the coat,
    and with the neck alone he reads as a mounted trophy."""
    for ob in BODY:
        ob.hide_render = on


def reset():
    bust(False)
    for b in pb:
        b.location = (0, 0, 0)
        b.rotation_euler = (0, 0, 0)
    post_show(False)


def yz_angle(bone):
    """A rest bone's direction in the side (y, z) plane: the leg bones bend
    about the model's X axis only, because the legs stand straight down."""
    d = bone.tail_local - bone.head_local
    return math.atan2(d.z, d.y)


LEG_SEGMENTS = {
    "fore": ["upper", "fore", "cannon", "hoof"],
    "hind": ["thigh", "shank", "cannon", "hoof"],
}


def set_leg(leg, kind, absolute_deg, body_pitch=0.0):
    """Pose one leg by the absolute side-plane angle of each segment (0 points
    forward, -90 straight down, 180 back), the way the rig's own gait code
    does: each bone turns by its change in angle less its parent's. A pitched
    body turns the whole leg with it, so `body_pitch` is taken back out."""
    prev = math.radians(body_pitch)
    for seg, a in zip(LEG_SEGMENTS[kind], absolute_deg):
        bone = rig.data.bones[f"{leg}_{seg}"]
        delta = math.radians(a) - yz_angle(bone)
        pb[f"{leg}_{seg}"].rotation_euler = (delta - prev, 0, 0)
        prev = delta


def heading(h):
    rig.rotation_euler = (0, 0, -math.radians(h))


def look(neck_pitch=0.0, neck_turn=0.0, head_pitch=0.0, head_turn=0.0):
    """Neck and head: pitch raises (+) or lowers the muzzle, turn swings it
    toward the goat's right (+), which faces the camera in every pose here."""
    pb["neck"].rotation_euler = (math.radians(neck_pitch), 0, math.radians(neck_turn))
    pb["head"].rotation_euler = (math.radians(head_pitch), 0, math.radians(head_turn))


# ---------------------------------------------------------------- trail post
# A waymarker post for the waiting pose: a squared timber post with a
# brand-pink blaze, in the model's own hoof and tag materials and its own
# inverted-hull ink, built here so the .blend is never edited.
POST = []


def _box(cx, cy, z0, z1, hw, bevel_top=0.0):
    me = bpy.data.meshes.new("post")
    bm = bmesh.new()
    res = bmesh.ops.create_cube(bm, size=1.0)
    for v in res["verts"]:
        v.co.x = cx + v.co.x * 2 * hw
        v.co.y = cy + v.co.y * 2 * hw
        v.co.z = z0 + (v.co.z + 0.5) * (z1 - z0)
        if bevel_top and v.co.z > z1 - 1e-6:
            v.co.x = cx + (v.co.x - cx) * (1 - bevel_top)
            v.co.y = cy + (v.co.y - cy) * (1 - bevel_top)
    bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=2, use_grid_fill=True)
    bm.to_mesh(me)
    bm.free()
    return me


def _prop(name, me, mat, line):
    me.materials.append(bpy.data.materials[mat])
    ob = bpy.data.objects.new(name, me)
    scene.collection.objects.link(ob)
    POST.append(ob)
    if line:
        me2 = me.copy()
        me2.materials.clear()
        me2.materials.append(bpy.data.materials["ink"])
        bm = bmesh.new()
        bm.from_mesh(me2)
        bmesh.ops.reverse_faces(bm, faces=bm.faces)
        bm.to_mesh(me2)
        bm.free()
        ol = bpy.data.objects.new(name + "_ink", me2)
        scene.collection.objects.link(ol)
        d = ol.modifiers.new("hull", "DISPLACE")
        d.direction, d.mid_level, d.strength = "NORMAL", 0.0, -line
        ol["line"] = line
        POST.append(ol)


def build_post(x, y):
    """A trail sign: a timber post and an arrow board pointing the way he faces."""
    _prop("post_wood", _box(x, y, 0.0, 0.98, 0.042, bevel_top=0.3), "hoof", 0.016)
    me = bpy.data.meshes.new("post_board")
    bm = bmesh.new()
    z0, z1, t = 0.70, 0.86, 0.022
    outline = [(x - 0.05, z0), (x + 0.26, z0), (x + 0.34, (z0 + z1) / 2), (x + 0.26, z1), (x - 0.05, z1)]
    front = [bm.verts.new((px, y - 0.046 - t, pz)) for px, pz in outline]
    back = [bm.verts.new((px, y - 0.046 + t, pz)) for px, pz in outline]
    bm.faces.new(front)
    bm.faces.new(list(reversed(back)))
    for i in range(len(outline)):
        j = (i + 1) % len(outline)
        bm.faces.new([front[i], back[i], back[j], front[j]])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    _prop("post_board", me, "tag", 0.012)
    me = bpy.data.meshes.new("post_shadow")
    n = 32
    me.from_pydata([(0, 0, 0)] + [(math.cos(2 * math.pi * k / n), math.sin(2 * math.pi * k / n), 0) for k in range(n)],
                   [], [(0, 1 + k, 1 + (k + 1) % n) for k in range(n)])
    _prop("post_shadow", me, "contact_shadow", 0.0)
    POST[-1].location = (x, y, 0.002)
    POST[-1].scale = (0.14, 0.09, 1)


def post_show(on):
    for ob in POST:
        ob.hide_render = not on


build_post(0.9, 0.42)
post_show(False)


# ------------------------------------------------------------------- poses
def pose_badge():
    reset()
    heading(152)
    # Head up and turned to the camera so the face and both horns read.
    look(neck_pitch=6, neck_turn=-18, head_pitch=4, head_turn=-14)


# Lying down (sternal, as goats rest): the body lowered to the ground and
# pitched a little rump-down, the forelegs folded at the knee under the chest,
# the hind legs folded forward beside the belly with the hock behind. The
# legs stay in their own planes, never splayed out. The head is carried up.
REST_DROP = 0.40
REST_PITCH = 5.0


def pose_rest():
    reset()
    heading(104)
    pb["body"].location = (0, 0, -REST_DROP)
    pb["body"].rotation_euler = (math.radians(REST_PITCH), 0, 0)
    # The far foreleg folded flat; the near one folded with its knee ahead.
    set_leg("FL", "fore", [-100, -4, 178, 172], REST_PITCH)
    set_leg("FR", "fore", [-74, -6, 4, -16], REST_PITCH)
    for leg in ("HL", "HR"):
        set_leg(leg, "hind", [-40, -174, -6, -22], REST_PITCH)
    look(neck_pitch=14, neck_turn=-16, head_pitch=-4, head_turn=-10)


# A goat's hop: all four hooves tucked and off the ground, back level, head up.
HOP = 0.2


def pose_proud():
    reset()
    heading(140)
    pb["body"].location = (0, 0, HOP)
    pb["body"].rotation_euler = (math.radians(6), 0, 0)
    for leg in ("FL", "FR"):
        set_leg(leg, "fore", [-112, -128, -70, -40], 6)
    for leg in ("HL", "HR"):
        set_leg(leg, "hind", [-62, -136, -96, -70], 6)
    look(neck_pitch=12, neck_turn=-16, head_pitch=6, head_turn=-10)


def pose_head():
    pose_badge()
    bust(True)


def pose_wait():
    reset()
    heading(100)
    post_show(True)
    look(neck_pitch=8, neck_turn=-40, head_pitch=2, head_turn=-30)


# name: (pose, camera tilt, margin, head_only, include shadow, lift)
POSES = {
    "badge": (pose_badge, 78, 1.10, False, False, 0.0),
    "head": (pose_head, 80, 1.08, False, False, 0.0),
    "rest": (pose_rest, 68, 1.08, False, False, 0.0),
    "proud": (pose_proud, 76, 1.08, False, True, 0.0),
    "wait": (pose_wait, 78, 1.08, False, False, 0.0),
}


def render(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


made = {}
for name, (pose, tilt, margin, head_only, shadow, lift) in POSES.items():
    if ONLY not in ("all", name):
        continue
    pose()
    scene.frame_set(0)
    for px in ([512] if PREVIEW else SIZES[name]):
        line_weight(ink_for(px, close=head_only))
        # The fit reads normalised camera coordinates, so it needs the square
        # aspect the renders use; it runs per size because the hull it fits
        # grows with the line weight.
        scene.render.resolution_x = scene.render.resolution_y = px
        bpy.context.view_layer.update()
        frame_fit(tilt, margin, head_only, shadow, lift)
        path = os.path.join(OUT, f"{name}-{px}.png")
        render(path)
        made.setdefault(name, []).append(path)


with open(os.path.join(OUT, "renders.json"), "w") as fh:
    json.dump(made, fh, indent=1)
print("RENDERED", sum(len(v) for v in made.values()), "images to", OUT)
