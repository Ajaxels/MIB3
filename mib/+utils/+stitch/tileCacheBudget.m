function budgetBytes = tileCacheBudget(layout, options)
% TILECACHEBUDGET - LRU tile-cache size that fits this layout and this machine.
%
% Syntax:
%   .. code-block:: matlab
%
%      budgetBytes = utils.stitch.tileCacheBudget(layout)
%      budgetBytes = utils.stitch.tileCacheBudget(layout, options)
%
% The default budget of :func:`utils.stitch.makeTileReader`. A fixed 2 GB was
% fine for ordinary tiles and useless for large ones: a 24000x24000 uint16 tile
% is 1.15 GB, so two of them do not fit and the seam inspector re-decoded BOTH
% tiles of a pair every time the user stepped back to a seam they had already
% looked at (measured: 17.9 s per revisit, versus 0.00 s once the pair stays
% resident). Sizing the budget to the layout is what turns a repeated review
% loop into a one-off cost.
%
% The budget is an upper bound, not an allocation - the cache only ever holds
% tiles that were actually read - so asking for more than the tiles need is
% harmless, and asking for more than the machine has is not: hence the cap at a
% fraction of the memory MATLAB reports as available.
%
% .. important::
%    Callers that run several readers AT ONCE must divide it themselves -
%    :func:`utils.stitch.measureAllPairs` keeps a fixed per-worker budget for its
%    ``parfor`` path, where every worker builds its own cache.
%
% Input Arguments:
%   - **layout** - [struct array] tile layout (``.tileSize``, ``.dataClass``).
%   - **options** *(optional)* - struct with fields:
%
%     - ``.minBytes`` - [double] never return less than this, so the budget can
%       only ever grow relative to the old fixed default (default: ``2*1024^3``)
%     - ``.memoryFraction`` - [double] share of the available memory the cache
%       may claim (default: ``0.5``, leaving room for the mosaic being built)
%     - ``.divisor`` - [double] number of readers that will exist at once
%       (default: ``1``)
%
% Output Arguments:
%   - **budgetBytes** - [double] cache budget in bytes.
%
% **Example** - a reader that can hold the whole mosaic:
%
%   .. code-block:: matlab
%
%      readerFcn = utils.stitch.makeTileReader(layout, ...
%          struct('cacheSizeBytes', utils.stitch.tileCacheBudget(layout)));
%
% See also utils.stitch.makeTileReader

if nargin < 2; options = struct(); end
if ~isfield(options, 'minBytes');       options.minBytes = 2 * 1024^3; end
if ~isfield(options, 'memoryFraction'); options.memoryFraction = 0.5; end
if ~isfield(options, 'divisor');        options.divisor = 1; end

budgetBytes = options.minBytes;
if isempty(layout); return; end

% What holding EVERY tile at once would cost.
layoutBytes = 0;
for tileIdx = 1:numel(layout)
    tileSize = layout(tileIdx).tileSize;
    if isempty(tileSize); continue; end
    if isfield(layout, 'dataClass') && ~isempty(layout(tileIdx).dataClass)
        dataClass = layout(tileIdx).dataClass;
    else
        dataClass = 'uint16';
    end
    layoutBytes = layoutBytes + prod(double(tileSize)) * bytesPerElement(dataClass);
end
if layoutBytes <= 0; return; end

availableBytes = availableMemory();
if isempty(availableBytes)
    % No way to ask (non-Windows, or `memory` unavailable): keep the old fixed
    % default rather than guess at a machine we cannot see.
    return;
end

allowance = options.memoryFraction * availableBytes / max(1, options.divisor);
budgetBytes = max(options.minBytes, min(layoutBytes, allowance));

end

% =========================================================================
function nBytes = bytesPerElement(className)
switch className
    case {'uint8', 'int8', 'logical'};   nBytes = 1;
    case {'uint16', 'int16'};            nBytes = 2;
    case {'uint32', 'int32', 'single'};  nBytes = 4;
    case {'uint64', 'int64', 'double'};  nBytes = 8;
    otherwise;                           nBytes = 8;
end
end

% =========================================================================
function availableBytes = availableMemory()
% AVAILABLEMEMORY - Bytes MATLAB reports it could still allocate, or [] when the
% platform cannot say (`memory` is Windows-only).
availableBytes = [];
try
    memoryInfo = memory;
    availableBytes = memoryInfo.MemAvailableAllArrays;
catch
    % leave empty - the caller falls back to its fixed default
end
end
