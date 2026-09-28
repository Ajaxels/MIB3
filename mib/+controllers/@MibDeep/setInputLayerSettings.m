function setInputLayerSettings(obj)
% SETINPUTLAYERSETTINGS - update init settings for the input layer of networks.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.setInputLayerSettings()
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibDeep.setInputLayerSettings: triggered\n');
end

    prompts = {...
        sprintf('Data normalization\n"zerocenter" - subtract the mean specified by Mean\n"zscore" - subtract the mean specified by Mean and divide by StandardDeviation\n"rescale-symmetric" - rescale the input to be in the range [-1, 1] using the minimum and maximum values specified by Min and Max, respectively\n"rescale-zero-one" - rescale the input to be in the range [0, 1] using the minimum and maximum values specified by Min and Max, respectively\n"none" - do not normalize the input data'); ...
        sprintf('\nThe following fields may be empty for automatic calculations during training or be an array of values per channel or a numeric scalar\n\nMean [zerocenter or z-score]'); ...
        sprintf('Standard deviation for z-score normalization [z-score]'); ...
        sprintf('Minimum value for rescaling [rescale-symmetric or rescale-zero-one]');...
        sprintf('Maximum value for rescaling [rescale-symmetric or rescale-zero-one]')};

    defAns = {{'zerocenter', 'zscore', 'rescale-symmetric', 'rescale-zero-one', 'none', find(ismember({'zerocenter', 'zscore', 'rescale-symmetric', 'rescale-zero-one', 'none'}, obj.InputLayerOpt.Normalization))};...
        num2str(reshape(obj.InputLayerOpt.Mean, [1 numel(obj.InputLayerOpt.Mean)]));
        num2str(reshape(obj.InputLayerOpt.StandardDeviation, [1 numel(obj.InputLayerOpt.StandardDeviation)]));
        num2str(reshape(obj.InputLayerOpt.Min, [1 numel(obj.InputLayerOpt.Min)]));
        num2str(reshape(obj.InputLayerOpt.Max, [1 numel(obj.InputLayerOpt.Max)]))};
    dlgTitle = 'Input layer settings';
    options.WindowStyle = 'normal';
    options.WindowWidth = 550;
    options.WindowHeight = 450;
    options.LabelPosition = 'top';
    options.HelpUrl = 'https://se.mathworks.com/help/deeplearning/ref/nnet.cnn.layer.image3dinputlayer.html'; % [optional], an url for the Help button

    [answer, selIndex] = utils.dlgs.inputUniversalDlg(obj.view.gui, '', prompts, defAns, dlgTitle, options);
    if isempty(answer); return; end

    obj.InputLayerOpt.Normalization = answer{1};
    obj.InputLayerOpt.Mean = str2num(answer{2}); %#ok<*ST2NM>
    obj.InputLayerOpt.StandardDeviation = str2num(answer{3});
    obj.InputLayerOpt.Min = str2num(answer{4});
    obj.InputLayerOpt.Max = str2num(answer{5});
end

