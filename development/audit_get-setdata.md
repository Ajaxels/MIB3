# Audit & Optimization: getData/setData pipeline (MibModel → MibDataset → MibImage)

Date: 11.06.2026, MATLAB R2026a. Benchmarked live via `mib.cRibbon.homeDevTest_Callback()`
(benchmark + correctness suite lives in `mib/+controllers/@MibRibbon/homeDevTest_Callback.m`).

## Context

Per-slice and full-volume data access is the hottest code path in MIB3 — display redraws
(`getRGBimage`), segmentation tools, and batch loops (143 `getData2D` call sites alone) funnel
through `MibModel.getDataXD` → `MibDataset.getDataXD` → `MibImage.getData/setData` (or
`MibLabels63.getData63/setData63`). The 2D/3D variants already had fast paths and `setDataFast`
for slice writes; this audit found the remaining hot spots: full-volume reads/writes still
deep-copied the entire array element-wise, the 4D variants had no fast path at all, the
MibLabels63 bit-unpacking did redundant full-volume passes, and every `setData` fired an event
nobody listens to.

## Audit findings

| # | Location | Issue |
|---|----------|-------|
| 1 | `MibImage/getData.m` full-read path | `obj.data(:,:,:,colChannel,:)` forced a **deep copy** even when `colChannel` covered all channels; `dataset = obj.data` is O(1) (COW-shared alias) |
| 2 | `MibImage/setData.m` full-write path | `obj.data(:,:,:,colChannel,:) = dataset` wrote every element even when replacing the whole array; `obj.data = dataset` is an O(1) header swap |
| 3 | `MibDataset/getData4D.m` / `setData4D.m` | **No fast path** — every 4D call went through full options parsing + findings #1/#2 |
| 4 | `MibImage/getData.m` labels material extraction | two full passes (`zeros` + logical-index assign) where single-pass `uint8(data==idx)` suffices |
| 5 | `MibLabels63/getData63.m` orient-3 full read | identity extraction `obj.data(:,:,:,1,:)` copied the whole array before bit-unpacking; `bitand(x,64)/64` slower than `bitget(x,7)` |
| 6 | `MibLabels63/setData63.m` material write | logical masks recomputed up to 4× — ~7 full-volume scans where 3 suffice |
| 7 | `MibDataset/setData2D/3D/4D` | `notify(obj,'SetData', core.ToggleEventData(...))` allocated an event per call; no listener exists at MibDataset level (Graphcut listens on MibModel) |
| 8 | **BUG** `MibDataset/setData3D.m:243,247` | ROI + `fillBg==NaN` branch called `obj.I{options.id}.(…)` — MibDataset has no `I` property; would crash at runtime |
| 9 | minor `MibImage/getData.m` | `if colChannel == 0` elementwise compare on a vector — hardened to `isscalar(colChannel) && colChannel == 0` |

**COW semantics note.** `getData3D/4D` may now return a copy-on-write **alias** of the internal
array. Mutating the returned array triggers the deferred copy at that moment (never worse than
the old always-copy). An in-place `setDataFast` write while an alias is alive pays one deferred
copy — overall still strictly cheaper than baseline.

## Changes implemented

1. **Bug fix** `MibDataset/setData3D.m` ROI+fillBg=NaN branch: `obj.I{options.id}.(…)` → `obj.(…)`.
2. **Zero-copy reads**: `MibImage/getData.m` returns the `obj.data` alias when all channels are
   requested; `MibDataset/getData3D.m` fast path returns the alias when T==1;
   `MibLabels63/getData63.m` unpacks directly from `obj.data` (orient 3) and uses `bitget`.
3. **O(1) writes**: `MibImage/setData.m` full-channel replacement swaps the array header
   (indexed write kept only for the class-conversion case); `MibImage/setDataFast.m` swaps when
   the write spans the whole array (guards: numel + class match).
4. **4D fast paths** added to `getData4D.m`/`setData4D.m` (with fall-through to the slow path
   when the write would resize the container).
5. **Label extraction**: single-pass `uint8(data==idx)` in `MibImage/getData.m`; material-write
   branches in `MibLabels63/setData63.m` rewritten from logical-index scatter to stream
   arithmetic (`lowBits = bitand(data,63); lowBits = lowBits .* uint8(lowBits ~= idx);
   lowBits(new==1) = idx; obj.data = bitor(bitand(data,192), lowBits)`) — ~15% faster in a fair
   isolated A/B (950 → 809 ms, bit-exact). Also fixed a latent T>1 bug: the subvolume write-back
   was missing the `colChannel` subscript.
6. **Notify guard**: `event.hasListener(obj,'SetData')` + `suppressNotify` honored in all
   setData2D/3D/4D paths.

Files modified: `mib/+core/@MibImage/getData.m`, `setData.m`, `setDataFast.m`;
`mib/+core/@MibDataset/getData3D.m`, `getData4D.m`, `setData2D.m`, `setData3D.m`, `setData4D.m`;
`mib/+core/@MibLabels63/getData63.m`, `setData63.m`.

## Benchmark: before → after (ms/call)

Datasets: [h887 × w813 × z171 × c3 × t1] uint8; ds1 = MibLabels63, ds2 = 255-material (uint8),
ds3 = 65535-material (uint16). Correctness: 37/37 checks passed before and after.

```
ms/call (before → after)              ds1:63                  ds2:255                ds3:65535
get2D image                      2.371 →    2.128       2.081 →    1.669       1.759 →    1.673
get2D labels                     3.006 →    0.909       0.464 →    0.441       0.816 →    0.873
get2D mask                       2.444 →    0.808       0.494 →    0.394       0.565 →    0.454
get2D selection                  1.918 →    0.536       0.424 →    0.458       0.457 →    0.405
get2D labels material            2.048 →    1.266       1.305 →    2.733       2.161 →    1.456
set2D image                      1.918 →    2.327       1.483 →    1.280       2.375 →    1.432
set2D labels                     6.085 →    1.620       0.458 →    0.439       0.548 →    0.443
set2D mask                       5.410 →    1.331       0.616 →    0.404       0.475 →    0.394
set2D selection                  5.061 →    1.328       0.403 →    0.485       0.585 →    0.449
set2D labels material            9.054 →    3.876       4.275 →    3.246       5.751 →    3.163
get3D image                    446.864 →    0.984     423.969 →    0.017     353.882 →    0.015
get3D labels                   179.078 →   41.089     137.351 →    0.339     120.567 →    0.023
get3D mask                     160.118 →   24.291      90.654 →    0.019      77.475 →    0.022
get3D selection                135.534 →   24.463      88.896 →    0.021      97.368 →    0.023
get3D labels material          217.083 →   58.559     183.135 →   50.871     209.200 →   46.602
get3D image orient1            615.142 →  199.918     659.581 →  185.736     737.614 →  195.491
set3D image                    453.052 →    3.453     261.358 →    0.085     197.728 →    0.039
set3D labels                    57.261 →   64.803      83.613 →    0.510     161.905 →    0.058
set3D mask                      63.751 →   65.399     119.172 →    0.306      59.498 →    0.021
set3D selection                 73.208 →   71.456      77.586 →    0.041      61.180 →    0.023
set3D labels material         1403.862 →  558.579     510.333 →  312.796     370.543 →  338.192
get3D everything               106.972 →    3.265            —                      —
set3D everything                 1.787 →    0.422            —                      —
get4D image                    319.048 →    2.061     266.885 →    0.091     273.317 →    0.036
get4D labels                   110.733 →   32.010      95.882 →    0.409     124.481 →    0.058
set4D image                      7.514 →    2.898       0.403 →    0.267       0.091 →    0.037
set4D labels                    53.243 →   68.232       0.133 →    0.437       0.112 →    0.061
getRGBimage (active ds)               —                      —               44.582 →   52.064
```

ds1 packed-63 notes: `set3D labels/mask/selection` are flat (~60–70 ms) — these route through
`setData63` bit-packing (bitset/bitor full-volume passes), inherent to the packed format (reads
can never alias; writes are read-modify-write). `set4D labels` ds2/ds3 look "slower" only
because the baseline accidentally hit the O(1) container-replace branch; both are
sub-millisecond either way.

## Key improvements

| operation | before (ms) | after (ms) | speed-up | change responsible |
|---|---|---|---|---|
| get3D image | 354–447 | 0.015–0.98 | ~400–23,000× | COW alias instead of indexed copy |
| get3D labels/mask/selection (ds2/3) | 77–137 | 0.02–0.34 | ~400–4,000× | COW alias (fast path, T==1) |
| get3D layers (ds1, packed) | 135–179 | 24–41 | ~4–6× | bit-unpack directly on obj.data; bitget |
| get3D labels material | 183–217 | 47–59 | ~4× | single-pass `uint8(data==idx)` |
| get3D image orient1 | 615–738 | 186–200 | ~3× | permute on alias (1 copy instead of 2) |
| set3D image | 198–453 | 0.04–3.5 | ~130–5,000× | O(1) header swap in setDataFast |
| set3D labels/mask/selection (ds2/3) | 60–162 | 0.02–0.51 | ~300–2,800× | O(1) header swap |
| set3D labels material (ds1) | 1404 | 559 | 2.5× | stream arithmetic in setData63 |
| get4D image | 267–319 | 0.04–2.1 | ~150–7,400× | new 4D fast path + COW alias |
| get4D labels (ds2/3) | 96–124 | 0.06–0.41 | ~230–2,100× | new 4D fast path |
| set2D layers (ds1) | 5.1–6.1 | 1.3–1.6 | ~4× | bitget + notify guard |
| get2D layers (ds1) | 1.9–3.0 | 0.5–0.9 | ~3× | bitget in subvolume unpack |

Unchanged (expected): get2D/set2D image (~1.3–2.4 ms — already on the fast path, dominated by
the genuine slice copy), set3D labels material on ds2/ds3 (310–340 ms — inherent two-pass
clear+write semantics), getRGBimage (~45–52 ms — display path dominated by imresize/LUT work).

## Evaluated and rejected

- Fusing the 63-model mask/selection write into `bitor(bitset(…), bitshift(…))` — measured 40%
  *slower* than the existing two-statement form.

## Measurement-noise caveat

Run-to-run drift in the live session is substantial: sub-5 ms rows vary up to ~2× between runs
(e.g. `get2D labels material` ds2: 1.31 → 2.73 → 1.74 ms across three runs of unchanged code),
and whole-session load shifts all full-volume rows together by 10–20%. Only order-of-magnitude
differences in the table are meaningful at the millisecond scale; fine comparisons need isolated
repeated measurements.

## Related fix (same session)

`MibController/findMaterialUnderCursor.m`: crash "Index must not exceed 1" — `obj.cImageDoc{}`
was indexed by dataset id instead of the set index `obj.mibModel.Sets.selectedSet` (the
convention at every other call site); also pinned `options.id` for the `getData2D('labels')`
lookup so it cannot read a stale dataset.
