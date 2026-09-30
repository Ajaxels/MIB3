function doObjectSeparation(obj)
% DOOBJECTSEPARATION - Perform watershed-based object separation.
%
% Reads configuration from ``obj.BatchOpt`` and runs a seeded or standard
% distance-transform watershed on the chosen layer (selection / mask /
% labels), storing the result back into the selection layer.
%
% Four processing branches:
%
% * Seeded + 3D   - full-volume seeded watershed
% * Seeded + 2D   - per-slice seeded watershed
% * Standard + 3D - full-volume distance-transform watershed
% * Standard + 2D - per-slice distance-transform watershed
%
% The function is a split method and is called from ``ObjectSeparator.m``.

% Author: Ilya Belevich, University of Helsinki (ilya.belevich @ helsinki.fi)
% Part of Microscopy Image Browser, http://mib.helsinki.fi
% License: GNU General Public License v3, https://www.gnu.org/licenses/gpl-3.0.en.html

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.ObjectSeparator.doObjectSeparation: triggered\n');
end
id = obj.BatchOpt.id;

%% --- Parse BatchOpt ---
aspect = str2num(obj.BatchOpt.AspectRatio); %#ok<ST2NM>

% Color channel: 'Ch 1' → 1
colorChannelIndex = str2double(strrep(obj.BatchOpt.ColorChannel{1}, 'Ch ', ''));

invertImage  = strcmp(obj.BatchOpt.InvertImage{1}, 'black-on-white, signal is dark');
useSeeds     = obj.BatchOpt.UseSeeds;
isIntensity  = strcmp(obj.BatchOpt.WatershedSource{1}, 'Intensity');
is3D         = strcmp(obj.BatchOpt.Mode{1}, 'mode3dRadio');
reduceOverseg = obj.BatchOpt.ReduceOversegmentation;

%% --- Backup ---
if ~isempty(obj.view)
    if strcmp(obj.BatchOpt.Mode{1}, 'mode2dCurrentRadio')
        obj.mibModel.backup('selection', 0, struct('id', id));
    else
        obj.mibModel.backup('selection', 1, struct('id', id));
    end
end

%% --- Subarea ---
xRange = str2num(obj.BatchOpt.XSubarea); %#ok<ST2NM>
yRange = str2num(obj.BatchOpt.YSubarea); %#ok<ST2NM>
zRange = str2num(obj.BatchOpt.ZSubarea); %#ok<ST2NM>

getDataOptions.x  = [min(xRange) max(xRange)];
getDataOptions.y  = [min(yRange) max(yRange)];
getDataOptions.z  = [min(zRange) max(zRange)];
getDataOptions.id = id;

if strcmp(obj.BatchOpt.Mode{1}, 'mode2dCurrentRadio')
    currentSliceIndex         = obj.mibModel.I{id}.slices{3}(1);
    getDataOptions.z          = [currentSliceIndex currentSliceIndex];
end

%% --- Binning ---
binValues = str2num(obj.BatchOpt.Binning); %#ok<ST2NM>
binXY     = binValues(1);
binZ      = binValues(2);

xWidth    = max(xRange) - min(xRange) + 1;
yHeight   = max(yRange) - min(yRange) + 1;
zDepth    = max(zRange) - min(zRange) + 1;   % original subarea depth (for resize-back)

binWidth  = ceil(xWidth  / binXY);
binHeight = ceil(yHeight / binXY);
binDepth  = ceil(zDepth  / binZ);

needsBinning = (binXY ~= 1 || binZ ~= 1);

%% --- Object source (type + material index) ---
switch obj.BatchOpt.ObjectSource{1}
    case 'Selection'
        inputType          = 'selection';
        objectMaterialIndex = [];
    case 'Mask'
        inputType          = 'mask';
        objectMaterialIndex = [];
    case 'Model'
        inputType          = 'labels';
        materialNames      = obj.mibModel.I{id}.labels.materialNames;
        objectMaterialIndex = find(strcmp(materialNames, obj.BatchOpt.ObjectMaterial{1}), 1);
        if isempty(objectMaterialIndex); objectMaterialIndex = 1; end
end

%% --- Seed source (type + material index) ---
switch obj.BatchOpt.SeedSource{1}
    case 'seedsSelection'
        seedType          = 'selection';
        seedMaterialIndex = [];
    case 'seedsMask'
        seedType          = 'mask';
        seedMaterialIndex = [];
    case 'seedsModel'
        seedType          = 'labels';
        materialNames     = obj.mibModel.I{id}.labels.materialNames;
        seedMaterialIndex = find(strcmp(materialNames, obj.BatchOpt.SeedMaterial{1}), 1);
        if isempty(seedMaterialIndex); seedMaterialIndex = 1; end
end

%% --- Progress bar ---
if obj.BatchOpt.showWaitbar
    if is3D
        progressSteps = 10;
    else
        progressSteps = getDataOptions.z(2) - getDataOptions.z(1) + 1;
        if progressSteps < 1; progressSteps = 1; end
    end
    if ~isempty(obj.view)
        parentFig = obj.view.gui;
    else
        parentFig = obj.mibGUI;
    end
    pwb = core.PoolWaitbar(progressSteps, 'Object separation, please wait...', ...
        parentFig, 'Object separation', true);
end

tic;

%% =====================================================================
%% SEEDED WATERSHED
%% =====================================================================
if useSeeds
    if is3D
        % ----- Seeded 3D -----
        objectVolume = squeeze(cell2mat(obj.mibModel.getData3D(inputType, [], 3, objectMaterialIndex, getDataOptions)));
        seedVolume   = squeeze(cell2mat(obj.mibModel.getData3D(seedType,  [], 3, seedMaterialIndex,  getDataOptions)));

        if isIntensity
            intensityVolume = squeeze(cell2mat(obj.mibModel.getData3D('image', [], 3, colorChannelIndex, getDataOptions)));
        end

        if needsBinning
            if obj.BatchOpt.showWaitbar
                pwb.updateText('Binning the data, please wait...'); pwb.increment();
                if pwb.getCancelState(); pwb.deletePoolWaitbar(); return; end
            end
            resizeOptions.height = binHeight;
            resizeOptions.width  = binWidth;
            resizeOptions.depth  = binDepth;
            resizeOptions.method = 'nearest';
            objectVolume = utils.resizeImage3d(objectVolume, [], resizeOptions);
            seedVolume   = utils.resizeImage3d(seedVolume,   [], resizeOptions);
            if isIntensity
                resizeOptions.method = 'bicubic';
                intensityVolume = utils.resizeImage3d(intensityVolume, [], resizeOptions);
            end
            aspect(1) = aspect(1) * binXY;
            aspect(2) = aspect(2) * binXY;
            aspect(3) = aspect(3) * binZ;
        end

        if isIntensity
            if invertImage
                if obj.BatchOpt.showWaitbar
                    pwb.updateText('Complementing the image, please wait...'); pwb.increment();
                    if pwb.getCancelState(); pwb.deletePoolWaitbar(); return; end
                end
                intensityVolume = imcomplement(intensityVolume);
            end
            if obj.BatchOpt.showWaitbar
                pwb.updateText('Updating local minima, please wait...'); pwb.increment();
                if pwb.getCancelState(); pwb.deletePoolWaitbar(); return; end
            end
            W = imimposemin(intensityVolume, ~objectVolume | seedVolume);
            clear intensityVolume;
        else
            if obj.BatchOpt.showWaitbar
                pwb.updateText('Computing the distance transform, please wait...'); pwb.increment();
                if pwb.getCancelState(); pwb.deletePoolWaitbar(); return; end
            end
            if aspect(1)/aspect(3) > 0.65 && aspect(1)/aspect(3) <= 1.5
                W = bwdist(~objectVolume);
            else
                W = bwdistsc(~objectVolume, aspect);
            end
            if obj.BatchOpt.showWaitbar
                pwb.updateText('Complementing the distance map, please wait...'); pwb.increment();
                if pwb.getCancelState(); pwb.deletePoolWaitbar(); return; end
            end
            W = -W;
            if obj.BatchOpt.showWaitbar
                pwb.updateText('Generating local minima, please wait...'); pwb.increment();
                if pwb.getCancelState(); pwb.deletePoolWaitbar(); return; end
            end
            W = imimposemin(W, seedVolume);
        end

        if obj.BatchOpt.showWaitbar
            pwb.updateText('Computing watershed regions, please wait...'); pwb.increment();
            if pwb.getCancelState(); pwb.deletePoolWaitbar(); return; end
        end
        W = watershed(W);

        if obj.BatchOpt.showWaitbar
            pwb.updateText('Removing background, please wait...'); pwb.increment();
            if pwb.getCancelState(); pwb.deletePoolWaitbar(); return; end
        end
        W(~objectVolume) = 0;

        % bwlabeln distinguishes objects that share the same watershed label
        % but lack a seed - those must be discarded
        if obj.BatchOpt.showWaitbar
            pwb.updateText('Relabeling the objects, please wait...'); pwb.increment();
            if pwb.getCancelState(); pwb.deletePoolWaitbar(); return; end
        end
        W = bwlabeln(W);

        if obj.BatchOpt.showWaitbar
            pwb.updateText('Generating resulting image, please wait...'); pwb.increment();
            if pwb.getCancelState(); pwb.deletePoolWaitbar(); return; end
        end
        objectIndices = unique(W(seedVolume ~= 0));
        objectIndices(objectIndices == 0) = [];
        W = uint8(ismember(W, objectIndices));

        if needsBinning
            resizeOptions.height = yHeight;
            resizeOptions.width  = xWidth;
            resizeOptions.depth  = zDepth;
            resizeOptions.method = 'nearest';
            W = utils.resizeImage3d(W, [], resizeOptions);
        end

        obj.mibModel.setData3D(W, 'selection', [], 3, [], getDataOptions);

        if obj.BatchOpt.showWaitbar; pwb.updateText('Done!'); pwb.increment(); end

    else
        % ----- Seeded 2D loop -----
        for sliceIndex = getDataOptions.z(1) : getDataOptions.z(2)
            if obj.BatchOpt.showWaitbar
                if pwb.getCancelState(); pwb.deletePoolWaitbar(); return; end
                pwb.increment();
            end

            objectSlice = cell2mat(obj.mibModel.getData2D(inputType, sliceIndex, [], objectMaterialIndex, getDataOptions));
            seedSlice   = cell2mat(obj.mibModel.getData2D(seedType,   sliceIndex, [], seedMaterialIndex,   getDataOptions));
            if max(seedSlice(:)) == 0; continue; end   % no seeds → skip this slice

            if isIntensity
                intensitySlice = cell2mat(obj.mibModel.getData2D('image', sliceIndex, [], colorChannelIndex, getDataOptions));
            end

            if binXY ~= 1
                objectSlice = imresize(objectSlice, [binHeight binWidth], 'nearest');
                seedSlice   = imresize(seedSlice,   [binHeight binWidth], 'nearest');
                if isIntensity
                    intensitySlice = imresize(intensitySlice, [binHeight binWidth], 'bicubic');
                end
            end

            if isIntensity
                if invertImage
                    intensitySlice = imcomplement(intensitySlice);
                end
                W = imimposemin(intensitySlice, ~objectSlice | seedSlice);
            else
                W = bwdistsc(~objectSlice, [aspect(1) aspect(2)]);
                W = -W;
                W = imimposemin(W, seedSlice);
            end

            W = watershed(W);
            W(~objectSlice) = 0;
            W = bwlabeln(W);
            objectIndices = unique(W(seedSlice ~= 0));
            W = uint8(ismember(W, objectIndices));

            if binXY ~= 1
                W = imresize(W, [yHeight xWidth], 'nearest');
            end

            obj.mibModel.setData2D(W, 'selection', sliceIndex, [], [], getDataOptions);
        end
    end

%% =====================================================================
%% STANDARD (non-seeded) WATERSHED
%% =====================================================================
else
    if is3D
        % ----- Standard 3D -----
        objectVolume = squeeze(cell2mat(obj.mibModel.getData3D(inputType, [], 3, objectMaterialIndex, getDataOptions)));

        if needsBinning
            if obj.BatchOpt.showWaitbar
                pwb.updateText('Binning the dataset, please wait...'); pwb.increment();
                if pwb.getCancelState(); pwb.deletePoolWaitbar(); return; end
            end
            resizeOptions.height = binHeight;
            resizeOptions.width  = binWidth;
            resizeOptions.depth  = binDepth;
            resizeOptions.method = 'nearest';
            objectVolume = utils.resizeImage3d(objectVolume, [], resizeOptions);
            aspect(1) = aspect(1) * binXY;
            aspect(2) = aspect(2) * binXY;
            aspect(3) = aspect(3) * binZ;
        end

        if obj.BatchOpt.showWaitbar
            pwb.updateText('Computing the distance transform, please wait...'); pwb.increment();
            if pwb.getCancelState(); pwb.deletePoolWaitbar(); return; end
        end
        distanceMap = bwdistsc(~objectVolume, aspect);
        distanceMap = -distanceMap;

        if reduceOverseg
            if obj.BatchOpt.showWaitbar
                pwb.updateText('Reducing oversegmentation, please wait...'); pwb.increment();
                if pwb.getCancelState(); pwb.deletePoolWaitbar(); return; end
            end
            oversegMask = imextendedmin(distanceMap, 2);
            distanceMap = imimposemin(distanceMap, oversegMask);
        end

        if obj.BatchOpt.showWaitbar
            pwb.updateText('Computing watershed regions, please wait...'); pwb.increment();
            if pwb.getCancelState(); pwb.deletePoolWaitbar(); return; end
        end
        distanceMap = uint8(watershed(distanceMap));

        if obj.BatchOpt.showWaitbar
            pwb.updateText('Generating resulting image, please wait...'); pwb.increment();
            if pwb.getCancelState(); pwb.deletePoolWaitbar(); return; end
        end
        distanceMap(~objectVolume) = 0;
        distanceMap(distanceMap > 1) = 1;   % flatten: watershed labels → binary

        if needsBinning
            resizeOptions.height = yHeight;
            resizeOptions.width  = xWidth;
            resizeOptions.depth  = zDepth;
            resizeOptions.method = 'nearest';
            distanceMap = utils.resizeImage3d(distanceMap, [], resizeOptions);
        end

        obj.mibModel.setData3D(distanceMap, 'selection', [], 3, [], getDataOptions);

        if obj.BatchOpt.showWaitbar; pwb.updateText('Done!'); pwb.increment(); end

    else
        % ----- Standard 2D loop -----
        for sliceIndex = getDataOptions.z(1) : getDataOptions.z(2)
            if obj.BatchOpt.showWaitbar
                if pwb.getCancelState(); pwb.deletePoolWaitbar(); return; end
                pwb.increment();
            end

            objectSlice = cell2mat(obj.mibModel.getData2D(inputType, sliceIndex, [], objectMaterialIndex, getDataOptions));

            if binXY ~= 1
                objectSlice = imresize(objectSlice, [binHeight binWidth], 'nearest');
            end

            W = bwdistsc(~objectSlice, [aspect(1) aspect(2)]);
            W = -W;

            if reduceOverseg
                oversegMask = imextendedmin(W, 2);
                W = imimposemin(W, oversegMask);
            end

            W = uint8(watershed(W));
            W(~objectSlice) = 0;
            W(W > 1) = 1;   % flatten: watershed labels → binary

            if binXY ~= 1
                W = imresize(W, [yHeight xWidth], 'nearest');
            end

            obj.mibModel.setData2D(W, 'selection', sliceIndex, [], [], getDataOptions);
        end
    end
end

%% --- Cleanup ---
if obj.BatchOpt.showWaitbar; pwb.deletePoolWaitbar(); end

fprintf('Object separation: elapsed time %.3f seconds\n', toc);
notify(obj.mibModel, 'ShowImage');
end
