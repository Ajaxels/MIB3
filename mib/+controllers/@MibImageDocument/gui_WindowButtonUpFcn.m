function gui_WindowButtonUpFcn(obj, brush_switch)
% GUI_WINDOWBUTTONUPFCN - Callback for release of the mouse button.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.gui_WindowButtonUpFcn()
%      obj.gui_WindowButtonUpFcn(brush_switch)
%
% Linked via:
%
%   .. code-block:: matlab
%
%      hFig.WindowButtonUpFcn = @(~,~)obj.gui_WindowButtonUpFcn();
%
% Performs three tasks in order:
%   1. If brush data exists (``obj.brushSelection`` is a cell), commits drawn brush stroke
%      to selection layer, applying fill-holes, material/mask restriction, and add/subtract mode
%   2. Clears brush state and updates ROI screen positions
%   3. Restores all figure callbacks and pointer disabled during panning or brush operation,
%      then triggers full image refresh
%
% Input Arguments:
%   - **brush_switch** *(optional)* - [char] brush mode: when ``'subtract'``, brush stroke is removed from
%     current selection instead of being added (needed for eraser mode); default: ``''`` (add mode)
%
% Output Arguments:
%   (none)
%

showCongratulations = false; % switch to show the milestone congratulations

if nargin < 2; brush_switch = ''; end

% ---- 1. Commit brush stroke (if brush tool was active) ----
if iscell(obj.brushSelection) % return after movement of the brush tool

    % If a secondary brush slice exists (eraser tweak), swap in the
    % accumulated selection that was built during the stroke.
    if numel(obj.brushSelection) > 1
        obj.brushSelection{1}.selection = obj.brushSelection{2}.selectedSlic;
    end

    % Read the current selection from the model (block-mode aware)
    getDataOptions.blockModeSwitch = 1;
    getDataOptions.roiId = -1;
    currSelection = cell2mat(obj.mibModel.getData2D('selection', [], [], NaN, getDataOptions));

    % With no committed selection layer (e.g. a BigData set opened browse-only,
    % no model created yet) getData2D returns empty - skip the commit instead of
    % crashing on a 0-size imresize. The callback cleanup further below still runs.
    if ~isempty(currSelection)

    % Fill holes in brush stroke if the auto-fill option is enabled
    if obj.mibModel.autoFillSelection
        obj.brushSelection{1}.selection = imfill(obj.brushSelection{1}.selection, 'holes');
    end

    % Resize brush mask to match the on-disk selection size
    % (may differ when block mode is active or image is zoomed)
    obj.brushSelection{1}.selection = imresize(obj.brushSelection{1}.selection, size(currSelection), 'method', 'nearest');

    % % smooth brush, quite slow
    % filterOptions.fitType = 'Gaussian';
    % filterOptions.hSize = 11;
    % filterOptions.sigma = filterOptions.hSize;
    % filterOptions.showWaitbar = 0;
    % filterOptions.dataType = '3D';
    % filterOptions.orientation = 4;
    % obj.brushSelection{1}.selection = mibDoImageFiltering(obj.brushSelection{1}.selection, filterOptions);

    dataset = obj.mibModel.I{obj.mibModel.id};
    selcontour = dataset.getSelectedMaterialIndex();

    % Restrict brush stroke to the currently selected material if enabled
    if dataset.restrictSelectionToMaterial
        currModel = cell2mat(obj.mibModel.getData2D('labels', [], [], NaN, getDataOptions));
        obj.brushSelection{1}.selection(currModel ~= selcontour) = 0;
    end

    % Restrict brush stroke to the mask layer if enabled
    if dataset.restrictSelectionToMask
        mask = cell2mat(obj.mibModel.getData2D('mask', [], [], NaN, getDataOptions));
        obj.brushSelection{1}.selection(mask ~= 1) = 0;
    end

    % Write the final selection back to the model
    if strcmp(brush_switch, 'subtract')
        % Eraser mode: remove brush pixels from the existing selection
        currSelection(obj.brushSelection{1}.selection == 1) = 0;
        obj.mibModel.setData2D(currSelection, 'selection', [], [], NaN, getDataOptions);
    else
        % Add mode: OR the brush stroke into the existing selection
        obj.mibModel.setData2D(uint8(currSelection | obj.brushSelection{1}.selection), 'selection', [], [], NaN, getDataOptions);
    end

    % Add travelled brush distance to the gamification counter
    travelInMeters = obj.brushSelection{1}.travelPathInPixels * obj.mibModel.sessionSettings.metersPerPixel;
    obj.mibModel.preferences.Users.Tiers.brushTravelDistance = ...
        obj.mibModel.preferences.Users.Tiers.brushTravelDistance + travelInMeters;
    obj.mibModel.preferences.Users.Tiers.collectedPoints = ...
        obj.mibModel.preferences.Users.Tiers.collectedPoints + travelInMeters * 10; % add to scores
    end   % if ~isempty(currSelection)
end

% ---- 2. Clear brush state and update ROI positions ----
obj.brushSelection = []; % remove all brush_selection data
obj.brushPrevXY = [];

% % update ROI of the Measure tool
% if ~isempty(obj.mibModel.I{obj.mibModel.id}.hMeasure.roi.type)
%     obj.mibModel.I{obj.mibModel.id}.hMeasure.updateROIScreenPosition('crop');
% end

% % update ROI of the hROI class
% if ~isempty(obj.mibModel.I{obj.mibModel.id}.hROI.roi.type)
%     obj.mibModel.I{obj.mibModel.id}.hROI.updateROIScreenPosition('crop');
% end

% ---- 3. Restore figure callbacks and pointer ----
hFig = obj.UIFigure;

% Restore default crosshair pointer
hFig.Pointer = 'crosshair';

% Clear the button-up callback (self) first
hFig.WindowButtonUpFcn = [];

% Restore the button-down callback
hFig.WindowButtonDownFcn = @(~, ~)obj.gui_WindowButtonDownFcn();

% turn ON callback for the keys; if a quick measurement is active, restore
% its key handler (panning clears it) rather than the standard one.
if ~isempty(obj.quickMeasure) && isfield(obj.quickMeasure, 'measureKPF') && ...
        ~isempty(obj.quickMeasure.measureKPF)
    hFig.WindowKeyPressFcn = obj.quickMeasure.measureKPF;
else
    hFig.WindowKeyPressFcn = @(hWidget, hData)obj.mibController.gui_WindowKeyPressFcn(hWidget, hData);
end

% Restore scroll wheel callback 
hFig.WindowScrollWheelFcn = @(~, eventdata)obj.gui_ScrollWheelFcn(eventdata);

% Restore mouse motion callback 
hFig.WindowButtonMotionFcn = @(~, ~)obj.gui_WinMouseMotionFcn();

% Re-show the center spot marker if it was hidden during pan
if ~isempty(obj.centralMarker)
    obj.centralMarker.Visible = true;
end
% Re-show quick measure ROI and label now that axes limits are stable
if ~isempty(obj.quickMeasure) && isfield(obj.quickMeasure, 'roi') && ...
        ~isempty(obj.quickMeasure.roi) && isvalid(obj.quickMeasure.roi)
    obj.quickMeasure.roi.Visible = true;
end
if ~isempty(obj.quickMeasure) && isfield(obj.quickMeasure, 'textH') && ...
        ~isempty(obj.quickMeasure.textH) && isvalid(obj.quickMeasure.textH)
    obj.quickMeasure.textH.Visible = true;
end

% Refresh the full image display, explicitly specifying this document's set
% so the correct panel is rendered regardless of mibModel.Sets.selectedSet state.
obj.mibController.showImage(true, obj.setOfDatasetsIndex);

% Update the dashed brush cursor outline for the next stroke
% Pass [] so the position is read from CurrentPoint (not treated as xy)
obj.updateBrushCursor([], ':');

% ---- Gamification: check for tier-level milestone ----
%obj.mibModel.preferences.Users.Tiers.brushTravelDistance
% showCongratulations = true;
%obj.mibModel.preferences.Users.Tiers.collectedPoints = 998;
%obj.mibModel.preferences.Users.Tiers.tierLevel = 1;
% fprintf('Collected points: %f\n', obj.mibModel.preferences.Users.Tiers.collectedPoints);
if obj.mibModel.preferences.Users.Tiers.collectedPoints > ...
        obj.mibModel.preferences.Users.tierPointsCoef * 2^obj.mibModel.preferences.Users.Tiers.tierLevel
    obj.mibModel.preferences.Users.Tiers.tierLevel = obj.mibModel.preferences.Users.Tiers.tierLevel + 1;
    showCongratulations = true;
end

% show milestone dialog upon next level reach
if showCongratulations
    pause(0.5);
    utils.dlgs.showMilestoneDialog(obj.mibController.view.gui, obj.mibModel.preferences.Users, ...
        'milestoneReached', struct('mibPath', obj.mibModel.mibPath));
    
    % update MIB title
    titleString = sprintf('MIB %s', obj.mibController.mibVersion);
    if isdeployed; titleString = sprintf('%s deployed version', titleString); end
    titleString = [titleString '    level ' obj.mibModel.preferences.Users.tierLevelRanks{min(obj.mibModel.preferences.Users.Tiers.tierLevel, numel(obj.mibModel.preferences.Users.tierLevelRanks))}];
    obj.view.gui.Title =  titleString;

end
