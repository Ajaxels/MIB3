function setStartingWeightsSettings(obj)
% SETSTARTINGWEIGHTSSETTINGS - update settings of the two-phase "frozen then trainable" schedule.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.setStartingWeightsSettings()
%
% The settings are stored in ``obj.StartingWeightsOpt`` and are only used by the 2D
% Instance workflow when ``BatchOpt.T_StartingWeights`` is ``'COCO, frozen then trainable'``
% (see :func:`startTrainingInstances`).
%
% Input Arguments:
%   (none)
%
% Output Arguments:
%   (none)
%

prompts = {'Smallest share of the total epochs the frozen phase must use, no switch happens before this [0.1]'; ...
    'Largest share of the total epochs the frozen phase may use, the switch happens no later than this [0.25]'; ...
    'Window used to decide the loss is flat, in epochs; the mean loss of the last window is compared with the window before it [25]'; ...
    'Relative improvement between those two windows below which the loss counts as flat [0.01, i.e. 1%]'; ...
    'Learning rate of the trainable phase; an absolute value, not a fraction of the initial rate, and it is capped at the initial rate [1e-4]'; ...
    'Abandon the run when the validation mAP stays at zero for this many evaluations in a row, i.e. nothing is being detected; 0 disables the check [8]'};

defAns = {struct('Spinner', true, 'Value', obj.StartingWeightsOpt.MinFrozenFraction, 'Limits', [0 0.9], 'Step', 0.05, 'Round', false); ...
    struct('Spinner', true, 'Value', obj.StartingWeightsOpt.MaxFrozenFraction, 'Limits', [0.05 0.95], 'Step', 0.05, 'Round', false); ...
    struct('Spinner', true, 'Value', obj.StartingWeightsOpt.PlateauWindowEpochs, 'Limits', [1 Inf], 'Step', 1, 'Round', true); ...
    struct('Spinner', true, 'Value', obj.StartingWeightsOpt.PlateauTolerance, 'Limits', [0 1], 'Step', 0.005, 'Round', false); ...
    struct('Spinner', true, 'Value', obj.StartingWeightsOpt.TrainableLearnRate, 'Limits', [0 Inf], 'Step', 0.00005, 'Round', false); ...
    struct('Spinner', true, 'Value', obj.StartingWeightsOpt.CollapseEvaluations, 'Limits', [0 Inf], 'Step', 1, 'Round', true)};

dlgOptions.WindowWidth = 640;
dlgOptions.Title = 'Frozen then trainable schedule';
dlgOptions.HeaderLines = 8;
header = sprintf(['Training runs in two phases: the COCO backbone is held fixed while the heads learn,' ...
    'then it is unfrozen at a lower learning rate so the features adapt to the data.\n\n' ...
    'The switch happens as soon as the training loss stops improving, but never before the' ...
    'minimum below and never after the maximum. The epochs the frozen phase does not use are' ...
    'handed to the trainable phase, so the total number of epochs is unchanged.\n\n' ...
    'A flat loss can also mean the network has collapsed and detects nothing, which unfreezing' ...
    'cannot repair. The last setting stops such a run instead of starting the trainable phase.']);

answer = utils.dlgs.inputUniversalDlg(obj.view.gui, header, prompts, defAns, ...
    'Starting weights settings', dlgOptions);
if isempty(answer); return; end

if answer{1} >= answer{2}
    mgsOpt.MsgBoxOnly = true;
    mgsOpt.Icon = 'puffin_warning';
    utils.dlgs.inputUniversalDlg(obj.view.gui, ...
        sprintf('The minimum share of the frozen phase (%g) must be smaller than the maximum (%g).\n\nThe settings were not changed.', ...
        answer{1}, answer{2}), {}, {}, 'Wrong configuration', mgsOpt);
    return;
end

obj.StartingWeightsOpt.MinFrozenFraction = answer{1};
obj.StartingWeightsOpt.MaxFrozenFraction = answer{2};
obj.StartingWeightsOpt.PlateauWindowEpochs = answer{3};
obj.StartingWeightsOpt.PlateauTolerance = answer{4};
obj.StartingWeightsOpt.TrainableLearnRate = answer{5};
obj.StartingWeightsOpt.CollapseEvaluations = answer{6};
end
