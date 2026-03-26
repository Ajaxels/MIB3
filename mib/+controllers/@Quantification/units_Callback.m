function units_Callback(obj)
% function units_Callback(obj)
% Handle selection change in the Units dropdown.
%
% Warns the user when switching to physical units in 3D mode with
% anisotropic voxels (x≠z or y≠z), because several 3D measurements
% (MajorAxisLength, SurfaceArea, EquivDiameter, eccentricities) are only
% geometrically valid for isotropic voxels.  The warning is shown once per
% session (obj.anisotropicVoxelsAgree flag).
%
%|
% @b Examples:
% @code % wired in addCallbacks: @endcode
% @code h.Units.ValueChangedFcn = @(~,~) obj.units_Callback(); @endcode

% Updates
%

curValue = obj.view.handles.Units.Value;

pixSize = obj.mibModel.getImageProperty('pixSize');
isAnisotropic = (pixSize.x ~= pixSize.z || pixSize.y ~= pixSize.z);
is3D = obj.view.handles.Shape3D.Value;

if isAnisotropic && ~strcmp(curValue, 'pixels') && is3D && obj.anisotropicVoxelsAgree == 0
    answer = utils.dlgs.inputQuestDlg(obj.view.gui, ...
        sprintf(['!!! Warning !!!\n\nPlease note that calculation of certain 3D properties, such as\n' ...
                 'MeridionalEccentricity, EquatorialEccentricity, MajorAxisLength,\n' ...
                 'SecondAxisLength, ThirdAxisLength, EquivDiameter, SurfaceArea\n' ...
                 'requires isotropic voxels!']), ...
        'Attention!!!', 'Confirm', 'Cancel', 'Confirm');
    if strcmp(answer, 'Cancel')
        obj.view.handles.Units.Value = 'pixels';
        return;
    end
    obj.anisotropicVoxelsAgree = 1;
end
obj.BatchOpt.Units{1} = curValue;
end
