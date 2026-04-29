# Documentation Block Template

Every new or ported function/method must include this block using Sphinx RST-compatible format:

```matlab
function result = myMethod(obj, param1, param2, BatchOptIn)
% MYMETHOD - One-line summary of what the method does.
%
% Syntax:
%   result = myMethod(obj, param1, param2, BatchOptIn)
%
% Longer description if needed — explain the algorithm, side-effects,
% or any non-obvious behaviour.
%
% Input Arguments:
%   - **param1** — [type] description
%     - .value1 - meaning
%     - .value2 - meaning
%   - **param2** — *(optional)* [type] description; default value and when it applies
%   - **BatchOptIn** — a structure for batch processing mode; when NaN, returns
%     default options via "SyncBatch" event
%     - .FieldName - [type, {choices}] description
%     - .showWaitbar - logical, show or not the waitbar
%     - .id - *(optional)* dataset index 1-9, default = obj.getActiveId()
%
% Output Arguments:
%   - **result** — [type] description; empty [] when cancelled or on error
%
% Usage:
%   Example 1 - Typical call::
%
%     result = obj.mibModel.myMethod(p1, p2);
%
%   Example 2 - Batch/scripted call::
%
%     BatchOpt.FieldName = 'value';
%     BatchOpt.showWaitbar = false;
%     obj.mibModel.myMethod(p1, p2, BatchOpt);
%
% See also:
%   relatedFunction1, relatedFunction2
```

## Rules

- First comment line uses `% FUNCNAME - One-line summary.` format (name in ALL CAPS).
- For methods/functions, include a `Syntax:` section with the function signature.
- `*(optional)*` marks optional parameters; always state the default.
- Sub-fields of struct parameters are indented as `  - .fieldName - description`.
- At least one `Usage:` example with `Example N - Title::` header and indented code block.
- BatchOpt-enabled methods: include a batch call example.
- `core.*` low-level methods: show call via `obj.mibModel.I{obj.mibModel.id}.method(...)`.
- `classdef` files: no `Syntax:` section; examples use `Example N::` (no title needed).
- Use `See also:` (not `@see`) for cross-references.
- No `Updates` section — version history goes in git log, not source code.
