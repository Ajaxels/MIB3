classdef SurfaceArea3d < handle
% SURFACEAREA3D - Plugin controller for 3D surface area calculation of segmented objects.
%
% Traces object boundaries slice-by-slice using ``bwtraceboundary``, smooths
% and samples the curves, triangulates consecutive boundary pairs with
% ``mibTriangulateCurvePair``, and accumulates facet areas via
% ``trimeshSurfaceArea`` to give the total 3D surface area for each
% connected component of the selected model material.
%
% .. note::
%
%    Video demo: https://youtu.be/dIl1dt_cSqE
    properties
        mibModel            % handle to MibModel
        view                % handle to the AppDesigner view (core.ChildView wrapper)
        listener            % cell array of event listeners
        childControllers    = {}
        childControllersIds = {}
        matlabExportVariable  % name of export variable for Matlab workspace
    end

    events
        CloseEvent
    end

    methods (Static)

        function ViewListner_Callback2(obj, ~, evnt)
        % VIEWLISTNER_CALLBACK2 - React to MibModel events (static guard).
        %
        % Deletes stale listeners when the view has been closed, and calls
        % ``updateWidgets`` on ``UpdateGuiWidgets`` and ``NewDataset`` events.
        %
        % Parameters:
        % **obj** — handle to the ``SurfaceArea3d`` controller instance
        % **~** — event source (unused)
        % **evnt** — ``EventData`` object; ``evnt.EventName`` is inspected
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

    end  % methods (Static)

    methods

        % -----------------------------------------------------------------
        function obj = SurfaceArea3d(mibModel, varargin)
        % SURFACEAREA3D - Constructor.  Initialises plugin controller and GUI.
        %
        % Parameters:
        % **mibModel** — handle to the ``MibModel`` instance
        % **varargin** *(optional)* — unused; reserved for future batch options

            obj.mibModel = mibModel;

            id = obj.mibModel.getActiveId();

            % Check for the virtual stacking mode
            if strcmp(obj.mibModel.I{id}.image.type, 'Virtual')
                obj.view = [];
                dlgOpt.MsgBoxOnly  = true;
                dlgOpt.Icon        = 'puffin_warning';
                dlgOpt.HeaderLines = 1;
                utils.dlgs.inputUniversalDlg(obj.mibModel.mibGUI, '!!! Warning !!!', {''}, ...
                    {'This plugin is not compatible with the virtual stacking mode!\nPlease switch to the memory-resident mode and try again'}, ...
                    'Not implemented', dlgOpt);
                obj.closeWindow();
                return;
            end

            obj.view = core.ChildView(obj, 'SurfaceArea3dGUI');
            obj.view.gui = utils.moveWindowOutside(obj.view.gui, obj.mibModel.mibGUI, 'left');

            % Window icon — use plugin icon if present, fall back to MIB default
            pluginDir    = fileparts(mfilename('fullpath'));
            localIcon    = fullfile(pluginDir, 'icon_16px.png');
            fallbackIcon = fullfile(obj.mibModel.mibPath, 'assets', 'icons', 'mib_icon_16px.png');
            if isfile(localIcon)
                obj.view.gui.Icon = localIcon;
            elseif isfile(fallbackIcon)
                obj.view.gui.Icon = fallbackIcon;
            end

            % Font size
            Font = obj.mibModel.preferences.System.Font;
            if obj.view.handles.Label.FontSize ~= Font.FontSize || ...
                    ~strcmp(obj.view.handles.Label.FontName, Font.FontName)
                utils.fontSizeUpdate(obj.view.gui, Font);
            end

            % Help text
            obj.view.handles.Label.Text  = sprintf('Calculation of surface areas in 3D\nSee details in the Help section');
            obj.view.handles.Label2.Text = sprintf('Important!\nIndividual objects have to be connected in 3D\nHoles are not allowed');
            obj.matlabExportVariable = 'SurfaceArea';

            obj.addCallbacks();
            obj.initTooltips();
            obj.updateWidgets();

            if isdeployed
                obj.view.handles.exportMatlabCheck.Enable = 'off';
            end

            % Initialise filename and directory widgets
            [imagePath, imageFilenameBase] = fileparts(obj.mibModel.I{id}.image.filename);
            outputFilename = fullfile(imagePath, [imageFilenameBase '_SurfaceArea3D.csv']);
            obj.view.handles.filenameEdit.Value   = outputFilename;
            obj.view.handles.filenameEdit.Tooltip = outputFilename;
            obj.view.handles.exportResultsSurfEditField.Value   = imagePath;
            obj.view.handles.exportResultsSurfEditField.Tooltip = imagePath;

            obj.listener{1} = addlistener(obj.mibModel, 'UpdateGuiWidgets', ...
                @(src, evnt) obj.ViewListner_Callback2(obj, src, evnt));
            obj.listener{2} = addlistener(obj.mibModel, 'NewDataset', ...
                @(src, evnt) obj.ViewListner_Callback2(obj, src, evnt));

            obj.view.gui.Visible = true;
        end

        % -----------------------------------------------------------------
        function closeWindow(obj)
        % CLOSEWINDOW - Close the plugin window and release all resources.
        %
        % Recursively closes child controllers, deletes the AppDesigner
        % figure, removes all MibModel listeners, and fires ``CloseEvent``.

            for i = numel(obj.childControllers):-1:1
                child = obj.childControllers{i};
                if isa(child, 'handle') && isvalid(child)
                    child.closeWindow();
                end
            end
            obj.childControllers    = {};
            obj.childControllersIds = {};

            if ~isempty(obj.view) && isvalid(obj.view.gui)
                obj.view.gui.CloseRequestFcn = '';
                delete(obj.view.gui);
            end

            for i = 1:numel(obj.listener)
                delete(obj.listener{i});
            end

            notify(obj, 'CloseEvent');
        end

        % -----------------------------------------------------------------
        function addCallbacks(obj)
        % ADDCALLBACKS - Wire all widget callbacks to controller methods.
        %
        % Called once from the constructor after the view is created.
        % Sets ``CloseRequestFcn`` and all ``ButtonPushedFcn`` /
        % ``ValueChangedFcn`` handlers so no callback logic lives inside
        % the ``.mlapp`` file.

            obj.view.gui.CloseRequestFcn = @(~,~) obj.closeWindow();
            handles = obj.view.handles;
            handles.closeBtn.ButtonPushedFcn               = @(~,~) obj.closeWindow();
            handles.continueBtn.ButtonPushedFcn             = @(~,~) obj.continueBtn_Callback();
            handles.saveResultsCheck.ValueChangedFcn        = @(~,~) obj.saveResultsCheck_Callback();
            handles.exportResultsFilename.ButtonPushedFcn   = @(~,~) obj.exportResultsFilename_Callback();
            handles.generateModelObjectsCheckBox.ValueChangedFcn      = @(~,~) obj.CheckBox_Callback();
            handles.exportResultsSurf.ButtonPushedFcn      = @(~,~) obj.exportResultsSurf_Callback();
            handles.exportMatlabCheck.ValueChangedFcn       = @(~,~) obj.exportMatlabCheck_Callback();
            handles.helpBtn.ButtonPushedFcn                 = @(~,~) obj.helpBtn_Callback();
        end

        % -----------------------------------------------------------------
        function initTooltips(obj)
        % INITTOOLTIPS - Set static tooltip strings on all interactive widgets.
        %
        % Called once from the constructor after ``addCallbacks``.
        % Assigns plain strings to each widget's ``.Tooltip`` property.

            h = obj.view.handles;

            h.materialDropdown.Tooltip = ...
                'Model material whose surface area will be calculated';

            h.xySmoothingEditField.Tooltip = sprintf([ ...
                'Sliding-window half-width (px) applied to the traced XY boundary.\n' ...
                'Reduces jagged edges caused by pixel staircase effects.\n' ...
                'Set to 0 to skip smoothing.']);

            h.xySamplingEditField.Tooltip = sprintf([ ...
                'Keep every N-th point along the XY boundary curve (1 = all points).\n' ...
                'Increase to reduce computation time for large or complex objects.']);

            h.zSamplingEditField.Tooltip = sprintf([ ...
                'Process every N-th Z-slice (1 = all slices).\n' ...
                'Increase to speed up calculation at the cost of surface accuracy.']);

            h.showPointsCheckBox.Tooltip = sprintf([ ...
                'Mark detected surface boundary points in the selection layer.\n' ...
                'Useful for visual quality control of the tracing result.']);

            h.exportMatlabCheck.Tooltip = sprintf([ ...
                'Export the SurfaceArea results structure to the MATLAB base workspace.\n' ...
                'Variable name can be customised when the checkbox is ticked.']);

            h.saveResultsCheck.Tooltip = sprintf([ ...
                'Write results to a file after calculation.\n' ...
                'Supported formats: CSV (.csv), MATLAB (.mat), Excel (.xlsx).\n' ...
                'The output format is determined by the file extension.']);

            h.addMaterialNameCheckBox.Tooltip = sprintf([ ...
                'Append the selected material name to the output filename,\n' ...
                'e.g. results.csv → results_MaterialName.csv.']);

            h.exportResultsFilename.Tooltip = ...
                'Browse to choose the output file path and format (CSV / MAT / XLSX)';

            h.filenameEdit.Tooltip = sprintf([ ...
                'Full path of the output file.\n' ...
                'Extension sets the format: .csv → CSV table, .mat → MATLAB, .xlsx → Excel.']);

            h.generateModelObjectsCheckBox.Tooltip = sprintf([ ...
                'Save each detected object surface as an Amira HyperSurface (.surf) file\n' ...
                'in the directory specified below.']);

            h.exportResultsSurf.Tooltip = ...
                'Browse to choose the directory where .surf surface files will be written';

            h.exportResultsSurfEditField.Tooltip = ...
                'Directory for .surf output files (one file per detected object)';

            h.exportContactImarisCheckBox.Tooltip = sprintf([ ...
                'Send each surface mesh to an open Imaris session via the ImarisXT interface.\n' ...
                'Imaris must be running and connected before starting the calculation.']);

            h.continueBtn.Tooltip = ...
                'Start surface area calculation for the selected material';

            h.closeBtn.Tooltip = 'Close this dialog';

            h.helpBtn.Tooltip = 'Open plugin documentation in the system browser';
        end

        % -----------------------------------------------------------------
        function updateWidgets(obj)
        % UPDATEWIDGETS - Refresh GUI widgets from the current dataset state.
        %
        % Populates the material dropdown from
        % ``MibModel.I{id}.labels.materialNames`` and enables or disables
        % the Calculate button depending on whether a labelled model is loaded.

            id = obj.mibModel.getActiveId();

            if obj.mibModel.I{id}.modelExist == 0
                materialsList = {'Insufficient data, please check Help!'};
                obj.view.handles.materialDropdown.Items = materialsList;
                obj.view.handles.materialDropdown.Value = materialsList{1};
                obj.view.handles.continueBtn.Enable   = 'off';
            else
                materialsList = obj.mibModel.I{id}.labels.materialNames;
                if isempty(materialsList)
                    materialsList = {'Insufficient data, please check Help!'};
                    obj.view.handles.continueBtn.Enable = 'off';
                else
                    obj.view.handles.continueBtn.Enable = 'on';
                end
                obj.view.handles.materialDropdown.Items = materialsList;
                obj.view.handles.materialDropdown.Value = materialsList{1};
            end
        end

        % -----------------------------------------------------------------
        function exportMatlabCheck_Callback(obj)
        % EXPORTMATLABCHECK_CALLBACK - Prompt for MATLAB export variable name.
        %
        % Fires when the *Export to MATLAB* checkbox is ticked.  Opens an
        % input dialog so the user can rename the workspace variable before
        % calculation begins.

            if obj.view.handles.exportMatlabCheck.Value
                answer = utils.dlgs.inputUniversalDlg(obj.view.gui, '', ...
                    {'Please define output variable:'}, {obj.matlabExportVariable}, ...
                    'Export variable');
                if ~isempty(answer)
                    obj.matlabExportVariable = answer{1};
                end
            end
        end

        % -----------------------------------------------------------------
        function saveResultsCheck_Callback(obj)
        % SAVERESULTSCHECK_CALLBACK - Toggle file-export controls.
        %
        % Enables or disables the filename browse button and edit field
        % when the *Save results* checkbox changes state.

            if obj.view.handles.saveResultsCheck.Value == 1
                obj.view.handles.exportResultsFilename.Enable = 'on';
                obj.view.handles.filenameEdit.Enable          = 'on';
            else
                obj.view.handles.exportResultsFilename.Enable = 'off';
                obj.view.handles.filenameEdit.Enable          = 'off';
            end
        end

        % -----------------------------------------------------------------
        function exportResultsFilename_Callback(obj)
        % EXPORTRESULTSFILENAME_CALLBACK - Open a file-save dialog for the output path.
        %
        % Supports ``.csv``, ``.mat``, and ``.xlsx`` formats.  Updates
        % both the filename edit field and its tooltip with the chosen path.

            formatText = {'*.csv', 'Comma-separated values (*.csv)'; ...
                          '*.mat', 'Matlab format (*.mat)'; ...
                          '*.xlsx', 'Microsoft Excel (*.xlsx)'};
            currentFilename = obj.view.handles.filenameEdit.Value;
            [fileName, pathName] = uiputfile(formatText, 'Select filename', currentFilename);
            if isequal(fileName, 0) || isequal(pathName, 0); return; end

            outputFilename = fullfile(pathName, fileName);
            obj.view.handles.filenameEdit.Value   = outputFilename;
            obj.view.handles.filenameEdit.Tooltip = outputFilename;
        end

        % -----------------------------------------------------------------
        function CheckBox_Callback(obj)
        % CHECKBOX_CALLBACK - Toggle Amira .surf output controls.
        %
        % Enables or disables the directory browse button and path edit
        % field when the *Generate .surf files* checkbox changes state.

            if obj.view.handles.generateModelObjectsCheckBox.Value == 1
                obj.view.handles.exportResultsSurf.Enable = 'on';
                obj.view.handles.exportResultsSurfEditField.Enable               = 'on';
            else
                obj.view.handles.exportResultsSurf.Enable = 'off';
                obj.view.handles.exportResultsSurfEditField.Enable               = 'off';
            end
        end

        % -----------------------------------------------------------------
        function exportResultsSurf_Callback(obj)
        % EXPORTRESULTSFILENAME_2_CALLBACK - Browse for the .surf output directory.
        %
        % Opens a directory picker and writes the chosen path to the
        % directory edit field and its tooltip.

            startPath = obj.view.handles.exportResultsSurfEditField.Value;
            folderName = uigetdir(startPath, 'Select directory');
            if isequal(folderName, 0); return; end

            obj.view.handles.exportResultsSurfEditField.Value   = folderName;
            obj.view.handles.exportResultsSurfEditField.Tooltip = folderName;
        end

        % -----------------------------------------------------------------
        function helpBtn_Callback(obj)
        % HELPBTN_CALLBACK - Open the plugin HTML documentation in a browser.
        %
        % Constructs the path relative to ``mibModel.mibPath`` and calls
        % MATLAB's ``web`` function with the ``-browser`` flag.

            mibPath = obj.mibModel.mibPath;
            web(fullfile(mibPath, 'techdoc/html/user-interface/plugins/organelle-analysis/surface-area-3d.html'), '-browser');
        end

        % -----------------------------------------------------------------
        function continueBtn_Callback(obj)
        % CONTINUEBTN_CALLBACK - Main processing: calculate 3D surface areas for segmented objects.
        %
        % Steps:
        %
        % 1. Read widget values and validate input.
        % 2. Back up the current annotation layer and clear annotations.
        % 3. Load the labels volume and crop to the bounding box of the material.
        % 4. Fill holes slice-by-slice; find connected components (26-connectivity).
        % 5. Remove single-slice objects (cannot form a closed surface).
        % 6. For each component, trace XY boundaries on every N-th Z-slice,
        %    apply optional smoothing and sampling, then triangulate
        %    consecutive curve pairs with ``mibTriangulateCurvePair``.
        % 7. Accumulate facet areas via ``trimeshSurfaceArea``.
        % 8. Optionally export Amira ``.surf`` files, send to Imaris, write
        %    selection layer, or save to CSV / MAT / Excel.
        % 9. Add centroid annotations and fire ``ShowImage``.

            id = obj.mibModel.getActiveId();

            material1_Name  = obj.view.handles.materialDropdown.Value;
            materialsList   = obj.mibModel.I{id}.labels.materialNames;
            material1_Index = find(strcmp(materialsList, material1_Name));
            if isempty(material1_Index); material1_Index = 1; end

            outFn = obj.view.handles.filenameEdit.Value;
            if obj.view.handles.addMaterialNameCheckBox.Value == 1
                [filePath, filenamePart, fileExt] = fileparts(outFn);
                filenamePart = [filenamePart '_' material1_Name];
                outFn = fullfile(filePath, [filenamePart fileExt]);
            end

            [~, surfFnTemplate] = fileparts(obj.mibModel.I{id}.image.filename);

            if obj.mibModel.I{id}.modelExist == 0
                utils.dlgs.showErrorDialog(obj.view.gui, ...
                    'This plugin requires a model to be present!', 'Model is missing');
                return;
            end

            if obj.view.handles.saveResultsCheck.Value
                if exist(outFn, 'file') == 2
                    strText = sprintf('!!! Warning !!!\n\nThe file:\n%s \nis already exist!\n\nOverwrite?', outFn);
                    button = utils.dlgs.inputQuestDlg(obj.view.gui, strText, 'File exist!', 'Overwrite', 'Cancel', 'Cancel');
                    if strcmp(button, 'Cancel'); return; end
                    delete(outFn);
                end
            end

            xySmoothValue  = obj.view.handles.xySmoothingEditField.Value;   % in pixels
            xySamplingStep = obj.view.handles.xySamplingEditField.Value;  % take each N-th pixel in XY
            zSamplingStep  = obj.view.handles.zSamplingEditField.Value;   % take each N-th pixel in Z

            tic

            % Backup current annotations
            obj.mibModel.backup('labels', 1);
            % Clear annotations
            obj.mibModel.I{id}.annotations.clearContents();

            exportToMatlab = obj.view.handles.exportMatlabCheck.Value;
            saveToFile     = obj.view.handles.saveResultsCheck.Value;
            saveImages     = obj.view.handles.generateModelObjectsCheckBox.Value;
            outDir         = obj.view.handles.exportResultsSurfEditField.Value;

            surf2amiraOptions.overwrite = 1;
            surf2amiraOptions.format    = 'binary';

            globalBoundingBox = obj.mibModel.I{id}.image.boundingBox;  % [xmin, xmax, ymin, ymax, zmin, zmax]

            if saveImages && isfolder(outDir) == 0; mkdir(outDir); end

            progressDialog = uiprogressdlg(obj.view.gui, ...
                'Title', 'SurfaceArea3D', ...
                'Message', 'Obtaining the model, please wait...', ...
                'Value', 0);

            % Get model
            getDataOptions.blockModeSwitch = 0;
            labelsData = obj.mibModel.getData3D('labels', [], 3, material1_Index, getDataOptions);
            Model = labelsData{1};

            pixSize = obj.mibModel.I{id}.image.pixSize;

            progressDialog.Value   = 0.1;
            progressDialog.Message = 'Cropping the model, please wait...';

            % Crop the model to object bounds
            [Y, X, Z] = ind2sub(size(Model), find(Model == 1));
            minX = min(X);
            minY = min(Y);
            minZ = min(Z);
            maxX = max(X);
            maxY = max(Y);
            maxZ = max(Z);

            Model             = Model(minY:maxY, minX:maxX, minZ:maxZ);
            globalBoundingBox(1) = globalBoundingBox(1) + (minX-1)*pixSize.x;  % xmin
            globalBoundingBox(3) = globalBoundingBox(3) + (minY-1)*pixSize.y;  % ymin
            globalBoundingBox(5) = globalBoundingBox(5) + (minZ-1)*pixSize.z;  % zmin

            progressDialog.Value   = 0.2;
            progressDialog.Message = 'Looking for connected objects, please wait...';

            % Fill holes and find connected components
            for sliceIndex = 1:size(Model, 3)
                Model(:,:,sliceIndex) = imfill(Model(:,:,sliceIndex));
            end
            CC = bwconncomp(Model, 26);

            progressDialog.Value   = 0.3;
            progressDialog.Message = 'Calculating the bounding boxes, please wait...';

            STATS = regionprops(CC, 'BoundingBox', 'Centroid');

            % Remove objects that span only a single slice
            singleSliceList = zeros([CC.NumObjects, 1]);
            for objId = 1:CC.NumObjects
                if STATS(objId).BoundingBox(6) < 2
                    fprintf('SurfaceArea3D object number: %d at slice: %d was removed from analysis\n', ...
                        objId, floor(STATS(objId).BoundingBox(3))+minZ);
                    singleSliceList(objId) = 1;
                end
            end

            if sum(singleSliceList) > 0
                STATS(singleSliceList==1)          = [];
                CC.NumObjects                       = sum(singleSliceList==0);
                CC.PixelIdxList(singleSliceList==1) = [];
            end

            % Allocate annotation arrays
            labelList    = cell([CC.NumObjects, 1]);
            labelValues  = zeros([CC.NumObjects, 1]);
            positionList = zeros([CC.NumObjects, 4]);

            progressDialog.Value   = 0.3;
            progressDialog.Message = 'Generating the label matrix, please wait...';

            L = labelmatrix(CC);

            % Results structure
            SurfaceArea = struct();
            SurfaceArea(1).pixSize        = pixSize;
            SurfaceArea(1).MaterialName   = material1_Name;
            SurfaceArea(1).xySmoothValue  = xySmoothValue;
            SurfaceArea(1).xySamplingStep = xySamplingStep;
            SurfaceArea(1).zSamplingStep  = zSamplingStep;

            progressDialog.Value   = 0.3;
            progressDialog.Message = 'Calculating the areas, please wait...';

            % Loop across detected objects
            for objId = 1:CC.NumObjects
                bb  = ceil(STATS(objId).BoundingBox);  % [x,y,z,w,h,d]
                M2  = L(bb(2):bb(2)+bb(5)-1, bb(1):bb(1)+bb(4)-1, bb(3):bb(3)+bb(6)-1);
                M1  = zeros(size(M2), 'uint8');
                M1(M2==objId) = 1;
                depthM1 = size(M1, 3);

                SurfaceArea(objId).SumAreaTotal = 0;
                vAll = zeros(0, 3);
                fAll = zeros(0, 3);

                zPointsVector = 1:zSamplingStep:depthM1;
                if zPointsVector(end) ~= depthM1
                    zPointsVector(end+1) = depthM1;
                end

                SurfaceArea(objId).PointsVector = cell([numel(zPointsVector), 1]);
                PointsVectorIndex = 1;

                connMatrix           = cell([numel(zPointsVector), 1]);
                branchPointsDetected = 0;
                zIndex               = 1;
                detectedSlices       = NaN([numel(zPointsVector), 1]);
                detectedIndex        = 1;

                for z = zPointsVector
                    if z < zPointsVector(end)
                        if z > zPointsVector(1)
                            currObjCC = nextObjCC;   %#ok<NODEF>
                        else
                            currObjCC = bwconncomp(M1(:, :, z), 8);
                        end
                        nextObjCC = bwconncomp(M1(:, :, min([z+zSamplingStep, depthM1])), 8);

                        if z > zPointsVector(1)
                            objStats = regionprops(nextObjCC, 'BoundingBox');
                        else
                            objStats = regionprops(currObjCC, 'BoundingBox');
                        end
                        minXVec = arrayfun(@(s) s.BoundingBox(1), objStats);
                        minYVec = arrayfun(@(s) s.BoundingBox(2), objStats);
                        maxXVec = arrayfun(@(s) s.BoundingBox(1)+s.BoundingBox(3), objStats);
                        maxYVec = arrayfun(@(s) s.BoundingBox(2)+s.BoundingBox(4), objStats);
                        for vecId = 1:numel(minYVec)
                            findMinY  = minYVec > minYVec(vecId);
                            findMinX  = minXVec > minXVec(vecId);
                            findMaxY  = maxYVec < maxYVec(vecId);
                            findMaxX  = maxXVec < maxXVec(vecId);
                            findTotal = findMinY + findMinX + findMaxY + findMaxX;
                            if ~isempty(find(findTotal==4))  %#ok<EFIND>
                                fprintf('\nWarning!!! Potential problem is found on slice: %d for object %d\n', z+bb(3)-1+minZ, objId);
                                detectedSlices(detectedIndex) = z+bb(3)-1+minZ;
                                detectedIndex = detectedIndex + 1;
                            end
                        end

                        if currObjCC.NumObjects == nextObjCC.NumObjects && currObjCC.NumObjects == 1
                            connMatrix{zIndex} = [1 1];
                        else
                            currL = labelmatrix(currObjCC);
                            currL = imdilate(currL, ones(3));
                            nextL = labelmatrix(nextObjCC);
                            nextL = imdilate(nextL, ones(3));
                            for sourceIndex = 1:currObjCC.NumObjects
                                overlapIndices = double(unique(nextL(currL==sourceIndex)));
                                overlapIndices(overlapIndices==0) = [];
                                for i = 1:numel(overlapIndices)
                                    connMatrix{zIndex} = [connMatrix{zIndex}; sourceIndex overlapIndices(i)];
                                end
                            end
                        end
                        zIndex = zIndex + 1;
                    end

                    % Thin the object
                    Mthin = bwmorph(M1(:, :, z), 'thin', Inf);
                    CC2   = bwconncomp(Mthin, 8);

                    for subObjId = 1:CC2.NumObjects
                        objImg = zeros(size(Mthin), 'uint8');
                        objImg(CC2.PixelIdxList{subObjId}) = 1;

                        endPoints           = bwmorph(objImg, 'endpoints');
                        [ePntsY, ePntsX]    = find(endPoints);
                        if numel(ePntsY) > 2
                            if branchPointsDetected == 0
                                fprintf('Removing branch points: .');
                            else
                                fprintf('.');
                            end
                            branchPointsDetected = 1;
                            objImg   = logical(utils.removeBranches(objImg));
                            Mthin    = Mthin - (Mthin - objImg);
                            endPoints        = bwmorph(objImg, 'endpoints');
                            [ePntsY, ePntsX] = find(endPoints);
                        elseif numel(ePntsY) == 1
                            ePntsY = [ePntsY; ePntsY];
                            ePntsX = [ePntsX; ePntsX];
                        end

                        noPix = sum(sum(objImg));
                        if noPix > 1
                            B = bwtraceboundary(objImg, [ePntsY(1), ePntsX(1)], 'N', 8, sum(sum(objImg)));
                        else
                            [y, x] = find(objImg);
                            B = [y, x; y, x];
                        end

                        B(:,1) = (B(:,1)+bb(2)-1)*pixSize.y + globalBoundingBox(3)-pixSize.y;
                        B(:,2) = (B(:,2)+bb(1)-1)*pixSize.x + globalBoundingBox(1)-pixSize.x;
                        B(:,3) = (z+bb(3)-1)*pixSize.z      + globalBoundingBox(5)-pixSize.z;

                        % XY smoothing
                        if xySmoothValue > 0
                            noElements = numel(B(:,1));
                            if noElements/2 < xySmoothValue
                                B(:,1) = utils.align.windv(B(:,1), floor(noElements/2), 1);
                                B(:,2) = utils.align.windv(B(:,2), floor(noElements/2), 1);
                            else
                                B(:,1) = utils.align.windv(B(:,1), xySmoothValue, 1);
                                B(:,2) = utils.align.windv(B(:,2), xySmoothValue, 1);
                            end
                        end

                        % XY sampling
                        if xySamplingStep > 1
                            Btemp       = B;
                            pointVector = 1:xySamplingStep:size(Btemp, 1);
                            if pointVector(end) ~= size(Btemp, 1)
                                pointVector(end+1) = size(Btemp, 1);
                            end
                            B = Btemp(pointVector, :);
                        end
                        SurfaceArea(objId).PointsVector{PointsVectorIndex}{subObjId} = B;
                    end
                    PointsVectorIndex = PointsVectorIndex + 1;
                end

                if branchPointsDetected == 1; fprintf('\n'); end

                detectedSlices(isnan(detectedSlices)) = [];
                if numel(detectedSlices) > 0
                    fprintf('ObjId: %d, list of slices with possible conflicts:\n%s\n', objId, num2str(detectedSlices'));
                end

                cellVector = [SurfaceArea(objId).PointsVector{:}];
                SurfaceArea(objId).PointCloud  = cat(1, cellVector{:});
                SurfaceArea(objId).Centroid(1) = STATS(objId).Centroid(1)+minX;
                SurfaceArea(objId).Centroid(2) = STATS(objId).Centroid(2)+minY;
                SurfaceArea(objId).Centroid(3) = STATS(objId).Centroid(3)+minZ;
                SurfaceArea(objId).Centroid(4) = obj.mibModel.I{id}.getCurrentTimePoint();

                for z = 1:numel(SurfaceArea(objId).PointsVector)-1
                    noBrakePointsCurr = histcounts(connMatrix{z}(:,1), 1:max(connMatrix{z}(:,1))+1)-1;
                    noBrakePointsNext = histcounts(connMatrix{z}(:,2), 1:max(connMatrix{z}(:,2))+1)-1;

                    pVecZ1   = SurfaceArea(objId).PointsVector{z};
                    pVecZ2   = SurfaceArea(objId).PointsVector{z+1};
                    cMatrix1 = connMatrix{z};
                    cMatrix  = connMatrix{z};
                    clear vec1 vec2;
                    objIndex = 1;

                    for matrixIndex = 1:size(connMatrix{z}, 1)
                        subObjId = cMatrix(matrixIndex, 1);
                        vecZ = [pVecZ1{subObjId}(:,2), pVecZ1{subObjId}(:,1), pVecZ1{subObjId}(:,3)];

                        if noBrakePointsCurr(subObjId) == 0
                            vec1{objIndex} = vecZ;  %#ok<AGROW>
                        else
                            clear nextEndpoints;
                            rowInd = find(cMatrix1(:,1) == subObjId);
                            for i = 1:numel(rowInd)
                                nextObjId = cMatrix1(rowInd(i), 2);
                                nextEndpoints(i*2-1:i*2,:) = pVecZ2{nextObjId}([1 end], [2 1]);  %#ok<AGROW>
                            end
                            [~, minPointsIds] = minDistancePoints(nextEndpoints, vecZ(:,1:2));
                            minPointsIds(minPointsIds==min(minPointsIds)) = 1;
                            minPointsIds(minPointsIds==max(minPointsIds)) = size(vecZ,1);
                            brakePointIndex = floor(mean([minPointsIds(2), minPointsIds(3)]));
                            pntsSortedVec   = sort([minPointsIds(1), brakePointIndex]);
                            vec1{objIndex}  = vecZ(pntsSortedVec(1):pntsSortedVec(2), :);  %#ok<AGROW>
                            pVecZ1{subObjId}(pntsSortedVec(1):pntsSortedVec(2)-1, :) = [];
                            noBrakePointsCurr(subObjId) = noBrakePointsCurr(subObjId) - 1;
                            cMatrix1(matrixIndex, :) = NaN;
                        end

                        subObjId = cMatrix(matrixIndex, 2);
                        vecZ = [pVecZ2{subObjId}(:,2), pVecZ2{subObjId}(:,1), pVecZ2{subObjId}(:,3)];

                        if noBrakePointsNext(subObjId) == 0
                            vec2{objIndex} = vecZ;  %#ok<AGROW>
                        else
                            clear nextEndpoints;
                            rowInd = find(cMatrix(:,2) == subObjId);
                            for i = 1:numel(rowInd)
                                nextObjId = cMatrix(rowInd(i), 1);
                                nextEndpoints(i*2-1:i*2,:) = pVecZ1{nextObjId}([1 end], [2 1]);  %#ok<AGROW>
                            end
                            [~, minPointsIds] = minDistancePoints(nextEndpoints, vecZ(:, 1:2));
                            minPointsIds(minPointsIds==min(minPointsIds)) = 1;
                            minPointsIds(minPointsIds==max(minPointsIds)) = size(vecZ,1);
                            brakePointIndex = floor(mean([minPointsIds(2), minPointsIds(3)]));
                            pntsSortedVec   = sort([minPointsIds(1), brakePointIndex]);
                            vec2{objIndex}  = vecZ(pntsSortedVec(1):pntsSortedVec(2), :);  %#ok<AGROW>
                            pVecZ2{subObjId}(pntsSortedVec(1):pntsSortedVec(2)-1, :) = [];
                            noBrakePointsNext(subObjId) = noBrakePointsNext(subObjId) - 1;
                            cMatrix(rowInd(1), :) = NaN;
                        end
                        objIndex = objIndex + 1;
                    end

                    if ~isempty(vec1)
                        SurfaceArea(objId).Area{z} = 0;
                        for vecId = 1:numel(vec1)
                            try
                                [v, f] = mibTriangulateCurvePair(vec1{vecId}, vec2{vecId}, ...
                                    min([pixSize.x, pixSize.y, pixSize.z])/10);
                            catch triangulationError
                                fprintf('Warning!!! This case can not be handled with this plugin, see slices = %d-%d\n', z+minZ-1, z+minZ);
                                fprintf('Details: "%s"\n', triangulationError.message);
                                fprintf('Most likely one of these slices have a 2D small object next to the main object\n');
                                continue;
                            end
                            fAll = [fAll; f + size(vAll, 1)];   %#ok<AGROW>
                            vAll = [vAll; v];                    %#ok<AGROW>
                            currArea = trimeshSurfaceArea(v, f);
                            SurfaceArea(objId).Area{z}      = SurfaceArea(objId).Area{z} + currArea;
                            SurfaceArea(objId).SumAreaTotal = SurfaceArea(objId).SumAreaTotal + currArea;
                        end
                    end
                end
                fprintf('Surface %d; total area is %f\n', objId, SurfaceArea(objId).SumAreaTotal);

                labelList(objId)      = {sprintf('Obj%d', objId)};
                labelValues(objId)    = SurfaceArea(objId).SumAreaTotal;
                positionList(objId,:) = [SurfaceArea(objId).Centroid(3), SurfaceArea(objId).Centroid(1), ...
                    SurfaceArea(objId).Centroid(2), SurfaceArea(objId).Centroid(4)];

                if saveImages
                    try
                        surface.vertices = vAll;
                        surface.faces    = fAll;
                        surf2amiraHyperSurface( ...
                            fullfile(outDir, sprintf('%s_%s_Id_%04i.surf', surfFnTemplate, material1_Name, objId)), ...
                            surface, surf2amiraOptions);
                    catch surfExportError
                        disp(['An error detected in ' num2str(objId) '!']);
                        disp(surfExportError.message);
                    end
                end

                if obj.view.handles.exportContactImarisCheckBox.Value
                    imarisOptions.name = sprintf('%s_Id_%04i', material1_Name, objId);
                    surface.vertices   = vAll;
                    surface.faces      = fAll;
                    obj.mibModel.connImaris = io.imaris.mibSetImarisSurface(surface, obj.mibModel.connImaris, imarisOptions);
                end

                figure(15);
                if objId == 1; clf; end
                patch('Faces', fAll, 'Vertices', vAll, 'FaceColor', 'red');
                axis equal;

                progressDialog.Value = objId / CC.NumObjects;
            end  % for objId

            if obj.view.handles.showPointsCheckBox.Value
                progressDialog.Value   = 0.95;
                progressDialog.Message = 'Generating selection layer...';
                selection = zeros(size(Model), 'uint8');
                getDataOptions.x = [minX, maxX];
                getDataOptions.y = [minY, maxY];
                getDataOptions.z = [minZ, maxZ];
                for objId = 1:CC.NumObjects
                    yVec = round((SurfaceArea(objId).PointCloud(:,1) - globalBoundingBox(3) + pixSize.y) / pixSize.y);
                    xVec = round((SurfaceArea(objId).PointCloud(:,2) - globalBoundingBox(1) + pixSize.x) / pixSize.x);
                    zVec = round((SurfaceArea(objId).PointCloud(:,3) - globalBoundingBox(5) + pixSize.z) / pixSize.z);
                    linearInd = sub2ind(size(Model), yVec, xVec, zVec);
                    selection(linearInd) = 1;
                end
                obj.mibModel.setData3D(selection, 'selection', [], 3, [], getDataOptions);
            end

            if exportToMatlab
                progressDialog.Message = 'Exporting to Matlab...';
                fprintf('SurfaceArea3D: a structure with results "%s" was created\n', obj.matlabExportVariable);
                assignin('base', obj.matlabExportVariable, SurfaceArea);
            end
            toc

            if saveToFile
                if strcmp(outFn(end-2:end), 'mat')
                    progressDialog.Message = 'Saving to Matlab file...';
                    save(outFn, 'SurfaceArea');
                elseif strcmp(outFn(end-2:end), 'csv')
                    progressDialog.Message = 'Generating CSV file...';
                    obj.saveToCSV(SurfaceArea, outFn);
                else
                    progressDialog.Message = 'Generating Excel file...';
                    obj.saveToExcel(SurfaceArea, outFn);
                end
                fprintf('SurfaceArea3D: saving SurfaceArea structure to a file:\n%s\n', outFn);
            end

            % Add annotations and refresh display
            obj.mibModel.I{id}.annotations.addLabels(labelList, positionList, labelValues);
            obj.mibModel.mibAnnMarkerEdit        = 'label';
            obj.mibModel.mibShowAnnotationsCheck = 1;
            notify(obj.mibModel, 'UpdateAnnotations');
            notify(obj.mibModel, 'ShowImage');

            close(progressDialog);
        end

        % -----------------------------------------------------------------
        function saveToCSV(obj, SurfaceArea, outFn)
        % SAVETOCSV - Write surface area results to a CSV file.
        %
        % Columns: SurfaceId, Time, Z, X, Y, SurfaceArea.  Centroid
        % coordinates are in dataset physical units (pixels × pixel size).
        %
        % Parameters:
        % **SurfaceArea** — struct array produced by ``continueBtn_Callback``
        % **outFn** — full path of the output ``.csv`` file

            SurfaceId = (1:numel(SurfaceArea))';
            centMat   = cat(1, SurfaceArea.Centroid);
            Time      = centMat(:,4);
            Z         = centMat(:,3);
            X         = centMat(:,1);
            Y         = centMat(:,2);
            SurfArea  = [SurfaceArea.SumAreaTotal]';
            T = table(SurfaceId, Time, Z, X, Y, SurfArea, 'VariableNames', ...
                {'SurfaceId','Time','Z','X','Y','SurfaceArea'});
            writetable(T, outFn);
        end

        % -----------------------------------------------------------------
        function saveToExcel(obj, SurfaceArea, outFn)
        % SAVETOEXCEL - Write surface area results to an Excel workbook.
        %
        % Sheet *General results* contains a header block with image path,
        % model filename, material name, pixel size, and sampling
        % parameters, followed by a per-object table (SurfaceId, Time,
        % Z, X, Y, SurfaceArea).
        %
        % Parameters:
        % **SurfaceArea** — struct array produced by ``continueBtn_Callback``
        % **outFn** — full path of the output ``.xlsx`` file

            id = obj.mibModel.getActiveId();
            warning('off', 'MATLAB:xlswrite:AddSheet');

            s = {'SurfaceArea3D: calculate area of surfaces in 3D'};
            s(2,1) = {['Image directory:      ' fileparts(obj.mibModel.I{id}.image.filename)]};
            s(3,1) = {['Model filename:       ' obj.mibModel.I{id}.labels.filename]};
            s(4,1) = {['Main object material: ' SurfaceArea(1).MaterialName]};
            s(5,1) = {sprintf('Pixel size [x,y,z]/units: %fx%fx%f %s', ...
                SurfaceArea(1).pixSize.x, SurfaceArea(1).pixSize.y, ...
                SurfaceArea(1).pixSize.z, SurfaceArea(1).pixSize.units)};

            s(4,8) = {sprintf('XY Smooth Value, px: %d',   SurfaceArea(1).xySmoothValue)};
            s(5,8) = {sprintf('XY Sampling Step, px: %d',  SurfaceArea(1).xySamplingStep)};
            s(6,8) = {sprintf('Z Sampling Step, px: %d',   SurfaceArea(1).zSamplingStep)};

            s(8,1) = {'SurfaceId'}; s(8,2) = {'Time'}; s(8,3) = {'Z'}; ...
            s(8,4) = {'X'};         s(8,5) = {'Y'};    s(8,6) = {'SurfaceArea'};

            shiftY = 8;
            for objId = 1:numel(SurfaceArea)
                s(shiftY+objId, 1) = {num2str(objId)};
                s(shiftY+objId, 2) = {num2str(SurfaceArea(objId).Centroid(4))};
                s(shiftY+objId, 3) = {num2str(SurfaceArea(objId).Centroid(3))};
                s(shiftY+objId, 4) = {num2str(SurfaceArea(objId).Centroid(1))};
                s(shiftY+objId, 5) = {num2str(SurfaceArea(objId).Centroid(2))};
                s(shiftY+objId, 6) = {num2str(SurfaceArea(objId).SumAreaTotal)};
            end
            xlswrite2(outFn, s, 'General results', 'A1');
        end

    end  % methods

end
