function deleteImageDocument(obj, docIndex)
% DELETEIMAGEDOCUMENT - Delete an image document and reindex remaining documents.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.deleteImageDocument(docIndex)
%
% Removes the image document at the specified index, properly cleans up
% all associated resources (FigureDocument, ImageViewDocument, brush cursor),
% and updates the setOfDatasetsIndex property of all subsequent documents
% to maintain consistency with their array positions.
%
% The method performs these operations:
% 1. Validates the document index
% 2. Calls the document's delete() method for cleanup
% 3. Removes the document from the cImageDoc array
% 4. Reindexes all documents after the deleted position
%
% Input Arguments:
%   - **docIndex** — double, index of the document to delete (1-based)
%
% Output Arguments:
%   (none)
%
% **Example 1** — delete the image document at index 3:
%
%   .. code-block:: matlab
%
%      obj.mibController.deleteImageDocument(3);
%
% **Example 2** — delete all documents (cleanup loop):
%
%   .. code-block:: matlab
%
%      while ~isempty(obj.mibController.cImageDoc)
%          obj.mibController.deleteImageDocument(1);
%      end
%

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
        obj.cImageDoc{i}.setOfDatasetsIndex = i;
    end
end
end
