# Implementation Plan: Stereology Tool Upgrade

> Companion to [`plan_stereology_improvements.md`](plan_stereology_improvements.md) (the evaluation).
> That doc = *what & why*; this doc = *how, in what order, and with which model*.
> Target user: EM / cell biologists. Scope decided with the user: classical manual
> probes + segmentation automation + sampling rigor + organelle presets.

## Context

`controllers.Stereology` today is a single-probe tool (rectangular line grid →
point counting → V_v). The evaluation identified missing probes (line, cycloid,
disector, counting frame), missing metrics (S_v, L_v, N_v, size), correctness bugs,
and an opportunity to compute the same quantities directly from MIB segmentations.
This plan sequences that work so each phase ships a usable increment and never
breaks the existing **editable-mask** workflow (users prune grid crosses from
irrelevant regions before analysis — the mask stays the source of truth for which
points are valid).

## Model-selection rule (token budget)

- **Opus** — phases with novel geometry, statistics, or the one-time architecture
  contract: getting these wrong is expensive and hard to detect. (cycloid math,
  disector logic, CE estimation, probe-dispatch design.)
- **Sonnet** — phases that follow an established pattern: AppDesigner wiring,
  BatchOpt config, preset tables, reuse-integration of existing plugins, Excel
  export, docs, tests. Fast and cheap once the spec is fixed.

Each phase names a **primary** model; sub-steps that can drop to the cheaper model
are called out inline.

## Cross-cutting constraints

- **`.mlapp` layout is a manual App Designer step.** The view
  `mib/+views/StereologyGUI.mlapp` is binary; Claude cannot hand-edit widget
  layout reliably. Each UI phase splits into *(a)* "add widgets in App Designer"
  (developer, guided by a widget list Claude provides) and *(b)* controller logic
  (Claude). Every BatchOpt widget must be **named exactly as its BatchOpt field**
  (root CLAUDE.md rule) so `obj.view.handles.<Field>` resolves.
- **Split `@Stereology/Stereology.m` into per-method files** as it grows (constructor
  + signatures in the class file; each probe generator / analyzer in its own
  `@Stereology/*.m`), matching the `@Alignment`, `@MibSegmentation` convention.
- **Verification per phase** uses the MATLAB MCP tools (`mcp__matlab__*`) on
  synthetic phantoms of known geometry before touching real data.

---

## Phase 1 — Correctness fixes + grid metadata  · **Sonnet**

Ship the trustworthy-numbers baseline. No new probes.

- Rename result fields: `SurfaceFraction` → `VolumeFraction_Vv`, `Surface_in_units`
  → `Area_in_units` (keep old names as deprecated aliases one release; note in docs).
- Fix the dY-axis bug: `Stereology.m:382` `diff(xy(:,1))` → `diff(xy(:,2))`.
- Persist the **original** `stepX/stepY` (in pixels and units) so the per-point area
  constant no longer depends on `mode`-of-centroid recovery after pruning. Store in
  `obj.mibModel.I{id}.image.customMeta` (existing struct) under a
  `stereologyGrid` key, and echo into the results struct. **Keep** counting valid
  points from the edited mask.
- Update `docs/` stereology page + `docs_api` docblocks; add a regression test that
  a square grid gives identical numbers and a non-square grid gives corrected dY.

Files: `Stereology.m`, `mib/+core/@MibImage/MibImage.m` (customMeta key doc only),
`docs/.../tools-stereology.*`, `tests/`.

---

## Phase 2 — Probe architecture (BatchOpt + probe dispatch)  · **Opus**

One-time design that every later phase depends on. Get the abstraction right.

- Introduce `obj.BatchOpt` and wire it via `utils.updateBatchOptFromGUI_Shared` /
  `updateGUIFromBatchOpt_Shared` (follow `@DebrisRemoval` / `@MorphOps`).
- Add a **`ProbeType` dropdown**: `Point grid`, `Line grid`, `Cycloid grid`,
  `Counting frame`, `Disector`. Selecting a probe shows/hides its parameter panel
  (Visible toggling) and sets which estimator `doStereology` runs.
- Refactor `generateGrid_Callback` and `doStereologyBtn_Callback` into a **dispatch**:
  a small `generateProbe(probeType)` and `analyzeProbe(probeType)` that call
  per-probe methods. Define the internal contract (what a probe writes to the mask,
  what metadata it stores, what the analyzer returns) so Phases 3–5 just add cases.
- Point-grid path = today's behaviour, moved behind the dispatch (regression parity).

Files: `Stereology.m` (+ new `@Stereology/generateProbe.m`, `analyzeProbe.m`),
`StereologyGUI.mlapp` (dropdown + panels — manual layout step). Sonnet can do the
mlapp-widget-to-BatchOpt wiring once Opus fixes the schema.

---

## Phase 3 — Surface density S_v: line + cycloid grids  · **Opus**

Highest-value missing metric (ER, cristae, nuclear/plasma membrane, myelin).

- **Line grid generator:** straight test lines of known total length L into the mask
  (reuse offset/centering/thickness/ROI logic already in `generateGrid`).
- **Cycloid grid generator:** sine-weighted cycloid arcs, minor axis parallel to a
  user-set **vertical axis** (new BatchOpt `VerticalAxisDeg`); tile in a systematic
  lattice. This is the crux algorithm — validate arc parametrisation and L per arc.
- **Intersection counting:** count crossings I between test-line pixels and the
  boundary of each material (boundary = `bwperim` of the label); `S_v = 2·I / L`,
  report per material and per reference volume.
- Warn if `Cycloid` chosen but no vertical section design declared.

Verify on a phantom: sphere/shell of known radius → 2I/L converges to analytic S_v
within CE. Files: new `@Stereology/generateCycloidGrid.m`,
`@Stereology/countIntersections.m`; `StereologyGUI.mlapp` (S_v panel).

---

## Phase 4 — Number density: disector + unbiased counting frame  · **Opus**

Correct organelle counting (mitochondria, synapses, vesicles, nuclei).

- **Unbiased counting frame:** rectangle with inclusion (green) + forbidden (red)
  lines; implement the forbidden-line rule so profiles are counted once.
- **Physical disector:** reference + look-up plane separated by gap `h` (MIB already
  holds the 3D stack). Count particles present in reference but not look-up (Q⁻)
  via connected-component correspondence between the two planes; `N_v = ΣQ⁻ /
  (a·h·ΣP)`.
- **Fractionator** option for total number N (robust to shrinkage).
- Store `h`, frame area `a`, section thickness as design metadata.

The 3D correspondence + edge rules are the risky part → Opus. The 2D counting-frame
overlay alone could be Sonnet. Verify against ground-truth connected components on a
small labelled crop. Files: new `@Stereology/disectorCount.m`,
`@Stereology/countingFrame.m`; `StereologyGUI.mlapp` (Nv panel).

---

## Phase 5 — Length density L_v  · **Sonnet**

Tubular structures (microtubules, capillaries, tubular ER). Reuses Phase 3 cycloid
infrastructure, so mostly application, not new math.

- Count intersections Q of profiles with a test plane / cycloid; `L_v = 2·Q / A`.
- Report mean tubule diameter from `S_v / L_v` when both available.

Files: extend `@Stereology/countIntersections.m`; `StereologyGUI.mlapp` (Lv panel).
(If built before Phase 3, promote to Opus — it would then own the cycloid math.)

---

## Phase 6 — Organelle presets  · **Sonnet**

Config layer on top of existing probes; no new algorithms.

- **`Task` dropdown**: Mitochondria (volume / number / cristae area), ER (S_v + L_v),
  Nucleus/envelope, Synapses/vesicles (N_v), Capillaries/microtubules (L_v),
  Myelin thickness, Golgi (V_v + S_v). Each selection sets `ProbeType`, default
  spacing, and the required sampling design, and shows a design-mismatch warning.
- Presets are a data table → thin logic; ideal Sonnet work.

Files: `Stereology.m` (preset map), `StereologyGUI.mlapp` (Task dropdown).

---

## Phase 7 — Automation from segmentation  · **Sonnet** (Opus for N edge-exclusion)

MIB's differentiator; heavy reuse of existing code.

- **Direct measurement mode** computing from labels, reported alongside the probe
  estimate so segmentation bias is visible:
  - V_v — voxel ratio (trivial).
  - S_v — reuse `plugins.OrganelleAnalysis.SurfaceMeasurements` (already does
    model→mesh surface area via signed-tetrahedra/cross-product) and
    `utils.isosurfaceMibRendering`.
  - Size / count — reuse `mib/external/regionprops3mib.m` and the measurement
    patterns in `@Quantification/quantification_Callback.m`.
  - L_v — skeleton length via `mib/external/FastMarching/skeleton.m` +
    `utils.removeBranches`.
  - N — connected components **with disector-style face exclusion** so partial
    objects on volume faces are not mis-counted → the one Opus sub-step here.
- **Probe-on-segmentation (QC):** run any Phase 3–5 probe programmatically over the
  segmented volume to auto-produce counts + CE at scale.

Files: new `@Stereology/measureFromLabels.m` (mostly glue to existing helpers);
reuse list above.

---

## Phase 8 — Sampling rigor: CE + reference space + design metadata  · **Opus**

Publishable-grade precision reporting; statistical correctness matters.

- **Coefficient of Error** per estimate (Gundersen–Jensen m=0/1 for systematic
  random sampling; noise + variance decomposition).
- **Reference-space** phase so results are reported relative to a defined reference
  (avoid the reference trap): e.g. S_v per µm³ cytoplasm.
- Record + export sampling design (IUR / vertical / isotropic-vEM), section
  thickness, disector `h`. Extend the Excel/MATLAB export to include CE and design.

Files: new `@Stereology/estimateCE.m`; extend the export block in `analyzeProbe`.

---

## Phase 9 — Size/shape + 3D spatial probes (stretch)  · **Opus**

- Star volume (point-sampled intercepts), nucleator/rotator for mean particle volume.
- Fakir / virtual-cycloid (six-arc spider) probes for direct S_v & L_v on isotropic
  vEM without physical vertical sections.
- Optional second-order: nearest-neighbour / pair-correlation of counted particles.

Advanced and independent; schedule after core metrics land.

---

## Suggested grouping for delivery

| Milestone | Phases | Value |
|-----------|--------|-------|
| M1 Trustworthy baseline | 1, 2 | correct V_v + extensible architecture |
| M2 Core EM metrics | 3, 4, 5 | S_v, N_v, L_v — the missing 90% |
| M3 Usability + scale | 6, 7 | presets + segmentation automation |
| M4 Rigor + advanced | 8, 9 | CE/reference space, star volume, 3D probes |

## Verification (all phases)

- Drive MATLAB headless with `mcp__matlab__run_matlab_file` / `evaluate_matlab_code`
  on phantoms: sphere shell (S_v), known-count blob field (N_v), straight rods (L_v).
- Regression: Phase 1/2 must reproduce current point-count numbers exactly on an
  unedited square grid.
- `buildtool check` + `buildtool test` (needs `addpath('tests')`); add per-probe
  unit tests under `tests/`.
- After code changes, refresh the knowledge graph: `python development/graphify/run_all.py`.

## Key files

- Controller: `mib/+controllers/@Stereology/Stereology.m` (→ split into method files)
- View: `mib/+views/StereologyGUI.mlapp` (manual App Designer layout per UI phase)
- Reuse: `mib/plugins/OrganelleAnalysis/SurfaceMeasurements/SurfaceMeasurements.m`,
  `mib/external/regionprops3mib.m`, `mib/+utils/isosurfaceMibRendering.m`,
  `mib/external/FastMarching/skeleton.m`, `mib/+utils/removeBranches.m`,
  `mib/+controllers/@Quantification/quantification_Callback.m`
- Metadata: `mib/+core/@MibImage/MibImage.m` `customMeta` struct
- Infra: `core.PoolWaitbar`, `utils.dlgs.*`, `xlswrite2`
