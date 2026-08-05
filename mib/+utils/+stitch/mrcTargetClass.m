function [targetClass, needsScaling] = mrcTargetClass(mrcMode)
% MRCTARGETCLASS - Pixel class a stitched MRC montage is read into, from the MRC mode.
%
% Syntax:
%   .. code-block:: matlab
%
%      [targetClass, needsScaling] = utils.stitch.mrcTargetClass(mrcMode)
%
% MRC stores pixels as unsigned bytes, SIGNED 16-bit integers or 32-bit floats,
% while MIB works in unsigned integer classes only. This function is the single
% place that decides which class a montage's tiles become, so the two callers -
% :func:`utils.stitch.buildLayoutMdoc` (which records ``layout.dataClass``, and
% therefore what :func:`utils.stitch.planCanvas` allocates) and
% :func:`utils.stitch.makeTileReader` (which does the actual conversion) - cannot
% drift apart.
%
% **Why every scaled mode lands on uint16 rather than the widest class that
% fits.** :class:`io.loaders.ImodLoader` picks the target class from the header's
% density RANGE, which sends a typical float montage to ``uint32`` and leaves MIB
% to stretch it to ``uint16`` on load. A mosaic is built once and kept, so the
% intermediate ``uint32`` would only double the canvas and every fused slice for
% a range that is going to be squeezed anyway.
%
% .. important::
%    Scaling uses the range from the FILE HEADER, never per-slice statistics.
%    Every tile of a montage is a slice of one container, so a per-slice range
%    would give each tile its own intensity scale - injecting exactly the
%    tile-to-tile mismatch a stitch is supposed to be free of.
%
% Input Arguments:
%   - **mrcMode** - [double] MRC ``mode`` field: ``0`` = unsigned byte,
%     ``1`` = int16, ``2`` = float32, ``6`` = uint16 (``3``/``4`` complex and
%     ``16`` RGB are treated as scaled modes).
%
% Output Arguments:
%   - **targetClass** - [char] MATLAB class the tiles are returned as.
%   - **needsScaling** - [logical] ``true`` when pixels must be mapped from the
%     header's ``[minDensity maxDensity]`` onto the full range of ``targetClass``;
%     ``false`` when the stored values are already unsigned and pass through.
%
% **Example** - allocate a canvas for a float32 montage:
%
%   .. code-block:: matlab
%
%      [tileClass, mustScale] = utils.stitch.mrcTargetClass(2);
%      % tileClass = 'uint16', mustScale = true
%
% See also utils.stitch.buildLayoutMdoc, utils.stitch.makeTileReader

arguments
    mrcMode (1,1) double
end

switch mrcMode
    case 0      % unsigned byte - already what MIB wants
        targetClass  = 'uint8';
        needsScaling = false;
    case 6      % unsigned 16-bit - already what MIB wants
        targetClass  = 'uint16';
        needsScaling = false;
    otherwise   % int16, float32, and the complex/RGB modes
        targetClass  = 'uint16';
        needsScaling = true;
end

end
