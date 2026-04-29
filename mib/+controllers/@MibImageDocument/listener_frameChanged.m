function listener_frameChanged(obj)
% LISTENER_FRAMECHANGED - Listener callback for the MibModel 'FrameChanged' event.
%
% Syntax:
%   function listener_frameChanged(obj)
%
% Synchronises the frame-number edit box and slider of this image document
% with the current time point stored in the model (slices{5}), then
% redraws the image.
%
% Called automatically when any code fires:
% notify(obj.mibModel, 'FrameChanged');
%
% The caller is responsible for updating mibModel.I{id}.slices{5} to the
% new frame value BEFORE firing the event so this listener can read it.
%
% The method guards against processing changes that belong to a different
% document in split-panel mode (selectedSet ~= setOfDatasetsIndex).
%
% Important: this method updates widgets DIRECTLY and must NOT delegate to
% frameNumber_Callback or frameNumberSlider_Callback — those callbacks
% fire 'SliceChanged' themselves, which would create an infinite loop.
%
% Input Arguments:
%   none  (called via @(~,~) obj.listener_frameChanged())
%
% Output Arguments:
%   none
%
% Usage:
%   Example 1 - wired in setupCallbacks::
%
%     % wired in setupCallbacks:
%     obj.listeners{end+1} = addlistener(obj.mibModel, 'FrameChanged', ...
%         @(~,~) obj.listener_frameChanged());
%

% Only act for the dataset displayed by this document
if obj.mibModel.Sets.selectedSet ~= obj.setOfDatasetsIndex; return; end

frameNumber = obj.mibModel.I{obj.mibModel.id}.slices{5}(1);

% Sync widgets directly — avoid triggering slider/edit callbacks
obj.handles.frameNumber.Value      = frameNumber;
obj.frameNumber_Callback();

end
