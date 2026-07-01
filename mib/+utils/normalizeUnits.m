function unitsOut = normalizeUnits(unitsIn)
% NORMALIZEUNITS - Map a physical-unit string to MIB's canonical short code.
%
% MIB stores spatial units as the short codes ``'m'``, ``'cm'``, ``'mm'``,
% ``'um'``, ``'nm'`` (plus ``'pixels'`` for unscaled data). Datasets imported
% from OME-Zarr / BigData, however, carry the long OME spellings
% (``'micrometers'``, ``'nanometers'``, ...). Several savers
% (``utils.calculateResolution``, ``io.BioFormats.mibImage2ometiff``) ``switch``
% on the short code and silently fall back — or, in the OME-TIFF case, error on
% an undefined scale factor — when handed a long spelling. Run the units string
% through this helper first so every caller sees a canonical code.
%
% Syntax:
%   .. code-block:: matlab
%
%      unitsOut = utils.normalizeUnits(unitsIn)
%
% Input Arguments:
%   - **unitsIn** — [char | string] a physical-unit string, e.g. ``'micrometers'``,
%     ``'um'``, ``'nm'``, ``'pixels'``.
%
% Output Arguments:
%   - **unitsOut** — [char] the canonical short code (``'m'`` | ``'cm'`` | ``'mm'``
%     | ``'um'`` | ``'nm'`` | ``'pixels'``). Unrecognised strings are returned
%     lower-cased and trimmed but otherwise unchanged, so callers keep their own
%     fallback behaviour.
%
% Usage:
%   **Example 1** — long form to short code
%
%   .. code-block:: matlab
%
%      u = utils.normalizeUnits('micrometers');   % 'um'
%
% See also: utils.calculateResolution, io.BioFormats.mibImage2ometiff

unitsOut = lower(strtrim(char(unitsIn)));
switch unitsOut
    case {'m', 'meter', 'meters', 'metre', 'metres'}
        unitsOut = 'm';
    case {'cm', 'centimeter', 'centimeters', 'centimetre', 'centimetres'}
        unitsOut = 'cm';
    case {'mm', 'millimeter', 'millimeters', 'millimetre', 'millimetres'}
        unitsOut = 'mm';
    case {'um', 'micrometer', 'micrometers', 'micrometre', 'micrometres', ...
          'micron', 'microns'}
        unitsOut = 'um';
    case {'nm', 'nanometer', 'nanometers', 'nanometre', 'nanometres'}
        unitsOut = 'nm';
    case {'pixel', 'pixels', 'px'}
        unitsOut = 'pixels';
    % otherwise: leave the (lower-cased, trimmed) string unchanged
end
end
