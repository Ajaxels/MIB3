function setAugmentationSettings(obj, mode)
% SETAUGMENTATIONSETTINGS - update settings for augmentation for 2D or 3D networks.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.setAugmentationSettings(mode)
%
    
    if nargin < 2; mode = '2D'; end

    switch mode
        case '2D'
            if ~isstruct(obj.AugOpt2D.RandScale)
                obj.AugOpt2D = deepmib.oldAugSettingsToNew(obj.AugOpt2D, '2D');
            end
            utils.startController(obj, 'controllers.MibDeepAugmentSettings', obj, '2D');
        case '3D'
            if ~isstruct(obj.AugOpt3D.RandScale)
                obj.AugOpt3D = deepmib.oldAugSettingsToNew(obj.AugOpt3D, '3D');
            end
            utils.startController(obj, 'controllers.MibDeepAugmentSettings', obj, '3D');

    end
end


