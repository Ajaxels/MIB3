function image_Callbacks(obj, hWidget, hData)
% IMAGE_CALLBACKS - callback on press of buttons in the Image ribbon.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.image_Callbacks(hWidget, hData)
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
    fprintf('controllers.MibRibbon.image_Callbacks: Image ribbon-> %s\n', mode);
end

switch mode
    %% Mode section
    case {'Grayscale', 'Multi-channel', 'HSV color', 'Indexed', '8 bit', '16 bit', '32 bit'}
        BatchOpt.Target = {mode};
        obj.mibModel.changeImageMode(BatchOpt);
    %% Image adjustment section
    case sprintf('Adjust\ndisplay')               % obj.handles.ribbonImage.display
        obj.mibController.startController('controllers.DisplayAdjust');
    % % Color channels
    case 'Insert empty channel...'  % obj.handles.ribbonImage.colorsInsert
        obj.mibModel.colorChannelActions('Insert empty channel');
    case 'Copy channel...'          % obj.handles.ribbonImage.colorsCopy
        obj.mibModel.colorChannelActions('Copy channel');
    case 'Invert channel...'        % obj.handles.ribbonImage.colorsInvert
        obj.mibModel.colorChannelActions('Invert channel');
    case 'Rotate channel...'        % obj.handles.ribbonImage.colorsRotate
        obj.mibModel.colorChannelActions('Rotate channel');
    case 'Shift channel...'         % obj.handles.ribbonImage.colorsShift
        obj.mibModel.colorChannelActions('Shift channel');
    case 'Swap channel...'          % obj.handles.ribbonImage.colorsSwap
        obj.mibModel.colorChannelActions('Swap channels');
    case 'Delete channel...'        % obj.handles.ribbonImage.colorsDelete
        obj.mibModel.colorChannelActions('Delete channel');
    % %  Visualization
    case 'Visualization'        % obj.handles.ribbonImage.visualization
        obj.mibController.updateVisualizationMode();
    case 'Bicubic'              % obj.handles.ribbonImage.visBicubic
        obj.mibController.updateVisualizationMode('bicubic');
    case 'Nearest'              % obj.handles.ribbonImage.visNearest
        obj.mibController.updateVisualizationMode('nearest');
    case 'Automatic'            % obj.handles.ribbonImage.visAuto
        obj.mibController.updateVisualizationMode('auto');
    % % Contrast
    case 'Contrast-limited adaptive histogram equalization'     % obj.handles.ribbonImage.contrastCLAHE
        obj.mibController.startController('controllers.ContrastClahe');
    case 'Normalize layers'                                     % obj.handles.ribbonImage.contrastNorm
        obj.mibController.startController('controllers.ContrastNormalization');
    % % Invert
    case 'Shown slice (2D)'         % obj.handles.ribbonImage.invert2D
        obj.mibModel.invertImage('2D, Slice');
    case 'Current stack (3D)'       % obj.handles.ribbonImage.invert3D
        obj.mibModel.invertImage('3D, Stack');
    case {'Invert', 'Complete volume (4D)'}     % obj.handles.ribbonImage.invert4D
        obj.mibModel.invertImage('4D, Dataset');
    %% Image tools section
    case 'Image filters'                % obj.handles.ribbonImage.filters
        obj.mibController.startController('controllers.ImageFilters');
    % Image tools
    case 'Content-aware fill'                                   % obj.handles.ribbonImage.contentAware
        obj.mibController.startController('controllers.ContentAwareFill');
    case 'Debris removal'                % obj.handles.ribbonImage.debrisRemoval

    case 'Image arithmetics'       % obj.handles.ribbonImage.imageMath

    case 'Intensity projection'  % obj.handles.ribbonImage.intProjection

    case 'Select image frame'               % obj.handles.ribbonImage.imgFrame

    case 'White balance correction'          

    % Intensity profile
    case 'Line intensity profile'       % obj.handles.ribbonImage.profileLine

    case 'Arbitrary intensity profile'  % obj.handles.ribbonImage.profileArbitrary

end


end
