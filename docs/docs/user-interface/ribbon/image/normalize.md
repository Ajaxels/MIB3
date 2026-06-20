# Normalize Layers

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Ribbon](../index.md) | [Image](index.md)*

---

![Normalize layers dialog](images/menuImage-contrast-norm.png){.on-glb align=left width="320"}

Normalizes image intensities slice-by-slice across Z or time to reduce illumination variation.

<div class="h4-like">Demonstration</div>

- [:fontawesome-brands-youtube:{.red-color} Image normalization tutorial](https://youtu.be/MmBmdGtuUdM)


<div class="clear-float"></div>

<span class="widget widget-dropdown">Target</span>: what to normalize:

- **Z stack**: normalize each Z-slice to a common mean and standard deviation.
- **Time series**: normalize each time frame; controlled by <span class="widget widget-dropdown">Time series normalization</span> — either *Based on current 2D slice* or *Based on complete 3D stack*.
- **Masked area**: compute normalization coefficients only from the masked region (see <span class="widget widget-dropdown">Mask layer</span>).
- **Background**: shift each slice so that the mean intensity of the masked background area matches the dataset mean.

<span class="widget widget-dropdown">Mode</span>:

- **Automatic**: coefficients (mean and std) are computed from the data.
- **Manual**: use the fixed target <span class="widget widget-edit">Mean</span> and <span class="widget widget-edit">Std</span> values.
- **BasedOnSlice**: use the slice specified by <span class="widget widget-edit">Reference slice No</span> as the normalization reference.

<span class="widget widget-dropdown">Color channel</span>: channels to normalize (`All channels`, `Shown channels`, or a specific channel).

<span class="widget widget-dropdown">Exclude</span>: pixels to exclude from mean/std calculations — `Whole range`, `Exclude blacks`, or `Exclude whites`.

<span class="widget widget-dropdown">Mask layer</span> *(Masked area / Background only)*: `selection` or `mask` layer used to define the region.

??? info "Normalization algorithm"

    1. Calculate mean intensity and standard deviation (std) for the whole dataset.
    2. Calculate mean and std for each slice.
    3. Shift each slice by the difference between its mean and the dataset mean; stretch by the ratio of dataset std to slice std.

    For 4D datasets, normalization can be done across time.<br>
    For Z-stacks, black or white pixels can be excluded from the statistics.

---

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Ribbon](../index.md) | [Image](index.md)*
