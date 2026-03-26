# Documentation Block Template

Every new or ported function/method must include this block:

```matlab
function result = myMethod(obj, param1, param2, BatchOptIn)
% function result = myMethod(obj, param1, param2, BatchOptIn)
% One-line summary of what the method does.
%
% Longer description if needed — explain the algorithm, side-effects,
% or any non-obvious behaviour.
%
% Parameters:
% param1: [type] description
%   @li value1 - meaning
%   @li value2 - meaning
% param2: [@em optional] [type] description; default value and when it applies
% BatchOptIn: a structure for batch processing mode; when NaN, returns
%   default options via "SyncBatch" event
%   @li .FieldName - [type, {choices}] description
%   @li .showWaitbar - logical, show or not the waitbar
%   @li .id -> [@em optional], dataset index 1-9, default = obj.getActiveId()
%
% Return values:
% result: [type] description; empty [] when cancelled or on error
%

%|
% @b Examples:
% @code result = obj.mibModel.myMethod(p1, p2);  // typical call @endcode
% @code
% BatchOpt.FieldName = 'value';
% BatchOpt.showWaitbar = false;
% obj.mibModel.myMethod(p1, p2, BatchOpt);       // batch / scripted call
% @endcode

% Updates
% DD.MM.YYYY - description of a significant change
```

## Rules

- First comment line **repeats the function signature** exactly.
- `[@em optional]` marks optional parameters; always state the default.
- `@li` for enumerated values or struct fields.
- At least one `@b Examples:` `@code ... @endcode` with a realistic call.
- BatchOpt-enabled methods: include a batch call example.
- `core.*` low-level methods: show call via `obj.mibModel.I{obj.mibModel.id}.method(...)`.
