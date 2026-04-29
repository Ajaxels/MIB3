function setSegmentationLayerOptions(obj)
% SETSEGMENTATIONLAYEROPTIONS - update options for the activation layers.
%
% Syntax:
%   function setSegmentationLayerOptions(obj)
%
    switch obj.BatchOpt.T_SegmentationLayer{1}
        case 'focalLossLayer'
            prompts = {sprintf('Alpha, balancing parameter of the focal loss function\nThe Alpha value scales the loss function linearly, when decreasing Alpha, increase Gamma\npositive real number, [default=0.25]'); ...
                sprintf('Gamma, focusing parameter of the focal loss function\nIncreasing the value of Gamma increases the sensitivity of the network to misclassified observations\npositive real number [default=2]')};
            defAns = {num2str(obj.SegmentationLayerOpt.focalLossLayer.Alpha);...
                num2str(obj.SegmentationLayerOpt.focalLossLayer.Gamma)};
            options.WindowHeight = 250;
        case 'dicePixelCustomClassificationLayer'
            prompts = {sprintf('Exclude the Exterior (default: false)')};
            defAns = {obj.SegmentationLayerOpt.dicePixelCustom.ExcludeExerior};
            options.HeaderLines = 4;
            options.Header = sprintf('EXPERIMENTAL!\nExclude the Exterior (background) class\nfrom calculation of the loss function\n(disabled when 0-pixels used as mask)');
            options.LabelPosition = 'left';
            options.WindowHeight = 180;
    end
    dlgTitle = 'Segmentation layer options';
    options.WindowStyle = 'normal';
    options.WindowWidth = 540;

    [answer, selIndex] = utils.dlgs.inputUniversalDlg(obj.view.gui, '', prompts, defAns, dlgTitle, options);
    if isempty(answer); return; end

    switch obj.BatchOpt.T_SegmentationLayer{1}
        case 'focalLossLayer'
            obj.SegmentationLayerOpt.focalLossLayer.Alpha = str2double(answer{1});
            obj.SegmentationLayerOpt.focalLossLayer.Gamma = str2double(answer{2});
        case 'dicePixelCustomClassificationLayer'
            obj.SegmentationLayerOpt.dicePixelCustom.ExcludeExerior = logical(answer{1});
    end
end

