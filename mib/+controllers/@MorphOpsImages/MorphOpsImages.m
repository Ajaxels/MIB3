classdef MorphOpsImages < handle
% MORPHOPSIMAGES - Controller for morphological operations on the image layer.
%
% Applies imbothat, imclearborder, imclose, imdilate, imerode, imfill,
% imhmax, imhmin, imopen, imtophat to the image layer in 2D (slice or
% stack), 3D, or 4D mode.
%
% Launch as GUI tool::
%
%   obj.mibController.startController('controllers.MorphOpsImages');
%   obj.mibController.startController('controllers.MorphOpsImages', 'Dilate image');
%
% Launch in batch mode::
%
%   BatchOpt.MorphOperation = {'Dilate image'};
%   BatchOpt.DatasetType    = {'3D, Stack'};
%   obj.mibController.startController('controllers.MorphOpsImages', [], BatchOpt);
%
% Trigger return of default options::
%
%   obj.mibController.startController('controllers.MorphOpsImages', [], NaN);
%

    properties
        mibModel
        % handle to MibModel
        view
        % handle to the view (views.MorphOpsImagesGUI)
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
                case 'SliceChanged'
                    if obj.view.handles.autoPreviewCheck.Value
                        obj.previewButtonPushed();
                    end
            end
        end
    end

    methods
        % External method file declarations
        Calculate(obj, batchModeSwitch)

        % -----------------------------------------------------------
        function obj = MorphOpsImages(mibModel, varargin)
            % MORPHOPSIMAGES - Constructor.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj = MorphOpsImages(mibModel)
            %       obj = MorphOpsImages(mibModel, initialOperation)
            %       obj = MorphOpsImages(mibModel, [], BatchOpt)
            %
            obj.mibModel = mibModel;
            obj.mibGUI   = mibModel.mibGUI;

            id = obj.mibModel.getActiveId();
            colorCount = obj.mibModel.I{id}.image.colors;
            possibleColorChannels = arrayfun(@(x) sprintf('ColCh %d', x), 1:colorCount, 'UniformOutput', false);

            initialOperation = 'Bottom-hat filtering';
            if numel(varargin) >= 1 && ~isempty(varargin{1}) && ischar(varargin{1})
                initialOperation = varargin{1};
            end

            obj.BatchOpt.MorphOperation    = {initialOperation};
            obj.BatchOpt.MorphOperation{2} = {'Bottom-hat filtering','Clear border','Morphological closing', ...
                'Dilate image','Erode image','Fill regions','H-maxima transform','H-minima transform', ...
                'Morphological opening','Top-hat filtering'};
            obj.BatchOpt.DatasetType    = {'2D, Slice'};
            obj.BatchOpt.DatasetType{2} = {'2D, Slice','3D, Stack','4D, Dataset'};
            obj.BatchOpt.Mode    = {'2D'};
            obj.BatchOpt.Mode{2} = {'2D','3D'};
            obj.BatchOpt.ColorChannel    = {'All'};
            obj.BatchOpt.ColorChannel{2} = [{'All'}, possibleColorChannels];
            obj.BatchOpt.ActionToResult    = {'None'};
            obj.BatchOpt.ActionToResult{2} = {'None','AddToImage','SubtractFromImage'};
            obj.BatchOpt.StrelShape    = {'rectangle'};
            obj.BatchOpt.StrelShape{2} = {'rectangle','disk'};
            obj.BatchOpt.StrelSize     = '7';
            obj.BatchOpt.Connectivity    = {'4'};
            obj.BatchOpt.Connectivity{2} = {'4','8'};
            obj.BatchOpt.Multiply    = {1,   [0 Inf], 'off'};
            obj.BatchOpt.SmoothHSize = {0,   [0 Inf], 'on'};
            obj.BatchOpt.SmoothSigma = {0.0, [0 Inf], 'off'};
            obj.BatchOpt.showWaitbar = true;
            obj.BatchOpt.id = id;

            obj.BatchOpt.mibBatchSectionName = 'Ribbon -> Image';
            obj.BatchOpt.mibBatchActionName  = 'Morphological operations for images';
            obj.BatchOpt.mibBatchTooltip.MorphOperation  = 'Morphological operation to apply to the image';
            obj.BatchOpt.mibBatchTooltip.DatasetType     = 'Apply to current slice (2D, Slice), whole stack (3D, Stack), or complete dataset (4D, Dataset)';
            obj.BatchOpt.mibBatchTooltip.Mode            = 'Clear border, H-maxima, H-minima can also run in 3D mode';
            obj.BatchOpt.mibBatchTooltip.ColorChannel    = 'Color channel to process; All = process all channels';
            obj.BatchOpt.mibBatchTooltip.ActionToResult  = 'How to combine the morphological result with the original image';
            obj.BatchOpt.mibBatchTooltip.StrelShape      = 'Shape of the structuring element (rectangle or disk)';
            obj.BatchOpt.mibBatchTooltip.StrelSize       = 'Size(s) of the structuring element; enter two values for anisotropic (e.g. 7 3)';
            obj.BatchOpt.mibBatchTooltip.Connectivity    = 'Connectivity: 4/8 in 2D mode; 6/18/26 in 3D mode';
            obj.BatchOpt.mibBatchTooltip.Multiply        = 'Multiply the operation result by this factor before combining with original';
            obj.BatchOpt.mibBatchTooltip.SmoothHSize     = 'Gaussian smoothing kernel size applied to result (0 = disabled)';
            obj.BatchOpt.mibBatchTooltip.SmoothSigma     = 'Gaussian sigma used when SmoothHSize > 0';
            obj.BatchOpt.mibBatchTooltip.showWaitbar     = 'Show or hide the progress bar during execution';

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
                    {sprintf('Morphological operations are not available in virtual or BigData mode.\nPlease switch to the memory-resident mode and try again.')}, ...
                    'Not implemented', dlgOpt);
                notify(obj, 'CloseEvent');
                return;
            end

            %% GUI mode
            obj.view = core.ChildView(obj, 'views.MorphOpsImagesGUI');
            obj.view.gui = utils.moveWindowOutside(obj.view.gui, obj.mibGUI, 'left');

            Font = obj.mibModel.preferences.System.Font;
            if obj.view.handles.continueButton.FontSize ~= Font.FontSize || ...
                    ~strcmp(obj.view.handles.continueButton.FontName, Font.FontName)
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
            handles.MorphOperation.ValueChangedFcn   = @(h,e) obj.morphOperationChanged(e);
            handles.DatasetType.ValueChangedFcn      = @(h,e) obj.datasetTypeChanged(e);
            handles.Mode.ValueChangedFcn             = @(h,e) obj.modeChanged(e);
            handles.ColorChannel.ValueChangedFcn     = @(h,e) obj.updateBatchOptFromGUI(e);
            handles.ActionToResult.SelectionChangedFcn   = @(h,e) obj.updateBatchOptFromGUI(e);
            handles.StrelShape.ValueChangedFcn       = @(h,e) obj.updateBatchOptFromGUI(e);
            handles.StrelSize.ValueChangedFcn        = @(h,e) obj.strelOrMultiplyChanged(e);
            handles.Connectivity.ValueChangedFcn     = @(h,e) obj.updateBatchOptFromGUI(e);
            handles.Multiply.ValueChangedFcn         = @(h,e) obj.updateBatchOptFromGUI(e);
            handles.SmoothHSize.ValueChangedFcn      = @(h,e) obj.smoothHSizeChanged(e);
            handles.SmoothSigma.ValueChangedFcn      = @(h,e) obj.updateBatchOptFromGUI(e);
            handles.autoPreviewCheck.ValueChangedFcn = @(h,e) obj.autoPreviewChanged(e);
            handles.previewButton.ButtonPushedFcn    = @(~,~) obj.previewButtonPushed();
            handles.continueButton.ButtonPushedFcn   = @(~,~) obj.Calculate();
            handles.helpButton.ButtonPushedFcn       = @(~,~) obj.helpButton_Callback();
            handles.closeButton.ButtonPushedFcn      = @(~,~) obj.closeWindow();
            obj.view.gui.KeyPressFcn = @(~,e) obj.figureKeyPress(e);
        end

        % -----------------------------------------------------------
        function figureKeyPress(obj, event)
            % FIGUREKEYPRESS - Forward key presses to MIB main window shortcuts.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.MorphOpsImages.figureKeyPress: triggered\n');
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
                fprintf('controllers.MorphOpsImages.closeWindow: triggered\n');
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
                fprintf('controllers.MorphOpsImages.updateBatchOptFromGUI(%s): triggered\n', event.Source.Tag);
            end
            obj.BatchOpt = utils.updateBatchOptFromGUI_Shared(obj.BatchOpt, event.Source);
            obj.triggerAutoPreview();
        end

        % -----------------------------------------------------------
        function updateConnectivityList(obj)
            % UPDATECONNECTIVITYLIST - Refresh Connectivity dropdown items to match Mode.
            if strcmp(obj.BatchOpt.Mode{1}, '3D')
                newItems = {'6','18','26'};
            else
                newItems = {'4','8'};
            end
            obj.BatchOpt.Connectivity{2} = newItems;

            if ~ismember(obj.BatchOpt.Connectivity{1}, newItems)
                obj.BatchOpt.Connectivity{1} = newItems{1};
            end
            if ~isempty(obj.view) && isvalid(obj.view.gui)
                obj.view.handles.Connectivity.Items = newItems;
                obj.view.handles.Connectivity.Value = obj.BatchOpt.Connectivity{1};
            end
        end

        % -----------------------------------------------------------
        function updateWidgets(obj)
            % UPDATEWIDGETS - Refresh widgets to reflect current model state.
            obj.BatchOpt.id = obj.mibModel.getActiveId();
            id = obj.BatchOpt.id;

            % Rebuild color channel list in case dataset changed
            colorCount = obj.mibModel.I{id}.image.colors;
            possibleColorChannels = arrayfun(@(x) sprintf('ColCh %d', x), 1:colorCount, 'UniformOutput', false);
            obj.BatchOpt.ColorChannel{2} = [{'All'}, possibleColorChannels];
            if ~ismember(obj.BatchOpt.ColorChannel{1}, obj.BatchOpt.ColorChannel{2})
                obj.BatchOpt.ColorChannel{1} = 'All';
            end

            utils.updateGUIFromBatchOpt_Shared(obj.view, obj.BatchOpt);
            obj.updateConnectivityList();
            obj.applyUIRules();
        end

        % -----------------------------------------------------------
        function modeChanged(obj, event)
            % MODECHANGED - Handle Mode dropdown change.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.MorphOpsImages.modeChanged: triggered\n');
            end
            obj.BatchOpt = utils.updateBatchOptFromGUI_Shared(obj.BatchOpt, event.Source);
            obj.updateConnectivityList();
            obj.applyUIRules();
            obj.triggerAutoPreview();
        end

        % -----------------------------------------------------------
        function morphOperationChanged(obj, event)
            % MORPHOPERATIONCHANGED - Handle MorphOperation dropdown change.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.MorphOpsImages.morphOperationChanged: triggered\n');
            end
            obj.BatchOpt = utils.updateBatchOptFromGUI_Shared(obj.BatchOpt, event.Source);
            obj.applyUIRules();
            obj.triggerAutoPreview();
        end

        % -----------------------------------------------------------
        function datasetTypeChanged(obj, event)
            % DATASETTYPECHANGED - Handle DatasetType change; force Mode=2D for slice-only scope.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.MorphOpsImages.datasetTypeChanged: triggered\n');
            end
            obj.BatchOpt = utils.updateBatchOptFromGUI_Shared(obj.BatchOpt, event.Source);
            if strcmp(obj.BatchOpt.DatasetType{1}, '2D, Slice')
                obj.BatchOpt.Mode{1} = '2D';
                obj.view.handles.Mode.Value = '2D';
                obj.updateConnectivityList();
            end
            obj.applyUIRules();
            obj.triggerAutoPreview();
        end

        % -----------------------------------------------------------
        function strelOrMultiplyChanged(obj, event)
            % STRELORCHANGED - Handle StrelSize text edit change.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.MorphOpsImages.strelOrMultiplyChanged: triggered\n');
            end
            obj.BatchOpt = utils.updateBatchOptFromGUI_Shared(obj.BatchOpt, event.Source);
            obj.triggerAutoPreview();
        end

        % -----------------------------------------------------------
        function smoothHSizeChanged(obj, event)
            % SMOOTHHSIZECHANGED - Handle SmoothHSize change; auto-set SmoothSigma = size/5.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.MorphOpsImages.smoothHSizeChanged: triggered\n');
            end
            obj.BatchOpt = utils.updateBatchOptFromGUI_Shared(obj.BatchOpt, event.Source);
            newSigma = obj.BatchOpt.SmoothHSize{1} / 5;
            obj.BatchOpt.SmoothSigma{1} = newSigma;
            obj.view.handles.SmoothSigma.Value = newSigma;
            obj.triggerAutoPreview();
        end

        % -----------------------------------------------------------
        function autoPreviewChanged(obj, event)
            % AUTOPREVIEWCHANGED - Handle autoPreview checkbox; fire preview if just checked.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.MorphOpsImages.autoPreviewChanged: triggered\n');
            end
            if event.Source.Value
                obj.previewButtonPushed();
            end
        end

        % -----------------------------------------------------------
        function triggerAutoPreview(obj)
            % TRIGGERAUTPREVIEW - Fire preview when autoPreview is on and Mode is 2D.
            if isempty(obj.view) || ~isvalid(obj.view.gui); return; end
            if obj.view.handles.autoPreviewCheck.Value && strcmp(obj.BatchOpt.Mode{1}, '2D')
                obj.previewButtonPushed();
            end
        end

        % -----------------------------------------------------------
        function applyUIRules(obj)
            % APPLYUIRULES - Enforce all widget enable/visible rules from current BatchOpt state.
            if isempty(obj.view) || ~isvalid(obj.view.gui); return; end
            handles   = obj.view.handles;
            currentOp = obj.BatchOpt.MorphOperation{1};
            is3D      = strcmp(obj.BatchOpt.Mode{1}, '3D');

            % Mode is only meaningful for ops that support 3D
            ops3DCapable = {'Clear border','H-maxima transform','H-minima transform'};
            if ismember(currentOp, ops3DCapable)
                handles.Mode.Enable = 'on';
            else
                obj.BatchOpt.Mode{1} = '2D';
                handles.Mode.Value   = '2D';
                handles.Mode.Enable  = 'off';
                is3D = false;
                obj.updateConnectivityList();
            end

            % Strel controls only for strel-based operations
            strelOps = {'Bottom-hat filtering','Morphological closing','Dilate image', ...
                        'Erode image','Morphological opening','Top-hat filtering'};
            useStrel = ismember(currentOp, strelOps);
            handles.StrelShape.Enable = useStrel;
            handles.StrelSize.Enable  = useStrel;

            % Connectivity only for connectivity-based operations
            connOps = {'Clear border','H-maxima transform','H-minima transform'};
            handles.Connectivity.Enable = ismember(currentOp, connOps);

            % Preview / auto-preview / smoothing only in 2D mode
            handles.previewButton.Enable    = ~is3D;
            handles.autoPreviewCheck.Enable = ~is3D;
            handles.SmoothHSize.Enable      = ~is3D;
            handles.SmoothSigma.Enable      = ~is3D;
            if is3D
                handles.autoPreviewCheck.Value = false;
            end

            % Info text and preview illustration
            handles.infoText.Text = obj.getInfoText();
            obj.loadPreviewImage();
        end

        % -----------------------------------------------------------
        function loadPreviewImage(obj)
            % LOADPREVIEWIMAGE - Load operation illustration from Resources folder.
            if isempty(obj.view) || ~isvalid(obj.view.gui); return; end
            operationFileMap = dictionary( ...
                {'Bottom-hat filtering','Clear border','Morphological closing','Dilate image', ...
                 'Erode image','Fill regions','H-maxima transform','H-minima transform', ...
                 'Morphological opening','Top-hat filtering'}, ...
                {'morphops_imbothat','morphops_imclearborder','morphops_imclose','morphops_imdilate', ...
                 'morphops_imerode','morphops_imfill','morphops_imhmax','morphops_imhmin', ...
                 'morphops_imopen','morphops_imtophat'});
            imageName = operationFileMap{obj.BatchOpt.MorphOperation(1)};
            imagePath = fullfile(obj.mibModel.mibPath, 'assets', 'images', [imageName '.jpg']);
            if exist(imagePath, 'file') == 2
                obj.view.handles.previewAxes.ImageSource = imagePath;
            end
        end

        % -----------------------------------------------------------
        function infoText = getInfoText(obj)
            % GETINFOTEXT - Return description for the currently selected operation.
            switch obj.BatchOpt.MorphOperation{1}
                case 'Bottom-hat filtering'
                    infoText = 'Computes the morphological closing of the image (using imclose) and then subtracts the result from the original image';
                case 'Clear border'
                    infoText = 'Suppresses light structures connected to image border';
                case 'Morphological closing'
                    infoText = 'Morphologically close image: a dilation followed by an erosion';
                case 'Dilate image'
                    infoText = 'Dilate image';
                case 'Erode image'
                    infoText = 'Erode image';
                case 'Fill regions'
                    infoText = 'Fills holes in the image, where a hole is defined as an area of dark pixels surrounded by lighter pixels';
                case 'H-maxima transform'
                    infoText = 'Suppresses all maxima in the image whose height is less than H';
                case 'H-minima transform'
                    infoText = 'Suppresses all minima in the image whose depth is less than H';
                case 'Morphological opening'
                    infoText = 'Morphologically open image: an erosion followed by a dilation';
                case 'Top-hat filtering'
                    infoText = 'Computes the morphological opening of the image (using imopen) and then subtracts the result from the original image';
                otherwise
                    infoText = '';
            end
        end

        % -----------------------------------------------------------
        function se = getStrelElement(obj)
            % GETSTRELELEMENT - Build strel element from current BatchOpt settings.
            sizeValues = str2num(obj.BatchOpt.StrelSize); %#ok<ST2NM>
            id = obj.BatchOpt.id;
            is3D = strcmp(obj.BatchOpt.Mode{1}, '3D');

            if is3D
                if isscalar(sizeValues)
                    sizeValues(2) = max([round(sizeValues(1) * obj.mibModel.I{id}.image.pixSize.x / ...
                        obj.mibModel.I{id}.image.pixSize.z), 1]);
                end
            elseif isscalar(sizeValues)
                sizeValues(2) = sizeValues(1);
            end

            if strcmp(obj.BatchOpt.StrelShape{1}, 'rectangle')
                if is3D
                    se = ones([sizeValues(1), sizeValues(1), sizeValues(2)]);
                else
                    se = strel('rectangle', [sizeValues(1), sizeValues(2)]);
                end
            else  % disk
                if is3D
                    se = zeros(sizeValues(1)*2+1, sizeValues(1)*2+1, sizeValues(2)*2+1);
                    [x,y,z] = meshgrid(-sizeValues(1):sizeValues(1), ...
                                       -sizeValues(1):sizeValues(1), ...
                                       -sizeValues(2):sizeValues(2));
                    ball = sqrt((x/sizeValues(1)).^2 + (y/sizeValues(1)).^2 + (z/sizeValues(2)).^2);
                    se(ball <= 1) = 1;
                else
                    se = strel('disk', sizeValues(1), 0);
                end
            end
        end

        % -----------------------------------------------------------
        function processedImage = applyOperation2D(obj, imageSlice)
            % APPLYOPERATION2D - Apply current 2D operation to a single image slice.
            %
            % Input/output are plain matrices (not cells); multi-channel supported.
            %
            se             = obj.getStrelElement();
            hValue         = str2num(obj.BatchOpt.StrelSize); %#ok<ST2NM>
            conn           = str2double(obj.BatchOpt.Connectivity{1});
            smoothHSize    = obj.BatchOpt.SmoothHSize{1};
            smoothSigma    = obj.BatchOpt.SmoothSigma{1};
            multiplyFactor = obj.BatchOpt.Multiply{1};

            if smoothHSize > 0
                smoothFilter = fspecial('gaussian', smoothHSize, smoothSigma);
            end

            processedImage = zeros(size(imageSlice), class(imageSlice));
            for colorChannel = 1:size(imageSlice, 3)
                slicePlane = imageSlice(:,:,colorChannel);
                switch obj.BatchOpt.MorphOperation{1}
                    case 'Bottom-hat filtering';     processedImage(:,:,colorChannel) = imbothat(slicePlane, se);
                    case 'Clear border';             processedImage(:,:,colorChannel) = imclearborder(slicePlane, conn);
                    case 'Morphological closing';    processedImage(:,:,colorChannel) = imclose(slicePlane, se);
                    case 'Dilate image';             processedImage(:,:,colorChannel) = imdilate(slicePlane, se);
                    case 'Erode image';              processedImage(:,:,colorChannel) = imerode(slicePlane, se);
                    case 'Fill regions';             processedImage(:,:,colorChannel) = imfill(slicePlane);
                    case 'H-maxima transform';       processedImage(:,:,colorChannel) = imhmax(slicePlane, hValue(1), conn);
                    case 'H-minima transform';       processedImage(:,:,colorChannel) = imhmin(slicePlane, hValue(1), conn);
                    case 'Morphological opening';    processedImage(:,:,colorChannel) = imopen(slicePlane, se);
                    case 'Top-hat filtering';        processedImage(:,:,colorChannel) = imtophat(slicePlane, se);
                end
                if smoothHSize > 0
                    processedImage(:,:,colorChannel) = imfilter(processedImage(:,:,colorChannel), smoothFilter, 'replicate');
                end
            end

            switch obj.BatchOpt.ActionToResult{1}
                case 'None';              processedImage = processedImage * multiplyFactor;
                case 'AddToImage';        processedImage = imageSlice + processedImage * multiplyFactor;
                case 'SubtractFromImage'; processedImage = imageSlice - processedImage * multiplyFactor;
            end
        end

        % -----------------------------------------------------------
        function previewButtonPushed(obj)
            % PREVIEWBUTTONPUSHED - Apply 2D operation to current view block and display.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.MorphOpsImages.previewButtonPushed: triggered\n');
            end
            if isempty(obj.view) || ~isvalid(obj.view.gui); return; end

            getDataOptions.blockModeSwitch = 1;
            getDataOptions.id = obj.BatchOpt.id;

            colorChannelIndex = find(ismember(obj.BatchOpt.ColorChannel{2}, obj.BatchOpt.ColorChannel(1))) - 1;
            originalImage = cell2mat(obj.mibModel.getData2D('image', [], [], colorChannelIndex, getDataOptions));

            processedImage = obj.applyOperation2D(originalImage);

            % Convert to uint8 for display (same logic as ImageFilters.PreviewButtonPushed)
            if ~isa(processedImage, 'uint8')
                dataset = obj.mibModel.I{obj.BatchOpt.id};
                if ~obj.mibModel.onFlyImageStretch
                    for colorChannel = 1:size(processedImage, 3)
                        processedImage(:,:,colorChannel) = uint8( ...
                            double(processedImage(:,:,colorChannel)) / ...
                            double(dataset.image.viewPort.max(colorChannel)) * 255);
                    end
                end
                processedImage = uint8(processedImage / 256);
            end

            showSettings.resizeToMagnification = true;
            showSettings.sImgIn = processedImage;
            notify(obj.mibModel, 'ShowImage', core.ToggleEventData(showSettings));
        end

        % -----------------------------------------------------------
        function helpButton_Callback(obj)
            % HELPBUTTON_CALLBACK - Open documentation in browser.

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.MorphOpsImages.helpButton_Callback: triggered\n');
            end
            helpFilPath = fullfile(fileparts(obj.mibModel.mibPath), 'docs', 'html', 'user-interface', 'ribbon', 'image', 'image-morphops.html');
            utils.openHelpPage(helpFilPath, ...
                'http://mib.helsinki.fi/help/main3/user-interface/ribbon/image/image-morphops.html');
        end

    end
end
