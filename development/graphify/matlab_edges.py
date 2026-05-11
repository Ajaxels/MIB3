"""
matlab_edges.py  — inject MATLAB-specific edges into graphify's AST result.

Graphify routes .m files to the Objective-C extractor (wrong language), so
it produces almost no edges. This script adds them deterministically from
folder structure and source parsing.

Handles three MATLAB OOP patterns:

  Pattern A — @ClassName/ folder, external methods only
      All methods live in separate .m files inside the folder.

  Pattern B — @ClassName/ folder + inline methods  (e.g. MeasureTool.m)
      Bare method declarations in the methods block → external .m files.
      Full `function ... end` blocks → inline methods captured here.

  Pattern C — standalone classdef (e.g. MibDeepActivations.m)
      No @ClassName/ folder; classdef and ALL methods in one file.

Edges produced:
  1. ClassName -contains-> external_method_file   (folder scan)
  2. ClassName -contains-> inline_method_node     (function keyword parse)
  3. ClassName -inherits_from-> Parent            (classdef X < Y parse)
  4. caller -calls-> callee                        (obj.method / ClassName() heuristic)

Run AFTER build_ast.py, BEFORE merge_extraction.py.
"""

import json
import re
from pathlib import Path

ROOT = Path('mib')
AST_FILE = Path('graphify-out/.graphify_ast.json')

ast = json.loads(AST_FILE.read_text(encoding='utf-8'))
nodes_by_id = {n['id']: n for n in ast['nodes']}
existing_edges = set((e['source'], e['target']) for e in ast['edges'])

new_edges = []
new_nodes = []

# ─── regex patterns ───────────────────────────────────────────────────────────
# function [retval =] funcName(  — must start with 'function' keyword
FUNC_RE = re.compile(
    r'^\s*function\s+(?:[\w\[\],\s~.]+\s*=\s*)?(\w+)\s*\(',
    re.MULTILINE,
)
# classdef ClassName [< Parent]
CLASSDEF_RE = re.compile(r'^\s*classdef\s+(\w+)(?:\s*<\s*([\w.]+))?', re.MULTILINE)
# strip comment lines (% ...)
COMMENT_RE = re.compile(r'^\s*%.*$', re.MULTILINE)


def strip_comments(src: str) -> str:
    return COMMENT_RE.sub('', src)


def file_to_id(path: Path) -> str:
    """Convert a mib/-relative path to the graphify node ID."""
    rel = path.relative_to(ROOT)
    parts = []
    for part in rel.parts:
        clean = part.lstrip('+').lstrip('@')
        parts.append(clean.lower())
    raw = '_'.join(parts)
    return re.sub(r'[^a-z0-9]+', '_', raw).strip('_')


def inline_method_id(class_node_id: str, method_name: str) -> str:
    """Node ID for an inline method: class_node_id + '_' + method_name (lower)."""
    base = class_node_id[:-2] if class_node_id.endswith('_m') else class_node_id
    return f'{base}_{method_name.lower()}'


def add_edge(source_id, target_id, relation, source_file, confidence='EXTRACTED', score=1.0):
    key = (source_id, target_id)
    if key in existing_edges:
        return
    existing_edges.add(key)
    new_edges.append({
        'source': source_id,
        'target': target_id,
        'relation': relation,
        'confidence': confidence,
        'confidence_score': score,
        'source_file': str(source_file),
        'source_location': None,
        'weight': 1.0,
    })


def ensure_node(node_id, label, source_file):
    if node_id not in nodes_by_id:
        node = {
            'id': node_id,
            'label': label,
            'file_type': 'code',
            'source_file': str(source_file),
            'source_location': None,
            'source_url': None,
            'captured_at': None,
            'author': None,
            'contributor': None,
        }
        nodes_by_id[node_id] = node
        new_nodes.append(node)


def parse_inline_methods(class_node_id: str, classdef_file: Path,
                         known_external_stems: set) -> list:
    """
    Parse `function` definitions inside a classdef .m file.
    Returns list of (method_node_id, method_name) for inline methods only.
    Skips methods that already have an external .m file (Pattern A/B split).
    """
    try:
        src = classdef_file.read_text(encoding='utf-8', errors='replace')
    except Exception:
        return []
    src_no_comments = strip_comments(src)
    results = []
    seen = set()
    for m in FUNC_RE.finditer(src_no_comments):
        name = m.group(1)
        name_lower = name.lower()
        if name_lower in seen:
            continue
        seen.add(name_lower)
        # Skip if there is already an external file for this method
        if name_lower in known_external_stems:
            continue
        node_id = inline_method_id(class_node_id, name)
        results.append((node_id, name))
    return results


# ─────────────────────────────────────────────────────────────────────────────
# Collect: (a) @ClassName dirs, (b) standalone classdef files
# ─────────────────────────────────────────────────────────────────────────────
at_dirs = sorted(d for d in ROOT.rglob('@*') if d.is_dir())

# Standalone classdefs: .m files NOT inside any @ClassName dir
at_dir_set = set(str(d) for d in at_dirs)

def is_in_at_dir(path: Path) -> bool:
    for part in path.parts:
        if part.startswith('@'):
            return True
    return False

# Map classname (lower) → class node ID (populated across all passes)
class_ids: dict[str, str] = {}

# ─────────────────────────────────────────────────────────────────────────────
# Pass 1 — @ClassName/ folders: external files + inline methods
# ─────────────────────────────────────────────────────────────────────────────
contains_edges_before = len(new_edges)
inline_count_p1 = 0

for at_dir in at_dirs:
    class_name = at_dir.name.lstrip('@')
    class_name_lower = class_name.lower()

    class_m = at_dir / f'{class_name}.m'
    if not class_m.exists():
        candidates = sorted(at_dir.glob('*.m'))
        if not candidates:
            continue
        class_m = candidates[0]

    class_node_id = file_to_id(class_m)
    class_ids[class_name_lower] = class_node_id
    ensure_node(class_node_id, f'{class_name}.m', class_m.relative_to(ROOT))

    # External method files (everything else in the folder)
    external_stems: set[str] = set()
    for method_m in sorted(at_dir.glob('*.m')):
        if method_m == class_m:
            continue
        method_node_id = file_to_id(method_m)
        ensure_node(method_node_id, method_m.name, method_m.relative_to(ROOT))
        add_edge(class_node_id, method_node_id, 'contains', class_m.relative_to(ROOT))
        external_stems.add(method_m.stem.lower())

    # Inline methods in the main classdef file
    for method_node_id, method_name in parse_inline_methods(
            class_node_id, class_m, external_stems):
        ensure_node(method_node_id, method_name,
                    class_m.relative_to(ROOT))
        add_edge(class_node_id, method_node_id, 'contains',
                 class_m.relative_to(ROOT))
        inline_count_p1 += 1

print(f'Pass 1: {len(at_dirs)} @ClassName dirs -> '
      f'{len(new_edges) - contains_edges_before} contains edges '
      f'({inline_count_p1} from inline functions)')

# ─────────────────────────────────────────────────────────────────────────────
# Pass 2 — Standalone classdef files (no @ClassName dir)
# ─────────────────────────────────────────────────────────────────────────────
standalone_count = 0
inline_count_p2 = 0

for m_file in sorted(ROOT.rglob('*.m')):
    if is_in_at_dir(m_file):
        continue
    try:
        src = m_file.read_text(encoding='utf-8', errors='replace')
    except Exception:
        continue
    cd_match = CLASSDEF_RE.search(src)
    if not cd_match:
        continue  # not a classdef

    class_name = cd_match.group(1)
    class_name_lower = class_name.lower()
    class_node_id = file_to_id(m_file)
    class_ids[class_name_lower] = class_node_id
    ensure_node(class_node_id, m_file.name, m_file.relative_to(ROOT))
    standalone_count += 1

    for method_node_id, method_name in parse_inline_methods(
            class_node_id, m_file, set()):
        ensure_node(method_node_id, method_name, m_file.relative_to(ROOT))
        add_edge(class_node_id, method_node_id, 'contains', m_file.relative_to(ROOT))
        inline_count_p2 += 1

print(f'Pass 2: {standalone_count} standalone classdefs -> {inline_count_p2} inline method nodes')

# ─────────────────────────────────────────────────────────────────────────────
# Pass 3 — classdef X < ParentClass → inherits_from
# ─────────────────────────────────────────────────────────────────────────────
INHERITS_RE = re.compile(r'^\s*classdef\s+\w+\s*<\s*([\w.]+)', re.MULTILINE)
inherits_count = 0

all_classdef_files = (
    [at_dir / f'{at_dir.name.lstrip("@")}.m' for at_dir in at_dirs]
    + [f for f in ROOT.rglob('*.m') if not is_in_at_dir(f)]
)

for cf in all_classdef_files:
    if not cf.exists():
        continue
    try:
        src = cf.read_text(encoding='utf-8', errors='replace')
    except Exception:
        continue
    for m in INHERITS_RE.finditer(src):
        parent_str = m.group(1).strip()
        if '.' in parent_str or parent_str.lower() in ('handle', 'copyable'):
            continue
        child_id = class_ids.get(cf.stem.lower())
        parent_id = class_ids.get(parent_str.lower())
        if child_id and parent_id and child_id != parent_id:
            add_edge(child_id, parent_id, 'inherits_from', cf.relative_to(ROOT))
            inherits_count += 1

print(f'Pass 3: {inherits_count} inherits_from edges')

# ─────────────────────────────────────────────────────────────────────────────
# Pass 4 — Call-site heuristics (obj.method / ClassName constructor)
# ─────────────────────────────────────────────────────────────────────────────
# Build method lookup: method_name_lower -> [(class_node_id, method_node_id)]
method_lookup: dict[str, list] = {}
for nid, ndata in nodes_by_id.items():
    label = ndata.get('label', '')
    # inline method nodes have label == method name (no .m suffix)
    if not label.endswith('.m'):
        for cid in class_ids.values():
            if nid.startswith(cid[:-2] if cid.endswith('_m') else cid):
                method_lookup.setdefault(label.lower(), []).append((cid, nid))
                break
    else:
        # External method file: stem → class it belongs to
        src_file = ndata.get('source_file', '')
        p = Path(src_file)
        if len(p.parts) >= 2 and p.parts[-2].startswith('@'):
            owner_class = p.parts[-2].lstrip('@').lower()
            cid = class_ids.get(owner_class)
            if cid:
                method_lookup.setdefault(p.stem.lower(), []).append((cid, nid))

constructor_lookup = {cn: cid for cn, cid in class_ids.items()}

CALL_RE = re.compile(r'\b([A-Z][A-Za-z0-9_]*)\s*[(<]')
METHOD_CALL_RE = re.compile(r'\bobj\.([a-zA-Z][a-zA-Z0-9_]*)\s*[(<]')

call_edges_added = 0

def scan_calls(caller_id: str, src: str, src_rel: Path, owner_class_lower: str | None = None):
    global call_edges_added
    src_nc = strip_comments(src)
    for m in CALL_RE.finditer(src_nc):
        callee_name = m.group(1).lower()
        callee_id = constructor_lookup.get(callee_name)
        if callee_id and callee_id != caller_id:
            add_edge(caller_id, callee_id, 'calls', src_rel, 'INFERRED', 0.7)
            call_edges_added += 1
    if owner_class_lower:
        class_node_id = class_ids.get(owner_class_lower)
        for m in METHOD_CALL_RE.finditer(src_nc):
            callee_stem = m.group(1).lower()
            for cid, mid in method_lookup.get(callee_stem, []):
                if cid == class_node_id and mid != caller_id:
                    add_edge(caller_id, mid, 'calls', src_rel, 'INFERRED', 0.75)
                    call_edges_added += 1

# Scan external method files
for at_dir in at_dirs:
    class_name = at_dir.name.lstrip('@')
    for method_m in at_dir.glob('*.m'):
        try:
            src = method_m.read_text(encoding='utf-8', errors='replace')
        except Exception:
            continue
        scan_calls(file_to_id(method_m), src,
                   method_m.relative_to(ROOT), class_name.lower())

# Scan standalone classdef files (call heuristic only — inline method nodes
# inherit source from the class file, so use the class node as caller)
for m_file in ROOT.rglob('*.m'):
    if is_in_at_dir(m_file):
        continue
    cid = class_ids.get(m_file.stem.lower())
    if not cid:
        continue
    try:
        src = m_file.read_text(encoding='utf-8', errors='replace')
    except Exception:
        continue
    scan_calls(cid, src, m_file.relative_to(ROOT), m_file.stem.lower())

print(f'Pass 4: {call_edges_added} call edges (INFERRED)')

# ─────────────────────────────────────────────────────────────────────────────
# Pass 5 — Package-qualified function calls: utils.pkg.func(...)
#
# Covers calls that Pass 4 misses because they use dot-package syntax with a
# lowercase function name, e.g.:
#   utils.align.crossShiftStacks(...)
#   utils.dlgs.showErrorDialog(...)
#   utils.fontSizeUpdate(...)
#   deepmib.storeLoadImages(...)
# ─────────────────────────────────────────────────────────────────────────────

# Step 5a — find top-level package names from the mib/ directory
top_pkgs = sorted(
    d.name.lstrip('+')
    for d in ROOT.iterdir()
    if d.is_dir() and d.name.startswith('+')
)


def file_to_qualified_name(path: Path) -> str | None:
    """Return the dot-qualified package name for a file inside mib/+pkg/... folders.

    Returns None if the file is inside an @ClassName dir or a non-package dir.
    """
    try:
        rel = path.relative_to(ROOT)
    except ValueError:
        return None
    parts: list[str] = []
    for part in rel.parts[:-1]:  # directory components only
        if part.startswith('+'):
            parts.append(part.lstrip('+'))
        else:
            return None  # hit a non-package dir (includes @ClassName)
    parts.append(path.stem)
    return '.'.join(parts)


# Step 5b — build index: qualified_name_lower → node_id
# Includes both plain functions AND classdef files in packages (static calls)
pkg_func_by_full: dict[str, str] = {}   # 'utils.align.crossshiftstacks' → nid
pkg_func_by_tail: dict[str, list] = {}  # 'align.crossshiftstacks' → [nid, ...]

top_pkgs_set = set(top_pkgs)

for m_file in sorted(ROOT.rglob('*.m')):
    if is_in_at_dir(m_file):
        continue
    qual = file_to_qualified_name(m_file)
    if not qual:
        continue
    if qual.split('.')[0] not in top_pkgs_set:
        continue
    nid = file_to_id(m_file)
    key = qual.lower()
    pkg_func_by_full[key] = nid
    tail = '.'.join(qual.split('.')[1:]).lower()
    if tail:
        pkg_func_by_tail.setdefault(tail, []).append(nid)

print(f'Pass 5: indexed {len(pkg_func_by_full)} package-qualified names')


def lookup_pkg_func(pkg: str, rest: str) -> str | None:
    """Resolve a call like utils + .align.crossShiftStacks to a node ID."""
    full_key = (pkg + rest).lower()
    nid = pkg_func_by_full.get(full_key)
    if nid:
        return nid
    # Try tail (strip the leading package component — handles partial qualification)
    tail_key = rest.lstrip('.').lower()
    candidates = pkg_func_by_tail.get(tail_key, [])
    if len(candidates) == 1:
        return candidates[0]
    return None


# Step 5c — build a regex that only fires when the call starts with a known
# top-level package name, preventing false matches on obj.prop.method patterns
_pkg_alt = '|'.join(re.escape(p) for p in sorted(top_pkgs, key=len, reverse=True))
PKG_CALL_RE = re.compile(
    r'\b(' + _pkg_alt + r')((?:\.[a-zA-Z][a-zA-Z0-9_]*)+)\s*\('
)

# Step 5d — scan every .m file that has a node in the graph
pkg_call_count = 0

for m_file in sorted(ROOT.rglob('*.m')):
    caller_id = file_to_id(m_file)
    if caller_id not in nodes_by_id:
        continue
    try:
        src = m_file.read_text(encoding='utf-8', errors='replace')
    except Exception:
        continue
    src_nc = strip_comments(src)
    for m in PKG_CALL_RE.finditer(src_nc):
        pkg = m.group(1)
        rest = m.group(2)
        callee_id = lookup_pkg_func(pkg, rest)
        if callee_id and callee_id != caller_id:
            add_edge(caller_id, callee_id, 'calls', m_file.relative_to(ROOT),
                     'EXTRACTED', 1.0)
            pkg_call_count += 1

print(f'Pass 5: {pkg_call_count} package-function call edges (EXTRACTED)')

# ─────────────────────────────────────────────────────────────────────────────
# Write back
# ─────────────────────────────────────────────────────────────────────────────
ast['nodes'].extend(new_nodes)
ast['edges'].extend(new_edges)

AST_FILE.write_text(json.dumps(ast, indent=2), encoding='utf-8')

print()
print(f'Done. AST updated: {len(ast["nodes"])} nodes, {len(ast["edges"])} edges')
print(f'  New nodes: {len(new_nodes)}  |  New edges: {len(new_edges)}')
