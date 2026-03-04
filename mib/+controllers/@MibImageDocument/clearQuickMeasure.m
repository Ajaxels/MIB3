function clearQuickMeasure(obj)
% function clearQuickMeasure(obj)
% Silently remove the active quick-measurement ROI and text label.
% Also restores WindowKeyPressFcn saved when the measurement was started.
% Idempotent: safe to call multiple times or from DeletingROI re-entry.
%
% Parameters:
%   none
%
% Return values:
%   none

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
