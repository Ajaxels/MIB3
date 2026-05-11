import json
from pathlib import Path
from networkx.readwrite import json_graph
import networkx as nx

data = json.loads(Path('graphify-out/graph.json').read_text())
G = json_graph.node_link_graph(data, edges='links')
DG = nx.DiGraph(G)

# Find crossShiftStacks
target = 'utils_align_crossshiftstacks_m'
callers = [(u, G.nodes[u].get('label','?')) for u, v, d in DG.in_edges(target, data=True) if d.get('relation') == 'calls']
print(f'crossShiftStacks called by ({len(callers)}):')
for nid, label in sorted(callers, key=lambda x: x[1]):
    print(f'  {label}')

# Also check showErrorDialog callers (top 5)
sed = 'utils_dlgs_showerrordialog_m'
sed_callers = [(u, G.nodes[u].get('label','?')) for u, v, d in DG.in_edges(sed, data=True)]
print(f'\nshowErrorDialog called by ({len(sed_callers)} files) — sample:')
for nid, label in sorted(sed_callers, key=lambda x: x[1])[:8]:
    print(f'  {label}')

# Overall stats
print()
rel_counts = {}
for u, v, d in G.edges(data=True):
    r = d.get('relation', '?')
    rel_counts[r] = rel_counts.get(r, 0) + 1
print('Edge types:')
for r, c in sorted(rel_counts.items(), key=lambda x: -x[1]):
    print(f'  {r}: {c}')
