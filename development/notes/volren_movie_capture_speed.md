# Why 3D viewer animations record at ~1 frame per second

Recording an animation or spin movie from the 3D volume viewer
(`controllers.VolRenApp.makeAnimation` → `controllers.MakeMovie`) costs roughly **0.8 s per
frame**, so a 360-frame animation takes about 5 minutes. This note records what was measured
so the investigation is not repeated.

**It is not the rendering.** Moving the camera and letting the viewer redraw costs ~20 ms.
Practically all of the time is the single `getframe` call inside
`controllers.VolRenApp.grabFrame` that reads the rendered pixels back out of the viewer.

## Measurements

R2026a, Windows 11, RTX 3080 Ti, 160³ uint8 test volume, 640×560 capture.

| capture route | ms/frame |
|---|---|
| camera update + redraw, no capture | **20** |
| `getframe(figure, panelRect)` - what `grabFrame` does today | 830 |
| `getframe(viewer)` - capture the viewer3d object directly | 820 |
| `exportapp(fig, file)` | 967 |
| `print(fig, '-RGBImage')` | errors: not supported for UI components |
| `viewer.takeSnapshot()` | 0.5, but yields no pixels - it only sets Live Editor flags |
| the same uifigure with a plain `uiaxes` instead of viewer3d | **55** |
| classic figure + `patch` of an extracted isosurface | **50** |

## Things that make no difference

- **Capture size** - 635 ms at 160×160 vs 857 ms at 640×640. The cost is mostly fixed;
  a 10×10 px capture still takes 782 ms.
- **Figure type** - a classic `figure` hosting the viewer is just as slow (838 ms).
- **`Visible` on/off** - 816 vs 793 ms, and a hidden figure still captures real pixels.
- **`RenderingQuality`** - low/medium/high all land at ~780 ms.
- **Whether the camera moved** - capturing an unchanged scene still costs 768 ms.
- **Batching** - putting several viewers side by side and grabbing them in one `getframe`
  is *worse*: the cost scales per WebGL canvas (~0.7-0.8 s each), not per call. A 3×3 grid
  took 7.3 s for a single capture.

## Conclusion

`viewer3d` renders into a Chromium/WebGL canvas (`RendererInfo` reports
`WebKit WebGL … ANGLE (NVIDIA …) Direct3D11`). Pulling those pixels back into MATLAB is a
synchronous cross-process round trip, and it is specific to viewer3d rather than a general
`uifigure` weakness - the same figure with ordinary `uiaxes` captures 15× faster. No public
MATLAB API avoids it.

A ~16× faster path exists only by leaving viewer3d behind: extract the geometry once
(`extractIsosurface`, 145 ms) and animate it as a `patch` in a classic figure, which captures
at 50 ms/frame. It was **not** implemented, because the result would no longer match the
interactive viewer - no volume rendering or slice planes, and lighting, background gradient,
scale bar and orientation axes would all have to be approximated. Revisit only if a separate
"fast preview export" is wanted, accepting that it looks different.

## What was done instead

`controllers.MakeMovie` now shows the frame count and a live time estimate on every frame
(`updateMovieProgress`), and reports honestly when a recording is cancelled, naming how many
frames reached the partial file rather than printing "movie saved".
