import json
from graphify.cache import check_semantic_cache
from pathlib import Path

detect = json.loads(Path('graphify-out/.graphify_detect.json').read_text())
all_files = [f for files in detect['files'].values() for f in files]

cached_nodes, cached_edges, cached_hyperedges, uncached = check_semantic_cache(all_files)

if cached_nodes or cached_edges or cached_hyperedges:
    Path('graphify-out/.graphify_cached.json').write_text(json.dumps({'nodes': cached_nodes, 'edges': cached_edges, 'hyperedges': cached_hyperedges}))
Path('graphify-out/.graphify_uncached.txt').write_text('\n'.join(uncached))

total_cached = len(all_files) - len(uncached)
print(f'Cache: {total_cached} files hit, {len(uncached)} files need extraction')
print(f'Uncached files: {len(uncached)}')

# Show breakdown
docs = detect.get('files', {}).get('document', [])
papers = detect.get('files', {}).get('paper', [])
images = detect.get('files', {}).get('image', [])

uncached_set = set(uncached)
doc_uncached = sum(1 for f in docs if f in uncached_set)
paper_uncached = sum(1 for f in papers if f in uncached_set)
image_uncached = sum(1 for f in images if f in uncached_set)

print(f'  docs: {doc_uncached}/{len(docs)}')
print(f'  papers: {paper_uncached}/{len(papers)}')
print(f'  images: {image_uncached}/{len(images)}')
