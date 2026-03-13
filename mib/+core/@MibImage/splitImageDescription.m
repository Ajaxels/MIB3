function [imageDescription, actionLog] = splitImageDescription(fullStr)
% function [imageDescription, actionLog] = splitImageDescription(fullStr)
% Split a full ImageDescription string into the BoundingBox part and a
% cell array of per-operation log entries.
%
% BACKGROUND
%   MIB stores two conceptually distinct pieces of information inside the
%   single ImageDescription tag that is written to TIFF (and other) files:
%
%     1. Physical extent (BoundingBox) — a compact string describing the
%        real-world coordinates of the dataset in micrometres:
%
%            'BoundingBox xmin xmax ymin ymax zmin zmax'
%
%     2. Operation log — a pipe-separated list of timestamped records that
%        document every processing step applied to the dataset since it was
%        first opened in MIB:
%
%            'MIB(2601041823): MIB demo dataset, Huh7 SBEM'
%            'MIB(2603131934): ImFilter: Gaussian, HSize:3  3, Sigma:0.6, ...'
%
%   The two parts are concatenated with '|' as delimiter:
%
%       'BoundingBox x1 x2 y1 y2 z1 z2|LogEntry1|LogEntry2|...'
%
%   This function separates them so that:
%     - imageDescription  carries the BoundingBox string; parsed by
%       MibImage.initialize into obj.boundingBox (a 1×6 double).
%     - actionLog         carries the per-operation records; stored in
%       obj.actionLog of the MibImage (and its subclasses MibLabels,
%       MibVirtualImage); appended to when operations are performed.
%
% Parameters:
%   fullStr — (char) the raw ImageDescription string as read from a file or
%             stored in an imginfo dictionary.  May be empty or contain only
%             a BoundingBox with no log entries, or only log entries with no
%             BoundingBox.  All combinations are handled gracefully.
%
% Return values:
%   imageDescription — (char) the substring that precedes the first '|',
%                      trimmed of leading/trailing whitespace.  Contains the
%                      BoundingBox tag when present, or is empty when the
%                      input starts immediately with '|'.
%   actionLog        — (1×N cell of char) each element is one log entry,
%                      trimmed of whitespace.  Empty entries (consecutive
%                      '||' or trailing '|') are silently discarded.
%                      Returns {} when no log entries are found.
%
% USAGE EXAMPLES
%   @code
%   %% 1. Typical MIB TIFF tag with BoundingBox and two log entries
%   raw = ['BoundingBox 0.000000 6.760000 0.000000 4.823000 0.000000 2.220000' ...
%          '|MIB(2601041823): MIB demo dataset, Huh7 SBEM' ...
%          '|MIB(2603131934): ImFilter: Gaussian, HSize:3  3, Sigma: 0.6,' ...
%          'Orient:4,ColCh:1, Mode:2D, shown slice, Options:Apply filter,slice=1'];
%
%   [imgDesc, log] = core.MibImage.splitImageDescription(raw);
%   % imgDesc -> 'BoundingBox 0.000000 6.760000 0.000000 4.823000 0.000000 2.220000'
%   % log     -> {'MIB(2601041823): MIB demo dataset, Huh7 SBEM', ...
%   %             'MIB(2603131934): ImFilter: Gaussian, ...'}
%   @endcode
%
%   @code
%   %% 2. BoundingBox only, no log
%   raw = 'BoundingBox 0 511.5 0 511.5 0 49.5';
%   [imgDesc, log] = core.MibImage.splitImageDescription(raw);
%   % imgDesc -> 'BoundingBox 0 511.5 0 511.5 0 49.5'
%   % log     -> {}
%   @endcode
%
%   @code
%   %% 3. Log entries only, no BoundingBox (e.g. ImageJ description)
%   raw = 'ImageJ=1.52p|unit=um|spacing=0.2|loop=false';
%   [imgDesc, log] = core.MibImage.splitImageDescription(raw);
%   % imgDesc -> 'ImageJ=1.52p'
%   % log     -> {'unit=um', 'spacing=0.2', 'loop=false'}
%   @endcode
%
%   @code
%   %% 4. Empty or default initializer string
%   [imgDesc, log] = core.MibImage.splitImageDescription('');
%   % imgDesc -> ''
%   % log     -> {}
%
%   [imgDesc, log] = core.MibImage.splitImageDescription('|');  % initializeImgInfo default
%   % imgDesc -> ''
%   % log     -> {}
%   @endcode
%
%   @code
%   %% 5. Typical loader workflow — split immediately after reading metadata
%   raw = imginfo{'ImageDescription'};   % full string from file
%   [imgDesc, actionLog] = core.MibImage.splitImageDescription(raw);
%
%   % Store split parts back into the dictionary before passing to MibDataset
%   imginfo{'ImageDescription'} = imgDesc;
%   imginfo{'ActionLog'}        = actionLog;
%   @endcode
%
%   @code
%   %% 6. Round-trip test — split then rejoin
%   raw = 'BoundingBox 0 10 0 8 0 4|MIB(001): opened|MIB(002): filtered';
%   [imgDesc, log] = core.MibImage.splitImageDescription(raw);
%
%   if isempty(log)
%       rebuilt = imgDesc;
%   else
%       rebuilt = [imgDesc '|' strjoin(log, '|')];
%   end
%   assert(strcmp(raw, rebuilt));
%   @endcode
%
% SEE ALSO
%   core.MibImage.initializeImgInfo, core.MibDataset.initialize,
%   core.MibDataset.saveImage

% --- handle empty / missing input ---
if nargin < 1 || isempty(fullStr)
    imageDescription = '';
    actionLog        = {};
    return;
end

% --- locate the first pipe ---
pipePos = strfind(fullStr, '|');

if isempty(pipePos)
    % No pipe at all — the entire string is the imageDescription
    imageDescription = strtrim(fullStr);
    actionLog        = {};
    return;
end

% --- split at the first pipe ---
imageDescription = strtrim(fullStr(1 : pipePos(1)-1));
remainder        = fullStr(pipePos(1)+1 : end);

% --- parse remaining entries (split at every subsequent '|') ---
if isempty(strtrim(remainder))
    actionLog = {};
    return;
end

entries   = strsplit(remainder, '|');
entries   = strtrim(entries);
actionLog = entries(~cellfun(@isempty, entries));   % drop empty entries
end
