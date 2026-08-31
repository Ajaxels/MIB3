function rebuildIndex(obj)
% REBUILDINDEX - Rebuild the per-object index of the active instance model.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.rebuildIndex()
%
% The one genuinely whole-volume operation in the tool, so it is the one that
% gets a cancelable progress dialog. Everything else works inside a bounding box
% and is fast enough that a progress bar would be the slowest part of it.
%
% Input Arguments:
%   (none)
%
% Output Arguments:
%   (none)

% Updates
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.InstanceEditor.rebuildIndex: triggered\n');
end

if ~obj.modelIsEditable(); return; end

dataset = obj.mibModel.I{obj.mibModel.getActiveId()};
wb = uiprogressdlg(obj.view.gui, 'Indeterminate', 'on', 'Cancelable', 'on', ...
    'Message', 'Indexing the objects of the model, please wait...', ...
    'Title', 'Instance editor');

[~, cancelled] = dataset.buildInstanceIndex( ...
    struct('timePoint', dataset.getCurrentTimePoint()), wb);
delete(wb);

if cancelled
    % The previous index is left in place by buildInstanceIndex, but it is the
    % stale one that prompted the rebuild - say so rather than looking done.
    obj.updateStatusLine();
    return;
end

obj.updateWidgets();
end
