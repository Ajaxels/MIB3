function [status, augNumber] = setAugFuncHandles(obj, mode, augOptions)
    % function [status, augNumber] = setAugFuncHandles(obj, mode, augOptions)
    % define list of 2D/3D augmentation functions
    %
    % Parameters:
    % mode: string defining '2D' or '3D' augmentations
    % augOptions: a custom temporary structure with augmentation
    %    options to be used instead of obj.AugOpt2D and obj.AugOpt3D.
    %    It is used by mibDeepAugmentSettingsController to preview
    %    selected augmentations
    %
    % Return values:
    % status: a logical success switch (1-success, 0- fail)
    % augNumber: number of selected augmentations

    status = 0;
    augNumber = 0;

    if nargin < 3
        if strcmp(mode, '2D')
            % an old legacy setting for augmentations that may
            % sneak into the current set.
            if isfield(obj.AugOpt2D, 'ImageNoise')
                obj.AugOpt2D = rmfield(obj.AugOpt2D, 'ImageNoise');
            end
            augOptions = obj.AugOpt2D;
        else    % '2.5D Semantic' and '3D Semantic'
            augOptions = obj.AugOpt3D;
        end
    end

    if strcmp(mode, '2D')
        switch2D = true;  % 2D mode switch
        AugFuncNamesField = 'Aug2DFuncNames';
        AugFuncProbabilityField = 'Aug2DFuncProbability';
    else    % '2.5D Semantic' and '3D Semantic'
        switch2D = false; % 3D mode
        AugFuncNamesField = 'Aug3DFuncNames';
        AugFuncProbabilityField = 'Aug3DFuncProbability';
    end

    obj.(AugFuncNamesField) = [];
    obj.(AugFuncProbabilityField) = [];  % probability of each augmentation to be triggered

    augmentationNames = fieldnames(augOptions);
    for augId=1:numel(augmentationNames)
        switch augmentationNames{augId}
            case {'Fraction', 'FillValue'}
                continue;
            otherwise
                if augOptions.(augmentationNames{augId}).Enable
                    obj.(AugFuncNamesField) = [obj.(AugFuncNamesField), augmentationNames(augId)];
                    obj.(AugFuncProbabilityField) = [obj.(AugFuncProbabilityField), augOptions.(augmentationNames{augId}).Probability];
                end
        end
    end

    if isempty(obj.(AugFuncNamesField))
        mgsOpt.MsgBoxOnly = true;
        header = sprintf('Augmentation filters were not selected or their probabilities are zero!\nPlease use set 2D augmentation settings dialog (Train tab->Augmentation->2D) to set them up');
        utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Wrong augmentations', mgsOpt);
        return;
    end
    augNumber = numel(obj.(AugFuncNamesField));
    status = 1;
end

