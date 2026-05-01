classdef MibDeepAugmentSettings < handle
% MIBDEEPAUGMENTSETTINGS - @type MibDeepAugmentSettings class is a template class for using with.
%
% GUI developed using appdesigner of Matlab
%
%
% .. code-block:: matlab
%
%   obj.startController('controllers.MibDeepAugmentSettings', obj, '2D'); // as GUI tool
%
% or
%
% .. code-block:: matlab
%
%   // a code below was used for mibImageArithmeticController
%   BatchOpt.Parameter = 'test';  // fill edit boxes as strings
%   BatchOpt.Checkbox = true;     // fill checkboxes with logicals: true/false
%   BatchOpt.Popup = {'value'};        // value for the popups as a cell
%   BatchOpt.Radio = {'Radio1'};          // selection of radio buttons, as cell with the handle of the target radio button
%   BatchOpt.showWaitbar = true;  // show or not the waitbar
%   obj.startController('MibDeepAugmentSettings', [], BatchOpt); // start MibDeepAugmentSettings in the batch mode
%
% or
%
% .. code-block:: matlab
%
%   // trigger return of the possible Options using returnBatchOpt function
%   // using notify syncBatch event
%   obj.startController('MibDeepAugmentSettings', [], NaN);
    
	% Updates
	%     
    
    properties
        mibModel
        % handles to mibModel
        view
        % handle to the view / mibDeepAugmentSettingsGUI
        listener
        % a cell array with handles to listeners
        BatchOpt
        % a structure compatible with batch operation
        % name of each field should be displayed in a tooltip of GUI
        % it is recommended that the Tags of widgets match the name of the
        % fields in this structure
        % .Parameter - [editbox], char/string 
        % .Checkbox - [checkbox], logical value true or false
        % .Dropdown{1} - [dropdown],  cell string for the dropdown
        % .Dropdown{2} - [optional], an array with possible options
        % .Radio - [radiobuttons], cell string 'Radio1' or 'Radio2'...
        % .ParameterNumeric{1} - [numeric editbox], cell with a number 
        % .ParameterNumeric{2} - [optional], vector with limits [min, max]
        % .ParameterNumeric{3} - [optional], string 'on' - to round the value, 'off' to do not round the value
        mibDeep
        % a handle to parent mibDeep controller
        augmentationMode
        % a string defining 2D or 3D augmentations to setup
        augOptions
        % copy of augmented options obj.obj.AugOpt2D or obj.obj.AugOpt3D
        lastSeed
        % last random seed used
    end
    
    events
        %> Description of events
        CloseEvent
        % event firing when window is closed
    end
    
    methods (Static)
        function ViewListner_Callback(obj, src, evnt)
            switch evnt.EventName
                case {'UpdateGuiWidgets'}
                    obj.updateWidgets();
            end
        end
    end
    
    methods
        function obj = MibDeepAugmentSettings(mibModel, varargin)
            obj.mibModel = mibModel;    % assign model
            obj.mibDeep = varargin{1};
            obj.augmentationMode = varargin{2};
            obj.lastSeed = 1;   % last random seed used for preview 

            switch obj.augmentationMode
                case '2D'
                    obj.augOptions = obj.mibDeep.AugOpt2D;
                case '3D'
                    obj.augOptions = obj.mibDeep.AugOpt3D;
            end

            guiName = 'views.MibDeepAugmentSettingsGUI';
            obj.view = core.ChildView(obj, guiName); % initialize the view
            
            % disable widgets that are not for 2D
            if strcmp(obj.augmentationMode, '2D')
                obj.view.handles.RandZReflection_Enable.Value = false;
                obj.view.handles.RandZReflection_Enable.Enable = 'off';
                obj.view.handles.RandZReflection_Probability.Enable = 'off';
                obj.view.handles.RandZReflection_Preview.Enable = 'off';
                obj.view.gui.Name = sprintf('2D augmentation settings');
            else
                obj.view.gui.Name = sprintf('2.5D and 3D augmentation settings');
            end

            % update font and size
            Font = obj.mibModel.preferences.System.Font;
            if obj.view.handles.infoText.FontSize ~= Font.FontSize ...
                    || ~strcmp(obj.view.handles.infoText.FontName, Font.FontName)
                utils.fontSizeUpdate(obj.view.gui, Font);
            end

            % move the window to the left hand side of the main window
            obj.view.gui = utils.moveWindowOutside(obj.view.gui, obj.mibModel.mibGUI, 'center', 'center');
            
			obj.updateWidgets();
			
            % add handle tags to the tooltips
            if obj.mibModel.preferences.System.DeveloperMode
                utils.overrideDescriptions(obj.view.handles, true, 'obj.view.handles');
            end

            % show the gui
            obj.view.gui.Visible = 'on';    % turn on the window 
			
			% add listener to obj.mibModel and call controller function as a callback
            obj.listener{1} = addlistener(obj.mibModel, 'UpdateGuiWidgets', @(src,evnt) obj.ViewListner_Callback(obj, src, evnt));    % listen changes in number of ROIs
        end
        
        function closeWindow(obj)
            % CLOSEWINDOW - closing MibDeepAugmentSettings window.
            %
            % Syntax:
            %   function closeWindow(obj)
            %
            if isvalid(obj.view.gui)
                delete(obj.view.gui);   % delete childController window
            end
            
            % delete listeners, otherwise they stay after deleting of the
            % controller
            for i=1:numel(obj.listener)
                delete(obj.listener{i});
            end
            
            notify(obj, 'CloseEvent');      % notify mibController that this child window is closed
        end
        
        function updateWidgets(obj, widgetGroup)
            % UPDATEWIDGETS - update widgets of this window.
            %
            % Syntax:
            %   function updateWidgets(obj, widgetGroup)
            %

            % Parameters:
            % widgetGroup: tag of a widget group that gets affected

            if nargin < 2; widgetGroup = []; end

            obj.view.handles.Fraction.Value = obj.augOptions.Fraction;
            obj.view.handles.FillValue.Value = obj.augOptions.FillValue;

            doubleParamtersTags = {'RandXReflection', 'RandYReflection', ...
                'Rotation90', 'ReflectedRotation90', 'PoissonNoise'};

            tripleParamtersTags = {'RandRotation', 'GaussianNoise', 'ImageBlur', ...
                'RandScale', 'RandXScale', 'RandYScale', 'RandXShear', 'RandYShear', ...
                'BrightnessJitter', 'ContrastJitter', 'HueJitter', 'SaturationJitter'};
            
            % add additional 3D augmentations
            if strcmp(obj.augmentationMode, '3D')
                doubleParamtersTags = [doubleParamtersTags, 'RandZReflection'];
            end

            for tagId=1:numel(doubleParamtersTags)
                if isempty(widgetGroup) || strcmp(widgetGroup, doubleParamtersTags{tagId})
                    handleEnable = [doubleParamtersTags{tagId} '_Enable'];
                    handleProbability = [doubleParamtersTags{tagId} '_Probability'];
                    handlePreview = [doubleParamtersTags{tagId} '_Preview'];
                    obj.view.handles.(handleEnable).Value = obj.augOptions.(doubleParamtersTags{tagId}).Enable;
                    obj.view.handles.(handleProbability).Value = obj.augOptions.(doubleParamtersTags{tagId}).Probability;
                    if obj.view.handles.(handleEnable).Value
                        obj.view.handles.(handleProbability).Enable = 'on';
                        obj.view.handles.(handlePreview).Enable = 'on';
                    else
                        obj.view.handles.(handleProbability).Enable = 'off';
                        obj.view.handles.(handlePreview).Enable = 'off';
                    end
                end
            end

            for tagId=1:numel(tripleParamtersTags)
                if isempty(widgetGroup) || strcmp(widgetGroup, tripleParamtersTags{tagId})
                    handleEnable = [tripleParamtersTags{tagId} '_Enable'];
                    handleProbability = [tripleParamtersTags{tagId} '_Probability'];
                    handleMin = [tripleParamtersTags{tagId} '_Min'];
                    handleMax = [tripleParamtersTags{tagId} '_Max'];
                    handlePreview = [tripleParamtersTags{tagId} '_Preview'];

                    obj.view.handles.(handleEnable).Value = obj.augOptions.(tripleParamtersTags{tagId}).Enable;
                    obj.view.handles.(handleProbability).Value = obj.augOptions.(tripleParamtersTags{tagId}).Probability;
                    obj.view.handles.(handleMin).Value = obj.augOptions.(tripleParamtersTags{tagId}).Min;
                    obj.view.handles.(handleMax).Value = obj.augOptions.(tripleParamtersTags{tagId}).Max;
                    if obj.view.handles.(handleEnable).Value
                        obj.view.handles.(handleProbability).Enable = 'on';
                        obj.view.handles.(handleMin).Enable = 'on';
                        obj.view.handles.(handleMax).Enable = 'on';
                        obj.view.handles.(handlePreview).Enable = 'on';
                    else
                        obj.view.handles.(handleProbability).Enable = 'off';
                        obj.view.handles.(handleMin).Enable = 'off';
                        obj.view.handles.(handleMax).Enable = 'off';
                        obj.view.handles.(handlePreview).Enable = 'off';
                    end
                end
            end
        end
        
        function enableStateChange(obj, event)
            % ENABLESTATECHANGE - callback on press of enable checkboxes - enable or disable.
            %
            % Syntax:
            %   function enableStateChange(obj, event)
            %
            % the selected augmentation

            augmenterName = event.Source.Tag(1:strfind(event.Source.Tag, '_')-1);
            obj.augOptions.(augmenterName).Enable = event.Source.Value;
            obj.updateWidgets(augmenterName);
        end

        function updateAugmentationParameters(obj, event)
            % UPDATEAUGMENTATIONPARAMETERS - callback on change of spinboxes - change settings for.
            %
            % Syntax:
            %   function updateAugmentationParameters(obj, event)
            %
            % augmentations

            switch event.Source.Tag
                case {'Fraction', 'FillValue'}
                    obj.augOptions.(event.Source.Tag) = event.Source.Value;
                otherwise
                    augmenterName = event.Source.Tag(1:strfind(event.Source.Tag, '_')-1);
                    augmenterParameter = event.Source.Tag(strfind(event.Source.Tag, '_')+1:end);
                    obj.augOptions.(augmenterName).(augmenterParameter) = event.Source.Value;
                    if event.Source.Value == 0 && strcmp(augmenterParameter, 'Probability')
                        obj.augOptions.(augmenterName).Enable = false;
                        obj.updateWidgets(augmenterName);
                    end

            end
        end

        function disableAugmentations(obj)
            % DISABLEAUGMENTATIONS - disable all augmentations.
            %
            % Syntax:
            %   function disableAugmentations(obj)
            %
            
            augmentationNames = fieldnames(obj.augOptions);
            for augId = 1:numel(augmentationNames)
                switch augmentationNames{augId}
                    case {'Fraction', 'FillValue'}
                        continue;
                    otherwise
                        obj.augOptions.(augmentationNames{augId}).Enable = false;
                end
            end
            obj.updateWidgets();
        end

        function resetAugmentations(obj)
            % RESETAUGMENTATIONS - resetAugmentations(obj).
            %
            % Syntax:
            %   function resetAugmentations(obj)
            %
            % reset augmentation settings to their default values
            
            obj.augOptions = deepmib.generateDefaultAugmentations(obj.augmentationMode);
            obj.updateWidgets();
        end

        function setPreviewAugmentationSettings(obj)
            % SETPREVIEWAUGMENTATIONSETTINGS - update settings for preview of augmented patches.
            %
            % Syntax:
            %   function setPreviewAugmentationSettings(obj)
            %
            
            if ~isfield(obj.mibDeep.PatchPreviewOpt, 'imageSize'); obj.mibDeep.PatchPreviewOpt.imageSize = 160; end

            colorList = {'blue', 'green', 'red', 'cyan', 'magenta', 'yellow','black', 'white'};
            prompts = { 'Number of patches to show [def=9]';...
                'Patch size in pixels'; ...
                'Show information label [def=true]';...
                'Label size [def=9]'; ...
                'Label color [def=black]'; ...
                'Label background color [def=yellow]'; ...
                'Label background opacity [def=0.6]'};
            % defAns = {num2str(obj.mibDeep.PatchPreviewOpt.noImages); ...
            %     num2str(obj.mibDeep.PatchPreviewOpt.imageSize); ...
            %     obj.mibDeep.PatchPreviewOpt.labelShow; ...
            %     num2str(obj.mibDeep.PatchPreviewOpt.labelSize); ...
            %     [colorList, {find(ismember(colorList, obj.mibDeep.PatchPreviewOpt.labelColor)==1)}]; ...
            %     [colorList, {find(ismember(colorList, obj.mibDeep.PatchPreviewOpt.labelBgColor)==1)}]; ...
            %     num2str(obj.mibDeep.PatchPreviewOpt.labelBgOpacity) };

            defAns = {struct('Spinner', true, 'Value', obj.mibDeep.PatchPreviewOpt.noImages, 'Limits', [1 Inf], 'Step', 1, 'Round', true); ...
                      struct('Spinner', true, 'Value', obj.mibDeep.PatchPreviewOpt.imageSize, 'Limits', [1 Inf], 'Step', 1, 'Round', true); ...
                      obj.mibDeep.PatchPreviewOpt.labelShow; ...
                      struct('Spinner', true, 'Value', obj.mibDeep.PatchPreviewOpt.labelSize, 'Limits', [1 100], 'Step', 1, 'Round', true); ...
                [colorList, {find(ismember(colorList, obj.mibDeep.PatchPreviewOpt.labelColor)==1)}]; ...
                [colorList, {find(ismember(colorList, obj.mibDeep.PatchPreviewOpt.labelBgColor)==1)}]; ...
                struct('Spinner', true, 'Value', obj.mibDeep.PatchPreviewOpt.labelBgOpacity, 'Limits', [0 1], 'Step', 0.1, 'Round', false) };

            dlgTitle = 'Augmented patch preview settings';
            options.Focus = 1;      % [optional] define index of the widget to get focus
            options.WindowHeight = 380;
            
            [answer, selIndex] = utils.dlgs.inputUniversalDlg(obj.view.gui, '', prompts, defAns, dlgTitle, options);
            if isempty(answer); return; end

            obj.mibDeep.PatchPreviewOpt.noImages = answer{1};
            obj.mibDeep.PatchPreviewOpt.imageSize = answer{2};
            obj.mibDeep.PatchPreviewOpt.labelShow = logical(answer{3});
            obj.mibDeep.PatchPreviewOpt.labelSize = answer{4};
            obj.mibDeep.PatchPreviewOpt.labelColor = answer{5};
            obj.mibDeep.PatchPreviewOpt.labelBgColor = answer{6};
            obj.mibDeep.PatchPreviewOpt.labelBgOpacity = answer{7};
        end

        function previewAugmentations(obj, selectedAugmentation)
            % PREVIEWAUGMENTATIONS - previewAugmentations(obj, selectedAugmentation).
            %
            % Syntax:
            %   function previewAugmentations(obj, selectedAugmentation)
            %
            % preview selected augmentations.
            % The order of shown augmentations depends on the Random seed
            % value within the Train tab of DeepMIB, when 0 a random set of
            % augmentations is used each time, otherwise random generator
            % os always intialized using the provided seed.
            %
            % Input Arguments:
            %   - **selectedAugmentation** — 'string' with the id of the
            %     augmentation to preview. When empty, all augmentations will
            %     be rendered.
            %
            
            global mibPath;
            global mibDeepTrainingProgressStruct
            if nargin < 2; selectedAugmentation = []; end
            
            % check that the selected workflow is matching previewed
            % augmentations
            okToProceed = false;
            if strcmp(obj.augmentationMode, '2D') && strcmp(obj.mibDeep.BatchOpt.Workflow{1}(1:2), '2D')
                okToProceed = true;
            end
            if strcmp(obj.augmentationMode, '3D') && (strcmp(obj.mibDeep.BatchOpt.Workflow{1}(1:2), '3D') || strcmp(obj.mibDeep.BatchOpt.Workflow{1}(1:2), '2.'))
                okToProceed = true;
            end
            if ~okToProceed
                uialert(obj.view.gui, ...
                    sprintf(['!!! Error !!!\n\nYour selected workflow (%s) is not matching the augmentation settings (%s) that you are going to preview!\n\n' ...
                    'Switch the workflow or choose proper augmentation settings!'], ...
                    obj.mibDeep.BatchOpt.Workflow{1}, obj.view.gui.Name), ...
                    'Workflow is not matching augmentations!', 'icon', 'error');
                return;
            end
            
            mibDeepTrainingProgressStruct.emergencyBrake = false;
            
            if obj.view.handles.RandomSeedEdit.Value == 0
                seedId = randi(1e6);         % Pick a random seed
                rng(seedId, 'twister');      % Set the RNG to this seed with twister (shuffles from this point)
                obj.lastSeed = seedId;
            else
                rng(obj.view.handles.RandomSeedEdit.Value, 'twister'); 
                seedId = obj.view.handles.RandomSeedEdit.Value;
            end

            obj.mibDeep.TrainingProgress = struct();    % reset obj.TrainingProgress to make sure that it is closed
            obj.mibDeep.TrainingProgress.emergencyBrake = false;    % to make sure that it won't stop inside transform structure
            inputPatchSize = str2num(obj.mibDeep.BatchOpt.T_InputPatchSize);

            % prepare options for loading of images
            mibDeepStoreLoadImagesOpt.mibBioformatsCheck = obj.mibDeep.BatchOpt.BioformatsTraining;
            mibDeepStoreLoadImagesOpt.BioFormatsIndices = obj.mibDeep.BatchOpt.BioformatsTrainingIndex{1};
            mibDeepStoreLoadImagesOpt.Workflow = obj.mibDeep.BatchOpt.Workflow{1};

            % the other options are not available, require to process images
            try
                if strcmp(obj.mibDeep.BatchOpt.PreprocessingMode{1}, 'Preprocessing is not required') || strcmp(obj.mibDeep.BatchOpt.PreprocessingMode{1}, 'Split files for training/validation')
                    fnExtention = lower(['.' obj.mibDeep.BatchOpt.ImageFilenameExtensionTraining{1}]);

                    % check for the classification type training
                    if strcmp(obj.mibDeep.BatchOpt.Workflow{1}, '2D Patch-wise')
                        % get folders with class names
                        fileList = dir(fullfile(obj.mibDeep.BatchOpt.OriginalTrainingImagesDir, 'TrainImages'));
                        fileList = fileList([fileList.isdir]);
                        if numel(fileList) > 2 % remove '.' and '..'
                            fileList(1:2) = [];
                        end
                        prompts = {'Select label class to show'};
                        defAns = {{fileList.name}'};
                        dlgTitle = 'Label selection';
                        [answer, selIndex] = mibInputMultiDlg({mibPath}, prompts, defAns, dlgTitle);
                        if isempty(answer); return; end
                        inputPath = fullfile(obj.mibDeep.BatchOpt.OriginalTrainingImagesDir, 'TrainImages', fileList(selIndex).name);
                    else
                        inputPath = fullfile(obj.mibDeep.BatchOpt.OriginalTrainingImagesDir, 'TrainImages');
                    end
                    imgDS = imageDatastore(inputPath, ...
                        'FileExtensions', fnExtention, ...
                        'IncludeSubfolders', false, ...
                        'ReadFcn', @(fn)deepmib.storeLoadImages(fn, mibDeepStoreLoadImagesOpt));
                else        % with preprocessing
                    imgDS = imageDatastore(fullfile(obj.mibDeep.BatchOpt.ResultingImagesDir, 'TrainImages'), ...
                        'FileExtensions', '.mibImg', 'IncludeSubfolders', false, 'ReadFcn', @deepmib.storeLoadImages);
                end
            catch err
                mibShowErrorDialog(obj.view.gui, err, 'Missing files');
                if obj.mibDeep.BatchOpt.showWaitbar; delete(obj.mibDeep.wb); end
                return;
            end

            % generate random patch datastores
            switch obj.mibDeep.BatchOpt.Workflow{1}(1:2)
                case {'3D', '2.'}   % '2.5D Semantic' and '3D Semantic'
                    randomStoreInputPatchSize = [min([obj.mibDeep.PatchPreviewOpt.imageSize inputPatchSize(1)]), ...
                                                 min([obj.mibDeep.PatchPreviewOpt.imageSize, inputPatchSize(2)]), ...
                                                 inputPatchSize(3)];
                    if isempty(selectedAugmentation)    % show all selected augmentations
                        status = obj.mibDeep.setAugFuncHandles('3D', obj.augOptions);   % use current local copy (obj.augOptions) of augmentation settings
                        if status == 0; return; end
                    else
                        obj.mibDeep.Aug3DFuncNames = {selectedAugmentation};
                        if isempty(obj.augOptions.(selectedAugmentation).Min)   % augmentation without variation
                            obj.mibDeep.Aug3DFuncProbability = 0.5;
                        else
                            obj.mibDeep.Aug3DFuncProbability = 1;
                        end
                    end
                case '2D'
                    randomStoreInputPatchSize = [min([obj.mibDeep.PatchPreviewOpt.imageSize inputPatchSize(1)]), ...
                                                 min([obj.mibDeep.PatchPreviewOpt.imageSize, inputPatchSize(2)])];
                    if isempty(selectedAugmentation)    % show all selected augmentations
                        status = obj.mibDeep.setAugFuncHandles('2D', obj.augOptions);   % use current local copy (obj.augOptions) of augmentation settings
                        if status == 0; return; end
                    else
                        obj.mibDeep.Aug2DFuncNames = {selectedAugmentation};
                        if isempty(obj.augOptions.(selectedAugmentation).Min)   % augmentation without variation
                            obj.mibDeep.Aug2DFuncProbability = 0.5;
                        else
                            obj.mibDeep.Aug2DFuncProbability = 1;
                        end
                    end
            end
            noAugmentations = numel(fieldnames(obj.augOptions))-2;  % without Fraction and FillValue fields

            patchDS = randomPatchExtractionDatastore(imgDS, imgDS, randomStoreInputPatchSize, ...
                'PatchesPerImage', 1); %#ok<ST2NM>
            patchDS.MiniBatchSize = 1;

            patchIn = read(patchDS);

            Iout = cell([obj.mibDeep.PatchPreviewOpt.noImages, 1]);
            augOperation = cell([obj.mibDeep.PatchPreviewOpt.noImages, 1]);
            augParameter = zeros([obj.mibDeep.PatchPreviewOpt.noImages, noAugmentations]);

            % define options for
            mibDeepAugmentOpt.Workflow = obj.mibDeep.BatchOpt.Workflow{1};
            mibDeepAugmentOpt.T_ConvolutionPadding = obj.mibDeep.BatchOpt.T_ConvolutionPadding{1};
            mibDeepAugmentOpt.O_PreviewImagePatches = obj.mibDeep.BatchOpt.O_PreviewImagePatches;
            mibDeepAugmentOpt.O_FractionOfPreviewPatches = obj.mibDeep.BatchOpt.O_FractionOfPreviewPatches{1};
            
            t1 = tic;
            for z=1:obj.mibDeep.PatchPreviewOpt.noImages
                if strcmp(obj.mibDeep.BatchOpt.Workflow{1}(1:2), '2D')
                    mibDeepAugmentOpt.AugOpt2D = obj.augOptions;
                    mibDeepAugmentOpt.Aug2DFuncNames = obj.mibDeep.Aug2DFuncNames;
                    mibDeepAugmentOpt.Aug2DFuncProbability = obj.mibDeep.Aug2DFuncProbability;
                    [augPatch, info, augOperation(z), augParameter(z,:)] = deepmib.augmentAndCrop2dPatchMultiGPU(patchIn, [], inputPatchSize, inputPatchSize, 'aug', mibDeepAugmentOpt); %#ok<ASGLU>
                    Iout{z} = augPatch.inpVol{1};
                else
                    mibDeepAugmentOpt.AugOpt3D = obj.augOptions;
                    mibDeepAugmentOpt.Aug3DFuncNames = obj.mibDeep.Aug3DFuncNames;
                    mibDeepAugmentOpt.Aug3DFuncProbability = obj.mibDeep.Aug3DFuncProbability;
                    [augPatch, info, augOperation(z), augParameter(z,:)] = deepmib.augmentAndCrop3dPatchMultiGPU(patchIn, [], inputPatchSize, inputPatchSize, 'aug', mibDeepAugmentOpt); %#ok<ASGLU>
                    Iout{z} = squeeze(augPatch.inpVol{1}(:,:, ceil(size(augPatch.inpVol{1},3)/2),:));
                end

                if inputPatchSize(4) == 2
                    Iout{z}(:,:,3) = zeros([randomStoreInputPatchSize(1) randomStoreInputPatchSize(2)]);
                end
            end
            t2 = toc(t1);
            if obj.mibDeep.PatchPreviewOpt.labelShow
                for z=1:obj.mibDeep.PatchPreviewOpt.noImages
                    textString = sprintf('%s\n%s', strjoin(augOperation{z}, ','), num2str(augParameter(z, 1:numel(augOperation{z}))));
                    Iout{z} = insertText(Iout{z}, [1 1], ...
                        textString, 'FontSize', obj.mibDeep.PatchPreviewOpt.labelSize, ...
                        'TextColor', obj.mibDeep.PatchPreviewOpt.labelColor, ...
                        'BoxColor', obj.mibDeep.PatchPreviewOpt.labelBgColor, ...
                        'BoxOpacity', obj.mibDeep.PatchPreviewOpt.labelBgOpacity);
                end
            end

            rng('shuffle');
            hFig = figure(randi(1000));
            montage(Iout, 'BorderSize', 5);
            uicontrol(hFig, 'style', 'text', ...
                'Position', [20, 20, 400, 20], ...
                'String', sprintf('SeedId: %d; calculation performance: %f seconds per image', seedId, t2/obj.mibDeep.PatchPreviewOpt.noImages));
        end

        function help(obj)
            % HELP - direct to help.
            %
            % Syntax:
            %   function help(obj)
            %
            
            web(fullfile(obj.mibModel.mibPath, 'techdoc', 'html', 'ug_gui_menu_tools_deeplearning_train.html'), '-helpbrowser');
        end

        function restorePreviousSeed(obj)
            % RESTOREPREVIOUSSEED - restore the previous seed used in random settings.
            %
            % Syntax:
            %   function restorePreviousSeed(obj)
            %
            
            obj.view.handles.RandomSeedEdit.Value = double(obj.lastSeed);
        end


        % ------------------------------------------------------------------
        % % Additional functions and callbacks
        function Accept(obj)
            % ACCEPT - accept selected augmentations.
            %
            % Syntax:
            %   function Accept(obj)
            %

            % disable augmentations with 0/1 variability
            %
            % one of other ways to switch off augmentation was to make the
            % variation to 0 or 1
            augsDisabledWhenVariationZero = {'RandRotation', 'GaussianNoise', 'ImageBlur', ...
                                   'RandXShear', 'RandYShear', 'BrightnessJitter', ...
                                   'HueJitter', 'SaturationJitter'};
            augsDisabledWhenVariationOne = {'RandScale', 'RandXScale', 'RandYScale', ...
                                   'ContrastJitter'};

            augNames = fieldnames(obj.augOptions);
            for fieldId=1:numel(augNames)
                if ismember(augNames{fieldId}, augsDisabledWhenVariationZero) && ...
                            obj.augOptions.(augNames{fieldId}).Min == 0 && obj.augOptions.(augNames{fieldId}).Max == 0
                    obj.augOptions.(augNames{fieldId}).Enable = false;
                end
                if ismember(augNames{fieldId}, augsDisabledWhenVariationOne) && ...
                            obj.augOptions.(augNames{fieldId}).Min == 1 && obj.augOptions.(augNames{fieldId}).Max == 1
                    obj.augOptions.(augNames{fieldId}).Enable = false;
                end
            end

            switch obj.augmentationMode
                case '2D'
                    obj.mibDeep.AugOpt2D = obj.augOptions;
                case '3D'
                    obj.mibDeep.AugOpt3D = obj.augOptions;
            end
            obj.closeWindow();
        end
        
        
    end
end
