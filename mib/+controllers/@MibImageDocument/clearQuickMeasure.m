function clearQuickMeasure(obj)
% CLEARQUICKMEASURE - Silently remove the active quick-measurement ROI and text label.
%
% Syntax:
%   function clearQuickMeasure(obj)
%
% Also restores WindowKeyPressFcn saved when the measurement was started.
% Idempotent: safe to call multiple times or from DeletingROI re-entry.
%
% Input Arguments:
%   none
%
% Output Arguments:
%   none
%

if isempty(obj.quickMeasure); return; end

qm = obj.quickMeasure;
obj.quickMeasure = [];   % clear first to prevent re-entry from DeletingROI listener

% Restore the key press callback that was active before measurement started
if isfield(qm, 'savedKPF')
    obj.UIFigure.WindowKeyPressFcn = qm.savedKPF;
end

if ~isempty(qm.textH) && isvalid(qm.textH); delete(qm.textH); end
if ~isempty(qm.roi)   && isvalid(qm.roi);   delete(qm.roi);   end

end
