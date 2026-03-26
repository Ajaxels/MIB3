function property_Callback(obj)
% function property_Callback(obj)
% Handle selection change in the Property dropdown.
%
% Side-effects:
% @li Enables ColorChannel2 only when 'Correlation' is selected
% @li Warns and switches Connectivity to 8 when EndpointsLength/CurveLength
%     is selected with 4/6 connectivity
% @li Stores the selected index for the current mode/shape so it can be
%     restored when the user switches shape or mode
% @li In Multiple mode, immediately re-sorts and re-renders the table and
%     histogram using the newly chosen display property
%
%|
% @b Examples:
% @code % wired in addCallbacks: @endcode
% @code h.Property.ValueChangedFcn = @(~,~) obj.property_Callback(); @endcode

% Updates
%

list = obj.view.handles.Property.Items;
value = obj.view.handles.Property.Value;

if strcmp(value, 'Correlation')
    obj.view.handles.ColorChannel2.Enable = 'on';
else
    obj.view.handles.ColorChannel2.Enable = 'off';
    if strcmp(value, 'EndpointsLength') || strcmp(value, 'CurveLength')
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

    if strcmp(obj.BatchOpt.DetectionType{1}, 'Object')
        valIdx = find(strcmp(list, value), 1);
        if ~isempty(valIdx)
            if strcmp(obj.BatchOpt.ObjectShape{1}, 'Shape2D')
                obj.obj2DType = valIdx;
            else
                obj.obj3DType = valIdx;
            end
        end
    else
        valIdx = find(strcmp(list, value), 1);
        if ~isempty(valIdx); obj.intType = valIdx; end
    end
end
selectedProperty = value;

% append channel suffix for intensity measurements
if ismember(selectedProperty, {'SumIntensity','StdIntensity','MeanIntensity','MaxIntensity','MinIntensity'})
    colChItems = obj.view.handles.ColorChannel1.Items;
    colChVal = obj.view.handles.ColorChannel1.Value;
    colIdx = find(strcmp(colChItems, colChVal), 1);
    if isempty(colIdx); colIdx = 1; end
    selectedProperty = sprintf('%s_Ch%d', selectedProperty, colIdx);
end

if obj.BatchOpt.Multiple
    if isfield(obj.STATS, selectedProperty)
        data = zeros(numel(obj.STATS), 4);
        if numel(data) ~= 0
            [data(:,2), obj.sortingRowIndex] = sort(cat(1, obj.STATS.(selectedProperty)), 'descend');
            data(:,1) = [obj.STATS(obj.sortingRowIndex).ObjectId];

            id = obj.mibModel.getActiveId();
            w1 = obj.mibModel.getImageProperty('width');
            h1 = obj.mibModel.getImageProperty('height');
            d1 = obj.mibModel.getImageProperty('depth');
            for row = 1:size(data, 1)
                pixelId = max([1 floor(numel(obj.STATS(obj.sortingRowIndex(row)).PixelIdxList)/2)]);
                [~, ~, data(row,3)] = ind2sub([w1, h1, d1], ...
                    obj.STATS(obj.sortingRowIndex(row)).PixelIdxList(pixelId));
            end
            data(:,4) = [obj.STATS(obj.sortingRowIndex(end)).TimePnt]; % last element indexing kept from MIB2
            obj.view.handles.statTable.RowName = {obj.sortingRowIndex};
        end
        data = obj.sortBtn_Callback(data);
        obj.view.handles.statTable.Data = data;

        dataVals = data(:,2);
        [a, b] = hist(dataVals, 256); %#ok<HIST>
        bar(obj.view.handles.histogram, b, a);
        obj.histLimits = [min(b) max(b)];
        obj.histScale_Callback();
        grid(obj.view.handles.histogram);
    else
        obj.view.handles.statTable.Data = [];
    end
end

if ~obj.BatchOpt.Multiple
    obj.BatchOpt.Property{1} = value;
end
end
