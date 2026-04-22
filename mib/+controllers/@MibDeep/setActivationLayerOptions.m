function setActivationLayerOptions(obj)
    % function setActivationLayerOptions(obj)
    % update options for the activation layers
    switch obj.BatchOpt.T_ActivationLayer{1}
        case 'clippedReluLayer'
            prompts = {'Ceiling for input clipping, positive scalar [default=10]'};
            defAns = {struct('Spinner', true, 'Value', obj.ActivationLayerOpt.clippedReluLayer.Ceiling, 'Limits', [0 Inf], 'Step', 1, 'Round', false)};
        case 'eluLayer'
            prompts = {sprintf('Nonlinearity parameter alpha\nThe minimum value of the output of the ELU layer equals -Alpha and the slope at negative inputs approaching 0 is Alpha\nnumeric scalar [default=1]')};
            defAns = {struct('Spinner', true, 'Value', obj.ActivationLayerOpt.eluLayer.Alpha, 'Limits', [0 Inf], 'Step', 1, 'Round', false)};
            options.WindowHeight = 180;
        case 'leakyReluLayer'
            prompts = {'Scalar multiplier for negative input values, numeric scalar [default=0.01]'};
            defAns = {struct('Spinner', true, 'Value', obj.ActivationLayerOpt.leakyReluLayer.Scale, 'Limits', [0 Inf], 'Step', 0.1, 'Round', false)};
    end
    dlgTitle = 'Activation layer options';
    options.WindowStyle = 'normal';

    answer = utils.dlgs.inputUniversalDlg(obj.view.gui, '', prompts, defAns, dlgTitle, options);
    if isempty(answer); return; end

    switch obj.BatchOpt.T_ActivationLayer{1}
        case 'clippedReluLayer'
            obj.ActivationLayerOpt.clippedReluLayer.Ceiling = answer{1};
        case 'eluLayer'
            obj.ActivationLayerOpt.eluLayer.Alpha = answer{1};
        case 'leakyReluLayer'
            obj.ActivationLayerOpt.leakyReluLayer.Scale = answer{1};
    end
end

