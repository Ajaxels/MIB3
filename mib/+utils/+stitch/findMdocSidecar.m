function sidecar = findMdocSidecar(montageFilePath)
% FINDMDOCSIDECAR - Resolve a SerialEM montage's .mdoc and image container from either one.
%
% Syntax:
%   .. code-block:: matlab
%
%      sidecar = utils.stitch.findMdocSidecar(montageFilePath)
%
% A SerialEM montage is TWO files: an MRC stack holding every tile as a slice,
% and a plain-text ``.mdoc`` next to it recording where those slices go. The
% ``.mdoc`` is named after the image it describes (``Cell1.mrc`` →
% ``Cell1.mrc.mdoc``), so either file identifies the pair and a user picking one
% of them means the same montage. Whatever is passed, ``.mdocPath`` comes back
% pointing at the text file - the one that has to be parsed - and ``.imagePath``
% at the container the tiles are read from.
%
% ``.mdocPath`` doubles as the "is this a SerialEM montage at all?" test: a path
% whose extension is neither ``.mdoc`` nor an MRC image extension yields an
% all-empty struct rather than an error, so a caller can branch on it exactly as
% it branches on :func:`utils.stitch.findAtlasSidecars`.
%
% .. important::
%    A non-empty ``.mdocPath`` does NOT mean the file describes a mosaic -
%    SerialEM writes the same format for tilt series and single-shot acquisitions,
%    which have no ``PieceCoordinates`` and are not stitchable. ``.isMontage``
%    is the flag for that, and it is reported rather than raised so the caller can
%    still route the file to :func:`utils.stitch.buildLayoutMdoc` and get one clear
%    error instead of a confusing parse of the wrong file kind.
%
% The three counts describe how far SerialEM got with its own stitch, mirroring
% the ``.ve-tie`` / ``.ve-updates`` presence checks on the Atlas side: they let a
% caller offer only the import modes the file can actually honour.
%
% Input Arguments:
%   - **montageFilePath** - [char] full path to either the ``.mdoc`` or the MRC
%     image (``.mrc``, ``.st``, ``.rec``, ``.ali``, ``.preali``, ``.pre``).
%
% Output Arguments:
%   - **sidecar** - struct with fields:
%
%     - ``.mdocPath`` - [char] full path to the ``.mdoc``; ``''`` when the input
%       is not a SerialEM montage file or the ``.mdoc`` is missing
%     - ``.imagePath`` - [char] full path to the image container; ``''`` if absent
%     - ``.isMrcImage`` - [logical] the input path is an MRC IMAGE (by extension),
%       whatever came of the lookup. Lets a caller tell "an MRC whose ``.mdoc`` is
%       missing" (worth an explanatory error) from "not a SerialEM file at all"
%       (fall through to the next format) - the two are otherwise identical, since
%       both leave ``.mdocPath`` empty.
%     - ``.isMontage`` - [logical] the ``.mdoc`` describes a mosaic (it declares
%       ``Montage = 1`` or carries ``PieceCoordinates``)
%     - ``.numTiles`` - [double] tiles the ``.mdoc`` places
%     - ``.numEdges`` - [double] measured seams (``XedgeDxy`` + ``YedgeDxy``)
%     - ``.numAligned`` - [double] tiles with a solved ``AlignedPieceCoords``
%
% **Example** - branch on whether a picked file is a SerialEM montage:
%
%   .. code-block:: matlab
%
%      sidecar = utils.stitch.findMdocSidecar(selectedFile);
%      if ~isempty(sidecar.mdocPath)
%          layout = utils.stitch.buildLayoutMdoc(sidecar.mdocPath);
%      end
%
% See also utils.stitch.buildLayoutMdoc, utils.stitch.findAtlasSidecars

arguments
    montageFilePath (1,:) char
end

sidecar.mdocPath   = '';
sidecar.imagePath  = '';
sidecar.isMrcImage = false;
sidecar.isMontage  = false;
sidecar.numTiles   = 0;
sidecar.numEdges   = 0;
sidecar.numAligned = 0;

mrcExtensions = {'.mrc', '.st', '.rec', '.ali', '.preali', '.pre', '.mrcs'};

[montageFolder, montageBaseName, extension] = fileparts(montageFilePath);
extension = lower(extension);
sidecar.isMrcImage = ismember(extension, mrcExtensions);

if strcmp(extension, '.mdoc')
    if ~isfile(montageFilePath); return; end
    sidecar.mdocPath = montageFilePath;
    % 'Cell1.mrc.mdoc' -> base name 'Cell1.mrc', which IS the image.
    sidecar.imagePath = resolveImageFile(montageFolder, montageBaseName, mrcExtensions);
elseif ismember(extension, mrcExtensions)
    if ~isfile(montageFilePath); return; end
    % SerialEM appends .mdoc to the WHOLE image name, extension included.
    mdocCandidate = [montageFilePath, '.mdoc'];
    if ~isfile(mdocCandidate)
        % Tolerate the shorter form some tools write ('Cell1.mdoc').
        mdocCandidate = fullfile(montageFolder, [montageBaseName, '.mdoc']);
    end
    if ~isfile(mdocCandidate); return; end
    sidecar.mdocPath  = mdocCandidate;
    sidecar.imagePath = montageFilePath;
else
    return;   % not a SerialEM montage file - the caller treats it as whatever else it is
end

% ---- What the .mdoc says it holds -------------------------------------
% A plain text scan, not a parse: this only decides which import modes are on
% offer, and it must never be the reason a valid montage cannot be opened.
try
    mdocText = fileread(sidecar.mdocPath);
catch
    return;
end

sidecar.numTiles   = countKey(mdocText, 'PieceCoordinates');
sidecar.numEdges   = countKey(mdocText, 'XedgeDxy') + countKey(mdocText, 'YedgeDxy');
sidecar.numAligned = countKey(mdocText, 'AlignedPieceCoords');
sidecar.isMontage  = sidecar.numTiles > 0 || ...
    ~isempty(regexp(mdocText, '(?m)^\s*Montage\s*=\s*1\s*$', 'once'));

% The image recorded inside the file is a last resort: it names the acquisition
% machine's file, so only its BASE NAME is usable where the data is analysed.
if isempty(sidecar.imagePath)
    recordedImage = regexp(mdocText, '(?m)^\s*ImageFile\s*=\s*(.+?)\s*$', 'tokens', 'once');
    if ~isempty(recordedImage)
        [~, recordedBase, recordedExt] = fileparts(strrep(recordedImage{1}, '\', filesep));
        localCandidate = fullfile(montageFolder, [recordedBase, recordedExt]);
        if isfile(localCandidate); sidecar.imagePath = localCandidate; end
    end
end

end

% =========================================================================
function imagePath = resolveImageFile(montageFolder, strippedName, mrcExtensions)
% RESOLVEIMAGEFILE - Locate the container a '<image>.mdoc' name points at.
% 'Cell1.mrc.mdoc' strips to 'Cell1.mrc' (already a full image name); 'Cell1.mdoc'
% strips to 'Cell1', which needs an extension trying on.
imagePath = '';
strippedCandidate = fullfile(montageFolder, strippedName);
if isfile(strippedCandidate)
    imagePath = strippedCandidate;
    return;
end
for extIdx = 1:numel(mrcExtensions)
    candidate = fullfile(montageFolder, [strippedName, mrcExtensions{extIdx}]);
    if isfile(candidate)
        imagePath = candidate;
        return;
    end
end
end

% =========================================================================
function keyCount = countKey(mdocText, keyName)
% COUNTKEY - How many times a 'Key = value' line appears in the .mdoc.
keyCount = numel(regexp(mdocText, ['(?m)^\s*', keyName, '\s*='], 'start'));
end
