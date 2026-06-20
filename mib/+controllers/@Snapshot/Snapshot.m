classdef Snapshot < handle
    % SNAPSHOT - Controller for the Snapshot dialog.
    %
    % Makes snapshots of the currently shown image in MIB. Supports saving
    % to file or clipboard, various formats (TIF, JPG, PNG, BMP), scale bars,
    % split channels, and ROI/shown area cropping.

    properties
        mibModel
        % handle to MibModel
        mibController
        % handle to MibController (for modifier keys)
        view
        % handle to the view (core.ChildView)
        listener
        % cell array of listener handles
        extraController
        % optional handle to extra controller (volume viewer)
        origHeight
        % original height of the image area
        origWidth
        % original width of the image area
        resizedWidth
        % width adjusted for aspect ratio
        BatchOpt
        % BatchOpt structure for batch processing
    end

    events
        CloseEvent
        % event firing when window is closed
    end

    methods (Static)
        function ViewListner_Callback2(obj, src, evnt)
            % VIEWLISTNER_CALLBACK2 - Standard listener callback with validity guard.
            if ~isvalid(obj) || isempty(obj.view) || ~isvalid(obj.view.gui)
                for i = 1:numel(obj.listener); delete(obj.listener{i}); end
                return;
            end
            switch evnt.EventName
                case {'UpdateGuiWidgets', 'NewDataset'}
                    obj.updateWidgets();
                case 'AxesLimitsChanged'
                    obj.axesLimitsChanged_Callback();
            end
        end
    end

    methods
        function obj = Snapshot(mibModel, varargin)
            % SNAPSHOT - Constructor for the Snapshot controller.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       controller = controllers.Snapshot(mibModel)
            %       controller = controllers.Snapshot(mibModel, extraController)
            %       controller = controllers.Snapshot(mibModel, [], BatchOpt)
            %
            % Parameters:
            %   **mibModel** — handle to the MibModel instance
            %
            %   **extraController** *(optional)* — handle to extra controller (volume viewer)
            %
            %   **BatchOpt** *(optional)* — structure with batch options or NaN to return defaults

            obj.mibModel = mibModel;
            if nargin > 1 && ~isempty(varargin{1})
                obj.extraController = varargin{1};
            else
                obj.extraController = [];
            end

            % Initialize BatchOpt
            obj.BatchOpt.Destination = {'Clipboard'};
            obj.BatchOpt.Destination{2} = {'File', 'Clipboard'};
            obj.BatchOpt.Crop = {'FullImage'};
            obj.BatchOpt.Crop{2} = {'FullImage', 'ShownArea', 'ROI'};
            obj.BatchOpt.RoiIndex = {'1'};
            obj.BatchOpt.RoiIndex{2} = {'1'};
            obj.BatchOpt.Width = '';
            obj.BatchOpt.Height = '';

            obj.BatchOpt.Width{1} = 1024;
            obj.BatchOpt.Width{2} = [1 Inf];
            obj.BatchOpt.Width{3} = true;
            obj.BatchOpt.Height{1} = 1024;
            obj.BatchOpt.Height{2} = [1 Inf];
            obj.BatchOpt.Height{3} = true;

            obj.BatchOpt.ResizeMethod = {'bicubic'};
            obj.BatchOpt.ResizeMethod{2} = {'bicubic', 'bilinear', 'nearest'};
            obj.BatchOpt.Scalebar = false;
            obj.BatchOpt.Measurements = false;
            obj.BatchOpt.WhiteBackground = true;
            obj.BatchOpt.SplitChannels = false;
            obj.BatchOpt.Grayscale = false;
            obj.BatchOpt.ColsNumber{1} = 2;         % default value
            obj.BatchOpt.ColsNumber{2} = [1 Inf];   % range
            obj.BatchOpt.ColsNumber{3} = true;      % round
            obj.BatchOpt.RowsNumber{1} = 2;            % default value
            obj.BatchOpt.RowsNumber{2} = [1 Inf];   % range
            obj.BatchOpt.RowsNumber{3} = true;      % round
            obj.BatchOpt.Margin{1} = 10;            % default value
            obj.BatchOpt.Margin{2} = [0 Inf];       % range
            obj.BatchOpt.Margin{3} = true;          % round
            obj.BatchOpt.FileFormat = {'TIF'};
            obj.BatchOpt.FileFormat{2} = {'TIF', 'BMP', 'JPG', 'PNG'};
            obj.BatchOpt.TIFcompression = {'lzw'};
            obj.BatchOpt.TIFcompression{2} = {'none', 'lzw', 'packbits', 'deflate', 'jpeg', 'ccitt', 'fax3', 'fax4'};
            obj.BatchOpt.JPGmode = {'lossy'};
            obj.BatchOpt.JPGmode{2} = {'lossy', 'lossless'};
            obj.BatchOpt.JPGquality = '95';

            % batch tool metadata
            obj.BatchOpt.mibBatchSectionName = 'Ribbon -> Home';
            obj.BatchOpt.mibBatchActionName = 'Make snapshot';
            % tooltips
            obj.BatchOpt.mibBatchTooltip.Destination = 'Destination for snapshots';
            obj.BatchOpt.mibBatchTooltip.Crop = 'Crop the snapshot to ROI or the shown area';
            obj.BatchOpt.mibBatchTooltip.RoiIndex = '[ROI Crop only] index of ROI to be used for cropping';
            obj.BatchOpt.mibBatchTooltip.Width = 'Width of the output image, keep empty to match the crop parameter';
            obj.BatchOpt.mibBatchTooltip.Height = 'Height of the output image, keep empty to match the crop parameter';
            obj.BatchOpt.mibBatchTooltip.ResizeMethod = 'Method for image resizing, normally - bicubic for downsampling and nearest for upsampling';
            obj.BatchOpt.mibBatchTooltip.Scalebar = 'When checked, add a scale bar to the output image';
            obj.BatchOpt.mibBatchTooltip.Measurements = 'When checked, add measurements to the output image';
            obj.BatchOpt.mibBatchTooltip.WhiteBackground = 'When checked, use the white color for background, recommended for EM images, otherwise black - recommended for LM images';
            obj.BatchOpt.mibBatchTooltip.SplitChannels = 'When checked, make a montage image where the shown channels are split into a single images';
            obj.BatchOpt.mibBatchTooltip.Grayscale = '[Split channels only] render each channel as grayscale image, otherwise the color is defined by LUT';
            obj.BatchOpt.mibBatchTooltip.ColsNumber = '[Split channels only] number of columns in the output montage image';
            obj.BatchOpt.mibBatchTooltip.RowsNumber = '[Split channels only] number of rows in the output montage image';
            obj.BatchOpt.mibBatchTooltip.Margin = '[Split channels only] margin between individual panels in pixels';
            obj.BatchOpt.mibBatchTooltip.FileFormat = '[File target only] output format for snapshots';
            obj.BatchOpt.mibBatchTooltip.TIFcompression = '[TIF only] type of compression algorithm to use';
            obj.BatchOpt.mibBatchTooltip.JPGmode = '[JPG only] type of compression algorithm to use';
            obj.BatchOpt.mibBatchTooltip.JPGquality = '[JPG only] compression quality from 0 to 100';

            % handle batch mode
            if nargin == 3
                BatchOptInput = varargin{2};
                if isstruct(BatchOptInput) == 0
                    if isnan(BatchOptInput)
                        obj.returnBatchOpt();
                    else
                        utils.dlgs.showErrorDialog([], 'A structure as the 3rd parameter is required!', 'BatchOpt Error');
                    end
                    return;
                end
                obj.BatchOpt = updateBatchOptCombineFields_Shared(obj.BatchOpt, BatchOptInput);
                obj.snapshotBtn_Callback();
                return;
            end

            % GUI mode
            obj.view = core.ChildView(obj, 'views.SnapshotGUI');
            obj.addCallbacks();
            obj.updateWidgets();

            % update font and size
            Font = obj.mibModel.preferences.System.Font;
            if obj.view.handles.Clipboard.FontSize ~= Font.FontSize ...
                    || ~strcmp(obj.view.handles.Clipboard.FontName, Font.FontName)
                utils.fontSizeUpdate(obj.view.gui, Font);
            end

            % move window to the left of the main MIB window
            obj.view.gui = utils.moveWindowOutside(obj.view.gui, obj.mibModel.mibGUI, 'left');

            % add listeners
            obj.listener{1} = addlistener(obj.mibModel, 'UpdateGuiWidgets', @(src, evnt) obj.ViewListner_Callback2(obj, src, evnt));
            obj.listener{2} = addlistener(obj.mibModel, 'NewDataset', @(src, evnt) obj.ViewListner_Callback2(obj, src, evnt));
            obj.listener{3} = addlistener(obj.mibModel, 'AxesLimitsChanged', @(src, evnt) obj.ViewListner_Callback2(obj, src, evnt));

            % add handle tags to tooltips in developer mode
            if obj.mibModel.preferences.System.DeveloperMode
                utils.overrideDescriptions(obj.view.handles, true, 'obj.view.handles');
            end

            % show the dialog
            obj.view.gui.Visible = true;
        end

        function addCallbacks(obj)
            % ADDCALLBACKS - Wire essential callbacks (CloseRequestFcn only).
            % Other callbacks are wired in the .mlapp by the user.
            obj.view.gui.CloseRequestFcn = @(~, ~) obj.closeWindow();
            
            h = obj.view.handles;
            % Destination radio button group (Clipboard / File)
            h.Destination.SelectionChangedFcn = @(~, ~) obj.updateDestination();
            % Crop radio button group (Full / Shown / Roi)
            h.Crop.SelectionChangedFcn = @(~, ~) obj.updateCropMode();
            
            h.RoiIndex.ValueChangedFcn = @(~, ~) obj.updateRoiIndex();  % Roi index changed
            h.Width.ValueChangedFcn = @(~, ~) obj.Width_Callback();     % Width changed
            h.Height.ValueChangedFcn = @(~, ~) obj.Height_Callback();   % Height changed
            h.ResizeMethod.ValueChangedFcn = @(~, ~) obj.updateBatchOptFromGUI(h.ResizeMethod);   % Height changed
            h.binCheck.ValueChangedFcn = @(~, ~) obj.binCheck_Callback();   % bin/mag switch

            % bin/mag buttons
            h.bin2Btn.ButtonPushedFcn = @obj.binMagButtons_Callback;   % bin/mag buttons
            h.bin4Btn.ButtonPushedFcn = @obj.binMagButtons_Callback;   % bin/mag buttons
            h.bin8Btn.ButtonPushedFcn = @obj.binMagButtons_Callback;   % bin/mag buttons

            % Options panel
            h.SplitChannels.ValueChangedFcn = @(~, ~) obj.SplitChannels_Callback();
            h.Grayscale.ValueChangedFcn = @(~, ~) obj.updateBatchOptFromGUI(h.Grayscale);
            h.ColsNumber.ValueChangedFcn = @(~, ~) obj.updateBatchOptFromGUI(h.ColsNumber);
            h.RowsNumber.ValueChangedFcn = @(~, ~) obj.updateBatchOptFromGUI(h.RowsNumber);
            h.Margin.ValueChangedFcn = @(~, ~) obj.updateBatchOptFromGUI(h.Margin);
            
            h.Scalebar.ValueChangedFcn = @(~, ~) obj.scalebar_Callback();
            h.WhiteBackground.ValueChangedFcn = @(~, ~) obj.updateBatchOptFromGUI(h.WhiteBackground);
            h.Measurements.ValueChangedFcn = @(~, ~) obj.measurements_Callback();
            h.measurementsOptions.ButtonPushedFcn = @(~, ~) obj.measurementsOptions_Callback();
            
            % File format panel
            h.FileFormatTabGroup.SelectionChangedFcn = @(~, ~) obj.FileFormatTabGroup_Callback();
            h.FileFormat.ValueChangedFcn = @(~, ~) obj.FileFormat_Callback();
            h.JPGquality.ValueChangedFcn = @(~, ~) obj.updateBatchOptFromGUI(h.JPGquality);
            h.JPGmode.ValueChangedFcn = @(~, ~) obj.updateBatchOptFromGUI(h.JPGmode);
            h.selectFileBtn.ButtonPushedFcn = @(~, ~) obj.selectFileBtn_Callback();
            h.outputDir.ValueChangedFcn = @(~, ~) obj.outputDir_Callback();

            % buttons at the bottom
            h.helpButton.ButtonPushedFcn = @(~, ~) obj.help();
            h.snapshotBtn.ButtonPushedFcn = @(~, ~) obj.snapshotBtn_Callback();
            h.closelBtn.ButtonPushedFcn = @(~, ~) obj.closeWindow();
        end

        function closeWindow(obj)
            % CLOSEWINDOW - Close the Snapshot dialog and clean up.
            if isvalid(obj.view.gui)
                delete(obj.view.gui);
            end
            for i = 1:numel(obj.listener)
                delete(obj.listener{i});
            end
            notify(obj, 'CloseEvent');
        end

        function returnBatchOpt(obj, BatchOptOut)
            % RETURNBATCHOPT - Return BatchOpt structure via SyncBatch event.
            if nargin < 2; BatchOptOut = obj.BatchOpt; end
            eventdata = core.ToggleEventData(BatchOptOut);
            notify(obj.mibModel, 'SyncBatch', eventdata);
        end

        function updateBatchOptFromGUI(obj, hObject, ~)
            % UPDATEBATCHOPTFROMGUI - Update BatchOpt from GUI widget value.
            obj.BatchOpt = utils.updateBatchOptFromGUI_Shared(obj.BatchOpt, hObject);
        end

        function updateWidgets(obj)
            % UPDATEWIDGETS - Refresh all widgets to match the current dataset state.

            activeId = obj.mibModel.getActiveId();

            if ~isempty(obj.extraController)
                obj.view.handles.FullImage.Enable = 'off';
                obj.view.handles.ShownArea.Enable = 'off';
                obj.view.handles.ROI.Enable = 'off';
                obj.view.handles.SplitChannels.Enable = 'off';
                obj.view.handles.Measurements.Enable = 'off';
                obj.view.handles.WhiteBackground.Enable = 'off';
            end

            if isempty(obj.mibModel.I{activeId}.snapshotFilename)
                [filePath, baseName] = fileparts(obj.mibModel.I{activeId}.image.filename);
                if isempty(filePath); filePath = obj.mibModel.currentDirectory; end
                formatValue = obj.view.handles.FileFormat.Value;
                ext = ['.' lower(formatValue)];
                baseName = [baseName, '_snapshot'];
                obj.mibModel.I{activeId}.snapshotFilename = fullfile(filePath, [baseName ext]);
            end
            filename = obj.mibModel.I{activeId}.snapshotFilename;
            [~, ~, ext] = fileparts(filename);

            if strcmp(ext(2:end), 'tif')
                obj.view.handles.FileFormat.Value = 'TIF';
            elseif strcmp(ext(2:end), 'png')
                obj.view.handles.FileFormat.Value = 'PNG';
            elseif strcmp(ext(2:end), 'jpg')
                obj.view.handles.FileFormat.Value = 'JPG';
            elseif strcmp(ext(2:end), 'bmp')
                obj.view.handles.FileFormat.Value = 'BMP';
            end
            obj.FileFormat_Callback();

            obj.updateWidthHeight();

            % update split color channels
            if obj.mibModel.I{activeId}.image.colors > 1
                obj.view.handles.SplitChannels.Enable = 'on';
            else
                obj.view.handles.SplitChannels.Enable = 'off';
                obj.view.handles.SplitChannels.Value = false;
            end
            obj.SplitChannels_Callback();

            [numberOfROI, indices] = obj.mibModel.I{activeId}.hROI.getNumberOfROI();
            if numberOfROI == 0
                obj.view.handles.ROI.Enable = 'off';
                obj.view.handles.RoiIndex.Enable = 'off';
                if obj.view.handles.ROI.Value
                    obj.view.handles.FullImage.Value = true;
                end
            else
                obj.view.handles.ROI.Enable = 'on';
                obj.view.handles.RoiIndex.Enable = 'on';

                roiNames = cell([numberOfROI 1]);
                for i = 1:numberOfROI
                    roiNames(i) = obj.mibModel.I{activeId}.hROI.Data(indices(i)).label;
                end
                if numel(roiNames) < numel(obj.view.handles.RoiIndex.Items)
                    obj.view.handles.RoiIndex.Value = roiNames{1};
                end
                obj.view.handles.RoiIndex.Items = roiNames;
                if obj.mibModel.I{activeId}.selectedROI >  0
                    obj.view.handles.RoiIndex.ValueIndex = obj.mibModel.I{activeId}.selectedROI; 
                    obj.BatchOpt.RoiIndex{1} = num2str(obj.mibModel.I{activeId}.selectedROI);
                end
            end
        end

        function updateWidthHeight(obj)
            % UPDATEWIDTHHEIGHT - Update width/height fields for the snapshot.

            activeId = obj.mibModel.getActiveId();
            dataset = obj.mibModel.I{activeId};
            if isempty(obj.extraController)
                blockModeSwitch = obj.view.handles.ShownArea.Value;
                [height, width] = dataset.image.getDatasetDimensions([], [], blockModeSwitch);
                obj.origWidth = width;
                orientation = dataset.orientation;
                pixSize = dataset.image.pixSize;
                if orientation == 1
                    width = width * pixSize.z / pixSize.x;
                elseif orientation == 2
                    width = width * pixSize.z / pixSize.y;
                elseif orientation == 3
                    width = width * pixSize.x / pixSize.y;
                end
                width = ceil(width);
            else
                if strcmp(obj.extraController.view.gui.Name, '3D onFlyImageStretch')
                    curUnits = obj.extraController.view.handles.volViewPanel.Units;
                    obj.extraController.view.handles.volViewPanel.Units = 'pixels';
                    height = ceil(obj.extraController.view.handles.volViewPanel.Position(4));
                    width = ceil(obj.extraController.view.handles.volViewPanel.Position(3));
                    obj.extraController.view.handles.volViewPanel.Units = curUnits;
                    obj.origWidth = width;
                elseif strcmp(obj.extraController.view.gui.Name, '3D Controls')
                    height = ceil(obj.extraController.childControllers{1}.view.handles.volumeViewerPanel.Position(4));
                    width = ceil(obj.extraController.childControllers{1}.view.handles.volumeViewerPanel.Position(3));
                    obj.origWidth = width;
                end
            end
            obj.view.handles.Width.Value = width;
            obj.view.handles.Height.Value = height;
            obj.origHeight = height;
            obj.resizedWidth = width;
        end

        function axesLimitsChanged_Callback(obj)
            % AXESLIMITSCHANGED_CALLBACK - Update dimensions when shown area changes.
            if obj.view.handles.ShownArea.Value
                obj.crop_Callback();
            end
        end

        function updateDestination(obj)
            % update destination for the snapshot
            if obj.view.handles.File.Value
                obj.view.handles.filePanel.Enable = true;
            else
                obj.view.handles.filePanel.Enable = false;
            end
            obj.updateBatchOptFromGUI(obj.view.handles.Destination);
        end

        function updateCropMode(obj)
            % update the crop mode for the snapshot
            
            % update obj.BatchOpt
            obj.updateBatchOptFromGUI(obj.view.handles.Crop);
            % update the crop factor
            obj.crop_Callback();
        end

        function updateRoiIndex(obj)
            % updateRoiIndex - Update shown ROI selection.
            activeId = obj.mibModel.getActiveId();
            roiItems = obj.view.handles.RoiIndex.Items;
            roiValue = obj.view.handles.RoiIndex.Value;
            roiIdx = find(strcmp(roiItems, roiValue), 1);
            obj.mibModel.I{activeId}.selectedROI = roiIdx;
            
            eventdata = core.ToggleEventData({'roi'});
            notify(obj.mibModel, 'UpdateGuiWidgets', eventdata);
            
            notify(obj.mibModel, 'ShowImage');
            obj.crop_Callback();
        end

        function binCheck_Callback(obj)
            % update buttons bin/mag buttons
            if obj.view.handles.binCheck.Value
                obj.view.handles.bin2Btn.Text = 'bin x2';
                obj.view.handles.bin2Btn.Tooltip = 'Reduce dimensions of the snapshot in 2 times';
                obj.view.handles.bin4Btn.Text = 'bin x4';
                obj.view.handles.bin4Btn.Tooltip = 'Reduce dimensions of the snapshot in 4 times';
                obj.view.handles.bin8Btn.Text = 'bin x8';
                obj.view.handles.bin8Btn.Tooltip = 'Reduce dimensions of the snapshot in 8 times';
            else
                obj.view.handles.bin2Btn.Text = 'mag x2';
                obj.view.handles.bin2Btn.Tooltip = 'Increse dimensions of the snapshot in 2 times';
                obj.view.handles.bin4Btn.Text = 'mag x4';
                obj.view.handles.bin4Btn.Tooltip = 'Increse dimensions of the snapshot in 4 times';
                obj.view.handles.bin8Btn.Text = 'mag x8';
                obj.view.handles.bin8Btn.Tooltip = 'Increse dimensions of the snapshot in 8 times';
            end
        end

        function binMagButtons_Callback(obj, hObject, event)
            % calculate new width/height of the dataset depending on the
            % pressed button and its text

            % get downsampling / upsampling factor
            switch hObject.Tag
                case 'bin2Btn'
                    xFactor = 2;
                case 'bin4Btn'
                    xFactor = 4;
                case 'bin8Btn'
                    xFactor = 8;
            end

            % magnification mode
            if hObject.Text(1) == 'm'
                xFactor = 1/xFactor;
            end
            width = obj.view.handles.Width.Value;
            height = obj.view.handles.Height.Value;
            width = ceil(width/xFactor);
            height = ceil(height/xFactor);
            obj.view.handles.Width.Value = width;
            obj.view.handles.Height.Value = height;
        end

        function FileFormat_Callback(obj)
            % FILEFORMAT_CALLBACK - Switch format tab and update filename extension.
            format = obj.view.handles.FileFormat.Value;

            % switch the selected tab
            switch format
                case 'BMP'
                    obj.view.handles.FileFormatTabGroup.SelectedTab = obj.view.handles.bmpTab;
                case 'JPG'
                    obj.view.handles.FileFormatTabGroup.SelectedTab = obj.view.handles.jpgTab;
                case 'PNG'
                    obj.view.handles.FileFormatTabGroup.SelectedTab = obj.view.handles.pngTab;
                case 'TIF'
                    obj.view.handles.FileFormatTabGroup.SelectedTab = obj.view.handles.tifTab;
            end

            activeId = obj.mibModel.getActiveId();
            fn = obj.mibModel.I{activeId}.snapshotFilename;
            [filePath, baseName, ~] = fileparts(fn);
            ext = ['.' lower(format)];
            fn = fullfile(filePath, [baseName ext]);
            obj.view.handles.outputDir.Value = fn;
            obj.mibModel.I{activeId}.snapshotFilename = fn;

            % update BatchOpt
            obj.updateBatchOptFromGUI(obj.view.handles.FileFormat);
        end

        function FileFormatTabGroup_Callback(obj)
            % FILEFORMATTABGROUP_CALLBACK - Sync format dropdown and filename when a tab is clicked directly.
            tabTitle = obj.view.handles.FileFormatTabGroup.SelectedTab.Title;
            obj.view.handles.FileFormat.Value = tabTitle;
            activeId = obj.mibModel.getActiveId();
            fn = obj.mibModel.I{activeId}.snapshotFilename;
            [filePath, baseName] = fileparts(fn);
            fn = fullfile(filePath, [baseName '.' lower(tabTitle)]);
            obj.view.handles.outputDir.Value = fn;
            obj.mibModel.I{activeId}.snapshotFilename = fn;
            obj.updateBatchOptFromGUI(obj.view.handles.FileFormat);
        end

        function measurements_Callback(obj)
            % enable or disable rendering of measurements on the snapshot

            obj.view.handles.measurementsOptions.Enable = false;
            if obj.view.handles.Measurements.Value
                dlgOpt.MsgBoxOnly  = true;
                dlgOpt.Icon        = 'puffin_warning';
                dlgOpt.HeaderLines = 1;
                dlgOpt.WindowHeight = 220;
                msgText = sprintf('Addition of measurements to the snapshot may add artifacts at the borders of the image (at least in R2014b)!\n\nAfter rendering please make sure that the snapshot is good enough for your purposes!');
                utils.dlgs.inputUniversalDlg(obj.view.gui, ...
                    sprintf('Attention!'), ...
                    {}, {msgText}, 'Adding measurements', dlgOpt);
                obj.view.handles.measurementsOptions.Enable = true;
            end
            obj.updateBatchOptFromGUI(obj.view.handles.Measurements);
        end

        function measurementsOptions_Callback(obj)
            % MEASUREMENTSOPTIONS_CALLBACK - Update measurement visualization settings.
            activeId = obj.mibModel.getActiveId();
            obj.mibModel.I{activeId}.measure.updateOptions(obj.view.gui);
            notify(obj.mibModel, 'ShowImage');
        end

        function scalebar_Callback(obj)
            % SCALEBAR_CALLBACK - Enable scale bar and verify pixel size.
            if obj.view.handles.Scalebar.Value
                activeId = obj.mibModel.getActiveId();
                dataset = obj.mibModel.I{activeId};
                dlgOpts.showDialog   = true;
                dlgOpts.ParentFigure = obj.view.gui;
                dlgOpts.mibPath      = obj.mibModel.mibPath;
                dlgOpts.WindowStyle = 'modal';
                [~, newPixSize, dlgResult] = utils.updatePixSizeAndResolution([], dataset.image.pixSize, dlgOpts);
                if dlgResult; dataset.setPixSize(newPixSize); end
            end
            obj.updateBatchOptFromGUI(obj.view.handles.Scalebar);
        end

        function crop_Callback(obj)
            % CROP_CALLBACK - Update dimensions based on crop mode selection.

            activeId = obj.mibModel.getActiveId();

            switch obj.BatchOpt.Crop{1}
                case 'FullImage'
                    options.blockModeSwitch = 0;
                case 'ShownArea'
                    options.blockModeSwitch = 1;
                case 'ROI'
                    options.blockModeSwitch = 0;
            end

            if strcmp(obj.BatchOpt.Crop{1}, 'ROI')
                roiValue = obj.view.handles.RoiIndex.Value;
                roiImg = obj.mibModel.I{activeId}.hROI.returnMask(roiValue);
                STATS = regionprops(roiImg, 'BoundingBox');
                width = ceil(STATS.BoundingBox(3));
                height = ceil(STATS.BoundingBox(4));
            else
                [height, width] = obj.mibModel.I{activeId}.getDatasetDimensions('image', [], options);
            end

            obj.origWidth = width;
            obj.view.handles.Height.Value = height;
            orientation = obj.mibModel.I{activeId}.orientation;
            pixSize = obj.mibModel.I{activeId}.image.pixSize;
            if orientation == 1
                width = width * pixSize.z / pixSize.x;
            elseif orientation == 2
                width = width * pixSize.z / pixSize.y;
            elseif orientation == 3
                width = width * pixSize.x / pixSize.y;
            end
            obj.view.handles.Width.Value = width;
            obj.origHeight = height;
            obj.resizedWidth = width;
        end

        function SplitChannels_Callback(obj)
            % SPLITCHANNELS_CALLBACK - Enable/disable split channel controls.
            if obj.view.handles.SplitChannels.Value
                obj.view.handles.Grayscale.Enable = 'on';
                obj.view.handles.ColsNumber.Enable = 'on';
                obj.view.handles.RowsNumber.Enable = 'on';
                obj.view.handles.Margin.Enable = 'on';
            else
                obj.view.handles.Grayscale.Enable = 'off';
                obj.view.handles.ColsNumber.Enable = 'off';
                obj.view.handles.RowsNumber.Enable = 'off';
                obj.view.handles.Margin.Enable = 'off';
            end
        end

        function outputDir_Callback(obj)
            % OUTPUTDIR_CALLBACK - Validate and update the output filename.
            fn = obj.view.handles.outputDir.Value;
            activeId = obj.mibModel.getActiveId();
            [~, ~, ext] = fileparts(fn);
            if isempty(ext)
                formatOut = lower(obj.view.handles.FileFormat.Value);
                fn = strcat(fn, '.', formatOut);
                obj.view.handles.outputDir.Value = fn;
            end
            if isequal(fn, 0)
                obj.view.handles.outputDir.Value = obj.mibModel.I{activeId}.snapshotFilename;
                return;
            end

            if exist(fn, 'file')
                button = utils.dlgs.inputQuestDlg(obj.view.gui, ...
                    sprintf('Warning!\nThe file already exist!\n\nOverwrite?'), ...
                    'Overwrite?', 'Cancel', 'Overwrite', 'Cancel');
                if strcmp(button, 'Cancel'); return; end
            end
            obj.mibModel.I{activeId}.snapshotFilename = fn;
        end

        function selectFileBtn_Callback(obj)
            % SELECTFILEBTN_CALLBACK - Open a file save dialog for the snapshot.
            activeId = obj.mibModel.getActiveId();
            format = obj.view.handles.FileFormat.Value;
            switch format
                case 'BMP'
                    formatText = {'*.bmp', 'Windows Bitmap (*.bmp)'};
                case 'JPG'
                    formatText = {'*.jpg', 'JPG format (*.jpg)'};
                case 'PNG'
                    formatText = {'*.png', 'PNG format (*.png)'};
                case 'TIF'
                    formatText = {'*.tif', 'TIF format (*.tif)'};
            end

            [FileName, PathName, ~] = uiputfile(formatText, 'Select filename', obj.mibModel.I{activeId}.snapshotFilename);
            if isequal(FileName, 0) || isequal(PathName, 0); return; end

            obj.mibModel.I{activeId}.snapshotFilename = fullfile(PathName, FileName);
            obj.view.handles.outputDir.Value = obj.mibModel.I{activeId}.snapshotFilename;
        end

        function Width_Callback(obj)
            % WIDTH_CALLBACK - Update height to maintain aspect ratio when width changes.
            
            newWidth = obj.view.handles.Width.Value;
            if isempty(obj.extraController)
                ratio = obj.origHeight / obj.resizedWidth;
                newHeight = round(newWidth * ratio);
                obj.view.handles.Height.Value = newHeight;
            else
                if strcmp(obj.extraController.view.gui.Name, '3D onFlyImageStretch') || strcmp(obj.extraController.view.gui.Name, '3D Controls')
                    screensize = get(groot, 'Screensize');
                    if screensize(3) < newWidth
                        utils.dlgs.showErrorDialog(obj.view.gui, ...
                            'The output dimensions should be smaller than the screen size!', 'Size is too large');
                        obj.view.handles.Width.Value = obj.resizedWidth;
                        return;
                    end
                end
            end
        end

        function Height_Callback(obj)
            % HEIGHT_CALLBACK - Update width to maintain aspect ratio when height changes.
            newHeight = obj.view.handles.Height.Value;
            if isempty(obj.extraController)
                ratio = obj.origHeight / obj.resizedWidth;
                newWidth = round(newHeight / ratio);
                obj.view.handles.Width.Value = newWidth;
            else
                if strcmp(obj.extraController.view.gui.Name, '3D onFlyImageStretch')
                    screensize = get(groot, 'Screensize');
                    if screensize(4) < newHeight
                        utils.dlgs.showErrorDialog(obj.view.gui, ...
                            'The output dimensions should be smaller than the screen size!', 'Size is too large');
                        obj.view.handles.Height.Value = obj.origHeight;
                        return;
                    end
                end
            end
        end

        function help(obj)
            % show help
            helpFilPath = fullfile(fileparts(obj.mibModel.mibPath), 'docs', 'site', 'user-interface', 'ribbon', 'home', 'home-makesnapshot.html');
            if isfile(helpFilPath)
                web(helpFilPath, '-browser');
            else
                web('http://mib.helsinki.fi/help/main3/user-interface/ribbon/home/home-makesnapshot.html', '-browser');
            end
        end

        function snapshotBtn_Callback(obj, useBatchMode)
            % SNAPSHOTBTN_CALLBACK - Generate and save/copy the snapshot image.

            if nargin < 2; useBatchMode = 0; end
            activeId = obj.mibModel.getActiveId();
            dataset = obj.mibModel.I{activeId};
            if useBatchMode == 0
                obj.view.handles.snapshotBtn.BackgroundColor = [1 0 0];
                drawnow;
            end

            bgColor = double(obj.BatchOpt.WhiteBackground); % 1-white, 0-black

            options.resizeToMagnification = false;
            options.blockModeSwitch = false;
            options.markerType = 'Label + Value';
            if strcmp(obj.BatchOpt.Crop{1}, 'ShownArea')
                options.blockModeSwitch = true;
            elseif strcmp(obj.BatchOpt.Crop{1}, 'ROI')
                options.blockModeSwitch = dataset.blockModeSwitch;
            end

            slices = dataset.slices;
            noColorChannels = numel(slices{4});
            if obj.view.handles.SplitChannels.Value    % split color channels
                rowNo = obj.BatchOpt.RowsNumber{1};
                colNo = obj.BatchOpt.ColsNumber{1};
                if noColorChannels + 1 > rowNo * colNo
                    utils.dlgs.showErrorDialog(obj.view.gui, ...
                        sprintf('Number of selected color channels is larger than the number of panels in the resulting image!\nIncrease number of columns or rows and try again'), ...
                        'Too many color channels');
                    if useBatchMode == 0
                        obj.view.handles.snapshotBtn.BackgroundColor = [0.149 0.902 0.1804];
                    end
                    return;
                end
                maxImageIndex = min([noColorChannels + 1, rowNo * colNo]);
                imageShift = obj.BatchOpt.Margin{1};
            else
                rowNo = 1;
                colNo = 1;
                maxImageIndex = 1;
            end

            newWidth = obj.view.handles.Width.Value;
            newHeight = obj.view.handles.Height.Value;
            colorChannels = slices{4};    % store selected color channels

            progressBar = core.PoolWaitbar(maxImageIndex, 'Generating images, please wait...', ...
                obj.view.gui, 'Making snapshot', true);

            if isempty(obj.extraController)     % snapshot from MIB main window
                for imageId = 1:maxImageIndex
                    if progressBar.getCancelState()
                        progressBar.deletePoolWaitbar();
                        if useBatchMode == 0; obj.view.handles.snapshotBtn.BackgroundColor = [0.149 0.902 0.1804]; end
                        return;
                    end

                    if imageId == maxImageIndex
                        if isfield(options, 'useLut'); options = rmfield(options, 'useLut'); end
                        img = obj.mibModel.getRGBimage(options);   
                    else
                        if obj.BatchOpt.Grayscale; options.useLut = 0; end

                        dataset.slices{4} = colorChannels(imageId);
                        img = obj.mibModel.getRGBimage(options);
                    end
                    dataset.slices{4} = colorChannels;

                    if obj.BatchOpt.Measurements
                        hFig = figure(153);
                        hFig.Renderer = 'zbuffer';
                        clf;
                        warning('off', 'images:initSize:adjustingMag');
                        warning('off', 'MATLAB:print:DeprecateZbuffer');

                        imshow(img);
                        axHandle = gca;
                        hold(axHandle, 'on');
                        % imshow maps image pixel (X,Y) to axes coords (X,Y) — identity conversion
                        convertFcn = @(X, Y) deal(double(X), double(Y));
                        dataset.measure.addMeasurementsToPlot(axHandle, 'full', dataset.orientation, convertFcn, 0);
                        set(axHandle, 'xtick', []);
                        set(axHandle, 'ytick', []);
                        img2 = export_fig('-native', '-zbuffer', '-a1');

                        delete(153);
                        warning('on', 'images:initSize:adjustingMag');
                        warning('on', 'MATLAB:print:DeprecateZbuffer');
                        img = imresize(img2, [size(img, 1) size(img, 2)], 'nearest');
                    end

                    if strcmp(obj.BatchOpt.Crop{1}, 'ROI')
                        roiImg = dataset.hROI.returnMask(str2double(obj.BatchOpt.RoiIndex{1}));
                        STATS = regionprops(roiImg, 'BoundingBox');
                        img = imcrop(img, STATS.BoundingBox);
                    end

                    scale = newWidth / size(img, 2);
                    if newWidth ~= size(img, 2) || newHeight ~= size(img, 1)
                        resizeMethod = obj.view.handles.ResizeMethod.Value;
                        img = imresize(img, [newHeight newWidth], resizeMethod);
                    end

                    if obj.BatchOpt.Scalebar
                        scalebarOptions.orientation = dataset.orientation;
                        scalebarOptions.bgColor = bgColor;
                        img = utils.addScaleBar(img, dataset.image.pixSize, scale, scalebarOptions);
                    end

                    if maxImageIndex == 1
                        imgOut = img;
                    else
                        if imageId == 1
                            outH = size(img, 1);
                            outW = size(img, 2);
                            colId = 1;
                            rowId = 1;
                            maxInt = double(intmax(class(img)));
                            bgColor2 = bgColor * maxInt;
                            imgOut = zeros([outH*rowNo + (rowNo-1)*imageShift, outW*colNo + (colNo-1)*imageShift, size(img, 3)], class(img)) + bgColor2;
                        end

                        y1 = (rowId-1)*outH + 1 + imageShift*(rowId-1);
                        y2 = y1 + outH - 1;
                        x1 = (colId-1)*outW + 1 + imageShift*(colId-1);
                        x2 = x1 + outW - 1;
                        imgOut(y1:y2, x1:x2, :) = img;
                        colId = colId + 1;
                        if colId > colNo
                            colId = 1;
                            rowId = rowId + 1;
                        end
                    end
                    progressBar.increment();
                end
            else
                if strcmp(obj.extraController.view.gui.Name, '3D onFlyImageStretch') || strcmp(obj.extraController.view.gui.Name, '3D Controls')
                    imgOut = obj.extraController.grabFrame(newWidth, newHeight);
                end
                progressBar.increment();
            end

            % cancel check before saving
            if progressBar.getCancelState()
                progressBar.deletePoolWaitbar();
                if useBatchMode == 0; obj.view.handles.snapshotBtn.BackgroundColor = [0.149 0.902 0.1804]; end
                return;
            end

            if obj.view.handles.File.Value     % saving to a file
                if exist(dataset.snapshotFilename, 'file')
                    button = utils.dlgs.inputQuestDlg(obj.view.gui, ...
                        sprintf('Warning!\nThe file already exist!\n\nOverwrite?'), ...
                        'Overwrite?', 'Overwrite', 'Cancel', 'Cancel');
                    if strcmp(button, 'Cancel')
                        progressBar.deletePoolWaitbar();
                        if useBatchMode == 0; obj.view.handles.snapshotBtn.BackgroundColor = [0.149 0.902 0.1804]; end
                        return;
                    end
                end

                format = obj.view.handles.FileFormat.Value;
                switch format
                    case 'BMP'
                        parameters = struct();
                        if ~isa(imgOut, 'uint8')
                            imgOut = im2uint8(imgOut);
                        end
                    case 'JPG'
                        if ~isa(imgOut, 'uint8')
                            imgOut = im2uint8(imgOut);
                        end
                        parameters.Quality = obj.view.handles.JPGquality.Value;
                        parameters.Bitdepth = str2double(obj.view.handles.JPGbitdepth.Value);
                        parameters.Mode = obj.view.handles.JPGmode.Value;
                        parameters.Comment = obj.view.handles.JPGcomment.Value;
                    case 'PNG'
                        parameters.BitDepth = 8;
                    case 'TIF'
                        parameters.Compression = obj.view.handles.TIFcompression.Value;
                        parameters.ColorSpace = obj.view.handles.TIFcolor.Value;
                        parameters.Resolution = obj.view.handles.TIFresolution.Value;
                        parameters.RowsPerStrip = obj.view.handles.TIFrowsperstrip.Value;
                        parameters.Description = obj.view.handles.TIFdescription.Value;
                        parameters.WriteMode = 'overwrite';
                end

                utils.mibImWrite(imgOut, dataset.snapshotFilename, parameters);
            elseif obj.view.handles.Clipboard.Value  % copy to Clipboard
                progressBar.updateText('Exporting to clipboard, please wait...');
                utils.ensureJavaLibraries({'imageselection'});  % link ImageSelection.java on the first use
                imclipboard('copy', imgOut);
            end
            progressBar.deletePoolWaitbar();

            % count user's points
            obj.mibModel.preferences.Users.Tiers.numberOfSnapAndMovies = obj.mibModel.preferences.Users.Tiers.numberOfSnapAndMovies + 1;
            eventdata = core.ToggleEventData(2);
            notify(obj.mibModel, 'UpdateUserScore', eventdata);

            if useBatchMode == 0
                obj.view.handles.snapshotBtn.BackgroundColor = [0.149 0.902 0.1804];
            end
        end

    end
end
