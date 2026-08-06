% Author: Ilya Belevich, University of Helsinki (ilya.belevich @ helsinki.fi)
% Date: 25.04.2023
% License: BSD-3 clause (https:% opensource.org/license/bsd-3-clause/)

function updateActionLog(obj, logEntry, action, entryIndex)
% UPDATEACTIONLOG - Append or modify a timestamped entry in the action log (obj.actionLog).
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.updateActionLog(logEntry, action, entryIndex)
%
% Input Arguments:
%   - **logEntry** - [char or string] description of the processing step to record,
%     e.g. 'ImFilter: Median, HSize:3 3, Orient:4'. Pass '' when only
%     performing a delete action.
%   - **action** - *(optional)* additional operation to perform; when omitted, entry is appended to the end:
%
%     - ``'insert'`` - insert new entry before position ``entryIndex``
%     - ``'delete'`` - delete entry at position ``entryIndex`` (``logEntry`` is ignored)
%     - ``'modify'`` - overwrite entry at position ``entryIndex``
%   - **entryIndex** - *(optional)* 1-based index for 'insert', 'delete', 'modify'
%
% Output Arguments:
%   (none) - modifies obj.actionLog in place.
%
% Usage:
%   **Example 1**
%
%   .. code-block:: matlab
%
%
%     obj.image.updateActionLog('ImFilter: Median, HSize:3 3, Orient:4');
%
%   **Example 2**
%
%   .. code-block:: matlab
%
%
%     obj.image.updateActionLog('MIB demo dataset', 'insert', 2);
%
%   **Example 3**
%
%   .. code-block:: matlab
%
%
%     obj.image.updateActionLog('', 'delete', 4);
%
%   **Example 4**
%
%   .. code-block:: matlab
%
%
%     obj.image.updateActionLog('Updated text', 'modify', 4);
%

% Updates
% 11.04.2026 - created
% 18.04.2026 - added action/entryIndex parameters

if nargin < 2; logEntry = ''; end
if isempty(logEntry) && (nargin < 3); return; end

stamp = sprintf('MIB(%s): %s', datestr(now, 'yymmddHHMM'), char(logEntry));

if nargin < 3   % simple append
    obj.actionLog{end+1} = stamp;
    return;
end

switch action
    case 'insert'
        if nargin < 4 || isempty(entryIndex) || entryIndex > numel(obj.actionLog)
            obj.actionLog{end+1} = stamp;
        else
            obj.actionLog = [obj.actionLog(1:entryIndex-1), {stamp}, obj.actionLog(entryIndex:end)];
        end
    case 'delete'
        if nargin >= 4 && ~isempty(entryIndex) && entryIndex <= numel(obj.actionLog)
            obj.actionLog(entryIndex) = [];
        end
    case 'modify'
        if nargin >= 4 && ~isempty(entryIndex) && entryIndex <= numel(obj.actionLog)
            obj.actionLog{entryIndex} = stamp;
        end
    otherwise
        if ~isempty(logEntry)
            obj.actionLog{end+1} = stamp;
        end
end
end
