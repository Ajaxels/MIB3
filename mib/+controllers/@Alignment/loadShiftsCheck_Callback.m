function loadShiftsCheck_Callback(obj)
% LOADSHIFTSCHECK_CALLBACK - Load pre-computed shifts from a ``.coefXY`` file.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.loadShiftsCheck_Callback()
%
% When the ``loadShiftsCheck`` checkbox is enabled the user is prompted for a
% ``.coefXY`` file. The file may contain ``shiftsX`` / ``shiftsY`` (drift
% correction), ``tformMatrix`` / ``rbMatrix`` (legacy feature-based), or a
% feature-based v2 parameter struct. Disabling the checkbox clears the path.

h = obj.view.handles;
if ~h.loadShiftsCheck.Value
    h.loadShiftsXYpath.Enable = 'off';
    return;
end

startingPath = h.loadShiftsXYpath.Value;
[fileName, pathName] = utils.dlgs.mibUiGetFile( ...
    {'*.coefXY', 'MIB shift files (*.coefXY)'; '*.*', 'All Files (*.*)'}, ...
    'Select file with shifts...', startingPath);
if fileName == 0
    h.loadShiftsCheck.Value = false;
    return;
end

fullPath = fullfile(pathName, fileName{1});
h.loadShiftsXYpath.Value  = fullPath;
h.loadShiftsXYpath.Enable = 'on';

try
    loaded = load(fullPath, '-mat');
catch ME
    utils.dlgs.showErrorDialog(obj.view.gui, ME, 'Failed to load shifts');
    h.loadShiftsCheck.Value = false;
    h.loadShiftsXYpath.Enable = 'off';
    return;
end

if isfield(loaded, 'shiftsX')
    obj.shiftsX = loaded.shiftsX;
    obj.shiftsY = loaded.shiftsY;
elseif isfield(loaded, 'tformMatrix')
    obj.shiftsX = loaded.tformMatrix;
    obj.shiftsY = loaded.rbMatrix;
else
    % Load parameters for the updated Automatic
    % Feature-based registration
    %
    % These fields will be assigned to obj.shiftsX
    % .pairwiseTforms: {51×1 cell}
    % .cumulativeTforms: {51×1 cell}
    % .translations: [51×2 double]
    % .rotations: [51×1 double]
    % .scales: [51×1 double]
    % .affine_params: [51×4 double]
    % .rbMatrix: {51×1 cell}

    obj.shiftsX = loaded;
    obj.shiftsY = [];
end

end
