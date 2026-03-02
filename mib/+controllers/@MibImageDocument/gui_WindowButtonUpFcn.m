function gui_WindowButtonUpFcn(obj, brush_switch)
% function gui_WindowButtonUpFcn(obj, brush_switch)
% Callback for release of the mouse button.
%
% Linked via (example):
%   hFig.WindowButtonUpFcn = @(~,~)obj.gui_WindowButtonUpFcn();
%
% Performs three tasks in order:
%   1. If brush data exists (obj.brushSelection is a cell), commits the
%      drawn brush stroke to the selection layer, applying fill-holes,
%      material/mask restriction, and add/subtract mode as needed.
%   2. Clears brush state and updates ROI screen positions.
%   3. Restores all figure callbacks and pointer that were disabled during
%      panning or brush operation, then triggers a full image refresh.
%
% Parameters:
% brush_switch: char - when 'subtract', the brush stroke is removed from
%               the current selection instead of being added to it.
%               Needed for return after the brush eraser mode.
%               Default: '' (add mode)
%
% Return values:
%   (none)
%
% Updates
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
    currSelection = cell2mat(obj.mibModel.getData2D('selection', NaN, NaN, NaN, getDataOptions));

    % Fill holes in brush stroke if the auto-fill option is enabled
    if obj.mibController.cSegmentation.handles.autoFill.Value
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
        currModel = cell2mat(obj.mibModel.getData2D('labels', NaN, NaN, NaN, getDataOptions));
        obj.brushSelection{1}.selection(currModel ~= selcontour) = 0;
    end

    % Restrict brush stroke to the mask layer if enabled
    if dataset.restrictSelectionToMask
        mask = cell2mat(obj.mibModel.getData2D('mask', NaN, NaN, NaN, getDataOptions));
        obj.brushSelection{1}.selection(mask ~= 1) = 0;
    end

    % Write the final selection back to the model
    if strcmp(brush_switch, 'subtract')
        % Eraser mode: remove brush pixels from the existing selection
        currSelection(obj.brushSelection{1}.selection == 1) = 0;
        obj.mibModel.setData2D('selection', currSelection, NaN, NaN, NaN, getDataOptions);
    else
        % Add mode: OR the brush stroke into the existing selection
        obj.mibModel.setData2D('selection', uint8(currSelection | obj.brushSelection{1}.selection), NaN, NaN, NaN, getDataOptions);
    end

    % Add travelled brush distance to the gamification counter
    travelInMeters = obj.brushSelection{1}.travelPathInPixels * obj.mibModel.sessionSettings.metersPerPixel;
    obj.mibModel.preferences.Users.Tiers.brushTravelDistance = ...
        obj.mibModel.preferences.Users.Tiers.brushTravelDistance + travelInMeters;
    obj.mibModel.preferences.Users.Tiers.collectedPoints = ...
        obj.mibModel.preferences.Users.Tiers.collectedPoints + travelInMeters * 10; % add to scores
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

% turn ON callback for the keys
hFig.WindowKeyPressFcn = @(~, ~)obj.gui_WindowKeyPressFcn();

% Restore scroll wheel callback (moved from plotImage)
hFig.WindowScrollWheelFcn = @(~, eventdata)obj.gui_ScrollWheelFcn(eventdata);

% Restore mouse motion callback (moved from plotImage)
hFig.WindowButtonMotionFcn = @(~, ~)obj.gui_WinMouseMotionFcn();

% Re-show the center spot marker if it was hidden during pan
if ~isempty(obj.centralMarker)
    obj.centralMarker.Visible = true;
end

% Refresh the full image display
obj.mibController.showImage();

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

if showCongratulations
    pause(0.5);
    utils.dlgs.showMilestoneDialog(obj.mibModel.mibPath, obj.mibModel.preferences.Users, ...
        'milestoneReached', struct('ParentFigure', obj.mibController.view.gui));

end
