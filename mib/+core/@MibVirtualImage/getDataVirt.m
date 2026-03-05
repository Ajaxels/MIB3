function dataset = getDataVirt(obj, type, orient, colChannel, options)
% function dataset = getDataVirt(obj, type, orient, colChannel, options)
% Read a virtual dataset (BioFormats or HDF5) from disk on demand.
%
% Ported from MIB2/@MibImage/getDataVirt with the following adaptations:
%   - obj.data{} instead of obj.img{}
%   - obj.dataClass instead of obj.meta('imgClass')
%   - YX orientation is 3 (MIB3) not 4 (MIB2)
%   - Output dimension order [y, x, z, c, t] (MIB3) not [y, x, c, z, t] (MIB2)
%   - colChannel [] means all channels (MIB3) instead of NaN (MIB2)
%
% Parameters:
% type: type of layer to retrieve — only 'image' is supported
% orient: [@em optional], orientation of returned dataset
%   @li 1 — xz: output [x, z, y, c, t]
%   @li 2 — yz: output [y, z, x, c, t]
%   @li 3 — yx: output [y, x, z, c, t]  (@b default)
% colChannel: [@em optional], vector of colour channel indices;
%             [] = all channels
% options: [@em optional], struct with optional fields:
%   @li .y  — [ymin ymax] pixel range
%   @li .x  — [xmin xmax] pixel range
%   @li .z  — [zmin zmax] slice range
%   @li .t  — [tmin tmax] time-point range
%   @li .level        — pyramid level index (default 1 = full resolution)
%   @li .showWaitbar  — override waitbar display ([] = auto)
%
% Return values:
% dataset: 5D array [y, x, z, c, t] for orient==3;
%          [x, z, y, c, t] for orient==1;
%          [y, z, x, c, t] for orient==2
%|
% @b Examples:
% @code dataset = obj.getDataVirt('image');                       // full YX dataset @endcode
% @code dataset = obj.getDataVirt('image', 3, 2, options);       // channel 2, YX @endcode

%% Updates
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

if orient == 1       % xz
    if isfield(options, 'x'); Zlim = options.x(1, :); end
    if isfield(options, 'z'); Ylim = floor(options.z(1, :) / level); end
    if isfield(options, 'y'); Xlim = floor(options.y(1, :) / level); end
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
    if numel(readerId) > 1
        if numel(unique(obj.Virtual.objectType(readerId))) > 1
            errordlg('Image files were selected using multiple readers; combining such files is not yet possible.', 'Multiple readers');
            dataset = [];
            return;
        end
    end

    switch obj.Virtual.objectType{readerId(1)}

        case {'matlab.hdf5', 'hdf5_image'}
            % allocate in MIB2 order [y, x, c, z, t] — h5read returns [y,x,c,z,t]
            dataset = zeros([Ylim(2)-Ylim(1)+1, Xlim(2)-Xlim(1)+1, obj.colors, Zlim(2)-Zlim(1)+1, Tlim(2)-Tlim(1)+1], obj.dataClass);

            [uniqueVal, uniquePos, ~] = unique(readerId);
            uniquePos(end+1) = Zlim(2) - Zlim(1) + 2;
            readerId = uniqueVal;

            for indexVal = 1:numel(uniqueVal)
                z2Out = uniquePos(indexVal + 1) - 1;
                z1Out = z2Out - (uniquePos(indexVal + 1) - uniquePos(indexVal)) + 1;

                if indexVal == 1
                    z1In = Zlim(1) - sum(obj.Virtual.slicesPerFile(1:readerId(indexVal) - 1));
                else
                    z1In = 1;
                end
                zIn_noPoints = z2Out - z1Out + 1;

                % h5read returns [y, x, c, z, t]
                dataset(:, :, :, z1Out:z2Out, :) = h5read( ...
                    obj.data{readerId(indexVal)}, ...
                    obj.Virtual.seriesName{readerId(indexVal)}, ...
                    [Ylim(1)            Xlim(1)            1           z1In         Tlim(1)], ...
                    [Ylim(2)-Ylim(1)+1  Xlim(2)-Xlim(1)+1  obj.colors  zIn_noPoints  Tlim(2)-Tlim(1)+1]);
            end
            dataset = dataset(:, :, colChannel, :, :);

        case 'bioformats'
            % allocate in MIB2 order [y, x, c, z, t]
            dataset = zeros([Ylim(2)-Ylim(1)+1, Xlim(2)-Xlim(1)+1, numel(colChannel), Zlim(2)-Zlim(1)+1, Tlim(2)-Tlim(1)+1], obj.dataClass);

            maxT = Tlim(2) - Tlim(1) + 1;
            for t = 1:maxT
                timepoint = Tlim(1) + t - 2;
                for z = 1:Zlim(2) - Zlim(1) + 1
                    r = loci.formats.Memoizer(bfGetReader(), 0, java.io.File(obj.BioFormatsMemoizerMemoDir));
                    r.setId(obj.data{readerId(z)});
                    r.setSeries(obj.Virtual.seriesName{readerId(z)} - 1);

                    planeId = Zlim(1) + z - 1 - sum(obj.Virtual.slicesPerFile(1:readerId(z) - 1));

                    for colCh = 1:numel(colChannel)
                        iPlane = r.getIndex(planeId - 1, colChannel(colCh) - 1, timepoint) + 1;
                        cPlane = bfGetPlane(r, iPlane, Xlim(1), Ylim(1), Xlim(2)-Xlim(1)+1, Ylim(2)-Ylim(1)+1);
                        if isa(cPlane(1), 'int8')
                            cPlane = int16(cPlane);
                            cPlane(cPlane < 0) = cPlane(cPlane < 0) + 256;
                            dataset(:, :, colCh, z, t) = cPlane;
                        else
                            dataset(:, :, colCh, z, t) = cPlane;
                        end
                    end
                end
                if showWaitbar; waitbar(t / maxT, wb); end
                r.close();
            end

    end

    % --- convert MIB2 dim order [y,x,c,z,t] -> MIB3 [y,x,z,c,t] ---------
    dataset = permute(dataset, [1 2 4 3 5]);

else
    % non-image layers are not stored in virtual mode
    dataset = zeros([Ylim(2)-Ylim(1)+1, Xlim(2)-Xlim(1)+1, Zlim(2)-Zlim(1)+1, Tlim(2)-Tlim(1)+1], 'uint8');
end

% --- apply orientation permutation ----------------------------------------
if orient == 1       % xz: [y,x,z,c,t] -> [x,z,y,c,t]
    dataset = permute(dataset, [2 3 1 4 5]);
elseif orient == 2   % yz: [y,x,z,c,t] -> [y,z,x,c,t]
    dataset = permute(dataset, [1 3 2 4 5]);
% orient == 3 (yx): no permutation needed

end

if showWaitbar; delete(wb); end
end
