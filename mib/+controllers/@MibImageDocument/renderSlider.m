function renderSlider(obj, sliderType, value)
% RENDERSLIDER - Commit a slider value to the model and redraw the image.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.renderSlider(sliderType, value)
%
% Thin wrapper that records the render time (for throttling) and delegates to the
% matching slider callback, which updates the model slice/frame and redraws. Used
% both for direct (throttled) renders during dragging and as the ``TimerFcn`` of
% the Zarr debounce timer, so it guards against the document being torn down.
%
% Input Arguments:
%   - **sliderType** - [char] ``'slice'`` or ``'frame'``
%   - **value** - [numeric] slider position value to commit
%
% Output Arguments:
%   (none)
%
% See also:
%   ``sliderDragCallback``, ``sliceNumberSlider_Callback``, ``frameNumberSlider_Callback``

% Guard against a pending timer firing during document teardown
if ~isvalid(obj); return; end

obj.lastSliderRenderTime = tic;
switch sliderType
    case 'slice'; obj.sliceNumberSlider_Callback(value);
    case 'frame'; obj.frameNumberSlider_Callback(value);
end

end
