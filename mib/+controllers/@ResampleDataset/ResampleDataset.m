classdef ResampleDataset < handle
% RESAMPLEDATASET - @type ResampleDataset class is responsible for showing the dataset.
%
% resample window, available from MIB > Ribbon > Dataset > Resample

    % Updates
    %

    properties
        mibModel
        % handle to MibModel
        view
        % handle to the view (ResampleDatasetGUI)
        listener
        % cell array of listener handles
        height
        % current dataset height (pixels)
        width
        % current dataset width (pixels)
        color
        % number of colour channels
        depth
        % current dataset depth (slices)
        BatchOpt
        % structure compatible with batch processing
    end

    events
        CloseEvent
        % fired when window is closed
    end

    methods (Static)
        function ViewListner_Callback2(obj, ~, evnt)
            % VIEWLISTNER_CALLBACK2 - static listener guard.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.ViewListner_Callback2(~, evnt)
            %
            % Input Arguments:
            %   - **obj** — handle to ResampleDataset
            %   - **evnt** — event data
            %
            if ~isvalid(obj) || isempty(obj.view) || ~isvalid(obj.view.gui)
                for i = 1:numel(obj.listener); delete(obj.listener{i}); end
                return;
            end
            switch evnt.EventName
                case {'UpdateGuiWidgets', 'NewDataset'}
                    obj.updateWidgets();
            end
        end
    end

    methods

        % ---------------------------------------------------------------
        function obj = ResampleDataset(mibModel, varargin)
            % RESAMPLEDATASET - constructor.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj = ResampleDataset(mibModel)
            %       obj = ResampleDataset(mibModel, BatchOpt)
            %
            % Input Arguments:
            %   - **mibModel** — handle to MibModel
            %   - **varargin{1}** — *(optional)* BatchOpt struct or NaN (batch mode)
            %
            % Usage:
            %   Example 1::
            %
            %     obj.mibController.startController('controllers.ResampleDataset');
            %

            obj.mibModel = mibModel;
            id = obj.mibModel.getActiveId();

            getDataOpt.blockModeSwitch = 0;
            [obj.height, obj.width, obj.depth, colors] = obj.mibModel.I{id}.getDatasetDimensions('image', 3, getDataOpt);
            obj.color = numel(colors);

            pixSize = obj.mibModel.I{id}.image.pixSize;

            % ---- BatchOpt defaults
            obj.BatchOpt.ResamplingMode    = {'Dimensions'};
            obj.BatchOpt.ResamplingMode{2} = {'Dimensions', 'Voxels', 'PercentageXYZ', 'PercentageXY'};
            obj.BatchOpt.ResamplingFunction    = {'imresize'};
            obj.BatchOpt.ResamplingFunction{2} = {'interpn', 'imresize', 'tformarray'};
            obj.BatchOpt.ResamplingMethod    = {'cubic'};
            obj.BatchOpt.ResamplingMethod{2} = {'nearest','linear','spline','cubic','box','triangle','lanczos2','lanczos3','osc'};
            obj.BatchOpt.LabelsresampleDropDown    = {'nearest'};
            obj.BatchOpt.LabelsresampleDropDown{2} = {'nearest','linear','spline','cubic'};
            obj.BatchOpt.DimensionX   = num2str(obj.width);
            obj.BatchOpt.DimensionY   = num2str(obj.height);
            obj.BatchOpt.DimensionZ   = num2str(obj.depth);
            obj.BatchOpt.Percentage   = '100';
            obj.BatchOpt.VoxelX       = num2str(pixSize.x);
            obj.BatchOpt.VoxelY       = num2str(pixSize.y);
            obj.BatchOpt.VoxelZ       = num2str(pixSize.z);
            obj.BatchOpt.FixAspectRatio = true;
            obj.BatchOpt.showWaitbar    = true;
            obj.BatchOpt.mibBatchSectionName = 'Ribbon -> Dataset';
            obj.BatchOpt.mibBatchActionName  = 'Resample...';
            obj.BatchOpt.mibBatchTooltip.ResamplingMode         = 'Resampling basis: pixel dimensions, voxel sizes, or percentage';
            obj.BatchOpt.mibBatchTooltip.ResamplingFunction     = 'Resampling function (interpn / imresize / tformarray)';
            obj.BatchOpt.mibBatchTooltip.ResamplingMethod       = 'Interpolation method for images; cubic recommended for downsampling';
            obj.BatchOpt.mibBatchTooltip.LabelsresampleDropDown = 'Interpolation method for labels/model; nearest recommended';
            obj.BatchOpt.mibBatchTooltip.DimensionX   = '[Dimensions] New width in pixels';
            obj.BatchOpt.mibBatchTooltip.DimensionY   = '[Dimensions] New height in pixels';
            obj.BatchOpt.mibBatchTooltip.DimensionZ   = '[Dimensions] New depth in slices';
            obj.BatchOpt.mibBatchTooltip.Percentage   = '[Percentage] Scaling factor in %';
            obj.BatchOpt.mibBatchTooltip.VoxelX       = '[Voxels] New voxel size in X';
            obj.BatchOpt.mibBatchTooltip.VoxelY       = '[Voxels] New voxel size in Y';
            obj.BatchOpt.mibBatchTooltip.VoxelZ       = '[Voxels] New voxel size in Z';
            obj.BatchOpt.mibBatchTooltip.FixAspectRatio = 'Lock XY aspect ratio when one dimension is changed';
            obj.BatchOpt.mibBatchTooltip.showWaitbar    = 'Show progress bar during execution';

            % ---- Guard: not available in Virtual or BigData mode
            if any(obj.mibModel.I{id}.datasetType(1) == ['V' 'B'])
                if nargin ~= 3
                    warnOpt.MsgBoxOnly = true;
                    warnOpt.Icon       = 'puffin_warning';
                    warnOpt.WindowHeight = 160;
                    utils.dlgs.inputUniversalDlg(obj.mibModel.mibGUI, [], {}, ...
                        {sprintf('Resample is not available in virtual or BigData mode.\nPlease switch to the memory-resident mode and try again.')}, ...
                        'Not implemented', warnOpt);
                end
                notify(obj.mibModel, 'StopProtocol');
                return;
            end

            % ---- Batch-mode path
            if nargin == 3
                BatchOptInput = varargin{2};
                if isstruct(BatchOptInput)
                    obj.BatchOpt = utils.updateBatchOptCombineFields_Shared(obj.BatchOpt, BatchOptInput);
                    obj.resampleBtn_Callback(true);
                    notify(obj, 'CloseEvent');
                elseif isnan(BatchOptInput)
                    obj.returnBatchOpt();
                else
                    utils.dlgs.showErrorDialog([], ...
                        'A BatchOpt struct is required as the 3rd parameter.', ...
                        'ResampleDataset: init error');
                    notify(obj.mibModel, 'StopProtocol');
                end
                return;
            end

            % ---- GUI path
            guiName = 'views.ResampleDatasetGUI';
            obj.view = core.ChildView(obj, guiName);
            obj.addCallbacks();

            Font = obj.mibModel.preferences.System.Font;
            if obj.view.handles.PixelsizeXLabel.FontSize ~= Font.FontSize ...
                    || ~strcmp(obj.view.handles.PixelsizeXLabel.FontName, Font.FontName)
                utils.fontSizeUpdate(obj.view.gui, Font);
            end
            obj.view.gui = utils.moveWindowOutside(obj.view.gui, obj.mibModel.mibGUI, 'left');
            obj.updateWidgets();

            obj.view.gui.Visible = 'on';

            obj.listener{1} = addlistener(obj.mibModel, 'UpdateGuiWidgets', ...
                @(src,evnt) obj.ViewListner_Callback2(obj, src, evnt));
            obj.listener{2} = addlistener(obj.mibModel, 'NewDataset', ...
                @(src,evnt) obj.ViewListner_Callback2(obj, src, evnt));
        end

        % ---------------------------------------------------------------
        function closeWindow(obj)
            % CLOSEWINDOW - close the ResampleDataset GUI.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.closeWindow()
            %
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.ResampleDataset.closeWindow: triggered\n');
            end
            if ~isempty(obj.view) && isvalid(obj.view.gui)
                delete(obj.view.gui);
            end
            for i = 1:numel(obj.listener); delete(obj.listener{i}); end
            notify(obj, 'CloseEvent');
        end

        % ---------------------------------------------------------------
        function returnBatchOpt(obj, BatchOptOut)
            % RETURNBATCHOPT - send BatchOpt to mibBatchController.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.returnBatchOpt()
            %       obj.returnBatchOpt(BatchOptOut)
            %
            if nargin < 2; BatchOptOut = obj.BatchOpt; end
            eventdata = core.ToggleEventData(BatchOptOut);
            notify(obj.mibModel, 'SyncBatch', eventdata);
        end

        % ---------------------------------------------------------------
        function updateBatchOptFromGUI(obj, hObject)
            % UPDATEBATCHOPTFROMGUI - sync obj.BatchOpt from a widget.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.updateBatchOptFromGUI(hObject)
            %
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.ResampleDataset.updateBatchOptFromGUI: triggered\n');
            end
            obj.BatchOpt = utils.updateBatchOptFromGUI_Shared(obj.BatchOpt, hObject);
        end

        % ---------------------------------------------------------------
        function addCallbacks(obj)
            % ADDCALLBACKS - wire all GUI widget callbacks.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.addCallbacks()
            %
            h = obj.view.handles;
            obj.view.gui.CloseRequestFcn = @(~,~) obj.closeWindow();
            % radio button group
            h.ResamplingMode.SelectionChangedFcn = @(~, event) obj.radio_Callback(event.NewValue);
            % numeric edit fields
            h.DimensionX.ValueChangedFcn  = @(src,~) obj.editbox_Callback(src);
            h.DimensionY.ValueChangedFcn  = @(src,~) obj.editbox_Callback(src);
            h.DimensionZ.ValueChangedFcn  = @(src,~) obj.editbox_Callback(src);
            h.VoxelX.ValueChangedFcn      = @(src,~) obj.editbox_Callback(src);
            h.VoxelY.ValueChangedFcn      = @(src,~) obj.editbox_Callback(src);
            h.VoxelZ.ValueChangedFcn      = @(src,~) obj.editbox_Callback(src);
            h.Percentage.ValueChangedFcn  = @(src,~) obj.editbox_Callback(src);
            % checkbox
            h.FixAspectRatio.ValueChangedFcn = @(src,~) obj.updateBatchOptFromGUI(src);
            % dropdowns
            h.ResamplingFunction.ValueChangedFcn     = @(src,~) obj.updateBatchOptFromGUI(src);
            h.ResamplingMethod.ValueChangedFcn       = @(src,~) obj.updateBatchOptFromGUI(src);
            h.LabelsresampleDropDown.ValueChangedFcn = @(src,~) obj.updateBatchOptFromGUI(src);
            % buttons
            h.resampleBtn.ButtonPushedFcn = @(~,~) obj.resampleBtn_Callback(false);
            h.resetBtn.ButtonPushedFcn    = @(~,~) obj.updateWidgets();
            h.cancelBtn.ButtonPushedFcn   = @(~,~) obj.closeWindow();
            h.helpButton.ButtonPushedFcn  = @(~,~) obj.helpBtn_Callback();
        end

        % ---------------------------------------------------------------
        function updateWidgets(obj)
            % UPDATEWIDGETS - refresh all GUI widgets from current dataset state.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.updateWidgets()
            %
            id = obj.mibModel.getActiveId();
            opts.blockModeSwitch = 0;
            [obj.height, obj.width, obj.depth, colors] = ...
                obj.mibModel.I{id}.getDatasetDimensions('image', 3, opts);
            obj.color = numel(colors);

            h = obj.view.handles;
            pixSize = obj.mibModel.I{id}.image.pixSize;

            % current size labels
            h.widthTxt.Text   = num2str(obj.width);
            h.heightTxt.Text  = num2str(obj.height);
            h.depthTxt.Text   = num2str(obj.depth);
            h.colorsTxt.Text  = num2str(obj.color);
            h.pixsizeX.Text   = sprintf('%f %s', pixSize.x, pixSize.units);
            h.pixsizeY.Text   = sprintf('%f %s', pixSize.y, pixSize.units);
            h.pixsizeZ.Text   = sprintf('%f %s', pixSize.z, pixSize.units);

            % reset resample-target fields to current values
            h.DimensionX.Value = obj.width;
            h.DimensionY.Value = obj.height;
            h.DimensionZ.Value = obj.depth;
            h.VoxelX.Value     = pixSize.x;
            h.VoxelY.Value     = pixSize.y;
            h.VoxelZ.Value     = pixSize.z;
            h.Percentage.Value = 100;

            % populate dropdown Items before setting Value (AppDesigner requires Items first)
            h.ResamplingFunction.Items     = obj.BatchOpt.ResamplingFunction{2};
            h.ResamplingFunction.Value     = obj.BatchOpt.ResamplingFunction{1};
            h.ResamplingMethod.Items       = obj.BatchOpt.ResamplingMethod{2};
            h.ResamplingMethod.Value       = obj.BatchOpt.ResamplingMethod{1};
            h.LabelsresampleDropDown.Items = obj.BatchOpt.LabelsresampleDropDown{2};
            h.LabelsresampleDropDown.Value = 'nearest';

            % sync BatchOpt from current values
            obj.BatchOpt.DimensionX = num2str(obj.width);
            obj.BatchOpt.DimensionY = num2str(obj.height);
            obj.BatchOpt.DimensionZ = num2str(obj.depth);
            obj.BatchOpt.Percentage = '100';
            obj.BatchOpt.VoxelX     = num2str(pixSize.x);
            obj.BatchOpt.VoxelY     = num2str(pixSize.y);
            obj.BatchOpt.VoxelZ     = num2str(pixSize.z);
            obj.BatchOpt.LabelsresampleDropDown{1} = 'nearest';

            % apply enable/disable state for the current mode
            obj.updateEditboxStates(obj.BatchOpt.ResamplingMode{1});
        end

        % ---------------------------------------------------------------
        function updateEditboxStates(obj, mode)
            % UPDATEEDITBOXSTATES - enable the primary input group for the selected mode.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.updateEditboxStates(mode)
            %
            % Input Arguments:
            %   - **mode** — string — 'Dimensions' | 'Voxels' | 'PercentageXYZ' | 'PercentageXY'
            %
            h = obj.view.handles;
            isDim  = strcmp(mode, 'Dimensions');
            isVox  = strcmp(mode, 'Voxels');
            isPct  = strcmp(mode, 'PercentageXYZ') || strcmp(mode, 'PercentageXY');
            h.DimensionX.Enable = isDim;
            h.DimensionY.Enable = isDim;
            h.DimensionZ.Enable = isDim;
            h.VoxelX.Enable     = isVox;
            h.VoxelY.Enable     = isVox;
            h.VoxelZ.Enable     = isVox;
            h.Percentage.Enable = isPct;
        end

        % ---------------------------------------------------------------
        function radio_Callback(obj, hObject)
            % RADIO_CALLBACK - handle ResamplingMode button group change.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.radio_Callback(hObject)
            %
            % Input Arguments:
            %   - **hObject** — event.NewValue — the newly selected radio button
            %
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.ResampleDataset.radio_Callback: triggered\n');
            end
            obj.BatchOpt.ResamplingMode{1} = hObject.Tag;
            obj.updateEditboxStates(hObject.Tag);
            switch hObject.Tag
                case {'PercentageXYZ', 'PercentageXY'}
                    obj.editbox_Callback(obj.view.handles.Percentage);
                    focus(obj.view.handles.Percentage);
                case 'Voxels'
                    focus(obj.view.handles.VoxelX);
                case 'Dimensions'
                    focus(obj.view.handles.DimensionX);

            end
            obj.updateBatchOptFromGUI(obj.view.handles.ResamplingMode);
        end

        % ---------------------------------------------------------------
        function helpBtn_Callback(obj)
            % HELPBTN_CALLBACK - open online help.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.helpBtn_Callback()
            %
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.ResampleDataset.helpBtn_Callback: triggered\n');
            end
            helpFilPath = fullfile(fileparts(obj.mibModel.mibPath), 'docs', 'site', 'user-interface', 'ribbon', 'dataset', 'dataset-resample.html');
            if isfile(helpFilPath)
                web(helpFilPath, '-browser');
            else
                web('http://mib.helsinki.fi/help/main3/user-interface/ribbon/dataset/dataset-resample.html', '-browser');
            end

        end

        % ---------------------------------------------------------------
        function editbox_Callback(obj, hObject)
            % EDITBOX_CALLBACK - respond to dimension / voxel / percentage edits.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.editbox_Callback(hObject)
            %
            % Input Arguments:
            %   - **hObject** — the NumericEditField that changed
            %
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.ResampleDataset.editbox_Callback: triggered\n');
            end
            id = obj.mibModel.getActiveId();
            pixSize = obj.mibModel.I{id}.image.pixSize;
            h = obj.view.handles;

            switch obj.BatchOpt.ResamplingMode{1}
                case 'Dimensions'
                    switch hObject.Tag
                        case 'DimensionX'
                            val   = hObject.Value;
                            ratio = obj.width / val;
                            h.VoxelX.Value = pixSize.x * ratio;
                            if h.FixAspectRatio.Value
                                h.DimensionY.Value = floor(obj.height / ratio);
                                h.VoxelY.Value = pixSize.y * ratio;
                            end
                        case 'DimensionY'
                            val   = hObject.Value;
                            ratio = obj.height / val;
                            h.VoxelY.Value = pixSize.y * ratio;
                            if h.FixAspectRatio.Value
                                h.DimensionX.Value = floor(obj.width / ratio);
                                h.VoxelX.Value = pixSize.x * ratio;
                            end
                        case 'DimensionZ'
                            val   = hObject.Value;
                            ratio = obj.depth / val;
                            h.VoxelZ.Value = pixSize.z * ratio;
                    end
                case 'Voxels'
                    switch hObject.Tag
                        case 'VoxelX'
                            val   = hObject.Value;
                            ratio = val / pixSize.x;
                            h.DimensionX.Value = floor(obj.width / ratio);
                            if h.FixAspectRatio.Value
                                h.DimensionY.Value = floor(obj.height / ratio);
                                h.VoxelY.Value = pixSize.y * ratio;
                            end
                        case 'VoxelY'
                            val   = hObject.Value;
                            ratio = val / pixSize.y;
                            h.DimensionY.Value = floor(obj.height / ratio);
                            if h.FixAspectRatio.Value
                                h.DimensionX.Value = floor(obj.width / ratio);
                                h.VoxelX.Value = pixSize.x * ratio;
                            end
                        case 'VoxelZ'
                            val   = hObject.Value;
                            ratio = val / pixSize.z;
                            h.DimensionZ.Value = floor(obj.depth / ratio);
                    end
                case 'PercentageXYZ'
                    val = h.Percentage.Value;
                    h.DimensionX.Value = floor(obj.width  / 100 * val);
                    h.DimensionY.Value = floor(obj.height / 100 * val);
                    h.DimensionZ.Value = round(obj.depth  / 100 * val);
                    if h.DimensionX.Value > 0
                        h.VoxelX.Value = pixSize.x * obj.width  / h.DimensionX.Value;
                    end
                    if h.DimensionY.Value > 0
                        h.VoxelY.Value = pixSize.y * obj.height / h.DimensionY.Value;
                    end
                    if h.DimensionZ.Value > 0
                        h.VoxelZ.Value = pixSize.z * obj.depth  / h.DimensionZ.Value;
                    end
                case 'PercentageXY'
                    val = h.Percentage.Value;
                    h.DimensionX.Value = floor(obj.width  / 100 * val);
                    h.DimensionY.Value = floor(obj.height / 100 * val);
                    if h.DimensionX.Value > 0
                        h.VoxelX.Value = pixSize.x * obj.width  / h.DimensionX.Value;
                    end
                    if h.DimensionY.Value > 0
                        h.VoxelY.Value = pixSize.y * obj.height / h.DimensionY.Value;
                    end
            end

            % sync BatchOpt string fields from current widget values
            obj.BatchOpt.DimensionX = num2str(h.DimensionX.Value);
            obj.BatchOpt.DimensionY = num2str(h.DimensionY.Value);
            obj.BatchOpt.DimensionZ = num2str(h.DimensionZ.Value);
            obj.BatchOpt.Percentage = num2str(h.Percentage.Value);
            obj.BatchOpt.VoxelX     = num2str(h.VoxelX.Value);
            obj.BatchOpt.VoxelY     = num2str(h.VoxelY.Value);
            obj.BatchOpt.VoxelZ     = num2str(h.VoxelZ.Value);
        end

        % ---------------------------------------------------------------
        function resampleBtn_Callback(obj, batchModeSwitch)
            % RESAMPLEBTN_CALLBACK - resample the current dataset.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.resampleBtn_Callback()
            %       obj.resampleBtn_Callback(batchModeSwitch)
            %
            % Input Arguments:
            %   - **batchModeSwitch** — *(optional)* logical; true when called headlessly
            %

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.ResampleDataset.resampleBtn_Callback: triggered\n');
            end
            if nargin < 2; batchModeSwitch = false; end
            id = obj.mibModel.getActiveId();
            
            BatchOptLoc = obj.BatchOpt;
            
            pixSize = obj.mibModel.I{id}.image.pixSize;
            
            tic;
            wb = [];
            if BatchOptLoc.showWaitbar && ~batchModeSwitch
                wb = uiprogressdlg(obj.view.gui, ...
                    'Value', 0, ...
                    'Message', sprintf('Resampling image...\ndoing backup...'), ...
                    'Title', 'Resampling...', 'Cancelable', 'off');
            end
            
            % backup before destructive operation (GUI path only)
            if ~batchModeSwitch
                obj.mibModel.backup('image', 1);
            end

            % resolve target pixel dimensions from the selected mode
            switch BatchOptLoc.ResamplingMode{1}
                case 'Voxels'
                    voxX  = str2double(BatchOptLoc.VoxelX);
                    ratio = voxX / pixSize.x;
                    BatchOptLoc.DimensionX = num2str(floor(obj.width / ratio));
                    if BatchOptLoc.FixAspectRatio
                        BatchOptLoc.DimensionY = num2str(floor(obj.height / ratio));
                    else
                        voxY  = str2double(BatchOptLoc.VoxelY);
                        ratio = voxY / pixSize.y;
                        BatchOptLoc.DimensionY = num2str(floor(obj.height / ratio));
                    end
                    voxZ  = str2double(BatchOptLoc.VoxelZ);
                    ratio = voxZ / pixSize.z;
                    BatchOptLoc.DimensionZ = num2str(round(obj.depth / ratio));
                case 'PercentageXYZ'
                    val = str2double(BatchOptLoc.Percentage);
                    BatchOptLoc.DimensionX = num2str(floor(obj.width  / 100 * val));
                    BatchOptLoc.DimensionY = num2str(floor(obj.height / 100 * val));
                    BatchOptLoc.DimensionZ = num2str(round(obj.depth  / 100 * val));
                case 'PercentageXY'
                    val = str2double(BatchOptLoc.Percentage);
                    BatchOptLoc.DimensionX = num2str(floor(obj.width  / 100 * val));
                    BatchOptLoc.DimensionY = num2str(floor(obj.height / 100 * val));
                    BatchOptLoc.DimensionZ = num2str(obj.depth);
            end

            newW = str2double(BatchOptLoc.DimensionX);
            newH = str2double(BatchOptLoc.DimensionY);
            newZ = str2double(BatchOptLoc.DimensionZ);
            maxT = obj.mibModel.I{id}.image.time;

            if newW == obj.width && newH == obj.height && newZ == obj.depth
                if ~batchModeSwitch
                    dlgOpt.MsgBoxOnly  = true;
                    dlgOpt.Icon        = 'puffin_warning';
                    dlgOpt.HeaderLines = 1;
                    dlgOpt.mibPath     = obj.mibModel.mibPath;
                    utils.dlgs.inputUniversalDlg(obj.view.gui, 'The dimensions were not changed!', {''}, ...
                        {''}, 'Resample: no change', dlgOpt);
                end
                if ~isempty(wb); delete(wb); end
                notify(obj.mibModel, 'StopProtocol');
                return;
            end

            resampledRatio = [newW/obj.width, newH/obj.height, newZ/obj.depth];
            resamplingFn   = BatchOptLoc.ResamplingFunction{1};
            methodImage    = BatchOptLoc.ResamplingMethod{1};
            methodLabels   = BatchOptLoc.LabelsresampleDropDown{1};
            imgClass       = obj.mibModel.I{id}.image.dataClass;

            % wb = [];
            % if BatchOptLoc.showWaitbar && ~batchModeSwitch
            %     wb = uiprogressdlg(obj.view.gui, ...
            %         'Value', 0, ...
            %         'Message', sprintf('Resampling image...\n[%d %d %d %d] -> [%d %d %d %d]', ...
            %             obj.height, obj.width, obj.color, obj.depth, ...
            %             newH, newW, obj.color, newZ), ...
            %         'Title', 'Resampling...', 'Cancelable', 'off');
            % end
            
            if ~isempty(wb); wb.Message = sprintf('Resampling image...\n[%d %d %d %d] -> [%d %d %d %d]', ...
                    obj.height, obj.width, obj.color, obj.depth, ...
                    newH, newW, obj.color, newZ); 
            end
            
            opts.blockModeSwitch = 0;
            % allocate output in MIB3 layout [h, w, d, c, t].
            % getData3D(..., NaN, ...) below returns ALL color channels of the
            % dataset, so size the buffer by the total channel count — not
            % obj.color, which counts only the currently selected/shown channels
            % (obj.slices{4}) and would be too small for multi-channel data.
            totalColors = obj.mibModel.I{id}.image.colors;
            imgOut = zeros([newH, newW, newZ, totalColors, maxT], imgClass);
            opts.height  = newH;
            opts.width   = newW;
            opts.depth   = newZ;
            opts.method  = methodImage;
            opts.imgType = '4D';

            for t = 1:maxT
                % getData3D returns [h,w,d,c] in MIB3; resizeImage3d accepts [h,w,d,c] natively
                img = cell2mat(obj.mibModel.getData3D('image', t, 3, NaN, opts));
                if ~isempty(wb); wb.Value = 0.05; end
                resizeOpts              = opts;
                resizeOpts.showWaitbar = ~isempty(wb);
                resizeOpts.algorithm   = resamplingFn;
                resizeOpts.wb          = wb;  % updated in-place; not deleted by resizeImage3d
                imgOut(:,:,:,:,t) = utils.resizeImage3d(img, [], resizeOpts);
            end
            clear img;
            if ~isempty(wb); wb.Value = 0.5; end

            % write image back — replace the data container directly (setData4D
            % writes into the existing fixed-size array and would error on a size change)
            img5D = obj.mibModel.I{id}.image;
            oldBB = img5D.boundingBox;          % save physical extent before any changes
            img5D.data   = imgOut;
            img5D.height    = newH;
            img5D.width     = newW;
            img5D.depth     = newZ;
            img5D.dim_yxzct = [newH, newW, newZ, img5D.colors, img5D.time];
            if ~isempty(wb); wb.Value = 0.55; end

            % update bounding box (preserve physical extent, recompute voxel sizes from new dims)
            % updateBoundingBox reads height/width/depth from img5D (already updated) and
            % propagates the new pixSize to all layers via setPixSize
            obj.mibModel.I{id}.updateBoundingBox(oldBB);

            % sync MibDataset-level dim/slices (same pattern as cropDataset.m)
            ds = obj.mibModel.I{id};
            ds.dim_yxzct = img5D.dim_yxzct;
            if img5D.height < ds.current_yxz(1); ds.current_yxz(1) = img5D.height; end
            if img5D.width  < ds.current_yxz(2); ds.current_yxz(2) = img5D.width;  end
            if img5D.depth  < ds.current_yxz(3); ds.current_yxz(3) = img5D.depth;  end
            current_layer = ds.slices{ds.orientation}(1);
            ds.slices{1}  = [1, newH];
            ds.slices{2}  = [1, newW];
            ds.slices{3}  = [1, newZ];
            ds.slices{ds.orientation} = repmat(min(ds.dim_yxzct(ds.orientation), current_layer), 1, 2);

            % ----- resample labels + mask -----
            labelsOpts         = opts;
            labelsOpts.method  = methodLabels;
            labelsOpts.imgType = '3D';
            isLabels63 = isa(obj.mibModel.I{id}.labels, 'core.MibLabels63');

            % Only resample the model when a real model exists. modelExist is the
            % authoritative flag (false by default, set true by createModel/loadModel/
            % setData*/moveLayers). Using labels.exists here would be wrong for the
            % 63-material packed container: it always "exists" (it also holds the
            % selection layer), so an EMPTY model would be needlessly resampled —
            % which is what made MIB3 slower than MIB2 (MIB2 gates on modelExist and
            % skips an absent model). An empty model falls through to the cheap
            % zeros-reallocation branch below instead.
            labelsExist = obj.mibModel.I{id}.modelExist;

            modelDataType = 'labels';
            if labelsExist || (isLabels63 && obj.mibModel.I{id}.maskExist)
                if ~isempty(wb)
                    wb.Message = sprintf('Resampling labels...\n[%d %d %d] -> [%d %d %d]', ...
                        obj.height, obj.width, obj.depth, newH, newW, newZ);
                    wb.Value = 0.75;
                end

                if isLabels63 && strcmp(methodLabels, 'nearest')
                    modelDataType = 'everything';
                end

                % getData4D returns [h,w,d,t] for labels (no colour dim)
                model4D = cell2mat(obj.mibModel.getData4D(modelDataType, 3, NaN, labelsOpts));
                materialsNumber = numel(obj.mibModel.I{id}.labels.materialNames);

                imgOutModel = zeros([newH, newW, newZ, maxT], class(model4D));
                for t = 1:maxT
                    if t==maxT 
                        modelSlice = model4D; % faster this way
                    else
                        modelSlice = model4D(:,:,:,t);  % [h,w,d]
                    end
                    resizeLabOpts              = labelsOpts;
                    resizeLabOpts.showWaitbar  = 0;
                    resizeLabOpts.algorithm    = resamplingFn;
                    if strcmp(resamplingFn, 'interpn') && ~strcmp(methodLabels, 'nearest')
                        % per-material interpolation for non-nearest methods
                        modelTemp = zeros([newH, newW, newZ], 'uint8');
                        for matId = 1:materialsNumber
                            matMask    = uint8(modelSlice == matId);
                            matResized = utils.resizeImage3d(matMask, [], resizeLabOpts);
                            modelTemp(matResized > 0.33) = matId;
                        end
                        imgOutModel(:,:,:,t) = modelTemp;
                    else
                        imgOutModel(:,:,:,t) = utils.resizeImage3d(modelSlice, [], resizeLabOpts);
                    end
                end
                if ~isempty(wb); wb.Value = 0.95; end

                % MibLabels63 stores everything in a fixed-size data{1}; pre-allocate
                % the container at the new dimensions before setData63 fills it.
                % Regular MibLabels is handled generically by MibImage.setData
                % which auto-resizes data{1} on full-container replacement.
                if isLabels63
                    obj.mibModel.I{id}.labels.data    = zeros([newH, newW, newZ, maxT], 'uint8');
                    obj.mibModel.I{id}.labels.height      = newH;
                    obj.mibModel.I{id}.labels.width       = newW;
                    obj.mibModel.I{id}.labels.depth       = newZ;
                    obj.mibModel.I{id}.labels.dim_yxzct   = [newH, newW, newZ, 1, maxT];
                end
                obj.mibModel.setData4D(imgOutModel, modelDataType, 3, NaN, labelsOpts);

            elseif isLabels63
                % no model data — reset packed container to new size
                newDims = [newH, newW, newZ, maxT];
                obj.mibModel.I{id}.labels.data = zeros(newDims, 'uint8');
                obj.mibModel.I{id}.labels.height   = newH;
                obj.mibModel.I{id}.labels.width    = newW;
                obj.mibModel.I{id}.labels.depth    = newZ;
                obj.mibModel.I{id}.labels.time     = maxT;
                obj.mibModel.I{id}.labels.dim_yxzct = [newH, newW, newZ, 1, maxT];
            end

            % ----- shift annotations -----
            labelsNumber = obj.mibModel.I{id}.annotations.getLabelsNumber();
            if labelsNumber > 0
                [labelsList, labelValues, labelPositions] = ...
                    obj.mibModel.I{id}.annotations.getLabels();
                if numel(labelsList) == 0
                    if ~isempty(wb); delete(wb); end
                    notify(obj.mibModel, 'StopProtocol');
                    return;
                end
                labelPositions(:,1) = labelPositions(:,1) * newZ  / obj.depth;   % Z
                labelPositions(:,2) = labelPositions(:,2) * newW  / obj.width;   % X
                labelPositions(:,3) = labelPositions(:,3) * newH  / obj.height;  % Y
                obj.mibModel.I{id}.annotations.replaceLabels(labelsList, labelPositions, labelValues);
            end

            % ----- resample ROIs -----
            obj.mibModel.I{id}.hROI.resample(resampledRatio);

            % ----- resample measurements -----
            obj.mibModel.I{id}.measure.resample(resampledRatio);

            % ----- action log -----
            log_text = sprintf('Resample [%d %d %d %d %d]->[%d %d %d %d %d], method: %s', ...
                obj.height, obj.width, obj.color, obj.depth, maxT, ...
                newH, newW, obj.color, newZ, maxT, methodImage);
            obj.mibModel.I{id}.image.updateActionLog(log_text);

            % remove SliceName filenames if Z changed (they are now mismatched)
            if ~isempty(obj.mibModel.I{id}.image.sliceName) && newZ ~= obj.depth
                obj.mibModel.I{id}.image.sliceName = {};
            end

            % remove SliceSize if Z or spatial dimensions changed
            if ~isempty(obj.mibModel.I{id}.image.sliceSize) && ...
                    (newZ ~= obj.depth || newH ~= obj.height || newW ~= obj.width)
                obj.mibModel.I{id}.image.sliceSize = [];
                obj.mibModel.I{id}.labels.sliceSize = [];
            end

            % clear selection and mask unless 'everything' was resampled together
            if ~strcmp(modelDataType, 'everything')
                obj.mibModel.I{id}.clearLayer('selection');
                obj.mibModel.I{id}.clearLayer('mask');
            end

            if ~isempty(wb)
                wb.Value = 1;
                delete(wb);
            end
            toc;

            obj.returnBatchOpt(obj.BatchOpt);

            notify(obj.mibModel, 'NewDataset');
            notify(obj.mibModel, 'ShowImage');
        end

    end % methods
end % classdef
