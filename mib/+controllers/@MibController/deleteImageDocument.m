function deleteImageDocument(obj, docIndex)
% function deleteImageDocument(obj, docIndex)
% Delete an image document and reindex remaining documents
%
% Removes the image document at the specified index, properly cleans up
% all associated resources (FigureDocument, ImageView, brush cursor),
% and updates the documentIndex property of all subsequent documents
% to maintain consistency with their array positions.
%
% The method performs these operations:
% 1. Validates the document index
% 2. Calls the document's delete() method for cleanup
% 3. Removes the document from the cImageDoc array
% 4. Reindexes all documents after the deleted position
%
% Parameters:
%   docIndex: double, index of the document to delete (1-based)
%
% Return values:
%   none
%
% Example:
%   % Delete document at index 3
%   obj.mibController.deleteImageDocument(3);
%
%   % Delete document when closing a buffer
%   prevSelectedSet = 2;
%   obj.mibController.deleteImageDocument(prevSelectedSet);
%
%   % Delete with validation
%   setToDelete = 5;
%   if setToDelete <= numel(obj.mibController.cImageDoc)
%       obj.mibController.deleteImageDocument(setToDelete);
%       fprintf('Document %d deleted successfully\n', setToDelete);
%   end
%
%   % Delete all documents (cleanup)
%   while ~isempty(obj.mibController.cImageDoc)
%       obj.mibController.deleteImageDocument(1);
%   end

% Validate index
if docIndex < 1 || docIndex > numel(obj.cImageDoc)
    warning('MibController:deleteImageDocument', ...
        'Invalid document index: %d. Valid range is 1-%d', ...
        docIndex, numel(obj.cImageDoc));
    return;
end

% Delete the document object (triggers cleanup in delete() method)
if ~isempty(obj.cImageDoc{docIndex}); delete(obj.cImageDoc{docIndex}); end

% Remove from array
obj.cImageDoc(docIndex) = [];

% Re-index all subsequent documents to maintain consistency
for i = docIndex:numel(obj.cImageDoc)
    if ~isempty(obj.cImageDoc{i})
        obj.cImageDoc{i}.documentIndex = i;
    end
end
end
