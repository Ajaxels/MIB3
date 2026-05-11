import sys, json
from graphify.extract import collect_files, extract
from pathlib import Path

code_files = []
detect = json.loads(Path('graphify-out/.graphify_detect.json').read_text())
for f in detect.get('files', {}).get('code', []):
    code_files.extend(collect_files(Path(f)) if Path(f).is_dir() else [Path(f)])

print(f'Extracting AST from {len(code_files)} code files...')
result = extract(code_files)
Path('graphify-out/.graphify_ast.json').write_text(json.dumps(result, indent=2))
print(f'AST: {len(result.get("nodes", []))} nodes, {len(result.get("edges", []))} edges')
