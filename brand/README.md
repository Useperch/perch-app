# Perch brand mark

The Perch owl mark (symbol only, no wordmark). Pure black `#000000` on transparent.
Brand background is the warm cream `#EBE8DF` used in the source artwork.

## Files

| File | Use |
| --- | --- |
| `perch-owl.svg` | **Primary asset.** Scalable vector, fill is `currentColor` (theme it via CSS `color`). |
| `perch-owl-black.svg` | Same path, hard-coded black fill. Use where `currentColor` isn't supported. |
| `perch-owl-mark-transparent.png` | High-res transparent PNG (tight crop, 2000px tall). |
| `perch-owl-256.png` / `-512.png` / `-1024.png` | Transparent PNGs, owl centered on a square canvas with padding (app/icon use). |
| `perch-owl-white.jpg` | Mark on white, square. |
| `perch-owl-cream.jpg` | Mark on brand cream `#EBE8DF`, square. |

Need another size? Re-render from the SVG — it's the source of truth:

```sh
rsvg-convert -h 1024 perch-owl-black.svg -o out.png      # raster at any height
rsvg-convert -h 1024 -b "#EBE8DF" perch-owl-black.svg -o out-cream.png
```

## Clear space & color

- **Clear space:** keep padding ≥ the owl's ear-tuft height around the mark.
- **Single-color only.** Reverse use: set the fill to the background's contrasting tone
  (`perch-owl.svg` + CSS `color`, or recolor the path).
- Minimum legible size ≈ 24px tall.

## Provenance

**Geometrically rebuilt** from the supplied reference (not auto-traced) so the curves
are clean Béziers that stay crisp at any scale. The owl is one `<path>` with
`fill-rule="evenodd"`: an outer horseshoe silhouette (ears, crown, cheeks, belly, tail,
feet) plus three islands — two almond eyes and the diamond beak. The head is symmetric
about `x = 120.5` in the path's `0–215` coordinate space.

`perch-owl.build.py` regenerates the SVG from named landmark points — edit a coordinate
there and re-run (`python3 perch-owl.build.py`) to tweak the mark, rather than hand-editing
path data.
