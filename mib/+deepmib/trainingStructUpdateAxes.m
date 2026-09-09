function trainingStructUpdateAxes(hMenu, actionData, parameter)
% TRAININGSTRUCTUPDATEAXES - Handle context-menu callbacks for ``mibDeepTrainingProgressStruct.UILossAxes``.
%
% Syntax:
%   .. code-block:: matlab
%
%      trainingStructUpdateAxes(hMenu, actionData, parameter)
%
global mibDeepTrainingProgressStruct

prompts = {'Define value for Y max:', 'Define value for Y min:'};
defAns = {mibDeepTrainingProgressStruct.UILossAxes.YLim(2), ...
    mibDeepTrainingProgressStruct.UILossAxes.YLim(1)};
dlgTitle = 'Update Y limits';
options.WindowStyle = 'normal';
answer = utils.dlgs.inputUniversalDlg(mibDeepTrainingProgressStruct.UIFigure, '', prompts, defAns, dlgTitle, options);
if isempty(answer); return; end
ymax = answer{1};
ymin = answer{2};
if isempty(ymin) || isempty(ymax) || isnan(ymin) || isnan(ymax) || ymin >= ymax; return; end

mibDeepTrainingProgressStruct.UILossAxes.YLim = [ymin, ymax];
end
