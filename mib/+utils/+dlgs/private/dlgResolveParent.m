function parent = dlgResolveParent(ParentFigure, optParent)
% DLGRESOLVEPARENT - Resolve the parent window used for dialog centering.
%
% Syntax:
%   .. code-block:: matlab
%
%      parent = dlgResolveParent(ParentFigure, optParent)
%
% Priority: ``ParentFigure`` parameter > ``options.ParentFigure`` > cached handle
% from a prior call. A valid handle from either source refreshes the cache, so
% later calls may pass ``[]`` and still center on the main GUI window.
% Uses ``isvalid()`` not ``ishandle()`` — AppContainer satisfies ``isvalid`` but
% not ``ishandle``.
%
% Input Arguments:
%   - **ParentFigure** — [handle] dialog's first parameter (AppContainer, uifigure, or ``[]``)
%   - **optParent** — [handle] value of ``options.ParentFigure``, or ``[]``
%
% Output Arguments:
%   - **parent** — [handle] resolved parent window; ``[]`` when none is available

persistent cachedParent   % cached handle to the main GUI window

parent = [];
if ~isempty(ParentFigure) && isvalid(ParentFigure)
    parent = ParentFigure;
    cachedParent = ParentFigure;
elseif ~isempty(optParent) && isvalid(optParent)
    parent = optParent;
    cachedParent = optParent;
elseif ~isempty(cachedParent) && isvalid(cachedParent)
    parent = cachedParent;
end
end
