function title = getTitle(obj)
% function title = getTitle(obj)
% Get the title of this image document
%
% Returns the current title displayed in the document tab.
% The title typically shows the dataset name or buffer identifier.
%
% Parameters:
%   none
%
% Return values:
%   title: char, current title of the document
%
% Example:
%   % Get title of current document
%   currentTitle = obj.mibController.cImageDoc{1}.getTitle();
%   fprintf('Document title: %s\n', currentTitle);
%
%   % Search for document by title
%   targetTitle = 'MyDataset';
%   for i = 1:numel(obj.mibController.cImageDoc)
%       if strcmp(obj.mibController.cImageDoc{i}.getTitle(), targetTitle)
%           fprintf('Found at index %d\n', i);
%           break;
%       end
%   end

title = char(obj.figureDoc.Title);
end