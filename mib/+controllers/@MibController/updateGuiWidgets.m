function updateGuiWidgets(obj, updatePanels)
% UPDATEGUIWIDGETS - Update user interface widgets based on the properties of the currently open dataset.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.updateGuiWidgets()
%      obj.updateGuiWidgets(updatePanels)
%
% Refreshes the named subsets of the GUI; when called with no arguments (or
% an empty cell array) every panel is refreshed.  Callers that know which
% panel changed should pass the relevant name(s) to avoid unnecessary work.
%
% Input Arguments:
%   - **updatePanels** — *(optional)* char or cell array of chars identifying the
%     panel(s) to refresh.  Pass ``{}`` or omit to refresh everything.  Valid
%     name strings:
%
%     - ``'ribbonImage'``        — Image ribbon tab (bit depth, color type)
%     - ``'ribbonModel'``        — Model ribbon tab (model type radio buttons)
%     - ``'QuickAccessBar'``     — Orientation buttons, ROI, block-mode toggle
%     - ``'depthSlider'``        — Z-slice number slider and edit field
%     - ``'timeSlider'``         — Time-frame slider and edit field
%     - ``'checkboxes'``         — Show mask / model checkboxes, restrict controls
%     - ``'imView'``             — Image view panel title
%     - ``'activeDataset'``      — Dataset buffer buttons in the Datasets panel
%     - ``'dirContentsDataset'`` — Directory contents file list and filter
%     - ``'panelThresholding'``  — Black/white threshold sliders
%     - ``'roi'``                — ROI related items
%     - ``'selectionPanel'``     — LUT checkbox and colour table
%     - ``'statusBar'``          — Status bar current-directory field
%
% Output Arguments:
%   (none)
%
% **Example 1** — refresh ALL panels (e.g. after loading a new dataset):
%
%   .. code-block:: matlab
%
%      obj.updateGuiWidgets();
%
% **Example 2** — refresh only the Model ribbon tab and the checkboxes panel:
%
%   .. code-block:: matlab
%
%      obj.updateGuiWidgets({'ribbonModel', 'checkboxes'});
%
% **Example 3** — trigger a full refresh via the MibModel event bus:
%
%   .. code-block:: matlab
%
%      notify(obj.mibModel, 'UpdateGuiWidgets');
%
% **Example 4** — trigger a selective refresh via the MibModel event bus:
%
%   .. code-block:: matlab
%
%      eventdata = core.ToggleEventData({'ribbonModel', 'checkboxes'});
%      notify(obj.mibModel, 'UpdateGuiWidgets', eventdata);
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibController.updateGuiWidgets triggered\n');
end

% Guard against shutdown: widgets inside document panels may already be
% deleted while a queued UpdateGuiWidgets event is still in flight.
selectedSet = obj.mibModel.Sets.selectedSet;
if selectedSet > numel(obj.cImageDoc) || ...
        ~isvalid(obj.cImageDoc{selectedSet}) || ...
        ~isvalid(obj.cImageDoc{selectedSet}.handles.imViewAxes)
    return;
end

% define cell array of panels to update, when empty update all panels
if nargin < 2; updatePanels = {}; end

% create a alias for the dataset
dataset = obj.mibModel.I{obj.mibModel.id};

% get new filename
[newFileDir, newFileName, newFileExt] = fileparts(dataset.image.filename);
newFileBasename = [newFileName newFileExt];
if isempty(newFileDir)  % placeholder dataset (e.g. 'none.tif') — keep current directory
    newFileDir = obj.mibModel.currentDirectory;
end

%% Update the IMAGE TAB ---------------------------------------------
% -------------------------------------------------------------------
if isempty(updatePanels) || ismember('ribbonImage', updatePanels)
    % get short handle to ribbonImage
    ribbonImage = obj.cRibbon.handles.ribbonImage;
    if isempty(ribbonImage)
        % lazily init the tab
        obj.globalTabGroup_SelectionCallback('Image');
        ribbonImage = obj.cRibbon.handles.ribbonImage;
    end

    if strcmp(dataset.image.dataClass, 'uint8') && ~ribbonImage.bit8.Value
        % update 8bit checkbox
        ribbonImage.bit8.Value = true;
        ribbonImage.bit16.Value = false;
        ribbonImage.bit32.Value = false;
    elseif strcmp(dataset.image.dataClass, 'uint16') && ~ribbonImage.bit16.Value
        % update 16bit checkbox
        ribbonImage.bit8.Value = false;
        ribbonImage.bit16.Value = true;
        ribbonImage.bit32.Value = false;
    elseif strcmp(dataset.image.dataClass, 'uint32') && ~ribbonImage.bit32.Value
        % update 32bit checkbox
        ribbonImage.bit8.Value = false;
        ribbonImage.bit16.Value = false;
        ribbonImage.bit32.Value = true;
    end
      
    % update color type
    if strcmp(dataset.image.colorType, 'grayscale') && ~ribbonImage.grayscale.Value
        % update grayscale checkbox
        ribbonImage.grayscale.Value = true;
        ribbonImage.grayscale.Enabled = true;
        ribbonImage.multichannel.Value = false;
        ribbonImage.hsv.Value = false;
        ribbonImage.hsv.Enabled = false;
        ribbonImage.indexed.Value = false;
        ribbonImage.indexed.Enabled = true;
    elseif strcmp(dataset.image.colorType, 'multichannel') && ~ribbonImage.multichannel.Value
        ribbonImage.grayscale.Value = false;
        ribbonImage.grayscale.Enabled = true;
        ribbonImage.multichannel.Value = true;
        ribbonImage.hsv.Value = false;
        ribbonImage.hsv.Enabled = true;
        ribbonImage.indexed.Value = false;
        ribbonImage.indexed.Enabled = true;
    elseif strcmp(dataset.image.colorType, 'hsvcolor') && ~ribbonImage.hsv.Value
        ribbonImage.grayscale.Value = false;
        ribbonImage.grayscale.Enabled = false;
        ribbonImage.multichannel.Value = false;
        ribbonImage.hsv.Value = true;
        ribbonImage.hsv.Enabled = true;
        ribbonImage.indexed.Value = false;
        ribbonImage.indexed.Enabled = false;
    elseif strcmp(dataset.image.colorType, 'indexed') && ~ribbonImage.indexed.Value
        ribbonImage.grayscale.Value = false;
        ribbonImage.grayscale.Enabled = true;
        ribbonImage.multichannel.Value = false;
        ribbonImage.hsv.Value = false;
        ribbonImage.hsv.Enabled = false;
        ribbonImage.indexed.Value = true;
        ribbonImage.indexed.Enabled = true;
    end
end

%% Update the MODEL TAB ---------------------------------------------
% -------------------------------------------------------------------
if isempty(updatePanels) || ismember('ribbonModel', updatePanels)
    % get short handle to ribbonImage
    ribbonModel = obj.cRibbon.handles.ribbonModel;
    if isempty(ribbonModel)
        % lazily init the tab
        obj.globalTabGroup_SelectionCallback('Model');
        ribbonModel = obj.cRibbon.handles.ribbonModel;
    end

    if dataset.labels.maxMaterials == 63 && ~ribbonModel.mat63.Value
        ribbonModel.mat63.Value = true;
        ribbonModel.mat255.Value = false;
        ribbonModel.mat65535.Value = false;
        ribbonModel.mat4294967295.Value = false;
    elseif dataset.labels.maxMaterials == 255 && ~ribbonModel.mat255.Value
        ribbonModel.mat63.Value = false;
        ribbonModel.mat255.Value = true;
        ribbonModel.mat65535.Value = false;
        ribbonModel.mat4294967295.Value = false;
    elseif dataset.labels.maxMaterials == 65535 && ~ribbonModel.mat65535.Value
        ribbonModel.mat63.Value = false;
        ribbonModel.mat255.Value = false;
        ribbonModel.mat65535.Value = true;
        ribbonModel.mat4294967295.Value = false;
    elseif dataset.labels.maxMaterials == 4294967295 && ~ribbonModel.mat4294967295.Value
        ribbonModel.mat63.Value = false;
        ribbonModel.mat255.Value = false;
        ribbonModel.mat65535.Value = false;
        ribbonModel.mat4294967295.Value = true;
    end
    
    % update buttons of the segmentation panel if needed
    segmHandles = obj.view.handles.panels.segmentation.handles;
    if dataset.labels.maxMaterials < 256 && ... 
            (isempty(segmHandles.addMaterial.Icon) || ~strcmp(segmHandles.addMaterial.Tooltip, 'Add a new material to the model'))
        % update the buttons in the panel to match the model type with less than 256 materials

        % update the add material button
        segmHandles.addMaterial.Icon = core.MibIconCache.get('alpha_cache', 'plus_16px');
        segmHandles.addMaterial.Tooltip = 'Add a new material to the model';
        if obj.mibModel.preferences.System.DeveloperMode
            segmHandles.addMaterial.Tooltip = sprintf('obj.cSegmentation.view.handles.addMaterial:\n%s', segmHandles.addMaterial.Tooltip);
        end
        % update the remove material button
        segmHandles.removeMaterial.Icon = core.MibIconCache.get('alpha_cache', 'minus_16px');
        segmHandles.removeMaterial.Tooltip = 'Remove selected material from the model';
        if obj.mibModel.preferences.System.DeveloperMode
            segmHandles.addMaterial.Tooltip = sprintf('obj.cSegmentation.view.handles.removeMaterial:\n%s', segmHandles.removeMaterial.Tooltip);
        end
    elseif dataset.labels.maxMaterials > 256 && ~strcmp(segmHandles.addMaterial.Tooltip, 'Find and select the next empty material')
        % update the buttons in the panel to match the model type with more than 256 materials
        
        % update the add material button -> to next material
        segmHandles.addMaterial.Icon = core.MibIconCache.get('alpha_cache', 'next_16px');
        segmHandles.addMaterial.Tooltip = 'Find and select the next empty material';
        if obj.mibModel.preferences.System.DeveloperMode
            segmHandles.addMaterial.Tooltip = sprintf('obj.cSegmentation.view.handles.addMaterial:\n%s', segmHandles.addMaterial.Tooltip);
        end
        % update the remove material button -> squeeze the labels
        segmHandles.removeMaterial.Icon = core.MibIconCache.get('alpha_cache', 'shrink_16px');
        segmHandles.removeMaterial.Tooltip = 'Squeeze the labels to remove all empty indices and select next available index';
        if obj.mibModel.preferences.System.DeveloperMode
            segmHandles.addMaterial.Tooltip = sprintf('obj.cSegmentation.view.handles.removeMaterial:\n%s', segmHandles.removeMaterial.Tooltip);
        end
    end
end


%% Update sliders ---------------------------------------------
% -------------------------------------------------------------
if isempty(updatePanels) || ismember('depthSlider', updatePanels)
    % get alias to handles
    imViewHandles = obj.cImageDoc{selectedSet}.handles;
    max_slice = dataset.dim_yxzct(dataset.orientation);
    currentSlice = min(dataset.slices{dataset.orientation}(1), max_slice); % clamp: guard against stale post-crop values

    if max_slice > 1 && max_slice ~= imViewHandles.sliceNumber.Limits(2) - 0.001
        imViewHandles.sliceNumber.Limits = [1 max_slice+0.001]; % add small value to make sure that limits are not the same
        imViewHandles.sliceNumberSlider.Limits = [1 max_slice+0.001];
        imViewHandles.sliceNumberSlider.MinorTicks = 1:(max_slice-1)/10:max_slice;
        % show the slider panel
        if imViewHandles.mainGridLayout.ColumnWidth{1} ~= 30; imViewHandles.mainGridLayout.ColumnWidth{1} = 30; end
    elseif max_slice == 1 && max_slice ~= imViewHandles.sliceNumber.Limits(2) - 0.001
        imViewHandles.sliceNumber.Limits = [1 max_slice+0.001];
        imViewHandles.sliceNumberSlider.Limits = [1 max_slice+0.001];
        % hide the slider panel
        if imViewHandles.mainGridLayout.ColumnWidth{1} ~= 0; imViewHandles.mainGridLayout.ColumnWidth{1} = 0; end
    end
    % always sync the slider/edit value to the active dataset's current slice
    imViewHandles.sliceNumber.Value = currentSlice;
    imViewHandles.sliceNumberSlider.Value = currentSlice;
end

% update time slider
if isempty(updatePanels) || ismember('timeSlider', updatePanels)
    % get alias to handles
    imViewHandles = obj.cImageDoc{selectedSet}.handles;
    currentTime = min(dataset.slices{5}(1), dataset.image.time); % clamp: guard against stale post-crop values

    if dataset.image.time > 1 && dataset.image.time ~= imViewHandles.frameNumber.Limits(2) - 0.001
        imViewHandles.frameNumber.Limits = [1 dataset.image.time+0.001]; % add small value to make sure that limits are not the same
        imViewHandles.frameNumberSlider.Limits = [1 dataset.image.time+0.001];
        imViewHandles.frameNumberSlider.MinorTicks = 1:(dataset.image.time-1)/10:dataset.image.time;
        % show the slider panel
        if imViewHandles.mainGridLayout.RowHeight{2} ~= 20; imViewHandles.mainGridLayout.RowHeight{2} = 20; end
    elseif dataset.image.time == 1 && dataset.image.time ~= imViewHandles.frameNumber.Limits(2) - 0.001
        % hide the slider panel
        if imViewHandles.mainGridLayout.RowHeight{2} ~= 0; imViewHandles.mainGridLayout.RowHeight{2} = 0; end
        imViewHandles.frameNumber.Limits = [1 dataset.image.time+0.001];
        imViewHandles.frameNumberSlider.Limits = [1 dataset.image.time+0.001];
    end
    % always sync the slider/edit value to the active dataset's current frame
    imViewHandles.frameNumber.Value = currentTime;
    imViewHandles.frameNumberSlider.Value = currentTime;
end


%% Update checkboxes ---------------------------------------------
% ----------------------------------------------------------------
if isempty(updatePanels) || ismember('checkboxes', updatePanels)
    % create aliases
    selectionPanelHandles = obj.view.handles.panels.selection.handles;
    segmentationPanelHandles = obj.view.handles.panels.segmentation.handles;
    
    % update show mask checkbox
    if ~dataset.maskExist
        if selectionPanelHandles.showMask.Value
            selectionPanelHandles.showMask.Value = false;
        end
        if segmentationPanelHandles.restrictMask.Value
            segmentationPanelHandles.restrictMask.Value = false;
            segmentationPanelHandles.restrictMask.FontColor = segmentationPanelHandles.favoriteTool.FontColor;
        end
        dataset.restrictSelectionToMask = false;
        obj.mibModel.showMask = false;
    end

    % update show model checkbox
    selectionPanelHandles.showModel.Value = obj.mibModel.showModel;
    if selectionPanelHandles.showModel.Value && ~dataset.labels.exists
        selectionPanelHandles.showModel.Value = false;
        obj.mibModel.showModel = false;
        dataset.restrictSelectionToMaterial = false;
    end

    % update Restrict to Mask status
    if segmentationPanelHandles.restrictMask.Value ~= dataset.restrictSelectionToMask
        segmentationPanelHandles.restrictMask.Value = dataset.restrictSelectionToMask;
        obj.cSegmentation.restrictMask_Callback();
    end

    % update Restrict to Material status and redraw Materials table
    % using obj.updateSegmentationTable() inside mibSegmSelectedOnlyCheck_Callback
    segmentationPanelHandles.restrictMaterial.Value = dataset.restrictSelectionToMaterial;
    % update materialsTable
    obj.cSegmentation.restrictMaterial_Callback();

    % update Show selected material only
    if logical(segmentationPanelHandles.materialsTableContextShowSelected.Checked) == dataset.showAllMaterials
        segmentationPanelHandles.materialsTableContextShowSelected.Checked = logical(1-dataset.showAllMaterials);
    end
    % update useLUT checkbox, see below selectionPanel
end

%% Update imView panel ---------------------------------------------
% ------------------------------------------------------------
if isempty(updatePanels) || ismember('imView', updatePanels)
    % update image view panel
    % add a label to the image view panel
    strVal1 = 'Image View    >>>>>    ';
    [~, fn, ext] = fileparts(dataset.image.filename);
    strVal1 = sprintf('%s%s%s', strVal1, fn, ext);
    if ~isempty(dataset.image.sliceName) && ...
            dataset.image.depth > 1 && dataset.orientation == 3   %'yx'
    
        % use getfield to get exact value as suggested by Ian M. Garcia in
        % http://stackoverflow.com/questions/3627107/how-can-i-index-a-matlab-array-returned-by-a-function-without-first-assigning-it
        layerName = getfield(dataset.image.sliceName, {min([currentSlice numel(dataset.image.sliceName)])});  %#ok<GFLD>
        obj.cImageDoc{selectedSet}.handles.imViewAxes.Title.String = sprintf('%s    >>>>>    %s', strVal1, layerName{1});
    else
        obj.cImageDoc{selectedSet}.handles.imViewAxes.Title.String = strVal1;
    end
end

%% Update activeDataset panel ---------------------------------------------
% ------------------------------------------------------------
% update tooltip for the buffer button
if isempty(updatePanels) || ismember('activeDataset', updatePanels)
    % get alias
    activeDataset = obj.view.handles.panels.activeDataset;

    % update buffer buttons in the Datasets panel
    bufferId = sprintf('buffer%d', obj.mibModel.Sets.selectedDataset(selectedSet));  % generate handle for the buffer button
    
    if strcmp(dataset.image.filename, 'none.tif')  % no dataset loaded
        activeDataset.handles.(bufferId).Tooltip = 'use RMB for a context menu with additional options';
    else
        activeDataset.handles.(bufferId).Tooltip = dataset.image.filename;
    end
    activeDataset.handles.(bufferId).BackgroundColor = [0 1 0];
    
    % add DeveloperMode tag
    if obj.mibModel.preferences.System.DeveloperMode
        activeDataset.handles.(bufferId).Tooltip = sprintf('obj.view.handles.panels.activeDataset.handles.%s:\n%s', ...
            bufferId, activeDataset.handles.(bufferId).Tooltip);
    end
end

%% Update dirContentsDataset panel ---------------------------------------------
% ------------------------------------------------------------
if isempty(updatePanels) || ismember('dirContentsDataset', updatePanels)
    % update directory contents panel
    % get alias
    dirContents = obj.view.handles.panels.dirContents;
    
    reader = 'Default';
    if obj.mibModel.useBioFormats; reader = 'BioFormats'; end
    
    % get list of extensions
    extentions = ['all known', obj.mibModel.extensionRegistryLoad.getAllowedExtensions(dataset.datasetType, reader)];
    dirContents.handles.fileFilters.Items = extentions;
    dirContents.handles.fileFilters.Value = obj.mibModel.selectedFileFilter{obj.mibModel.useBioFormats+1};
    obj.mibModel.selectedFileFilter{obj.mibModel.useBioFormats+1} = dirContents.handles.fileFilters.Value;

    if strcmp(newFileDir, obj.mibModel.currentDirectory)
        % Same directory — just highlight the matching file in the existing list
        fileListBox = dirContents.handles.fileList;
        if ~isempty(newFileBasename) && ismember(newFileBasename, fileListBox.Items)
            fileListBox.Value = newFileBasename;
            scroll(fileListBox, newFileBasename);
        end
    else
        % Directory changed — update currentDirectory and rebuild the file list
        obj.mibModel.currentDirectory = newFileDir;
        obj.cDirContents.updateFileList_Callback(newFileBasename);
    end

end

%% Update panelThresholding panel ---------------------------------------------
% ------------------------------------------------------------
% sliders in the black-and-white thresholding
if isempty(updatePanels) || ismember('panelThresholding', updatePanels)
    % get alias to the panel
    segmHandles = obj.cSegmentation.handles;
    maxInt = dataset.image.maxInt;

    if segmHandles.thresholdLow.Value > maxInt-1 || segmHandles.thresholdLowValue.Value > maxInt-1
        segmHandles.thresholdLow.Value = maxInt-1; 
        segmHandles.thresholdLowValue.Value = maxInt-1; 
    end
    segmHandles.thresholdLow.Limits = [0 maxInt-1];
    segmHandles.thresholdLowValue.Limits = [0 maxInt-1];
    segmHandles.thresholdLow.MajorTicks = 0:maxInt/4-1:maxInt;
    
    if segmHandles.thresholdHigh.Value > maxInt || segmHandles.thresholdHighValue.Value > maxInt
        segmHandles.thresholdHigh.Value = maxInt; 
        segmHandles.thresholdHighValue.Value = maxInt;
    end
    segmHandles.thresholdHigh.Limits = [1 maxInt];
    segmHandles.thresholdHighValue.Limits = [1 maxInt];
    segmHandles.thresholdHigh.MajorTicks = 0:maxInt/4-1:maxInt;
    
    % enable 4D thresholding checkbox
    if dataset.image.time > 1 && ~segmHandles.threshold4D.Enable
        segmHandles.threshold4D.Enable = true;
    elseif dataset.image.time==1 && (segmHandles.threshold4D.Enable || segmHandles.threshold4D.Value)
        segmHandles.threshold4D.Enable = false;
        segmHandles.threshold4D.Value = false;
    end
end

%% Update selectionPanel panel ---------------------------------------------
% ------------------------------------------------------------
if isempty(updatePanels) || ismember('selectionPanel', updatePanels)
    % update selection and view settings panel
    selectionPanelHandles = obj.view.handles.panels.selection.handles;

    selectionPanelHandles.lutColors.Value = dataset.useLUT;
    selectionPanelHandles.showMask.Value = obj.mibModel.showMask;
    selectionPanelHandles.showModel = obj.mibModel.showModel;
    
    % update LUT table and the linked colChannel dropdown
    obj.cSelection.lutTable_update_fromModel();
end

% update additional settings depending on the type of the loaded dataset
if dataset.datasetType(1) == 'V'  % virtual dataset
    obj.view.brushCursorShow = false;
else
    obj.view.brushCursorOffset = []; % reset offset to re-render cursor
    if ismember(obj.cSegmentation.handles.segmTool.Value, {'3D ball', 'Spot', 'Brush', })
        % show cursor
        obj.view.brushCursorShow = true;
        selectedSet = obj.mibModel.Sets.selectedSet;
        obj.cImageDoc{selectedSet}.updateBrushCursorOffset();
        obj.cImageDoc{selectedSet}.updateBrushCursor();
    else
        % hide cursor
        obj.view.brushCursorShow = false;
    end
end

%% Update status bar ---------------------------------------------
% ------------------------------------------------------------
if isempty(updatePanels) || ismember('statusBar', updatePanels)
    obj.cStatus.handles.currentDirectory.Value = newFileDir;
end

%% update mouse and key callbacks for MibImageDocuments --------------------------------------------
% --------------------------------------------------------------------------------------------------
for docId = 1:numel(obj.cImageDoc)
    cImageDoc = obj.cImageDoc{docId};
    UIFigure = cImageDoc.UIFigure;
    UIFigure.WindowButtonMotionFcn = @(~, ~)cImageDoc.gui_WinMouseMotionFcn();
    UIFigure.WindowScrollWheelFcn = @(~, eventdata)cImageDoc.gui_ScrollWheelFcn(eventdata);
    UIFigure.SizeChangedFcn = @(~, ~)cImageDoc.gui_SizeChangedFcn();
    UIFigure.WindowKeyPressFcn = @(hWidget, hData)cImageDoc.mibController.gui_WindowKeyPressFcn(hWidget, hData);
    UIFigure.WindowButtonDownFcn = @(~, ~)cImageDoc.gui_WindowButtonDownFcn();
end


%% update ROI stuff ---------------------------------------------
% ---------------------------------------------------------------
% update ROI list box
if isempty(updatePanels) || ismember('roi', updatePanels)
    roiListHandle = obj.cRoi.handles.roiList;
    [number, indices] = dataset.hROI.getNumberOfROI(0);
    items = cell(1, number + 1);
    items{1} = 'All';
    for i = 1:number
        lbl = dataset.hROI.Data(indices(i)).label;
        if iscell(lbl); lbl = lbl{1}; end
        items{i+1} = lbl;
    end
    roiListHandle.Items = items;
    
    if number > 0
        prevSelected = dataset.selectedROI + 1;
        if prevSelected <= numel(items)
            roiListHandle.ValueIndex = prevSelected;           
        else
            roiListHandle.ValueIndex = 1;
        end
        obj.cRoi.handles.roiShowROI.Value = dataset.roiShow;
    else
        roiListHandle.Value = 'All';
        dataset.roiShow = false;
        obj.cRoi.handles.roiShowROI.Value = false;
    end
end

%% Update the QuickAccessBar TAB ------------------------------------
% -------------------------------------------------------------------
if isempty(updatePanels) || ismember('QuickAccessBar', updatePanels)
    % update orientation buttons
    qabHandles = obj.cQuickAccessBar.handles;
    if dataset.orientation == 3 && ~qabHandles.yx_orientation.Value
        qabHandles.yx_orientation.Value = true;
        qabHandles.yz_orientation.Value = false;
        qabHandles.xz_orientation.Value = false;
    elseif dataset.orientation == 2 && ~qabHandles.yz_orientation.Value
        qabHandles.yx_orientation.Value = false;
        qabHandles.yz_orientation.Value = true;
        qabHandles.xz_orientation.Value = false;
    elseif dataset.orientation == 1 && ~qabHandles.xz_orientation.Value
        qabHandles.yx_orientation.Value = false;
        qabHandles.yz_orientation.Value = false;
        qabHandles.xz_orientation.Value = true;
    end

    % define ROI button state
    if qabHandles.roiMode.Value ~= dataset.roiShow
        qabHandles.roiMode.Value = dataset.roiShow;
    end

    % define the blockModeSwitch state
    if qabHandles.blockMode.Value ~= dataset.blockModeSwitch
        qabHandles.blockMode.Value = dataset.blockModeSwitch;
    end
end


% update callbacks, not needed here most likely
% obj.cImageDoc{selectedSet}.setupCallbacks();


%% TO DO 
%obj.mibView.updateCursor();  % update size of the cursor
%obj.mibModel.disableSegmentation = false;    % re-enable segmentation tools if they were accidentally turned off
%obj.toolbarVirtualMode_ClickedCallback('keepcurrent');         % update the virtual stack button

% clear trackerYXZ variable of the membrane clicktracker tool
for ii = 1:numel(obj.cImageDoc)
    if ~isempty(obj.cImageDoc{ii}) && isvalid(obj.cImageDoc{ii})
        obj.cImageDoc{ii}.trackerYXZ = [NaN; NaN; NaN];
    end
end
 
% %% place callbacks for gui
% obj.mibView.gui.WindowButtonMotionFcn = (@(hObject, eventdata, handles) obj.mibGUI_WinMouseMotionFcn());   
% obj.mibView.gui.WindowScrollWheelFcn = (@(hObject, eventdata, handles) obj.mibGUI_ScrollWheelFcn(eventdata));
% obj.mibView.gui.WindowKeyPressFcn = (@(hObject, eventdata, handles) obj.mibGUI_WindowKeyPressFcn(hObject, eventdata));
 

end
