function buildImageTab(obj, lazyInit)
% function buildImageTab(obj, lazyInit)
% build the Image tab group (obj.handles.toolbar.image)
% and add it to obj.handles.toolbar.global 
%
% Parameters:
% lazyInit: [@em optional default=false] logical, when true do only
% place maker initialization of the panel. The full rendering is upon the
% first call, using
% "controllers.MibController.globalTabGroup_SelectionCallback" function

arguments (Input)
    obj views.MibView
    lazyInit logical = false
end

%% Lazy initialization
if lazyInit
    % lazy initialization, the real initialization is in controllers.MibController.globalTabGroup_SelectionCallback
    % Make the tab
    obj.handles.toolbar.image = matlab.ui.internal.toolstrip.Tab("Image");
    obj.handles.toolbar.image.Tag = 'toolbarImage';
    % Add tab to the tab group
    obj.handles.toolbar.global.add(obj.handles.toolbar.image);
    return;
end

%% Init shorter variables and import classes
iconPath = fullfile(obj.controller.mibPath, 'assets', 'icons');
import matlab.ui.internal.toolstrip.Icon
import matlab.ui.internal.toolstrip.PopupList
import matlab.ui.internal.toolstrip.ListItem
import matlab.ui.internal.toolstrip.Button
import matlab.ui.internal.toolstrip.DropDownButton

%% ============= Make "Dataset tools" section =============
section = obj.handles.toolbar.image.addSection("Convert");
%% -------- MODE --------
column = section.addColumn();
obj.handles.image.mode =  DropDownButton('Mode', Icon(fullfile(iconPath, 'mode_24px.png')));
obj.handles.image.mode.Description = "Transform the dataset";

popupList = PopupList();
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
obj.handles.image.display = Button('Adjust display',  Icon(fullfile(iconPath, 'display_24px.png')));
obj.handles.image.display.Description = 'Adjust display/image';
obj.handles.image.display.ButtonPushedFcn = @(varargin)disp('Adjust display pressed');
column.add(obj.handles.image.display);

%% -------- COLOR CHANNELS --------
column = section.addColumn();
obj.handles.image.colors =  DropDownButton('Color channels', Icon(fullfile(iconPath, 'colors_24px.png')));
obj.handles.image.colors.Description = "Color channels";

popupList = PopupList();
% % Insert empty channel
obj.handles.image.colorsInsert =  ListItem('Insert empty channel...', Icon(fullfile(iconPath, 'colors_insert_24px.png')));
obj.handles.image.colorsInsert.ItemPushedFcn = @(varargin)disp('Insert empty channel pressed');
popupList.add(obj.handles.image.colorsInsert);
% % Copy channel
obj.handles.image.colorsCopy =  ListItem('Copy channel...', Icon(fullfile(iconPath, 'colors_copy_24px.png')));
obj.handles.image.colorsCopy.ItemPushedFcn = @(varargin)disp('Copy channel pressed');
popupList.add(obj.handles.image.colorsCopy);
% % Invert channel
obj.handles.image.colorsInvert =  ListItem('Invert channel...', Icon(fullfile(iconPath, 'colors_invert_24px.png')));
obj.handles.image.colorsInvert.ItemPushedFcn = @(varargin)disp('Invert channel pressed');
popupList.add(obj.handles.image.colorsInvert);
% % Rotate channel
obj.handles.image.colorsRotate =  ListItem('Rotate channel...', Icon(fullfile(iconPath, 'colors_rotate_24px.png')));
obj.handles.image.colorsRotate.ItemPushedFcn = @(varargin)disp('Rotate channel pressed');
popupList.add(obj.handles.image.colorsRotate);
% % Shift channel
obj.handles.image.colorsShift =  ListItem('Shift channel...', Icon(fullfile(iconPath, 'colors_shift_24px.png')));
obj.handles.image.colorsShift.ItemPushedFcn = @(varargin)disp('Shift channel pressed');
popupList.add(obj.handles.image.colorsShift);
% % Swap channel
obj.handles.image.colorsSwap =  ListItem('Swap channel...', Icon(fullfile(iconPath, 'colors_swap_24px.png')));
obj.handles.image.colorsSwap.ItemPushedFcn = @(varargin)disp('Swap channel pressed');
popupList.add(obj.handles.image.colorsSwap);
% % Delete channel
obj.handles.image.colorsDelete =  ListItem('Delete channel...', Icon(fullfile(iconPath, 'colors_delete_24px.png')));
obj.handles.image.colorsDelete.ItemPushedFcn = @(varargin)disp('Delete channel pressed');
popupList.add(obj.handles.image.colorsDelete);

% add the popup list to the Color channels button
obj.handles.image.colors.Popup = popupList;
column.add(obj.handles.image.colors);

%% -------- CONTRAST --------
column = section.addColumn();
obj.handles.image.contrast =  DropDownButton('Contrast', Icon(fullfile(iconPath, 'contrast_24px.png')));
obj.handles.image.contrast.Description = "Adjust contrast or normalize image intensities";

popupList = PopupList();
% % CLAHE
obj.handles.image.contrastCLAHE =  ListItem('Contrast-limited adaptive histogram equalization', Icon(fullfile(iconPath, 'contrast_clahe_24px.png')));
obj.handles.image.contrastCLAHE.ItemPushedFcn = @(varargin)disp('CLAHE pressed');
popupList.add(obj.handles.image.contrastCLAHE);
% % Normalize Z stack
obj.handles.image.contrastNormZ =  ListItem('Normalize layers', Icon(fullfile(iconPath, 'contrast_normZ_24px.png')));
obj.handles.image.contrastNormZ.ItemPushedFcn = @(varargin)disp('Normalize Z stack pressed');
popupList.add(obj.handles.image.contrastNormZ);
% % Normalize Z stack masked
obj.handles.image.contrastNormZmask =  ListItem('Normalize layers based on mask', Icon(fullfile(iconPath, 'contrast_normZmask_24px.png')));
obj.handles.image.contrastNormZmask.ItemPushedFcn = @(varargin)disp('Normalize layers based on mask pressed');
popupList.add(obj.handles.image.contrastNormZmask);
% % Normalize layers based on masked background
obj.handles.image.contrastNormZmaskBg =  ListItem('Normalize layers based on masked background', Icon(fullfile(iconPath, 'contrast_normZbg_24px.png')));
obj.handles.image.contrastNormZmaskBg.ItemPushedFcn = @(varargin)disp('Normalize layers based on masked background pressed');
popupList.add(obj.handles.image.contrastNormZmaskBg);
% % Normalize T stack
obj.handles.image.contrastNormT =  ListItem('Normalize time series', Icon(fullfile(iconPath, 'contrast_normT_24px.png')));
obj.handles.image.contrastNormT.ItemPushedFcn = @(varargin)disp('Normalize time series pressed');
popupList.add(obj.handles.image.contrastNormT);

% add the popup list to the Contrast button
obj.handles.image.contrast.Popup = popupList;
column.add(obj.handles.image.contrast);

%% -------- INVERT --------
column = section.addColumn();
obj.handles.image.invert = matlab.ui.internal.toolstrip.SplitButton('Invert',Icon(fullfile(iconPath, 'invert_24px.png')));
obj.handles.image.invert.ButtonPushedFcn  = @(varargin)disp('Invert image pressed');
obj.handles.image.invert.Description = "Invert image";

popupList = PopupList();
% % Invert image -> Shown slice (2D)
obj.handles.image.invert2D =  ListItem('Shown slice (2D)', Icon(fullfile(iconPath, 'dataset2d_24px.png')));
obj.handles.image.invert2D.ItemPushedFcn = @(varargin)disp('Shown slice (2D) pressed');
popupList.add(obj.handles.image.invert2D);
% % Invert image -> Current Stack (3D)
obj.handles.image.invert3D =  ListItem('Current stack (3D)', Icon(fullfile(iconPath, 'dataset3d_24px.png')));
obj.handles.image.invert3D.ItemPushedFcn = @(varargin)disp('Current stack (3D) pressed');
popupList.add(obj.handles.image.invert3D);
% % Invert image -> Complete volume (4D)
obj.handles.image.invert4D =  ListItem('Complete volume (4D)', Icon(fullfile(iconPath, 'dataset4d_24px.png')));
obj.handles.image.invert4D.ItemPushedFcn = @(varargin)disp('Complete volume (4D) pressed');
popupList.add(obj.handles.image.invert4D);


% add the popup list to the INVERT button
obj.handles.image.invert.Popup = popupList;
column.add(obj.handles.image.invert);

%% ============= Make "Dataset tools" section =============
section = obj.handles.toolbar.image.addSection("Image tools");

%% --------- IMAGE FILTERS ---------
column = section.addColumn();
obj.handles.image.filters = Button('Image filters',  Icon(fullfile(iconPath, 'image_filters_24px.png')));
obj.handles.image.filters.Description = 'Image filters';
obj.handles.image.filters.ButtonPushedFcn = @(varargin)disp('Image filters pressed');
column.add(obj.handles.image.filters);

%% -------- IMAGE TOOLS --------
column = section.addColumn();
obj.handles.image.tools =  DropDownButton('Image tools', Icon(fullfile(iconPath, 'image_tools_24px.png')));
obj.handles.image.tools.Description = "Tools for images";

popupList = PopupList();
% % Contrnt-aware fill
obj.handles.image.contentAware =  ListItem('Contrnt-aware fill', Icon(fullfile(iconPath, 'content_fill_24px.png')));
obj.handles.image.contentAware.ItemPushedFcn = @(varargin)disp('Content-aware fill pressed');
popupList.add(obj.handles.image.contentAware);
% % Debris removal
obj.handles.image.debrisRemoval =  ListItem('Debris removal', Icon(fullfile(iconPath, 'debris_removal_24px.png')));
obj.handles.image.debrisRemoval.ItemPushedFcn = @(varargin)disp('Debris removal pressed');
popupList.add(obj.handles.image.debrisRemoval);
% % Image arithmetics
obj.handles.image.imageMath =  ListItem('Image arithmetics', Icon(fullfile(iconPath, 'image_arithmetics_24px.png')));
obj.handles.image.imageMath.ItemPushedFcn = @(varargin)disp('Image arithmetics pressed');
popupList.add(obj.handles.image.imageMath);
% % Intensity projection
obj.handles.image.intProjection =  ListItem('Intensity projection', Icon(fullfile(iconPath, 'intensity_projection_24px.png')));
obj.handles.image.intProjection.ItemPushedFcn = @(varargin)disp('Intensity projection pressed');
popupList.add(obj.handles.image.intProjection);
% % Select image frame
obj.handles.image.imgFrame =  ListItem('Select image frame', Icon(fullfile(iconPath, 'image_frame_24px.png')));
obj.handles.image.imgFrame.ItemPushedFcn = @(varargin)disp('Select image frame pressed');
popupList.add(obj.handles.image.imgFrame);
% % White balance correction
obj.handles.image.whiteBalance =  ListItem('White balance correction', Icon(fullfile(iconPath, 'white_balance_24px.png')));
obj.handles.image.whiteBalance.ItemPushedFcn = @(varargin)disp('White balance correction pressed');
popupList.add(obj.handles.image.whiteBalance);

% add the popup list to the INVERT button
obj.handles.image.tools.Popup = popupList;
column.add(obj.handles.image.tools);

%% -------- Morphological operations --------
column = section.addColumn();
obj.handles.image.morphops =  DropDownButton('MorphOps', Icon(fullfile(iconPath, 'morph_ops_24px.png')));
obj.handles.image.morphops.Description = "Morphological operations";

popupList = PopupList();
% % Bottom-hat filtering
obj.handles.image.botHat =  ListItem('Bottom-hat filtering', Icon(fullfile(iconPath, 'botHat_24px.png')));
obj.handles.image.botHat.ItemPushedFcn = @(varargin)disp('Bottom-hat filtering pressed');
popupList.add(obj.handles.image.botHat);
% % Clear border
obj.handles.image.clearBorder =  ListItem('Clear border', Icon(fullfile(iconPath, 'clearBorder_24px.png')));
obj.handles.image.clearBorder.ItemPushedFcn = @(varargin)disp('Clear border pressed');
popupList.add(obj.handles.image.clearBorder);
% % Morphological closing
obj.handles.image.morphClose =  ListItem('Morphological closing', Icon(fullfile(iconPath, 'morphClose_24px.png')));
obj.handles.image.morphClose.ItemPushedFcn = @(varargin)disp('Morphological closing pressed');
popupList.add(obj.handles.image.morphClose);
% % Dilate image
obj.handles.image.dilate =  ListItem('Dilate image', Icon(fullfile(iconPath, 'dilate_24px.png')));
obj.handles.image.dilate.ItemPushedFcn = @(varargin)disp('Dilate image pressed');
popupList.add(obj.handles.image.dilate);
% % Erode image
obj.handles.image.erode =  ListItem('Erode image', Icon(fullfile(iconPath, 'erode_24px.png')));
obj.handles.image.erode.ItemPushedFcn = @(varargin)disp('Erode image pressed');
popupList.add(obj.handles.image.erode);
% % Fill regions
obj.handles.image.fill =  ListItem('Fill regions', Icon(fullfile(iconPath, 'fill_regions_24px.png')));
obj.handles.image.fill.ItemPushedFcn = @(varargin)disp('Fill regions pressed');
popupList.add(obj.handles.image.fill);
% % H-maxima transform
obj.handles.image.hMax =  ListItem('H-maxima transform', Icon(fullfile(iconPath, 'hMax_24px.png')));
obj.handles.image.hMax.ItemPushedFcn = @(varargin)disp('H-maxima transform pressed');
popupList.add(obj.handles.image.hMax);
% % H-minima transform
obj.handles.image.hMin =  ListItem('H-minima transform', Icon(fullfile(iconPath, 'hMin_24px.png')));
obj.handles.image.hMin.ItemPushedFcn = @(varargin)disp('H-minima transform pressed');
popupList.add(obj.handles.image.hMin);
% % Morphological opening
obj.handles.image.morphOpen =  ListItem('Morphological opening', Icon(fullfile(iconPath, 'morphOpen_24px.png')));
obj.handles.image.morphOpen.ItemPushedFcn = @(varargin)disp('Morphological opening pressed');
popupList.add(obj.handles.image.morphOpen);
% % Top-hat filtering
obj.handles.image.topHat =  ListItem('Top-hat filtering', Icon(fullfile(iconPath, 'topHat_24px.png')));
obj.handles.image.topHat.ItemPushedFcn = @(varargin)disp('Top-hat filtering pressed');
popupList.add(obj.handles.image.topHat);

% add the popup list to the button
obj.handles.image.morphops.Popup = popupList;
column.add(obj.handles.image.morphops);

%% -------- Intensity profile --------
column = section.addColumn();
obj.handles.image.profile =  DropDownButton('Intensity profile', Icon(fullfile(iconPath, 'intensity_profile_24px.png')));
obj.handles.image.profile.Description = "Intensity profile";

popupList = PopupList();
% % Line intensity profile
obj.handles.image.profileLine =  ListItem('Line intensity profile', Icon(fullfile(iconPath, 'profileLine_24px.png')));
obj.handles.image.profileLine.ItemPushedFcn = @(varargin)disp('Line intensity profile pressed');
popupList.add(obj.handles.image.profileLine);
% % Arbitrary intensity profile
obj.handles.image.profileArbitrary =  ListItem('Arbitrary intensity profile', Icon(fullfile(iconPath, 'profileArbitrary_24px.png')));
obj.handles.image.profileArbitrary.ItemPushedFcn = @(varargin)disp('Arbitrary intensity profile pressed');
popupList.add(obj.handles.image.profileArbitrary);

% add the popup list to the button
obj.handles.image.profile.Popup = popupList;
column.add(obj.handles.image.profile);

%%
%obj.handles.toolbar.global.add(obj.handles.toolbar.image);

end