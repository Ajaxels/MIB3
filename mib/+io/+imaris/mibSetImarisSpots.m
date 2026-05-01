% This program is free software: you can redistribute it and/or modify
% it under the terms of the GNU General Public License as published by
% the Free Software Foundation, either version 3 of the License, or
% (at your option) any later version.
%
% This program is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
% GNU General Public License for more details.
% You should have received a copy of the GNU General Public License
% along with this program.  If not, see <https://www.gnu.org/licenses/>

% Author: Ilya Belevich, University of Helsinki (ilya.belevich @ helsinki.fi)
% part of Microscopy Image Browser, http:\\mib.helsinki.fi 
% Date: 25.04.2023

function connImaris = mibSetImarisSpots(spots, connImaris, options)
% MIBSETIMARISSPOTS - Send a spots from MIB to Imaris.
%
% Syntax:
%   .. code-block:: matlab
%
%      connImaris = io.imaris.mibSetImarisSpots(spots, connImaris)
%      connImaris = io.imaris.mibSetImarisSpots(spots, connImaris, options)
%
% Input Arguments:
%   - **spots** — [n×4] matrix of spot coordinates [x, y, z, t]
%   - **connImaris** — *(optional)* handle to an existing Imaris connection
%   - **options** — *(optional)* struct with additional settings:
%
%     - ``.radii`` — *(optional)* [n×1] vector of spot radii; default: ``width/150``
%     - ``.color`` — *(optional)* [1×4] RGBA colour vector (0–1); default red ``[1, 0, 0, 1]``
%     - ``.name`` — (char) name of the spot object (default: ``'mibSpots'``)
%     - ``.dt`` — *(optional)* time step (default: ``1``)
%
% Output Arguments:
%   - **connImaris** — handle to the Imaris connection
%
% .. note::
%    Uses IceImarisConnector bindings. Requires:
%
%    1. Set system environment variable ``IMARISPATH`` to the Imaris installation
%       directory, e.g. ``'c:\tools\science\imaris'``
%    2. Restart MATLAB
%
% **Example** — send spot coordinates to Imaris:
%
%   .. code-block:: matlab
%
%      spots = [1, 1, 1, 1];   % single spot at [x=1, y=1, z=1, t=1]
%      obj.connImaris = io.imaris.mibSetImarisSpots(spots, obj.connImaris);

% Updates
% 25.09.2017 IB updated connection to Imaris

if nargin < 3;     options = struct(); end
if nargin < 2;     connImaris = []; end

if ~isfield(options, 'color'); options.color = [1, 0, 0, 1]; end    % use red color by default
if ~isfield(options, 'name'); options.name = 'mibSpots'; end        % use mibSpots name by default
if ~isfield(options, 'radii')   % use radii as 1/150th of width
    minX = min(spots);
    maxX = max(spots);
    options.radii = zeros([size(spots, 1) 1]) + (maxX(1)-minX(1))/150; 
end          
if ~isfield(options, 'dt')   % time step
    options.dt = 1;
end


% establish connection to Imaris
connImaris = io.imaris.connectToImaris(connImaris);
if isempty(connImaris); return; end

wb = waitbar(0, 'Please wait...', 'Name', 'Export spots to Imaris');

% reformat spots matrix to extract time
if size(spots, 2) == 4  % [x,y,z,t xn] matrix
    timeVec = spots(:,4)-1;
    spots = spots(:,1:3);
elseif size(spots, 2) == 3 % [x,y,z xn] matrix
    timeVec = zeros([size(spots, 1) 1])+1;
end

connImaris.createAndSetSpots(spots, timeVec, options.radii, options.name, options.color);

delete(wb);
end
