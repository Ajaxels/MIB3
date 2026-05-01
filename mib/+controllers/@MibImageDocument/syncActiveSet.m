function changed = syncActiveSet(obj)
% SYNCACTIVESET - Lightweight sync of mibModel's active set to this document's setOfDatasetsIndex.
%
% Syntax:
%   .. code-block:: matlab
%
%      changed = obj.syncActiveSet()
%
% In split-panel mode the model keeps a single "active set" (``Sets.selectedSet`` +
% ``mibModel.id``), but multiple MibImageDocument panels are simultaneously visible
% and can receive callbacks (scroll, motion). This function ensures the model
% reflects the set that owns the currently-active document before any
% data access via ``obj.mibModel.id`` or ``obj.mibModel.I{...}``.
%
% **Important note:** This method updates model fields ONLY (no events, no ``ShowImage``).
% Callers that need full UI refresh (dropdown, buffer buttons, re-render)
% should call the ``setsOps_Callbacks`` path instead; see ``gui_WindowButtonDownFcn``.
%
% Input Arguments:
%   (none)
%
% Output Arguments:
%   - **changed** — [logical] ``true`` if the active set was actually changed
%
% **Example** — sync at start of frequent callback (mouse motion, scroll):
%
%   .. code-block:: matlab
%
%      obj.syncActiveSet();
%      dataset = obj.mibModel.I{obj.mibModel.id};
%

changed = (obj.mibModel.Sets.selectedSet ~= obj.setOfDatasetsIndex);
if changed
    obj.mibModel.Sets.selectedSet = obj.setOfDatasetsIndex;
    obj.mibModel.id = obj.mibModel.Sets.selectedDataset(obj.setOfDatasetsIndex) + ...
        (obj.setOfDatasetsIndex - 1) * obj.mibModel.Sets.datasetsInSet;
end
end
