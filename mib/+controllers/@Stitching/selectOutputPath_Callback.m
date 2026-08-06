function selectOutputPath_Callback(obj)
% SELECTOUTPUTPATH_CALLBACK - Open a file picker to choose the output path.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.selectOutputPath_Callback()
%
% What is offered depends on ``BatchOpt.OutputMode``:
%   - **OME-Zarr3 (BigData)** - a single ``.zarr3`` store.
%   - **Image files** - the formats from
%     :meth:`controllers.Stitching.imageFileFormats`, whose picked filter is
%     recorded in ``BatchOpt.OutputFormat``. This dialog is the ONLY place the
%     image format is chosen, which is why it also has to survive the cancel
%     path unchanged.
%
% ``In memory`` never reaches here - the button is disabled for it.
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.Stitching.selectOutputPath_Callback: triggered\n');
end

if strcmp(obj.BatchOpt.OutputMode{1}, 'Image files')
    selectImageFilePath(obj);
else
    selectZarrPath(obj);
end

end

% =========================================================================
function selectZarrPath(obj)
% SELECTZARRPATH - Pick the destination .zarr3 store.
startFolder = obj.BatchOpt.OutputPath;
if isempty(startFolder) || ~isfolder(fileparts(startFolder))
    startFolder = obj.mibModel.currentDirectory;
end

[selectedFile, selectedFolder] = uiputfile( ...
    {'*.zarr3', 'OME-Zarr directory (*.zarr3)'}, ...
    'Save OME-Zarr output as', fullfile(startFolder, 'stitched.zarr3'));
if isequal(selectedFile, 0)
    return;
end

outputPath = fullfile(selectedFolder, selectedFile);
obj.BatchOpt.OutputPath = outputPath;
obj.view.handles.OutputPath.Value = outputPath;

% A fresh output path means the pyramid settings are re-asked on the next
% Stitch (they described the previous destination).
obj.zarrExportOptions = [];
end

% =========================================================================
function selectImageFilePath(obj)
% SELECTIMAGEFILEPATH - Pick the destination image file and, with it, the format.
formats = controllers.Stitching.imageFileFormats();

% The suggested name is the one the mosaic carries everywhere else
% (<source>_stitch), re-extensioned to the format currently selected - so
% reopening the dialog offers back what was picked last time.
currentEntry = controllers.Stitching.imageFileFormat(obj.BatchOpt.OutputFormat{1});
defaultPath = obj.BatchOpt.OutputPath;
if isempty(defaultPath) || ~isfolder(fileparts(defaultPath))
    defaultPath = obj.stitchedFilename();
end
[defaultFolder, defaultName] = fileparts(defaultPath);
if isempty(defaultFolder) || ~isfolder(defaultFolder)
    defaultFolder = obj.mibModel.currentDirectory;
end
defaultPath = fullfile(defaultFolder, [defaultName, currentEntry.extension]);

filterSpec = [cellfun(@(ext) ['*' ext], {formats.extension}', 'UniformOutput', false), ...
    {formats.label}'];

% uiputfile always opens on its first row, so move the selected format there -
% the same reordering models.MibModel.saveImage does. formatOrder tracks where
% each row came from, since filterIndex refers to the REORDERED list.
formatOrder = 1:numel(formats);
selectedIdx = find(strcmp({formats.label}, currentEntry.label), 1);
if ~isempty(selectedIdx) && selectedIdx > 1
    formatOrder = [selectedIdx, setdiff(formatOrder, selectedIdx, 'stable')];
    filterSpec = filterSpec(formatOrder, :);
end

[selectedFile, selectedFolder, filterIndex] = uiputfile(filterSpec, ...
    'Save stitched mosaic as', defaultPath);
if isequal(selectedFile, 0)
    return;
end
if filterIndex < 1 || filterIndex > numel(formatOrder)
    return;   % "All files" or an unexpected index - no format was stated
end
pickedEntry = formats(formatOrder(filterIndex));

% Enforce the filter's extension on the returned name: uiputfile does not
% reliably rewrite it when the user switches the format dropdown (R2026a-pre,
% case 08552750), and here a wrong extension would also make the two .am rows
% indistinguishable. Same fix as models.MibModel.saveImage.
[~, pickedName] = fileparts(selectedFile);
outputPath = fullfile(selectedFolder, [pickedName, pickedEntry.extension]);

obj.BatchOpt.OutputPath      = outputPath;
obj.BatchOpt.OutputFormat{1} = pickedEntry.label;
obj.view.handles.OutputPath.Value = outputPath;

% The format is not on a widget of its own, so the path field's tooltip is
% where the user can read back which of the two .am variants was picked.
obj.updateWidgets();
end
