function sliderDragCallback(obj, sliderType, value, isFinal)
% SLIDERDRAGCALLBACK - Handle slice/frame slider dragging with a throttle + final render.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.sliderDragCallback(sliderType, value, isFinal)
%
% Keeps slider dragging interactive. The numeric readout is updated on every
% tick, but the expensive ``showImage`` redraw is rate-limited:
%
%   - **In-memory datasets, and native (zarrMex) zarr datasets** — redraws are
%     throttled by wall-clock time (at most once per ``obj.sliderThrottleInterval``
%     seconds) while dragging and rendered live; intermediate ticks only update the
%     numeric box. On release (``isFinal``) the exact final position is always
%     rendered (trailing edge). Native zarr reads (~5-10 ms) are fast enough to
%     render live, so they share this path for smooth scrolling.
%   - **Python-backend zarr datasets** — out-of-process reads are slower
%     (~15-30 ms+), so the disk read is deferred with a singleShot debounce timer
%     until the user pauses (100 ms).
%
% While dragging, ``obj.sliderDragging`` is set so that ``listener_sliceChanged`` /
% ``listener_frameChanged`` do not write the model value back onto the slider thumb
% (which would fight the user's drag and make the thumb appear to lag/jump).
%
% Input Arguments:
%   - **sliderType** — [char] ``'slice'`` or ``'frame'``
%   - **value** — [numeric] current slider position value
%   - **isFinal** — [logical] ``true`` when called from the slider ``ValueChanged``
%     (release) event; ``false`` for live ``ValueChanging`` drag events
%
% Output Arguments:
%   (none)
%
% See also:
%   ``renderSlider``, ``gui_Callbacks``, ``sliceNumberSlider_Callback``, ``frameNumberSlider_Callback``

% Immediate numeric-box update keeps the readout live during the drag
switch sliderType
    case 'slice'; obj.handles.sliceNumber.Value = round(value);
    case 'frame'; obj.handles.frameNumber.Value = round(value);
end

% Release: always render the exact final position, end the drag
if isFinal
    obj.sliderDragging = false;
    if ~isempty(obj.sliderDebounceTimer) && isvalid(obj.sliderDebounceTimer)
        stop(obj.sliderDebounceTimer);
        delete(obj.sliderDebounceTimer);
        obj.sliderDebounceTimer = [];
    end
    obj.renderSlider(sliderType, value);
    return;
end

firstTick = ~obj.sliderDragging;   % first event of a new drag gesture
obj.sliderDragging = true;

datasetId = obj.mibModel.id;
isZarr = any(obj.mibModel.I{datasetId}.datasetType(1) == ['V' 'B']) && ...
    ~isempty(obj.mibModel.I{datasetId}.image.pyramid.levelNames);

% Slow reads are deferred with a debounce so dragging stays responsive; this is
% needed for the python zarr backend (out-of-process reads are ~15-30 ms+). Native
% zarr reads are fast (~5-10 ms), so they render live through the wall-clock throttle
% below, exactly like in-memory datasets — giving much smoother slice scrolling.
if isZarr && io.zarr.Config.isPython()
    % defer the disk read until the user pauses dragging
    if ~isempty(obj.sliderDebounceTimer) && isvalid(obj.sliderDebounceTimer)
        stop(obj.sliderDebounceTimer);
        delete(obj.sliderDebounceTimer);
    end
    obj.sliderDebounceTimer = timer( ...
        'ExecutionMode', 'singleShot', ...
        'StartDelay',    0.1, ...
        'TimerFcn',      @(~,~) obj.renderSlider(sliderType, value));
    start(obj.sliderDebounceTimer);
    return;
end

% In-memory: throttle live redraws by wall-clock so the thumb stays responsive.
% Always render the first tick of a gesture; skip later ticks that arrive faster
% than the throttle interval (the numeric box has already been updated above).
if ~firstTick && ~isempty(obj.lastSliderRenderTime) && ...
        toc(obj.lastSliderRenderTime) < obj.sliderThrottleInterval
    return;
end
obj.renderSlider(sliderType, value);

end
