# Cancelable downloads with `matlab.net.http` - what does not work as documented

Background for `core.DownloadProgressMonitor` (`mib/+core/@DownloadProgressMonitor/`). The class
docblock says how to use it; this note records why it is built the way it is. Everything below was
measured on MATLAB R2026a Update 1 (October 2026) against `mib.helsinki.fi`, `dl.fbaipublicfiles.com`
and `zenodo.org`.

## Why not `webread` / `websave` / `unzip(url)`

They block until the whole file has arrived. A `uiprogressdlg` Cancel button can only be read after
the transfer is over, and the bar cannot move. That is acceptable for kilobytes; MIB downloads up to
2.4 GB (SAM `vit_h` checkpoint), measured sizes:

| Download | Size |
|---|---|
| SAM1 checkpoints | 358 MB - 2446 MB |
| SAM2 checkpoints | 150 MB - 857 MB |
| MIB update `MIB3_Matlab.zip` | 137 MB |
| DeepLabV3 templates | 59 - 129 MB |
| Example dataset Trypanosoma (image + model) | 2 x 118 MB |
| U-Net encoders | 10 - 84 MB |
| SAM1 onnx zip | 6 MB |

All servers send `Content-Length`, so a real percentage is always available.

`matlab.net.http.RequestMessage.send` with `HTTPOptions.ProgressMonitorFcn` is the only built-in
route that runs MATLAB code *during* a transfer.

## Surprise 1 - `ProgressMonitor.CancelFcn` is Ctrl+C

The documented way for a monitor to stop a transfer is to call `obj.CancelFcn()`. MATLAB's own
help for the property says it "has the same effect as interrupting the operation in the command
window". In practice: `send()` ends with

```
Operation terminated by user during matlab.net.http.internal.HTTPConnector/copyContentToByteArray
```

which `try/catch` does **not** catch, not even around the outermost call. In a GUI callback it
unwinds the whole callback (the progress dialog stays open, no cleanup runs except `onCleanup`) and
prints red text in the command window. The mechanism: `ProgressReporter.update` returns `ok = false`
to the C++ `InterruptibleStreamCopier`, which raises the interrupt.

**What works:** raise an ordinary `error()` from `set.Value`. `send()` passes it through as a normal
`MException`, and `download` catches it. Verified: a cancel 1.5 s into a 118 MB download returns
`cancelled = true` about 1.5 s later, data empty, nothing on the command line.

## Surprise 2 - `Interval` does not pace the updates

`ProgressMonitor.Interval` reads as "seconds between updates". It only delays the **first** `Value`
update of a direction; `ProgressReporter.update` then sets `Value` on every received chunk ("Once it is
started, we don't wait for interval"). Measured on a 118 MB download: **2399 `Value` updates in 25 s**,
arriving in bursts several ms apart with ~0.25 s gaps between bursts.

Consequences of the first implementation, which wrote the dialog on every update and smoothed the speed
exponentially per chunk (`0.7 * old + 0.3 * chunkBytes / chunkSeconds`):

- the shown speed jumped between 2 and 79 MB/s while the true average was ~1.1 MB/s (a chunk over a
  few ms gives a meaningless rate, and the bursts dominate any per-chunk average)
- ~100 dialog redraws per second

**What works:** keep checking Cancel on every call (cheap, keeps Cancel instant), but refresh the
dialog at most every 0.5 s, and compute the speed as bytes over the last 3 s of those refreshes.
Result on a full 118 MB download: 77 refreshes, speed rising smoothly 0.7 -> 3.4 MB/s against a true
average of 2.93 MB/s.

## Surprise 3 - `ConvertResponse = false` silently disables `FileConsumer`

For in-memory downloads `HTTPOptions.ConvertResponse = false` is wanted: the body comes back as raw
`uint8` whatever `Content-Type` the server reports (`mib.helsinki.fi` sends none for `.raw`). With a
`matlab.net.http.io.FileConsumer`, however, the same option makes `send()` bypass the consumer: status
200, `Body.Data` holds all the bytes, **and no file is written**.

```matlab
r = matlab.net.http.RequestMessage().send(url, ...
        matlab.net.http.HTTPOptions('ConvertResponse', false), ...
        matlab.net.http.io.FileConsumer(fn));
isfile(fn)      % false - the 6 MB are in r.Body.Data instead
```

This broke every save-to-file download until it was found by the SAM test (`unzip` could not find the
temporary zip). **What works:** set `ConvertResponse = false` only when no file is written; `download`
also errors when a file download reports success but the file does not exist, so this cannot fail
silently again.

## Other decisions

- **Partial files are always deleted** - on cancel, on HTTP error and on any network error. SAM writes
  the checkpoint straight to its final name and later only tests `isfile()`, so a truncated `.pth` would
  be reused as valid.
- **Mirrors as a cell array** (`download({url1, url2}, ...)`): the next address is tried only after an
  error; a cancel returns without an error and so never starts the next one. Replaced three hand-written
  nested `try/catch` blocks (SAM, MIB update, U-Net encoder).
- **Speed of the transfer itself** is the same as `webread`: 13.9 MB in 9.1 s vs 9.1 s
  (`ConvertResponse = false` + monitor). An earlier gap of ~50 % was mostly network variance, partly
  `BinaryConsumer` (9.5 s), which is no longer used.
- **The monitor sets the dialog message at the start of each file**, because the first `Value` update
  comes only after the connection is made and `Interval` has passed.

## Where it is used

| Caller | What |
|---|---|
| `MibRibbon/homeExamples_Callback.m` | Example datasets (raw, in memory) and DeepMIB example projects (zip) |
| `MibImageDocument/segmentationSAM_requirements.m` | SAM checkpoints and SAM2 configs (with mirror), SAM1 onnx zip |
| `UpdateCheck/UpdateCheck.m` | MIB update zip (HTTPS, then HTTP) |
| `MibDeep/generateUnet2DwithEncoder.m` | U-Net encoders (HTTP, then HTTPS) |
| `MibDeep/generateDeepLabV3Network.m`, `generate3DDeepLabV3Network.m` | DeepLabV3 templates |

Not converted on purpose: small JSON/text `webread` calls (Zarr metadata, `io.RemoteStore`, version
check) and third-party `external/export_fig`.
