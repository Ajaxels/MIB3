function pixSize = layoutPixSize(layout)
% LAYOUTPIXSIZE - The acquisition pixel size a layout carries, if it carries one.
%
% Syntax:
%   .. code-block:: matlab
%
%      pixSize = utils.stitch.layoutPixSize(layout)
%
% Layout sources that read a real acquisition record - SerialEM ``.mdoc``, Fibics
% Atlas ``.ve-mif``, Bio-Formats OME metadata - know the physical pixel size and
% attach it to every tile as ``layout(k).pixSize``. Sources that only see a folder
% of images (Grid, filename pattern, MIB position file) do not, and say so by not
% having the field at all.
%
% This resolves that into one answer for the whole mosaic, so callers do not each
% have to re-implement the "is it there, and is it usable?" test. It returns
% ``[]`` rather than a default when nothing is known, which lets the caller leave
% ``planCanvas`` to apply its own 1 um fallback instead of inventing a number here
% that would then be indistinguishable from a measured one.
%
% Input Arguments:
%   - **layout** - [struct array] tile layout.
%
% Output Arguments:
%   - **pixSize** - [struct] ``.x .y .z`` in µm plus ``.units``, or ``[]`` when the
%     layout carries no usable pixel size.
%
% **Example**
%
%   .. code-block:: matlab
%
%      pixSize = utils.stitch.layoutPixSize(layout);
%      if ~isempty(pixSize); canvasOptions.pixSize = pixSize; end
%
% See also utils.stitch.planCanvas, utils.stitch.buildLayoutMdoc

arguments
    layout struct
end

pixSize = [];
if isempty(layout) || ~isfield(layout, 'pixSize'); return; end

% First tile that has a complete, positive, finite triple wins. Tiles of one
% mosaic share a scale, so there is nothing to reconcile - but a builder that
% failed to read the metadata for one tile should not veto the rest.
for tileIdx = 1:numel(layout)
    candidate = layout(tileIdx).pixSize;
    if isempty(candidate) || ~isstruct(candidate); continue; end
    if ~all(isfield(candidate, {'x', 'y', 'z'})); continue; end
    values = [candidate.x, candidate.y, candidate.z];
    if ~all(isfinite(values)) || any(values <= 0); continue; end
    if ~isfield(candidate, 'units') || isempty(candidate.units)
        candidate.units = 'um';
    end
    pixSize = candidate;
    return;
end

end
