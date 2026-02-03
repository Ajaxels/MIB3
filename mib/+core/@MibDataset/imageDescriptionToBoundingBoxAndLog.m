function [bb, logEntries] = imageDescriptionToBoundingBoxAndLog(obj, imageDescription)
% function [bb, logEntries] = imageDescriptionToBoundingBoxAndLog(obj, imageDescription)
% Extract bounding box and log entries from ImageDescription field
%
% This method parses the ImageDescription field to extract both bounding 
% box coordinates and log entries. The BoundingBox is expected at the 
% beginning, followed by log entries separated by '|' (pipe) characters.
% If bounding box is not found, it calculates default values using image 
% dimensions and pixel sizes.
%
% Parameters:
% imageDescription: [@em char] - ImageDescription text from dictionary,
%     containing BoundingBox tag (optional) and other entries separated 
%     using the '|' character
%
% Return values:
% bb: [@em double] - bounding box as a 6-element vector [xmin, xmax, ymin, ymax, zmin, zmax]
%     @li bb(1) = Xmin - minimum X coordinate
%     @li bb(2) = Xmax - maximum X coordinate
%     @li bb(3) = Ymin - minimum Y coordinate
%     @li bb(4) = Ymax - maximum Y coordinate
%     @li bb(5) = Zmin - minimum Z coordinate
%     @li bb(6) = Zmax - maximum Z coordinate
% logEntries: [@em cell] - cell array of strings, each containing one log entry.
%     Empty cell array {} is returned if no log entries are found.
%
% Examples:
% @code
% % Extract both bounding box and log entries
% imageDesc = obj.meta{'ImageDescription'};
% [bb, logEntries] = obj.imageDescriptionToBoundingBoxAndLog(imageDesc);
%
% % Example with full ImageDescription
% imageDesc = 'BoundingBox 0 511.5 0 511.5 0 49.5 | ImageJ=1.52p | Processing: filter applied';
% [bb, logEntries] = obj.imageDescriptionToBoundingBoxAndLog(imageDesc);
% % bb = [0 511.5 0 511.5 0 49.5]
% % logEntries = {'ImageJ=1.52p', 'Processing: filter applied'}
%
% % Example without BoundingBox
% imageDesc = 'ImageJ=1.52p | Date=2026-02-03';
% [bb, logEntries] = obj.imageDescriptionToBoundingBoxAndLog(imageDesc);
% % bb = calculated from dimensions
% % logEntries = {'ImageJ=1.52p', 'Date=2026-02-03'}
% @endcode

% define default bounding box
bb(1) = 0;
bb(3) = 0;
bb(5) = 0;
bb(2) = (max([obj.image.width 2])-1) * obj.pixSize.x;
bb(4) = (max([obj.image.height 2])-1) * obj.pixSize.y;
bb(6) = (max([obj.image.depth 2])-1) * obj.pixSize.z;

logEntries = {};

% Check if BoundingBox exists at the beginning
bb_info_exist = strfind(imageDescription, 'BoundingBox');

if bb_info_exist == 1
    % Find space positions
    spaces = strfind(imageDescription, ' ');
    
    % Ensure we have enough spaces
    if numel(spaces) < 7; spaces(7) = numel(imageDescription); end
    
    % Find pipe character position
    pipe_positions = strfind(imageDescription, '|');
    
    % Extract bounding box numbers between first space and either 7th space or pipe
    pos = min([spaces(7) pipe_positions]);
    bb = str2num(imageDescription(spaces(1):pos-1)); %#ok<ST2NM>
    
    % Extract log entries after the first pipe
    if ~isempty(pipe_positions)
        remainingText = imageDescription(pipe_positions(1)+1:end);
        entries = strsplit(remainingText, '|');
        
        % Trim whitespace and remove empty entries
        for i = 1:numel(entries)
            trimmedEntry = strtrim(entries{i});
            if ~isempty(trimmedEntry)
                logEntries{end+1} = trimmedEntry; %#ok<AGROW>
            end
        end
    end
else
    % No BoundingBox found - extract all as log entries
    if ~isempty(imageDescription)
        entries = strsplit(imageDescription, '|');
        
        % Trim whitespace and remove empty entries
        for i = 1:numel(entries)
            trimmedEntry = strtrim(entries{i});
            if ~isempty(trimmedEntry)
                logEntries{end+1} = trimmedEntry; %#ok<AGROW>
            end
        end
    end
end
end
