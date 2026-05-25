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
%   BatchOpt.Mode           = {'2D'};
%   BatchOpt.MorphOperation = {'thin'};
%   BatchOpt.DatasetScope   = {'3D, Stack'};
%   BatchOpt.IterationsMode = {'infinite'};
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

            obj.BatchOpt.Mode{1} = '2D';
            obj.BatchOpt.Mode{2} = {'2D', '3D'};

            obj.BatchOpt.MorphOperation{1} = 'branchpoints';
            obj.BatchOpt.MorphOperation{2} = {'branchpoints', 'bwulterode', 'diag', 'endpoints', 'skel', 'spur', 'thin'};

            obj.BatchOpt.DatasetScope{1} = '3D, Stack';
            obj.BatchOpt.DatasetScope{2} = {'2D, Slice', '3D, Stack'};

            obj.BatchOpt.IterationsMode{1} = 'limitTo';
            obj.BatchOpt.IterationsMode{2} = {'limitTo', 'infinite'};

            obj.BatchOpt.Iterations = {1, [1 Inf], 'on'};

            obj.BatchOpt.RemoveBranches = false;

            obj.BatchOpt.BwulterodeConnectivity{1} = '4';
            obj.BatchOpt.BwulterodeConnectivity{2} = {'4', '8'};

            obj.BatchOpt.BwulterodeMethod{1} = 'infinity';
            obj.BatchOpt.BwulterodeMethod{2} = {'infinity', 'euclidean'};

            obj.BatchOpt.showWaitbar = true;
            obj.BatchOpt.id = id;

            % Restore last-used settings from session
            if isfield(obj.mibModel.sessionSettings, 'morphOpsImages')
                ss = obj.mibModel.sessionSettings.morphOpsImages;
                if isfield(ss, 'Mode') && ismember(ss.Mode, {'2D', '3D'})
                    obj.BatchOpt.Mode{1} = ss.Mode;
                    obj.updateMorphOperationList();
                end
                if isfield(ss, 'MorphOperation') && ismember(ss.MorphOperation, obj.BatchOpt.MorphOperation{2})
                    obj.BatchOpt.MorphOperation{1} = ss.MorphOperation;
                end
            end

            obj.BatchOpt.mibBatchSectionName = 'Ribbon -> Selection';
            obj.BatchOpt.mibBatchActionName  = 'Tools for Selection -> Morphological operations';
            obj.BatchOpt.mibBatchTooltip.Mode                   = 'Use 2D (bwmorph) or 3D (bwmorph3/bwskel) operations';
            obj.BatchOpt.mibBatchTooltip.MorphOperation         = '2D or 3D morphological operation to apply';
            obj.BatchOpt.mibBatchTooltip.DatasetScope           = 'Apply to current slice only or the whole stack (2D mode)';
            obj.BatchOpt.mibBatchTooltip.IterationsMode         = 'Apply a fixed number of iterations (limitTo) or run until convergence (infinite)';
            obj.BatchOpt.mibBatchTooltip.Iterations             = 'Number of iterations when IterationsMode is limitTo';
            obj.BatchOpt.mibBatchTooltip.RemoveBranches         = 'Remove branches after thinning or skeletonization (skel/thin with infinite iterations)';
            obj.BatchOpt.mibBatchTooltip.BwulterodeConnectivity = 'Connectivity for bwulterode (4 or 8)';
            obj.BatchOpt.mibBatchTooltip.BwulterodeMethod       = 'Method for bwulterode: infinity or euclidean';
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
                obj.updateMorphOperationList();   % ensure {2} matches Mode after merge
                obj.Calculate(true);
                notify(obj, 'CloseEvent');
                return;
            end

            %% Virtual mode guard
            if strcmp(obj.mibModel.I{id}.datasetType, 'Virtual')
                dlgOpt.MsgBoxOnly = true;
                dlgOpt.Icon = 'puffin_warning';
                utils.dlgs.inputUniversalDlg(obj.mibGUI, '', {''}, ...
                    {'Morphological operations are not available in virtual stacking mode.\nPlease switch to the memory-resident mode and try again.'}, ...
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
            obj.view.handles.Mode.ValueChangedFcn               = @(h,e) obj.modeChanged(e);
            obj.view.handles.MorphOperation.ValueChangedFcn     = @(h,e) obj.operationChanged(e);
            obj.view.handles.DatasetScope.SelectionChangedFcn   = @(h,e) obj.updateBatchOptFromGUI(e);
            obj.view.handles.IterationsMode.SelectionChangedFcn = @(h,e) obj.iterationsModeChanged(e);
            obj.view.handles.Iterations.ValueChangedFcn         = @(h,e) obj.updateBatchOptFromGUI(e);
            obj.view.handles.RemoveBranches.ValueChangedFcn     = @(h,e) obj.updateBatchOptFromGUI(e);
            obj.view.handles.BwulterodeConnectivity.ValueChangedFcn = @(h,e) obj.updateBatchOptFromGUI(e);
            obj.view.handles.BwulterodeMethod.ValueChangedFcn   = @(h,e) obj.updateBatchOptFromGUI(e);
            obj.view.handles.showWaitbar.ValueChangedFcn        = @(h,e) obj.updateBatchOptFromGUI(e);
            obj.view.handles.previewButton.ButtonPushedFcn      = @(~,~) obj.previewButtonPushed();
            obj.view.handles.continueButton.ButtonPushedFcn     = @(~,~) obj.Calculate();
            obj.view.handles.helpButton.ButtonPushedFcn         = @(~,~) obj.helpButton_Callback();
            obj.view.handles.closeButton.ButtonPushedFcn        = @(~,~) obj.closeWindow();
            obj.view.gui.KeyPressFcn = @(~,e) obj.figureKeyPress(e);
        end

        % -----------------------------------------------------------
        function figureKeyPress(obj, event)
            % FIGUREKEYPRESS - Forward key presses to MIB main window shortcuts.
            if isempty(event.Character); return; end
            eventData = core.ToggleEventData(struct('eventdata', event));
            notify(obj.mibModel, 'KeyPressEvent', eventData);
        end

        % -----------------------------------------------------------
        function closeWindow(obj)
            % CLOSEWINDOW - Save session settings, destroy view, fire CloseEvent.
            if ~isempty(obj.BatchOpt)
                obj.mibModel.sessionSettings.morphOpsImages.Mode          = obj.BatchOpt.Mode{1};
                obj.mibModel.sessionSettings.morphOpsImages.MorphOperation = obj.BatchOpt.MorphOperation{1};
            end
            if ~isempty(obj.view) && isvalid(obj.view.gui); delete(obj.view.gui); end
            for i = 1:numel(obj.listener); delete(obj.listener{i}); end
            notify(obj, 'CloseEvent');
        end

        % -----------------------------------------------------------
        function updateMorphOperationList(obj)
            % UPDATEMORPHOPERATIONLIST - Update MorphOperation{2} to match current Mode.
            if strcmp(obj.BatchOpt.Mode{1}, '2D')
                newList = {'branchpoints', 'bwulterode', 'diag', 'endpoints', 'skel', 'spur', 'thin'};
            else
                newList = {'branchpoints', 'clean', 'endpoints', 'fill', 'majority', 'remove', 'skel'};
            end
            obj.BatchOpt.MorphOperation{2} = newList;
            if ~ismember(obj.BatchOpt.MorphOperation{1}, newList)
                obj.BatchOpt.MorphOperation{1} = newList{1};
            end
        end

        % -----------------------------------------------------------
        function updateWidgets(obj)
            % UPDATEWIDGETS - Refresh widgets to reflect current model state.
            obj.BatchOpt.id = obj.mibModel.getActiveId();
            utils.updateGUIFromBatchOpt_Shared(obj.view, obj.BatchOpt);
            obj.applyUIRules();
        end

        % -----------------------------------------------------------
        function updateBatchOptFromGUI(obj, event)
            % UPDATEBATCHOPTFROMGUI - Sync BatchOpt from a widget change event.
            obj.BatchOpt = utils.updateBatchOptFromGUI_Shared(obj.BatchOpt, event.Source);
        end

        % -----------------------------------------------------------
        function modeChanged(obj, event)
            % MODECHANGED - Handle 2D/3D mode switch; repopulate MorphOperation list.
            obj.BatchOpt = utils.updateBatchOptFromGUI_Shared(obj.BatchOpt, event.Source);
            obj.updateMorphOperationList();
            obj.view.handles.MorphOperation.Items = obj.BatchOpt.MorphOperation{2};
            obj.view.handles.MorphOperation.Value = obj.BatchOpt.MorphOperation{1};
            obj.applyUIRules();
        end

        % -----------------------------------------------------------
        function operationChanged(obj, event)
            % OPERATIONCHANGED - Handle MorphOperation dropdown change.
            obj.BatchOpt = utils.updateBatchOptFromGUI_Shared(obj.BatchOpt, event.Source);
            obj.applyUIRules();
        end

        % -----------------------------------------------------------
        function iterationsModeChanged(obj, event)
            % ITERATIONSMODECHANGED - Handle limitTo/infinite radio switch.
            obj.BatchOpt = utils.updateBatchOptFromGUI_Shared(obj.BatchOpt, event.Source);
            obj.applyUIRules();
        end

        % -----------------------------------------------------------
        function applyUIRules(obj)
            % APPLYUIRULES - Enforce all enable/visible rules from current BatchOpt state.
            is2D      = strcmp(obj.BatchOpt.Mode{1}, '2D');
            currentOp = obj.BatchOpt.MorphOperation{1};

            % DatasetScope only applies in 2D mode
            if is2D
                obj.view.handles.DatasetScope.Enable = 'on';
            else
                obj.view.handles.DatasetScope.Enable = 'off';
                obj.view.handles.DatasetScope.SelectedObject = obj.view.handles.datasetRadio;
                obj.BatchOpt.DatasetScope{1} = '3D, Stack';
            end

            if is2D && strcmp(currentOp, 'bwulterode')
                obj.view.handles.iterPanel.Visible  = 'off';
                obj.view.handles.ulterPanel.Visible = 'on';
                obj.view.handles.RemoveBranches.Enable = 'off';
                obj.view.handles.RemoveBranches.Value  = false;
                obj.BatchOpt.RemoveBranches = false;
            else
                obj.view.handles.iterPanel.Visible  = 'on';
                obj.view.handles.ulterPanel.Visible = 'off';

                % 2D skel: bwskel requires a finite MinBranchLength — disable infinite
                isSkel2D = is2D && strcmp(currentOp, 'skel');
                if isSkel2D
                    obj.view.handles.infinite.Enable = 'off';
                    obj.view.handles.limitTo.Value = true;
                    obj.BatchOpt.IterationsMode{1} = 'limitTo';
                else
                    obj.view.handles.infinite.Enable = 'on';
                end

                isLimitTo = strcmp(obj.BatchOpt.IterationsMode{1}, 'limitTo');
                obj.view.handles.Iterations.Enable = isLimitTo;

                % RemoveBranches: only when skel or thin in 2D with infinite iterations
                canRemove = is2D && ismember(currentOp, {'skel', 'thin'}) && ~isLimitTo;
                obj.view.handles.RemoveBranches.Enable = canRemove;
                if ~canRemove
                    obj.view.handles.RemoveBranches.Value = false;
                    obj.BatchOpt.RemoveBranches = false;
                end
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
            web(fullfile(obj.mibModel.mibPath, 'techdoc', 'html', 'user-interface', 'menu', 'selection', 'selection-morphops.html'), '-browser');
        end

        % -----------------------------------------------------------
        function morphedSel = applyMorphOp2D(obj, selSlice)
            % APPLYMORPHOP2D - Apply current 2D morphological operation to a selection slice.
            operation    = obj.BatchOpt.MorphOperation{1};
            connectivity = str2double(obj.BatchOpt.BwulterodeConnectivity{1});
            method       = obj.BatchOpt.BwulterodeMethod{1};

            if strcmp(obj.BatchOpt.IterationsMode{1}, 'limitTo')
                iterNo = obj.BatchOpt.Iterations{1};
            else
                iterNo = Inf;
            end

            if max(selSlice(:)) == 0
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
                        morphedSel = uint8(bwmorph(selSlice, 'skel', iterNo));
                    end
                otherwise
                    morphedSel = uint8(bwmorph(selSlice, operation, iterNo));
            end

            if obj.BatchOpt.RemoveBranches && ismember(operation, {'skel', 'thin'}) && isinf(iterNo)
                morphedSel = utils.removeBranches(morphedSel);
            end
        end

        % -----------------------------------------------------------
        function previewButtonPushed(obj)
            % PREVIEWBUTTONPUSHED - Apply 2D operation to current view block and display as overlay.
            getDataOptions.blockModeSwitch = 1;
            getDataOptions.id = obj.BatchOpt.id;

            selSlice = cell2mat(obj.mibModel.getData2D('selection', [], [], [], getDataOptions));
            if ~any(selSlice(:)); return; end

            morphedSel = obj.applyMorphOp2D(selSlice);

            imgSlice  = cell2mat(obj.mibModel.getData2D('image', [], [], 0, getDataOptions));
            dataClass = obj.mibModel.I{obj.BatchOpt.id}.image.dataClass;
            maxVal    = double(intmax(dataClass));
            grayBg    = uint8(double(imgSlice(:,:,1)) / maxVal * 160);
            previewRGB = repmat(grayBg, [1 1 3]);
            highlight  = uint8(double(morphedSel) * 95);
            previewRGB(:,:,2) = min(255, previewRGB(:,:,2) + highlight);
            previewRGB(:,:,3) = min(255, previewRGB(:,:,3) + highlight);

            showSettings.resizeToMagnification = true;
            showSettings.sImgIn = previewRGB;
            notify(obj.mibModel, 'ShowImage', core.ToggleEventData(showSettings));
        end

    end
end
