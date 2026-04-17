function setActivationLayerOptions(obj)
    % function setActivationLayerOptions(obj)
    % update options for the activation layers
    switch obj.BatchOpt.T_ActivationLayer{1}
        case 'clippedReluLayer'
            prompts = {'Ceiling for input clipping, positive scalar [default=10]'};
            defAns = {num2str(obj.ActivationLayerOpt.clippedReluLayer.Ceiling)};
            options.PromptLines = 2;
        case 'eluLayer'
            prompts = {sprintf('Nonlinearity parameter alpha\nThe minimum value of the output of the ELU layer equals -Alpha and the slope at negative inputs approaching 0 is Alpha\nnumeric scalar [default=1]')};
            defAns = {num2str(obj.ActivationLayerOpt.eluLayer.Alpha)};
            options.PromptLines = 6;
        case 'leakyReluLayer'
            prompts = {'Scalar multiplier for negative input values, numeric scalar [default=0.01]'};
            defAns = {num2str(obj.ActivationLayerOpt.leakyReluLayer.Scale)};
            options.PromptLines = 2;
    end
    dlgTitle = 'Activation layer options';
    options.WindowStyle = 'normal';
    %options.WindowWidth = 1;    % [optional] make window x1.2 times wider

    [answer, selIndex] = utils.dlgs.inputUniversalDlg(obj.view.gui, '', prompts, defAns, dlgTitle, options);
    if isempty(answer); return; end

    switch obj.BatchOpt.T_ActivationLayer{1}
        case 'clippedReluLayer'
            obj.ActivationLayerOpt.clippedReluLayer.Ceiling = str2double(answer{1});
        case 'eluLayer'
            obj.ActivationLayerOpt.eluLayer.Alpha = str2double(answer{1});
        case 'leakyReluLayer'
            obj.ActivationLayerOpt.leakyReluLayer.Scale = str2double(answer{1});
    end
end

