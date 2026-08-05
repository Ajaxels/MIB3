function accepted = askImportMode(obj, inputPath)
% ASKIMPORTMODE - Ask how much of an acquisition's own stitch to reuse.
%
% Syntax:
%   .. code-block:: matlab
%
%      accepted = obj.askImportMode(inputPath)
%
% Called from :meth:`controllers.Stitching.selectInputBtn_Callback` when the
% *Position file* source is pointed at a file that can carry a finished stitch -
% a Fibics Atlas ``.ve-mif`` or a SerialEM ``.mdoc`` - rather than a position
% text file.
%
% Both formats record the same three stages of the same job: a nominal placement,
% the pairwise seam measurements taken from it, and the final solved positions.
% Only where they are written differs - Atlas puts each stage in its own sidecar
% file, SerialEM keeps all three in the one ``.mdoc``. The choice offered is
% therefore identical, and only the WORDING is vendor-specific.
%
% Both later stages are worth having: MIB can solve from the recorded
% measurements without re-registering a pixel, or take the finished placement and
% go straight to fusing. Neither is worth having blindly, though - under
% difficult imaging conditions the stage positions a vendor works from can be
% wrong enough that its stitch is bad while the tiles themselves are perfectly
% stitchable. So the choice is the user's, and *Nominal grid only* (register
% everything from scratch) is always offered.
%
% The answer is written into ``BatchOpt.LayoutImport``, which
% :meth:`controllers.Stitching.buildLayoutFromBatchOpt` reads when it builds the
% layout. Nothing is asked when the file carries no stitch (there is nothing to
% choose) or when the tool has no window (batch runs take the BatchOpt value as
% given).
%
% Input Arguments:
%   - **inputPath** - [char] full path to the ``.ve-mif`` / ``.mdoc`` about to be
%     opened
%
% Output Arguments:
%   - **accepted** - [logical] ``false`` only when the user cancelled the dialog;
%     the caller should then abandon the whole selection
%
% See also utils.stitch.findAtlasSidecars, utils.stitch.findMdocSidecar,
% utils.stitch.buildLayoutAtlas, utils.stitch.buildLayoutMdoc

accepted = true;
if isempty(obj.view); return; end                 % batch/headless: BatchOpt decides

descriptor = describeAvailableImport(inputPath);
if isempty(descriptor.vendorName); return; end    % not a format that carries a stitch

if ~descriptor.hasEdges && ~descriptor.hasPositions
    % Nothing was stitched - the nominal placement is all there is.
    obj.BatchOpt.LayoutImport{1} = 'Nominal grid only';
    return;
end

% Buttons carry the BatchOpt value they stand for, because the wording has to
% follow both the vendor and what is actually on disk: with no measurements the
% fullest import is a placement without them (the layout builder synthesises the
% matching edges), and calling that button "seams + positions" would be a lie.
gridOnlyValue = 'Nominal grid only';
edgesValue    = 'Vendor seam measurements';
bothValue     = 'Vendor seams + solved positions';

buttonLabels = {gridOnlyValue};
buttonValues = {gridOnlyValue};
explanations = { sprintf([ ...
    '%s - ignore what is recorded and start from the %s grid noted at\n' ...
    'acquisition. MIB measures every overlap and solves the %s itself. Use\n' ...
    'this when %s''s own stitch came out wrong.'], ...
    gridOnlyValue, descriptor.gridNoun, descriptor.mosaicNoun, descriptor.vendorName) };

if descriptor.hasEdges
    buttonLabels{end+1} = sprintf('%s seam measurements', descriptor.vendorName);
    buttonValues{end+1} = edgesValue;
    explanations{end+1} = sprintf([ ...
        '%s - take %s''s pairwise seam shifts and let MIB\n' ...
        'run its global solve on them. No image registration is repeated.'], ...
        buttonLabels{end}, descriptor.vendorName);
end
if descriptor.hasPositions && descriptor.hasEdges
    buttonLabels{end+1} = sprintf('%s seams + solved positions', descriptor.vendorName);
    buttonValues{end+1} = bothValue;
    explanations{end+1} = sprintf([ ...
        '%s - also take %s''s final tile placement,\n' ...
        'so the %s is ready as it stands: press Stitch to fuse it with nothing\n' ...
        'recomputed.'], buttonLabels{end}, descriptor.vendorName, descriptor.mosaicNoun);
elseif descriptor.hasPositions
    buttonLabels{end+1} = sprintf('%s solved positions', descriptor.vendorName);
    buttonValues{end+1} = bothValue;
    explanations{end+1} = sprintf([ ...
        '%s - take %s''s final tile placement, so the\n' ...
        '%s is ready as it stands: press Stitch to fuse it with nothing recomputed.'], ...
        buttonLabels{end}, descriptor.vendorName, descriptor.mosaicNoun);
end

question = sprintf('%s has already stitched this %s:\n\n%s\n\n%s', ...
    descriptor.vendorName, descriptor.mosaicNoun, ...
    strjoin(descriptor.foundLines, newline), strjoin(explanations, sprintf('\n\n')));

% Default to the current BatchOpt value when it is still on the menu (so a
% repeated import keeps the user's habit), otherwise to the fullest import.
defaultIndex = find(strcmp(buttonValues, obj.BatchOpt.LayoutImport{1}), 1, 'last');
if isempty(defaultIndex); defaultIndex = numel(buttonLabels); end

dlgOptions.WindowWidth  = 680;
dlgOptions.WindowHeight = 400;
dlgOptions.Icon         = 'puffin_question';
selection = utils.dlgs.inputQuestDlg(obj.view.gui, question, ...
    sprintf('%s stitching results found', descriptor.vendorName), ...
    buttonLabels{:}, buttonLabels{defaultIndex}, dlgOptions);

selectedIndex = find(strcmp(buttonLabels, selection), 1);
if isempty(selectedIndex)
    accepted = false;      % dialog closed without choosing
    return;
end
obj.BatchOpt.LayoutImport{1} = buttonValues{selectedIndex};

end

% =========================================================================
function descriptor = describeAvailableImport(inputPath)
% DESCRIBEAVAILABLEIMPORT - Which vendor wrote this, and what did it finish?
%
% ``.vendorName`` empty means the path is not a format that can carry a stitch,
% and the caller stands down. Everything else is presentation: the nouns that
% make the dialog read naturally, and one summary line per recorded stage.

descriptor = struct('vendorName', '', 'mosaicNoun', 'mosaic', 'gridNoun', 'stage', ...
    'hasEdges', false, 'hasPositions', false, 'foundLines', {{}});

atlasSidecars = utils.stitch.findAtlasSidecars(inputPath);
mdocSidecar   = utils.stitch.findMdocSidecar(inputPath);

if ~isempty(mdocSidecar.mdocPath)
    % SerialEM keeps all three stages inside the one .mdoc, so the summary names
    % the KEYS that were found rather than sidecar files.
    descriptor.vendorName   = 'SerialEM';
    descriptor.mosaicNoun   = 'montage';
    descriptor.gridNoun     = 'piece';
    descriptor.hasEdges     = mdocSidecar.numEdges > 0;
    descriptor.hasPositions = mdocSidecar.numAligned > 0;

    [~, mdocName, mdocExt] = fileparts(mdocSidecar.mdocPath);
    foundLines = {};
    if descriptor.hasEdges
        foundLines{end+1} = sprintf('    %s%s - %s (XedgeDxy / YedgeDxy)', ...
            mdocName, mdocExt, describeCount(mdocSidecar.numEdges, 'measured seam'));
    end
    if descriptor.hasPositions
        foundLines{end+1} = sprintf('    %s%s - %s (AlignedPieceCoords)', ...
            mdocName, mdocExt, describeCount(mdocSidecar.numAligned, 'solved tile position'));
    end
    descriptor.foundLines = foundLines;
    return;
end

if ~isempty(atlasSidecars.mifPath)
    descriptor.vendorName   = 'Atlas';
    descriptor.hasEdges     = ~isempty(atlasSidecars.tiePath);
    descriptor.hasPositions = ~isempty(atlasSidecars.updatesPath);

    foundLines = {};
    if descriptor.hasEdges
        [~, tieName, tieExt] = fileparts(atlasSidecars.tiePath);
        foundLines{end+1} = sprintf('    %s%s - %s', tieName, tieExt, ...
            describeCount(countXmlElements(atlasSidecars.tiePath, 'Tie'), 'measured seam'));
    end
    if descriptor.hasPositions
        [~, updatesName, updatesExt] = fileparts(atlasSidecars.updatesPath);
        foundLines{end+1} = sprintf('    %s%s - %s', updatesName, updatesExt, ...
            describeCount(countXmlElements(atlasSidecars.updatesPath, 'Tile'), 'solved tile position'));
    end
    descriptor.foundLines = foundLines;
end

end

% =========================================================================
function elementCount = countXmlElements(filePath, tagName)
% COUNTXMLELEMENTS - How many ``<tagName>`` elements a file holds; NaN on failure.
% A plain text count, not a parse: this only feeds the dialog's summary line, and
% it must never be the reason an otherwise valid import cannot be offered.
elementCount = NaN;
try
    fileText = fileread(filePath);
    elementCount = numel(strfind(fileText, ['<', tagName, '>'])) + ...
                   numel(strfind(fileText, ['<', tagName, ' ']));
catch
end
end

% =========================================================================
function text = describeCount(elementCount, noun)
% DESCRIBECOUNT - "4 measured seams" / "a measured seam" / "contents" when unknown.
if ~isfinite(elementCount)
    text = sprintf('%ss', noun);
elseif elementCount == 1
    text = sprintf('1 %s', noun);
else
    text = sprintf('%d %ss', elementCount, noun);
end
end
