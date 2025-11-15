function initialize(obj)
% function initialize(obj)
% init MibDataset class and set all elements of the class to default values

% ---------- main layers ----------
obj.annotations = core.Annotations; % handle to class for keeping annotations
obj.lines3D = core.Lines3D; % handle to class for keeping 3D Lines and skeletons
obj.measure = []; % handle to class to keep measurements
obj.hROI = []; % handle to ROI class, @b mibRoiRegion

% ---------- other properties ----------

obj.axesX = NaN; % a vector [min, max] with minimal and maximal coordinates of
% the axes X of the 'obj.view.handles.imView{setId}.handles.imViewAxes' axes; use @code obj.mibModel.getAxesLimits() @endcode to read this property

obj.axesY = NaN; % a vector [min, max] with minimal and maximal coordinates of
% the axes Y of the 'obj.view.handles.imView{setId}.handles.imViewAxes' axes; use @code obj.mibModel.getAxesLimits() @endcode to read this property

obj.blockModeSwitch =  false;
% a variable to hold a status of the block mode (obj.handles.qab.blockMode), true - enabled, false - disabled

obj.current_yxz = [1 1 1]; % a vector to remember last selected slice number of each 'yx', 'zx', 'zy' planes,
% @note dimensions: @code [1 1 1] @endcode

obj.enableSelection = true;
% a switch (0/1) to enable or not the selection, mask, model layers

obj.lastSegmSelection = [2 1];
% a vector with 2 elements of two previously selected materials for use with the 'e' key shortcut

obj.magFactor = 1; % magnification factor for the datasets, 1=100%, 1.5 = 150%; use @code mibModel.getMagFactor() @endcode to read this property

obj.maskExist = false;
% a switch to indicate presence of the 'Mask' layer. Can be 0 (no mask) or 1 (mask exist)

obj.maskStats = []; % Statistics for the 'Mask' layer with the 'PixelList' info returned by 'regionprops' Matlab function

obj.modelExist = false; % a switch to indicate presence of the 'Model' layer. Can be 0 (no model) or 1 (model exist)

obj.orientation = 3; % Orientation of the currently shown dataset,
% @li @b 3 = the 'yz' plane, @b default
% @li @b 1 = the 'zx' plane
% @li @b 2 = the 'zy' plane

obj.restrictSelectionToMask = false;
% a switch indicating the value of the obj.view.handles.panels.segmentation.handles.restrictMask

obj.restrictSelectionToMaterial = false;
% a switch indicating the value of the obj.view.handles.panels.segmentation.handles.restrictMaterial

obj.selectedAddToMaterial = 1;
% index of selected Add to Material, where the Selection layer
% should be targeted, assigned in the AddTo column of the obj.view.handles.panels.segmentation.handles.materialsTable
% @b 1 - Mask; @b 2 - Exterior; @b 3 - first material of the model, @b 4 - second material etc

obj.selectedColorChannel = 1;
% color channel selected in the Color channel dropdown (obj.view.handles.panels.selection.handles.colChannel) of the
% Selection panel. 0 - all colors, 1, 2 - 1st, 2nd ...

obj.selectedMaterial = 1; % index of material selected in the obj.view.handles.panels.segmentation.handles.materialsTable: @b 1 - Mask; @b 2 - Exterior; @b 3 - first material of the model, @b 4 - second material etc

obj.selectedROI = -1; % a vector of indices (as stored in mibRoiRegion class) of the
% selected ROI in the mibView.handles.mibRoiList table; -1 -> roi is not shown; [1, 3] -> first and third...
% allocate slices
% coordinates of the shown part of the dataset
% @note dimensions are @code ([height, width, color, depth, time],[min max]) @endcode
% @li (1,[min max]) - height
% @li (2,[min max]) - width
% @li (3,[min max]) - z - value
% @li (4,[min max]) - colors , array of color channels to show, for example [1, 3, 4]
% @li (5,[min max]) - t - time point
obj.slices{1} = [1, 1];
obj.slices{2} = [1, 1];
obj.slices{3} = [1, 1];
obj.slices{4} = 1:obj.img.colors;
obj.slices{5} = [1 1];

obj.useLUT = false;
% use or not LUT for visualization of image, a number @b false - do not use; @b true - use a status of obj.view.handles.panels.selection.handles.lutColors

end