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
if isfield(h, 'Subarea');  h.Subarea.Enable = 'on';  end
if isfield(h, 'previewFeaturesBtn'); h.previewFeaturesBtn.Text = 'Preview'; end

hddModeValue = false;
if isfield(h, 'HDD_Mode')
    hddModeValue = h.HDD_Mode.Value;
    h.HDD_Mode.Enable = 'off';
    h.HDD_Mode.Value = false;
end

helpText = '';
switch methodSelected
    case 'Drift correction'
        helpText = 'Use Drift correction for small shifts between comparably sized images.';
        enableWidgets(h, {'ColorChannel','IntensityGradient','CorrelateWith','HDD_Mode'});
        if isfield(h, 'HDD_Mode'); h.HDD_Mode.Value = hddModeValue; end

    case 'Template matching'
        helpText = 'Use Template matching when one stack is smaller than the other.';
        enableWidgets(h, {'ColorChannel','IntensityGradient','CorrelateWith'});

    case {'Automatic feature-based', 'Automatic feature-based v2'}
        helpText = 'Use automatic feature detection to align slices.';
        enableWidgets(h, {'TransformationType','TransformationMode','FeatureDetectorType', ...
            'previewFeaturesBtn','ColorChannel','HDD_Mode','UseParallelComputing'});
        if isfield(h, 'HDD_Mode'); h.HDD_Mode.Value = hddModeValue; end
        if isfield(h, 'TransformationType')
            if strcmp(methodSelected, 'Automatic feature-based')
                allowed = {'similarity', 'affine', 'projective'};
            else
                allowed = {'translation', 'rigid', 'similarity', 'affine'};
            end
            h.TransformationType.Items = allowed;
            h.TransformationType.Value = allowed{1};
            obj.BatchOpt.TransformationType{2} = allowed;
            obj.BatchOpt.TransformationType{1} = allowed{1};
        end

    case 'AMST: median-smoothed template'
        helpText = ['Align dataset to a Z-median-smoothed version of itself, compensating ' ...
            'for local deformations. The dataset must be pre-aligned with Drift correction.'];
        enableWidgets(h, {'TransformationType','previewFeaturesBtn','ColorChannel', ...
            'MedianSize','UseParallelComputing'});
        if isfield(h, 'TransformationType')
            allowed = {'similarity', 'affine', 'projective'};
            h.TransformationType.Items = allowed;
            h.TransformationType.Value = 'affine';
            obj.BatchOpt.TransformationType{2} = allowed;
            obj.BatchOpt.TransformationType{1} = 'affine';
        end
        if isfield(h, 'TransformationMode')
            h.TransformationMode.Value = 'cropped';
            obj.BatchOpt.TransformationMode{1} = 'cropped';
        end
        if isfield(h, 'previewFeaturesBtn'); h.previewFeaturesBtn.Text = 'Settings'; end
        if isfield(h, 'Subarea');  h.Subarea.Enable = 'off'; end

    case 'Single landmark point'
        helpText = ['Use the Brush or Annotation tool to mark two corresponding spots on ' ...
            'consecutive slices. The dataset is translated to align the marked spots.'];

    case 'Three landmark points'
        helpText = ['Use the Brush tool to mark three corresponding spots on consecutive ' ...
            'slices. The dataset is transformed to align the marked spots. ' ...
            'The Landmark mode is recommended instead.'];

    case 'Landmarks, multi points'
        helpText = ['Use annotations or selection-with-brush to mark corresponding spots on ' ...
            'consecutive slices. The dataset is transformed to align the marked areas.'];
        enableWidgets(h, {'TransformationType','TransformationMode'});
        if isfield(h, 'TransformationType')
            allowed = {'non reflective similarity', 'similarity', 'affine', 'projective'};
            h.TransformationType.Items = allowed;
            obj.BatchOpt.TransformationType{2} = allowed;
        end

    case 'Color channels, multi points'
        helpText = ['Select the colour channel to move and use annotations to identify ' ...
            'corresponding spots: text = point id, value = colour channel id.'];
        enableWidgets(h, {'TransformationType','TransformationMode','ColorChannel'});
        if isfield(h, 'TransformationType')
            allowed = {'non reflective similarity', 'similarity', 'affine', 'projective'};
            h.TransformationType.Items = allowed;
            obj.BatchOpt.TransformationType{2} = allowed;
        end
        if isfield(h, 'TransformationMode')
            h.TransformationMode.Value = 'cropped';
            obj.BatchOpt.TransformationMode{1} = 'cropped';
        end
end

if isfield(h, 'landmarkHelpText')
    h.landmarkHelpText.Text = helpText;
    h.landmarkHelpText.Tooltip = helpText;
end

end

function enableWidgets(h, tags)
% ENABLEWIDGETS - Local helper that turns ``Enable = 'on'`` on every present widget tag.
for k = 1:numel(tags)
    if isfield(h, tags{k})
        h.(tags{k}).Enable = 'on';
    end
end
end
