function [shiftXOut, shiftYOut, halfwidth, excludePeaks] = subtractRunningAverage(parentFigure, shiftX, shiftY, halfwidth, excludePeaks, useBatchMode)
% SUBTRACTRUNNINGAVERAGE - Smooth drift curves via running-average subtraction.
%
% Syntax:
%   .. code-block:: matlab
%
%      [sxOut, syOut] = utils.align.subtractRunningAverage(parentFigure, shiftX, shiftY)
%      [sxOut, syOut, halfwidth, excludePeaks] = ...
%          utils.align.subtractRunningAverage(parentFigure, shiftX, shiftY, halfwidth, excludePeaks)
%      [sxOut, syOut, halfwidth, excludePeaks] = ...
%          utils.align.subtractRunningAverage(parentFigure, shiftX, shiftY, halfwidth, excludePeaks, useBatchMode)
%
% Lets the user iteratively tune ``halfwidth`` / ``excludePeaks`` and preview
% the smoothed curves on a plot before accepting the result. In batch mode the
% supplied parameters are applied without prompting.
%
% Input Arguments:
%   - **parentFigure** — [handle] parent ``uifigure`` (or AppContainer) used to
%     centre dialogs.
%   - **shiftX** — [numeric vector] input X displacements.
%   - **shiftY** — [numeric vector] input Y displacements.
%   - **halfwidth** *(optional)* — [integer] starting half-width of the smoothing
%     window (default: ``25``).
%   - **excludePeaks** *(optional)* — [numeric] starting peak-exclusion threshold
%     (default: ``0`` — disabled).
%   - **useBatchMode** *(optional)* — [logical] when ``true`` apply the supplied
%     parameters and return without prompting (default: ``false``).
%
% Output Arguments:
%   - **shiftXOut** — [numeric vector] smoothed X displacements; ``[]`` if the user cancelled.
%   - **shiftYOut** — [numeric vector] smoothed Y displacements; ``[]`` if the user cancelled.
%   - **halfwidth** — [integer] final half-width used.
%   - **excludePeaks** — [numeric] final peak-exclusion threshold used.

if nargin < 6; useBatchMode = false; end
if nargin < 5; excludePeaks = 0;     end
if nargin < 4; halfwidth = 25;       end

notOk = true;
while notOk
    if ~useBatchMode
        prompts = {'Half-width of the averaging window:'; ...
                   'Exclude peaks higher than this value from the running average:'};
        defAns = {struct('Spinner', true, 'Value', halfwidth,    'Limits', [0 Inf], 'Step', 1, 'Round', true); ...
                  struct('Spinner', true, 'Value', excludePeaks, 'Limits', [0 Inf], 'Step', 1, 'Round', true)};
        dlgOpt.WindowStyle  = 'modal';
        dlgOpt.LabelPosition = 'left';
        dlgOpt.Icon         = 'puffin_question';
        answer = utils.dlgs.inputUniversalDlg(parentFigure, ...
            'Running average', prompts, defAns, 'Running average', dlgOpt);
        if isempty(answer); shiftXOut = []; shiftYOut = []; return; end
        halfwidth    = answer{1};
        excludePeaks = answer{2};

        shiftXOut = round(utils.align.runningAverageSmoothPoints(shiftX, halfwidth, excludePeaks));
        shiftYOut = round(utils.align.runningAverageSmoothPoints(shiftY, halfwidth, excludePeaks));

        figure(155);
        subplot(2,1,1);
        plot(1:length(shiftX), shiftX, '.-', 1:length(shiftXOut), shiftXOut, '.-');
        legend('Shift X', 'Smoothed X', 'Location', 'best'); grid on;
        xlabel('Frame number'); ylabel('Displacement'); title('X coordinate');
        subplot(2,1,2);
        plot(1:length(shiftY), shiftY, '.-', 1:length(shiftYOut), shiftYOut, '.-');
        legend('Shift Y', 'Smoothed Y', 'Location', 'best'); grid on;
        xlabel('Frame number'); ylabel('Displacement'); title('Y coordinate');

        questOpt.Icon = 'puffin_question';
        questOpt.WindowStyle = 'modal';
        fixDrifts = utils.dlgs.inputQuestDlg(parentFigure, ...
            'Align the stack using detected displacements?', 'Align dataset', ...
            'Apply current values', 'Change window size', 'Quit alignment', ...
            'Apply current values', questOpt);

        if isempty(fixDrifts) || strcmp(fixDrifts, 'Quit alignment')
            if ~isdeployed
                assignin('base', 'shiftX', shiftXOut);
                assignin('base', 'shiftY', shiftYOut);
                fprintf(['Shifts between images were exported to the MATLAB workspace ' ...
                    '(shiftX, shiftY).\nThese variables can be modified and saved to disk via:\n' ...
                    '  save ''myfile.mat'' shiftX shiftY;\n']);
            end
            shiftXOut = [];
            shiftYOut = [];
            return;
        end
        if strcmp(fixDrifts, 'Apply current values')
            notOk = false;
        end
    else
        shiftXOut = round(utils.align.runningAverageSmoothPoints(shiftX, halfwidth, excludePeaks));
        shiftYOut = round(utils.align.runningAverageSmoothPoints(shiftY, halfwidth, excludePeaks));
        notOk = false;
    end
end

end
