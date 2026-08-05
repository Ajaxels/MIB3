# Bug report draft — MathWorks Technical Support

**Product:** Computer Vision Toolbox / Image Processing Toolbox (`images.dltrain` training framework)
**Release:** R2026a (also present in earlier releases that ship `images.dltrain.internal.dltrain`)
**Affected functions:** `trainSOLOV2`, and any other trainer built on `images.dltrain.internal.dltrain`

---

## Summary

When a training run started with `trainSOLOV2` is stopped early through the `OutputFcn`
callback, the function does not return promptly. Instead it keeps looping internally until
the configured `MaxEpochs` is reached. The time taken to return is proportional to the
number of epochs that were *left*, not to the amount of training actually performed.

With `CheckpointPath` set, this is severe: a checkpoint file is still written for each of
the remaining epochs, so stopping a long run early can block MATLAB for hours and write
hundreds of gigabytes of duplicate network files to disk.

## Expected behaviour

`trainSOLOV2` returns shortly after the `OutputFcn` returns `true`, as `trainnet` and
`trainNetwork` do.

## Observed behaviour

`trainSOLOV2` continues to occupy MATLAB for a time proportional to
`MaxEpochs - epochAtWhichStopWasRequested`, and continues to write checkpoint files during
that period.

---

## Reproduction

Attached script: **`dltrainStopRepro.m`**. It trains on four synthetic
256×256 images with one object each. The `OutputFcn` requests a stop at iteration 3 in both
runs; the only difference between the runs is the value of `MaxEpochs`:

```matlab
runOnce(5);
runOnce(20);
...
trainingOpt = trainingOptions('adam', ...
    'MaxEpochs', maxEpochs, ...
    'MiniBatchSize', 1, ...
    'CheckpointPath', checkpointFolder, ...
    'OutputFcn', @iStopAtIterationThree);

trainSOLOV2(trainingStore, detector, trainingOpt, 'FreezeSubNetwork', 'backbone');

function stopFlag = iStopAtIterationThree(trainingInfo)
    stopFlag = trainingInfo.Iteration >= 3;
end
```

### Result

| `MaxEpochs` | stop requested at | time until `trainSOLOV2` returned | checkpoint files written |
|---|---|---|---|
| 20  | iteration 3 | 45.3 s | 20 |
| 400 | iteration 3 | 765.5 s | 396 |
| 5  | iteration 3 | 15.7 s | 5 |
| 20 | iteration 3 | 42.2 s | 20 |

Both runs stop at the same iteration, so both should return after roughly the same time.
Instead the elapsed time and the number of checkpoint files both scale with `MaxEpochs`.

---

## Cause

`images.dltrain.internal.SerialTrainer/fit` (`SerialTrainer.m`, around line 73):

```matlab
function stop(self)
    self.StopTraining = true;
end

function TF = keepTraining(self)
    TF = hasdata(self.DataQueue) && ~self.StopTraining;
end

...

for epoch = 1:self.TrainingOptions.MaxEpochs      % <-- never exited early
    while keepTraining(self)                      % <-- only this loop is exited
        ... one training iteration ...
        notify(self, 'IterationEnd', data);
    end

    self.EpochCount = self.EpochCount + 1;
    data.Epoch = self.EpochCount;
    data.IsValidationIteration = false;
    notify(self, 'EpochEnd', data);               % <-- still fires every remaining epoch
    reset(self.DataQueue);
    if self.TrainingOptions.Shuffle == "every-epoch"
        shuffle(self.DataQueue);
    end
end
```

`stop()` sets a flag that only short-circuits the inner `while`. The outer `for epoch`
loop keeps iterating over every remaining epoch, and each of those iterations still:

- fires `EpochEnd`, which `dltrain.m` (around line 105) has wired to
  `images.dltrain.internal.CheckpointSaver/saveCheckpoint` — so the full network is written
  to disk again for every remaining epoch that matches `CheckpointFrequency`;
- calls `reset` and `shuffle` on the data queue.

`images.dltrain.internal.ParallelTrainer/fit` (around line 130) has the same structure and
the same issue.

A `break` after the inner `while` when the stop flag is set would resolve it:

```matlab
    if self.StopTraining
        break
    end
```

## Side effect worth noting

Because `evt.Iteration` stops advancing while `evt.Epoch` keeps incrementing, all the
checkpoint files written during this phase are named after the *same* iteration number and
differ only by timestamp (`iGenerateCheckpointName` in `CheckpointSaver.m` uses
`evt.Iteration`). They are also byte-for-byte the same network.

## Impact

This is reached through the ordinary "stop training early" workflow, which is a normal way
to use a long-running training session. On our side (Microscopy Image Browser, an
instance-segmentation workflow built on `trainSOLOV2`) a user pressing Stop on a run with a
high `MaxEpochs` left MATLAB unresponsive for over an hour with no way to tell what was
happening.
