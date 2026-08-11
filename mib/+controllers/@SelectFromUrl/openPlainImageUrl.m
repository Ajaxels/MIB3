function openPlainImageUrl(obj)
% OPENPLAINIMAGEURL - Import an ordinary image from a URL with imread.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.openPlainImageUrl()
%
% The original behaviour of Home -> Import -> URL / Zarr, moved here unchanged
% when the menu item grew the OME-Zarr path, so a plain image URL still works
% exactly as before.
%
% Note that a multi-page file is fetched once per page: ``imread`` re-reads the
% remote file for every index. That was true before this move as well, and is
% only worth revisiting if someone actually opens large multi-page files this way.

urlAddress = obj.rootUrl;
if isempty(urlAddress); urlAddress = strtrim(obj.BatchOpt.Url); end

try
    imageInfo = imfinfo(urlAddress);
catch exception
    utils.dlgs.showErrorDialog(obj.guiFigure(), ...
        sprintf('Cannot get image info from URL:\n%s\n\n%s', urlAddress, exception.message), ...
        'URL import error');
    return;
end

progressDialog = [];
if obj.BatchOpt.showWaitbar && ~isempty(obj.guiFigure())
    progressDialog = uiprogressdlg(obj.guiFigure(), 'Value', 0, ...
        'Message', sprintf('Downloading from:\n%s\nPlease wait...', urlAddress), ...
        'Title', 'Downloading image');
end

try
    if numel(imageInfo) > 1
        [imageTemp, colorMap] = imread(urlAddress, 1);
        imageData = zeros([size(imageTemp, 1), size(imageTemp, 2), size(imageTemp, 3), ...
            numel(imageInfo)], class(imageTemp));
        imageData(:, :, :, 1) = imageTemp;
        for sliceNo = 2:numel(imageInfo)
            imageData(:, :, :, sliceNo) = imread(urlAddress, sliceNo);
            if ~isempty(progressDialog); progressDialog.Value = sliceNo / numel(imageInfo); end
        end
    else
        [imageData, colorMap] = imread(urlAddress);
        if ~isempty(progressDialog); progressDialog.Value = 1; end
    end
catch exception
    if ~isempty(progressDialog); close(progressDialog); end
    utils.dlgs.showErrorDialog(obj.guiFigure(), ...
        sprintf('Cannot download image from URL:\n%s\n\n%s', urlAddress, exception.message), ...
        'URL import error');
    return;
end
if ~isempty(progressDialog); close(progressDialog); end

% imread gives [h, w, c] or [h, w, c, z]; MIB3 wants [h, w, z, c, t]
imageData = permute(imageData, [1, 2, 4, 3]);

[~, imageName, imageExt] = fileparts(urlAddress);
imageFilename = fullfile(obj.mibModel.currentDirectory, [imageName, imageExt]);
imageMeta = core.MibImage.initializeImgInfo('Filename', imageFilename, 'Colormap', colorMap);

datasetId = obj.mibModel.getActiveId();
obj.mibModel.I{datasetId}.initialize(imageData, imageMeta, 'Standard', 'imageOnly', ...
    obj.mibModel.preferences.System.EnableSelection);

notify(obj.mibModel, 'NewDataset');
notify(obj.mibModel, 'ShowImage');
end
