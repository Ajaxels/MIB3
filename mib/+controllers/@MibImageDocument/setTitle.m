function setTitle(obj, title)
% function setTitle(obj, title)
% Set the title of this image document
%
% Updates the title displayed in the document tab. This is useful
% when renaming datasets or updating document identification.
%
% Parameters:
%   title: char, new title for the document
%
% Return values:
%   none
%
% Example:
%   % Set simple title
%   obj.mibController.cImageDoc{1}.setTitle('Dataset_001');
%
%   % Set title based on filename
%   [~, fname] = fileparts(obj.mibModel.I{1}.image.filename);
%   obj.mibController.cImageDoc{1}.setTitle(fname);
%
%   % Update title when buffer changes
%   selectedSet = obj.mibModel.Sets.selectedSet;
%   newTitle = sprintf('Buffer %d', selectedSet);
%   obj.mibController.cImageDoc{selectedSet}.setTitle(newTitle);

obj.figureDoc.Title = title;
end