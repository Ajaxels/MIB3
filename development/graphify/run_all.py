#!/usr/bin/env python3
"""
Complete graphify pipeline for MIB3.
Runs all steps in the correct order:
  1. detect_graph.py     — scan mib/ folder
  2. build_ast.py        — extract AST from code
  3. matlab_edges.py     — inject MATLAB-specific edges
  4. cluster_graph.py    — cluster into communities
  5. gen_html.py         — generate HTML visualization

Run from repository root:
    python development/graphify/run_all.py
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
    print(f'\n{"="*60}')
    print(f'{description}')
    print(f'{"="*60}')
    print(f'Running: {script_path}')
    result = subprocess.run([PYTHON, str(script_path)], cwd=str(ROOT))
    if result.returncode != 0:
        print(f'\n❌ ERROR: {script_name} failed with exit code {result.returncode}')
        sys.exit(1)
    print(f'✓ {description} complete')


def main():
    print('\n' + '='*60)
    print('MIB3 Graphify Pipeline')
    print('='*60)
    print(f'Python: {PYTHON}')
    print(f'Root: {ROOT}')

    steps = [
        ('detect_graph.py', 'Step 1: Detect files in mib/'),
        ('build_ast.py', 'Step 2: Extract AST from code files'),
        ('matlab_edges.py', 'Step 3: Inject MATLAB-specific edges'),
        ('cluster_graph.py', 'Step 4: Cluster graph and generate report'),
        ('gen_html.py', 'Step 5: Generate HTML visualization'),
    ]

    for script, desc in steps:
        run_step(script, desc)

    print('\n' + '='*60)
    print('✓ Graphify update complete!')
    print('='*60)
    print(f'\nOutputs in: {ROOT}/graphify-out/')
    print('  📊 graph.html         — open in browser')
    print('  📋 GRAPH_REPORT.md    — architecture insights')
    print('  📦 graph.json         — raw graph data')
    print('\nNext: open graph.html or read GRAPH_REPORT.md')
    print()


if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        print('\n\n⚠️  Interrupted by user')
        sys.exit(130)
    except Exception as e:
        print(f'\n❌ Fatal error: {e}')
        sys.exit(1)
