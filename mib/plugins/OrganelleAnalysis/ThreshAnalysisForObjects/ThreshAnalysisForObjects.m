classdef ThreshAnalysisForObjects < handle
% ThreshAnalysisForObjects < handle
% Plugin controller for threshold-based analysis of segmentation objects.
% Each object of the selected material is intensity-thresholded and the
% thresholded area is compared with the original object area.
%
% @code
%   controller = plugins.OrganelleAnalysis.ThreshAnalysisForObjects.ThreshAnalysisForObjects(mibModel);
% @endcode

    properties
        mibModel
        % handle to MibModel
        view
        % handle to the AppDesigner view (core.ChildView wrapper)
        listener
        % cell array of event listeners
        Results
        % struct array with per-object analysis results
        saveGraphFormats
        % cell array of formats for saving the triangulation graph
        % ('lines3d', 'amira-binary', 'excel')
        matlabVarName
        % variable name used when exporting results to the MATLAB workspace
    end

    events
        CloseEvent
    end

    methods (Static)

        function ViewListner_Callback2(obj, ~, evnt)
        % ViewListner_Callback2  React to MibModel events.
            if ~isvalid(obj) || isempty(obj.view) || ~isvalid(obj.view.gui)
                for i = 1:numel(obj.listener); delete(obj.listener{i}); end
                return;
            end
            switch evnt.EventName
                case {'UpdateGuiWidgets', 'NewDataset'}
                    obj.updateWidgets();
            end
        end

    end  % methods (Static)

    methods

        % -----------------------------------------------------------------
        function obj = ThreshAnalysisForObjects(mibModel)
        % ThreshAnalysisForObjects  Constructor - initialises controller and GUI.
        %
        % Parameters:
        % mibModel: handle to the MibModel instance

            obj.mibModel = mibModel;
            id = obj.mibModel.getActiveId();

            % check for virtual stacking mode - not supported
            if isprop(obj.mibModel.I{id}, 'Virtual') && obj.mibModel.I{id}.Virtual.virtual == 1
                dlgOpt.MsgBoxOnly = true;
                dlgOpt.Icon = 'puffin_warning';
                utils.dlgs.inputUniversalDlg(obj.mibModel.mibGUI, '', ...
                    {''}, {'This plugin is not compatible with the virtual stacking mode!\nPlease switch to the memory-resident mode and try again'}, ...
                    'Not implemented', dlgOpt);
                notify(obj, 'CloseEvent');
                return;
            end

            obj.Results = struct();
            obj.saveGraphFormats = {};
            obj.matlabVarName = 'ThreshAnalysis';

            obj.view = core.ChildView(obj, 'ThreshAnalysisForObjectsGUI');
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
            if obj.view.handles.objectPopup.FontSize ~= Font.FontSize ...
                    || ~strcmp(obj.view.handles.objectPopup.FontName, Font.FontName)
                utils.fontSizeUpdate(obj.view.gui, Font);
            end

            % warn if model is missing
            materialsList = obj.mibModel.I{id}.labels.materialNames;
            if obj.mibModel.I{id}.modelExist == 0 || numel(materialsList) < 1
                utils.dlgs.showErrorDialog(obj.view.gui, ...
                    sprintf('A model with at least one material is needed to proceed further!\n\nPlease create a new model, add a material containing the objects that should be analysed, then try again.'), ...
                    'Missing the model');
            end

            obj.updateWidgets();
            obj.generateOutputFilename();

            obj.listener{1} = addlistener(mibModel, 'UpdateGuiWidgets', @(s,e) obj.ViewListner_Callback2(obj, s, e));
            obj.listener{2} = addlistener(mibModel, 'NewDataset',       @(s,e) obj.ViewListner_Callback2(obj, s, e));

            obj.view.gui.Visible = true;
        end

        % -----------------------------------------------------------------
        function addCallbacks(obj)
        % addCallbacks  Wire all widget callbacks and assign tooltips.
            obj.view.gui.CloseRequestFcn = @(~,~) obj.closeWindow();
            handles = obj.view.handles;

            handles.closeBtn.ButtonPushedFcn              = @(~,~) obj.closeWindow();
            handles.startBtn.ButtonPushedFcn              = @(~,~) obj.startBtn_Callback();
            handles.helpBtn.ButtonPushedFcn               = @(~,~) obj.helpBtn_Callback();
            handles.regenerateOutputPath.ButtonPushedFcn  = @(~,~) obj.generateOutputFilename();
            handles.selectFilenameBtn.ButtonPushedFcn     = @(~,~) obj.selectFilenameBtn_Callback();
            handles.thresholdPolicyPopup.ValueChangedFcn  = @(~,~) obj.thresholdPolicyPopup_Callback();
            handles.triangulateCentroidsCheck.ValueChangedFcn = @(~,~) obj.triangulateCentroidsCheck_Callback();
            handles.saveTriangulation.ValueChangedFcn     = @(~,~) obj.saveTriangulation_Callback();
            handles.minDiameterCheck.ValueChangedFcn      = @(~,~) obj.minDiameterCheck_Callback();
            handles.makePlotCheck.ValueChangedFcn         = @(~,~) obj.makePlotCheck_Callback();
            handles.exportMatlabCheck.ValueChangedFcn     = @(~,~) obj.exportMatlabCheck_Callback();
            handles.exportExcelCheck.ValueChangedFcn      = @(~,~) obj.exportFileCheck_Callback();
            handles.exportMatlabFileCheck.ValueChangedFcn = @(~,~) obj.exportFileCheck_Callback();

            % tooltips
            handles.startBtn.Tooltip               = 'Run threshold analysis on selected material objects';
            handles.closeBtn.Tooltip               = 'Close this window';
            handles.helpBtn.Tooltip                = 'Open documentation in the browser';
            handles.objectIndices.Tooltip          = 'Enter material indices separated by commas; if empty, uses the popup selection';
            handles.objectPopup.Tooltip            = 'Select the material containing the objects to analyse';
            handles.imageColChPopup.Tooltip        = 'Select color channel used for intensity measurements';
            handles.highlightMinDiamterCheck.Tooltip = 'Mark minimum diameter positions in the selection layer';
            handles.triangulateCentroidsCheck.Tooltip = 'Compute Delaunay triangulation of object centroids per slice';
            handles.removeFreeBoundaryCheck.Tooltip = 'Remove boundary edges from the triangulation result';
            handles.thresholdPolicyPopup.Tooltip   = 'Absolute: use a fixed threshold; Relative: compute threshold per object (Otsu or Median)';
            handles.relativeThresholdMethodPopup.Tooltip = 'Method for computing the relative threshold value for each object';
            handles.thresholdValueText.Tooltip     = 'Label indicating whether the value below is an absolute threshold or a relative offset';
            handles.thresholdEdit.Tooltip          = 'Absolute pixel intensity threshold; pixels above this value count as thresholded area';
            handles.thresholdOffsetEdit.Tooltip    = 'Offset added to the per-object relative threshold (Otsu or Median intensity)';
            handles.erodeDilateCheck.Tooltip       = 'Apply erosion then dilation with a 3×3 strel to remove small noise from the thresholded area';
            handles.connectivityPopup.Tooltip      = '4-connected or 8-connected neighbourhood for object detection';
            handles.exportMatlabCheck.Tooltip      = 'Export results to the MATLAB base workspace as ''ThreshAnalysis''';
            handles.exportExcelCheck.Tooltip       = 'Save results to an Excel (.xls) file';
            handles.exportMatlabFileCheck.Tooltip  = 'Save results as a MATLAB (.mat) file alongside the dataset';
            handles.filenameEdit.Tooltip           = 'Output file path for Excel and MATLAB exports';
            handles.selectFilenameBtn.Tooltip      = 'Browse to choose the output filename';
            handles.regenerateOutputPath.Tooltip   = 'Auto-generate the output filename from the dataset path';
            handles.saveTriangulation.Tooltip      = 'Save triangulation graph to file (format configured when checked)';
            handles.minDiameterCheck.Tooltip       = 'Compute the minimum inscribed sphere diameter for each object';
            handles.makePlotCheck.Tooltip          = 'Generate violin plots of the results in a MATLAB figure';
            handles.figureId.Tooltip               = 'Figure number used for the result violin plots';
            handles.autoPrintCheck.Tooltip         = 'Automatically send the figure to the printer after calculation';
        end

        % -----------------------------------------------------------------
        function closeWindow(obj)
        % closeWindow  Delete GUI, remove listeners, fire CloseEvent.
            if isvalid(obj.view.gui); delete(obj.view.gui); end
            for i = 1:numel(obj.listener); delete(obj.listener{i}); end
            notify(obj, 'CloseEvent');
        end

        % -----------------------------------------------------------------
        function updateWidgets(obj)
        % updateWidgets  Refresh material list and color-channel dropdown.
            id = obj.mibModel.getActiveId();
            materialList = obj.mibModel.I{id}.labels.materialNames;
            if obj.mibModel.I{id}.modelExist == 0 || numel(materialList) < 1
                obj.view.handles.startBtn.Enable = 'off';
            else
                obj.view.handles.startBtn.Enable = 'on';
                obj.view.handles.objectPopup.Items = materialList;
                obj.view.handles.objectPopup.Value = materialList{1};
            end

            numColors = obj.mibModel.I{id}.image.colors;
            colorItems = cell(numColors, 1);
            for i = 1:numColors
                colorItems{i} = sprintf('Ch %d', i);
            end
            obj.view.handles.imageColChPopup.Items = colorItems;
            selectedIdx = max(obj.mibModel.I{id}.selectedColorChannel, 1);
            if selectedIdx <= numColors
                obj.view.handles.imageColChPopup.Value = colorItems{selectedIdx};
            else
                obj.view.handles.imageColChPopup.Value = colorItems{1};
            end
        end

        % -----------------------------------------------------------------
        function generateOutputFilename(obj)
        % generateOutputFilename  Build default output path from dataset filename.
            id = obj.mibModel.getActiveId();
            [imagePath, imageFilename] = fileparts(obj.mibModel.I{id}.image.filename);
            outputFilename = fullfile(imagePath, [imageFilename '_ThresAnalysis.xls']);
            obj.view.handles.filenameEdit.Value   = outputFilename;
            obj.view.handles.filenameEdit.Tooltip = outputFilename;
        end

        % -----------------------------------------------------------------
        function defineTriangulationOutputFormat(obj)
        % defineTriangulationOutputFormat  Ask which graph formats to save.
            [answer, ~] = utils.dlgs.inputUniversalDlg(obj.view.gui, ...
                'Specify the output formats to save triangulation results', ...
                {'MIB format (recommended)', 'Amira binary', 'Excel sheet'}, ...
                {true, false, false}, 'Save triangulation', struct('LabelPosition', 'left', 'WindowHeight', 180));
            if isempty(answer); return; end
            obj.saveGraphFormats = {};
            if answer{1} == 1; obj.saveGraphFormats = [obj.saveGraphFormats, {'lines3d'}];       end
            if answer{2} == 1; obj.saveGraphFormats = [obj.saveGraphFormats, {'amira-binary'}];  end
            if answer{3} == 1; obj.saveGraphFormats = [obj.saveGraphFormats, {'excel'}];         end
        end

        % -----------------------------------------------------------------
        function thresholdPolicyPopup_Callback(obj)
        % thresholdPolicyPopup_Callback  Toggle controls based on Absolute/Relative policy.
            if strcmp(obj.view.handles.thresholdPolicyPopup.Value, 'Absolute')
                obj.view.handles.relativeThresholdMethodPopup.Enable = 'off';
                obj.view.handles.thresholdValueText.Text = 'Threshold value:';
                obj.view.handles.thresholdOffsetEdit.Enable = 'off';
                obj.view.handles.thresholdEdit.Enable = 'on';
            else
                obj.view.handles.relativeThresholdMethodPopup.Enable = 'on';
                obj.view.handles.thresholdValueText.Text = 'Offset value:';
                obj.view.handles.thresholdOffsetEdit.Enable = 'on';
                obj.view.handles.thresholdEdit.Enable = 'off';
            end
        end

        % -----------------------------------------------------------------
        function triangulateCentroidsCheck_Callback(obj)
        % triangulateCentroidsCheck_Callback  Enable/disable triangulation-related controls.
            if obj.view.handles.triangulateCentroidsCheck.Value
                obj.view.handles.removeFreeBoundaryCheck.Enable = 'on';
                obj.view.handles.saveTriangulation.Enable       = 'on';
            else
                obj.view.handles.removeFreeBoundaryCheck.Enable = 'off';
                obj.view.handles.saveTriangulation.Enable       = 'off';
                obj.view.handles.saveTriangulation.Value        = false;
            end
        end

        % -----------------------------------------------------------------
        function saveTriangulation_Callback(obj)
        % saveTriangulation_Callback  When checked, ask for format and enable filename controls.
            if obj.view.handles.saveTriangulation.Value
                obj.defineTriangulationOutputFormat();
                obj.view.handles.filenameEdit.Enable    = 'on';
                obj.view.handles.selectFilenameBtn.Enable = 'on';
            else
                if obj.view.handles.exportExcelCheck.Value + obj.view.handles.exportMatlabFileCheck.Value == 0
                    obj.view.handles.filenameEdit.Enable    = 'off';
                    obj.view.handles.selectFilenameBtn.Enable = 'off';
                end
            end
        end

        % -----------------------------------------------------------------
        function minDiameterCheck_Callback(obj)
        % minDiameterCheck_Callback  Enable/disable min-diameter highlight option.
            if obj.view.handles.minDiameterCheck.Value
                obj.view.handles.highlightMinDiamterCheck.Enable = 'on';
            else
                obj.view.handles.highlightMinDiamterCheck.Enable = 'off';
                obj.view.handles.highlightMinDiamterCheck.Value  = false;
            end
        end

        % -----------------------------------------------------------------
        function makePlotCheck_Callback(obj)
        % makePlotCheck_Callback  Enable/disable figure-ID field.
            if obj.view.handles.makePlotCheck.Value
                obj.view.handles.figureId.Enable = 'on';
            else
                obj.view.handles.figureId.Enable = 'off';
            end
        end

        % -----------------------------------------------------------------
        function exportMatlabCheck_Callback(obj)
        % exportMatlabCheck_Callback  When checked, ask for the workspace variable name.
            if ~obj.view.handles.exportMatlabCheck.Value; return; end
            [answer, ~] = utils.dlgs.inputUniversalDlg(obj.view.gui, ...
                '', {'Variable name:'}, {obj.matlabVarName}, 'Export to MATLAB workspace');
            if isempty(answer)
                obj.view.handles.exportMatlabCheck.Value = false;
                return;
            end
            if ~isempty(strtrim(answer{1}))
                obj.matlabVarName = strtrim(answer{1});
            end
        end

        % -----------------------------------------------------------------
        function exportFileCheck_Callback(obj)
        % exportFileCheck_Callback  Enable/disable filename controls when any export is active.
            if obj.view.handles.exportExcelCheck.Value + obj.view.handles.exportMatlabFileCheck.Value > 0
                obj.view.handles.filenameEdit.Enable    = 'on';
                obj.view.handles.selectFilenameBtn.Enable = 'on';
            else
                if ~obj.view.handles.saveTriangulation.Value
                    obj.view.handles.filenameEdit.Enable    = 'off';
                    obj.view.handles.selectFilenameBtn.Enable = 'off';
                end
            end
        end

        % -----------------------------------------------------------------
        function selectFilenameBtn_Callback(obj)
        % selectFilenameBtn_Callback  Browse for output file path.
            formatText = {'*.xls', 'Microsoft Excel (*.xls)'; '*.mat', 'Matlab Format (*.mat)'};
            currentFilename = obj.view.handles.filenameEdit.Value;
            [fileName, pathName] = uiputfile(formatText, 'Select filename', currentFilename);
            if isequal(fileName, 0) || isequal(pathName, 0); return; end
            outputFilename = fullfile(pathName, fileName);
            obj.view.handles.filenameEdit.Value   = outputFilename;
            obj.view.handles.filenameEdit.Tooltip = outputFilename;
        end

        % -----------------------------------------------------------------
        function helpBtn_Callback(obj)
            % helpBtn_Callback  Open plugin documentation in the browser.
            helpFilPath = fullfile(fileparts(obj.mibModel.mibPath), 'docs', 'html', 'user-interface', 'plugins', 'organelle-analysis', 'thres-analysis-for-objects.html');
            utils.openHelpPage(helpFilPath, ...
                'http://mib.helsinki.fi/help/main3/user-interface/plugins/organelle-analysis/thres-analysis-for-objects.html');

        end

        % -----------------------------------------------------------------
        function startBtn_Callback(obj)
        % startBtn_Callback  Run threshold analysis and produce all requested outputs.
            id = obj.mibModel.getActiveId();

            minDiameterPositionsToSelection = obj.view.handles.highlightMinDiamterCheck.Value;
            triangulatePointsCheck = obj.view.handles.triangulateCentroidsCheck.Value;
            removeFreeBoundaryCheck = obj.view.handles.removeFreeBoundaryCheck.Value;

            getDataOptions.blockModeSwitch = 0;
            [height, width, depth, ~, time] = obj.mibModel.I{id}.getDatasetDimensions('image', 3, getDataOptions);

            % resolve material indices
            materialId = str2num(obj.view.handles.objectIndices.Value); %#ok<ST2NM>
            materialList = obj.view.handles.objectPopup.Items;
            if isempty(materialId)
                materialId = find(strcmp(materialList, obj.view.handles.objectPopup.Value));
            end
            materialNames = materialList(materialId);
            colCh = find(strcmp(obj.view.handles.imageColChPopup.Items, obj.view.handles.imageColChPopup.Value));

            exportMatlab    = obj.view.handles.exportMatlabCheck.Value;
            exportExcel     = obj.view.handles.exportExcelCheck.Value;
            exportMatlabFile = obj.view.handles.exportMatlabFileCheck.Value;

            matlabVarName = obj.matlabVarName;
            thresholdPolicy = obj.view.handles.thresholdPolicyPopup.Value;
            relativeThresholdMethod = obj.view.handles.relativeThresholdMethodPopup.Value;
            absoluteThresholdValue  = obj.view.handles.thresholdEdit.Value;
            thresholdOffsetValue    = obj.view.handles.thresholdOffsetEdit.Value;
            pixSize = obj.mibModel.I{id}.image.pixSize;
            erodeDilateCheck = obj.view.handles.erodeDilateCheck.Value;
            if strcmp(obj.view.handles.connectivityPopup.Value, '4')
                objConnectivity = 4;
            else
                objConnectivity = 8;
            end

            if strcmp(thresholdPolicy, 'Absolute')
                relativeThresholdMethod = '';
                thresholdOffsetValue    = [];
            else
                absoluteThresholdValue  = [];
            end

            % populate Results header fields
            obj.Results = struct();
            obj.Results(1).colCh                       = colCh;
            obj.Results(1).materialId                  = materialId;
            obj.Results(1).materialNames               = materialNames;
            obj.Results(1).absoluteThresholdValue      = absoluteThresholdValue;
            obj.Results(1).relativeThresholdMethod     = relativeThresholdMethod;
            obj.Results(1).thresholdOffsetValue        = thresholdOffsetValue;
            obj.Results(1).thresholdPolicy             = thresholdPolicy;
            obj.Results(1).ErodeDilate                 = erodeDilateCheck;
            obj.Results(1).pixSize                     = pixSize;

            imageMeta = obj.mibModel.I{id}.image.getMeta();
            obj.Results(1).datasetName                 = char(imageMeta('Filename'));
            obj.Results(1).modelName                   = obj.mibModel.I{id}.labels.filename;
            obj.Results(1).triangulatePoints           = logical(triangulatePointsCheck);
            obj.Results(1).triangulateRemoveFreeBoundary = logical(removeFreeBoundaryCheck);
            obj.Results(1).objConnectivity             = objConnectivity;

            if isKey(imageMeta, 'SliceName')
                SliceName = imageMeta('SliceName');
                if numel(SliceName) ~= depth
                    SliceName = repmat(SliceName, [depth, 1]);
                end
            else
                [~, datasetFn, datasetExt] = fileparts(char(imageMeta('Filename')));
                SliceName = repmat({[datasetFn, datasetExt]}, [depth, 1]);
            end

            % output filenames
            [pathStr, fileStr, ~] = fileparts(obj.view.handles.filenameEdit.Value);
            exportExcelFn  = fullfile(pathStr, [fileStr '.xls']);
            exportMatlabFn = fullfile(pathStr, [fileStr '.mat']);

            if exportExcel || exportMatlabFile
                if exist(exportExcelFn, 'file') == 2 || exist(exportMatlabFn, 'file') == 2
                    strText = sprintf('The file:\n%s\nalready exists!\n\nOverwrite?', exportExcelFn);
                    button = utils.dlgs.inputQuestDlg(obj.view.gui, strText, 'File exists!', 'Overwrite', 'Cancel', 'Cancel');
                    if strcmp(button, 'Cancel'); return; end
                    if exist(exportExcelFn,  'file') == 2; delete(exportExcelFn);  end
                    if exist(exportMatlabFn, 'file') == 2; delete(exportMatlabFn); end
                end
            end

            progressDialog = uiprogressdlg(obj.view.gui, ...
                'Title',     'Threshold Analysis for Objects', ...
                'Message',   'Calculating areas, please wait...', ...
                'Value',     0, ...
                'Cancelable', 'on');

            obj.mibModel.backup('mask', 1);

            mask = zeros([height, width, depth, time], 'uint8');
            obj.mibModel.I{id}.annotations.clearContents();
            if minDiameterPositionsToSelection
                obj.mibModel.I{id}.clearLayer('selection', '4D');
            end
            if obj.view.handles.minDiameterCheck.Value == 0
                minDiameterPositionsToSelection = 0;
            end

            annId = 1;
            getDataOptions.t = [1 1];

            for sliceId = 1:depth
                if progressDialog.CancelRequested; close(progressDialog); return; end
                progressDialog.Value   = (sliceId - 1) / depth;
                progressDialog.Message = sprintf('Calculating areas: slice %d / %d', sliceId, depth);

                currImg   = cell2mat(obj.mibModel.getData2D('image',  sliceId, 3, colCh, getDataOptions));
                currModel = cell2mat(obj.mibModel.getData2D('labels', sliceId, 3, NaN,   getDataOptions));
                maxIntValue = double(intmax(class(currImg)));

                for matId = 1:numel(materialId)
                    BW = zeros([height, width], 'uint8');
                    BW(currModel == materialId(matId)) = true;
                    if matId == 1
                        CC = bwconncomp(BW, objConnectivity);
                        CC.objMaterialName = repmat(materialNames(matId), [CC.NumObjects, 1]);
                    else
                        CC1 = bwconncomp(BW, objConnectivity);
                        CC.NumObjects    = CC.NumObjects + CC1.NumObjects;
                        CC.PixelIdxList  = [CC.PixelIdxList CC1.PixelIdxList];
                        CC.objMaterialName = [CC.objMaterialName; repmat(materialNames(matId), [CC1.NumObjects, 1])];
                    end
                end
                if CC.NumObjects == 0; continue; end

                currMask = mask(:,:,sliceId);

                STATS  = regionprops(CC, currImg, 'Centroid', 'Area', 'BoundingBox', 'Eccentricity');
                STATS2 = regionprops3mib(CC, 'FirstAxisLength', 'SecondAxisLength');
                [STATS.FirstAxisLength]  = STATS2.FirstAxisLength;
                [STATS.SecondAxisLength] = STATS2.SecondAxisLength;

                if strcmp(thresholdPolicy, 'Absolute')
                    objThresholdValues = zeros([CC.NumObjects, 1]) + absoluteThresholdValue;
                else
                    objThresholdValues = zeros([CC.NumObjects, 1]);
                end

                for objId = 1:CC.NumObjects
                    STATS(objId).objMaterialName = CC.objMaterialName{objId};

                    if strcmp(thresholdPolicy, 'Absolute')
                        pixelIndices = currImg(CC.PixelIdxList{objId}) > absoluteThresholdValue;
                    else
                        switch relativeThresholdMethod
                            case 'Otsu'
                                thresholdValue = graythresh(currImg(CC.PixelIdxList{objId})) * maxIntValue + thresholdOffsetValue;
                            case 'Median'
                                thresholdValue = median(currImg(CC.PixelIdxList{objId})) + thresholdOffsetValue;
                        end
                        pixelIndices = currImg(CC.PixelIdxList{objId}) > thresholdValue;
                        objThresholdValues(objId) = thresholdValue;
                    end
                    currMask(CC.PixelIdxList{objId}(pixelIndices)) = 1;
                end

                if erodeDilateCheck
                    strelElem = ones(3);
                    currMask = imerode(currMask, strelElem);
                    currMask = imdilate(currMask, strelElem);
                end

                if obj.view.handles.minDiameterCheck.Value == 1
                    L = labelmatrix(CC);
                    if minDiameterPositionsToSelection
                        selection = zeros([height, width], 'uint8');
                    end
                end

                for objId = 1:CC.NumObjects
                    obj.Results(annId).objId           = objId;
                    obj.Results(annId).sliceNo         = sliceId;
                    obj.Results(annId).objMaterialName = STATS(objId).objMaterialName;
                    obj.Results(annId).CentroidX       = STATS(objId).Centroid(1);
                    obj.Results(annId).CentroidY       = STATS(objId).Centroid(2);
                    obj.Results(annId).FirstAxisLength  = STATS(objId).FirstAxisLength  * pixSize.x;
                    obj.Results(annId).SecondAxisLength = STATS(objId).SecondAxisLength * pixSize.x;
                    obj.Results(annId).Eccentricity    = STATS(objId).Eccentricity;
                    obj.Results(annId).Median          = median(currImg(CC.PixelIdxList{objId}));
                    obj.Results(annId).TotalArea       = numel(CC.PixelIdxList{objId}) * pixSize.x * pixSize.y;
                    obj.Results(annId).SliceName       = SliceName{sliceId};

                    threshMask = currMask(CC.PixelIdxList{objId}) > 0;
                    obj.Results(annId).ThresholdedArea  = sum(threshMask) * pixSize.x * pixSize.y;
                    obj.Results(annId).objThresholdValues = objThresholdValues(objId);
                    obj.Results(annId).RatioOfAreas     = obj.Results(annId).ThresholdedArea / obj.Results(annId).TotalArea;

                    if obj.view.handles.minDiameterCheck.Value == 1
                        xMin = ceil(STATS(objId).BoundingBox(1));
                        yMin = ceil(STATS(objId).BoundingBox(2));
                        xMax = xMin + STATS(objId).BoundingBox(3) - 1;
                        yMax = yMin + STATS(objId).BoundingBox(4) - 1;

                        pixelInObject = CC.PixelIdxList{objId}(1);
                        [objPixY, objPixX] = ind2sub([height, width], pixelInObject);
                        objMask = L(yMin:yMax, xMin:xMax);
                        objMask(objMask ~= objMask(objPixY-yMin+1, objPixX-xMin+1)) = 0;
                        distanceTransform = bwdist(~objMask);
                        ultErosion = imregionalmax(distanceTransform, 8);

                        obj.Results(annId).minDiameter        = distanceTransform(ultErosion > 0) * 2 * pixSize.x;
                        obj.Results(annId).minDiameterAverage = mean(obj.Results(annId).minDiameter);

                        if minDiameterPositionsToSelection
                            [yPts, xPts] = find(ultErosion > 0);
                            yPts = yPts + yMin - 1;
                            xPts = xPts + xMin - 1;
                            selection(sub2ind([height, width], yPts, xPts)) = 1;
                        end
                    end

                    annId = annId + 1;
                end
                mask(:,:,sliceId) = currMask;

                if minDiameterPositionsToSelection
                    obj.mibModel.setData2D(selection, 'selection', sliceId, 3, NaN, getDataOptions);
                end
            end  % sliceId loop

            % --- triangulation -------------------------------------------
            if triangulatePointsCheck == 1
                progressDialog.Value   = 0;
                progressDialog.Message = 'Computing triangulation, please wait...';
                obj.mibModel.I{id}.lines3D.clearContents();

                sliceNoVector = [obj.Results.sliceNo];
                centroidXVec  = [obj.Results.CentroidX]';
                centroidYVec  = [obj.Results.CentroidY]';
                Points   = [];
                TreeName = [];
                Edges    = [];
                for sliceNo = 1:depth
                    if progressDialog.CancelRequested; close(progressDialog); return; end
                    currInd    = find(sliceNoVector == sliceNo);
                    centroidsX = centroidXVec(currInd);
                    centroidsY = centroidYVec(currInd);

                    DT    = delaunayTriangulation(centroidsX, centroidsY);
                    edges = DT.edges;

                    if removeFreeBoundaryCheck && ~isempty(edges)
                        F = DT.freeBoundary;
                        for i = 1:size(F,1)
                            F(i,:) = [min(F(i,:)), max(F(i,:))];
                        end
                        edges(ismember(edges, F, 'rows'), :) = [];
                        if isempty(edges); edges = DT.edges; end
                    end
                    edges = edges + size(Points, 1);

                    pointsTemp = [centroidsX, centroidsY, repmat(sliceNo, [numel(centroidsY), 1])];
                    Points   = [Points;   pointsTemp]; %#ok<AGROW>
                    TreeName = [TreeName; repmat({sprintf('Slice_%d', sliceNo)}, [numel(centroidsY), 1])]; %#ok<AGROW>
                    Edges    = [Edges;    edges]; %#ok<AGROW>
                    progressDialog.Value = sliceNo / depth;
                end

                progressDialog.Value   = 0.99;
                progressDialog.Message = 'Generating the graph...';
                NodeTable = table(Points, TreeName, 'VariableNames', {'PointsXYZ', 'TreeName'});
                EdgeTable = table(Edges,  'VariableNames', {'EndNodes'});
                G = graph(EdgeTable, NodeTable);
                G.Nodes.Properties.VariableUnits            = {'pixel', 'string'};
                G.Nodes.Properties.UserData.BoundingBox     = obj.mibModel.I{id}.image.boundingBox;
                G.Nodes.Properties.UserData.pixSize         = pixSize;

                obj.mibModel.I{id}.lines3D.replaceGraph(G);
                obj.mibModel.I{id}.lines3D.clipExtraThickness = 0;
            end

            % --- write mask and annotations ------------------------------
            labelList          = num2str([obj.Results.objId]');
            labelListPositions = [[obj.Results.sliceNo]' [obj.Results.CentroidX]' [obj.Results.CentroidY]'];
            labelListValues    = [obj.Results.RatioOfAreas]';

            if exist('labelList', 'var')
                obj.mibModel.I{id}.annotations.addLabels(labelList, labelListPositions, labelListValues);
            end
            obj.mibModel.setData3D(mask, 'mask', [], 3);

            % --- MATLAB workspace export ---------------------------------
            if exportMatlab
                progressDialog.Value   = 0.8;
                progressDialog.Message = 'Exporting to MATLAB workspace...';
                assignin('base', matlabVarName, obj.Results);
                exportText = sprintf('"%s"', matlabVarName);
                if triangulatePointsCheck == 1
                    graphVarName = [matlabVarName 'Graph'];
                    assignin('base', graphVarName, G);
                    exportText = sprintf('"%s" and "%s"', matlabVarName, graphVarName);
                end
                fprintf('Results were exported to the main MATLAB workspace as %s\n', exportText);
            end

            % --- MATLAB file export --------------------------------------
            if exportMatlabFile
                progressDialog.Value   = 0.85;
                progressDialog.Message = 'Saving MATLAB file...';
                Results = obj.Results; %#ok<PROP>
                save(exportMatlabFn, 'Results', '-v7');

                annotationFn = fullfile(pathStr, [fileStr '.ann']);
                annotationExportSettings.format      = 'ann';
                annotationExportSettings.showWaitbar = 0;
                obj.mibModel.I{id}.annotations.saveToFile(annotationFn, annotationExportSettings);
            end

            % --- triangulation file export -------------------------------
            if obj.view.handles.saveTriangulation.Value && exist('G', 'var')
                progressDialog.Value   = 0.88;
                progressDialog.Message = 'Saving triangulation...';
                saveGraphOptions.showWaitbar = false;
                for i = 1:numel(obj.saveGraphFormats)
                    switch obj.saveGraphFormats{i}
                        case 'lines3d'
                            outputFn = fullfile(pathStr, [fileStr '_Graph.lines3d']);
                        case 'amira-binary'
                            saveGraphOptions.EdgeFieldName = 'Length';
                            outputFn = fullfile(pathStr, [fileStr '_Graph.am']);
                        case 'excel'
                            outputFn = fullfile(pathStr, [fileStr '_Graph.xls']);
                    end
                    saveGraphOptions.format = obj.saveGraphFormats{i};
                    obj.mibModel.I{id}.lines3D.saveToFile(outputFn, saveGraphOptions);
                end
            end

            % --- Excel export --------------------------------------------
            if exportExcel
                progressDialog.Value   = 0.9;
                progressDialog.Message = 'Exporting to Excel...';
                warning('off', 'MATLAB:xlswrite:AddSheet');

                s = {'ThreshAnalysis: each object of the specified material(s) is intensity based thresholded compared with the original area'};
                if strcmp(obj.Results(1).thresholdPolicy, 'Absolute')
                    s(2,1) = {sprintf('Method: absolute thresholding, threshold value = %d', obj.Results(1).absoluteThresholdValue)};
                else
                    s(2,1) = {sprintf('Method: relative thresholding using %s intensity + %d offset', obj.Results(1).relativeThresholdMethod, obj.Results(1).thresholdOffsetValue)};
                end
                if obj.Results(1).ErodeDilate == 1; erodeDilateStr = 'YES'; else; erodeDilateStr = 'No'; end
                s(3,1) = {sprintf('Use of additional thresholding by erosion+dilation with strel size [3x3]: %s', erodeDilateStr)};

                s(5,1) = {sprintf('Dataset filename: %s', obj.Results(1).datasetName)};
                s(6,1) = {sprintf('Model filename: %s', obj.Results(1).modelName)};
                materialNamesString = sprintf('%s (id: %d)', obj.Results(1).materialNames{1}, obj.Results(1).materialId(1));
                for i = 2:numel(obj.Results(1).materialNames)
                    materialNamesString = sprintf('%s, %s (id: %d)', materialNamesString, obj.Results(1).materialNames{i}, obj.Results(1).materialId(i));
                end
                s(7,1) = {'Material name(s):'}; s(7,2) = {materialNamesString};
                s(8,1) = {sprintf('Connectivity of the object detection: %d', objConnectivity)};
                s(9,1) = {sprintf('Color channel: %d', obj.Results(1).colCh)};
                s(10,1) = {sprintf('Pixel size [x, y, z]: %f x %f x %f %s', obj.Results(1).pixSize.x, obj.Results(1).pixSize.y, obj.Results(1).pixSize.z, obj.Results(1).pixSize.units)};
                s(10,5) = {'Thresholded Area - is the area where pixel intensity is higher than the provided threshold value'};
                if obj.Results(1).triangulatePoints
                    extraStr = '(edges at boundaries were kept)';
                    if obj.Results(1).triangulateRemoveFreeBoundary
                        extraStr = '(edges at boundaries were removed)';
                    end
                    s(11,1) = {sprintf('The centroids were triangulated (%s); see more in corresponding files: %s', extraStr, fullfile(pathStr, [fileStr '_TRI.*']))};
                end

                rowId = 13;
                s(rowId,1) = {'ObjId'};  s(rowId,2) = {'SliceNo'}; s(rowId,3) = {'SliceName'}; s(rowId,4) = {'ObjMaterial'};
                s(rowId,5) = {'CentroidX, px'}; s(rowId,6) = {'CentroidY, px'};
                s(rowId,7) = {'FirstAxisLength, units'}; s(rowId,8) = {'SecondAxisLength, units'}; s(rowId,9) = {'Eccentricity'};
                s(rowId,10) = {'MedianIntensity'}; s(rowId,11) = {'Total Area, units'}; s(rowId,12) = {'Thresholded Area, units'};
                s(rowId,13) = {'Ratio, Thresholded/Total'}; s(rowId,14) = {'Threshold value'};
                if isfield(obj.Results, 'minDiameterAverage'); s(rowId,15) = {'Average min diameter, um'}; end

                noElements = numel(obj.Results);
                s(rowId+1:rowId+noElements, 1)  = num2cell([obj.Results(:).objId]);
                s(rowId+1:rowId+noElements, 2)  = num2cell([obj.Results(:).sliceNo]);
                s(rowId+1:rowId+noElements, 3)  = {obj.Results(:).SliceName}';
                s(rowId+1:rowId+noElements, 4)  = {obj.Results(:).objMaterialName}';
                s(rowId+1:rowId+noElements, 5)  = num2cell([obj.Results(:).CentroidX]);
                s(rowId+1:rowId+noElements, 6)  = num2cell([obj.Results(:).CentroidY]);
                s(rowId+1:rowId+noElements, 7)  = num2cell([obj.Results(:).FirstAxisLength]);
                s(rowId+1:rowId+noElements, 8)  = num2cell([obj.Results(:).SecondAxisLength]);
                s(rowId+1:rowId+noElements, 9)  = num2cell([obj.Results(:).Eccentricity]);
                s(rowId+1:rowId+noElements, 10) = num2cell([obj.Results(:).Median]);
                s(rowId+1:rowId+noElements, 11) = num2cell([obj.Results(:).TotalArea]);
                s(rowId+1:rowId+noElements, 12) = num2cell([obj.Results(:).ThresholdedArea]);
                s(rowId+1:rowId+noElements, 13) = num2cell([obj.Results(:).RatioOfAreas]);
                s(rowId+1:rowId+noElements, 14) = num2cell([obj.Results(:).objThresholdValues]);
                if isfield(obj.Results, 'minDiameterAverage')
                    s(rowId+1:rowId+noElements, 15) = num2cell([obj.Results(:).minDiameterAverage]);
                end

                % unwrap any single-element nested cells that xlswrite2 cannot handle
                for sRow = 1:size(s,1)
                    for sCol = 1:size(s,2)
                        val = s{sRow, sCol};
                        while iscell(val) && numel(val) == 1
                            val = val{1};
                        end
                        s{sRow, sCol} = val;
                    end
                end
                xlswrite2(exportExcelFn, s, 'Results', 'A1');
            end

            % --- optional plot -------------------------------------------
            if obj.view.handles.makePlotCheck.Value == 1
                obj.printResults();
            end

            obj.mibModel.showAnnotations = true;
            obj.mibModel.showMask        = true;
            if triangulatePointsCheck
                obj.mibModel.showLines3D = true;
                obj.mibModel.mibController.view.handles.panels.segmentation.handles.linesShowLines.Value = true;
            end
            notify(obj.mibModel, 'ShowImage');

            if isvalid(progressDialog); close(progressDialog); end
        end

        % -----------------------------------------------------------------
        function printResults(obj)
        % printResults  Generate violin-plot summary figure of the results.
            if isempty(obj.Results); return; end
            id = obj.mibModel.getActiveId();
            warning('off', 'MATLAB:gui:latexsup:UnableToInterpretTeXString');

            hFig = figure(obj.view.handles.figureId.Value);
            clf;
            hFig.PaperOrientation = 'landscape';
            hFig.PaperUnits       = 'centimeters';
            hFig.PaperPosition    = [0.634517 0.634517 28.4084 19.715];
            hFig.PaperType        = 'A4';

            noPanels    = 3;
            listOfFields = {'TotalArea', 'RatioOfAreas', 'FirstAxisLength'};
            if isfield(obj.Results, 'minDiameterAverage')
                noPanels = noPanels + 1;
                listOfFields{end+1} = 'minDiameterAverage';
            end
            if obj.view.handles.triangulateCentroidsCheck.Value
                noPanels = noPanels + 1;
                listOfFields{end+1} = 'Triangulation';
            end

            axesPosX  = .02;
            axesPosY  = .35;
            dX        = .05;
            axesWidth = 1/noPanels - dX;
            axesHeight = .5;

            axesHandles = cell([noPanels, 1]);
            for i = 1:noPanels
                axesHandles{i} = axes('Units', 'normalized', 'Position', [axesPosX axesPosY axesWidth axesHeight]); %#ok<LAXES>
                axesPosX = axesPosX + axesWidth + dX;
                switch listOfFields{i}
                    case 'TotalArea'
                        violinplot([[obj.Results.TotalArea]', [obj.Results.ThresholdedArea]']);
                        xticklabels({'Total', 'Thresholded'});
                        title(sprintf('Area, total and thresholded, %s^2', obj.Results(1).pixSize.units));
                    case 'RatioOfAreas'
                        violinplot([obj.Results.RatioOfAreas]');
                        title('Ratio total/thresholded');
                    case 'FirstAxisLength'
                        violinplot([[obj.Results.FirstAxisLength]', [obj.Results.SecondAxisLength]']);
                        xticklabels({'First', 'Second'});
                        title(sprintf('First and second axis length, %s', obj.Results(1).pixSize.units));
                    case 'minDiameterAverage'
                        combinedMinDiam = [obj.Results.minDiameterAverage]';
                        combinedMinDiam(isinf(combinedMinDiam)) = [];
                        violinplot(combinedMinDiam);
                        title(sprintf('Min average diameter, %s', obj.Results(1).pixSize.units));
                    case 'Triangulation'
                        try
                            violinplot(obj.mibModel.I{id}.lines3D.G.Edges.Length);
                        end
                        title(sprintf('Triangulation distances, %s', obj.Results(1).pixSize.units));
                end
                axesHandles{i}.YLim(1) = 0;
            end

            % annotation text block
            axes('Units', 'normalized', 'Visible', 'off'); %#ok<LAXES>
            text(.001, 1,   'ThreshAnalysis: each object of the specified material(s) is intensity based thresholded compared with the original area');
            if strcmp(obj.Results(1).thresholdPolicy, 'Absolute')
                text(.001, .97, sprintf('Method: absolute thresholding, threshold value = %d', obj.Results(1).absoluteThresholdValue));
            else
                text(.001, .97, sprintf('Method: relative thresholding using %s intensity + %d offset', obj.Results(1).relativeThresholdMethod, obj.Results(1).thresholdOffsetValue));
            end
            if obj.Results(1).ErodeDilate == 1; erodeDilateStr = 'YES'; else; erodeDilateStr = 'No'; end
            dY     = 0.18;
            dYstep = 0.03;
            text(.001, dY,          sprintf('Use of additional thresholding by erosion+dilation with strel size [3x3]: %s', erodeDilateStr));
            text(.001, dY-dYstep,   sprintf('Dataset filename: %s', obj.Results(1).datasetName), 'Interpreter', 'none');
            text(.001, dY-dYstep*2, sprintf('Model filename: %s', obj.Results(1).modelName), 'Interpreter', 'none');
            materialNamesString = sprintf('%s (id: %d)', obj.Results(1).materialNames{1}, obj.Results(1).materialId(1));
            for i = 2:numel(obj.Results(1).materialNames)
                materialNamesString = sprintf('%s, %s (id: %d)', materialNamesString, obj.Results(1).materialNames{i}, obj.Results(1).materialId(i));
            end
            text(.001, dY-dYstep*3, sprintf('Material name(s): %s', materialNamesString), 'Interpreter', 'none');
            text(.001, dY-dYstep*4, sprintf('Color channel: %d', obj.Results(1).colCh));
            text(.001, dY-dYstep*5, sprintf('Pixel size [x, y, z]: %f x %f x %f %s', obj.Results(1).pixSize.x, obj.Results(1).pixSize.y, obj.Results(1).pixSize.z, obj.Results(1).pixSize.units));
            text(.001, .22, 'Violin plots show data distribution; white dot = median, thick bar = IQR');

            if obj.view.handles.autoPrintCheck.Value
                uiprintdlg(hFig);
            end
        end

    end  % methods
end
