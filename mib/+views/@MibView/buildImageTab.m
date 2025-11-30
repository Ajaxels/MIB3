function buildImageTab(obj)
% function buildImageTab(obj)
% build the Image tab group (obj.handles.toolbar.image)
% and add it to obj.handles.toolbar.global 

arguments (Input)
    obj views.MibView
end

obj.handles.toolbar.image = matlab.ui.internal.toolstrip.Tab("Image");

%% ============= Make "Dataset tools" section =============
section = obj.handles.toolbar.image.addSection("Convert");
%% -------- MODE --------
column = section.addColumn();
obj.handles.image.mode =  matlab.ui.internal.toolstrip.DropDownButton('Mode', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'mode_24px')));
obj.handles.image.mode.Description = "Transform the dataset";

popupList = matlab.ui.internal.toolstrip.PopupList();
% % Mode -> grayscale
obj.handles.image.grayscale =  matlab.ui.internal.toolstrip.ListItemWithCheckBox('Grayscale', true);
obj.handles.image.grayscale.ValueChangedFcn = @(varargin)disp('Grayscale pressed');
popupList.add(obj.handles.image.grayscale);
% % Mode -> multicolor
obj.handles.image.multicolor =  matlab.ui.internal.toolstrip.ListItemWithCheckBox('Multicolor', false);
obj.handles.image.multicolor.ValueChangedFcn = @(varargin)disp('Multicolor pressed');
popupList.add(obj.handles.image.multicolor);
% % Mode -> HSV color
obj.handles.image.hsv =  matlab.ui.internal.toolstrip.ListItemWithCheckBox('HSV color', false);
obj.handles.image.hsv.ValueChangedFcn = @(varargin)disp('HSV color pressed');
popupList.add(obj.handles.image.hsv);
% % Mode -> Indexed
obj.handles.image.indexed =  matlab.ui.internal.toolstrip.ListItemWithCheckBox('Indexed', false);
obj.handles.image.indexed.ValueChangedFcn = @(varargin)disp('Indexed pressed');
popupList.add(obj.handles.image.indexed);

% % SEPARATOR
separator = matlab.ui.internal.toolstrip.PopupListSeparator();
popupList.add(separator);

% % Mode -> 8bit
obj.handles.image.bit8 =  matlab.ui.internal.toolstrip.ListItemWithCheckBox('8 bit', true);
obj.handles.image.bit8.ValueChangedFcn = @(varargin)disp('8 bit pressed');
popupList.add(obj.handles.image.bit8);
% % Mode -> 16bit
obj.handles.image.bit16 =  matlab.ui.internal.toolstrip.ListItemWithCheckBox('16 bit', false);
obj.handles.image.bit16.ValueChangedFcn = @(varargin)disp('16 bit pressed');
popupList.add(obj.handles.image.bit16);
% % Mode -> 32bit
obj.handles.image.bit32 =  matlab.ui.internal.toolstrip.ListItemWithCheckBox('32 bit', false);
obj.handles.image.bit32.ValueChangedFcn = @(varargin)disp('32 bit pressed');
popupList.add(obj.handles.image.bit32);

% add the popup list to the Mode button
obj.handles.image.mode.Popup = popupList;
column.add(obj.handles.image.mode);

%% ============= Make "Dataset tools" section =============
section = obj.handles.toolbar.image.addSection("Image adjustments");
%% --------- ADJUST DISPLAY ---------
column = section.addColumn();
obj.handles.image.display = matlab.ui.internal.toolstrip.Button('Adjust display',  matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'display_24px')));
obj.handles.image.display.Description = 'Adjust display/image';
obj.handles.image.display.ButtonPushedFcn = @(varargin)disp('Adjust display pressed');
column.add(obj.handles.image.display);

%% -------- COLOR CHANNELS --------
column = section.addColumn();
obj.handles.image.colors =  matlab.ui.internal.toolstrip.DropDownButton('Color channels', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'colors_24px')));
obj.handles.image.colors.Description = "Color channels";

popupList = matlab.ui.internal.toolstrip.PopupList();
% % Insert empty channel
obj.handles.image.colorsInsert =  matlab.ui.internal.toolstrip.ListItem('Insert empty channel...', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'colors_insert_24px')));
obj.handles.image.colorsInsert.ItemPushedFcn = @(varargin)disp('Insert empty channel pressed');
popupList.add(obj.handles.image.colorsInsert);
% % Copy channel
obj.handles.image.colorsCopy =  matlab.ui.internal.toolstrip.ListItem('Copy channel...', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'colors_copy_24px')));
obj.handles.image.colorsCopy.ItemPushedFcn = @(varargin)disp('Copy channel pressed');
popupList.add(obj.handles.image.colorsCopy);
% % Invert channel
obj.handles.image.colorsInvert =  matlab.ui.internal.toolstrip.ListItem('Invert channel...', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'colors_invert_24px')));
obj.handles.image.colorsInvert.ItemPushedFcn = @(varargin)disp('Invert channel pressed');
popupList.add(obj.handles.image.colorsInvert);
% % Rotate channel
obj.handles.image.colorsRotate =  matlab.ui.internal.toolstrip.ListItem('Rotate channel...', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'colors_invert_24px')));
obj.handles.image.colorsRotate.ItemPushedFcn = @(varargin)disp('Rotate channel pressed');
popupList.add(obj.handles.image.colorsRotate);
% % Shift channel
obj.handles.image.colorsShift =  matlab.ui.internal.toolstrip.ListItem('Shift channel...', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'colors_shift_24px')));
obj.handles.image.colorsShift.ItemPushedFcn = @(varargin)disp('Shift channel pressed');
popupList.add(obj.handles.image.colorsShift);
% % Swap channel
obj.handles.image.colorsSwap =  matlab.ui.internal.toolstrip.ListItem('Swap channel...', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'colors_swap_24px')));
obj.handles.image.colorsSwap.ItemPushedFcn = @(varargin)disp('Swap channel pressed');
popupList.add(obj.handles.image.colorsSwap);
% % Delete channel
obj.handles.image.colorsDelete =  matlab.ui.internal.toolstrip.ListItem('Delete channel...', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'colors_delete_24px')));
obj.handles.image.colorsDelete.ItemPushedFcn = @(varargin)disp('Delete channel pressed');
popupList.add(obj.handles.image.colorsDelete);

% add the popup list to the Color channels button
obj.handles.image.colors.Popup = popupList;
column.add(obj.handles.image.colors);

%% -------- CONTRAST --------
column = section.addColumn();
obj.handles.image.contrast =  matlab.ui.internal.toolstrip.DropDownButton('Contrast', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'contrast_24px')));
obj.handles.image.contrast.Description = "Adjust contrast or normalize image intensities";

popupList = matlab.ui.internal.toolstrip.PopupList();
% % CLAHE
obj.handles.image.contrastCLAHE =  matlab.ui.internal.toolstrip.ListItem('Contrast-limited adaptive histogram equalization', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'contrast_clahe_24px')));
obj.handles.image.contrastCLAHE.ItemPushedFcn = @(varargin)disp('CLAHE pressed');
popupList.add(obj.handles.image.contrastCLAHE);
% % Normalize Z stack
obj.handles.image.contrastNormZ =  matlab.ui.internal.toolstrip.ListItem('Normalize layers', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'contrast_normZ_24px')));
obj.handles.image.contrastNormZ.ItemPushedFcn = @(varargin)disp('Normalize Z stack pressed');
popupList.add(obj.handles.image.contrastNormZ);
% % Normalize Z stack masked
obj.handles.image.contrastNormZmask =  matlab.ui.internal.toolstrip.ListItem('Normalize layers based on mask', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'contrast_normZmask_24px')));
obj.handles.image.contrastNormZmask.ItemPushedFcn = @(varargin)disp('Normalize layers based on mask pressed');
popupList.add(obj.handles.image.contrastNormZmask);
% % Normalize layers based on masked background
obj.handles.image.contrastNormZmaskBg =  matlab.ui.internal.toolstrip.ListItem('Normalize layers based on masked background', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'contrast_normZbg_24px')));
obj.handles.image.contrastNormZmaskBg.ItemPushedFcn = @(varargin)disp('Normalize layers based on masked background pressed');
popupList.add(obj.handles.image.contrastNormZmaskBg);
% % Normalize T stack
obj.handles.image.contrastNormT =  matlab.ui.internal.toolstrip.ListItem('Normalize time series', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'contrast_normT_24px')));
obj.handles.image.contrastNormT.ItemPushedFcn = @(varargin)disp('Normalize time series pressed');
popupList.add(obj.handles.image.contrastNormT);

% add the popup list to the Contrast button
obj.handles.image.contrast.Popup = popupList;
column.add(obj.handles.image.contrast);

%% -------- INVERT --------
column = section.addColumn();
obj.handles.image.invert = matlab.ui.internal.toolstrip.SplitButton('Invert',matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'invert_24px')));
obj.handles.image.invert.ButtonPushedFcn  = @(varargin)disp('Invert image pressed');
obj.handles.image.invert.Description = "Invert image";

popupList = matlab.ui.internal.toolstrip.PopupList();
% % Invert image -> Shown slice (2D)
obj.handles.image.invert2D =  matlab.ui.internal.toolstrip.ListItem('Shown slice (2D)', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'dataset2d_24px')));
obj.handles.image.invert2D.ItemPushedFcn = @(varargin)disp('Shown slice (2D) pressed');
popupList.add(obj.handles.image.invert2D);
% % Invert image -> Current Stack (3D)
obj.handles.image.invert3D =  matlab.ui.internal.toolstrip.ListItem('Current stack (3D)', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'dataset3d_24px')));
obj.handles.image.invert3D.ItemPushedFcn = @(varargin)disp('Current stack (3D) pressed');
popupList.add(obj.handles.image.invert3D);
% % Invert image -> Complete volume (4D)
obj.handles.image.invert4D =  matlab.ui.internal.toolstrip.ListItem('Complete volume (4D)', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'dataset4d_24px')));
obj.handles.image.invert4D.ItemPushedFcn = @(varargin)disp('Complete volume (4D) pressed');
popupList.add(obj.handles.image.invert4D);


% add the popup list to the INVERT button
obj.handles.image.invert.Popup = popupList;
column.add(obj.handles.image.invert);

%% ============= Make "Dataset tools" section =============
section = obj.handles.toolbar.image.addSection("Image tools");

%% --------- IMAGE FILTERS ---------
column = section.addColumn();
obj.handles.image.filters = matlab.ui.internal.toolstrip.Button('Image filters',  matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'image_filters_24px')));
obj.handles.image.filters.Description = 'Image filters';
obj.handles.image.filters.ButtonPushedFcn = @(varargin)disp('Image filters pressed');
column.add(obj.handles.image.filters);

%% -------- IMAGE TOOLS --------
column = section.addColumn();
obj.handles.image.tools =  matlab.ui.internal.toolstrip.DropDownButton('Image tools', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'image_tools_24px')));
obj.handles.image.tools.Description = "Tools for images";

popupList = matlab.ui.internal.toolstrip.PopupList();
% % Contrnt-aware fill
obj.handles.image.contentAware =  matlab.ui.internal.toolstrip.ListItem('Contrnt-aware fill', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'content_fill_24px')));
obj.handles.image.contentAware.ItemPushedFcn = @(varargin)disp('Content-aware fill pressed');
popupList.add(obj.handles.image.contentAware);
% % Debris removal
obj.handles.image.debrisRemoval =  matlab.ui.internal.toolstrip.ListItem('Debris removal', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'debris_removal_24px')));
obj.handles.image.debrisRemoval.ItemPushedFcn = @(varargin)disp('Debris removal pressed');
popupList.add(obj.handles.image.debrisRemoval);
% % Image arithmetics
obj.handles.image.imageMath =  matlab.ui.internal.toolstrip.ListItem('Image arithmetics', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'image_arithmetics_24px')));
obj.handles.image.imageMath.ItemPushedFcn = @(varargin)disp('Image arithmetics pressed');
popupList.add(obj.handles.image.imageMath);
% % Intensity projection
obj.handles.image.intProjection =  matlab.ui.internal.toolstrip.ListItem('Intensity projection', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'intensity_projection_24px')));
obj.handles.image.intProjection.ItemPushedFcn = @(varargin)disp('Intensity projection pressed');
popupList.add(obj.handles.image.intProjection);
% % Select image frame
obj.handles.image.imgFrame =  matlab.ui.internal.toolstrip.ListItem('Select image frame', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'image_frame_24px')));
obj.handles.image.imgFrame.ItemPushedFcn = @(varargin)disp('Select image frame pressed');
popupList.add(obj.handles.image.imgFrame);
% % White balance correction
obj.handles.image.whiteBalance =  matlab.ui.internal.toolstrip.ListItem('White balance correction', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'white_balance_24px')));
obj.handles.image.whiteBalance.ItemPushedFcn = @(varargin)disp('White balance correction pressed');
popupList.add(obj.handles.image.whiteBalance);

% add the popup list to the INVERT button
obj.handles.image.tools.Popup = popupList;
column.add(obj.handles.image.tools);

%% -------- Morphological operations --------
column = section.addColumn();
obj.handles.image.morphops =  matlab.ui.internal.toolstrip.DropDownButton('MorphOps', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'morph_ops_24px')));
obj.handles.image.morphops.Description = "Morphological operations";

popupList = matlab.ui.internal.toolstrip.PopupList();
% % Bottom-hat filtering
obj.handles.image.botHat =  matlab.ui.internal.toolstrip.ListItem('Bottom-hat filtering', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'botHat_24px')));
obj.handles.image.botHat.ItemPushedFcn = @(varargin)disp('Bottom-hat filtering pressed');
popupList.add(obj.handles.image.botHat);
% % Clear border
obj.handles.image.clearBorder =  matlab.ui.internal.toolstrip.ListItem('Clear border', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'clearBorder_24px')));
obj.handles.image.clearBorder.ItemPushedFcn = @(varargin)disp('Clear border pressed');
popupList.add(obj.handles.image.clearBorder);
% % Morphological closing
obj.handles.image.morphClose =  matlab.ui.internal.toolstrip.ListItem('Morphological closing', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'morphClose_24px')));
obj.handles.image.morphClose.ItemPushedFcn = @(varargin)disp('Morphological closing pressed');
popupList.add(obj.handles.image.morphClose);
% % Dilate image
obj.handles.image.dilate =  matlab.ui.internal.toolstrip.ListItem('Dilate image', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'dilate_24px')));
obj.handles.image.dilate.ItemPushedFcn = @(varargin)disp('Dilate image pressed');
popupList.add(obj.handles.image.dilate);
% % Erode image
obj.handles.image.erode =  matlab.ui.internal.toolstrip.ListItem('Erode image', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'erode_24px')));
obj.handles.image.erode.ItemPushedFcn = @(varargin)disp('Erode image pressed');
popupList.add(obj.handles.image.erode);
% % Fill regions
obj.handles.image.fill =  matlab.ui.internal.toolstrip.ListItem('Fill regions', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'fill_regions_24px')));
obj.handles.image.fill.ItemPushedFcn = @(varargin)disp('Fill regions pressed');
popupList.add(obj.handles.image.fill);
% % H-maxima transform
obj.handles.image.hMax =  matlab.ui.internal.toolstrip.ListItem('H-maxima transform', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'hMax_24px')));
obj.handles.image.hMax.ItemPushedFcn = @(varargin)disp('H-maxima transform pressed');
popupList.add(obj.handles.image.hMax);
% % H-minima transform
obj.handles.image.hMin =  matlab.ui.internal.toolstrip.ListItem('H-minima transform', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'hMin_24px')));
obj.handles.image.hMin.ItemPushedFcn = @(varargin)disp('H-minima transform pressed');
popupList.add(obj.handles.image.hMin);
% % Morphological opening
obj.handles.image.morphOpen =  matlab.ui.internal.toolstrip.ListItem('Morphological opening', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'morphOpen_24px')));
obj.handles.image.morphOpen.ItemPushedFcn = @(varargin)disp('Morphological opening pressed');
popupList.add(obj.handles.image.morphOpen);
% % Top-hat filtering
obj.handles.image.topHat =  matlab.ui.internal.toolstrip.ListItem('Top-hat filtering', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'topHat_24px')));
obj.handles.image.topHat.ItemPushedFcn = @(varargin)disp('Top-hat filtering pressed');
popupList.add(obj.handles.image.topHat);

% add the popup list to the button
obj.handles.image.morphops.Popup = popupList;
column.add(obj.handles.image.morphops);

%% -------- Intensity profile --------
column = section.addColumn();
obj.handles.image.profile =  matlab.ui.internal.toolstrip.DropDownButton('Intensity profile', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'intensity_profile_24px')));
obj.handles.image.profile.Description = "Intensity profile";

popupList = matlab.ui.internal.toolstrip.PopupList();
% % Line intensity profile
obj.handles.image.profileLine =  matlab.ui.internal.toolstrip.ListItem('Line intensity profile', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'profileLine_24px')));
obj.handles.image.profileLine.ItemPushedFcn = @(varargin)disp('Line intensity profile pressed');
popupList.add(obj.handles.image.profileLine);
% % Arbitrary intensity profile
obj.handles.image.profileArbitrary =  matlab.ui.internal.toolstrip.ListItem('Arbitrary intensity profile', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'profileArbitrary_24px')));
obj.handles.image.profileArbitrary.ItemPushedFcn = @(varargin)disp('Arbitrary intensity profile pressed');
popupList.add(obj.handles.image.profileArbitrary);

% add the popup list to the button
obj.handles.image.profile.Popup = popupList;
column.add(obj.handles.image.profile);

%%
obj.handles.toolbar.global.add(obj.handles.toolbar.image);

end