# Building the API Documentation

MIB3 API reference is built with **Sphinx** + `sphinxcontrib-matlabdomain`.
This file covers environment setup, required library patches, and producing an
HTML build.

The same Miniforge/Zensical environment used for the user docs (see
[`docs/install.md`](../docs/install.md)) already contains all required packages
if you followed those steps.

---

## 1. Install Miniforge and create the environment

Follow **steps 1-3** in [`docs/install.md`](../docs/install.md).  The
`pip install sphinx sphinxcontrib-matlabdomain sphinx-rtd-theme sphinx-immaterial`
command in that guide installs everything needed here as well.

Tested package versions:

| Package | Version |
|---------|---------|
| Python | 3.12 |
| Sphinx | 9.0.4 |
| sphinxcontrib-matlabdomain | 0.22.1 |
| sphinx-immaterial | latest |

---

## 2. Apply required patches to sphinxcontrib-matlabdomain

Version 0.22.1 of `sphinxcontrib-matlabdomain` has three bugs that prevent
correct resolution of MATLAB `+package` modules.  Patched files are stored
under `docs_api/sphinx/` and must be copied over the installed library before
building.

**Library location** (adjust for your Python environment):

```
d:\Python\Miniforge3\envs\Zensical\Lib\site-packages\sphinxcontrib\
```

**Apply all patches at once** by copying the bundled files:

```
copy docs_api\sphinx\mat_types.py       <library_path>\mat_types.py
copy docs_api\sphinx\mat_documenters.py <library_path>\mat_documenters.py
```

### Patch 1 - `mat_types.py`: `+package` name-resolution fallback

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

### Patch 2 - `mat_documenters.py`: non-fatal analyzer failure for `+package` modules

**Problem 1:** `generate()` catches only `PycodeError`, but MATLAB module analysis
raises `MatcodeError` for `+package` modules.  The unhandled exception aborts
documentation of all members.

**Problem 2:** Sphinx 9.0.4 removed `app.debug()`, causing
`AttributeError: 'Sphinx' object has no attribute 'debug'`.

**Fix:** Add `MatcodeError` to the imports from `.mat_types`, catch both error
types, and use `logger.debug()` instead of `self.env.app.debug()`.

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

### Patch 3 - `mat_documenters.py`: null-guard in `get_object_members`

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

## 3. Build the HTML output

From `C:\Matlab\MIB3\docs_api\`:

```
d:\Python\Miniforge3\envs\Zensical\Scripts\sphinx-build.exe -b html source html
```

If `sphinx-build` is on `PATH`:

```
sphinx-build -b html source html
```

Open `html\index.html` in a browser to view the result.

---

## Project structure

```
docs_api/
  source/
    conf.py              - Sphinx config (MATLAB src path, theme, extensions)
    index.rst            - top-level navigation
    _static/
      custom.css         - MIB3 brand colours (#006633 green + #F28C38 orange)
    api/                 - RST pages, one per package and class
  html/                  - generated HTML output
  sphinx/
    mat_types.py         - patched copy (Patch 1 applied)
    mat_documenters.py   - patched copy (Patches 2 and 3 applied)
  install.md             - this file
  README.md              - overview and patch details
```

---

## Docstring format

All MATLAB docblocks use RST format compatible with `sphinxcontrib-matlabdomain`.
See [`development/guides/docs_api_sphinx.md`](../development/guides/docs_api_sphinx.md) for the
complete style guide and canonical examples.
