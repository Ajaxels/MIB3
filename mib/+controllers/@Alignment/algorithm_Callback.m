function algorithm_Callback(obj)
% ALGORITHM_CALLBACK - Toggle widget enable/disable based on the selected algorithm.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.algorithm_Callback()
%
% Reads ``obj.view.handles.Algorithm.Value``, then enables only the widgets
% relevant to that algorithm. ``HDD_Mode`` is enabled only for drift / template
% / feature-based; AMST disables ``Subarea`` and forces ``cropped`` mode; the
% feature-based variants restrict ``TransformationType`` to a method-specific
% subset.

h = obj.view.handles;
methodSelected = h.Algorithm.Value;

% Default: turn off all situational widgets
optionalTags = {'ColorChannel','IntensityGradient','TransformationType', ...
    'TransformationMode','CorrelateWith','TransformationDegree', ...
    'FeatureDetectorType','previewFeaturesBtn','MedianSize', ...
    'UseParallelComputing'};
for k = 1:numel(optionalTags)
    if isfield(h, optionalTags{k})
        h.(optionalTags{k}).Enable = 'off';
    end
end
h.Subarea.Enable = 'on';

hddModeValue = h.HDD_Mode.Value;
h.HDD_Mode.Enable = 'off';
h.HDD_Mode.Value = false;

helpText = '';
switch methodSelected
    case 'Drift correction'
        helpText = 'Use Drift correction for small shifts between comparably sized images.';
        enableWidgets(h, {'ColorChannel','IntensityGradient','CorrelateWith','HDD_Mode'});
        h.HDD_Mode.Value = hddModeValue;

    case 'Template matching'
        helpText = 'Use Template matching when one stack is smaller than the other.';
        enableWidgets(h, {'ColorChannel','IntensityGradient','CorrelateWith'});

    case {'Automatic feature-based', 'Automatic feature-based v2'}
        helpText = 'Use automatic feature detection to align slices.';
        enableWidgets(h, {'TransformationType','TransformationMode','FeatureDetectorType', ...
            'previewFeaturesBtn','ColorChannel','HDD_Mode','UseParallelComputing'});
        h.HDD_Mode.Value = hddModeValue;

        if strcmp(methodSelected, 'Automatic feature-based')
            allowed = {'similarity', 'affine', 'projective'};
        else
            allowed = {'translation', 'rigid', 'similarity', 'affine'};
        end
        h.TransformationType.Items = allowed;
        h.TransformationType.Value = allowed{1};
        obj.BatchOpt.TransformationType{2} = allowed;
        obj.BatchOpt.TransformationType{1} = allowed{1};

    case 'AMST: median-smoothed template'
        helpText = sprintf(['Align dataset to a Z-median-smoothed version of itself, compensating ' ...
            'for local deformations.\nThe dataset must be pre-aligned with Drift correction.']);
        enableWidgets(h, {'TransformationType','previewFeaturesBtn','ColorChannel', 'MedianSize','UseParallelComputing'});

        allowed = {'similarity', 'affine', 'projective'};
        h.TransformationType.Items = allowed;
        h.TransformationType.Value = 'affine';
        obj.BatchOpt.TransformationType{2} = allowed;
        obj.BatchOpt.TransformationType{1} = 'affine';

        h.TransformationMode.Value = 'cropped';
        obj.BatchOpt.TransformationMode{1} = 'cropped';
        h.Subarea.Enable = 'off';

    case 'Single landmark point'
        helpText = sprintf(['Use the Brush or Annotation tool to mark two corresponding spots on ' ...
            'consecutive slices.\nThe dataset is translated to align the marked spots.']);
        % BigData honours extended/cropped; the in-memory path always extends, so
        % only expose the choice for BigData. Default to extended either way.
        if obj.isBigData; enableWidgets(h, {'TransformationMode'}); end
        h.TransformationMode.Value = 'extended';
        obj.BatchOpt.TransformationMode{1} = 'extended';

    case 'Three landmark points'
        helpText = sprintf(['Use the Brush tool to mark three corresponding spots on consecutive ' ...
            'slices. The dataset is transformed to align the marked spots. ' ...
            '\n\nThe Landmark mode is recommended instead.']);
        if obj.isBigData; enableWidgets(h, {'TransformationMode'}); end
        h.TransformationMode.Value = 'extended';
        obj.BatchOpt.TransformationMode{1} = 'extended';

    case 'Landmarks, multi points'
        helpText = sprintf(['Use annotation name to mark corresponding points or selection-with-brush to mark corresponding spots on ' ...
            'consecutive slices.\nThe dataset is transformed to align the marked areas.']);
        enableWidgets(h, {'TransformationType','TransformationMode'});
        allowed = {'non reflective similarity', 'similarity', 'affine', 'projective'};
        h.TransformationType.Items = allowed;
        obj.BatchOpt.TransformationType{2} = allowed;

    case 'Color channels, multi points'
        helpText = sprintf(['Select the colour channel to move and use annotations to identify ' ...
            'corresponding spots:\ntext = point id\nvalue = colour channel id.']);
        enableWidgets(h, {'TransformationType','TransformationMode','ColorChannel'});
        allowed = {'non reflective similarity', 'similarity', 'affine', 'projective'};
        h.TransformationType.Items = allowed;
        obj.BatchOpt.TransformationType{2} = allowed;
        h.TransformationMode.Value = 'cropped';
        obj.BatchOpt.TransformationMode{1} = 'cropped';
end

h.landmarkHelpText.Text = helpText;
h.landmarkHelpText.Tooltip = helpText;

end

function enableWidgets(h, tags)
% ENABLEWIDGETS - Local helper that turns ``Enable = 'on'`` on every present widget tag.
for k = 1:numel(tags)
    if isfield(h, tags{k})
        h.(tags{k}).Enable = 'on';
    end
end
end
