classdef SurfaceMeasurements < handle
% SurfaceMeasurements < handle
% Plugin controller that renders the current segmentation model as a
% triangular mesh and exports per-object and per-material surface area /
% volume statistics to Excel files.
%
% Rendering logic is adapted from mibRenderModel.m; quantification uses
% the signed-tetrahedra volume formula and the cross-product triangle area.
%
% @b Usage:
% @code
%   controller = plugins.OrganelleAnalysis.SurfaceMeasurements.SurfaceMeasurements(mibModel);
% @endcode

% Author: Ilya Belevich, University of Helsinki (ilya.belevich @ helsinki.fi)
% URL: https://mib.helsinki.fi
% Date: 28.04.2026

    properties
        mibModel            % handle to MibModel
        view                % handle to the AppDesigner view (core.ChildView wrapper)
        listener            % cell array of event listeners
        childControllers    = {}
        childControllersIds = {}
    end

    events
        CloseEvent
    end

    methods (Static)

        function ViewListner_Callback2(obj, ~, evnt)
        % ViewListner_Callback2  React to MibModel events.
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
        function obj = SurfaceMeasurements(mibModel, varargin)
        % SurfaceMeasurements  Constructor — initialises plugin controller and GUI.
        %
        % Parameters:
        % mibModel: handle to the MibModel instance
        % varargin: [@em optional] unused; reserved for batch options

            obj.mibModel = mibModel;

            obj.view = core.ChildView(obj, 'SurfaceMeasurementsGUI');
            obj.view.gui = utils.moveWindowOutside(obj.view.gui, obj.mibModel.mibGUI, 'left');

            % Window icon
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
            if obj.view.handles.infoText1.FontSize ~= Font.FontSize || ...
                    ~strcmp(obj.view.handles.infoText1.FontName, Font.FontName)
                utils.fontSizeUpdate(obj.view.gui, Font);
            end

            obj.view.gui.CloseRequestFcn = @(~,~) obj.closeWindow();

            obj.updateWidgets();

            obj.listener{1} = addlistener(obj.mibModel, 'UpdateGuiWidgets', ...
                @(src, evnt) obj.ViewListner_Callback2(obj, src, evnt));
            obj.listener{2} = addlistener(obj.mibModel, 'NewDataset', ...
                @(src, evnt) obj.ViewListner_Callback2(obj, src, evnt));
        end

        % -----------------------------------------------------------------
        function closeWindow(obj)
        % closeWindow  Close the plugin window and release all resources.

            for i = numel(obj.childControllers):-1:1
                child = obj.childControllers{i};
                if isa(child, 'handle') && isvalid(child)
                    child.closeWindow();
                end
            end
            obj.childControllers    = {};
            obj.childControllersIds = {};

            if isvalid(obj.view.gui)
                obj.view.gui.CloseRequestFcn = '';
                delete(obj.view.gui);
            end

            for i = 1:numel(obj.listener)
                delete(obj.listener{i});
            end

            notify(obj, 'CloseEvent');
        end

        % -----------------------------------------------------------------
        function updateWidgets(obj)
        % updateWidgets  Refresh GUI widgets from the current dataset state.

            id = obj.mibModel.getActiveId();
            imageFilename = obj.mibModel.I{id}.image.filename;
            [outputDir, ~, ~] = fileparts(imageFilename);
            if isempty(outputDir)
                outputDir = obj.mibModel.mibPath;
            end
            obj.view.handles.outputDirEdit.Value = outputDir;

            obj.view.handles.materialsEdit.Value = '0';
            obj.view.handles.reduceEdit.Value    = '500';
            obj.view.handles.smoothEdit.Value    = '5';
            obj.view.handles.maxFacesEdit.Value  = '300000';
        end

        % -----------------------------------------------------------------
        function selectDirButton_Callback(obj)
        % selectDirButton_Callback  Browse for output directory.

            currentDir = obj.view.handles.outputDirEdit.Value;
            if ~isfolder(currentDir)
                currentDir = pwd;
            end
            selectedDir = uigetdir(currentDir, 'Select output directory');
            if selectedDir ~= 0
                obj.view.handles.outputDirEdit.Value = selectedDir;
            end
        end

        % -----------------------------------------------------------------
        function runButton_Callback(obj)
        % runButton_Callback  Generate 3-D mesh, compute measurements, write Excel.
        %
        % Steps:
        %   1. Read and validate widget values.
        %   2. Load labels volume and metadata from MibModel.
        %   3. For each requested material: smooth → reduce → isosurface.
        %   4. Scale vertices to physical units.
        %   5. Split mesh into connected components; compute area and volume.
        %   6. Render material mesh in a shared figure.
        %   7. Write per-object and per-material tables to Excel.

            % --- 1. Widget values ----------------------------------------
            id = obj.mibModel.getActiveId();

            materialsStr = strtrim(obj.view.handles.materialsEdit.Value);
            reduceVal    = str2double(strtrim(obj.view.handles.reduceEdit.Value));
            smoothVal    = str2double(strtrim(obj.view.handles.smoothEdit.Value));
            maxFacesVal  = str2double(strtrim(obj.view.handles.maxFacesEdit.Value));
            outputDir    = strtrim(obj.view.handles.outputDirEdit.Value);

            if isnan(reduceVal) || reduceVal < 0
                utils.dlgs.showErrorDialog(obj.view.gui, ...
                    '"Reduce" must be a non-negative number.', 'Invalid input');
                return;
            end
            if isnan(smoothVal) || smoothVal < 0
                utils.dlgs.showErrorDialog(obj.view.gui, ...
                    '"Smooth" must be a non-negative number.', 'Invalid input');
                return;
            end
            if isnan(maxFacesVal) || maxFacesVal < 0
                utils.dlgs.showErrorDialog(obj.view.gui, ...
                    '"Max faces" must be a non-negative number.', 'Invalid input');
                return;
            end

            % --- 2. Model existence check ---------------------------------
            if ~obj.mibModel.I{id}.modelExist
                utils.dlgs.showErrorDialog(obj.view.gui, ...
                    'No segmentation model is loaded. Please create or load a model first.', ...
                    'No model');
                return;
            end

            % --- 3. Load labels volume and metadata -----------------------
            options.blockModeSwitch = 0;
            labelsCell = obj.mibModel.getData3D('labels', [], 3, [], options);
            labelsVolume = labelsCell{1};  % [height × width × depth]

            materialNames  = obj.mibModel.I{id}.labels.materialNames;
            materialColors = obj.mibModel.I{id}.labels.materialColors;  % Nx3, 0-1
            pixSize        = obj.mibModel.I{id}.image.pixSize;
            boundingBox    = obj.mibModel.I{id}.image.boundingBox;  % [xMin xMax yMin yMax zMin zMax]

            numMaterials = numel(materialNames);
            if numMaterials == 0
                utils.dlgs.showErrorDialog(obj.view.gui, ...
                    'The model has no materials.', 'Empty model');
                return;
            end

            % --- 4. Parse material indices --------------------------------
            materialIndices = str2num(materialsStr); %#ok<ST2NM>
            if isempty(materialIndices) || (isscalar(materialIndices) && materialIndices == 0)
                materialIndices = 1:numMaterials;
            end
            % Clamp to valid range
            materialIndices = materialIndices(materialIndices >= 1 & materialIndices <= numMaterials);
            if isempty(materialIndices)
                utils.dlgs.showErrorDialog(obj.view.gui, ...
                    'No valid material indices after filtering. Check the Materials field.', ...
                    'Invalid materials');
                return;
            end

            % --- 5. Reduction and smoothing factors -----------------------
            if reduceVal > 0
                factorX = ceil(size(labelsVolume, 2) / reduceVal);
                factorY = ceil(factorX * pixSize.x / pixSize.y - 0.001);
                factorZ = ceil(factorX * pixSize.x / pixSize.z);
            else
                factorX = 1;
                factorY = 1;
                factorZ = 1;
            end
            factorX = max(factorX, 1);
            factorY = max(factorY, 1);
            factorZ = max(factorZ, 1);

            kernelX = smoothVal;
            if kernelX > 0
                kernelY = round(kernelX * pixSize.x / pixSize.y) + ...
                    abs(mod(round(kernelX * pixSize.x / pixSize.y), 2) - 1);
                kernelZ = round(kernelX * pixSize.x / pixSize.z) + ...
                    abs(mod(round(kernelX * pixSize.x / pixSize.z), 2) - 1);
                kernelY = max(kernelY, 1);
                kernelZ = max(kernelZ, 1);
            else
                kernelY = 0;
                kernelZ = 0;
            end

            % --- 6. Unit-to-micron conversion factor ----------------------
            unitFactor = obj.unitToUmFactor(pixSize.units);

            % --- 7. Prepare rendering figure ------------------------------
            renderFig = figure(12347);

            clf;
            daspect([1 1 1]);
            hold on;

            % --- 8. Output file paths ------------------------------------
            imageFilename = obj.mibModel.I{id}.image.filename;
            [~, baseFilename, ~] = fileparts(imageFilename);
            if isempty(baseFilename)
                baseFilename = 'SurfaceMeasurements';
            end
            objFile = fullfile(outputDir, [baseFilename '_SurfVolObj.xlsx']);
            matFile = fullfile(outputDir, [baseFilename '_SurfVols.xlsx']);

            % --- 9. Progress dialog ---------------------------------------
            progressDialog = uiprogressdlg(obj.view.gui, ...
                'Title', 'Surface Measurements', ...
                'Message', 'Initialising...', ...
                'Value', 0, ...
                'Cancelable', 'on');

            % --- 10. Preallocate result rows ------------------------------
            objRows = {};  % {materialName, objectId, isClosed, area_um2, vol_um3}
            matRows = {};  % {materialName, numObj, numClosed, totalArea, totalVol}

            bb = boundingBox;

            try
                numMat = numel(materialIndices);
                for matLoopIdx = 1:numMat
                    materialIdx = materialIndices(matLoopIdx);

                    % Check for user cancellation
                    if progressDialog.CancelRequested
                        break;
                    end

                    materialName = materialNames{materialIdx};
                    if size(materialColors, 1) >= materialIdx
                        faceColor = materialColors(materialIdx, :);
                    else
                        faceColor = rand(1, 3);
                    end

                    progressDialog.Value   = (matLoopIdx - 1) / numMat;
                    progressDialog.Message = sprintf('Material %d/%d: %s — smoothing...', ...
                        matLoopIdx, numMat, materialName);

                    % Binary sub-volume for this material
                    subVolume = uint8(labelsVolume == materialIdx);

                    % Smooth
                    if kernelX > 0
                        subVolume = uint8(smooth3(subVolume, 'box', [kernelX kernelY kernelZ]));
                    end

                    progressDialog.Message = sprintf('Material %d/%d: %s — reducing...', ...
                        matLoopIdx, numMat, materialName);

                    % Reduce volume resolution
                    [~, ~, ~, subVolumeReduced] = reducevolume(subVolume, [factorX factorY factorZ]);

                    progressDialog.Message = sprintf('Material %d/%d: %s — isosurface...', ...
                        matLoopIdx, numMat, materialName);

                    % Extract isosurface
                    [faces, verts] = isosurface(subVolumeReduced, 0.5);

                    if isempty(verts)
                        % Record zero-object entry for this material
                        matRows(end+1, :) = {materialName, 0, 0, 0, 0}; %#ok<AGROW>
                        continue;
                    end

                    % Scale vertices to physical units
                    verts(:, 1) = verts(:, 1) * pixSize.x * factorX + bb(1) - pixSize.x * factorX;
                    verts(:, 2) = verts(:, 2) * pixSize.y * factorY + bb(3) - pixSize.y * factorY;
                    verts(:, 3) = verts(:, 3) * pixSize.z * factorZ + bb(5) - pixSize.z * factorZ;

                    progressDialog.Message = sprintf('Material %d/%d: %s — connected components...', ...
                        matLoopIdx, numMat, materialName);

                    % Split mesh into connected components via graph
                    numVerts = size(verts, 1);
                    edgeList = [faces(:,1) faces(:,2); ...
                                faces(:,2) faces(:,3); ...
                                faces(:,1) faces(:,3)];
                    meshGraph  = graph(edgeList(:,1), edgeList(:,2), [], numVerts);
                    componentIds = conncomp(meshGraph);  % 1 × numVerts

                    uniqueComponents = unique(componentIds);
                    numComponents    = numel(uniqueComponents);

                    totalAreaMaterial = 0;
                    totalVolMaterial  = 0;
                    numClosedObjects  = 0;

                    for compLoopIdx = 1:numComponents
                        targetCompId = uniqueComponents(compLoopIdx);
                        [componentFaces, componentVerts] = obj.extractComponent( ...
                            faces, verts, componentIds, targetCompId);

                        areaNative = obj.computeSurfaceArea(componentFaces, componentVerts);
                        isClosed   = obj.isClosedMesh(componentFaces);

                        if isClosed
                            volumeNative = obj.computeMeshVolume(componentFaces, componentVerts);
                            numClosedObjects = numClosedObjects + 1;
                        else
                            volumeNative = NaN;
                        end

                        areaMicron2 = areaNative  * unitFactor^2;
                        if ~isnan(volumeNative)
                            volumeMicron3 = volumeNative * unitFactor^3;
                        else
                            volumeMicron3 = NaN;
                        end

                        totalAreaMaterial = totalAreaMaterial + areaMicron2;
                        if ~isnan(volumeMicron3)
                            totalVolMaterial = totalVolMaterial + volumeMicron3;
                        end

                        objRows(end+1, :) = {materialName, compLoopIdx, isClosed, ...
                            areaMicron2, volumeMicron3}; %#ok<AGROW>
                    end

                    % Render material mesh in 3-D figure
                    progressDialog.Message = sprintf('Material %d/%d: %s — rendering...', ...
                        matLoopIdx, numMat, materialName);

                    patchHandle = patch('Faces', faces, 'Vertices', verts, ...
                        'FaceColor', faceColor, 'EdgeColor', 'none', ...
                        'AmbientStrength', 0.3);

                    if maxFacesVal > 0
                        reducepatch(patchHandle, maxFacesVal);
                    end

                    matRows(end+1, :) = {materialName, numComponents, numClosedObjects, ...
                        totalAreaMaterial, totalVolMaterial}; %#ok<AGROW>
                end  % for each material

            catch renderError
                close(progressDialog);
                utils.dlgs.showErrorDialog(obj.view.gui, ...
                    sprintf('Error during processing:\n%s', renderError.message), ...
                    'Processing error');
                return;
            end

            % --- 11. Finalise 3-D figure ----------------------------------
            set(gca, 'projection', 'perspective');
            lighting gouraud;
            camlight('headlight');
            axis tight;
            grid;
            %view3d(renderFig, 'rot');
            hold off;

            % --- 12. Build and write tables -------------------------------
            progressDialog.Message = 'Writing Excel files...';
            progressDialog.Value   = 0.95;

            try
                if ~isempty(objRows)
                    objTable = cell2table(objRows, ...
                        'VariableNames', {'MaterialName', 'ObjectId', 'IsClosed', ...
                                          'SurfaceArea_um2', 'Volume_um3'});
                    writetable(objTable, objFile);
                end

                if ~isempty(matRows)
                    matTable = cell2table(matRows, ...
                        'VariableNames', {'MaterialName', 'NumObjects', 'NumClosedObjects', ...
                                          'SurfaceArea_um2', 'Volume_um3'});
                    writetable(matTable, matFile);
                end
            catch writeError
                close(progressDialog);
                utils.dlgs.showErrorDialog(obj.view.gui, ...
                    sprintf('Error writing Excel files:\n%s', writeError.message), ...
                    'Write error');
                return;
            end

            close(progressDialog);

            % --- 13. Notify user -----------------------------------------
            dlgOpt.MsgBoxOnly  = true;
            dlgOpt.Icon        = 'puffin_info';
            dlgOpt.HeaderLines = 1;
            utils.dlgs.inputUniversalDlg(obj.view.gui, ...
                'Measurements saved:', ...
                {''}, ...
                {sprintf('Per-object: %s\nPer-material: %s', objFile, matFile)}, ...
                'Done', dlgOpt);
        end

    end  % methods

    methods (Access = private)

        % -----------------------------------------------------------------
        function area = computeSurfaceArea(~, faces, verts)
        % computeSurfaceArea  Total surface area of a triangular mesh.
        %
        % Parameters:
        % faces: [Nf x 3] vertex indices
        % verts: [Nv x 3] vertex coordinates
        %
        % Return values:
        % area: scalar total surface area in the same units as verts

            vertex1 = verts(faces(:,1), :);
            vertex2 = verts(faces(:,2), :);
            vertex3 = verts(faces(:,3), :);
            crossVectors = cross(vertex2 - vertex1, vertex3 - vertex1, 2);
            area = 0.5 * sum(sqrt(sum(crossVectors.^2, 2)));
        end

        % -----------------------------------------------------------------
        function volume = computeMeshVolume(~, faces, verts)
        % computeMeshVolume  Signed-tetrahedra volume formula for closed meshes.
        %
        % Only valid for closed (watertight) meshes.  Call isClosedMesh() first.
        %
        % Parameters:
        % faces: [Nf x 3] vertex indices
        % verts: [Nv x 3] vertex coordinates
        %
        % Return values:
        % volume: scalar volume in cubic units matching verts

            vertex1 = verts(faces(:,1), :);
            vertex2 = verts(faces(:,2), :);
            vertex3 = verts(faces(:,3), :);
            volume = abs(sum(dot(vertex1, cross(vertex2, vertex3, 2), 2))) / 6;
        end

        % -----------------------------------------------------------------
        function isClosed = isClosedMesh(~, faces)
        % isClosedMesh  Return true if every edge is shared by exactly two faces.
        %
        % Parameters:
        % faces: [Nf x 3] vertex indices
        %
        % Return values:
        % isClosed: logical scalar

            allEdges   = sort([faces(:,[1 2]); faces(:,[2 3]); faces(:,[1 3])], 2);
            [~, ~, ic] = unique(allEdges, 'rows');
            edgeCounts = accumarray(ic, 1);
            isClosed   = all(edgeCounts == 2);
        end

        % -----------------------------------------------------------------
        function [componentFaces, componentVerts] = extractComponent(~, faces, verts, componentIds, targetId)
        % extractComponent  Extract a single connected component from a mesh.
        %
        % Parameters:
        % faces: [Nf x 3] vertex indices (global)
        % verts: [Nv x 3] vertex coordinates
        % componentIds: [1 x Nv] component label per vertex (from conncomp)
        % targetId: scalar component label to extract
        %
        % Return values:
        % componentFaces: [nf x 3] re-indexed face list for the component
        % componentVerts: [nv x 3] vertex coordinates for the component

            vertMask      = (componentIds == targetId);
            facesMask     = all(vertMask(faces), 2);
            componentFaces = faces(facesMask, :);

            usedVertices = unique(componentFaces);
            remapTable   = zeros(1, size(verts, 1));
            remapTable(usedVertices) = 1:numel(usedVertices);
            componentFaces = remapTable(componentFaces);
            componentVerts = verts(usedVertices, :);
        end

        % -----------------------------------------------------------------
        function factor = unitToUmFactor(~, units)
        % unitToUmFactor  Conversion factor from the dataset length unit to microns.
        %
        % Parameters:
        % units: string length unit stored in pixSize.units
        %
        % Return values:
        % factor: scalar multiplier so that value_in_units * factor = value_in_um

            switch units
                case 'nm';  factor = 1e-3;
                case 'um';  factor = 1;
                case 'mm';  factor = 1e3;
                case 'cm';  factor = 1e4;
                case 'm';   factor = 1e6;
                otherwise;  factor = 1;
            end
        end

    end  % methods (Access = private)

end
