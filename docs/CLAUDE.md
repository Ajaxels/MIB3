# Zensical User Documentation Guide

User-facing documentation for MIB3. Built with **Zensical** (MkDocs-based).

---

## Directory layout

```
docs/
  zensical.toml        — site config: nav tree, theme, plugins, extensions
  docs/                — Markdown source files (mirrors the nav structure)
    css/
      styles.css       — custom CSS (admonitions, widgets, <mouse> tag, tables)
      extra.js         — custom JS (data-help tooltip balloons)
    assets/            — images and SVG icons
    index.md           — home page
    ...                — content pages, grouped by nav section
  site/                — built output (do NOT edit; regenerate with zensical build)
```

---

## Build commands (run from `docs/`)

```bash
zensical serve        # live-reload preview at localhost:8000
zensical serve -o     # same, opens browser automatically
zensical build        # generate static site into docs/site/
```

---

## Documentation conversion workflow

When porting documentation from MIB2 (`temp/docs_mib2_md/`) or updating existing pages to match MIB3:

1. **Source of truth for widget names** — launch the actualz MIB3 dialog in MATLAB and dump widget handles:
   ```matlab
   h = controllers.XxxClass(mib.mibModel, mib);   % open dialog
   t = findall(h.view.gui);
   for i = 1:numel(t); try; fprintf('%s | %s\n', t(i).Tag, t(i).Text); catch; end; end
   ```
   Use the exact `.Text` values (including capitalisation) for all `<span class="widget ...">` labels.

2. **Always edit `docs/docs/`** — never `temp/`. The `temp/` tree is scratch space only.

3. **Cross-check with the ribbon source** — for ribbon tab pages, read
   `mib/+views/@MibView/addRibbon<Tab>.m` to get the definitive section names,
   button labels, and dropdown item order before updating the docs.

---

## Ribbon tab page structure

All ribbon tab index pages (`user-interface/ribbon/<tab>/index.md`) follow this hierarchy:

| Level | Markdown | Maps to |
|-------|----------|---------|
| Page title | `#` | Tab name, e.g. `# Home Ribbon Tab` |
| Ribbon section | `##` | `addSection("…")` call in the ribbon source, e.g. `## Import Image Section` |
| Ribbon button / item | `###` | Individual button or dropdown, e.g. `### Make Snapshot` |
| Dropdown sub-item | `####` | Sub-menu item inside a dropdown, e.g. `#### Flip...` |

Rules:
- Section `##` headings use the exact name from the ribbon source + " Section" suffix (e.g. `## Dataset Tools Section`).
- Button `###` headings use the exact label string from the ribbon source (PascalCase as displayed in the UI).
- Dropdown items under a `###` button are listed as a bullet list **or** promoted to `####` when they have enough content to warrant a heading.
- Sub-pages linked with `[See details](sub-page.md)` keep their own page structure independently of the index hierarchy.

### Widget label spans

Use the exact `.Text` value from the widget dump inside the span — including colons, lowercase letters, and special characters exactly as they appear in the dialog:

```markdown
<span class="widget widget-button">Rename and Shuffle</span>
<span class="widget widget-dropdown">Mask method</span>
<span class="widget widget-checkbox">enable undo</span>
<span class="widget widget-edit">Number of CPUs</span>
```

### Preference page sections

Category names in the overview list must match the actual tree-node `.Text` values (lowercase second word):
- `User interface`, `Colors and styles`, `Backup and undo`, `External directories`, `Keyboard shortcuts`, `Segmentation tools`

Sub-sections within each category use `###` headings; individual widgets use inline `<span>` elements.

---

## Keeping cross-links valid after page edits

Zensical generates anchor IDs from heading text by lowercasing and replacing spaces with hyphens.
Renaming a `##` or `###` heading therefore **changes its anchor**, breaking any links pointing to it from other pages.

**After renaming a section heading:**

1. Find all `#old-anchor` references across the docs tree:
   ```powershell
   cd "C:\MATLAB\MIB_CONVERSION\MIB3\docs"
   & "C:\Python\Miniforge\envs\mkdocs\Scripts\zensical.exe" build 2>&1 |
     ForEach-Object { $_ -replace '\x1b\[[0-9;]*[mGKHFa-zA-Z]','' } |
     Select-String "anchor|Warning" | ForEach-Object { $_.Line.Trim() } |
     Where-Object { $_ -ne '' }
   ```
2. Update every broken `#old-anchor` to `#new-anchor` in the files reported.
3. Re-run the build until no anchor warnings remain.

**Common anchor-breaking operations and what to update:**

| Operation | Anchor that breaks | Search pattern |
|-----------|-------------------|----------------|
| Rename `### Parameters` → `### Voxels` | `#parameters` | `#parameters)` |
| Rename `## Slice` → `### Slices` | `#slice` | `#slice)` |
| Rename any section | `#old-name` | `#old-name)` |

Anchor rules: all lowercase, spaces → `-`, special characters stripped.
Example: `### My Section` → `#my-section`.

---

## When to update docs alongside code changes

| Change | File(s) to update |
|--------|-------------------|
| New ribbon button / menu item | `docs/user-interface/ribbon/<tab>/` |
| New panel or panel feature | `docs/user-interface/panels/<panel>/` |
| New plugin | `docs/user-interface/plugins/<category>/` + nav in `zensical.toml` |
| New keyboard / mouse shortcut | `docs/user-interface/key-and-mouse-shortcuts.md` |
| New preference | `docs/user-interface/ribbon/home/home-preferences.md` |
| New release | `docs/getting-started/releasenotes/index.md` (current) + `release-notes-history.md` (older) |
| New segmentation tool | `docs/user-interface/panels/segm/` |

---

## Adding a new page

1. Create the `.md` file at the appropriate path under `docs/docs/`.
2. Register it in the `nav` array in `docs/zensical.toml`:

```toml
# Leaf page
{ "Page Title" = "path/relative/to/docs/page.md" }

# Section with sub-pages
{ "Section Title" = [
  "section/index.md",
  { "Sub-page" = "section/sub.md" },
]}
```

**File naming:** always lowercase with hyphens (e.g. `my-feature.md`).  
Zensical does a **case-sensitive** filename lookup even on Windows — the nav entry must match the exact filename case or the link will fall back to a raw `.md` path.

---

## Custom inline elements

These custom tags and classes are defined in `css/styles.css` and work anywhere in Markdown via the `md_in_html` extension:

| Syntax | Renders as |
|--------|-----------|
| `<mouse class="left"></mouse>` | left-click icon (SVG) + "LMB" label |
| `<mouse class="right"></mouse>` | right-click icon (SVG) + "RMB" label |
| `<span class="widget widget-button">Label</span>` | keyboard / UI button widget |
| `<span class="widget widget-dropdown">Item</span>` | dropdown widget |
| `<span class="widget widget-checkbox">Label</span>` | checked checkbox widget |
| `<span class="widget widget-radio">Label</span>` | radio button widget |
| `:octicons-gear-16:{.orange-color}` | orange-tinted icon (any icon name) |
| `<div class="clear-float"></div>` | clears float after an `align=left` image |
| `<div data-help="tip text">…</div>` | tooltip balloon on hover |

---

## Admonition types

Standard Material/Zensical admonition types (frame color matches icon):

```markdown
!!! note
!!! abstract / !!! info / !!! tip / !!! hint
!!! success / !!! check / !!! done
!!! question / !!! faq / !!! help
!!! warning / !!! caution / !!! attention
!!! failure / !!! fail / !!! missing
!!! danger / !!! error
!!! bug / !!! example / !!! quote / !!! cite
```

Collapsible variant: `???` (collapsed by default) or `???+` (open by default).

---

## CSS design tokens

Admonition accent colors are defined as CSS variables in `:root` inside `styles.css`.  
To change any type's color, update only the token:

```css
:root {
  --admonition-warning-color: #ff9100;  /* change here to affect border + title bar */
  /* ... one variable per type ... */
}
```

Mouse SVGs are inlined as data URIs in `--mouse-left-svg` / `--mouse-right-svg` (required for `file://` offline mode).

---

## Annotations syntax

For a **paragraph**:
```markdown
Some text with annotation (1) here.
{ .annotate }

1. Annotation content.
```

For a **list item** (no blank line before `{ .annotate }`):
```markdown
- List item with annotation (1)
{ .annotate }

    1. Annotation content.
```
