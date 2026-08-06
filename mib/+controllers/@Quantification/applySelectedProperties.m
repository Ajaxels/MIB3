function applySelectedProperties(obj, propertyList)
% APPLYSELECTEDPROPERTIES - Apply the property list returned by the QuantificationProperties dialog.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.applySelectedProperties(propertyList)
%
% Called by the QuantificationProperties child controller when the user
% confirms the selection.  Sorts the list, warns if CurveLength or
% EndpointsLength requires 8-connectivity, switches Object/Intensity
% mode if needed, and updates BatchOpt.Property / MultipleProperty.
%
% Input Arguments:
%   - **propertyList** - cell array of selected property names,
%     e.g. ``{'Area', 'Perimeter', 'MeanIntensity'}``
%
% Usage:
%   Example 1::
%
%     obj.applySelectedProperties({'Area', 'Perimeter', 'MeanIntensity'});
%

% Updates
%

if isempty(propertyList); return; end

propertyList = sort(propertyList);

% warn if CurveLength or EndpointsLength selected with 4-connectivity
customProps = {'CurveLength', 'EndpointsLength'};
if sum(ismember(propertyList, customProps)) > 0
    if strcmp(obj.view.handles.Connectivity.Value, '4/6 connectivity')
        dlgOpt.MsgBoxOnly = true;
        dlgOpt.Icon = 'puffin_warning';
        header = 'The connectivity parameter was changed from 4 to 8!';
        dlgOpt.HeaderLines = 1;
        utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Connectivity changed', dlgOpt);
        obj.view.handles.Connectivity.Value = '8/26 connectivity';
        obj.BatchOpt.Connectivity{1} = '8/26 connectivity';
    end
end

curList = obj.view.handles.Property.Items;
index = find(ismember(curList, propertyList{1}), 1);
if isempty(index)
    % property is in a different mode - switch Object/Intensity
    if obj.view.handles.Object.Value
        obj.view.handles.Intensity.Value = true;
    else
        obj.view.handles.Object.Value = true;
    end
    obj.radioButton_Callback(obj.view.handles.Object);
    curList = obj.view.handles.Property.Items;
    index = find(ismember(curList, propertyList{1}), 1);
end
if ~isempty(index)
    obj.view.handles.Property.Value = curList{index};
end

obj.BatchOpt.Property(1) = propertyList(1);
joined = sprintf('%s; ', propertyList{:});
obj.BatchOpt.MultipleProperty = joined(1:end-2);    % remove trailing '; '
end
