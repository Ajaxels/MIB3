function homeImport_Callback(obj, hWidget, hData)
% HOMEIMPORT_CALLBACK - callback on press of the import buttons in the Home ribbon.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.homeImport_Callback(hWidget, hData)
%
% Input Arguments:
%   - **hWidget** — handle to the pressed widget
%   - **hData** — handle to supporting EventData class
%

arguments (Input)
    obj controllers.MibRibbon
    hWidget matlab.ui.internal.toolstrip.base.Action
    hData matlab.ui.internal.toolstrip.base.ToolstripEventData
end

mode = hWidget.Text;
if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibRibbon.homeImport_Callback: Load dataset pressed -> %s\n', mode);
end

switch mode
    case {'Import', 'MATLAB'}  % obj.handles.ribbonHome.import &  obj.handles.ribbonHome.importFromMatlab
        obj.mibModel.importDataset('image');
    case 'System Clipboard'    % obj.handles.ribbonHome.importFromClipboard
        img = imclipboard('paste');
        if isempty(img)
            utils.dlgs.showErrorDialog(obj.view.gui, 'Image is missing in the clipboard!', 'Clipboard import');
            return;
        end
        % convert to MIB3 [y,x,z,c,t] dimensions
        img = permute(img, [1,2,4,3]);
        id = obj.mibModel.getActiveId();
        obj.mibModel.I{id}.initialize(img, [], 'Standard', 'imageOnly', obj.mibModel.preferences.System.EnableSelection);

        % --- notify controllers ---
        notify(obj.mibModel, 'NewDataset');
        notify(obj.mibModel, 'ShowImage');

    case 'Imaris'              % obj.handles.ribbonHome.importFromImaris
        [imageData, imarisInfo, viewPort, lutColors, obj.mibModel.connImaris] = io.imaris.getImarisDataset(obj.mibModel.connImaris);
        if isnan(imageData(1)); return; end

        % getImarisDataset returns [h,w,c,z,t]; convert to MIB3 [h,w,z,c,t]
        imageData = permute(imageData, [1,2,4,3,5]);

        % Build metadata dictionary from Imaris containers.Map
        [imgDesc, actionLog] = core.MibImage.splitImageDescription(imarisInfo('ImageDescription'));
        imageMeta = core.MibImage.initializeImgInfo( ...
            'Filename',         fullfile(obj.mibModel.currentDirectory, 'imaris_import.tif'), ...
            'ColorType',        imarisInfo('ColorType'), ...
            'ImageDescription', imgDesc, ...
            'ActionLog',        actionLog, ...
            'viewPort',         viewPort, ...
            'lutColors',        lutColors);

        id = obj.mibModel.getActiveId();
        obj.mibModel.I{id}.initialize(imageData, imageMeta, 'Standard', 'imageOnly', obj.mibModel.preferences.System.EnableSelection);
        obj.mibModel.I{id}.useLUT = true;

        notify(obj.mibModel, 'NewDataset');
        notify(obj.mibModel, 'ShowImage');
        
    case 'Omero'               % obj.handles.ribbonHome.importFromOmero
        utils.dlgs.showErrorDialog(obj.view.gui, 'Not implemented yet!', 'OMERO import');
        return;

    case 'URL'                 % obj.handles.ribbonHome.importFromURL
        % Pre-fill URL from clipboard if it looks like a link
        clipboardText = clipboard('paste');
        webLink = 'http://mib.helsinki.fi/images/im_browser_splash.jpg';
        if ~isempty(clipboardText)
            if contains(clipboardText, {'https://', 'http://'}); webLink = clipboardText; end
        end

        answer = utils.dlgs.inputUniversalDlg(obj.view.gui, '', ...
            {'URL of the image to import (including protocol, e.g. http://):'}, ...
            {webLink}, 'Open URL', struct());
        if isempty(answer); return; end
        urlAddress = answer{1};

        % Get image info (number of slices, format, etc.)
        try
            imageInfo = imfinfo(urlAddress);
        catch exception
            utils.dlgs.showErrorDialog(obj.view.gui, ...
                sprintf('Cannot get image info from URL:\n%s\n\n%s', urlAddress, exception.message), ...
                'URL import error');
            return;
        end

        % Download with progress
        progressDialog = uiprogressdlg(obj.view.gui, 'Value', 0, ...
            'Message', sprintf('Downloading from:\n%s\nPlease wait...', urlAddress), ...
            'Title', 'Downloading image');
        try
            if numel(imageInfo) > 1
                [imageTemp, colorMap] = imread(urlAddress, 1);
                imageData = zeros([size(imageTemp,1), size(imageTemp,2), size(imageTemp,3), numel(imageInfo)], class(imageTemp));
                imageData(:,:,:,1) = imageTemp;
                for sliceNo = 2:numel(imageInfo)
                    imageData(:,:,:,sliceNo) = imread(urlAddress, sliceNo);
                    progressDialog.Value = sliceNo / numel(imageInfo);
                end
            else
                [imageData, colorMap] = imread(urlAddress);
                progressDialog.Value = 1;
            end
        catch exception
            close(progressDialog);
            utils.dlgs.showErrorDialog(obj.view.gui, ...
                sprintf('Cannot download image from URL:\n%s\n\n%s', urlAddress, exception.message), ...
                'URL import error');
            return;
        end
        close(progressDialog);

        % Convert imread output [h,w,c] or [h,w,c,z] → MIB3 [h,w,z,c,t]
        imageData = permute(imageData, [1,2,4,3]);

        % Build metadata dictionary: filename derived from URL, colormap for indexed images
        [~, imageName, imageExt] = fileparts(urlAddress);
        imageFilename = fullfile(obj.mibModel.currentDirectory, [imageName, imageExt]);
        imageMeta = core.MibImage.initializeImgInfo('Filename', imageFilename, 'Colormap', colorMap);

        id = obj.mibModel.getActiveId();
        obj.mibModel.I{id}.initialize(imageData, imageMeta, 'Standard', 'imageOnly', obj.mibModel.preferences.System.EnableSelection);

        notify(obj.mibModel, 'NewDataset');
        notify(obj.mibModel, 'ShowImage');
end

end
