function createContextMenus(obj)
% CREATECONTEXTMENUS - Build the right-click context menu for statTable programmatically.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.createContextMenus()
%
% Creates a uicontextmenu attached to obj.view.gui and assigns it to
% the statTable widget.  Items cover: selection actions (New/Add/Remove),
% clipboard copy, annotations (New/Add/Remove), statistics aggregates
% (Mean/Sum/Min/Max), crop to file/MATLAB, object-to-model conversion,
% and histogram plotting.
%
% Usage:
%   Example 1::
%
%     obj.createContextMenus();  // called once from addCallbacks
%

% Updates
%

cm = uicontextmenu(obj.view.gui);

% Selection actions
uimenu(cm, 'Label', 'New selection',         'MenuSelectedFcn', @(~,~) obj.statTable_CellSelectionCallback([], 'Replace'));
uimenu(cm, 'Label', 'Add to selection',      'MenuSelectedFcn', @(~,~) obj.statTable_CellSelectionCallback([], 'Add'));
uimenu(cm, 'Label', 'Remove from selection', 'MenuSelectedFcn', @(~,~) obj.statTable_CellSelectionCallback([], 'Remove'));

uimenu(cm, 'Label', 'Copy column(s) to clipboard', 'Separator', 'on', ...
    'MenuSelectedFcn', @(~,~) obj.tableContextMenu_cb('copyColumn'));

% Annotations
uimenu(cm, 'Label', 'New annotations',       'Separator', 'on', 'MenuSelectedFcn', @(~,~) obj.tableContextMenu_cb('newLabel'));
uimenu(cm, 'Label', 'Add annotations',        'MenuSelectedFcn', @(~,~) obj.tableContextMenu_cb('addLabel'));
uimenu(cm, 'Label', 'Remove annotations',     'MenuSelectedFcn', @(~,~) obj.tableContextMenu_cb('removeLabel'));

% Statistics operations
uimenu(cm, 'Label', 'Calculate Mean',  'Separator', 'on', 'MenuSelectedFcn', @(~,~) obj.tableContextMenu_cb('mean'));
uimenu(cm, 'Label', 'Calculate Sum',   'MenuSelectedFcn', @(~,~) obj.tableContextMenu_cb('sum'));
uimenu(cm, 'Label', 'Calculate Min',   'MenuSelectedFcn', @(~,~) obj.tableContextMenu_cb('min'));
uimenu(cm, 'Label', 'Calculate Max',   'MenuSelectedFcn', @(~,~) obj.tableContextMenu_cb('max'));

% Crop & model
uimenu(cm, 'Label', 'Crop to file/MATLAB...', 'Separator', 'on', 'MenuSelectedFcn', @(~,~) obj.tableContextMenu_cb('crop'));
uimenu(cm, 'Label', 'Objects to a new model', 'MenuSelectedFcn', @(~,~) obj.statTable_CellSelectionCallback([], 'obj2model'));

% Histogram
uimenu(cm, 'Label', 'Plot histogram', 'Separator', 'on', 'MenuSelectedFcn', @(~,~) obj.tableContextMenu_cb('hist'));

obj.view.handles.statTable.ContextMenu = cm;
end
