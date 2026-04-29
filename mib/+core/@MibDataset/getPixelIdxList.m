function dataset = getPixelIdxList(obj, type, PixelIdxList, options) %#ok<INUSD>
% GETPIXELIDXLIST - Get pixel values at a list of linear indices from the active dataset layer.
%
% Syntax:
%   function dataset = getPixelIdxList(obj, type, PixelIdxList, options) %#ok<INUSD>
%
% Wrapper method on MibDataset that routes the read request to the correct
% layer object (obj.image, obj.labels, obj.mask, obj.selection) and then
% delegates to core.MibImage.getPixelIdxList.
%
% Routing rules (mirror getData3D):
% - type 'image'               → obj.image
% - type 'labels'/'model'      → obj.labels (returns [] when modelExist==0)
% - type 'mask'                → obj.labels (MibLabels63) or obj.mask (MibLabels)
% returns [] when maskExist==0
% - type 'selection'           → obj.labels (MibLabels63) or obj.selection (MibLabels)
% - type 'everything'          → obj.labels (MibLabels63 only)
%
% The PixelIdxList must be linear indices into the full 3D volume in XY
% orientation (i.e. as returned by bwconncomp / regionprops).
%
% Input Arguments:
%   - **type** — char, layer type to read:
%
%     - ``'image'`` — pixel values from the image layer
%     - ``'model'`` — synonym for ``'labels'``
%     - ``'labels'`` — material indices from the labels layer
%     - ``'mask'`` — mask layer values (0/1)
%     - ``'selection'`` — selection layer values (0/1)
%     - ``'everything'`` — raw packed byte (``MibLabels63`` only)
%   - **PixelIdxList** — numeric vector of linear pixel indices into the full dataset
%     in the XY orientation (standard MATLAB column-major order)
%   - **options** — *(optional)* struct; reserved for future use, not used currently
%
% Output Arguments:
%   - **dataset** — numeric column vector of values at the requested indices;
%     [] when the layer does not exist (modelExist==0 or maskExist==0)
%
% Usage:
%   **Example 1** — query selection values inside object 1
%
%   .. code-block:: matlab
%
%
%     I = cell2mat(obj.mibModel.getData3D('mask'));
%     CC = bwconncomp(I, 26);
%     % query selection values inside object 1:
%     vals = obj.mibModel.I{id}.getPixelIdxList('selection', CC.PixelIdxList{1});
%
%   **Example 2** — reading model material indices for a set of pixels
%
%   .. code-block:: matlab
%
%
%     % reading model material indices for a set of pixels:
%     matIdx = obj.mibModel.I{id}.getPixelIdxList('labels', pixIdx);
%

% Updates
%

dataset = [];
if nargin < 4; options = struct(); end %#ok<NASGU>
if nargin < 3; error('getPixelIdxList: PixelIdxList is required'); end
if nargin < 2; error('getPixelIdxList: type is required'); end

if strcmp(type, 'model'); type = 'labels'; end

switch type
    case 'image'
        dataset = obj.image.getPixelIdxList('image', PixelIdxList);

    case 'labels'
        if ~obj.modelExist; return; end
        dataset = obj.labels.getPixelIdxList('labels', PixelIdxList);

    case 'mask'
        if ~obj.maskExist; return; end
        if obj.labels.maxMaterials < 255
            % MibLabels63: mask packed in bit 7 of obj.labels
            dataset = obj.labels.getPixelIdxList('mask', PixelIdxList);
        else
            % MibLabels: mask stored in separate obj.mask layer
            dataset = obj.mask.getPixelIdxList('image', PixelIdxList);
        end

    case 'selection'
        if obj.labels.maxMaterials < 255
            % MibLabels63: selection packed in bit 8 of obj.labels
            dataset = obj.labels.getPixelIdxList('selection', PixelIdxList);
        else
            % MibLabels: selection stored in separate obj.selection layer
            dataset = obj.selection.getPixelIdxList('image', PixelIdxList);
        end

    case 'everything'
        % Raw packed byte — only valid for MibLabels63
        dataset = obj.labels.getPixelIdxList('everything', PixelIdxList);

    otherwise
        error('getPixelIdxList: unknown type ''%s''', type);
end
end
