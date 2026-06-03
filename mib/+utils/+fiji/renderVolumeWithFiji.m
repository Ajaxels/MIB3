function result = renderVolumeWithFiji(Volume, pixSize, mibGUI)
% RENDERVOLUMEWITHFIJI - Render a 3D volume using Fiji's 3D Viewer.
%
% Requires Fiji to be installed (http://fiji.sc/Fiji).
%
% Based on ``Matlab3DViewerDemo_1.m`` by Jean-Yves Tinevez \<jeanyves.tinevez at gmail.com\>.
%
% Syntax:
%   .. code-block:: matlab
%
%      result = utils.fiji.renderVolumeWithFiji(Volume, pixSize)
%      result = utils.fiji.renderVolumeWithFiji(Volume, pixSize, mibGUI)
%
% Input Arguments:
%   - **Volume** — [uint8] 3D volume to visualize, dimensions [height, width, colors, z]
%   - **pixSize** — struct with physical voxel dimensions:
%
%     - ``.x`` — physical width
%     - ``.y`` — physical height
%     - ``.z`` — physical thickness
%     - ``.units`` — physical units string
%
%   - **mibGUI** *(optional)* — handle to the parent UIFigure for dialogs and progress bar
%
% Output Arguments:
%   - **result** — [logical] ``0`` on failure, ``1`` on success
%
% Updates
%

if nargin < 3; mibGUI = []; end

result = 0;

if ~isa(Volume, 'uint8')
    dlgOpt.MsgBoxOnly = true;
    dlgOpt.Icon = 'puffin_error';
    dlgOpt.WindowHeight = 140;
    utils.dlgs.inputUniversalDlg(mibGUI, '', {''}, ...
        {sprintf('Volume Renderer is implemented for uint8 type!\nCurrent image type is %s', class(Volume))}, ...
        'Volume data class error!', dlgOpt);
    return;
end

% check for installed Miji
if ~isdeployed
    if isempty(which('Miji'))
        dlgOpt.MsgBoxOnly = true;
        dlgOpt.Icon = 'puffin_error';
        dlgOpt.WindowHeight = 180;
        dlgOpt.HeaderLines = 1;
        utils.dlgs.inputUniversalDlg(mibGUI, 'Miji was not found!', {''}, ...
            {sprintf('<html>To fix:<ul><li>1. Install Fiji (http://fiji.sc/Fiji)</li><li>2. Add Fiji.app location to <em>MIB Preferences->External directories</em></li></ul></html>')}, ...
            'Missing Miji!', dlgOpt);
        return;
    end
end

%% Make sure Java3D is installed
% If not, try to install it
try
    if ~IsJava3DInstalled(true)
        dlgOpt.MsgBoxOnly = true;
        dlgOpt.Icon = 'puffin_error';
        utils.dlgs.inputUniversalDlg(mibGUI, '', {''}, ...
            {'Java3D is not installed'}, 'Java error!', dlgOpt);
        return;
    end
catch err %#ok<NASGU>
    % skip — IsJava3DInstalled may be unavailable; not required for newer Fiji versions
end

prompt = {'Reduce the volume down to, max width pixels [no volume reduction when 0]?',... % 'Smoothing 3d kernel, width (no smoothing when 0):',...
          'invert the volume (recommended for EM)',...
          'Transparency threshold, use several comma-separated numbers for RGB:'};
defAns = {struct('Spinner', true, 'Value', 512, 'Limits', [0 Inf], 'Step', 1, 'Round',true) , true, 'NaN'};

dlgOpt.WindowHeight = 220;
answer = utils.dlgs.inputUniversalDlg(mibGUI, '', prompt, defAns, 'Volume parameters', dlgOpt);
if isempty(answer); return; end

tic

maxVolumeWidth = answer{1};
if maxVolumeWidth ~= 0
    factorX=ceil(size(Volume,2)/maxVolumeWidth);
    factorY=ceil(factorX*pixSize.x/pixSize.y-.001);
    factorZ=ceil(factorX*pixSize.x/pixSize.z);
else
    factorX=1;
    factorY=1;
    factorZ=1;
end

% kernelX = str2double(answer{2});
% kernelY = round(kernelX*pixSize.x/pixSize.y) + abs(mod(round(kernelX*pixSize.x/pixSize.y),2)-1);
% kernelZ = round(kernelX*pixSize.x/pixSize.z) + abs(mod(round(kernelX*pixSize.x/pixSize.z),2)-1);

pwb = core.PoolWaitbar(100, 'Preparing the volume...', mibGUI, 'Volume', true);
% Smoothing with ib_doImageFiltering is not yet available in MIB3
% if kernelX > 0
%     options.fitType = 'Gaussian';
%     options.dataType = '4D';
%     options.hSize = [kernelX kernelY kernelZ];
%     options.sigma = kernelX/5;
%     options.pixSize = pixSize;
%     options.filters3DCheck = 1;
%     Volume = ib_doImageFiltering(Volume, options);
% end

maxVolumeWidth = answer{1};
if maxVolumeWidth ~= 0
    factorX=ceil(size(Volume,2)/maxVolumeWidth);
    factorY=ceil(factorX*pixSize.x/pixSize.y-.001);
    factorZ=ceil(factorX*pixSize.x/pixSize.z);
else
    factorX=1;
    factorY=1;
    factorZ=1;
end
width = ceil(size(Volume,2)/factorX);
height = ceil(size(Volume,1)/factorY);
depth = ceil(size(Volume,3)/factorZ);

pwb.updateText(sprintf('Reducing the volume to %d x %d x %d px ...', height, width, depth));
pwb.setCurrentIteration(29); pwb.increment();
if factorX ~= 1 || factorY ~= 1 || factorZ ~=1
    binVolume = zeros([height, width, depth, size(Volume, 4)], class(Volume));
    for color = 1:size(Volume,4)
        [~,~,~,binVolume(:,:,:,color)] = reducevolume(squeeze(Volume(:,:,:,color)), [factorY,factorX,factorZ]);
    end
    Volume = binVolume;
    clear binVolume;
end

% Invert image intensities, Ctrl+I shortcut
invertSwitch = answer{2};
if invertSwitch ==1
    pwb.updateText('Inverting the volume...'); pwb.setCurrentIteration(49); pwb.increment();
    maxval = intmax(class(Volume));
    Volume = maxval - Volume;
end

transparencyThresholds = str2num(answer{3}); %#ok<ST2NM>
if invertSwitch && ~isnan(transparencyThresholds)
    transparencyThresholds = double(intmax(class(Volume))) - transparencyThresholds;
end
pwb.updateText('Adding transparency...');
if ~isnan(transparencyThresholds)
    for color = numel(transparencyThresholds)
        Vol = Volume(:,:,:,color);
        Vol(Vol < transparencyThresholds(color)) = 0;
        Volume(:,:,:,color) = Vol;
        clear Vol;
    end
end

pwb.updateText('Preparing the volume...'); pwb.setCurrentIteration(59); pwb.increment();
if size(Volume, 4) == 1 % grayscale
    %[R G B] = deal(squeeze(Volume));
    R = 1;
    G = 1;
    B = 1;
elseif size(Volume, 4) == 2
    R = squeeze(Volume(:,:,:,1));
    G = squeeze(Volume(:,:,:,2));
    B = zeros(size(squeeze(Volume(:,:,:,1))),class(Volume));
else
    R = squeeze(Volume(:,:,:,1));
    G = squeeze(Volume(:,:,:,2));
    B = squeeze(Volume(:,:,:,3));
end

% We now put them together into one 3D color image (that is, with 4D). To
% do so, we simply concatenate them along the 3th dimension.
% A note here: MIJ expects the dimensions of a 3D color image to be the
% following: [ x y z color ]; this is why we did this 'cat' operation just
% above. However, if you want to display the data in MATLAB's native
% implay, they must be in the following order: [ x y color z ]. In the
% latter case, 'permute' is your friend.
J = cat(4, R,G,B);

% First, we launch Miji. Here we use the launcher in non-interactive mode.
% The only thing that this will do is actually to set the path so that the
% subsequent commands and classes can be found by Matlab.
% We launched it with a 'false' in argument, to specify that we do not want
% to diplay the ImageJ toolbar. Indeed, this example is a command line
% example, so we choose not to display the GUI. Feel free to experiment.

if exist('MIJ','class') == 8
    if ~isempty(ij.gui.Toolbar.getInstance)
        ij_instance = char(ij.gui.Toolbar.getInstance.toString);
        % -> ij.gui.Toolbar[canvas1,3,41,548x27,invalid]
        if numel(strfind(ij_instance, 'invalid')) > 0    % instance already exist, but not shown
            utils.fiji.Miji_wrapper(true);     % wrapper to Miji.m file
        end
    else
        utils.fiji.Miji_wrapper(true);     % wrapper to Miji.m file
    end
else
    utils.fiji.Miji_wrapper(true);     % wrapper to Miji.m file
end


% The 3D viewer can only display ImagePlus. ImagePlus is the way ImageJ
% represent images. We can't feed it directly MATLAB data. Fortunately,
% that is where MIJ comes into handy. It has a function that can create an
% ImagePlus from a Matlab object.
% 1. The first argument is the name we will give to the image.
% 2. The second argument is the Matlab data
% 3. The last argument is a boolean. If true, the ImagePlus will be
% displayed as an image sequence. You might find this useful as well.
if size(Volume,4) == 1 % grayscale
    pwb.updateText('Creating the grayscale data...'); pwb.setCurrentIteration(69); pwb.increment();
    imp = MIJ.createImage('im_browser data', squeeze(Volume), false);
else
    pwb.updateText('Creating the color data...'); pwb.setCurrentIteration(69); pwb.increment();
    imp = MIJ.createColor('im_browser data', J, false);
end

%%
% Since we had a color volume (4D data), we used the createColor method. If
% we had only a grayscale volume (3D data), we could have used the
% createImage method instead, which works the same.

%%
% Now comes a little non-mandatory tricky bit.
% By default, the 3D viewer will assume that the image voxel is square,
% that is, every voxel has a size of 1 in the X, Y and Z direction.
% However, for the MRI data we are playing with, this is incorrect, as a
% voxel is 2.5 times larger in the Z direction that in the X and Y
% direction.
% If we do not correct that, the head we are trying to display will look
% flat.
% A way to tell this to the 3D viewer is to create a Calibration object and
% set its public field pixelDepth to 2.5. Then we set this object to be the
% calibration of the ImagePlus, and the 3D viewer will be able to deal with
% it.
pwb.updateText('Set voxel scaling...'); pwb.setCurrentIteration(89); pwb.increment();
calibration = ij.measure.Calibration();
calibration.pixelWidth = pixSize.x*factorX;
calibration.pixelHeight = pixSize.y*factorY;
calibration.pixelDepth = pixSize.z*factorZ;
%calibration.setUnits = pixSize.units;
%calibration.pixelDepth = (pixSize.z/pixSize.x)/factorZ;
imp.setCalibration(calibration);

%% Display the data in ImageJ 3D viewer
% Now for the display itself.
%
% We create an empty 3D viewer to start with. We do not show it yet.
pwb.updateText('Creating 3D Universe...'); pwb.setCurrentIteration(94); pwb.increment();
universe = ij3d.Image3DUniverse();

%%
% Now we show the 3D viewer window.
universe.show();

%%
% Then we send it the data, and ask it to be displayed as a volumetric
% rendering.
c = universe.addVoltex(imp);
pwb.deletePoolWaitbar();
toc
result = 1;
end
