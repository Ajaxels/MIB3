function listener_sliceChanged(obj)
% LISTENER_SLICECHANGED - Listener callback for the MibModel 'SliceChanged' event.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.listener_sliceChanged()
%
% Synchronises the slice-number edit box and slider of this image document
% with the current z-slice stored in the model, then redraws the image.
%
% Called automatically when:
%   .. code-block:: matlab
%
%      notify(obj.mibModel, 'SliceChanged');
%
% **Important notes:**
%   - This method guards against changes from different documents in split-panel mode (``selectedSet ~= setOfDatasetsIndex``)
%   - Updates widgets DIRECTLY; does NOT delegate to ``sliceNumber_Callback`` or ``sliceNumberSlider_Callback``
%     (which would create an infinite loop by firing ``SliceChanged`` themselves)
%
% Input Arguments:
%   (none — called via ``@(~,~) obj.listener_sliceChanged()``)
%
% Output Arguments:
%   (none)
%
% **Example** — wired in ``setupCallbacks``:
%
%   .. code-block:: matlab
%
%      obj.listeners{end+1} = addlistener(obj.mibModel, 'SliceChanged', ...
%          @(~,~) obj.listener_sliceChanged());
%

% Only act for the dataset displayed by this document
if obj.mibModel.Sets.selectedSet ~= obj.setOfDatasetsIndex; return; end

dataset     = obj.mibModel.I{obj.mibModel.id};
sliceNumber = dataset.slices{dataset.orientation}(1);

% Sync widgets directly — avoid triggering slider/edit callbacks
obj.handles.sliceNumber.Value      = sliceNumber;
obj.sliceNumber_Callback()

end
