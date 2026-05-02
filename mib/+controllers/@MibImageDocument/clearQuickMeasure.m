function clearQuickMeasure(obj)
% CLEARQUICKMEASURE - Silently remove the active quick-measurement ROI and text label.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.clearQuickMeasure()
%
% Also restores ``WindowKeyPressFcn`` saved when the measurement was started.
% Idempotent: safe to call multiple times or from ``DeletingROI`` re-entry.
%
% Input Arguments:
%   (none)
%
% Output Arguments:
%   (none)

if isempty(obj.quickMeasure); return; end

qm = obj.quickMeasure;
obj.quickMeasure = [];   % clear first to prevent re-entry from DeletingROI listener

% Restore the key press callback that was active before measurement started
if isfield(qm, 'savedKPF')
    obj.UIFigure.WindowKeyPressFcn = qm.savedKPF;
end

% Re-enable segmentation that was suppressed during measurement
if isfield(qm, 'mibController') && ~isempty(qm.mibController) && isvalid(qm.mibController)
    qm.mibController.mibModel.disableSegmentation = false;
end

if ~isempty(qm.textH) && isvalid(qm.textH); delete(qm.textH); end
if ~isempty(qm.roi)   && isvalid(qm.roi);   delete(qm.roi);   end

end
