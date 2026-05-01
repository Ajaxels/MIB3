function imageMorphOps_Callbacks(obj, hWidget, hData)
% IMAGEMORPHOPS_CALLBACKS - callback on press of morph-ops buttons in the Image ribbon.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.imageMorphOps_Callbacks(hWidget, hData)
%
% Input Arguments:
%   - **hWidget** — handle to the pressed widget
%   - **hData** — handle to supporting EventData class
%

arguments (Input)
    obj controllers.MibRibbon
    hWidget matlab.ui.internal.toolstrip.base.Action
    hData matlab.ui.internal.toolstrip.base.ToolstripEventData
end

mode = hWidget.Text;
if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibRibbon.imageMorphOps_Callbacks: Image ribbon->morph-ops -> %s\n', mode);
end

switch mode
    case 'Bottom-hat filtering'               % obj.handles.ribbonImage.botHat
    case 'Clear border'                % obj.handles.ribbonImage.clearBorder
    case 'Morphological closing'       % obj.handles.ribbonImage.morphClose
    case 'Dilate image'  % obj.handles.ribbonImage.dilate
    case 'Erode image'               % obj.handles.ribbonImage.erode
    case 'Fill regions'                % obj.handles.ribbonImage.fill
    case 'H-maxima transform'       % obj.handles.ribbonImage.hMax
    case 'H-minima transform'  % obj.handles.ribbonImage.hMin
    case 'Morphological opening'               % obj.handles.ribbonImage.morphOpen
    case 'Top-hat filtering'                % obj.handles.ribbonImage.topHat
end

end
