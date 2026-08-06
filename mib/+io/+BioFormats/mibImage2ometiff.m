function [result, options] = mibImage2ometiff(filename, imageS, options)
% MIBIMAGE2OMETIFF - Save image in OME.TIF format - either as a single 5D file or a 2D sequence.
%
% Syntax:
%   .. code-block:: matlab
%
%      [result, options] = io.BioFormats.mibImage2ometiff(filename, imageS)
%      [result, options] = io.BioFormats.mibImage2ometiff(filename, imageS, options)
%
% Input Arguments:
%   - **filename** - full path for the output file (extension forced to ``.ome.tiff``)
%   - **imageS** - dataset [height, width, color_channels, z_slices, time]
%   - **options** - *(optional)* struct with fields:
%
%     - ``.pixSize`` - MIB pixel-size struct with fields ``.x``, ``.y``, ``.z``, ``.t``,
%       ``.units``, ``.tunits``; default: all ``1``, units ``'um'``, tunits ``'s'``
%     - ``.lutColors`` - [C×3] LUT colour matrix (unused in 2D imwrite path)
%     - ``.ImageDescription`` - (char or cell-string) description embedded in the file
%       (default: ``''``)
%     - ``.DatasetType`` - ``'image'`` (default) or ``'model'``
%     - ``.Saving3d`` - ``'5D'`` (default): write all slices into one OME-TIFF via
%       ``bfsave``; ``'2D'``: write each z-slice as a separate ``.tif`` file
%     - ``.overwrite`` - ``1`` = skip the "file exists" prompt (default: ``0``)
%     - ``.Compression`` - ``'none'`` (default), ``'lzw'``, or ``'packbits'`` (2D path only)
%     - ``.showWaitbar`` - ``1`` = show progress bar (default); ``0`` = suppress
%     - ``.ParentFigure`` - handle to the MIB UIFigure; when provided the progress bar
%       is shown as a ``uiprogressdlg`` attached to that window; when absent the legacy
%       ``waitbar`` is used
%     - ``.silent`` - [logical] (default: ``false``); when ``true`` all interactive
%       dialogs are suppressed
%     - ``.sequentialFn`` - controls 2D output naming:
%
%       - ``true`` (default when ``NaN``) - sequential names, e.g. ``image_01.ome.tiff``
%       - ``false`` - use original per-slice names from ``.SliceName``; falls back to
%         sequential when ``.SliceName`` is absent or empty
%       - ``NaN`` - decide at runtime (currently defaults to ``true``); normally set by
%         the calling saver (``OmeTiffSaver``) based on the user's dialog choice
%
%     - ``.SliceName`` - cell array of per-slice source filenames (without path); used
%       by the ``false`` branch of ``.sequentialFn``
%     - ``.cmap`` - colormap matrix for indexed images; ``NaN`` (default) means
%       grayscale/RGB
%     - ``.Resolution`` - [xDPI yDPI] written into 2D ``.tif`` files; derived
%       automatically from ``pixSize`` when absent
%     - ``.DimensionOrder`` - dimension order string passed to ``bfsave`` /
%       ``createMinimalOMEXMLMetadata``; default: ``'XYZCT'``
%
% Output Arguments:
%   - **result** - ``1`` = success, ``0`` = failure
%   - **options** - the options struct as used (with all defaults filled in)
%

% use SCIFIO to open ome-tiff in Fiji
% https://imagej.net/SCIFIO

% Updates
% 2026 - added options.silent, sequentialFn, cmap, Resolution defaults;
%        fixed 2D sequential naming (.ome compound extension stripped);
%        moved naming dialog to OmeTiffSaver (caller)

% **Example 1** - standalone 5D save:
%
%   .. code-block:: matlab
%
%      opts.pixSize     = struct('x',0.065,'y',0.065,'z',0.2,'t',1,'units','um','tunits','s');
%      opts.Saving3d    = '5D';
%      opts.Compression = 'lzw';
%      opts.showWaitbar = false;
%      opts.overwrite   = 1;
%      io.BioFormats.mibImage2ometiff('/output/stack.ome.tiff', imageData, opts);
%
% **Example 2** - 2D sequence with sequential naming:
%
%   .. code-block:: matlab
%
%      opts.pixSize      = struct('x',0.065,'y',0.065,'z',0.2,'t',1,'units','um','tunits','s');
%      opts.Saving3d     = '2D';
%      opts.sequentialFn = true;
%      opts.showWaitbar  = true;
%      opts.overwrite    = 1;
%      opts.ParentFigure = obj.mibModel.mibGUI;
%      io.BioFormats.mibImage2ometiff('/output/slice.ome.tiff', imageData, opts);
%      % produces /output/slice_01.ome.tiff, /output/slice_02.ome.tiff, ...
%
% **Example 3** - 2D sequence with original naming:
%
%   .. code-block:: matlab
%
%      opts.Saving3d     = '2D';
%      opts.sequentialFn = false;
%      opts.SliceName    = {'frame001', 'frame002', 'frame003'};  % no extension
%      io.BioFormats.mibImage2ometiff('/output/any.ome.tiff', imageData, opts);
%      % produces /output/frame001.ome.tiff, /output/frame002.ome.tiff, ...

result = 0;
if nargin < 3; options = struct(); end
if nargin < 2; msgbox('Please provide filename and image!', 'Error!', 'error', 'modal'); return; end

% link the Bio-Formats Java library on the first use (lazy, skipped at MIB startup)
utils.ensureJavaLibraries({'bioformats'});

if ~isfield(options, 'pixSize')
    options.pixSize = struct();
    options.pixSize.x = 1;
    options.pixSize.y = 1;
    options.pixSize.z = 1;
    options.pixSize.t = 1;
    options.pixSize.units = 'um';
    options.pixSize.tnits = 's';
end
if ~isfield(options, 'showWaitbar'); options.showWaitbar = 1; end
if ~isfield(options, 'ImageDescription'); options.ImageDescription = {''}; end
if ~isfield(options, 'overwrite'); options.overwrite = 0; end
if ~isfield(options, 'DatasetType'); options.DatasetType = 'image'; end
if ~isfield(options, 'Saving3d'); options.Saving3d = '5D'; end
if ~isfield(options, 'Compression'); options.Compression = 'none'; end
if ~isfield(options, 'DimensionOrder'); options.DimensionOrder = 'XYZCT'; end
if ~isfield(options, 'cmap');         options.cmap         = NaN;   end   % NaN = grayscale/RGB; otherwise indexed colormap
if ~isfield(options, 'silent');      options.silent       = false; end   % suppress all interactive dialogs
if ~isfield(options, 'sequentialFn'); options.sequentialFn = NaN;  end   % NaN=ask, true=sequential, false=original

% define time units for the output
switch lower(strtrim(char(options.pixSize.tunits)))
    case {'sec', 's', 'second', 'seconds'}
        tunits = ome.units.UNITS.SECOND;
    case {'min', 'm', 'minute', 'minutes'}
        tunits = ome.units.UNITS.MINUTE;
    case {'hour', 'h', 'hours'}
        tunits = ome.units.UNITS.HOUR;
    otherwise
        tunits = ome.units.UNITS.SECOND;
end

if options.overwrite == 0
    if exist(filename, 'file') == 2
        reply = questdlg(sprintf('!!! Warning !!!\n\n The file alreadt exists! Overwrite?'),'Overwrite', 'Overwrite', 'Cancel', 'Cancel');
        if strcmp(reply, 'Cancel'); return; end
    end
end
files_no = size(imageS, 4);
wb = [];
if options.showWaitbar
    if isfield(options, 'ParentFigure') && ~isempty(options.ParentFigure)
        try
            wb = uiprogressdlg(options.ParentFigure, 'Title', 'Saving images', ...
                'Message', sprintf('%s\nPlease wait...', filename));
        catch; wb = []; end
    else
        curInt = get(0, 'DefaulttextInterpreter');
        set(0, 'DefaulttextInterpreter', 'none');
        wb = waitbar(0, sprintf('%s\nPlease wait...', filename), 'Name', 'Saving images', 'WindowStyle', 'modal');
        set(findall(wb,'type','text'), 'Interpreter', 'none');
    end
end

% scale pixel size to um (normalize long spellings, e.g. zarr 'micrometers')
switch utils.normalizeUnits(options.pixSize.units)
    case 'm'
        scaleFactor = 1e6;
    case 'cm'
        scaleFactor = 1e4;
    case 'mm'
        scaleFactor = 1e3;
    case 'um'
        scaleFactor = 1;
    case 'nm'
        scaleFactor = .001;
    otherwise   % 'pixels' or unrecognised → treat as already in um (no scaling)
        scaleFactor = 1;
end
options.pixSize.x = options.pixSize.x * scaleFactor;
options.pixSize.y = options.pixSize.y * scaleFactor;
options.pixSize.z = options.pixSize.z * scaleFactor;

% Resolution in pixels-per-inch (imwrite default unit) derived from pixSize [µm]
% 1 inch = 25400 µm
if ~isfield(options, 'Resolution')
    options.Resolution = [25400 / options.pixSize.x, 25400 / options.pixSize.y];
end

% Ensure ImageDescription is a cell array for indexed access in the 2D path
if ischar(options.ImageDescription)
    options.ImageDescription = {options.ImageDescription};
end

if strcmp(options.Saving3d, '5D')
    % permute image from y,x,c,z,t to y,x,z,c,t
    % imageS = permute(imageS, [1 2 4 3 5]);

    metadata = local_buildOmeMetadata(imageS, options, tunits, options.ImageDescription{1});

    % delete old file
    if exist(filename, 'file') == 2; delete(filename); end

    loci.common.DebugTools.enableLogging('ERROR');  % suppress BioFormats tile/strip DEBUG messages
    if strcmp(options.Compression, 'none')
        bfsave(imageS, filename, 'metadata', metadata);
    else
        bfsave(imageS, filename, 'metadata', metadata, 'Compression', options.Compression);
    end
    
%     imwrite(squeeze(imageS(:,:,:,1)),filename,'tif','WriteMode','overwrite','Description',cell2mat(ImageDescription(1)),'Resolution',options.Resolution,'Compression',options.Compression);
%     for num = 2:files_no
%             imwrite(squeeze(imageS(:,:,:,num)),filename,'tif','WriteMode','append','Description',cell2mat(ImageDescription(num)),'Resolution',options.Resolution,'Compression',options.Compression);
%             if options.showWaitbar; waitbar(num/files_no,wb); end
%         end
    options.SliceName{1} = filename;
elseif strcmp(options.Saving3d, '2D')
    % ---- determine naming mode ----
    % options.sequentialFn is set by the caller (OmeTiffSaver); NaN falls
    % back to sequential so direct callers that don't set it still work.
    if isnan(options.sequentialFn)
        sequentialFn = true;
    else
        sequentialFn = logical(options.sequentialFn);
    end

    [pathstr, name] = fileparts(filename);
    % Strip compound .ome extension so sequential names do not become
    % 'image.ome_01.ome.tiff'.  fileparts('image.ome.tiff') returns
    % name='image.ome'; remove the trailing '.ome'.
    if length(name) > 4 && strcmpi(name(end-3:end), '.ome')
        name = name(1:end-4);
    end

    if sequentialFn     % generate sequential filenames
        for i = 1:files_no
            options.SliceName{i} = fullfile(pathstr, utils.generateSequentialFilename(name, i, files_no, '.ome.tiff'));
        end
    else                % use original filenames supplied by the caller
        if ~isfield(options, 'SliceName') || isempty(options.SliceName)
            % no original names available - fall back to sequential
            for i = 1:files_no
                options.SliceName{i} = fullfile(pathstr, utils.generateSequentialFilename(name, i, files_no, '.ome.tiff'));
            end
        else
            % remove existing extension from supplied names
            for i = 1:numel(options.SliceName)
                [~, options.SliceName{i}] = fileparts(options.SliceName{i});
            end

            % resolve duplicate base names
            i = 1;
            while i <= numel(options.SliceName)
                duplicatesNo = sum(cell2mat(strfind(options.SliceName(:), options.SliceName{i})));
                if duplicatesNo > 1
                    for j = i:i+duplicatesNo-1
                        options.SliceName{j} = utils.generateSequentialFilename(options.SliceName{j}, j-i+1, duplicatesNo, '.ome.tiff');
                    end
                    i = i + duplicatesNo;
                else
                    options.SliceName{i} = [options.SliceName{i} '.ome.tiff'];
                    i = i + 1;
                end
            end

            % prepend full path
            for i = 1:files_no
                options.SliceName{i} = fullfile(pathstr, options.SliceName{i});
            end
        end
    end
    
    
    loci.common.DebugTools.enableLogging('ERROR');  % suppress BioFormats tile/strip DEBUG messages
    for num = 1:files_no
        descIdx = min(num, numel(options.ImageDescription));
        desc = cell2mat(options.ImageDescription(descIdx));
        if isnan(options.cmap)  % grayscale or rgb image
            % write via bfsave (real OME-XML per file) so per-channel LUT
            % colours survive the round-trip; imwrite has no OME concept and
            % silently drops them (only a plain 'Description' string, no
            % Channel/Color metadata)
            imgSlice = imageS(:,:,:,num,:);   % keep [H,W,C,1,T] shape
            sliceMetadata = local_buildOmeMetadata(imgSlice, options, tunits, desc);
            if exist(options.SliceName{num}, 'file') == 2; delete(options.SliceName{num}); end
            if strcmp(options.Compression, 'none')
                bfsave(imgSlice, options.SliceName{num}, 'metadata', sliceMetadata);
            else
                bfsave(imgSlice, options.SliceName{num}, 'metadata', sliceMetadata, 'Compression', options.Compression);
            end
        else            % indexed image - palette is embedded directly by imwrite
            % imwrite errors on an empty 'Description' value, so only pass it when non-empty
            descArgs = {};
            if ~isempty(desc); descArgs = {'Description', desc}; end
            imwrite(imageS(:,:,:,num),options.cmap,options.SliceName{num},'tif','Compression',options.Compression,descArgs{:},'Resolution',options.Resolution);
        end
        if ~isempty(wb); if isa(wb,'matlab.ui.dialog.ProgressDialog'); wb.Value=num/files_no; else; waitbar(num/files_no,wb); end; end
    end
else
    error('Error: wrong saving type, use ''5D'' or ''2D''');
end

if ~isempty(wb); if isa(wb,'matlab.ui.dialog.ProgressDialog'); wb.Value=1; else; waitbar(1,wb); end; end
disp(['image2tiff: ' options.SliceName{1} ' was/were created!']);
if ~isempty(wb)
    if ~isa(wb, 'matlab.ui.dialog.ProgressDialog'); set(0, 'DefaulttextInterpreter', curInt); end
    delete(wb);
end
result = 1;
end

function metadata = local_buildOmeMetadata(imgSlice, options, tunits, imageDescription)
% LOCAL_BUILDOMEMETADATA - OME-XML metadata (pixel size, description, channel
% colours) for a 5D array, shared by the '5D' and '2D' saving branches so
% both carry the same physical-size and Channel/Color information.
metadata = createMinimalOMEXMLMetadata(imgSlice, options.DimensionOrder);
pixelSize = ome.units.quantity.Length(java.lang.Double(options.pixSize.x), ome.units.UNITS.MICROMETER);
metadata.setPixelsPhysicalSizeX(pixelSize, 0);
pixelSize = ome.units.quantity.Length(java.lang.Double(options.pixSize.y), ome.units.UNITS.MICROMETER);
metadata.setPixelsPhysicalSizeY(pixelSize, 0);
pixelSize = ome.units.quantity.Length(java.lang.Double(options.pixSize.z), ome.units.UNITS.MICROMETER);
metadata.setPixelsPhysicalSizeZ(pixelSize, 0);
pixelSize = ome.units.quantity.Time(java.lang.Double(options.pixSize.t), tunits);
metadata.setPixelsTimeIncrement(pixelSize, 0);

% ImageDescription - carries the MIB BoundingBox string so that the
% dataset's physical extent is preserved when reloading in MIB
if ~isempty(imageDescription)
    metadata.setImageDescription(imageDescription, 0);
end

% Channel LUT colours - written so that MIB (and Fiji/OMERO) can restore
% per-channel colours when reloading the file.
% Cap the loop at the metadata's SizeC: calling setChannelColor beyond the
% declared channel count creates a phantom Channel node with no ID, which
% makes the Bio-Formats writer throw "Channel ID #N in Image #0 is null"
% (e.g. a grayscale image whose lutColors still carries several RGB rows).
if isfield(options, 'lutColors') && ~isempty(options.lutColors)
    sizeC = metadata.getPixelsSizeC(0).getValue();
    nCh = min(size(options.lutColors, 1), sizeC);
    for iCh = 1:nCh
        r = int32(round(options.lutColors(iCh, 1) * 255));
        g = int32(round(options.lutColors(iCh, 2) * 255));
        b = int32(round(options.lutColors(iCh, 3) * 255));
        metadata.setChannelColor(ome.xml.model.primitives.Color(r, g, b, int32(255)), 0, iCh-1);
    end
end
end

