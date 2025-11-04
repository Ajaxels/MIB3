function buildPluginsTab(obj)
% function buildPluginsTab(obj)
% build the Plugins tab group (obj.handles.toolbar.plugins)
% and add it to obj.handles.toolbar.global 
arguments (Input)
    obj views.MibView
end

obj.handles.toolbar.plugins = matlab.ui.internal.toolstrip.Tab("Plugins");
obj.handles.toolbar.plugins.Tag = 'toolbarPlugins';

obj.handles.toolbar.global.add(obj.handles.toolbar.plugins);

end