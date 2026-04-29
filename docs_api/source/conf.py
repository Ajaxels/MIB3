import os

# ── Project info ────────────────────────────────────────────────────────────
project = 'MIB3'
copyright = '2026, Ilya Belevich'
author = 'Ilya Belevich'
release = '2026.04'

# ── Extensions ──────────────────────────────────────────────────────────────
extensions = [
    'sphinxcontrib.matlab',   # MATLAB autodoc support
    'sphinx.ext.autodoc',     # autodoc engine (required by matlabdomain)
    'sphinx.ext.viewcode',    # adds [source] links to functions
    'sphinx.ext.napoleon',    # enables Google/NumPy style docstrings (optional)
    'sphinx_immaterial',      # Material Design theme
]

# ── MATLAB source path ───────────────────────────────────────────────────────
# Point to the ROOT of your .m files (absolute path recommended).
# All subfolders and +packages are picked up automatically.
# Use __file__ to anchor the path to conf.py's location — this is reliable
# regardless of which directory sphinx is invoked from.
matlab_src_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), '../../mib'))

# Make MATLAB the default domain — so you don't need to prefix
# every directive with "mat:" in your .rst files.
primary_domain = 'mat'

# ── Theme ────────────────────────────────────────────────────────────────────
html_theme = 'sphinx_immaterial'

html_theme_options = {
    'repo_url': 'https://github.com/Ajaxels/MIB3',  # optional, shows GitHub link
    'repo_name': 'MIB3',
    'palette': {
        'primary': 'green',
        'accent':  'orange',
    },
    'features': [
        'navigation.expand',
        'navigation.top',
        'search.highlight',
    ],
}

# ── General ──────────────────────────────────────────────────────────────────
exclude_patterns  = ['_build']
templates_path    = ['_templates']
html_static_path  = ['_static']
html_css_files    = ['custom.css']

# Show full module path in function signatures (e.g. +pkg.MyClass.myMethod)
add_module_names = True

# ── Optional: autodoc defaults ───────────────────────────────────────────────
autodoc_default_options = {
    'members':          True,   # document all public members automatically
    'undoc-members':    False,  # skip members with no docstring
    'show-inheritance': True,
}