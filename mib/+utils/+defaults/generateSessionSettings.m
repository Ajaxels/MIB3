function sessionSettings = generateSessionSettings()
% GENERATESESSIONSETTINGS - Generate the default MIB session settings structure.
%
% Syntax:
%   .. code-block:: matlab
%
%      sessionSettings = generateSessionSettings()
%
% Input Arguments:
%   - **mibPath** - path to MIB installation directory
%
% Output Arguments:
%   - **sessionSettings** - struct with default session settings for MIB
%
% Usage:
%
%   **Example 1** - initialise session settings at startup
%
%   .. code-block:: matlab
%
%      obj.mibModel.sessionSettings = utils.defaults.generateSessionSettings();
%

%% Define session settings structure
% define default parameters for filters
sessionSettings.prevCursorCoordinate = 0; % previous coordinate of mouse over the image axes to calculate mouse travel distance

% add CLAHE to session settings
sessionSettings.CLAHE.Mode = 'Current stack (3D)';
sessionSettings.CLAHE.NumTiles = [8 8];
sessionSettings.CLAHE.ClipLimit = 0.01;
sessionSettings.CLAHE.NBins = 256;
sessionSettings.CLAHE.Distribution = 'uniform';
sessionSettings.CLAHE.Alpha = 0.4;

% content-aware fill session settings
sessionSettings.contentAwareFill.Method      = 'inpaintCoherent';
sessionSettings.contentAwareFill.DatasetType = 'Shown slice (2D)';
sessionSettings.contentAwareFill.Mask        = 'selection';
sessionSettings.contentAwareFill.Radius      = 9;
sessionSettings.contentAwareFill.SmoothingFactor = 4;
sessionSettings.contentAwareFill.FillOrder   = 'gradient';

% NOTE: sessionSettings.stitching is deliberately absent. The Stitching dialog
% writes it on close and reads it on open (controllers.Stitching), so seeding
% defaults here would duplicate its BatchOpt defaults and the two would drift.

% NOTE: sessionSettings.stitchModelInstances and .mergeInstancesTo3D are absent
% for the same reason - the 2D-to-3D instance stitching dialog owns them
% (models.MibModel.stitchModelInstances, controllers.MibDeep.mergeInstancesTo3D),
% writing them after a run and reading them back to reopen on the last values.

% add physical pixel size in meters
pixelsPerInch = get(0, 'ScreenPixelsPerInch');
sessionSettings.metersPerPixel = 0.0254/pixelsPerInch;

% NOTE: the "do not show again" registry moved to a persistent location:
% preferences.DoNotShowDialogs (see utils.defaults.generatePreferences), so the
% choice survives across sessions.

end
