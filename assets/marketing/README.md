# Marketing art for the public pages

Generated art for the landing page and the auth shell ([decisions.md § 1620](../../docs/architecture/decisions.md)). Everything here is a script, and the outputs are committed under `apps/web/static/marketing/`. Regenerate the art; don't edit the images by hand.

| File | Tool | Role |
|---|---|---|
| `terrain.py` | plain Python | The one seeded heightfield and route both generators read, so the render and the contour map show the same place. |
| `scene.py` | Blender 5.x, Cycles | Night landscape: contour lines in the ground shader, the route glowing in the wordmark's ember to magenta ramp, start and finish markers. Two cameras: `hero` (2400x860) and `panel` (1200x1500). |
| `contours.py` | plain Python | Marching squares over the heightfield, drawn as `topo.svg`. The web uses it as a CSS mask, so the page supplies the colour. |
| `gen-marketing.sh` | Blender + ImageMagick | Renders, adds bloom, exports the WebP sizes and writes `topo.svg`. |

## Run

```bash
assets/marketing/gen-marketing.sh                 # full quality, ~2 min on the CPU
SAMPLES=32 assets/marketing/gen-marketing.sh      # quick look
SKIP_RENDER=1 assets/marketing/gen-marketing.sh   # re-grade the last render only
```

`scene.py` uses OptiX when a GPU is available, then CUDA, and otherwise renders on the CPU with OIDN denoising. A driver problem makes the render slower but doesn't stop it. Renders land in `out/` (gitignored). Not run in CI (no Blender), same as `../gen-icons.sh`.

## Rules the pages rely on

- **No copy on a picture.** The hero terrain is anchored below the call-to-action buttons, and the auth panel's art follows the panel copy in the page flow. A raster can't be contrast-checked, so if you reframe a camera, keep the bright horizon out of any area where text might sit.
- **The sky meets the ramp.** The render's sky is the hero ramp's plum, so the art's top fade blends into the page. If you change `PLUM*` in `scene.py`, change the ramps with it, or the seam shows.
- **Size.** The 1600px hero is about 30 KB. If an output grows by an order of magnitude, the encoder settings changed, not the art.
