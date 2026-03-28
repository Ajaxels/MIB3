function gui_WindowDragAndDropMotionFcn(obj, brushSelection)
% function gui_WindowDragAndDropMotionFcn(obj, brushSelection)
% Visual feedback during drag-and-drop: brightens displaced pixels
%
% Parameters:
% brushSelection: uint8 matrix, image of the selected layer area
%
% Return values:
%   (none)

% Updates
%

pos = obj.handles.imViewAxes.CurrentPoint;
XLim = size(obj.mibModel.Ishown, 2);
YLim = size(obj.mibModel.Ishown, 1);
pos = round(pos);

if pos(1,1) <= 0; pos(1,1) = 1; end
if pos(1,1) > XLim; pos(1,1) = XLim; end
if pos(1,2) <= 0; pos(1,2) = 1; end
if pos(1,2) > YLim; pos(1,2) = YLim; end

if isnan(obj.brushPrevXY(1,1))
    obj.brushPrevXY = [pos(1,1) pos(1,2)];
    return;
end

% calculate shift for the selection layer
diffX = pos(1,1) - obj.brushPrevXY(1);
diffY = pos(1,2) - obj.brushPrevXY(2);

selAreaOut = zeros(size(brushSelection), 'uint8');
w2 = XLim - abs(diffX);
h2 = YLim - abs(diffY);
if diffY > 0 && diffX > 0
    selAreaOut(diffY+1:end, diffX+1:end) = brushSelection(1:h2, 1:w2);
elseif diffY > 0 && diffX <= 0
    selAreaOut(diffY+1:end, 1:w2) = brushSelection(1:h2, abs(diffX)+1:end);
elseif diffY <= 0 && diffX > 0
    selAreaOut(1:h2, diffX+1:end) = brushSelection(abs(diffY)+1:end, 1:w2);
elseif diffY <= 0 && diffX <= 0
    selAreaOut(1:h2, 1:w2) = brushSelection(abs(diffY)+1:end, abs(diffX)+1:end);
end
img = obj.mibModel.Ishown;
img(selAreaOut == 1) = img(selAreaOut == 1) + intmax(class(obj.mibModel.Ishown)) * .4;

obj.imageHandle.CData = img;
end
