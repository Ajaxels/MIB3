classdef CropDataset < handle
    % @type CropDataset class is responsible for showing the dataset
    % crop window, available from MIB -> Ribbon -> Dataset -> Crop
    %
    % @code
    % obj.startController('controllers.CropDataset'); // as GUI tool
    % @endcode

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
        % handle to controllers.MibController — used to resolve the active
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
            % Guard: if the view window was closed, clean up listeners and return.
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
            % obj = CropDataset(mibModel, varargin)
            % Constructor of the CropDataset controller
            %
            % Parameters:
            % mibModel: handle to MibModel
            % varargin{1}: [@em optional] handle to controllers.MibController
            %   (canonical, split-panel safe) OR an axes handle (legacy)
            %   OR a BatchOpt struct / NaN (batch mode with no controller)
            % varargin{2}: [@em optional] BatchOpt struct / NaN when varargin{1}
            %   is a controller or axes handle
            %
            % @b Examples:
            % @code obj.startController('controllers.CropDataset'); @endcode
            % @code obj.startController('controllers.CropDataset', obj); @endcode
            % @code obj.startController('controllers.CropDataset', obj, BatchOpt); @endcode

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
            obj.BatchOpt.cropMode    = {'Manual'};
            obj.BatchOpt.cropMode{2} = {'Interactive', 'Manual', 'ROI'};

            obj.BatchOpt.Destination    = {'Current'};
            obj.BatchOpt.Destination{2} = destBuffers;

            obj.BatchOpt.ZarrPyramidLevel{2} = arrayfun(@(x) sprintf('s%d', x), 0:9, 'UniformOutput', false);
            obj.BatchOpt.ZarrPyramidLevel(1) = obj.BatchOpt.ZarrPyramidLevel{2}(1);

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

            obj.view.gui.Icon = fullfile(obj.mibModel.mibPath, 'assets', 'icons', 'mib_icon_16px.png');

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
            % function closeWindow(obj)
            % closing CropDataset window

            if isvalid(obj.view.gui)
                delete(obj.view.gui);
            end

            for i = 1:numel(obj.listener)
                delete(obj.listener{i});
            end

            notify(obj, 'CloseEvent');
        end

        function addCallbacks(obj)
            % function addCallbacks(obj)
            % assign callbacks to all interactive widgets; called once from
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

            % buttons
            h.resetBtn.ButtonPushedFcn  = @(~,~) obj.resetBtn_Callback();
            h.cropBtn.ButtonPushedFcn   = @(src,~) obj.cropBtn_Callback(src);
            h.croptoBtn.ButtonPushedFcn = @(~,~) obj.cropToBtn_Callback();
            h.helpButton.ButtonPushedFcn = @(~,~) obj.helpButton_Callback();
            h.closeBtn.ButtonPushedFcn  = @(~,~) obj.closeWindow();
        end

        function returnBatchOpt(obj, BatchOptOut)
            % function returnBatchOpt(obj, BatchOptOut)
            % return structure with Batch Options via the 'SyncBatch' event
            %
            % Parameters:
            % BatchOptOut: [@em optional] local BatchOpt to send; defaults to obj.BatchOpt

            if nargin < 2; BatchOptOut = obj.BatchOpt; end
            if isfield(BatchOptOut, 'id'); BatchOptOut = rmfield(BatchOptOut, 'id'); end
            eventdata = core.ToggleEventData(BatchOptOut);
            notify(obj.mibModel, 'SyncBatch', eventdata);
        end

        function updateBatchOptFromGUI(obj, hObject)
            % function updateBatchOptFromGUI(obj, hObject)
            % update obj.BatchOpt from a GUI widget
            %
            % Parameters:
            % hObject: handle to the widget that changed

            obj.BatchOpt = utils.updateBatchOptFromGUI_Shared(obj.BatchOpt, hObject);
        end

        function updateWidgets(obj)
            % function updateWidgets(obj)
            % update all widgets of the current window

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

            % update Zarr pyramid dropdown
            if isempty(dataset.image.pyramid.levelNames)   % standard dataset
                obj.BatchOpt.ZarrPyramidLevel(1) = obj.BatchOpt.ZarrPyramidLevel{2}(1);
                obj.view.handles.ZarrPyramidLevel.Enable = 'off';
            else                                       % Zarr/pyramid dataset
                obj.view.handles.ZarrPyramidLevel.Enable = 'on';
            end
            obj.view.handles.ZarrPyramidLevel.Items = obj.BatchOpt.ZarrPyramidLevel{2};
            obj.view.handles.ZarrPyramidLevel.Value = obj.BatchOpt.ZarrPyramidLevel{1};
            obj.selectZarrLevel();
        end

        function radio_Callback(obj, hObject)
            % function radio_Callback(obj, hObject)
            % callback for selection of crop mode
            %
            % Parameters:
            % hObject: handle to the selected radio button (Interactive, Manual, or ROI)

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
            % function editboxes_Callback(obj)
            % update obj.roiPos from the values in the Width/Height/Depth/Time fields

            str2 = obj.view.handles.Width.Value;
            obj.roiPos{1}(1) = min(str2num(str2)); %#ok<ST2NM>
            obj.roiPos{1}(2) = max(str2num(str2)); %#ok<ST2NM>
            str2 = obj.view.handles.Height.Value;
            obj.roiPos{1}(3) = min(str2num(str2)); %#ok<ST2NM>
            obj.roiPos{1}(4) = max(str2num(str2)); %#ok<ST2NM>
            str2 = obj.view.handles.Depth.Value;
            obj.roiPos{1}(5) = min(str2num(str2)); %#ok<ST2NM>
            obj.roiPos{1}(6) = max(str2num(str2)); %#ok<ST2NM>
            str2 = obj.view.handles.Time.Value;
            obj.roiPos{1}(7) = min(str2num(str2)); %#ok<ST2NM>
            obj.roiPos{1}(8) = max(str2num(str2)); %#ok<ST2NM>
        end

        function SelectROI_Callback(obj)
            % function SelectROI_Callback(obj)
            % callback for change of the SelectROI dropdown

            % convert dropdown string value to 0-based ROI index
            val = obj.view.handles.SelectROI.ValueIndex - 1;
            id = obj.mibModel.getActiveId();
            dataset = obj.mibModel.I{id};

            str2 = obj.view.handles.Time.Value;
            tMin = min(str2num(str2)); %#ok<ST2NM>
            tMax = max(str2num(str2)); %#ok<ST2NM>

            if val == 0     % 'All' — collect bounding box of every ROI
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
            % function resetBtn_Callback(obj)
            % reset crop fields to full image dimensions

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

        function selectZarrLevel(obj)
            % function selectZarrLevel(obj)
            % update Zarr downsampling info label based on the selected pyramid level

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
            % function ZarrPyramidLevel_Callback(obj, hObject)
            % callback for the Zarr pyramid level dropdown

            obj.selectZarrLevel();
            obj.updateBatchOptFromGUI(hObject);
        end

        function cropToBtn_Callback(obj)
            % function cropToBtn_Callback(obj)
            % select a destination buffer and perform crop there

            if strcmp(obj.BatchOpt.Width, 'Multi')
                dlgOpt.MsgBoxOnly  = true;
                dlgOpt.Icon        = 'puffin_warning';
                dlgOpt.HeaderLines = 1;
                utils.dlgs.inputUniversalDlg(obj.view.gui, ...
                    '!!! Warning !!!', {''}, ...
                    {'Oops, not implemented yet!\nPlease select a single ROI from the Select ROI combobox'}, ...
                    'Multiple ROI crop', dlgOpt);
                notify(obj.mibModel, 'StopProtocol');
                return;
            end

            % find the first empty buffer as default destination
            maxId = obj.mibModel.Sets.datasetsInSet * numel(obj.mibModel.Sets.names);
            bufferId = maxId;
            for i = 1:maxId - 1
                if strcmp(obj.mibModel.I{i}.image.filename, 'none.tif')
                    bufferId = i;
                    break;
                end
            end

            prompts = {'Enter the destination buffer:'};
            defAns  = {arrayfun(@(x) {num2str(x)}, 1:maxId)};
            defAns{1}(end+1) = {bufferId};      % numeric default index as last element
            answer = utils.dlgs.inputUniversalDlg(obj.view.gui, '', prompts, defAns, 'Crop dataset to');
            if isempty(answer); return; end

            bufferId = str2double(answer{1});
            obj.BatchOpt.Destination(1) = {sprintf('Container %d', bufferId)};
            obj.cropBtn_Callback();
        end

        function cropBtn_Callback(obj, hObject)
            % function cropBtn_Callback(obj, hObject)
            % perform the crop operation
            %
            % Parameters:
            % hObject: [@em optional] handle to the pressed button (cropBtn or croptoBtn)

            if nargin > 1
                if strcmp(hObject.Tag, 'cropBtn')
                    obj.BatchOpt.Destination(1) = {'Current'};
                end
            end

            BatchOptLoc = obj.BatchOpt;
            id          = obj.mibModel.id;

            if strcmp(BatchOptLoc.cropMode{1}, 'Interactive')
                % --- Interactive mode: user draws a rectangle on the image axes ---
                % Resolve the currently active image axes (split-panel safe).
                % Priority: mibController → cImageDoc{selectedSet}.handles.imViewAxes;
                % fall back to a cached axes handle if mibController is not available.
                imViewAxes = [];
                cImageDoc  = [];
                if ~isempty(obj.mibController) && isvalid(obj.mibController)
                    selectedSet = obj.mibModel.Sets.selectedSet;
                    if selectedSet >= 1 && selectedSet <= numel(obj.mibController.cImageDoc)
                        cImageDoc  = obj.mibController.cImageDoc{selectedSet};
                        if ~isempty(cImageDoc) && isvalid(cImageDoc)
                            imViewAxes = cImageDoc.handles.imViewAxes;
                        end
                    end
                end
                if isempty(imViewAxes) && ~isempty(obj.mibImageAxes) && isgraphics(obj.mibImageAxes)
                    imViewAxes = obj.mibImageAxes;
                end
                if isempty(imViewAxes) || ~isgraphics(imViewAxes)
                    utils.dlgs.showErrorDialog(obj.view.gui, ...
                        sprintf('!!! Error !!!\n\nImage axes handle is not available.\nPlease use Manual or ROI mode instead.'), ...
                        'Interactive crop error');
                    return;
                end

                obj.view.gui.Visible = 'off';
                obj.mibModel.disableSegmentation = 1;

                % Hide brush overlay and switch cursor while drawing
                if ~isempty(cImageDoc) && isvalid(cImageDoc)
                    if ~isempty(cImageDoc.brushCursor) && isvalid(cImageDoc.brushCursor)
                        cImageDoc.brushCursor.Visible = false;
                    end
                    cImageDoc.UIFigure.Pointer = 'cross';
                end

                roi = [];
                try
                    roi = drawrectangle(imViewAxes);
                    if isvalid(roi); wait(roi); end
                catch ME
                    if ~isempty(roi) && isvalid(roi); delete(roi); end
                    obj.mibModel.disableSegmentation = 0;
                    if ~isempty(cImageDoc) && isvalid(cImageDoc)
                        cImageDoc.UIFigure.Pointer = 'cross';
                        cImageDoc.updateBrushCursor();
                    end
                    obj.view.gui.Visible = 'on';
                    rethrow(ME);
                end

                % Cleanup pointer/overlay
                obj.mibModel.disableSegmentation = 0;
                if ~isempty(cImageDoc) && isvalid(cImageDoc)
                    cImageDoc.UIFigure.Pointer = 'cross';
                    cImageDoc.updateBrushCursor();
                end
                obj.view.gui.Visible = 'on';

                % User cancelled (Escape) — roi becomes invalid before Position is read
                if isempty(roi) || ~isvalid(roi); return; end

                new_position = roi.Position;   % [xmin ymin w h] — same format as imrect
                delete(roi);

                if isempty(new_position) || any(~isfinite(new_position)); return; end
                if new_position(3) == 0 || new_position(4) == 0
                    utils.dlgs.showErrorDialog(obj.view.gui, ...
                        sprintf('!!! Error !!!\n\nThe defined area is too small!\nTo select the area for crop press the left mouse button and drag the mouse while having the left mouse button pressed. To confirm selection, double click inside the selected area'), ...
                        'Crop error');
                    return;
                end

                % convert [xmin ymin width height] to [xmin ymin xmax ymax]
                new_position(3) = new_position(3) + new_position(1);   % xMax
                new_position(4) = new_position(4) + new_position(2);   % yMax
                if new_position(1) < 0; new_position(1) = max([new_position(1), 0.5]); end
                if new_position(2) < 0; new_position(2) = max([new_position(2), 0.5]); end

                opts.blockModeSwitch = 0;
                [height, width] = obj.mibModel.I{id}.getDatasetDimensions('selection', [], opts);

                [position(1), position(2)] = obj.mibModel.convertMouseToDataCoordinates(new_position(1), new_position(2), 'shown');
                [position(3), position(4)] = obj.mibModel.convertMouseToDataCoordinates(new_position(3), new_position(4), 'shown');
                position = ceil(position);

                if position(3) > width;  position(3) = width;  end
                if position(4) > height; position(4) = height; end

                if obj.mibModel.I{id}.orientation == 3       % XY plane
                    crop_factor = [position(1:2), position(3)-position(1)+1, position(4)-position(2)+1, ...
                        1, obj.mibModel.I{id}.image.depth];
                elseif obj.mibModel.I{id}.orientation == 1   % XZ plane
                    crop_factor = [position(2), 1, position(4)-position(2)+1, obj.mibModel.I{id}.image.height, ...
                        position(1), position(3)-position(1)+1];
                elseif obj.mibModel.I{id}.orientation == 2   % YZ plane
                    crop_factor = [1, position(2), obj.mibModel.I{id}.image.width, position(4)-position(2)+1, ...
                        position(1), position(3)-position(1)+1];
                end

            else
                % --- Manual / ROI mode ---
                if strcmp(BatchOptLoc.Width, 'Multi')
                    dlgOpt.MsgBoxOnly  = true;
                    dlgOpt.Icon        = 'puffin_warning';
                    dlgOpt.HeaderLines = 1;
                    utils.dlgs.inputUniversalDlg(obj.view.gui, ...
                        '!!! Warning !!!', {''}, ...
                        {'Oops, not implemented yet!\nPlease select a single ROI from the Select ROI combobox'}, ...
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
            if ~strcmp(BatchOptLoc.Destination{1}, sprintf('Container %d', id)) && ...
                    ~strcmp(BatchOptLoc.Destination{1}, 'Current')
                bufferId = str2double(BatchOptLoc.Destination{1}(end));
                % deep-copy dataset to destination buffer before cropping
                copyOpts.showWaitbar = BatchOptLoc.showWaitbar;
                if ~isempty(obj.view) && isvalid(obj.view.gui)
                    copyOpts.UIFigure = obj.view.gui;
                else
                    copyOpts.UIFigure = [];
                end
                obj.mibModel.imageDeepCopy(id, bufferId, copyOpts);
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

            obj.mibModel.I{bufferId}.enableSelection = obj.mibModel.preferences.System.EnableSelection;

            % get Zarr pyramid level index if applicable
            if strcmp(obj.view.handles.ZarrPyramidLevel.Enable, 'on')
                items = obj.view.handles.ZarrPyramidLevel.Items;
                BatchOptLoc.pyramidLevel = find(strcmp(items, obj.view.handles.ZarrPyramidLevel.Value), 1);
                if isempty(BatchOptLoc.pyramidLevel); BatchOptLoc.pyramidLevel = 1; end
            end

            result = obj.mibModel.I{bufferId}.cropDataset(crop_factor, BatchOptLoc);
            if result == 0; notify(obj.mibModel, 'StopProtocol'); return; end

            obj.mibModel.I{bufferId}.hROI.crop(crop_factor);
            obj.mibModel.I{bufferId}.annotations.crop(crop_factor);
            log_text = ['ImCrop: [x1 y1 dx dy z1 dz t1 dt]: [' num2str(crop_factor) ']'];
            obj.mibModel.I{bufferId}.image.updateActionLog(log_text);

            % notify about the new dataset
            obj.listener{1}.Enabled = 0;    % suppress updateWidgets during event
            if bufferId == id
                notify(obj.mibModel, 'NewDataset');
            else
                eventdata = core.ToggleEventData(struct('index', bufferId));
                notify(obj.mibModel, 'NewDataset', eventdata);
            end
            obj.listener{1}.Enabled = 1;

            if strcmp(BatchOptLoc.Destination{1}, sprintf('Container %d', id)) || ...
                    strcmp(BatchOptLoc.Destination{1}, 'Current')
                notify(obj.mibModel, 'ShowImage');
            end

            % refresh widgets (GUI mode only, current buffer only)
            if ~isempty(obj.view) && bufferId == id
                obj.updateWidgets();
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
            % function helpButton_Callback(obj)
            % open the help page for the Crop Dataset dialog

            web(fullfile(obj.mibModel.mibPath, 'techdoc/html/user-interface/menu/dataset/dataset-crop.html'), '-browser');
        end

    end
end
