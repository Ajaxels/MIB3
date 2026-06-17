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

import sys, os
from pathlib import Path
import subprocess

# Force UTF-8 output so checkmarks don't crash on Windows cp1252 terminals
os.environ.setdefault('PYTHONIOENCODING', 'utf-8')

PYTHON = sys.executable
ROOT = Path(__file__).parent.parent.parent  # C:\Matlab\MIB3

def run_step(script_name, description):
    script_path = ROOT / 'development' / 'graphify' / script_name
    print(f'\n=== {description} ===')
    print(f'Running: {script_path}')
    result = subprocess.run([PYTHON, str(script_path)], cwd=str(ROOT))
    if result.returncode != 0:
        print(f'ERROR: {script_name} failed with exit code {result.returncode}')
        sys.exit(1)
    print(f'OK: {description} complete')


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
    print('Graphify update complete!')
    print('='*60)
    print(f'Outputs: {ROOT}/graphify-out/')
    print('  - graph.html (open in browser)')
    print('  - GRAPH_REPORT.md (architecture insights)')
    print('  - graph.json (raw data)')


if __name__ == '__main__':
    main()
