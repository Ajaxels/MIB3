# DeepMIB - Potential Improvements

Register of DeepMIB ideas that are **understood but deliberately not implemented yet**. Each entry
records *why* it is worth doing, what evidence motivated it, and a plan concrete enough to pick up
cold. Nothing here is scheduled - moving an entry out of this file into a real plan is a separate
decision.

Related documents in this folder:

- [`instance_2d_plan.md`](instance_2d_plan.md) - 2D Instance (SOLOv2) workflow, plan of record
- [`instance_3d_plan.md`](instance_3d_plan.md) - 3D instance stitching improvement plan
- [`stitchInstances2Dto3D.md`](stitchInstances2Dto3D.md) - the 2D->3D stitching algorithm
- [`update_3D_unet.md`](update_3D_unet.md) - `unet3dLayers` -> `unet3d` migration
- [`deepmib_dimensions_problems.md`](deepmib_dimensions_problems.md) - MIB3 axis-order pitfalls

---

## 1. Weight averaging over checkpoints (SWA) to finalize a network

**Status:** deferred (2026-08-14), no code written.

### The problem

`OutputNetwork = 'last-iteration'` returns the weights left by the final update. It does **not**
scale anything by the learning rate - but near a minimum the optimizer does not settle, it orbits
in a ball whose radius is proportional to the learning rate. The last iterate is therefore one
random draw from that ball, and with a large learning rate it can sit well off the centre.

Measured on the mitochondria SOLOv2 runs (`c:\temp\DeepMIB_Mito_instances\`, August 2026), the
spread of the training loss over the final 10% of iterations tracks the learning rate directly:

| Run | Learning rate at the end | std of training loss, last 10% |
|-----|--------------------------|--------------------------------|
| Frozen backbone, 12-13 Aug | 8.1e-3 | 0.0825 |
| Trainable backbone, 13-14 Aug | 6.9e-4 | 0.0066 |

The existing mitigations are both indirect:

- **Learning-rate annealing** shrinks the ball, so the last iterate lands closer to the centre. It
  works, but it costs training time at rates too small to make progress, and DeepMIB's default
  `LearnRateDropFactor = 0.9` with a long `LearnRateDropPeriod` barely anneals at all (the 12-Aug
  run went 0.01 -> 0.0081 across 1462 epochs, a 19% reduction).
- **`OutputNetwork = 'best-validation-loss'`** picks the minimum of a noisy validation curve, which
  is selection on noise rather than averaging - especially with a small validation set.

MATLAB exposes neither SWA nor EMA through `trainingOptions`, `trainnet` or `trainSOLOV2`.

### The idea

Averaging the weights of several late checkpoints puts the network at the **centre** of the ball
directly, instead of hoping the last draw was a good one. This is Stochastic Weight Averaging
(Izmailov et al., 2018), and DeepMIB already saves everything it needs: `T_SaveProgress` writes
`net_checkpoint__<iteration>__<timestamp>.mat` into `<ResultingImagesDir>/ScoreNetwork/` at
`CheckpointFrequency`.

So this can be a **post-processing utility**, not a change to the training loop - it works
retroactively on checkpoint folders from runs that have already finished.

### Implementation plan

1. **Utility function**, e.g. `mib/+deepmib/averageCheckpoints.m`:
   `averagedNet = deepmib.averageCheckpoints(checkpointDir, options)` with
   `options.NumCheckpoints` (default: last 5), `options.RecomputeBatchNorm` (default true) and
   `options.TrainingDatastore`.
2. Load the newest N checkpoints, verify they share an identical layer graph, and average the
   `Learnables` table value-by-value. Refuse with a clear error if the architectures differ.
3. **BatchNorm statistics** are the one part that is not a plain average - see caveats below.
4. Save through the normal `.mibDeep` writer so the result is a first-class network: the same
   variables `startTrainingInstances` / `startTraining` save (`net`, `BatchOpt`, `classNames`,
   `inputPatchSize`, ...), taken from the newest checkpoint's companion config.
5. **UI:** a button on the Options tab, or an entry in the existing checkpoint dialog that already
   enumerates `ScoreNetwork/*.mat` in `startTrainingInstances.m`. The dialog is the cheaper hook -
   it already has the file list and the user is already thinking about checkpoints there.

**Do semantic workflows first.** They train through `trainnet`/`trainNetwork` and hand back a
`dlnetwork` whose `Learnables` is a plain table - averaging is a few lines. The `solov2` detector
wraps its network more deeply and the BatchNorm recomputation would need the instance training
datastore rebuilt outside `startTrainingInstances`, so instance support is a second step.

### Caveats that must be respected

- **Same basin only.** Averaging checkpoints from different phases of training produces nonsense.
  The utility should only be pointed at late checkpoints taken at a small learning rate, and the
  documentation must say so plainly. Consider warning when the spread of iteration numbers is large
  relative to the run, or when the learning rate changed between the selected checkpoints.
- **BatchNorm running statistics.** After averaging the weights, the stored running mean/variance
  no longer match the averaged network. The standard SWA recipe recomputes them with one forward
  pass over the training data in training mode. Averaging the `State` table instead is an
  approximation that usually works but is not equivalent - if `RecomputeBatchNorm` is false, say
  so in the saved config so a later comparison is not confounded.
- Averaging is not free of risk: if the checkpoints straddle a loss spike, the average can be worse
  than the last iterate. The utility should report the training loss of each input checkpoint so
  the choice is visible.

### Open questions

- Should the averaged network replace the `.mibDeep` or be saved alongside it? Replacing loses the
  ability to compare, so alongside seems right, but it doubles the disk footprint of a 70 MB file.
- Is there value in exposing an EMA option during training instead? It would need a hook in the
  `OutputFcn`, which for `trainSOLOV2` is already carrying the stop/emergency-brake machinery
  (see `deepmib.customTrainingProgressDisplay`) - considerably more invasive than post-processing.

---

## 2. Automatic two-phase training: frozen backbone then trainable

**Status: IMPLEMENTED 2026-08-15** as the `COCO, frozen then trainable` state of
`T_StartingWeights`, now the default for the 2D Instance workflow. The section below is kept
as the rationale and the record of what was measured; the implementation notes are at the end.

### The problem

For the 2D Instance workflow, `T_StartingWeights` offers `COCO, frozen backbone` and
`COCO, trainable backbone`. The two want **different learning rates**, and `trainSOLOV2` accepts
only one global rate, so the correct recipe is sequential rather than a single setting:

1. train with the backbone frozen at a normal rate (1e-3 to 1e-2) until the loss settles;
2. continue from that network with the backbone trainable at about 1e-4.

Evidence from the mitochondria runs:

| Run | Freeze | Initial LR | Result |
|-----|--------|-----------|--------|
| 05-Aug | backbone | 1e-3 | final loss 0.578 (min 0.345) |
| 12-Aug | backbone | 1e-2 | final loss ~0.65 |
| 13-Aug | none | 3e-3 | loss floor 3.033, **validation mAP 0.000 across all 126 evaluations**, zero detections at threshold 0.05 even on a training image |
| 14-Aug | none, continued from the 12-Aug network | 1e-4 | reached ~0.3 (better than either frozen run) |

The 13-Aug run is the failure mode this feature exists to prevent: at a rate that is perfectly safe
with a frozen backbone, the pretrained weights are destroyed within the first ~100 iterations and
the network never recovers. Users have no way to know that the same number means something
different once the backbone is trainable.

### The idea

A third dropdown state, e.g. `COCO, frozen then trainable`, which runs both phases in one go:
`trainSOLOV2` with `'FreezeSubNetwork', 'backbone'`, then `trainSOLOV2` again seeded with the
returned network and `'none'` plus a reduced learning rate.

### Why it is not a small change

`FreezeSubNetwork` is fixed for the duration of a `trainSOLOV2` call, so this means **two
sequential calls**, and everything downstream of the call in `startTrainingInstances.m` assumes
there was exactly one:

- The custom progress window deletes and rebuilds itself between calls - that is what the
  validation-fallback retry path does at `startTrainingInstances.m:622-629`. The loss curve would
  restart at iteration 1 instead of continuing across the phase boundary.
- The two `info` struct arrays must be concatenated with an iteration offset before the `.score`
  and per-field CSV export, which currently walks `fieldnames(info)` once.
- Stop training, Emergency brake, checkpoint saving and `best-validation-loss` selection all have
  to become phase-aware.

Rough estimate: 200-300 lines plus edge cases, most of it in the progress/reporting plumbing rather
than in the training logic.

### Design question to settle first

The obvious trigger - "switch when the loss plateaus around 0.6" - is **not portable**: 0.6 is
specific to this dataset and this loss composition, and would misfire on the next project. Better
candidates:

- a fixed epoch split (e.g. 70% frozen / 30% trainable), simple and predictable;
- reuse `ValidationPatience` to end phase 1, which is already a familiar knob.

The phase-2 learning rate should be derived from phase 1 rather than entered separately (a fixed
divisor, or an explicit second field), so the user cannot accidentally carry the phase-1 rate over
- which is exactly the mistake that produced the dead 13-Aug network.

### What was measured before building it

The 15-Aug run (`c:\temp\DeepMIB_Mito_instances\DeepMIB_mito_16nm_freeze-unfreeze\`) settled it:
training loss 0.149 (min 0.123) and validation mAP peaking at 0.7575, against ~0.65 loss for the
frozen run and a dead network for the single-phase trainable one. Validation loss fell throughout
(1.029 -> 0.323) rather than turning up, so no overfitting appeared even at epoch 447.

### How it was implemented

- **State:** `'COCO, frozen then trainable'`, first in the 2D Instance list in
  `updateStartingWeightsList.m`, therefore the default.
- **Settings:** `obj.StartingWeightsOpt` (`MinFrozenFraction`, `MaxFrozenFraction`,
  `PlateauWindowEpochs`, `PlateauTolerance`, `TrainableLearnRate`), edited through
  `setStartingWeightsSettings.m` from a button next to the dropdown.
- **Trigger:** plateau detection in `deepmib.customTrainingProgressDisplay`, placed above the
  refresh-rate early return so it sees every iteration. It raises
  `mibDeepTrainingProgressStruct.phaseSwitchRequested` alongside `mibDeepStopTraining`, which is
  what keeps a plateau distinguishable from the user pressing Stop.
- **Phases:** `startTrainingInstances.m` calls `trainSOLOV2` twice; phase 2 is seeded with phase 1's
  network and `'FreezeSubNetwork', 'none'`. `preprareTrainingOptionsInstances` gained an optional
  `trainingOptOverrides` argument so each phase gets its own `MaxEpochs` and `InitialLearnRate`
  without touching `obj.TrainingOpt`.
- **Reporting:** `iNormalizeTrainingInfo` and `iConcatenateTrainingInfo` (local to
  `startTrainingInstances.m`) join the two phases into one continuous `info`, shifting `Iteration`
  and `Epoch` and dropping fields that only one phase produced. Each phase still draws its own
  progress window - unifying the plot across phases was judged not worth the OutputFcn surgery.

### Two bugs the first real run exposed (2026-08-16)

1. **`gpuDevice(index)` resets the device even when that index is already selected**, destroying
   every existing `gpuArray` (`parallel:gpu:array:InvalidData`). `preprareTrainingOptionsInstances`
   called it unconditionally, so building phase 2's options wiped the GPU-resident weights of the
   network phase 1 had just returned, and phase 2 died in `MetricLogger.initializeMetrics` on its
   first validation forward pass. Fixed by selecting only when the device is not already current.
   The other `gpuDevice(selectedIndex)` call sites are safe because they run before any network is
   on the GPU (prediction loads its network from disk first).
2. **A multiplicative phase-2 learning rate cannot express what phase 2 needs.** The frozen phase
   tolerates a wide band (1e-3 and 1e-2 both converged) because it is searching from random heads;
   the trainable phase needs a near-absolute ~1e-4 because it is protecting an already-good
   backbone. `x 0.01` maps 1e-2 correctly but turns 1e-3 into 1e-5. Replaced with an absolute
   `TrainableLearnRate` (default 1e-4), capped at the frozen-phase rate.

### Calibration note (do not lower these blindly)

The plateau rule was replayed over recorded loss curves before the defaults were chosen. With a
10-epoch window and no minimum, it fired after **30 of 7500 iterations** on a run whose loss later
fell from 3.4 to 0.578 - training losses sit on long shoulders and no local test distinguishes a
shoulder from convergence. The 25-epoch window plus a minimum share and a 50-iteration window floor
were what made it correctly stop the dead run while leaving a still-improving run alone.

**Second calibration, 2026-08-17**, after the first full auto run. Defaults moved to
`MinFrozenFraction = 0.1`, `MaxFrozenFraction = 0.25`, tolerance unchanged at `0.01`:

- The frozen phase of a healthy run improves by **more than 5% per 500-iteration window all the way
  to iteration 4500**, so the plateau test never fires on it at any tolerance from 1% to 3%; 5% does
  fire (iteration 2400) and is a false positive. Raising the tolerance therefore buys nothing and
  starts to cost - **leave it at 1%**.
- Consequence: on healthy runs the **cap** is what ends the frozen phase, not the plateau test. The
  test earns its place on pathological runs (the destroyed-backbone curve fires at 900-2000 in every
  configuration tried).
- The cap dropped to 0.25 because the trainable phase is where the gains are: frozen went
  0.61 -> 0.33 over its last 4500 iterations, trainable went 1.28 -> 0.14 in a third of that and was
  still improving when the run was stopped. Note this is a **hypothesis worth one run**, not a
  measured result - a frozen phase stopped at 0.44 instead of 0.33 hands a slightly worse network to
  phase 2, and whether the extra trainable epochs more than repay that has not been tested.
- Corrected an earlier claim in this file's history: "phase 1 is done by 1500-2000 iterations" was
  based on shrinking *absolute* loss deltas. In *relative* terms it keeps improving steadily, which
  is what the plateau rule measures.

Scripts used: `test_plateau.m`, `test_plateau2.m`, `tune_plateau.m` in the session scratchpad.

### Collapse detection added 2026-08-18 (third real run)

The `DeepMIB_mito_16nm_2` run (Resnet50, extended training set, `InitialLearnRate = 0.005`) exposed
the blind spot in the plateau rule: **a flat loss does not mean converged.**

SOLOv2 fails by saturating its category branch to "background everywhere". The loss goes flat at a
high value and the validation mAP stays at exactly `0.000`. The plateau test cannot tell that apart
from convergence, so it dutifully unfroze a network that had never detected anything, and phase 2
was configured for 700 more epochs - **~100 hours** at the measured 13 s/iteration.

Freezing does **not** protect against this. The backbone is safe, but the neck and heads are trained
in both modes and they are what saturates. Measured on the same dataset, all with `adam`:

| Initial LR | Backbone | Last-500 train loss | Best val mAP |
|---|---|---|---|
| `1e-4` | trainable (warm start) | 0.165 | **0.758** |
| `1e-3` | frozen, then trainable | 0.211 | **0.714** |
| `1e-3` | frozen only | 0.560 | (no validation) |
| `3e-3` | trainable | 3.037 | **0.000** |
| `5e-3` | frozen, then trainable | 3.118 | **0.000** |

Every run at or above `3e-3` collapses; every run at or below `1e-3` learns. This **falsifies an
earlier claim** made in this file, in `MibDeep.m` and in `deepmib-train.md` that the frozen phase
"tolerates a wide band, `1e-3` to `1e-2`". That was extrapolated from a single `1e-3` run, never
measured, and it is what led the user to pick `5e-3` as "half of 0.01". All three places corrected.
The `0.01` figure in the <span>Initial learn rate</span> tooltip is MATLAB's **sgdm** default;
DeepMIB uses **adam**, whose default is `0.001`.

**The rule.** Count consecutive validation evaluations reporting `mAP == 0`; at
`StartingWeightsOpt.CollapseEvaluations` (default 8) declare the phase collapsed, stop the run, do
**not** unfreeze, and show a dialog naming the learn rate as the likely cause. Any non-zero mAP
resets the count - one detection proves the head is alive.

mAP was chosen over an absolute loss threshold deliberately: the collapsed loss level depends on
architecture and class count (`~3.1` here), while "detects nothing" does not.

Unlike the plateau test this is **not** bounded by `MinFrozenFraction` - the whole point is to stop
before the cap burns hours. Replayed over all four recorded runs (`test_collapse.m`):

| Run | Expected | Result |
|---|---|---|
| auto-switch RN18, 2-phase | healthy | did not fire over 96 evaluations |
| unfreeze-from-freeze RN18 | healthy | did not fire over 112 evaluations |
| trainable-from-scratch RN18 | dead | **fired at iteration 336** of 6000 |
| RN50 two-phase | dead | **fired at iteration 1092** of 3937 |

Margin: the longest zero-mAP streak in a healthy run is 2 (first detection at evaluation #3), so 8 is
4x clear. On the RN50 run it would have stopped at **3 h 12 min** instead of 11 h 25 min, before
committing to the 4-day phase 2.

**Not extended to the single-phase instance states** (`COCO, frozen backbone`, `COCO, trainable
backbone`), although the `3e-3` run above shows they collapse identically and wasted 6000 iterations.
The settings dialog that configures the threshold is only enabled for the two-phase state, so a
single-phase user could not turn the check off. Wiring that up is the obvious next step if the
detector proves itself.

### Progress gauge overshot in every instance run (fixed 2026-09-10)

The iteration estimate behind the progress gauge was copied from the semantic workflow, where
`trainNetwork` **discards** the observations that do not fill the last complete mini-batch of an
epoch - hence the floor form `ceil((n - mod(n, mb))/mb)`. `trainSOLOV2` trains through
`images.dltrain`, which instead **runs that partial mini-batch as one more iteration**, so the real
count rounds up.

Measured on `SOLOv2_mitos.mibCfg` (9 training images x 4 patches per image = 36 observations,
mini-batch 8, `MaxEpochs` 200, `MaxFrozenFraction` 0.25 -> a 50-epoch frozen phase):

| | iterations per epoch | frozen phase total |
|---|---|---|
| estimate (floor) | 4 | 200 |
| actual | 5 | **250** |

Confirmed from that run's artefacts: the exported `*_Epoch.csv` repeats each epoch number five
times, and the phase-1 checkpoint is named `net_checkpoint__frozenPhaseEnd_250__*`. The gauge is
limited to `[0 100]`, so the needle was drawn 25% past the edge for the last quarter of every phase.

The error is `mb/n` of the total, so it is invisible on large training sets and worst on the small
ones - which is exactly where the two-phase schedule is aimed.

Fixed in `startTrainingInstances.m` (both the phase-1 estimate and the phase-2 one) by computing
`iterPerEpoch = ceil(noFiles/miniBatchSize)` and deriving `maxNoIter` from it. `iterPerEpoch` also
feeds `ValidationFrequencyInIterations` and the plateau detector's `MinIterations`, so both were
off by the same fraction and are now correct too. `findBestMinibatchSize` rounds by workflow for its
"epochs per hour" column. Both progress displays now clamp the gauge to 100 - the estimate stays an
estimate, and a needle past the edge reads as a fault.

**The semantic path was deliberately left on floor**: it is right for `trainNetwork`.

### Still open

Compare the two-phase network against the frozen one on held-out data (object counts and
boundaries on a region never trained on) rather than on the validation curve, which is weak here -
see [`instance_2d_plan.md`](instance_2d_plan.md).

---

## 3. Instance scores: per-object export, and score-guided gap bridging

**Status:** discussed 2026-08-19, no code written. Two related items: the export (3a) is small and
independently useful; the stitching use (3b) is gated on a measurement that has not been run.

Companion entry in [`instance_3d_plan.md`](instance_3d_plan.md) - the stitcher side of this idea is
listed there under the same name.

### Where the scores are today

`segmentObjects` returns a scalar confidence per detected instance. Both stitching modes already
hold it and both throw it away:

- `mib/+deepmib/segmentBlockedImageInstances.m:50` - sorted at line 58 to decide painting order,
  then discarded.
- `mib/+deepmib/segmentImageInstancesIoUMerge.m:103,121` - accumulated into `detScore`; line 182
  already computes `groupScore` (max per merged group), used for paint order at 183, then discarded.

`startPredictionInstances.m` never reads `BatchOpt.P_ScoreFiles` and never creates
`PredictionImages/ResultsScores`. The semantic paths do (`startPrediction2D.m:38`,
`startPrediction3D.m:38`, `startPredictionBlockedImage.m:67` -> `processBlocksBlockedImage` ->
`deepmib.segmentBlockedImage`). `updateWidgets.m:89` does **not** disable the dropdown for
`2D Instance`, so it is live but ignored: selecting a score format silently produces nothing. That
is a plain UI bug and is worth fixing whatever happens to the rest of this section.

### 3a. Export per-object scores

Semantic scores are an `[h w numClasses]` probability image, which is why the AM / mibImg / MAT
image containers make sense there. An instance score is one scalar per object - typically tens to a
couple of hundred per slice - so an image is the wrong container.

Proposed output: a table next to each model,
`PredictionImages/ResultsScores/Score_<name>.csv`, with columns
`SliceIndex, InstanceIndex, Score, Area, CentroidX, CentroidY` (plus bounding box), where
`InstanceIndex` matches the relabelled `1..N` values written into the `.model`, so the two can be
joined directly. Needs the per-tile functions to return the surviving scores alongside the labels,
and `startPredictionInstances` to collect and write them. For `IoU merge` the merged score is
`groupScore`, already computed; for `Centroid in core` it is the score of the emitting detection.

Uses that depend on nothing else being built: filtering weak detections before stitching, sorting
objects for manual review, and informing `absOverlapPixels` / threshold choices.

### 3b. Score-guided gap bridging, and why a dense score map is the wrong tool

Motivating idea: when `utils.instances.stitch2Dto3D` sees a strong overlap across a one-slice gap,
consult a score map on the skipped slice to decide whether the gap is a dropout or a genuine object
end.

**A dense score map cannot answer that**, for a reason that is not size:

- Size is not the objection. A score map needs one channel, not one per object: paint each object's
  pixels with `round(score*255)`. Touching objects need no distinct indices, because identity is not
  being recovered from the map - it is already in the `.model`. That is ~150 MB uint8 for a
  1078x1380x101 stack, and highly compressible because it is piecewise constant.
- **It is empty exactly where the query is.** A map painted from accepted detections is zero on the
  gap slice by construction, because the gap exists precisely because nothing there cleared the
  threshold. The lookup would confirm the gap every time.
- **SOLOv2 offers no fallback.** Unlike semantic segmentation there is no per-pixel objectness
  output; `segmentObjects` returns logical masks plus scalar scores, and the pre-binarisation mask
  logits stay inside MathWorks' implementation.

**What does carry the signal: sub-threshold detections.** A dropout slice usually has a detection
sitting at ~0.25-0.45 that `Threshold = 0.5` discarded. So the mechanism is a two-threshold
(hysteresis) scheme, the instance-level analogue of Canny:

1. predict at a low recall threshold; detections above the confident threshold are real, the rest
   are **tentative**;
2. write tentative objects into a second label layer, never into the main model, so they can never
   become objects on their own;
3. in the stitcher, link A(z) and B(z+2) when they overlap across the gap **and** a tentative
   instance on z+1 overlaps both.

That is direct evidence at the gap slice, it is a pure geometry test, it needs no image data at
stitch time, and it can run off bounding boxes plus the 3a table (kilobytes) instead of a score
volume.

**Risk to respect.** Lowering the threshold feeds the false-positive problem already recorded in
[`instance_3d_plan.md`](instance_3d_plan.md): the shared 2D indices behind the `splitDisconnected2D`
cascade were themselves wrong 2D instances, with the prediction threshold named as a suspect.
Tentative objects must stay quarantined as bridge evidence only, or gaps get traded for that cascade.

### The measurement that gates 3b

Confirm first that gaps are a real failure mode on the target data. The 3D plan's own results point
the other way: Phase C' (centroid-NN bridging) found no benefit on the hard benchmark because the
residual false splits were 52-810 slices apart with zero z-overlap, i.e. not gaps at all; and
`zLookback` already bridges single-slice dropouts blindly, with nothing yet measuring whether it
over-merges.

Cheapest informative test, on the salivary-gland stack: predict twice, at threshold 0.5 and 0.3;
then for every pair that `zLookback = 2` currently bridges, count how many have a 0.3-threshold
detection on the skipped slice overlapping both.

- High fraction -> hysteresis bridging is worth building, and `zLookback` is doing the right thing
  for the right reason.
- Low fraction -> the gaps are real object ends and no amount of score plumbing will help.

Note that the MitoNet benchmark data is off this machine and the Phase C numbers predate the
`splitDisconnected2D` default, so they must be re-measured before being cited either way.

### Key files

- Export: `mib/+controllers/@MibDeep/startPredictionInstances.m`,
  `mib/+deepmib/segmentBlockedImageInstances.m`, `mib/+deepmib/segmentImageInstancesIoUMerge.m`;
  dropdown gating in `mib/+controllers/@MibDeep/updateWidgets.m`.
- Bridging: `mib/+utils/+instances/stitch2Dto3D.m`, with any new stitching parameter going into
  `mib/+utils/+dlgs/stitchInstancesSettingsDlg.m` rather than into the two callers.

---

## 4. Smaller items

- **`T_ConvolutionPadding` for 2D Instance.** Unread by the instance path, but
  `selectArchitecture.m` disables overlapping tiles whenever it is `'valid'`, so a value left over
  from a semantic project silently switches off overlapping tiles for instance prediction. Options:
  force `'same'` and grey it out for the workflow, or make the overlapping-tiles rule
  workflow-aware. Not done: it changes a stored value on workflow switch, which is the behaviour
  that was explicitly rejected for `T_NumberOfClasses`.
- **Validation set sizing for 2D Instance.** The validation datastore now honours
  "Patches per image" and crops deterministic windows when a non-zero random seed is set
  (`startTrainingInstances.m`, `deepmib.readInstancePatch`). Still open: with only a handful of
  validation *images*, `best-validation-loss` remains a weak selector. Consider warning when the
  validation set is below some threshold, or reporting the validation mAP alongside the loss in
  the picked-iteration marker.
