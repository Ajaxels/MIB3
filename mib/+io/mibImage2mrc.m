function result = mibImage2mrc(O, Options)
% function result = mibImage2mrc(O, Options)
% Export volume in MRC format
%
% @note Requires matTomo function set, available in mib/external/MatTomo
%
% Parameters:
% O: a dataset, [1:height,1:width,1:thickness] or [1:height,1:width,1,1:thickness]
% Options: a structure:
% @li .volumeFilename  — filename, use 'mrc' extension
% @li .pixSize.x       — physical width of the voxels
% @li .pixSize.y       — physical height of the voxels
% @li .pixSize.z       — physical thickness of the voxels
% @li .pixSize.units   — physical units
% @li .showWaitbar     — if @b 1 - show the wait bar, if @b 0 - do not show
% @li .ParentFigure    — [@em optional] handle to the main MIB application
%                        window.  When provided, the progress bar is rendered
%                        as a uiprogressdlg attached to that window
%                        (recommended for GUI use).  When absent or empty
%                        the legacy waitbar is used as a fallback.
%
% Return values:
% result: result of the function run, @b 1 - success, @b 0 - fail
%
% Example:
%   @code
%   %% Standalone / scripted use (no GUI parent):
%   mrcOpts.volumeFilename = '/output/volume.mrc';
%   mrcOpts.pixSize        = struct('x',0.065,'y',0.065,'z',0.2,'units','um');
%   mrcOpts.showWaitbar    = false;
%   io.mibImage2mrc(imageData_hwd, mrcOpts);
%   @endcode
%
%   @code
%   %% GUI use — attach progress dialog to the MIB window:
%   mrcOpts.volumeFilename = '/output/volume.mrc';
%   mrcOpts.pixSize        = struct('x',0.065,'y',0.065,'z',0.2,'units','um');
%   mrcOpts.showWaitbar    = true;
%   mrcOpts.ParentFigure   = obj.mibModel.mibGUI;   % uiprogressdlg parent
%   io.mibImage2mrc(imageData_hwd, mrcOpts);
%   @endcode

result = 0;
if ~isfield(Options, 'showWaitbar'); Options.showWaitbar = 1; end

if ndims(O) == 3
    O = permute(O, [2 1 3]);
else
    if size(O,3) > 1
        errordlg(sprintf('MRC format requires grayscale images!\nPlease convert dataset to the grayscale mode: Menu->Image->Mode->Grayscale'),'Wrong input data');
        return;
    end
    O = permute(squeeze(O), [2 1 3]);
end

wb = [];
if Options.showWaitbar
    if isfield(Options, 'ParentFigure') && ~isempty(Options.ParentFigure)
        try
            wb = uiprogressdlg(Options.ParentFigure, 'Title', 'Saving to MRC', ...
                'Message', sprintf('Saving:\n%s\nPlease wait...', Options.volumeFilename));
        catch; wb = []; end
    else
        curInt = get(0, 'DefaulttextInterpreter');
        set(0, 'DefaulttextInterpreter', 'none');
        wb = waitbar(0, sprintf('Saving:\n%s\nPlease wait...', Options.volumeFilename), 'Name', 'Saving to MRC');
        set(findall(wb,'type','text'), 'Interpreter', 'none');
    end
end

mrcImage = MRCImage();
O = flip(O, 2);
mrcImage = setVolume(mrcImage, O);

switch Options.pixSize.units
    case 'm'
        coef = 1e-10;
    case 'cm'
        coef = 1e-8;
    case 'mm'
        coef = 1e-7;
    case 'um'
        coef = 1e-4;
    case 'nm'
        coef = 1e-1;
end
pixSizeX_Angstrom = Options.pixSize.x/coef;
pixSizeY_Angstrom = Options.pixSize.y/coef;
pixSizeZ_Angstrom = Options.pixSize.z/coef;

mrcImage = setPixelSize(mrcImage, pixSizeX_Angstrom, pixSizeY_Angstrom, pixSizeZ_Angstrom);

save(mrcImage, Options.volumeFilename);
if ~isempty(wb)
    if ~isa(wb, 'matlab.ui.dialog.ProgressDialog'); set(0, 'DefaulttextInterpreter', curInt); end
    delete(wb);
end

result = result + 1;
end
