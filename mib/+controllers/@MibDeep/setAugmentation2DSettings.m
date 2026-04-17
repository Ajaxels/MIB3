function setAugmentation2DSettings(obj)
    % function setAugmentation2DSettings(obj)
    % update settings for augmentation fo 2D images
    if ~isstruct(obj.AugOpt2D.RandScale)
        obj.AugOpt2D = utils.deepmib.oldAugSettingsToNew(obj.AugOpt2D, '2D');
    end
    obj.startController('mibDeepAugmentSettingsController', obj, '2D');
end

