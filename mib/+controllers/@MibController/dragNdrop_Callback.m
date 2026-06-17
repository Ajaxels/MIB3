function status = dragNdrop_Callback(obj, parameterIn)
% DRAGNDROP_CALLBACK - Callback for filename drag-and-drop operations into MIB.
%
% Syntax:
%   .. code-block:: matlab
%
%      status = obj.dragNdrop_Callback(parameterIn)
%
% Callback for filename drag-and-drop operation in MIB.
%
% Input Arguments:
%   - **parameterIn** — cell array, where
%
%     - the first element is a handle to the webWindow that was the target for the drag-and-drop operation
%     - the second element is a filename that was dragged into MIB
%
% Output Arguments:
%   - **status** — logical; ``true`` on success, ``false`` if the file could not be loaded
%

% arguments (Input)
%     obj controllers.MibController
%     parameterIn cell
% end

arguments (Output)
    status logical
end

status = false;

if obj.mibModel.preferences.System.DeveloperMode
    if size(parameterIn{2},1) < 2
        fprintf('MibController.dragNdrop_Callback: drag-and-drop file into MIB:\n%s\n', parameterIn{2});
    else
        fprintf('MibController.dragNdrop_Callback: drag-and-drop file into MIB:\n');
        disp(cellstr(parameterIn{2}));
    end
end

filenameList = cell(size(parameterIn{2},1), 1);
for i=1:size(parameterIn{2},1)
    filenameList(i) = cellstr(parameterIn{2}(i,:));
end

[path, fn, ext] = fileparts(filenameList{1});
extLower = lower(ext);

% .mibcfg is a DeepMIB config file — always handled here, never falls through
if strcmpi(extLower, '.mibcfg')
    deepMibIdx = find(strcmp(obj.childControllersIds, 'controllers.MibDeep'), 1);
    if ~isempty(deepMibIdx) && isvalid(obj.childControllers{deepMibIdx})
        obj.childControllers{deepMibIdx}.loadConfig(filenameList{1});
        status = true;
    else
        dlgOpt.MsgBoxOnly = true;
        dlgOpt.Icon = 'puffin_warning';
        utils.dlgs.inputUniversalDlg(obj.view.gui, ...
            'DeepMIB window must be open to load a *.mibCfg config file.', ...
            {}, {}, 'Drag and Drop', dlgOpt);
    end
    return;
end

% extension-based routing between loadImages and loadModel
% - modelOnlyExts  : always load as segmentation model
% - ambiguousExts  : can be image or model; decide by current dataset state
%                    (empty dataset -> image; dataset loaded -> ask user)
% everything else goes through loadImages
modelOnlyExts  = {'.model', '.mibcat'};
ambiguousExts  = {'.am', '.h5', '.hdf5', '.mat', '.mrc', '.rec', '.st', ...
                  '.nrrd', '.tif', '.png', '.tiff', '.xml'};

loadAsModel = false;
if any(strcmp(extLower, modelOnlyExts))
    loadAsModel = true;
elseif any(strcmp(extLower, ambiguousExts))
    activeId = obj.mibModel.getActiveId();
    datasetEmpty = strcmp(obj.mibModel.I{activeId}.image.filename, 'none.tif');
    if ~datasetEmpty
        answer = utils.dlgs.inputQuestDlg(obj.view.gui, ...
            sprintf('Load the dropped file as an image or as a segmentation model?\n\n%s', filenameList{1}), ...
            'Drag-and-drop', 'Image', 'Model', 'Cancel', 'Image');
        if strcmp(answer, 'Cancel'); return; end
        loadAsModel = strcmp(answer, 'Model');
    end
end

if loadAsModel
    BatchOpt = struct();
    BatchOpt.Filenames = sort(filenameList);   % full paths; supports single or multiple files
    obj.mibModel.loadModel([], BatchOpt);
    obj.mibModel.currentDirectory = path;
    obj.cDirContents.updateFileList_Callback([fn ext]);
    obj.view.handles.status.currentDirectory.Value = path;
    status = true;
    return;
end

switch extLower
    case '.mask'
    case '.ann'
        id = obj.mibModel.getActiveId();
        loadOptions.parentFigure     = obj.mibModel.mibGUI;
        loadOptions.currentDirectory = obj.mibModel.currentDirectory;
        loadOptions.boundingBox      = obj.mibModel.I{id}.image.boundingBox;
        loadOptions.pixSize          = obj.mibModel.I{id}.image.pixSize;
        loadOptions.currentT         = obj.mibModel.I{id}.slices{5}(1);
        obj.mibModel.backup('annotations', 0);
        status = obj.mibModel.I{id}.annotations.loadAnnotations(filenameList{1}, loadOptions);
        if ~status; return; end
        obj.mibModel.showAnnotations = true;
        notify(obj.mibModel, 'UpdateGuiWidgets', core.ToggleEventData({'checkboxes'}));
        notify(obj.mibModel, 'ShowImage');
    otherwise % drag and drop image files to open
        BatchOpt.Mode = {'Combine datasets'};
        % sort filenames, otherwise the first file may be the one that was under the focus when drag-n-drop started
        BatchOpt.Filenames = sort(filenameList);
        BatchOpt.DirectoryName = {path};
        obj.mibModel.loadImages([], BatchOpt);

        obj.mibModel.currentDirectory = path;
        obj.cDirContents.updateFileList_Callback([fn ext]);
end

% update the current directory in MIB GUI
obj.view.handles.status.currentDirectory.Value = path;

status = true;
end
