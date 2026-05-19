# Running Graphify for MIB3

Complete graphify update for MIB3 codebase in one command.

## Quick Start

```bash
cd C:\Matlab\MIB3
python development/graphify/run_all.py
```

That's it. Everything else is automated.

---

## What This Does

The `run_all.py` script orchestrates the complete graphify pipeline in the correct order:

1. **detect_graph.py** — Scan `mib/` folder for files (738 MATLAB files + 3 docs)
2. **build_ast.py** — Extract AST from code files (735 nodes, 5 edges)
3. **matlab_edges.py** — Inject MATLAB-specific edges using structural analysis (adds 969 nodes, 2860 edges)
   - Detects `@ClassName/` folder patterns and external method files
   - Finds inline methods inside classdef files
   - Extracts inheritance (`classdef X < Y`)
   - Detects method calls (`obj.method(...)`)
   - Detects package-qualified function calls (`utils.pkg.func(...)`)
4. **Clustering** — Build networkx graph and cluster into 112 communities
5. **gen_html.py** — Generate interactive graph.html visualization

**Output:** `graphify-out/` directory with:
- `graph.json` — raw graph data
- `graph.html` — interactive visualization (open in browser)
- `GRAPH_REPORT.md` — audit report with god nodes, communities, insights

---

## How to Create run_all.py

Create `development/graphify/run_all.py`:

```python
#!/usr/bin/env python3
"""
Complete graphify pipeline for MIB3.
Runs all steps in the correct order:
  1. detect_graph.py
  2. build_ast.py
  3. matlab_edges.py
  4. cluster_graph.py
  5. gen_html.py
"""

import sys
from pathlib import Path
import subprocess

# Find Python executable used to run this script
PYTHON = sys.executable
ROOT = Path(__file__).parent.parent.parent  # C:\Matlab\MIB3

def run_step(script_name, description):
    """Run a single step and report results."""
    script_path = ROOT / 'development' / 'graphify' / script_name
    print(f'\n=== {description} ===')
    print(f'Running: {script_path}')
    result = subprocess.run([PYTHON, str(script_path)], cwd=str(ROOT))
    if result.returncode != 0:
        print(f'ERROR: {script_name} failed with exit code {result.returncode}')
        sys.exit(1)
    print(f'✓ {description} complete')


def main():
    print('MIB3 Graphify Pipeline')
    print(f'Python: {PYTHON}')
    print(f'Root: {ROOT}')

    steps = [
        ('detect_graph.py', 'Step 1: Detect files'),
        ('build_ast.py', 'Step 2: Extract AST from code'),
        ('matlab_edges.py', 'Step 3: Inject MATLAB-specific edges'),
        ('cluster_graph.py', 'Step 4: Cluster graph'),
        ('gen_html.py', 'Step 5: Generate HTML visualization'),
    ]

    for script, desc in steps:
        run_step(script, desc)

    print('\n' + '='*60)
    print('✓ Graphify update complete!')
    print('='*60)
    print(f'Outputs: {ROOT}/graphify-out/')
    print('  - graph.html (open in browser)')
    print('  - GRAPH_REPORT.md (architecture insights)')
    print('  - graph.json (raw data)')


if __name__ == '__main__':
    main()
```

---

## Scripts Included

### detect_graph.py
Scans `mib/` folder and identifies all code/doc/video files.
- **Input:** (none, scans filesystem)
- **Output:** `graphify-out/.graphify_detect.json`
- **Time:** <1s

### build_ast.py
Extracts AST using graphify's built-in language parsers.
- **Input:** `.graphify_detect.json`
- **Output:** `graphify-out/.graphify_ast.json`
- **Time:** ~30s (falls back to sequential on Windows)
- **Note:** Routes .m files to wrong language handler; matlab_edges.py fixes this

### matlab_edges.py
**CRITICAL STEP** — Injects MATLAB-specific edges that graphify's AST misses.

Performs 5 passes:
1. **@ClassName/ folders** — external methods + inline functions
2. **Standalone classdefs** — all methods in one file
3. **Inheritance** — classdef X < Parent
4. **Method calls** — obj.method(...) heuristics
5. **Package calls** — utils.pkg.func(...) with regex + lookup table

- **Input:** `.graphify_ast.json`
- **Output:** `.graphify_ast.json` (updated with new nodes/edges)
- **Time:** ~5s
- **Result:** Grows graph from 735 nodes / 5 edges → 1704 nodes / 2865 edges

### cluster_graph.py
Builds networkx graph, clusters into communities, generates report.
- **Input:** `.graphify_ast.json`, `.graphify_detect.json`
- **Output:**
  - `graph.json` (for visualization + queries)
  - `GRAPH_REPORT.md` (god nodes, surprising connections, community breakdown)
  - `.graphify_analysis.json` (analysis data for later tools)
- **Time:** ~10s
- **Result:** 112 communities, cohesion scores, surprise detection

### gen_html.py
Generates interactive D3.js graph visualization.
- **Input:** `graph.json`, `.graphify_analysis.json`
- **Output:** `graph.html`
- **Time:** ~3s
- **Open:** `graphify-out/graph.html` in any browser

---

## Directory Structure

```
development/graphify/
  ├── run_graphify.md                    ← you are here
  ├── run_all.py                         ← orchestrator (create this)
  ├── detect_graph.py                    ← file detection
  ├── build_ast.py                       ← AST extraction
  ├── matlab_edges.py                    ← MATLAB-specific edges
  ├── cluster_graph.py                   ← clustering + report
  ├── gen_html.py                        ← HTML viz
  ├── inspect_ast.py                     ← (debugging: inspect AST nodes/edges)
  ├── verify_graph.py                    ← (debugging: validate graph.json)
  ├── merge_chunks.py                    ← (for semantic extraction if used)
  └── merge_extraction.py                ← (for semantic extraction if used)

graphify-out/                            ← output directory (auto-created)
  ├── .graphify_detect.json              ← file manifest
  ├── .graphify_ast.json                 ← final merged AST + MATLAB edges
  ├── .graphify_analysis.json            ← community analysis data
  ├── graph.json                         ← graph data (for viz + queries)
  ├── graph.html                         ← interactive visualization
  ├── GRAPH_REPORT.md                    ← audit report
  └── cost.json                          ← token usage tracking (0 for AST)
```

---

## Troubleshooting

### Python not found
```bash
# Set Python explicitly
set PYTHON=d:\Python\Mambaforge\envs\mkdocs\python.exe
%PYTHON% development/graphify/run_all.py
```

### graphify module not found
```bash
# Install graphify in the current environment
pip install graphifyy
```

### Port multiprocessing errors (Windows)
Normal — the scripts fall back to sequential extraction automatically. No action needed.

### Unicode errors writing files
Ensure all scripts open files with `encoding='utf-8'`. Already handled in provided scripts.

### matlab_edges.py is slow
It's doing 5 passes over all .m files. Normal for 738 files. Takes ~5s.

### graph.html is blank
Likely a large graph (>5000 nodes). Check `graphify-out/GRAPH_REPORT.md` instead. The HTML viz has limits due to browser performance.

---

## Output Interpretation

### graph.html
Interactive visualization. Zoom, pan, hover over nodes to see:
- **Node label** (function/class name)
- **Degree** (number of connections)
- **Community** (color-coded)

Relationships:
- **Solid lines** = calls / contains / inherits
- **Dashed lines** = inferred (confidence 0.7-0.75)

### GRAPH_REPORT.md

**God Nodes** — highly connected components (possible hubs or utilities)

**Surprising Connections** — edges that cross community boundaries unexpectedly

**Communities** — grouped by modularity. Each community shows:
- Cohesion (0.0-1.0, higher = more tightly grouped)
- Node count
- Sample nodes

**Knowledge Gaps** — isolated nodes or undocumented relationships

### graph.json
Raw networkx JSON format. Use for:
- Custom analysis
- Programmatic queries
- Integration with other tools

---

## Next Steps After Update

1. **Review GRAPH_REPORT.md** — understand architecture from god nodes + surprising connections
2. **Open graph.html** — explore visually, find tightly-knit clusters (high cohesion = stable subsystems)
3. **Query the graph** (if you add MCP server support):
   ```bash
   python -m graphify.serve graphify-out/graph.json
   ```
4. **Update when code changes** — re-run `run_all.py` to refresh (incremental cache speeds it up)

---

## Environment

- **Python:** Any version that graphify supports (3.9+)
- **Required packages:** graphify, networkx
- **Time for full run:** ~50 seconds
- **Token cost:** 0 (AST-only + structural analysis)
- **Disk space:** ~20 MB for outputs

---

## References

- `matlab_edges.py` — MATLAB structural patterns (53 @ClassName dirs, 50 standalone classdefs)
- `develop/docs_api_sphinx.md` — RST documentation standards
- `mib/mib3.m` — entry point
- `CLAUDE.md` — architecture overview
