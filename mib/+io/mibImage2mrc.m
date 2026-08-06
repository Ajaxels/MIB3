function result = mibImage2mrc(O, Options)
% MIBIMAGE2MRC - Export volume data in MRC format.
%
% Syntax:
%
%   .. code-block:: matlab
%
%      result = io.mibImage2mrc(O, Options)
%
% Exports 3D volumetric image data to MRC format (Electron Microscopy Data Bank
% standard). Requires the MatTomo function set, available in ``mib/external/MatTomo``.
%
% Input Arguments:
%   - **O** - [H, W, D] or [H, W, 1, D] numeric array, volumetric dataset.
%     Grayscale format required (MRC does not support multichannel images).
%   - **Options** - struct with configuration:
%
%     - ``.volumeFilename`` - [char] output filename; use ``'.mrc'`` extension
%     - ``.pixSize`` - struct with voxel size information:
%
%       - ``.x`` - [numeric] physical width of voxels
%       - ``.y`` - [numeric] physical height of voxels
%       - ``.z`` - [numeric] physical thickness of voxels
%       - ``.units`` - [char] physical units (``'m'``, ``'cm'``, ``'mm'``, ``'um'``, ``'nm'``)
%
%     - ``.showWaitbar`` - *(optional)* [logical] default: ``true``
%       show progress bar during save
%     - ``.ParentFigure`` - *(optional)* [handle] main MIB window for ``uiprogressdlg``
%       attachment (recommended for GUI use). When absent, falls back to legacy ``waitbar``.
%
% Output Arguments:
%   - **result** - [logical] ``1`` on success, ``0`` on failure
%
% **Example 1** - standalone scripted use (no GUI parent):
%
%   .. code-block:: matlab
%
%      mrcOpts.volumeFilename = '/output/volume.mrc';
%      mrcOpts.pixSize = struct('x',0.065,'y',0.065,'z',0.2,'units','um');
%      mrcOpts.showWaitbar = false;
%      io.mibImage2mrc(imageData_hwd, mrcOpts);
%
% **Example 2** - GUI use with progress dialog attached to MIB window:
%
%   .. code-block:: matlab
%
%      mrcOpts.volumeFilename = '/output/volume.mrc';
%      mrcOpts.pixSize = struct('x',0.065,'y',0.065,'z',0.2,'units','um');
%      mrcOpts.showWaitbar = true;
%      mrcOpts.ParentFigure = obj.mibModel.mibGUI;
%      io.mibImage2mrc(imageData_hwd, mrcOpts);
%

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
