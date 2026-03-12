function result = bitmap2nrrd(filename, bitmap, bb, options)
% function result = bitmap2nrrd(filename, bitmap, bb, options)
% Save bitmap matrix to NRRD format
%
% Format description:
% http://teem.sourceforge.net/nrrd/format.html
%
% Parameters:
% filename: filename for NRRD
% bitmap: a dataset, [1:height, 1:width, 1:colors, 1:no_stacks]
% bb: bounding box information, a vector [minX, maxX, minY, maxY, minZ, maxZ]
% options: a structure with some optional parameters
% - .overwrite      — if @b 1 do not check whether file with provided filename already exists
% - .showWaitbar    — if @b 1 - show the wait bar, if @b 0 - do not show
% - .ParentFigure   — [@em optional] handle to the main MIB application window.
%                     When provided, the progress bar is rendered as a
%                     uiprogressdlg attached to that window (recommended for
%                     GUI use).  When absent or empty the legacy waitbar is
%                     used as a fallback.
%
% Return values:
% result: result of the function run, @b 1 - success, @b 0 - fail
%
% Example:
%   @code
%   %% Standalone / scripted use (no GUI parent):
%   bb = dataset.boundingBox;  % [xmin xmax ymin ymax zmin zmax]
%   opts.overwrite   = 1;
%   opts.showWaitbar = false;
%   io.NRRD.bitmap2nrrd('/output/volume.nrrd', imgData_hwd, bb, opts);
%   @endcode
%
%   @code
%   %% GUI use — attach progress dialog to the MIB window:
%   bb = dataset.boundingBox;
%   opts.overwrite    = 1;
%   opts.showWaitbar  = true;
%   opts.ParentFigure = obj.mibModel.mibGUI;   % uiprogressdlg parent
%   io.NRRD.bitmap2nrrd('/output/volume.nrrd', imgData_hwd, bb, opts);
%   @endcode

result = 0;
if nargin < 2
    error('Please provide filename, and bitmap matrix!');
end
if nargin < 3
    bb(1) = 0;
    bb(2) = size(bitmap,2)-1;
    bb(3) = 0;
    bb(4) = size(bitmap,1)-1;
    bb(5) = 0;
    bb(6) = max([1 size(bitmap,4)-1 size(bitmap,3)]);
end

if nargin < 4
    options = struct();
end
if ~isfield(options, 'overwrite'); options.overwrite = 0; end
if ~isfield(options, 'showWaitbar'); options.showWaitbar = 1; end

if options.overwrite == 0
    if exist(filename,'file') == 2
        choice = questdlg('File exists! Overwrite?', 'Warning!', 'Continue','Cancel','Cancel');
        if ~strcmp(choice,'Continue'); disp('Canceled, nothing was saved!'); return; end
    end
end

wb = [];
if options.showWaitbar
    if isfield(options, 'ParentFigure') && ~isempty(options.ParentFigure)
        try
            wb = uiprogressdlg(options.ParentFigure, 'Title', 'Saving images in the nrrd format...', ...
                'Message', sprintf('%s\nPlease wait...', filename));
        catch; wb = []; end
    else
        curInt = get(0, 'DefaulttextInterpreter');
        set(0, 'DefaulttextInterpreter', 'none');
        wb = waitbar(0, sprintf('%s\nPlease wait...', filename), 'Name', 'Saving images in the nrrd format...', 'WindowStyle', 'modal');
        set(findall(wb,'type','text'), 'Interpreter', 'none');
    end
end

width = size(bitmap, 2);
height = size(bitmap, 1);
if ndims(bitmap) == 4
    stacks = size(bitmap, 4);
    colors = size(bitmap, 3);
else
    if size(bitmap, 3) == 3
        stacks = 1;
        colors = size(bitmap, 3);
    else
        stacks = size(bitmap, 3);
        colors = 1;
    end
end

fid = fopen(filename, 'w');
fprintf(fid, 'NRRD0004\n');
fprintf(fid, '# Complete NRRD file format specification at:\n');
fprintf(fid, '# http://teem.sourceforge.net/nrrd/format.html\n');
if isa(bitmap, 'uint8')
    fprintf(fid, 'type: unsigned char\n');
elseif isa(bitmap, 'uint16')
    fprintf(fid, 'type: unsigned short\n');
else
    error('bitmap2nrrd: wrong data type');
end

if colors==1
    fprintf(fid, 'dimension: 3\n');
else
    fprintf(fid, 'dimension: 4\n');
end
fprintf(fid, 'space: left-posterior-superior\n');

if colors==1
    fprintf(fid, 'sizes: %d %d %d\n', size(bitmap,2), size(bitmap,1), size(bitmap, ndims(bitmap)));
else
    fprintf(fid, 'sizes: %d %d %d %d\n', size(bitmap,3), size(bitmap,2), size(bitmap,1), size(bitmap,4));
end

if colors == 1
    fprintf(fid, 'space directions: (%f,0,0) (0,%f,0) (0,0,%f)\n',(bb(2)-bb(1))/(max([1 width-1])), (bb(4)-bb(3))/max([(height-1) 1]), (bb(6)-bb(5))/max([(stacks-1) 1]));
    fprintf(fid, 'kinds: domain domain domain\n');
else
    fprintf(fid, 'space directions: none (%f, 0, 0) (0, %f, 0) (0,0,%f)\n',(bb(2)-bb(1))/(max([1 width-1])), (bb(4)-bb(3))/max([(height-1) 1]), (bb(6)-bb(5))/max([(stacks-1) 1]));
    fprintf(fid, 'kinds: vector domain domain domain\n');
end
fprintf(fid, 'encoding: raw\n');
fprintf(fid, 'endian: little\n');
fprintf(fid, 'space origin: (%f,%f,%f)\n', -bb(1), -bb(3), bb(5));
fprintf(fid, '\n');
if ~isempty(wb); if isa(wb,'matlab.ui.dialog.ProgressDialog'); wb.Value=0.05; else; waitbar(0.05,wb); end; end

if colors == 1  % greyscale
    if ndims(bitmap) == 4
        bitmap = reshape(permute(bitmap,[2 1 4 3]),1,[])';
    else
        bitmap = reshape(permute(bitmap,[2 1 3]),1,[])';
    end
else
    bitmap = reshape(permute(bitmap,[3 2 1 4]),1,[])';
end
fwrite(fid, bitmap, class(bitmap), 0, 'ieee-le');
if ~isempty(wb); if isa(wb,'matlab.ui.dialog.ProgressDialog'); wb.Value=1; else; waitbar(1,wb); end; end
fclose(fid);
disp(['bitmap2nrrd: ' filename ' was created!']);
result = 1;
if ~isempty(wb)
    if ~isa(wb, 'matlab.ui.dialog.ProgressDialog'); set(0, 'DefaulttextInterpreter', curInt); end
    delete(wb);
end
end
