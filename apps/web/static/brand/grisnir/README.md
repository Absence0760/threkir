# Grisnir exports

Grisnir is Threkir's mascot: a white mountain goat with long swept-back horns
in the brand gradient. Every image here is rendered from his Blender model. The
model and its build scripts live in the owner's private brand repo, under
`social/brand/threkir/mascot/`, and are never copied into this repo.

To re-render, with that repo checked out:

    bash scripts/brand/render_mascot.sh <path>/social/brand/threkir/mascot/grisnir.blend

`scripts/brand/render_mascot.py` poses the rig and renders each file at the
size it ships at (Eevee, the model's flat toon shading, a transparent film).
The wrapper only trims the transparent margin, writes the rest-day WebP
twins, copies the phone assets and regenerates
`apps/web/src/lib/share/grisnir_badge_data.ts`. Nothing is scaled down from a
larger still.

## Files

| File | Size (px) | Bytes | Pose | Used by |
|---|---|---|---|---|
| `grisnir-badge-256.png` | 166 × 248 | 35,964 | Standing, 3/4 view | Web run share card (map style); inlined as `grisnir_badge_data.ts` into the `/og/{run,route,badge,challenge,recap}` unfurls; copied to `apps/mobile_{android,ios}/assets/brand/grisnir/` for the phone's run share card |
| `grisnir-rest-192.png` / `.webp` | 188 × 156 | 23,044 / 14,986 | Lying down, legs folded under | Web dashboard rest day, 1x |
| `grisnir-rest-384.png` / `.webp` | 368 × 304 | 60,891 / 37,986 | Same | Web dashboard rest day, 2x; copied to the phones for Home's rest-day card |

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
  lost run.
- **Never a nag.** No streak guilt. On rest days he rests, with at most one dry
  line (Thor's goats are back by morning).
- **Small and out of the way** on share cards: a corner, never over the route,
  the stats or the runner's name.
- **No AI-generated variations.** A new pose or size is a new render from the
  model.
- **The runner can hide him** (`show_mascot`, docs/backend/settings.md).
