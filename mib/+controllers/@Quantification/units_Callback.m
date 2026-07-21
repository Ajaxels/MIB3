function units_Callback(obj)
% UNITS_CALLBACK - Handle selection change in the Units dropdown.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.units_Callback()
%
% Warns the user when switching to physical units in 3D mode with
% anisotropic voxels (x≠z or y≠z), because several 3D measurements
% (MajorAxisLength, SurfaceArea, EquivDiameter, eccentricities) are only
% geometrically valid for isotropic voxels.  The warning is shown once per
% session (obj.anisotropicVoxelsAgree flag).
%
% Usage:
%   Example 1::
%
%     % wired in addCallbacks:
%
%   Example 2::
%
%     h.Units.ValueChangedFcn = @(~,~) obj.units_Callback();
%

% Updates
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.Quantification.units_Callback: triggered\n');
end

curValue = obj.view.handles.Units.Value;

id = obj.mibModel.getActiveId();
pixSize = obj.mibModel.I{id}.image.pixSize;
isAnisotropic = (pixSize.x ~= pixSize.z || pixSize.y ~= pixSize.z);
is3D = obj.view.handles.Shape3D.Value;

if isAnisotropic && ~strcmp(curValue, 'pixels') && is3D && obj.anisotropicVoxelsAgree == 0
    dlgOpt.WindowHeight = 200;
    dlgOpt.Icon = 'puffin_warning';
    answer = utils.dlgs.inputQuestDlg(obj.view.gui, ...
        sprintf(['Please note that calculation of certain 3D properties, such as\n' ...
                 'MeridionalEccentricity, EquatorialEccentricity, MajorAxisLength,\n' ...
                 'SecondAxisLength, ThirdAxisLength, EquivDiameter, SurfaceArea\n' ...
                 'requires isotropic voxels!']), ...
        'Attention!!!', 'Confirm', 'Cancel', 'Confirm', dlgOpt);
    if strcmp(answer, 'Cancel')
        obj.view.handles.Units.Value = 'pixels';
        return;
    end
    obj.anisotropicVoxelsAgree = 1;
end
obj.BatchOpt.Units{1} = curValue;
end
