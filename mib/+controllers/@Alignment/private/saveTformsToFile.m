function saveTformsToFile(obj, id, useBatchMode, parentFig, label)
% SAVETFORMSTOFILE - Persist alignment transforms to a .coefXY file.
%
% Syntax:
%   .. code-block:: matlab
%
%      saveTformsToFile(obj, id, useBatchMode, parentFig)
%      saveTformsToFile(obj, id, useBatchMode, parentFig, label)
%
% Private helper for the alignment algorithms. Saves the contents of
% ``obj.shiftsX`` (as ``tformMatrix``) and ``obj.shiftsY`` (as
% ``rbMatrix``) to a ``.coefXY`` file so the user can replay the
% alignment via :meth:`loadShiftsCheck_Callback`. In **batch mode** the
% file path is auto-derived from the dataset filename; in **GUI mode**
% the path is read from ``obj.view.handles.saveShiftsXYpath.Value``.
%
% Input Arguments:
%   - **label** *(optional)* - [char] human-readable algorithm name
%     prefixed onto the progress message (default ``'alignment'``).

% Updates
%

if nargin < 5; label = 'alignment'; end

if useBatchMode
    fn = obj.mibModel.I{id}.image.sliceName('Filename');
    [pathstr, name, ~] = fileparts(fn);
    fullPath = fullfile(pathstr, [name '_align.coefXY']);
elseif ~isempty(obj.view) && isvalid(obj.view) && isfield(obj.view.handles, 'saveShiftsXYpath')
    fullPath = obj.view.handles.saveShiftsXYpath.Value;
else
    return;
end
tformMatrix = obj.shiftsX;
rbMatrix    = obj.shiftsY;
fprintf('Saving %s transforms to file: %s ... ', label, fullPath);
try
    save(fullPath, 'tformMatrix', 'rbMatrix');
    fprintf('done!\n');
catch ME
    fprintf('failed.\n');
    utils.dlgs.showErrorDialog(parentFig, ME, 'Save shifts');
end
end
