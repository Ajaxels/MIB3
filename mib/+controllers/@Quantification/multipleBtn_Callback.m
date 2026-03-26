function multipleBtn_Callback(obj)
% function multipleBtn_Callback(obj)
% Open the property selection dialog for multi-property batch analysis.
%
% Calls the MIB2 mibMaskStatsProps dialog as a placeholder; the result is
% a cell array of selected property names.  After selection:
% @li Updates BatchOpt.MultipleProperty (semicolon-separated list)
% @li Sets Property dropdown to the first selected property
% @li Warns if CurveLength or EndpointsLength requires 8-connectivity
%
% @b Note: The mibMaskStatsProps call is a placeholder and should be
% replaced with a native MIB3 AppDesigner dialog when available.
%
%|
% @b Examples:
% @code % wired in addCallbacks: @endcode
% @code h.defineProperties.ButtonPushedFcn = @(~,~) obj.multipleBtn_Callback(); @endcode

% Updates
%

obj3d = ~strcmp(obj.view.handles.ObjectShape.SelectedObject.Tag, 'Shape2D');    % 0 = 2D mode, 1 = 3D mode

if isempty(obj.BatchOpt.MultipleProperty)
    propertyList = obj.BatchOpt.Property(1);
else
    propertyList = arrayfun(@(x) strtrim(x), split(obj.BatchOpt.MultipleProperty, ';'), 'UniformOutput', false);
    allProps = [obj.availableProperties2D, obj.availableProperties3D, obj.availablePropertiesInt];
    propertyList(~ismember(propertyList, allProps)) = [];
end

% --- Placeholder: call MIB2 mibMaskStatsProps dialog ---
% TODO: replace with a MIB3 port when available
res = mibMaskStatsProps(propertyList, obj3d);

if ~isempty(res)
    propertyList = sort(res);

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
end
