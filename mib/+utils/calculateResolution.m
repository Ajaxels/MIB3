function resolution = calculateResolution(pixSize)
% CALCULATERESOLUTION - Calculate image resolution in Pixels/Inch for saving TIFF files.
%
% Syntax:
%
%   .. code-block:: matlab
%
%      resolution = calculateResolution(pixSize)
%
% Input Arguments:
%   - **pixSize** — struct with physical voxel dimensions:
%
%     - ``.x`` — physical width of the pixel
%     - ``.y`` — physical height of the pixel
%     - ``.units`` — physical unit string: ``'m'``, ``'cm'``, ``'mm'``, ``'um'``, ``'nm'``
%
% Output Arguments:
%   - **resolution** — [numeric] ``[XResolution, YResolution]`` in Pixels/Inch
%
% Usage:
%
%   **Example 1** — compute resolution for TIFF saving
%
%   .. code-block:: matlab
%
%      pixSize.x = 0.065; pixSize.y = 0.065; pixSize.units = 'um';
%      resolution = utils.calculateResolution(pixSize);
%

% Updates
% 

switch utils.normalizeUnits(pixSize.units)
    case 'm'
        resolution(1) = 1/pixSize.x*1*0.0254;
        resolution(2) = 1/pixSize.y*1*0.0254;
    case 'cm'
        resolution(1) = 1/pixSize.x*1e2*0.0254;
        resolution(2) = 1/pixSize.y*1e2*0.0254;
    case 'mm'
        resolution(1) = 1/pixSize.x*1e3*0.0254;
        resolution(2) = 1/pixSize.y*1e3*0.0254;
    case 'um'
        resolution(1) = 1/pixSize.x*1e6*0.0254;
        resolution(2) = 1/pixSize.y*1e6*0.0254;
    case 'nm'
        resolution(1) = 1/pixSize.x*1e9*0.0254;
        resolution(2) = 1/pixSize.y*1e9*0.0254;
    otherwise
        resolution(1) = 72;
        resolution(2) = 72;
end
end
