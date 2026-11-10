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
        dimsPixSize
        % pixSize the Width/Height fields were last computed from; a voxel-size change
        % alters the aspect ratio of the output, so axesLimitsChanged_Callback recomputes them
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
            %   **mibModel** - handle to the MibModel instance
            %
            %   **extraController** *(optional)* - handle to extra controller (volume viewer)
            %
            %   **BatchOpt** *(optional)* - structure with batch options or NaN to return defaults

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
            obj.BatchOpt.ROIoutlines = false;
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
            obj.BatchOpt.mibBatchTooltip.ROIoutlines = 'When checked, add outlines of the ROIs to the output image';
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
            utils.ensureJavaLibraries({'imageselection'});  % no-op if already loaded at startup; fallback if not
            obj.view = core.ChildView(obj, 'views.SnapshotGUI');
            utils.applyThemeColors(obj.view.gui);   % adapt the standard dialog button colors to the light/dark theme
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
            h.ROIoutlines.ValueChangedFcn = @(~, ~) obj.updateBatchOptFromGUI(h.ROIoutlines);
            
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
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.Snapshot.closeWindow: triggered\n');
            end
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
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.Snapshot.updateBatchOptFromGUI(%s): triggered\n', hObject.Tag);
            end
            
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
                obj.view.handles.ROIoutlines.Enable = 'off';
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
                    % a programmatic change does not fire SelectionChangedFcn
                    obj.updateCropMode();
                end
            else
                obj.view.handles.ROI.Enable = 'on';
                obj.view.handles.RoiIndex.Enable = 'on';

                roiNames = cell([numberOfROI 1]);
                for i = 1:numberOfROI
                    roiNames(i) = obj.mibModel.I{activeId}.hROI.Data(indices(i)).label;
                end
                % Value falls back to the first item when it is not in the new list
                obj.view.handles.RoiIndex.Items = roiNames;
                % selectedROI indexes hROI.Data, the list holds only the ROIs of the current orientation
                listPosition = find(ismember(indices, obj.mibModel.I{activeId}.selectedROI), 1);
                if ~isempty(listPosition)
                    obj.view.handles.RoiIndex.ValueIndex = listPosition;
                end
                % always refresh: the stored index may come from a buffer with more ROIs
                obj.BatchOpt.RoiIndex{1} = num2str(indices(obj.view.handles.RoiIndex.ValueIndex));
                % updateWidthHeight above returns the size of the full image or the shown area
                if obj.view.handles.ROI.Value
                    obj.crop_Callback();
                end
            end
        end

        function updateWidthHeight(obj)
            % UPDATEWIDTHHEIGHT - Update width/height fields for the snapshot.

            activeId = obj.mibModel.getActiveId();
            dataset = obj.mibModel.I{activeId};
            if isempty(obj.extraController)
                blockModeSwitch = obj.view.handles.ShownArea.Value;
                % Ask the DATASET, not the image: the shown block is defined by
                % dataset.slices, which core.MibImage does not have - so the
                % image's own blockModeSwitch branch always errored, and ticking
                % "Shown area" threw out of the UpdateGuiWidgets listener. It
                % also resolves orient to the CURRENT orientation instead of
                % forcing YX, which is what the aspect correction below assumes.
                [height, width] = dataset.getDatasetDimensions('image', [], ...
                    struct('blockModeSwitch', blockModeSwitch));
                obj.origWidth = width;
                orientation = dataset.orientation;
                pixSize = dataset.image.pixSize;
                obj.dimsPixSize = pixSize;
                if orientation == 1     % zx: Z runs vertically
                    height = ceil(height * pixSize.z / pixSize.x);
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
            % AXESLIMITSCHANGED_CALLBACK - Update dimensions when the shown area or the voxel size changes.
            %
            % Fired by MibController.listener_updateDatasetAxes after zoom, resize and
            % fit, and also after a voxel-size change (MibRibbon.updateVoxelSizes,
            % scalebar_Callback). With the shown area the output size follows the
            % view; otherwise it is recomputed only when the voxel size differs from
            % the one the fields were computed from, so a size typed by the user is
            % not reset by every zoom.
            if ~isempty(obj.extraController); return; end
            activeId = obj.mibModel.getActiveId();
            voxelSizeChanged = ~isequal(obj.dimsPixSize, obj.mibModel.I{activeId}.image.pixSize);
            if obj.view.handles.ShownArea.Value || voxelSizeChanged
                obj.crop_Callback();
            end
        end

        function updateDestination(obj)
            % update destination for the snapshot
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.Snapshot.updateDestination: triggered\n');
            end
            if obj.view.handles.File.Value
                obj.view.handles.filePanel.Enable = true;
            else
                obj.view.handles.filePanel.Enable = false;
            end
            obj.updateBatchOptFromGUI(obj.view.handles.Destination);
        end

        function updateCropMode(obj)
            % update the crop mode for the snapshot
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.Snapshot.updateCropMode: triggered\n');
            end

            % update obj.BatchOpt
            obj.updateBatchOptFromGUI(obj.view.handles.Crop);
            % update the crop factor
            obj.crop_Callback();
        end

        function updateRoiIndex(obj)
            % updateRoiIndex - Update shown ROI selection.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.Snapshot.updateRoiIndex: triggered\n');
            end
            activeId = obj.mibModel.getActiveId();
            roiItems = obj.view.handles.RoiIndex.Items;
            roiValue = obj.view.handles.RoiIndex.Value;
            roiIdx = find(strcmp(roiItems, roiValue), 1);
            [~, indices] = obj.mibModel.I{activeId}.hROI.getNumberOfROI();
            obj.mibModel.I{activeId}.selectedROI = indices(roiIdx);
            
            eventdata = core.ToggleEventData({'roi'});
            notify(obj.mibModel, 'UpdateGuiWidgets', eventdata);
            
            notify(obj.mibModel, 'ShowImage');
            obj.crop_Callback();
        end

        function binCheck_Callback(obj)
            % update buttons bin/mag buttons
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.Snapshot.binCheck_Callback: triggered\n');
            end
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
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.Snapshot.binMagButtons_Callback(%s): triggered\n', hObject.Tag);
            end

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
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.Snapshot.FileFormat_Callback: triggered\n');
            end
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
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.Snapshot.FileFormatTabGroup_Callback: triggered\n');
            end
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
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.Snapshot.measurements_Callback: triggered\n');
            end

            obj.view.handles.measurementsOptions.Enable = obj.view.handles.Measurements.Value;
            obj.updateBatchOptFromGUI(obj.view.handles.Measurements);
        end

        function measurementsOptions_Callback(obj)
            % MEASUREMENTSOPTIONS_CALLBACK - Update measurement visualization settings.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.Snapshot.measurementsOptions_Callback: triggered\n');
            end
            activeId = obj.mibModel.getActiveId();
            obj.mibModel.I{activeId}.measure.updateOptions(obj.view.gui);
            notify(obj.mibModel, 'ShowImage');
        end

        function scalebar_Callback(obj)
            % SCALEBAR_CALLBACK - Enable scale bar and verify pixel size.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.Snapshot.scalebar_Callback: triggered\n');
            end
            if obj.view.handles.Scalebar.Value
                activeId = obj.mibModel.getActiveId();
                dataset = obj.mibModel.I{activeId};
                dlgOpts.showDialog   = true;
                dlgOpts.ParentFigure = obj.view.gui;
                dlgOpts.mibPath      = obj.mibModel.mibPath;
                dlgOpts.WindowStyle = 'modal';
                [~, newPixSize, dlgResult] = utils.updatePixSizeAndResolution([], dataset.image.pixSize, dlgOpts);
                if dlgResult
                    dataset.setPixSize(newPixSize);
                    % a new voxel size changes the aspect ratio: refresh the view, which
                    % also recomputes Width/Height via axesLimitsChanged_Callback
                    notify(obj.mibModel, 'UpdateDatasetAxes', core.ToggleEventData(struct('mode', 'resize')));
                    notify(obj.mibModel, 'ShowImage');
                end
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
                % the bounding box, not returnMask: a full-slice mask of a BigData image may not fit in memory
                roiBox = obj.mibModel.I{activeId}.hROI.getBoundingBox(roiValue);  % [xmin xmax ymin ymax]
                width = ceil(roiBox(2)) - floor(roiBox(1)) + 1;
                height = ceil(roiBox(4)) - floor(roiBox(3)) + 1;
            else
                [height, width] = obj.mibModel.I{activeId}.getDatasetDimensions('image', [], options);
            end

            obj.origWidth = width;
            orientation = obj.mibModel.I{activeId}.orientation;
            pixSize = obj.mibModel.I{activeId}.image.pixSize;
            obj.dimsPixSize = pixSize;
            if orientation == 1     % zx: Z runs vertically
                height = ceil(height * pixSize.z / pixSize.x);
            elseif orientation == 2
                width = width * pixSize.z / pixSize.y;
            elseif orientation == 3
                width = width * pixSize.x / pixSize.y;
            end
            obj.view.handles.Height.Value = height;
            obj.view.handles.Width.Value = width;
            obj.origHeight = height;
            obj.resizedWidth = width;
        end

        function SplitChannels_Callback(obj)
            % SPLITCHANNELS_CALLBACK - Enable/disable split channel controls.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.Snapshot.SplitChannels_Callback: triggered\n');
            end
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
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.Snapshot.outputDir_Callback: triggered\n');
            end
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
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.Snapshot.selectFileBtn_Callback: triggered\n');
            end
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
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.Snapshot.Width_Callback: triggered\n');
            end

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
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.Snapshot.Height_Callback: triggered\n');
            end
            newHeight = obj.view.handles.Height.Value;
            if isempty(obj.extraController)
                ratio = obj.origHeight / obj.resizedWidth;
                newWidth = round(newHeight / ratio);
                obj.view.handles.Width.Value = newWidth;
            else
                if strcmp(obj.extraController.view.gui.Name, '3D onFlyImageStretch') || strcmp(obj.extraController.view.gui.Name, '3D Controls')
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
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.Snapshot.help: triggered\n');
            end
            helpFilPath = fullfile(fileparts(obj.mibModel.mibPath), 'docs', 'html', 'user-interface', 'ribbon', 'home', 'home-makesnapshot.html');
            utils.openHelpPage(helpFilPath, ...
                'http://mib.helsinki.fi/help/main3/user-interface/ribbon/home/home-makesnapshot.html');
        end

        function snapshotBtn_Callback(obj, useBatchMode)
            % SNAPSHOTBTN_CALLBACK - Generate and save (or copy to clipboard) the snapshot image.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.snapshotBtn_Callback()
            %      obj.snapshotBtn_Callback(useBatchMode)
            %
            % Builds an RGB image from the current dataset slice using the settings
            % in ``obj.BatchOpt`` (crop mode, output dimensions, scale bar, LUT, …)
            % and either saves it to disk or copies it to the system clipboard.
            %
            % **BigData pyramid-level selection** - for BigData datasets (OME-Zarr / WSI),
            % the function selects the *finest* pyramid level whose native resolution still
            % covers the requested output size, avoiding loading the full-resolution image
            % into memory before resize:
            %
            %   - ``'ShownArea'`` - fetches at ``dataset.magFactor`` (current viewport resolution).
            %   - ``'FullImage'`` - selects the coarsest level ``L`` where
            %     ``levelScaleFactors(L) ≤ min(fullW/newW, fullH/newH)``.
            %   - ``'ROI'``       - same formula using ``obj.origWidth``/``obj.origHeight``
            %     (ROI extent in full-res pixels set by ``crop_Callback``).
            %
            % **ROI crop** - for every dataset type only the bounding box of the ROI is read:
            % it is passed to ``getRGBimage`` as ``options.x`` / ``options.y`` (full-res
            % pixels of the shown orientation, clamped to the image) with
            % ``blockModeSwitch = 0``. Reading the whole slice and cropping it afterwards ran
            % BigData BioFormats files out of Java heap, because at the default output size
            % (ROI size) the selected pyramid level is the full-resolution one.
            %
            % **Scale bar correction** - ``utils.addScaleBar`` expects
            % ``scale = newWidth / fullResWidth``.  For a downsampled pyramid level the
            % raw ``newWidth / size(img,2)`` ratio is too large, so the correct value is
            % computed from ``pyramid.levelImageSizes(1,2)`` (FullImage), ``scale / magFactor``
            % (ShownArea), or ``newWidth / obj.origWidth`` (ROI).  ZX / ZY orientations are
            % unaffected because the Z dimension is never pyramided.
            %
            % **Overlays** - measurements and ROI outlines are read once per snapshot by
            % ``collectOverlayItems`` and drawn into every panel by ``burnOverlayItems`` after
            % the crop and the resize, directly in the pixels of the output image. The region
            % passed to ``burnOverlayItems`` is expressed in full-resolution dataset pixels, so
            % pyramid levels, the shown area, ROI crops and anisotropic stretching all reduce
            % to one offset and one scale.
            %
            % Input Arguments:
            %   - **useBatchMode** *(optional)* - [logical] ``1`` = run silently (no GUI
            %     button flash), used when called from batch processing. Default: ``0``.
            %
            % **Example 1** - interactive snapshot triggered by the Snapshot button:
            %
            %   .. code-block:: matlab
            %
            %      obj.snapshotBtn_Callback();
            %
            % **Example 2** - batch-mode: save a 2048 × 2048 PNG of the full image:
            %
            %   .. code-block:: matlab
            %
            %      obj.BatchOpt.Crop{1}       = 'FullImage';
            %      obj.BatchOpt.Width{1}      = 2048;
            %      obj.BatchOpt.Height{1}     = 2048;
            %      obj.BatchOpt.FileFormat{1} = 'PNG';
            %      obj.BatchOpt.Destination{1} = 'File';
            %      obj.snapshotBtn_Callback(1);

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.Snapshot.snapshotBtn_Callback: triggered\n');
            end
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
                % read only the ROI bounding box (full-resolution pixels of the shown
                % orientation): a whole BigData slice cropped afterwards does not fit
                % in memory. blockModeSwitch must be off, otherwise getData2D replaces
                % .x/.y with the shown area
                roiBox = dataset.hROI.getBoundingBox(str2double(obj.BatchOpt.RoiIndex{1}));  % [xmin xmax ymin ymax]
                [fullHeight, fullWidth] = dataset.getDatasetDimensions('image', [], struct('blockModeSwitch', 0));
                options.x = [max(1, floor(roiBox(1))), min(fullWidth, ceil(roiBox(2)))];
                options.y = [max(1, floor(roiBox(3))), min(fullHeight, ceil(roiBox(4)))];
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

            % BigData: pick the finest pyramid level that still covers the output size.
            % Without this, getData2D defaults to magFactor=1 (full-res) and the entire
            % WSI level-0 image would be loaded before resizing to newWidth × newHeight.
            if strcmp(dataset.image.type, 'bigdata') && ~isempty(dataset.image.pyramid.levelNames)
                switch obj.BatchOpt.Crop{1}
                    case 'ShownArea'
                        % Fetch at the current display magnification - matches what the user sees
                        options.magFactor = dataset.magFactor;

                    case 'FullImage'
                        fullH = dataset.image.pyramid.levelImageSizes(1, 1);
                        fullW = dataset.image.pyramid.levelImageSizes(1, 2);
                        targetMagFactor = min(fullW / newWidth, fullH / newHeight);
                        scales = dataset.image.pyramid.levelScaleFactors(:, 1);
                        validIdx = find(scales <= targetMagFactor);
                        if isempty(validIdx)
                            options.pyramidLevel = 1;             % output larger than level 0 - use full-res
                        else
                            options.pyramidLevel = validIdx(end); % coarsest level that still covers output
                        end

                    case 'ROI'
                        % obj.origWidth / origHeight hold the ROI extent in full-res pixels (set in crop_Callback)
                        if obj.origWidth > 0 && obj.origHeight > 0
                            targetMagFactor = min(obj.origWidth / newWidth, obj.origHeight / newHeight);
                            scales = dataset.image.pyramid.levelScaleFactors(:, 1);
                            validIdx = find(scales <= targetMagFactor);
                            if isempty(validIdx)
                                options.pyramidLevel = 1;
                            else
                                options.pyramidLevel = validIdx(end);
                            end
                        end
                end
            end

            overlayItems = [];
            if isempty(obj.extraController) && (obj.BatchOpt.Measurements || obj.BatchOpt.ROIoutlines)
                overlayItems = obj.collectOverlayItems(dataset);
                % part of the dataset returned by getRGBimage, in full-resolution pixels
                if options.blockModeSwitch
                    [yMin, yMax, xMin, xMax] = dataset.getCoordinatesOfShownImage();
                    regionOrigin = [xMin yMin] - 1;
                    regionSize = [xMax - xMin + 1, yMax - yMin + 1];
                elseif strcmp(obj.BatchOpt.Crop{1}, 'ROI')
                    regionOrigin = [options.x(1) options.y(1)] - 1;
                    regionSize = [diff(options.x) + 1, diff(options.y) + 1];
                else
                    [fullHeight, fullWidth] = dataset.getDatasetDimensions('image', [], struct('blockModeSwitch', 0));
                    regionOrigin = [0 0];
                    regionSize = [fullWidth fullHeight];
                end
            end

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

                    scale = newWidth / size(img, 2);
                    if newWidth ~= size(img, 2) || newHeight ~= size(img, 1)
                        resizeMethod = obj.view.handles.ResizeMethod.Value;
                        img = imresize(img, [newHeight newWidth], resizeMethod);
                    end

                    if ~isempty(overlayItems)
                        img = obj.burnOverlayItems(img, overlayItems, regionOrigin, regionSize);
                    end

                    if obj.BatchOpt.Scalebar
                        scalebarOptions.orientation = dataset.orientation;
                        scalebarOptions.bgColor = bgColor;

                        % For BigData XY the fetched image is from a downsampled pyramid level
                        % or display-resolution viewport, so scale = newWidth/size(img,2) does
                        % not equal newWidth/fullResWidth - which is what addScaleBar requires
                        % (it computes pixelSize = pixSize.x / scale).
                        % ZX/ZY orientations are unaffected because Z is never pyramided.
                        scaleForBar = scale;
                        if strcmp(dataset.image.type, 'bigdata') && ...
                                ~isempty(dataset.image.pyramid.levelNames) && dataset.orientation == 3
                            switch obj.BatchOpt.Crop{1}
                                case 'FullImage'
                                    scaleForBar = newWidth / dataset.image.pyramid.levelImageSizes(1, 2);
                                case 'ShownArea'
                                    scaleForBar = scale / dataset.magFactor;
                                case 'ROI'
                                    if obj.origWidth > 0
                                        scaleForBar = newWidth / obj.origWidth;
                                    end
                            end
                        end

                        img = utils.addScaleBar(img, dataset.image.pixSize, scaleForBar, scalebarOptions);
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
                    try
                        imgOut = obj.extraController.grabFrame(newWidth, newHeight);
                    catch err
                        progressBar.deletePoolWaitbar();
                        if useBatchMode == 0; obj.view.handles.snapshotBtn.BackgroundColor = [0.149 0.902 0.1804]; end
                        utils.dlgs.showErrorDialog(obj.view.gui, err, 'Snapshot error', ...
                            'The snapshot was not generated', '', struct('Icon', 'puffin_warning'));
                        return;
                    end
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
                try     % fails without Java on macOS/Linux
                    imclipboard('copy', imgOut);
                catch err
                    progressBar.deletePoolWaitbar();
                    if useBatchMode == 0; obj.view.handles.snapshotBtn.BackgroundColor = [0.149 0.902 0.1804]; end
                    utils.dlgs.showErrorDialog(obj.view.gui, err, 'Snapshot error', ...
                        'The snapshot was not copied to the clipboard', '', struct('Icon', 'puffin_warning'));
                    return;
                end
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

    methods (Access = private)
        function overlayItems = collectOverlayItems(obj, dataset)
            % COLLECTOVERLAYITEMS - Read the geometry and style of the overlays selected for the snapshot.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      overlayItems = obj.collectOverlayItems(dataset)
            %
            % Calls ``RoiRegion.addROIsToPlot`` and ``Measurements.addMeasurementsToPlot`` on
            % an invisible axes that holds no image and reads back the created line and text
            % objects, so that those two methods stay the only definition of what an overlay
            % looks like (slice and time filtering, ``Options``, shapes of the measurement
            % types). ROIs follow ``dataset.selectedROI``, the same as the image view, but
            % their labels are always added: the label switch belongs to the ROI panel, which
            % is not reachable from this controller.
            %
            % Input Arguments:
            %   - **dataset** - [core.MibDataset] dataset the snapshot is made from
            %
            % Output Arguments:
            %   - **overlayItems** - [struct] in the drawing order, coordinates in full-resolution
            %     dataset pixels of the current orientation:
            %
            %     - ``.lines`` - struct array, fields ``X, Y, Color, LineStyle, LineWidth,
            %       Marker, MarkerSize, MarkerEdgeColor``
            %     - ``.texts`` - struct array, fields ``Position, String, Color,
            %       BackgroundColor, FontSize``

            hFig = figure('Visible', 'off');
            figureCleanup = onCleanup(@() delete(hFig));
            axHandle = axes(hFig);
            convertFcn = @(X, Y) deal(double(X), double(Y));
            if obj.BatchOpt.ROIoutlines
                dataset.hROI.addROIsToPlot(axHandle, 'full', dataset.orientation, convertFcn, dataset.selectedROI, true);
            end
            if obj.BatchOpt.Measurements
                dataset.measure.addMeasurementsToPlot(axHandle, 'full', dataset.orientation, convertFcn, 0);
            end

            % findobj returns the newest object first
            lineHandles = flip(findobj(axHandle, 'Type', 'line'));
            textHandles = flip(findobj(axHandle, 'Type', 'text'));
            overlayItems.lines = arrayfun(@(h) struct('X', h.XData, 'Y', h.YData, 'Color', h.Color, ...
                'LineStyle', char(h.LineStyle), 'LineWidth', h.LineWidth, 'Marker', char(h.Marker), ...
                'MarkerSize', h.MarkerSize, 'MarkerEdgeColor', h.MarkerEdgeColor), lineHandles);
            overlayItems.texts = arrayfun(@(h) struct('Position', h.Position, 'String', char(join(string(h.String))), ...
                'Color', h.Color, 'BackgroundColor', h.BackgroundColor, 'FontSize', h.FontSize), textHandles);
        end

        function img = burnOverlayItems(obj, img, overlayItems, regionOrigin, regionSize)
            % BURNOVERLAYITEMS - Draw the collected overlays directly into the pixels of an image.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      img = obj.burnOverlayItems(img, overlayItems, regionOrigin, regionSize)
            %
            % Only the pixels of the outlines change, so the cost follows the amount of drawn
            % overlay and not the size of the image. Line widths, marker and font sizes are
            % given in points; they are multiplied by ``imageWidth / 1000`` (at least 1), which
            % keeps the share of the image taken by an overlay independent of the output size.
            %
            % Input Arguments:
            %   - **img** - [RGB, unsigned integer] the cropped and resized output image
            %   - **overlayItems** - [struct] output of ``collectOverlayItems``
            %   - **regionOrigin** - [1x2 numeric] ``[x y]`` of the region shown by ``img``,
            %     number of full-resolution pixels to the left of and above it
            %   - **regionSize** - [1x2 numeric] ``[width height]`` of that region in
            %     full-resolution pixels; differs from the size of ``img`` after resizing,
            %     aspect correction or when a pyramid level was used
            %
            % Output Arguments:
            %   - **img** - the image with the overlays. Parts of an overlay outside the region
            %     are clipped.

            [imageHeight, imageWidth, ~] = size(img);
            scale = [imageWidth imageHeight] ./ regionSize;
            styleScale = max(1, imageWidth / 1000);
            maxIntensity = double(intmax(class(img)));

            for itemId = 1:numel(overlayItems.lines)
                item = overlayItems.lines(itemId);
                % pixel centers: x in the dataset is (x - origin - 0.5) * scale + 0.5 in the output
                pixelX = (item.X(:) - regionOrigin(1) - 0.5) * scale(1) + 0.5;
                pixelY = (item.Y(:) - regionOrigin(2) - 0.5) * scale(2) + 0.5;
                strokeWidth = max(1, round(item.LineWidth * styleScale));
                if ~strcmp(item.LineStyle, 'none') && isnumeric(item.Color) && numel(pixelX) > 1
                    [pathX, pathY] = obj.rasterizePolyline(pixelX, pixelY, item.LineStyle, strokeWidth);
                    [brushX, brushY] = obj.discBrush(strokeWidth);
                    img = obj.stampPixels(img, pathX, pathY, brushX, brushY, item.Color * maxIntensity);
                end

                markerColor = item.MarkerEdgeColor;
                if ~isnumeric(markerColor); markerColor = item.Color; end
                if ~strcmp(item.Marker, 'none') && isnumeric(markerColor)
                    [brushX, brushY] = obj.markerBrush(item.Marker, item.MarkerSize * styleScale, strokeWidth);
                    img = obj.stampPixels(img, round(pixelX), round(pixelY), brushX, brushY, markerColor * maxIntensity);
                end
            end

            for itemId = 1:numel(overlayItems.texts)
                item = overlayItems.texts(itemId);
                if isempty(strtrim(item.String)) || ~isnumeric(item.Color); continue; end
                fontSize = min(200, max(8, round(item.FontSize * styleScale)));
                xPos = round((item.Position(1) - regionOrigin(1) - 0.5) * scale(1) + 0.5);
                yPos = round((item.Position(2) - regionOrigin(2) - 0.5) * scale(2) + 0.5);

                % insertText returns a copy of its input, give it only the area around the label
                x1 = max(1, xPos);
                x2 = min(imageWidth, xPos + numel(item.String) * fontSize + 8);
                y1 = max(1, yPos - fontSize - 4);
                y2 = min(imageHeight, yPos + fontSize + 4);
                if x2 <= x1 || y2 <= y1; continue; end

                textOptions = {'FontSize', fontSize, 'TextColor', item.Color * maxIntensity, ...
                    'AnchorPoint', 'LeftCenter', 'BoxOpacity', 0};
                if isnumeric(item.BackgroundColor)
                    textOptions(end-1:end) = {'BoxOpacity', 1};
                    textOptions = [textOptions, {'BoxColor', item.BackgroundColor * maxIntensity}]; %#ok<AGROW>
                end
                img(y1:y2, x1:x2, :) = insertText(img(y1:y2, x1:x2, :), ...
                    [xPos - x1 + 1, yPos - y1 + 1], item.String, textOptions{:});
            end
        end

        function [pathX, pathY] = rasterizePolyline(~, X, Y, lineStyle, strokeWidth)
            % RASTERIZEPOLYLINE - Convert a polyline into a chain of integer pixel positions.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      [pathX, pathY] = obj.rasterizePolyline(X, Y, lineStyle, strokeWidth)
            %
            % Segments with a non-finite end are skipped, the same gaps as in ``plot``. Dashes
            % are measured along the whole polyline in units of the stroke width.
            %
            % Input Arguments:
            %   - **X**, **Y** - [numeric vectors] vertices in pixels of the output image
            %   - **lineStyle** - [char] ``'-'``, ``'--'``, ``':'`` or ``'-.'``
            %   - **strokeWidth** - [numeric] width of the stroke in pixels
            %
            % Output Arguments:
            %   - **pathX**, **pathY** - [column vectors] pixel positions of the drawn part

            X = X(:);
            Y = Y(:);
            segmentLength = hypot(diff(X), diff(Y));
            validSegments = find(isfinite(segmentLength));
            segmentLength(~isfinite(segmentLength)) = 0;
            travelled = [0; cumsum(segmentLength)];

            pathX = cell(numel(validSegments), 1);
            pathY = pathX;
            pathDistance = pathX;
            for pathId = 1:numel(validSegments)
                segmentId = validSegments(pathId);
                pointCount = ceil(max(abs(X(segmentId + 1) - X(segmentId)), abs(Y(segmentId + 1) - Y(segmentId)))) + 1;
                pathX{pathId} = round(linspace(X(segmentId), X(segmentId + 1), pointCount))';
                pathY{pathId} = round(linspace(Y(segmentId), Y(segmentId + 1), pointCount))';
                pathDistance{pathId} = linspace(travelled(segmentId), travelled(segmentId + 1), pointCount)';
            end
            pathX = vertcat(pathX{:});
            pathY = vertcat(pathY{:});
            pathDistance = vertcat(pathDistance{:});

            switch lineStyle
                case '--'
                    dashPattern = [6 4];
                case ':'
                    dashPattern = [1 3];
                case '-.'
                    dashPattern = [6 3 1 3];
                otherwise
                    return;
            end
            dashPattern = dashPattern * max(strokeWidth, 2);
            phase = mod(pathDistance, sum(dashPattern));
            % the number of pattern edges passed is even inside a dash and odd inside a gap
            isDrawn = mod(sum(phase >= cumsum(dashPattern), 2), 2) == 0;
            pathX = pathX(isDrawn);
            pathY = pathY(isDrawn);
        end

        function [brushX, brushY] = discBrush(~, diameter)
            % DISCBRUSH - Pixel offsets of a filled disc used as the stroke of a line.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      [brushX, brushY] = obj.discBrush(diameter)
            %
            % Input Arguments:
            %   - **diameter** - [numeric] diameter of the disc in pixels
            %
            % Output Arguments:
            %   - **brushX**, **brushY** - [column vectors] offsets from the center

            halfWidth = floor(diameter / 2);
            [brushX, brushY] = meshgrid(-halfWidth:diameter - halfWidth - 1);
            inDisc = brushX.^2 + brushY.^2 <= (diameter / 2 + 0.5)^2;
            brushX = brushX(inDisc);
            brushY = brushY(inDisc);
        end

        function [brushX, brushY] = markerBrush(obj, marker, markerSize, strokeWidth)
            % MARKERBRUSH - Pixel offsets of a marker shape drawn around its center.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      [brushX, brushY] = obj.markerBrush(marker, markerSize, strokeWidth)
            %
            % Covers every marker offered by the ROI and Measurements options. Both the short
            % and the long names are accepted, because the ``Marker`` property of a line
            % returns the long ones (``'square'`` for ``'s'``). As in ``plot``, the ``'.'``
            % marker is a filled dot a third of the marker size.
            %
            % Input Arguments:
            %   - **marker** - [char] name of the marker
            %   - **markerSize** - [numeric] size of the marker in pixels
            %   - **strokeWidth** - [numeric] width of the marker edge in pixels
            %
            % Output Arguments:
            %   - **brushX**, **brushY** - [column vectors] offsets from the center

            if strcmp(marker, '.') || strcmp(marker, 'point')
                [brushX, brushY] = obj.discBrush(max(1, round(markerSize / 3)));
                return;
            end

            % outlines at radius 1, the Y axis points down as in the image
            diagonal = sqrt(0.5);
            circleAngles = linspace(0, 2*pi, 33);
            plusShape = {[-1 1; 0 0], [0 0; -1 1]};
            crossShape = {diagonal*[-1 1; -1 1], diagonal*[-1 1; 1 -1]};
            starRadius = @(tips, innerRadius) [repmat([1 innerRadius], 1, tips) 1];
            starAngles = @(tips) linspace(-pi/2, 3*pi/2, 2*tips + 1);
            switch marker
                case 'o'
                    shapes = {[cos(circleAngles); sin(circleAngles)]};
                case '+'
                    shapes = plusShape;
                case 'x'
                    shapes = crossShape;
                case '*'
                    shapes = [plusShape, crossShape];
                case {'s', 'square'}
                    shapes = {[-1 1 1 -1 -1; -1 -1 1 1 -1]};
                case {'d', 'diamond'}
                    shapes = {[0 0.7 0 -0.7 0; -1 0 1 0 -1]};
                case '^'
                    shapes = {[0 1 -1 0; -1 1 1 -1]};
                case 'v'
                    shapes = {[0 1 -1 0; 1 -1 -1 1]};
                case '>'
                    shapes = {[1 -1 -1 1; 0 1 -1 0]};
                case '<'
                    shapes = {[-1 1 1 -1; 0 1 -1 0]};
                case {'p', 'pentagram'}
                    shapes = {starRadius(5, 0.38) .* [cos(starAngles(5)); sin(starAngles(5))]};
                case {'h', 'hexagram'}
                    shapes = {starRadius(6, 0.58) .* [cos(starAngles(6)); sin(starAngles(6))]};
                otherwise
                    shapes = {};
            end

            markerRadius = max(1, markerSize / 2);
            [strokeX, strokeY] = obj.discBrush(strokeWidth);
            offsets = zeros(0, 2);
            for shapeId = 1:numel(shapes)
                [pathX, pathY] = obj.rasterizePolyline(shapes{shapeId}(1, :) * markerRadius, ...
                    shapes{shapeId}(2, :) * markerRadius, '-', 1);
                offsets = [offsets; reshape(pathX + strokeX', [], 1), reshape(pathY + strokeY', [], 1)]; %#ok<AGROW>
            end
            offsets = unique(offsets, 'rows');
            brushX = offsets(:, 1);
            brushY = offsets(:, 2);
        end

        function img = stampPixels(~, img, centerX, centerY, brushX, brushY, color)
            % STAMPPIXELS - Paint a brush at a list of positions, clipped to the image.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      img = obj.stampPixels(img, centerX, centerY, brushX, brushY, color)
            %
            % Input Arguments:
            %   - **img** - [RGB, unsigned integer] image to paint on
            %   - **centerX**, **centerY** - [numeric column vectors] integer positions in the
            %     image, may lie outside of it or be NaN
            %   - **brushX**, **brushY** - [numeric column vectors] pixel offsets of the brush
            %   - **color** - [1x3 numeric] color in the intensity range of ``img``
            %
            % Output Arguments:
            %   - **img** - the painted image

            [imageHeight, imageWidth, colorChannels] = size(img);
            margin = max(abs([brushX; brushY]));
            nearImage = centerX >= 1 - margin & centerX <= imageWidth + margin & ...
                centerY >= 1 - margin & centerY <= imageHeight + margin;
            centers = unique([centerX(nearImage), centerY(nearImage)], 'rows');
            if isempty(centers); return; end

            stampX = reshape(centers(:, 1) + brushX', [], 1);
            stampY = reshape(centers(:, 2) + brushY', [], 1);
            inside = stampX >= 1 & stampX <= imageWidth & stampY >= 1 & stampY <= imageHeight;
            pixelIds = unique(sub2ind([imageHeight imageWidth], stampY(inside), stampX(inside)));
            for channelId = 1:colorChannels
                img(pixelIds + (channelId - 1) * imageHeight * imageWidth) = color(channelId);
            end
        end
    end
end
