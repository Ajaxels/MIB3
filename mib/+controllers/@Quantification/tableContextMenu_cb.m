function tableContextMenu_cb(obj, parameter)
% TABLECONTEXTMENU_CB - Handle context menu actions on statTable rows.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.tableContextMenu_cb(parameter)
%
% Dispatches to the appropriate action based on parameter.  All actions
% operate on the rows currently selected in obj.indices.
%
% Input Arguments:
%   - **parameter** — [char] action identifier:
%
%     - ``'mean'`` — compute mean of column 2 for selected rows; copy to clipboard
%     - ``'sum'`` — compute sum; copy to clipboard
%     - ``'min'`` — compute min; copy to clipboard
%     - ``'max'`` — compute max; copy to clipboard
%     - ``'copyColumn'`` — copy selected column(s) to system clipboard
%     - ``'crop'`` — open controllers.CropObjects with centroids of selected objects
%     - ``'hist'`` — plot histogram of selected values in the histogram axes
%     - ``'newLabel'`` — create new MIB annotations at selected object centroids
%     - ``'addLabel'`` — add MIB annotations (keeps existing)
%     - ``'removeLabel'`` — remove MIB annotations at selected centroids
%
% **Example 1** — compute and copy mean value:
%
%   .. code-block:: matlab
%
%      obj.tableContextMenu_cb('mean');
%
% **Example 2** — open crop dialog:
%
%   .. code-block:: matlab
%
%      obj.tableContextMenu_cb('crop');

data = obj.view.handles.statTable.Data;
if isempty(data); return; end
if iscell(data(1)); return; end
if isempty(obj.indices); return; end

id = obj.mibModel.getActiveId();

switch parameter
    case {'mean', 'sum', 'min', 'max'}
        switch parameter
            case 'mean'; val = mean(data(obj.indices(:,1), 2)); label = 'Mean';
            case 'sum';  val = sum(data(obj.indices(:,1), 2));  label = 'Sum';
            case 'min';  val = min(data(obj.indices(:,1), 2));  label = 'Minimal';
            case 'max';  val = max(data(obj.indices(:,1), 2));  label = 'Maximal';
        end
        clipboard('copy', val);
        dlgOpt.MsgBoxOnly = true;
        dlgOpt.Icon = 'puffin_info';
        header = sprintf('%s value for %d selected objects: %f\n\n(copied to clipboard)', ...
            label, numel(obj.indices(:,1)), val);
        dlgOpt.HeaderLines = 2;
        utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, [label ' value'], dlgOpt);

    case 'crop'
        % Build annotationLabels from STATS for the selected rows
        rowIndices = unique(obj.indices(:,1));
        rowNames = obj.view.handles.statTable.RowName;
        objIds = str2num(cell2mat(rowNames(rowIndices))); %#ok<ST2NM>
        annotationLabels.positions = zeros(numel(objIds), 4);
        annotationLabels.names = cell(numel(objIds), 1);

        % Cache the repeated GUI lookup ONCE outside any loop context
        materialValue = obj.view.handles.Material.Value;
        
        centroids = vertcat(obj.STATS(objIds).Centroid);   % Nx3 matrix
        timePnts  = vertcat(obj.STATS(objIds).TimePnt);    % Nx1 vector
        % build positions in one shot, reordering columns [z, x, y, t]
        annotationLabels.positions = [centroids(:,3), centroids(:,1), centroids(:,2), timePnts];
        annotationLabels.names = repmat({materialValue}, 1, numel(objIds));
        % pass bounding boxes so generatePatches can crop full object + margin
        if isfield(obj.STATS, 'BoundingBox')
            annotationLabels.boundingBoxes = vertcat(obj.STATS(objIds).BoundingBox);
        end
        % pass actual object IDs for use in output filenames
        annotationLabels.objectIds = [obj.STATS(objIds).ObjectId];
        
        % pre-set Generate3DPatches so CropObjects opens with it checked for Shape3D
        obj.BatchOpt.Generate3DPatches = strcmp(obj.BatchOpt.ObjectShape{1}, 'Shape3D');
        utils.startController(obj, 'controllers.CropObjects', obj, false, annotationLabels);

    case 'hist'
        val = data(obj.indices(:,1), 2);
        answer = utils.dlgs.inputSingleDlg(obj.view.gui, ...
            {sprintf('Number of bins\n(%d entries selected):', numel(val))}, ...
            {'10'}, 'Histogram');
        if isempty(answer); return; end
        nbins = str2double(answer);
        if isnan(nbins)
            utils.dlgs.showErrorDialog(obj.view.gui, 'Please enter a number for bins!', 'Error');
            return;
        end
        parList = obj.view.handles.Property.Value;
        hf = figure(randi(1000));
        hist(val, nbins); %#ok<HIST>
        hHist = findobj(gca, 'Type', 'patch');
        hHist.FaceColor = [0 1 0];
        hHist.EdgeColor = 'k';
        lab(1) = xlabel(parList);
        lab(2) = ylabel('Frequency');
        [lab(:).FontSize] = deal(12);
        [lab(:).FontWeight] = deal('bold');
        [~, figName] = fileparts(obj.mibModel.I{id}.image.filename);
        hf.Name = figName;
        grid;

    case 'copyColumn'
        columnIds = unique(obj.indices(:, 2));
        d = data(:, columnIds);
        clipboard('copy', d);
        fprintf('Quantification: %d column(s) copied to clipboard\n', numel(columnIds));

    case {'newLabel', 'addLabel', 'removeLabel'}
        if strcmp(parameter, 'newLabel')
            if obj.mibModel.I{id}.annotations.getLabelsNumber() > 0
                answer = utils.dlgs.inputQuestDlg(obj.view.gui, ...
                    sprintf('Do you want to overwrite the existing annotations?'), ...
                    'Overwrite annotations', 'Overwrite', 'Cancel', 'Cancel');
                if strcmp(answer, 'Cancel'); return; end
            end
            obj.mibModel.backup('annotations', 1);
            obj.mibModel.I{id}.annotations.clearContents();
        else
            obj.mibModel.backup('annotations', 1);
        end

        if ~isfield(obj.mibModel.sessionSettings, 'StatToAnnotation')
            obj.mibModel.sessionSettings.StatToAnnotation.CustomText = '';
            obj.mibModel.sessionSettings.StatToAnnotation.AddMaterialName = false;
            obj.mibModel.sessionSettings.StatToAnnotation.AddObjId = false;
        end

        if ~strcmp(parameter, 'removeLabel')
            prompts = {'Custom text:'; 'Add material name to label'; 'Add object Id to label'};
            defAns = {obj.mibModel.sessionSettings.StatToAnnotation.CustomText; ...
                      obj.mibModel.sessionSettings.StatToAnnotation.AddMaterialName; ...
                      obj.mibModel.sessionSettings.StatToAnnotation.AddObjId};
            dlgTitle = 'Annotation label settings';
            options.Title = 'Annotation labels settings:';
            %options.WindowHeight = 220;
            options.LabelPosition = 'left';
            answer = utils.dlgs.inputUniversalDlg(obj.view.gui, '',  prompts, defAns, dlgTitle, options);
            if isempty(answer); return; end

            obj.mibModel.sessionSettings.StatToAnnotation.CustomText = answer{1};
            obj.mibModel.sessionSettings.StatToAnnotation.AddMaterialName = logical(answer{2});
            obj.mibModel.sessionSettings.StatToAnnotation.AddObjId = logical(answer{3});
        end

        property = obj.view.handles.Property.Value;
        materialName = '';
        if ~isempty(obj.mibModel.sessionSettings.StatToAnnotation.CustomText)
            materialName = [obj.mibModel.sessionSettings.StatToAnnotation.CustomText '_'];
        end
        if obj.mibModel.sessionSettings.StatToAnnotation.AddMaterialName
            materialName = [materialName obj.view.handles.Material.Value '_'];
        end

        colIds = unique(obj.indices(:,1));
        labelList = repmat({[materialName property]}, [numel(colIds), 1]);
        linearObjIndices = str2num(cell2mat(obj.view.handles.statTable.RowName(colIds))); %#ok<ST2NM>
        objIndices = data(colIds, 1);

        if obj.mibModel.sessionSettings.StatToAnnotation.AddObjId
            noDecimals = numel(num2str(max(objIndices)));
            fmt = sprintf('%%.%dd', max(2, min(noDecimals, 10)));
            labelList = arrayfun(@(x, y) sprintf(['%s_' fmt], cell2mat(x), y), labelList, objIndices, 'UniformOutput', false);
        end

        labelValues = data(colIds, 2);
        positionList = arrayfun(@(index) data(index, 3), colIds);
        positionList(:,2) = arrayfun(@(objId) obj.STATS(objId).Centroid(1), linearObjIndices);
        positionList(:,3) = arrayfun(@(objId) obj.STATS(objId).Centroid(2), linearObjIndices);
        positionList(:,4) = arrayfun(@(index) data(index, 4), colIds);

        if strcmp(parameter, 'removeLabel')
            obj.mibModel.I{id}.annotations.removeLabels(positionList);
        else
            obj.mibModel.I{id}.annotations.addLabels(labelList, positionList, labelValues);
        end
        obj.mibModel.showAnnotations = 1;
        notify(obj.mibModel, 'UpdateAnnotations');
        notify(obj.mibModel, 'ShowImage');

    otherwise
        obj.statTable_CellSelectionCallback([], parameter);
end
end
