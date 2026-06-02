function result = renderModelWithFiji(Volume, materialIndex, pixSize, colorList, mibGUI)
% RENDERMODELWITHFIJI - Render a segmentation model as a volume in Fiji's 3D Viewer.
%
% Requires Fiji to be installed (http://fiji.sc/Fiji).
%
% Based on ``mibRenderModelFiji.m`` and ``Matlab3DViewerDemo_1.m``
% by Jean-Yves Tinevez \<jeanyves.tinevez at gmail.com\>.
%
% Syntax:
%   .. code-block:: matlab
%
%      result = utils.fiji.renderModelWithFiji(Volume, materialIndex, pixSize)
%      result = utils.fiji.renderModelWithFiji(Volume, materialIndex, pixSize, colorList)
%      result = utils.fiji.renderModelWithFiji(Volume, materialIndex, pixSize, colorList, mibGUI)
%
% Input Arguments:
%   - **Volume** — [uint8] 3D label volume, dimensions [height, width, depth]; voxel values are material indices
%   - **materialIndex** — [numeric] material to render: ``0`` renders all materials as RGB; any positive integer renders that single material as grayscale
%   - **pixSize** — struct with physical voxel dimensions:
%
%     - ``.x`` — physical width
%     - ``.y`` — physical height
%     - ``.z`` — physical thickness
%     - ``.units`` — physical units string
%
%   - **colorList** *(optional)* — [M × 3 double] RGB color map for materials, values 0–1; row index corresponds to material index
%   - **mibGUI** *(optional)* — handle to the parent UIFigure for dialogs and progress bar
%
% Output Arguments:
%   - **result** — [logical] ``0`` on failure, ``1`` on success
%
% Updates
%

if nargin < 5; mibGUI = []; end
if nargin < 4 || isempty(colorList)
    colorList = rand(255, 3);
end

result = 0;

if ~isa(Volume, 'uint8')
    utils.dlgs.showErrorDialog(mibGUI, ...
        sprintf('The model renderer expects uint8 data!\nCurrent type: %s', class(Volume)), ...
        'Data type error');
    return;
end

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

try
    if ~IsJava3DInstalled(true)
        dlgOpt.MsgBoxOnly = true;
        dlgOpt.Icon = 'puffin_error';
        utils.dlgs.inputUniversalDlg(mibGUI, '', {''}, ...
            {'Java3D is not installed'}, 'Java error!', dlgOpt);
        return;
    end
catch
    % skip — IsJava3DInstalled may be unavailable in newer Fiji versions
end

prompt = {'Reduce the volume down to, max width pixels [no volume reduction when 0]?'};
defAns = {struct('Spinner', true, 'Value', 512, 'Limits', [0 Inf], 'Step', 1, 'Round', true)};
dlgOpt.WindowHeight = 160;
answer = utils.dlgs.inputUniversalDlg(mibGUI, '', prompt, defAns, 'Volume parameters', dlgOpt);
if isempty(answer); return; end

maxVolumeWidth = answer{1};
if maxVolumeWidth ~= 0
    factorX = ceil(size(Volume, 2) / maxVolumeWidth);
    factorY = ceil(factorX * pixSize.x / pixSize.y - 0.001);
    factorZ = ceil(factorX * pixSize.x / pixSize.z);
else
    factorX = 1; factorY = 1; factorZ = 1;
end
width  = ceil(size(Volume, 2) / factorX);
height = ceil(size(Volume, 1) / factorY);
depth  = ceil(size(Volume, 3) / factorZ);

if materialIndex == 0
    minMaterial = 1;
    maxMaterial = max(Volume(:));
else
    minMaterial = materialIndex;
    maxMaterial = materialIndex;
end

isColorRendering = (minMaterial ~= maxMaterial);

pwb = core.PoolWaitbar(100, 'Preparing the volume...', mibGUI, 'Fiji rendering', true);

if isColorRendering
    redChannel   = zeros(height, width, depth, class(Volume));
    greenChannel = zeros(height, width, depth, class(Volume));
    blueChannel  = zeros(height, width, depth, class(Volume));

    for materialIdx = minMaterial:maxMaterial
        pwb.updateText(sprintf('Processing material %d/%d (%d x %d x %d px)...', ...
            materialIdx, maxMaterial, height, width, depth));
        pwb.setCurrentIteration(round(49 * materialIdx / maxMaterial)); pwb.increment();

        subVolume = Volume == materialIdx;
        [~, ~, ~, subVolume] = reducevolume(subVolume, [factorY, factorX, factorZ]);

        if materialIdx <= size(colorList, 1)
            redChannel(subVolume)   = colorList(materialIdx, 1) * 255;
            greenChannel(subVolume) = colorList(materialIdx, 2) * 255;
            blueChannel(subVolume)  = colorList(materialIdx, 3) * 255;
        end
    end
    colorData = cat(4, redChannel, greenChannel, blueChannel);
else
    pwb.updateText(sprintf('Reducing volume to %d x %d x %d px...', height, width, depth));
    pwb.setCurrentIteration(29); pwb.increment();

    subVolume = Volume == minMaterial;
    [~, ~, ~, subVolume] = reducevolume(subVolume, [factorY, factorX, factorZ]);
    subVolume = uint8(subVolume) * 254;
end

pwb.updateText('Launching Fiji...'); pwb.setCurrentIteration(55); pwb.increment();
if exist('MIJ', 'class') == 8
    if ~isempty(ij.gui.Toolbar.getInstance)
        ijInstance = char(ij.gui.Toolbar.getInstance.toString);
        if numel(strfind(ijInstance, 'invalid')) > 0
            io.Fiji.Miji_wrapper(true);
        end
    else
        io.Fiji.Miji_wrapper(true);
    end
else
    io.Fiji.Miji_wrapper(true);
end

pwb.updateText('Creating image data...'); pwb.setCurrentIteration(69); pwb.increment();
if isColorRendering
    imp = MIJ.createColor('MIB model', colorData, false);
else
    imp = MIJ.createImage('MIB model', subVolume, false);
end

pwb.updateText('Setting voxel calibration...'); pwb.setCurrentIteration(89); pwb.increment();
calibration = ij.measure.Calibration();
calibration.pixelWidth  = pixSize.x * factorX;
calibration.pixelHeight = pixSize.y * factorY;
calibration.pixelDepth  = pixSize.z * factorZ;
imp.setCalibration(calibration);

pwb.updateText('Creating 3D Universe...'); pwb.setCurrentIteration(94); pwb.increment();
universe = ij3d.Image3DUniverse();
universe.show();
universe.addVoltex(imp);

pwb.deletePoolWaitbar();
result = 1;
end
