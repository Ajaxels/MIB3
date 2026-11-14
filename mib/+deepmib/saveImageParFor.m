function saveImageParFor(fn, imgOut, compressImage, options)
% SAVEIMAGEPARFOR - Save an image matrix from inside a ``parfor`` loop.
%
% Syntax:
%   .. code-block:: matlab
%
%      saveImageParFor(fn, imgOut, compressImage)
%      saveImageParFor(fn, imgOut, compressImage, options)
%
% Used by ``mibDeepController`` to preprocess images; ``save`` cannot be
% called directly inside ``parfor``.
%
% Input Arguments:
%   - **fn** - [string] full output filename
%   - **imgOut** - image matrix to save
%   - **compressImage** - [logical] ``true`` to enable MAT-file compression
%   - **options** *(optional)* - struct with additional parameters:
%
%     - ``.dimOrder`` - [char] axis order string, e.g. ``'yxzct'``
%       meaning ``[height, width, depth, color, time]``
%     - ``.modelType`` - [double] label model type: ``63``, ``255``, or ``65536``
%     - ``.modelMaterialNames`` - cell array of class name strings
%     - ``.modelMaterialColors`` - ``[N×3 double]`` RGB colour matrix per class
%     - ``.boundingBox`` - ``[xmin xmax ymin ymax zmin zmax]`` of the image the
%       data was made from (``deepmib.getSourceBoundingBox``); returned by
%       ``io.loaders.MibImgLoader`` as the ``BoundingBox`` metadata key
%     - ``.pixSize`` - voxel size struct (``.x .y .z .units``) of that image
%
% The whole ``options`` struct is stored in the file, so the optional fields
% are written only by callers that set them.
%

if nargin < 4; options = struct(); end
if ~isfield(options, 'dimOrder'); options.dimOrder = 'yxzct'; end

imgVariable = 'imgOut';     % defines name of the variable in the file with the image

if compressImage     % saving images
    save(fn, 'imgOut', 'imgVariable', 'options', '-mat', '-v7.3');   % save image file
else
    save(fn, 'imgOut', 'imgVariable', 'options', '-nocompression', '-mat', '-v7.3');
end
end
