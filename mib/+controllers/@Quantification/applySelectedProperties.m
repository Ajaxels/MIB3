function applySelectedProperties(obj, propertyList)
% function applySelectedProperties(obj, propertyList)
% Apply the property list returned by the QuantificationProperties dialog.
%
% Called by the QuantificationProperties child controller when the user
% confirms the selection.  Sorts the list, warns if CurveLength or
% EndpointsLength requires 8-connectivity, switches Object/Intensity
% mode if needed, and updates BatchOpt.Property / MultipleProperty.
%
% Parameters:
% propertyList: cell array of selected property names,
%   e.g. @code {'Area', 'Perimeter', 'MeanIntensity'} @endcode
%
%|
% @b Examples:
% @code obj.applySelectedProperties({'Area', 'Perimeter', 'MeanIntensity'}); @endcode

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
        dlgOpt.Header = 'The connectivity parameter was changed from 4 to 8!';
        dlgOpt.HeaderLines = 1;
        utils.dlgs.inputUniversalDlg(obj.view.gui, {}, {}, 'Connectivity changed', dlgOpt);
        obj.view.handles.Connectivity.Value = '8/26 connectivity';
        obj.BatchOpt.Connectivity{1} = '8/26 connectivity';
    end
end

curList = obj.view.handles.Property.Items;
index = find(ismember(curList, propertyList{1}), 1);
if isempty(index)
    % property is in a different mode — switch Object/Intensity
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
