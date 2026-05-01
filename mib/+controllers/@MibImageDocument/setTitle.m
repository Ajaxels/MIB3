function setTitle(obj, title)
% SETTITLE - Set the title of this image document.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.setTitle(title)
%
% Updates the title displayed in the document tab. This is useful
% when renaming datasets or updating document identification.
%
% Input Arguments:
%   - **title** — [char] new title for the document
%
% Output Arguments:
%   (none)
%
% **Example 1** — set simple title:
%
%   .. code-block:: matlab
%
%      obj.mibController.cImageDoc{1}.setTitle('Dataset_001');
%
% **Example 2** — set title based on filename:
%
%   .. code-block:: matlab
%
%      [~, fname] = fileparts(obj.mibModel.I{1}.image.filename);
%      obj.mibController.cImageDoc{1}.setTitle(fname);
%
% **Example 3** — update title when buffer changes:
%
%   .. code-block:: matlab
%
%      selectedSet = obj.mibModel.Sets.selectedSet;
%      newTitle = sprintf('Buffer %d', selectedSet);
%      obj.mibController.cImageDoc{selectedSet}.setTitle(newTitle);
%

obj.figureDoc.Title = title;
end
