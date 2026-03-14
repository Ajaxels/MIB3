function result = saveBigDataViewerFormat(filename, I, options)
% function result = saveBigDataViewerFormat(filename, I, options)
% Save a dataset in Fiji BigDataViewer (BDV) HDF5 format.
%
% Format description:
%   http://fiji.sc/BigDataViewer#About_the_BigDataViewer_data_format
%
% DATA CONVENTION
%   Input I must be [W, H, C, D, T] — i.e. X/Y already swapped by the
%   caller (HDF5Saver permutes [H,W,D,C,T] → [W,H,C,D,T] before calling).
%   Each colour channel is stored separately under /t{T}/s{C}/{level}/cells
%   as a 3-D dataset [newW, newH, newZ].
%
% NOTES
%   * BDV requires int16 data; uint8 is promoted to uint16 first, then all
%     non-int16 types are reinterpreted via typecast.
%   * Pyramid downsampling uses imresize3 (Image Processing Toolbox R2017a+).
%   * An XML header is NOT written here; call io.HDF5.saveXMLheader with
%     options.Format = 'bdv.hdf5' after this function returns.
%
% Parameters:
%   filename — full path to the output .h5 file
%   I        — [W, H, C, D, T] image array (X/Y pre-swapped by caller)
%   options  — struct with fields:
%     .ChunkSize        [3 x L] chunk sizes per pyramid level (or [3 x 1]
%                       replicated to all levels); default [64;64;64]
%     .Deflate          compression level 0-9; default 0
%     .SubSampling      [3 x L] downsampling factors per level,
%                       e.g. [1 2 4; 1 2 4; 1 2 4]; default [1;1;1]
%     .ResamplingMethod 'nearest'|'bicubic'|'bilinear'; default 'bicubic'
%     .t                time-point start index (for multi-time writing);
%                       default 1
%     .showWaitbar      logical; default true
%     .ParentFigure     handle to the main MIB window (for uiprogressdlg)
%     .ImageDescription (char) BoundingBox metadata string
%     .lutColors        [C x 3] LUT colours (0..1) per channel
%
% Return values:
%   result — 1 = success, 0 = failure
%
% USAGE EXAMPLES
%   @code
%   %% Minimal — single resolution level
%   opts.SubSampling      = [1;1;1];
%   opts.ChunkSize        = [64;64;64];
%   opts.Deflate          = 0;
%   opts.showWaitbar      = false;
%   opts.t                = 1;
%   dataBDV = permute(data_HWDCT, [2 1 4 3 5]);   % [H,W,D,C,T]→[W,H,C,D,T]
%   io.HDF5.saveBigDataViewerFormat('out.h5', dataBDV, opts);
%   io.HDF5.saveXMLheader('out.h5', opts);         % writes out.xml
%   @endcode
%
%   @code
%   %% Three-level pyramid
%   opts.SubSampling = [1 2 4; 1 2 4; 1 2 4];     % [x;y;z] per level
%   opts.ChunkSize   = [64 64 64; 64 64 64; 64 64 64]';  % [3 x 3]
%   @endcode
%
% SEE ALSO
%   io.HDF5.saveXMLheader, io.savers.HDF5Saver

% Updates
%   ported from MIB2 saveBigDataViewerFormat.m (Ilya Belevich) to MIB3 package

result = 0;
if nargin < 3; options = struct(); end

% ---- defaults ----
if ~isfield(options, 'ChunkSize');        options.ChunkSize        = [64; 64; 64]; end
if ~isfield(options, 'Deflate');          options.Deflate          = 0;            end
if ~isfield(options, 'SubSampling');      options.SubSampling      = [1; 1; 1];    end
if ~isfield(options, 'ResamplingMethod'); options.ResamplingMethod = 'bicubic';    end
if ~isfield(options, 't');                options.t                = 1;            end
if ~isfield(options, 'showWaitbar');      options.showWaitbar      = true;         end

[filePath, baseName, ~] = fileparts(filename);
h5Filename = fullfile(filePath, [baseName '.h5']);

% ---- data dimensions (I is [W, H, C, D, T]) ----
dimW   = size(I, 1);   % X (swapped)
dimH   = size(I, 2);   % Y (swapped)
colors = size(I, 3);
depth  = size(I, 4);
timePts = size(I, 5);

noLevels = size(options.SubSampling, 2);
noDims   = size(options.SubSampling, 1);

% ensure ChunkSize is [noDims x noLevels]
if size(options.ChunkSize, 2) ~= noLevels
    options.ChunkSize = repmat(options.ChunkSize(:, 1), [1, noLevels]);
end

% ---- convert to int16 (BDV requirement) ----
if ~isa(I, 'int16')
    if isa(I, 'uint8'); I = uint16(I); end
    I = typecast(I(:), 'int16');
    I = reshape(I, [dimW, dimH, colors, depth, timePts]);
end

% ---- progress dialog ----
wb = [];
curInt = '';
if options.showWaitbar
    if isfield(options, 'ParentFigure') && ~isempty(options.ParentFigure)
        try
            wb = uiprogressdlg(options.ParentFigure, ...
                'Title',   'Saving BigDataViewer HDF5...', ...
                'Message', sprintf('%s\nPlease wait...', h5Filename));
        catch; wb = []; end
    else
        curInt = get(0, 'DefaulttextInterpreter');
        set(0, 'DefaulttextInterpreter', 'none');
        wb = waitbar(0, sprintf('%s\nPlease wait...', h5Filename), ...
            'Name', 'Saving BigDataViewer HDF5...', 'WindowStyle', 'modal');
    end
end

% ---- create HDF5 file structure on first time point ----
if options.t(1) == 1
    if exist(h5Filename, 'file') == 2; delete(h5Filename); end

    for colId = 1:colors
        % /s{cc}/resolutions — [noDims x noLevels] double
        dsName = sprintf('/s%02i/resolutions', colId-1);
        h5create(h5Filename, dsName, [noDims, noLevels], ...
            'Datatype', 'double', 'ChunkSize', [noDims, 1]);
        h5write(h5Filename, dsName, options.SubSampling);

        % /s{cc}/subdivisions — [noDims x noLevels] int32
        dsName = sprintf('/s%02i/subdivisions', colId-1);
        h5create(h5Filename, dsName, [noDims, noLevels], ...
            'Datatype', 'int32', 'ChunkSize', [noDims, 1]);
        h5write(h5Filename, dsName, int32(options.ChunkSize));

        % /s{cc}/color — [3 x 1] int32  (optional)
        if isfield(options, 'lutColors') && size(options.lutColors, 1) >= colId
            dsName = sprintf('/s%02i/color', colId-1);
            h5create(h5Filename, dsName, [noDims, 1], ...
                'Datatype', 'int32', 'ChunkSize', [noDims, 1]);
            h5write(h5Filename, dsName, int32(options.lutColors(colId, :))');
        end
    end

    % /ImageDescription — scalar string dataset
    if isfield(options, 'ImageDescription') && ~isempty(options.ImageDescription)
        file_id  = H5F.open(h5Filename, 'H5F_ACC_RDWR', 'H5P_DEFAULT');
        space_id = H5S.create('H5S_SCALAR');
        stype    = H5T.copy('H5T_C_S1');
        H5T.set_size(stype, numel(options.ImageDescription));
        dset_id  = H5D.create(file_id, '/ImageDescription', stype, space_id, 'H5P_DEFAULT');
        H5D.write(dset_id, stype, 'H5S_ALL', 'H5S_ALL', 'H5P_DEFAULT', options.ImageDescription);
        H5D.close(dset_id);
        H5S.close(space_id);
        H5F.close(file_id);
    end
end

if ~isempty(wb)
    if isa(wb,'matlab.ui.dialog.ProgressDialog'); wb.Value = 0.1;
    else; waitbar(0.1, wb); end
end

% ---- write image data ----
totalOps = timePts * colors * noLevels;
opsDone  = 0;

for timeId = 1:timePts
    timeId2 = options.t(1) + timeId - 1;
    for colId = 1:colors
        for levelId = 1:noLevels
            sf   = options.SubSampling(:, levelId);  % [xFactor; yFactor; zFactor]
            newW = max(1, round(dimW  / sf(1)));
            newH = max(1, round(dimH  / sf(2)));
            newZ = max(1, round(depth / sf(3)));

            vol = squeeze(I(:, :, colId, :, timeId));  % [W, H, D]

            if newW ~= dimW || newH ~= dimH || newZ ~= depth
                % utils.resizeImage3d expects [H, W, D] input — permute from [W,H,D],
                % resize, cast to int16, permute back to [W,H,D].
                resOpts.algorithm   = 'imresize';
                resOpts.method      = options.ResamplingMethod;
                resOpts.height      = newH;
                resOpts.width       = newW;
                resOpts.depth       = newZ;
                resOpts.showWaitbar = ~isempty(wb);
                resOpts.wb          = wb;   % outer loop owns the progress bar
                volP = permute(single(vol), [2 1 3]);          % [H, W, D]
                volP = utils.resizeImage3d(volP, [], resOpts);  % returns [H, W, D] single
                volP = typecast(int16(volP(:)), 'int16');
                vol  = permute(reshape(volP, [newH, newW, newZ]), [2 1 3]);  % [W, H, D]
            end

            dsName  = sprintf('/t%05i/s%02i/%d/cells', timeId2-1, colId-1, levelId-1);
            chunkSz = options.ChunkSize(:, levelId);
            chunkSz(1) = min(chunkSz(1), newW);
            chunkSz(2) = min(chunkSz(2), newH);
            chunkSz(3) = min(chunkSz(3), max(1, newZ));

            h5create(h5Filename, dsName, [newW, newH, newZ], ...
                'Datatype', 'int16', 'ChunkSize', chunkSz(:)', ...
                'Deflate', options.Deflate);
            h5write(h5Filename, dsName, vol);

            opsDone = opsDone + 1;
            if ~isempty(wb)
                val = 0.1 + 0.9 * opsDone / totalOps;
                if isa(wb,'matlab.ui.dialog.ProgressDialog'); wb.Value = val;
                else; waitbar(val, wb); end
            end
        end
    end
end

if ~isempty(wb)
    if ~isa(wb, 'matlab.ui.dialog.ProgressDialog')
        set(0, 'DefaulttextInterpreter', curInt);
    end
    delete(wb);
end

result = 1;
end
