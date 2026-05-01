function result = setPixelIdxList(obj, type, dataset, PixelIdxList, options) 
% SETPIXELIDXLIST - Write pixel values at a list of linear indices into the active dataset layer.
%
% Syntax:
%   .. code-block:: matlab
%
%       result = obj.setPixelIdxList(type, dataset, PixelIdxList, options) %#ok<INUSD>
%
% Wrapper method on MibDataset that routes the write request to the correct
% layer object (obj.image, obj.labels, obj.mask, obj.selection) and then
% delegates to core.MibImage.setPixelIdxList.
%
% Routing rules (mirror setData3D):
%   - ``'image'`` — routes to ``obj.image``
%   - ``'labels'`` or ``'model'`` — routes to ``obj.labels``; sets ``obj.modelExist = true``
%   - ``'mask'`` — routes to ``obj.labels`` (``MibLabels63``) or ``obj.mask`` (``MibLabels``); sets ``obj.maskExist = true``
%   - ``'selection'`` — routes to ``obj.labels`` (``MibLabels63``) or ``obj.selection`` (``MibLabels``)
%   - ``'everything'`` — routes to ``obj.labels`` (``MibLabels63`` only)
%
% The PixelIdxList must be linear indices into the full 3D volume in XY
% orientation (i.e. as returned by bwconncomp / regionprops).
%
% Input Arguments:
%   - **type** — char, layer type to write:
%
%     - ``'image'`` — pixel values of the image layer
%     - ``'model'`` — synonym for ``'labels'``
%     - ``'labels'`` — material indices into the labels layer
%     - ``'mask'`` — mask layer values (0/1)
%     - ``'selection'`` — selection layer values (0/1)
%     - ``'everything'`` — raw packed byte (``MibLabels63`` only)
%   - **dataset** — numeric vector of values to write; must match numel(PixelIdxList)
%   - **PixelIdxList** — numeric vector of linear pixel indices into the full dataset
%     in the XY orientation (standard MATLAB column-major order)
%   - **options** — *(optional)* struct; reserved for future use, not used currently
%
% Output Arguments:
%   - **result** — logical **true** on success, **false** on error
%
% Usage:
%   **Example 1** — move object 1 pixels into the selection layer
%
%   .. code-block:: matlab
%
%
%     I = cell2mat(obj.mibModel.getData3D('mask'));
%     CC = bwconncomp(I, 26);
%     val = zeros(numel(CC.PixelIdxList{1}), 1, 'uint8') + 1;
%     % move object 1 pixels into the selection layer:
%     obj.mibModel.I{id}.setPixelIdxList('selection', val, CC.PixelIdxList{1});
%
%   **Example 2** — clear the model label at a set of pixel positions
%
%   .. code-block:: matlab
%
%
%     % clear the model label at a set of pixel positions:
%     obj.mibModel.I{id}.setPixelIdxList('labels', zeros(numel(idx),1,'uint8'), idx);
%

% Updates
%

result = false; %#ok<NASGU>
if nargin < 5; options = struct(); end %#ok<NASGU>
if nargin < 4; error('setPixelIdxList: PixelIdxList is required'); end
if nargin < 3; error('setPixelIdxList: dataset is required'); end
if nargin < 2; error('setPixelIdxList: type is required'); end

if strcmp(type, 'model'); type = 'labels'; end

switch type
    case 'image'
        result = obj.image.setPixelIdxList('image', dataset, PixelIdxList);

    case 'labels'
        obj.labels.setPixelIdxList('labels', dataset, PixelIdxList);
        obj.modelExist = true;
        result = true;

    case 'mask'
        if obj.labels.maxMaterials < 255
            % MibLabels63: mask packed in bit 7 of obj.labels
            obj.labels.setPixelIdxList('mask', dataset, PixelIdxList);
        else
            % MibLabels: mask stored in separate obj.mask layer
            obj.mask.setPixelIdxList('image', dataset, PixelIdxList);
        end
        obj.maskExist = true;
        result = true;

    case 'selection'
        if obj.labels.maxMaterials < 255
            % MibLabels63: selection packed in bit 8 of obj.labels
            obj.labels.setPixelIdxList('selection', dataset, PixelIdxList);
        else
            % MibLabels: selection stored in separate obj.selection layer
            obj.selection.setPixelIdxList('image', dataset, PixelIdxList);
        end
        result = true;

    case 'everything'
        % Raw packed byte — only valid for MibLabels63
        obj.labels.setPixelIdxList('everything', dataset, PixelIdxList);
        result = true;

    otherwise
        error('setPixelIdxList: unknown type ''%s''', type);
end
end
