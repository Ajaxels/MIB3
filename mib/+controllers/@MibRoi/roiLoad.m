function roiLoad(obj)
% ROILOAD - Load ROIs from a .roi (MAT) file into the current dataset.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.roiLoad()
%
% Parameters: none
% Return values: none

% developer mode
if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibRoi.roiLoad: pressed\n');
end

dataset = obj.mibModel.I{obj.mibModel.id};

% determine starting directory from image filename or current directory
fn = dataset.image.filename;
if strcmp(fn, 'none.tif') || isempty(fn)
    startPath = obj.mibModel.currentDirectory;
else
    startPath = fileparts(fn);
end

[filename, path] = utils.dlgs.mibUiGetFile( ...
    {'*.roi', 'Area shape, MATLAB format (*.roi)'; ...
     '*.*',   'All Files (*.*)'}, ...
    'Open ROI shape file...', startPath);
if isequal(filename, 0); return; end
filename = filename{1};

res = load(fullfile(path, filename), '-mat');
% ZX ROIs are stored in the legacy MIB2 frame, see core.RoiRegion.swapZXAxes
dataset.hROI.Data = core.RoiRegion.swapZXAxes(res.Data);
dataset.hROI.convertLegacyTypes();  % convert MIB2 type names to MIB3

% enable ROI display
dataset.roiShow = true;
obj.handles.roiShowROI.Value = true;
obj.mibController.cQuickAccessBar.handles.roiMode.Value = true;

obj.refreshROIList([]);
dataset.selectedROI = 0;
obj.mibController.showImage();
fprintf('MIB: loading ROI from %s -> done!\n', fullfile(path, filename));
end
