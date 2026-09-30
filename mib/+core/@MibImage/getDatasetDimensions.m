function varargout = getDatasetDimensions(obj, orient, splitDims, blockModeSwitch)
% GETDATASETDIMENSIONS - Get dimensions of the dataset as [height, width, depth, colors, time] or a combined vector.
%
% Syntax:
%   .. code-block:: matlab
%
%       varargout = obj.getDatasetDimensions(orient, splitDims, blockModeSwitch)
%
% Input Arguments:
%   - **orient** - *(optional)*, can be ``[]``; default ``3``:
%
%     - ``1`` - returns dimensions in ZX configuration: ``[y,x,z,c,t]`` → ``[z,x,y,c,t]``
%     - ``2`` - returns dimensions in ZY configuration: ``[y,x,z,c,t]`` → ``[y,z,x,c,t]``
%     - ``3`` - returns dimensions of the original YX dataset: ``[y,x,z,c,t]``
%
%   - **splitDims** - *(optional)* logical; default ``true``:
%
%     - ``true`` - return individual outputs: ``height``, ``width``, ``depth``, ``colors``, ``time``
%     - ``false`` - return a single array ``[height, width, depth, colors, time]``
%
%   - **blockModeSwitch** - *(optional)* logical; default ``false``. Must be
%     ``false``: an image does not know which part of itself is on screen, since
%     the shown block is ``MibDataset.slices``. Passing ``true`` raises
%     ``MibImage:getDatasetDimensions:blockModeUnsupported``; use
%     :meth:`core.MibDataset.getDatasetDimensions` for block-mode dimensions.
%
% Output Arguments:
%   - when **splitDims** = ``true``: ``[height, width, depth, colors, time]`` as separate outputs
%   - when **splitDims** = ``false``: single numeric array ``[height, width, depth, colors, time]``
%
% Usage:
%   **Example 1**
%
%   .. code-block:: matlab
%
%
%     [height, width, depth, colors, time] = obj.getDatasetDimensions();
%
%   **Example 2**
%
%   .. code-block:: matlab
%
%
%     dims = obj.getDatasetDimensions(3, false);   % dims = [height, width, depth, colors, time]

% define missing parameters
if nargin < 4; blockModeSwitch = false; end  
if nargin < 3; splitDims = []; end  
if nargin < 2; orient = []; end  

% update default settings
if isempty(splitDims); splitDims = true; end % split dimensions
% NaN is a MIB2 leftover still passed by some call sites; without this it fell
% through the branches below with nothing assigned, and the error named the
% local variable ("Unrecognized function or variable 'height'") rather than the
% argument that was wrong.
if isempty(orient) || (isnumeric(orient) && isscalar(orient) && isnan(orient))
    orient = 3;    % YX-plane
end

dim_yxz = [obj.height, obj.width, obj.depth];
colors = obj.colors;
time = obj.time;

% An image does not know what part of it is on screen: the shown block is
% dataset.slices, a MibDataset property. This branch used to read obj.slices and
% could only ever raise "Unrecognized method, property, or field 'slices' for
% class 'core.MibImage'" - a message that points at this file rather than at the
% call site that asked the wrong object. Say what to do instead.
if blockModeSwitch
    error('MibImage:getDatasetDimensions:blockModeUnsupported', ...
        ['core.MibImage cannot report block-mode dimensions - the shown block is\n' ...
         'defined by MibDataset.slices. Call it on the dataset instead:\n' ...
         '    dataset.getDatasetDimensions(''image'', [], struct(''blockModeSwitch'', true))']);
end

switch orient
    case 3 % yx
        height = dim_yxz(1);
        width = dim_yxz(2);
        depth = dim_yxz(3);
    case 1 % zx: rows = Z, columns = X
        height = dim_yxz(3);
        width = dim_yxz(2);
        depth = dim_yxz(1);
    case 2 % yz
        height = dim_yxz(1);
        width = dim_yxz(3);
        depth = dim_yxz(2);
    otherwise
        error('MibImage:getDatasetDimensions:badOrient', ...
            'orient must be 1 (ZX), 2 (ZY) or 3 (YX); got %s.', num2str(orient));
end

% Return based on outputMode
if splitDims
    varargout{1} = height;
    varargout{2} = width;
    varargout{3} = depth;
    varargout{4} = colors;
    varargout{5} = time;
else
    varargout{1} = [height, width, depth, colors, time];
end

end
