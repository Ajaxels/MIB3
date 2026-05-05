classdef CropObjects < handle
% CROPOBJECTS - Child controller for the Crop Image Patches dialog.
%
% Launched from the Annotations context menu.  Crops image patches
% centred on annotation positions and saves them to disk or the
% MATLAB workspace.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.startController('controllers.CropObjects', obj, false, annotationLabels);

    % Updates
    % 

    properties
        mibModel
        % handle to MibModel
        parentController
        % handle to the parent controller (owns BatchOpt)
        view
        % handle to core.ChildView (views.CropObjectsGUI)
        listener
        % cell array with listener handles
        outputDir
        % output directory for saved patches
        outputVar
        % base variable name used when exporting to Matlab workspace
        annotationLabels
        % struct: .positions [Nx4 z,x,y,t] and .names {Nx1 cell}
        sessionSettingsKey
        % key into mibModel.sessionSettings for persisting crop/jitter settings;
        % default (obj.sessionSettingsKey); use 'quantificationCropPatches' for Quantification
    end

    events
        CloseEvent
        % fires when the dialog is closed; caught by parent to purge this child
    end

    methods (Static)
        function ViewListner_Callback2(obj, ~, evnt)
            % VIEWLISTNER_CALLBACK2 - Guard: clean up listeners and return silently if the view was closed.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      CropObjects.ViewListner_Callback2(obj, src, evnt)
            %
            % Input Arguments:
            %   - **obj** — handle to the CropObjects controller instance
            %   - **src** — event source handle (unused)
            %   - **evnt** — event data; ``evnt.EventName`` identifies the event
            %
            % Output Arguments:
            %   (none)
            %
            if ~isvalid(obj) || isempty(obj.view) || ~isvalid(obj.view.gui)
                for i = 1:numel(obj.listener)
                    delete(obj.listener{i});
                end
                return;
            end
            switch evnt.EventName
                case 'UpdateGuiWidgets'
                    obj.updateWidgets();
            end
        end
    end

    methods
        function obj = CropObjects(mibModel, parentController, batchModeSwitch, annotationLabels)
            % CROPOBJECTS - Constructor for the CropObjects controller.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj = CropObjects(mibModel, parentController)
            %      obj = CropObjects(mibModel, parentController, batchModeSwitch, annotationLabels)
            %
            % Input Arguments:
            %   - **mibModel** — handle to MibModel
            %   - **parentController** — handle to the parent Annotations controller
            %   - **batchModeSwitch** — *(optional)* logical; when ``true``, runs in
            %     headless mode without opening the GUI
            %   - **annotationLabels** — *(optional)* struct with annotation crop coordinates
            %
            %     - ``.positions`` — [Nx4] matrix with [z, x, y, t] annotation coordinates
            %     - ``.names`` — {Nx1} cell array of label strings
            %
            % Output Arguments:
            %   - **obj** — new CropObjects controller instance
            %

            if nargin < 4; annotationLabels = []; end
            if nargin < 3; batchModeSwitch = []; end

            obj.mibModel = mibModel;
            obj.parentController = parentController;
            obj.annotationLabels = annotationLabels;

            % Use parent's session key if it defines one, else default to annotations
            if isprop(parentController, 'sessionSettingsKey') && ~isempty(parentController.sessionSettingsKey)
                obj.sessionSettingsKey = parentController.sessionSettingsKey;
            else
                obj.sessionSettingsKey = 'annotationsCropPatches';
            end

            id = obj.mibModel.getActiveId();
            [~, obj.outputVar] = fileparts(obj.mibModel.I{id}.image.filename);
            if isempty(obj.outputVar); obj.outputVar = 'CropOut'; end
            
            obj.outputDir = obj.mibModel.currentDirectory;

            % batch mode: resolve output directory, run silently, skip GUI
            if batchModeSwitch
                cropDest = obj.parentController.BatchOpt.CropObjectsTo{1};
                if ~strcmp(cropDest, 'Crop to MATLAB')
                    outName = obj.parentController.BatchOpt.CropObjectsOutputName;
                    if ~isempty(outName)
                        % absolute path if starts with separator or drive letter, else relative to image dir
                        if outName(1) == filesep || (numel(outName) > 1 && outName(2) == ':')
                            obj.outputDir = outName;
                        else
                            imgDir = fileparts(obj.mibModel.I{id}.image.filename);
                            obj.outputDir = fullfile(imgDir, outName);
                        end
                        if exist(obj.outputDir, 'dir') == 0; mkdir(obj.outputDir); end
                    end
                end
                obj.generatePatches();
                return;
            end

            % initialise the view
            guiName = 'views.CropObjectsGUI';
            obj.view = core.ChildView(obj, guiName);

            obj.addCallbacks();
            obj.updateWidgets();

            obj.view.gui.Icon = fullfile(obj.mibModel.mibPath, 'assets', 'icons', 'mib_icon_16px.png');

            % centre over the parent dialog, or main MIB window as fallback
            parentGui = obj.mibModel.mibGUI;
            if ~isempty(parentController) && isvalid(parentController) && ...
                    ~isempty(parentController.view) && isvalid(parentController.view.gui)
                parentGui = parentController.view.gui;
            end
            drawnow;   % let AppDesigner finish layout before reading position
            obj.view.gui = utils.moveWindowOutside(obj.view.gui, parentGui, 'center', 'center');

            % add handle tags to the tooltips
            if obj.mibModel.preferences.System.DeveloperMode
                utils.overrideDescriptions(obj.view.handles, true, 'obj.view.handles');
            end
            % show the gui
            obj.view.gui.Visible = 'on';

            % register model listeners
            obj.listener{1} = addlistener(obj.mibModel, 'UpdateGuiWidgets', ...
                @(src, evnt) controllers.CropObjects.ViewListner_Callback2(obj, src, evnt));
        end

        % -----------------------------------------------------------------
        function closeWindow(obj)
            % CLOSEWINDOW - Close the dialog and release all listeners.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.closeWindow()
            %
            % Output Arguments:
            %   (none)
            %

            if isvalid(obj.view.gui)
                delete(obj.view.gui);
            end
            for i = 1:numel(obj.listener)
                delete(obj.listener{i});
            end
            notify(obj, 'CloseEvent');
        end

        % -----------------------------------------------------------------
        function addCallbacks(obj)
            % ADDCALLBACKS - Wire all widget callbacks; called once from the constructor.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.addCallbacks()
            %
            % Output Arguments:
            %   (none)
            %

            obj.view.gui.CloseRequestFcn = @(~,~) obj.closeWindow();

            h = obj.view.handles;

            h.cancelBtn.ButtonPushedFcn          = @(~,~) obj.closeWindow();
            h.cropBtn.ButtonPushedFcn            = @(~,~) obj.cropBtn_Callback();
            h.targetPanel.SelectionChangedFcn    = @(~,~) obj.targetPanel_Callback();
            h.Generate3DPatches.ValueChangedFcn  = @(~,~) obj.generate3DPatches_Callback();
            h.jitterEnableCheckbox.ValueChangedFcn = @(~,~) obj.jitter_Callback();
            h.cropModelCheck.ValueChangedFcn     = @(~,~) obj.cropModelCheck_Callback();
            h.cropMaskCheck.ValueChangedFcn      = @(~,~) obj.cropMaskCheck_Callback();

            h.formatPopup.ValueChangedFcn         = @(hObj,~) obj.updateBatchOptFromGUI(hObj);
            h.marginXYEdit.ValueChangedFcn        = @(hObj,~) obj.updateBatchOptFromGUI(hObj);
            h.marginZEdit.ValueChangedFcn         = @(hObj,~) obj.updateBatchOptFromGUI(hObj);
            h.CropObjectsDepth.ValueChangedFcn    = @(hObj,~) obj.updateBatchOptFromGUI(hObj);
            h.jitterVariationEditbox.ValueChangedFcn = @(hObj,~) obj.updateBatchOptFromGUI(hObj);
            h.jitterSeedEditbox.ValueChangedFcn   = @(hObj,~) obj.updateBatchOptFromGUI(hObj);
            h.modelFormatPopup.ValueChangedFcn    = @(hObj,~) obj.updateBatchOptFromGUI(hObj);
            h.maskFormatPopup.ValueChangedFcn     = @(hObj,~) obj.updateBatchOptFromGUI(hObj);
            h.SingleMaskObjectPerDataset.ValueChangedFcn = @(hObj,~) obj.updateBatchOptFromGUI(hObj);

            h.selectDirBtn.ButtonPushedFcn = @(~,~) obj.selectDirBtn_Callback();
            h.dirEdit.ValueChangedFcn      = @(~,~) obj.dirEdit_Callback();
        end

        % -----------------------------------------------------------------
        function selectDirBtn_Callback(obj)
            % SELECTDIRBTN_CALLBACK - Browse for the output directory using a folder picker dialog.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.selectDirBtn_Callback()
            %
            % Output Arguments:
            %   (none)
            %

            obj.view.handles.cropBtn.Enable = 'off';  % prevent crop while dialog is open
            folder_name = uigetdir(obj.outputDir, 'Select directory');
            if isequal(folder_name, 0)
                obj.view.handles.cropBtn.Enable = 'on';
                return;
            end
            obj.outputDir = folder_name;
            obj.view.handles.dirEdit.Value = folder_name;
            obj.view.handles.cropBtn.Enable = 'on';
        end

        % -----------------------------------------------------------------
        function dirEdit_Callback(obj)
            % DIREDIT_CALLBACK - Validate a directory path typed manually into dirEdit.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.dirEdit_Callback()
            %
            % Output Arguments:
            %   (none)
            %

            folder_name = obj.view.handles.dirEdit.Value;
            if exist(folder_name, 'dir') == 0
                choice = utils.dlgs.inputQuestDlg(obj.view.gui, ...
                    sprintf('The target directory:\n%s\nis missing!\n\nCreate?', folder_name), ...
                    'Create Directory', 'Create', 'Cancel', 'Cancel');
                if strcmp(choice, 'Cancel')
                    obj.view.handles.dirEdit.Value = obj.outputDir;
                    return;
                end
                mkdir(folder_name);
            end
            obj.outputDir = folder_name;
        end

        % -----------------------------------------------------------------
        function updateWidgets(obj)
            % UPDATEWIDGETS - Refresh all widgets from parentController.BatchOpt.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.updateWidgets()
            %
            % Output Arguments:
            %   (none)
            %

            h = obj.view.handles;
            id = obj.mibModel.getActiveId();
            BatchOptLocal = obj.parentController.BatchOpt;

            % --- target radio group ---
            if strcmp(BatchOptLocal.CropObjectsTo{1}, 'Crop to MATLAB')
                h.targetPanel.SelectedObject = h.matlabRadio;
                h.formatPopup.Enable  = 'off';
                h.selectDirBtn.Enable = 'off';
                h.dirEdit.Enable      = 'off';
            else
                h.targetPanel.SelectedObject = h.fileRadio;
                h.formatPopup.Enable  = 'on';
                h.selectDirBtn.Enable = 'on';
                h.dirEdit.Enable      = 'on';
                if ismember(BatchOptLocal.CropObjectsTo{1}, h.formatPopup.Items)
                    h.formatPopup.Value = BatchOptLocal.CropObjectsTo{1};
                else
                    % value is not a valid format (e.g. 'Do not crop' from Quantification default)
                    h.formatPopup.Value = h.formatPopup.Items{1};
                    BatchOptLocal.CropObjectsTo{1} = h.formatPopup.Items{1};
                end
            end

            fromQuantification = isa(obj.parentController, 'controllers.Quantification');

            % --- patch dimensions ---
            if fromQuantification
                h.MarginXYLabel.Text = 'MarginXY, px';
                h.MarginZLabel.Text  = 'MarginZ, px';
            else
                h.MarginXYLabel.Text = 'Width, px';
                h.MarginZLabel.Text  = 'Height, px';
            end
            h.marginXYEdit.Value = str2double(BatchOptLocal.CropObjectsMarginXY);
            h.marginZEdit.Value  = str2double(BatchOptLocal.CropObjectsMarginZ);

            % --- 3D patches ---
            h.Generate3DPatches.Enable = 'on';
            h.Generate3DPatches.Value  = BatchOptLocal.Generate3DPatches;
            h.CropObjectsDepth.Value   = str2double(BatchOptLocal.CropObjectsDepth);
            if fromQuantification
                % Depth box unused from Quantification (Z comes from BoundingBox)
                h.CropObjectsDepth.Enable = 'off';
                % marginZ enabled only when "Crop 3D objects" is checked
                h.marginZEdit.Enable = matlab.lang.OnOffSwitchState(BatchOptLocal.Generate3DPatches);
            else
                h.marginZEdit.Enable = 'on';
                h.CropObjectsDepth.Enable = matlab.lang.OnOffSwitchState(BatchOptLocal.Generate3DPatches);
            end

            % --- model / mask inclusion ---
            if fromQuantification
                isMaskLayer = str2double(obj.parentController.BatchOpt.MaterialIndex) == -1;
                h.SingleMaskObjectPerDataset.Enable = matlab.lang.OnOffSwitchState(isMaskLayer);
                BatchOptLocal.SingleMaskObjectPerDataset = BatchOptLocal.SingleMaskObjectPerDataset && isMaskLayer;
            else
                h.SingleMaskObjectPerDataset.Enable = 'off';
                BatchOptLocal.SingleMaskObjectPerDataset = false;
            end
            h.SingleMaskObjectPerDataset.Value = BatchOptLocal.SingleMaskObjectPerDataset;

            if obj.mibModel.I{id}.modelExist
                h.cropModelCheck.Enable = 'on';
            else
                h.cropModelCheck.Enable = 'off';
                h.cropModelCheck.Value = false;
            end
            if obj.mibModel.I{id}.maskExist
                h.cropMaskCheck.Enable = 'on';
            else
                h.cropMaskCheck.Enable = 'off';
                h.cropMaskCheck.Value = false;
            end
            % keep format popups visible but disabled until checkbox is ticked
            h.modelFormatPopup.Enable = 'off';
            h.maskFormatPopup.Enable  = 'off';

            % --- jitter ---
            h.jitterEnableCheckbox.Value = BatchOptLocal.CropObjectsJitter;
            h.jitterVariationEditbox.Value = str2double(BatchOptLocal.CropObjectsJitterVariation);
            h.jitterSeedEditbox.Value      = str2double(BatchOptLocal.CropObjectsJitterSeed);
            if BatchOptLocal.CropObjectsJitter
                h.jitterVariationEditbox.Enable = 'on';
                h.jitterSeedEditbox.Enable      = 'on';
            else
                h.jitterVariationEditbox.Enable = 'off';
                h.jitterSeedEditbox.Enable      = 'off';
            end

            % --- output directory ---
            h.dirEdit.Value = obj.outputDir;

            obj.parentController.BatchOpt = BatchOptLocal;
        end

        % -----------------------------------------------------------------
        function updateBatchOptFromGUI(obj, hObject)
            % UPDATEBATCHOPTFROMGUI - Sync a single widget value back into parentController.BatchOpt.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.updateBatchOptFromGUI(hObject)
            %
            % Input Arguments:
            %   - **hObject** — handle to the widget that changed; ``hObject.Tag``
            %     identifies the BatchOpt field to update
            %
            % Output Arguments:
            %   (none)
            %

            BatchOptLocal = obj.parentController.BatchOpt;
            switch hObject.Tag
                case 'formatPopup'
                    if obj.view.handles.fileRadio.Value
                        BatchOptLocal.CropObjectsTo{1} = hObject.Value;
                    end
                case 'marginXYEdit'
                    BatchOptLocal.CropObjectsMarginXY = num2str(round(hObject.Value));
                case 'marginZEdit'
                    BatchOptLocal.CropObjectsMarginZ = num2str(round(hObject.Value));
                case 'CropObjectsDepth'
                    BatchOptLocal.CropObjectsDepth = num2str(round(hObject.Value));
                case 'jitterVariationEditbox'
                    BatchOptLocal.CropObjectsJitterVariation = num2str(round(hObject.Value));
                    obj.mibModel.sessionSettings.(obj.sessionSettingsKey).CropObjectsJitterVariation = num2str(round(hObject.Value));
                case 'jitterSeedEditbox'
                    BatchOptLocal.CropObjectsJitterSeed = num2str(round(hObject.Value));
                    obj.mibModel.sessionSettings.(obj.sessionSettingsKey).CropObjectsJitterSeed = num2str(round(hObject.Value));
                case 'modelFormatPopup'
                    BatchOptLocal.CropObjectsIncludeModel{1} = hObject.Value;
                case 'maskFormatPopup'
                    BatchOptLocal.CropObjectsIncludeMask{1} = hObject.Value;
                case 'SingleMaskObjectPerDataset'
                    BatchOptLocal.SingleMaskObjectPerDataset = hObject.Value;
            end
            obj.parentController.BatchOpt = BatchOptLocal;
        end

        % -----------------------------------------------------------------
        function targetPanel_Callback(obj)
            % TARGETPANEL_CALLBACK - Callback for the target radio button group (File / MATLAB).
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.targetPanel_Callback()
            %
            % Output Arguments:
            %   (none)
            %

            h = obj.view.handles;
            if h.fileRadio.Value
                h.formatPopup.Enable  = 'on';
                h.selectDirBtn.Enable = 'on';
                h.dirEdit.Enable      = 'on';
                obj.parentController.BatchOpt.CropObjectsTo{1} = h.formatPopup.Value;
            else
                % MATLAB export — ask for variable name
                notOk = true;
                while notOk
                    answer = utils.dlgs.inputSingleDlg(obj.view.gui, ...
                        {sprintf('Enter variable name template for export to MATLAB:\n(must start with a letter)')}, ...
                        {obj.outputVar}, 'Variable name');
                    if isempty(answer); return; end
                    
                    if ~isnan(str2double(answer(1)))
                        dlgOpt.MsgBoxOnly  = true;
                        dlgOpt.Icon        = 'puffin_error';
                        header      = 'The first character cannot be numerical!';
                        dlgOpt.HeaderLines = 1;
                        utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Wrong variable name', dlgOpt);
                    else
                        notOk = false;
                        obj.outputVar = answer;
                    end
                end
                h.formatPopup.Enable  = 'off';
                h.selectDirBtn.Enable = 'off';
                h.dirEdit.Enable      = 'off';
                obj.parentController.BatchOpt.CropObjectsTo{1} = 'Crop to MATLAB';
            end
        end

        % -----------------------------------------------------------------
        function generate3DPatches_Callback(obj)
            % GENERATE3DPATCHES_CALLBACK - Callback for the "crop 3D objects" checkbox.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.generate3DPatches_Callback()
            %
            % Output Arguments:
            %   (none)
            %

            h = obj.view.handles;
            state = matlab.lang.OnOffSwitchState(h.Generate3DPatches.Value);
            if isa(obj.parentController, 'controllers.Quantification')
                h.marginZEdit.Enable = state;       % Z margin only meaningful in 3D mode
            else
                h.CropObjectsDepth.Enable = state;  % fixed depth box for annotations
            end
            obj.parentController.BatchOpt.Generate3DPatches = h.Generate3DPatches.Value;
        end

        % -----------------------------------------------------------------
        function jitter_Callback(obj)
            % JITTER_CALLBACK - Callback for the jitter enable checkbox.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.jitter_Callback()
            %
            % Output Arguments:
            %   (none)
            %

            h = obj.view.handles;
            if h.jitterEnableCheckbox.Value
                h.jitterVariationEditbox.Enable = 'on';
                h.jitterSeedEditbox.Enable      = 'on';
            else
                h.jitterVariationEditbox.Enable = 'off';
                h.jitterSeedEditbox.Enable      = 'off';
            end
            obj.parentController.BatchOpt.CropObjectsJitter = h.jitterEnableCheckbox.Value;
        end

        % -----------------------------------------------------------------
        function cropModelCheck_Callback(obj)
            % CROPMODELCHECK_CALLBACK - Callback for the "Crop Model" checkbox.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.cropModelCheck_Callback()
            %
            % Output Arguments:
            %   (none)
            %

            h = obj.view.handles;
            BatchOptLocal = obj.parentController.BatchOpt;
            if h.cropModelCheck.Value
                h.modelFormatPopup.Enable = 'on';
                BatchOptLocal.CropObjectsIncludeModel{1} = h.modelFormatPopup.Value;
            else
                h.modelFormatPopup.Enable = 'off';
                BatchOptLocal.CropObjectsIncludeModel{1} = 'Do not include';
            end
            obj.parentController.BatchOpt = BatchOptLocal;
        end

        % -----------------------------------------------------------------
        function cropMaskCheck_Callback(obj)
            % CROPMASKCHECK_CALLBACK - Callback for the "Crop Mask" checkbox.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.cropMaskCheck_Callback()
            %
            % Output Arguments:
            %   (none)
            %

            h = obj.view.handles;
            BatchOptLocal = obj.parentController.BatchOpt;
            if h.cropMaskCheck.Value
                h.maskFormatPopup.Enable = 'on';
                BatchOptLocal.CropObjectsIncludeMask{1} = h.maskFormatPopup.Value;
            else
                h.maskFormatPopup.Enable = 'off';
                BatchOptLocal.CropObjectsIncludeMask{1} = 'Do not include';
            end
            obj.parentController.BatchOpt = BatchOptLocal;
        end

        % -----------------------------------------------------------------
        function cropBtn_Callback(obj)
            % CROPBTN_CALLBACK - Callback for the Crop button; resolves output directory then calls generatePatches.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.cropBtn_Callback()
            %
            % Output Arguments:
            %   (none)
            %

            BatchOptLocal = obj.parentController.BatchOpt;

            % persist jitter settings
            if ~isfield(obj.mibModel.sessionSettings, obj.sessionSettingsKey)
                obj.mibModel.sessionSettings.(obj.sessionSettingsKey) = struct();
            end
            obj.mibModel.sessionSettings.(obj.sessionSettingsKey).CropObjectsJitterVariation = BatchOptLocal.CropObjectsJitterVariation;
            obj.mibModel.sessionSettings.(obj.sessionSettingsKey).CropObjectsJitterSeed      = BatchOptLocal.CropObjectsJitterSeed;

            if isempty(obj.annotationLabels); return; end

            if strcmp(BatchOptLocal.CropObjectsTo{1}, 'Crop to MATLAB')
                obj.outputDir = '';
                obj.generatePatches();
            else
                if exist(obj.outputDir, 'dir') == 0; mkdir(obj.outputDir); end
                obj.generatePatches();
            end
        end

        % -----------------------------------------------------------------
        function generatePatches(obj)
            % GENERATEPATCHES - Crop image patches centred on each annotation and save them.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.generatePatches()
            %
            % Reads coordinates from ``obj.annotationLabels.positions`` [Nx4: z,x,y,t]
            % and names from ``obj.annotationLabels.names`` {Nx1}.
            % Output format and inclusion of model/mask are controlled by
            % ``obj.parentController.BatchOpt`` fields.
            %
            % Output Arguments:
            %   (none)
            %

            BatchOptLocal   = obj.parentController.BatchOpt;
            id  = obj.mibModel.getActiveId();
            hasView = ~isempty(obj.view) && isvalid(obj.view.gui);
            if hasView; h = obj.view.handles; end

            % ---- jitter ------------------------------------------------
            if BatchOptLocal.CropObjectsJitter
                randSeed = str2double(BatchOptLocal.CropObjectsJitterSeed);
                if randSeed == 0
                    rng('shuffle');
                else
                    rng(randSeed, 'twister');
                end
                randVariation = str2double(BatchOptLocal.CropObjectsJitterVariation);
                nPts      = size(obj.annotationLabels.positions, 1);
                varMatrix = randi(randVariation * 2, [nPts, 2]) - randVariation;
                obj.annotationLabels.positions(:, 2:3) = obj.annotationLabels.positions(:, 2:3) + varMatrix;
            end

            obj.annotationLabels.positions = round(obj.annotationLabels.positions);

            % ---- extension & target ------------------------------------
            extensionPos = strfind(BatchOptLocal.CropObjectsTo{1}, '*.');
            ext = '';
            if ~isempty(extensionPos)
                ext = BatchOptLocal.CropObjectsTo{1}(extensionPos+1:end-1);
            end
            toMatlab = strcmp(BatchOptLocal.CropObjectsTo{1}, 'Crop to MATLAB');

            % ---- dataset dimensions & pixelsize ------------------------
            imgW    = obj.mibModel.I{id}.image.width;
            imgH    = obj.mibModel.I{id}.image.height;
            imgZ    = obj.mibModel.I{id}.image.depth;
            pixSize = obj.mibModel.I{id}.image.pixSize;

            % ---- filename template(s) ----------------------------------
            if toMatlab
                fnTemplate = obj.outputVar;  % scalar string
            else
                % ask user about per-file naming options once
                if ~isfield(obj.mibModel.sessionSettings, (obj.sessionSettingsKey)) || ...
                        ~isfield(obj.mibModel.sessionSettings.(obj.sessionSettingsKey), 'includeName')
                    obj.mibModel.sessionSettings.(obj.sessionSettingsKey).includeName          = false;
                    obj.mibModel.sessionSettings.(obj.sessionSettingsKey).includeZ             = false;
                    obj.mibModel.sessionSettings.(obj.sessionSettingsKey).includeX             = false;
                    obj.mibModel.sessionSettings.(obj.sessionSettingsKey).includeY             = false;
                    obj.mibModel.sessionSettings.(obj.sessionSettingsKey).useSliceNameIdentifier = false;
                    obj.mibModel.sessionSettings.(obj.sessionSettingsKey).cropOutAllMaterials  = 1;
                end

                if ~isempty(obj.mibModel.I{id}.labels.materialNames)
                    modelText1 = 'All materials';
                    matIdx     = max([1, obj.mibModel.I{id}.selectedAddToMaterial - 2]);
                    modelText2 = sprintf('Selected material (%s)', obj.mibModel.I{id}.labels.materialNames{matIdx});
                else
                    modelText1 = 'not used';
                    modelText2 = '';
                    obj.mibModel.sessionSettings.(obj.sessionSettingsKey).cropOutAllMaterials = 1;
                end

                if hasView
                    prompts = {'Include annotation name';
                               'Include Z coordinate';
                               'Include X coordinate';
                               'Include Y coordinate';
                               'Use slice names as filename templates';
                               sprintf('Export all materials or only selected?\n(applies when Crop Model is checked)')};
                    defAns = {obj.mibModel.sessionSettings.(obj.sessionSettingsKey).includeName;
                              obj.mibModel.sessionSettings.(obj.sessionSettingsKey).includeZ;
                              obj.mibModel.sessionSettings.(obj.sessionSettingsKey).includeX;
                              obj.mibModel.sessionSettings.(obj.sessionSettingsKey).includeY;
                              obj.mibModel.sessionSettings.(obj.sessionSettingsKey).useSliceNameIdentifier;
                              {modelText1, modelText2, obj.mibModel.sessionSettings.(obj.sessionSettingsKey).cropOutAllMaterials}};
                    dlgOpt.mibPath      = obj.mibModel.mibPath;
                    dlgOpt.WindowWidth  = 550;
                    dlgOpt.WindowHeight  = 260;
                    dlgOpt.LabelPosition = 'left';
                    header        = 'Specify additional filename parameters';
                    dlgOpt.HeaderLines   = 1;
                    [answer, selValue] = utils.dlgs.inputUniversalDlg(obj.view.gui, header, prompts, defAns, 'Crop patches settings', dlgOpt);
                    if isempty(answer); return; end

                    obj.mibModel.sessionSettings.(obj.sessionSettingsKey).includeName            = logical(answer{1});
                    obj.mibModel.sessionSettings.(obj.sessionSettingsKey).includeZ               = logical(answer{2});
                    obj.mibModel.sessionSettings.(obj.sessionSettingsKey).includeX               = logical(answer{3});
                    obj.mibModel.sessionSettings.(obj.sessionSettingsKey).includeY               = logical(answer{4});
                    obj.mibModel.sessionSettings.(obj.sessionSettingsKey).useSliceNameIdentifier = logical(answer{5});
                    obj.mibModel.sessionSettings.(obj.sessionSettingsKey).cropOutAllMaterials    = selValue(6);
                end
                % read naming flags from sessionSettings (set by dialog above, or pre-existing in batch)
                ss = obj.mibModel.sessionSettings.(obj.sessionSettingsKey);
                includeName = logical(ss.includeName);
                includeZ    = logical(ss.includeZ);
                includeX    = logical(ss.includeX);
                includeY    = logical(ss.includeY);

                % build per-slice filename templates
                [~, fnBase]  = fileparts(obj.mibModel.I{id}.image.filename);
                if isempty(fnBase); fnBase = obj.outputVar; end
                fnTemplate   = repmat({fnBase}, [imgZ, 1]);

                useSliceIdx = logical(ss.useSliceNameIdentifier);
                if useSliceIdx
                    sliceNames = obj.mibModel.I{id}.image.sliceName;
                    if numel(sliceNames) == imgZ
                        [~, fnTemplate] = fileparts(sliceNames);
                    end
                end
            end

            % ---- model material index ----------------------------------
            cropModelChecked = hasView && h.cropModelCheck.Value || ...
                (~hasView && ~strcmp(BatchOptLocal.CropObjectsIncludeModel{1}, 'Do not include'));
            if cropModelChecked
                if ~isfield(obj.mibModel.sessionSettings, obj.sessionSettingsKey) || ...
                        ~isfield(obj.mibModel.sessionSettings.(obj.sessionSettingsKey), 'cropOutAllMaterials') || ...
                        obj.mibModel.sessionSettings.(obj.sessionSettingsKey).cropOutAllMaterials == 1
                    BatchOptLocal.CropObjectsIncludeModelMaterialIndex = 'NaN';
                else
                    matIdx = max([1, obj.mibModel.I{id}.selectedAddToMaterial - 2]);
                    BatchOptLocal.CropObjectsIncludeModelMaterialIndex = num2str(matIdx);
                end
                obj.parentController.BatchOpt = BatchOptLocal;
            end
            material_id = str2double(BatchOptLocal.CropObjectsIncludeModelMaterialIndex);

            % ---- patch sizes -------------------------------------------
            marginXY = str2double(BatchOptLocal.CropObjectsMarginXY);
            marginZ  = str2double(BatchOptLocal.CropObjectsMarginZ);
            useBoundingBox = isfield(obj.annotationLabels, 'boundingBoxes');
            if ~useBoundingBox
                % annotation-based: marginXY = total width, marginZ = total height (Y)
                if BatchOptLocal.Generate3DPatches
                    patchDepth = str2double(BatchOptLocal.CropObjectsDepth);
                else
                    patchDepth = 1;
                end
            end

            % ---- image save options (shared) ---------------------------
            saveOpts.showWaitbar      = false;
            saveOpts.overwrite        = true;
            saveOpts.silent           = true;
            saveOpts.Saving3DPolicy   = '3D stack';
            saveOpts.pixSize          = pixSize;
            if contains(BatchOptLocal.CropObjectsTo{1}, 'LZW')
                saveOpts.Compression = 'lzw';
            else
                saveOpts.Compression = 'none';
            end
            saveOpts.Format = BatchOptLocal.CropObjectsTo{1};

            % ---- progress bar ------------------------------------------
            noPoints  = size(obj.annotationLabels.positions, 1);
            objDigits = numel(num2str(noPoints));
            hasView = ~isempty(obj.view) && isvalid(obj.view.gui);
            if hasView
                pwb = core.PoolWaitbar(noPoints, 'Processing patches...', obj.view.gui, 'Crop patches', true);
            end

            getDataOpt.blockModeSwitch = 0;
            getDataOpt.id              = id;

            for pntId = 1:noPoints
                if hasView
                    if pwb.getCancelState(); break; end
                    pwb.updateText(sprintf('Processing patch %d / %d...', pntId, noPoints));
                end

                annZ = obj.annotationLabels.positions(pntId, 1);
                t1   = obj.annotationLabels.positions(pntId, 4);

                % ---- compute crop bounds --------------------------------
                if useBoundingBox
                    % Object-based: BoundingBox + marginXY/marginZ padding on each side.
                    % MATLAB regionprops BoundingBox: [x_start, y_start, z_start, w, h, d]
                    % with 0.5-offset origin, so first pixel index = ceil(start).
                    bb_obj = obj.annotationLabels.boundingBoxes(pntId, :);
                    bbX1 = ceil(bb_obj(1));  bbX2 = bbX1 + bb_obj(4) - 1;
                    bbY1 = ceil(bb_obj(2));  bbY2 = bbY1 + bb_obj(5) - 1;
                    x1 = max(1,    bbX1 - marginXY);
                    x2 = min(imgW, bbX2 + marginXY);
                    y1 = max(1,    bbY1 - marginXY);
                    y2 = min(imgH, bbY2 + marginXY);
                    if BatchOptLocal.Generate3DPatches
                        bbZ1 = ceil(bb_obj(3));  bbZ2 = bbZ1 + bb_obj(6) - 1;
                        z1 = max(1,    bbZ1 - marginZ);
                        z2 = min(imgZ, bbZ2 + marginZ);
                    else
                        z1 = annZ;  z2 = annZ;
                    end
                else
                    % Centroid-based: marginXY = total width, marginZ = total height (Y)
                    x1 = max(1, min(obj.annotationLabels.positions(pntId, 2) - floor(marginXY / 2), imgW - marginXY + 1));
                    y1 = max(1, min(obj.annotationLabels.positions(pntId, 3) - floor(marginZ  / 2), imgH - marginZ  + 1));
                    z1 = max(1, min(annZ - floor(patchDepth / 2), imgZ - patchDepth + 1));
                    x2 = x1 + marginXY  - 1;
                    y2 = y1 + marginZ   - 1;
                    z2 = z1 + patchDepth - 1;
                end

                getDataOpt.x = [x1, x2];
                getDataOpt.y = [y1, y2];
                getDataOpt.z = [z1, z2];

                % ---- bounding box in physical units ---------------------
                xMinPhys = (x1 - 1) * pixSize.x;
                yMinPhys = (y1 - 1) * pixSize.y;
                zMinPhys = (z1 - 1) * pixSize.z;
                xMaxPhys = xMinPhys + (x2 - x1 + 1) * pixSize.x;
                yMaxPhys = yMinPhys + (y2 - y1 + 1) * pixSize.y;
                zMaxPhys = zMinPhys + (z2 - z1 + 1) * pixSize.z;
                bb       = [xMinPhys, xMaxPhys, yMinPhys, yMaxPhys, zMinPhys, zMaxPhys];

                % ---- generate output filename ---------------------------
                if isfield(obj.annotationLabels, 'objectIds')
                    fileId = obj.annotationLabels.objectIds(pntId);
                else
                    fileId = pntId;
                end
                if toMatlab
                    filename = sprintf(['%s_%0' num2str(objDigits) 'd'], fnTemplate, fileId);
                else
                    filename = fullfile(obj.outputDir, ...
                        sprintf(['%s_%0' num2str(objDigits) 'd'], fnTemplate{annZ}, fileId));
                    if includeName
                        filename = sprintf('%s_%s', filename, obj.annotationLabels.names{pntId});
                    end
                    if includeZ
                        zDigits  = numel(num2str(imgZ));
                        filename = sprintf(['%s_z%0' num2str(zDigits) 'd'], filename, annZ);
                    end
                    if includeX
                        filename = sprintf('%s_x%d', filename, obj.annotationLabels.positions(pntId, 2));
                    end
                    if includeY
                        filename = sprintf('%s_y%d', filename, obj.annotationLabels.positions(pntId, 3));
                    end
                    filename = [filename ext]; %#ok<AGROW>
                end

                % ---- get image data ------------------------------------
                imData = cell2mat(obj.mibModel.getData3D('image', t1, 3, NaN, getDataOpt));

                % ---- save image ----------------------------------------
                if toMatlab
                    matlabVar      = struct();
                    matlabVar.img  = imData;
                    matlabVar.pixSize  = pixSize;
                    matlabVar.logText = sprintf( ...
                        'ObjectCrop: [y1:y2,x1:x2,:,z1:z2,t]: %d:%d,%d:%d,:,%d:%d,%d', ...
                        y1, y2, x1, x2, z1, z2, t1);
                else
                    imgOut = core.MibImage(imData);
                    imgOut.boundingBox = bb;
                    imgOut.save(filename, saveOpts);
                end

                % ---- save model (optional) ------------------------------
                if ~strcmp(BatchOptLocal.CropObjectsIncludeModel{1}, 'Do not include')
                    modelData = cell2mat(obj.mibModel.getData3D('labels', t1, 3, material_id, getDataOpt));

                    modelMaterialNames  = obj.mibModel.I{id}.labels.materialNames;
                    modelMaterialColors = obj.mibModel.I{id}.labels.materialColors;
                    if material_id > 0
                        modelMaterialColors = modelMaterialColors(material_id, :);
                        modelMaterialNames  = modelMaterialNames(material_id);
                    end

                    if toMatlab
                        matlabVar.Model.model     = modelData;
                        matlabVar.Model.materials = modelMaterialNames;
                        matlabVar.Model.colors    = modelMaterialColors;
                    else
                        [~, fnBase] = fileparts(filename);
                        fnModel = fullfile(obj.outputDir, ['Labels_' fnBase]);
                        obj.saveAuxLayer(modelData, BatchOptLocal.CropObjectsIncludeModel{1}, fnModel, pixSize, ...
                            xMinPhys, yMinPhys, zMinPhys, modelMaterialColors, modelMaterialNames, ...
                            saveOpts, id, 'model');
                    end
                end

                % ---- save mask (optional) -------------------------------
                if ~strcmp(BatchOptLocal.CropObjectsIncludeMask{1}, 'Do not include')
                    maskData = cell2mat(obj.mibModel.getData3D('mask', t1, 3, NaN, getDataOpt));

                    if toMatlab
                        matlabVar.Mask = maskData;
                    else
                        [~, fnBase] = fileparts(filename);
                        fnMask = fullfile(obj.outputDir, ['Mask_' fnBase]);
                        maskColors  = [.567, .213, .625];
                        maskNames   = {'Mask'};
                        obj.saveAuxLayer(maskData, BatchOptLocal.CropObjectsIncludeMask{1}, fnMask, pixSize, ...
                            xMinPhys, yMinPhys, zMinPhys, maskColors, maskNames, ...
                            saveOpts, id, 'mask');
                    end
                end

                % ---- export to Matlab workspace -------------------------
                if toMatlab
                    [~, matlabVarName] = fileparts(filename);
                    assignin('base', matlabVarName, matlabVar);
                    fprintf('MIB: "%s" was exported to MATLAB workspace\n', matlabVarName);
                end
                
                if hasView
                    pwb.increment();
                end
            end

            if hasView
                pwb.deletePoolWaitbar();
                obj.closeWindow();
            end
        end

        % -----------------------------------------------------------------
        function saveAuxLayer(obj, data, format, fnBase, pixSize, ...
                xMinPhys, yMinPhys, zMinPhys, colors, names, ~, id, layerType)
            % SAVEAUXLAYER - Save a model or mask subvolume in the requested format.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.saveAuxLayer(data, format, fnBase, pixSize, xMinPhys, yMinPhys, zMinPhys, colors, names, saveOpts, id, layerType)
            %
            % Input Arguments:
            %   - **data** — [H x W x D] uint8 array with model/mask voxel data
            %   - **format** — [char] one of the ``CropObjectsIncludeModel``/``CropObjectsIncludeMask`` option strings
            %   - **fnBase** — [char] base filename without extension; directory already included
            %   - **pixSize** — struct with physical voxel size fields ``.x``, ``.y``, ``.z``, ``.units``
            %   - **xMinPhys** — [double] physical X origin of the crop region
            %   - **yMinPhys** — [double] physical Y origin of the crop region
            %   - **zMinPhys** — [double] physical Z origin of the crop region
            %   - **colors** — [Nx3] colour matrix for Amira label export
            %   - **names** — {Nx1} cell array of material names
            %   - **saveOpts** — shared save options struct (unused; reserved for future use)
            %   - **id** — [numeric] active dataset index
            %   - **layerType** — [char] ``'model'`` or ``'mask'``
            %
            % Output Arguments:
            %   (none)
            %

            pixStr      = pixSize;
            pixStr.minx = xMinPhys;
            pixStr.miny = yMinPhys;
            pixStr.minz = zMinPhys;

            switch format
                case {'MATLAB format (*.model)', 'MATLAB format (*.mask)'}
                    if strcmp(layerType, 'model')
                        fnOut              = [fnBase '.model'];
                        imOut              = data;
                        modelVariable      = 'imOut';
                        modelType          = obj.mibModel.I{id}.labels.maxMaterials;
                        modelMaterialNames  = names;
                        modelMaterialColors = colors;
                        BoundingBox        = [xMinPhys, xMinPhys + size(data,2)*pixSize.x, ...
                                              yMinPhys, yMinPhys + size(data,1)*pixSize.y, ...
                                              zMinPhys, zMinPhys + size(data,3)*pixSize.z];
                        save(fnOut, 'imOut', 'modelMaterialNames', 'modelMaterialColors', ...
                            'BoundingBox', 'modelVariable', 'modelType', '-mat', '-v7.3');
                    else
                        fnOut = [fnBase '.mask'];
                        imOut = data;
                        save(fnOut, 'imOut', '-mat', '-v7.3');
                    end

                case 'Amira Mesh binary (*.am)'
                    fnOut = [fnBase '.am'];
                    io.AmiraMesh.bitmap2amiraLabels(fnOut, data, 'binary', pixStr, colors, names, 1, 0);

                case 'MRC format for IMOD (*.mrc)'
                    fnOut = [fnBase '.mrc'];
                    mrcOpt.volumeFilename = fnOut;
                    mrcOpt.pixSize        = pixSize;
                    mrcOpt.showWaitbar    = 0;
                    io.mibImage2mrc(data, mrcOpt);

                case 'NRRD Data Format (*.nrrd)'
                    fnOut = [fnBase '.nrrd'];
                    bbVec = [xMinPhys, xMinPhys + size(data,2)*pixSize.x, ...
                             yMinPhys, yMinPhys + size(data,1)*pixSize.y, ...
                             zMinPhys, zMinPhys + size(data,3)*pixSize.z];
                    nrrdOpt.overwrite   = 1;
                    nrrdOpt.showWaitbar = 0;
                    io.NRRD.bitmap2nrrd(fnOut, data, bbVec, nrrdOpt);

                case {'TIF format LZW compression (*.tif)', 'TIF format uncompressed (*.tif)'}
                    fnOut = [fnBase '.tif'];
                    tifSaver = io.savers.TiffSaver();
                    meta.colorType       = 'grayscale';
                    meta.lutColors       = [1 1 1];
                    meta.sliceName       = {};
                    meta.imageDescription = '';
                    meta.xResolution     = 1 / pixSize.x;
                    meta.yResolution     = 1 / pixSize.y;
                    tifOpt.overwrite     = true;
                    tifOpt.showWaitbar   = false;
                    tifOpt.silent        = true;
                    tifOpt.Saving3DPolicy = '3D stack';
                    if strcmp(format, 'TIF format LZW compression (*.tif)')
                        tifOpt.Compression = 'lzw';
                    else
                        tifOpt.Compression = 'none';
                    end
                    % TiffSaver expects [H, W, D, C, T]
                    data5d = reshape(data, [size(data,1), size(data,2), size(data,3), 1, 1]);
                    tifSaver.save(data5d, meta, fnOut, tifOpt);
            end
        end

    end
end


