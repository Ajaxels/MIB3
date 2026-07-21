function radioButton_Callback(obj, hObject)
% RADIOBUTTON_CALLBACK - Handle Shape2D / Shape3D / Object / Intensity radio button changes.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.radioButton_Callback(hObject)
%
% Rebuilds the Property dropdown items appropriate for the new mode/shape
% combination and restores the last-used property index for that mode.
%
% Additionally:
%   - Switching to Shape2D resets Property to 'Area' and clears Multiple
%   - Switching to Shape3D resets Property to 'Volume', clears Multiple, and refreshes the Units warning for anisotropic voxels
%   - Switching Object/Intensity toggles ColorChannel1 visibility
%
% Input Arguments:
%   - **hObject** — handle to the radio button widget that fired the callback;
%     Tag is used to distinguish Shape2D/Shape3D from Object/Intensity
%
% Usage:
%   Example 1::
%
%     % wired in addCallbacks:
%
%   Example 2::
%
%     h.Shape2D.ValueChangedFcn = @(hObj,~) obj.radioButton_Callback(hObj);
%

% Updates
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.Quantification.radioButton_Callback: triggered\n');
end

% Update ObjectShape and DetectionType batch options
obj.BatchOpt.ObjectShape{1} = obj.view.handles.ObjectShape.SelectedObject.Tag;
obj.BatchOpt.DetectionType{1} = obj.view.handles.DetectionType.SelectedObject.Tag;

% Build property list based on mode/shape and restore stored index
if strcmp(obj.BatchOpt.DetectionType{1}, 'Intensity')
    list = obj.availablePropertiesInt;
    obj.view.handles.ColorChannel1.Enable = 'on';
    targetIdx = obj.intType;
else
    obj.view.handles.ColorChannel1.Enable = 'off';
    obj.view.handles.ColorChannel2.Enable = 'off';
    if strcmp(obj.BatchOpt.ObjectShape{1}, 'Shape2D')
        list = obj.availableProperties2D;
        targetIdx = obj.obj2DType;
    else
        if ~verLessThan('matlab', '9.3')
            list = {'Volume','ConvexVolume','EndpointsLength','EquatorialEccentricity','EquivDiameter','Extent', ...
                    'FilledArea','HolesArea','MajorAxisLength','MeridionalEccentricity','SecondAxisLength','Solidity', ...
                    'SurfaceArea','ThirdAxisLength'};
        else
            list = {'Volume','EndpointsLength','EquatorialEccentricity','FilledArea','HolesArea','MajorAxisLength', ...
                    'MeridionalEccentricity','SecondAxisLength','ThirdAxisLength'};
        end
        targetIdx = obj.obj3DType;
    end
end
obj.view.handles.Property.Items = list;

% Set property dropdown value
if targetIdx >= 1 && targetIdx <= numel(list)
    obj.view.handles.Property.Value = list{targetIdx};
else
    obj.view.handles.Property.Value = list{1};
end

% Update BatchOpt based on which button triggered the callback
if ~isempty(hObject)
    switch hObject.Tag
        case 'Shape2D'
            obj.BatchOpt.Property{1} = 'Area';
            obj.BatchOpt.MultipleProperty = 'Area';
            obj.BatchOpt.Multiple = false;
            obj.view.handles.Multiple.Value = false;
            obj.view.handles.defineProperties.Enable = 'off';
        case 'Shape3D'
            obj.BatchOpt.Property{1} = 'Volume';
            obj.BatchOpt.MultipleProperty = 'Volume';
            obj.BatchOpt.Multiple = false;
            obj.view.handles.Multiple.Value = false;
            obj.view.handles.defineProperties.Enable = 'off';
            obj.units_Callback();
        otherwise  % Object or Intensity radio buttons
            obj.BatchOpt.Property{1} = obj.view.handles.Property.Value;
    end
end
obj.property_Callback();
end
