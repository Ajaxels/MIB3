function intensityProjection(obj, BatchOptIn)
% INTENSITYPROJECTION - Calculate intensity projection of the dataset along a chosen dimension.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.intensityProjection()
%       obj.intensityProjection(BatchOptIn)
%
% Calculates intensity projection (Max, Min, Mean, Median, or Sum) of the current
% dataset along a selected dimension (Y, X, Z, C, or T). The result is written
% back to the active container or to any other open container.
%
% For virtual datasets only Z-projection is available; it is computed slice-by-slice
% to avoid loading the full volume into memory.
%
% Input Arguments:
%   - **BatchOptIn** — *(optional)* a structure for batch processing mode; when ``NaN``
%     returns a structure with default options via ``SyncBatch`` event:
%
%     - ``.ProjectionType`` — cell string, type of projection
%       (default ``{'Max'}``); values ``{'Max', 'Min', 'Mean', 'Median', 'Sum'}``
%       (virtual mode omits ``'Median'``)
%     - ``.Dimension`` — cell string, projection dimension
%       (default ``{'Z'}``); values ``{'Y', 'X', 'Z', 'C', 'T'}``; virtual mode: ``{'Z'}`` only
%     - ``.Set`` — cell string, name of the destination set
%       (default: name of the currently active set), e.g. ``{'Set 1'}``
%     - ``.Container`` — numeric cell, local buffer index within the destination set
%       (default: active buffer); ``{1}`` value, ``{2}`` limits ``[1 N]``, ``{3}`` ``'on'`` (integer)
%     - ``.showWaitbar`` — logical, show the progress bar (default ``true``)
%     - ``.id`` — *(runtime)* index of the source dataset; stripped before ``SyncBatch``
%
% Usage:
%   **Example 1** — max Z-projection interactively
%
%   .. code-block:: matlab
%
%      obj.mibModel.intensityProjection();
%
%   **Example 2** — batch: mean projection along Z to buffer 2 of Set 1
%
%   .. code-block:: matlab
%
%      BatchOpt.ProjectionType = {'Mean'};
%      BatchOpt.Dimension      = {'Z'};
%      BatchOpt.Set            = {'Set 1'};
%      BatchOpt.Container      = {2};
%      BatchOpt.showWaitbar    = false;
%      obj.mibModel.intensityProjection(BatchOpt);
%
%   **Example 3** — return default BatchOpt to the Batch Processing editor
%
%   .. code-block:: matlab
%
%      obj.mibModel.intensityProjection(NaN);
%

% Updates
%

if nargin < 2; BatchOptIn = struct(); end

activeId  = obj.getActiveId();
isVirtual = strcmp(obj.I{activeId}.datasetType, 'Virtual');

if isVirtual
    PossibleProjections = {'Max', 'Min', 'Mean', 'Sum'};
    PossibleDimensions  = {'Z'};
else
    PossibleProjections = {'Max', 'Min', 'Mean', 'Median', 'Sum'};
    PossibleDimensions  = {'Y', 'X', 'Z', 'C', 'T'};
end

activeSetIdx  = ceil(activeId / obj.Sets.datasetsInSet);
activeLocalId = mod(activeId-1, obj.Sets.datasetsInSet) + 1;

%% Default BatchOpt — restore last-used settings from session
BatchOpt = struct();
BatchOpt.ProjectionType = {'Max'};
BatchOpt.Dimension      = {'Z'};
if isfield(obj.sessionSettings, 'intensityProjection')
    ss = obj.sessionSettings.intensityProjection;
    if isfield(ss, 'ProjectionType') && ismember(ss.ProjectionType{1}, PossibleProjections)
        BatchOpt.ProjectionType = ss.ProjectionType;
    end
    if isfield(ss, 'Dimension') && ismember(ss.Dimension{1}, PossibleDimensions)
        BatchOpt.Dimension = ss.Dimension;
    end
end
BatchOpt.ProjectionType{2} = PossibleProjections;
BatchOpt.Dimension{2}      = PossibleDimensions;

BatchOpt.Set       = {obj.Sets.names{activeSetIdx}};
BatchOpt.Set{2}    = obj.Sets.names(:)';
BatchOpt.Container = {activeLocalId, [1 obj.Sets.datasetsInSet], 'on'};

BatchOpt.showWaitbar = true;
BatchOpt.id          = activeId;

BatchOpt.mibBatchSectionName = 'Ribbon -> Image';
BatchOpt.mibBatchActionName  = 'Tools for Images -> Intensity projection';
BatchOpt.mibBatchTooltip.ProjectionType = 'Projection type; when Sum is used the image class may change';
BatchOpt.mibBatchTooltip.Dimension      = 'Dimension for the projection calculation';
BatchOpt.mibBatchTooltip.Set            = 'Name of the destination set';
BatchOpt.mibBatchTooltip.Container      = sprintf('Destination buffer within the set (1-%d)', obj.Sets.datasetsInSet);
BatchOpt.mibBatchTooltip.showWaitbar    = 'Show or not the progress bar during execution';

%% Batch-mode dispatch
if nargin == 2
    if ~isstruct(BatchOptIn)
        if isnan(BatchOptIn)
            BatchOpt = rmfield(BatchOpt, 'id');
            notify(obj, 'SyncBatch', core.ToggleEventData(BatchOpt));
        else
            ErrorDlgOpt.winTitle       = 'BatchOpt Error';
            ErrorDlgOpt.optionalPrefix = 'Error in MibModel.intensityProjection';
            ErrorDlgOpt.err            = 'A structure as the 2nd parameter is required!';
            ErrorDlgOpt.WindowHeight   = 150;
            notify(obj, 'ShowErrorDialog', core.ToggleEventData(ErrorDlgOpt));
        end
        return;
    end
    BatchOpt = utils.updateBatchOptCombineFields_Shared(BatchOpt, BatchOptIn);
end

%% Interactive dialog (nargin < 2)
if nargin < 2
    if obj.I{activeId}.modelExist || obj.I{activeId}.maskExist
        dlgOpt.Icon = 'puffin_warning';
        button = utils.dlgs.inputQuestDlg(obj.getProgressBarParent(), ...
            sprintf('The existing model and mask will be removed during calculation of the intensity projection!'), ...
            'Intensity projection', 'Continue', 'Cancel', 'Cancel', dlgOpt);
        if strcmp(button, 'Cancel'); return; end
    end

    destSetIdx   = find(strcmp(obj.Sets.names, BatchOpt.Set{1}), 1);
    if isempty(destSetIdx); destSetIdx = activeSetIdx; end
    destLocalId  = BatchOpt.Container{1};

    prompts = {'Projection type:'; 'Dimension:'; 'Destination set:'; ...
               sprintf('Destination buffer (1-%d):', obj.Sets.datasetsInSet)};
    defAns  = { [BatchOpt.ProjectionType{2}, {find(strcmp(BatchOpt.ProjectionType{2}, BatchOpt.ProjectionType{1}))}]; ...
                [BatchOpt.Dimension{2},      {find(strcmp(BatchOpt.Dimension{2},      BatchOpt.Dimension{1}))}]; ...
                [obj.Sets.names(:)', {destSetIdx}]; ...
                struct('Spinner', true, 'Value', destLocalId, 'Limits', [1 obj.Sets.datasetsInSet], 'Step', 1, 'Round', true) };
    dlgOptions.Focus   = 1;
    dlgOptions.mibPath = obj.mibPath;
    dlgOptions.WindowHeight = 240;
    dlgOptions.HelpUrl = fullfile(obj.mibPath, 'techdoc/html/user-interface/menu/image/image-tools-projections.html');
    [answer, selIndex] = utils.dlgs.inputUniversalDlg(obj.getProgressBarParent(), '', prompts, defAns, ...
        'Intensity projection', dlgOptions);
    if isempty(answer); return; end

    BatchOpt.ProjectionType(1) = answer(1);
    BatchOpt.Dimension(1)      = answer(2);
    BatchOpt.Set(1)            = {obj.Sets.names{selIndex(3)}};
    BatchOpt.Container{1}      = answer{4};
end

%% Resolve destination global ID
destSetIdx   = find(strcmp(obj.Sets.names, BatchOpt.Set{1}), 1);
if isempty(destSetIdx); destSetIdx = activeSetIdx; end
destGlobalId = BatchOpt.Container{1} + (destSetIdx-1)*obj.Sets.datasetsInSet;

%% Resolve projection dimension index into [h,w,z,c,t]
projectionType = lower(BatchOpt.ProjectionType{1});
dim = find(strcmp(PossibleDimensions, BatchOpt.Dimension{1}));

height    = obj.I{activeId}.image.height;
width     = obj.I{activeId}.image.width;
depth     = obj.I{activeId}.image.depth;
colors    = obj.I{activeId}.image.colors;
time      = obj.I{activeId}.image.time;
dataClass = obj.I{activeId}.image.dataClass;

%% Progress bar
if BatchOpt.showWaitbar
    progressBar = uiprogressdlg(obj.getProgressBarParent(), 'Value', 0, ...
        'Message', 'Generating the projection...', ...
        'Title', 'Intensity projection');
end

%% Compute projection
getDataOptions.blockModeSwitch = 0;
getDataOptions.id = activeId;

if ~isVirtual
    I = cell2mat(obj.getData4D('image', 3, NaN, getDataOptions));   % [h,w,z,c,t]
    if BatchOpt.showWaitbar; progressBar.Value = 0.2; end
    switch projectionType
        case 'max';    I = max(I,   [], dim);
        case 'min';    I = min(I,   [], dim);
        case 'mean';   I = cast(mean(double(I), dim), dataClass);
        case 'median'; I = cast(median(I,        dim), dataClass);
        case 'sum';    I = sum(double(I), dim);
    end
    if BatchOpt.showWaitbar; progressBar.Value = 0.7; end
    % For Y or X projections, move the collapsed singleton into the Z position (dim 3)
    if dim == 1          % Y collapsed: [1,w,z,c,t] → [z,w,1,c,t]
        I = permute(I, [3, 2, 1, 4, 5]);
    elseif dim == 2      % X collapsed: [h,1,z,c,t] → [h,z,1,c,t]
        I = permute(I, [1, 3, 2, 4, 5]);
    end
else
    % Virtual: slice-by-slice Z projection only
    switch projectionType
        case 'min'
            I = zeros([height, width, 1, colors, time], dataClass) + intmax(dataClass);
        case 'max'
            I = zeros([height, width, 1, colors, time], dataClass);
        case {'mean', 'sum'}
            I = zeros([height, width, 1, colors, time]);   % double accumulator
    end
    for t = 1:time
        getDataOptions.t = [t t];
        for z = 1:depth
            Icur  = cell2mat(obj.getData2D('image', z, 3, NaN, getDataOptions));   % [h,w,c]
            Icur5 = reshape(Icur, height, width, 1, colors);
            switch projectionType
                case 'min';  I(:,:,1,:,t) = min(I(:,:,1,:,t), Icur5);
                case 'max';  I(:,:,1,:,t) = max(I(:,:,1,:,t), Icur5);
                case 'mean'; I(:,:,1,:,t) = I(:,:,1,:,t) + double(Icur5)/depth;
                case 'sum';  I(:,:,1,:,t) = I(:,:,1,:,t) + double(Icur5);
            end
        end
        if BatchOpt.showWaitbar; progressBar.Value = 0.1 + 0.6*t/time; end
    end
end

%% Post-process: ensure correct image class
if strcmp(projectionType, 'sum') && ~isa(I, dataClass)
    maxVal = max(I(:));
    if maxVal <= intmax('uint8')
        I = uint8(I);
        dataClass = 'uint8';
    elseif maxVal <= intmax('uint16')
        I = uint16(I);
        dataClass = 'uint16';
    else
        I = uint32(I);
        dataClass = 'uint32';
    end
end

if BatchOpt.showWaitbar; progressBar.Value = 0.85; end

%% Save viewport (restored after writing; not applicable for C projection)
preserveViewPort = ~strcmp(BatchOpt.Dimension{1}, 'C');
if preserveViewPort
    savedViewPort = obj.I{activeId}.image.viewPort;
end

%% Write result
% Always replace with a fresh MibDataset so that slices{}, current_yxz,
% labels, mask, and selection are all reinitialized to the new dimensions.
% Using setData4D in-place would leave the viewing state (slices{3}, etc.)
% pointing at coordinates that no longer exist in the projected dataset.
logText = sprintf('%s-intensity projection, dim=%s', projectionType, BatchOpt.Dimension{1});

if strcmp(obj.I{destGlobalId}.datasetType, 'Virtual')
    obj.I{destGlobalId}.image.closeVirtualDataset();
end
meta = obj.I{activeId}.image.getMeta();
meta{'Height'}   = size(I, 1);
meta{'Width'}    = size(I, 2);
meta{'Depth'}    = size(I, 3);
meta{'Colors'}   = size(I, 4);
meta{'Time'}     = size(I, 5);
meta{'imgClass'} = dataClass;
meta{'MaxInt'}   = double(intmax(dataClass));
obj.I{destGlobalId} = core.MibDataset(I, meta, 'Standard', 'labels63');
if preserveViewPort
    obj.I{destGlobalId}.image.viewPort = savedViewPort;
end
obj.I{destGlobalId}.image.updateActionLog(logText);

if destGlobalId == activeId
    notify(obj, 'NewDataset');
else
    notify(obj, 'NewDataset', core.ToggleEventData(struct('index', destGlobalId)));
end

if BatchOpt.showWaitbar; progressBar.Value = 1; delete(progressBar); end

%% Persist session settings and notify batch recorder
obj.sessionSettings.intensityProjection.ProjectionType = BatchOpt.ProjectionType(1);
obj.sessionSettings.intensityProjection.Dimension      = BatchOpt.Dimension(1);

BatchOpt = rmfield(BatchOpt, 'id');
notify(obj, 'SyncBatch', core.ToggleEventData(BatchOpt));
end
