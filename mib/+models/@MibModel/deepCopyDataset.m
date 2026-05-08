function newDataset = deepCopyDataset(obj, fromId, toId, options)
% DEEPCOPYDATASET - Deep-copy a MibDataset; optionally install it into another container slot.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.deepCopyDataset(fromId, toId, options)
%       newDataset = obj.deepCopyDataset(fromId, [], options)
%
% @c copy() (matlab.mixin.Copyable) performs a shallow copy only — all
% handle sub-properties (*image,* *labels,* *mask,* *selection,*
% *annotations,* *lines3D,* *measure,* *hROI)* continue to point
% at the same objects after a plain @c copy(). This method fixes that by
% explicitly deep-copying every handle sub-property.
%
% Used by container-buffer and crop operations (cross-container deep copy)
% as well as by :meth:`backup` and :meth:`undo` for the ``'mibDataset'``
% snapshot type.
%
% Input Arguments:
%   - **fromId** — index of the source dataset in ``obj.I``
%   - **toId** — index of the destination dataset in ``obj.I``; when
%     ``[]``, the deep-copied dataset is *not* installed into ``obj.I`` and
%     is only returned via ``newDataset`` (used by undo/backup)
%   - **options** — *(optional)* structure with additional parameters
%
%     - ``.showWaitbar`` — logical, show a progress dialog *(default: true)*
%     - ``.UIFigure`` — handle to a UIFigure for the progress dialog; when
%       empty the dialog is created without a parent *(default:* ``[]`` *)*
%
%
% Output Arguments:
%   - **newDataset** — deep-copied :class:`core.MibDataset`; fully
%     independent of ``obj.I{fromId}``
%
% Usage:
%   **Example 1** — deep-copy dataset from container 1 to container 2
%
%   .. code-block:: matlab
%
%      obj.mibModel.deepCopyDataset(srcId, destId, options);
%
%   **Example 2** — get a free-standing deep copy (no destination slot)
%
%   .. code-block:: matlab
%
%      datasetCopy = obj.mibModel.deepCopyDataset(srcId, [], struct('showWaitbar', false));
%

% Updates
%

if nargin < 4; options = struct(); end
if nargin < 3; toId = []; end
if ~isfield(options, 'showWaitbar'); options.showWaitbar = true; end
if ~isfield(options, 'UIFigure');    options.UIFigure = []; end

wb = [];
if options.showWaitbar
    if ~isempty(options.UIFigure)
        wb = uiprogressdlg(options.UIFigure, 'Value', 0, ...
            'Message', 'Copying dataset, please wait...', ...
            'Title', 'Copy dataset');
    end
end

% close any open virtual file readers at the destination before overwriting
if ~isempty(toId)
    obj.I{toId}.closeVirtualDataset();
end

% --- shallow copy of the entire MibDataset (value-type properties are
%     fully copied; handle-type properties still share the source object)
newDataset = copy(obj.I{fromId});

if options.showWaitbar && ~isempty(wb); wb.Value = 0.15; end

% --- deep-copy image layer (core.MibImage or core.MibVirtualImage)
newDataset.image = copy(obj.I{fromId}.image);

% for Virtual datasets that use BioFormats, the .img cell of reader
% handles must be shared (cannot be serialised / copied)
if strcmp(obj.I{fromId}.datasetType, 'Virtual') && ...
        ~isempty(obj.I{fromId}.image.Virtual) && ...
        isfield(obj.I{fromId}.image.Virtual, 'objectType') && ...
        strcmp(obj.I{fromId}.image.Virtual.objectType{1}, 'bioformats')
    newDataset.image.img = obj.I{fromId}.image.img;
end

if options.showWaitbar && ~isempty(wb); wb.Value = 0.30; end

% --- deep-copy labels layer (core.MibLabels or core.MibLabels63)
if ~isequal(obj.I{fromId}.labels, NaN) && ~isempty(obj.I{fromId}.labels)
    newDataset.labels = copy(obj.I{fromId}.labels);
end

if options.showWaitbar && ~isempty(wb); wb.Value = 0.45; end

% --- deep-copy mask layer (core.MibLabels)
if ~isequal(obj.I{fromId}.mask, NaN) && ~isempty(obj.I{fromId}.mask)
    newDataset.mask = copy(obj.I{fromId}.mask);
end

% --- deep-copy selection layer (core.MibLabels)
if ~isequal(obj.I{fromId}.selection, NaN) && ~isempty(obj.I{fromId}.selection)
    newDataset.selection = copy(obj.I{fromId}.selection);
end

if options.showWaitbar && ~isempty(wb); wb.Value = 0.60; end

% --- deep-copy ROI region; then re-point its back-reference to the new dataset
newDataset.hROI = copy(obj.I{fromId}.hROI);
newDataset.hROI.mibDataset = newDataset;        % re-reference

if options.showWaitbar && ~isempty(wb); wb.Value = 0.70; end

% --- deep-copy annotations (core.Annotations)
newDataset.annotations = copy(obj.I{fromId}.annotations);

if options.showWaitbar && ~isempty(wb); wb.Value = 0.80; end

% --- deep-copy Lines3D skeleton (core.Lines3D)
newDataset.lines3D = copy(obj.I{fromId}.lines3D);

if options.showWaitbar && ~isempty(wb); wb.Value = 0.90; end

% --- deep-copy measurements; class carries a back-reference that must
%     be re-pointed at the new dataset
if ~isempty(obj.I{fromId}.measure)
    newDataset.measure = copy(obj.I{fromId}.measure);
    % re-reference if the class holds a back-pointer (field names vary
    % between versions — use a defensive check)
    if isprop(newDataset.measure, 'mibDataset')
        newDataset.measure.mibDataset = newDataset;
    end
end

if options.showWaitbar && ~isempty(wb); wb.Value = 0.95; end

% --- commit the deep-copied dataset to the destination slot
if ~isempty(toId)
    obj.I{toId} = newDataset;
end

if options.showWaitbar && ~isempty(wb); wb.Value = 1; delete(wb); end
end
