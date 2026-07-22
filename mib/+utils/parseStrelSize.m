function se_size = parseStrelSize(strelSizeStr, is3D, pixSizeX, pixSizeZ)
% PARSESTRELSIZE - Parse the StrelSize string into a two-element radius vector.
%
% Syntax:
%   .. code-block:: matlab
%
%       se_size = utils.parseStrelSize(strelSizeStr, is3D, pixSizeX, pixSizeZ)
%
% Shared by ``MibModel.dilateImage``/``erodeImage`` and the Selection-panel
% controllers so the structuring-element geometry (and therefore the isotropy
% test that drives the bwdist fast path) is computed identically everywhere.
%
% A single value expands to an isotropic in-plane disk; in 3D the Z radius is
% derived from the voxel aspect ratio. Two space-separated values give the XY
% radius and the Z radius (3D) or X radius (2D anisotropic) explicitly.
%
% Input Arguments:
%   - **strelSizeStr** — char, the ``StrelSize`` value, e.g. ``'5'`` or ``'5 2'``
%   - **is3D** — logical, true for a 3D (volumetric) element
%   - **pixSizeX** — *(optional)* numeric, X voxel size (only used for a single
%     value in 3D); default 1
%   - **pixSizeZ** — *(optional)* numeric, Z voxel size (only used for a single
%     value in 3D); default 1
%
% Output Arguments:
%   - **se_size** — [1x2 double] ``[XYradius, Zradius]`` (3D) or ``[Yradius, Xradius]`` (2D),
%     clipped at 0
%

% Updates
%

if nargin < 3 || isempty(pixSizeX); pixSizeX = 1; end
if nargin < 4 || isempty(pixSizeZ); pixSizeZ = 1; end

seSize = str2num(strelSizeStr); %#ok<ST2NM>

if numel(seSize) == 2
    se_size = [seSize(1), seSize(2)];
else
    if is3D
        se_size(1) = seSize;
        se_size(2) = max(round(seSize * pixSizeX / pixSizeZ), 1);
    else
        se_size = [seSize, seSize];
    end
end
se_size = max(se_size, 0);
end
