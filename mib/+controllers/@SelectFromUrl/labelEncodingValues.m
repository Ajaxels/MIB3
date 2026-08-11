function [presentValue, unknownValue, isSemantic] = labelEncodingValues(~, pyramidInfo)
% LABELENCODINGVALUES - Read how a label group encodes its values.
%
% Syntax:
%   .. code-block:: matlab
%
%      [presentValue, unknownValue, isSemantic] = obj.labelEncodingValues(pyramidInfo)
%
% Every COSEM single-class group states its own encoding in
% ``cellmap.annotation.annotation_type.encoding``, so nothing here is a
% convention MIB imposes.
%
% **The third output is the one that matters.** A group with no ``cellmap``
% block is not a binary mask with default values - it is an index map holding
% several classes, which is what a crop's merged ``all`` group is. Treating it
% as binary looks for voxels equal to 1 and, on a crop whose ids start at 3,
% finds none, giving an empty model and no error. ``isSemantic`` is therefore
% false unless the store actually declares a ``present`` value, never by default.
%
% Input Arguments:
%   - **pyramidInfo** - [struct] from :meth:`readGroupPyramid`
%
% Output Arguments:
%   - **presentValue** - [numeric] value meaning "this class is here"; only
%     meaningful when ``isSemantic`` is true
%   - **unknownValue** - [numeric] value meaning "not annotated" (default 255,
%     which every group of the reference store uses, declared or not)
%   - **isSemantic** - [logical] true for a single-class binary group, false for
%     a multi-class index map

presentValue = 1;
unknownValue = 255;
isSemantic   = false;

if isempty(pyramidInfo) || ~isstruct(pyramidInfo) || isempty(pyramidInfo.encoding)
    return;
end

encoding = pyramidInfo.encoding;
if isfield(encoding, 'unknown') && ~isempty(encoding.unknown)
    unknownValue = double(encoding.unknown);
end
if isfield(encoding, 'present') && ~isempty(encoding.present)
    presentValue = double(encoding.present);
    isSemantic   = true;
end
end
