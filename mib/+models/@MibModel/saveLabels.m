function fnOut = saveLabels(obj, filename, BatchOptIn)
% SAVELABELS - Save the segmentation model (labels layer) for the current dataset.
%
% Syntax:
%   function fnOut = saveLabels(obj, filename, BatchOptIn)
%
% Thin convenience wrapper around obj.saveImage('labels', ...).
% All BatchOpt machinery (SyncBatch, mibBatchSectionName, FilenamePolicy,
% directory resolution, [F] template) is implemented in saveImage and
% is fully available via this wrapper.
%
% Input Arguments:
%   obj        — MibModel instance
%   filename   — *(optional)* (char) full output path. When empty ([])
%   a uiputfile dialog is shown. When omitted, the existing
%   labels filename is used.
%   BatchOptIn — *(optional)* (struct | NaN) batch processing options.
%   When NaN, fires SyncBatch event and returns without saving.
%   See models.MibModel.saveImage for the full field list.
%   - .Format          — output format string
%   - .FilenamePolicy  — 'Use existing name' | 'Use new provided name'
%   - .Filename        — output filename stem (supports [F] template)
%   - .OutputDirectoryPolicy — 'Same as image' | 'Subfolder' | 'Full path' | 'Same as loaded'
%   - .DestinationDirectory  — target folder
%   - .Saving3DPolicy  — '3D stack' | '2D sequence'
%   - .MaterialIndex   — '' = all, 'NaN' = current, integer = specific material
%   - .showWaitbar     — logical
%   - .id              — *(optional)* dataset index 1-9, default = obj.id
%
% Output Arguments:
%   fnOut — (char or cell of char) saved filename(s); [] on failure or cancel
%
% Usage:
%   **Example 1** — save using existing filename
%
%   .. code-block:: matlab
%
%      obj.mibModel.saveLabels();
%
%   **Example 2** — show save-as dialog
%
%   .. code-block:: matlab
%
%      obj.mibModel.saveLabels([]);
%
%   **Example 3** — full batch mode
%
%   .. code-block:: matlab
%
%      BatchOpt.Format                = {'Matlab format (``*.model``)'};
%      BatchOpt.FilenamePolicy        = {'Use existing name'};
%      BatchOpt.OutputDirectoryPolicy = {'Same as image'};
%      BatchOpt.Saving3DPolicy        = {'3D stack'};
%      BatchOpt.showWaitbar           = false;
%      BatchOpt.mibBatchTooltip.LayerType = '';
%      obj.mibModel.saveLabels([], BatchOpt);
%

% Updates

if nargin < 2
    % No filename given: use existing labels filename and save without dialog
    filename = obj.I{obj.id}.labels.filename;
end
if nargin < 3
    fnOut = obj.saveImage('labels', filename);
else
    fnOut = obj.saveImage('labels', filename, BatchOptIn);
end
end
