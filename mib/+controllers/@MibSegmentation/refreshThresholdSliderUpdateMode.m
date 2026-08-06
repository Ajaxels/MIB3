function refreshThresholdSliderUpdateMode(obj)
% REFRESHTHRESHOLDSLIDERUPDATEMODE - Switch threshold sliders between interactive and on-release updates.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.refreshThresholdSliderUpdateMode()
%
% Wires the low/high threshold sliders (``thresholdLow``, ``thresholdHigh``) of the
% Segmentation panel->Black and white thresholding tool to the appropriate callback
% type based on the ``threshold3D``/``threshold4D`` checkbox state:
%
%   - **2D mode** (both checkboxes off) - thresholding is fast, so the result is updated
%     interactively while dragging the slider (``ValueChangingFcn``).
%   - **3D/4D mode** (either checkbox on) - thresholding is slow, so the result is updated
%     only once the slider is released (``ValueChangedFcn``).
%
% Call this whenever the ``threshold3D``/``threshold4D`` checkbox state changes, including
% programmatic changes (e.g. when applying a preset or refreshing widgets).
%
% Input Arguments:
%   (none)
%
% Output Arguments:
%   (none)
%

segmHandles = obj.view.handles.panels.segmentation.handles;
if segmHandles.threshold3D.Value || segmHandles.threshold4D.Value
    % 3D/4D mode (slow): update the result only on mouse release
    segmHandles.thresholdLow.ValueChangingFcn = '';
    segmHandles.thresholdHigh.ValueChangingFcn = '';
    segmHandles.thresholdLow.ValueChangedFcn = @obj.thresholdingPanel_Callback;
    segmHandles.thresholdHigh.ValueChangedFcn = @obj.thresholdingPanel_Callback;
else
    % 2D mode (fast): update the result interactively while dragging
    segmHandles.thresholdLow.ValueChangedFcn = '';
    segmHandles.thresholdHigh.ValueChangedFcn = '';
    segmHandles.thresholdLow.ValueChangingFcn = @obj.thresholdingPanel_Callback;
    segmHandles.thresholdHigh.ValueChangingFcn = @obj.thresholdingPanel_Callback;
end
end
