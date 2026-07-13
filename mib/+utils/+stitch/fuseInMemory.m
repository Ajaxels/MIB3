function imgOut = fuseInMemory(layout, canvas, options)
% FUSEINMEMORY - Fuse all tiles into a resident mosaic array.
%
% Syntax:
%   .. code-block:: matlab
%
%      imgOut = utils.stitch.fuseInMemory(layout, canvas)
%      imgOut = utils.stitch.fuseInMemory(layout, canvas, options)
%
% Allocates the full ``[H W Z C T]`` mosaic of ``canvas.dataClass`` (initialised
% to ``options.background``) and fills it by compositing every tile at its planned
% placement, one output Z-slice at a time via
% :func:`utils.stitch.fuseSliceComposite`, so the transient blending accumulators
% stay bounded to a single slice even though the final array is resident. This is
% the fast path for mosaics that fit in RAM; larger jobs use
% :func:`utils.stitch.fuseStreaming`.
%
% Input Arguments:
%   - **layout** — [struct array] tile layout.
%   - **canvas** — [struct] from :func:`utils.stitch.planCanvas`.
%   - **options** *(optional)* — struct with fields:
%
%     - ``.blendMode`` — [char] ``'Feather'`` (default) | ``'Average'`` | ``'Max'`` | ``'Overwrite'``
%     - ``.background`` — [double] background fill value (default: ``0``)
%     - ``.marginPx`` — [double] feather margin (default: derived from tile size)
%     - ``.cacheSizeBytes`` — [double] LRU tile-cache budget (default: ``2*1024^3``)
%     - ``.readerFcn`` — [function_handle] reuse an existing tile reader (optional)
%
% Output Arguments:
%   - **imgOut** — [H x W x Z x C x T] fused mosaic of class ``canvas.dataClass``.
%
% **Example** — feather-blend a solved layout:
%
%   .. code-block:: matlab
%
%      opts.blendMode = 'Feather';
%      imgOut = utils.stitch.fuseInMemory(layout, canvas, opts);

if nargin < 3; options = struct(); end
if ~isfield(options, 'blendMode');      options.blendMode = 'Feather'; end
if ~isfield(options, 'background');     options.background = 0; end
if ~isfield(options, 'cacheSizeBytes'); options.cacheSizeBytes = 2 * 1024^3; end

if isfield(options, 'readerFcn') && ~isempty(options.readerFcn)
    readerFcn = options.readerFcn;
else
    readerFcn = utils.stitch.makeTileReader(layout, ...
        struct('cacheSizeBytes', options.cacheSizeBytes));
end

H = canvas.size(1);
W = canvas.size(2);
Z = canvas.size(3);
C = canvas.size(4);
T = canvas.size(5);
dataClass = canvas.dataClass;

imgOut = cast(options.background, dataClass) + zeros(H, W, Z, C, T, dataClass);

for t = 1:T
    for z = 1:Z
        outSlice = utils.stitch.fuseSliceComposite(layout, canvas, z, t, readerFcn, options);
        imgOut(:, :, z, :, t) = reshape(outSlice, H, W, 1, C);
    end
end
end
