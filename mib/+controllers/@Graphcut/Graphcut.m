classdef Graphcut < handle
% GRAPHCUT - Controller for graph-cut (max-flow/min-cut) image segmentation.
%
% Provides 2D-per-slice, 2D-all-slices, 3D, and 3D-grid segmentation modes
% using SLIC or Watershed supervoxels combined with maxflow/mincut optimization.
% Available from MIB → Ribbon → Segmentation → Graphcut.

    properties
        mibModel
        % handle to MibModel
        mibGUI
        % shortcut to mibModel.mibGUI (parent figure for dialogs)
        view
        % handle to the view (core.ChildView wrapping views.GraphcutGUI)
        listener
        % cell array with handles to event listeners
        graphcut
        % struct array with graphcut data:
        %   .slic          - superpixel/supervoxel label array
        %   .noPix         - number of superpixels/supervoxels
        %   .Graph         - cell of sparse adjacency graphs for maxflow
        %   .Edges         - cell of edge lists [src dst]
        %   .EdgesValues   - cell of edge intensity differences
        %   .PixelIdxList  - (optional) pixel index lists per superpixel
        %   .bb            - bounding box [x1 x2 y1 y2 z1 z2]
        %   .grid          - struct with grid tile bounding boxes (mode3dGridRadio)
        %   .version       - graphcut format version (2.2)
        %   .mode          - segmentation mode string
        %   .binVal        - binning factors [xy z]
        %   .colCh         - color channel index
        %   .spSize        - superpixel size parameter
        %   .spCompact     - SLIC compactness parameter
        %   .superPixType  - 'SLIC' or 'Watershed'
        %   .blackOnWhite  - signal polarity flag
        %   .scaleFactor   - edge weight scaling factor
        %   .dilateMode    - 'pre' or 'post' dilation mode
        %   .tilesX/Y/Z    - grid tile counts
        graphcutVersion = 2.2 
        % version of the graphcut structure
        mode
        % active segmentation mode string:
        %   'mode2dCurrentRadio' | 'mode2dRadio' | 'mode3dRadio' | 'mode3dGridRadio'
        realtimeSwitch
        % logical: enable real-time segmentation on model paint
        slicSize
        % size parameter for SLIC superpixels
        watershedSize
        % size parameter for Watershed superpixels
        shownLabelObj
        % cell array: label vectors of currently displayed superpixels
        seedObj
        % cell array: object seeds per slice (3D modes)
        seedBg
        % cell array: background seeds per slice (3D modes)
        timerElapsed
        % elapsed time of last segmentation (seconds); controls waitbar display
        timerElapsedMax
        % threshold (seconds): show waitbar when timerElapsed exceeds this
    end

    events
        CloseEvent
        % fired when the window is closed, notifies MibController to remove this child
    end

    methods (Static)
        function ViewListner_Callback2(obj, ~, evnt)
        % VIEWLISTNER_CALLBACK2 - React to model events; clean up listeners if the view is gone.
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      controllers.Graphcut.ViewListner_Callback2(obj, src, evnt)
        %
        % Input Arguments:
        %   - **obj** — handle to the ``Graphcut`` controller
        %   - **evnt** — event data; ``evnt.EventName`` is inspected for dispatch
            if ~isvalid(obj) || isempty(obj.view) || ~isvalid(obj.view.gui)
                for i = 1:numel(obj.listener); delete(obj.listener{i}); end
                return;
            end
            switch evnt.EventName
                case {'UpdateGuiWidgets', 'NewDataset'}
                    obj.updateWidgets();
                case {'SetData'}
                    if strcmp(evnt.Parameters.type, 'labels') && obj.realtimeSwitch == 1
                        tic
                        obj.doGraphcutSegmentation();
                        obj.timerElapsed = toc;
                        fprintf('Elapsed time is %f seconds.\n', obj.timerElapsed);
                        notify(obj.mibModel, 'ShowMask');
                    end 
            end
        end

        [G, calcCancelled] = calcSupervoxels(Graphcut, img, parLoopOptions, usePrecomputedSlic)
        % declaration — implemented in calcSupervoxels.m
    end

    methods
        function obj = Graphcut(mibModel)
        % GRAPHCUT - Constructor; creates and shows the Graphcut segmentation window.
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      controller = controllers.Graphcut(mibModel)
        %
        % Input Arguments:
        %   - **mibModel** — handle to the ``MibModel`` instance
        %
        % Output Arguments:
        %   - **controller** — handle to the constructed ``Graphcut`` object
            obj.mibModel = mibModel;
            obj.view.gui   = mibModel.mibGUI;

            id = obj.mibModel.getActiveId();
            dataset = obj.mibModel.I{id};

            % check for virtual stacking mode
            %% Virtual mode guard
            if strcmp(dataset.datasetType, 'Virtual')
                dlgOpt.MsgBoxOnly = true;
                dlgOpt.Icon = 'puffin_warning';
                utils.dlgs.inputUniversalDlg(obj.view.gui, '', {''}, ...
                    {'This tool is not available in virtual stacking mode.\nPlease switch to the memory-resident mode and try again.'}, ...
                    'Not implemented', dlgOpt);
                obj.closeWindow();
                return;
            end

            obj.slicSize      = 500;
            obj.watershedSize = 15;

            obj.graphcut(1).slic    = [];
            obj.graphcut(1).noPix   = [];
            obj.graphcut(1).Graph   = cell(1);
            obj.graphcut(1).grid    = struct;
            obj.graphcut(1).version = obj.graphcutVersion;

            obj.shownLabelObj  = cell(1);
            obj.seedObj        = cell(1);
            obj.seedBg         = cell(1);
            obj.realtimeSwitch = 0;
            obj.timerElapsedMax = .5;
            obj.timerElapsed    = 9999999;
            obj.mode = 'mode2dCurrentRadio';

            obj.view = core.ChildView(obj, 'views.GraphcutGUI');
            obj.addCallbacks();
            obj.updateWidgets();

            Font = obj.mibModel.preferences.System.Font;
            if obj.view.handles.infoLabel.FontSize ~= Font.FontSize ...
                    || ~strcmp(obj.view.handles.infoLabel.FontName, Font.FontName)
                utils.fontSizeUpdate(obj.view.gui, Font);
            end
            obj.view.gui = utils.moveWindowOutside(obj.view.gui, obj.mibModel.mibGUI, 'left');

            obj.listener{1} = addlistener(obj.mibModel, 'UpdateGuiWidgets', @(s,e) obj.ViewListner_Callback2(obj, s, e));
            obj.listener{2} = addlistener(obj.mibModel, 'NewDataset',       @(s,e) obj.ViewListner_Callback2(obj, s, e));
            obj.listener{3} = addlistener(obj.mibModel, 'SetData',          @(s,e) obj.ViewListner_Callback2(obj, s, e));  % to update graphcut upon adding a seed

            obj.view.gui.Visible = true;
        end

        function addCallbacks(obj)
        % ADDCALLBACKS - Wire all GUI widget callbacks to controller methods.
            obj.view.gui.CloseRequestFcn = @(~,~) obj.closeWindow();
            handles = obj.view.handles;

            % mode selection — wire the ButtonGroup that contains the 4 radios
            handles.modeButtonGroup.SelectionChangedFcn = @(~, evnt) obj.mode2dRadio_Callback(evnt.NewValue);

            % dimension edit fields
            handles.xSubareaEdit.ValueChangedFcn = @(h,~) obj.checkDimensions(h);
            handles.ySubareaEdit.ValueChangedFcn = @(h,~) obj.checkDimensions(h);
            handles.zSubareaEdit.ValueChangedFcn = @(h,~) obj.checkDimensions(h);
            handles.binSubareaEdit.ValueChangedFcn = @(h,~) obj.binSubareaEdit_Callback(h);

            % superpixel controls
            handles.superpixTypePopup.ValueChangedFcn = @(~,~) obj.superpixTypePopup_Callback();
            handles.superpixelEdit.ValueChangedFcn    = @(~,~) obj.clearPreprocessBtn_Callback();

            % checkboxes
            handles.realtimeCheck.ValueChangedFcn     = @(h,~) obj.realtimeCheck_Callback(h);
            handles.parforCheck.ValueChangedFcn       = @(~,~) obj.parforCheck_Callback();
            handles.pixelIdxListCheck.ValueChangedFcn = @(~,~) obj.pixelIdxListCheck_Callback();

            % buttons
            handles.updateMaterialsBtn.ButtonPushedFcn      = @(~,~) obj.updateMaterialsBtn_Callback();
            handles.clearPreprocessBtn.ButtonPushedFcn       = @(~,~) obj.clearPreprocessBtn_Callback();
            handles.resetDimsBtn.ButtonPushedFcn             = @(~,~) obj.resetDimsBtn_Callback();
            handles.currentViewBtn.ButtonPushedFcn           = @(~,~) obj.currentViewBtn_Callback();
            handles.subAreaFromSelectionBtn.ButtonPushedFcn  = @(~,~) obj.subAreaFromSelectionBtn_Callback();
            handles.superpixelsBtn.ButtonPushedFcn           = @(~,~) obj.superpixelsBtn_Callback();
            handles.superpixelsPreviewBtn.ButtonPushedFcn    = @(~,~) obj.superpixelsPreviewBtn_Callback();
            handles.exportSuperpixelsBtn.ButtonPushedFcn     = @(~,~) obj.exportSuperpixelsBtn_Callback();
            handles.importSuperpixelsBtn.ButtonPushedFcn     = @(~,~) obj.importSuperpixelsBtn_Callback();
            handles.segmentBtn.ButtonPushedFcn               = @(~,~) obj.segmentBtn_Callback();
            handles.segmentAllBtn.ButtonPushedFcn            = @(~,~) obj.segmentAllBtn_Callback();
            handles.closeButton.ButtonPushedFcn              = @(~,~) obj.closeWindow();
            handles.recalculateGraph.ButtonPushedFcn         = @(~,~) obj.recalcGraph_Callback();

            
        end

        function closeWindow(obj)
        % CLOSEWINDOW - Delete the view and all listeners, then fire ``CloseEvent``.
            if isvalid(obj.view.gui); delete(obj.view.gui); end
            for i = 1:numel(obj.listener); delete(obj.listener{i}); end
            notify(obj, 'CloseEvent');
        end

        function updateWidgets(obj)
        % UPDATEWIDGETS - Refresh all widget states from the current dataset.
            id = obj.mibModel.getActiveId();
            dataset = obj.mibModel.I{id};

            if dataset.image.depth < 2
                obj.view.handles.mode3dRadio.Enable = 'off';
                obj.view.handles.mode3dGridRadio.Enable = 'off';
                obj.view.handles.mode2dCurrentRadio.Value = true;
            else
                obj.view.handles.mode3dRadio.Enable = 'on';
                obj.view.handles.mode3dGridRadio.Enable = 'on';
            end

            % update color channel dropdown
            colorsNo = dataset.image.colors;
            colCh = arrayfun(@(i) sprintf('Ch %d', i), 1:colorsNo, 'UniformOutput', false);
            obj.view.handles.imageColChPopup.Items = colCh;
            if ~ismember(obj.view.handles.imageColChPopup.Value, colCh)
                obj.view.handles.imageColChPopup.Value = colCh{1};
            end

            obj.updateMaterialsBtn_Callback();

            if isempty(obj.graphcut(1).slic)
                [height, width, depth] = dataset.getDatasetDimensions('selection', 3, []);
                obj.view.handles.xSubareaEdit.Value = sprintf('%d:%d', 1, width);
                obj.view.handles.ySubareaEdit.Value = sprintf('%d:%d', 1, height);
                obj.view.handles.zSubareaEdit.Value = sprintf('%d:%d', 1, depth);
            else
                obj.importSuperpixelsBtn_Callback(1);
            end
        end

        function updateMaterialsBtn_Callback(obj)
        % UPDATEMATERIALSBTN_CALLBACK - Repopulate background/signal material dropdowns.
            id = obj.mibModel.getActiveId();
            list = obj.mibModel.I{id}.labels.materialNames;
            if obj.mibModel.I{id}.modelExist == 0 || isempty(list)
                warningMsg = 'Please create a model with 2 materials: background and object and restart the watershed tool';
                obj.view.handles.backgroundMaterialPopup.Items = {warningMsg};
                obj.view.handles.backgroundMaterialPopup.Value = warningMsg;
                obj.view.handles.backgroundMaterialPopup.BackgroundColor = [1 0 0];
                obj.view.handles.signalMaterialPopup.Items = {warningMsg};
                obj.view.handles.signalMaterialPopup.Value = warningMsg;
                obj.view.handles.signalMaterialPopup.BackgroundColor = [1 0 0];
            else
                obj.view.handles.backgroundMaterialPopup.Items = list;
                obj.view.handles.backgroundMaterialPopup.Value = list{1};
                obj.view.handles.backgroundMaterialPopup.BackgroundColor = [1 1 1];
                obj.view.handles.signalMaterialPopup.Items = list;
                obj.view.handles.signalMaterialPopup.Value = list{end};
                obj.view.handles.signalMaterialPopup.BackgroundColor = [1 1 1];
            end
        end

        function status = clearPreprocessBtn_Callback(obj)
        % CLEARPREPROCESSBTN_CALLBACK - Reset the graphcut struct and update bounding-box from UI.
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      obj.clearPreprocessBtn_Callback()
        %      status = obj.clearPreprocessBtn_Callback()
        %
        % Output Arguments:
        %   - **status** — [logical] ``1`` when cleared successfully, ``0`` when cancelled
            status = 0;

            if ~isempty(obj.graphcut(1).noPix)
                button = utils.dlgs.inputQuestDlg(obj.view.gui, ...
                    sprintf('The pre-processed data will be removed!'), ...
                    'Warning!', 'Continue', 'Cancel', 'Cancel');
                if strcmp(button, 'Cancel'); return; end
            end

            obj.graphcut = struct();
            obj.graphcut(1).slic    = [];
            obj.graphcut(1).noPix   = [];
            obj.graphcut(1).Graph   = cell(1);
            obj.graphcut(1).grid    = struct;
            obj.graphcut(1).version = obj.graphcutVersion;

            superPixType = obj.view.handles.superpixTypePopup.Value;
            if strcmp(superPixType, 'SLIC')
                obj.slicSize = obj.view.handles.superpixelEdit.Value;
            else
                obj.watershedSize = obj.view.handles.superpixelEdit.Value;
            end

            width  = str2num(obj.view.handles.xSubareaEdit.Value); %#ok<ST2NM>
            height = str2num(obj.view.handles.ySubareaEdit.Value); %#ok<ST2NM>
            depth  = str2num(obj.view.handles.zSubareaEdit.Value); %#ok<ST2NM>
            obj.graphcut(1).bb = [min(width) max(width) min(height) max(height) min(depth) max(depth)];

            if strcmp(obj.mode, 'mode3dGridRadio')
                tilesX = obj.view.handles.chopXedit.Value;
                tilesY = obj.view.handles.chopYedit.Value;
                tilesZ = obj.view.handles.chopZedit.Value;
                bb = obj.graphcut(1).bb;
                obj.graphcut(1).grid.stepX = ceil((bb(2)-bb(1)+1)/tilesX);
                obj.graphcut(1).grid.stepY = ceil((bb(4)-bb(3)+1)/tilesY);
                obj.graphcut(1).grid.stepZ = ceil((bb(6)-bb(5)+1)/tilesZ);
                xBoundaries = [bb(1):obj.graphcut(1).grid.stepX:bb(2) bb(2)];
                yBoundaries = [bb(3):obj.graphcut(1).grid.stepY:bb(4) bb(4)];
                zBoundaries = [bb(5):obj.graphcut(1).grid.stepZ:bb(6) bb(6)];

                index = 1;
                for z = 1:tilesZ
                    for y = 1:tilesY
                        for x = 1:tilesX
                            obj.graphcut(1).grid.bb(x,y,z).x      = [xBoundaries(x) xBoundaries(x+1)];
                            obj.graphcut(1).grid.bb(x,y,z).width  = xBoundaries(x+1)-xBoundaries(x)+1;
                            obj.graphcut(1).grid.bb(x,y,z).y      = [yBoundaries(y) yBoundaries(y+1)];
                            obj.graphcut(1).grid.bb(x,y,z).height = yBoundaries(y+1)-yBoundaries(y)+1;
                            obj.graphcut(1).grid.bb(x,y,z).z      = [zBoundaries(z) zBoundaries(z+1)];
                            obj.graphcut(1).grid.bb(x,y,z).depth  = zBoundaries(z+1)-zBoundaries(z)+1;
                            obj.graphcut(1).grid.bb(x,y,z).index  = index;
                            index = index + 1;
                        end
                    end
                end
                obj.graphcut(1).tilesX = tilesX;
                obj.graphcut(1).tilesY = tilesY;
                obj.graphcut(1).tilesZ = tilesZ;
            else
                obj.graphcut(1).grid.bb(1).x      = [min(width) max(width)];
                obj.graphcut(1).grid.bb(1).width   = obj.graphcut(1).grid.bb(1).x(2)-obj.graphcut(1).grid.bb(1).x(1)+1;
                obj.graphcut(1).grid.bb(1).y      = [min(height) max(height)];
                obj.graphcut(1).grid.bb(1).height  = obj.graphcut(1).grid.bb(1).y(2)-obj.graphcut(1).grid.bb(1).y(1)+1;
                obj.graphcut(1).grid.bb(1).z      = [min(depth) max(depth)];
                obj.graphcut(1).grid.bb(1).depth   = obj.graphcut(1).grid.bb(1).z(2)-obj.graphcut(1).grid.bb(1).z(1)+1;
                obj.graphcut(1).grid.bb(1).index   = 1;
                obj.graphcut(1).grid.stepX = obj.graphcut(1).grid.bb(1).width;
                obj.graphcut(1).grid.stepY = obj.graphcut(1).grid.bb(1).height;
                obj.graphcut(1).grid.stepZ = obj.graphcut(1).grid.bb(1).depth;
                obj.graphcut(1).tilesX = 1;
                obj.graphcut(1).tilesY = 1;
                obj.graphcut(1).tilesZ = 1;
            end

            if obj.view.handles.mode2dRadio.Value
                obj.seedObj       = cell(1);
                obj.seedBg        = cell(1);
                obj.shownLabelObj = cell([obj.graphcut(1).grid.bb(1).depth 1]);
            elseif obj.view.handles.mode3dGridRadio.Value
                obj.shownLabelObj = cell([numel(obj.graphcut(1).grid.bb) 1]);
                obj.seedObj       = cell([numel(obj.graphcut(1).grid.bb) 1]);
                obj.seedBg        = cell([numel(obj.graphcut(1).grid.bb) 1]);
            else
                obj.shownLabelObj = cell(1);
                obj.seedObj       = cell(1);
                obj.seedBg        = cell(1);
            end

            defaultBgColor = obj.view.handles.resetDimsBtn.BackgroundColor;
            obj.view.handles.preprocessBtn.BackgroundColor  = defaultBgColor;
            obj.view.handles.superpixelsBtn.BackgroundColor = defaultBgColor;
            obj.view.handles.superpixelsCountText.Text = 'Superpixels count: 0';

            binVal = str2num(obj.view.handles.binSubareaEdit.Value); %#ok<ST2NM>
            if sum(binVal) ~= 2
                obj.view.handles.realtimeCheck.Value  = false;
                obj.realtimeSwitch = 0;
                obj.view.handles.realtimeCheck.Enable = 'off';
                obj.view.handles.realtimeText.Enable  = 'off';
            else
                obj.view.handles.realtimeCheck.Enable = 'on';
                obj.view.handles.realtimeText.Enable  = 'on';
            end
            status = 1;
        end

        function mode2dRadio_Callback(obj, hObject)
        % MODE2DRADIO_CALLBACK - Handle segmentation mode change from the radio button group.
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      obj.mode2dRadio_Callback(hObject)
        %
        % Input Arguments:
        %   - **hObject** — handle to the newly selected radio button
            if ~isempty(obj.graphcut(1).noPix)
                button = utils.dlgs.inputQuestDlg(obj.view.gui, ...
                    sprintf('The pre-processed data will be removed!'), ...
                    'Warning!', 'Continue', 'Cancel', 'Cancel');
                if strcmp(button, 'Cancel')
                    obj.view.handles.(obj.mode).Value = true;
                    return;
                end
                obj.graphcut = struct();
                obj.graphcut(1).noPix = [];
                obj.clearPreprocessBtn_Callback();
            end
            obj.mode = hObject.Tag;
            obj.superpixTypePopup_Callback();
            hObject.Value = true;
        end

        function checkDimensions(obj, hObject)
        % CHECKDIMENSIONS - Validate a dimension edit field value and clear preprocessed data.
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      obj.checkDimensions(hObject)
        %
        % Input Arguments:
        %   - **hObject** — handle to ``xSubareaEdit``, ``ySubareaEdit``, or ``zSubareaEdit``
            id = obj.mibModel.getActiveId();
            text = hObject.Value;
            typedValue = str2num(text); %#ok<ST2NM>
            [height, width, depth] = obj.mibModel.I{id}.getDatasetDimensions('selection', 3, []);
            switch hObject.Tag
                case 'xSubareaEdit'; maxVal = width;
                case 'ySubareaEdit'; maxVal = height;
                case 'zSubareaEdit'; maxVal = depth;
            end
            if min(typedValue) < 1 || max(typedValue) > maxVal
                hObject.Value = sprintf('1:%d', maxVal);
                utils.dlgs.showErrorDialog(obj.view.gui, 'Please check the values!', 'Wrong parameters!');
                return;
            end
            obj.clearPreprocessBtn_Callback();
        end

        function resetDimsBtn_Callback(obj)
        % RESETDIMSBTN_CALLBACK - Reset sub-area edit fields to the full dataset extent.
            status = obj.clearPreprocessBtn_Callback();    
            if status==0; return; end
            id = obj.mibModel.getActiveId();
            [height, width, depth] = obj.mibModel.I{id}.getDatasetDimensions('selection', 3, []);
            obj.view.handles.xSubareaEdit.Value    = sprintf('1:%d', width);
            obj.view.handles.ySubareaEdit.Value    = sprintf('1:%d', height);
            obj.view.handles.zSubareaEdit.Value    = sprintf('1:%d', depth);
            obj.view.handles.binSubareaEdit.Value  = '1; 1';
        end

        function currentViewBtn_Callback(obj)
        % CURRENTVIEWBTN_CALLBACK - Set the XY sub-area from the currently visible image region.
            id = obj.mibModel.getActiveId();
            [yMin, yMax, xMin, xMax] = obj.mibModel.I{id}.getCoordinatesOfShownImage();
            obj.view.handles.xSubareaEdit.Value = sprintf('%d:%d', xMin, xMax);
            obj.view.handles.ySubareaEdit.Value = sprintf('%d:%d', yMin, yMax);
            obj.clearPreprocessBtn_Callback();
        end

        function subAreaFromSelectionBtn_Callback(obj)
        % SUBAREAFROMBTN_CALLBACK - Set the sub-area from the bounding box of the selection layer.
            bgColor = obj.view.handles.subAreaFromSelectionBtn.BackgroundColor;
            obj.view.handles.subAreaFromSelectionBtn.BackgroundColor = [1 0 0];
            drawnow;
            if strcmp(obj.mode, 'mode2dCurrentRadio')
                img = cell2mat(obj.mibModel.getData2D('selection'));
                STATS = regionprops(img, 'BoundingBox');
                if numel(STATS) == 0
                    utils.dlgs.showErrorDialog(obj.view.gui, ...
                        sprintf('Selection layer was not found!\nPlease make sure that the Selection layer is shown in the Image View panel'), ...
                        'Missing Selection');
                    obj.resetDimsBtn_Callback();
                    obj.view.handles.subAreaFromSelectionBtn.BackgroundColor = bgColor;
                    return;
                end
                obj.view.handles.xSubareaEdit.Value = sprintf('%d:%d', ceil(STATS(1).BoundingBox(1)), ceil(STATS(1).BoundingBox(1))+STATS(1).BoundingBox(3)-1);
                obj.view.handles.ySubareaEdit.Value = sprintf('%d:%d', ceil(STATS(1).BoundingBox(2)), ceil(STATS(1).BoundingBox(2))+STATS(1).BoundingBox(4)-1);
            else
                img = cell2mat(obj.mibModel.getData3D('selection', [], 3));
                STATS = regionprops(img, 'BoundingBox');
                if numel(STATS) == 0
                    utils.dlgs.showErrorDialog(obj.view.gui, ...
                        sprintf('Selection layer was not found!\nPlease make sure that the Selection layer is shown in the Image View panel'), ...
                        'Missing Selection');
                    obj.resetDimsBtn_Callback();
                    obj.view.handles.subAreaFromSelectionBtn.BackgroundColor = bgColor;
                    return;
                end
                obj.view.handles.xSubareaEdit.Value = sprintf('%d:%d', ceil(STATS(1).BoundingBox(1)), ceil(STATS(1).BoundingBox(1))+STATS(1).BoundingBox(4)-1);
                obj.view.handles.ySubareaEdit.Value = sprintf('%d:%d', ceil(STATS(1).BoundingBox(2)), ceil(STATS(1).BoundingBox(2))+STATS(1).BoundingBox(5)-1);
                obj.view.handles.zSubareaEdit.Value = sprintf('%d:%d', ceil(STATS(1).BoundingBox(3)), ceil(STATS(1).BoundingBox(3))+STATS(1).BoundingBox(6)-1);
            end
            obj.clearPreprocessBtn_Callback();
            obj.view.handles.subAreaFromSelectionBtn.BackgroundColor = bgColor;
        end

        function binSubareaEdit_Callback(obj, hObject)
        % BINSUBAREAEDIT_CALLBACK - Parse and normalise the binning field value.
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      obj.binSubareaEdit_Callback(hObject)
        %
        % Input Arguments:
        %   - **hObject** — handle to ``binSubareaEdit``; ``.Value`` is a semicolon-separated
        %     pair of integers, e.g. ``'2; 1'`` (XY bin; Z bin)
            val = str2num(hObject.Value); %#ok<ST2NM>
            if isempty(val)
                val = [1; 1];
            elseif isnan(val(1)) || min(val) <= .5
                val = [1; 1];
            else
                val = round(val);
            end
            hObject.Value = sprintf('%d; %d', val(1), val(2));
            obj.clearPreprocessBtn_Callback();
        end

        function realtimeCheck_Callback(obj, hObject)
        % REALTIMECHECK_CALLBACK - Sync ``realtimeSwitch`` with the checkbox state.
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      obj.realtimeCheck_Callback(hObject)
        %
        % Input Arguments:
        %   - **hObject** — handle to ``realtimeCheck``
            obj.realtimeSwitch = hObject.Value;
        end

        function parforCheck_Callback(obj)
        % PARFORCHECK_CALLBACK - Start a parallel pool when the parallel checkbox is ticked.
            if obj.view.handles.parforCheck.Value
                nWorkers = obj.mibModel.preferences.System.cpuParallelLimit;
                if isempty(gcp('nocreate'))
                    parpool(nWorkers);
                end
            end
        end

        function doGraphcutSegmentation(obj)
        % DOGRAPHCUTSEGMENTATION - Run maxflow/mincut and write the result to the mask layer.
        %
        % Reads object/background seeds from the labels layer, builds the data term,
        % calls ``maxflow_v222``, and writes the resulting mask — either incrementally
        % (when ``shownLabelObj`` is already set) or in full.
            id = obj.mibModel.getActiveId();
            dataset = obj.mibModel.I{id};
            bgMaterialId   = find(strcmp(obj.view.handles.backgroundMaterialPopup.Items, obj.view.handles.backgroundMaterialPopup.Value));
            seedMaterialId = find(strcmp(obj.view.handles.signalMaterialPopup.Items, obj.view.handles.signalMaterialPopup.Value));
            noMaterials    = numel(obj.view.handles.signalMaterialPopup.Items);

            if bgMaterialId == seedMaterialId
                utils.dlgs.showErrorDialog(obj.view.gui, ...
                    sprintf('Wrong selection of materials!\nPlease select two different materials in the Background and Object combo boxes.'), ...
                    'Wrong materials');
                return;
            end

            if isempty(obj.graphcut(1).noPix); obj.superpixelsBtn_Callback(); end

            if obj.timerElapsed > obj.timerElapsedMax
                progressBar = uiprogressdlg(obj.view.gui, 'Value', 0, ...
                    'Message', 'Graphcut segmentation...', 'Title', 'Maxflow/Mincut');
            else
                progressBar = [];
            end

            if strcmp(obj.mode, 'mode3dGridRadio')
                [winWidth, winHeight] = obj.mibModel.getAxesLimits();
                centX = mean(winWidth);
                centY = mean(winHeight);
                centZ = dataset.slices{3}(1);

                bbX = mean(vertcat(obj.graphcut(1).grid.bb.x), 2);
                bbY = mean(vertcat(obj.graphcut(1).grid.bb.y), 2);
                bbZ = mean(vertcat(obj.graphcut(1).grid.bb.z), 2);
                bbCenters = [bbX, bbY, bbZ];
                distances = sqrt((bbCenters(:,1)-centX).^2 + (bbCenters(:,2)-centY).^2 + (bbCenters(:,3)-centZ).^2);
                [~, graphId] = min(distances);

                getDataOptions.x = obj.graphcut(1).grid.bb(graphId).x;
                getDataOptions.y = obj.graphcut(1).grid.bb(graphId).y;
                getDataOptions.z = obj.graphcut(1).grid.bb(graphId).z;
            else
                graphId = 1;
                width  = str2num(obj.view.handles.xSubareaEdit.Value); %#ok<ST2NM>
                height = str2num(obj.view.handles.ySubareaEdit.Value); %#ok<ST2NM>
                depth  = str2num(obj.view.handles.zSubareaEdit.Value); %#ok<ST2NM>
                getDataOptions.x = [min(width) max(width)];
                getDataOptions.y = [min(height) max(height)];
                getDataOptions.z = [min(depth) max(depth)];
                getDataOptions.blockModeSwitch = 0;
            end

            % getData2D checks 'if ~isfield(options, "z")' before setting z from slice_no,
            % so a pre-set .z range would cause it to return the whole stack instead of one slice.
            % Use a copy without .z for all getData2D calls in 2D modes.
            get2DOpt = rmfield(getDataOptions, 'z');

            convertPixelOpt.x = getDataOptions.x;
            convertPixelOpt.y = getDataOptions.y;
            convertPixelOpt.z = getDataOptions.z;

            binVal    = str2num(obj.view.handles.binSubareaEdit.Value); %#ok<ST2NM>
            binWidth  = ceil((getDataOptions.x(2)-getDataOptions.x(1)+1) / binVal(1));
            binHeight = ceil((getDataOptions.y(2)-getDataOptions.y(1)+1) / binVal(1));
            binDepth  = ceil((getDataOptions.z(2)-getDataOptions.z(1)+1) / binVal(2));

            if dataset.maskExist == 0
                dataset.clearLayer('mask');
            end

            singleToolScores = 1;

            if obj.view.handles.mode2dCurrentRadio.Value
                negIds = [];
                posIds = [];

                seedImg = cell2mat(obj.mibModel.getData2D('labels', [], [], [], get2DOpt));

                if size(obj.graphcut(1).slic, 3) > 1
                    sliceNo  = dataset.slices{3}(1);
                    currSlic = obj.graphcut(1).slic(:,:,sliceNo);
                else
                    currSlic = obj.graphcut(1).slic;
                    sliceNo  = 1;
                end

                if binVal(1) ~= 1
                    seedImg = imresize(seedImg, [binHeight binWidth], 'nearest');
                end

                labelObj = unique(currSlic(seedImg==seedMaterialId));
                if isempty(labelObj)
                    if ~isempty(progressBar); delete(progressBar); end
                    return;
                end
                labelBg = unique(currSlic(seedImg==bgMaterialId));

                if strcmp(obj.graphcut(1).superPixType, 'Watershed') && strcmp(obj.graphcut(1).dilateMode, 'post')
                    labelObj(labelObj==0) = [];
                    labelBg(labelBg==0)   = [];
                end

                if ~isempty(progressBar); progressBar.Value = 0.45; progressBar.Message = 'Generating data term...'; end

                T = zeros([obj.graphcut(1).noPix(sliceNo), 2]) + 0.5;
                labelObj(ismember(labelObj, labelBg)) = [];
                T(labelObj, 1) = 0;      T(labelObj, 2) = 99999;
                T(labelBg,  1) = 99999;  T(labelBg,  2) = 0;
                T = sparse(T);

                [~, labels] = maxflow_v222(obj.graphcut(1).Graph{sliceNo}, T);

                if isempty(obj.shownLabelObj{1})
                    obj.shownLabelObj{1} = labels;
                    Mask = zeros(size(seedImg), 'uint8');
                else
                    Mask   = cell2mat(obj.mibModel.getData2D('mask', [], [], [], get2DOpt));
                    negIds = obj.shownLabelObj{1} - labels;
                    posIds = labels - obj.shownLabelObj{1};
                    obj.shownLabelObj{1} = labels;
                end

                if isfield(obj.graphcut(1), 'PixelIdxList')
                    if ~isempty(negIds)
                        Mask(vertcat(obj.graphcut(1).PixelIdxList{negIds>0})) = 0;
                        Mask(vertcat(obj.graphcut(1).PixelIdxList{posIds>0})) = 1;
                    else
                        Mask(vertcat(obj.graphcut(1).PixelIdxList{labels>0})) = 1;
                    end
                else
                    if ~isempty(negIds)
                        negIds = find(negIds > 0);
                        posIds = find(posIds > 0);
                        negIds = cast(negIds, class(currSlic));
                        posIds = cast(posIds, class(currSlic));
                        if ~isempty(negIds); Mask(ismember(currSlic, negIds)) = 0; end
                        if ~isempty(posIds); Mask(ismember(currSlic, posIds)) = 1; end
                    else
                        indexLabel = cast(find(labels>0), class(currSlic));
                        Mask(ismember(currSlic, indexLabel)) = 1;
                    end
                end
                Mask(seedImg==bgMaterialId) = 0;

                if strcmp(obj.graphcut(1).superPixType, 'Watershed') && strcmp(obj.graphcut(1).dilateMode, 'post')
                    Mask = imdilate(Mask, ones(3));
                end
                if binVal(1) ~= 1
                    Mask = imresize(Mask, [max(height)-min(height)+1, max(width)-min(width)+1], 'nearest');
                end
                obj.mibModel.setData2D(Mask, 'mask', [], [], [], getDataOptions);

            elseif obj.view.handles.mode2dRadio.Value
                if obj.realtimeSwitch == 0
                    startIndex = getDataOptions.z(1);
                    endIndex   = getDataOptions.z(2);
                    index = 1;
                else
                    startIndex = dataset.slices{3}(1);
                    endIndex   = startIndex;
                    index      = startIndex - getDataOptions.z(1) + 1;
                end
                total = endIndex - startIndex + 1;

                for sliceNo = startIndex:endIndex
                    negIds  = [];
                    seedImg = cell2mat(obj.mibModel.getData2D('labels', sliceNo, [], [], get2DOpt));
                    if binVal(1) ~= 1
                        seedImg = imresize(seedImg, [binHeight binWidth], 'nearest');
                    end
                    currSlic = obj.graphcut(1).slic(:,:,index);
                    labelObj = unique(currSlic(seedImg==seedMaterialId));
                    if isempty(labelObj); index = index + 1; continue; end
                    labelBg = unique(currSlic(seedImg==bgMaterialId));

                    if strcmp(obj.graphcut(1).superPixType, 'Watershed') && strcmp(obj.graphcut(1).dilateMode, 'post')
                        labelObj(labelObj==0) = [];
                        labelBg(labelBg==0)   = [];
                    end

                    labelObj(ismember(labelObj, labelBg)) = [];

                    T = zeros([obj.graphcut(1).noPix(index), 2]) + 0.5;
                    T(labelObj, 1) = 0;      T(labelObj, 2) = 99999;
                    T(labelBg,  1) = 99999;  T(labelBg,  2) = 0;
                    T = sparse(T);
                    [~, labels] = maxflow_v222(obj.graphcut(1).Graph{index}, T);

                    if isempty(obj.shownLabelObj{index})
                        obj.shownLabelObj{index} = labels;
                        Mask = zeros(size(seedImg), 'uint8');
                    else
                        Mask   = cell2mat(obj.mibModel.getData2D('mask', sliceNo, [], [], get2DOpt));
                        negIds = obj.shownLabelObj{index} - labels;
                        posIds = labels - obj.shownLabelObj{index};
                        obj.shownLabelObj{index} = labels;
                    end

                    if isfield(obj.graphcut, 'PixelIdxList')
                        if ~isempty(negIds)
                            Mask(vertcat(obj.graphcut(1).PixelIdxList{index}{negIds>0})) = 0;
                            Mask(vertcat(obj.graphcut(1).PixelIdxList{index}{posIds>0})) = 1;
                        else
                            Mask(vertcat(obj.graphcut(1).PixelIdxList{index}{labels>0})) = 1;
                        end
                    else
                        if ~isempty(negIds)
                            negIds = cast(find(negIds > 0), class(currSlic));
                            posIds = cast(find(posIds > 0), class(currSlic));
                            if ~isempty(negIds); Mask(ismember(currSlic, negIds)) = 0; end
                            if ~isempty(posIds); Mask(ismember(currSlic, posIds)) = 1; end
                        else
                            indexLabel = cast(find(labels>0), class(currSlic));
                            Mask(ismember(currSlic, indexLabel)) = 1;
                        end
                    end

                    Mask(seedImg==bgMaterialId) = 0;
                    if strcmp(obj.graphcut(1).superPixType, 'Watershed') && strcmp(obj.graphcut(1).dilateMode, 'post')
                        Mask = imdilate(Mask, ones(3));
                    end
                    if binVal(1) ~= 1
                        Mask = imresize(Mask, [max(height)-min(height)+1, max(width)-min(width)+1], 'nearest');
                    end
                    obj.mibModel.setData2D(Mask, 'mask', sliceNo, [], [], getDataOptions);

                    if ~isempty(progressBar)
                        progressBar.Value   = index/total;
                        progressBar.Message = 'Calculating...';
                    end
                    index = index + 1;
                end
                singleToolScores = 4;

            else    % 3D modes
                negIds = [];
                posIds = [];

                if numel(obj.shownLabelObj{graphId}) == 0
                    obj.seedObj{graphId} = cell([getDataOptions.z(2)-getDataOptions.z(1)+1 1]);
                    obj.seedBg{graphId}  = cell([getDataOptions.z(2)-getDataOptions.z(1)+1 1]);

                    seedImg = cell2mat(obj.mibModel.getData3D('labels', [], 3, [], getDataOptions));
                    if binVal(1) ~= 1 || binVal(2) ~= 1
                        if ~isempty(progressBar); progressBar.Value = 0.05; progressBar.Message = 'Binning the labels...'; end
                        resizeOptions.height = binHeight;
                        resizeOptions.width  = binWidth;
                        resizeOptions.depth  = binDepth;
                        resizeOptions.method = 'nearest';
                        seedImg = utils.resizeImage3d(seedImg, [], resizeOptions);
                    end
                else
                    sliceId = dataset.slices{3}(1) - obj.graphcut(1).grid.bb(graphId).z(1) + 1;
                    if size(obj.graphcut(graphId).slic, 3) < sliceId
                        if ~isempty(progressBar); delete(progressBar); end
                        return;
                    end
                    getDataOptions.z = [sliceId, sliceId];
                    seedImg = cell2mat(obj.mibModel.getData2D('labels', [], 3, [], getDataOptions));
                    if binVal(1) ~= 1 || binVal(2) ~= 1
                        resizeOptions.height = binHeight;
                        resizeOptions.width  = binWidth;
                        resizeOptions.depth  = 1;
                        resizeOptions.method = 'nearest';
                        seedImg = utils.resizeImage3d(seedImg, [], resizeOptions);
                    end
                end

                if ~isempty(progressBar); progressBar.Value = 0.35; progressBar.Message = 'Defining the labels...'; end

                if numel(obj.shownLabelObj{graphId}) == 0
                    for sliceId = 1:size(obj.graphcut(graphId).slic, 3)
                        currSlicImg = obj.graphcut(graphId).slic(:, :, sliceId);
                        currSeedImg = seedImg(:, :, sliceId);
                        obj.seedObj{graphId}{sliceId} = unique(currSlicImg(currSeedImg==seedMaterialId));
                        if noMaterials == 2
                            obj.seedBg{graphId}{sliceId} = unique(currSlicImg(currSeedImg==bgMaterialId));
                        else
                            obj.seedBg{graphId}{sliceId} = unique(currSlicImg(~ismember(currSeedImg, [0 seedMaterialId])));
                        end
                    end
                else
                    currSlicImg = obj.graphcut(graphId).slic(:, :, sliceId);
                    obj.seedObj{graphId}{sliceId} = unique(currSlicImg(seedImg==seedMaterialId));
                    if noMaterials == 2
                        obj.seedBg{graphId}{sliceId} = unique(currSlicImg(seedImg==bgMaterialId));
                    else
                        obj.seedBg{graphId}{sliceId} = unique(currSlicImg(~ismember(seedImg, [0 seedMaterialId])));
                    end
                end

                labelBg = vertcat(obj.seedBg{graphId}{:});
                for sliceId = 1:size(obj.graphcut(graphId).slic, 3)
                    [~, bgIdx] = intersect(obj.seedObj{graphId}{sliceId}, labelBg);
                    obj.seedObj{graphId}{sliceId}(bgIdx) = [];
                end
                labelObj = vertcat(obj.seedObj{graphId}{:});

                if ~isempty(progressBar); progressBar.Value = 0.45; progressBar.Message = 'Generating data term...'; end

                try
                    T = zeros([obj.graphcut(graphId).noPix, 2]) + 0.5;
                    T(labelObj, 1) = 0;       T(labelObj, 2) = 999999;
                    T(labelBg,  1) = 999999;  T(labelBg,  2) = 0;
                catch err
                    dlgOpt.MsgBoxOnly = true; dlgOpt.Icon = 'puffin_warning';
                    utils.dlgs.inputUniversalDlg(obj.view.gui, '!!! Warning !!!', {''}, ...
                        {sprintf('A supervoxel with index 0 likely exists; try recalculating supervoxels\n\n%s\n%s', err.identifier, err.message)}, ...
                        'Error', dlgOpt);
                end
                T = sparse(T);

                if ~isempty(progressBar); progressBar.Value = 0.55; progressBar.Message = 'Doing maxflow/mincut...'; end
                [~, labels] = maxflow_v222(obj.graphcut(graphId).Graph{1}, T);

                if ~isempty(progressBar); progressBar.Value = 0.75; progressBar.Message = 'Generating the mask...'; end

                if isempty(obj.shownLabelObj{graphId})
                    obj.shownLabelObj{graphId} = labels;
                    Mask = zeros(size(seedImg), 'uint8');
                else
                    negIds = obj.shownLabelObj{graphId} - labels;
                    posIds = labels - obj.shownLabelObj{graphId};
                    obj.shownLabelObj{graphId} = labels;
                end

                if isfield(obj.graphcut(graphId), 'PixelIdxList')
                    if ~isempty(negIds)
                        setDataOpt.PixelIdxList = find(negIds>0);
                        if ~isempty(setDataOpt.PixelIdxList)
                            setDataOpt.PixelIdxList = vertcat(obj.graphcut(graphId).PixelIdxList{setDataOpt.PixelIdxList});
                            setDataOpt.PixelIdxList = dataset.convertPixelIdxListCrop2Full(setDataOpt.PixelIdxList, convertPixelOpt);
                            obj.mibModel.setData3D(zeros([numel(setDataOpt.PixelIdxList), 1], 'uint8'), 'mask', [], [], [], setDataOpt);
                        end
                        setDataOpt.PixelIdxList = find(posIds>0);
                        if ~isempty(setDataOpt.PixelIdxList)
                            setDataOpt.PixelIdxList = vertcat(obj.graphcut(graphId).PixelIdxList{setDataOpt.PixelIdxList});
                            setDataOpt.PixelIdxList = dataset.convertPixelIdxListCrop2Full(setDataOpt.PixelIdxList, convertPixelOpt);
                            obj.mibModel.setData3D(ones([numel(setDataOpt.PixelIdxList), 1], 'uint8'), 'mask', [], [], [], setDataOpt);
                        end
                        if ~isempty(progressBar); delete(progressBar); end
                        return;
                    else
                        Mask(vertcat(obj.graphcut(graphId).PixelIdxList{labels>0})) = 1;
                    end
                else
                    if ~isempty(negIds)
                        negIds = cast(find(negIds > 0), class(obj.graphcut(graphId).slic));
                        posIds = cast(find(posIds > 0), class(obj.graphcut(graphId).slic));
                        if ~isempty(negIds)
                            setDataOpt.PixelIdxList = find(ismember(obj.graphcut(graphId).slic, negIds)>0);
                            setDataOpt.PixelIdxList = dataset.convertPixelIdxListCrop2Full(setDataOpt.PixelIdxList, convertPixelOpt);
                            obj.mibModel.setData3D(zeros([numel(setDataOpt.PixelIdxList), 1], 'uint8'), 'mask', [], [], [], setDataOpt);
                        end
                        if ~isempty(posIds)
                            setDataOpt.PixelIdxList = find(ismember(obj.graphcut(graphId).slic, posIds)>0);
                            setDataOpt.PixelIdxList = dataset.convertPixelIdxListCrop2Full(setDataOpt.PixelIdxList, convertPixelOpt);
                            obj.mibModel.setData3D(ones([numel(setDataOpt.PixelIdxList), 1], 'uint8'), 'mask', [], [], [], setDataOpt);
                        end
                        if ~isempty(progressBar); delete(progressBar); end
                        return;
                    else
                        indexLabel = cast(find(labels>0), class(obj.graphcut(graphId).slic));
                        Mask(ismember(obj.graphcut(graphId).slic, indexLabel)) = 1;
                    end
                end

                if strcmp(obj.graphcut(1).superPixType, 'Watershed') && strcmp(obj.graphcut(1).dilateMode, 'post')
                    Mask = imdilate(Mask, ones([3 3 3]));
                end

                if binVal(1) ~= 1 || binVal(2) ~= 1
                    if ~isempty(progressBar); progressBar.Value = 0.95; progressBar.Message = 'Re-binning the mask...'; end
                    resizeOptions.width  = getDataOptions.x(2)-getDataOptions.x(1)+1;
                    resizeOptions.height = getDataOptions.y(2)-getDataOptions.y(1)+1;
                    resizeOptions.depth  = getDataOptions.z(2)-getDataOptions.z(1)+1;
                    resizeOptions.method = 'nearest';
                    Mask = utils.resizeImage3d(Mask, [], resizeOptions);
                end
                obj.mibModel.setData3D(Mask, 'mask', [], 3, [], getDataOptions);
                singleToolScores = 4;
            end

            if ~isempty(progressBar); delete(progressBar); end

            obj.mibModel.preferences.Users.Tiers.numberOfGraphcuts = obj.mibModel.preferences.Users.Tiers.numberOfGraphcuts + 1;
            notify(obj.mibModel, 'UpdateUserScore', core.ToggleEventData(singleToolScores));
        end

        function superpixelsBtn_Callback(obj, usePrecomputedSlic)
        % SUPERPIXELSBTN_CALLBACK - Compute supervoxels and the boundary graph for all modes.
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      obj.superpixelsBtn_Callback()
        %      obj.superpixelsBtn_Callback(usePrecomputedSlic)
        %
        % Input Arguments:
        %   - **usePrecomputedSlic** *(optional)* — [logical] when ``1``, skip supervoxel
        %     calculation and rebuild the graph from the existing ``obj.graphcut.slic``;
        %     default: ``0``
            if nargin < 2; usePrecomputedSlic = 0; end
            id = obj.mibModel.getActiveId();
            dataset =  obj.mibModel.I{id};

            if usePrecomputedSlic == 0
                status = obj.clearPreprocessBtn_Callback();
                if status == 0; return; end
            end

            if obj.view.handles.supervoxelsAutosaveCheck.Value
                fn_out = dataset.image.filename;
                dotIndex = strfind(fn_out, '.');
                if ~isempty(dotIndex); fn_out = fn_out(1:dotIndex(end)-1); end
                if isempty(strfind(fn_out,'/')) && isempty(strfind(fn_out,'\'))
                    fn_out = fullfile(obj.mibModel.currentDirectory, fn_out);
                end
                if isempty(fn_out); fn_out = obj.mibModel.currentDirectory; end
                [filename, path] = uiputfile({'*.graph', 'Matlab format (*.graph)'}, 'Save Graph...', fn_out);
                if isequal(filename, 0); return; end
                fn_out = fullfile(path, filename);
            end

            tic
            superPixType = obj.view.handles.superpixTypePopup.Value;
            titleStr = sprintf('%s superpixels/supervoxels', superPixType);
            
            col_channel      = find(strcmp(obj.view.handles.imageColChPopup.Items, obj.view.handles.imageColChPopup.Value));
            superpixelSize   = obj.view.handles.superpixelEdit.Value;
            superpixelCompact = obj.view.handles.superpixelsCompactEdit.Value;
            blackOnWhite     = find(strcmp(obj.view.handles.signalPopup.Items, obj.view.handles.signalPopup.Value));

            getDataOptions.x = obj.graphcut(1).bb(1:2);
            getDataOptions.y = obj.graphcut(1).bb(3:4);
            getDataOptions.z = obj.graphcut(1).bb(5:6);

            binVal    = str2num(obj.view.handles.binSubareaEdit.Value); %#ok<ST2NM>
            binWidth  = ceil((getDataOptions.x(2)-getDataOptions.x(1)+1) / binVal(1));
            binHeight = ceil((getDataOptions.y(2)-getDataOptions.y(1)+1) / binVal(1));
            binDepth  = ceil((getDataOptions.z(2)-getDataOptions.z(1)+1) / binVal(2));

            obj.graphcut(1).dilateMode = 'post';

            tilesX = obj.view.handles.chopXedit.Value;
            tilesY = obj.view.handles.chopYedit.Value;
            tilesZ = obj.view.handles.chopZedit.Value;

            switch obj.mode
                case 'mode2dCurrentRadio'
                    progressBar = uiprogressdlg(obj.view.gui, 'Value', 0, 'Message', 'Initiating...', 'Title', titleStr, 'Indeterminate', true, 'Cancelable', true);

                    getDataOptions.z = dataset.slices{3}(1);
                    img = cell2mat(obj.mibModel.getData2D('image', [], [], col_channel, getDataOptions));
                    if binVal(1) ~= 1
                        img = imresize(img, [binHeight binWidth], 'bicubic');
                    end

                    currViewPort = dataset.image.viewPort;
                    if isa(img, 'uint16')
                        if obj.mibModel.onFlyImageStretch
                            img = imadjust(img, stretchlim(img,[0 1]), []);
                        else
                            img = imadjust(img, [currViewPort.min(col_channel)/65535 currViewPort.max(col_channel)/65535], [0 1], currViewPort.gamma(col_channel));
                        end
                        img = uint8(img/255);
                    else
                        if currViewPort.min(col_channel) > 1 || currViewPort.max(col_channel) < 255
                            img = imadjust(img, [currViewPort.min(col_channel)/255 currViewPort.max(col_channel)/255], [0 1], currViewPort.gamma(col_channel));
                        end
                    end

                    dims = size(img);
                    if strcmp(superPixType, 'SLIC')
                        progressBar.Message = 'Calculating SLIC superpixels...';
                        obj.graphcut(1).noPix = ceil(dims(1)*dims(2)/superpixelSize);
                        [obj.graphcut(1).slic, obj.graphcut(1).noPix] = slicmex(img, obj.graphcut(1).noPix, superpixelCompact);
                        obj.graphcut(1).noPix = double(obj.graphcut(1).noPix);
                        obj.graphcut(1).slic  = obj.graphcut(1).slic + 1;
                        STATS = regionprops(obj.graphcut(1).slic, img, 'MeanIntensity');
                        gap = 0;
                        obj.graphcut(1).Edges{1}      = double(imRAG(obj.graphcut(1).slic, gap));
                        obj.graphcut(1).EdgesValues{1} = zeros([size(obj.graphcut(1).Edges{1},1), 1]);
                        meanVals = [STATS.MeanIntensity];
                        for i = 1:size(obj.graphcut(1).Edges{1}, 1)
                            obj.graphcut(1).EdgesValues{1}(i) = abs(meanVals(obj.graphcut(1).Edges{1}(i,1)) - meanVals(obj.graphcut(1).Edges{1}(i,2)));
                        end
                        progressBar.Message = 'Calculating boundary weights...';
                        obj.recalcGraph_Callback();
                    else
                        progressBar.Message = 'Calculating Watershed superpixels...';
                        if blackOnWhite == 1; img = imcomplement(img); end
                        mask = imextendedmin(img, superpixelSize);
                        mask = imimposemin(img, mask);
                        obj.graphcut(1).slic = watershed(mask);
                        progressBar.Message = 'Calculating connectivity...';
                        [obj.graphcut(1).Edges{1}, edgeIndsList] = imRichRAG(obj.graphcut(1).slic);
                        obj.graphcut(1).EdgesValues{1} = cell2mat(cellfun(@(idx) mean(img(idx)), edgeIndsList, 'UniformOutput', false));
                        obj.recalcGraph_Callback();
                        obj.graphcut(1).noPix      = max(obj.graphcut(1).slic(:));
                        obj.graphcut(1).dilateMode = 'pre';
                        if strcmp(obj.graphcut(1).dilateMode, 'pre')
                            obj.graphcut(1).slic = imdilate(obj.graphcut(1).slic, ones(3));
                        end
                    end

                case 'mode2dRadio'
                    progressBar = uiprogressdlg(obj.view.gui, 'Value', 0, 'Message', 'Initiating...', 'Title', titleStr, 'Indeterminate', true, 'Cancelable', true);

                    img = cell2mat(obj.mibModel.getData3D('image', [], [], col_channel, getDataOptions));
                    if binVal(1) ~= 1
                        progressBar.Value = 0.05; progressBar.Message = 'Binning the images...';
                        img2 = zeros([binHeight, binWidth, 1, size(img,4)], class(img));
                        for sliceId = 1:size(img, 4)
                            img2(:,:,:,sliceId) = imresize(img(:,:,:,sliceId), [binHeight binWidth], 'bicubic');
                        end
                        img = img2;
                        clear img2;
                    end
                    img = squeeze(img);

                    currViewPort = dataset.image.viewPort;
                    if isa(img, 'uint16')
                        if obj.mibModel.onFlyImageStretch
                            for sliceId = 1:size(img, 3)
                                img(:,:,sliceId) = imadjust(img(:,:,sliceId), stretchlim(img(:,:,sliceId),[0 1]), []);
                            end
                        else
                            for sliceId = 1:size(img, 3)
                                img(:,:,sliceId) = imadjust(img(:,:,sliceId), [currViewPort.min(col_channel)/65535 currViewPort.max(col_channel)/65535], [0 1], currViewPort.gamma(col_channel));
                            end
                        end
                        img = uint8(img/255);
                    else
                        if currViewPort.min(col_channel) > 1 || currViewPort.max(col_channel) < 255
                            for sliceId = 1:size(img, 3)
                                img(:,:,sliceId) = imadjust(img(:,:,sliceId), [currViewPort.min(col_channel)/255 currViewPort.max(col_channel)/255], [0 1], currViewPort.gamma(col_channel));
                            end
                        end
                    end

                    dims = size(img);
                    if numel(dims) == 2; dims(3) = 1; end
                    obj.graphcut(1).slic  = zeros(size(img));
                    obj.graphcut(1).noPix = zeros([size(img,3), 1]);
                    
                    progressBar.Indeterminate = false;
                    progressStep = floor(dims(3)/20);

                    if strcmp(superPixType, 'SLIC')
                        noPix = ceil(dims(1)*dims(2)/superpixelSize);
                        for i = 1:dims(3)
                            [obj.graphcut(1).slic(:,:,i), noPixCurrent] = slicmex(img(:,:,i), noPix, superpixelCompact);
                            obj.graphcut(1).noPix(i) = double(noPixCurrent);
                            obj.graphcut(1).slic(:,:,i) = obj.graphcut(1).slic(:,:,i) + 1;
                            STATS = regionprops(obj.graphcut(1).slic(:,:,i), img(:,:,i), 'MeanIntensity');
                            gap = 0;
                            Edges      = double(imRAG(obj.graphcut(1).slic(:,:,i), gap));
                            meanVals   = [STATS.MeanIntensity];
                            EdgesValues = zeros([size(Edges,1), 1]);
                            for j = 1:size(Edges,1)
                                EdgesValues(j) = abs(meanVals(Edges(j,1)) - meanVals(Edges(j,2)));
                            end
                            obj.graphcut(1).Edges{i}      = Edges;
                            obj.graphcut(1).EdgesValues{i} = EdgesValues;

                            if progressBar.CancelRequested()
                                delete(progressBar);
                                obj.graphcut = struct();
                                obj.graphcut(1).slic    = [];
                                obj.graphcut(1).noPix   = [];
                                obj.graphcut(1).Graph   = cell(1);
                                obj.graphcut(1).grid    = struct;
                                obj.graphcut(1).version = obj.graphcutVersion;
                                return;
                            end
                            if mod(i, progressStep) == 1
                                progressBar.Value   = i/dims(3);
                                progressBar.Message = sprintf('Calculating (slice %d of %d)\nPlease wait...', i, dims(3));
                            end
                        end
                        obj.recalcGraph_Callback();
                    else
                        if blackOnWhite == 1; img = imcomplement(img); end
                        for i = 1:dims(3)
                            currImg = img(:,:,i);
                            mask = imextendedmin(currImg, superpixelSize);
                            mask = imimposemin(currImg, mask);
                            obj.graphcut(1).slic(:,:,i)    = watershed(mask);
                            [obj.graphcut(1).Edges{i}, edgeIndsList] = imRichRAG(obj.graphcut(1).slic(:,:,i));
                            obj.graphcut(1).EdgesValues{i} = cell2mat(cellfun(@(idx) mean(currImg(idx)), edgeIndsList, 'UniformOutput', false));
                            obj.graphcut(1).Edges{i}       = double(obj.graphcut(1).Edges{i});
                            obj.graphcut(1).noPix(i)       = double(max(max(obj.graphcut(1).slic(:,:,i))));
                            obj.graphcut(1).dilateMode     = 'pre';
                            if strcmp(obj.graphcut(1).dilateMode, 'pre')
                                obj.graphcut(1).slic(:,:,i) = imdilate(obj.graphcut(1).slic(:,:,i), ones(3));
                            end
                            if progressBar.CancelRequested()
                                delete(progressBar);
                                obj.graphcut = struct();
                                obj.graphcut(1).slic    = [];
                                obj.graphcut(1).noPix   = [];
                                obj.graphcut(1).Graph   = cell(1);
                                obj.graphcut(1).grid    = struct;
                                obj.graphcut(1).version = obj.graphcutVersion;
                                return;
                            end
                            if mod(i, progressStep) == 1
                                progressBar.Value   = i/dims(3);
                                progressBar.Message = sprintf('Calculating (slice %d of %d)\nPlease wait...', i, dims(3));
                            end
                        end
                        obj.recalcGraph_Callback();
                    end

                case {'mode3dRadio', 'mode3dGridRadio'}
                    if strcmp(obj.mode, 'mode3dGridRadio') && (tilesX + tilesY + tilesZ == 3)
                        utils.dlgs.showErrorDialog(obj.view.gui, 'The grid has not been defined, please use the Chop fields to specify number of grid blocks.', ...
                            'Grid not defined');
                        return;
                    end
                    progressBar = uiprogressdlg(obj.view.gui, 'Value', 0, 'Message', 'Initiating...', 'Title', titleStr, 'Indeterminate', true, 'Cancelable', true);

                    parLoopOptions.viewPort.min    = dataset.image.viewPort.min(col_channel);
                    parLoopOptions.viewPort.max    = dataset.image.viewPort.max(col_channel);
                    parLoopOptions.viewPort.gamma  = dataset.image.viewPort.gamma(col_channel);
                    parLoopOptions.onFlyImageStretch = obj.mibModel.onFlyImageStretch;
                    parLoopOptions.binVal          = binVal;
                    parLoopOptions.binHeight       = binHeight;
                    parLoopOptions.binWidth        = binWidth;
                    parLoopOptions.binDepth        = binDepth;
                    parLoopOptions.superPixType    = superPixType;
                    parLoopOptions.blackOnWhite    = blackOnWhite;
                    parLoopOptions.superpixelSize  = superpixelSize;
                    parLoopOptions.superpixelCompact = superpixelCompact;
                    parLoopOptions.waitbar         = [];
                    parLoopOptions.tilesX          = tilesX;
                    parLoopOptions.tilesY          = tilesY;

                    Graphcut = obj.graphcut;
                    img      = cell([numel(obj.graphcut(1).grid.bb), 1]);
                    for graphId = 1:numel(obj.graphcut(1).grid.bb)
                        getDataOptions = obj.graphcut(1).grid.bb(graphId);
                        img(graphId)   = obj.mibModel.getData3D('image', [], 3, col_channel, getDataOptions);
                        if usePrecomputedSlic == 0
                            Graphcut(graphId).slic  = 0;
                            Graphcut(graphId).noPix = 0;
                        end
                        Graphcut(graphId).Edges      = cell(1);
                        Graphcut(graphId).EdgesValues = cell(1);
                    end

                    parallelSwitch = strcmp(obj.mode, 'mode3dGridRadio') && obj.view.handles.parforCheck.Value;

                    if parallelSwitch
                        pw = core.PoolWaitbar(numel(obj.graphcut(1).grid.bb), 'Calculating graphs...', obj.view.gui, 'Calculating graphs', true, true);
                        parfor (graphId = 1:numel(obj.graphcut(1).grid.bb), obj.mibModel.preferences.System.cpuParallelLimit)
                            G = Graphcut(graphId);
                            G = controllers.Graphcut.calcSupervoxels(G, img{graphId}, parLoopOptions);
                            fNames = fieldnames(G);
                            for fieldId = 1:numel(fNames)
                                Graphcut(graphId).(fNames{fieldId}) = G.(fNames{fieldId});
                            end
                            pw.increment();
                        end
                        parCancelled = pw.getCancelState();
                        pw.deletePoolWaitbar(true);
                        if parCancelled
                            delete(progressBar);
                            obj.graphcut = struct();
                            obj.graphcut(1).slic    = [];
                            obj.graphcut(1).noPix   = [];
                            obj.graphcut(1).Graph   = cell(1);
                            obj.graphcut(1).grid    = struct;
                            obj.graphcut(1).version = obj.graphcutVersion;
                            return;
                        end
                        obj.graphcut = Graphcut;
                        clear Graphcut;
                    else
                        if numel(obj.graphcut(1).grid.bb) == 1
                            parLoopOptions.waitbar = progressBar;
                        end
                        parLoopOptions.cancelProgressBar = progressBar;
                        for graphId = 1:numel(obj.graphcut(1).grid.bb)
                            progressBar.Value   = graphId/numel(obj.graphcut(1).grid.bb);
                            progressBar.Message = 'Calculating graphcut...';
                            G = Graphcut(graphId);
                            [G, calcCancelled] = controllers.Graphcut.calcSupervoxels(G, img{graphId}, parLoopOptions, usePrecomputedSlic);
                            if calcCancelled
                                delete(progressBar);
                                obj.graphcut = struct();
                                obj.graphcut(1).slic    = [];
                                obj.graphcut(1).noPix   = [];
                                obj.graphcut(1).Graph   = cell(1);
                                obj.graphcut(1).grid    = struct;
                                obj.graphcut(1).version = obj.graphcutVersion;
                                return;
                            end
                            fNames = fieldnames(G);
                            for fieldId = 1:numel(fNames)
                                Graphcut(graphId).(fNames{fieldId}) = G.(fNames{fieldId});
                            end

                            if progressBar.CancelRequested()
                                delete(progressBar);
                                obj.graphcut = struct();
                                obj.graphcut(1).slic    = [];
                                obj.graphcut(1).noPix   = [];
                                obj.graphcut(1).Graph   = cell(1);
                                obj.graphcut(1).grid    = struct;
                                obj.graphcut(1).version = obj.graphcutVersion;
                                return;
                            end
                        end
                        obj.graphcut = Graphcut;
                        clear Graphcut;
                    end

                    for graphId = 1:numel(obj.graphcut(1).grid.bb)
                        obj.seedObj{graphId} = cell([size(obj.graphcut(graphId).slic, 3), 1]);
                        obj.seedBg{graphId}  = cell([size(obj.graphcut(graphId).slic, 3), 1]);
                    end

                    obj.graphcut(1).mode        = obj.mode;
                    obj.graphcut(1).binVal      = binVal;
                    obj.graphcut(1).colCh       = col_channel;
                    obj.graphcut(1).spSize      = superpixelSize;
                    obj.graphcut(1).spCompact   = superpixelCompact;
                    obj.graphcut(1).superPixType = superPixType;
                    obj.graphcut(1).blackOnWhite = blackOnWhite;
                    obj.recalcGraph_Callback();
            end

            if strcmp(obj.mode, 'mode2dCurrentRadio') || strcmp(obj.mode, 'mode2dRadio')
                for graphId = 1:numel(obj.graphcut)
                    if max(obj.graphcut(graphId).noPix) < 256
                        obj.graphcut(graphId).slic = uint8(obj.graphcut(graphId).slic);
                    elseif max(obj.graphcut(1).noPix) < 65536
                        obj.graphcut(graphId).slic = uint16(obj.graphcut(graphId).slic);
                    else
                        obj.graphcut(graphId).slic = uint32(obj.graphcut(graphId).slic);
                    end
                end
                obj.graphcut(1).bb          = [getDataOptions.x getDataOptions.y getDataOptions.z];
                obj.graphcut(1).mode        = obj.mode;
                obj.graphcut(1).binVal      = binVal;
                obj.graphcut(1).colCh       = col_channel;
                obj.graphcut(1).spSize      = superpixelSize;
                obj.graphcut(1).spCompact   = superpixelCompact;
                obj.graphcut(1).superPixType = superPixType;
                obj.graphcut(1).blackOnWhite = blackOnWhite;
            end

            if exist('fn_out', 'var')
                progressBar.Value = 0.95; progressBar.Message = 'Saving Graphcut to a file...';
                Graphcut = rmfield(obj.graphcut, 'Graph'); %#ok<NASGU>
                save(fn_out, 'Graphcut', '-mat', '-v7.3');
                fprintf('MIB: saving graphcut structure to %s -> done!\n', fn_out);
            end

            if obj.view.handles.pixelIdxListCheck.Value
                progressBar.Value = 0.98; progressBar.Message = 'Calculating PixelIdxList...';
                obj.pixelIdxListCheck_Callback();
            end

            progressBar.Value = 1; progressBar.Message = 'Done!';
            obj.view.handles.superpixelsBtn.BackgroundColor = [0.149 0.902 0.1804];
            obj.view.handles.superpixelsCountText.Text = sprintf('Superpixels count: %d', sum([obj.graphcut(:).noPix]));
            obj.view.handles.superpixelsCountText.Tooltip = sprintf('Superpixels count: %d', sum([obj.graphcut(:).noPix]));
            delete(progressBar);
            toc
        end

        function exportSuperpixelsBtn_Callback(obj)
        % EXPORTSUPERPIXELSBTN_CALLBACK - Export the graphcut struct to workspace, file, model, or 3D lines.
            id = obj.mibModel.getActiveId();
            dataset = obj.mibModel.I{id};

            Graphcut = obj.graphcut;
            if isempty(Graphcut(1).noPix); return; end

            dlgOpt.LabelPosition = 'left';
            dlgOpt.WindowHeight = 220;
            answer = utils.dlgs.inputUniversalDlg(obj.view.gui, 'Please select where to export the supervoxels', ...
                {'Export to Matlab'; 'Save to a file'; 'Export to a model'; 'Export to 3DLines'}, ...
                {false; false; false; false}, 'Export supervoxels', dlgOpt);
            if isempty(answer); return; end

            if answer{1} == true
                dlgOpt2.Focus = 1;
                answer2 = utils.dlgs.inputSingleDlg(obj.view.gui, 'A variable for the export to Matlab', 'Graphcut', 'Input variable to export', dlgOpt2);
                if isempty(answer2); return; end
                assignin('base', answer2, Graphcut);
                fprintf('MIB: export superpixel data ("%s") to Matlab -> done!\n', answer2);
            end

            if answer{2} == true
                fn_out = dataset.image.filename;
                dotIndex = strfind(fn_out, '.');
                if ~isempty(dotIndex); fn_out = fn_out(1:dotIndex(end)-1); end
                if isempty(strfind(fn_out,'/')) && isempty(strfind(fn_out,'\'))
                    fn_out = fullfile(obj.mibModel.currentDirectory, fn_out);
                end
                if isempty(fn_out); fn_out = obj.mibModel.currentDirectory; end

                [filename, path] = uiputfile({'*.graph', 'Matlab format (*.graph)'}, 'Save Graph...', fn_out);
                if isequal(filename, 0); return; end
                fn_out = fullfile(path, filename);
                progressBar = uiprogressdlg(obj.view.gui, ...
                    'Message', 'Saving Graphcut to a file...', 'Title', 'Saving to a file', 'Indeterminate', true);
                tic
                if isfield(Graphcut, 'PixelIdxList'); Graphcut = rmfield(Graphcut, 'PixelIdxList'); end
                Graphcut = rmfield(Graphcut, 'Graph'); %#ok<NASGU>
                save(fn_out, 'Graphcut', '-mat', '-v7.3');
                fprintf('MIB: saving graphcut structure to %s -> done!\n', fn_out);
                toc
                delete(progressBar);
            end

            if answer{3} == true
                dlgOpt3.Icon = 'puffin_warning';
                button = utils.dlgs.inputQuestDlg(obj.view.gui, ...
                    sprintf('If you continue the existing model will be removed!'), ...
                    'Export to model', 'Continue', 'Cancel', 'Cancel', dlgOpt3);
                if strcmp(button, 'Cancel'); return; end

                progressBar = uiprogressdlg(obj.view.gui, 'Message', 'Exporting to a model...', 'Title', 'Export', 'Indeterminate', true);

                graphId = 1;
                if strcmp(obj.mode, 'mode3dGridRadio')
                    [winWidth, winHeight] = obj.mibModel.getAxesLimits();
                    centX = mean(winWidth);
                    centY = mean(winHeight);
                    centZ = dataset.slices{3}(1);
                    bbX = mean(vertcat(obj.graphcut(1).grid.bb.x), 2);
                    bbY = mean(vertcat(obj.graphcut(1).grid.bb.y), 2);
                    bbZ = mean(vertcat(obj.graphcut(1).grid.bb.z), 2);
                    bbCenters = [bbX, bbY, bbZ];
                    distances = sqrt((bbCenters(:,1)-centX).^2 + (bbCenters(:,2)-centY).^2 + (bbCenters(:,3)-centZ).^2);
                    [~, graphId] = min(distances);
                    getDataOptions.x = obj.graphcut(1).grid.bb(graphId).x;
                    getDataOptions.y = obj.graphcut(1).grid.bb(graphId).y;
                    getDataOptions.z = obj.graphcut(1).grid.bb(graphId).z;
                end

                if Graphcut(graphId).noPix < 65536
                    modelType = 65535;
                else
                    modelType = 4294967295;
                end

                if dataset.modelExist == 0
                    dataset.createModel(modelType);
                end

                if modelType ~= dataset.labels.maxMaterials
                    dataset.convertModel(modelType);
                end

                if strcmp(Graphcut(1).mode, 'mode2dCurrentRadio')
                    obj.mibModel.setData2D({Graphcut(graphId).slic}, 'labels', [], 3);
                elseif strcmp(Graphcut(1).mode, 'mode3dGridRadio')
                    obj.mibModel.setData3D({Graphcut(graphId).slic}, 'labels', [], 3, [], getDataOptions);
                else
                    obj.mibModel.setData4D({Graphcut(graphId).slic}, 'labels', 3);
                end
                dataset.labels.materialNames = {'1','2'}';
                
                if size(dataset.labels.materialColors, 1) < 65535
                    dataset.labels.materialColors = [dataset.labels.materialColors; rand([65535-Graphcut(graphId).noPix, 3])];
                end
                [pathTemp, fnTemplate] = fileparts(dataset.image.filename);
                dataset.labels.filename       = fullfile(pathTemp, ['Labels_' fnTemplate '.model']);
                dataset.labels.labelsVariable = 'mibModel';
                
                obj.mibModel.showModel = true;
                notify(obj.mibModel, 'ShowImage');
                notify(obj.mibModel, 'UpdateGuiWidgets');
                delete(progressBar);
            end

            if answer{4} == true
                dlgOpt4.Icon = 'puffin_info';
                button = utils.dlgs.inputQuestDlg(obj.view.gui, ...
                    sprintf('Export to 3D lines is only recommended for a relatively small number of supervoxels!'), ...
                    'Export to 3d lines', 'Continue', 'Cancel', 'Cancel', dlgOpt4);
                if strcmp(button, 'Cancel'); return; end

                progressBar = uiprogressdlg(obj.view.gui, 'Value', 0, 'Message', 'Exporting to 3D lines...', 'Title', 'Exporting to 3D lines', 'Indeterminate', true);

                % grid.bb(1) stores the subarea in full-dataset pixel indices.
                % regionprops Centroid values are 1-indexed within the slic array
                % (local coords), so shift them to full-dataset pixel indices before
                % passing to replaceGraph, which uses dataset.image.boundingBox to
                % convert full-dataset pixels to physical units.
                bb1 = obj.graphcut(1).grid.bb(1);
                xOffset = bb1.x(1) - 1;
                yOffset = bb1.y(1) - 1;
                zOffset = bb1.z(1) - 1;

                switch obj.graphcut.mode
                    case 'mode3dRadio'
                        dataset.lines3D.clearContents();
                        STATS  = regionprops(Graphcut.slic, 'Centroid');
                        points = reshape([STATS.Centroid], [3, numel(STATS)])';
                        points(:,1) = points(:,1) + xOffset;
                        points(:,2) = points(:,2) + yOffset;
                        points(:,3) = points(:,3) + zOffset;
                        NodeTable = table(points, 'VariableNames', {'PointsXYZ'});
                        EdgeTable = table([Graphcut.Edges{1}(:,1), Graphcut.Edges{1}(:,2)], Graphcut.EdgesValues{1}, 'VariableNames', {'EndNodes', 'Weight'});
                        G = graph(EdgeTable, NodeTable);
                        G.Nodes.Properties.VariableUnits = {'pixel'};
                        G.Nodes.Properties.UserData.pixSize      = dataset.image.pixSize;
                        G.Nodes.Properties.UserData.BoundingBox  = dataset.image.boundingBox;
                        dataset.lines3D.replaceGraph(G);

                    case 'mode2dRadio'
                        dataset.lines3D.clearContents();
                        treeNames = {};
                        t = []; s = []; w = []; points = [];
                        maxNodeId = 0;
                        for z = 1:size(Graphcut.slic, 3)
                            STATS  = regionprops(Graphcut.slic(:,:,z), 'Centroid');
                            cPoints = reshape([STATS.Centroid], [2, numel(STATS)])';
                            cPoints(:,3) = repmat(z, [size(cPoints,1) 1]);
                            points    = cat(1, points, cPoints);
                            treeNames = [treeNames; repmat({sprintf('SliceNo_%.4d', z + zOffset)}, [size(cPoints,1) 1])];
                            s = [s; Graphcut.Edges{z}(:,1) + maxNodeId];
                            t = [t; Graphcut.Edges{z}(:,2) + maxNodeId];
                            w = [w; Graphcut.EdgesValues{z}];
                            maxNodeId = maxNodeId + max(Graphcut.Edges{z}(:));
                        end
                        points(:,1) = points(:,1) + xOffset;
                        points(:,2) = points(:,2) + yOffset;
                        points(:,3) = points(:,3) + zOffset;
                        NodeTable = table(points, treeNames, 'VariableNames', {'PointsXYZ', 'TreeName'});
                        EdgeTable = table([s, t], w, 'VariableNames', {'EndNodes', 'Weight'});
                        G = graph(EdgeTable, NodeTable);
                        G.Nodes.Properties.VariableUnits = {'pixel', 'string'};
                        G.Nodes.Properties.UserData.pixSize     = dataset.image.pixSize;
                        G.Nodes.Properties.UserData.BoundingBox = dataset.image.boundingBox;
                        progressBar.Message = 'Submitting the 3D lines object...';
                        dataset.lines3D.replaceGraph(G);

                    case 'mode2dCurrentRadio'
                        % z is the full-dataset current slice — correct as-is; only x/y need offset
                        z = dataset.slices{3}(1);
                        STATS  = regionprops(Graphcut.slic, 'Centroid');
                        points = reshape([STATS.Centroid], [2, numel(STATS)])';
                        points(:,1) = points(:,1) + xOffset;
                        points(:,2) = points(:,2) + yOffset;
                        points(:,3) = repmat(z, [size(points,1) 1]);
                        treeNames   = repmat({sprintf('SliceNo_%.4d', z)}, [size(points,1) 1]);
                        s = Graphcut.Edges{1}(:,1);
                        t = Graphcut.Edges{1}(:,2);
                        w = Graphcut.EdgesValues{1};
                        NodeTable = table(points, treeNames, 'VariableNames', {'PointsXYZ', 'TreeName'});
                        EdgeTable = table([s, t], w, 'VariableNames', {'EndNodes', 'Weight'});
                        G = graph(EdgeTable, NodeTable);
                        G.Nodes.Properties.VariableUnits = {'pixel', 'string'};
                        G.Nodes.Properties.UserData.pixSize     = dataset.image.pixSize;
                        G.Nodes.Properties.UserData.BoundingBox = dataset.image.boundingBox;
                        progressBar.Message = 'Submitting the 3D lines object...';
                        dataset.lines3D.replaceGraph(G);

                    otherwise
                        utils.dlgs.showErrorDialog(obj.view.gui, 'This mode is not yet implemented!', 'Not implemented');
                        delete(progressBar);
                        return;
                end
                % make sure that the showLines3D is checked and enabled
                obj.mibModel.showLines3D = true;
                eventdata = core.ToggleEventData({'checkboxes'});
                notify(obj.mibModel, 'UpdateGuiWidgets', eventdata);
                % render image
                notify(obj.mibModel, 'ShowImage');
                delete(progressBar);
            end
        end

        function importSuperpixelsBtn_Callback(obj, noImportSwitch)
        % IMPORTSUPERPIXELSBTN_CALLBACK - Load a saved graphcut struct or pre-computed clusters.
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      obj.importSuperpixelsBtn_Callback()
        %      obj.importSuperpixelsBtn_Callback(noImportSwitch)
        %
        % Input Arguments:
        %   - **noImportSwitch** *(optional)* — [logical] when ``1``, restore the UI from
        %     the current ``obj.graphcut`` without showing the import dialog; default: ``0``
            if nargin < 2; noImportSwitch = 0; end
            id = obj.mibModel.getActiveId();

            if noImportSwitch == 0
                dlgOpt.WindowHeight = 180;
                answer = utils.dlgs.inputUniversalDlg(obj.view.gui, 'Import graphcut structure or precomputed clusters:', ...
                    {'Settings:'}, ...
                    {{'Load from a file', 'Import from Matlab', 'Load precomputed 2D/3D clusters from a file', 1}}, ...
                    'Import graphcut', dlgOpt);
                if isempty(answer); return; end

                switch answer{1}
                    case 'Load from a file'
                        [filename, path] = utils.dlgs.mibUiGetFile( ...
                            {'*.graph;', 'Matlab format (*.graph)'}, ...
                            'Load Graphcut data...', obj.mibModel.currentDirectory);
                        if isequal(filename, 0); return; end

                        progressBar = uiprogressdlg(obj.view.gui, 'Value', 0.05, 'Message', 'Loading preprocessed Graphcut...', 'Title', 'Loading');
                        tic;
                        obj.clearPreprocessBtn_Callback();
                        res = load(fullfile(path, filename{1}), '-mat');
                        Graphcut = res.Graphcut;
                        progressBar.Value = 0.99; progressBar.Message = 'Finishing...';
                        delete(progressBar);
                        toc;

                    case 'Import from Matlab'
                        availableVars = evalin('base', 'whos');
                        idx = ismember({availableVars.class}, {'struct'});
                        if sum(idx) == 0
                            utils.dlgs.showErrorDialog(obj.view.gui, 'Nothing to import...', 'Nothing to import');
                            return;
                        end
                        varNames = {availableVars(idx).name}';
                        idx2 = find(ismember(varNames, 'Graphcut') == 1);
                        if ~isempty(idx2); varNames{end+1} = idx2; end

                        answer2 = utils.dlgs.inputUniversalDlg(obj.view.gui, '', ...
                            {'A variable that contains compatible structure:'}, {varNames}, ...
                            'Input variable for import');
                        if isempty(answer2); return; end

                        tic;
                        obj.clearPreprocessBtn_Callback();
                        try
                            Graphcut = evalin('base', answer2{1});
                        catch exception
                            utils.dlgs.showErrorDialog(obj.view.gui, ...
                                sprintf('The variable was not found in the Matlab base workspace:\n\n%s', exception.message), ...
                                'Missing variable!');
                            return;
                        end
                        toc;

                    case 'Load precomputed 2D/3D clusters from a file'
                        obj.resetDimsBtn_Callback();
                        loadOptions.startDir = obj.mibModel.currentDirectory;

                        dlgOpt2.windowHeight = 300;
                        answer2 = utils.dlgs.inputUniversalDlg(obj.view.gui, 'Import parameters', ...
                            {'Type of clusters:'; 'Clustering mode:'; 'Type of signal (watershed only):'; 'Gaps (watershed only):'; 'Continuous labels:'}, ...
                            {{'Watershed', 'SLIC', 1}; {'2D clusters', '3D clusters', 2}; ...
                             {'black-on-white, dark lines', 'white-on-black, bright lines', 1}; ...
                             {'with gaps', 'without gaps', 1}; {'yes', 'no', 1}}, ...
                            'Import superpixels', dlgOpt2);
                        if isempty(answer2); return; end

                        [filenames, path] = utils.dlgs.mibUiGetFile( ...
                            {'*.tif;*.tiff;*.png;*.jpg;*.jpeg;*.bmp;*.h5;*.hdf5', 'Image files'}, ...
                            'Load precomputed clusters...', loadOptions.startDir);
                        if isequal(filenames, 0); return; end
                        filenames = cellfun(@(f) fullfile(path, f), filenames, 'UniformOutput', false);

                        loaderOptions.waitbar        = true;
                        loaderOptions.mibPath        = obj.mibModel.mibPath;
                        loaderOptions.ParentFigure   = obj.mibGUI;
                        loaderOptions.Font           = obj.mibModel.preferences.System.Font;
                        loaderOptions.silentMode     = false;

                        extReg     = io.ExtensionRegistryLoad();
                        loaderInfo = extReg.resolveLoader(filenames{1}, 'Standard', 'Default');
                        loader     = io.LoaderFactory.create(loaderInfo, loaderOptions);

                        [imginfo, files] = loader.loadMetadata(filenames, loaderOptions);
                        if isempty(imginfo); return; end

                        [img, imginfo] = loader.loadImages(files, imginfo, loaderOptions);
                        if isempty(img); return; end
                        img = squeeze(img(:,:,:,1,1));

                        progressBar = uiprogressdlg(obj.view.gui, 'Value', 0, 'Message', 'Please wait...', 'Title', 'Processing', 'Indeterminate', true);
                        if strcmp(answer2{5}, 'no')
                            progressBar.Message = 'Squeezing the labels...';
                            [a, ~, c] = unique(img);
                            if a(1) == 0; c = c - 1; end
                            img = reshape(c, size(img));
                            clear c;
                        end

                        if strcmp(answer2{2}, '3D clusters')
                            obj.mode2dRadio_Callback(obj.view.handles.mode3dRadio);
                            if strcmp(answer2{4}, 'without gaps')
                                progressBar.Message = 'Adding gaps...';
                                Gmag = imgradient3(img, 'intermediate');
                                Gmag = imbinarize(Gmag);
                                assignin('base', 'Gaps', uint8(Gmag));
                                img(Gmag==1) = 0;
                            end
                            obj.graphcut.mode = 'mode3dRadio';
                        else
                            obj.mode2dRadio_Callback(obj.view.handles.mode2dRadio);
                            if strcmp(answer2{4}, 'without gaps')
                                progressBar.Message = 'Adding gaps...';
                                depth = size(img, 3);
                                for z = 1:depth
                                    gap  = imbinarize(imgradient(img(:,:,z), 'intermediate'));
                                    img2 = img(:,:,z);
                                    img2(gap==1) = 0;
                                    img(:,:,z) = img2;
                                end
                            end
                            obj.graphcut.mode = 'mode2dRadio';
                        end

                        obj.graphcut.superPixType = answer2{1};
                        if strcmp(answer2{3}, 'black-on-white, dark lines')
                            obj.view.handles.signalPopup.Value = obj.view.handles.signalPopup.Items{1};
                        else
                            obj.view.handles.signalPopup.Value = obj.view.handles.signalPopup.Items{2};
                        end

                        obj.view.handles.superpixTypePopup.Value = answer2{1};  % 'Watershed' or 'SLIC'
                        obj.graphcut.noPix = [];
                        obj.graphcut.slic  = img;
                        obj.superpixTypePopup_Callback('keep');
                        obj.superpixelsBtn_Callback(1);
                        delete(progressBar);
                        return;
                end

                obj.view.handles.xSubareaEdit.Value = sprintf('%d:%d', Graphcut(1).bb(1), Graphcut(1).bb(2));
                obj.view.handles.ySubareaEdit.Value = sprintf('%d:%d', Graphcut(1).bb(3), Graphcut(1).bb(4));
                obj.view.handles.zSubareaEdit.Value = sprintf('%d:%d', Graphcut(1).bb(5), Graphcut(1).bb(6));

                switch Graphcut(1).mode
                    case 'mode2dCurrentRadio'; obj.view.handles.mode2dCurrentRadio.Value = true; obj.mode = 'mode2dCurrentRadio';
                    case 'mode2dRadio';        obj.view.handles.mode2dRadio.Value = true;        obj.mode = 'mode2dRadio';
                    case 'mode3dRadio';        obj.view.handles.mode3dRadio.Value = true;        obj.mode = 'mode3dRadio';
                    case 'mode3dGridRadio';    obj.view.handles.mode3dGridRadio.Value = true;    obj.mode = 'mode3dGridRadio';
                end
                obj.clearPreprocessBtn_Callback();
                obj.graphcut = Graphcut;
                clear Graphcut;
            else
                obj.view.handles.xSubareaEdit.Value = sprintf('%d:%d', obj.graphcut(1).bb(1), obj.graphcut(1).bb(2));
                obj.view.handles.ySubareaEdit.Value = sprintf('%d:%d', obj.graphcut(1).bb(3), obj.graphcut(1).bb(4));
                obj.view.handles.zSubareaEdit.Value = sprintf('%d:%d', obj.graphcut(1).bb(5), obj.graphcut(1).bb(6));

                switch obj.graphcut(1).mode
                    case 'mode2dCurrentRadio'; obj.view.handles.mode2dCurrentRadio.Value = true; obj.mode = 'mode2dCurrentRadio';
                    case 'mode2dRadio';        obj.view.handles.mode2dRadio.Value = true;        obj.mode = 'mode2dRadio';
                    case 'mode3dRadio';        obj.view.handles.mode3dRadio.Value = true;        obj.mode = 'mode3dRadio';
                    case 'mode3dGridRadio';    obj.view.handles.mode3dGridRadio.Value = true;    obj.mode = 'mode3dGridRadio';
                end
            end

            if ~isfield(obj.graphcut(1), 'version') || obj.graphcut(1).version < obj.graphcutVersion
                utils.dlgs.showErrorDialog(obj.view.gui, ...
                    sprintf('Incompatible graphcut structure!\nMost likely from an older MIB version (2.12 or older).'), ...
                    'Wrong Graphcut');
                return;
            end

            obj.view.handles.binSubareaEdit.Value = sprintf('%d;%d', obj.graphcut(1).binVal(1), obj.graphcut(1).binVal(2));
            obj.view.handles.imageColChPopup.Value = obj.view.handles.imageColChPopup.Items{obj.graphcut(1).colCh};

            if isfield(obj.graphcut(1), 'scaleFactor')
                obj.view.handles.edgeFactorEdit.Value = obj.graphcut(1).scaleFactor;
            end

            if strcmp(obj.graphcut(1).superPixType, 'SLIC')
                obj.view.handles.superpixTypePopup.Value = 'SLIC';
                obj.slicSize = obj.graphcut(1).spSize;
            else
                obj.view.handles.superpixTypePopup.Value = 'Watershed';
                obj.watershedSize = obj.graphcut(1).spSize;
            end

            obj.view.handles.superpixelEdit.Value         = obj.graphcut(1).spSize;
            obj.view.handles.superpixelsCompactEdit.Value = obj.graphcut(1).spCompact;

            if ~isfield(obj.graphcut(1), 'blackOnWhite'); obj.graphcut(1).blackOnWhite = 1; end
            obj.view.handles.signalPopup.Value = obj.view.handles.signalPopup.Items{obj.graphcut(1).blackOnWhite};

            if ~isfield(obj.graphcut(1), 'Graph')
                obj.recalcGraph_Callback(1);
            end

            if obj.view.handles.pixelIdxListCheck.Value && ~isfield(obj.graphcut, 'PixelIdxList')
                obj.pixelIdxListCheck_Callback();
            end
            if isfield(obj.graphcut, 'PixelIdxList')
                obj.view.handles.pixelIdxListCheck.Value = true;
            end
            if isfield(obj.graphcut, 'tilesX')
                obj.view.handles.chopXedit.Value = obj.graphcut(1).tilesX;
                obj.view.handles.chopYedit.Value = obj.graphcut(1).tilesY;
                obj.view.handles.chopZedit.Value = obj.graphcut(1).tilesZ;
            else
                obj.view.handles.chopXedit.Value = 1;
                obj.view.handles.chopYedit.Value = 1;
                obj.view.handles.chopZedit.Value = 1;
            end

            obj.view.handles.superpixelsBtn.BackgroundColor = [0.149 0.902 0.1804];
            obj.view.handles.superpixelsCountText.Text = sprintf('Superpixels count: %d', sum([obj.graphcut.noPix]));
            obj.superpixTypePopup_Callback('keep');
        end

        function superpixelsPreviewBtn_Callback(obj)
        % SUPERPIXELSPREVIEWBTN_CALLBACK - Show supervoxel boundaries in the selection layer.
            if isempty(obj.graphcut(1).noPix); return; end
            id = obj.mibModel.getActiveId();

            progressBar = uiprogressdlg(obj.view.gui, 'Value', 0, 'Message', 'Please wait...', 'Title', 'Generating superpixels');

            if strcmp(obj.mode, 'mode3dGridRadio')
                [winWidth, winHeight] = obj.mibModel.getAxesLimits();
                centX = mean(winWidth);
                centY = mean(winHeight);
                centZ = obj.mibModel.I{id}.slices{3}(1);
                bbX = mean(vertcat(obj.graphcut(1).grid.bb.x), 2);
                bbY = mean(vertcat(obj.graphcut(1).grid.bb.y), 2);
                bbZ = mean(vertcat(obj.graphcut(1).grid.bb.z), 2);
                distances = sqrt((bbX-centX).^2 + (bbY-centY).^2 + (bbZ-centZ).^2);
                [~, graphId] = min(distances);
                width  = obj.graphcut(1).grid.bb(graphId).width;
                height = obj.graphcut(1).grid.bb(graphId).height;
                depth  = obj.graphcut(1).grid.bb(graphId).depth; %#ok<NASGU>
                getDataOptions.x = obj.graphcut(1).grid.bb(graphId).x;
                getDataOptions.y = obj.graphcut(1).grid.bb(graphId).y;
                getDataOptions.z = obj.graphcut(1).grid.bb(graphId).z;
            else
                width  = str2num(obj.view.handles.xSubareaEdit.Value); %#ok<ST2NM>
                height = str2num(obj.view.handles.ySubareaEdit.Value); %#ok<ST2NM>
                depth  = str2num(obj.view.handles.zSubareaEdit.Value); %#ok<ST2NM>
                getDataOptions.x = [min(width) max(width)];
                getDataOptions.y = [min(height) max(height)];
                getDataOptions.z = [min(depth) max(depth)];
                graphId = 1;
            end
            progressBar.Value = 0.05;

            binVal = str2num(obj.view.handles.binSubareaEdit.Value); %#ok<ST2NM>

            switch obj.mode
                case 'mode2dCurrentRadio'
                    if size(obj.graphcut(1).slic, 3) > 1
                        currSlic = obj.graphcut(graphId).slic(:,:,obj.mibModel.I{id}.slices{3}(1));
                    else
                        currSlic = obj.graphcut(graphId).slic;
                    end
                    progressBar.Value = 0.5;
                    if binVal(1) ~= 1
                        L2 = imresize(currSlic, [max(height)-min(height)+1, max(width)-min(width)+1], 'nearest');
                        L2 = imdilate(L2, ones([3,3])) > L2;
                    else
                        L2 = imdilate(currSlic, ones([3,3])) > currSlic;
                    end
                    progressBar.Value = 0.9;
                    obj.mibModel.setData2D(L2, 'selection', [], [], [], getDataOptions);

                case 'mode2dRadio'
                    if binVal(1) ~= 1
                        resizeOptions.height = max(height)-min(height)+1;
                        resizeOptions.width  = max(width)-min(width)+1;
                        resizeOptions.depth  = max(depth)-min(depth)+1;
                        resizeOptions.method = 'nearest';
                        L2 = utils.resizeImage3d(obj.graphcut(graphId).slic, [], resizeOptions);
                    else
                        L2 = obj.graphcut(graphId).slic;
                    end
                    progressBar.Value = 0.5;
                    for i = 1:size(L2,3)
                        L2(:,:,i) = imdilate(L2(:,:,i), ones([3,3], class(L2))) > L2(:,:,i);
                    end
                    progressBar.Value = 0.9;
                    obj.mibModel.setData3D(uint8(L2), 'selection', [], 3, [], getDataOptions);

                case {'mode3dRadio', 'mode3dGridRadio'}
                    if binVal(1) ~= 1 || binVal(2) ~= 1
                        resizeOptions.height = max(height)-min(height)+1;
                        resizeOptions.width  = max(width)-min(width)+1;
                        resizeOptions.depth  = max(depth)-min(depth)+1;
                        resizeOptions.method = 'nearest';
                        L2 = utils.resizeImage3d(obj.graphcut(graphId).slic, [], resizeOptions);
                    else
                        L2 = obj.graphcut(graphId).slic;
                    end
                    progressBar.Value = 0.5;
                    L2 = imdilate(L2, ones([3,3,3])) > L2;
                    progressBar.Value = 0.9;
                    obj.mibModel.setData3D(L2, 'selection', [], 3, [], getDataOptions);
            end

            progressBar.Value = 1;
            notify(obj.mibModel, 'ShowImage');
            delete(progressBar);
        end

        function superpixTypePopup_Callback(obj, parameter)
        % SUPERPIXTYPE_CALLBACK - Update UI controls when the superpixel type changes.
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      obj.superpixTypePopup_Callback()
        %      obj.superpixTypePopup_Callback(parameter)
        %
        % Input Arguments:
        %   - **parameter** *(optional)* — [char] pass ``'keep'`` to suppress clearing
        %     the preprocessed data after UI update; default: ``'clear'``
            if nargin < 2; parameter = 'clear'; end

            obj.view.handles.chopXedit.Enable    = 'off';
            obj.view.handles.chopYedit.Enable    = 'off';
            obj.view.handles.chopZedit.Enable    = 'off';
            obj.view.handles.parforCheck.Enable  = 'off';
            obj.view.handles.segmentAllBtn.Enable = 'off';

            if strcmp(obj.view.handles.superpixTypePopup.Value, 'SLIC')
                obj.view.handles.superpixelEdit.Value           = obj.slicSize;
                obj.view.handles.compactnessText.Enable         = 'on';
                obj.view.handles.superpixelsCompactEdit.Enable  = 'on';
                if obj.view.handles.mode3dRadio.Value
                    obj.view.handles.chopXedit.Enable = 'on';
                    obj.view.handles.chopYedit.Enable = 'on';
                end
                obj.view.handles.superpixelSize.Text    = sprintf('Size of superpixels');
                obj.view.handles.superpixelSize.Tooltip = 'set approximate size of each superpixel (2D) or supervoxel (3D); smaller gives better segmentation but slower';
                obj.view.handles.superpixelEdit.Tooltip = 'set approximate size of each superpixel (2D) or supervoxel (3D); smaller gives better segmentation but slower';
            else
                obj.view.handles.superpixelEdit.Value           = obj.watershedSize;
                obj.view.handles.compactnessText.Enable         = 'off';
                obj.view.handles.superpixelsCompactEdit.Enable  = 'off';
                obj.view.handles.superpixelSize.Text    = sprintf('Reduce superpixels number');
                obj.view.handles.superpixelSize.Tooltip = 'reduce oversegmentation; higher number gives bigger superpixels';
                obj.view.handles.superpixelEdit.Tooltip = 'reduce oversegmentation; higher number gives bigger superpixels';
            end

            if obj.view.handles.mode3dGridRadio.Value
                obj.view.handles.chopXedit.Enable    = 'on';
                obj.view.handles.chopYedit.Enable    = 'on';
                obj.view.handles.chopZedit.Enable    = 'on';
                obj.view.handles.parforCheck.Enable  = 'on';
                obj.view.handles.segmentAllBtn.Enable = 'on';
            end

            if ~strcmp(parameter, 'keep')
                obj.clearPreprocessBtn_Callback();
            end
        end

        function recalcGraph_Callback(obj, showWaitbar)
        % RECALCGRAPH_CALLBACK - Rebuild the sparse boundary graph from stored edges and scale factor.
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      obj.recalcGraph_Callback()
        %      obj.recalcGraph_Callback(showWaitbar)
        %
        % Input Arguments:
        %   - **showWaitbar** *(optional)* — [logical] show a progress dialog; default: ``0``
            if nargin < 2; showWaitbar = 0; end

            if ~isfield(obj.graphcut(1), 'EdgesValues')
                utils.dlgs.showErrorDialog(obj.view.gui, ...
                    sprintf('The edges are missing!\nPlease press the Superpixels/Graph button to calculate them.'), ...
                    'Missing edges');
                return;
            end

            if showWaitbar
                progressBar = uiprogressdlg(obj.view.gui, 'Value', 0, 'Message', 'Calculating boundary weights...', 'Title', 'Recalculating graph', 'Indeterminate', true);
            end

            for graphId = 1:numel(obj.graphcut)
                obj.graphcut(graphId).scaleFactor = obj.view.handles.edgeFactorEdit.Value;
                
                for i = 1:numel(obj.graphcut(graphId).EdgesValues)
                    edgeMax = max(obj.graphcut(graphId).EdgesValues{i});
                    edgeMin = min(obj.graphcut(graphId).EdgesValues{i});
                    edgeVar = edgeMax - edgeMin;
                    normE   = obj.graphcut(graphId).EdgesValues{i} / edgeVar;
                    EdgesValues = exp(-normE * obj.graphcut(graphId).scaleFactor);

                    Edges2 = fliplr(obj.graphcut(graphId).Edges{i});
                    Edges  = double([obj.graphcut(graphId).Edges{i}; Edges2]);
                    try
                        obj.graphcut(graphId).Graph{i} = sparse(Edges(:,1), Edges(:,2), [EdgesValues EdgesValues]);
                    catch
                    end
                end
            end
            if showWaitbar; delete(progressBar); end
        end

        function pixelIdxListCheck_Callback(obj)
        % PIXELIDXLISTCHECK_CALLBACK - Compute or remove ``PixelIdxList`` from the graphcut struct.
        %
        % When ticked, calls ``regionprops`` for each graphcut element and stores
        % ``PixelIdxList`` to accelerate incremental mask updates during segmentation.
            if isempty(obj.graphcut(1).noPix); return; end

            if ~obj.view.handles.pixelIdxListCheck.Value
                if isfield(obj.graphcut, 'PixelIdxList')
                    obj.graphcut = rmfield(obj.graphcut, 'PixelIdxList');
                end
                return;
            end

            progressBar = uiprogressdlg(obj.view.gui, 'Value', 0, 'Message', 'Calculating PixelIdxList...', 'Title', 'PixelIdxList');
            if obj.view.handles.mode2dCurrentRadio.Value
                STATS = regionprops(obj.graphcut(1).slic, 'PixelIdxList');
                obj.graphcut(1).PixelIdxList = struct2cell(STATS);
            elseif obj.view.handles.mode2dRadio.Value
                depth = size(obj.graphcut(1).slic, 3);
                for sliceId = 1:depth
                    STATS = regionprops(obj.graphcut(1).slic(:,:,sliceId), 'PixelIdxList');
                    obj.graphcut(1).PixelIdxList{sliceId} = struct2cell(STATS);
                    progressBar.Value = sliceId/depth;
                end
            elseif obj.view.handles.mode3dRadio.Value
                STATS = regionprops(obj.graphcut(1).slic, 'PixelIdxList');
                progressBar.Value = 0.8;
                obj.graphcut(1).PixelIdxList = struct2cell(STATS);
            else
                for graphId = 1:numel(obj.graphcut)
                    STATS = regionprops(obj.graphcut(graphId).slic, 'PixelIdxList');
                    obj.graphcut(graphId).PixelIdxList = struct2cell(STATS);
                end
            end
            progressBar.Value = 1;
            delete(progressBar);
        end

        function segmentBtn_Callback(obj)
        % SEGMENTBTN_CALLBACK - Back up the mask, run one segmentation pass, and show the result.
            id = obj.mibModel.getActiveId();
            tic
            if ~strcmp(obj.mode, 'mode2dCurrentRadio')
                obj.mibModel.backup('mask', 1);
            else
                obj.mibModel.backup('mask', 0);
            end

            if strcmp(obj.mode, 'mode3dGridRadio')
                obj.shownLabelObj = cell([numel(obj.graphcut(1).grid.bb) 1]);
                obj.seedObj       = cell([numel(obj.graphcut(1).grid.bb) 1]);
                obj.seedBg        = cell([numel(obj.graphcut(1).grid.bb) 1]);
            elseif strcmp(obj.mode, 'mode2dRadio')
                obj.shownLabelObj = cell([obj.graphcut(1).grid.bb(1).depth 1]);
                obj.seedObj       = cell(1);
                obj.seedBg        = cell(1);
            else
                obj.shownLabelObj = cell(1);
                obj.seedObj       = cell(1);
                obj.seedBg        = cell(1);
            end

            realtimeSwitchLocal = obj.realtimeSwitch;
            obj.realtimeSwitch  = 0;
            obj.doGraphcutSegmentation();
            obj.realtimeSwitch = realtimeSwitchLocal;

            obj.mibModel.I{id}.maskExist = 1;
            obj.mibModel.showMask = true;
            notify(obj.mibModel, 'ShowImage');
            obj.timerElapsed = toc;
            fprintf('Elapsed time: %f seconds\n', obj.timerElapsed);
        end

        function segmentAllBtn_Callback(obj)
        % SEGMENTALLBTN_CALLBACK - Segment every grid tile sequentially and show the result.
            id = obj.mibModel.getActiveId();
            dataset = obj.mibModel.I{id};
            tic
            progressBar = uiprogressdlg(obj.view.gui, 'Value', 0, 'Message', 'Segmenting dataset...', 'Title', 'Segmenting');

            if ~strcmp(obj.mode, 'mode2dCurrentRadio')
                obj.mibModel.backup('mask', 1);
            else
                obj.mibModel.backup('mask', 0);
            end

            obj.shownLabelObj = cell([numel(obj.graphcut(1).grid.bb) 1]);
            obj.seedObj       = cell([numel(obj.graphcut(1).grid.bb) 1]);
            obj.seedBg        = cell([numel(obj.graphcut(1).grid.bb) 1]);

            realtimeSwitchLocal = obj.realtimeSwitch;
            obj.realtimeSwitch  = 0;
            for areaId = 1:numel(obj.shownLabelObj)
                posX = round(mean(obj.graphcut(1).grid.bb(areaId).x));
                posY = round(mean(obj.graphcut(1).grid.bb(areaId).y));
                posZ = round(mean(obj.graphcut(1).grid.bb(areaId).z));
                dataset.moveView(posX, posY, 3);
                dataset.slices{3} = [posZ, posZ];
                notify(obj.mibModel, 'SliceChanged');
                drawnow;
                obj.doGraphcutSegmentation();
                progressBar.Value = areaId/numel(obj.shownLabelObj);
            end
            obj.realtimeSwitch = realtimeSwitchLocal;

            dataset.maskExist = 1;
            obj.mibModel.showMask = true;
            notify(obj.mibModel, 'ShowImage');
            obj.timerElapsed = toc;
            fprintf('Elapsed time: %f seconds\n', obj.timerElapsed);
            progressBar.Value = 1;
            delete(progressBar);
        end

    end
end
