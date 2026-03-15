function fnOut = saveImage(obj, layerType, filename, BatchOptIn)
% function fnOut = saveImage(obj, layerType, filename, BatchOptIn)
% Save image, mask, or labels layer; top-level BatchOpt-compatible wrapper.
%
% This is the HIGHEST-LEVEL save entry point.  It replaces the three
% separate MIB2 functions (saveImageAsDialog / saveMask / saveModel) with
% a unified interface that:
%   1. Declares a BatchOpt structure with full tooltip metadata for the
%      batch processing controller.
%   2. Handles the SyncBatch event (when BatchOptIn == NaN) so the batch
%      controller can discover this function's parameters.
%   3. Resolves output directory and filename policies (Subfolder, Full
%      path, Same as image/loaded, Use existing name, Use new name, [F]
%      template substitution).
%   4. Delegates to core.MibDataset.saveImage() for actual file writing.
%   5. Fires StopProtocol if saving fails.
%
% PARAMETER OVERVIEW
%   layerType — (char) 'image' | 'mask' | 'labels' | 'everything' for MibLabels63 only
%   filename  — (char, optional) full output path.  When empty the path is
%               resolved through the directory/filename policies below.
%   BatchOptIn — (struct | NaN | omitted):
%     When omitted     → simple GUI mode (prompts dialogs unless opts set)
%     When NaN         → SyncBatch mode: fires SyncBatch event and returns
%     When a struct    → batch/scripted mode: merges with defaults,
%                        resolves policies, then calls MibDataset.saveImage()
%
% BatchOpt FIELDS (also the defaults used in simple mode)
%   .LayerType       — {'image'} | {'mask'} | {'labels'} (cell{1})
%   .Format          — {'TIF format uncompressed (*.tif)'} (image default)
%                      Format{2} = list of valid formats for this LayerType
%   .FilenamePolicy  — {'Use existing name'} | {'Use new provided name'}
%   .Filename        — (char) stem used when FilenamePolicy = 'Use new…'
%                      Supports [F] template to embed the source stem:
%                        'Labels_[F]_suffix' → 'Labels_myStack_suffix.model'
%   .OutputDirectoryPolicy — {'Same as image'} | {'Subfolder'} |
%                             {'Full path'} | {'Same as loaded'}
%   .DestinationDirectory  — (char) meaning depends on OutputDirectoryPolicy:
%                             Subfolder  → relative subdirectory name
%                             Full path  → absolute destination path
%                             Use [InheritLastDIR] to inherit from DIR LOOP
%   .FilenameGenerator     — {'Use sequential filename'} |
%                             {'Use original filename'}
%   .Saving3DPolicy        — {'3D stack'} | {'2D sequence'}
%   .MaterialIndex         — (char) '' = all materials, 'NaN' = current
%   .showWaitbar           — (logical)
%   .id                    — (integer) dataset index, default obj.id
%
% Batch metadata (not used at run-time, displayed in batch controller UI):
%   .mibBatchSectionName   — 'Menu -> File' | 'Menu -> Mask' | 'Menu -> Models'
%   .mibBatchActionName    — 'Save layer'
%   .mibBatchTooltip.<field> — (char) help text per BatchOpt field
%
% Return values:
%   fnOut — (char or cell of char) saved filename(s); [] on failure
%
% USAGE EXAMPLES
%   @code
%   %% 1. Simple mode — save current image (GUI-based, asks dialogs as needed)
%   obj.mibModel.saveImage('image');
%   @endcode
%
%   @code
%   %% 2. Simple mode with explicit filename (silent, no dialogs)
%   obj.mibModel.saveImage('image', '/output/stack.tif');
%   @endcode
%
%   @code
%   %% 3. Scripted/batch mode — save image to a specific folder and format
%   BatchOpt.LayerType              = {'image'};
%   BatchOpt.Format                 = {'TIF format LZW compression (*.tif)'};
%   BatchOpt.OutputDirectoryPolicy  = {'Full path'};
%   BatchOpt.DestinationDirectory   = '/output/tif_export';
%   BatchOpt.FilenamePolicy         = {'Use existing name'};
%   BatchOpt.FilenameGenerator      = {'Use sequential filename'};
%   BatchOpt.Saving3DPolicy         = {'3D stack'};
%   BatchOpt.showWaitbar            = false;
%   BatchOpt.mibBatchTooltip.LayerType = '';   % marks as full batch mode
%   obj.mibModel.saveImage('image', [], BatchOpt);
%   @endcode
%
%   @code
%   %% 4. Batch mode with [F] template — prefix saved name with dataset stem
%   BatchOpt.LayerType              = {'labels'};
%   BatchOpt.Format                 = {'Matlab format (*.model)'};
%   BatchOpt.FilenamePolicy         = {'Use new provided name'};
%   BatchOpt.Filename               = 'Labels_[F]';   % [F] → source stem
%   BatchOpt.OutputDirectoryPolicy  = {'Subfolder'};
%   BatchOpt.DestinationDirectory   = 'Models';
%   BatchOpt.Saving3DPolicy         = {'3D stack'};
%   BatchOpt.showWaitbar            = false;
%   BatchOpt.mibBatchTooltip.LayerType = '';
%   obj.mibModel.saveImage('labels', [], BatchOpt);
%   @endcode
%
%   @code
%   %% 5. SyncBatch mode — let batch controller discover this function
%   obj.mibModel.saveImage('image', [], NaN);
%   % → fires SyncBatch event with default BatchOpt; no file is written
%   @endcode
%
%   @code
%   %% 6. Save mask in Amira format to same directory as source image
%   BatchOpt.LayerType              = {'mask'};
%   BatchOpt.Format                 = {'Amira mesh binary (*.am)'};
%   BatchOpt.OutputDirectoryPolicy  = {'Same as image'};
%   BatchOpt.FilenamePolicy         = {'Use existing name'};
%   BatchOpt.Saving3DPolicy         = {'3D stack'};
%   BatchOpt.showWaitbar            = true;
%   BatchOpt.mibBatchTooltip.LayerType = '';
%   obj.mibModel.saveImage('mask', [], BatchOpt);
%   @endcode
%
% SEE ALSO
%   core.MibDataset.saveImage, core.MibImage.save, core.MibLabels.save,
%   io.SaverFactory, utils.updateBatchOptCombineFields_Shared

fnOut = [];
if nargin < 4; BatchOptIn = struct(); end
if nargin < 3; filename = []; end
if nargin < 2
    error('MibModel:saveImage:missingLayerType', ...
        'layerType must be provided: ''image'', ''labels'', or ''mask''.');
end

% ================================================================== %
%  SECTION 1 — Declare default BatchOpt structure                    %
% ================================================================== %
BatchOpt = struct();

% --- dataset index ---
if isstruct(BatchOptIn) && isfield(BatchOptIn, 'id')
    BatchOpt.id = BatchOptIn.id;
else
    BatchOpt.id = obj.id;
end

% --- layer type ---
BatchOpt.LayerType    = {layerType};
BatchOpt.LayerType{2} = {'image', 'mask', 'labels'};

% --- filename ---
if ~isempty(filename)
    [inputFilenamePath, inputFilenameName, inputFilenameExt] = fileparts(filename);
    BatchOpt.Filename = [inputFilenameName inputFilenameExt];
else
    [~, inputFilenameName, inputFilenameExt] = fileparts(obj.I{BatchOpt.id}.image.filename);
    switch lower(layerType)
        case 'image';  BatchOpt.Filename = [inputFilenameName inputFilenameExt];
        case 'mask'
            if obj.I{BatchOpt.id}.labels.maxMaterials < 64 % mask included into the labels with selection
                mask_fn = obj.I{BatchOpt.id}.labels.maskFilename;
            else
                mask_fn = obj.I{BatchOpt.id}.mask.filename;
            end
            if ~isempty(mask_fn)
                [~, mask_name, mask_ext] = fileparts(mask_fn);
                BatchOpt.Filename = [mask_name mask_ext];
            else
                BatchOpt.Filename = ['Mask_' inputFilenameName '.mask'];
            end
        case 'labels'
            label_fn = obj.I{BatchOpt.id}.labels.filename;
            if ~isempty(label_fn)
                [~, label_name, label_ext] = fileparts(label_fn);
                BatchOpt.Filename = [label_name label_ext];
            else
                BatchOpt.Filename = ['Labels_' inputFilenameName '.model'];
            end
    end
end

BatchOpt.Format    = {io.SaverFactory.getDefaultFormat(layerType, inputFilenameExt)}; % --- file formats list (depends on LayerType) ---
BatchOpt.Format{2} = io.SaverFactory.getFormats(layerType);
BatchOpt.FilenamePolicy    = {'Use existing name'};         % --- filename policy ---                                   
BatchOpt.FilenamePolicy{2} = {'Use existing name', 'Use new provided name'};
BatchOpt.OutputDirectoryPolicy    = {'Same as image'};      % --- directory policy ---
BatchOpt.OutputDirectoryPolicy{2} = {'Subfolder', 'Full path', 'Same as image', 'Same as loaded'};
BatchOpt.DestinationDirectory = 'MIB_SaveAs';  % --- destination directory default ---
if ~isempty(filename) && ~isempty(inputFilenamePath)
    BatchOpt.DestinationDirectory   = inputFilenamePath;
    BatchOpt.OutputDirectoryPolicy{1} = 'Full path';
end
BatchOpt.FilenameGenerator    = {'Use sequential filename'};   % --- filename generator (sequential or original) ---
BatchOpt.FilenameGenerator{2} = {'Use original filename', 'Use sequential filename'};
BatchOpt.Saving3DPolicy    = {'3D stack'};   % --- 3D policy ---
BatchOpt.Saving3DPolicy{2} = {'3D stack', '2D sequence'};
BatchOpt.MaterialIndex = '';   % % --- material index (labels only):'= all, 'NaN' = currently selected
BatchOpt.showWaitbar = true; % --- waitbar ---

% --- batch controller metadata ---
switch lower(layerType)
    case 'image'
        BatchOpt.mibBatchSectionName = 'Menu -> File';
        BatchOpt.mibBatchActionName  = 'Save dataset';
    case 'mask'
        BatchOpt.mibBatchSectionName = 'Menu -> Mask';
        BatchOpt.mibBatchActionName  = 'Save mask';
    case 'labels'
        BatchOpt.mibBatchSectionName = 'Menu -> Models';
        BatchOpt.mibBatchActionName  = 'Save model';
end

% --- tooltips for batch controller UI ---
BatchOpt.mibBatchTooltip.LayerType    = sprintf('Which data layer to save: image data, binary mask, or multi-material segmentation labels');
BatchOpt.mibBatchTooltip.Format       = sprintf('File format for the output. The available options depend on LayerType.');
BatchOpt.mibBatchTooltip.FilenamePolicy = sprintf('Use existing name: filename from the last save/load. Use new provided name: use the Filename field (supports [F] template).');
BatchOpt.mibBatchTooltip.Filename     = sprintf('[Use new provided name only] Output filename stem. Use [F] to embed the source image stem, e.g. Labels_[F] → Labels_myStack.model');
BatchOpt.mibBatchTooltip.OutputDirectoryPolicy = sprintf('Subfolder: relative to source image path.\nFull path: absolute DestinationDirectory.\nSame as image: same folder as the source image.\nSame as loaded: same folder as last loaded dataset.');
BatchOpt.mibBatchTooltip.DestinationDirectory  = sprintf('Target directory for Subfolder (no leading slash) or Full path policy. Use [InheritLastDIR] to inherit from a preceding DIR LOOP batch action. Compatible with "..\\".');
BatchOpt.mibBatchTooltip.FilenameGenerator     = sprintf('Use original filename: derive output filenames from SliceName metadata. Use sequential filename: generate numbered filenames from the provided stem.');
BatchOpt.mibBatchTooltip.Saving3DPolicy        = sprintf('[TIF/PNG only] 3D stack: save all Z-slices in one file. 2D sequence: one file per slice.');
BatchOpt.mibBatchTooltip.MaterialIndex         = sprintf('[Labels only] Material index to export. Empty = all materials. NaN = currently selected material. Integer = specific material (exported as binary 0/1).');
BatchOpt.mibBatchTooltip.showWaitbar           = sprintf('Show or hide the progress bar during saving.');

% ================================================================== %
%  SECTION 2 — BatchOpt mode routing                                  %
% ================================================================== %
if nargin == 4  % BatchOptIn was explicitly provided
    if isstruct(BatchOptIn) == 0  % scalar (NaN) → SyncBatch mode
        if isnan(BatchOptIn)
            BatchOpt = rmfield(BatchOpt, 'id');
            eventdata = core.ToggleEventData(BatchOpt);
            notify(obj, 'SyncBatch', eventdata);
        else
            errorOpts.mibPath = obj.mibModel.mibPath;
            errorOpts.WindowHeight = 150;
            utils.dlgs.showErrorDialog(obj.view.gui, sprintf('A struct (or NaN) is required as the 3rd parameter!'), 'Error', 'Error in MibModel.savaImage', '', errorOpts);
        end
        return;
    else
        % Merge caller's struct with our defaults
        BatchOpt = utils.updateBatchOptCombineFields_Shared(BatchOpt, BatchOptIn);
    end
else
    % ----------------------------------------------------------------
    % SIMPLE MODE — no BatchOptIn provided (called from GUI callbacks)
    % Assemble saveOptions directly and call MibDataset.saveImage()
    % ----------------------------------------------------------------
    saveOpts = struct();
    if ~isempty(filename)
        if isfield(BatchOptIn,'Format')
            saveOpts.Format = BatchOptIn.Format;
        end
        saveOpts.silent       = false;
        saveOpts.showWaitbar  = true;
        saveOpts.overwrite    = true;
        saveOpts.ParentFigure = obj.mibGUI;
        saveOpts.mibPath      = obj.mibPath;
        fnOut = obj.I{BatchOpt.id}.saveImage(layerType, filename, saveOpts);
    else
        % No filename = show a save-file dialog so the user can choose
        formats   = io.SaverFactory.getFormats(layerType);
        extTokens = regexp(formats, '\(\*\.[\w.]+\)', 'match', 'once');
        extTokens = strrep(strrep(extTokens, '(', ''), ')', '');  % '*.tif', '*.am', ...
        filterSpec = [extTokens, formats];  % Nx2 cell for uiputfile
        
        [imgDir, ~, ~]  = fileparts(obj.I{BatchOpt.id}.image.filename);
        defaultFilename = fullfile(imgDir, BatchOpt.Filename);
        [~, ~, defaultExt] = fileparts(defaultFilename);
        
        % resort formats to have the current one selected
        formatListPosition = find(ismember(filterSpec(:,1), ['*' defaultExt]));
        if ~isempty(formatListPosition)
            formatListPosition = formatListPosition(1);
            selectedFilter = filterSpec(formatListPosition, :);
            filterSpec(formatListPosition, :) = [];
            filterSpec = [selectedFilter; filterSpec];
        end

        dialogTitle = ['Save ' layerType];
        [fname, fpath, filterIndex] = uiputfile(filterSpec, dialogTitle, defaultFilename);
        if isequal(fname, 0); return; end   % user cancelled

        if filterIndex >  size(filterSpec,1) % All Files (*.*) case, cancel
            dlgOpts.MsgBoxOnly = true;
            dlgOpts.Header = 'The output format was not selected!';
            dlgOpts.Icon = 'puffin_warning';
            dlgOpts.mibPath = obj.mibPath;
            dlgOpts.WindowHeight = 150;
            utils.dlgs.inputUniversalDlg(obj.mibGUI, {}, {}, 'Missing output format', dlgOpts);
            return;
        end

        % Fix filename extension to match the selected filter.
        % MATLAB's uiputfile does not always update the extension (R2026a-pre, case 08552750) when the
        % user changes the format filter (platform-dependent bug), so we
        % enforce it here.  Handles compound extensions like '.ome.tiff'.
        selectedExt  = strrep(filterSpec{filterIndex, 1}, '*', '');   % e.g. '.jpg' or '.ome.tiff'
        allKnownExts = cellfun(@(e) strrep(e, '*', ''), filterSpec(:,1), 'UniformOutput', false);
        [~, fbase, oldExt] = fileparts(fname);
        [~, fbase2, ext2]  = fileparts(fbase);   % one extra level for compound ext
        if ismember([ext2, oldExt], allKnownExts)
            fbase = fbase2;   % strip compound prefix too (e.g. '.ome' from '.ome.tiff')
        end
        fname = [fbase, selectedExt];

        filename = fullfile(fpath, fname);
        saveOpts.Format       = filterSpec{filterIndex,2};
        saveOpts.silent       = false;
        saveOpts.showWaitbar  = true;
        saveOpts.overwrite    = true;
        saveOpts.ParentFigure = obj.mibGUI;
        saveOpts.mibPath      = obj.mibPath;

        % When saving image data: prompt the user to review / update voxel sizes
        % before the file is written (equivalent to MIB2 saveImageAsDialog ->
        % updatePixSizeResolution() call).
        if strcmpi(layerType, 'image')
            ds = obj.I{BatchOpt.id};
            dlgOpts.showDialog   = true;
            dlgOpts.ParentFigure = obj.mibGUI;
            dlgOpts.mibPath      = obj.mibPath;
            dlgOpts.HelpUrl      = fullfile(obj.mibPath, ...
                'techdoc', 'html', 'user-interface', 'menu', 'dataset', 'index.html#parameters');
            [~, updatedPixSize, pixDlgResult] = utils.updatePixSizeAndResolution([], ds.image.pixSize, dlgOpts);
            if pixDlgResult == 0; return; end   % user cancelled the voxel-size dialog

            % Apply updated pixSize to the dataset and recalculate bounding box
            ds.setPixSize(updatedPixSize);
            ds.image.boundingBox(2) = ds.image.boundingBox(1) + (ds.image.width  - 1) * ds.image.pixSize.x;
            ds.image.boundingBox(4) = ds.image.boundingBox(3) + (ds.image.height - 1) * ds.image.pixSize.y;
            ds.image.boundingBox(6) = ds.image.boundingBox(5) + (ds.image.depth  - 1) * ds.image.pixSize.z;
        end

        fnOut = obj.I{BatchOpt.id}.saveImage(layerType, filename, saveOpts);
        
        % update the list of files
        UpdateFilelist.filename = fname;
        eventdata = core.ToggleEventData(UpdateFilelist);
        notify(obj, 'UpdateFileList', eventdata);
    end
    return;
end

% ------------------------------------------------------------------ %
% Check if caller passed mibBatchTooltip — if not, treat as simple    %
% parameterised call (not true batch-controller mode)                 %
% ------------------------------------------------------------------ %
if ~isfield(BatchOptIn, 'mibBatchTooltip')
    % Parameterised call: pass BatchOptIn fields through to MibDataset
    saveOpts = BatchOptIn;
    saveOpts.Format       = BatchOpt.Format{1};
    saveOpts.showWaitbar  = BatchOpt.showWaitbar;
    saveOpts.overwrite    = true;
    saveOpts.ParentFigure = obj.mibGUI;
    saveOpts.mibPath      = obj.mibPath;
    if isfield(BatchOpt,'MaterialIndex') && ~isempty(BatchOpt.MaterialIndex)
        materialIndex = str2double(BatchOpt.MaterialIndex);
        if ~isnan(materialIndex); saveOpts.MaterialIndex = materialIndex; end
    end
    fnOut = obj.I{BatchOpt.id}.saveImage(layerType, filename, saveOpts);
    if isempty(fnOut); notify(obj, 'StopProtocol'); end
    return;
end

% ==================================================================   %
%  SECTION 3 — Full batch mode: resolve directory + filename policies  %
% ==================================================================   %

% --- resolve destination directory ---
imgFullFilename = obj.I{BatchOpt.id}.image.filename;
[imgPath, imgName, ~] = fileparts(imgFullFilename);

switch BatchOpt.OutputDirectoryPolicy{1}
    case 'Subfolder'
        destDir = fullfile(imgPath, BatchOpt.DestinationDirectory);
        if exist(destDir,'dir') ~= 7; mkdir(destDir); end
        BatchOpt.OutputDirectoryPolicy{1} = 'Full path';
    case 'Same as image'
        destDir = imgPath;
        BatchOpt.OutputDirectoryPolicy{1} = 'Full path';
    case 'Same as loaded'
        destDir = obj.currentDirectory;
        BatchOpt.OutputDirectoryPolicy{1} = 'Full path';
    otherwise  % 'Full path'
        destDir = BatchOpt.DestinationDirectory;
        % Handle [InheritLastDIR] tag (used with DIR LOOP batch action)
        if contains(destDir, '[InheritLastDIR]')
            destDir = strrep(destDir, '[InheritLastDIR]', obj.currentDirectory);
        end
        % Resolve relative paths (e.g. '..\')
        if ~isempty(destDir) && ~isabsolute_path(destDir)
            destDir = fullfile(imgPath, destDir);
        end
end
if exist(destDir,'dir') ~= 7; mkdir(destDir); end

% --- resolve output filename stem ---
if strcmp(BatchOpt.FilenamePolicy{1}, 'Use existing name')
    outputName = imgName;   % use source image stem
else
    % 'Use new provided name' — may contain [F] template
    outputName = BatchOpt.Filename;
    tPos = strfind(outputName, '[');
    if ~isempty(tPos)
        % Replace [F] with the source image stem
        outputName = [outputName(1:tPos(1)-1), imgName, ...
            outputName(tPos(1)+3:end)];  % [F] = 3 chars
    end
end

% Derive extension from the selected format string
formatExt = '';
tk = regexp(BatchOpt.Format{1}, '\*\.(\w+)\)', 'tokens', 'once');
if ~isempty(tk); formatExt = ['.' tk{1}]; end

outputFilename = fullfile(destDir, [outputName, formatExt]);

% ================================================================== %
%  SECTION 4 — Assemble saveOptions and delegate to MibDataset.saveImage() %
% ================================================================== %
saveOpts.Format            = BatchOpt.Format{1};
saveOpts.Saving3DPolicy    = BatchOpt.Saving3DPolicy{1};
saveOpts.FilenameGenerator = BatchOpt.FilenameGenerator{1};
saveOpts.FilenamePolicy    = BatchOpt.FilenamePolicy{1};
saveOpts.showWaitbar       = BatchOpt.showWaitbar;
saveOpts.silent            = true;   % batch mode → no interactive dialogs
saveOpts.overwrite         = true;
saveOpts.ParentFigure      = obj.mibGUI;
saveOpts.mibPath           = obj.mibPath;

% Parse MaterialIndex from string (batch controller stores it as char)
if isfield(BatchOpt,'MaterialIndex') && ~isempty(BatchOpt.MaterialIndex)
    materialIndex = str2double(BatchOpt.MaterialIndex);
    if ~isnan(materialIndex); saveOpts.MaterialIndex = materialIndex; end
end

fnOut = obj.I{BatchOpt.id}.saveImage(layerType, outputFilename, saveOpts);
if isempty(fnOut); notify(obj, 'StopProtocol'); end

% update the list of files
UpdateFilelist.filename = fname;
eventdata = core.ToggleEventData(UpdateFilelist);
notify(obj, 'UpdateFileList', eventdata);
end

% ------------------------------------------------------------------   %
%   Local helper                                                       %
% ------------------------------------------------------------------   %
function tf = isabsolute_path(p)
% Return true if p is an absolute filesystem path.
if ispc
    tf = numel(p) >= 2 && p(2) == ':';    % Windows: starts with drive letter
else
    tf = ~isempty(p) && p(1) == '/';      % Unix/Mac
end
end
