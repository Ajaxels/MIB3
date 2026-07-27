classdef ImageFrame < handle
% IMAGEFRAME - Controller for the Select Image Frame dialog.
%
% Detects border regions of an image (connected components with a specified
% intensity value that touch the image edges) and writes them to the
% Selection, Mask, or Image layer.
%
% Launch as GUI tool::
%
%   obj.mibController.startController('controllers.ImageFrame');
%
% Launch in batch mode::
%
%   BatchOpt.DatasetType    = {'3D, Stack'};
%   BatchOpt.FrameIntensity = {0, [0 Inf], 'on'};
%   BatchOpt.Destination    = {'Selection'};
%   BatchOpt.showWaitbar    = false;
%   obj.mibController.startController('controllers.ImageFrame', [], BatchOpt);
%
% Trigger return of possible options::
%
%   obj.mibController.startController('controllers.ImageFrame', [], NaN);
%

    properties
        mibModel
        % handle to MibModel
        view
        % handle to the view (views.ImageFrameGUI)
        mibGUI
        % handle to main MIB figure (used as parent for dialogs)
        listener
        % cell array of listener handles
        BatchOpt
        % structure compatible with batch processing; field names match widget Tags
    end

    events
        CloseEvent
        % fired when the window is closed
    end

    methods (Static)
        function ViewListner_Callback2(obj, ~, evnt)
            % VIEWLISTNER_CALLBACK2 - Static listener guard; safe even when view is invalid.
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
        % -----------------------------------------------------------
        function obj = ImageFrame(mibModel, varargin)
            % IMAGEFRAME - Constructor.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj = ImageFrame(mibModel)
            %       obj = ImageFrame(mibModel, [], BatchOpt)
            %
            obj.mibModel = mibModel;
            obj.mibGUI   = mibModel.mibGUI;

            id      = obj.mibModel.getActiveId();
            nColors = obj.mibModel.I{id}.image.colors;

            obj.BatchOpt.DatasetType{1} = '3D, Stack';
            obj.BatchOpt.DatasetType{2} = {'2D, Slice', '3D, Stack', '4D, Dataset'};
            obj.BatchOpt.ColorChannel{1} = 'ColCh 1';
            obj.BatchOpt.ColorChannel{2} = arrayfun(@(x) sprintf('ColCh %d', x), 1:nColors, 'UniformOutput', false);
            obj.BatchOpt.Connectivity{1} = 'connection4';
            obj.BatchOpt.Connectivity{2} = {'connection4', 'connection8'};
            obj.BatchOpt.FrameIntensity    = {0, [0 Inf], 'on'};
            obj.BatchOpt.MinimalObjectSize = {0, [0 Inf], 'on'};
            obj.BatchOpt.NewFrameIntensity = {0, [0 Inf], 'on'};
            obj.BatchOpt.Destination{1} = 'Selection';
            obj.BatchOpt.Destination{2} = {'Selection', 'Mask', 'Image'};
            obj.BatchOpt.showWaitbar = true;
            obj.BatchOpt.id = id;

            obj.BatchOpt.mibBatchSectionName = 'Ribbon -> Image';
            obj.BatchOpt.mibBatchActionName  = 'Tools for Images -> Select Image Frame';
            obj.BatchOpt.mibBatchTooltip.DatasetType       = 'Define type of the dataset for detection of the frame';
            obj.BatchOpt.mibBatchTooltip.ColorChannel      = 'Select a color channel to use';
            obj.BatchOpt.mibBatchTooltip.Connectivity      = 'Define connectivity parameter for detection of objects';
            obj.BatchOpt.mibBatchTooltip.FrameIntensity    = 'Intensity of the image frame to be detected';
            obj.BatchOpt.mibBatchTooltip.MinimalObjectSize = 'Objects below this area are ignored';
            obj.BatchOpt.mibBatchTooltip.NewFrameIntensity = 'New intensity value for the detected frame (Image destination only)';
            obj.BatchOpt.mibBatchTooltip.Destination       = 'Destination layer for results';
            obj.BatchOpt.mibBatchTooltip.showWaitbar       = 'Show or not the progress bar during execution';

            %% Batch / headless mode
            if nargin == 3
                BatchOptIn = varargin{2};
                if ~isstruct(BatchOptIn)
                    if isnan(BatchOptIn)
                        obj.returnBatchOpt();
                    else
                        utils.dlgs.showErrorDialog([], 'A structure as the 3rd parameter is required!', 'BatchOpt Error');
                    end
                    notify(obj, 'CloseEvent');
                    return;
                end
                obj.BatchOpt = utils.updateBatchOptCombineFields_Shared(obj.BatchOpt, BatchOptIn);
                obj.Calculate(true);
                notify(obj, 'CloseEvent');
                return;
            end

            %% Virtual mode guard
            if any(obj.mibModel.I{id}.datasetType(1) == ['V' 'B'])
                dlgOpt.MsgBoxOnly = true;
                dlgOpt.Icon = 'puffin_warning';
                utils.dlgs.inputUniversalDlg(obj.mibModel.getProgressBarParent(), '', {''}, ...
                    {'This tool is not available in virtual or BigData mode.\nPlease switch to the memory-resident mode and try again.'}, ...
                    'Not implemented', dlgOpt);
                notify(obj, 'CloseEvent');
                return;
            end

            %% GUI mode
            obj.view = core.ChildView(obj, 'views.ImageFrameGUI');
            obj.view.gui = utils.moveWindowOutside(obj.view.gui, obj.mibGUI, 'left');

            Font = obj.mibModel.preferences.System.Font;
            if obj.view.handles.continueButton.FontSize ~= Font.FontSize || ...
                    ~strcmp(obj.view.handles.continueButton.FontName, Font.FontName)
                utils.fontSizeUpdate(obj.view.gui, Font);
            end

            % % Load preview image
            % previewFilename = fullfile(obj.mibModel.mibPath, 'Resources', 'image_border_detection.png');
            % if isfile(previewFilename)
            %     [previewImg, ~, transparency] = imread(previewFilename);
            %     image(obj.view.handles.previewAxes, previewImg, 'AlphaData', double(transparency)/255);
            %     obj.view.handles.previewAxes.Box    = 'off';
            %     obj.view.handles.previewAxes.XTick  = [];
            %     obj.view.handles.previewAxes.YTick  = [];
            %     obj.view.handles.previewAxes.XColor = 'none';
            %     obj.view.handles.previewAxes.YColor = 'none';
            %     obj.view.handles.previewAxes.Color  = 'none';
            % end

            obj.view.handles.infoText.Text = 'This tool allows selection of borders at the edge of the dataset';

            obj.updateWidgets();
            obj.addCallbacks();
            obj.view.gui.Visible = 'on';

            obj.listener{1} = addlistener(obj.mibModel, 'UpdateGuiWidgets', @(s,e) obj.ViewListner_Callback2(obj, s, e));
            obj.listener{2} = addlistener(obj.mibModel, 'NewDataset',       @(s,e) obj.ViewListner_Callback2(obj, s, e));
        end

        % -----------------------------------------------------------
        function addCallbacks(obj)
            % ADDCALLBACKS - Wire all widget callbacks after view creation.
            obj.view.gui.CloseRequestFcn = @(~,~) obj.closeWindow();
            obj.view.handles.DatasetType.ValueChangedFcn       = @(h,e) obj.updateBatchOptFromGUI(e);
            obj.view.handles.ColorChannel.ValueChangedFcn      = @(h,e) obj.updateBatchOptFromGUI(e);
            obj.view.handles.Connectivity.SelectionChangedFcn  = @(h,e) obj.updateBatchOptFromGUI(e);
            obj.view.handles.FrameIntensity.ValueChangedFcn    = @(h,e) obj.updateBatchOptFromGUI(e);
            obj.view.handles.NewFrameIntensity.ValueChangedFcn = @(h,e) obj.updateBatchOptFromGUI(e);
            obj.view.handles.MinimalObjectSize.ValueChangedFcn = @(h,e) obj.updateBatchOptFromGUI(e);
            obj.view.handles.Destination.SelectionChangedFcn   = @(h,e) obj.destinationChanged(e);
            obj.view.handles.continueButton.ButtonPushedFcn    = @(~,~) obj.Calculate();
            obj.view.handles.helpButton.ButtonPushedFcn        = @(~,~) obj.helpButton_Callback();
            obj.view.handles.closeButton.ButtonPushedFcn       = @(~,~) obj.closeWindow();
            obj.view.gui.KeyPressFcn = @(~,e) obj.figureKeyPress(e);
        end

        % -----------------------------------------------------------
        function figureKeyPress(obj, event)
            % FIGUREKEYPRESS - Forward key presses to MIB main window shortcuts.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.ImageFrame.figureKeyPress: triggered\n');
            end
            if isempty(event.Character); return; end
            eventData = struct();
            eventData.eventdata = event;
            eventData = core.ToggleEventData(eventData);
            notify(obj.mibModel, 'KeyPressEvent', eventData);
        end

        % -----------------------------------------------------------
        function closeWindow(obj)
            % CLOSEWINDOW - Destroy view and fire CloseEvent.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.ImageFrame.closeWindow: triggered\n');
            end
            if isvalid(obj.view.gui); delete(obj.view.gui); end
            for i = 1:numel(obj.listener); delete(obj.listener{i}); end
            notify(obj, 'CloseEvent');
        end

        % -----------------------------------------------------------
        function updateWidgets(obj)
            % UPDATEWIDGETS - Refresh widgets to reflect current model state.
            id = obj.mibModel.getActiveId();
            obj.BatchOpt.id = id;

            nColors   = obj.mibModel.I{id}.image.colors;
            colorList = arrayfun(@(x) sprintf('ColCh %d', x), 1:nColors, 'UniformOutput', false);
            if ~ismember(obj.BatchOpt.ColorChannel{1}, colorList)
                obj.BatchOpt.ColorChannel{1} = colorList{1};
            end
            obj.BatchOpt.ColorChannel{2} = colorList;

            utils.updateGUIFromBatchOpt_Shared(obj.view, obj.BatchOpt);

            % NewFrameIntensity is only relevant when writing to Image
            if strcmp(obj.BatchOpt.Destination{1}, 'Image')
                obj.view.handles.NewFrameIntensity.Enable = 'on';
            else
                obj.view.handles.NewFrameIntensity.Enable = 'off';
            end
        end

        % -----------------------------------------------------------
        function updateBatchOptFromGUI(obj, event)
            % UPDATEBATCHOPTFROMGUI - Sync BatchOpt from a widget change event.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.ImageFrame.updateBatchOptFromGUI(%s): triggered\n', event.Source.Tag);
            end
            obj.BatchOpt = utils.updateBatchOptFromGUI_Shared(obj.BatchOpt, event.Source);
        end

        % -----------------------------------------------------------
        function destinationChanged(obj, event)
            % DESTINATIONCHANGED - Update BatchOpt and toggle NewFrameIntensity field.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.ImageFrame.destinationChanged: triggered\n');
            end
            obj.BatchOpt = utils.updateBatchOptFromGUI_Shared(obj.BatchOpt, event.Source);
            if strcmp(obj.BatchOpt.Destination{1}, 'Image')
                obj.view.handles.NewFrameIntensity.Enable = 'on';
            else
                obj.view.handles.NewFrameIntensity.Enable = 'off';
            end
        end

        % -----------------------------------------------------------
        function helpButton_Callback(obj)
            % HELPBUTTON_CALLBACK - Open documentation in browser.

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.ImageFrame.helpButton_Callback: triggered\n');
            end
            helpFilPath = fullfile(fileparts(obj.mibModel.mibPath), 'docs', 'site', 'user-interface', 'ribbon', 'image', 'image-tools-selectframe.html');
            if isfile(helpFilPath)
                web(helpFilPath, '-browser');
            else
                web('http://mib.helsinki.fi/help/main3/user-interface/ribbon/image/image-tools-selectframe.html', '-browser');
            end

        end

        % -----------------------------------------------------------
        function returnBatchOpt(obj, BatchOptOut)
            % RETURNBATCHOPT - Send BatchOpt to mibBatchController.
            if nargin < 2; BatchOptOut = obj.BatchOpt; end
            if isfield(BatchOptOut, 'id'); BatchOptOut = rmfield(BatchOptOut, 'id'); end
            notify(obj.mibModel, 'SyncBatch', core.ToggleEventData(BatchOptOut));
        end

        % -----------------------------------------------------------
        function Calculate(obj, batchModeSwitch)
            % CALCULATE - Detect and mark image frame border pixels.
            %
            % Parameters:
            %   **batchModeSwitch** *(optional)* — ``true`` when called from batch processing;
            %     skips undo backup and ``returnBatchOpt``. Default: ``false``.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.ImageFrame.Calculate: triggered\n');
            end
            if nargin < 2; batchModeSwitch = false; end

            id = obj.BatchOpt.id;

            % define parent window
            if isempty(obj.view)   % headless batch mode
                parentFigure = obj.mibModel.mibGUI;
            else
                parentFigure = obj.view.gui;
            end

            if obj.BatchOpt.showWaitbar
                progressBar = uiprogressdlg(parentFigure, 'Value', 0, 'Cancelable', 'on', ...
                    'Message', 'Please wait...', 'Title', 'Frame selection');
            end

            datasetType       = obj.BatchOpt.DatasetType{1};
            colCh             = find(ismember(obj.BatchOpt.ColorChannel{2}, obj.BatchOpt.ColorChannel{1}), 1);
            connectivity      = str2double(obj.BatchOpt.Connectivity{1}(end));
            destination       = lower(obj.BatchOpt.Destination{1});
            frameIntensity    = obj.BatchOpt.FrameIntensity{1};
            newFrameIntensity = obj.BatchOpt.NewFrameIntensity{1};
            objectThreshold   = obj.BatchOpt.MinimalObjectSize{1};

            height = obj.mibModel.I{id}.image.height;
            width  = obj.mibModel.I{id}.image.width;
            depth  = obj.mibModel.I{id}.image.depth;

            getDataOptions.blockModeSwitch = 0;
            getDataOptions.id = id;

            % Backup current data (skip in batch mode; skip 4D — too expensive)
            if ~batchModeSwitch
                switch datasetType
                    case '2D, Slice'; obj.mibModel.backup(destination, 0, getDataOptions);
                    case '3D, Stack'; obj.mibModel.backup(destination, 1, getDataOptions);
                end
            end

            % Determine slice/time range
            switch datasetType
                case '2D, Slice'
                    t1 = obj.mibModel.I{id}.slices{5}(1);
                    t2 = t1;
                    startSlice = obj.mibModel.I{id}.getCurrentSliceNumber();
                    endSlice   = startSlice;
                    maxIndex   = 1;
                case '3D, Stack'
                    t1 = obj.mibModel.I{id}.slices{5}(1);
                    t2 = t1;
                    startSlice = 1;
                    endSlice   = depth;
                    maxIndex   = depth;
                case '4D, Dataset'
                    t1 = 1;
                    t2 = obj.mibModel.I{id}.image.time;
                    startSlice = 1;
                    endSlice   = depth;
                    maxIndex   = depth * t2;
            end

            index = 0;
            for t = t1:t2
                getDataOptions.t = [t t];
                for z = startSlice:endSlice
                    if obj.BatchOpt.showWaitbar && mod(index, 10) == 0
                        if progressBar.CancelRequested
                            delete(progressBar);
                            return;
                        end
                        if maxIndex > 0; progressBar.Value = index / maxIndex; end
                    end

                    imageSlice = cell2mat(obj.mibModel.getData2D('image', z, [], colCh, getDataOptions));

                    binaryMask = zeros(size(imageSlice), 'uint8');
                    binaryMask(imageSlice == frameIntensity) = 1;

                    CC    = bwconncomp(binaryMask, connectivity);
                    STATS = regionprops(CC, 'PixelList', 'Area');

                    if isempty(STATS)
                        index = index + 1;
                        continue;
                    end

                    % Filter objects below the minimum area threshold
                    keepVec         = arrayfun(@(x) x.Area > objectThreshold, STATS);
                    CC.PixelIdxList = CC.PixelIdxList(keepVec);
                    CC.NumObjects   = sum(keepVec);
                    STATS           = STATS(keepVec);

                    if isempty(STATS)
                        index = index + 1;
                        continue;
                    end

                    % Find objects touching any image border
                    % PixelList columns: [col(x), row(y)]
                    notTouchLeft   = arrayfun(@(x) isempty(find(x.PixelList == 1, 1)), STATS);
                    notTouchBottom = arrayfun(@(x) isempty(find(x.PixelList(:,2) == height, 1)), STATS);
                    notTouchRight  = arrayfun(@(x) isempty(find(x.PixelList(:,1) == width,  1)), STATS);
                    borderVec = unique([find(~notTouchLeft); find(~notTouchBottom); find(~notTouchRight)]);

                    if ~isempty(borderVec)
                        pixelIdx = cat(1, CC.PixelIdxList{borderVec});
                        if strcmp(destination, 'image')
                            imageSlice(pixelIdx) = newFrameIntensity;
                            obj.mibModel.setData2D(imageSlice, destination, z, [], colCh, getDataOptions);
                        else
                            resultMask = zeros(size(imageSlice), 'uint8');
                            resultMask(pixelIdx) = 1;
                            obj.mibModel.setData2D(resultMask, destination, z, [], [], getDataOptions);
                        end
                    end
                    index = index + 1;
                end
            end

            % Update action log (image destination only)
            if strcmp(destination, 'image')
                logText = sprintf('ImageFrame: ColCh=%d, orient=%d, NewInt=%d', ...
                    colCh, obj.mibModel.I{id}.orientation, newFrameIntensity);
                if strcmp(datasetType, '2D, Slice')
                    logText = [logText sprintf(', 2D, Z=%d, T=%d', startSlice, t1)];
                elseif strcmp(datasetType, '3D, Stack')
                    logText = [logText sprintf(', 3D, T=%d', t1)];
                else
                    logText = [logText ', 4D'];
                end
                obj.mibModel.I{id}.image.updateActionLog(logText);
            elseif strcmp(destination, 'mask')
                obj.mibModel.showMask = true;
            end

            if obj.BatchOpt.showWaitbar; delete(progressBar); end
            notify(obj.mibModel, 'ShowImage');

            if ~batchModeSwitch; obj.returnBatchOpt(); end
        end

    end
end
