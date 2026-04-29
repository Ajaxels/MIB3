function roiSave(obj)
% ROISAVE - Save ROIs of the current dataset to a .roi (MAT) file.
%
% Syntax:
%   function roiSave(obj)
%
% Parameters: none
% Return values: none

% developer mode
if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibRoi.roiSave: pressed\n');
end

dataset = obj.mibModel.I{obj.mibModel.id};

if dataset.hROI.getNumberOfROI(0) < 1
    dlgTitle = 'No ROI present!';
    dlgOptions.mibPath = obj.mibModel.mibPath;
    dlgOptions.MsgBoxOnly = true;
    header = 'Create a Region of Interest first!';
    dlgOptions.Icon = 'puffin_warning';
    utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, dlgTitle, dlgOptions);
    return;
end

% build default output filename from image filename (strip extension)
fn = dataset.image.filename;
if strcmp(fn, 'none.tif') || isempty(fn)
    fn_out = obj.mibModel.currentDirectory;
else
    [fPath, fName] = fileparts(fn);
    fn_out = fullfile(fPath, fName);
end

[filename, path] = uiputfile( ...
    {'*.roi', 'Area shape, MATLAB format (*.roi)'; ...
     '*.*',   'All Files (*.*)'}, ...
    'Save ROI data...', fn_out);
if isequal(filename, 0); return; end

fn_out = fullfile(path, filename);
Data = dataset.hROI.Data; %#ok<NASGU>
save(fn_out, 'Data', '-mat', '-v7.3');

% show dialog
dlgTitle = 'ROI Save';
dlgOptions.mibPath = obj.mibModel.mibPath;
dlgOptions.MsgBoxOnly = true;
header = 'The ROI(s) was saved to a file!';
dlgOptions.Icon = 'puffin_info';
dlgOptions.WindowWidth = 500;
utils.dlgs.inputUniversalDlg(obj.view.gui, header, {fn_out}, {fn_out}, dlgTitle, dlgOptions);

fprintf('MIB: saving ROI to %s -> done!\n', fn_out);
end
