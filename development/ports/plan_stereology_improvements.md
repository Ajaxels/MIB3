# Evaluation: MIB3 Stereology Tool — Gaps & Improvement Suggestions

> **Status: evaluation only.** No code is to be written in this phase. This document
> assesses the current tool against design-based stereology practice and proposes
> a prioritized set of missing grid/probe types, metrics, and workflow features.
> Primary audience: EM / cell biologists quantifying organelles on TEM/SEM/vEM.

## Context

`mib/+controllers/@Stereology/Stereology.m` is the only file in the controller.
It generates a **rectangular line grid** into the Mask layer, then at each grid
**intersection point** it reads the model material and tallies occurrences. From
that single probe it computes an areal/volume fraction and a per-point area. This
is the most basic stereological estimator (point counting for V_v). EM users who
quantify organelles routinely need **surface area, number, length, and size**
estimators as well — and those require different probes (lines, cycloids,
disectors, counting frames). The goal here is to map what is missing and how each
gap maps onto specific organelle questions, so a later implementation phase can be
scoped.

---

## 1. What the current tool actually does (assessment)

**Grid:** one type only — an axis-aligned rectangular grid of horizontal + vertical
lines (`generateGrid_Callback`, lines 168–273). Options: step X/Y, offset X/Y,
centered vs offset, line thickness, units (pixels or image units), ROI clipping.

**Probe/metric:** point counting at grid line **intersections**
(`doStereologyBtn_Callback`, lines 275–560). It thins the grid, finds branchpoints
= intersection test points, then for each point reads the model label and
increments `Occurrence(t, slice, material)`. Outputs:
- `Occurrence` — point counts per material per slice.
- `SurfaceFraction` = Occurrence / Σ Occurrence (per slice).
- `Surface_in_units` = Occurrence × dX × dY.
- Edge correction via `scaleToImage` (fractional cell overlap at image border).
- Optional annotation-label counts. Export to MATLAB struct or per-timepoint Excel.

**Strengths worth keeping:** systematic grid with offset/centering, boundary
edge-correction, ROI clipping, per-slice/per-timepoint tabulation, dual export.
These are a solid foundation for point counting.

**Correctness / terminology problems (fix regardless of new features):**
- **Misnamed outputs.** By the Delesse–Rosiwal principle, point counting yields a
  **volume fraction V_v** (equivalently areal fraction A_a), *not* a surface. The
  fields `SurfaceFraction` and `Surface_in_units` are volume/area fraction and
  per-slice **area**, not surface (interface) area. This is actively misleading to
  EM users — "surface" in stereology means membrane area (S_v), which this tool
  does **not** measure. Rename to `AreaFraction`/`VolumeFraction_Vv` and
  `Area_in_units` (with migration note in docs).
- **dY uses the wrong axis.** Lines 382–383 compute `dYp` from
  `diff(xy(:,1))` — the X-coordinate — instead of `xy(:,2)`. dY is silently set
  equal to dX. Harmless for a square grid but wrong for non-square steps and for
  any area/length derived from dY. Should be `diff(xy(:,2))`.
- **Grid points are read back from the (user-editable) mask — this is by design.**
  Deriving the valid intersection points from the mask at analysis time is an
  intentional, load-bearing feature, **not** a defect: in microscopy not all of the
  imaged field is analysable, so the user generates the grid, then prunes crosses
  from irrelevant regions with MIB's segmentation tools, and only the surviving
  points are counted. The mask must remain the source of truth for *which* points
  are valid — do **not** replace this with grid geometry carried in metadata.
  The narrower concern is only the **spacing** dX/dY used for per-point area: it is
  recovered as the `mode` of centroid spacings, which is fine while the majority of
  points survive but can drift after heavy pruning (gaps become 2×step, etc.).
  Mitigation without breaking the workflow: store the *original* `stepX/stepY` as
  mask metadata and use it for the area-per-point constant, while still counting
  valid points from the edited mask. (Also fixes the dY-axis bug above independently.)
- **Point count uses a single grid whose spacing = line spacing.** In classic
  designs the *point grid* for reference-space volume is deliberately **coarser**
  than the line grid used for surface/length, so the two counts are statistically
  independent and efficient. Currently only one spacing exists.

---

## 2. Missing metric families (the core gap)

Point counting answers only "what fraction of volume is organelle X." EM organelle
studies routinely need four more first-order quantities. Each needs a probe the
tool does not have:

| Quantity | Symbol | Probe needed | Estimator | Typical organelle question |
|---|---|---|---|---|
| Volume fraction | V_v | point grid (have) | P_material / P_total | mito volume / cell volume |
| **Surface density** | **S_v** | **line / cycloid grid** | S_v = 2·I / L | ER, cristae, plasma & nuclear membrane area |
| **Length density** | **L_v** | **plane / cycloid probe** | L_v = 2·Q / A | microtubules, capillaries, tubular ER length |
| **Number density / total number** | **N_v, N** | **disector + counting frame** | N_v = ΣQ⁻ / (a·h·ΣP); fractionator for N | mitochondria/synapse/vesicle/nucleus counts |
| **Mean particle volume & size dist.** | v̄, v_N | point-sampled intercepts / nucleator / rotator | star volume, PSI | organelle size, cell size, size distribution |

Notes for the EM audience:
- **S_v (surface).** Superimpose test **lines** and count **intersections (I)**
  between the line and the segmented membrane boundary; S_v = 2I/L_test. For
  arbitrarily/anisotropically oriented membranes (ER, cristae, myelin) this is only
  unbiased with **isotropic** test lines → **cycloid** arcs on **vertical
  sections**, or an IUR design. This is the single most-requested missing metric
  for membrane biology.
- **L_v (length).** For linear/tubular structures, count intersections **Q** of
  profiles with a test **plane** (or use cycloids for L_v in thick sections);
  L_v = 2·Q/A.
- **N_v / N (number).** The **physical disector** (two adjacent slices — MIB
  already handles 3D stacks, so both reference and look-up planes are available) or
  **optical disector**, combined with an **unbiased counting frame** (Gundersen's
  inclusion/exclusion lines) to count particles once and without edge bias.
  **Fractionator** sampling gives total number N directly and is robust to shrinkage.
  This is the correct way to count mitochondria, synapses, vesicles, nuclei —
  profile counting on single sections is biased by particle size/shape.
- **Size / shape.** **Star volume** (point-sampled intercepts) and the
  **nucleator/rotator** estimate mean particle volume from random rays through a
  reference point — directly usable once objects are segmented.

---

## 3. Missing grid / probe types

Currently: one rectangular line grid. Add a probe selector with:

1. **Point grid (coincident/independent).** Explicit sparse point grid (crosses or
   `+` ticks) for V_v, decoupled from the line spacing. Support **double lattice**
   (coarse points for abundant reference space + fine points/lines for the rare
   phase) — the standard efficiency trick.
2. **Line grid for S_v.** Horizontal/vertical or arbitrary-angle straight test
   lines with defined total length L, counting boundary intersections. Include the
   classic combined **point + line** test system (points on the lines) so V_v and
   S_v come from one overlay.
3. **Cycloid grid (vertical-section design).** Sine-weighted cycloid arcs with
   minor axis parallel to the marked **vertical** direction — the unbiased probe
   for S_v and L_v on anisotropic structures. Needs a per-image "vertical axis"
   input. This is the key addition for EM membrane work.
4. **Unbiased counting frame.** Rectangular frame with green inclusion + red
   forbidden lines, for counting profiles/particles per frame (2D N_A and, with the
   disector, N_v).
5. **Disector pair overlay.** Reference + look-up frame across a chosen slice gap h,
   highlighting particles present in one but not the other (Q⁻).
6. **3D spatial probes (for MIB's vEM strength).** Fakir test lines (isotropic 3D
   lines) or the six-arc **virtual cycloid / spider probe** for direct S_v and L_v
   on isotropic volume data without needing physical vertical sections.
7. **Curved / radial grids** and **random offset per slice** (systematic-random
   jitter) as options on any of the above.

---

## 4. Organelle-specific presets (task-driven UI)

Because "different organelles require different approaches," add a **task preset**
dropdown that pre-selects probe + estimator + defaults:

- **Mitochondria — volume:** point grid → V_v. **— number:** disector + counting
  frame → N_v / total N. **— cristae membrane area:** cycloid grid → S_v.
- **Endoplasmic reticulum:** cycloid grid → S_v (membrane area) and L_v (tubular
  ER length); V_v for rough vs smooth fraction.
- **Nucleus / nuclear envelope:** point grid V_v; cycloid S_v for envelope area;
  nucleator for mean nuclear volume.
- **Synapses / vesicles:** disector + counting frame → N_v; V_v for bouton volume.
- **Capillaries / microtubules / filaments:** plane or cycloid probe → L_v; mean
  diameter from S_v/L_v.
- **Myelin / membranes — thickness:** orthogonal-intercept distribution.
- **Golgi:** V_v (point) + S_v (cycloid) — matches published volume-SEM + stereology
  higher-throughput workflow.

Each preset should also set the **recommended sampling design** (IUR, vertical, or
isotropic-vEM) and warn if the loaded data does not meet its orientation
assumption (e.g. cycloid S_v selected but no vertical axis defined).

---

## 5. Sampling & precision rigor (design-based correctness)

The tool currently reports raw per-slice counts with no precision estimate and no
enforcement of an unbiased sampling design. For a "gold-standard, publishable"
EM audience, add:

- **Coefficient of Error (CE).** Report CE of each estimate (Gundersen–Jensen
  m=0/1 for systematic random sampling; split-sample / noise+variance
  decomposition). Users need CE to justify how many points/sections suffice
  ("do more animals, not more points").
- **Reference-space handling.** Explicit "reference volume" phase so estimates are
  reported *relative to a defined reference* (the reference trap) — e.g. mito
  surface per µm³ of cytoplasm, not per image.
- **Sampling-design metadata.** Record whether sections are IUR / vertical /
  isotropic-vEM, section thickness, and disector height h; export them with results.
- **Systematic-random point offset** already partly present (offset fields) — expose
  a proper random start per timepoint/section and document it.
- **Terminology / units fixes** from §1 (V_v naming, dY-axis bug) — these are
  prerequisites for trustworthy numbers.
- **Second-order option (advanced):** nearest-neighbour / pair-correlation for
  spatial distribution of counted particles.

---

## 6. Automation via segmentation (MIB's differentiator)

MIB already has deep-learning segmentation and full 3D/vEM label volumes. Two
complementary modes should coexist:

- **Probe-on-segmentation (validation/QC):** run any probe above automatically over
  a segmented volume — count intersections/points programmatically instead of by
  eye. Lets users cross-check direct measurement vs unbiased estimate and get CE
  essentially for free on large volumes.
- **Direct measurement from labels (when segmentation is trusted):** compute V_v
  (voxel ratio), S_v (marching-cubes / boundary-voxel surface area per reference
  volume), L_v (skeleton length of tubular labels), N (connected components with
  disector-style edge exclusion so partial objects at volume faces are not
  over/under-counted), and per-object size distributions. Report these **alongside**
  the stereological estimate so bias from imperfect segmentation is visible.
- Reuse existing MIB machinery: connected-components / `regionprops3`, skeletonize,
  ROI masks, the label/material model, and the current Excel/MATLAB export scaffold.

This positions the tool between classic manual stereology and modern vEM: unbiased
estimators for rigor, automated measurement for throughput, both from one panel.

---

## 7. Suggested prioritization (for a later implementation phase)

1. **Fix correctness first (small):** rename V_v outputs, fix dY-axis bug, store the
   original stepX/stepY as mask metadata for the area-per-point constant (keep
   counting valid points from the editable mask), add CE reporting. Prerequisite for
   everything else.
2. **Surface density S_v via line + cycloid grid** — highest-value missing metric
   for EM membranes (ER, cristae, envelope, myelin).
3. **Number density via disector + unbiased counting frame** — correct organelle
   counting (mito, synapses, vesicles); leverages MIB's existing 3D stacks.
4. **Length density L_v** (plane/cycloid) for tubular structures.
5. **Organelle presets** wiring the above into one-click task defaults.
6. **Automation-from-segmentation** measurement mode + direct S_v/L_v/N/size.
7. **Size/shape estimators** (star volume, nucleator/rotator) and 3D spatial probes
   (fakir / virtual cycloid) for isotropic vEM.

---

## 8. Key references (grounding)

- stereology.info — Probe Index, Cycloid, Surface region, Cycloids for S_v / L_v
  (https://stereology.info/probe-index/ , https://stereology.info/cycloid/ ,
  https://stereology.info/surface/ , https://stereology.info/cycloids-sv/).
- Ochs & Mühlfeld, "Stereology as the 3D tool to quantitate lung architecture,"
  *Histochem Cell Biol* (2020) — probe/estimator overview
  (https://link.springer.com/article/10.1007/s00418-020-01927-0).
- Design-based surface estimation with virtual cycloids in arbitrary-orientation
  thick sections (ResearchGate 8346214).
- Ferguson et al., "Quantifying Golgi structure using EM: combining volume-SEM and
  stereology," *J Microsc* (2017) (https://pubmed.ncbi.nlm.nih.gov/28429122/).
- Disector method for number/total N in brain (ResearchGate 323556299);
  semi-automatic nucleator, Hansen 2011, *J Microsc*
  (https://onlinelibrary.wiley.com/doi/10.1111/j.1365-2818.2010.03460.x).
- "Call to action to properly utilize EM to measure organelles" (mitochondria/ER
  quantification) (https://www.sciencedirect.com/science/article/pii/S0171933523000808).
- MBF StereoInvestigator probe docs — Cycloids for S_v / L_v (reference UX).

## 9. How to validate the recommendations (next phase, not now)

- Prototype S_v on a synthetic phantom of known surface (e.g. a sphere shell of
  known radius) and confirm 2I/L converges to analytic S_v within CE.
- Cross-check disector N against ground-truth connected components on a small
  labeled vEM crop.
- Confirm the V_v rename + dY fix reproduce identical numbers on a square grid and
  corrected numbers on a non-square grid.
- Use the MATLAB MCP tools to run these phantoms headless before touching the UI.
