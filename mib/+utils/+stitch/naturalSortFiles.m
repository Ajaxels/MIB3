function sortedFiles = naturalSortFiles(cellstrFiles)
% NATURALSORTFILES - Sort a cell array of filenames in natural (alphanumeric) order.
%
% Syntax:
%   .. code-block:: matlab
%
%      sortedFiles = utils.stitch.naturalSortFiles(cellstrFiles)
%
% Natural sort treats embedded digit sequences as numbers, so that
% ``tile2.tif`` sorts before ``tile10.tif``.  Comparison is
% case-insensitive and operates on the full path string.
%
% Input Arguments:
%   - **cellstrFiles** - [cell] cell array of character vectors (filenames or full paths)
%
% Output Arguments:
%   - **sortedFiles** - [cell] input cell sorted in natural/alphanumeric order
%
% **Example** - sort a mixed list of tile names:
%
%   .. code-block:: matlab
%
%      files = {'tile10.tif', 'tile2.tif', 'tile1.tif'};
%      sorted = utils.stitch.naturalSortFiles(files);
%      % sorted = {'tile1.tif', 'tile2.tif', 'tile10.tif'}
%

if isempty(cellstrFiles)
    sortedFiles = cellstrFiles;
    return;
end

% Build sort keys by splitting each string into alternating text/number tokens.
% Each token is padded to the same width so lexicographic sort equals numeric sort.
numFiles = numel(cellstrFiles);
sortKeys = cell(numFiles, 1);

for fileIdx = 1:numFiles
    rawName = lower(cellstrFiles{fileIdx});
    % Split into digit and non-digit runs using a cell array of tokens
    tokens = regexp(rawName, '(\d+|\D+)', 'tokens');
    keyParts = '';
    for tokenIdx = 1:numel(tokens)
        tokenStr = tokens{tokenIdx}{1};
        if ~isempty(regexp(tokenStr, '^\d+$', 'once'))
            % Pad numeric token to 20 digits for correct lexicographic ordering
            keyParts = [keyParts, sprintf('%020s', tokenStr)]; %#ok<AGROW>
        else
            keyParts = [keyParts, tokenStr]; %#ok<AGROW>
        end
    end
    sortKeys{fileIdx} = keyParts;
end

[~, sortIndices] = sort(sortKeys);
sortedFiles = cellstrFiles(sortIndices);

end
