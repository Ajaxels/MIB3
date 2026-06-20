classdef Stereology < handle
    % STEREOLOGY - @type The Stereology tool generates a grid overlay on the image and counts model material occurrences at grid intersection points to calculate surface-area fractions, exporting results to MATLAB or Excel.
    %
    % Available from MIB Ribbon -> Tools -> Stereology
    %
    % .. code-block:: matlab
    %
    %   obj.startController('controllers.Stereology');

    % Updates
    % ported to MIB3 AppDesigner framework

    properties
        mibModel
        % handle to the MibModel
        view
        % handle to the view / views.StereologyGUI
        listener
        % a cell array with handles to listeners
    end

    events
        CloseEvent
        % fires when window is closed; caught by MibController to purge this child
    end

    methods (Static)
        function ViewListner_Callback2(obj, ~, evnt)
            % VIEWLISTNER_CALLBACK2 - Guard: if the view was closed before listener cleanup, clean up and return.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.ViewListner_Callback2(src, evnt)
            %
            if ~isvalid(obj) || isempty(obj.view) || ~isvalid(obj.view.gui)
                for i = 1:numel(obj.listener)
                    delete(obj.listener{i});
                end
                return;
            end
            switch evnt.EventName
                case {'UpdateGuiWidgets', 'NewDataset'}
                    obj.updateWidgets();
            end
        end
    end

    methods
        function obj = Stereology(mibModel, varargin)
            % STEREOLOGY - Constructor for the Stereology controller.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj = Stereology(mibModel)
            %
            % Input Arguments:
            %   - **mibModel** — handle to MibModel
            %   - **varargin{1}** — controller handle (unused, for startController compatibility)
            %

            obj.mibModel = mibModel;
            id = obj.mibModel.id;

            obj.view = core.ChildView(obj, 'views.StereologyGUI');

            % check for the virtual stacking mode and close the controller
            if isprop(obj.mibModel.I{id}, 'Virtual') && obj.mibModel.I{id}.Virtual.virtual == 1
                dlgOpt.MsgBoxOnly = true;
                dlgOpt.Icon = 'puffin_warning';
                dlgOpt.HeaderLines = 1;
                utils.dlgs.inputUniversalDlg(obj.view.gui, '!!! Warning !!!', ...
                    {''}, ...
                    {'The stereology tool is not yet available in the virtual stacking mode!\nPlease switch to the memory-resident mode and try again'}, ...
                    'Not implemented', dlgOpt);
                obj.closeWindow();
                return;
            end

            obj.addCallbacks();

            % update font and size
            Font = obj.mibModel.preferences.System.Font;
            if obj.view.handles.infoText.FontSize ~= Font.FontSize ...
                    || ~strcmp(obj.view.handles.infoText.FontName, Font.FontName)
                utils.fontSizeUpdate(obj.view.gui, Font);
            end

            obj.view.gui = utils.moveWindowOutside(obj.view.gui, obj.mibModel.mibGUI, 'left');
            obj.updateWidgets();
            obj.view.gui.Visible = true;

            obj.listener{1} = addlistener(obj.mibModel, 'UpdateGuiWidgets', ...
                @(src,evnt) obj.ViewListner_Callback2(obj, src, evnt));
            obj.listener{2} = addlistener(obj.mibModel, 'NewDataset', ...
                @(src,evnt) obj.ViewListner_Callback2(obj, src, evnt));
        end

        function addCallbacks(obj)
            % ADDCALLBACKS - Wire all widget callbacks; called once from the constructor.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.addCallbacks()
            %

            obj.view.gui.CloseRequestFcn = @(~,~) obj.closeWindow();
            h = obj.view.handles;
            h.closeBtn.ButtonPushedFcn        = @(~,~) obj.closeWindow();
            h.generateGrid.ButtonPushedFcn    = @(~,~) obj.generateGrid_Callback();
            h.doStereologyBtn.ButtonPushedFcn = @(~,~) obj.doStereologyBtn_Callback();
            h.helpBtn.ButtonPushedFcn         = @(~,~) obj.helpBtn_Callback();
        end

        function closeWindow(obj)
            % CLOSEWINDOW - Close the Stereology window and clean up listeners.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.closeWindow()
            %

            if isvalid(obj.view.gui)
                delete(obj.view.gui);
            end
            for i = 1:numel(obj.listener)
                delete(obj.listener{i});
            end
            notify(obj, 'CloseEvent');
        end

        function updateWidgets(obj)
            % UPDATEWIDGETS - Refresh widget display with current pixel size information.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.updateWidgets()
            %

            id = obj.mibModel.id;
            pixSize = obj.mibModel.I{id}.image.pixSize;
            pixString = sprintf('Pixel size\n%.3f x %.3f x %.3f\tunits: %s', pixSize.x, pixSize.y, pixSize.z, pixSize.units);
            obj.view.handles.pixelSizeText.Text = pixString;
        end

        function helpBtn_Callback(obj)
            % HELPBTN_CALLBACK - Open the stereology documentation in the default browser.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.helpBtn_Callback()
            %

            helpFilPath = fullfile(fileparts(obj.mibModel.mibPath), 'docs', 'site', 'user-interface', 'ribbon', 'tools', 'tools-stereology.html');
            if isfile(helpFilPath)
                web(helpFilPath, '-browser');
            else
                web('http://mib.helsinki.fi/help/main3/user-interface/ribbon/tools/tools-stereology.html', '-browser');
            end

        end

        function generateGrid_Callback(obj)
            % GENERATEGRID_CALLBACK - Generate a regular grid over the image and place it in the Mask layer.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.generateGrid_Callback()
            %
            % The grid can be centered (even margins on all sides) or offset by user-specified values.
            % Optionally dilated to a specified thickness. Clipped to the active ROI when one is selected.

            id = obj.mibModel.id;
            dataset = obj.mibModel.I{id};

            if obj.mibModel.preferences.System.EnableSelection == 0
                utils.dlgs.showErrorDialog(obj.view.gui, ...
                    sprintf('!!! Error !!!\n\nSelection is disabled\nEnable it in the\nMenu->File->Preferences->Enable selection: yes'), ...
                    'Error');
                return;
            end

            getDataOptions = struct('blockModeSwitch', 0);
            [height, width, depth, ~, time] = dataset.getDatasetDimensions('image', 3, getDataOptions);

            if dataset.maskExist == 1
                button = utils.dlgs.inputQuestDlg(obj.view.gui, ...
                    sprintf('The existing mask layer will be replaced with the grid!\n\nIt can be undone using the Ctrl+Z shortcut'), ...
                    'Generate grid', 'Continue', 'Cancel', 'Cancel');
                if strcmp(button, 'Cancel'); return; end
            end

            if dataset.image.time == 1
                obj.mibModel.backup('mask', 1);
            end

            dX = obj.view.handles.stepXedit.Value;
            dY = obj.view.handles.stepYedit.Value;
            oX = obj.view.handles.offsetXedit.Value;
            oY = obj.view.handles.offsetYedit.Value;
            pixSize = dataset.image.pixSize;

            % calculate grid step in pixels
            if obj.view.handles.imageUnits.Value
                dX = round(dX / pixSize.x);
                dY = round(dY / pixSize.y);
                oX = round(oX / pixSize.x);
                oY = round(oY / pixSize.y);
            end

            if obj.view.handles.centeredGrid.Value
                % Evenly distribute grid leaving equal margins on all sides.
                % Stereology analysis will correct for boundary cells later.
                nx = floor(width  / dX);
                ny = floor(height / dY);
                offset_x = ceil((width  - nx * dX) / 2);
                if offset_x == 0; offset_x = 1; end
                offset_y = ceil((height - ny * dY) / 2);
                if offset_y == 0; offset_y = 1; end
                x_coords = offset_x : dX : width;
                y_coords = offset_y : dY : height;
            else
                oX2 = ceil(dX / 2);
                oY2 = ceil(dY / 2);
                x_coords = 1 + oX + oX2 : dX : width;
                y_coords = 1 + oY + oY2 : dY : height;
            end

            pwb = core.PoolWaitbar(time * 4, 'Generating the grid...', obj.view.gui, 'Stereology grid', true);

            for t = 1:time
                if pwb.getCancelState(); pwb.deletePoolWaitbar(); return; end

                mask = zeros([height, width, depth], 'uint8');
                mask(:, x_coords, :) = 1;
                pwb.increment();

                if pwb.getCancelState(); pwb.deletePoolWaitbar(); return; end
                mask(y_coords, :, :) = 1;
                pwb.increment();

                gridThickness = obj.view.handles.gridThickness.Value;
                if gridThickness > 0
                    se = zeros(gridThickness * 2 + 1);
                    se(:, round(gridThickness / 2)) = 1;
                    se(round(gridThickness / 2), :) = 1;
                    for sliceIndex = 1:size(mask, 3)
                        mask(:, :, sliceIndex) = imdilate(mask(:, :, sliceIndex), se);
                    end
                end

                if dataset.selectedROI > 0
                    roiMask = dataset.hROI.returnMask(dataset.selectedROI);
                    for sliceIndex = 1:size(mask, 3)
                        mask(:, :, sliceIndex) = mask(:, :, sliceIndex) & roiMask;
                    end
                end
                pwb.increment();

                obj.mibModel.setData3D(mask, 'mask', t, 3, 0, getDataOptions);
                pwb.increment();
            end

            obj.mibModel.showMask = true;
            notify(obj.mibModel, 'ShowImage');
            pwb.deletePoolWaitbar();
        end

        function doStereologyBtn_Callback(obj)
            % DOSTEREOLOGYBTN_CALLBACK - Calculate stereology results from the grid mask and model.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.doStereologyBtn_Callback()
            %
            % Reads grid intersection points from the mask layer, counts the model material
            % at each intersection, and exports occurrence counts, surface fractions, and
            % surface-area estimates to a MATLAB workspace variable or an Excel file.

            id = obj.mibModel.id;
            dataset = obj.mibModel.I{id};

            getDataOptions = struct('blockModeSwitch', 0);
            [height, width, depth, ~, time] = dataset.getDatasetDimensions('image', 3, getDataOptions);

            if dataset.maskExist == 0
                utils.dlgs.showErrorDialog(obj.view.gui, ...
                    sprintf('The mask layer with a grid is required to proceed further!\n\nUse the Generate grid button to make a new grid!'), ...
                    'Missing the mask!');
                return;
            end

            if dataset.modelExist == 1
                button = utils.dlgs.inputQuestDlg(obj.view.gui, ...
                    sprintf('The existing model layer will be replaced with the results!\n\nIt can be undone using the Ctrl+Z shortcut'), ...
                    'Do analysis', 'Continue', 'Cancel', 'Cancel');
                if strcmp(button, 'Cancel'); return; end
            else
                utils.dlgs.showErrorDialog(obj.view.gui, ...
                    sprintf('A model with labeled objects of interest has to be present to proceed further!\n\nMake a new model and segment structures of interest'), ...
                    'Missing the model!');
                return;
            end

            % Determine export target: MATLAB variable name or Excel file path
            if obj.view.handles.matlabRadio.Value
                [~, defaultName] = fileparts(dataset.image.filename);
                exportTarget = utils.dlgs.inputSingleDlg(obj.view.gui, ...
                    sprintf('A variable for the measurements structure\n(should start with a letter!):'), ...
                    sprintf('Stgy_%s', defaultName), ...
                    'Input variable to export', struct());
                if isempty(exportTarget); return; end
            else
                [filePath, defaultName] = fileparts(dataset.image.filename);
                exportTarget = fullfile(filePath, [defaultName '_stgy.xls']);
                if isempty(exportTarget)
                    exportTarget = fullfile(obj.mibModel.currentDirectory, 'stereology.xls');
                end
                filters = {'*.xls', 'Excel format (*.xls)'};
                [fn, fp] = uiputfile(filters, 'Save stereology...', exportTarget);
                if isequal(fn, 0); return; end
                exportTarget = fullfile(fp, fn);
            end

            if dataset.image.time == 1
                obj.mibModel.backup('model', 1);
            end

            pwb = core.PoolWaitbar(depth * time, 'Doing stereology...', obj.view.gui, 'Stereology analysis', true);

            pointSize = obj.view.handles.markerSize.Value;
            materialNames = dataset.labels.materialNames;
            nMat = numel(materialNames);

            if strcmp(materialNames{end}, 'Unassigned')
                unassignedId = nMat;
                Occurrence = zeros([time, depth, nMat]);
            else
                unassignedId = nMat + 1;
                materialNames{unassignedId, :} = 'Unassigned';
                Occurrence = zeros([time, depth, nMat + 1]);
            end

            % Pre-build a circular structuring element for point stamping
            [X, Y] = meshgrid(-pointSize:pointSize, -pointSize:pointSize);
            circularMask = (X.^2 + Y.^2) <= pointSize^2;
            [circMaskH, circMaskW] = size(circularMask);

            % Per-timepoint variables initialised in the slice==1 block
            xy = [];
            dXp = 0; dYp = 0; dX = 0; dY = 0;
            scalingFactors = [];

            for t = 1:time
                sliceOptions.t = [t t];
                modelOut = zeros([height, width, depth], 'uint8');

                for sliceIndex = 1:depth
                    if pwb.getCancelState(); pwb.deletePoolWaitbar(); return; end

                    currMask = cell2mat(obj.mibModel.getData2D('mask', sliceIndex, [], [], sliceOptions));
                    currMask = bwmorph(currMask, 'thin', 'Inf');
                    currMask = bwmorph(currMask, 'branchpoints', 1);

                    if sliceIndex == 1
                        % Detect grid step from intersection centroids on the first slice
                        STATS = regionprops(bwconncomp(currMask, 8), 'Area', 'Centroid');
                        xy = cat(1, STATS.Centroid);

                        dXp = diff(xy(:, 1));
                        dXp(dXp == 0) = [];
                        dXp = mode(dXp);
                        dX = dXp * dataset.image.pixSize.x;

                        dYp = diff(xy(:, 1));
                        dYp(dYp == 0) = [];
                        dYp = mode(dYp);
                        dY = dYp * dataset.image.pixSize.y;

                        if obj.view.handles.scaleToImage.Value
                            % Compute fractional overlap of each grid cell with the image boundary
                            halfX = ceil(dXp / 2);
                            halfY = ceil(dYp / 2);
                            Xc = xy(:, 1);
                            Yc = xy(:, 2);
                            left   = Xc - halfX;
                            right  = Xc + halfX;
                            top    = Yc - halfY;
                            bottom = Yc + halfY;
                            interLeft   = max(left,   0);
                            interRight  = min(right,  width);
                            interTop    = max(top,    0);
                            interBottom = min(bottom, height);
                            overlapW = max(0, interRight  - interLeft);
                            overlapH = max(0, interBottom - interTop);
                            scalingFactors = (overlapW .* overlapH) / (dXp * dYp);
                        else
                            scalingFactors = ones([size(xy, 1), 1]);
                        end
                    end

                    currModel    = cell2mat(obj.mibModel.getData2D('labels', sliceIndex, [], [], sliceOptions));
                    currModelOut = zeros(size(currModel), 'uint8');

                    for crossId = 1:size(xy, 1)
                        x = round(xy(crossId, 1));
                        y = round(xy(crossId, 2));

                        materialIndex = currModel(y, x);
                        if materialIndex == 0; materialIndex = unassignedId; end
                        Occurrence(t, sliceIndex, materialIndex) = Occurrence(t, sliceIndex, materialIndex) + scalingFactors(crossId);
                        currModelOut(y, x) = materialIndex;

                        % Stamp a filled circle of radius pointSize at the intersection
                        x1 = max(1, x - pointSize);
                        x2 = min(width,  x + pointSize);
                        y1 = max(1, y - pointSize);
                        y2 = min(height, y + pointSize);
                        mx1 = max(1, 1 + (x1 - (x - pointSize)));
                        my1 = max(1, 1 + (y1 - (y - pointSize)));
                        mx2 = min(circMaskW, mx1 + (x2 - x1));
                        my2 = min(circMaskH, my1 + (y2 - y1));
                        currModelOut(y1:y2, x1:x2) = uint8(circularMask(my1:my2, mx1:mx2)) * materialIndex;
                    end
                    modelOut(:, :, sliceIndex) = currModelOut;
                    pwb.increment();
                end
                obj.mibModel.setData3D(modelOut, 'labels', t, 3, [], sliceOptions);
            end
            dataset.labels.materialNames = materialNames;

            % Assemble result structure
            results.Occurrence = Occurrence;
            results.Materials = materialNames;

            SurfaceFraction  = zeros(size(Occurrence));
            Surface_in_units = zeros(size(Occurrence));
            for t = 1:time
                for sliceId = 1:depth
                    SurfaceFraction(t, sliceId, :)  = Occurrence(t, sliceId, :) ./ sum(Occurrence(t, sliceId, :));
                    Surface_in_units(t, sliceId, :) = Occurrence(t, sliceId, :) * dX * dY;
                end
            end
            results.SurfaceFraction  = SurfaceFraction;
            results.Surface_in_units = Surface_in_units;
            results.GridSize.pixelsX  = dXp;
            results.GridSize.pixelsY  = dYp;
            results.GridSize.unitsX   = dX;
            results.GridSize.unitsY   = dY;
            results.GridSize.unitsType = dataset.image.pixSize.units;
            results.Filename   = dataset.image.filename;
            results.ModelName  = dataset.labels.filename;
            results.ScaleToImage = logical(obj.view.handles.scaleToImage.Value);
            results.CenteredGrid = logical(obj.view.handles.centeredGrid.Value);

            % Optional: include annotation label counts
            if obj.view.handles.includeAnnotations.Value
                [labelsList, labelValues, labelPositions, ~] = dataset.annotations.getLabels();
                labelsList = strtrim(labelsList);
                uniqueLabels = unique(labelsList);
                results.Annotations.Labels = uniqueLabels;
                results.Annotations.Occurrence = zeros([time, depth, numel(uniqueLabels)]);
                for labelId = 1:numel(uniqueLabels)
                    for timeId = 1:time
                        for sliceId = 1:depth
                            matchIndices = ismember(labelsList, uniqueLabels(labelId)) ...
                                & ismember(labelPositions(:, 1), sliceId) ...
                                & ismember(labelPositions(:, 4), timeId);
                            results.Annotations.Occurrence(timeId, sliceId, labelId) = sum(labelValues(matchIndices));
                        end
                    end
                end
            end

            % Export results
            if obj.view.handles.matlabRadio.Value
                pwb.updateText('Exporting to MATLAB...');
                assignin('base', exportTarget, results);
                fprintf('MIB: export stereology measurements ("%s") to Matlab -> done!\n', exportTarget);
            else
                if isfile(exportTarget); delete(exportTarget); end
                pwb.updateText('Exporting to Excel...');
                warning('off', 'MATLAB:xlswrite:AddSheet');

                for t = 1:time
                    clear cellData;
                    cellData = {'Stereology analysis with Microscopy Image Browser'};
                    cellData(2, 1:2) = {'Filename:' sprintf('%s', results.Filename)};
                    cellData(3, 1:2) = {'Model:' sprintf('%s', results.ModelName)};
                    cellData(1, 10:12) = {'Grid size', 'dX', 'dY'};
                    cellData(2, 10:12) = {'in Pixels:' sprintf('%d', results.GridSize.pixelsX) sprintf('%d', results.GridSize.pixelsY)};
                    cellData(3, 10:13) = {'in Units:' sprintf('%f', results.GridSize.unitsX) sprintf('%f', results.GridSize.unitsY) sprintf('%s', results.GridSize.unitsType)};
                    if results.CenteredGrid
                        cellData(4, 10:11) = {'Centered grid:' 'true'};
                    else
                        cellData(4, 10:11) = {'Centered grid:' 'false'};
                    end
                    if results.ScaleToImage
                        cellData(5, 10:11) = {'Scale to image size:' 'true'};
                    else
                        cellData(5, 10:11) = {'Scale to image size:' 'false'};
                    end
                    cellData(1, 15:17) = {'Pixel size', 'dX', 'dY'};
                    cellData(2, 16:17) = {sprintf('%f', dataset.image.pixSize.x) ...
                                          sprintf('%f', dataset.image.pixSize.y)};
                    cellData(4, 1:2) = {'Time point:' sprintf('%d', t)};

                    nMat = numel(results.Materials);
                    dataRowId = 7;
                    cellData(dataRowId, 1) = {'SliceId'};
                    cellData(dataRowId, 2) = {'Occurrence'};
                    cellData(dataRowId, 2 + nMat + 2) = {'SurfaceFraction'};
                    cellData(dataRowId, 2 + nMat * 2 + 2 * 2) = {sprintf('Surface in %s^2', results.GridSize.unitsType)};
                    if obj.view.handles.includeAnnotations.Value
                        cellData(dataRowId, 2 + nMat * 3 + 3 * 2) = {'Annotation labels'};
                    end
                    cellData(dataRowId + 1, 2:nMat + 1) = results.Materials(:);
                    cellData(dataRowId + 1, 2 + nMat + 2:2 + nMat * 2 + 2 - 1) = results.Materials(:);
                    cellData(dataRowId + 1, 2 + nMat * 2 + 2 * 2:2 + nMat * 3 + 2 * 2 - 1) = results.Materials(:);

                    currDataRowId = dataRowId + 2;
                    sliceNames = dataset.image.sliceName;
                    if isempty(sliceNames) || numel(sliceNames) ~= depth
                        sliceIndices = 1:depth;
                        cellData(currDataRowId:currDataRowId + depth - 1, 1) = cellstr(num2str(sliceIndices'));
                    else
                        cellData(currDataRowId:currDataRowId + depth - 1, 1) = sliceNames;
                    end

                    cellData(currDataRowId:currDataRowId + depth - 1, 2:nMat + 1) = ...
                        num2cell(results.Occurrence(t, :, :));
                    cellData(currDataRowId:currDataRowId + depth - 1, 2 + nMat + 2:2 + nMat * 2 + 2 - 1) = ...
                        num2cell(results.SurfaceFraction(t, :, :));
                    cellData(currDataRowId:currDataRowId + depth - 1, 2 + nMat * 2 + 2 * 2:2 + nMat * 3 + 2 * 2 - 1) = ...
                        num2cell(results.Surface_in_units(t, :, :));

                    if obj.view.handles.includeAnnotations.Value
                        nLabels = numel(results.Annotations.Labels);
                        cellData(dataRowId + 1, 2 + nMat * 3 + 3 * 2:2 + nMat * 3 + nLabels + 3 * 2 - 1) = results.Annotations.Labels(:);
                        cellData(currDataRowId:currDataRowId + depth - 1, 2 + nMat * 3 + 3 * 2:2 + nMat * 3 + nLabels + 3 * 2 - 1) = ...
                            num2cell(results.Annotations.Occurrence(t, :, :));
                    end

                    cellData(depth + 11, nMat * 5) = {''};
                    sheetId = sprintf('Sheet_%d', t);
                    xlswrite2(exportTarget, cellData, sheetId, 'A1');
                end
            end

            notify(obj.mibModel, 'UpdateGuiWidgets');
            notify(obj.mibModel, 'ShowImage');
            pwb.deletePoolWaitbar();
        end
    end
end
