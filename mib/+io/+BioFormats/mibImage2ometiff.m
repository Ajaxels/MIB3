function [result, options] = mibImage2ometiff(filename, imageS, options)
% function [result, options] = mibImage2ometiff(filename, imageS, options)
% Save image in OME.TIF format — either as a single 5D file or a 2D sequence.
%
% Parameters:
% filename: full path for the output file (extension forced to .ome.tiff)
% imageS: dataset [height, width, color_channels, z_slices, time]
% options: [@em optional] struct with fields:
%  .pixSize        — MIB pixel-size struct (.x .y .z .t .units .tunits);
%                    default: all 1, units 'um', tunits 's'
%  .lutColors      — [C x 3] LUT colour matrix (unused in 2D imwrite path)
%  .ImageDescription — char or cell-string description embedded in the file;
%                    default: ''
%  .DatasetType    — 'image' (default) or 'model'
%  .Saving3d       — '5D' (default): write all slices into one OME-TIFF via
%                    bfsave; '2D': write each z-slice as a separate .tif file
%  .overwrite      — 1 = skip the "file exists" prompt (default: 0)
%  .Compression    — 'none' (default), 'lzw', 'packbits' (2D path only)
%  .showWaitbar    — 1 (default) show progress bar; 0 suppress
%  .ParentFigure   — handle to the MIB application window; when provided the
%                    progress bar is rendered as a uiprogressdlg attached to
%                    that window.  When absent the legacy waitbar is used.
%  .silent         — logical (default false); when true all interactive
%                    dialogs are suppressed
%  .sequentialFn   — controls 2D output naming:
%                      true  (default when NaN) : sequential names,
%                            e.g. image_01.ome.tiff, image_02.ome.tiff
%                      false : use original per-slice names from .SliceName;
%                              falls back to sequential when .SliceName is
%                              absent or empty
%                      NaN   : decide at runtime — currently defaults to true
%                    Normally set by the calling saver (OmeTiffSaver) based
%                    on the user's dialog choice; direct callers may set it
%                    explicitly to bypass the default.
%  .SliceName      — cell array of per-slice source filenames (without path);
%                    used by the 'original filename' branch when
%                    sequentialFn = false
%  .cmap           — colormap matrix for indexed images; NaN (default) means
%                    grayscale / RGB
%  .Resolution     — [xDPI yDPI] written into 2D .tif files; derived
%                    automatically from pixSize when absent
%  .DimensionOrder — dimension order string passed to bfsave / createMinimalOMEXMLMetadata;
%                    default 'XYZCT'
%
% Return values:
% result: 1 on success, 0 on failure
% options: the options struct as used (with all defaults filled in)

% use SCIFIO to open ome-tiff in Fiji
% https://imagej.net/SCIFIO

% Updates
% 2026 — added options.silent, sequentialFn, cmap, Resolution defaults;
%        fixed 2D sequential naming (.ome compound extension stripped);
%        moved naming dialog to OmeTiffSaver (caller)

% Example:
%   @code
%   %% Standalone 5D save:
%   opts.pixSize     = struct('x',0.065,'y',0.065,'z',0.2,'t',1,'units','um','tunits','s');
%   opts.Saving3d    = '5D';
%   opts.Compression = 'lzw';
%   opts.showWaitbar = false;
%   opts.overwrite   = 1;
%   mibImage2ometiff('/output/stack.ome.tiff', imageData, opts);
%   @endcode
%
%   @code
%   %% 2D sequence — sequential naming:
%   opts.pixSize       = struct('x',0.065,'y',0.065,'z',0.2,'t',1,'units','um','tunits','s');
%   opts.Saving3d      = '2D';
%   opts.sequentialFn  = true;
%   opts.showWaitbar   = true;
%   opts.overwrite     = 1;
%   opts.ParentFigure  = obj.mibModel.mibGUI;
%   mibImage2ometiff('/output/slice.ome.tiff', imageData, opts);
%   % produces /output/slice_01.ome.tiff, /output/slice_02.ome.tiff, ...
%   @endcode
%
%   @code
%   %% 2D sequence — original naming:
%   opts.Saving3d      = '2D';
%   opts.sequentialFn  = false;
%   opts.SliceName     = {'frame001', 'frame002', 'frame003'};  % no extension
%   mibImage2ometiff('/output/any.ome.tiff', imageData, opts);
%   % produces /output/frame001.ome.tiff, /output/frame002.ome.tiff, ...
%   @endcode

result = 0;
if nargin < 3; options = struct(); end
if nargin < 2; msgbox('Please provide filename and image!', 'Error!', 'error', 'modal'); return; end

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
switch options.pixSize.tunits
    case {'sec', 's'}
        tunits = ome.units.UNITS.SECOND;
    case {'min', 'm'}
        tunits = ome.units.UNITS.MINUTE;
    case {'hour', 'h'}
        tunits = ome.units.UNITS.HOUR;
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

% scale pixel size to um
switch options.pixSize.units
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
    
    metadata = createMinimalOMEXMLMetadata(imageS, options.DimensionOrder);
    pixelSize = ome.units.quantity.Length(java.lang.Double(options.pixSize.x), ome.units.UNITS.MICROMETER);
    metadata.setPixelsPhysicalSizeX(pixelSize, 0);
    pixelSize = ome.units.quantity.Length(java.lang.Double(options.pixSize.y), ome.units.UNITS.MICROMETER);
    metadata.setPixelsPhysicalSizeY(pixelSize, 0);
    pixelSize = ome.units.quantity.Length(java.lang.Double(options.pixSize.z), ome.units.UNITS.MICROMETER);
    metadata.setPixelsPhysicalSizeZ(pixelSize, 0);
    pixelSize = ome.units.quantity.Time(java.lang.Double(options.pixSize.t), tunits);
    metadata.setPixelsTimeIncrement(pixelSize, 0);

    % ImageDescription — carries the MIB BoundingBox string so that the
    % dataset's physical extent is preserved when reloading in MIB
    if isfield(options, 'ImageDescription') && ~isempty(options.ImageDescription)
        desc5d = options.ImageDescription{1};
        if ~isempty(desc5d)
            metadata.setImageDescription(desc5d, 0);
        end
    end

    % Channel LUT colours — written so that MIB (and Fiji/OMERO) can
    % restore per-channel colours when reloading the file
    if isfield(options, 'lutColors') && ~isempty(options.lutColors)
        nCh = size(options.lutColors, 1);
        for iCh = 1:nCh
            r = int32(round(options.lutColors(iCh, 1) * 255));
            g = int32(round(options.lutColors(iCh, 2) * 255));
            b = int32(round(options.lutColors(iCh, 3) * 255));
            metadata.setChannelColor(ome.xml.model.primitives.Color(r, g, b, int32(255)), 0, iCh-1);
        end
    end
    
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
            % no original names available — fall back to sequential
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
    
    
    for num = 1:files_no
        descIdx = min(num, numel(options.ImageDescription));
        desc = cell2mat(options.ImageDescription(descIdx));
        if isnan(options.cmap)  % grayscale or rgb image
            imwrite(imageS(:,:,:,num),options.SliceName{num},'tif','Compression',options.Compression,'Description',desc,'Resolution',options.Resolution);
        else            % indexed image
            imwrite(imageS(:,:,:,num),options.cmap,options.SliceName{num},'tif','Compression',options.Compression,'Description',desc,'Resolution',options.Resolution);
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

