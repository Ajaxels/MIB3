# Sphinx API Documentation Guide

RST-based API reference for MIB3 MATLAB classes. Built with **Sphinx** +
`sphinxcontrib-matlabdomain`.

For build instructions, prerequisites, required library patches, and project
structure see [`README.md`](README.md) in this directory.

For the complete RST docblock style guide see
[`development/docs_api_sphinx.md`](../development/docs_api_sphinx.md).

---

## When to update API docs alongside code changes

- **New public method** — add an RST entry in the appropriate `source/api/` file.
- **New class** — create `source/api/<package>/<ClassName>.rst` and add it to the
  `toctree` in `source/api/<package>/index.rst`.
- **New package** — create `source/api/<package>/index.rst`, add `.. automodule::`,
  and register the package in `source/index.rst`.
- **Renamed / removed method** — update or remove the corresponding RST directive
  and fix any cross-references (``:func:``, ``:meth:``, ``:class:``).

---

## Docblock rules (quick reference)

```matlab
% METHODNAME - One-line description.
%
% Syntax:
%   .. code-block:: matlab
%
%      result = obj.methodName(param1, param2)
%
% Description:
%   Full description of what the method does.
%
% Parameters:
%   **param1** — description of param1.
%   **param2** *(optional)* — description of param2, default ``'value'``.
%
% Return values:
%   **result** — description of the return value.
%
% Example 1 — basic usage:
%   .. code-block:: matlab
%
%      result = obj.methodName(1, 'option');
```

Rules:
- Header: `% METHODNAME - One-line description.` — all-caps name, no function call
- Use `.. code-block:: matlab` (never bare `::`)
- Parameter names in `**bold**` with em-dash `—` separator
- Optional params: `*(optional)*` after the bold name
- Defaults and inline code: double backticks `` ``value`` ``
- Struct fields: nested RST bullets with `` `.fieldName` `` — description
- No Doxygen tags (`@b`, `@li`, `[@em ...]`, `@Note:`) — use RST equivalents
