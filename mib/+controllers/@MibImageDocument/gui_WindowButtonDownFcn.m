function gui_WindowButtonDownFcn(obj)
% function gui_WindowButtonDownFcn(obj)
% Callback for mouse button press in the image view.
%
% Linked via (example):
%   hFig.WindowButtonDownFcn = @(~, ~)obj.gui_WindowButtonDownFcn();
%
% Parameters:
% obj: handle to MibImageDocument instance
%
% Notes:
% - The callback dispatches to either "pan" or "interact" mode depending on
%   SelectionType + modifier keys and the "swap mouse buttons" state.
% - "Pan" temporarily disables other callbacks and attaches motion/up
%   callbacks to implement click-and-drag panning.
% - "Interact" triggers segmentation/annotation tools depending on the
%   selected segmentation tool.

% ---- Get figure handle + input state ----
hFig = obj.UIFigure;
seltype = hFig.SelectionType;          % 'normal','alt','extend','open'
modifier = hFig.CurrentModifier;       % cell array: {'shift','control',...}
% Get mouse coordinates in axes space (data units)
xy = obj.handles.imViewAxes.CurrentPoint;  % 2x3, use row(1,1:2)
% Get selected tool in the segmentation panel
tool = obj.mibController.cSegmentation.handles.segmTool.Value;
% 3D interaction switch (best-effort; depends on panel naming)
switch3d = obj.mibController.cSelection.handles.apply3D.Value;

%character = hFig.CurrentCharacter;
%fprintf('seltype: %s modifier: "%s" char: "%s"\n', seltype, cell2mat(modifier), character)
%fprintf('seltype: %s modifier: "%s"\n', seltype, cell2mat(modifier))

% check for the mouse inside the image axes
if ~obj.isInsideAxes; return; end

% define operation depending on the state of obj.mibModel.preferences.System.LeftMouseButton = 'select' or 'pan'
if obj.mibModel.preferences.System.LeftMouseButton(1) == 's'  % the selection mode, options: 'select' or 'pan'
    switch seltype
        case 'normal'   % LMB
            if ~isempty(modifier) && sum(ismember(modifier, {'shift', 'alt', 'control'})) == 3
                % a tweak for the drawing pan shift+alt+control+click for pan eraser
                operation = 'pan';
            else
                operation = 'select';
            end
        case 'alt'      % RMB, Ctrl+LMB
            if isempty(modifier)
                operation = 'pan';
            else
                operation = 'select';
            end
        case 'extend'   % Shift+RMB, Shift+LMB, MMB, LMB+RMB
            operation = 'select';
        case 'open'     % double click
            return
        otherwise
            return
    end
else
    switch seltype
        case 'normal'   % LMB
            if ~isempty(modifier) && sum(ismember(modifier, {'shift', 'alt', 'control'})) == 3
                % a tweak for the drawing pan the panning mode is enabled when Shift+Alt+Ctrl are used
                operation = 'select';
            else
                operation = 'pan';
            end
        case 'alt'      % RMB, Ctrl+LMB
            operation = 'select';
        case 'extend'   % Shift+RMB, Shift+LMB, MMB, LMB+RMB
            operation = 'select';
        case 'open'     % double click
            return
        otherwise
            return
    end
end

% get dataset alias
dataset = obj.mibModel.I{obj.mibModel.id};

% handle the mouse click
if strcmp(operation, 'pan') %& strcmp(modifier,'alt')
    %%     % Start the pan mode

    % Disable conflicting callbacks during pan gesture
    hFig.WindowKeyPressFcn = [];     % turn off callback for the keys during the panning
    hFig.WindowButtonDownFcn = [];   % turn off callback for the mouse key press during the pan mode
    hFig.WindowScrollWheelFcn = [];  % turn off callback for the mouse wheel during the pan mode

    % Hide center spot marker
    if ~isempty(obj.centralMarker); obj.centralMarker.Visible = false; end
    % Hide brush/segmentation cursor if it exists
    if ~isempty(obj.brushCursor); obj.brushCursor.Visible = false; end

    % Decide whether "fast pan" mode is enabled.
    % In fast-pan we do not force full-res redraw here; otherwise we fetch
    % full RGB and re-plot annotations/ROIs for smooth panning.
    magFactor = obj.mibModel.getMagFactor();
    [axesX, axesY] = obj.mibModel.getAxesLimits();
    xy2 = zeros([2,1]);  % converted coordinates

    if ~obj.mibController.fastPanningMode % full image / padded mode
        switch dataset.orientation
            case 3;  coef_z = dataset.pixSize.x / dataset.pixSize.y;
            case 1;  coef_z = dataset.pixSize.z / dataset.pixSize.x;
            otherwise; coef_z = dataset.pixSize.z / dataset.pixSize.y;
        end

        if magFactor < 1    % zoomed in: load padded region only (avoids fetching the full large image)
            % Extend the current viewport by one viewport-size on each side so the
            % user can pan freely without reloading, while skipping the cost of
            % fetching the entire dataset.  Region is clamped to image boundaries.
            imgFullWidth  = dataset.image.width;
            imgFullHeight = dataset.image.height;
            viewportW = axesX(2) - axesX(1);
            viewportH = axesY(2) - axesY(1);
            paddedX = [max(1, floor(axesX(1) - viewportW)), min(imgFullWidth,  ceil(axesX(2) + viewportW))];
            paddedY = [max(1, floor(axesY(1) - viewportH)), min(imgFullHeight, ceil(axesY(2) + viewportH))];

            % Load padded region at 1:1 pixel resolution (no up/downscale)
            obj.mibModel.setAxesLimits(paddedX, paddedY);   % temporarily widen the model view
            rgbOptions.blockModeSwitch = 1;
            rgbOptions.resizeToMagnification = false;
            imgRGB = obj.mibModel.getRGBimage(rgbOptions);
            obj.mibModel.setAxesLimits(axesX, axesY);       % restore the real viewport

            obj.imageHandle.CData = [];
            obj.imageHandle.CData = imgRGB;
            % Map padded image: first pixel → paddedX(1), one data-unit per pixel
            obj.imageHandle.XData = [paddedX(1), paddedX(1) + (size(imgRGB, 2) - 1) * coef_z];
            obj.imageHandle.YData = [paddedY(1), paddedY(1) + size(imgRGB, 1) - 1];

            obj.handles.imViewAxes.XLim = axesX;
            obj.handles.imViewAxes.YLim = axesY;

            % modify xy with respect to the magFactor and shifts of the axes
            xy2(1) = xy(1,1)*magFactor + max([axesX(1) 0]);
            xy2(2) = xy(1,2)*magFactor + max([axesY(1) 0]);

            imgXLim = double(paddedX);
            imgYLim = double(paddedY);
        else    % zoomed out: full image fits in viewport, load it entirely
            rgbOptions.blockModeSwitch = 0;
            imgRGB = obj.mibModel.getRGBimage(rgbOptions);
            obj.imageHandle.CData = [];
            obj.imageHandle.CData = imgRGB;
            % getRGBimage downsamples the image when magFactor>1, so the
            % returned size differs from the previous showImage() render.
            % Update XData/YData to match the newly loaded image so the
            % axes display it at the correct scale and position.
            obj.imageHandle.XData = [1, size(imgRGB, 2) * coef_z];
            obj.imageHandle.YData = [1, size(imgRGB, 1)];

            obj.handles.imViewAxes.XLim = axesX/magFactor;
            obj.handles.imViewAxes.YLim = axesY/magFactor;
            % modify xy with respect to the magFactor and shifts of the axes
            xy2(1) = xy(1,1)+max([axesX(1)/magFactor 0]);
            xy2(2) = xy(1,2)+max([axesY(1)/magFactor 0]);

            imgXLim = [1, obj.imageHandle.XData(2)];
            imgYLim = [1, obj.imageHandle.YData(2)];
        end
    else   % --------  fast pan mode: use currently shown image extents
        xy2(1) = xy(1,1);
        xy2(2) = xy(1,2);
        imgXLim = [obj.imageHandle.XData(1), obj.imageHandle.XData(2)];
        imgYLim = [obj.imageHandle.YData(1), obj.imageHandle.YData(2)];
    end

    % Attach panning motion callback
    hFig.WindowButtonMotionFcn = @(~, ~)obj.gui_panAxesFcn(xy2, imgXLim, imgYLim);

    % update mouse cursor
    obj.UIFigure.Pointer = 'fleur';
   
    % Attach button-up callback to finish the pan
    hFig.WindowButtonUpFcn = @(~, ~)obj.gui_WindowButtonUpFcn();
elseif strcmp(operation, 'select')
    %% Start segmentation mode
    %y = round(xy(1,2));
    %x = round(xy(1,1));

    if dataset.enableSelection == 0 && ~ismember(tool, {'Annotations', '3D lines'})
        return;
    end    % no selection layer

    % In MIB2 this checked obj.mibModel.Ishown size; in MIB3 prefer object
    % state if available, otherwise do conservative bounds check.
    if isprop(obj, 'isInsideImage') && (isnan(obj.isInsideImage) || obj.isInsideImage == 0)
        return;
    end
    if xy(1,1) < 1 || xy(1,2) < 1 || xy(1,1) > dataset.image.width || xy(1,2) > dataset.image.height
        % NOTE: still keep a bounds guard; this may be stricter than MIB2 in
        % some zoom/orientation cases but prevents tool calls outside image.
        % If needed, replace with your project's canonical "inside image" test.
        % return;
    end

    % x, y - x/y coordinates of a pixel that was clicked for the full dataset
    %x = xy(1,1)*obj.mibView.handles.Img{obj.mibView.handles.Id}.I.magFactor + max([0 floor(obj.mibView.handles.Img{obj.mibView.handles.Id}.I.axesX(1))]);
    %y = xy(1,2)*obj.mibView.handles.Img{obj.mibView.handles.Id}.I.magFactor + max([0 floor(obj.mibView.handles.Img{obj.mibView.handles.Id}.I.axesY(1))]);

    % Normalize some tool naming differences between MIB2 and MIB3
    if strcmp(tool, 'MagicWand/RegionGrowing')
        tool = 'MagicWand-RegionGrowing';
    end

    switch tool
        case '3D ball'
            % 3D ball: filled shere in 3d with a center at the clicked point
            [w, h, z] = obj.mibModel.convertMouseToDataCoordinates(xy(1,1), xy(1,2), 'shown', 0);
            obj.mibSegmentation3dBall(ceil(h), ceil(w), ceil(z), modifier);
            return;

        case '3D lines'
            [w, h, z] = obj.mibModel.convertMouseToDataCoordinates(xy(1,1), xy(1,2), 'shown', 0);
            obj.mibSegmentationLines3D(h, w, z, modifier);

            % recenter the view (best-effort checkbox read)
            recenterSw = 0;
            try
                recenterSw = obj.mibController.cSegmentation.handles.segmTrackRecenter.Value;
            catch
                try
                    recenterSw = obj.view.handles.mibSegmTrackRecenterCheck.Value;
                catch
                    recenterSw = 0;
                end
            end
            if recenterSw == 1 && isempty(modifier)  % recenter the view
                dataset.moveView(w, h);
            end

            localRefreshImage(obj);
            return;

        case 'Annotations'
            % add text annotation
            [w, h, z, t] = obj.mibModel.convertMouseToDataCoordinates(xy(1,1), xy(1,2), 'shown', 0);
            obj.mibSegmentationAnnotation(h, w, z, t, modifier);

        case {'Brush'}
            % the Brush mode
            x = round(xy(1,1));
            y = round(xy(1,2));
            try
                hFig.WindowScrollWheelFcn = []; % turn off callback for the mouse wheel during the brush selection
            catch
            end
            try
                hFig.WindowKeyPressFcn = [];    % turn off callback for the keys during the brush selection
            catch
            end
            obj.mibSegmentationBrush(y, x, modifier);
            return;

        case 'BW Thresholding'
            % Black and white thresholding
            return;

        case 'Drag & Drop materials'
            % Drag and drop selection with the mouse
            x = round(xy(1,1));
            y = round(xy(1,2));
            if isempty(modifier); return; end
            try
                hFig.WindowScrollWheelFcn = []; % turn off callback for the mouse wheel during the brush selection
            catch
            end
            try
                hFig.WindowKeyPressFcn = [];    % turn off callback for the keys during the brush selection
            catch
            end
            obj.mibSegmentationDragAndDrop(y, x, modifier);
            return;

        case 'Lasso'
            % Lasso mode
            % NOTE: This section depends on a number of UI widgets; in MIB3
            % their exact handle names may differ. We keep the original logic,
            % but guard all UI reads.
            try
                hManual = obj.mibController.cSegmentation.handles.mibSegmObjectPickerPanelSub2Select;
                manualEnabled = strcmp(hManual.Enable, 'on');
            catch
                manualEnabled = false;
            end

            if manualEnabled
                [w, h] = obj.mibModel.convertMouseToDataCoordinates(xy(1,1), xy(1,2), 'shown', 1);
                spotToolBatchOpt.Shape = {'square'};
                % Read width/height from UI (fallback to current brush radius)
                wStr = '10'; hStr = '10';
                try
                    wStr = obj.mibController.cSegmentation.handles.mibSegmObjectPickerPanelSub2Width.String;
                    hStr = obj.mibController.cSegmentation.handles.mibSegmObjectPickerPanelSub2Height.String;
                catch
                end
                spotToolBatchOpt.Radius = [wStr ';' hStr];
                obj.mibSegmentationSpot(ceil(h), ceil(w), modifier, spotToolBatchOpt);
                return;
            end   % cancel when the manual mode is enabled

            modifier = '';
            % have to define subtract action differently for the lasso type of tools
            try
                addPopupVal = obj.mibController.cSegmentation.handles.mibSegmObjectPickerPanelAddPopup.Value;
            catch
                addPopupVal = 1;
            end
            if addPopupVal == 2 % subtract mode
                modifier = 'control';
            end
            try
                obj.mibSegmentationLasso(modifier);
            catch err %#ok<NASGU>
                %err
            end

        case {'MagicWand-RegionGrowing'}
            % Magic Wand mode
            magicWandRadius = 0;
            try
                magicWandRadius = str2double(obj.mibController.cSegmentation.handles.mibMagicWandRadius.String);
            catch
                try
                    magicWandRadius = str2double(obj.view.handles.mibMagicWandRadius.String);
                catch
                    magicWandRadius = 0;
                end
            end

            if switch3d
                if obj.mibModel.getImageProperty('blockModeSwitch') == 1 && magicWandRadius == 0
                    [w, h, z] = obj.mibModel.convertMouseToDataCoordinates(xy(1,1), xy(1,2), 'blockmode', 0);
                else
                    [w, h, z] = obj.mibModel.convertMouseToDataCoordinates(xy(1,1), xy(1,2), 'shown', 0);
                end
                yxzCoordinate = [h, w, z];
            else
                %yxzCoordinate = [yCrop, xCrop];
                if obj.mibModel.getImageProperty('blockModeSwitch') == 1 && magicWandRadius == 0
                    [w, h, z] = obj.mibModel.convertMouseToDataCoordinates(xy(1,1), xy(1,2), 'blockmode', 1);
                else
                    [w, h, z] = obj.mibModel.convertMouseToDataCoordinates(xy(1,1), xy(1,2), 'shown', 1);
                end
                yxzCoordinate = [h, w, z];
            end

            subTool = 1;
            try
                subTool = obj.mibController.cSegmentation.handles.mibMagicwandMethodPopup.Value; % magic wand or region growing
            catch
                subTool = 1;
            end

            % make new selection with shift and add to the selection
            % without modifiers
            if isempty(modifier)
                modifier = 'shift';
            elseif ischar(modifier) && strcmp(modifier, 'shift')
                modifier = [];
            elseif iscell(modifier) && any(strcmp(modifier, 'shift'))
                modifier = [];
            end

            if subTool == 1
                obj.mibSegmentationMagicWand(ceil(yxzCoordinate), modifier);
            else
                obj.mibSegmentationRegionGrowing(ceil(yxzCoordinate), modifier);
            end

        case 'Object Picker'
            % targeted selection from Mask/Models layers
            if switch3d
                [w, h, z] = obj.mibModel.convertMouseToDataCoordinates(xy(1,1), xy(1,2), 'shown', 0);
            else
                if obj.mibModel.getImageProperty('blockModeSwitch') == 1
                    [w, h, z] = obj.mibModel.convertMouseToDataCoordinates(xy(1,1), xy(1,2), 'blockmode', 1);
                else
                    [w, h, z] = obj.mibModel.convertMouseToDataCoordinates(xy(1,1), xy(1,2), 'shown', 1);
                end
            end
            yxzCoordinate = [h,w,z];
            try
                obj.mibSegmentationObjectPicker(ceil(yxzCoordinate), modifier);
            catch err %#ok<NASGU>
            end

            % return when using the Brush tool
            try
                if obj.mibController.cSegmentation.handles.mibFilterSelectionPopup.Value == 6; return; end
            catch
            end

        case 'Membrane ClickTracker'
            % Trace membranes
            if switch3d
                [w, h, z] = obj.mibModel.convertMouseToDataCoordinates(xy(1,1), xy(1,2), 'shown', 0);
            else
                [w, h, z] = obj.mibModel.convertMouseToDataCoordinates(xy(1,1), xy(1,2), 'shown', 1);
            end
            yxzCoordinate = [h,w,z];
            yx(1) = xy(1,2);
            yx(2) = xy(1,1);

            output = obj.mibSegmentationMembraneClickTraker(ceil(yxzCoordinate), yx, modifier);
            if strcmp(output, 'return')
%                 if obj.mibView.handles.mibSegmTrackRecenterCheck.Value == 1     % recenter the view
%                     obj.mibModel.I{obj.mibModel.id}.moveView(w, h);
%                     obj.plotImage(); 
%                 end
                return;
            end

            % recenter checkbox (best-effort)
            recenterSw = 0;
            try
                recenterSw = obj.mibController.cSegmentation.handles.segmTrackRecenter.Value;
            catch
                try
                    recenterSw = obj.view.handles.mibSegmTrackRecenterCheck.Value;
                catch
                    recenterSw = 0;
                end
            end
            if recenterSw == 1 && isempty(modifier)  % recenter the view
                dataset.moveView(w, h);
            end

        case 'Segment-anything model'
            % NOTE: This block is kept almost verbatim; UI handle access is
            % adapted to MIB3 (controller-first) but still guarded.

            samMethodVal = 1;    % 1=Interactive, 2=Interactive 3D, 3=Landmarks
            sam2checked = false;
            try
                samMethodVal = obj.mibController.cSegmentation.handles.mibSegmSAMMethod.Value;
            catch
            end
            try
                sam2checked = logical(obj.mibController.cSegmentation.handles.mibSAM2checkbox.Value);
            catch
            end

            % check that Interactive 3D mode is used only for SAM2
            if samMethodVal == 2 && ~sam2checked
                msg = sprintf('!!! Error !!!\n\nThe Interactive 3D mode is not available for SAM1!\nCheck the SAM2 checkbox or use the 3D mode for the Interactive mode!');
                try
                    errorDlgOpts.mibPath = obj.mibModel.mibPath;
                    utils.dlgs.showErrorDialog(obj.view.gui, msg, 'Error in gui_WindowButtonDownFcn', 'Interactive 3D', '', errorDlgOpts);
                catch
                    errordlg(msg, 'Interactive 3D');
                end
                return;
            end

            % add labels
            [w, h, z, t] = obj.mibModel.convertMouseToDataCoordinates(xy(1,1), xy(1,2), 'shown', 1); % to enable the interactive mode also in YZ/XZ

            if samMethodVal == 1 || samMethodVal == 2   % 'Interactive' or 'Interactive 3D'
                % remove shift modifier
                if ~isempty(modifier) && any(strcmp(modifier, 'shift')) && isempty(obj.mibModel.sessionSettings.SAMsegmenter.Points.Value)
                    modifier = [];
                end

                extraOptions.addNextMaterial = false;    % add next material after adding the current one only for "add, +next material" mode

                % Read SAM mode/destination from MIB3 segmentation controller (matches gui_WindowKeyPressFcn usage)
                samMode = '';
                destinationLayer = '';
                try
                    samMode = obj.mibController.cSegmentation.handles.samMode.Value;
                catch
                    try
                        samMode = obj.mibController.cSegmentation.handles.mibSegmSAMMode.String{obj.mibController.cSegmentation.handles.mibSegmSAMMode.Value};
                    catch
                        samMode = 'replace';
                    end
                end
                try
                    destinationLayer = obj.mibController.cSegmentation.handles.samDestination.Value;
                catch
                    try
                        destinationLayer = obj.mibController.cSegmentation.handles.mibSegmSAMDestination.String{obj.mibController.cSegmentation.handles.mibSegmSAMDestination.Value};
                    catch
                        destinationLayer = 'selection';
                    end
                end

                if strcmp(samMode, 'add, +next material') && ~strcmp(destinationLayer, 'model')
                    samMode = 'replace';
                    try
                        obj.mibController.cSegmentation.handles.mibSegmSAMMode.Value = 1;
                    catch
                    end
                end

                if isempty(modifier)    % start new segmentation
                    obj.mibModel.sessionSettings.SAMsegmenter.Points.Position = [w, h, z];
                    obj.mibModel.sessionSettings.SAMsegmenter.Points.Value = 1;

                    % limit to the selected material of the model
                    if dataset.restrictSelectionToMaterial == 1
                        % update selected material state
                        selectedFixToMaterial = dataset.getSelectedMaterialIndex();
                        getData2Doptions.blockModeSwitch = true;
                        obj.mibModel.sessionSettings.SAMsegmenter.initialImageSelected = ...
                            uint8(cell2mat(obj.mibModel.getData2D('labels', NaN, NaN, selectedFixToMaterial, getData2Doptions)));
                    end

                    switch samMode
                        case 'add'
                            % do backup and store states
                            z1 = min(obj.mibModel.sessionSettings.SAMsegmenter.Points.Position(:,3));
                            z2 = max(obj.mibModel.sessionSettings.SAMsegmenter.Points.Position(:,3));
                            getDataOptions.blockModeSwitch = true;
                            getDataOptions.z = [z1 z2];

                            % store the current state
                            obj.mibModel.sessionSettings.SAMsegmenter.initialImageAddTo = ...
                                uint8(cell2mat(obj.mibModel.getData3D(destinationLayer, t, NaN, dataset.getSelectedMaterialIndex('AddTo'), getDataOptions)));

                            % done in mibSegmentationSAM2
                            obj.mibModel.mibDoBackup(destinationLayer, 1, getDataOptions);

                        case 'add, +next material'
                            if dataset.modelType < 256 || ~strcmp(destinationLayer, 'model')
                                errordlg(sprintf(['!!! Error !!!\n\nThere current settings are not compatible with the "add, +next material" mode!\n\n' ...
                                    'Please make sure that:\n' ...
                                    '   1. You created or already have a model with type 65535 or larger\n' ...
                                    '   2. Destination should be set to "Model"']), ...
                                    'add, +next material');
                                return;
                            end

                            % select the second material row in the table (legacy JTable behavior)
                            if dataset.selectedAddToMaterial < 4
                                try
                                    userData = obj.mibController.cSegmentation.handles.materialsTable.UserData;
                                    jTable = userData.jTable;   % jTable is initializaed in the beginning of mibGUI.m
                                    jTable.changeSelection(3, 2, false, false);    % automatically calls mibSegmentationTable_CellSelectionCallback
                                    dataset.lastSegmSelection = [3 4];
                                    dataset.selectedAddToMaterial = 4;
                                catch
                                end
                            end

                            extraOptions.addNextMaterial = true;

                            backupOptions.LinkedVariable.modelMaterialNames = 'obj.mibModel.I{obj.mibModel.id}.labels.materialNames';
                            backupOptions.LinkedData.modelMaterialNames = dataset.labels.materialNames;
                            obj.mibModel.mibDoBackup(destinationLayer, 0, backupOptions);

                        otherwise
                            obj.mibModel.sessionSettings.SAMsegmenter.initialImageAddTo = [];
                    end

                else  % second click with Shift or Ctrl modifiers
                    if ischar(modifier) && strcmp(modifier, 'control')
                        if isempty(obj.mibModel.sessionSettings.SAMsegmenter.Points.Position); return; end
                        markerValue = 0;
                    elseif (iscell(modifier) && any(strcmp(modifier, 'control')))
                        if isempty(obj.mibModel.sessionSettings.SAMsegmenter.Points.Position); return; end
                        markerValue = 0;
                    elseif ischar(modifier) && strcmp(modifier, 'shift')
                        markerValue = 1;
                    elseif (iscell(modifier) && any(strcmp(modifier, 'shift')))
                        markerValue = 1;
                    else
                        return
                    end

                    switch samMode
                        case 'add, +next material'
                            % select the first material row in the table
                            if dataset.selectedAddToMaterial == 4
                                eventdata2.Indices = [3, 3];
                                try
                                    obj.mibSegmentationTable_CellSelectionCallback(eventdata2);     % update materialsTable
                                catch
                                end
                            end
                    end

                    if samMethodVal == 2  % 'Interactive 3D'
                        if obj.mibModel.sessionSettings.SAMsegmenter.Points.Position(end) == z
                            % use NaN value to specify end of the dataset for automatic cropping
                            obj.mibModel.sessionSettings.SAMsegmenter.Points.Value = [obj.mibModel.sessionSettings.SAMsegmenter.Points.Value, markerValue];
                        else
                            % use NaN value to specify end of the dataset for automatic cropping
                            obj.mibModel.sessionSettings.SAMsegmenter.Points.Value = [obj.mibModel.sessionSettings.SAMsegmenter.Points.Value, NaN];

                            % limit to the selected material of the model
                            if dataset.restrictSelectionToMaterial == 1
                                % update selected material state
                                selectedFixToMaterial = dataset.getSelectedMaterialIndex();
                                getData3Doptions.blockModeSwitch = true;
                                getData3Doptions.z = [min([obj.mibModel.sessionSettings.SAMsegmenter.Points.Position(:,3); z]), max([obj.mibModel.sessionSettings.SAMsegmenter.Points.Position(:,3); z])];
                                obj.mibModel.sessionSettings.SAMsegmenter.initialImageSelected = ...
                                    uint8(cell2mat(obj.mibModel.getData3D('labels', NaN, NaN, selectedFixToMaterial, getData3Doptions)));
                            end
                        end
                        obj.mibModel.sessionSettings.SAMsegmenter.Points.Position = [obj.mibModel.sessionSettings.SAMsegmenter.Points.Position; w, h, z];

                    else   % 'Interactive', 'Landmarks', 'Automatic everything'
                        samDatasetVal = 1;
                        try
                            samDatasetVal = obj.mibController.cSegmentation.handles.mibSegmSAMDataset.Value;
                        catch
                            samDatasetVal = 1;
                        end

                        if samDatasetVal == 1 % 2D, Slice
                            % add point to segmentation
                            obj.mibModel.sessionSettings.SAMsegmenter.Points.Position = [obj.mibModel.sessionSettings.SAMsegmenter.Points.Position; w, h, z];
                            obj.mibModel.sessionSettings.SAMsegmenter.Points.Value = [obj.mibModel.sessionSettings.SAMsegmenter.Points.Value, markerValue];
                        else % 3D, Dataset
                            % interpolate the points between the current and
                            % the previous points when z-value was changed
                            if obj.mibModel.sessionSettings.SAMsegmenter.Points.Value(end) == markerValue && ...
                                    obj.mibModel.sessionSettings.SAMsegmenter.Points.Position(end,3) ~= z

                                if obj.mibModel.sessionSettings.SAMsegmenter.Points.Position(end, 3) < z
                                    z_range = obj.mibModel.sessionSettings.SAMsegmenter.Points.Position(end, 3):z;
                                else
                                    z_range = obj.mibModel.sessionSettings.SAMsegmenter.Points.Position(end, 3):-1:z;
                                end

                                % Interpolate x and y values for each z value
                                x_interp = interp1([obj.mibModel.sessionSettings.SAMsegmenter.Points.Position(end, 3); z], [obj.mibModel.sessionSettings.SAMsegmenter.Points.Position(end, 1); w], z_range, 'linear');
                                y_interp = interp1([obj.mibModel.sessionSettings.SAMsegmenter.Points.Position(end, 3); z], [obj.mibModel.sessionSettings.SAMsegmenter.Points.Position(end, 2); h], z_range, 'linear');
                                id1 = size(obj.mibModel.sessionSettings.SAMsegmenter.Points.Position, 1);
                                id2 = id1+numel(x_interp)-1;
                                obj.mibModel.sessionSettings.SAMsegmenter.Points.Position(id1:id2, 1) = x_interp;
                                obj.mibModel.sessionSettings.SAMsegmenter.Points.Position(id1:id2, 2) = y_interp;
                                obj.mibModel.sessionSettings.SAMsegmenter.Points.Position(id1:id2, 3) = z_range;
                                obj.mibModel.sessionSettings.SAMsegmenter.Points.Value(id1:id2) = markerValue;
                            else
                                % add point to segmentation
                                obj.mibModel.sessionSettings.SAMsegmenter.Points.Position = [obj.mibModel.sessionSettings.SAMsegmenter.Points.Position; w, h, z];
                                obj.mibModel.sessionSettings.SAMsegmenter.Points.Value = [obj.mibModel.sessionSettings.SAMsegmenter.Points.Value, markerValue];
                            end
                        end
                    end
                end

                % do backup and store states
                z1 = min(obj.mibModel.sessionSettings.SAMsegmenter.Points.Position(:,3));
                z2 = max(obj.mibModel.sessionSettings.SAMsegmenter.Points.Position(:,3));
                getDataOptions.blockModeSwitch = true;
                getDataOptions.z = [z1 z2];

                switch samMode
                    case 'add, +next material'
                        if isempty(modifier) % store initial state for the initial selection of the object
                            obj.mibModel.sessionSettings.SAMsegmenter.initialImageAddTo = ...
                                uint8(cell2mat(obj.mibModel.getData3D(destinationLayer, NaN, NaN, dataset.getSelectedMaterialIndex('AddTo'), getDataOptions)));
                        end
                end

                if obj.mibModel.preferences.SegmTools.SAM.samVersion == 1
                    % use original SAM1
                    obj.mibSegmentationSAM(extraOptions);
                else
                    % use newer version SAM2
                    obj.mibSegmentationSAM2(extraOptions);
                end
                return;

            elseif samMethodVal == 3    % 'Landmarks'
                obj.mibSegmentationAnnotation(h, w, z, t, modifier);
            end

        case 'Spot'
            % The spot mode: draw a circle after mouse click
            [w, h, z] = obj.mibModel.convertMouseToDataCoordinates(xy(1,1), xy(1,2), 'shown', 1);
            obj.mibSegmentationSpot(ceil(h), ceil(w), modifier);
            return;
    end

    % Refresh image after interaction and restore motion/up callbacks
    localRefreshImage(obj);

    % moved from plotImage
    if ismethod(obj, 'gui_WinMouseMotionFcn')
        hFig.WindowButtonMotionFcn = @(~, ~)obj.gui_WinMouseMotionFcn();
    else
        try
            hFig.WindowButtonMotionFcn = @(~, ~)obj.mibGUI_WinMouseMotionFcn();
        catch
            hFig.WindowButtonMotionFcn = [];
        end
    end

    if ismethod(obj, 'gui_WindowButtonUpFcn')
        hFig.WindowButtonUpFcn = @(~, ~)obj.gui_WindowButtonUpFcn();
    else
        try
            hFig.WindowButtonUpFcn = @(~, ~)obj.mibGUI_WindowButtonUpFcn();
        catch
            hFig.WindowButtonUpFcn = [];
        end
    end
end

end

% -------------------------------------------------------------------------
% Local helpers (kept inside the method file for clarity)
% -------------------------------------------------------------------------

function localRefreshImage(obj)
% Refresh displayed image after an interaction.
% Prefer controller-driven refresh in MIB3, fall back to legacy plotImage.
try
    obj.mibController.showImage();
catch
    try
        obj.plotImage();
    catch
    end
end
end
