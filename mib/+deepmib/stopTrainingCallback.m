function stopTrainingCallback(hButton, varargin)
% STOPTRAININGCALLBACK - Stop the DeepMIB training process via the Stop or Emergency Brake button.
%
% Syntax:
%   .. code-block:: matlab
%
%      stopTrainingCallback(hButton)
%
% Input Arguments:
%   - **hButton** - handle to the button that triggered the callback, or a
%     ``matlab.ui.dialog.ProgressDialog`` handle when called from a progress dialog

global mibDeepStopTraining
global mibDeepTrainingProgressStruct

mibDeepStopTraining = true;

% check for presence of the progress dialog when training is prepared
% and obj.wb.CancelRequested
if isa(hButton, 'matlab.ui.dialog.ProgressDialog')   % close training progress window
    delete(hButton);
    mibDeepTrainingProgressStruct =  struct();
    return;
end

% instant training stop with generation of mibDeep file from
% the recent checkpoint
% strcmpi: the buttons created by deepmib.customTrainingProgressDisplay and
% deepmib.customTrainingProgressDisplayTrainNet are labelled 'Emergency brake' (lower-case
% 'b'), so a case-sensitive comparison here never matched and the brake never engaged
if ~isempty(hButton) && isprop(hButton, 'Text') && strcmpi(hButton.Text, 'Emergency brake')
    % 3D workflows and SegNet carry BatchNormalization layers whose final means and
    % variances are only computed when the run is finalized normally. The fields are absent
    % when the progress window was never built (plots disabled), in which case there is
    % nothing to warn about and the brake is applied directly
    hasBatchNormalization = isfield(mibDeepTrainingProgressStruct, 'Workflow') && ...
        ~isempty(mibDeepTrainingProgressStruct.Workflow) && ...
        (mibDeepTrainingProgressStruct.Workflow(1) == '3' || ...
        (isfield(mibDeepTrainingProgressStruct, 'Architecture') && strcmp(mibDeepTrainingProgressStruct.Architecture, 'SegNet')));
    if hasBatchNormalization
        answer = questdlg(sprintf('!!! Warning !!!\n\nThe current network architecture has BatchNormalization layers which requires calculation of final means and variances to finalize the network.\n\nIf you are not planning to use the network or planning to continue training in future this step may be skipped (Stop immediately), otherwise cancel and stop the run normally (Stop and finalize)'), ...
            'Emergency brake', ...
            'Stop immediately', 'Stop and finalize', 'Stop and finalize');
        if strcmp(answer, 'Stop immediately')
            mibDeepTrainingProgressStruct.emergencyBrake = true;
        end
    else
        mibDeepTrainingProgressStruct.emergencyBrake = true;
    end
end

switch hButton.Text
    case 'Stop training'
        hButton.Text = 'Stopping...';
        hButton.BackgroundColor = [1 .5 0];
    case 'Stopping...'
        hButton.Text = 'Train';
        hButton.BackgroundColor = [0.7686    0.9020    0.9882];
        mibDeepTrainingProgressStruct =  struct();
end
drawnow;

end
