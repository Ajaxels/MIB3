% This program is free software: you can redistribute it and/or modify
% it under the terms of the GNU General Public License as published by
% the Free Software Foundation, either version 3 of the License, or
% (at your option) any later version.
%
% This program is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
% GNU General Public License for more details.
% You should have received a copy of the GNU General Public License
% along with this program.  If not, see <https://www.gnu.org/licenses/>

% Author: Ilya Belevich, University of Helsinki (ilya.belevich @ helsinki.fi)
% part of Microscopy Image Browser, http:\\mib.helsinki.fi
% Date: 25.04.2023
% Ported from MIB2 to MIB3 package structure (io.IMOD.mibExportModelToImodModel)
% Source: MIB2_RENAMED_FOR_MIB3/ImportExportTools/IMOD/mibExportModelToImodModel.m

function [Model, selection] = mibExportModelToImodModel(O, Options)
% MIBEXPORTMODELTOIMODMODEL - Export model to Imod model type.
%
% Syntax:
%   .. code-block:: matlab
%
%      [Model, selection] = io.IMOD.mibExportModelToImodModel(O, Options)
%
% .. note::
%    Requires matTomo function sets, available in ``mib/external/MatTomo``.
%
% Input Arguments:
%   - **O** - model array [height, width, depth]
%   - **Options** - struct with fields:
%
%     - ``.modelFilename`` - filename to save the model (use ``'mod'`` extension)
%     - ``.pixSize`` - struct with voxel size fields ``.x``, ``.y``, ``.z``
%     - ``.xyScaleFactor`` - XY step when sampling contour points; e.g. ``5`` = every 5th point
%     - ``.zScaleFactor`` - Z step when sampling contour points; ``1`` = every section
%     - ``.colorList`` - [M×3] material RGB colours (0-1)
%     - ``.ModelMaterialNames`` - cell array with material name strings
%     - ``.generateSelectionSw`` - ``1`` = generate the Selection layer with contour points
%     - ``.showWaitbar`` - ``1`` = show the wait bar, ``0`` = hide it
%     - ``.ParentFigure`` - *(optional)* handle to the main MIB UIFigure; when provided,
%       the progress bar is shown as a ``uiprogressdlg`` attached to that window;
%       when absent or empty, the legacy ``waitbar`` is used as a fallback
%
% Output Arguments:
%   - **Model** - IMOD model object
%   - **selection** - selection layer [height, width, depth]
%
% **Example 1** - standalone use (no GUI parent):
%
%   .. code-block:: matlab
%
%      savingOptions.modelFilename       = '/output/Labels.mod';
%      savingOptions.pixSize             = dataset.pixSize;
%      savingOptions.xyScaleFactor       = 5;
%      savingOptions.zScaleFactor        = 1;
%      savingOptions.colorList           = labels.materialColors;
%      savingOptions.ModelMaterialNames  = labels.materialNames;
%      savingOptions.generateSelectionSw = false;
%      savingOptions.showWaitbar         = false;
%      io.IMOD.mibExportModelToImodModel(modelData_hwd, savingOptions);
%
% **Example 2** - GUI use (attach progress dialog to MIB window):
%
%   .. code-block:: matlab
%
%      savingOptions.modelFilename       = '/output/Labels.mod';
%      savingOptions.pixSize             = dataset.pixSize;
%      savingOptions.xyScaleFactor       = 5;
%      savingOptions.zScaleFactor        = 1;
%      savingOptions.colorList           = labels.materialColors;
%      savingOptions.ModelMaterialNames  = labels.materialNames;
%      savingOptions.generateSelectionSw = false;
%      savingOptions.showWaitbar         = true;
%      savingOptions.ParentFigure        = obj.mibModel.mibGUI;
%      io.IMOD.mibExportModelToImodModel(modelData_hwd, savingOptions);
%

% Updates
% 11.04.2016, IB, added showWaitbar option

if ~isfield(Options, 'showWaitbar'); Options.showWaitbar = 1; end

% create IMOD model
modelFilename = Options.modelFilename;

O = permute(O, [2 1 3]);
width = size(O,1);
height = size(O,2);
thickness = size(O,3);

selection = zeros(size(O),'uint8');

Model = ImodModel();
Model = setFilename(Model, modelFilename);
Model = setMax(Model, [width, height, thickness]);
Model = setPixelSize(Model, Options.pixSize.x);
Model = setYScale(Model, Options.pixSize.y/Options.pixSize.x);
Model = setZScale(Model, Options.pixSize.z/Options.pixSize.x);

% O - is a model
Objects = unique(O);
Objects(Objects==0) = [];
noObjects = numel(Objects);
wb = [];
if Options.showWaitbar
    if isfield(Options, 'ParentFigure') && ~isempty(Options.ParentFigure)
        try
            wb = uiprogressdlg(Options.ParentFigure, 'Title', 'Saving contours to IMOD model...', ...
                'Message', sprintf('%s\nPlease wait...', modelFilename));
        catch; wb = []; end
    else
        curInt = get(0, 'DefaulttextInterpreter');
        set(0, 'DefaulttextInterpreter', 'none');
        wb = waitbar(0, sprintf('%s\nPlease wait...', modelFilename), 'Name', 'Saving contours to IMOD model...', 'WindowStyle', 'modal');
        set(findall(wb,'type','text'), 'Interpreter', 'none');
    end
end

noOfProvidedColor = size(Options.colorList, 1);
maxInt = double(intmax(class(Objects)));
for objectLoop=1:noObjects
    object = Objects(objectLoop);

    imodObject = ImodObject;
    if objectLoop > noOfProvidedColor
        imodObject = setColor(imodObject, rand([1 3]));
    else
        imodObject = setColor(imodObject, Options.colorList(objectLoop, :));
    end
    if maxInt > 255
        imodObject = setName(imodObject, num2str(objectLoop));
    else
        imodObject = setName(imodObject, Options.ModelMaterialNames{objectLoop});
    end
    imodObject = setType(imodObject, 'closed');

    BW = zeros(size(O),'uint8');
    BW(O==object) = 1;
    CC = bwconncomp(BW, 6);

    for subobject = 1:CC.NumObjects
        BWtemp = zeros(size(BW),'uint8');
        BWtemp(CC.PixelIdxList{subobject}) = 1;

        for z=1:Options.zScaleFactor:thickness
            if ~any(BWtemp(:,:,z),'all'); continue; end

            img = BWtemp(:,:,z);
            img = bwperim(img);

            CC2 = bwconncomp(img,8);
            for contourId=1:CC2.NumObjects
                [start_pnt1(1), start_pnt1(2)] = ind2sub([width height],CC2.PixelIdxList{contourId}(1));
                contour = bwtraceboundary(img, start_pnt1,'NE');
                if size(contour,1) < Options.xyScaleFactor; continue; end
                contour = contour([1:Options.xyScaleFactor:end end], :);
                contourOut = ones(size(contour,1),1)*(z-1);
                contourOut = [contour contourOut]';

                if Options.generateSelectionSw
                    for ind=1:size(contour,1)
                        selection(contour(ind,1),contour(ind,2),z)=1;
                    end
                end
                imodContour = ImodContour(contourOut);
                imodContour = setSurfaceIdx(imodContour, subobject);
                imodObject = appendContour(imodObject, imodContour);
            end
        end
    end
    Model = appendObject(Model, imodObject);
    if ~isempty(wb); if isa(wb,'matlab.ui.dialog.ProgressDialog'); wb.Value=objectLoop/noObjects; else; waitbar(objectLoop/noObjects,wb); end; end
end
write(Model, Options.modelFilename);
selection = permute(selection, [2 1 3]);
if ~isempty(wb)
    if ~isa(wb, 'matlab.ui.dialog.ProgressDialog'); set(0, 'DefaulttextInterpreter', curInt); end
    delete(wb);
end
end
