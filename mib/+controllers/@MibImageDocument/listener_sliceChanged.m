function listener_sliceChanged(obj)
% function listener_sliceChanged(obj)
% Listener callback for the MibModel 'SliceChanged' event.
%
% Synchronises the slice-number edit box and slider of this image document
% with the current z-slice stored in the model, then redraws the image.
%
% Called automatically when any code fires:
%   notify(obj.mibModel, 'SliceChanged');
%
% The method guards against processing changes that belong to a different
% document in split-panel mode (setOfDatasetsIndex ~= mibModel.id).
%
% Important: this method updates widgets DIRECTLY and must NOT delegate to
% sliceNumber_Callback or sliceNumberSlider_Callback — those callbacks
% fire 'SliceChanged' themselves, which would create an infinite loop.
%
% Parameters:
%   none  (called via @(~,~) obj.listener_sliceChanged())
%
% Return values:
%   none
%
%|
% @b Examples:
% @code
% % wired in setupCallbacks:
% obj.listeners{end+1} = addlistener(obj.mibModel, 'SliceChanged', ...
%     @(~,~) obj.listener_sliceChanged());
% @endcode

% Only act for the dataset displayed by this document
if obj.setOfDatasetsIndex ~= obj.mibModel.id; return; end

dataset     = obj.mibModel.I{obj.mibModel.id};
sliceNumber = dataset.slices{dataset.orientation}(1);

% Sync widgets directly — avoid triggering slider/edit callbacks
obj.handles.sliceNumber.Value      = sliceNumber;
obj.sliceNumber_Callback()

end
