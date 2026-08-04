function sidecars = findAtlasSidecars(atlasFilePath)
% FINDATLASSIDECARS - Resolve a Fibics Atlas mosaic's three XML files from any one of them.
%
% Syntax:
%   .. code-block:: matlab
%
%      sidecars = utils.stitch.findAtlasSidecars(atlasFilePath)
%
% A Fibics Atlas mosaic folder holds up to three XML files that share one base
% name and describe three successive stages of the same stitch:
%
%   - ``MosaicInfo_<name>.ve-mif`` — the acquisition record: per-tile grid index
%     and NOMINAL stage position (the rough placement);
%   - ``MosaicInfo_<name>.ve-tie`` — Atlas's pairwise seam measurements;
%   - ``MosaicInfo_<name>.ve-updates`` — Atlas's FINAL solved tile positions.
%
% The last two are written only after the mosaic has been stitched in Atlas, so
% either may be missing. This helper reports which are present, letting the
% caller offer only the import modes that can actually be honoured.
%
% **Any of the three may be passed in** — they sit side by side with near-identical
% names and a user picking one of them means the same mosaic either way. Whatever
% is passed, ``.mifPath`` comes back pointing at the acquisition record, which is
% the file everything else is read relative to.
%
% ``.mifPath`` doubles as the "is this an Atlas input at all?" test: a path whose
% extension is none of the three (a plain position ``.txt``, an image, …) yields
% an all-empty struct rather than an error, so a caller can branch on it.
%
% Input Arguments:
%   - **atlasFilePath** — [char] full path to any of the mosaic's three XML files.
%
% Output Arguments:
%   - **sidecars** — struct with fields:
%
%     - ``.mifPath`` — [char] full path to the ``.ve-mif``, ``''`` if the input is
%       not an Atlas file or the ``.ve-mif`` itself is missing
%     - ``.tiePath`` — [char] full path to the ``.ve-tie`` file, ``''`` if absent
%     - ``.updatesPath`` — [char] full path to the ``.ve-updates`` file, ``''`` if absent
%
% **Example** — branch on whether a picked position file is really an Atlas mosaic:
%
%   .. code-block:: matlab
%
%      sidecars = utils.stitch.findAtlasSidecars(selectedFile);
%      if ~isempty(sidecars.mifPath)
%          layout = utils.stitch.buildLayoutAtlas(sidecars.mifPath);
%      else
%          layout = utils.stitch.buildLayoutPositionFile(selectedFile);
%      end
%
% See also utils.stitch.buildLayoutAtlas, utils.stitch.buildLayoutPositionFile

arguments
    atlasFilePath (1,:) char
end

sidecars.mifPath     = '';
sidecars.tiePath     = '';
sidecars.updatesPath = '';

[mosaicFolder, mosaicBaseName, extension] = fileparts(atlasFilePath);
if ~ismember(lower(extension), {'.ve-mif', '.ve-tie', '.ve-updates'})
    return;   % not an Atlas file — the caller treats it as whatever else it is
end

mifCandidate = fullfile(mosaicFolder, [mosaicBaseName, '.ve-mif']);
if isfile(mifCandidate); sidecars.mifPath = mifCandidate; end

tieCandidate = fullfile(mosaicFolder, [mosaicBaseName, '.ve-tie']);
if isfile(tieCandidate); sidecars.tiePath = tieCandidate; end

updatesCandidate = fullfile(mosaicFolder, [mosaicBaseName, '.ve-updates']);
if isfile(updatesCandidate); sidecars.updatesPath = updatesCandidate; end

end
