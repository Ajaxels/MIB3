classdef DisplayAdjust < handle
    % @type DisplayAdjust class is responsible for the Display Adjustment
    % window, available from Ribbon -> Image -> Adjust display
    %
    % @code
    % obj.startController('controllers.DisplayAdjust'); // as GUI tool
    % @endcode

    % Updates
    %

    properties
        mibModel
        % handle to MibModel
        view
        % handle to the view (core.ChildView wrapping views.DisplayAdjustGUI)
        listener
        % cell array with handles to event listeners
        BatchOpt
        % a structure compatible with batch operation, see constructor
        updateTimer
        % matlab.timer — fires ShowImage after dragging pauses, keeps slider responsive
    end

    events
        closeEvent
        % event firing when the window is closed
    end

    methods (Static)
        function ViewListner_Callback2(obj, ~, evnt)
            % Static listener dispatched by mibModel events
            if ~isvalid(obj) || isempty(obj.view) || ~isvalid(obj.view.gui)
                for i = 1:numel(obj.listener)
                    delete(obj.listener{i});
                end
                return;
            end
            switch evnt.EventName
                case 'SliceChanged'
                    if obj.listener{2}.Enabled
                        obj.updateHist();
                    end
                case 'FrameChanged'
                    if obj.listener{3}.Enabled
                        obj.updateHist();
                    end
                case {'UpdateGuiWidgets', 'NewDataset'}
                    obj.updateWidgets();
            end
        end
    end

    methods
        % -----------------------------------------------------------------
        function obj = DisplayAdjust(mibModel, varargin)
            % function obj = DisplayAdjust(mibModel, varargin)
            % Constructor for the DisplayAdjust controller
            %
            % Parameters:
            % mibModel: handle to MibModel
            % varargin{1}: [optional] a controller handle
            % varargin{2}: [optional] BatchOpt struct; if NaN, returns default BatchOpt

            obj.mibModel = mibModel;

            id = obj.mibModel.getActiveId();
            viewPort = obj.mibModel.I{id}.image.viewPort;
            nColors   = obj.mibModel.I{id}.image.colors;

            % ---- build BatchOpt with defaults
            PossibleColChannels = [{'All channels'}, ...
                arrayfun(@(x) sprintf('ColCh %d', x), 1:nColors, 'UniformOutput', false)];
            obj.BatchOpt.ColChannel    = {'All channels'};
            obj.BatchOpt.ColChannel{2} = PossibleColChannels;
            obj.BatchOpt.Min           = num2str(viewPort.min');
            obj.BatchOpt.Max           = num2str(viewPort.max');
            obj.BatchOpt.Gamma         = num2str(viewPort.gamma');
            obj.BatchOpt.detectMinPoint    = false;
            obj.BatchOpt.detectMinQuantile = '0';
            obj.BatchOpt.detectMaxPoint    = false;
            obj.BatchOpt.detectMaxQuantile = '0';
            obj.BatchOpt.showWaitbar   = true;

            obj.BatchOpt.mibBatchSectionName = 'Panel -> View settings';
            obj.BatchOpt.mibBatchActionName  = 'Display';

            obj.BatchOpt.mibBatchTooltip.ColChannel    = 'Apply Min/Max/Gamma to the specified color channel(s)';
            obj.BatchOpt.mibBatchTooltip.Min           = 'Intensities below this value will be shown in black';
            obj.BatchOpt.mibBatchTooltip.Max           = 'Intensities above this value will be shown in white';
            obj.BatchOpt.mibBatchTooltip.Gamma         = 'Value for the gamma correction curve';
            obj.BatchOpt.mibBatchTooltip.detectMinPoint    = 'When enabled, min point is auto-calculated from the dataset';
            obj.BatchOpt.mibBatchTooltip.detectMinQuantile = '% of pixels (0-100) excluded from blacks when detectMinPoint is on';
            obj.BatchOpt.mibBatchTooltip.detectMaxPoint    = 'When enabled, max point is auto-calculated from the dataset';
            obj.BatchOpt.mibBatchTooltip.detectMaxQuantile = '% of pixels (0-100) excluded from whites when detectMaxPoint is on';
            obj.BatchOpt.mibBatchTooltip.showWaitbar   = 'Show or not the progress bar during execution';

            % ---- Headless / batch mode
            if nargin == 3
                BatchOptInput = varargin{2};
                if ~isstruct(BatchOptInput)
                    if isnan(BatchOptInput)
                        obj.returnBatchOpt();
                    else
                        errOpts.mibPath = obj.mibModel.mibPath;
                        errOpts.WindowHeight = 150;
                        utils.dlgs.showErrorDialog([], ...
                            'A structure as the 3rd parameter is required!', ...
                            'Error', 'Error in controllers.DisplayAdjust', '', errOpts);
                    end
                    return;
                end

                % merge incoming fields
                obj.BatchOpt = utils.updateBatchOptCombineFields_Shared(obj.BatchOpt, BatchOptInput);

                if strcmp(obj.BatchOpt.ColChannel{1}, 'All channels')
                    colList = 1:nColors;
                else
                    colList = str2double(obj.BatchOpt.ColChannel{1}(6:end));
                end

                minVal   = str2num(obj.BatchOpt.Min);   %#ok<ST2NM>
                maxVal   = str2num(obj.BatchOpt.Max);   %#ok<ST2NM>
                gammaVal = str2num(obj.BatchOpt.Gamma); %#ok<ST2NM>
                if numel(minVal)   < numel(colList); minVal   = repmat(minVal(1),   [numel(colList),1]); end
                if numel(maxVal)   < numel(colList); maxVal   = repmat(maxVal(1),   [numel(colList),1]); end
                if numel(gammaVal) < numel(colList); gammaVal = repmat(gammaVal(1), [numel(colList),1]); end

                for colId = 1:numel(colList)
                    if obj.BatchOpt.detectMinPoint
                        minVal(colId) = obj.findMinBtn_Callback(colList(colId), ...
                            str2double(obj.BatchOpt.detectMinQuantile));
                    end
                    viewPort.min(colList(colId)) = minVal(colId);

                    if obj.BatchOpt.detectMaxPoint
                        maxVal(colId) = obj.findMaxBtn_Callback(colList(colId), ...
                            str2double(obj.BatchOpt.detectMaxQuantile));
                    end
                    viewPort.max(colList(colId)) = maxVal(colId);
                    viewPort.gamma(colList(colId)) = gammaVal(colId);
                end

                obj.BatchOpt.Min = num2str(viewPort.min(colList)');
                obj.BatchOpt.Max = num2str(viewPort.max(colList)');
                obj.mibModel.I{id}.image.viewPort = viewPort;

                obj.returnBatchOpt();
                notify(obj.mibModel, 'ShowImage');
                return;
            end

            % ---- GUI mode
            guiName = 'views.DisplayAdjustGUI';
            obj.view = core.ChildView(obj, guiName);

            % deferred-render timer — fires ShowImage 80ms after last slider event
            obj.updateTimer = timer('ExecutionMode', 'singleShot', 'StartDelay', 0.01, ...
                'TimerFcn', @(~,~) notify(obj.mibModel, 'ShowImage'));

            obj.addCallbacks();

            % update font
            Font = obj.mibModel.preferences.System.Font;
            if obj.view.handles.ColorDropDownLabel.FontSize ~= Font.FontSize || ...
                    ~strcmp(obj.view.handles.ColorDropDownLabel.FontName, Font.FontName)
                utils.fontSizeUpdate(obj.view.gui, Font);
            end

            obj.view.gui = utils.moveWindowOutside(obj.view.gui, obj.mibModel.mibGUI, 'left');

            obj.updateWidgets();
            obj.view.gui.Visible = 'on';

            % check for indexed color (cannot adjust)
            if strcmp(obj.mibModel.I{id}.image.colorType, 'indexed')
                dlgOpt.MsgBoxOnly   = true;
                dlgOpt.Icon         = 'puffin_warning';
                dlgOpt.Header       = '!!! Warning !!!';
                dlgOpt.HeaderLines  = 1;
                prompts = {sprintf('Indexed images cannot be adjusted!\nPlease convert to Grayscale or RGB first:\nMenu -> Image -> Mode ->')};
                defAns  = {''};
                utils.dlgs.inputUniversalDlg(obj.mibModel.mibGUI, prompts, defAns, 'Indexed colors', dlgOpt);
            end

            % ---- register event listeners
            obj.listener{1} = addlistener(obj.mibModel, 'UpdateGuiWidgets', ...
                @(src,evnt) controllers.DisplayAdjust.ViewListner_Callback2(obj, src, evnt));
            obj.listener{2} = addlistener(obj.mibModel, 'SliceChanged', ...
                @(src,evnt) controllers.DisplayAdjust.ViewListner_Callback2(obj, src, evnt));
            obj.listener{3} = addlistener(obj.mibModel, 'FrameChanged', ...
                @(src,evnt) controllers.DisplayAdjust.ViewListner_Callback2(obj, src, evnt));
            obj.listener{4} = addlistener(obj.mibModel, 'NewDataset', ...
                @(src,evnt) controllers.DisplayAdjust.ViewListner_Callback2(obj, src, evnt));
            obj.listener{2}.Enabled = false;   % enabled by autoHistCheck
            obj.listener{3}.Enabled = false;
        end

        % -----------------------------------------------------------------
        function closeWindow(obj)
            % function closeWindow(obj)
            % close the DisplayAdjust window and clean up

            if ~isempty(obj.updateTimer) && isvalid(obj.updateTimer)
                stop(obj.updateTimer);
                delete(obj.updateTimer);
            end
            if isvalid(obj.view.gui)
                delete(obj.view.gui);
            end
            for i = 1:numel(obj.listener)
                delete(obj.listener{i});
            end
            notify(obj, 'closeEvent');
        end

        % -----------------------------------------------------------------
        function returnBatchOpt(obj, BatchOptOut)
            % function returnBatchOpt(obj, BatchOptOut)
            % return BatchOpt structure to mibBatchController via SyncBatch

            if nargin < 2; BatchOptOut = obj.BatchOpt; end
            if isfield(BatchOptOut, 'id'); BatchOptOut = rmfield(BatchOptOut, 'id'); end
            eventdata = core.ToggleEventData(BatchOptOut);
            notify(obj.mibModel, 'SyncBatch', eventdata);
        end

        % -----------------------------------------------------------------
        function addCallbacks(obj)
            % function addCallbacks(obj)
            % wire all widget callbacks; called once from the constructor

            h = obj.view.handles;

            obj.view.gui.CloseRequestFcn = @(~,~) obj.closeWindow();
            obj.view.gui.WindowKeyPressFcn = @(hh,d) utils.childWindowKeyPressFcn(obj, hh, d);

            h.colorChannelCombo.ValueChangedFcn = @(~,~) obj.colorChannelCombo_Callback();

            h.minEdit.ValueChangedFcn      = @(~,~)   obj.minEdit_Callback();
            h.minSlider.ValueChangedFcn    = @(~,~)   obj.minSlider_Callback();
            h.minSlider.ValueChangingFcn   = @(~,evt) obj.minSlider_Changing(evt);
            h.maxEdit.ValueChangedFcn      = @(~,~)   obj.maxEdit_Callback();
            h.maxSlider.ValueChangedFcn    = @(~,~)   obj.maxSlider_Callback();
            h.maxSlider.ValueChangingFcn   = @(~,evt) obj.maxSlider_Changing(evt);
            h.gammaEdit.ValueChangedFcn    = @(~,~)   obj.gammaEdit_Callback();
            h.gammaSlider.ValueChangedFcn  = @(~,~)   obj.gammaSlider_Callback();
            h.gammaSlider.ValueChangingFcn = @(~,evt) obj.gammaSlider_Changing(evt);

            h.logViewCheck.ValueChangedFcn     = @(~,~) obj.updateHist();
            h.linkChannelsCheck.ValueChangedFcn = @(~,~) obj.updateHist();
            h.autoHistCheck.ValueChangedFcn     = @(~,~) obj.autoHistCheck_Callback();

            h.updateBtn.ButtonPushedFcn   = @(~,~) obj.updateHist();
            h.findMinBtn.ButtonPushedFcn  = @(~,~) obj.findMinBtn_Callback([], 0);
            h.findMaxBtn.ButtonPushedFcn  = @(~,~) obj.findMaxBtn_Callback([], 0);
            h.applyBtn.ButtonPushedFcn    = @(~,~) obj.applyBtn_Callback();
            h.stretchCurrent.ButtonPushedFcn = @(~,~) obj.stretchCurrent_Callback();
            h.adjHelpBtn.ButtonPushedFcn  = @(~,~) obj.adjHelpBtn_Callback();

            % histogram click
            h.imHist.ButtonDownFcn = @(~,~) obj.imHist_ButtonDownFcn();

            % context menus for findMin / findMax
            obj.addFindBtnContextMenus();
        end

        % -----------------------------------------------------------------
        function addFindBtnContextMenus(obj)
            % function addFindBtnContextMenus(obj)
            % add right-click context menus to findMinBtn and findMaxBtn

            h = obj.view.handles;
            thresholds = {0, 0.1, 0.25, 0.5, 1, 2.5, NaN};
            labels     = {'0%', '0.1%', '0.25%', '0.5%', '1%', '2.5%', 'Custom...'};

            % findMinBtn context menu
            cmMin = uicontextmenu(obj.view.gui);
            for k = 1:numel(thresholds)
                t = thresholds{k};
                uimenu(cmMin, 'Text', labels{k}, ...
                    'MenuSelectedFcn', @(~,~) obj.findMinBtn_Callback([], t));
            end
            h.findMinBtn.ContextMenu = cmMin;

            % findMaxBtn context menu
            cmMax = uicontextmenu(obj.view.gui);
            for k = 1:numel(thresholds)
                t = thresholds{k};
                uimenu(cmMax, 'Text', labels{k}, ...
                    'MenuSelectedFcn', @(~,~) obj.findMaxBtn_Callback([], t));
            end
            h.findMaxBtn.ContextMenu = cmMax;
        end

        % -----------------------------------------------------------------
        function updateWidgets(obj)
            % function updateWidgets(obj)
            % refresh all GUI widgets from the model (called on UpdateGuiWidgets)

            id = obj.mibModel.getActiveId();
            nColors = obj.mibModel.I{id}.image.colors;
            h = obj.view.handles;

            % rebuild channel list
            chItems = arrayfun(@(x) sprintf('Channel %d', x), 1:nColors, 'UniformOutput', false);
            oldVal  = h.colorChannelCombo.Value;
            h.colorChannelCombo.Items = chItems;

            % initialize to first of the currently selected color channels
            slices = obj.mibModel.I{id}.slices;
            firstCh = slices{4}(1);
            if firstCh <= nColors
                h.colorChannelCombo.Value = chItems{firstCh};
            elseif ismember(oldVal, chItems)
                h.colorChannelCombo.Value = oldVal;
            else
                h.colorChannelCombo.Value = chItems{1};
            end

            obj.updateSliders();
        end

        % -----------------------------------------------------------------
        function updateSliders(obj)
            % function updateSliders(obj)
            % synchronise slider ranges and edit-spinner values from viewPort

            id      = obj.mibModel.getActiveId();
            channel = obj.getChannelIndex();
            viewPort = obj.mibModel.I{id}.image.viewPort;
            maxInt  = double(obj.mibModel.I{id}.image.maxInt);

            min_val = viewPort.min(channel);
            max_val = viewPort.max(channel);
            gamma   = viewPort.gamma(channel);

            h = obj.view.handles;

            % minSlider: fixed range [0, maxInt]
            h.minSlider.Limits = [0, maxInt];
            h.minSlider.Value  = min_val;
            h.minEdit.Value    = min_val;
            ticks = round(linspace(0, maxInt, 5));
            h.minSlider.MajorTicks = ticks;
            h.minSlider.MajorTickLabels = arrayfun(@(v) sprintf('%d', v), ticks, 'UniformOutput', false);

            % maxSlider: fixed range [0, maxInt]
            h.maxSlider.Limits = [0, maxInt];
            h.maxSlider.Value  = max_val;
            h.maxEdit.Value    = max_val;
            h.maxSlider.MajorTicks = ticks;
            h.maxSlider.MajorTickLabels = arrayfun(@(v) sprintf('%d', v), ticks, 'UniformOutput', false);

            % gammaSlider: fixed range 0.1-5
            h.gammaSlider.Limits = [0.1, 5];
            h.gammaSlider.Value  = gamma;
            h.gammaEdit.Limits   = [0.1, 5];
            h.gammaEdit.Value    = gamma;

            obj.updateHist();
        end

        % -----------------------------------------------------------------
        function updateHist(obj)
            % function updateHist(obj)
            % recompute histogram for the current slice and selected channel

            id      = obj.mibModel.getActiveId();
            channel = obj.getChannelIndex();
            viewPort = obj.mibModel.I{id}.image.viewPort;
            maxInt  = double(obj.mibModel.I{id}.image.maxInt);
            h = obj.view.handles;

            % get current slice (blockModeSwitch=1 → crop to visible area)
            options.blockModeSwitch = 1;
            img = cell2mat(obj.mibModel.getData2D('image', [], [], channel, options));

            minX = viewPort.min(channel) - 1;
            maxX = viewPort.max(channel) + 1;
            viewDiff = max(1, ceil((maxX - minX) / 255));
            x = minX:viewDiff:maxX;
            if numel(x) < 2; x = [minX, maxX+1]; end
            counts = histcounts(double(img(:)), x);

            if obj.mibModel.I{id}.useLUT
                plotColor = obj.mibModel.I{id}.image.lutColors(channel, :);
                if isnan(plotColor(1)); plotColor = [0.2 0.5 0.8]; end
            else
                plotColor = [0.2 0.5 0.8];
            end

            ax = h.imHist;
            if any(counts > 0)
                areaObj = area(ax, x(1:end-1), counts, 'LineStyle', 'none', 'FaceColor', plotColor);
                areaObj.HitTest = 'off';
                areaObj.PickableParts = 'none';
            else
                cla(ax);
            end
            ax.XLim = [min(viewPort.min(channel), maxInt-3), ...
                       max(viewPort.max(channel), 2)];
            if h.logViewCheck.Value
                ax.YScale = 'log';
            else
                ax.YScale = 'linear';
            end

            % update channel dropdown items with current LUT colors
            nColors  = obj.mibModel.I{id}.image.colors;
            chItems  = arrayfun(@(x) sprintf('Channel %d', x), 1:nColors, 'UniformOutput', false);
            if ~isequal(h.colorChannelCombo.Items, chItems)
                curVal = h.colorChannelCombo.Value;
                h.colorChannelCombo.Items = chItems;
                if ismember(curVal, chItems)
                    h.colorChannelCombo.Value = curVal;
                else
                    h.colorChannelCombo.Value = chItems{1};
                end
            end

            % background color of combo = LUT color when useLUT is on, else white
            if obj.mibModel.I{id}.useLUT
                lut = obj.mibModel.I{id}.image.lutColors(channel, :);
                if isnan(lut(1)); lut = [0, 0, 0]; end
            else
                lut = [1, 1, 1];
            end
            h.colorChannelPanel1.BackgroundColor = lut;

            % update adjustPanel title
            h.adjustPanel.Title = sprintf('Adjust channel %d', channel);
        end

        % -----------------------------------------------------------------
        function updateSettings(obj)
            % function updateSettings(obj)
            % write slider values into viewPort for the active channel(s)

            id = obj.mibModel.getActiveId();
            h  = obj.view.handles;

            if h.linkChannelsCheck.Value
                channel = obj.mibModel.I{id}.slices{4};
            else
                channel = obj.getChannelIndex();
            end
            obj.mibModel.I{id}.image.viewPort.min(channel)   = h.minSlider.Value;
            obj.mibModel.I{id}.image.viewPort.max(channel)   = h.maxSlider.Value;
            obj.mibModel.I{id}.image.viewPort.gamma(channel) = h.gammaSlider.Value;
        end

        % -----------------------------------------------------------------
        function colorChannelCombo_Callback(obj)
            % function colorChannelCombo_Callback(obj)
            % update sliders when user selects a different channel

            obj.updateSliders();
        end

        % -----------------------------------------------------------------
        function minSlider_Callback(obj)
            % function minSlider_Callback(obj)
            % enforce min < max, sync edit field, update image

            id      = obj.mibModel.getActiveId();
            channel = obj.getChannelIndex();
            h = obj.view.handles;

            curVal  = h.minSlider.Value;
            max_val = obj.mibModel.I{id}.image.viewPort.max(channel);
            if curVal >= max_val
                curVal = max_val - 1;
                h.minSlider.Value = curVal;
            end
            h.minEdit.Value = curVal;

            obj.updateSettings();
            obj.updateHist();
            notify(obj.mibModel, 'ShowImage');
        end

        % -----------------------------------------------------------------
        function minEdit_Callback(obj)
            % function minEdit_Callback(obj)
            % validate user entry in minEdit spinner, then behave like slider

            id      = obj.mibModel.getActiveId();
            channel = obj.getChannelIndex();
            h = obj.view.handles;

            val = h.minEdit.Value;

            if val >= obj.mibModel.I{id}.image.viewPort.max(channel)
                val = obj.mibModel.I{id}.image.viewPort.max(channel) - 1;
                h.minEdit.Value = val;
            end

            if val < 0
                h.minSlider.Limits(1) = val;
            else
                h.minSlider.Limits(1) = 0;
            end
            h.minSlider.Value = val;
            obj.minSlider_Callback();
        end

        % -----------------------------------------------------------------
        function maxSlider_Callback(obj)
            % function maxSlider_Callback(obj)
            % enforce max > min, sync edit field, update image

            id      = obj.mibModel.getActiveId();
            channel = obj.getChannelIndex();
            h = obj.view.handles;

            curVal  = h.maxSlider.Value;
            min_val = obj.mibModel.I{id}.image.viewPort.min(channel);
            if curVal <= min_val
                curVal = min_val + 1;
                h.maxSlider.Value = curVal;
            end
            h.maxEdit.Value = curVal;

            obj.updateSettings();
            obj.updateHist();
            notify(obj.mibModel, 'ShowImage');
        end

        % -----------------------------------------------------------------
        function maxEdit_Callback(obj)
            % function maxEdit_Callback(obj)
            % validate user entry in maxEdit spinner, then behave like slider

            id      = obj.mibModel.getActiveId();
            channel = obj.getChannelIndex();
            h = obj.view.handles;
            maxInt = double(obj.mibModel.I{id}.image.maxInt);

            val = h.maxEdit.Value;

            if val <= obj.mibModel.I{id}.image.viewPort.min(channel)
                val = obj.mibModel.I{id}.image.viewPort.min(channel) + 1;
                h.maxEdit.Value = val;
            end

            if val > maxInt
                h.maxSlider.Limits(2) = val;
            else
                h.maxSlider.Limits(2) = maxInt;
            end
            h.maxSlider.Value = val;
            obj.maxSlider_Callback();
        end

        % -----------------------------------------------------------------
        function gammaSlider_Callback(obj)
            % function gammaSlider_Callback(obj)
            % update gamma in viewPort, refresh image and histogram

            h = obj.view.handles;
            h.gammaEdit.Value = h.gammaSlider.Value;
            obj.updateSettings();
            notify(obj.mibModel, 'ShowImage');
            obj.updateHist();
        end

        % -----------------------------------------------------------------
        function gammaEdit_Callback(obj)
            % function gammaEdit_Callback(obj)
            % clamp gamma to [0.1 5], sync slider, update image

            h = obj.view.handles;
            val = max(0.1, min(5, h.gammaEdit.Value));
            h.gammaEdit.Value  = val;
            h.gammaSlider.Value = val;
            obj.gammaSlider_Callback();
        end

        % -----------------------------------------------------------------
        function minSlider_Changing(obj, event)
            % function minSlider_Changing(obj, event)
            % live update while min slider is being dragged

            id      = obj.mibModel.getActiveId();
            channel = obj.getChannelIndex();
            h = obj.view.handles;

            val = event.Value;
            maxVal = obj.mibModel.I{id}.image.viewPort.max(channel);
            if val >= maxVal; val = maxVal - 1; end

            h.minEdit.Value = val;
            if h.linkChannelsCheck.Value
                channels = obj.mibModel.I{id}.slices{4};
            else
                channels = channel;
            end
            obj.mibModel.I{id}.image.viewPort.min(channels) = val;
            obj.throttledShowImage();
        end

        % -----------------------------------------------------------------
        function maxSlider_Changing(obj, event)
            % function maxSlider_Changing(obj, event)
            % live update while max slider is being dragged

            id      = obj.mibModel.getActiveId();
            channel = obj.getChannelIndex();
            h = obj.view.handles;

            val = event.Value;
            minVal = obj.mibModel.I{id}.image.viewPort.min(channel);
            if val <= minVal; val = minVal + 1; end

            h.maxEdit.Value = val;
            if h.linkChannelsCheck.Value
                channels = obj.mibModel.I{id}.slices{4};
            else
                channels = channel;
            end
            obj.mibModel.I{id}.image.viewPort.max(channels) = val;
            obj.throttledShowImage();
        end

        % -----------------------------------------------------------------
        function gammaSlider_Changing(obj, event)
            % function gammaSlider_Changing(obj, event)
            % live update while gamma slider is being dragged

            id      = obj.mibModel.getActiveId();
            channel = obj.getChannelIndex();
            h = obj.view.handles;

            val = event.Value;
            h.gammaEdit.Value = val;
            if h.linkChannelsCheck.Value
                channels = obj.mibModel.I{id}.slices{4};
            else
                channels = channel;
            end
            obj.mibModel.I{id}.image.viewPort.gamma(channels) = val;
            obj.throttledShowImage();
        end

        % -----------------------------------------------------------------
        function throttledShowImage(obj)
            % function throttledShowImage(obj)
            % restart the deferred-render timer on every slider event;
            % ShowImage fires 80ms after the last event (outside the callback)

            if ~isempty(obj.updateTimer) && isvalid(obj.updateTimer)
                if strcmp(obj.updateTimer.Running, 'on')
                    stop(obj.updateTimer);
                end
                start(obj.updateTimer);
            end
        end

        % -----------------------------------------------------------------
        function imHist_ButtonDownFcn(obj)
            % function imHist_ButtonDownFcn(obj)
            % left-click sets min, right-click sets max via histogram axes

            h = obj.view.handles;
            xy      = h.imHist.CurrentPoint;
            seltype = obj.view.gui.SelectionType;

            ylims = h.imHist.YLim;
            if xy(1,2) > ylims(2) + diff(ylims)*0.2; return; end

            switch seltype
                case 'normal'   % left click → set min
                    if xy(1,1) >= h.maxEdit.Value - 3; return; end
                    h.minEdit.Value = xy(1,1);
                    obj.minEdit_Callback();
                case 'alt'      % right click → set max
                    if xy(1,1) <= h.minEdit.Value + 3; return; end
                    h.maxEdit.Value = xy(1,1);
                    obj.maxEdit_Callback();
            end
        end

        % -----------------------------------------------------------------
        function minval = findMinBtn_Callback(obj, colorCh, threshold)
            % function minval = findMinBtn_Callback(obj, colorCh, threshold)
            % detect minimum intensity; threshold (%) excluded from low end
            %
            % Parameters:
            % colorCh: [optional] channel index; default = selected channel
            % threshold: [optional] % to exclude (0-2.5); NaN = ask user
            %
            % Return values:
            % minval: detected minimum value(s)

            if nargin < 3; threshold = 0; end
            if nargin < 2 || isempty(colorCh); colorCh = obj.getChannelIndex(); end

            id = obj.mibModel.getActiveId();

            if isnan(threshold)
                defAns = struct('Value', 0, 'Limits', [0 Inf], 'Step', 1, 'Round', false);
                threshold = utils.dlgs.inputSingleDlg(obj.view.gui, ...
                    'Quantile (%), 0 = absolute minimum:', defAns, ...
                    'Custom threshold');
                if isempty(threshold); minval = []; return; end
                if isnan(threshold) || threshold < 0 || threshold >= 100; minval = []; return; end
            end

            minval = zeros([numel(colorCh), 1], obj.mibModel.I{id}.image.dataClass);
            wb = [];
            if obj.BatchOpt.showWaitbar && ~isempty(obj.view)
                wb = uiprogressdlg(obj.mibModel.mibGUI, 'Value', 0, ...
                    'Message', 'Calculating minimum value...', 'Title', 'Find Min');
            end

            if ~strcmp(obj.mibModel.I{id}.datasetType, 'Virtual')
                for colId = 1:numel(colorCh)
                    if threshold == 0
                        minval(colId) = min(min(min(min( ...
                            obj.mibModel.I{id}.image.data{1}(:,:,colorCh(colId),:,:)))));
                    else
                        img  = obj.mibModel.I{id}.image.data{1}(:,:,colorCh(colId),:,:);
                        img  = sort(img(:));
                        n    = numel(img);
                        minval(colId) = (double(img(max(1, floor(n*threshold/100)))) + ...
                                         double(img(ceil(n*threshold/100)))) / 2;
                    end
                    if ~isempty(wb); wb.Value = colId/numel(colorCh); end
                end
            else
                if threshold ~= 0
                    dlgOpt.MsgBoxOnly = true; dlgOpt.Icon = 'puffin_error';
                    dlgOpt.Header = 'Quantile calculation in Virtual mode is not implemented!';
                    dlgOpt.HeaderLines = 1;
                    utils.dlgs.inputUniversalDlg(obj.view.gui, {}, {}, 'Error', dlgOpt);
                    notify(obj.mibModel, 'StopProtocol');
                    if ~isempty(wb); delete(wb); end
                    minval = []; return;
                end
                for colId = 1:numel(colorCh)
                    for t = 1:obj.mibModel.I{id}.image.time
                        getDataOpt.t = [t, t];
                        for z = 1:obj.mibModel.I{id}.image.depth
                            img = cell2mat(obj.mibModel.getData2D('image', z, 3, colorCh(colId), getDataOpt));
                            minval(colId) = min([minval(colId), min(img(:))]);
                            if minval(colId) == 0; break; end
                        end
                        if minval(colId) == 0; break; end
                    end
                    if ~isempty(wb); wb.Value = colId/numel(colorCh); end
                end
            end

            if ~isempty(wb); delete(wb); end
            if ~isempty(obj.view) && isvalid(obj.view.gui)
                obj.view.handles.minEdit.Value = double(minval(1));
                obj.minEdit_Callback();
            end
        end

        % -----------------------------------------------------------------
        function maxval = findMaxBtn_Callback(obj, colorCh, threshold)
            % function maxval = findMaxBtn_Callback(obj, colorCh, threshold)
            % detect maximum intensity; threshold (%) excluded from high end
            %
            % Parameters:
            % colorCh: [optional] channel index; default = selected channel
            % threshold: [optional] % to exclude from high end; NaN = ask user
            %
            % Return values:
            % maxval: detected maximum value(s)

            if nargin < 3; threshold = 0; end
            if nargin < 2 || isempty(colorCh); colorCh = obj.getChannelIndex(); end

            id = obj.mibModel.getActiveId();
            maxInt = double(obj.mibModel.I{id}.image.maxInt);

            if isnan(threshold)               
                defAns = struct('Value', 0, 'Limits', [0 Inf], 'Step', 1, 'Round', false);               
                threshold = utils.dlgs.inputSingleDlg(obj.view.gui, ...
                    'Quantile (%), 0 = absolute maximum:', defAns, ...
                    'Custom threshold');
                if isempty(threshold); maxval = []; return; end

                if isnan(threshold) || threshold < 0 || threshold >= 100; maxval = []; return; end
            end

            maxval = zeros([numel(colorCh), 1], obj.mibModel.I{id}.image.dataClass);
            wb = [];
            if obj.BatchOpt.showWaitbar && ~isempty(obj.view)
                wb = uiprogressdlg(obj.mibModel.mibGUI, 'Value', 0, ...
                    'Message', 'Calculating maximum value...', 'Title', 'Find Max');
            end

            if ~strcmp(obj.mibModel.I{id}.datasetType, 'Virtual')
                for colId = 1:numel(colorCh)
                    if threshold == 0
                        maxval(colId) = max(max(max(max( ...
                            obj.mibModel.I{id}.image.data{1}(:,:,colorCh(colId),:,:)))));
                    else
                        img  = obj.mibModel.I{id}.image.data{1}(:,:,colorCh(colId),:,:);
                        img  = sort(img(:));
                        n    = numel(img);
                        maxval(colId) = (double(img(max(1, floor(n*(1-threshold/100))))) + ...
                                         double(img(ceil(n*(1-threshold/100))))) / 2;
                    end
                    if ~isempty(wb); wb.Value = colId/numel(colorCh); end
                end
            else
                if threshold ~= 0
                    dlgOpt.MsgBoxOnly = true; dlgOpt.Icon = 'puffin_error';
                    dlgOpt.Header = 'Quantile calculation in Virtual mode is not implemented!';
                    dlgOpt.HeaderLines = 1;
                    utils.dlgs.inputUniversalDlg(obj.view.gui, {}, {}, 'Error', dlgOpt);
                    notify(obj.mibModel, 'StopProtocol');
                    if ~isempty(wb); delete(wb); end
                    maxval = []; return;
                end
                for colId = 1:numel(colorCh)
                    for t = 1:obj.mibModel.I{id}.image.time
                        getDataOpt.t = [t, t];
                        for z = 1:obj.mibModel.I{id}.image.depth
                            img = cell2mat(obj.mibModel.getData2D('image', z, 3, colorCh(colId), getDataOpt));
                            maxval(colId) = max([maxval(colId), max(img(:))]);
                            if maxval(colId) == maxInt; break; end
                        end
                        if maxval(colId) == maxInt; break; end
                    end
                    if ~isempty(wb); wb.Value = colId/numel(colorCh); end
                end
            end

            if ~isempty(wb); delete(wb); end
            if ~isempty(obj.view) && isvalid(obj.view.gui)
                obj.view.handles.maxEdit.Value = double(maxval(1));
                obj.maxEdit_Callback();
            end
        end

        % -----------------------------------------------------------------
        function applyBtn_Callback(obj)
            % function applyBtn_Callback(obj)
            % bake the current display range into ALL slices of the dataset

            id = obj.mibModel.getActiveId();

            if strcmp(obj.mibModel.I{id}.datasetType, 'Virtual')
                dlgOpt.MsgBoxOnly = true; dlgOpt.Icon = 'puffin_warning';
                dlgOpt.Header = 'Intensity recalculation is not available in Virtual mode!';
                dlgOpt.HeaderLines = 1;
                utils.dlgs.inputUniversalDlg(obj.view.gui, {}, {}, 'Not implemented', dlgOpt);
                notify(obj.mibModel, 'StopProtocol');
                return;
            end

            res = utils.dlgs.inputQuestDlg(obj.view.gui, ...
                sprintf('You are going to permanently recalculate intensities of the original image by stretching!\n\nAre you sure?'), ...
                '!!! Warning !!!', 'Proceed', 'Cancel', 'Cancel');
            if strcmp(res, 'Cancel'); return; end

            maxZ   = obj.mibModel.I{id}.image.depth;
            maxT   = obj.mibModel.I{id}.image.time;
            maxInt = double(obj.mibModel.I{id}.image.maxInt);
            channel = obj.getChannelIndex();
            viewPort = obj.mibModel.I{id}.image.viewPort;

            if maxT == 1; obj.mibModel.backup('image', 1); end

            wb = [];
            if obj.BatchOpt.showWaitbar
                wb = uiprogressdlg(obj.mibModel.mibGUI, 'Value', 0, ...
                    'Message', 'Adjusting...', 'Title', 'Adjusting intensities');
            end

            [lowIn, highIn, lowOut, highOut] = obj.mibModel.I{id}.image.getImAdjustStretchCoef(channel);
            waitbarStep = max(1, round(maxT*maxZ/20));

            for t = 1:maxT
                for z = 1:maxZ
                    obj.mibModel.I{id}.image.data{1}(:,:,z,channel,t) = imadjust( ...
                        obj.mibModel.I{id}.image.data{1}(:,:,z,channel,t), ...
                        [lowIn, highIn], [lowOut, highOut], viewPort.gamma(channel));
                    if ~isempty(wb) && mod(z + (t-1)*maxZ, waitbarStep) == 0
                        wb.Value = (z + (t-1)*maxZ) / (maxZ*maxT);
                    end
                end
            end

            log_text = sprintf('ContrastGamma: Channel:%d, Min:%g, Max:%g, Gamma:%g', ...
                channel, viewPort.min(channel), viewPort.max(channel), viewPort.gamma(channel));
            obj.mibModel.I{id}.image.updateImgInfo(log_text);

            obj.mibModel.I{id}.image.viewPort.min(channel)   = 0;
            obj.mibModel.I{id}.image.viewPort.max(channel)   = maxInt;
            obj.mibModel.I{id}.image.viewPort.gamma(channel) = 1;

            if ~isempty(wb); delete(wb); end
            obj.updateSliders();
            notify(obj.mibModel, 'ShowImage');
        end

        % -----------------------------------------------------------------
        function stretchCurrent_Callback(obj)
            % function stretchCurrent_Callback(obj)
            % bake the current display range into the CURRENT slice only

            id = obj.mibModel.getActiveId();

            if strcmp(obj.mibModel.I{id}.datasetType, 'Virtual')
                dlgOpt.MsgBoxOnly = true; dlgOpt.Icon = 'puffin_warning';
                dlgOpt.Header = 'Intensity recalculation is not available in Virtual mode!';
                dlgOpt.HeaderLines = 1;
                utils.dlgs.inputUniversalDlg(obj.view.gui, {}, {}, 'Not implemented', dlgOpt);
                notify(obj.mibModel, 'StopProtocol');
                return;
            end

            obj.mibModel.backup('image', 0);
            maxInt  = double(obj.mibModel.I{id}.image.maxInt);
            channel = obj.getChannelIndex();
            viewPort = obj.mibModel.I{id}.image.viewPort;

            getDataOpt.blockModeSwitch = 0;
            slice = cell2mat(obj.mibModel.getData2D('image', [], [], channel, getDataOpt));

            [lowIn, highIn, lowOut, highOut] = obj.mibModel.I{id}.image.getImAdjustStretchCoef(channel);
            slice = imadjust(slice, [lowIn, highIn], [lowOut, highOut], viewPort.gamma(channel));

            obj.mibModel.setData2D({slice}, 'image', [], [], channel, getDataOpt);

            obj.mibModel.I{id}.image.viewPort.min(channel)   = 0;
            obj.mibModel.I{id}.image.viewPort.max(channel)   = maxInt;
            obj.mibModel.I{id}.image.viewPort.gamma(channel) = 1;

            obj.updateSliders();
            notify(obj.mibModel, 'ShowImage');
        end

        % -----------------------------------------------------------------
        function autoHistCheck_Callback(obj)
            % function autoHistCheck_Callback(obj)
            % enable/disable automatic histogram refresh on slice/frame change

            val = obj.view.handles.autoHistCheck.Value;
            obj.listener{2}.Enabled = val;
            obj.listener{3}.Enabled = val;
            if val; obj.updateHist(); end
        end

        % -----------------------------------------------------------------
        function adjHelpBtn_Callback(obj)
            % function adjHelpBtn_Callback(obj)
            % open the help page in the system browser

            web(fullfile(fileparts(obj.mibModel.mibPath), ...
                'docs/html/user-interface/panels/viewsettings/viewsettings-adjustments.html'), ...
                '-browser');
        end

        % -----------------------------------------------------------------
        function idx = getChannelIndex(obj)
            % function idx = getChannelIndex(obj)
            % return the 1-based channel index from colorChannelCombo
            %
            % Return values:
            % idx: integer channel index; falls back to 1 on mismatch

            h   = obj.view.handles;
            idx = find(strcmp(h.colorChannelCombo.Items, h.colorChannelCombo.Value), 1);
            if isempty(idx); idx = 1; end
        end

    end % methods
end % classdef
