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

% define defaults for ErrorDlgOpt
ErrorDlgOpt = struct('optionalPrefix', 'Error in MibModel.loadImages', 'WindowHeight', 160);

%% Batch mode check actions
if nargin == 3  % batch mode 
    if isstruct(BatchOptIn) == 0
        if isnan(BatchOptIn)     % when varargin{3} == NaN return possible settings
            % trigger SyncBatch event to send BatchOptInOut to mibBatchController 
            BatchOpt = rmfield(BatchOpt, 'id');     % remove id field
            eventdata = core.ToggleEventData(BatchOpt);
            notify(obj, 'SyncBatch', eventdata);
        else
            ErrorDlgOpt.winTitle = 'BatchOpt Error';
            ErrorDlgOpt.err = 'A structure as the 3rd parameter is required!';
            eventdata = core.ToggleEventData(ErrorDlgOpt);
            notify(obj, 'ShowErrorDialog', eventdata);
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
                ErrorDlgOpt.winTitle = 'No files selected!';
                ErrorDlgOpt.err = 'Please select files in the Directory contents panel and try again!';
                eventdata = core.ToggleEventData(ErrorDlgOpt);
                notify(obj, 'ShowErrorDialog', eventdata);
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
        ErrorDlgOpt.winTitle = 'Files were not selected!';
        ErrorDlgOpt.err = 'Please select files to open in the Directory contents panel!';
        eventdata = core.ToggleEventData(ErrorDlgOpt);
        notify(obj, 'ShowErrorDialog', eventdata);
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
            ErrorDlgOpt.winTitle = 'No files selected!';
            ErrorDlgOpt.err = 'Please select files in the Directory contents panel and try again!';
            eventdata = core.ToggleEventData(ErrorDlgOpt);
            notify(obj, 'ShowErrorDialog', eventdata);
            return; 
        end
        BatchOpt.Filenames = arrayfun(@(filename) fullfile(BatchOpt.DirectoryName{1}, cell2mat(filename)), filenames, 'UniformOutput', false);  % generate full paths
    end

    if strcmp(BatchOpt.Mode{1}, 'Load each N-th dataset') || strcmp(BatchOpt.Mode{1}, 'Add each N-th dataset as new color channel')
        % get the name for a new set
        options.Type = 'spinner';
        options.WindowHeight = 170;
        options.mibPath = obj.mibPath;
        defAns = struct('Value', 2, 'Limits', [1 Inf], 'ValueDisplayFormat', '%d');
        dlgText = sprintf('There are %d file selected; please enter the loading step:\n\nFor example when step is 2 \nMIB loads each second dataset', numel(BatchOpt.Filenames));
        answer = utils.dlgs.inputSingleDlg(obj.mibGUI, dlgText, defAns, 'Enter the step', options);
        if isempty(answer); return; end

        BatchOpt.EachNthStep = num2str(answer);
    end
end

if numel(BatchOpt.Filenames) < 1
    ErrorDlgOpt.winTitle = 'Wrong selection!';
    ErrorDlgOpt.err = sprintf('No files were selected!!!\nPlease select desired files and try again!\nYou can use Ctrl and Shift for the selection.');
    eventdata = core.ToggleEventData(ErrorDlgOpt);
    notify(obj, 'ShowErrorDialog', eventdata);
    notify(obj, 'StopProtocol');
    return; 
end

%% Define additional options
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
options.ParentFigure = obj.mibGUI; % handle to mibGUI window to be a parent for progress dialog
%options.Font = obj.preferences.System.Font; % add font to render dialogs
% init the extension registry
%extReg = io.ExtensionRegistryLoad();
%ext = extReg.getAllowedExtensions('Standard', 'BioFormats', true);

reader = 'Default';
if BatchOpt.UseBioFormats; reader = 'BioFormats'; end
% find a loader that should be used for this specific dataset mode, selected reader and filename extension
loaderInfo = obj.extensionRegistryLoad.resolveLoader(BatchOpt.Filenames{1}, obj.I{obj.id}.datasetType, reader);
if ischar(loaderInfo)
    ErrorDlgOpt.winTitle = 'io:ExtensionRegistryLoad:NotAllowed';
    ErrorDlgOpt.err = loaderInfo;
    eventdata = core.ToggleEventData(ErrorDlgOpt);
    notify(obj, 'ShowErrorDialog', eventdata);
    notify(obj, 'StopProtocol');
    return;
end

%% Main loading loop -------------

switch BatchOpt.Mode{1}
    %% 'Combine datasets', 'Load each N-th dataset', 'Load part of dataset', 'Combine files as color channels'
    case {'Combine datasets', 'Load each N-th dataset', 'Load part of dataset', 'Combine files as color channels'}
        if obj.I{BatchOpt.id}.datasetType(1) == 'V' && strcmp(BatchOpt.Mode{1}, 'Combine files as color channels')
            ErrorDlgOpt.winTitle = 'Not implemented!';
            ErrorDlgOpt.WindowHeight = 170;
            toolname = 'The colors can not be combined in the virtual stacking mode.';
            ErrorDlgOpt.err = sprintf('%s\nPlease switch to the memory-resident mode and try again', toolname);
            eventdata = core.ToggleEventData(ErrorDlgOpt);
            notify(obj, 'ShowErrorDialog', eventdata);
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
            %% 'Load part of dataset' -------------
            options.customSections = 1;     % to load part of the dataset, for AM, TIF only
            % check for correct extensions
            [~,~,extList] = fileparts(BatchOpt.Filenames);
            if sum(~ismember(lower(unique(extList)), {'.tif', '.tiff', '.am'})) > 0 && ~options.UseBioFormats
                ErrorDlgOpt.winTitle = 'Wrong format!';
                ErrorDlgOpt.err = 'It is only possible to load part of the dataset for AM and TIF formats!';
                eventdata = core.ToggleEventData(ErrorDlgOpt);
                notify(obj, 'ShowErrorDialog', eventdata);

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
        if strcmp(BatchOpt.Mode{1}, 'Combine files as color channels')
            %% Combine files as color channels ----------------------------
            nFiles = numel(BatchOpt.Filenames);
            [img_temp, img_info] = loader.loadImages(files(1), img_info, options);
            if isempty(img_temp)
                ErrorDlgOpt.winTitle = 'Wrong file!';
                ErrorDlgOpt.err = sprintf('It is not possible to load the dataset as color channels...\nDimensions mismatch or cancelled?');
                eventdata = core.ToggleEventData(ErrorDlgOpt);
                notify(obj, 'ShowErrorDialog', eventdata);
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
            % grab view port
            viewPort = struct();
            viewPort.min(1:noColorsInFile) = img_info{"viewPort"}.min;
            viewPort.max(1:noColorsInFile) = img_info{"viewPort"}.max;
            viewPort.gamma(1:noColorsInFile) = img_info{"viewPort"}.gamma; %#ok<STRNU>

            % loop other color channels
            for colChannelId = 2:nFiles
                [img_temp, img_info_temp] = loader.loadImages(files(colChannelId), img_info, options);
                if isempty(img_temp)
                    ErrorDlgOpt.winTitle = 'Wrong file!';
                    ErrorDlgOpt.err = sprintf('It is not possible to load the dataset as color channels...\nDimensions mismatch or cancelled?');
                    eventdata = core.ToggleEventData(ErrorDlgOpt);
                    notify(obj, 'ShowErrorDialog', eventdata);
                    notify(obj, 'StopProtocol');
                    return;
                end

                if img_info{'Height'} ~= img_info_temp{'Height'} || img_info{'Width'} ~= img_info_temp{'Width'} || ...
                        img_info{'Depth'} ~= img_info_temp{'Depth'} || img_info{'Time'} ~= img_info_temp{'Time'}

                    ErrorDlgOpt.winTitle = 'Dimensions mismatch!';
                    ErrorDlgOpt.err = sprintf('Dimensions mismatch!\nWhen combining colors please make sure that your images have the same Height, Width, Depth and Time dimensions');
                    eventdata = core.ToggleEventData(ErrorDlgOpt);
                    notify(obj, 'ShowErrorDialog', eventdata);

                    notify(obj, 'StopProtocol');
                    return;
                end

                startChannel = (colChannelId - 1) * noColorsInFile + 1;
                endChannel   = colChannelId * noColorsInFile;

                img(:, :, :, startChannel:endChannel,:) = img_temp;
                if isKey(img_info_temp, 'lutColors')
                    lutTemp = img_info_temp{'lutColors'};
                    lutColors(startChannel:endChannel, :) = lutTemp(1:noColorsInFile);
                end
                % update viewport
                viewPort.min(startChannel:endChannel) = img_info{"viewPort"}.min;
                viewPort.max(startChannel:endChannel) = img_info{"viewPort"}.max;
                viewPort.gamma(startChannel:endChannel) = img_info{"viewPort"}.gamma; %#ok<STRNU>
            end

            % update img_info
            img_info{'ColorType'} = 'multichannel';
            if isKey(img_info, 'lutColors')
                img_info{'lutColors'} = lutColors;
            end
            img_info{'Colors'} = noColorsInResult;
            img_info{'viewPort'} = viewPort;
        else
            %% Combine datasets
            if options.customSections && isfield(obj.sessionSettings, 'customSections')
                % obj.sessionSettings.customSections - has the previously defined subvolume to load
                options.customSectionsSettings = obj.sessionSettings.customSections;
            end

            % Load images
            [img, img_info] = loader.loadImages(files, img_info, options);
            if isempty(img)
                ErrorDlgOpt.winTitle = 'Wrong file!';
                ErrorDlgOpt.err = sprintf('It is not possible to load the dataset...\nDimensions mismatch or cancelled?');
                eventdata = core.ToggleEventData(ErrorDlgOpt);
                notify(obj, 'ShowErrorDialog', eventdata);
                
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

        % Pass BioFormats memoizer path to virtual image so BioFormatsVirtualLoader
        % can open readers without access to MibDataset.bioFormatsMemoizerMemoDir
        if obj.I{BatchOpt.id}.datasetType(1) == 'V'
            obj.I{BatchOpt.id}.image.bioFormatsMemoizerMemoDir = options.bioFormatsMemoizerMemoDir;
        end

        % explicitly sync slices{4} to the new image color count before
        % notifying, so that getRGBimage never indexes lutColors out of bounds
        % when the previously loaded dataset had more color channels
        if obj.I{BatchOpt.id}.useLUT
            obj.I{BatchOpt.id}.slices{4} = 1:obj.I{BatchOpt.id}.image.colors;
        else
            obj.I{BatchOpt.id}.slices{4} = 1:min([obj.I{BatchOpt.id}.image.colors 3]);
        end

        notify(obj, 'NewDataset');   % notify mibController about a new dataset; see function obj.Listner2_Callback for details
        
        obj.I{obj.id}.lastSegmSelection = [2 1];  % last selected contour for use with the 'e' button
        
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
        %% Insert into open dataset -------------
        virtualMode = obj.I{BatchOpt.id}.datasetType(1) == 'V';
        if batchModeSwitch == 0
            dlgOptions = struct;
            dlgOptions.Header = 'Where the new dataset should be inserted?';
            dlgOptions.HeaderLines = 1;
            prompts = {'Dimension:'; ...
                sprintf('Position\n1 - beginning of the open dataset\n0 - end of the open dataset\nor type any number to define position')};
            defAns = {{'depth', 'time', 1}; struct('Spinner', true, 'Value', 0, 'Limits', [0 obj.I{obj.id}.dim_yxzct(3)], 'Step', 1, 'Round', true)};
            dlgOptions.LabelPosition = 'top';
            dlgOptions.WindowHeight = 230;
            dlgOptions.mibPath = obj.mibPath;
            dlgOptions.Focus = 2; % focus on the edit field
            answer = utils.dlgs.inputUniversalDlg(options.ParentFigure, ...
                            prompts, defAns, 'Insert dataset', dlgOptions);
            if isempty(answer); return; end
            options.dim = answer{1};
            insertPosition = answer{2};
        else
            insertPosition = str2double(BatchOpt.InsertDatasetPosition);
            options.dim = BatchOpt.InsertDatasetDimension{1};
            options.bgColor = str2double(BatchOpt.InsertDatasetPosition);
        end
        
        % Create file loader
        loader = io.LoaderFactory.create(loaderInfo, options);
        if isempty(loader); notify(obj, 'StopProtocol'); return; end
        % options.virtual = virtualMode;
        [img_info, files] = loader.loadMetadata(BatchOpt.Filenames, options);
        [img, img_info] = loader.loadImages(files, img_info, options);
        obj.I{obj.id}.insertSlice(img, insertPosition, img_info, options);
        
        if obj.I{BatchOpt.id}.useLUT
            obj.I{BatchOpt.id}.slices{4} = 1:obj.I{BatchOpt.id}.image.colors;
        else
            obj.I{BatchOpt.id}.slices{4} = 1:min([obj.I{BatchOpt.id}.image.colors 3]);
        end
        notify(obj, 'NewDataset');   % notify MibController about a new dataset; see function MibController.listenerNewDataset for details
    case {'Add as new color channel', 'Add each N-th dataset as new color channel'}
        %% Add as new color channel / Add each N-th dataset as new color channel
        if obj.I{BatchOpt.id}.datasetType(1) == 'V'
            ErrorDlgOpt.winTitle = 'Not implemented!';
            ErrorDlgOpt.WindowHeight = 170;
            ErrorDlgOpt.err = sprintf('The color channels can not be added in the virtual stacking mode.\nPlease switch to the memory-resident mode and try again');
            eventdata = core.ToggleEventData(ErrorDlgOpt);
            notify(obj, 'ShowErrorDialog', eventdata);
            notify(obj, 'StopProtocol');
            return;
        end

        % Create file loader and load images
        loader = io.LoaderFactory.create(loaderInfo, options);
        if isempty(loader); notify(obj, 'StopProtocol'); return; end
        [img_info, files] = loader.loadMetadata(BatchOpt.Filenames, options);
        if img_info.numEntries == 0; notify(obj, 'StopProtocol'); return; end
        [img, img_info] = loader.loadImages(files, img_info, options);
        if isempty(img); notify(obj, 'StopProtocol'); return; end

        lutColors = NaN;
        if isKey(img_info, 'lutColors')
            lutTemp = img_info{'lutColors'};
            lutColors = lutTemp(1:img_info{'Colors'}, :);
        end

        addOpts.ParentFigure = options.ParentFigure;
        addOpts.showWaitbar  = options.waitbar;
        result = obj.I{BatchOpt.id}.image.addColorChannel(img, NaN, lutColors, addOpts);
        if result == 0; notify(obj, 'StopProtocol'); return; end

        % update displayed color channels
        if obj.I{BatchOpt.id}.useLUT
            obj.I{BatchOpt.id}.slices{4} = 1:obj.I{BatchOpt.id}.image.colors;
        else
            obj.I{BatchOpt.id}.slices{4} = 1:min([obj.I{BatchOpt.id}.image.colors 3]);
        end
        notify(obj, 'NewDataset');
end

end