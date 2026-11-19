function quantification_Callback(obj, batchModeSwitch)
% QUANTIFICATION_CALLBACK - Run the shape/intensity quantification analysis and populate statTable.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.quantification_Callback()
%       obj.quantification_Callback(batchModeSwitch)
%
% The main computation engine of the Quantification controller.  Dispatches
% to 3D or 2D code paths depending on BatchOpt.ObjectShape, then iterates over
% time points and (for 2D) slices.  Computed statistics are stored in
% obj.STATS.  After the run, statTable and histogram are updated.
%
% Supported properties (3D): Volume, FilledArea, HolesArea, EndpointsLength,
% MajorAxisLength, SecondAxisLength, ThirdAxisLength, MeridionalEccentricity,
% EquatorialEccentricity, ConvexVolume, EquivDiameter, Extent, Solidity,
% SurfaceArea, Correlation, and all intensity properties.
%
% Supported properties (2D): Area, ConvexArea, CurveLength, Eccentricity,
% EquivDiameter, EndpointsLength, EulerNumber, Extent, FilledArea,
% FirstAxisLength, HolesArea, MajorAxisLength, MinorAxisLength,
% Orientation, Perimeter, SecondAxisLength, Solidity, Correlation,
% and all intensity properties.
%
% **BigData datasets** are measured at the pyramid level
% ``BatchOpt.BigData_PyramidLevel`` (``'s0'`` = full resolution), read with an
% explicit ``pyramidLevel`` so the display zoom does not matter:
%
%   - Shape3D reads the whole level at once; Shape2D walks the XY slices of the
%     level (``'2D, Slice'``: the level slice holding the shown slice,
%     ``ceil(z / scaleZ)``). Each level slice ``k`` is requested as the
%     full-resolution slice ``floor((k-1)*scaleZ)+1``, which getData maps back to
%     ``k``.
%   - Values are in the voxels of the level: ``pixels`` means level pixels, and
%     physical units use the level voxel size (``pixSize .* levelScaleFactors``).
%     Rescaling to full-resolution pixels is not exact for every shape property
%     (a perimeter, an Euler number), so it is not done.
%   - After the run ``Centroid`` and ``BoundingBox`` are mapped to full
%     resolution (``(c - 0.5)*s + 0.5``; widths ``*s``), and the slice column of
%     the table holds the first full-resolution slice of the level slice, so
%     navigation, annotations, Crop objects and the export take them as for a
%     Standard dataset. ``PixelIdxList`` stays in level-linear indices, the frame
%     recorded in ``obj.runPyramidLevel`` and used by ``highlightSelection``.
%   - Block mode is ignored: the whole level is measured.
%   - Refused (error dialog, ``StopProtocol``): a level the dataset lacks, no
%     model store, a model level of another size than the image level, Shape2D
%     outside XY, Shape3D when the level does not fit the available memory; see
%     the local ``resolveBigDataLevel``.
%
% Input Arguments:
%   - **batchModeSwitch** - *(optional)* logical; 1 = headless batch mode (no
%     GUI updates, no statTable write, auto-exports if configured);
%     default 0
%
% Usage:
%   Example 1::
%
%     obj.quantification_Callback();     // interactive run
%
%   Example 2::
%
%     obj.quantification_Callback(1);    // batch / scripted run
%

% Updates
%

tic
if nargin < 2; batchModeSwitch = 0; end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.Quantification.quantification_Callback: triggered\n');
end

id = obj.mibModel.getActiveId();
dataset = obj.mibModel.I{id};

parentFig = [];
if batchModeSwitch == 0 && ~isempty(obj.view) && isvalid(obj.view.gui)
    parentFig = obj.view.gui;
end

selectedProperty = obj.BatchOpt.Property{1};

if obj.BatchOpt.Multiple
    property = cellstr(strtrim(split(obj.BatchOpt.MultipleProperty, ';')));
    allProps = [obj.availableProperties2D, obj.availableProperties3D, obj.availablePropertiesInt];
    property(~ismember(property, allProps)) = [];

    if isempty(property)
        utils.dlgs.showErrorDialog(parentFig, ...
            sprintf(['!!! Error !!!\n\nMultiple properties selected but none are valid.\n' ...
                     'Press the Define properties button to make a selection.']), ...
            'Missing properties');
        notify(obj.mibModel, 'StopProtocol');
        return;
    end
    if batchModeSwitch == 0
        selectedProperty = obj.view.handles.Property.Value;
        obj.BatchOpt.Property{1} = selectedProperty;
    end
else
    property = cellstr(selectedProperty);
    if strcmp(obj.BatchOpt.DetectionType{1}, 'Object') && strcmp(obj.BatchOpt.ObjectShape{1}, 'Shape2D')
        if ~ismember(selectedProperty, obj.availableProperties2D)
            utils.dlgs.showErrorDialog(parentFig, ...
                sprintf('!!! Error !!!\nProperty "%s" is not available for 2D objects.', selectedProperty), ...
                'Wrong property name');
            notify(obj.mibModel, 'StopProtocol');
            return;
        end
    elseif strcmp(obj.BatchOpt.DetectionType{1}, 'Object') && strcmp(obj.BatchOpt.ObjectShape{1}, 'Shape3D')
        if ~ismember(selectedProperty, obj.availableProperties3D)
            utils.dlgs.showErrorDialog(parentFig, ...
                sprintf('!!! Error !!!\nProperty "%s" is not available for 3D objects.', selectedProperty), ...
                'Wrong property name');
            notify(obj.mibModel, 'StopProtocol');
            return;
        end
    end
end

obj.indices = [];
intProps = {'SumIntensity','StdIntensity','MeanIntensity','MaxIntensity','MinIntensity'};

if obj.BatchOpt.Multiple
    colorChannel = 1:dataset.image.colors;
else
    colorChannel = str2double(obj.BatchOpt.ColorChannel1{1}(6:end));
end
colorChannel1 = str2double(obj.BatchOpt.ColorChannel1{1}(6:end));
colorChannel2 = str2double(obj.BatchOpt.ColorChannel2{1}(6:end));

selectedMaterial = str2double(obj.BatchOpt.MaterialIndex);

% --- Validate and build waitbar title ---
if selectedMaterial ~= -1   % model / exterior
    if ~dataset.modelExist
        utils.dlgs.showErrorDialog(parentFig, ...
            sprintf('Model not detected!\n\nPlease create a model using:\nMenu->Models->New model'), ...
            'Missing model');
        notify(obj.mibModel, 'StopProtocol');
        return;
    end
    list = dataset.labels.materialNames;
    if selectedMaterial == 0
        materialName = 'Exterior';
    elseif selectedMaterial == -2
        materialName = 'Model';
        selectedMaterial = NaN;
    else
        if dataset.labels.maxMaterials < 256
            if selectedMaterial > numel(list)
                utils.dlgs.showErrorDialog(parentFig, ...
                    sprintf('Wrong material index; must be below %d', numel(list)+1), 'Wrong material index');
                return;
            end
            materialName = list{selectedMaterial};
        else
            materialName = obj.BatchOpt.MaterialIndex;
        end
    end

    if isscalar(property)
        waitbarTitle = sprintf('Calculating "%s" of %s for %s\nMaterial: "%s"\nPlease wait...', ...
            property{1}, obj.BatchOpt.ObjectShape{1}, obj.BatchOpt.DatasetType{1}, materialName);
    else
        waitbarTitle = sprintf('Calculating %s stats for %s\nPlease wait...', obj.BatchOpt.ObjectShape{1}, materialName);
    end
else    % mask
    if ~dataset.maskExist
        utils.dlgs.showErrorDialog(parentFig, ...
            sprintf(['Mask not detected!\n\nPlease create a Mask using:\n' ...
                     '1. Draw with Brush\n2. Add to Mask in Segmentation panel\n3. Press "A" to add to Mask']), ...
            'Missing mask');
        notify(obj.mibModel, 'StopProtocol');
        return;
    end
    if isscalar(property)
        waitbarTitle = sprintf('Calculating "%s" of %s for %s\nMaterial: Mask\nPlease wait...', ...
            property{1}, obj.BatchOpt.ObjectShape{1}, obj.BatchOpt.DatasetType{1});
    else
        waitbarTitle = sprintf('Calculating %s stats for Mask\nPlease wait...', obj.BatchOpt.ObjectShape{1});
    end
end

% --- BigData: the pyramid level to measure ---
isBigData = strcmp(dataset.datasetType, 'BigData');
if isBigData
    imageChannelsAtOnce = 0;    % image channels a Shape3D run holds next to the labels
    if any(ismember(property, intProps)); imageChannelsAtOnce = 1; end
    if ismember('Correlation', property); imageChannelsAtOnce = 2; end
    [pyramidLevel, levelSize, levelScale, errorText] = resolveBigDataLevel(obj, dataset, imageChannelsAtOnce);
    if ~isempty(errorText)
        utils.dlgs.showErrorDialog(parentFig, errorText, 'Quantification of BigData');
        notify(obj.mibModel, 'StopProtocol');
        return;
    end
    waitbarTitle = sprintf('%s\nBigData level: %s', waitbarTitle, obj.BatchOpt.BigData_PyramidLevel{1});
end

% --- Create progress dialog ---
wb = [];
isUiDlg = false;
if obj.BatchOpt.showWaitbar
    if batchModeSwitch == 0 && ~isempty(parentFig)
        wb = uiprogressdlg(parentFig, 'Title', 'Object shape stats', 'Message', waitbarTitle, 'Value', 0, 'Cancelable', 'on');
        isUiDlg = true;
    else
        wb = waitbar(0, waitbarTitle, 'Name', 'Object shape stats...', 'WindowStyle', 'modal');
        wb.Children.Title.Interpreter = 'none';
    end
end

getDataOptions.blockModeSwitch = 0;
[img_height, img_width, img_depth, ~, img_time] = dataset.getDatasetDimensions('image', [], getDataOptions);
if isBigData
    % every read is of the chosen level, in its voxels; x/y/z stay full-resolution coordinates
    getDataOptions.pyramidLevel = pyramidLevel;
    img_height = levelSize(1);
    img_width = levelSize(2);
    img_depth = levelSize(3);
end

t1 = dataset.slices{5}(1);
t2 = dataset.slices{5}(1);
if strcmp(obj.BatchOpt.DatasetType{1}, '4D, Dataset')
    t1 = 1;
    t2 = img_time;
end

property{end+1} = 'PixelIdxList';
property{end+1} = 'Centroid';
property{end+1} = 'TimePnt';
property{end+1} = 'BoundingBox';

obj.STATS = [];
obj.runPyramidLevel = [];

pixSize = dataset.image.pixSize;
if isBigData
    % PixelIdxList is in the voxels of the level; highlightSelection needs that frame
    obj.runPyramidLevel = struct('level', pyramidLevel, 'size', levelSize, 'scale', levelScale);
    % physical units: the voxel size of the level
    pixSize.y = pixSize.y * levelScale(1);
    pixSize.x = pixSize.x * levelScale(2);
    pixSize.z = pixSize.z * levelScale(3);
end

for t = t1:t2
    if obj.BatchOpt.showWaitbar && checkCancel(wb, isUiDlg)
        if ~isempty(wb); delete(wb); end
        notify(obj.mibModel, 'StopProtocol');
        return;
    end
    start_id = 1; % init for proper visualization of progress bar
    end_id = 2;   % init for proper visualization of progress bar
    if strcmp(obj.BatchOpt.ObjectShape{1}, 'Shape3D')
        if strcmp(obj.BatchOpt.DatasetType{1}, '2D, Slice')
            if obj.BatchOpt.showWaitbar; mibSetWb(wb, isUiDlg, 0, ''); delete(wb); end
            dlgOpt.MsgBoxOnly = true; dlgOpt.Icon = 'puffin_error';
            header = 'CANCELED! The Shown slice with 3D Mode is not implemented!';
            dlgOpt.HeaderLines = 1;
            utils.dlgs.inputUniversalDlg(parentFig, header, {}, {}, 'Error!', dlgOpt);
            notify(obj.mibModel, 'StopProtocol');
            return;
        end

        if strcmp(obj.BatchOpt.Connectivity{1}, '4/6 connectivity')
            conn = 6;
        else
            conn = 26;
        end

        % XY orientation in MIB3 is 3 (was 4 in MIB2)
        if dataset.orientation ~= 3 && dataset.blockModeSwitch == 1 && ~isBigData
            if obj.BatchOpt.showWaitbar; delete(wb); end
            dlgOpt.MsgBoxOnly = true; dlgOpt.Icon = 'puffin_warning';
            header = sprintf(['!!! Warning !!!\n\nBlock mode requires XY orientation.\n' ...
                'Please switch to XY or disable block mode.']);
            dlgOpt.HeaderLines = 3;
            utils.dlgs.inputUniversalDlg(parentFig, header, {}, {}, 'Wrong orientation', dlgOpt);
            notify(obj.mibModel, 'StopProtocol');
            return;
        end
        % BigData: the whole level is measured; the block-mode limits are full-resolution
        % screen coordinates, and the index conversion below assumes full resolution
        getDataOptions.blockModeSwitch = dataset.blockModeSwitch && ~isBigData;

        if selectedMaterial == -1
            img = cell2mat(obj.mibModel.getData3D('mask', t, 3, [], getDataOptions));
        else
            img = cell2mat(obj.mibModel.getData3D('labels', t, 3, selectedMaterial, getDataOptions));
        end

        if sum(ismember(property, 'HolesArea')) > 0
            img = imfill(img, conn, 'holes') - img;
        end

        if dataset.labels.maxMaterials < 256 || ~isnan(selectedMaterial)
            CC = bwconncomp(img, conn);
            if CC.NumObjects == 0; continue; end
        else
            CC = img;
            imgSize = size(img);
            clear img;
        end
        if obj.BatchOpt.showWaitbar; mibSetWb(wb, isUiDlg, 0.05, waitbarTitle); end

        if isnan(selectedMaterial)
            STATS = regionprops(CC, CC, {'PixelIdxList','Centroid','BoundingBox','MinIntensity'});
            emptyIdx = find(arrayfun(@(s) isempty(s.PixelIdxList), STATS));
            STATS(emptyIdx) = [];
            CC = struct('PixelIdxList', {{STATS(:).PixelIdxList}}, ...
                        'NumObjects', numel({STATS(:).PixelIdxList}), ...
                        'ImageSize', imgSize, 'Connectivity', conn);
            [STATS.ObjectId] = STATS.MinIntensity;
            STATS = rmfield(STATS, 'MinIntensity');
        else
            STATS = regionprops(CC, {'PixelIdxList','Centroid','BoundingBox'}); %#ok<*PROP>
            dummy = struct('ObjectId', num2cell(1:CC.NumObjects));
            [STATS.ObjectId] = deal(dummy.ObjectId);
        end

        % Volume / FilledArea
        prop1 = property(ismember(property, {'FilledArea'}));
        if ismember('Volume', property); prop1 = [prop1, {'Area'}]; end
        if ~isempty(prop1)
            if obj.BatchOpt.showWaitbar; mibSetWb(wb, isUiDlg, 0.06, sprintf('%s\nComputing: %s', waitbarTitle, strjoin(prop1, ', '))); end
            STATS2 = regionprops(CC, prop1);
            fn = fieldnames(STATS2);
            for i = 1:numel(fn)
                if strcmp(fn{i}, 'Area')
                    [STATS.Volume] = STATS2.(fn{i});
                else
                    [STATS.(fn{i})] = STATS2.(fn{i});
                end
            end
        end
        if obj.BatchOpt.showWaitbar; mibSetWb(wb, isUiDlg, 0.1, waitbarTitle); end

        % HolesArea
        if ~isempty(property(ismember(property, 'HolesArea')))
            if obj.BatchOpt.showWaitbar; mibSetWb(wb, isUiDlg, 0.10, sprintf('%s\nComputing: HolesArea', waitbarTitle)); end
            STATS2 = regionprops(CC, 'Area');
            [STATS.HolesArea] = STATS2.Area;
        end

        % MeridionalEccentricity / EquatorialEccentricity
        prop1 = property(ismember(property, {'MeridionalEccentricity','EquatorialEccentricity'}));
        if ~isempty(prop1)
            if obj.BatchOpt.showWaitbar; mibSetWb(wb, isUiDlg, 0.20, sprintf('%s\nComputing: %s', waitbarTitle, strjoin(prop1, ', '))); end
            STATS2 = regionprops3mib(CC, 'Eccentricity');
            if ismember('MeridionalEccentricity', property);  [STATS.MeridionalEccentricity]  = deal(STATS2.MeridionalEccentricity); end
            if ismember('EquatorialEccentricity', property); [STATS.EquatorialEccentricity] = deal(STATS2.EquatorialEccentricity); end
        end

        % MajorAxisLength
        if ~isempty(property(ismember(property, 'MajorAxisLength')))
            if obj.BatchOpt.showWaitbar; mibSetWb(wb, isUiDlg, 0.30, sprintf('%s\nComputing: MajorAxisLength', waitbarTitle)); end
            STATS2 = regionprops3mib(CC, 'MajorAxisLength');
            [STATS.MajorAxisLength] = deal(STATS2.MajorAxisLength);
        end

        % SecondAxisLength / ThirdAxisLength
        prop1 = property(ismember(property, {'SecondAxisLength','ThirdAxisLength'}));
        if ~isempty(prop1)
            if obj.BatchOpt.showWaitbar; mibSetWb(wb, isUiDlg, 0.40, sprintf('%s\nComputing: %s', waitbarTitle, strjoin(prop1, ', '))); end
            STATS2 = regionprops3mib(CC, 'AllAxes');
            if ismember('SecondAxisLength', property); [STATS.SecondAxisLength] = deal(STATS2.SecondAxisLength); end
            if ismember('ThirdAxisLength',  property); [STATS.ThirdAxisLength]  = deal(STATS2.ThirdAxisLength);  end
        end
        if obj.BatchOpt.showWaitbar && checkCancel(wb, isUiDlg)
            if ~isempty(wb); delete(wb); end
            notify(obj.mibModel, 'StopProtocol');
            return;
        end

        % EndpointsLength (3D)
        if ~isempty(property(ismember(property, 'EndpointsLength')))
            if obj.BatchOpt.showWaitbar; mibSetWb(wb, isUiDlg, 0.50, sprintf('%s\nComputing: EndpointsLength', waitbarTitle)); end
            STATS3 = regionprops(CC, 'PixelList');
            if strcmp(obj.BatchOpt.Units{1}, 'pixels')
                xPix = 1; yPix = 1; zPix = 1;
            else
                xPix = pixSize.x; yPix = pixSize.y; zPix = pixSize.z;
            end
            for objId = 1:numel(STATS3)
                minZ = STATS3(objId).PixelList(1,3);
                maxZ = STATS3(objId).PixelList(end,3);
                minPts = STATS3(objId).PixelList(STATS3(objId).PixelList(:,3)==minZ, :);
                minPts = [minPts(1,1:2); minPts(end,1:2)];
                maxPts = STATS3(objId).PixelList(STATS3(objId).PixelList(:,3)==maxZ, :);
                maxPts = [maxPts(1,1:2); maxPts(end,1:2)];
                DD = sqrt(bsxfun(@plus, sum(minPts.^2,2), sum(maxPts.^2,2)') - 2*(minPts*maxPts'));
                maxVal = max(DD(:));
                [row, col] = find(DD == maxVal, 1);
                STATS3(objId).EndpointsLength = sqrt( ...
                    ((minPts(row,1)-maxPts(col,1))*xPix)^2 + ...
                    ((minPts(row,2)-maxPts(col,2))*yPix)^2 + ...
                    ((minZ-maxZ)*zPix)^2 );
            end
            [STATS.EndpointsLength] = deal(STATS3.EndpointsLength);
        end
        if obj.BatchOpt.showWaitbar && checkCancel(wb, isUiDlg)
            if ~isempty(wb); delete(wb); end
            notify(obj.mibModel, 'StopProtocol');
            return;
        end

        % Intensity properties (3D)
        prop1 = property(ismember(property, intProps));
        if ~isempty(prop1)
            if obj.BatchOpt.showWaitbar; mibSetWb(wb, isUiDlg, 0.60, sprintf('%s\nComputing: %s', waitbarTitle, strjoin(prop1, ', '))); end
            for i = 1:numel(colorChannel)
                img = squeeze(cell2mat(obj.mibModel.getData3D('image', t, 3, colorChannel(i), getDataOptions)));
                STATS2 = regionprops(CC, img, 'PixelValues');
                vals = arrayfun(@(x) double(x.PixelValues), STATS2, 'UniformOutput', false);
                STATS2 = cell2struct(vals', {'PixelValues'});
                if ismember('MinIntensity',  property); fn = sprintf('MinIntensity_Ch%d',  colorChannel(i)); tmp = num2cell(cellfun(@min,  struct2cell(STATS2), 'UniformOutput', true)); [STATS.(fn)] = tmp{:}; end
                if ismember('MaxIntensity',  property); fn = sprintf('MaxIntensity_Ch%d',  colorChannel(i)); tmp = num2cell(cellfun(@max,  struct2cell(STATS2), 'UniformOutput', true)); [STATS.(fn)] = tmp{:}; end
                if ismember('MeanIntensity', property); fn = sprintf('MeanIntensity_Ch%d', colorChannel(i)); tmp = num2cell(cellfun(@mean, struct2cell(STATS2), 'UniformOutput', true)); [STATS.(fn)] = tmp{:}; end
                if ismember('SumIntensity',  property); fn = sprintf('SumIntensity_Ch%d',  colorChannel(i)); tmp = num2cell(cellfun(@sum,  struct2cell(STATS2), 'UniformOutput', true)); [STATS.(fn)] = tmp{:}; end
                if ismember('StdIntensity',  property); fn = sprintf('StdIntensity_Ch%d',  colorChannel(i)); tmp = num2cell(cellfun(@std2, struct2cell(STATS2), 'UniformOutput', true)); [STATS.(fn)] = tmp{:}; end
            end
        end

        if obj.BatchOpt.showWaitbar && checkCancel(wb, isUiDlg)
            if ~isempty(wb); delete(wb); end
            notify(obj.mibModel, 'StopProtocol');
            return;
        end

        % ConvexVolume, EquivDiameter, Extent, Solidity, SurfaceArea
        prop1 = property(ismember(property, {'ConvexVolume','EquivDiameter','Extent','Solidity','SurfaceArea'}));
        if ~isempty(prop1)
            if obj.BatchOpt.showWaitbar; mibSetWb(wb, isUiDlg, 0.70, sprintf('%s\nComputing: %s', waitbarTitle, strjoin(prop1, ', '))); end
            STATS2 = table2struct(regionprops3(CC, prop1));
            fn = fieldnames(STATS2);
            for i = 1:numel(fn); [STATS.(fn{i})] = STATS2.(fn{i}); end
        end
        if obj.BatchOpt.showWaitbar && checkCancel(wb, isUiDlg)
            if ~isempty(wb); delete(wb); end
            notify(obj.mibModel, 'StopProtocol');
            return;
        end

        % Correlation (3D)
        if ~isempty(property(ismember(property, 'Correlation')))
            if obj.BatchOpt.showWaitbar; mibSetWb(wb, isUiDlg, 0.80, sprintf('%s\nComputing: Correlation', waitbarTitle)); end
            img1 = squeeze(cell2mat(obj.mibModel.getData3D('image', t, 3, colorChannel1, getDataOptions)));
            img2 = squeeze(cell2mat(obj.mibModel.getData3D('image', t, 3, colorChannel2, getDataOptions)));
            clear img;
            for object = 1:numel(STATS)
                STATS(object).Correlation = corr2(img1(STATS(object).PixelIdxList), img2(STATS(object).PixelIdxList));
            end
        end
        [STATS.TimePnt] = deal(t);
        if obj.BatchOpt.showWaitbar && checkCancel(wb, isUiDlg)
            if ~isempty(wb); delete(wb); end
            notify(obj.mibModel, 'StopProtocol');
            return;
        end

        % Unit conversion (3D)
        if ~strcmp(obj.BatchOpt.Units{1}, 'pixels')
            fn = fieldnames(STATS);
            for i = 1:numel(fn)
                switch fn{i}
                    case {'Volume','FilledArea','ConvexVolume','HolesArea'}
                        tmp = num2cell([STATS.(fn{i})] * pixSize.x * pixSize.y * pixSize.z);
                        [STATS.(fn{i})] = tmp{:};
                    case {'MajorAxisLength','SecondAxisLength','ThirdAxisLength','EquivDiameter'}
                        tmp = num2cell([STATS.(fn{i})] * (pixSize.x + pixSize.y) / 2);
                        [STATS.(fn{i})] = tmp{:};
                    case 'SurfaceArea'
                        tmp = num2cell([STATS.(fn{i})] * (pixSize.x + pixSize.y) / 2 * pixSize.z);
                        [STATS.(fn{i})] = tmp{:};
                end
            end
        end

        % Recalculate PixelIdxList to full dataset (block mode)
        if getDataOptions.blockModeSwitch == 1
            [yMin, yMax, xMin, xMax, zMin, zMax] = dataset.getCoordinatesOfShownImage(3); %#ok<ASGLU> (zMax unused but returned for API completeness)
            convOpt.y = [yMin yMax]; convOpt.x = [xMin xMax]; convOpt.z = [zMin zMax];
            for ooId = 1:CC.NumObjects
                STATS(ooId).PixelIdxList = dataset.convertPixelIdxListCrop2Full(STATS(ooId).PixelIdxList, convOpt);
                STATS(ooId).Centroid(1) = STATS(ooId).Centroid(1) + xMin - 1;
                STATS(ooId).Centroid(2) = STATS(ooId).Centroid(2) + yMin - 1;
                STATS(ooId).BoundingBox(1) = STATS(ooId).BoundingBox(1) + xMin - 1;
                STATS(ooId).BoundingBox(2) = STATS(ooId).BoundingBox(2) + yMin - 1;
            end
        end

        if isempty(obj.STATS)
            obj.STATS = orderfields(STATS');
        else
            obj.STATS = [obj.STATS orderfields(STATS')];
        end
        if obj.BatchOpt.showWaitbar; mibSetWb(wb, isUiDlg, 0.95, waitbarTitle); end

    else    % ======================== 2D objects ========================
        if strcmp(obj.BatchOpt.Connectivity{1}, '4/6 connectivity')
            conn = 4;
        else
            conn = 8;
        end

        orientation = dataset.orientation;

        if strcmp(obj.BatchOpt.DatasetType{1}, '2D, Slice')
            start_id = dataset.getCurrentSliceNumber();
            if isBigData; start_id = ceil(start_id / levelScale(3)); end   % the level slice that holds the shown one
            end_id = start_id;
        elseif isBigData
            start_id = 1;
            end_id = img_depth;     % slices of the level (XY only, checked above)
        else
            start_id = 1;
            end_id = dataset.dim_yxzct(orientation);  % number of slices along the current orientation
        end

        shapeProps = {'Solidity','Perimeter','Orientation','MinorAxisLength','MajorAxisLength', ...
                      'FilledArea','Extent','EulerNumber','EquivDiameter','Eccentricity','ConvexArea','Area'};
        shapeProps3D = {'FirstAxisLength','SecondAxisLength'};
        commonProps = {'PixelIdxList','Centroid','BoundingBox'};

        getDataOptions.t = [t t];
        getDataOptions.blockModeSwitch = 0;

        for lay_id = start_id:end_id
            if obj.BatchOpt.showWaitbar && end_id > start_id
                mibSetWb(wb, isUiDlg, (lay_id-start_id)/(end_id-start_id), waitbarTitle);
            end
            if obj.BatchOpt.showWaitbar && checkCancel(wb, isUiDlg)
                if ~isempty(wb); delete(wb); end
                notify(obj.mibModel, 'StopProtocol');
                return;
            end

            % getData2D takes a full-resolution slice number; on BigData lay_id is a
            % level slice, so pass a full-resolution slice inside it (getData maps z
            % with ceil(z / scale), and floor((k-1)*s)+1 maps back to k for s >= 1)
            readSliceNo = lay_id;
            if isBigData; readSliceNo = floor((lay_id - 1) * levelScale(3)) + 1; end

            if selectedMaterial == -1
                slice = cell2mat(obj.mibModel.getData2D('mask', readSliceNo, orientation, [], getDataOptions));
            else
                slice = cell2mat(obj.mibModel.getData2D('labels', readSliceNo, orientation, selectedMaterial, getDataOptions));
            end

            if ~isempty(property(ismember(property, 'HolesArea')))
                slice = imfill(slice, conn, 'holes') - slice;
            end

            if ~isnan(selectedMaterial)
                CC = bwconncomp(slice, conn);
                if CC.NumObjects == 0; continue; end
            else
                CC = slice;
            end

            if isnan(selectedMaterial)
                STATS = regionprops(CC, CC, [commonProps, {'MinIntensity'}]);
                emptyIdx = find(arrayfun(@(s) isempty(s.PixelIdxList), STATS));
                STATS(emptyIdx) = [];
                % a slice without objects: skip it, as the material path does; its empty STATS
                % would lack the fields of the measured properties and break the concatenation
                if isempty(STATS); continue; end
                CC = struct('PixelIdxList', {{STATS(:).PixelIdxList}}, ...
                            'NumObjects', numel({STATS(:).PixelIdxList}), ...
                            'ImageSize', size(slice), 'Connectivity', conn);
                [STATS.ObjectId] = STATS.MinIntensity;
                STATS = rmfield(STATS, 'MinIntensity');
            else
                STATS = regionprops(CC, commonProps);
                dummy = struct('ObjectId', num2cell(1:CC.NumObjects));
                [STATS.ObjectId] = deal(dummy.ObjectId);
            end

            % Standard shape properties
            prop1 = property(ismember(property, shapeProps));
            if ~isempty(prop1)
                STATS2 = regionprops(CC, prop1);
                fn = fieldnames(STATS2);
                for i = 1:numel(fn); [STATS.(fn{i})] = STATS2.(fn{i}); end
            end

            % regionprops3mib shape properties (FirstAxisLength, SecondAxisLength)
            prop1 = property(ismember(property, shapeProps3D));
            if ~isempty(prop1)
                try
                    STATS2 = regionprops3mib(CC, prop1{:});
                    fn = fieldnames(STATS2);
                    for i = 1:numel(fn); [STATS.(fn{i})] = STATS2.(fn{i}); end
                catch
                end
            end

            % EndpointsLength (2D)
            if ~isempty(property(ismember(property, 'EndpointsLength')))
                STATS2 = regionprops(CC, 'PixelList');
                for objId = 1:numel(STATS2)
                    STATS(objId).EndpointsLength = sqrt( ...
                        (STATS2(objId).PixelList(1,1) - STATS2(objId).PixelList(end,1))^2 + ...
                        (STATS2(objId).PixelList(1,2) - STATS2(objId).PixelList(end,2))^2);
                end
            end

            % CurveLength (2D)
            if ~isempty(property(ismember(property, 'CurveLength')))
                STATS2 = utils.calcCurveLength(CC);
                if isstruct(STATS2)
                    [STATS.CurveLength] = deal(STATS2.CurveLengthInPixels);
                end
            end

            % HolesArea (2D)
            if ~isempty(property(ismember(property, 'HolesArea')))
                STATS2 = regionprops(CC, 'Area');
                [STATS.HolesArea] = deal(STATS2.Area);
            end

            % Intensity properties (2D)
            prop1 = property(ismember(property, intProps));
            if ~isempty(prop1)
                for i = 1:numel(colorChannel)
                    imgSlice = cell2mat(obj.mibModel.getData2D('image', readSliceNo, orientation, colorChannel(i), getDataOptions));
                    STATS2 = regionprops(CC, imgSlice, 'PixelValues');
                    vals = arrayfun(@(x) double(x.PixelValues), STATS2, 'UniformOutput', false);
                    STATS2 = cell2struct(vals', {'PixelValues'});
                    if ismember('MinIntensity',  property); fn = sprintf('MinIntensity_Ch%d',  colorChannel(i)); tmp = num2cell(cellfun(@min,  struct2cell(STATS2), 'UniformOutput', true)); [STATS.(fn)] = tmp{:}; end
                    if ismember('MaxIntensity',  property); fn = sprintf('MaxIntensity_Ch%d',  colorChannel(i)); tmp = num2cell(cellfun(@max,  struct2cell(STATS2), 'UniformOutput', true)); [STATS.(fn)] = tmp{:}; end
                    if ismember('MeanIntensity', property); fn = sprintf('MeanIntensity_Ch%d', colorChannel(i)); tmp = num2cell(cellfun(@mean, struct2cell(STATS2), 'UniformOutput', true)); [STATS.(fn)] = tmp{:}; end
                    if ismember('SumIntensity',  property); fn = sprintf('SumIntensity_Ch%d',  colorChannel(i)); tmp = num2cell(cellfun(@sum,  struct2cell(STATS2), 'UniformOutput', true)); [STATS.(fn)] = tmp{:}; end
                    if ismember('StdIntensity',  property); fn = sprintf('StdIntensity_Ch%d',  colorChannel(i)); tmp = num2cell(cellfun(@std2, struct2cell(STATS2), 'UniformOutput', true)); [STATS.(fn)] = tmp{:}; end
                end
            end

            % Correlation (2D)
            if ~isempty(property(ismember(property, 'Correlation')))
                % read each channel by its number: [] would return only the displayed channels
                img1 = cell2mat(obj.mibModel.getData2D('image', readSliceNo, orientation, colorChannel1, getDataOptions));
                img2 = cell2mat(obj.mibModel.getData2D('image', readSliceNo, orientation, colorChannel2, getDataOptions));
                for object = 1:numel(STATS)
                    STATS(object).Correlation = corr2(img1(STATS(object).PixelIdxList), img2(STATS(object).PixelIdxList));
                end
            end

            % Unit conversion (2D)
            if ~strcmp(obj.BatchOpt.Units{1}, 'pixels')
                fn = fieldnames(STATS);
                for i = 1:numel(fn)
                    switch fn{i}
                        case {'Area','ConvexArea','FilledArea','HolesArea'}
                            tmp = num2cell([STATS.(fn{i})] * pixSize.x * pixSize.y);
                            [STATS.(fn{i})] = tmp{:};
                        case {'CurveLength','EndpointsLength','MajorAxisLength','MinorAxisLength', ...
                              'EquivDiameter','Perimeter','FirstAxisLength','SecondAxisLength'}
                            tmp = num2cell([STATS.(fn{i})] * (pixSize.x + pixSize.y) / 2);
                            [STATS.(fn{i})] = tmp{:};
                    end
                end
            end

            if numel(STATS) > 0 %#ok<ISMT>
                % Lift 2D pixel indices into 3D space
                STATS = arrayfun(@(s) setfield(s, 'PixelIdxList', s.PixelIdxList + img_height*img_width*(lay_id-1)), STATS);
                % Append Z to centroid
                STATS = arrayfun(@(s) setfield(s, 'Centroid', [s.Centroid, lay_id]), STATS);
                % Expand BoundingBox to 3D
                STATS = arrayfun(@(s) setfield(s, 'BoundingBox', [s.BoundingBox(1), s.BoundingBox(2), lay_id, s.BoundingBox(3), s.BoundingBox(4), 1]), STATS);
            end
            [STATS.TimePnt] = deal(t);

            if isempty(obj.STATS)
                obj.STATS = orderfields(STATS');
            else
                obj.STATS = [obj.STATS orderfields(STATS')];
            end
        end
    end
end

% --- BigData: centroids and bounding boxes to full-resolution coordinates ---
% Measured at the level; navigation, annotations, Crop objects and the export
% take full-resolution coordinates. Level voxel k covers full-resolution voxels
% (k-1)*s+1 .. k*s, so a coordinate c (voxel centres at integers, edges at
% half-integers) maps to (c - 0.5)*s + 0.5 and a width w to w*s.
% PixelIdxList stays in the voxels of the level (obj.runPyramidLevel).
if isBigData && ~isempty(obj.STATS)
    scaleXYZ = levelScale([2 1 3]);
    centroids = (vertcat(obj.STATS.Centroid) - 0.5) .* scaleXYZ + 0.5;
    centroids = num2cell(centroids, 2);
    [obj.STATS.Centroid] = centroids{:};
    boxes = vertcat(obj.STATS.BoundingBox);
    boxes = [(boxes(:, 1:3) - 0.5) .* scaleXYZ + 0.5, boxes(:, 4:6) .* scaleXYZ];
    boxes = num2cell(boxes, 2);
    [obj.STATS.BoundingBox] = boxes{:};
end

% --- Store which dataset was quantified ---
if isnan(selectedMaterial); selectedMaterial = -2; end
obj.runId = [id, selectedMaterial];
if batchModeSwitch == 0; obj.enableStatTable(); end

if obj.BatchOpt.showWaitbar && end_id > start_id; mibSetWb(wb, isUiDlg, 0.9, 'Reformatting indices...'); end

data = zeros(numel(obj.STATS), 4);
rowNames = {};
if numel(data) ~= 0
    if ismember(selectedProperty, intProps)
        selectedProperty = sprintf('%s_Ch%d', selectedProperty, colorChannel1);
    end

    if isfield(obj.STATS, selectedProperty)
        [data(:,2), obj.sortingRowIndex] = sort(cat(1, obj.STATS.(selectedProperty)), 'descend');
    else
        [data(:,2), obj.sortingRowIndex] = sort(cat(1, obj.STATS.(property{1})), 'descend');
    end
    data(:,1) = [obj.STATS(obj.sortingRowIndex).ObjectId];

    dataWidth  = dataset.image.width;
    dataHeight = dataset.image.height;
    dataDepth  = dataset.image.depth;
    if isBigData    % PixelIdxList is in the voxels of the level
        dataWidth  = img_width;
        dataHeight = img_height;
        dataDepth  = img_depth;
    end
    for row = 1:size(data, 1)
        pixelId = max([1, floor(numel(obj.STATS(obj.sortingRowIndex(row)).PixelIdxList)/2)]);
        [~, ~, data(row,3)] = ind2sub([dataWidth, dataHeight, dataDepth], ...
            obj.STATS(obj.sortingRowIndex(row)).PixelIdxList(pixelId));
    end
    if isBigData    % the first full-resolution slice of the level slice, for navigation
        data(:,3) = floor((data(:,3) - 1) * levelScale(3)) + 1;
    end
    data(:,4) = [obj.STATS(obj.sortingRowIndex).TimePnt]';

    if ~batchModeSwitch
        rowNames = {obj.sortingRowIndex};
    else
        rowNames = cellstr(num2str(obj.sortingRowIndex));
    end
end

if obj.BatchOpt.showWaitbar && end_id > start_id; mibSetWb(wb, isUiDlg, 1, 'Done'); end

if batchModeSwitch == 0
    obj.view.handles.statTable.Data = data;
    if ~isempty(rowNames)
        obj.view.handles.statTable.RowName = rowNames;
    end
    obj.sortBtn_Callback();   % in-place: reorders both Data and RowName together
    data = obj.view.handles.statTable.Data;  % pick up the sorted data for histogram
else
    data = obj.sortBtn_Callback(data);
end

dataVals = data(:,2);
[a, b] = hist(dataVals, 256); %#ok<HIST>
obj.histLimits = [min(b), max(b)];
if batchModeSwitch == 0
    bar(obj.view.handles.histogram, b, a);
    obj.view.handles.histogram.XLim = [obj.histLimits(1), obj.histLimits(2)];
    obj.view.handles.highlight1.Value = obj.histLimits(1);
    obj.view.handles.highlight2.Value = obj.histLimits(2);
    obj.histScale_Callback();
    grid(obj.view.handles.histogram);
end

if obj.BatchOpt.showWaitbar && ~isempty(wb); delete(wb); end

if batchModeSwitch == 1
    if ~strcmp(obj.BatchOpt.ExportResultsTo{1}, 'Do not export')
        obj.exportButton_Callback(batchModeSwitch);
    end
    if ~strcmp(obj.BatchOpt.CropObjectsTo{1}, 'Do not crop') && ~isempty(obj.STATS) && isfield(obj.STATS, 'Centroid')
        cropObjIds = 1:numel(obj.STATS);
        centroids  = vertcat(obj.STATS(cropObjIds).Centroid);
        timePnts   = [obj.STATS(cropObjIds).TimePnt]';
        cropAnnot.positions  = [centroids(:,3), centroids(:,1), centroids(:,2), timePnts];
        cropAnnot.names      = repmat({obj.BatchOpt.MaterialIndex}, 1, numel(cropObjIds));
        if isfield(obj.STATS, 'BoundingBox')
            cropAnnot.boundingBoxes = vertcat(obj.STATS(cropObjIds).BoundingBox);
        end
        cropAnnot.objectIds = [obj.STATS(cropObjIds).ObjectId];
        utils.startController(obj, 'controllers.CropObjects', obj, batchModeSwitch, cropAnnot);
    end
end

% Update user score
obj.mibModel.preferences.Users.Tiers.numberOfGetStats = ...
    obj.mibModel.preferences.Users.Tiers.numberOfGetStats + 1;
eventdata = core.ToggleEventData(3);
notify(obj.mibModel, 'UpdateUserScore', eventdata);

obj.returnBatchOpt(obj.BatchOpt);
toc
end

% -------------------------------------------------------------------------
function [pyramidLevel, levelSize, levelScale, errorText] = resolveBigDataLevel(obj, dataset, imageChannelsAtOnce)
% RESOLVEBIGDATALEVEL - local helper: the pyramid level of a BigData run, or why it cannot run.
%
% Syntax:
%   function [pyramidLevel, levelSize, levelScale, errorText] = resolveBigDataLevel(obj, dataset, imageChannelsAtOnce)
%
% Parses ``obj.BatchOpt.BigData_PyramidLevel{1}`` (``'sN'`` -> level N+1) and
% refuses, with ``errorText`` for the error dialog:
%
%   - a level the dataset does not have (a protocol recorded on a dataset with
%     more levels);
%   - a dataset without a model store (the mask lives in the same store);
%   - a model level whose size differs from the image level (a label overlay
%     with its own pyramid): the reads and the coordinate mapping assume one
%     size, the check of ``controllers.BigDataOptions.checkModelOutput``;
%   - Shape2D when the view is not XY: the 2D loop walks XY slices of the level;
%   - Shape3D when the level does not fit the available physical memory. The
%     estimate counts per voxel the packed store block, the unpacked labels and
%     ``imageChannelsAtOnce`` image channels (2 for Correlation). It is a lower
%     bound: regionprops adds 8 bytes per object voxel (PixelIdxList) on top.
%     ``memory`` exists on Windows only; elsewhere the check is skipped.
%
% Output Arguments:
%   - **pyramidLevel** - [double] 1-based level (1 = full resolution)
%   - **levelSize** - [1x3 double] ``[Y X Z]`` of the level
%   - **levelScale** - [1x3 double] ``[y x z]`` full-resolution voxels per level voxel
%   - **errorText** - [char] empty when the run can go ahead

levelSize = [];
levelScale = [];
errorText = '';
pyramid = dataset.image.pyramid;
levelCount = size(pyramid.levelImageSizes, 1);
levelItem = obj.BatchOpt.BigData_PyramidLevel{1};
pyramidLevel = sscanf(levelItem, 's%d', 1) + 1;
if isempty(pyramidLevel) || pyramidLevel < 1 || pyramidLevel > levelCount
    errorText = sprintf('Unknown pyramid level "%s" (BigData_PyramidLevel); this dataset has levels s0..s%d.', ...
        levelItem, levelCount - 1);
    return;
end
levelSize = pyramid.levelImageSizes(pyramidLevel, :);
levelScale = pyramid.levelScaleFactors(pyramidLevel, :);

labels = dataset.labels;
if ~isprop(labels, 'modelLevelSizes') || isempty(labels.modelLevelSizes)
    errorText = sprintf(['This BigData dataset has no model, which also holds the mask.\n' ...
        'Create one first (Segmentation panel -> Create).']);
    return;
end
if pyramidLevel > size(labels.modelLevelSizes, 1) || ~isequal(labels.modelLevelSizes(pyramidLevel, :), levelSize)
    errorText = sprintf(['Level %s of the model does not have the size of the image level (%d x %d x %d); ' ...
        'the model has its own pyramid. Choose a level they share.'], levelItem, levelSize(2), levelSize(1), levelSize(3));
    return;
end

if strcmp(obj.BatchOpt.ObjectShape{1}, 'Shape2D') && dataset.orientation ~= 3
    errorText = sprintf(['Shape2D on a BigData dataset measures the XY slices of the level.\n' ...
        'Switch the view to XY, or use Shape3D.']);
    return;
end

if strcmp(obj.BatchOpt.ObjectShape{1}, 'Shape3D')
    bytesOf = @(className) numel(typecast(zeros(1, 1, className), 'uint8'));
    if isprop(labels, 'containerClass')
        packedClass = labels.containerClass;    % packed store, core.MibLabels63 layout
    else
        packedClass = labels.dataClass;         % instance index overlay, core.MibBigDataLabelsIndex
    end
    packedBytes = bytesOf(packedClass);
    voxelBytes = 2 * packedBytes + imageChannelsAtOnce * bytesOf(dataset.image.dataClass);
    requiredBytes = prod(levelSize) * voxelBytes;
    try
        [~, systemView] = memory();
        availableBytes = systemView.PhysicalMemory.Available;
    catch
        availableBytes = Inf;
    end
    if requiredBytes > availableBytes
        errorText = sprintf(['Shape3D reads level %s whole: %d x %d x %d voxels, at least %.1f GB, ' ...
            'while %.1f GB of memory is available.\nChoose a coarser level, or use Shape2D.'], ...
            levelItem, levelSize(2), levelSize(1), levelSize(3), requiredBytes / 1e9, availableBytes / 1e9);
    end
end
end

% -------------------------------------------------------------------------
function mibSetWb(wb, isUiDlg, val, msg)
% MIBSETWB - local helper: update progress dialog regardless of type.
%
% Syntax:
%   function mibSetWb(wb, isUiDlg, val, msg)
%
if isempty(wb); return; end

if isUiDlg
    wb.Value = min(max(val, 0), 1);
    if ~isempty(msg); wb.Message = msg; end
else
    if isempty(msg)
        waitbar(val, wb);
    else
        waitbar(val, wb, msg);
    end
end
drawnow;
end

% -------------------------------------------------------------------------
function tf = checkCancel(wb, isUiDlg)
% CHECKCANCEL - local helper: true when the user pressed Cancel on the uiprogressdlg.
%
% Syntax:
%   function tf = checkCancel(wb, isUiDlg)
%
% Returns false for the legacy waitbar path (no cancel button) so callers
% can use a uniform check regardless of the progress dialog type.
tf = false;
if isempty(wb) || ~isUiDlg; return; end
if isvalid(wb) && wb.CancelRequested; tf = true; end
end
