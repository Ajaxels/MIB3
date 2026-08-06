function title = getTitle(obj)
% GETTITLE - Get the title of this image document.
%
% Syntax:
%   .. code-block:: matlab
%
%      title = obj.getTitle()
%
% Returns the current title displayed in the document tab.
% The title typically shows the dataset name or buffer identifier.
%
% Input Arguments:
%   (none)
%
% Output Arguments:
%   - **title** - [char] current title of the document
%
% **Example 1** - get title of current document:
%
%   .. code-block:: matlab
%
%      currentTitle = obj.mibController.cImageDoc{1}.getTitle();
%      fprintf('Document title: %s\n', currentTitle);
%
% **Example 2** - search for document by title:
%
%   .. code-block:: matlab
%
%      targetTitle = 'MyDataset';
%      for i = 1:numel(obj.mibController.cImageDoc)
%          if strcmp(obj.mibController.cImageDoc{i}.getTitle(), targetTitle)
%              fprintf('Found at index %d\n', i);
%              break;
%          end
%      end
%

title = char(obj.figureDoc.Title);
end
