function showModel_ContextMenuOpening(obj, hContextMenu, openingData)
% SHOWMODEL_CONTEXTMENUOPENING - refresh the "Show model" context menu from the active dataset.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.showModel_ContextMenuOpening(hContextMenu, openingData)
%
% Input Arguments:
%   - **hContextMenu** - [matlab.ui.container.ContextMenu] the menu being opened
%   - **openingData** - [ContextMenuOpeningData] menu event data; unused
%
% Notes:
%   Reading the state as the menu opens rather than keeping it in step with listeners is what
%   makes it impossible to show stale: a buffer switch, a mode change or a model being closed
%   need no notification to reach it.
%
%   ``Render instances per object`` applies only to ``core.MibBigDataLabelsIndex``, the
%   read-only overlay served from a label pyramid the image does not share. The other BigData
%   label classes pack six bits of material into a byte, so their object ids did not survive
%   the load and there is nothing left to separate.
%

arguments (Input)
    obj controllers.MibSelection
    hContextMenu matlab.ui.container.ContextMenu
    openingData
end

labels = obj.mibModel.I{obj.mibModel.getActiveId()}.labels;
isOverlay = isa(labels, 'core.MibBigDataLabelsIndex') && labels.exists;

perObjectEntry = findobj(hContextMenu.Children, 'Tag', 'showModelContextPerObject');
perObjectEntry.Enable = matlab.lang.OnOffSwitchState(isOverlay);
perObjectEntry.Checked = matlab.lang.OnOffSwitchState(isOverlay && labels.renderPerObject);
end
