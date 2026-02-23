function loadImages(obj, parameter, BatchOptIn)
% function loadImages(obj, parameter, BatchOptIn)
% Load images and arrange them into a stack
%
% Parameters:
% parameter: a string with parameters for the function
%   @li 'Combine datasets' - [@em default] Combine selected datasets 
%   @li 'Load part of dataset' - Load part of the dataset
%   @li 'Load each N-th dataset' - Load each N-th dataset
%   @li 'Insert into open dataset' - Insert into the open dataset
%   @li 'Combine files as color channels' - Combine files as color channels
%   @li 'Add as new color channel' - Add as a new color channel
%   @li 'Add each N-th dataset as new color channel' - Add each N-th dataset as a new color channel
% BatchOptIn: a structure for batch processing mode, 
%   @li when NaN return a structure with default options via "SyncBatch" event, see Declaration of the BatchOpt structure below for details, 
%       the function variables are preferred over the BatchOptIn variables
%   @li .Mode -> [cell], desired mode to combine the images - 
%       'Combine datasets', 
%       'Load each N-th dataset', 
%       'Insert into open dataset', 
%       'Combine files as color channels', 
%       'Add as new color channel', 
%       'Add each N-th dataset as new color channel'
% @li .DirectoryName -> [cell] directory name, where the files are located 
% @li .FilenameFilter -> [char] filter for filenames
%       *.* - process all files in the directory; 
%       *.tif - process only the TIF files; 
%       could also be a filename
% @li .Filenames -> [A CELL WITHIN CELL ARRAY, optional] with list of FULL PATH filenames to open, only for the batch mode
% @li .UseBioFormats -> [logical] when checked the Bio-Formats reader will be used
% @li .BioFormatsIndices -> [char, BioFormats only] indices of images to be opened for file containers, 
%       when empty load all
% @li .EachNthStep -> [char] define step to be used for combining images using each N-th option
% @li .BackgroundColorIntensity -> [char] Intensity of the background color for cases, 
%       when width/height of combined images mismatch
% @li .InsertDatasetDimension -> [Insert only, cell] Image dimension to insert the dataset: 'depth', 'time'
% @li .InsertDatasetPosition -> [Insert only, string] insert position; 
%       @b 1 - beginning of the open dataset; 
%       @b 0 - end of the open dataset
%       @b Number - define position
% @li .showWaitbar -> [logical] show or not the waitbar
% @li .id -> [@em optional], an index dataset, default - currently shown dataset

% Updates
% 

if nargin < 2; parameter = 'Combine datasets'; end

%% Declaration of the BatchOpt structure
BatchOpt = struct();
if ~isempty(parameter)
    BatchOpt.Mode = {parameter};
else
    BatchOpt.Mode = {'Combine datasets'};
end
BatchOpt.Mode{2} = {'Combine datasets', 'Load each N-th dataset', ...
        'Insert into open dataset', 'Combine files as color channels', 'Add as new color channel', ...
        'Add each N-th dataset as new color channel', 'Series-by-series'};
BatchOpt.DirectoryName = {'Current MIB path'};   % specify the target directory
BatchOpt.DirectoryName{2} = {'Current MIB path', 'Selected files in Directory Contents', 'Inherit from Directory/File loop', obj.currentDirectory};  % this option forces the directories to be provided from the Dir/File loops
filter = obj.selectedFileFilter{obj.useBioFormats+1}; % get the selected file filter
if strcmp(filter, 'all known')
    BatchOpt.FilenameFilter = '*.*';
else
    BatchOpt.FilenameFilter = ['*.' filter];
end
% BatchOpt.Filenames -> this is optional parameter, when it is provided the loaded files are taken only from this list box
BatchOpt.UseBioFormats = obj.useBioFormats;
BatchOpt.BioFormatsIndices = '';
BatchOpt.EachNthStep = '2'; 
BatchOpt.BackgroundColorIntensity = '65535'; 
BatchOpt.InsertDatasetDimension = {'depth'}; 
BatchOpt.InsertDatasetDimension{2} = {'depth', 'time'};
BatchOpt.InsertDatasetPosition = '0';
BatchOpt.showWaitbar = true;   % show or not the waitbar
BatchOpt.id = obj.id;   % optional, id

BatchOpt.mibBatchSectionName = 'Menu -> File';    % section name for the Batch
BatchOpt.mibBatchActionName = 'Load and combine images';
BatchOpt.mibBatchTooltip.Mode = sprintf('Desired mode to combine the images, use "Series-by-series" to process each dataset in a file-container individually (bio-formats only)');
BatchOpt.mibBatchTooltip.DirectoryName = sprintf('Directory name, where the files are located, use the right mouse click over the Parameters table to modify the directory');
BatchOpt.mibBatchTooltip.FilenameFilter = sprintf('Filter for filenames: *.* - process all files in the directory; *.tif - process only the TIF files; could also be a filename');
BatchOpt.mibBatchTooltip.UseBioFormats = sprintf('When checked the Bio-Formats reader will be used');
BatchOpt.mibBatchTooltip.BioFormatsIndices = sprintf('[BioFormats only] indices of images to be opened for file containers, when empty load all');
BatchOpt.mibBatchTooltip.EachNthStep = sprintf('Define step to be used for combining images using each N-th option');
BatchOpt.mibBatchTooltip.BackgroundColorIntensity = sprintf('Intensity of the background color for cases, when width/height of combined images mismatch');
BatchOpt.mibBatchTooltip.InsertDatasetDimension = sprintf('[Insert only] Image dimension to insert the dataset');
BatchOpt.mibBatchTooltip.InsertDatasetPosition = sprintf('[Insert only] insert position; 1 - beginning of the open dataset; 0 - end of the open dataset\nor type any number to define position');
BatchOpt.mibBatchTooltip.showWaitbar = sprintf('Show or not the waitbar');

batchModeSwitch = 0;    % indicates that the function is running in the gui mode

%% Batch mode check actions
if nargin == 3  % batch mode 
    if isstruct(BatchOptIn) == 0
        if isnan(BatchOptIn)     % when varargin{3} == NaN return possible settings
            % trigger SyncBatch event to send BatchOptInOut to mibBatchController 
            BatchOpt = rmfield(BatchOpt, 'id');     % remove id field
            eventdata = core.ToggleEventData(BatchOpt);
            notify(obj, 'SyncBatch', eventdata);
        else
            errorText = sprintf('A structure as the 3rd parameter is required!');
            utils.dlgs.showErrorDialog(obj.mibGUI, errorText, 'BatchOpt Error');
        end
        return;
    else
        % add/update BatchOpt with the provided fields in BatchOptIn
        % combine fields from input and default structures
        BatchOpt = utils.updateBatchOptCombineFields_Shared(BatchOpt, BatchOptIn);
    end

    if strcmp(BatchOpt.DirectoryName{1}, 'Current MIB path')
        BatchOpt.DirectoryName{1} = obj.currentDirectory; 
    end

    if ~isfield(BatchOptIn, 'Filenames')
        if ~strcmp(BatchOpt.DirectoryName{1}, 'Selected files in Directory Contents')
            filename = dir(fullfile(BatchOpt.DirectoryName{1}, BatchOpt.FilenameFilter));   % get list of files
            filename2 = arrayfun(@(filename) fullfile(BatchOpt.DirectoryName{1}, filename.name), filename, 'UniformOutput', false);  % generate full paths
            notDirsIndices = arrayfun(@(filename2) ~isdir(cell2mat(filename2)), filename2);     %#ok<ISDIR> % get indices of not directories
            BatchOpt.Filenames = filename2(notDirsIndices);     % generate full path file names
        else
            if isempty(obj.selectedFiles)
                errorText = sprintf('!!! Error !!!\n\nPlease select files in the Directory contents panel and try again!');
                utils.dlgs.showErrorDialog(obj.mibGUI, errorText, 'No files selected!');
                return;
            end
            BatchOpt.Filenames = arrayfun(@(filename) fullfile(obj.currentDirectory, filename), obj.selectedFiles, 'UniformOutput', true);  % generate full paths
        end
    else
        %BatchOpt.Filenames = BatchOptIn.Filenames{1};   % convert from cell with cell array to cell array
        %if ischar(BatchOpt.Filenames); BatchOpt.Filenames = {BatchOpt.Filenames}; end
    end
    if isfield(BatchOptIn, 'mibBatchTooltip'); batchModeSwitch = 1; end    % indicates that the function is running in the batch mode
else
    if strcmp(BatchOpt.DirectoryName{1}, 'Current MIB path'); BatchOpt.DirectoryName{1} = obj.currentDirectory; end
    % generate a dataset from the selected files    % generate list of files
    
    if isempty(obj.selectedFiles)
        utils.dlgs.showErrorDialog(obj.mibGUI, sprintf('MibModel.loadImages:\nPlease select files to open in the Directory contents panel'), 'Files were not selected');
        return;
    end

    % handle ome-zarr
    if numel(obj.selectedFiles) == 1 && obj.selectedFiles{1}(1) == '[' %#ok<ISCL> % trying to open a folder
        filename{1} = obj.selectedFiles{1}(2:end-1); % remove '['  and ']'
        BatchOpt.Filenames = fullfile(BatchOpt.DirectoryName{1}, filename);
    else
        % remove folders
        filenames = obj.selectedFiles(~contains(obj.selectedFiles, '['));
        
        if isempty(filenames)
            errorText = sprintf('!!! Error !!!\n\nPlease select files in the Directory contents panel and try again!');
            utils.dlgs.showErrorDialog(obj.mibGUI, errorText, 'No files selected!');
            return; 
        end
        BatchOpt.Filenames = arrayfun(@(filename) fullfile(BatchOpt.DirectoryName{1}, cell2mat(filename)), filenames, 'UniformOutput', false);  % generate full paths
    end

    if strcmp(BatchOpt.Mode{1}, 'Load each N-th dataset') || strcmp(BatchOpt.Mode{1}, 'Add each N-th dataset as new color channel')

        % get the name for a new set
        options.ParentFigure = obj.mibGUI;
        options.Type = 'spinner';
        options.WindowHeight = 150;
        defAns = struct('Value', 2, 'Limits', [1 Inf], 'ValueDisplayFormat', '%d');
        dlgText = sprintf('There are %d file selected; please enter the loading step:\n\nFor example when step is 2 \nMIB loads each second dataset', numel(BatchOpt.Filenames));
        answer = utils.dlgs.mibInputSingleDlg(obj.mibPath, dlgText, defAns, 'Enter the step', options);
        if isempty(answer); return; end

        BatchOpt.EachNthStep = num2str(answer);
    end
end

if numel(BatchOpt.Filenames) < 1
    errorText = sprintf('No files were selected!!!\nPlease select desired files and try again!\nYou can use Ctrl and Shift for the selection.');
    utils.dlgs.showErrorDialog(obj.mibGUI, errorText, 'Wrong selection!');
    notify(obj, 'StopProtocol');
    return; 
end

%%
options.UseBioFormats = BatchOpt.UseBioFormats;
options.waitbar = BatchOpt.showWaitbar;
options.mibPath = obj.mibPath;
options.id = BatchOpt.id;   % id of the current dataset
options.bioFormatsMemoizerMemoDir = obj.preferences.ExternalDirs.BioFormatsMemoizerMemoDir;  % path to temp folder for Bioformats
options.customSections = false; % load a part from datasets
if batchModeSwitch == 1    % batch mode is used
    options.BackgroundColorIntensity = str2double(BatchOpt.BackgroundColorIntensity);   % add background color intensity, for cases when size of the combined slices mismatch; see more in mibLoadImages 
    options.silentMode = true;  % do not ask any questions in the subfunctions, i.e. insertSlice
    options.BioFormatsIndices = str2num(BatchOpt.BioFormatsIndices);    %#ok<ST2NM> % get indices of images to load using bioformats
end
if isfield(BatchOpt, 'verbose'); options.verbose = BatchOpt.verbose; end

if strcmp(BatchOpt.Mode{1}, 'Load each N-th dataset') || strcmp(BatchOpt.Mode{1}, 'Add each N-th dataset as new color channel')
    step = str2double(BatchOpt.EachNthStep);
    BatchOpt.Filenames = BatchOpt.Filenames(1:step:end);
end

% add mibPath to options for io.loadImages
options.mibPath = obj.mibPath;
options.parentGUI = obj.mibGUI; % handle to mibGUI window to be a parent for progress dialog
%options.Font = obj.preferences.System.Font; % add font to render dialogs
% init the extension registry
%extReg = io.ExtensionRegistryLoad();
%ext = extReg.getAllowedExtensions('Standard', 'BioFormats', true);

reader = 'Default';
if BatchOpt.UseBioFormats; reader = 'BioFormats'; end
% find a loader that should be used for this specific dataset mode, selected reader and filename extension
loaderInfo = obj.extensionRegistryLoad.resolveLoader(BatchOpt.Filenames{1}, obj.I{obj.id}.datasetType, reader);
if ischar(loaderInfo)
    utils.dlgs.showErrorDialog(obj.mibGUI, loaderInfo, 'io:ExtensionRegistryLoad:NotAllowed');
    notify(obj, 'StopProtocol');
    return;
end

switch BatchOpt.Mode{1}
    case {'Combine datasets', 'Load each N-th dataset', 'Load part of dataset', 'Combine files as color channels'}
        if strcmp(obj.I{BatchOpt.id}.datasetType, 'Virtual') && strcmp(BatchOpt.Mode{1}, 'Combine files as color channels')
            toolname = 'The colors can not be combined in the virtual stacking mode.';
            errorText = sprintf('!!! Warning !!!\n\n%s\nPlease switch to the memory-resident mode and try again', toolname);
            utils.dlgs.showErrorDialog(obj.mibGUI, errorText, 'Not implemented');
            notify(obj, 'StopProtocol');
            return;
        end

        if obj.I{obj.id}.modelExist == 1 && nargin < 3
            dlgText = sprintf(['!!! Warning !!!\nYou are going to load a new dataset!\n\nMeanwhile you have an open model\n' ...
                'would you like to continue?']);
            selection = uiconfirm(obj.mibGUI, ...
                dlgText, 'Load dataset', ...
                'Options', ["Load dataset", "Cancel"], 'DefaultOption', 2, 'CancelOption', 2, ...
                'Icon', 'warning');
            if strcmp(selection, 'Cancel'); return; end
        end

        if strcmp(BatchOpt.Mode{1}, 'Load part of dataset')
            options.customSections = 1;     % to load part of the dataset, for AM, TIF only
            % check for correct extensions
            [~,~,extList] = fileparts(BatchOpt.Filenames);
            if sum(~ismember(lower(unique(extList)), {'.tif', '.tiff', '.am'})) > 0 && ~options.UseBioFormats
                errorText = sprintf('MibModel.loadImages\n\nIt is only possible to load part of the dataset for AM and TIF formats!');
                utils.dlgs.showErrorDialog(obj.mibGUI, errorText, 'Wrong format!');
                notify(obj, 'StopProtocol');
                return;
            end
        end

        if ~isempty(BatchOpt.BioFormatsIndices)
            options.BioFormatsIndices = str2num(BatchOpt.BioFormatsIndices); %#ok<ST2NM>
        else
            if batchModeSwitch == 1    % batch mode is used
                options.BioFormatsIndices = BatchOpt.BioFormatsIndices;
            end
        end

        % Create file loader
        loader = io.LoaderFactory.create(loaderInfo, options);
        if isempty(loader); notify(obj, 'StopProtocol'); return; end

        % Load metadata (img_info dictionary) and populate structure array with files information (files)
        [img_info, files] = loader.loadMetadata(BatchOpt.Filenames, options);
        if img_info.numEntries == 0
            notify(obj, 'StopProtocol');
            return;
        end

        % main loader for z-stacks
        if ~strcmp(BatchOpt.Mode{1}, 'Combine files as color channels')
            if options.customSections && isfield(obj.sessionSettings, 'customSections')
                % obj.sessionSettings.customSections - has the previously defined subvolume to load
                options.customSectionsSettings = obj.sessionSettings.customSections;
            end

            % Load images
            [img, img_info] = loader.loadImages(files, img_info, options);
            if isempty(img)
                errorText = sprintf(['MibModel.loadImages\n\nIt is not possible to load the dataset...\n' ...
                    'Dimensions mismatch or cancelled?']);
                utils.dlgs.showErrorDialog(obj.mibGUI, errorText, 'Wrong file');
                notify(obj, 'StopProtocol');
                return;
            end

            % store the selection for subvolume to load to reuse next time
            if options.customSections && isfield(files, 'xMin')
                obj.sessionSettings.customSections.xMin = files(1).xMin;
                obj.sessionSettings.customSections.xMax = files(1).xMax;
                obj.sessionSettings.customSections.yMin = files(1).yMin;
                obj.sessionSettings.customSections.yMax = files(1).yMax;
                obj.sessionSettings.customSections.zMin = files(1).zMin;
                obj.sessionSettings.customSections.zMax = files(1).zMax;
                obj.sessionSettings.customSections.xyStep = files(1).xyStep;
            end
        else
            for colChannelId = 1:numel(BatchOpt.Filenames)
                if colChannelId==1
                    [img_temp, img_info] = loader.loadImages(files(1), img_info, options);
                    if isempty(img_temp)
                        errorText = sprintf(['MibModel.loadImages\n\nIt is not possible to load the dataset as color channels...\n' ...
                                             'Dimensions mismatch or cancelled?']);
                        utils.dlgs.showErrorDialog(obj.mibGUI, errorText, 'Wrong file');
                        notify(obj, 'StopProtocol');
                        return;
                    end

                    noColorsInFile = img_info{'Colors'}; % number of color channels in the first file
                    noColorsInResult = img_info{'Colors'}*numel(BatchOpt.Filenames); % total number of color channels in the combined file

                    img = zeros([img_info{'Height'}, img_info{'Width'}, img_info{'Depth'}, noColorsInResult, img_info{'Time'}], img_info{'imgClass'});
                    img(:, :, :, 1:noColorsInFile, :) = img_temp;
                    % correct lutColors
                    lutColors = zeros(noColorsInResult, 3);
                    if isKey(img_info, 'lutColors')
                        lutTemp = img_info{'lutColors'};
                        lutColors(1:noColorsInFile, :) = lutTemp(1:noColorsInFile);
                    end
                else
                    [img_temp, img_info_temp] = loader.loadImages(files(colChannelId), img_info, options);
                    if isempty(img_temp)
                        errorText = sprintf(['MibModel.loadImages\n\nIt is not possible to load the dataset as color channels...\n' ...
                                             'Dimensions mismatch or cancelled?']);
                        utils.dlgs.showErrorDialog(obj.mibGUI, errorText, 'Wrong file');
                        notify(obj, 'StopProtocol');
                        return;
                    end

                    if img_info{'Height'} ~= img_info_temp{'Height'} || img_info{'Width'} ~= img_info_temp{'Width'} || ...
                            img_info{'Depth'} ~= img_info_temp{'Depth'} || img_info{'Time'} ~= img_info_temp{'Time'}
                        errorText = sprintf(['MibModel.loadImages\n\nDimensions mismatch!\n' ...
                            'When combining colors please make sure that your images have the same Height, Width, Depth and Time dimensions']);
                        utils.dlgs.showErrorDialog(obj.mibGUI, errorText, 'Dimensions mismatch');
                        notify(obj, 'StopProtocol');
                        return;
                    end
                    
                    img(:, :, :, colChannelId*noColorsInFile-noColorsInFile+1:colChannelId*noColorsInFile,:) = img_temp;
                    if isKey(img_info_temp, 'lutColors')
                        lutTemp = img_info_temp{'lutColors'};
                        lutColors(colChannelId*noColorsInFile-noColorsInFile+1:colChannelId*noColorsInFile, :) = lutTemp(1:noColorsInFile);
                    end
                end
            end
            
            % update img_info
            img_info{'ColorType'} = 'multichannel';
            if isKey(img_info, 'lutColors')
                img_info{'lutColors'} = lutColors;
            end
            img_info{'Colors'} = noColorsInResult;
        end

        % % check that Zarr is opened in correct mode
        % if isscalar(BatchOpt.Filenames) && isfolder(BatchOpt.Filenames{1})
        %     [~, ~, ext] = fileparts(BatchOpt.Filenames{1}); % get extension
        %     if ismember(ext, {'.zarr', '.zarr2', '.zarr3'}) 
        %         % init python environment
        %         if isempty(obj.pythonEnv)
        %             try
        %                 obj.pythonEnv = pyenv( ...
        %                     'Version', obj.preferences.ExternalDirs.PythonInstallationPath, ...
        %                     'ExecutionMode', 'OutOfProcess');     % InProcess or OutOfProcess
        %             catch err
        %                 if strcmp(err.identifier, 'MATLAB:Pyenv:PythonLoaded')
        %                     terminate(pyenv);
        %                     obj.pythonEnv = pyenv( ...
        %                         'Version', obj.preferences.ExternalDirs.PythonInstallationPath, ...
        %                         'ExecutionMode', 'OutOfProcess');     % InProcess or OutOfProcess
        %                 end
        %             end
        %         end
        %     end
        % end

        %options.virtual = strcmp(obj.I{BatchOpt.id}.datasetType, 'Virtual');
        
        % enable fast panning mode for ome-zarr
        if isKey(img_info, 'Pyramid')
            % set the pan mode to the fast-pan
            Options.button = 'fastpan';
            Options.state = true;
            eventdata = core.ToggleEventData(Options);
            notify(obj, 'UpdateToolbar', eventdata);
            %obj.mibView.handles.toolbarFastPanMode.State = 'on'; 
        end

        obj.I{BatchOpt.id}.initialize(img, img_info);
        notify(obj, 'NewDataset');   % notify mibController about a new dataset; see function obj.Listner2_Callback for details
        
        obj.I{obj.id}.lastSegmSelection = [2 1];  % last selected contour for use with the 'e' button
        notify(obj, 'ShowImage');
        
        % update list of recent directories
        dirPos = ismember(obj.preferences.System.Dirs.RecentDirs, BatchOpt.DirectoryName{1});
        if sum(dirPos) == 0
            % add directory to the list
            obj.preferences.System.Dirs.RecentDirs = [obj.currentDirectory obj.preferences.System.Dirs.RecentDirs];    % add the new folder to the list of folders
            if numel(obj.preferences.System.Dirs.RecentDirs) > obj.preferences.System.Dirs.RecentDirsNumber    % trim the list
                obj.preferences.System.Dirs.RecentDirs = obj.preferences.System.Dirs.RecentDirs(1:obj.preferences.System.Dirs.RecentDirsNumber);
            end
            notify(obj, 'UpdateRecentDirsList'); % update the list of recent directories under Open Image button
        elseif dirPos(1) ~= 1
            % re-sort the list and put the opened folder to the top of the list
            obj.preferences.System.Dirs.RecentDirs = [obj.preferences.System.Dirs.RecentDirs(dirPos==1) obj.preferences.System.Dirs.RecentDirs(dirPos==0)];
            notify(obj, 'UpdateRecentDirsList'); % update the list of recent directories under Open Image button
        end
        
        % count user's points
        obj.preferences.Users.Tiers.numberOfLoadedDatasets = obj.preferences.Users.Tiers.numberOfLoadedDatasets+1;
        %notify(obj, 'updateUserScore');     % update score using default obj.preferences.Users.singleToolScores increase
    case 'Insert into open dataset'
        if batchModeSwitch == 0
            prompts = {'Dimension:'; ...
                sprintf('Position\n1 - beginning of the open dataset\n0 - end of the open dataset\nor type any number to define position')};
            if obj.I{BatchOpt.id}.Virtual.virtual == 0
                defAns = {{'depth', 'time', 1}; '0'};
            else
                defAns = {{'depth', 1}; '0'};    
            end
            options.PromptLines = [1, 4];
            dlgtitle = 'Insert dataset';
            options.Title = 'Where the new dataset should be inserted?';
            options.TitleLines = 1;
            options.Focus = 2;
            output = mibInputMultiDlg([], prompts, defAns, dlgtitle, options);
            if isempty(output); return; end
            insertPosition = str2double(output{2});
            options.dim = output{1};
        else
            insertPosition = str2double(BatchOpt.InsertDatasetPosition);
            options.dim = BatchOpt.InsertDatasetDimension{1};
            options.bgColor = str2double(BatchOpt.InsertDatasetPosition);
        end
        options.virtual = obj.I{BatchOpt.id}.Virtual.virtual;
        [img, img_info, ~] = mibLoadImages(BatchOpt.Filenames, options);
        obj.I{BatchOpt.id}.insertSlice(img, insertPosition, img_info, options);
        
        if obj.mibView.handles.mibLutCheckbox.Value == 1
            obj.I{BatchOpt.id}.slices{3} = 1:obj.I{BatchOpt.id}.meta('Colors');
        else
            obj.I{BatchOpt.id}.slices{3} = 1:min([obj.I{BatchOpt.id}.meta('Colors') 3]);
        end
        notify(obj, 'newDataset');   % notify mibView about a new dataset; see function obj.mibView.Listner2_Callback for details
        obj.plotImage(1);
    case {'Add as new color channel' 'Add each N-th dataset as new color channel'}   % add color channel
        if obj.I{BatchOpt.id}.Virtual.virtual == 1
            toolname = 'The color channels can not be added in the virtual stacking mode.';
            warndlg(sprintf('!!! Warning !!!\n\n%s\nPlease switch to the memory-resident mode and try again', ...
                toolname), 'Not implemented');
            notify(obj, 'StopProtocol');
            return;
        end

        [img, img_info, ~] = mibLoadImages(BatchOpt.Filenames, options);
        if isempty(img(1)); notify(obj, 'StopProtocol'); return; end
        
        if isKey(img_info, 'lutColors')
            lutColors = img_info('lutColors');
            lutColors = lutColors(1:size(img,3),:);
        else
            lutColors = NaN;
        end
        
        result = obj.I{BatchOpt.id}.addColorChannel(img, NaN, lutColors);
        if result == 0; notify(obj, 'StopProtocol'); return; end
        notify(obj, 'newDataset');   % notify mibView about a new dataset; see function obj.mibView.Listner2_Callback for details
        obj.plotImage(1);
end

end