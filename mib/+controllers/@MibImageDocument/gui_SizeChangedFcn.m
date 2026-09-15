function gui_SizeChangedFcn(obj)
% GUI_SIZECHANGEDFCN - Callback triggered when the document figure size changes.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.gui_SizeChangedFcn()
%
% This function handles window resize events for MibImageDocument in two stages.
%
% The expensive stage - recomputing the field of view of every dataset and re-rendering the
% images - is debounced: a global timer is created or reset on each resize event and only
% fires after 100ms of no resize activity, which keeps continuous dragging responsive.
%
% The cheap stage runs immediately, because the debounce alone leaves the image visibly
% distorted in the meantime. The image axes is kept in stretch-to-fill mode
% (``DataAspectRatioMode = 'auto'``), so an undistorted image requires the ``XLim``/``YLim``
% spans to stay numerically equal to the width/height of the axes in pixels. A resize changes
% the pixel box while the limits still hold their old values, and maximizing the window turns
% that into a 2-3x stretch held for several hundred milliseconds. The limits are therefore
% rewritten for the new size right away, before the stretched frame can be presented.
%
% When any document in an AppContainer is resized (including divider dragging),
% all visible documents are updated to ensure proper display.
%
% Input Arguments:
%   (none - automatically called by MATLAB when figure size changes)
%
% Output Arguments:
%   (none)
%
% **Technical details:**
%   - Uses global timer stored in MibController to coordinate updates across multiple documents
%   - Timer delay: 100ms (adjustable via ``StartDelay`` property)
%   - Prevents callback re-entrance using persistent variables
%   - Handles AppContainer divider dragging by updating all documents
%   - ``imViewAxes.InnerPosition`` is still the pre-resize value while this callback runs;
%     only ``UIFigure.Position`` is already current, hence the predicted axes size based on
%     ``obj.axesDecorationSize``. Calling ``drawnow`` here to refresh InnerPosition is not an
%     option - it would present the stretched frame that this stage exists to avoid
%
% **Example 1** - automatically triggered when window is resized:
%
%   .. code-block:: matlab
%
%      obj.handles.gui.SizeChangedFcn = @(src, evt) obj.gui_SizeChangedFcn();
%
% **Example 2** - manual call to force resize update (not typical):
%
%   .. code-block:: matlab
%
%      obj.gui_SizeChangedFcn();
%
% See also:
%   ``listener_updateDatasetAxes``, ``showImage``, ``updateBrushCursor``
%

% Rewrite the axes limits for the new size straight away, so that the image is never
% presented stretched while the debounced update below is pending. The maths mirrors the
% 'resize' mode of controllers.MibController.listener_updateDatasetAxes (keep magFactor,
% keep the centre of the field of view, expand or contract it to the new axes size) and the
% limits that controllers.MibController.showImage derives from it. Nothing is written back
% to the model and no image is regenerated here - the timer below remains authoritative.
if ~isempty(obj.axesDecorationSize) && isvalid(obj.handles.imViewAxes) && ...
        obj.setOfDatasetsIndex <= numel(obj.mibModel.Sets.selectedDataset)
    newAxesSize = obj.UIFigure.Position(3:4) - obj.axesDecorationSize;
    datasetId = obj.mibModel.Sets.selectedDataset(obj.setOfDatasetsIndex) + ...
        obj.mibModel.Sets.datasetsInSet * (obj.setOfDatasetsIndex - 1);

    if all(newAxesSize > 1) && datasetId <= numel(obj.mibModel.I)
        dataset = obj.mibModel.I{datasetId};
        [axesX, axesY] = dataset.getAxesLimits();

        % NaN limits mean the dataset has not been shown yet; the deferred update fits it
        % to the screen and computes a magFactor, there is nothing to preserve here
        if ~isnan(axesX(1))
            switch dataset.orientation
                case 3      % xy
                    coefZ = dataset.image.pixSize.x / dataset.image.pixSize.y;
                case 1      % zx
                    coefZ = dataset.image.pixSize.z / dataset.image.pixSize.x;
                case 2      % zy
                    coefZ = dataset.image.pixSize.z / dataset.image.pixSize.y;
            end
            magFactor = dataset.magFactor;

            % field of view for the new axes size, centred as before
            xCenter = (axesX(1) + axesX(2)) / 2;
            yCenter = (axesY(1) + axesY(2)) / 2;
            axesX = xCenter + [-1, 1] * newAxesSize(1) * magFactor / (2 * coefZ);
            axesY = yCenter + [-1, 1] * newAxesSize(2) * magFactor / 2;

            % the part of the field of view that lies outside the image becomes the empty
            % margin on the left/top; the rest of the span is the axes size in pixels
            xLimLeft = min(axesX(1), 0) * coefZ / magFactor;
            yLimTop = min(axesY(1), 0) / magFactor;
            obj.handles.imViewAxes.XLim = [xLimLeft, xLimLeft + newAxesSize(1)];
            obj.handles.imViewAxes.YLim = [yLimTop, yLimTop + newAxesSize(2)];
        end
    end
end

% Check if global resize timer property exists in MibController
if ~isprop(obj.mibController, 'globalResizeTimer')
    % Add dynamic property to store the global timer
    addprop(obj.mibController, 'globalResizeTimer');
    obj.mibController.globalResizeTimer = [];
end

% If timer already exists and is running, stop and delete it
% This resets the timer on each resize event (debouncing)
if ~isempty(obj.mibController.globalResizeTimer) && ...
        isvalid(obj.mibController.globalResizeTimer)
    stop(obj.mibController.globalResizeTimer);
    delete(obj.mibController.globalResizeTimer);
end

% Create new single-shot timer that executes after resize stops
obj.mibController.globalResizeTimer = timer(...
    'ExecutionMode', 'singleShot', ...
    'StartDelay', 0.1, ...  % 100ms delay - adjust if needed
    'TimerFcn', @(~,~) executeResizeAll(obj));

% Start the timer
start(obj.mibController.globalResizeTimer);

end

function executeResizeAll(obj)
% EXECUTERESIZEALL - Execute resize operations for all visible documents.
%
% Syntax:
%   .. code-block:: matlab
%
%      executeResizeAll(obj)
%
% Nested function called by timer after resize activity stops. Updates axes limits and
% redraws images for all visible documents to handle both main window resizing and
% AppContainer divider dragging.
%
% Includes re-entrance protection to prevent conflicts if called multiple times simultaneously.
%
% Input Arguments:
%   - **obj** - [handle] MibImageDocument instance that initiated the resize
%
% Output Arguments:
%   (none)
%

persistent inCallback

% Prevent re-entrance - exit if already processing
if ~isempty(inCallback) && inCallback
    return
end

inCallback = true;

try
    % Process all pending layout updates ONCE before reading InnerPosition,
    % so all documents in a split-panel view have current dimensions.
    drawnow;

    % Loop through all document sets and update each one
    for setId = 1:numel(obj.mibController.cImageDoc)
        % Check if document exists and is valid
        if ~isempty(obj.mibController.cImageDoc{setId}) && ...
                isvalid(obj.mibController.cImageDoc{setId}.gui)

            % Update axes for all datasets in this document set (cheap math only)
            globalFirstIndex = 1 + ((setId-1) * obj.mibModel.Sets.datasetsInSet);

            for i = globalFirstIndex:globalFirstIndex+obj.mibModel.Sets.datasetsInSet-1
                % Verify dataset exists before updating
                if i <= numel(obj.mibModel.I)
                    Options.mode = 'resize';
                    Options.index = i;
                    Options.setOfDatasetsIndex = setId;
                    eventdata = core.ToggleEventData(Options);
                    notify(obj.mibModel, 'UpdateDatasetAxes', eventdata);
                end
            end

            % Trigger image redraw for this document set.
            % All valid documents need ShowImage - in split-panel view multiple
            % documents are visible simultaneously and all need re-rendering.
            OptionsShowImage.setOfDatasetsIndex = setId;
            eventdataShowImage = core.ToggleEventData(OptionsShowImage);
            notify(obj.mibModel, 'ShowImage', eventdataShowImage);

            % Update brush cursor to match new axes size
            obj.mibController.cImageDoc{setId}.brushCursorOffset = []; % clear brush offset to recalculate it
            %obj.mibController.cImageDoc{setId}.updateBrushCursor([], [], false);
            obj.mibController.cImageDoc{setId}.updateBrushCursor();
        end
    end

catch ME
    % Ensure callback flag is reset even if error occurs
    inCallback = false;
    rethrow(ME);
end

% Reset callback flag
inCallback = false;

end
