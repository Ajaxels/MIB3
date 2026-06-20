classdef MCcalc < handle
    % MCCALC - Plugin for detection of contacts between organelles and calculation of distance distributions.
    %
    % @code
    % obj.startController('MCcalc');
    % @endcode

    properties
        mibModel
        % handles to the model
        view
        % handle to the view
        listener
        % a cell array with handles to listeners
        matlabExportVariable
        % name of variable for export results to Matlab
    end

    events
        CloseEvent
        % event firing when window is closed
    end

    methods (Static)
        function ViewListner_Callback2(obj, ~, evnt)
            if ~isvalid(obj) || isempty(obj.view) || ~isvalid(obj.view.gui)
                for i = 1:numel(obj.listener); delete(obj.listener{i}); end
                return;
            end
            switch evnt.EventName
                case {'UpdateGuiWidgets'}
                    obj.updateWidgets();
            end
        end
    end

    methods
        function obj = MCcalc(mibModel)
            obj.mibModel = mibModel;
            id = obj.mibModel.getActiveId();

            % check for the virtual stacking mode and close the controller
            if isprop(obj.mibModel.I{id}, 'Virtual') && obj.mibModel.I{id}.Virtual.virtual == 1
                dlgOpt.MsgBoxOnly = true;
                dlgOpt.Icon = 'puffin_warning';
                utils.dlgs.inputUniversalDlg(obj.mibModel.mibGUI, '', ...
                    {''}, {'This plugin is not compatible with the virtual stacking mode!\nPlease switch to the memory-resident mode and try again'}, ...
                    'Not implemented', dlgOpt);
                notify(obj, 'CloseEvent');
                return;
            end

            obj.matlabExportVariable = 'MCcalc';

            obj.view = core.ChildView(obj, 'MCcalcGUI');
            obj.addCallbacks();

            % window icon
            pluginDir = fileparts(mfilename('fullpath'));
            localIcon = fullfile(pluginDir, 'icon_16px.png');
            fallbackIcon = fullfile(obj.mibModel.mibPath, 'assets', 'icons', 'mib_icon_16px.png');
            if isfile(localIcon)
                obj.view.gui.Icon = localIcon;
            elseif isfile(fallbackIcon)
                obj.view.gui.Icon = fallbackIcon;
            end

            if isdeployed
                obj.view.handles.exportMatlabCheck.Enable = 'off';
            end

            obj.view.gui = utils.moveWindowOutside(obj.view.gui, obj.mibModel.mibGUI, 'left');

            Font = obj.mibModel.preferences.System.Font;
            if obj.view.handles.infoText.FontSize ~= Font.FontSize ...
                    || ~strcmp(obj.view.handles.infoText.FontName, Font.FontName)
                utils.fontSizeUpdate(obj.view.gui, Font);
            end

            obj.updateWidgets();
            obj.view.gui.Visible = true;

            obj.listener{1} = addlistener(obj.mibModel, 'UpdateGuiWidgets', ...
                @(src,evnt) obj.ViewListner_Callback2(obj, src, evnt));
        end

        function closeWindow(obj)
            if isvalid(obj.view.gui); delete(obj.view.gui); end
            for i = 1:numel(obj.listener); delete(obj.listener{i}); end
            notify(obj, 'CloseEvent');
        end

        function addCallbacks(obj)
            obj.view.gui.CloseRequestFcn = @(~,~) obj.closeWindow();
            handles = obj.view.handles;

            handles.infoText.Text = sprintf(['Detection of contacts between organelles of interest ' ...
                'and calculation of distance distributions between them\n' ...
                'See details in the Help section']);

            id = obj.mibModel.getActiveId();
            [filePath, fileName] = fileparts(obj.mibModel.I{id}.image.filename);
            handles.filenameEdit.Value   = fullfile(filePath, [fileName '_MCcalc.xlsx']);
            handles.filenameEdit.Tooltip = fullfile(filePath, [fileName '_MCcalc.xlsx']);
            handles.resultImagesDirEdit.Value   = filePath;
            handles.resultImagesDirEdit.Tooltip = filePath;

            handles.continueBtn.ButtonPushedFcn             = @(~,~) obj.continueBtn_Callback();
            handles.closeBtn.ButtonPushedFcn                = @(~,~) obj.closeWindow();
            handles.helpBtn.ButtonPushedFcn                 = @(~,~) obj.helpBtn_Callback();
            handles.calcPixelsCheck.ValueChangedFcn         = @(~,~) obj.calcPixelsCheck_Callback();
            handles.exportMatlabCheck.ValueChangedFcn       = @(~,~) obj.exportMatlabCheck_Callback();
            handles.saveResultsCheck.ValueChangedFcn        = @(~,~) obj.saveResultsCheck_Callback();
            handles.exportResultsFilename.ButtonPushedFcn   = @(~,~) obj.exportResultsFilename_Callback();
            handles.resultsImagesCheck.ValueChangedFcn      = @(~,~) obj.resultsImagesCheck_Callback();
            handles.resultImagesDirBtn.ButtonPushedFcn      = @(~,~) obj.resultImagesDirBtn_Callback();
            handles.detectContactsCheck.ValueChangedFcn     = @(~,~) obj.detectContactsCheck_Callback();
            handles.extendRays.ValueChangedFcn              = @(~,~) obj.extendRays_Callback();
        end

        function updateWidgets(obj)
            id = obj.mibModel.getActiveId();
            materialsList = obj.mibModel.I{id}.labels.materialNames;
            if isempty(materialsList)
                materialsList = {'Insufficient data, please check Help!'};
                obj.view.handles.continueBtn.Enable = 'off';
            else
                obj.view.handles.continueBtn.Enable = 'on';
            end
            obj.view.handles.material1Popup.Items = materialsList;
            obj.view.handles.material2Popup.Items = materialsList;
            obj.view.handles.material1Popup.Value = materialsList{1};
            if numel(materialsList) > 1
                obj.view.handles.material2Popup.Value = materialsList{2};
            else
                obj.view.handles.material2Popup.Value = materialsList{1};
            end
        end

        function calcPixelsCheck_Callback(obj)
            id = obj.mibModel.getActiveId();
            rangeUnits = obj.view.handles.probeDistanceEdit.Value;
            rangeCutoffUnits = obj.view.handles.contactCutOffEdit.Value;
            pixSizeX = obj.mibModel.I{id}.image.pixSize.x;
            if obj.view.handles.calcPixelsCheck.Value
                obj.view.handles.probeDistanceEdit.Limits = [1, Inf];
                obj.view.handles.probeDistanceEdit.ValueDisplayFormat = '%d';
                obj.view.handles.probeDistanceEdit.Value = max([1, ceil(rangeUnits / pixSizeX)]);
                obj.view.handles.contactCutOffEdit.Limits = [1, Inf];
                obj.view.handles.contactCutOffEdit.ValueDisplayFormat = '%d';
                obj.view.handles.contactCutOffEdit.Value = max([1, ceil(rangeCutoffUnits / pixSizeX)]);
                obj.view.handles.unitsText.Text = 'pixels';
            else
                obj.view.handles.probeDistanceEdit.Limits = [0, Inf];
                obj.view.handles.probeDistanceEdit.ValueDisplayFormat = '%.3f';
                obj.view.handles.probeDistanceEdit.Value = rangeUnits * pixSizeX;
                obj.view.handles.contactCutOffEdit.Limits = [0, Inf];
                obj.view.handles.contactCutOffEdit.ValueDisplayFormat = '%.3f';
                obj.view.handles.contactCutOffEdit.Value = rangeCutoffUnits * pixSizeX;
                obj.view.handles.unitsText.Text = obj.mibModel.I{id}.image.pixSize.units;
            end
        end

        function exportMatlabCheck_Callback(obj)
            if obj.view.handles.exportMatlabCheck.Value
                answer = utils.dlgs.inputUniversalDlg(obj.view.gui, '', ...
                    {sprintf('Please define output variable:')}, ...
                    {obj.matlabExportVariable}, 'Export variable');
                if ~isempty(answer)
                    obj.matlabExportVariable = answer{1};
                else
                    obj.view.handles.exportMatlabCheck.Value = false;
                end
            end
        end

        function helpBtn_Callback(obj)
            helpFilPath = fullfile(fileparts(obj.mibModel.mibPath), 'docs', 'site', 'user-interface', 'plugins', 'organelle-analysis', 'mccalc.html');
            if isfile(helpFilPath)
                web(helpFilPath, '-browser');
            else
                web('http://mib.helsinki.fi/help/main3/user-interface/plugins/organelle-analysis/mccalc.html', '-browser');
            end
        end

        function saveResultsCheck_Callback(obj)
            if obj.view.handles.saveResultsCheck.Value
                obj.view.handles.exportResultsFilename.Enable = 'on';
                obj.view.handles.filenameEdit.Enable = 'on';
            else
                obj.view.handles.exportResultsFilename.Enable = 'off';
                obj.view.handles.filenameEdit.Enable = 'off';
            end
        end

        function exportResultsFilename_Callback(obj)
            formatText = {'*.xlsx', 'Microsoft Excel (*.xlsx)'; '*.mat', 'Matlab format (*.mat)'};
            currentFilename = obj.view.handles.filenameEdit.Value;
            [fileName, pathName] = uiputfile(formatText, 'Select filename', currentFilename);
            if isequal(fileName, 0) || isequal(pathName, 0); return; end
            outputFilename = fullfile(pathName, fileName);
            obj.view.handles.filenameEdit.Value = outputFilename;
            obj.view.handles.filenameEdit.Tooltip = outputFilename;
        end

        function resultsImagesCheck_Callback(obj)
            if obj.view.handles.resultsImagesCheck.Value
                obj.view.handles.resultImagesDirBtn.Enable = 'on';
                obj.view.handles.resultImagesDirEdit.Enable = 'on';
                obj.view.handles.outputResolutionEdit.Enable = 'on';
            else
                obj.view.handles.resultImagesDirBtn.Enable = 'off';
                obj.view.handles.resultImagesDirEdit.Enable = 'off';
                obj.view.handles.outputResolutionEdit.Enable = 'off';
            end
        end

        function resultImagesDirBtn_Callback(obj)
            startPath = obj.view.handles.resultImagesDirEdit.Value;
            folderName = uigetdir(startPath, 'Select directory');
            if isequal(folderName, 0); return; end
            obj.view.handles.resultImagesDirEdit.Value = folderName;
            obj.view.handles.resultImagesDirEdit.Tooltip = folderName;
        end

        function detectContactsCheck_Callback(obj)
            if obj.view.handles.detectContactsCheck.Value
                obj.view.handles.contactCutOffEdit.Enable = 'on';
                obj.view.handles.contactGapWidthEdit.Enable = 'on';
                obj.view.handles.highlightCheck.Enable = 'on';
            else
                obj.view.handles.contactCutOffEdit.Enable = 'off';
                obj.view.handles.contactGapWidthEdit.Enable = 'off';
                obj.view.handles.highlightCheck.Enable = 'off';
            end
        end

        function extendRays_Callback(obj)
            if obj.view.handles.extendRays.Value
                obj.view.handles.extendRaysFactor.Enable = 'on';
            else
                obj.view.handles.extendRaysFactor.Enable = 'off';
            end
        end

        function continueBtn_Callback(obj)
            id = obj.mibModel.getActiveId();
            outFilename = obj.view.handles.filenameEdit.Value;

            if obj.mibModel.I{id}.modelExist == 0
                utils.dlgs.showErrorDialog(obj.view.gui, 'This plugin requires a model to be present!', 'Model is missing');
                return;
            end

            if obj.view.handles.saveResultsCheck.Value
                if exist(outFilename, 'file') == 2
                    strText = sprintf('!!! Warning !!!\n\nThe file:\n%s \nis already exist!\n\nOverwrite?', outFilename);
                    button = utils.dlgs.inputQuestDlg(obj.view.gui, strText, 'File exist!', 'Overwrite', 'Cancel', 'Cancel');
                    if strcmp(button, 'Cancel'); return; end
                    delete(outFilename);
                end
            end

            material1_Index = find(strcmp(obj.view.handles.material1Popup.Items, obj.view.handles.material1Popup.Value));
            material2_Index = find(strcmp(obj.view.handles.material2Popup.Items, obj.view.handles.material2Popup.Value));

            tic

            obj.mibModel.I{id}.annotations.clearContents();

            probingRangeInUnits = obj.view.handles.probeDistanceEdit.Value;
            if obj.view.handles.calcPixelsCheck.Value
                pixSize = 1;
                units = 'pixels';
                range = ceil(probingRangeInUnits);
            else
                pixSize = obj.mibModel.I{id}.image.pixSize.x;
                units = obj.mibModel.I{id}.image.pixSize.units;
                range = ceil(probingRangeInUnits / pixSize);
            end

            generateSelectionSw = obj.view.handles.highlightCheck.Value;
            smoothing = obj.view.handles.smoothEdit.Value;
            showObj = obj.view.handles.showObjectEdit.Value;
            exportToMatlab = obj.view.handles.exportMatlabCheck.Value;
            saveToFile = obj.view.handles.saveResultsCheck.Value;
            saveImages = obj.view.handles.resultsImagesCheck.Value;
            outDir = obj.view.handles.resultImagesDirEdit.Value;
            histBinningEdit = ceil(obj.view.handles.histBinningEdit.Value);
            outputResolution = sprintf('-r%d', obj.view.handles.outputResolutionEdit.Value);
            extendRays = logical(obj.view.handles.extendRays.Value);
            extendRaysFactor = obj.view.handles.extendRaysFactor.Value;

            if obj.view.handles.detectContactsCheck.Value
                contactCutOff = obj.view.handles.contactCutOffEdit.Value;
                contactGapWidth = obj.view.handles.contactGapWidthEdit.Value;
                if contactGapWidth <= sqrt(2)
                    contactGapWidth = sqrt(2) + 0.05;
                    obj.view.handles.contactGapWidthEdit.Value = contactGapWidth;
                end
            else
                contactCutOff = 0;
                contactGapWidth = 0;
            end

            if saveImages && ~isfolder(outDir)
                mkdir(outDir);
            end

            height = obj.mibModel.I{id}.image.height;
            width  = obj.mibModel.I{id}.image.width;

            MCcalcExport = struct();
            MCcalcExport(1).smoothing = smoothing;
            MCcalcExport(1).probingRangeInUnits = probingRangeInUnits;
            MCcalcExport(1).units = units;
            MCcalcExport(1).pixSize = pixSize;
            MCcalcExport(1).mainMaterial = obj.mibModel.I{id}.labels.materialNames(material1_Index);
            MCcalcExport(1).secondaryMaterial = obj.mibModel.I{id}.labels.materialNames(material2_Index);
            MCcalcExport(1).histBinningEdit = histBinningEdit;
            MCcalcExport(1).contactCutOff = contactCutOff;
            MCcalcExport(1).contactGapWidth = contactGapWidth;
            MCcalcExport(1).extendRays = extendRays;
            MCcalcExport(1).extendRaysFactor = extendRaysFactor;

            progressBar = uiprogressdlg(obj.view.gui, 'Value', 0, ...
                'Message', sprintf('Calculating\nPlease wait...'), 'Title', 'MCcalc progress');

            fh{1} = figure('Visible', 'off');
            fh{1}.Position = [969   141   909   934];
            fh{2} = figure('Visible', 'off');
            fh{2}.Position = [969   141   909   934];

            useDistanceMap = false;

            objId = 1;
            sliceCounter = 1;
            maxSlice = obj.mibModel.I{id}.image.time * obj.mibModel.I{id}.image.depth;
            getDataOptions.blockModeSwitch = 0;

            for t = 1:obj.mibModel.I{id}.image.time
                getDataOptions.t = [t, t];
                for z = 1:obj.mibModel.I{id}.image.depth
                    M1 = cell2mat(obj.mibModel.getData2D('labels', z, 3, material1_Index, getDataOptions));
                    M2 = cell2mat(obj.mibModel.getData2D('labels', z, 3, material2_Index, getDataOptions));

                    CC = bwconncomp(M1, 8);
                    noPixels = cellfun(@numel, CC.PixelIdxList);
                    smallObjIndices = find(noPixels < 20);
                    if ~isempty(smallObjIndices)
                        CC.PixelIdxList(smallObjIndices) = [];
                        CC.NumObjects = numel(CC.PixelIdxList);
                        fprintf('Removing %d small objects (smaller than 20 pixels), time point: %d, slice number: %d', numel(smallObjIndices), t, z);
                    end
                    STATS = regionprops(CC, 'BoundingBox', 'Centroid', 'Area', 'Eccentricity');

                    if generateSelectionSw
                        selection = zeros(size(M1), 'uint8');
                    end

                    if useDistanceMap
                        M2dist = bwdist(M2, 'euclidean'); %#ok<UNRCH>
                    end

                    for objIndex = 1:CC.NumObjects
                        x1 = ceil(STATS(objIndex).BoundingBox(1));
                        y1 = ceil(STATS(objIndex).BoundingBox(2));
                        x2 = x1 + STATS(objIndex).BoundingBox(3);
                        y2 = y1 + STATS(objIndex).BoundingBox(4);

                        range2 = range + 10;
                        x1 = max([1 x1 - range2]);
                        x2 = min([width  x2 + range2]);
                        y1 = max([1 y1 - range2]);
                        y2 = min([height y2 + range2]);

                        M1c = zeros(size(M1), 'uint8');
                        M1c(CC.PixelIdxList{objIndex}) = 1;
                        M1c = M1c(y1:y2, x1:x2);
                        D2 = bwdist(M1c, 'euclidean');
                        M2c = M2(y1:y2, x1:x2);
                        if material1_Index == material2_Index
                            M2c(M1c == 1) = 0;
                        end
                        D2(~M2c) = Inf;

                        Dn = bwdist(~M1c);
                        UltErosionCrop = imregionalmax(Dn, 8);
                        mainMinThicknessUnits = mean(Dn(UltErosionCrop > 0) * 2 * pixSize);
                        mainAreaUnits = STATS(objIndex).Area * pixSize * pixSize;
                        mainEccentricity = STATS(objIndex).Eccentricity;

                        cWidth  = size(M1c, 2);
                        cHeight = size(M1c, 1);

                        Boundary = bwboundaries(M1c, 8);
                        Boundary = cell2mat(Boundary);

                        if smoothing > 0
                            extBoundary = repmat(Boundary, [3, 1]);
                            extBoundary(:,1) = utils.align.windv(extBoundary(:,1), floor(smoothing/2), 1);
                            extBoundary(:,2) = utils.align.windv(extBoundary(:,2), floor(smoothing/2), 1);
                            Boundary = extBoundary(size(Boundary,1)+1:size(Boundary,1)*2, :);
                        end

                        d = diff([Boundary(:,2) Boundary(:,1)]);
                        mainTotalPerimeter = sum(sqrt(sum(d.*d, 2))) * pixSize;

                        indicesX1 = find(Boundary(:,2) == 1);
                        indicesX2 = find(Boundary(:,2) == cWidth);
                        indicesY1 = find(Boundary(:,1) == 1);
                        indicesY2 = find(Boundary(:,1) == cHeight);
                        indices = unique([indicesX1; indicesX2; indicesY1; indicesY2]);

                        mainPerimeterBorder = 0;
                        if ~isempty(indices)
                            for brakePnt = 1:numel(indices)-1
                                if indices(brakePnt+1) - indices(brakePnt) == 1
                                    mainPerimeterBorder = sqrt((Boundary(indices(brakePnt),2) - Boundary(indices(brakePnt+1),2))^2 + ...
                                        (Boundary(indices(brakePnt),1) - Boundary(indices(brakePnt+1),1))^2) + mainPerimeterBorder;
                                end
                            end
                        end
                        mainPerimeterBorder = mainPerimeterBorder * pixSize;

                        B = Boundary;
                        B(indices, :) = [];

                        if useDistanceMap %#ok<UNRCH>
                        else
                            [results, B, rayDestinationPosX, rayDestinationPosY, Bx1, Bx2, By1, By2] = ...
                                obj.raytraceObject(B, D2, range, pixSize, extendRays, extendRaysFactor);
                        end

                        if MCcalcExport(1).contactCutOff > 0
                            try
                                contactIds = find(results < contactCutOff);
                                contactLength = [];
                                contactMeanDistance = [];
                                contactIndex = 1;

                                if ~isempty(contactIds) && numel(contactIds) > 1
                                    contactDistVector = sqrt(sum(diff(B(contactIds,:)).^2, 2));
                                    contactBrkPoints = find(contactDistVector > MCcalcExport(1).contactGapWidth);

                                    if isempty(contactBrkPoints)
                                        contactLength = sum(sqrt(sum(diff(B(contactIds(1):contactIds(end),:)).^2, 2)));
                                        distVector = results(contactIds);
                                        distVector(distVector == Inf) = [];
                                        contactMeanDistance(1) = mean(distVector);
                                    else
                                        contactLength = zeros([numel(contactBrkPoints)+1, 1]);
                                        contactMeanDistance = zeros([numel(contactBrkPoints)+1, 1]);

                                        contactLength(contactIndex) = sum(sqrt(sum(diff(B(contactIds(1):contactIds(contactBrkPoints(1)),:), 1, 1).^2, 2))) + 1;
                                        distVector = results(contactIds(1):contactIds(contactBrkPoints(1)));
                                        contactIds1 = contactIds(1):contactIds(contactBrkPoints(1));
                                        contactIds1(distVector == Inf) = [];
                                        distVector(distVector == Inf) = [];
                                        contactMeanDistance(contactIndex) = mean(distVector);

                                        for brkPnt = 1:numel(contactBrkPoints)-1
                                            contactIndex = contactIndex + 1;
                                            localIndices = contactIds(contactBrkPoints(brkPnt)+1):contactIds(contactBrkPoints(brkPnt+1));
                                            if numel(localIndices) > 1
                                                contactLength(contactIndex) = sum(sqrt(sum(diff(B(contactIds(contactBrkPoints(brkPnt)+1):contactIds(contactBrkPoints(brkPnt+1)),:), 1, 1).^2, 2))) + 1;
                                            else
                                                contactLength(contactIndex) = 1;
                                            end
                                            distVector = results(contactIds(contactBrkPoints(brkPnt)+1):contactIds(contactBrkPoints(brkPnt+1)));
                                            distVector(distVector == Inf) = [];
                                            contactMeanDistance(contactIndex) = mean(distVector);
                                        end

                                        contactIndex = contactIndex + 1;
                                        contactLength(contactIndex) = sum(sqrt(sum(diff(B(contactIds(contactBrkPoints(end)+1)-1:contactIds(end)-1,:), 1, 1).^2, 2))) + 1;

                                        distVector = results(contactIds(contactBrkPoints(end)+1):contactIds(end));
                                        contactIds2 = contactIds(contactBrkPoints(end)+1):contactIds(end);
                                        contactIds2(distVector == Inf) = [];
                                        distVector(distVector == Inf) = [];
                                        contactMeanDistance(contactIndex) = mean(distVector);
                                    end

                                    if contactIds(1) == 1 && contactIds(end) == numel(results)
                                        if contactIndex > 1
                                            contactLength(1) = contactLength(1) + contactLength(end);
                                            contactLength(end) = [];
                                            contactMeanDistance(1) = mean([results(contactIds1); results(contactIds2)]);
                                            contactMeanDistance(end) = [];
                                        end
                                    end

                                    contactLength = contactLength * pixSize;
                                    contactMeanDistance = contactMeanDistance - pixSize;

                                    GapsPositionIndices = find(contactDistVector > sqrt(2) & contactDistVector < MCcalcExport(1).contactGapWidth);
                                    for gapIdx = 1:numel(GapsPositionIndices)
                                        contactIds = [contactIds; (contactIds(GapsPositionIndices(gapIdx))+1:contactIds(GapsPositionIndices(gapIdx)+1)-1)']; %#ok<AGROW>
                                    end
                                    contactIds = sort(contactIds);
                                end

                                cutOffContactY = round(B(contactIds, 1));
                                cutOffContactX = round(B(contactIds, 2));
                                if generateSelectionSw
                                    for ind = 1:numel(cutOffContactY)
                                        selection(cutOffContactY(ind)+y1-1, cutOffContactX(ind)+x1-1) = 1;
                                    end
                                end

                            catch err
                                err %#ok<NOANS>
                            end
                        end

                        InfIndices = find(results == Inf);
                        rayDestinationPosY(InfIndices) = [];
                        rayDestinationPosX(InfIndices) = [];
                        results(InfIndices) = [];

                        raySourcePosX = B(:,2);
                        raySourcePosX(InfIndices) = [];
                        raySourcePosY = B(:,1);
                        raySourcePosY(InfIndices) = [];

                        MCcalcExport(objId).Centroid = STATS(objIndex).Centroid;
                        MCcalcExport(objId).time = t;
                        MCcalcExport(objId).slice = z;
                        MCcalcExport(objId).MinDist = results;
                        MCcalcExport(objId).rayDestinationPosX = rayDestinationPosX;
                        MCcalcExport(objId).rayDestinationPosY = rayDestinationPosY;
                        MCcalcExport(objId).raySourcePosX = raySourcePosX;
                        MCcalcExport(objId).raySourcePosY = raySourcePosY;
                        MCcalcExport(objId).mainPerimeterWithoutBorder = mainTotalPerimeter - mainPerimeterBorder;
                        MCcalcExport(objId).mainPerimeterBorder = mainPerimeterBorder;
                        MCcalcExport(objId).mainPerimeterNoPixels = size(B, 1);
                        MCcalcExport(objId).mainMinThicknessUnits = mainMinThicknessUnits;
                        MCcalcExport(objId).mainAreaUnits = mainAreaUnits;
                        MCcalcExport(objId).mainEccentricity = mainEccentricity;
                        MCcalcExport(objId).secondaryHitsNoPixels = size(rayDestinationPosX, 1);
                        if MCcalcExport(1).contactCutOff > 0
                            MCcalcExport(objId).cutOffContactX = cutOffContactX;
                            MCcalcExport(objId).cutOffContactY = cutOffContactY;
                            MCcalcExport(objId).contactLength = contactLength;
                            MCcalcExport(objId).contactMeanDistance = contactMeanDistance;
                        end

                        edges = pixSize*histBinningEdit:pixSize*histBinningEdit:probingRangeInUnits;
                        DistributionMinDist = histcounts(MCcalcExport(objId).MinDist, edges);
                        MCcalcExport(objId).DistributionMinDist = DistributionMinDist;
                        MCcalcExport(objId).DistributionCenters = edges(1:end-1);
                        DistributionMinDistNorm = DistributionMinDist / MCcalcExport(objId).mainPerimeterNoPixels;
                        MCcalcExport(objId).DistributionMinDistNorm = DistributionMinDistNorm;

                        if objId == 1
                            MCcalcExport(1).DistributionMinDistNormAv = zeros([numel(MCcalcExport(1).DistributionCenters), 1]);
                        end
                        MCcalcExport(1).DistributionMinDistNormAv = MCcalcExport(1).DistributionMinDistNormAv + MCcalcExport(objId).DistributionMinDistNorm';

                        obj.mibModel.I{id}.annotations.addLabels({num2str(objId)}, [z, STATS(objIndex).Centroid, t]);

                        if saveImages || objId == showObj
                            if objId == showObj
                                figId = 1;
                            else
                                figId = 2;
                            end
                            clf(fh{figId});

                            D3 = D2;
                            D3(D3 == Inf) = 0;
                            B2 = bwboundaries(M1c, 8);

                            ax1 = axes(fh{figId});
                            ax1.Position = [.1 .4 .8 .55];
                            image(ax1, repmat(uint8(D3*255), [1,1,3]));
                            ax1.DataAspectRatioMode = 'manual';
                            ax1.PlotBoxAspectRatioMode = 'manual';
                            ax1.DataAspectRatio = [1 1 1];

                            hold(ax1, 'on');
                            plot(ax1, Boundary(:,2), Boundary(:,1), 'y', 'LineWidth', 1);
                            plot(ax1, [Bx1 Bx2]', [By1 By2]');
                            for k = 1:length(B2)
                                boundary = B2{k};
                                plot(ax1, boundary(:,2), boundary(:,1), 'r', 'LineWidth', 1);
                            end
                            h = plot(ax1, B(1,2), B(1,1), 'rx');
                            set(h, 'MarkerSize', 10);
                            plot(ax1, MCcalcExport(objId).rayDestinationPosX, MCcalcExport(objId).rayDestinationPosY, 'g.');
                            if MCcalcExport(1).contactCutOff > 0
                                hc = plot(ax1, MCcalcExport(objId).cutOffContactX, MCcalcExport(objId).cutOffContactY, 'y.');
                                set(hc, 'MarkerSize', 6);
                            end

                            if strcmp(units, 'pixels')
                                titleStr = sprintf('Perimeter without edge: %.0f %s\nBorder length: %.0f %s', MCcalcExport(objId).mainPerimeterWithoutBorder, units, mainPerimeterBorder, units);
                            else
                                titleStr = sprintf('Perimeter without edge: %.3f %s\nBorder length: %.3f %s', MCcalcExport(objId).mainPerimeterWithoutBorder, units, mainPerimeterBorder, units);
                            end
                            ax1.Title.String = titleStr;

                            ax2 = axes(fh{figId});
                            ax2.Position = [.1, .1, .8, .2];
                            bar(ax2, MCcalcExport(objId).DistributionCenters, MCcalcExport(objId).DistributionMinDistNorm);
                            title(ax2, sprintf('Minimal distances (norm. to number of generated rays, %d)', MCcalcExport(objId).mainPerimeterNoPixels));
                            xlabel(ax2, sprintf('Distance from %s, in %s, step=%f', cell2mat(MCcalcExport(1).mainMaterial), units, pixSize*histBinningEdit));
                            ylabel(ax2, 'Occurrence / number rays');
                            if saveImages
                                try
                                    print(fh{figId}, fullfile(outDir, sprintf('ObjId_%04i.png', objId)), '-dpng', outputResolution);
                                catch
                                    disp(['An error detected in ' num2str(objId) '!']);
                                end
                            end
                            if objId == showObj
                                fh{figId}.Visible = 'on';
                            end
                        end
                        objId = objId + 1;
                    end

                    progressBar.Value = sliceCounter / maxSlice;
                    sliceCounter = sliceCounter + 1;

                    if generateSelectionSw
                        obj.mibModel.setData2D(selection, 'selection', z, 3, material1_Index, getDataOptions);
                    end
                end
            end

            delete(fh{2});

            MCcalcExport(1).DistributionMinDistNormAv = MCcalcExport(1).DistributionMinDistNormAv / numel(MCcalcExport);

            if exportToMatlab
                progressBar.Message = 'Exporting to Matlab...';
                progressBar.Value = 1;
                fprintf('MCcalc: a structure with results "%s" was created\n', obj.matlabExportVariable);
                assignin('base', obj.matlabExportVariable, MCcalcExport);
            end

            toc

            if saveToFile
                if strcmp(outFilename(end-2:end), 'mat') || exportToMatlab
                    [outMatPath, outMatFname] = fileparts(outFilename);
                    outMatFname = fullfile(outMatPath, [outMatFname, '.mat']);
                    progressBar.Message = 'Saving to Matlab file...';
                    progressBar.Value = 1;
                    fprintf('MCcalc: saving MCcalcExport structure to a file:\n%s\n', outMatFname);
                    save(outMatFname, 'MCcalcExport');
                end
                if strcmp(outFilename(end-3:end), 'xlsx')
                    progressBar.Message = 'Generating Excel file...';
                    progressBar.Value = 1;
                    obj.saveToExcel(MCcalcExport, outFilename);
                end
            end

            figure(1024)
            plot(MCcalcExport(1).DistributionCenters, MCcalcExport(1).DistributionMinDistNormAv);
            xlabel(sprintf('Distance from %s, in %s, step=%f', cell2mat(MCcalcExport(1).mainMaterial), units, pixSize*histBinningEdit));
            ylabel(sprintf('Occurrence/number of rays, averaged for all %s', cell2mat(MCcalcExport(1).mainMaterial)));
            title(sprintf('Averaged results for all points (N=%d)', numel(MCcalcExport)));
            grid;

            obj.mibModel.showAnnotations = true;
            notify(obj.mibModel, 'ShowImage');

            delete(progressBar);
        end

        function [results, B, rayDestinationPosX, rayDestinationPosY, Bx1, Bx2, By1, By2] = ...
                raytraceObject(obj, B, D2, range, pixSize, extendRays, extendRaysFactor)
            % RAYTRACEOBJECT - Use raytracing to find hits from main object boundary to secondary material.
            %
            % Parameters:
            %   B: [N x 2] boundary coordinates [y, x]
            %   D2: distance map (Inf where no secondary material)
            %   range: probing distance in pixels
            %   pixSize: pixel size for unit conversion
            %   extendRays: logical, extend rays with additional vector rays
            %   extendRaysFactor: precision at the end of the ray

            cWidth  = size(D2, 2);
            cHeight = size(D2, 1);

            N = LineNormals2D(B);

            nanVecY = find(isnan(N(:,1)));
            nanVecX = find(isnan(N(:,2)));
            nanVec  = unique([nanVecY; nanVecX]);
            N(nanVec, :) = [];
            B(nanVec, :) = [];

            Bx1 = B(:, 2);
            Bx2 = B(:, 2) + range * N(:, 2);
            By1 = B(:, 1);
            By2 = B(:, 1) + range * N(:, 1);

            if extendRays == 1
                Bx1 = [Bx1; Bx1(1)]; %#ok<AGROW>
                Bx2 = [Bx2; Bx2(1)]; %#ok<AGROW>
                By1 = [By1; By1(1)]; %#ok<AGROW>
                By2 = [By2; By2(1)]; %#ok<AGROW>

                pntDiff      = sqrt(diff(Bx2).^2 + diff(By2).^2);
                pntDiffN_Orgn = sqrt(diff(Bx1).^2 + diff(By1).^2);

                dN_ind     = find(pntDiff > extendRaysFactor);
                Border_ind = find(pntDiffN_Orgn >= 2);

                noExtraPoints = sum(abs(floor(pntDiff(dN_ind)/extendRaysFactor))) + numel(dN_ind)*2;
                B2x1 = nan([numel(Bx1)+noExtraPoints, 1]);
                B2x2 = nan([numel(Bx1)+noExtraPoints, 1]);
                B2y1 = nan([numel(Bx1)+noExtraPoints, 1]);
                B2y2 = nan([numel(Bx1)+noExtraPoints, 1]);

                newIndex    = 1;
                diffVecIndex = 1;
                for i = 1:numel(Bx1)
                    if isempty(find(dN_ind == i, 1)) || sum(ismember(Border_ind, [i, i+1])) > 0
                        B2x1(newIndex) = Bx1(i);
                        B2x2(newIndex) = Bx2(i);
                        B2y1(newIndex) = By1(i);
                        B2y2(newIndex) = By2(i);
                        newIndex = newIndex + 1;
                        if ismember(i+1, Border_ind) == 1
                            diffVecIndex = diffVecIndex + 1;
                        end
                    else
                        extraNsX = linspace(Bx2(dN_ind(diffVecIndex)), Bx2(dN_ind(diffVecIndex)+1), floor(abs(pntDiff(dN_ind(diffVecIndex)))/extendRaysFactor)+2);
                        extraNsY = linspace(By2(dN_ind(diffVecIndex)), By2(dN_ind(diffVecIndex)+1), floor(abs(pntDiff(dN_ind(diffVecIndex)))/extendRaysFactor)+2);
                        noExtraNs = numel(extraNsX);
                        B2x1(newIndex:newIndex+noExtraNs-1) = Bx1(i);
                        B2y1(newIndex:newIndex+noExtraNs-1) = By1(i);
                        B2x2(newIndex:newIndex+noExtraNs-1) = extraNsX';
                        B2y2(newIndex:newIndex+noExtraNs-1) = extraNsY';
                        newIndex = newIndex + noExtraNs;
                        diffVecIndex = diffVecIndex + 1;
                    end
                end

                nanIndex = find(isnan(B2x1(:,1)) == 1, 1);
                Bx1 = B2x1(1:nanIndex-1);
                Bx2 = B2x2(1:nanIndex-1);
                By1 = B2y1(1:nanIndex-1);
                By2 = B2y2(1:nanIndex-1);
                B = By1;
                B(:, 2) = Bx1;
            end

            results            = Inf(size(B,1), 1);
            rayDestinationPosX = zeros(size(B,1), 1);
            rayDestinationPosY = zeros(size(B,1), 1);

            for point = 1:size(B,1)
                dx = Bx2(point) - Bx1(point);
                dy = By2(point) - By1(point);
                nPnts = max([abs(dx) abs(dy)]) + 1;
                linSpacing = linspace(0, 1, nPnts);

                xVal = round(Bx1(point) + linSpacing * dx);
                yVal = round(By1(point) + linSpacing * dy);

                indicesX1 = find(xVal < 1);
                indicesX2 = find(xVal > cWidth);
                indicesY1 = find(yVal < 1);
                indicesY2 = find(yVal > cHeight);
                outIndices = unique([indicesX1, indicesX2, indicesY1, indicesY2]);
                xVal(outIndices) = [];
                yVal(outIndices) = [];

                linIndices = sub2ind([cHeight, cWidth], yVal, xVal);
                minVal = min(min(D2(linIndices)));
                if minVal ~= Inf
                    results(point) = minVal * pixSize;
                    pointIndex = find(D2(linIndices) == minVal);
                    if numel(pointIndex) == 1
                        rayDestinationPosY(point) = yVal(pointIndex);
                        rayDestinationPosX(point) = xVal(pointIndex);
                    else
                        point2 = 1;
                        dist1 = sqrt((By1(point)-yVal(pointIndex(point2)))^2 + (Bx1(point)-xVal(pointIndex(point2)))^2);
                        for ind2 = 2:numel(pointIndex)
                            dist2 = sqrt((By1(point)-yVal(pointIndex(ind2)))^2 + (Bx1(point)-xVal(pointIndex(ind2)))^2);
                            if dist2 < dist1
                                dist1 = dist2;
                                point2 = ind2;
                            end
                        end
                        rayDestinationPosY(point) = yVal(pointIndex(point2));
                        rayDestinationPosX(point) = xVal(pointIndex(point2));
                    end
                end
            end
        end

        function saveToExcel(obj, MCcalcExport, outFn)
            id = obj.mibModel.getActiveId();
            warning('off', 'MATLAB:xlswrite:AddSheet');

            s = {'MCcalc: calculate distribution of minimal distances from main object to secondary objects'};
            s(2,1) = {['Image directory: ' fileparts(obj.mibModel.I{id}.image.filename)]};
            s(3,1) = {['Main object material: ' cell2mat(MCcalcExport(1).mainMaterial)]};
            s(3,5) = {['Pixel size/units: ' num2str(MCcalcExport(1).pixSize) ' ' MCcalcExport(1).units]};
            s(3,9) = {['Smoothing of rays, px: ' num2str(MCcalcExport(1).smoothing)]};
            s(3,13) = {['Extended rays, logical: ' num2str(MCcalcExport(1).extendRays)]};
            s(4,1) = {['Secondary object material: ' cell2mat(MCcalcExport(1).secondaryMaterial)]};
            s(4,5) = {['Probing range: ' num2str(MCcalcExport(1).probingRangeInUnits) ' ' MCcalcExport(1).units]};
            s(4,9) = {['Histogram bin factor: ' num2str(MCcalcExport(1).histBinningEdit)]};
            s(4,13) = {['Extend rays precision, px: ' num2str(MCcalcExport(1).extendRaysFactor)]};
            s(5,1) = {['Model filename: ' obj.mibModel.I{id}.labels.filename]};

            s(8,1) = {'ObjId'}; s(8,2) = {'Time'}; s(8,3) = {'Z, index'}; s(8,4) = {'X, px'}; s(8,5) = {'Y, px'};
            s(8,6) = {sprintf('PerimeterWithoutBorder, %s', MCcalcExport(1).units)};
            s(8,7) = {sprintf('BorderPerimeter, %s', MCcalcExport(1).units)};
            s(8,8) = {'NoPixelsOfPerimeterWithoutBorder'}; s(8,9) = {'NoOfHitPixels'};
            s(8,10) = {sprintf('MinThickness, %s', MCcalcExport(1).units)};
            s(8,11) = {sprintf('Area, %s', MCcalcExport(1).units)};
            s(8,12) = {'Eccentricity, 0-circle'};

            shiftY = 8;
            for objId = 1:numel(MCcalcExport)
                s(shiftY+objId, 1) = num2cell(objId);
                s(shiftY+objId, 2) = num2cell(MCcalcExport(objId).time);
                s(shiftY+objId, 3) = num2cell(MCcalcExport(objId).slice);
                s(shiftY+objId, 4) = num2cell(MCcalcExport(objId).Centroid(1));
                s(shiftY+objId, 5) = num2cell(MCcalcExport(objId).Centroid(2));
                s(shiftY+objId, 6) = num2cell(MCcalcExport(objId).mainPerimeterWithoutBorder);
                s(shiftY+objId, 7) = num2cell(MCcalcExport(objId).mainPerimeterBorder);
                s(shiftY+objId, 8) = num2cell(MCcalcExport(objId).mainPerimeterNoPixels);
                s(shiftY+objId, 9) = num2cell(MCcalcExport(objId).secondaryHitsNoPixels);
                s(shiftY+objId, 10) = num2cell(MCcalcExport(objId).mainMinThicknessUnits);
                s(shiftY+objId, 11) = num2cell(MCcalcExport(objId).mainAreaUnits);
                s(shiftY+objId, 12) = num2cell(MCcalcExport(objId).mainEccentricity);
            end
            xlswrite2(outFn, s, 'General results', 'A1');

            s = {'Distribution of minimal distances for objects'};
            shiftY = 2;
            shiftX = 2;
            s(shiftY+1, shiftX) = {['Distance, ' MCcalcExport(1).units]};
            maxNo = numel(MCcalcExport(1).DistributionCenters);
            s(shiftY+2:shiftY+1+maxNo, shiftX) = num2cell(cat(1, MCcalcExport(1).DistributionCenters));
            for objId = 1:numel(MCcalcExport)
                shiftX = shiftX + 1;
                s(shiftY+1, shiftX) = {['Obj. ' num2str(objId)]};
                s(shiftY+2:shiftY+1+maxNo, shiftX) = num2cell(cat(1, MCcalcExport(objId).DistributionMinDist));
            end
            xlswrite2(outFn, s, 'Dist. of distances', 'A1');

            s = {'Normalized distribution to number of points of the main object perimeter'};
            shiftY = 2;
            shiftX = 2;
            s(shiftY+1, shiftX) = {['Distance, ' MCcalcExport(1).units]};
            s(shiftY+1, shiftX+1) = {'Averaged'};
            maxNo = numel(MCcalcExport(1).DistributionCenters);
            s(shiftY+2:shiftY+1+maxNo, shiftX) = num2cell(cat(1, MCcalcExport(1).DistributionCenters));
            s(shiftY+2:shiftY+1+maxNo, shiftX+1) = num2cell(cat(1, MCcalcExport(1).DistributionMinDistNormAv));
            shiftX = shiftX + 6;
            s(shiftY+1, shiftX) = {['Distance, ' MCcalcExport(1).units]};
            s(shiftY+2:shiftY+1+maxNo, shiftX) = num2cell(cat(1, MCcalcExport(1).DistributionCenters));
            for objId = 1:numel(MCcalcExport)
                shiftX = shiftX + 1;
                s(shiftY+1, shiftX+1) = {['Obj. ' num2str(objId)]};
                s(shiftY+2:shiftY+1+maxNo, shiftX+1) = num2cell(cat(1, MCcalcExport(objId).DistributionMinDistNorm));
            end
            xlswrite2(outFn, s, 'Dist. of distances (norm)', 'A1');

            if MCcalcExport(1).contactCutOff > 0
                s = {'Length of detected contacts'};
                s(2, 1) = {['Cut off distance: ' num2str(MCcalcExport(1).contactCutOff) ' ' MCcalcExport(1).units]};
                s(3, 1) = {['Fuse contacts with brakes smaller than : ' num2str(MCcalcExport(1).contactGapWidth) ' pixels']};
                s(5, 2) = {'Obj. Id'};
                s(5, 3) = {sprintf('PerimeterWithoutBorder, %s', MCcalcExport(1).units)};
                s(5, 4) = {'Number of contacts'};
                s(5, 5) = {sprintf('Sum length of contacts, %s', MCcalcExport(1).units)};
                s(5, 6) = {'Ratio Contacts/Obj'};
                s(5, 9) = {sprintf('Length of each contact, %s', MCcalcExport(1).units)};
                maxContactsNumber = max(arrayfun(@(x) numel(x.contactLength), MCcalcExport));
                s(5, 10+maxContactsNumber) = {'Mean distance of each contact'};
                for objId = 1:numel(MCcalcExport)
                    s(objId+5, 2) = {['Obj. ' num2str(objId)]};
                    s(objId+5, 3) = num2cell(MCcalcExport(objId).mainPerimeterWithoutBorder);
                    s(objId+5, 4) = num2cell(numel(find(MCcalcExport(objId).contactLength > 0)));
                    s(objId+5, 5) = num2cell(sum(MCcalcExport(objId).contactLength));
                    s(objId+5, 6) = num2cell(sum(MCcalcExport(objId).contactLength) / MCcalcExport(objId).mainPerimeterWithoutBorder);
                    s(objId+5, 9:8+numel(MCcalcExport(objId).contactLength)) = num2cell(cat(1, MCcalcExport(objId).contactLength));
                    s(objId+5, 10+maxContactsNumber:9+maxContactsNumber+numel(MCcalcExport(objId).contactLength)) = num2cell(cat(1, MCcalcExport(objId).contactMeanDistance));
                end
                xlswrite2(outFn, s, 'Contacts', 'A1');
            end

            s = {'Check Sheet 1 also!!!'};
            s(1, 4) = {sprintf('RAW data, distance between the main and secondary organelle for each hit, i.e. when the ray hits the secondary object in %s', MCcalcExport(1).units)};
            s(2, 1) = {'ObjId:'};
            for objId = 1:numel(MCcalcExport)
                maxNo = numel(MCcalcExport(objId).MinDist);
                s(2, objId+1) = {num2str(objId)};
                s(3:maxNo+2, objId+1) = num2cell(cat(1, MCcalcExport(objId).MinDist))';
            end
            xlswrite2(outFn, s, 'RAW dist to hits', 'A1');
        end

    end
end
