% Author: Ilya Belevich, University of Helsinki (ilya.belevich @ helsinki.fi)
% part of Microscopy Image Browser, http:\\mib.helsinki.fi
% License: BSD-3 clause (https://opensource.org/license/bsd-3-clause/)

classdef ContrastNormalization < handle
% CONTRASTNORMALIZATION - Controller for slice-by-slice contrast normalization of 3D/4D datasets.
%
% Normalizes image contrast across Z-slices or time frames using one of four
% strategies: full-frame Z-stack, time-series, masked-area, or background shift.
% Fully compatible with the MIB3 batch-processing pipeline (BatchOpt).
%
% Usage:
%   .. code-block:: matlab
%
%      obj.mibController.startController('controllers.ContrastNormalization');
%      controllers.ContrastNormalization(mibModel, [], BatchOpt);   % headless batch run
%      controllers.ContrastNormalization(mibModel, [], NaN);        % return BatchOpt schema
%      obj.startController('controllers.ContrastNormalization');    % start from MibController
%      obj.startController('controllers.ContrastNormalization');    % start from MibController

    properties
        mibModel        % handle to MibModel
        view            % handle to the ContrastNormalizationGUI .mlapp (empty in batch mode)
        listener        % cell array of listener handles
        BatchOpt        % structure compatible with batch processing
    end

    events
        CloseEvent      % fired when the window closes
    end

    methods (Static)
        function ViewListner_Callback2(obj, ~, evnt)
            % VIEWLISTNER_CALLBACK2 - Static guarded listener callback.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.ViewListner_Callback2(src, evnt)
            %
            % Routes ``UpdateGuiWidgets`` and ``NewDataset`` model events to
            % :meth:`updateWidgets`. Deletes stale listeners when the controller
            % or its view has been destroyed.
            %
            % Input Arguments:
            %   - **obj** - :class:`controllers.ContrastNormalization` instance.
            %   - **evnt** - event data from the model.
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
        % --- External method file declarations ---
        gui_Callbacks(obj, source, event)
        continueBtn_Callback(obj, useBatchMode)
        options = normalizeZStack(obj, colorChannel, options)
        options = normalizeTimeSeries(obj, colorChannel, options)
        options = normalizeMaskedArea(obj, colorChannel, options)
        options = normalizeBackground(obj, colorChannel, options)
        [mean_val, std_val] = collectSliceStats(obj, z1, z2, t, colorCh, useMask, options)

        % ---------------------------------------------------------------
        function obj = ContrastNormalization(mibModel, varargin)
            % CONTRASTNORMALIZATION - Construct the contrast-normalization controller.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj = controllers.ContrastNormalization(mibModel)
            %      obj = controllers.ContrastNormalization(mibModel, [])
            %      obj = controllers.ContrastNormalization(mibModel, [], BatchOptInput)
            %      obj = controllers.ContrastNormalization(mibModel, [], NaN)
            %
            % Input Arguments:
            %   - **mibModel** - handle to :class:`models.MibModel`.
            %   - **varargin{1}** *(optional)* - reserved compatibility slot.
            %   - **varargin{2}** *(optional)* - ``BatchOpt`` struct for headless run,
            %     or ``NaN`` to return the default ``BatchOpt`` schema via ``SyncBatch``.

            obj.mibModel = mibModel;
            id = obj.mibModel.getActiveId();
            dataset = obj.mibModel.I{id};

            % Initialise session settings if not yet present
            %obj.mibModel.sessionSettings = rmfield(obj.mibModel.sessionSettings, 'ContNorm');
            if ~isfield(obj.mibModel.sessionSettings, 'ContNorm')
                obj.mibModel.sessionSettings.ContNorm = obj.defaultSessionSettings();
            end
            settings = obj.mibModel.sessionSettings.ContNorm;

            % Build color-channel list dynamically from the active dataset
            possibleColChannels = arrayfun(@(x) sprintf('ColCh %d', x), 1:dataset.image.colors, 'UniformOutput', false);
            possibleColChannels = [{'All channels', 'Shown channels'}, possibleColChannels];

            [~, ~, depth] = dataset.getDatasetDimensions('image');

            % ---- BatchOpt defaults (restored from session settings where available) ----
            obj.BatchOpt.Target    = {settings.Target};
            obj.BatchOpt.Target{2} = {'Z stack', 'Time series', 'Masked area', 'Background'};
            obj.BatchOpt.Mode    = {settings.Mode};
            obj.BatchOpt.Mode{2} = {'Automatic', 'Manual', 'BasedOnSlice'};
            obj.BatchOpt.Mean{1} = settings.Mean;
            obj.BatchOpt.Mean{2} = [1, Inf];
            obj.BatchOpt.Mean{3} = 'on';
            obj.BatchOpt.Std{1}  = settings.Std;
            obj.BatchOpt.Std{2}  = [0.1, Inf];
            obj.BatchOpt.Std{3}  = 'off';
            obj.BatchOpt.ColChannel    = {settings.ColChannel};
            obj.BatchOpt.ColChannel{2} = possibleColChannels;
            obj.BatchOpt.Exculude    = {settings.Exculude};
            obj.BatchOpt.Exculude{2} = {'Whole range', 'Excude blacks', 'Excude whites'};
            obj.BatchOpt.MaskLayer    = {settings.MaskLayer};
            obj.BatchOpt.MaskLayer{2} = {'selection', 'mask'};
            obj.BatchOpt.ReferenceSliceNo{1} = dataset.slices{3}(1);
            obj.BatchOpt.ReferenceSliceNo{2} = [1 depth];
            obj.BatchOpt.ReferenceSliceNo{3} = 'on';
            obj.BatchOpt.TimeSeriesNormalization    = {settings.TimeSeriesNormalization};
            obj.BatchOpt.TimeSeriesNormalization{2} = {'Based on current 2D slice', 'Based on complete 3D stack'};
            obj.BatchOpt.showWaitbar = settings.showWaitbar;
            obj.BatchOpt.id = id;

            obj.BatchOpt.mibBatchSectionName = 'Ribbon -> Image';
            obj.BatchOpt.mibBatchActionName  = 'Contrast -> Normalize layers';
            obj.BatchOpt.mibBatchTooltip.Target = ...
                'Normalize Z stack, frames of the time series, obtain normalization coef. from the masked areas (Masked area) or background normalization from the masked areas';
            obj.BatchOpt.mibBatchTooltip.Mode = ...
                'In the automatic mode the normalization coefficients are calculated from the stack; in manual mode the provided Mean and Std values are used';
            obj.BatchOpt.mibBatchTooltip.Mean = ...
                '[Only for Mode->Manual] Normalize intensities to this mean value';
            obj.BatchOpt.mibBatchTooltip.Std = ...
                '[Only for Mode->Manual] Normalize intensities to this std value';
            obj.BatchOpt.mibBatchTooltip.ColChannel = 'Color channels for normalization';
            obj.BatchOpt.mibBatchTooltip.Exculude = ...
                'Exclude black or white pixels from the calculations of Mean and Std values';
            obj.BatchOpt.mibBatchTooltip.MaskLayer = ...
                '[Masked area and Background only] Specify the layer to obtain the masked areas';
            obj.BatchOpt.mibBatchTooltip.ReferenceSliceNo = ...
                '[BasedOnSlice only] Specify slice number to use as reference for normalization';
            obj.BatchOpt.mibBatchTooltip.TimeSeriesNormalization = ...
                '[Time series only] Calculate mean/std for each 3D stack or only the shown Z-section';
            obj.BatchOpt.mibBatchTooltip.showWaitbar = 'Show or not the progress bar during execution';

            % ---- Batch-mode dispatch ----
            if nargin == 3
                BatchOptInput = varargin{2};
                if ~isstruct(BatchOptInput)
                    if isnan(BatchOptInput)
                        obj.returnBatchOpt();
                    else
                        utils.dlgs.showErrorDialog(obj.mibModel.getProgressBarParent(), ...
                            'A structure as the 3rd parameter is required!', ...
                            'ContrastNormalization: init error');
                    end
                    return;
                end
                obj.BatchOpt = utils.updateBatchOptCombineFields_Shared(obj.BatchOpt, BatchOptInput);
                obj.continueBtn_Callback(true);
                notify(obj, 'CloseEvent');
                return;
            end

            % ---- GUI mode ----
            guiName = 'views.ContrastNormalizationGUI';
            obj.view = core.ChildView(obj, guiName); % initialize the view
            utils.applyThemeColors(obj.view.gui);   % adapt the standard dialog button colors to the light/dark theme
            obj.addCallbacks();

            % update font size
            Font = obj.mibModel.preferences.System.Font;
            if obj.view.handles.continueBtn.FontSize ~= Font.FontSize ...
                    || ~strcmp(obj.view.handles.continueBtn.FontName, Font.FontName)
                utils.fontSizeUpdate(obj.view.gui, Font);
            end
            % position the dialog
            obj.view.gui = utils.moveWindowOutside(obj.view.gui, obj.mibModel.mibGUI, 'left');
            obj.updateWidgets();

            obj.listener{1} = addlistener(obj.mibModel, 'UpdateGuiWidgets', @(src, evnt) obj.ViewListner_Callback2(obj, src, evnt));
            obj.listener{2} = addlistener(obj.mibModel, 'NewDataset', @(src, evnt) obj.ViewListner_Callback2(obj, src, evnt));
            % show gui window
            obj.view.gui.Visible = 'on';
        end

        % ---------------------------------------------------------------
        function closeWindow(obj)
            % CLOSEWINDOW - Close the dialog, save settings, and release listeners.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.closeWindow()

            % Persist current settings for next open
            obj.mibModel.sessionSettings.ContNorm = obj.captureSessionSettings();

            if ~isempty(obj.view) && isvalid(obj.view.gui)
                delete(obj.view.gui);
            end
            for i = 1:numel(obj.listener); delete(obj.listener{i}); end
            notify(obj, 'CloseEvent');
        end

        % ---------------------------------------------------------------
        function returnBatchOpt(obj, BatchOptOut)
            % RETURNBATCHOPT - Forward ``BatchOpt`` to ``mibBatchController`` via ``SyncBatch``.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.returnBatchOpt()
            %      obj.returnBatchOpt(BatchOptOut)
            %
            % Input Arguments:
            %   - **BatchOptOut** *(optional)* - override struct; defaults to ``obj.BatchOpt``.
            if nargin < 2; BatchOptOut = obj.BatchOpt; end
            eventdata = core.ToggleEventData(BatchOptOut);
            notify(obj.mibModel, 'SyncBatch', eventdata);
        end

        % ---------------------------------------------------------------
        function updateBatchOptFromGUI(obj, hObject)
            % UPDATEBATCHOPTFROMGUI - Sync ``obj.BatchOpt`` from a single widget.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.updateBatchOptFromGUI(hObject)
            %
            % Input Arguments:
            %   - **hObject** - AppDesigner widget whose ``Tag`` matches a ``BatchOpt`` field.
            obj.BatchOpt = utils.updateBatchOptFromGUI_Shared(obj.BatchOpt, hObject);
        end

        % ---------------------------------------------------------------
        function updateWidgets(obj)
            % UPDATEWIDGETS - Refresh all GUI widgets from the current dataset state.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.updateWidgets()
            %
            % Rebuilds the ``ColChannel`` dropdown to match the active dataset,
            % then applies the current ``BatchOpt`` to all widgets and updates
            % context-sensitive enable states.

            id = obj.mibModel.getActiveId();
            dataset = obj.mibModel.I{id};
            [~, ~, depth] = dataset.getDatasetDimensions('image');

            % Rebuild ColChannel options for the active dataset
            possibleColChannels = arrayfun(@(x) sprintf('ColCh %d', x), 1:dataset.image.colors, 'UniformOutput', false);
            possibleColChannels = [{'All channels', 'Shown channels'}, possibleColChannels];
            obj.BatchOpt.ColChannel{2} = possibleColChannels;
            if ~ismember(obj.BatchOpt.ColChannel{1}, possibleColChannels)
                obj.BatchOpt.ColChannel{1} = 'All channels';
            end

            % Update reference slice to the current slice
            obj.BatchOpt.ReferenceSliceNo{1} = dataset.slices{3}(1);
            obj.BatchOpt.ReferenceSliceNo{2} = [1 depth];

            % Apply BatchOpt to all widgets
            utils.updateGUIFromBatchOpt_Shared(obj.view, obj.BatchOpt);

            % Update context-sensitive enable states
            obj.updateContextualWidgets();
        end

        % ---------------------------------------------------------------
        function updateContextualWidgets(obj)
            % UPDATECONTEXTUALWIDGETS - Enable or disable context-sensitive widgets.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.updateContextualWidgets()
            %
            % Enables ``Mean`` / ``Std`` only in Manual mode; ``ReferenceSliceNo``
            % only in BasedOnSlice mode; ``MaskLayer`` only for Masked area /
            % Background targets; ``TimeSeriesNormalization`` only for Time series.

            if isempty(obj.view) || ~isvalid(obj.view.gui); return; end
            h = obj.view.handles;

            isManual      = strcmp(obj.BatchOpt.Mode{1}, 'Manual');
            isBasedOnSlice = strcmp(obj.BatchOpt.Mode{1}, 'BasedOnSlice');
            isMasked      = ismember(obj.BatchOpt.Target{1}, {'Masked area', 'Background'});
            isTimeSeries  = strcmp(obj.BatchOpt.Target{1}, 'Time series');

            h.Mean.Enable = matlab.lang.OnOffSwitchState(isManual);
            h.Std.Enable = matlab.lang.OnOffSwitchState(isManual);
            h.ReferenceSliceNo.Enable = matlab.lang.OnOffSwitchState(isBasedOnSlice);
            h.MaskLayer.Enable = matlab.lang.OnOffSwitchState(isMasked);
            h.TimeSeriesNormalization.Enable = matlab.lang.OnOffSwitchState(isTimeSeries);
        end

        % ---------------------------------------------------------------
        function addCallbacks(obj)
            % ADDCALLBACKS - Wire every widget to the central :meth:`gui_Callbacks` dispatcher.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.addCallbacks()
            %
            % Sets ``CloseRequestFcn`` on the figure, then assigns the
            % ``gui_Callbacks`` anonymous handle to every tagged widget listed
            % in the view contract.  Widgets not yet present in the ``.mlapp``
            % are silently skipped.

            obj.view.gui.CloseRequestFcn = @(~,~) obj.closeWindow();
            h  = obj.view.handles;
            cb = @(src, evt) obj.gui_Callbacks(src, evt);

            buttonTags = {'continueBtn', 'closeBtn', 'helpBtn'};
            for k = 1:numel(buttonTags)
                if isfield(h, buttonTags{k})
                    h.(buttonTags{k}).ButtonPushedFcn = cb;
                end
            end

            valueTags = {'Target', 'Mode', 'Mean', 'Std', 'ReferenceSliceNo', ...
                'ColChannel', 'Exculude', 'MaskLayer', 'TimeSeriesNormalization', ...
                'showWaitbar'};
            for k = 1:numel(valueTags)
                if isfield(h, valueTags{k})
                    h.(valueTags{k}).ValueChangedFcn = cb;
                end
            end
        end
    end

    methods (Access = private)
        % ---------------------------------------------------------------
        function settings = defaultSessionSettings(~)
            % DEFAULTSESSIONSETTINGS - Return the factory-default ContNorm settings struct.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      settings = obj.defaultSessionSettings()
            %
            % Output Arguments:
            %   - **settings** - struct stored in ``mibModel.sessionSettings.ContNorm``.
            settings.Target                  = 'Z stack';
            settings.Mode                    = 'Automatic';
            settings.Mean                    = 30000;
            settings.Std                     = 3000;
            settings.ColChannel              = 'All channels';
            settings.Exculude                = 'Whole range';
            settings.MaskLayer               = 'selection';
            settings.ReferenceSliceNo        = 1;
            settings.TimeSeriesNormalization = 'Based on current 2D slice';
            settings.showWaitbar             = true;
        end

        % ---------------------------------------------------------------
        function settings = captureSessionSettings(obj)
            % CAPTURESESSIONSETTINGS - Snapshot current ``BatchOpt`` into a session settings struct.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      settings = obj.captureSessionSettings()
            %
            % Output Arguments:
            %   - **settings** - struct ready to be written to ``mibModel.sessionSettings.ContNorm``.
            settings.Target                  = obj.BatchOpt.Target{1};
            settings.Mode                    = obj.BatchOpt.Mode{1};
            settings.Mean                    = obj.BatchOpt.Mean{1};
            settings.Std                     = obj.BatchOpt.Std{1};
            settings.ColChannel              = obj.BatchOpt.ColChannel{1};
            settings.Exculude                = obj.BatchOpt.Exculude{1};
            settings.MaskLayer               = obj.BatchOpt.MaskLayer{1};
            settings.ReferenceSliceNo        = obj.BatchOpt.ReferenceSliceNo{1};
            settings.TimeSeriesNormalization = obj.BatchOpt.TimeSeriesNormalization{1};
            settings.showWaitbar             = obj.BatchOpt.showWaitbar;
        end
    end
end
