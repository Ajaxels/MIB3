function fnOut = saveLabels(obj, filename, BatchOptIn)
% function fnOut = saveLabels(obj, filename, BatchOptIn)
% Save the segmentation model (labels layer) for the current dataset.
%
% Thin convenience wrapper around obj.saveImage('labels', ...).
% All BatchOpt machinery (SyncBatch, mibBatchSectionName, FilenamePolicy,
% directory resolution, [F] template) is implemented in saveImage and
% is fully available via this wrapper.
%
% Parameters:
%   obj        — MibModel instance
%   filename   — [@em optional] (char) full output path. When empty ([])
%                a uiputfile dialog is shown. When omitted, the existing
%                labels filename is used.
%   BatchOptIn — [@em optional] (struct | NaN) batch processing options.
%                When NaN, fires SyncBatch event and returns without saving.
%                See models.MibModel.saveImage for the full field list.
%     @li .Format          — output format string
%     @li .FilenamePolicy  — 'Use existing name' | 'Use new provided name'
%     @li .Filename        — output filename stem (supports [F] template)
%     @li .OutputDirectoryPolicy — 'Same as image' | 'Subfolder' | 'Full path' | 'Same as loaded'
%     @li .DestinationDirectory  — target folder
%     @li .Saving3DPolicy  — '3D stack' | '2D sequence'
%     @li .MaterialIndex   — '' = all, 'NaN' = current, integer = specific material
%     @li .showWaitbar     — logical
%     @li .id              — [@em optional] dataset index 1-9, default = obj.id
%
% Return values:
%   fnOut — (char or cell of char) saved filename(s); [] on failure or cancel
%
%|
% @b Examples:
% @code obj.mibModel.saveLabels();         % save using existing filename @endcode
% @code obj.mibModel.saveLabels([]);       % show save-as dialog @endcode
% @code
% BatchOpt.Format                = {'Matlab format (*.model)'};
% BatchOpt.FilenamePolicy        = {'Use existing name'};
% BatchOpt.OutputDirectoryPolicy = {'Same as image'};
% BatchOpt.Saving3DPolicy        = {'3D stack'};
% BatchOpt.showWaitbar           = false;
% BatchOpt.mibBatchTooltip.LayerType = '';   % marks as full batch mode
% obj.mibModel.saveLabels([], BatchOpt);
% @endcode

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
