function str = buildImageDescription(bb, actionLog)
% BUILDIMAGEDESCRIPTION - Reconstruct a full ImageDescription string from a bounding box vector and an action log cell array.
%
% Syntax:
%   .. code-block:: matlab
%
%       str = buildImageDescription(bb, actionLog)
%
% This is the inverse of core.MibImage.splitImageDescription.  It produces
% the canonical string written into the ImageDescription tag of TIFF files
% and equivalent metadata fields in other formats (HDF5, NRRD, AmiraMesh…).
%
% FORMAT
% The reconstructed string has the form:
%
% 'BoundingBox x1 x2 y1 y2 z1 z2|LogEntry1|LogEntry2|...'
%
% where the six floating-point numbers are the physical extents of the
% dataset in the order  [xmin xmax ymin ymax zmin zmax]  (units: µm by
% default, matching MibDataset.pixSize.units).
%
% When actionLog is empty, no pipe or log entries are appended.
% When bb is empty or invalid, the BoundingBox prefix is omitted and the
% result contains only the joined log entries (or '' if both are empty).
%
% Input Arguments:
%   - **bb** - (1×6 double) bounding box ``[xmin xmax ymin ymax zmin zmax]``.
%     Pass ``[]`` to omit the BoundingBox prefix.
%   - **actionLog** - (1×N cell of char) per-operation log strings.
%     Pass ``{}`` or ``[]`` to produce a string with no log section.
%
% Output Arguments:
%   - **str** - (char) the reconstructed ImageDescription string, ready to be
%     written to a file or stored in a metadata struct.
%
% Usage:
%   **Example 1** - Full round-trip: split then rebuild
%
%   .. code-block:: matlab
%
%
%       raw = ['BoundingBox 0.000000 6.760000 0.000000 4.823000 0.000000 2.220000 ' ...
%              '|MIB(2601041823): MIB demo dataset, Huh7 SBEM' ...
%              '|MIB(2603131934): ImFilter: Gaussian, HSize:3  3, Sigma: 0.6'];
%
%       [imgDesc, log] = core.MibImage.splitImageDescription(raw);
%       bb = sscanf(imgDesc, 'BoundingBox %f %f %f %f %f %f')';
%
%       rebuilt = core.MibImage.buildImageDescription(bb, log);
%       % rebuilt -> 'BoundingBox 0.000000 6.760000 0.000000 4.823000 0.000000 2.220000 |MIB...'
%
%   **Example 2** - From a MibImage object in MibImage.save()
%
%   .. code-block:: matlab
%
%
%       metadata.imageDescription = core.MibImage.buildImageDescription( ...
%           obj.boundingBox, obj.actionLog);
%       metadata.boundingBox = obj.boundingBox;
%
%   **Example 3** - Mask save in MibDataset.saveImage()
%
%   .. code-block:: matlab
%
%
%       metadata.imageDescription = core.MibImage.buildImageDescription( ...
%           obj.image.boundingBox, obj.image.actionLog);
%
%   **Example 4** - BoundingBox only, no log
%
%   .. code-block:: matlab
%
%
%       bb  = [0, 511.5, 0, 511.5, 0, 49.5];
%       str = core.MibImage.buildImageDescription(bb, {});
%       % str -> 'BoundingBox 0.000000 511.500000 0.000000 511.500000 0.000000 49.500000'
%
%   **Example 5** - Log only, no spatial calibration
%
%   .. code-block:: matlab
%
%
%       str = core.MibImage.buildImageDescription([], {'ImageJ=1.52p', 'unit=um'});
%       % str -> 'ImageJ=1.52p|unit=um'
%
%   **Example 6** - Append a new log entry to a MibImage in-place
%
%   .. code-block:: matlab
%
%
%       img.updateActionLog('ImFilter: Median, HSize:3 3, Orient:4');
%       % The timestamp is added automatically; the next call to img.save()
%       % will include the new entry automatically.
%
% See also:
%   core.MibImage.splitImageDescription, core.MibImage.save, core.MibDataset.saveImage
%

% --- BoundingBox prefix ---
if ~isempty(bb) && isnumeric(bb) && numel(bb) == 6
    bbStr = sprintf('BoundingBox %f %f %f %f %f %f', ...
        bb(1), bb(2), bb(3), bb(4), bb(5), bb(6));
else
    bbStr = '';
end

% --- action log section ---
if isempty(actionLog)
    logStr = '';
else
    logStr = strjoin(actionLog(:)', '|');
end

% --- combine ---
if isempty(bbStr) && isempty(logStr)
    str = '';
elseif isempty(logStr)
    str = bbStr;
elseif isempty(bbStr)
    str = logStr;
else
    str = [bbStr ' |' logStr];
end
end
