function connImaris = setImarisDataset(mibDataset, connImaris, options)
% function connImaris = setImarisDataset(mibDataset, connImaris, options)
% Send a dataset layer from MIB to Imaris
%
% Parameters:
% mibDataset: an instance of core.MibDataset with the dataset to export
% connImaris: [@em optional] a handle to an existing Imaris connection
% options: [@em optional] a structure with additional settings
% @li .type -> [@em optional] type of dataset layer to send
%     'image' [@em default], 'labels' (model), 'mask', 'selection'
% @li .modelIndex -> [@em optional] for 'labels': material index to send
%     (@em NaN = all materials, integer = single material)
%     for 'mask' and 'selection': not used (ignored)
% @li .mode -> [@em optional] '3D' or '4D' export mode; prompted if omitted and time > 1
% @li .insertInto -> [@em optional] cell with time-point index; -1 = replace whole dataset
% @li .lutColors -> [@em optional] [nChannels x 3] matrix of RGB colors (0-1) for image channels
% @li .maskColor -> [@em optional] [1 x 3] RGB color (0-1) for mask display in Imaris; default [1 0 0]
% @li .showWaitbar -> logical, show or not the waitbar
% @li .mibGUI -> [@em optional] handle to the main MIB window for dialogs
%
% Return values:
% connImaris: a handle to the Imaris connection

% @note
% Uses IceImarisConnector bindings.
% @b Requires:
% 1. Set system environment variable IMARISPATH to the Imaris installation directory
% 2. Restart MATLAB

%|
% @b Examples:
% @code
% imarisOpts.type = 'image';
% imarisOpts.lutColors = obj.mibModel.I{id}.image.lutColors;
% imarisOpts.mibGUI = obj.mibGUI;
% obj.mibModel.connImaris = io.imaris.setImarisDataset(obj.mibModel.I{id}, obj.mibModel.connImaris, imarisOpts);
% @endcode

% Updates
% MIB3 port: mibImage (mibImage class) replaced by mibDataset (core.MibDataset).
% Key API differences from MIB2:
%   slices{3}=colors(MIB2) -> slices{4}=colors(MIB3)
%   getData(type,4,...) -> getData4D(type,3,...) returns cell; cell2mat needed
%   type 'model'(MIB2) -> 'labels'(MIB3); both strings accepted here
%   image.meta('imgClass') -> image.dataClass
%   modelMaterialNames -> labels.materialNames
%   modelMaterialColors -> labels.materialColors
%   model{1} -> labels.data{1}
%   getBoundingBox() -> image.boundingBox (direct property [xMin xMax yMin yMax zMin zMax])
%   meta('ImageDescription') -> core.MibImage.buildImageDescription(...)
%   Virtual.virtual -> strcmp(datasetType,'Virtual')

if nargin < 3; options = struct(); end
if nargin < 2; connImaris = []; end

if strcmp(mibDataset.datasetType, 'Virtual')
    dlgOpt = struct();
    dlgOpt.MsgBoxOnly = true;
    dlgOpt.Icon = 'puffin_error';
    if isfield(options, 'mibGUI') && ~isempty(options.mibGUI)
        utils.dlgs.inputUniversalDlg(options.mibGUI, '!!! Error !!!', {''}, ...
            {'This mode is not yet implemented for the virtual stacking mode'}, ...
            'Not implemented', dlgOpt);
    else
        errordlg('This mode is not yet implemented for the virtual stacking mode', 'Not implemented');
    end
    return;
end

if ~isfield(options, 'type'); options.type = 'image'; end
% accept legacy 'model' type from MIB2 callers
if strcmp(options.type, 'model'); options.type = 'labels'; end
if ~isfield(options, 'modelIndex'); options.modelIndex = NaN; end
if ~isfield(options, 'showWaitbar'); options.showWaitbar = true; end
if ~isfield(options, 'mibGUI'); options.mibGUI = []; end
if ~isfield(options, 'maskColor'); options.maskColor = [1 0 0]; end  % default red

% establish Imaris connection
connImaris = io.imaris.connectToImaris(connImaris, options.mibGUI);
if isempty(connImaris); return; end

% determine 3D vs 4D mode
if isfield(options, 'mode')
    mode = options.mode;
else
    if mibDataset.image.time > 1
        if ~isempty(options.mibGUI)
            mode = utils.dlgs.inputQuestDlg(options.mibGUI, ...
                sprintf('Export currently shown 3D (W×H×C×Z) stack or complete 4D (W×H×C×Z×T) dataset?'), ...
                'Export to Imaris', '3D', '4D', '3D');
        else
            mode = questdlg('Export currently shown 3D (W×H×C×Z) stack or complete 4D (W×H×C×Z×T) dataset?', ...
                'Export to Imaris', '3D', '4D', 'Cancel', '3D');
        end
        if isempty(mode) || strcmp(mode, 'Cancel'); return; end
    else
        mode = '3D';
    end
end

options.blockModeSwitch = 0;

% read dataset dimensions directly from MibImage properties
sizeY     = mibDataset.image.height;
sizeX     = mibDataset.image.width;
maxColors = mibDataset.image.colors;
sizeZ     = mibDataset.image.depth;
maxTime   = mibDataset.image.time;

blockSizeX = 512;
blockSizeY = 512;
blockSizeZ = 512;

useBlockMode = sizeX * sizeY * sizeZ > 134217728;  % 512×512×512

switch options.type
    case 'image'
        noColors  = numel(mibDataset.slices{4});   % number of currently shown color channels
        dataClass = mibDataset.image.dataClass;
    case 'mask'
        noColors            = 1;
        options.modelIndex  = NaN;                 % mask is a single binary layer
        dataClass           = 'uint8';
    otherwise  % 'labels'
        if isnan(options.modelIndex)
            noColors           = numel(mibDataset.labels.materialNames);
            options.modelIndex = 1:noColors;
        else
            noColors = numel(options.modelIndex);
        end
        dataClass = class(mibDataset.labels.data{1});
end

updateBoundingBox = 1;
if strcmp(mode, '4D')
    connImaris.createDataset(dataClass, sizeX, sizeY, sizeZ, noColors, maxTime);
    timePointsIn  = 1:maxTime;
    timePointsOut = 1:maxTime;
elseif isempty(connImaris.mImarisApplication.GetDataSet) && strcmp(mode, '3D')
    connImaris.createDataset(dataClass, sizeX, sizeY, sizeZ, noColors, 1);
    timePointsIn  = mibDataset.slices{5}(1);
    timePointsOut = 1;
else
    [vSizeX, vSizeY, vSizeZ, vSizeC, vSizeT] = connImaris.getSizes();
    if vSizeZ > 1 && vSizeT > 1 && strcmp(mode, '3D')
        if ~isfield(options, 'insertInto')
            warningMsg = sprintf('!!! Warning !!!\n\nA 5D dataset is open in Imaris!\nEnter a time point to update (starting from 0)\nor type "-1" to replace the dataset completely');
            if ~isempty(options.mibGUI)
                answer = utils.dlgs.inputUniversalDlg(options.mibGUI, '', ...
                    {warningMsg}, {num2str(mibDataset.slices{5}(1))}, ...
                    'Time point', struct());
            else
                answer = inputdlg(warningMsg, 'Time point', 1, {num2str(mibDataset.slices{5}(1))});
            end
            if isempty(answer); return; end
            insertInto = answer;
        else
            insertInto = options.insertInto;
        end
        if str2double(insertInto{1}) == -1
            connImaris.createDataset(dataClass, sizeX, sizeY, sizeZ, noColors, 1);
            timePointsIn  = mibDataset.slices{5}(1);
            timePointsOut = 1;
        else
            timePointsIn      = str2double(insertInto{1});
            timePointsOut     = str2double(insertInto{1});
            updateBoundingBox = 0;
        end
    else
        connImaris.createDataset(dataClass, sizeX, sizeY, sizeZ, noColors, 1);
        timePointsIn  = mibDataset.slices{5}(1);
        timePointsOut = 1;
    end
end

if options.showWaitbar
    waitbarHandle = waitbar(0, 'Please wait...', 'Name', 'Export to Imaris');
end
callsId = 0;

if useBlockMode
    maxWaitbarIndex = noColors * ceil(sizeZ/blockSizeZ) * ceil(sizeY/blockSizeY) * ceil(sizeX/blockSizeX) * numel(timePointsIn);
else
    maxWaitbarIndex = numel(timePointsIn) * noColors;
end

% color/LUT data for channel configuration
if ~isfield(options, 'lutColors') || isempty(options.lutColors)
    options.lutColors = rand(noColors, 3);
end
colorData = options.lutColors;

getDataOptions.blockModeSwitch = 0;

tIndex = 1;
for timePoint = timePointsIn
    getDataOptions.t = [timePoint timePoint];

    for colId = 1:noColors
        % retrieve pixel data for this channel/material
        switch options.type
            case 'image'
                colorIndex = mibDataset.slices{4}(colId);
                img = squeeze(cell2mat(mibDataset.getData4D('image', 3, colorIndex, getDataOptions)));
            case 'mask'
                colorIndex = NaN;
                img = squeeze(cell2mat(mibDataset.getData4D('mask', 3, NaN, getDataOptions)));
            otherwise  % 'labels'
                colorIndex = options.modelIndex(colId);
                img = squeeze(cell2mat(mibDataset.getData4D('labels', 3, colorIndex, getDataOptions)));
        end

        % push to Imaris
        if ~useBlockMode
            connImaris.setDataVolumeRM(img(:,:,:), colId-1, timePointsOut(tIndex)-1);
            callsId = callsId + 1;
        else
            for blockZ = 0:ceil(sizeZ/blockSizeZ)-1
                for blockY = 0:ceil(sizeY/blockSizeY)-1
                    for blockX = 0:ceil(sizeX/blockSizeX)-1
                        imgBlock = img( ...
                            1+blockSizeY*blockY : min(blockSizeY+blockSizeY*blockY, sizeY), ...
                            1+blockSizeX*blockX : min(blockSizeX+blockSizeX*blockX, sizeX), ...
                            1+blockSizeZ*blockZ : min(blockSizeZ+blockSizeZ*blockZ, sizeZ));
                        connImaris.mib_setDataSubVolumeRM(imgBlock, ...
                            blockSizeX*blockX, blockSizeY*blockY, blockSizeZ*blockZ, ...
                            colId-1, timePointsOut(tIndex)-1, ...
                            size(imgBlock,2), size(imgBlock,1), size(imgBlock,3));
                        callsId = callsId + 1;
                        if options.showWaitbar; waitbar(callsId/maxWaitbarIndex, waitbarHandle); end
                    end
                end
            end
        end

        % configure channel color and display range (first time point only)
        if timePoint == timePointsIn(1)
            switch options.type
                case 'image'
                    colorIndex = mibDataset.slices{4}(colId);
                    connImaris.mImarisApplication.GetDataSet.SetChannelRange(colId-1, ...
                        mibDataset.image.viewPort.min(colorIndex), ...
                        mibDataset.image.viewPort.max(colorIndex));
                    connImaris.mImarisApplication.GetDataSet.SetChannelGamma(colId-1, ...
                        mibDataset.image.viewPort.gamma(colorIndex));
                    channelRGB = colorData(colorIndex, :);
                    if sum(channelRGB) == 0; channelRGB = [1 1 1]; end   % replace black with white
                    ColorRGBA = connImaris.mapRgbaVectorToScalar([channelRGB 0]);
                case 'mask'
                    ColorRGBA = connImaris.mapRgbaVectorToScalar([options.maskColor 0]);
                    connImaris.mImarisApplication.GetDataSet.SetChannelRange(colId-1, 0, max(img(:)));
                otherwise  % 'labels'
                    ColorRGBA = connImaris.mapRgbaVectorToScalar( ...
                        [mibDataset.labels.materialColors(colorIndex, :) 0]);
                    connImaris.mImarisApplication.GetDataSet.SetChannelRange(colId-1, 0, max(img(:)));
            end
            connImaris.mImarisApplication.GetDataSet.SetChannelColorRGBA(colId-1, ColorRGBA);
        end

        if options.showWaitbar && ~useBlockMode
            waitbar(callsId/maxWaitbarIndex, waitbarHandle);
        end
    end
    tIndex = tIndex + 1;
end

% update bounding box and image description in Imaris
if updateBoundingBox
    bb = mibDataset.image.boundingBox;   % [xMin xMax yMin yMax zMin zMax]
    connImaris.mImarisApplication.GetDataSet.SetExtendMinX(bb(1));
    connImaris.mImarisApplication.GetDataSet.SetExtendMaxX(bb(2));
    connImaris.mImarisApplication.GetDataSet.SetExtendMinY(bb(3));
    connImaris.mImarisApplication.GetDataSet.SetExtendMaxY(bb(4));
    connImaris.mImarisApplication.GetDataSet.SetExtendMinZ(bb(5));
    if size(img, 3) > 1
        connImaris.mImarisApplication.GetDataSet.SetExtendMaxZ(bb(6) + mibDataset.image.pixSize.z);
    else
        connImaris.mImarisApplication.GetDataSet.SetExtendMaxZ(bb(6));
    end

    % set image description
    imageDescription = core.MibImage.buildImageDescription(mibDataset.image.boundingBox, mibDataset.image.actionLog);
    linefeeds = strfind(imageDescription, '|');
    logOut = '';
    if ~isempty(linefeeds)
        prevPos = 1;
        for i = 1:numel(linefeeds)
            logOut = [logOut sprintf('%s\n', imageDescription(prevPos:linefeeds(i)-1))]; %#ok<AGROW>
            prevPos = linefeeds(i) + 1;
        end
        if prevPos <= numel(imageDescription)
            logOut = [logOut sprintf('%s\n', imageDescription(prevPos:end))];
        end
    end
    connImaris.mImarisApplication.GetDataSet.SetParameter('Image', 'Description', logOut);
end

% synchronise time metadata
if numel(timePointsIn) == 1 && timePointsOut(1) == 1
    connImaris.mImarisApplication.GetDataSet.SetTimePoint(0, '0000-01-00 00:00:00.000');
else
    offsetSeconds = (timePointsIn(1)-1) * mibDataset.image.pixSize.t;
    stringTime = sprintf('0000-01-00 %s', char(seconds(offsetSeconds), 'hh:mm:ss.SSS'));
    connImaris.mImarisApplication.GetDataSet.SetTimePoint(timePointsOut(1)-1, stringTime);
    connImaris.mImarisApplication.GetDataSet.SetTimePointsDelta(mibDataset.image.pixSize.t);
end

if options.showWaitbar; delete(waitbarHandle); end
end
