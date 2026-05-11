import json
from pathlib import Path

detect = json.loads(Path('graphify-out/.graphify_detect.json').read_text())

# Get uncached files
uncached_list = Path('graphify-out/.graphify_uncached.txt').read_text().strip().split('\n')

# Get file types
docs = set(detect.get('files', {}).get('document', []))
papers = set(detect.get('files', {}).get('paper', []))
images = set(detect.get('files', {}).get('image', []))

# Separate by type
doc_files = [f for f in uncached_list if f in docs]
paper_files = [f for f in uncached_list if f in papers]
image_files = [f for f in uncached_list if f in images]

print(f'Preparing chunks...')
print(f'  Docs: {len(doc_files)}')
print(f'  Papers: {len(paper_files)}')
print(f'  Images: {len(image_files)}')

# Strategy: Group docs+papers (20 per chunk), images get their own chunks (1 per chunk for vision)
# This is a lot of images - ~546 images would be 546 chunks which is too many
# Better: 5-10 images per chunk max

chunks = []

# Chunk 1: All docs and papers
if doc_files or paper_files:
    chunks.append({
        'num': len(chunks) + 1,
        'files': doc_files + paper_files,
        'type': 'docs_papers'
    })

# Image chunks (10 images per chunk)
image_chunk_size = 10
for i in range(0, len(image_files), image_chunk_size):
    chunks.append({
        'num': len(chunks) + 1,
        'files': image_files[i:i+image_chunk_size],
        'type': 'images'
    })

print(f'\nTotal chunks: {len(chunks)}')
print(f'  1 chunk: docs + papers ({len(doc_files) + len(paper_files)} files)')
print(f'  {len(chunks)-1} chunks: images (~10 per chunk)')

# Save chunk info
Path('graphify-out/.graphify_chunks.json').write_text(json.dumps(chunks, indent=2))
