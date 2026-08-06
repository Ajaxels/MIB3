function stitchModelInstances(obj, BatchOptIn)
% STITCHMODELINSTANCES - Stitch per-slice 2D instance labels into a 3D instance model.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.stitchModelInstances()
%       obj.stitchModelInstances(BatchOptIn)
%
% Treats the active labels layer as a stack of independently generated 2D
% instance segmentations (per-slice indices, not consistent across slices) and
% links overlapping objects between neighbouring slices into single 3D
% instances with one consistent index through the whole stack. Wrapper around
% :func:`core.MibDataset.stitchModelInstances`, which in turn calls
% :func:`utils.stitchInstances2Dto3D`.
%
% When called interactively (no ``BatchOptIn`` or a struct without ``.Method``)
% a settings dialog is shown to pick the linking strategy and thresholds. The
% current model is backed up first, so the operation can be undone (Ctrl+Z).
%
% Input Arguments:
%   - **BatchOptIn** *(optional)* - structure for batch processing; pass ``NaN``
%     to return default options via the ``SyncBatch`` event
%
%     - ``.Method`` - cell string dropdown selecting the linking strategy:
%
%       - ``'graph'`` *(default)* - link every pair of overlapping objects on
%         neighbouring slices, then group the links into 3D objects by connected
%         components. Naturally handles objects that split into several pieces or
%         merge together between slices.
%       - ``'hungarian'`` - strict one-to-one matching per slice pair (empanada /
%         MitoNet style), plus a containment merge for the leftovers.
%
%     - ``.IoUThreshold`` - Intersection-over-Union link threshold, range 0-1. For
%       two objects on adjacent slices, ``IoU = overlapping pixels / pixels in
%       either object``; they are joined into one 3D object when IoU exceeds this
%       value. **Higher** = only near-identical cross-sections are joined (more,
%       smaller 3D objects); **lower** = looser joining (fewer, larger objects).
%     - ``.IoAThreshold`` - logical checkbox: enable Intersection-over-Area
%       merging of split objects. When ``true`` *(default)*, two objects are also
%       joined when ``overlapping pixels / pixels in the *smaller* object`` is
%       high (one is mostly contained in the other), reconnecting a 3D object
%       that briefly breaks into small fragments on one slice. When ``false``,
%       objects are linked by IoU only. (Internally maps to an IoA threshold of
%       ``0.5`` when enabled, ``Inf`` when disabled.)
%     - ``.MinOverlapPixels`` - absolute minimum number of overlapping pixels
%       before two objects may be linked; stops a 1-2 px touch between unrelated
%       objects from fusing them.
%     - ``.ZLookback`` - how many slices apart to compare. ``1`` = only directly
%       adjacent slices; ``2+`` also compares a slice with the one 2 (or more)
%       planes away, so an object that vanishes for a slice or two is reconnected.
%     - ``.MinObjectVoxels`` - after stitching, delete any 3D object smaller than
%       this many voxels (``0`` = keep all); useful for removing tiny single-slice
%       noise fragments.
%     - ``.UseAnisotropy`` - logical. When ``true``, the IoU link threshold is
%       lowered by the dataset voxel aspect ratio ``pixSize.z / pixSize.x`` so a
%       real but displaced continuation still links across thick Z sections. IoA
%       (containment) is unaffected. Pair with ``MaxCentroidShift`` to stop the
%       relaxed threshold from fusing distant objects [*default* ``false``].
%     - ``.MaxCentroidShift`` - reject a link when the two object centroids are
%       more than this many pixels apart (scaled by the slice gap when
%       ``ZLookback`` > 1); ``0`` = disabled.
%     - ``.CentroidLinkRadius`` - advanced centroid nearest-neighbour gap
%       bridging: link an object that has no overlapping neighbour to the
%       mutually-nearest such orphan on the next compared slice within this many
%       pixels (scaled by the slice gap), when of comparable size. Reconnects a
%       displaced or briefly-missing continuation on anisotropic/gappy data;
%       ``0`` = disabled.
%     - ``.showWaitbar`` - logical, show or not the waitbar [*default* ``true``]
%     - ``.id`` - *(optional)* dataset index 1-9; default = active dataset
%
% Output Arguments:
%   (none)
%
% **Example** - stitch the active model with default (graph) settings
%
%   .. code-block:: matlab
%
%      obj.mibModel.stitchModelInstances();
%

% Updates
%

if nargin < 2; BatchOptIn = struct(); end
% interactive when called with no batch struct (or a struct that lacks .Method)
showDialog = isstruct(BatchOptIn) && ~isfield(BatchOptIn, 'Method');

%% Declaration of the BatchOpt structure
BatchOpt = struct();
BatchOpt.Method = {'graph'};
BatchOpt.Method{2} = {'graph', 'hungarian'};
BatchOpt.IoUThreshold = {0.25, [0, 1], 'off'};
BatchOpt.IoAThreshold = true;   % logical -> checkbox; enables IoA-based merging of split objects
BatchOpt.MinOverlapPixels = {5, [0, 1e6], 'on'};
BatchOpt.ZLookback = {1, [1, 100], 'on'};
BatchOpt.MinObjectVoxels = {0, [0, 1e9], 'on'};
BatchOpt.UseAnisotropy = false;   % lower the IoU threshold by pixSize.z/pixSize.x
BatchOpt.MaxCentroidShift = {0, [0, 1e6], 'on'};   % 0 = gate disabled
BatchOpt.CentroidLinkRadius = {0, [0, 1e6], 'on'};   % 0 = centroid-NN bridging off
BatchOpt.showWaitbar = true;
BatchOpt.id = obj.getActiveId();

BatchOpt.mibBatchSectionName = 'Ribbon -> Model';
BatchOpt.mibBatchActionName  = 'Stitch 2D instances to 3D';

BatchOpt.mibBatchTooltip.Method           = 'Linking strategy. "graph": link every pair of overlapping objects on neighbouring slices and group them by connected components - handles objects that split or merge between slices. "hungarian": strict one-to-one matching per slice pair (empanada/MitoNet style) plus a containment merge for leftovers';
BatchOpt.mibBatchTooltip.IoUThreshold     = 'Intersection-over-Union link threshold (0-1). IoU = overlapping pixels / pixels in either object. Two cross-sections on adjacent slices are joined into one 3D object when IoU exceeds this. Higher = only near-identical shapes join (more, smaller objects); lower = looser joining';
BatchOpt.mibBatchTooltip.IoAThreshold     = 'Merge split objects using Intersection-over-Area. When enabled, two objects are also joined when (overlapping pixels)/(pixels in the SMALLER object) is high, i.e. one is mostly contained in the other - this reconnects a 3D object that briefly breaks into small fragments on one slice. Uncheck to link by IoU only';
BatchOpt.mibBatchTooltip.MinOverlapPixels = 'Minimum number of overlapping pixels required before two objects on adjacent slices may be linked. Prevents a 1-2 pixel touch between unrelated objects from fusing them';
BatchOpt.mibBatchTooltip.ZLookback        = 'How many slices apart to compare. 1 = only directly adjacent slices; 2 or more also compares a slice with the one further away, so an object that disappears for a slice or two can still be reconnected';
BatchOpt.mibBatchTooltip.MinObjectVoxels  = 'After stitching, remove any 3D object smaller than this many voxels (0 = keep all). Useful for discarding tiny single-slice noise fragments';
BatchOpt.mibBatchTooltip.UseAnisotropy    = 'For anisotropic stacks (thick Z sections), a real continuation is displaced more between slices, so its IoU legitimately drops. When enabled, the IoU threshold is lowered by the voxel aspect ratio (pixSize.z / pixSize.x) taken from the dataset. Pair with a Max centroid shift to stop the relaxed threshold from fusing distant objects';
BatchOpt.mibBatchTooltip.MaxCentroidShift = 'Reject a link when the two object centroids are more than this many pixels apart (scaled by the slice gap when Z lookback > 1). 0 = disabled. Use together with anisotropic-Z relaxation so that a lower IoU threshold does not merge far-apart objects';
BatchOpt.mibBatchTooltip.CentroidLinkRadius = 'Centroid nearest-neighbour gap bridging (advanced, for anisotropic / gappy data). For an object with NO overlapping neighbour on the next compared slice, link it to the mutually-nearest such orphan within this many pixels (scaled by the slice gap), if of comparable size. Reconnects a continuation that is laterally displaced or briefly missing. 0 = disabled';
BatchOpt.mibBatchTooltip.showWaitbar      = 'Show or not the progress bar during execution';

%% Batch mode check actions
batchModeSwitch = 0;
if isstruct(BatchOptIn) == 0
    if isscalar(BatchOptIn) && isnan(BatchOptIn)
        BatchOpt = rmfield(BatchOpt, 'id');
        eventdata = core.ToggleEventData(BatchOpt);
        notify(obj, 'SyncBatch', eventdata);
    else
        ErrorDlgOpt.winTitle = 'BatchOpt Error';
        ErrorDlgOpt.optionalPrefix = 'Error in MibModel.stitchModelInstances';
        ErrorDlgOpt.err = 'A structure as the 2nd parameter is required!';
        ErrorDlgOpt.WindowHeight = 150;
        eventdata = core.ToggleEventData(ErrorDlgOpt);
        notify(obj, 'ShowErrorDialog', eventdata);
    end
    return;
else
    BatchOpt = utils.updateBatchOptCombineFields_Shared(BatchOpt, BatchOptIn);
    if isfield(BatchOptIn, 'mibBatchTooltip'); batchModeSwitch = 1; end
end

dlgOpt.mibPath = obj.mibPath;

%% Virtual stacking guard
if strcmp(obj.I{BatchOpt.id}.datasetType, 'Virtual')
    dlgOpt.MsgBoxOnly  = true;
    dlgOpt.Icon        = 'puffin_warning';
    dlgOpt.HeaderLines = 1;
    utils.dlgs.inputUniversalDlg(obj.getProgressBarParent(), 'Not available in virtual stacking mode!', {''}, ...
        {'Instance stitching requires memory-resident mode. Please switch to standard mode and try again.'}, ...
        'Virtual mode', dlgOpt);
    notify(obj, 'StopProtocol');
    return;
end

%% Initial checks
if obj.I{BatchOpt.id}.enableSelection == 0
    dlgOpt.MsgBoxOnly  = true;
    dlgOpt.Icon        = 'puffin_warning';
    dlgOpt.HeaderLines = 1;
    utils.dlgs.inputUniversalDlg(obj.getProgressBarParent(), 'The models are switched off!', {''}, ...
        {'Please enable the "Enable selection" option in Preferences (Ribbon -> Home -> Preferences) and try again.'}, ...
        'Models are disabled', dlgOpt);
    notify(obj, 'StopProtocol');
    return;
end

if ~obj.I{BatchOpt.id}.modelExist
    dlgOpt.MsgBoxOnly  = true;
    dlgOpt.Icon        = 'puffin_warning';
    dlgOpt.HeaderLines = 1;
    utils.dlgs.inputUniversalDlg(obj.getProgressBarParent(), 'No model exists!', {''}, ...
        {'Please load or create a 2D instance model first (Ribbon -> Models -> Load Model).'}, ...
        'No model', dlgOpt);
    notify(obj, 'StopProtocol');
    return;
end

%% Interactive settings dialog
if showDialog && ~batchModeSwitch
    note = sprintf(['The active model is treated as a stack of independent 2D instance masks;\n' ...
        'objects overlapping between neighbouring slices are linked into one 3D instance.']);

    prompt = {...
        sprintf('Method:\n  "graph" links every overlapping pair and groups them by connected components\n  "hungarian" uses strict 1-to-1 matching per slice pair'), ...
        sprintf('IoU threshold (0-1):\n  join two objects when (overlap area)/(their union area) exceeds this;\nhigher = stricter, giving more but smaller 3D objects'), ...
        sprintf('Merge split objects (IoA):\n  also join when a smaller object is mostly contained in a neighbour,\n  reconnecting an object that breaks into pieces on one slice'), ...
        sprintf('Min overlap (pixels):\n  require at least this many overlapping pixels before linking, to block tiny spurious touches'), ...
        sprintf('Z lookback (slices):\n  also compare slices this many planes apart;\n  1 = adjacent slices only, higher bridges an object that briefly vanishes'), ...
        sprintf('Min object size (voxels):\n  after stitching, delete 3D objects smaller than this; 0 = keep all'), ...
        sprintf('Anisotropic Z (use pixel size):\n  lower the IoU threshold by pixSize.z/pixSize.x for thick sections,\n  so a real but displaced continuation still links'), ...
        sprintf('Max centroid shift (pixels):\n  reject a link when object centroids are farther apart than this;\n  0 = off. Pair with anisotropic Z to avoid fusing distant objects'), ...
        sprintf('Centroid link radius (pixels):\n  advanced gap bridging - link an object with no overlapping neighbour\n  to the mutually-nearest one within this distance; 0 = off')};

    methodChoices = [BatchOpt.Method{2}, find(strcmp(BatchOpt.Method{2}, BatchOpt.Method{1}))];
    defAns = {methodChoices, ...
              struct('Spinner', true, 'Value', BatchOpt.IoUThreshold{1},     'Limits', BatchOpt.IoUThreshold{2},     'Step', 0.05, 'Round', false), ...
              logical(BatchOpt.IoAThreshold), ...
              struct('Spinner', true, 'Value', BatchOpt.MinOverlapPixels{1}, 'Limits', BatchOpt.MinOverlapPixels{2}, 'Step', 1,    'Round', true), ...
              struct('Spinner', true, 'Value', BatchOpt.ZLookback{1},        'Limits', BatchOpt.ZLookback{2},        'Step', 1,    'Round', true), ...
              struct('Spinner', true, 'Value', BatchOpt.MinObjectVoxels{1},  'Limits', BatchOpt.MinObjectVoxels{2},  'Step', 1,    'Round', true), ...
              logical(BatchOpt.UseAnisotropy), ...
              struct('Spinner', true, 'Value', BatchOpt.MaxCentroidShift{1},   'Limits', BatchOpt.MaxCentroidShift{2},   'Step', 1, 'Round', true), ...
              struct('Spinner', true, 'Value', BatchOpt.CentroidLinkRadius{1}, 'Limits', BatchOpt.CentroidLinkRadius{2}, 'Step', 1, 'Round', true)};

    dlgParams.mibPath = obj.mibPath;
    dlgParams.WindowWidth = 720;
    dlgParams.WindowHeight = 560;
    dlgParams.HeaderLines = 2;
    dlgParams.LabelPosition = 'left';
    answer = utils.dlgs.inputUniversalDlg(obj.getProgressBarParent(), note, prompt, defAns, ...
        'Stitch 2D instances to 3D', dlgParams);
    if isempty(answer); notify(obj, 'StopProtocol'); return; end

    BatchOpt.Method{1}          = answer{1};
    BatchOpt.IoUThreshold{1}    = answer{2};
    BatchOpt.IoAThreshold       = answer{3};   % logical (checkbox)
    BatchOpt.MinOverlapPixels{1} = answer{4};
    BatchOpt.ZLookback{1}       = answer{5};
    BatchOpt.MinObjectVoxels{1} = answer{6};
    BatchOpt.UseAnisotropy      = answer{7};   % logical (checkbox)
    BatchOpt.MaxCentroidShift{1} = answer{8};
    BatchOpt.CentroidLinkRadius{1} = answer{9};
end

%% Assemble the options for utils.stitchInstances2Dto3D
% IoAThreshold is a checkbox: enabled -> use a 0.5 containment threshold;
% disabled -> Inf so IoA never contributes a link (IoU-only linking).
ioaEnabledThreshold = 0.5;
options = struct();
options.method = BatchOpt.Method{1};
options.iouThreshold = BatchOpt.IoUThreshold{1};
if BatchOpt.IoAThreshold
    options.ioaThreshold = ioaEnabledThreshold;
else
    options.ioaThreshold = inf;
end
options.minOverlapPixels = BatchOpt.MinOverlapPixels{1};
options.zLookback = BatchOpt.ZLookback{1};
options.minObjectVoxels = BatchOpt.MinObjectVoxels{1};

% Anisotropic Z: derive the voxel aspect ratio from the dataset pixel size and
% pass it through so the utility lowers the effective IoU threshold for thick
% sections. Left at 1 (isotropic, no relaxation) when the option is off.
if BatchOpt.UseAnisotropy
    pixSize = obj.I{BatchOpt.id}.image.pixSize;
    if isfield(pixSize, 'x') && pixSize.x > 0
        options.anisotropyZ = max(1, pixSize.z / pixSize.x);
    end
end
% Centroid-shift gate: 0 in the UI means disabled (Inf inside the utility).
if BatchOpt.MaxCentroidShift{1} > 0
    options.maxCentroidShift = BatchOpt.MaxCentroidShift{1};
end
% Centroid-NN gap bridging: 0 = disabled.
if BatchOpt.CentroidLinkRadius{1} > 0
    options.centroidLinkRadius = BatchOpt.CentroidLinkRadius{1};
end

%% Backup the current model for undo (skip in batch protocols)
% 'modelLayers' rather than 'labels': stitching replaces the labels layer with
% an indexed uint16/uint32 model, so a pixel snapshot taken at the old type
% (typically the bit-packed type 63) could not be written back on Ctrl+Z
if ~batchModeSwitch
    obj.backup('modelLayers', 1, struct('id', BatchOpt.id));
end

%% Perform stitching
wb = [];
if BatchOpt.showWaitbar
    % Indeterminate: the graph-building phase inside stitchInstances2Dto3D is a
    % single opaque pass with no fine-grained progress to report.
    wb = uiprogressdlg(obj.getProgressBarParent(), 'Indeterminate', 'on', ...
        'Message', 'Stitching 2D instances into 3D objects, please wait...', ...
        'Title', 'Stitch 2D instances to 3D');
end

tic
stats = obj.I{BatchOpt.id}.stitchModelInstances(options, wb);
toc

if obj.preferences.System.DeveloperMode
    fprintf('MibModel.stitchModelInstances: %d 2D objects -> %d 3D instances (method=%s)\n', ...
        stats.numInput2DObjects, stats.numOutput3DObjects, options.method);
end

notify(obj, 'UpdateGuiWidgets', core.ToggleEventData({'ribbonModel', 'checkboxes'}));
notify(obj, 'ShowImage');

% Notify batch mode
BatchOpt = rmfield(BatchOpt, 'id');
eventdata = core.ToggleEventData(BatchOpt);
notify(obj, 'SyncBatch', eventdata);

if BatchOpt.showWaitbar && ~isempty(wb) && isvalid(wb); delete(wb); end
end
