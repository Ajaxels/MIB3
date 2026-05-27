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
    case {'Bottom-hat filtering','Clear border','Morphological closing','Dilate image', ...
          'Erode image','Fill regions','H-maxima transform','H-minima transform', ...
          'Morphological opening','Top-hat filtering'}
        obj.mibController.startController('controllers.MorphOpsImages', mode);
end

end
