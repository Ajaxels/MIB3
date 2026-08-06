function selectDocument(obj)
% SELECTDOCUMENT - Select this document in the document group.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.selectDocument()
%
% Makes this document the active/selected document in the MDI interface.
% This updates the UI to show this document's tab as selected.
%
% Input Arguments:
%   (none)
%
% Output Arguments:
%   (none)
%
% **Example 1** - select document by index:
%
%   .. code-block:: matlab
%
%      obj.mibController.cImageDoc{2}.selectDocument();
%
% **Example 2** - select document after finding it:
%
%   .. code-block:: matlab
%
%      for i = 1:numel(obj.mibController.cImageDoc)
%          if strcmp(obj.mibController.cImageDoc{i}.getTitle(), 'MyDataset')
%              obj.mibController.cImageDoc{i}.selectDocument();
%              break;
%          end
%      end
%

obj.figureDoc.Selected = true;
end
