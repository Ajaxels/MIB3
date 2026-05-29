classdef DisplayAdjust < handle
% DISPLAYADJUST - Controller for the Display Adjustment dialog.
%
% Available from Ribbon → Image → Adjust display.  Provides per-channel
% min/max/gamma controls and a histogram view for the current dataset.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.startController('controllers.DisplayAdjust');

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
        CloseEvent
        % event firing when the window is closed
    end

    methods (Static)
        function ViewListner_Callback2(obj, ~, evnt)
            % VIEWLISTNER_CALLBACK2 - Static listener dispatched by mibModel events.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      DisplayAdjust.ViewListner_Callback2(obj, src, evnt)
            %
            % If the view window is no longer valid, deletes all listeners and
            % returns silently.
            %
            % Input Arguments:
            %   - **obj** — handle to the DisplayAdjust controller instance
            %   - **src** — event source handle (unused)
            %   - **evnt** — event data; ``evnt.EventName`` identifies the event
            %
            % Output Arguments:
            %   (none)
            %
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
            % DISPLAYADJUST - Constructor for the DisplayAdjust controller.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj = DisplayAdjust(mibModel)
            %      obj = DisplayAdjust(mibModel, controllerHandle, BatchOptIn)
            %
            % Input Arguments:
            %   - **mibModel** — handle to MibModel
            %   - **varargin{1}** — *(optional)* controller handle (reserved)
            %   - **varargin{2}** — *(optional)* BatchOpt struct; pass ``NaN`` to
            %     return the default BatchOpt without opening the GUI
            %
            % Output Arguments:
            %   - **obj** — new DisplayAdjust controller instance
            %

            obj.mibModel = mibModel;

            id = obj.mibModel.getActiveId();
            viewPort = obj.mibModel.I{id}.image.viewPort;
            nColors   = obj.mibModel.I{id}.image.colors;

            % ---- build BatchOpt with defaults
            PossibleColChannels = [{'All channels'}, arrayfun(@(x) sprintf('ColCh %d', x), 1:nColors, 'UniformOutput', false)];
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

            obj.BatchOpt.mibBatchSectionName = 'Ribbon -> Image';
            obj.BatchOpt.mibBatchActionName  = 'Adjust Display/Image';

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
            obj.updateTimer = timer('ExecutionMode', 'singleShot', 'StartDelay', 0.01, 'TimerFcn', @(~,~) notify(obj.mibModel, 'ShowImage'));

            obj.addCallbacks();

            % update font
            Font = obj.mibModel.preferences.System.Font;
            if obj.view.handles.ColorDropDownLabel.FontSize ~= Font.FontSize || ...
                    ~strcmp(obj.view.handles.ColorDropDownLabel.FontName, Font.FontName)
                utils.fontSizeUpdate(obj.view.gui, Font);
            end

            obj.view.gui = utils.moveWindowOutside(obj.view.gui, obj.mibModel.mibGUI, 'left');

            obj.updateWidgets();
            % add handle tags to the tooltips
            if obj.mibModel.preferences.System.DeveloperMode
                utils.overrideDescriptions(obj.view.handles, true, 'obj.view.handles');
            end
            % show the gui
            obj.view.gui.Visible = 'on';

            % check for indexed color (cannot adjust)
            if strcmp(obj.mibModel.I{id}.image.colorType, 'indexed')
                dlgOpt.MsgBoxOnly   = true;
                dlgOpt.Icon         = 'puffin_warning';
                prompts = {sprintf('Indexed images cannot be adjusted!\nPlease convert to Grayscale or RGB first:\nMenu -> Image -> Mode ->')};
                defAns  = {''};
                utils.dlgs.inputUniversalDlg(obj.mibModel.mibGUI, prompts, defAns, 'Indexed colors', dlgOpt);
            end

            % ---- register event listeners
            obj.listener{1} = addlistener(obj.mibModel, 'UpdateGuiWidgets', @(src,evnt) controllers.DisplayAdjust.ViewListner_Callback2(obj, src, evnt));
            obj.listener{2} = addlistener(obj.mibModel, 'SliceChanged', @(src,evnt) controllers.DisplayAdjust.ViewListner_Callback2(obj, src, evnt));
            obj.listener{3} = addlistener(obj.mibModel, 'FrameChanged', @(src,evnt) controllers.DisplayAdjust.ViewListner_Callback2(obj, src, evnt));
            obj.listener{4} = addlistener(obj.mibModel, 'NewDataset', @(src,evnt) controllers.DisplayAdjust.ViewListner_Callback2(obj, src, evnt));
            obj.listener{2}.Enabled = false;   % enabled by autoHistCheck
            obj.listener{3}.Enabled = false;
        end

        % -----------------------------------------------------------------
        function closeWindow(obj)
            % CLOSEWINDOW - Close the DisplayAdjust window and release all listeners.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.closeWindow()
            %
            % Output Arguments:
            %   (none)
            %

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
            notify(obj, 'CloseEvent');
        end

        % -----------------------------------------------------------------
        function returnBatchOpt(obj, BatchOptOut)
            % RETURNBATCHOPT - Return the BatchOpt structure to the Batch controller via the SyncBatch event.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.returnBatchOpt()
            %      obj.returnBatchOpt(BatchOptOut)
            %
            % Input Arguments:
            %   - **BatchOptOut** — *(optional)* local BatchOpt structure; when omitted,
            %     ``obj.BatchOpt`` is used
            %
            % Output Arguments:
            %   (none)
            %

            if nargin < 2; BatchOptOut = obj.BatchOpt; end
            if isfield(BatchOptOut, 'id'); BatchOptOut = rmfield(BatchOptOut, 'id'); end
            eventdata = core.ToggleEventData(BatchOptOut);
            notify(obj.mibModel, 'SyncBatch', eventdata);
        end

        % -----------------------------------------------------------------
        function addCallbacks(obj)
            % ADDCALLBACKS - Wire all widget callbacks; called once from the constructor.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.addCallbacks()
            %
            % Output Arguments:
            %   (none)
            %

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

            % double-click on sliders resets to limit/default
            obj.view.gui.WindowButtonDownFcn = @(~,~) obj.figureWindowButtonDown_Callback();
        end

        % -----------------------------------------------------------------
        function addFindBtnContextMenus(obj)
            % ADDFINDBTNCONTEXTMENUS - Add right-click context menus to findMinBtn and findMaxBtn.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.addFindBtnContextMenus()
            %
            % Output Arguments:
            %   (none)
            %

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
            % UPDATEWIDGETS - Refresh all GUI widgets from the model.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.updateWidgets()
            %
            % Output Arguments:
            %   (none)
            %

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
            % UPDATESLIDERS - Synchronise slider ranges and edit-spinner values from viewPort.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.updateSliders()
            %
            % Output Arguments:
            %   (none)
            %

            id      = obj.mibModel.getActiveId();
            channel = obj.getChannelIndex();
            viewPort = obj.mibModel.I{id}.image.viewPort;
            maxInt  = double(obj.mibModel.I{id}.image.maxInt);

            min_val = viewPort.min(channel);
            max_val = viewPort.max(channel);
            gamma   = viewPort.gamma(channel);

            h = obj.view.handles;

            % minSlider: expand lower limit if viewport min is below 0
            h.minSlider.Limits = [min(0, min_val), maxInt];
            h.minSlider.Value  = min_val;
            h.minEdit.Value    = min_val;
            ticks = round(linspace(0, maxInt, 5));
            h.minSlider.MajorTicks = ticks;
            h.minSlider.MajorTickLabels = arrayfun(@(v) sprintf('%d', v), ticks, 'UniformOutput', false);

            % maxSlider: expand upper limit if viewport max exceeds maxInt
            h.maxSlider.Limits = [0, max(maxInt, max_val)];
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
            % UPDATEHIST - Recompute histogram for the current slice and selected channel.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.updateHist()
            %
            % Output Arguments:
            %   (none)
            %

            id      = obj.mibModel.getActiveId();
            channel = obj.getChannelIndex();
            viewPort = obj.mibModel.I{id}.image.viewPort;
            maxInt  = double(obj.mibModel.I{id}.image.maxInt);
            h = obj.view.handles;

            % get current slice (blockModeSwitch=1 → crop to visible area)
            options.blockModeSwitch = 1;
            img = cell2mat(obj.mibModel.getData2D('image', [], [], channel, options));

            % Clamp viewport bounds to the valid intensity range
            viewMin = max(0, viewPort.min(channel));
            viewMax = min(maxInt, viewPort.max(channel));
            if viewMax - viewMin < 1
                viewMax = viewMin + 1;  % guard against zero-width range
            end

            % Distribute all bins across the visible viewport range so the
            % histogram has full resolution regardless of zoom level.
            % At full range this is identical to the old behavior; when
            % zoomed to a narrow range each bin covers a fraction of an
            % intensity level instead of ~128 levels.
            nBins = min(512, max(1, round(viewMax - viewMin)));
            binEdges = linspace(viewMin, viewMax, nBins + 1);
            counts = histcounts(double(img(:)), binEdges);

            if obj.mibModel.I{id}.useLUT
                plotColor = obj.mibModel.I{id}.image.lutColors(channel, :);
                if isnan(plotColor(1)); plotColor = [0.2 0.5 0.8]; end
            else
                plotColor = [0.2 0.5 0.8];
            end

            ax = h.imHist;
            if any(counts > 0)
                areaObj = area(ax, binEdges(1:end-1), counts, 'LineStyle', 'none', 'FaceColor', plotColor);
                areaObj.HitTest = 'off';
                areaObj.PickableParts = 'none';
            else
                cla(ax);
            end
            ax.XLim = [viewMin, viewMax];
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
            % UPDATESETTINGS - Write slider values into viewPort for the active channel(s).
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.updateSettings()
            %
            % Output Arguments:
            %   (none)
            %

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
            % COLORCHANNELCOMBO_CALLBACK - Update sliders when the user selects a different channel.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.colorChannelCombo_Callback()
            %
            % Output Arguments:
            %   (none)
            %

            obj.updateSliders();
        end

        % -----------------------------------------------------------------
        function minSlider_Callback(obj)
            % MINSLIDER_CALLBACK - Enforce min < max, sync edit field, update image.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.minSlider_Callback()
            %
            % Output Arguments:
            %   (none)
            %

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
            % MINEDIT_CALLBACK - Validate user entry in minEdit spinner, then behave like slider.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.minEdit_Callback()
            %
            % Output Arguments:
            %   (none)
            %

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
            % MAXSLIDER_CALLBACK - Enforce max > min, sync edit field, update image.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.maxSlider_Callback()
            %
            % Output Arguments:
            %   (none)
            %

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
            % MAXEDIT_CALLBACK - Validate user entry in maxEdit spinner, then behave like slider.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.maxEdit_Callback()
            %
            % Output Arguments:
            %   (none)
            %

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
            % GAMMASLIDER_CALLBACK - Update gamma in viewPort, refresh image and histogram.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.gammaSlider_Callback()
            %
            % Output Arguments:
            %   (none)
            %

            h = obj.view.handles;
            h.gammaEdit.Value = h.gammaSlider.Value;
            obj.updateSettings();
            notify(obj.mibModel, 'ShowImage');
            obj.updateHist();
        end

        % -----------------------------------------------------------------
        function gammaEdit_Callback(obj)
            % GAMMAEDIT_CALLBACK - Clamp gamma to [0.1, 5], sync slider, update image.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.gammaEdit_Callback()
            %
            % Output Arguments:
            %   (none)
            %

            h = obj.view.handles;
            val = max(0.1, min(5, h.gammaEdit.Value));
            h.gammaEdit.Value  = val;
            h.gammaSlider.Value = val;
            obj.gammaSlider_Callback();
        end

        % -----------------------------------------------------------------
        function minSlider_Changing(obj, event)
            % MINSLIDER_CHANGING - Live update while the min slider is being dragged.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.minSlider_Changing(event)
            %
            % Input Arguments:
            %   - **event** — ``ValueChangingData`` from the AppDesigner
            %     ``ValueChangingFcn`` callback; ``event.Value`` holds the current slider value
            %
            % Output Arguments:
            %   (none)
            %

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
            h.imHist.XLim = [min(val, double(obj.mibModel.I{id}.image.maxInt)-3), ...
                             max(obj.mibModel.I{id}.image.viewPort.max(channel), 2)];
            obj.throttledShowImage();
        end

        % -----------------------------------------------------------------
        function maxSlider_Changing(obj, event)
            % MAXSLIDER_CHANGING - Live update while the max slider is being dragged.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.maxSlider_Changing(event)
            %
            % Input Arguments:
            %   - **event** — ``ValueChangingData`` from the AppDesigner
            %     ``ValueChangingFcn`` callback; ``event.Value`` holds the current slider value
            %
            % Output Arguments:
            %   (none)
            %

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
            h.imHist.XLim = [min(obj.mibModel.I{id}.image.viewPort.min(channel), double(obj.mibModel.I{id}.image.maxInt)-3), ...
                             max(val, 2)];
            obj.throttledShowImage();
        end

        % -----------------------------------------------------------------
        function gammaSlider_Changing(obj, event)
            % GAMMASLIDER_CHANGING - Live update while the gamma slider is being dragged.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.gammaSlider_Changing(event)
            %
            % Input Arguments:
            %   - **event** — ``ValueChangingData`` from the AppDesigner
            %     ``ValueChangingFcn`` callback; ``event.Value`` holds the current slider value
            %
            % Output Arguments:
            %   (none)
            %

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
            % THROTTLEDSHOWIMAGE - Restart the deferred-render timer on every slider event.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.throttledShowImage()
            %
            % ShowImage fires after a short delay following the last slider event,
            % keeping the slider responsive during rapid dragging.
            %
            % Output Arguments:
            %   (none)
            %

            if ~isempty(obj.updateTimer) && isvalid(obj.updateTimer)
                if strcmp(obj.updateTimer.Running, 'on')
                    stop(obj.updateTimer);
                end
                start(obj.updateTimer);
            end
        end

        % -----------------------------------------------------------------
        function imHist_ButtonDownFcn(obj)
            % IMHIST_BUTTONDOWNFCN - Left-click sets min, right-click sets max via histogram axes.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.imHist_ButtonDownFcn()
            %
            % Output Arguments:
            %   (none)
            %

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
            % FINDMINBTN_CALLBACK - Detect minimum intensity; threshold (%) excluded from low end.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.findMinBtn_Callback(colorCh, threshold)
            %      minval = obj.findMinBtn_Callback(colorCh, threshold)
            %
            % Input Arguments:
            %   - **colorCh** — *(optional)* channel index; default = selected channel
            %   - **threshold** — *(optional)* percentage of pixels to exclude from the
            %     low end (0–2.5); ``NaN`` prompts the user for a custom value
            %
            % Output Arguments:
            %   - **minval** — detected minimum intensity value(s)
            %

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
            pwb = [];
            if obj.BatchOpt.showWaitbar && ~isempty(obj.view)
                pwb = core.PoolWaitbar(numel(colorCh), 'Calculating minimum value...', obj.view.gui, 'Find Min', true);
            end

            if ~strcmp(obj.mibModel.I{id}.datasetType, 'Virtual')
                for colId = 1:numel(colorCh)
                    if threshold == 0
                        minval(colId) = min(min(min(min( ...
                            obj.mibModel.I{id}.image.data{1}(:,:,:,colorCh(colId),:)))));
                    else
                        img  = obj.mibModel.I{id}.image.data{1}(:,:,:,colorCh(colId),:);
                        img  = sort(img(:));
                        n    = numel(img);
                        minval(colId) = (double(img(max(1, floor(n*threshold/100)))) + ...
                                         double(img(ceil(n*threshold/100)))) / 2;
                    end
                    if ~isempty(pwb)
                        if pwb.getCancelState(); pwb.deletePoolWaitbar(); minval = []; return; end
                        pwb.increment(); 
                    end
                end
            else
                if threshold ~= 0
                    dlgOpt.MsgBoxOnly = true; dlgOpt.Icon = 'puffin_error';
                    header = 'Quantile calculation in Virtual mode is not implemented!';
                    dlgOpt.HeaderLines = 1;
                    utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Error', dlgOpt);
                    notify(obj.mibModel, 'StopProtocol');
                    if ~isempty(pwb); pwb.deletePoolWaitbar(); end
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
                    if ~isempty(pwb); pwb.increment(); end
                end
            end

            if ~isempty(pwb); pwb.deletePoolWaitbar(); end
            if ~isempty(obj.view) && isvalid(obj.view.gui)
                obj.view.handles.minEdit.Value = double(minval(1));
                obj.minEdit_Callback();
            end
        end

        % -----------------------------------------------------------------
        function maxval = findMaxBtn_Callback(obj, colorCh, threshold)
            % FINDMAXBTN_CALLBACK - Detect maximum intensity; threshold (%) excluded from high end.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.findMaxBtn_Callback(colorCh, threshold)
            %      maxval = obj.findMaxBtn_Callback(colorCh, threshold)
            %
            % Input Arguments:
            %   - **colorCh** — *(optional)* channel index; default = selected channel
            %   - **threshold** — *(optional)* percentage of pixels to exclude from the
            %     high end (0–2.5); ``NaN`` prompts the user for a custom value
            %
            % Output Arguments:
            %   - **maxval** — detected maximum intensity value(s)
            %

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
            pwb = [];
            if obj.BatchOpt.showWaitbar && ~isempty(obj.view)
                pwb = core.PoolWaitbar(numel(colorCh), 'Calculating maximum value...', obj.view.gui, 'Find Max', true);
            end

            if ~strcmp(obj.mibModel.I{id}.datasetType, 'Virtual')
                for colId = 1:numel(colorCh)
                    if threshold == 0
                        maxval(colId) = max(max(max(max( ...
                            obj.mibModel.I{id}.image.data{1}(:,:,:,colorCh(colId),:)))));
                    else
                        img  = obj.mibModel.I{id}.image.data{1}(:,:,:,colorCh(colId),:);
                        img  = sort(img(:));
                        n    = numel(img);
                        maxval(colId) = (double(img(max(1, floor(n*(1-threshold/100))))) + ...
                                         double(img(ceil(n*(1-threshold/100))))) / 2;
                    end
                    if ~isempty(pwb)
                        if pwb.getCancelState(); pwb.deletePoolWaitbar(); maxval = []; return; end
                        pwb.increment();
                    end
                end
            else
                if threshold ~= 0
                    dlgOpt.MsgBoxOnly = true; dlgOpt.Icon = 'puffin_error';
                    header = 'Quantile calculation in Virtual mode is not implemented!';
                    dlgOpt.HeaderLines = 1;
                    utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Error', dlgOpt);
                    notify(obj.mibModel, 'StopProtocol');
                    if ~isempty(pwb); pwb.deletePoolWaitbar(); end
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
                    if ~isempty(pwb)
                        if pwb.getCancelState(); pwb.deletePoolWaitbar(); maxval = []; return; end
                        pwb.increment();
                    end
                end
            end

            if ~isempty(pwb); pwb.deletePoolWaitbar(); end
            if ~isempty(obj.view) && isvalid(obj.view.gui)
                obj.view.handles.maxEdit.Value = double(maxval(1));
                obj.maxEdit_Callback();
            end
        end

        % -----------------------------------------------------------------
        function applyBtn_Callback(obj)
            % APPLYBTN_CALLBACK - Bake the current display range into all slices of the dataset.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.applyBtn_Callback()
            %
            % Output Arguments:
            %   (none)
            %

            id = obj.mibModel.getActiveId();

            if strcmp(obj.mibModel.I{id}.datasetType, 'Virtual')
                dlgOpt.MsgBoxOnly = true; dlgOpt.Icon = 'puffin_warning';
                header = 'Intensity recalculation is not available in Virtual mode!';
                dlgOpt.HeaderLines = 1;
                utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Not implemented', dlgOpt);
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

            pwb = [];
            if obj.BatchOpt.showWaitbar
                waitbarStep = round(maxT*maxZ/20);
                pwb = core.PoolWaitbar(20, 'Adjusting...', obj.view.gui, 'Adjusting intensities', true);
            end
            

            [lowIn, highIn, lowOut, highOut] = obj.mibModel.I{id}.image.getImAdjustStretchCoef(channel);
            gammaVal = viewPort.gamma(channel);

            % Cache data{1} locally — avoids repeated subsref dispatch through
            % obj.mibModel.I{id}.image.data{1} on every slice (~18x slower in
            % the live MibModel chain than mutating a local variable).
            imageData = obj.mibModel.I{id}.image.data{1};
            tic
            index = 1;
            for t = 1:maxT
                for z = 1:maxZ
                    imageData(:,:,z,channel,t) = imadjust( ...
                        imageData(:,:,z,channel,t), ...
                        [lowIn, highIn], [lowOut, highOut], gammaVal);
                    if ~isempty(pwb) && mod(index, waitbarStep) == 0
                        if pwb.getCancelState()
                            obj.mibModel.I{id}.image.data{1} = imageData;
                            pwb.deletePoolWaitbar();
                            return;
                        end
                        pwb.increment();
                    end
                    index = index + 1;
                end
            end
            obj.mibModel.I{id}.image.data{1} = imageData;
            toc

            log_text = sprintf('ContrastGamma: Channel:%d, Min:%g, Max:%g, Gamma:%g', ...
                channel, viewPort.min(channel), viewPort.max(channel), viewPort.gamma(channel));
            
            obj.mibModel.I{id}.image.updateActionLog(log_text);

            obj.mibModel.I{id}.image.viewPort.min(channel)   = 0;
            obj.mibModel.I{id}.image.viewPort.max(channel)   = maxInt;
            obj.mibModel.I{id}.image.viewPort.gamma(channel) = 1;

            if ~isempty(pwb); pwb.deletePoolWaitbar(); end
            obj.updateSliders();
            notify(obj.mibModel, 'ShowImage');
        end

        % -----------------------------------------------------------------
        function stretchCurrent_Callback(obj)
            % STRETCHCURRENT_CALLBACK - Bake the current display range into the current slice only.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.stretchCurrent_Callback()
            %
            % Output Arguments:
            %   (none)
            %

            id = obj.mibModel.getActiveId();

            if strcmp(obj.mibModel.I{id}.datasetType, 'Virtual')
                dlgOpt.MsgBoxOnly = true; dlgOpt.Icon = 'puffin_warning';
                header = 'Intensity recalculation is not available in Virtual mode!';
                dlgOpt.HeaderLines = 1;
                utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Not implemented', dlgOpt);
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
            % AUTOHISTCHECK_CALLBACK - Enable/disable automatic histogram refresh on slice/frame change.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.autoHistCheck_Callback()
            %
            % Output Arguments:
            %   (none)
            %

            val = obj.view.handles.autoHistCheck.Value;
            obj.listener{2}.Enabled = val;
            obj.listener{3}.Enabled = val;
            if val; obj.updateHist(); end
        end

        % -----------------------------------------------------------------
        function adjHelpBtn_Callback(obj)
            % ADJHELPBTN_CALLBACK - Open the help page for the Display Adjustment dialog in a browser.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.adjHelpBtn_Callback()
            %
            % Output Arguments:
            %   (none)
            %

            web(fullfile(fileparts(obj.mibModel.mibPath), ...
                'docs/html/user-interface/panels/viewsettings/viewsettings-adjustments.html'), ...
                '-browser');
        end

        % -----------------------------------------------------------------
        function figureWindowButtonDown_Callback(obj)
            % FIGUREWINDOWBUTTONDOWN_CALLBACK - Reset slider on double-click.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.figureWindowButtonDown_Callback()
            %
            % Fires on every mouse press in the figure; only acts on
            % double-click (``SelectionType == 'open'``) over one of the three
            % sliders.
            %
            % Output Arguments:
            %   (none)
            %

            if ~strcmp(obj.view.gui.SelectionType, 'open'); return; end
            h = obj.view.handles;
            currentObj = obj.view.gui.CurrentObject;
            if isequal(currentObj, h.minSlider)
                obj.resetSlider('min');
            elseif isequal(currentObj, h.maxSlider)
                obj.resetSlider('max');
            elseif isequal(currentObj, h.gammaSlider)
                obj.resetSlider('gamma');
            end
        end

        % -----------------------------------------------------------------
        function resetSlider(obj, whichSlider)
            % RESETSLIDER - Reset a slider to its natural limit or default.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.resetSlider(whichSlider)
            %
            % Input Arguments:
            %   - **whichSlider** — ``'min'``, ``'max'``, or ``'gamma'``
            %
            %     - ``'min'`` — sets minSlider to ``Limits(1)`` (0, or lower if viewport was negative)
            %     - ``'max'`` — sets maxSlider to ``Limits(2)`` (maxInt, or higher if viewport exceeded it)
            %     - ``'gamma'`` — resets gammaSlider to ``1``
            %
            % Output Arguments:
            %   (none)
            %

            h = obj.view.handles;
            switch whichSlider
                case 'min'
                    val = h.minSlider.Limits(1);
                    h.minSlider.Value = val;
                    h.minEdit.Value   = val;
                case 'max'
                    val = h.maxSlider.Limits(2);
                    h.maxSlider.Value = val;
                    h.maxEdit.Value   = val;
                case 'gamma'
                    h.gammaSlider.Value = 1;
                    h.gammaEdit.Value   = 1;
            end
            obj.updateSettings();
            obj.updateHist();
            notify(obj.mibModel, 'ShowImage');
        end

        % -----------------------------------------------------------------
        function idx = getChannelIndex(obj)
            % GETCHANNELINDEX - Return the 1-based channel index from colorChannelCombo.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      idx = obj.getChannelIndex()
            %
            % Output Arguments:
            %   - **idx** — integer channel index; falls back to ``1`` on mismatch
            %

            h   = obj.view.handles;
            idx = find(strcmp(h.colorChannelCombo.Items, h.colorChannelCombo.Value), 1);
            if isempty(idx); idx = 1; end
        end

    end % methods
end % classdef
