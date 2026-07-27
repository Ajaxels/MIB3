classdef GlobalThresholding < handle
% GLOBALTHRESHOLDING - Controller for automatic black-and-white thresholding.
%
% Applies one of 12 histogram-based thresholding algorithms (Otsu, Entropy,
% Concavity, Percentile, …) to the selected color channel of the image layer
% and writes the binary result to the selection or mask layer.
%
% Launch as GUI tool::
%
%   obj.mibController.startController('controllers.GlobalThresholding');
%
% Launch in batch mode::
%
%   BatchOpt.Algorithm   = {'Otsu'};
%   BatchOpt.Mode        = {'3D, Stack'};
%   BatchOpt.Destination = {'mask'};
%   obj.mibController.startController('controllers.GlobalThresholding', [], BatchOpt);
%
% Trigger return of default options::
%
%   obj.mibController.startController('controllers.GlobalThresholding', [], NaN);
%

    properties
        mibModel
        % handle to MibModel
        view
        % handle to the view (views.GlobalThresholdingGUI)
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
            % VIEWLISTNER_CALLBACK2 - Static listener guard; safe even after close.
            if ~isvalid(obj) || isempty(obj.view) || ~isvalid(obj.view.gui)
                for i = 1:numel(obj.listener); delete(obj.listener{i}); end
                return;
            end
            switch evnt.EventName
                case {'UpdateGuiWidgets', 'NewDataset'}
                    obj.updateWidgets();
                case 'SliceChanged'
                    if obj.view.handles.autoPreviewCheck.Value
                        obj.previewBtn_Callback();
                    end
            end
        end
    end

    methods
        % -----------------------------------------------------------
        function obj = GlobalThresholding(mibModel, varargin)
            % GLOBALTHRESHOLDING - Constructor.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj = GlobalThresholding(mibModel)
            %       obj = GlobalThresholding(mibModel, [], BatchOpt)
            %       obj = GlobalThresholding(mibModel, [], NaN)
            %
            obj.mibModel = mibModel;
            obj.mibGUI   = mibModel.mibGUI;

            id = obj.mibModel.getActiveId();
            colorCount = obj.mibModel.I{id}.image.colors;
            colorChannelList = arrayfun(@(x) sprintf('Ch %d', x), 1:colorCount, 'UniformOutput', false);

            %% Initialize BatchOpt
            obj.BatchOpt.id = id;

            obj.BatchOpt.Algorithm    = {'Concavity'};
            obj.BatchOpt.Algorithm{2} = {'Concavity','Entropy','InterMeans iter','InterModes',...
                'Mean','Median','MinError','MinError iter','Minimum','Moments','Otsu','Percentile'};
            obj.BatchOpt.Mode    = {'2D, Slice'};
            obj.BatchOpt.Mode{2} = {'2D, Slice','3D, Stack','4D, Dataset'};
            obj.BatchOpt.ColorChannel    = {colorChannelList{max(1, obj.mibModel.I{id}.selectedColorChannel)}};
            obj.BatchOpt.ColorChannel{2} = colorChannelList;
            obj.BatchOpt.Destination    = {'selection'};
            obj.BatchOpt.Destination{2} = {'selection','mask'};
            obj.BatchOpt.ForegroundFraction = {0.5, [0 1], 'off'};
            obj.BatchOpt.ThresholdOffset = {0, [-Inf Inf], 'on'};
            obj.BatchOpt.showWaitbar = true;

            obj.BatchOpt.mibBatchSectionName = 'Ribbon -> Tools';
            obj.BatchOpt.mibBatchActionName  = 'Global thresholding';

            obj.BatchOpt.mibBatchTooltip.Algorithm          = 'Selection of available methods for thresholding';
            obj.BatchOpt.mibBatchTooltip.Mode               = 'Apply thresholding for the current slice (2D), current stack (3D) or the whole dataset (4D)';
            obj.BatchOpt.mibBatchTooltip.ColorChannel       = 'Color channel to be used for thresholding';
            obj.BatchOpt.mibBatchTooltip.Destination        = 'Assign thresholding results to the Mask or Selection layer of MIB';
            obj.BatchOpt.mibBatchTooltip.ForegroundFraction = '[Percentile only]: fraction of foreground pixels (0–1)';
            obj.BatchOpt.mibBatchTooltip.ThresholdOffset    = 'Offset added to the calculated threshold (positive = raise threshold, negative = lower it)';
            obj.BatchOpt.mibBatchTooltip.showWaitbar        = 'Show or not the progress bar during execution';

            %% Batch / headless mode
            if numel(varargin) >= 2
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
                obj.applyButton_Callback(true);
                notify(obj, 'CloseEvent');
                return;
            end

            %% Virtual mode guard
            if any(obj.mibModel.I{id}.datasetType(1) == ['V' 'B'])
                dlgOpt.MsgBoxOnly = true;
                dlgOpt.Icon = 'puffin_warning';
                utils.dlgs.inputUniversalDlg(obj.mibModel.getProgressBarParent(), '', {''}, ...
                    {sprintf('Global thresholding is not available in virtual or BigData mode.\nPlease switch to the memory-resident mode and try again.')}, ...
                    'Not implemented', dlgOpt);
                notify(obj, 'CloseEvent');
                return;
            end

            %% GUI mode
            obj.view = core.ChildView(obj, 'views.GlobalThresholdingGUI');
            obj.view.gui = utils.moveWindowOutside(obj.view.gui, obj.mibGUI, 'left');

            Font = obj.mibModel.preferences.System.Font;
            if obj.view.handles.applyBtn.FontSize ~= Font.FontSize || ...
                    ~strcmp(obj.view.handles.applyBtn.FontName, Font.FontName)
                utils.fontSizeUpdate(obj.view.gui, Font);
            end

            obj.addCallbacks();
            obj.updateWidgets();
            obj.view.gui.Visible = 'on';

            obj.listener{1} = addlistener(obj.mibModel, 'UpdateGuiWidgets', @(s,e) obj.ViewListner_Callback2(obj, s, e));
            obj.listener{2} = addlistener(obj.mibModel, 'NewDataset',       @(s,e) obj.ViewListner_Callback2(obj, s, e));
            obj.listener{3} = addlistener(obj.mibModel, 'SliceChanged',     @(s,e) obj.ViewListner_Callback2(obj, s, e));
        end

        % -----------------------------------------------------------
        function addCallbacks(obj)
            % ADDCALLBACKS - Wire all widget callbacks after view creation.
            obj.view.gui.CloseRequestFcn = @(~,~) obj.closeWindow();
            handles = obj.view.handles;
            handles.Algorithm.ValueChangedFcn          = @(~,e) obj.algorithmChanged(e);
            handles.Mode.ValueChangedFcn               = @(~,e) obj.updateBatchOptFromGUI(e);
            handles.ColorChannel.ValueChangedFcn       = @(~,e) obj.updateBatchOptFromGUI(e);
            handles.Destination.ValueChangedFcn        = @(~,e) obj.updateBatchOptFromGUI(e);
            handles.ForegroundFraction.ValueChangedFcn  = @(~,e) obj.foregroundFractionChanged(e);
            handles.foregroundSlider.ValueChangedFcn    = @(~,e) obj.foregroundSliderChanged(e);
            handles.ThresholdOffset.ValueChangedFcn     = @(~,e) obj.thresholdOffsetChanged(e);
            handles.offsetSlider.ValueChangedFcn        = @(~,e) obj.offsetSliderChanged(e);
            handles.autoPreviewCheck.ValueChangedFcn   = @(~,e) obj.autoPreviewChanged(e);
            handles.previewBtn.ButtonPushedFcn         = @(~,~) obj.previewBtn_Callback();
            handles.resetBtn.ButtonPushedFcn           = @(~,~) obj.resetSliders_Callback();
            handles.applyBtn.ButtonPushedFcn           = @(~,~) obj.applyButton_Callback();
            handles.closeBtn.ButtonPushedFcn           = @(~,~) obj.closeWindow();
            handles.helpBtn.ButtonPushedFcn            = @(~,~) obj.helpButton_Callback();
            obj.view.gui.KeyPressFcn                   = @(~,e) obj.figureKeyPress(e);
        end

        % -----------------------------------------------------------
        function figureKeyPress(obj, event)
            % FIGUREKEYPRESS - Forward key presses to MIB main window shortcuts.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.GlobalThresholding.figureKeyPress: triggered\n');
            end
            if isempty(event.Character); return; end
            eventData = struct();
            eventData.eventdata = event;
            eventData = core.ToggleEventData(eventData);
            notify(obj.mibModel, 'KeyPressEvent', eventData);
        end

        % -----------------------------------------------------------
        function closeWindow(obj)
            % CLOSEWINDOW - Destroy view, listeners, fire CloseEvent.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.GlobalThresholding.closeWindow: triggered\n');
            end
            if ~isempty(obj.view) && isvalid(obj.view.gui); delete(obj.view.gui); end
            for i = 1:numel(obj.listener); delete(obj.listener{i}); end
            notify(obj, 'CloseEvent');
        end

        % -----------------------------------------------------------
        function returnBatchOpt(obj, BatchOptOut)
            % RETURNBATCHOPT - Send BatchOpt to mibBatchController.
            if nargin < 2; BatchOptOut = obj.BatchOpt; end
            if isfield(BatchOptOut, 'id'); BatchOptOut = rmfield(BatchOptOut, 'id'); end
            notify(obj.mibModel, 'SyncBatch', core.ToggleEventData(BatchOptOut));
        end

        % -----------------------------------------------------------
        function updateBatchOptFromGUI(obj, event)
            % UPDATEBATCHOPTFROMGUI - Sync BatchOpt from a widget change event.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.GlobalThresholding.updateBatchOptFromGUI(%s): triggered\n', event.Source.Tag);
            end
            obj.BatchOpt = utils.updateBatchOptFromGUI_Shared(obj.BatchOpt, event.Source);
            obj.triggerAutoPreview();
        end

        % -----------------------------------------------------------
        function algorithmChanged(obj, event)
            % ALGORITHMCHANGED - Handle Algorithm dropdown change.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.GlobalThresholding.algorithmChanged: triggered\n');
            end
            obj.BatchOpt.Algorithm{1} = event.Source.Value;
            obj.applyUIRules();
            obj.triggerAutoPreview();
        end

        % -----------------------------------------------------------
        function foregroundFractionChanged(obj, event)
            % FOREGROUNDFRACTIONCHANGED - Handle ForegroundFraction spinner change; sync slider.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.GlobalThresholding.foregroundFractionChanged: triggered\n');
            end
            obj.BatchOpt = utils.updateBatchOptFromGUI_Shared(obj.BatchOpt, event.Source);
            obj.view.handles.foregroundSlider.Value = obj.BatchOpt.ForegroundFraction{1};
            obj.triggerAutoPreview();
        end

        % -----------------------------------------------------------
        function foregroundSliderChanged(obj, event)
            % FOREGROUNDSLIDERCHANGED - Handle foregroundSlider change; sync spinner.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.GlobalThresholding.foregroundSliderChanged: triggered\n');
            end
            newValue = event.Source.Value;
            obj.BatchOpt.ForegroundFraction{1} = newValue;
            obj.view.handles.ForegroundFraction.Value = newValue;
            obj.triggerAutoPreview();
        end

        % -----------------------------------------------------------
        function thresholdOffsetChanged(obj, event)
            % THRESHOLDOFFSETCHANGED - Handle ThresholdOffset spinner change; sync slider.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.GlobalThresholding.thresholdOffsetChanged: triggered\n');
            end
            obj.BatchOpt = utils.updateBatchOptFromGUI_Shared(obj.BatchOpt, event.Source);
            obj.view.handles.offsetSlider.Value = max(-256, min(256, obj.BatchOpt.ThresholdOffset{1}));
            obj.triggerAutoPreview();
        end

        % -----------------------------------------------------------
        function offsetSliderChanged(obj, event)
            % OFFSETSLIDERCHANGED - Handle offsetSlider change; sync spinner.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.GlobalThresholding.offsetSliderChanged: triggered\n');
            end
            newValue = event.Source.Value;
            obj.BatchOpt.ThresholdOffset{1} = newValue;
            obj.view.handles.ThresholdOffset.Value = newValue;
            obj.triggerAutoPreview();
        end

        % -----------------------------------------------------------
        function resetSliders_Callback(obj)
            % RESETSLIDERS_CALLBACK - Reset ForegroundFraction to 0.5 and ThresholdOffset to 0.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.GlobalThresholding.resetSliders_Callback: triggered\n');
            end
            obj.BatchOpt.ForegroundFraction{1} = 0.5;
            obj.view.handles.ForegroundFraction.Value = 0.5;
            obj.view.handles.foregroundSlider.Value   = 0.5;

            obj.BatchOpt.ThresholdOffset{1} = 0;
            obj.view.handles.ThresholdOffset.Value = 0;
            obj.view.handles.offsetSlider.Value    = 0;

            obj.triggerAutoPreview();
        end

        % -----------------------------------------------------------
        function autoPreviewChanged(obj, event)
            % AUTOPREVIEWCHANGED - Handle autoPreview checkbox; fire preview if just checked.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.GlobalThresholding.autoPreviewChanged: triggered\n');
            end
            if event.Source.Value
                obj.previewBtn_Callback();
            end
        end

        % -----------------------------------------------------------
        function triggerAutoPreview(obj)
            % TRIGGERAUTPREVIEW - Fire preview when autoPreview checkbox is on.
            if isempty(obj.view) || ~isvalid(obj.view.gui); return; end
            if obj.view.handles.autoPreviewCheck.Value
                obj.previewBtn_Callback();
            end
        end

        % -----------------------------------------------------------
        function applyUIRules(obj)
            % APPLYUIRULES - Enable/disable Percentile controls and update info text.
            if isempty(obj.view) || ~isvalid(obj.view.gui); return; end
            isPercentile = strcmp(obj.BatchOpt.Algorithm{1}, 'Percentile');
            obj.view.handles.ForegroundFraction.Enable = isPercentile;
            obj.view.handles.foregroundSlider.Enable   = isPercentile;
            obj.view.handles.infoText.Text = obj.getInfoText();
        end

        % -----------------------------------------------------------
        function infoText = getInfoText(obj)
            % GETINFOTEXT - Return description for the currently selected algorithm.
            switch obj.BatchOpt.Algorithm{1}
                case 'Concavity'
                    infoText = 'Concavity: for images that do not have distinct objects and background';
                case 'Entropy'
                    infoText = 'Entropy: divides the histogram into two probability distributions, one for objects and one for background';
                case 'InterMeans iter'
                    infoText = 'InterMeans iter: find a global threshold using the iterative intermeans method';
                case 'InterModes'
                    infoText = 'InterModes: assumes a bimodal histogram; unsuitable for images with extremely unequal peaks or a broad, flat valley';
                case 'MaxLik'
                    infoText = 'MaxLik: expectation-maximization approach for fitting mixtures of distributions';
                case 'Mean'
                    infoText = 'Mean: does not take into account histogram shape';
                case 'Median'
                    infoText = 'Median: assumes that the percentage of object pixels is known';
                case 'MinError'
                    infoText = 'MinError: views the histogram as an estimate of the probability density function of the mixture population';
                case 'MinError iter'
                    infoText = 'MinError iter: find a global threshold using the iterative minimum error thresholding method';
                case 'Minimum'
                    infoText = 'Minimum: assumes a bimodal histogram; unsuitable for images with extremely unequal peaks or a broad, flat valley';
                case 'Moments'
                    infoText = 'Moments: moment-preserving thresholding';
                case 'Otsu'
                    infoText = 'Otsu: positions the threshold midway between the means of the two classes';
                case 'Percentile'
                    infoText = 'Percentile: assumes that the percentage of object pixels is known (set via Foreground Fraction)';
                otherwise
                    infoText = '';
            end
        end

        % -----------------------------------------------------------
        function updateWidgets(obj)
            % UPDATEWIDGETS - Refresh widgets to reflect current model state.
            id = obj.mibModel.getActiveId();
            obj.BatchOpt.id = id;

            colorCount = obj.mibModel.I{id}.image.colors;
            colorChannelList = arrayfun(@(x) sprintf('Ch %d', x), 1:colorCount, 'UniformOutput', false);
            obj.BatchOpt.ColorChannel{2} = colorChannelList;
            if ~ismember(obj.BatchOpt.ColorChannel{1}, colorChannelList)
                selectedCh = max(1, obj.mibModel.I{id}.selectedColorChannel);
                obj.BatchOpt.ColorChannel{1} = colorChannelList{min(selectedCh, colorCount)};
            end

            utils.updateGUIFromBatchOpt_Shared(obj.view, obj.BatchOpt);
            obj.view.handles.foregroundSlider.Value = obj.BatchOpt.ForegroundFraction{1};
            maxVal = obj.mibModel.I{id}.image.maxInt;
            obj.view.handles.offsetSlider.Value = obj.BatchOpt.ThresholdOffset{1};
            obj.view.handles.offsetSlider.Limits = [-maxVal maxVal];
            obj.applyUIRules();
        end

        % -----------------------------------------------------------
        function threshold = computeThreshold(obj, img, algorithm, foregroundFraction, maxInt)
            % COMPUTETHRESHOLD - Apply the selected thresholding algorithm to img.
            %
            % Input Arguments:
            %   - **img** — [uint8 | uint16] single-channel 2-D image
            %   - **algorithm** — [char] algorithm name from BatchOpt.Algorithm{1}
            %   - **foregroundFraction** — [double] fraction for Percentile algorithm
            %   - **maxInt** — [double] maximum intensity for the image data type
            %
            % Output Arguments:
            %   - **threshold** — [double] raw intensity threshold value
            %
            switch algorithm
                case 'Concavity';       threshold = th_concavity(img);
                case 'Entropy';         threshold = th_entropy(img);
                case 'InterMeans iter'; threshold = th_intermeans_iter(img);
                case 'InterModes';      threshold = th_intermodes(img);
                case 'MaxLik';          threshold = th_maxlik(img);
                case 'Mean';            threshold = th_mean(img);
                case 'Median';          threshold = th_median(img);
                case 'MinError';        threshold = th_minerror(img);
                case 'MinError iter';   threshold = th_minerror_iter(img);
                case 'Minimum';         threshold = th_minimum(img);
                case 'Moments';         threshold = th_moments(img);
                case 'Otsu'
                    threshold = graythresh(img) * maxInt;
                case 'Percentile'
                    threshold = th_ptile(img, 1 - foregroundFraction);
                otherwise
                    threshold = 0;
            end
        end

        % -----------------------------------------------------------
        function previewBtn_Callback(obj)
            % PREVIEWBTN_CALLBACK - Apply thresholding to the current slice and show in selection.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.GlobalThresholding.previewBtn_Callback: triggered\n');
            end
            id = obj.BatchOpt.id;
            colChId = find(ismember(obj.BatchOpt.ColorChannel{2}, obj.BatchOpt.ColorChannel{1}), 1);

            getDataOptions.id = id;
            img = cell2mat(obj.mibModel.getData2D('image', [], [], colChId, getDataOptions));

            maxInt = obj.mibModel.I{id}.image.maxInt;

            % Non-Otsu methods are optimised for 8-bit; convert if needed
            if maxInt > 255 && ~strcmp(obj.BatchOpt.Algorithm{1}, 'Otsu')
                maxPixel = max(img(:));
                if maxPixel > 0
                    img = uint8(double(img) / double(maxPixel) * 255);
                else
                    img = uint8(img);
                end
                maxInt = 255;
            end

            threshold = obj.computeThreshold(img, obj.BatchOpt.Algorithm{1}, ...
                obj.BatchOpt.ForegroundFraction{1}, maxInt) + obj.BatchOpt.ThresholdOffset{1};

            imgOut = uint8(img > threshold);
            obj.mibModel.setData2D(imgOut, 'selection', [], [], NaN, getDataOptions);
            notify(obj.mibModel, 'ShowImage');
        end

        % -----------------------------------------------------------
        function applyButton_Callback(obj, batchModeSwitch)
            % APPLYBUTTON_CALLBACK - Perform thresholding on the selected scope.
            %
            % Input Arguments:
            %   - **batchModeSwitch** *(optional)* — logical; ``true`` when called
            %     headlessly from the batch dispatcher. Default ``false``.
            %
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.GlobalThresholding.applyButton_Callback: triggered\n');
            end
            if nargin < 2; batchModeSwitch = false; end

            if isempty(obj.view)
                parentFig = obj.mibGUI;
            else
                parentFig = obj.view.gui;
            end

            BatchOptLoc = obj.BatchOpt;
            id = BatchOptLoc.id;

            colChId = find(ismember(BatchOptLoc.ColorChannel{2}, BatchOptLoc.ColorChannel{1}), 1);
            maxInt  = obj.mibModel.I{id}.image.maxInt;

            %% Resolve z / t ranges and perform backup
            [~, ~, depthCount] = obj.mibModel.I{id}.getDatasetDimensions('image', 3);

            switch BatchOptLoc.Mode{1}
                case '2D, Slice'
                    tRange = repmat(obj.mibModel.I{id}.slices{5}(1), 1, 2);
                    zRange = repmat(obj.mibModel.I{id}.getCurrentSliceNumber(), 1, 2);
                    if isfield(BatchOptLoc, 't'); tRange = BatchOptLoc.t; end
                    if isfield(BatchOptLoc, 'z'); zRange = BatchOptLoc.z; end
                    if ~batchModeSwitch
                        obj.mibModel.backup(BatchOptLoc.Destination{1}, 0, BatchOptLoc);
                    end

                case '3D, Stack'
                    tRange = repmat(obj.mibModel.I{id}.slices{5}(1), 1, 2);
                    zRange = [1, depthCount];
                    if isfield(BatchOptLoc, 't'); tRange = BatchOptLoc.t; end
                    if isfield(BatchOptLoc, 'z'); zRange = BatchOptLoc.z; end
                    if ~batchModeSwitch
                        obj.mibModel.backup(BatchOptLoc.Destination{1}, 1, BatchOptLoc);
                    end

                case '4D, Dataset'
                    tRange = [1, obj.mibModel.I{id}.image.time];
                    zRange = [1, depthCount];
                    if isfield(BatchOptLoc, 't'); tRange = BatchOptLoc.t; end
                    if isfield(BatchOptLoc, 'z'); zRange = BatchOptLoc.z; end
                    if ~batchModeSwitch && tRange(1) == tRange(2)
                        obj.mibModel.backup(BatchOptLoc.Destination{1}, 1, BatchOptLoc);
                    end
            end

            %% Progress dialog
            maxIndex = (diff(zRange) + 1) * (diff(tRange) + 1);
            waitbarMessage = sprintf('%s thresholding\nPlease wait...', BatchOptLoc.Algorithm{1});
            if BatchOptLoc.showWaitbar
                progressBar = core.PoolWaitbar(maxIndex, waitbarMessage, parentFig, ...
                    [BatchOptLoc.Algorithm{1} ' thresholding'], true);
            end

            %% Build optional spatial options
            getDataOptions.id = id;
            if isfield(BatchOptLoc, 'x'); getDataOptions.x = BatchOptLoc.x; end
            if isfield(BatchOptLoc, 'y'); getDataOptions.y = BatchOptLoc.y; end

            fgFraction  = BatchOptLoc.ForegroundFraction{1};
            thOffset    = BatchOptLoc.ThresholdOffset{1};

            %% Main processing loop
            for timePoint = tRange(1):tRange(2)
                getDataOptions.t = [timePoint, timePoint];
                for sliceId = zRange(1):zRange(2)
                    if BatchOptLoc.showWaitbar && progressBar.getCancelState()
                        progressBar.deletePoolWaitbar();
                        notify(obj.mibModel, 'StopProtocol');
                        notify(obj.mibModel, 'ShowImage');
                        return;
                    end

                    img = cell2mat(obj.mibModel.getData2D('image', sliceId, 3, colChId, getDataOptions));

                    localMaxInt = maxInt;
                    if localMaxInt > 255 && ~strcmp(BatchOptLoc.Algorithm{1}, 'Otsu')
                        maxPixel = max(img(:));
                        if maxPixel > 0
                            img = uint8(double(img) / double(maxPixel) * 255);
                        else
                            img = uint8(img);
                        end
                        localMaxInt = 255;
                    end

                    threshold = obj.computeThreshold(img, BatchOptLoc.Algorithm{1}, fgFraction, localMaxInt) + thOffset;
                    imgOut = uint8(img > threshold);

                    obj.mibModel.setData2D(imgOut, BatchOptLoc.Destination{1}, sliceId, 3, NaN, getDataOptions);

                    if BatchOptLoc.showWaitbar; progressBar.increment(); end
                end
            end

            if BatchOptLoc.showWaitbar; progressBar.deletePoolWaitbar(); end

            if strcmp(BatchOptLoc.Destination{1}, 'mask')
                obj.mibModel.showMask = true;
                notify(obj.mibModel, 'UpdateGuiWidgets', core.ToggleEventData({'checkboxes'}));
            end
            notify(obj.mibModel, 'ShowImage');

            obj.returnBatchOpt(BatchOptLoc);
        end

        % -----------------------------------------------------------
        function helpButton_Callback(obj)
            % HELPBUTTON_CALLBACK - Open documentation in browser.

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.GlobalThresholding.helpButton_Callback: triggered\n');
            end
            helpFilPath = fullfile(fileparts(obj.mibModel.mibPath), 'docs', 'site', 'user-interface', 'ribbon', 'tools', 'tools-globalthres.html');
            if isfile(helpFilPath)
                web(helpFilPath, '-browser');
            else
                web('http://mib.helsinki.fi/help/main3/user-interface/ribbon/tools/tools-globalthres.html', '-browser');
            end

        end

    end
end
