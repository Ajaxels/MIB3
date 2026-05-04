function gui_WindowButtonDownFcn(obj)
% GUI_WINDOWBUTTONDOWNFCN - Callback for mouse button press in the image view.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.gui_WindowButtonDownFcn()
%
% Linked via:
%
%   .. code-block:: matlab
%
%      hFig.WindowButtonDownFcn = @(~, ~)obj.gui_WindowButtonDownFcn();
%
% Input Arguments:
%   (none)
%
% Output Arguments:
%   (none)
%
% **Behavior:**
%   - Dispatches to either ``'pan'`` or ``'interact'`` mode depending on SelectionType + modifier keys and "swap mouse buttons" state
%   - ``'Pan'`` mode temporarily disables other callbacks and attaches motion/up callbacks to implement click-and-drag panning
%   - ``'Interact'`` mode triggers segmentation/annotation tools depending on selected segmentation tool
%

% ---- Get figure handle + input state ----
hFig = obj.UIFigure;
seltype = hFig.SelectionType;          % 'normal','alt','extend','open'
modifier = hFig.CurrentModifier;       % cell array: {'shift','control',...}
% Get mouse coordinates in axes space (data units)
xy = obj.handles.imViewAxes.CurrentPoint;  % 2x3, use row(1,1:2)
% Get selected tool in the segmentation panel
tool = obj.mibController.cSegmentation.handles.segmTool.Value;
% 3D interaction switch (best-effort; depends on panel naming)
switch3d = obj.mibModel.applySegmentationIn3D;

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
            % Use 'control' specifically — not just any non-empty modifier.
            % UIFigure.CurrentModifier can stay stale as {'shift'} after a
            % blocking Python call; checking for 'control' prevents a stale
            % Shift state from turning a plain RMB pan into a select.
            if any(strcmp(modifier, 'control'))
                operation = 'select';
            else
                operation = 'pan';
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

% Split-panel guard: when multiple documents are visible side-by-side, the
% AppContainer may not fire listener_appStateChanged if this document was
% already LastSelected. Ensure the model + UI reflect this document's set
% before any data access. Uses the same setsOps_Callbacks path as
% listener_appStateChanged so dropdown, buffer buttons, mibModel.id, and
% ShowImage all update correctly.
% NOTE: syncActiveSet() must NOT be called before this block — it would
% silently update Sets.selectedSet and make this condition always false,
% preventing the proper full-UI update path from running.
if obj.mibModel.Sets.selectedSet ~= obj.setOfDatasetsIndex
    setName = obj.mibModel.Sets.names{obj.setOfDatasetsIndex};
    obj.mibController.view.handles.panels.activeDataset.handles.sets.Value = setName;
    obj.mibController.cActiveDataset.setsOps_Callbacks([], [], 'sets');
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
    if ~isempty(obj.brushCursor) && isvalid(obj.brushCursor); obj.brushCursor.Visible = false; end
    % Hide quick measure ROI and label during pan to avoid mis-positioned rendering
    if ~isempty(obj.quickMeasure) && isfield(obj.quickMeasure, 'roi') && ...
            ~isempty(obj.quickMeasure.roi) && isvalid(obj.quickMeasure.roi)
        obj.quickMeasure.roi.Visible = false;
    end
    if ~isempty(obj.quickMeasure) && isfield(obj.quickMeasure, 'textH') && ...
            ~isempty(obj.quickMeasure.textH) && isvalid(obj.quickMeasure.textH)
        obj.quickMeasure.textH.Visible = false;
    end
    % Decide whether "fast pan" mode is enabled.
    % In fast-pan we do not force full-res redraw here; otherwise we fetch
    % full RGB and re-plot annotations/ROIs for smooth panning.
    magFactor = obj.mibModel.getMagFactor();
    [axesX, axesY] = obj.mibModel.getAxesLimits();
    xy2 = zeros([2,1]);  % converted coordinates

    if ~obj.mibController.fastPanningMode % full image / padded mode
        % Delete ROI and measurement overlay objects — they use data coordinates
        % that become invalid when the image is reloaded at a different scale;
        % showImage redraws them on release. Not needed in fast-pan mode
        % because the image CData/XData are unchanged there.
        overlayObjs = findobj(obj.handles.imViewAxes, 'tag', 'roi', '-or', 'tag', 'measurements');
        if ~isempty(overlayObjs); delete(overlayObjs); end
        if isempty(obj.imageHandle) || ~isvalid(obj.imageHandle); return; end
        switch dataset.orientation
            case 3;  coef_z = dataset.image.pixSize.x / dataset.image.pixSize.y;
            case 1;  coef_z = dataset.image.pixSize.z / dataset.image.pixSize.x;
            otherwise; coef_z = dataset.image.pixSize.z / dataset.image.pixSize.y;
        end

        % Determine full image dimensions to decide between padded or full load.
        % Use padded loading whenever the viewport shows a sub-region of the
        % image — covers both magFactor < 1 (zoomed in) and magFactor > 1
        % with large images where loading the full image would be too slow.
        getDimsOpts.blockModeSwitch = false;
        [imgFullHeight, imgFullWidth] = dataset.getDatasetDimensions('image', [], getDimsOpts);
        if numel(axesX) < 2 || isnan(axesX(1)); axesX = [1, imgFullWidth]; end
        if numel(axesY) < 2 || isnan(axesY(1)); axesY = [1, imgFullHeight]; end
        viewportW = axesX(2) - axesX(1);
        viewportH = axesY(2) - axesY(1);

        if viewportW < imgFullWidth * 0.99 || viewportH < imgFullHeight * 0.99
            % Partial view: load padded region only (avoids fetching the full large image).
            % Extends the current viewport by one viewport-size on each side so the
            % user can pan freely without reloading, clamped to image boundaries.
            paddedX = [max(1, floor(axesX(1) - viewportW)), min(imgFullWidth,  ceil(axesX(2) + viewportW))];
            paddedY = [max(1, floor(axesY(1) - viewportH)), min(imgFullHeight, ceil(axesY(2) + viewportH))];

            obj.mibModel.setAxesLimits(paddedX, paddedY);   % temporarily widen the model view
            rgbOptions.blockModeSwitch = 1;

            if magFactor < 1
                % Zoomed in: load padded region at 1:1 data pixels (no downscale)
                rgbOptions.resizeToMagnification = false;
                imgRGB = obj.mibModel.getRGBimage(rgbOptions);
                obj.mibModel.setAxesLimits(axesX, axesY);       % restore the real viewport

                obj.imageHandle.CData = [];
                obj.imageHandle.CData = imgRGB;
                % Map padded image: first pixel → paddedX(1), one data-unit per pixel
                obj.imageHandle.XData = [paddedX(1), paddedX(1) + (size(imgRGB, 2) - 1) * coef_z];
                obj.imageHandle.YData = [paddedY(1), paddedY(1) + size(imgRGB, 1) - 1];

                % Set XLim in physical (XData) space so coordinate systems are
                % consistent with showImage and gui_panAxesFcn.
                obj.handles.imViewAxes.XLim = paddedX(1) + (axesX - paddedX(1)) * coef_z;
                obj.handles.imViewAxes.YLim = axesY;  % Y: coef_z == 1
            else
                % Zoomed out but partial view (large image): load padded
                % region downscaled by magFactor — same coordinate system
                % as the full-image path but only loading the padded sub-region.
                imgRGB = obj.mibModel.getRGBimage(rgbOptions);
                obj.mibModel.setAxesLimits(axesX, axesY);       % restore the real viewport

                obj.imageHandle.CData = [];
                obj.imageHandle.CData = imgRGB;
                obj.imageHandle.XData = paddedX * coef_z / magFactor;
                obj.imageHandle.YData = paddedY / magFactor;

                obj.handles.imViewAxes.XLim = axesX * coef_z / magFactor;
                obj.handles.imViewAxes.YLim = axesY / magFactor;
            end

            % Re-read CurrentPoint after XLim change so xy2 is in the new
            % coordinate system (avoids manual coordinate conversion).
            pt2 = obj.handles.imViewAxes.CurrentPoint;
            xy2(1) = pt2(1,1);
            xy2(2) = pt2(1,2);

            imgXLim = [obj.imageHandle.XData(1), obj.imageHandle.XData(2)];
            imgYLim = [obj.imageHandle.YData(1), obj.imageHandle.YData(2)];
        else    % full image fits in viewport, load it entirely
            if magFactor < 1
                % Zoomed in beyond 100%: use blockModeSwitch=0 to load
                % the FULL image (not clipped to current axesX viewport).
                % panModeException (blockModeSwitch=0 && mag<1) skips
                % the upscale in getRGBimage, giving us 1:1 data pixels —
                % the same coordinate system as the padded path above.
                % This keeps gui_panAxesFcn's magFactorFixed=1 correct.
                rgbOptions.blockModeSwitch = 0;
                imgRGB = obj.mibModel.getRGBimage(rgbOptions);
                obj.imageHandle.CData = [];
                obj.imageHandle.CData = imgRGB;
                % 1:1 data-pixel mapping (same as padded path)
                obj.imageHandle.XData = [1, 1 + (size(imgRGB, 2) - 1) * coef_z];
                obj.imageHandle.YData = [1, size(imgRGB, 1)];
                % XLim shows the viewport region within the 1:1 image
                obj.handles.imViewAxes.XLim = 1 + (axesX - 1) * coef_z;
                obj.handles.imViewAxes.YLim = axesY;
            else
                % Zoomed out: blockModeSwitch=0 loads the full image and
                % getRGBimage downsamples it correctly (panModeException=0
                % when magFactor>=1).
                rgbOptions.blockModeSwitch = 0;
                imgRGB = obj.mibModel.getRGBimage(rgbOptions);
                obj.imageHandle.CData = [];
                obj.imageHandle.CData = imgRGB;
                obj.imageHandle.XData = [1, size(imgRGB, 2) * coef_z];
                obj.imageHandle.YData = [1, size(imgRGB, 1)];
                obj.handles.imViewAxes.XLim = axesX * coef_z / magFactor;
                obj.handles.imViewAxes.YLim = axesY / magFactor;
            end
            % Re-read CurrentPoint after XLim change so xy2 is in the new
            % coordinate system (avoids manual coordinate conversion).
            pt2 = obj.handles.imViewAxes.CurrentPoint;
            xy2(1) = pt2(1,1);
            xy2(2) = pt2(1,2);

            imgXLim = [1, obj.imageHandle.XData(2)];
            imgYLim = [1, obj.imageHandle.YData(2)];
        end
    else   % --------  fast pan mode: use currently shown image extents
        xy2(1) = xy(1,1);
        xy2(2) = xy(1,2);
        imgXLim = [obj.imageHandle.XData(1), obj.imageHandle.XData(2)];
        imgYLim = [obj.imageHandle.YData(1), obj.imageHandle.YData(2)];
    end

    % Reposition drawing ROI into the pan coordinate system.
    % Cannot use convertDataToMouseCoordinates here because pan changes
    % the axes coordinate system away from what that function expects.
    if ~obj.mibController.fastPanningMode && obj.mibModel.disableSegmentation
        drawInfo = obj.mibController.cRoi.drawingROI;
        roiH = drawInfo.roi;
        dp   = drawInfo.dataPos;
        %fprintf('[ROI-reposition] active=%d, roiValid=%d, dpEmpty=%d, magFactor=%.3f, type=%s\n', ...
        %    drawInfo.active, ~isempty(roiH) && isvalid(roiH), isempty(dp), magFactor, drawInfo.type);
        if ~isempty(roiH) && isvalid(roiH) && ~isempty(dp)
            obj.mibController.cRoi.drawingROI.repositioning = true;
            try
                if magFactor < 1
                    % 1:1 data-pixel mapping with coef_z stretch on X.
                    % imgXLim(1) is both the axes origin and the data-pixel origin.
                    xO = imgXLim(1);
                    toX = @(x) xO + (x - xO) .* coef_z;
                    toY = @(y) y;
                else
                    % Downsampled image: axes = data * coef_z / magFactor
                    toX = @(x) x .* coef_z ./ magFactor;
                    toY = @(y) y ./ magFactor;
                end

                switch drawInfo.type
                    case 'Rectangle'
                        Xax = toX(dp(:,1));  Yax = toY(dp(:,2));
                        w = Xax(2)-Xax(1);   h = Yax(2)-Yax(1);
                        if w > 0 && h > 0
                            roiH.Position = [Xax(1), Yax(1), w, h];
                        end
                    case 'Ellipse'
                        cx_ax = toX(dp(1));  cy_ax = toY(dp(2));
                        ex_ax = toX(dp(1)+dp(3));
                        ey_ax = toY(dp(2)+dp(4));
                        rx_ax = abs(ex_ax - cx_ax);
                        ry_ax = abs(ey_ax - cy_ax);
                        if rx_ax > 0 && ry_ax > 0
                            roiH.Center   = [cx_ax, cy_ax];
                            roiH.SemiAxes = [rx_ax, ry_ax];
                        end
                    otherwise
                        Xax = toX(dp(:,1));  Yax = toY(dp(:,2));
                        roiH.Position = [Xax(:), Yax(:)];
                end
            catch
            end
            obj.mibController.cRoi.drawingROI.repositioning = false;
        end
    end

    % Attach panning motion callback
    hFig.WindowButtonMotionFcn = @(~, ~)obj.gui_panAxesFcn(xy2, imgXLim, imgYLim);

    % update mouse cursor
    obj.UIFigure.Pointer = 'fleur';
   
    % Attach button-up callback to finish the pan
    hFig.WindowButtonUpFcn = @(~, ~)obj.gui_WindowButtonUpFcn();
elseif strcmp(operation, 'select')
    %% Start segmentation mode
    % skip all segmentation when ROI drawing is active (pan still works)
    if obj.mibModel.disableSegmentation; return; end

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

    switch tool
        case '3D ball'
            % 3D ball: filled shere in 3d with a center at the clicked point
            [w, h, z] = obj.mibModel.convertMouseToDataCoordinates(xy(1,1), xy(1,2), 'shown', 0);
            obj.segmentationBall3D(ceil(h), ceil(w), ceil(z), modifier);
            return;

        case '3D lines'
            [w, h, z] = obj.mibModel.convertMouseToDataCoordinates(xy(1,1), xy(1,2), 'shown', 0);
            obj.segmentationLines3D(h, w, z, modifier);

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

            obj.mibController.showImage();
            return;

        case 'Annotations'
            % add text annotation
            [w, h, z, t] = obj.mibModel.convertMouseToDataCoordinates(xy(1,1), xy(1,2), 'shown', 0);
            obj.segmentationAnnotation(h, w, z, t, modifier);

        case 'Brush'
            % the Brush mode
            x = round(xy(1,1));
            y = round(xy(1,2));
            hFig.WindowScrollWheelFcn = []; % turn off callback for the mouse wheel during the brush selection
            hFig.WindowKeyPressFcn = [];    % turn off callback for the keys during the brush selection
            obj.segmentationBrush(y, x, modifier);
            return;

        case 'BW Thresholding'
            % Black and white thresholding
            return;

        case 'Drag&Drop materials'
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
            obj.segmentationDragAndDrop(y, x, modifier);
            return;

        case 'Lasso'
            % Lasso mode
            % read add/subtract mode from lassoMode dropdown
            modifier = '';
            lassoMode = obj.mibController.cSegmentation.handles.lassoMode.Value;
            if strcmp(lassoMode, 'Subtract')
                modifier = 'control';
            end

            % check if manual mode is enabled
            manualEnabled = obj.mibController.cSegmentation.handles.lassoManually.Value;
            if manualEnabled
                obj.segmentationLassoManual(modifier);
            else
                obj.segmentationLasso(modifier);
            end

        case {'MagicWand/RegionGrowing'}
            % Magic Wand mode
            magicWandRadius = obj.mibController.cSegmentation.handles.magicRadius.Value;

            if switch3d
                if obj.mibModel.getImageProperty('blockModeSwitch') == 1 && magicWandRadius == 0
                    [w, h, z] = obj.mibModel.convertMouseToDataCoordinates(xy(1,1), xy(1,2), 'blockmode', 0);
                else
                    [w, h, z] = obj.mibModel.convertMouseToDataCoordinates(xy(1,1), xy(1,2), 'shown', 0);
                end
                yxzCoordinate = [h, w, z];
            else
                if obj.mibModel.getImageProperty('blockModeSwitch') == 1 && magicWandRadius == 0
                    [w, h, z] = obj.mibModel.convertMouseToDataCoordinates(xy(1,1), xy(1,2), 'blockmode', 1);
                else
                    [w, h, z] = obj.mibModel.convertMouseToDataCoordinates(xy(1,1), xy(1,2), 'shown', 1);
                end
                yxzCoordinate = [h, w, z];
            end

            subTool = obj.mibController.cSegmentation.handles.magicMethod.Value;

            % make new selection with shift and add to the selection without modifiers
            BatchOptIn = struct;
            if isempty(modifier)
                BatchOptIn.Action = 'Add';
            elseif ismember('shift', modifier)
                BatchOptIn.Action = 'Replace';
            elseif ismember('control', modifier)
                BatchOptIn.Action = 'Subtract';
            end
            
            if strcmp(subTool, 'Magic Wand')
                obj.segmentationMagicWand(ceil(yxzCoordinate), BatchOptIn);
            else
                obj.segmentationRegionGrowing(ceil(yxzCoordinate), BatchOptIn);
            end

        case 'Object picker'
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
            obj.segmentationObjectPicker(ceil(yxzCoordinate), modifier);

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

            output = obj.segmentationClickTracker(ceil(yxzCoordinate), yx, modifier);
            if strcmp(output, 'return')
                % recenter the view if enabled
                if obj.mibController.cSegmentation.handles.membraneRecenterView.Value && isempty(modifier)
                    dataset.moveView(w, h);
                    obj.mibController.showImage();
                end
                return;
            end

            % recenter the view after placing a starting point
            if obj.mibController.cSegmentation.handles.membraneRecenterView.Value && isempty(modifier)
                dataset.moveView(w, h);
            end

        case 'Segment-anything model'
            % Interactive segment-anything model

            % Use obj.mibController.currentModifier as the authoritative modifier.
            % Both hFig.CurrentModifier and hFig.SelectionType can become stale
            % after a blocking pyrun() call — key-release events fired during Python
            % execution are queued but never delivered, so both figure properties
            % may still show {'shift'} long after the user released the key.
            % currentModifier is maintained by KeyPressFcn/KeyReleaseFcn and is
            % explicitly reset to {} after every SAM segmentation call, so it always
            % reflects the true keyboard state.
            modifier = obj.mibController.currentModifier;
            
            samVersion = obj.mibController.cSegmentation.handles.samVersion.Value; 
            samMethodVal = obj.mibController.cSegmentation.handles.samMethod.ValueIndex;
            % 1 - Interactive
            % 2 - Interactive 3D
            % 3 - Landmarks
            % 4 - Automatic everything

            % check that Interactive 3D mode is used only for SAM2
            if samMethodVal == 2 && strcmp(samVersion, 'SAM1')
                msg = sprintf('The Interactive 3D mode is not available for SAM1!\nChange Version to "SAM2" or use the Dataset: "3D Stack" for the Interactive mode!');
                errorDlgOpts.mibPath = obj.mibModel.mibPath;
                utils.dlgs.showErrorDialog(obj.view.gui, msg, 'Error in gui_WindowButtonDownFcn', 'SAM Interactive 3D', '', errorDlgOpts);
                return;
            end

            % add labels
            [w, h, z, t] = obj.mibModel.convertMouseToDataCoordinates(xy(1,1), xy(1,2), 'shown', 1); % to enable the interactive mode also in YZ/XZ

            if samMethodVal < 3 % 'Interactive' or 'Interactive 3D'
                % remove shift modifier
                if ~isempty(modifier) && any(strcmp(modifier, 'shift')) && isempty(obj.mibModel.sessionSettings.SAMsegmenter.Points.Value)
                    modifier = [];
                end

                extraOptions.addNextMaterial = false;    % add next material after adding the current one only for "add, +next material" mode

                % Read SAM mode/destination from MIB3 segmentation controller (matches gui_WindowKeyPressFcn usage)
                samMode = obj.mibController.cSegmentation.handles.samMode.Value;
                destinationLayer = obj.mibController.cSegmentation.handles.samDestination.Value;

                if strcmp(samMode, 'add, +next material') && ~strcmp(destinationLayer, 'labels')
                    samMode = 'replace';
                    obj.mibController.cSegmentation.handles.samMode.Value = 'replace';
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

                            % for Interactive 3D the z-range grows with each Shift+click so
                            % backup is owned by segmentationSAM2 (with full range each time);
                            % for all other methods backup is done here
                            if samMethodVal ~= 2
                                obj.mibModel.backup(destinationLayer, 1, getDataOptions);
                            end

                        case 'add, +next material'
                            if dataset.labels.maxMaterials < 256 || ~strcmp(destinationLayer, 'labels')
                                utils.dlgs.showErrorDialog(obj.mibModel.mibGUI, ...
                                    sprintf(['The current settings are not compatible with the "add, +next material" mode!\n\n' ...
                                    'Please make sure that:\n' ...
                                    '   1. You created or already have a model with type 65535 or larger\n' ...
                                    '   2. Destination should be set to "Model"']), ...
                                    'Error', 'add, +next material');
                                return;
                            end

                            % select the second material row in the table
                            if dataset.selectedAddToMaterial < 4
                                tableHandle = obj.mibController.cSegmentation.handles.materialsTable;
                                scroll(tableHandle, 'row', 4);
                                obj.mibController.cSegmentation.materialsTable_CellSelectionCallback([4, 3]);
                            end

                            extraOptions.addNextMaterial = true;

                            backupOptions.LinkedVariable.modelMaterialNames = 'obj.I{obj.id}.labels.materialNames';
                            backupOptions.LinkedData.modelMaterialNames = dataset.labels.materialNames;
                            obj.mibModel.backup(destinationLayer, 0, backupOptions);

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
                    case 'add'
                        if samMethodVal == 2 && ~isempty(modifier)
                            % Interactive 3D + Shift+click: z-range just grew, so
                            % refresh initialImageAddTo to match the new [z1,z2] extent.
                            % Without this, bitor() in segmentationSAM2 would broadcast
                            % a stale single-slice state across the full 3D output.
                            obj.mibModel.sessionSettings.SAMsegmenter.initialImageAddTo = ...
                                uint8(cell2mat(obj.mibModel.getData3D(destinationLayer, t, NaN, dataset.getSelectedMaterialIndex('AddTo'), getDataOptions)));
                        end
                    case 'add, +next material'
                        if isempty(modifier) % store initial state for the initial selection of the object
                            obj.mibModel.sessionSettings.SAMsegmenter.initialImageAddTo = ...
                                uint8(cell2mat(obj.mibModel.getData3D(destinationLayer, NaN, NaN, dataset.getSelectedMaterialIndex('AddTo'), getDataOptions)));
                        end
                end

                if strcmp(samVersion, 'SAM1')
                    % use original SAM1
                    obj.segmentationSAM(extraOptions);
                else
                    % use newer version SAM2
                    obj.segmentationSAM2(extraOptions);
                end

                % Key-release events fired during the blocking Python call are
                % lost in some MATLAB versions, leaving currentModifier stale.
                % Reset it explicitly so scroll wheel and other callbacks see
                % the correct (no-modifier) state after SAM completes.
                obj.mibController.currentModifier = {};
                return;

            elseif samMethodVal == 3    % 'Landmarks'
                obj.segmentationAnnotation(h, w, z, t, modifier);
            end

        case 'Spot'
            % The spot mode: draw a circle after mouse click
            [w, h, z] = obj.mibModel.convertMouseToDataCoordinates(xy(1,1), xy(1,2), 'shown', 1);
            obj.segmentationSpot(ceil(h), ceil(w), modifier);
            return;
    end

    % Refresh image after interaction and restore motion/up callbacks
    obj.mibController.showImage();

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
