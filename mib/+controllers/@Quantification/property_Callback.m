function property_Callback(obj)
% PROPERTY_CALLBACK - Handle selection change in the Property dropdown.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.property_Callback()
%
% Side-effects:
%   - Enables ColorChannel2 only when 'Correlation' is selected
%   - Warns and switches Connectivity to 8 when EndpointsLength/CurveLength is selected with 4/6 connectivity
%   - Stores the selected index for the current mode/shape so it can be restored when the user switches shape or mode
%   - In Multiple mode, immediately re-sorts and re-renders the table and histogram using the newly chosen display property
%
% Usage:
%   Example 1::
%
%     % wired in addCallbacks:
%
%   Example 2::
%
%     h.Property.ValueChangedFcn = @(~,~) obj.property_Callback();
%

% Updates
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.Quantification.property_Callback: triggered\n');
end

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
            header = 'The connectivity parameter was changed from 4 to 8!';
            dlgOpt.HeaderLines = 1;
            utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Connectivity changed', dlgOpt);
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
            dataset = obj.mibModel.I{id};
            w1 = dataset.image.width;
            h1 = dataset.image.height;
            d1 = dataset.image.depth;
            for row = 1:size(data, 1)
                pixelId = max([1 floor(numel(obj.STATS(obj.sortingRowIndex(row)).PixelIdxList)/2)]);
                [~, ~, data(row,3)] = ind2sub([w1, h1, d1], ...
                    obj.STATS(obj.sortingRowIndex(row)).PixelIdxList(pixelId));
            end
            data(:,4) = [obj.STATS(obj.sortingRowIndex(end)).TimePnt]; % last element indexing kept from MIB2
            obj.view.handles.statTable.RowName = {obj.sortingRowIndex};
        end
        obj.view.handles.statTable.Data = data;
        obj.sortBtn_Callback();   % in-place: reorders both Data and RowName together

        dataVals = data(:,2);
        [a, b] = hist(dataVals, 256); %#ok<HIST>
        bar(obj.view.handles.histogram, b, a);
        obj.histLimits = [min(b) max(b)];
        obj.view.handles.histogram.XLim = [obj.histLimits(1), obj.histLimits(2)];
        obj.view.handles.highlight1.Value = obj.histLimits(1);
        obj.view.handles.highlight2.Value = obj.histLimits(2);
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
