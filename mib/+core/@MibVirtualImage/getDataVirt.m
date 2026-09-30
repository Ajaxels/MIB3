function dataset = getDataVirt(obj, type, orient, colChannel, options)
% GETDATAVIRT - Read a virtual dataset (BioFormats or HDF5) from disk on demand.
%
% Syntax:
%   .. code-block:: matlab
%
%       dataset = obj.getDataVirt(type, orient, colChannel, options)
%
% Input Arguments:
%   - **type** - [char] layer type to retrieve; only ``'image'`` is supported
%   - **orient** - *(optional)* [numeric] orientation of returned dataset:
%
%     - ``1`` - ``zx`` plane: output ``[z, x, y, c, t]`` (rows = Z, columns = X)
%     - ``2`` - ``yz`` plane: output ``[y, z, x, c, t]``
%     - ``3`` - ``yx`` plane: output ``[y, x, z, c, t]`` (default)
%
%   - **colChannel** - *(optional)* [numeric vector] colour channel indices;
%     ``[]`` = all channels
%   - **options** - *(optional)* [struct] with optional fields:
%
%     - ``.y`` - [numeric] ``[ymin ymax]`` pixel range
%     - ``.x`` - [numeric] ``[xmin xmax]`` pixel range
%     - ``.z`` - [numeric] ``[zmin zmax]`` slice range
%     - ``.t`` - [numeric] ``[tmin tmax]`` time-point range
%     - ``.level`` - [numeric] pyramid level index (default: ``1`` = full resolution)
%     - ``.showWaitbar`` - [logical or []] override waitbar display; ``[]`` = auto
%
% Output Arguments:
%   - **dataset** - [numeric array] 5D data in MIB3 order:
%
%     - ``[y, x, z, c, t]`` for ``orient==3`` (default)
%     - ``[z, x, y, c, t]`` for ``orient==1`` (rows = Z, columns = X)
%     - ``[y, z, x, c, t]`` for ``orient==2``
%
% **Example 1** - read full YX dataset:
%
%   .. code-block:: matlab
%
%      dataset = obj.getDataVirt('image');
%
% **Example 2** - read channel 2 in YX orientation:
%
%   .. code-block:: matlab
%
%      dataset = obj.getDataVirt('image', 3, 2, options);
%
if nargin < 5; options = struct(); end
if nargin < 4; colChannel = []; end
if nargin < 3; orient = []; end
if nargin < 2; type = 'image'; end

if isempty(orient); orient = 3; end

showWaitbar = 0;

if ~isfield(options, 'level'); options.level = 1; end
if ~isfield(options, 'showWaitbar'); options.showWaitbar = []; end

level = 2^(options.level - 1);   % resampling factor

if strcmp(type, 'image')
    if isempty(colChannel); colChannel = 1:obj.colors; end
end

% --- coordinate ranges in original dataset --------------------------------
Xlim = [1  floor(obj.width  / level)];
Ylim = [1  floor(obj.height / level)];
Zlim = [1  obj.depth];
Tlim = [1  obj.time];

if orient == 1       % zx: rows = Z, columns = X, slice = Y
    if isfield(options, 'x'); Xlim = floor(options.x(1, :) / level); end
    if isfield(options, 'y'); Zlim = options.y(1, :); end
    if isfield(options, 'z'); Ylim = floor(options.z(1, :) / level); end
elseif orient == 2   % yz
    if isfield(options, 'x'); Zlim = options.x(1, :); end
    if isfield(options, 'y'); Ylim = floor(options.y(1, :) / level); end
    if isfield(options, 'z'); Xlim = floor(options.z(1, :) / level); end
elseif orient == 3   % yx  (MIB3 default; MIB2 used orient==4)
    if isfield(options, 'x'); Xlim = floor(options.x(1, :) / level); end
    if isfield(options, 'y'); Ylim = floor(options.y(1, :) / level); end
    if isfield(options, 'z'); Zlim = options.z(1, :); end
end

if isfield(options, 't')
    if numel(options.t) == 1; options.t = [options.t  options.t]; end
    Tlim = options.t;
end

% clamp to valid range
Xlim = [max([Xlim(1) 1])  min([Xlim(2) floor(obj.width  / level)])];
Ylim = [max([Ylim(1) 1])  min([Ylim(2) floor(obj.height / level)])];
Zlim = [max([Zlim(1) 1])  min([Zlim(2) obj.depth])];
Tlim = [max([Tlim(1) 1])  min([Tlim(2) obj.time])];

% --- waitbar --------------------------------------------------------------
if isempty(options.showWaitbar)
    if Tlim(2) - Tlim(1) > 0 || Zlim(2) - Zlim(1) > 0
        wb = waitbar(0, sprintf('Loading the dataset\nPlease wait...'));
        showWaitbar = 1;
    end
elseif options.showWaitbar == 1
    wb = waitbar(0, sprintf('Loading the dataset\nPlease wait...'));
    showWaitbar = 1;
end

% --- read image data ------------------------------------------------------
if strcmp(type, 'image')
    readerId = obj.Virtual.readerId(Zlim(1):Zlim(2));

    % mixing reader types within one request is not supported
    if numel(readerId) > 1 && numel(unique(obj.Virtual.objectType(readerId))) > 1
        errordlg('Image files were selected using multiple readers; combining such files is not yet possible.', 'Multiple readers');
        dataset = [];
        return;
    end

    % Allocate output in MIB3 order [y, x, z, c, t]
    nY  = Ylim(2) - Ylim(1) + 1;
    nX  = Xlim(2) - Xlim(1) + 1;
    nZ  = Zlim(2) - Zlim(1) + 1;
    nC  = numel(colChannel);
    nT  = Tlim(2) - Tlim(1) + 1;
    dataset = zeros([nY, nX, nZ, nC, nT], obj.dataClass);

    switch obj.Virtual.objectType{readerId(1)}

        case {'matlab.hdf5', 'hdf5_image'}
            % Group consecutive slices that belong to the same source file
            % and read each group as a single h5read call.
            [uniqueFileIds, uniquePos, ~] = unique(readerId, 'stable');
            uniquePos(end+1) = nZ + 1;   % sentinel for range calculation

            for gi = 1:numel(uniqueFileIds)
                fileIdx = uniqueFileIds(gi);

                % output z-range for this group (1-based within the request)
                z1Out = uniquePos(gi);
                z2Out = uniquePos(gi + 1) - 1;

                % input z-range within the source file (1-based within the file)
                if gi == 1
                    z1In = Zlim(1) - sum(obj.Virtual.slicesPerFile(1:fileIdx - 1));
                else
                    z1In = 1;
                end
                zCount = z2Out - z1Out + 1;

                loader = obj.getOrCreateLoader(fileIdx);
                % readRegion returns [nY, nX, zCount, obj.colors, nT] in [y,x,z,c,t]
                block = loader.readRegion(Ylim, Xlim, z1In, zCount, obj.colors, Tlim, obj.dataClass);
                dataset(:, :, z1Out:z2Out, :, :) = block(:, :, :, colChannel, :);
            end

        case 'bioformats'
            % BioFormats reads one XY plane at a time.
            % Readers are opened lazily and kept open across calls (see
            % BioFormatsVirtualLoader) to avoid re-opening for every slice.
            maxT = nT;
            for t = 1:maxT
                timepoint = Tlim(1) + t - 2;   % 0-based for BioFormats getIndex
                for z = 1:nZ
                    fileIdx = readerId(z);
                    planeId = Zlim(1) + z - 1 - sum(obj.Virtual.slicesPerFile(1:fileIdx - 1));

                    loader = obj.getOrCreateLoader(fileIdx);
                    % readPlane returns [nY, nX, nC] for the requested channels
                    dataset(:, :, z, :, t) = loader.readPlane( ...
                        Ylim, Xlim, planeId, colChannel, timepoint, obj.dataClass);
                end
                if showWaitbar; waitbar(t / maxT, wb); end
            end

    end

else
    % non-image layers are not stored in virtual mode
    dataset = zeros([Ylim(2)-Ylim(1)+1, Xlim(2)-Xlim(1)+1, Zlim(2)-Zlim(1)+1, Tlim(2)-Tlim(1)+1], 'uint8');
end

% --- apply orientation permutation ----------------------------------------
% dataset is in MIB3 order [y, x, z, c, t] at this point
if orient == 1       % zx: [y,x,z,c,t] -> [z,x,y,c,t]
    dataset = permute(dataset, [3 2 1 4 5]);
elseif orient == 2   % yz: [y,x,z,c,t] -> [y,z,x,c,t]
    dataset = permute(dataset, [1 3 2 4 5]);
% orient == 3 (yx): no permutation needed
end

if showWaitbar; delete(wb); end
end
