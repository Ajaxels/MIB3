function selectDocument(obj)
% function selectDocument(obj)
% Select this document in the document group
%
% Makes this document the active/selected document in the MDI interface.
% This updates the UI to show this document's tab as selected.
%
% Parameters:
%   none
%
% Return values:
%   none
%
% Example:
%   % Select document by index
%   obj.mibController.cImageDoc{2}.selectDocument();
%
%   % Select document after finding it
%   for i = 1:numel(obj.mibController.cImageDoc)
%       if strcmp(obj.mibController.cImageDoc{i}.getTitle(), 'MyDataset')
%           obj.mibController.cImageDoc{i}.selectDocument();
%           break;
%       end
%   end

obj.figureDoc.Selected = true;
end