# 05_stitch_smoke_pattern_folders — filename-pattern + folder Z-stacks

Tiles are **folders** of slice images whose **folder names carry the MIB2 chop
pattern** `_Z##-X##-Y##`. Use it to exercise the *Tiles are folders (Z-stacks)*
modifier with the **Filename pattern** layout source — the combination that fails
when folders are named grid-style (e.g. `tile_r1c1`), which carry no Z/X/Y tokens.

## What it exercises

- Filename-pattern layout source parsing `Z##-X##-Y##` tokens from folder names.
- Folder-Z-stack reading (as in `04_stitch_smoke_folders`) combined with pattern parsing.
- The pattern source's overlap support: real ~22 % XY overlap + jitter, so measure +
  optimize actually register the tiles (not just a layout smoke test).

## Dataset

- 460×460×12 volume: every slice carries the SAME lines + circles as the 2D baseline
  (a bad XY seam breaks a line on every slice) + mild per-slice noise.
- 2×2 tiles, ~22 % overlap, ±4 px jitter; four `stack_Z01-X##-Y##` folders of
  `slice_###.tif`.
- Outputs to `temp\stitching_test\05_stitch_smoke_pattern_folders\`.

## Run

```matlab
run('development\stitching\05_stitch_smoke_pattern_folders\generateSmokePatternFolders.m')
```

Stitch ribbon → Layout source = **Filename pattern**, tick **Tiles are folders
(Z-stacks)** → set Overlap X/Y ≈ 22 (or tick **Estimate overlap**) → browse
(multi-select the four `stack_…` folders, or pick the parent) → Measure overlaps →
Optimize positions → Stitch.

Expected origin error ≈ 0.02 px. See `smoke_tests.md` test **5**.
