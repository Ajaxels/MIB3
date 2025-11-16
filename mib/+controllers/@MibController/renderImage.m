function renderImage(obj, resize)
% renderImage(obj, resize)
% Render (show) the current image in the Image View panel,
% MIB2 function plotImage
%
% Parameters:
% resize: [@em optional]
% - when @b 0 [@em default] keep the current vieweing settings 
% - when @b 1 resize image to fit the screen
%
% Return values:
% 

%| 
% @b Examples:
% @code 
% // standard call to redraw image in the image view panel
% notify(obj.mibModel, 'RenderImage');
% @endcode
% @code 
% // custom call to resize and redraw image in the image view panel
% Options.resize = true;
% eventdata = core.ToggleEventData(Options);
% notify(obj, 'RenderImage', eventdata);
% @endcode
% @code 
% // direct call from controllers.MibController class
% obj.renderImage();
% @endcode

I = obj.mibModel.I{obj.mibModel.id}.getData();
image(I, 'parent', obj.view.handles.imView{obj.mibModel.Sets.selectedSet}.handles.imViewAxes);
end