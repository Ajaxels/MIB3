function trainingStructUpdateAxes(hMenu, actionData, parameter)
% TRAININGSTRUCTUPDATEAXES - Handle context-menu callbacks for ``mibDeepTrainingProgressStruct.UILossAxes``.
%
% Syntax:
%   .. code-block:: matlab
%
%      trainingStructUpdateAxes(hMenu, actionData, parameter)
%
global mibPath;
global mibDeepTrainingProgressStruct

prompts = {'Define value for Y max:', 'Define value for Y min:'};
defAns = {num2str(mibDeepTrainingProgressStruct.UILossAxes.YLim(2)), 
    num2str(mibDeepTrainingProgressStruct.UILossAxes.YLim(1))};
dlgTitle = 'Update Y limits';
options.WindowStyle = 'normal';
answer = mibInputMultiDlg({mibPath}, prompts, defAns, dlgTitle, options);
if isempty(answer); return; end
ymax = str2double(answer{1});
ymin = str2double(answer{2});
if isnan(ymin) || isnan(ymax); return; end

mibDeepTrainingProgressStruct.UILossAxes.YLim = [ymin, ymax];
end
