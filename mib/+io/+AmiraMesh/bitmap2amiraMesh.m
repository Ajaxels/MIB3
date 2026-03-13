function result = bitmap2amiraMesh(filename, bitmap, img_info, options)
% function result = bitmap2amiraMesh(filename, bitmap, img_info, options)
% Convert bitmap matrix to Amira Mesh binary format
%
% Parameters:
% filename: filename for Amira Mesh file
% bitmap: a dataset in MIB3 native order [H, W, D, C, T]
%         (height, width, depth/slices, colour channels, time points).
%         Only the first time point (T=1) is written.
% img_info: metadata dictionary (MATLAB dictionary, string → cell); pass []
%           to use defaults.  Recognised keys:
%           'pixSize'              — pixSize struct (.x .y .z .units ...)
%           'BoundingBox'          — [xmin xmax ymin ymax zmin zmax]
%           'colorType'            — 'grayscale' | 'multichannel'
%           'lutColors'            — [C x 3] colour matrix (0..1)
%           'ImageDescription'     — (char) optional description string
%           'TransformationMatrix' — optional transform (char or numeric)
% options: a structure with optional parameters:
% - .overwrite      — if 1, do not check whether file already exists
% - .showWaitbar    — if 1, show the progress bar
% - .ParentFigure   — [@em optional] handle to the main MIB application window.
%                     When provided, the progress bar is rendered as a
%                     uiprogressdlg attached to that window (recommended for
%                     GUI use).  When absent or empty the legacy waitbar is
%                     used as a fallback.
% - .colors         — [optional] [C x 3] colour matrix (0..1) for multichannel;
%                     overrides img_info lutColors
% - .Saving3d       — 'multi'    : save all z-slices in a single file (default)
%                     'sequence' : save one file per z-slice
% - .SliceName      — [optional] cell array with per-slice filenames (no path)
% - .verbose        — [optional] logical (default: true)
%
% Return values:
% result: 1 - success, 0 - fail
%
% Example:
%   @code
%   %% Standalone / scripted use (no GUI parent):
%   opts.overwrite   = 1;
%   opts.showWaitbar = false;
%   opts.Saving3d    = 'multi';
%   opts.colors      = lutColors;
%   io.AmiraMesh.bitmap2amiraMesh('/output/stack.am', data_hwdct, imgInfoDict, opts);
%   @endcode
%
%   @code
%   %% GUI use — attach progress dialog to the MIB window:
%   opts.overwrite      = 1;
%   opts.showWaitbar    = true;
%   opts.Saving3d       = 'multi';
%   opts.colors         = lutColors;
%   opts.ParentFigure   = obj.mibModel.mibGUI;   % uiprogressdlg parent
%   io.AmiraMesh.bitmap2amiraMesh('/output/stack.am', data_hwdct, imgInfoDict, opts);
%   @endcode

% Updates
% ver 1.01 - 10.02.2012, memory performance improvement
% ver 1.02 - 07.11.2013, added .colors
% ver 1.03 - 17.09.2014, fix for saving parameters that are in structures
% ver 1.04 - 04.06.2018 save TransformationMatrix with AmiraMesh
% ver 1.05 - 22.01.2019 added saving of amira mesh files as 2D sequence
% ver 1.06 - 28.01.2022 replaced multiple spaces with single space chars in BoundingBox
% ver 2.00 - 2025, MIB3 port: bitmap order changed to [H,W,D,C,T];
%            img_info changed from containers.Map to MATLAB dictionary

result = 0;
if nargin < 2; error('Please provide filename, and bitmap matrix!'); end
if nargin < 3; img_info = []; end
if isempty(img_info)
    img_info = configureDictionary("string", "cell");
end

if nargin < 4
    options = struct();
    options.parameters.CoordType = '"uniform"';
end
if ~isfield(options, 'overwrite');    options.overwrite    = 0;      end
if ~isfield(options, 'showWaitbar');  options.showWaitbar  = 1;      end
if ~isfield(options, 'Saving3d');     options.Saving3d     = 'multi'; end
if ~isfield(options, 'verbose');      options.verbose      = true;   end
if ~isfield(options, 'ParentFigure'); options.ParentFigure = [];   end

% overwrite lutColors in img_info if colours provided in options
if isfield(options, 'colors')
    img_info("lutColors") = {options.colors};
end

if options.overwrite == 0
    if exist(filename, 'file') == 2
        if ~isempty(options.ParentFigure) 
            choice = uiconfirm(options.ParentFigure, ...
                sprintf('File exists!\n%s\n\nOverwrite?', filename), 'Overwrite?',  'Icon', 'warning', ...
                'Options', {'Continue', 'Cancel'}, 'DefaultOption', 2);
        else
            choice = questdlg('File exists! Overwrite?', 'Warning!', ...
                'Continue', 'Cancel', 'Cancel');
        end
        if strcmp(choice, 'Cancel'); disp('Canceled, nothing was saved!'); return; end
    end
end

wb = [];
if options.showWaitbar
    if ~isempty(options.ParentFigure)
        try
            wb = uiprogressdlg(options.ParentFigure, 'Title', 'Saving images as Amira Mesh...', ...
                'Message', sprintf('%s\nPlease wait...', filename));
        catch
            wb = [];
        end
    else
        wb = waitbar(0, sprintf('%s\nPlease wait...', filename), ...
            'Name', 'Saving images as Amira Mesh...', 'WindowStyle', 'modal');
    end
end

nD = size(bitmap, 3);   % depth (number of z-slices)

if strcmp(options.Saving3d, 'multi')
    saveAmFile(filename, bitmap, img_info, options, wb);
else
    [saveDir, saveFn, saveExt] = fileparts(filename);
    if ~isfield(options, 'SliceName') || numel(options.SliceName) ~= nD
        options.SliceName = arrayfun( ...
            @(i) utils.generateSequentialFilename(saveFn, i, nD, saveExt), ...
            1:nD, 'UniformOutput', false)';
    end
    for fnId = 1:nD
        saveAmFile(fullfile(saveDir, options.SliceName{fnId}), ...
            bitmap(:,:,fnId,:,1), img_info, options, wb);
    end
end

if options.verbose; disp(['bitmap2amiraMesh: ' filename ' was created!']); end
result = 1;
if ~isempty(wb); delete(wb); end
end


% ------------------------------------------------------------------ %
function saveAmFile(filename, bitmap, img_info, options, wb)
% Write one Amira Mesh file.
% bitmap: [H, W, D, C, T] — MIB3 native order; only first T is used.

nC = size(bitmap, 4);   % colour channels
nD = size(bitmap, 3);   % depth (z-slices)

HxMultiChannelField3 = nC > 1;

fid = fopen(filename, 'w');
fprintf(fid, '# AmiraMesh BINARY-LITTLE-ENDIAN 2.1\n\n\n');
fprintf(fid, 'define Lattice %d %d %d\n\n', size(bitmap,2), size(bitmap,1), nD);
fprintf(fid, 'Parameters {\n');

% BoundingBox: read the numeric value BEFORE removing it from img_info.
% Priority: explicit numeric "BoundingBox" key > "ImageDescription" prefix > pixel extents.
bb = [0 max([size(bitmap,2) 2])-1  0 max([size(bitmap,1) 2])-1  0 max([nD 2])-1];
if isKey(img_info, "BoundingBox")
    bbVal = img_info{"BoundingBox"};
    if isnumeric(bbVal) && numel(bbVal) == 6
        bb = bbVal(:)';
    end
elseif isKey(img_info, "ImageDescription")
    coords = sscanf(char(img_info{"ImageDescription"}), 'BoundingBox %f %f %f %f %f %f');
    if numel(coords) == 6
        bb = coords(:)';
    end
end

% Remove keys that are written explicitly further below so they are not
% duplicated inside the im_browser {} generic field loop.
if isKey(img_info, "Content");     img_info = remove(img_info, "Content");     end
if isKey(img_info, "BoundingBox"); img_info = remove(img_info, "BoundingBox"); end
if isKey(img_info, "CoordType");   img_info = remove(img_info, "CoordType");   end
if isKey(img_info, "SliceName");   img_info = remove(img_info, "SliceName");   end

fields = keys(img_info);    % string array
fprintf(fid, '\tim_browser {\n');
for fieldIdx = 1:numel(fields)
    currKey = regexprep(fields(fieldIdx), '[_%! ()[]{}/|\\#?.,]', '_');
    currKey = strrep(currKey, sprintf('\xC5'), 'A');
    currKey = strrep(currKey, sprintf('\xB5'), 'u');
    currKey = char(currKey);

    valCell = img_info(fields(fieldIdx));
    val = valCell{1};    % unwrap cell

    if isstruct(val)
        extraFields = fieldnames(val);
        for extraFieldId = 1:numel(extraFields)
            currKey2 = regexprep(extraFields{extraFieldId}, '[_%! ()[]{}/|\\#?.,]', '_');
            currKey2 = strrep(currKey2, sprintf('\xC5'), 'A');
            currKey2 = strrep(currKey2, sprintf('\xB5'), 'u');
            subVal = val.(extraFields{extraFieldId});
            if isstruct(subVal) || numel(subVal) > 1
                fprintf(fid, '\t\t%s_%s skipped,\n', currKey, currKey2);
            elseif ~ischar(subVal) && ~isstring(subVal)
                fprintf(fid, '\t\t%s_%s %s,\n', currKey, currKey2, num2str(subVal));
            else
                fprintf(fid, '\t\t%s_%s %s,\n', currKey, currKey2, char(subVal));
            end
        end
    elseif iscell(val)
        continue;
    elseif isa(val, 'dictionary')
        continue;   % skip nested dictionaries
    elseif ~ischar(val) && ~isstring(val)
        if isscalar(val)
            fprintf(fid, '\t\t%s %s,\n', currKey, num2str(val));
        else
            fprintf(fid, '\t\t%s %s,\n', currKey, sprintf('"%s"', mat2str(val)));
        end
    else
        fprintf(fid, '\t\t%s "%s",\n', currKey, char(val));
    end
end
fprintf(fid, '\t}\n');

if HxMultiChannelField3
    for ch = 1:nC
        fprintf(fid, '\tChannel%d {\n', ch);
        dataWindowKey = sprintf('Channel%d_DataWindow', ch);
        if isKey(img_info, dataWindowKey)
            dwCell = img_info(dataWindowKey);
            fprintf(fid, '\t\tDataWindow %s,\n', char(dwCell{1}));
        else
            chData = bitmap(:,:,:,ch,1);
            fprintf(fid, '\t\tDataWindow %d %d,\n', min(chData(:)), max(chData(:)));
        end
        colorKey = sprintf('Channel%d_Color', ch);
        if isKey(img_info, "lutColors")
            lutColorsCell = img_info("lutColors");
            lutColors = lutColorsCell{1};
            fprintf(fid, '\t\tColor %f %f %f\n', lutColors(ch,1), lutColors(ch,2), lutColors(ch,3));
        elseif isKey(img_info, colorKey)
            colorCell = img_info(colorKey);
            fprintf(fid, '\t\tColor %s\n', char(colorCell{1}));
        else
            if isfield(options, 'colors')
                fprintf(fid, '\t\tColor %f %f %f\n', options.colors(ch,1), options.colors(ch,2), options.colors(ch,3));
            else
                fprintf(fid, '\t\tColor 0 1 0\n');
            end
        end
        fprintf(fid, '\t}\n');
    end
    fprintf(fid, '\tContentType "HxMultiChannelField3",\n');
else
    imgClass = mibAmiraClass(bitmap);
    fprintf(fid, '\tContent "%dx%dx%d %s, uniform coordinates",\n', ...
        size(bitmap,2), size(bitmap,1), nD, imgClass);
end

fprintf(fid, '\tBoundingBox %f %f %f %f %f %f,\n', bb(1), bb(2), bb(3), bb(4), bb(5), bb(6));
fprintf(fid, '\tCoordType "uniform"');
if isKey(img_info, "TransformationMatrix")
    tmCell = img_info("TransformationMatrix");
    fprintf(fid, '\tTransformationMatrix %s\n', num2str(tmCell{1}));
else
    fprintf(fid, '\n');
end
fprintf(fid, '}\n\n');

imgClass = mibAmiraClass(bitmap);
if ~isempty(wb); if isa(wb, 'matlab.ui.dialog.ProgressDialog'); wb.Value = 0.05; else; waitbar(0.05, wb); end; end

if nC == 1  % grayscale
    fprintf(fid, 'Lattice { %s Data } @1\n\n', imgClass);
    fprintf(fid, '# Data section follows\n');
    fprintf(fid, '@1\n');
    for zIndex = 1:nD
        img = bitmap(:,:,zIndex,1,1);
        img = reshape(permute(img, [3 2 1]), 1, [])';
        fwrite(fid, img, class(img), 0, 'ieee-le');
        if ~isempty(wb) && mod(zIndex, ceil(nD/20)) == 0
            if isa(wb, 'matlab.ui.dialog.ProgressDialog'); wb.Value = zIndex/nD; else; waitbar(zIndex/nD, wb); end
        end
    end
else  % multichannel
    maxIndex = nD * nC;
    index    = 1;
    for ch = 1:nC
        fprintf(fid, 'Lattice { %s Data%d } @%d\n', imgClass, ch, ch);
    end
    fprintf(fid, '\n');
    fprintf(fid, '# Data section follows');
    for ch = 1:nC
        fprintf(fid, '\n');
        fprintf(fid, '@%d\n', ch);
        for zIndex = 1:nD
            img = bitmap(:,:,zIndex,ch,1);
            img = reshape(permute(img, [3 2 1]), 1, [])';
            fwrite(fid, img, class(img), 0, 'ieee-le');
            if ~isempty(wb) && mod(index, ceil(maxIndex/20)) == 0
                if isa(wb, 'matlab.ui.dialog.ProgressDialog'); wb.Value = index/maxIndex; else; waitbar(index/maxIndex, wb); end
            end
            index = index + 1;
        end
    end
end
fprintf(fid, '\n');
fclose(fid);
end


% ------------------------------------------------------------------ %
function imgClass = mibAmiraClass(bitmap)
% Return the Amira type string for the bitmap's data class.
if isa(bitmap(1), 'uint8')
    imgClass = 'byte';
else
    imgClass = 'ushort';
end
end
