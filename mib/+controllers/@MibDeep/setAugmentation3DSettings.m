function setAugmentation3DSettings(obj)
    % function setAugmentation3DSettings(obj)
    % update settings for augmentation fo 3D images

    if ~isstruct(obj.AugOpt3D.RandScale)
        obj.AugOpt3D = utils.deepmib.oldAugSettingsToNew(obj.AugOpt3D, '3D');
    end
    obj.startController('mibDeepAugmentSettingsController', obj, '3D');
end

