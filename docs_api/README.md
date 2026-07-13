# MIB3 API Documentation

Sphinx-based API documentation for the MIB3 MATLAB project.
Generated HTML output lives in `docs_api/build/html/`.

---

## Prerequisites

Python 3.11+ with the following packages (tested in the `mkdocs` Mambaforge environment):

```
pip install sphinx sphinxcontrib-matlabdomain sphinx-rtd-theme
pip install sphinx-immaterial
```

Exact versions used:

| Package | Version |
|---------|---------|
| Sphinx | 9.0.4 |
| sphinxcontrib-matlabdomain | 0.22.1 |
| sphinx-immaterial | latest |
| Python | 3.11.13 |

---

## Building

From `C:\Matlab\MIB3\docs_api\`:

```
d:\Python\Mambaforge\envs\mkdocs\Scripts\sphinx-build.exe -b html source build\html
```

Or if `sphinx-build` is on `PATH`:

```
sphinx-build -b html source build\html
```

Open `build\html\index.html` in a browser to view the result.

---

## Required patches to sphinxcontrib-matlabdomain 0.22.1

Version 0.22.1 of `sphinxcontrib-matlabdomain` has three bugs that prevent correct
resolution of MATLAB `+package` modules.  The patched files are saved under
`docs_api/sphinx/` and must be applied to the installed library before building.

**Library location** (adjust for your Python environment):

```
d:\Python\Mambaforge\envs\mkdocs\Lib\site-packages\sphinxcontrib\
```

**To apply all patches at once**, copy the bundled files over the installed ones:

```
copy docs_api\sphinx\mat_types.py      <library_path>\mat_types.py
copy docs_api\sphinx\mat_documenters.py <library_path>\mat_documenters.py
```

---

### Patch 1 — `mat_types.py`: `+package` name-resolution fallback

**Problem:** MATLAB `+package` directories are stored in `entities_table` with a
leading `+` key (e.g. `+controllers`), but RST directives reference the bare name
(e.g. `controllers`).  The direct lookup always misses, so all modules fail to
resolve.

**Fix:** In `try_get_module_entity_or_default`, add a fallback through
`entities_name_map` when the direct lookup returns `None`.

Replace:

```python
def try_get_module_entity_or_default(entity_name):
    maybe_mod = entities_table.get(entity_name)
    if isinstance(maybe_mod, dict):
        return maybe_mod["mod"]
    return maybe_mod
```

With:

```python
def try_get_module_entity_or_default(entity_name):
    maybe_mod = entities_table.get(entity_name)
    if maybe_mod is None:
        # Fall back via name_map: handles MATLAB +package folders whose
        # entities_table key has the leading '+' (e.g. '+controllers') but
        # RST directives use the bare name (e.g. 'controllers').
        mapped_name = entities_name_map.get(entity_name)
        if mapped_name:
            maybe_mod = entities_table.get(mapped_name)
    if isinstance(maybe_mod, dict):
        return maybe_mod["mod"]
    return maybe_mod
```

---

### Patch 2 — `mat_documenters.py`: Non-fatal analyzer failure for `+package` modules

**Problem 1:** `generate()` catches only `PycodeError`, but MATLAB module analysis
raises `MatcodeError` for `+package` modules.  The unhandled exception aborts
documentation of all members.

**Problem 2:** Sphinx 9.0.4 removed `app.debug()`, causing
`AttributeError: 'Sphinx' object has no attribute 'debug'`.

**Fix:** Add `MatcodeError` to the imports from `.mat_types`, catch both error types,
and use `logger.debug()` instead of `self.env.app.debug()`.

At the top of `mat_documenters.py`, the `from .mat_types import (...)` block must
include `MatcodeError` and `entities_name_map`:

```python
from .mat_types import (
    MatModule, MatObject, MatFunction, MatClass, MatProperty,
    MatMethod, MatScript, MatException, MatModuleAnalyzer,
    MatApplication, MatcodeError, entities_table, entities_name_map,
    strip_package_prefix, try_get_module_entity_or_default,
)
```

In the `generate()` method (around line 774), change:

```python
        except PycodeError as err:
            self.env.app.debug(...)
            self.analyzer = None
```

To:

```python
        except (PycodeError, MatcodeError) as err:
            logger.debug(
                "[sphinxcontrib-matlabdomain] module analyzer failed: %s", err
            )
            self.analyzer = None
```

---

### Patch 3 — `mat_documenters.py`: Null-guard in `get_object_members`

**Problem:** When a module fails to load, `self.object` is `None`, causing
`AttributeError: 'NoneType' object has no attribute 'safe_getmembers'` for every
function in the module.

**Fix:** Add an early `None` check at the top of `MatModuleDocumenter.get_object_members`:

```python
def get_object_members(self, want_all):
    if self.object is None:
        logger.warning(
            "[sphinxcontrib-matlabdomain] Module %s could not be loaded "
            "(object is None), skipping members.",
            self.fullname,
        )
        return False, []
    # ... rest of original method unchanged
```

---

## Project structure

```
docs_api/
  source/
    conf.py              — Sphinx config (MATLAB src path, theme, extensions)
    index.rst            — Top-level navigation
    _static/
      custom.css         — MIB3 brand colours (#006633 green + #F28C38 orange)
    api/                 — RST pages, one per package and class
  build/
    html/                — Generated HTML output (excluded from git)
  sphinx/
    mat_types.py         — Patched copy (Patch 1 applied)
    mat_documenters.py   — Patched copy (Patches 2 and 3 applied)
  README.md              — This file
```

---

## Docstring format

All MATLAB docblocks use RST format compatible with `sphinxcontrib-matlabdomain`.
See [`development/guides/docs_api_sphinx.md`](../development/guides/docs_api_sphinx.md) for the
complete style guide and canonical examples.
