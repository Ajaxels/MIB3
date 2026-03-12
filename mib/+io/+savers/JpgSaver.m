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
% Date: 2025

classdef JpgSaver < io.savers.BaseSaver
    % classdef JpgSaver < io.savers.BaseSaver
    % Saver for JPEG output — one file per Z-slice (always a 2-D sequence).
    %
    % JPEG is a lossy format suitable for display purposes; it is NOT
    % recommended for quantitative analysis.  uint16 multichannel data
    % cannot be saved as JPEG (MATLAB limitation); use uint8 RGB only.
    %
    % Handled format string:
    %   'Joint Photographic Experts Group (*.jpg)'
    %
    % DATA DIMENSIONS
    %   Input  data : [H, W, D, C, T]
    %   imwrite call: [H, W, C] per 2-D slice (C ≤ 3, class == uint8)
    %
    % NOTES
    %   * options.Quality  (0–100, default 90): JPEG quality factor.
    %   * options.Compression ('lossy'|'lossless', default 'lossy').
    %   * JPEG does not support indexed colourmaps; 'indexed' colour images
    %     will be saved using the raw index values as greyscale.
    %
    % USAGE EXAMPLES
    %   @code
    %   %% 1. Direct saver use
    %   saver = io.SaverFactory.create('Joint Photographic Experts Group (*.jpg)');
    %
    %   opts.Format      = 'Joint Photographic Experts Group (*.jpg)';
    %   opts.Quality     = 90;
    %   opts.Compression = 'lossy';
    %   opts.showWaitbar = false;
    %   opts.silent      = true;
    %   opts.overwrite   = true;
    %   opts.FilenameGenerator = 'Use sequential filename';
    %
    %   meta.filename         = 'source.tif';
    %   meta.colorType        = 'multichannel';
    %   meta.lutColors        = eye(3);
    %   meta.dataClass        = 'uint8';
    %   meta.maxInt           = 255;
    %   meta.sliceName        = {};
    %   meta.imageDescription = '';
    %
    %   data = uint8(rand(256,256,10,3,1)*255);   % [H W D C T], RGB
    %   fnOut = saver.save(data, meta, '/output/slice.jpg', opts);
    %   % Generates /output/slice_01.jpg … /output/slice_10.jpg
    %   @endcode
    %
    %   @code
    %   %% 2. Via MibModel with quality control
    %   BatchOpt.LayerType       = {'image'};
    %   BatchOpt.Format          = {'Joint Photographic Experts Group (*.jpg)'};
    %   BatchOpt.Quality         = '90';
    %   BatchOpt.Compression     = 'lossy';
    %   BatchOpt.OutputDirectoryPolicy = {'Full path'};
    %   BatchOpt.DestinationDirectory  = '/output';
    %   BatchOpt.FilenamePolicy  = {'Use existing name'};
    %   BatchOpt.showWaitbar     = false;
    %   BatchOpt.mibBatchTooltip.LayerType = '';
    %   model.save('image', [], BatchOpt);
    %   @endcode
    %
    % SEE ALSO
    %   io.SaverFactory, io.savers.BaseSaver, io.savers.PngSaver

    methods

        function obj = JpgSaver(options)
            if nargin < 1; options = struct(); end
            obj.Options = options;
            obj.initBaseProps(options);
        end

        function formats = getSupportedFormats(~)
            formats = {'Joint Photographic Experts Group (*.jpg)'};
        end

        function fnOut = save(obj, data, metadata, filename, options)
            % function fnOut = save(obj, data, metadata, filename, options)
            % Write JPEG 2-D sequence (one file per Z-slice × time point).
            %
            % Parameters:
            %   data     — [H, W, D, C, T]  uint8 (or uint16 greyscale)
            %   metadata — struct; used fields:
            %     .colorType        — data type (multichannel RGB must be uint8)
            %     .sliceName        — (optional) per-slice source filenames
            %     .imageDescription — (optional) JPEG Comment tag
            %   filename — full path template, e.g. '/out/frame.jpg'
            %   options  — struct; additionally used:
            %     .Quality     — (double 0–100, default 90)
            %     .Compression — (char) 'lossy' | 'lossless', default 'lossy'
            %
            % Return values:
            %   fnOut — cell of char with all saved paths,
            %           or single char if only one slice

            fnOut = [];

            % --- defaults ---
            if ~isfield(options, 'showWaitbar');       options.showWaitbar    = true;   end
            if ~isfield(options, 'silent');            options.silent         = false;  end
            if ~isfield(options, 'overwrite');         options.overwrite      = true;   end
            if ~isfield(options, 'FilenameGenerator'); options.FilenameGenerator = 'Use sequential filename'; end
            if ~isfield(options, 'Quality');           options.Quality        = 90;     end
            if ~isfield(options, 'Compression');       options.Compression    = 'lossy'; end

            comment = '';
            if isfield(metadata,'imageDescription'); comment = metadata.imageDescription; end

            [pathStr, baseName, ext] = obj.splitFilename(filename);
            if isempty(ext); ext = '.jpg'; end
            if isempty(pathStr); pathStr = pwd; end
            if exist(pathStr,'dir') ~= 7; mkdir(pathStr); end

            [~, ~, nD, nC, nT] = size(data);

            % JPEG supports ≤3 channels; multichannel must be uint8
            if nC > 3
                warning('JpgSaver:tooManyChannels', ...
                    'JPEG supports ≤3 colour channels; got %d.', nC);
                return;
            end
            if nC > 1 && ~isa(data,'uint8')
                warning('JpgSaver:wrongClass', ...
                    'Multichannel JPEG requires uint8; got %s. Skipping.', class(data));
                return;
            end

            % --- build output names ---
            sliceNames = obj.buildSliceNames(baseName, pathStr, nD, ext, options, metadata);

            % --- progress ---
            wb = [];
            if options.showWaitbar
                wb = obj.createProgressDialog('Saving images...', sprintf('Saving JPEG — %s', baseName), false);
            end

            allFn = {};
            done  = 0;
            total = nD * nT;

            try
                for t = 1:nT
                    for z = 1:nD
                        img2D = squeeze(data(:,:,z,:,t));  % [H, W, C]

                        if nT > 1
                            [~, sn, se] = fileparts(sliceNames{z});
                            outName = fullfile(pathStr, sprintf('%s_T%03d%s', sn, t, se));
                        else
                            outName = sliceNames{z};
                        end

                        imwrite(img2D, outName, 'jpg', ...
                            'Comment', comment, ...
                            'Mode',    options.Compression, ...
                            'Quality', options.Quality);

                        allFn{end+1} = outName; %#ok<AGROW>
                        done = done + 1;
                        if ~isempty(wb); wb.Value = done/total; end
                    end
                end
            catch ME
                if ~isempty(wb); delete(wb); end
                rethrow(ME);
            end
            if ~isempty(wb); delete(wb); end

            fprintf('JpgSaver: saved %d file(s) → %s\n', numel(allFn), pathStr);
            if isscalar(allFn)
                fnOut = allFn{1};
            else
                fnOut = allFn(:);
            end
        end

    end
end
