# Contrast-limited Adaptive Histogram Equalization (CLAHE)

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Ribbon](../index.md) | [Image](index.md)*

---

![CLAHE dialog](images/menuImage-contrast-clahe.png){.on-glb align=left width="320"}

CLAHE enhances contrast locally in small rectangular tiles rather than globally. 
Each tile's histogram is redistributed to match the chosen *Distribution*, then neighboring tiles are 
blended with bilinear interpolation to avoid sharp boundaries. 
A clip limit caps contrast amplification in uniform areas to suppress noise. 

See MATLAB's [adapthisteq](https://se.mathworks.com/help/images/ref/adapthisteq.html) for details.

<div class="clear-float"></div>

<span class="widget widget-dropdown">Dataset type</span>: scope of the operation — `Shown slice (2D)`, `Current stack (3D)`, or `Complete volume (4D)`.

<span class="widget widget-dropdown">Color channel</span>: `All`, `Displayed`, or a specific channel.

<span class="widget widget-edit">Number of tiles Y</span> / <span class="widget widget-edit">Number of tiles X</span>: tile grid size (1–256 in each direction); more tiles = finer local adaptation.

<span class="widget widget-edit">Clip limit</span>: contrast enhancement limit (0–1); higher values give stronger contrast but more noise amplification.

<span class="widget widget-edit">Number of bins</span>: histogram bins used for the contrast transform (2–65536); more bins = greater dynamic range.

<span class="widget widget-dropdown">Distribution</span>: target histogram shape — `uniform`, `rayleigh`, or `exponential`.

<span class="widget widget-edit">Alpha</span>: distribution shape parameter for `rayleigh` and `exponential` (disabled for `uniform`).

Use <span class="widget widget-button">Preview</span> to check the result on the current slice before applying to the full dataset.

---

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Ribbon](../index.md) | [Image](index.md)*
