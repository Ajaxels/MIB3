# Morphological 2D/3D Operations

---

## Overview

![Morphological Ops](images/menuSelectionMorphOps.png){.on-glb align=left width="300"}

Applies morphological operations to the **Selection** layer using MATLAB's
[bwmorph](https://se.mathworks.com/help/images/ref/bwmorph.html),
[bwmorph3](https://se.mathworks.com/help/images/ref/bwmorph3.html),
[bwskel](https://se.mathworks.com/help/images/ref/bwskel.html), and
[bwulterode](https://se.mathworks.com/help/images/ref/bwulterode.html) functions.

The available operations depend on the <span class="widget widget-checkbox">3D objects</span>
checkbox — switching it repopulates the <span class="widget widget-dropdown">Morphological operation</span>
dropdown with the operations relevant to the chosen dimensionality.

[:fontawesome-brands-youtube:{.red-color} Demonstration](https://youtu.be/L-w8eGDfUkU)  
[:fontawesome-brands-youtube:{.red-color} Skeleton for 3D objects](https://youtu.be/Au4vb7max9Q)

<div class="clear-float"></div>

---

## Controls

- <span class="widget widget-dropdown">Morphological operation</span>: the operation to apply
  (see [2D operations](#2d-operations) and [3D operations](#3d-operations) below).

- <label class="widget widget-checkbox">3D objects</label>: when checked, uses 3D operations
  (`bwmorph3` / `bwskel`); when unchecked, uses 2D operations (`bwmorph`).
  Switching repopulates <span class="widget widget-dropdown">Morphological operation</span>.

- <span class="widget widget-radio">Apply to</span> *(2D mode only)*:
    - **Current slice** — applies the operation to the currently displayed slice.
    - **Stack** — applies to every slice in the Z-stack.

- **Iterations**:
    - <span class="widget widget-radio">Limit to</span> *N* / <span class="widget widget-radio">Infinite</span>:
      choose a fixed iteration count or run until convergence.
      For **Skeleton**, only *Limit to* is available and the value is used as *Min branch length*.
      For 3D operations other than **Skeleton**, iterations are not applicable and these controls are disabled.
    - <span class="widget widget-edit">Iterations number</span> /
      <span class="widget widget-edit">Min branch length</span>: the spinner value
      (label changes based on the selected operation).

- <label class="widget widget-checkbox">Remove branches</label>: removes small branches after
  thinning or skeletonisation. Available for **Skeleton** (2D) and **Thin** with *Infinite* iterations (2D).

- **Ultimate erosion panel** *(visible only when **bwulterode** is selected in 2D mode)*:
    - <span class="widget widget-radio">2D</span> / <span class="widget widget-radio">3D</span>:
      selects the connectivity dimension for the erosion.
    - <span class="widget widget-dropdown">Connectivity</span>: `4` or `8` in 2D mode; `6`, `18`, or `26` in 3D mode.
    - <span class="widget widget-dropdown">Method</span>: distance metric —
      `euclidean`, `cityblock`, `chessboard`, or `quasi-euclidean`.

- <label class="widget widget-checkbox">Auto preview</label> *(2D mode only)*: updates the
  preview automatically on every widget change.
- <span class="widget widget-button">Preview</span> *(2D mode only)*: overlays the result on
  the current view without committing changes.
- <span class="widget widget-button">Apply</span>: applies the operation to the Selection layer.
- <span class="widget widget-button">Close</span>: closes the dialog without making changes.

---

## 2D operations

Available when <label class="widget widget-checkbox">3D objects</label> is **unchecked**.

### Branch points

`branchpoints` — finds branch points (junctions) of a skeleton:

- Pixels where multiple skeleton branches meet are set to 1; all others to 0.
- The image must be skeletonised first.
- Reference: [bwmorph](https://se.mathworks.com/help/images/ref/bwmorph.html)

---

### Diagonal fill

`diag` — eliminates 8-connectivity of the background using diagonal fill:

- Fills diagonal gaps so that background regions lose 8-connectivity:
  `1 0 → 1 1` / `0 1 → 1 1`
- Reference: [bwmorph](https://se.mathworks.com/help/images/ref/bwmorph.html)

---

### Endpoints

`endpoints` — finds end points of a skeleton:

- Pixels with only one 8-connected neighbour are set to 1.
- Reference: [bwmorph](https://se.mathworks.com/help/images/ref/bwmorph.html)

---

### Skeleton

`skel` — reduces objects to 1-pixel-wide skeletons using `bwskel`:

- Removes boundary pixels without breaking connectivity; preserves the Euler number.
- The **Limit to** value is used as *Min branch length* (branches shorter than this are pruned).
- <label class="widget widget-checkbox">Remove branches</label> applies additional branch removal after skeletonisation.
- Reference: [bwskel](https://se.mathworks.com/help/images/ref/bwskel.html)  
  [:fontawesome-brands-youtube:{.red-color} Demo](https://youtu.be/Au4vb7max9Q)

---

### Spur

`spur` — removes spur pixels (pixels with exactly one 8-connected neighbour):

- Cleans up isolated line endpoints produced by skeletonisation or thinning.
- Reference: [bwmorph](https://se.mathworks.com/help/images/ref/bwmorph.html)

---

### Thin

`thin` — thins objects to lines:

- Objects without holes shrink to minimally connected strokes; objects with holes shrink to rings.
- Preserves the Euler number.
- With *Infinite* iterations and <label class="widget widget-checkbox">Remove branches</label>
  checked, small branches are removed from the result.
- Reference: [bwmorph](https://se.mathworks.com/help/images/ref/bwmorph.html)  
  [:fontawesome-brands-youtube:{.red-color} Demo](https://youtu.be/rqZbH3Jpru8)

---

### Ultimate erosion

`bwulterode` — reduces objects to their ultimate eroded points (local maxima of the distance transform):

- Each connected object is reduced to one or more isolated representative pixels.
- Configure the erosion via the **Ultimate erosion panel**:
    - **Mode** (2D / 3D) and **Connectivity** control how neighbourhoods are defined.
    - **Method** selects the distance metric (`euclidean`, `cityblock`, `chessboard`, `quasi-euclidean`).
- Reference: [bwulterode](https://se.mathworks.com/help/images/ref/bwulterode.html)

---

## 3D operations

Available when <label class="widget widget-checkbox">3D objects</label> is **checked**.
All operations process the full 3D stack; **Apply to** is fixed to *Stack*.
Iterations are not applicable except for **Skeleton**.

### Branch points

`branchpoints` — finds branch points of a 3D skeleton:

- Voxels at skeleton junctions are set to 1; all others to 0.
- The volume must be skeletonised first.
- Reference: [bwmorph3](https://se.mathworks.com/help/images/ref/bwmorph3.html)

---

### Clean

`clean` — removes isolated voxels:

- An isolated voxel is a single voxel set to 1 completely surrounded by voxels set to 0.
- Reference: [bwmorph3](https://se.mathworks.com/help/images/ref/bwmorph3.html)

---

### Endpoints

`endpoints` — finds end points of a 3D skeleton:

- Voxels with only one 26-connected neighbour are set to 1.
- Reference: [bwmorph3](https://se.mathworks.com/help/images/ref/bwmorph3.html)

---

### Fill

`fill` — fills isolated interior voxels:

- Isolated interior voxels (set to 0 and surrounded 6-connected by voxels set to 1) are set to 1.
- Reference: [bwmorph3](https://se.mathworks.com/help/images/ref/bwmorph3.html)

---

### Majority

`majority` — keeps a voxel set to 1 only if the majority of its neighbourhood is 1:

- A voxel stays 1 if ≥ 14 of the 26 voxels in its 3×3×3 neighbourhood are 1; otherwise set to 0.
- Reference: [bwmorph3](https://se.mathworks.com/help/images/ref/bwmorph3.html)

---

### Remove

`remove` — removes interior voxels:

- Interior voxels (set to 1 and surrounded 6-connected by voxels set to 1) are set to 0,
  leaving only the object surface.
- Reference: [bwmorph3](https://se.mathworks.com/help/images/ref/bwmorph3.html)

---

### Skeleton

`skel` — reduces 3D objects to 1-voxel-wide skeletons using `bwskel`:

- The **Limit to** value is used as *Min branch length*; branches shorter than this are pruned.
- Reference: [bwskel](https://se.mathworks.com/help/images/ref/bwskel.html)  
  [:fontawesome-brands-youtube:{.red-color} Demo](https://youtu.be/Au4vb7max9Q)

---

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Ribbon](../index.md) | [Selection](index.md)*
