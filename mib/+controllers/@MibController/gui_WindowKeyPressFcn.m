function gui_WindowKeyPressFcn(obj, hWidget, hData)
% GUI_WINDOWKEYPRESSFCN - Callback for a key press in MIB.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.gui_WindowKeyPressFcn(hWidget, hData)
%
% Linked via: obj.UIFigure.WindowKeyPressFcn = @(~, ~)obj.gui_WindowKeyPressFcn();
%
% Input Arguments:
%   - **hWidget** — handle to the UIFigure that received the key event
%   - **hData** — ``matlab.ui.eventdata.KeyData`` event data; use ``hData.Key``
%     and ``hData.Modifier`` to identify the pressed key and modifier state
%
% Output Arguments:
%   (none)
%

% Read key data from the event object (hData), NOT from hFigure.CurrentKey.
% hFigure.CurrentKey is a stale cached property that retains the last key
% pressed on that figure — even when a completely different figure fires the
% callback (e.g. MibDirContents after a save dialog closes).  hData is
% scoped to the exact event that triggered this invocation, so it is always
% correct regardless of which figure is in focus.
if isempty(hData) || ~isprop(hData, 'Key') || isempty(hData.Key); return; end
char     = lower(hData.Key);
modifier = hData.Modifier;  % cell array of modifier strings, e.g. {'control'}
obj.currentModifier = modifier;   % store for button callbacks that can't read UIFigure.CurrentModifier

% Skip if the focused component is an edit field or text area.
% Use hWidget (the figure that fired the event) — CurrentObject is only
% set on the event-source figure.
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

% In split-panel mode, determine which document panel the mouse is hovering over.
% Keyboard events always arrive on one UIFigure regardless of which panel has
% the cursor, so we cannot rely on Sets.selectedSet for view-navigation keys
% (zoom, cursor repositioning). For those keys we use the hovered panel.
hoverDocIdx = obj.mibModel.Sets.selectedSet;
for iHoverDoc = 1:numel(obj.cImageDoc)
    if obj.cImageDoc{iHoverDoc}.isInsideAxes
        hoverDocIdx = iHoverDoc;
        break;
    end
end
cImageDoc = obj.cImageDoc{hoverDocIdx};
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
            notify(obj.mibModel, 'AddMeasurement');
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
            % Refresh pixel label so the NEXT keypress reads YX coordinates, not stale ones from the
            % previous orientation.  orientationChange() physically moves the cursor via
            % centerCursorInAxes() but gui_WinMouseMotionFcn doesn't fire until the next event-loop
            % tick — calling it explicitly here keeps the label in sync.
            cImageDoc.gui_WinMouseMotionFcn();
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
            cImageDoc.gui_WinMouseMotionFcn();  % keep pixel label in sync after cursor reposition
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
            cImageDoc.gui_WinMouseMotionFcn();  % keep pixel label in sync after cursor reposition
        case 'Interpolate selection'            % default 'i'
            obj.mibModel.interpolateImage('selection');
        case 'Invert image'                     % default 'Ctrl + i'
            obj.mibModel.invertImage('4D, Dataset');
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
            selectionTo = 'labels';
            if dataset.getSelectedMaterialIndex('AddTo') == -1; selectionTo = 'mask'; end
            obj.currentModifier = {};  % clear before notify/drawnow yield points below
            obj.mibModel.moveLayers('selection', selectionTo, layerScope, operation);

        case 'Clear selection'                          % default 'c'/'Shift+c'
            obj.cSelection.clearSelection();

        case {'Fill the holes in the Selection layer', 'Erode the Selection layer', 'Dilate the Selection layer'}
            % default 'f'/'Shift+f', 'z'/'Shift+z', 'x'/'Shift+x'
            if dataset.enableSelection == 0; return; end

            switch KeyShortcuts.Action{ActionId}
                case 'Fill the holes in the Selection layer' 
                    obj.cSelection.fillSelection();
                case 'Erode the Selection layer'              
                    obj.cSelection.erodeSelection();
                case 'Dilate the Selection layer'             
                    obj.cSelection.dilateSelection();
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
                    shift = cImageDoc.sliderZStep;
                    if shiftPressed; shift = cImageDoc.sliderZShiftStep; end
                    new_index = max(1, min(dataset.dim_yxzct(dataset.orientation), dataset.slices{dataset.orientation}(1) + direction*shift));
                    dataset.slices{dataset.orientation} = [new_index, new_index];
                    cImageDoc.handles.sliceNumberSlider.Value = new_index;
                    cImageDoc.sliceNumberSlider_Callback();
                end
            else
                % Zoom in/out: apply to the panel the mouse is hovering over.
                % Sync mibModel state so zoomEdit_Callback uses the correct
                % dataset/panel for axis reads and cursor repositioning.
                if hoverDocIdx ~= obj.mibModel.Sets.selectedSet
                    obj.mibModel.Sets.selectedSet = hoverDocIdx;
                    obj.mibModel.id = obj.mibModel.Sets.selectedDataset(hoverDocIdx) + ...
                        (hoverDocIdx-1)*obj.mibModel.Sets.datasetsInSet;
                end
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
            if dataset.getSelectedMaterialIndex() < 1; return; end
            obj.mibModel.materialsActions('Rename material');

        case 'Show/hide the Model layer'                % default 'space'
            newValue = logical(abs(obj.cSelection.handles.showModel.Value - 1));
            obj.cSelection.handles.showModel.Value = newValue;
            obj.mibModel.showModel = newValue;
            obj.showImage();
        case 'Show/hide the Mask layer'                 % default 'Ctrl + space'
            newValue = logical(abs(obj.cSelection.handles.showMask.Value - 1));
            obj.cSelection.handles.showMask.Value = newValue;
            obj.mibModel.showMask = newValue;
            obj.showImage();

        case 'Fix selection to material'
            cSegmentation.handles.restrictMaterial.Value = abs(cSegmentation.handles.restrictMaterial.Value - 1);
            cSegmentation.restrictMaterial_Callback();

        case 'Save image as...'                         % default 'Ctrl + s'
            obj.mibModel.saveImage('image');

        case 'Copy to buffer selection from the current slice'  % default 'Ctrl + c'
            obj.cRibbon.selectionBuffer('copy');

        case 'Paste buffered selection to the current slice'    % default 'Ctrl + v'
            obj.currentModifier = {};   % clear before selectionBuffer may open a dialog
            obj.cRibbon.selectionBuffer('paste');

        case 'Paste buffered selection to all slices'           % default 'Ctrl + Shift + v'
            obj.currentModifier = {};   % clear before uiprogressdlg steals the KeyRelease event
            obj.cRibbon.selectionBuffer('pasteall');

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
                nextTool = obj.mibModel.preferences.SegmTools.FavoriteTools(max([1 find(obj.mibModel.preferences.SegmTools.FavoriteTools > toolId, 1)]));
            elseif actionName(end) == 'A'  % favorite tool A, 'Shift+D' shortcut
                nextTool = find(strcmp(toolList, obj.mibModel.preferences.SegmTools.FavoriteToolA), 1);
            else % 'B'  % favorite tool B, 'Ctrl+D' shortcut
                nextTool = find(strcmp(toolList, obj.mibModel.preferences.SegmTools.FavoriteToolB), 1);
            end

            % show information text
            axPos  = getpixelposition(cImageDoc.handles.imViewAxes, true);  % [x y w h] in figure pixels
            % axPos(1) = left edge of axes
            % axPos(2) = bottom edge of axes
            % axPos(3) = axes width
            % axPos(4) = axes height
            lblW = 340;
            lblH = 85;
            lblX = axPos(1) + (axPos(3) - lblW) / 2;   % horizontally centered over axes
            lblY = axPos(2) + axPos(4) * 0.65;         % 65% up the axes height

            msg = sprintf('<div style="background:#ff9e46;border-radius:10px;padding:12px 24px;font-family:Arial;font-size:20px;font-weight:bold;font-style:italic;color:#1a1a1a;text-align:center;box-shadow:2px 2px 8px rgba(0,0,0,0.2)">%s</div>', toolList{nextTool});
             
            fittext = uihtml(cImageDoc.UIFigure, 'HTMLSource', msg, ...
                'Position', [lblX lblY lblW lblH]);
            pause(.3);

            cSegmentation.handles.segmTool.ValueIndex = nextTool;
            cSegmentation.segmentationTool_Callback();
            delete(fittext);

        case 'Undo/Redo last action'                    % default 'Ctrl + z'
            if ~obj.mibModel.Backup.enableSwitch; return; end
            if obj.mibModel.Backup.prevUndoIndex == 0; return; end
            % Clear modifier before undo: the undo chain triggers UI updates
            % (DatasetsPanelUpdate, updateGuiWidgets) that can shift focus to a
            % panel without WindowKeyReleaseFcn, causing the KeyRelease event to
            % fire there and never reach gui_WindowKeyReleaseFcn.
            obj.currentModifier = {};
            obj.mibModel.undo();
            % When Membrane ClickTracker is active, pop the last tracker
            % point so the next click continues from the previous chain point
            if strcmp(cSegmentation.handles.segmTool.Value, 'Membrane ClickTracker') && ...
                    size(cImageDoc.trackerYXZ, 2) > 1
                cImageDoc.trackerYXZ = cImageDoc.trackerYXZ(:, 1:end-1);
            end
            obj.showImage();

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
            obj.cSelection.updateSettingsFromPreset(str2double(KeyShortcuts.Action{ActionId}(8)));

        case {'Preset 1 update from the selected segmentation tool', ...
                'Preset 2 update from the selected segmentation tool', ...
                'Preset 3 update from the selected segmentation tool'}     % default Shift+1, Shift+2, Shift+3
            obj.cSelection.updateSegmentationPreset(str2double(KeyShortcuts.Action{ActionId}(8)));
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
        case 'return'
            % Finish custom Polyline Stage 1 placement on Enter
            if obj.mibModel.disableSegmentation
                cRoiCtrl = obj.cRoi;
                if ~isempty(cRoiCtrl) && cRoiCtrl.drawingROI.placementMode
                    uiresume(cImageDoc.UIFigure);
                    return;
                end
            end
        case 'escape'
            % Cancel custom Polyline Stage 1 placement on Escape
            if obj.mibModel.disableSegmentation
                cRoiCtrl = obj.cRoi;
                if ~isempty(cRoiCtrl) && cRoiCtrl.drawingROI.placementMode
                    cRoiCtrl.drawingROI.placementVertices = [];  % signal cancellation
                    uiresume(cImageDoc.UIFigure);
                    return;
                end
            end
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
            if strcmp(modifier, 'control') | strcmp(modifier, 'alt') 
                if dataset.labels.maxMaterials ~= 128
                    if strcmp(modifier, 'alt')
                        if dataset.selectedMaterial == 1
                            obj.mibModel.moveLayers('mask', 'selection', '3D, Stack', 'replace');
                        elseif dataset.labels.exists
                            obj.mibModel.moveLayers('labels', 'selection', '3D, Stack', 'replace');
                        end
                    else
                        if dataset.selectedMaterial == 1
                            obj.mibModel.moveLayers('mask', 'selection', '2D, Slice', 'replace');
                        elseif dataset.labels.exists
                            obj.mibModel.moveLayers('labels', 'selection', '2D, Slice', 'replace');
                        end
                    end
                end
                obj.showImage();
            end
        case 'control'  % temporarily enlarge brush radius for eraser mode
            if controlSw && obj.view.ctrlPressed == 0
                if obj.mibModel.preferences.SegmTools.Brush.EraserRadiusFactor == 1; return; end
                radius = cSegmentation.handles.brushRadius.Value;
                obj.view.ctrlPressed = max([floor(radius * obj.mibModel.preferences.SegmTools.Brush.EraserRadiusFactor - radius), 1]);
                cSegmentation.handles.brushRadius.Value = radius + obj.view.ctrlPressed;
                cImageDoc.updateBrushCursor([], '-', true);
            end
    end
end

% When the keypress came from a child panel (MibSelection, DisplayAdjust, etc.)
% that has no WindowKeyReleaseFcn registered, the key-release event fires on that
% panel's figure and never reaches gui_WindowKeyReleaseFcn — so currentModifier
% would stay stale.  Clear it here after the action is handled.
if isempty(hWidget.WindowKeyReleaseFcn)
    obj.currentModifier = {};
end
end
