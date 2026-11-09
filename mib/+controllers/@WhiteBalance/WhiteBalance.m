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
        bigDataOptions
        % controllers.BigDataOptions - BigData_* BatchOpt fields, the BigData output panel and the BigData run
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

            % BigData: the result goes to a new store (BigData_* fields, ignored otherwise)
            obj.bigDataOptions = controllers.BigDataOptions(obj, 'whitebalance');
            obj.BatchOpt = obj.bigDataOptions.addBatchOptFields(obj.BatchOpt);

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
            utils.applyThemeColors(obj.view.gui);   % adapt the standard dialog button colors to the light/dark theme
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
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.WhiteBalance.closeWindow: triggered\n');
            end
            if isvalid(obj.view.gui); delete(obj.view.gui); end
            for i = 1:numel(obj.listener); delete(obj.listener{i}); end
            notify(obj, 'CloseEvent');
        end

        % ---------------------------------------------------------------
        function figureKeyPress(obj, event)
            % FIGUREKEYPRESS - Forward key presses to MIB main window shortcuts.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.WhiteBalance.figureKeyPress: triggered\n');
            end
            if isempty(event.Character); return; end

            eventData = struct();
            eventData.eventdata = event;
            eventData = core.ToggleEventData(eventData);
            notify(obj.mibModel, 'KeyPressEvent', eventData);
        end

        % -----------------------------------------------------------
        function updateWidgets(obj)
            % UPDATEWIDGETS - Refresh widgets to reflect current model state.
            %
            % On a BigData dataset only the manual white value is offered (the
            % picked region and Detect read whole slices), the whole dataset is
            % corrected (no Correct current), and the BigData output panel is
            % shown; the widgets are enabled again for other datasets.
            obj.BatchOpt.id = obj.mibModel.getActiveId();
            isBigData = strcmp(obj.mibModel.I{obj.BatchOpt.id}.datasetType, 'BigData');
            if isBigData; obj.BatchOpt.PickedRegion{1} = 'ManualValue'; end
            utils.updateGUIFromBatchOpt_Shared(obj.view, obj.BatchOpt);
            if isempty(obj.view) || ~isvalid(obj.view.gui); return; end
            handles = obj.view.handles;
            for widgetName = {'SelectedAreas', 'MaskedAreas', 'detectButton', 'correctCurrentButton'}
                handles.(widgetName{1}).Enable = ~isBigData;
            end
            handles.ManualWhiteColor.Enable = strcmp(obj.BatchOpt.PickedRegion{1}, 'ManualValue');
            obj.bigDataOptions.updateWidgets();
        end

        % -----------------------------------------------------------
        function updateBatchOptFromGUI(obj, event)
            % UPDATEBATCHOPTFROMGUI - Sync BatchOpt from a widget change event.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.WhiteBalance.updateBatchOptFromGUI(%s): triggered\n', event.Source.Tag);
            end
            obj.BatchOpt = utils.updateBatchOptFromGUI_Shared(obj.BatchOpt, event.Source);
        end

        % -----------------------------------------------------------
        function manualWhiteColorValueChanged(obj, event)
            % MANUALWHITECOLORVALUECHANGED - Validate that ManualWhiteColor contains 3 numeric values.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.WhiteBalance.manualWhiteColorValueChanged: triggered\n');
            end
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
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.WhiteBalance.pickedRegionSelectionChanged: triggered\n');
            end
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
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.WhiteBalance.helpButton_Callback: triggered\n');
            end
            helpFilPath = fullfile(fileparts(obj.mibModel.mibPath), 'docs', 'html', 'user-interface', 'ribbon', 'image', 'image-tools-whitebalance.html');
            utils.openHelpPage(helpFilPath, ...
                'http://mib.helsinki.fi/help/main3/user-interface/ribbon/image/image-tools-whitebalance.html');
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
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.WhiteBalance.detectWhiteFromLayer: triggered\n');
            end
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
            %   **mode** *(optional)* - ``'Correct current'`` processes current slice only;
            %   ``'Correct all'`` (default) processes the whole stack.
            %   **batchModeSwitch** *(optional)* - ``true`` when called from batch processing;
            %   skips undo backup. Default: ``false``.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.WhiteBalance.correctWhiteBalance: triggered\n');
            end
            if nargin < 2; mode = 'Correct all'; end
            if nargin < 3; batchModeSwitch = false; end

            obj.BatchOpt.id = obj.mibModel.getActiveId();
            id = obj.BatchOpt.id;
            dataset = obj.mibModel.I{id};
            colors = dataset.image.colors;

            if strcmp(dataset.datasetType, 'BigData')     % read-only image: corrected into a new store
                obj.correctBigData_(mode, batchModeSwitch);
                return;
            end

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

            if strcmp(dataset.datasetType, 'Virtual')
                if obj.BatchOpt.showWaitbar; delete(progressBar); end
                dlgOpt.MsgBoxOnly = true;
                dlgOpt.Icon = 'puffin_warning';
                utils.dlgs.inputUniversalDlg(obj.mibModel.getProgressBarParent(), '', {''}, ...
                    {sprintf('This plugin is not compatible with the virtual mode!\nPlease switch to the memory-resident mode and try again')}, ...
                    'Not implemented', dlgOpt);
                notify(obj.mibModel, 'StopProtocol');
                if ~isempty(obj.view); obj.closeWindow(); end   % batch mode has no window
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

            % count user's points
            obj.mibModel.preferences.Users.Tiers.numberOfContrastAdjustments = obj.mibModel.preferences.Users.Tiers.numberOfContrastAdjustments + 1;
            notify(obj.mibModel, 'UpdateUserScore', core.ToggleEventData(2));    % scale scoring by factor 2

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

    methods (Access = private)
        function correctBigData_(obj, mode, batchModeSwitch)
            % CORRECTBIGDATA_ - White balance of a BigData image into a new OME-Zarr store.
            %
            % ``chromadapt`` with the white of ``ManualWhiteColor`` maps every pixel
            % on its own (to linear RGB, a 3 x 3 adaptation matrix, back), so the
            % level ``BigData_PyramidLevel`` is corrected in bands of rows without a
            % halo and equals the Standard correction of the whole slices. The
            % result goes to a new store, opened as ``BigData_OpenIn`` says
            % (``controllers.BigDataOptions.run``).
            %
            % Refused, with a dialog or raised as ``controllers:WhiteBalance:bigData``
            % when headless: an image without 3 channels; *SelectedAreas* /
            % *MaskedAreas* (the white of every slice would need the image under
            % the selection or mask, read band-aligned with the model - not done
            % yet); *Correct current*, because a new store holds the whole dataset.
            %
            % Input Arguments:
            %   - **mode** - ``'Correct all'`` or ``'Correct current'``
            %   - **batchModeSwitch** - ``true`` from a batch protocol: no BatchOpt hand-over
            BatchOpt = obj.BatchOpt;
            dataset = obj.mibModel.I{BatchOpt.id};
            parentFigure = obj.mibModel.mibGUI;     % [] headless: errors are raised
            if ~isempty(obj.view) && isvalid(obj.view.gui); parentFigure = obj.view.gui; end
            errorId = 'controllers:WhiteBalance:bigData';
            title = 'BigData white balance';
            if dataset.image.colors ~= 3
                controllers.BigDataOptions.reportError(obj.mibModel, parentFigure, errorId, ...
                    'White balance correction is only available for 3 color-channel RGB images!', title);
                return;
            end
            if ~strcmp(BatchOpt.PickedRegion{1}, 'ManualValue')
                controllers.BigDataOptions.reportError(obj.mibModel, parentFigure, errorId, sprintf(['On BigData ' ...
                    'datasets the white is given as a manual value; "%s" is not available.\nPoint at an area that ' ...
                    'should be white or gray to read its intensities, and enter them as the manual white value.'], ...
                    BatchOpt.PickedRegion{1}), title);
                return;
            end
            whiteColor = str2num(BatchOpt.ManualWhiteColor); %#ok<ST2NM> entered as text
            if numel(whiteColor) ~= 3
                controllers.BigDataOptions.reportError(obj.mibModel, parentFigure, errorId, ...
                    'Please provide 3 values that describe intensity in an area that should be white or gray!', title);
                return;
            end
            if strcmp(mode, 'Correct current')
                controllers.BigDataOptions.reportError(obj.mibModel, parentFigure, errorId, ...
                    'On BigData datasets the whole dataset is corrected into a new store; please use Correct all.', title);
                return;
            end

            colorSpace = BatchOpt.ColorSpace{1};
            method = BatchOpt.ChromaticAdaptationMethod{1};
            blockFunction = @(block) chromadapt(block, whiteColor, 'ColorSpace', colorSpace, 'Method', method);
            try
                result = obj.bigDataOptions.run(BatchOpt, blockFunction, ...
                    Fingerprint = jsonencode(struct('white', whiteColor, 'colorSpace', colorSpace, 'method', method)));
            catch err
                controllers.BigDataOptions.reportError(obj.mibModel, parentFigure, errorId, ...
                    sprintf('White balance correction of the BigData dataset failed:\n%s', err.message), title);
                return;
            end
            if isempty(result)      % cancelled; nothing is left on disk
                notify(obj.mibModel, 'StopProtocol');
                return;
            end

            obj.bigDataOptions.reportStoreResult(result, sprintf('WB correction: %g %g %g, %s, %s; level %s -> %s', ...
                whiteColor, colorSpace, method, BatchOpt.BigData_PyramidLevel{1}, result.outputPath));
            obj.mibModel.preferences.Users.Tiers.numberOfContrastAdjustments = obj.mibModel.preferences.Users.Tiers.numberOfContrastAdjustments + 1;
            notify(obj.mibModel, 'UpdateUserScore', core.ToggleEventData(2));
            if ~batchModeSwitch; obj.returnBatchOpt(); end
        end
    end
end
