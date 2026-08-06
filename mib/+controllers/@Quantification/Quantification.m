classdef Quantification < handle
% QUANTIFICATION - controller for the Quantification (image statistics) window.

    properties
        mibModel
        % handle to MibModel
        view
        % handle to core.ChildView (views.QuantificationGUI)
        anisotropicVoxelsAgree
        % flag: warning about anisotropic voxels was already shown (1) or not (0)
        availableProperties2D
        % cell array with the list of available properties for 2D objects
        availableProperties3D
        % cell array with the list of available properties for 3D objects
        availablePropertiesInt
        % cell array with the list of available properties for intensity
        histLimits
        % limits [low, high] for the histogram display
        indices
        % indices of selected rows in statTable
        listener
        % cell array with handles to event listeners
        intType
        % selected mode index for intensity mode
        obj2DType
        % selected mode index for 2D object mode
        obj3DType
        % selected mode index for 3D object mode
        runId
        % [datasetId, materialId] vector for which STATS were calculated; empty if not yet run
        sessionSettingsKey
        % key into mibModel.sessionSettings used by CropObjects to persist crop/jitter settings
        sortingDirection
        % 'ascend' or 'descend' - current sort direction
        sortingColIndex
        % column index used for sorting (1-4)
        sortingRowIndex
        % mapping: sortingRowIndex(i) -> index in STATS after sorting
        statProperties
        % cell array of properties to calculate (single or multiple)
        STATS
        % struct array with quantification results
        childControllers
        % cell array of opened child controller handles
        childControllersIds
        % cell array with class names of initialized child controllers
        BatchOpt
        % struct compatible with batch processing - see constructor for fields
    end

    events
        CloseEvent        % fires when the dialog is closed; caught by parent to clean up
    end

    methods (Static)

        function ViewListner_Callback2(obj, src, evnt)
            % VIEWLISTNER_CALLBACK2 - static listener callback for mibModel events.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.ViewListner_Callback2(src, evnt)
            %
            % Input Arguments:
            %   - **obj** - handle to Quantification controller
            %   - **src** - event source
            %   - **evnt** - event data with EventName field
            %

            if ~isvalid(obj) || isempty(obj.view) || ~isvalid(obj.view.gui)
                for i = 1:numel(obj.listener); delete(obj.listener{i}); end
                return;
            end
            switch evnt.EventName
                case {'UpdateGuiWidgets', 'NewDataset'}
                    if strcmp(evnt.EventName, 'NewDataset')
                        % clear stored results when the active dataset changes
                        id = obj.mibModel.getActiveId();
                        if ~isempty(obj.runId) && obj.runId(1) == id
                            obj.STATS = struct;
                            obj.view.handles.statTable.Data = cell([1, 4]);
                            obj.runId = [];
                        end
                    end
                    obj.updateWidgets();
            end
        end
    end % methods (Static)

    methods
        % declaration of methods in external files
        addCallbacks(obj) % Wire all widget callbacks once from the constructor
        applySelectedProperties(obj, propertyList) % Apply the property list returned by the QuantificationProperties dialog
        closeWindow(obj) % Close the Quantification dialog and release all resources
        createContextMenus(obj)  % Build the right-click context menu for statTable programmatically
        enableStatTable(obj) % Enable or disable statTable depending on whether results are available
        exportButton_Callback(obj, batchModeSwitch)  % Export quantification results to Excel, CSV, MAT file, or MATLAB workspace
        gui_WindowButtonDownFcn(obj)  % Handle mouse button press events on the histogram axes.
        highlightRange_Callback(obj) % Highlight all objects whose Value column falls within the range
        highlightSelection(obj, object_list, mode, sliceNumbers)  % Highlight selected quantification objects in the selection layer
        histScale_Callback(obj)  % Toggle the histogram Y axis between logarithmic and linear scale
        material_Callback(obj) % Handle selection change in the Material dropdown
        multiple_Callback(obj) % Handle the Multiple properties checkbox toggle
        multipleBtn_Callback(obj) % Open the property selection dialog for multi-property batch analysis
        property_Callback(obj) % Handle selection change in the Property dropdown
        quantification_Callback(obj, batchModeSwitch) % Run the shape/intensity quantification analysis and populate statTable
        radioButton_Callback(obj, hObject) % Handle Shape2D / Shape3D / Object / Intensity radio button changes
        returnBatchOpt(obj, BatchOptOut) % Publish BatchOpt to the macro recorder via 'SyncBatch' event
        data = sortBtn_Callback(obj, data) % Sort the statTable data matrix according to the current sorting settings
        statTable_CellSelectionCallback(obj, indices, parameter) % Handle cell selection in statTable and optionally highlight objects
        tableContextMenu_cb(obj, parameter) % Handle context menu actions on statTable rows
        units_Callback(obj) % Handle selection change in the Units dropdown
        updateBatchOptFromGUI(obj, hObject, ~)  % Sync BatchOpt from a changed widget using the shared utility
        updateSortingSettings(obj) % Sync sort direction and column index from the sortTable dropdown
        updateWidgets(obj) % Refresh all GUI widgets from the current model state and BatchOpt

        function obj = Quantification(mibModel, varargin)
            % QUANTIFICATION - constructor for Quantification controller.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj = controllers.Quantification(mibModel)
            %       obj = controllers.Quantification(mibModel, mibController, BatchOpt, contIndex)
            %
            % Input Arguments:
            %   - **mibModel** - handle to MibModel
            %   - **varargin{1}** - *(optional)* handle to parent MibController (for startController compatibility)
            %   - **varargin{2}** - *(optional)* BatchOpt struct; pass NaN to return default BatchOpt via SyncBatch
            %   - **varargin{3}** - *(optional)* contIndex - material index to pre-select (-1=Mask, 0=Exterior, 1,2,...=material)
            %
            % Output Arguments:
            %   - **obj** - [Quantification] initialized controller instance
            %
            % Usage:
            %   Example 1::
            %
            %     obj.startController('controllers.Quantification');
            %

            id = mibModel.getActiveId();

            % --- Property lists ---
            obj.availableProperties2D = {'Area','ConvexArea','CurveLength','Eccentricity','EquivDiameter', ...
                'EndpointsLength','EulerNumber','Extent','FilledArea','FirstAxisLength','HolesArea','MajorAxisLength', ...
                'MinorAxisLength','Orientation','Perimeter','SecondAxisLength','Solidity'};
            obj.availableProperties3D = {'Volume','EndpointsLength','EquatorialEccentricity','FilledArea','HolesArea','MajorAxisLength', ...
                'MeridionalEccentricity','SecondAxisLength','ThirdAxisLength', ...
                'ConvexVolume','EquivDiameter','Extent','Solidity','SurfaceArea'};
            obj.availablePropertiesInt = {'MinIntensity','MaxIntensity','MeanIntensity','StdIntensity','SumIntensity','Correlation'};

            % --- Parse optional contIndex ---
            contIndex = [];
            if numel(varargin) >= 1 && ~isempty(varargin{1})
                contIndex = varargin{1};  % -1, mask, 0-ext, 1-mat1...
            end
            if isempty(contIndex)
                contIndex = mibModel.I{id}.getSelectedMaterialIndex();
            end

            obj.mibModel = mibModel;

            % --- Build default BatchOpt ---
            obj.BatchOpt.MaterialIndex = num2str(contIndex);
            obj.BatchOpt.DatasetType = {'3D, Stack'};
            obj.BatchOpt.DatasetType{2} = {'2D, Slice', '3D, Stack', '4D, Dataset'};
            obj.BatchOpt.ObjectShape = {'Shape2D'};
            obj.BatchOpt.ObjectShape{2} = {'Shape2D', 'Shape3D'};
            obj.BatchOpt.DetectionType = {'Object'};
            obj.BatchOpt.DetectionType{2} = {'Object', 'Intensity'};
            obj.BatchOpt.Property = {'Area'};
            obj.BatchOpt.Property{2} = [{'---- 2D Object ----'}, obj.availableProperties2D, ...
                                         {'---- 3D Object ----'}, obj.availableProperties3D, ...
                                         {'---- Intensity ----'}, obj.availablePropertiesInt];
            obj.BatchOpt.Multiple = false;
            obj.BatchOpt.MultipleProperty = 'Area; FirstAxisLength; Orientation; SecondAxisLength; MinIntensity; MaxIntensity; MeanIntensity; SumIntensity';
            obj.BatchOpt.Connectivity = {'4/6 connectivity'};
            obj.BatchOpt.Connectivity{2} = {'4/6 connectivity', '8/26 connectivity'};
            obj.BatchOpt.Units = {'pixels'};
            obj.BatchOpt.Units{2} = {'pixels', mibModel.I{id}.image.pixSize.units};
            PossibleColChannels = arrayfun(@(x) sprintf('ColCh %d', x), 1:mibModel.I{id}.image.colors, 'UniformOutput', false);
            obj.BatchOpt.ColorChannel1 = {'ColCh 1'};
            obj.BatchOpt.ColorChannel1{2} = PossibleColChannels;
            obj.BatchOpt.ColorChannel2 = PossibleColChannels(end);
            obj.BatchOpt.ColorChannel2{2} = PossibleColChannels;
            obj.BatchOpt.ExportResultsTo = {'Excel format (*.xls)'};
            obj.BatchOpt.ExportResultsTo{2} = {'Do not export', 'Export to MATLAB', ...
                'Excel format (*.xls)', 'Comma-separated values (*.csv)', ...
                'MATLAB format (*.mat)', 'MATLAB format minimalistic (*.mat)'};
            imgFilename = mibModel.I{id}.image.filename;
            [~, imgFilename] = fileparts(imgFilename);
            obj.BatchOpt.ExportFilename = [filesep imgFilename '_analysis'];
            obj.BatchOpt.CropObjectsTo = {'Do not crop'};
            obj.BatchOpt.CropObjectsTo{2} = {'Do not crop', 'Crop to MATLAB', ...
                'Amira Mesh binary (*.am)', 'MRC format for IMOD (*.mrc)', 'NRRD Data Format (*.nrrd)', ...
                'TIF format LZW compression (*.tif)', 'TIF format uncompressed (*.tif)'};
            obj.BatchOpt.CropObjectsMarginXY = '0';
            obj.BatchOpt.CropObjectsMarginZ = '0';
            obj.BatchOpt.CropObjectsIncludeModel = {'Do not include'};
            obj.BatchOpt.CropObjectsIncludeModel{2} = {'Do not include', 'Crop to MATLAB', 'MATLAB format (*.model)', ...
                'Amira Mesh binary (*.am)', 'MRC format for IMOD (*.mrc)', 'NRRD Data Format (*.nrrd)', ...
                'TIF format LZW compression (*.tif)', 'TIF format uncompressed (*.tif)'};
            obj.BatchOpt.CropObjectsIncludeModelMaterialIndex = 'NaN';
            obj.BatchOpt.CropObjectsIncludeMask = {'Do not include'};
            obj.BatchOpt.CropObjectsIncludeMask{2} = {'Do not include', 'Crop to MATLAB', 'MATLAB format (*.mask)', ...
                'Amira Mesh binary (*.am)', 'MRC format for IMOD (*.mrc)', 'NRRD Data Format (*.nrrd)', ...
                'TIF format LZW compression (*.tif)', 'TIF format uncompressed (*.tif)'};
            obj.BatchOpt.CropObjectsOutputName = 'CropOut';
            obj.BatchOpt.CropObjectsJitter = false;
            obj.BatchOpt.Generate3DPatches = false;
            obj.BatchOpt.CropObjectsDepth = '10';
            if ~isfield(mibModel.sessionSettings, 'quantificationCropPatches') || ...
                    ~isfield(mibModel.sessionSettings.quantificationCropPatches, 'CropObjectsJitterVariation')
                mibModel.sessionSettings.quantificationCropPatches.CropObjectsJitterVariation = '50';
                mibModel.sessionSettings.quantificationCropPatches.CropObjectsJitterSeed = '0';
            end
            obj.BatchOpt.CropObjectsJitterVariation = mibModel.sessionSettings.quantificationCropPatches.CropObjectsJitterVariation;
            obj.BatchOpt.CropObjectsJitterSeed = mibModel.sessionSettings.quantificationCropPatches.CropObjectsJitterSeed;
            obj.BatchOpt.SingleMaskObjectPerDataset = false;
            obj.BatchOpt.showWaitbar = true;

            if contIndex == -1
                obj.BatchOpt.mibBatchSectionName = 'Ribbon -> Mask';
            else
                obj.BatchOpt.mibBatchSectionName = 'Ribbon -> Model';
            end
            obj.BatchOpt.mibBatchActionName = 'Quantification';

            obj.BatchOpt.mibBatchTooltip.MaterialIndex = 'Index of the material: -1=Mask, 0=Exterior, 1,2,...=material index, NaN=complete model (>255 materials)';
            obj.BatchOpt.mibBatchTooltip.DatasetType = 'Apply to a shown slice (2D, Slice), whole stack (3D, Stack) or complete dataset (4D, Dataset)';
            obj.BatchOpt.mibBatchTooltip.ObjectShape = 'ObjectShape of the objects to be identified';
            obj.BatchOpt.mibBatchTooltip.DetectionType = 'Calculate properties of objects or image intensity under the object areas';
            obj.BatchOpt.mibBatchTooltip.Property = 'Select one property; ObjectShape parameter must match';
            obj.BatchOpt.mibBatchTooltip.Multiple = 'Check to calculate multiple properties; use the MultipleProperty field';
            obj.BatchOpt.mibBatchTooltip.MultipleProperty = 'Property names separated with ";", used when Multiple is true';
            obj.BatchOpt.mibBatchTooltip.Connectivity = 'Connectivity value for object separation';
            obj.BatchOpt.mibBatchTooltip.Units = 'Units for results: pixels or physical units';
            obj.BatchOpt.mibBatchTooltip.ColorChannel1 = '[Intensity only] Color channel for analysis';
            obj.BatchOpt.mibBatchTooltip.ColorChannel2 = '[Intensity/Correlation only] Second color channel for correlation analysis';
            obj.BatchOpt.mibBatchTooltip.ExportResultsTo = 'Destination for calculated results; provide relative filename in ExportFilename';
            obj.BatchOpt.mibBatchTooltip.ExportFilename = 'Variable name or filename relative to dataset; use [F] template for dataset filename, e.g. [F]_analysis';
            obj.BatchOpt.mibBatchTooltip.CropObjectsTo = 'Also crop detected objects to disk or MATLAB';
            obj.BatchOpt.mibBatchTooltip.CropObjectsOutputName = 'Directory name or variable for cropped objects';
            obj.BatchOpt.mibBatchTooltip.CropObjectsMarginXY = 'XY margin in pixels when cropping objects';
            obj.BatchOpt.mibBatchTooltip.CropObjectsMarginZ = 'Z margin in pixels when cropping objects';
            obj.BatchOpt.mibBatchTooltip.CropObjectsIncludeModel = 'Also crop model and save next to the images';
            obj.BatchOpt.mibBatchTooltip.CropObjectsIncludeModelMaterialIndex = 'Material index to crop, or NaN to crop all';
            obj.BatchOpt.mibBatchTooltip.CropObjectsIncludeMask = 'Also crop mask and save next to the images';
            obj.BatchOpt.mibBatchTooltip.SingleMaskObjectPerDataset = 'Remove other objects within the clipping box of the main detected object';
            obj.BatchOpt.mibBatchTooltip.showWaitbar = 'Show or hide the progress bar during execution';
            obj.BatchOpt.mibBatchTooltip.CropObjectsJitter = 'Enable jitter for centroid coordinates when cropping objects';
            obj.BatchOpt.mibBatchTooltip.Generate3DPatches = 'Crop 3D patches with a fixed depth around each object centroid';
            obj.BatchOpt.mibBatchTooltip.CropObjectsDepth = 'Depth in Z slices for 3D patches';
            obj.BatchOpt.mibBatchTooltip.CropObjectsJitterVariation = 'Jitter variation in pixels';
            obj.BatchOpt.mibBatchTooltip.CropObjectsJitterSeed = 'Random generator seed (0 = random)';

            obj.sortingDirection = 'descend';
            obj.sortingColIndex = 2;

            % --- Batch mode ---
            if nargin >= 3 && ~isempty(varargin{2})
                BatchOptInput = varargin{2};
                if isstruct(BatchOptInput) == 0
                    if isnan(BatchOptInput)
                        obj.returnBatchOpt();
                    else
                        utils.dlgs.showErrorDialog([], 'A structure as the 3rd parameter is required!', 'Quantification error');
                    end
                    return;
                end
                obj.BatchOpt.MultipleProperty = 'Area';
                obj.BatchOpt = utils.updateBatchOptCombineFields_Shared(obj.BatchOpt, BatchOptInput);
                if strcmp(obj.BatchOpt.Property{1}, 'EndpointsLength') || strcmp(obj.BatchOpt.Property{1}, 'CurveLength')
                    obj.BatchOpt.Connectivity{1} = '8/26 connectivity';
                end
                obj.quantification_Callback(1);
                return;
            end

            % --- Create view ---
            guiName = 'views.QuantificationGUI';
            obj.view = core.ChildView(obj, guiName);

            obj.addCallbacks();

            % update font and size
            Font = obj.mibModel.preferences.System.Font;
            if obj.view.handles.Multiple.FontSize ~= Font.FontSize ...
                    || ~strcmp(obj.view.handles.Multiple.FontName, Font.FontName)
                utils.fontSizeUpdate(obj.view.gui, Font);
            end
            % move the window to the left hand side of the main window
            obj.view.gui = utils.moveWindowOutside(obj.view.gui, obj.mibModel.mibGUI, 'left');

            % --- Initialize state ---
            obj.intType = 1;
            obj.obj2DType = 1;
            obj.obj3DType = 1;
            obj.statProperties = {'Area'};
            obj.sortingRowIndex = [];
            obj.indices = [];
            obj.histLimits = [0 1];
            obj.STATS = struct();
            obj.runId = [];
            obj.sessionSettingsKey = 'quantificationCropPatches';
            obj.anisotropicVoxelsAgree = 0;
            obj.childControllers = {};
            obj.childControllersIds = {};

            obj.updateWidgets();

            % Pre-select material based on contIndex
            items = obj.view.handles.Material.Items;
            if contIndex >= 1
                contIndex = mibModel.I{id}.selectedMaterial;
                if mibModel.I{id}.labels.maxMaterials < 256
                    idx = contIndex;
                else
                    idx = contIndex + 1;
                end
                if idx >= 1 && idx <= numel(items)
                    obj.view.handles.Material.Value = items{idx};
                end
            else
                if ~isempty(items)
                    obj.view.handles.Material.Value = items{1};
                end
            end
            obj.material_Callback();

            % add handle tags to the tooltips
            if obj.mibModel.preferences.System.DeveloperMode
                utils.overrideDescriptions(obj.view.handles, true, 'obj.view.handles');
            end
            % show the gui
            obj.view.gui.Visible = 'on';    % turn on the window

            % --- Register model listeners ---
            obj.listener{1} = addlistener(obj.mibModel, 'UpdateGuiWidgets', @(src, evnt) controllers.Quantification.ViewListner_Callback2(obj, src, evnt));
            obj.listener{2} = addlistener(obj.mibModel, 'NewDataset', @(src, evnt) controllers.Quantification.ViewListner_Callback2(obj, src, evnt));
        end

    end % methods
end
