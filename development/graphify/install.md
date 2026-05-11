# Graphify — Installation and Usage Guide for MIB3

Graphify builds a navigable knowledge graph of the MIB3 MATLAB codebase.
It produces three outputs in `graphify-out/`:

- `graph.html` — interactive browser visualization
- `graph.json` — raw graph data (queryable by AI agents)
- `GRAPH_REPORT.md` — audit report with god nodes and community analysis

---

## 1. Prerequisites

- **Python 3.9+** — any distribution (Anaconda, Mambaforge, system Python)
- **Git** — repo must be cloned locally

---

## 2. Install the graphify package

```bash
pip install graphify
```

Or into a specific conda/mamba environment:

```bash
conda activate myenv
pip install graphify
```

Verify installation:

```bash
python -c "import graphify; print('OK')"
```

> **Note:** The MIB3 graphify pipeline uses graphify as a library only.
> The standard graphify package is unmodified — all MIB3-specific logic
> lives in the scripts in this folder.

---

## 3. Connect to GitHub Copilot CLI

This registers the `/graphify` slash command so Copilot can query the graph
interactively in the terminal.

```bash
graphify copilot install
```

The skill is installed per-user at:
- **Windows:** `%USERPROFILE%\.copilot\skills\graphify\SKILL.md`
- **Linux/macOS:** `~/.copilot/skills/graphify/SKILL.md`

After installation, `/graphify query "..."` and `/graphify explain "..."` work
in any Copilot CLI session from the repo directory.

To uninstall:

```bash
graphify copilot uninstall
```

---

## 4. Connect to Claude Code

The same skill file is picked up automatically by Claude Code (GitHub Copilot
coding agent). No extra step is needed beyond the `graphify copilot install`
above — Claude Code reads skills from the same `~/.copilot/skills/` directory.

Once installed, Claude Code follows these rules (already added to `CLAUDE.md`):
- Reads `graphify-out/GRAPH_REPORT.md` before answering architecture questions
- Uses `graphify query` / `graphify path` / `graphify explain` for cross-module questions
- Runs `graphify update .` after code changes (calls the pipeline scripts below)

---

## 5. Build the graph for the first time

All scripts must be run **from the repository root** (`C:\Matlab\MIB3`).

```bash
cd C:\Matlab\MIB3

python development\graphify\build_ast.py
python development\graphify\matlab_edges.py
python development\graphify\merge_extraction.py
python development\graphify\cluster_graph.py
python development\graphify\gen_html.py
```

Expected output of a full run:

```
Extracting AST from 708 code files...
AST: 709 nodes, 5 edges
Pass 1: 51 @ClassName dirs → 1028 contains edges (381 from inline functions)
Pass 2: 50 standalone classdefs → 405 inline method nodes
Pass 3: 2 inherits_from edges
Pass 4: 1753 call edges (INFERRED)
Pass 5: indexed 146 package-qualified names
Pass 5: 1088 package-function call edges (EXTRACTED)
Done. AST updated: 1649 nodes, 2708 edges
Merged: 1725 nodes, 2825 edges (1649 AST + 76 semantic)
Graph: 1725 nodes, 2815 edges, 112 communities
graph.html written - open in any browser
```

Total runtime: ~30 seconds. No LLM calls are required for the MATLAB source
files — everything is deterministic.

> **Semantic extraction** (LLM-based) is only used for the three documentation
> files in `mib/` (`mib_structure.txt`, `project_structure.txt`,
> `mib3_prefs_override.txt`). Results are cached in `graphify-out/cache/`.
> On subsequent runs these are skipped automatically.

---

## 6. Update the graph after code changes

Run the same five commands from section 5. The AST and MATLAB edge passes
are fast (~25 s) and fully deterministic — safe to run after every commit.

For convenience, a one-liner:

```bash
cd C:\Matlab\MIB3 && python development\graphify\build_ast.py && python development\graphify\matlab_edges.py && python development\graphify\merge_extraction.py && python development\graphify\cluster_graph.py && python development\graphify\gen_html.py
```

---

## 7. Query the graph

After building, use these commands from the repo root:

```bash
# Broad context — what is X connected to?
graphify query "MibModel data flow"

# Trace a specific path
graphify path "MibController" "MibDataset"

# Explain a specific class or function
graphify explain "MibDeepActivations"
```

These work in both the Copilot CLI terminal and as slash commands inside
Claude Code sessions.

---

## 8. What each script does

| Script | Step | Description |
|--------|------|-------------|
| `detect_graph.py` | 1 | Detects files under `mib/`, writes `.graphify_detect.json` |
| `build_ast.py` | 2 | Runs graphify's AST extractor on all `.m` files → `.graphify_ast.json` |
| `matlab_edges.py` | 3 | **Custom.** Injects MATLAB-specific edges (see below) |
| `check_cache.py` | 4a | Checks semantic LLM cache for doc files |
| `prepare_chunks.py` | 4b | Splits uncached doc files into chunks for LLM subagents |
| `merge_chunks.py` | 4c | Merges LLM chunk results |
| `merge_extraction.py` | 5 | Merges AST + semantic → `.graphify_extract.json` |
| `cluster_graph.py` | 6 | Builds graph, detects communities, writes `GRAPH_REPORT.md` + `graph.json` |
| `gen_html.py` | 7 | Generates `graph.html` interactive visualization |
| `inspect_ast.py` | diag | Prints statistics about the raw AST extraction result |
| `verify_graph.py` | diag | Checks specific nodes and edges in the built graph |

### Why `matlab_edges.py` is needed

Graphify's built-in AST extractor routes `.m` files to its **Objective-C parser**
(same file extension, wrong language). The ObjC parser finds zero MATLAB
structures, producing only 5 edges from 708 files.

`matlab_edges.py` compensates with five passes over the source tree:

| Pass | What it finds | Edge type | Confidence |
|------|---------------|-----------|------------|
| 1 | `@ClassName/method.m` folder layout + inline `function` blocks | `contains` | EXTRACTED |
| 2 | Standalone classdef files (`MibDeepActivations.m` etc.) + their inline methods | `contains` | EXTRACTED |
| 3 | `classdef X < Y` inheritance declarations | `inherits_from` | EXTRACTED |
| 4 | `obj.method(` and `ClassName(` call-site patterns | `calls` | INFERRED 0.7–0.75 |
| 5 | Package-qualified calls: `utils.align.func(`, `core.Class(` etc. | `calls` | EXTRACTED 1.0 |

---

## 9. File layout

```
C:\Matlab\MIB3\
  .graphifyignore              # controls which files are included (repo root)
  graphify-out\                # generated outputs (not committed)
    graph.html                 # open in any browser
    graph.json                 # graph data
    GRAPH_REPORT.md            # audit report
    cache\                     # LLM semantic cache (commit to skip re-extraction)
  development\
    graphify\
      install.md               # this file
      build_ast.py
      matlab_edges.py
      merge_extraction.py
      cluster_graph.py
      gen_html.py
      detect_graph.py
      check_cache.py
      prepare_chunks.py
      merge_chunks.py
      inspect_ast.py
      verify_graph.py
```

---

## 10. Troubleshooting

**`ModuleNotFoundError: No module named 'graphify'`**
→ Wrong Python interpreter. Use the one where you ran `pip install graphify`.
Prefix each command with the full path, e.g.:
```bash
d:\Python\Mambaforge\envs\mkdocs\python.exe development\graphify\build_ast.py
```

**Graph shows classes as isolated nodes (no methods)**
→ `matlab_edges.py` was not run, or was run before `build_ast.py`.
Always run in the order: `build_ast.py` → `matlab_edges.py` → `merge_extraction.py`.

**`graphify-out/.graphify_semantic_new.json` not found**
→ The semantic (LLM) extraction step was never run for the doc files.
Run `check_cache.py` to see which files are uncached, then run the
graphify skill's semantic extraction step for those files.
After one run the results are cached and the error disappears.

**`UnicodeEncodeError` on Windows**
→ All scripts use `encoding='utf-8'` explicitly. If this appears in a
third-party graphify function, set the environment variable:
```bash
set PYTHONUTF8=1
```
