function updateSettingsFromPreset(obj, presetId)
% function updateSettingsFromPreset(obj, presetId)
% Update settings of the selected segmentation tool from a stored preset;
% callback on click of preset1/2/3 buttons or 1/2/3 keyboard shortcuts.
%
% Parameters:
% presetId: [numeric] preset index, 1 to 3
%
% Return values:
%

%|
% @b Examples:
% @code obj.updateSettingsFromPreset(1);  // restore preset 1 settings @endcode

% Updates
%

switch presetId
    case 1; setName = 'Set1';
    case 2; setName = 'Set2';
    case 3; setName = 'Set3';
end

% get alias to the segmentation panel handles and controller
cSeg = obj.mibController.cSegmentation;
handles = cSeg.handles;

% restore segmentation settings depending on the selected tool
switch handles.segmTool.Value
    case 'Annotations'
        Annotations = obj.mibModel.preferences.SegmTools.Presets.Annotations;
        handles.annShowPrompt.Value = Annotations.(setName).ShowPrompt;
        handles.annFocusOnValue.Value = Annotations.(setName).FocusOnValue;
        obj.mibModel.preferences.SegmTools.Annotations.FontSize = Annotations.(setName).Size;
        obj.mibModel.preferences.SegmTools.Annotations.Color = Annotations.(setName).Color;
        obj.mibModel.preferences.SegmTools.Annotations.ShownExtraDepth = Annotations.(setName).ExtraSlices;
        handles.annDisplayAs.Value = Annotations.(setName).DisplayAs;
        notify(obj.mibModel, 'ShowImage');
    case '3D lines'
        Lines3D = obj.mibModel.preferences.SegmTools.Presets.Lines3D;
        handles.linesClick.Value = Lines3D.(setName).Click;
        handles.linesShiftClick.Value = Lines3D.(setName).ShiftClick;
        handles.linesCtrlClick.Value = Lines3D.(setName).CtrlClick;
        handles.linesAltClick.Value = Lines3D.(setName).AltClick;
    case {'3D ball', 'Brush', 'Spot'}
        Brush = obj.mibModel.preferences.SegmTools.Presets.Brush;
        % restore brush radius (may be stored as string in legacy preferences)
        radius = Brush.(setName).Radius;
        if ischar(radius); radius = str2double(radius); end
        handles.brushRadius.Value = radius;
        % restore eraser factor (may be stored as string in legacy preferences)
        eraser = Brush.(setName).Eraser;
        if ischar(eraser); eraser = str2double(eraser); end
        handles.eraserFactor.Value = eraser;
        % restore clustering mode from Watershed/SLIC boolean flags
        if Brush.(setName).Watershed
            targetCluster = 'Watershed';
        elseif Brush.(setName).SLIC
            targetCluster = 'SLIC';
        else
            targetCluster = 'No clusters';
        end
        bg = handles.brushUseClustering;
        for btn = bg.Children'
            if isa(btn, 'matlab.ui.control.RadioButton') && strcmp(btn.Text, targetCluster)
                bg.SelectedObject = btn;
                break;
            end
        end
        % update the clustering parameters panel and brush cursor
        cSeg.brushPanel_Callback([], [], 'brushUseClustering');
        selectedSet = obj.mibModel.Sets.selectedSet;
        obj.mibController.cImageDoc{selectedSet}.updateBrushCursorOffset();
        obj.mibController.cImageDoc{selectedSet}.updateBrushCursor();
    case 'BW thresholding'
        BWThresholding = obj.mibModel.preferences.SegmTools.Presets.BWThresholding;
        handles.thresholdAdaptive.Value = logical(BWThresholding.(setName).Adaptive);
        if handles.thresholdAdaptive.Value
            handles.thresholdType.Enable = 'on';
            handles.thresholdInvert.Enable = 'on';
        else
            handles.thresholdType.Enable = 'off';
            handles.thresholdInvert.Enable = 'off';
        end
        handles.thresholdType.Value = BWThresholding.(setName).BlackOnWhite;
        handles.threshold3D.Value = logical(BWThresholding.(setName).Switch3D);
        handles.thresholdInvert.Value = logical(BWThresholding.(setName).Invert);
        % restore low threshold value and sync slider
        paramLo = BWThresholding.(setName).ParameterLo;
        if ischar(paramLo); paramLo = str2double(paramLo); end
        paramLo = max(handles.thresholdLow.Limits(1), min(handles.thresholdLow.Limits(2), paramLo));
        handles.thresholdLowValue.Value = paramLo;
        handles.thresholdLow.Value = paramLo;
        % restore high threshold value and sync slider
        paramHi = BWThresholding.(setName).ParameterHi;
        if ischar(paramHi); paramHi = str2double(paramHi); end
        paramHi = max(handles.thresholdHigh.Limits(1), min(handles.thresholdHigh.Limits(2), paramHi));
        handles.thresholdHighValue.Value = paramHi;
        handles.thresholdHigh.Value = paramHi;
        % restore slider step
        cSeg.thresholdSliderStep = BWThresholding.(setName).SliderStep;
    case 'Drag&Drop materials'
        DragNDrop = obj.mibModel.preferences.SegmTools.Presets.DragNDrop;
        handles.dragLayer.Value = DragNDrop.(setName).Layer;
        shift = DragNDrop.(setName).Shift;
        if ischar(shift); shift = str2double(shift); end
        handles.dragValue.Value = shift;
    case 'MagicWand/RegionGrowing'
        MagicWand = obj.mibModel.preferences.SegmTools.Presets.MagicWand;
        handles.magicMethod.Value = MagicWand.(setName).Method;
        % update Range2 enable state based on method
        if strcmp(handles.magicMethod.Value, 'Magic Wand')
            handles.magicRange2.Enable = true;
        else
            handles.magicRange2.Enable = false;
        end
        varLo = MagicWand.(setName).VariationLo;
        if ischar(varLo); varLo = str2double(varLo); end
        handles.magicRange1.Value = varLo;
        varHi = MagicWand.(setName).VariationHi;
        if ischar(varHi); varHi = str2double(varHi); end
        handles.magicRange2.Value = varHi;
        radius = MagicWand.(setName).Radius;
        if ischar(radius); radius = str2double(radius); end
        handles.magicRadius.Value = radius;
        % restore connectivity via ButtonGroup child search
        connectVal = MagicWand.(setName).Connect;
        bg = handles.magicConnect;
        for btn = bg.Children'
            if isa(btn, 'matlab.ui.control.RadioButton') && contains(btn.Text, num2str(connectVal))
                bg.SelectedObject = btn;
                break;
            end
        end
    case 'Membrane ClickTracker'
        MembraClickTracker = obj.mibModel.preferences.SegmTools.Presets.MembraClickTracker;
        scale = MembraClickTracker.(setName).Scale;
        if ischar(scale); scale = str2double(scale); end
        handles.membraneScale.Value = scale;
        width = MembraClickTracker.(setName).Width;
        if ischar(width); width = str2double(width); end
        handles.membraneWidth.Value = width;
        handles.membraneStraightLine.Value = logical(MembraClickTracker.(setName).StraightLine);
        handles.membraneBlackSignal.Value = logical(MembraClickTracker.(setName).BlackSignal);
        handles.membraneRecenterView.Value = logical(MembraClickTracker.(setName).RecenterView);
    case 'Object picker'
        ObjectPicker = obj.mibModel.preferences.SegmTools.Presets.ObjectPicker;
        handles.lassoType.Value = ObjectPicker.(setName).lassoType;
        handles.lassoMode.Value = ObjectPicker.(setName).lassoMode;
    case 'Segment-anything model'
        SAM = obj.mibModel.preferences.SegmTools.Presets.SAM;
        handles.samMethod.Value =SAM.(setName).Method;
        handles.samDataset.Value =SAM.(setName).Dataset;
        handles.samDestination.Value =SAM.(setName).Destination;
        handles.samMode.Value =SAM.(setName).Mode;
        % update samSegment enable state based on selected method
        switch handles.samMethod.Value
            case {'Automatic everything', 'Landmarks'}
                handles.samSegment.Enable = 'on';
            case {'Interactive', 'Interactive 3D'}
                handles.samSegment.Enable = 'off';
        end
end

end
