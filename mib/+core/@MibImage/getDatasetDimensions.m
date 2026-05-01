function varargout = getDatasetDimensions(obj, orient, splitDims, blockModeSwitch)
% GETDATASETDIMENSIONS - Get dimensions of the dataset as [height, width, depth, colors, time] or a combined vector.
%
% Syntax:
%   .. code-block:: matlab
%
%       varargout = obj.getDatasetDimensions(orient, splitDims, blockModeSwitch)
%
% Input Arguments:
%   - **orient** — *(optional)*, can be ``[]``; default ``3``:
%
%     - ``1`` — returns dimensions in ZX configuration: ``[y,x,z,c,t]`` → ``[x,z,y,c,t]``
%     - ``2`` — returns dimensions in ZY configuration: ``[y,x,z,c,t]`` → ``[y,z,x,c,t]``
%     - ``3`` — returns dimensions of the original YX dataset: ``[y,x,z,c,t]``
%
%   - **splitDims** — *(optional)* logical; default ``true``:
%
%     - ``true`` — return individual outputs: ``height``, ``width``, ``depth``, ``colors``, ``time``
%     - ``false`` — return a single array ``[height, width, depth, colors, time]``
%
%   - **blockModeSwitch** — *(optional)* logical; default ``false``:
%
%     - ``false`` — return dimensions of the full dataset
%     - ``true`` — return dimensions of the shown (block-mode) part only
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
if isempty(orient); orient = 3; end % YX-plane

dim_yxz = [obj.height, obj.width, obj.depth];
colors = obj.colors;
time = obj.time;

if blockModeSwitch
    if orient == 3 % yx
        height = obj.slices{1}(2)-obj.slices{1}(1)+1;
        width = obj.slices{2}(2)-obj.slices{2}(1)+1;
        depth = dim_yxz(3);
    elseif orient==1     % xz
        depth = dim_yxz(1);
        height = obj.slices{2}(2)-obj.slices{2}(1)+1;
        width = obj.slices{3}(2)-obj.slices{3}(1)+1;
    elseif orient==2 % yz
        height = obj.slices{1}(2)-obj.slices{1}(1)+1;
        width = obj.slices{3}(2)-obj.slices{3}(1)+1;
        depth = dim_yxz(2);
    end
else % block mode
    if orient == 3 % yx
        height = dim_yxz(1);
        width = dim_yxz(2);
        depth = dim_yxz(3);
    elseif orient==1     % xz
        height = dim_yxz(2);
        width = dim_yxz(3);
        depth = dim_yxz(1);
    elseif orient==2 % yz
        height = dim_yxz(1);
        width = dim_yxz(3);
        depth = dim_yxz(2);
    end
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
