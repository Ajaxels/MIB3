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
% :func:`utils.instances.stitch2Dto3D`.
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
%     - ``.SplitDisconnected2D`` - logical checkbox. When ``true`` *(default)*
%       each connected blob of a per-slice index is treated as its own 2D
%       object. 2D instance predictors regularly give one index to several
%       separate blobs; keeping them as one object welds their 3D chains
%       together, and the welds chain across slices until most of the stack is
%       a single giant instance. Uncheck only when the per-slice indices are
%       trusted and a genuinely disconnected 2D mask must stay one object.
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
%     - ``.AbsOverlapPixels`` - link two objects whose overlap reaches this many
%       pixels whatever their IoU and IoA (``0`` = disabled). IoU and IoA are
%       both ratios against object area, so a large cross-section meeting a much
%       smaller one scores low on each even when the shared area is substantial.
%       This is a *sufficient* condition added to the ratio tests, the opposite
%       role from ``MinOverlapPixels``, which is a guard applied to all of them.
%       The right value depends on object size in the dataset.
%     - ``.ZLookback`` - how many slices apart to compare. ``1`` = only directly
%       adjacent slices; ``2+`` also compares a slice with the one 2 (or more)
%       planes away, so an object that vanishes for a slice or two is reconnected.
%     - ``.MinObjectVoxels`` - after stitching, delete any 3D object smaller than
%       this many voxels (``0`` = keep all); useful for removing tiny single-slice
%       noise fragments.
%     - ``.MinObjectSlices`` - after stitching, delete any 3D object that appears
%       on this many Z-slices or fewer (``0`` = keep all, ``1`` = drop
%       single-slice objects, ``2`` = also drop those seen on two slices).
%       Catches the noise ``MinObjectVoxels`` cannot: a false detection may be
%       large in-plane yet never propagate through the stack.
%     - ``.AbsorbFragmentVoxels`` - after stitching, give any 3D object of this
%       size or smaller to the object surrounding it in-plane [*default* ``5``,
%       matching ``MinOverlapPixels`` - the size below which an object can never
%       be linked at all; ``0`` = off].
%       2D predictors leave stray pixels inside or on the rim of a neighbouring
%       mask; being smaller than ``MinOverlapPixels`` they can never be linked
%       and survive as specks, usually a hole in an otherwise solid object.
%       Deleting them with ``MinObjectVoxels`` leaves the hole, and relaxing
%       ``MinOverlapPixels`` instead is unsafe - a speck touching two different
%       objects on consecutive slices would then weld them together. A fragment
%       with no labelled neighbour is left for ``MinObjectVoxels``.
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
BatchOpt.SplitDisconnected2D = true;   % each connected blob of an index is its own 2D object
BatchOpt.IoUThreshold = {0.25, [0, 1], 'off'};
BatchOpt.IoAThreshold = true;   % logical -> checkbox; enables IoA-based merging of split objects
BatchOpt.MinOverlapPixels = {5, [0, 1e6], 'on'};
BatchOpt.AbsOverlapPixels = {0, [0, 1e9], 'on'};   % 0 = disabled; sufficient link condition
BatchOpt.ZLookback = {1, [1, 100], 'on'};
BatchOpt.MinObjectVoxels = {0, [0, 1e9], 'on'};
BatchOpt.MinObjectSlices = {0, [0, 1e6], 'on'};   % 0 = keep all, 1 = drop single-slice objects
BatchOpt.AbsorbFragmentVoxels = {5, [0, 1e6], 'on'};   % 0 = off; dust joins the object around it
BatchOpt.UseAnisotropy = false;   % lower the IoU threshold by pixSize.z/pixSize.x
BatchOpt.MaxCentroidShift = {0, [0, 1e6], 'on'};   % 0 = gate disabled
BatchOpt.CentroidLinkRadius = {0, [0, 1e6], 'on'};   % 0 = centroid-NN bridging off
BatchOpt.showWaitbar = true;
BatchOpt.id = obj.getActiveId();

%% Restore the settings last used in this MIB session
% The key is shared with controllers.MibDeep.mergeInstancesTo3D: it is the same
% dialog driving the same algorithm, so a threshold trialled at one entry point
% is offered at the other. The two differ only in how Z anisotropy is asked for,
% which is why that one is stored under two names - 'UseAnisotropy' (this
% method's yes/no, the ratio coming from the dataset pixel size) and
% 'Anisotropy' (MibDeep's raw ratio, prediction images having no pixel size).
% Each entry point reads and writes only its own, so neither clobbers the other.
%
% Only plain values are stored; the spinner limits and rounding flags above stay
% owned by this file, so a stale session entry cannot widen them. Applied before
% the BatchOptIn merge, so an explicit caller argument still wins.
if isfield(obj.sessionSettings, 'stitchInstances2Dto3D')
    lastUsed = obj.sessionSettings.stitchInstances2Dto3D;
    if isfield(lastUsed, 'Method') && ismember(lastUsed.Method, BatchOpt.Method{2})
        BatchOpt.Method{1} = lastUsed.Method;
    end
    for logicalField = {'SplitDisconnected2D', 'IoAThreshold', 'UseAnisotropy'}
        name = logicalField{1};
        if isfield(lastUsed, name) && isscalar(lastUsed.(name))
            BatchOpt.(name) = logical(lastUsed.(name));
        end
    end
    for numericField = {'IoUThreshold', 'MinOverlapPixels', 'AbsOverlapPixels', 'ZLookback', ...
            'MinObjectVoxels', 'MinObjectSlices', 'AbsorbFragmentVoxels', ...
            'MaxCentroidShift', 'CentroidLinkRadius'}
        name = numericField{1};
        if ~isfield(lastUsed, name); continue; end
        storedValue = lastUsed.(name);
        allowedRange = BatchOpt.(name){2};
        if isnumeric(storedValue) && isscalar(storedValue) && ...
                storedValue >= allowedRange(1) && storedValue <= allowedRange(2)
            BatchOpt.(name){1} = storedValue;
        end
    end
end

BatchOpt.mibBatchSectionName = 'Ribbon -> Model';
BatchOpt.mibBatchActionName  = 'Stitch 2D instances to 3D';

BatchOpt.mibBatchTooltip.Method           = 'Linking strategy. "graph": link every pair of overlapping objects on neighbouring slices and group them by connected components - handles objects that split or merge between slices. "hungarian": strict one-to-one matching per slice pair (empanada/MitoNet style) plus a containment merge for leftovers';
BatchOpt.mibBatchTooltip.SplitDisconnected2D = 'Treat each separate blob of a per-slice index as its own 2D object. 2D predictors often give one index to several unconnected blobs; without this they are welded into one 3D object and the welds chain across slices, fusing most of the stack into a single giant instance. Uncheck only if the per-slice indices are trusted and a disconnected 2D mask must stay one object';
BatchOpt.mibBatchTooltip.IoUThreshold     = 'Intersection-over-Union link threshold (0-1). IoU = overlapping pixels / pixels in either object. Two cross-sections on adjacent slices are joined into one 3D object when IoU exceeds this. Higher = only near-identical shapes join (more, smaller objects); lower = looser joining';
BatchOpt.mibBatchTooltip.IoAThreshold     = 'Merge split objects using Intersection-over-Area. When enabled, two objects are also joined when (overlapping pixels)/(pixels in the SMALLER object) is high, i.e. one is mostly contained in the other - this reconnects a 3D object that briefly breaks into small fragments on one slice. Uncheck to link by IoU only';
BatchOpt.mibBatchTooltip.MinOverlapPixels = 'Minimum number of overlapping pixels required before two objects on adjacent slices may be linked. Prevents a 1-2 pixel touch between unrelated objects from fusing them';
BatchOpt.mibBatchTooltip.AbsOverlapPixels = 'Link two objects when they share at least this many pixels, whatever their IoU and IoA. 0 = disabled. IoU and IoA are ratios against object area, so a large cross-section meeting a much smaller one scores low on both even when hundreds of pixels are shared. Note this is the opposite role from "Min overlap": that one blocks links, this one creates them. The right value depends on how large objects are in this dataset';
BatchOpt.mibBatchTooltip.ZLookback        = 'How many slices apart to compare. 1 = only directly adjacent slices; 2 or more also compares a slice with the one further away, so an object that disappears for a slice or two can still be reconnected';
BatchOpt.mibBatchTooltip.MinObjectVoxels  = 'After stitching, remove any 3D object smaller than this many voxels (0 = keep all). Useful for discarding tiny single-slice noise fragments';
BatchOpt.mibBatchTooltip.MinObjectSlices  = 'After stitching, remove any 3D object that appears on this many Z-slices or fewer. 0 = keep all, 1 = remove objects found on a single slice, 2 = also remove those seen on two slices. Catches noise that "Min object size" cannot: a false detection can be large in-plane yet never propagate through the stack';
BatchOpt.mibBatchTooltip.AbsorbFragmentVoxels = 'After stitching, hand any 3D object of this size or smaller to the object surrounding it in-plane, instead of leaving it as a separate speck. 0 = disabled. Stray pixels left by a 2D predictor are smaller than "Min overlap" and so can never be linked; they survive as holes inside otherwise solid objects. Deleting them with "Min object size" leaves the hole behind, and lowering "Min overlap" instead is unsafe, because a speck touching two different objects on consecutive slices would weld them together. A fragment with no labelled neighbour is left alone';
BatchOpt.mibBatchTooltip.UseAnisotropy    ='For anisotropic stacks (thick Z sections), a real continuation is displaced more between slices, so its IoU legitimately drops. When enabled, the IoU threshold is lowered by the voxel aspect ratio (pixSize.z / pixSize.x) taken from the dataset. Pair with a Max centroid shift to stop the relaxed threshold from fusing distant objects';
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

    % the shared dialog (utils.dlgs.stitchInstancesSettingsDlg) also builds the
    % stitch options, but they are rebuilt below from BatchOpt so that the batch
    % path, which never opens the dialog, goes through the same code
    dlgDefaults = struct(...
        'Method',              BatchOpt.Method{1}, ...
        'SplitDisconnected2D', BatchOpt.SplitDisconnected2D, ...
        'IoUThreshold',        BatchOpt.IoUThreshold{1}, ...
        'IoAThreshold',        BatchOpt.IoAThreshold, ...
        'MinOverlapPixels',    BatchOpt.MinOverlapPixels{1}, ...
        'AbsOverlapPixels',    BatchOpt.AbsOverlapPixels{1}, ...
        'ZLookback',           BatchOpt.ZLookback{1}, ...
        'MinObjectVoxels',     BatchOpt.MinObjectVoxels{1}, ...
        'MinObjectSlices',     BatchOpt.MinObjectSlices{1}, ...
        'AbsorbFragmentVoxels', BatchOpt.AbsorbFragmentVoxels{1}, ...
        'Anisotropy',          BatchOpt.UseAnisotropy, ...
        'MaxCentroidShift',    BatchOpt.MaxCentroidShift{1}, ...
        'CentroidLinkRadius',  BatchOpt.CentroidLinkRadius{1});

    dlgSettings.anisotropyMode = 'checkbox';   % the ratio comes from the dataset pixel size
    dlgSettings.dlgTitle = 'Stitch 2D instances to 3D';
    dlgSettings.mibPath = obj.mibPath;
    [~, values] = utils.dlgs.stitchInstancesSettingsDlg(obj.getProgressBarParent(), ...
        note, dlgDefaults, dlgSettings);
    if isempty(values); notify(obj, 'StopProtocol'); return; end

    BatchOpt.Method{1}             = values.Method;
    BatchOpt.SplitDisconnected2D   = values.SplitDisconnected2D;
    BatchOpt.IoUThreshold{1}       = values.IoUThreshold;
    BatchOpt.IoAThreshold          = values.IoAThreshold;
    BatchOpt.MinOverlapPixels{1}   = values.MinOverlapPixels;
    BatchOpt.AbsOverlapPixels{1}   = values.AbsOverlapPixels;
    BatchOpt.ZLookback{1}          = values.ZLookback;
    BatchOpt.MinObjectVoxels{1}    = values.MinObjectVoxels;
    BatchOpt.MinObjectSlices{1}    = values.MinObjectSlices;
    BatchOpt.AbsorbFragmentVoxels{1} = values.AbsorbFragmentVoxels;
    BatchOpt.UseAnisotropy         = values.Anisotropy;
    BatchOpt.MaxCentroidShift{1}   = values.MaxCentroidShift;
    BatchOpt.CentroidLinkRadius{1} = values.CentroidLinkRadius;
end

%% Assemble the options for utils.instances.stitch2Dto3D
% Built from BatchOpt rather than from the dialog result, so the batch path
% (which skips the dialog entirely) produces exactly the same options.
% IoAThreshold is a checkbox: enabled -> use a 0.5 containment threshold;
% disabled -> Inf so IoA never contributes a link (IoU-only linking).
ioaEnabledThreshold = 0.5;
options = struct();
options.method = BatchOpt.Method{1};
options.splitDisconnected2D = logical(BatchOpt.SplitDisconnected2D);
options.iouThreshold = BatchOpt.IoUThreshold{1};
if BatchOpt.IoAThreshold
    options.ioaThreshold = ioaEnabledThreshold;
else
    options.ioaThreshold = inf;
end
options.minOverlapPixels = BatchOpt.MinOverlapPixels{1};
options.absOverlapPixels = BatchOpt.AbsOverlapPixels{1};
options.zLookback = BatchOpt.ZLookback{1};
options.minObjectVoxels = BatchOpt.MinObjectVoxels{1};
options.minObjectSlices = BatchOpt.MinObjectSlices{1};
options.absorbFragmentVoxels = BatchOpt.AbsorbFragmentVoxels{1};

% Anisotropic Z: the dialog only collects a yes/no, so derive the voxel aspect
% ratio from the dataset pixel size here and pass it through so the utility
% lowers the effective IoU threshold for thick sections. Left at 1 (isotropic,
% no relaxation) when the option is off.
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
    % Indeterminate: the phases inside utils.instances.stitch2Dto3D report themselves
    % through wb.Message (which slice of which pass), but there is no single
    % fraction that covers them all honestly.
    wb = uiprogressdlg(obj.getProgressBarParent(), 'Indeterminate', 'on', ...
        'Message', 'Stitching 2D instances into 3D objects, please wait...', ...
        'Title', 'Stitch 2D instances to 3D', 'Cancelable', 'on');
end

tic
stats = obj.I{BatchOpt.id}.stitchModelInstances(options, wb);
toc

% Cancelled: the dataset was left untouched by MibDataset.stitchModelInstances,
% so there is nothing to undo, redraw or report back to a batch protocol.
if stats.cancelled
    if ~isempty(wb) && isvalid(wb); delete(wb); end
    fprintf('MibModel.stitchModelInstances: cancelled by the user, the model was not modified\n');
    notify(obj, 'StopProtocol');
    return;
end

if obj.preferences.System.DeveloperMode
    fprintf('MibModel.stitchModelInstances: %d 2D objects -> %d 3D instances (method=%s)\n', ...
        stats.numInput2DObjects, stats.numOutput3DObjects, options.method);
    if stats.numAbsorbedFragments > 0
        fprintf('   %d fragments absorbed into their neighbours (%d voxels)\n', ...
            stats.numAbsorbedFragments, stats.numAbsorbedVoxels);
    end
end

%% Remember the settings for the rest of this MIB session
% So a second run of the dialog opens on the values just used - the common case
% while trialling thresholds on one dataset - whether that run comes from here or
% from DeepMIB's "Merge 2D to 3D". Written field by field into whatever is
% already stored rather than replacing it, so MibDeep's 'Anisotropy' ratio
% survives a run from this side (see the note at the top).
sessionValues = struct(...
    'Method',              BatchOpt.Method{1}, ...
    'SplitDisconnected2D', BatchOpt.SplitDisconnected2D, ...
    'IoUThreshold',        BatchOpt.IoUThreshold{1}, ...
    'IoAThreshold',        BatchOpt.IoAThreshold, ...
    'MinOverlapPixels',    BatchOpt.MinOverlapPixels{1}, ...
    'AbsOverlapPixels',    BatchOpt.AbsOverlapPixels{1}, ...
    'ZLookback',           BatchOpt.ZLookback{1}, ...
    'MinObjectVoxels',     BatchOpt.MinObjectVoxels{1}, ...
    'MinObjectSlices',     BatchOpt.MinObjectSlices{1}, ...
    'AbsorbFragmentVoxels', BatchOpt.AbsorbFragmentVoxels{1}, ...
    'UseAnisotropy',       BatchOpt.UseAnisotropy, ...
    'MaxCentroidShift',    BatchOpt.MaxCentroidShift{1}, ...
    'CentroidLinkRadius',  BatchOpt.CentroidLinkRadius{1});
if isfield(obj.sessionSettings, 'stitchInstances2Dto3D')
    stored = obj.sessionSettings.stitchInstances2Dto3D;
else
    stored = struct();
end
for sessionField = fieldnames(sessionValues)'
    stored.(sessionField{1}) = sessionValues.(sessionField{1});
end
obj.sessionSettings.stitchInstances2Dto3D = stored;

notify(obj, 'UpdateGuiWidgets', core.ToggleEventData({'ribbonModel', 'checkboxes'}));
notify(obj, 'ShowImage');

% Notify batch mode
BatchOpt = rmfield(BatchOpt, 'id');
eventdata = core.ToggleEventData(BatchOpt);
notify(obj, 'SyncBatch', eventdata);

if BatchOpt.showWaitbar && ~isempty(wb) && isvalid(wb); delete(wb); end
end
