import json
from graphify.detect import detect
from pathlib import Path

result = detect(Path('mib'))
with open('graphify-out/.graphify_detect.json', 'w') as f:
    json.dump(result, f)

total = result.get('total_files', 0)
words = result.get('total_words', 0)
print(f'Corpus: {total} files, {words} words')
for ftype, files in result.get('files', {}).items():
    if files:
        print(f'  {ftype}: {len(files)} files')
