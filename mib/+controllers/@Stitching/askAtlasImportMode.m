function accepted = askAtlasImportMode(obj, veMifPath)
% ASKATLASIMPORTMODE - Ask how much of an Atlas mosaic's own stitch to reuse.
%
% Syntax:
%   .. code-block:: matlab
%
%      accepted = obj.askAtlasImportMode(veMifPath)
%
% Called from :meth:`controllers.Stitching.selectInputBtn_Callback` when the
% *Position file* source is pointed at a Fibics Atlas ``.ve-mif`` rather than a
% position text file.
%
% A Fibics Atlas mosaic that has already been stitched in Atlas carries its
% result in two sidecar files next to the ``.ve-mif`` acquisition record — the
% pairwise seam measurements (``.ve-tie``) and the final tile placement
% (``.ve-updates``). Both are worth having: MIB can solve from Atlas's
% measurements without re-registering a pixel, or take the finished placement and
% go straight to fusing.
%
% Neither is worth having blindly, though. Under some imaging conditions the
% stage positions Atlas works from are wrong enough that its stitch is bad while
% the tiles themselves are perfectly stitchable — so the choice is the user's,
% and *Nominal grid only* (register everything from scratch) is always offered.
%
% The answer is written into ``BatchOpt.AtlasImport``, which
% :meth:`controllers.Stitching.buildLayoutFromBatchOpt` reads when it builds the
% layout. Nothing is asked when neither sidecar exists (there is nothing to
% choose) or when the tool has no window (batch runs take the BatchOpt value as
% given).
%
% Input Arguments:
%   - **veMifPath** — [char] full path to the ``.ve-mif`` about to be opened
%
% Output Arguments:
%   - **accepted** — [logical] ``false`` only when the user cancelled the dialog;
%     the caller should then abandon the whole selection
%
% See also utils.stitch.findAtlasSidecars, utils.stitch.buildLayoutAtlas

accepted = true;
if isempty(obj.view); return; end                 % batch/headless: BatchOpt decides

sidecars = utils.stitch.findAtlasSidecars(veMifPath);
hasTies    = ~isempty(sidecars.tiePath);
hasUpdates = ~isempty(sidecars.updatesPath);

if ~hasTies && ~hasUpdates
    % Nothing was stitched in Atlas — the nominal grid is all there is.
    obj.BatchOpt.AtlasImport{1} = 'Nominal grid only';
    return;
end

% ---- What each file offers, counted so the user knows what is on the table ----
foundLines = {};
if hasTies
    [~, tieName, tieExt] = fileparts(sidecars.tiePath);
    foundLines{end+1} = sprintf('    %s%s — %s', tieName, tieExt, ...
        describeCount(countXmlElements(sidecars.tiePath, 'Tie'), 'measured seam'));
end
if hasUpdates
    [~, updatesName, updatesExt] = fileparts(sidecars.updatesPath);
    foundLines{end+1} = sprintf('    %s%s — %s', updatesName, updatesExt, ...
        describeCount(countXmlElements(sidecars.updatesPath, 'Tile'), 'solved tile position'));
end

% Buttons carry the BatchOpt value they stand for, because the wording has to
% follow what is actually on disk: with no .ve-tie the fullest import is a
% placement without measurements (the layout builder synthesises the matching
% edges), and calling that button "seams + positions" would be a lie.
gridOnlyLabel = 'Nominal grid only';
tiesLabel     = 'Atlas seam measurements';
bothLabel     = 'Atlas seams + solved positions';

buttonLabels = {gridOnlyLabel};
buttonValues = {gridOnlyLabel};
explanations = { sprintf([ ...
    '%s — ignore both files and start from the stage grid recorded at\n' ...
    'acquisition. MIB measures every overlap and solves the mosaic itself. Use\n' ...
    'this when Atlas''s own stitch came out wrong.'], gridOnlyLabel) };

if hasTies
    buttonLabels{end+1} = tiesLabel;
    buttonValues{end+1} = tiesLabel;
    explanations{end+1} = sprintf([ ...
        '%s — take Atlas''s pairwise seam shifts and let MIB run\n' ...
        'its global solve on them. No image registration is repeated.'], tiesLabel);
end
if hasUpdates && hasTies
    buttonLabels{end+1} = bothLabel;
    buttonValues{end+1} = bothLabel;
    explanations{end+1} = sprintf([ ...
        '%s — also take Atlas''s final tile placement, so\n' ...
        'the mosaic is ready as it stands: press Stitch to fuse it with nothing\n' ...
        'recomputed.'], bothLabel);
elseif hasUpdates
    buttonLabels{end+1} = 'Atlas solved positions';
    buttonValues{end+1} = bothLabel;
    explanations{end+1} = sprintf([ ...
        'Atlas solved positions — take Atlas''s final tile placement, so the mosaic\n' ...
        'is ready as it stands: press Stitch to fuse it with nothing recomputed.']);
end

question = sprintf('Atlas has already stitched this mosaic:\n\n%s\n\n%s', ...
    strjoin(foundLines, newline), strjoin(explanations, sprintf('\n\n')));

% Default to the current BatchOpt value when it is still on the menu (so a
% repeated import keeps the user's habit), otherwise to the fullest import.
defaultIndex = find(strcmp(buttonValues, obj.BatchOpt.AtlasImport{1}), 1, 'last');
if isempty(defaultIndex); defaultIndex = numel(buttonLabels); end

dlgOptions.WindowWidth  = 680;
dlgOptions.WindowHeight = 400;
dlgOptions.Icon         = 'puffin_question';
selection = utils.dlgs.inputQuestDlg(obj.view.gui, question, ...
    'Atlas stitching results found', buttonLabels{:}, buttonLabels{defaultIndex}, dlgOptions);

selectedIndex = find(strcmp(buttonLabels, selection), 1);
if isempty(selectedIndex)
    accepted = false;      % dialog closed without choosing
    return;
end
obj.BatchOpt.AtlasImport{1} = buttonValues{selectedIndex};

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
