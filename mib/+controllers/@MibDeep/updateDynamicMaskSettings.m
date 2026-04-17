function updateDynamicMaskSettings(obj)
    % function updateDynamicMaskSettings(obj)
    % update settings for calculation of dynamic masks during
    % prediction using blockedimage mode
    % the settings are stored in obj.DynamicMaskOpt

    % 'Keep above threshold' or 'Keep below threshold'
    prompts = {...
        sprintf('Masking method:\n"Keep above threshold" - threshold the image and process only the areas that are above the specified threshold\n"Keep below threshold" - threshold the image and process only the areas that are below the specified threshold'); ...
        sprintf('Intensity threshold value');...
        sprintf('Inclusion threshold (0-1):\nwhen 0, select a block with at least one pixel in the corresponding mask block is nonzero\nwhen 1, select a block only when all pixels in the mask block are nonzero')};

    defAns = {{'Keep above threshold', 'Keep below threshold', find(ismember({'Keep above threshold', 'Keep below threshold'}, obj.DynamicMaskOpt.Method))};...
        num2str(obj.DynamicMaskOpt.ThresholdValue);
        num2str(obj.DynamicMaskOpt.InclusionThreshold)};
    dlgTitle = 'Dynamic masking settings';
    options.WindowStyle = 'normal';
    options.PromptLines = [3, 1, 3];
    options.WindowWidth = 900;
    answer = utils.dlgs.inputUniversalDlg(obj.view.gui, '', prompts, defAns, dlgTitle, options);
    if isempty(answer); return; end

    if str2double(answer{3}) < 0 || str2double(answer{3}) > 1
        mgsOpt.MsgBoxOnly = true;
        mgsOpt.Header = sprintf('Inclusion threshold value should be between 0 and 1!');
        mgsOpt.Icon = 'puffin_error';
        utils.dlgs.inputUniversalDlg(obj.view.gui, {}, {}, 'Wrong inclusion threshold', mgsOpt);
        return;
    end

    obj.DynamicMaskOpt.Method = answer{1};
    obj.DynamicMaskOpt.ThresholdValue = str2double(answer{2});
    obj.DynamicMaskOpt.InclusionThreshold = str2double(answer{3});
end

