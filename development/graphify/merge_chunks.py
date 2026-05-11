import json, glob
from pathlib import Path

# Merge chunk results
chunks = sorted(glob.glob('graphify-out/.graphify_chunk_*.json'))
all_nodes, all_edges, all_hyperedges = [], [], []
total_in, total_out = 0, 0

for c in chunks:
    d = json.loads(Path(c).read_text())
    all_nodes += d.get('nodes', [])
    all_edges += d.get('edges', [])
    all_hyperedges += d.get('hyperedges', [])
    total_in += d.get('input_tokens', 0)
    total_out += d.get('output_tokens', 0)

Path('graphify-out/.graphify_semantic_new.json').write_text(json.dumps({
    'nodes': all_nodes, 'edges': all_edges, 'hyperedges': all_hyperedges,
    'input_tokens': total_in, 'output_tokens': total_out,
}, indent=2))

print(f'Merged {len(chunks)} chunks: {total_in:,} in / {total_out:,} out tokens')
print(f'  Nodes: {len(all_nodes)}')
print(f'  Edges: {len(all_edges)}')
print(f'  Hyperedges: {len(all_hyperedges)}')
