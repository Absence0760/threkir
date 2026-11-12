# Grisnir exports

Grisnir is Threkir's mascot: a white mountain goat with long swept-back horns
in the brand gradient. Every image here is rendered from his Blender model. The
model and its build scripts live in the owner's private brand repo, under
`social/brand/threkir/mascot/`, and are never copied into this repo.

To re-render, with that repo checked out:

    bash scripts/brand/render_mascot.sh <path>/social/brand/threkir/mascot/grisnir.blend

`scripts/brand/render_mascot.py` poses the rig and renders each file at the
size it ships at (Eevee, the model's flat toon shading, a transparent film).
The wrapper only trims the transparent margin, writes the WebP twins of
the rest, milestone and waiting art, copies the phone assets and regenerates
`apps/web/src/lib/share/grisnir_badge_data.ts`. Nothing is scaled down from a
larger still.

## Files

Sizes are the trimmed files; the render is square at the size in the name.

| File | Size (px) | Bytes | Pose | Used by |
|---|---|---|---|---|
| `grisnir-badge-256.png` | 144 × 238 | 30,820 | Standing, front 3/4, face and both horns to the camera | Web run share card (map style); copied to `apps/mobile_{android,ios}/assets/brand/grisnir/` for the phone's run share card |
| `grisnir-head-128.png` | 96 × 124 | 9,347 | Head and horns alone, facing the camera | Small sizes (a spare, not yet placed) |
| `grisnir-head-256.png` | 186 × 242 | 23,491 | Same | Inlined as `grisnir_badge_data.ts` into the `/og/{run,route,badge,challenge,recap}` unfurls, 160 to 180 of 630 px tall (about 54 px at 360 px feed width) |
| `grisnir-rest-192.png` / `.webp` | 184 × 162 | 24,195 / 15,706 | Lying down, head up, one foreleg stretched forward, the others folded under | Web dashboard rest day, 1x |
| `grisnir-rest-384.png` / `.webp` | 362 × 320 | 64,520 / 40,542 | Same | Web dashboard rest day, 2x; copied to the phones for Home's rest-day card |
| `grisnir-proud-192.png` / `.webp` | 100 × 183 | 18,541 / 12,340 | A hop: all four hooves off the ground, a contact shadow below | Web run detail milestone (`GrisnirMilestone.svelte`), 1x |
| `grisnir-proud-384.png` / `.webp` | 190 × 360 | 48,168 / 30,710 | Same | Web milestone, 2x; copied to the phones for the run detail and post-run summary milestone |
| `grisnir-wait-192.png` / `.webp` | 184 × 150 | 19,865 / 13,346 | Standing beside a trail sign, looking at you | Web empty runs, routes and feed states (`EmptyState`'s `mascot` prop) and the onboarding panel, 1x |
| `grisnir-wait-384.png` / `.webp` | 362 × 294 | 52,603 / 33,422 | Same | Web, 2x; copied to the phones for the same empty states and the first onboarding page |

The trail sign in the waiting pose is built by `render_mascot.py` from the
model's own hoof and tag materials and ink; the `.blend` is not edited.

## The 3D trot (`grisnir-trot.glb`)

| File | Bytes | What | Used by |
|---|---|---|---|
| `grisnir-trot.glb` | 172,368 | The rigged model and its trot (15 frames, a 0.5 s loop), one skinned mesh, quantized by gltfpack | The web 3D course preview and its exported flyover video, in place of the position dot (decisions § 2458) |

Re-export, with the brand repo checked out (gltfpack on the PATH):

    heavy blender -b <path>/social/brand/threkir/mascot/grisnir.blend --python scripts/brand/export_grisnir_gltf.py

The export is byte-stable, so an unchanged model gives an unchanged file.
It carries no textures or lights: the toon look is packed into `COLOR_0`
(R the horn's base-to-tip position, G the ink width, B the part), which only
the preview's renderer (`apps/web/src/lib/components/course_preview/mascot/`)
reads, so a generic glTF viewer shows him grey. `glb.test.ts` fails the PR
past a 256 KiB budget or when the part order drifts from the script.

## Rules for using the art

From the brand notes; they apply to every placement.

- **Keep the horns.** The long gradient horns are his best feature. Never crop
  them off, recolour them, or swap them for short black ones.
- **Never splay the legs** to make him easier to read. The rest pose folds them
  under the body, as a goat lies.
- **No error states.** He never appears on a lost-GPS, failed-sync, unsaved-run,
  payment or crash screen: a mascot there reads as the app making light of a
  lost run. Web's `EmptyState` refuses him on a `danger` tone or an alert role,
  and the phone's `ErrorState` has no slot for him.
- **Empty states opt in by name** (the empty runs list, routes list and feed,
  and onboarding); a guard on each platform lists them.
- **One milestone per run**, at most one dry line, never a nag.
- **Never a nag.** No streak guilt. On rest days he rests, with at most one dry
  line (Thor's goats are back by morning).
- **Small and out of the way** on share cards: a corner, never over the route,
  the stats or the runner's name.
- **No AI-generated variations.** A new pose or size is a new render from the
  model.
- **The runner can hide him** (`show_mascot`, docs/backend/settings.md).
