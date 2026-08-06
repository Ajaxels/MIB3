function replaceMaskedArea(obj, maskVolume, colorValues, colorChannels, options)
% REPLACEMASKEDAREA - Replace pixels where maskVolume==1 with colorValues directly in obj.data.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.replaceMaskedArea(maskVolume, colorValues, colorChannels, options)
%
% Modifies ``obj.data`` in-place for the z-slice range and time point
% given in ``options``.  Called per time point by ``MibModel.replaceMaskedArea``.
%
% Input Arguments:
%   - **maskVolume** - [numeric | logical] ``[h, w, numZ]`` binary mask for
%     one time point; ``numZ`` must equal ``options.zRange(2) - options.zRange(1) + 1``
%   - **colorValues** - [numeric] scalar or vector with one replacement intensity
%     per entry in ``colorChannels``; a scalar is broadcast to every channel
%   - **colorChannels** - [numeric] vector of 1-based channel indices to modify
%   - **options** - *(optional)* struct with fields:
%
%     - ``.zRange`` - ``[z1, z2]`` indices into ``obj.data`` (default = all z)
%     - ``.timePoint`` - scalar time index into ``obj.data`` (default = ``1``)
%
% Output Arguments:
%   (none) - modifies ``obj.data`` in place
%
% Usage:
%   **Example 1** - set all channels to black inside the mask for time point 3, z 10-20
%
%   .. code-block:: matlab
%
%      opts.zRange    = [10, 20];
%      opts.timePoint = 3;
%      obj.image.replaceMaskedArea(maskVol, 0, 1:obj.image.colors, opts);
%

% Updates
% 2025 - ported from MIB2 mibImage.replaceImageColor; rewritten to update data{1} in-place

if nargin < 5; options = struct(); end
if ~isfield(options, 'zRange');    options.zRange    = [1, obj.depth]; end
if ~isfield(options, 'timePoint'); options.timePoint = 1;              end

colorValues = cast(min(max(colorValues, 0), obj.maxInt), obj.dataClass);
if isscalar(colorValues)
    colorValues = repmat(colorValues, 1, numel(colorChannels));
end

z1 = options.zRange(1);
z2 = options.zRange(2);
t  = options.timePoint;

logicalMask = logical(maskVolume);

imageData = obj.data;
for colIdx = 1:numel(colorChannels)
    ch = colorChannels(colIdx);
    imgBlock = imageData(:,:,z1:z2,ch,t);
    imgBlock(logicalMask) = colorValues(colIdx);
    imageData(:,:,z1:z2,ch,t) = imgBlock;
end
obj.data = imageData;

end
