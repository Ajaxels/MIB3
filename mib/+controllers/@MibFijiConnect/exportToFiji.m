function exportToFiji(obj)
% EXPORTTOFIJI - Export the currently open dataset to Fiji/ImageJ.
%
% Exports the selected dataset type (image, labels, mask, or selection) to a
% running Fiji/ImageJ instance via MIJ. Fiji is started automatically if it is
% not already running.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.exportToFiji()
%
% Updates
%

id = obj.mibModel.getActiveId();
datasetType = obj.handles.imageType.Value;   % 'image' | 'labels' | 'mask' | 'selection'

% virtual stacking mode does not support layer exports other than image
if strcmp(obj.mibModel.I{id}.datasetType, 'Virtual')
    if ismember(datasetType, {'labels', 'mask', 'selection'})
        dlgOpt.MsgBoxOnly = true;
        dlgOpt.Icon = 'puffin_warning';
        dlgOpt.HeaderLines = 3;
        utils.dlgs.inputUniversalDlg(obj.mibModel.mibGUI, ...
            sprintf('It is not yet possible to export "%s" in the virtual stacking mode!\nPlease switch to the memory-resident mode and try again.', datasetType), ...
            {}, {}, 'Not implemented', dlgOpt);
        return;
    end
end

% ensure Fiji/MIJ is running
if exist('MIJ', 'class') == 8
    if ~isempty(ij.gui.Toolbar.getInstance)
        ijInstance = char(ij.gui.Toolbar.getInstance.toString);
        if contains(ijInstance, 'invalid')  % instance exists but window was closed
            utils.fiji.Miji_wrapper(true);
        end
    else
        utils.fiji.Miji_wrapper(true);
    end
else
    utils.fiji.Miji_wrapper(true);
end

filename = obj.mibModel.I{id}.image.filename;
[~, baseFilename] = fileparts(filename);

roiNo = obj.mibModel.I{id}.selectedROI;
if ~obj.mibModel.I{id}.roiShow
    roiNo = -1;  % ROI overlay is off; ignore stale selectedROI and use full dataset
end
% roiNo == 0  → "All ROIs" mode (multiple patches)
% numel > 1   → several specific ROIs selected
if obj.mibModel.I{id}.roiShow && (roiNo == 0 && obj.mibModel.I{id}.hROI.getNumberOfROI() > 1)
    dlgOpt.MsgBoxOnly = true;
    dlgOpt.Icon = 'puffin_warning';
    dlgOpt.HeaderLines = 3;
    utils.dlgs.inputUniversalDlg(obj.mibModel.mibGUI, ...
        'Please select a single ROI from the ROI list or disable the ROI mode!', ...
        {}, {}, 'Select ROI!', dlgOpt);
    return;
end

answer = utils.dlgs.inputUniversalDlg(obj.mibModel.mibGUI, '', ...
    {'Please enter a name for the dataset:'}, {baseFilename}, 'Set name');
if isempty(answer); return; end
datasetName = answer{1};

progressDlg = uiprogressdlg(obj.mibModel.mibGUI, ...
    'Title', 'Export to Fiji', 'Message', 'Reading image data from MIB...', 'Value', 0.1);

pause(0.1);  % without this short pause MIJ calls freeze MATLAB

options.roiId = roiNo;
options.blockModeSwitch = 0;

imageData = cell2mat(obj.mibModel.getData3D(datasetType, [], 3, [], options));

% squeeze single color channel: [h,w,d,1] → [h,w,d]
if size(imageData, 4) == 1
    imageData = squeeze(imageData);
end

progressDlg.Value = 0.6; progressDlg.Message = 'Sending data to Fiji...';

if isa(imageData, 'uint16')
    if ndims(imageData) == 4  % [h,w,d,c] multichannel 16-bit — not supported
        delete(progressDlg);
        utils.dlgs.showErrorDialog(obj.mibModel.mibGUI, ...
            sprintf('Export to Fiji:\nIt is not possible to export a 16-bit Z-stack to Fiji.\n\nExport supports 8-bit Z-stacks or 16-bit single images.'), ...
            'Export to Fiji');
        return;
    else
        imp = MIJ.createImage(datasetName, imageData, 0);
        imp.show;
    end
else
    if ndims(imageData) == 4  % [h,w,d,c] multichannel 8-bit — MIJ expects [h,w,d,c]
        MIJ.createColor(datasetName, imageData, 1);
    elseif strcmp(obj.mibModel.I{id}.image.colorType, 'truecolor')
        MIJ.createColor(datasetName, imageData, 1);
    else
        imp = MIJ.createImage(datasetName, imageData, 0);
        imp.show;
    end
end
delete(progressDlg);
end
