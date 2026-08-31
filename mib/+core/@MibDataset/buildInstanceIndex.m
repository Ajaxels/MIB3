function [index, cancelled] = buildInstanceIndex(obj, options, wb)
% BUILDINSTANCEINDEX - Build or refresh the cached per-object index of the instance model.
%
% Syntax:
%   .. code-block:: matlab
%
%       index = obj.buildInstanceIndex()
%       index = obj.buildInstanceIndex(options)
%       [index, cancelled] = obj.buildInstanceIndex(options, wb)
%
% Reads the labels layer of one time point and hands it to
% ``utils.instances.objectIndex``, storing the result in ``obj.instanceIndex``.
% The index is what lets ``controllers.InstanceEditor`` answer "where is object
% N" without a volume scan, and what confines every edit to one bounding box.
%
% The whole volume is read with the fast path of ``getData3D`` (Standard
% dataset, XY orientation, all materials, no block mode), which returns a
% copy-on-write alias of the labels array rather than a copy. Nothing here
% writes to it.
%
% Input Arguments:
%   - **options** - *(optional)* structure:
%
%     - ``.timePoint`` - time point to index (default: the currently shown one).
%       The index describes one time point at a time; the field is recorded in
%       the returned struct so a caller can tell when it no longer applies
%     - ``.objectIds`` - refresh only these objects in the existing
%       ``obj.instanceIndex`` instead of rebuilding (default: ``[]`` = full
%       build). Ignored when there is no index yet, or when it belongs to a
%       different time point, in which case a full build is done instead
%     - ``.bbox`` - ``[yMin yMax xMin xMax zMin zMax]`` region the edit changed,
%       passed through to ``utils.instances.objectIndex``
%     - ``.computeSliceCount`` - fill ``.sliceCount`` (default: ``true``)
%
%   - **wb** - *(optional)* handle of a caller-owned cancelable ``uiprogressdlg``,
%     or ``[]``.
%
% Output Arguments:
%   - **index** - the index structure, also stored in ``obj.instanceIndex``. It
%     carries two fields this method owns on top of the utility's:
%
%     - ``.timePoint`` - the time point it describes
%     - ``.stale`` - always ``false`` on return. Set it to ``true`` from outside
%       when the model is edited by anything other than the editor
%
%     Empty when the model is missing or the run was cancelled.
%   - **cancelled** - logical, true when the user pressed Cancel. ``obj.instanceIndex``
%     is then left as it was rather than replaced by a partial index.
%
% Usage:
%   **Example 1** - build the index for the shown time point
%
%   .. code-block:: matlab
%
%      index = obj.mibModel.I{id}.buildInstanceIndex();
%
%   **Example 2** - refresh two objects after an edit
%
%   .. code-block:: matlab
%
%      refreshOptions.objectIds = [7, 12];
%      refreshOptions.bbox = [120 180 300 420 4 19];
%      obj.mibModel.I{id}.buildInstanceIndex(refreshOptions);
%
% See also: utils.instances.objectIndex, models.MibModel.editInstanceObjects

% Updates
%

if nargin < 3; wb = []; end
if nargin < 2 || isempty(options); options = struct(); end

if ~isfield(options, 'timePoint');         options.timePoint = obj.getCurrentTimePoint(); end
if ~isfield(options, 'objectIds');         options.objectIds = []; end
if ~isfield(options, 'bbox');              options.bbox = []; end
if ~isfield(options, 'computeSliceCount'); options.computeSliceCount = true; end

cancelled = false;
index = [];

if ~obj.modelExist || ~obj.labels.exists
    obj.instanceIndex = [];
    return;
end

% Whole labels volume of this time point. NaN as the colour channel asks for the
% raw index map rather than one material as a binary mask, which is what makes
% the zero-copy fast path apply.
readOptions = struct('blockModeSwitch', 0);
volume = cell2mat(obj.getData3D('labels', options.timePoint, 3, NaN, readOptions));

indexOptions = struct('bbox', options.bbox, 'computeSliceCount', options.computeSliceCount);

% A refresh is only valid against an index of the same time point; anything else
% silently describes a different volume, so fall back to a full build.
canRefresh = ~isempty(options.objectIds) && ~isempty(obj.instanceIndex) && ...
    isfield(obj.instanceIndex, 'timePoint') && ...
    isequal(obj.instanceIndex.timePoint, options.timePoint);
if canRefresh
    indexOptions.index = obj.instanceIndex;
    indexOptions.objectIds = options.objectIds;
end

[index, cancelled] = utils.instances.objectIndex(volume, indexOptions, wb);
if cancelled
    % Leave the previous index in place; a partial one would carry stale boxes
    % that the next edit would write through.
    index = [];
    return;
end

index.timePoint = options.timePoint;
index.stale = false;
obj.instanceIndex = index;
end
