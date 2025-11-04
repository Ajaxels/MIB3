function plotImage(obj)
% plotImage(obj)
% Plot (show) the current image in the Image View panel

I = obj.mibModel.I{obj.mibModel.id}.getData();
image(I, 'parent', obj.view.handles.sets{1}.handles.imViewAxes);
end