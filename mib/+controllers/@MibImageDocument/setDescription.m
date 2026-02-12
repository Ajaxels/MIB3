function setDescription(obj, description)
% function setDescription(obj, description)
% Update the description text of this document
%
% The description appears below the document title and typically
% shows buffer number and filename information.
%
% Parameters:
%   description: char, description text to display
%
% Return values:
%   none
%
% Example:
%   obj.setDescription(sprintf('Buffer %d:\n%s', 1, 'myimage.tif'));

obj.figureDoc.Description = description;
end