function [cumT, cumR, cumS, useSmoothed, cancelled] = interactiveSmoothingV2( ...
    cumT, cumR, cumS, affine_params, Depth, transformType, parentFig)
% INTERACTIVESMOOTHINGV2 - Interactive running-average smoothing dialog for v2 params.
%
% Syntax:
%   .. code-block:: matlab
%
%      [cumT, cumR, cumS, useSmoothed, cancelled] = ...
%          utils.align.interactiveSmoothingV2(cumT, cumR, cumS, affine_params, ...
%          Depth, transformType, parentFig)
%
% Plots cumulative alignment parameters and asks the user whether to apply the
% current values or fix drifts with running-average smoothing. When "Fix drifts"
% is chosen, loops through a settings dialog where the user adjusts the smoothing
% half-width and per-component flags until satisfied. Shared by the in-memory and
% BigData v2 alignment paths.
%
% See also: utils.align.plotCumulativeV2, utils.align.runningAverageSmoothPoints

useSmoothed = false;
cancelled = false;

% --- Subplot layout depends on transform type
switch transformType
    case 'translation';  noRows = 1; noCols = 1;
    case 'rigid';        noRows = 1; noCols = 2;
    case 'similarity';   noRows = 1; noCols = 3;
    case 'affine';       noRows = 2; noCols = 4;
end

% --- Plot original cumulative parameters (figure 125)
hFig125 = figure(125);
hFig125.Name = 'Cumulative alignment parameters';
utils.align.plotCumulativeV2(hFig125, noRows, noCols, cumT, cumR, cumS, affine_params, Depth, transformType);

% --- First question: apply as-is or fix drifts?
questOpt.Icon = 'puffin_question';
questOpt.WindowStyle = 'normal';
answer1 = utils.dlgs.inputQuestDlg(parentFig, ...
    'Align the stack using detected displacements?', 'Align dataset', ...
    'Apply current values', 'Fix drifts', 'Quit alignment', 'Apply current values', questOpt);
if isempty(answer1) || strcmp(answer1, 'Quit alignment')
    cancelled = true;
    if isvalid(hFig125); close(hFig125); end
    return;
end
if strcmp(answer1, 'Apply current values')
    if isvalid(hFig125); close(hFig125); end
    return;
end

% --- "Fix drifts" smoothing loop
maxHalfwidth = max(1, floor(Depth/2 - 1));
halfWidthDefault = min(25, maxHalfwidth);

prompts = {'Half-width of the averaging window'; 'Fix translation'; 'Exclude jumps higher than (0=off):'};
defAns = {struct('Spinner',true,'Value',halfWidthDefault,'Limits',[1 maxHalfwidth],'Step',1,'Round',true); ...
           true; ...
           struct('Spinner',true,'Value',0,'Limits',[0 Inf],'Step',1,'Round',false)};

if ismember(transformType, {'rigid', 'similarity', 'affine'})
    prompts = [prompts; {'Fix rotations'; 'Exclude jumps higher than (0=off):'}];
    defAns = [defAns; {true; struct('Spinner',true,'Value',0,'Limits',[0 Inf],'Step',1,'Round',false)}];
end
if ismember(transformType, {'similarity', 'affine'})
    prompts = [prompts; {'Fix scales'; 'Exclude jumps higher than (0=off):'}];
    defAns = [defAns; {true; struct('Spinner',true,'Value',0,'Limits',[0 Inf],'Step',1,'Round',false)}];
end

dlgOpt.okBtnText = 'Continue';
dlgOpt.LabelPosition = 'left';
dlgOpt.WindowHeight = 210;

hFig126 = [];
notOk = true;
while notOk
    answer = utils.dlgs.inputUniversalDlg(parentFig, '', prompts, defAns, 'Correction settings', dlgOpt);
    if isempty(answer)
        cancelled = true;
        if isvalid(hFig125); close(hFig125); end
        if ~isempty(hFig126) && isvalid(hFig126); close(hFig126); end
        return;
    end

    halfwidth = answer{1};
    fixTranslation = answer{2};
    excludeTranslationJumps = answer{3};

    fixRotation = false;
    fixScale = false;
    excludeRotationJumps = 0;
    excludeScaleJumps = 0;
    idx = 4;
    if ismember(transformType, {'rigid', 'similarity', 'affine'})
        fixRotation = answer{idx};
        excludeRotationJumps = answer{idx + 1};
        idx = idx + 2;
    end
    if ismember(transformType, {'similarity', 'affine'})
        fixScale = answer{idx};
        excludeScaleJumps = answer{idx + 1};
    end

    % Apply smoothing
    smoothT = cumT;
    if fixTranslation
        smoothT(:, 1) = utils.align.runningAverageSmoothPoints(cumT(:, 1), halfwidth, excludeTranslationJumps);
        smoothT(:, 2) = utils.align.runningAverageSmoothPoints(cumT(:, 2), halfwidth, excludeTranslationJumps);
    end
    smoothR = cumR;
    if fixRotation
        smoothR = utils.align.runningAverageSmoothPoints(cumR, halfwidth, excludeRotationJumps);
    end
    smoothS = cumS;
    if fixScale
        smoothS = utils.align.runningAverageSmoothPoints(cumS, halfwidth, excludeScaleJumps) + 1;
    end

    % Plot smoothed parameters (figure 126)
    if isempty(hFig126) || ~isvalid(hFig126)
        hFig126 = figure(126);
    end
    hFig126.Name = 'Smoothed alignment parameters';
    hFig126.Position = hFig125.Position;
    utils.align.plotCumulativeV2(hFig126, noRows, noCols, smoothT, smoothR, smoothS, affine_params, Depth, transformType);

    answer2 = utils.dlgs.inputQuestDlg(parentFig, ...
        'Align the stack using detected displacements?', 'Align dataset', ...
        'Apply values', 'Change window size', 'Quit alignment', 'Apply current values', questOpt);
    if isempty(answer2) || strcmp(answer2, 'Quit alignment')
        cancelled = true;
        if isvalid(hFig125); close(hFig125); end
        if isvalid(hFig126); close(hFig126); end
        return;
    end

    if strcmp(answer2, 'Apply values')
        cumT = smoothT;
        cumR = smoothR;
        cumS = smoothS;
        useSmoothed = true;
        notOk = false;
    else
        % "Change window size" — loop with updated defaults
        defAns{1} = struct('Spinner',true,'Value',halfwidth,'Limits',[1 maxHalfwidth],'Step',1,'Round',true);
        defAns{2} = fixTranslation;
        defAns{3} = struct('Spinner',true,'Value',excludeTranslationJumps,'Limits',[0 Inf],'Step',1,'Round',false);
        idx = 4;
        if ismember(transformType, {'rigid', 'similarity', 'affine'})
            defAns{idx}   = fixRotation;
            defAns{idx+1} = struct('Spinner',true,'Value',excludeRotationJumps,'Limits',[0 Inf],'Step',1,'Round',false);
            idx = idx + 2;
        end
        if ismember(transformType, {'similarity', 'affine'})
            defAns{idx}   = fixScale;
            defAns{idx+1} = struct('Spinner',true,'Value',excludeScaleJumps,'Limits',[0 Inf],'Step',1,'Round',false);
        end
    end
end

if isvalid(hFig125); close(hFig125); end
if ~isempty(hFig126) && isvalid(hFig126); close(hFig126); end
end
