function listener_frameChanged(obj)
% LISTENER_FRAMECHANGED - Listener callback for the MibModel 'FrameChanged' event.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.listener_frameChanged()
%
% Synchronises the frame-number edit box and slider of this image document
% with the current time point stored in the model (``slices{5}``), then
% redraws the image.
%
% Called automatically when:
%   .. code-block:: matlab
%
%      notify(obj.mibModel, 'FrameChanged');
%
% **Important notes:**
%   - The caller must update ``mibModel.I{id}.slices{5}`` to the new frame value BEFORE firing the event
%   - This method guards against changes from different documents in split-panel mode (``selectedSet ~= setOfDatasetsIndex``)
%   - Updates widgets DIRECTLY; does NOT delegate to ``frameNumber_Callback`` or ``frameNumberSlider_Callback``
%     (which would create an infinite loop by firing ``FrameChanged`` themselves)
%
% Input Arguments:
%   (none — called via ``@(~,~) obj.listener_frameChanged()``)
%
% Output Arguments:
%   (none)
%
% **Example** — wired in ``setupCallbacks``:
%
%   .. code-block:: matlab
%
%      obj.listeners{end+1} = addlistener(obj.mibModel, 'FrameChanged', ...
%          @(~,~) obj.listener_frameChanged());
%

% Only act for the dataset displayed by this document
if obj.mibModel.Sets.selectedSet ~= obj.setOfDatasetsIndex; return; end

frameNumber = obj.mibModel.I{obj.mibModel.id}.slices{5}(1);

% Sync widgets directly — avoid triggering slider/edit callbacks
obj.handles.frameNumber.Value      = frameNumber;
obj.frameNumber_Callback();

end
