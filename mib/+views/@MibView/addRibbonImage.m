function widgetHandles = addRibbonImage(obj, lazyInit)
% function widgetHandles = addRibbonImage(obj, lazyInit)
% build the Image tab group (obj.handles.ribbon.image)
% and add it to obj.handles.ribbon.global 
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
    obj.handles.ribbon.image = matlab.ui.internal.toolstrip.Tab("Image");
    obj.handles.ribbon.image.Tag = 'toolbarImage';
    % Add tab to the tab group
    obj.handles.ribbon.global.add(obj.handles.ribbon.image);
    widgetHandles = [];
    return;
end

%% Init shorter variables and import classes
iconPath = fullfile(obj.controller.mibPath, 'assets', 'icons');
import matlab.ui.internal.toolstrip.Icon
import matlab.ui.internal.toolstrip.PopupList
import matlab.ui.internal.toolstrip.ListItem
import matlab.ui.internal.toolstrip.Button
import matlab.ui.internal.toolstrip.DropDownButton
import matlab.ui.internal.toolstrip.PopupListHeader
import matlab.ui.internal.toolstrip.ListItemWithCheckBox

%% ============= Make "Dataset tools" section =============
section = obj.handles.ribbon.image.addSection("Convert");
%% -------- MODE --------
column = section.addColumn();
widgetHandles.mode =  DropDownButton('Mode', Icon(fullfile(iconPath, 'mode_24px.png')));
widgetHandles.mode.Description = "Transform the dataset";

popupList = PopupList();
header1 = PopupListHeader('Image mode change');
popupList.add(header1);
% % Mode -> grayscale
widgetHandles.grayscale =  ListItemWithCheckBox('Grayscale', true);
popupList.add(widgetHandles.grayscale);
% % Mode -> multichannel
widgetHandles.multichannel =  ListItemWithCheckBox('Multi-channel', false);
popupList.add(widgetHandles.multichannel);
% % Mode -> HSV color
widgetHandles.hsv =  ListItemWithCheckBox('HSV color', false);
popupList.add(widgetHandles.hsv);
% % Mode -> Indexed
widgetHandles.indexed =  ListItemWithCheckBox('Indexed', false);
popupList.add(widgetHandles.indexed);

% % SEPARATOR
separator = matlab.ui.internal.toolstrip.PopupListSeparator();
popupList.add(separator);

% % Mode -> 8bit
widgetHandles.bit8 =  ListItemWithCheckBox('8 bit', true);
popupList.add(widgetHandles.bit8);
% % Mode -> 16bit
widgetHandles.bit16 =  ListItemWithCheckBox('16 bit', false);
popupList.add(widgetHandles.bit16);
% % Mode -> 32bit
widgetHandles.bit32 =  ListItemWithCheckBox('32 bit', false);
popupList.add(widgetHandles.bit32);

% add the popup list to the Mode button
widgetHandles.mode.Popup = popupList;
column.add(widgetHandles.mode);

%% ============= Make "Dataset tools" section =============
section = obj.handles.ribbon.image.addSection("Image adjustments");
%% --------- ADJUST DISPLAY ---------
column = section.addColumn();
widgetHandles.display = Button('Adjust display',  Icon(fullfile(iconPath, 'display_24px.png')));
widgetHandles.display.Description = 'Adjust display/image';
column.add(widgetHandles.display);

%% -------- COLOR CHANNELS --------
column = section.addColumn();
widgetHandles.colors =  DropDownButton('Color channels', Icon(fullfile(iconPath, 'colors_24px.png')));
widgetHandles.colors.Description = "Color channels";

popupList = PopupList();
header1 = PopupListHeader('Operations with color channels');
popupList.add(header1);

% % Insert empty channel
widgetHandles.colorsInsert =  ListItem('Insert empty channel...', Icon(fullfile(iconPath, 'colors_insert_24px.png')));
popupList.add(widgetHandles.colorsInsert);
% % Copy channel
widgetHandles.colorsCopy =  ListItem('Copy channel...', Icon(fullfile(iconPath, 'colors_copy_24px.png')));
popupList.add(widgetHandles.colorsCopy);
% % Invert channel
widgetHandles.colorsInvert =  ListItem('Invert channel...', Icon(fullfile(iconPath, 'colors_invert_24px.png')));
popupList.add(widgetHandles.colorsInvert);
% % Rotate channel
widgetHandles.colorsRotate =  ListItem('Rotate channel...', Icon(fullfile(iconPath, 'colors_rotate_24px.png')));
popupList.add(widgetHandles.colorsRotate);
% % Shift channel
widgetHandles.colorsShift =  ListItem('Shift channel...', Icon(fullfile(iconPath, 'colors_shift_24px.png')));
popupList.add(widgetHandles.colorsShift);
% % Swap channel
widgetHandles.colorsSwap =  ListItem('Swap channel...', Icon(fullfile(iconPath, 'colors_swap_24px.png')));
popupList.add(widgetHandles.colorsSwap);
% % Delete channel
widgetHandles.colorsDelete =  ListItem('Delete channel...', Icon(fullfile(iconPath, 'colors_delete_24px.png')));
popupList.add(widgetHandles.colorsDelete);

% add the popup list to the Color channels button
widgetHandles.colors.Popup = popupList;
column.add(widgetHandles.colors);

%% -------- CONTRAST --------
column = section.addColumn();
widgetHandles.contrast =  DropDownButton('Contrast', Icon(fullfile(iconPath, 'contrast_24px.png')));
widgetHandles.contrast.Description = "Adjust contrast or normalize image intensities";

popupList = PopupList();
header1 = PopupListHeader('Adjust or normalize contrast');
popupList.add(header1);

% % CLAHE
widgetHandles.contrastCLAHE =  ListItem('Contrast-limited adaptive histogram equalization', Icon(fullfile(iconPath, 'contrast_clahe_24px.png')));
popupList.add(widgetHandles.contrastCLAHE);
% % Normalize Z stack
widgetHandles.contrastNormZ =  ListItem('Normalize layers', Icon(fullfile(iconPath, 'contrast_normZ_24px.png')));
popupList.add(widgetHandles.contrastNormZ);
% % Normalize Z stack masked
widgetHandles.contrastNormZmask =  ListItem('Normalize layers based on mask', Icon(fullfile(iconPath, 'contrast_normZmask_24px.png')));
popupList.add(widgetHandles.contrastNormZmask);
% % Normalize layers based on masked background
widgetHandles.contrastNormZmaskBg =  ListItem('Normalize layers based on masked background', Icon(fullfile(iconPath, 'contrast_normZbg_24px.png')));
popupList.add(widgetHandles.contrastNormZmaskBg);
% % Normalize T stack
widgetHandles.contrastNormT =  ListItem('Normalize time series', Icon(fullfile(iconPath, 'contrast_normT_24px.png')));
popupList.add(widgetHandles.contrastNormT);

% add the popup list to the Contrast button
widgetHandles.contrast.Popup = popupList;
column.add(widgetHandles.contrast);

%% -------- INVERT --------
column = section.addColumn();
widgetHandles.invert = matlab.ui.internal.toolstrip.SplitButton('Invert', Icon(fullfile(iconPath, 'invert_24px.png')));
widgetHandles.invert.Description = "Invert image";

popupList = PopupList();
header1 = PopupListHeader('Invert image intersity');
popupList.add(header1);

% % Invert image -> Shown slice (2D)
widgetHandles.invert2D =  ListItem('Shown slice (2D)', Icon(fullfile(iconPath, 'dataset2d_24px.png')));
popupList.add(widgetHandles.invert2D);
% % Invert image -> Current Stack (3D)
widgetHandles.invert3D =  ListItem('Current stack (3D)', Icon(fullfile(iconPath, 'dataset3d_24px.png')));
popupList.add(widgetHandles.invert3D);
% % Invert image -> Complete volume (4D)
widgetHandles.invert4D =  ListItem('Complete volume (4D)', Icon(fullfile(iconPath, 'dataset4d_24px.png')));
popupList.add(widgetHandles.invert4D);


% add the popup list to the INVERT button
widgetHandles.invert.Popup = popupList;
column.add(widgetHandles.invert);

%% --------- IMAGE RESAMPLE ---------
column = section.addColumn();
widgetHandles.visualization = matlab.ui.internal.toolstrip.SplitButton('Visualization',  ...
    Icon(fullfile(iconPath, sprintf('image_%s_24px.png', obj.mibModel.preferences.System.ImageResizeMethod))));
widgetHandles.visualization.Description = 'Type of image interpolation for the visualization';

popupList = PopupList();
header1 = PopupListHeader('Image interpolation for visualization');
popupList.add(header1);

% Bicubic interpolation
widgetHandles.visBicubic =  ListItem('Bicubic', Icon(fullfile(iconPath, 'image_bicubic_24px.png')));
widgetHandles.visBicubic.Description = 'Bicubic interpolation to resize images for visualization (best for zooming out)';
popupList.add(widgetHandles.visBicubic);
% Nearest interpolation
widgetHandles.visNearest =  ListItem('Nearest', Icon(fullfile(iconPath, 'image_nearest_24px.png')));
widgetHandles.visNearest.Description = 'Nearest interpolation to resize images for visualization (best for zooming in)';
popupList.add(widgetHandles.visNearest);
% Automatic interpolation
widgetHandles.visAuto =  ListItem('Automatic', Icon(fullfile(iconPath, 'image_auto_24px.png')));
widgetHandles.visAuto.Description = 'Nearest for zooming-in and bicubic for zooming-out';
popupList.add(widgetHandles.visAuto);

% add the popup list to the visualization button
widgetHandles.visualization.Popup = popupList;
column.add(widgetHandles.visualization);

%% ============= Make "Dataset tools" section =============
section = obj.handles.ribbon.image.addSection("Image tools");

%% --------- IMAGE FILTERS ---------
column = section.addColumn();
widgetHandles.filters = Button('Image filters',  Icon(fullfile(iconPath, 'image_filters_24px.png')));
widgetHandles.filters.Description = 'Image filters';
column.add(widgetHandles.filters);

%% -------- IMAGE TOOLS --------
column = section.addColumn();
widgetHandles.tools =  DropDownButton('Image tools', Icon(fullfile(iconPath, 'image_tools_24px.png')));
widgetHandles.tools.Description = "Tools for images";

popupList = PopupList();
header1 = PopupListHeader('Collection of image tools');
popupList.add(header1);
% % Contrnt-aware fill
widgetHandles.contentAware =  ListItem('Content-aware fill', Icon(fullfile(iconPath, 'content_fill_24px.png')));
popupList.add(widgetHandles.contentAware);
% % Debris removal
widgetHandles.debrisRemoval =  ListItem('Debris removal', Icon(fullfile(iconPath, 'debris_removal_24px.png')));
popupList.add(widgetHandles.debrisRemoval);
% % Image arithmetics
widgetHandles.imageMath =  ListItem('Image arithmetics', Icon(fullfile(iconPath, 'image_arithmetics_24px.png')));
popupList.add(widgetHandles.imageMath);
% % Intensity projection
widgetHandles.intProjection =  ListItem('Intensity projection', Icon(fullfile(iconPath, 'intensity_projection_24px.png')));
popupList.add(widgetHandles.intProjection);
% % Select image frame
widgetHandles.imgFrame =  ListItem('Select image frame', Icon(fullfile(iconPath, 'image_frame_24px.png')));
popupList.add(widgetHandles.imgFrame);
% % White balance correction
widgetHandles.whiteBalance =  ListItem('White balance correction', Icon(fullfile(iconPath, 'white_balance_24px.png')));
popupList.add(widgetHandles.whiteBalance);

% add the popup list to the INVERT button
widgetHandles.tools.Popup = popupList;
column.add(widgetHandles.tools);

%% -------- Morphological operations --------
column = section.addColumn();
widgetHandles.morphops =  DropDownButton('MorphOps', Icon(fullfile(iconPath, 'morph_ops_24px.png')));
widgetHandles.morphops.Description = "Morphological operations";

popupList = PopupList();
header1 = PopupListHeader('Morphological operations');
popupList.add(header1);

% % Bottom-hat filtering
widgetHandles.botHat =  ListItem('Bottom-hat filtering', Icon(fullfile(iconPath, 'botHat_24px.png')));
popupList.add(widgetHandles.botHat);
% % Clear border
widgetHandles.clearBorder =  ListItem('Clear border', Icon(fullfile(iconPath, 'clearBorder_24px.png')));
popupList.add(widgetHandles.clearBorder);
% % Morphological closing
widgetHandles.morphClose =  ListItem('Morphological closing', Icon(fullfile(iconPath, 'morphClose_24px.png')));
popupList.add(widgetHandles.morphClose);
% % Dilate image
widgetHandles.dilate =  ListItem('Dilate image', Icon(fullfile(iconPath, 'dilate_24px.png')));
popupList.add(widgetHandles.dilate);
% % Erode image
widgetHandles.erode =  ListItem('Erode image', Icon(fullfile(iconPath, 'erode_24px.png')));
popupList.add(widgetHandles.erode);
% % Fill regions
widgetHandles.fill =  ListItem('Fill regions', Icon(fullfile(iconPath, 'fill_regions_24px.png')));
popupList.add(widgetHandles.fill);
% % H-maxima transform
widgetHandles.hMax =  ListItem('H-maxima transform', Icon(fullfile(iconPath, 'hMax_24px.png')));
popupList.add(widgetHandles.hMax);
% % H-minima transform
widgetHandles.hMin =  ListItem('H-minima transform', Icon(fullfile(iconPath, 'hMin_24px.png')));
popupList.add(widgetHandles.hMin);
% % Morphological opening
widgetHandles.morphOpen =  ListItem('Morphological opening', Icon(fullfile(iconPath, 'morphOpen_24px.png')));
popupList.add(widgetHandles.morphOpen);
% % Top-hat filtering
widgetHandles.topHat =  ListItem('Top-hat filtering', Icon(fullfile(iconPath, 'topHat_24px.png')));
popupList.add(widgetHandles.topHat);

% add the popup list to the button
widgetHandles.morphops.Popup = popupList;
column.add(widgetHandles.morphops);

%% -------- Intensity profile --------
column = section.addColumn();
widgetHandles.profile =  DropDownButton('Intensity profile', Icon(fullfile(iconPath, 'intensity_profile_24px.png')));
widgetHandles.profile.Description = "Intensity profile";

popupList = PopupList();
header1 = PopupListHeader('Measure length');
popupList.add(header1);

% % Line intensity profile
widgetHandles.profileLine =  ListItem('Line intensity profile', Icon(fullfile(iconPath, 'profileLine_24px.png')));
popupList.add(widgetHandles.profileLine);
% % Arbitrary intensity profile
widgetHandles.profileArbitrary =  ListItem('Arbitrary intensity profile', Icon(fullfile(iconPath, 'profileArbitrary_24px.png')));
popupList.add(widgetHandles.profileArbitrary);

% add the popup list to the button
widgetHandles.profile.Popup = popupList;
column.add(widgetHandles.profile);

%%
obj.handles.ribbonImage = widgetHandles;

end