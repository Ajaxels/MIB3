classdef ContentAwareFill < handle
% CONTENTAWAREFILL - Controller for the Content-aware fill dialog.
%
% Launch as GUI tool::
%
%   obj.mibController.startController('controllers.ContentAwareFill');
%
% Launch in batch mode::
%
%   BatchOpt.DatasetType = {'Current stack (3D)'};
%   BatchOpt.Method      = {'inpaintExemplar'};
%   obj.mibController.startController('controllers.ContentAwareFill', [], BatchOpt);
%

    properties
        mibModel
        % handle to MibModel
        view
        % handle to the view (views.ContentAwareFillGUI)
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
                case {'UpdateGuiWidgets', 'NewDataset'}
                    obj.updateWidgets();
            end
        end
    end

    methods
        % External method file declarations
        imgOut = applyFilter(obj, varargin)

        % -----------------------------------------------------------
        function obj = ContentAwareFill(mibModel, varargin)
            % CONTENTAWAREFILL - Constructor.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj = ContentAwareFill(mibModel)
            %       obj = ContentAwareFill(mibModel, [], BatchOpt)
            %
            obj.mibModel = mibModel;
            obj.mibGUI   = mibModel.mibGUI;

            id       = obj.mibModel.getActiveId();
            settings = obj.mibModel.sessionSettings.contentAwareFill;

            obj.BatchOpt.Method    = {settings.Method};
            obj.BatchOpt.Method{2} = {'inpaintCoherent', 'inpaintExemplar'};
            obj.BatchOpt.DatasetType    = {settings.DatasetType};
            obj.BatchOpt.DatasetType{2} = {'Shown slice (2D)', 'Current stack (3D)', 'Complete volume (4D)'};
            obj.BatchOpt.Mask    = {settings.Mask};
            obj.BatchOpt.Mask{2} = {'selection', 'mask'};
            obj.BatchOpt.Radius          = {settings.Radius,  [1, Inf], 'on'};
            obj.BatchOpt.SmoothingFactor = {settings.SmoothingFactor,  [0, Inf],  'on'};
            obj.BatchOpt.FillOrder    = {settings.FillOrder};
            obj.BatchOpt.FillOrder{2} = {'gradient', 'tensor'};
            obj.BatchOpt.showWaitbar  = true;
            obj.BatchOpt.id           = id;

            obj.BatchOpt.mibBatchSectionName = 'Ribbon -> Image';
            obj.BatchOpt.mibBatchActionName  = 'Tools for Images -> Content-aware fill';
            obj.BatchOpt.mibBatchTooltip.DatasetType     = 'Specify part of the dataset to fill';
            obj.BatchOpt.mibBatchTooltip.Mask            = 'Layer that defines the fill region: selection or mask';
            obj.BatchOpt.mibBatchTooltip.Method          = 'Fill algorithm: inpaintCoherent (coherent diffusion) or inpaintExemplar (patch-based)';
            obj.BatchOpt.mibBatchTooltip.Radius          = 'For inpaintCoherent: neighbourhood radius; for inpaintExemplar: patch size in pixels';
            obj.BatchOpt.mibBatchTooltip.SmoothingFactor = 'Smoothness of inpaintCoherent fill (0 = no smoothing); ignored for inpaintExemplar';
            obj.BatchOpt.mibBatchTooltip.FillOrder       = 'Fill priority for inpaintExemplar: gradient (edge-first) or tensor; ignored for inpaintCoherent';
            obj.BatchOpt.mibBatchTooltip.showWaitbar     = 'Show or not the progress bar during execution';

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
                obj.applyFilter();
                notify(obj, 'CloseEvent');
                return;
            end

            %% GUI mode
            obj.view = core.ChildView(obj, 'views.ContentAwareFillGUI');
            obj.view.gui = utils.moveWindowOutside(obj.view.gui, obj.mibGUI, 'left');
            utils.fontSizeUpdate(obj.view.gui, obj.mibModel.preferences.System.Font);

            obj.updateWidgets();
            utils.updateGUIFromBatchOpt_Shared(obj.view, obj.BatchOpt);
            obj.updateMethodDependentWidgets();
            obj.addCallbacks();
            obj.view.gui.Visible = 'on';

            obj.listener{1} = addlistener(obj.mibModel, 'UpdateGuiWidgets', @(src,evnt) obj.ViewListner_Callback2(obj, src, evnt));
            obj.listener{2} = addlistener(obj.mibModel, 'NewDataset',       @(src,evnt) obj.ViewListner_Callback2(obj, src, evnt));
        end

        % -----------------------------------------------------------
        function addCallbacks(obj)
            % ADDCALLBACKS - Wire all widget callbacks after view creation.
            obj.view.gui.CloseRequestFcn                  = @(~,~) obj.closeWindow();
            obj.view.handles.DatasetType.ValueChangedFcn  = @(h,e) obj.updateBatchOptFromGUI(e);
            obj.view.handles.Mask.ValueChangedFcn         = @(h,e) obj.updateBatchOptFromGUI(e);
            obj.view.handles.Method.ValueChangedFcn       = @(h,e) obj.methodChanged(e);
            obj.view.handles.Radius.ValueChangedFcn       = @(h,e) obj.updateBatchOptFromGUI(e);
            obj.view.handles.SmoothingFactor.ValueChangedFcn = @(h,e) obj.updateBatchOptFromGUI(e);
            obj.view.handles.FillOrder.ValueChangedFcn    = @(h,e) obj.updateBatchOptFromGUI(e);
            obj.view.handles.showWaitbar.ValueChangedFcn  = @(h,e) obj.updateBatchOptFromGUI(e);
            obj.view.handles.previewButton.ButtonPushedFcn = @(~,~) obj.previewButtonPushed();
            obj.view.handles.applyButton.ButtonPushedFcn  = @(~,~) obj.applyFilter();
            obj.view.handles.helpButton.ButtonPushedFcn   = @(~,~) obj.helpButton_Callback();
            obj.view.handles.closeButton.ButtonPushedFcn  = @(~,~) obj.closeWindow();
            obj.view.gui.KeyPressFcn = @(~,e) obj.figureKeyPress(e);
        end

        % -----------------------------------------------------------
        function figureKeyPress(obj, event)
            % FIGUREKEYPRESS - Forward key presses to MIB main window shortcuts.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.ContentAwareFill.figureKeyPress: triggered\n');
            end
            if isempty(event.Character); return; end
            eventData = core.ToggleEventData(struct('eventdata', event));
            notify(obj.mibModel, 'KeyPressEvent', eventData);
        end

        % -----------------------------------------------------------
        function updateBatchOptFromGUI(obj, event)
            % UPDATEBATCHOPTFROMGUI - Sync BatchOpt from a widget change event.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.ContentAwareFill.updateBatchOptFromGUI(%s): triggered\n', event.Source.Tag);
            end
            obj.BatchOpt = utils.updateBatchOptFromGUI_Shared(obj.BatchOpt, event.Source);
            if obj.view.handles.autoPreview.Value; obj.previewButtonPushed(); end
        end

        % -----------------------------------------------------------
        function methodChanged(obj, event)
            % METHODCHANGED - Update BatchOpt and toggle method-dependent widget states.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.ContentAwareFill.methodChanged: triggered\n');
            end
            obj.BatchOpt = utils.updateBatchOptFromGUI_Shared(obj.BatchOpt, event.Source);
            obj.updateMethodDependentWidgets();
            if obj.view.handles.autoPreview.Value; obj.previewButtonPushed(); end
        end

        % -----------------------------------------------------------
        function updateMethodDependentWidgets(obj)
            % UPDATEMETHODDEPENDENTWIDGETS - Enable/disable SmoothingFactor and FillOrder
            % based on the selected inpaint method.
            isCoherent = strcmp(obj.BatchOpt.Method{1}, 'inpaintCoherent');
            if isCoherent
                obj.view.handles.SmoothingFactor.Enable = 'on';
                obj.view.handles.FillOrder.Enable       = 'off';
                obj.view.handles.infoLabel.Text = sprintf('Diffusion-based fill; works well for smooth textures.\n - Radius controls the neighbourhood size\n - Smoothing factor controls how smooth the transition is');
            else
                obj.view.handles.SmoothingFactor.Enable = 'off';
                obj.view.handles.FillOrder.Enable       = 'on';
                obj.view.handles.infoLabel.Text = sprintf('Patch-based fill; copies texture patches from nearby areas.\n - Radius sets the patch size\n - Fill order (gradient / tensor) determines which pixels are filled first');
            end
        end

        % -----------------------------------------------------------
        function updateWidgets(obj)
            % UPDATEWIDGETS - Refresh widgets to reflect current model state.
            obj.BatchOpt.id = obj.mibModel.getActiveId();
            utils.updateGUIFromBatchOpt_Shared(obj.view, obj.BatchOpt);
        end

        % -----------------------------------------------------------
        function returnBatchOpt(obj, BatchOptOut)
            % RETURNBATCHOPT - Send BatchOpt to mibBatchController.
            if nargin < 2; BatchOptOut = obj.BatchOpt; end
            BatchOptOut = rmfield(BatchOptOut, 'id');
            notify(obj.mibModel, 'SyncBatch', core.ToggleEventData(BatchOptOut));
        end

        % -----------------------------------------------------------
        function closeWindow(obj)
            % CLOSEWINDOW - Save session settings, destroy view, fire CloseEvent.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.ContentAwareFill.closeWindow: triggered\n');
            end
            obj.mibModel.sessionSettings.contentAwareFill.Method      = obj.BatchOpt.Method{1};
            obj.mibModel.sessionSettings.contentAwareFill.DatasetType = obj.BatchOpt.DatasetType{1};
            obj.mibModel.sessionSettings.contentAwareFill.Mask        = obj.BatchOpt.Mask{1};
            obj.mibModel.sessionSettings.contentAwareFill.Radius = obj.BatchOpt.Radius{1};
            obj.mibModel.sessionSettings.contentAwareFill.SmoothingFactor = obj.BatchOpt.SmoothingFactor{1};
            obj.mibModel.sessionSettings.contentAwareFill.FillOrder   = obj.BatchOpt.FillOrder{1};

            if isvalid(obj.view.gui); delete(obj.view.gui); end
            for i = 1:numel(obj.listener); delete(obj.listener{i}); end
            notify(obj, 'CloseEvent');
        end

        % -----------------------------------------------------------
        function helpButton_Callback(obj)
            % HELPBUTTON_CALLBACK - Open documentation in browser.

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.ContentAwareFill.helpButton_Callback: triggered\n');
            end
            helpFilPath = fullfile(fileparts(obj.mibModel.mibPath), 'docs', 'site', 'user-interface', 'ribbon', 'image', 'image-tools-awarefill.html');
            if isfile(helpFilPath)
                web(helpFilPath, '-browser');
            else
                web('http://mib.helsinki.fi/help/main3/user-interface/ribbon/image/image-tools-awarefill.html', '-browser');
            end
        end

        % -----------------------------------------------------------
        function previewButtonPushed(obj)
            % PREVIEWBUTTONPUSHED - Apply fill to current view slice and display as overlay.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.ContentAwareFill.previewButtonPushed: triggered\n');
            end
            getDataOptions.blockModeSwitch = 1;
            id = obj.mibModel.getActiveId();

            img  = cell2mat(obj.mibModel.getData2D('image',              [], [], 0, getDataOptions));
            mask = cell2mat(obj.mibModel.getData2D(obj.BatchOpt.Mask{1}, [], [], 0, getDataOptions));

            if ~any(mask(:)); return; end

            waitbarHandle = uiprogressdlg(obj.mibModel.getProgressBarParent(), 'Indeterminate', 'on', ...
                'Message', 'Applying content-aware fill...', 'Title', 'Preview');
            filteredImg = obj.applyFilter(img, logical(mask));
            delete(waitbarHandle);
            if isempty(filteredImg); return; end

            dataset  = obj.mibModel.I{id};
            viewPort = dataset.image.viewPort;
            maxInt   = dataset.image.maxInt;

            if ~isa(filteredImg, 'uint8') && ~obj.mibModel.onFlyImageStretch
                if size(filteredImg, 3) == 1
                    colCh = dataset.selectedColorChannel;
                    if viewPort.min(colCh) ~= 0 || viewPort.max(colCh) ~= maxInt || viewPort.gamma(colCh) ~= 1
                        filteredImg = imadjust(filteredImg, ...
                            [viewPort.min(colCh)/maxInt viewPort.max(colCh)/maxInt], [0 1], viewPort.gamma(colCh));
                    end
                else
                    for colCh = 1:size(filteredImg, 3)
                        filteredImg(:,:,colCh) = imadjust(filteredImg(:,:,colCh), ...
                            [viewPort.min(colCh)/maxInt viewPort.max(colCh)/maxInt], [0 1], viewPort.gamma(colCh));
                    end
                end
                filteredImg = uint8(filteredImg / 256);
            end

            showSettings.resizeToMagnification = true;
            showSettings.sImgIn = filteredImg;
            notify(obj.mibModel, 'ShowImage', core.ToggleEventData(showSettings));
        end

    end
end
