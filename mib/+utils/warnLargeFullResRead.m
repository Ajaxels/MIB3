function warnLargeFullResRead(height, width, budgetMegapixels)
% WARNLARGEFULLRESREAD - Non-blocking warning for an oversized full-resolution read.
%
% Syntax:
%   .. code-block:: matlab
%
%      utils.warnLargeFullResRead(height, width)
%      utils.warnLargeFullResRead(height, width, budgetMegapixels)
%
% WSI safety net (warn-only). Some editing tools, when used without a footprint
% bound (e.g. Magic Wand / Region Growing with radius = 0), read a whole
% full-resolution slice of a pyramidal (BigData / Virtual) dataset. On a
% gigapixel slide that can be slow or exhaust memory. This helper emits a
% **non-blocking** ``warning`` (it never blocks the operation, per the agreed
% "warn only" policy) when the read would exceed a megapixel budget. It is
% throttled to once per MATLAB session so it does not spam the console during
% repeated strokes.
%
% Input Arguments:
%   - **height** — [numeric] full-resolution slice height (pixels)
%   - **width** — [numeric] full-resolution slice width (pixels)
%   - **budgetMegapixels** — *(optional)* [numeric] threshold in megapixels above
%     which to warn; default ``256``
%
% Output Arguments:
%   (none)
%
% **Example** — guard a radius-less flood fill on a pyramidal dataset:
%
%   .. code-block:: matlab
%
%      if any(obj.mibModel.I{id}.datasetType(1) == ['V' 'B'])
%          utils.warnLargeFullResRead(obj.mibModel.I{id}.image.height, ...
%              obj.mibModel.I{id}.image.width);
%      end

persistent alreadyWarned
if isempty(alreadyWarned); alreadyWarned = false; end
if nargin < 3 || isempty(budgetMegapixels); budgetMegapixels = 256; end

megapixels = double(height) * double(width) / 1e6;

if megapixels > budgetMegapixels && ~alreadyWarned
    alreadyWarned = true;   % once per session — avoid console spam during strokes
    warning('MIB:BigData:largeFullResRead', ...
        ['A full-resolution read of ~%.0f megapixels (%d x %d) was requested on a ' ...
         'pyramidal dataset.\nOn very large (WSI / gigapixel) slides this can be slow ' ...
         'or exhaust memory. Prefer a radius-limited tool, zoom in, or pick a coarser ' ...
         'pyramid level.\n(This warning is shown once per session.)'], ...
        megapixels, width, height);
end
end
