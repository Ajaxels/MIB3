classdef MorphOps < handle
% MORPHOPS - Controller for morphological operations on the selection layer.
%
% Applies ``bwmorph``, ``bwmorph3``, ``bwskel``, and ``bwulterode`` to the
% selection layer in 2D (slice or stack) or 3D mode.
%
% Launch as GUI tool::
%
%   obj.mibController.startController('controllers.MorphOps');
%
% Launch in batch mode::
%
%   BatchOpt.Objects3D      = false;
%   BatchOpt.MorphOperation = {'thin'};
%   BatchOpt.ApplyTo   = {'Stack'};
%   BatchOpt.IterationsMode      = {'Infinite'};
%   BatchOpt.showWaitbar    = false;
%   obj.mibController.startController('controllers.MorphOps', [], BatchOpt);
%
% Trigger return of possible options::
%
%   obj.mibController.startController('controllers.MorphOps', [], NaN);
%

    properties
        mibModel
        % handle to MibModel
        view
        % handle to the view (views.MorphOpsGUI)
        mibGUI
        % handle to main MIB figure (used as parent for dialogs)
        listener
        % cell array of listener handles
        BatchOpt
        % structure compatible with batch processing; field names match widget Tags
        autoPreview = false
        % when true, every widget change fires previewButtonPushed (2D mode only)
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
        Calculate(obj, batchModeSwitch)

        % -----------------------------------------------------------
        function obj = MorphOps(mibModel, varargin)
            % MORPHOPS - Constructor.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj = MorphOps(mibModel)
            %       obj = MorphOps(mibModel, [], BatchOpt)
            %
            obj.mibModel = mibModel;
            obj.mibGUI   = mibModel.mibGUI;

            id = obj.mibModel.getActiveId();

            obj.BatchOpt.Objects3D = false;
            obj.BatchOpt.MorphOperation{1} = 'branchpoints';
            obj.BatchOpt.MorphOperation{2} = {'branchpoints', 'bwulterode', 'clean', 'diag', 'endpoints', 'fill', 'majority', 'remove', 'skel', 'spur', 'thin'};
            obj.BatchOpt.ApplyTo{1} = 'CurrentSlice';
            obj.BatchOpt.ApplyTo{2} = {'CurrentSlice', 'Stack'};
            obj.BatchOpt.IterationsMode{1} = 'limitTo';
            obj.BatchOpt.IterationsMode{2} = {'limitTo', 'Infinite'};
            obj.BatchOpt.Iterations = {1, [1 Inf], 'on'};
            obj.BatchOpt.RemoveBranches = false;
            obj.BatchOpt.Connectivity{1} = '4';
            obj.BatchOpt.Connectivity{2} = {'4', '8'};
            obj.BatchOpt.BwulterodeMode{1} = '2D';
            obj.BatchOpt.BwulterodeMode{2} = {'2D', '3D'};
            obj.BatchOpt.Method{1} = 'euclidean';
            obj.BatchOpt.Method{2} = {'euclidean', 'cityblock', 'chessboard', 'quasi-euclidean'};
            obj.BatchOpt.showWaitbar = true;
            obj.BatchOpt.id = id;

            % Restore last-used settings from session
            if isfield(obj.mibModel.sessionSettings, 'morphOpsImages')
                ss = obj.mibModel.sessionSettings.morphOpsImages;
                if isfield(ss, 'Objects3D') && islogical(ss.Objects3D)
                    obj.BatchOpt.Objects3D = ss.Objects3D;
                end
                if isfield(ss, 'MorphOperation') && ismember(ss.MorphOperation, obj.BatchOpt.MorphOperation{2})
                    obj.BatchOpt.MorphOperation{1} = ss.MorphOperation;
                end
            end

            obj.BatchOpt.mibBatchSectionName = 'Ribbon -> Selection';
            obj.BatchOpt.mibBatchActionName  = 'Morphological operations';
            obj.BatchOpt.mibBatchTooltip.Objects3D              = 'Use 3D operations (bwmorph3/bwskel) when true; 2D operations (bwmorph) when false';
            obj.BatchOpt.mibBatchTooltip.MorphOperation         = '2D or 3D morphological operation to apply';
            obj.BatchOpt.mibBatchTooltip.ApplyTo           = 'Apply to current slice only or the whole stack (2D mode)';
            obj.BatchOpt.mibBatchTooltip.IterationsMode         = 'Apply a fixed number of iterations (limitTo) or run until convergence (infinite)';
            obj.BatchOpt.mibBatchTooltip.Iterations             = 'Number of iterations when IterationsMode is limitTo';
            obj.BatchOpt.mibBatchTooltip.RemoveBranches         = 'Remove branches after thinning or skeletonization (skel/thin with infinite iterations)';
            obj.BatchOpt.mibBatchTooltip.Connectivity = 'Connectivity value for bwulterode (2D: 4/8; 3D: 6/18/26)';
            obj.BatchOpt.mibBatchTooltip.BwulterodeMode        = 'Use 2D (connectivity 4/8) or 3D (connectivity 6/18/26) mode for bwulterode';
            obj.BatchOpt.mibBatchTooltip.Method       = 'Method for bwulterode: infinity or euclidean';
            obj.BatchOpt.mibBatchTooltip.showWaitbar            = 'Show or not the progress bar during execution';

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
                obj.updateMorphOperationList();
                obj.updateConnectivityList();
                obj.Calculate(true);
                notify(obj, 'CloseEvent');
                return;
            end

            %% Virtual mode guard
            if any(obj.mibModel.I{id}.datasetType(1) == ['V' 'B'])
                dlgOpt.MsgBoxOnly = true;
                dlgOpt.Icon = 'puffin_warning';
                utils.dlgs.inputUniversalDlg(obj.mibModel.getProgressBarParent(), '', {''}, ...
                    {'Morphological operations are not available in virtual or BigData mode.\nPlease switch to the memory-resident mode and try again.'}, ...
                    'Not implemented', dlgOpt);
                notify(obj, 'CloseEvent');
                return;
            end

            %% GUI mode
            obj.view = core.ChildView(obj, 'views.MorphOpsGUI');
            obj.view.gui = utils.moveWindowOutside(obj.view.gui, obj.mibGUI, 'left');

            Font = obj.mibModel.preferences.System.Font;
            if obj.view.handles.continueButton.FontSize ~= Font.FontSize || ...
                    ~strcmp(obj.view.handles.continueButton.FontName, Font.FontName)
                utils.fontSizeUpdate(obj.view.gui, Font);
            end

            %obj.view.handles.ulterosionPanel.Parent = obj.view.handles.IterationsMode;

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
            obj.view.handles.Objects3D.ValueChangedFcn          = @(h,e) obj.objects3DChanged(e);
            obj.view.handles.Mode.SelectionChangedFcn           = @(h,e) obj.modeSelectionChanged(e);
            obj.view.handles.MorphOperation.ValueChangedFcn     = @(h,e) obj.operationChanged(e);
            obj.view.handles.ApplyTo.SelectionChangedFcn   = @(h,e) obj.updateBatchOptFromGUI(e);
            obj.view.handles.IterationsMode.SelectionChangedFcn = @(h,e) obj.iterationsModeChanged(e);
            obj.view.handles.Iterations.ValueChangedFcn         = @(h,e) obj.updateBatchOptFromGUI(e);
            obj.view.handles.RemoveBranches.ValueChangedFcn     = @(h,e) obj.updateBatchOptFromGUI(e);
            obj.view.handles.Connectivity.ValueChangedFcn = @(h,e) obj.updateBatchOptFromGUI(e);
            obj.view.handles.Method.ValueChangedFcn   = @(h,e) obj.updateBatchOptFromGUI(e);
            
            obj.view.handles.autoPreview.ValueChangedFcn        = @(h,e) obj.autoPreviewChanged(e);
            obj.view.handles.previewButton.ButtonPushedFcn      = @(~,~) obj.previewButtonPushed();
            obj.view.handles.continueButton.ButtonPushedFcn     = @(~,~) obj.Calculate();
            obj.view.handles.helpButton.ButtonPushedFcn         = @(~,~) obj.helpButton_Callback();
            obj.view.handles.closeButton.ButtonPushedFcn        = @(~,~) obj.closeWindow();
            obj.view.gui.KeyPressFcn = @(~,e) obj.figureKeyPress(e);
        end

        % -----------------------------------------------------------
        function figureKeyPress(obj, event)
            % FIGUREKEYPRESS - Forward key presses to MIB main window shortcuts.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.MorphOps.figureKeyPress: triggered\n');
            end
            if isempty(event.Character); return; end

            eventData = struct();
            eventData.eventdata = event;
            eventData = core.ToggleEventData(eventData);
            notify(obj.mibModel, 'KeyPressEvent', eventData);
        end

        % -----------------------------------------------------------
        function closeWindow(obj)
            % CLOSEWINDOW - Save session settings, destroy view, fire CloseEvent.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.MorphOps.closeWindow: triggered\n');
            end
            if ~isempty(obj.BatchOpt)
                obj.mibModel.sessionSettings.morphOpsImages.Objects3D      = obj.BatchOpt.Objects3D;
                obj.mibModel.sessionSettings.morphOpsImages.MorphOperation  = obj.BatchOpt.MorphOperation{1};
            end
            if ~isempty(obj.view) && isvalid(obj.view.gui); delete(obj.view.gui); end
            for i = 1:numel(obj.listener); delete(obj.listener{i}); end
            notify(obj, 'CloseEvent');
        end

        % -----------------------------------------------------------
        function updateMorphOperationList(obj)
            % UPDATEMORPHOPERATIONLIST - Refresh MorphOperation dropdown items to match Objects3D state.
            if obj.BatchOpt.Objects3D
                currentList = {'branchpoints', 'clean', 'endpoints', 'fill', 'majority', 'remove', 'skel'};
            else
                currentList = {'branchpoints', 'bwulterode', 'diag', 'endpoints', 'skel', 'spur', 'thin'};
            end
            if ~ismember(obj.BatchOpt.MorphOperation{1}, currentList)
                obj.BatchOpt.MorphOperation{1} = currentList{1};
            end
            if ~isempty(obj.view) && isvalid(obj.view.gui)
                obj.view.handles.MorphOperation.Items = currentList;
                obj.view.handles.MorphOperation.Value = obj.BatchOpt.MorphOperation{1};
            end
        end

        % -----------------------------------------------------------
        function updateConnectivityList(obj)
            % UPDATECONNECTIVITYLIST - Refresh Connectivity items to match BwulterodeMode.
            if strcmp(obj.BatchOpt.BwulterodeMode{1}, '3D')
                newList = {'6', '18', '26'};
            else
                newList = {'4', '8'};
            end
            obj.BatchOpt.Connectivity{2} = newList;
            if ~ismember(obj.BatchOpt.Connectivity{1}, newList)
                obj.BatchOpt.Connectivity{1} = newList{1};
            end
            if ~isempty(obj.view) && isvalid(obj.view.gui)
                obj.view.handles.Connectivity.Items = newList;
                obj.view.handles.Connectivity.Value = obj.BatchOpt.Connectivity{1};
            end
        end

        % -----------------------------------------------------------
        function updateWidgets(obj)
            % UPDATEWIDGETS - Refresh widgets to reflect current model state.
            obj.BatchOpt.id = obj.mibModel.getActiveId();
            utils.updateGUIFromBatchOpt_Shared(obj.view, obj.BatchOpt);
            obj.updateMorphOperationList();
            obj.updateConnectivityList();
            obj.applyUIRules();
        end

        % -----------------------------------------------------------
        function updateBatchOptFromGUI(obj, event)
            % UPDATEBATCHOPTFROMGUI - Sync BatchOpt from a widget change event.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.MorphOps.updateBatchOptFromGUI(%s): triggered\n', event.Source.Tag);
            end
            obj.BatchOpt = utils.updateBatchOptFromGUI_Shared(obj.BatchOpt, event.Source);
            obj.triggerAutoPreview();
        end

        % -----------------------------------------------------------
        function objects3DChanged(obj, event)
            % OBJECTS3DCHANGED - Handle Objects3D checkbox; switch between 2D/3D morphological operations.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.MorphOps.objects3DChanged: triggered\n');
            end
            obj.BatchOpt.Objects3D = event.Source.Value;
            obj.updateMorphOperationList();
            obj.applyUIRules();
            obj.triggerAutoPreview();
        end

        % -----------------------------------------------------------
        function modeSelectionChanged(obj, event)
            % MODESELECTIONCHANGED - Handle Mode radio change; update bwulterode connectivity dimension.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.MorphOps.modeSelectionChanged: triggered\n');
            end
            if strcmp(event.NewValue.Tag, 'mode3D')
                obj.BatchOpt.BwulterodeMode{1} = '3D';
                obj.BatchOpt.ApplyTo{1} = 'Stack';
                obj.view.handles.Stack.Value = 1;
            else
                obj.BatchOpt.BwulterodeMode{1} = '2D';
            end
            obj.updateConnectivityList();
            obj.triggerAutoPreview();
        end

        % -----------------------------------------------------------
        function operationChanged(obj, event)
            % OPERATIONCHANGED - Handle MorphOperation dropdown change.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.MorphOps.operationChanged: triggered\n');
            end
            obj.BatchOpt = utils.updateBatchOptFromGUI_Shared(obj.BatchOpt, event.Source);
            obj.applyUIRules();
            obj.triggerAutoPreview();
        end

        % -----------------------------------------------------------
        function iterationsModeChanged(obj, event)
            % ITERATIONSMODECHANGED - Handle limitTo/infinite radio switch.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.MorphOps.iterationsModeChanged: triggered\n');
            end
            obj.BatchOpt = utils.updateBatchOptFromGUI_Shared(obj.BatchOpt, event.Source);
            obj.applyUIRules();
            obj.triggerAutoPreview();
        end

        % -----------------------------------------------------------
        function autoPreviewChanged(obj, event)
            % AUTOPREVIEWCHANGED - Handle autoPreview checkbox toggle.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.MorphOps.autoPreviewChanged: triggered\n');
            end
            obj.autoPreview = event.Source.Value;
            obj.triggerAutoPreview();
        end

        % -----------------------------------------------------------
        function triggerAutoPreview(obj)
            % TRIGGERAUTPREVIEW - Fire preview if autoPreview is on and in 2D mode.
            if obj.autoPreview && ~obj.BatchOpt.Objects3D
                obj.previewButtonPushed();
            end
        end

        % -----------------------------------------------------------
        function applyUIRules(obj)
            % APPLYUIRULES - Enforce all enable/visible rules from current BatchOpt state.
            is2D      = ~obj.BatchOpt.Objects3D;
            currentOp = obj.BatchOpt.MorphOperation{1};

            % Sync bwulterode Mode radio buttons (inside ulterosionPanel)
            if strcmp(obj.BatchOpt.BwulterodeMode{1}, '3D')
                obj.view.handles.Mode.SelectedObject = obj.view.handles.mode3D;
            else
                obj.view.handles.Mode.SelectedObject = obj.view.handles.mode2D;
            end

            % ApplyTo only applies in 2D mode
            if is2D
                obj.view.handles.ApplyTo.Enable = 'on';
            else
                obj.view.handles.ApplyTo.Enable = 'off';
                obj.view.handles.ApplyTo.SelectedObject = obj.view.handles.Stack;
                obj.BatchOpt.ApplyTo{1} = 'Stack';
            end

            if is2D && strcmp(currentOp, 'bwulterode')
                obj.view.handles.IterationsMode.Visible  = 'off';
                obj.view.handles.ulterosionPanel.Visible = 'on';
                obj.view.handles.RemoveBranches.Enable = 'off';
                obj.view.handles.RemoveBranches.Value  = false;
                obj.BatchOpt.RemoveBranches = false;
            else
                obj.view.handles.IterationsMode.Visible  = 'on';
                obj.view.handles.ulterosionPanel.Visible = 'off';

                isSkel = strcmp(currentOp, 'skel');

                if ~is2D && ~isSkel
                    % 3D non-skel: iterations not applicable - disable all iteration controls
                    obj.view.handles.limitTo.Enable          = 'off';
                    obj.view.handles.Infinite.Enable         = 'off';
                    obj.view.handles.Iterations.Enable       = 'off';
                    obj.view.handles.iterationsLabel.Enable  = 'off';
                else
                    obj.view.handles.limitTo.Enable          = 'on';
                    obj.view.handles.iterationsLabel.Enable  = 'on';

                    if isSkel
                        % skel (2D or 3D): bwskel requires finite MinBranchLength
                        obj.view.handles.Infinite.Enable = 'off';
                        obj.view.handles.limitTo.Value = true;
                        obj.BatchOpt.IterationsMode{1} = 'limitTo';
                        obj.view.handles.iterationsLabel.Text = 'Min branch length:';
                    else
                        obj.view.handles.Infinite.Enable = 'on';
                        obj.view.handles.iterationsLabel.Text = 'Iterations number:';
                    end

                    isLimitTo = strcmp(obj.BatchOpt.IterationsMode{1}, 'limitTo');
                    obj.view.handles.Iterations.Enable = isLimitTo;
                end

                % RemoveBranches: skel always (2D only); thin with infinite iterations (2D only)
                isLimitTo = strcmp(obj.BatchOpt.IterationsMode{1}, 'limitTo');
                canRemove = is2D && (isSkel || (strcmp(currentOp, 'thin') && ~isLimitTo));
                obj.view.handles.RemoveBranches.Enable = canRemove;
                if ~canRemove
                    obj.view.handles.RemoveBranches.Value = false;
                    obj.BatchOpt.RemoveBranches = false;
                end
            end

            % Preview controls - only meaningful in 2D mode
            obj.view.handles.previewButton.Enable = is2D;
            obj.view.handles.autoPreview.Enable   = is2D;
            if ~is2D
                obj.view.handles.autoPreview.Value = false;
                obj.autoPreview = false;
            end

            obj.view.handles.infoText.Text = obj.getInfoText();
        end

        % -----------------------------------------------------------
        function infoText = getInfoText(obj)
            % GETINFOTEXT - Return description string for the currently selected operation.
            operation = obj.BatchOpt.MorphOperation{1};

            switch operation
                case 'branchpoints'
                    infoText = sprintf('Find branch points of skeleton.\nBranch points are the pixels at the junction where multiple branches meet.\nTo find branch points, the image must be skeletonized.');
                case 'bwulterode'
                    infoText = sprintf('The ultimate erosion computes the ultimate erosion of the selection.\n0 1 1 1  ->  0 0 0 0\n0 1 1 1  ->  0 0 1 0\n0 1 1 1  ->  0 0 0 0\n0 0 0 0  ->  0 0 0 0');
                case 'clean'
                    infoText = sprintf('Remove isolated voxels.\nAn isolated voxel is an individual voxel set to 1 surrounded by voxels set to 0.');
                case 'diag'
                    infoText = sprintf('Uses diagonal fill to eliminate 8-connectivity of the background.\n1 0  ->  1 1\n0 1  ->  1 1');
                case 'endpoints'
                    infoText = sprintf('Find end points of skeleton.\n1 0 0  ->  1 0 0\n0 1 0  ->  0 0 0\n0 0 1  ->  0 0 1');
                case 'fill'
                    infoText = sprintf('Fill isolated interior voxels, setting them to 1.\nIsolated interior voxels are individual voxels set to 0 surrounded (6-connected) by voxels set to 1.');
                case 'majority'
                    infoText = sprintf('Keep a voxel set to 1 if 14 or more voxels (the majority) in its 3x3x3, 26-connected neighborhood are set to 1; otherwise set to 0.');
                case 'remove'
                    infoText = sprintf('Remove interior voxels, setting them to 0.\nInterior voxels are individual voxels set to 1 surrounded (6-connected) by voxels set to 1.');
                case 'skel'
                    infoText = sprintf('With Iterations = Inf, removes pixels on the boundaries of objects without allowing objects to break apart.\nThe remaining pixels make up the image skeleton. This option preserves the Euler number.');
                case 'spur'
                    infoText = sprintf('Removes spur pixels.\n0 0 0  ->  0 0 0\n0 0 1  ->  0 0 0\n0 1 0  ->  0 1 0\n1 1 0  ->  1 1 0');
                case 'thin'
                    infoText = sprintf('With Iterations = Inf, thins objects to lines.\nAn object without holes shrinks to a minimally connected stroke; an object with holes shrinks to a connected ring. Preserves the Euler number.');
                otherwise
                    infoText = operation;
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
        function helpButton_Callback(obj)
            % HELPBUTTON_CALLBACK - Open documentation in browser.

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.MorphOps.helpButton_Callback: triggered\n');
            end
            helpFilPath = fullfile(fileparts(obj.mibModel.mibPath), 'docs', 'html', 'user-interface', 'ribbon', 'selection', 'selection-morphops.html');
            if isfile(helpFilPath)
                web(helpFilPath, '-browser');
            else
                web('http://mib.helsinki.fi/help/main3/user-interface/ribbon/selection/selection-morphops.html', '-browser');
            end
        end

        % -----------------------------------------------------------
        function morphedSel = applyMorphOp2D(obj, selSlice)
            % APPLYMORPHOP2D - Apply current 2D morphological operation to a selection slice.
            operation    = obj.BatchOpt.MorphOperation{1};
            connectivity = str2double(obj.BatchOpt.Connectivity{1});
            method       = obj.BatchOpt.Method{1};

            if strcmp(obj.BatchOpt.IterationsMode{1}, 'limitTo')
                iterNo = obj.BatchOpt.Iterations{1};
            else
                iterNo = Inf;
            end

            selSlice = squeeze(selSlice);
            if isempty(selSlice) || max(selSlice(:)) == 0
                morphedSel = selSlice;
                return;
            end

            switch operation
                case 'bwulterode'
                    morphedSel = uint8(bwulterode(logical(selSlice), method, connectivity));
                case 'skel'
                    if ~verLessThan('matlab', '9.4')
                        morphedSel = uint8(bwskel(logical(selSlice), 'MinBranchLength', iterNo));
                    else
                        morphedSel = uint8(bwmorph(logical(selSlice), 'skel', iterNo));
                    end
                otherwise
                    morphedSel = uint8(bwmorph(logical(selSlice), operation, iterNo));
            end

            if obj.BatchOpt.RemoveBranches && (strcmp(operation, 'skel') || (strcmp(operation, 'thin') && isinf(iterNo)))
                morphedSel = utils.removeBranches(morphedSel);
            end
        end

        % -----------------------------------------------------------
        function previewButtonPushed(obj)
            % PREVIEWBUTTONPUSHED - Apply 2D operation to current view block and display as overlay.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.MorphOps.previewButtonPushed: triggered\n');
            end
            getDataOptions.blockModeSwitch = 1;
            getDataOptions.id = obj.BatchOpt.id;

            selSlice = cell2mat(obj.mibModel.getData2D('selection', [], [], [], getDataOptions));
            if ~any(selSlice(:)); return; end

            morphedSel = obj.applyMorphOp2D(selSlice);

            % Build preview: normal RGB image with morphed selection overlaid as white
            getRGBimageOptions.blockModeSwitch = 1;
            getRGBimageOptions.resizeToMagnification = false;
            currTransparency = obj.mibModel.preferences.Colors.SelectionTransparency;
            obj.mibModel.preferences.Colors.SelectionTransparency = 1;
            previewRGB = obj.mibModel.getRGBimage(getRGBimageOptions);
            obj.mibModel.preferences.Colors.SelectionTransparency = currTransparency;
            previewRGB(morphedSel == 1) = 255;

            showSettings.resizeToMagnification = true;
            showSettings.sImgIn = previewRGB;
            notify(obj.mibModel, 'ShowImage', core.ToggleEventData(showSettings));
        end

    end
end
