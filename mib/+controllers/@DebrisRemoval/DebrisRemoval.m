classdef DebrisRemoval < handle
% DEBRISREMOVAL - Controller for the Debris removal dialog.
%
% Removes debris artifacts from 3D image stacks by comparing adjacent
% slices and replacing detected outlier regions with interpolated content.
%
% Launch as GUI tool::
%
%   obj.mibController.startController('controllers.DebrisRemoval');
%
% Launch in batch mode::
%
%   BatchOpt.DetectionMode = {'AutomaticDetection'};
%   BatchOpt.IntensityThreshold = {100, [0 Inf], 'on'};
%   obj.mibController.startController('controllers.DebrisRemoval', [], BatchOpt);
%
% Trigger return of possible options::
%
%   obj.mibController.startController('controllers.DebrisRemoval', [], NaN);
%

    properties
        mibModel
        % handle to MibModel
        view
        % handle to the view (views.DebrisRemovalGUI)
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
        function obj = DebrisRemoval(mibModel, varargin)
            % DEBRISREMOVAL - Constructor.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj = DebrisRemoval(mibModel)
            %       obj = DebrisRemoval(mibModel, [], BatchOpt)
            %
            obj.mibModel = mibModel;
            obj.mibGUI   = mibModel.mibGUI;

            obj.BatchOpt.DetectionMode{1} = 'AutomaticDetection';
            obj.BatchOpt.DetectionMode{2} = {'AutomaticDetection', 'MaskedAreas', 'SelectedAreas'};
            obj.BatchOpt.IntensityThreshold = {100, [0 Inf], 'on'};
            obj.BatchOpt.ObjectSizeTheshold = {1000, [0 Inf], 'on'};
            obj.BatchOpt.StrelSize          = {7, [1 Inf], 'on'};
            obj.BatchOpt.HighlightAs{1} = 'mask';
            obj.BatchOpt.HighlightAs{2} = {'mask', 'selection'};
            obj.BatchOpt.showWaitbar = true;
            obj.BatchOpt.id = obj.mibModel.getActiveId();

            obj.BatchOpt.mibBatchSectionName = 'Ribbon -> Image';
            obj.BatchOpt.mibBatchActionName  = 'Tools for Images -> Debris removal';
            obj.BatchOpt.mibBatchTooltip.DetectionMode      = 'Detection mode: automatic or use masked/selected areas';
            obj.BatchOpt.mibBatchTooltip.IntensityThreshold = 'Intensity threshold for detection of debris in the difference of images';
            obj.BatchOpt.mibBatchTooltip.ObjectSizeTheshold = 'Detected objects larger than this value are considered as debris and removed';
            obj.BatchOpt.mibBatchTooltip.StrelSize          = 'Size of the strel element for morphological operations';
            obj.BatchOpt.mibBatchTooltip.HighlightAs        = 'Highlight removed debris as mask or selection layer';
            obj.BatchOpt.mibBatchTooltip.showWaitbar        = 'Show or not the progress bar during execution';

            %% Batch / headless mode
            if nargin == 3
                BatchOptIn = varargin{2};
                if ~isstruct(BatchOptIn)
                    if isnan(BatchOptIn)
                        obj.returnBatchOpt();
                    else
                        utils.dlgs.showErrorDialog([], 'A structure as the 2nd parameter is required!', 'Error');
                    end
                    notify(obj, 'CloseEvent');
                    return;
                end
                obj.BatchOpt = utils.updateBatchOptCombineFields_Shared(obj.BatchOpt, BatchOptIn);
                obj.Calculate('Remove all', true);
                notify(obj, 'CloseEvent');
                return;
            end

            %% GUI mode
            obj.view = core.ChildView(obj, 'views.DebrisRemovalGUI');
            obj.view.gui = utils.moveWindowOutside(obj.view.gui, obj.mibGUI, 'left');
            
            % update font and size
            Font = obj.mibModel.preferences.System.Font;
            if obj.view.handles.removeAllButton.FontSize ~= Font.FontSize ...
                    || ~strcmp(obj.view.handles.removeAllButton.FontName, Font.FontName)
                utils.fontSizeUpdate(obj.view.gui, Font);
            end

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
            obj.view.gui.CloseRequestFcn = @(~,~) obj.closeWindow();
            obj.view.handles.DetectionMode.SelectionChangedFcn  = @(h,e) obj.detectionModeSelectionChanged(e);
            obj.view.handles.IntensityThreshold.ValueChangedFcn = @(h,e) obj.updateBatchOptFromGUI(e);
            obj.view.handles.ObjectSizeTheshold.ValueChangedFcn = @(h,e) obj.updateBatchOptFromGUI(e);
            obj.view.handles.StrelSize.ValueChangedFcn          = @(h,e) obj.updateBatchOptFromGUI(e);
            obj.view.handles.HighlightAs.ValueChangedFcn        = @(h,e) obj.updateBatchOptFromGUI(e);
            obj.view.handles.removeAllButton.ButtonPushedFcn    = @(~,~) obj.Calculate('Remove all');
            obj.view.handles.currentButton.ButtonPushedFcn      = @(~,~) obj.Calculate('Current');
            obj.view.handles.helpButton.ButtonPushedFcn         = @(~,~) obj.helpButton_Callback();
            obj.view.handles.closeButton.ButtonPushedFcn        = @(~,~) obj.closeWindow();
            obj.view.gui.KeyPressFcn = @(~,e) obj.figureKeyPress(e);
        end

        % ---------------------------------------------------------------
        function figureKeyPress(obj, event)
            % FIGUREKEYPRESS - Forward key presses to MIB main window shortcuts.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.DebrisRemoval.figureKeyPress: triggered\n');
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
                fprintf('controllers.DebrisRemoval.closeWindow: triggered\n');
            end
            if isvalid(obj.view.gui); delete(obj.view.gui); end
            for i = 1:numel(obj.listener); delete(obj.listener{i}); end
            notify(obj, 'CloseEvent');
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
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.DebrisRemoval.updateBatchOptFromGUI(%s): triggered\n', event.Source.Tag);
            end
            obj.BatchOpt = utils.updateBatchOptFromGUI_Shared(obj.BatchOpt, event.Source);
        end

        % -----------------------------------------------------------
        function detectionModeSelectionChanged(obj, event)
            % DETECTIONMODESELECTIONCHANGED - Update BatchOpt and toggle mode-dependent widgets.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.DebrisRemoval.detectionModeSelectionChanged: triggered\n');
            end
            obj.BatchOpt = utils.updateBatchOptFromGUI_Shared(obj.BatchOpt, event.Source);
            if strcmp(event.Source.SelectedObject.Tag, 'AutomaticDetection')
                obj.view.handles.ObjectSizeTheshold.Enable = 'on';
                obj.view.handles.IntensityThreshold.Enable = 'on';
                obj.view.handles.StrelSize.Enable = 'on';
                obj.view.handles.HighlightAs.Enable = 'on';
            else
                obj.view.handles.ObjectSizeTheshold.Enable = 'off';
                obj.view.handles.IntensityThreshold.Enable = 'off';
                obj.view.handles.StrelSize.Enable = 'off';
                obj.view.handles.HighlightAs.Enable = 'off';
            end
        end

        % -----------------------------------------------------------
        function helpButton_Callback(obj)
            % HELPBUTTON_CALLBACK - Open documentation in browser.

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.DebrisRemoval.helpButton_Callback: triggered\n');
            end
            helpFilPath = fullfile(fileparts(obj.mibModel.mibPath), 'docs', 'html', 'user-interface', 'ribbon', 'image', 'image-tools-debris.html');
            if isfile(helpFilPath)
                web(helpFilPath, '-browser');
            else
                web('http://mib.helsinki.fi/help/main3/user-interface/ribbon/image/image-tools-debris.html', '-browser');
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
        function Calculate(obj, mode, batchModeSwitch)
            % CALCULATE - Remove debris artifacts from the image stack.
            %
            % Parameters:
            % **mode** *(optional)* — ``'Current'`` processes the current slice only;
            %   ``'Remove all'`` (default) processes the whole stack (slices 2..depth-1).
            % **batchModeSwitch** *(optional)* — ``true`` when called from batch processing;
            %   skips undo backup. Default: ``false``.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.DebrisRemoval.Calculate: triggered\n');
            end
            if nargin < 2; mode = 'Remove all'; end
            if nargin < 3; batchModeSwitch = false; end

            if obj.mibModel.I{obj.BatchOpt.id}.image.colors ~= 1
                utils.dlgs.showErrorDialog(obj.mibModel.getProgressBarParent(), ...
                    'Debris removal is only available for grayscale (single-channel) images!', ...
                    'Wrong image type');
                notify(obj.mibModel, 'StopProtocol');
                return;
            end

            % define parent window
            if isempty(obj.view)   % headless batch mode
                parentFigure = obj.mibModel.mibGUI;
            else
                parentFigure = obj.view.gui;
            end
            if obj.BatchOpt.showWaitbar
                progressBar = uiprogressdlg(parentFigure, 'Value', 0, 'Cancelable', 'on', ...
                    'Message', 'Please wait...', 'Title', 'Debris removal');
            end

            if any(obj.mibModel.I{obj.BatchOpt.id}.datasetType(1) == ['V' 'B'])
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

            currentMode = strcmp(mode, 'Current');

            getDataOptions.id = obj.BatchOpt.id;
            if ~batchModeSwitch
                if currentMode
                    obj.mibModel.backup('image', 0, getDataOptions);
                else
                    obj.mibModel.backup('image', 1, getDataOptions);
                end
            end
            [~, ~, depth] = obj.mibModel.I{obj.BatchOpt.id}.getDatasetDimensions('image');
            progressBarStep = floor(depth/20);
            if currentMode
                z1 = obj.mibModel.I{obj.BatchOpt.id}.getCurrentSliceNumber();
                z2 = z1;
                if z1 < 2 || z2 > depth-1
                    if obj.BatchOpt.showWaitbar; delete(progressBar); end
                    utils.dlgs.showErrorDialog(obj.mibModel.getProgressBarParent(), ...
                        sprintf('The current slice should be between 2 and %d', depth-1), 'Wrong slice');
                    return;
                end
            else
                z1 = 2;
                z2 = depth-1;
            end

            if strcmp(obj.BatchOpt.DetectionMode{1}, 'MaskedAreas')
                maskLayer = 'mask';
            else
                maskLayer = 'selection';
            end

            index = 1;
            for z = z1:z2
                if obj.BatchOpt.showWaitbar && mod(z, progressBarStep)==0
                    if progressBar.CancelRequested
                        delete(progressBar);
                        return;
                    end
                    progressBar.Value = z/depth;
                    progressBar.Message = sprintf('Debris removal, slice %d of %d\nPlease wait...', z, depth);
                end

                if strcmp(obj.BatchOpt.DetectionMode{1}, 'AutomaticDetection')
                    if index > 2
                        I1 = I2;
                        I2 = I3;
                        Iprev = Icurr;
                        Icurr = Inext;
                        Inext = cell2mat(obj.mibModel.getData2D('image', z+1, [], [], getDataOptions));
                        I3 = Inext + imbothat(Inext, strel('disk', obj.BatchOpt.StrelSize{1}, 0));
                    else
                        Iprev = cell2mat(obj.mibModel.getData2D('image', z-1, [], [], getDataOptions));
                        Icurr = cell2mat(obj.mibModel.getData2D('image', z,   [], [], getDataOptions));
                        Inext = cell2mat(obj.mibModel.getData2D('image', z+1, [], [], getDataOptions));
                        I1 = Iprev + imbothat(Iprev, strel('disk', obj.BatchOpt.StrelSize{1}, 0));
                        I2 = Icurr + imbothat(Icurr, strel('disk', obj.BatchOpt.StrelSize{1}, 0));
                        I3 = Inext + imbothat(Inext, strel('disk', obj.BatchOpt.StrelSize{1}, 0));
                    end

                    dI1 = I1 - I2;
                    dI2 = I3 - I2;
                    dI  = dI1 + dI2;

                    S = zeros(size(dI), 'uint8');
                    S(dI > obj.BatchOpt.IntensityThreshold{1}) = 1;
                    CC    = bwconncomp(S, 8);
                    STATS = regionprops(CC, {'Area', 'PixelIdxList'});
                    if numel(STATS) == 0; index = index + 1; continue; end

                    for objId = 1:numel(STATS)
                        if STATS(objId).Area < obj.BatchOpt.ObjectSizeTheshold{1}
                            S(STATS(objId).PixelIdxList) = 0;
                        end
                    end
                    S = imdilate(S, strel('disk', 5, 0));
                    S = imfill(S);
                    S = imerode(S, strel('disk', 3, 0));
                    obj.mibModel.setData2D(S, obj.BatchOpt.HighlightAs{1}, z, [], [], getDataOptions);
                else
                    if index > 2
                        Iprev = Icurr;
                        Icurr = Inext;
                        Inext = cell2mat(obj.mibModel.getData2D('image', z+1, [], [], getDataOptions));
                    else
                        Iprev = cell2mat(obj.mibModel.getData2D('image', z-1, [], [], getDataOptions));
                        Icurr = cell2mat(obj.mibModel.getData2D('image', z,   [], [], getDataOptions));
                        Inext = cell2mat(obj.mibModel.getData2D('image', z+1, [], [], getDataOptions));
                    end
                    S = cell2mat(obj.mibModel.getData2D(maskLayer, z, [], [], getDataOptions));
                end

                Iout   = Icurr;
                Ipatch = Iprev/2 + Inext/2;
                Iout(S == 1) = Ipatch(S == 1);
                obj.mibModel.setData2D(Iout, 'image', z, [], [], getDataOptions);

                index = index + 1;
            end
            if obj.BatchOpt.showWaitbar; delete(progressBar); end

            obj.mibModel.showMask = true;
            notify(obj.mibModel, 'ShowImage');

            if ~currentMode
                if strcmp(obj.BatchOpt.DetectionMode{1}, 'AutomaticDetection')
                    obj.mibModel.I{obj.BatchOpt.id}.image.updateActionLog(sprintf( ...
                        'Debris removal: threshold: %d, size limit: %d, strel: %d', ...
                        obj.BatchOpt.IntensityThreshold{1}, obj.BatchOpt.ObjectSizeTheshold{1}, obj.BatchOpt.StrelSize{1}));
                else
                    obj.mibModel.I{obj.BatchOpt.id}.image.updateActionLog(sprintf( ...
                        'Debris removal using %s', obj.BatchOpt.DetectionMode{1}));
                end
                obj.returnBatchOpt();
            end
        end

    end
end
