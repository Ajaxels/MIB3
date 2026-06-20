classdef ContrastClahe < handle
% CONTRASTCLAHE - Controller for the Contrast-limited Adaptive Histogram Equalization dialog.
%
% Launch as GUI tool::
%
%   obj.mibController.startController('controllers.ContrastClahe');
%
% Launch in batch mode::
%
%   BatchOpt.DatasetType = {'Current stack (3D)'};
%   BatchOpt.NumTilesY   = {8, [1 256], 'on'};
%   obj.mibController.startController('controllers.ContrastClahe', [], BatchOpt);
%

    % Updates
    %

    properties
        mibModel
        % handle to MibModel
        view
        % handle to the view (views.ContrastClaheGUI)
        mibGUI
        % handle to main MIB figure (used as parent for modal dialogs)
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
                case 'UpdateGuiWidgets'
                    obj.updateWidgets();
                case 'SliceChanged'
                    if obj.view.handles.AutopreviewCheckbox.Value
                        obj.previewButtonPushed();
                    end
            end
        end
    end

    methods
        % External method file declarations
        imgOut = applyFilter(obj, varargin)

        % ---------------------------------------------------------------
        function obj = ContrastClahe(mibModel, varargin)
            % CONTRASTCLAHE - Constructor.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj = ContrastClahe(mibModel)
            %       obj = ContrastClahe(mibModel, [], BatchOpt)
            %

            obj.mibModel = mibModel;
            obj.mibGUI = mibModel.mibGUI;

            id = obj.mibModel.getActiveId();

            %% Build BatchOpt from sessionSettings.CLAHE
            PossibleColChannels = arrayfun(@(x) sprintf('ColCh %d', x), ...
                1:obj.mibModel.I{id}.image.colors, 'UniformOutput', false);

            numTiles    = obj.mibModel.sessionSettings.CLAHE.NumTiles;
            clipLimit   = obj.mibModel.sessionSettings.CLAHE.ClipLimit;
            nBins       = obj.mibModel.sessionSettings.CLAHE.NBins;
            distribution = obj.mibModel.sessionSettings.CLAHE.Distribution;
            alpha       = obj.mibModel.sessionSettings.CLAHE.Alpha;

            obj.BatchOpt.DatasetType    = {'Current stack (3D)'};
            obj.BatchOpt.DatasetType{2} = {'Shown slice (2D)', 'Current stack (3D)', 'Complete volume (4D)'};
            obj.BatchOpt.ColorChannel    = {'All'};
            obj.BatchOpt.ColorChannel{2} = [{'All'}, {'Displayed'}, PossibleColChannels];
            obj.BatchOpt.NumTilesX    = {numTiles(2), [1, 256],   'on'};
            obj.BatchOpt.NumTilesY    = {numTiles(1), [1, 256],   'on'};
            obj.BatchOpt.ClipLimit    = {clipLimit,   [0, 1],     'off'};
            obj.BatchOpt.NBins        = {nBins,       [2, 65536], 'on'};
            obj.BatchOpt.Distribution    = {distribution};
            obj.BatchOpt.Distribution{2} = {'uniform', 'rayleigh', 'exponential'};
            obj.BatchOpt.Alpha        = {alpha, [0, 1], 'off'};
            obj.BatchOpt.showWaitbar  = true;
            obj.BatchOpt.id           = id;

            obj.BatchOpt.mibBatchSectionName = 'Ribbon -> Image';
            obj.BatchOpt.mibBatchActionName  = 'Contrast-limited adaptive histogram equalization';
            obj.BatchOpt.mibBatchTooltip.DatasetType  = 'Specify part of the dataset for CLAHE';
            obj.BatchOpt.mibBatchTooltip.ColorChannel = 'Specify color channels for CLAHE';
            obj.BatchOpt.mibBatchTooltip.NumTilesY    = 'Number of tiles in the Y direction (rows)';
            obj.BatchOpt.mibBatchTooltip.NumTilesX    = 'Number of tiles in the X direction (columns)';
            obj.BatchOpt.mibBatchTooltip.ClipLimit    = 'Contrast enhancement limit [0 1]; higher values yield stronger contrast';
            obj.BatchOpt.mibBatchTooltip.NBins        = 'Number of histogram bins for the contrast transformation; higher values give greater dynamic range';
            obj.BatchOpt.mibBatchTooltip.Distribution = 'Desired histogram shape: uniform, rayleigh, or exponential';
            obj.BatchOpt.mibBatchTooltip.Alpha        = 'Distribution parameter for rayleigh and exponential; ignored for uniform';
            obj.BatchOpt.mibBatchTooltip.showWaitbar  = 'Show or not the progress bar during execution';

            %% Batch / headless mode
            if nargin == 3
                BatchOptIn = varargin{2};
                if isstruct(BatchOptIn) == 0
                    if isnan(BatchOptIn)
                        obj.returnBatchOpt();
                    else
                        utils.dlgs.showErrorDialog([], 'A structure as the 3rd parameter is required!', 'Error');
                    end
                    notify(obj, 'CloseEvent');
                    return;
                end
                obj.BatchOpt = utils.updateBatchOptCombineFields_Shared(obj.BatchOpt, BatchOptIn);
                obj.applyFilter();
                notify(obj, 'CloseEvent');
                return;
            end

            %% GUI mode
            obj.view = core.ChildView(obj, 'views.ContrastClaheGUI');
            obj.view.gui = utils.moveWindowOutside(obj.view.gui, obj.mibGUI, 'left');
            utils.fontSizeUpdate(obj.view.gui, obj.mibModel.preferences.System.Font);

            obj.updateWidgets();
            utils.updateGUIFromBatchOpt_Shared(obj.view, obj.BatchOpt);
            obj.updateAlphaState();
            obj.addCallbacks();
            obj.view.gui.Visible = 'on';

            obj.listener{1} = addlistener(obj.mibModel, 'UpdateGuiWidgets', @(src,evnt) obj.ViewListner_Callback2(obj, src, evnt));
            %obj.listener{2} = addlistener(obj.mibModel, 'SliceChanged',     @(src,evnt) obj.ViewListner_Callback2(obj, src, evnt));
        end

        % ---------------------------------------------------------------
        function addCallbacks(obj)
            % ADDCALLBACKS - Wire all widget callbacks after view creation.
            obj.view.gui.CloseRequestFcn = @(~,~) obj.closeWindow();
            obj.view.handles.DatasetType.ValueChangedFcn  = @(h,e) obj.updateBatchOptFromGUI(e);
            obj.view.handles.ColorChannel.ValueChangedFcn = @(h,e) obj.updateBatchOptFromGUI(e);
            obj.view.handles.NumTilesY.ValueChangedFcn     = @(h,e) obj.updateBatchOptFromGUI(e);
            obj.view.handles.NumTilesX.ValueChangedFcn     = @(h,e) obj.updateBatchOptFromGUI(e);
            obj.view.handles.ClipLimit.ValueChangedFcn     = @(h,e) obj.updateBatchOptFromGUI(e);
            obj.view.handles.NBins.ValueChangedFcn         = @(h,e) obj.updateBatchOptFromGUI(e);
            obj.view.handles.Distribution.ValueChangedFcn = @(h,e) obj.distributionChanged(e);
            obj.view.handles.Alpha.ValueChangedFcn         = @(h,e) obj.updateBatchOptFromGUI(e);
            obj.view.handles.previewButton.ButtonPushedFcn  = @(~,~) obj.previewButtonPushed();
            obj.view.handles.applyButton.ButtonPushedFcn   = @(~,~) obj.applyFilter();
            obj.view.handles.helpButton.ButtonPushedFcn     = @(~,~) obj.helpButton_Callback();
            obj.view.handles.closeButton.ButtonPushedFcn    = @(~,~) obj.closeWindow();
            obj.view.gui.KeyPressFcn = @(~,e) obj.figureKeyPress(e);
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

        % ---------------------------------------------------------------
        function updateBatchOptFromGUI(obj, event)
            % UPDATEBATCHOPTFROMGUI - Sync BatchOpt from a widget change event.
            obj.BatchOpt = utils.updateBatchOptFromGUI_Shared(obj.BatchOpt, event.Source);
            if obj.view.handles.autoPreview.Value; obj.previewButtonPushed(); end
        end

        % ---------------------------------------------------------------
        function distributionChanged(obj, event)
            % DISTRIBUTIONCHANGED - Update BatchOpt and toggle Alpha enable state.
            obj.BatchOpt = utils.updateBatchOptFromGUI_Shared(obj.BatchOpt, event.Source);
            obj.updateAlphaState();
            if obj.view.handles.autoPreview.Value; obj.previewButtonPushed(); end
        end

        % ---------------------------------------------------------------
        function updateAlphaState(obj)
            % UPDATEALPHASTATE - Enable AlphaSpinner only for non-uniform distributions.
            isUniform = strcmp(obj.BatchOpt.Distribution{1}, 'uniform');
            if isUniform
                obj.view.handles.AlphaSpinner.Enable = 'off';
            else
                obj.view.handles.AlphaSpinner.Enable = 'on';
            end
        end

        % ---------------------------------------------------------------
        function updateWidgets(obj)
            % UPDATEWIDGETS - Refresh widgets to reflect current model state.
            obj.BatchOpt.id = obj.mibModel.getActiveId();
            id = obj.BatchOpt.id;

            PossibleColChannels = arrayfun(@(x) sprintf('ColCh %d', x), ...
                1:obj.mibModel.I{id}.image.colors, 'UniformOutput', false);
            if numel(PossibleColChannels) + 2 ~= numel(obj.BatchOpt.ColorChannel{2})
                obj.BatchOpt.ColorChannel    = {'All'};
                obj.BatchOpt.ColorChannel{2} = [{'All'}, {'Displayed'}, PossibleColChannels];
            end

            utils.updateGUIFromBatchOpt_Shared(obj.view, obj.BatchOpt);
        end

        % ---------------------------------------------------------------
        function returnBatchOpt(obj, BatchOptOut)
            % RETURNBATCHOPT - Send BatchOpt to mibBatchController.
            if nargin < 2
                BatchOptOut = obj.BatchOpt;
            end
            BatchOptOut = rmfield(BatchOptOut, 'id');
            eventdata = core.ToggleEventData(BatchOptOut);
            notify(obj.mibModel, 'SyncBatch', eventdata);
        end

        % ---------------------------------------------------------------
        function closeWindow(obj)
            % CLOSEWINDOW - Save session settings, destroy view, fire CloseEvent.
            obj.mibModel.sessionSettings.CLAHE.NumTiles    = [obj.BatchOpt.NumTilesY{1}, obj.BatchOpt.NumTilesX{1}];
            obj.mibModel.sessionSettings.CLAHE.ClipLimit   = obj.BatchOpt.ClipLimit{1};
            obj.mibModel.sessionSettings.CLAHE.NBins       = obj.BatchOpt.NBins{1};
            obj.mibModel.sessionSettings.CLAHE.Distribution = obj.BatchOpt.Distribution{1};
            obj.mibModel.sessionSettings.CLAHE.Alpha       = obj.BatchOpt.Alpha{1};

            if isvalid(obj.view.gui)
                delete(obj.view.gui);
            end
            for i = 1:numel(obj.listener)
                delete(obj.listener{i});
            end
            notify(obj, 'CloseEvent');
        end

        % ---------------------------------------------------------------
        function helpButton_Callback(obj)
            % HELPBUTTON_CALLBACK - Open documentation in browser.
            helpFilPath = fullfile(fileparts(obj.mibModel.mibPath), 'docs', 'site', 'user-interface', 'ribbon', 'image', 'clahe.html');
            if isfile(helpFilPath)
                web(helpFilPath, '-browser');
            else
                web('http://mib.helsinki.fi/help/main3/user-interface/ribbon/image/clahe.html', '-browser');
            end
        end

        % ---------------------------------------------------------------
        function previewButtonPushed(obj)
            % PREVIEWBUTTONPUSHED - Apply CLAHE to current view and display as overlay.
            getDataOptions.blockModeSwitch = 1;
            id = obj.mibModel.getActiveId();
            dataset = obj.mibModel.I{id};

            switch obj.BatchOpt.ColorChannel{1}
                case 'All';       ColCh = 0;
                case 'Displayed'; ColCh = [];
                otherwise;        ColCh = str2double(obj.BatchOpt.ColorChannel{1}(7:end));
            end
            img = cell2mat(obj.mibModel.getData2D('image', [], [], ColCh, getDataOptions));

            filteredImg = obj.applyFilter(img);
            if isempty(filteredImg); return; end

            viewPort = dataset.image.viewPort;
            maxInt = dataset.image.maxInt;

            if ~isa(filteredImg, 'uint8')
                if ~obj.mibModel.onFlyImageStretch
                    if size(filteredImg, 3) == 1
                        colCh = dataset.selectedColorChannel;
                        if viewPort.min(colCh) ~= 0 || viewPort.max(colCh) ~= maxInt || viewPort.gamma(colCh) ~= 1
                            filteredImg = imadjust(filteredImg, ...
                                [viewPort.min(colCh)/maxInt viewPort.max(colCh)/maxInt], [0 1], viewPort.gamma(colCh));
                        end
                    else
                        if max(viewPort.min) > 0 || min(viewPort.max) ~= maxInt || sum(viewPort.gamma) ~= size(filteredImg,3)
                            for colCh = 1:size(filteredImg, 3)
                                filteredImg(:,:,colCh) = imadjust(filteredImg(:,:,colCh), ...
                                    [viewPort.min(colCh)/maxInt viewPort.max(colCh)/maxInt], [0 1], viewPort.gamma(colCh));
                            end
                        end
                    end
                    filteredImg = uint8(filteredImg / 256);
                end
            end

            showSettings.resizeToMagnification = true;
            showSettings.sImgIn = filteredImg;
            notify(obj.mibModel, 'ShowImage', core.ToggleEventData(showSettings));
        end

    end
end
