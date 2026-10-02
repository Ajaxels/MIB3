# API Reference

The **API class reference** documents the MATLAB classes, methods, and properties that make up
Microscopy Image Browser. It is the starting point when writing plugins, scripting MIB, or
extending its functionality.

[Open the MIB API reference :octicons-link-16:](http://mib.helsinki.fi/help/api3/index.html)

!!! note
    The online API reference for MIB3 is being prepared and may not be available yet.

You can also open it from within MIB: **Ribbon → Home → Help → Class Reference**.

## Installation

The API reference is generated from the MATLAB docblocks with **Sphinx** and
`sphinxcontrib-matlabdomain`. It uses the same Python environment as the user documentation.

### 1. Create the environment

Follow steps 1-3 of the [Zensical installation](markdown.md#installation), including the optional
Sphinx packages:

```
pip install sphinx sphinxcontrib-matlabdomain sphinx-rtd-theme sphinx-immaterial
```

Tested versions: Python 3.12, Sphinx 9.0.4, sphinxcontrib-matlabdomain 0.22.1.

### 2. Patch sphinxcontrib-matlabdomain

Version 0.22.1 of `sphinxcontrib-matlabdomain` does not resolve MATLAB `+package` folders and fails
with Sphinx 9. Patched files are stored in `docs_api/sphinx/`; copy them over the installed library
from the MIB project folder, replacing the path with the location of your environment:

```
copy docs_api\sphinx\mat_types.py       d:\Python\Miniforge3\envs\Zensical\Lib\site-packages\sphinxcontrib\mat_types.py
copy docs_api\sphinx\mat_documenters.py d:\Python\Miniforge3\envs\Zensical\Lib\site-packages\sphinxcontrib\mat_documenters.py
```

Repeat this step after every reinstall or upgrade of `sphinxcontrib-matlabdomain`.

### 3. Generate the API reference

Run the command from the `docs_api` subfolder of the MIB project:

```
d:\Python\Miniforge3\envs\Zensical\Scripts\sphinx-build.exe -b html source html
```

Open `docs_api/html/index.html` in a browser to view the result.

!!! note

    Do not edit files in `docs_api/html/`, they are overwritten on every build.

---

*Back to [MIB](index.md)*
