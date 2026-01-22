function updateGuiWidgets(obj, updatePanels)
% function updateGuiWidgets(obj, updatePanel)
% Update user interface widgets in obj.mibView.gui based on the properties of the opened dataset

% define cell array of panels to update, when empty update all panels
if nargin < 2; updatePanels = {}; end

% create a handle for the dataset
dataset = obj.mibModel.I{obj.mibModel.id};

%% ------------ Update the IMAGE TAB ------------
if isempty(updatePanels) || ismember(updatePanels, 'ribbonImage')
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

%% ------------ Update the MODEL TAB ------------
if isempty(updatePanels) || ismember(updatePanels, 'ribbonModel')
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
    if dataset.labels.maxMaterials < 256 && segmHandles.colorWheel.Visible
        % update the buttons in the panel to match the model type with less than 256 materials

        % update the add material button
        segmHandles.addMaterial.Icon = core.MibIconCache.get('alpha_cache', 'plus_16px');
        segmHandles.addMaterial.Tooltip = 'Add a new material to the model';
        if obj.mibModel.preferences.System.DeveloperMode
            segmHandles.addMaterial.Tooltip = sprintf('obj.cSegmentation.view.handles.addMaterial:\n%s', segmHandles.addMaterial.Tooltip);
        end
        % update the remove material button
        segmHandles.removeMaterial = core.MibIconCache.get('alpha_cache', 'minus_16px');
        segmHandles.removeMaterial.Tooltip = 'Remove selected material from the model';
        if obj.mibModel.preferences.System.DeveloperMode
            segmHandles.addMaterial.Tooltip = sprintf('obj.cSegmentation.view.handles.removeMaterial:\n%s', segmHandles.removeMaterial.Tooltip);
        end
        % hide color wheel button
        segmHandles.colorWheel.Visible = false;
    elseif dataset.labels.maxMaterials > 256 && ~segmHandles.colorWheel.Visible
        % update the buttons in the panel to match the model type with more than 256 materials
        
        % update the add material button -> to next material
        segmHandles.addMaterial.Icon = core.MibIconCache.get('alpha_cache', 'next_16px');
        segmHandles.addMaterial.Tooltip = 'Find and select the next empty material';
        if obj.mibModel.preferences.System.DeveloperMode
            segmHandles.addMaterial.Tooltip = sprintf('obj.cSegmentation.view.handles.addMaterial:\n%s', segmHandles.addMaterial.Tooltip);
        end
        % update the remove material button -> squeeze the labels
        segmHandles.removeMaterial = core.MibIconCache.get('alpha_cache', 'shrink_16px');
        segmHandles.removeMaterial.Tooltip = 'Squeeze the labels to remove all empty indices and select next available index';
        if obj.mibModel.preferences.System.DeveloperMode
            segmHandles.addMaterial.Tooltip = sprintf('obj.cSegmentation.view.handles.removeMaterial:\n%s', segmHandles.removeMaterial.Tooltip);
        end

        % show color wheel button
        segmHandles.colorWheel.Visible = true;
    end
end

%% ------------ Update the QuickAccessBar TAB ------------
if isempty(updatePanels) || ismember(updatePanels, 'QuickAccessBar')
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
    elseif dataset.orientation == 1 && ~oqabHandles.xz_orientation.Value
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

%% Update sliders


%% Update panels
% sliders in the black-and-white thresholding
if isempty(updatePanels) || ismember(updatePanels, 'panelThresholding')
    % get alias to the panel
    segmHandles = obj.cSegmentation.handles;
    maxInt = dataset.image.maxInt;
    
    if segmHandles.thresholdLow.Value > maxInt-1 || segmHandles.thresholdLowValue.Value > maxInt-1
        segmHandles.thresholdLow.Value = maxInt-1; 
        segmHandles.thresholdLowValue.Value = maxInt-1; 
    end
    segmHandles.thresholdLow.Limits = [0 maxInt-1];
    segmHandles.thresholdLowValue.Limits = [0 maxInt-1];
    
    if segmHandles.thresholdHigh.Value > maxInt || segmHandles.thresholdHighValue.Value > maxInt
        segmHandles.thresholdHigh.Value = maxInt; 
        segmHandles.thresholdHighValue.Value = maxInt;
    end
    segmHandles.thresholdHigh.Limits = [1 maxInt];
    segmHandles.thresholdHighValue.Limits = [1 maxInt];
    
    % enable 4D thresholding checkbox
    if dataset.image.time > 1 && ~segmHandles.threshold4D.Enable
        segmHandles.threshold4D.Enable = true;
    elseif dataset.image.time==1 && (segmHandles.threshold4D.Enable || segmHandles.threshold4D.Value)
        segmHandles.threshold4D.Enable = false;
        segmHandles.threshold4D.Value = false;
    end
end





%% TO DO
%obj.mibView.updateCursor();  % update size of the cursor
%obj.mibModel.disableSegmentation = 0;    % re-enable segmentation tools if they were accidentally turned off
%obj.updateInterpolationMode(true);      % update the selection interpolation button
%obj.updateVisualizationMode('keepcurrent');     % update the image interpolation button icon
%obj.toolbarVirtualMode_ClickedCallback('keepcurrent');         % update the virtual stack button


end