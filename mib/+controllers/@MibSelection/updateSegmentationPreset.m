function updateSegmentationPreset(obj, presetId)
% UPDATESEGMENTATIONPRESET - Update preset from the current settings of the selected segmentation.
%
% Syntax:
%   function updateSegmentationPreset(obj, presetId)
%
% tool; callback on Shift+click of preset1/2/3 buttons or Shift+1/2/3 keyboard shortcuts.
%
% Input Arguments:
%   - **presetId** — [numeric] preset index, 1 to 3
%
% Output Arguments:
%
% Usage:
%   Example 1::
%
%     obj.updateSegmentationPreset(1);  // store current settings to preset 1
%

% Updates
%

switch presetId
    case 1; setName = 'Set1';
    case 2; setName = 'Set2';
    case 3; setName = 'Set3';
end

% get alias to the segmentation panel handles
handles = obj.mibController.cSegmentation.handles;

% update segmentation settings depending on the selected tool
switch handles.segmTool.Value
    case 'Annotations'
        obj.mibModel.preferences.SegmTools.Presets.Annotations.(setName).ShowPrompt = logical(handles.annShowPrompt.Value);
        obj.mibModel.preferences.SegmTools.Presets.Annotations.(setName).FocusOnValue = logical(handles.annFocusOnValue.Value);
        obj.mibModel.preferences.SegmTools.Presets.Annotations.(setName).Size = obj.mibModel.preferences.SegmTools.Annotations.FontSize;
        obj.mibModel.preferences.SegmTools.Presets.Annotations.(setName).Color = obj.mibModel.preferences.SegmTools.Annotations.Color;
        obj.mibModel.preferences.SegmTools.Presets.Annotations.(setName).ExtraSlices = obj.mibModel.preferences.SegmTools.Annotations.ShownExtraDepth;
        obj.mibModel.preferences.SegmTools.Presets.Annotations.(setName).DisplayAs = handles.annDisplayAs.Value;
    case '3D lines'
        obj.mibModel.preferences.SegmTools.Presets.Lines3D.(setName).Click = handles.linesClick.Value;
        obj.mibModel.preferences.SegmTools.Presets.Lines3D.(setName).ShiftClick = handles.linesShiftClick.Value;
        obj.mibModel.preferences.SegmTools.Presets.Lines3D.(setName).CtrlClick = handles.linesCtrlClick.Value;
        obj.mibModel.preferences.SegmTools.Presets.Lines3D.(setName).AltClick = handles.linesAltClick.Value;
    case {'3D ball', 'Brush', 'Spot'}
        obj.mibModel.preferences.SegmTools.Presets.Brush.(setName).Radius = handles.brushRadius.Value;
        obj.mibModel.preferences.SegmTools.Presets.Brush.(setName).Eraser = handles.eraserFactor.Value;
        obj.mibModel.preferences.SegmTools.Presets.Brush.(setName).Watershed = strcmp(handles.brushUseClustering.SelectedObject.Text, 'Watershed');
        obj.mibModel.preferences.SegmTools.Presets.Brush.(setName).SLIC = strcmp(handles.brushUseClustering.SelectedObject.Text, 'SLIC');
    case 'BW thresholding'
        obj.mibModel.preferences.SegmTools.Presets.BWThresholding.(setName).Adaptive = logical(handles.thresholdAdaptive.Value);
        obj.mibModel.preferences.SegmTools.Presets.BWThresholding.(setName).BlackOnWhite = handles.thresholdType.Value;
        obj.mibModel.preferences.SegmTools.Presets.BWThresholding.(setName).Switch3D = logical(handles.threshold3D.Value);
        obj.mibModel.preferences.SegmTools.Presets.BWThresholding.(setName).Invert = logical(handles.thresholdInvert.Value);
        obj.mibModel.preferences.SegmTools.Presets.BWThresholding.(setName).ParameterLo = handles.thresholdLowValue.Value;
        obj.mibModel.preferences.SegmTools.Presets.BWThresholding.(setName).ParameterHi = handles.thresholdHighValue.Value;
        obj.mibModel.preferences.SegmTools.Presets.BWThresholding.(setName).SliderStep = obj.mibController.cSegmentation.thresholdSliderStep;
    case 'Drag&Drop materials'
        obj.mibModel.preferences.SegmTools.Presets.DragNDrop.(setName).Layer = handles.dragLayer.Value;
        obj.mibModel.preferences.SegmTools.Presets.DragNDrop.(setName).Shift = handles.dragValue.Value;
    case 'MagicWand/RegionGrowing'
        obj.mibModel.preferences.SegmTools.Presets.MagicWand.(setName).Method = handles.magicMethod.Value;
        obj.mibModel.preferences.SegmTools.Presets.MagicWand.(setName).VariationLo = handles.magicRange1.Value;
        obj.mibModel.preferences.SegmTools.Presets.MagicWand.(setName).VariationHi = handles.magicRange2.Value;
        obj.mibModel.preferences.SegmTools.Presets.MagicWand.(setName).Radius = handles.magicRadius.Value;
        if contains(handles.magicConnect.SelectedObject.Text, '8')
            obj.mibModel.preferences.SegmTools.Presets.MagicWand.(setName).Connect = 8;
        else
            obj.mibModel.preferences.SegmTools.Presets.MagicWand.(setName).Connect = 4;
        end
    case 'Membrane ClickTracker'
        obj.mibModel.preferences.SegmTools.Presets.MembraClickTracker.(setName).Scale = handles.membraneScale.Value;
        obj.mibModel.preferences.SegmTools.Presets.MembraClickTracker.(setName).Width = handles.membraneWidth.Value;
        obj.mibModel.preferences.SegmTools.Presets.MembraClickTracker.(setName).StraightLine = logical(handles.membraneStraightLine.Value);
        obj.mibModel.preferences.SegmTools.Presets.MembraClickTracker.(setName).BlackSignal = logical(handles.membraneBlackSignal.Value);
        obj.mibModel.preferences.SegmTools.Presets.MembraClickTracker.(setName).RecenterView = logical(handles.membraneRecenterView.Value);
    case 'Object picker'
        obj.mibModel.preferences.SegmTools.Presets.ObjectPicker.(setName).lassoType = handles.lassoType.Value;
        obj.mibModel.preferences.SegmTools.Presets.ObjectPicker.(setName).lassoMode = handles.lassoMode.Value;
    case 'Segment-anything model'
        obj.mibModel.preferences.SegmTools.Presets.SAM.(setName).Method = handles.samMethod.Value;
        obj.mibModel.preferences.SegmTools.Presets.SAM.(setName).Dataset = handles.samDataset.Value;
        obj.mibModel.preferences.SegmTools.Presets.SAM.(setName).Destination = handles.samDestination.Value;
        obj.mibModel.preferences.SegmTools.Presets.SAM.(setName).Mode = handles.samMode.Value;
end

end
