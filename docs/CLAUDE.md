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
