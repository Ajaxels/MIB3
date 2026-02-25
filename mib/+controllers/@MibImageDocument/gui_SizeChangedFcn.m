function gui_SizeChangedFcn(obj)
% function gui_SizeChangedFcn(obj)
% Callback triggered when the document figure size changes
%
% This function handles window resize events for MibImageDocument using a
% debounced timer approach. When the window is resized, a global timer is
% created or reset. The actual resize operations (updating axes and redrawing
% images) only execute after 100ms of no resize activity, preventing
% performance issues and aspect ratio glitches during continuous resizing.
%
% When any document in an AppContainer is resized (including divider dragging),
% all visible documents are updated to ensure proper display.
%
% Syntax:
%   obj.gui_SizeChangedFcn()
%
% Parameters:
%   none - automatically called by MATLAB when figure size changes
%
% Return values:
%   none
%
% Technical details:
%   - Uses a global timer stored in MibController to coordinate updates
%     across multiple documents
%   - Timer delay: 100ms (adjustable via StartDelay property)
%   - Prevents callback re-entrance using persistent variables
%   - Handles AppContainer divider dragging by updating all documents
%
%|
% @b Examples:
% @code
% // Automatically triggered by MATLAB when window is resized
% // No manual call needed - set as SizeChangedFcn callback:
% obj.handles.gui.SizeChangedFcn = @(src, evt) obj.gui_SizeChangedFcn();
% @endcode
%
% @code
% // Manual call to force resize update (not typical)
% obj.gui_SizeChangedFcn();
% @endcode
%
% See also: listenerUpdateDatasetAxes, showImage, updateBrushCursor

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
% function executeResizeAll(obj)
% Execute resize operations for all visible documents
%
% This nested function is called by the timer after resize activity stops.
% It updates axes limits and redraws images for all visible documents
% to handle both main window resizing and AppContainer divider dragging.
%
% The function includes re-entrance protection to prevent conflicts if
% somehow called multiple times simultaneously.
%
% Parameters:
%   obj: handle to the MibImageDocument that initiated the resize
%
% Return values:
%   none

persistent inCallback

% Prevent re-entrance - exit if already processing
if ~isempty(inCallback) && inCallback
    return
end

inCallback = true;

try
    % Loop through all document sets and update each visible one
    for setId = 1:numel(obj.mibController.cImageDoc)
        % Check if document exists and is valid
        if ~isempty(obj.mibController.cImageDoc{setId}) && ...
                isvalid(obj.mibController.cImageDoc{setId}.gui)
            drawnow;

            % Update axes for all datasets in this document set
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

            % Trigger image redraw for this document set
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
