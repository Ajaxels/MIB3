classdef Granularity < handle
% Granularity < handle
% Plugin controller for granularity analysis of organelle shapes.
% Calculates the ratio of tubular to total area/volume using morphological
% opening (erosion + dilation) with a configurable structuring element.
%
% @code
%   controller = plugins.OrganelleAnalysis.Granularity.Granularity(mibModel);
% @endcode

    properties
        mibModel
        % handle to MibModel
        view
        % handle to the AppDesigner view (core.ChildView wrapper)
        listener
        % cell array of event listeners
        matlabExportVariable
        % variable name for workspace export of results
        mode
        % analysis mode string: 'image2D' | 'timelapse2D' | 'volume3D'
        se
        % structuring element (logical array)
        subarea
        % struct with selected subarea: .x [min max], .y [min max], .z [min max]
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
        function obj = Granularity(mibModel)
        % Granularity  Constructor — initialises controller and GUI.
        %
        % Parameters:
        % mibModel: handle to the MibModel instance

            obj.mibModel = mibModel;
            id = obj.mibModel.getActiveId();

            % check for virtual stacking mode — not supported
            if isprop(obj.mibModel.I{id}, 'Virtual') && obj.mibModel.I{id}.Virtual.virtual == 1
                dlgOpt.MsgBoxOnly = true;
                dlgOpt.Icon = 'puffin_warning';
                utils.dlgs.inputUniversalDlg(obj.mibModel.mibGUI, '', ...
                    {''}, {'This plugin is not compatible with the virtual stacking mode!\nPlease switch to the memory-resident mode and try again'}, ...
                    'Not implemented', dlgOpt);
                notify(obj, 'CloseEvent');
                return;
            end

            obj.subarea = struct();
            obj.mode = 'image2D';
            obj.matlabExportVariable = 'Granularity';

            obj.view = core.ChildView(obj, 'GranularityGUI');
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
            if obj.view.handles.strelTypePopup.FontSize ~= Font.FontSize ...
                    || ~strcmp(obj.view.handles.strelTypePopup.FontName, Font.FontName)
                utils.fontSizeUpdate(obj.view.gui, Font);
            end

            % preview strel button icon
            previewIcon = fullfile(obj.mibModel.mibPath, 'assets', 'icons', 'view_settings_16px.png');
            if isfile(previewIcon)
                obj.view.handles.previewStrelBtn.Icon = previewIcon;
            end

            obj.updateWidgets();
            obj.updateStrel_Callback();

            % default output filename
            [filePath, fileName] = fileparts(obj.mibModel.I{id}.image.filename);
            outputFilename = fullfile(filePath, [fileName '_Granularity.xlsx']);
            obj.view.handles.filenameEdit.Value   = outputFilename;
            obj.view.handles.filenameEdit.Tooltip = outputFilename;

            obj.listener{1} = addlistener(obj.mibModel, 'UpdateGuiWidgets', ...
                @(src, evnt) obj.ViewListner_Callback2(obj, src, evnt));
            obj.listener{2} = addlistener(obj.mibModel, 'NewDataset', ...
                @(src, evnt) obj.ViewListner_Callback2(obj, src, evnt));

            obj.view.gui.Visible = true;
        end

        % -----------------------------------------------------------------
        function addCallbacks(obj)
        % addCallbacks  Wire all widget callbacks; always called once from constructor.
            obj.view.gui.CloseRequestFcn = @(~,~) obj.closeWindow();
            handles = obj.view.handles;

            % mode radio button group
            handles.modeButtonGroup.SelectionChangedFcn     = @(~, evnt) obj.modeRadio_Callback(evnt.NewValue);

            % subarea controls
            handles.resetDimsBtn.ButtonPushedFcn            = @(~,~) obj.resetSubarea();
            handles.currentViewBtn.ButtonPushedFcn          = @(~,~) obj.currentViewBtn_Callback();
            handles.subAreaFromSelectionBtn.ButtonPushedFcn = @(~,~) obj.subAreaFromSelectionBtn_Callback();
            handles.xSubareaEdit.ValueChangedFcn            = @(h,~) obj.updateSubarea(h);
            handles.ySubareaEdit.ValueChangedFcn            = @(h,~) obj.updateSubarea(h);
            handles.zSubareaEdit.ValueChangedFcn            = @(h,~) obj.updateSubarea(h);

            % strel controls (strelSizeEdit / strelSizeZEdit / strelRotationsEdit are uispinners)
            handles.strelTypePopup.ValueChangedFcn          = @(~,~) obj.updateStrel_Callback();
            handles.strelSizeEdit.ValueChangedFcn           = @(~,~) obj.updateStrel_Callback();
            handles.strelSizeZEdit.ValueChangedFcn          = @(~,~) obj.updateStrel_Callback();
            handles.strelRotationsEdit.ValueChangedFcn      = @(~,~) obj.updateStrel_Callback();
            handles.previewStrelBtn.ButtonPushedFcn         = @(~,~) obj.previewStrelBtn_Callback();

            % source material
            handles.updateMaterialsBtn.ButtonPushedFcn     = @(~,~) obj.updateMaterialsBtn_Callback();

            % export controls
            handles.exportFileCheck.ValueChangedFcn         = @(~,~) obj.exportFileCheck_Callback();
            handles.exportResultsFilename.ButtonPushedFcn   = @(~,~) obj.exportResultsFilename_Callback();
            handles.exportMatlabCheck.ValueChangedFcn       = @(~,~) obj.exportMatlabCheck_Callback();

            % action / close / help
            handles.calculateBtn.ButtonPushedFcn            = @(~,~) obj.calculateBtn_Callback();
            handles.closeBtn.ButtonPushedFcn                = @(~,~) obj.closeWindow();
            handles.helpBtn.ButtonPushedFcn                 = @(~,~) obj.helpBtn_Callback();

            % --- tooltips ------------------------------------------------
            handles.image2D.Tooltip         = 'Analyze the currently shown 2D image slice only';
            handles.timelapse2D.Tooltip     = 'Analyze each slice independently as a 2D image (z-stack or timelapse)';
            handles.volume3D.Tooltip        = 'Analyze the full 3D volume; the structuring element is rotated through all orientations';

            handles.xSubareaEdit.Tooltip    = 'X pixel range for the analysis subarea — format: start:end (e.g. 1:512)';
            handles.ySubareaEdit.Tooltip    = 'Y pixel range for the analysis subarea — format: start:end (e.g. 1:512)';
            handles.zSubareaEdit.Tooltip    = 'Z slice range for the analysis subarea — format: start:end (e.g. 1:50)';
            handles.resetDimsBtn.Tooltip    = 'Reset the subarea to cover the full dataset dimensions';
            handles.currentViewBtn.Tooltip  = 'Set the XY subarea to the region currently visible in the Image View panel';
            handles.subAreaFromSelectionBtn.Tooltip = 'Set the subarea bounding box from the bounding box of the current Selection layer';

            handles.strelTypePopup.Tooltip      = 'Shape of the structuring element: disk = circle, rectangle = square, sphere = cross-section of a sphere';
            handles.strelSizeEdit.Tooltip       = 'XY radius of the structuring element in pixels';
            handles.strelSizeZEdit.Tooltip      = 'Z radius in voxels (volume3D mode only); set to 0 to use a flat disc at every Z level';
            handles.strelRotationsEdit.Tooltip  = 'Number of angular steps for 3D rotation of the structuring element — higher = more accurate but slower';
            handles.previewStrelBtn.Tooltip     = 'Preview the current structuring element shape in a figure window';

            handles.sourceMaterialPopup.Tooltip = 'Layer to analyse: ''Mask'' for the binary mask, or a material from the loaded model';
            handles.updateMaterialsBtn.Tooltip  = 'Refresh the material list from the currently loaded model';
            handles.useROICheck.Tooltip         = 'Restrict analysis to the currently selected ROI region (requires at least one ROI to be defined)';

            handles.exportFileCheck.Tooltip          = 'Save analysis results to an Excel (.xlsx) or Matlab (.mat) file';
            handles.filenameEdit.Tooltip             = 'Full path of the output results file';
            handles.exportResultsFilename.Tooltip    = 'Browse for output file location and name';
            handles.exportMatlabCheck.Tooltip        = 'Export the Granularity results structure to the Matlab base workspace under the specified variable name';

            handles.calculateBtn.Tooltip = 'Run the granularity analysis; the morphological opening result is written to the Selection layer';
            handles.closeBtn.Tooltip     = 'Close the Granularity plugin';
            handles.helpBtn.Tooltip      = 'Open the online help documentation in a browser';
        end

        % -----------------------------------------------------------------
        function closeWindow(obj)
        % closeWindow  Close the plugin window and release all resources.
            if isvalid(obj.view.gui)
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

            if obj.mibModel.I{id}.image.depth < 2
                obj.view.handles.timelapse2D.Enable = 'off';
                obj.view.handles.volume3D.Enable    = 'off';
                obj.view.handles.modeButtonGroup.SelectedObject = obj.view.handles.image2D;
            else
                obj.view.handles.timelapse2D.Enable = 'on';
                obj.view.handles.volume3D.Enable    = 'on';
            end

            if obj.mibModel.I{id}.hROI.getNumberOfROI(0) > 0
                obj.view.handles.useROICheck.Enable = 'on';
            else
                obj.view.handles.useROICheck.Enable = 'off';
                obj.view.handles.useROICheck.Value  = false;
            end

            obj.updateMaterialsBtn_Callback();

            if ~isfield(obj.subarea, 'x'); obj.resetSubarea(); end
        end

        % -----------------------------------------------------------------
        function modeRadio_Callback(obj, hObject)
        % modeRadio_Callback  Handle mode ButtonGroup selection change.
        %
        % Parameters:
        % hObject: handle to the newly selected radio button (evnt.NewValue)
            obj.mode = hObject.Tag;
            if strcmp(obj.mode, 'volume3D')
                obj.view.handles.strelSizeZEdit.Enable     = 'on';
                obj.view.handles.strelRotationsEdit.Enable = 'on';
                obj.view.handles.strelTypePopup.Value      = 'sphere';
                obj.view.handles.useROICheck.Value         = false;
                obj.view.handles.useROICheck.Enable        = 'off';
            else
                obj.view.handles.strelSizeZEdit.Enable     = 'off';
                obj.view.handles.strelRotationsEdit.Enable = 'off';
                obj.view.handles.useROICheck.Enable        = 'on';
            end
            obj.updateStrel_Callback();
        end

        % -----------------------------------------------------------------
        function resetSubarea(obj)
        % resetSubarea  Reset the subarea edit boxes to the full dataset extent.
            id = obj.mibModel.getActiveId();
            obj.subarea.x = [1, obj.mibModel.I{id}.image.width];
            obj.subarea.y = [1, obj.mibModel.I{id}.image.height];
            obj.subarea.z = [1, obj.mibModel.I{id}.image.depth];
            obj.view.handles.xSubareaEdit.Value = sprintf('%d:%d', obj.subarea.x(1), obj.subarea.x(2));
            obj.view.handles.ySubareaEdit.Value = sprintf('%d:%d', obj.subarea.y(1), obj.subarea.y(2));
            obj.view.handles.zSubareaEdit.Value = sprintf('%d:%d', obj.subarea.z(1), obj.subarea.z(2));
        end

        % -----------------------------------------------------------------
        function updateSubarea(obj, hObject)
        % updateSubarea  Validate a subarea edit box entry and update obj.subarea.
        %
        % Parameters:
        % hObject: handle to the changed uitextfield (xSubareaEdit / ySubareaEdit / zSubareaEdit)
            typedValue = str2num(hObject.Value); %#ok<ST2NM>
            id = obj.mibModel.getActiveId();
            switch hObject.Tag
                case 'xSubareaEdit'; maxVal = obj.mibModel.I{id}.image.width;  fieldName = 'x';
                case 'ySubareaEdit'; maxVal = obj.mibModel.I{id}.image.height; fieldName = 'y';
                case 'zSubareaEdit'; maxVal = obj.mibModel.I{id}.image.depth;  fieldName = 'z';
            end
            if isempty(typedValue) || min(typedValue) < 1 || max(typedValue) > maxVal
                hObject.Value = sprintf('%d:%d', obj.subarea.(fieldName)(1), obj.subarea.(fieldName)(2));
                hObject.BackgroundColor = [1 0 0];
                utils.dlgs.showErrorDialog(obj.view.gui, 'Please check the values!', 'Wrong dimensions!');
                return;
            end
            obj.subarea.(fieldName)(1) = min(typedValue);
            obj.subarea.(fieldName)(2) = max(typedValue);
            hObject.BackgroundColor = [1 1 1];
        end

        % -----------------------------------------------------------------
        function currentViewBtn_Callback(obj)
        % currentViewBtn_Callback  Set subarea to the currently displayed image area.
            id = obj.mibModel.getActiveId();
            [yMin, yMax, xMin, xMax] = obj.mibModel.I{id}.getCoordinatesOfShownImage();
            obj.view.handles.xSubareaEdit.Value = sprintf('%d:%d', xMin, xMax);
            obj.view.handles.ySubareaEdit.Value = sprintf('%d:%d', yMin, yMax);
            obj.subarea.x = [xMin, xMax];
            obj.subarea.y = [yMin, yMax];
        end

        % -----------------------------------------------------------------
        function subAreaFromSelectionBtn_Callback(obj)
        % subAreaFromSelectionBtn_Callback  Derive subarea bounding box from Selection layer.
            id = obj.mibModel.getActiveId();
            bgColor = obj.view.handles.subAreaFromSelectionBtn.BackgroundColor;
            obj.view.handles.subAreaFromSelectionBtn.BackgroundColor = [1 0 0];
            drawnow;

            if strcmp(obj.mode, 'image2D')
                selectionCell = obj.mibModel.getData2D('selection', [], [], [], []);
                img = selectionCell{1};
                STATS = regionprops(img, 'BoundingBox');
                if numel(STATS) == 0
                    utils.dlgs.showErrorDialog(obj.view.gui, ...
                        sprintf('Selection layer was not found!\nPlease make sure that the Selection layer\nis shown in the Image View panel'), ...
                        'Missing Selection');
                    obj.resetSubarea();
                    obj.view.handles.subAreaFromSelectionBtn.BackgroundColor = bgColor;
                    return;
                end
                xStart = ceil(STATS(1).BoundingBox(1));
                yStart = ceil(STATS(1).BoundingBox(2));
                obj.view.handles.xSubareaEdit.Value = sprintf('%d:%d', xStart, xStart + STATS(1).BoundingBox(3) - 1);
                obj.view.handles.ySubareaEdit.Value = sprintf('%d:%d', yStart, yStart + STATS(1).BoundingBox(4) - 1);
                obj.subarea.x = [xStart, xStart + STATS(1).BoundingBox(3) - 1];
                obj.subarea.y = [yStart, yStart + STATS(1).BoundingBox(4) - 1];
            else
                selectionCell = obj.mibModel.getData3D('selection', [], 3, [], []);
                img = selectionCell{1};
                STATS = regionprops(img, 'BoundingBox');
                if numel(STATS) == 0
                    utils.dlgs.showErrorDialog(obj.view.gui, ...
                        sprintf('Selection layer was not found!\nPlease make sure that the Selection layer\nis shown in the Image View panel'), ...
                        'Missing Selection');
                    obj.resetSubarea();
                    obj.view.handles.subAreaFromSelectionBtn.BackgroundColor = bgColor;
                    return;
                end
                xStart = ceil(STATS(1).BoundingBox(1));
                yStart = ceil(STATS(1).BoundingBox(2));
                zStart = ceil(STATS(1).BoundingBox(3));
                obj.view.handles.xSubareaEdit.Value = sprintf('%d:%d', xStart, xStart + STATS(1).BoundingBox(4) - 1);
                obj.view.handles.ySubareaEdit.Value = sprintf('%d:%d', yStart, yStart + STATS(1).BoundingBox(5) - 1);
                obj.view.handles.zSubareaEdit.Value = sprintf('%d:%d', zStart, zStart + STATS(1).BoundingBox(6) - 1);
                obj.subarea.x = [xStart, xStart + STATS(1).BoundingBox(4) - 1];
                obj.subarea.y = [yStart, yStart + STATS(1).BoundingBox(5) - 1];
                obj.subarea.z = [zStart, zStart + STATS(1).BoundingBox(6) - 1];
            end
            obj.view.handles.subAreaFromSelectionBtn.BackgroundColor = bgColor;
        end

        % -----------------------------------------------------------------
        function updateMaterialsBtn_Callback(obj)
        % updateMaterialsBtn_Callback  Rebuild the source material dropdown.
            id = obj.mibModel.getActiveId();
            materialList = obj.mibModel.I{id}.labels.materialNames;
            if obj.mibModel.I{id}.maskExist
                materialList = [{'Mask'}; materialList(:)];
            end
            if isempty(materialList)
                obj.view.handles.sourceMaterialPopup.Items           = {'Please create a model or a mask'};
                obj.view.handles.sourceMaterialPopup.Value           = 'Please create a model or a mask';
                obj.view.handles.sourceMaterialPopup.BackgroundColor = [1 0 0];
            else
                obj.view.handles.sourceMaterialPopup.Items           = materialList;
                obj.view.handles.sourceMaterialPopup.Value           = materialList{1};
                obj.view.handles.sourceMaterialPopup.BackgroundColor = [1 1 1];
            end
        end

        % -----------------------------------------------------------------
        function updateStrel_Callback(obj)
        % updateStrel_Callback  Recompute the structuring element from current widget values.
            strelType = obj.view.handles.strelTypePopup.Value;   % string: 'disk'|'rectangle'|'sphere'
            strelSize = obj.view.handles.strelSizeEdit.Value;     % numeric (uispinner)

            if strcmp(obj.mode, 'volume3D')
                strelSizeZ = obj.view.handles.strelSizeZEdit.Value;   % numeric
                seSize = [strelSize strelSize strelSizeZ];
                obj.se = zeros(seSize(1)*2+1, seSize(2)*2+1, seSize(3)*2+1);
                if seSize(3) > 0
                    [x, y, z] = meshgrid(-seSize(1):seSize(1), -seSize(2):seSize(2), -seSize(3):seSize(3));
                    ball = sqrt((x/seSize(1)).^2 + (y/seSize(2)).^2 + (z/seSize(3)).^2);
                    obj.se(ball <= 1) = 1;
                else
                    se1 = strel('sphere', strelSize);
                    se1 = se1.Neighborhood(:,:,strelSize+1);
                    obj.se = zeros([size(se1, 1), size(se1, 2), 3], 'uint8');
                    obj.se(:,:,2) = se1;
                end
            else
                switch strelType
                    case 'disk'
                        obj.se = strel('disk', strelSize).Neighborhood;
                    case 'rectangle'
                        obj.se = strel('rectangle', [strelSize, strelSize]).Neighborhood;
                    case 'sphere'
                        obj.se = strel('sphere', strelSize).Neighborhood(:,:,strelSize+1);
                end
            end
        end

        % -----------------------------------------------------------------
        function previewStrelBtn_Callback(obj)
        % previewStrelBtn_Callback  Display structuring element shape.
            if strcmp(obj.mode, 'volume3D')
                rotationSteps = obj.view.handles.strelRotationsEdit.Value;  % numeric
                angleStep = pi / rotationSteps;
                index = 0;
                for yAngle = 0:angleStep:pi
                    my = makehgtform('yrotate', yAngle);
                    for xAngle = 0:angleStep:pi
                        mx = makehgtform('xrotate', xAngle);
                        tform = affine3d(mx * my);
                        se3Rotated = imwarp(obj.se, tform, 'nearest');
                        figOffset = floor(index / 16);
                        subIdx    = mod(index, 16) + 1;
                        figure(141 + figOffset);
                        subplot(4, 4, subIdx);
                        cla;
                        [faces, verts] = isosurface(se3Rotated, 0.5);
                        p = patch('Faces', faces, 'Vertices', verts, ...
                            'FaceColor', [1 0 0], 'EdgeColor', 'none');
                        p.AmbientStrength = 0.3;
                        set(gca, 'projection', 'perspective');
                        lighting gouraud;
                        camlight('headlight');
                        axis tight; axis equal;
                        title(sprintf('X: %d, Y: %d', xAngle/pi*180, yAngle/pi*180));
                        grid;
                        index = index + 1;
                    end
                end
            else
                imtool(obj.se, []);
            end
        end

        % -----------------------------------------------------------------
        function exportMatlabCheck_Callback(obj)
        % exportMatlabCheck_Callback  Prompt for workspace variable name when export is enabled.
            if obj.view.handles.exportMatlabCheck.Value
                answer = utils.dlgs.inputUniversalDlg(obj.view.gui, '', ...
                    {'Please define output variable:'}, ...
                    {obj.matlabExportVariable}, 'Export variable');
                if ~isempty(answer)
                    obj.matlabExportVariable = answer{1};
                else
                    obj.view.handles.exportMatlabCheck.Value = false;
                end
            end
        end

        % -----------------------------------------------------------------
        function exportFileCheck_Callback(obj)
        % exportFileCheck_Callback  Toggle enable state of file export widgets.
            isEnabled = obj.view.handles.exportFileCheck.Value;
            if isEnabled
                obj.view.handles.exportResultsFilename.Enable = 'on';
                obj.view.handles.filenameEdit.Enable          = 'on';
            else
                obj.view.handles.exportResultsFilename.Enable = 'off';
                obj.view.handles.filenameEdit.Enable          = 'off';
            end
        end

        % -----------------------------------------------------------------
        function exportResultsFilename_Callback(obj)
        % exportResultsFilename_Callback  Browse for output file path.
            formatText = {'*.xlsx', 'Microsoft Excel (*.xlsx)'; '*.mat', 'Matlab format (*.mat)'};
            currentFilename = obj.view.handles.filenameEdit.Value;
            [fileName, pathName] = uiputfile(formatText, 'Select filename', currentFilename);
            if isequal(fileName, 0) || isequal(pathName, 0); return; end
            outputFilename = fullfile(pathName, fileName);
            obj.view.handles.filenameEdit.Value   = outputFilename;
            obj.view.handles.filenameEdit.Tooltip = outputFilename;
        end

        % -----------------------------------------------------------------
        function helpBtn_Callback(obj)
        % helpBtn_Callback  Open online help in the system browser.
            helpFilPath = fullfile(fileparts(obj.mibModel.mibPath), 'docs', 'html', 'user-interface', 'plugins', 'organelle-analysis', 'granularity.html');
            if isfile(helpFilPath)
                web(helpFilPath, '-browser');
            else
                web('http://mib.helsinki.fi/help/main3/user-interface/plugins/organelle-analysis/granularity.html', '-browser');
            end
        end

        % -----------------------------------------------------------------
        function calculateBtn_Callback(obj)
        % calculateBtn_Callback  Run the granularity analysis and write results.
            id = obj.mibModel.getActiveId();

            if obj.mibModel.I{id}.orientation ~= 3
                utils.dlgs.showErrorDialog(obj.view.gui, ...
                    'Please rotate the dataset to the XY orientation!', 'Wrong orientation');
                return;
            end

            outFilename = obj.view.handles.filenameEdit.Value;
            if obj.view.handles.exportFileCheck.Value
                if exist(outFilename, 'file') == 2
                    strText = sprintf('!!! Warning !!!\n\nThe file:\n%s \nis already exist!\n\nOverwrite?', outFilename);
                    button = utils.dlgs.inputQuestDlg(obj.view.gui, strText, 'File exist!', 'Overwrite', 'Cancel', 'Cancel');
                    if strcmp(button, 'Cancel'); return; end
                    delete(outFilename);
                end
            end

            % --- build results structure ----------------------------------
            Granularity = struct();
            pixSize = obj.mibModel.I{id}.image.pixSize;
            Granularity(1).pixSize            = pixSize;
            Granularity(1).DatasetFilename    = obj.mibModel.I{id}.image.filename;
            Granularity(1).MaskFilename       = [];
            Granularity(1).MaskMaterialIndex  = 1;
            Granularity(1).MaskMaterialName   = 'Mask';
            Granularity(1).StrelType          = obj.view.handles.strelTypePopup.Value;
            Granularity(1).StrelSize          = obj.view.handles.strelSizeEdit.Value;
            Granularity(1).StrelElement       = obj.se;

            imageMeta = obj.mibModel.I{id}.image.getMeta();
            if isKey(imageMeta, 'SliceName')
                Granularity(1).SliceName = imageMeta('SliceName');
            else
                [~, fn, ext] = fileparts(obj.mibModel.I{id}.image.filename);
                Granularity(1).SliceName = {[fn ext]};
            end

            Granularity(1).subarea    = struct();
            Granularity(1).Granularity = [];
            if obj.view.handles.useROICheck.Value
                Granularity(1).useROI = obj.mibModel.I{id}.selectedROI;
            else
                Granularity(1).useROI = 0;
            end

            if strcmp(obj.mode, 'volume3D')
                Granularity(1).totalVolumePixels   = [];
                Granularity(1).totalVolumeUnits    = [];
                Granularity(1).sheetsVolumePixels  = [];
                Granularity(1).sheetsVolumeUnits   = [];
                Granularity(1).tubulesVolumePixels = [];
                Granularity(1).tubulesVolumeUnits  = [];
            else
                Granularity(1).sheetsAreaUnits   = [];
                Granularity(1).tubulesAreaUnits  = [];
                Granularity(1).totalAreaUnits    = [];
                Granularity(1).sheetsAreaPixels  = [];
                Granularity(1).tubulesAreaPixels = [];
                Granularity(1).totalAreaPixels   = [];
            end

            % --- resolve data source and layer names ---------------------
            dataSource = obj.view.handles.sourceMaterialPopup.Value;
            if strcmp(dataSource, 'Mask')
                layerIn        = 'mask';
                materialIndex  = [];
                layerOut       = 'selection';
                Granularity(1).MaskFilename = obj.mibModel.I{id}.mask.filename;
            else
                layerIn = 'labels';
                materialItems = obj.view.handles.sourceMaterialPopup.Items;
                materialIndex = find(strcmp(materialItems, dataSource));
                if strcmp(materialItems{1}, 'Mask')
                    materialIndex = materialIndex - 1;
                end
                layerOut = 'selection';
                Granularity(1).MaskFilename      = obj.mibModel.I{id}.labels.filename;
                Granularity(1).MaskMaterialIndex = materialIndex;
                Granularity(1).MaskMaterialName  = obj.mibModel.I{id}.labels.materialNames{materialIndex};
            end

            % --- build getData options -----------------------------------
            if Granularity(1).useROI > 0
                if numel(obj.mibModel.I{id}.selectedROI) > 1
                    utils.dlgs.showErrorDialog(obj.view.gui, ...
                        'Please select a single ROI in the ROI panel and try again', 'Missing ROIs');
                    return;
                end
                getDataOptions.roiId  = [];
                getDataOptions.fillBg = 0;
            else
                getDataOptions.roiId = -1;
            end
            getDataOptions.blockModeSwitch = 0;
            getDataOptions.x = obj.subarea.x;
            getDataOptions.y = obj.subarea.y;
            getDataOptions.z = obj.subarea.z;

            % --- backup and clear output layer ---------------------------
            obj.mibModel.backup(layerOut, 1, getDataOptions);
            if strcmp(layerOut, 'selection')
                obj.mibModel.I{id}.clearLayer('selection', '4D');
            elseif strcmp(layerOut, 'labels')
                if obj.mibModel.I{id}.modelExist
                    button = utils.dlgs.inputQuestDlg(obj.view.gui, ...
                        sprintf('!!! Warning !!!\n\nThe existing model will be removed!\n\nContinue?'), ...
                        'Overwrite the model', 'Continue', 'Cancel', 'Cancel');
                    if strcmp(button, 'Cancel'); return; end
                end
                obj.mibModel.I{id}.createModel(63);
            end

            if strcmp(obj.mode, 'image2D')
                currentSlice = obj.mibModel.I{id}.getCurrentSliceNumber();
                getDataOptions.z = [currentSlice, currentSlice];
            end

            Granularity(1).subarea.x = getDataOptions.x;
            Granularity(1).subarea.y = getDataOptions.y;
            Granularity(1).subarea.z = getDataOptions.z;

            % --- load mask / labels data ---------------------------------
            maskCell = obj.mibModel.getData3D(layerIn, [], 3, materialIndex, getDataOptions);
            mask     = maskCell{1};
            sheetsOut = zeros(size(mask), 'uint8');

            % --- set up progress dialog ----------------------------------
            progressDialog = uiprogressdlg(obj.view.gui, ...
                'Title',      'Granularity', ...
                'Message',    'Calculating granularity...', ...
                'Value',      0, ...
                'Cancelable', 'on');

            % --- main computation ----------------------------------------
            if strcmp(obj.mode, 'volume3D')
                rotationSteps = obj.view.handles.strelRotationsEdit.Value;
                angleStep = pi / rotationSteps;
                iterNo = numel(0:angleStep:pi)^2;
                index = 0;
                for yAngle = 0:angleStep:pi
                    my = makehgtform('yrotate', yAngle);
                    for xAngle = 0:angleStep:pi
                        if progressDialog.CancelRequested
                            close(progressDialog); return;
                        end
                        index = index + 1;
                        progressDialog.Value   = index / iterNo;
                        progressDialog.Message = sprintf('Calculating granularity: rotation %d / %d', index, iterNo);
                        tform = affine3d(makehgtform('xrotate', xAngle) * my);
                        se3Rotated = imwarp(obj.se, tform, 'nearest');
                        M2 = imdilate(imerode(mask, se3Rotated), se3Rotated);
                        sheetsOut = sheetsOut | M2;
                    end
                end
                Granularity(1).totalVolumePixels   = sum(mask(:));
                Granularity(1).totalVolumeUnits    = Granularity(1).totalVolumePixels * pixSize.x * pixSize.y * pixSize.z;
                Granularity(1).sheetsVolumePixels  = sum(sheetsOut(:));
                Granularity(1).sheetsVolumeUnits   = Granularity(1).sheetsVolumePixels * pixSize.x * pixSize.y * pixSize.z;
                Granularity(1).tubulesVolumePixels = Granularity(1).totalVolumePixels  - Granularity(1).sheetsVolumePixels;
                Granularity(1).tubulesVolumeUnits  = Granularity(1).tubulesVolumePixels * pixSize.x * pixSize.y * pixSize.z;
                Granularity(1).Granularity         = Granularity(1).tubulesVolumePixels / Granularity(1).totalVolumePixels;
            else
                noSlices = size(mask, 3);
                Granularity(1).sheetsAreaUnits   = zeros(noSlices, 1);
                Granularity(1).tubulesAreaUnits  = zeros(noSlices, 1);
                Granularity(1).totalAreaUnits    = zeros(noSlices, 1);
                Granularity(1).sheetsAreaPixels  = zeros(noSlices, 1);
                Granularity(1).tubulesAreaPixels = zeros(noSlices, 1);
                Granularity(1).totalAreaPixels   = zeros(noSlices, 1);
                Granularity(1).Granularity       = zeros(noSlices, 1);

                for z = 1:noSlices
                    if progressDialog.CancelRequested
                        close(progressDialog); return;
                    end
                    progressDialog.Value   = (z - 1) / noSlices;
                    progressDialog.Message = sprintf('Calculating granularity: slice %d / %d', z, noSlices);
                    Granularity(1).totalAreaPixels(z) = sum(sum(mask(:,:,z)));
                    Granularity(1).totalAreaUnits(z)  = Granularity(1).totalAreaPixels(z) * pixSize.x * pixSize.y;
                    sheetsOut(:,:,z) = imdilate(imerode(mask(:,:,z), obj.se), obj.se);
                    Granularity(1).sheetsAreaPixels(z)  = sum(sum(sheetsOut(:,:,z)));
                    Granularity(1).sheetsAreaUnits(z)   = Granularity(1).sheetsAreaPixels(z) * pixSize.x * pixSize.y;
                    Granularity(1).tubulesAreaPixels(z) = Granularity(1).totalAreaPixels(z) - Granularity(1).sheetsAreaPixels(z);
                    Granularity(1).tubulesAreaUnits(z)  = Granularity(1).totalAreaUnits(z)  - Granularity(1).sheetsAreaUnits(z);
                    Granularity(1).Granularity(z) = Granularity(1).tubulesAreaPixels(z) / Granularity(1).totalAreaPixels(z);
                end
            end

            % --- write results back and export ---------------------------
            getDataOptions.fillBg = NaN;
            obj.mibModel.setData3D(sheetsOut, layerOut, [], 3, [], getDataOptions);

            if obj.view.handles.exportMatlabCheck.Value
                progressDialog.Value   = 0.99;
                progressDialog.Message = 'Exporting to Matlab...';
                assignin('base', obj.matlabExportVariable, Granularity);
                fprintf('Granularity: structure ''%s'' has been created in the Matlab workspace\n', obj.matlabExportVariable);
            end

            if obj.view.handles.exportFileCheck.Value
                if strcmp(outFilename(end-2:end), 'mat')
                    save(outFilename, 'Granularity');
                    fprintf('Granularity: exporting results to a file: done\n%s\n', outFilename);
                else
                    progressDialog.Value   = 0.99;
                    progressDialog.Message = 'Generating Excel file...';
                    obj.saveToExcel(Granularity, outFilename);
                end
            end

            close(progressDialog);
            notify(obj.mibModel, 'ShowImage');

            if strcmp(obj.mode, 'timelapse2D')
                figure(717);
                plot(Granularity(1).subarea.z(1):Granularity(1).subarea.z(2), Granularity(1).Granularity, 'o-');
                xlabel('Slice number');
                ylabel('Granularity, tubules/total');
                title('Granularity value');
            elseif strcmp(obj.mode, 'image2D')
                fprintf('Granularity of slice %d (0-1): %f\n', getDataOptions.z(1), Granularity(1).Granularity);
            elseif strcmp(obj.mode, 'volume3D')
                fprintf('Granularity of 3D dataset (0-1): %f\n', Granularity(1).Granularity);
                dlgOpt.MsgBoxOnly  = true;
                dlgOpt.Icon        = 'puffin_info';
                dlgOpt.HeaderLines = 1;
                utils.dlgs.inputUniversalDlg(obj.view.gui, ...
                    'Granularity of 3D dataset (0-1):', ...
                    {''}, {sprintf('%f', Granularity(1).Granularity)}, ...
                    'Granularity result', dlgOpt);
            end
        end

        % -----------------------------------------------------------------
        function saveToExcel(obj, Granularity, outFilename)
        % saveToExcel  Write Granularity results struct to an Excel file.
        %
        % Parameters:
        % Granularity: results struct array from calculateBtn_Callback
        % outFilename: full path to the output .xlsx file
            warning('off', 'MATLAB:xlswrite:AddSheet');
            s = {'Granularity: calculate ratio of tubular areas to total area of the object'};
            s(2,2) = {'Image filename:'};  s(2,4) = {Granularity(1).DatasetFilename};
            s(3,2) = {'Mask filename:'};   s(3,4) = {Granularity(1).MaskFilename};
            s(4,2) = {sprintf('Material index: %d', Granularity(1).MaskMaterialIndex)};
            s(4,4) = {sprintf('Material name: %s',  Granularity(1).MaskMaterialName)};
            s(5,2) = {sprintf('Strel type: %s',     Granularity(1).StrelType)};
            s(5,4) = {sprintf('Strel size: %d',     Granularity(1).StrelSize)};
            s(6,2) = {sprintf('Pixel size [x,y,z]/units: %fx%fx%f %s', ...
                Granularity(1).pixSize.x, Granularity(1).pixSize.y, Granularity(1).pixSize.z, Granularity(1).pixSize.units)};
            s(7,2) = {sprintf('Analyzed area [x1:x2, y1:y2, z1:z2]/pixels: %d:%d, %d:%d, %d:%d', ...
                Granularity(1).subarea.x(1), Granularity(1).subarea.x(2), ...
                Granularity(1).subarea.y(1), Granularity(1).subarea.y(2), ...
                Granularity(1).subarea.z(1), Granularity(1).subarea.z(2))};
            if Granularity(1).useROI > 0
                s(7,9) = {sprintf('Used ROI index: %d', Granularity(1).useROI)};
            end

            if ~isfield(Granularity, 'totalVolumePixels')
                text1 = 'area'; text2 = 'Area';
            else
                text1 = 'volume'; text2 = 'Volume';
            end

            dR1 = 9;
            if numel(Granularity(1).SliceName) > 1; s(dR1, 1) = {'Filename'}; end
            s(dR1,  2) = {'SliceNo'};
            s(dR1,  3) = {'Granularity,'}; s(dR1+1, 3) = {'tubules/total'};
            s(dR1,  5) = {'Tubules,'};     s(dR1+1, 5) = {sprintf('%s, px',  text1)};
            s(dR1,  6) = {'Sheets,'};      s(dR1+1, 6) = {sprintf('%s, px',  text1)};
            s(dR1,  7) = {'Total,'};       s(dR1+1, 7) = {sprintf('%s, px',  text1)};
            s(dR1,  9) = {'Tubules,'};     s(dR1+1, 9) = {sprintf('%s, %s', text1, Granularity(1).pixSize.units)};
            s(dR1, 10) = {'Sheets,'};      s(dR1+1,10) = {sprintf('%s, %s', text1, Granularity(1).pixSize.units)};
            s(dR1, 11) = {'Total,'};       s(dR1+1,11) = {sprintf('%s, %s', text1, Granularity(1).pixSize.units)};

            dR2   = 11;
            maxVal = size(Granularity(1).Granularity, 1);
            if numel(Granularity(1).SliceName) > 1
                if maxVal > 1
                    s(dR2:dR2+maxVal-1, 1) = Granularity(1).SliceName( ...
                        Granularity(1).subarea.z(1):Granularity(1).subarea.z(2));
                else
                    s(dR2, 1) = Granularity(1).SliceName(Granularity(1).subarea.z(1));
                end
            end
            vecTemp = (1:maxVal) + Granularity(1).subarea.z(1) - 1;
            s(dR2:dR2+maxVal-1,  2) = num2cell(vecTemp');
            s(dR2:dR2+maxVal-1,  3) = num2cell(Granularity(1).Granularity);
            s(dR2:dR2+maxVal-1,  5) = num2cell(Granularity(1).(sprintf('tubules%sPixels', text2)));
            s(dR2:dR2+maxVal-1,  6) = num2cell(Granularity(1).(sprintf('sheets%sPixels',  text2)));
            s(dR2:dR2+maxVal-1,  7) = num2cell(Granularity(1).(sprintf('total%sPixels',   text2)));
            s(dR2:dR2+maxVal-1,  9) = num2cell(Granularity(1).(sprintf('tubules%sUnits',  text2)));
            s(dR2:dR2+maxVal-1, 10) = num2cell(Granularity(1).(sprintf('sheets%sUnits',   text2)));
            s(dR2:dR2+maxVal-1, 11) = num2cell(Granularity(1).(sprintf('total%sUnits',    text2)));

            xlswrite2(outFilename, s, 'Results', 'A1');
            fprintf('Granularity: exporting results to a file: done\n%s\n', outFilename);
        end

    end  % methods

end
