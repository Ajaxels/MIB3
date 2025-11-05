function plotImage(obj)
% plotImage(obj)
% Plot (show) the current image in the Image View panel

I = obj.mibModel.I{obj.mibModel.id}.getData();
image(I, 'parent', obj.view.handles.imView{obj.mibModel.Sets.selectedSet}.handles.imViewAxes);
end