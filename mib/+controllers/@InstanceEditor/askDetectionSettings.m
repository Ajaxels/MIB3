function askDetectionSettings(obj)
% ASKDETECTIONSETTINGS - Ask how the object list is drawn and what counts as one piece.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.askDetectionSettings()
%
% Four settings that are chosen once and then left alone for a whole
% proofreading run - the length of the list, the two size filters that hunt the
% noise down in it, and the connectivity the split operations count pieces with.
% They were four permanent widgets; the window is mostly a list, and the room
% they took is worth more to the list than to them.
%
% The row cap and the two filters are ``obj.listOptions``, which only
% ``updateObjectTable`` reads - they change what is drawn, never what is edited,
% and are not sent to the model. The connectivity is a real operation setting
% and stays in ``obj.BatchOpt``, where ``SplitComponents`` and
% ``SplitBySelection`` pick it up.
%
% All four are kept in ``MibModel.sessionSettings.instanceEditor`` and read back
% by the constructor, so a reopened editor lists what the last one listed.
%
% The mode decides how many questions there are: a slice count is not a property
% of a row in 2D mode, so the slice filter is left out there rather than shown
% and ignored, and the connectivity offers 26/6 or 8/4 accordingly.
%
% Input Arguments:
%   (none)
%
% Output Arguments:
%   (none)
%
% See also: controllers.InstanceEditor.updateObjectTable,
% controllers.InstanceEditor.askCleanupSettings

% Updates
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.InstanceEditor.askDetectionSettings: triggered\n');
end

use3D = logical(obj.view.handles.Mode3D.Value);
if use3D
    sizeUnits = 'voxels';
else
    sizeUnits = 'pixels on the shown slice';
end

prompts = {...
    sprintf(['Max rows:\n  longest list that is drawn. Picked objects are shown\n' ...
             '  whatever this says, so a selection cannot hide behind it']), ...
    sprintf(['Max size (%s):\n  list only objects this size or smaller; 0 = no filter.\n' ...
             '  This is how the noise is found - sort by size and work up'], sizeUnits)};

defAns = {...
    struct('Spinner', true, 'Value', obj.listOptions.MaxRows, 'Limits', [10, 1e5], ...
        'Step', 100, 'Round', true), ...
    struct('Spinner', true, 'Value', obj.listOptions.MaxVoxels, 'Limits', [0, 1e9], ...
        'Step', 10, 'Round', true)};

if use3D
    prompts{end+1} = sprintf(['Max slices:\n  list only objects spanning this many slices or fewer;\n' ...
        '  0 = no filter. Catches the wide false detection that a\n  size filter cannot see']);
    defAns{end+1} = struct('Spinner', true, 'Value', obj.listOptions.MaxSlices, ...
        'Limits', [0, 1e6], 'Step', 1, 'Round', true);
end

items = obj.BatchOpt.Connectivity{2};
selected = find(strcmp(items, obj.BatchOpt.Connectivity{1}));
if isempty(selected); selected = 1; end
prompts{end+1} = sprintf(['Connectivity:\n  neighbourhood that decides what is one connected piece,\n' ...
    '  used by the two split operations. The smaller value keeps\n' ...
    '  pieces apart that touch only at a corner or an edge']);
defAns{end+1} = [items, {selected}];

dlgParams.WindowWidth = 620;
% One row taller in 3D mode, where the slice filter is also asked for
if use3D; dlgParams.WindowHeight = 380; else; dlgParams.WindowHeight = 310; end
dlgParams.HeaderLines = 2;
dlgParams.LabelPosition = 'left';
dlgParams.mibPath = obj.mibModel.mibPath;

note = sprintf(['How the object list is drawn, and what counts as one connected piece.\n' ...
    'Nothing in the model is changed.']);
answer = utils.dlgs.inputUniversalDlg(obj.view.gui, note, prompts, defAns, ...
    'Detection settings', dlgParams);
if isempty(answer); return; end

obj.listOptions.MaxRows = answer{1};
obj.listOptions.MaxVoxels = answer{2};
if use3D; obj.listOptions.MaxSlices = answer{3}; end
obj.BatchOpt.Connectivity{1} = answer{end};

obj.mibModel.sessionSettings.instanceEditor.MaxRows = obj.listOptions.MaxRows;
obj.mibModel.sessionSettings.instanceEditor.MaxVoxels = obj.listOptions.MaxVoxels;
obj.mibModel.sessionSettings.instanceEditor.MaxSlices = obj.listOptions.MaxSlices;
obj.mibModel.sessionSettings.instanceEditor.Connectivity = obj.BatchOpt.Connectivity{1};

% Only the list is affected, and only by the three above - but repainting it is
% cheap next to the dialog the user has just closed, and a filter that appears
% to do nothing until the next click is worse.
obj.updateObjectTable();
end
