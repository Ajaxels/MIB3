import json
from pathlib import Path

ast = json.loads(Path('graphify-out/.graphify_ast.json').read_text())

# Show all 5 edges
print('All AST edges:')
for e in ast['edges']:
    src = e.get('source', '?')
    tgt = e.get('target', '?')
    rel = e.get('relation', '?')
    conf = e.get('confidence', '?')
    print(f'  {src} --{rel}--> {tgt}  [{conf}]')

print()

# Check MibDataset nodes
mib_nodes = [n for n in ast['nodes'] if 'MibDataset' in n.get('label','') or 'MibDataset' in n.get('id','')]
print(f'MibDataset nodes ({len(mib_nodes)}):')
for n in mib_nodes[:5]:
    print(f'  id={n["id"]}  label={n["label"]}  src={n.get("source_file","")}')

print()

# Show a few random nodes to understand what was extracted
print('Sample nodes (first 10):')
for n in ast['nodes'][:10]:
    print(f'  id={n["id"]}  label={n["label"]}  src={n.get("source_file","")}')

# Check what extensions are present
exts = {}
for n in ast['nodes']:
    sf = n.get('source_file','')
    if sf:
        ext = Path(sf).suffix
        exts[ext] = exts.get(ext,0)+1
print()
print('Source file extensions in AST nodes:')
for ext, cnt in sorted(exts.items(), key=lambda x:-x[1]):
    print(f'  {ext}: {cnt}')
