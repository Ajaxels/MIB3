function gui_WindowKeyPressFcn(obj, hWidget, hData)
% function gui_WindowKeyPressFcn(obj)
% Callback for a key press in MIB
% Linked via: obj.UIFigure.WindowKeyPressFcn = @(~, ~)obj.gui_WindowKeyPressFcn();
%
% Parameters:
% obj: handle to MibImageDocument instance
%
% Return values:
%

% Get key info directly from the UIFigure current key data
hFigure = obj.cImageDoc{obj.mibModel.Sets.selectedSet}.UIFigure;
char = lower(hFigure.CurrentKey);
modifier = hFigure.CurrentModifier;  % cell array of modifier strings

% Skip if the focused component is an edit field or text area.
% Use hWidget (the figure that fired the event), NOT hFigure (the image
% document panel) — CurrentObject is only set on the event-source figure.
focusedComp = hWidget.CurrentObject;
if ~isempty(focusedComp) && isprop(focusedComp, 'Type') && ...
        ismember(focusedComp.Type, {'uieditfield', 'uinumericeditfield', 'uitextarea', 'uispinner'})
    return;
end

% return when Alt is pressed
if strcmp(char, 'alt'); return; end %#ok<STCI>

% find a shortcut action
KeyShortcuts = obj.mibModel.preferences.KeyShortcuts;
dataset = obj.mibModel.I{obj.mibModel.id};
cImageDoc = obj.cImageDoc{obj.mibModel.Sets.selectedSet};
cSegmentation = obj.cSegmentation;

% cancel if button is not registered as a shortcut
keyMask = strcmp(KeyShortcuts.Key, char);

% define the modifiers press status
controlSw  = any(strcmp(modifier, 'control'));
shiftPressed = any(strcmp(modifier, 'shift'));
altPressed   = any(strcmp(modifier, 'alt'));

% correct with override shift setting
shiftSw = shiftPressed && ~any(strcmp(char, KeyShortcuts.Key(KeyShortcuts.overrideShift == 1)));

% alt override
if ~altPressed
    altSw = false;
else
    overrideAlt = any(strcmp(char, KeyShortcuts.Key(KeyShortcuts.overrideAlt == 1)));
    altPlusA    = any(strcmp(char, KeyShortcuts.Key(strcmp(KeyShortcuts.Action, 'Add to selection to material')))) && shiftPressed;
    altSw = ~overrideAlt && ~altPlusA;
end

ActionId = find(keyMask & ...
    (KeyShortcuts.control == controlSw) & (KeyShortcuts.shift   == shiftSw)& (KeyShortcuts.alt     == altSw));

% get image coordinates under the mouse cursor
xyString = obj.cStatus.handles.pixelLabel.Text;
xy = sscanf(xyString, '%f:%f', 2);

if ~isempty(ActionId) % find in the list of existing shortcuts
    % compute layer scope from modifier combination (used by several cases)
    modCount = sum([altPressed, shiftPressed]);
    scopeList = {'2D, Slice', '3D, Stack', '4D, Dataset'};
    layerScope = scopeList{min(modCount, 2) + 1}; % one of the scopeList options

    switch KeyShortcuts.Action{ActionId}
        case 'Add measurement (Measure tool)'   % add measurement, works with Measure Tool, default 'm'
            notify(obj.mibModel, 'AddMeasurement', eventdata);
        case 'Switch dataset to XY orientation'         % default 'Alt + 1'
            if dataset.orientation == 3 || isnan(cImageDoc.isInsideImage) || ~cImageDoc.isInsideImage || strcmp(dataset.datasetType, 'Virtual'); return; end
            if dataset.orientation == 1
                dataset.current_yxz(2) = xy(2);
                dataset.current_yxz(3) = xy(1);
            elseif dataset.orientation == 2
                dataset.current_yxz(1) = xy(2);
                dataset.current_yxz(3) = xy(1);
            end
            obj.cQuickAccessBar.orientationChange(obj.cQuickAccessBar.handles.yx_orientation, true);
        case 'Switch dataset to ZY orientation'         % default 'Alt + 2'
            if dataset.orientation == 2 || isnan(cImageDoc.isInsideImage) || ~cImageDoc.isInsideImage || strcmp(dataset.datasetType, 'Virtual'); return; end
            if dataset.orientation == 1
                dataset.current_yxz(1) = dataset.slices{1}(1);
                dataset.current_yxz(2) = xy(2);
                dataset.current_yxz(3) = xy(1);
            elseif dataset.orientation == 3
                dataset.current_yxz(1) = xy(2);
                dataset.current_yxz(2) = xy(1);
                dataset.current_yxz(3) = dataset.slices{3}(1);
            end
            obj.cQuickAccessBar.orientationChange(obj.cQuickAccessBar.handles.yz_orientation, true);
        case 'Switch dataset to ZX orientation'         % default 'Alt + 3'
            if dataset.orientation == 1 || isnan(cImageDoc.isInsideImage) || ~cImageDoc.isInsideImage || strcmp(dataset.datasetType, 'Virtual'); return; end
            if dataset.orientation == 2
                dataset.current_yxz(1) = xy(2);
                dataset.current_yxz(2) = dataset.slices{2}(1);
                dataset.current_yxz(3) = xy(1);
            elseif dataset.orientation == 3
                dataset.current_yxz(1) = xy(2);
                dataset.current_yxz(2) = xy(1);
                dataset.current_yxz(3) = dataset.slices{3}(1);
            end
            obj.cQuickAccessBar.orientationChange(obj.cQuickAccessBar.handles.xz_orientation, true);
        case 'Interpolate selection'            % default 'i'
            error('MISSING IMPLEMENTATION: obj.menuSelectionInterpolate();');
        case 'Invert image'                     % default 'Ctrl + i'
            error("MISSING IMPLEMENTATION: obj.menuImageInvert_Callback('4D');");
        case {'Add to selection to material', 'Subtract from material', 'Replace material with current selection'}
            % default 'a'/'Shift+a', 's'/'Shift+s', 'r'/'Shift+r'
            if dataset.enableSelection == 0; return; end

            % special SAM tweak — only for 'Add to selection to material'
            if strcmp(KeyShortcuts.Action{ActionId}, 'Add to selection to material')
                selectedSegmentationTool = cSegmentation.handles.segmTool.Value;
                if strcmp(selectedSegmentationTool, 'Segment-anything model') && ...
                        strcmp(cSegmentation.handles.samMode.Value, 'add, +next material') && ...
                        strcmp(cSegmentation.handles.samDestination.Value, 'selection')

                    if dataset.labels.maxMaterials < 256
                        errorDlgOpts.mibPath = obj.mibModel.mibPath;
                        utils.dlgs.showErrorDialog(obj.view.gui, ...
                            sprintf(['The current settings are not compatible with the "add, +next material" mode!\n\n' ...
                            'Please make sure that:\n' ...
                            '   - You created or already have a model with type 65535 or larger']), ...
                            'Error in gui_WindowKeyPressFcn', 'Error: add, +next material', '', errorDlgOpts);
                        return;
                    end
                    if dataset.selectedAddToMaterial < 4
                        dataset.lastSegmSelection = [3 4];
                        dataset.selectedAddToMaterial = 4;
                        cSegmentation.materialsTable_CellSelectionCallback([3, 2]);
                    end
                    obj.mibModel.moveLayers('selection', 'model', '2D, Slice', 'add');
                    obj.mibModel.sessionSettings.SAMsegmenter.initialImageAddTo = [];
                    selMaterialIndex = dataset.getSelectedMaterialIndex('AddTo');
                    dataset.labels.materialNames = {num2str(selMaterialIndex), num2str(selMaterialIndex+1)};
                    if size(dataset.labels.materialColors, 1) < selMaterialIndex+1
                        dataset.labels.materialColors(selMaterialIndex+1, :) = rand(1,3);
                    end
                    cSegmentation.updateMaterialsTable();
                    cSegmentation.materialsTable_CellSelectionCallback([dataset.selectedAddToMaterial, 3]);
                    return;
                end
            end

            % map action name to moveLayers operation
            opMap = dictionary(...
                ["Add to selection to material", "Subtract from material", "Replace material with current selection"], ...
                ["add",                          "remove",                  "replace"]);
            operation = opMap(KeyShortcuts.Action{ActionId});
            selectionTo = 'model';
            if dataset.getSelectedMaterialIndex('AddTo') == -1; selectionTo = 'mask'; end
            obj.mibModel.moveLayers('selection', selectionTo, layerScope, operation);

        case 'Clear selection'                          % default 'c'/'Shift+c'
            error('MISSING IMPLEMENTATION: obj.mibSelectionClearBtn_Callback();')

        case {'Fill the holes in the Selection layer', 'Erode the Selection layer', 'Dilate the Selection layer'}
            % default 'f'/'Shift+f', 'z'/'Shift+z', 'x'/'Shift+x'
            if dataset.enableSelection == 0; return; end

            switch KeyShortcuts.Action{ActionId}
                case 'Fill the holes in the Selection layer';  error('MISSING IMPLEMENTATION: obj.mibSelectionFillBtn_Callback();')
                case 'Erode the Selection layer';              error('MISSING IMPLEMENTATION: obj.mibSelectionErodeBtn_Callback();')
                case 'Dilate the Selection layer';             error('MISSING IMPLEMENTATION: obj.mibSelectionDilateBtn_Callback();')
            end

        case {'Zoom out/Previous slice', 'Previous slice', 'Zoom in/Next slice', 'Next slice'}
            % default 'q'/'downarrow', 'w'/'uparrow'
            if (strcmp(char, 'leftarrow') || strcmp(char, 'downarrow')) && ~cImageDoc.isInsideAxes; return; end

            isNext = contains(KeyShortcuts.Action{ActionId}, 'Next');
            direction = 2*isNext - 1;   % +1 for next, -1 for previous

            isPureSlice = any(strcmp(KeyShortcuts.Action{ActionId}, {'Previous slice', 'Next slice'}));
            changeSliceSwitch = isPureSlice || obj.mibModel.preferences.System.MouseWheel(1) == 'z';

            if changeSliceSwitch
                if altPressed   % change time
                    if dataset.image.time == 1; return; end
                    new_index = max(1, min(dataset.image.time, dataset.slices{5}(1) + direction));
                    dataset.slices{5} = [new_index, new_index];
                    cImageDoc.handles.frameNumberSlider.Value = new_index;
                    cImageDoc.frameNumberSlider_Callback();
                else            % change Z
                    if dataset.image.depth == 1; return; end
                    shift = obj.sliderZStep;
                    if shiftPressed; shift = obj.sliderZShiftStep; end
                    new_index = max(1, min(dataset.dim_yxzct(dataset.orientation), dataset.slices{dataset.orientation}(1) + direction*shift));
                    dataset.slices{dataset.orientation} = [new_index, new_index];
                    cImageDoc.handles.sliceNumberSlider.Value = new_index;
                    cImageDoc.sliceNumberSlider_Callback();
                end
            else
                if isNext
                    BatchOpt.Mode = 'Zoom in';
                    recenterSwitch = true;
                    obj.cStatus.zoomEdit_Callback(recenterSwitch, BatchOpt);
                else
                    BatchOpt.Mode = 'Zoom out';
                    recenterSwitch = true;
                    obj.cStatus.zoomEdit_Callback(recenterSwitch, BatchOpt);
                end
            end

        case 'Rename material'                          % default F2
            if dataset.getSelectedMaterialIndex() > 0
                error("MISSING IMPLEMENTATION: obj.mibModel.renameMaterial();")
            end

        case 'Show/hide the Model layer'                % default 'space'
            obj.cSelection.handles.showModel.Value = abs(obj.cSelection.handles.showModel.Value - 1);
            error("MISSING IMPLEMENTATION: obj.mibModelShowCheck_Callback();")

        case 'Show/hide the Mask layer'                 % default 'Ctrl + space'
            obj.cSelection.handles.showMask.Value = abs(obj.cSelection.handles.showMask.Value - 1);
            error("MISSING IMPLEMENTATION: obj.mibMaskShowCheck_Callback();")

        case 'Fix selection to material'
            cSegmentation.handles.restrictMaterial.Value = abs(cSegmentation.handles.restrictMaterial.Value - 1);
            cSegmentation.restrictMaterial_Callback();

        case 'Save image as...'                         % default 'Ctrl + s'
            obj.mibModel.saveImage('image');

        case 'Copy to buffer selection from the current slice'  % default 'Ctrl + c'
            error("MISSING IMPLEMENTATION: obj.menuSelectionBuffer_Callback('copy');")

        case 'Paste buffered selection to the current slice'    % default 'Ctrl + v'
            error("MISSING IMPLEMENTATION: obj.menuSelectionBuffer_Callback('paste');")

        case 'Paste buffered selection to all slices'           % default 'Ctrl + Shift + v'
            error("MISSING IMPLEMENTATION: obj.menuSelectionBuffer_Callback('pasteall');")

        case 'Toggle between the selected material and exterior' % default 'e'
            cSegmentation.materialsTable_CellSelectionCallback([dataset.lastSegmSelection(1), 2]);
            dataset.lastSegmSelection = fliplr(dataset.lastSegmSelection);

        case 'Toggle current and previous buffer'   % default ctrl+e, toggle buffer buttons
            obj.cActiveDataset.buffers_Callback([],[], obj.mibModel.previouslySelectedDataset);

        case {'Loop through the list of favourite segmentation tools', 'Favorite tool A', 'Favorite tool B'}  % default 'd', Shift+D, Ctrl+D
            actionName = KeyShortcuts.Action{ActionId};
            toolList = cSegmentation.handles.segmTool.Items;

            if actionName(1) == 'L'     % Loop, 'D' shortcut
                if numel(obj.mibModel.preferences.SegmTools.FavoriteTools) == 0
                    errorDlgOpts.mibPath = obj.mibModel.mibPath;
                    utils.dlgs.showErrorDialog(obj.view.gui, ...
                        sprintf('The selection tools for the fast access with the "D" shortcut are not defined!\n\nPlease use the "Favotite tool (D)" checkbox in the Segmentation panel to select them!'), ...
                        'Error in gui_WindowKeyPressFcn', 'No favorite tools defined!', '', errorDlgOpts);
                    return;
                end
                toolId = cSegmentation.handles.segmTool.ValueIndex;
                nextTool = obj.mibModel.preferences.SegmTools.FavoriteTools(find(obj.mibModel.preferences.SegmTools.FavoriteTools > toolId, 1));

                if isempty(nextTool); nextTool = obj.mibModel.preferences.SegmTools.FavoriteTools(1); end
            elseif actionName(end) == 'A'  % favorite tool A, 'Shift+D' shortcut
                nextTool = find(strcmp(toolList, obj.mibModel.preferences.SegmTools.FavoriteToolA), 1);
            else % 'B'  % favorite tool B, 'Ctrl+D' shortcut
                nextTool = find(strcmp(toolList, obj.mibModel.preferences.SegmTools.FavoriteToolB), 1);
            end

            % show information text
            axPos  = getpixelposition(obj.handles.imViewAxes, true);  % [x y w h] in figure pixels
            % axPos(1) = left edge of axes
            % axPos(2) = bottom edge of axes
            % axPos(3) = axes width
            % axPos(4) = axes height
            lblW = 340;
            lblH = 85;
            lblX = axPos(1) + (axPos(3) - lblW) / 2;   % horizontally centered over axes
            lblY = axPos(2) + axPos(4) * 0.65;         % 65% up the axes height

            msg = sprintf('<div style="background:#DFF2FC;border-radius:10px;padding:12px 24px;font-family:Arial;font-size:20px;font-weight:bold;font-style:italic;color:#1a1a1a;text-align:center;box-shadow:2px 2px 8px rgba(0,0,0,0.2)">%s</div>', toolList{nextTool});
            fittext = uihtml(obj.UIFigure, 'HTMLSource', msg, ...
                'Position', [lblX lblY lblW lblH]);
            pause(.4);

            cSegmentation.handles.segmTool.ValueIndex = nextTool;
            cSegmentation.segmentationTool_Callback();
            delete(fittext);

        case 'Undo/Redo last action'                    % default 'Ctrl + z'
            if obj.mibModel.Undo.enableSwitch == 0; return; end
            if obj.mibModel.Undo.prevUndoIndex == 0; return; end
            error("MISSING IMPLEMENTATION: obj.mibDoUndo();")

        case 'Find material under cursor'               % default 'Ctrl + f'
            error("MISSING IMPLEMENTATION: obj.mibFindMaterialUnderCursor();")

        case {'Previous time point', 'Next time point'} % default leftarrow / rightarrow
            if dataset.image.time == 1; return; end
            direction = 2*strcmp(KeyShortcuts.Action{ActionId}, 'Next time point') - 1;  % +1 or -1
            new_index = max(1, min(dataset.image.time, dataset.slices{5}(1) + direction));
            cImageDoc.handles.frameNumberSlider.Value = new_index;
            cImageDoc.frameNumberSlider_Callback();

        case 'Increse active material index by 1 for models with 65535 materials'  % default 'n' shortcut
            if dataset.labels.maxMaterials > 255
                contIndex = dataset.selectedMaterial - 2;
                if contIndex < 1; return; end
                dataset.labels.materialNames{contIndex} = num2str(str2double(dataset.labels.materialNames{contIndex}) + 1);
                cSegmentation.updateMaterialsTable();
            end

        case {'Preset 1 use for the selected segmentation tool', ...
                'Preset 2 use for the selected segmentation tool', ...
                'Preset 3 use for the selected segmentation tool'}         % default 1, 2, 3
            error("MISSING IMPLEMENTATION: obj.mibUpdateSegmentationSettingsFromPreset(str2double(KeyShortcuts.Action{ActionId}(8)));")

        case {'Preset 1 update from the selected segmentation tool', ...
                'Preset 2 update from the selected segmentation tool', ...
                'Preset 3 update from the selected segmentation tool'}     % default Shift+1, Shift+2, Shift+3
            error("MISSING IMPLEMENTATION: obj.mibUpdatePresetFromSegmentationSettings(str2double(KeyShortcuts.Action{ActionId}(8)));")

        case 'Zoom to 100% view'  % should be define in Preferences
            error("MISSING IMPLEMENTATION: obj.mibToolbar_ZoomBtn_ClickedCallback('one2onePush');")

        case 'Zoom to fit the view'  % should be define in Preferences
            error("MISSING IMPLEMENTATION: obj.mibToolbar_ZoomBtn_ClickedCallback('fitPush');")

        case {'Brush size decrease', 'Brush size increase'}  % default [ and ] as well as shift+[ and shift+]
            Parameters = struct();
            Parameters.VerticalScrollCount = 1 - 2*strcmp(KeyShortcuts.Action{ActionId}, 'Brush size increase'); % +1 decrease, -1 increase
            Parameters.VerticalScrollAmount = 3;
            eventdata = core.ToggleEventData(Parameters);
            obj.gui_ScrollWheelFcn(eventdata);
            return;
    end
else    % all other possible shortcuts
    switch char
        case 'escape'
            % % detect escape when modifying the measurements, see Measure.drawROI method
            % if ~isempty(dataset.hMeasure.roi.imroi)
            %     if isvalid(dataset.hMeasure.roi.imroi)
            %         dataset.hMeasure.roi.imroi.setColor('r');
            %         resume(dataset.hMeasure.roi.imroi);
            %     end
            % end
            % % detect escape when modifying the ROIs, see mibRoiRegion.drawROI method
            % if ~isempty(dataset.hROI.roi.imroi)
            %     if isvalid(dataset.hROI.roi.imroi)
            %         dataset.hROI.roi.imroi.setColor('r');
            %         resume(dataset.hROI.roi.imroi);
            %     end
            % end
        case 'a'    % Select the Mask or Material (when mask is not shown) layer
            if strcmp(modifier, 'control') | strcmp(modifier, 'alt') %#ok<OR2>
                if dataset.labels.maxMaterials ~= 128
                    if strcmp(modifier, 'alt')
                        if dataset.selectedMaterial == 1
                            %obj.mibModel.moveLayers('mask', 'selection', '3D, Stack', 'replace');
                        elseif dataset.labels.exists
                            %obj.mibModel.moveLayers('labels', 'selection', '3D, Stack', 'replace');
                        end
                    else
                        if dataset.selectedMaterial == 1
                            %obj.mibModel.moveLayers('mask', 'selection', '2D, Slice', 'replace');
                        elseif dataset.labels.exists
                            %obj.mibModel.moveLayers('labels', 'selection', '2D, Slice', 'replace');
                        end
                    end
                end
                obj.showImage();
            end
        case 'control'  % increase the radius of the brush for the erase tool
            %if strcmp(modifier{1}, 'control') && obj.mibView.ctrlPressed == 0
            % if obj.mibModel.preferences.SegmTools.Brush.EraserRadiusFactor == 1; return; end
            % radius = str2double(obj.mibView.handles.mibSegmSpotSizeEdit.String);
            % obj.mibView.ctrlPressed = max([floor(radius*obj.mibModel.preferences.SegmTools.Brush.EraserRadiusFactor - radius) 1]);
            % obj.mibView.handles.mibSegmSpotSizeEdit.String = num2str(radius+obj.mibView.ctrlPressed);
            % obj.mibView.updateBrushCursor('solid');
            %end
    end
end