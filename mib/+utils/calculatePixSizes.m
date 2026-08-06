function pixSize = calculatePixSizes(resolution, unitFrom, unitTo)
% CALCULATEPIXSIZES - Recalculate pixel size (width, height) of the dataset to new units.
%
% Syntax:
%
%   .. code-block:: matlab
%
%      pixSize = calculatePixSizes(resolution, unitFrom, unitTo)
%
% Input Arguments:
%   - **resolution** - [numeric] current resolution of the dataset ``[XResolution, YResolution]``
%   - **unitFrom** - [char] source units: ``'Inch'``, ``'Centimeter'``, ``'Meter'``
%   - **unitTo** - [char] desired units: ``'m'``, ``'cm'``, ``'mm'``, ``'um'``, ``'nm'``
%
% Output Arguments:
%   - **pixSize** - struct with updated pixel sizes:
%
%     - ``.x`` - physical width of the pixel
%     - ``.y`` - physical height of the pixel
%
% Usage:
%
%   **Example 1** - convert 72 dpi resolution to micrometres
%
%   .. code-block:: matlab
%
%      pixSize = utils.calculatePixSizes([72, 72], 'Inch', 'um');
%

% Updates
% 

switch unitFrom     % get coef for conversion to meters
    case 'Inch'
        coef = 1/.0254;
    case 'Centimeter'
        coef = 1e2;
    case 'Meter'
        coef = 1;
    otherwise
        coef = 1;
end
% calculate pixel sizes in program units
switch unitTo
    case 'm'
        pixSize.x = 1/(resolution(1)*coef);
        pixSize.y = 1/(resolution(2)*coef);
    case 'cm'
        pixSize.x = 1e2/(resolution(1)*coef);
        pixSize.y = 1e2/(resolution(2)*coef);
    case 'mm'
        pixSize.x = 1e3/(resolution(1)*coef);
        pixSize.y = 1e3/(resolution(2)*coef);
    case 'um'
        pixSize.x = 1e6/(resolution(1)*coef);
        pixSize.y = 1e6/(resolution(2)*coef);
    case 'nm'
        pixSize.x = 1e9/(resolution(1)*coef);
        pixSize.y = 1e9/(resolution(2)*coef);
end
end
