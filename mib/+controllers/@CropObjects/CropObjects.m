classdef CropObjects < handle
    % @type CropObjects is a child controller for the Crop Image Patches
    % dialog, launched from the Annotations context menu.
    %
    % @code
    % obj.startController('controllers.CropObjects', obj, false, annotationLabels);
    % @endcode
    %
    % @b annotationLabels is a struct with:
    % @li .positions  — [N x 4] matrix of [z, x, y, t] annotation coordinates
    % @li .names      — {N x 1} cell array of annotation label strings

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
        closeEvent
        % fires when the dialog is closed; caught by parent to purge this child
    end

    methods (Static)
        function ViewListner_Callback2(obj, ~, evnt)
            % Guard: if the view was closed before listener cleanup, bail out.
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
            % function obj = CropObjects(mibModel, parentController, batchModeSwitch, annotationLabels)
            % Constructor for the CropObjects controller.
            %
            % Parameters:
            % mibModel: handle to MibModel
            % parentController: handle to the parent Annotations controller
            % batchModeSwitch: [@em optional] logical, reserved for future batch mode; default false
            % annotationLabels: [@em optional] struct with annotation crop coordinates
            % @li .positions  — [Nx4] matrix [z, x, y, t]
            % @li .names      — {Nx1} cell array of label strings

            if nargin < 4; annotationLabels = []; end
            if nargin < 3; batchModeSwitch = []; end

            obj.mibModel = mibModel;
            obj.parentController = parentController;
            obj.annotationLabels = annotationLabels;

            % Use parent's session key if it defines one, else default to annotations
            if isprop(parentController, 'sessionSettingsKey')
                obj.sessionSettingsKey = parentController.sessionSettingsKey;
            else
                obj.sessionSettingsKey = (obj.sessionSettingsKey);
            end

            id = obj.mibModel.getActiveId();
            [~, obj.outputVar] = fileparts(obj.mibModel.I{id}.image.filename);
            if isempty(obj.outputVar); obj.outputVar = 'CropOut'; end
            
            obj.outputDir = obj.mibModel.currentDirectory;

            % initialise the view
            guiName = 'views.CropObjectsGUI';
            obj.view = core.ChildView(obj, guiName);

            obj.addCallbacks();
            obj.updateWidgets();

            obj.view.gui.Icon = fullfile(obj.mibModel.mibPath, 'assets', 'icons', 'mib_icon_16px.png');
            obj.view.gui.Visible = 'on';

            % register model listeners
            obj.listener{1} = addlistener(obj.mibModel, 'UpdateGuiWidgets', ...
                @(src, evnt) controllers.CropObjects.ViewListner_Callback2(obj, src, evnt));
        end

        % -----------------------------------------------------------------
        function closeWindow(obj)
            % function closeWindow(obj)
            % Close the dialog and clean up listeners.

            if isvalid(obj.view.gui)
                delete(obj.view.gui);
            end
            for i = 1:numel(obj.listener)
                delete(obj.listener{i});
            end
            notify(obj, 'closeEvent');
        end

        % -----------------------------------------------------------------
        function addCallbacks(obj)
            % function addCallbacks(obj)
            % Wire all widget callbacks once from the constructor.

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
        end

        % -----------------------------------------------------------------
        function updateWidgets(obj)
            % function updateWidgets(obj)
            % Refresh all widgets from parentController.BatchOpt.

            h = obj.view.handles;
            id = obj.mibModel.getActiveId();
            BatchOptLocal = obj.parentController.BatchOpt;

            % --- target radio group ---
            if strcmp(BatchOptLocal.CropObjectsTo{1}, 'Crop to Matlab')
                h.targetPanel.SelectedObject = h.matlabRadio;
                h.formatPopup.Enable = 'off';
            else
                h.targetPanel.SelectedObject = h.fileRadio;
                h.formatPopup.Enable = 'on';
                if ismember(BatchOptLocal.CropObjectsTo{1}, h.formatPopup.Items)
                    h.formatPopup.Value = BatchOptLocal.CropObjectsTo{1};
                end
            end

            % --- patch dimensions (annotation mode: MarginXY=width, MarginZ=height) ---
            h.MarginXYLabel.Text = 'Width, px';
            h.MarginZLabel.Text  = 'Height, px';
            h.marginXYEdit.Value = str2double(BatchOptLocal.CropObjectsMarginXY);
            h.marginZEdit.Value  = str2double(BatchOptLocal.CropObjectsMarginZ);
            h.marginZEdit.Enable = 'on';

            % --- 3D patches ---
            h.Generate3DPatches.Enable = 'on';
            h.Generate3DPatches.Value  = BatchOptLocal.Generate3DPatches;
            h.CropObjectsDepth.Value   = str2double(BatchOptLocal.CropObjectsDepth);
            if BatchOptLocal.Generate3DPatches
                h.CropObjectsDepth.Enable = 'on';
            else
                h.CropObjectsDepth.Enable = 'off';
            end

            % --- model / mask inclusion ---
            h.SingleMaskObjectPerDataset.Enable = 'off';
            BatchOptLocal.SingleMaskObjectPerDataset = false;
            h.SingleMaskObjectPerDataset.Value = false;

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

            obj.parentController.BatchOpt = BatchOptLocal;
        end

        % -----------------------------------------------------------------
        function updateBatchOptFromGUI(obj, hObject)
            % function updateBatchOptFromGUI(obj, hObject)
            % Sync a single widget value back into parentController.BatchOpt.

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
            % function targetPanel_Callback(obj)
            % Callback for target radio button group (File / MATLAB).

            h = obj.view.handles;
            if h.fileRadio.Value
                h.formatPopup.Enable = 'on';
                obj.parentController.BatchOpt.CropObjectsTo{1} = h.formatPopup.Value;
            else
                h.formatPopup.Enable = 'off';
                obj.parentController.BatchOpt.CropObjectsTo{1} = 'Crop to Matlab';
            end
        end

        % -----------------------------------------------------------------
        function generate3DPatches_Callback(obj)
            % function generate3DPatches_Callback(obj)
            % Callback for the "crop 3D objects" checkbox.

            h = obj.view.handles;
            if h.Generate3DPatches.Value
                h.CropObjectsDepth.Enable = 'on';
            else
                h.CropObjectsDepth.Enable = 'off';
            end
            obj.parentController.BatchOpt.Generate3DPatches = h.Generate3DPatches.Value;
        end

        % -----------------------------------------------------------------
        function jitter_Callback(obj)
            % function jitter_Callback(obj)
            % Callback for the jitter enable checkbox.

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
            % function cropModelCheck_Callback(obj)
            % Callback for the "Crop Model" checkbox.

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
            % function cropMaskCheck_Callback(obj)
            % Callback for the "Crop Mask" checkbox.

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
            % function cropBtn_Callback(obj)
            % Callback for the Crop button; resolves output directory then calls generatePatches.

            BatchOptLocal = obj.parentController.BatchOpt;

            % persist jitter settings
            obj.mibModel.sessionSettings.(obj.sessionSettingsKey).CropObjectsJitterVariation = BatchOptLocal.CropObjectsJitterVariation;
            obj.mibModel.sessionSettings.(obj.sessionSettingsKey).CropObjectsJitterSeed      = BatchOptLocal.CropObjectsJitterSeed;

            if isempty(obj.annotationLabels); return; end

            if strcmp(BatchOptLocal.CropObjectsTo{1}, 'Crop to Matlab')
                obj.outputDir = '';
                obj.generatePatches();
            else
                folder = uigetdir(obj.mibModel.currentDirectory, 'Select output directory for patches');
                if isequal(folder, 0); return; end
                obj.outputDir = folder;
                if exist(obj.outputDir, 'dir') == 0; mkdir(obj.outputDir); end
                obj.generatePatches();
            end
        end

        % -----------------------------------------------------------------
        function generatePatches(obj)
            % function generatePatches(obj)
            % Crop image patches centred on each annotation and save them.
            %
            % Reads coordinates from obj.annotationLabels.positions [Nx4: z,x,y,t]
            % and names from obj.annotationLabels.names {Nx1}.
            %
            % Output format and inclusion of model/mask are controlled through
            % obj.parentController.BatchOpt fields.

            BatchOptLocal   = obj.parentController.BatchOpt;
            id  = obj.mibModel.getActiveId();
            h   = obj.view.handles;

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
            toMatlab = strcmp(BatchOptLocal.CropObjectsTo{1}, 'Crop to Matlab');

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
                dlgOpt.WindowWidth  = 450;
                dlgOpt.PromptLines  = [1, 1, 1, 1, 1, 2];
                dlgOpt.Title        = 'Specify additional filename parameters';
                dlgOpt.TitleLines   = 1;
                [answer, selValue] = utils.dlgs.inputUniversalDlg(obj.view.gui, prompts, defAns, 'Crop patches settings', dlgOpt);
                if isempty(answer); return; end

                obj.mibModel.sessionSettings.(obj.sessionSettingsKey).includeName            = logical(answer{1});
                obj.mibModel.sessionSettings.(obj.sessionSettingsKey).includeZ               = logical(answer{2});
                obj.mibModel.sessionSettings.(obj.sessionSettingsKey).includeX               = logical(answer{3});
                obj.mibModel.sessionSettings.(obj.sessionSettingsKey).includeY               = logical(answer{4});
                obj.mibModel.sessionSettings.(obj.sessionSettingsKey).useSliceNameIdentifier = logical(answer{5});
                obj.mibModel.sessionSettings.(obj.sessionSettingsKey).cropOutAllMaterials    = selValue(6);

                includeName = logical(answer{1});
                includeZ    = logical(answer{2});
                includeX    = logical(answer{3});
                includeY    = logical(answer{4});

                % build per-slice filename templates
                [~, fnBase]  = fileparts(obj.mibModel.I{id}.image.filename);
                if isempty(fnBase); fnBase = obj.outputVar; end
                fnTemplate   = repmat({fnBase}, [imgZ, 1]);

                useSliceIdx = logical(answer{5});
                if useSliceIdx
                    sliceNames = obj.mibModel.I{id}.image.sliceName;
                    if numel(sliceNames) == imgZ
                        [~, fnTemplate] = fileparts(sliceNames);
                    end
                end
            end

            % ---- model material index ----------------------------------
            if h.cropModelCheck.Value
                if obj.mibModel.sessionSettings.(obj.sessionSettingsKey).cropOutAllMaterials == 1
                    BatchOptLocal.CropObjectsIncludeModelMaterialIndex = 'NaN';
                else
                    matIdx = max([1, obj.mibModel.I{id}.selectedAddToMaterial - 2]);
                    BatchOptLocal.CropObjectsIncludeModelMaterialIndex = num2str(matIdx);
                end
                obj.parentController.BatchOpt = BatchOptLocal;
            end
            material_id = str2double(BatchOptLocal.CropObjectsIncludeModelMaterialIndex);

            % ---- patch sizes -------------------------------------------
            patchWidth  = str2double(BatchOptLocal.CropObjectsMarginXY);
            patchHeight = str2double(BatchOptLocal.CropObjectsMarginZ);
            if BatchOptLocal.Generate3DPatches
                patchDepth = str2double(BatchOptLocal.CropObjectsDepth);
            else
                patchDepth = 1;
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
            wb = uiprogressdlg(obj.view.gui, 'Title', 'Crop patches', ...
                'Message', 'Please wait...', 'Value', 0);

            getDataOpt.blockModeSwitch = 0;
            getDataOpt.id              = id;

            for pntId = 1:noPoints
                wb.Value   = (pntId - 1) / noPoints;
                wb.Message = sprintf('Processing patch %d / %d...', pntId, noPoints);

                annZ = obj.annotationLabels.positions(pntId, 1);
                t1   = obj.annotationLabels.positions(pntId, 4);

                % ---- compute crop bounds --------------------------------
                x1 = obj.annotationLabels.positions(pntId, 2) - floor(patchWidth  / 2);
                y1 = obj.annotationLabels.positions(pntId, 3) - floor(patchHeight / 2);
                z1 = annZ                                      - floor(patchDepth  / 2);

                x1 = max(1, min(x1, imgW - patchWidth  + 1));
                y1 = max(1, min(y1, imgH - patchHeight + 1));
                z1 = max(1, min(z1, imgZ - patchDepth  + 1));

                x2 = x1 + patchWidth  - 1;
                y2 = y1 + patchHeight - 1;
                z2 = z1 + patchDepth  - 1;

                getDataOpt.x = [x1, x2];
                getDataOpt.y = [y1, y2];
                getDataOpt.z = [z1, z2];

                % ---- bounding box in physical units ---------------------
                xMinPhys = (x1 - 1) * pixSize.x;
                yMinPhys = (y1 - 1) * pixSize.y;
                zMinPhys = (z1 - 1) * pixSize.z;
                xMaxPhys = xMinPhys + patchWidth  * pixSize.x;
                yMaxPhys = yMinPhys + patchHeight * pixSize.y;
                zMaxPhys = zMinPhys + patchDepth  * pixSize.z;
                bb       = [xMinPhys, xMaxPhys, yMinPhys, yMaxPhys, zMinPhys, zMaxPhys];

                % ---- generate output filename ---------------------------
                if toMatlab
                    filename = sprintf(['%s_%0' num2str(objDigits) 'd'], fnTemplate, pntId);
                else
                    filename = fullfile(obj.outputDir, ...
                        sprintf(['%s_%0' num2str(objDigits) 'd'], fnTemplate{annZ}, pntId));
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
                        [~, fnModel] = fileparts(filename);
                        fnModel      = ['Labels_' fnModel];
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
                        [~, fnMask] = fileparts(filename);
                        fnMask      = ['Mask_' fnMask];
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
            end

            wb.Value = 1;
            delete(wb);
            obj.closeWindow();
        end

        % -----------------------------------------------------------------
        function saveAuxLayer(obj, data, format, fnBase, pixSize, ...
                xMinPhys, yMinPhys, zMinPhys, colors, names, ~, id, layerType)
            % function saveAuxLayer(obj, data, format, fnBase, pixSize, ...)
            % Save a model or mask subvolume in the requested format.
            %
            % Parameters:
            % data: [H x W x D] uint8 array with model/mask data
            % format: char — one of the CropObjectsIncludeModel/Mask option strings
            % fnBase: char — base filename without extension (directory already included)
            % pixSize: struct — physical voxel size (.x .y .z .units)
            % xMinPhys, yMinPhys, zMinPhys: doubles — physical origin of the crop
            % colors: [Nx3] color matrix for Amira labels
            % names: {Nx1} cell array of material names
            % saveOpts: struct — shared save options (Compression etc.)
            % id: int — active dataset index
            % layerType: char — 'model' | 'mask' (used for Matlab format extension)

            pixStr      = pixSize;
            pixStr.minx = xMinPhys;
            pixStr.miny = yMinPhys;
            pixStr.minz = zMinPhys;

            switch format
                case {'Matlab format (*.model)', 'Matlab format (*.mask)'}
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


