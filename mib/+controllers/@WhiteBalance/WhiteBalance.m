classdef WhiteBalance < handle
% WHITEBALANCE - Controller for the White Balance correction dialog.
%
% Corrects white balance of RGB images using MATLAB's ``chromadapt`` function.
% The white point can be detected from selection/mask areas, or specified manually.
%
% Launch as GUI tool::
%
%   obj.mibController.startController('controllers.WhiteBalance');
%
% Launch in batch mode::
%
%   BatchOpt.PickedRegion = {'ManualValue'};
%   BatchOpt.ManualWhiteColor = '200 190 180';
%   obj.mibController.startController('controllers.WhiteBalance', [], BatchOpt);
%
% Trigger return of possible options::
%
%   obj.mibController.startController('controllers.WhiteBalance', [], NaN);
%

    properties
        mibModel
        % handle to MibModel
        view
        % handle to the view (views.WhiteBalanceGUI)
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
        function obj = WhiteBalance(mibModel, varargin)
            % WHITEBALANCE - Constructor.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj = WhiteBalance(mibModel)
            %       obj = WhiteBalance(mibModel, [], BatchOpt)
            %
            obj.mibModel = mibModel;
            obj.mibGUI   = mibModel.mibGUI;

            obj.BatchOpt.PickedRegion{1} = 'SelectedAreas';
            obj.BatchOpt.PickedRegion{2} = {'SelectedAreas', 'MaskedAreas', 'ManualValue'};
            obj.BatchOpt.ManualWhiteColor = '128 128 128';
            obj.BatchOpt.ColorSpace    = {'sRGB'};
            obj.BatchOpt.ColorSpace{2} = {'sRGB', 'Adobe-RGB-1998', 'linear-RGB'};
            obj.BatchOpt.ChromaticAdaptationMethod    = {'bradford'};
            obj.BatchOpt.ChromaticAdaptationMethod{2} = {'bradford', 'vonkries', 'simple'};
            obj.BatchOpt.showWaitbar = true;
            obj.BatchOpt.id = obj.mibModel.getActiveId();

            obj.BatchOpt.mibBatchSectionName = 'Ribbon -> Image';
            obj.BatchOpt.mibBatchActionName  = 'Tools for Images -> White balance correction';
            obj.BatchOpt.mibBatchTooltip.PickedRegion              = 'Layers containing areas that should be white or gray';
            obj.BatchOpt.mibBatchTooltip.ManualWhiteColor          = 'Provide 3 values that describe intensity in an area that should be white or gray';
            obj.BatchOpt.mibBatchTooltip.ColorSpace                = 'Color space of the image';
            obj.BatchOpt.mibBatchTooltip.ChromaticAdaptationMethod = 'Chromatic adaptation method used to scale the RGB values';
            obj.BatchOpt.mibBatchTooltip.showWaitbar               = 'Show or not the progress bar during execution';

            %% Batch / headless mode
            if nargin == 3
                BatchOptIn = varargin{2};
                if ~isstruct(BatchOptIn)
                    if isnan(BatchOptIn)
                        obj.returnBatchOpt();
                    else
                        utils.dlgs.showErrorDialog([], 'A structure as the 3rd parameter is required!', 'Error');
                    end
                    notify(obj, 'CloseEvent');
                    return;
                end
                obj.BatchOpt = utils.updateBatchOptCombineFields_Shared(obj.BatchOpt, BatchOptIn);
                obj.correctWhiteBalance('Correct all', true);
                notify(obj, 'CloseEvent');
                return;
            end

            %% GUI mode
            obj.view = core.ChildView(obj, 'views.WhiteBalanceGUI');
            obj.view.gui = utils.moveWindowOutside(obj.view.gui, obj.mibGUI, 'left');
            utils.fontSizeUpdate(obj.view.gui, obj.mibModel.preferences.System.Font);

            obj.updateWidgets();
            utils.updateGUIFromBatchOpt_Shared(obj.view, obj.BatchOpt);
            obj.addCallbacks();
            obj.view.gui.Visible = 'on';

            obj.listener{1} = addlistener(obj.mibModel, 'UpdateGuiWidgets', @(src,evnt) obj.ViewListner_Callback2(obj, src, evnt));
            obj.listener{2} = addlistener(obj.mibModel, 'NewDataset',       @(src,evnt) obj.ViewListner_Callback2(obj, src, evnt));
        end

        % -----------------------------------------------------------
        function addCallbacks(obj)
            % ADDCALLBACKS - Wire all widget callbacks after view creation.
            obj.view.gui.CloseRequestFcn                              = @(~,~) obj.closeWindow();
            obj.view.handles.PickedRegion.SelectionChangedFcn         = @(h,e) obj.pickedRegionSelectionChanged(e);
            obj.view.handles.ManualWhiteColor.ValueChangedFcn         = @(h,e) obj.manualWhiteColorValueChanged(e);
            obj.view.handles.ColorSpace.ValueChangedFcn               = @(h,e) obj.updateBatchOptFromGUI(e);
            obj.view.handles.ChromaticAdaptationMethod.ValueChangedFcn = @(h,e) obj.updateBatchOptFromGUI(e);
            obj.view.handles.correctAllButton.ButtonPushedFcn         = @(~,~) obj.correctWhiteBalance('Correct all');
            obj.view.handles.correctCurrentButton.ButtonPushedFcn     = @(~,~) obj.correctWhiteBalance('Correct current');
            obj.view.handles.detectButton.ButtonPushedFcn             = @(~,~) obj.detectWhiteFromLayer();
            obj.view.handles.helpButton.ButtonPushedFcn               = @(~,~) obj.helpButton_Callback();
            obj.view.handles.closeButton.ButtonPushedFcn              = @(~,~) obj.closeWindow();
            obj.view.gui.KeyPressFcn = @(~,e) obj.figureKeyPress(e);
        end

        % -----------------------------------------------------------
        function closeWindow(obj)
            % CLOSEWINDOW - Destroy view and fire CloseEvent.
            if isvalid(obj.view.gui); delete(obj.view.gui); end
            for i = 1:numel(obj.listener); delete(obj.listener{i}); end
            notify(obj, 'CloseEvent');
        end

        % ---------------------------------------------------------------
        function figureKeyPress(obj, event)
            % FIGUREKEYPRESS - Forward key presses to MIB main window shortcuts.
            if isempty(event.Character); return; end

            eventData = struct();
            eventData.eventdata = event;
            eventData = core.ToggleEventData(eventData);
            notify(obj.mibModel, 'KeyPressEvent', eventData);
        end

        % -----------------------------------------------------------
        function updateWidgets(obj)
            % UPDATEWIDGETS - Refresh widgets to reflect current model state.
            obj.BatchOpt.id = obj.mibModel.getActiveId();
            utils.updateGUIFromBatchOpt_Shared(obj.view, obj.BatchOpt);
        end

        % -----------------------------------------------------------
        function updateBatchOptFromGUI(obj, event)
            % UPDATEBATCHOPTFROMGUI - Sync BatchOpt from a widget change event.
            obj.BatchOpt = utils.updateBatchOptFromGUI_Shared(obj.BatchOpt, event.Source);
        end

        % -----------------------------------------------------------
        function manualWhiteColorValueChanged(obj, event)
            % MANUALWHITECOLORVALUECHANGED - Validate that ManualWhiteColor contains 3 numeric values.
            value = obj.view.handles.ManualWhiteColor.Value;
            parsedValues = str2num(value); %#ok<ST2NM>
            if numel(parsedValues) ~= 3
                utils.dlgs.showErrorDialog(obj.mibModel.getProgressBarParent(), ...
                    'Please provide 3 values that describe intensity in an area that should be white or gray!', ...
                    'Wrong value');
                obj.view.handles.ManualWhiteColor.Value = event.PreviousValue;
                return;
            end
            obj.updateBatchOptFromGUI(event);
        end

        % -----------------------------------------------------------
        function pickedRegionSelectionChanged(obj, event)
            % PICKEDREGIONSELECTIONCHANGED - Update BatchOpt and toggle ManualWhiteColor enable state.
            obj.BatchOpt = utils.updateBatchOptFromGUI_Shared(obj.BatchOpt, event.Source);
            if strcmp(event.Source.SelectedObject.Tag, 'ManualValue')
                obj.view.handles.ManualWhiteColor.Enable = 'on';
            else
                obj.view.handles.ManualWhiteColor.Enable = 'off';
            end
        end

        % -----------------------------------------------------------
        function helpButton_Callback(obj)
            % HELPBUTTON_CALLBACK - Open documentation in browser.
            web(fullfile(obj.mibModel.mibPath, 'techdoc', 'html', 'user-interface', 'menu', 'image', 'image-tools-whitebalance.html'), '-browser');
        end

        % -----------------------------------------------------------
        function returnBatchOpt(obj, BatchOptOut)
            % RETURNBATCHOPT - Send BatchOpt to mibBatchController.
            if nargin < 2; BatchOptOut = obj.BatchOpt; end
            if isfield(BatchOptOut, 'id'); BatchOptOut = rmfield(BatchOptOut, 'id'); end
            notify(obj.mibModel, 'SyncBatch', core.ToggleEventData(BatchOptOut));
        end

        % -----------------------------------------------------------
        function detectWhiteFromLayer(obj)
            % DETECTWHITEFROMLAYER - Sample mean RGB from current mask/selection layer
            % and populate ManualWhiteColor; switch PickedRegion to ManualValue.
            id = obj.BatchOpt.id;
            dataset = obj.mibModel.I{id};

            if dataset.image.colors ~= 3
                utils.dlgs.showErrorDialog(obj.mibModel.getProgressBarParent(), ...
                    'White point detection requires a 3 color-channel RGB image!', ...
                    'Wrong number of color channels');
                return;
            end

            layerType = 'selection';
            z = dataset.getCurrentSliceNumber();
            getDataOptions.id = id;

            maskData = cell2mat(obj.mibModel.getData2D(layerType, z, [], [], getDataOptions));
            if ~any(maskData(:))
                utils.dlgs.showErrorDialog(obj.mibModel.getProgressBarParent(), ...
                    sprintf('No pixels found in the %s layer on the current slice', layerType), ...
                    'Empty layer');
                return;
            end

            imageData = cell2mat(obj.mibModel.getData2D('image', z, [], [], getDataOptions));
            whiteColors = zeros(1, 3);
            for colCh = 1:3
                channelData = imageData(:,:,colCh);
                whiteColors(colCh) = mean(double(channelData(maskData == 1)));
            end

            obj.BatchOpt.ManualWhiteColor = sprintf('%d %d %d', round(whiteColors));
            obj.BatchOpt.PickedRegion{1} = 'ManualValue';
            utils.updateGUIFromBatchOpt_Shared(obj.view, obj.BatchOpt);
            obj.view.handles.ManualWhiteColor.Enable = 'on';
        end

        % -----------------------------------------------------------
        function correctWhiteBalance(obj, mode, batchModeSwitch)
            % CORRECTWHITEBALANCE - Apply white balance correction to the image.
            %
            % Parameters:
            % **mode** *(optional)* — ``'Correct current'`` processes current slice only;
            %   ``'Correct all'`` (default) processes the whole stack.
            % **batchModeSwitch** *(optional)* — ``true`` when called from batch processing;
            %   skips undo backup. Default: ``false``.
            if nargin < 2; mode = 'Correct all'; end
            if nargin < 3; batchModeSwitch = false; end

            id = obj.BatchOpt.id;
            dataset = obj.mibModel.I{id};
            colors = dataset.image.colors;

            if colors ~= 3
                utils.dlgs.showErrorDialog(obj.mibModel.getProgressBarParent(), ...
                    'White balance correction is only available for 3 color-channel RGB images!', ...
                    'Wrong number of color channels');
                return;
            end

            manualWhiteColors = str2num(obj.BatchOpt.ManualWhiteColor); %#ok<ST2NM>
            if numel(manualWhiteColors) ~= 3 && strcmp(obj.BatchOpt.PickedRegion{1}, 'ManualValue')
                utils.dlgs.showErrorDialog(obj.mibModel.getProgressBarParent(), ...
                    'Please provide 3 values that describe intensity in an area that should be white or gray!', ...
                    'Wrong value');
                return;
            end

            if obj.BatchOpt.showWaitbar
                progressBar = uiprogressdlg(obj.mibModel.getProgressBarParent(), 'Value', 0, 'Cancelable', 'on', ...
                    'Message', 'Please wait...', 'Title', 'White balance correction');
            end

            if any(dataset.datasetType(1) == ['V' 'B'])
                if obj.BatchOpt.showWaitbar; delete(progressBar); end
                dlgOpt.MsgBoxOnly = true;
                dlgOpt.Icon = 'puffin_warning';
                utils.dlgs.inputUniversalDlg(obj.mibModel.getProgressBarParent(), '', {''}, ...
                    {sprintf('This plugin is not compatible with the virtual or BigData mode!\nPlease switch to the memory-resident mode and try again')}, ...
                    'Not implemented', dlgOpt);
                notify(obj.mibModel, 'StopProtocol');
                obj.closeWindow();
                return;
            end

            currentMode = strcmp(mode, 'Correct current');

            getDataOptions.id = id;
            if ~batchModeSwitch
                if currentMode
                    obj.mibModel.backup('image', 0, getDataOptions);
                else
                    obj.mibModel.backup('image', 1, getDataOptions);
                end
            end

            [~, ~, depth] = dataset.getDatasetDimensions('image');
            progressBarStep = floor(depth/20);

            if currentMode
                z1 = dataset.getCurrentSliceNumber();
                z2 = z1;
            else
                z1 = 1;
                z2 = depth;
            end

            if strcmp(obj.BatchOpt.PickedRegion{1}, 'MaskedAreas')
                maskLayer = 'mask';
            else
                maskLayer = 'selection';
            end

            detectedWhiteColors = [];
            for z = z1:z2
                if obj.BatchOpt.showWaitbar && mod(z, progressBarStep) == 0
                    if progressBar.CancelRequested
                        delete(progressBar);
                        return;
                    end
                    progressBar.Value   = z / depth;
                    progressBar.Message = sprintf('White balance correction, slice %d of %d\nPlease wait...', z, depth);
                end

                imageData = cell2mat(obj.mibModel.getData2D('image', z, [], [], getDataOptions));
                if strcmp(obj.BatchOpt.PickedRegion{1}, 'ManualValue')
                    imageData = chromadapt(imageData, manualWhiteColors, ...
                        'ColorSpace', obj.BatchOpt.ColorSpace{1}, ...
                        'Method',     obj.BatchOpt.ChromaticAdaptationMethod{1});
                else
                    maskData = cell2mat(obj.mibModel.getData2D(maskLayer, z, [], [], getDataOptions));
                    if sum(maskData(:)) > 0
                        detectedWhiteColors = zeros(3, 1);
                        for colCh = 1:colors
                            channelData = imageData(:,:,colCh);
                            detectedWhiteColors(colCh) = mean(double(channelData(maskData == 1)));
                        end
                    elseif isempty(detectedWhiteColors)
                        continue;
                    end
                    imageData = chromadapt(imageData, detectedWhiteColors, ...
                        'ColorSpace', obj.BatchOpt.ColorSpace{1}, ...
                        'Method',     obj.BatchOpt.ChromaticAdaptationMethod{1});
                end
                obj.mibModel.setData2D(imageData, 'image', z, [], [], getDataOptions);
            end
            if obj.BatchOpt.showWaitbar; delete(progressBar); end

            if ~strcmp(obj.BatchOpt.PickedRegion{1}, 'ManualValue') && ~isempty(detectedWhiteColors)
                obj.BatchOpt.ManualWhiteColor = sprintf('%d %d %d', round(detectedWhiteColors));
                if ~isempty(obj.view) && isvalid(obj.view.gui)
                    obj.view.handles.ManualWhiteColor.Value  = obj.BatchOpt.ManualWhiteColor;
                    obj.view.handles.ManualWhiteColor.Enable = 'on';
                end
            end

            obj.mibModel.showMask = true;
            notify(obj.mibModel, 'ShowImage');

            if ~currentMode
                if strcmp(obj.BatchOpt.PickedRegion{1}, 'ManualValue')
                    dataset.image.updateActionLog(sprintf('WB correction: %d %d %d, %s, %s', ...
                        manualWhiteColors(1), manualWhiteColors(2), manualWhiteColors(3), ...
                        obj.BatchOpt.ColorSpace{1}, obj.BatchOpt.ChromaticAdaptationMethod{1}));
                else
                    dataset.image.updateActionLog(sprintf('WB correction using %s layer, detected white: %d %d %d, %s, %s', ...
                        maskLayer, round(detectedWhiteColors(1)), round(detectedWhiteColors(2)), round(detectedWhiteColors(3)), ...
                        obj.BatchOpt.ColorSpace{1}, obj.BatchOpt.ChromaticAdaptationMethod{1}));
                end
                obj.returnBatchOpt();
            end
        end

    end
end
