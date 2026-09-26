classdef CropDataset < handle
% CROPDATASET - @type CropDataset class is responsible for showing the dataset.
%
% crop window, available from MIB Ribbon Dataset Crop
%
%
% .. code-block:: matlab
%
%   obj.startController('controllers.CropDataset'); // as GUI tool

    % Updates
    % ported to MIB3 AppDesigner framework

    properties
        mibModel
        % handles to the model
        view
        % handle to the view / views.CropDatasetGUI
        listener
        % a cell array with handles to listeners
        roiPos
        % a cell array with position of the ROI for crop
        % obj.roiPos{1} = [1, width, 1, height, 1, depth, 1, time];
        mibController
        % handle to controllers.MibController - used to resolve the active
        % image axes dynamically (split-panel safe); see cropBtn_Callback
        mibImageAxes
        % handle to the main image axes of MIB (needed for Interactive mode).
        % Optional fallback; prefer mibController-based resolution when available
        currentMode
        % a string with the selected crop mode: 'Interactive','Manual','ROI'
        BatchOpt
        % a structure compatible with batch operation, see details in the constructor
        batchProcessingSwitch
        % logical indicating whether the batch processing mode is used
    end

    events
        %> Description of events
        CloseEvent
        % event firing when window is closed
    end

    methods (Static)
        function ViewListner_Callback2(obj, src, evnt)
            % VIEWLISTNER_CALLBACK2 - Guard: if the view window was closed, clean up listeners and return.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.ViewListner_Callback2(src, evnt)
            %
            if ~isvalid(obj) || isempty(obj.view) || ~isvalid(obj.view.gui)
                for i = 1:numel(obj.listener)
                    delete(obj.listener{i});
                end
                return;
            end
            switch evnt.EventName
                case {'UpdateGuiWidgets', 'NewDataset'}
                    obj.updateWidgets();
            end
        end
    end

    methods
        function obj = CropDataset(mibModel, varargin)
            % CROPDATASET - obj = CropDataset(mibModel, varargin).
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj = CropDataset(mibModel)
            %       obj = CropDataset(mibModel, mibController)
            %       obj = CropDataset(mibModel, mibController, BatchOpt)
            %
            % Constructor of the CropDataset controller
            %
            % Input Arguments:
            %   - **mibModel** - handle to MibModel
            %   - **varargin{1}** - *(optional)* handle to controllers.MibController
            %     (canonical, split-panel safe) OR an axes handle (legacy)
            %     OR a BatchOpt struct / NaN (batch mode with no controller)
            %   - **varargin{2}** - *(optional)* BatchOpt struct / NaN when varargin{1}
            %     is a controller or axes handle
            %
            % Usage:
            %   Example 1::
            %
            %     obj.startController('controllers.CropDataset');
            %
            %   Example 2::
            %
            %     obj.startController('controllers.CropDataset', obj);
            %
            %   Example 3::
            %
            %     obj.startController('controllers.CropDataset', obj, BatchOpt);
            %

            obj.mibModel = mibModel;
            id = obj.mibModel.getActiveId();
            obj.batchProcessingSwitch = false;

            getDataOpt.blockModeSwitch = 0;
            [height, width, depth, ~, time] = obj.mibModel.I{id}.getDatasetDimensions('image', 3, getDataOpt);

            % fill BatchOpt structure with default parameters
            maxId = obj.mibModel.Sets.datasetsInSet * numel(obj.mibModel.Sets.names);
            destBuffers = arrayfun(@(x) sprintf('Container %d', x), 1:maxId, 'UniformOutput', false);
            destBuffers = ['Current', destBuffers];

            [~, indicesOfROI] = obj.mibModel.I{id}.hROI.getNumberOfROI(0);
            ROIlist{1} = 'All';
            i = 2;
            for idx = indicesOfROI
                ROIlist(i) = obj.mibModel.I{id}.hROI.Data(idx).label; %#ok<AGROW>
                i = i + 1;
            end

            obj.BatchOpt.Width  = sprintf('%d:%d', 1, width);
            obj.BatchOpt.Height = sprintf('%d:%d', 1, height);
            obj.BatchOpt.Depth  = sprintf('%d:%d', 1, depth);
            obj.BatchOpt.Time   = sprintf('%d:%d', 1, time);

            % crop mode: radio button group stored as a cell {selected, {options}}
            obj.BatchOpt.cropMode    = {'Interactive'};
            obj.BatchOpt.cropMode{2} = {'Interactive', 'Manual', 'ROI'};

            obj.BatchOpt.Destination    = {'Current'};
            obj.BatchOpt.Destination{2} = destBuffers;

            obj.BatchOpt.ZarrPyramidLevel{2} = arrayfun(@(x) sprintf('s%d', x), 0:9, 'UniformOutput', false);
            obj.BatchOpt.ZarrPyramidLevel(1) = obj.BatchOpt.ZarrPyramidLevel{2}(1);

            obj.BatchOpt.OutputType    = {'Standard'};
            obj.BatchOpt.OutputType{2} = {'Standard', 'BigData'};

            obj.BatchOpt.SelectROI    = {'All'};
            obj.BatchOpt.SelectROI{2} = ROIlist;

            obj.BatchOpt.showWaitbar = true;

            % batch tool metadata
            obj.BatchOpt.mibBatchSectionName = 'Ribbon -> Dataset';
            obj.BatchOpt.mibBatchActionName  = 'Crop dataset';

            obj.BatchOpt.mibBatchTooltip.Width            = sprintf('[Manual mode only]\nRange of points for the cropping in X\nFor example, "100:200", "1:end"');
            obj.BatchOpt.mibBatchTooltip.Height           = sprintf('[Manual mode only]\nRange of points for the cropping in Y\nFor example, "100:200", "1:end"');
            obj.BatchOpt.mibBatchTooltip.Depth            = sprintf('[Manual mode only]\nRange of points for the cropping in Z\nFor example, "100:200", "1:end"');
            obj.BatchOpt.mibBatchTooltip.Time             = sprintf('[Manual mode only]\nRange of points for the cropping in T\nFor example, "10:20", "1:end"');
            obj.BatchOpt.mibBatchTooltip.cropMode         = sprintf('"Interactive" - not compatible with batch mode\n"Manual" - use Width/Height/Depth/Time fields\n"ROI" - crop to selected ROI bounding box');
            obj.BatchOpt.mibBatchTooltip.Destination      = sprintf('Destination container');
            obj.BatchOpt.mibBatchTooltip.ZarrPyramidLevel = sprintf('[Zarr only] Level of the Zarr dataset to generate the crop operation');
            obj.BatchOpt.mibBatchTooltip.SelectROI        = sprintf('[ROI mode only]\nSelected ROI for the cropping');
            obj.BatchOpt.mibBatchTooltip.showWaitbar      = sprintf('Show or not the progress bar during execution');
            obj.BatchOpt.mibBatchTooltip.OutputType       = sprintf('[BigData source only]\n"Standard" = load cropped region into memory\n"BigData" = write cropped pyramid to a new Zarr folder on disk');

            % ---- parse varargin ----
            % Canonical: varargin{1} = controllers.MibController
            %            varargin{2} = [@em optional] BatchOpt struct / NaN
            % Legacy:    varargin{1} = axes handle (graphics object)
            %            varargin{2} = [@em optional] BatchOpt struct / NaN
            % Legacy:    varargin{1} = BatchOpt struct or NaN (no controller/axes)
            axesOverride = [];
            batchOptArg  = [];

            if numel(varargin) >= 1 && isa(varargin{1}, 'controllers.MibController')
                obj.mibController = varargin{1};
                if numel(varargin) >= 2; batchOptArg = varargin{2}; end
            elseif numel(varargin) >= 1 && ~isempty(varargin{1}) && isgraphics(varargin{1})
                axesOverride = varargin{1};
                if numel(varargin) >= 2; batchOptArg = varargin{2}; end
            elseif numel(varargin) >= 1 && (isstruct(varargin{1}) || ...
                    (isnumeric(varargin{1}) && isscalar(varargin{1}) && isnan(varargin{1})))
                batchOptArg = varargin{1};
            elseif numel(varargin) >= 2
                batchOptArg = varargin{2};
            end

            if ~isempty(axesOverride); obj.mibImageAxes = axesOverride; end

            if ~isempty(batchOptArg)
                BatchOptInput = batchOptArg;
                if isstruct(BatchOptInput) == 0
                    if isnan(BatchOptInput)
                        obj.returnBatchOpt();
                    else
                        utils.dlgs.showErrorDialog([], 'A structure as the batch parameter is required!', 'Error');
                    end
                    notify(obj, 'CloseEvent');
                    return;
                end

                % combine fields from input and default structures
                obj.BatchOpt = utils.updateBatchOptCombineFields_Shared(obj.BatchOpt, BatchOptInput);

                if strcmp(obj.BatchOpt.cropMode{1}, 'Interactive')
                    utils.dlgs.showErrorDialog([], ...
                        sprintf('!!! Error !!!\n\nCrop tool in the batch mode is not compatible with the "Interactive" option!'), ...
                        'Crop: initialization error');
                    notify(obj.mibModel, 'StopProtocol');
                    notify(obj, 'CloseEvent');
                    return;
                end

                % replace 'end' tokens with actual dimension values
                dataset = obj.mibModel.I{id};
                if contains(obj.BatchOpt.Depth,  'end')
                    obj.BatchOpt.Depth  = strrep(obj.BatchOpt.Depth,  'end', num2str(dataset.image.depth));
                end
                if contains(obj.BatchOpt.Height, 'end')
                    obj.BatchOpt.Height = strrep(obj.BatchOpt.Height, 'end', num2str(dataset.image.height));
                end
                if contains(obj.BatchOpt.Width,  'end')
                    obj.BatchOpt.Width  = strrep(obj.BatchOpt.Width,  'end', num2str(dataset.image.width));
                end
                if contains(obj.BatchOpt.Time,   'end')
                    obj.BatchOpt.Time   = strrep(obj.BatchOpt.Time,   'end', num2str(dataset.image.time));
                end

                obj.batchProcessingSwitch = true;
                obj.cropBtn_Callback();
                notify(obj, 'CloseEvent');
                return;
            end

            % ---- GUI mode path ----
            guiName = 'views.CropDatasetGUI';
            obj.view = core.ChildView(obj, guiName);
            utils.applyThemeColors(obj.view.gui);   % adapt the standard dialog button colors to the light/dark theme

            obj.addCallbacks();

            % update font and size
            Font = obj.mibModel.preferences.System.Font;
            if obj.view.handles.descriptionText.FontSize ~= Font.FontSize ...
                    || ~strcmp(obj.view.handles.descriptionText.FontName, Font.FontName)
                utils.fontSizeUpdate(obj.view.gui, Font);
            end

            % move window to the left of the main MIB window
            obj.view.gui = utils.moveWindowOutside(obj.view.gui, obj.mibModel.mibGUI, 'left');

            obj.currentMode = 'Manual';
            obj.updateWidgets();

            % add handle tags to tooltips in developer mode
            if obj.mibModel.preferences.System.DeveloperMode
                utils.overrideDescriptions(obj.view.handles, true, 'obj.view.handles');
            end

            obj.view.gui.Visible = 'on';

            % add listeners
            obj.listener{1} = addlistener(obj.mibModel, 'UpdateGuiWidgets', @(src, evnt) obj.ViewListner_Callback2(obj, src, evnt));
            obj.listener{2} = addlistener(obj.mibModel, 'NewDataset',       @(src, evnt) obj.ViewListner_Callback2(obj, src, evnt));
        end

        function closeWindow(obj)
            % CLOSEWINDOW - closing CropDataset window.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.closeWindow()
            %

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.CropDataset.closeWindow: triggered\n');
            end
            if isvalid(obj.view.gui)
                delete(obj.view.gui);
            end

            for i = 1:numel(obj.listener)
                delete(obj.listener{i});
            end

            notify(obj, 'CloseEvent');
        end

        function addCallbacks(obj)
            % ADDCALLBACKS - assign callbacks to all interactive widgets; called once from.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.addCallbacks()
            %
            % the constructor after the view is created

            obj.view.gui.CloseRequestFcn = @(~,~) obj.closeWindow();

            h = obj.view.handles;

            % radio button group (Interactive / Manual / ROI)
            h.cropMode.SelectionChangedFcn = @(~, event) obj.radio_Callback(event.NewValue);

            % edit fields
            h.Width.ValueChangedFcn  = @(~,~) obj.editboxes_Callback();
            h.Height.ValueChangedFcn = @(~,~) obj.editboxes_Callback();
            h.Depth.ValueChangedFcn  = @(~,~) obj.editboxes_Callback();
            h.Time.ValueChangedFcn   = @(~,~) obj.editboxes_Callback();

            % dropdowns
            h.SelectROI.ValueChangedFcn        = @(~,~) obj.SelectROI_Callback();
            h.ZarrPyramidLevel.ValueChangedFcn = @(src,~) obj.ZarrPyramidLevel_Callback(src);
            h.OutputType.ValueChangedFcn       = @(src,~) obj.OutputType_Callback(src);

            % buttons
            h.selectAreaBtn.ButtonPushedFcn = @(~,~) obj.selectAreaBtn_Callback();
            h.resetBtn.ButtonPushedFcn  = @(~,~) obj.resetBtn_Callback();
            h.cropBtn.ButtonPushedFcn   = @(src,~) obj.cropBtn_Callback(src);
            h.croptoBtn.ButtonPushedFcn = @(~,~) obj.cropToBtn_Callback();
            h.helpButton.ButtonPushedFcn = @(~,~) obj.helpButton_Callback();
            h.closeBtn.ButtonPushedFcn  = @(~,~) obj.closeWindow();
        end

        function returnBatchOpt(obj, BatchOptOut)
            % RETURNBATCHOPT - return structure with Batch Options via the 'SyncBatch' event.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.returnBatchOpt()
            %       obj.returnBatchOpt(BatchOptOut)
            %
            % Input Arguments:
            %   - **BatchOptOut** - *(optional)* local BatchOpt to send; defaults to obj.BatchOpt
            %

            if nargin < 2; BatchOptOut = obj.BatchOpt; end
            if isfield(BatchOptOut, 'id'); BatchOptOut = rmfield(BatchOptOut, 'id'); end
            eventdata = core.ToggleEventData(BatchOptOut);
            notify(obj.mibModel, 'SyncBatch', eventdata);
        end

        function updateBatchOptFromGUI(obj, hObject)
            % UPDATEBATCHOPTFROMGUI - update obj.BatchOpt from a GUI widget.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.updateBatchOptFromGUI(hObject)
            %
            % Input Arguments:
            %   - **hObject** - handle to the widget that changed
            %

            obj.BatchOpt = utils.updateBatchOptFromGUI_Shared(obj.BatchOpt, hObject);
        end

        function updateWidgets(obj)
            % UPDATEWIDGETS - update all widgets of the current window.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.updateWidgets()
            %

            id = obj.mibModel.id;
            dataset = obj.mibModel.I{id};

            obj.view.handles.Width.Value  = sprintf('1:%d', dataset.image.width);
            obj.view.handles.Height.Value = sprintf('1:%d', dataset.image.height);
            obj.view.handles.Depth.Value  = sprintf('1:%d', dataset.image.depth);
            obj.view.handles.Time.Value   = sprintf('1:%d', dataset.image.time);

            obj.roiPos{1} = NaN;

            % read currently selected mode from the button group
            obj.currentMode = obj.view.handles.cropMode.SelectedObject.Tag;

            % check ROI availability
            [numberOfROI, indicesOfROI] = dataset.hROI.getNumberOfROI(0);
            if numberOfROI == 0
                obj.view.handles.ROI.Enable = 'off';
                if strcmp(obj.currentMode, 'ROI')
                    obj.currentMode = 'Manual';
                    obj.BatchOpt.cropMode{1} = 'Manual';
                    obj.view.handles.cropMode.SelectedObject = obj.view.handles.Manual;
                end
            end

            obj.radio_Callback(obj.view.handles.(obj.currentMode));

            % populate ROI dropdown
            list{1} = 'All';
            i = 2;
            for idx = indicesOfROI
                list(i) = dataset.hROI.Data(idx).label; %#ok<AGROW>
                i = i + 1;
            end
            obj.view.handles.SelectROI.Items = list;

            if numel(list) > 1
                selIdx = max([dataset.selectedROI + 1, 2]);
                if selIdx > numel(list); selIdx = numel(list); end
                obj.view.handles.SelectROI.Value = list{selIdx};
                obj.view.handles.ROI.Enable = 'on';
            else
                obj.view.handles.SelectROI.Value = list{1};
            end

            % update OutputType and Zarr pyramid dropdowns
            isBigData = ~isempty(dataset.image.pyramid.levelNames) && strcmp(dataset.datasetType, 'BigData');
            obj.view.handles.OutputType.Enable = matlab.lang.OnOffSwitchState(isBigData);
            if ~isBigData
                obj.BatchOpt.OutputType{1} = 'Standard';
                obj.view.handles.OutputType.Value = 'Standard';
            end
            outputIsStandard = strcmp(obj.BatchOpt.OutputType{1}, 'Standard');
            if isempty(dataset.image.pyramid.levelNames)
                obj.BatchOpt.ZarrPyramidLevel(1) = obj.BatchOpt.ZarrPyramidLevel{2}(1);
                obj.view.handles.ZarrPyramidLevel.Enable = 'off';
            else
                obj.view.handles.ZarrPyramidLevel.Enable = matlab.lang.OnOffSwitchState(outputIsStandard);
            end
            obj.view.handles.ZarrPyramidLevel.Items = obj.BatchOpt.ZarrPyramidLevel{2};
            obj.view.handles.ZarrPyramidLevel.Value = obj.BatchOpt.ZarrPyramidLevel{1};
            obj.selectZarrLevel();
        end

        function radio_Callback(obj, hObject)
            % RADIO_CALLBACK - callback for selection of crop mode.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.radio_Callback(hObject)
            %
            % Input Arguments:
            %   - **hObject** - handle to the selected radio button (Interactive, Manual, or ROI)
            %

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.CropDataset.radio_Callback(%s): triggered\n', hObject.Tag);
            end
            mode = hObject.Tag;
            id = obj.mibModel.getActiveId();

            obj.view.handles.SelectROI.Enable = 'off';
            obj.view.handles.Width.Enable     = 'off';
            obj.view.handles.Height.Enable    = 'off';
            obj.view.handles.Depth.Enable     = 'off';

            if obj.mibModel.I{id}.image.time > 1
                obj.view.handles.Time.Enable = 'on';
            else
                obj.view.handles.Time.Enable = 'off';
            end

            obj.BatchOpt.cropMode{1} = mode;

            switch mode
                case 'Interactive'
                    text = sprintf('Interactive mode allows to draw a rectangle that will be used for cropping.\nTo start, press the Crop button and use the left mouse button to draw an area, double click over the area to crop');
                    obj.editboxes_Callback();
                case 'Manual'
                    obj.view.handles.Width.Enable  = 'on';
                    obj.view.handles.Height.Enable = 'on';
                    obj.view.handles.Depth.Enable  = 'on';
                    text = sprintf('In the manual mode the numbers entered in the edit boxes below will be used for cropping');
                    obj.editboxes_Callback();
                case 'ROI'
                    obj.view.handles.SelectROI.Enable = 'on';
                    text = sprintf('Use existing ROIs to crop the image');
                    obj.SelectROI_Callback();
            end

            obj.view.handles.descriptionText.Text    = text;
            obj.view.handles.descriptionText.Tooltip = text;
            obj.currentMode = mode;

            % keep BatchOpt in sync
            obj.BatchOpt.Width  = obj.view.handles.Width.Value;
            obj.BatchOpt.Height = obj.view.handles.Height.Value;
            obj.BatchOpt.Depth  = obj.view.handles.Depth.Value;
            obj.BatchOpt.Time   = obj.view.handles.Time.Value;

            obj.updateBatchOptFromGUI(obj.view.handles.cropMode);
        end

        function editboxes_Callback(obj)
            % EDITBOXES_CALLBACK - update obj.BatchOpt and obj.roiPos from the Width/Height/Depth/Time fields.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.editboxes_Callback()
            %

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.CropDataset.editboxes_Callback: triggered\n');
            end
            obj.BatchOpt.Width  = obj.view.handles.Width.Value;
            obj.BatchOpt.Height = obj.view.handles.Height.Value;
            obj.BatchOpt.Depth  = obj.view.handles.Depth.Value;
            obj.BatchOpt.Time   = obj.view.handles.Time.Value;

            str2 = obj.BatchOpt.Width;
            obj.roiPos{1}(1) = min(str2num(str2)); %#ok<ST2NM>
            obj.roiPos{1}(2) = max(str2num(str2)); %#ok<ST2NM>
            str2 = obj.BatchOpt.Height;
            obj.roiPos{1}(3) = min(str2num(str2)); %#ok<ST2NM>
            obj.roiPos{1}(4) = max(str2num(str2)); %#ok<ST2NM>
            str2 = obj.BatchOpt.Depth;
            obj.roiPos{1}(5) = min(str2num(str2)); %#ok<ST2NM>
            obj.roiPos{1}(6) = max(str2num(str2)); %#ok<ST2NM>
            str2 = obj.BatchOpt.Time;
            obj.roiPos{1}(7) = min(str2num(str2)); %#ok<ST2NM>
            obj.roiPos{1}(8) = max(str2num(str2)); %#ok<ST2NM>
        end

        function SelectROI_Callback(obj)
            % SELECTROI_CALLBACK - callback for change of the SelectROI dropdown.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.SelectROI_Callback()
            %

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.CropDataset.SelectROI_Callback: triggered\n');
            end
            % convert dropdown string value to 0-based ROI index
            val = obj.view.handles.SelectROI.ValueIndex - 1;
            id = obj.mibModel.getActiveId();
            dataset = obj.mibModel.I{id};

            str2 = obj.view.handles.Time.Value;
            tMin = min(str2num(str2)); %#ok<ST2NM>
            tMax = max(str2num(str2)); %#ok<ST2NM>

            if val == 0     % 'All' - collect bounding box of every ROI
                [~, roiIndices] = dataset.hROI.getNumberOfROI(0);
                i = 1;
                for idx = roiIndices
                    obj.roiPos{i} = dataset.getRoiBoundingBox(idx);
                    obj.roiPos{i}(7:8) = [tMin, tMax];
                    i = i + 1;
                end
                obj.view.handles.Width.Value  = 'Multi';
                obj.view.handles.Height.Value = 'Multi';
                obj.view.handles.Depth.Value  = 'Multi';
            else
                bb{1} = dataset.getRoiBoundingBox(val);
                obj.view.handles.Width.Value  = [num2str(bb{1}(1)) ':' num2str(bb{1}(2))];
                obj.view.handles.Height.Value = [num2str(bb{1}(3)) ':' num2str(bb{1}(4))];
                obj.view.handles.Depth.Value  = [num2str(bb{1}(5)) ':' num2str(bb{1}(6))];
                obj.roiPos{1} = bb{1};
                obj.roiPos{1}(7:8) = [tMin, tMax];
            end

            obj.BatchOpt.Width  = obj.view.handles.Width.Value;
            obj.BatchOpt.Height = obj.view.handles.Height.Value;
            obj.BatchOpt.Depth  = obj.view.handles.Depth.Value;
            obj.BatchOpt.Time   = obj.view.handles.Time.Value;
        end

        function resetBtn_Callback(obj)
            % RESETBTN_CALLBACK - reset crop fields to full image dimensions.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.resetBtn_Callback()
            %

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.CropDataset.resetBtn_Callback: triggered\n');
            end
            id = obj.mibModel.getActiveId();
            dataset = obj.mibModel.I{id};

            obj.view.handles.Width.Value  = sprintf('1:%d', dataset.image.width);
            obj.view.handles.Height.Value = sprintf('1:%d', dataset.image.height);
            obj.view.handles.Depth.Value  = sprintf('1:%d', dataset.image.depth);
            obj.view.handles.Time.Value   = sprintf('1:%d', dataset.image.time);

            obj.roiPos{1} = [1, dataset.image.width, 1, dataset.image.height, ...
                             1, dataset.image.depth, 1, dataset.image.time];

            obj.view.handles.cropMode.SelectedObject = obj.view.handles.Manual;
            obj.radio_Callback(obj.view.handles.Manual);
        end

        function selectAreaBtn_Callback(obj)
            % SELECTAREABTN_CALLBACK - pick the crop area on the image and put it into the edit boxes.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.selectAreaBtn_Callback()
            %
            % Uses the same rectangle drawing tool as the Interactive crop mode
            % (obj.drawCropArea), but instead of cropping fills the Width, Height
            % and Depth edit boxes with the coordinates of the drawn rectangle.
            % Only the two dimensions defined by the shown orientation are
            % updated, the third one is left untouched. After a successful
            % selection the dialog is switched to the Manual mode, so that the
            % Crop and Crop to... buttons use the new coordinates.
            %

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.CropDataset.selectAreaBtn_Callback: triggered\n');
            end

            position = obj.drawCropArea();   % [x1, y1, x2, y2] in data pixels of the shown plane
            if isempty(position); return; end

            id = obj.mibModel.id;
            dataset = obj.mibModel.I{id};

            switch dataset.orientation
                case 3      % XY plane: the rectangle defines Width and Height
                    obj.view.handles.Width.Value  = sprintf('%d:%d', position(1), position(3));
                    obj.view.handles.Height.Value = sprintf('%d:%d', position(2), position(4));
                case 1      % ZX plane: the rectangle defines Depth and Width
                    obj.view.handles.Depth.Value = sprintf('%d:%d', position(1), position(3));
                    obj.view.handles.Width.Value = sprintf('%d:%d', position(2), position(4));
                case 2      % ZY plane: the rectangle defines Depth and Height
                    obj.view.handles.Depth.Value  = sprintf('%d:%d', position(1), position(3));
                    obj.view.handles.Height.Value = sprintf('%d:%d', position(2), position(4));
            end

            % the ROI mode with "All" selected leaves 'Multi' in the edit boxes;
            % restore the full range for the dimension the rectangle does not define
            if strcmp(obj.view.handles.Width.Value,  'Multi')
                obj.view.handles.Width.Value  = sprintf('1:%d', dataset.image.width);
            end
            if strcmp(obj.view.handles.Height.Value, 'Multi')
                obj.view.handles.Height.Value = sprintf('1:%d', dataset.image.height);
            end
            if strcmp(obj.view.handles.Depth.Value,  'Multi')
                obj.view.handles.Depth.Value  = sprintf('1:%d', dataset.image.depth);
            end

            % switch to the Manual mode; radio_Callback calls editboxes_Callback
            % which syncs obj.BatchOpt and obj.roiPos with the new values
            obj.view.handles.cropMode.SelectedObject = obj.view.handles.Manual;
            obj.radio_Callback(obj.view.handles.Manual);
        end

        function selectZarrLevel(obj)
            % SELECTZARRLEVEL - update Zarr downsampling info label based on the selected pyramid level.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.selectZarrLevel()
            %

            id = obj.mibModel.getActiveId();

            items = obj.view.handles.ZarrPyramidLevel.Items;
            zarrIdx = find(strcmp(items, obj.view.handles.ZarrPyramidLevel.Value), 1);
            if isempty(zarrIdx); zarrIdx = 1; end

            scaleFactors = obj.mibModel.I{id}.image.pyramid.levelScaleFactors;
            if zarrIdx > size(scaleFactors, 1)
                zarrIdx = size(scaleFactors, 1);
                obj.view.handles.ZarrPyramidLevel.Value = items{zarrIdx};
            end

            scales = scaleFactors(zarrIdx, :);
            obj.view.handles.zarrBinningFactors.Text = ...
                sprintf('Zarr downsampling scales (XYZ): %d x %d x %d', scales(2), scales(1), scales(3));
        end

        function ZarrPyramidLevel_Callback(obj, hObject)
            % ZARRPYRAMIDLEVEL_CALLBACK - callback for the Zarr pyramid level dropdown.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.ZarrPyramidLevel_Callback(hObject)
            %

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.CropDataset.ZarrPyramidLevel_Callback: triggered\n');
            end
            obj.selectZarrLevel();
            obj.updateBatchOptFromGUI(hObject);
        end

        function OutputType_Callback(obj, hObject)
            % OUTPUTTYPE_CALLBACK - callback for the OutputType dropdown.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.OutputType_Callback(hObject)
            %
            % Toggles ZarrPyramidLevel enable based on the selected output type.
            % ZarrPyramidLevel is only applicable for BigData → Standard export.

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.CropDataset.OutputType_Callback: triggered\n');
            end
            obj.updateBatchOptFromGUI(hObject);
            id = obj.mibModel.getActiveId();
            dataset = obj.mibModel.I{id};
            outputIsStandard = strcmp(obj.BatchOpt.OutputType{1}, 'Standard');
            if ~isempty(dataset.image.pyramid.levelNames)
                obj.view.handles.ZarrPyramidLevel.Enable = matlab.lang.OnOffSwitchState(outputIsStandard);
            end
        end

        function cropToBtn_Callback(obj)
            % CROPTOBTN_CALLBACK - select a destination buffer and perform crop there.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.cropToBtn_Callback()
            %

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.CropDataset.cropToBtn_Callback: triggered\n');
            end
            if strcmp(obj.BatchOpt.Width, 'Multi')
                dlgOpt.MsgBoxOnly  = true;
                dlgOpt.Icon        = 'puffin_warning';
                dlgOpt.HeaderLines = 1;
                utils.dlgs.inputUniversalDlg(obj.view.gui, ...
                    'Oops, not implemented yet!', {''}, ...
                    {sprintf('Please select a single ROI from the Select ROI combobox')}, ...
                    'Multiple ROI crop', dlgOpt);
                notify(obj.mibModel, 'StopProtocol');
                return;
            end

            % Resolve the default destination: first empty container in the current set
            datasetsInSet = obj.mibModel.Sets.datasetsInSet;
            selectedSet   = obj.mibModel.Sets.selectedSet;
            destGlobalId  = selectedSet * datasetsInSet;   % fallback: last in current set
            for i = 1:datasetsInSet * numel(obj.mibModel.Sets.names)
                if strcmp(obj.mibModel.I{i}.image.filename, 'none.tif')
                    destGlobalId = i;
                    break;
                end
            end
            destSetIdx  = ceil(destGlobalId / datasetsInSet);
            destLocalId = mod(destGlobalId - 1, datasetsInSet) + 1;

            prompts  = {'Destination set:', sprintf('Destination buffer (1-%d):', datasetsInSet)};
            setItems = obj.mibModel.Sets.names(:)';
            defAns   = {[setItems, {destSetIdx}], ...
                        struct('Spinner', true, 'Value', destLocalId, 'Limits', [1 datasetsInSet], 'Step', 1, 'Round', true)};
            dlgOptions.mibPath       = obj.mibModel.mibPath;
            dlgOptions.LabelPosition = 'left';
            dlgOptions.Focus         = 2;
            [answer, selIndex] = utils.dlgs.inputUniversalDlg(obj.view.gui, '', prompts, defAns, 'Crop dataset to', dlgOptions);
            if isempty(answer); return; end

            destSetIdx   = selIndex(1);
            destLocalId  = answer{2};
            destGlobalId = destLocalId + (destSetIdx - 1) * datasetsInSet;

            obj.BatchOpt.Destination(1) = {sprintf('Container %d', destGlobalId)};
            obj.cropBtn_Callback();
        end

        function cropBtn_Callback(obj, hObject)
            % CROPBTN_CALLBACK - perform the crop operation.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.cropBtn_Callback()
            %       obj.cropBtn_Callback(hObject)
            %
            % Input Arguments:
            %   - **hObject** - *(optional)* handle to the pressed button (cropBtn or croptoBtn)
            %

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.CropDataset.cropBtn_Callback: triggered\n');
            end
            if nargin > 1
                if strcmp(hObject.Tag, 'cropBtn')
                    obj.BatchOpt.Destination(1) = {'Current'};
                end
            end

            BatchOptLoc = obj.BatchOpt;
            id          = obj.mibModel.id;

            % Parent figure for all dialogs of this operation: the crop window
            % when it is open, otherwise the main MIB window (batch mode)
            if ~isempty(obj.view) && isvalid(obj.view.gui)
                progressParent = obj.view.gui;
            else
                progressParent = obj.mibModel.getProgressBarParent();
            end

            if strcmp(BatchOptLoc.cropMode{1}, 'Interactive')
                % --- Interactive mode: draw a rectangle on the image axes ---
                position = obj.drawCropArea();
                if isempty(position); return; end

                switch obj.mibModel.I{id}.orientation
                    case 3   % XY plane
                        crop_factor = [position(1:2), position(3)-position(1)+1, position(4)-position(2)+1, ...
                            1, obj.mibModel.I{id}.image.depth];
                    case 1   % XZ plane
                        crop_factor = [position(2), 1, position(4)-position(2)+1, obj.mibModel.I{id}.image.height, ...
                            position(1), position(3)-position(1)+1];
                    case 2   % YZ plane
                        crop_factor = [1, position(2), obj.mibModel.I{id}.image.width, position(4)-position(2)+1, ...
                            position(1), position(3)-position(1)+1];
                end

            else
                % --- Manual / ROI mode ---
                if strcmp(BatchOptLoc.Width, 'Multi')
                    dlgOpt.MsgBoxOnly  = true;
                    dlgOpt.Icon        = 'puffin_warning';
                    dlgOpt.HeaderLines = 1;
                    utils.dlgs.inputUniversalDlg(progressParent, ...
                        'Oops, not implemented yet!', {''}, ...
                        {'Please select a single ROI from the Select ROI combobox'}, ...
                        'Multiple ROI crop', dlgOpt);
                    notify(obj.mibModel, 'StopProtocol');
                    return;
                end

                cropDim = str2num(BatchOptLoc.Width);  %#ok<ST2NM>
                x1 = min(cropDim);  x2 = max(cropDim);
                cropDim = str2num(BatchOptLoc.Height); %#ok<ST2NM>
                y1 = min(cropDim);  y2 = max(cropDim);
                cropDim = str2num(BatchOptLoc.Depth);  %#ok<ST2NM>
                z1 = min(cropDim);  z2 = max(cropDim);
                crop_factor = [x1, y1, x2-x1+1, y2-y1+1, z1, z2-z1+1];
            end

            % determine destination buffer
            bigDataOutput = isfield(BatchOptLoc, 'OutputType') && strcmp(BatchOptLoc.OutputType{1}, 'BigData');
            if ~strcmp(BatchOptLoc.Destination{1}, sprintf('Container %d', id)) && ...
                    ~strcmp(BatchOptLoc.Destination{1}, 'Current')
                % 'Container 12' -> 12; parsing only the last character breaks
                % for two-digit container indices (datasetsInSet is 10)
                bufferId = sscanf(BatchOptLoc.Destination{1}, 'Container %d');
                % deep-copy dataset to destination buffer before cropping
                % (skipped for BigData output - cropToBigData creates the destination fresh)
                if ~bigDataOutput
                    copyOpts.showWaitbar = BatchOptLoc.showWaitbar;
                    copyOpts.UIFigure    = progressParent;
                    obj.mibModel.deepCopyDataset(id, bufferId, copyOpts);
                end
            else
                bufferId = id;
                if ~obj.batchProcessingSwitch
                    obj.mibModel.backup('image', 1);
                end
            end

            cropDim = str2num(BatchOptLoc.Time); %#ok<ST2NM>
            tMin = min(cropDim);
            tMax = max(cropDim);
            crop_factor = [crop_factor, tMin, tMax-tMin+1];

            % Note: enableSelection is intentionally NOT touched here.
            % Cropping is a geometric operation and must not change whether
            % models/selection are enabled in the destination buffer:
            %  - Standard source: the deep copy already carries the source value
            %  - Virtual/BigData source: cropDataset converts to Standard via
            %    switchDatasetMode(1, true), which enables selection itself

            % get Zarr pyramid level index if applicable
            if ~obj.batchProcessingSwitch && strcmp(obj.view.handles.ZarrPyramidLevel.Enable, 'on')
                items = obj.view.handles.ZarrPyramidLevel.Items;
                BatchOptLoc.pyramidLevel = find(strcmp(items, obj.view.handles.ZarrPyramidLevel.Value), 1);
                if isempty(BatchOptLoc.pyramidLevel); BatchOptLoc.pyramidLevel = 1; end
            end

            bigDataOutputDone = false;
            if bigDataOutput
                % --- BigData → BigData output path ---
                % Warn: a new Zarr3 pyramid will be written to disk. When the
                % destination buffer is the current one the dataset will be
                % replaced; the original file on disk is not deleted.
                warnSel = utils.dlgs.inputQuestDlg(progressParent, ...
                    sprintf(['The crop operation will write a new OME-Zarr v3 pyramid to disk.\n\n' ...
                    'The current dataset in the destination buffer will be replaced with the cropped BigData.\n' ...
                    'The source file on disk is not modified.']), ...
                    'Crop to BigData', 'Continue', 'Cancel', 'Continue', ...
                    struct('Icon', 'puffin_warning', 'mibPath', obj.mibModel.mibPath));
                if ~strcmp(warnSel, 'Continue'); return; end

                [srcDir, srcStem] = fileparts(obj.mibModel.I{id}.image.filename);
                [outputFilename, outputFolder] = uiputfile({'*.zarr3', 'OME-Zarr v3 (*.zarr3)'}, ...
                    'Save cropped BigData as...', ...
                    fullfile(srcDir, [srcStem '_crop.zarr3']));
                if isequal(outputFilename, 0); return; end
                outputPath = fullfile(outputFolder, outputFilename);

                cropOpts.showWaitbar = BatchOptLoc.showWaitbar;
                cropOpts.UIFigure    = progressParent;
                cropOpts.outputPath  = outputPath;

                result = obj.mibModel.I{id}.cropToBigData(crop_factor, cropOpts);
                if result == 0; notify(obj.mibModel, 'StopProtocol'); return; end

                % Capture model metadata from the source BEFORE initialize wipes I{bufferId}
                % (when bufferId == id, initialize replaces the source dataset in-place)
                srcHasModel       = isa(obj.mibModel.I{id}.labels, 'core.MibBigDataLabels') && obj.mibModel.I{id}.labels.exists;
                srcMaterialNames  = {};
                srcMaterialColors = [];
                srcMaterialsCount = 0;
                if srcHasModel
                    srcMaterialNames  = obj.mibModel.I{id}.labels.materialNames;
                    srcMaterialColors = obj.mibModel.I{id}.labels.materialColors;
                    srcMaterialsCount = obj.mibModel.I{id}.labels.materialsCount;
                end

                % Load new zarr into destination buffer
                lo = struct('datasetMode', 'BigData');
                zarr3Loader = io.loaders.Zarr3VirtualSetupLoader(lo);
                [imgInfo, files] = zarr3Loader.loadMetadata({outputPath}, lo);
                [img, imgInfo]   = zarr3Loader.loadImages(files, imgInfo, lo);
                % initialize() keeps BigData browse-only (enableSelection=false);
                % it is switched on below only when a model store is reattached
                obj.mibModel.I{bufferId}.initialize(img, imgInfo, 'BigData');

                % Reattach the model zarr if cropToBigData created one:
                % model is saved as Labels_<stem><ext> alongside the image zarr
                [bdParentDir, bdStem, bdExt] = fileparts(outputPath);
                modelStorePath = fullfile(bdParentDir, ['Labels_' bdStem bdExt]);
                if isfolder(modelStorePath)
                    newLabels = core.MibBigDataLabels([], core.MibImage.initializeImgInfo());
                    newLabels.openStore(modelStorePath);
                    newLabels.filename       = modelStorePath;
                    newLabels.materialNames  = srcMaterialNames;
                    newLabels.materialColors = srcMaterialColors;
                    newLabels.materialsCount = srcMaterialsCount;
                    obj.mibModel.I{bufferId}.labels     = newLabels;
                    obj.mibModel.I{bufferId}.modelExist = true;
                    obj.mibModel.I{bufferId}.enableSelection = true;
                end

                % Sync Sets.datasetTypes for the BigData output buffer
                targetSet     = floor((bufferId - 1) / obj.mibModel.Sets.datasetsInSet) + 1;
                targetLocalId = mod(bufferId - 1, obj.mibModel.Sets.datasetsInSet) + 1;
                obj.mibModel.Sets.datasetTypes{targetSet, targetLocalId} = obj.mibModel.I{bufferId}.datasetType;

                obj.listener{1}.Enabled = 0;
                if bufferId == id
                    notify(obj.mibModel, 'NewDataset');
                else
                    eventdata = core.ToggleEventData(struct('index', bufferId));
                    notify(obj.mibModel, 'NewDataset', eventdata);
                end
                obj.listener{1}.Enabled = 1;
                notify(obj.mibModel, 'UpdateFileList');  % highlight output zarr3 in Directory Contents
                bigDataOutputDone = true;
            else
                % --- Standard output path (existing) ---
                % Map ZarrPyramidLevel string ('s0','s1',...) to 1-indexed pyramidLevel
                zarrStr = BatchOptLoc.ZarrPyramidLevel{1};
                BatchOptLoc.pyramidLevel = str2double(zarrStr(2:end)) + 1;
                % cropDataset skips its progress dialog without a parent figure
                BatchOptLoc.UIFigure = progressParent;
                result = obj.mibModel.I{bufferId}.cropDataset(crop_factor, BatchOptLoc);
                if result == 0; notify(obj.mibModel, 'StopProtocol'); return; end
            end

            if ~bigDataOutputDone
                obj.mibModel.I{bufferId}.hROI.crop(crop_factor);
                obj.mibModel.I{bufferId}.annotations.crop(crop_factor);
                obj.mibModel.I{bufferId}.measure.crop(crop_factor);
                log_text = ['ImCrop: [x1 y1 dx dy z1 dz t1 dt]: [' num2str(crop_factor) ']'];
                obj.mibModel.I{bufferId}.image.updateActionLog(log_text);

                % Clamp stale slice positions that were deep-copied from the source buffer.
                % When crop reduces the Z-depth or T-frames, slices{} may exceed the new
                % dimensions, causing widget Value-out-of-range errors on first display.
                newDims = obj.mibModel.I{bufferId}.dim_yxzct;   % [height, width, depth, colors, time]
                maxZ = newDims(3);
                maxT = newDims(5);
                for dimIdx = 1:3   % all three Z-related orientations
                    obj.mibModel.I{bufferId}.slices{dimIdx} = min(obj.mibModel.I{bufferId}.slices{dimIdx}, [maxZ maxZ]);
                end
                obj.mibModel.I{bufferId}.slices{5} = min(obj.mibModel.I{bufferId}.slices{5}, [maxT maxT]);

                % Sync Sets.datasetTypes so the Datasets panel shows the correct type
                % (e.g. after BigData→Standard conversion via cropDataset)
                targetSet     = floor((bufferId - 1) / obj.mibModel.Sets.datasetsInSet) + 1;
                targetLocalId = mod(bufferId - 1, obj.mibModel.Sets.datasetsInSet) + 1;
                obj.mibModel.Sets.datasetTypes{targetSet, targetLocalId} = obj.mibModel.I{bufferId}.datasetType;

                % notify about the new dataset
                obj.listener{1}.Enabled = 0;    % suppress updateWidgets during event
                if bufferId == id
                    notify(obj.mibModel, 'NewDataset');
                else
                    eventdata = core.ToggleEventData(struct('index', bufferId));
                    notify(obj.mibModel, 'NewDataset', eventdata);
                end
                obj.listener{1}.Enabled = 1;
                notify(obj.mibModel, 'DatasetsPanelUpdate'); % sync datasetType widget in Datasets panel
                notify(obj.mibModel, 'UpdateGuiWidgets');   % refresh other panel widgets

                if strcmp(BatchOptLoc.Destination{1}, sprintf('Container %d', id)) || ...
                        strcmp(BatchOptLoc.Destination{1}, 'Current')
                    notify(obj.mibModel, 'ShowImage');
                end

                % refresh widgets (GUI mode only, current buffer only)
                if ~isempty(obj.view) && bufferId == id
                    obj.updateWidgets();
                end
            end

            % normalise BatchOptLoc for macro recording
            if strcmp(BatchOptLoc.cropMode{1}, 'Interactive')
                BatchOptLoc.cropMode{1} = 'Manual';
                BatchOptLoc.Width  = sprintf('%d:%d', crop_factor(1), crop_factor(1)+crop_factor(3)-1);
                BatchOptLoc.Height = sprintf('%d:%d', crop_factor(2), crop_factor(2)+crop_factor(4)-1);
                BatchOptLoc.Depth  = sprintf('%d:%d', crop_factor(5), crop_factor(5)+crop_factor(6)-1);
                BatchOptLoc.Time   = sprintf('%d:%d', crop_factor(7), crop_factor(7)+crop_factor(8)-1);
            end
            if strcmp(BatchOptLoc.cropMode{1}, 'ROI')
                BatchOptLoc.cropMode{1} = 'Manual';
            end
            obj.returnBatchOpt(BatchOptLoc);
        end

        function helpButton_Callback(obj)
            % HELPBUTTON_CALLBACK - open the help page for the Crop Dataset dialog.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.helpButton_Callback()
            %

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.CropDataset.helpButton_Callback: triggered\n');
            end
            helpFilPath = fullfile(fileparts(obj.mibModel.mibPath), 'docs', 'html', 'user-interface', 'ribbon', 'dataset', 'dataset-crop.html');
            utils.openHelpPage(helpFilPath, ...
                'http://mib.helsinki.fi/help/main3/user-interface/ribbon/dataset/dataset-crop.html');

        end

    end

    methods (Access = private)
        function position = drawCropArea(obj)
            % DRAWCROPAREA - draw a rectangle over the image and return its position in data pixels.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       position = obj.drawCropArea()
            %
            % Shared by the Interactive crop mode (cropBtn_Callback) and by the
            % select area button (selectAreaBtn_Callback). The crop window is
            % hidden while the rectangle is drawn and segmentation is disabled,
            % so that dragging over the image does not modify the layers.
            %
            % The axes, image document and ROI controller are resolved from
            % obj.mibController at call time, which keeps the tool split-panel
            % safe - the rectangle is always drawn on the currently active panel.
            % Zoom and pan stability during drawing comes from registering the
            % rectangle in cRoi.drawingROI: showImage calls
            % cRoi.repositionDrawingROI on every redraw, while the
            % MovingROI/ROIMoved listeners keep cRoi.drawingROI.dataPos in
            % data pixel coordinates.
            %
            % Return values:
            %   **position** - ``[x1, y1, x2, y2]`` of the drawn rectangle in data
            %   pixels of the currently shown orientation, clamped to the dataset
            %   dimensions. Empty when the user cancelled the drawing (Escape) or
            %   when the resulting area was too small
            %

            position = [];
            id = obj.mibModel.id;

            % Resolve axes, cImageDoc and cRoi from mibController (split-panel safe)
            if isempty(obj.mibController) || ~isvalid(obj.mibController)
                utils.dlgs.showErrorDialog(obj.view.gui, ...
                    sprintf('!!! Error !!!\n\nImage axes handle is not available.\nPlease use Manual or ROI mode instead.'), ...
                    'Interactive crop error');
                return;
            end

            selectedSet = obj.mibModel.Sets.selectedSet;
            cImageDoc = obj.mibController.cImageDoc{selectedSet};
            imViewAxes = cImageDoc.handles.imViewAxes;
            cRoi = obj.mibController.cRoi;

            if isempty(imViewAxes) || ~isgraphics(imViewAxes)
                utils.dlgs.showErrorDialog(obj.view.gui, ...
                    sprintf('!!! Error !!!\n\nImage axes handle is not available.\nPlease use Manual or ROI mode instead.'), ...
                    'Interactive crop error');
                return;
            end

            % Prepare drawing state
            obj.view.gui.Visible = 'off';
            obj.mibModel.disableSegmentation = true;

            if ~isempty(cImageDoc) && isvalid(cImageDoc)
                cImageDoc.UIFigure.Pointer = 'cross';
            end

            if ~isempty(cRoi)
                cRoi.drawingROI.type          = 'Rectangle';
                cRoi.drawingROI.dataPos       = [];
                cRoi.drawingROI.repositioning = false;
                cRoi.drawingROI.active        = false;
            end

            % Draw rectangle and wait for confirmation (single try-catch).
            % Zoom-stable repositioning via cRoi.drawingROI / repositionDrawingROI
            % is activated after drawrectangle creates the ROI object.
            roi = [];  movingLsn = [];  movedLsn = [];
            drawOk = false;
            try
                roi = drawrectangle(imViewAxes);
                if isvalid(roi)
                    captureF  = @() controllers.CropDataset.captureCropDataPos(roi, cRoi, obj.mibModel);
                    movingLsn = addlistener(roi, 'MovingROI', @(~,~) captureF());
                    movedLsn  = addlistener(roi, 'ROIMoved',  @(~,~) captureF());
                    captureF();
                    if ~isempty(cRoi)
                        cRoi.drawingROI.roi    = roi;
                        cRoi.drawingROI.active = true;
                    end
                    wait(roi);
                    % Escape clears roi.Position without deleting the object;
                    % deletion (e.g. clicking X) makes isvalid false - check both.
                    drawOk = isvalid(roi) && ~isempty(roi.Position);
                end
            catch
            end

            % Cleanup: listeners, drawing state, cursor, dialog visibility
            if ~isempty(movingLsn); delete(movingLsn); end
            if ~isempty(movedLsn);  delete(movedLsn);  end
            if ~isempty(cRoi); cRoi.drawingROI.active = false; end
            obj.mibModel.disableSegmentation = false;

            if ~isempty(cImageDoc) && isvalid(cImageDoc)
                cImageDoc.UIFigure.Pointer = 'cross';
            end
            % Restore the crop window and realize it before returning: the caller
            % parents its progress dialog to obj.view.gui, and a figure that has
            % only been switched back on is not yet rendered, so the dialog would
            % never appear (visible with slow sources such as remote Zarr)
            obj.view.gui.Visible = 'on';
            figure(obj.view.gui);   % bring the window in front of the image document
            drawnow;

            if ~drawOk
                if ~isempty(roi) && isvalid(roi); delete(roi); end
                return;
            end

            % Extract final position in data-pixel coordinates.
            % Prefer coords cached by captureF (already in data pixels, zoom-corrected).
            % Fall back to converting roi.Position when cRoi was unavailable.
            if ~isempty(cRoi) && ~isempty(cRoi.drawingROI.dataPos)
                dp = cRoi.drawingROI.dataPos;   % 2x2: [xmin ymin; xmax ymax]
                delete(roi);
                position = ceil([dp(1,1), dp(1,2), dp(2,1), dp(2,2)]);
            else
                new_position = roi.Position;   % [xmin ymin w h]
                delete(roi);
                if isempty(new_position) || any(~isfinite(new_position)); return; end
                new_position(3) = new_position(3) + new_position(1);
                new_position(4) = new_position(4) + new_position(2);
                new_position(1) = max(new_position(1), 0.5);
                new_position(2) = max(new_position(2), 0.5);
                [position(1), position(2)] = obj.mibModel.convertMouseToDataCoordinates(new_position(1), new_position(2), 'shown');
                [position(3), position(4)] = obj.mibModel.convertMouseToDataCoordinates(new_position(3), new_position(4), 'shown');
                position = ceil(position);
            end

            % Clamp to image bounds
            opts.blockModeSwitch = 0;
            [height, width] = obj.mibModel.I{id}.getDatasetDimensions('selection', [], opts);
            position(1) = max(position(1), 1);
            position(2) = max(position(2), 1);
            position(3) = min(position(3), width);
            position(4) = min(position(4), height);

            % Validate the selected area
            if position(3) <= position(1) || position(4) <= position(2)
                utils.dlgs.showErrorDialog(obj.view.gui, ...
                    sprintf('!!! Error !!!\n\nThe defined area is too small!\nTo select the area for crop press the left mouse button and drag the mouse while having the left mouse button pressed. To confirm selection, double click inside the selected area'), ...
                    'Crop error');
                position = [];
                return;
            end
        end
    end

    methods (Static, Access = private)
        function captureCropDataPos(roi, cRoi, mibModel)
            % CAPTURECROPDATAPOS - Store the current drawrectangle position in data-pixel coordinates.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       controllers.CropDataset.captureCropDataPos(roi, cRoi, mibModel)
            %
            % Called from MovingROI/ROIMoved listeners during interactive crop drawing.
            % Writes result into cRoi.drawingROI.dataPos (2×2: [xmin ymin; xmax ymax]).
            if isempty(roi) || ~isvalid(roi); return; end
            if ~isempty(cRoi) && cRoi.drawingROI.repositioning; return; end
            try
                p = roi.Position;   % [x y w h] in axes coords
                [X, Y] = mibModel.convertMouseToDataCoordinates( ...
                    [p(1); p(1)+p(3)], [p(2); p(2)+p(4)], 'shown');
                if ~isempty(cRoi)
                    cRoi.drawingROI.dataPos = [X(:), Y(:)];
                end
            catch
            end
        end
    end
end
