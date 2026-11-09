# Snapshot overlays: why they are drawn into the pixels

Until 2026.11 measurements were added to a snapshot through `export_fig`: `imshow` of the whole image
in a temporary figure, `plot`/`text` on top, `export_fig -native`, then a nearest-neighbour resize back
to the image size. From 2026.12 `controllers.Snapshot` draws lines and labels directly into the output
image (`collectOverlayItems` + `burnOverlayItems`) and `export_fig` is not used by MIB any more.

## Measured (2026-11-09)

8240 x 8232 RGB, 7 ROIs, separate `matlab -batch` process per route, Threadripper 3945WX, R2026a.
Time is the fusing step only, after the first (warm-up) call; memory is the peak working set above the
level at the start of the step.

| Route | Time | Peak above start | Stroke for LineWidth 2 |
|---|---|---|---|
| `imshow` + `export_fig -native` (old) | 20-25 s | 1.8 GB | 23 px, depends on the figure size |
| Same with `imshow(..., 'Border', 'tight')` | 19-24 s | 1.8 GB | 17 px, depends on the figure size |
| `insertShape` on the full image | 0.45 s | 0.8 GB | set by the code |
| Direct pixel drawing (chosen) | 0.23 s | 0.6 GB | set by the code |
| Direct, output resized to 2000 px | 0.23 s including the resize | 0.4 GB | scales with the output |

Whole snapshot to BMP in the real dialog at the same size, 3 runs after warm-up: no overlays 0.79 s,
7 ROIs 0.9-1.1 s, 7 ROIs + 300 measurements with labels 2.7-2.8 s.

## Problems of the old route that disappeared

- `export_fig` returns one channel when the figure has only gray pixels, which broke `addScaleBar`.
- Coordinates were plotted unconverted on the fetched image, so overlays were lost or misplaced with
  the shown area (measurement at 600-700 in a view of 513-1024 was missing from the output), and the
  same mapping is wrong for downsampled BigData pyramid levels.
- Line width and font size depended on the size of the temporary figure.
- The lines went through a nearest-neighbour resize.

## Decisions

- Geometry comes from the existing `addROIsToPlot` / `addMeasurementsToPlot`, called on an invisible
  axes without an image and read back from the created objects. Reimplementing the measurement types
  in the renderer would have made a second definition of how an overlay looks.
- Drawing happens after crop and resize, so a single offset and scale per axis covers every crop mode,
  pyramid levels and anisotropic stretching.
- Line, marker and font sizes are multiplied by `max(1, outputWidth / 1000)`.
- `insertText` runs on a small patch around the label: it returns a copy of its input.
