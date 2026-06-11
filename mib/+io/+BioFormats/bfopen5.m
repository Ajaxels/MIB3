function [result] = bfopen5(r, seriesNumber, sliceNo, options)
% BFOPEN5 - Open microscopy images in MATLAB using Bio-Formats with Memoizer support.
%
% Syntax:
%   .. code-block:: matlab
%
%      result = io.BioFormats.bfopen5(r, seriesNumber)
%      result = io.BioFormats.bfopen5(r, seriesNumber, sliceNo, options)
%
% Modified from the original bfopen.m by Ilya Belevich.
% Returns the selected dataset from a Bio-Formats Memoizer reader.
%
% Input Arguments:
%   - **r** — handle to a Memoizer opened as:
%
%     .. code-block:: matlab
%
%        r = loci.formats.Memoizer(bfGetReader(), 0);
%        r.setId(filename);
%        r.close();   % optionally
%
%     When the Memoizer class is used, ``r`` won't be closed at the end of the
%     function. Alternatively, pass a ``filename`` string to use with ``setId``.
%   - **seriesNumber** — series number to load, starting from ``1``
%   - **sliceNo** — *(optional)* desired slice number from the series
%   - **options** — *(optional)* struct with fields:
%
%     - ``.bioFormatsMemoizerMemoDir`` — directory to store Memoizer memo files
%     - ``.dimensionOrder`` — (char) output order of dimensions:
%
%       - ``'XYZCT'`` — default
%       - ``'XYCZT'``
%       - ``'XYTZC'``
%       - ``'XYZTC'``
%
%     - ``.x1`` — starting x position
%     - ``.y1`` — starting y position
%     - ``.z1`` — starting z position
%     - ``.dx`` — width
%     - ``.dy`` — height
%     - ``.dz`` — depth
%     - ``.waitbarHandle`` — *(optional)* handle to an existing waitbar; ``[]`` if none
%     - ``.waitbarUpdateFrequency`` — *(optional)* frequency to update the waitbar
%
% Output Arguments:
%   - **result** — struct with the selected series:
%
%     - ``.img`` — image array ``[height, width, depth, color, time]``; dims
%       re-projected per ``options.dimensionOrder``
%     - ``.ColorType`` — ``'grayscale'``, ``'multichannel'``, or ``'indexed'``
%     - ``.ColorMap`` — colormap for indexed images
%
% .. note::
%   Portions of this code were adapted from:
%   http://www.mathworks.com/support/solutions/en/data/1-2WPAYR/
%
%   This method is ~1.5×–2.5× slower than Bio-Formats's command line showinf tool,
%   due to overhead from copying arrays.
%
%   Internet Explorer sometimes erroneously renames the Bio-Formats library to
%   ``loci_tools.zip`` — if this happens, rename it back to ``loci_tools.jar``.
%
%   Thanks to all who offered suggestions and improvements:
%     * Ville Rantanen
%     * Brett Shoelson
%     * Martin Offterdinger
%     * Tony Collins
%     * Cris Luengo
%     * Arnon Lieber
%     * Jimmy Fong
%   NB: Internet Explorer sometimes erroneously renames the Bio-Formats library
%     to loci_tools.zip. If this happens, rename it back to loci_tools.jar.
%
% Updates:
%   - 30.01.2019 Ilya Belevich, adaptation for use with Memoizer
%   - 13.12.2023 Ilya Belevich, added cancel upon waitbar cancel click
%   - 07.01.2026 Ilya Belevich, switched to [Y X Z C T] outputs, renamed .ColorType truecolor->multichannel
%

if nargin < 4;     options = struct;   end
if nargin < 3;     sliceNo = NaN;   end

% link the Bio-Formats Java library on the first use (lazy, skipped at MIB startup)
utils.ensureJavaLibraries({'bioformats'});

% Disable logging
bfInitLogging('ERROR');

if ~isfield(options, 'dimensionOrder'); options.dimensionOrder = 'XYZCT'; end

% check whether the waitbar handle is provided
if ~isfield(options, 'waitbarHandle'); options.waitbarHandle = []; end
% define update frequency for the waitbar
if ~isfield(options, 'waitbarUpdateFrequency'); options.waitbarUpdateFrequency = 1; end

if isa(r, 'loci.formats.Memoizer')  % r is a filename
   filename = [];
else
    filename = r;
    if isfield(options, 'bioFormatsMemoizerMemoDir')
        r = loci.formats.Memoizer(bfGetReader(), 0, java.io.File(options.bioFormatsMemoizerMemoDir));
    else
        r = loci.formats.Memoizer(bfGetReader(), 0);
    end
    r.setId(filename);
end
r.setSeries(seriesNumber - 1);

if ~isfield(options, 'x1')
    Width = r.getSizeX();
    Height = r.getSizeY();
else
    Width = options.dx;
    Height = options.dy;
end
Colors = r.getSizeC();
Time = 1;

if isfield(options, 'dz')
    ZStacks = options.dz;
    sliceNo = NaN; % override sliceNo when options.dz, options.z1 are provided
else
    if isnan(sliceNo)
        if r.getSizeZ() == 1 && r.getSizeT() > 1
            % swap T and Z
            ZStacks = r.getSizeT();
            % swap options.dimensionOrder
            [options.dimensionOrder(options.dimensionOrder=='T'), options.dimensionOrder(options.dimensionOrder=='Z')] = deal('Z', 'T');
        else
            ZStacks = r.getSizeZ();
            Time = r.getSizeT();
        end
    else
        ZStacks = 1;
    end
end

bpp = r.getBitsPerPixel();
if bpp <= 8
    ImageClassType = 'uint8';
elseif bpp <= 16
    ImageClassType = 'uint16';
elseif bpp <= 32
    ImageClassType = 'uint32';
else
    ImageClassType = 'double';
end


% switch options.dimensionOrder
%     case 'XYZCT'
%         result.img = zeros([Height, Width, ZStacks, Colors, Time], ImageClassType);
%     case 'XYZTC'
%         result.img = zeros([Height, Width, ZStacks, Time, Colors], ImageClassType);
%     case 'XYCZT'
%         result.img = zeros([Height, Width, ZStacks, Colors, Time], ImageClassType);
%     case 'XYTZC'
%         result.img = zeros([Height, Width, Time, ZStacks, Colors], ImageClassType);
%     otherwise
%         fprintf('io.BioFormats.bfopen5: options.dimensionOrder is missing or wrong!\nCancelling!');
%         return;
% end
result.img = zeros([Height, Width, ZStacks, Colors, Time], ImageClassType);

if ~isfield(options, 'x1')
    fprintf('Reading series #%d', seriesNumber);
end

pixelType = r.getPixelType();
bpp = loci.formats.FormatTools.getBytesPerPixel(pixelType);

if isfield(options, 'dz')
    startSlice = options.z1*Colors-(Colors-1);
    endSlice = (options.z1+options.dz-1)*Colors;
    if endSlice > r.getImageCount()
        fprintf('bfopen4: Wrong slice number!\nCancelling!');
        return;
    end
else
    if isnan(sliceNo)
        startSlice = 1;
        endSlice = r.getImageCount();
    else
        startSlice = sliceNo*Colors-(Colors-1);
        endSlice = sliceNo*Colors;
        if endSlice > r.getImageCount()
            fprintf('io.BioFormats.bfopen5: Wrong slice number!\nCancelling!');
            return;
        end
    end
end

colorID = 1;
sliceID = 1;
timeID = 1;

% define number of slices
noSlices = endSlice-startSlice+1;

result.ColorType = NaN;
index = 1;
for i = startSlice:endSlice
    % different color channels loaded as a list, so they have to be
    % assigned to the proper z-slices
    if ~isfield(options, 'x1')
        if mod(index+1, 72) == 1
            fprintf('\n    ');
        end
        if i>1; fprintf('.'); end
    end

    if ~isfield(options, 'x1')
        arr = bfGetPlane(r, i);    
    else
        arr = bfGetPlane(r, i, options.x1, options.y1, options.dx, options.dy);
    end
    
    % convert MRC int8 to uint8
    if bpp == 1 && isa(arr(1), 'int8')
        arr = int16(arr);
        arr(arr<0) = arr(arr<0) + 256;
        arr = uint8(arr);
    end
    
    % save image plane and label into the list
    switch options.dimensionOrder
        case 'XYZCT'
            result.img(:, :, sliceID, colorID, timeID) = arr;
            sliceID = sliceID + 1;
            if sliceID > ZStacks
                sliceID = 1;
                colorID = colorID + 1;
            end
            if colorID > Colors
                colorID = 1;
                timeID = timeID + 1;
            end
        case 'XYZTC'
            result.img(:, :, sliceID, timeID, colorID) = arr;
            sliceID = sliceID + 1;
            if sliceID > ZStacks
                sliceID = 1;
                timeID = timeID + 1;
            end
            if timeID > Time
                timeID = 1;
                colorID = colorID + 1;
            end
        case 'XYCZT'
            % checked
            result.img(:, :, sliceID, colorID, timeID) = arr;
            colorID = colorID + 1;
            if colorID > Colors
                colorID = 1;
                sliceID = sliceID + 1;
            end
            if sliceID > ZStacks
                sliceID = 1;
                timeID = timeID + 1;
            end
            % result.img(:, :, colorID, sliceID, timeID) = arr;
            % colorID = colorID + 1;
            % if colorID > Colors
            %     colorID = 1;
            %     sliceID = sliceID + 1;
            % end
            % if sliceID > ZStacks
            %     sliceID = 1;
            %     timeID = timeID + 1;
            % end
        case 'XYTZC'
            % checked
            result.img(:, :, sliceID, colorID, timeID) = arr;
            timeID = timeID + 1;
            if timeID > Time
                timeID = 1;
                sliceID = sliceID + 1;
            end
            if sliceID > ZStacks
                sliceID = 1;
                colorID = colorID + 1;
            end
    end


    % update waitbar
    if ~isempty(options.waitbarHandle) && mod(index, options.waitbarUpdateFrequency)==0
        if options.waitbarHandle.CancelRequested
            result = [];
            delete(options.waitbarHandle);
            fprintf('\n');
            return;
        end
        options.waitbarHandle.Value = index/noSlices;
    end

    index = index + 1;
end

if isnan(result.ColorType)
    result.ColorMap = NaN;
    if Colors == 1
        result.ColorType = 'grayscale';
    else
        result.ColorType = 'multichannel';
    end
else
    msgbox('Indexed color type, Not really tested!','Warning!','warn');
end
% % extract metadata table for this series
%metadataList = r.getMetadata(); % for old bio-formats
% metadataList = r.getSeriesMetadata(); % for new bio-formats

% % save images and metadata into our master series list
% result{s, 1} = imageList;
% result{s, 2} = metadataList;
% result{s, 3} = colorMaps;
% result{s, 4} = r.getMetadataStore();
if ~isfield(options, 'x1');     fprintf('\n');  end
if ~isempty(filename)
    r.close();
end

end
