function setMeta(obj, meta)
% SETMETA - Apply a metadata dictionary to MibImage properties.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.setMeta(meta)
%
% Updates the object's properties from a dictionary matching the schema
% of MibImage.initializeImgInfo(). Does NOT touch obj.data - only
% updates metadata properties. This is the inverse of getMeta().
%
% Input Arguments:
%   - **meta** - dictionary with MibImage metadata fields (as returned by getMeta
%     or initializeImgInfo)
%
% Output Arguments:
%
% Usage:
%   **Example 1**
%
%   .. code-block:: matlab
%
%
%     meta = obj.mibModel.I{obj.mibModel.id}.image.getMeta();
%     meta{'Width'} = 1024;
%     obj.mibModel.I{obj.mibModel.id}.image.setMeta(meta);% apply modified metadata
%

% Updates
%

obj.filename    = meta{'Filename'};
obj.height      = meta{'Height'};
obj.width       = meta{'Width'};
obj.colors      = meta{'Colors'};
obj.colormap    = meta{'Colormap'};
obj.depth       = meta{'Depth'};
obj.time        = meta{'Time'};
obj.dataClass   = meta{'imgClass'};
obj.colorType   = meta{'ColorType'};
obj.maxInt      = meta{'MaxInt'};
obj.sliceName   = meta{'SliceName'};
obj.sliceSize   = meta{'SliceSize'};
obj.pixSize     = meta{'pixSize'};
obj.lutColors   = meta{'lutColors'};

% viewPort
if ~isempty(meta{'viewPort'})
    obj.viewPort = meta{'viewPort'};
end

% boundingBox + actionLog from ImageDescription
[imgDesc, parsedLog] = core.MibImage.splitImageDescription(meta{'ImageDescription'});
coords = sscanf(imgDesc, 'BoundingBox %f %f %f %f %f %f');
if numel(coords) == 6
    obj.boundingBox = coords(:)';
end
if isKey(meta, 'ActionLog') && ~isempty(meta{'ActionLog'})
    obj.actionLog = meta{'ActionLog'};
else
    obj.actionLog = parsedLog;
end

% custom metadata from loaders
if isKey(meta, 'customMeta') && isstruct(meta{'customMeta'})
    obj.customMeta = meta{'customMeta'};
else
    obj.customMeta = struct();
end

% update dim_yxzct
obj.dim_yxzct = [obj.height obj.width obj.depth obj.colors obj.time];
end
