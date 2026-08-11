classdef TripleAreaIntensity < handle
    % TripleAreaIntensity
    % Calculate image intensities (mean, min, max or sum) of 3 areas stored
    % under 3 materials of a model.
    %
    % @code
    % obj.startController('TripleAreaIntensity');
    % @endcode

    % Updates
    %

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
            switch evnt.EventName
                case {'UpdateGuiWidgets'}
                    obj.updateWidgets();
            end
        end
    end

    methods
        function obj = TripleAreaIntensity(mibModel)
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

            obj.matlabExportVariable = 'TripleAreaIntensity';

            guiName = 'TripleAreaIntensityGUI';
            obj.view = core.ChildView(obj, guiName);
            obj.addCallbacks();

            % set window icon
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
            if obj.view.handles.filenameEdit.FontSize ~= Font.FontSize ...
                    || ~strcmp(obj.view.handles.filenameEdit.FontName, Font.FontName)
                utils.fontSizeUpdate(obj.view.gui, Font);
            end

            obj.updateWidgets();
            obj.view.gui.Visible = true;
            obj.listener{1} = addlistener(obj.mibModel, 'UpdateGuiWidgets', @(src,evnt) obj.ViewListner_Callback2(obj, src, evnt));
        end

        function closeWindow(obj)
            if isvalid(obj.view.gui)
                delete(obj.view.gui);
            end
            for i = 1:numel(obj.listener)
                delete(obj.listener{i});
            end
            notify(obj, 'CloseEvent');
        end

        function addCallbacks(obj)
            obj.view.gui.CloseRequestFcn = @(~,~) obj.closeWindow();

            obj.view.handles.helpText.Text = ...
                'Calculate image intensities of two materials of the opened model. See details in the Help section.';

            handles = obj.view.handles;
            handles.continueBtn.ButtonPushedFcn               = @(~,~) obj.continueBtn_Callback();
            handles.closeBtn.ButtonPushedFcn                  = @(~,~) obj.closeWindow();
            handles.helpBtn.ButtonPushedFcn                   = @(~,~) obj.helpBtn_Callback();
            handles.selectFilenameBtn.ButtonPushedFcn         = @(~,~) obj.selectFilenameBtn_Callback();
            handles.savetoExcel.ValueChangedFcn               = @(~,~) obj.savetoExcel_Callback();
            handles.backgroundCheck.ValueChangedFcn           = @(~,~) obj.backgroundCheck_Callback();
            handles.additionalThresholdingCheck.ValueChangedFcn = @(~,~) obj.additionalThresholdingCheck_Callback();
            handles.exportMatlabCheck.ValueChangedFcn         = @(~,~) obj.exportMatlabCheck_Callback();
        end

        function updateWidgets(obj)
            id = obj.mibModel.getActiveId();

            % populate colour channel dropdown
            colorCount = obj.mibModel.I{id}.image.colors;
            colorChannelList = arrayfun(@(x) sprintf('Channel %d', x), 1:colorCount, 'UniformOutput', false);
            obj.view.handles.colorChannelCombo.Items = colorChannelList;
            colorChannelSelection = max([1 obj.mibModel.I{id}.slices{4}(1)]);
            if colorChannelSelection <= colorCount
                obj.view.handles.colorChannelCombo.Value = colorChannelList{colorChannelSelection};
            else
                obj.view.handles.colorChannelCombo.Value = colorChannelList{1};
            end

            % populate material dropdowns
            materialsList = obj.mibModel.I{id}.labels.materialNames;
            if isempty(materialsList)
                materialsList = {'Insufficient data, please check Help!'};
            end
            obj.view.handles.backgroundPopup.Items = materialsList;
            obj.view.handles.material1Popup.Items = materialsList;
            obj.view.handles.material2Popup.Items = materialsList;
            obj.view.handles.thresholdingPopup.Items = materialsList;

            obj.view.handles.backgroundPopup.Value = materialsList{1};
            obj.view.handles.material1Popup.Value = materialsList{1};
            obj.view.handles.thresholdingPopup.Value = materialsList{1};

            if obj.mibModel.I{id}.modelExist == 0 || (isscalar(materialsList) && strcmp(materialsList{1}, 'Insufficient data, please check Help!'))
                obj.view.handles.material2Popup.Value = materialsList{1};
                obj.view.handles.continueBtn.Enable = 'off';
            else
                obj.view.handles.continueBtn.Enable = 'on';
                if numel(materialsList) > 1
                    obj.view.handles.material2Popup.Value = materialsList{2};
                else
                    obj.view.handles.material2Popup.Value = materialsList{1};
                end
            end

            % set default output filename
            [filePath, fileName] = fileparts(obj.mibModel.I{id}.image.filename);
            outputFilename = fullfile(filePath, [fileName '_analysis.xls']);
            obj.view.handles.filenameEdit.Value = outputFilename;
            obj.view.handles.filenameEdit.Tooltip = outputFilename;
        end

        function exportMatlabCheck_Callback(obj)
            if obj.view.handles.exportMatlabCheck.Value
                answer = utils.dlgs.inputUniversalDlg(obj.view.gui, '', ...
                    {sprintf('Please define output variable\n(do not use spaces or special characters):')}, ...
                    {obj.matlabExportVariable}, 'Export variable');
                if ~isempty(answer)
                    obj.matlabExportVariable = answer{1};
                else
                    obj.view.handles.exportMatlabCheck.Value = false;
                end
            end
        end

        function savetoExcel_Callback(obj)
            if obj.view.handles.savetoExcel.Value
                obj.view.handles.filenameEdit.Enable = 'on';
                obj.view.handles.selectFilenameBtn.Enable = 'on';
            else
                obj.view.handles.filenameEdit.Enable = 'off';
                obj.view.handles.selectFilenameBtn.Enable = 'off';
            end
        end

        function selectFilenameBtn_Callback(obj)
            formatText = {'*.xls', 'Microsoft Excel (*.xls)'};
            currentFilename = obj.view.handles.filenameEdit.Value;
            [fileName, pathName] = uiputfile(formatText, 'Select filename', currentFilename);
            if isequal(fileName, 0) || isequal(pathName, 0); return; end
            outputFilename = fullfile(pathName, fileName);
            obj.view.handles.filenameEdit.Value = outputFilename;
            obj.view.handles.filenameEdit.Tooltip = outputFilename;
        end

        function backgroundCheck_Callback(obj)
            if obj.view.handles.backgroundCheck.Value
                obj.view.handles.backgroundPopup.Enable = 'on';
                obj.view.handles.subtractBackgroundCheck.Enable = 'on';
                obj.view.handles.additionalThresholdingCheck.Enable = 'on';
            else
                obj.view.handles.backgroundPopup.Enable = 'off';
                obj.view.handles.subtractBackgroundCheck.Enable = 'off';
                obj.view.handles.additionalThresholdingCheck.Enable = 'off';
                obj.view.handles.additionalThresholdingCheck.Value = false;
            end
            obj.additionalThresholdingCheck_Callback();
        end

        function additionalThresholdingCheck_Callback(obj)
            if obj.view.handles.additionalThresholdingCheck.Value
                obj.view.handles.thresholdingPopup.Enable = 'on';
                obj.view.handles.thresholdEdit.Enable = 'on';
            else
                obj.view.handles.thresholdingPopup.Enable = 'off';
                obj.view.handles.thresholdEdit.Enable = 'off';
            end
        end

        function helpBtn_Callback(obj)
            helpFilPath = fullfile(fileparts(obj.mibModel.mibPath), 'docs', 'html', 'user-interface', 'plugins', 'intensity-analysis', 'triple-area-intensity.html');
            utils.openHelpPage(helpFilPath, ...
                'http://mib.helsinki.fi/help/main3/user-interface/plugins/intensity-analysis/triple-area-intensity.html');
        end

        function continueBtn_Callback(obj)
            id = obj.mibModel.getActiveId();

            if obj.mibModel.I{id}.modelExist == 0
                utils.dlgs.showErrorDialog(obj.view.gui, 'This plugin requires a model to be present!', 'Model was not detected');
                return;
            end

            outputFilename = obj.view.handles.filenameEdit.Value;
            if obj.view.handles.savetoExcel.Value
                if exist(outputFilename, 'file') == 2
                    strText = sprintf('!!! Warning !!!\n\nThe file:\n%s \nalready exists!\n\nOverwrite?', outputFilename);
                    button = utils.dlgs.inputQuestDlg(obj.view.gui, strText, 'File exists!', 'Overwrite', 'Cancel', 'Cancel');
                    if strcmp(button, 'Cancel'); return; end
                    delete(outputFilename);
                end
            end

            connectionsCheck = obj.view.handles.connectionsCheck.Value;
            if connectionsCheck
                obj.mibModel.clearMask('4D, Dataset');
            end

            parameterToCalculate = obj.view.handles.parameterCombo.Value;

            colorChannelItems = obj.view.handles.colorChannelCombo.Items;
            colorChannel = find(strcmp(colorChannelItems, obj.view.handles.colorChannelCombo.Value));

            materialsList = obj.mibModel.I{id}.labels.materialNames;
            material1_Index = find(strcmp(obj.view.handles.material1Popup.Items, obj.view.handles.material1Popup.Value));
            material2_Index = find(strcmp(obj.view.handles.material2Popup.Items, obj.view.handles.material2Popup.Value));
            backgroundCheck = obj.view.handles.backgroundCheck.Value;
            background_Index = find(strcmp(obj.view.handles.backgroundPopup.Items, obj.view.handles.backgroundPopup.Value));
            subtractBackgroundCheck = obj.view.handles.subtractBackgroundCheck.Value;
            calculateRatioCheck = obj.view.handles.calculateRatioCheck.Value;
            additionalThresholdingCheck = obj.view.handles.additionalThresholdingCheck.Value;

            if additionalThresholdingCheck
                addMaterial_Index = find(strcmp(obj.view.handles.thresholdingPopup.Items, obj.view.handles.thresholdingPopup.Value));
                addMaterial_Shift = obj.view.handles.thresholdEdit.Value;
                obj.mibModel.clearMask();
                obj.mibModel.I{id}.maskExist = true;
                if addMaterial_Index ~= material1_Index && addMaterial_Index ~= material2_Index
                    utils.dlgs.showErrorDialog(obj.view.gui, 'Material for additional thresholding should be Material 1 or Material 2!', 'Wrong material!');
                    return;
                end
            end

            % initialise results structure
            TripleArea = struct();
            TripleArea.Filename = {};
            TripleArea.SliceNumber = [];
            TripleArea.Intensity1 = [];
            TripleArea.Intensity2 = [];
            TripleArea.IntensityBg = [];
            TripleArea.IntensityA = [];
            TripleArea.Ratio = [];

            progressBar = uiprogressdlg(obj.view.gui, 'Value', 0, 'Message', 'Please wait...', 'Title', 'Triple Area Intensity...');
            obj.mibModel.backup('selection', 1);
            obj.mibModel.I{id}.annotations.clearContents();

            warning('off', 'MATLAB:xlswrite:AddSheet');
            s = {'TripleAreaIntensity: triple material intensity analysis and ratio calculation'};
            s(2,1) = {'Image directory:'};
            s(2,2) = {fileparts(obj.mibModel.I{id}.image.filename)};
            s(3,1) = {['Calculating: ' parameterToCalculate]};
            s(3,4) = {['Color channel: ' num2str(colorChannel)]};

            TripleArea.info = 'TripleAreaIntensity: triple material intensity analysis and ratio calculation';
            TripleArea.imgDir = fileparts(obj.mibModel.I{id}.image.filename);
            TripleArea.calcPar = parameterToCalculate;
            TripleArea.colChannel = colorChannel;
            TripleArea.subtractedBg = subtractBackgroundCheck;
            TripleArea.RatioInfo = [materialsList{material1_Index} '/' materialsList{material2_Index}];

            if backgroundCheck
                s(4,4) = {['Background material: ' materialsList{background_Index}]};
                TripleArea.BackgroundMaterial = materialsList{background_Index};
            end

            s(6,1) = {'Filename'};
            s(6,2) = {'Slice Number'};
            if subtractBackgroundCheck
                s(6,3) = cellstr([materialsList{material1_Index} '-minus-Bg']);
                s(6,4) = cellstr([materialsList{material2_Index} '-minus-Bg']);
                TripleArea.MaterialName1 = [materialsList{material1_Index} '_minus_Bg'];
                TripleArea.MaterialName2 = [materialsList{material2_Index} '_minus_Bg'];
            else
                s(6,3) = materialsList(material1_Index);
                s(6,4) = materialsList(material2_Index);
                TripleArea.MaterialName1 = materialsList{material1_Index};
                TripleArea.MaterialName2 = materialsList{material2_Index};
            end
            s(6,5) = cellstr('Bg');
            s(7,5) = cellstr('(background)');
            s(6,6) = {'Ratio'};
            s(7,6) = {[materialsList{material1_Index} '/' materialsList{material2_Index}]};
            if additionalThresholdingCheck
                TripleArea.additionalThresholdingValue = addMaterial_Shift;
                s(4,8) = {['Intensity shift for thresholding: ' num2str(addMaterial_Shift)]};
                s(6,7) = {'Intensity of thresholded'};
                if subtractBackgroundCheck
                    s(7,7) = {[materialsList{addMaterial_Index} '-minus-Bg']};
                    TripleArea.MaterialNameAdditionallyThresholded = [materialsList{addMaterial_Index} '-minus-Bg'];
                else
                    s(7,7) = materialsList(addMaterial_Index);
                    TripleArea.MaterialNameAdditionallyThresholded = materialsList(addMaterial_Index);
                end
            end

            options.blockModeSwitch = 0;
            imageData = cell2mat(obj.mibModel.getData3D('image', [], 3, colorChannel, options));
            model1 = cell2mat(obj.mibModel.getData3D('labels', [], 3, material1_Index, options));
            model2 = cell2mat(obj.mibModel.getData3D('labels', [], 3, material2_Index, options));
            if backgroundCheck
                backgroundData = cell2mat(obj.mibModel.getData3D('labels', [], 3, background_Index, options));
            else
                backgroundData = NaN;
            end

            if connectionsCheck
                selectionData = zeros(size(model1), class(model1));
            end

            if ~isempty(obj.mibModel.I{id}.image.sliceName)
                inputFilenames = obj.mibModel.I{id}.image.sliceName;
                if numel(inputFilenames) < size(imageData, 3)
                    inputFilenames = repmat(inputFilenames(1), [size(imageData,3), 1]);
                end
            else
                [~, baseName, ext] = fileparts(obj.mibModel.I{id}.image.filename);
                inputFilenames = [baseName ext];
            end

            rowId = 8;
            ratioValues = [];

            for sliceId = 1:size(model1, 3)
                progressBar.Value = sliceId / size(model1, 3);
                CC1 = bwconncomp(model1(:,:,sliceId), 8);
                if CC1.NumObjects == 0; continue; end
                STATS1 = regionprops(CC1, 'Centroid', 'PixelIdxList');
                CC2 = bwconncomp(model2(:,:,sliceId), 8);
                STATS2 = regionprops(CC2, 'Centroid', 'PixelIdxList');
                if CC1.NumObjects ~= CC2.NumObjects; continue; end

                BG_CC.NumObjects = 0;
                BG_STATS = [];
                if backgroundCheck
                    BG_CC = bwconncomp(backgroundData(:,:,sliceId), 8);
                    BG_STATS = regionprops(BG_CC, 'Centroid', 'PixelIdxList');
                end

                X1 = zeros([numel(STATS1) 2]);
                X2 = zeros([numel(STATS2) 2]);
                for i = 1:numel(STATS1)
                    X1(i,:) = STATS1(i).Centroid;
                    X2(i,:) = STATS2(i).Centroid;
                end
                idx = mibFindMatchingPairs(X1, X2);

                bg_idx = [];
                if backgroundCheck == 1
                    X3 = zeros([numel(BG_STATS) 2]);
                    for i = 1:numel(BG_STATS)
                        X3(i,:) = BG_STATS(i).Centroid;
                    end
                    if CC1.NumObjects == BG_CC.NumObjects
                        bg_idx = mibFindMatchingPairs(X1, X3);
                    end
                end

                Intensity1 = zeros([numel(STATS1), 1]);
                Intensity2 = zeros([numel(STATS2), 1]);
                Background = zeros([numel(BG_STATS), 1]);
                if additionalThresholdingCheck
                    if addMaterial_Index == material1_Index
                        IntensityA = zeros([numel(STATS1), 1]);
                        AD_STATS = STATS1;
                    else
                        IntensityA = zeros([numel(STATS2), 1]);
                        AD_STATS = STATS2;
                    end
                    mask = zeros(size(model1, 1), size(model1, 2), 'uint8');
                end
                slice = imageData(:,:,sliceId);

                % average background when object counts differ
                if backgroundCheck == 1 && CC1.NumObjects ~= BG_CC.NumObjects
                    intensityVector = [];
                    for bgId = 1:numel(BG_STATS)
                        intensityVector = [intensityVector; slice(BG_STATS(bgId).PixelIdxList)]; %#ok<AGROW>
                    end
                    switch parameterToCalculate
                        case 'Mean intensity'; Background = mean(intensityVector);
                        case 'Min intensity';  Background = min(intensityVector);
                        case 'Max intensity';  Background = max(intensityVector);
                        case 'Sum intensity';  Background = sum(intensityVector);
                    end
                end

                for objId = 1:numel(STATS1)
                    pnts(1,:) = STATS1(objId).Centroid;
                    pnts(2,:) = STATS2(idx(objId)).Centroid;
                    if connectionsCheck
                        selectionData(:,:,sliceId) = mibConnectPoints(selectionData(:,:,sliceId), pnts);
                        if numel(bg_idx) > 0
                            pnts2(1,:) = STATS1(objId).Centroid;
                            pnts2(2,:) = BG_STATS(bg_idx(objId)).Centroid;
                            selectionData(:,:,sliceId) = mibConnectPoints(selectionData(:,:,sliceId), pnts2);
                        end
                    end

                    switch parameterToCalculate
                        case 'Mean intensity'
                            Intensity1(objId) = mean(slice(STATS1(objId).PixelIdxList));
                            Intensity2(objId) = mean(slice(STATS2(idx(objId)).PixelIdxList));
                            if backgroundCheck == 1 && CC1.NumObjects == BG_CC.NumObjects
                                Background(objId) = mean(slice(BG_STATS(bg_idx(objId)).PixelIdxList));
                            end
                            if additionalThresholdingCheck
                                threshIndices = find(slice(AD_STATS(objId).PixelIdxList) > (Background(min([numel(Background) objId])) + addMaterial_Shift));                                pixelList = AD_STATS(objId).PixelIdxList(threshIndices);
                                mask(pixelList) = 1;
                                IntensityA(objId) = mean(slice(pixelList));
                            end
                        case 'Min intensity'
                            Intensity1(objId) = min(slice(STATS1(objId).PixelIdxList));
                            Intensity2(objId) = min(slice(STATS2(idx(objId)).PixelIdxList));
                            if backgroundCheck == 1 && CC1.NumObjects == BG_CC.NumObjects
                                Background(objId) = min(slice(BG_STATS(bg_idx(objId)).PixelIdxList));
                            end
                            if additionalThresholdingCheck
                                threshIndices = find(slice(AD_STATS(objId).PixelIdxList) > (Background(min([numel(Background) objId])) + addMaterial_Shift));                                pixelList = AD_STATS(objId).PixelIdxList(threshIndices);
                                mask(pixelList) = 1;
                                IntensityA(objId) = min(slice(pixelList));
                            end
                        case 'Max intensity'
                            Intensity1(objId) = max(slice(STATS1(objId).PixelIdxList));
                            Intensity2(objId) = max(slice(STATS2(idx(objId)).PixelIdxList));
                            if backgroundCheck == 1 && CC1.NumObjects == BG_CC.NumObjects
                                Background(objId) = max(slice(BG_STATS(bg_idx(objId)).PixelIdxList));
                            end
                            if additionalThresholdingCheck
                                threshIndices = find(slice(AD_STATS(objId).PixelIdxList) > (Background(min([numel(Background) objId])) + addMaterial_Shift));                                pixelList = AD_STATS(objId).PixelIdxList(threshIndices);
                                mask(pixelList) = 1;
                                IntensityA(objId) = max(slice(pixelList));
                            end
                        case 'Sum intensity'
                            Intensity1(objId) = sum(slice(STATS1(objId).PixelIdxList));
                            Intensity2(objId) = sum(slice(STATS2(idx(objId)).PixelIdxList));
                            if backgroundCheck == 1 && CC1.NumObjects == BG_CC.NumObjects
                                Background(objId) = sum(slice(BG_STATS(bg_idx(objId)).PixelIdxList));
                            end
                            if additionalThresholdingCheck
                                threshIndices = find(slice(AD_STATS(objId).PixelIdxList) > (Background(min([numel(Background) objId])) + addMaterial_Shift));                                pixelList = AD_STATS(objId).PixelIdxList(threshIndices);
                                mask(pixelList) = 1;
                                IntensityA(objId) = sum(slice(pixelList));
                            end
                    end

                    if subtractBackgroundCheck == 1 && backgroundCheck == 1
                        bgVal = Background(min([numel(Background) objId]));
                        Intensity1(objId) = Intensity1(objId) - bgVal;
                        Intensity2(objId) = Intensity2(objId) - bgVal;
                        if additionalThresholdingCheck
                            IntensityA(objId) = IntensityA(objId) - bgVal;
                        end
                    end

                    if iscell(inputFilenames)
                        s(rowId, 1) = inputFilenames(sliceId);
                    else
                        s(rowId, 1) = {inputFilenames};
                    end
                    s(rowId, 2) = {sliceId};
                    s(rowId, 3) = {Intensity1(objId)};
                    s(rowId, 4) = {Intensity2(objId)};
                    if backgroundCheck
                        if CC1.NumObjects == BG_CC.NumObjects
                            s(rowId, 5) = {Background(objId)};
                        elseif objId == 1
                            s(rowId, 5) = {Background(1)};
                        end
                    end
                    if calculateRatioCheck
                        s(rowId, 6) = {Intensity1(objId) / Intensity2(objId)};
                    end
                    if additionalThresholdingCheck
                        s(rowId, 7) = {IntensityA(objId)};
                    end

                    obj.mibModel.I{id}.annotations.addLabels({TripleArea.MaterialName1}, [sliceId, round(X1(objId,:)), 1], Intensity1(objId));
                    obj.mibModel.I{id}.annotations.addLabels({TripleArea.MaterialName2}, [sliceId, round(X2(idx(objId),:)), 1], Intensity2(objId));

                    if backgroundCheck == 1 && CC1.NumObjects == BG_CC.NumObjects
                        obj.mibModel.I{id}.annotations.addLabels({TripleArea.BackgroundMaterial}, [sliceId, round(X3(bg_idx(objId),:)), 1], Background(objId));
                    end
                    if additionalThresholdingCheck
                        try
                            if addMaterial_Index == material1_Index
                                annotCoords = round(X1(objId,:));
                            else
                                annotCoords = round(X2(idx(objId),:));
                            end
                            annotCoords(2) = annotCoords(2) + 18;
                            obj.mibModel.I{id}.annotations.addLabels({'thres:'}, [sliceId, annotCoords, 1], IntensityA(objId));
                        catch
                        end
                    end

                    rowId = rowId + 1;
                end

                if backgroundCheck == 1 && CC1.NumObjects ~= BG_CC.NumObjects
                    for bgId = 1:numel(BG_STATS)
                        obj.mibModel.I{id}.annotations.addLabels({TripleArea.BackgroundMaterial}, [sliceId, round(X3(bgId,:)), 1], Background(min([numel(Background) bgId])));
                    end
                end

                if calculateRatioCheck
                    ratioValues = [ratioValues; Intensity1./Intensity2]; %#ok<AGROW>
                end

                if additionalThresholdingCheck
                    obj.mibModel.setData2D(mask, 'mask', sliceId, [], [], options);
                end

                if obj.view.handles.exportMatlabCheck.Value
                    TripleArea.Filename = [TripleArea.Filename; repmat(s(rowId-1, 1), [numel(STATS1), 1])];
                    TripleArea.SliceNumber = [TripleArea.SliceNumber; repmat(sliceId, [numel(STATS1), 1])];
                    TripleArea.Intensity1 = [TripleArea.Intensity1; Intensity1];
                    TripleArea.Intensity2 = [TripleArea.Intensity2; Intensity2];
                    if additionalThresholdingCheck
                        TripleArea.IntensityA = [TripleArea.IntensityA; IntensityA];
                    end
                    if numel(Background) == numel(STATS1)
                        TripleArea.IntensityBg = [TripleArea.IntensityBg; Background];
                    else
                        TripleArea.IntensityBg = [TripleArea.IntensityBg; repmat(Background, [numel(STATS1), 1])];
                    end
                    if calculateRatioCheck
                        TripleArea.Ratio = [TripleArea.Ratio; Intensity1./Intensity2];
                    end
                end
            end

            if connectionsCheck
                obj.mibModel.setData3D(selectionData, 'mask', [], 3, [], options);
            end

            if obj.view.handles.savetoExcel.Value
                progressBar.Message = 'Generating Excel file...';
                progressBar.Value = 0.99;
                xlswrite2(outputFilename, s, 'Sheet1', 'A1');
            end

            if obj.view.handles.exportMatlabCheck.Value
                progressBar.Message = 'Exporting to Matlab...';
                progressBar.Value = 1;
                fprintf('TripleAreaIntensity: a structure with results "%s" was created\n', obj.matlabExportVariable);
                assignin('base', obj.matlabExportVariable, TripleArea);
            end

            obj.mibModel.showAnnotations = true;
            obj.mibModel.showMask = true;
            notify(obj.mibModel, 'ShowImage');

            delete(progressBar);

            if calculateRatioCheck && ~isempty(ratioValues)
                figure(321);
                histogram(ratioValues, ceil(numel(ratioValues)/2));
                title(sprintf('Ratio (%s/%s) calculated from %s, N=%d', ...
                    materialsList{material1_Index}, materialsList{material2_Index}, ...
                    parameterToCalculate, numel(ratioValues)), 'FontSize', 14);
                xlabel(sprintf('Ratio (%s/%s)', materialsList{material1_Index}, materialsList{material2_Index}), 'FontSize', 12);
                ylabel('Number of cells', 'FontSize', 12);
                grid;
            end
        end
    end
end
