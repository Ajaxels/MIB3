# Deep MIB - 2D Instance Segmentation (SOLOv2)

Training and application of the SOLOv2 network for 2D instance segmentation in Microscopy Image Browser.

---

## Overview

Unlike the semantic workflows, which assign every pixel to a *class* (all objects of the same
type share one label), **instance segmentation** detects each object *individually*: every
object receives its own distinct label, so touching or overlapping objects of the same type are
separated. Deep MIB implements 2D instance segmentation using the MATLAB **SOLOv2** network.

The typical procedure follows the same three phases as the other workflows — with one important
difference: instance segmentation **requires a preprocessing step** before training (see
[Preprocessing](#preprocessing-required-for-training)).

1. **Preprocess** the ground-truth models into the SOLOv2 annotation format (*Directories and Preprocessing tab*).
2. **Train** the SOLOv2 network (*Train tab*).
3. **Predict** new datasets and export the detected objects as MIB models (*Predict tab*).

!!! warning "Support package required"

    `solov2` requires the *Computer Vision Toolbox Model for SOLO V2 Instance Segmentation*
    support package. To install this support package, use the **Add-On Explorer**.

---

## Compatible source datasets

- **Images**: 2D images with **1 (grayscale) or 3 (RGB)** colour channels. Grayscale images are
  automatically converted to RGB, because the SOLOv2 backbone expects 3-channel input.
- **Ground-truth labels**: a MIB `.model` file per image (or a single `.model` file for all
  images when <label class="widget widget-checkbox">Single MIB model file</label> is checked),
  in which **each individual object is painted with its own unique index** (`1, 2, 3, …`) and the
  background is `0`. Touching objects must use different indices to be separated. `uint8` models
  allow up to 255 objects per image; `uint16` models allow many more.
- **Classes**: the current implementation is **single-class** — every detected object belongs to
  one class named `object`. The <span class="widget widget-edit">Number of classes</span> field
  is not used for this workflow.

!!! tip "Preparing instance labels"

    Paint each object as a separate material index in the MIB model (for example, using the
    watershed / object-separation tools), so that `regionprops` can extract one bounding box and
    one mask per object during preprocessing.

---

## Network panel

In the [Network panel](deepmib-networks.md) select:

- <span class="widget widget-dropdown">Workflow</span>: **2D Instance**
- <span class="widget widget-dropdown">Architecture</span>: **SOLOv2**
- <span class="widget widget-dropdown">Encoder</span>: **Resnet18** (lighter, faster) or
  **Resnet50** (heavier, potentially more accurate). These map to the pretrained
  `light-resnet18-coco` and `resnet50-coco` backbones.

The <span class="widget widget-edit">Input patch size</span> is given as
`height width depth colors`, for example `800 800 1 3`. The width and height should be
**multiples of 32**, the depth is always `1`, and the colour value is `3`. This size defines the
**patch** cropped during training and the **tile** used during prediction — images are processed
at native resolution in patches/tiles of this size, not downscaled as a whole.

!!! note

    Use a **square** input patch size if you intend to enable the 90° rotation augmentations
    (see the [Train tab](deepmib-train.md)); non-square patches are not compatible with those
    augmentations.

---

## Preprocessing (required for training)

Instance segmentation does not train directly on MIB `.model` files: preprocessing first
converts each model into a lightweight MAT-file that stores the 2-D instance label map.
Training then crops native-resolution patches from these maps on-the-fly.

**To preprocess for training:**

1. Arrange the training data under the *training* directory (named `1_Training` in the
   [directory schemes](deepmib-dirs.md#organization-of-directories)):
    - `Images/` — the training images
    - `Labels/` — the corresponding `.model` files (one per image, or a single model file)
2. Set <span class="widget widget-dropdown">Preprocess for</span> to **Training**.
3. Press <span class="widget widget-button">Preprocess</span>. Deep MIB converts the models into
   `LabelsInstances/*.mat` and then offers to **split the files into training and validation
   sets**. Choosing *Split labels* creates the `TrainImages`, `TrainLabels`, `ValidationImages`
   and `ValidationLabels` subfolders used during training.

Preprocessing writes **one `.mat` per input image** (so the file count matches the number of
input models), splitting them into the `TrainLabels`/`ValidationLabels` folders.

??? abstract "Preprocessed label file format (`LabelsInstances/*.mat`)"

    Each MAT-file is lightweight and contains only two variables:

    | Variable | Type | Description |
    |----------|------|-------------|
    | `imageFilename` | `char` | name of the source image (e.g. `00001.png`), used to locate the image in `TrainImages` / `ValidationImages` |
    | `instanceLabelMap` | `H×W uint16` | 2-D label map — each object a unique index, background `0` |

    Storing a compact 2-D label map (instead of a full `H×W×N` binary mask stack) keeps memory
    usage low for large / whole-slide images. Native-resolution training patches are cropped from
    this map on-the-fly, and the per-patch object masks and bounding boxes are rebuilt only for the
    small cropped patch.

!!! info "Prediction needs no preprocessing"

    Only *training* requires preprocessing. For **prediction**, SOLOv2 reads the raw images
    directly, so no label preprocessing is performed — place the images to segment in the
    prediction directory (`2_Prediction/Images`) and run the [Predict tab](deepmib-predict.md).

---

## Training

Training is configured and started from the [Train tab](deepmib-train.md).

- **Native-resolution patches**: the network trains on patches cropped **on-the-fly from the
  label maps at native resolution** (the network input size, e.g. `800×800`), *not* on downscaled
  whole images. This is essential for large / whole-slide microscopy images, where resizing the
  whole image to the network input would destroy resolution and hide small objects. Images
  smaller than the patch are symmetrically padded.
- **Patch sampling**: each image contributes <span class="widget widget-edit">Patches per image</span>
  patches per epoch. ~90 % are object-seeded (a random object is picked and the patch placed with a
  random offset so the object appears anywhere in the patch, never forced to the centre) and ~10 %
  are uniform-random (may be pure background).
- **Augmentation** (<label class="widget widget-checkbox">Augmentation</label>): supported for
  instance segmentation. Geometric augmentations (reflections, 90°/arbitrary rotation, scale,
  shear) are applied to the image and every object mask together, and the bounding boxes are
  recomputed from the transformed masks so that boxes, masks and labels stay in sync.
  Intensity/colour augmentations (noise, blur, brightness/contrast/hue/saturation jitter) are
  applied to the image only. Augmentation settings are shared with the 2D semantic workflow.
- **Validation**: a validation set (created during the split step) is used when available; if the
  installed MATLAB version does not support validation for SOLOv2, training automatically retries
  without validation.
- **Progress**: the SOLOv2 trainer reports the **training loss**, shown in the training progress
  window. There is no *training* accuracy metric for this workflow (the Training accuracy gauge
  reads `N/A`), but an optional **validation** accuracy can be enabled — see
  [Validation accuracy (mAP)](#validation-accuracy-map) below.

### Validation accuracy (mAP)

By default the trainer computes only the validation **loss**. To also track a validation
accuracy, enable <label class="widget widget-checkbox">Calculate accuracy for instance 2D</label>
on the [Options tab](deepmib-options.md#custom-training-plot-section). When checked, Deep MIB
attaches the mean Average Precision (mAP) metric to the SOLOv2 training: at each validation
interval the trained detector is run over the whole validation set and the resulting mAP is
displayed on the **Validation accuracy** gauge of the custom training progress window.

- Requires a validation set (*Directories and Preprocessing → Fraction of images for validation* > 0);
  with no validation images the metric cannot be computed and the gauge stays `N/A`.
- It adds a noticeable cost — full inference plus IoU matching over the validation set on every
  validation pass — so leave it **unchecked** to speed up training when only the validation loss
  is needed.

??? abstract "Training parameters for the 2D Instance workflow"

    | Parameter | Where | Notes / recommendation |
    |-----------|-------|------------------------|
    | Input patch size | Train tab | `height width 1 3`; width/height multiples of 32; use a **square** size to allow 90° rotation augmentations. Patches are cropped at this size from the images at native resolution. |
    | Encoder | Network panel | `Resnet18` (lighter, faster) or `Resnet50` (heavier, potentially more accurate). |
    | Patches per image | Train tab | number of native-resolution patches sampled from each image per epoch; increase for large images that hold many objects. |
    | Mini-batch size | Train tab | patches processed per iteration; bounded by GPU memory. Must be ≤ *Patches per image* × *number of training images*. |
    | Augmentation | Train tab | enable to apply the shared 2D augmentations (geometric to image + masks, intensity to image only). |
    | Number of epochs | Train settings | more epochs = more augmented exposure (each epoch re-crops and re-augments every image). |
    | Solver / Initial learn rate / schedule | Train settings | e.g. `sgdm`, initial learn rate `5e-4`, piecewise schedule (as in the MathWorks SOLOv2 example); `adam`/`rmsprop` also supported. |
    | Fraction of images for validation | Directories and Preprocessing tab | fraction moved to the validation set during the split; `0` disables validation. |
    | Random generator seed | Directories and Preprocessing / Train tab | fix for reproducible splits and training; `0` = new random seed each run. |

    Only *training* uses patch cropping; **Patches per image** has no effect on prediction (which
    tiles whole images — see below).

The trained network is saved to the `*.mibDeep` file specified by
<span class="widget widget-button">Network filename</span>, together with its configuration
(`*.mibCfg`).

---

## Prediction

Prediction is started from the [Predict tab](deepmib-predict.md):

1. Set <span class="widget widget-button">Network filename</span> to the trained `*.mibDeep` file.
2. Place the images to segment in the prediction directory (`2_Prediction/Images`).
3. Press <span class="widget widget-button">Predict</span>.

Large images are **tiled** at native resolution using the blocked-image overlap strategy
(controlled by <label class="widget widget-checkbox">Overlapping tiles</label> and
<span class="widget widget-edit">Overlap, %</span> in the Predict tab): each tile is segmented with
`segmentObjects` with a surrounding border of context, and objects are stitched across tiles. The
stitching rule is selected with the <span class="widget widget-dropdown">Overlap mode</span>
dropdown of the *Instance segmentation* subpanel in the Predict tab:

* **Centroid in core** — each object is emitted by the tile that owns its centroid, so there are
  no duplicates and no seam-splitting. Requires the tile overlap to be at least as large as the
  biggest object.
* **IoU merge** — all detections of every tile are kept, and detections from neighbouring tiles
  are merged into one instance when their masks agree inside the shared overlap band
  (intersection-over-union test). Objects larger than the overlap are detected piecewise and
  merged, so only the band width matters — use this mode when objects may exceed the overlap.

The detection confidence threshold, the merge IoU/IoA thresholds and the minimal object area are
configured with the subpanel's *Settings* button — see the
[Predict tab](deepmib-predict.md#instance-segmentation-subpanel) for details.

The result is written as a MIB `.model` file under
`3_Results/PredictionImages/ResultsModels`, in which **every object instance is a unique index**
(background `0`), matching the input labelling convention. Two objects that are separated in the
image never share an index: in both overlap modes each index is finally split into its separate
objects, and components below <span class="widget widget-edit">Minimal object area, pixels</span>
are discarded.

Both 2D images and z-stacks may be used as prediction images, exactly as in the *2D Semantic*
workflow:

* a **2D image** is predicted directly and saved as a 2D model;
* a **z-stack** (a multi-page TIF, an HDF5 volume, ...) is predicted **slice-by-slice** and saved
  as a single 3D model with the same number of slices.

In both cases the instance indices run `1..N` **within each slice** and are *not* consistent
between slices - an object continuing through several slices carries a different index on each of
them. Linking them into true 3D objects is done afterwards with
[Merge 2D to 3D](#merging-2d-predictions-into-a-3d-model), which ignores the input indices.

!!! warning "Overlap size vs stitching mode"

    With **Centroid in core**, the **tile overlap must be at least as large as the biggest
    object** — otherwise an object that never fits fully inside a single tile's field of view
    will be truncated. Increase <span class="widget widget-edit">Overlap, %</span> for large
    objects, or switch to **IoU merge**, which lifts this restriction (the overlap band only
    needs to be wide enough — a few tens of pixels — for neighbouring tiles to produce
    consistent masks in it). If **IoU merge** is selected while
    <label class="widget widget-checkbox">Overlapping tiles</label> is unchecked, a default 5%
    overlap is applied automatically.

---

## Merging 2D predictions into a 3D model

When the prediction images are serial sections of a volume, the predicted instance models can be
merged into **3D instance models** with the
<span class="widget widget-button">Merge 2D to 3D</span> button of the *Instance segmentation*
subpanel in the [Predict tab](deepmib-predict.md#instance-segmentation-subpanel). Objects
overlapping between neighbouring slices are linked into 3D instances with one consistent index
through the whole stack.

The layout of the results in `3_Results/PredictionImages/ResultsModels` is detected automatically
from the depth of the first `*.model` file:

* **2D models** (the prediction images were separate 2D files) - all files are the Z-slices of one
  stack and are taken in **alphabetical order of their filenames**, so make sure the prediction
  images are named in their correct Z-order. One merged 3D model is written.
* **3D models** (the prediction images were z-stacks) - every file already is a complete stack, so
  each is stitched **independently** and one merged 3D model is written per input file.

!!! note "Do not mix the two layouts"

    The results folder must contain either 2D models only or 3D models only. A mixed folder is
    ambiguous (are the 2D files slices of their own stack, or strays?) and is rejected with an
    error. Empty the folder before re-running a prediction on a different kind of input.

The stitching settings dialog is the same one used by
[Ribbon → Model → Stitch 2D instances to 3D](../user-interface/ribbon/model/instance-stitching.md),
where every option is described and illustrated. One option differs here: **Z anisotropy ratio** is
a number to type in rather than a checkbox, because raw prediction images carry no pixel size for it
to be taken from (`1` = isotropic, off).

The dialog reopens on the values used last for as long as MIB is running, and the two entry points
share them, so a threshold tried in one is offered in the other. Each accepted run also prints one
line to the MATLAB console listing exactly what was used - handy when trialling thresholds over
several runs. The values are per session and are not written to preferences.

After the settings, the destination is requested. When a **single** merged model is produced, a
file dialog asks for the directory, filename and file format. When **several** stacks are stitched
(one per 3D input model), a folder is requested instead, followed by a format dropdown; each output
is then named after its input model with a `_stitched3D` suffix.

The merged model can be written as a **single 3D file** (e.g. *Matlab format (\*.model)*, TIF
3D stack, Amira Mesh, HDF5, MRC, NRRD) or as a **sequence of 2D files** (e.g. *Matlab format 2D
sequence (\*.model)*, TIF/PNG 2D sequence) — for TIF the policy is asked during saving of a single
model, while multiple models are always written with the format's default policy to avoid one
dialog per file.

Merging takes a while. It can be stopped at any point with
<span class="widget widget-button">Cancel</span>; when several stacks are being merged, the models
finished before the stop are kept and the rest are not written.

---

*Back to [MIB](../index.md) | [DeepMIB](index.md)*
