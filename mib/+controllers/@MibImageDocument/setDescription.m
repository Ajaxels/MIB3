function setDescription(obj, description)
% SETDESCRIPTION - Update the description text of this document.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.setDescription(description)
%
% The description appears below the document title and typically
% shows buffer number and filename information.
%
% Input Arguments:
%   - **description** - [char] description text to display
%
% Output Arguments:
%   (none)
%
% **Example** - set description with buffer number and filename:
%
%   .. code-block:: matlab
%
%      obj.setDescription(sprintf('Buffer %d: %s', 1, 'myimage.tif'));
%

obj.figureDoc.Description = description;
end
